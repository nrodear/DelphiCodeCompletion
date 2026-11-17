unit dpcc.Core.Completion.Fallback.Tests;

// Zweites Strg+Leertaste öffnet die Liste der IDE (L3), ohne IDE: Merker TDpccCompletionFallback für sich, die Meldung
// OnSettled des Controllers (leer auch nach Fehler oder Zeitlimit einer Quelle) und beides zusammen wie im Editor.
// L4 (TDpccIdeList): Ist dpcc der gewählte Code-Insight-Anbieter, bleibt der zweite Druck bei dpcc und der Hinweis
// entfällt; bei offener Liste der IDE gehört ihr die Taste, dpcc öffnet keine zweite Liste.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccCompletionFallbackTests = class
  public
    [Test]
    procedure EmptyResultHandsSecondPressToIde;
    [Test]
    procedure ResultWithItemsKeepsDpcc;
    [Test]
    procedure InputInBetweenKeepsDpcc;
    [Test]
    procedure OtherPlaceKeepsDpcc;
    [Test]
    procedure PendingResultKeepsDpcc;
    [Test]
    procedure LateResultAfterInputIsIgnored;
    [Test]
    procedure HandOverResetsState;
    [Test]
    procedure NotificationWithoutChangeKeepsState;
    [Test]
    procedure ViewChangeResetsState;
    [Test]
    procedure HintTextInBothLanguages;
    /// <summary>L4: dpcc ist der gewählte Anbieter (Liste der IDE nicht erreichbar): kein Hinweis, der zweite Druck
    /// fragt wieder dpcc (durchgereicht käme er ohnehin bei dpcc an).</summary>
    [Test]
    procedure SelectedManagerKeepsSecondPressWithoutHint;
    /// <summary>L4: Liste der IDE offen: Strg+Leertaste gehört ihr, auch ohne leeres Ergebnis davor und auch, wenn
    /// eine Abfrage von dpcc aussteht; der Merker ist danach leer.</summary>
    [Test]
    procedure OpenIdeListTakesTheKey;
    /// <summary>L4: Die alte Form Press(APlace) verhält sich wie mit erreichbarer, geschlossener Liste der IDE.
    /// </summary>
    [Test]
    procedure UsualIdeListIsReachableAndClosed;
  end;

  /// <summary>OnSettled des Controllers und der Ablauf wie im Editor.</summary>
  [TestFixture]
  TDpccCompletionSettledTests = class
  public
    [Test]
    procedure EmptyResultSettlesEmpty;
    [Test]
    procedure ItemsSettleNotEmpty;
    [Test]
    procedure NoMatchSettlesEmpty;
    [Test]
    procedure ErrorSettlesEmpty;
    [Test]
    procedure TimeoutSettlesEmpty;
    [Test]
    procedure SecondPressAfterEmptyResultGoesToIde;
    [Test]
    procedure PressWhileLoadingStaysWithDpcc;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Internals.Async,
  dpcc.Core.Completion.Controller,
  dpcc.Core.Completion.Fallback,
  dpcc.Core.Completion.Providers.Fixed,
  dpcc.UI.Strings,
  dpcc.UI.Completion.Strings;

const
  cFile = 'C:\P\Unit1.pas';
  cLine = 'begin Foo. end;';

type
  /// <summary>Ansicht, die nur den leeren Zustand mitschreibt.</summary>
  TSettledView = class(TInterfacedObject, IDpccCompletionView)
  public
    Empty: Boolean;
    procedure ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
  end;

  /// <summary>Quelle, deren Anfrage scheitert (Server weg, Zeitlimit des Servers); zählt wie beim Server nicht als
  /// Fehler der Quelle.</summary>
  TFailingProvider = class(TDpccAsyncCompletionProvider)
  protected
    function IsFailure(AE: Exception): Boolean; override;
    function Fetch(const AContext: TDpccContext; AData: TObject; const ACancelled: TDpccCancelledFunc;
      const AEmit: TDpccEmitProc; out AState: TDpccFetchState): TDpccCompletionItems; override;
  end;

procedure TSettledView.ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
begin
  Empty := False;
end;

procedure TSettledView.HideList;
begin
  Empty := False;
end;

procedure TSettledView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
  Empty := True;
end;

function TSettledView.PageSize: Integer;
begin
  Result := 3;
end;

function TFailingProvider.IsFailure(AE: Exception): Boolean;
begin
  Result := False;
end;

function TFailingProvider.Fetch(const AContext: TDpccContext; AData: TObject; const ACancelled: TDpccCancelledFunc;
  const AEmit: TDpccEmitProc; out AState: TDpccFetchState): TDpccCompletionItems;
begin
  AState := Default(TDpccFetchState);
  Result := nil;
  if not ACancelled() then
  begin
    raise Exception.Create('Zeitlimit der Anfrage');
  end;
end;

/// <summary>Stelle in cFile, Zeile 3.</summary>
function Place(ACharacter: Integer; const ALineText: string = cLine): TDpccCompletionPlace;
begin
  Result := TDpccCompletionPlace.At(cFile, 3, ACharacter, ALineText);
end;

function Item(const AName: string): TDpccCompletionItem;
begin
  Result := Default(TDpccCompletionItem);
  Result.Name := AName;
end;

/// <summary>Kontext wie Strg+Leertaste an Zeile 3, Zeichen 10 von cFile.</summary>
function Context(const APrefix: string): TDpccContext;
begin
  Result := Default(TDpccContext);
  Result.FileName := cFile;
  Result.Line := 2;
  Result.Character := 10;
  Result.Prefix := APrefix;
end;

/// <summary>Arbeitet eingereihte Aufrufe ab, bis ACondition gilt oder die Zeit um ist.</summary>
function WaitFor(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal = 3000): Boolean;
var
  mStart: UInt64;
begin
  mStart := TThread.GetTickCount64;
  repeat
    CheckSynchronize(5);
    if ACondition() then
    begin
      Exit(True);
    end;
  until TThread.GetTickCount64 - mStart > ATimeoutMs;
  Result := False;
end;

/// <summary>Startet AController an Context(APrefix), wartet auf den Abschluss und liefert, wie oft OnSettled kam und
/// mit welchem Wert zuletzt.</summary>
procedure RunQuery(AController: TDpccCompletionController; const APrefix: string; out ACount: Integer;
  out AEmpty: Boolean);
var
  mCount: Integer;
  mEmpty: Boolean;
begin
  mCount := 0;
  mEmpty := False;
  AController.OnSettled :=
    procedure(ASettledEmpty: Boolean)
    begin
      Inc(mCount);
      mEmpty := ASettledEmpty;
    end;
  AController.Start(Context(APrefix));
  Assert.IsTrue(WaitFor(
    function: Boolean
    begin
      Result := mCount > 0;
    end), 'Abfrage abgeschlossen');
  // Kommt nichts mehr nach: genau eine Meldung je Start.
  CheckSynchronize(20);
  ACount := mCount;
  AEmpty := mEmpty;
  AController.OnSettled := nil;
end;

{ TDpccCompletionFallbackTests }

procedure TDpccCompletionFallbackTests.EmptyResultHandsSecondPressToIde;
var
  mFallback: TDpccCompletionFallback;
begin
  mFallback := TDpccCompletionFallback.Create;
  try
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Dpcc, 'erstes Drücken fragt dpcc');
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Pending, 'wartet auf das Ergebnis');
    Assert.IsTrue(mFallback.Settled(True), 'leeres Ergebnis: Hinweis zeigen');
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Empty);
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Ide, 'zweites Drücken: Liste der IDE');
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.ResultWithItemsKeepsDpcc;
var
  mFallback: TDpccCompletionFallback;
begin
  mFallback := TDpccCompletionFallback.Create;
  try
    mFallback.Press(Place(10));
    Assert.IsFalse(mFallback.Settled(False), 'Einträge: kein Hinweis');
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Idle);
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Dpcc, 'Liste war nicht leer: wieder dpcc');
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.InputInBetweenKeepsDpcc;
var
  mFallback: TDpccCompletionFallback;
begin
  mFallback := TDpccCompletionFallback.Create;
  try
    mFallback.Press(Place(10));
    mFallback.Settled(True);
    // "x" getippt und wieder gelöscht: Stelle und Zeile sind danach wie vorher, die Eingabe zählt trotzdem.
    mFallback.Edited(Place(11, 'begin Foo.x end;'));
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Idle, 'Eingabe verwirft den Merker');
    mFallback.Edited(Place(10));
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Dpcc, 'nach Eingabe wieder dpcc');
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.OtherPlaceKeepsDpcc;
var
  mFallback: TDpccCompletionFallback;

  procedure Arm;
  begin
    mFallback.Press(Place(10));
    mFallback.Settled(True);
  end;

begin
  mFallback := TDpccCompletionFallback.Create;
  try
    Arm;
    Assert.IsTrue(mFallback.Press(Place(4)) = TDpccCompletionRoute.Dpcc, 'anderes Zeichen');
    Arm;
    Assert.IsTrue(mFallback.Press(TDpccCompletionPlace.At(cFile, 4, 10, cLine)) = TDpccCompletionRoute.Dpcc,
      'andere Zeile');
    Arm;
    Assert.IsTrue(mFallback.Press(TDpccCompletionPlace.At('C:\P\Unit2.pas', 3, 10, cLine)) =
      TDpccCompletionRoute.Dpcc, 'andere Datei');
    Arm;
    Assert.IsTrue(mFallback.Press(Place(10, 'begin Bar. end;')) = TDpccCompletionRoute.Dpcc, 'anderer Zeilentext');
    // Der Druck an der anderen Stelle wartet jetzt selbst; die alte Stelle zählt nicht mehr.
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Pending);
    Assert.AreEqual('begin Bar. end;', mFallback.Place.LineText);
    Arm;
    Assert.IsTrue(mFallback.Press(TDpccCompletionPlace.At('c:\p\UNIT1.PAS', 3, 10, cLine)) =
      TDpccCompletionRoute.Ide, 'Dateiname ohne Groß/klein');
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.PendingResultKeepsDpcc;
var
  mFallback: TDpccCompletionFallback;
begin
  mFallback := TDpccCompletionFallback.Create;
  try
    mFallback.Press(Place(10));
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Dpcc, 'Ergebnis steht aus: nie die IDE');
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Pending);
    Assert.IsTrue(mFallback.Settled(True));
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Ide, 'erst nach dem Ergebnis');
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.LateResultAfterInputIsIgnored;
var
  mFallback: TDpccCompletionFallback;
begin
  mFallback := TDpccCompletionFallback.Create;
  try
    mFallback.Press(Place(10));
    mFallback.Edited(Place(11, 'begin Foo.x end;'));
    Assert.IsFalse(mFallback.Settled(True), 'Ergebnis nach Eingabe: kein Hinweis');
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Idle);
    // Ohne Druck vorher zählt ein Ergebnis nie (etwa nach "." automatisch geöffnet).
    Assert.IsFalse(mFallback.Settled(True));
    Assert.IsTrue(mFallback.Press(Place(11, 'begin Foo.x end;')) = TDpccCompletionRoute.Dpcc);
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.HandOverResetsState;
var
  mFallback: TDpccCompletionFallback;
begin
  mFallback := TDpccCompletionFallback.Create;
  try
    mFallback.Press(Place(10));
    mFallback.Settled(True);
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Ide);
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Idle, 'nach dem Durchreichen zurückgesetzt');
    Assert.AreEqual('', mFallback.Place.FileName);
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Dpcc, 'drittes Drücken fragt wieder dpcc');
    Assert.IsTrue(mFallback.Settled(True), 'und merkt ein leeres Ergebnis erneut');
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.NotificationWithoutChangeKeepsState;
var
  mFallback: TDpccCompletionFallback;
begin
  mFallback := TDpccCompletionFallback.Create;
  try
    mFallback.Press(Place(10));
    mFallback.Settled(True);
    // Meldung "geändert" ohne Änderung an der Stelle.
    mFallback.Edited(Place(10));
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Empty);
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Ide);
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.ViewChangeResetsState;
var
  mFallback: TDpccCompletionFallback;
begin
  mFallback := TDpccCompletionFallback.Create;
  try
    mFallback.Press(Place(10));
    mFallback.Settled(True);
    mFallback.Reset;
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Idle);
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Dpcc, 'anderer Reiter dazwischen: dpcc');
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.HintTextInBothLanguages;
var
  mSaved: TDpccLanguage;
begin
  mSaved := TDpccStrings.Language;
  try
    TDpccStrings.Language := TDpccLanguage.German;
    Assert.AreEqual('Strg+Leertaste erneut für die Liste der IDE',
      TDpccCompletionStrings.Text(TDpccCompletionTextId.IdeListAgain));
    TDpccStrings.Language := TDpccLanguage.English;
    Assert.AreEqual('Press Ctrl+Space again for the IDE list',
      TDpccCompletionStrings.Text(TDpccCompletionTextId.IdeListAgain));
  finally
    TDpccStrings.Language := mSaved;
  end;
end;

procedure TDpccCompletionFallbackTests.SelectedManagerKeepsSecondPressWithoutHint;
var
  mFallback: TDpccCompletionFallback;
  mSelected: TDpccIdeList;
begin
  mSelected := TDpccIdeList.Create(False, False);
  mFallback := TDpccCompletionFallback.Create;
  try
    Assert.IsTrue(mFallback.Press(Place(10), mSelected) = TDpccCompletionRoute.Dpcc, 'erstes Drücken fragt dpcc');
    Assert.IsFalse(mFallback.Settled(True), 'leeres Ergebnis: kein Hinweis auf die Liste der IDE');
    Assert.IsTrue(mFallback.Press(Place(10), mSelected) = TDpccCompletionRoute.Dpcc,
      'zweites Drücken bleibt bei dpcc');
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Pending, 'wartet wieder auf das Ergebnis');
    Assert.IsFalse(mFallback.Settled(True), 'auch beim zweiten leeren Ergebnis kein Hinweis');
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.OpenIdeListTakesTheKey;
var
  mFallback: TDpccCompletionFallback;
begin
  mFallback := TDpccCompletionFallback.Create;
  try
    Assert.IsTrue(mFallback.Press(Place(10), TDpccIdeList.Create(True, True)) = TDpccCompletionRoute.Ide,
      'offene Liste der IDE: keine zweite Liste von dpcc');
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Idle);
    Assert.IsTrue(mFallback.Press(Place(10), TDpccIdeList.Usual) = TDpccCompletionRoute.Dpcc, 'danach wieder dpcc');
    Assert.IsTrue(mFallback.Press(Place(10), TDpccIdeList.Create(True, True)) = TDpccCompletionRoute.Ide,
      'auch während eine Abfrage aussteht');
    Assert.IsTrue(mFallback.State = TDpccFallbackState.Idle, 'Merker leer');
    Assert.IsFalse(mFallback.Settled(True), 'das späte Ergebnis zählt nicht mehr');
  finally
    mFallback.Free;
  end;
end;

procedure TDpccCompletionFallbackTests.UsualIdeListIsReachableAndClosed;
var
  mFallback: TDpccCompletionFallback;
begin
  Assert.IsTrue(TDpccIdeList.Usual.Reachable, 'erreichbar');
  Assert.IsFalse(TDpccIdeList.Usual.Open, 'geschlossen');
  mFallback := TDpccCompletionFallback.Create;
  try
    mFallback.Press(Place(10), TDpccIdeList.Usual);
    Assert.IsTrue(mFallback.Settled(True), 'Hinweis wie in L3');
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Ide, 'zweites Drücken: Liste der IDE');
  finally
    mFallback.Free;
  end;
end;

{ TDpccCompletionSettledTests }

procedure TDpccCompletionSettledTests.EmptyResultSettlesEmpty;
var
  mView: TSettledView;
  mViewRef: IDpccCompletionView;
  mController: TDpccCompletionController;
  mCount: Integer;
  mEmpty: Boolean;
begin
  mView := TSettledView.Create;
  mViewRef := mView;
  mController := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create(nil) as IDpccCompletionProvider, mViewRef);
  try
    RunQuery(mController, '', mCount, mEmpty);
    Assert.AreEqual(1, mCount, 'eine Meldung je Abfrage');
    Assert.IsTrue(mEmpty, 'kein Kontext, keine Einträge: leer');
    Assert.IsTrue(mView.Empty, 'leerer Zustand sichtbar');
  finally
    mController.Free;
  end;
end;

procedure TDpccCompletionSettledTests.ItemsSettleNotEmpty;
var
  mViewRef: IDpccCompletionView;
  mController: TDpccCompletionController;
  mCount: Integer;
  mEmpty: Boolean;
begin
  mViewRef := TSettledView.Create;
  mController := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('Add'), Item('Assign')]) as IDpccCompletionProvider, mViewRef);
  try
    RunQuery(mController, '', mCount, mEmpty);
    Assert.AreEqual(1, mCount);
    Assert.IsFalse(mEmpty, 'Liste mit Einträgen');
  finally
    mController.Free;
  end;
end;

procedure TDpccCompletionSettledTests.NoMatchSettlesEmpty;
var
  mViewRef: IDpccCompletionView;
  mController: TDpccCompletionController;
  mCount: Integer;
  mEmpty: Boolean;
begin
  mViewRef := TSettledView.Create;
  mController := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('Add')]) as IDpccCompletionProvider, mViewRef);
  try
    // Einträge kommen, aber keiner passt zum Getippten: Die Liste zeigt den leeren Zustand.
    RunQuery(mController, 'xyz', mCount, mEmpty);
    Assert.AreEqual(1, mCount);
    Assert.IsTrue(mEmpty);
  finally
    mController.Free;
  end;
end;

procedure TDpccCompletionSettledTests.ErrorSettlesEmpty;
var
  mViewRef: IDpccCompletionView;
  mController: TDpccCompletionController;
  mCount: Integer;
  mEmpty: Boolean;
begin
  mViewRef := TSettledView.Create;
  mController := TDpccCompletionController.Create(TFailingProvider.Create as IDpccCompletionProvider, mViewRef);
  try
    RunQuery(mController, '', mCount, mEmpty);
    Assert.AreEqual(1, mCount, 'Fehler der Quelle schließt die Abfrage ab');
    Assert.IsTrue(mEmpty, 'Fehler zählt als leer');
  finally
    mController.Free;
  end;
end;

procedure TDpccCompletionSettledTests.TimeoutSettlesEmpty;
var
  mViewRef: IDpccCompletionView;
  mController: TDpccCompletionController;
  mCount: Integer;
  mEmpty: Boolean;
begin
  mViewRef := TSettledView.Create;
  // Wie der Server nach seinem Zeitlimit: spät und ohne Einträge.
  mController := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create(nil, 100) as IDpccCompletionProvider, mViewRef);
  try
    RunQuery(mController, 'Fo', mCount, mEmpty);
    Assert.AreEqual(1, mCount);
    Assert.IsTrue(mEmpty, 'Zeitlimit zählt als leer');
  finally
    mController.Free;
  end;
end;

procedure TDpccCompletionSettledTests.SecondPressAfterEmptyResultGoesToIde;
var
  mViewRef: IDpccCompletionView;
  mController: TDpccCompletionController;
  mFallback: TDpccCompletionFallback;
  mHints: Integer;
begin
  mViewRef := TSettledView.Create;
  mFallback := TDpccCompletionFallback.Create;
  mController := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create(nil, 50) as IDpccCompletionProvider, mViewRef);
  try
    mHints := 0;
    // Wie dpcc.IDE.Completion.EditorState.WireFallback.
    mController.OnSettled :=
      procedure(AEmpty: Boolean)
      begin
        if mFallback.Settled(AEmpty) then
        begin
          Inc(mHints);
        end;
      end;
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Dpcc);
    mController.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := mHints > 0;
      end), 'Hinweis nach dem leeren Ergebnis');
    Assert.AreEqual(1, mHints);
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Ide, 'zweites Drücken: Liste der IDE');
  finally
    mController.OnSettled := nil;
    mController.Free;
    mFallback.Free;
  end;
end;

procedure TDpccCompletionSettledTests.PressWhileLoadingStaysWithDpcc;
var
  mViewRef: IDpccCompletionView;
  mController: TDpccCompletionController;
  mFallback: TDpccCompletionFallback;
  mHints: Integer;
begin
  mViewRef := TSettledView.Create;
  mFallback := TDpccCompletionFallback.Create;
  mController := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create(nil, 200) as IDpccCompletionProvider, mViewRef);
  try
    mHints := 0;
    mController.OnSettled :=
      procedure(AEmpty: Boolean)
      begin
        if mFallback.Settled(AEmpty) then
        begin
          Inc(mHints);
        end;
      end;
    mFallback.Press(Place(10));
    mController.Start(Context(''));
    Assert.IsTrue(mController.Loading, 'Ergebnis kommt erst nach dem Tastendruck');
    // Zweiter Druck, bevor das Ergebnis da ist: dpcc fragt erneut, die IDE bekommt die Taste nicht.
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Dpcc);
    mController.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not mController.Loading;
      end));
    CheckSynchronize(20);
    Assert.AreEqual(1, mHints, 'nur das Ergebnis der letzten Anfrage zählt');
    Assert.IsTrue(mFallback.Press(Place(10)) = TDpccCompletionRoute.Ide);
  finally
    mController.OnSettled := nil;
    mController.Free;
    mFallback.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccCompletionFallbackTests);
  TDUnitX.RegisterTestFixture(TDpccCompletionSettledTests);

end.
