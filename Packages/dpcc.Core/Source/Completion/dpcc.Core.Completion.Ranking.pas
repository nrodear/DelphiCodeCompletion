unit dpcc.Core.Completion.Ranking;

// Reihenfolge der Liste (#229, #418, #419, #422), ohne Fenster:
//   - Treffer nach Güte (TDpccCompletionMatcher), dazu ein Lernzuschlag unter
//     100 Punkten, damit ein besserer Treffer immer vor einem gelernten bleibt.
//   - Ohne getipptes Präfix und mit GroupInherited: eigene Member zuerst, dann
//     je Vorfahr eine Gruppe mit Überschrift (in der Reihenfolge ein -1 vor dem
//     ersten Eintrag der Gruppe). Mit Präfix keine Überschriften; bei gleicher
//     Güte steht der eigene Member vor dem geerbten.
//   - Erwarteter Typ (#417, #444): passende Einträge oben, darunter die
//     übrigen, je mit Überschrift, auch mit Präfix. Innerhalb der Gruppe wie
//     oben. Aktionen („Neue Methode …“) passen immer und stehen zuletzt.
//   - Werte einer erwarteten Aufzählung (#448) stehen in der passenden Gruppe
//     zuerst, ohne Präfix in Deklarationsreihenfolge (Ordinal), auch vor
//     Gelerntem.
//   - Angeheftete Einträge („Alle Werte einfügen“, #449) passen immer. Ohne
//     Präfix stehen sie ganz oben; mit Präfix hinter den Treffern, damit Enter
//     nach "skC" den Wert übernimmt und nicht alle Zweige.
//   - Deklarationen eines unbekannten Namens (#471) stehen als Aktionen am
//     Ende, unter der Überschrift UnknownHeader („Name ist unbekannt“).
//   - Hinweise „n Methoden von I fehlen“ (#466) passen immer und stehen ganz oben, auch mit Präfix; der
//     Controller wählt sie nicht vor.
//   - Komponenten aus dem Formular (#455) stehen als eigene Gruppe mit Überschrift („Formular frmMain“) vor allen
//     übrigen Bezeichnern. Passt eine nur über ihren Typ ("button" → btnSave: TButton), hat der Server sie schon
//     gefiltert; sie bleibt sichtbar und steht hinter den Namenstreffern.
//   - Sender mit Typumwandlung (#480): eine Überschrift „Sender ist TButton · btnSave, btnLoad“ über der Liste.
//   - uses-Abschnitt (#469, Item.UsesGroup): Projekt-Units vor RTL/VCL vor Drittanbietern, je Gruppe eine
//     Überschrift.
//   - Favoriten (#458, Item.Favorite): vor allen anderen Gruppen, auch vor Hinweisen und Formularkomponenten,
//     unabhängig von Lernen und Rang, aber nur, wenn sie zum getippten Präfix passen. Ohne Überschrift; die
//     Gruppen danach beginnen wie am Anfang der Liste.
//   - Typkonvertierung (#490): Ein Umwandlungseintrag (Conversion) steht direkt über seinem Original
//     (ConvertFrom) und nur, wenn das Original sichtbar ist; er zählt weder zu Gruppen noch zum Rest.
//   - Rest der Liste (#497, TDpccListMode): Filter zeigt nur Treffer. All hängt mit Präfix die übrigen Einträge
//     des Kontexts ohne Überschrift hinter die Treffer, Rest unter der Überschrift RestHeader („Weitere
//     Einträge“, gedämpft). Beide in Rang- und Namensfolge, ohne Aktionen, Hinweise und Tippfehler-Treffer,
//     vor der Gruppe des unbekannten Namens.
// Die Filter-Chips (Einschränkung auf eine Art, #422) gibt es seit S7a nicht mehr: Die schlichte Liste (S6) zeigt
// sie nicht.

interface

uses
  System.SysUtils,
  dpcc.Core.Completion.Contract;

{$SCOPEDENUMS ON}

type
  /// <summary>Was mit Präfix außer den Treffern sichtbar bleibt (#497).</summary>
  TDpccListMode = (Filter, All, Rest);

  /// <summary>Wo der Listenmodus gilt (#497): nur in Mitgliederlisten nach "." oder überall.</summary>
  TDpccListScope = (Members, Everywhere);

  /// <summary>Schreibweise der Listenmodi in den Einstellungen.</summary>
  TDpccListModes = class
  public const
    cModeNames: array[TDpccListMode] of string = ('filter', 'all', 'rest');
    cScopeNames: array[TDpccListScope] of string = ('members', 'everywhere');
  public
    /// <summary>Modus zu AName (ohne Groß-/Kleinschreibung); Filter bei Unbekanntem.</summary>
    class function ModeOf(const AName: string): TDpccListMode; static;
    /// <summary>Geltungsbereich zu AName; Members bei Unbekanntem.</summary>
    class function ScopeOf(const AName: string): TDpccListScope; static;
  end;

  /// <summary>Lernzuschlag 0..99 je Eintragsindex.</summary>
  TDpccBoostFunc = reference to function(AIndex: Integer): Integer;

  TDpccRankOptions = record
    GroupInherited: Boolean;
    Boost: TDpccBoostFunc;
    /// <summary>Übrige Einträge mit Präfix (#497); Filter = nur Treffer.</summary>
    ListMode: TDpccListMode;
    class function Defaults: TDpccRankOptions; static;
  end;

  TDpccRanking = class
  public const
    /// <summary>Markiert in der Reihenfolge eine Gruppenüberschrift vor dem nächsten Eintrag.</summary>
    cHeader = -1;
    /// <summary>Überschrift „Meintest du“ vor den Tippfehler-Treffern (#485).</summary>
    cTypoHeader = -2;
    /// <summary>Überschrift „Name ist unbekannt“ vor den Deklarationen (#471).</summary>
    cUnknownHeader = -3;
    /// <summary>Überschrift „Weitere Einträge“ vor dem gedämpften Rest (#497, TDpccListMode.Rest).</summary>
    cRestHeader = -4;
    /// <summary>Höchstens so viele Tippfehler-Treffer; nur bei weniger regulären als MinRegular.</summary>
    cMaxTypos = 5;
    cMinRegular = 3;
  public
    /// <summary>Ähnliche Namen zu APattern als TypoHeader + Indizes (#485); leer ohne.</summary>
    class function Typos(const AItems: TDpccCompletionItems; const APattern: string;
      const AOptions: TDpccRankOptions; const AScores, ABoosts: TArray<Integer>): TArray<Integer>; static;
    /// <summary>Anzeigereihenfolge: Indizes in AItems, Header (-1) vor Gruppen geerbter Member.</summary>
    class function Order(const AItems: TDpccCompletionItems; const APattern: string;
      const AOptions: TDpccRankOptions): TArray<Integer>; overload; static;
    /// <summary>Wie oben; ARestStart ist die Position des ersten Eintrags ohne Treffer (#497), -1 ohne.</summary>
    class function Order(const AItems: TDpccCompletionItems; const APattern: string;
      const AOptions: TDpccRankOptions; out ARestStart: Integer): TArray<Integer>; overload; static;
    /// <summary>Einträge ohne Überschriften.</summary>
    class function ItemCount(const AOrder: TArray<Integer>): Integer; static;
    /// <summary>Überschrift statt Eintrag (Header, TypoHeader)?</summary>
    class function IsHeader(AValue: Integer): Boolean; static;
    /// <summary>Nur „Meintest du“-Einträge, kein regulärer Treffer (#485): Die Fußzeile nennt dann
    /// „Keine Treffer für ‚…‘“.</summary>
    class function OnlyTypos(const AOrder: TArray<Integer>): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  dpcc.Core.Completion.Matching;

{ TDpccRankOptions }

class function TDpccRankOptions.Defaults: TDpccRankOptions;
begin
  Result.GroupInherited := False;
  Result.Boost := nil;
  Result.ListMode := TDpccListMode.Filter;
end;

{ TDpccListModes }

class function TDpccListModes.ModeOf(const AName: string): TDpccListMode;
var
  mMode: TDpccListMode;
begin
  Result := TDpccListMode.Filter;
  for mMode := Low(TDpccListMode) to High(TDpccListMode) do
  begin
    if SameText(Trim(AName), cModeNames[mMode]) then
    begin
      Result := mMode;
    end;
  end;
end;

class function TDpccListModes.ScopeOf(const AName: string): TDpccListScope;
var
  mScope: TDpccListScope;
begin
  Result := TDpccListScope.Members;
  for mScope := Low(TDpccListScope) to High(TDpccListScope) do
  begin
    if SameText(Trim(AName), cScopeNames[mScope]) then
    begin
      Result := mScope;
    end;
  end;
end;

{ TDpccRanking }

function NameOf(const AItem: TDpccCompletionItem): string;
begin
  if AItem.FilterText <> '' then
  begin
    Result := AItem.FilterText;
  end
  else
  begin
    Result := AItem.Name;
  end;
end;

/// <summary>Bereichsstufe zum Sortieren (#488): ohne Angabe hinter allen Stufen.</summary>
function ScopeRank(const AItem: TDpccCompletionItem): Integer;
begin
  if AItem.Scope > 0 then
  begin
    Result := AItem.Scope;
  end
  else
  begin
    Result := 9;
  end;
end;

/// <summary>Gruppe im uses-Abschnitt (#469): 0 = Projekt (oder keine), 1 = RTL/VCL, 2 = Drittanbieter.</summary>
function UsesRank(const AItem: TDpccCompletionItem): Integer;
begin
  if AItem.UsesGroup = 'rtl' then
  begin
    Result := 1;
  end
  else if AItem.UsesGroup = 'library' then
  begin
    Result := 2;
  end
  else
  begin
    Result := 0;
  end;
end;

/// <summary>Schlüssel einer aktiven Variante: Name und Unit.</summary>
function ActiveKey(const AItem: TDpccCompletionItem): string;
begin
  Result := UpperCase(AItem.Name + #0 + AItem.DeclaringUnit);
end;

/// <summary>Schlüssel der aktiven Variante, zu der AItem gehört.</summary>
function OriginKey(const AItem: TDpccCompletionItem): string;
begin
  Result := UpperCase(AItem.Name + #0 + AItem.SameNameOf);
end;

/// <summary>Hängt die Varianten zur aktiven mit dem Schlüssel AKey in ihrer Reihenfolge an AMoved.</summary>
procedure AddVariants(const AItems: TDpccCompletionItems; AFound, AMoved: TList<Integer>; const AKey: string);
var
  mVariant: Integer;
begin
  for mVariant in AFound do
  begin
    if (AItems[mVariant].SameNameOf <> '') and (OriginKey(AItems[mVariant]) = AKey) then
    begin
      AMoved.Add(mVariant);
    end;
  end;
end;

/// <summary>Gleichnamige Varianten aus anderen Units (#475) direkt hinter die aktive, in ihrer Reihenfolge; ohne
/// aktive in der Liste bleiben sie, wo sie sind.</summary>
procedure MoveVariants(const AItems: TDpccCompletionItems; AFound: TList<Integer>);
var
  mActives: TDictionary<string, Boolean>;
  mMoved: TList<Integer>;
  mIndex: Integer;
begin
  mActives := TDictionary<string, Boolean>.Create;
  mMoved := TList<Integer>.Create;
  try
    for mIndex in AFound do
    begin
      if AItems[mIndex].SameNameActive then
      begin
        mActives.AddOrSetValue(ActiveKey(AItems[mIndex]), True);
      end;
    end;
    if mActives.Count = 0 then
    begin
      Exit;
    end;
    for mIndex in AFound do
    begin
      if AItems[mIndex].SameNameOf = '' then
      begin
        mMoved.Add(mIndex);
        if AItems[mIndex].SameNameActive then
        begin
          AddVariants(AItems, AFound, mMoved, ActiveKey(AItems[mIndex]));
        end;
      end
      else if not mActives.ContainsKey(OriginKey(AItems[mIndex])) then
      begin
        mMoved.Add(mIndex);
      end;
    end;
    AFound.Clear;
    AFound.AddRange(mMoved);
  finally
    mMoved.Free;
    mActives.Free;
  end;
end;

/// <summary>Nach "inherited " (#482): 0 = gleiche Parameter, 1 = andere Überladung, 2 = weiterer Konstruktor
/// bzw. Destruktor, 3 = übrige Einträge.</summary>
function InheritedRank(const AItem: TDpccCompletionItem): Integer;
begin
  if AItem.InheritedMatch = 'same' then
  begin
    Result := 0;
  end
  else if AItem.InheritedMatch = 'overload' then
  begin
    Result := 1;
  end
  else if AItem.InheritedMatch = 'other' then
  begin
    Result := 2;
  end
  else
  begin
    Result := 3;
  end;
end;

/// <summary>0 = passt zum erwarteten Typ, 1 = übrige, 2 = ohne erwarteten Typ.</summary>
function GroupOf(const AItem: TDpccCompletionItem; AAnyFits: Boolean): Integer;
begin
  // Gruppen nur, wenn etwas passt: Teilergebnisse (#616) behalten den erwarteten Typ, auch wenn erst ein
  // späteres Teil einen passenden Eintrag bringt.
  if not AAnyFits or (AItem.ExpectedType = '') then
  begin
    Result := 2;
  end
  else if AItem.Fits then
  begin
    Result := 0;
  end
  else
  begin
    Result := 1;
  end;
end;

class function TDpccRanking.Order(const AItems: TDpccCompletionItems; const APattern: string;
  const AOptions: TDpccRankOptions): TArray<Integer>;
var
  mRestStart: Integer;
begin
  Result := Order(AItems, APattern, AOptions, mRestStart);
end;

/// <summary>Weder Hinweis noch angeheftet noch Deklaration eines unbekannten Namens.</summary>
function IsPlainItem(const AItem: TDpccCompletionItem): Boolean;
begin
  Result := not AItem.Hint and not AItem.Pinned and (AItem.Unknown = '');
end;

/// <summary>Gehört AItem ohne Treffer (AScore) in den Rest der Liste (#497)?</summary>
function IsRestCandidate(const AItem: TDpccCompletionItem; AScore: Integer): Boolean;
begin
  Result := (AScore = TDpccCompletionMatcher.cNoMatch) and not AItem.IsAction and (AItem.Conversion = '') and
    IsPlainItem(AItem);
end;

/// <summary>Einträge ohne Treffer für den Rest der Liste (#497): keine Aktionen, Hinweise oder angehefteten
/// Einträge, nicht schon in AShown; in Rang- und Namensfolge.</summary>
function RestOf(const AItems: TDpccCompletionItems; const AScores, AShown: TArray<Integer>): TArray<Integer>;
var
  mItems: TDpccCompletionItems;
  mShown: TArray<Boolean>;
  mRest: TList<Integer>;
  mIndex: Integer;
begin
  mItems := AItems;
  SetLength(mShown, Length(mItems));
  for mIndex in AShown do
  begin
    if mIndex >= 0 then
    begin
      mShown[mIndex] := True;
    end;
  end;
  mRest := TList<Integer>.Create;
  try
    for mIndex := 0 to High(mItems) do
    begin
      if not mShown[mIndex] and IsRestCandidate(mItems[mIndex], AScores[mIndex]) then
      begin
        mRest.Add(mIndex);
      end;
    end;
    mRest.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Ord(mItems[A].Unavailable) - Ord(mItems[B].Unavailable);
        if Result = 0 then
        begin
          Result := mItems[A].Rank - mItems[B].Rank;
        end;
        if Result = 0 then
        begin
          Result := CompareText(mItems[A].Name, mItems[B].Name);
        end;
        if Result = 0 then
        begin
          Result := A - B;
        end;
      end));
    Result := mRest.ToArray;
  finally
    mRest.Free;
  end;
end;

/// <summary>Umwandlungseinträge (#490) je direkt vor ihr Original in AOrder; jeder höchstens einmal.</summary>
function WithConversions(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>): TArray<Integer>;
var
  mPlaced: TArray<Boolean>;
  mIndex, mConversion: Integer;
  mAny: Boolean;
begin
  mAny := False;
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].Conversion <> '' then
    begin
      mAny := True;
    end;
  end;
  if not mAny then
  begin
    Exit(AOrder);
  end;
  SetLength(mPlaced, Length(AItems));
  Result := nil;
  for mIndex in AOrder do
  begin
    if mIndex >= 0 then
    begin
      for mConversion := 0 to High(AItems) do
      begin
        if not mPlaced[mConversion] and (AItems[mConversion].Conversion <> '') and
          SameText(AItems[mConversion].ConvertFrom, AItems[mIndex].Name) then
        begin
          mPlaced[mConversion] := True;
          Result := Result + [mConversion];
          Break;
        end;
      end;
    end;
    Result := Result + [mIndex];
  end;
end;

/// <summary>Überschrift vor AItem: UnknownHeader vor den Deklarationen eines unbekannten Namens (#471), sonst
/// Header.</summary>
function HeaderOf(const AItem: TDpccCompletionItem): Integer;
begin
  if AItem.Unknown <> '' then
  begin
    Result := TDpccRanking.cUnknownHeader;
  end
  else
  begin
    Result := TDpccRanking.cHeader;
  end;
end;

type
  /// <summary>Stand beim Einfügen der Überschriften: Gruppe, Tiefe und Klasse des vorigen Eintrags.</summary>
  TArrangeState = record
    Group: Integer;
    Depth: Integer;
    Container: string;
  end;

  /// <summary>Bewertet und ordnet die Einträge für TDpccRanking.Order.</summary>
  TRanker = class
  private
    FItems: TDpccCompletionItems;
    FOptions: TDpccRankOptions;
    FScores: TArray<Integer>;
    FBoosts: TArray<Integer>;
    FAnyFits: Boolean;
    FNoPattern: Boolean;
    FGrouped: Boolean;
    /// <summary>Leerer Eintrag als Vorgänger des ersten nach den Favoriten.</summary>
    FNone: TDpccCompletionItem;
    function ScoreOf(AIndex: Integer; const APattern: string): Integer;
    procedure Collect(const APattern: string; AFound: TList<Integer>);
    function CompareKind(A, B: Integer): Integer;
    function CompareGroup(A, B: Integer): Integer;
    function CompareGrouped(A, B: Integer): Integer;
    function CompareScored(A, B: Integer): Integer;
    function Compare(A, B: Integer): Integer;
    function NeedsHeader(const AItem, APrevious: TDpccCompletionItem; AIsFirst: Boolean;
      const AState: TArrangeState): Boolean;
    function FollowingHeader(const AItem, APrevious: TDpccCompletionItem; const AState: TArrangeState): Boolean;
    function Arrange(AFound: TList<Integer>): TArray<Integer>;
  public
    constructor Create(const AItems: TDpccCompletionItems; const APattern: string;
      const AOptions: TDpccRankOptions);
    /// <summary>Treffer sortiert, mit Überschriften, ohne Umwandlungen.</summary>
    function Order(const APattern: string): TArray<Integer>;
    property Scores: TArray<Integer> read FScores;
    property Boosts: TArray<Integer> read FBoosts;
  end;

constructor TRanker.Create(const AItems: TDpccCompletionItems; const APattern: string;
  const AOptions: TDpccRankOptions);
var
  mIndex: Integer;
begin
  inherited Create;
  FItems := AItems;
  FOptions := AOptions;
  SetLength(FScores, Length(FItems));
  SetLength(FBoosts, Length(FItems));
  FGrouped := FOptions.GroupInherited and (APattern = '');
  FNoPattern := APattern = '';
  FAnyFits := False;
  for mIndex := 0 to High(FItems) do
  begin
    if FItems[mIndex].Fits then
    begin
      FAnyFits := True;
      Break;
    end;
  end;
  FNone := Default(TDpccCompletionItem);
end;

function TRanker.ScoreOf(AIndex: Integer; const APattern: string): Integer;
begin
  if FItems[AIndex].IsAction or FItems[AIndex].Pinned or FItems[AIndex].Hint or FItems[AIndex].ByType then
  begin
    Result := 0;
  end
  else
  begin
    Result := TDpccCompletionMatcher.Score(APattern, NameOf(FItems[AIndex]));
  end;
end;

procedure TRanker.Collect(const APattern: string; AFound: TList<Integer>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FItems) do
  begin
    FScores[mIndex] := TDpccCompletionMatcher.cNoMatch;
    // Umwandlungen (#490) setzt WithConversions vor ihr Original.
    if FItems[mIndex].Conversion <> '' then
    begin
      Continue;
    end;
    FScores[mIndex] := ScoreOf(mIndex, APattern);
    if FScores[mIndex] = TDpccCompletionMatcher.cNoMatch then
    begin
      Continue;
    end;
    if Assigned(FOptions.Boost) then
    begin
      FBoosts[mIndex] := EnsureRange(FOptions.Boost(mIndex), 0, 99);
    end;
    AFound.Add(mIndex);
  end;
end;

/// <summary>Art des Eintrags: Favoriten, Hinweise, Formular, Angeheftetes, Aktionen, Postfix, Verfügbarkeit.</summary>
function TRanker.CompareKind(A, B: Integer): Integer;
begin
  // Angeheftete Favoriten (#458) vor allem anderen.
  Result := Ord(FItems[B].Favorite) - Ord(FItems[A].Favorite);
  if Result = 0 then
  begin
    Result := Ord(FItems[B].Hint) - Ord(FItems[A].Hint);
  end;
  if Result = 0 then
  begin
    Result := Ord(FItems[B].Form <> '') - Ord(FItems[A].Form <> '');
  end;
  if (Result = 0) and (FItems[A].Form <> '') then
  begin
    Result := Ord(FItems[A].ByType) - Ord(FItems[B].ByType);
  end;
  if Result = 0 then
  begin
    Result := Ord(FItems[B].Pinned and FNoPattern) - Ord(FItems[A].Pinned and FNoPattern);
  end;
  if Result = 0 then
  begin
    Result := Ord(FItems[A].IsAction) - Ord(FItems[B].IsAction);
  end;
  // Echte Mitglieder immer vor Postfix-Vorlagen (#188).
  if Result = 0 then
  begin
    Result := Ord(FItems[A].Postfix) - Ord(FItems[B].Postfix);
  end;
  // In der aktiven Konfiguration nicht vorhanden: ans Ende (#476).
  if Result = 0 then
  begin
    Result := Ord(FItems[A].Unavailable) - Ord(FItems[B].Unavailable);
  end;
end;

/// <summary>Gruppe: erwarteter Typ, inherited-Aufrufe, uses-Abschnitt, Aufzählungswerte.</summary>
function TRanker.CompareGroup(A, B: Integer): Integer;
begin
  Result := GroupOf(FItems[A], FAnyFits) - GroupOf(FItems[B], FAnyFits);
  // Vollständige inherited-Aufrufe vor den Namen der Vorfahrmethoden (#482).
  if Result = 0 then
  begin
    Result := InheritedRank(FItems[A]) - InheritedRank(FItems[B]);
  end;
  // uses-Abschnitt (#469): Projekt vor RTL/VCL vor Drittanbietern.
  if Result = 0 then
  begin
    Result := UsesRank(FItems[A]) - UsesRank(FItems[B]);
  end;
  // Aufzählungswerte vor den übrigen passenden Einträgen, ohne Präfix in Deklarationsreihenfolge (#448).
  if Result = 0 then
  begin
    Result := Ord(FItems[B].Ordinal > 0) - Ord(FItems[A].Ordinal > 0);
  end;
  if (Result = 0) and (FItems[A].Ordinal > 0) and FNoPattern then
  begin
    Result := FItems[A].Ordinal - FItems[B].Ordinal;
  end;
end;

/// <summary>Ohne Präfix: nach Bereich (lokal vor Parameter vor Feld …, #488), dann Gruppen nach Tiefe, darin
/// Gelerntes zuerst.</summary>
function TRanker.CompareGrouped(A, B: Integer): Integer;
begin
  Result := ScopeRank(FItems[A]) - ScopeRank(FItems[B]);
  if Result = 0 then
  begin
    Result := FItems[A].Depth - FItems[B].Depth;
  end;
  if (Result = 0) and (FItems[A].Depth > 0) then
  begin
    Result := CompareText(FItems[A].DeclaringClass, FItems[B].DeclaringClass);
  end;
  if Result = 0 then
  begin
    Result := FBoosts[B] - FBoosts[A];
  end;
end;

/// <summary>Güte, dann Bereich (#488), dann Gelerntes (#418).</summary>
function TRanker.CompareScored(A, B: Integer): Integer;
begin
  Result := FScores[B] - FScores[A];
  if Result = 0 then
  begin
    Result := ScopeRank(FItems[A]) - ScopeRank(FItems[B]);
  end;
  if Result = 0 then
  begin
    Result := FBoosts[B] - FBoosts[A];
  end;
  if (Result = 0) and FOptions.GroupInherited then
  begin
    Result := FItems[A].Depth - FItems[B].Depth;
  end;
end;

function TRanker.Compare(A, B: Integer): Integer;
begin
  Result := CompareKind(A, B);
  if Result = 0 then
  begin
    Result := CompareGroup(A, B);
  end;
  if Result <> 0 then
  begin
    Exit;
  end;
  if FGrouped then
  begin
    Result := CompareGrouped(A, B);
  end
  else
  begin
    Result := CompareScored(A, B);
  end;
  if Result = 0 then
  begin
    Result := FItems[A].Rank - FItems[B].Rank;
  end;
  if Result = 0 then
  begin
    Result := CompareText(FItems[A].Name, FItems[B].Name);
  end;
  if Result = 0 then
  begin
    Result := A - B;
  end;
end;

/// <summary>Überschrift vor AItem? Je Gruppe zum erwarteten Typ (#417), sonst vor jeder Gruppe geerbter Member
/// (#419). APrevious ist der Eintrag davor, FNone vor dem ersten nach den Favoriten (AIsFirst).</summary>
function TRanker.NeedsHeader(const AItem, APrevious: TDpccCompletionItem; AIsFirst: Boolean;
  const AState: TArrangeState): Boolean;
begin
  if AItem.Unknown <> '' then
  begin
    Result := AIsFirst or (APrevious.Unknown = '');
  end
  else if AItem.Form <> '' then
  begin
    Result := AIsFirst or (APrevious.Form = '');
  end
  // Sender (#480) und Typargumente (#450): eine Überschrift über der Liste.
  else if AIsFirst and ((AItem.Sender <> '') or (AItem.TypeParam <> '')) then
  begin
    Result := True;
  end
  // uses-Abschnitt (#469): eine Überschrift je Gruppe (Projekt, RTL/VCL, Drittanbieter).
  else if AItem.UsesGroup <> '' then
  begin
    Result := AIsFirst or (APrevious.UsesGroup <> AItem.UsesGroup);
  end
  else
  begin
    Result := FollowingHeader(AItem, APrevious, AState);
  end;
end;

function TRanker.FollowingHeader(const AItem, APrevious: TDpccCompletionItem; const AState: TArrangeState): Boolean;
begin
  // Nach der Formulargruppe eine Überschrift über dem Rest („Weitere“ bzw. die Gruppe zum erwarteten Typ).
  if APrevious.Form <> '' then
  begin
    Result := True;
  end
  else if FAnyFits and (AItem.ExpectedType <> '') and not AItem.IsAction then
  begin
    Result := GroupOf(AItem, FAnyFits) <> AState.Group;
  end
  else
  begin
    Result := FGrouped and (AItem.Depth > 0) and ((AItem.Depth <> AState.Depth) or
      not SameText(AItem.DeclaringClass, AState.Container));
  end;
end;

function TRanker.Arrange(AFound: TList<Integer>): TArray<Integer>;
var
  mOrdered: TList<Integer>;
  mState: TArrangeState;
  mPosition, mFirst, mIndex: Integer;
  mHeader: Boolean;
begin
  mState.Group := -1;
  mState.Depth := 0;
  mState.Container := '';
  // Favoriten (#458) stehen vorne und ohne Überschrift; die übrigen Gruppen beginnen bei mFirst.
  mFirst := 0;
  while (mFirst < AFound.Count) and FItems[AFound[mFirst]].Favorite do
  begin
    Inc(mFirst);
  end;
  // In einer Liste sammeln: Anhängen an das Array kopierte es bei jedem Eintrag (#616).
  mOrdered := TList<Integer>.Create;
  try
    for mPosition := 0 to AFound.Count - 1 do
    begin
      mIndex := AFound[mPosition];
      if mPosition >= mFirst then
      begin
        if mPosition = mFirst then
        begin
          mHeader := NeedsHeader(FItems[mIndex], FNone, True, mState);
        end
        else
        begin
          mHeader := NeedsHeader(FItems[mIndex], FItems[AFound[mPosition - 1]], False, mState);
        end;
        if mHeader then
        begin
          mOrdered.Add(HeaderOf(FItems[mIndex]));
        end;
        mState.Group := GroupOf(FItems[mIndex], FAnyFits);
        mState.Depth := FItems[mIndex].Depth;
        mState.Container := FItems[mIndex].DeclaringClass;
      end;
      mOrdered.Add(mIndex);
    end;
    Result := mOrdered.ToArray;
  finally
    mOrdered.Free;
  end;
end;

function TRanker.Order(const APattern: string): TArray<Integer>;
var
  mFound: TList<Integer>;
begin
  mFound := TList<Integer>.Create;
  try
    Collect(APattern, mFound);
    mFound.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Compare(A, B);
      end));
    MoveVariants(FItems, mFound);
    Result := Arrange(mFound);
  finally
    mFound.Free;
  end;
end;

/// <summary>Position der Überschrift UnknownHeader (#471) in AOrder; Länge ohne.</summary>
function UnknownStart(const AOrder: TArray<Integer>): Integer;
var
  mPosition: Integer;
begin
  for mPosition := 0 to High(AOrder) do
  begin
    if AOrder[mPosition] = TDpccRanking.cUnknownHeader then
    begin
      Exit(mPosition);
    end;
  end;
  Result := Length(AOrder);
end;

/// <summary>ARest vor der Gruppe des unbekannten Namens (#497): bei Rest unter RestHeader. ARestStart wird die
/// Position des ersten Rest-Eintrags; ohne Rest bleibt alles, wie es ist.</summary>
function WithRest(const AOrder, ARest: TArray<Integer>; AMode: TDpccListMode; var ARestStart: Integer):
  TArray<Integer>;
var
  mUnknown: Integer;
begin
  if Length(ARest) = 0 then
  begin
    Exit(AOrder);
  end;
  mUnknown := UnknownStart(AOrder);
  if AMode = TDpccListMode.Rest then
  begin
    ARestStart := mUnknown + 1;
    Result := Copy(AOrder, 0, mUnknown) + [TDpccRanking.cRestHeader] + ARest + Copy(AOrder, mUnknown, MaxInt);
  end
  else
  begin
    ARestStart := mUnknown;
    Result := Copy(AOrder, 0, mUnknown) + ARest + Copy(AOrder, mUnknown, MaxInt);
  end;
end;

class function TDpccRanking.Order(const AItems: TDpccCompletionItems; const APattern: string;
  const AOptions: TDpccRankOptions; out ARestStart: Integer): TArray<Integer>;
var
  mRanker: TRanker;
  mUnknown: Integer;
begin
  ARestStart := -1;
  mRanker := TRanker.Create(AItems, APattern, AOptions);
  try
    Result := WithConversions(AItems, mRanker.Order(APattern));
    // Tippfehler (#485): wenig reguläre Treffer, dann bis zu MaxTypos ähnliche Namen unter „Meintest du“, vor
    // der Gruppe des unbekannten Namens (#471), die nicht als Treffer zählt.
    mUnknown := UnknownStart(Result);
    if (ItemCount(Copy(Result, 0, mUnknown)) < cMinRegular) and (TDpccCompletionMatcher.TypoLimit(APattern) > 0) then
    begin
      Result := Copy(Result, 0, mUnknown) + Typos(AItems, APattern, AOptions, mRanker.Scores, mRanker.Boosts) +
        Copy(Result, mUnknown, MaxInt);
    end;
    // Rest der Liste (#497): hinter Treffern und Tippfehlern, vor dem unbekannten Namen.
    if (AOptions.ListMode <> TDpccListMode.Filter) and (APattern <> '') then
    begin
      Result := WithRest(Result, RestOf(AItems, mRanker.Scores, Result), AOptions.ListMode, ARestStart);
    end;
  finally
    mRanker.Free;
  end;
end;

class function TDpccRanking.Typos(const AItems: TDpccCompletionItems; const APattern: string;
  const AOptions: TDpccRankOptions; const AScores, ABoosts: TArray<Integer>): TArray<Integer>;
var
  mItems: TDpccCompletionItems;
  mDistances: TArray<Integer>;
  mCandidates: TList<Integer>;
  mIndex, mLimit: Integer;
  mBoosts: TArray<Integer>;
begin
  Result := nil;
  mItems := AItems;
  mBoosts := ABoosts;
  mLimit := TDpccCompletionMatcher.TypoLimit(APattern);
  SetLength(mDistances, Length(mItems));
  mCandidates := TList<Integer>.Create;
  try
    for mIndex := 0 to High(mItems) do
    begin
      // Nur, was nicht schon regulär passt; keine Aktionen.
      if mItems[mIndex].IsAction or (mItems[mIndex].Conversion <> '') or
        (AScores[mIndex] <> TDpccCompletionMatcher.cNoMatch) then
      begin
        Continue;
      end;
      mDistances[mIndex] := TDpccCompletionMatcher.TypoDistance(APattern, NameOf(mItems[mIndex]));
      if mDistances[mIndex] <= mLimit then
      begin
        mCandidates.Add(mIndex);
      end;
    end;
    if mCandidates.Count = 0 then
    begin
      Exit;
    end;
    mCandidates.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := mDistances[A] - mDistances[B];
        if Result = 0 then
        begin
          Result := mBoosts[B] - mBoosts[A];
        end;
        if Result = 0 then
        begin
          Result := CompareText(mItems[A].Name, mItems[B].Name);
        end;
      end));
    Result := [cTypoHeader];
    for mIndex := 0 to Min(mCandidates.Count, cMaxTypos) - 1 do
    begin
      Result := Result + [mCandidates[mIndex]];
    end;
  finally
    mCandidates.Free;
  end;
end;

class function TDpccRanking.ItemCount(const AOrder: TArray<Integer>): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex in AOrder do
  begin
    if not IsHeader(mIndex) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TDpccRanking.IsHeader(AValue: Integer): Boolean;
begin
  Result := AValue < 0;
end;

class function TDpccRanking.OnlyTypos(const AOrder: TArray<Integer>): Boolean;
begin
  Result := (Length(AOrder) > 1) and (AOrder[0] = cTypoHeader);
end;

end.
