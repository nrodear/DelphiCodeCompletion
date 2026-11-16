unit dpcc.Common.Index.Adapters.DiskFileSystem;

// IIndexFileSystem auf der echten Platte. Lesen erkennt die Kodierung wie
// beim Öffnen im Editor; der binäre Index-Cache (#617) geht seit Format 34
// über OpenBlocks (einzelne Blöcke über ein offenes Handle, TIndexBlockFiles)
// und WriteStream. Schreiben (Cache) geht über eine temporäre Datei,
// die die alte in einem Schritt ersetzt (TFile.Replace). So sieht ein Leser
// nie einen halben Cache, auch nicht nach einem Abbruch (#184).
//
// Ein Schreiber je Cache: Den Projekt-Cache schreibt nur die
// Instanz, die seine Sperre hält (TShellWorkspace.LockCache), den gemeinsamen
// Bibliotheks-Cache nur, wer TryLockWrite erhalten hat. WriteBytes muss darum
// keine Wettläufe zweier Schreiber mehr ausgleichen; scheitert es, meldet es
// den Grund, statt ihn zu verschlucken.
//
// Eine Instanz für alle Dienste des Prozesses (Shared, Speicher-Optimierung b1): Die gemeinsamen Caches
// (TSharedCacheReads, TSharedCacheWrites im Index-Dienst) erkennen eine Datei an Dateisystem und Name. Mit einer
// eigenen Instanz je Arbeitsbereich las jedes Projekt einer Gruppe den Bibliotheks-Cache selbst (neun Kopien beim
// Start der Gruppe dpcc_d13), und der gemerkte Stand jeder Datei kam bei jedem Serverstart einmal hinzu.
//
// Ergänzen an Ort und Stelle (IIndexFileAppend, Speicher-Optimierung Phase 4): Beim ersten Aufbau schreibt der Dienst
// den Bibliotheks-Cache zwischendurch; statt die ganze Datei jedes Mal neu zu schreiben, hängt er nur die neuen Blöcke
// und ein neues Verzeichnis an. Das geht nur, solange die Datei den erwarteten Zeitstempel hat; Leser mit offenem
// Handle lesen ihre Blöcke unverändert weiter.

interface

uses
  System.SysUtils,
  dpcc.Common.Index.Contract;

type
  TDiskIndexFileSystem = class(TInterfacedObject, IIndexFileSystem, IIndexFileAppend)
  private
    class var FShared: IIndexFileSystem;
  public
    /// <summary>Die Platte für alle Dienste des Prozesses; die Klasse hält keinen Zustand.</summary>
    class function Shared: IIndexFileSystem; static;
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    function WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
    function TryLockWrite(const AFileName: string): IInterface;
    function OpenBlocks(const AFileName: string): IIndexBlockReader;
    function WriteStream(const AFileName: string; const AWrite: TIndexStreamWrite; out AError: string): Boolean;
    { IIndexFileAppend }
    function AppendStream(const AFileName: string; AStamp: Int64; const AWrite: TIndexStreamWrite;
      out AError: string): Boolean;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  dpcc.Common.Documents.FileEncoding,
  dpcc.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDiskFileSystemText = (TargetNotReplaced, FileChanged);

const
  cTexts: array[TDiskFileSystemText] of TDpccText = (
    (De: 'Ziel nicht ersetzt'; En: 'Target not replaced'),
    (De: 'Datei inzwischen geändert'; En: 'File changed in the meantime'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Hält die Sperrdatei offen, solange jemand die Schnittstelle hält.</summary>
  TWriteLock = class(TInterfacedObject)
  private
    FStream: TStream;
  public
    constructor Create(AStream: TStream);
    destructor Destroy; override;
  end;

constructor TWriteLock.Create(AStream: TStream);
begin
  inherited Create;
  FStream := AStream;
end;

destructor TWriteLock.Destroy;
begin
  FStream.Free;
  inherited;
end;

/// <summary>Grund ohne Pfad: Klasse, bei Ein-/Ausgabe- und Systemfehlern mit Fehlercode.</summary>
function ErrorReason(AE: Exception): string;
begin
  Result := AE.ClassName;
  if AE is EInOutError then
  begin
    Result := Format('%s %d', [Result, EInOutError(AE).ErrorCode]);
  end
  else if AE is EOSError then
  begin
    Result := Format('%s %d', [Result, EOSError(AE).ErrorCode]);
  end;
end;

{ TDiskIndexFileSystem }

class function TDiskIndexFileSystem.Shared: IIndexFileSystem;
begin
  Result := FShared;
end;

function TDiskIndexFileSystem.FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
var
  mAge: TDateTime;
begin
  Result := FileAge(AFileName, mAge);
  if Result then
  begin
    AStamp := Round(mAge * MSecsPerDay);
  end
  else
  begin
    AStamp := 0;
  end;
end;

function TDiskIndexFileSystem.ReadText(const AFileName: string; out AText: string): Boolean;
var
  mFormat: TFileFormat;
begin
  try
    AText := TFileEncoding.LoadFromFile(AFileName, mFormat);
    Result := True;
  except
    on EInOutError do
      Result := False;
    on EFOpenError do
      Result := False;
  end;
  if not Result then
  begin
    AText := '';
  end;
end;

function TDiskIndexFileSystem.ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
begin
  // Ohne Datei keine Ausnahme: Der erste Start hat noch keinen Cache.
  if not FileExists(AFileName) then
  begin
    ABytes := nil;
    Exit(False);
  end;
  try
    // Über TFileEncoding: teilt Löschen, damit ein zweiter Server den Cache währenddessen ersetzen kann
    //.
    ABytes := TFileEncoding.ReadAllBytes(AFileName);
    Result := True;
  except
    on EInOutError do
      Result := False;
    on EFOpenError do
      Result := False;
  end;
  if not Result then
  begin
    ABytes := nil;
  end;
end;

function TDiskIndexFileSystem.WriteText(const AFileName, AText: string): Boolean;
var
  mError: string;
begin
  Result := WriteBytes(AFileName, TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(AText), mError);
end;

function TDiskIndexFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
var
  mBytes: TBytes;
begin
  mBytes := ABytes;
  Result := WriteStream(AFileName,
    function(AStream: TStream): Boolean
    begin
      if Length(mBytes) > 0 then
      begin
        AStream.WriteBuffer(mBytes[0], Length(mBytes));
      end;
      Result := True;
    end, AError);
end;

function TDiskIndexFileSystem.WriteStream(const AFileName: string; const AWrite: TIndexStreamWrite;
  out AError: string): Boolean;
var
  mTemp, mBackup: string;
  mWritten: Boolean;
  mStream: TFileStream;
begin
  AError := '';
  // Name je Thread: Auch ein Schreiber ohne Sperre (Tests, Aufräumen) überschreibt keine fremde Zwischendatei.
  mTemp := Format('%s.%d.tmp', [AFileName, TThread.CurrentThread.ThreadID]);
  // TFile.Replace braucht eine Sicherungsdatei: Mit '' scheitert es an
  // TPath.GetFullPath('') ("Pfad ist leer"), sobald die Zieldatei existiert. Eindeutig je Schreibvorgang: Hält ein
  // Leser die alte Datei noch offen (Format 34, Blockleser), bleibt die Sicherung bis zu seinem Ende bestehen.
  mBackup := Format('%s.%d.%d.bak', [AFileName, TThread.CurrentThread.ThreadID, TThread.GetTickCount64]);
  try
    ForceDirectories(ExtractFileDir(AFileName));
    // Format 34: Der Cache entsteht Block für Block in der temporären Datei (Speicher-Optimierung Phase 3).
    mStream := TFileStream.Create(mTemp, fmCreate);
    try
      mWritten := AWrite(mStream);
    finally
      mStream.Free;
    end;
    if mWritten then
    begin
      if FileExists(AFileName) then
      begin
        TFile.Replace(mTemp, AFileName, mBackup);
      end
      else
      begin
        RenameFile(mTemp, AFileName); // lsp-ignore: inline-not-expanded -- Common ohne Winapi
      end;
    end;
  except
    // Gemeldet, nicht verschluckt: Der Aufrufer schreibt den Grund ins Log.
    // lsp-ignore: catch-all-without-raise -- Fehler geht als AError an den Aufrufer
    on E: Exception do
    begin
      AError := ErrorReason(E);
      mWritten := False;
    end;
  end;
  // TFile.Replace wertet das Ergebnis von ReplaceFile nicht aus und wirft bei einem Fehler
  // nichts (etwa ein Ziel, das ein fremdes Programm ohne FILE_SHARE_DELETE offen hält).
  // Gelungen ist das Schreiben genau dann, wenn die temporäre Datei an die Stelle des Ziels
  // getreten ist.
  Result := mWritten and not FileExists(mTemp);
  // ReplaceFile kann das alte Ziel schon zur Sicherung umbenannt haben, ohne die neue Datei
  // nachzuschieben (ERROR_UNABLE_TO_MOVE_REPLACEMENT_2). Die temporäre Datei ist vollständig
  // geschrieben, also an ihre Stelle setzen.
  if mWritten and not Result and not FileExists(AFileName) then
  begin
    Result := RenameFile(mTemp, AFileName); // lsp-ignore: inline-not-expanded -- Common ohne Winapi
  end;
  if not Result and (AError = '') then
  begin
    AError := cTexts[TDiskFileSystemText.TargetNotReplaced].Text;
  end;
  // Keine Reste, weder bei Erfolg noch bei Fehler (Test FailedReplaceLeavesNoRemains).
  if FileExists(mTemp) then
  begin
    System.SysUtils.DeleteFile(mTemp);
  end;
  if FileExists(mBackup) then
  begin
    System.SysUtils.DeleteFile(mBackup);
  end;
end;

function TDiskIndexFileSystem.AppendStream(const AFileName: string; AStamp: Int64; const AWrite: TIndexStreamWrite;
  out AError: string): Boolean;
var
  mStamp: Int64;
  mStream: TFileStream;
begin
  AError := '';
  Result := False;
  try
    // Nur die Datei, deren Stand der Aufrufer kennt: Hat ein anderer sie ersetzt, schreibt er sie ganz.
    if not FileStamp(AFileName, mStamp) or (mStamp <> AStamp) then
    begin
      AError := cTexts[TDiskFileSystemText.FileChanged].Text;
      Exit;
    end;
    // Leser behalten ihre Handles (sie teilen Schreiben); ein zweiter Schreiber bekommt die Datei nicht.
    mStream := TFileStream.Create(AFileName, fmOpenReadWrite or fmShareDenyWrite);
    try
      Result := AWrite(mStream);
    finally
      mStream.Free;
    end;
  except
    // Gemeldet, nicht verschluckt: Der Aufrufer schreibt die Datei dann ganz.
    // lsp-ignore: catch-all-without-raise -- Fehler geht als AError an den Aufrufer
    on E: Exception do
    begin
      AError := ErrorReason(E);
      Result := False;
    end;
  end;
end;

function TDiskIndexFileSystem.OpenBlocks(const AFileName: string): IIndexBlockReader;
begin
  // Ohne Datei kein Leser: Der erste Start hat noch keinen Cache.
  if not FileExists(AFileName) then
  begin
    Exit(nil);
  end;
  Result := TIndexBlockFiles.Open(AFileName);
end;

function TDiskIndexFileSystem.TryLockWrite(const AFileName: string): IInterface;
begin
  // Dieselbe Sperrdatei wie TIndexCacheDirectory.TryLock (LockExtension), die TShellWorkspace.LockCache hält:
  // Aufräumen und Leeren lassen den Cache dann in Ruhe. Der Test DiskWriteLockIsExclusive prüft, dass beide
  // übereinstimmen; ein Adapter importiert den anderen nicht (Rollenmatrix).
  try
    ForceDirectories(ExtractFileDir(AFileName));
    Result := TWriteLock.Create(TFileStream.Create(AFileName + '.lock', fmCreate or fmShareExclusive));
  except
    // Gesperrt: Ein anderer schreibt gerade. Das ist das erwartete Ergebnis, kein Fehler.
    on EStreamError do
      Result := nil;
    on EInOutError do
      Result := nil;
  end;
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Index.Adapters.DiskFileSystem', cTexts);
  TDiskIndexFileSystem.FShared := TDiskIndexFileSystem.Create;

finalization
  TDiskIndexFileSystem.FShared := nil;

end.
