unit dpcc.Core.Commands.Palette;

// Befehlspalette (#502), Teil ohne Open Tools API: Befehle aus IDE-Aktionen
// und dpcc, Verlauf je Benutzer und Rangfolge. Ausgewählt wird wie in der
// Vervollständigung (#229: genauer Name, Anfang, Wortanfänge, Teilfolge),
// gegen die Beschriftung und ersatzweise „Menüpfad Beschriftung“; zuletzt
// eine einfache Teilfolge ohne Wortgrenzen („bpj“ → „Build Project“), weil
// Befehle aus mehreren Wörtern bestehen. Zuletzt und
// häufig genutzte Befehle bekommen einen Zuschlag unter 100 Punkten; ohne
// Eingabe stehen sie oben, danach alphabetisch.
// Mit AKeepOrder (Code-Aktionen, #399) bleibt ohne Eingabe die Reihenfolge der
// Liste, bei Gleichstand ebenso.
// Der Verlauf (palette.json) wird über TDpccDataFile gelesen und atomar
// geschrieben: Eine unbrauchbare Datei liegt danach als .defekt
// daneben, eine gesperrte bleibt unverändert und wird nicht überschrieben.
// Zusatzquelle (#1270, Issues in der Palette): IDpccPaletteSource erfährt
// jede Eingabe und zeigt ihre Treffer als eigene Gruppe unter den Befehlen
// (TDpccPaletteGroup), auch später, wenn die Antwort aus dem Netz kommt.
// TDpccPaletteRows bestimmt die Zeilen (Befehle, Überschrift, Status,
// Einträge), welche wählbar sind und welche Aktion eine Taste auslöst.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Core.Files.DataFile;

type
  TDpccCommand = record
    /// <summary>Eindeutig, z. B. Name der Aktion oder "dpcc.Options".</summary>
    Id: string;
    Caption: string;
    /// <summary>Menüpfad bzw. Kategorie, gedimmt angezeigt ("Projekt › Erzeugen").</summary>
    Path: string;
    ShortCut: string;
    Description: string;
    IsDpcc: Boolean;
    /// <summary>Abzeichen rechts in der Zeile (Zustand eines Issues, #1270); '' ohne.</summary>
    Badge: string;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Wie ein Eintrag einer Zusatzgruppe ausgeführt wird: Enter (Open), Strg+Enter (Start),
  /// Umschalt+Enter (Browse), Strg+C (Copy, die Palette bleibt offen), Alt+Enter (Toggle: Schnellschalter einer
  /// Einstellung umschalten, #1884).</summary>
  TDpccPaletteAction = (Open, Start, Browse, Copy, Toggle);
{$SCOPEDENUMS OFF}

  /// <summary>Gruppe einer Zusatzquelle unter den Befehlen (#1270).</summary>
  TDpccPaletteGroup = record
    /// <summary>Überschrift ("Issues"); '' = keine Gruppe.</summary>
    Title: string;
    /// <summary>Zeile unter der Überschrift ("Suche im Tracker …", Fehler, Tastenhinweis); '' ohne.</summary>
    Status: string;
    /// <summary>Text, dessen Zeichen in den Einträgen hervorgehoben werden.</summary>
    Highlight: string;
    Items: TArray<TDpccCommand>;
    class function None: TDpccPaletteGroup; static;
    class function Create(const ATitle, AStatus, AHighlight: string;
      const AItems: TArray<TDpccCommand>): TDpccPaletteGroup; static;
    function Visible: Boolean;
  end;

  /// <summary>Art einer Zeile: Befehl, Überschrift und Status der Zusatzgruppe, Eintrag der Gruppe.</summary>
{$SCOPEDENUMS ON}
  TDpccPaletteRowKind = (Command, Header, Status, Item);
{$SCOPEDENUMS OFF}

  /// <summary>Zeilen der Palette (#1270): zuerst die Treffer der Befehle, darunter die Zusatzgruppe mit
  /// Überschrift, optionaler Statuszeile und Einträgen. Überschrift und Status sind nicht wählbar.</summary>
  TDpccPaletteRows = record
  private
    FCommands: Integer;
    FGroup: Boolean;
    FStatus: Boolean;
    FItems: Integer;
  public
    class function Create(ACommands: Integer; const AGroup: TDpccPaletteGroup): TDpccPaletteRows; static;
    function Count: Integer;
    /// <summary>Art der Zeile ARow; AIndex: Befehl in der Trefferliste bzw. Eintrag der Gruppe.</summary>
    function Kind(ARow: Integer; out AIndex: Integer): TDpccPaletteRowKind;
    function Selectable(ARow: Integer): Boolean;
    /// <summary>Erste wählbare Zeile; -1 ohne.</summary>
    function First: Integer;
    /// <summary>Von AFrom um ADelta weiter, Überschrift und Status in Schrittrichtung übersprungen (am Rand
    /// zurück); AFrom, wenn es keine wählbare Zeile gibt.</summary>
    function Step(AFrom, ADelta: Integer): Integer;
    /// <summary>Enter auf einem Eintrag: Strg = Start, sonst Umschalt = Browse, sonst Open.</summary>
    class function ActionOf(ACtrl, AShift: Boolean): TDpccPaletteAction; overload; static;
    /// <summary>Wie oben; Alt+Enter = Toggle (#1884), vor Strg und Umschalt.</summary>
    class function ActionOf(ACtrl, AShift, AAlt: Boolean): TDpccPaletteAction; overload; static;
  end;

  /// <summary>Zusatzquelle der Palette (#1270), z. B. Issues im Tracker. Alle Aufrufe im Hauptthread.</summary>
  IDpccPaletteSource = interface
    ['{D1D5D951-0AD7-4D3E-80D8-5021BD5F0C41}']
    /// <summary>Palette geöffnet; AShow zeigt bzw. ersetzt die Gruppe, auch später (nach Closed wirkungslos).
    /// </summary>
    procedure Opened(const AShow: TProc<TDpccPaletteGroup>);
    /// <summary>Eingabe geändert (auch auf leer).</summary>
    procedure Changed(const APattern: string);
    /// <summary>Eintrag der Gruppe ausgeführt; außer bei Copy ist die Palette danach geschlossen.</summary>
    procedure Execute(const AItem: TDpccCommand; AAction: TDpccPaletteAction);
    /// <summary>Palette geschlossen: laufende Anfragen abbrechen, AShow nicht mehr rufen.</summary>
    procedure Closed;
  end;

  /// <summary>Liefert beim Öffnen der Palette eine Zusatzquelle (#1270, #1455); ein Modul stellt es über seinen
  /// Scope bereit (etwa „Meine Issues“). nil = gerade keine Quelle. Hauptthread.</summary>
  IDpccPaletteSourceProvider = interface
    ['{C737B249-C8ED-44D7-A33E-BEB867FED4B5}']
    function PaletteSource: IDpccPaletteSource;
  end;

  /// <summary>dpcc-Befehle anmelden (Palette, #520); ohne VCL und Open Tools API. Features melden ihre Befehle
  /// darüber an, statt die Palette der IDE-Schicht zu importieren. Ohne Referenzzählung: Die Palette
  /// gehört der Composition; Empfänger speichern die Schnittstelle nicht.</summary>
  IDpccCommandRegistry = interface
    ['{57AA1265-60F8-4655-BC7B-1AE31AC48481}']
    /// <summary>dpcc-Befehl für die Palette (Beschriftung mit „dpcc: “ davor).</summary>
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc); overload;
    /// <summary>Wie oben; der Befehl erscheint nur, solange AVisible True liefert (#520).</summary>
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc;
      const AVisible: TFunc<Boolean>); overload;
  end;

  TDpccCommandHistory = class
  private type
    TEntry = record
      Count: Integer;
      Last: Int64;
    end;
  private
    FEntries: TDictionary<string, TEntry>;
    FTick: Int64;
    /// <summary>Vorhandene Datei, die LoadFromFile nicht lesen konnte: SaveToFile überschreibt sie nicht.</summary>
    FKept: string;
    FKind: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Executed(const AId: string);
    /// <summary>Zuschlag 0..99: zuletzt ausgeführt am meisten, Häufigkeit dazu.</summary>
    function Boost(const AId: string): Integer;
    /// <summary>Übernimmt AText ({"Befehl": [Anzahl, Zeitpunkt], …}); Einträge anderer Form fallen weg. False,
    /// wenn AText kein Objekt ist.</summary>
    function Parse(const AText: string): Boolean;
    /// <summary>Liest über TDpccDataFile.Load; fehlt die Datei oder ist sie unbrauchbar, beginnt der Verlauf
    /// leer. Ergebnis Kept: Die Datei bleibt unverändert, SaveToFile schreibt sie nicht.</summary>
    function LoadFromFile(const AFileName: string): TDpccDataLoad;
    /// <summary>Schreibt atomar; False, wenn LoadFromFile die vorhandene Datei nicht lesen konnte.</summary>
    function SaveToFile(const AFileName: string): Boolean;
    /// <summary>Name der Ablage im Protokoll; Vorgabe „Verlauf der Befehlspalette“ (Schnell öffnen nutzt die
    /// Klasse auch).</summary>
    property Kind: string read FKind write FKind;
  end;

  TDpccCommandPalette = class
  public
    /// <summary>Indizes der passenden Befehle, beste zuerst. AKeepOrder: ohne Eingabe und bei
    /// Gleichstand die Reihenfolge von ACommands statt alphabetisch.</summary>
    class function Order(const ACommands: TArray<TDpccCommand>; const APattern: string;
      AHistory: TDpccCommandHistory; AKeepOrder: Boolean): TArray<Integer>; overload; static;
    /// <summary>Wie oben mit AKeepOrder = False.</summary>
    class function Order(const ACommands: TArray<TDpccCommand>; const APattern: string;
      AHistory: TDpccCommandHistory): TArray<Integer>; overload; static;
    /// <summary>Beschriftung ohne Kürzelzeichen: "&amp;Datei" → "Datei", "&amp;&amp;" → "&amp;", "..." am Ende
    /// weg.</summary>
    class function CleanCaption(const ACaption: string): string; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  System.Generics.Defaults,
  dpcc.Core.Completion.Matching;

{ TDpccPaletteGroup }

class function TDpccPaletteGroup.None: TDpccPaletteGroup;
begin
  Result.Title := '';
  Result.Status := '';
  Result.Highlight := '';
  Result.Items := nil;
end;

class function TDpccPaletteGroup.Create(const ATitle, AStatus, AHighlight: string;
  const AItems: TArray<TDpccCommand>): TDpccPaletteGroup;
begin
  Result.Title := ATitle;
  Result.Status := AStatus;
  Result.Highlight := AHighlight;
  Result.Items := AItems;
end;

function TDpccPaletteGroup.Visible: Boolean;
begin
  Result := Title <> '';
end;

{ TDpccPaletteRows }

class function TDpccPaletteRows.Create(ACommands: Integer; const AGroup: TDpccPaletteGroup): TDpccPaletteRows;
begin
  Result.FCommands := ACommands;
  if Result.FCommands < 0 then
  begin
    Result.FCommands := 0;
  end;
  Result.FGroup := AGroup.Visible;
  Result.FStatus := Result.FGroup and (AGroup.Status <> '');
  Result.FItems := 0;
  if Result.FGroup then
  begin
    Result.FItems := Length(AGroup.Items);
  end;
end;

function TDpccPaletteRows.Count: Integer;
begin
  Result := FCommands;
  if not FGroup then
  begin
    Exit;
  end;
  Inc(Result, 1 + FItems);
  if FStatus then
  begin
    Inc(Result);
  end;
end;

function TDpccPaletteRows.Kind(ARow: Integer; out AIndex: Integer): TDpccPaletteRowKind;
begin
  AIndex := ARow;
  Result := TDpccPaletteRowKind.Command;
  if ARow < FCommands then
  begin
    Exit;
  end;
  AIndex := ARow - FCommands;
  if AIndex = 0 then
  begin
    Exit(TDpccPaletteRowKind.Header);
  end;
  Dec(AIndex);
  if FStatus then
  begin
    if AIndex = 0 then
    begin
      Exit(TDpccPaletteRowKind.Status);
    end;
    Dec(AIndex);
  end;
  Result := TDpccPaletteRowKind.Item;
end;

function TDpccPaletteRows.Selectable(ARow: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := (ARow >= 0) and (ARow < Count) and
    (Kind(ARow, mIndex) in [TDpccPaletteRowKind.Command, TDpccPaletteRowKind.Item]);
end;

function TDpccPaletteRows.First: Integer;
var
  mRow: Integer;
begin
  for mRow := 0 to Count - 1 do
  begin
    if Selectable(mRow) then
    begin
      Exit(mRow);
    end;
  end;
  Result := -1;
end;

function TDpccPaletteRows.Step(AFrom, ADelta: Integer): Integer;
var
  mRow, mDirection: Integer;
begin
  Result := AFrom;
  if (Count = 0) or (ADelta = 0) then
  begin
    Exit;
  end;
  mDirection := Sign(ADelta);
  mRow := EnsureRange(AFrom + ADelta, 0, Count - 1);
  while (mRow >= 0) and (mRow < Count) and not Selectable(mRow) do
  begin
    Inc(mRow, mDirection);
  end;
  // Am Rand nur Überschrift oder Status: zurück zur nächsten wählbaren Zeile.
  if (mRow < 0) or (mRow >= Count) then
  begin
    mRow := EnsureRange(AFrom + ADelta, 0, Count - 1);
    while (mRow >= 0) and (mRow < Count) and not Selectable(mRow) do
    begin
      Dec(mRow, mDirection);
    end;
  end;
  if (mRow >= 0) and (mRow < Count) then
  begin
    Result := mRow;
  end;
end;

class function TDpccPaletteRows.ActionOf(ACtrl, AShift, AAlt: Boolean): TDpccPaletteAction;
begin
  if AAlt then
  begin
    Exit(TDpccPaletteAction.Toggle);
  end;
  Result := ActionOf(ACtrl, AShift);
end;

class function TDpccPaletteRows.ActionOf(ACtrl, AShift: Boolean): TDpccPaletteAction;
begin
  if ACtrl then
  begin
    Result := TDpccPaletteAction.Start;
  end
  else if AShift then
  begin
    Result := TDpccPaletteAction.Browse;
  end
  else
  begin
    Result := TDpccPaletteAction.Open;
  end;
end;

{ TDpccCommandHistory }

constructor TDpccCommandHistory.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TEntry>.Create;
  FKind := 'Verlauf der Befehlspalette';
end;

destructor TDpccCommandHistory.Destroy;
begin
  FEntries.Free;
  inherited;
end;

procedure TDpccCommandHistory.Executed(const AId: string);
var
  mEntry: TEntry;
begin
  if not FEntries.TryGetValue(AId, mEntry) then
  begin
    mEntry := Default(TEntry);
  end;
  Inc(mEntry.Count);
  Inc(FTick);
  mEntry.Last := FTick;
  FEntries.AddOrSetValue(AId, mEntry);
end;

function TDpccCommandHistory.Boost(const AId: string): Integer;
var
  mEntry: TEntry;
begin
  Result := 0;
  if not FEntries.TryGetValue(AId, mEntry) then
  begin
    Exit;
  end;
  // Der zuletzt ausgeführte Befehl steht vorn (bis 70), Häufigkeit gibt bis 29 dazu.
  Result := Max(0, 70 - Integer(FTick - mEntry.Last) * 10) + Min(29, mEntry.Count * 3);
end;

function TDpccCommandHistory.Parse(const AText: string): Boolean;
var
  mRoot: TJSONValue;
  mPair: TJSONPair;
  mValues: TJSONArray;
  mEntry: TEntry;
begin
  FEntries.Clear;
  FTick := 0;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := mRoot is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    for mPair in TJSONObject(mRoot) do
    begin
      // Früher brach ein kurzes oder falsch getyptes Paar das Lesen mit einer Ausnahme ab.
      if not (mPair.JsonValue is TJSONArray) then
      begin
        Continue;
      end;
      mValues := TJSONArray(mPair.JsonValue);
      if (mValues.Count < 2) or not mValues.Items[0].TryGetValue<Integer>(mEntry.Count) or
        not mValues.Items[1].TryGetValue<Int64>(mEntry.Last) then
      begin
        Continue;
      end;
      FEntries.AddOrSetValue(mPair.JsonString.Value, mEntry);
      FTick := Max(FTick, mEntry.Last);
    end;
  finally
    mRoot.Free;
  end;
end;

function TDpccCommandHistory.LoadFromFile(const AFileName: string): TDpccDataLoad;
begin
  FEntries.Clear;
  FTick := 0;
  FKept := '';
  Result := TDpccDataFile.Load(AFileName, FKind,
    function(const AText: string): Boolean
    begin
      Result := Parse(AText);
    end);
  if not TDpccDataFile.Writable(Result) then
  begin
    FKept := AFileName;
  end;
  if Result <> TDpccDataLoad.Loaded then
  begin
    FEntries.Clear;
    FTick := 0;
  end;
end;

function TDpccCommandHistory.SaveToFile(const AFileName: string): Boolean;
var
  mRoot: TJSONObject;
  mPair: TPair<string, TEntry>;
begin
  Result := not SameFileName(AFileName, FKept);
  if not Result then
  begin
    Exit;
  end;
  mRoot := TJSONObject.Create;
  try
    for mPair in FEntries do
    begin
      mRoot.AddPair(mPair.Key, TJSONArray.Create.Add(mPair.Value.Count).Add(mPair.Value.Last));
    end;
    TDpccDataFile.Write(AFileName, mRoot.ToJSON);
  finally
    mRoot.Free;
  end;
end;

/// <summary>Alle Zeichen von APattern kommen in AText in dieser Reihenfolge vor (Großschreibung egal).</summary>
function IsSubsequence(const APattern, AText: string): Boolean;
var
  mPatternIndex, mTextIndex: Integer;
begin
  mPatternIndex := 1;
  for mTextIndex := 1 to Length(AText) do
  begin
    if (mPatternIndex <= Length(APattern)) and (UpCase(AText[mTextIndex]) = UpCase(APattern[mPatternIndex])) then
    begin
      Inc(mPatternIndex);
    end;
  end;
  Result := mPatternIndex > Length(APattern);
end;

const
  cScoreLoose = 100;

{ TDpccCommandPalette }

class function TDpccCommandPalette.CleanCaption(const ACaption: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := 1;
  while mIndex <= Length(ACaption) do
  begin
    if ACaption[mIndex] = '&' then
    begin
      if (mIndex < Length(ACaption)) and (ACaption[mIndex + 1] = '&') then
      begin
        Result := Result + '&';
        Inc(mIndex);
      end;
    end
    else
    begin
      Result := Result + ACaption[mIndex];
    end;
    Inc(mIndex);
  end;
  Result := Trim(Result);
  if Result.EndsWith('...') then
  begin
    Result := TrimRight(Copy(Result, 1, Length(Result) - 3));
  end
  else if Result.EndsWith('…') then
  begin
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
  end;
end;

class function TDpccCommandPalette.Order(const ACommands: TArray<TDpccCommand>; const APattern: string;
  AHistory: TDpccCommandHistory): TArray<Integer>;
begin
  Result := Order(ACommands, APattern, AHistory, False);
end;

/// <summary>Treffergüte von ACommand zu APattern: Beschriftung, ersatzweise mit Menüpfad ("projekt erz" findet
/// „Erzeugen“ unter „Projekt“, halbe Güte), zuletzt lose als Teilfolge; NoMatch ohne Treffer.</summary>
function MatchScore(const APattern: string; const ACommand: TDpccCommand): Integer;
begin
  Result := TDpccCompletionMatcher.Score(APattern, ACommand.Caption);
  if (Result = TDpccCompletionMatcher.cNoMatch) and (ACommand.Path <> '') then
  begin
    Result := TDpccCompletionMatcher.Score(APattern, ACommand.Path + ' ' + ACommand.Caption);
    if Result <> TDpccCompletionMatcher.cNoMatch then
    begin
      Result := Result div 2;
    end;
  end;
  if (Result = TDpccCompletionMatcher.cNoMatch) and IsSubsequence(APattern.Replace(' ', ''), ACommand.Caption) then
  begin
    Result := cScoreLoose;
  end;
end;

/// <summary>Reihenfolge der Treffer: ohne Muster nach Verlauf, sonst nach Güte und Verlauf; bei Gleichstand nach
/// Beschriftung (nicht mit AKeepOrder), zuletzt nach Index.</summary>
function OrderComparer(const ACommands: TArray<TDpccCommand>; const AScores, ABoosts: TArray<Integer>;
  const APattern: string; AKeepOrder: Boolean): IComparer<Integer>;
begin
  Result := TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      if APattern = '' then
      begin
        Result := ABoosts[B] - ABoosts[A];
      end
      else
      begin
        Result := (AScores[B] + ABoosts[B]) - (AScores[A] + ABoosts[A]);
      end;
      if (Result = 0) and not AKeepOrder then
      begin
        Result := CompareText(ACommands[A].Caption, ACommands[B].Caption);
      end;
      if Result = 0 then
      begin
        Result := A - B;
      end;
    end);
end;

class function TDpccCommandPalette.Order(const ACommands: TArray<TDpccCommand>; const APattern: string;
  AHistory: TDpccCommandHistory; AKeepOrder: Boolean): TArray<Integer>;
var
  mScores, mBoosts: TArray<Integer>;
  mFound: TList<Integer>;
  mIndex, mScore: Integer;
begin
  SetLength(mScores, Length(ACommands));
  SetLength(mBoosts, Length(ACommands));
  mFound := TList<Integer>.Create;
  try
    for mIndex := 0 to High(ACommands) do
    begin
      mScore := MatchScore(APattern, ACommands[mIndex]);
      if mScore = TDpccCompletionMatcher.cNoMatch then
      begin
        Continue;
      end;
      mScores[mIndex] := mScore;
      if AHistory <> nil then
      begin
        mBoosts[mIndex] := AHistory.Boost(ACommands[mIndex].Id);
      end;
      mFound.Add(mIndex);
    end;
    mFound.Sort(OrderComparer(ACommands, mScores, mBoosts, APattern, AKeepOrder));
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

end.