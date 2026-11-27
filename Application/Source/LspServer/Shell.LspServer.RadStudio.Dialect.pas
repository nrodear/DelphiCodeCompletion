unit Shell.LspServer.RadStudio.Dialect;

// Host-Rolle Shell, nur in dpcc.LspServer.exe: Übersetzer zwischen dem Server und dem LSP-Dialekt der RAD-Studio-IDE
// als Transport um den eigentlichen Transport (stdin/stdout). Er liest initialize mit; meldet sich der Client als
// "RAD Studio" (clientInfo.name), gilt bis zum Ende der Verbindung der Dialekt, für alle anderen Clients bleibt alles
// Standard-LSP (nur documentSymbolProvider kommt in den Capabilities dazu).
// Dialekt (gemessen am 26.11.2026 an DelphiLSP in Delphi 12 und 13, Mitschnitte des Machbarkeitsversuchs):
// - initialize: Capabilities wie DelphiLSP (textDocumentSync 1 = ganzer Text, completion mit resolve und den
//   Auslösezeichen . ( < [, signatureHelp mit ( , <), aber nur, was der Server kann: definition, declaration,
//   typeDefinition, documentSymbol, hover. Keine implementation, keine Diagnosen.
// - textDocument/completion: {"isIncomplete", "kibitzkind": 2, "items": [{label, kind, detail, DCC_Flags,
//   sortText}]}. detail wie DelphiLSP hinter dem Namen: ": Integer;" (Feld, Variable, Property),
//   "(const A: Integer): Integer;" bzw. ";" (Routinen). DCC_Flags (Bits gemessen): 0x13 Feld/Variable,
//   0x34 Prozedur, 0x35 Funktion, +0x200 virtual, +0x400 protected, +0x20000 Konstruktor, +0x40000 Destruktor,
//   +0x800000 Klassenmethode, +0x4000000 overload, +0x10000000 deprecated, 0x8018 Property. Für Typen, Konstanten,
//   Units und Schlüsselwörter ist kein Wert gemessen; sie bekommen keinen. Einträge, die zusätzliche Änderungen
//   brauchen (uses ergänzen, Vorlagen, Befehle), fehlen: Die IDE übernähme nur den Namen.
// - completionItem/resolve: kind und insertTextFormat kommen als Zeichenketten; data fehlt. Der Übersetzer setzt den
//   Eintrag der letzten Liste (über sortText und label) wieder ein und antwortet im Format der Liste mit
//   documentation als Klartext.
// - textDocument/signatureHelp: Die IDE zeigt die Hilfe nur, wenn documentation in der Signatur und in jedem
//   Parameter steht; Parameter mit label als Text (nicht als Bereich). Signatur: {"kind": "html", "value": …},
//   Parameter: {"kind": "xml", "value": …} wie DelphiLSP.
// - textDocument/hover: contents als einfacher String (Klartext), ohne die dpcc-Teile. Das Format ist nicht gemessen
//   ("Hover-Modell", returnHoverModel); HoverAnswer ist die eine Stelle, an der es sich ändern lässt.
// - Benachrichtigungen und Anfragen des Servers an den Client (window/logMessage, $/progress, dpcc/…) gehen nicht an
//   die IDE; sie kennt sie nicht.
// Threadsicher: WriteMessage kommt aus Worker-Threads, ReadMessage nur aus dem Lese-Thread der Verbindung.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.JSON,
  System.Generics.Collections,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.Index.Contract;

type
  /// <summary>Sucht die Deklaration an ALine/ACharacter (Namensposition) in AFileName; False ohne Treffer.</summary>
  TRadSymbolLookup = reference to function(const AFileName: string; ALine, ACharacter: Integer;
    out ASymbol: TIndexSymbol): Boolean;
  /// <summary>Nach initialize: Name des Clients und processId (0 ohne).</summary>
  TRadInitializeEvent = reference to procedure(const AClientName: string; AProcessId: Cardinal);

  TRadStudioDialect = class(TInterfacedObject, IJsonRpcTransport)
  public const
    cClientName = 'RAD Studio';
    cKibitzKind = 2;
  private
    FInner: IJsonRpcTransport;
    FLock: TCriticalSection;
    FActive: Boolean;
    FDecided: Boolean;
    /// <summary>Methode je offener Anfrage des Clients (id als JSON-Text).</summary>
    FPending: TDictionary<string, string>;
    /// <summary>Einträge der letzten Vervollständigung (sortText + #1 + label → Eintrag des Servers).</summary>
    FLastItems: TObjectDictionary<string, TJSONObject>;
    FLookup: TRadSymbolLookup;
    FOnInitialize: TRadInitializeEvent;
    FDropped: Integer;
    function GetActive: Boolean;
    procedure NoteInitialize(AMessage: TJSONObject);
    procedure FixResolveParams(AMessage: TJSONObject);
    function TakeMethod(const AId: TJSONValue): string;
    function Transform(const AMethod: string; AResult: TJSONValue): TJSONValue;
    function CompletionAnswer(AResult: TJSONValue): TJSONValue;
    function ResolveAnswer(AResult: TJSONValue): TJSONValue;
    function RadItem(AItem: TJSONObject; AWithDocumentation: Boolean): TJSONObject;
    procedure RememberItems(AItems: TJSONArray);
  public
    constructor Create(const AInner: IJsonRpcTransport);
    destructor Destroy; override;
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
    /// <summary>Capabilities für die IDE aus denen des Servers (nur, was er kann); der Aufrufer übernimmt sie.
    /// </summary>
    class function RadCapabilities(const AServer: TJSONObject): TJSONObject; static;
    /// <summary>Hover im Format der IDE aus der Antwort des Servers; der Aufrufer übernimmt es.</summary>
    class function HoverAnswer(AResult: TJSONValue): TJSONValue; static;
    /// <summary>Parameterhilfe im Format der IDE; der Aufrufer übernimmt sie.</summary>
    class function SignatureAnswer(AResult: TJSONValue): TJSONValue; static;
    /// <summary>detail wie DelphiLSP aus der Deklaration ASymbol.</summary>
    class function DetailOf(const ASymbol: TIndexSymbol): string; static;
    /// <summary>DCC_Flags zu ASymbol; False, wenn für die Art kein Wert gemessen ist.</summary>
    class function DccFlagsOf(const ASymbol: TIndexSymbol; out AFlags: Int64): Boolean; static;
    /// <summary>Markdown grob als Klartext (Backticks, Sternchen, Rauten am Zeilenanfang, Trennlinien).</summary>
    class function PlainOf(const AMarkdown: string): string; static;
    /// <summary>Der Client ist RAD Studio (nach initialize).</summary>
    property Active: Boolean read GetActive;
    /// <summary>Verworfene Nachrichten des Servers an die IDE.</summary>
    property Dropped: Integer read FDropped;
    property Lookup: TRadSymbolLookup read FLookup write FLookup;
    property OnInitialize: TRadInitializeEvent read FOnInitialize write FOnInitialize;
  end;

implementation

uses
  System.StrUtils,
  dpcc.Common.Documents.Uris;

function IdKey(const AId: TJSONValue): string;
begin
  Result := '';
  if AId <> nil then
  begin
    Result := AId.ToJSON;
  end;
end;

/// <summary>Zeichenkette wie "2" als Zahl ersetzen (completionItem/resolve der IDE).</summary>
procedure NumberFromString(AObject: TJSONObject; const AName: string);
var
  mValue: TJSONValue;
  mNumber: Integer;
begin
  mValue := AObject.GetValue(AName);
  if (mValue is TJSONString) and not (mValue is TJSONNumber) and TryStrToInt(Trim(mValue.Value), mNumber) then
  begin
    AObject.RemovePair(AName).Free;
    AObject.AddPair(AName, TJSONNumber.Create(mNumber));
  end;
end;

function HtmlEscape(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '<br>', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '<br>', [rfReplaceAll]);
end;

/// <summary>Text aus documentation (String oder MarkupContent); '' ohne.</summary>
function DocumentationText(AValue: TJSONValue): string;
begin
  Result := '';
  if AValue is TJSONObject then
  begin
    Result := TJSONObject(AValue).GetValue<string>('value', '');
    if SameText(TJSONObject(AValue).GetValue<string>('kind', ''), 'markdown') then
    begin
      Result := TRadStudioDialect.PlainOf(Result);
    end;
  end
  else if (AValue is TJSONString) and not (AValue is TJSONNumber) then
  begin
    Result := AValue.Value;
  end;
end;

{ TRadStudioDialect }

constructor TRadStudioDialect.Create(const AInner: IJsonRpcTransport);
begin
  inherited Create;
  FInner := AInner;
  FLock := TCriticalSection.Create;
  FPending := TDictionary<string, string>.Create;
  FLastItems := TObjectDictionary<string, TJSONObject>.Create([doOwnsValues]);
end;

destructor TRadStudioDialect.Destroy;
begin
  FLastItems.Free;
  FPending.Free;
  FLock.Free;
  FInner := nil;
  inherited;
end;

function TRadStudioDialect.GetActive: Boolean;
begin
  FLock.Enter;
  try
    Result := FActive;
  finally
    FLock.Leave;
  end;
end;

procedure TRadStudioDialect.NoteInitialize(AMessage: TJSONObject);
var
  mParams: TJSONObject;
  mName: string;
  mProcessId: Int64;
  mValue: TJSONValue;
begin
  mName := '';
  mProcessId := 0;
  if AMessage.GetValue('params') is TJSONObject then
  begin
    mParams := TJSONObject(AMessage.GetValue('params'));
    mName := mParams.GetValue<string>('clientInfo.name', '');
    mValue := mParams.GetValue('processId');
    if mValue is TJSONNumber then
    begin
      mProcessId := TJSONNumber(mValue).AsInt64;
    end;
  end;
  FLock.Enter;
  try
    if not FDecided then
    begin
      FDecided := True;
      FActive := SameText(Trim(mName), cClientName);
    end;
  finally
    FLock.Leave;
  end;
  if Assigned(FOnInitialize) then
  begin
    if (mProcessId < 0) or (mProcessId > High(Cardinal)) then
    begin
      mProcessId := 0;
    end;
    FOnInitialize(mName, Cardinal(mProcessId));
  end;
end;

procedure TRadStudioDialect.FixResolveParams(AMessage: TJSONObject);
var
  mParams, mOriginal: TJSONObject;
  mKey: string;
begin
  if not (AMessage.GetValue('params') is TJSONObject) then
  begin
    Exit;
  end;
  mParams := TJSONObject(AMessage.GetValue('params'));
  NumberFromString(mParams, 'kind');
  NumberFromString(mParams, 'insertTextFormat');
  // Die IDE schickt den Eintrag ohne data zurück: den Eintrag des Servers einsetzen.
  mKey := mParams.GetValue<string>('sortText', '') + #1 + mParams.GetValue<string>('label', '');
  FLock.Enter;
  try
    if FLastItems.TryGetValue(mKey, mOriginal) then
    begin
      AMessage.RemovePair('params').Free;
      AMessage.AddPair('params', TJSONObject(mOriginal.Clone));
    end;
  finally
    FLock.Leave;
  end;
end;

function TRadStudioDialect.ReadMessage: TJSONObject;
var
  mMethod: string;
  mId: TJSONValue;
begin
  Result := FInner.ReadMessage;
  try
    mMethod := Result.GetValue<string>('method', '');
    mId := Result.GetValue('id');
    if mMethod = 'initialize' then
    begin
      NoteInitialize(Result);
    end;
    if (mMethod <> '') and (mId <> nil) then
    begin
      FLock.Enter;
      try
        FPending.AddOrSetValue(IdKey(mId), mMethod);
      finally
        FLock.Leave;
      end;
    end;
    if Active and (mMethod = 'completionItem/resolve') then
    begin
      FixResolveParams(Result);
    end;
  except
    // Eine unerwartete Form darf die Nachricht nicht verlieren: unverändert weiter.
    on Exception do
      ;
  end;
end;

function TRadStudioDialect.TakeMethod(const AId: TJSONValue): string;
var
  mKey: string;
begin
  Result := '';
  mKey := IdKey(AId);
  FLock.Enter;
  try
    if FPending.TryGetValue(mKey, Result) then
    begin
      FPending.Remove(mKey);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TRadStudioDialect.WriteMessage(const AMessage: TJSONObject);
var
  mMethod: string;
  mResult, mNew: TJSONValue;
  mCopy: TJSONObject;
begin
  if AMessage.GetValue('method') <> nil then
  begin
    // Benachrichtigung oder Anfrage des Servers: Die IDE kennt sie nicht.
    if Active then
    begin
      TInterlocked.Increment(FDropped);
      Exit;
    end;
    FInner.WriteMessage(AMessage);
    Exit;
  end;
  mMethod := TakeMethod(AMessage.GetValue('id'));
  mResult := AMessage.GetValue('result');
  if (mResult = nil) or ((mMethod <> 'initialize') and not Active) then
  begin
    FInner.WriteMessage(AMessage);
    Exit;
  end;
  mNew := nil;
  try
    mNew := Transform(mMethod, mResult);
  except
    // Lieber die Antwort des Servers als keine.
    on Exception do
      FreeAndNil(mNew);
  end;
  if mNew = nil then
  begin
    FInner.WriteMessage(AMessage);
    Exit;
  end;
  mCopy := TJSONObject.Create;
  try
    mCopy.AddPair('jsonrpc', '2.0');
    mCopy.AddPair('id', TJSONValue(AMessage.GetValue('id').Clone));
    mCopy.AddPair('result', mNew);
    FInner.WriteMessage(mCopy);
  finally
    mCopy.Free;
  end;
end;

function TRadStudioDialect.Transform(const AMethod: string; AResult: TJSONValue): TJSONValue;
var
  mCaps: TJSONObject;
  mResult: TJSONObject;
begin
  Result := nil;
  if AMethod = 'initialize' then
  begin
    if not (AResult is TJSONObject) or not (TJSONObject(AResult).GetValue('capabilities') is TJSONObject) then
    begin
      Exit;
    end;
    mResult := TJSONObject(AResult.Clone);
    try
      if Active then
      begin
        mCaps := RadCapabilities(TJSONObject(TJSONObject(AResult).GetValue('capabilities')));
      end
      else
      begin
        mCaps := TJSONObject(TJSONObject(AResult).GetValue('capabilities').Clone);
        if mCaps.GetValue('documentSymbolProvider') = nil then
        begin
          mCaps.AddPair('documentSymbolProvider', TJSONBool.Create(True));
        end;
      end;
      mResult.RemovePair('capabilities').Free;
      mResult.AddPair('capabilities', mCaps);
    except
      mResult.Free;
      raise;
    end;
    Exit(mResult);
  end;
  if AMethod = 'textDocument/completion' then
  begin
    Result := CompletionAnswer(AResult);
  end
  else if AMethod = 'completionItem/resolve' then
  begin
    Result := ResolveAnswer(AResult);
  end
  else if AMethod = 'textDocument/signatureHelp' then
  begin
    Result := SignatureAnswer(AResult);
  end
  else if AMethod = 'textDocument/hover' then
  begin
    Result := HoverAnswer(AResult);
  end;
end;

class function TRadStudioDialect.RadCapabilities(const AServer: TJSONObject): TJSONObject;
var
  mTriggers: TJSONArray;
  mCompletion, mSignature: TJSONObject;
  mName: string;
begin
  Result := TJSONObject.Create;
  // Ganzer Text bei jeder Änderung, wie die IDE ohnehin schickt.
  Result.AddPair('textDocumentSync', TJSONNumber.Create(1));
  for mName in TArray<string>.Create('definitionProvider', 'declarationProvider', 'typeDefinitionProvider') do
  begin
    if AServer.GetValue(mName) <> nil then
    begin
      Result.AddPair(mName, TJSONBool.Create(True));
    end;
  end;
  Result.AddPair('documentSymbolProvider', TJSONBool.Create(True));
  if AServer.GetValue('hoverProvider') <> nil then
  begin
    Result.AddPair('hoverProvider', TJSONBool.Create(True));
  end;
  if AServer.GetValue('completionProvider') <> nil then
  begin
    mCompletion := TJSONObject.Create;
    mCompletion.AddPair('resolveProvider', TJSONBool.Create(True));
    mTriggers := TJSONArray.Create;
    mTriggers.Add('.').Add('(').Add('<').Add('[');
    mCompletion.AddPair('triggerCharacters', mTriggers);
    Result.AddPair('completionProvider', mCompletion);
  end;
  if AServer.GetValue('signatureHelpProvider') <> nil then
  begin
    mSignature := TJSONObject.Create;
    mTriggers := TJSONArray.Create;
    mTriggers.Add('(').Add(',').Add('<');
    mSignature.AddPair('triggerCharacters', mTriggers);
    Result.AddPair('signatureHelpProvider', mSignature);
  end;
end;

class function TRadStudioDialect.PlainOf(const AMarkdown: string): string;
var
  mLines: TArray<string>;
  mLine, mText: string;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mLines := StringReplace(AMarkdown, #13#10, #10, [rfReplaceAll]).Split([#10]);
    for mLine in mLines do
    begin
      mText := mLine;
      if StartsStr('```', Trim(mText)) or (Trim(mText) = '---') then
      begin
        Continue;
      end;
      while StartsStr('#', mText) do
      begin
        mText := Copy(mText, 2, MaxInt);
      end;
      mText := StringReplace(mText, '**', '', [rfReplaceAll]);
      mText := StringReplace(mText, '`', '', [rfReplaceAll]);
      mText := StringReplace(mText, '\_', '_', [rfReplaceAll]);
      if mBuilder.Length > 0 then
      begin
        mBuilder.Append(#13#10);
      end;
      mBuilder.Append(TrimLeft(mText));
    end;
    Result := Trim(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

class function TRadStudioDialect.HoverAnswer(AResult: TJSONValue): TJSONValue;
var
  mContents: TJSONValue;
  mText: string;
  mItem: TJSONValue;
begin
  if not (AResult is TJSONObject) then
  begin
    // null: kein Hover.
    Exit(nil);
  end;
  mContents := TJSONObject(AResult).GetValue('contents');
  mText := '';
  if mContents is TJSONArray then
  begin
    for mItem in TJSONArray(mContents) do
    begin
      if mText <> '' then
      begin
        mText := mText + #13#10;
      end;
      mText := mText + DocumentationText(mItem);
    end;
  end
  else
  begin
    mText := DocumentationText(mContents);
  end;
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('contents', mText);
end;

class function TRadStudioDialect.SignatureAnswer(AResult: TJSONValue): TJSONValue;
var
  mSignatures, mParameters, mNewSignatures, mNewParameters: TJSONArray;
  mSignature, mParameter, mNewSignature, mNewParameter, mDoc: TJSONObject;
  mSignatureValue, mParameterValue, mLabelValue: TJSONValue;
  mLabel, mParamLabel: string;
  mStart, mEnd: Integer;
begin
  if not (AResult is TJSONObject) or not TJSONObject(AResult).TryGetValue<TJSONArray>('signatures', mSignatures) then
  begin
    Exit(nil);
  end;
  Result := TJSONObject.Create;
  try
    mNewSignatures := TJSONArray.Create;
    TJSONObject(Result).AddPair('signatures', mNewSignatures);
    for mSignatureValue in mSignatures do
    begin
      if not (mSignatureValue is TJSONObject) then
      begin
        Continue;
      end;
      mSignature := TJSONObject(mSignatureValue);
      mLabel := mSignature.GetValue<string>('label', '');
      mNewSignature := TJSONObject.Create;
      mNewSignatures.AddElement(mNewSignature);
      mNewSignature.AddPair('label', mLabel);
      // Ohne documentation zeigt die IDE die Hilfe nicht an.
      mDoc := TJSONObject.Create;
      mDoc.AddPair('kind', 'html');
      mDoc.AddPair('value', '<html><body>' + HtmlEscape(DocumentationText(mSignature.GetValue('documentation'))) +
        '</body></html>');
      mNewSignature.AddPair('documentation', mDoc);
      mNewParameters := TJSONArray.Create;
      mNewSignature.AddPair('parameters', mNewParameters);
      if not mSignature.TryGetValue<TJSONArray>('parameters', mParameters) then
      begin
        Continue;
      end;
      for mParameterValue in mParameters do
      begin
        if not (mParameterValue is TJSONObject) then
        begin
          Continue;
        end;
        mParameter := TJSONObject(mParameterValue);
        mLabelValue := mParameter.GetValue('label');
        mParamLabel := '';
        if (mLabelValue is TJSONArray) and (TJSONArray(mLabelValue).Count = 2) then
        begin
          // Bereich [Anfang, Ende) im Label der Signatur.
          mStart := TJSONArray(mLabelValue).Items[0].GetValue<Integer>;
          mEnd := TJSONArray(mLabelValue).Items[1].GetValue<Integer>;
          mParamLabel := Copy(mLabel, mStart + 1, mEnd - mStart);
        end
        else if mLabelValue <> nil then
        begin
          mParamLabel := mLabelValue.Value;
        end;
        mNewParameter := TJSONObject.Create;
        mNewParameters.AddElement(mNewParameter);
        mNewParameter.AddPair('label', mParamLabel);
        mDoc := TJSONObject.Create;
        mDoc.AddPair('kind', 'xml');
        mDoc.AddPair('value', DocumentationText(mParameter.GetValue('documentation')));
        mNewParameter.AddPair('documentation', mDoc);
      end;
    end;
    TJSONObject(Result).AddPair('activeSignature',
      TJSONNumber.Create(TJSONObject(AResult).GetValue<Integer>('activeSignature', 0)));
    TJSONObject(Result).AddPair('activeParameter',
      TJSONNumber.Create(TJSONObject(AResult).GetValue<Integer>('activeParameter', 0)));
  except
    Result.Free;
    raise;
  end;
end;

/// <summary>Teil der Signatur hinter dem Namen bis zum ersten ";" außerhalb von Klammern, z. B.
/// "(const A: Integer): Integer"; '' ohne Namen.</summary>
function AfterName(const ASignature, AName: string): string;
var
  mUpper, mName: string;
  mPos, mIndex, mDepth: Integer;
  mFound: Boolean;
begin
  Result := '';
  mUpper := UpperCase(ASignature);
  mName := UpperCase(AName);
  mPos := Pos(mName, mUpper);
  mFound := False;
  while mPos > 0 do
  begin
    // Ganzes Wort: davor kein Buchstabe, dahinter keiner.
    if ((mPos = 1) or not CharInSet(mUpper[mPos - 1], ['A'..'Z', '0'..'9', '_', '.'])) and
      ((mPos + Length(mName) > Length(mUpper)) or not CharInSet(mUpper[mPos + Length(mName)], ['A'..'Z', '0'..'9',
      '_'])) then
    begin
      mFound := True;
      Break;
    end;
    mPos := PosEx(mName, mUpper, mPos + 1);
  end;
  if not mFound then
  begin
    Exit;
  end;
  mIndex := mPos + Length(mName);
  mDepth := 0;
  while mIndex <= Length(ASignature) do
  begin
    case ASignature[mIndex] of
      '(', '[', '<':
        Inc(mDepth);
      ')', ']', '>':
        Dec(mDepth);
      ';':
        if mDepth <= 0 then
        begin
          Break;
        end;
    end;
    Result := Result + ASignature[mIndex];
    Inc(mIndex);
  end;
  Result := Trim(Result);
  // Generische Parameter des Namens (Foo<T>(…)) bleiben vorn stehen.
end;

class function TRadStudioDialect.DetailOf(const ASymbol: TIndexSymbol): string;
var
  mRest: string;
begin
  case ASymbol.Kind of
    TIndexSymbolKind.Field, TIndexSymbolKind.Variable, TIndexSymbolKind.Property_, TIndexSymbolKind.Constant:
      if ASymbol.TypeName <> '' then
      begin
        Result := ': ' + ASymbol.TypeName + ';';
      end
      else
      begin
        Result := ';';
      end;
    TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine:
      begin
        mRest := AfterName(ASymbol.Signature, ASymbol.Name);
        if mRest = '' then
        begin
          Result := ';';
        end
        else if StartsStr(':', mRest) then
        begin
          Result := mRest + ';';
        end
        else
        begin
          Result := mRest + ';';
        end;
      end;
  else
    Result := '';
  end;
end;

class function TRadStudioDialect.DccFlagsOf(const ASymbol: TIndexSymbol; out AFlags: Int64): Boolean;
begin
  AFlags := 0;
  Result := True;
  case ASymbol.Kind of
    TIndexSymbolKind.Field, TIndexSymbolKind.Variable:
      AFlags := $13;
    TIndexSymbolKind.Property_:
      AFlags := $8018;
    TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine:
      begin
        if ASymbol.TypeName <> '' then
        begin
          AFlags := $35;
        end
        else
        begin
          AFlags := $34;
        end;
        if ASymbol.Kind = TIndexSymbolKind.Constructor_ then
        begin
          AFlags := AFlags or $20000;
        end;
        if ASymbol.HasDirective('destructor') or StartsText('destructor', TrimLeft(ASymbol.Signature)) then
        begin
          AFlags := AFlags or $40000;
        end;
        if StartsText('class ', TrimLeft(ASymbol.Signature)) then
        begin
          AFlags := AFlags or $800000;
        end;
        if ASymbol.IsVirtual or ASymbol.HasDirective('virtual') or ASymbol.HasDirective('override') or
          ASymbol.HasDirective('dynamic') then
        begin
          AFlags := AFlags or $200;
        end;
        if ASymbol.HasDirective('overload') then
        begin
          AFlags := AFlags or $4000000;
        end;
      end;
  else
    Exit(False);
  end;
  if ASymbol.HasDirective('deprecated') then
  begin
    AFlags := AFlags or $10000000;
  end;
  if ASymbol.Visibility in [TIndexVisibility.Protected, TIndexVisibility.StrictProtected] then
  begin
    AFlags := AFlags or $400;
  end;
end;

function TRadStudioDialect.RadItem(AItem: TJSONObject; AWithDocumentation: Boolean): TJSONObject;
var
  mData: TJSONObject;
  mSymbol: TIndexSymbol;
  mFound: Boolean;
  mFlags: Int64;
  mDetail, mFile, mDoc: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('label', AItem.GetValue<string>('label', ''));
  Result.AddPair('kind', TJSONNumber.Create(AItem.GetValue<Integer>('kind', 1)));
  mDetail := AItem.GetValue<string>('detail', '');
  mFound := False;
  if Assigned(FLookup) and (AItem.GetValue('data') is TJSONObject) then
  begin
    mData := TJSONObject(AItem.GetValue('data'));
    mFile := mData.GetValue<string>('file', '');
    if mFile <> '' then
    begin
      try
        mFound := FLookup(mFile, mData.GetValue<Integer>('line', -1), mData.GetValue<Integer>('character', -1),
          mSymbol);
      except
        // Ohne Deklaration bleibt das detail des Servers.
        on Exception do
          mFound := False;
      end;
    end;
  end;
  if mFound then
  begin
    mDetail := DetailOf(mSymbol);
  end;
  Result.AddPair('detail', mDetail);
  if mFound and DccFlagsOf(mSymbol, mFlags) then
  begin
    Result.AddPair('DCC_Flags', TJSONNumber.Create(mFlags));
  end;
  Result.AddPair('sortText', AItem.GetValue<string>('sortText', ''));
  if AItem.GetValue('insertText') <> nil then
  begin
    // Bezeichner mit &: im Quelltext mit Escape.
    Result.AddPair('insertText', AItem.GetValue<string>('insertText', ''));
  end;
  if AWithDocumentation then
  begin
    mDoc := DocumentationText(AItem.GetValue('documentation'));
    if mDoc <> '' then
    begin
      Result.AddPair('documentation', mDoc);
    end;
  end;
end;

/// <summary>Braucht der Eintrag mehr als seinen Namen (Änderungen, Vorlage, Befehl)?</summary>
function NeedsEdits(AItem: TJSONObject): Boolean;
var
  mEdits: TJSONArray;
begin
  Result := (AItem.GetValue('textEdit') <> nil) or (AItem.GetValue('command') <> nil) or
    (AItem.GetValue<Integer>('insertTextFormat', 1) = 2) or
    (AItem.TryGetValue<TJSONArray>('additionalTextEdits', mEdits) and (mEdits.Count > 0));
end;

procedure TRadStudioDialect.RememberItems(AItems: TJSONArray);
var
  mItem: TJSONValue;
  mKey: string;
begin
  FLock.Enter;
  try
    FLastItems.Clear;
    for mItem in AItems do
    begin
      if mItem is TJSONObject then
      begin
        mKey := TJSONObject(mItem).GetValue<string>('sortText', '') + #1 +
          TJSONObject(mItem).GetValue<string>('label', '');
        FLastItems.AddOrSetValue(mKey, TJSONObject(mItem.Clone));
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TRadStudioDialect.CompletionAnswer(AResult: TJSONValue): TJSONValue;
var
  mItems, mNewItems: TJSONArray;
  mItem: TJSONValue;
  mIncomplete: Boolean;
begin
  mIncomplete := False;
  if AResult is TJSONArray then
  begin
    mItems := TJSONArray(AResult);
  end
  else if (AResult is TJSONObject) and TJSONObject(AResult).TryGetValue<TJSONArray>('items', mItems) then
  begin
    mIncomplete := TJSONObject(AResult).GetValue<Boolean>('isIncomplete', False);
  end
  else
  begin
    mItems := nil;
  end;
  Result := TJSONObject.Create;
  try
    TJSONObject(Result).AddPair('isIncomplete', TJSONBool.Create(mIncomplete));
    TJSONObject(Result).AddPair('kibitzkind', TJSONNumber.Create(cKibitzKind));
    mNewItems := TJSONArray.Create;
    TJSONObject(Result).AddPair('items', mNewItems);
    if mItems = nil then
    begin
      Exit;
    end;
    RememberItems(mItems);
    for mItem in mItems do
    begin
      if (mItem is TJSONObject) and not NeedsEdits(TJSONObject(mItem)) then
      begin
        mNewItems.AddElement(RadItem(TJSONObject(mItem), False));
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TRadStudioDialect.ResolveAnswer(AResult: TJSONValue): TJSONValue;
begin
  if not (AResult is TJSONObject) then
  begin
    Exit(nil);
  end;
  Result := RadItem(TJSONObject(AResult), True);
end;

end.
