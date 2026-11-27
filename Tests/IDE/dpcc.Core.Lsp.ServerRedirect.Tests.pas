unit dpcc.Core.Lsp.ServerRedirect.Tests;

// Tests für die Betriebsart Server ohne IDE (Stufe 2 von dpcc.LspServer.exe): die reine Entscheidung des Hooks auf
// CreateProcessW (dpcc.Core.Lsp.ServerRedirect: Schreibweisen DelphiLsp.exe/DelphiLSP.exe, Anführungszeichen,
// angehängte Parameter, fremde Programme bleiben unberührt, Betriebsart, fehlende EXE), der Ort der EXE relativ zum
// Plugin (Setup und Entwicklungsbaum, 64 Bit zuerst) und der Importtabellen-Teil (dpcc.Core.Diagnostics.ImportPatch)
// an einem ungefährlichen Ziel im Testprogramm selbst: kernel32!GetCurrentProcessId finden, auf eine zählende
// Weiterleitung setzen, zurücksetzen. Keine Registry, keine Dateien.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccLspServerRedirectTests = class
  public
    /// <summary>So wie Delphi 12 (DelphiLsp.exe) und Delphi 13 (DelphiLSP.exe) aufrufen: Anwendung und Kommandozeile
    /// werden ersetzt, die Kommandozeile mit der EXE in Anführungszeichen.</summary>
    [Test]
    [TestCase('Delphi 12', 'C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\DelphiLsp.exe')]
    [TestCase('Delphi 13', 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\DelphiLSP.exe')]
    procedure RedirectsDelphiLsp(const AOriginal: string);
    /// <summary>Kommandozeile ohne Anführungszeichen, mit angehängten Parametern, ohne lpApplicationName.</summary>
    [Test]
    procedure CommandLineVariants;
    /// <summary>Fremde Programme (auch mit DelphiLSP im Ordnernamen oder als Parameter) bleiben unberührt.</summary>
    [Test]
    procedure OtherProgramsUntouched;
    /// <summary>Aus und Plugin leiten nie um; fehlt die EXE (kein Ort oder Datei weg), bleibt der Originalaufruf.
    /// </summary>
    [Test]
    procedure ModeAndMissingExe;
    /// <summary>Zerlegen der Kommandozeile.</summary>
    [Test]
    procedure SplitCommandLine;
    /// <summary>Orte der EXE: Setup ({app}\bpl\d13 → {app}\server\win64|win32), Entwicklungsbaum
    /// (Output\Win32\&lt;Konfig&gt;\Bpl → Output\Win64\&lt;Konfig&gt;\Bin, Debug, Release, dann Win32), 64 Bit zuerst nur
    /// auf 64-Bit-Windows, zuletzt neben dem Plugin; Locate nimmt den ersten vorhandenen.</summary>
    [Test]
    procedure CandidatesAndLocate;
    /// <summary>Importtabelle des Testprogramms: Eintrag finden, umbiegen (Aufruf läuft über die Weiterleitung),
    /// zurücksetzen (Aufruf wieder direkt); fremd umgebogene Einträge werden nicht zurückgesetzt; ungültige Ziele
    /// liefern nichts.</summary>
    [Test]
    procedure ImportTablePatchAndRestore;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  dpcc.Core.Settings.OperatingMode,
  dpcc.Core.Lsp.ServerRedirect,
  dpcc.Core.Diagnostics.ImportPatch;

const
  cExe = 'C:\Users\Test\AppData\Local\Programs\dpcc\server\win64\dpcc.LspServer.exe';

function Input(const AApp, ACmd: string; AMode: TDpccOperatingMode; const AExe: string): TDpccLspRedirectInput;
begin
  Result := Default(TDpccLspRedirectInput);
  Result.ApplicationName := AApp;
  Result.CommandLine := ACmd;
  Result.Mode := AMode;
  Result.ServerExe := AExe;
end;

function Exists(const AFiles: array of string): TFunc<string, Boolean>;
var
  mFiles: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mFiles, Length(AFiles));
  for mIndex := 0 to High(AFiles) do
  begin
    mFiles[mIndex] := AFiles[mIndex];
  end;
  Result :=
    function(APath: string): Boolean
    begin
      Result := MatchText(APath, mFiles);
    end;
end;

{ TDpccLspServerRedirectTests }

procedure TDpccLspServerRedirectTests.RedirectsDelphiLsp(const AOriginal: string);
var
  mDecision: TDpccLspRedirectDecision;
begin
  // Gemessen: lpApplicationName = voller Pfad, Kommandozeile = "<Pfad>" mit Leerzeichen dahinter.
  mDecision := TDpccLspRedirect.Decide(Input(AOriginal, '"' + AOriginal + '" ', TDpccOperatingMode.Server, cExe),
    Exists([cExe]));
  Assert.IsTrue(mDecision.IsDelphiLsp, 'erkannt');
  Assert.IsTrue(mDecision.Redirect, 'umgeleitet: ' + mDecision.Reason);
  Assert.AreEqual(cExe, mDecision.ApplicationName, 'Anwendung');
  Assert.AreEqual('"' + cExe + '"', mDecision.CommandLine, 'Kommandozeile');
end;

procedure TDpccLspServerRedirectTests.CommandLineVariants;
const
  cLsp = 'C:\Studio\37.0\bin\DelphiLSP.exe';
var
  mDecision: TDpccLspRedirectDecision;
begin
  // Ohne Anführungszeichen und ohne Anwendung: nur die Kommandozeile zählt, die Anwendung bleibt nil.
  mDecision := TDpccLspRedirect.Decide(Input('', 'C:\Studio\bin\delphilsp.EXE', TDpccOperatingMode.Server, cExe),
    nil);
  Assert.IsTrue(mDecision.Redirect, 'ohne Anführungszeichen');
  Assert.AreEqual('', mDecision.ApplicationName, 'Anwendung bleibt nil');
  Assert.AreEqual('"' + cExe + '"', mDecision.CommandLine);
  // Angehängte Originalparameter bleiben hinten.
  mDecision := TDpccLspRedirect.Decide(Input(cLsp, '"' + cLsp + '" -pipe  --log x', TDpccOperatingMode.Server,
    cExe), Exists([cExe]));
  Assert.IsTrue(mDecision.Redirect, 'mit Parametern');
  Assert.AreEqual('"' + cExe + '" -pipe  --log x', mDecision.CommandLine, 'Parameter');
  // Nur die Anwendung gesetzt, keine Kommandozeile.
  mDecision := TDpccLspRedirect.Decide(Input(cLsp, '', TDpccOperatingMode.Server, cExe), Exists([cExe]));
  Assert.IsTrue(mDecision.Redirect, 'nur Anwendung');
  Assert.AreEqual(cExe, mDecision.ApplicationName);
  Assert.AreEqual('"' + cExe + '"', mDecision.CommandLine);
end;

procedure TDpccLspServerRedirectTests.OtherProgramsUntouched;
const
  cCases: array[0..4] of string = ('"C:\Windows\System32\cmd.exe" /c echo', 'C:\Studio\bin\dcc32.exe -B',
    '"C:\DelphiLSP.exe\tool.exe"', '"C:\Studio\bin\rsvars.exe" DelphiLSP.exe', '"C:\Studio\bin\DelphiLSP.exe.bak"');
var
  mCase: string;
  mDecision: TDpccLspRedirectDecision;
begin
  for mCase in cCases do
  begin
    mDecision := TDpccLspRedirect.Decide(Input('', mCase, TDpccOperatingMode.Server, cExe), Exists([cExe]));
    Assert.IsFalse(mDecision.IsDelphiLsp, mCase + ': erkannt');
    Assert.IsFalse(mDecision.Redirect, mCase + ': umgeleitet');
    Assert.AreEqual(mCase, mDecision.CommandLine, mCase + ': Kommandozeile bleibt');
    Assert.AreEqual('', mDecision.ApplicationName, mCase + ': Anwendung bleibt');
  end;
  // Die EXE selbst wird nie noch einmal umgeleitet.
  mDecision := TDpccLspRedirect.Decide(Input(cExe, '"' + cExe + '"', TDpccOperatingMode.Server, cExe), nil);
  Assert.IsFalse(mDecision.Redirect, 'dpcc.LspServer.exe');
end;

procedure TDpccLspServerRedirectTests.ModeAndMissingExe;
const
  cLsp = 'C:\Studio\23.0\bin\DelphiLsp.exe';
var
  mMode: TDpccOperatingMode;
  mDecision: TDpccLspRedirectDecision;
begin
  for mMode in [TDpccOperatingMode.Off, TDpccOperatingMode.Plugin] do
  begin
    mDecision := TDpccLspRedirect.Decide(Input(cLsp, '"' + cLsp + '" ', mMode, cExe), Exists([cExe]));
    Assert.IsTrue(mDecision.IsDelphiLsp, 'erkannt');
    Assert.IsFalse(mDecision.Redirect, TDpccOperatingModes.LogName(mMode) + ': nie umgeleitet');
    Assert.AreEqual(cLsp, mDecision.ApplicationName, 'Anwendung bleibt');
    Assert.AreEqual('"' + cLsp + '" ', mDecision.CommandLine, 'Kommandozeile bleibt');
    Assert.IsTrue(ContainsText(mDecision.Reason, TDpccOperatingModes.LogName(mMode)), mDecision.Reason);
  end;
  // Server, aber keine EXE gefunden bzw. Datei inzwischen weg.
  mDecision := TDpccLspRedirect.Decide(Input(cLsp, '"' + cLsp + '" ', TDpccOperatingMode.Server, ''), nil);
  Assert.IsFalse(mDecision.Redirect, 'ohne Ort');
  Assert.IsTrue(ContainsText(mDecision.Reason, 'nicht gefunden'), mDecision.Reason);
  mDecision := TDpccLspRedirect.Decide(Input(cLsp, '"' + cLsp + '" ', TDpccOperatingMode.Server, cExe), Exists([]));
  Assert.IsFalse(mDecision.Redirect, 'Datei fehlt');
  Assert.AreEqual(cLsp, mDecision.ApplicationName, 'Original');
  Assert.IsTrue(ContainsText(mDecision.Reason, 'fehlt'), mDecision.Reason);
end;

procedure TDpccLspServerRedirectTests.SplitCommandLine;
var
  mProgram, mRest: string;
begin
  Assert.IsTrue(TDpccLspRedirect.SplitCommandLine('"C:\a b\x.exe" -p 1', mProgram, mRest));
  Assert.AreEqual('C:\a b\x.exe', mProgram);
  Assert.AreEqual('-p 1', mRest);
  Assert.IsTrue(TDpccLspRedirect.SplitCommandLine('  x.exe   y  ', mProgram, mRest), 'Leerraum');
  Assert.AreEqual('x.exe', mProgram);
  Assert.AreEqual('y', mRest);
  Assert.IsTrue(TDpccLspRedirect.SplitCommandLine('"C:\offen\x.exe', mProgram, mRest), 'ohne Ende');
  Assert.AreEqual('C:\offen\x.exe', mProgram);
  Assert.AreEqual('', mRest);
  Assert.IsFalse(TDpccLspRedirect.SplitCommandLine('   ', mProgram, mRest), 'leer');
  Assert.IsTrue(TDpccLspRedirect.IsDelphiLsp('DELPHILSP.EXE'), 'ohne Ordner');
  Assert.IsFalse(TDpccLspRedirect.IsDelphiLsp('C:\bin\DelphiLSP.exe\x'), 'Ordner');
end;

procedure TDpccLspServerRedirectTests.CandidatesAndLocate;
const
  cSetup = 'C:\Users\Test\AppData\Local\Programs\dpcc';
  cRepo = 'D:\repo\DelphiCodeCompletion\Output';
var
  mList: TArray<string>;
begin
  // Setup, 64-Bit-Windows: erst win64, dann win32, zuletzt neben dem Plugin.
  mList := TDpccLspRedirect.Candidates(cSetup + '\bpl\d13\dpcc.Plugin370.bpl', True);
  Assert.AreEqual(3, Integer(Length(mList)), string.Join(' | ', mList));
  Assert.AreEqual(cSetup + '\server\win64\dpcc.LspServer.exe', mList[0]);
  Assert.AreEqual(cSetup + '\server\win32\dpcc.LspServer.exe', mList[1]);
  Assert.AreEqual(cSetup + '\bpl\d13\dpcc.LspServer.exe', mList[2]);
  // 32-Bit-Windows: keine 64-Bit-EXE.
  mList := TDpccLspRedirect.Candidates(cSetup + '\bpl\d12\dpcc.Plugin290.bpl', False);
  Assert.AreEqual(cSetup + '\server\win32\dpcc.LspServer.exe', mList[0]);
  Assert.IsFalse(ContainsText(string.Join('|', mList), 'win64'), 'ohne win64');
  // Entwicklungsbaum Delphi 12 (Konfiguration D12): Win64\D12, Debug, Release, dann Win32 ebenso.
  mList := TDpccLspRedirect.Candidates(cRepo + '\Win32\D12\Bpl\dpcc.Plugin290.bpl', True);
  Assert.AreEqual(cRepo + '\Win64\D12\Bin\dpcc.LspServer.exe', mList[0]);
  Assert.AreEqual(cRepo + '\Win64\Debug\Bin\dpcc.LspServer.exe', mList[1]);
  Assert.AreEqual(cRepo + '\Win64\Release\Bin\dpcc.LspServer.exe', mList[2]);
  Assert.AreEqual(cRepo + '\Win32\D12\Bin\dpcc.LspServer.exe', mList[3]);
  Assert.AreEqual(cRepo + '\Win32\Debug\Bin\dpcc.LspServer.exe', mList[4]);
  // Delphi 13 (Debug): ohne Doppel.
  mList := TDpccLspRedirect.Candidates(cRepo + '\Win32\Debug\Bpl\dpcc.Plugin370.bpl', True);
  Assert.AreEqual(cRepo + '\Win64\Debug\Bin\dpcc.LspServer.exe', mList[0]);
  Assert.AreEqual(cRepo + '\Win64\Release\Bin\dpcc.LspServer.exe', mList[1]);
  Assert.AreEqual(cRepo + '\Win32\Debug\Bin\dpcc.LspServer.exe', mList[2]);
  Assert.AreEqual(5, Integer(Length(mList)), string.Join(' | ', mList));
  // Locate: die 64-Bit-EXE fehlt → 32 Bit; keine da → ''.
  Assert.AreEqual(cRepo + '\Win32\Debug\Bin\dpcc.LspServer.exe', TDpccLspRedirect.Locate(cRepo +
    '\Win32\D12\Bpl\dpcc.Plugin290.bpl', True, Exists([cRepo + '\Win32\Debug\Bin\dpcc.LspServer.exe'])), 'Win32');
  Assert.AreEqual(cRepo + '\Win64\Debug\Bin\dpcc.LspServer.exe', TDpccLspRedirect.Locate(cRepo +
    '\Win32\D12\Bpl\dpcc.Plugin290.bpl', True, Exists([cRepo + '\Win32\Debug\Bin\dpcc.LspServer.exe',
    cRepo + '\Win64\Debug\Bin\dpcc.LspServer.exe'])), 'Win64 bevorzugt');
  Assert.AreEqual('', TDpccLspRedirect.Locate(cSetup + '\bpl\d13\dpcc.Plugin370.bpl', True, Exists([])), 'keine');
  // Ein beliebiger Ordner: nur neben dem Plugin.
  mList := TDpccLspRedirect.Candidates('E:\Pakete\dpcc.Plugin370.bpl', True);
  Assert.AreEqual(1, Integer(Length(mList)), string.Join(' | ', mList));
  Assert.AreEqual('E:\Pakete\dpcc.LspServer.exe', mList[0]);
  Assert.AreEqual(0, Integer(Length(TDpccLspRedirect.Candidates('', True))), 'ohne Plugin');
end;

var
  /// <summary>Weiterleitung für den Importtabellen-Test: Aufrufe des Testthreads und das Original.</summary>
  PatchCalls: Integer;
  PatchThread: DWORD;
  PatchOriginal: function: DWORD; stdcall;

function CountingGetCurrentProcessId: DWORD; stdcall;
begin
  // Andere Threads laufen ungezählt durch; jeder bekommt den richtigen Wert.
  if GetCurrentThreadId = PatchThread then
  begin
    Inc(PatchCalls);
  end;
  Result := PatchOriginal();
end;

procedure TDpccLspServerRedirectTests.ImportTablePatchAndRestore;
var
  mSlots: TArray<PPointer>;
  mOld: TArray<Pointer>;
  mSlot: PPointer;
  mPrevious: Pointer;
  mIndex: Integer;
  mPid: DWORD;
begin
  mPid := GetCurrentProcessId;
  mSlots := TDpccImportPatch.FindSlots(HInstance, 'kernel32.dll', 'GetCurrentProcessId');
  Assert.IsTrue(Length(mSlots) > 0, 'Eintrag gefunden');
  // Ohne Endung und in anderer Schreibweise derselbe Eintrag.
  Assert.AreEqual(Integer(Length(mSlots)), Integer(Length(TDpccImportPatch.FindSlots(HInstance, 'KERNEL32',
    'GetCurrentProcessId'))), 'ohne Endung');
  PatchCalls := 0;
  PatchThread := GetCurrentThreadId;
  @PatchOriginal := GetProcAddress(GetModuleHandle('kernel32.dll'), 'GetCurrentProcessId');
  SetLength(mOld, Length(mSlots));
  for mIndex := 0 to High(mSlots) do
  begin
    Assert.IsTrue(TDpccImportPatch.Patch(mSlots[mIndex], @CountingGetCurrentProcessId, mOld[mIndex]), 'gesetzt');
  end;
  try
    Assert.AreEqual(Integer(mPid), Integer(GetCurrentProcessId), 'Wert über die Weiterleitung');
    Assert.AreEqual(1, PatchCalls, 'Aufruf lief über die Weiterleitung');
  finally
    for mIndex := 0 to High(mSlots) do
    begin
      Assert.IsTrue(TDpccImportPatch.Restore(mSlots[mIndex], @CountingGetCurrentProcessId, mOld[mIndex]),
        'zurückgesetzt');
    end;
  end;
  Assert.AreEqual(Integer(mPid), Integer(GetCurrentProcessId), 'Wert direkt');
  Assert.AreEqual(1, PatchCalls, 'nach dem Zurücksetzen keine Weiterleitung mehr');
  // Ein Eintrag, der nicht (mehr) auf unser Ziel zeigt, bleibt unangetastet.
  mSlot := mSlots[0];
  mPrevious := mSlot^;
  Assert.IsFalse(TDpccImportPatch.Restore(mSlot, @CountingGetCurrentProcessId, nil), 'fremder Eintrag');
  Assert.IsTrue(mSlot^ = mPrevious, 'unverändert');
  // Ungültige Ziele: nichts, keine Ausnahme.
  Assert.AreEqual(0, Integer(Length(TDpccImportPatch.FindSlots(0, 'kernel32.dll', 'GetCurrentProcessId'))), '0');
  Assert.AreEqual(0, Integer(Length(TDpccImportPatch.FindSlots(HInstance, 'kernel32.dll', 'GibtEsNicht'))),
    'unbekannte Funktion');
  Assert.AreEqual(0, Integer(Length(TDpccImportPatch.FindSlots(HInstance, 'gibtesnicht.dll', 'Irgendwas'))),
    'unbekannte DLL');
  Assert.IsFalse(TDpccImportPatch.Patch(nil, @CountingGetCurrentProcessId, mPrevious), 'nil');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccLspServerRedirectTests);

end.
