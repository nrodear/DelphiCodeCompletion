unit dpcc.Core.Documentation.Typeset;

// Satz der XMLDoc (#654, #770): baut aus der strukturierten Doku die Zeilen, Stücke und Links eines
// TDpccDocLayout (dpcc.Core.Documentation.Layout, dort Typen und Abfragen). TLayoutBuilder setzt Läufe mit
// Umbruch, Codeblöcken, Listen und Spalten; TDocSections ordnet die Abschnitte in fester Reihenfolge (PARAMETER,
// TYPPARAMETER, RÜCKGABE, WERT, AUSNAHMEN, HINWEISE, BEISPIEL, SIEHE AUCH, BEGRÜNDUNG) und setzt den Schalter
// „Mehr/Weniger anzeigen“. Der Inhalt einer Unit (#1921) steht zuletzt und immer offen: je Überschrift des
// Servers die Gruppen als Zeilen mit Gruppenname und Namen.
//
// Mit offener Signatur (#1919, hover.signatureParams) stehen PARAMETER und RÜCKGABE aus der Deklaration auch
// zugeklappt und ohne XMLDoc unter der Beschreibung, wie bei Help Insight; der Schalter verbirgt dann nur den Rest.

interface

uses
  System.SysUtils,
  dpcc.Core.Documentation.Contract,
  dpcc.Core.Documentation.Layout;

{$SCOPEDENUMS ON}

type
  /// <summary>Was gesetzt wird: Doku, Signatur aus der Deklaration (ordnet die Parameter) und ob aufgeklappt.
  /// </summary>
  TDpccDocContent = record
    Doc: TDpccDoc;
    Signature: TDpccDocSignature;
    Expanded: Boolean;
    /// <summary>Parameter und Rückgabe der Signatur immer offen, auch ohne XMLDoc (#1919).</summary>
    OpenSignature: Boolean;
    /// <summary>Ganz aufgeklappt ohne Schalter „Mehr/Weniger anzeigen“ (Hover-Tooltip seit S3b, ohne Klicks).
    /// </summary>
    Fixed: Boolean;
    /// <summary>Namen von Parametern und Typparametern in normaler Schrift und Textfarbe statt fett in Akzentfarbe
    /// (Hover-Tooltip seit S3c, wie Bezeichner in der Code-Insight-Liste).</summary>
    PlainNames: Boolean;
    class function Create(const ADoc: TDpccDoc; const ASignature: TDpccDocSignature;
      AExpanded: Boolean): TDpccDocContent; static;
    /// <summary>Offene Signatur mit Parametern oder Rückgabe: Diese Abschnitte stehen auch zugeklappt da.</summary>
    function SignatureShown: Boolean;
  end;

  TDpccDocTypeset = class
  public
    /// <summary>Weitere Abschnitte außer der Beschreibung: Nur dann gibt es den Schalter.</summary>
    class function IsCollapsible(const ADoc: TDpccDoc): Boolean; overload; static;
    /// <summary>Wie oben; bei offener Signatur zählen Parameter und Rückgabe nicht als verborgen.</summary>
    class function IsCollapsible(const AContent: TDpccDocContent): Boolean; overload; static;
    /// <summary>Verborgenes im zugeklappten Zustand: Text und Farbe je Teil.</summary>
    class function HiddenParts(const ADoc: TDpccDoc; const ASignature: TDpccDocSignature;
      const ALabels: TDpccDocLabels; out AColors: TArray<TDpccDocColor>): TArray<string>; overload; static;
    /// <summary>Wie oben; bei offener Signatur ohne Parameter und Rückgabe, die schon dastehen.</summary>
    class function HiddenParts(const AContent: TDpccDocContent; const ALabels: TDpccDocLabels;
      out AColors: TArray<TDpccDocColor>): TArray<string>; overload; static;
    /// <summary>Aufgeklappt, ohne Signatur.</summary>
    class function Build(const ADoc: TDpccDoc; AWidth: Integer; const AMetrics: TDpccDocMetrics;
      const AMeasure: TDpccDocMeasure; const ALabels: TDpccDocLabels): TDpccDocLayout; overload; static;
    /// <summary>Signatur des Inhalts ordnet die Parameter; Expanded = aufgeklappt.</summary>
    class function Build(const AContent: TDpccDocContent; AWidth: Integer; const AMetrics: TDpccDocMetrics;
      const AMeasure: TDpccDocMeasure; const ALabels: TDpccDocLabels): TDpccDocLayout; overload; static;
  end;

implementation

uses
  System.Math,
  dpcc.Core.Style.Syntax;

type
  /// <summary>Zelle einer Zeile mit Spalten: Läufe oder ein Text in fester Schrift und Farbe.</summary>
  TDocCell = record
    HasRuns: Boolean;
    Runs: TDpccDocRuns;
    Text: string;
    Face: TDpccDocFace;
    Color: TDpccDocColor;
    HasLink: Boolean;
    Link: TDpccDocLink;
    class function OfRuns(const ARuns: TDpccDocRuns; AColor: TDpccDocColor): TDocCell; static;
    class function OfText(const AText: string; const AFace: TDpccDocFace; AColor: TDpccDocColor): TDocCell;
      static;
  end;

  TDocRow = TArray<TDocCell>;

  /// <summary>Codefläche: Text ab Inner, Umbruch vor Right.</summary>
  TCodeArea = record
    Inner: Integer;
    Right: Integer;
  end;

  TLayoutBuilder = class
  private
    FMetrics: TDpccDocMetrics;
    FMeasure: TDpccDocMeasure;
    FLines: TArray<TDpccDocLine>;
    FLinks: TArray<TDpccDocLink>;
    FWidth: Integer;
    /// <summary>Linker Rand des Abschnitts; Absätze kehren dorthin zurück.</summary>
    FBase: Integer;
    /// <summary>Linker Rand nach einem Zeilenumbruch im Text bzw. nach automatischem Umbruch.</summary>
    FLeft: Integer;
    FHang: Integer;
    FNextStart: Integer;
    FX: Integer;
    FOpen: Boolean;
    FPendingGap: Integer;
    procedure OpenLine;
    procedure FlowCode(const AText: string; AHighlight: Boolean);
    procedure LayoutTable(const ARuns: TDpccDocRuns; var AIndex: Integer; ABaseColor: TDpccDocColor);
    procedure Merge(const ABuilders: TArray<TLayoutBuilder>; const ALefts: TArray<Integer>; AGap: Integer);
    /// <summary>Weiter in der nächsten Zeile mit hängendem Einzug.</summary>
    procedure WrapLine;
    /// <summary>Platz in der Zeile ab der aktuellen Stelle.</summary>
    function Available: Integer;
    /// <summary>Ein Wort samt folgender Leerzeichen; zu breite Wörter an Zeichen getrennt.</summary>
    procedure AddWord(const AWord: string; const AFace: TDpccDocFace; AColor: TDpccDocColor; AUnderline: Boolean;
      ALink: Integer);
    /// <summary>Neue Codezeile auf schattierter Fläche ab AShade, Text ab AStart.</summary>
    procedure StartCodeLine(AStart, AShade: Integer);
    /// <summary>Stück einer Codezeile bis ARight, zu lange an Zeichen umgebrochen und eingerückt.</summary>
    procedure AddCodePiece(const APiece: string; const AFace: TDpccDocFace; AColor: TDpccDocColor;
      const ACode: TCodeArea);
    procedure FlowBullet(const ARun: TDpccDocRun);
  public
    constructor Create(AWidth: Integer; const AMetrics: TDpccDocMetrics; const AMeasure: TDpccDocMeasure);
    procedure NewLine;
    procedure Gap(AValue: Integer);
    procedure SetBase(ALeft: Integer);
    procedure AddSpan(const AText: string; const AFace: TDpccDocFace; AColor: TDpccDocColor;
      AUnderline: Boolean; ALink: Integer);
    function AddLink(const ALink: TDpccDocLink): Integer;
    /// <summary>Text mit Umbruch an Wortgrenzen ab der aktuellen Stelle.</summary>
    procedure AddWords(const AText: string; const AFace: TDpccDocFace; AColor: TDpccDocColor); overload;
    procedure AddWords(const AText: string; const AFace: TDpccDocFace; AColor: TDpccDocColor;
      AUnderline: Boolean; ALink: Integer); overload;
    /// <summary>Text ohne Umbruch; passt er nicht mehr, in die nächste Zeile.</summary>
    procedure AddWhole(const AText: string; const AFace: TDpccDocFace; AColor: TDpccDocColor; ALink: Integer);
    procedure FlowRuns(const ARuns: TDpccDocRuns; ABaseColor: TDpccDocColor);
    /// <summary>Überschrift in Kapitälchen mit Linie bis zum rechten Rand.</summary>
    procedure Heading(const AText: string);
    /// <summary>Zeile mit Spalten der Breiten AWidths; die letzte Zelle füllt den Rest.</summary>
    procedure Columns(const ARow: TDocRow; const AWidths: TArray<Integer>);
    procedure Section(const ASection: TDpccDocSection; AColor: TDpccDocColor);
    function LineCount: Integer;
    property Lines: TArray<TDpccDocLine> read FLines;
    property Links: TArray<TDpccDocLink> read FLinks;
    property X: Integer read FX;
  end;

  /// <summary>Setzt die Abschnitte einer Doku in fester Reihenfolge in einen TLayoutBuilder.</summary>
  TDocSections = class
  private
    FBuilder: TLayoutBuilder;
    FDoc: TDpccDoc;
    FSignature: TDpccDocSignature;
    FLabels: TDpccDocLabels;
    FWidth: Integer;
    FMeasure: TDpccDocMeasure;
    FName: TDpccDocFace;
    /// <summary>Farbe der Namen von Parametern und Typparametern (Akzent bzw. mit PlainNames Text).</summary>
    FNameColor: TDpccDocColor;
    FMono: TDpccDocFace;
    FUI: TDpccDocFace;
    FNameWidth: Integer;
    FTypeWidth: Integer;
    FThreeColumns: Boolean;
    FOpenSignature: Boolean;
    function Width(const AText: string; const AFace: TDpccDocFace; APercent: Integer): Integer;
    /// <summary>Breite der Namensspalte über die ersten ACount Abschnitte, mindestens 1.</summary>
    function NameColumn(const ASections: TArray<TDpccDocSection>; ACount: Integer; const AFace: TDpccDocFace;
      APercent: Integer): Integer;
    function LinkCell(const ASection: TDpccDocSection): TDocCell;
    procedure TypeAndText(const AType: string; AKind: TDpccDocSectionKind);
    procedure ParamRow(const AName, AType: string; const ARuns: TDpccDocRuns; ANameColor, ATextColor: TDpccDocColor);
    procedure MeasureParams;
    procedure KnownParams(const ASections: TArray<TDpccDocSection>);
    procedure NamedRows(const ASections: TArray<TDpccDocSection>; ACount: Integer);
    procedure Params;
    procedure TypeParams;
    procedure ReturnsAndValue;
    procedure Exceptions;
    procedure TextSections(AKind: TDpccDocSectionKind; const ATitle: string; AColor: TDpccDocColor);
    procedure SeeAlso(AGap: Integer);
  public
    constructor Create(ABuilder: TLayoutBuilder; const AContent: TDpccDocContent; const ALabels: TDpccDocLabels;
      AWidth: Integer; const AMeasure: TDpccDocMeasure);
    procedure Summary;
    /// <summary>Alle Abschnitte außer Beschreibung und Begründung (nur aufgeklappt).</summary>
    procedure Details(AGap: Integer);
    /// <summary>Offene Signatur zugeklappt (#1919): PARAMETER und RÜCKGABE.</summary>
    procedure SignatureSections;
    procedure Rationale(AExpanded: Boolean);
    /// <summary>Inhalt der Unit (#1921), auch zugeklappt.</summary>
    procedure UnitContents;
    procedure Toggle(AExpanded: Boolean; AGap: Integer);
  end;

{ TDocCell }

class function TDocCell.OfRuns(const ARuns: TDpccDocRuns; AColor: TDpccDocColor): TDocCell;
begin
  Result := Default(TDocCell);
  Result.HasRuns := True;
  Result.Runs := ARuns;
  Result.Color := AColor;
end;

class function TDocCell.OfText(const AText: string; const AFace: TDpccDocFace; AColor: TDpccDocColor): TDocCell;
begin
  Result := Default(TDocCell);
  Result.Text := AText;
  Result.Face := AFace;
  Result.Color := AColor;
end;

{ TLayoutBuilder }

/// <summary>Lässt sich ein Stück gleicher Gestalt direkt an ASpan anhängen?</summary>
function CanExtend(const ASpan: TDpccDocSpan; AX: Integer; const AFace: TDpccDocFace; AColor: TDpccDocColor;
  AUnderline: Boolean; ALink: Integer): Boolean;
begin
  Result := (ASpan.Right = AX) and ASpan.Face.SameAs(AFace);
  if Result then
  begin
    Result := (ASpan.Color = AColor) and (ASpan.Underline = AUnderline) and (ASpan.Link = ALink);
  end;
end;

/// <summary>Farbe eines Tokens; andere Sprachen (Markdown der Issue-Vorschau, #1264) ohne Delphi-Farben.</summary>
function TokenColor(AKind: TDpccTokenKind): TDpccDocColor;
begin
  case AKind of
    TDpccTokenKind.Keyword:
      Result := TDpccDocColor.Keyword;
    TDpccTokenKind.StringLiteral:
      Result := TDpccDocColor.StringLiteral;
    TDpccTokenKind.Comment:
      Result := TDpccDocColor.Comment;
    TDpccTokenKind.Number:
      Result := TDpccDocColor.Number;
  else
    Result := TDpccDocColor.Text;
  end;
end;

function RowEnd(const ARuns: TDpccDocRuns; AIndex: Integer): Integer;
begin
  // AIndex ist ein Bullet; die Zeile endet vor dem nächsten Bullet bzw. Absatz.
  Result := AIndex + 1;
  while (Result <= High(ARuns)) and not (ARuns[Result].Kind in [TDpccDocRunKind.Bullet,
    TDpccDocRunKind.Paragraph]) do
  begin
    Inc(Result);
  end;
end;

function IsTableRow(const ARuns: TDpccDocRuns; AIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if (AIndex > High(ARuns)) or (ARuns[AIndex].Kind <> TDpccDocRunKind.Bullet) then
  begin
    Exit;
  end;
  for mIndex := AIndex + 1 to RowEnd(ARuns, AIndex) - 1 do
  begin
    if ARuns[mIndex].Kind = TDpccDocRunKind.Cell then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Verweis: anklickbar, wenn der Server den Fundort kennt.</summary>
procedure FlowRef(ABuilder: TLayoutBuilder; const ARun: TDpccDocRun);
var
  mLink: TDpccDocLink;
  mFace: TDpccDocFace;
begin
  mFace := TDpccDocFace.Create(TDpccDocFont.Mono, ARun.Bold, ARun.Italic);
  if not ARun.Location.HasLocation then
  begin
    ABuilder.AddWords(ARun.Text, mFace, TDpccDocColor.Accent);
    Exit;
  end;
  mLink := Default(TDpccDocLink);
  mLink.Kind := TDpccDocLinkKind.Ref;
  mLink.Target := ARun.Location;
  ABuilder.AddWords(ARun.Text, mFace, TDpccDocColor.Accent, True, ABuilder.AddLink(mLink));
end;

/// <summary>Link; Issue ohne Tracker (#1123) bleibt Text.</summary>
procedure FlowLink(ABuilder: TLayoutBuilder; const ARun: TDpccDocRun; ABaseColor: TDpccDocColor);
var
  mLink: TDpccDocLink;
  mFace: TDpccDocFace;
  mIsIssue: Boolean;
  mLinkIndex: Integer;
begin
  mFace := TDpccDocFace.Create(TDpccDocFont.UI, ARun.Bold, ARun.Italic);
  mIsIssue := ARun.Target.StartsWith(TDpccDocIssueLinks.cPrefix, True);
  if mIsIssue and (TDpccDocIssueLinks.Url(ARun.Target) = '') then
  begin
    ABuilder.AddWords(ARun.Text, mFace, ABaseColor);
    Exit;
  end;
  mLinkIndex := -1;
  if ARun.Target <> '' then
  begin
    mLink := Default(TDpccDocLink);
    mLink.Kind := TDpccDocLinkKind.Url;
    mLink.Url := ARun.Target;
    if mIsIssue then
    begin
      mLink.Url := TDpccDocIssueLinks.Url(ARun.Target);
    end;
    mLinkIndex := ABuilder.AddLink(mLink);
  end;
  ABuilder.AddWords(ARun.Text, mFace, TDpccDocColor.Accent, mLinkIndex >= 0, mLinkIndex);
end;

constructor TLayoutBuilder.Create(AWidth: Integer; const AMetrics: TDpccDocMetrics;
  const AMeasure: TDpccDocMeasure);
begin
  inherited Create;
  FWidth := Max(1, AWidth);
  FMetrics := AMetrics;
  FMeasure := AMeasure;
end;

function TLayoutBuilder.LineCount: Integer;
begin
  Result := Length(FLines);
end;

function HeightOf(const AFace: TDpccDocFace; const AMetrics: TDpccDocMetrics): Integer;
begin
  if AFace.Font = TDpccDocFont.Mono then
  begin
    Result := AMetrics.MonoHeight;
  end
  else
  begin
    Result := AMetrics.LineHeight;
  end;
end;

procedure TLayoutBuilder.SetBase(ALeft: Integer);
begin
  FBase := ALeft;
  FLeft := ALeft;
  FHang := ALeft;
  FNextStart := ALeft;
end;

procedure TLayoutBuilder.NewLine;
begin
  FOpen := False;
  FNextStart := FLeft;
end;

procedure TLayoutBuilder.Gap(AValue: Integer);
begin
  NewLine;
  // Kein Abstand vor der ersten Zeile.
  if Length(FLines) > 0 then
  begin
    FPendingGap := Max(FPendingGap, AValue);
  end;
end;

procedure TLayoutBuilder.OpenLine;
var
  mLine: TDpccDocLine;
begin
  mLine := Default(TDpccDocLine);
  mLine.GapBefore := FPendingGap;
  mLine.Height := FMetrics.LineHeight;
  FLines := FLines + [mLine];
  FPendingGap := 0;
  FOpen := True;
  FX := FNextStart;
end;

function TLayoutBuilder.AddLink(const ALink: TDpccDocLink): Integer;
begin
  FLinks := FLinks + [ALink];
  Result := High(FLinks);
end;

procedure TLayoutBuilder.AddSpan(const AText: string; const AFace: TDpccDocFace; AColor: TDpccDocColor;
  AUnderline: Boolean; ALink: Integer);
var
  mSpan: TDpccDocSpan;
  mWidth, mLast: Integer;
begin
  if AText = '' then
  begin
    Exit;
  end;
  if not FOpen then
  begin
    OpenLine;
  end;
  mWidth := FMeasure(AText, AFace);
  mLast := High(FLines);
  // Gleich gestaltetes Stück direkt davor verlängern.
  if Length(FLines[mLast].Spans) > 0 then
  begin
    mSpan := FLines[mLast].Spans[High(FLines[mLast].Spans)];
    if CanExtend(mSpan, FX, AFace, AColor, AUnderline, ALink) then
    begin
      mSpan.Text := mSpan.Text + AText;
      mSpan.Width := FMeasure(mSpan.Text, AFace);
      FLines[mLast].Spans[High(FLines[mLast].Spans)] := mSpan;
      FX := mSpan.Right;
      FLines[mLast].Height := Max(FLines[mLast].Height, HeightOf(AFace, FMetrics));
      Exit;
    end;
  end;
  mSpan := Default(TDpccDocSpan);
  mSpan.Text := AText;
  mSpan.Left := FX;
  mSpan.Width := mWidth;
  mSpan.Face := AFace;
  mSpan.Color := AColor;
  mSpan.Underline := AUnderline;
  mSpan.Link := ALink;
  FLines[mLast].Spans := FLines[mLast].Spans + [mSpan];
  FLines[mLast].Height := Max(FLines[mLast].Height, HeightOf(AFace, FMetrics));
  Inc(FX, mWidth);
end;

procedure TLayoutBuilder.AddWords(const AText: string; const AFace: TDpccDocFace; AColor: TDpccDocColor);
begin
  AddWords(AText, AFace, AColor, False, -1);
end;

procedure TLayoutBuilder.WrapLine;
begin
  FOpen := False;
  FNextStart := FHang;
end;

function TLayoutBuilder.Available: Integer;
begin
  if FOpen then
  begin
    Result := FWidth - FX;
  end
  else
  begin
    Result := FWidth - FNextStart;
  end;
end;

procedure TLayoutBuilder.AddWord(const AWord: string; const AFace: TDpccDocFace; AColor: TDpccDocColor;
  AUnderline: Boolean; ALink: Integer);
var
  mWord, mBare: string;
  mCount: Integer;
begin
  mWord := AWord;
  mBare := TrimRight(mWord);
  // Am Zeilenanfang keine Leerzeichen.
  if mBare = '' then
  begin
    if FOpen and (FX <> FNextStart) then
    begin
      AddSpan(mWord, AFace, AColor, AUnderline, ALink);
    end;
    Exit;
  end;
  if FOpen and (FX > FNextStart) and (FX + FMeasure(mBare, AFace) > FWidth) then
  begin
    WrapLine;
  end;
  // Wort breiter als die Zeile: an Zeichen trennen, mindestens ein Zeichen je Zeile.
  while (mBare <> '') and (FMeasure(mBare, AFace) > Available) do
  begin
    mCount := Length(mBare) - 1;
    while (mCount > 1) and (FMeasure(Copy(mBare, 1, mCount), AFace) > Available) do
    begin
      Dec(mCount);
    end;
    if mCount < 1 then
    begin
      Break;
    end;
    AddSpan(Copy(mBare, 1, mCount), AFace, AColor, AUnderline, ALink);
    Delete(mBare, 1, mCount);
    Delete(mWord, 1, mCount);
    WrapLine;
  end;
  AddSpan(mWord, AFace, AColor, AUnderline, ALink);
end;

procedure TLayoutBuilder.AddWords(const AText: string; const AFace: TDpccDocFace; AColor: TDpccDocColor;
  AUnderline: Boolean; ALink: Integer);
var
  mIndex, mStart: Integer;
begin
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    // Wort samt folgender Leerzeichen.
    mStart := mIndex;
    while (mIndex <= Length(AText)) and (AText[mIndex] <> ' ') do
    begin
      Inc(mIndex);
    end;
    while (mIndex <= Length(AText)) and (AText[mIndex] = ' ') do
    begin
      Inc(mIndex);
    end;
    AddWord(Copy(AText, mStart, mIndex - mStart), AFace, AColor, AUnderline, ALink);
  end;
end;

procedure TLayoutBuilder.AddWhole(const AText: string; const AFace: TDpccDocFace; AColor: TDpccDocColor;
  ALink: Integer);
begin
  if FOpen and (FX > FNextStart) and (FX + FMeasure(AText, AFace) > FWidth) then
  begin
    WrapLine;
  end;
  AddSpan(AText, AFace, AColor, False, ALink);
end;

procedure TLayoutBuilder.StartCodeLine(AStart, AShade: Integer);
begin
  FOpen := False;
  FNextStart := AStart;
  OpenLine;
  FLines[High(FLines)].Shaded := True;
  FLines[High(FLines)].ShadeLeft := AShade;
  FLines[High(FLines)].Height := FMetrics.MonoHeight;
end;

procedure TLayoutBuilder.AddCodePiece(const APiece: string; const AFace: TDpccDocFace; AColor: TDpccDocColor;
  const ACode: TCodeArea);
var
  mPiece: string;
  mCount: Integer;
begin
  // Einrückung bleibt; zu lange Zeilen brechen an Zeichen um
  // (kein waagrechtes Scrollen), die Fortsetzung eingerückt.
  mPiece := APiece;
  while mPiece <> '' do
  begin
    if FX + FMeasure(mPiece, AFace) <= ACode.Right then
    begin
      AddSpan(mPiece, AFace, AColor, False, -1);
      Exit;
    end;
    mCount := Length(mPiece);
    while (mCount > 0) and (FX + FMeasure(Copy(mPiece, 1, mCount), AFace) > ACode.Right) do
    begin
      Dec(mCount);
    end;
    if (mCount = 0) and (FX <= ACode.Inner + FMetrics.Indent) then
    begin
      mCount := 1;
    end;
    if mCount > 0 then
    begin
      AddSpan(Copy(mPiece, 1, mCount), AFace, AColor, False, -1);
      Delete(mPiece, 1, mCount);
    end;
    StartCodeLine(ACode.Inner + FMetrics.Indent, FLeft);
  end;
end;

procedure TLayoutBuilder.FlowCode(const AText: string; AHighlight: Boolean);
var
  mCodeLine: string;
  mToken: TDpccToken;
  mKind: TDpccTokenKind;
  mCode: TCodeArea;
begin
  // Schattierte, gerahmte Fläche ab dem linken Rand; Text um CodePad eingerückt.
  mCode.Inner := FLeft + FMetrics.CodePad;
  mCode.Right := Max(mCode.Inner + 1, FWidth - FMetrics.CodePad);
  Gap(FMetrics.ParagraphGap);
  for mCodeLine in AText.Split([#10]) do
  begin
    StartCodeLine(mCode.Inner, FLeft);
    for mToken in TDpccSyntax.Tokens(mCodeLine) do
    begin
      mKind := mToken.Kind;
      if not AHighlight then
      begin
        mKind := TDpccTokenKind.Plain;
      end;
      // Schlüsselwörter halbfett wie in der Deklaration (TDpccStyledText).
      AddCodePiece(Copy(mCodeLine, mToken.Start + 1, mToken.Stop - mToken.Start),
        TDpccDocFace.Create(TDpccDocFont.Mono, mKind = TDpccTokenKind.Keyword), TokenColor(mKind), mCode);
    end;
  end;
  FOpen := False;
  FNextStart := FLeft;
  Gap(FMetrics.ParagraphGap);
end;

/// <summary>Breite der Läufe [AFrom, ATo) in einer Zeile ohne Umbruch.</summary>
function SingleLineWidth(const ARuns: TDpccDocRuns; AFrom, ATo: Integer; const AMeasure: TDpccDocMeasure): Integer;
var
  mIndex: Integer;
  mFont: TDpccDocFont;
begin
  Result := 0;
  for mIndex := AFrom to ATo - 1 do
  begin
    if ARuns[mIndex].Kind in [TDpccDocRunKind.Code, TDpccDocRunKind.Ref, TDpccDocRunKind.ParamRef,
      TDpccDocRunKind.Keyword] then
    begin
      mFont := TDpccDocFont.Mono;
    end
    else
    begin
      mFont := TDpccDocFont.UI;
    end;
    // paramref fett wie beim Satz (FlowRuns).
    Inc(Result, AMeasure(ARuns[mIndex].Text, TDpccDocFace.Create(mFont,
      ARuns[mIndex].Bold or (ARuns[mIndex].Kind = TDpccDocRunKind.ParamRef), ARuns[mIndex].Italic)));
  end;
end;

/// <summary>Zeile ARow von ASource um ALeft verschoben in ALine übernehmen; Links landen in ATarget.</summary>
procedure MergeColumn(var ALine: TDpccDocLine; ATarget, ASource: TLayoutBuilder; ARow, ALeft: Integer);
var
  mSpan: TDpccDocSpan;
begin
  if ARow >= ASource.LineCount then
  begin
    Exit;
  end;
  ALine.Height := Max(ALine.Height, ASource.Lines[ARow].Height);
  if ASource.Lines[ARow].Shaded and not ALine.Shaded then
  begin
    ALine.Shaded := True;
    ALine.ShadeLeft := ASource.Lines[ARow].ShadeLeft + ALeft;
  end;
  for mSpan in ASource.Lines[ARow].Spans do
  begin
    ALine.Spans := ALine.Spans + [mSpan];
    Inc(ALine.Spans[High(ALine.Spans)].Left, ALeft);
    if mSpan.Link >= 0 then
    begin
      ALine.Spans[High(ALine.Spans)].Link := ATarget.AddLink(ASource.Links[mSpan.Link]);
    end;
  end;
end;

procedure TLayoutBuilder.Merge(const ABuilders: TArray<TLayoutBuilder>; const ALefts: TArray<Integer>;
  AGap: Integer);
var
  mRow, mCount, mColumn: Integer;
  mLine: TDpccDocLine;
  mSource: TLayoutBuilder;
begin
  // Zeilen der Spalten nebeneinander; Links der Spalten werden übernommen.
  mCount := 0;
  for mSource in ABuilders do
  begin
    mCount := Max(mCount, mSource.LineCount);
  end;
  NewLine;
  for mRow := 0 to mCount - 1 do
  begin
    mLine := Default(TDpccDocLine);
    mLine.Height := FMetrics.LineHeight;
    if (mRow = 0) and (Length(FLines) > 0) then
    begin
      mLine.GapBefore := Max(FPendingGap, AGap);
    end;
    for mColumn := 0 to High(ABuilders) do
    begin
      MergeColumn(mLine, Self, ABuilders[mColumn], mRow, ALefts[mColumn]);
    end;
    FLines := FLines + [mLine];
  end;
  FPendingGap := 0;
end;

procedure TLayoutBuilder.LayoutTable(const ARuns: TDpccDocRuns; var AIndex: Integer;
  ABaseColor: TDpccDocColor);
var
  mIndex, mStop, mCell, mColumn, mTermWidth, mLeft: Integer;
  mTerm, mDescription: TLayoutBuilder;

  function CellOf(AFrom, ATo: Integer): Integer;
  var
    mProbe: Integer;
  begin
    for mProbe := AFrom to ATo - 1 do
    begin
      if ARuns[mProbe].Kind = TDpccDocRunKind.Cell then
      begin
        Exit(mProbe);
      end;
    end;
    Result := ATo;
  end;

begin
  mLeft := FLeft + (Max(1, ARuns[AIndex].Level) - 1) * FMetrics.Indent;
  // Breite der Begriffsspalte über alle Zeilen der Tabelle.
  mColumn := 0;
  mIndex := AIndex;
  while IsTableRow(ARuns, mIndex) do
  begin
    mStop := RowEnd(ARuns, mIndex);
    mColumn := Max(mColumn, SingleLineWidth(ARuns, mIndex + 1, CellOf(mIndex + 1, mStop), FMeasure));
    mIndex := mStop;
  end;
  mTermWidth := Min(mColumn, (FWidth - mLeft) * TDpccDocLayout.cTermColumnPercent div 100);
  mTermWidth := Max(mTermWidth, 1);
  while IsTableRow(ARuns, AIndex) do
  begin
    mStop := RowEnd(ARuns, AIndex);
    mCell := CellOf(AIndex + 1, mStop);
    mTerm := TLayoutBuilder.Create(mTermWidth, FMetrics, FMeasure);
    mDescription := TLayoutBuilder.Create(Max(1, FWidth - mLeft - mTermWidth - FMetrics.ColumnGap), FMetrics,
      FMeasure);
    try
      mTerm.FlowRuns(Copy(ARuns, AIndex + 1, mCell - AIndex - 1), ABaseColor);
      mDescription.FlowRuns(Copy(ARuns, mCell + 1, mStop - mCell - 1), ABaseColor);
      Merge([mTerm, mDescription], [mLeft, mLeft + mTermWidth + FMetrics.ColumnGap], FMetrics.ParagraphGap div 2);
    finally
      mTerm.Free;
      mDescription.Free;
    end;
    AIndex := mStop;
  end;
  // AIndex steht auf dem Lauf nach der Tabelle; FlowRuns zählt selbst weiter.
  Dec(AIndex);
  NewLine;
end;

procedure TLayoutBuilder.FlowBullet(const ARun: TDpccDocRun);
var
  mLink: TDpccDocLink;
  mLinkIndex: Integer;
  mColor: TDpccDocColor;
begin
  NewLine;
  FLeft := FBase + (Max(1, ARun.Level) - 1) * FMetrics.Indent;
  FHang := FLeft;
  FNextStart := FLeft;
  OpenLine;
  if ARun.Text = '' then
  begin
    Exit;
  end;
  // Marke mit Ziel (Kästchen einer Checkliste, #1273): anklickbar in Akzentfarbe, ohne Unterstrich.
  mLinkIndex := -1;
  mColor := TDpccDocColor.Muted;
  if ARun.Target <> '' then
  begin
    mLink := Default(TDpccDocLink);
    mLink.Kind := TDpccDocLinkKind.Url;
    mLink.Url := ARun.Target;
    mLinkIndex := AddLink(mLink);
    mColor := TDpccDocColor.Accent;
  end;
  AddSpan(ARun.Text, TDpccDocFace.Create(TDpccDocFont.UI, ARun.Bold), mColor, False, mLinkIndex);
  // Fester Platz für die Marke, damit die Texte der Punkte bündig stehen.
  FX := FLeft + Max(FMeasure(ARun.Text + ' ', TDpccDocFace.Create(TDpccDocFont.UI, ARun.Bold)),
    FMeasure('00. ', TDpccDocFace.Create(TDpccDocFont.UI)));
  FHang := FX;
end;

procedure TLayoutBuilder.FlowRuns(const ARuns: TDpccDocRuns; ABaseColor: TDpccDocColor);
var
  mIndex: Integer;
  mRun: TDpccDocRun;
begin
  mIndex := 0;
  while mIndex <= High(ARuns) do
  begin
    mRun := ARuns[mIndex];
    case mRun.Kind of
      TDpccDocRunKind.Text:
        AddWords(mRun.Text, TDpccDocFace.Create(TDpccDocFont.UI, mRun.Bold, mRun.Italic), ABaseColor);
      TDpccDocRunKind.Code:
        AddWords(mRun.Text, TDpccDocFace.Create(TDpccDocFont.Mono, mRun.Bold, mRun.Italic), ABaseColor);
      TDpccDocRunKind.ParamRef:
        // Schlicht (S8): Editorschrift fett in der Farbe des Absatzes, ohne Pille.
        AddWords(mRun.Text, TDpccDocFace.Create(TDpccDocFont.Mono, True, mRun.Italic), ABaseColor);
      TDpccDocRunKind.Keyword:
        AddWords(mRun.Text, TDpccDocFace.Create(TDpccDocFont.Mono, mRun.Bold, mRun.Italic),
          TDpccDocColor.Keyword);
      TDpccDocRunKind.Ref:
        FlowRef(Self, mRun);
      TDpccDocRunKind.Link:
        FlowLink(Self, mRun, ABaseColor);
      TDpccDocRunKind.LineBreak:
        begin
          // Innerhalb eines Listenpunkts bleibt der hängende Einzug.
          FOpen := False;
          FLeft := FHang;
          FNextStart := FHang;
        end;
      TDpccDocRunKind.Paragraph:
        begin
          FLeft := FBase;
          FHang := FBase;
          Gap(FMetrics.ParagraphGap);
        end;
      TDpccDocRunKind.CodeBlock:
        begin
          FLeft := FBase;
          FHang := FBase;
          FlowCode(mRun.Text, mRun.IsDelphiCode);
        end;
      TDpccDocRunKind.Bullet:
        if IsTableRow(ARuns, mIndex) then
        begin
          FLeft := FBase;
          LayoutTable(ARuns, mIndex, ABaseColor);
        end
        else
        begin
          FlowBullet(mRun);
        end;
      TDpccDocRunKind.Cell:
        AddWords(' – ', TDpccDocFace.Create(TDpccDocFont.UI), ABaseColor);
    end;
    Inc(mIndex);
  end;
end;

procedure TLayoutBuilder.Heading(const AText: string);
begin
  SetBase(0);
  Gap(FMetrics.SectionGap);
  AddSpan(AText, TDpccDocFace.Heading, TDpccDocColor.Muted, False, -1);
  FLines[High(FLines)].Rule := True;
  FLines[High(FLines)].RuleFrom := FX + FMetrics.ColumnGap;
  NewLine;
end;

procedure TLayoutBuilder.Columns(const ARow: TDocRow; const AWidths: TArray<Integer>);
var
  mBuilders: TArray<TLayoutBuilder>;
  mLefts: TArray<Integer>;
  mIndex, mLeft, mWidth, mLinkIndex: Integer;
  mCell: TDocCell;
begin
  SetLength(mBuilders, Length(ARow));
  SetLength(mLefts, Length(ARow));
  try
    mLeft := 0;
    for mIndex := 0 to High(ARow) do
    begin
      if mIndex < High(ARow) then
      begin
        mWidth := AWidths[mIndex];
      end
      else
      begin
        mWidth := FWidth - mLeft;
      end;
      mLefts[mIndex] := mLeft;
      mBuilders[mIndex] := TLayoutBuilder.Create(Max(1, mWidth), FMetrics, FMeasure);
      mCell := ARow[mIndex];
      if mCell.HasRuns then
      begin
        mBuilders[mIndex].FlowRuns(mCell.Runs, mCell.Color);
      end
      else
      begin
        mLinkIndex := -1;
        if mCell.HasLink then
        begin
          mLinkIndex := mBuilders[mIndex].AddLink(mCell.Link);
        end;
        mBuilders[mIndex].AddWords(mCell.Text, mCell.Face, mCell.Color, mCell.HasLink, mLinkIndex);
      end;
      Inc(mLeft, mWidth + FMetrics.ColumnGap);
    end;
    SetBase(0);
    Merge(mBuilders, mLefts, FMetrics.ParagraphGap div 2);
    NewLine;
  finally
    for mIndex := 0 to High(mBuilders) do
    begin
      mBuilders[mIndex].Free;
    end;
  end;
end;

procedure TLayoutBuilder.Section(const ASection: TDpccDocSection; AColor: TDpccDocColor);
begin
  SetBase(0);
  NewLine;
  FlowRuns(ASection.Runs, AColor);
  NewLine;
end;

type
  TSectionKinds = set of TDpccDocSectionKind;

/// <summary>Verbirgt der Schalter etwas? Abschnitte der Arten AShown stehen auch zugeklappt da.</summary>
function HasHidden(const ADoc: TDpccDoc; const AShown: TSectionKinds): Boolean;
var
  mSection: TDpccDocSection;
  mRationale: Integer;
begin
  // Begründungen sind zugeklappt sichtbar, nur über MaxRationale hinaus nicht.
  mRationale := 0;
  for mSection in ADoc.Sections do
  begin
    if mSection.Kind = TDpccDocSectionKind.Rationale then
    begin
      Inc(mRationale);
    end
    else if not (mSection.Kind in AShown) then
    begin
      Exit(True);
    end;
  end;
  Result := mRationale > TDpccDocLayout.cMaxRationale;
end;

class function TDpccDocTypeset.IsCollapsible(const ADoc: TDpccDoc): Boolean;
begin
  // Der Inhalt einer Unit (#1921) steht immer da.
  Result := HasHidden(ADoc, [TDpccDocSectionKind.Summary, TDpccDocSectionKind.UnitContents]);
end;

class function TDpccDocTypeset.IsCollapsible(const AContent: TDpccDocContent): Boolean;
begin
  if AContent.SignatureShown then
  begin
    Result := HasHidden(AContent.Doc, [TDpccDocSectionKind.Summary, TDpccDocSectionKind.Param,
      TDpccDocSectionKind.Returns, TDpccDocSectionKind.UnitContents]);
  end
  else
  begin
    Result := IsCollapsible(AContent.Doc);
  end;
end;

function SectionsOf(const ADoc: TDpccDoc; AKind: TDpccDocSectionKind): TArray<TDpccDocSection>;
var
  mSection: TDpccDocSection;
begin
  Result := nil;
  for mSection in ADoc.Sections do
  begin
    if mSection.Kind = AKind then
    begin
      Result := Result + [mSection];
    end;
  end;
end;

/// <summary>Parameter der Doku, die die Signatur nicht kennt; ohne erkannte Signatur keine.</summary>
function UnknownParams(const ADoc: TDpccDoc; const ASignature: TDpccDocSignature): TArray<TDpccDocSection>;
var
  mSection: TDpccDocSection;
begin
  Result := nil;
  if not ASignature.Known then
  begin
    Exit;
  end;
  for mSection in SectionsOf(ADoc, TDpccDocSectionKind.Param) do
  begin
    if ASignature.IndexOf(mSection.Name) < 0 then
    begin
      Result := Result + [mSection];
    end;
  end;
end;

function ParamCount(const ADoc: TDpccDoc; const ASignature: TDpccDocSignature): Integer;
begin
  if ASignature.Known then
  begin
    Result := Length(ASignature.Params) + Length(UnknownParams(ADoc, ASignature));
  end
  else
  begin
    Result := Length(SectionsOf(ADoc, TDpccDocSectionKind.Param));
  end;
end;

function HasReturns(const ADoc: TDpccDoc; const ASignature: TDpccDocSignature): Boolean;
begin
  Result := ADoc.Has(TDpccDocSectionKind.Returns) or
    ((ASignature.ResultType <> '') and not ASignature.IsProperty);
end;

function HasValue(const ADoc: TDpccDoc; const ASignature: TDpccDocSignature): Boolean;
begin
  Result := ADoc.Has(TDpccDocSectionKind.Value) or ((ASignature.ResultType <> '') and ASignature.IsProperty);
end;

/// <summary>Verborgenes im zugeklappten Zustand; AOpen: Parameter und Rückgabe stehen schon da (#1919).</summary>
function CollectHiddenParts(const ADoc: TDpccDoc; const ASignature: TDpccDocSignature;
  const ALabels: TDpccDocLabels; AOpen: Boolean; out AColors: TArray<TDpccDocColor>): TArray<string>;
var
  mCount: Integer;
  mParts: TArray<string>;
  mColors: TArray<TDpccDocColor>;

  procedure Add(const AText: string; AColor: TDpccDocColor);
  begin
    mParts := mParts + [AText];
    mColors := mColors + [AColor];
  end;

  function Counted(ACount: Integer; const AOne, AMany: string): string;
  begin
    if ACount = 1 then
    begin
      Result := Format(AOne, [ACount]);
    end
    else
    begin
      Result := Format(AMany, [ACount]);
    end;
  end;

begin
  mParts := nil;
  mColors := nil;
  mCount := 0;
  if not AOpen then
  begin
    mCount := ParamCount(ADoc, ASignature);
  end;
  if mCount > 0 then
  begin
    Add(Counted(mCount, ALabels.CountParam, ALabels.CountParams), TDpccDocColor.Muted);
  end;
  mCount := Length(SectionsOf(ADoc, TDpccDocSectionKind.TypeParam));
  if mCount > 0 then
  begin
    Add(Counted(mCount, ALabels.CountTypeParam, ALabels.CountTypeParams), TDpccDocColor.Muted);
  end;
  if not AOpen and HasReturns(ADoc, ASignature) then
  begin
    Add(ALabels.ItemReturns, TDpccDocColor.Muted);
  end;
  if HasValue(ADoc, ASignature) then
  begin
    Add(ALabels.ItemValue, TDpccDocColor.Muted);
  end;
  mCount := Length(SectionsOf(ADoc, TDpccDocSectionKind.Exception));
  if mCount > 0 then
  begin
    Add(Counted(mCount, ALabels.CountException, ALabels.CountExceptions), TDpccDocColor.Error);
  end;
  if ADoc.Has(TDpccDocSectionKind.Remarks) then
  begin
    Add(ALabels.ItemRemarks, TDpccDocColor.Muted);
  end;
  if ADoc.Has(TDpccDocSectionKind.Example) then
  begin
    Add(ALabels.ItemExample, TDpccDocColor.Muted);
  end;
  if ADoc.Has(TDpccDocSectionKind.SeeAlso) then
  begin
    Add(ALabels.ItemSeeAlso, TDpccDocColor.Muted);
  end;
  mCount := Length(SectionsOf(ADoc, TDpccDocSectionKind.Rationale)) - TDpccDocLayout.cMaxRationale;
  if mCount > 0 then
  begin
    Add(Counted(mCount, ALabels.CountRationale, ALabels.CountRationales), TDpccDocColor.Muted);
  end;
  AColors := mColors;
  Result := mParts;
end;

class function TDpccDocTypeset.HiddenParts(const ADoc: TDpccDoc; const ASignature: TDpccDocSignature;
  const ALabels: TDpccDocLabels; out AColors: TArray<TDpccDocColor>): TArray<string>;
begin
  Result := CollectHiddenParts(ADoc, ASignature, ALabels, False, AColors);
end;

class function TDpccDocTypeset.HiddenParts(const AContent: TDpccDocContent; const ALabels: TDpccDocLabels;
  out AColors: TArray<TDpccDocColor>): TArray<string>;
begin
  Result := CollectHiddenParts(AContent.Doc, AContent.Signature, ALabels, AContent.SignatureShown, AColors);
end;

function SectionIndex(const ASections: TArray<TDpccDocSection>; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ASections) do
  begin
    if SameText(ASections[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TDocSections }

constructor TDocSections.Create(ABuilder: TLayoutBuilder; const AContent: TDpccDocContent;
  const ALabels: TDpccDocLabels; AWidth: Integer; const AMeasure: TDpccDocMeasure);
begin
  inherited Create;
  FBuilder := ABuilder;
  FDoc := AContent.Doc;
  FSignature := AContent.Signature;
  FOpenSignature := AContent.SignatureShown;
  FLabels := ALabels;
  FWidth := AWidth;
  FMeasure := AMeasure;
  FName := TDpccDocFace.Create(TDpccDocFont.Mono, True);
  FNameColor := TDpccDocColor.Accent;
  if AContent.PlainNames then
  begin
    FName := TDpccDocFace.Create(TDpccDocFont.Mono);
    FNameColor := TDpccDocColor.Text;
  end;
  FMono := TDpccDocFace.Create(TDpccDocFont.Mono);
  FUI := TDpccDocFace.Create(TDpccDocFont.UI);
end;

function TDocSections.Width(const AText: string; const AFace: TDpccDocFace; APercent: Integer): Integer;
begin
  Result := Min(FMeasure(AText, AFace), FWidth * APercent div 100);
end;

function TDocSections.NameColumn(const ASections: TArray<TDpccDocSection>; ACount: Integer;
  const AFace: TDpccDocFace; APercent: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 1;
  for mIndex := 0 to Min(ACount, Length(ASections)) - 1 do
  begin
    Result := Max(Result, Width(ASections[mIndex].Name, AFace, APercent));
  end;
end;

function TDocSections.LinkCell(const ASection: TDpccDocSection): TDocCell;
begin
  Result := TDocCell.OfText(ASection.Name, FMono, TDpccDocColor.Error);
  // Klasse anklickbar, wenn der Server sie gefunden hat.
  if ASection.NameRef.HasLocation then
  begin
    Result.HasLink := True;
    Result.Link.Kind := TDpccDocLinkKind.Ref;
    Result.Link.Target := ASection.NameRef;
  end;
end;

procedure TDocSections.TypeAndText(const AType: string; AKind: TDpccDocSectionKind);
var
  mDocs: TArray<TDpccDocSection>;
begin
  mDocs := SectionsOf(FDoc, AKind);
  if (AType <> '') and (Length(mDocs) > 0) then
  begin
    FBuilder.Columns([TDocCell.OfText(AType, FMono, TDpccDocColor.Keyword),
      TDocCell.OfRuns(mDocs[0].Runs, TDpccDocColor.Muted)],
      [Width(AType, FMono, TDpccDocLayout.cTypeColumnPercent)]);
  end
  else if AType <> '' then
  begin
    FBuilder.Columns([TDocCell.OfText(AType, FMono, TDpccDocColor.Keyword)], nil);
  end
  else if Length(mDocs) > 0 then
  begin
    FBuilder.Columns([TDocCell.OfRuns(mDocs[0].Runs, TDpccDocColor.Muted)], nil);
  end;
end;

procedure TDocSections.ParamRow(const AName, AType: string; const ARuns: TDpccDocRuns;
  ANameColor, ATextColor: TDpccDocColor);
begin
  if FThreeColumns then
  begin
    FBuilder.Columns([TDocCell.OfText(AName, FName, ANameColor), TDocCell.OfText(AType, FMono,
      TDpccDocColor.Muted), TDocCell.OfRuns(ARuns, ATextColor)], [FNameWidth, FTypeWidth]);
  end
  else
  begin
    FBuilder.Columns([TDocCell.OfText(AName, FName, ANameColor), TDocCell.OfRuns(ARuns, ATextColor)],
      [FNameWidth]);
  end;
end;

procedure TDocSections.MeasureParams;
var
  mParam: TDpccDocParam;
begin
  FThreeColumns := FSignature.Known and FSignature.HasTypes;
  FNameWidth := NameColumn(SectionsOf(FDoc, TDpccDocSectionKind.Param), MaxInt, FName,
    TDpccDocLayout.cNameColumnPercent);
  FTypeWidth := 1;
  for mParam in FSignature.Params do
  begin
    FNameWidth := Max(FNameWidth, Width(mParam.Name, FName, TDpccDocLayout.cNameColumnPercent));
    FTypeWidth := Max(FTypeWidth, Width(mParam.TypeText, FMono, TDpccDocLayout.cTypeColumnPercent));
  end;
end;

procedure TDocSections.KnownParams(const ASections: TArray<TDpccDocSection>);
var
  mParam: TDpccDocParam;
  mSection: TDpccDocSection;
  mFound: Integer;
  mUndocumented: TDpccDocRuns;
begin
  mUndocumented := [TDpccDocRun.Create(TDpccDocRunKind.Text, FLabels.Undocumented)];
  mUndocumented[0].Italic := True;
  // Offene Signatur ohne einen dokumentierten Parameter: Textspalte leer statt lauter „nicht dokumentiert“.
  if FOpenSignature and (Length(ASections) = 0) then
  begin
    mUndocumented := nil;
  end;
  for mParam in FSignature.Params do
  begin
    mFound := SectionIndex(ASections, mParam.Name);
    if mFound >= 0 then
    begin
      ParamRow(mParam.Name, mParam.TypeText, ASections[mFound].Runs, FNameColor, TDpccDocColor.Text);
    end
    else
    begin
      ParamRow(mParam.Name, mParam.TypeText, mUndocumented, FNameColor, TDpccDocColor.Muted);
    end;
  end;
  for mSection in UnknownParams(FDoc, FSignature) do
  begin
    ParamRow(mSection.Name, '', mSection.Runs, TDpccDocColor.Warn, TDpccDocColor.Warn);
  end;
end;

procedure TDocSections.Summary;
var
  mSection: TDpccDocSection;
begin
  for mSection in SectionsOf(FDoc, TDpccDocSectionKind.Summary) do
  begin
    FBuilder.Section(mSection, TDpccDocColor.Text);
  end;
end;

procedure TDocSections.Params;
var
  mSections: TArray<TDpccDocSection>;
  mSection: TDpccDocSection;
begin
  // PARAMETER: in der Reihenfolge der Signatur, dann unbekannte in Warnfarbe.
  if ParamCount(FDoc, FSignature) = 0 then
  begin
    Exit;
  end;
  FBuilder.Heading(FLabels.Params);
  MeasureParams;
  mSections := SectionsOf(FDoc, TDpccDocSectionKind.Param);
  if FSignature.Known then
  begin
    KnownParams(mSections);
    Exit;
  end;
  for mSection in mSections do
  begin
    ParamRow(mSection.Name, '', mSection.Runs, FNameColor, TDpccDocColor.Text);
  end;
end;

procedure TDocSections.NamedRows(const ASections: TArray<TDpccDocSection>; ACount: Integer);
var
  mNameWidth, mIndex: Integer;
begin
  mNameWidth := NameColumn(ASections, ACount, FName, TDpccDocLayout.cNameColumnPercent);
  for mIndex := 0 to Min(ACount, Length(ASections)) - 1 do
  begin
    FBuilder.Columns([TDocCell.OfText(ASections[mIndex].Name, FName, FNameColor),
      TDocCell.OfRuns(ASections[mIndex].Runs, TDpccDocColor.Text)], [mNameWidth]);
  end;
end;

procedure TDocSections.TypeParams;
var
  mSections: TArray<TDpccDocSection>;
begin
  mSections := SectionsOf(FDoc, TDpccDocSectionKind.TypeParam);
  if Length(mSections) > 0 then
  begin
    FBuilder.Heading(FLabels.TypeParams);
    NamedRows(mSections, MaxInt);
  end;
end;

procedure TDocSections.ReturnsAndValue;
var
  mReturnType, mValueType: string;
begin
  // Bei Properties ist der Typ der Wert, sonst die Rückgabe.
  mReturnType := FSignature.ResultType;
  mValueType := '';
  if FSignature.IsProperty then
  begin
    mValueType := mReturnType;
    mReturnType := '';
  end;
  if HasReturns(FDoc, FSignature) then
  begin
    FBuilder.Heading(FLabels.Returns);
    TypeAndText(mReturnType, TDpccDocSectionKind.Returns);
  end;
  if HasValue(FDoc, FSignature) then
  begin
    FBuilder.Heading(FLabels.Value);
    TypeAndText(mValueType, TDpccDocSectionKind.Value);
  end;
end;

procedure TDocSections.Exceptions;
var
  mSections: TArray<TDpccDocSection>;
  mSection: TDpccDocSection;
  mNameWidth: Integer;
begin
  mSections := SectionsOf(FDoc, TDpccDocSectionKind.Exception);
  if Length(mSections) = 0 then
  begin
    Exit;
  end;
  FBuilder.Heading(FLabels.Exceptions);
  mNameWidth := NameColumn(mSections, MaxInt, FMono, 50);
  for mSection in mSections do
  begin
    FBuilder.Columns([LinkCell(mSection), TDocCell.OfRuns(mSection.Runs, TDpccDocColor.Muted)], [mNameWidth]);
  end;
end;

procedure TDocSections.TextSections(AKind: TDpccDocSectionKind; const ATitle: string; AColor: TDpccDocColor);
var
  mSections: TArray<TDpccDocSection>;
  mSection: TDpccDocSection;
begin
  mSections := SectionsOf(FDoc, AKind);
  if Length(mSections) = 0 then
  begin
    Exit;
  end;
  FBuilder.Heading(ATitle);
  for mSection in mSections do
  begin
    FBuilder.Section(mSection, AColor);
  end;
end;

procedure TDocSections.SeeAlso(AGap: Integer);
var
  mSections: TArray<TDpccDocSection>;
  mIndex: Integer;
begin
  // SIEHE AUCH in einer Zeile mit den Verweisen.
  mSections := SectionsOf(FDoc, TDpccDocSectionKind.SeeAlso);
  if Length(mSections) = 0 then
  begin
    Exit;
  end;
  FBuilder.SetBase(0);
  FBuilder.Gap(AGap);
  FBuilder.AddSpan(FLabels.SeeAlso, TDpccDocFace.Heading, TDpccDocColor.Muted, False, -1);
  FBuilder.AddSpan('  ', FUI, TDpccDocColor.Muted, False, -1);
  for mIndex := 0 to High(mSections) do
  begin
    if mIndex > 0 then
    begin
      FBuilder.AddWords(', ', FUI, TDpccDocColor.Muted);
    end;
    FBuilder.FlowRuns(mSections[mIndex].Runs, TDpccDocColor.Text);
  end;
  FBuilder.NewLine;
end;

procedure TDocSections.Details(AGap: Integer);
begin
  Params;
  TypeParams;
  ReturnsAndValue;
  Exceptions;
  TextSections(TDpccDocSectionKind.Remarks, FLabels.Remarks, TDpccDocColor.Muted);
  TextSections(TDpccDocSectionKind.Example, FLabels.Example, TDpccDocColor.Text);
  SeeAlso(AGap);
end;

procedure TDocSections.SignatureSections;
var
  mReturnType: string;
begin
  Params;
  if HasReturns(FDoc, FSignature) then
  begin
    mReturnType := '';
    if not FSignature.IsProperty then
    begin
      mReturnType := FSignature.ResultType;
    end;
    FBuilder.Heading(FLabels.Returns);
    TypeAndText(mReturnType, TDpccDocSectionKind.Returns);
  end;
end;

procedure TDocSections.Rationale(AExpanded: Boolean);
var
  mSections: TArray<TDpccDocSection>;
  mShown: Integer;
begin
  // BEGRÜNDUNG (#1123) nach der XMLDoc; zugeklappt die ersten MaxRationale.
  mSections := SectionsOf(FDoc, TDpccDocSectionKind.Rationale);
  if Length(mSections) = 0 then
  begin
    Exit;
  end;
  FBuilder.Heading(FLabels.Rationale);
  mShown := Length(mSections);
  if not AExpanded then
  begin
    mShown := Min(mShown, TDpccDocLayout.cMaxRationale);
  end;
  NamedRows(mSections, mShown);
end;

procedure TDocSections.UnitContents;
var
  mSections: TArray<TDpccDocSection>;
  mFirst, mLast: Integer;
begin
  // Gruppen unter derselben Überschrift folgen aufeinander; je Überschrift eine Tabelle.
  mSections := SectionsOf(FDoc, TDpccDocSectionKind.UnitContents);
  mFirst := 0;
  while mFirst <= High(mSections) do
  begin
    mLast := mFirst;
    while (mLast < High(mSections)) and (mSections[mLast + 1].Heading = mSections[mFirst].Heading) do
    begin
      Inc(mLast);
    end;
    FBuilder.Heading(mSections[mFirst].Heading);
    NamedRows(Copy(mSections, mFirst, mLast - mFirst + 1), MaxInt);
    mFirst := mLast + 1;
  end;
end;

procedure TDocSections.Toggle(AExpanded: Boolean; AGap: Integer);
var
  mToggle: TDpccDocLink;
  mParts: TArray<string>;
  mColors: TArray<TDpccDocColor>;
  mIndex: Integer;
begin
  // Schalter: zugeklappt mit dem, was verborgen ist.
  mToggle := Default(TDpccDocLink);
  mToggle.Kind := TDpccDocLinkKind.Toggle;
  FBuilder.SetBase(0);
  FBuilder.Gap(AGap);
  if AExpanded then
  begin
    FBuilder.AddWhole(FLabels.Less, FUI, TDpccDocColor.Accent, FBuilder.AddLink(mToggle));
    FBuilder.NewLine;
    Exit;
  end;
  FBuilder.AddWhole(FLabels.More, FUI, TDpccDocColor.Accent, FBuilder.AddLink(mToggle));
  mParts := CollectHiddenParts(FDoc, FSignature, FLabels, FOpenSignature, mColors);
  if Length(mParts) > 0 then
  begin
    FBuilder.AddSpan('   ', FUI, TDpccDocColor.Muted, False, -1);
  end;
  for mIndex := 0 to High(mParts) do
  begin
    if mIndex > 0 then
    begin
      FBuilder.AddWords(TDpccDocLayout.cSeparator, FUI, TDpccDocColor.Muted);
    end;
    FBuilder.AddWords(mParts[mIndex], FUI, mColors[mIndex]);
  end;
  FBuilder.NewLine;
end;

{ TDpccDocContent }

class function TDpccDocContent.Create(const ADoc: TDpccDoc; const ASignature: TDpccDocSignature;
  AExpanded: Boolean): TDpccDocContent;
begin
  Result.Doc := ADoc;
  Result.Signature := ASignature;
  Result.Expanded := AExpanded;
  Result.OpenSignature := False;
  Result.Fixed := False;
  Result.PlainNames := False;
end;

function TDpccDocContent.SignatureShown: Boolean;
begin
  Result := OpenSignature and Signature.Known and ((Length(Signature.Params) > 0) or
    ((Signature.ResultType <> '') and not Signature.IsProperty));
end;

/// <summary>Klartext einer Zeile anhängen und die Anfänge der Stücke darin merken; ein Sprung in eine andere
/// Spalte wird zum Tabulator.</summary>
procedure AppendLineText(var ALine: TDpccDocLine; AText: TStringBuilder);
var
  mPen, mIndex: Integer;
  mSpan: TDpccDocSpan;
begin
  if AText.Length > 0 then
  begin
    AText.Append(#13#10);
  end;
  mPen := -1;
  for mIndex := 0 to High(ALine.Spans) do
  begin
    mSpan := ALine.Spans[mIndex];
    if (mPen >= 0) and (mSpan.Left > mPen + 1) and (AText.Length > 0) and
      not CharInSet(AText.Chars[AText.Length - 1], [' ', #9]) then
    begin
      AText.Append(#9);
    end;
    ALine.Spans[mIndex].TextStart := AText.Length;
    AText.Append(mSpan.Text);
    mPen := mSpan.Right;
  end;
end;

/// <summary>Leere Zeilen am Ende weg; dann Positionen, Höhe und Klartext.</summary>
procedure PlaceLines(var ALayout: TDpccDocLayout);
var
  mY, mIndex: Integer;
  mText: TStringBuilder;
begin
  while (Length(ALayout.Lines) > 0) and (Length(ALayout.Lines[High(ALayout.Lines)].Spans) = 0) do
  begin
    SetLength(ALayout.Lines, Length(ALayout.Lines) - 1);
  end;
  if Length(ALayout.Lines) > 0 then
  begin
    ALayout.Lines[0].GapBefore := 0;
  end;
  mY := 0;
  mText := TStringBuilder.Create;
  try
    for mIndex := 0 to High(ALayout.Lines) do
    begin
      Inc(mY, ALayout.Lines[mIndex].GapBefore);
      ALayout.Lines[mIndex].Top := mY;
      Inc(mY, ALayout.Lines[mIndex].Height);
      AppendLineText(ALayout.Lines[mIndex], mText);
    end;
    ALayout.Text := mText.ToString;
  finally
    mText.Free;
  end;
  ALayout.Height := mY;
end;

class function TDpccDocTypeset.Build(const ADoc: TDpccDoc; AWidth: Integer; const AMetrics: TDpccDocMetrics;
  const AMeasure: TDpccDocMeasure; const ALabels: TDpccDocLabels): TDpccDocLayout;
begin
  Result := Build(TDpccDocContent.Create(ADoc, Default(TDpccDocSignature), True), AWidth, AMetrics, AMeasure,
    ALabels);
end;

class function TDpccDocTypeset.Build(const AContent: TDpccDocContent; AWidth: Integer;
  const AMetrics: TDpccDocMetrics; const AMeasure: TDpccDocMeasure;
  const ALabels: TDpccDocLabels): TDpccDocLayout;
var
  mBuilder: TLayoutBuilder;
  mSections: TDocSections;
begin
  Result := Default(TDpccDocLayout);
  if AContent.Doc.IsEmpty and not AContent.SignatureShown then
  begin
    Exit;
  end;
  Result.Collapsible := IsCollapsible(AContent);
  Result.Expanded := AContent.Expanded or AContent.Fixed or not Result.Collapsible;
  mBuilder := TLayoutBuilder.Create(AWidth, AMetrics, AMeasure);
  mSections := TDocSections.Create(mBuilder, AContent, ALabels, AWidth, AMeasure);
  try
    mSections.Summary;
    if Result.Expanded and Result.Collapsible then
    begin
      mSections.Details(AMetrics.SectionGap);
    end
    else if AContent.SignatureShown then
    begin
      mSections.SignatureSections;
    end;
    mSections.Rationale(Result.Expanded);
    mSections.UnitContents;
    if Result.Collapsible and not AContent.Fixed then
    begin
      mSections.Toggle(Result.Expanded, AMetrics.SectionGap);
    end;
    Result.Lines := mBuilder.Lines;
    Result.Links := mBuilder.Links;
  finally
    mSections.Free;
    mBuilder.Free;
  end;
  PlaceLines(Result);
end;

end.
