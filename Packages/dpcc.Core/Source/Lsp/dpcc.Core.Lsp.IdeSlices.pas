unit dpcc.Core.Lsp.IdeSlices;

// Zeitscheiben für Typen und Mitglieder aus den Packages der IDE (dpcc/ideTypes, dpcc/ideMembers), ohne RTTI, Open
// Tools API und VCL. Die RTTI der Packages liest nur der Hauptthread (dpcc.IDE.CodeInsight.IdeTypes,
// dpcc.IDE.CodeInsight.IdeMembers); damit die IDE dabei nicht hängt, in Takten mit Zeitbudget, die über
// TDpccMainThread.ForceQueue aufeinander folgen. JSON und Senden laufen danach im Hintergrund. Hier die reine Logik:
//   - TDpccSliceWalk: Lauf über eine zweistufige Liste (Packages × Typen; Palette: Packages × Komponenten), über
//     Takte fortsetzbar. Run lädt die innere Liste eines Elements (ALoad, etwa GetTypes: ein Aufruf, nicht teilbar)
//     und besucht danach jedes innere Element einzeln (AVisit). Nach jedem Laden und jedem Besuch fragt es
//     AExhausted (Zeitbudget); jeder Aufruf erledigt mindestens einen Schritt, so kommt jeder Lauf voran. Reload lädt
//     die innere Liste neu und setzt an derselben Stelle fort (die IDE hat zwischen zwei Takten Module entladen).
//   - TDpccSliceStats: Takte, Summe und längster Takt für die Diagnosezeilen „IDE-Typen“ und „IDE-Mitglieder“.
//   - TDpccUnitModules: Unit → Module (Dateinamen der Packages), gemerkt beim Lauf der IDE-Typen. Der Lauf der
//     Mitglieder besucht damit nur die Packages der gewünschten Units; ist eine davon unbekannt, alle.
//   - TDpccIdeMemberQueue: Anforderungen dpcc/ideMembersWanted. Höchstens ein Lauf; was währenddessen kommt, wird
//     zusammengeführt und läuft danach genau einmal. Cancel (neue Sitzung, Stopp, Entladen) verwirft alles und
//     wechselt die Generation: Ein laufender Lauf erkennt daran, dass er nichts mehr senden darf.
// Alles nur im Hauptthread (keine Sperren).

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Lauf über eine zweistufige Liste in Takten (nur Hauptthread).</summary>
  TDpccSliceWalk = class
  private
    FOuterCount: Integer;
    FOuter: Integer;
    FInner: Integer;
    /// <summary>Zahl der inneren Elemente von FOuter; -1 = noch nicht geladen.</summary>
    FInnerCount: Integer;
  public
    /// <summary>Lauf über AOuterCount äußere Elemente (fest für den Lauf).</summary>
    constructor Create(AOuterCount: Integer);
    /// <summary>Weiter, bis fertig oder AExhausted True meldet (gefragt nach jedem Schritt; mindestens ein Schritt
    /// je Aufruf). ALoad(Außen) lädt die innere Liste und liefert ihre Länge; AVisit(Außen, Innen) besucht ein
    /// Element. Beide fangen ihre Ausnahmen selbst; entkommt doch eine, gilt das Element als erledigt. True, wenn
    /// fertig.</summary>
    function Run(const ALoad: TFunc<Integer, Integer>; const AVisit: TProc<Integer, Integer>;
      const AExhausted: TFunc<Boolean>): Boolean;
    /// <summary>Innere Liste des aktuellen Elements beim nächsten Schritt neu laden; die Stelle darin bleibt.
    /// </summary>
    procedure Reload;
    function Done: Boolean;
    property OuterCount: Integer read FOuterCount;
    property Outer: Integer read FOuter;
    property Inner: Integer read FInner;
  end;

  /// <summary>Takte eines Laufs: Anzahl, Summe und längster (ms).</summary>
  TDpccSliceStats = record
    Steps: Integer;
    TotalMs: Int64;
    LongestMs: Int64;
    procedure Add(AMs: Int64);
  end;

  /// <summary>Unit → Module (Dateinamen der Packages), ohne Groß-/Kleinschreibung (nur Hauptthread).</summary>
  TDpccUnitModules = class
  private
    FModules: TDictionary<string, TArray<string>>;
    /// <summary>Zuletzt eingetragenes Paar: Die Typen eines Packages kommen meist Unit für Unit.</summary>
    FLastUnit: string;
    FLastModule: string;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AUnit liegt im Modul AModule; dasselbe Paar mehrfach zählt einmal, leere Angaben gar nicht.</summary>
    procedure Add(const AUnit, AModule: string);
    /// <summary>Module der Units AUnits (Reihenfolge des ersten Vorkommens, ohne doppelte); False, wenn eine davon
    /// unbekannt ist (dann alle Packages besuchen).</summary>
    function ModulesOf(const AUnits: TArray<string>; out AModules: TArray<string>): Boolean;
    function Count: Integer;
  end;

  /// <summary>Anforderungen dpcc/ideMembersWanted (nur Hauptthread): höchstens ein Lauf, zusammengeführt.</summary>
  TDpccIdeMemberQueue = record
  private
    FPending: TArray<string>;
    FRunning: Boolean;
    FGeneration: Cardinal;
  public
    /// <summary>Units AUnits merken (ohne doppelte, ohne Groß-/Kleinschreibung); True, wenn jetzt ein Lauf beginnen
    /// soll (keiner läuft, etwas wartet).</summary>
    function Request(const AUnits: TArray<string>): Boolean;
    /// <summary>Lauf beginnen: alle wartenden Units übernehmen; AGeneration kennzeichnet den Lauf. False, wenn schon
    /// einer läuft oder nichts wartet.</summary>
    function TryStart(out AUnits: TArray<string>; out AGeneration: Cardinal): Boolean;
    /// <summary>Lauf AGeneration ist zu Ende (auch nach Fehler); True, wenn inzwischen Units warten (dann genau
    /// einmal TryStart). Ein veralteter Lauf (nach Cancel) ändert nichts.</summary>
    function Finish(AGeneration: Cardinal): Boolean;
    /// <summary>Ist AGeneration der laufende Lauf?</summary>
    function IsCurrent(AGeneration: Cardinal): Boolean;
    /// <summary>Lauf und wartende Units verwerfen (neue Sitzung, Stopp, Entladen).</summary>
    procedure Cancel;
    function Running: Boolean;
    function Pending: TArray<string>;
  end;

implementation

{ TDpccSliceWalk }

constructor TDpccSliceWalk.Create(AOuterCount: Integer);
begin
  inherited Create;
  FOuterCount := AOuterCount;
  FInnerCount := -1;
end;

function TDpccSliceWalk.Run(const ALoad: TFunc<Integer, Integer>; const AVisit: TProc<Integer, Integer>;
  const AExhausted: TFunc<Boolean>): Boolean;
var
  mCount: Integer;
begin
  while FOuter < FOuterCount do
  begin
    if FInnerCount < 0 then
    begin
      // Vorher leer: Eine Ausnahme beim Laden lässt das Element aus, statt es bei jedem Aufruf neu zu laden.
      FInnerCount := 0;
      mCount := ALoad(FOuter);
      if mCount > 0 then
      begin
        FInnerCount := mCount;
      end;
    end
    else if FInner < FInnerCount then
    begin
      // Erst weiterzählen: Eine Ausnahme in AVisit wiederholt das Element nicht.
      Inc(FInner);
      AVisit(FOuter, FInner - 1);
    end;
    if FInner >= FInnerCount then
    begin
      Inc(FOuter);
      FInner := 0;
      FInnerCount := -1;
    end;
    if AExhausted() then
    begin
      Break;
    end;
  end;
  Result := Done;
end;

procedure TDpccSliceWalk.Reload;
begin
  if not Done then
  begin
    FInnerCount := -1;
  end;
end;

function TDpccSliceWalk.Done: Boolean;
begin
  Result := FOuter >= FOuterCount;
end;

{ TDpccSliceStats }

procedure TDpccSliceStats.Add(AMs: Int64);
begin
  Inc(Steps);
  Inc(TotalMs, AMs);
  if AMs > LongestMs then
  begin
    LongestMs := AMs;
  end;
end;

{ TDpccUnitModules }

constructor TDpccUnitModules.Create;
begin
  inherited Create;
  FModules := TDictionary<string, TArray<string>>.Create;
end;

destructor TDpccUnitModules.Destroy;
begin
  FModules.Free;
  inherited;
end;

procedure TDpccUnitModules.Add(const AUnit, AModule: string);
var
  mKey: string;
  mModules: TArray<string>;
  mModule: string;
begin
  if (AUnit = '') or (AModule = '') or ((AUnit = FLastUnit) and (AModule = FLastModule)) then
  begin
    Exit;
  end;
  FLastUnit := AUnit;
  FLastModule := AModule;
  mKey := UpperCase(AUnit);
  if not FModules.TryGetValue(mKey, mModules) then
  begin
    mModules := [AModule];
    FModules.Add(mKey, mModules);
    Exit;
  end;
  for mModule in mModules do
  begin
    if SameText(mModule, AModule) then
    begin
      Exit;
    end;
  end;
  FModules[mKey] := mModules + [AModule];
end;

function TDpccUnitModules.ModulesOf(const AUnits: TArray<string>; out AModules: TArray<string>): Boolean;
var
  mUnit: string;
  mModule: string;
  mModules: TArray<string>;
  mSeen: TDictionary<string, Boolean>;
begin
  AModules := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mUnit in AUnits do
    begin
      if not FModules.TryGetValue(UpperCase(mUnit), mModules) then
      begin
        AModules := nil;
        Exit(False);
      end;
      for mModule in mModules do
      begin
        if not mSeen.ContainsKey(UpperCase(mModule)) then
        begin
          mSeen.Add(UpperCase(mModule), True);
          AModules := AModules + [mModule];
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
  Result := True;
end;

function TDpccUnitModules.Count: Integer;
begin
  Result := FModules.Count;
end;

{ TDpccIdeMemberQueue }

function TDpccIdeMemberQueue.Request(const AUnits: TArray<string>): Boolean;
var
  mUnit: string;
  mPending: string;
  mKnown: Boolean;
begin
  for mUnit in AUnits do
  begin
    if Trim(mUnit) = '' then
    begin
      Continue;
    end;
    mKnown := False;
    for mPending in FPending do
    begin
      if SameText(mPending, Trim(mUnit)) then
      begin
        mKnown := True;
        Break;
      end;
    end;
    if not mKnown then
    begin
      FPending := FPending + [Trim(mUnit)];
    end;
  end;
  Result := not FRunning and (Length(FPending) > 0);
end;

function TDpccIdeMemberQueue.TryStart(out AUnits: TArray<string>; out AGeneration: Cardinal): Boolean;
begin
  AUnits := nil;
  AGeneration := FGeneration;
  if FRunning or (Length(FPending) = 0) then
  begin
    Exit(False);
  end;
  Inc(FGeneration);
  FRunning := True;
  AUnits := FPending;
  FPending := nil;
  AGeneration := FGeneration;
  Result := True;
end;

function TDpccIdeMemberQueue.Finish(AGeneration: Cardinal): Boolean;
begin
  if not IsCurrent(AGeneration) then
  begin
    Exit(False);
  end;
  FRunning := False;
  Result := Length(FPending) > 0;
end;

function TDpccIdeMemberQueue.IsCurrent(AGeneration: Cardinal): Boolean;
begin
  Result := FRunning and (FGeneration = AGeneration);
end;

procedure TDpccIdeMemberQueue.Cancel;
begin
  FPending := nil;
  FRunning := False;
  Inc(FGeneration);
end;

function TDpccIdeMemberQueue.Running: Boolean;
begin
  Result := FRunning;
end;

function TDpccIdeMemberQueue.Pending: TArray<string>;
begin
  Result := FPending;
end;

end.
