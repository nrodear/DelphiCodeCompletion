unit dpcc.IDE.Hover.DebugValue;

// Variablenwert im Hover beim Debuggen (#891) über den Debugger der IDE:
//   - Nur bei angehaltenem Prozess (psStopped, psFault, psException).
//   - IOTAThread.Evaluate (Überladung aus IOTAThread90) im Kontext von Datei und
//     Zeile, ohne Nebenwirkungen (eseNone): Die Auswertung ruft nichts im
//     Programm auf.
//   - Antwortet der Debugger verzögert (erDeferred, Win64/LLDB), meldet
//     IOTAThreadNotifier.EvaluateComplete den Wert später. Die IDE wartet nie in
//     einer Schleife darauf; das Ergebnis geht über TDpccMainThread an den
//     Rückruf, der Notifier wird erst danach im Hauptthread abgemeldet.
//   - Eine neue Auswertung oder Cancel verwirft die laufende.
//   - Fenster „Auswerten“ (#784): Auswerten auf Wunsch mit Nebenwirkungen
//     (eseAll, Funktionsaufrufe erlaubt) und Ändern über IOTAThread.Modify,
//     das sich auf den zuletzt ausgewerteten Ausdruck bezieht.

interface

uses
  System.SysUtils,
  ToolsAPI,
  dpcc.Core.Hover.DebugValue;

type
  /// <summary>Ergebnis einer verzögerten Auswertung; läuft im Hauptthread.</summary>
  TDpccDebugValueEvent = reference to procedure(const AValue: TDpccDebugValue);

  TDpccIdeDebugValues = class
  private type
    TDeferred = class(TNotifierObject, IOTAThreadNotifier, IOTAThreadNotifier160)
    private
      FOwner: TDpccIdeDebugValues;
      FExpression: string;
      FOnDone: TDpccDebugValueEvent;
      FDone: Boolean;
      FThreadGone: Boolean;
      procedure Complete(const AResult: string; AReturnCode: Integer);
    public
      constructor Create(AOwner: TDpccIdeDebugValues; const AExpression: string;
        const AOnDone: TDpccDebugValueEvent);
      { IOTAThreadNotifier }
      procedure ThreadNotify(Reason: TOTANotifyReason);
      procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
        ResultAddress, ResultSize: LongWord; ReturnCode: Integer); overload;
      procedure ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
      { IOTAThreadNotifier160 }
      procedure EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
        ResultAddress: TOTAAddress; ResultSize: LongWord; ReturnCode: Integer); overload;
      { IOTANotifier: Der Thread wird abgebaut. }
      procedure Destroyed; reintroduce;
    end;
  private
    FDeferred: TDeferred;
    FDeferredRef: IOTAThreadNotifier;
    FThread: IOTAThread;
    FIndex: Integer;
    /// <summary>Notifier abmelden, wenn er zu ADeferred gehört.</summary>
    procedure Release(ADeferred: TDeferred);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Thread des angehaltenen Prozesses; nil, wenn kein Prozess angehalten ist.</summary>
    class function StoppedThread: IOTAThread; static;
    class function Stopped: Boolean; static;
    /// <summary>Wertet AExpression aus (ALine 1-basiert). Sofort fertig: Wert bzw. Fehler; verzögert:
    /// Pending, AOnDone kommt später im Hauptthread. None ohne angehaltenen Prozess.</summary>
    function Evaluate(const AExpression, AFileName: string; ALine: Integer;
      const AOnDone: TDpccDebugValueEvent): TDpccDebugValue; overload;
    /// <summary>Wie oben; ASideEffects erlaubt Funktionsaufrufe im Ausdruck (#784).</summary>
    function Evaluate(const AExpression, AFileName: string; ALine: Integer; ASideEffects: Boolean;
      const AOnDone: TDpccDebugValueEvent): TDpccDebugValue; overload;
    /// <summary>Setzt AExpression auf ANewValue (#784): erst auswerten, dann IOTAThread.Modify. AResult: neuer Wert
    /// bzw. Fehlertext; leer, wenn der Debugger verzögert antwortet (dann beim nächsten Auswerten sichtbar).
    /// </summary>
    class function Modify(const AExpression, AFileName: string; ALine: Integer; const ANewValue: string;
      out AResult: string): Boolean; static;
    /// <summary>Wie Evaluate, wartet aber nicht auf eine verzögerte Antwort (Tooltip der IDE).</summary>
    class function EvaluateNow(const AExpression, AFileName: string; ALine: Integer): TDpccDebugValue; static;
    /// <summary>Laufende Auswertung verwerfen; ihr Ergebnis kommt nicht mehr.</summary>
    procedure Cancel;
  end;

implementation

uses
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.MainThread;

const
  cBufferSize = 4096;

type
  TOutcome = record
    Code: TOTAEvaluateResult;
    Text: string;
  end;

function RunEvaluate(const AThread: IOTAThread; const AExpression, AFileName: string;
  ALine: Integer; ASideEffects: Boolean): TOutcome;
var
  mBuffer: array[0..cBufferSize - 1] of Char;
  mCanModify: Boolean;
  mResultAddr, mResultSize, mResultVal: LongWord;
begin
  FillChar(mBuffer, SizeOf(mBuffer), 0);
  if ASideEffects then
  begin
    Result.Code := AThread.Evaluate(AExpression, @mBuffer[0], Length(mBuffer), mCanModify, eseAll, '', mResultAddr,
      mResultSize, mResultVal, AFileName, ALine);
  end
  else
  begin
    Result.Code := AThread.Evaluate(AExpression, @mBuffer[0], Length(mBuffer), mCanModify, eseNone, '', mResultAddr,
      mResultSize, mResultVal, AFileName, ALine);
  end;
  Result.Text := mBuffer;
end;

{ TDpccIdeDebugValues.TDeferred }

constructor TDpccIdeDebugValues.TDeferred.Create(AOwner: TDpccIdeDebugValues; const AExpression: string;
  const AOnDone: TDpccDebugValueEvent);
begin
  inherited Create;
  FOwner := AOwner;
  FExpression := AExpression;
  FOnDone := AOnDone;
end;

procedure TDpccIdeDebugValues.TDeferred.Complete(const AResult: string; AReturnCode: Integer);
var
  mKeep: IOTAThreadNotifier;
  mDeferred: TDeferred;
  mValue: TDpccDebugValue;
begin
  if FDone then
  begin
    Exit;
  end;
  FDone := True;
  if AReturnCode = 0 then
  begin
    mValue := TDpccDebugValue.Evaluated(FExpression, AResult);
  end
  else
  begin
    mValue := TDpccDebugValue.Failed(FExpression, AResult);
  end;
  // Der Debugger ruft aus seiner Benachrichtigung; abmelden und anzeigen erst danach im Hauptthread.
  // Keep hält den Notifier bis dahin am Leben.
  mKeep := Self;
  mDeferred := Self;
  TDpccMainThread.ForceQueue(TDpccFeature.Hover,
    procedure
    begin
      if mKeep <> nil then
      begin
        TDpccGuard.Run(TDpccFeature.Hover,
        procedure
        begin
          if mDeferred.FOwner = nil then
          begin
            Exit;
          end;
          mDeferred.FOwner.Release(mDeferred);
          if Assigned(mDeferred.FOnDone) then
          begin
            mDeferred.FOnDone(mValue);
          end;
        end);
      end;
    end);
end;

procedure TDpccIdeDebugValues.TDeferred.ThreadNotify(Reason: TOTANotifyReason);
begin
  // Nichts zu tun: Ob der Debugger zum Auswerten kurz weiterläuft, ist nicht festgelegt. Läuft das Programm
  // wirklich weiter, verwirft der Tooltip die Auswertung beim Schließen (Taste, Klick) über Cancel.
end;

procedure TDpccIdeDebugValues.TDeferred.EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
  ResultAddress, ResultSize: LongWord; ReturnCode: Integer);
begin
  Complete(ResultStr, ReturnCode);
end;

procedure TDpccIdeDebugValues.TDeferred.EvaluateComplete(const ExprStr, ResultStr: string; CanModify: Boolean;
  ResultAddress: TOTAAddress; ResultSize: LongWord; ReturnCode: Integer);
begin
  Complete(ResultStr, ReturnCode);
end;

procedure TDpccIdeDebugValues.TDeferred.ModifyComplete(const ExprStr, ResultStr: string; ReturnCode: Integer);
begin
end;

procedure TDpccIdeDebugValues.TDeferred.Destroyed;
begin
  // Thread beendet: nicht mehr abmelden, kein Wert.
  FThreadGone := True;
  Complete('', -1);
end;

{ TDpccIdeDebugValues }

constructor TDpccIdeDebugValues.Create;
begin
  inherited Create;
  FIndex := -1;
end;

destructor TDpccIdeDebugValues.Destroy;
begin
  Cancel;
  inherited Destroy;
end;

class function TDpccIdeDebugValues.StoppedThread: IOTAThread;
var
  mDebugger: IOTADebuggerServices;
  mProcess: IOTAProcess;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) then
  begin
    Exit;
  end;
  mProcess := mDebugger.CurrentProcess;
  if (mProcess = nil) or not (mProcess.ProcessState in [psStopped, psFault, psException]) then
  begin
    Exit;
  end;
  Result := mProcess.CurrentThread;
end;

class function TDpccIdeDebugValues.Stopped: Boolean;
begin
  Result := StoppedThread <> nil;
end;

procedure TDpccIdeDebugValues.Release(ADeferred: TDeferred);
begin
  if (ADeferred = nil) or (ADeferred <> FDeferred) then
  begin
    Exit;
  end;
  if (FThread <> nil) and (FIndex >= 0) and not FDeferred.FThreadGone then
    try
      FThread.RemoveNotifier(FIndex);
    except
      // Thread schon abgebaut: nichts mehr abzumelden.
    end;
  FDeferred.FOwner := nil;
  FDeferred := nil;
  FDeferredRef := nil;
  FThread := nil;
  FIndex := -1;
end;

procedure TDpccIdeDebugValues.Cancel;
begin
  if FDeferred <> nil then
  begin
    FDeferred.FDone := True;
    Release(FDeferred);
  end;
end;

function TDpccIdeDebugValues.Evaluate(const AExpression, AFileName: string; ALine: Integer;
  const AOnDone: TDpccDebugValueEvent): TDpccDebugValue;
begin
  Result := Evaluate(AExpression, AFileName, ALine, False, AOnDone);
end;

function TDpccIdeDebugValues.Evaluate(const AExpression, AFileName: string; ALine: Integer; ASideEffects: Boolean;
  const AOnDone: TDpccDebugValueEvent): TDpccDebugValue;
var
  mThread: IOTAThread;
  mOutcome: TOutcome;
begin
  Cancel;
  Result := Default(TDpccDebugValue);
  mThread := StoppedThread;
  if (mThread = nil) or (AExpression = '') then
  begin
    Exit;
  end;
  mOutcome := RunEvaluate(mThread, AExpression, AFileName, ALine, ASideEffects);
  case mOutcome.Code of
    erOK:
      Result := TDpccDebugValue.Evaluated(AExpression, mOutcome.Text);
    erDeferred:
      begin
        // Antwort kommt über den Notifier des Threads.
        FDeferred := TDeferred.Create(Self, AExpression, AOnDone);
        FDeferredRef := FDeferred;
        FThread := mThread;
        FIndex := mThread.AddNotifier(FDeferredRef);
        Result := TDpccDebugValue.Pending(AExpression);
      end;
  else
    // erError, erBusy: kein Wert.
    Result := TDpccDebugValue.Failed(AExpression, mOutcome.Text);
  end;
end;

class function TDpccIdeDebugValues.EvaluateNow(const AExpression, AFileName: string;
  ALine: Integer): TDpccDebugValue;
var
  mThread: IOTAThread;
  mOutcome: TOutcome;
begin
  Result := Default(TDpccDebugValue);
  mThread := StoppedThread;
  if (mThread = nil) or (AExpression = '') then
  begin
    Exit;
  end;
  mOutcome := RunEvaluate(mThread, AExpression, AFileName, ALine, False);
  if mOutcome.Code = erOK then
  begin
    Result := TDpccDebugValue.Evaluated(AExpression, mOutcome.Text);
  end
  else
  begin
    Result := TDpccDebugValue.Failed(AExpression, mOutcome.Text);
  end;
end;

class function TDpccIdeDebugValues.Modify(const AExpression, AFileName: string; ALine: Integer;
  const ANewValue: string; out AResult: string): Boolean;
var
  mThread: IOTAThread;
  mOutcome: TOutcome;
  mBuffer: array[0..cBufferSize - 1] of Char;
  mResultVal: Integer;
  mCode: TOTAEvaluateResult;
begin
  AResult := '';
  mThread := StoppedThread;
  if (mThread = nil) or (AExpression = '') then
  begin
    Exit(False);
  end;
  // Modify ändert den zuletzt ausgewerteten Ausdruck: erst auswerten, ohne Nebenwirkungen.
  mOutcome := RunEvaluate(mThread, AExpression, AFileName, ALine, False);
  if mOutcome.Code <> erOK then
  begin
    AResult := mOutcome.Text;
    Exit(False);
  end;
  FillChar(mBuffer, SizeOf(mBuffer), 0);
  mResultVal := 0;
  mCode := mThread.Modify(ANewValue, @mBuffer[0], Length(mBuffer), mResultVal);
  AResult := mBuffer;
  Result := mCode in [erOK, erDeferred];
end;

end.
