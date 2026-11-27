unit Shell.LspServer.FileLog;

// Host-Rolle Shell, nur in dpcc.LspServer.exe: Protokoll in eine Datei je Prozess. Jede Zeile wird sofort
// angehängt (Datei kurz öffnen, schreiben, schließen), damit ein hartes Ende durch die IDE nichts verliert und andere
// Prozesse mitlesen können. Fehler beim Schreiben verschluckt die Senke: Das Protokoll darf den Server nie stören.
// Nie stdout und nie stderr: stdout gehört dem Protokoll, und stderr liest die IDE womöglich nicht (eine volle Pipe
// hielte den Server an).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  dpcc.Common.Logging.Contract;

type
  TLspFileLogSink = class(TInterfacedObject, ILogSink)
  private
    FFileName: string;
    FLock: TCriticalSection;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    procedure Write(const AEntry: TLogEntry);
    /// <summary>Datei des Protokolls für diesen Prozess in AFolder (legt den Ordner an).</summary>
    class function FileFor(const AFolder: string; AProcessId: Cardinal): string; static;
    /// <summary>Löscht Protokolle in AFolder, die älter als AMaxAgeDays sind; liefert die Anzahl.</summary>
    class function RemoveOld(const AFolder: string; AMaxAgeDays: Integer): Integer; static;
    property FileName: string read FFileName;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  dpcc.Common.Logging.EntryText;

constructor TLspFileLogSink.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
  FLock := TCriticalSection.Create;
end;

destructor TLspFileLogSink.Destroy;
begin
  FLock.Free;
  inherited;
end;

class function TLspFileLogSink.FileFor(const AFolder: string; AProcessId: Cardinal): string;
begin
  ForceDirectories(AFolder);
  Result := TPath.Combine(AFolder, Format('lsp-%s-%d.log', [FormatDateTime('yyyymmdd', Now), AProcessId]));
end;

class function TLspFileLogSink.RemoveOld(const AFolder: string; AMaxAgeDays: Integer): Integer;
var
  mFile: string;
begin
  Result := 0;
  try
    if not TDirectory.Exists(AFolder) then
    begin
      Exit;
    end;
    for mFile in TDirectory.GetFiles(AFolder, 'lsp-*.log') do
    begin
      if DaysBetween(Now, TFile.GetLastWriteTime(mFile)) > AMaxAgeDays then
      begin
        if DeleteFile(mFile) then
        begin
          Inc(Result);
        end;
      end;
    end;
  except
    // Aufräumen nach Kräften.
    on Exception do
      ;
  end;
end;

procedure TLspFileLogSink.Write(const AEntry: TLogEntry);
var
  mStream: TFileStream;
  mBytes: TBytes;
begin
  try
    mBytes := TEncoding.UTF8.GetBytes(TLogEntryText.PlainLine(AEntry) + sLineBreak);
    FLock.Enter;
    try
      if FileExists(FFileName) then
      begin
        mStream := TFileStream.Create(FFileName, fmOpenWrite or fmShareDenyNone);
      end
      else
      begin
        mStream := TFileStream.Create(FFileName, fmCreate or fmShareDenyNone);
      end;
      try
        mStream.Seek(0, soEnd);
        if Length(mBytes) > 0 then
        begin
          mStream.WriteBuffer(mBytes[0], Length(mBytes));
        end;
      finally
        mStream.Free;
      end;
    finally
      FLock.Leave;
    end;
  except
    // Das Protokoll darf den Server nie stören.
    on Exception do
      ;
  end;
end;

end.
