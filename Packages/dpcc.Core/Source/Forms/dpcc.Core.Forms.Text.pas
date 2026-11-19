unit dpcc.Core.Forms.Text;

// Formulartext aus dem Designer (#402), Teil ohne VCL und Open Tools API:
// Bei offenem Formular liegt der aktuelle Stand im Designer, nicht in der
// .dfm auf der Platte. Das Plugin streamt die Wurzelkomponente wie beim
// Speichern (TWriter.WriteDescendent ohne Vorfahr) und wandelt das Ergebnis
// mit ObjectBinaryToText in DFM-Text. Methodennamen von Ereignissen kennt im
// Designer nur der Designer; sie kommen über AMethodName.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TDpccFormText = class
  public
    /// <summary>DFM-Text zu ARoot. AMethodName liefert den Namen eines Ereignis-Handlers ('' = unbekannt);
    /// nil: Namen aus den published-Methoden der Wurzel.</summary>
    class function Write(ARoot: TComponent; const AMethodName: TFunc<TMethod, string>): string; static;
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
var
  mBinary: TMemoryStream;
  mText: TStringStream;
  mWriter: TWriter;
  mNamer: TMethodNamer;
begin
  mBinary := TMemoryStream.Create;
  mText := TStringStream.Create('', TEncoding.UTF8);
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
    mBinary.Position := 0;
    ObjectBinaryToText(mBinary, mText);
    Result := mText.DataString;
  finally
    mNamer.Free;
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
