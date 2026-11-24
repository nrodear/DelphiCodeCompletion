unit dpcc.Core.Lsp.GotoBothWays.Tests;

// Strg+Klick wechselt in beide Richtungen (Auftrag NAV; Meldung aus Delphi 12 auf einem anderen Rechner: von der
// Implementierung zur Deklaration springt es, von der Deklaration nicht zur Implementierung). Geprüft auf dem Weg
// der IDE: TLspSession.GotoTargetAt ohne eigenen Abgleich (Sync vorher wie im Hauptthread, Zeilentext aus dem
// abgeglichenen Text wie TDpccCodeInsightQueries.GotoPlace) gegen den echten Completion-Server im eigenen Prozess
// (TLspInProcessServer, Muster dpcc.Core.Lsp.Adapters.InProcess.Tests). GotoTargetAt fragt
// textDocument/declaration; liegt das Ziel auf der Klickstelle (TDpccGotoDefinition.OnTarget: gleiche Datei,
// gleiche Zeile, gleiches Wort), folgt textDocument/definition.
// Ein Test je Form: Methodenarten und Direktiven, abweichende Schreibweise zwischen Deklaration und Implementierung,
// Überladungen (jede in beide Richtungen), Generics, Records, class operator, verschachtelte Typen, freie Routinen,
// gleichnamige Methoden mehrerer Klassen, Klickstelle im Namen, Tabs, Zeilenenden und Formen des Dateipfads.
// Die Erwartung ist das GEWÜNSCHTE Verhalten (Deklaration → Implementierung, Implementierung → Deklaration).
// Schlägt ein Test fehl, ist das ein Befund: Die Meldung nennt je Paar beide Richtungen (Zeilen 0-basiert wie im
// LSP, -1 ohne Ziel, -2 bei Ausnahme) und dazu an jeder Stelle die rohen Antworten auf declaration und definition
// samt Urteil von OnTarget. Daran ist abzulesen, ob der Server oder die Seite der IDE abweicht.
// Jeder Test startet einen eigenen Server (der Leckmonitor misst je Test); der erste Lauf im [SetupFixture] ist
// ungemessen. Alle Dateien liegen in einem eigenen Ordner unter %TEMP% und werden am Ende gelöscht.

interface

uses
  DUnitX.TestFramework,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session;

type
{$SCOPEDENUMS ON}
  /// <summary>Klickstelle im Namen: erstes Zeichen, Mitte, letztes Zeichen oder direkt dahinter (Schreibmarke
  /// hinter dem Namen, „Deklaration suchen“ per Tastatur).</summary>
  TGotoClick = (First, Middle, Last, Behind);
{$SCOPEDENUMS OFF}

  /// <summary>Stelle eines Namens im Text: Zeile und Zeichen seines Anfangs (0-basiert, UTF-16) und seine Länge.
  /// </summary>
  TGotoSpot = record
    Line: Integer;
    Character: Integer;
    NameLength: Integer;
  end;

  /// <summary>Eine geprüfte Stelle, für die Meldung bei einem Fehlschlag.</summary>
  TGotoProbe = record
    Caption: string;
    Spot: TGotoSpot;
    Click: TGotoClick;
  end;

  [TestFixture]
  TGotoBothWaysTests = class
  private
    FRoot: string;
    FFolder: string;
    FProjectFile: string;
    /// <summary>Dateiname, wie ihn die IDE übergibt (in den Pfadtests eine andere Schreibweise derselben Datei).
    /// </summary>
    FUnitFile: string;
    FText: string;
    FServerRef: IDpccLspServer;
    FSession: TLspSession;
    FExpected: string;
    FActual: string;
    FErrors: string;
    FProbes: TArray<TGotoProbe>;
    /// <summary>Projekt und AText als UGoto.pas in den Ordner des Fixtures schreiben, Server starten, initialize,
    /// didOpen.</summary>
    procedure Start(const AText: string); overload;
    /// <summary>Wie oben im Ordner AFolder; AUnitFile ist der Dateiname, wie die IDE ihn übergibt ('' = der echte
    /// Pfad).</summary>
    procedure Start(const AText, AFolder, AUnitFile: string); overload;
    /// <summary>Wie StopSessionNow im Plugin: Client schließen, Sitzung freigeben, dann den Server; Felder leeren.
    /// </summary>
    procedure Stop;
    /// <summary>Zeile ALine des abgeglichenen Texts ohne Umbruch.</summary>
    function LineText(ALine: Integer): string;
    /// <summary>Stelle des Namens AName (ganzes Wort, Groß-/Kleinschreibung egal) im ersten Vorkommen von AMarker.
    /// </summary>
    function SpotOf(const AMarker, AName: string): TGotoSpot;
    /// <summary>Strg+Klick an ASpot wie im Plugin (GotoTargetAt): Zeile des Ziels, -1 ohne Ziel, -2 bei Ausnahme.
    /// </summary>
    function JumpLine(const ASpot: TGotoSpot; AClick: TGotoClick): Integer;
    /// <summary>Rohe Antwort auf declaration (ADeclaration) bzw. definition an der Stelle, mit Urteil von OnTarget.
    /// </summary>
    function AnswerText(ADeclaration: Boolean; const AProbe: TGotoProbe): string;
    function ProbeText(const AProbe: TGotoProbe): string;
    /// <summary>Ein Paar Deklaration/Implementierung des Namens AName in beide Richtungen springen und Erwartung und
    /// Ergebnis anhängen; geprüft wird erst in CheckPairs.</summary>
    procedure AddPair(const AName, ADeclMarker, AImplMarker: string); overload;
    procedure AddPair(const AName, ADeclMarker, AImplMarker: string; AClick: TGotoClick); overload;
    /// <summary>Alle Paare zusammen prüfen: Die Meldung zeigt jede Richtung jedes Paars.</summary>
    procedure CheckPairs;
    /// <summary>Einfache Methode im Ordner AFolder, von der IDE als AUnitFile übergeben: OnTarget erkennt den
    /// Zielpfad des Servers als dieselbe Datei, und der Sprung wechselt in beide Richtungen.</summary>
    procedure CheckPathForm(const AFolder, AUnitFile: string);
  public
    /// <summary>Ordner anlegen und den ersten Lauf ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure CreateRootAndWarmUp;
    [TearDownFixture]
    procedure DeleteRoot;
    [TearDown]
    procedure StopServer;

    // 1. Einfache Formen
    /// <summary>Prozedur ohne Parameter.</summary>
    [Test]
    procedure SimpleProcedure;
    /// <summary>Funktion mit Parametern, Implementierung wiederholt sie gleich.</summary>
    [Test]
    procedure FunctionWithParameters;

    // 2. Implementierung ohne Parameterliste
    /// <summary>Prozedur und constructor mit Parametern, Implementierung ohne Parameterliste.</summary>
    [Test]
    procedure ImplementationWithoutParameterList;
    /// <summary>Funktion, Implementierung ohne Parameterliste und ohne Ergebnistyp ("function TFoo.Rechne;").
    /// </summary>
    [Test]
    procedure FunctionImplementationWithoutParametersAndResult;

    // 3. Abweichende Schreibweise (nicht überladen)
    /// <summary>"A:Integer;const S:string" gegen "A: Integer; const S: string".</summary>
    [Test]
    procedure SpacingDiffers;
    /// <summary>"integer"/"STRING" in der Deklaration, "Integer"/"string" in der Implementierung.</summary>
    [Test]
    procedure TypeCaseDiffers;
    /// <summary>Implementierung klein geschrieben ("tfoo.setze").</summary>
    [Test]
    procedure ImplementationNameCaseDiffers;
    /// <summary>Vorgabewerte nur in der Deklaration.</summary>
    [Test]
    procedure DefaultValuesOnlyInDeclaration;
    /// <summary>"System.Integer" in der Deklaration, "Integer" in der Implementierung.</summary>
    [Test]
    procedure QualifiedTypeName;
    /// <summary>Zeilenumbruch in der Parameterliste der Implementierung bzw. der Deklaration.</summary>
    [Test]
    procedure LineBreakInParameterList;

    // 4. Überladungen
    /// <summary>Zwei Überladungen, jede in beide Richtungen.</summary>
    [Test]
    procedure OverloadsTwo;
    /// <summary>Drei Überladungen (ohne, ein, zwei Parameter).</summary>
    [Test]
    procedure OverloadsThree;
    /// <summary>Drei Überladungen, Implementierungen in umgekehrter Reihenfolge.</summary>
    [Test]
    procedure OverloadsImplementationOrderReversed;
    /// <summary>Überladungen mit "A:Integer" gegen "A: Integer".</summary>
    [Test]
    procedure OverloadsSpacingDiffers;
    /// <summary>Überladungen mit "integer"/"String" gegen "Integer"/"string" und "tfoo.bar".</summary>
    [Test]
    procedure OverloadsCaseDiffers;
    /// <summary>Überladungen mit Vorgabewerten nur in der Deklaration.</summary>
    [Test]
    procedure OverloadsDefaultValuesOnlyInDeclaration;
    /// <summary>Überladungen, eine mit "System.Integer" in der Deklaration und "Integer" in der Implementierung.
    /// </summary>
    [Test]
    procedure OverloadsQualifiedTypeName;
    /// <summary>Überladungen mit Zeilenumbruch in der Parameterliste der Implementierung.</summary>
    [Test]
    procedure OverloadsLineBreakInParameterList;

    // 5. Methodenarten und Direktiven
    /// <summary>constructor mit Parameter.</summary>
    [Test]
    procedure ConstructorBothWays;
    /// <summary>Zwei überladene constructor.</summary>
    [Test]
    procedure ConstructorOverloads;
    /// <summary>destructor Destroy; override.</summary>
    [Test]
    procedure DestructorOverride;
    /// <summary>class procedure.</summary>
    [Test]
    procedure ClassProcedure;
    /// <summary>class function ... static.</summary>
    [Test]
    procedure ClassFunctionStatic;
    /// <summary>Methode mit virtual.</summary>
    [Test]
    procedure VirtualMethod;
    /// <summary>virtual im Vorfahren, override im Nachfahren derselben Unit: jede zu ihrer Implementierung.</summary>
    [Test]
    procedure OverrideInDescendant;
    /// <summary>overload an einer Methode ohne zweite Variante.</summary>
    [Test]
    procedure OverloadDirectiveWithoutSecondVariant;
    /// <summary>Botschaftsmethode (message) mit Parameter "var Message" wie in der VCL.</summary>
    [Test]
    procedure MessageMethod;
    /// <summary>inline und stdcall (stdcall in der Implementierung wiederholt).</summary>
    [Test]
    procedure InlineAndCallingConvention;

    // 6. Generics
    /// <summary>Generische Klasse TFoo&lt;T&gt;, Implementierung TFoo&lt;T&gt;.Bar.</summary>
    [Test]
    procedure GenericClassMethod;
    /// <summary>Generische Klasse, Parameter vom Typparameter T.</summary>
    [Test]
    procedure GenericClassMethodWithTypeParameter;
    /// <summary>Generische Klasse mit zwei Typparametern.</summary>
    [Test]
    procedure GenericClassWithTwoTypeParameters;
    /// <summary>Generische Klasse mit Einschränkung (T: class, constructor), Implementierung ohne sie.</summary>
    [Test]
    procedure GenericClassWithConstraint;
    /// <summary>Generische Methode Bar&lt;T&gt; einer gewöhnlichen Klasse.</summary>
    [Test]
    procedure GenericMethod;
    /// <summary>Generische Methode Bar&lt;T&gt; überladen mit Bar(A: Integer).</summary>
    [Test]
    procedure GenericMethodWithPlainOverload;

    // 7. Records, Operatoren, verschachtelte Typen
    /// <summary>Methoden eines Records.</summary>
    [Test]
    procedure RecordMethod;
    /// <summary>class operator Add und Equal.</summary>
    [Test]
    procedure ClassOperator;
    /// <summary>Zwei class operator Implicit mit verschiedenen Parametertypen.</summary>
    [Test]
    procedure ClassOperatorOverloads;
    /// <summary>Zwei class operator Implicit, die sich nur im Ergebnistyp unterscheiden.</summary>
    [Test]
    procedure ClassOperatorDiffersOnlyByResultType;
    /// <summary>Methode eines verschachtelten Typs (TOuter.TInner.Bar) neben gleichnamiger Methode von TOuter.
    /// </summary>
    [Test]
    procedure NestedTypeMethod;

    // 8. Freie Routinen
    /// <summary>Routinen im interface deklariert, Rumpf im implementation-Teil.</summary>
    [Test]
    procedure FreeRoutineInterfaceAndImplementation;
    /// <summary>Freie Funktion, Rumpf ohne Parameterliste und Ergebnistyp.</summary>
    [Test]
    procedure FreeRoutineImplementationWithoutParameterList;
    /// <summary>Überladene freie Routinen, Rümpfe in umgekehrter Reihenfolge.</summary>
    [Test]
    procedure FreeRoutineOverloads;
    /// <summary>forward-Deklaration im implementation-Teil.</summary>
    [Test]
    procedure ForwardDeclaration;

    // 9. Klickstelle, Tabs, Zeichen, Zeilenenden
    /// <summary>Klick auf das erste Zeichen des Namens.</summary>
    [Test]
    procedure ClickOnFirstCharacter;
    /// <summary>Klick in die Mitte des Namens.</summary>
    [Test]
    procedure ClickInMiddleOfName;
    /// <summary>Klick auf das letzte Zeichen des Namens.</summary>
    [Test]
    procedure ClickOnLastCharacter;
    /// <summary>Schreibmarke direkt hinter dem Namen.</summary>
    [Test]
    procedure ClickDirectlyBehindName;
    /// <summary>Klasse mit Tab-Einrückung; die Stelle wie im Plugin aus der Editorspalte (Tabweite 8).</summary>
    [Test]
    procedure TabIndentedDeclaration;
    /// <summary>Methodenname mit Umlauten.</summary>
    [Test]
    procedure UmlautInMethodName;
    /// <summary>Zeichen außerhalb der BMP (Ersatzpaar) vor dem Namen in der Zeile der Deklaration.</summary>
    [Test]
    procedure NonBmpCharacterBeforeName;
    /// <summary>Datei nur mit LF.</summary>
    [Test]
    procedure LfLineEndings;
    /// <summary>Klasse mit CRLF, implementation-Teil mit LF.</summary>
    [Test]
    procedure MixedLineEndings;

    // 10. Dateipfad
    /// <summary>Ordner mit Leerzeichen.</summary>
    [Test]
    procedure PathWithSpaces;
    /// <summary>Ordner mit Umlauten und ß.</summary>
    [Test]
    procedure PathWithUmlauts;
    /// <summary>Ordner mit runden, eckigen und geschweiften Klammern.</summary>
    [Test]
    procedure PathWithBrackets;
    /// <summary>Ordner mit "#", "%" und einer Folge, die wie eine Kodierung aussieht ("%41").</summary>
    [Test]
    procedure PathWithHashAndPercent;
    /// <summary>Ordner mit Zeichen, die in URIs Bedeutung haben (+ &amp; ; = , ! $ @ ~).</summary>
    [Test]
    procedure PathWithUriSpecialCharacters;
    /// <summary>Laufwerksbuchstabe klein ("c:\…").</summary>
    [Test]
    procedure DriveLetterLowerCase;
    /// <summary>Laufwerksbuchstabe groß ("C:\…"; der Server schreibt ihn in der URI klein).</summary>
    [Test]
    procedure DriveLetterUpperCase;
    /// <summary>Gemischte Schrägstriche ("…\Ordner/Unter/UGoto.pas").</summary>
    [Test]
    procedure MixedSlashes;
    /// <summary>Nur Schrägstriche ("C:/…/UGoto.pas").</summary>
    [Test]
    procedure ForwardSlashesOnly;
    /// <summary>Pfad mit "Unter\..\".</summary>
    [Test]
    procedure PathWithDotSegments;

    // 11. Gleichnamige Methoden und weitere Formen
    /// <summary>TA.Run, TB.Run, TC.Run (reintroduce), IRun.Run und eine freie Routine Run in einer Unit; Rümpfe in
    /// anderer Reihenfolge: jeder Sprung bei der eigenen Klasse.</summary>
    [Test]
    procedure SameMethodNameInSeveralClasses;
    /// <summary>Klasse nur im implementation-Teil.</summary>
    [Test]
    procedure ClassInImplementationSection;
    /// <summary>Formular-Unit wie aus der IDE: uses mit VCL-Units, published Ereignisse, {$R *.dfm}.</summary>
    [Test]
    procedure FormUnitWithUsesAndResourceDirective;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  dpcc.Core.Lsp.Adapters.InProcess,
  dpcc.Core.Editor.Navigation,
  dpcc.Text.Lines;

const
  cTimeoutMs = 20000;
  cUnitName = 'UGoto.pas';
  cDprName = 'GotoProbe.dpr';
  cDprojName = 'GotoProbe.dproj';

  cDprText =
    'program GotoProbe;'#13#10 +
    'uses'#13#10 +
    '  UGoto in ''UGoto.pas'';'#13#10 +
    'begin'#13#10 +
    'end.'#13#10;

  // Wie dpcc.Core.Lsp.Adapters.InProcess.Tests, mit eigener GUID und eigener Unit.
  cDprojText =
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '    <PropertyGroup>'#13#10 +
    '        <ProjectGuid>{3C8E1F42-9B7D-4E21-A6C5-7D2B9E0F1A34}</ProjectGuid>'#13#10 +
    '        <ProjectVersion>20.3</ProjectVersion>'#13#10 +
    '        <FrameworkType>None</FrameworkType>'#13#10 +
    '        <MainSource>GotoProbe.dpr</MainSource>'#13#10 +
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
    '        <DCCReference Include="UGoto.pas"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '    <ProjectExtensions>'#13#10 +
    '        <Borland.Personality>Delphi.Personality.12</Borland.Personality>'#13#10 +
    '        <Borland.ProjectType>Application</Borland.ProjectType>'#13#10 +
    '    </ProjectExtensions>'#13#10 +
    '</Project>'#13#10;

  /// <summary>Methodenname mit Umlauten: "Größe".</summary>
  cUmlautName = 'Gr'#$00F6#$00DF'e';

{ Hilfen }

function IsNameChar(AChar: Char): Boolean;
begin
  // Wie dpcc.Core.Editor.Navigation: Zeichen jenseits von ASCII zählen zum Namen.
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

/// <summary>Zeilen mit ABreak verbunden, ohne Umbruch am Ende.</summary>
function LinesWith(const ABreak: string; const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ABreak;
    end;
    Result := Result + ALines[mIndex];
  end;
end;

/// <summary>Zeilen mit CRLF wie im Editorpuffer unter Windows.</summary>
function Lines(const ALines: array of string): string;
begin
  Result := LinesWith(#13#10, ALines);
end;

function ClickCharacter(const ASpot: TGotoSpot; AClick: TGotoClick): Integer;
begin
  case AClick of
    TGotoClick.Middle:
      Result := ASpot.Character + ASpot.NameLength div 2;
    TGotoClick.Last:
      Result := ASpot.Character + ASpot.NameLength - 1;
    TGotoClick.Behind:
      Result := ASpot.Character + ASpot.NameLength;
  else
    Result := ASpot.Character;
  end;
end;

function Probe(const ACaption: string; const ASpot: TGotoSpot; AClick: TGotoClick): TGotoProbe;
begin
  Result.Caption := ACaption;
  Result.Spot := ASpot;
  Result.Click := AClick;
end;

/// <summary>Projektdateien und AText als UGoto.pas in AFolder.</summary>
procedure WriteProject(const AFolder, AText: string);
begin
  ForceDirectories(AFolder);
  TFile.WriteAllText(TPath.Combine(AFolder, cDprName), cDprText, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(AFolder, cDprojName), cDprojText, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(AFolder, cUnitName), AText, TEncoding.UTF8);
end;

/// <summary>Klasse TFoo mit einer Prozedur Bar (für die Pfadtests und die Zeilenenden).</summary>
function SimpleLines: TArray<string>;
begin
  Result := ['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public', '    procedure Bar;', '  end;',
    'implementation', 'procedure TFoo.Bar;', 'begin', 'end;', 'end.'];
end;

/// <summary>Klasse TFoo mit Berechne(A: Integer) (für die Klickstellen).</summary>
function ClickText: string;
begin
  Result := Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Berechne(A: Integer);', '  end;', 'implementation', 'procedure TFoo.Berechne(A: Integer);',
    'begin', 'end;', 'end.']);
end;

/// <summary>Viele Formen in einer Unit für den ungemessenen ersten Lauf.</summary>
function WarmUpText: string;
begin
  Result := Lines(['unit UGoto;', 'interface', 'type',
    '  TFoo = class',
    '  public type',
    '    TInner = class',
    '      procedure Innen;',
    '    end;',
    '  public',
    '    constructor Create; overload;',
    '    constructor Create(AValue: Integer); overload;',
    '    destructor Destroy; override;',
    '    procedure Bar(A: Integer); overload;',
    '    procedure Bar(const S: string); overload;',
    '    class function Make: TFoo; static;',
    '    procedure Neu<T>(const A: T);',
    '  end;',
    '  TListe<T> = class',
    '    procedure Setze(const A: T);',
    '  end;',
    '  TVec = record',
    '    X: Integer;',
    '    class operator Add(const A, B: TVec): TVec;',
    '  end;',
    'procedure Rechne(A: Integer); // Deklaration',
    'implementation',
    'procedure Hilfe; forward;',
    'procedure TFoo.TInner.Innen;', 'begin', 'end;',
    'constructor TFoo.Create;', 'begin', '  inherited Create;', 'end;',
    'constructor TFoo.Create(AValue: Integer);', 'begin', '  inherited Create;', 'end;',
    'destructor TFoo.Destroy;', 'begin', '  inherited;', 'end;',
    'procedure TFoo.Bar(A: Integer);', 'begin', 'end;',
    'procedure TFoo.Bar(const S: string);', 'begin', 'end;',
    'class function TFoo.Make: TFoo;', 'begin', '  Result := nil;', 'end;',
    'procedure TFoo.Neu<T>(const A: T);', 'begin', 'end;',
    'procedure TListe<T>.Setze(const A: T);', 'begin', 'end;',
    'class operator TVec.Add(const A, B: TVec): TVec;', 'begin', '  Result.X := A.X + B.X;', 'end;',
    'procedure Rechne(A: Integer); // Rumpf', 'begin', '  Hilfe;', 'end;',
    'procedure Hilfe; // Rumpf', 'begin', 'end;',
    'end.']);
end;

{ TGotoBothWaysTests }

procedure TGotoBothWaysTests.CreateRootAndWarmUp;
begin
  FRoot := TPath.Combine(TPath.GetTempPath, 'dpcc-goto-' + IntToStr(MainThreadID));
  ForceDirectories(FRoot);
  try
    Start(WarmUpText);
    AddPair('Bar', '    procedure Bar(A: Integer)', 'procedure TFoo.Bar(A: Integer)');
    AddPair('Bar', '    procedure Bar(const S: string)', 'procedure TFoo.Bar(const S: string)');
    AddPair('Create', '    constructor Create(AValue', 'constructor TFoo.Create(AValue');
    AddPair('Innen', '      procedure Innen;', 'procedure TFoo.TInner.Innen;');
    AddPair('Setze', '    procedure Setze(', 'procedure TListe<T>.Setze(');
    AddPair('Add', '    class operator Add(', 'class operator TVec.Add(');
    AddPair('Rechne', 'procedure Rechne(A: Integer); // Deklaration', 'procedure Rechne(A: Integer); // Rumpf');
    AddPair('Hilfe', 'procedure Hilfe; forward;', 'procedure Hilfe; // Rumpf');
  except
    // Scheitert der Lauf, meldet das der Test selbst.
    on Exception do
      ;
  end;
  Stop;
end;

procedure TGotoBothWaysTests.DeleteRoot;
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

procedure TGotoBothWaysTests.StopServer;
begin
  Stop;
end;

procedure TGotoBothWaysTests.Start(const AText: string);
begin
  Start(AText, TPath.Combine(FRoot, 'Projekt'), '');
end;

procedure TGotoBothWaysTests.Start(const AText, AFolder, AUnitFile: string);
var
  mServer: TLspInProcessServer;
begin
  Stop;
  FFolder := AFolder;
  FText := AText;
  WriteProject(FFolder, FText);
  FProjectFile := TPath.Combine(FFolder, cDprojName);
  FUnitFile := AUnitFile;
  if FUnitFile = '' then
  begin
    FUnitFile := TPath.Combine(FFolder, cUnitName);
  end;
  mServer := TLspInProcessServer.Create;
  FServerRef := mServer;
  Assert.IsTrue(FServerRef.Running, 'Server läuft nach dem Start');
  FSession := TLspSession.Create(FServerRef.Client, cTimeoutMs);
  FSession.SetProjects([FProjectFile]);
  FSession.Initialize;
  Assert.IsTrue(FSession.Initialized, 'initialize beantwortet');
  Assert.IsTrue(FSession.Supports('declarationProvider'), 'declarationProvider');
  Assert.IsTrue(FSession.Supports('definitionProvider'), 'definitionProvider');
  // didOpen im Hauptthread wie im Plugin; GotoTargetAt gleicht nicht selbst ab.
  FSession.Sync(FUnitFile, FText);
end;

procedure TGotoBothWaysTests.Stop;
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
  // Alles, was ein Test belegt, gibt das TearDown frei (Leckmonitor).
  FProbes := nil;
  FExpected := '';
  FActual := '';
  FErrors := '';
  FText := '';
  FFolder := '';
  FProjectFile := '';
  FUnitFile := '';
end;

function TGotoBothWaysTests.LineText(ALine: Integer): string;
var
  mTable: TLineTable;
begin
  // Wie LineOf in dpcc.IDE.CodeInsight.Manager.Queries.
  Result := '';
  mTable := TLineTable.Build(FText);
  if (ALine >= 0) and (ALine < mTable.LineCount) then
  begin
    Result := Copy(FText, mTable.LineStart(ALine) + 1, mTable.LineContentEnd(ALine) - mTable.LineStart(ALine));
  end;
end;

function TGotoBothWaysTests.SpotOf(const AMarker, AName: string): TGotoSpot;
var
  mMarker, mIndex, mAfter: Integer;
  mTable: TLineTable;
begin
  mMarker := Pos(AMarker, FText);
  if mMarker = 0 then
  begin
    raise Exception.CreateFmt('Testaufbau: "%s" nicht im Text', [AMarker]);
  end;
  for mIndex := mMarker to mMarker + Length(AMarker) - Length(AName) do
  begin
    mAfter := mIndex + Length(AName);
    if SameText(Copy(FText, mIndex, Length(AName)), AName) and
      ((mIndex = 1) or not IsNameChar(FText[mIndex - 1])) and
      ((mAfter > Length(FText)) or not IsNameChar(FText[mAfter])) then
    begin
      mTable := TLineTable.Build(FText);
      Result.Line := mTable.PositionAt(mIndex - 1).Line;
      Result.Character := mTable.PositionAt(mIndex - 1).Character;
      Result.NameLength := Length(AName);
      Exit;
    end;
  end;
  raise Exception.CreateFmt('Testaufbau: Name "%s" nicht in "%s"', [AName, AMarker]);
end;

function TGotoBothWaysTests.JumpLine(const ASpot: TGotoSpot; AClick: TGotoClick): Integer;
var
  mLocation: TLspLocation;
  mCharacter: Integer;
begin
  Result := -1;
  mCharacter := ClickCharacter(ASpot, AClick);
  try
    // Wie GotoWork im Plugin: ohne Abgleich, mit der Zeile aus dem abgeglichenen Text.
    if FSession.GotoTargetAt(FUnitFile, LineText(ASpot.Line), ASpot.Line, mCharacter, cTimeoutMs, mLocation) then
    begin
      Result := mLocation.Line;
    end;
  except
    on E: Exception do
    begin
      Result := -2;
      FErrors := FErrors + Format(' | Ausnahme an %d:%d: %s: %s', [ASpot.Line, mCharacter, E.ClassName,
        E.Message]);
    end;
  end;
end;

function TGotoBothWaysTests.AnswerText(ADeclaration: Boolean; const AProbe: TGotoProbe): string;
const
  cMethods: array[Boolean] of string = ('definition', 'declaration');
var
  mLocations: TArray<TLspLocation>;
  mLocation: TLspLocation;
  mCharacter: Integer;
  mFailure: string;
begin
  mCharacter := ClickCharacter(AProbe.Spot, AProbe.Click);
  mLocations := nil;
  mFailure := '';
  try
    if ADeclaration then
    begin
      mLocations := FSession.Declarations(FUnitFile, AProbe.Spot.Line, mCharacter);
    end
    else
    begin
      mLocations := FSession.Definitions(FUnitFile, AProbe.Spot.Line, mCharacter);
    end;
  except
    on E: Exception do
    begin
      mFailure := E.ClassName + ': ' + E.Message;
    end;
  end;
  Result := cMethods[ADeclaration];
  if mFailure <> '' then
  begin
    Result := Result + ' Ausnahme ' + mFailure;
  end
  else if Length(mLocations) = 0 then
  begin
    Result := Result + ' ohne Ziel';
  end;
  for mLocation in mLocations do
  begin
    Result := Result + Format(' %d:%d', [mLocation.Line, mLocation.Character]);
    if mLocation.FileName <> FUnitFile then
    begin
      Result := Result + ' in "' + mLocation.FileName + '"';
    end;
    Result := Result + ' OnTarget=' + BoolToStr(TDpccGotoDefinition.OnTarget(FUnitFile, AProbe.Spot.Line,
      mCharacter, LineText(AProbe.Spot.Line), mLocation.FileName, mLocation.Line, mLocation.Character), True);
  end;
end;

function TGotoBothWaysTests.ProbeText(const AProbe: TGotoProbe): string;
begin
  Result := Format('%s an %d:%d: %s; %s', [AProbe.Caption, AProbe.Spot.Line,
    ClickCharacter(AProbe.Spot, AProbe.Click), AnswerText(True, AProbe), AnswerText(False, AProbe)]);
end;

procedure TGotoBothWaysTests.AddPair(const AName, ADeclMarker, AImplMarker: string);
begin
  AddPair(AName, ADeclMarker, AImplMarker, TGotoClick.First);
end;

procedure TGotoBothWaysTests.AddPair(const AName, ADeclMarker, AImplMarker: string; AClick: TGotoClick);
var
  mDecl, mImpl: TGotoSpot;
  mNumber, mToImpl, mToDecl: Integer;
begin
  mDecl := SpotOf(ADeclMarker, AName);
  mImpl := SpotOf(AImplMarker, AName);
  mNumber := Length(FProbes) div 2 + 1;
  mToImpl := JumpLine(mDecl, AClick);
  mToDecl := JumpLine(mImpl, AClick);
  FExpected := FExpected + Format('[%d %s] Dekl->Impl %d, Impl->Dekl %d; ', [mNumber, AName, mImpl.Line,
    mDecl.Line]);
  FActual := FActual + Format('[%d %s] Dekl->Impl %d, Impl->Dekl %d; ', [mNumber, AName, mToImpl, mToDecl]);
  FProbes := FProbes + [Probe('Dekl ' + AName, mDecl, AClick), Probe('Impl ' + AName, mImpl, AClick)];
end;

procedure TGotoBothWaysTests.CheckPairs;
var
  mDetails: string;
  mProbe: TGotoProbe;
begin
  mDetails := FErrors;
  // Die rohen Antworten nur bei einer Abweichung: Sie kosten je Stelle zwei weitere Anfragen.
  if FActual <> FExpected then
  begin
    for mProbe in FProbes do
    begin
      mDetails := mDetails + ' | ' + ProbeText(mProbe);
    end;
  end;
  Assert.AreEqual(FExpected, FActual, 'Zeilen 0-basiert, -1 ohne Ziel' + mDetails);
end;

procedure TGotoBothWaysTests.CheckPathForm(const AFolder, AUnitFile: string);
var
  mDecl: TGotoSpot;
  mLocations: TArray<TLspLocation>;
  mServerFile: string;
  mSame: Boolean;
begin
  Start(Lines(SimpleLines), AFolder, AUnitFile);
  // Wie GotoTargetAt: declaration auf der Deklaration selbst liefert sie; OnTarget muss den Pfad des Servers als
  // dieselbe Datei erkennen, sonst bleibt der Sprung auf der Deklaration stehen.
  mDecl := SpotOf('    procedure Bar;', 'Bar');
  mLocations := FSession.Declarations(FUnitFile, mDecl.Line, mDecl.Character);
  mServerFile := '';
  mSame := False;
  if Length(mLocations) > 0 then
  begin
    mServerFile := mLocations[0].FileName;
    mSame := TDpccGotoDefinition.OnTarget(FUnitFile, mDecl.Line, mDecl.Character, LineText(mDecl.Line),
      mLocations[0].FileName, mLocations[0].Line, mLocations[0].Character);
  end;
  FErrors := FErrors + Format(' | Pfad der IDE "%s", Pfad vom Server "%s"', [FUnitFile, mServerFile]);
  AddPair('Bar', '    procedure Bar;', 'procedure TFoo.Bar;');
  FExpected := FExpected + 'gleiche Datei True';
  FActual := FActual + 'gleiche Datei ' + BoolToStr(mSame, True);
  CheckPairs;
end;

{ 1. Einfache Formen }

procedure TGotoBothWaysTests.SimpleProcedure;
begin
  Start(Lines(SimpleLines));
  AddPair('Bar', '    procedure Bar;', 'procedure TFoo.Bar;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.FunctionWithParameters;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    function Rechne(A: Integer; const S: string): Integer;', '  end;', 'implementation',
    'function TFoo.Rechne(A: Integer; const S: string): Integer;', 'begin', '  Result := A + Length(S);', 'end;',
    'end.']));
  AddPair('Rechne', '    function Rechne(', 'function TFoo.Rechne(');
  CheckPairs;
end;

{ 2. Implementierung ohne Parameterliste }

procedure TGotoBothWaysTests.ImplementationWithoutParameterList;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    constructor Create(AOwner: TObject);', '    procedure Setze(A: Integer; const S: string);', '  end;',
    'implementation', 'constructor TFoo.Create;', 'begin', '  inherited Create;', 'end;', 'procedure TFoo.Setze;',
    'begin', 'end;', 'end.']));
  AddPair('Setze', '    procedure Setze(', 'procedure TFoo.Setze;');
  AddPair('Create', '    constructor Create(', 'constructor TFoo.Create;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.FunctionImplementationWithoutParametersAndResult;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    function Rechne(A: Integer): Integer;', '  end;', 'implementation', 'function TFoo.Rechne;', 'begin',
    '  Result := A;', 'end;', 'end.']));
  AddPair('Rechne', '    function Rechne(', 'function TFoo.Rechne;');
  CheckPairs;
end;

{ 3. Abweichende Schreibweise }

procedure TGotoBothWaysTests.SpacingDiffers;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Setze(A:Integer;const S:string);', '  end;', 'implementation',
    'procedure TFoo.Setze(A: Integer; const S: string);', 'begin', 'end;', 'end.']));
  AddPair('Setze', '    procedure Setze(', 'procedure TFoo.Setze(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.TypeCaseDiffers;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Setze(A: integer; S: STRING);', '  end;', 'implementation',
    'procedure TFoo.Setze(A: Integer; S: string);', 'begin', 'end;', 'end.']));
  AddPair('Setze', '    procedure Setze(', 'procedure TFoo.Setze(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.ImplementationNameCaseDiffers;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Setze(A: Integer);', '  end;', 'implementation', 'procedure tfoo.setze(A: Integer);', 'begin',
    'end;', 'end.']));
  AddPair('Setze', '    procedure Setze(', 'procedure tfoo.setze(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.DefaultValuesOnlyInDeclaration;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Setze(A: Integer = 0; const S: string = ''x'');', '  end;', 'implementation',
    'procedure TFoo.Setze(A: Integer; const S: string);', 'begin', 'end;', 'end.']));
  AddPair('Setze', '    procedure Setze(', 'procedure TFoo.Setze(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.QualifiedTypeName;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Setze(A: System.Integer; B: System.Byte);', '  end;', 'implementation',
    'procedure TFoo.Setze(A: Integer; B: Byte);', 'begin', 'end;', 'end.']));
  AddPair('Setze', '    procedure Setze(', 'procedure TFoo.Setze(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.LineBreakInParameterList;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Setze(A: Integer; const S: string);',
    '    procedure Lege(A: Integer;',
    '      const S: string);',
    '  end;', 'implementation',
    'procedure TFoo.Setze(A: Integer;',
    '  const S: string);',
    'begin', 'end;',
    'procedure TFoo.Lege(A: Integer; const S: string);',
    'begin', 'end;', 'end.']));
  AddPair('Setze', '    procedure Setze(', 'procedure TFoo.Setze(');
  AddPair('Lege', '    procedure Lege(', 'procedure TFoo.Lege(');
  CheckPairs;
end;

{ 4. Überladungen }

procedure TGotoBothWaysTests.OverloadsTwo;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Bar(A: Integer); overload;', '    procedure Bar(const S: string); overload;', '  end;',
    'implementation', 'procedure TFoo.Bar(A: Integer);', 'begin', 'end;', 'procedure TFoo.Bar(const S: string);',
    'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar(A: Integer)', 'procedure TFoo.Bar(A: Integer)');
  AddPair('Bar', '    procedure Bar(const S: string)', 'procedure TFoo.Bar(const S: string)');
  CheckPairs;
end;

procedure TGotoBothWaysTests.OverloadsThree;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public', '    procedure Bar; overload;',
    '    procedure Bar(A: Integer); overload;', '    procedure Bar(A, B: Integer); overload;', '  end;',
    'implementation', 'procedure TFoo.Bar;', 'begin', 'end;', 'procedure TFoo.Bar(A: Integer);', 'begin', 'end;',
    'procedure TFoo.Bar(A, B: Integer);', 'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar;', 'procedure TFoo.Bar;');
  AddPair('Bar', '    procedure Bar(A: Integer)', 'procedure TFoo.Bar(A: Integer)');
  AddPair('Bar', '    procedure Bar(A, B: Integer)', 'procedure TFoo.Bar(A, B: Integer)');
  CheckPairs;
end;

procedure TGotoBothWaysTests.OverloadsImplementationOrderReversed;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Bar(A: Integer); overload;', '    procedure Bar(const S: string); overload;',
    '    procedure Bar(A: Integer; const S: string); overload;', '  end;', 'implementation',
    'procedure TFoo.Bar(A: Integer; const S: string);', 'begin', 'end;', 'procedure TFoo.Bar(const S: string);',
    'begin', 'end;', 'procedure TFoo.Bar(A: Integer);', 'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar(A: Integer);', 'procedure TFoo.Bar(A: Integer);');
  AddPair('Bar', '    procedure Bar(const S: string);', 'procedure TFoo.Bar(const S: string);');
  AddPair('Bar', '    procedure Bar(A: Integer; const S', 'procedure TFoo.Bar(A: Integer; const S');
  CheckPairs;
end;

procedure TGotoBothWaysTests.OverloadsSpacingDiffers;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Bar(A:Integer;B:Integer); overload;', '    procedure Bar(const S:string); overload;', '  end;',
    'implementation', 'procedure TFoo.Bar(A: Integer; B: Integer);', 'begin', 'end;',
    'procedure TFoo.Bar(const S: string);', 'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar(A:Integer', 'procedure TFoo.Bar(A: Integer');
  AddPair('Bar', '    procedure Bar(const S:string)', 'procedure TFoo.Bar(const S: string)');
  CheckPairs;
end;

procedure TGotoBothWaysTests.OverloadsCaseDiffers;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Bar(A: integer); overload;', '    procedure Bar(const S: String); overload;', '  end;',
    'implementation', 'procedure tfoo.bar(A: Integer);', 'begin', 'end;', 'procedure TFoo.Bar(const S: string);',
    'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar(A: integer)', 'procedure tfoo.bar(A: Integer)');
  AddPair('Bar', '    procedure Bar(const S: String)', 'procedure TFoo.Bar(const S: string)');
  CheckPairs;
end;

procedure TGotoBothWaysTests.OverloadsDefaultValuesOnlyInDeclaration;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Bar(A: Integer; B: Integer = 0); overload;',
    '    procedure Bar(const S: string; B: Integer = 0); overload;', '  end;', 'implementation',
    'procedure TFoo.Bar(A: Integer; B: Integer);', 'begin', 'end;', 'procedure TFoo.Bar(const S: string; B: Integer);',
    'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar(A: Integer', 'procedure TFoo.Bar(A: Integer');
  AddPair('Bar', '    procedure Bar(const S: string', 'procedure TFoo.Bar(const S: string');
  CheckPairs;
end;

procedure TGotoBothWaysTests.OverloadsQualifiedTypeName;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Bar(A: System.Integer); overload;', '    procedure Bar(const S: string); overload;', '  end;',
    'implementation', 'procedure TFoo.Bar(A: Integer);', 'begin', 'end;', 'procedure TFoo.Bar(const S: string);',
    'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar(A: System.Integer)', 'procedure TFoo.Bar(A: Integer)');
  AddPair('Bar', '    procedure Bar(const S: string)', 'procedure TFoo.Bar(const S: string)');
  CheckPairs;
end;

procedure TGotoBothWaysTests.OverloadsLineBreakInParameterList;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Bar(A: Integer; B: Integer); overload;', '    procedure Bar(const S: string; B: Integer); overload;',
    '  end;', 'implementation',
    'procedure TFoo.Bar(A: Integer;',
    '  B: Integer);',
    'begin', 'end;',
    'procedure TFoo.Bar(const S: string;',
    '  B: Integer);',
    'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar(A: Integer;', 'procedure TFoo.Bar(A: Integer;');
  AddPair('Bar', '    procedure Bar(const S: string;', 'procedure TFoo.Bar(const S: string;');
  CheckPairs;
end;

{ 5. Methodenarten und Direktiven }

procedure TGotoBothWaysTests.ConstructorBothWays;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    constructor Create(AOwner: TObject);', '  end;', 'implementation', 'constructor TFoo.Create(AOwner: TObject);',
    'begin', '  inherited Create;', 'end;', 'end.']));
  AddPair('Create', '    constructor Create(', 'constructor TFoo.Create(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.ConstructorOverloads;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public', '    constructor Create; overload;',
    '    constructor Create(AValue: Integer); overload;', '  end;', 'implementation', 'constructor TFoo.Create;',
    'begin', '  inherited Create;', 'end;', 'constructor TFoo.Create(AValue: Integer);', 'begin', '  Create;', 'end;',
    'end.']));
  AddPair('Create', '    constructor Create;', 'constructor TFoo.Create;');
  AddPair('Create', '    constructor Create(AValue', 'constructor TFoo.Create(AValue');
  CheckPairs;
end;

procedure TGotoBothWaysTests.DestructorOverride;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public', '    destructor Destroy; override;',
    '  end;', 'implementation', 'destructor TFoo.Destroy;', 'begin', '  inherited;', 'end;', 'end.']));
  AddPair('Destroy', '    destructor Destroy;', 'destructor TFoo.Destroy;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.ClassProcedure;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public', '    class procedure Reset;',
    '  end;', 'implementation', 'class procedure TFoo.Reset;', 'begin', 'end;', 'end.']));
  AddPair('Reset', '    class procedure Reset;', 'class procedure TFoo.Reset;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.ClassFunctionStatic;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    class function Make: TFoo; static;', '  end;', 'implementation', 'class function TFoo.Make: TFoo;', 'begin',
    '  Result := nil;', 'end;', 'end.']));
  AddPair('Make', '    class function Make:', 'class function TFoo.Make:');
  CheckPairs;
end;

procedure TGotoBothWaysTests.VirtualMethod;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public', '    procedure Run; virtual;',
    '  end;', 'implementation', 'procedure TFoo.Run;', 'begin', 'end;', 'end.']));
  AddPair('Run', '    procedure Run; virtual;', 'procedure TFoo.Run;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.OverrideInDescendant;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TBase = class', '  public', '    procedure Run; virtual;',
    '  end;', '  TChild = class(TBase)', '  public', '    procedure Run; override;', '  end;', 'implementation',
    'procedure TBase.Run;', 'begin', 'end;', 'procedure TChild.Run;', 'begin', '  inherited;', 'end;', 'end.']));
  AddPair('Run', '    procedure Run; virtual;', 'procedure TBase.Run;');
  AddPair('Run', '    procedure Run; override;', 'procedure TChild.Run;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.OverloadDirectiveWithoutSecondVariant;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Bar(A: Integer); overload;', '  end;', 'implementation', 'procedure TFoo.Bar(A: Integer);', 'begin',
    'end;', 'end.']));
  AddPair('Bar', '    procedure Bar(', 'procedure TFoo.Bar(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.MessageMethod;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TMessage = record', '    Msg: Cardinal;', '  end;',
    '  TFoo = class', '  private', '    procedure WMSize(var Message: TMessage); message 5;', '  end;',
    'implementation', 'procedure TFoo.WMSize(var Message: TMessage);', 'begin', '  inherited;', 'end;', 'end.']));
  AddPair('WMSize', '    procedure WMSize(', 'procedure TFoo.WMSize(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.InlineAndCallingConvention;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    function Calc(A: Integer): Integer; inline;', '    procedure Notify(A: Integer); stdcall;', '  end;',
    'implementation', 'function TFoo.Calc(A: Integer): Integer;', 'begin', '  Result := A;', 'end;',
    'procedure TFoo.Notify(A: Integer); stdcall;', 'begin', 'end;', 'end.']));
  AddPair('Calc', '    function Calc(', 'function TFoo.Calc(');
  AddPair('Notify', '    procedure Notify(', 'procedure TFoo.Notify(');
  CheckPairs;
end;

{ 6. Generics }

procedure TGotoBothWaysTests.GenericClassMethod;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo<T> = class', '  public', '    procedure Bar;', '  end;',
    'implementation', 'procedure TFoo<T>.Bar;', 'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar;', 'procedure TFoo<T>.Bar;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.GenericClassMethodWithTypeParameter;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo<T> = class', '  public', '    procedure Setze(const A: T);',
    '    function Hole: T;', '  end;', 'implementation', 'procedure TFoo<T>.Setze(const A: T);', 'begin', 'end;',
    'function TFoo<T>.Hole: T;', 'begin', '  Result := Default(T);', 'end;', 'end.']));
  AddPair('Setze', '    procedure Setze(', 'procedure TFoo<T>.Setze(');
  AddPair('Hole', '    function Hole:', 'function TFoo<T>.Hole:');
  CheckPairs;
end;

procedure TGotoBothWaysTests.GenericClassWithTwoTypeParameters;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TPaar<TKey, TValue> = class', '  public',
    '    procedure Setze(const AKey: TKey; const AValue: TValue);', '  end;', 'implementation',
    'procedure TPaar<TKey, TValue>.Setze(const AKey: TKey; const AValue: TValue);', 'begin', 'end;', 'end.']));
  AddPair('Setze', '    procedure Setze(', 'procedure TPaar<TKey, TValue>.Setze(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.GenericClassWithConstraint;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TRepo<T: class, constructor> = class', '  public',
    '    function Neu: T;', '  end;', 'implementation', 'function TRepo<T>.Neu: T;', 'begin', '  Result := T.Create;',
    'end;', 'end.']));
  AddPair('Neu', '    function Neu:', 'function TRepo<T>.Neu:');
  CheckPairs;
end;

procedure TGotoBothWaysTests.GenericMethod;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public', '    procedure Bar<T>(const A: T);',
    '  end;', 'implementation', 'procedure TFoo.Bar<T>(const A: T);', 'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar<T>(', 'procedure TFoo.Bar<T>(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.GenericMethodWithPlainOverload;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure Bar<T>(const A: T); overload;', '    procedure Bar(A: Integer); overload;', '  end;',
    'implementation', 'procedure TFoo.Bar<T>(const A: T);', 'begin', 'end;', 'procedure TFoo.Bar(A: Integer);',
    'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar<T>(', 'procedure TFoo.Bar<T>(');
  AddPair('Bar', '    procedure Bar(A: Integer)', 'procedure TFoo.Bar(A: Integer)');
  CheckPairs;
end;

{ 7. Records, Operatoren, verschachtelte Typen }

procedure TGotoBothWaysTests.RecordMethod;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TPunkt = record', '    X, Y: Integer;',
    '    procedure Verschiebe(DX, DY: Integer);', '    function Laenge: Integer;', '  end;', 'implementation',
    'procedure TPunkt.Verschiebe(DX, DY: Integer);', 'begin', '  Inc(X, DX);', '  Inc(Y, DY);', 'end;',
    'function TPunkt.Laenge: Integer;', 'begin', '  Result := Abs(X) + Abs(Y);', 'end;', 'end.']));
  AddPair('Verschiebe', '    procedure Verschiebe(', 'procedure TPunkt.Verschiebe(');
  AddPair('Laenge', '    function Laenge:', 'function TPunkt.Laenge:');
  CheckPairs;
end;

procedure TGotoBothWaysTests.ClassOperator;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TVec = record', '    X: Integer;',
    '    class operator Add(const A, B: TVec): TVec;', '    class operator Equal(const A, B: TVec): Boolean;', '  end;',
    'implementation', 'class operator TVec.Add(const A, B: TVec): TVec;', 'begin', '  Result.X := A.X + B.X;',
    'end;', 'class operator TVec.Equal(const A, B: TVec): Boolean;', 'begin', '  Result := A.X = B.X;', 'end;',
    'end.']));
  AddPair('Add', '    class operator Add(', 'class operator TVec.Add(');
  AddPair('Equal', '    class operator Equal(', 'class operator TVec.Equal(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.ClassOperatorOverloads;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TVec = record', '    X: Integer;',
    '    class operator Implicit(A: Integer): TVec;', '    class operator Implicit(const A: TVec): Integer;', '  end;',
    'implementation', 'class operator TVec.Implicit(A: Integer): TVec;', 'begin', '  Result.X := A;', 'end;',
    'class operator TVec.Implicit(const A: TVec): Integer;', 'begin', '  Result := A.X;', 'end;', 'end.']));
  AddPair('Implicit', '    class operator Implicit(A: Integer)', 'class operator TVec.Implicit(A: Integer)');
  AddPair('Implicit', '    class operator Implicit(const A: TVec)', 'class operator TVec.Implicit(const A: TVec)');
  CheckPairs;
end;

procedure TGotoBothWaysTests.ClassOperatorDiffersOnlyByResultType;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TVec = record', '    X: Integer;',
    '    class operator Implicit(const A: TVec): Integer;', '    class operator Implicit(const A: TVec): string;',
    '  end;', 'implementation', 'class operator TVec.Implicit(const A: TVec): Integer;', 'begin', '  Result := A.X;',
    'end;', 'class operator TVec.Implicit(const A: TVec): string;', 'begin', '  Result := '''';', 'end;', 'end.']));
  AddPair('Implicit', '    class operator Implicit(const A: TVec): Integer;',
    'class operator TVec.Implicit(const A: TVec): Integer;');
  AddPair('Implicit', '    class operator Implicit(const A: TVec): string;',
    'class operator TVec.Implicit(const A: TVec): string;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.NestedTypeMethod;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TOuter = class', '  public type', '    TInner = class',
    '    public', '      procedure Bar; // TInner', '    end;', '  public', '    procedure Bar; // TOuter', '  end;',
    'implementation', 'procedure TOuter.TInner.Bar;', 'begin', 'end;', 'procedure TOuter.Bar;', 'begin', 'end;',
    'end.']));
  AddPair('Bar', '      procedure Bar; // TInner', 'procedure TOuter.TInner.Bar;');
  AddPair('Bar', '    procedure Bar; // TOuter', 'procedure TOuter.Bar;');
  CheckPairs;
end;

{ 8. Freie Routinen }

procedure TGotoBothWaysTests.FreeRoutineInterfaceAndImplementation;
begin
  Start(Lines(['unit UGoto;', 'interface', 'procedure Rechne(A: Integer); // Deklaration',
    'function Summe(A, B: Integer): Integer; // Deklaration', 'implementation',
    'procedure Rechne(A: Integer); // Rumpf', 'begin', 'end;', 'function Summe(A, B: Integer): Integer; // Rumpf',
    'begin', '  Result := A + B;', 'end;', 'end.']));
  AddPair('Rechne', 'procedure Rechne(A: Integer); // Deklaration', 'procedure Rechne(A: Integer); // Rumpf');
  AddPair('Summe', 'function Summe(A, B: Integer): Integer; // Deklaration',
    'function Summe(A, B: Integer): Integer; // Rumpf');
  CheckPairs;
end;

procedure TGotoBothWaysTests.FreeRoutineImplementationWithoutParameterList;
begin
  Start(Lines(['unit UGoto;', 'interface', 'function Summe(A, B: Integer): Integer;', 'implementation',
    'function Summe;', 'begin', '  Result := A + B;', 'end;', 'end.']));
  AddPair('Summe', 'function Summe(A', 'function Summe;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.FreeRoutineOverloads;
begin
  Start(Lines(['unit UGoto;', 'interface', 'procedure Rechne(A: Integer); overload;',
    'procedure Rechne(const S: string); overload;', 'implementation', 'procedure Rechne(const S: string); // Rumpf',
    'begin', 'end;', 'procedure Rechne(A: Integer); // Rumpf', 'begin', 'end;', 'end.']));
  AddPair('Rechne', 'procedure Rechne(A: Integer); overload;', 'procedure Rechne(A: Integer); // Rumpf');
  AddPair('Rechne', 'procedure Rechne(const S: string); overload;', 'procedure Rechne(const S: string); // Rumpf');
  CheckPairs;
end;

procedure TGotoBothWaysTests.ForwardDeclaration;
begin
  Start(Lines(['unit UGoto;', 'interface', 'implementation', 'procedure Hilfe(A: Integer); forward;',
    'procedure Nutze;', 'begin', '  Hilfe(1);', 'end;', 'procedure Hilfe(A: Integer); // Rumpf', 'begin', 'end;',
    'end.']));
  AddPair('Hilfe', 'procedure Hilfe(A: Integer); forward;', 'procedure Hilfe(A: Integer); // Rumpf');
  CheckPairs;
end;

{ 9. Klickstelle, Tabs, Zeichen, Zeilenenden }

procedure TGotoBothWaysTests.ClickOnFirstCharacter;
begin
  Start(ClickText);
  AddPair('Berechne', '    procedure Berechne(', 'procedure TFoo.Berechne(', TGotoClick.First);
  CheckPairs;
end;

procedure TGotoBothWaysTests.ClickInMiddleOfName;
begin
  Start(ClickText);
  AddPair('Berechne', '    procedure Berechne(', 'procedure TFoo.Berechne(', TGotoClick.Middle);
  CheckPairs;
end;

procedure TGotoBothWaysTests.ClickOnLastCharacter;
begin
  Start(ClickText);
  AddPair('Berechne', '    procedure Berechne(', 'procedure TFoo.Berechne(', TGotoClick.Last);
  CheckPairs;
end;

procedure TGotoBothWaysTests.ClickDirectlyBehindName;
begin
  Start(ClickText);
  AddPair('Berechne', '    procedure Berechne(', 'procedure TFoo.Berechne(', TGotoClick.Behind);
  CheckPairs;
end;

procedure TGotoBothWaysTests.TabIndentedDeclaration;
var
  mDecl: TGotoSpot;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', #9'TFoo = class', #9'public', #9#9'procedure Berechne(A: Integer);',
    #9'end;', 'implementation', 'procedure TFoo.Berechne(A: Integer);', 'begin', #9'if A > 0 then', #9#9'Exit;',
    'end;', 'end.']));
  mDecl := SpotOf(#9#9'procedure Berechne(', 'Berechne');
  // Zwei Tabs und "procedure ": "Berechne" ist Zeichen 12; bei Tabweite 8 steht es in Editorspalte 27. So rechnet
  // das Plugin die Stelle der IDE um (ColumnToIndex mit TDpccEditorBuffer.TabWidth).
  Assert.AreEqual(12, mDecl.Character, 'Testaufbau: Zeichen von Berechne');
  Assert.AreEqual(12, TLspSession.ColumnToIndex(LineText(mDecl.Line), 27, 8), 'Editorspalte 27 bei Tabweite 8');
  AddPair('Berechne', #9#9'procedure Berechne(', 'procedure TFoo.Berechne(');
  AddPair('Berechne', #9#9'procedure Berechne(', 'procedure TFoo.Berechne(', TGotoClick.Last);
  CheckPairs;
end;

procedure TGotoBothWaysTests.UmlautInMethodName;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    function ' + cUmlautName + ': Integer;', '  end;', 'implementation',
    'function TFoo.' + cUmlautName + ': Integer;', 'begin', '  Result := 0;', 'end;', 'end.']));
  AddPair(cUmlautName, '    function ' + cUmlautName, 'function TFoo.' + cUmlautName);
  CheckPairs;
end;

procedure TGotoBothWaysTests.NonBmpCharacterBeforeName;
begin
  // U+1F600 als Ersatzpaar: zählt in UTF-16 doppelt, als Codepunkt einfach.
  Start(Lines(['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public',
    '    {'#$D83D#$DE00'} procedure Bar;', '  end;', 'implementation', 'procedure TFoo.Bar; {'#$D83D#$DE00'}', 'begin',
    'end;', 'end.']));
  AddPair('Bar', '} procedure Bar;', 'procedure TFoo.Bar;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.LfLineEndings;
begin
  Start(LinesWith(#10, SimpleLines));
  AddPair('Bar', '    procedure Bar;', 'procedure TFoo.Bar;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.MixedLineEndings;
begin
  Start(LinesWith(#13#10, ['unit UGoto;', 'interface', 'type', '  TFoo = class', '  public', '    procedure Bar;',
    '    procedure Baz(A: Integer);', '  end;', 'implementation']) + #10 + LinesWith(#10, ['procedure TFoo.Bar;',
    'begin', 'end;', 'procedure TFoo.Baz(A: Integer);', 'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar;', 'procedure TFoo.Bar;');
  AddPair('Baz', '    procedure Baz(', 'procedure TFoo.Baz(');
  CheckPairs;
end;

{ 10. Dateipfad }

procedure TGotoBothWaysTests.PathWithSpaces;
begin
  CheckPathForm(TPath.Combine(FRoot, 'Ordner mit Leer zeichen'), '');
end;

procedure TGotoBothWaysTests.PathWithUmlauts;
begin
  // "Pfad-ÄÖÜäöüß" über Zeichencodes: unabhängig von der Kodierung dieser Datei.
  CheckPathForm(TPath.Combine(FRoot, 'Pfad-'#$00C4#$00D6#$00DC#$00E4#$00F6#$00FC#$00DF), '');
end;

procedure TGotoBothWaysTests.PathWithBrackets;
begin
  CheckPathForm(TPath.Combine(FRoot, 'Kopie (2) [alt] {x}'), '');
end;

procedure TGotoBothWaysTests.PathWithHashAndPercent;
begin
  CheckPathForm(TPath.Combine(FRoot, 'Nr#1 100% %41'), '');
end;

procedure TGotoBothWaysTests.PathWithUriSpecialCharacters;
begin
  CheckPathForm(TPath.Combine(FRoot, 'a+b&c;d=e,f!g$h@i~j'), '');
end;

procedure TGotoBothWaysTests.DriveLetterLowerCase;
var
  mFolder, mFile: string;
begin
  mFolder := TPath.Combine(FRoot, 'Laufwerk-klein');
  mFile := TPath.Combine(mFolder, cUnitName);
  if (Length(mFile) >= 2) and (mFile[2] = ':') then
  begin
    mFile := LowerCase(mFile[1]) + Copy(mFile, 2, MaxInt);
  end;
  CheckPathForm(mFolder, mFile);
end;

procedure TGotoBothWaysTests.DriveLetterUpperCase;
var
  mFolder, mFile: string;
begin
  mFolder := TPath.Combine(FRoot, 'Laufwerk-gross');
  mFile := TPath.Combine(mFolder, cUnitName);
  if (Length(mFile) >= 2) and (mFile[2] = ':') then
  begin
    mFile := UpperCase(mFile[1]) + Copy(mFile, 2, MaxInt);
  end;
  CheckPathForm(mFolder, mFile);
end;

procedure TGotoBothWaysTests.MixedSlashes;
var
  mFolder: string;
begin
  mFolder := TPath.Combine(TPath.Combine(FRoot, 'Schraeg'), 'Unter');
  CheckPathForm(mFolder, FRoot + '/Schraeg/Unter/' + cUnitName);
end;

procedure TGotoBothWaysTests.ForwardSlashesOnly;
var
  mFolder: string;
begin
  mFolder := TPath.Combine(FRoot, 'NurSchraeg');
  CheckPathForm(mFolder, StringReplace(TPath.Combine(mFolder, cUnitName), '\', '/', [rfReplaceAll]));
end;

procedure TGotoBothWaysTests.PathWithDotSegments;
var
  mFolder: string;
begin
  mFolder := TPath.Combine(FRoot, 'Punkte');
  ForceDirectories(TPath.Combine(mFolder, 'Unter'));
  CheckPathForm(mFolder, mFolder + '\Unter\..\' + cUnitName);
end;

{ 11. Gleichnamige Methoden und weitere Formen }

procedure TGotoBothWaysTests.SameMethodNameInSeveralClasses;
begin
  Start(Lines(['unit UGoto;', 'interface', 'type', '  IRun = interface', '    procedure Run;', '  end;',
    '  TA = class(TInterfacedObject, IRun)', '  public', '    procedure Run; // TA', '  end;', '  TB = class',
    '  public', '    procedure Run; // TB', '  end;', '  TC = class(TA)', '  public',
    '    procedure Run; reintroduce; // TC', '  end;', 'implementation', 'procedure Run;', 'begin', 'end;',
    'procedure TC.Run;', 'begin', 'end;', 'procedure TB.Run;', 'begin', 'end;', 'procedure TA.Run;', 'begin', 'end;',
    'end.']));
  AddPair('Run', '    procedure Run; // TA', 'procedure TA.Run;');
  AddPair('Run', '    procedure Run; // TB', 'procedure TB.Run;');
  AddPair('Run', '    procedure Run; reintroduce; // TC', 'procedure TC.Run;');
  CheckPairs;
end;

procedure TGotoBothWaysTests.ClassInImplementationSection;
begin
  Start(Lines(['unit UGoto;', 'interface', 'implementation', 'type', '  TIntern = class', '  public',
    '    procedure Bar(A: Integer);', '  end;', 'procedure TIntern.Bar(A: Integer);', 'begin', 'end;', 'end.']));
  AddPair('Bar', '    procedure Bar(', 'procedure TIntern.Bar(');
  CheckPairs;
end;

procedure TGotoBothWaysTests.FormUnitWithUsesAndResourceDirective;
begin
  Start(Lines(['unit UGoto;', '', 'interface', '', 'uses',
    '  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;', '',
    'type', '  TForm1 = class(TForm)', '    Button1: TButton;', '    procedure Button1Click(Sender: TObject);',
    '    procedure FormCreate(Sender: TObject);', '  private', '    { Private-Deklarationen }',
    '    procedure Aktualisiere;', '  public', '    { Public-Deklarationen }', '  end;', '', 'var',
    '  Form1: TForm1;', '', 'implementation', '', '{$R *.dfm}', '', 'procedure TForm1.Button1Click(Sender: TObject);',
    'begin', '  Aktualisiere;', 'end;', '', 'procedure TForm1.FormCreate(Sender: TObject);', 'begin', 'end;', '',
    'procedure TForm1.Aktualisiere;', 'begin', 'end;', '', 'end.']));
  AddPair('Button1Click', '    procedure Button1Click(', 'procedure TForm1.Button1Click(');
  AddPair('FormCreate', '    procedure FormCreate(', 'procedure TForm1.FormCreate(');
  AddPair('Aktualisiere', '    procedure Aktualisiere;', 'procedure TForm1.Aktualisiere;');
  CheckPairs;
end;

initialization
  TDUnitX.RegisterTestFixture(TGotoBothWaysTests);

end.
