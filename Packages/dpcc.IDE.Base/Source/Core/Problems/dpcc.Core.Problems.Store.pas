unit dpcc.Core.Problems.Store;

// Probleme je Datei (#398), nur im Hauptthread benutzt. Jede Datei merkt sich
// den Text, auf den sich die Positionen beziehen.
// - Update: neue Diagnosen des Servers für einen Text. dpcc-Meldungen werden
//   ersetzt; Compilermeldungen (dcc) nur mit AReplaceCompiler (erste Meldung,
//   nach workspace/diagnostic/refresh, nicht geöffnete Dateien), sonst
//   behält die Datei ihre mitgewanderten Compilermeldungen: Der Server liefert
//   sie an den Zeilen des letzten Compiles, auch wenn der Text sich seither
//   verschoben hat.
// - Edit: Der Editortext hat sich geändert. Zeilen vor und hinter der
//   geänderten Stelle bleiben bzw. verschieben sich um die Zahl eingefügter
//   oder gelöschter Zeilen; Meldungen in der geänderten Stelle werden blass
//   (Stale). Compilermeldungen werden nach jeder Änderung blass, bis zum
//   nächsten Compile.
// Version zählt jede Änderung, damit Zeichner und Liste nur bei Bedarf
// neu aufbauen.
// Inaktive {$IFDEF}-Zweige (#615) liefert InactiveSpans je Zeile als Spalten
// des Editors, auch für Zweige, die innerhalb einer Zeile beginnen oder enden.
// Hinweise zu uses-Einträgen (#621, data.uses) sind weder Probleme noch
// inaktive Zweige: UsesSpans liefert die ungenutzten zum Abblenden, UsesAt die
// an einer Stelle für den Tooltip.
// Fehlgeschlagene Tests (#69) stehen als dritte Art neben dpcc- und
// Compilermeldungen (Quelle "DUnitX"): SetTests ersetzt die eines Testlaufs,
// Update des Servers lässt sie stehen, Edit führt sie wie dpcc-Meldungen mit.
// Eine Datei nur mit Tests gilt nicht als vom Server geprüft (Contains,
// AllFiles).
// Befunde von Projektaufgaben (#900) stehen als vierte Art daneben (Quelle =
// Name der Aufgabe): SetTaskProblems ersetzt die einer Aufgabe in allen
// Dateien, Update des Servers lässt sie stehen; ändert sich die Zeile eines
// Befunds (Edit), fällt er weg, statt blass zu werden. Ausgeblendete Aufgaben
// (SetTaskHidden) fehlen in ForFile und allem, was darauf aufbaut.
// Gruppe „Compiler vorab“ (#1024): Meldet der letzte Build an der Zeile eines
// dpcc-Befunds einen der Codes aus data.compilerCodes, ist der Befund „vom
// Compiler bestätigt“ (Confirmed, ConfirmedCode). Mit CompilerMerge (Vorgabe,
// problems.compilerMerge = merge) entfällt die Compilermeldung dann in
// ForFile und allem, was darauf aufbaut (Wellenlinie, Hover, Fenster); mit
// both bleiben beide. Ist die Meldung nach dem nächsten Build weg, bleibt nur
// der dpcc-Befund.
// Gelöschte Zeilen (#1818, editor.trackLines): Mit DropDeletedLines fallen
// bei einer reinen Löschung (die geänderte Stelle ist im neuen Text leer)
// die Meldungen weg, die ganz in den gelöschten Zeilen lagen, statt blass
// auf die Folgezeile zu rutschen; bis zur nächsten Antwort des Servers.
// Fehler der IDE (#1819, problems.ideErrors): SetIdeErrors ersetzt die
// Fehler aus Error Insight einer Datei. Sie stehen nicht in ForFile (keine
// Wellenlinie, kein Hover, keine Zähler: die IDE zeichnet ihre Fehler
// selbst), sondern nur in WithIde für das Fenster „dpcc-Prüfung“, dort mit
// den dpcc-Befunden abgeglichen (dpcc.Core.Problems.IdeErrors). Wie
// Befunde von Aufgaben gelten sie für den Text, den die IDE sah: Bei Edit
// fallen sie in der geänderten Stelle weg, dahinter verschieben sie sich.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Core.Problems.Contract;

type
  /// <summary>Spalten einer Editorzeile (1-basiert, Tabs aufgelöst), Last einschließlich;
  /// Last = MaxInt bis zum Zeilenende.</summary>
  TDpccColumnSpan = record
    First: Integer;
    Last: Integer;
    class function Create(AFirst, ALast: Integer): TDpccColumnSpan; static;
    /// <summary>Liegt die Spalte in einem der Bereiche?</summary>
    class function Contains(const ASpans: TArray<TDpccColumnSpan>; AColumn: Integer): Boolean; static;
    /// <summary>Liegen alle Spalten AColumn .. AColumn + ACount - 1 in den Bereichen?</summary>
    class function Covers(const ASpans: TArray<TDpccColumnSpan>; AColumn, ACount: Integer): Boolean; static;
  end;

  /// <summary>Einträge je Datei mit Stand (Stamp); Grundlage von TDpccProblemStore.</summary>
  TDpccProblemEntries = class
  protected type
    TEntry = class
      FFileName: string;
      FText: string;
      FTextKnown: Boolean;
      FResultId: string;
      FDpcc: TArray<TDpccProblem>;
      FCompiler: TArray<TDpccProblem>;
      /// <summary>Fehlgeschlagene Tests des letzten Laufs (#69).</summary>
      FTests: TArray<TDpccProblem>;
      /// <summary>Befunde von Projektaufgaben (#900), Source = Name der Aufgabe.</summary>
      FTasks: TArray<TDpccProblem>;
      /// <summary>Fehler aus Error Insight der IDE (#1819), Source "IDE".</summary>
      FIde: TArray<TDpccProblem>;
      /// <summary>Diagnosen des Servers kamen schon (Update); False bei einer Datei nur mit Tests.</summary>
      FFromServer: Boolean;
      // ForFile bzw. Inactive, bis sich etwas ändert.
      FVisible: TArray<TDpccProblem>;
      FVisibleValid: Boolean;
      FInactiveList: TArray<TDpccProblem>;
      FInactiveValid: Boolean;
      FUsesList: TArray<TDpccProblem>;
      FUsesValid: Boolean;
      // Zeilen von Text, bei Bedarf.
      FLines: TArray<string>;
      FLinesValid: Boolean;
      /// <summary>Stand der Datei: neu bei jeder Änderung ihrer Probleme oder ihres Texts (Stamp).</summary>
      FStamp: Integer;
    end;
  protected
    FEntries: TObjectDictionary<string, TEntry>;
    FVersion: Integer;
    // Über alle Speicher hinweg fortlaufend: Ein neuer Speicher (Neustart des Servers) wiederholt keinen Stand.
    class var FLastStamp: Integer;
    /// <summary>Einträge ohne Server, Tests und Aufgaben entfernen.</summary>
    procedure DropEmpty;
    function Find(const AFileName: string): TEntry;
    function Ensure(const AFileName: string): TEntry;
    /// <summary>Neuer Stand für AEntry (Stamp).</summary>
    class procedure Touch(AEntry: TEntry); static;
    /// <summary>Positionen auf ANewText bringen; ADropDeleted: Meldungen in rein gelöschten Zeilen entfernen.
    /// </summary>
    class procedure Shift(AEntry: TEntry; const ANewText: string; ADropDeleted: Boolean); static;
  public
    constructor Create;
    destructor Destroy; override;
    class function Key(const AFileName: string): string; static;
    /// <summary>Fehler der IDE für AFileName (#1819): ersetzt die bisherigen; Positionen zum Text der letzten
    /// Prüfung. Ohne Eintrag der Datei geschieht nichts.</summary>
    procedure SetIdeErrors(const AFileName: string; const AErrors: TArray<TDpccProblem>);
    /// <summary>Fehler der IDE aller Dateien entfernen (problems.ideErrors aus).</summary>
    procedure ClearIdeErrors;
    /// <summary>Fehler der IDE der Datei, wie zuletzt gesetzt und mitgeführt.</summary>
    function IdeErrors(const AFileName: string): TArray<TDpccProblem>;
    property Version: Integer read FVersion;
  end;

  TDpccProblemStore = class(TDpccProblemEntries)
  public const
    /// <summary>Quelle der Meldungen fehlgeschlagener Tests (#69).</summary>
    cTestSource = 'DUnitX';
  private
    FCompilerMerge: Boolean;
    FDropDeletedLines: Boolean;
    FHiddenTasks: TArray<string>;
    procedure SetCompilerMerge(AValue: Boolean);
    /// <summary>Spalten der Bereiche AProblems in der Zeile (wie InactiveSpans).</summary>
    function SpansOf(const AFileName: string; const AProblems: TArray<TDpccProblem>;
      ALine, ATabWidth: Integer): TArray<TDpccColumnSpan>;
  public
    constructor Create;
    /// <summary>Diagnosen des Servers für AText (ATextKnown = False: Text unbekannt, etwa von der Platte).</summary>
    procedure Update(const AFileName, AText: string; ATextKnown: Boolean; const AProblems: TArray<TDpccProblem>;
      const AResultId: string; AReplaceCompiler: Boolean);
    /// <summary>Editortext geändert: Positionen mitführen.</summary>
    procedure Edit(const AFileName, ANewText: string);
    procedure Remove(const AFileName: string);
    procedure Clear;
    /// <summary>Fehlgeschlagene Tests eines Laufs (#69): ersetzt die Tests aller Dateien. AProblems je Datei;
    /// Positionen beziehen sich auf den Text der Platte bzw. den bekannten Text.</summary>
    procedure SetTests(const AProblems: TArray<TPair<string, TDpccProblem>>);
    /// <summary>Tests aller Dateien entfernen.</summary>
    procedure ClearTests;
    /// <summary>Befunde der Projektaufgabe ATask (#900): ersetzt ihre Befunde in allen Dateien. AProblems je
    /// Datei; Source wird ATask.</summary>
    procedure SetTaskProblems(const ATask: string; const AProblems: TArray<TPair<string, TDpccProblem>>);
    /// <summary>Befunde der Aufgabe ATask entfernen.</summary>
    procedure ClearTask(const ATask: string);
    /// <summary>Befunde aller Aufgaben entfernen.</summary>
    procedure ClearTasks;
    /// <summary>Befunde der Aufgabe ATask aus- bzw. wieder einblenden (Problemliste, Editor).</summary>
    procedure SetTaskHidden(const ATask: string; AHidden: Boolean);
    function TaskHidden(const ATask: string): Boolean;
    /// <summary>Aufgaben mit Befunden (auch ausgeblendete), nach Namen.</summary>
    function TaskNames: TArray<string>;
    /// <summary>Zahl der Befunde der Aufgabe ATask, auch ausgeblendet.</summary>
    function TaskCount(const ATask: string): Integer;
    /// <summary>ForFile mit den Fehlern der IDE abgeglichen (#1819): bestätigte Befunde mit IdeConfirmed, übrige
    /// Fehler der IDE dazu. Ohne Fehler der IDE gleich ForFile.</summary>
    function WithIde(const AFileName: string): TArray<TDpccProblem>;
    /// <summary>Hat der Server die Datei schon geliefert? Dateien nur mit Tests zählen nicht.</summary>
    function Contains(const AFileName: string): Boolean;
    function ResultId(const AFileName: string): string;
    /// <summary>Probleme der Datei ohne inaktive Bereiche und ohne Doppelte, nach Position.</summary>
    function ForFile(const AFileName: string): TArray<TDpccProblem>;
    /// <summary>Inaktive {$IFDEF}-Zweige der Datei (Diagnosen mit Tag Unnecessary, #615).</summary>
    function Inactive(const AFileName: string): TArray<TDpccProblem>;
    /// <summary>Liegt die ganze Zeile (0-basiert) in einem inaktiven Zweig?</summary>
    function LineInactive(const AFileName: string; ALine: Integer): Boolean;
    /// <summary>Inaktive Spalten der Zeile (0-basiert) für die Tabweite ATabWidth: ganze Zeilen und, bei
    /// bekanntem Text, Teile von Zeilen ({$IFDEF X} a {$ENDIF}). Blasse Bereiche (geänderte Stelle) nur
    /// als ganze Zeilen, bis neue Diagnosen da sind.</summary>
    function InactiveSpans(const AFileName: string; ALine, ATabWidth: Integer): TArray<TDpccColumnSpan>;
    /// <summary>Inaktive Bereiche an der Stelle (0-basiert), für den Hinweis im Tooltip.</summary>
    function InactiveAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TDpccProblem>;
    /// <summary>Ungenutzte uses-Einträge der Datei (#621).</summary>
    function UnusedUses(const AFileName: string): TArray<TDpccProblem>;
    /// <summary>Spalten ungenutzter uses-Einträge in der Zeile (0-basiert), wie InactiveSpans.</summary>
    function UsesSpans(const AFileName: string; ALine, ATabWidth: Integer): TArray<TDpccColumnSpan>;
    /// <summary>Hinweise zu uses-Einträgen an der Stelle (0-basiert), auch behaltene und verschiebbare.</summary>
    function UsesAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TDpccProblem>;
    /// <summary>Probleme, die die Zeile (0-basiert) berühren.</summary>
    function OnLine(const AFileName: string; ALine: Integer): TArray<TDpccProblem>;
    /// <summary>Probleme an der Stelle (0-basiert).</summary>
    function At(const AFileName: string; ALine, ACharacter: Integer): TArray<TDpccProblem>;
    /// <summary>Text, auf den sich die Positionen beziehen; '' wenn unbekannt.</summary>
    function TextOf(const AFileName: string): string;
    /// <summary>Zeile (0-basiert, ohne #13) des Texts, auf den sich die Positionen beziehen.</summary>
    function LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
    /// <summary>Dateien mit Problemen, nach Namen sortiert.</summary>
    function Files: TArray<string>;
    /// <summary>Alle Dateien mit Diagnosen des Servers, auch ohne Probleme, nach Namen sortiert (Projektzustand
    /// #592: Was hier fehlt, ist nicht geprüft).</summary>
    function AllFiles: TArray<string>;
    /// <summary>Stand der Datei: ändert sich mit allem, was ForFile oder LineText der Datei ändert; 0 ohne
    /// Eintrag. Wer je Datei ableitet (Fenster „dpcc-Prüfung“), baut nur Dateien mit neuem Stand neu.</summary>
    function Stamp(const AFileName: string): Integer;
    /// <summary>Bestätigte Compilermeldungen mit dem dpcc-Befund zusammenführen (problems.compilerMerge, #1024).
    /// </summary>
    property CompilerMerge: Boolean read FCompilerMerge write SetCompilerMerge;
    /// <summary>Meldungen in gelöschten Zeilen bei Edit entfernen statt blass weiterzuführen (#1818).</summary>
    property DropDeletedLines: Boolean read FDropDeletedLines write FDropDeletedLines;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults,
  dpcc.Core.Editor.Pairs,
  dpcc.Core.Problems.IdeErrors,
  dpcc.Text.Diff;

{ TDpccColumnSpan }

class function TDpccColumnSpan.Create(AFirst, ALast: Integer): TDpccColumnSpan;
begin
  Result.First := AFirst;
  Result.Last := ALast;
end;

class function TDpccColumnSpan.Contains(const ASpans: TArray<TDpccColumnSpan>; AColumn: Integer): Boolean;
var
  mSpan: TDpccColumnSpan;
begin
  for mSpan in ASpans do
  begin
    if (AColumn >= mSpan.First) and (AColumn <= mSpan.Last) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDpccColumnSpan.Covers(const ASpans: TArray<TDpccColumnSpan>; AColumn, ACount: Integer): Boolean;
var
  mColumn: Integer;
begin
  for mColumn := AColumn to AColumn + ACount - 1 do
  begin
    if not Contains(ASpans, mColumn) then
    begin
      Exit(False);
    end;
  end;
  Result := ACount > 0;
end;

{ TDpccProblemEntries }

constructor TDpccProblemEntries.Create;
begin
  inherited Create;
  FEntries := TObjectDictionary<string, TEntry>.Create([doOwnsValues]);
end;

{ TDpccProblemStore }

constructor TDpccProblemStore.Create;
begin
  inherited Create;
  FCompilerMerge := True;
end;

procedure TDpccProblemStore.SetCompilerMerge(AValue: Boolean);
var
  mEntry: TEntry;
begin
  if FCompilerMerge = AValue then
  begin
    Exit;
  end;
  FCompilerMerge := AValue;
  for mEntry in FEntries.Values do
  begin
    mEntry.FVisibleValid := False;
    Touch(mEntry);
  end;
  Inc(FVersion);
end;

/// <summary>Index der Compilermeldung in AProblems, die AProblem bestätigt (gleiche Zeile, Code aus
/// CompilerCodes); -1 ohne.</summary>
function ConfirmingIndex(const AProblems: TArray<TDpccProblem>; const AProblem: TDpccProblem): Integer;
var
  mIndex: Integer;
  mCode: string;
begin
  for mIndex := 0 to High(AProblems) do
  begin
    if AProblems[mIndex].IsCompiler and (AProblems[mIndex].StartLine = AProblem.StartLine) then
    begin
      for mCode in AProblem.CompilerCodes do
      begin
        if SameText(mCode, AProblems[mIndex].Code) then
        begin
          Exit(mIndex);
        end;
      end;
    end;
  end;
  Result := -1;
end;

destructor TDpccProblemEntries.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

class function TDpccProblemEntries.Key(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

function TDpccProblemEntries.Find(const AFileName: string): TEntry;
begin
  if not FEntries.TryGetValue(Key(AFileName), Result) then
  begin
    Result := nil;
  end;
end;

function TDpccProblemEntries.Ensure(const AFileName: string): TEntry;
begin
  Result := Find(AFileName);
  if Result = nil then
  begin
    Result := TEntry.Create;
    Result.FFileName := AFileName;
    Touch(Result);
    FEntries.Add(Key(AFileName), Result);
  end;
end;

class procedure TDpccProblemEntries.Touch(AEntry: TEntry);
begin
  Inc(FLastStamp);
  AEntry.FStamp := FLastStamp;
end;

function TDpccProblemStore.Stamp(const AFileName: string): Integer;
var
  mEntry: TEntry;
begin
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Result := 0;
  end
  else
  begin
    Result := mEntry.FStamp;
  end;
end;

procedure TDpccProblemStore.Update(const AFileName, AText: string; ATextKnown: Boolean;
  const AProblems: TArray<TDpccProblem>; const AResultId: string; AReplaceCompiler: Boolean);
var
  mEntry: TEntry;
  mIsNew: Boolean;
  mProblem: TDpccProblem;
  mCompiler: TArray<TDpccProblem>;
begin
  // Eine Datei, die bisher nur Tests hatte, ist für den Server neu.
  mEntry := Find(AFileName);
  mIsNew := (mEntry = nil) or not mEntry.FFromServer;
  mEntry := Ensure(AFileName);
  // Behaltene Compilermeldungen auf den neuen Text bringen.
  if not mIsNew and mEntry.FTextKnown and ATextKnown and (mEntry.FText <> AText) then
  begin
    Shift(mEntry, AText, FDropDeletedLines);
  end;
  mEntry.FDpcc := nil;
  mCompiler := nil;
  for mProblem in AProblems do
  begin
    if mProblem.IsCompiler then
    begin
      mCompiler := mCompiler + [mProblem];
    end
    else
    begin
      mEntry.FDpcc := mEntry.FDpcc + [mProblem];
    end;
  end;
  if mIsNew or AReplaceCompiler then
  begin
    mEntry.FCompiler := mCompiler;
  end;
  mEntry.FText := AText;
  mEntry.FLinesValid := False;
  mEntry.FTextKnown := ATextKnown;
  mEntry.FResultId := AResultId;
  mEntry.FFromServer := True;
  mEntry.FVisibleValid := False;
  Touch(mEntry);
  mEntry.FInactiveValid := False;
  mEntry.FUsesValid := False;
  Inc(FVersion);
end;

/// <summary>Meldungen ohne die, die ganz in den Zeilen [AFrom, ATill) liegen.</summary>
function WithoutLines(const AProblems: TArray<TDpccProblem>; AFrom, ATill: Integer): TArray<TDpccProblem>;
var
  mProblem: TDpccProblem;
begin
  Result := nil;
  for mProblem in AProblems do
  begin
    if (mProblem.StartLine < AFrom) or (mProblem.EndLine >= ATill) then
    begin
      Result := Result + [mProblem];
    end;
  end;
end;

/// <summary>Meldungen außerhalb der geänderten Zeilen [AFrom, ATill); dahinter um ADelta verschoben.</summary>
function OutsideChange(const AProblems: TArray<TDpccProblem>; AFrom, ATill, ADelta: Integer):
  TArray<TDpccProblem>;
var
  mProblem: TDpccProblem;
  mItem: TDpccProblem;
begin
  Result := nil;
  for mItem in AProblems do
  begin
    if (mItem.EndLine >= AFrom) and (mItem.StartLine < ATill) then
    begin
      Continue;
    end;
    mProblem := mItem;
    if mProblem.StartLine >= ATill then
    begin
      Inc(mProblem.StartLine, ADelta);
      Inc(mProblem.EndLine, ADelta);
    end;
    Result := Result + [mProblem];
  end;
end;

class procedure TDpccProblemEntries.Shift(AEntry: TEntry; const ANewText: string; ADropDeleted: Boolean);
var
  mOldCount, mNewCount, mPrefix, mSuffix, mChangedEnd, mDelta, mIndex: Integer;

  procedure Map(var AProblem: TDpccProblem; ACompiler: Boolean);
  begin
    if ACompiler then
    begin
      AProblem.Stale := True;
    end;
    if AProblem.EndLine < mPrefix then
    begin
      Exit;
    end;
    if AProblem.StartLine >= mChangedEnd then
    begin
      Inc(AProblem.StartLine, mDelta);
      Inc(AProblem.EndLine, mDelta);
      Exit;
    end;
    // In der geänderten Stelle: bleibt stehen, aber blass und im Text.
    AProblem.Stale := True;
    AProblem.StartLine := EnsureRange(AProblem.StartLine, 0, Max(0, mNewCount - 1));
    AProblem.EndLine := EnsureRange(AProblem.EndLine, AProblem.StartLine, Max(0, mNewCount - 1));
  end;

begin
  // Ohne die Texte in Zeilen zu zerlegen: Das läuft im Hauptthread nach jeder Änderung.
  TTextDiff.CommonPrefixSuffix(AEntry.FText, ANewText, mPrefix, mSuffix, mOldCount, mNewCount);
  mChangedEnd := mOldCount - mSuffix;
  mDelta := mNewCount - mOldCount;
  // Reine Löschung: Was ganz in den gelöschten Zeilen stand, gibt es nicht mehr (#1818).
  if ADropDeleted and (mDelta < 0) and (mNewCount - mSuffix <= mPrefix) then
  begin
    AEntry.FDpcc := WithoutLines(AEntry.FDpcc, mPrefix, mChangedEnd);
    AEntry.FCompiler := WithoutLines(AEntry.FCompiler, mPrefix, mChangedEnd);
    AEntry.FTests := WithoutLines(AEntry.FTests, mPrefix, mChangedEnd);
  end;
  for mIndex := 0 to High(AEntry.FDpcc) do
  begin
    Map(AEntry.FDpcc[mIndex], False);
  end;
  for mIndex := 0 to High(AEntry.FCompiler) do
  begin
    Map(AEntry.FCompiler[mIndex], True);
  end;
  for mIndex := 0 to High(AEntry.FTests) do
  begin
    Map(AEntry.FTests[mIndex], False);
  end;
  // Befunde von Aufgaben und Fehler der IDE (#1819) gelten für den Stand, den das Werkzeug bzw. die IDE sah: in
  // der geänderten Stelle fallen sie weg.
  AEntry.FTasks := OutsideChange(AEntry.FTasks, mPrefix, mChangedEnd, mDelta);
  AEntry.FIde := OutsideChange(AEntry.FIde, mPrefix, mChangedEnd, mDelta);
  AEntry.FText := ANewText;
  AEntry.FLinesValid := False;
  AEntry.FVisibleValid := False;
  AEntry.FInactiveValid := False;
  AEntry.FUsesValid := False;
end;

function TDpccProblemStore.Inactive(const AFileName: string): TArray<TDpccProblem>;
var
  mEntry: TEntry;
  mProblem: TDpccProblem;
begin
  Result := nil;
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Exit;
  end;
  // Zeichnen fragt je Textlauf: nicht jedes Mal alle Meldungen durchgehen.
  if mEntry.FInactiveValid then
  begin
    Exit(mEntry.FInactiveList);
  end;
  for mProblem in mEntry.FDpcc do
  begin
    if mProblem.Unnecessary and not mProblem.IsUses then
    begin
      Result := Result + [mProblem];
    end;
  end;
  mEntry.FInactiveList := Result;
  mEntry.FInactiveValid := True;
end;

function TDpccProblemStore.UnusedUses(const AFileName: string): TArray<TDpccProblem>;
var
  mEntry: TEntry;
  mProblem: TDpccProblem;
begin
  Result := nil;
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Exit;
  end;
  if mEntry.FUsesValid then
  begin
    Exit(mEntry.FUsesList);
  end;
  for mProblem in mEntry.FDpcc do
  begin
    if mProblem.UsesState = TDpccProblem.cUsesUnused then
    begin
      Result := Result + [mProblem];
    end;
  end;
  mEntry.FUsesList := Result;
  mEntry.FUsesValid := True;
end;

function TDpccProblemStore.UsesSpans(const AFileName: string; ALine, ATabWidth: Integer): TArray<TDpccColumnSpan>;
begin
  Result := SpansOf(AFileName, UnusedUses(AFileName), ALine, ATabWidth);
end;

function TDpccProblemStore.UsesAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TDpccProblem>;
var
  mEntry: TEntry;
  mProblem: TDpccProblem;
begin
  Result := nil;
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Exit;
  end;
  for mProblem in mEntry.FDpcc do
  begin
    if mProblem.IsUses and mProblem.Contains(ALine, ACharacter) then
    begin
      Result := Result + [mProblem];
    end;
  end;
end;

function TDpccProblemStore.InactiveSpans(const AFileName: string; ALine, ATabWidth: Integer): TArray<TDpccColumnSpan>;
begin
  Result := SpansOf(AFileName, Inactive(AFileName), ALine, ATabWidth);
end;

/// <summary>Spalten der ersten bzw. letzten Zeile ALine eines inaktiven Zweigs: ab dem Ende der öffnenden bis vor
/// die schließende Direktive, nur Text, nicht das Zeilenende. False, wenn nichts bleibt.</summary>
function EdgeSpan(const AProblem: TDpccProblem; ALine: Integer; const AText: string; ATabWidth: Integer;
  out ASpan: TDpccColumnSpan): Boolean;
var
  mFirst, mLast: Integer;
begin
  mFirst := 1;
  if ALine = AProblem.StartLine then
  begin
    mFirst := TDpccPairs.ColumnOf(AText, Min(AProblem.StartCharacter, Length(AText)), ATabWidth);
  end;
  if ALine = AProblem.EndLine then
  begin
    mLast := TDpccPairs.ColumnOf(AText, Min(AProblem.EndCharacter, Length(AText)), ATabWidth) - 1;
  end
  else
  begin
    mLast := TDpccPairs.ColumnOf(AText, Length(AText), ATabWidth) - 1;
  end;
  ASpan := TDpccColumnSpan.Create(mFirst, mLast);
  Result := mLast >= mFirst;
end;

function TDpccProblemStore.SpansOf(const AFileName: string; const AProblems: TArray<TDpccProblem>;
  ALine, ATabWidth: Integer): TArray<TDpccColumnSpan>;
var
  mProblem: TDpccProblem;
  mText: string;
  mHasText: Boolean;
  mSpan: TDpccColumnSpan;
begin
  Result := nil;
  mHasText := False;
  mText := '';
  for mProblem in AProblems do
  begin
    if (ALine < mProblem.StartLine) or (ALine > mProblem.EndLine) then
    begin
      Continue;
    end;
    // Zeilen zwischen den Direktiven ganz.
    if (ALine > mProblem.StartLine) and (ALine < mProblem.EndLine) then
    begin
      Result := Result + [TDpccColumnSpan.Create(1, MaxInt)];
      Continue;
    end;
    if mProblem.Stale then
    begin
      Continue;
    end;
    if not mHasText and not LineText(AFileName, ALine, mText) then
    begin
      Exit;
    end;
    mHasText := True;
    if EdgeSpan(mProblem, ALine, mText, ATabWidth, mSpan) then
    begin
      Result := Result + [mSpan];
    end;
  end;
end;

function TDpccProblemStore.InactiveAt(const AFileName: string; ALine, ACharacter: Integer): TArray<TDpccProblem>;
var
  mProblem: TDpccProblem;
begin
  Result := nil;
  for mProblem in Inactive(AFileName) do
  begin
    // Das Ende gehört schon zur schließenden Direktive.
    if mProblem.Contains(ALine, ACharacter) and
      ((ALine < mProblem.EndLine) or (ACharacter < mProblem.EndCharacter)) then
    begin
      Result := Result + [mProblem];
    end;
  end;
end;

function TDpccProblemStore.LineInactive(const AFileName: string; ALine: Integer): Boolean;
var
  mProblem: TDpccProblem;
begin
  // Ein Bereich beginnt hinter der Direktive, die den Zweig abschaltet, und endet vor der nächsten:
  // Die Zeilen dazwischen sind ganz inaktiv, die Zeilen der Direktiven selbst nicht.
  Result := False;
  for mProblem in Inactive(AFileName) do
  begin
    if (ALine > mProblem.StartLine) and (ALine < mProblem.EndLine) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TDpccProblemStore.Edit(const AFileName, ANewText: string);
var
  mEntry: TEntry;
begin
  mEntry := Find(AFileName);
  if (mEntry = nil) or (mEntry.FTextKnown and (mEntry.FText = ANewText)) then
  begin
    Exit;
  end;
  if not mEntry.FTextKnown then
  begin
    // Positionen kamen ohne bekannten Text (Platte): ab jetzt diesen Text zugrunde legen.
    mEntry.FText := ANewText;
    mEntry.FLinesValid := False;
    mEntry.FTextKnown := True;
    Touch(mEntry);
    Exit;
  end;
  Shift(mEntry, ANewText, FDropDeletedLines);
  Touch(mEntry);
  Inc(FVersion);
end;

procedure TDpccProblemStore.Remove(const AFileName: string);
begin
  if Find(AFileName) = nil then
  begin
    Exit;
  end;
  FEntries.Remove(Key(AFileName));
  Inc(FVersion);
end;

procedure TDpccProblemStore.Clear;
begin
  if FEntries.Count = 0 then
  begin
    Exit;
  end;
  FEntries.Clear;
  Inc(FVersion);
end;

function TDpccProblemStore.Contains(const AFileName: string): Boolean;
var
  mEntry: TEntry;
begin
  mEntry := Find(AFileName);
  Result := (mEntry <> nil) and mEntry.FFromServer;
end;

procedure TDpccProblemEntries.DropEmpty;
var
  mEntry: TEntry;
  mEmptied: TArray<string>;
  mFileName: string;
begin
  mEmptied := nil;
  for mEntry in FEntries.Values do
  begin
    if not mEntry.FFromServer and (Length(mEntry.FTests) = 0) and (Length(mEntry.FTasks) = 0) then
    begin
      mEmptied := mEmptied + [mEntry.FFileName];
    end;
  end;
  for mFileName in mEmptied do
  begin
    FEntries.Remove(Key(mFileName));
  end;
end;

procedure TDpccProblemEntries.SetIdeErrors(const AFileName: string; const AErrors: TArray<TDpccProblem>);
var
  mEntry: TEntry;
begin
  mEntry := Find(AFileName);
  if (mEntry = nil) or ((mEntry.FIde = nil) and (AErrors = nil)) then
  begin
    Exit;
  end;
  mEntry.FIde := Copy(AErrors);
  Touch(mEntry);
  Inc(FVersion);
end;

procedure TDpccProblemEntries.ClearIdeErrors;
var
  mEntry: TEntry;
  mChanged: Boolean;
begin
  mChanged := False;
  for mEntry in FEntries.Values do
  begin
    if mEntry.FIde <> nil then
    begin
      mEntry.FIde := nil;
      Touch(mEntry);
      mChanged := True;
    end;
  end;
  if mChanged then
  begin
    Inc(FVersion);
  end;
end;

function TDpccProblemEntries.IdeErrors(const AFileName: string): TArray<TDpccProblem>;
var
  mEntry: TEntry;
begin
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Exit(nil);
  end;
  Result := mEntry.FIde;
end;

function TDpccProblemStore.WithIde(const AFileName: string): TArray<TDpccProblem>;
var
  mIde: TArray<TDpccProblem>;
begin
  mIde := IdeErrors(AFileName);
  Result := ForFile(AFileName);
  if mIde <> nil then
  begin
    Result := TDpccIdeErrors.Merge(Result, mIde);
  end;
end;

procedure TDpccProblemStore.ClearTests;
var
  mEntry: TEntry;
  mChanged: Boolean;
begin
  mChanged := False;
  for mEntry in FEntries.Values do
  begin
    if Length(mEntry.FTests) > 0 then
    begin
      mEntry.FTests := nil;
      mEntry.FVisibleValid := False;
      Touch(mEntry);
      mChanged := True;
    end;
  end;
  DropEmpty;
  if mChanged then
  begin
    Inc(FVersion);
  end;
end;

procedure TDpccProblemStore.ClearTask(const ATask: string);
var
  mEntry: TEntry;
  mKept: TArray<TDpccProblem>;
  mProblem: TDpccProblem;
  mChanged: Boolean;
begin
  mChanged := False;
  for mEntry in FEntries.Values do
  begin
    mKept := nil;
    for mProblem in mEntry.FTasks do
    begin
      if not SameText(mProblem.Source, ATask) then
      begin
        mKept := mKept + [mProblem];
      end;
    end;
    if Length(mKept) <> Length(mEntry.FTasks) then
    begin
      mEntry.FTasks := mKept;
      mEntry.FVisibleValid := False;
      Touch(mEntry);
      mChanged := True;
    end;
  end;
  DropEmpty;
  if mChanged then
  begin
    Inc(FVersion);
  end;
end;

procedure TDpccProblemStore.ClearTasks;
var
  mEntry: TEntry;
  mChanged: Boolean;
begin
  mChanged := False;
  for mEntry in FEntries.Values do
  begin
    if Length(mEntry.FTasks) > 0 then
    begin
      mEntry.FTasks := nil;
      mEntry.FVisibleValid := False;
      Touch(mEntry);
      mChanged := True;
    end;
  end;
  DropEmpty;
  if mChanged then
  begin
    Inc(FVersion);
  end;
end;

procedure TDpccProblemStore.SetTaskProblems(const ATask: string;
  const AProblems: TArray<TPair<string, TDpccProblem>>);
var
  mItem: TPair<string, TDpccProblem>;
  mEntry: TEntry;
  mProblem: TDpccProblem;
begin
  ClearTask(ATask);
  for mItem in AProblems do
  begin
    mEntry := Ensure(mItem.Key);
    mProblem := mItem.Value;
    mProblem.Source := ATask;
    mEntry.FTasks := mEntry.FTasks + [mProblem];
    mEntry.FVisibleValid := False;
    Touch(mEntry);
  end;
  if Length(AProblems) > 0 then
  begin
    Inc(FVersion);
  end;
end;

function TDpccProblemStore.TaskHidden(const ATask: string): Boolean;
var
  mName: string;
begin
  for mName in FHiddenTasks do
  begin
    if SameText(mName, ATask) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TDpccProblemStore.SetTaskHidden(const ATask: string; AHidden: Boolean);
var
  mKept: TArray<string>;
  mName: string;
  mEntry: TEntry;
begin
  if TaskHidden(ATask) = AHidden then
  begin
    Exit;
  end;
  if AHidden then
  begin
    FHiddenTasks := FHiddenTasks + [ATask];
  end
  else
  begin
    mKept := nil;
    for mName in FHiddenTasks do
    begin
      if not SameText(mName, ATask) then
      begin
        mKept := mKept + [mName];
      end;
    end;
    FHiddenTasks := mKept;
  end;
  for mEntry in FEntries.Values do
  begin
    mEntry.FVisibleValid := False;
    Touch(mEntry);
  end;
  Inc(FVersion);
end;

function TDpccProblemStore.TaskNames: TArray<string>;
var
  mEntry: TEntry;
  mProblem: TDpccProblem;
  mName: string;
  mKnown: Boolean;
begin
  Result := nil;
  for mEntry in FEntries.Values do
  begin
    for mProblem in mEntry.FTasks do
    begin
      mKnown := False;
      for mName in Result do
      begin
        if SameText(mName, mProblem.Source) then
        begin
          mKnown := True;
        end;
      end;
      if not mKnown then
      begin
        Result := Result + [mProblem.Source];
      end;
    end;
  end;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(A, B);
    end));
end;

function TDpccProblemStore.TaskCount(const ATask: string): Integer;
var
  mEntry: TEntry;
  mProblem: TDpccProblem;
begin
  Result := 0;
  for mEntry in FEntries.Values do
  begin
    for mProblem in mEntry.FTasks do
    begin
      if SameText(mProblem.Source, ATask) then
      begin
        Inc(Result);
      end;
    end;
  end;
end;

procedure TDpccProblemStore.SetTests(const AProblems: TArray<TPair<string, TDpccProblem>>);
var
  mItem: TPair<string, TDpccProblem>;
  mEntry: TEntry;
  mProblem: TDpccProblem;
begin
  ClearTests;
  for mItem in AProblems do
  begin
    mEntry := Ensure(mItem.Key);
    mProblem := mItem.Value;
    mProblem.Source := cTestSource;
    mEntry.FTests := mEntry.FTests + [mProblem];
    mEntry.FVisibleValid := False;
    Touch(mEntry);
  end;
  if Length(AProblems) > 0 then
  begin
    Inc(FVersion);
  end;
end;

function TDpccProblemStore.ResultId(const AFileName: string): string;
var
  mEntry: TEntry;
begin
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Result := '';
  end
  else
  begin
    Result := mEntry.FResultId;
  end;
end;

function TDpccProblemStore.TextOf(const AFileName: string): string;
var
  mEntry: TEntry;
begin
  mEntry := Find(AFileName);
  if (mEntry = nil) or not mEntry.FTextKnown then
  begin
    Result := '';
  end
  else
  begin
    Result := mEntry.FText;
  end;
end;

function TDpccProblemStore.LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
var
  mEntry: TEntry;
begin
  AText := '';
  mEntry := Find(AFileName);
  if (mEntry = nil) or not mEntry.FTextKnown then
  begin
    Exit(False);
  end;
  if not mEntry.FLinesValid then
  begin
    mEntry.FLines := mEntry.FText.Split([#10]);
    mEntry.FLinesValid := True;
  end;
  Result := (ALine >= 0) and (ALine <= High(mEntry.FLines));
  if Result then
  begin
    AText := mEntry.FLines[ALine].TrimRight([#13]);
  end;
end;

/// <summary>Schlüssel für Doppelte: dieselbe Stelle mit derselben Meldung (Groß-/Kleinschreibung egal).</summary>
function DuplicateKey(const AProblem: TDpccProblem): string;
begin
  Result := IntToStr(AProblem.StartLine) + ':' + IntToStr(AProblem.StartCharacter) + ':' +
    UpperCase(AProblem.Message);
end;

/// <summary>Vom Compiler bestätigte Befunde markieren (#1024); mit AMerge ohne die bestätigende
/// Compilermeldung.</summary>
function Confirmed(const AProblems: TArray<TDpccProblem>; AMerge: Boolean): TArray<TDpccProblem>;
var
  mProblems: TArray<TDpccProblem>;
  mDrop: TArray<Boolean>;
  mIndex, mFound: Integer;
begin
  mProblems := Copy(AProblems);
  SetLength(mDrop, Length(mProblems));
  for mIndex := 0 to High(mProblems) do
  begin
    mFound := -1;
    if not mProblems[mIndex].IsCompiler and (mProblems[mIndex].CompilerCodes <> nil) then
    begin
      mFound := ConfirmingIndex(mProblems, mProblems[mIndex]);
    end;
    if mFound >= 0 then
    begin
      mProblems[mIndex].Confirmed := True;
      mProblems[mIndex].ConfirmedCode := mProblems[mFound].Code;
      mDrop[mFound] := AMerge;
    end;
  end;
  SetLength(Result, Length(mProblems));
  mFound := 0;
  for mIndex := 0 to High(mProblems) do
  begin
    if not mDrop[mIndex] then
    begin
      Result[mFound] := mProblems[mIndex];
      Inc(mFound);
    end;
  end;
  SetLength(Result, mFound);
end;

procedure SortByPosition(var AProblems: TArray<TDpccProblem>);
begin
  TArray.Sort<TDpccProblem>(AProblems, TComparer<TDpccProblem>.Construct(
    function(const A, B: TDpccProblem): Integer
    begin
      Result := A.StartLine - B.StartLine;
      if Result = 0 then
      begin
        Result := A.StartCharacter - B.StartCharacter;
      end;
      if Result = 0 then
      begin
        Result := Ord(A.Severity) - Ord(B.Severity);
      end;
    end));
end;

function TDpccProblemStore.ForFile(const AFileName: string): TArray<TDpccProblem>;
var
  mEntry: TEntry;
  mProblem: TDpccProblem;
  mAll, mVisible: TArray<TDpccProblem>;
  mSeen: TDictionary<string, Boolean>;
  mKey: string;
  mCount: Integer;
begin
  Result := nil;
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Exit;
  end;
  if mEntry.FVisibleValid then
  begin
    Exit(mEntry.FVisible);
  end;
  mAll := mEntry.FCompiler + mEntry.FDpcc + mEntry.FTests + mEntry.FTasks;
  SetLength(mVisible, Length(mAll));
  mCount := 0;
  // Doppelte über eine Tabelle: Große Units haben Tausende Befunde, und das läuft nach jeder Änderung.
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mProblem in mAll do
    begin
      // Inaktive Zweige und uses-Hinweise (#621) sind keine Probleme; ausgeblendete Projektaufgaben (#900) fehlen.
      if mProblem.Unnecessary or mProblem.IsUses or ((FHiddenTasks <> nil) and TaskHidden(mProblem.Source)) then
      begin
        Continue;
      end;
      mKey := DuplicateKey(mProblem);
      if not mSeen.ContainsKey(mKey) then
      begin
        mSeen.Add(mKey, True);
        mVisible[mCount] := mProblem;
        Inc(mCount);
      end;
    end;
  finally
    mSeen.Free;
  end;
  SetLength(mVisible, mCount);
  mVisible := Confirmed(mVisible, FCompilerMerge);
  SortByPosition(mVisible);
  mEntry.FVisible := mVisible;
  mEntry.FVisibleValid := True;
  Result := mVisible;
end;

function TDpccProblemStore.OnLine(const AFileName: string; ALine: Integer): TArray<TDpccProblem>;
var
  mProblem: TDpccProblem;
begin
  Result := nil;
  for mProblem in ForFile(AFileName) do
  begin
    if (ALine >= mProblem.StartLine) and (ALine <= mProblem.EndLine) then
    begin
      Result := Result + [mProblem];
    end;
  end;
end;

function TDpccProblemStore.At(const AFileName: string; ALine, ACharacter: Integer): TArray<TDpccProblem>;
var
  mProblem: TDpccProblem;
begin
  Result := nil;
  for mProblem in ForFile(AFileName) do
  begin
    if mProblem.Contains(ALine, ACharacter) then
    begin
      Result := Result + [mProblem];
    end;
  end;
end;

function TDpccProblemStore.AllFiles: TArray<string>;
var
  mEntry: TEntry;
begin
  Result := nil;
  for mEntry in FEntries.Values do
  begin
    if mEntry.FFromServer then
    begin
      Result := Result + [mEntry.FFileName];
    end;
  end;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(A, B);
    end));
end;

function TDpccProblemStore.Files: TArray<string>;
var
  mEntry: TEntry;
begin
  Result := nil;
  for mEntry in FEntries.Values do
  begin
    if Length(ForFile(mEntry.FFileName)) > 0 then
    begin
      Result := Result + [mEntry.FFileName];
    end;
  end;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := CompareText(A, B);
    end));
end;

end.
