unit dpcc.Core.Hover.Plain;

// Inhalt des Hover-Tooltips, Teil ohne VCL (S3, seit S3b wieder mit allem, was der Tooltip vor S3 zeigte):
// was der Tooltip zeigt, als schlichte Abschnitte in fester Reihenfolge (Sections) wie im Detailpanel der
// Vervollständigung. Das Fenster (dpcc.UI.Hover.Tip) zeichnet die Abschnitte nur noch der Reihe nach.
//   DebugValue:    Wert des Ausdrucks unter der Maus im angehaltenen Debugger (#891): Ausdruck, darunter der Wert
//                  bzw. „wird ausgewertet …“. Kennt der Server den Bezeichner nicht, steht nur dieser Abschnitt da.
//   Headline:      Art und Signatur, z. B. "constructor  Create(const AFileName: string; Mode: Word)"; die Art steht
//                  am Anfang der Deklaration (procedure, function, property …) oder folgt aus der Art des Servers
//                  (type, const, var, field). Die Signatur darf umbrechen.
//   Origin:        Art in Worten, Bibliothek und Herkunft: "Konstruktor · RTL · System.Classes.TFileStream"; ohne
//                  Unit (aktuelle Datei) die Unit der Datei.
//   Location:      Fundort "System.Classes.pas : 1234", wenn der Server ihn kennt.
//   Notes:         Wert ("= 48") und Veraltung (deprecated, platform, experimental).
//   Documentation: die ganze XMLDoc (summary, Parameter in der Reihenfolge der Signatur, Rückgabe, Wert, Ausnahmen,
//                  Hinweise, Beispiel, Siehe auch, Begründung, Inhalt einer Unit) über denselben Satz wie im
//                  Detailpanel (TDpccDocContent); Parameter und Rückgabe stehen auch ohne XMLDoc da (wie vor S3 mit
//                  hover.signatureParams). Ohne strukturierte Doku (fremder Server, Markdown) der Klartext.
//   Members:       published-Properties und Ereignisse einer Komponentenklasse samt geerbter (#110): Zusammenfassung,
//                  je Abschnitt die ersten cPropertyRows bzw. cEventRows Zeilen (wie vor S3 ohne Klick), danach
//                  „+ n weitere …“; dazu die Standard-Property.
//   Chain:         Vererbungskette bzw. Zieltyp einer Klassenreferenz, mehr als fünf Glieder gekürzt.
// Leere Abschnitte entfallen.
// Antworten ohne "dpcc" sind Markdown (TDpccHoverData.Markdown; Direktiven, Schlüsselwörter, fremde Server): Die
// Kopfzeile verliert **, ` und [Text](URL) (nur Text); in der Doku entfallen Trennlinien (---), **fett**, `Code` und
// [Text](URL) werden Läufe (fett, Editorschrift, Link) statt Zeichen im Klartext (LOOK4).

interface

uses
  dpcc.Core.Hover.Contract,
  dpcc.Core.Hover.DebugValue,
  dpcc.Core.Hover.Texts,
  dpcc.Core.Style.Look,
  dpcc.Core.Documentation.Contract,
  dpcc.Core.Documentation.Typeset;

type
  {$SCOPEDENUMS ON}
  /// <summary>Abschnitte des Tooltips in der Reihenfolge der Anzeige.</summary>
  TDpccPlainHoverSection = (DebugValue, Headline, Origin, Location, Notes, Documentation, Members, Chain);
  {$SCOPEDENUMS OFF}

  /// <summary>Zeile einer Tabelle der published-Mitglieder: Name, Typ, Vorgabe (Ereignisse: Hinweis
  /// „(of object)“ bzw. ''), deklarierende Klasse.</summary>
  TDpccPlainHoverRow = record
    Name: string;
    TypeName: string;
    DefaultText: string;
    Declared: string;
  end;

  /// <summary>Abschnitt Properties bzw. Ereignisse: Überschrift, gezeigte Zeilen, „+ n weitere …“ und Hinweis.
  /// </summary>
  TDpccPlainHoverTable = record
    Caption: string;
    Rows: TArray<TDpccPlainHoverRow>;
    /// <summary>„+ 31 weitere Properties“; '' wenn alle Zeilen dastehen.</summary>
    More: string;
    /// <summary>Ereignisse: woran sie erkannt sind; sonst ''.</summary>
    Note: string;
    function IsEmpty: Boolean;
  end;

  TDpccPlainHover = record
  public const
    /// <summary>Höchstens so viele Zeichen Kurztext für die Sprachausgabe.</summary>
    cMaxSummaryChars = 1000;
    /// <summary>Abstand zwischen Art und Signatur (wie in der Liste der Vervollständigung).</summary>
    cKindGap = '  ';
    /// <summary>So viele Zeilen zeigen die Tabellen der published-Mitglieder (wie vor S3 vor dem Klick auf
    /// „+ n weitere“).</summary>
    cPropertyRows = 7;
    cEventRows = 4;
    /// <summary>Höchstens so viele Zeilen Wert im Debugger.</summary>
    cDebugValueLines = 6;
    cChainSeparator = ' › ';
  public
    /// <summary>Wert im angehaltenen Debugger (#891); Visible = False ohne.</summary>
    Debug: TDpccDebugValue;
    /// <summary>Text unter dem Ausdruck: Wert bzw. „wird ausgewertet …“.</summary>
    DebugText: string;
    /// <summary>Deklaration, wie der Server sie liefert (ordnet die Parameter der Doku).</summary>
    Declaration: string;
    /// <summary>Art der Deklaration (constructor, function, type …); '' ohne.</summary>
    Kind: string;
    /// <summary>Deklaration ohne Art und abschließendes Semikolon, Leerraum zusammengefasst.</summary>
    Signature: string;
    /// <summary>Art in Worten (Konstruktor, Klasse …); '' ohne.</summary>
    KindCaption: string;
    /// <summary>VCL, FMX, RTL; '' bei eigenen Units.</summary>
    Framework: string;
    /// <summary>Unit bzw. Unit.Typ; '' ohne.</summary>
    Origin: string;
    /// <summary>"Datei.pas : 20"; '' ohne Fundort.</summary>
    Location: string;
    Value: string;
    Deprecation: string;
    /// <summary>Kurztext (summary) als Fließtext für die Sprachausgabe; '' ohne Doku.</summary>
    Summary: string;
    /// <summary>XMLDoc bzw. Klartext als Beschreibung.</summary>
    Doc: TDpccDoc;
    Display: TDpccDocDisplay;
    /// <summary>„published: 38 Properties · 24 Ereignisse“; '' ohne Mitglieder.</summary>
    MembersSummary: string;
    Properties: TDpccPlainHoverTable;
    Events: TDpccPlainHoverTable;
    /// <summary>Standard-Property bis „]“, z. B. "Strings[Index: Integer]"; '' ohne.</summary>
    DefaultProperty: string;
    DefaultPropertyCaption: string;
    DefaultPropertyLabel: string;
    DefaultPropertyNote: string;
    /// <summary>Hinweis unter den Mitgliedern (geerbte VCL-Mitglieder nur mit VCL-Quellen im Index).</summary>
    MembersNote: string;
    /// <summary>„Vererbung“ bzw. „Zieltyp TBFrame“; '' ohne Kette.</summary>
    ChainCaption: string;
    /// <summary>"TBFrame › TFrame › … › TObject".</summary>
    Chain: string;
    /// <summary>Zeile 1: Art, zwei Leerzeichen, Signatur (ohne Art nur die Signatur).</summary>
    function Headline: string;
    /// <summary>Gruppe der Art für die Farbe der Art in der Kopfzeile (LOOK2, TDpccLook.Kind): „class function“
    /// wie „function“, operator als Routine, program/library/package wie unit, resourcestring als Konstante,
    /// threadvar als Variable; None ohne Art.</summary>
    function KindGroup: TDpccKindGroup;
    /// <summary>Art in Worten · Bibliothek · Unit.Typ, leere Teile entfallen.</summary>
    function OriginLine: string;
    /// <summary>Wert ("= 48"); '' ohne.</summary>
    function ValueLine: string;
    /// <summary>Doku für den Satz des Detailpanels: ganz aufgeklappt, ohne Schalter, mit offener Signatur.</summary>
    function DocContent: TDpccDocContent;
    /// <summary>Hat der Abschnitt Inhalt?</summary>
    function Has(ASection: TDpccPlainHoverSection): Boolean;
    /// <summary>Abschnitte mit Inhalt in der Reihenfolge der Anzeige.</summary>
    function Sections: TArray<TDpccPlainHoverSection>;
    /// <summary>Text für die Sprachausgabe: Wert im Debugger, Zeile 1, Herkunft und Kurztext.</summary>
    function Spoken: string;
    function HasSummary: Boolean;
    /// <summary>Zusammenstellung aus der Antwort des Servers; ACurrentUnit gilt, wenn der Server keine Unit nennt
    /// (Deklaration in der aktuellen Datei). ATexts: Texte der Oberfläche, ADebug: Wert im Debugger.</summary>
    class function From(const AData: TDpccHoverData; const ACurrentUnit: string; const ATexts: TDpccHoverTexts;
      const ADebug: TDpccDebugValue): TDpccPlainHover; overload; static;
    /// <summary>Wie oben ohne Texte der Oberfläche und ohne Wert im Debugger.</summary>
    class function From(const AData: TDpccHoverData; const ACurrentUnit: string): TDpccPlainHover; overload; static;
    /// <summary>Unit einer Datei: Dateiname ohne Pfad und Endung ('' ohne Datei).</summary>
    class function UnitOfFile(const AFileName: string): string; static;
    /// <summary>Länge des Namens am Anfang der Signatur (Bezeichner mit Punkten, &amp;), den die Kopfzeile fett
    /// zeigt wie die Code-Insight-Liste (S3c); 0 ohne.</summary>
    class function NameLength(const ASignature: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math;

/// <summary>Leerraum (auch Zeilenumbrüche, Tabulatoren) zu einzelnen Leerzeichen.</summary>
function Collapse(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mChar: Char;
  mSpace: Boolean;
begin
  mBuilder := TStringBuilder.Create(Length(AText));
  try
    mSpace := False;
    for mChar in AText do
    begin
      if CharInSet(mChar, [#9, #10, #13, ' ']) then
      begin
        mSpace := True;
        Continue;
      end;
      if mSpace and (mBuilder.Length > 0) then
      begin
        mBuilder.Append(' ');
      end;
      mSpace := False;
      mBuilder.Append(mChar);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Zeile nur aus ---, *** bzw. ___ (Trennlinie im Markdown, Leerzeichen dazwischen erlaubt).</summary>
function IsRule(const ALine: string): Boolean;
var
  mLine: string;
  mChar: Char;
begin
  mLine := StringReplace(Trim(ALine), ' ', '', [rfReplaceAll]);
  Result := (Length(mLine) >= 3) and CharInSet(mLine[1], ['-', '*', '_']);
  if not Result then
  begin
    Exit;
  end;
  for mChar in mLine do
  begin
    if mChar <> mLine[1] then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Trennlinien (---) des Markdowns entfernen; an ihrer Stelle bleibt eine Leerzeile (Absatz).</summary>
function WithoutRules(const AText: string): string;
var
  mLine: string;
  mLines: TArray<string>;
begin
  mLines := nil;
  for mLine in StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]) do
  begin
    if IsRule(mLine) then
    begin
      mLines := mLines + [''];
    end
    else
    begin
      mLines := mLines + [mLine];
    end;
  end;
  Result := Trim(string.Join(string(#10), mLines));
end;

/// <summary>Link [Text](URL) ab AStart ('['): Text, Ziel und Stelle hinter der schließenden Klammer. Klammern im
/// Ziel zählen paarweise (…/IFNDEF_directive_(Delphi)). False, wenn dort kein Link steht.</summary>
function TryLink(const AText: string; AStart: Integer; out ALabel, ATarget: string; out ANext: Integer): Boolean;
var
  mClose, mIndex, mDepth: Integer;
begin
  Result := False;
  ALabel := '';
  ATarget := '';
  ANext := AStart;
  mClose := PosEx(']', AText, AStart + 1);
  if (mClose = 0) or (mClose >= Length(AText)) or (AText[mClose + 1] <> '(') then
  begin
    Exit;
  end;
  mDepth := 0;
  for mIndex := mClose + 1 to Length(AText) do
  begin
    if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        ALabel := Copy(AText, AStart + 1, mClose - AStart - 1);
        ATarget := Copy(AText, mClose + 2, mIndex - mClose - 2);
        ANext := mIndex + 1;
        Exit(ALabel <> '');
      end;
    end;
  end;
end;

/// <summary>Läufe eines Texts mit Markdown-Auszeichnung: **fett** als fetter Text, `Code` in der Editorschrift,
/// [Text](URL) als Link mit dem Text; Zeichen ohne Gegenstück bleiben stehen.</summary>
function InlineRuns(const AText: string): TDpccDocRuns;
var
  mRuns: TDpccDocRuns;
  mRun: TDpccDocRun;
  mPlain, mLabel, mTarget: string;
  mIndex, mClose, mNext: Integer;

  procedure Flush;
  begin
    if mPlain <> '' then
    begin
      mRuns := mRuns + [TDpccDocRun.Create(TDpccDocRunKind.Text, mPlain)];
      mPlain := '';
    end;
  end;

begin
  mRuns := nil;
  mPlain := '';
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if Copy(AText, mIndex, 2) = '**' then
    begin
      mClose := PosEx('**', AText, mIndex + 2);
      if mClose > mIndex + 2 then
      begin
        Flush;
        mRun := TDpccDocRun.Create(TDpccDocRunKind.Text,
          StringReplace(Copy(AText, mIndex + 2, mClose - mIndex - 2), '`', '', [rfReplaceAll]));
        mRun.Bold := True;
        mRuns := mRuns + [mRun];
        mIndex := mClose + 2;
        Continue;
      end;
    end
    else if AText[mIndex] = '`' then
    begin
      mClose := PosEx('`', AText, mIndex + 1);
      if mClose > mIndex + 1 then
      begin
        Flush;
        mRuns := mRuns + [TDpccDocRun.Create(TDpccDocRunKind.Code, Copy(AText, mIndex + 1, mClose - mIndex - 1))];
        mIndex := mClose + 1;
        Continue;
      end;
    end
    else if (AText[mIndex] = '[') and TryLink(AText, mIndex, mLabel, mTarget, mNext) then
    begin
      Flush;
      mLabel := StringReplace(StringReplace(mLabel, '**', '', [rfReplaceAll]), '`', '', [rfReplaceAll]);
      mRuns := mRuns + [TDpccDocRun.Create(TDpccDocRunKind.Link, mLabel, mTarget)];
      mIndex := mNext;
      Continue;
    end;
    mPlain := mPlain + AText[mIndex];
    Inc(mIndex);
  end;
  Flush;
  Result := mRuns;
end;

/// <summary>Markdown-Auszeichnung im Fließtext entfernen: **fett**, `Code`, [Text](URL) wird Text.</summary>
function WithoutMarks(const AText: string): string;
var
  mRun: TDpccDocRun;
begin
  Result := '';
  for mRun in InlineRuns(AText) do
  begin
    Result := Result + mRun.Text;
  end;
end;

/// <summary>Doku aus Markdown (Direktiven, Schlüsselwörter, fremde Server; LOOK4): Absätze und eingerückter Code
/// wie TDpccDoc.FromText; Trennlinien (---) entfallen (die Doku steht schon unter einer Trennlinie); **fett**,
/// `Code` und [Text](URL) werden Läufe (fett, Editorschrift, Link mit URL als Ziel).</summary>
function MarkdownDoc(const AText: string): TDpccDoc;
var
  mSection: Integer;
  mRuns: TDpccDocRuns;
  mRun: TDpccDocRun;
begin
  Result := TDpccDoc.FromText(WithoutRules(AText));
  for mSection := 0 to High(Result.Sections) do
  begin
    mRuns := nil;
    for mRun in Result.Sections[mSection].Runs do
    begin
      if mRun.Kind = TDpccDocRunKind.Text then
      begin
        mRuns := mRuns + InlineRuns(mRun.Text);
      end
      else
      begin
        mRuns := mRuns + [mRun];
      end;
    end;
    Result.Sections[mSection].Runs := mRuns;
  end;
end;

/// <summary>Teile mit ASeparator verbinden; leere entfallen.</summary>
function Joined(const AParts: array of string; const ASeparator: string): string;
var
  mPart: string;
begin
  Result := '';
  for mPart in AParts do
  begin
    if mPart = '' then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + ASeparator;
    end;
    Result := Result + mPart;
  end;
end;

/// <summary>Art am Anfang der Deklaration (auch „class function“); '' ohne.</summary>
function LeadingKind(const ADeclaration: string; out ARest: string): string;
const
  cWords: array[0..12] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator', 'property',
    'unit', 'program', 'library', 'package', 'resourcestring', 'threadvar', 'var');
var
  mWord, mText: string;
  mPrefix: string;
begin
  Result := '';
  ARest := ADeclaration;
  mText := ADeclaration;
  mPrefix := '';
  if StartsText('class ', mText) then
  begin
    mPrefix := 'class ';
    mText := TrimLeft(Copy(mText, Length('class ') + 1, MaxInt));
  end;
  for mWord in cWords do
  begin
    if StartsText(mWord + ' ', mText) or SameText(mWord, mText) then
    begin
      Result := mPrefix + mWord;
      ARest := TrimLeft(Copy(mText, Length(mWord) + 1, MaxInt));
      Exit;
    end;
  end;
end;

/// <summary>Art aus der Art des Servers, wenn die Deklaration keine nennt.</summary>
function KindWord(const AKind: string): string;
begin
  if MatchStr(AKind, ['class', 'classref', 'object', 'record', 'interface', 'helper', 'enum', 'type']) then
  begin
    Result := 'type';
  end
  else if MatchStr(AKind, ['constant', 'enumMember']) then
  begin
    Result := 'const';
  end
  else if AKind = 'variable' then
  begin
    Result := 'var';
  end
  else if AKind = 'field' then
  begin
    Result := 'field';
  end
  else if AKind = 'property' then
  begin
    Result := 'property';
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Unit bzw. Unit.Typ; eine Include-Datei hinter der Unit („Unit (Datei.inc)“) bleibt hinten.</summary>
function OriginOf(const AUnit, AContainer: string): string;
var
  mUnit, mSuffix: string;
  mSplit: Integer;
begin
  mUnit := Trim(AUnit);
  mSuffix := '';
  mSplit := Pos(' (', mUnit);
  if mSplit > 0 then
  begin
    mSuffix := Copy(mUnit, mSplit, MaxInt);
    mUnit := Copy(mUnit, 1, mSplit - 1);
  end;
  if AContainer = '' then
  begin
    Result := mUnit;
  end
  else if mUnit = '' then
  begin
    Result := AContainer;
  end
  else
  begin
    Result := mUnit + '.' + AContainer;
  end;
  Result := Result + mSuffix;
end;

/// <summary>Kurztext: summary der XMLDoc; ohne strukturierte Doku der erste Absatz des Klartexts.</summary>
function SummaryOf(const AData: TDpccHoverData): string;
var
  mSection: TDpccDocSection;
  mText: string;
  mSplit: Integer;
begin
  Result := '';
  for mSection in AData.Doc.SectionsOf(TDpccDocSectionKind.Summary) do
  begin
    Result := Result + ' ' + mSection.Text;
  end;
  if (Trim(Result) = '') and AData.Doc.IsEmpty then
  begin
    // Ohne Trennlinien (---), sonst wäre sie der erste Absatz.
    mText := WithoutRules(AData.Documentation);
    mSplit := Pos(#10#10, mText);
    if mSplit > 0 then
    begin
      mText := Copy(mText, 1, mSplit - 1);
    end;
    Result := WithoutMarks(mText);
  end;
  Result := Collapse(Result);
  if Length(Result) > TDpccPlainHover.cMaxSummaryChars then
  begin
    // An einem Leerzeichen kürzen.
    mSplit := TDpccPlainHover.cMaxSummaryChars;
    while (mSplit > 1) and (Result[mSplit] <> ' ') do
    begin
      Dec(mSplit);
    end;
    if mSplit <= 1 then
    begin
      mSplit := TDpccPlainHover.cMaxSummaryChars;
    end;
    Result := TrimRight(Copy(Result, 1, mSplit)) + ' …';
  end;
end;

/// <summary>Text unter dem Ausdruck im Debugger: Wert, „wird ausgewertet …“ bzw. die Erklärung „kein Zugriff“.
/// </summary>
function DebugTextOf(const ADebug: TDpccDebugValue; const ATexts: TDpccHoverTexts): string;
begin
  if ADebug.State = TDpccDebugValueState.Pending then
  begin
    Result := ATexts.DebugPending;
  end
  else if ADebug.Explained then
  begin
    Result := Joined([ADebug.Note.Caption, ADebug.Note.Reason, ADebug.Note.Origin], sLineBreak);
  end
  else
  begin
    Result := ADebug.Text;
  end;
end;

/// <summary>Properties (AEvents False) bzw. Ereignisse samt geerbter, die ersten ALimit Zeilen.</summary>
function TableOf(const AData: TDpccHoverData; AEvents: Boolean; ALimit: Integer; const ACaption, AMoreFormat,
  AImplicit: string): TDpccPlainHoverTable;
var
  mIndices: TArray<Integer>;
  mIndex: Integer;
  mMember: TDpccHoverMember;
  mRow: TDpccPlainHoverRow;
begin
  Result := Default(TDpccPlainHoverTable);
  // Vorgaben wie vor S3: geerbte zeigen, nicht nur Properties mit Vorgabe.
  mIndices := AData.VisibleMembers(AEvents, True, False);
  if Length(mIndices) = 0 then
  begin
    Exit;
  end;
  Result.Caption := ACaption;
  for mIndex := 0 to Min(High(mIndices), ALimit - 1) do
  begin
    mMember := AData.Members[mIndices[mIndex]];
    mRow := Default(TDpccPlainHoverRow);
    mRow.Name := mMember.Name;
    mRow.TypeName := mMember.TypeName;
    if not AEvents then
    begin
      mRow.DefaultText := mMember.DefaultText(AImplicit);
    end
    // Am Methodenzeiger-Typ erkannt, nicht am Namen: fremde Typnamen kenntlich machen.
    else if not EndsText('Event', mMember.TypeName) then
    begin
      mRow.DefaultText := '(of object)';
    end;
    mRow.Declared := mMember.DeclaringClass;
    Result.Rows := Result.Rows + [mRow];
  end;
  if (Length(mIndices) > ALimit) and (AMoreFormat <> '') then
  begin
    Result.More := Format(AMoreFormat, [Length(mIndices) - ALimit]);
  end;
end;

/// <summary>Kette als Text: Glieder mit „ › “, „…“ für ausgelassene.</summary>
function ChainOf(const AData: TDpccHoverData): string;
var
  mIndex: Integer;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mIndex in AData.VisibleChain do
  begin
    if mIndex < 0 then
    begin
      mParts := mParts + ['…'];
    end
    else
    begin
      mParts := mParts + [AData.Ancestors[mIndex].Name];
    end;
  end;
  Result := string.Join(TDpccPlainHover.cChainSeparator, mParts);
end;

{ TDpccPlainHoverTable }

function TDpccPlainHoverTable.IsEmpty: Boolean;
begin
  Result := Length(Rows) = 0;
end;

{ TDpccPlainHover }

function TDpccPlainHover.Headline: string;
begin
  if Kind = '' then
  begin
    Result := Signature;
  end
  else if Signature = '' then
  begin
    Result := Kind;
  end
  else
  begin
    Result := Kind + cKindGap + Signature;
  end;
end;

function TDpccPlainHover.KindGroup: TDpccKindGroup;
var
  mWord: string;
begin
  mWord := Trim(Kind);
  if StartsText('class ', mWord) then
  begin
    mWord := Trim(Copy(mWord, Length('class ') + 1, MaxInt));
  end;
  if SameText(mWord, 'operator') then
  begin
    Result := TDpccKindGroup.Routine;
  end
  else if MatchText(mWord, ['program', 'library', 'package']) then
  begin
    Result := TDpccKindGroup.TypeName;
  end
  else if SameText(mWord, 'resourcestring') then
  begin
    Result := TDpccKindGroup.Constant;
  end
  else if SameText(mWord, 'threadvar') then
  begin
    Result := TDpccKindGroup.Variable;
  end
  else
  begin
    Result := TDpccLook.KindGroupOf(mWord);
  end;
end;

function TDpccPlainHover.OriginLine: string;
begin
  Result := Joined([KindCaption, Framework, Origin], ' · ');
end;

function TDpccPlainHover.ValueLine: string;
begin
  Result := '';
  if Value <> '' then
  begin
    Result := '= ' + Value;
  end;
end;

function TDpccPlainHover.DocContent: TDpccDocContent;
begin
  Result := TDpccDocContent.Create(Doc, TDpccDocSignature.Parse(Declaration), True);
  Result.OpenSignature := True;
  Result.Fixed := True;
  // Parameternamen wie Bezeichner der Code-Insight-Liste, nicht fett in Akzentfarbe (S3c).
  Result.PlainNames := True;
end;

function TDpccPlainHover.Has(ASection: TDpccPlainHoverSection): Boolean;
var
  mContent: TDpccDocContent;
begin
  case ASection of
    TDpccPlainHoverSection.DebugValue:
      Result := Debug.Visible;
    TDpccPlainHoverSection.Headline:
      Result := Headline <> '';
    TDpccPlainHoverSection.Origin:
      Result := (Headline <> '') and (OriginLine <> '');
    TDpccPlainHoverSection.Location:
      Result := (Headline <> '') and (Location <> '');
    TDpccPlainHoverSection.Notes:
      Result := (Headline <> '') and ((Value <> '') or (Deprecation <> ''));
    TDpccPlainHoverSection.Documentation:
      begin
        mContent := DocContent;
        Result := (Headline <> '') and (not mContent.Doc.IsEmpty or mContent.SignatureShown);
      end;
    TDpccPlainHoverSection.Members:
      Result := (Headline <> '') and (not Properties.IsEmpty or not Events.IsEmpty or (DefaultProperty <> ''));
    TDpccPlainHoverSection.Chain:
      Result := (Headline <> '') and (Chain <> '');
  else
    Result := False;
  end;
end;

function TDpccPlainHover.Sections: TArray<TDpccPlainHoverSection>;
var
  mSection: TDpccPlainHoverSection;
begin
  Result := nil;
  for mSection := Low(TDpccPlainHoverSection) to High(TDpccPlainHoverSection) do
  begin
    if Has(mSection) then
    begin
      Result := Result + [mSection];
    end;
  end;
end;

function TDpccPlainHover.HasSummary: Boolean;
begin
  Result := Summary <> '';
end;

function TDpccPlainHover.Spoken: string;
var
  mDebug: string;
begin
  mDebug := '';
  if Debug.Visible then
  begin
    mDebug := Debug.Expression + ' = ' + DebugText;
  end;
  Result := Joined([mDebug, Headline, OriginLine, Summary], '. ');
end;

class function TDpccPlainHover.From(const AData: TDpccHoverData; const ACurrentUnit: string): TDpccPlainHover;
begin
  Result := From(AData, ACurrentUnit, Default(TDpccHoverTexts), Default(TDpccDebugValue));
end;

class function TDpccPlainHover.From(const AData: TDpccHoverData; const ACurrentUnit: string;
  const ATexts: TDpccHoverTexts; const ADebug: TDpccDebugValue): TDpccPlainHover;
var
  mDeclaration, mRest: string;
  mUnit: string;
  mBracket: Integer;
begin
  Result := Default(TDpccPlainHover);
  Result.Debug := ADebug;
  Result.DebugText := DebugTextOf(ADebug, ATexts);
  if not AData.Found then
  begin
    Exit;
  end;
  Result.Declaration := AData.Declaration;
  mDeclaration := Collapse(AData.Declaration);
  if EndsText(';', mDeclaration) then
  begin
    mDeclaration := TrimRight(Copy(mDeclaration, 1, Length(mDeclaration) - 1));
  end;
  Result.Kind := LeadingKind(mDeclaration, mRest);
  if Result.Kind <> '' then
  begin
    Result.Signature := mRest;
  end
  else
  begin
    Result.Kind := KindWord(AData.Kind);
    Result.Signature := mDeclaration;
  end;
  // Markdown ohne "dpcc" (Direktive, Schlüsselwort, fremder Server): Auszeichnung erst nach der Art auflösen, damit
  // „**function** (Schlüsselwort)“ keine Art-Spalte bekommt. „**AUTOREFCOUNT**: nicht definiert …“ wird
  // „AUTOREFCOUNT: …“; den Namen am Anfang zeigt die Kopfzeile ohnehin fett (NameLength).
  if AData.Markdown then
  begin
    Result.Signature := WithoutMarks(Result.Signature);
  end;
  Result.KindCaption := ATexts.KindCaption;
  Result.Framework := AData.Origin;
  mUnit := AData.UnitName;
  if mUnit = '' then
  begin
    mUnit := ACurrentUnit;
  end;
  // Über einem Unit-Namen ist die Unit selbst die Zeile 1; keine Herkunft.
  if not SameText(Result.Kind, 'unit') then
  begin
    Result.Origin := OriginOf(mUnit, AData.Container);
  end;
  if AData.Location.HasLocation then
  begin
    Result.Location := AData.LocationText;
  end;
  Result.Value := AData.Value;
  Result.Deprecation := AData.Deprecation;
  Result.Summary := SummaryOf(AData);
  // Fremde Server liefern nur Klartext: als Beschreibung, ohne Kürzen.
  Result.Doc := AData.Doc;
  if Result.Doc.IsEmpty and (Trim(AData.Documentation) <> '') then
  begin
    if AData.Markdown then
    begin
      // Ohne „---“ und Sterne; [DocWiki](URL) als Link (LOOK4).
      Result.Doc := MarkdownDoc(AData.Documentation);
    end
    else
    begin
      Result.Doc := TDpccDoc.FromText(AData.Documentation);
    end;
  end;
  Result.Display := AData.Display;
  // published-Mitglieder (#110).
  if Length(AData.Members) > 0 then
  begin
    Result.MembersSummary := Format(ATexts.PublishedSummary, [AData.MemberCount(False), AData.MemberCount(True)]);
    Result.Properties := TableOf(AData, False, cPropertyRows, ATexts.PublishedProperties,
      ATexts.PublishedMoreProperties, ATexts.PublishedImplicit);
    Result.Events := TableOf(AData, True, cEventRows, ATexts.PublishedEvents, ATexts.PublishedMoreEvents,
      ATexts.PublishedImplicit);
    if not Result.Events.IsEmpty then
    begin
      Result.Events.Note := ATexts.PublishedEventsNote;
    end;
    Result.MembersNote := ATexts.PublishedVclNote;
  end;
  if AData.DefaultProperty <> '' then
  begin
    // „default“ heißt an einer Array-Property nicht Vorgabewert.
    Result.DefaultProperty := AData.DefaultProperty;
    mBracket := Pos(']', Result.DefaultProperty);
    if mBracket > 0 then
    begin
      Result.DefaultProperty := Copy(Result.DefaultProperty, 1, mBracket);
    end;
    Result.DefaultPropertyCaption := ATexts.PublishedArrayProperty;
    Result.DefaultPropertyLabel := ATexts.PublishedDefaultProperty;
    Result.DefaultPropertyNote := ATexts.PublishedDefaultPropertyNote;
  end;
  // Vererbung bzw. Zieltyp einer Klassenreferenz.
  if Length(AData.Ancestors) > 0 then
  begin
    Result.Chain := ChainOf(AData);
    if AData.Kind = TDpccHoverData.cKindClassRef then
    begin
      if ATexts.TargetType <> '' then
      begin
        Result.ChainCaption := Format(ATexts.TargetType, [AData.ChainOf]);
      end;
    end
    else
    begin
      Result.ChainCaption := ATexts.Inheritance;
    end;
  end;
end;

class function TDpccPlainHover.UnitOfFile(const AFileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AFileName), '');
end;

class function TDpccPlainHover.NameLength(const ASignature: string): Integer;
begin
  Result := 0;
  while (Result < Length(ASignature)) and (CharInSet(ASignature[Result + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_',
    '.', '&']) or (Ord(ASignature[Result + 1]) > 127)) do
  begin
    Inc(Result);
  end;
end;

end.
