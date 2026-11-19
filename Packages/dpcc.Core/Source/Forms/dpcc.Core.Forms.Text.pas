unit dpcc.Core.Forms.Text;

// Formulartext aus dem Designer (#402), Teil ohne VCL und Open Tools API:
// Bei offenem Formular liegt der aktuelle Stand im Designer, nicht in der
// .dfm auf der Platte. Das Plugin streamt die Wurzelkomponente wie beim
// Speichern (TWriter.WriteDescendent ohne Vorfahr) und wandelt das Ergebnis
// mit ObjectBinaryToText in DFM-Text. Methodennamen von Ereignissen kennt im
// Designer nur der Designer; sie kommen über AMethodName.
// Zwei Schritte (IDE hängt nicht beim Laden von Formularen): WriteBinary fasst
// die Komponenten an und gehört in den Hauptthread; die Methodennamen stehen
// danach schon im Binärstrom. BinaryToText (bei Bildlisten und Picture.Data der
// teure Teil) braucht nur die Bytes und läuft in jedem Thread.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TDpccFormText = class
  public
    /// <summary>DFM-Text zu ARoot (WriteBinary und BinaryToText nacheinander). AMethodName liefert den Namen eines
    /// Ereignis-Handlers ('' = unbekannt); nil: Namen aus den published-Methoden der Wurzel.</summary>
    class function Write(ARoot: TComponent; const AMethodName: TFunc<TMethod, string>): string; static;
    /// <summary>ARoot binär wie beim Speichern (TWriter.WriteDescendent ohne Vorfahr), Methodennamen über
    /// AMethodName wie bei Write. Fasst die Komponenten an: nur im Hauptthread.</summary>
    class function WriteBinary(ARoot: TComponent; const AMethodName: TFunc<TMethod, string>): TBytes; static;
    /// <summary>DFM-Text zu einem Binärstrom aus WriteBinary; '' bei leerem Strom. Ohne Komponenten, threadsicher.
    /// </summary>
    class function BinaryToText(const ABinary: TBytes): string; static;
    /// <summary>Formulardatei eines Designers aus seinen Moduldateien (IDesigner.ModuleFileNames): AFormFileName,
    /// wenn es eine .dfm bzw. .fmx ist; sonst neben AImplFileName die .dfm, die .fmx nur, wenn es nur diese gibt
    /// (AExists prüft, nil = keine vorhanden). '' ohne beides: Dann ist das Formular keiner Datei sicher zugeordnet.
    /// </summary>
    class function FormFileOf(const AImplFileName, AFormFileName: string;
      const AExists: TFunc<string, Boolean>): string; static;
  end;

implementation

type
  TMethodNamer = class
  private
    FMethodName: TFunc<TMethod, string>;
  public
    procedure FindMethodName(Writer: TWriter; AMethod: TMethod; var AName: string);
  end;

procedure TMethodNamer.FindMethodName(Writer: TWriter; AMethod: TMethod; var AName: string);
begin
  if Assigned(FMethodName) then
  begin
    AName := FMethodName(AMethod);
  end;
end;

class function TDpccFormText.Write(ARoot: TComponent; const AMethodName: TFunc<TMethod, string>): string;
begin
  Result := BinaryToText(WriteBinary(ARoot, AMethodName));
end;

class function TDpccFormText.WriteBinary(ARoot: TComponent; const AMethodName: TFunc<TMethod, string>): TBytes;
var
  mBinary: TMemoryStream;
  mWriter: TWriter;
  mNamer: TMethodNamer;
begin
  Result := nil;
  mBinary := TMemoryStream.Create;
  mNamer := TMethodNamer.Create;
  try
    mNamer.FMethodName := AMethodName;
    mWriter := TWriter.Create(mBinary, 4096);
    try
      if Assigned(AMethodName) then
      begin
        mWriter.OnFindMethodName := mNamer.FindMethodName;
      end;
      mWriter.WriteDescendent(ARoot, nil);
    finally
      // Erst das Freigeben schreibt den Puffer in den Stream.
      mWriter.Free;
    end;
    SetLength(Result, mBinary.Size);
    if mBinary.Size > 0 then
    begin
      Move(mBinary.Memory^, Result[0], mBinary.Size);
    end;
  finally
    mNamer.Free;
    mBinary.Free;
  end;
end;

class function TDpccFormText.BinaryToText(const ABinary: TBytes): string;
var
  mBinary: TBytesStream;
  mText: TStringStream;
begin
  Result := '';
  if Length(ABinary) = 0 then
  begin
    Exit;
  end;
  // TBytesStream liest das Feld ohne Kopie; es wird nur gelesen (andere Threads dürfen es zugleich lesen).
  mBinary := TBytesStream.Create(ABinary);
  mText := TStringStream.Create('', TEncoding.UTF8);
  try
    ObjectBinaryToText(mBinary, mText);
    Result := mText.DataString;
  finally
    mText.Free;
    mBinary.Free;
  end;
end;

class function TDpccFormText.FormFileOf(const AImplFileName, AFormFileName: string;
  const AExists: TFunc<string, Boolean>): string;
var
  mFmx, mDfm: string;
begin
  if SameText(ExtractFileExt(AFormFileName), '.dfm') or SameText(ExtractFileExt(AFormFileName), '.fmx') then
  begin
    Exit(AFormFileName);
  end;
  if AImplFileName = '' then
  begin
    Exit('');
  end;
  mDfm := ChangeFileExt(AImplFileName, '.dfm');
  mFmx := ChangeFileExt(AImplFileName, '.fmx');
  if Assigned(AExists) and AExists(mFmx) and not AExists(mDfm) then
  begin
    Result := mFmx;
  end
  else
  begin
    Result := mDfm;
  end;
end;

end.
