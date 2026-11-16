unit dpcc.Core.Documentation.Contract;

// Strukturierte XMLDoc (#654) aus "dpcc.documentation" der Hover-Antwort bzw.
// "data.dpcc.documentation" der Resolve-Antwort: Abschnitte (summary, param,
// typeparam, returns, value, exception, remarks, example, seealso) mit Läufen
// (Text, Code, Verweis mit Fundort, Link, Absatz, Codeblock, Listenpunkt,
// Tabellenzelle). Dazu Begründungen (#1123) als Abschnitte rationale, je
// Eintrag einer mit der Marke als Name; ein Link "issue:312" darin zeigt auf ein
// Issue im Tracker (TDpccDocIssueUrl). Über einem Unit-Namen (#1921) kommt der Inhalt der Unit als Abschnitte
// unitContents, je Gruppe einer mit Überschrift (heading), Gruppenname (name) und den Namen als Verweisen.
// Dazu die Anzeige-Einstellungen "xmlDoc" (zu- oder aufgeklappt
// beim Öffnen, Zeilengrenze), die der Server je Projekt meldet, und die
// Parameter der Signatur (#770) aus der Deklaration (Name, Art, Typ;
// Ergebnistyp), damit die Doku jeden Parameter in der Reihenfolge der Signatur
// zeigen kann. Den Zustand „wie zuletzt“ hält TDpccDocExpandState in
// dpcc.Core.Documentation.Layout.

interface

uses
  System.JSON;

{$SCOPEDENUMS ON}

type
  /// <summary>Art eines Laufs; Namen wie im Server (text, code, ref, link, paramref, keyword, br, para,
  /// codeblock, bullet, cell).</summary>
  TDpccDocRunKind = (Text, Code, Ref, Link, ParamRef, Keyword, LineBreak, Paragraph, CodeBlock, Bullet, Cell);

  TDpccDocSectionKind = (Summary, Param, TypeParam, Returns, Value, Exception, Remarks, Example, SeeAlso, Rationale,
    UnitContents);

  /// <summary>Adresse des Issues AKey ("312") im Tracker des aktuellen Projekts; '' ohne Tracker.</summary>
  TDpccDocIssueUrl = reference to function(const AKey: string): string;

  /// <summary>XMLDoc beim Öffnen (#770, hints.xmlDocExpand): immer zugeklappt, wie zuletzt, immer aufgeklappt.
  /// </summary>
  TDpccDocExpand = (Collapsed, Last, Expanded);

  /// <summary>Wo die Doku steht; „wie zuletzt“ gilt je Fläche.</summary>
  TDpccDocSurface = (Tooltip, Details);

  /// <summary>Ziel eines Verweises; FileName '' ohne Fundort (Name, Unit bleiben).</summary>
  TDpccDocTarget = record
    Name: string;
    UnitName: string;
    FileName: string;
    /// <summary>0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    function HasLocation: Boolean;
    class function FromJson(const AObject: TJSONObject): TDpccDocTarget; static;
  end;

  TDpccDocRun = record
    Kind: TDpccDocRunKind;
    Text: string;
    /// <summary>Ref: cref (ohne Präfix); Link: URL; CodeBlock: Sprache ('' = Delphi; Markdown der Issue-Vorschau,
    /// #1264); Bullet: Ziel der anklickbaren Marke ('' = nur Marke; Kästchen einer Checkliste, #1273).</summary>
    Target: string;
    Bold: Boolean;
    Italic: Boolean;
    /// <summary>Bullet: Listenebene ab 1.</summary>
    Level: Integer;
    /// <summary>Ref: Fundort, wenn der Server ihn kennt.</summary>
    Location: TDpccDocTarget;
    class function Create(AKind: TDpccDocRunKind; const AText, ATarget: string): TDpccDocRun; overload; static;
    /// <summary>Wie oben ohne Ziel (ATarget = '').</summary>
    class function Create(AKind: TDpccDocRunKind; const AText: string): TDpccDocRun; overload; static;
    /// <summary>CodeBlock in Delphi (ohne Sprache, pascal, delphi, objectpascal, pas, dpr): eingefärbt.</summary>
    function IsDelphiCode: Boolean;
  end;

  TDpccDocRuns = TArray<TDpccDocRun>;

  TDpccDocSection = record
    Kind: TDpccDocSectionKind;
    /// <summary>Param, TypeParam: Name; Exception: Klasse; Rationale: Marke (WHY); UnitContents: Gruppe (Klassen).
    /// </summary>
    Name: string;
    /// <summary>UnitContents: Überschrift, unter der die Gruppe steht ("IN DIESER DATEI BENUTZT (2)"); sonst ''.
    /// </summary>
    Heading: string;
    /// <summary>Exception: Fundort der Klasse, wenn bekannt.</summary>
    NameRef: TDpccDocTarget;
    Runs: TDpccDocRuns;
    /// <summary>Text der Läufe ohne Auszeichnung (für Sprachausgabe und Tests).</summary>
    function Text: string;
  end;

  TDpccDoc = record
    Sections: TArray<TDpccDocSection>;
    function IsEmpty: Boolean;
    function Has(AKind: TDpccDocSectionKind): Boolean;
    /// <summary>Abschnitte der Art AKind in Reihenfolge.</summary>
    function SectionsOf(AKind: TDpccDocSectionKind): TArray<TDpccDocSection>;
    /// <summary>Objekt mit "sections"; nil bzw. anderes ergibt eine leere Doku.</summary>
    class function FromJson(const AValue: TJSONValue): TDpccDoc; static;
    /// <summary>Klartext fremder Server als eine Beschreibung: Zeilenumbrüche bleiben, Leerzeilen trennen
    /// Absätze, eingerückte Zeilen behalten ihre Einrückung.</summary>
    class function FromText(const AText: string): TDpccDoc; static;
    class function TryParseRunKind(const AName: string; out AKind: TDpccDocRunKind): Boolean; static;
    class function TryParseSectionKind(const AName: string; out AKind: TDpccDocSectionKind): Boolean; static;
  end;

  /// <summary>Anzeige der XMLDoc (#654, #770): zu- oder aufgeklappt beim Öffnen und höchstens MaxLines Zeilen
  /// ohne Scrollen (0 = bis zur Bildschirmhöhe).</summary>
  TDpccDocDisplay = record
  public const
    cMaxMaxLines = 50;
  public
    /// <summary>Vom Server gemeldet (dpcc.json bzw. Einstellungen des Plugins).</summary>
    Known: Boolean;
    Expand: TDpccDocExpand;
    MaxLines: Integer;
    class function Create(AExpand: TDpccDocExpand; AMaxLines: Integer): TDpccDocDisplay; static;
    /// <summary>"xmlDoc" der Antwort; ohne Angabe AFallback (Einstellungen des Plugins). Liest "expand" und
    /// das frühere "full" (true = aufgeklappt).</summary>
    class function FromJson(const AValue: TJSONValue; const AFallback: TDpccDocDisplay): TDpccDocDisplay; static;
    /// <summary>"collapsed", "last", "expanded"; Unbekanntes ergibt Last.</summary>
    class function ExpandOf(const AName: string): TDpccDocExpand; static;
    class function ExpandName(AExpand: TDpccDocExpand): string; static;
  end;

  /// <summary>Parameter der Signatur: Name, Art (const, var, out, constref; '' ohne) und Typ ('' ohne).</summary>
  TDpccDocParam = record
    Name: string;
    Modifier: string;
    TypeName: string;
    /// <summary>"const string", "out TCompilerMessage", "var" (untypisiert); '' ohne Art und Typ.</summary>
    function TypeText: string;
  end;

  /// <summary>Signatur aus der Deklaration (#770); Known = Parameterliste erkannt (auch leer).</summary>
  TDpccDocSignature = record
    Known: Boolean;
    /// <summary>Property: ResultType ist ihr Typ (Abschnitt WERT statt RÜCKGABE).</summary>
    IsProperty: Boolean;
    Params: TArray<TDpccDocParam>;
    /// <summary>Ergebnistyp einer Funktion bzw. Typ einer Property; '' ohne.</summary>
    ResultType: string;
    function IndexOf(const AName: string): Integer;
    function HasTypes: Boolean;
    /// <summary>Liest "function TX.Name(const A, B: string; out C: TFoo = nil): Boolean; overload;",
    /// Properties mit [..]-Parametern und Generics; Unbekanntes ergibt Known = False.</summary>
    class function Parse(const ADeclaration: string): TDpccDocSignature; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.Math;

const
  cRunKindNames: array[TDpccDocRunKind] of string = ('text', 'code', 'ref', 'link', 'paramref', 'keyword', 'br',
    'para', 'codeblock', 'bullet', 'cell');
  cSectionKindNames: array[TDpccDocSectionKind] of string = ('summary', 'param', 'typeparam', 'returns', 'value',
    'exception', 'remarks', 'example', 'seealso', 'rationale', 'unitContents');

{ TDpccDocTarget }

function TDpccDocTarget.HasLocation: Boolean;
begin
  Result := FileName <> '';
end;

class function TDpccDocTarget.FromJson(const AObject: TJSONObject): TDpccDocTarget;
begin
  Result := Default(TDpccDocTarget);
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

{ TDpccDocRun }

class function TDpccDocRun.Create(AKind: TDpccDocRunKind; const AText: string): TDpccDocRun;
begin
  Result := Create(AKind, AText, '');
end;

class function TDpccDocRun.Create(AKind: TDpccDocRunKind; const AText, ATarget: string): TDpccDocRun;
begin
  Result := Default(TDpccDocRun);
  Result.Kind := AKind;
  Result.Text := AText;
  Result.Target := ATarget;
end;

function TDpccDocRun.IsDelphiCode: Boolean;
var
  mLanguage: string;
begin
  mLanguage := LowerCase(Trim(Target));
  Result := (mLanguage = '') or (mLanguage = 'pascal') or (mLanguage = 'delphi') or (mLanguage = 'objectpascal') or
    (mLanguage = 'object-pascal') or (mLanguage = 'pas') or (mLanguage = 'dpr');
end;

{ TDpccDocSection }

function TDpccDocSection.Text: string;
var
  mRun: TDpccDocRun;
begin
  Result := '';
  for mRun in Runs do
    case mRun.Kind of
      TDpccDocRunKind.LineBreak, TDpccDocRunKind.Paragraph:
        Result := Result + #10;
      TDpccDocRunKind.CodeBlock:
        Result := Result + #10 + mRun.Text + #10;
      TDpccDocRunKind.Bullet:
        if mRun.Text = '' then
        begin
          Result := Result + #10;
        end
        else
        begin
          Result := Result + #10 + mRun.Text + ' ';
        end;
      TDpccDocRunKind.Cell:
        Result := Result + ' – ';
    else
      Result := Result + mRun.Text;
    end;
  Result := Trim(Result);
end;

{ TDpccDoc }

function TDpccDoc.IsEmpty: Boolean;
begin
  Result := Length(Sections) = 0;
end;

function TDpccDoc.Has(AKind: TDpccDocSectionKind): Boolean;
var
  mSection: TDpccDocSection;
begin
  for mSection in Sections do
  begin
    if mSection.Kind = AKind then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDpccDoc.SectionsOf(AKind: TDpccDocSectionKind): TArray<TDpccDocSection>;
var
  mSection: TDpccDocSection;
begin
  Result := nil;
  for mSection in Sections do
  begin
    if mSection.Kind = AKind then
    begin
      Result := Result + [mSection];
    end;
  end;
end;

class function TDpccDoc.TryParseRunKind(const AName: string; out AKind: TDpccDocRunKind): Boolean;
var
  mKind: TDpccDocRunKind;
begin
  for mKind := Low(TDpccDocRunKind) to High(TDpccDocRunKind) do
  begin
    if SameText(cRunKindNames[mKind], AName) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDpccDoc.TryParseSectionKind(const AName: string; out AKind: TDpccDocSectionKind): Boolean;
var
  mKind: TDpccDocSectionKind;
begin
  for mKind := Low(TDpccDocSectionKind) to High(TDpccDocSectionKind) do
  begin
    if SameText(cSectionKindNames[mKind], AName) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Läufe eines Abschnitts; unbekannte (neuerer Server) fallen weg.</summary>
function DocRunsFromJson(const AItem: TJSONObject): TDpccDocRuns;
var
  mRuns: TJSONArray;
  mRunItem: TJSONValue;
  mRun: TDpccDocRun;
  mKind: TDpccDocRunKind;
begin
  Result := nil;
  mRuns := nil;
  if not AItem.TryGetValue<TJSONArray>('runs', mRuns) then
  begin
    Exit;
  end;
  for mRunItem in mRuns do
  begin
    if not (mRunItem is TJSONObject) or
      not TDpccDoc.TryParseRunKind(TJSONObject(mRunItem).GetValue<string>('kind', ''), mKind) then
    begin
      Continue;
    end;
    mRun := TDpccDocRun.Create(mKind, TJSONObject(mRunItem).GetValue<string>('text', ''),
      TJSONObject(mRunItem).GetValue<string>('target', ''));
    mRun.Bold := TJSONObject(mRunItem).GetValue<Boolean>('bold', False);
    mRun.Italic := TJSONObject(mRunItem).GetValue<Boolean>('italic', False);
    mRun.Level := TJSONObject(mRunItem).GetValue<Integer>('level', 0);
    if mKind = TDpccDocRunKind.Ref then
    begin
      mRun.Location := TDpccDocTarget.FromJson(TJSONObject(mRunItem));
      if mRun.Location.Name = '' then
      begin
        mRun.Location.Name := mRun.Target;
      end;
    end;
    Result := Result + [mRun];
  end;
end;

function DocSectionFromJson(const AItem: TJSONObject; AKind: TDpccDocSectionKind): TDpccDocSection;
var
  mRef: TJSONValue;
begin
  Result := Default(TDpccDocSection);
  Result.Kind := AKind;
  Result.Name := AItem.GetValue<string>('name', '');
  Result.Heading := AItem.GetValue<string>('heading', '');
  mRef := AItem.GetValue('ref');
  if mRef is TJSONObject then
  begin
    Result.NameRef := TDpccDocTarget.FromJson(TJSONObject(mRef));
    if Result.NameRef.Name = '' then
    begin
      Result.NameRef.Name := Result.Name;
    end;
  end;
  Result.Runs := DocRunsFromJson(AItem);
end;

class function TDpccDoc.FromJson(const AValue: TJSONValue): TDpccDoc;
var
  mList: TJSONArray;
  mItem: TJSONValue;
  mKind: TDpccDocSectionKind;
begin
  Result := Default(TDpccDoc);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mList := nil;
  if not TJSONObject(AValue).TryGetValue<TJSONArray>('sections', mList) then
  begin
    Exit;
  end;
  for mItem in mList do
  begin
    // Unbekannte Abschnitte und Läufe (neuerer Server) überspringen statt abbrechen.
    if (mItem is TJSONObject) and
      TryParseSectionKind(TJSONObject(mItem).GetValue<string>('kind', ''), mKind) then
    begin
      Result.Sections := Result.Sections + [DocSectionFromJson(TJSONObject(mItem), mKind)];
    end;
  end;
end;

class function TDpccDoc.FromText(const AText: string): TDpccDoc;
var
  mSection: TDpccDocSection;
  mLine: string;
  mPending: TDpccDocRunKind;
  mHasPending: Boolean;
  mLast: Integer;
begin
  Result := Default(TDpccDoc);
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  mSection := Default(TDpccDocSection);
  mSection.Kind := TDpccDocSectionKind.Summary;
  mHasPending := False;
  mPending := TDpccDocRunKind.LineBreak;
  for mLine in Trim(StringReplace(AText, #13#10, #10, [rfReplaceAll])).Split([#10]) do
  begin
    if Trim(mLine) = '' then
    begin
      mPending := TDpccDocRunKind.Paragraph;
      mHasPending := Length(mSection.Runs) > 0;
      Continue;
    end;
    mLast := High(mSection.Runs);
    // Eingerückte Zeilen (Code, Beispiele) als Codeblock mit Einrückung; aufeinanderfolgende in einem.
    if mLine.StartsWith(' ') and (mLast >= 0) and (mSection.Runs[mLast].Kind = TDpccDocRunKind.CodeBlock) and
      (mPending = TDpccDocRunKind.LineBreak) then
    begin
      mSection.Runs[mLast].Text := mSection.Runs[mLast].Text + #10 + TrimRight(mLine);
      Continue;
    end;
    if mHasPending then
    begin
      mSection.Runs := mSection.Runs + [TDpccDocRun.Create(mPending, '')];
    end;
    if mLine.StartsWith(' ') then
    begin
      mSection.Runs := mSection.Runs + [TDpccDocRun.Create(TDpccDocRunKind.CodeBlock, TrimRight(mLine))];
    end
    else
    begin
      mSection.Runs := mSection.Runs + [TDpccDocRun.Create(TDpccDocRunKind.Text, TrimRight(mLine))];
    end;
    mHasPending := True;
    mPending := TDpccDocRunKind.LineBreak;
  end;
  Result.Sections := [mSection];
end;

{ TDpccDocDisplay }

const
  cExpandNames: array[TDpccDocExpand] of string = ('collapsed', 'last', 'expanded');

class function TDpccDocDisplay.Create(AExpand: TDpccDocExpand; AMaxLines: Integer): TDpccDocDisplay;
begin
  Result.Known := False;
  Result.Expand := AExpand;
  Result.MaxLines := EnsureRange(AMaxLines, 0, cMaxMaxLines);
end;

class function TDpccDocDisplay.ExpandOf(const AName: string): TDpccDocExpand;
var
  mExpand: TDpccDocExpand;
begin
  for mExpand := Low(TDpccDocExpand) to High(TDpccDocExpand) do
  begin
    if SameText(cExpandNames[mExpand], Trim(AName)) then
    begin
      Exit(mExpand);
    end;
  end;
  Result := TDpccDocExpand.Last;
end;

class function TDpccDocDisplay.ExpandName(AExpand: TDpccDocExpand): string;
begin
  Result := cExpandNames[AExpand];
end;

class function TDpccDocDisplay.FromJson(const AValue: TJSONValue;
  const AFallback: TDpccDocDisplay): TDpccDocDisplay;
var
  mFull: TJSONValue;
begin
  Result := AFallback;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  Result.Known := True;
  if TJSONObject(AValue).GetValue('expand') is TJSONString then
  begin
    Result.Expand := ExpandOf(TJSONObject(AValue).GetValue<string>('expand', ''));
  end
  else
  begin
    // Server vor #770: "full".
    mFull := TJSONObject(AValue).GetValue('full');
    if mFull is TJSONBool then
    begin
      if TJSONBool(mFull).AsBoolean then
      begin
        Result.Expand := TDpccDocExpand.Expanded;
      end
      else
      begin
        Result.Expand := TDpccDocExpand.Collapsed;
      end;
    end;
  end;
  Result.MaxLines := EnsureRange(TJSONObject(AValue).GetValue<Integer>('maxLines', AFallback.MaxLines), 0,
    cMaxMaxLines);
end;

{ TDpccDocParam }

function TDpccDocParam.TypeText: string;
begin
  Result := Trim(Modifier + ' ' + TypeName);
end;

{ TDpccDocSignature }

function TDpccDocSignature.IndexOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Params) do
  begin
    if SameText(Params[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TDpccDocSignature.HasTypes: Boolean;
var
  mParam: TDpccDocParam;
begin
  for mParam in Params do
  begin
    if mParam.TypeText <> '' then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Stelle von AChar ab AFrom außerhalb von Klammern, spitzen Klammern und Strings; 0 ohne.</summary>
function FindTop(const AText: string; AChar: Char; AFrom: Integer): Integer;
var
  mIndex, mDepth: Integer;
  mInString: Boolean;
begin
  mDepth := 0;
  mInString := False;
  for mIndex := AFrom to Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mInString := not mInString;
    end;
    if mInString then
    begin
      Continue;
    end;
    if (mDepth = 0) and (AText[mIndex] = AChar) then
    begin
      Exit(mIndex);
    end;
    if CharInSet(AText[mIndex], ['(', '[', '<']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(AText[mIndex], [')', ']', '>']) and (mDepth > 0) then
    begin
      Dec(mDepth);
    end;
  end;
  Result := 0;
end;

/// <summary>Teile von AText an ASeparator außerhalb von Klammern.</summary>
function SplitTop(const AText: string; ASeparator: Char): TArray<string>;
var
  mStart, mStop: Integer;
begin
  Result := nil;
  mStart := 1;
  repeat
    mStop := FindTop(AText, ASeparator, mStart);
    if mStop = 0 then
    begin
      Result := Result + [Trim(Copy(AText, mStart, MaxInt))];
      Break;
    end;
    Result := Result + [Trim(Copy(AText, mStart, mStop - mStart))];
    mStart := mStop + 1;
  until False;
end;

/// <summary>Erstes Wort nach "class": function, procedure, constructor, destructor, operator oder property;
/// '' bei anderem.</summary>
function SignatureWord(const AText: string): string;
const
  cWords: array[0..5] of string = ('function', 'procedure', 'constructor', 'destructor', 'operator', 'property');
var
  mHead, mWord: string;
begin
  Result := '';
  mHead := LowerCase(AText);
  if mHead.StartsWith('class ') then
  begin
    mHead := Trim(Copy(mHead, 7, MaxInt));
  end;
  mWord := Copy(mHead, 1, Pos(' ', mHead + ' ') - 1);
  for mHead in cWords do
  begin
    if mWord = mHead then
    begin
      Exit(mWord);
    end;
  end;
end;

/// <summary>Position der öffnenden Klammer AOpenChar nach dem Namen, außerhalb von Generics; 0 ohne. AIndex steht
/// danach auf der Klammer bzw. dem ersten Zeichen hinter dem Namen.</summary>
function FindParamOpen(const AText: string; AOpenChar: Char; out AIndex: Integer): Integer;
var
  mClose: Integer;
begin
  Result := 0;
  AIndex := 1;
  while AIndex <= Length(AText) do
  begin
    if AText[AIndex] = '<' then
    begin
      mClose := FindTop(AText, '>', AIndex + 1);
      if mClose = 0 then
      begin
        Exit;
      end;
      AIndex := mClose + 1;
      Continue;
    end;
    if CharInSet(AText[AIndex], [':', ';', '=']) then
    begin
      Exit;
    end;
    if AText[AIndex] = AOpenChar then
    begin
      Exit(AIndex);
    end;
    Inc(AIndex);
  end;
end;

/// <summary>[Ref] und andere Attribute vorn weglassen.</summary>
function StripAttributes(const ANames: string): string;
begin
  Result := ANames;
  while Result.StartsWith('[') and (Pos(']', Result) > 0) do
  begin
    Result := Trim(Copy(Result, Pos(']', Result) + 1, MaxInt));
  end;
end;

/// <summary>Art (const/var/out/constref) vorn abtrennen; '' ohne.</summary>
function TakeModifier(var ANames: string): string;
const
  cModifiers: array[0..3] of string = ('const', 'var', 'out', 'constref');
var
  mWord: string;
begin
  Result := '';
  for mWord in cModifiers do
  begin
    if LowerCase(ANames).StartsWith(mWord + ' ') then
    begin
      ANames := Trim(Copy(ANames, Length(mWord) + 1, MaxInt));
      Exit(mWord);
    end;
  end;
end;

/// <summary>Namen und Typ einer Gruppe "const A, B: string = ''".</summary>
procedure SplitGroup(const AGroup: string; out ANames, ATypeName: string);
var
  mColon, mEqual: Integer;
begin
  mColon := FindTop(AGroup, ':', 1);
  if mColon = 0 then
  begin
    ANames := AGroup;
    ATypeName := '';
    Exit;
  end;
  ANames := Trim(Copy(AGroup, 1, mColon - 1));
  ATypeName := Trim(Copy(AGroup, mColon + 1, MaxInt));
  mEqual := FindTop(ATypeName, '=', 1);
  if mEqual > 0 then
  begin
    ATypeName := Trim(Copy(ATypeName, 1, mEqual - 1));
  end;
end;

/// <summary>Parameter einer Gruppe; Attribute stehen vor oder nach der Art.</summary>
function GroupParams(const AGroup: string): TArray<TDpccDocParam>;
var
  mNames, mTypeName, mModifier, mName: string;
  mParam: TDpccDocParam;
begin
  Result := nil;
  SplitGroup(AGroup, mNames, mTypeName);
  mNames := StripAttributes(mNames);
  mModifier := TakeModifier(mNames);
  mNames := StripAttributes(mNames);
  for mName in SplitTop(mNames, ',') do
  begin
    if mName <> '' then
    begin
      mParam.Name := mName;
      mParam.Modifier := mModifier;
      mParam.TypeName := mTypeName;
      Result := Result + [mParam];
    end;
  end;
end;

/// <summary>Ergebnis- bzw. Property-Typ: nach ":" bis ";" oder bis zum ersten Wort von read/write/index/default;
/// '' ohne Doppelpunkt.</summary>
function ResultTypeOf(const ARest: string): string;
const
  cDirectives: array[0..6] of string = ('read', 'write', 'index', 'default', 'stored', 'nodefault', 'implements');
var
  mWord: string;
  mStop: Integer;
begin
  Result := Trim(ARest);
  if not Result.StartsWith(':') then
  begin
    Exit('');
  end;
  Result := Trim(Copy(Result, 2, MaxInt));
  mStop := FindTop(Result, ';', 1);
  if mStop > 0 then
  begin
    Result := Copy(Result, 1, mStop - 1);
  end;
  for mWord in cDirectives do
  begin
    mStop := Pos(' ' + mWord + ' ', LowerCase(Result) + ' ');
    if mStop > 0 then
    begin
      Result := Copy(Result, 1, mStop - 1);
    end;
  end;
  Result := Trim(Result);
end;

class function TDpccDocSignature.Parse(const ADeclaration: string): TDpccDocSignature;
var
  mText, mGroup, mWord, mRest: string;
  mOpen, mClose, mIndex: Integer;
  mOpenChar, mCloseChar: Char;
begin
  Result := Default(TDpccDocSignature);
  mText := Trim(StringReplace(StringReplace(ADeclaration, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]));
  mWord := SignatureWord(mText);
  if mWord = '' then
  begin
    Exit;
  end;
  // Parameterliste: erste runde (bzw. bei Properties eckige) Klammer nach dem Namen, außerhalb von Generics.
  Result.IsProperty := mWord = 'property';
  mOpenChar := '(';
  mCloseChar := ')';
  if Result.IsProperty then
  begin
    mOpenChar := '[';
    mCloseChar := ']';
  end;
  mOpen := FindParamOpen(mText, mOpenChar, mIndex);
  mRest := Copy(mText, mIndex, MaxInt);
  if mOpen > 0 then
  begin
    mClose := FindTop(mText, mCloseChar, mOpen + 1);
    if mClose = 0 then
    begin
      Exit;
    end;
    for mGroup in SplitTop(Copy(mText, mOpen + 1, mClose - mOpen - 1), ';') do
    begin
      if mGroup <> '' then
      begin
        Result.Params := Result.Params + GroupParams(mGroup);
      end;
    end;
    mRest := Copy(mText, mClose + 1, MaxInt);
  end;
  Result.Known := True;
  Result.ResultType := ResultTypeOf(mRest);
end;

end.
