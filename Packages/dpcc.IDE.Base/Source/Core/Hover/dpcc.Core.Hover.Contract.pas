unit dpcc.Core.Hover.Contract;

// Inhalt des Hover-Tooltips (#442, #588) aus dem Objekt "dpcc" der Hover-Antwort: Deklaration, Unit, Typ, in dem
// die Deklaration steht (container, S3), Art und Herkunft (VCL, FMX, RTL), Doku (Klartext und seit #654
// strukturiert samt Anzeige-Einstellungen), Wert, Veraltung, Fundort und die Vererbungskette. Ohne "dpcc" (fremder
// Server, Direktiven, Schlüsselwörter) wird der Klartext wie bisher in Deklaration und Doku geteilt.
// Bei Komponentenklassen (#110) kommen die published-Properties und Ereignisse samt geerbter aus "dpcc.published",
// dazu die Standard-Property.
// Seit S3b wieder der volle Inhalt (S3 hatte ihn auf Signatur, Herkunft und Kurztext gekürzt); nicht gelesen werden
// nur die Typverweise der Deklaration ("links", Klickflächen gibt es im schlichten Tooltip nicht) sowie
// "reassigned" und "docWiki", die der Server seit dem Rückbau nicht mehr schickt.

interface

uses
  System.JSON,
  dpcc.Core.Documentation.Contract;

type
  /// <summary>Typ mit Fundort (0-basiert); FileName '' ohne Fundort.</summary>
  TDpccHoverTypeRef = record
    Name: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
    function HasLocation: Boolean;
    /// <summary>Schlüssel für "derselbe Typ" (Datei und Position bzw. Name).</summary>
    function Key: string;
    class function FromJson(const AObject: TJSONObject): TDpccHoverTypeRef; static;
  end;

  /// <summary>Vorgabe eines published-Mitglieds (#110): keine Angabe, default Wert, implizit (False, 0, erster
  /// Aufzählungswert) bzw. nodefault.</summary>
  TDpccHoverDefaultKind = (hdNone, hdExplicit, hdImplicit, hdNoDefault);

  /// <summary>published-Property oder Ereignis einer Komponentenklasse (#110).</summary>
  TDpccHoverMember = record
    Name: string;
    TypeName: string;
    /// <summary>Wert nach default bzw. der implizite Wert; '' ohne.</summary>
    DefaultValue: string;
    DefaultKind: TDpccHoverDefaultKind;
    /// <summary>Text nach stored (False, IsCaptionStored); '' ohne.</summary>
    Stored: string;
    /// <summary>Klasse, die das Mitglied mit Typ deklariert.</summary>
    DeclaringClass: string;
    IsEvent: Boolean;
    /// <summary>Hat eine Vorgabe (ausdrücklich oder implizit).</summary>
    function HasDefault: Boolean;
    /// <summary>Gehört zur gewählten Art (Ereignis oder Property); mit AOnlyDefaults nur Properties mit Vorgabe.
    /// </summary>
    function Matches(AEvents, AOnlyDefaults: Boolean): Boolean;
    /// <summary>Spalte „Vorgabe“ als Klartext: "crDefault", "False (implizit)", "nodefault", dazu "stored …".
    /// </summary>
    function DefaultText(const AImplicit: string): string;
  end;

  TDpccHoverData = record
  public const
    cKindClassRef = 'classref';
    /// <summary>Bis zu so vielen Gliedern zeigt der Tooltip die ganze Kette.</summary>
    cMaxChainShown = 5;
  public
    Declaration: string;
    /// <summary>Unit der Deklaration; '' bei der aktuellen Datei.</summary>
    UnitName: string;
    /// <summary>Typ, in dem die Deklaration steht (z. B. TFileStream bei Create); '' auf oberster Ebene.</summary>
    Container: string;
    /// <summary>class, classref, record, interface, enum, type, method … ('' unbekannt).</summary>
    Kind: string;
    /// <summary>VCL, FMX, RTL oder '' (eigene Unit).</summary>
    Origin: string;
    /// <summary>Doku als Klartext (Sprachausgabe, Rückfall ohne Doc).</summary>
    Documentation: string;
    /// <summary>Strukturierte XMLDoc (#654); leer bei fremden Servern.</summary>
    Doc: TDpccDoc;
    /// <summary>Anzeige laut Server (dpcc.xmlDoc); Known = False ohne Angabe.</summary>
    Display: TDpccDocDisplay;
    /// <summary>Wert bei Zahlen, Konstanten und Aufzählungswerten; '' ohne.</summary>
    Value: string;
    /// <summary>Hinweis bei deprecated, platform, experimental; '' ohne.</summary>
    Deprecation: string;
    /// <summary>Fundort der Deklaration; Name ist der deklarierte Name, wenn bekannt.</summary>
    Location: TDpccHoverTypeRef;
    /// <summary>Typ, dessen Kette Ancestors zeigt (bei "class of T" T).</summary>
    ChainOf: string;
    Ancestors: TArray<TDpccHoverTypeRef>;
    /// <summary>published-Properties und Ereignisse samt geerbter (#110), abgeleitete Klassen zuerst.</summary>
    Members: TArray<TDpccHoverMember>;
    /// <summary>Standard-Property (Array-Property mit default), z. B. "Strings[Index: Integer]: string"; '' ohne.
    /// </summary>
    DefaultProperty: string;
    function Found: Boolean;
    /// <summary>Zahl der published-Properties bzw. -Ereignisse (#110).</summary>
    function MemberCount(AEvents: Boolean): Integer;
    /// <summary>Indizes in Members: Properties oder Ereignisse; ohne AInherited nur die der Klasse selbst
    /// (DeclaringClass = Title), mit AOnlyDefaults nur Properties mit Vorgabe.</summary>
    function VisibleMembers(AEvents, AInherited, AOnlyDefaults: Boolean): TArray<Integer>;
    /// <summary>Name des angezeigten Typs: erstes Kettenglied bzw. Name am Fundort bzw. Deklarationsanfang.</summary>
    function Title: string;
    /// <summary>"Datei.pas : 20" (1-basiert) bzw. die Unit; '' ohne beides.</summary>
    function LocationText: string;
    /// <summary>Indizes der anzuzeigenden Kettenglieder; -1 steht für "…" (mehr als MaxChainShown).</summary>
    function VisibleChain: TArray<Integer>;
    class function FromHover(const AHover: TJSONValue): TDpccHoverData; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

{ TDpccHoverTypeRef }

function TDpccHoverTypeRef.HasLocation: Boolean;
begin
  Result := FileName <> '';
end;

function TDpccHoverTypeRef.Key: string;
begin
  if HasLocation then
  begin
    Result := Format('%s|%d|%d', [UpperCase(FileName), Line, Character]);
  end
  else
  begin
    Result := UpperCase(Name);
  end;
end;

class function TDpccHoverTypeRef.FromJson(const AObject: TJSONObject): TDpccHoverTypeRef;
begin
  Result := Default(TDpccHoverTypeRef);
  if AObject = nil then
  begin
    Exit;
  end;
  Result.Name := AObject.GetValue<string>('name', '');
  Result.UnitName := AObject.GetValue<string>('unit', '');
  Result.FileName := AObject.GetValue<string>('file', '');
  Result.Line := AObject.GetValue<Integer>('line', 0);
  Result.Character := AObject.GetValue<Integer>('character', 0);
end;

{ TDpccHoverMember }

function TDpccHoverMember.HasDefault: Boolean;
begin
  Result := (DefaultKind = hdExplicit) or (DefaultKind = hdImplicit);
end;

function TDpccHoverMember.Matches(AEvents, AOnlyDefaults: Boolean): Boolean;
begin
  Result := (IsEvent = AEvents) and (AEvents or not AOnlyDefaults or HasDefault);
end;

function TDpccHoverMember.DefaultText(const AImplicit: string): string;
begin
  case DefaultKind of
    hdExplicit: Result := DefaultValue;
    hdImplicit: Result := DefaultValue + ' (' + AImplicit + ')';
    hdNoDefault: Result := 'nodefault';
  else
    Result := '';
  end;
  if Stored <> '' then
  begin
    Result := Trim(Result + ' stored ' + Stored);
  end;
end;

{ TDpccHoverData }

function TDpccHoverData.Found: Boolean;
begin
  Result := Declaration <> '';
end;

function TDpccHoverData.MemberCount(AEvents: Boolean): Integer;
var
  mMember: TDpccHoverMember;
begin
  Result := 0;
  for mMember in Members do
  begin
    if mMember.IsEvent = AEvents then
    begin
      Inc(Result);
    end;
  end;
end;

function TDpccHoverData.VisibleMembers(AEvents, AInherited, AOnlyDefaults: Boolean): TArray<Integer>;
var
  mIndex: Integer;
  mOwn: string;
begin
  Result := nil;
  mOwn := Title;
  for mIndex := 0 to High(Members) do
  begin
    if Members[mIndex].Matches(AEvents, AOnlyDefaults) and
      (AInherited or SameText(Members[mIndex].DeclaringClass, mOwn))
    then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

/// <summary>Bezeichner am Anfang von AText (mit Punkt und &amp;).</summary>
function LeadingName(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := AText;
  for mIndex := 1 to Length(Result) do
  begin
    if not CharInSet(Result[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '&']) then
    begin
      Result := Copy(Result, 1, mIndex - 1);
      Break;
    end;
  end;
end;

function TDpccHoverData.Title: string;
begin
  if (Length(Ancestors) > 0) and (Kind <> cKindClassRef) then
  begin
    Exit(Ancestors[0].Name);
  end;
  if Location.Name <> '' then
  begin
    Exit(Location.Name);
  end;
  // Erster Bezeichner der Deklaration (TFoo = class, Name: Typ, procedure Bar).
  Result := LeadingName(Trim(Declaration));
  if MatchText(Result, ['procedure', 'function', 'constructor', 'destructor', 'property', 'class', 'type',
    'var', 'const']) then
  begin
    Result := LeadingName(Trim(Copy(Trim(Declaration), Length(Result) + 1, MaxInt)));
  end;
end;

function TDpccHoverData.LocationText: string;
begin
  if Location.HasLocation then
  begin
    Result := Format('%s : %d', [ExtractFileName(Location.FileName), Location.Line + 1]);
  end
  else
  begin
    Result := UnitName;
  end;
end;

function TDpccHoverData.VisibleChain: TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  if Length(Ancestors) <= cMaxChainShown then
  begin
    for mIndex := 0 to High(Ancestors) do
    begin
      Result := Result + [mIndex];
    end;
    Exit;
  end;
  // Die ersten vier, dann "…", dann das letzte (meist TObject).
  for mIndex := 0 to cMaxChainShown - 2 do
  begin
    Result := Result + [mIndex];
  end;
  Result := Result + [-1, High(Ancestors)];
end;

function PlainText(const AHover: TJSONValue): string;
var
  mContents: TJSONValue;
begin
  Result := '';
  if not (AHover is TJSONObject) then
  begin
    Exit;
  end;
  mContents := TJSONObject(AHover).GetValue('contents');
  if mContents is TJSONString then
  begin
    Result := mContents.Value;
  end
  else if mContents is TJSONObject then
  begin
    Result := TJSONObject(mContents).GetValue<string>('value', '');
  end;
end;

function MemberFromJson(AObject: TJSONObject): TDpccHoverMember;
var
  mKind: string;
begin
  Result := Default(TDpccHoverMember);
  Result.Name := AObject.GetValue<string>('name', '');
  Result.TypeName := AObject.GetValue<string>('type', '');
  Result.DefaultValue := AObject.GetValue<string>('default', '');
  mKind := AObject.GetValue<string>('defaultKind', '');
  if mKind = 'explicit' then
  begin
    Result.DefaultKind := hdExplicit;
  end
  else if mKind = 'implicit' then
  begin
    Result.DefaultKind := hdImplicit;
  end
  else if mKind = 'nodefault' then
  begin
    Result.DefaultKind := hdNoDefault;
  end;
  Result.Stored := AObject.GetValue<string>('stored', '');
  Result.DeclaringClass := AObject.GetValue<string>('declaringClass', '');
  Result.IsEvent := AObject.GetValue<Boolean>('event', False);
end;

/// <summary>Rückfall ohne "dpcc": erster Absatz Deklaration, der Rest Doku; Markdown-Zäune entfernen.</summary>
procedure ReadPlain(var AData: TDpccHoverData; const AHover: TJSONValue);
var
  mText: string;
  mSplit: Integer;
begin
  mText := StringReplace(PlainText(AHover), #13#10, #10, [rfReplaceAll]);
  mText := StringReplace(mText, '```pascal', '', [rfReplaceAll]);
  mText := Trim(StringReplace(mText, '```', '', [rfReplaceAll]));
  mSplit := Pos(#10#10, mText);
  if mSplit = 0 then
  begin
    AData.Declaration := mText;
  end
  else
  begin
    AData.Declaration := Trim(Copy(mText, 1, mSplit - 1));
    AData.Documentation := Trim(Copy(mText, mSplit + 2, MaxInt));
  end;
end;

/// <summary>Doku als Klartext und strukturiert (#654) samt Anzeige laut Server.</summary>
procedure ReadDocumentation(var AData: TDpccHoverData; ADpcc: TJSONObject);
begin
  // Seit #654 ist "documentation" strukturiert, der Klartext steht in "documentationText".
  if not ADpcc.TryGetValue<string>('documentationText', AData.Documentation) and
    (ADpcc.GetValue('documentation') is TJSONString) then
  begin
    AData.Documentation := ADpcc.GetValue('documentation').Value;
  end;
  AData.Doc := TDpccDoc.FromJson(ADpcc.GetValue('documentation'));
  // Nur Begründungen (#1123) bzw. der Inhalt einer Unit (#1921) strukturiert: die Doku als Klartext davor, sonst
  // fiele sie weg (beim Unit-Namen der Dateipfad).
  if (AData.Documentation <> '') and not AData.Doc.IsEmpty and
    (Length(AData.Doc.Sections) = Length(AData.Doc.SectionsOf(TDpccDocSectionKind.Rationale)) +
    Length(AData.Doc.SectionsOf(TDpccDocSectionKind.UnitContents))) then
  begin
    AData.Doc.Sections := TDpccDoc.FromText(AData.Documentation).Sections + AData.Doc.Sections;
  end;
  AData.Display := TDpccDocDisplay.FromJson(ADpcc.GetValue('xmlDoc'),
    TDpccDocDisplay.Create(TDpccDocExpand.Last, 0));
end;

function AncestorsFromJson(ADpcc: TJSONObject): TArray<TDpccHoverTypeRef>;
var
  mList: TJSONArray;
  mValue: TJSONValue;
begin
  Result := nil;
  if not ADpcc.TryGetValue<TJSONArray>('ancestors', mList) then
  begin
    Exit;
  end;
  for mValue in mList do
  begin
    if mValue is TJSONObject then
    begin
      Result := Result + [TDpccHoverTypeRef.FromJson(TJSONObject(mValue))];
    end;
  end;
end;

/// <summary>published-Properties und Ereignisse (#110).</summary>
procedure ReadPublished(var AData: TDpccHoverData; ADpcc: TJSONObject);
var
  mItem: TJSONObject;
  mList: TJSONArray;
  mValue: TJSONValue;
begin
  if not ADpcc.TryGetValue<TJSONObject>('published', mItem) then
  begin
    Exit;
  end;
  AData.DefaultProperty := mItem.GetValue<string>('defaultProperty', '');
  if not mItem.TryGetValue<TJSONArray>('members', mList) then
  begin
    Exit;
  end;
  for mValue in mList do
  begin
    if mValue is TJSONObject then
    begin
      AData.Members := AData.Members + [MemberFromJson(TJSONObject(mValue))];
    end;
  end;
end;

class function TDpccHoverData.FromHover(const AHover: TJSONValue): TDpccHoverData;
var
  mDpcc: TJSONObject;
begin
  Result := Default(TDpccHoverData);
  mDpcc := nil;
  if AHover is TJSONObject then
  begin
    mDpcc := TJSONObject(AHover).GetValue('dpcc') as TJSONObject;
  end;
  if mDpcc = nil then
  begin
    ReadPlain(Result, AHover);
    Exit;
  end;
  Result.Declaration := mDpcc.GetValue<string>('declaration', '');
  Result.UnitName := mDpcc.GetValue<string>('unit', '');
  Result.Container := mDpcc.GetValue<string>('container', '');
  ReadDocumentation(Result, mDpcc);
  Result.Value := mDpcc.GetValue<string>('value', '');
  Result.Deprecation := mDpcc.GetValue<string>('deprecation', '');
  Result.Kind := mDpcc.GetValue<string>('kind', '');
  Result.Origin := mDpcc.GetValue<string>('origin', '');
  Result.Location := TDpccHoverTypeRef.FromJson(mDpcc);
  Result.Location.Name := '';
  Result.Location.UnitName := Result.UnitName;
  Result.ChainOf := mDpcc.GetValue<string>('chainOf', '');
  Result.Ancestors := AncestorsFromJson(mDpcc);
  ReadPublished(Result, mDpcc);
  // Der angezeigte Typ selbst: erstes Kettenglied mit demselben Fundort.
  if (Length(Result.Ancestors) > 0) and (Result.Ancestors[0].Key = Result.Location.Key) then
  begin
    Result.Location.Name := Result.Ancestors[0].Name;
  end;
end;

end.
