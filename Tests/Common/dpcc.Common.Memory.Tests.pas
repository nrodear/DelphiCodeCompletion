unit dpcc.Common.Memory.Tests;

// Speicher-Optimierung (Phase 0 und 1): Selbstmessung über GetProcessMemoryInfo (a0) und die einstellbare Wurzel der
// Index-Caches (DPCC_CACHE_ROOT, LOCALAPPDATA der Umgebung), damit Tests und Messprogramm den Cache des Benutzers
// nicht berühren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccMemoryTests = class
  public
    /// <summary>Einmal-Belegungen (Statistik der Syntaxbäume, Merker der .dcp) vor dem Leckmonitor.</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>DPCC_CACHE_ROOT ersetzt den Ordner, sonst gilt LOCALAPPDATA aus der Umgebung.</summary>
    [Test]
    procedure CacheRootFollowsEnvironment;
    /// <summary>Das Diagnoselog liegt unter derselben Wurzel wie die Caches.</summary>
    [Test]
    procedure DiagnosticLogFollowsCacheRoot;
    /// <summary>Private Bytes, Spitze und freie Region kommen vom Betriebssystem, nicht vom Speichermanager.</summary>
    [Test]
    procedure ProcessMemoryIsMeasured;
    /// <summary>Die Zeile „mem“ hat nur Kleinbuchstaben, Zahlen und „MB“/„kb“, ohne Schrägstrich (Filter des
    /// Diagnoselogs), und der Stand ist danach über Latest abrufbar.</summary>
    [Test]
    procedure MemoryReportLineIsPlain;
    /// <summary>a2: Vom .dcp bleiben nur die Namen aus dem Kopf (Units, Namespaces, requires); was nur im Rumpf
    /// steht (verwendete Units, Bezeichner), zählt nicht mehr.</summary>
    [Test]
    procedure CompiledPackageKeepsHeaderNames;
    /// <summary>a2: Ohne erkennbaren Kopf gilt wie früher jedes ganze Wort der Datei.</summary>
    [Test]
    procedure CompiledPackageWithoutHeaderUsesWords;
    /// <summary>a2: Der Locator beantwortet Provides und Requires aus den Namen; requires des .dcp führen die
    /// Unit-Suche weiter (vcl → rtl).</summary>
    [Test]
    procedure LocatorAnswersFromCompiledNames;
    /// <summary>a2 mit den .dcp der Installation (Delphi 13, Win32 und Win64): rtl, vcl, wenige KB statt MB.</summary>
    [Test]
    procedure InstalledPackagesKeepOnlyNames;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  Winapi.Windows,
  dpcc.Common.Projects.PackageLocator,
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.Windows.Diagnostics.ProcessInfo,
  Shell.Diagnostics;

/// <summary>Setzt eine Umgebungsvariable des Prozesses; '' entfernt sie.</summary>
procedure SetEnv(const AName, AValue: string);
begin
  if AValue = '' then
  begin
    Winapi.Windows.SetEnvironmentVariable(PChar(AName), nil);
  end
  else
  begin
    Winapi.Windows.SetEnvironmentVariable(PChar(AName), PChar(AValue));
  end;
end;

{ TDpccMemoryTests }

procedure TDpccMemoryTests.WarmUp;
begin
  TShellMemoryReport.Take(nil, nil, -1);
end;

procedure TDpccMemoryTests.CacheRootFollowsEnvironment;
var
  mOldRoot, mOldLocal, mFolder: string;
begin
  mOldRoot := GetEnvironmentVariable(TIndexCacheDirectory.cRootVariable);
  mOldLocal := GetEnvironmentVariable('LOCALAPPDATA');
  mFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-cacheroot-test');
  try
    SetEnv(TIndexCacheDirectory.cRootVariable, mFolder + PathDelim);
    Assert.AreEqual(mFolder, TIndexCacheDirectory.DefaultRoot, 'DPCC_CACHE_ROOT ohne Trenner am Ende');
    SetEnv(TIndexCacheDirectory.cRootVariable, '');
    SetEnv('LOCALAPPDATA', mFolder);
    Assert.AreEqual(TPath.Combine(mFolder, 'dpcc'), TIndexCacheDirectory.DefaultRoot, 'LOCALAPPDATA der Umgebung');
  finally
    SetEnv(TIndexCacheDirectory.cRootVariable, mOldRoot);
    SetEnv('LOCALAPPDATA', mOldLocal);
  end;
end;

procedure TDpccMemoryTests.DiagnosticLogFollowsCacheRoot;
var
  mOldRoot, mFolder: string;
begin
  mOldRoot := GetEnvironmentVariable(TIndexCacheDirectory.cRootVariable);
  mFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-cacheroot-test');
  try
    SetEnv(TIndexCacheDirectory.cRootVariable, mFolder);
    Assert.AreEqual(TPath.Combine(TPath.Combine(mFolder, 'Logs'), 'Diagnose'), TShellDiagnostics.DefaultFolder);
  finally
    SetEnv(TIndexCacheDirectory.cRootVariable, mOldRoot);
  end;
end;

procedure TDpccMemoryTests.ProcessMemoryIsMeasured;
var
  mMemory: TProcessMemory;
  mBlock: Pointer;
  mBefore: Int64;
begin
  mMemory := TProcessInfo.Memory;
  Assert.IsTrue(mMemory.Valid, 'GetProcessMemoryInfo');
  Assert.IsTrue(mMemory.PrivateBytes > 0, 'Private Bytes');
  Assert.IsTrue(mMemory.WorkingSetBytes > 0, 'Working Set');
  Assert.IsTrue(mMemory.PeakPrivateBytes >= mMemory.PrivateBytes, 'Spitze');
  Assert.IsTrue(mMemory.LargestFreeBytes > 0, 'freie Region');
  // 32 MB zusagen: Die Private Bytes steigen (FastMM legt große Blöcke direkt per VirtualAlloc an).
  mBefore := mMemory.PrivateBytes;
  GetMem(mBlock, 32 * 1024 * 1024);
  try
    FillChar(mBlock^, 32 * 1024 * 1024, 1);
    Assert.IsTrue(TProcessInfo.Memory.PrivateBytes >= mBefore + 30 * 1024 * 1024, 'Private Bytes nach 32 MB');
  finally
    FreeMem(mBlock);
  end;
end;

procedure TDpccMemoryTests.MemoryReportLineIsPlain;
var
  mReport: TShellMemoryReport;
  mText: string;
begin
  mReport := TShellMemoryReport.Take(nil, nil, -1);
  mText := mReport.Text;
  Assert.IsTrue(StartsText('private ', mText), mText);
  Assert.IsFalse(ContainsText(mText, '/'), mText);
  Assert.Contains(mText, ' peak ');
  Assert.Contains(mText, ' free ');
  Assert.Contains(mText, ' index -1 MB');
  Assert.AreEqual(mReport.Process.PrivateBytes, TShellMemoryReport.Latest.Process.PrivateBytes, 'Latest');
end;

/// <summary>Kleines .dcp im Format PKX0 (Win32): BPL-Name, requires, je Unit 60 Byte Kopf, Name und Namespace,
/// Abschluss ".&lt;APackage&gt;", danach ein Rumpf mit AFiller.</summary>
function FakeDcp(const APackage: string; const ARequires, AUnits: TArray<string>; const AFiller: string): TBytes;
var
  mData: TBytes;

  procedure AddBytes(const ABytes: TBytes);
  begin
    mData := mData + ABytes;
  end;

  procedure AddText(const AText: string);
  begin
    AddBytes(TEncoding.ASCII.GetBytes(AText) + [0]);
  end;

var
  mHead: TBytes;
  mName: string;
  mZero: TBytes;
begin
  SetLength(mHead, 32);
  FillChar(mHead[0], 32, 0);
  mHead[0] := Ord('P');
  mHead[1] := Ord('K');
  mHead[2] := Ord('X');
  mHead[3] := Ord('0');
  mHead[4] := Length(ARequires);
  mHead[8] := Length(AUnits) + 1;
  mData := mHead;
  AddText(LowerCase(APackage) + '370.bpl');
  for mName in ARequires do
  begin
    AddText(mName);
  end;
  SetLength(mZero, 60);
  FillChar(mZero[0], 60, 0);
  for mName in AUnits do
  begin
    // Adresse vor der Null: Reste wie im echten Kopf.
    mZero[4] := $FF;
    mZero[8] := $84;
    AddBytes(mZero);
    AddText(mName);
    AddText(Copy(mName, 1, Pos('.', mName + '.') - 1));
  end;
  AddBytes([3, 0, 0, 0]);
  AddText('.' + APackage);
  AddBytes(TEncoding.ASCII.GetBytes(AFiller));
  Result := mData;
end;

procedure TDpccMemoryTests.CompiledPackageKeepsHeaderNames;
var
  mNames: TPackageCompiledNames;
begin
  mNames := TPackageCompiledNames.Parse(FakeDcp('Probe', ['rtl', 'vcl'], ['Probe.Eins', 'Probe.Zwei'],
    ' uses System.SysUtils; TGeheim = class end '), 'Probe');
  Assert.IsTrue(mNames.FromHeader, 'aus dem Kopf');
  Assert.IsTrue(mNames.Contains('Probe.Eins'), 'Probe.Eins');
  Assert.IsTrue(mNames.Contains('probe.zwei'), 'ohne Groß-/Kleinschreibung');
  Assert.IsTrue(mNames.Contains('Probe'), 'Namespace');
  Assert.IsFalse(mNames.Contains('System.SysUtils'), 'nur im Rumpf');
  Assert.IsFalse(mNames.Contains('TGeheim'), 'Bezeichner im Rumpf');
  Assert.IsFalse(mNames.Contains('Probe.Ei'), 'nur ganze Namen');
  Assert.AreEqual('rtl,vcl', string.Join(',', mNames.Requires), 'requires');
  Assert.IsTrue(mNames.Bytes < 4096, 'wenige Byte');
end;

procedure TDpccMemoryTests.CompiledPackageWithoutHeaderUsesWords;
var
  mNames: TPackageCompiledNames;
begin
  mNames := TPackageCompiledNames.Parse(TEncoding.ASCII.GetBytes('xx Alt.Unit;Zweite_Unit yy'), 'Alt');
  Assert.IsFalse(mNames.FromHeader, 'kein Kopf');
  Assert.IsTrue(mNames.Contains('alt.unit'), 'ganzes Wort');
  Assert.IsTrue(mNames.Contains('Zweite_Unit'), 'zweites Wort');
  Assert.IsFalse(mNames.Contains('Alt'), 'Teil eines Worts');
  Assert.AreEqual(0, Integer(Length(mNames.Requires)), 'ohne requires');
  // Kopf ohne Abschluss ".<Package>": ebenso die Näherung.
  Assert.IsFalse(TPackageCompiledNames.Parse(FakeDcp('Probe', [], ['Probe.Eins'], ''), 'Anders').FromHeader,
    'Abschluss eines anderen Packages');
end;

procedure TDpccMemoryTests.LocatorAnswersFromCompiledNames;
var
  mLocator: TPackageLocator;
  mContains: Boolean;
  mData: TBytes;
begin
  mData := FakeDcp('Probe', ['rtl'], ['Probe.Eins'], ' System.SysUtils ');
  mLocator := TPackageLocator.Create(['X:\Pakete'],
    function(const AFileName: string; out AData: TBytes): Boolean
    begin
      Result := SameText(AFileName, 'X:\Pakete\Probe.dcp');
      AData := nil;
      if Result then
      begin
        AData := mData;
      end;
    end);
  try
    Assert.IsTrue(mLocator.Provides('Probe', 'Probe.Eins', mContains), 'Package gefunden');
    Assert.IsTrue(mContains, 'enthält Probe.Eins');
    Assert.IsTrue(mLocator.Provides('Probe', 'System.SysUtils', mContains), 'Package gefunden');
    Assert.IsFalse(mContains, 'System.SysUtils kommt aus rtl, nicht aus Probe');
    Assert.AreEqual('rtl', string.Join(',', mLocator.Requires('Probe')), 'requires aus dem .dcp');
    Assert.IsFalse(mLocator.Provides('Fehlt', 'Probe.Eins', mContains), 'unbekanntes Package');
  finally
    mLocator.Free;
  end;
end;

procedure TDpccMemoryTests.InstalledPackagesKeepOnlyNames;
const
  cLib = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\';
var
  mNames: TPackageCompiledNames;
  mPlatform: string;
begin
  if not FileExists(cLib + 'win32\release\rtl.dcp') then
  begin
    Assert.Pass('Delphi 13 nicht installiert');
    Exit;
  end;
  for mPlatform in ['win32', 'win64'] do
  begin
    if not FileExists(cLib + mPlatform + '\release\vcl.dcp') then
    begin
      Continue;
    end;
    // Ohne TPackageCompiledFiles: Dessen Merker lebt bis Programmende und zählte im Test als Leck.
    mNames := TPackageCompiledNames.Parse(TFile.ReadAllBytes(cLib + mPlatform + '\release\rtl.dcp'), 'rtl');
    Assert.IsTrue(mNames.FromHeader, mPlatform + ' rtl: Kopf');
    Assert.IsTrue(mNames.Contains('System.SysUtils') and mNames.Contains('System') and
      mNames.Contains('Winapi.Windows'), mPlatform + ' rtl: Units');
    Assert.IsFalse(mNames.Contains('Vcl.Forms'), mPlatform + ' rtl: keine VCL');
    Assert.AreEqual(0, Integer(Length(mNames.Requires)), mPlatform + ' rtl: ohne requires');
    Assert.IsTrue(mNames.Bytes < 256 * 1024, mPlatform + ' rtl: wenige KB');
    mNames := TPackageCompiledNames.Parse(TFile.ReadAllBytes(cLib + mPlatform + '\release\vcl.dcp'), 'vcl');
    Assert.IsTrue(mNames.Contains('Vcl.Forms'), mPlatform + ' vcl: Vcl.Forms');
    Assert.IsFalse(mNames.Contains('System.SysUtils'), mPlatform + ' vcl: System.SysUtils nur verwendet');
    Assert.AreEqual('rtl', string.Join(',', mNames.Requires), mPlatform + ' vcl: requires');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccMemoryTests);

end.
