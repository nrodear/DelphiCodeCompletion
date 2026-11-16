unit dpcc.Windows.Documents.SharedRead;

// Platform-Feature "Documents", Root: Dateien lesen, ohne das atomare Ersetzen
// zu blockieren. Die RTL teilt beim Lesen nie FILE_SHARE_DELETE:
// TFile.ReadAllBytes teilt nur Lesen, TFileStream mit fmShareDenyNone Lesen
// und Schreiben. Solange der Server eine Datei so offen hat, kann das Plugin
// sie nicht durch ihre neue Fassung ersetzen (settings.json, dpcc.json, Units
// nach dem Umbenennen), und ein zweiter Server nicht den Index-Cache.
// Install trägt ReadAllBytes in TFileEncoding.Reader ein; alle Leser über
// TFileEncoding teilen dann auch Löschen.
//
// Dieselbe Lesart hat das Plugin in TDpccTextFile.ReadAllBytes; es bindet
// dpcc.Windows nicht ein.
//
// Index-Cache Format 34 (Speicher-Optimierung Phase 3): Install trägt auch einen
// Opener in TIndexBlockFiles ein. Er hält ein Handle auf die Cache-Datei, das
// Lesen, Schreiben und Löschen teilt, und liest einzelne Blöcke mit ReadFile
// an ihrem Offset (kein durchgehendes Mapping im 32-Bit-Prozess). Ersetzt ein
// Schreiber die Datei (TFile.Replace), liest das Handle den alten Stand weiter,
// zu dem das Verzeichnis des Lesers passt; den neuen Stand liest der nächste
// Aufbau über ein neues Handle.

interface

uses
  System.SysUtils,
  dpcc.Common.Index.Contract;

type
  TWindowsSharedRead = record
  public
    /// <summary>Liest die ganze Datei und teilt Lesen, Schreiben und Löschen. Ersetzt ein anderer die Datei
    /// währenddessen, liest es den alten Stand zu Ende. EFOpenError, wenn sie fehlt oder gesperrt ist;
    /// EReadError bei einem Lesefehler.</summary>
    class function ReadAllBytes(const AFileName: string): TBytes; static;
    /// <summary>Trägt ReadAllBytes in TFileEncoding.Reader ein.</summary>
    class procedure Install; static;
    /// <summary>Nimmt es wieder heraus.</summary>
    class procedure Uninstall; static;
    /// <summary>Blockleser über AFileName: hält das Handle (teilt Lesen, Schreiben und Löschen) und liest mit
    /// ReadFile am Offset; nil, wenn die Datei fehlt oder gesperrt ist.</summary>
    class function OpenBlocks(const AFileName: string): IIndexBlockReader; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.RTLConsts,
  dpcc.Common.Documents.FileEncoding;

class function TWindowsSharedRead.ReadAllBytes(const AFileName: string): TBytes;
var
  mHandle: THandle;
  mSize: Int64;
  mTotal, mCount: Integer;
begin
  mHandle := CreateFile(PChar(AFileName), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_SEQUENTIAL_SCAN, 0);
  if mHandle = INVALID_HANDLE_VALUE then
  begin
    raise EFOpenError.CreateResFmt(@SFOpenErrorEx, [ExpandFileName(AFileName), SysErrorMessage(GetLastError)]);
  end;
  try
    mSize := FileSeek(mHandle, Int64(0), 2);
    if (mSize < 0) or (mSize > MaxInt) or (FileSeek(mHandle, Int64(0), 0) <> 0) then
    begin
      raise EReadError.CreateRes(@SReadError);
    end;
    SetLength(Result, Integer(mSize));
    mTotal := 0;
    while mTotal < Length(Result) do
    begin
      mCount := FileRead(mHandle, Result[mTotal], Length(Result) - mTotal);
      if mCount < 0 then
      begin
        raise EReadError.CreateRes(@SReadError);
      end;
      // Kürzer geworden (jemand schreibt an Ort und Stelle): lesen, was da ist.
      if mCount = 0 then
      begin
        Break;
      end;
      Inc(mTotal, mCount);
    end;
    SetLength(Result, mTotal);
  finally
    CloseHandle(mHandle);
  end;
end;

type
  /// <summary>Blockleser mit gehaltenem Handle (Index-Cache Format 34).</summary>
  TWindowsBlockReader = class(TInterfacedObject, IIndexBlockReader)
  private
    FHandle: THandle;
    FSize: Int64;
    FStamp: Int64;
  public
    constructor Create(AHandle: THandle; ASize, AStamp: Int64);
    destructor Destroy; override;
    function Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
    function Size: Int64;
    function Stamp: Int64;
  end;

constructor TWindowsBlockReader.Create(AHandle: THandle; ASize, AStamp: Int64);
begin
  inherited Create;
  FHandle := AHandle;
  FSize := ASize;
  FStamp := AStamp;
end;

destructor TWindowsBlockReader.Destroy;
begin
  CloseHandle(FHandle);
  inherited;
end;

function TWindowsBlockReader.Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
var
  mOverlapped: TOverlapped;
  mDone: DWORD;
  mTotal: Integer;
  mAt: Int64;
begin
  ABytes := nil;
  if (AOffset < 0) or (ACount < 0) or (AOffset + ACount > FSize) then
  begin
    Exit(False);
  end;
  SetLength(ABytes, ACount);
  mTotal := 0;
  // ReadFile mit Offset: kein gemeinsamer Dateizeiger, mehrere Threads lesen ohne eigene Sperre.
  while mTotal < ACount do
  begin
    mAt := AOffset + mTotal;
    FillChar(mOverlapped, SizeOf(mOverlapped), 0);
    mOverlapped.Offset := DWORD(mAt);
    mOverlapped.OffsetHigh := DWORD(mAt shr 32);
    mDone := 0;
    if not ReadFile(FHandle, ABytes[mTotal], DWORD(ACount - mTotal), mDone, @mOverlapped) or (mDone = 0) then
    begin
      ABytes := nil;
      Exit(False);
    end;
    Inc(mTotal, Integer(mDone));
  end;
  Result := True;
end;

function TWindowsBlockReader.Size: Int64;
begin
  Result := FSize;
end;

function TWindowsBlockReader.Stamp: Int64;
begin
  Result := FStamp;
end;

class function TWindowsSharedRead.OpenBlocks(const AFileName: string): IIndexBlockReader;
var
  mHandle: THandle;
  mSize: Int64;
  mAge: TDateTime;
begin
  // Zeitstempel wie TDiskIndexFileSystem.FileStamp, vor dem Öffnen: Ersetzt ihn jemand dazwischen, gilt der Stand
  // als älter und der nächste Aufbau liest neu.
  if not FileAge(AFileName, mAge) then
  begin
    Exit(nil);
  end;
  mHandle := CreateFile(PChar(AFileName), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_RANDOM_ACCESS, 0);
  if mHandle = INVALID_HANDLE_VALUE then
  begin
    Exit(nil);
  end;
  if not GetFileSizeEx(mHandle, mSize) then
  begin
    CloseHandle(mHandle);
    Exit(nil);
  end;
  Result := TWindowsBlockReader.Create(mHandle, mSize, Round(mAge * MSecsPerDay));
end;

class procedure TWindowsSharedRead.Install;
begin
  TFileEncoding.Reader :=
    function(const AFileName: string): TBytes
    begin
      Result := TWindowsSharedRead.ReadAllBytes(AFileName);
    end;
  TIndexBlockFiles.Opener :=
    function(const AFileName: string): IIndexBlockReader
    begin
      Result := TWindowsSharedRead.OpenBlocks(AFileName);
    end;
end;

class procedure TWindowsSharedRead.Uninstall;
begin
  TFileEncoding.Reader := nil;
  TIndexBlockFiles.Opener := nil;
end;

end.
