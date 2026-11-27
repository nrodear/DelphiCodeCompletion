unit Shell.LspServer.Options;

// Host-Rolle Shell, nur in dpcc.LspServer.exe: Befehlszeile und Ablageort.
// Aufruf: dpcc.LspServer.exe [--cache-root <Ordner>] [--log-level debug|info|warning|error] [--no-log]
//                            [--version] [--help]
// Unbekannte Parameter werden übergangen: Wer den Start von DelphiLSP.exe umleitet, hängt dessen Pfad und Parameter
// (-LogModes 0 -Name Agent0 …) an.
// Ablageort (Index-Caches, Projektwahl, Diagnoselog, Protokoll), in dieser Reihenfolge:
//   1. --cache-root <Ordner>
//   2. Umgebungsvariable DPCC_LSPSERVER_CACHE_ROOT
//   3. %LOCALAPPDATA%\dpcc.LspServer
// Er ist bewusst NICHT %LOCALAPPDATA%\dpcc (der gehört dem Plugin), und DPCC_CACHE_ROOT des Aufrufers gilt nicht:
// Das Programm setzt DPCC_CACHE_ROOT in seinem eigenen Prozess auf den gewählten Ordner, damit alle Teile des Servers
// dort ablegen. Protokoll: <Ablage>\Logs\LspServer\lsp-<Datum>-<Prozess>.log (älter als 14 Tage wird beim Start
// gelöscht).

interface

uses
  System.SysUtils,
  dpcc.Common.Logging.Contract;

type
  TLspServerOptions = record
  public const
    cCacheRootVariable = 'DPCC_LSPSERVER_CACHE_ROOT';
    cFolderName = 'dpcc.LspServer';
  public
    CacheRoot: string;
    LogLevel: TLogLevel;
    NoLog: Boolean;
    ShowVersion: Boolean;
    ShowHelp: Boolean;
    /// <summary>Liest AArgs (ohne Programmnamen); ACacheVariable: Wert von DPCC_LSPSERVER_CACHE_ROOT,
    /// ALocalAppData: Wert von LOCALAPPDATA.</summary>
    class function Parse(const AArgs: TArray<string>; const ACacheVariable, ALocalAppData: string): TLspServerOptions;
      static;
    /// <summary>Wie Parse mit der Befehlszeile und der Umgebung dieses Prozesses.</summary>
    class function FromProcess: TLspServerOptions; static;
    /// <summary>Ordner des Protokolls unter CacheRoot.</summary>
    function LogFolder: string;
    class function HelpText: string; static;
  end;

implementation

uses
  System.IOUtils,
  dpcc.Common.Product.Version;

class function TLspServerOptions.Parse(const AArgs: TArray<string>; const ACacheVariable,
  ALocalAppData: string): TLspServerOptions;
var
  mIndex: Integer;
  mArg, mValue: string;

  function NextValue: string;
  begin
    Result := '';
    if mIndex < High(AArgs) then
    begin
      Inc(mIndex);
      Result := AArgs[mIndex];
    end;
  end;

begin
  Result := Default(TLspServerOptions);
  Result.LogLevel := TLogLevel.Info;
  mIndex := 0;
  while mIndex <= High(AArgs) do
  begin
    mArg := AArgs[mIndex];
    mValue := '';
    if mArg.StartsWith('--') and (Pos('=', mArg) > 0) then
    begin
      mValue := Copy(mArg, Pos('=', mArg) + 1, MaxInt);
      mArg := Copy(mArg, 1, Pos('=', mArg) - 1);
      if SameText(mArg, '--cache-root') then
      begin
        Result.CacheRoot := mValue;
      end
      else if SameText(mArg, '--log-level') then
      begin
        mValue := LowerCase(mValue);
      end;
    end
    else if SameText(mArg, '--cache-root') then
    begin
      Result.CacheRoot := NextValue;
    end
    else if SameText(mArg, '--log-level') then
    begin
      mValue := LowerCase(NextValue);
    end
    else if SameText(mArg, '--no-log') then
    begin
      Result.NoLog := True;
    end
    else if SameText(mArg, '--version') then
    begin
      Result.ShowVersion := True;
    end
    else if SameText(mArg, '--help') or SameText(mArg, '-h') or (mArg = '/?') then
    begin
      Result.ShowHelp := True;
    end;
    if (mValue = 'debug') then
    begin
      Result.LogLevel := TLogLevel.Debug;
    end
    else if mValue = 'warning' then
    begin
      Result.LogLevel := TLogLevel.Warning;
    end
    else if mValue = 'error' then
    begin
      Result.LogLevel := TLogLevel.Error;
    end
    else if mValue = 'info' then
    begin
      Result.LogLevel := TLogLevel.Info;
    end;
    Inc(mIndex);
  end;
  Result.CacheRoot := Trim(Result.CacheRoot);
  if Result.CacheRoot = '' then
  begin
    Result.CacheRoot := Trim(ACacheVariable);
  end;
  if Result.CacheRoot = '' then
  begin
    if Trim(ALocalAppData) <> '' then
    begin
      Result.CacheRoot := TPath.Combine(Trim(ALocalAppData), cFolderName);
    end
    else
    begin
      Result.CacheRoot := TPath.Combine(TPath.GetCachePath, cFolderName);
    end;
  end;
  // Relativ hieße: relativ zum Arbeitsordner, und das ist beim Start aus der IDE deren bin-Ordner.
  Result.CacheRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Result.CacheRoot));
end;

class function TLspServerOptions.FromProcess: TLspServerOptions;
var
  mArgs: TArray<string>;
  mIndex: Integer;
begin
  mArgs := nil;
  for mIndex := 1 to ParamCount do
  begin
    mArgs := mArgs + [ParamStr(mIndex)];
  end;
  Result := Parse(mArgs, GetEnvironmentVariable(cCacheRootVariable), GetEnvironmentVariable('LOCALAPPDATA'));
end;

function TLspServerOptions.LogFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(CacheRoot, 'Logs'), 'LspServer');
end;

class function TLspServerOptions.HelpText: string;
begin
  Result := 'dpcc.LspServer ' + TProductVersion.cVersion + ' - Language Server (stdio) für Delphi' + sLineBreak +
    sLineBreak +
    'Aufruf: dpcc.LspServer.exe [--cache-root <Ordner>] [--log-level debug|info|warning|error] [--no-log]' +
    sLineBreak +
    '                           [--version] [--help]' + sLineBreak + sLineBreak +
    'Spricht LSP über stdin/stdout. Ablage: --cache-root, sonst %' + cCacheRootVariable + '%, sonst ' +
    '%LOCALAPPDATA%\' + cFolderName + '.';
end;

end.
