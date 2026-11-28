unit dpcc.Core.Lsp.GotoMatrix.Tests;

// Sprungmatrix für Strg+Klick: alle Varianten „von → nach und
// zurück“ auf dem Weg der IDE, wie dpcc.Core.Lsp.GotoBothWays.Tests, aber in einem Projekt mit mehreren Units, Suchpfad
// und Include-Dateien (dpcc.Core.Lsp.GotoMatrix.Fixtures), dazu Routinen der installierten RTL (Abschnitt E, Rumpf
// einer Bibliotheks-Routine). Je Variante ein eigener Test (Name = Zeile von TJumpCase),
// damit ein roter Test sofort sagt, welche Variante bricht.
// Weg: TLspSession.Sync der Datei, in der geklickt wird (wie der Hauptthread für den aktiven Puffer), dann
// GotoTargetAt mit der Zeile aus dem abgeglichenen Text (declaration, bei OnTarget auch definition) gegen den echten
// Completion-Server im eigenen Prozess. Rückweg: derselbe Ablauf an der Stelle des Ziels (Gegensprung). Den
// Sprungverlauf der IDE (zurück zur Ausgangsstelle) gibt es hier nicht; er ist nur in der IDE prüfbar.
// Geprüft wird je Richtung „Datei Zeile:Zeichen“ (Zeile und Zeichen 0-basiert, UTF-16 wie im LSP; Datei relativ zum
// Projektordner). Kein Ziel erwartet: kein Ziel, keine Ausnahme und Antwort binnen cNoHangMs.
// Jeder Test startet einen eigenen Server und wartet auf den Index (außer FileDuringIndexBuild); er baut ihn vor der
// Prüfung wieder ab (LEAK1 wie CheckPairs in GotoBothWays): Der Indexaufbau liefe sonst über das Testende hinaus.
// Die Erwartung ist das GEWÜNSCHTE Verhalten (Entscheidungen des Nutzers im Kopf der Fixtures-Unit). Ein roter Test
// ist ein Befund; die Meldung nennt beide Richtungen, die Dauer und den Grund aus dpcc/noTarget. Kategorien:
// Verdacht (fachlich richtige Erwartung zu einem Verdacht aus Phase 1), NeueErwartung (vom Nutzer neu festgelegt,
// Umsetzung folgt), HeutigesVerhalten (nicht vom Nutzer entschieden, hält das heutige Verhalten fest); beide ersten
// dürfen rot sein, bis der Fehler behoben ist.
// FileDuringIndexBuild: Strg+Klick ohne Warten auf den Index. Erwartet sofort kein Ziel mit Indexing = True und eine
// Meldung, die zum erneuten Klick auffordert (deutsch „erneut“, englisch „again“) statt „Kein Sprungziel“. Ist der
// Index beim Klick schon fertig, ist der Fall nicht nachgestellt (Assert.Pass).

interface

uses
  DUnitX.TestFramework,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.Session.Json,
  dpcc.Core.Lsp.LateAnswers,
  dpcc.Core.Lsp.GotoMatrix.Fixtures;

type
  /// <summary>Stelle eines Namens: Datei (relativ), Zeile und Zeichen seines Anfangs (0-basiert), Länge.</summary>
  TJumpSpot = record
    FileName: string;
    Line: Integer;
    Character: Integer;
    NameLength: Integer;
  end;

  [TestFixture]
  TGotoMatrixTests = class
  private
    FRoot: string;
    FFolder: string;
    FSetup: TJumpSetup;
    FFiles: TArray<TJumpFile>;
    FServerRef: IDpccLspServer;
    FSession: TLspSession;
    FErrors: string;
    /// <summary>Projekt zu ASetup schreiben, Server starten, initialize; auf den Index warten (außer NoIndexWait).
    /// </summary>
    procedure Start(ASetup: TJumpSetup);
    /// <summary>Wie StopSessionNow im Plugin: Client schließen, Sitzung freigeben, dann den Server.</summary>
    procedure Stop;
    /// <summary>Bis die uses-Zeile von UNutzer UBasis auflöst (Index fertig), höchstens cIndexWaitMs.</summary>
    procedure WaitForIndex;
    function FolderOf(ASetup: TJumpSetup): string;
    function FileIndex(const AName: string): Integer;
    /// <summary>Text der Datei, wie die IDE ihn hat: der Puffer, sonst der Text auf der Platte.</summary>
    function TextOf(const AName: string): string;
    /// <summary>Pfad der Datei, wie die IDE ihn übergibt (in den Pfadtests andere Schreibweise).</summary>
    function PathOf(const AName: string): string;
    function LineText(const AName: string; ALine: Integer): string;
    function SpotOf(const AName, AMarker, AWord: string): TJumpSpot;
    /// <summary>Strg+Klick an ASpot wie im Plugin; False ohne Ziel oder bei Ausnahme (dann in FErrors).</summary>
    function JumpFrom(const ASpot: TJumpSpot; AClick: TJumpClick; out ALocation: TLspLocation;
      out ANoTarget: TDpccNoTarget; out AElapsedMs: Int64): Boolean;
    /// <summary>Ziel als „Datei Zeile:Zeichen“ (Datei relativ zum Projekt, sonst voller Pfad).</summary>
    function PlaceText(AFound: Boolean; const ALocation: TLspLocation; ACharacter: Boolean;
      AFileOnly: Boolean): string;
    function SpotText(const ASpot: TJumpSpot; ACharacter: Boolean): string;
    /// <summary>Erwartetes Ziel der Zeile ARow (Unit-Ziel: Zeile 0, Zeichen 0).</summary>
    function TargetSpot(const ARow: TJumpRow): TJumpSpot;
    procedure Run(ACase: TJumpCase);
    /// <summary>Pfad der RTL-Unit zum Platzhalter (TJumpFixture.cLibSysUtils, cLibClasses): wohin der Sprung aus der
    /// uses-Liste von UBibliothek führt. Die Datei kommt mit ihrem Text (Zeilenenden LF) als TJumpFile unter ihrem
    /// vollen Pfad dazu, damit Marker, Sync und Rückweg wie bei Projektdateien gehen.</summary>
    function LibraryFile(const APlaceholder: string): string;
    /// <summary>Ersetzt die Platzhalter in den Dateien von ARow durch die Pfade (LibraryFile).</summary>
    procedure ResolveLibrary(var ARow: TJumpRow);
  public
    [SetupFixture]
    procedure CreateRoot;
    [TearDownFixture]
    procedure DeleteRoot;
    [TearDown]
    procedure StopServer;

    [Test]
    procedure DeclImplOverrideInDescendant;
    [Test]
    procedure DeclImplMethodOverloadInOtherUnit;
    [Test]
    procedure DeclImplOverrideOfAbstractOverload;
    [Test]
    procedure DeclImplClassHelper;
    [Test]
    procedure DeclImplRecordHelper;
    [Test]
    procedure DeclImplPropertyGetter;
    [Test]
    procedure DeclImplFreeOverloadSameParamNameInteger;
    [Test]
    procedure DeclImplFreeOverloadSameParamNameDouble;
    [Test]
    procedure DeclImplExternalInImplementation;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure DeclImplAbstractOverloadFirstStays;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure DeclImplAbstractOverloadSecondStays;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure DeclImplInterfaceOverloadFirstStays;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure DeclImplInterfaceOverloadSecondStays;
    [Test]
    procedure DeclImplInterfaceMethodStays;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure DeclImplPlainAndGenericSameNamePlain;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure DeclImplPlainAndGenericSameNameGeneric;
    [Test]
    procedure DeclImplLastLineOfFile;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure DeclImplMethodFromIncludeInClassBody;
    [Test]
    procedure DeclImplFreeRoutineFromInclude;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure DeclImplBackFromIncludeFile;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure DeclImplDprojWithDotSegments;
    [Test]
    procedure UsageLocalVariable;
    [Test]
    procedure UsageParameter;
    [Test]
    procedure UsageInheritedField;
    [Test]
    procedure UsagePropertyImplicit;
    [Test]
    procedure UsagePropertyViaSelf;
    [Test]
    procedure UsageConstant;
    [Test]
    procedure UsageGetterOnPropertyLine;
    [Test]
    procedure UsageSetterOnPropertyLine;
    [Test]
    procedure UsageFieldOnPropertyLine;
    [Test]
    procedure UsageEnumUnscoped;
    [Test]
    procedure UsageEnumScopedTypePart;
    [Test]
    procedure UsageEnumScopedValuePart;
    [Test]
    procedure UsageTypeInClassHeading;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure UsageTypeOtherUnit;
    [Test]
    procedure UsageMethodImplicitSelf;
    [Test]
    procedure UsageMethodExplicitSelf;
    [Test]
    procedure UsageSelf;
    [Test]
    procedure UsageInheritedWithName;
    /// <summary>Neue Erwartung des Nutzers (Umsetzung in Phase 2b), darf rot sein.</summary>
    [Test]
    [Category('NeueErwartung')]
    procedure UsageInheritedBare;
    [Test]
    procedure UsageInterfaceMethod;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure UsageInterfaceOverloadString;
    [Test]
    procedure UsageOverloadInteger;
    [Test]
    procedure UsageOverloadString;
    [Test]
    procedure UsageClassHelper;
    [Test]
    procedure UsageRecordHelper;
    [Test]
    procedure UsageFreeRoutineOtherUnit;
    [Test]
    procedure UsageFreeOverloadInteger;
    [Test]
    procedure UsageFreeOverloadDouble;
    [Test]
    procedure UsageQualifiedUnitPart;
    [Test]
    procedure UsageQualifiedRoutinePart;
    [Test]
    procedure UsageQualifiedConstantPart;
    [Test]
    procedure UsageWithMember;
    [Test]
    procedure UsageWithProperty;
    [Test]
    procedure UsageSearchPathRoutine;
    [Test]
    procedure UsageUsesSearchPathUnit;
    [Test]
    procedure UsageUsesProjectUnit;
    [Test]
    procedure UsageUsesRtlUnit;
    /// <summary>Erwartung = heutiges Verhalten, nicht vom Nutzer entschieden.</summary>
    [Test]
    [Category('HeutigesVerhalten')]
    procedure UsageUsesDottedFirstPart;
    [Test]
    procedure UsageRtlRoutine;
    /// <summary>Neue Erwartung des Nutzers (Umsetzung in Phase 2b), darf rot sein.</summary>
    [Test]
    [Category('NeueErwartung')]
    procedure UsageIncludeDirectiveOpensFile;
    /// <summary>Neue Erwartung des Nutzers (Umsetzung in Phase 2b), darf rot sein.</summary>
    [Test]
    [Category('NeueErwartung')]
    procedure UsageIncludeDirectiveLongFormOpensFile;
    [Test]
    procedure UsageIncludeRoutine;
    [Test]
    procedure UsageIncludeMethod;
    [Test]
    procedure UsageNestedRoutine;
    /// <summary>Erwartung = heutiges Verhalten, nicht vom Nutzer entschieden.</summary>
    [Test]
    [Category('HeutigesVerhalten')]
    procedure UsageResult;
    [Test]
    procedure UsageLastLineRoutine;
    [Test]
    procedure UsageClickLastCharacter;
    [Test]
    procedure UsageClickBehindName;
    [Test]
    procedure UsageAtLineStart;
    [Test]
    procedure UsageAtLineEndLastCharacter;
    [Test]
    procedure UsageAtLineEndBehind;
    [Test]
    procedure FileSourceBufferShifted;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure FileTargetBufferShifted;
    [Test]
    procedure FileTargetUtf8WithBom;
    [Test]
    procedure FileTargetUtf8WithoutBom;
    [Test]
    procedure FileTargetAnsi;
    [Test]
    procedure FileTargetTabsBeforeName;
    [Test]
    procedure FileTargetLfOnly;
    [Test]
    procedure FilePathCaseDiffers;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, darf rot sein.</summary>
    [Test]
    [Category('Verdacht')]
    procedure FilePathShortForm;
    /// <summary>Neue Erwartung des Nutzers (Umsetzung in Phase 2b), darf rot sein.</summary>
    [Test]
    [Category('NeueErwartung')]
    procedure FileDuringIndexBuild;
    [Test]
    procedure NegativeKeyword;
    [Test]
    procedure NegativeComment;
    [Test]
    procedure NegativeString;
    [Test]
    procedure NegativeNumber;
    [Test]
    procedure NegativeUnknownName;
    [Test]
    procedure NegativeResourceDirective;
    [Test]
    procedure NegativeOperator;
    [Test]
    procedure NegativePastLineEnd;
    // E. Bibliothek
    [Test]
    procedure LibraryCallToDeclarationThenBody;
    [Test]
    procedure LibraryBodyToDeclaration;
    [Test]
    procedure LibraryOverloadInt64FromDeclaration;
    [Test]
    procedure LibraryOverloadFormat;
    [Test]
    procedure LibraryMethodOfClass;
    [Test]
    procedure LibraryAbstractMethodStays;
    /// <summary>textDocument/definition auf einem Aufruf einer RTL-Routine führt wie DelphiLSP zum Anfang der Zeile
    /// ihres Rumpfs (Kern, auch dpcc.LspServer.exe), declaration zur Deklaration; eine Routine ohne Rumpf bleibt bei
    /// der Deklaration.</summary>
    [Test]
    procedure LibraryDefinitionRequestToBody;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  dpcc.Core.Lsp.Adapters.InProcess,
  dpcc.Core.Editor.Navigation,
  dpcc.Core.Localization.Language,
  dpcc.Text.Lines,
  dpcc.Text.Uris;

const
  cTimeoutMs = 20000;
  cIndexWaitMs = 30000;
  /// <summary>Ohne Ziel muss die Antwort so schnell kommen (kein Hänger, kein Warten bis zum Zeitlimit).</summary>
  cNoHangMs = 3000;
  /// <summary>Über der Entprellung der Index-Aktualisierung aus ungespeichertem Text (500 ms, IndexRefresh).</summary>
  cBufferRefreshMs = 1500;
  /// <summary>Ordner mit Leerzeichen und langem Namen: hat eine 8.3-Kurzform, wo das Dateisystem sie anlegt.</summary>
  cLongFolder = 'Langer Ordnername mit Leerzeichen';

function IsNameChar(AChar: Char): Boolean;
begin
  // Wie dpcc.Core.Editor.Navigation.
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

/// <summary>Bytes von AText in AEncoding, mit BOM nur bei Utf8Bom.</summary>
function BytesOf(const AText: string; AEncoding: TJumpEncoding): TBytes;
var
  mAnsi: TEncoding;
begin
  case AEncoding of
    TJumpEncoding.Utf8Bom:
      Result := TEncoding.UTF8.GetPreamble + TEncoding.UTF8.GetBytes(AText);
    TJumpEncoding.Utf8:
      Result := TEncoding.UTF8.GetBytes(AText);
  else
    mAnsi := TEncoding.GetEncoding(1252);
    try
      Result := mAnsi.GetBytes(AText);
    finally
      mAnsi.Free;
    end;
  end;
end;

function ShortPathOf(const APath: string): string;
var
  mBuffer: array[0..MAX_PATH] of Char;
  mLength: DWORD;
begin
  mLength := GetShortPathName(PChar(APath), mBuffer, Length(mBuffer));
  if (mLength = 0) or (mLength > MAX_PATH) then
  begin
    Exit(APath);
  end;
  SetString(Result, PChar(@mBuffer[0]), mLength);
end;

{ TGotoMatrixTests }

procedure TGotoMatrixTests.CreateRoot;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'dpcc-gotomatrix-' + IntToStr(MainThreadID));
  ForceDirectories(FRoot);
  // Erster Lauf ungemessen (Leckmonitor misst je Test), wie CreateRootAndWarmUp in GotoBothWays.
  try
    Start(TJumpSetup.Standard);
  except
    // Scheitert der Lauf, meldet das der Test selbst.
    on Exception do
      ;
  end;
  Stop;
end;

procedure TGotoMatrixTests.DeleteRoot;
begin
  Stop;
  if (FRoot <> '') and TDirectory.Exists(FRoot) then
  try
    TDirectory.Delete(FRoot, True);
  except
    // Ein Rest im Temp-Ordner stört keinen Test.
    on Exception do
      ;
  end;
  FRoot := '';
end;

procedure TGotoMatrixTests.StopServer;
begin
  Stop;
end;

function TGotoMatrixTests.FolderOf(ASetup: TJumpSetup): string;
begin
  if ASetup = TJumpSetup.PathShortForm then
  begin
    Result := TPath.Combine(FRoot, cLongFolder);
  end
  else
  begin
    Result := TPath.Combine(FRoot, 'Projekt' + IntToStr(Ord(ASetup)));
  end;
end;

procedure TGotoMatrixTests.Start(ASetup: TJumpSetup);
var
  mFile: TJumpFile;
  mFull: string;
  mServer: TLspInProcessServer;
begin
  Stop;
  FSetup := ASetup;
  FFolder := FolderOf(ASetup);
  FFiles := TJumpFixture.Files(ASetup);
  ForceDirectories(FFolder);
  ForceDirectories(TPath.Combine(FFolder, 'Unter'));
  for mFile in FFiles do
  begin
    mFull := TPath.Combine(FFolder, mFile.Name);
    ForceDirectories(ExtractFilePath(mFull));
    TFile.WriteAllBytes(mFull, BytesOf(mFile.Text, mFile.Encoding));
  end;
  TFile.WriteAllBytes(TPath.Combine(FFolder, TJumpFixture.cDprName), BytesOf(TJumpFixture.DprText(ASetup),
    TJumpEncoding.Utf8Bom));
  TFile.WriteAllBytes(TPath.Combine(FFolder, TJumpFixture.cDprojName), BytesOf(TJumpFixture.DprojText(ASetup),
    TJumpEncoding.Utf8Bom));
  mServer := TLspInProcessServer.Create;
  FServerRef := mServer;
  Assert.IsTrue(FServerRef.Running, 'Server läuft nach dem Start');
  FSession := TLspSession.Create(FServerRef.Client, cTimeoutMs);
  FSession.SetProjects([TPath.Combine(FFolder, TJumpFixture.cDprojName)]);
  FSession.Initialize;
  Assert.IsTrue(FSession.Initialized, 'initialize beantwortet');
  if ASetup <> TJumpSetup.NoIndexWait then
  begin
    WaitForIndex;
  end;
  if ASetup = TJumpSetup.TargetBufferShifted then
  begin
    // Die Ziel-Unit ist im Editor offen und ungespeichert geändert. Im Plugin gleicht nur der aktive Puffer ab
    // (Manager.Editors); hier bekommt der Server den Puffer, damit die Seite des Servers prüfbar ist. Ob das Plugin
    // ihn in der IDE vor dem Sprung abgleicht, ist nur dort prüfbar.
    FSession.Sync(PathOf(TJumpFixture.cBasis), TextOf(TJumpFixture.cBasis));
    TThread.Sleep(cBufferRefreshMs);
  end;
end;

procedure TGotoMatrixTests.Stop;
begin
  if FSession <> nil then
  begin
    if FServerRef <> nil then
    begin
      FServerRef.Client.Close;
    end;
    FreeAndNil(FSession);
  end;
  FServerRef := nil;
  FFiles := nil;
  FFolder := '';
  FErrors := '';
end;

procedure TGotoMatrixTests.WaitForIndex;
var
  mSpot: TJumpSpot;
  mLocation: TLspLocation;
  mWhy: TDpccNoTarget;
  mMs: Int64;
  mStarted: UInt64;
begin
  mSpot := SpotOf(TJumpFixture.cNutzer, 'UBasis, USuch', 'UBasis');
  mStarted := TThread.GetTickCount64;
  while not JumpFrom(mSpot, TJumpClick.First, mLocation, mWhy, mMs) do
  begin
    if TThread.GetTickCount64 - mStarted > cIndexWaitMs then
    begin
      FErrors := FErrors + ' | Index nach ' + IntToStr(cIndexWaitMs) + ' ms nicht fertig';
      Exit;
    end;
    TThread.Sleep(100);
  end;
  // Das Warten selbst ist kein Befund.
  FErrors := '';
end;

function TGotoMatrixTests.FileIndex(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FFiles) do
  begin
    if SameText(FFiles[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  raise Exception.CreateFmt('Testaufbau: Datei "%s" nicht im Projekt', [AName]);
end;

function TGotoMatrixTests.TextOf(const AName: string): string;
var
  mFile: TJumpFile;
begin
  mFile := FFiles[FileIndex(AName)];
  Result := mFile.Buffer;
  if Result = '' then
  begin
    Result := mFile.Text;
  end;
end;

function TGotoMatrixTests.PathOf(const AName: string): string;
begin
  // RTL-Units der Bibliothek (LibraryFile) stehen mit vollem Pfad in FFiles.
  if TPath.IsPathRooted(AName) then
  begin
    Exit(AName);
  end;
  Result := TPath.Combine(FFolder, AName);
  case FSetup of
    TJumpSetup.PathCaseDiffers:
      Result := AnsiUpperCase(Result);
    TJumpSetup.PathShortForm:
      Result := ShortPathOf(Result);
  end;
end;

function TGotoMatrixTests.LineText(const AName: string; ALine: Integer): string;
var
  mText: string;
  mTable: TLineTable;
begin
  // Wie LineOf in dpcc.IDE.CodeInsight.Manager.Queries.
  Result := '';
  mText := TextOf(AName);
  mTable := TLineTable.Build(mText);
  if (ALine >= 0) and (ALine < mTable.LineCount) then
  begin
    Result := Copy(mText, mTable.LineStart(ALine) + 1, mTable.LineContentEnd(ALine) - mTable.LineStart(ALine));
  end;
end;

function TGotoMatrixTests.SpotOf(const AName, AMarker, AWord: string): TJumpSpot;
var
  mText: string;
  mMarker, mIndex, mAfter: Integer;
  mTable: TLineTable;
begin
  mText := TextOf(AName);
  mMarker := Pos(AMarker, mText);
  if mMarker = 0 then
  begin
    raise Exception.CreateFmt('Testaufbau: "%s" nicht in %s', [AMarker, AName]);
  end;
  for mIndex := mMarker to mMarker + Length(AMarker) - Length(AWord) do
  begin
    mAfter := mIndex + Length(AWord);
    if SameText(Copy(mText, mIndex, Length(AWord)), AWord) and
      ((mIndex = 1) or not IsNameChar(mText[mIndex - 1]) or not IsNameChar(AWord[1])) and
      ((mAfter > Length(mText)) or not IsNameChar(mText[mAfter]) or not IsNameChar(AWord[Length(AWord)])) then
    begin
      mTable := TLineTable.Build(mText);
      Result.FileName := AName;
      Result.Line := mTable.PositionAt(mIndex - 1).Line;
      Result.Character := mTable.PositionAt(mIndex - 1).Character;
      Result.NameLength := Length(AWord);
      Exit;
    end;
  end;
  raise Exception.CreateFmt('Testaufbau: "%s" nicht in "%s"', [AWord, AMarker]);
end;

function TGotoMatrixTests.JumpFrom(const ASpot: TJumpSpot; AClick: TJumpClick; out ALocation: TLspLocation;
  out ANoTarget: TDpccNoTarget; out AElapsedMs: Int64): Boolean;
var
  mCharacter: Integer;
  mLine: string;
  mStarted: UInt64;
begin
  ALocation := Default(TLspLocation);
  ANoTarget := Default(TDpccNoTarget);
  mLine := LineText(ASpot.FileName, ASpot.Line);
  case AClick of
    TJumpClick.Middle:
      mCharacter := ASpot.Character + ASpot.NameLength div 2;
    TJumpClick.Last:
      mCharacter := ASpot.Character + ASpot.NameLength - 1;
    TJumpClick.Behind:
      mCharacter := ASpot.Character + ASpot.NameLength;
    TJumpClick.PastLineEnd:
      mCharacter := Length(mLine) + 10;
  else
    mCharacter := ASpot.Character;
  end;
  mStarted := TThread.GetTickCount64;
  try
    // Wie der Hauptthread (Sync des aktiven Puffers) und GotoWork (GotoTargetAt mit der Zeile aus diesem Text).
    FSession.Sync(PathOf(ASpot.FileName), TextOf(ASpot.FileName));
    Result := FSession.GotoTargetAt(PathOf(ASpot.FileName), mLine, ASpot.Line, mCharacter, cTimeoutMs, ALocation,
      ANoTarget);
  except
    on E: Exception do
    begin
      FErrors := FErrors + Format(' | Ausnahme an %s %d:%d: %s: %s', [ASpot.FileName, ASpot.Line, mCharacter,
        E.ClassName, E.Message]);
      Result := False;
    end;
  end;
  AElapsedMs := Int64(TThread.GetTickCount64 - mStarted);
end;

function TGotoMatrixTests.SpotText(const ASpot: TJumpSpot; ACharacter: Boolean): string;
begin
  Result := Format('%s %d', [ASpot.FileName, ASpot.Line]);
  if ACharacter then
  begin
    Result := Result + ':' + IntToStr(ASpot.Character);
  end;
end;

function TGotoMatrixTests.PlaceText(AFound: Boolean; const ALocation: TLspLocation; ACharacter: Boolean;
  AFileOnly: Boolean): string;
var
  mFile: TJumpFile;
  mName: string;
begin
  if not AFound then
  begin
    Exit('kein Ziel');
  end;
  if AFileOnly then
  begin
    Exit('*' + ExtractFileName(ALocation.FileName));
  end;
  mName := '"' + ALocation.FileName + '"';
  for mFile in FFiles do
  begin
    // Der Server liefert den Pfad vereinheitlicht; derselbe Vergleich wie OnTarget.
    if TTextUris.SamePath(ALocation.FileName, TPath.Combine(FFolder, mFile.Name)) or
      TTextUris.SamePath(ALocation.FileName, PathOf(mFile.Name)) then
    begin
      mName := mFile.Name;
      Break;
    end;
  end;
  Result := Format('%s %d', [mName, ALocation.Line]);
  if ACharacter then
  begin
    Result := Result + ':' + IntToStr(ALocation.Character);
  end;
end;

function TGotoMatrixTests.TargetSpot(const ARow: TJumpRow): TJumpSpot;
begin
  if ARow.ToMarker = '' then
  begin
    // Unit-Ziel: Anfang der Datei.
    Result := Default(TJumpSpot);
    Result.FileName := ARow.ToFile;
    Exit;
  end;
  Result := SpotOf(ARow.ToFile, ARow.ToMarker, ARow.ToName);
end;

procedure TGotoMatrixTests.Run(ACase: TJumpCase);
var
  mRow: TJumpRow;
  mFrom, mTo, mBackSpot: TJumpSpot;
  mLocation, mBackLocation: TLspLocation;
  mWhy, mBackWhy: TDpccNoTarget;
  mFound, mBackFound, mFileOnly: Boolean;
  mMs, mBackMs: Int64;
  mExpected, mActual, mDetails, mNoticeDe, mNoticeEn: string;
begin
  mRow := TJumpFixture.RowOf(ACase);
  Start(mRow.Setup);
  ResolveLibrary(mRow);
  if (mRow.Setup = TJumpSetup.PathShortForm) and SameText(ShortPathOf(FFolder), FFolder) then
  begin
    // Ohne 8.3-Namen auf diesem Laufwerk gibt es keine Kurzform zu prüfen.
    Stop;
    Assert.Pass('Laufwerk ohne 8.3-Kurznamen');
  end;
  mTo := Default(TJumpSpot);
  mFileOnly := StartsText('*', mRow.ToFile);
  mFrom := SpotOf(mRow.FromFile, mRow.FromMarker, mRow.FromName);
  mFound := JumpFrom(mFrom, mRow.Click, mLocation, mWhy, mMs);
  mDetails := Format(' | %s: hin %d ms, Grund %s', [mRow.Caption, mMs, TDpccNoTarget.CodeOf(mWhy.Reason)]);
  if mRow.ExpectIndexing and mFound then
  begin
    // Der Index war beim Klick schon fertig: Der Fall (Klick während des Aufbaus) ist nicht nachgestellt.
    WaitForIndex;
    Stop;
    Assert.Pass('Index beim Klick schon fertig, Fall nicht nachgestellt');
  end;
  if mRow.ToFile = '' then
  begin
    mExpected := 'Hin kein Ziel, schnell';
    mActual := 'Hin ' + PlaceText(mFound, mLocation, True, False) + IfThen(mMs <= cNoHangMs, ', schnell',
      Format(', langsam (%d ms)', [mMs]));
    if mRow.ExpectIndexing then
    begin
      // Nutzer: Meldung „Index wird aufgebaut, bitte erneut klicken“ statt „Kein Sprungziel …“, in beiden Sprachen.
      mNoticeDe := TDpccGotoNotice.ForNoTarget(TDpccLanguage.German, mWhy);
      mNoticeEn := TDpccGotoNotice.ForNoTarget(TDpccLanguage.English, mWhy);
      mExpected := mExpected + '; Index im Aufbau; Meldung zum erneuten Klick';
      mActual := mActual + IfThen(mWhy.Indexing, '; Index im Aufbau', '; Index nicht im Aufbau') +
        IfThen(ContainsText(mNoticeDe, 'erneut') and ContainsText(mNoticeEn, 'again') and
        not StartsText('Kein Sprungziel', mNoticeDe), '; Meldung zum erneuten Klick', '; Meldung: ' + mNoticeDe);
    end;
  end
  else
  begin
    if mFileOnly then
    begin
      mExpected := 'Hin ' + mRow.ToFile;
      mActual := 'Hin ' + PlaceText(mFound, mLocation, False, True);
    end
    else
    begin
      mTo := TargetSpot(mRow);
      mExpected := 'Hin ' + SpotText(mTo, mRow.CheckCharacter);
      mActual := 'Hin ' + PlaceText(mFound, mLocation, mRow.CheckCharacter, False);
    end;
    if mRow.Back <> TJumpBack.None then
    begin
      case mRow.Back of
        TJumpBack.ToOrigin:
          mBackSpot := mFrom;
        TJumpBack.Stays:
          mBackSpot := mTo;
      else
        mBackSpot := SpotOf(mRow.BackFile, mRow.BackMarker, mRow.BackName);
      end;
      // Der Rückweg startet an der erwarteten Zielstelle, auch wenn der Hinweg danebenlag: So zeigt jede Richtung
      // ihren eigenen Befund.
      mBackFound := JumpFrom(mTo, TJumpClick.First, mBackLocation, mBackWhy, mBackMs);
      mExpected := mExpected + '; zurück ' + SpotText(mBackSpot, not mRow.BackLineOnly);
      mActual := mActual + '; zurück ' + PlaceText(mBackFound, mBackLocation, not mRow.BackLineOnly, False);
      mDetails := mDetails + Format(', zurück %d ms, Grund %s', [mBackMs, TDpccNoTarget.CodeOf(mBackWhy.Reason)]);
    end;
  end;
  mDetails := mDetails + FErrors;
  if mRow.Setup = TJumpSetup.NoIndexWait then
  begin
    // Den Aufbau noch zu Ende laufen lassen: Ein abgebrochener Aufbau gibt je nach Zeitpunkt verschieden viel
    // Speicher erst später frei (Leckmonitor, wie StopServer in Shell.Composition.PackageJump.Tests).
    WaitForIndex;
  end;
  // Server noch im Test abbauen (LEAK1, wie CheckPairs in GotoBothWays).
  Stop;
  Assert.AreEqual(mExpected, mActual, 'Zeilen und Zeichen 0-basiert' + mDetails);
end;

function TGotoMatrixTests.LibraryFile(const APlaceholder: string): string;
var
  mWord: string;
  mLocation: TLspLocation;
  mWhy: TDpccNoTarget;
  mMs: Int64;
  mFile: TJumpFile;
  mBytes: TBytes;
  mText: string;
begin
  mWord := Copy(APlaceholder, 2, Length(APlaceholder) - 2);
  for mFile in FFiles do
  begin
    if SameText(ExtractFileName(mFile.Name), 'System.' + mWord + '.pas') and TPath.IsPathRooted(mFile.Name) then
    begin
      Exit(mFile.Name);
    end;
  end;
  if not JumpFrom(SpotOf(TJumpFixture.cBibliothek, TJumpFixture.cLibUses, mWord), TJumpClick.First, mLocation, mWhy,
    mMs) or not SameText(ExtractFileName(mLocation.FileName), 'System.' + mWord + '.pas') then
  begin
    raise Exception.CreateFmt('Testaufbau: RTL-Unit System.%s nicht gefunden (%s)', [mWord, mLocation.FileName]);
  end;
  Result := mLocation.FileName;
  mBytes := TFile.ReadAllBytes(Result);
  if (Length(mBytes) >= 3) and (mBytes[0] = $EF) and (mBytes[1] = $BB) and (mBytes[2] = $BF) then
  begin
    mText := TEncoding.UTF8.GetString(mBytes, 3, Length(mBytes) - 3);
  end
  else
  begin
    mText := TEncoding.UTF8.GetString(mBytes);
  end;
  mFile := Default(TJumpFile);
  mFile.Name := Result;
  // Marker der Tabelle trennen Zeilen mit #10; die Zeilennummern bleiben gleich.
  mFile.Text := StringReplace(mText, #13#10, #10, [rfReplaceAll]);
  mFile.Encoding := TJumpEncoding.Utf8;
  FFiles := FFiles + [mFile];
end;

procedure TGotoMatrixTests.ResolveLibrary(var ARow: TJumpRow);

  procedure Resolve(var AName: string);
  begin
    if StartsText('<', AName) then
    begin
      AName := LibraryFile(AName);
    end;
  end;

begin
  Resolve(ARow.FromFile);
  Resolve(ARow.ToFile);
  Resolve(ARow.BackFile);
end;

procedure TGotoMatrixTests.DeclImplOverrideInDescendant;
begin
  Run(TJumpCase.DeclImplOverrideInDescendant);
end;

procedure TGotoMatrixTests.DeclImplMethodOverloadInOtherUnit;
begin
  Run(TJumpCase.DeclImplMethodOverloadInOtherUnit);
end;

procedure TGotoMatrixTests.DeclImplOverrideOfAbstractOverload;
begin
  Run(TJumpCase.DeclImplOverrideOfAbstractOverload);
end;

procedure TGotoMatrixTests.DeclImplClassHelper;
begin
  Run(TJumpCase.DeclImplClassHelper);
end;

procedure TGotoMatrixTests.DeclImplRecordHelper;
begin
  Run(TJumpCase.DeclImplRecordHelper);
end;

procedure TGotoMatrixTests.DeclImplPropertyGetter;
begin
  Run(TJumpCase.DeclImplPropertyGetter);
end;

procedure TGotoMatrixTests.DeclImplFreeOverloadSameParamNameInteger;
begin
  Run(TJumpCase.DeclImplFreeOverloadSameParamNameInteger);
end;

procedure TGotoMatrixTests.DeclImplFreeOverloadSameParamNameDouble;
begin
  Run(TJumpCase.DeclImplFreeOverloadSameParamNameDouble);
end;

procedure TGotoMatrixTests.DeclImplExternalInImplementation;
begin
  Run(TJumpCase.DeclImplExternalInImplementation);
end;

procedure TGotoMatrixTests.DeclImplAbstractOverloadFirstStays;
begin
  Run(TJumpCase.DeclImplAbstractOverloadFirstStays);
end;

procedure TGotoMatrixTests.DeclImplAbstractOverloadSecondStays;
begin
  Run(TJumpCase.DeclImplAbstractOverloadSecondStays);
end;

procedure TGotoMatrixTests.DeclImplInterfaceOverloadFirstStays;
begin
  Run(TJumpCase.DeclImplInterfaceOverloadFirstStays);
end;

procedure TGotoMatrixTests.DeclImplInterfaceOverloadSecondStays;
begin
  Run(TJumpCase.DeclImplInterfaceOverloadSecondStays);
end;

procedure TGotoMatrixTests.DeclImplInterfaceMethodStays;
begin
  Run(TJumpCase.DeclImplInterfaceMethodStays);
end;

procedure TGotoMatrixTests.DeclImplPlainAndGenericSameNamePlain;
begin
  Run(TJumpCase.DeclImplPlainAndGenericSameNamePlain);
end;

procedure TGotoMatrixTests.DeclImplPlainAndGenericSameNameGeneric;
begin
  Run(TJumpCase.DeclImplPlainAndGenericSameNameGeneric);
end;

procedure TGotoMatrixTests.DeclImplLastLineOfFile;
begin
  Run(TJumpCase.DeclImplLastLineOfFile);
end;

procedure TGotoMatrixTests.DeclImplMethodFromIncludeInClassBody;
begin
  Run(TJumpCase.DeclImplMethodFromIncludeInClassBody);
end;

procedure TGotoMatrixTests.DeclImplFreeRoutineFromInclude;
begin
  Run(TJumpCase.DeclImplFreeRoutineFromInclude);
end;

procedure TGotoMatrixTests.DeclImplBackFromIncludeFile;
begin
  Run(TJumpCase.DeclImplBackFromIncludeFile);
end;

procedure TGotoMatrixTests.DeclImplDprojWithDotSegments;
begin
  Run(TJumpCase.DeclImplDprojWithDotSegments);
end;

procedure TGotoMatrixTests.UsageLocalVariable;
begin
  Run(TJumpCase.UsageLocalVariable);
end;

procedure TGotoMatrixTests.UsageParameter;
begin
  Run(TJumpCase.UsageParameter);
end;

procedure TGotoMatrixTests.UsageInheritedField;
begin
  Run(TJumpCase.UsageInheritedField);
end;

procedure TGotoMatrixTests.UsagePropertyImplicit;
begin
  Run(TJumpCase.UsagePropertyImplicit);
end;

procedure TGotoMatrixTests.UsagePropertyViaSelf;
begin
  Run(TJumpCase.UsagePropertyViaSelf);
end;

procedure TGotoMatrixTests.UsageConstant;
begin
  Run(TJumpCase.UsageConstant);
end;

procedure TGotoMatrixTests.UsageGetterOnPropertyLine;
begin
  Run(TJumpCase.UsageGetterOnPropertyLine);
end;

procedure TGotoMatrixTests.UsageSetterOnPropertyLine;
begin
  Run(TJumpCase.UsageSetterOnPropertyLine);
end;

procedure TGotoMatrixTests.UsageFieldOnPropertyLine;
begin
  Run(TJumpCase.UsageFieldOnPropertyLine);
end;

procedure TGotoMatrixTests.UsageEnumUnscoped;
begin
  Run(TJumpCase.UsageEnumUnscoped);
end;

procedure TGotoMatrixTests.UsageEnumScopedTypePart;
begin
  Run(TJumpCase.UsageEnumScopedTypePart);
end;

procedure TGotoMatrixTests.UsageEnumScopedValuePart;
begin
  Run(TJumpCase.UsageEnumScopedValuePart);
end;

procedure TGotoMatrixTests.UsageTypeInClassHeading;
begin
  Run(TJumpCase.UsageTypeInClassHeading);
end;

procedure TGotoMatrixTests.UsageTypeOtherUnit;
begin
  Run(TJumpCase.UsageTypeOtherUnit);
end;

procedure TGotoMatrixTests.UsageMethodImplicitSelf;
begin
  Run(TJumpCase.UsageMethodImplicitSelf);
end;

procedure TGotoMatrixTests.UsageMethodExplicitSelf;
begin
  Run(TJumpCase.UsageMethodExplicitSelf);
end;

procedure TGotoMatrixTests.UsageSelf;
begin
  Run(TJumpCase.UsageSelf);
end;

procedure TGotoMatrixTests.UsageInheritedWithName;
begin
  Run(TJumpCase.UsageInheritedWithName);
end;

procedure TGotoMatrixTests.UsageInheritedBare;
begin
  Run(TJumpCase.UsageInheritedBare);
end;

procedure TGotoMatrixTests.UsageInterfaceMethod;
begin
  Run(TJumpCase.UsageInterfaceMethod);
end;

procedure TGotoMatrixTests.UsageInterfaceOverloadString;
begin
  Run(TJumpCase.UsageInterfaceOverloadString);
end;

procedure TGotoMatrixTests.UsageOverloadInteger;
begin
  Run(TJumpCase.UsageOverloadInteger);
end;

procedure TGotoMatrixTests.UsageOverloadString;
begin
  Run(TJumpCase.UsageOverloadString);
end;

procedure TGotoMatrixTests.UsageClassHelper;
begin
  Run(TJumpCase.UsageClassHelper);
end;

procedure TGotoMatrixTests.UsageRecordHelper;
begin
  Run(TJumpCase.UsageRecordHelper);
end;

procedure TGotoMatrixTests.UsageFreeRoutineOtherUnit;
begin
  Run(TJumpCase.UsageFreeRoutineOtherUnit);
end;

procedure TGotoMatrixTests.UsageFreeOverloadInteger;
begin
  Run(TJumpCase.UsageFreeOverloadInteger);
end;

procedure TGotoMatrixTests.UsageFreeOverloadDouble;
begin
  Run(TJumpCase.UsageFreeOverloadDouble);
end;

procedure TGotoMatrixTests.UsageQualifiedUnitPart;
begin
  Run(TJumpCase.UsageQualifiedUnitPart);
end;

procedure TGotoMatrixTests.UsageQualifiedRoutinePart;
begin
  Run(TJumpCase.UsageQualifiedRoutinePart);
end;

procedure TGotoMatrixTests.UsageQualifiedConstantPart;
begin
  Run(TJumpCase.UsageQualifiedConstantPart);
end;

procedure TGotoMatrixTests.UsageWithMember;
begin
  Run(TJumpCase.UsageWithMember);
end;

procedure TGotoMatrixTests.UsageWithProperty;
begin
  Run(TJumpCase.UsageWithProperty);
end;

procedure TGotoMatrixTests.UsageSearchPathRoutine;
begin
  Run(TJumpCase.UsageSearchPathRoutine);
end;

procedure TGotoMatrixTests.UsageUsesSearchPathUnit;
begin
  Run(TJumpCase.UsageUsesSearchPathUnit);
end;

procedure TGotoMatrixTests.UsageUsesProjectUnit;
begin
  Run(TJumpCase.UsageUsesProjectUnit);
end;

procedure TGotoMatrixTests.UsageUsesRtlUnit;
begin
  Run(TJumpCase.UsageUsesRtlUnit);
end;

procedure TGotoMatrixTests.UsageUsesDottedFirstPart;
begin
  Run(TJumpCase.UsageUsesDottedFirstPart);
end;

procedure TGotoMatrixTests.UsageRtlRoutine;
begin
  Run(TJumpCase.UsageRtlRoutine);
end;

procedure TGotoMatrixTests.UsageIncludeDirectiveOpensFile;
begin
  Run(TJumpCase.UsageIncludeDirectiveOpensFile);
end;

procedure TGotoMatrixTests.UsageIncludeDirectiveLongFormOpensFile;
begin
  Run(TJumpCase.UsageIncludeDirectiveLongFormOpensFile);
end;

procedure TGotoMatrixTests.UsageIncludeRoutine;
begin
  Run(TJumpCase.UsageIncludeRoutine);
end;

procedure TGotoMatrixTests.UsageIncludeMethod;
begin
  Run(TJumpCase.UsageIncludeMethod);
end;

procedure TGotoMatrixTests.UsageNestedRoutine;
begin
  Run(TJumpCase.UsageNestedRoutine);
end;

procedure TGotoMatrixTests.UsageResult;
begin
  Run(TJumpCase.UsageResult);
end;

procedure TGotoMatrixTests.UsageLastLineRoutine;
begin
  Run(TJumpCase.UsageLastLineRoutine);
end;

procedure TGotoMatrixTests.UsageClickLastCharacter;
begin
  Run(TJumpCase.UsageClickLastCharacter);
end;

procedure TGotoMatrixTests.UsageClickBehindName;
begin
  Run(TJumpCase.UsageClickBehindName);
end;

procedure TGotoMatrixTests.UsageAtLineStart;
begin
  Run(TJumpCase.UsageAtLineStart);
end;

procedure TGotoMatrixTests.UsageAtLineEndLastCharacter;
begin
  Run(TJumpCase.UsageAtLineEndLastCharacter);
end;

procedure TGotoMatrixTests.UsageAtLineEndBehind;
begin
  Run(TJumpCase.UsageAtLineEndBehind);
end;

procedure TGotoMatrixTests.FileSourceBufferShifted;
begin
  Run(TJumpCase.FileSourceBufferShifted);
end;

procedure TGotoMatrixTests.FileTargetBufferShifted;
begin
  Run(TJumpCase.FileTargetBufferShifted);
end;

procedure TGotoMatrixTests.FileTargetUtf8WithBom;
begin
  Run(TJumpCase.FileTargetUtf8WithBom);
end;

procedure TGotoMatrixTests.FileTargetUtf8WithoutBom;
begin
  Run(TJumpCase.FileTargetUtf8WithoutBom);
end;

procedure TGotoMatrixTests.FileTargetAnsi;
begin
  Run(TJumpCase.FileTargetAnsi);
end;

procedure TGotoMatrixTests.FileTargetTabsBeforeName;
begin
  Run(TJumpCase.FileTargetTabsBeforeName);
end;

procedure TGotoMatrixTests.FileTargetLfOnly;
begin
  Run(TJumpCase.FileTargetLfOnly);
end;

procedure TGotoMatrixTests.FilePathCaseDiffers;
begin
  Run(TJumpCase.FilePathCaseDiffers);
end;

procedure TGotoMatrixTests.FilePathShortForm;
begin
  Run(TJumpCase.FilePathShortForm);
end;

procedure TGotoMatrixTests.FileDuringIndexBuild;
begin
  Run(TJumpCase.FileDuringIndexBuild);
end;

procedure TGotoMatrixTests.NegativeKeyword;
begin
  Run(TJumpCase.NegativeKeyword);
end;

procedure TGotoMatrixTests.NegativeComment;
begin
  Run(TJumpCase.NegativeComment);
end;

procedure TGotoMatrixTests.NegativeString;
begin
  Run(TJumpCase.NegativeString);
end;

procedure TGotoMatrixTests.NegativeNumber;
begin
  Run(TJumpCase.NegativeNumber);
end;

procedure TGotoMatrixTests.NegativeUnknownName;
begin
  Run(TJumpCase.NegativeUnknownName);
end;

procedure TGotoMatrixTests.NegativeResourceDirective;
begin
  Run(TJumpCase.NegativeResourceDirective);
end;

procedure TGotoMatrixTests.NegativeOperator;
begin
  Run(TJumpCase.NegativeOperator);
end;

procedure TGotoMatrixTests.NegativePastLineEnd;
begin
  Run(TJumpCase.NegativePastLineEnd);
end;

procedure TGotoMatrixTests.LibraryCallToDeclarationThenBody;
begin
  Run(TJumpCase.LibraryCallToDeclarationThenBody);
end;

procedure TGotoMatrixTests.LibraryBodyToDeclaration;
begin
  Run(TJumpCase.LibraryBodyToDeclaration);
end;

procedure TGotoMatrixTests.LibraryOverloadInt64FromDeclaration;
begin
  Run(TJumpCase.LibraryOverloadInt64FromDeclaration);
end;

procedure TGotoMatrixTests.LibraryOverloadFormat;
begin
  Run(TJumpCase.LibraryOverloadFormat);
end;

procedure TGotoMatrixTests.LibraryMethodOfClass;
begin
  Run(TJumpCase.LibraryMethodOfClass);
end;

procedure TGotoMatrixTests.LibraryAbstractMethodStays;
begin
  Run(TJumpCase.LibraryAbstractMethodStays);
end;

procedure TGotoMatrixTests.LibraryDefinitionRequestToBody;

  /// <summary>„Datei Zeile:Zeichen“ des ersten Ziels von definition bzw. declaration an ASpot.</summary>
  function Ask(const ASpot: TJumpSpot; ADeclaration: Boolean): string;
  var
    mFound: TArray<TLspLocation>;
    mFirst: TLspLocation;
  begin
    FSession.Sync(PathOf(ASpot.FileName), TextOf(ASpot.FileName));
    if ADeclaration then
    begin
      mFound := FSession.Declarations(PathOf(ASpot.FileName), ASpot.Line, ASpot.Character);
    end
    else
    begin
      mFound := FSession.Definitions(PathOf(ASpot.FileName), ASpot.Line, ASpot.Character);
    end;
    mFirst := Default(TLspLocation);
    if Length(mFound) > 0 then
    begin
      mFirst := mFound[0];
    end;
    Result := PlaceText(Length(mFound) > 0, mFirst, True, False);
  end;

  function Expected(const AFile, AMarker, AWord: string; ALineStart: Boolean): string;
  var
    mSpot: TJumpSpot;
  begin
    mSpot := SpotOf(AFile, AMarker, AWord);
    if ALineStart then
    begin
      mSpot.Character := 0;
    end;
    Result := SpotText(mSpot, True);
  end;

var
  mSysUtils, mClasses, mExpected, mActual: string;
begin
  Start(TJumpSetup.Standard);
  try
    mSysUtils := LibraryFile(TJumpFixture.cLibSysUtils);
    mClasses := LibraryFile(TJumpFixture.cLibClasses);
    mExpected := 'definition ' + Expected(mSysUtils, #10'function IntToStr(Value: Integer): string;'#10, 'IntToStr',
      True) + '; declaration ' + Expected(mSysUtils, 'function IntToStr(Value: Integer): string; overload;',
      'IntToStr', False) + '; Methode ' + Expected(mClasses, #10'function TStringList.Add(const S: string): Integer;'#10,
      'Add', True) + '; abstrakt ' + Expected(mClasses, 'procedure Clear; virtual; abstract;', 'Clear', False);
    mActual := 'definition ' + Ask(SpotOf(TJumpFixture.cBibliothek,
      'Text := IntToStr(Klein); // Bibliothek IntToStr Integer', 'IntToStr'), False) + '; declaration ' +
      Ask(SpotOf(TJumpFixture.cBibliothek, 'Text := IntToStr(Klein); // Bibliothek IntToStr Integer', 'IntToStr'),
      True) + '; Methode ' + Ask(SpotOf(TJumpFixture.cBibliothek, 'Liste.Add(Text); // Bibliothek Methode', 'Add'),
      False) + '; abstrakt ' + Ask(SpotOf(TJumpFixture.cBibliothek, 'Allgemein.Clear; // Bibliothek abstrakt',
      'Clear'), False);
    mActual := mActual + FErrors;
  finally
    Stop;
  end;
  Assert.AreEqual(mExpected, mActual, 'Zeilen und Zeichen 0-basiert');
end;

initialization
  TDUnitX.RegisterTestFixture(TGotoMatrixTests);

end.
