unit Shell.LspServer.StdStreams;

// Host-Rolle Shell, nur in dpcc.LspServer.exe: Standardein- und -ausgabe als Streams für das Protokoll (aus dem
// früheren Server-Prozess, vormals dpcc.Windows.Console.StdStreams). Die Streams arbeiten direkt auf den Handles, ohne
// Textmodus und ohne Pufferung der RTL, damit die Bytezählung des Protokolls stimmt. ReserveOutputForProtocol hält
// stdout für das Protokoll frei: Write/Writeln und Bibliotheken, die GetStdHandle benutzen, landen danach auf
// stderr.

interface

uses
  System.Classes;

type
  TLspStdStreams = record
  public
    /// <summary>Stream auf stdin. Der Aufrufer gibt ihn frei; das Handle bleibt offen.</summary>
    class function CreateInput: TStream; static;
    /// <summary>Stream auf das echte stdout; danach erreicht nur noch er stdout (siehe Kopf).</summary>
    class function ReserveOutputForProtocol: TStream; static;
    /// <summary>Text auf stderr (nur für --help und --version, nie im Betrieb).</summary>
    class procedure WriteError(const AText: string); static;
    /// <summary>Text auf stdout (nur für --help und --version, nie im Betrieb).</summary>
    class procedure WriteOutput(const AText: string); static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils;

function CreateHandleStream(AStdHandle: DWORD; const AName: string): TStream;
var
  mHandle: THandle;
begin
  mHandle := GetStdHandle(AStdHandle);
  if (mHandle = 0) or (mHandle = INVALID_HANDLE_VALUE) then
  begin
    raise EStreamError.CreateFmt('Kein gültiges Handle für %s', [AName]);
  end;
  Result := THandleStream.Create(mHandle);
end;

procedure WriteTo(AStdHandle: DWORD; const AText: string);
var
  mHandle: THandle;
  mBytes: TBytes;
  mWritten: DWORD;
begin
  mHandle := GetStdHandle(AStdHandle);
  if (mHandle = 0) or (mHandle = INVALID_HANDLE_VALUE) then
  begin
    Exit;
  end;
  mBytes := TEncoding.UTF8.GetBytes(AText + sLineBreak);
  if Length(mBytes) > 0 then
  begin
    WriteFile(mHandle, mBytes[0], Length(mBytes), mWritten, nil);
  end;
end;

{ TLspStdStreams }

class function TLspStdStreams.CreateInput: TStream;
begin
  Result := CreateHandleStream(STD_INPUT_HANDLE, 'stdin');
end;

class function TLspStdStreams.ReserveOutputForProtocol: TStream;
var
  mErrorHandle: THandle;
begin
  Result := CreateHandleStream(STD_OUTPUT_HANDLE, 'stdout');
  mErrorHandle := GetStdHandle(STD_ERROR_HANDLE);
  if (mErrorHandle <> 0) and (mErrorHandle <> INVALID_HANDLE_VALUE) then
  begin
    SetStdHandle(STD_OUTPUT_HANDLE, mErrorHandle);
    if TTextRec(Output).Mode = fmOutput then
    begin
      Flush(Output);
    end;
    TTextRec(Output).Handle := mErrorHandle;
  end;
  // "Runtime error ..." nicht auf die Konsole schreiben.
  {$WARN SYMBOL_PLATFORM OFF}
  NoErrMsg := True;
  {$WARN SYMBOL_PLATFORM DEFAULT}
end;

class procedure TLspStdStreams.WriteError(const AText: string);
begin
  WriteTo(STD_ERROR_HANDLE, AText);
end;

class procedure TLspStdStreams.WriteOutput(const AText: string);
begin
  WriteTo(STD_OUTPUT_HANDLE, AText);
end;

end.
