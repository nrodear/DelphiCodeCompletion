unit dpcc.Core.Style.Color;

// Farbmathematik von dpcc (#411), ohne VCL: Farben im Format von TColor
// ($00BBGGRR), damit die Oberfläche sie direkt verwenden kann. Mischen wie
// eine halbtransparente Fläche, HSL zum Aufhellen und Abdunkeln, relative
// Leuchtdichte und Kontrastverhältnis nach WCAG 2.1, Farbabstand ΔE2000 in
// CIELAB (D65) für die Paarfarben (#653).

interface

uses
  System.SysUtils;

type
  /// <summary>Farbe wie TColor: $00BBGGRR.</summary>
  TDpccColor = type Cardinal;

  TDpccHSL = record
    /// <summary>Farbton 0..360.</summary>
    H: Double;
    /// <summary>Sättigung 0..1.</summary>
    S: Double;
    /// <summary>Helligkeit 0..1.</summary>
    L: Double;
    class function FromColor(AColor: TDpccColor): TDpccHSL; static;
    function ToColor: TDpccColor;
  end;

  /// <summary>Farbe in CIELAB (D65).</summary>
  TDpccLab = record
    L: Double;
    A: Double;
    B: Double;
    class function Create(AL, AA, AB: Double): TDpccLab; static;
  end;

  TDpccColorMath = class
  public
    class function Rgb(ARed, AGreen, ABlue: Byte): TDpccColor; static;
    /// <summary>Aus "#RRGGBB"; EConvertError bei ungültiger Angabe.</summary>
    class function FromHex(const AHex: string): TDpccColor; static;
    class function ToHex(AColor: TDpccColor): string; static;
    class function Red(AColor: TDpccColor): Byte; static;
    class function Green(AColor: TDpccColor): Byte; static;
    class function Blue(AColor: TDpccColor): Byte; static;
    /// <summary>AFront mit Deckkraft AAlpha (0..1) über ABack, wie rgba() im Entwurf.</summary>
    class function Mix(AFront, ABack: TDpccColor; AAlpha: Double): TDpccColor; static;
    /// <summary>Helligkeit in HSL um AAmount (0..1) erhöhen.</summary>
    class function Lighten(AColor: TDpccColor; AAmount: Double): TDpccColor; static;
    class function Darken(AColor: TDpccColor; AAmount: Double): TDpccColor; static;
    /// <summary>Relative Leuchtdichte nach WCAG, 0 (schwarz) bis 1 (weiß).</summary>
    class function Luminance(AColor: TDpccColor): Double; static;
    /// <summary>Kontrastverhältnis nach WCAG, 1 bis 21.</summary>
    class function Contrast(A, B: TDpccColor): Double; static;
    /// <summary>Dunkle Fläche: Leuchtdichte unter der Mitte zwischen Schwarz und Weiß.</summary>
    class function IsDark(AColor: TDpccColor): Boolean; static;
    /// <summary>sRGB nach CIELAB (D65).</summary>
    class function ToLab(AColor: TDpccColor): TDpccLab; static;
    /// <summary>Farbabstand nach CIEDE2000 (kL = kC = kH = 1).</summary>
    class function DeltaE2000(const A, B: TDpccLab): Double; overload; static;
    class function DeltaE2000(A, B: TDpccColor): Double; overload; static;
  end;

implementation

uses
  System.Math;

{ TDpccHSL }

class function TDpccHSL.FromColor(AColor: TDpccColor): TDpccHSL;
var
  R, G, B, mMaxValue, mMinValue, mDelta: Double;
begin
  R := TDpccColorMath.Red(AColor) / 255;
  G := TDpccColorMath.Green(AColor) / 255;
  B := TDpccColorMath.Blue(AColor) / 255;
  mMaxValue := Max(R, Max(G, B));
  mMinValue := Min(R, Min(G, B));
  mDelta := mMaxValue - mMinValue;
  Result.L := (mMaxValue + mMinValue) / 2;
  if mDelta = 0 then
  begin
    Result.H := 0;
    Result.S := 0;
    Exit;
  end;
  Result.S := mDelta / (1 - Abs(2 * Result.L - 1));
  if mMaxValue = R then
  begin
    Result.H := 60 * FMod((G - B) / mDelta, 6);
  end
  else if mMaxValue = G then
  begin
    Result.H := 60 * ((B - R) / mDelta + 2);
  end
  else
  begin
    Result.H := 60 * ((R - G) / mDelta + 4);
  end;
  if Result.H < 0 then
  begin
    Result.H := Result.H + 360;
  end;
end;

function TDpccHSL.ToColor: TDpccColor;
var
  C, X, M, R, G, B, mHue: Double;
begin
  C := (1 - Abs(2 * EnsureRange(L, 0, 1) - 1)) * EnsureRange(S, 0, 1);
  mHue := FMod(H, 360);
  if mHue < 0 then
  begin
    mHue := mHue + 360;
  end;
  X := C * (1 - Abs(FMod(mHue / 60, 2) - 1));
  M := EnsureRange(L, 0, 1) - C / 2;
  case Trunc(mHue / 60) of
    0: begin R := C; G := X; B := 0; end;
    1: begin R := X; G := C; B := 0; end;
    2: begin R := 0; G := C; B := X; end;
    3: begin R := 0; G := X; B := C; end;
    4: begin R := X; G := 0; B := C; end;
  else
    R := C; G := 0; B := X;
  end;
  Result := TDpccColorMath.Rgb(Round((R + M) * 255), Round((G + M) * 255), Round((B + M) * 255));
end;

{ TDpccColorMath }

class function TDpccColorMath.Rgb(ARed, AGreen, ABlue: Byte): TDpccColor;
begin
  Result := TDpccColor(ARed or (AGreen shl 8) or (ABlue shl 16));
end;

class function TDpccColorMath.FromHex(const AHex: string): TDpccColor;
var
  mValue: Integer;
begin
  if (Length(AHex) <> 7) or (AHex[1] <> '#') or not TryStrToInt('$' + Copy(AHex, 2, 6), mValue) then
  begin
    raise EConvertError.CreateFmt('Ungültige Farbe "%s"', [AHex]);
  end;
  Result := Rgb((mValue shr 16) and $FF, (mValue shr 8) and $FF, mValue and $FF);
end;

class function TDpccColorMath.ToHex(AColor: TDpccColor): string;
begin
  Result := Format('#%.2X%.2X%.2X', [Red(AColor), Green(AColor), Blue(AColor)]);
end;

class function TDpccColorMath.Red(AColor: TDpccColor): Byte;
begin
  Result := AColor and $FF;
end;

class function TDpccColorMath.Green(AColor: TDpccColor): Byte;
begin
  Result := (AColor shr 8) and $FF;
end;

class function TDpccColorMath.Blue(AColor: TDpccColor): Byte;
begin
  Result := (AColor shr 16) and $FF;
end;

class function TDpccColorMath.Mix(AFront, ABack: TDpccColor; AAlpha: Double): TDpccColor;

  function Channel(AFrontValue, ABackValue: Byte): Byte;
  begin
    Result := Round(AFrontValue * AAlpha + ABackValue * (1 - AAlpha));
  end;

begin
  AAlpha := EnsureRange(AAlpha, 0, 1);
  Result := Rgb(Channel(Red(AFront), Red(ABack)), Channel(Green(AFront), Green(ABack)),
    Channel(Blue(AFront), Blue(ABack)));
end;

class function TDpccColorMath.Lighten(AColor: TDpccColor; AAmount: Double): TDpccColor;
var
  mHSL: TDpccHSL;
begin
  mHSL := TDpccHSL.FromColor(AColor);
  mHSL.L := EnsureRange(mHSL.L + AAmount, 0, 1);
  Result := mHSL.ToColor;
end;

class function TDpccColorMath.Darken(AColor: TDpccColor; AAmount: Double): TDpccColor;
begin
  Result := Lighten(AColor, -AAmount);
end;

class function TDpccColorMath.Luminance(AColor: TDpccColor): Double;

  function Linear(AValue: Byte): Double;
  var
    mValue: Double;
  begin
    mValue := AValue / 255;
    if mValue <= 0.04045 then
    begin
      Result := mValue / 12.92;
    end
    else
    begin
      Result := Power((mValue + 0.055) / 1.055, 2.4);
    end;
  end;

begin
  Result := 0.2126 * Linear(Red(AColor)) + 0.7152 * Linear(Green(AColor)) + 0.0722 * Linear(Blue(AColor));
end;

class function TDpccColorMath.Contrast(A, B: TDpccColor): Double;
var
  mLumA, mLumB: Double;
begin
  mLumA := Luminance(A);
  mLumB := Luminance(B);
  Result := (Max(mLumA, mLumB) + 0.05) / (Min(mLumA, mLumB) + 0.05);
end;

class function TDpccLab.Create(AL, AA, AB: Double): TDpccLab;
begin
  Result.L := AL;
  Result.A := AA;
  Result.B := AB;
end;

class function TDpccColorMath.ToLab(AColor: TDpccColor): TDpccLab;

  function Linear(AValue: Byte): Double;
  var
    mValue: Double;
  begin
    mValue := AValue / 255;
    if mValue <= 0.04045 then
    begin
      Result := mValue / 12.92;
    end
    else
    begin
      Result := Power((mValue + 0.055) / 1.055, 2.4);
    end;
  end;

  function F(AValue: Double): Double;
  begin
    if AValue > 216 / 24389 then
    begin
      Result := Power(AValue, 1 / 3);
    end
    else
    begin
      Result := (24389 / 27 * AValue + 16) / 116;
    end;
  end;

var
  R, G, B, X, Y, Z: Double;
begin
  R := Linear(Red(AColor));
  G := Linear(Green(AColor));
  B := Linear(Blue(AColor));
  X := F((0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047);
  Y := F(0.2126 * R + 0.7152 * G + 0.0722 * B);
  Z := F((0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883);
  Result := TDpccLab.Create(116 * Y - 16, 500 * (X - Y), 200 * (Y - Z));
end;

const
  /// <summary>25^7 für CIEDE2000.</summary>
  cPow25 = 6103515625.0;

type
  /// <summary>Chroma C' und Farbton h' (Grad) einer Farbe in CIEDE2000.</summary>
  TPrimedLab = record
    C: Double;
    H: Double;
  end;

  /// <summary>Gewichte S_L, S_C, S_H und Drehterm R_T von CIEDE2000.</summary>
  TDeltaWeights = record
    Sl: Double;
    Sc: Double;
    Sh: Double;
    Rt: Double;
  end;

function HueAngle(AB, AA: Double): Double;
begin
  Result := 0;
  if (AA <> 0) or (AB <> 0) then
  begin
    Result := RadToDeg(ArcTan2(AB, AA));
    if Result < 0 then
    begin
      Result := Result + 360;
    end;
  end;
end;

/// <summary>C' und h' von AColor; der Faktor G hängt von beiden Farben (AFirst, ASecond) ab.</summary>
function PrimedLab(const AColor, AFirst, ASecond: TDpccLab): TPrimedLab;
var
  mCMean, mG, mA: Double;
begin
  mCMean := (Sqrt(Sqr(AFirst.A) + Sqr(AFirst.B)) + Sqrt(Sqr(ASecond.A) + Sqr(ASecond.B))) / 2;
  mG := 0.5 * (1 - Sqrt(Power(mCMean, 7) / (Power(mCMean, 7) + cPow25)));
  mA := (1 + mG) * AColor.A;
  Result.C := Sqrt(Sqr(mA) + Sqr(AColor.B));
  Result.H := HueAngle(AColor.B, mA);
end;

function HueDelta(const AFirst, ASecond: TPrimedLab): Double;
begin
  Result := 0;
  if AFirst.C * ASecond.C <> 0 then
  begin
    Result := ASecond.H - AFirst.H;
    if Result > 180 then
    begin
      Result := Result - 360;
    end
    else if Result < -180 then
    begin
      Result := Result + 360;
    end;
  end;
end;

function MeanHue(const AFirst, ASecond: TPrimedLab): Double;
begin
  if AFirst.C * ASecond.C = 0 then
  begin
    Result := AFirst.H + ASecond.H;
  end
  else if Abs(AFirst.H - ASecond.H) <= 180 then
  begin
    Result := (AFirst.H + ASecond.H) / 2;
  end
  else if AFirst.H + ASecond.H < 360 then
  begin
    Result := (AFirst.H + ASecond.H + 360) / 2;
  end
  else
  begin
    Result := (AFirst.H + ASecond.H - 360) / 2;
  end;
end;

function DeltaWeights(ALMean, ACpMean, AHpMean: Double): TDeltaWeights;
var
  mT, mDTheta, mRc: Double;
begin
  mT := 1 - 0.17 * Cos(DegToRad(AHpMean - 30)) + 0.24 * Cos(DegToRad(2 * AHpMean)) +
    0.32 * Cos(DegToRad(3 * AHpMean + 6)) - 0.20 * Cos(DegToRad(4 * AHpMean - 63));
  mDTheta := 30 * Exp(-Sqr((AHpMean - 275) / 25));
  mRc := 2 * Sqrt(Power(ACpMean, 7) / (Power(ACpMean, 7) + cPow25));
  Result.Sl := 1 + 0.015 * Sqr(ALMean - 50) / Sqrt(20 + Sqr(ALMean - 50));
  Result.Sc := 1 + 0.045 * ACpMean;
  Result.Sh := 1 + 0.015 * ACpMean * mT;
  Result.Rt := -Sin(DegToRad(2 * mDTheta)) * mRc;
end;
class function TDpccColorMath.DeltaE2000(const A, B: TDpccLab): Double;
var
  mFirst, mSecond: TPrimedLab;
  mDHp, mDCp: Double;
  mWeights: TDeltaWeights;
begin
  mFirst := PrimedLab(A, A, B);
  mSecond := PrimedLab(B, A, B);
  mDCp := mSecond.C - mFirst.C;
  mDHp := 2 * Sqrt(mFirst.C * mSecond.C) * Sin(DegToRad(HueDelta(mFirst, mSecond) / 2));
  mWeights := DeltaWeights((A.L + B.L) / 2, (mFirst.C + mSecond.C) / 2, MeanHue(mFirst, mSecond));
  Result := Sqrt(Sqr((B.L - A.L) / mWeights.Sl) + Sqr(mDCp / mWeights.Sc) + Sqr(mDHp / mWeights.Sh) +
    mWeights.Rt * (mDCp / mWeights.Sc) * (mDHp / mWeights.Sh));
end;

class function TDpccColorMath.DeltaE2000(A, B: TDpccColor): Double;
begin
  Result := DeltaE2000(ToLab(A), ToLab(B));
end;

class function TDpccColorMath.IsDark(AColor: TDpccColor): Boolean;
begin
  // 0,18 ist die Leuchtdichte, bei der Schwarz und Weiß gleich gut kontrastieren.
  Result := Luminance(AColor) < 0.18;
end;

end.
