unit dpcc.UI.Popup.Render.Tests;

// Zeichentests der Popups ohne IDE (LOOK3): Vervollständigungsliste (gemischte Zeilen, Mengenmodus mit Warnleiste,
// leere Liste), Hover-Tooltip und Parameterhilfe (zwei Überladungen mit Standardwert, Format mit Platzhaltern und
// Pfadzeile) werden je Stufe (Intensiv, Dezent, Unscheinbar) und Grundpalette (TDpccColors.Light, TDpccColors.Dark)
// mit den Beispielinhalten des Entwurfs (dpcc-popups.html, Szenen 1 bis 5) gefüllt und in eine Bitmap gezeichnet.
//   - Gefüllt wird wie in dpcc.IDE (EditorOpen, Hover.Editor, Signature.Editor): Colors, LookLevel und SetScaling wie
//     TDpccIdeStyle.Apply, dann ShowList, ShowEmpty, ShowHover bzw. ShowSignature. Schriften fest: Editorschrift
//     Consolas 10 bei 96 dpi und Zoom 1; die UI-Schrift leitet das Fenster selbst ab (Screen.MessageFont, 12/13 der
//     Editorschrift). Bei 96 dpi ist Scale die Identität: Die logischen Maße der Zeichner gelten unverändert in Pixeln.
//   - Nie sichtbar: Die Show-Methoden zeigen über ShowAt (SetWindowPos mit SWP_SHOWWINDOW). Die Testklassen sind
//     Nachfahren der echten Fenster, die nur in WM_WINDOWPOSCHANGING das Flag SWP_SHOWWINDOW streichen; Größe und Lage
//     setzt ShowAt wie sonst. Das Fenster hat ein Handle, bleibt aber unsichtbar (IsShown wird geprüft).
//   - Gezeichnet wird über PaintWindow (wie bei WM_PAINT: Canvas auf den DC, dann Paint) direkt in den DC der Bitmap,
//     nicht über PaintTo oder WM_PRINT: Beide laufen durch TDpccPopupWindow.WndProc, das jede Ausnahme an TDpccGuard
//     meldet und schluckt; ein abstürzender Zeichner fiele so nicht auf.
//   - Geprüft wird robust, nicht pixelgenau gegen Text: keine Ausnahme, nicht sichtbar geworden, Größe wie das Fenster
//     und wie die Maße des Zeichners, mehrere Farben, Rand an allen Ecken in FrameColor und einige Punkte, an denen
//     laut Zeichner nur eine Fläche liegt (Begründung jeweils am Messpunkt). Dazu die Balken markierter Flächen
//     (Look.MarkBarUsed, nur Intensiv, cDpccLookMarkBar = 3 px bei 96 dpi): im Hover oben unter dem Rand, in der Liste
//     links vor der gewählten bzw. ersten leeren Zeile (x = Pad - 3 bis Pad), in der Parameterhilfe am linken
//     Innenrand der gewählten Überladung; ohne Balken liegt dort die Fläche bzw. die Auswahlfläche.
//   - Bilder: Ist die Umgebungsvariable DPCC_RENDER_DIR gesetzt, legt jeder Test seine Bitmap dort als
//     <fenster>-<stufe>-<palette>.png ab (liste, menge, leer, hover, parameter, format; z. B. liste-intense-light.png),
//     vor den Prüfungen, damit auch ein fehlschlagender Fall ein Bild hat. Ohne die Variable wird nichts geschrieben.
//   - Lecks: Das erste Zeichnen legt bleibende Daten der VCL an (Stil, Monitore, Liste der Zeichenflächen), das erste
//     PNG die des Kodierers; SetupFixture zeichnet deshalb alle Fälle einmal vorab und kodiert ein PNG in den Speicher.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccPopupRenderTests = class
  public
    /// <summary>Einmalige Belegungen der VCL (Stil, Monitore, Zeichenflächen, PNG-Kodierer) vor der Leckmessung:
    /// alle Fälle einmal zeichnen.</summary>
    [SetupFixture]
    procedure Prewarm;
    /// <summary>Szene 1: gewählte erste Zeile, Arten aus mehreren Gruppen, getipptes „Imp“, Marke deprecated (Warn)
    /// und „+ ImportStreams“ (Add), Aktionszeile, Überschrift „Weitere Einträge“ mit gedämpfter Zeile darunter,
    /// Scroll-Daumen und Fußzeile.</summary>
    [Test]
    [TestCase('Intensiv hell', 'intense,light')]
    [TestCase('Intensiv dunkel', 'intense,dark')]
    [TestCase('Dezent hell', 'subtle,light')]
    [TestCase('Dezent dunkel', 'subtle,dark')]
    [TestCase('Unscheinbar hell', 'plain,light')]
    [TestCase('Unscheinbar dunkel', 'plain,dark')]
    procedure CompletionList(const ALevel, APalette: string);
    /// <summary>Szene 2: Mengenmodus (Überschrift „TFontStyles · Menge von TFontStyle“, Kästchen, gewählte vierte
    /// Zeile) unter der Warnleiste „Ergebnisse möglicherweise unvollständig · Syntaxfehler in Zeile 47“.</summary>
    [Test]
    [TestCase('Intensiv hell', 'intense,light')]
    [TestCase('Intensiv dunkel', 'intense,dark')]
    [TestCase('Dezent hell', 'subtle,light')]
    [TestCase('Dezent dunkel', 'subtle,dark')]
    [TestCase('Unscheinbar hell', 'plain,light')]
    [TestCase('Unscheinbar dunkel', 'plain,dark')]
    procedure CompletionListSetMode(const ALevel, APalette: string);
    /// <summary>Szene 3: leere Liste „Keine Treffer für „Impx““ auf der Kopffläche, „Rücktaste erweitert die
    /// Suche“, Fußzeile mit dem Hinweis auf die Liste der IDE und „Esc schließt“.</summary>
    [Test]
    [TestCase('Intensiv hell', 'intense,light')]
    [TestCase('Intensiv dunkel', 'intense,dark')]
    [TestCase('Dezent hell', 'subtle,light')]
    [TestCase('Dezent dunkel', 'subtle,dark')]
    [TestCase('Unscheinbar hell', 'plain,light')]
    [TestCase('Unscheinbar dunkel', 'plain,dark')]
    procedure CompletionListEmpty(const ALevel, APalette: string);
    /// <summary>Szene 4: Kopfzeile (Art, Name, Signatur mit Schlüsselwort, Typ und Zahl), Herkunft, Fundort,
    /// Veraltungshinweis und XMLDoc (Beschreibung, Parameter, Rückgabe, Ausnahme, Beispiel, Siehe auch).</summary>
    [Test]
    [TestCase('Intensiv hell', 'intense,light')]
    [TestCase('Intensiv dunkel', 'intense,dark')]
    [TestCase('Dezent hell', 'subtle,light')]
    [TestCase('Dezent dunkel', 'subtle,dark')]
    [TestCase('Unscheinbar hell', 'plain,light')]
    [TestCase('Unscheinbar dunkel', 'plain,dark')]
    procedure HoverTip(const ALevel, APalette: string);
    /// <summary>Szene 5, „Eigene Methode mit Standardwert“: zwei Überladungen, die erste gewählt, aktiver Parameter
    /// AMaxRows mit Standardwert 0, die zweite gedämpft; darunter PARAMETER und die Beschreibung der Methode.
    /// </summary>
    [Test]
    [TestCase('Intensiv hell', 'intense,light')]
    [TestCase('Intensiv dunkel', 'intense,dark')]
    [TestCase('Dezent hell', 'subtle,light')]
    [TestCase('Dezent dunkel', 'subtle,dark')]
    [TestCase('Unscheinbar hell', 'plain,light')]
    [TestCase('Unscheinbar dunkel', 'plain,dark')]
    procedure SignatureHint(const ALevel, APalette: string);
    /// <summary>Szene 5, „Format mit Platzhaltern“: Pfadzeile „ShowMessage › Format“, zwei Überladungen (die zweite
    /// umbrochen), Platzhalterzeile „Platzhalter 2 von 2 erwartet ganzzahlig“ und der undokumentierte Parameter Args.
    /// </summary>
    [Test]
    [TestCase('Intensiv hell', 'intense,light')]
    [TestCase('Intensiv dunkel', 'intense,dark')]
    [TestCase('Dezent hell', 'subtle,light')]
    [TestCase('Dezent dunkel', 'subtle,dark')]
    [TestCase('Unscheinbar hell', 'plain,light')]
    [TestCase('Unscheinbar dunkel', 'plain,dark')]
    procedure SignatureHintFormat(const ALevel, APalette: string);
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.IOUtils,
  System.JSON,
  Vcl.Graphics,
  Vcl.Imaging.pngimage,
  dpcc.Common.Localization.Texts,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.Core.Style.Look,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Completion.Presentation,
  dpcc.Core.Hover.Contract,
  dpcc.Core.Hover.DebugValue,
  dpcc.Core.Signature.Contract,
  dpcc.UI.Popup.Window,
  dpcc.UI.Popup.Draw,
  dpcc.UI.Completion.Strings,
  dpcc.UI.Completion.RowColors,
  dpcc.UI.Completion.Popup,
  dpcc.UI.Hover.Tip,
  dpcc.UI.Signature.Hint;

const
  cRenderDirVariable = 'DPCC_RENDER_DIR';
  /// <summary>Feste Dichte und Editorschrift, damit die Bilder auf jedem Rechner gleich groß werden.</summary>
  cPPI = 96;
  cEditorFont = 'Consolas';
  cEditorFontSize = 10;
  /// <summary>Sichtbare Zeilen der Liste: eine weniger als Einträge samt Überschrift, damit der Daumen erscheint.
  /// </summary>
  cListRows = 10;
  /// <summary>Kästchen im Mengenmodus (DrawCheck): 13 px, 7 px vom Anfang der Zeile.</summary>
  cCheckSize = 13;
  cCheckInset = 7;

type
{$SCOPEDENUMS ON}
  TRenderScene = (List, SetList, Empty, Hover, Signature, FormatCall);
{$SCOPEDENUMS OFF}

  /// <summary>Maße der Liste, wie der Zeichner sie nimmt (TDpccCompletionPopupState/-Layout).</summary>
  TListMetrics = record
    Pad: Integer;
    SyntaxHeight: Integer;
    ListTop: Integer;
    RowHeight: Integer;
    FooterHeight: Integer;
    RowCount: Integer;
  end;

  /// <summary>Was ein Test nach dem Zeichnen über das (dann freigegebene) Fenster wissen muss.</summary>
  TRenderInfo = record
    Look: TDpccLook;
    Width: Integer;
    Height: Integer;
    /// <summary>Das Fenster wurde sichtbar (darf nicht sein).</summary>
    Shown: Boolean;
    List: TListMetrics;
  end;

  /// <summary>Zugriff auf PaintWindow (geschützt in TCustomControl).</summary>
  TPaintAccess = class(TDpccPopupWindow);

  /// <summary>Vervollständigungsliste, die nie sichtbar wird; dazu ihre Maße und Relayout wie bei offenem Popup.
  /// </summary>
  TRenderList = class(TDpccCompletionPopup)
  protected
    procedure WndProc(var Message: TMessage); override;
  public
    function Metrics: TListMetrics;
    /// <summary>Relayout, wie es ShowNotice und ShowSyntax nur bei sichtbarem Popup selbst aufrufen.</summary>
    procedure ApplyLayout;
  end;

  TRenderHover = class(TDpccHoverTip)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;

  TRenderSignature = class(TDpccSignatureHint)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;

const
  cSceneNames: array[TRenderScene] of string = ('liste', 'menge', 'leer', 'hover', 'parameter', 'format');

/// <summary>ShowAt zeigt über SetWindowPos mit SWP_SHOWWINDOW; ohne das Flag setzt es nur Größe und Lage.</summary>
procedure KeepHidden(var AMessage: TMessage);
begin
  if AMessage.Msg = WM_WINDOWPOSCHANGING then
  begin
    PWindowPos(AMessage.LParam)^.flags := PWindowPos(AMessage.LParam)^.flags and not SWP_SHOWWINDOW;
  end;
end;

{ TRenderList }

procedure TRenderList.WndProc(var Message: TMessage);
begin
  KeepHidden(Message);
  inherited WndProc(Message);
end;

function TRenderList.Metrics: TListMetrics;
begin
  Result.Pad := Pad;
  Result.SyntaxHeight := SyntaxHeight;
  Result.ListTop := ListTop;
  Result.RowHeight := RowHeight;
  Result.FooterHeight := FooterHeight;
  Result.RowCount := RowCount;
end;

procedure TRenderList.ApplyLayout;
begin
  Relayout;
end;

{ TRenderHover }

procedure TRenderHover.WndProc(var Message: TMessage);
begin
  KeepHidden(Message);
  inherited WndProc(Message);
end;

{ TRenderSignature }

procedure TRenderSignature.WndProc(var Message: TMessage);
begin
  KeepHidden(Message);
  inherited WndProc(Message);
end;

{ Beispielinhalte (dpcc-popups.html) }

function Item(AKind: TDpccItemKind; const AName, ASignature: string): TDpccCompletionItem;
begin
  Result := Default(TDpccCompletionItem);
  Result.Kind := AKind;
  Result.Name := AName;
  Result.Signature := ASignature;
  Result.UnitUsed := True;
end;

/// <summary>Szene 1 samt Aktionszeile (Szene 3) und einem zweiten gedämpften Eintrag für den Daumen.</summary>
function ListItems: TDpccCompletionItems;
var
  mEdit: TDpccTextEdit;
begin
  SetLength(Result, 10);
  Result[0] := Item(TDpccItemKind.Field, 'Importer', 'Importer: TCsvImporter');
  Result[1] := Item(TDpccItemKind.Procedure_, 'ImportFile', 'procedure ImportFile(const AFileName: string)');
  Result[1].Directives := ['deprecated'];
  Result[2] := Item(TDpccItemKind.Function_, 'ImportCount', 'function ImportCount: Integer');
  Result[3] := Item(TDpccItemKind.Property_, 'ImportOptions', 'property ImportOptions: TImportOptions');
  Result[4] := Item(TDpccItemKind.Constant, 'ImportBatchSize', 'Integer');
  Result[5] := Item(TDpccItemKind.Unit_, 'ImportCsv', 'C:\Projekte\Import\ImportCsv.pas');
  // Fehlende Unit (#180): Marke „+ ImportStreams“ aus der Ergänzung der uses.
  Result[6] := Item(TDpccItemKind.Function_, 'ImportFromStream', 'function ImportFromStream(AStream: TStream): Integer');
  Result[6].UnitUsed := False;
  mEdit := Default(TDpccTextEdit);
  mEdit.NewText := ', ImportStreams';
  Result[6].AdditionalEdits := [mEdit];
  Result[7] := Item(TDpccItemKind.Procedure_, 'Neue Methode ImportClick …', 'TImportForm.ImportClick(Sender: TObject)');
  Result[7].IsAction := True;
  Result[8] := Item(TDpccItemKind.Procedure_, 'Close', 'procedure Close');
  Result[9] := Item(TDpccItemKind.Procedure_, 'Free', 'procedure Free');
end;

/// <summary>Treffer, dann „Weitere Einträge“ (#497) mit dem gedämpften Rest.</summary>
function ListOrder: TArray<Integer>;
begin
  Result := [0, 1, 2, 3, 4, 5, 6, 7, TDpccRanking.cRestHeader, 8, 9];
end;

function SetItem(const AName: string; AChecked: Boolean): TDpccCompletionItem;
begin
  Result := Item(TDpccItemKind.EnumMember, AName, 'TFontStyle');
  Result.SetOf := 'TFontStyle';
  Result.ExpectedType := 'TFontStyles';
  Result.Checked := AChecked;
end;

/// <summary>Szene 2: Memo.Font.Style := [fs</summary>
function SetItems: TDpccCompletionItems;
begin
  Result := [SetItem('fsBold', True), SetItem('fsItalic', False), SetItem('fsUnderline', True),
    SetItem('fsStrikeOut', False)];
end;

function SetOrder: TArray<Integer>;
begin
  Result := [TDpccRanking.cHeader, 0, 1, 2, 3];
end;

/// <summary>Szene 4 als Antwort des Servers (Objekt "dpcc"), gelesen wie in dpcc.IDE.Hover.Editor.</summary>
function HoverData: TDpccHoverData;
const
  cJson = '{"dpcc":{' +
    '"declaration":"function ImportFile(const AFileName: string; AMaxRows: Integer = 0): Integer",' +
    '"unit":"ImportCsv","container":"TCsvImporter","kind":"method",' +
    '"documentationText":"Liest eine CSV-Datei ein und legt je Zeile einen Datensatz an.",' +
    '"documentation":{"sections":[' +
    '{"kind":"summary","runs":[{"kind":"text",' +
    '"text":"Liest eine CSV-Datei ein und legt je Zeile einen Datensatz an."}]},' +
    '{"kind":"param","name":"AFileName","runs":[{"kind":"text","text":"Pfad der Datei."}]},' +
    '{"kind":"returns","runs":[{"kind":"text","text":"Anzahl der eingelesenen Zeilen."}]},' +
    '{"kind":"exception","name":"EFOpenError","runs":[{"kind":"text",' +
    '"text":"Die Datei lässt sich nicht öffnen."}]},' +
    '{"kind":"example","runs":[{"kind":"codeblock","text":"Count := Importer.ImportFile(''kunden.csv'');"}]},' +
    '{"kind":"seealso","runs":[{"kind":"ref","text":"ImportStream","file":"ImportCsv.pas","line":12}]}' +
    ']},' +
    '"deprecation":"Veraltet: Nimm ImportStream",' +
    '"file":"C:\\Projekte\\Import\\ImportCsv.pas","line":38,"character":11}}';
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(cJson);
  try
    Result := TDpccHoverData.FromHover(mValue);
  finally
    mValue.Free;
  end;
end;

/// <summary>Parameter AText im Label ALabel (Lage 0-basiert, Stop exklusiv wie vom Server).</summary>
function Param(const ALabel, AText, ADocumentation: string): TDpccSignatureParameter;
begin
  Result := Default(TDpccSignatureParameter);
  Result.Start := Pos(AText, ALabel) - 1;
  Result.Stop := Result.Start + Length(AText);
  Result.Documentation := ADocumentation;
end;

function Signature(const ALabel, ADocumentation: string;
  const AParameters: TArray<TDpccSignatureParameter>): TDpccSignature;
begin
  Result := Default(TDpccSignature);
  Result.Label_ := ALabel;
  Result.Documentation := ADocumentation;
  Result.Parameters := AParameters;
end;

/// <summary>Szene 5, „Eigene Methode mit Standardwert“: Importer.ImportFile(Path, |</summary>
function ImportHelp: TDpccSignatureHelp;
const
  cFile = 'ImportFile(const AFileName: string; AMaxRows: Integer = 0): Integer';
  cStream = 'ImportFile(AStream: TStream): Integer';
begin
  Result := Default(TDpccSignatureHelp);
  Result.Signatures := [
    Signature(cFile, 'Liest eine CSV-Datei ein und legt je Zeile einen Datensatz an.',
      [Param(cFile, 'const AFileName: string', 'Pfad der Datei.'),
       Param(cFile, 'AMaxRows: Integer = 0', 'Höchstzahl der Zeilen, 0 liest alle.')]),
    Signature(cStream, '', [Param(cStream, 'AStream: TStream', '')])];
  Result.ActiveSignature := 0;
  Result.ActiveParameter := 1;
end;

function Placeholder(const AText: string; ATypeChar: Char; AArgument: Integer): TDpccFormatPlaceholder;
begin
  Result := Default(TDpccFormatPlaceholder);
  Result.Text := AText;
  Result.TypeChar := ATypeChar;
  Result.Valid := True;
  Result.Argument := AArgument;
  Result.WidthArgument := -1;
  Result.PrecisionArgument := -1;
end;

/// <summary>Szene 5, „Format mit Platzhaltern“: ShowMessage(Format('%s hat %d Einträge', [Name, |</summary>
function FormatHelp: TDpccSignatureHelp;
const
  cShort = 'Format(const Format: string; const Args: array of const): string';
  cLong = 'Format(const Format: string; const Args: array of const; const AFormatSettings: TFormatSettings): ' +
    'string';
begin
  Result := Default(TDpccSignatureHelp);
  Result.Signatures := [
    Signature(cShort, '', [Param(cShort, 'const Format: string', ''), Param(cShort, 'const Args: array of const', '')]),
    Signature(cLong, '', [Param(cLong, 'const Format: string', ''), Param(cLong, 'const Args: array of const', ''),
      Param(cLong, 'const AFormatSettings: TFormatSettings', '')])];
  Result.ActiveSignature := 0;
  Result.ActiveParameter := 1;
  // Cursor auf dem zweiten Eintrag der Liste: Platzhalter %d (2 von 2).
  Result.Format.Found := True;
  Result.Format.FormatParameter := 0;
  Result.Format.ListParameter := 1;
  Result.Format.ArgumentCount := 2;
  Result.Format.ActiveArgument := 1;
  Result.Format.Placeholders := [Placeholder('%s', 's', 0), Placeholder('%d', 'd', 1)];
  Result.Format.Problem := TDpccFormatProblem.None;
  Result.Format.ProblemPlaceholder := -1;
  Result.Format.ProblemArgument := -1;
end;

{ Erzeugen, füllen, zeichnen }

function LevelOf(const ALevel: string): TDpccLookLevel;
begin
  Result := DpccLookLevelFromId(ALevel, cDpccLookLevelDefault);
end;

function PaletteFor(ADark: Boolean): TDpccColors;
begin
  if ADark then
  begin
    Result := TDpccColors.Dark;
  end
  else
  begin
    Result := TDpccColors.Light;
  end;
end;

function PaletteOf(const APalette: string): TDpccColors;
begin
  Result := PaletteFor(SameText(APalette, 'dark'));
end;

/// <summary>Wie TDpccIdeStyle.Apply: Farben, Stufe, Dichte und Editorschrift.</summary>
procedure Configure(AWindow: TDpccPopupWindow; ALevel: TDpccLookLevel; const AColors: TDpccColors);
begin
  AWindow.Colors := AColors;
  AWindow.LookLevel := ALevel;
  AWindow.SetScaling(cPPI, 1, cEditorFont, cEditorFontSize);
end;

/// <summary>Caret- bzw. Wortrechteck oben links im Arbeitsbereich: Platz für alle Fenster darunter.</summary>
function AnchorRect: TRect;
var
  mArea: TRect;
begin
  mArea := TDpccPopupWindow.WorkAreaAt(Point(0, 0));
  Result := Rect(mArea.Left + 40, mArea.Top + 40, mArea.Left + 100, mArea.Top + 58);
end;

/// <summary>Zeichnet AWindow in eine neue Bitmap seiner Größe (PaintWindow: Canvas auf den DC der Bitmap, Paint).
/// </summary>
function Capture(AWindow: TDpccPopupWindow; var AInfo: TRenderInfo): TBitmap;
begin
  AInfo.Shown := AWindow.IsShown;
  if AInfo.Shown then
  begin
    AWindow.HidePopup;
  end;
  AInfo.Look := AWindow.Look;
  AInfo.Width := AWindow.Width;
  AInfo.Height := AWindow.Height;
  Result := TBitmap.Create;
  try
    Result.PixelFormat := pf24bit;
    Result.SetSize(AWindow.Width, AWindow.Height);
    TPaintAccess(AWindow).PaintWindow(Result.Canvas.Handle);
    GdiFlush;
  except
    Result.Free;
    raise;
  end;
end;

function RenderList(AScene: TRenderScene; ALevel: TDpccLookLevel; const AColors: TDpccColors;
  var AInfo: TRenderInfo): TBitmap;
var
  mList: TRenderList;
  mNotice: TDpccSyntaxNotice;
begin
  mList := TRenderList.Create(nil);
  try
    Configure(mList, ALevel, AColors);
    // Wie TDpccEditorCompletionOpen.ApplyOptions und Anchor.
    mList.VisibleRows := cListRows;
    mList.DimInherited := True;
    mList.Anchor := AnchorRect;
    case AScene of
      TRenderScene.SetList:
        begin
          mNotice := Default(TDpccSyntaxNotice);
          mNotice.Trust := TDpccSyntaxTrust.Limited;
          mNotice.Line := 46;
          mNotice.Character := 4;
          mNotice.Message := 'Syntaxfehler in Zeile 47';
          // Vor ShowList: Ein verborgenes Popup nimmt die Höhe der Warnleiste erst beim nächsten Relayout auf.
          mList.ShowSyntax(mNotice);
          mList.ShowList(SetItems, SetOrder, 3, 'fs');
        end;
      TRenderScene.Empty:
        begin
          mList.ShowEmpty('Impx', 21);
          // L3: Hinweis links in der Fußzeile; die Breite übernimmt ShowNotice nur bei sichtbarem Popup selbst.
          mList.ShowNotice(TDpccCompletionStrings.Text(TDpccCompletionTextId.IdeListAgain));
          mList.ApplyLayout;
        end;
    else
      mList.ShowList(ListItems, ListOrder, 0, 'Imp');
    end;
    AInfo.List := mList.Metrics;
    Result := Capture(mList, AInfo);
  finally
    mList.Free;
  end;
end;

function RenderHover(ALevel: TDpccLookLevel; const AColors: TDpccColors; var AInfo: TRenderInfo): TBitmap;
var
  mTip: TRenderHover;
begin
  mTip := TRenderHover.Create(nil);
  try
    Configure(mTip, ALevel, AColors);
    mTip.ShowHover(HoverData, Default(TDpccDebugValue), 'ImportForm', AnchorRect);
    Result := Capture(mTip, AInfo);
  finally
    mTip.Free;
  end;
end;

function RenderSignature(AScene: TRenderScene; ALevel: TDpccLookLevel; const AColors: TDpccColors;
  var AInfo: TRenderInfo): TBitmap;
var
  mHint: TRenderSignature;
begin
  mHint := TRenderSignature.Create(nil);
  try
    Configure(mHint, ALevel, AColors);
    // Wie TDpccSignatureEditor: Anker, Platzhalter und Pfad vor ShowSignature.
    mHint.Anchor := AnchorRect;
    if AScene = TRenderScene.FormatCall then
    begin
      mHint.FormatPlaceholders := True;
      mHint.SetPath(['ShowMessage'], 'Format');
      mHint.ShowSignature(FormatHelp, 0, 1);
    end
    else
    begin
      mHint.ShowSignature(ImportHelp, 0, 1);
    end;
    Result := Capture(mHint, AInfo);
  finally
    mHint.Free;
  end;
end;

function RenderScene(AScene: TRenderScene; ALevel: TDpccLookLevel; const AColors: TDpccColors;
  var AInfo: TRenderInfo): TBitmap;
begin
  AInfo := Default(TRenderInfo);
  case AScene of
    TRenderScene.Hover:
      Result := RenderHover(ALevel, AColors, AInfo);
    TRenderScene.Signature, TRenderScene.FormatCall:
      Result := RenderSignature(AScene, ALevel, AColors, AInfo);
  else
    Result := RenderList(AScene, ALevel, AColors, AInfo);
  end;
end;

/// <summary>Wie RenderScene; eine Ausnahme beim Erzeugen, Füllen oder Zeichnen wird zum Fehlschlag mit ihrem Text.
/// </summary>
function Render(AScene: TRenderScene; const ALevel, APalette: string; var AInfo: TRenderInfo): TBitmap;
begin
  Result := nil;
  try
    Result := RenderScene(AScene, LevelOf(ALevel), PaletteOf(APalette), AInfo);
  except
    on E: Exception do
    begin
      Assert.Fail(Format('%s-%s-%s: Erzeugen, Füllen oder Zeichnen wirft %s: %s', [cSceneNames[AScene], ALevel,
        APalette, E.ClassName, E.Message]));
    end;
  end;
end;

/// <summary>Mit DPCC_RENDER_DIR: ABitmap als &lt;fenster&gt;-&lt;stufe&gt;-&lt;palette&gt;.png dort ablegen.</summary>
procedure SaveImage(ABitmap: TBitmap; AScene: TRenderScene; const ALevel, APalette: string);
var
  mFolder: string;
  mPng: TPngImage;
begin
  mFolder := GetEnvironmentVariable(cRenderDirVariable);
  if mFolder = '' then
  begin
    Exit;
  end;
  ForceDirectories(mFolder);
  mPng := TPngImage.Create;
  try
    mPng.Assign(ABitmap);
    mPng.SaveToFile(TPath.Combine(mFolder, Format('%s-%s-%s.png', [cSceneNames[AScene], LowerCase(ALevel),
      LowerCase(APalette)])));
  finally
    mPng.Free;
  end;
end;

{ Prüfen }

function ColorValue(AColor: TDpccColor): Cardinal;
begin
  Result := Cardinal(AColor) and $00FFFFFF;
end;

function PixelAt(ABitmap: TBitmap; AX, AY: Integer): Cardinal;
begin
  Result := Cardinal(ABitmap.Canvas.Pixels[AX, AY]) and $00FFFFFF;
end;

procedure CheckPixel(ABitmap: TBitmap; AX, AY: Integer; AExpected: TDpccColor; const AWhat: string);
var
  mFound: Cardinal;
begin
  mFound := PixelAt(ABitmap, AX, AY);
  Assert.AreEqual(Integer(ColorValue(AExpected)), Integer(mFound), Format('%s bei (%d, %d): erwartet %.6x, ' +
    'gezeichnet %.6x', [AWhat, AX, AY, Integer(ColorValue(AExpected)), Integer(mFound)]));
end;

/// <summary>Verschiedene Farben der Bitmap, gezählt bis ALimit (höchstens 16).</summary>
function DistinctColors(ABitmap: TBitmap; ALimit: Integer): Integer;
var
  mSeen: array[0..15] of Cardinal;
  mX, mY, mIndex: Integer;
  mColor: Cardinal;
  mKnown: Boolean;
begin
  Result := 0;
  if ALimit > Length(mSeen) then
  begin
    ALimit := Length(mSeen);
  end;
  for mY := 0 to ABitmap.Height - 1 do
  begin
    for mX := 0 to ABitmap.Width - 1 do
    begin
      mColor := PixelAt(ABitmap, mX, mY);
      mKnown := False;
      for mIndex := 0 to Result - 1 do
      begin
        if mSeen[mIndex] = mColor then
        begin
          mKnown := True;
          Break;
        end;
      end;
      if not mKnown then
      begin
        mSeen[Result] := mColor;
        Inc(Result);
        if Result >= ALimit then
        begin
          Exit;
        end;
      end;
    end;
  end;
end;

/// <summary>Pixel der Spalte AX in der Farbe AColor.</summary>
function ColumnCount(ABitmap: TBitmap; AX: Integer; AColor: TDpccColor): Integer;
var
  mY: Integer;
begin
  Result := 0;
  for mY := 0 to ABitmap.Height - 1 do
  begin
    if PixelAt(ABitmap, AX, mY) = ColorValue(AColor) then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Für jedes Fenster: unsichtbar geblieben, so groß wie das Fenster, nicht einfarbig, Rand an allen vier
/// Ecken in AFrame (PaintBorder: FrameRect über ClientRect, als Letztes gezeichnet).</summary>
procedure CheckBasics(ABitmap: TBitmap; const AInfo: TRenderInfo; AFrame: TDpccColor);
begin
  Assert.IsFalse(AInfo.Shown, 'Fenster wurde sichtbar');
  Assert.IsTrue((ABitmap.Width > 0) and (ABitmap.Height > 0), Format('Größe %d x %d', [ABitmap.Width,
    ABitmap.Height]));
  Assert.AreEqual(AInfo.Width, ABitmap.Width, 'Breite wie das Fenster');
  Assert.AreEqual(AInfo.Height, ABitmap.Height, 'Höhe wie das Fenster');
  // Fläche, Rand, Auswahl bzw. Kopffläche und Text: mindestens vier Farben.
  Assert.IsTrue(DistinctColors(ABitmap, 4) >= 4, 'Bitmap (fast) einfarbig');
  CheckPixel(ABitmap, 0, 0, AFrame, 'Rand oben links');
  CheckPixel(ABitmap, ABitmap.Width - 1, 0, AFrame, 'Rand oben rechts');
  CheckPixel(ABitmap, 0, ABitmap.Height - 1, AFrame, 'Rand unten links');
  CheckPixel(ABitmap, ABitmap.Width - 1, ABitmap.Height - 1, AFrame, 'Rand unten rechts');
end;

/// <summary>Farbe im Balken einer markierten Fläche: mit Look.MarkBarUsed (Intensiv) MarkBar, sonst AWithout (was
/// ohne Balken dort liegt).</summary>
function BarColor(const AInfo: TRenderInfo; AWithout: TDpccColor): TDpccColor;
begin
  if AInfo.Look.MarkBarUsed then
  begin
    Result := AInfo.Look.MarkBar;
  end
  else
  begin
    Result := AWithout;
  end;
end;

/// <summary>Parameterhilfe beider Fälle: Breite, Flächen über und unter dem Inhalt, Auswahlfläche der gewählten
/// Überladung und ihr Balken am linken Innenrand.</summary>
procedure CheckSignature(ABitmap: TBitmap; const AInfo: TRenderInfo);
var
  mSelected, mBar: Integer;
begin
  CheckBasics(ABitmap, AInfo, AInfo.Look.Frame);
  Assert.IsTrue(ABitmap.Width <= TDpccSignatureHint.cMaxWidth, 'Breite ' + IntToStr(ABitmap.Width));
  // Über der ersten Überladung (cPad = 4) bzw. in der Pfadzeile ohne Band: links von cGap = 10 nur Fläche.
  CheckPixel(ABitmap, 3, 2, AInfo.Look.Colors.Surface, 'Fläche oben');
  // Unter der Doku-Zeile: Trennlinien und Texte beginnen erst bei cGap.
  CheckPixel(ABitmap, 3, ABitmap.Height - 3, AInfo.Look.Colors.Surface, 'Fläche unten');
  // Gewählte von zwei Überladungen: Auswahlfläche ab x = 1, Text erst ab cGap; in der Spalte x = 5 (hinter dem Balken
  // von x = 1 bis 3) ein Streifen von mindestens einer Zeile (Editorschrift + 6), aber nicht die ganze Höhe (die
  // zweite Überladung liegt auf der Fläche).
  mSelected := ColumnCount(ABitmap, 5, AInfo.Look.SelectionBack);
  Assert.IsTrue((mSelected >= 12) and (mSelected < ABitmap.Height div 2), Format('Auswahlfläche: %d von %d Pixeln ' +
    'der Spalte', [mSelected, ABitmap.Height]));
  // Balken (Intensiv): die ersten 3 px der Auswahlfläche am linken Innenrand über ihre ganze Höhe; in der Spalte x = 2
  // so viele Pixel in MarkBar wie die Auswahlfläche hoch ist (ohne Balken dort die Auswahlfläche).
  mBar := ColumnCount(ABitmap, 2, BarColor(AInfo, AInfo.Look.SelectionBack));
  Assert.AreEqual(mSelected, mBar, 'Balken der gewählten Überladung (Spalte x = 2)');
  // Der Rand bleibt neben dem Balken: Spalte x = 0 auf halber Höhe in FrameColor.
  CheckPixel(ABitmap, 0, ABitmap.Height div 2, AInfo.Look.Frame, 'Rand links');
end;

{ TDpccPopupRenderTests }

procedure TDpccPopupRenderTests.Prewarm;
var
  mScene: TRenderScene;
  mLevel: TDpccLookLevel;
  mDark: Boolean;
  mInfo: TRenderInfo;
  mBitmap: TBitmap;
  mPng: TPngImage;
  mStream: TMemoryStream;
begin
  // Dieselbe Sprache wie in den Tests (TLeakMonitor.PreSetup): Texte der Fenster einmal vorab.
  TDpccLocale.Use(TTextLanguage.German);
  for mScene := Low(TRenderScene) to High(TRenderScene) do
  begin
    for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
    begin
      for mDark := False to True do
      begin
        mBitmap := RenderScene(mScene, mLevel, PaletteFor(mDark), mInfo);
        try
          // Der PNG-Kodierer legt beim ersten Gebrauch Tabellen an; einmal in den Speicher kodieren.
          if (mScene = Low(TRenderScene)) and (mLevel = Low(TDpccLookLevel)) and not mDark then
          begin
            mStream := TMemoryStream.Create;
            mPng := TPngImage.Create;
            try
              mPng.Assign(mBitmap);
              mPng.SaveToStream(mStream);
            finally
              mPng.Free;
              mStream.Free;
            end;
          end;
        finally
          mBitmap.Free;
        end;
      end;
    end;
  end;
end;

procedure TDpccPopupRenderTests.CompletionList(const ALevel, APalette: string);
var
  mInfo: TRenderInfo;
  mBitmap: TBitmap;
  mList: TListMetrics;
  mRowMiddle: Integer;
begin
  mBitmap := Render(TRenderScene.List, ALevel, APalette, mInfo);
  try
    SaveImage(mBitmap, TRenderScene.List, ALevel, APalette);
    CheckBasics(mBitmap, mInfo, mInfo.Look.Frame);
    mList := mInfo.List;
    // Höhe wie ListHeight: Innenabstand oben und unten, zehn sichtbare Zeilen (elf Einträge samt Überschrift),
    // Fußzeile; ohne Warnleiste. Breite in den Grenzen der Liste.
    Assert.AreEqual(cListRows, mList.RowCount, 'sichtbare Zeilen');
    Assert.AreEqual(0, mList.SyntaxHeight, 'keine Warnleiste');
    Assert.AreEqual(2 * mList.Pad + cListRows * mList.RowHeight + mList.FooterHeight, mBitmap.Height, 'Höhe');
    Assert.IsTrue((mBitmap.Width >= TDpccCompletionPopup.cMinWidth) and
      (mBitmap.Width <= TDpccCompletionPopup.cMaxWidth), 'Breite ' + IntToStr(mBitmap.Width));
    mRowMiddle := mList.ListTop + mList.RowHeight div 2;
    // Gewählte erste Zeile: RowRect beginnt bei Pad, die Art-Spalte erst cInset = 4 px weiter; Pad + 1 liegt nur
    // auf der Auswahlfläche.
    CheckPixel(mBitmap, mList.Pad + 1, mRowMiddle, mInfo.Look.SelectionBack, 'gewählte Zeile');
    // Zwischen Rand (x = 0) und Innenabstand (Pad) neben der gewählten Zeile: Intensiv der Balken von Pad - 3 bis vor
    // Pad über die ganze Zeilenhöhe, sonst nur die Fläche; der Rand bleibt.
    CheckPixel(mBitmap, 2, mRowMiddle, BarColor(mInfo, mInfo.Look.Colors.Surface), 'Balken links der gewählten Zeile');
    CheckPixel(mBitmap, mList.Pad - 3, mList.ListTop, BarColor(mInfo, mInfo.Look.Colors.Surface),
      'Balken oben links');
    CheckPixel(mBitmap, mList.Pad - 1, mList.ListTop + mList.RowHeight - 1, BarColor(mInfo, mInfo.Look.Colors.Surface),
      'Balken unten rechts');
    CheckPixel(mBitmap, 0, mRowMiddle, mInfo.Look.Frame, 'Rand neben dem Balken');
    // Zweite Zeile (ImportFile, deprecated) ist nicht gewählt: an derselben Stelle Fläche, auch ohne Balken davor.
    CheckPixel(mBitmap, mList.Pad + 1, mRowMiddle + mList.RowHeight, mInfo.Look.Colors.Surface,
      'nicht gewählte Zeile');
    CheckPixel(mBitmap, 2, mRowMiddle + mList.RowHeight, mInfo.Look.Colors.Surface, 'kein Balken vor der zweiten Zeile');
    // Scroll-Daumen (elf Einträge, zehn sichtbar, ganz oben): Spur von Breite - Pad - 5 bis Breite - Pad - 1, ab
    // ListTop + 2; rechts neben dem Ende der Zeilen (Breite - Pad - ScrollReserve).
    CheckPixel(mBitmap, mBitmap.Width - mList.Pad - 3, mList.ListTop + 3, TDpccDraw.ThumbColor(mInfo.Look.Colors),
      'Scroll-Daumen');
  finally
    mBitmap.Free;
  end;
end;

procedure TDpccPopupRenderTests.CompletionListSetMode(const ALevel, APalette: string);
var
  mInfo: TRenderInfo;
  mBitmap: TBitmap;
  mList: TListMetrics;
  mItems: TDpccCompletionItems;
  mColors: TDpccRowColors;
  mBar: TDpccColor;
  mBoxLeft, mBoxTop: Integer;
begin
  mBitmap := Render(TRenderScene.SetList, ALevel, APalette, mInfo);
  try
    SaveImage(mBitmap, TRenderScene.SetList, ALevel, APalette);
    CheckBasics(mBitmap, mInfo, mInfo.Look.Frame);
    mList := mInfo.List;
    // Warnleiste über der Liste, darunter Überschrift und vier Werte.
    Assert.IsTrue(mList.SyntaxHeight > 0, 'Warnleiste');
    Assert.AreEqual(5, mList.RowCount, 'Zeilen');
    Assert.AreEqual(mList.Pad + mList.SyntaxHeight, mList.ListTop, 'Liste unter der Warnleiste');
    Assert.AreEqual(2 * mList.Pad + mList.SyntaxHeight + 5 * mList.RowHeight + mList.FooterHeight, mBitmap.Height,
      'Höhe');
    // Warnleiste: Intensiv und Dezent füllen sie ab (0, 0) bis vor die Trennlinie mit WarnBack, der Text beginnt erst
    // bei Pad + 12; Unscheinbar lässt die Fläche.
    if mInfo.Look.WarnBackUsed then
    begin
      mBar := mInfo.Look.WarnBack;
    end
    else
    begin
      mBar := mInfo.Look.Colors.Surface;
    end;
    CheckPixel(mBitmap, 2, 2, mBar, 'Warnleiste');
    // Überschrift (Zeile 0) ohne Fläche, Text erst ab Pad + 7.
    CheckPixel(mBitmap, mList.Pad + 1, mList.ListTop + mList.RowHeight div 2, mInfo.Look.Colors.Surface,
      'Überschrift');
    // Gewählt ist fsUnderline (Position 3): Auswahlfläche ab Pad, Kästchen erst ab Pad + 7; Intensiv auch im
    // Mengenmodus der Balken links davor.
    CheckPixel(mBitmap, mList.Pad + 1, mList.ListTop + 3 * mList.RowHeight + mList.RowHeight div 2,
      mInfo.Look.SelectionBack, 'gewählte Zeile');
    CheckPixel(mBitmap, 2, mList.ListTop + 3 * mList.RowHeight + mList.RowHeight div 2,
      BarColor(mInfo, mInfo.Look.Colors.Surface), 'Balken links der gewählten Zeile');
    // Kästchen (DrawCheck): 13 px ab Pad + 7, senkrecht in der Zeile zentriert. Zeile 1 (fsBold) angehakt: Fläche
    // CheckFill; (1, 1) im Kästchen liegt vor dem Haken (beginnt bei 3/13).
    mItems := SetItems;
    mColors := TDpccCompletionRowColors.Row(mInfo.Look, TDpccItemPresentation.KindWord(mItems[0]), False, False,
      False);
    mBoxLeft := mList.Pad + cCheckInset;
    mBoxTop := mList.ListTop + mList.RowHeight + (mList.RowHeight - cCheckSize) div 2;
    CheckPixel(mBitmap, mBoxLeft + 1, mBoxTop + 1, mColors.CheckFill, 'angehaktes Kästchen');
    // Zeile 2 (fsItalic) leer: 1 px Rand in CheckFrame, innen Fläche (der Text beginnt erst hinter cCheckWidth).
    mBoxTop := mList.ListTop + 2 * mList.RowHeight + (mList.RowHeight - cCheckSize) div 2;
    CheckPixel(mBitmap, mBoxLeft, mBoxTop + cCheckSize div 2, mColors.CheckFrame, 'Rand des leeren Kästchens');
    CheckPixel(mBitmap, mBoxLeft + cCheckSize div 2, mBoxTop + cCheckSize div 2, mInfo.Look.Colors.Surface,
      'leeres Kästchen innen');
    // Zeile 3 (fsUnderline, gewählt) angehakt: Kästchen wie in Dezent mit der Fläche in Look.Action (Intensiv der
    // Akzent, nicht mehr die Flächenfarbe), Haken in der Flächenfarbe.
    mColors := TDpccCompletionRowColors.Row(mInfo.Look, TDpccItemPresentation.KindWord(mItems[2]), False, True,
      False);
    Assert.AreEqual(Integer(ColorValue(mInfo.Look.Action)), Integer(ColorValue(mColors.CheckFill)),
      'Kästchen der gewählten Zeile in Look.Action');
    Assert.AreEqual(Integer(ColorValue(mInfo.Look.Colors.Surface)), Integer(ColorValue(mColors.CheckMark)),
      'Haken der gewählten Zeile in der Flächenfarbe');
    mBoxTop := mList.ListTop + 3 * mList.RowHeight + (mList.RowHeight - cCheckSize) div 2;
    CheckPixel(mBitmap, mBoxLeft + 1, mBoxTop + 1, mColors.CheckFill, 'angehaktes Kästchen der gewählten Zeile');
  finally
    mBitmap.Free;
  end;
end;

procedure TDpccPopupRenderTests.CompletionListEmpty(const ALevel, APalette: string);
var
  mInfo: TRenderInfo;
  mBitmap: TBitmap;
  mList: TListMetrics;
  mRowMiddle: Integer;
begin
  mBitmap := Render(TRenderScene.Empty, ALevel, APalette, mInfo);
  try
    SaveImage(mBitmap, TRenderScene.Empty, ALevel, APalette);
    CheckBasics(mBitmap, mInfo, mInfo.Look.Frame);
    mList := mInfo.List;
    // Leerer Zustand: zwei Zeilen und Fußzeile, mindestens so breit wie die kleinste Liste.
    Assert.AreEqual(2 * mList.Pad + 2 * mList.RowHeight + mList.FooterHeight, mBitmap.Height, 'Höhe');
    Assert.IsTrue(mBitmap.Width >= TDpccCompletionPopup.cMinWidth, 'Breite ' + IntToStr(mBitmap.Width));
    mRowMiddle := mList.ListTop + mList.RowHeight div 2;
    // „Keine Treffer …“ auf der Kopffläche von Pad bis Breite - Pad, Text erst ab Pad + 7; links davor im
    // Innenabstand Intensiv der Balken (Pad - 3 bis vor Pad), sonst die Fläche; der Rand bleibt.
    CheckPixel(mBitmap, mList.Pad + 1, mRowMiddle, mInfo.Look.HeadBack, 'Kopfzeile');
    CheckPixel(mBitmap, 2, mRowMiddle, BarColor(mInfo, mInfo.Look.Colors.Surface), 'Balken links der Kopfzeile');
    CheckPixel(mBitmap, 0, mRowMiddle, mInfo.Look.Frame, 'Rand neben dem Balken');
    // „Rücktaste erweitert die Suche“ ohne Fläche und ohne Balken.
    CheckPixel(mBitmap, mList.Pad + 1, mRowMiddle + mList.RowHeight, mInfo.Look.Colors.Surface, 'zweite Zeile');
    CheckPixel(mBitmap, 2, mRowMiddle + mList.RowHeight, mInfo.Look.Colors.Surface, 'kein Balken vor der zweiten Zeile');
  finally
    mBitmap.Free;
  end;
end;

procedure TDpccPopupRenderTests.HoverTip(const ALevel, APalette: string);
var
  mInfo: TRenderInfo;
  mBitmap: TBitmap;
  mHead: Integer;
begin
  mBitmap := Render(TRenderScene.Hover, ALevel, APalette, mInfo);
  try
    SaveImage(mBitmap, TRenderScene.Hover, ALevel, APalette);
    CheckBasics(mBitmap, mInfo, mInfo.Look.HoverFrame);
    // Mit Doku nimmt der Tooltip die Höchstbreite (PreferredWidth); hoch genug für Kopfzeile, Herkunft, Fundort,
    // Veraltung und die ganze Doku.
    Assert.AreEqual(TDpccHoverTip.cMaxWidth, mBitmap.Width, 'Breite');
    Assert.IsTrue(mBitmap.Height > 150, 'Höhe ' + IntToStr(mBitmap.Height));
    // Kopfzeile: Band ab y = 1 von Innenrand zu Innenrand, Text erst ab cPadX = 8 und unter cPadTop = 5. Intensiv
    // liegt darüber in den obersten 3 Zeilen unter dem Rand (y = 1 bis 3) der Balken von Innenrand zu Innenrand, sonst
    // dort die Kopffläche; (3, 5) liegt in allen Stufen nur auf der Kopffläche.
    CheckPixel(mBitmap, 3, 1, BarColor(mInfo, mInfo.Look.HeadBack), 'Balken oben');
    CheckPixel(mBitmap, 3, 3, BarColor(mInfo, mInfo.Look.HeadBack), 'Balken unten');
    CheckPixel(mBitmap, 1, 2, BarColor(mInfo, mInfo.Look.HeadBack), 'Balken am linken Innenrand');
    CheckPixel(mBitmap, mBitmap.Width - 2, 2, BarColor(mInfo, mInfo.Look.HeadBack), 'Balken am rechten Innenrand');
    CheckPixel(mBitmap, 3, 4, mInfo.Look.HeadBack, 'Kopfzeile unter dem Balken');
    CheckPixel(mBitmap, 3, 5, mInfo.Look.HeadBack, 'Kopfzeile');
    // Der Rand bleibt über und neben dem Balken sichtbar.
    CheckPixel(mBitmap, mBitmap.Width div 2, 0, mInfo.Look.HoverFrame, 'Rand über dem Balken');
    CheckPixel(mBitmap, 0, 2, mInfo.Look.HoverFrame, 'Rand links neben dem Balken');
    CheckPixel(mBitmap, mBitmap.Width - 1, 2, mInfo.Look.HoverFrame, 'Rand rechts neben dem Balken');
    // Kopffläche nur oben: in der Spalte x = 3 mindestens die Höhe einer Zeile, weniger als ein Drittel der Höhe.
    mHead := ColumnCount(mBitmap, 3, mInfo.Look.HeadBack);
    Assert.IsTrue((mHead > 10) and (mHead < mBitmap.Height div 3), Format('Kopffläche: %d von %d Pixeln der Spalte',
      [mHead, mBitmap.Height]));
    // Unterer Innenabstand (cPadBottom = 5): links vom Text nur Fläche (die Doku ist ab cPadX beschnitten).
    CheckPixel(mBitmap, 3, mBitmap.Height - 3, mInfo.Look.Colors.Surface, 'Fläche unten');
    // Veraltung auf der Warnfläche (Intensiv, Dezent): Band von Innenrand zu Innenrand, also auch in der Spalte x = 3.
    if mInfo.Look.WarnBackUsed then
    begin
      Assert.IsTrue(ColumnCount(mBitmap, 3, mInfo.Look.WarnBack) > 5, 'Warnfläche der Veraltung');
    end;
  finally
    mBitmap.Free;
  end;
end;

procedure TDpccPopupRenderTests.SignatureHint(const ALevel, APalette: string);
var
  mInfo: TRenderInfo;
  mBitmap: TBitmap;
begin
  mBitmap := Render(TRenderScene.Signature, ALevel, APalette, mInfo);
  try
    SaveImage(mBitmap, TRenderScene.Signature, ALevel, APalette);
    CheckSignature(mBitmap, mInfo);
  finally
    mBitmap.Free;
  end;
end;

procedure TDpccPopupRenderTests.SignatureHintFormat(const ALevel, APalette: string);
var
  mInfo: TRenderInfo;
  mBitmap: TBitmap;
begin
  mBitmap := Render(TRenderScene.FormatCall, ALevel, APalette, mInfo);
  try
    SaveImage(mBitmap, TRenderScene.FormatCall, ALevel, APalette);
    CheckSignature(mBitmap, mInfo);
  finally
    mBitmap.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccPopupRenderTests);

end.
