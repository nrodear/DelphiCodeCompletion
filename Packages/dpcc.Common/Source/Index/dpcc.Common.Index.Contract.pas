unit dpcc.Common.Index.Contract;

// Contract des Platform-Features Index: Verzeichnis aller Deklarationen im
// Projekt und in den referenzierten Bibliotheksquellen.
//
// - Je Unit ein TUnitIndex mit Symbolen, uses-Listen, Zeitstempel und Hash.
// - ISymbolIndex ist threadsicher; der Aufbau läuft im Hintergrund, Abfragen
//   (Namensauflösung, Symbolsuche, MCP) lesen jederzeit.
// - Dateizugriffe laufen über IIndexFileSystem, damit Tests ohne Platte
//   auskommen.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  dpcc.Common.Documents.Contract;

type
  TIndexSymbolKind = (
    ClassType, ObjectType, RecordType, InterfaceType, HelperType, EnumType, TypeAlias,
    EnumMember, Constant, Variable, Field, Property_, Method, Constructor_, Routine);

  /// <summary>Sichtbarkeit eines Mitglieds (#263); Public auch für Symbole auf Unit-Ebene.</summary>
  TIndexVisibility = (Public, Published, Protected, StrictProtected, Private, StrictPrivate);

  /// <summary>Speicher (Speicher-Optimierung Phase 2, c3): Die Ein-Byte-Felder (Kind, InInterface, Visibility,
  /// IsDefault, IsVirtual, Unavailable, ScopedEnum) stehen beisammen, MinArgs und MaxArgs sind SmallInt; vorher
  /// füllte der Record hinter jedem Byte auf vier Byte auf (136 statt 116 Byte je Symbol, bei rund 600.000
  /// Bibliothekssymbolen etwa 12 MB).</summary>
  TIndexSymbol = record
    Name: string;
    /// <summary>Umgebender Typ, z. B. TFoo bei TFoo.Bar; '' auf Unit-Ebene.</summary>
    Container: string;
    Kind: TIndexSymbolKind;
    /// <summary>Im interface-Abschnitt (von anderen Units sichtbar).</summary>
    InInterface: Boolean;
    Visibility: TIndexVisibility;
    /// <summary>Default-Property (Liste[i]).</summary>
    IsDefault: Boolean;
    /// <summary>Deklaration einer Methode mit virtual, dynamic, abstract oder override (#125).</summary>
    IsVirtual: Boolean;
    /// <summary>Steht in einem Zweig, der unter der aktiven Konfiguration nicht gilt (#476).</summary>
    Unavailable: Boolean;
    /// <summary>Aufzählungstyp und seine Werte unter {$SCOPEDENUMS ON} (#849): Werte gelten nur mit
    /// Typpräfix (TState.Error), nicht unqualifiziert.</summary>
    ScopedEnum: Boolean;
    /// <summary>Gesamte Deklaration.</summary>
    Range: TTextRange;
    /// <summary>Nur der Name.</summary>
    SelectionRange: TTextRange;
    /// <summary>Vorfahr und Interfaces bei Klassen und Interfaces, Zieltyp bei Helfern.</summary>
    Ancestors: TArray<string>;
    /// <summary>Deklarierter Typ bei Variablen, Feldern, Properties, Konstanten und Funktionen (Ergebnis); sonst
    /// ''.</summary>
    TypeName: string;
    /// <summary>Typargumente zu TypeName, z. B. 'TKunde' bei TList&lt;TKunde&gt; (#263); sonst ''.</summary>
    TypeArgs: string;
    /// <summary>Typargumente je Vorfahr in der Reihenfolge von Ancestors, '' bei Vorfahren ohne
    /// (class(TInterfacedObject, IComparer&lt;TKunde&gt;) → ['', 'TKunde']); nil, wenn keiner welche hat.</summary>
    AncestorArgs: TArray<string>;
    /// <summary>Typparameter generischer Typen und Methoden, kommagetrennt (TDictionary&lt;TKey,TValue&gt;).</summary>
    TypeParams: string;
    /// <summary>Routinen und indizierte Properties: Parameterzahl ohne bzw. mit Standardwerten. SmallInt reicht
    /// (Speicher-Optimierung Phase 2, c3: 4 Byte je Symbol).</summary>
    MinArgs: SmallInt;
    MaxArgs: SmallInt;
    /// <summary>Typen der Parameter in Reihenfolge ('' bei untypisierten).</summary>
    ParamTypes: TArray<string>;
    /// <summary>Datei der Deklaration, wenn sie aus einer $I-Datei kommt (#500); '' = Datei der Unit.</summary>
    FileName: string;
    /// <summary>Bedingung, unter der die Deklaration steht ("WIN64", "not MSWINDOWS"), "platform" bei der
    /// gleichnamigen Direktive; '' = immer (#476).</summary>
    Condition: string;
    /// <summary>Feld im varianten Teil eines Records (#846): Marken seines Zweigs ("0", "mkA, mkB"),
    /// verschachtelt mit " › " verbunden ("1 › 0"); '' = kein varianter Zweig.</summary>
    VariantBranch: string;
    /// <summary>Kopf der Deklaration (Signature) als UTF-8 (Speicher-Optimierung Phase 2, c2): fast nur
    /// ASCII, halb so groß wie UTF-16; Signaturen sind mit rund 60 MB der größte Textanteil der Bibliothek. Lesen
    /// und schreiben über Signature; direkt nur zum Teilen gleicher Texte (Cache) und für die Speicherschätzung.
    /// </summary>
    SignatureUtf8: UTF8String;
    /// <summary>Direktiven in Kleinschreibung und Reihenfolge der Deklaration: virtual, override,
    /// overload, static, inline, deprecated, platform … (#492). Dazu Merkmale ohne eigenes Feld (Index-Inhalte L1,
    /// Format 35), gelesen über die Funktionen unten:
    /// - "target:Form=Typ": Form und Zieltyp eines Typs ohne TypeName (Zeiger "^", "set of", "array of",
    ///   "array[0..9] of", "class of", "file of", "function", "procedure", "range" mit den Grenzen als Typ, "enum",
    ///   "record"), auch bei Feldern und Variablen mit anonymem Typ (TargetForm, TargetType);
    /// - "@Name": Attribut vor der Deklaration ([Weak] → "@Weak", Attributes);
    /// - "external", "external:Bibliothek", "name:Name", "index:Nummer", "delayed": DLL-Angaben, in Bibliotheks-Units
    ///   auch am interface-Symbol, dessen Rumpf im implementation-Teil nicht gespeichert ist; "impl:Zeile" ist die
    ///   Zeile (0-basiert) dieses Rumpfs (ImplementationLine);
    /// - "resourcestring", "threadvar", "operator", "destructor", "message:ID": Arten ohne eigene Symbolart;
    /// - "&lt;T:Einschränkungen&gt;": Einschränkungen eines Typparameters ("&lt;T:class,constructor&gt;",
    ///   ConstraintsOf).</summary>
    Directives: TArray<string>;
    /// <summary>Grund hinter deprecated 'Grund' (#38); '' ohne Grund oder ohne deprecated.</summary>
    DeprecatedText: string;
    /// <summary>Nur bei inline-Routinen (#1017): was der Rumpf aus anderen Units braucht, aufgelöst im Bereich
    /// der deklarierenden Unit. "Name" = Bezeichner, der nicht in dieser Unit deklariert ist; ":Typ" = Typ eines
    /// Felds oder einer Variablen, dessen Mitglieder der Rumpf benutzt (FListe.Count), bzw. ein Typverweis;
    /// "!Name" = Zugriff auf ein strict private-Mitglied der eigenen Klasse. Eine einbettbare inline-Routine ohne
    /// solche Verweise trägt genau den Eintrag InlineWithoutRefs (#1381: sonst sah die Regel inline-not-expanded
    /// sie nicht, H2445, H2456 und H2457 hängen nicht am Rumpf). nil = keine inline-Routine oder nicht einbettbar
    /// (asm, with, verschachtelte Routinen, virtual).</summary>
    InlineRefs: TArray<string>;
    /// <summary>Nur bei Klassen und Records: Methodenzuordnungen im Rumpf als "IFoo.Bar=Baz" in Reihenfolge der
    /// Deklaration. Sie sind keine eigenen Mitglieder (#849), zählen aber als Implementierung der
    /// Interface-Methode (interface-not-implemented, hresult-integer-mix).</summary>
    Resolutions: TArray<string>;
    /// <summary>Begründungen (#1123) über der Deklaration und bei Routinen im Rumpf, je Eintrag
    /// TRationale.Encode (Marke, Zeile, Text); alle möglichen Marken, gefiltert wird bei der Anzeige.</summary>
    Rationale: TArray<string>;
    function QualifiedName: string;
    /// <summary>Trägt die Direktive ADirective (ohne Groß-/Kleinschreibung)?</summary>
    function HasDirective(const ADirective: string): Boolean;
    function GetSignature: string;
    procedure SetSignature(const AValue: string);
    /// <summary>Kopf der Deklaration als eine Zeile, z. B. "function Foo(A: Integer): string; overload;"
    /// oder "TFoo = class(TBase)" (#492); höchstens MaxSignatureOf(Kind) Zeichen (Routinen, Methoden und
    /// Konstruktoren 1000, sonst 300). Die volle Länge liest TIndexFiles.SourceSignature aus der Quelle. Gespeichert
    /// als UTF-8 (SignatureUtf8).</summary>
    property Signature: string read GetSignature write SetSignature;
    /// <summary>Höchstlänge der Signatur einer Art (Index-Inhalte L1): Routinen, Methoden und Konstruktoren
    /// cMaxRoutineSignature, alle anderen cMaxSignature.</summary>
    class function MaxSignatureOf(AKind: TIndexSymbolKind): Integer; static;
    /// <summary>Form und Zieltyp aus einem Eintrag "target:Form=Typ" in ADirectives; False ohne.</summary>
    class function TargetOf(const ADirectives: TArray<string>; out AForm, AType: string): Boolean; static;
    /// <summary>Wert des ersten Eintrags "APrefix:Wert" in ADirectives (ohne Groß-/Kleinschreibung); '' ohne.
    /// </summary>
    class function DirectiveValueOf(const ADirectives: TArray<string>; const APrefix: string): string; static;
    /// <summary>Form des Zieltyps: "^", "set of", "array of", "array[0..9] of", "class of", "file of", "function",
    /// "procedure", "range", "enum", "record"; '' ohne Eintrag (Index-Inhalte L1).</summary>
    function TargetForm: string;
    /// <summary>Zieltyp als Text wie im Quelltext (PInteger → "Integer", array of TList&lt;T&gt; →
    /// "TList&lt;T&gt;", function: Boolean → "Boolean", 0..9 → "0..9"); '' ohne. Bewusst nicht in TypeName: Die
    /// Namensauflösung folgte sonst dem Alias, und aus PInteger würde Integer.</summary>
    function TargetType: string;
    /// <summary>Wert eines Eintrags "APrefix:Wert", z. B. DirectiveValue('external') = 'user32'.</summary>
    function DirectiveValue(const APrefix: string): string;
    /// <summary>Attribute vor der Deklaration ohne "@" in Reihenfolge ([Weak, Unsafe] → ['Weak', 'Unsafe']).</summary>
    function Attributes: TArray<string>;
    /// <summary>Zeile (0-basiert) des Rumpfs im implementation-Teil, den der Index bei Bibliotheks-Units nicht als
    /// eigenes Symbol führt; -1 ohne.</summary>
    function ImplementationLine: Integer;
    /// <summary>Einschränkungen des Typparameters AParam ("class,constructor"); '' ohne.</summary>
    function ConstraintsOf(const AParam: string): string;
  public const
    cMaxSignature = 300;
    /// <summary>Höchstlänge bei Routinen, Methoden und Konstruktoren (Index-Inhalte L1; die längste der Bibliothek hat
    /// 686 Zeichen).</summary>
    cMaxRoutineSignature = 1000;
    /// <summary>Einziger Eintrag in InlineRefs einer einbettbaren inline-Routine ohne Verweise (#1381).</summary>
    cInlineWithoutRefs = '';
    /// <summary>Vorsätze der Einträge in Directives (Index-Inhalte L1).</summary>
    cTargetPrefix = 'target:';
    cAttributePrefix = '@';
    cImplementationPrefix = 'impl';
  end;

  /// <summary>Verwendungen eines Bezeichners in einer Unit (#492, für #470): alle Stellen außer der
  /// Deklaration selbst, nach Position sortiert.</summary>
  TIndexUsage = record
    Name: string;
    Positions: TArray<TTextPosition>;
  end;

  /// <summary>Art einer Deklaration für die Präfix-Konvention des Projekts (#452).</summary>
  TNamingKind = (Field, Parameter, Local);

  /// <summary>Deklarationen einer Art und wie viele davon das übliche Präfix tragen (F, A bzw. L vor einem
  /// Großbuchstaben).</summary>
  TNamingCount = record
    Total: Integer;
    Prefixed: Integer;
  end;

  TNamingCounts = array[TNamingKind] of TNamingCount;

  /// <summary>Folgemuster einer Unit (#1890): Wie oft eine Anweisung mit dem Schlüssel Trigger vorkam und wie oft
  /// darauf die Anweisung nach der Vorlage Follow folgte. Je Trigger gibt es einen Eintrag mit Follow = '' für alle
  /// Stellen ohne erkannte Folge; der Anteil eines Musters ist sein Count durch die Summe aller Count seines
  /// Triggers. Nur Projekt-Units.</summary>
  TIndexFollowPattern = record
    /// <summary>Schlüssel der auslösenden Anweisung wie geschrieben, z. B. "$S := $T.Create", "$S := TFoo.Create",
    /// "$S.BeginUpdate" oder "EnterCriticalSection($A)"; verglichen ohne Groß-/Kleinschreibung.</summary>
    Trigger: string;
    /// <summary>Vorlage der folgenden Anweisung (TIndexFollowPatterns): Zeilen getrennt durch #10, Einrückung als
    /// führende ">", "$|" für den Rumpf, $S und $A für Subjekt und Argument; '' = keine erkannte Folge.</summary>
    Follow: string;
    Count: Integer;
    /// <summary>Zeilen (0-basiert) der ersten Auslöser als Beleg, höchstens drei; nur mit Follow.</summary>
    Lines: TArray<Integer>;
  end;

const
  /// <summary>Übliche Präfixe je Art (#452): F für Felder, A für Parameter, L für lokale Variablen.</summary>
  cNamingPrefixes: array[TNamingKind] of string = ('F', 'A', 'L');

type

  /// <summary>Nachschlagetabelle Name → Positionen in TUnitIndex.Symbols (Diagnoselog 15.10.2026): die
  /// Namensauflösung suchte jeden Bezeichner linear in allen Units der uses-Liste, bei großen Units
  /// (Winapi.Windows, Vcl.Controls) mehrere Sekunden je Datei. Gilt nur für das Symbol-Array, aus dem
  /// sie entstand; wird beim ersten Zugriff aufgebaut und ist threadsicher. Seit Speicher-Optimierung Phase 2
  /// (c4) ein nach Namen sortiertes Feld der Positionen (4 Byte je Symbol, Suche halbierend) statt eines
  /// Dictionarys mit großgeschriebenen Kopien der Namen (rund 24 MB für die Bibliothek).</summary>
  IUnitNameTable = interface
    ['{6C1F4E27-93A8-4B5D-8E02-D7A4C9B36F51}']
    /// <summary>Positionen der Symbole mit diesem Namen (ohne Groß-/Kleinschreibung) aufsteigend;
    /// False, wenn ASymbols nicht das Array der Tabelle ist.</summary>
    function Positions(const ASymbols: TArray<TIndexSymbol>; const AName: string;
      out APositions: TArray<Integer>): Boolean;
  end;

  TUnitIndex = record
    UnitName: string;
    FileName: string;
    /// <summary>Zeitstempel der Datei beim Einlesen (Ticks, vom Dateisystem vorgegeben).</summary>
    Stamp: Int64;
    /// <summary>Hash des Inhalts.</summary>
    Hash: string;
    InterfaceUses: TArray<string>;
    /// <summary>uses der implementation; bei program, library und package alle uses-Klauseln, beim package die
    /// contains-Klausel (Index-Inhalte L1).</summary>
    ImplementationUses: TArray<string>;
    /// <summary>Nur bei package: die requires-Klausel (Packages, keine Units; Index-Inhalte L1).</summary>
    Requires: TArray<string>;
    /// <summary>Hinweise im Unit-Kopf (unit X deprecated 'Grund' platform;) in Kleinschreibung: deprecated,
    /// experimental, platform, library (#1018).</summary>
    Directives: TArray<string>;
    /// <summary>Grund hinter deprecated im Unit-Kopf; '' ohne.</summary>
    DeprecatedText: string;
    /// <summary>Begründungen der Unit (#1123): Kopf und interface vor dem ersten type-Abschnitt, ohne die einer
    /// Deklaration; Format wie TIndexSymbol.Rationale.</summary>
    Rationale: TArray<string>;
    Symbols: TArray<TIndexSymbol>;
    /// <summary>Über eine uses-Liste nachgeladen (RTL, VCL, Bibliotheken), nicht aus dem Projekt.</summary>
    Library_: Boolean;
    /// <summary>Nur interface-Symbole behalten, um das Speicherbudget einzuhalten (#185).</summary>
    Compact: Boolean;
    /// <summary>Defines, mit denen die Unit gelesen wurde; nur im Speicher, nicht im Cache. Ein weiteres Projekt
    /// der Gruppe übernimmt eine Unit mit gleichem Stand und gleichem Schlüssel nicht noch einmal (Speicher,
    /// Rückmeldung 01.11.2026). '' = unbekannt, dann wird sie wie bisher neu übernommen.</summary>
    DefinesKey: string;
    /// <summary>Eingebundene Include-Dateien (#264); ändert sich eine davon, wird die Unit neu eingelesen.</summary>
    Includes: TArray<string>;
    /// <summary>Zeitstempel der Include-Dateien beim Einlesen, parallel zu Includes (#617).</summary>
    IncludeStamps: TArray<Int64>;
    /// <summary>Hat einen initialization- oder finalization-Abschnitt (#284); solche Units
    /// entfernt "ungenutzte uses entfernen" nie, weil sie etwas registrieren können.</summary>
    HasInitialization: Boolean;
    /// <summary>Felder, Parameter und lokale Variablen der Unit mit Präfix gezählt (#452); daraus ermittelt
    /// die Vervollständigung die Konvention des Projekts.</summary>
    Naming: TNamingCounts;
    /// <summary>Deklarationen aus Zweigen, die unter der aktiven Konfiguration nicht gelten (#476):
    /// getrennt von Symbols, damit Namensauflösung, Referenzen und Prüfregeln sie nicht sehen;
    /// nur die Vervollständigung zeigt sie abgeschwächt.</summary>
    Unavailable: TArray<TIndexSymbol>;
    /// <summary>Verwendungen der Bezeichner (#492), nach Name sortiert; nur Projekt-Units und nur mit
    /// index.usages.</summary>
    Usages: TArray<TIndexUsage>;
    /// <summary>Verwendungen wurden erfasst (auch wenn es keine gibt); ohne sie liest der Builder die
    /// Unit neu, sobald index.usages eingeschaltet ist.</summary>
    UsagesIndexed: Boolean;
    /// <summary>Verwendungen liegen nur im Cache auf der Platte, weil das Speicherbudget überschritten
    /// war (#492); TIndexService.UsagesOf lädt sie bei Bedarf.</summary>
    UsagesOffloaded: Boolean;
    /// <summary>Folgemuster der Unit (#1890); nur Projekt-Units, Bibliotheken bleiben leer.</summary>
    Patterns: TArray<TIndexFollowPattern>;
    /// <summary>Nachschlagetabelle der Namen; nil, solange PrepareNames nicht lief.</summary>
    NameTable: IUnitNameTable;
    /// <summary>Datei, in der ASymbol steht: seine Include-Datei (#500), sonst FileName.</summary>
    function SymbolFile(const ASymbol: TIndexSymbol): string;
    /// <summary>Legt die Nachschlagetabelle für die aktuellen Symbols an (aufgebaut wird sie beim ersten
    /// SymbolsNamed); nach jeder Änderung an Symbols erneut aufrufen.</summary>
    procedure PrepareNames;
    /// <summary>Positionen der Symbole mit dem Namen AName in Symbols, aufsteigend; ohne passende
    /// Tabelle linear gesucht.</summary>
    function SymbolsNamed(const AName: string): TArray<Integer>;
  end;

  TSymbolLocation = record
    UnitName: string;
    FileName: string;
    Symbol: TIndexSymbol;
  end;

  /// <summary>Katalogeintrag eines importierbaren Symbols (interface, oberste Ebene; Speicher-Optimierung Phase 3):
  /// nur, was "+ Unit", gleichnamige Symbole und die Helfer-Suche brauchen. Der Katalog kennt alle Units, auch die,
  /// deren volle Symbole nicht im Speicher sind; die Texte teilt er sich mit den Symbolen geladener Units. Seit
  /// Index-Inhalte L1 auch die Werte von Aufzählungen ohne {$SCOPEDENUMS} (fsBold, ssShift), deren TypeName ihr Typ
  /// ist.</summary>
  TCatalogSymbol = record
    Name: string;
    /// <summary>Wie TIndexSymbol.TypeName; bei Aufzählungswerten der Typ (TIndexSymbol.Container).</summary>
    TypeName: string;
    /// <summary>Vorfahren bei Klassen, Interfaces, Objekten und Helfern (beim Helfer der Zieltyp zuletzt); sonst
    /// nil.</summary>
    Ancestors: TArray<string>;
    /// <summary>Anfang des Namens (TIndexSymbol.SelectionRange.StartPos).</summary>
    Start: TTextPosition;
    MinArgs: SmallInt;
    MaxArgs: SmallInt;
    Kind: TIndexSymbolKind;
    /// <summary>cCatalogUnavailable, cCatalogScopedEnum; in den Bits ab cArityShift die Zahl der Typparameter
    /// (Index-Inhalte L1).</summary>
    Flags: Byte;
    /// <summary>Class- oder Record-Helper mit Zieltyp (#456)?</summary>
    function IsHelper: Boolean;
    /// <summary>Zahl der Typparameter: 1 bei TList&lt;T&gt;, 0 bei TList (Index-Inhalte L1).</summary>
    function Arity: Integer;
    /// <summary>TIndexSymbol mit den Feldern des Katalogs (InInterface; Container nur bei Aufzählungswerten, dort der
    /// Typ); der Rest bleibt leer.</summary>
    function ToSymbol: TIndexSymbol;
    /// <summary>Zahl der Typparameter in TypeParams ("K,V" → 2), höchstens cMaxArity.</summary>
    class function ArityOf(const ATypeParams: string): Integer; static;
  public const
    cCatalogUnavailable = 1;
    cCatalogScopedEnum = 2;
    cArityShift = 2;
    cMaxArity = 63;
  end;

  /// <summary>Katalog einer Unit (Speicher-Optimierung Phase 3): Kopf für die uses-Vervollständigung und die
  /// importierbaren Symbole. Bleibt im Speicher, auch wenn die Unit selbst verdrängt ist.</summary>
  TCatalogUnit = record
    UnitName: string;
    FileName: string;
    Library_: Boolean;
    InterfaceUses: TArray<string>;
    /// <summary>Die ersten cExportedTypes Typen des interface in Deklarationsreihenfolge, generische mit
    /// Typparametern (TList&lt;T&gt;); ExportedTypeCount ist die Gesamtzahl.</summary>
    ExportedTypes: TArray<string>;
    ExportedTypeCount: Integer;
    Symbols: TArray<TCatalogSymbol>;
    /// <summary>Katalog aus einer Unit mit Symbolen.</summary>
    class function FromUnit(const AUnit: TUnitIndex): TCatalogUnit; static;
    /// <summary>Ist ASymbol ein Eintrag des Katalogs (im interface, oberste Ebene)?</summary>
    class function IsEntry(const ASymbol: TIndexSymbol): Boolean; static;
    /// <summary>TUnitIndex mit Name, Datei, Bibliotheksmerker und interface-uses; ohne Symbole.</summary>
    function Header: TUnitIndex;
    /// <summary>Geschätzter Bedarf in Byte (geteilte Texte zählen bei jeder Verwendung).</summary>
    function Bytes: Int64;
  public const
    cExportedTypes = 6;
  end;

  /// <summary>Liest Abschnitte einer Datei über ein offenes Handle (Index-Cache Format 34, Speicher-Optimierung
  /// Phase 3). Unter Windows teilt das Handle Lesen, Schreiben und Löschen: Ersetzt jemand die Datei
  /// (TFile.Replace), liest es weiter den alten Stand, zu dem sein Verzeichnis passt. Threadsicher.</summary>
  IIndexBlockReader = interface
    ['{5B8E2D41-6C37-4A92-B1F0-7E3D9A4C2B58}']
    /// <summary>Liest genau ACount Byte ab AOffset; False bei Lese- oder Bereichsfehler.</summary>
    function Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
    /// <summary>Größe der Datei beim Öffnen.</summary>
    function Size: Int64;
    /// <summary>Zeitstempel der Datei beim Öffnen (wie IIndexFileSystem.FileStamp).</summary>
    function Stamp: Int64;
  end;

  /// <summary>Schreibt den Inhalt einer Datei in AStream; False bricht ab, die alte Datei bleibt.</summary>
  TIndexStreamWrite = reference to function(AStream: TStream): Boolean;

  /// <summary>Herkunft der vollen Symbole einer Unit, die nicht im Speicher ist: ihr Block im Index-Cache
  /// (Speicher-Optimierung Phase 3). Threadsicher.</summary>
  IIndexUnitSource = interface
    ['{9D41C7E2-3A58-4B16-8F2D-6E0B5A9C1D73}']
    /// <summary>Liest und dekodiert die ganze Unit (Symbole, nicht geltende Deklarationen, Verwendungen); False,
    /// wenn der Block fehlt oder beschädigt ist.</summary>
    function Load(out AUnit: TUnitIndex): Boolean;
    /// <summary>Der Block unverändert samt Prüfsumme, zum Kopieren in einen neuen Cache.</summary>
    function ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
    /// <summary>Größe des Blocks in Byte.</summary>
    function BlockSize: Integer;
  end;

  /// <summary>Geschätzter Speicher des Index nach Bereichen in Byte (#1356); die drei ergeben MemoryBytes.</summary>
  TIndexMemoryParts = record
    /// <summary>Symbole und uses der Projekt-Units (ohne Verwendungen).</summary>
    ProjectBytes: Int64;
    /// <summary>Symbole und uses der Bibliotheks-Units (ohne Verwendungen).</summary>
    LibraryBytes: Int64;
    /// <summary>Verwendungen aller Units, soweit nicht ausgelagert.</summary>
    UsageBytes: Int64;
  end;

  /// <summary>Prüffunktion für ISymbolIndex.HasSymbol.</summary>
  TSymbolMatch = reference to function(const ASymbol: TIndexSymbol): Boolean;

  /// <summary>Eine Unit des Index zum Schreiben des Caches (Speicher-Optimierung Phase 3): geladen mit Symbolen oder
  /// verdrängt als Kopf mit Katalog und Block (Source).</summary>
  TIndexStoredUnit = record
    /// <summary>Mit Symbolen, wenn Loaded; sonst nur der Kopf.</summary>
    Unit_: TUnitIndex;
    Catalog: TCatalogUnit;
    /// <summary>Block im Cache, aus dem die Unit nachgeladen werden kann; nil, solange keiner geschrieben ist.
    /// </summary>
    Source: IIndexUnitSource;
    Loaded: Boolean;
    /// <summary>Wird nie verdrängt (Projekt, Suchpfade, uses-Hülle, oft genutzt).</summary>
    Pinned: Boolean;
    SymbolCount: Integer;
    UnavailableCount: Integer;
    UsageCount: Integer;
  end;

  /// <summary>Zustand des bedarfsweisen Ladens (Speicher-Optimierung Phase 3) für das Diagnoselog "mem".</summary>
  TIndexLazyStats = record
    /// <summary>Units im Katalog (alle) und sein geschätzter Bedarf.</summary>
    CatalogUnits: Integer;
    CatalogBytes: Int64;
    /// <summary>Units mit Symbolen im Speicher, davon gepinnt (nie verdrängt) und verdrängbar.</summary>
    Loaded: Integer;
    Pinned: Integer;
    Evictable: Integer;
    /// <summary>Geschätzter Bedarf der verdrängbaren Units; Obergrenze TSymbolIndex.cEvictableBudget.</summary>
    EvictableBytes: Int64;
    /// <summary>Units nur im Katalog (verdrängt oder nie geladen).</summary>
    Cold: Integer;
    /// <summary>Nachgeladene und verdrängte Units seit dem Start des Index.</summary>
    Loads: Integer;
    Evictions: Integer;
    /// <summary>Dauer des Nachladens (Block lesen und dekodieren) in ms: Median der letzten Ladevorgänge, Höchstwert
    /// und die größte nachgeladene Unit (Byte) samt ihrer Dauer.</summary>
    LoadMedianMs: Double;
    LoadMaxMs: Double;
    LargestLoadBytes: Int64;
    LargestLoadMs: Double;
  end;

  /// <summary>Nutzungsstatistik der Bibliotheks-Units (Speicher-Optimierung Phase 3): Zähler mit Zerfall, die
  /// entscheiden, welche Units beim Aufbau geladen und nie verdrängt werden. Threadsicher.</summary>
  IIndexUsage = interface
    ['{E2A7C5D3-91B4-4F68-8C0E-3D5B7A1F9E26}']
    /// <summary>Zählt eine Nutzung der Unit AUnitName mit AWeight Punkten.</summary>
    procedure Note(const AUnitName: string; AWeight: Integer);
    /// <summary>Punkte der Unit nach Zerfall; 0 = unbekannt.</summary>
    function Score(const AUnitName: string): Integer;
    /// <summary>Datei, in der die Statistik steht ('' = nur im Speicher).</summary>
    function FileName: string;
  end;

const
  /// <summary>Ab so vielen Punkten der Nutzungsstatistik gilt eine Bibliotheks-Unit als oft genutzt (Phase 3): Der
  /// Aufbau lädt sie gleich, der Index verdrängt sie nie.</summary>
  cIndexHotScore = 24;

type

  ISymbolIndex = interface
    ['{8E3A51C4-7B29-4D6E-A0F8-2C9D41E7B635}']
    /// <summary>Fügt die Unit hinzu oder ersetzt den Stand derselben Datei.</summary>
    procedure AddUnit(const AUnit: TUnitIndex);
    procedure RemoveFile(const AFileName: string);
    /// <summary>Unit mit dem Namen AUnitName; ein Unit-Alias (WinTypes) führt auf seine Unit, wenn keine Unit
    /// so heißt.</summary>
    function FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Ergänzt Unit-Aliase (Name → Unit, DCC_UnitAlias eines Projekts) vor den bisherigen; die Vorgaben
    /// von Delphi kennt der Index von Anfang an.</summary>
    procedure AddUnitAliases(const AAliases: TArray<TPair<string, string>>);
    function FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Alle Symbole mit diesem Namen (ohne Groß-/Kleinschreibung).</summary>
    function FindSymbols(const AName: string): TArray<TSymbolLocation>;
    /// <summary>Gibt es ein Symbol mit diesem Namen, für das AMatch True liefert? Endet beim ersten Treffer und
    /// legt keine Fundstellen an (#1342). AMatch läuft unter der Sperre des Index und darf ihn nicht ändern.</summary>
    function HasSymbol(const AName: string; const AMatch: TSymbolMatch): Boolean;
    /// <summary>Direkte Nachfahren eines Typs (Klassen, Interfaces, Helfer).</summary>
    function Descendants(const ATypeName: string): TArray<TSymbolLocation>;
    /// <summary>Alle Units. Das Ergebnis ist ein geteilter Schnappschuss: nur lesen, nicht
    /// verändern.</summary>
    function Units: TArray<TUnitIndex>;
    /// <summary>Nur die Units mit Deklarationen aus nicht geltenden Zweigen (#476); meist wenige, für die
    /// Vervollständigung.</summary>
    function UnavailableUnits: TArray<TUnitIndex>;
    function UnitCount: Integer;
    function SymbolCount: Integer;
    /// <summary>Geschätzter Speicherbedarf der Einträge in Byte.</summary>
    function MemoryBytes: Int64;
    /// <summary>MemoryBytes nach Bereichen: Projekt, Bibliothek, Verwendungen (#1356).</summary>
    function MemoryParts: TIndexMemoryParts;
    /// <summary>Zahl der kompakt gehaltenen Units.</summary>
    function CompactCount: Integer;
    /// <summary>Zahl der Units, deren Verwendungen wegen des Budgets ausgelagert sind (#492).</summary>
    function OffloadedCount: Integer;
    /// <summary>Obergrenze in Byte; 0 = unbegrenzt. Wird sie überschritten, hält der Index
    /// zuerst Bibliotheks-, dann Projekt-Units kompakt.</summary>
    procedure SetBudget(ABytes: Int64);
    function Budget: Int64;
    /// <summary>Zählt jede Änderung am Index hoch; abgeleitete Strukturen (Namensindex, #617)
    /// erkennen daran, dass sie neu aufgebaut werden müssen.</summary>
    function Generation: Int64;
    /// <summary>Nach einem Aufbau: vergisst die gemeinsame Ablage gleicher Zeichenketten (Speicher-Optimierung
    /// Phase 2). Die Units behalten ihre geteilten Strings; erst später hinzukommende teilen sie nicht mehr mit
    /// früheren. Die Ablage wuchs sonst mit jedem Text und hielt auch die ersetzter Fassungen.</summary>
    procedure ReleaseStringPool;
    /// <summary>Wie FindFile, lädt aber nichts nach (Speicher-Optimierung Phase 3): eine verdrängte Unit kommt als
    /// Kopf ohne Symbole. Für Entscheidungen des Aufbaus (Stand, Defines, Includes).</summary>
    function FindHeader(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Wie FindUnit ohne Nachladen.</summary>
    function FindUnitHeader(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Katalog aller Units, auch der verdrängten; geteilter Schnappschuss bis zur nächsten Änderung
    /// (Generation). Nachladen und Verdrängen ändern ihn nicht.</summary>
    function CatalogUnits: TArray<TCatalogUnit>;
    /// <summary>Alle Units zum Schreiben des Caches.</summary>
    function StoredUnits: TArray<TIndexStoredUnit>;
    /// <summary>Wie AddUnit für eine Bibliotheks-Unit, die verdrängt werden darf, sobald ihr Block bekannt ist
    /// (ASource; nil = noch nicht im Cache).</summary>
    procedure AddEvictable(const AUnit: TUnitIndex; const ASource: IIndexUnitSource);
    /// <summary>Nur Kopf und Katalog einer Unit; ihre Symbole lädt FindUnit bzw. FindFile bei Bedarf aus ASource.
    /// </summary>
    procedure AddCold(const AHeader: TUnitIndex; const ACatalog: TCatalogUnit; const ASource: IIndexUnitSource;
      ASymbolCount, AUnavailableCount, AUsageCount: Integer);
    /// <summary>Hält die Unit AFileName dauerhaft im Speicher und lädt sie dafür nach; AWasPinned sagt, ob sie es
    /// schon war. False, wenn sie unbekannt ist oder sich nicht laden lässt.</summary>
    function Pin(const AFileName: string; out AWasPinned: Boolean): Boolean;
    /// <summary>Gibt den Units mit gleichem Stand (Datei, Zeitstempel, Hash wie in AHeaders) die Blöcke ASources (nach
    /// dem Schreiben oder Lesen eines Caches); liefert ihre Zahl. Nicht gepinnte dürfen danach verdrängt werden, bei
    /// gepinnten dient der Block dem nächsten Cache als Kopie.</summary>
    function BindSources(const AHeaders: TArray<TUnitIndex>; const ASources: TArray<IIndexUnitSource>): Integer;
    function LazyStats: TIndexLazyStats;
    /// <summary>Nutzungsstatistik der Bibliotheks-Units; nil = keine.</summary>
    procedure SetUsage(const AUsage: IIndexUsage);
    function Usage: IIndexUsage;
  end;

  /// <summary>Antworten, die nur vom Index und einem Namen abhängen, über alle Units eines Arbeitsbereichs
  /// gemerkt (TIndexNameFacts in dpcc.Common.Index.NameFacts).</summary>
  IIndexNameFacts = interface
    ['{4C2E8B91-7A3D-4F15-9E62-0B8D3C5A1F47}']
    /// <summary>Gemerkte Antwort zu AKey für diese Fassung von AIndex; beim ersten Mal aus ACompute. AKey nennt
    /// Frage und Namen ("propertyAccess:COUNT").</summary>
    function Lookup(const AIndex: ISymbolIndex; const AKey: string; const ACompute: TFunc<Integer>): Integer;
  end;

  IIndexFileSystem = interface
    ['{2F6C8B93-1E4D-4A75-9C02-B7E5D3A86F14}']
    /// <summary>Zeitstempel der Datei; False, wenn sie fehlt.</summary>
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    /// <summary>Binärer Inhalt (Index-Cache, #617); False, wenn die Datei fehlt.</summary>
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    /// <summary>Schreibt den binären Inhalt so, dass ein Leser nie einen halben Stand sieht. False mit AError
    /// (Grund ohne Pfad, für das anonyme Log), wenn es nicht ging.</summary>
    function WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
    /// <summary>Ein Schreiber je Datei über alle Prozesse: sperrt AFileName, ohne zu warten; nil,
    /// wenn ein anderer sie hält. Freigeben des Ergebnisses hebt die Sperre auf.</summary>
    function TryLockWrite(const AFileName: string): IInterface;
    /// <summary>Öffnet AFileName zum Lesen einzelner Abschnitte (Index-Cache Format 34); nil, wenn sie fehlt oder
    /// sich nicht öffnen lässt.</summary>
    function OpenBlocks(const AFileName: string): IIndexBlockReader;
    /// <summary>Wie WriteBytes, nur schreibt AWrite den Inhalt nach und nach in einen Strom (Index-Cache Format 34):
    /// Der ganze Cache liegt nie am Stück im Speicher. Ein Leser sieht nie einen halben Stand.</summary>
    function WriteStream(const AFileName: string; const AWrite: TIndexStreamWrite; out AError: string): Boolean;
  end;

  /// <summary>Optional neben IIndexFileSystem (Speicher-Optimierung Phase 4): eine Datei an Ort und Stelle ergänzen
  /// (Zwischenstände des Bibliotheks-Caches beim ersten Aufbau), statt sie ganz neu zu schreiben.</summary>
  IIndexFileAppend = interface
    ['{7A3C9E51-2D84-4B6F-9C17-E05B8D2F4A63}']
    /// <summary>Öffnet AFileName zum Lesen und Schreiben, wenn sie noch den Zeitstempel AStamp hat, und übergibt sie
    /// AWrite (der Strom umfasst die ganze Datei). Andere Leser lesen die Blöcke vor dem alten Ende weiter (mit
    /// gehaltenem Handle wie ohne, TReopeningBlockReader); AWrite schreibt neue Teile ans Ende und zuletzt den Kopf.
    /// Der Zeitstempel (auf ms gerundet) ist nur die erste Prüfung: AWrite vergleicht Größe und Kopf mit dem bekannten
    /// Stand (TIndexCache.Append mit AKnown, Phase 5). False mit AError (ohne Pfad), wenn die Datei fehlt, sich
    /// geändert hat, sich nicht öffnen lässt oder AWrite False liefert.</summary>
    function AppendStream(const AFileName: string; AStamp: Int64; const AWrite: TIndexStreamWrite;
      out AError: string): Boolean;
  end;

  /// <summary>Öffnet eine Datei für IIndexBlockReader; von der Plattform gesetzt (TIndexBlockFiles).</summary>
  TIndexBlockOpener = reference to function(const AFileName: string): IIndexBlockReader;

  /// <summary>Lesen einzelner Abschnitte einer Datei (Speicher-Optimierung Phase 3). Ohne Opener öffnet jeder
  /// Lesevorgang die Datei neu (RTL, ohne Löschen zu teilen) und prüft, dass sie seit dem Öffnen nicht ersetzt
  /// wurde (nur am Ende gewachsen gilt als unverändert, Phase 5); unter Windows trägt die Plattform einen Opener ein,
  /// der das Handle hält und Löschen teilt (dpcc.Windows.Documents.SharedRead).</summary>
  TIndexBlockFiles = class
  private
    class var FOpener: TIndexBlockOpener;
  public
    /// <summary>Reader über AFileName; nil, wenn sie fehlt.</summary>
    class function Open(const AFileName: string): IIndexBlockReader; static;
    /// <summary>Reader über Bytes im Speicher (Tests, Dateisystem im Speicher).</summary>
    class function OfBytes(const ABytes: TBytes; AStamp: Int64): IIndexBlockReader; static;
    /// <summary>Nur beim Start setzen.</summary>
    class property Opener: TIndexBlockOpener read FOpener write FOpener;
  end;

  TIndexProgressKind = (Started, Report, Finished);

  TFileChangeKind = (Created, Changed, Deleted);

  /// <summary>Änderung einer Datei außerhalb des Editors.</summary>
  TFileChange = record
    FileName: string;
    Kind: TFileChangeKind;
    constructor Create(const AFileName: string; AKind: TFileChangeKind);
  end;

  /// <summary>Fortschritt des Aufbaus; APercent 0..100.</summary>
  TIndexProgressEvent = reference to procedure(AKind: TIndexProgressKind; const AMessage: string;
    APercent: Integer);

  /// <summary>Unit-Name → Datei; '' wenn unbekannt.</summary>
  TUnitFileResolver = reference to function(const AUnitName: string): string;

  /// <summary>Abbruch des Aufbaus abfragen.</summary>
  TIndexCancelled = reference to function: Boolean;

  /// <summary>Lädt AUnitName bei Bedarf in den Index nach (Namensauflösung, #178); True, wenn sie danach
  /// vorliegt. Steht hier statt in dpcc.Common.Semantics.NameResolver, damit Contracts sie ohne fremdes
  /// Root nutzen können.</summary>
  TEnsureUnitFunc = reference to function(const AUnitName: string): Boolean;

  /// <summary>Stufen des Aufbaus (#648): Projektdateien samt über uses erreichbarer Units, dann alle Units
  /// der Projekt-Suchpfade, zuletzt alle Units der Bibliotheks- und Suchpfade der Installation.</summary>
  TIndexStage = (Project, SearchPaths, Library_);

  /// <summary>Reihenfolge mehrerer Aufbauten (Projekte einer Gruppe): Enter wartet, bis die Stufe dran ist,
  /// und liefert False bei Abbruch; Leave gibt sie wieder frei.</summary>
  IIndexTurn = interface
    ['{4A7E2C91-5B38-4F06-9D1A-E3C6B8F0A217}']
    function Enter(AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
    procedure Leave;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults;

type
  TUnitNameTable = class(TInterfacedObject, IUnitNameTable)
  private
    FSymbols: TArray<TIndexSymbol>;
    // Positionen in FSymbols, geordnet nach Name ohne Groß-/Kleinschreibung (CompareText, wie früher der
    // großgeschriebene Schlüssel), gleiche Namen aufsteigend nach Position.
    FOrder: TArray<Integer>;
    FBuilt: Boolean;
    procedure Build;
  public
    constructor Create(const ASymbols: TArray<TIndexSymbol>);
    function Positions(const ASymbols: TArray<TIndexSymbol>; const AName: string;
      out APositions: TArray<Integer>): Boolean;
  end;

{ TUnitNameTable }

constructor TUnitNameTable.Create(const ASymbols: TArray<TIndexSymbol>);
begin
  inherited Create;
  FSymbols := ASymbols;
end;

procedure TUnitNameTable.Build;
var
  mOrder: TArray<Integer>;
  mSymbols: TArray<TIndexSymbol>;
  mPosition: Integer;
begin
  SetLength(mOrder, Length(FSymbols));
  for mPosition := 0 to High(mOrder) do
  begin
    mOrder[mPosition] := mPosition;
  end;
  mSymbols := FSymbols;
  // Zugriff über den Index, damit die Symbol-Records nicht kopiert werden.
  TArray.Sort<Integer>(mOrder, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := CompareText(mSymbols[ALeft].Name, mSymbols[ARight].Name);
      if Result = 0 then
      begin
        Result := ALeft - ARight;
      end;
    end));
  FOrder := mOrder;
end;

function TUnitNameTable.Positions(const ASymbols: TArray<TIndexSymbol>; const AName: string;
  out APositions: TArray<Integer>): Boolean;
var
  mLow, mHigh, mMiddle, mEnd, mPosition: Integer;
begin
  APositions := nil;
  if Pointer(ASymbols) <> Pointer(FSymbols) then
  begin
    Exit(False);
  end;
  if not FBuilt then
  begin
    TMonitor.Enter(Self);
    try
      if not FBuilt then
      begin
        Build;
        FBuilt := True;
      end;
    finally
      TMonitor.Exit(Self);
    end;
  end;
  Result := True;
  // Erste Stelle, deren Name nicht vor AName liegt.
  mLow := 0;
  mHigh := Length(FOrder);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) shr 1;
    if CompareText(FSymbols[FOrder[mMiddle]].Name, AName) < 0 then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  mEnd := mLow;
  while (mEnd < Length(FOrder)) and (CompareText(FSymbols[FOrder[mEnd]].Name, AName) = 0) do
  begin
    Inc(mEnd);
  end;
  SetLength(APositions, mEnd - mLow);
  for mPosition := mLow to mEnd - 1 do
  begin
    APositions[mPosition - mLow] := FOrder[mPosition];
  end;
end;

{ TIndexSymbol }

function TIndexSymbol.QualifiedName: string;
begin
  if Container = '' then
  begin
    Result := Name;
  end
  else
  begin
    Result := Container + '.' + Name;
  end;
end;

function TIndexSymbol.GetSignature: string;
begin
  if SignatureUtf8 = '' then
  begin
    Result := '';
  end
  else
  begin
    Result := UTF8ToString(SignatureUtf8);
  end;
end;

procedure TIndexSymbol.SetSignature(const AValue: string);
begin
  if AValue = '' then
  begin
    SignatureUtf8 := '';
  end
  else
  begin
    SignatureUtf8 := UTF8Encode(AValue);
  end;
end;

function TIndexSymbol.HasDirective(const ADirective: string): Boolean;
var
  mDirective: string;
begin
  for mDirective in Directives do
  begin
    if SameText(mDirective, ADirective) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TIndexSymbol.MaxSignatureOf(AKind: TIndexSymbolKind): Integer;
begin
  if AKind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_] then
  begin
    Result := cMaxRoutineSignature;
  end
  else
  begin
    Result := cMaxSignature;
  end;
end;

class function TIndexSymbol.TargetOf(const ADirectives: TArray<string>; out AForm, AType: string): Boolean;
var
  mDirective: string;
  mEqual: Integer;
begin
  AForm := '';
  AType := '';
  for mDirective in ADirectives do
  begin
    if StartsText(cTargetPrefix, mDirective) then
    begin
      mEqual := Pos('=', mDirective);
      if mEqual = 0 then
      begin
        AForm := Copy(mDirective, Length(cTargetPrefix) + 1, MaxInt);
      end
      else
      begin
        AForm := Copy(mDirective, Length(cTargetPrefix) + 1, mEqual - Length(cTargetPrefix) - 1);
        AType := Copy(mDirective, mEqual + 1, MaxInt);
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TIndexSymbol.DirectiveValueOf(const ADirectives: TArray<string>; const APrefix: string): string;
var
  mDirective: string;
begin
  for mDirective in ADirectives do
  begin
    if (Length(mDirective) > Length(APrefix) + 1) and (mDirective[Length(APrefix) + 1] = ':') and
      StartsText(APrefix, mDirective) then
    begin
      Exit(Copy(mDirective, Length(APrefix) + 2, MaxInt));
    end;
  end;
  Result := '';
end;

function TIndexSymbol.TargetForm: string;
var
  mType: string;
begin
  TargetOf(Directives, Result, mType);
end;

function TIndexSymbol.TargetType: string;
var
  mForm: string;
begin
  TargetOf(Directives, mForm, Result);
end;

function TIndexSymbol.DirectiveValue(const APrefix: string): string;
begin
  Result := DirectiveValueOf(Directives, APrefix);
end;

function TIndexSymbol.Attributes: TArray<string>;
var
  mDirective: string;
begin
  Result := nil;
  for mDirective in Directives do
  begin
    if (Length(mDirective) > 1) and (mDirective[1] = cAttributePrefix) then
    begin
      Result := Result + [Copy(mDirective, 2, MaxInt)];
    end;
  end;
end;

function TIndexSymbol.ImplementationLine: Integer;
begin
  Result := StrToIntDef(DirectiveValue(cImplementationPrefix), -1);
end;

function TIndexSymbol.ConstraintsOf(const AParam: string): string;
var
  mDirective: string;
begin
  for mDirective in Directives do
  begin
    if (Length(mDirective) > Length(AParam) + 3) and (mDirective[1] = '<') and
      (mDirective[Length(mDirective)] = '>') and (mDirective[Length(AParam) + 2] = ':') and
      SameText(Copy(mDirective, 2, Length(AParam)), AParam) then
    begin
      Exit(Copy(mDirective, Length(AParam) + 3, Length(mDirective) - Length(AParam) - 3));
    end;
  end;
  Result := '';
end;

{ TUnitIndex }

function TUnitIndex.SymbolFile(const ASymbol: TIndexSymbol): string;
begin
  if ASymbol.FileName <> '' then
  begin
    Result := ASymbol.FileName;
  end
  else
  begin
    Result := FileName;
  end;
end;

procedure TUnitIndex.PrepareNames;
begin
  NameTable := TUnitNameTable.Create(Symbols);
end;

function TUnitIndex.SymbolsNamed(const AName: string): TArray<Integer>;
var
  mPosition, mCount: Integer;
begin
  if (NameTable <> nil) and NameTable.Positions(Symbols, AName, Result) then
  begin
    Exit;
  end;
  // Ohne Tabelle linear; das Ergebnis wächst in Stufen statt je Treffer um eins.
  Result := nil;
  mCount := 0;
  for mPosition := 0 to High(Symbols) do
  begin
    if SameText(Symbols[mPosition].Name, AName) then
    begin
      if mCount = Length(Result) then
      begin
        SetLength(Result, mCount * 2 + 4);
      end;
      Result[mCount] := mPosition;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

{ TFileChange }

constructor TFileChange.Create(const AFileName: string; AKind: TFileChangeKind);
begin
  FileName := AFileName;
  Kind := AKind;
end;

{ TCatalogSymbol }

function TCatalogSymbol.IsHelper: Boolean;
begin
  Result := (Kind = TIndexSymbolKind.HelperType) and (Length(Ancestors) > 0);
end;

function TCatalogSymbol.Arity: Integer;
begin
  Result := Flags shr cArityShift;
end;

class function TCatalogSymbol.ArityOf(const ATypeParams: string): Integer;
var
  mIndex: Integer;
begin
  if Trim(ATypeParams) = '' then
  begin
    Exit(0);
  end;
  Result := 1;
  for mIndex := 1 to Length(ATypeParams) do
  begin
    if ATypeParams[mIndex] = ',' then
    begin
      Inc(Result);
    end;
  end;
  if Result > cMaxArity then
  begin
    Result := cMaxArity;
  end;
end;

function TCatalogSymbol.ToSymbol: TIndexSymbol;
begin
  Result := Default(TIndexSymbol);
  Result.Name := Name;
  Result.Kind := Kind;
  Result.InInterface := True;
  if Kind = TIndexSymbolKind.EnumMember then
  begin
    // Aufzählungswert (L1): Der Katalog führt seinen Typ als TypeName, der Index als Container.
    Result.Container := TypeName;
  end
  else
  begin
    Result.TypeName := TypeName;
  end;
  Result.Ancestors := Ancestors;
  Result.SelectionRange.StartPos := Start;
  Result.SelectionRange.EndPos := TTextPosition.Create(Start.Line, Start.Character + Length(Name));
  Result.Range := Result.SelectionRange;
  Result.MinArgs := MinArgs;
  Result.MaxArgs := MaxArgs;
  Result.Unavailable := (Flags and cCatalogUnavailable) <> 0;
  Result.ScopedEnum := (Flags and cCatalogScopedEnum) <> 0;
end;

{ TCatalogUnit }

const
  /// <summary>Typen für die uses-Vervollständigung (wie cIndexTypeKinds der Vervollständigung).</summary>
  cCatalogTypeKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias];
  /// <summary>Arten, deren Vorfahren der Katalog behält (Filter für Exceptions und Attribute, Helfer).</summary>
  cCatalogAncestorKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];

class function TCatalogUnit.IsEntry(const ASymbol: TIndexSymbol): Boolean;
begin
  // Aufzählungswerte ohne {$SCOPEDENUMS} eines Typs auf oberster Ebene gelten wie Symbole der Unit (fsBold, L1);
  // Werte eines verschachtelten Typs (TFoo.TArt) brauchen den Typ davor.
  Result := ASymbol.InInterface and ((ASymbol.Container = '') or ((ASymbol.Kind = TIndexSymbolKind.EnumMember) and
    not ASymbol.ScopedEnum and not ASymbol.Unavailable and (Pos('.', ASymbol.Container) = 0)));
end;

class function TCatalogUnit.FromUnit(const AUnit: TUnitIndex): TCatalogUnit;
var
  mPosition, mCount: Integer;
  mName: string;
begin
  Result := Default(TCatalogUnit);
  Result.UnitName := AUnit.UnitName;
  Result.FileName := AUnit.FileName;
  Result.Library_ := AUnit.Library_;
  Result.InterfaceUses := AUnit.InterfaceUses;
  mCount := 0;
  for mPosition := 0 to High(AUnit.Symbols) do
  begin
    Inc(mCount, Ord(IsEntry(AUnit.Symbols[mPosition])));
  end;
  SetLength(Result.Symbols, mCount);
  mCount := 0;
  // Über den Index: die Symbol-Records nicht kopieren.
  for mPosition := 0 to High(AUnit.Symbols) do
  begin
    if not IsEntry(AUnit.Symbols[mPosition]) then
    begin
      Continue;
    end;
    Result.Symbols[mCount].Name := AUnit.Symbols[mPosition].Name;
    if AUnit.Symbols[mPosition].Kind = TIndexSymbolKind.EnumMember then
    begin
      Result.Symbols[mCount].TypeName := AUnit.Symbols[mPosition].Container;
    end
    else
    begin
      Result.Symbols[mCount].TypeName := AUnit.Symbols[mPosition].TypeName;
    end;
    if AUnit.Symbols[mPosition].Kind in cCatalogAncestorKinds then
    begin
      Result.Symbols[mCount].Ancestors := AUnit.Symbols[mPosition].Ancestors;
    end;
    Result.Symbols[mCount].Start := AUnit.Symbols[mPosition].SelectionRange.StartPos;
    Result.Symbols[mCount].MinArgs := AUnit.Symbols[mPosition].MinArgs;
    Result.Symbols[mCount].MaxArgs := AUnit.Symbols[mPosition].MaxArgs;
    Result.Symbols[mCount].Kind := AUnit.Symbols[mPosition].Kind;
    Result.Symbols[mCount].Flags := 0;
    if AUnit.Symbols[mPosition].Unavailable then
    begin
      Result.Symbols[mCount].Flags := Result.Symbols[mCount].Flags or TCatalogSymbol.cCatalogUnavailable;
    end;
    if AUnit.Symbols[mPosition].ScopedEnum then
    begin
      Result.Symbols[mCount].Flags := Result.Symbols[mCount].Flags or TCatalogSymbol.cCatalogScopedEnum;
    end;
    // Generik-Arität (L1): "+ Unit" unterscheidet TList und TList<T>.
    Result.Symbols[mCount].Flags := Result.Symbols[mCount].Flags or
      Byte(TCatalogSymbol.ArityOf(AUnit.Symbols[mPosition].TypeParams) shl TCatalogSymbol.cArityShift);
    Inc(mCount);
    if AUnit.Symbols[mPosition].Kind in cCatalogTypeKinds then
    begin
      Inc(Result.ExportedTypeCount);
      if Length(Result.ExportedTypes) < cExportedTypes then
      begin
        mName := AUnit.Symbols[mPosition].Name;
        if AUnit.Symbols[mPosition].TypeParams <> '' then
        begin
          mName := mName + '<' + AUnit.Symbols[mPosition].TypeParams.Replace(' ', '') + '>';
        end;
        Result.ExportedTypes := Result.ExportedTypes + [mName];
      end;
    end;
  end;
end;

function TCatalogUnit.Header: TUnitIndex;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := UnitName;
  Result.FileName := FileName;
  Result.Library_ := Library_;
  Result.InterfaceUses := InterfaceUses;
end;

/// <summary>Kopf, UTF-16-Zeichen und Endnull eines Strings wie in TIndexMemory.</summary>
function CatalogStringBytes(const AValue: string): Int64;
begin
  if AValue = '' then
  begin
    Result := 0;
  end
  else
  begin
    Result := 12 + (Length(AValue) + 1) * SizeOf(Char);
  end;
end;

function TCatalogUnit.Bytes: Int64;
var
  mIndex: Integer;
begin
  // Namen der Symbole zählen voll, Typnamen und Vorfahren nur als Verweis: Sie teilen sich wenige Texte.
  Result := SizeOf(TCatalogUnit) + CatalogStringBytes(UnitName) + CatalogStringBytes(FileName) +
    16 + Length(InterfaceUses) * SizeOf(Pointer);
  for mIndex := 0 to High(ExportedTypes) do
  begin
    Inc(Result, CatalogStringBytes(ExportedTypes[mIndex]) + SizeOf(Pointer));
  end;
  if Length(Symbols) > 0 then
  begin
    Inc(Result, 16 + Int64(Length(Symbols)) * SizeOf(TCatalogSymbol));
  end;
  for mIndex := 0 to High(Symbols) do
  begin
    Inc(Result, CatalogStringBytes(Symbols[mIndex].Name));
  end;
end;

{ Blockleser }

type
  /// <summary>Abschnitte aus Bytes im Speicher.</summary>
  TBytesBlockReader = class(TInterfacedObject, IIndexBlockReader)
  private
    FBytes: TBytes;
    FStamp: Int64;
  public
    constructor Create(const ABytes: TBytes; AStamp: Int64);
    function Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
    function Size: Int64;
    function Stamp: Int64;
  end;

  /// <summary>Ohne Opener der Plattform: öffnet die Datei je Lesevorgang neu (die RTL teilt Löschen nicht, ein
  /// gehaltenes Handle verhinderte das Ersetzen) und liest nur, solange sie den Stand vom Öffnen hat (Zeitstempel und
  /// Größe) oder nur am Ende gewachsen ist (Ergänzen, IIndexFileAppend, Phase 5): Was vor der alten Größe steht, ändert
  /// das Ergänzen nicht außer dem Kopf, und jeden Block schützt seine Prüfsumme. Vorher scheiterte nach einem Ergänzen
  /// jeder Lesevorgang über die alten Blöcke, und der Index verlor Units.</summary>
  TReopeningBlockReader = class(TInterfacedObject, IIndexBlockReader)
  private
    FFileName: string;
    FSize: Int64;
    FStamp: Int64;
  public
    constructor Create(const AFileName: string; ASize, AStamp: Int64);
    function Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
    function Size: Int64;
    function Stamp: Int64;
  end;

constructor TBytesBlockReader.Create(const ABytes: TBytes; AStamp: Int64);
begin
  inherited Create;
  FBytes := ABytes;
  FStamp := AStamp;
end;

function TBytesBlockReader.Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
begin
  ABytes := nil;
  Result := (AOffset >= 0) and (ACount >= 0) and (AOffset + ACount <= Length(FBytes));
  if Result then
  begin
    ABytes := Copy(FBytes, Integer(AOffset), ACount);
  end;
end;

function TBytesBlockReader.Size: Int64;
begin
  Result := Length(FBytes);
end;

function TBytesBlockReader.Stamp: Int64;
begin
  Result := FStamp;
end;

/// <summary>Zeitstempel wie TDiskIndexFileSystem.FileStamp; False, wenn die Datei fehlt.</summary>
function DiskStamp(const AFileName: string; out AStamp: Int64): Boolean;
var
  mAge: TDateTime;
begin
  Result := FileAge(AFileName, mAge);
  AStamp := 0;
  if Result then
  begin
    AStamp := Round(mAge * MSecsPerDay);
  end;
end;

constructor TReopeningBlockReader.Create(const AFileName: string; ASize, AStamp: Int64);
begin
  inherited Create;
  FFileName := AFileName;
  FSize := ASize;
  FStamp := AStamp;
end;

function TReopeningBlockReader.Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
var
  mStream: TFileStream;
  mStamp: Int64;
begin
  ABytes := nil;
  if (AOffset < 0) or (ACount < 0) or (AOffset + ACount > FSize) or not DiskStamp(FFileName, mStamp) then
  begin
    Exit(False);
  end;
  try
    mStream := TFileStream.Create(FFileName, fmOpenRead or fmShareDenyNone);
    try
      // Unverändert oder nur gewachsen (Phase 5); kleiner oder gleich groß mit anderem Zeitstempel heißt ersetzt.
      Result := ((mStamp = FStamp) and (mStream.Size = FSize)) or (mStream.Size > FSize);
      if Result then
      begin
        SetLength(ABytes, ACount);
        mStream.Position := AOffset;
        if ACount > 0 then
        begin
          mStream.ReadBuffer(ABytes[0], ACount);
        end;
      end;
    finally
      mStream.Free;
    end;
  except
    on EStreamError do
      Result := False;
    on EInOutError do
      Result := False;
  end;
  if not Result then
  begin
    ABytes := nil;
  end;
end;

function TReopeningBlockReader.Size: Int64;
begin
  Result := FSize;
end;

function TReopeningBlockReader.Stamp: Int64;
begin
  Result := FStamp;
end;

{ TIndexBlockFiles }

class function TIndexBlockFiles.Open(const AFileName: string): IIndexBlockReader;
var
  mOpener: TIndexBlockOpener;
  mStamp, mSize: Int64;
  mStream: TFileStream;
begin
  mOpener := FOpener;
  if Assigned(mOpener) then
  begin
    Exit(mOpener(AFileName));
  end;
  Result := nil;
  if not FileExists(AFileName) or not DiskStamp(AFileName, mStamp) then
  begin
    Exit;
  end;
  try
    mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
    try
      mSize := mStream.Size;
    finally
      mStream.Free;
    end;
  except
    on EStreamError do
      Exit(nil);
    on EInOutError do
      Exit(nil);
  end;
  Result := TReopeningBlockReader.Create(AFileName, mSize, mStamp);
end;

class function TIndexBlockFiles.OfBytes(const ABytes: TBytes; AStamp: Int64): IIndexBlockReader;
begin
  Result := TBytesBlockReader.Create(ABytes, AStamp);
end;

end.
