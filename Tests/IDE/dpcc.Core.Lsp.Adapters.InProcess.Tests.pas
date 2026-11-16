unit dpcc.Core.Lsp.Adapters.InProcess.Tests;

// In-Process-Modus (Schritt 2b, docs\Konzept-Completion-Schnitt.md Abschnitt 4.5): Der Test-Host startet den
// Completion-Server ohne Exe und ohne IDE über denselben Adapter wie das Plugin (TLspInProcessServer), spricht mit ihm
// über TLspSession (initialize, didOpen, completion wie Tools\Rauchtest) und baut ihn wieder ab. Das Projekt liegt mit
// .dproj in einem eigenen Ordner unter %TEMP%, sonst findet der Server weder Projekt noch Delphi-Installation.
// Start und Stopp 3× ohne Leck (Leckmonitor) und ohne übrig gebliebene Threads; der erste Lauf ist ungemessen
// ([SetupFixture]), weil er die Einmal-Belegungen der Bibliotheken (Texttabellen, Cache-Ordner, Thread-Pools) macht.
// Rauchtest (S1, Ersatz für Tools\Rauchtest\lsp_rauchtest.py, das den eigenen Server-Prozess über stdio startete):
// initialize mit Capabilities und Version, completion, completionItem/resolve, hover, signatureHelp, didSave und
// shutdown/exit gegen denselben Server im eigenen Prozess. Ohne RTL-Index: Das Testprojekt braucht nur eigene
// Bezeichner, so hängt der Test nicht vom Indexaufbau der Delphi-Installation ab.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspInProcessServerTests = class
  private
    FFolder: string;
    FUnitFile: string;
    FProjectFile: string;
    /// <summary>Ein Lauf: Start, initialize, didOpen, completion, Stopp; die Mitglieder aus der Antwort.</summary>
    function RunCycle: string;
  public
    /// <summary>Projektordner anlegen und den ersten Lauf ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure CreateProjectAndWarmUp;
    [TearDownFixture]
    procedure DeleteProject;
    /// <summary>Vervollständigung nach "Self.FWe" aus dem Server im eigenen Prozess.</summary>
    [Test]
    procedure CompletesMembersInProcess;
    /// <summary>Start und Stopp 3×: kein Leck, kein Thread übrig, die prozessweiten Schalter zurück.</summary>
    [Test]
    procedure StartsAndStopsThreeTimes;
    /// <summary>Endet der Server von selbst (exit), schließt der Adapter den Client und meldet Exit-Code 0.</summary>
    [Test]
    procedure ExitClosesClient;
    /// <summary>Rauchtest: initialize, completion, resolve, hover, signatureHelp, didSave, shutdown/exit.</summary>
    [Test]
    procedure SmokeTestInProcess;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.Adapters.InProcess,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Providers.Server,
  dpcc.Tests.LeakMonitor,
  dpcc.Text.Product.Version,
  Shell.Composition.InProcess;

const
  cUnitText =
    'unit UProbe;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    FWert: Integer;'#13#10 +
    '    FWeite: Integer;'#13#10 +
    '    procedure Setze;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Setze;'#13#10 +
    'begin'#13#10 +
    '  Self.FWe'#13#10 +
    'end;'#13#10 +
    'end.';

  cDprText =
    'program Probe;'#13#10 +
    'uses'#13#10 +
    '  UProbe in ''UProbe.pas'';'#13#10 +
    'begin'#13#10 +
    'end.'#13#10;

  // Wie Tools\Rauchtest\lsp_rauchtest.py.
  cDprojText =
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '    <PropertyGroup>'#13#10 +
    '        <ProjectGuid>{6F1D2C3B-7A41-4B8E-9C55-1D2E3F405A62}</ProjectGuid>'#13#10 +
    '        <ProjectVersion>20.3</ProjectVersion>'#13#10 +
    '        <FrameworkType>None</FrameworkType>'#13#10 +
    '        <MainSource>Probe.dpr</MainSource>'#13#10 +
    '        <Base>True</Base>'#13#10 +
    '        <Config Condition="''$(Config)''==''''">Debug</Config>'#13#10 +
    '        <Platform Condition="''$(Platform)''==''''">Win32</Platform>'#13#10 +
    '        <TargetedPlatforms>1</TargetedPlatforms>'#13#10 +
    '        <AppType>Console</AppType>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <PropertyGroup Condition="''$(Base)''!=''''">'#13#10 +
    '        <DCC_Namespace>System;Winapi;System.Win;$(DCC_Namespace)</DCC_Namespace>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DelphiCompile Include="$(MainSource)">'#13#10 +
    '            <MainSource>MainSource</MainSource>'#13#10 +
    '        </DelphiCompile>'#13#10 +
    '        <DCCReference Include="UProbe.pas"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '    <ProjectExtensions>'#13#10 +
    '        <Borland.Personality>Delphi.Personality.12</Borland.Personality>'#13#10 +
    '        <Borland.ProjectType>Application</Borland.ProjectType>'#13#10 +
    '    </ProjectExtensions>'#13#10 +
    '</Project>'#13#10;

  // Rauchtest (S1): nur eigene Bezeichner, Zeilen und Spalten 0-basiert wie in LSP.
  cSmokeUnitText =
    'unit URauch;'#13#10 +                                          // 0
    'interface'#13#10 +                                             // 1
    'type'#13#10 +                                                  // 2
    '  TFoo = class'#13#10 +                                        // 3
    '  private'#13#10 +                                             // 4
    '    FWert: Integer;'#13#10 +                                   // 5
    '    FWeite: Integer;'#13#10 +                                  // 6
    '  public'#13#10 +                                              // 7
    '    procedure Setze(AWert: Integer; const AName: string);'#13#10 + // 8
    '    procedure Zwei;'#13#10 +                                   // 9
    '    procedure Drei;'#13#10 +                                   // 10
    '  end;'#13#10 +                                                // 11
    'implementation'#13#10 +                                        // 12
    'procedure TFoo.Setze(AWert: Integer; const AName: string);'#13#10 + // 13
    'begin'#13#10 +                                                 // 14
    '  FWert := AWert;'#13#10 +                                     // 15
    'end;'#13#10 +                                                  // 16
    'procedure TFoo.Zwei;'#13#10 +                                  // 17
    'begin'#13#10 +                                                 // 18
    '  Self.FWe'#13#10 +                                            // 19
    'end;'#13#10 +                                                  // 20
    'procedure TFoo.Drei;'#13#10 +                                  // 21
    'begin'#13#10 +                                                 // 22
    '  Setze(1, ''x'');'#13#10 +                                    // 23
    'end;'#13#10 +                                                  // 24
    'end.';                                                         // 25

  cTimeoutMs = 20000;
  /// <summary>So lange dürfen Threads des Servers nach dem Stopp noch auslaufen.</summary>
  cThreadSettleMs = 5000;

{ TLspInProcessServerTests }

procedure TLspInProcessServerTests.CreateProjectAndWarmUp;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-inprocess-' + IntToStr(MainThreadID));
  ForceDirectories(FFolder);
  FUnitFile := TPath.Combine(FFolder, 'UProbe.pas');
  FProjectFile := TPath.Combine(FFolder, 'Probe.dproj');
  TFile.WriteAllText(FUnitFile, cUnitText, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'Probe.dpr'), cDprText, TEncoding.UTF8);
  TFile.WriteAllText(FProjectFile, cDprojText, TEncoding.UTF8);
  try
    RunCycle;
  except
    // Scheitert der Lauf, meldet das der Test selbst.
    on Exception do
      ;
  end;
end;

procedure TLspInProcessServerTests.DeleteProject;
begin
  if (FFolder <> '') and TDirectory.Exists(FFolder) then
  try
    TDirectory.Delete(FFolder, True);
  except
    // Ein Rest im Temp-Ordner stört keinen Test.
    on Exception do
      ;
  end;
end;

function TLspInProcessServerTests.RunCycle: string;
var
  mServer: TLspInProcessServer;
  mServerRef: IDpccLspServer;
  mSession: TLspSession;
  mResponse: TJSONValue;
  mItem: TDpccCompletionItem;
  mNames: TStringList;
begin
  Result := '';
  mServer := TLspInProcessServer.Create;
  mServerRef := mServer;
  try
    Assert.IsTrue(mServerRef.Running, 'Server läuft nach dem Start');
    mSession := TLspSession.Create(mServerRef.Client, cTimeoutMs);
    try
      mSession.SetProjects([FProjectFile]);
      mSession.Initialize;
      Assert.IsTrue(mSession.Initialized, 'initialize beantwortet');
      // didOpen
      mSession.Sync(FUnitFile, cUnitText);
      // Hinter "  Self.FWe" (Zeile 11, Spalte 10).
      mResponse := mSession.Completion(FUnitFile, 11, 10, cTimeoutMs);
      mNames := TStringList.Create;
      try
        for mItem in TDpccServerCompletionProvider.ItemsFromLsp(mResponse) do
        begin
          mNames.Add(mItem.Name);
        end;
        mNames.Sort;
        Result := mNames.CommaText;
      finally
        mNames.Free;
        mResponse.Free;
      end;
      // Wie StopSessionNow im Plugin: Client schließen, Sitzung freigeben, dann den Server.
      mServerRef.Client.Close;
    finally
      mSession.Free;
    end;
  finally
    mServerRef := nil;
  end;
end;

procedure TLspInProcessServerTests.CompletesMembersInProcess;
var
  mNames: string;
begin
  mNames := RunCycle;
  Assert.Contains(mNames, 'FWert');
  Assert.Contains(mNames, 'FWeite');
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'Server abgemeldet');
end;

procedure TLspInProcessServerTests.StartsAndStopsThreeTimes;
var
  mThreads: Integer;
  mCycle: Integer;
  mStarted: UInt64;
begin
  mThreads := ProcessThreadCount;
  for mCycle := 1 to 3 do
  begin
    Assert.Contains(RunCycle, 'FWeite', Format('Lauf %d', [mCycle]));
    Assert.AreEqual(0, TShellInProcessServer.ActiveCount, Format('Lauf %d abgemeldet', [mCycle]));
  end;
  // Server-Thread, Verbindung, Worker-Pool, Dateibeobachter und Index-Threads sind fort.
  mStarted := TThread.GetTickCount64;
  while (ProcessThreadCount > mThreads) and (TThread.GetTickCount64 - mStarted < cThreadSettleMs) do
  begin
    TThread.Sleep(20);
  end;
  Assert.IsTrue(ProcessThreadCount <= mThreads, Format('Threads vorher %d, nachher %d', [mThreads,
    ProcessThreadCount]));
end;

procedure TLspInProcessServerTests.ExitClosesClient;
var
  mServer: TLspInProcessServer;
  mServerRef: IDpccLspServer;
  mSession: TLspSession;
  mStarted: UInt64;
  mInfo: TLspCloseInfo;
begin
  mServer := TLspInProcessServer.Create;
  mServerRef := mServer;
  try
    mSession := TLspSession.Create(mServerRef.Client, cTimeoutMs);
    try
      mSession.SetProjects([FProjectFile]);
      mSession.Initialize;
      // shutdown, dann exit: Der Server beendet seine Schleife selbst, ohne dass dpcc ihn abbaut.
      mServerRef.Client.Request('shutdown', nil, cTimeoutMs).Free;
      mServerRef.Client.Notify('exit', nil);
      mStarted := TThread.GetTickCount64;
      while not mServerRef.Client.Closed and (TThread.GetTickCount64 - mStarted < cTimeoutMs) do
      begin
        TThread.Sleep(10);
      end;
      Assert.IsTrue(mServerRef.Client.Closed, 'Client nach exit geschlossen');
      Assert.IsFalse(mServerRef.Running, 'Server läuft nicht mehr');
      mInfo := mServerRef.Client.CloseInfo;
      Assert.IsTrue(mInfo.ExitKnown, 'Exit-Code bekannt');
      Assert.AreEqual(Cardinal(0), mInfo.ExitCode, 'Exit-Code nach shutdown/exit');
    finally
      mSession.Free;
    end;
  finally
    mServerRef := nil;
  end;
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'Server abgemeldet');
end;

/// <summary>Einträge einer Antwort auf textDocument/completion (CompletionList oder CompletionItem[]); nil ohne.
/// </summary>
function CompletionItems(AResponse: TJSONValue): TJSONArray;
begin
  Result := nil;
  if AResponse is TJSONArray then
  begin
    Result := TJSONArray(AResponse);
  end
  else if AResponse is TJSONObject then
  begin
    Result := TJSONObject(AResponse).GetValue('items') as TJSONArray;
  end;
end;

procedure TLspInProcessServerTests.SmokeTestInProcess;
var
  mServer: TLspInProcessServer;
  mServerRef: IDpccLspServer;
  mSession: TLspSession;
  mUnitFile, mHover, mLabels: string;
  mResponse, mResolved, mSignature: TJSONValue;
  mItems, mSignatures: TJSONArray;
  mItem: TJSONValue;
  mPick: TJSONObject;
  mStarted: UInt64;
  mInfo: TLspCloseInfo;
begin
  mUnitFile := TPath.Combine(FFolder, 'URauch.pas');
  TFile.WriteAllText(mUnitFile, cSmokeUnitText, TEncoding.UTF8);
  mServer := TLspInProcessServer.Create;
  mServerRef := mServer;
  try
    mSession := TLspSession.Create(mServerRef.Client, cTimeoutMs);
    try
      // 1. initialize: Capabilities der Completion und die Produktversion in serverInfo.
      mSession.SetProjects([FProjectFile]);
      mSession.Initialize;
      Assert.IsTrue(mSession.Initialized, 'initialize beantwortet');
      Assert.IsTrue(mSession.Supports('completionProvider'), 'completionProvider');
      Assert.IsTrue(mSession.Supports('hoverProvider'), 'hoverProvider');
      Assert.IsTrue(mSession.Supports('signatureHelpProvider'), 'signatureHelpProvider');
      Assert.AreEqual(TDpccVersion.cVersion, mSession.ServerVersion, 'serverInfo.version');
      // 2. didOpen und completion hinter "  Self.FWe".
      mSession.Sync(mUnitFile, cSmokeUnitText);
      mResponse := mSession.Completion(mUnitFile, 19, 10, cTimeoutMs);
      try
        mItems := CompletionItems(mResponse);
        Assert.IsNotNull(mItems, 'completion liefert Einträge');
        mLabels := '|';
        mPick := nil;
        for mItem in mItems do
        begin
          if mItem is TJSONObject then
          begin
            mLabels := mLabels + TJSONObject(mItem).GetValue<string>('label', '') + '|';
            if TJSONObject(mItem).GetValue<string>('label', '') = 'FWeite' then
            begin
              mPick := TJSONObject(mItem);
            end;
          end;
        end;
        Assert.Contains(mLabels, '|FWert|', 'FWert');
        Assert.Contains(mLabels, '|FWeite|', 'FWeite');
        Assert.IsNotNull(mPick, 'Eintrag FWeite');
        // 3. completionItem/resolve auf demselben Eintrag (die Anfrage gibt ihre Parameter frei).
        mResolved := mSession.ResolveCompletion(TJSONObject(mPick.Clone), cTimeoutMs);
        try
          Assert.IsTrue(mResolved is TJSONObject, 'resolve beantwortet');
          Assert.AreEqual('FWeite', TJSONObject(mResolved).GetValue<string>('label', ''), 'resolve: label');
        finally
          mResolved.Free;
        end;
      finally
        mResponse.Free;
      end;
      // 4. hover auf "FWert" in "  FWert := AWert;".
      mHover := mSession.Hover(mUnitFile, cSmokeUnitText, 15, 3, cTimeoutMs);
      Assert.Contains(mHover, 'FWert', 'hover nennt das Feld');
      Assert.Contains(mHover, 'Integer', 'hover nennt den Typ');
      // 5. signatureHelp in "  Setze(1, |'x');".
      mSignature := mSession.SignatureHelp(mUnitFile, 23, 11, cTimeoutMs);
      try
        Assert.IsTrue(mSignature is TJSONObject, 'signatureHelp beantwortet');
        mSignatures := TJSONObject(mSignature).GetValue('signatures') as TJSONArray;
        Assert.IsTrue((mSignatures <> nil) and (mSignatures.Count > 0), 'signatureHelp liefert Signaturen');
        Assert.Contains(mSignatures.Items[0].GetValue<string>('label', ''), 'AName', 'Signatur von Setze');
        Assert.AreEqual(1, TJSONObject(mSignature).GetValue<Integer>('activeParameter', -1), 'zweiter Parameter');
      finally
        mSignature.Free;
      end;
      // 6. didSave: Benachrichtigung ohne Antwort; der Server arbeitet danach normal weiter.
      mSession.Saved(mUnitFile);
      mResponse := mSession.Completion(mUnitFile, 19, 10, cTimeoutMs);
      try
        Assert.IsNotNull(CompletionItems(mResponse), 'completion nach didSave');
      finally
        mResponse.Free;
      end;
      Assert.IsTrue(mServerRef.Running, 'Server läuft nach didSave');
      // 7. shutdown und exit: Der Server beendet seine Schleife selbst mit Exit-Code 0.
      mServerRef.Client.Request('shutdown', nil, cTimeoutMs).Free;
      mServerRef.Client.Notify('exit', nil);
      mStarted := TThread.GetTickCount64;
      while not mServerRef.Client.Closed and (TThread.GetTickCount64 - mStarted < cTimeoutMs) do
      begin
        TThread.Sleep(10);
      end;
      Assert.IsTrue(mServerRef.Client.Closed, 'Client nach exit geschlossen');
      mInfo := mServerRef.Client.CloseInfo;
      Assert.IsTrue(mInfo.ExitKnown, 'Exit-Code bekannt');
      Assert.AreEqual(Cardinal(0), mInfo.ExitCode, 'Exit-Code nach shutdown/exit');
    finally
      mSession.Free;
    end;
  finally
    mServerRef := nil;
  end;
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'Server abgemeldet');
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInProcessServerTests);

end.
