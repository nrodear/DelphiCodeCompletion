unit dpcc.Core.Signature.Providers.Server;

// Signaturen für den Parameter-Hint (#436) vom dpcc-Server
// (textDocument/signatureHelp, #32). Query holt die Sitzung und gleicht den
// Editortext im aufrufenden Thread ab und fragt im Hintergrund; das Ergebnis
// kommt per TDpccMainThread.Queue im Hauptthread an, aber nur für die jüngste
// Anfrage. Vor dem Freigeben der Sitzung Shutdown aufrufen: Es bricht ab, ohne
// zu warten (Stopp im Hauptthread); laufende Arbeiter zählt gRunningWorkers, und
// der Stopp-Thread der Sitzung wartet mit WaitWorkersIdle auf sie, bevor er die
// Sitzung freigibt. Destroy wartet auf alle Arbeiter (sie nutzen die Quelle).
// Die Sitzungsfunktion darf keinen Server starten.
// Abgleich ohne Zeitlimit-Arbeiter: Sync legt die Nachricht nur in die
// Eingabe-Pipe des Servers (TLspInProcessServer puffert im Speicher)
// und wartet nie auf den Server. Früher lief Sync mit 200 ms Zeitlimit, und
// drei Überschreitungen auf einem beschäftigten Rechner schalteten den
// Parameter-Hint ab, obwohl nichts kaputt war. Dauert der Abgleich trotzdem
// länger als TDpccTimeLimit.LimitMs, steht das als „langsam“ im Protokoll.
// Absturzsicherheit (#493): Fehler zählt die Sicherung der Quelle
// ProviderTitle, die nach 3 Fehlern in 5 Minuten nur den Parameter-Hint
// vom Server abschaltet. Server weg bzw. dessen Zeitlimit zählt nicht.
// Platzhalter (#451): "format" der Antwort kommt nach TDpccSignatureHelp.Format.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  System.Generics.Collections,
  dpcc.Core.Signature.Contract,
  dpcc.Core.Lsp.Session;

type
  TDpccSignatureCallback = dpcc.Core.Signature.Contract.TDpccSignatureCallback;

  TDpccServerSignatureProvider = class(TInterfacedObject, IDpccSignatureSource)
  public const
    cDefaultTimeoutMs = 2000;
  public
    /// <summary>Name der Quelle für die Sicherung (#493) und ihre Meldungen, in der Sprache der Oberfläche.
    /// </summary>
    class function ProviderTitle: string; static;
  private type
    /// <summary>Hält eingereihte Aufrufe davon ab, eine freigegebene Quelle zu benutzen.</summary>
    TAliveFlag = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;
  private
    FSession: TDpccSessionFunc;
    FTimeoutMs: Cardinal;
    FLock: TCriticalSection;
    FGeneration: Integer;
    FWorkers: TList<TThread>;
    FFlag: TAliveFlag;
    FFlagRef: IInterface;
    procedure ReapWorkers;
    /// <summary>Auf alle Arbeiter warten und sie freigeben (Destroy).</summary>
    procedure WaitAllWorkers;
    /// <summary>Sitzung holen und den Text abgleichen; False ohne Server.</summary>
    function SyncedSession(const AFileName, AText: string; out ASession: TLspSession): Boolean;
    /// <summary>Fragt im eigenen Thread an; APosition: X Zeichen, Y Zeile (0-basiert).</summary>
    procedure StartWorker(ASession: TLspSession; const AFileName: string; const APosition: TPoint;
      AGeneration: Integer; const ACallback: TDpccSignatureCallback);
  public
    constructor Create(const ASession: TDpccSessionFunc; ATimeoutMs: Cardinal); overload;
    /// <summary>Wie oben mit ATimeoutMs = DefaultTimeoutMs.</summary>
    constructor Create(const ASession: TDpccSessionFunc); overload;
    destructor Destroy; override;
    /// <summary>Fragt die Signaturen an ALine/ACharacter (0-basiert) an; ACallback im Hauptthread.
    /// False, wenn kein Server verfügbar ist.</summary>
    function Query(const AFileName, AText: string; ALine, ACharacter: Integer;
      const ACallback: TDpccSignatureCallback): Boolean;
    procedure Cancel;
    /// <summary>Bricht ab, ohne zu warten: Kein Rückruf mehr, beendete Arbeiter werden freigegeben, laufende erst
    /// später (spätestens Destroy). Vor dem Freigeben der Sitzung WaitWorkersIdle abwarten.</summary>
    procedure Shutdown;
    /// <summary>Laufende Arbeiter aller Signatur-Quellen.</summary>
    class function RunningWorkers: Integer; static;
    /// <summary>Bis zu AMs warten, bis kein Arbeiter mehr läuft; vorzeitig beim Abbruchsignal (TDpccShutdown). Nur
    /// im Hintergrund (Stopp-Thread der Sitzung). True, wenn keiner läuft.</summary>
    class function WaitWorkersIdle(AMs: Cardinal): Boolean; static;
    /// <summary>Antwort auf textDocument/signatureHelp.</summary>
    class function HelpFromLsp(AResponse: TJSONValue): TDpccSignatureHelp; static;
  end;

implementation

uses
  System.Diagnostics,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.TimeLimit,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Localization.Language,
  dpcc.Core.Diagnostics.Shutdown;

const
  /// <summary>Takt von WaitWorkersIdle (nur im Hintergrund).</summary>
  cWorkerPollMs = 10;

var
  /// <summary>Laufende Arbeiter aller Signatur-Quellen; gezählt vor dem Start, vermindert am Ende des Threads.
  /// </summary>
  gRunningWorkers: Integer;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TServerText = (ParameterHintServer);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TServerText] of string = (
    ('Parameter-Hint (Server)'),
    ('Parameter hint (server)'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TServerText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

{ TDpccServerSignatureProvider }

class function TDpccServerSignatureProvider.ProviderTitle: string;
begin
  Result := UiText(TServerText.ParameterHintServer);
end;

constructor TDpccServerSignatureProvider.Create(const ASession: TDpccSessionFunc);
begin
  Create(ASession, cDefaultTimeoutMs);
end;

constructor TDpccServerSignatureProvider.Create(const ASession: TDpccSessionFunc; ATimeoutMs: Cardinal);
begin
  inherited Create;
  FSession := ASession;
  FTimeoutMs := ATimeoutMs;
  FLock := TCriticalSection.Create;
  FWorkers := TList<TThread>.Create;
  FFlag := TAliveFlag.Create;
  FFlag.Alive := True;
  FFlagRef := FFlag;
end;

destructor TDpccServerSignatureProvider.Destroy;
begin
  // Die Arbeiter lesen FGeneration und FTimeoutMs dieser Quelle: hier ohne Grenze warten.
  Cancel;
  WaitAllWorkers;
  // Eingereihte Aufrufe halten den Merker selbst und sehen dann Alive = False.
  FFlag.Alive := False;
  FFlagRef := nil;
  FWorkers.Free;
  FLock.Free;
  inherited;
end;

function DocumentationText(AValue: TJSONValue): string;
begin
  // string oder MarkupContent.
  if AValue is TJSONString then
  begin
    Result := TJSONString(AValue).Value;
  end
  else if AValue is TJSONObject then
  begin
    Result := TJSONObject(AValue).GetValue<string>('value', '');
  end
  else
  begin
    Result := '';
  end;
end;

function RangeFromLsp(AValue: TJSONValue; out ARange: TDpccFormatRange): Boolean;
begin
  ARange := Default(TDpccFormatRange);
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<Integer>('start.line', ARange.StartLine) and
    TJSONObject(AValue).TryGetValue<Integer>('start.character', ARange.StartCharacter) and
    TJSONObject(AValue).TryGetValue<Integer>('end.line', ARange.EndLine) and
    TJSONObject(AValue).TryGetValue<Integer>('end.character', ARange.EndCharacter);
end;

/// <summary>Objekt "format" der Antwort (#451); Found = False ohne.</summary>
function PlaceholderFromLsp(AItem: TJSONObject): TDpccFormatPlaceholder;
var
  mTypeText: string;
begin
  Result := Default(TDpccFormatPlaceholder);
  Result.Text := AItem.GetValue<string>('text', '');
  mTypeText := AItem.GetValue<string>('type', '');
  if mTypeText <> '' then
  begin
    Result.TypeChar := mTypeText[1];
  end;
  Result.Valid := AItem.GetValue<Boolean>('valid', False);
  Result.Argument := AItem.GetValue<Integer>('argument', -1);
  Result.WidthArgument := AItem.GetValue<Integer>('width', -1);
  Result.PrecisionArgument := AItem.GetValue<Integer>('precision', -1);
  Result.HasRange := RangeFromLsp(AItem.GetValue('range'), Result.Range);
end;

function PlaceholdersFromLsp(AItems: TJSONValue): TArray<TDpccFormatPlaceholder>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AItems is TJSONArray then
  begin
    for mItem in TJSONArray(AItems) do
    begin
      if mItem is TJSONObject then
      begin
        Result := Result + [PlaceholderFromLsp(TJSONObject(mItem))];
      end;
    end;
  end;
end;

function ArgumentsFromLsp(AItems: TJSONValue): TArray<TDpccFormatRange>;
var
  mItem: TJSONValue;
  mRange: TDpccFormatRange;
begin
  Result := nil;
  if AItems is TJSONArray then
  begin
    for mItem in TJSONArray(AItems) do
    begin
      if not RangeFromLsp(mItem, mRange) then
      begin
        mRange := Default(TDpccFormatRange);
      end;
      Result := Result + [mRange];
    end;
  end;
end;

function ProblemKindOf(const AKind: string): TDpccFormatProblem;
begin
  if AKind = 'invalid' then
  begin
    Result := TDpccFormatProblem.Invalid;
  end
  else if AKind = 'tooManyArguments' then
  begin
    Result := TDpccFormatProblem.TooManyArguments;
  end
  else if AKind = 'typeConflict' then
  begin
    Result := TDpccFormatProblem.TypeConflict;
  end
  else
  begin
    Result := TDpccFormatProblem.None;
  end;
end;

function FormatFromLsp(AValue: TJSONValue): TDpccSignatureFormat;
var
  mObject, mProblem: TJSONObject;
begin
  Result := Default(TDpccSignatureFormat);
  Result.ActiveArgument := -1;
  Result.ProblemPlaceholder := -1;
  Result.ProblemArgument := -1;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mObject := TJSONObject(AValue);
  Result.Found := True;
  Result.FormatParameter := mObject.GetValue<Integer>('formatParameter', -1);
  Result.ListParameter := mObject.GetValue<Integer>('listParameter', -1);
  Result.ArgumentCount := mObject.GetValue<Integer>('argumentCount', -1);
  Result.ActiveArgument := mObject.GetValue<Integer>('activeArgument', -1);
  Result.Placeholders := PlaceholdersFromLsp(mObject.GetValue('placeholders'));
  Result.Arguments := ArgumentsFromLsp(mObject.GetValue('arguments'));
  if mObject.GetValue('problem') is TJSONObject then
  begin
    mProblem := TJSONObject(mObject.GetValue('problem'));
    Result.Problem := ProblemKindOf(mProblem.GetValue<string>('kind', ''));
    Result.ProblemPlaceholder := mProblem.GetValue<Integer>('placeholder', -1);
    Result.ProblemArgument := mProblem.GetValue<Integer>('argument', -1);
    Result.ProblemKind := mProblem.GetValue<string>('argumentKind', '');
  end;
end;

/// <summary>label des Parameters: [Start, Ende] im Signaturtext oder der Text selbst.</summary>
procedure ParameterRange(ALabel: TJSONValue; const ASignatureLabel: string;
  var AParameter: TDpccSignatureParameter);
var
  mPosition: Integer;
begin
  if (ALabel is TJSONArray) and (TJSONArray(ALabel).Count = 2) and
    (TJSONArray(ALabel).Items[0] is TJSONNumber) and (TJSONArray(ALabel).Items[1] is TJSONNumber) then
  begin
    AParameter.Start := TJSONNumber(TJSONArray(ALabel).Items[0]).AsInt;
    AParameter.Stop := TJSONNumber(TJSONArray(ALabel).Items[1]).AsInt;
  end
  else if ALabel is TJSONString then
  begin
    mPosition := Pos(TJSONString(ALabel).Value, ASignatureLabel);
    if mPosition > 0 then
    begin
      AParameter.Start := mPosition - 1;
      AParameter.Stop := AParameter.Start + Length(TJSONString(ALabel).Value);
    end;
  end;
end;

function ParametersFromLsp(AItems: TJSONValue; const ASignatureLabel: string): TArray<TDpccSignatureParameter>;
var
  mItem: TJSONValue;
  mParameter: TDpccSignatureParameter;
begin
  Result := nil;
  if not (AItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AItems) do
  begin
    if mItem is TJSONObject then
    begin
      mParameter := Default(TDpccSignatureParameter);
      mParameter.Start := -1;
      mParameter.Stop := -1;
      ParameterRange(TJSONObject(mItem).GetValue('label'), ASignatureLabel, mParameter);
      mParameter.Documentation := DocumentationText(TJSONObject(mItem).GetValue('documentation'));
      Result := Result + [mParameter];
    end;
  end;
end;

function SignatureFromLsp(AItem: TJSONObject): TDpccSignature;
var
  mData: TJSONValue;
begin
  Result := Default(TDpccSignature);
  Result.Label_ := AItem.GetValue<string>('label', '');
  Result.Documentation := DocumentationText(AItem.GetValue('documentation'));
  // Argumenttypen (#498): data.fits = false dämpft die Überladung.
  mData := AItem.GetValue('data');
  if (mData is TJSONObject) and (TJSONObject(mData).GetValue('fits') is TJSONBool) and
    not TJSONBool(TJSONObject(mData).GetValue('fits')).AsBoolean then
  begin
    Result.TypeMismatch := True;
    Result.MismatchArgument := TJSONObject(mData).GetValue<Integer>('mismatch', 0);
  end;
  Result.Parameters := ParametersFromLsp(AItem.GetValue('parameters'), Result.Label_);
end;

class function TDpccServerSignatureProvider.HelpFromLsp(AResponse: TJSONValue): TDpccSignatureHelp;
var
  mSignatures, mItem: TJSONValue;
begin
  Result := Default(TDpccSignatureHelp);
  Result.ActiveSignature := -1;
  Result.ActiveParameter := -1;
  if not (AResponse is TJSONObject) then
  begin
    Exit;
  end;
  Result.ActiveSignature := TJSONObject(AResponse).GetValue<Integer>('activeSignature', -1);
  Result.ActiveParameter := TJSONObject(AResponse).GetValue<Integer>('activeParameter', -1);
  Result.Format := FormatFromLsp(TJSONObject(AResponse).GetValue('format'));
  mSignatures := TJSONObject(AResponse).GetValue('signatures');
  if mSignatures is TJSONArray then
  begin
    for mItem in TJSONArray(mSignatures) do
    begin
      if mItem is TJSONObject then
      begin
        Result.Signatures := Result.Signatures + [SignatureFromLsp(TJSONObject(mItem))];
      end;
    end;
  end;
end;

procedure TDpccServerSignatureProvider.ReapWorkers;
var
  mIndex: Integer;
begin
  FLock.Enter;
  try
    for mIndex := FWorkers.Count - 1 downto 0 do
    begin
      if FWorkers[mIndex].Finished then
      begin
        FWorkers[mIndex].Free;
        FWorkers.Delete(mIndex);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccServerSignatureProvider.Cancel;
begin
  TInterlocked.Increment(FGeneration);
end;

procedure TDpccServerSignatureProvider.Shutdown;
begin
  // Ab hier ruft kein Arbeiter mehr zurück (Generation). Laufende bleiben in der Liste; der Stopp-Thread der Sitzung
  // wartet auf sie (WaitWorkersIdle), Destroy gibt sie frei.
  Cancel;
  ReapWorkers;
end;

procedure TDpccServerSignatureProvider.WaitAllWorkers;
var
  mWorkers: TArray<TThread>;
  mWorker: TThread;
begin
  FLock.Enter;
  try
    mWorkers := FWorkers.ToArray;
    FWorkers.Clear;
  finally
    FLock.Leave;
  end;
  for mWorker in mWorkers do
  begin
    mWorker.WaitFor;
    mWorker.Free;
  end;
end;

class function TDpccServerSignatureProvider.RunningWorkers: Integer;
begin
  Result := AtomicCmpExchange(gRunningWorkers, 0, 0);
end;

class function TDpccServerSignatureProvider.WaitWorkersIdle(AMs: Cardinal): Boolean;
var
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  Result := RunningWorkers <= 0;
  while not Result and (mWatch.ElapsedMilliseconds < AMs) and not TDpccShutdown.Signalled do
  begin
    TThread.Sleep(cWorkerPollMs);
    Result := RunningWorkers <= 0;
  end;
end;

function TDpccServerSignatureProvider.SyncedSession(const AFileName, AText: string;
  out ASession: TLspSession): Boolean;
var
  mWatch: TStopwatch;
begin
  // Sitzung holen und abgleichen im aufrufenden Thread: Sync wartet nicht auf den Server (siehe oben).
  ASession := nil;
  mWatch := TStopwatch.StartNew;
  try
    if Assigned(FSession) then
    begin
      ASession := FSession();
    end;
    if ASession <> nil then
    begin
      ASession.Sync(AFileName, AText);
    end;
  except
    // Server weg: kein Hint. Anderes zählt die Sicherung (#493).
    on E: Exception do
    begin
      ASession := nil;
      if not (E is ELspClientError) then
      begin
        TDpccGuard.ReportProvider(ProviderTitle, E);
      end;
    end;
  end;
  if mWatch.ElapsedMilliseconds > TDpccTimeLimit.LimitMs then
  begin
    TDpccGuard.ReportProviderSlow(ProviderTitle, Format('Abgleich dauerte %d ms', [mWatch.ElapsedMilliseconds]));
  end;
  Result := ASession <> nil;
end;

/// <summary>Signaturen vom Server; leer, wenn er weg ist oder das Zeitlimit greift.</summary>
function FetchHelp(ASession: TLspSession; const AFileName: string; const APosition: TPoint;
  ATimeoutMs: Cardinal): TDpccSignatureHelp;
var
  mResponse: TJSONValue;
begin
  Result := Default(TDpccSignatureHelp);
  try
    mResponse := ASession.SignatureHelp(AFileName, APosition.Y, APosition.X, ATimeoutMs);
    try
      Result := TDpccServerSignatureProvider.HelpFromLsp(mResponse);
    finally
      mResponse.Free;
    end;
  except
    // Anderes als ein Fehler des Clients zählt die Sicherung (#493).
    on E: Exception do
    begin
      Result := Default(TDpccSignatureHelp);
      if not (E is ELspClientError) then
      begin
        TDpccGuard.ReportProvider(TDpccServerSignatureProvider.ProviderTitle, E);
      end;
    end;
  end;
end;

procedure TDpccServerSignatureProvider.StartWorker(ASession: TLspSession; const AFileName: string;
  const APosition: TPoint; AGeneration: Integer; const ACallback: TDpccSignatureCallback);
var
  mWorker: TThread;
  mProvider: TDpccServerSignatureProvider;
  mFlag: TAliveFlag;
  mFlagRef: IInterface;
  mFileName: string;
  mPosition: TPoint;
begin
  mProvider := Self;
  mFlag := FFlag;
  mFlagRef := FFlagRef;
  mFileName := AFileName;
  mPosition := APosition;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      mHelp: TDpccSignatureHelp;
    begin
      try
        mHelp := FetchHelp(ASession, mFileName, mPosition, mProvider.FTimeoutMs);
        if TInterlocked.CompareExchange(mProvider.FGeneration, 0, 0) <> AGeneration then
        begin
          Exit;
        end;
        // Im Hauptthread erst prüfen, ob die Quelle noch lebt und dies die jüngste Anfrage ist.
        TDpccMainThread.Queue(TDpccFeature.Signature,
          procedure
          begin
            if mFlag.Alive and (mFlagRef <> nil) and
              (TInterlocked.CompareExchange(mProvider.FGeneration, 0, 0) = AGeneration) then
            begin
              TDpccGuard.Run(TDpccFeature.Signature,
                procedure
                begin
                  ACallback(mHelp);
                end);
            end;
          end);
      finally
        AtomicDecrement(gRunningWorkers);
      end;
    end);
  mWorker.FreeOnTerminate := False;
  FLock.Enter;
  try
    FWorkers.Add(mWorker);
    // Vor dem Start gezählt: Der Stopp der Sitzung sieht den Arbeiter, bevor er die Sitzung freigibt.
    AtomicIncrement(gRunningWorkers);
  finally
    FLock.Leave;
  end;
  try
    mWorker.Start;
  except
    AtomicDecrement(gRunningWorkers);
    raise;
  end;
end;
function TDpccServerSignatureProvider.Query(const AFileName, AText: string; ALine, ACharacter: Integer;
  const ACallback: TDpccSignatureCallback): Boolean;
var
  mSession: TLspSession;
  mGeneration: Integer;
begin
  mGeneration := TInterlocked.Increment(FGeneration);
  ReapWorkers;
  Result := False;
  if (AFileName = '') or TDpccGuard.ProviderDisabled(ProviderTitle) then
  begin
    Exit;
  end;
  Result := SyncedSession(AFileName, AText, mSession);
  if Result then
  begin
    StartWorker(mSession, AFileName, TPoint.Create(ACharacter, ALine), mGeneration, ACallback);
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Signature.Providers.Server', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
