unit dpcc.Core.Files.Format;

// Kodierung und Zeilenende einer Datei (#591, Daten wie #121), ohne Open
// Tools API: Erkennen aus den Bytes auf der Platte, Text für die Zeile
// „Datei“ des dpcc-Statusfelds und Umwandeln in ein anderes Format
// (UTF-8 mit/ohne BOM, ANSI; CRLF/LF).
// Erkennung: BOM zuerst (UTF-8, UTF-16 LE/BE); ohne BOM gültiges UTF-8 als
// UTF-8 ohne BOM (reines ASCII ebenso), sonst ANSI. Zeilenenden: nur CRLF,
// nur LF, nur CR, gemischt oder keine. Die Prüfungen kommen aus dpcc.Text
//.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TDpccFileEncoding = (Utf8, Utf8Bom, Ansi, Utf16LE, Utf16BE);
  TDpccLineBreak = (None, CRLF, LF, CR, Mixed);
{$SCOPEDENUMS OFF}

  TDpccFileFormat = record
    Encoding: TDpccFileEncoding;
    LineBreak: TDpccLineBreak;
    class function Create(AEncoding: TDpccFileEncoding; ALineBreak: TDpccLineBreak): TDpccFileFormat; static;
    /// <summary>„UTF-8 ohne BOM, LF“.</summary>
    function Text: string;
    function Equals(const AOther: TDpccFileFormat): Boolean;
  end;

  TDpccFileFormats = class
  public
    /// <summary>Format der Bytes einer Datei.</summary>
    class function Detect(const ABytes: TBytes): TDpccFileFormat; static;
    /// <summary>Zeilenenden eines Texts.</summary>
    class function LineBreakOf(const AText: string): TDpccLineBreak; static;
    /// <summary>True, wenn ABytes ab AStart gültiges UTF-8 sind.</summary>
    class function IsUtf8(const ABytes: TBytes; AStart: Integer): Boolean; static;
    /// <summary>Text der Bytes nach AEncoding, ohne BOM.</summary>
    class function Decode(const ABytes: TBytes; AEncoding: TDpccFileEncoding): string; static;
    /// <summary>Bytes für AText im Format ATarget: Zeilenenden vereinheitlicht (None, Mixed: unverändert),
    /// BOM nach Kodierung.</summary>
    class function Encode(const AText: string; const ATarget: TDpccFileFormat): TBytes; static;
    /// <summary>ABytes in ATarget umwandeln; Kodierung und Zeilenenden der Quelle werden erkannt.</summary>
    class function Convert(const ABytes: TBytes; const ATarget: TDpccFileFormat): TBytes; static;
    /// <summary>True, wenn ABytes schon ATarget entsprechen. Reines ASCII ohne BOM gilt als UTF-8 ohne BOM
    /// und als ANSI; eine Datei ohne Zeilenende passt zu jedem Zeilenende.</summary>
    class function Satisfies(const ABytes: TBytes; const ATarget: TDpccFileFormat): Boolean; static;
    /// <summary>True, wenn ABytes nur 7-Bit-Zeichen enthalten.</summary>
    class function IsAscii(const ABytes: TBytes): Boolean; static;
    /// <summary>Zeichen von AText, die ANSI (Codepage des Systems) nicht darstellen kann.</summary>
    class function AnsiLosses(const AText: string): Integer; static;
    /// <summary>Zeilenenden auf ABreak vereinheitlichen (CRLF, LF oder CR; sonst unverändert).</summary>
    class function NormalizeLineBreaks(const AText: string; ABreak: TDpccLineBreak): string; static;
    /// <summary>Wählbare Ziele im Fenster: UTF-8 mit BOM, UTF-8 ohne BOM und ANSI, je mit CRLF und LF.</summary>
    class function Targets: TArray<TDpccFileFormat>; static;
    class function EncodingText(AEncoding: TDpccFileEncoding): string; static;
    class function LineBreakText(ALineBreak: TDpccLineBreak): string; static;
  end;

implementation

uses
  dpcc.Text.Lines,
  dpcc.Text.Encoding,
  dpcc.Core.Localization.Language;

{ TDpccFileFormat }

class function TDpccFileFormat.Create(AEncoding: TDpccFileEncoding; ALineBreak: TDpccLineBreak): TDpccFileFormat;
begin
  Result.Encoding := AEncoding;
  Result.LineBreak := ALineBreak;
end;

function TDpccFileFormat.Text: string;
begin
  Result := TDpccFileFormats.EncodingText(Encoding) + ', ' + TDpccFileFormats.LineBreakText(LineBreak);
end;

function TDpccFileFormat.Equals(const AOther: TDpccFileFormat): Boolean;
begin
  Result := (Encoding = AOther.Encoding) and (LineBreak = AOther.LineBreak);
end;

{ TDpccFileFormats }

class function TDpccFileFormats.EncodingText(AEncoding: TDpccFileEncoding): string;
const
  cNames: array[TDpccLanguage, TDpccFileEncoding] of string = (
    ('UTF-8 ohne BOM', 'UTF-8 mit BOM', 'ANSI', 'UTF-16 LE', 'UTF-16 BE'),
    ('UTF-8 without BOM', 'UTF-8 with BOM', 'ANSI', 'UTF-16 LE', 'UTF-16 BE'));
begin
  Result := cNames[TDpccTextLanguage.Current, AEncoding];
end;

class function TDpccFileFormats.LineBreakText(ALineBreak: TDpccLineBreak): string;
const
  cNames: array[TDpccLanguage, TDpccLineBreak] of string = (
    ('ohne Zeilenende', 'CRLF', 'LF', 'CR', 'gemischte Zeilenenden'),
    ('no line break', 'CRLF', 'LF', 'CR', 'mixed line breaks'));
begin
  Result := cNames[TDpccTextLanguage.Current, ALineBreak];
end;

class function TDpccFileFormats.IsUtf8(const ABytes: TBytes; AStart: Integer): Boolean;
begin
  Result := TTextEncodingProbe.IsValidUtf8(ABytes, AStart);
end;

class function TDpccFileFormats.LineBreakOf(const AText: string): TDpccLineBreak;
begin
  case TTextLines.KindOf(AText) of
    TTextLineBreak.CRLF:
      Result := TDpccLineBreak.CRLF;
    TTextLineBreak.LF:
      Result := TDpccLineBreak.LF;
    TTextLineBreak.CR:
      Result := TDpccLineBreak.CR;
    TTextLineBreak.Mixed:
      Result := TDpccLineBreak.Mixed;
  else
    Result := TDpccLineBreak.None;
  end;
end;

class function TDpccFileFormats.Detect(const ABytes: TBytes): TDpccFileFormat;
begin
  case TTextEncodingProbe.BomOf(ABytes) of
    TTextBom.Utf8:
      Result.Encoding := TDpccFileEncoding.Utf8Bom;
    TTextBom.Utf16LE:
      Result.Encoding := TDpccFileEncoding.Utf16LE;
    TTextBom.Utf16BE:
      Result.Encoding := TDpccFileEncoding.Utf16BE;
  else
    Result.Encoding := TDpccFileEncoding.Ansi;
  end;
  if (Result.Encoding = TDpccFileEncoding.Ansi) and IsUtf8(ABytes, 0) then
  begin
    Result.Encoding := TDpccFileEncoding.Utf8;
  end;
  Result.LineBreak := LineBreakOf(Decode(ABytes, Result.Encoding));
end;

class function TDpccFileFormats.Decode(const ABytes: TBytes; AEncoding: TDpccFileEncoding): string;
begin
  case AEncoding of
    TDpccFileEncoding.Utf8Bom:
      if Length(ABytes) >= 3 then
      begin
        Result := TEncoding.UTF8.GetString(ABytes, 3, Length(ABytes) - 3);
      end
      else
      begin
        Result := '';
      end;
    TDpccFileEncoding.Utf16LE:
      if Length(ABytes) >= 2 then
      begin
        Result := TEncoding.Unicode.GetString(ABytes, 2, Length(ABytes) - 2);
      end
      else
      begin
        Result := '';
      end;
    TDpccFileEncoding.Utf16BE:
      if Length(ABytes) >= 2 then
      begin
        Result := TEncoding.BigEndianUnicode.GetString(ABytes, 2, Length(ABytes) - 2);
      end
      else
      begin
        Result := '';
      end;
    TDpccFileEncoding.Ansi:
      Result := TEncoding.ANSI.GetString(ABytes);
  else
    Result := TEncoding.UTF8.GetString(ABytes);
  end;
end;

class function TDpccFileFormats.NormalizeLineBreaks(const AText: string; ABreak: TDpccLineBreak): string;
begin
  case ABreak of
    TDpccLineBreak.CRLF:
      Result := TTextLines.NormalizeLineBreaks(AText, #13#10);
    TDpccLineBreak.LF:
      Result := TTextLines.NormalizeLineBreaks(AText, #10);
    TDpccLineBreak.CR:
      Result := TTextLines.NormalizeLineBreaks(AText, #13);
  else
    Result := AText;
  end;
end;

class function TDpccFileFormats.Encode(const AText: string; const ATarget: TDpccFileFormat): TBytes;
var
  mText: string;
begin
  mText := NormalizeLineBreaks(AText, ATarget.LineBreak);
  case ATarget.Encoding of
    TDpccFileEncoding.Utf8Bom:
      Result := TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(mText);
    TDpccFileEncoding.Ansi:
      Result := TEncoding.ANSI.GetBytes(mText);
    TDpccFileEncoding.Utf16LE:
      Result := TEncoding.Unicode.GetPreamble + TEncoding.Unicode.GetBytes(mText);
    TDpccFileEncoding.Utf16BE:
      Result := TEncoding.BigEndianUnicode.GetPreamble + TEncoding.BigEndianUnicode.GetBytes(mText);
  else
    Result := TEncoding.UTF8.GetBytes(mText);
  end;
end;

class function TDpccFileFormats.Convert(const ABytes: TBytes; const ATarget: TDpccFileFormat): TBytes;
begin
  Result := Encode(Decode(ABytes, Detect(ABytes).Encoding), ATarget);
end;

class function TDpccFileFormats.IsAscii(const ABytes: TBytes): Boolean;
begin
  Result := TTextEncodingProbe.IsAscii(ABytes);
end;

class function TDpccFileFormats.Satisfies(const ABytes: TBytes; const ATarget: TDpccFileFormat): Boolean;
var
  mActual: TDpccFileFormat;
  mSameEncoding: Boolean;
begin
  mActual := Detect(ABytes);
  mSameEncoding := mActual.Encoding = ATarget.Encoding;
  if not mSameEncoding and (mActual.Encoding = TDpccFileEncoding.Utf8) and
    (ATarget.Encoding = TDpccFileEncoding.Ansi) then
  begin
    mSameEncoding := IsAscii(ABytes);
  end;
  Result := mSameEncoding and ((mActual.LineBreak = ATarget.LineBreak) or (mActual.LineBreak = TDpccLineBreak.None));
end;

class function TDpccFileFormats.AnsiLosses(const AText: string): Integer;
var
  mBack: string;
  mIndex: Integer;
begin
  mBack := TEncoding.ANSI.GetString(TEncoding.ANSI.GetBytes(AText));
  Result := Abs(Length(mBack) - Length(AText));
  for mIndex := 1 to Length(AText) do
  begin
    if (mIndex <= Length(mBack)) and (mBack[mIndex] <> AText[mIndex]) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TDpccFileFormats.Targets: TArray<TDpccFileFormat>;
begin
  Result := [TDpccFileFormat.Create(TDpccFileEncoding.Utf8Bom, TDpccLineBreak.CRLF),
    TDpccFileFormat.Create(TDpccFileEncoding.Utf8Bom, TDpccLineBreak.LF),
    TDpccFileFormat.Create(TDpccFileEncoding.Utf8, TDpccLineBreak.CRLF),
    TDpccFileFormat.Create(TDpccFileEncoding.Utf8, TDpccLineBreak.LF),
    TDpccFileFormat.Create(TDpccFileEncoding.Ansi, TDpccLineBreak.CRLF),
    TDpccFileFormat.Create(TDpccFileEncoding.Ansi, TDpccLineBreak.LF)];
end;

end.
