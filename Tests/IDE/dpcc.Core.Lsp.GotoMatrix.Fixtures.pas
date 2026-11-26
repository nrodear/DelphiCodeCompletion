unit dpcc.Core.Lsp.GotoMatrix.Fixtures;

// Fixture-Projekt und Tabelle der Sprungmatrix für dpcc.Core.Lsp.GotoMatrix.Tests.
// Ein Projekt mit mehreren Units wie in der IDE: UNutzer (Ausgangsstellen), UBasis (Ziele in einer anderen Unit),
// UGenerisch (TPaar und TPaar<T> mit gleichnamiger Methode), ULetzte (Ziel in der letzten Zeile, ohne Umbruch am
// Ende), Such\USuch (nur über DCC_UnitSearchPath zu finden), Teile.inc (Deklaration im interface über {$I}),
// Methoden.inc (Methodendeklaration im Klassenrumpf über {$I}) und Leer.inc (über {$INCLUDE}, nur ein Kommentar).
// Jede Zeile der Tabelle (TJumpCase) ist eine Variante: Ausgangsstelle → erwartetes Ziel → Rückweg. Der Rückweg ist
// ein zweiter Strg+Klick auf dem Ziel (Gegensprung): ToOrigin (Deklaration ↔ Implementierung), Stays (Ziel ist schon
// die Deklaration, kein Gegenstück), ToOther (Deklaration einer Routine → ihre Implementierung). Die Rückkehr zur
// Ausgangsstelle über einen Sprungverlauf führt dpcc nicht selbst (nur der Verlauf der IDE, nicht hier prüfbar).
// Die Erwartung ist das GEWÜNSCHTE Verhalten (Entscheidungen des Nutzers vom 26.11.2026):
//   - Deklaration ohne Rumpf (Interface-, abstrakte Methode): stehen bleiben; zwei solche Überladungen dürfen nicht
//     zueinander springen (Tag cTagSuspect).
//   - "inherited;" ohne Namen: zur Deklaration der gleichnamigen Methode im Vorfahren (cTagNew).
//   - Strg+Klick während des Indexaufbaus: sofort, ohne Sprung, mit der Meldung „Index wird aufgebaut, bitte erneut
//     klicken“ statt „kein Ziel“ (cTagNew).
//   - Dateiname in {$I …} bzw. {$INCLUDE …}: die Datei öffnen, Zeile 1 (cTagNew); {$R *.dfm} bleibt ohne Sprung.
// Nicht vom Nutzer entschieden, Erwartung = heutiges Verhalten (cTagToday): Verwendung einer Methode → Deklaration
// (alle Zeilen Usage…Method/Overload/Helper), Result → Kopf der Routine, "System" in System.SysUtils → Unit
// System.SysUtils; einen eigenen Rücksprung-Verlauf führt dpcc nicht (hier nicht geprüft).
// Tag cTagSuspect: Verdacht aus Phase 1, fachlich richtige Erwartung, darf rot sein.
// Marker: eindeutiger Textausschnitt der Zeile, Name: ganzes Wort darin (erstes Vorkommen im Marker).

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Klickstelle im Namen; PastLineEnd = zehn Zeichen hinter dem Zeilenende.</summary>
  TJumpClick = (First, Middle, Last, Behind, PastLineEnd);
  TJumpEncoding = (Utf8Bom, Utf8, Ansi);
  /// <summary>Aufbau des Projekts: Standard oder eine Abwandlung für Datei- und Pfad-Randfälle.</summary>
  TJumpSetup = (Standard, SourceBufferShifted, TargetBufferShifted, TargetUtf8Bom, TargetUtf8NoBom, TargetAnsi,
    TargetTabs, TargetLfOnly, PathCaseDiffers, PathShortForm, DprojDotSegments, NoIndexWait);
  TJumpBack = (None, ToOrigin, Stays, ToOther);

  TJumpCase = (
    // A. Deklaration ↔ Implementierung im Projekt mit mehreren Units
    DeclImplOverrideInDescendant,
    DeclImplMethodOverloadInOtherUnit,
    DeclImplOverrideOfAbstractOverload,
    DeclImplClassHelper,
    DeclImplRecordHelper,
    DeclImplPropertyGetter,
    DeclImplFreeOverloadSameParamNameInteger,
    DeclImplFreeOverloadSameParamNameDouble,
    DeclImplExternalInImplementation,
    DeclImplAbstractOverloadFirstStays,
    DeclImplAbstractOverloadSecondStays,
    DeclImplInterfaceOverloadFirstStays,
    DeclImplInterfaceOverloadSecondStays,
    DeclImplInterfaceMethodStays,
    DeclImplPlainAndGenericSameNamePlain,
    DeclImplPlainAndGenericSameNameGeneric,
    DeclImplLastLineOfFile,
    DeclImplMethodFromIncludeInClassBody,
    DeclImplFreeRoutineFromInclude,
    DeclImplBackFromIncludeFile,
    DeclImplDprojWithDotSegments,
    // B. Verwendung → Deklaration (und Strg+Klick auf dem Ziel)
    UsageLocalVariable,
    UsageParameter,
    UsageInheritedField,
    UsagePropertyImplicit,
    UsagePropertyViaSelf,
    UsageConstant,
    UsageGetterOnPropertyLine,
    UsageSetterOnPropertyLine,
    UsageFieldOnPropertyLine,
    UsageEnumUnscoped,
    UsageEnumScopedTypePart,
    UsageEnumScopedValuePart,
    UsageTypeInClassHeading,
    UsageTypeOtherUnit,
    UsageMethodImplicitSelf,
    UsageMethodExplicitSelf,
    UsageSelf,
    UsageInheritedWithName,
    UsageInheritedBare,
    UsageInterfaceMethod,
    UsageInterfaceOverloadString,
    UsageOverloadInteger,
    UsageOverloadString,
    UsageClassHelper,
    UsageRecordHelper,
    UsageFreeRoutineOtherUnit,
    UsageFreeOverloadInteger,
    UsageFreeOverloadDouble,
    UsageQualifiedUnitPart,
    UsageQualifiedRoutinePart,
    UsageQualifiedConstantPart,
    UsageWithMember,
    UsageWithProperty,
    UsageSearchPathRoutine,
    UsageUsesSearchPathUnit,
    UsageUsesProjectUnit,
    UsageUsesRtlUnit,
    UsageUsesDottedFirstPart,
    UsageRtlRoutine,
    UsageIncludeDirectiveOpensFile,
    UsageIncludeDirectiveLongFormOpensFile,
    UsageIncludeRoutine,
    UsageIncludeMethod,
    UsageNestedRoutine,
    UsageResult,
    UsageLastLineRoutine,
    UsageClickLastCharacter,
    UsageClickBehindName,
    UsageAtLineStart,
    UsageAtLineEndLastCharacter,
    UsageAtLineEndBehind,
    // C. Datei, Puffer, Kodierung, Pfad
    FileSourceBufferShifted,
    FileTargetBufferShifted,
    FileTargetUtf8WithBom,
    FileTargetUtf8WithoutBom,
    FileTargetAnsi,
    FileTargetTabsBeforeName,
    FileTargetLfOnly,
    FilePathCaseDiffers,
    FilePathShortForm,
    FileDuringIndexBuild,
    // D. Kein Sprung: kein Ziel, keine Ausnahme, kein Hänger
    NegativeKeyword,
    NegativeComment,
    NegativeString,
    NegativeNumber,
    NegativeUnknownName,
    NegativeResourceDirective,
    NegativeOperator,
    NegativePastLineEnd);

{$SCOPEDENUMS OFF}

  TJumpFile = record
    /// <summary>Relativ zum Projektordner, z. B. 'Such\USuch.pas'.</summary>
    Name: string;
    /// <summary>Inhalt auf der Platte.</summary>
    Text: string;
    /// <summary>Ungespeicherter Editorpuffer; '' = wie Text.</summary>
    Buffer: string;
    Encoding: TJumpEncoding;
  end;

  TJumpRow = record
    Caption: string;
    Setup: TJumpSetup;
    FromFile, FromMarker, FromName: string;
    Click: TJumpClick;
    /// <summary>'' = kein Ziel erwartet; '*Name.pas' = nur der Dateiname zählt (RTL, Ort je Installation).</summary>
    ToFile: string;
    /// <summary>ToMarker = '' bei einem Unit-Ziel: Zeile 0, Zeichen 0.</summary>
    ToMarker, ToName: string;
    CheckCharacter: Boolean;
    Back: TJumpBack;
    BackFile, BackMarker, BackName: string;
    /// <summary>'', cTagToday, cTagSuspect oder cTagNew; steht in der Meldung hinter dem Namen.</summary>
    Tag: string;
    /// <summary>Ohne Ziel erwartet, und zwar mit der Meldung zum Indexaufbau (Index noch nicht fertig).</summary>
    ExpectIndexing: Boolean;
    function Named(const ACaption: string): TJumpRow;
    /// <summary>Nicht vom Nutzer entschieden: die Zeile hält das HEUTIGE Verhalten fest.</summary>
    function Today: TJumpRow;
    /// <summary>Verdacht aus Phase 1: fachlich richtige Erwartung, der Test darf rot sein.</summary>
    function Suspect: TJumpRow;
    /// <summary>Neue Erwartung des Nutzers (Umsetzung folgt), der Test darf rot sein.</summary>
    function NewExpectation: TJumpRow;
    function IndexingNotice: TJumpRow;
    function Clicked(AClick: TJumpClick): TJumpRow;
    function InSetup(ASetup: TJumpSetup): TJumpRow;
    function BothWays: TJumpRow;
    function Stays: TJumpRow;
    function BackTo(const AFile, AMarker, AName: string): TJumpRow;
    function LineOnly: TJumpRow;
  end;

  TJumpFixture = record
  public const
    cBasis = 'UBasis.pas';
    cNutzer = 'UNutzer.pas';
    cGenerisch = 'UGenerisch.pas';
    cLetzte = 'ULetzte.pas';
    cSuch = 'Such\USuch.pas';
    cTeile = 'Teile.inc';
    cMethoden = 'Methoden.inc';
    cLeer = 'Leer.inc';
    cDprName = 'SprungProbe.dpr';
    cDprojName = 'SprungProbe.dproj';
    cTagToday = 'Erwartung = heutiges Verhalten, nicht vom Nutzer entschieden';
    cTagSuspect = 'Verdacht, darf rot sein';
    cTagNew = 'neue Erwartung des Nutzers, darf rot sein';
    /// <summary>Zeile von Frei in UBasis; die Kodierungs- und Tab-Abwandlungen ersetzen genau diese Zeile.</summary>
    cFreiLine = 'procedure Frei(A: Integer); // Frei Dekl';
  public
    class function Files(ASetup: TJumpSetup): TArray<TJumpFile>; static;
    class function DprText(ASetup: TJumpSetup): string; static;
    class function DprojText(ASetup: TJumpSetup): string; static;
    class function RowOf(ACase: TJumpCase): TJumpRow; static;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo;

const
  cB = TJumpFixture.cBasis;
  cN = TJumpFixture.cNutzer;
  cG = TJumpFixture.cGenerisch;
  cL = TJumpFixture.cLetzte;
  cS = TJumpFixture.cSuch;
  cT = TJumpFixture.cTeile;
  cM = TJumpFixture.cMethoden;
  cE = TJumpFixture.cLeer;
  /// <summary>"{äöü} " vor dem Namen: Zeichen jenseits von ASCII vor der Zielspalte.</summary>
  cUmlautPrefix = '{'#$00E4#$00F6#$00FC'} ';

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

function Lines(const ALines: array of string): string;
begin
  Result := LinesWith(#13#10, ALines) + #13#10;
end;

function BasisLines: TArray<string>;
begin
  Result := [
    'unit UBasis;',
    '',
    'interface',
    '',
    'type',
    '  TFarbe = (fRot, fGruen); // Aufzaehlung TFarbe',
    '{$SCOPEDENUMS ON}',
    '  TModus = (Aus, Ein); // Aufzaehlung TModus',
    '{$SCOPEDENUMS OFF}',
    '',
    '  IMelder = interface',
    '    [''{5B0D8C1E-3F2A-4C7B-9E61-2A4F8D3C7B10}'']',
    '    procedure Laufe; // IMelder.Laufe',
    '    procedure Melde(A: Integer); overload; // IMelder.Melde Integer',
    '    procedure Melde(const S: string); overload; // IMelder.Melde string',
    '  end;',
    '',
    '  TBasis = class(TInterfacedObject, IMelder) // Klasse TBasis',
    '  private',
    '    function GetWert: Integer; // Getter Dekl',
    '    procedure SetWert(AValue: Integer); // Setter Dekl',
    '  protected',
    '    FWert: Integer; // Feld FWert',
    '    procedure Zeichne(A: Integer); overload; virtual; abstract; // abstrakt Integer',
    '    procedure Zeichne(const S: string); overload; virtual; abstract; // abstrakt string',
    '  public',
    '    constructor Create(AWert: Integer); // Konstruktor Dekl',
    '    procedure Laufe; virtual; // TBasis.Laufe Dekl',
    '    procedure Melde(A: Integer); overload; // TBasis.Melde Integer Dekl',
    '    procedure Melde(const S: string); overload; // TBasis.Melde string Dekl',
    '    property Wert: Integer read GetWert write SetWert; // Property Wert',
    '    property Roh: Integer read FWert; // Property Roh',
    '  end;',
    '',
    '  TBasisHelfer = class helper for TBasis',
    '    procedure Hilf; // Klassenhelfer Dekl',
    '  end;',
    '',
    '  TZahlHelfer = record helper for Integer',
    '    function Doppelt: Integer; // Recordhelfer Dekl',
    '  end;',
    '',
    'const',
    '  cGrenze = 10; // Konstante cGrenze',
    '',
    TJumpFixture.cFreiLine,
    'function Rechne(A: Integer): Integer; overload; // Rechne Integer Dekl',
    'function Rechne(A: Double): Double; overload; // Rechne Double Dekl',
    'function Ticks: Cardinal; stdcall; // Ticks Dekl',
    '',
    'implementation',
    '',
    'function TBasis.GetWert: Integer; // Getter Rumpf',
    'begin',
    '  Result := FWert; // Nutzung Result',
    'end;',
    '',
    'procedure TBasis.SetWert(AValue: Integer); // Setter Rumpf',
    'begin',
    '  FWert := AValue;',
    'end;',
    '',
    'constructor TBasis.Create(AWert: Integer); // Konstruktor Rumpf',
    'begin',
    '  inherited Create;',
    '  FWert := AWert;',
    'end;',
    '',
    'procedure TBasis.Laufe; // TBasis.Laufe Rumpf',
    'begin',
    'end;',
    '',
    'procedure TBasis.Melde(A: Integer); // TBasis.Melde Integer Rumpf',
    'begin',
    'end;',
    '',
    'procedure TBasis.Melde(const S: string); // TBasis.Melde string Rumpf',
    'begin',
    'end;',
    '',
    'procedure TBasisHelfer.Hilf; // Klassenhelfer Rumpf',
    'begin',
    'end;',
    '',
    'function TZahlHelfer.Doppelt: Integer; // Recordhelfer Rumpf',
    'begin',
    '  Result := Self * 2;',
    'end;',
    '',
    'procedure Frei(A: Integer); // Frei Rumpf',
    'begin',
    'end;',
    '',
    'function Rechne(A: Integer): Integer; // Rechne Integer Rumpf',
    'begin',
    '  Result := A;',
    'end;',
    '',
    'function Rechne(A: Double): Double; // Rechne Double Rumpf',
    'begin',
    '  Result := A;',
    'end;',
    '',
    'function Ticks; external ''kernel32.dll'' name ''GetTickCount''; // Ticks extern',
    '',
    'end.'];
end;

function NutzerLines: TArray<string>;
begin
  Result := [
    'unit UNutzer;',
    '',
    'interface',
    '',
    'uses',
    '  System.SysUtils, UBasis, USuch, UGenerisch, ULetzte; // uses-Liste',
    '',
    '{$I Teile.inc} // Direktive Include',
    '{$INCLUDE Leer.inc} // Direktive INCLUDE',
    '',
    'type',
    '  TAbgeleitet = class(TBasis) // Klasse TAbgeleitet',
    '  protected',
    '    procedure Zeichne(A: Integer); overload; override; // Abgeleitet Zeichne Integer Dekl',
    '    procedure Zeichne(const S: string); overload; override; // Abgeleitet Zeichne string Dekl',
    '  public',
    '    procedure Laufe; override; // Abgeleitet Laufe Dekl',
    '    procedure Arbeite(AParam: Integer); // Arbeite Dekl',
    '    {$I Methoden.inc}',
    '  end;',
    '',
    'implementation',
    '',
    '{$R *.dfm} // Direktive Ressource',
    '',
    'procedure AusInclude; // AusInclude Rumpf',
    'begin',
    'end;',
    '',
    'procedure TAbgeleitet.Zeichne(A: Integer); // Abgeleitet Zeichne Integer Rumpf',
    'begin',
    'end;',
    '',
    'procedure TAbgeleitet.Zeichne(const S: string); // Abgeleitet Zeichne string Rumpf',
    'begin',
    'end;',
    '',
    'procedure TAbgeleitet.Laufe; // Abgeleitet Laufe Rumpf',
    'begin',
    '  inherited; // inherited nackt',
    '  inherited Laufe; // inherited mit Name',
    'end;',
    '',
    'procedure TAbgeleitet.AusIncludeMethode; // AusIncludeMethode Rumpf',
    'begin',
    'end;',
    '',
    'procedure TAbgeleitet.Arbeite(AParam: Integer); // Arbeite Rumpf',
    'var',
    '  Lokal: Integer; // Lokal Dekl',
    '  Text: string;',
    '  Melder: IMelder;',
    '  Farbe: TFarbe;',
    '  Modus: TModus;',
    '  Paar: TPaar;',
    '',
    '  procedure Innen; // Innen Dekl',
    '  begin',
    '  end;',
    '',
    'begin',
    '  Lokal := AParam; // Nutzung Lokal und Parameter',
    '  Lokal := FWert; // Nutzung Feld',
    '  Wert := Lokal; // Nutzung Property implizit',
    '  Self.Wert := cGrenze; // Nutzung Property Self und Konstante',
    '  Farbe := fGruen; // Nutzung Aufzaehlung ungescoped',
    '  Modus := TModus.Ein; // Nutzung Aufzaehlung gescoped',
    '  Laufe; // Nutzung Methode implizit',
    '  Self.Laufe; // Nutzung Methode Self',
    '  Melder := Self; // Nutzung Self',
    '  Melder.Laufe; // Nutzung Interface-Methode',
    '  Melder.Melde(''x''); // Nutzung Interface-Ueberladung string',
    '  Melde(1); // Nutzung Ueberladung Integer',
    '  Melde(''x''); // Nutzung Ueberladung string',
    '  Hilf; // Nutzung Klassenhelfer',
    '  Lokal := Lokal.Doppelt; // Nutzung Recordhelfer',
    '  Frei(Rechne(1)); // Nutzung freie Routine und Ueberladung Integer',
    '  Rechne(1.5); // Nutzung Ueberladung Double',
    '  UBasis.Frei(UBasis.cGrenze); // Nutzung qualifiziert',
    '  AusDemSuchpfad; // Nutzung Suchpfad',
    '  AusInclude; // Nutzung Include-Routine',
    '  AusIncludeMethode; // Nutzung Include-Methode',
    '  Innen; // Nutzung lokale Routine',
    '  Letzte; // Nutzung letzte Zeile',
    '  Paar := TPaar.Create; // Nutzung Typ TPaar',
    '  Text := IntToStr(Lokal); // Nutzung RTL',
    '  with TBasis(Self) do // Schluesselwort with',
    '    Melde(Wert); // Nutzung with',
    'Lokal := Lokal + 1; // Zeilenanfang',
    '  Lokal := 2 + Lokal',
    '    + 0; // Fortsetzung nach Zeilenende',
    '  { Kommentar mit Lokal }',
    '  Text := ''Lokal im String''; // Negativ String',
    '  Lokal := 42; // Negativ Zahl',
    '  Unbekannt; // Negativ unbekannt',
    'end;',
    '',
    'end.'];
end;

function GenerischText: string;
begin
  // Implementierungen in umgekehrter Reihenfolge: Paaren über die Reihenfolge wäre hier falsch.
  Result := Lines([
    'unit UGenerisch;',
    '',
    'interface',
    '',
    'type',
    '  TPaar = class // Klasse TPaar',
    '    procedure Setze(A: Integer); // TPaar.Setze Dekl',
    '  end;',
    '',
    '  TPaar<T> = class // Klasse TPaar<T>',
    '    procedure Setze(A: Integer); // TPaar<T>.Setze Dekl',
    '  end;',
    '',
    'implementation',
    '',
    'procedure TPaar<T>.Setze(A: Integer); // TPaar<T>.Setze Rumpf',
    'begin',
    'end;',
    '',
    'procedure TPaar.Setze(A: Integer); // TPaar.Setze Rumpf',
    'begin',
    'end;',
    '',
    'end.']);
end;

function LetzteText: string;
begin
  // Ohne Umbruch am Ende; die Implementierung steht in der letzten Zeile.
  Result := LinesWith(#13#10, [
    'unit ULetzte;',
    'interface',
    'procedure Letzte; // Letzte Dekl',
    'implementation',
    'procedure Letzte; begin end; end.']);
end;

function SuchText: string;
begin
  Result := Lines([
    'unit USuch;',
    'interface',
    'procedure AusDemSuchpfad; // Suchpfad Dekl',
    'implementation',
    'procedure AusDemSuchpfad; // Suchpfad Rumpf',
    'begin',
    'end;',
    'end.']);
end;

function FileOf(const AName, AText: string; AEncoding: TJumpEncoding = TJumpEncoding.Utf8Bom): TJumpFile;
begin
  Result.Name := AName;
  Result.Text := AText;
  Result.Buffer := '';
  Result.Encoding := AEncoding;
end;

/// <summary>ALines mit ALine ersetzt durch AReplacement.</summary>
function Replaced(const ALines: TArray<string>; const ALine, AReplacement: string): TArray<string>;
var
  mIndex: Integer;
begin
  Result := Copy(ALines);
  for mIndex := 0 to High(Result) do
  begin
    if Result[mIndex] = ALine then
    begin
      Result[mIndex] := AReplacement;
    end;
  end;
end;

/// <summary>ALines mit drei Kommentarzeilen nach der ersten Zeile AAfter (ungespeicherte Änderung im Puffer).
/// </summary>
function Shifted(const ALines: TArray<string>; const AAfter: string): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + [ALines[mIndex]];
    if ALines[mIndex] = AAfter then
    begin
      Result := Result + ['// im Puffer eingefuegt 1', '// im Puffer eingefuegt 2', '// im Puffer eingefuegt 3'];
    end;
  end;
end;

class function TJumpFixture.Files(ASetup: TJumpSetup): TArray<TJumpFile>;
var
  mBasis: TJumpFile;
  mNutzer: TJumpFile;
begin
  mBasis := FileOf(cBasis, Lines(BasisLines));
  mNutzer := FileOf(cNutzer, Lines(NutzerLines));
  case ASetup of
    TJumpSetup.SourceBufferShifted:
      mNutzer.Buffer := Lines(Shifted(NutzerLines, 'implementation'));
    TJumpSetup.TargetBufferShifted:
      mBasis.Buffer := Lines(Shifted(BasisLines, 'interface'));
    TJumpSetup.TargetUtf8Bom:
      mBasis := FileOf(cBasis, Lines(Replaced(BasisLines, cFreiLine, cUmlautPrefix + cFreiLine)),
        TJumpEncoding.Utf8Bom);
    TJumpSetup.TargetUtf8NoBom:
      mBasis := FileOf(cBasis, Lines(Replaced(BasisLines, cFreiLine, cUmlautPrefix + cFreiLine)),
        TJumpEncoding.Utf8);
    TJumpSetup.TargetAnsi:
      mBasis := FileOf(cBasis, Lines(Replaced(BasisLines, cFreiLine, cUmlautPrefix + cFreiLine)),
        TJumpEncoding.Ansi);
    TJumpSetup.TargetTabs:
      mBasis := FileOf(cBasis, Lines(Replaced(BasisLines, cFreiLine,
        #9'procedure'#9'Frei(A: Integer); // Frei Dekl')));
    TJumpSetup.TargetLfOnly:
      mBasis := FileOf(cBasis, LinesWith(#10, BasisLines) + #10);
  end;
  Result := [mNutzer, mBasis, FileOf(cGenerisch, GenerischText), FileOf(cLetzte, LetzteText),
    FileOf(cSuch, SuchText), FileOf(cTeile, Lines(['procedure AusInclude; // AusInclude Dekl'])),
    FileOf(cMethoden, Lines(['procedure AusIncludeMethode; // AusIncludeMethode Dekl'])),
    FileOf(cLeer, Lines(['// Leer.inc: nur ein Kommentar']))];
end;

/// <summary>Pfad von UBasis in dpr und dproj; bei DprojDotSegments über "Unter\..\".</summary>
function BasisReference(ASetup: TJumpSetup): string;
begin
  if ASetup = TJumpSetup.DprojDotSegments then
  begin
    Result := 'Unter\..\UBasis.pas';
  end
  else
  begin
    Result := 'UBasis.pas';
  end;
end;

class function TJumpFixture.DprText(ASetup: TJumpSetup): string;
begin
  // USuch steht absichtlich nicht hier: Es ist nur über den Suchpfad zu finden.
  Result := Lines([
    'program SprungProbe;',
    'uses',
    '  UNutzer in ''UNutzer.pas'',',
    '  UBasis in ''' + BasisReference(ASetup) + ''',',
    '  UGenerisch in ''UGenerisch.pas'',',
    '  ULetzte in ''ULetzte.pas'';',
    'begin',
    'end.']);
end;

class function TJumpFixture.DprojText(ASetup: TJumpSetup): string;
begin
  // Wie dpcc.Core.Lsp.GotoBothWays.Tests, mit eigener GUID, Suchpfad "Such" und mehreren Units.
  Result := Lines([
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">',
    '    <PropertyGroup>',
    '        <ProjectGuid>{7A41C2D9-5E3B-4F80-9C16-0B2E8D4F6A75}</ProjectGuid>',
    '        <ProjectVersion>20.3</ProjectVersion>',
    '        <FrameworkType>None</FrameworkType>',
    '        <MainSource>SprungProbe.dpr</MainSource>',
    '        <Base>True</Base>',
    '        <Config Condition="''$(Config)''==''''">Debug</Config>',
    '        <Platform Condition="''$(Platform)''==''''">Win32</Platform>',
    '        <TargetedPlatforms>1</TargetedPlatforms>',
    '        <AppType>Console</AppType>',
    '    </PropertyGroup>',
    '    <PropertyGroup Condition="''$(Base)''!=''''">',
    '        <DCC_Namespace>System;Winapi;System.Win;$(DCC_Namespace)</DCC_Namespace>',
    '        <DCC_UnitSearchPath>Such;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>',
    '    </PropertyGroup>',
    '    <ItemGroup>',
    '        <DelphiCompile Include="$(MainSource)">',
    '            <MainSource>MainSource</MainSource>',
    '        </DelphiCompile>',
    '        <DCCReference Include="UNutzer.pas"/>',
    '        <DCCReference Include="' + BasisReference(ASetup) + '"/>',
    '        <DCCReference Include="UGenerisch.pas"/>',
    '        <DCCReference Include="ULetzte.pas"/>',
    '    </ItemGroup>',
    '    <ProjectExtensions>',
    '        <Borland.Personality>Delphi.Personality.12</Borland.Personality>',
    '        <Borland.ProjectType>Application</Borland.ProjectType>',
    '    </ProjectExtensions>',
    '</Project>']);
end;

{ TJumpRow }

function Jump(const AFromFile, AFromMarker, AFromName, AToFile, AToMarker, AToName: string): TJumpRow;
begin
  Result := Default(TJumpRow);
  Result.Setup := TJumpSetup.Standard;
  Result.FromFile := AFromFile;
  Result.FromMarker := AFromMarker;
  Result.FromName := AFromName;
  Result.Click := TJumpClick.First;
  Result.ToFile := AToFile;
  Result.ToMarker := AToMarker;
  Result.ToName := AToName;
  Result.CheckCharacter := True;
  Result.Back := TJumpBack.None;
end;

function NoJump(const AFromFile, AFromMarker, AFromName: string): TJumpRow;
begin
  Result := Jump(AFromFile, AFromMarker, AFromName, '', '', '');
end;

/// <summary>Sprung auf eine Unit: Anfang der Datei.</summary>
function UnitJump(const AFromFile, AFromMarker, AFromName, AToFile: string): TJumpRow;
begin
  Result := Jump(AFromFile, AFromMarker, AFromName, AToFile, '', '');
end;

function TJumpRow.Named(const ACaption: string): TJumpRow;
begin
  Result := Self;
  Result.Caption := ACaption;
end;

function TJumpRow.Today: TJumpRow;
begin
  Result := Self;
  Result.Tag := TJumpFixture.cTagToday;
end;

function TJumpRow.NewExpectation: TJumpRow;
begin
  Result := Self;
  Result.Tag := TJumpFixture.cTagNew;
end;

function TJumpRow.IndexingNotice: TJumpRow;
begin
  Result := Self;
  Result.ExpectIndexing := True;
end;

function TJumpRow.Suspect: TJumpRow;
begin
  Result := Self;
  Result.Tag := TJumpFixture.cTagSuspect;
end;

function TJumpRow.Clicked(AClick: TJumpClick): TJumpRow;
begin
  Result := Self;
  Result.Click := AClick;
end;

function TJumpRow.InSetup(ASetup: TJumpSetup): TJumpRow;
begin
  Result := Self;
  Result.Setup := ASetup;
end;

function TJumpRow.BothWays: TJumpRow;
begin
  Result := Self;
  Result.Back := TJumpBack.ToOrigin;
end;

function TJumpRow.Stays: TJumpRow;
begin
  Result := Self;
  Result.Back := TJumpBack.Stays;
end;

function TJumpRow.BackTo(const AFile, AMarker, AName: string): TJumpRow;
begin
  Result := Self;
  Result.Back := TJumpBack.ToOther;
  Result.BackFile := AFile;
  Result.BackMarker := AMarker;
  Result.BackName := AName;
end;

function TJumpRow.LineOnly: TJumpRow;
begin
  Result := Self;
  Result.CheckCharacter := False;
end;

{ Tabelle }

const
  // Häufige Ziele, damit die Zeilen kurz bleiben.
  cLokalDekl = '  Lokal: Integer; // Lokal Dekl';
  cFreiMarker = 'Frei(A: Integer); // Frei Dekl';
  cFreiRumpf = 'procedure Frei(A: Integer); // Frei Rumpf';
  cLaufeAbgDekl = 'procedure Laufe; override; // Abgeleitet Laufe Dekl';
  cLaufeAbgRumpf = 'procedure TAbgeleitet.Laufe; // Abgeleitet Laufe Rumpf';
  cMeldeIntDekl = 'procedure Melde(A: Integer); overload; // TBasis.Melde Integer Dekl';
  cMeldeIntRumpf = 'procedure TBasis.Melde(A: Integer); // TBasis.Melde Integer Rumpf';
  cMeldeStrDekl = 'procedure Melde(const S: string); overload; // TBasis.Melde string Dekl';
  cMeldeStrRumpf = 'procedure TBasis.Melde(const S: string); // TBasis.Melde string Rumpf';
  cWertProp = 'property Wert: Integer read GetWert';

class function TJumpFixture.RowOf(ACase: TJumpCase): TJumpRow;
begin
  case ACase of
    // A. Deklaration ↔ Implementierung
    TJumpCase.DeclImplOverrideInDescendant:
      Result := Jump(cN, cLaufeAbgDekl, 'Laufe', cN, cLaufeAbgRumpf, 'Laufe').BothWays;
    TJumpCase.DeclImplMethodOverloadInOtherUnit:
      Result := Jump(cB, cMeldeStrDekl, 'Melde', cB, cMeldeStrRumpf, 'Melde').BothWays;
    TJumpCase.DeclImplOverrideOfAbstractOverload:
      Result := Jump(cN, 'Zeichne(const S: string); overload; override;', 'Zeichne', cN,
        'TAbgeleitet.Zeichne(const S: string); // Abgeleitet Zeichne string Rumpf', 'Zeichne').BothWays;
    TJumpCase.DeclImplClassHelper:
      Result := Jump(cB, 'procedure Hilf; // Klassenhelfer Dekl', 'Hilf', cB,
        'procedure TBasisHelfer.Hilf; // Klassenhelfer Rumpf', 'Hilf').BothWays;
    TJumpCase.DeclImplRecordHelper:
      Result := Jump(cB, 'function Doppelt: Integer; // Recordhelfer Dekl', 'Doppelt', cB,
        'function TZahlHelfer.Doppelt: Integer; // Recordhelfer Rumpf', 'Doppelt').BothWays;
    TJumpCase.DeclImplPropertyGetter:
      Result := Jump(cB, 'function GetWert: Integer; // Getter Dekl', 'GetWert', cB,
        'function TBasis.GetWert: Integer; // Getter Rumpf', 'GetWert').BothWays;
    TJumpCase.DeclImplFreeOverloadSameParamNameInteger:
      Result := Jump(cB, 'function Rechne(A: Integer): Integer; overload;', 'Rechne', cB,
        'function Rechne(A: Integer): Integer; // Rechne Integer Rumpf', 'Rechne').BothWays;
    TJumpCase.DeclImplFreeOverloadSameParamNameDouble:
      Result := Jump(cB, 'function Rechne(A: Double): Double; overload;', 'Rechne', cB,
        'function Rechne(A: Double): Double; // Rechne Double Rumpf', 'Rechne').BothWays;
    TJumpCase.DeclImplExternalInImplementation:
      // Muster aus Winapi.Windows: Deklaration im interface, "external" im implementation-Teil.
      Result := Jump(cB, 'function Ticks: Cardinal; stdcall;', 'Ticks', cB, 'function Ticks; external', 'Ticks')
        .BothWays;
    TJumpCase.DeclImplAbstractOverloadFirstStays:
      // Nutzer: stehen bleiben. Verdacht: Regel "sole" (zwei gleichnamige Fundstellen) paart die beiden abstrakten
      // Deklarationen, der Sprung geht zur anderen Überladung.
      Result := Jump(cB, 'Zeichne(A: Integer); overload; virtual; abstract;', 'Zeichne', cB,
        'Zeichne(A: Integer); overload; virtual; abstract;', 'Zeichne').Stays.Suspect;
    TJumpCase.DeclImplAbstractOverloadSecondStays:
      Result := Jump(cB, 'Zeichne(const S: string); overload; virtual; abstract;', 'Zeichne', cB,
        'Zeichne(const S: string); overload; virtual; abstract;', 'Zeichne').Stays.Suspect;
    TJumpCase.DeclImplInterfaceOverloadFirstStays:
      Result := Jump(cB, 'Melde(A: Integer); overload; // IMelder.Melde Integer', 'Melde', cB,
        'Melde(A: Integer); overload; // IMelder.Melde Integer', 'Melde').Stays.Suspect;
    TJumpCase.DeclImplInterfaceOverloadSecondStays:
      Result := Jump(cB, 'Melde(const S: string); overload; // IMelder.Melde string', 'Melde', cB,
        'Melde(const S: string); overload; // IMelder.Melde string', 'Melde').Stays.Suspect;
    TJumpCase.DeclImplInterfaceMethodStays:
      // Nutzer: Deklaration ohne Rumpf → stehen bleiben (nicht zur implementierenden Klasse).
      Result := Jump(cB, 'procedure Laufe; // IMelder.Laufe', 'Laufe', cB, 'procedure Laufe; // IMelder.Laufe',
        'Laufe').Stays;
    TJumpCase.DeclImplPlainAndGenericSameNamePlain:
      Result := Jump(cG, 'procedure Setze(A: Integer); // TPaar.Setze Dekl', 'Setze', cG,
        'procedure TPaar.Setze(A: Integer); // TPaar.Setze Rumpf', 'Setze').BothWays.Suspect;
    TJumpCase.DeclImplPlainAndGenericSameNameGeneric:
      Result := Jump(cG, 'procedure Setze(A: Integer); // TPaar<T>.Setze Dekl', 'Setze', cG,
        'procedure TPaar<T>.Setze(A: Integer); // TPaar<T>.Setze Rumpf', 'Setze').BothWays.Suspect;
    TJumpCase.DeclImplLastLineOfFile:
      Result := Jump(cL, 'procedure Letzte; // Letzte Dekl', 'Letzte', cL, 'procedure Letzte; begin end; end.',
        'Letzte').BothWays;
    TJumpCase.DeclImplMethodFromIncludeInClassBody:
      // Vom Rumpf zur Deklaration in Methoden.inc; zurück aus der Include-Datei siehe DeclImplBackFromIncludeFile.
      Result := Jump(cN, 'procedure TAbgeleitet.AusIncludeMethode;', 'AusIncludeMethode', cM,
        'procedure AusIncludeMethode; // AusIncludeMethode Dekl', 'AusIncludeMethode').Suspect;
    TJumpCase.DeclImplFreeRoutineFromInclude:
      Result := Jump(cN, 'procedure AusInclude; // AusInclude Rumpf', 'AusInclude', cT,
        'procedure AusInclude; // AusInclude Dekl', 'AusInclude');
    TJumpCase.DeclImplBackFromIncludeFile:
      // Strg+Klick in der geöffneten Include-Datei (eigener Puffer): zum Rumpf in der Unit.
      Result := Jump(cT, 'procedure AusInclude; // AusInclude Dekl', 'AusInclude', cN,
        'procedure AusInclude; // AusInclude Rumpf', 'AusInclude').Suspect;
    TJumpCase.DeclImplDprojWithDotSegments:
      // Verdacht: der Server vergleicht Pfade mit SameText (Definition.pas), der Index kennt "Unter\..\UBasis.pas".
      Result := Jump(cB, cFreiMarker, 'Frei', cB, cFreiRumpf, 'Frei').BothWays
        .InSetup(TJumpSetup.DprojDotSegments).Suspect;

    // B. Verwendung → Deklaration. Verwendung einer Methode → ihre Deklaration (nicht die Implementierung):
    // Erwartung = heutiges Verhalten, nicht vom Nutzer entschieden.
    TJumpCase.UsageLocalVariable:
      Result := Jump(cN, 'Lokal := AParam;', 'Lokal', cN, cLokalDekl, 'Lokal').Stays;
    TJumpCase.UsageParameter:
      Result := Jump(cN, 'Lokal := AParam;', 'AParam', cN, 'TAbgeleitet.Arbeite(AParam: Integer); // Arbeite Rumpf',
        'AParam').Stays;
    TJumpCase.UsageInheritedField:
      Result := Jump(cN, 'Lokal := FWert; // Nutzung Feld', 'FWert', cB, 'FWert: Integer; // Feld FWert', 'FWert')
        .Stays;
    TJumpCase.UsagePropertyImplicit:
      Result := Jump(cN, 'Wert := Lokal; // Nutzung Property implizit', 'Wert', cB, cWertProp, 'Wert').Stays;
    TJumpCase.UsagePropertyViaSelf:
      Result := Jump(cN, 'Self.Wert := cGrenze;', 'Wert', cB, cWertProp, 'Wert').Stays;
    TJumpCase.UsageConstant:
      Result := Jump(cN, 'Self.Wert := cGrenze;', 'cGrenze', cB, 'cGrenze = 10;', 'cGrenze').Stays;
    TJumpCase.UsageGetterOnPropertyLine:
      Result := Jump(cB, 'read GetWert write SetWert', 'GetWert', cB, 'function GetWert: Integer; // Getter Dekl',
        'GetWert').BackTo(cB, 'function TBasis.GetWert: Integer; // Getter Rumpf', 'GetWert');
    TJumpCase.UsageSetterOnPropertyLine:
      Result := Jump(cB, 'read GetWert write SetWert', 'SetWert', cB,
        'procedure SetWert(AValue: Integer); // Setter Dekl', 'SetWert')
        .BackTo(cB, 'procedure TBasis.SetWert(AValue: Integer); // Setter Rumpf', 'SetWert');
    TJumpCase.UsageFieldOnPropertyLine:
      Result := Jump(cB, 'read FWert; // Property Roh', 'FWert', cB, 'FWert: Integer; // Feld FWert', 'FWert').Stays;
    TJumpCase.UsageEnumUnscoped:
      Result := Jump(cN, 'Farbe := fGruen;', 'fGruen', cB, 'TFarbe = (fRot, fGruen);', 'fGruen').Stays;
    TJumpCase.UsageEnumScopedTypePart:
      Result := Jump(cN, 'Modus := TModus.Ein;', 'TModus', cB, 'TModus = (Aus, Ein);', 'TModus').Stays;
    TJumpCase.UsageEnumScopedValuePart:
      Result := Jump(cN, 'Modus := TModus.Ein;', 'Ein', cB, 'TModus = (Aus, Ein);', 'Ein').Stays;
    TJumpCase.UsageTypeInClassHeading:
      Result := Jump(cN, 'TAbgeleitet = class(TBasis)', 'TBasis', cB, 'TBasis = class(TInterfacedObject', 'TBasis')
        .Stays;
    TJumpCase.UsageTypeOtherUnit:
      // Verdacht: TPaar und TPaar<T> teilen sich im Index den Container "TPaar".
      Result := Jump(cN, 'Paar := TPaar.Create;', 'TPaar', cG, '  TPaar = class // Klasse TPaar', 'TPaar').Stays
        .Suspect;
    TJumpCase.UsageMethodImplicitSelf:
      Result := Jump(cN, '  Laufe; // Nutzung Methode implizit', 'Laufe', cN, cLaufeAbgDekl, 'Laufe')
        .BackTo(cN, cLaufeAbgRumpf, 'Laufe');
    TJumpCase.UsageMethodExplicitSelf:
      Result := Jump(cN, 'Self.Laufe; // Nutzung Methode Self', 'Laufe', cN, cLaufeAbgDekl, 'Laufe')
        .BackTo(cN, cLaufeAbgRumpf, 'Laufe');
    TJumpCase.UsageSelf:
      Result := Jump(cN, 'Melder := Self;', 'Self', cN, 'TAbgeleitet = class(TBasis)', 'TAbgeleitet').Stays;
    TJumpCase.UsageInheritedWithName:
      Result := Jump(cN, 'inherited Laufe; // inherited mit Name', 'Laufe', cB,
        'procedure Laufe; virtual; // TBasis.Laufe Dekl', 'Laufe')
        .BackTo(cB, 'procedure TBasis.Laufe; // TBasis.Laufe Rumpf', 'Laufe');
    TJumpCase.UsageInheritedBare:
      // Nutzer: wie "inherited Laufe" zur Deklaration im Vorfahren. Heute kein Ziel (Schlüsselwort, IdentifierAt).
      Result := Jump(cN, 'inherited; // inherited nackt', 'inherited', cB,
        'procedure Laufe; virtual; // TBasis.Laufe Dekl', 'Laufe')
        .BackTo(cB, 'procedure TBasis.Laufe; // TBasis.Laufe Rumpf', 'Laufe').NewExpectation;
    TJumpCase.UsageInterfaceMethod:
      Result := Jump(cN, 'Melder.Laufe; // Nutzung Interface-Methode', 'Laufe', cB,
        'procedure Laufe; // IMelder.Laufe', 'Laufe').Stays;
    TJumpCase.UsageInterfaceOverloadString:
      // Verdacht: Regel "sole" führt von der string-Variante zur ersten Deklaration (Integer).
      Result := Jump(cN, 'Melder.Melde(''x'');', 'Melde', cB,
        'procedure Melde(const S: string); overload; // IMelder.Melde string', 'Melde').Stays.Suspect;
    TJumpCase.UsageOverloadInteger:
      Result := Jump(cN, '  Melde(1); // Nutzung Ueberladung Integer', 'Melde', cB, cMeldeIntDekl, 'Melde')
        .BackTo(cB, cMeldeIntRumpf, 'Melde');
    TJumpCase.UsageOverloadString:
      Result := Jump(cN, '  Melde(''x''); // Nutzung Ueberladung string', 'Melde', cB, cMeldeStrDekl, 'Melde')
        .BackTo(cB, cMeldeStrRumpf, 'Melde');
    TJumpCase.UsageClassHelper:
      Result := Jump(cN, 'Hilf; // Nutzung Klassenhelfer', 'Hilf', cB, 'procedure Hilf; // Klassenhelfer Dekl',
        'Hilf').BackTo(cB, 'procedure TBasisHelfer.Hilf; // Klassenhelfer Rumpf', 'Hilf');
    TJumpCase.UsageRecordHelper:
      Result := Jump(cN, 'Lokal := Lokal.Doppelt;', 'Doppelt', cB, 'function Doppelt: Integer; // Recordhelfer Dekl',
        'Doppelt').BackTo(cB, 'function TZahlHelfer.Doppelt: Integer; // Recordhelfer Rumpf', 'Doppelt');
    TJumpCase.UsageFreeRoutineOtherUnit:
      Result := Jump(cN, 'Frei(Rechne(1));', 'Frei', cB, cFreiMarker, 'Frei').BackTo(cB, cFreiRumpf, 'Frei');
    TJumpCase.UsageFreeOverloadInteger:
      Result := Jump(cN, 'Frei(Rechne(1));', 'Rechne', cB, 'function Rechne(A: Integer): Integer; overload;', 'Rechne')
        .BackTo(cB, 'function Rechne(A: Integer): Integer; // Rechne Integer Rumpf', 'Rechne');
    TJumpCase.UsageFreeOverloadDouble:
      Result := Jump(cN, 'Rechne(1.5);', 'Rechne', cB, 'function Rechne(A: Double): Double; overload;', 'Rechne')
        .BackTo(cB, 'function Rechne(A: Double): Double; // Rechne Double Rumpf', 'Rechne');
    TJumpCase.UsageQualifiedUnitPart:
      Result := UnitJump(cN, 'UBasis.Frei(UBasis.cGrenze);', 'UBasis', cB);
    TJumpCase.UsageQualifiedRoutinePart:
      Result := Jump(cN, 'UBasis.Frei(UBasis.cGrenze);', 'Frei', cB, cFreiMarker, 'Frei')
        .BackTo(cB, cFreiRumpf, 'Frei');
    TJumpCase.UsageQualifiedConstantPart:
      Result := Jump(cN, 'UBasis.cGrenze); // Nutzung qualifiziert', 'cGrenze', cB, 'cGrenze = 10;', 'cGrenze').Stays;
    TJumpCase.UsageWithMember:
      Result := Jump(cN, 'Melde(Wert); // Nutzung with', 'Melde', cB, cMeldeIntDekl, 'Melde')
        .BackTo(cB, cMeldeIntRumpf, 'Melde');
    TJumpCase.UsageWithProperty:
      Result := Jump(cN, 'Melde(Wert); // Nutzung with', 'Wert', cB, cWertProp, 'Wert').Stays;
    TJumpCase.UsageSearchPathRoutine:
      Result := Jump(cN, 'AusDemSuchpfad; // Nutzung Suchpfad', 'AusDemSuchpfad', cS,
        'procedure AusDemSuchpfad; // Suchpfad Dekl', 'AusDemSuchpfad')
        .BackTo(cS, 'procedure AusDemSuchpfad; // Suchpfad Rumpf', 'AusDemSuchpfad');
    TJumpCase.UsageUsesSearchPathUnit:
      Result := UnitJump(cN, 'UBasis, USuch, UGenerisch', 'USuch', cS);
    TJumpCase.UsageUsesProjectUnit:
      Result := UnitJump(cN, 'UBasis, USuch, UGenerisch', 'UBasis', cB);
    TJumpCase.UsageUsesRtlUnit:
      // Braucht die RTL-Quellen der installierten Delphi-Version im Index (Ort je Installation).
      Result := UnitJump(cN, 'System.SysUtils, UBasis', 'SysUtils', '*System.SysUtils.pas');
    TJumpCase.UsageUsesDottedFirstPart:
      // Heute: der ganze Name (System.SysUtils), nicht die Unit System.
      Result := UnitJump(cN, 'System.SysUtils, UBasis', 'System', '*System.SysUtils.pas').Today;
    TJumpCase.UsageRtlRoutine:
      Result := UnitJump(cN, 'Text := IntToStr(Lokal);', 'IntToStr', '*System.SysUtils.pas');
    TJumpCase.UsageIncludeDirectiveOpensFile:
      // Nutzer: wie ein Unit-Name in uses die eingebundene Datei öffnen, Zeile 1. Heute kein Ziel (Direktive).
      Result := UnitJump(cN, '{$I Teile.inc} // Direktive Include', 'Teile', cT).NewExpectation;
    TJumpCase.UsageIncludeDirectiveLongFormOpensFile:
      Result := UnitJump(cN, '{$INCLUDE Leer.inc} // Direktive INCLUDE', 'Leer', cE).NewExpectation;
    TJumpCase.UsageIncludeRoutine:
      Result := Jump(cN, 'AusInclude; // Nutzung Include-Routine', 'AusInclude', cT,
        'procedure AusInclude; // AusInclude Dekl', 'AusInclude')
        .BackTo(cN, 'procedure AusInclude; // AusInclude Rumpf', 'AusInclude');
    TJumpCase.UsageIncludeMethod:
      Result := Jump(cN, 'AusIncludeMethode; // Nutzung Include-Methode', 'AusIncludeMethode', cM,
        'procedure AusIncludeMethode; // AusIncludeMethode Dekl', 'AusIncludeMethode')
        .BackTo(cN, 'procedure TAbgeleitet.AusIncludeMethode;', 'AusIncludeMethode');
    TJumpCase.UsageNestedRoutine:
      Result := Jump(cN, 'Innen; // Nutzung lokale Routine', 'Innen', cN, 'procedure Innen; // Innen Dekl', 'Innen')
        .Stays;
    TJumpCase.UsageResult:
      // Heute: Zeile des Kopfs der Routine (das Ziel beginnt am Anfang des Kopfs, nicht am Namen;
      // NameResolver.Locals SelectionRange = Range), deshalb nur die Zeile.
      Result := Jump(cB, 'Result := FWert; // Nutzung Result', 'Result', cB,
        'function TBasis.GetWert: Integer; // Getter Rumpf', 'GetWert').LineOnly.Today;
    TJumpCase.UsageLastLineRoutine:
      Result := Jump(cN, 'Letzte; // Nutzung letzte Zeile', 'Letzte', cL, 'procedure Letzte; // Letzte Dekl', 'Letzte')
        .BackTo(cL, 'procedure Letzte; begin end; end.', 'Letzte');
    TJumpCase.UsageClickLastCharacter:
      Result := Jump(cN, 'Lokal := AParam;', 'Lokal', cN, cLokalDekl, 'Lokal').Clicked(TJumpClick.Last);
    TJumpCase.UsageClickBehindName:
      Result := Jump(cN, 'Lokal := AParam;', 'Lokal', cN, cLokalDekl, 'Lokal').Clicked(TJumpClick.Behind);
    TJumpCase.UsageAtLineStart:
      Result := Jump(cN, 'Lokal := Lokal + 1; // Zeilenanfang', 'Lokal', cN, cLokalDekl, 'Lokal');
    TJumpCase.UsageAtLineEndLastCharacter:
      // Marker ab "2 + ": Name ist das zweite Lokal der Zeile, sein letztes Zeichen ist das letzte der Zeile.
      Result := Jump(cN, '2 + Lokal', 'Lokal', cN, cLokalDekl, 'Lokal').Clicked(TJumpClick.Last);
    TJumpCase.UsageAtLineEndBehind:
      // Marker ab "2 + ": Name ist das zweite Lokal der Zeile, direkt am Zeilenende.
      Result := Jump(cN, '2 + Lokal', 'Lokal', cN, cLokalDekl, 'Lokal').Clicked(TJumpClick.Behind);

    // C. Datei, Puffer, Kodierung, Pfad
    TJumpCase.FileSourceBufferShifted:
      Result := Jump(cN, 'Lokal := AParam;', 'Lokal', cN, cLokalDekl, 'Lokal').Stays
        .InSetup(TJumpSetup.SourceBufferShifted);
    TJumpCase.FileTargetBufferShifted:
      Result := Jump(cN, 'Frei(Rechne(1));', 'Frei', cB, cFreiMarker, 'Frei').BackTo(cB, cFreiRumpf, 'Frei')
        .InSetup(TJumpSetup.TargetBufferShifted).Suspect;
    TJumpCase.FileTargetUtf8WithBom:
      Result := Jump(cN, 'Frei(Rechne(1));', 'Frei', cB, cFreiMarker, 'Frei').BackTo(cB, cFreiRumpf, 'Frei')
        .InSetup(TJumpSetup.TargetUtf8Bom);
    TJumpCase.FileTargetUtf8WithoutBom:
      Result := Jump(cN, 'Frei(Rechne(1));', 'Frei', cB, cFreiMarker, 'Frei').BackTo(cB, cFreiRumpf, 'Frei')
        .InSetup(TJumpSetup.TargetUtf8NoBom);
    TJumpCase.FileTargetAnsi:
      Result := Jump(cN, 'Frei(Rechne(1));', 'Frei', cB, cFreiMarker, 'Frei').BackTo(cB, cFreiRumpf, 'Frei')
        .InSetup(TJumpSetup.TargetAnsi);
    TJumpCase.FileTargetTabsBeforeName:
      Result := Jump(cN, 'Frei(Rechne(1));', 'Frei', cB, cFreiMarker, 'Frei').BackTo(cB, cFreiRumpf, 'Frei')
        .InSetup(TJumpSetup.TargetTabs);
    TJumpCase.FileTargetLfOnly:
      Result := Jump(cN, 'Frei(Rechne(1));', 'Frei', cB, cFreiMarker, 'Frei').BackTo(cB, cFreiRumpf, 'Frei')
        .InSetup(TJumpSetup.TargetLfOnly);
    TJumpCase.FilePathCaseDiffers:
      Result := Jump(cN, 'Frei(Rechne(1));', 'Frei', cB, cFreiMarker, 'Frei').BackTo(cB, cFreiRumpf, 'Frei')
        .InSetup(TJumpSetup.PathCaseDiffers);
    TJumpCase.FilePathShortForm:
      Result := Jump(cN, 'Frei(Rechne(1));', 'Frei', cB, cFreiMarker, 'Frei').BackTo(cB, cFreiRumpf, 'Frei')
        .InSetup(TJumpSetup.PathShortForm).Suspect;
    TJumpCase.FileDuringIndexBuild:
      // Fall aus dpcc.log 25.11.2026 19:16 (Delphi 12): Strg+Klick direkt nach dem Start, Index im Aufbau →
      // unitNotFound. Nutzer: nicht warten und nicht nachreichen, sondern sofort ohne Sprung melden „Index wird
      // aufgebaut, bitte erneut klicken“ statt „kein Ziel“. War der Index beim Klick schon fertig, ist der Fall nicht
      // nachgestellt (Assert.Pass im Test).
      Result := NoJump(cN, 'Frei(Rechne(1));', 'Frei').IndexingNotice.InSetup(TJumpSetup.NoIndexWait).NewExpectation;

    // D. Kein Sprung
    TJumpCase.NegativeKeyword:
      Result := NoJump(cN, 'with TBasis(Self) do', 'with');
    TJumpCase.NegativeComment:
      Result := NoJump(cN, '{ Kommentar mit Lokal }', 'Lokal');
    TJumpCase.NegativeString:
      Result := NoJump(cN, '''Lokal im String''', 'Lokal');
    TJumpCase.NegativeNumber:
      Result := NoJump(cN, 'Lokal := 42;', '42');
    TJumpCase.NegativeUnknownName:
      Result := NoJump(cN, 'Unbekannt; // Negativ unbekannt', 'Unbekannt');
    TJumpCase.NegativeResourceDirective:
      // Nutzer: {$R *.dfm} bleibt ohne Sprung.
      Result := NoJump(cN, '{$R *.dfm} // Direktive Ressource', 'dfm');
    TJumpCase.NegativeOperator:
      Result := NoJump(cN, 'Lokal := 42;', ':=');
    TJumpCase.NegativePastLineEnd:
      Result := NoJump(cN, 'Unbekannt; // Negativ unbekannt', 'Unbekannt').Clicked(TJumpClick.PastLineEnd);
  else
    raise EArgumentOutOfRangeException.Create('Sprungmatrix: Zeile fehlt');
  end;
  if Result.Caption = '' then
  begin
    Result.Caption := GetEnumName(TypeInfo(TJumpCase), Ord(ACase));
  end;
  if Result.Tag <> '' then
  begin
    Result.Caption := Result.Caption + ' [' + Result.Tag + ']';
  end;
end;

end.
