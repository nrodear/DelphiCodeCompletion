unit dpcc.UI.Popup.Styled;

// Eingefärbter Code-Text für Hover-Tooltip und Parameter-Hint (#411, #436):
// Schlüsselwörter halbfett in Schlüsselwortfarbe, Strings und Kommentare in
// eigener Farbe; optional ein aktiver Bereich (aktiver Parameter) fett in
// Textfarbe, in der gewählten Überladung zusätzlich unterstrichen (seit S8 flach
// wie der Hover statt einer gerundeten Akzentfläche); Standardwerte von Parametern
// (" = 1", #441) gedämpft. Messen und Zeichnen gehen
// über dieselben Stücke, damit Umbruch und Zeichnung übereinstimmen.
// Schnell: Stücke ohne Array-Verkettung und ohne Sortieren je Token; der Umbruch
// misst den Text einmal (Präfixsummen) und rechnet dann nur noch Differenzen
// (TDpccWrap).
// Stufen der Darstellung (LOOK1): Typnamen sind ein eigenes Stück (TDpccSyntax.SignatureTokens). Ein Ziel aus
// TDpccLook (Create mit ALook) färbt Schlüsselwort, String, Kommentar, Zahl und Typ in den Syn*-Farben der Stufe und
// legt den aktiven Parameter auf ParamBack (wenn ParamBackUsed). Markierte Flächen (Kopfzeile des Hovers, gewählte
// Überladung) zeichnen ihre Aufrufer mit dem Ziel aus TDpccLook.Marked (Intensiv wie Dezent). Ein Ziel aus
// TDpccColors färbt wie vor LOOK1 (Zahlen und Typen in Textfarbe).

interface

uses
  System.Types,
  Vcl.Graphics,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.Core.Style.Look,
  dpcc.Core.Style.Syntax;

type
  /// <summary>Wohin gezeichnet wird: Leinwand und Farben.</summary>
  TDpccStyledTarget = record
    Canvas: TCanvas;
    Colors: TDpccColors;
    /// <summary>Farben der Stufe; nur mit UseLook (Create mit ALook).</summary>
    Look: TDpccLook;
    /// <summary>True: Syntax in den Syn*-Farben von Look; False: wie vor LOOK1 aus Colors.</summary>
    UseLook: Boolean;
    /// <summary>True: Fläche ActiveBack unter dem aktiven Bereich (aktiver Parameter).</summary>
    ActiveBackUsed: Boolean;
    ActiveBack: TDpccColor;
    /// <summary>Farben wie vor LOOK1: Schlüsselwort, String, Kommentar aus AColors, alles andere in Textfarbe.
    /// </summary>
    class function Create(ACanvas: TCanvas; const AColors: TDpccColors): TDpccStyledTarget; overload; static;
    /// <summary>Farben der Stufe ALook: SynKeyword, SynString, SynComment, SynNumber, SynType, Rest in Textfarbe;
    /// aktiver Parameter auf ParamBack, wenn ParamBackUsed. Für markierte Flächen ALook.Marked übergeben; deren
    /// Fläche füllt der Aufrufer.</summary>
    class function Create(ACanvas: TCanvas; const ALook: TDpccLook): TDpccStyledTarget; overload; static;
  end;

  TDpccStyledText = record
  private type
    TPiece = record
      Start: Integer;
      Stop: Integer;
      Kind: TDpccTokenKind;
      Active: Boolean;
      Muted: Boolean;
    end;
  private
    function Pieces(AFrom, ATill: Integer): TArray<TPiece>;
    /// <summary>Schnitte in [AFrom, ATill] an den Grenzen des aktiven und der gedämpften Bereiche, aufsteigend;
    /// liefert ihre Zahl.</summary>
    function CutsWithin(AFrom, ATill: Integer; var ACuts: TArray<Integer>): Integer;
    function PieceOf(AStart, AStop: Integer; AKind: TDpccTokenKind): TPiece;
    function PieceText(const APiece: TPiece): string;
    function PieceWidths(ACanvas: TCanvas; const APieces: TArray<TPiece>): TArray<Integer>;
    procedure ApplyFont(ACanvas: TCanvas; const APiece: TPiece);
  public
    Text: string;
    Tokens: TDpccTokens;
    /// <summary>Aktiver Bereich, 0-basiert, Stop exklusiv; -1 ohne.</summary>
    ActiveStart: Integer;
    ActiveStop: Integer;
    /// <summary>Aktiven Bereich unterstreichen (gewählte Überladung; sonst nur fett).</summary>
    ActiveUnderline: Boolean;
    /// <summary>Gedämpfte Bereiche (Standardwerte), X = Start, Y = Stop.</summary>
    MutedRanges: TArray<TPoint>;
    class function Create(const AText: string): TDpccStyledText; static;
    /// <summary>Breite von Text[AFrom..ATill) in der Schrift von ACanvas.</summary>
    function Width(ACanvas: TCanvas; AFrom, ATill: Integer): Integer;
    /// <summary>Zeichnet Text[AFrom..ATill) ab AX in der Zeile ARow; AX steht danach hinter dem Text.
    /// ARange: X = AFrom, Y = ATill (wie die Zeilen von WrapAtSpaces).</summary>
    procedure Draw(const ATarget: TDpccStyledTarget; const ARange: TPoint; var AX: Integer; const ARow: TRect;
      ADimmed: Boolean);
    /// <summary>Breiten aller Präfixe: Ergebnis[i] = Breite von Text[0..i), Länge Length(Text) + 1.</summary>
    function PrefixWidths(ACanvas: TCanvas): TArray<Integer>;
    /// <summary>Zeilen (Bereiche) bei Umbruch an Leerzeichen; Folgezeilen um AIndent schmaler.</summary>
    function WrapAtSpaces(ACanvas: TCanvas; AWidth, AIndent: Integer): TArray<TPoint>;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.UITypes,
  dpcc.Core.Style.Wrap;

/// <summary>ACuts[0..ACount) aufsteigend: Einfügesortierung, die Liste ist winzig.</summary>
procedure SortCuts(var ACuts: TArray<Integer>; ACount: Integer);
var
  mIndex, mValue, mPosition: Integer;
begin
  for mIndex := 1 to ACount - 1 do
  begin
    mValue := ACuts[mIndex];
    mPosition := mIndex - 1;
    while (mPosition >= 0) and (ACuts[mPosition] > mValue) do
    begin
      ACuts[mPosition + 1] := ACuts[mPosition];
      Dec(mPosition);
    end;
    ACuts[mPosition + 1] := mValue;
  end;
end;

/// <summary>Farbe eines Stücks: aktiv in Textfarbe, gedämpft, sonst nach der Art des Tokens (mit Look in den
/// Syn*-Farben der Stufe).</summary>
function PieceColor(const ATarget: TDpccStyledTarget; AKind: TDpccTokenKind; AActive, AMuted: Boolean): TDpccColor;
begin
  if AActive then
  begin
    Exit(ATarget.Colors.Text);
  end;
  if AMuted then
  begin
    Exit(ATarget.Colors.Muted);
  end;
  if ATarget.UseLook then
  begin
    case AKind of
      TDpccTokenKind.Keyword: Result := ATarget.Look.SynKeyword;
      TDpccTokenKind.StringLiteral: Result := ATarget.Look.SynString;
      TDpccTokenKind.Comment: Result := ATarget.Look.SynComment;
      TDpccTokenKind.Number: Result := ATarget.Look.SynNumber;
      TDpccTokenKind.TypeName: Result := ATarget.Look.SynType;
    else
      Result := ATarget.Colors.Text;
    end;
    Exit;
  end;
  case AKind of
    TDpccTokenKind.Keyword: Result := ATarget.Colors.Keyword;
    TDpccTokenKind.StringLiteral: Result := ATarget.Colors.StringLiteral;
    TDpccTokenKind.Comment: Result := ATarget.Colors.Comment;
  else
    Result := ATarget.Colors.Text;
  end;
end;

{ TDpccStyledTarget }

class function TDpccStyledTarget.Create(ACanvas: TCanvas; const AColors: TDpccColors): TDpccStyledTarget;
begin
  Result := Default(TDpccStyledTarget);
  Result.Canvas := ACanvas;
  Result.Colors := AColors;
end;

class function TDpccStyledTarget.Create(ACanvas: TCanvas; const ALook: TDpccLook): TDpccStyledTarget;
begin
  Result := Default(TDpccStyledTarget);
  Result.Canvas := ACanvas;
  Result.Colors := ALook.Colors;
  Result.Look := ALook;
  Result.UseLook := True;
  Result.ActiveBackUsed := ALook.ParamBackUsed;
  Result.ActiveBack := ALook.ParamBack;
end;

{ TDpccStyledText }

class function TDpccStyledText.Create(const AText: string): TDpccStyledText;
begin
  Result.Text := AText;
  // Mit Typnamen (LOOK1); ein Ziel aus TDpccColors zeichnet sie wie bisher in Textfarbe.
  Result.Tokens := TDpccSyntax.SignatureTokens(AText);
  Result.ActiveStart := -1;
  Result.ActiveStop := -1;
  Result.ActiveUnderline := True;
  Result.MutedRanges := TDpccSyntax.DefaultRanges(AText);
end;

function TDpccStyledText.CutsWithin(AFrom, ATill: Integer; var ACuts: TArray<Integer>): Integer;
var
  mCount: Integer;
  mRange: TPoint;

  procedure AddInside(AValue: Integer);
  begin
    if (AValue > AFrom) and (AValue < ATill) then
    begin
      ACuts[mCount] := AValue;
      Inc(mCount);
    end;
  end;

begin
  ACuts[0] := AFrom;
  mCount := 1;
  AddInside(ActiveStart);
  AddInside(ActiveStop);
  for mRange in MutedRanges do
  begin
    AddInside(mRange.X);
    AddInside(mRange.Y);
  end;
  ACuts[mCount] := ATill;
  Inc(mCount);
  SortCuts(ACuts, mCount);
  Result := mCount;
end;

function TDpccStyledText.PieceOf(AStart, AStop: Integer; AKind: TDpccTokenKind): TPiece;
var
  mRange: TPoint;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
  Result.Kind := AKind;
  Result.Active := (ActiveStart >= 0) and (AStart >= ActiveStart) and (AStop <= ActiveStop);
  Result.Muted := False;
  for mRange in MutedRanges do
  begin
    if (AStart >= mRange.X) and (AStop <= mRange.Y) then
    begin
      Result.Muted := True;
    end;
  end;
end;

function TDpccStyledText.PieceText(const APiece: TPiece): string;
begin
  Result := Copy(Text, APiece.Start + 1, APiece.Stop - APiece.Start);
end;

function TDpccStyledText.Pieces(AFrom, ATill: Integer): TArray<TPiece>;
var
  mToken: TDpccToken;
  mCuts: TArray<Integer>;
  mCutCount, mCount, mIndex: Integer;
begin
  Result := nil;
  mCount := 0;
  // Höchstens Anfang, Ende, zwei aktive Grenzen und zwei je gedämpftem Bereich.
  mCuts := nil;
  SetLength(mCuts, 4 + 2 * Length(MutedRanges));
  for mToken in Tokens do
  begin
    if Min(ATill, mToken.Stop) <= Max(AFrom, mToken.Start) then
    begin
      Continue;
    end;
    // Innerhalb des Tokens an den Grenzen des aktiven und der gedämpften Bereiche schneiden.
    mCutCount := CutsWithin(Max(AFrom, mToken.Start), Min(ATill, mToken.Stop), mCuts);
    for mIndex := 0 to mCutCount - 2 do
    begin
      if mCuts[mIndex + 1] = mCuts[mIndex] then
      begin
        Continue;
      end;
      if mCount = Length(Result) then
      begin
        SetLength(Result, 2 * mCount + 8);
      end;
      Result[mCount] := PieceOf(mCuts[mIndex], mCuts[mIndex + 1], mToken.Kind);
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

function TDpccStyledText.PieceWidths(ACanvas: TCanvas; const APieces: TArray<TPiece>): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(APieces));
  for mIndex := 0 to High(APieces) do
  begin
    ApplyFont(ACanvas, APieces[mIndex]);
    Result[mIndex] := ACanvas.TextWidth(PieceText(APieces[mIndex]));
  end;
end;

procedure TDpccStyledText.ApplyFont(ACanvas: TCanvas; const APiece: TPiece);
begin
  // Breite und Zeichnung gleich: Schlüsselwörter auch gedämpft halbfett.
  if APiece.Active or (not APiece.Muted and (APiece.Kind = TDpccTokenKind.Keyword)) then
  begin
    ACanvas.Font.Style := [fsBold];
  end
  else
  begin
    ACanvas.Font.Style := [];
  end;
end;

function TDpccStyledText.Width(ACanvas: TCanvas; AFrom, ATill: Integer): Integer;
var
  mPiece: TPiece;
begin
  Result := 0;
  for mPiece in Pieces(AFrom, ATill) do
  begin
    ApplyFont(ACanvas, mPiece);
    Inc(Result, ACanvas.TextWidth(Copy(Text, mPiece.Start + 1, mPiece.Stop - mPiece.Start)));
  end;
  ACanvas.Font.Style := [];
end;

procedure TDpccStyledText.Draw(const ATarget: TDpccStyledTarget; const ARange: TPoint; var AX: Integer;
  const ARow: TRect; ADimmed: Boolean);
const
  cFlags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS;
var
  mPieces: TArray<TPiece>;
  mWidths: TArray<Integer>;
  mIndex: Integer;
  mPart: TRect;
  mText: string;
  mCanvas: TCanvas;
begin
  mCanvas := ATarget.Canvas;
  mPieces := Pieces(ARange.X, ARange.Y);
  mWidths := PieceWidths(mCanvas, mPieces);
  mCanvas.Brush.Style := bsClear;
  for mIndex := 0 to High(mPieces) do
  begin
    if AX >= ARow.Right then
    begin
      Break;
    end;
    ApplyFont(mCanvas, mPieces[mIndex]);
    // Unterstreichung ändert die Breite nicht; Messen (ApplyFont) und Zeichnen bleiben gleich.
    if mPieces[mIndex].Active and ActiveUnderline and not ADimmed then
    begin
      mCanvas.Font.Style := mCanvas.Font.Style + [fsUnderline];
    end;
    // Fläche unter dem aktiven Parameter (Stufe Intensiv); die Stücke sind an seinen Grenzen geschnitten.
    if mPieces[mIndex].Active and ATarget.ActiveBackUsed and not ADimmed then
    begin
      mCanvas.Brush.Style := bsSolid;
      mCanvas.Brush.Color := TColor(ATarget.ActiveBack);
      mCanvas.FillRect(Rect(AX, ARow.Top, Min(AX + mWidths[mIndex], ARow.Right), ARow.Bottom));
      mCanvas.Brush.Style := bsClear;
    end;
    mCanvas.Font.Color := TColor(PieceColor(ATarget, mPieces[mIndex].Kind,
      mPieces[mIndex].Active and not ADimmed, ADimmed or mPieces[mIndex].Muted));
    mText := PieceText(mPieces[mIndex]);
    mPart := Rect(AX, ARow.Top, ARow.Right, ARow.Bottom);
    DrawText(mCanvas.Handle, PChar(mText), -1, mPart, cFlags);
    Inc(AX, mWidths[mIndex]);
  end;
  mCanvas.Font.Style := [];
  mCanvas.Brush.Style := bsSolid;
end;

function TDpccStyledText.PrefixWidths(ACanvas: TCanvas): TArray<Integer>;
var
  mPiece: TPiece;
  mPartial: TArray<Integer>;
  mPieceText: string;
  mIndex, mBase, mFit, mDone: Integer;
  mSize: TSize;
begin
  Result := nil;
  SetLength(Result, Length(Text) + 1);
  Result[0] := 0;
  mDone := 0;
  for mPiece in Pieces(0, Length(Text)) do
  begin
    // Lücke ohne Token (kommt bei TDpccSyntax nicht vor): Breite 0 wie bisher in Width.
    for mIndex := mDone + 1 to mPiece.Start do
    begin
      Result[mIndex] := Result[mDone];
    end;
    mDone := mPiece.Stop;
    ApplyFont(ACanvas, mPiece);
    mPieceText := Copy(Text, mPiece.Start + 1, mPiece.Stop - mPiece.Start);
    // TextWidth wählt die Schrift mit dem Stil des Stücks in den DC; dann Teilbreiten je Zeichen.
    mBase := Result[mPiece.Start];
    Result[mPiece.Stop] := mBase + ACanvas.TextWidth(mPieceText);
    mPartial := nil;
    SetLength(mPartial, Length(mPieceText));
    if (Length(mPieceText) > 0) and GetTextExtentExPointW(ACanvas.Handle, PChar(mPieceText), Length(mPieceText),
      MaxInt, @mFit, @mPartial[0], mSize) then
    begin
      for mIndex := 0 to High(mPartial) - 1 do
      begin
        Result[mPiece.Start + mIndex + 1] := mBase + mPartial[mIndex];
      end;
    end;
  end;
  for mIndex := mDone + 1 to Length(Text) do
  begin
    Result[mIndex] := Result[mDone];
  end;
  ACanvas.Font.Style := [];
end;

function TDpccStyledText.WrapAtSpaces(ACanvas: TCanvas; AWidth, AIndent: Integer): TArray<TPoint>;
begin
  // Umbruch hinter Leerzeichen; ein Wort, das allein nicht passt, steht allein (gekürzt).
  Result := TDpccWrap.AtSpaces(Text, PrefixWidths(ACanvas), AWidth, AIndent);
end;

end.
