unit dpcc.Common.Index.Cache;

// Festplatten-Cache des Symbolindex. Je Unit stehen Zeitstempel und Hash
// darin; beim Start werden nur geänderte Dateien neu eingelesen. Ein Cache
// mit anderer Formatversion (auch die früheren Text- und JSON-Formate) wird
// verworfen.
//
// Format 34 (Speicher-Optimierung Phase 3): Jede Unit steht in einem eigenen
// Block mit eigener String-Tabelle und eigener Prüfsumme; am Ende der Datei
// steht ein Verzeichnis aller Units (Name, Datei, Stand, uses, Katalog der
// importierbaren Symbole, Lage und Prüfsumme des Blocks). Der Leser liest nur
// Kopf und Verzeichnis; den Block einer Unit liest er einzeln über ein offenes
// Handle (IIndexBlockReader, ReadFile mit Offset), wenn er sie braucht. Format
// 33 hatte eine gemeinsame String-Tabelle (rund 950.000 Texte) und eine
// Prüfsumme über die ganze Datei: Einzelne Units ließen sich so nicht lesen,
// und jeder Start dekodierte die ganze Datei. Caches im Format 33 heißen
// index-33.dpccidx und werden nicht mehr gelesen; der erste Start baut den
// Index einmal neu auf.
// - Ein beschädigter Block betrifft nur seine Unit: Expand liefert False, der
//   Aufbau liest sie aus der Datei neu. Ein beschädigtes Verzeichnis (falsche
//   Prüfsumme, abgeschnittene Datei) verwirft den ganzen Cache wie bisher.
// - Signaturen dekodiert der Leser nicht nach UTF-16, sondern kopiert ihre
//   UTF-8-Bytes (TIndexSymbol.SignatureUtf8); Texte dekodiert er erst beim
//   ersten Lesen und teilt sie innerhalb der Unit.
// - Write schreibt Block für Block in einen Strom (IIndexFileSystem.WriteStream);
//   Units, die nicht im Speicher sind, kopiert es als unveränderten Block aus
//   dem alten Cache (IIndexUnitSource.ReadBlock). Der Cache liegt beim
//   Schreiben nie am Stück im Speicher.
//
// Format 35 (Index-Inhalte L1): ohne Kurztext je Symbol (TIndexSymbol.Summary las niemand); im Kopf der Unit
// zuletzt die requires-Klausel eines Packages. Neue Merkmale stehen ohne eigenes Feld in den Direktiven
// (TIndexSymbol.Directives: Zieltyp, Attribute, DLL-Angaben, Arten, Einschränkungen); der Katalog führt auch die
// Werte von Aufzählungen ohne {$SCOPEDENUMS} (Typ als Typname) und die Zahl der Typparameter in den Merkern (ab Bit
// 2). Bibliotheks-Units enthalten keine Rümpfe mehr, die eine interface-Deklaration wiederholen. Caches älterer
// Formate liest der Server nicht; beim Schreiben eines Caches im Format 35 löscht er die Dateien index-NN.dpccidx
// älterer Formate im selben Ordner (TIndexCacheDirectory.RemoveOlderFormats).
//
// Aufbau (Zahlen als Varint, vorzeichenbehaftete per ZigZag; fest = Little Endian):
//   Kopf (25 Byte): 'DPCCINDX' Version (1 Byte) Verzeichnis-Offset (8 Byte fest)
//            Verzeichnis-Länge (4 Byte fest) Verzeichnis-Prüfsumme (4 Byte fest, FNV-1a)
//   Blöcke:  je Unit: Texte (Anzahl, je Text Bytelänge und UTF-8-Bytes, Nummer 0 = '')
//            Kopf der Unit, Symbolzahl, Zahl-nicht-verfügbar, Symbole, Verwendungszahl, Verwendungen
//   Verzeichnis (am Ende): Texte wie oben, Unit-Anzahl, je Unit:
//            Name Datei Zeitstempel Hash Merker uses(interface) uses(implementation)
//            Include-Dateien Include-Zeitstempel Symbolzahl Zahl-nicht-verfügbar Verwendungszahl
//            Katalog: Typzahl Typen(Liste) Symbolzahl, je Symbol Name Typ Art Zeile Spalte MinArgs MaxArgs
//            Merker Vorfahren(Liste); dann Block-Offset Block-Länge Block-Prüfsumme
//   Kopf der Unit: Name Datei Zeitstempel Hash Merker uses(interface) uses(implementation)
//            Include-Dateien Include-Zeitstempel Namenszählung Hinweise Grund Begründungen Folgemuster requires
//            Merker: 1 = Bibliothek, 2 = kompakt, 4 = initialization/finalization, 8 = Verwendungen erfasst
//   Symbol:  Name Container Art L1 C1 L2 C2 SL1 SC1 SL2 SC2 Merker Vorfahren Typ
//            Typargumente Vorfahr-Typargumente Typparameter Sichtbarkeit MinArgs MaxArgs
//            Parametertypen Include-Datei Bedingung Signatur Direktiven Grund
//            Variante Inline-Verweise Zuordnungen Begründungen
//            Merker: 1 = InInterface, 2 = Default, 4 = Virtuell, 8 = NichtVerfügbar, 16 = ScopedEnum
//   Verwendung: Name Anzahl, je Stelle Zeilenabstand zur vorigen und Spalte
// Listen: Anzahl, dann die Einträge. Die Datei heißt index-35.dpccidx (Ablage in
// Index.Adapters.CacheDirectory).
//
// Speicher-Optimierung Phase 4 (ohne Formatänderung):
// - Write meldet die Lage jedes geschriebenen Blocks (TIndexBlockPlace); der Index bekommt seine Blöcke daraus
//   (SourceAt), statt das eben geschriebene Verzeichnis neu zu lesen.
// - Append ergänzt eine bestehende Datei an Ort und Stelle (erster Aufbau, Zwischenstände der Bibliothek): Blöcke,
//   die schon in der Datei stehen, bleiben, neue kommen ans Ende, dahinter ein neues Verzeichnis aller Units, zuletzt
//   der Kopf. Das alte Verzeichnis bleibt als ungenutzter Bereich, bis die Datei das nächste Mal ganz geschrieben
//   wird. Darum muss das Verzeichnis nicht mehr am Dateiende stehen, nur innerhalb der Datei: Bricht ein Ergänzen
//   ab, bevor der Kopf geschrieben ist, gilt der alte Stand weiter.
// - Ein Block lässt sich ohne Verwendungen (LoadFrom mit AUsages = False) oder nur mit ihnen (ExpandUsages)
//   dekodieren; der Rest wird überlesen, ohne Texte zu dekodieren.
//
// Speicher-Optimierung Phase 5 (ohne Formatänderung):
// - Überlesen prüft wie das Dekodieren, dass jede Textnummer in der String-Tabelle steht und der Dateiname einer Unit
//   nicht leer ist (nur die Nummer und die Länge, ohne den Text zu dekodieren). Vorher nahm das Teil-Dekodieren Blöcke
//   an, die das volle Dekodieren verwarf.
// - Append ergänzt nur die Datei, die der übergebene Leser kennt: gleiche Größe und gleicher Kopf (Lage, Länge und
//   Prüfsumme des Verzeichnisses). Der Zeitstempel allein (auf ms gerundet) unterschied eine ersetzte Datei nicht
//   sicher.
// - UnusedBytes nennt den ungenutzten Teil einer Datei (alte Verzeichnisse und Reste abgebrochener Ergänzungen); der
//   Index-Dienst schreibt sie am Ende eines Aufbaus ganz neu, wenn er zu groß ist.

interface

uses
  System.SysUtils,
  System.Classes,
  dpcc.Common.Index.Contract;

type
  /// <summary>Unit aus einem geladenen Cache: Kopf und Katalog aus dem Verzeichnis, die Symbole liest
  /// TIndexCache.Expand bei Bedarf aus dem Block (Source).</summary>
  TIndexCacheEntry = record
    /// <summary>Kopf aus dem Verzeichnis: Name, Datei, Stand, Merker, uses und Include-Dateien; ohne Symbole.
    /// </summary>
    Header: TUnitIndex;
    /// <summary>Header ist schon vollständig (aus einem TUnitIndex übernommen).</summary>
    Expanded: Boolean;
    /// <summary>Katalog der Unit aus dem Verzeichnis (Speicher-Optimierung Phase 3).</summary>
    Catalog: TCatalogUnit;
    /// <summary>Block der Unit in der Cache-Datei; nil bei Expanded.</summary>
    Source: IIndexUnitSource;
    SymbolCount: Integer;
    UnavailableCount: Integer;
    UsageCount: Integer;
    class function FromUnit(const AUnit: TUnitIndex): TIndexCacheEntry; static;
  end;

  /// <summary>Eine Unit für TIndexCache.Write: aus dem Speicher (Header mit Symbolen) oder als unveränderter Block
  /// aus einem anderen Cache (Source).</summary>
  TIndexCacheItem = record
    /// <summary>Ohne Source die ganze Unit, sonst ihr Kopf für das Verzeichnis.</summary>
    Header: TUnitIndex;
    Catalog: TCatalogUnit;
    Source: IIndexUnitSource;
    SymbolCount: Integer;
    UnavailableCount: Integer;
    UsageCount: Integer;
    /// <summary>Unit aus dem Speicher; der Katalog entsteht aus ihren Symbolen.</summary>
    class function OfUnit(const AUnit: TUnitIndex): TIndexCacheItem; static;
    /// <summary>Unit aus einem gelesenen Cache: ihr Block wird kopiert (ohne Source wie OfUnit).</summary>
    class function OfEntry(const AEntry: TIndexCacheEntry): TIndexCacheItem; static;
  end;

  /// <summary>Lage eines Blocks in der geschriebenen Datei (Phase 4); Written = False, wenn die Unit fehlt (alter
  /// Block unlesbar).</summary>
  TIndexBlockPlace = record
    Offset: Int64;
    Length: Integer;
    Checksum: Cardinal;
    Written: Boolean;
  end;

  /// <summary>Steht der Block von ASource schon in der Datei, die gerade ergänzt wird (TIndexCache.Append)?</summary>
  TIndexBlockInFile = reference to function(const ASource: IIndexUnitSource): Boolean;

  TIndexCache = class
  public
    // 13: Mitglieder aus nicht geltenden Zweigen in Unavailable (#476).
    // 14: dazu Routinen aus nicht geltenden Zweigen im implementation-Teil.
    // 15: Zusammenführung mit der Kette (Signatur, Direktiven, Kurztext je Symbol, #492).
    // 16: Zählung der Präfixe je Unit (#452).
    // 17: Grund hinter deprecated je Symbol (#38).
    // 18: Zweig varianter Record-Felder je Symbol (#846).
    // 19: Direktive class an Klassenmitgliedern (#1001).
    // 20: Verweise der Rümpfe von inline-Routinen (#1017).
    // 21: Hinweise im Unit-Kopf samt Grund hinter deprecated (#1018).
    // 22: Typparameter ohne die Typen aus Einschränkungen (<T: class, TBasis>, #1029).
    // 23: Unit-Name zählt nicht mehr als Hinweis im Unit-Kopf (dpcc.Settings.Experimental, #1018);
    // Feld Operator: string ist keine Routine mehr.
    // 24: Helfer mit Vorfahr (class helper (TBase) for T, #848), {$SCOPEDENUMS ON} je Aufzählung und Wert und
    // Mitglieder aus {$I} im Klassenrumpf (#849), Routinen hinter asm-Blöcken mit @@End (#861), Konstanten
    // hinter Steuerzeichen wie ^C (#862). Die Kette #847–#862 zählte getrennt 19–22.
    // 25: Methodenzuordnungen IFoo.Bar=Baz je Klasse statt als Mitglied (#849 mit #1000 und #1040).
    // 26: Namen ohne Escape-& (&begin → begin, &&op_Equality → &op_Equality, #1137).
    // 27: type AnsiString(Codepage) ohne Zieltyp, RawByteString/UTF8String bleiben eigene Typen (#1140).
    // 28: Begründungen (// WHY: …) je Symbol und Unit (#1123).
    // 29: Prozedurtypen über mehrere Zeilen vollständig, Merkmal "of object"/"reference to" in Directives (#1326).
    // 30: inline-Routinen ohne Verweise tragen InlineWithoutRefs statt nil (#1381).
    // 31: Typargumente je Vorfahr statt nur des ersten (class(TInterfacedObject, IComparer<TKunde>)).
    // 32: Hinweiswort vor dem Startwert (NoErrMsg: Boolean platform = False); ohne neue Version blieb System.pas
    // aus dem alten Index ohne NoErrMsg (unresolved-identifier).
    // 33: Folgemuster der Projekt-Units im Kopf (#1890, gelernte Vorschläge).
    // 34: Blöcke je Unit mit eigener String-Tabelle und Prüfsumme, Verzeichnis mit Katalog am Ende
    // (Speicher-Optimierung Phase 3).
    const cFormatVersion = 35;
    /// <summary>Ganzer Cache im Speicher (Tests); im Betrieb schreibt Write in einen Strom.</summary>
    class function Serialize(const AUnits: TArray<TUnitIndex>): TBytes; static;
    /// <summary>Schreibt AItems als Cache an die aktuelle Stelle von AStream. Liefert die Zahl geschriebener Units;
    /// eine Unit, deren alter Block sich nicht lesen lässt, fehlt (der nächste Aufbau liest sie neu).</summary>
    class function Write(AStream: TStream; const AItems: TArray<TIndexCacheItem>): Integer; overload; static;
    /// <summary>Wie oben; APlaces nennt je Eintrag von AItems die Lage seines Blocks (Phase 4).</summary>
    class function Write(AStream: TStream; const AItems: TArray<TIndexCacheItem>;
      out APlaces: TArray<TIndexBlockPlace>): Integer; overload; static;
    /// <summary>Ergänzt den Cache in AStream (die ganze bestehende Datei) an Ort und Stelle (Phase 4): Units, deren
    /// Block laut AInFile schon in der Datei steht, bleiben dort; die übrigen kommen ans Ende, dahinter ein neues
    /// Verzeichnis aller AItems, zuletzt der Kopf. -1, wenn AStream kein Cache dieses Formats ist (dann nichts
    /// geschrieben); sonst die Zahl der Units im neuen Verzeichnis.</summary>
    class function Append(AStream: TStream; const AItems: TArray<TIndexCacheItem>; const AInFile: TIndexBlockInFile;
      out APlaces: TArray<TIndexBlockPlace>): Integer; overload; static;
    /// <summary>Wie oben, aber nur, wenn AStream dieselbe Datei ist, die AKnown gelesen hat: gleiche Größe und gleicher
    /// Kopf (Phase 5); sonst -1 ohne zu schreiben. AKnown = nil prüft nicht.</summary>
    class function Append(AStream: TStream; const AItems: TArray<TIndexCacheItem>; const AInFile: TIndexBlockInFile;
      const AKnown: IIndexBlockReader; out APlaces: TArray<TIndexBlockPlace>): Integer; overload; static;
    /// <summary>Ungenutzte Bytes der über AReader geöffneten Datei (Phase 5): Größe ohne Kopf, Verzeichnis und die
    /// ABlockBytes der Blöcke, auf die das Verzeichnis verweist. 0, wenn AReader kein Cache dieses Formats ist.
    /// </summary>
    class function UnusedBytes(const AReader: IIndexBlockReader; ABlockBytes: Int64): Int64; static;
    /// <summary>Block an APlace der über AReader geöffneten Datei (nach Write oder Append).</summary>
    class function SourceAt(const AReader: IIndexBlockReader; const APlace: TIndexBlockPlace): IIndexUnitSource;
      static;
    /// <summary>Datei, aus der ASource liest; nil, wenn ASource kein Block eines Caches ist.</summary>
    class function ReaderOf(const ASource: IIndexUnitSource): IIndexBlockReader; static;
    /// <summary>Dekodiert die Unit aus ASource; ohne AUsages werden die Verwendungen nur überlesen (Phase 4).</summary>
    class function LoadFrom(const ASource: IIndexUnitSource; out AUnit: TUnitIndex; AUsages: Boolean): Boolean;
      static;
    /// <summary>Liest Kopf und Verzeichnis; bei falscher Version, falscher Prüfsumme oder fremdem Inhalt leer.
    /// </summary>
    class function ReadEntries(const AData: TBytes): TArray<TIndexCacheEntry>; overload; static;
    /// <summary>Wie oben; AReason nennt bei leerem Ergebnis den Grund ('' = gültig oder leer).</summary>
    class function ReadEntries(const AData: TBytes; out AReason: string): TArray<TIndexCacheEntry>; overload;
      static;
    /// <summary>Wie oben über einen Blockleser: liest nur Kopf und Verzeichnis, die Einträge lesen ihre Blöcke
    /// später über AReader. nil = kein Cache.</summary>
    class function ReadEntries(const AReader: IIndexBlockReader; out AReason: string): TArray<TIndexCacheEntry>;
      overload; static;
    /// <summary>Wie oben; ohne ACatalog bleibt der Katalog der Einträge leer (nur Kopf und Block, etwa um den Units
    /// des Index die Blöcke einer neuen Datei zuzuweisen): Seine Texte werden dann nicht dekodiert.</summary>
    class function ReadEntries(const AReader: IIndexBlockReader; out AReason: string;
      ACatalog: Boolean): TArray<TIndexCacheEntry>; overload; static;
    /// <summary>Unit mit Symbolen und (AUsages) Verwendungen; False, wenn ihr Block beschädigt ist.
    /// Ohne AUsages bleiben die Verwendungen auf der Platte: UsagesOffloaded ist dann gesetzt.</summary>
    class function Expand(const AEntry: TIndexCacheEntry; out AUnit: TUnitIndex;
      AUsages: Boolean): Boolean; overload; static;
    /// <summary>Wie oben mit AUsages = True.</summary>
    class function Expand(const AEntry: TIndexCacheEntry; out AUnit: TUnitIndex): Boolean; overload; static;
    /// <summary>Nur die Verwendungen einer Unit (Nachladen ausgelagerter Verwendungen).</summary>
    class function ExpandUsages(const AEntry: TIndexCacheEntry; out AUsages: TArray<TIndexUsage>): Boolean;
      static;
    /// <summary>Liest den ganzen Cache; bei falscher Version, fremdem Inhalt oder einem beschädigten Block leer.
    /// </summary>
    class function Deserialize(const AData: TBytes): TArray<TUnitIndex>; static;
    /// <summary>Hash eines Dateiinhalts.</summary>
    class function HashOf(const AText: string): string; static;
  end;

implementation

uses
  System.Hash,
  System.Generics.Collections,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TCacheText = (IndexCacheDamaged, IndexCacheTooLarge, IndexCacheSizeDiffersFrom, ChecksumDoesNotMatch,
    NoDpccIndexHeaderMissing, ContentDamaged, FormatVersionInsteadOf);

const
  cTexts: array[TCacheText] of TDpccText = (
    (De: 'Index-Cache beschädigt'; En: 'Index cache damaged'),
    (De: 'Index-Cache zu groß'; En: 'Index cache too large'),
    (De: 'Index-Cache: Größe weicht von der Vorabzählung ab'; En: 'Index cache: size differs from the pre-count'),
    (De: 'Prüfsumme stimmt nicht'; En: 'Checksum does not match'),
    (De: 'kein dpcc-Index (Kopf fehlt)'; En: 'no dpcc index (header missing)'),
    (De: 'Inhalt beschädigt'; En: 'content damaged'),
    (De: 'Formatversion %d statt %d'; En: 'Format version %d instead of %d'));

const
  // Kopf seit S5 'DPCCINDX' (gleiche Länge wie der frühere): Ein Cache mit anderem Kopf gilt als fremd, ReadEntries
  // liefert leer und der Index wird ohne Meldung neu aufgebaut.
  cMagic: array[0..7] of Byte = (Ord('D'), Ord('P'), Ord('C'), Ord('C'), Ord('I'), Ord('N'), Ord('D'), Ord('X'));
  cFlagLibrary = 1;
  cFlagCompact = 2;
  cFlagInitialization = 4;
  cFlagUsages = 8;
  // Magic, Version (1 Byte), Verzeichnis-Offset (8), -Länge (4) und -Prüfsumme (4).
  cVersionAt = 8;
  cDirectoryAt = 9;
  cHeadSize = 25;
  cSymbolInInterface = 1;
  cSymbolDefault = 2;
  cSymbolVirtual = 4;
  cSymbolUnavailable = 8;
  cSymbolScopedEnum = 16;
  /// <summary>Größter Block bzw. größtes Verzeichnis, das der Leser annimmt.</summary>
  cMaxSection = 512 * 1024 * 1024;

type
  ECacheFormat = class(Exception);

  /// <summary>Wachsender Bytepuffer; Clear behält die Kapazität für den nächsten Block.</summary>
  TCacheWriter = class
  private
    FData: TBytes;
    FLength: Integer;
    procedure Grow(ACount: Integer);
  public
    constructor Create(ACapacity: Integer);
    procedure Clear;
    procedure WriteByte(AValue: Byte);
    procedure WriteBytes(const AValue: TBytes; AIndex, ACount: Integer);
    procedure WriteVar(AValue: UInt64);
    procedure WriteInt(AValue: Int64);
    property Length_: Integer read FLength;
  end;

  /// <summary>Sammelt beim Schreiben die String-Tabelle eines Blocks bzw. des Verzeichnisses.</summary>
  TStringTable = class
  private
    FIndex: TDictionary<string, Integer>;
    FItems: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function IndexOf(const AValue: string): Integer;
    property Items: TList<string> read FItems;
  end;

  /// <summary>String-Tabelle eines gelesenen Blocks: dekodiert jeden Text erst beim ersten Lesen, als string oder
  /// (Signaturen) als UTF-8, und teilt ihn dann innerhalb des Blocks.</summary>
  TCacheStrings = class
  private
    FData: TBytes;
    FOffsets: TArray<Integer>;
    FSizes: TArray<Integer>;
    FTexts: TArray<string>;
    FTextDone: TArray<Boolean>;
    FUtf8: TArray<UTF8String>;
    FUtf8Done: TArray<Boolean>;
  public
    function Count: Integer;
    function Text(AIndex: Integer): string;
    function Utf8(AIndex: Integer): UTF8String;
  end;

  /// <summary>Liest Werte aus einem Bytepuffer; jede Überschreitung löst ECacheFormat aus.</summary>
  TCacheReader = record
    Data: TBytes;
    Position: Integer;
    Limit: Integer;
    Strings: TCacheStrings;
    function ReadByte: Byte;
    function ReadVar: UInt64;
    function ReadCount: Integer;
    /// <summary>Nicht negative Zahl bis High(Integer), unabhängig von der Dateigröße.</summary>
    function ReadNumber: Integer;
    function ReadInt: Int64;
    function ReadInt32: Integer;
    function ReadString: string;
    /// <summary>Überliest die Nummer eines Textes; prüft wie ReadString, dass es ihn gibt, ohne ihn zu dekodieren
    /// (Phase 5).</summary>
    procedure SkipString;
    /// <summary>Wie SkipString; ein leerer Text gilt wie in ReadUnitStart als beschädigt (Dateiname einer Unit).
    /// </summary>
    procedure SkipFileName;
    function ReadList: TArray<string>;
    /// <summary>Signatur als UTF-8 (ohne UTF-16-Fassung).</summary>
    function ReadSignature: UTF8String;
    /// <summary>Liest die String-Tabelle an der aktuellen Stelle; der Aufrufer gibt Strings frei.</summary>
    procedure ReadTable;
  end;

  /// <summary>Block einer Unit in einer Cache-Datei.</summary>
  TCacheBlockSource = class(TInterfacedObject, IIndexUnitSource)
  private
    FReader: IIndexBlockReader;
    FOffset: Int64;
    FLength: Integer;
    FChecksum: Cardinal;
  public
    constructor Create(const AReader: IIndexBlockReader; AOffset: Int64; ALength: Integer; AChecksum: Cardinal);
    function Load(out AUnit: TUnitIndex): Boolean;
    /// <summary>Wie Load; ohne AUsages bleiben die Verwendungen ungelesen (Phase 4).</summary>
    function LoadPart(out AUnit: TUnitIndex; AUsages: Boolean): Boolean;
    /// <summary>Nur die Verwendungen; Kopf und Symbole werden überlesen (Phase 4).</summary>
    function LoadUsages(out AUsages: TArray<TIndexUsage>): Boolean;
    function ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
    function BlockSize: Integer;
  end;

procedure Fail;
begin
  raise ECacheFormat.Create(cTexts[TCacheText.IndexCacheDamaged].Text);
end;

/// <summary>FNV-1a (32 Bit) über AData[AFrom..ATo-1], fortgesetzt ab ASeed.</summary>
function ChecksumAdd(ASeed: Cardinal; const AData: TBytes; AFrom, ATo: Integer): Cardinal;
var
  mIndex: Integer;
begin
  Result := ASeed;
  for mIndex := AFrom to ATo - 1 do
  begin
    Result := Cardinal(UInt64(Result xor AData[mIndex]) * 16777619);
  end;
end;

const
  cChecksumSeed = 2166136261;

/// <summary>FNV-1a (32 Bit) über AData ab AFrom.</summary>
function ChecksumOf(const AData: TBytes; AFrom, ATo: Integer): Cardinal;
begin
  Result := ChecksumAdd(cChecksumSeed, AData, AFrom, ATo);
end;

{ TCacheWriter }

constructor TCacheWriter.Create(ACapacity: Integer);
begin
  inherited Create;
  SetLength(FData, ACapacity);
end;

procedure TCacheWriter.Clear;
begin
  FLength := 0;
end;

procedure TCacheWriter.Grow(ACount: Integer);
var
  mNeeded, mCapacity: Integer;
begin
  mNeeded := FLength + ACount;
  mCapacity := Length(FData);
  if mNeeded <= mCapacity then
  begin
    Exit;
  end;
  if mCapacity < 1024 then
  begin
    mCapacity := 1024;
  end;
  // Bis 4 MB verdoppeln, darüber um ein Viertel (L2): Beim Umkopieren liegen alter und neuer Puffer zugleich im
  // Speicher; bei Blöcken großer Units (Office-Typbibliotheken, bis rund 16 MB) waren das bis zum Dreifachen.
  while mCapacity < mNeeded do
  begin
    if mCapacity < 4 * 1024 * 1024 then
    begin
      mCapacity := mCapacity * 2;
    end
    else
    begin
      mCapacity := mCapacity + mCapacity div 4;
    end;
  end;
  SetLength(FData, mCapacity);
end;

procedure TCacheWriter.WriteByte(AValue: Byte);
begin
  Grow(1);
  FData[FLength] := AValue;
  Inc(FLength);
end;

procedure TCacheWriter.WriteBytes(const AValue: TBytes; AIndex, ACount: Integer);
begin
  if ACount <= 0 then
  begin
    Exit;
  end;
  Grow(ACount);
  Move(AValue[AIndex], FData[FLength], ACount);
  Inc(FLength, ACount);
end;

procedure TCacheWriter.WriteVar(AValue: UInt64);
begin
  while AValue >= $80 do
  begin
    WriteByte(Byte(AValue and $7F) or $80);
    AValue := AValue shr 7;
  end;
  WriteByte(Byte(AValue));
end;

procedure TCacheWriter.WriteInt(AValue: Int64);
var
  mEncoded: UInt64;
begin
  // ZigZag: kleine negative Zahlen (-1) bleiben kurz.
  if AValue < 0 then
  begin
    mEncoded := (UInt64(not AValue) shl 1) or 1;
  end
  else
  begin
    mEncoded := UInt64(AValue) shl 1;
  end;
  WriteVar(mEncoded);
end;

{ TStringTable }

constructor TStringTable.Create;
begin
  inherited Create;
  FIndex := TDictionary<string, Integer>.Create;
  FItems := TList<string>.Create;
  IndexOf('');
end;

destructor TStringTable.Destroy;
begin
  FItems.Free;
  FIndex.Free;
  inherited;
end;

procedure TStringTable.Clear;
begin
  FIndex.Clear;
  FItems.Clear;
  IndexOf('');
end;

function TStringTable.IndexOf(const AValue: string): Integer;
begin
  if FIndex.TryGetValue(AValue, Result) then
  begin
    Exit;
  end;
  Result := FItems.Add(AValue);
  FIndex.Add(AValue, Result);
end;

{ TCacheStrings }

function TCacheStrings.Count: Integer;
begin
  Result := Length(FOffsets);
end;

function TCacheStrings.Text(AIndex: Integer): string;
begin
  if not FTextDone[AIndex] then
  begin
    if FSizes[AIndex] > 0 then
    begin
      FTexts[AIndex] := TEncoding.UTF8.GetString(FData, FOffsets[AIndex], FSizes[AIndex]);
    end;
    FTextDone[AIndex] := True;
  end;
  Result := FTexts[AIndex];
end;

function TCacheStrings.Utf8(AIndex: Integer): UTF8String;
begin
  if not FUtf8Done[AIndex] then
  begin
    if FSizes[AIndex] > 0 then
    begin
      SetLength(FUtf8[AIndex], FSizes[AIndex]);
      Move(FData[FOffsets[AIndex]], PAnsiChar(FUtf8[AIndex])^, FSizes[AIndex]);
    end;
    FUtf8Done[AIndex] := True;
  end;
  Result := FUtf8[AIndex];
end;

{ TCacheReader }

function TCacheReader.ReadByte: Byte;
begin
  if Position >= Limit then
  begin
    Fail;
  end;
  Result := Data[Position];
  Inc(Position);
end;

function TCacheReader.ReadVar: UInt64;
var
  mShift: Integer;
  mValue: Byte;
begin
  Result := 0;
  mShift := 0;
  repeat
    if mShift > 63 then
    begin
      Fail;
    end;
    mValue := ReadByte;
    Result := Result or (UInt64(mValue and $7F) shl mShift);
    Inc(mShift, 7);
  until mValue < $80;
end;

function TCacheReader.ReadNumber: Integer;
var
  mValue: UInt64;
begin
  mValue := ReadVar;
  if mValue > UInt64(High(Integer)) then
  begin
    Fail;
  end;
  Result := Integer(mValue);
end;

function TCacheReader.ReadCount: Integer;
var
  mValue: UInt64;
begin
  mValue := ReadVar;
  // Mehr Einträge als Bytes kann es nicht geben.
  if mValue > UInt64(Limit) then
  begin
    Fail;
  end;
  Result := Integer(mValue);
end;

function TCacheReader.ReadInt: Int64;
var
  mValue: UInt64;
begin
  mValue := ReadVar;
  if (mValue and 1) <> 0 then
  begin
    Result := not Int64(mValue shr 1);
  end
  else
  begin
    Result := Int64(mValue shr 1);
  end;
end;

function TCacheReader.ReadInt32: Integer;
var
  mValue: Int64;
begin
  mValue := ReadInt;
  if (mValue < Low(Integer)) or (mValue > High(Integer)) then
  begin
    Fail;
  end;
  Result := Integer(mValue);
end;

function TCacheReader.ReadString: string;
var
  mIndex: UInt64;
begin
  mIndex := ReadVar;
  if mIndex >= UInt64(Strings.Count) then
  begin
    Fail;
  end;
  Result := Strings.Text(Integer(mIndex));
end;

procedure TCacheReader.SkipString;
begin
  if ReadVar >= UInt64(Strings.Count) then
  begin
    Fail;
  end;
end;

procedure TCacheReader.SkipFileName;
var
  mIndex: UInt64;
begin
  mIndex := ReadVar;
  // Leer heißt Länge 0 (Nummer 0 ist immer ''); dekodiert wird nichts.
  if (mIndex >= UInt64(Strings.Count)) or (Strings.FSizes[Integer(mIndex)] = 0) then
  begin
    Fail;
  end;
end;

function TCacheReader.ReadSignature: UTF8String;
var
  mIndex: UInt64;
begin
  mIndex := ReadVar;
  if mIndex >= UInt64(Strings.Count) then
  begin
    Fail;
  end;
  if mIndex = 0 then
  begin
    Exit('');
  end;
  Result := Strings.Utf8(Integer(mIndex));
end;

function TCacheReader.ReadList: TArray<string>;
var
  mIndex, mCount: Integer;
begin
  mCount := ReadCount;
  SetLength(Result, mCount);
  for mIndex := 0 to mCount - 1 do
  begin
    Result[mIndex] := ReadString;
  end;
end;

procedure TCacheReader.ReadTable;
var
  mIndex, mSize: Integer;
begin
  Strings := TCacheStrings.Create;
  Strings.FData := Data;
  SetLength(Strings.FOffsets, ReadCount);
  SetLength(Strings.FSizes, Length(Strings.FOffsets));
  SetLength(Strings.FTexts, Length(Strings.FOffsets));
  SetLength(Strings.FTextDone, Length(Strings.FOffsets));
  SetLength(Strings.FUtf8, Length(Strings.FOffsets));
  SetLength(Strings.FUtf8Done, Length(Strings.FOffsets));
  for mIndex := 0 to High(Strings.FOffsets) do
  begin
    mSize := ReadCount;
    if Position + mSize > Limit then
    begin
      Fail;
    end;
    Strings.FSizes[mIndex] := mSize;
    Strings.FOffsets[mIndex] := Position;
    Inc(Position, mSize);
  end;
end;

{ TIndexCacheEntry }

class function TIndexCacheEntry.FromUnit(const AUnit: TUnitIndex): TIndexCacheEntry;
begin
  Result := Default(TIndexCacheEntry);
  Result.Header := AUnit;
  Result.Expanded := True;
  Result.Catalog := TCatalogUnit.FromUnit(AUnit);
  Result.SymbolCount := Length(AUnit.Symbols);
  Result.UnavailableCount := Length(AUnit.Unavailable);
  Result.UsageCount := Length(AUnit.Usages);
end;

{ TIndexCacheItem }

class function TIndexCacheItem.OfUnit(const AUnit: TUnitIndex): TIndexCacheItem;
begin
  Result := Default(TIndexCacheItem);
  Result.Header := AUnit;
  Result.Catalog := TCatalogUnit.FromUnit(AUnit);
  Result.SymbolCount := Length(AUnit.Symbols);
  Result.UnavailableCount := Length(AUnit.Unavailable);
  Result.UsageCount := Length(AUnit.Usages);
end;

class function TIndexCacheItem.OfEntry(const AEntry: TIndexCacheEntry): TIndexCacheItem;
begin
  if AEntry.Expanded or (AEntry.Source = nil) then
  begin
    Exit(OfUnit(AEntry.Header));
  end;
  Result := Default(TIndexCacheItem);
  Result.Header := AEntry.Header;
  Result.Catalog := AEntry.Catalog;
  Result.Source := AEntry.Source;
  Result.SymbolCount := AEntry.SymbolCount;
  Result.UnavailableCount := AEntry.UnavailableCount;
  Result.UsageCount := AEntry.UsageCount;
end;

{ Schreiben }

procedure WriteList(AWriter: TCacheWriter; ATable: TStringTable; const AValues: TArray<string>);
var
  mValue: string;
begin
  AWriter.WriteVar(Length(AValues));
  for mValue in AValues do
  begin
    AWriter.WriteVar(ATable.IndexOf(mValue));
  end;
end;

procedure WriteSymbol(AWriter: TCacheWriter; ATable: TStringTable; const ASymbol: TIndexSymbol);
var
  mFlags: Integer;
begin
  AWriter.WriteVar(ATable.IndexOf(ASymbol.Name));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.Container));
  AWriter.WriteVar(Ord(ASymbol.Kind));
  AWriter.WriteInt(ASymbol.Range.StartPos.Line);
  AWriter.WriteInt(ASymbol.Range.StartPos.Character);
  AWriter.WriteInt(ASymbol.Range.EndPos.Line);
  AWriter.WriteInt(ASymbol.Range.EndPos.Character);
  AWriter.WriteInt(ASymbol.SelectionRange.StartPos.Line);
  AWriter.WriteInt(ASymbol.SelectionRange.StartPos.Character);
  AWriter.WriteInt(ASymbol.SelectionRange.EndPos.Line);
  AWriter.WriteInt(ASymbol.SelectionRange.EndPos.Character);
  mFlags := 0;
  if ASymbol.InInterface then
  begin
    mFlags := mFlags or cSymbolInInterface;
  end;
  if ASymbol.IsDefault then
  begin
    mFlags := mFlags or cSymbolDefault;
  end;
  if ASymbol.IsVirtual then
  begin
    mFlags := mFlags or cSymbolVirtual;
  end;
  if ASymbol.Unavailable then
  begin
    mFlags := mFlags or cSymbolUnavailable;
  end;
  if ASymbol.ScopedEnum then
  begin
    mFlags := mFlags or cSymbolScopedEnum;
  end;
  AWriter.WriteVar(mFlags);
  WriteList(AWriter, ATable, ASymbol.Ancestors);
  AWriter.WriteVar(ATable.IndexOf(ASymbol.TypeName));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.TypeArgs));
  WriteList(AWriter, ATable, ASymbol.AncestorArgs);
  AWriter.WriteVar(ATable.IndexOf(ASymbol.TypeParams));
  AWriter.WriteVar(Ord(ASymbol.Visibility));
  AWriter.WriteInt(ASymbol.MinArgs);
  AWriter.WriteInt(ASymbol.MaxArgs);
  WriteList(AWriter, ATable, ASymbol.ParamTypes);
  AWriter.WriteVar(ATable.IndexOf(ASymbol.FileName));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.Condition));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.Signature));
  WriteList(AWriter, ATable, ASymbol.Directives);
  AWriter.WriteVar(ATable.IndexOf(ASymbol.DeprecatedText));
  AWriter.WriteVar(ATable.IndexOf(ASymbol.VariantBranch));
  WriteList(AWriter, ATable, ASymbol.InlineRefs);
  WriteList(AWriter, ATable, ASymbol.Resolutions);
  WriteList(AWriter, ATable, ASymbol.Rationale);
end;

procedure WriteUsage(AWriter: TCacheWriter; ATable: TStringTable; const AUsage: TIndexUsage);
var
  mPosition: TTextPosition;
  mLine: Integer;
begin
  AWriter.WriteVar(ATable.IndexOf(AUsage.Name));
  AWriter.WriteVar(Length(AUsage.Positions));
  // Zeilen als Abstand zur vorigen Stelle: meist 0 oder klein.
  mLine := 0;
  for mPosition in AUsage.Positions do
  begin
    AWriter.WriteInt(mPosition.Line - mLine);
    AWriter.WriteVar(Cardinal(mPosition.Character));
    mLine := mPosition.Line;
  end;
end;

function UnitFlags(const AUnit: TUnitIndex): Integer;
begin
  Result := 0;
  if AUnit.Library_ then
  begin
    Result := Result or cFlagLibrary;
  end;
  if AUnit.Compact then
  begin
    Result := Result or cFlagCompact;
  end;
  if AUnit.HasInitialization then
  begin
    Result := Result or cFlagInitialization;
  end;
  if AUnit.UsagesIndexed then
  begin
    Result := Result or cFlagUsages;
  end;
end;

/// <summary>Folgemuster einer Unit (#1890): Trigger, Folge, Anzahl und Belegzeilen.</summary>
procedure WritePatterns(AWriter: TCacheWriter; ATable: TStringTable; const APatterns: TArray<TIndexFollowPattern>);
var
  mPattern: TIndexFollowPattern;
  mLine: Integer;
begin
  AWriter.WriteVar(Length(APatterns));
  for mPattern in APatterns do
  begin
    AWriter.WriteVar(ATable.IndexOf(mPattern.Trigger));
    AWriter.WriteVar(ATable.IndexOf(mPattern.Follow));
    AWriter.WriteVar(mPattern.Count);
    AWriter.WriteVar(Length(mPattern.Lines));
    for mLine in mPattern.Lines do
    begin
      AWriter.WriteVar(mLine);
    end;
  end;
end;

/// <summary>Name bis Include-Zeitstempel: der Teil des Kopfes, den Block und Verzeichnis gemeinsam haben.</summary>
procedure WriteUnitStart(AWriter: TCacheWriter; ATable: TStringTable; const AUnit: TUnitIndex);
var
  mStamp: Int64;
begin
  AWriter.WriteVar(ATable.IndexOf(AUnit.UnitName));
  AWriter.WriteVar(ATable.IndexOf(AUnit.FileName));
  AWriter.WriteInt(AUnit.Stamp);
  AWriter.WriteVar(ATable.IndexOf(AUnit.Hash));
  AWriter.WriteVar(UnitFlags(AUnit));
  WriteList(AWriter, ATable, AUnit.InterfaceUses);
  WriteList(AWriter, ATable, AUnit.ImplementationUses);
  WriteList(AWriter, ATable, AUnit.Includes);
  AWriter.WriteVar(Length(AUnit.IncludeStamps));
  for mStamp in AUnit.IncludeStamps do
  begin
    AWriter.WriteInt(mStamp);
  end;
end;

/// <summary>Kopf einer Unit: Namen, Stempel, Flags, uses, Includes, Namenszählung, Hinweise und Folgemuster.
/// </summary>
procedure WriteUnitHeader(AWriter: TCacheWriter; ATable: TStringTable; const AUnit: TUnitIndex);
var
  mKind: TNamingKind;
begin
  WriteUnitStart(AWriter, ATable, AUnit);
  for mKind := Low(TNamingKind) to High(TNamingKind) do
  begin
    AWriter.WriteVar(AUnit.Naming[mKind].Total);
    AWriter.WriteVar(AUnit.Naming[mKind].Prefixed);
  end;
  WriteList(AWriter, ATable, AUnit.Directives);
  AWriter.WriteVar(ATable.IndexOf(AUnit.DeprecatedText));
  WriteList(AWriter, ATable, AUnit.Rationale);
  WritePatterns(AWriter, ATable, AUnit.Patterns);
  WriteList(AWriter, ATable, AUnit.Requires);
end;

/// <summary>Inhalt eines Blocks ohne seine String-Tabelle: Kopf, Symbole, nicht geltende Deklarationen,
/// Verwendungen.</summary>
procedure WriteBlockContent(AWriter: TCacheWriter; ATable: TStringTable; const AUnit: TUnitIndex);
var
  mIndex: Integer;
begin
  WriteUnitHeader(AWriter, ATable, AUnit);
  AWriter.WriteVar(Length(AUnit.Symbols));
  AWriter.WriteVar(Length(AUnit.Unavailable));
  // Über den Index: die Symbol-Records nicht kopieren.
  for mIndex := 0 to High(AUnit.Symbols) do
  begin
    WriteSymbol(AWriter, ATable, AUnit.Symbols[mIndex]);
  end;
  for mIndex := 0 to High(AUnit.Unavailable) do
  begin
    WriteSymbol(AWriter, ATable, AUnit.Unavailable[mIndex]);
  end;
  AWriter.WriteVar(Length(AUnit.Usages));
  for mIndex := 0 to High(AUnit.Usages) do
  begin
    WriteUsage(AWriter, ATable, AUnit.Usages[mIndex]);
  end;
end;

/// <summary>String-Tabelle: Anzahl, je Text Bytelänge und UTF-8-Bytes.</summary>
procedure WriteTable(AWriter: TCacheWriter; ATable: TStringTable);
var
  mValue: string;
  mBytes: TBytes;
begin
  AWriter.WriteVar(ATable.Items.Count);
  for mValue in ATable.Items do
  begin
    mBytes := TEncoding.UTF8.GetBytes(mValue);
    AWriter.WriteVar(Length(mBytes));
    AWriter.WriteBytes(mBytes, 0, Length(mBytes));
  end;
end;

/// <summary>Katalog einer Unit im Verzeichnis.</summary>
procedure WriteCatalog(AWriter: TCacheWriter; ATable: TStringTable; const ACatalog: TCatalogUnit);
var
  mIndex: Integer;
begin
  AWriter.WriteVar(ACatalog.ExportedTypeCount);
  WriteList(AWriter, ATable, ACatalog.ExportedTypes);
  AWriter.WriteVar(Length(ACatalog.Symbols));
  for mIndex := 0 to High(ACatalog.Symbols) do
  begin
    AWriter.WriteVar(ATable.IndexOf(ACatalog.Symbols[mIndex].Name));
    AWriter.WriteVar(ATable.IndexOf(ACatalog.Symbols[mIndex].TypeName));
    AWriter.WriteVar(Ord(ACatalog.Symbols[mIndex].Kind));
    AWriter.WriteInt(ACatalog.Symbols[mIndex].Start.Line);
    AWriter.WriteInt(ACatalog.Symbols[mIndex].Start.Character);
    AWriter.WriteInt(ACatalog.Symbols[mIndex].MinArgs);
    AWriter.WriteInt(ACatalog.Symbols[mIndex].MaxArgs);
    AWriter.WriteVar(ACatalog.Symbols[mIndex].Flags);
    WriteList(AWriter, ATable, ACatalog.Symbols[mIndex].Ancestors);
  end;
end;

/// <summary>Eintrag einer Unit im Verzeichnis samt Lage ihres Blocks.</summary>
procedure WriteDirectoryEntry(AWriter: TCacheWriter; ATable: TStringTable; const AItem: TIndexCacheItem;
  AOffset: Int64; ALength: Integer; AChecksum: Cardinal);
begin
  WriteUnitStart(AWriter, ATable, AItem.Header);
  AWriter.WriteVar(AItem.SymbolCount);
  AWriter.WriteVar(AItem.UnavailableCount);
  AWriter.WriteVar(AItem.UsageCount);
  WriteCatalog(AWriter, ATable, AItem.Catalog);
  AWriter.WriteVar(UInt64(AOffset));
  AWriter.WriteVar(ALength);
  AWriter.WriteVar(AChecksum);
end;

/// <summary>Schreibt den Puffer in den Strom.</summary>
procedure Emit(AStream: TStream; AWriter: TCacheWriter);
begin
  if AWriter.Length_ > 0 then
  begin
    AStream.WriteBuffer(AWriter.FData[0], AWriter.Length_);
  end;
end;

/// <summary>Zahl in ACount Byte Little Endian an AData[AAt].</summary>
procedure PutFixed(var AData: TBytes; AAt: Integer; AValue: UInt64; ACount: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ACount - 1 do
  begin
    AData[AAt + mIndex] := Byte(AValue shr (8 * mIndex));
  end;
end;

function GetFixed(const AData: TBytes; AAt, ACount: Integer): UInt64;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := ACount - 1 downto 0 do
  begin
    Result := (Result shl 8) or AData[AAt + mIndex];
  end;
end;

/// <summary>Schreibt die Blöcke von AItems ab der aktuellen Stelle von AStream, dahinter das Verzeichnis, und nennt
/// dessen Lage; AStart ist der Anfang der Datei im Strom. Mit AInFile (Ergänzen, Phase 4) bekommen Units, deren Block
/// schon in der Datei steht, nur ihren Verzeichniseintrag.</summary>
function WriteBody(AStream: TStream; AStart: Int64; const AItems: TArray<TIndexCacheItem>;
  const AInFile: TIndexBlockInFile; out APlaces: TArray<TIndexBlockPlace>; out ADirectoryAt: Int64;
  out ADirectoryLength: Integer; out ADirectoryChecksum: Cardinal): Integer;
var
  mOffset: Int64;
  mBlock: TBytes;
  mTable, mDirectoryTable: TStringTable;
  mText, mContent, mDirectory, mDirectoryText: TCacheWriter;
  mIndex: Integer;
  mChecksum: Cardinal;
  mLength: Integer;
  mKept: TCacheBlockSource;
begin
  Result := 0;
  SetLength(APlaces, Length(AItems));
  mTable := TStringTable.Create;
  mDirectoryTable := TStringTable.Create;
  mText := TCacheWriter.Create(64 * 1024);
  mContent := TCacheWriter.Create(256 * 1024);
  mDirectory := TCacheWriter.Create(1024 * 1024);
  mDirectoryText := nil;
  try
    // Über den Index: die Einträge (große Records) nicht kopieren.
    for mIndex := 0 to High(AItems) do
    begin
      APlaces[mIndex] := Default(TIndexBlockPlace);
      mKept := nil;
      if Assigned(AInFile) and (AItems[mIndex].Source <> nil) and (AItems[mIndex].Source is TCacheBlockSource) and
        AInFile(AItems[mIndex].Source) then
      begin
        mKept := AItems[mIndex].Source as TCacheBlockSource;
      end;
      if mKept <> nil then
      begin
        // Ergänzen: Der Block steht schon in dieser Datei und bleibt, wo er ist.
        mOffset := mKept.FOffset;
        mLength := mKept.FLength;
        mChecksum := mKept.FChecksum;
      end
      else if AItems[mIndex].Source <> nil then
      begin
        mOffset := AStream.Position - AStart;
        // Nicht im Speicher: der Block aus dem alten Cache, unverändert. Unlesbar = weglassen.
        if not AItems[mIndex].Source.ReadBlock(mBlock, mChecksum) then
        begin
          Continue;
        end;
        mLength := Length(mBlock);
        if mLength > 0 then
        begin
          AStream.WriteBuffer(mBlock[0], mLength);
        end;
        mBlock := nil;
      end
      else
      begin
        mOffset := AStream.Position - AStart;
        // Inhalt zuerst sammeln: Er vergibt die Nummern der String-Tabelle, die im Block davor steht.
        mTable.Clear;
        mContent.Clear;
        mText.Clear;
        WriteBlockContent(mContent, mTable, AItems[mIndex].Header);
        WriteTable(mText, mTable);
        mChecksum := ChecksumAdd(ChecksumOf(mText.FData, 0, mText.Length_), mContent.FData, 0, mContent.Length_);
        mLength := mText.Length_ + mContent.Length_;
        Emit(AStream, mText);
        Emit(AStream, mContent);
      end;
      WriteDirectoryEntry(mDirectory, mDirectoryTable, AItems[mIndex], mOffset, mLength, mChecksum);
      APlaces[mIndex].Offset := mOffset;
      APlaces[mIndex].Length := mLength;
      APlaces[mIndex].Checksum := mChecksum;
      APlaces[mIndex].Written := True;
      Inc(Result);
    end;
    // Verzeichnis: seine String-Tabelle, dann die Anzahl und die Einträge.
    mDirectoryText := TCacheWriter.Create(1024 * 1024);
    WriteTable(mDirectoryText, mDirectoryTable);
    mDirectoryText.WriteVar(Result);
    ADirectoryChecksum := ChecksumAdd(ChecksumOf(mDirectoryText.FData, 0, mDirectoryText.Length_), mDirectory.FData, 0,
      mDirectory.Length_);
    ADirectoryAt := AStream.Position - AStart;
    ADirectoryLength := mDirectoryText.Length_ + mDirectory.Length_;
    Emit(AStream, mDirectoryText);
    Emit(AStream, mDirectory);
  finally
    mDirectoryText.Free;
    mDirectory.Free;
    mContent.Free;
    mText.Free;
    mDirectoryTable.Free;
    mTable.Free;
  end;
end;

/// <summary>Schreibt den Kopf an AStart: Magic, Version, Lage und Prüfsumme des Verzeichnisses; danach steht der Strom
/// wieder am Ende.</summary>
procedure WriteHead(AStream: TStream; AStart, ADirectoryAt: Int64; ADirectoryLength: Integer;
  ADirectoryChecksum: Cardinal);
var
  mHead: TBytes;
begin
  SetLength(mHead, cHeadSize);
  Move(cMagic[0], mHead[0], Length(cMagic));
  mHead[cVersionAt] := TIndexCache.cFormatVersion;
  PutFixed(mHead, cDirectoryAt, UInt64(ADirectoryAt), 8);
  PutFixed(mHead, cDirectoryAt + 8, Cardinal(ADirectoryLength), 4);
  PutFixed(mHead, cDirectoryAt + 12, ADirectoryChecksum, 4);
  AStream.Position := AStart;
  AStream.WriteBuffer(mHead[0], cHeadSize);
  AStream.Seek(0, soEnd);
end;

class function TIndexCache.Write(AStream: TStream; const AItems: TArray<TIndexCacheItem>): Integer;
var
  mPlaces: TArray<TIndexBlockPlace>;
begin
  Result := Write(AStream, AItems, mPlaces);
end;

class function TIndexCache.Write(AStream: TStream; const AItems: TArray<TIndexCacheItem>;
  out APlaces: TArray<TIndexBlockPlace>): Integer;
var
  mStart, mDirectoryAt: Int64;
  mHead: TBytes;
  mLength: Integer;
  mChecksum: Cardinal;
begin
  mStart := AStream.Position;
  // Platz für den Kopf; Lage und Prüfsumme des Verzeichnisses kommen zuletzt.
  SetLength(mHead, cHeadSize);
  AStream.WriteBuffer(mHead[0], cHeadSize);
  Result := WriteBody(AStream, mStart, AItems, nil, APlaces, mDirectoryAt, mLength, mChecksum);
  WriteHead(AStream, mStart, mDirectoryAt, mLength, mChecksum);
end;

class function TIndexCache.Serialize(const AUnits: TArray<TUnitIndex>): TBytes;
var
  mItems: TArray<TIndexCacheItem>;
  mIndex: Integer;
  mStream: TBytesStream;
begin
  SetLength(mItems, Length(AUnits));
  for mIndex := 0 to High(AUnits) do
  begin
    mItems[mIndex] := TIndexCacheItem.OfUnit(AUnits[mIndex]);
  end;
  mStream := TBytesStream.Create;
  try
    Write(mStream, mItems);
    Result := Copy(mStream.Bytes, 0, mStream.Size);
  finally
    mStream.Free;
  end;
end;

{ Lesen }

/// <summary>Parameterzahl (TIndexSymbol.MinArgs/MaxArgs, SmallInt); außerhalb gilt der Block als beschädigt.</summary>
function ReadArgCount(var AReader: TCacheReader): SmallInt;
var
  mValue: Integer;
begin
  mValue := AReader.ReadInt32;
  if (mValue < Low(SmallInt)) or (mValue > High(SmallInt)) then
  begin
    Fail;
  end;
  Result := mValue;
end;

function ReadKind(var AReader: TCacheReader): TIndexSymbolKind;
var
  mKind: UInt64;
begin
  mKind := AReader.ReadVar;
  if mKind > UInt64(Ord(High(TIndexSymbolKind))) then
  begin
    Fail;
  end;
  Result := TIndexSymbolKind(Integer(mKind));
end;

function ReadSymbol(var AReader: TCacheReader): TIndexSymbol;
var
  mVisibility: UInt64;
  mFlags: Integer;
  mL1, mC1, mL2, mC2: Integer;
begin
  Result := Default(TIndexSymbol);
  Result.Name := AReader.ReadString;
  Result.Container := AReader.ReadString;
  Result.Kind := ReadKind(AReader);
  mL1 := AReader.ReadInt32;
  mC1 := AReader.ReadInt32;
  mL2 := AReader.ReadInt32;
  mC2 := AReader.ReadInt32;
  Result.Range := TTextRange.Create(TTextPosition.Create(mL1, mC1), TTextPosition.Create(mL2, mC2));
  mL1 := AReader.ReadInt32;
  mC1 := AReader.ReadInt32;
  mL2 := AReader.ReadInt32;
  mC2 := AReader.ReadInt32;
  Result.SelectionRange := TTextRange.Create(TTextPosition.Create(mL1, mC1), TTextPosition.Create(mL2, mC2));
  mFlags := AReader.ReadCount;
  Result.InInterface := (mFlags and cSymbolInInterface) <> 0;
  Result.IsDefault := (mFlags and cSymbolDefault) <> 0;
  Result.IsVirtual := (mFlags and cSymbolVirtual) <> 0;
  Result.Unavailable := (mFlags and cSymbolUnavailable) <> 0;
  Result.ScopedEnum := (mFlags and cSymbolScopedEnum) <> 0;
  Result.Ancestors := AReader.ReadList;
  Result.TypeName := AReader.ReadString;
  Result.TypeArgs := AReader.ReadString;
  Result.AncestorArgs := AReader.ReadList;
  Result.TypeParams := AReader.ReadString;
  mVisibility := AReader.ReadVar;
  if mVisibility > UInt64(Ord(High(TIndexVisibility))) then
  begin
    Fail;
  end;
  Result.Visibility := TIndexVisibility(Integer(mVisibility));
  Result.MinArgs := ReadArgCount(AReader);
  Result.MaxArgs := ReadArgCount(AReader);
  Result.ParamTypes := AReader.ReadList;
  Result.FileName := AReader.ReadString;
  Result.Condition := AReader.ReadString;
  Result.SignatureUtf8 := AReader.ReadSignature;
  Result.Directives := AReader.ReadList;
  Result.DeprecatedText := AReader.ReadString;
  Result.VariantBranch := AReader.ReadString;
  Result.InlineRefs := AReader.ReadList;
  Result.Resolutions := AReader.ReadList;
  Result.Rationale := AReader.ReadList;
end;

function ReadUsage(var AReader: TCacheReader): TIndexUsage;
var
  mIndex, mLine: Integer;
begin
  Result.Name := AReader.ReadString;
  SetLength(Result.Positions, AReader.ReadCount);
  mLine := 0;
  for mIndex := 0 to High(Result.Positions) do
  begin
    mLine := mLine + AReader.ReadInt32;
    Result.Positions[mIndex] := TTextPosition.Create(mLine, AReader.ReadInt32);
  end;
end;

function ReadPatterns(var AReader: TCacheReader): TArray<TIndexFollowPattern>;
var
  mIndex, mLine: Integer;
begin
  SetLength(Result, AReader.ReadCount);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex].Trigger := AReader.ReadString;
    Result[mIndex].Follow := AReader.ReadString;
    Result[mIndex].Count := AReader.ReadNumber;
    SetLength(Result[mIndex].Lines, AReader.ReadCount);
    for mLine := 0 to High(Result[mIndex].Lines) do
    begin
      Result[mIndex].Lines[mLine] := AReader.ReadNumber;
    end;
  end;
end;

/// <summary>Gegenstück zu WriteUnitStart.</summary>
function ReadUnitStart(var AReader: TCacheReader): TUnitIndex;
var
  mFlags, mIndex: Integer;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AReader.ReadString;
  Result.FileName := AReader.ReadString;
  Result.Stamp := AReader.ReadInt;
  Result.Hash := AReader.ReadString;
  mFlags := AReader.ReadCount;
  Result.Library_ := (mFlags and cFlagLibrary) <> 0;
  Result.Compact := (mFlags and cFlagCompact) <> 0;
  Result.HasInitialization := (mFlags and cFlagInitialization) <> 0;
  Result.UsagesIndexed := (mFlags and cFlagUsages) <> 0;
  Result.InterfaceUses := AReader.ReadList;
  Result.ImplementationUses := AReader.ReadList;
  Result.Includes := AReader.ReadList;
  SetLength(Result.IncludeStamps, AReader.ReadCount);
  for mIndex := 0 to High(Result.IncludeStamps) do
  begin
    Result.IncludeStamps[mIndex] := AReader.ReadInt;
  end;
  if Result.FileName = '' then
  begin
    Fail;
  end;
end;

function ReadUnitHeader(var AReader: TCacheReader): TUnitIndex;
var
  mKind: TNamingKind;
begin
  Result := ReadUnitStart(AReader);
  // Zahlen, keine Längen: ReadCount begrenzte sie auf die Dateigröße.
  for mKind := Low(TNamingKind) to High(TNamingKind) do
  begin
    Result.Naming[mKind].Total := AReader.ReadNumber;
    Result.Naming[mKind].Prefixed := AReader.ReadNumber;
  end;
  Result.Directives := AReader.ReadList;
  Result.DeprecatedText := AReader.ReadString;
  Result.Rationale := AReader.ReadList;
  Result.Patterns := ReadPatterns(AReader);
  Result.Requires := AReader.ReadList;
end;

/// <summary>Überliest eine Liste (Anzahl, Nummern der Texte), ohne die Texte zu dekodieren (Phase 4); prüft die
/// Nummern wie ReadList (Phase 5).</summary>
procedure SkipList(var AReader: TCacheReader);
var
  mIndex, mCount: Integer;
begin
  mCount := AReader.ReadCount;
  for mIndex := 1 to mCount do
  begin
    AReader.SkipString;
  end;
end;

/// <summary>Überliest ein Symbol (Gegenstück zu ReadSymbol, mit denselben Prüfungen).</summary>
procedure SkipSymbol(var AReader: TCacheReader);
var
  mIndex: Integer;
begin
  // Name, Container
  AReader.SkipString;
  AReader.SkipString;
  ReadKind(AReader);
  for mIndex := 1 to 8 do
  begin
    AReader.ReadInt32;
  end;
  // Merker, Vorfahren, Typ, Typargumente, Vorfahr-Typargumente, Typparameter
  AReader.ReadCount;
  SkipList(AReader);
  AReader.SkipString;
  AReader.SkipString;
  SkipList(AReader);
  AReader.SkipString;
  if AReader.ReadVar > UInt64(Ord(High(TIndexVisibility))) then
  begin
    Fail;
  end;
  ReadArgCount(AReader);
  ReadArgCount(AReader);
  // Parametertypen, Include-Datei, Bedingung, Signatur, Direktiven, Grund, Variante
  SkipList(AReader);
  AReader.SkipString;
  AReader.SkipString;
  AReader.SkipString;
  SkipList(AReader);
  AReader.SkipString;
  AReader.SkipString;
  // Inline-Verweise, Zuordnungen, Begründungen
  SkipList(AReader);
  SkipList(AReader);
  SkipList(AReader);
end;

/// <summary>Überliest den Kopf einer Unit im Block (Gegenstück zu ReadUnitHeader, mit denselben Prüfungen).</summary>
procedure SkipUnitHeader(var AReader: TCacheReader);
var
  mIndex, mCount, mLine: Integer;
  mKind: TNamingKind;
begin
  // Name, Datei (nicht leer), Zeitstempel, Hash, Merker
  AReader.SkipString;
  AReader.SkipFileName;
  AReader.ReadInt;
  AReader.SkipString;
  AReader.ReadCount;
  SkipList(AReader);
  SkipList(AReader);
  SkipList(AReader);
  mCount := AReader.ReadCount;
  for mIndex := 1 to mCount do
  begin
    AReader.ReadInt;
  end;
  for mKind := Low(TNamingKind) to High(TNamingKind) do
  begin
    AReader.ReadNumber;
    AReader.ReadNumber;
  end;
  SkipList(AReader);
  AReader.SkipString;
  SkipList(AReader);
  // Folgemuster
  mCount := AReader.ReadCount;
  for mIndex := 1 to mCount do
  begin
    AReader.SkipString;
    AReader.SkipString;
    AReader.ReadNumber;
    for mLine := 1 to AReader.ReadCount do
    begin
      AReader.ReadNumber;
    end;
  end;
  // requires (Format 35)
  SkipList(AReader);
end;

/// <summary>Überliest eine Verwendung (Gegenstück zu ReadUsage).</summary>
procedure SkipUsage(var AReader: TCacheReader);
var
  mIndex, mCount: Integer;
begin
  AReader.SkipString;
  mCount := AReader.ReadCount;
  for mIndex := 1 to mCount do
  begin
    AReader.ReadInt32;
    AReader.ReadInt32;
  end;
end;

/// <summary>Block einer Unit: String-Tabelle, Kopf, Symbole, nicht geltende Deklarationen, Verwendungen. Ohne
/// ASymbols werden Kopf und Symbole nur überlesen (AUnit bleibt leer), ohne AUsages die Verwendungen (Phase 4); geprüft
/// wird der ganze Block.</summary>
function DecodeBlock(const ABlock: TBytes; out AUnit: TUnitIndex; ASymbols, AUsages: Boolean): Boolean;
var
  mReader: TCacheReader;
  mIndex, mSymbols, mUnavailable, mUsages: Integer;
begin
  AUnit := Default(TUnitIndex);
  mReader := Default(TCacheReader);
  mReader.Data := ABlock;
  mReader.Limit := Length(ABlock);
  try
    try
      mReader.ReadTable;
      if ASymbols then
      begin
        AUnit := ReadUnitHeader(mReader);
        SetLength(AUnit.Symbols, mReader.ReadCount);
        SetLength(AUnit.Unavailable, mReader.ReadCount);
        for mIndex := 0 to High(AUnit.Symbols) do
        begin
          AUnit.Symbols[mIndex] := ReadSymbol(mReader);
        end;
        for mIndex := 0 to High(AUnit.Unavailable) do
        begin
          AUnit.Unavailable[mIndex] := ReadSymbol(mReader);
        end;
      end
      else
      begin
        SkipUnitHeader(mReader);
        mSymbols := mReader.ReadCount;
        mUnavailable := mReader.ReadCount;
        for mIndex := 1 to mSymbols + mUnavailable do
        begin
          SkipSymbol(mReader);
        end;
      end;
      mUsages := mReader.ReadCount;
      if AUsages then
      begin
        SetLength(AUnit.Usages, mUsages);
        for mIndex := 0 to mUsages - 1 do
        begin
          AUnit.Usages[mIndex] := ReadUsage(mReader);
        end;
      end
      else
      begin
        for mIndex := 1 to mUsages do
        begin
          SkipUsage(mReader);
        end;
      end;
      Result := mReader.Position = mReader.Limit;
    except
      on ECacheFormat do
        Result := False;
    end;
  finally
    mReader.Strings.Free;
  end;
  if not Result then
  begin
    AUnit := Default(TUnitIndex);
  end;
end;

{ TCacheBlockSource }

constructor TCacheBlockSource.Create(const AReader: IIndexBlockReader; AOffset: Int64; ALength: Integer;
  AChecksum: Cardinal);
begin
  inherited Create;
  FReader := AReader;
  FOffset := AOffset;
  FLength := ALength;
  FChecksum := AChecksum;
end;

function TCacheBlockSource.BlockSize: Integer;
begin
  Result := FLength;
end;

function TCacheBlockSource.ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
begin
  AChecksum := FChecksum;
  // Prüfsumme je Block: Ein beschädigter Block betrifft nur seine Unit.
  Result := FReader.Read(FOffset, FLength, ABlock) and (ChecksumOf(ABlock, 0, Length(ABlock)) = FChecksum);
  if not Result then
  begin
    ABlock := nil;
  end;
end;

function TCacheBlockSource.Load(out AUnit: TUnitIndex): Boolean;
begin
  Result := LoadPart(AUnit, True);
end;

function TCacheBlockSource.LoadPart(out AUnit: TUnitIndex; AUsages: Boolean): Boolean;
var
  mBlock: TBytes;
  mChecksum: Cardinal;
begin
  AUnit := Default(TUnitIndex);
  Result := ReadBlock(mBlock, mChecksum) and DecodeBlock(mBlock, AUnit, True, AUsages);
end;

function TCacheBlockSource.LoadUsages(out AUsages: TArray<TIndexUsage>): Boolean;
var
  mBlock: TBytes;
  mChecksum: Cardinal;
  mUnit: TUnitIndex;
begin
  AUsages := nil;
  Result := ReadBlock(mBlock, mChecksum) and DecodeBlock(mBlock, mUnit, False, True);
  if Result then
  begin
    AUsages := mUnit.Usages;
  end;
end;

/// <summary>Katalog einer Unit aus dem Verzeichnis.</summary>
function ReadCatalog(var AReader: TCacheReader; const AHeader: TUnitIndex): TCatalogUnit;
var
  mIndex: Integer;
begin
  Result := Default(TCatalogUnit);
  Result.UnitName := AHeader.UnitName;
  Result.FileName := AHeader.FileName;
  Result.Library_ := AHeader.Library_;
  Result.InterfaceUses := AHeader.InterfaceUses;
  Result.ExportedTypeCount := AReader.ReadNumber;
  Result.ExportedTypes := AReader.ReadList;
  SetLength(Result.Symbols, AReader.ReadCount);
  for mIndex := 0 to High(Result.Symbols) do
  begin
    Result.Symbols[mIndex].Name := AReader.ReadString;
    Result.Symbols[mIndex].TypeName := AReader.ReadString;
    Result.Symbols[mIndex].Kind := ReadKind(AReader);
    Result.Symbols[mIndex].Start.Line := AReader.ReadInt32;
    Result.Symbols[mIndex].Start.Character := AReader.ReadInt32;
    Result.Symbols[mIndex].MinArgs := ReadArgCount(AReader);
    Result.Symbols[mIndex].MaxArgs := ReadArgCount(AReader);
    Result.Symbols[mIndex].Flags := Byte(AReader.ReadNumber);
    Result.Symbols[mIndex].Ancestors := AReader.ReadList;
  end;
end;

/// <summary>Überspringt den Katalog einer Unit im Verzeichnis, ohne seine Texte zu dekodieren; prüft die Nummern
/// wie ReadCatalog (Phase 5).</summary>
procedure SkipCatalog(var AReader: TCacheReader);
var
  mIndex, mCount, mEntry: Integer;
begin
  AReader.ReadNumber;
  SkipList(AReader);
  mCount := AReader.ReadCount;
  for mIndex := 1 to mCount do
  begin
    AReader.SkipString;
    AReader.SkipString;
    ReadKind(AReader);
    AReader.ReadInt32;
    AReader.ReadInt32;
    ReadArgCount(AReader);
    ReadArgCount(AReader);
    AReader.ReadNumber;
    for mEntry := 1 to AReader.ReadCount do
    begin
      AReader.SkipString;
    end;
  end;
end;

/// <summary>Einträge des Verzeichnisses; Blöcke liegen vor ADirectoryAt.</summary>
function ReadDirectory(const ADirectory: TBytes; const AReader: IIndexBlockReader;
  ADirectoryAt: Int64; ACatalog: Boolean): TArray<TIndexCacheEntry>;
var
  mReader: TCacheReader;
  mIndex: Integer;
  mOffset: UInt64;
  mLength: Integer;
  mChecksum: UInt64;
begin
  mReader := Default(TCacheReader);
  mReader.Data := ADirectory;
  mReader.Limit := Length(ADirectory);
  try
    mReader.ReadTable;
    SetLength(Result, mReader.ReadCount);
    for mIndex := 0 to High(Result) do
    begin
      Result[mIndex] := Default(TIndexCacheEntry);
      Result[mIndex].Header := ReadUnitStart(mReader);
      Result[mIndex].SymbolCount := mReader.ReadNumber;
      Result[mIndex].UnavailableCount := mReader.ReadNumber;
      Result[mIndex].UsageCount := mReader.ReadNumber;
      if ACatalog then
      begin
        Result[mIndex].Catalog := ReadCatalog(mReader, Result[mIndex].Header);
      end
      else
      begin
        SkipCatalog(mReader);
      end;
      mOffset := mReader.ReadVar;
      mLength := mReader.ReadNumber;
      mChecksum := mReader.ReadVar;
      if (mOffset < cHeadSize) or (mLength > cMaxSection) or (mOffset + UInt64(mLength) > UInt64(ADirectoryAt)) or
        (mChecksum > High(Cardinal)) then
      begin
        Fail;
      end;
      Result[mIndex].Source := TCacheBlockSource.Create(AReader, Int64(mOffset), mLength, Cardinal(mChecksum));
    end;
    if mReader.Position <> mReader.Limit then
    begin
      Fail;
    end;
  finally
    mReader.Strings.Free;
  end;
end;

function HasMagic(const AData: TBytes): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AData) >= Length(cMagic);
  for mIndex := Low(cMagic) to High(cMagic) do
  begin
    if not Result then
    begin
      Break;
    end;
    Result := AData[mIndex] = cMagic[mIndex];
  end;
end;

class function TIndexCache.ReadEntries(const AData: TBytes): TArray<TIndexCacheEntry>;
var
  mReason: string;
begin
  Result := ReadEntries(AData, mReason);
end;

class function TIndexCache.ReadEntries(const AData: TBytes; out AReason: string): TArray<TIndexCacheEntry>;
begin
  Result := ReadEntries(TIndexBlockFiles.OfBytes(AData, 0), AReason);
end;

class function TIndexCache.ReadEntries(const AReader: IIndexBlockReader;
  out AReason: string): TArray<TIndexCacheEntry>;
begin
  Result := ReadEntries(AReader, AReason, True);
end;

class function TIndexCache.ReadEntries(const AReader: IIndexBlockReader; out AReason: string;
  ACatalog: Boolean): TArray<TIndexCacheEntry>;
var
  mHead, mDirectory: TBytes;
  mDirectoryAt: UInt64;
  mLength: Cardinal;
  mChecksum: Cardinal;
begin
  Result := nil;
  AReason := '';
  if (AReader = nil) or (AReader.Size = 0) then
  begin
    Exit;
  end;
  AReason := cTexts[TCacheText.NoDpccIndexHeaderMissing].Text;
  if (AReader.Size < cHeadSize) or not AReader.Read(0, cHeadSize, mHead) or not HasMagic(mHead) then
  begin
    // Älteres Format mit kürzerem Kopf: die Version steht wie hier hinter dem Magic.
    if (Length(mHead) = 0) and AReader.Read(0, Length(cMagic) + 1, mHead) and HasMagic(mHead) and
      (mHead[cVersionAt] <> cFormatVersion) then
    begin
      AReason := cTexts[TCacheText.FormatVersionInsteadOf].Fmt([mHead[cVersionAt], cFormatVersion]);
    end;
    Exit;
  end;
  if mHead[cVersionAt] <> cFormatVersion then
  begin
    AReason := cTexts[TCacheText.FormatVersionInsteadOf].Fmt([mHead[cVersionAt], cFormatVersion]);
    Exit;
  end;
  mDirectoryAt := GetFixed(mHead, cDirectoryAt, 8);
  mLength := Cardinal(GetFixed(mHead, cDirectoryAt + 8, 4));
  mChecksum := Cardinal(GetFixed(mHead, cDirectoryAt + 12, 4));
  // Das Verzeichnis steht am Ende (nach einem abgebrochenen Ergänzen, Phase 4, auch davor): Eine abgeschnittene Datei
  // fällt hier auf.
  AReason := cTexts[TCacheText.ContentDamaged].Text;
  if (mDirectoryAt < cHeadSize) or (mLength > cMaxSection) or (mDirectoryAt + mLength > UInt64(AReader.Size)) or
    not AReader.Read(Int64(mDirectoryAt), Integer(mLength), mDirectory) then
  begin
    Exit;
  end;
  if ChecksumOf(mDirectory, 0, Length(mDirectory)) <> mChecksum then
  begin
    AReason := cTexts[TCacheText.ChecksumDoesNotMatch].Text;
    Exit;
  end;
  try
    Result := ReadDirectory(mDirectory, AReader, Int64(mDirectoryAt), ACatalog);
    AReason := '';
  except
    on ECacheFormat do
      Result := nil;
  end;
end;

class function TIndexCache.Append(AStream: TStream; const AItems: TArray<TIndexCacheItem>;
  const AInFile: TIndexBlockInFile; out APlaces: TArray<TIndexBlockPlace>): Integer;
begin
  Result := Append(AStream, AItems, AInFile, nil, APlaces);
end;

class function TIndexCache.Append(AStream: TStream; const AItems: TArray<TIndexCacheItem>;
  const AInFile: TIndexBlockInFile; const AKnown: IIndexBlockReader; out APlaces: TArray<TIndexBlockPlace>): Integer;
var
  mHead, mKnownHead: TBytes;
  mDirectoryAt: Int64;
  mLength: Integer;
  mChecksum: Cardinal;
begin
  APlaces := nil;
  // Nur einen Cache dieses Formats ergänzen; sonst schreibt der Aufrufer die Datei ganz.
  SetLength(mHead, cHeadSize);
  AStream.Position := 0;
  if (AStream.Size < cHeadSize) or (AStream.Read(mHead[0], cHeadSize) <> cHeadSize) or not HasMagic(mHead) or
    (mHead[cVersionAt] <> cFormatVersion) then
  begin
    Exit(-1);
  end;
  // Phase 5: Nur die Datei, deren Blöcke AKnown kennt. Gleiche Größe und gleicher Kopf (die Prüfsumme des
  // Verzeichnisses deckt die Lage aller Blöcke); hat ein anderer sie ersetzt, stimmen die Stellen nicht mehr.
  if (AKnown <> nil) and ((AStream.Size <> AKnown.Size) or not AKnown.Read(0, cHeadSize, mKnownHead) or
    (Length(mKnownHead) <> cHeadSize) or not CompareMem(@mKnownHead[0], @mHead[0], cHeadSize)) then
  begin
    Exit(-1);
  end;
  // Neue Blöcke und das Verzeichnis hinter das Ende; erst zuletzt zeigt der Kopf darauf.
  AStream.Seek(0, soEnd);
  Result := WriteBody(AStream, 0, AItems, AInFile, APlaces, mDirectoryAt, mLength, mChecksum);
  WriteHead(AStream, 0, mDirectoryAt, mLength, mChecksum);
end;

class function TIndexCache.UnusedBytes(const AReader: IIndexBlockReader; ABlockBytes: Int64): Int64;
var
  mHead: TBytes;
begin
  Result := 0;
  if (AReader = nil) or (AReader.Size < cHeadSize) or not AReader.Read(0, cHeadSize, mHead) or not HasMagic(mHead) or
    (mHead[cVersionAt] <> cFormatVersion) then
  begin
    Exit;
  end;
  Result := AReader.Size - cHeadSize - Int64(GetFixed(mHead, cDirectoryAt + 8, 4)) - ABlockBytes;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

class function TIndexCache.SourceAt(const AReader: IIndexBlockReader; const APlace: TIndexBlockPlace):
  IIndexUnitSource;
begin
  Result := TCacheBlockSource.Create(AReader, APlace.Offset, APlace.Length, APlace.Checksum);
end;

class function TIndexCache.ReaderOf(const ASource: IIndexUnitSource): IIndexBlockReader;
begin
  Result := nil;
  if (ASource <> nil) and (ASource is TCacheBlockSource) then
  begin
    Result := (ASource as TCacheBlockSource).FReader;
  end;
end;

class function TIndexCache.LoadFrom(const ASource: IIndexUnitSource; out AUnit: TUnitIndex;
  AUsages: Boolean): Boolean;
begin
  AUnit := Default(TUnitIndex);
  if ASource = nil then
  begin
    Exit(False);
  end;
  if not AUsages and (ASource is TCacheBlockSource) then
  begin
    Exit((ASource as TCacheBlockSource).LoadPart(AUnit, False));
  end;
  Result := ASource.Load(AUnit);
end;

class function TIndexCache.ExpandUsages(const AEntry: TIndexCacheEntry; out AUsages: TArray<TIndexUsage>): Boolean;
var
  mUnit: TUnitIndex;
begin
  AUsages := nil;
  if AEntry.Expanded then
  begin
    AUsages := AEntry.Header.Usages;
    Exit(True);
  end;
  // Phase 4: nur die Verwendungen dekodieren; Kopf und Symbole werden überlesen.
  if (AEntry.Source <> nil) and (AEntry.Source is TCacheBlockSource) then
  begin
    Exit((AEntry.Source as TCacheBlockSource).LoadUsages(AUsages));
  end;
  Result := (AEntry.Source <> nil) and AEntry.Source.Load(mUnit);
  if Result then
  begin
    AUsages := mUnit.Usages;
  end;
end;

class function TIndexCache.Expand(const AEntry: TIndexCacheEntry; out AUnit: TUnitIndex): Boolean;
begin
  Result := Expand(AEntry, AUnit, True);
end;

class function TIndexCache.Expand(const AEntry: TIndexCacheEntry; out AUnit: TUnitIndex; AUsages: Boolean): Boolean;
begin
  AUnit := AEntry.Header;
  if AEntry.Expanded then
  begin
    Exit(True);
  end;
  // Ohne AUsages bleiben die Verwendungen ungelesen (Phase 4; vorher dekodiert und verworfen).
  Result := LoadFrom(AEntry.Source, AUnit, AUsages);
  if not Result then
  begin
    AUnit := AEntry.Header;
    Exit;
  end;
  if AUnit.UsagesIndexed and not AUsages then
  begin
    AUnit.Usages := nil;
    AUnit.UsagesOffloaded := AEntry.UsageCount > 0;
  end;
end;

class function TIndexCache.Deserialize(const AData: TBytes): TArray<TUnitIndex>;
var
  mEntries: TArray<TIndexCacheEntry>;
  mIndex: Integer;
begin
  mEntries := ReadEntries(AData);
  SetLength(Result, Length(mEntries));
  for mIndex := 0 to High(mEntries) do
  begin
    if not Expand(mEntries[mIndex], Result[mIndex]) then
    begin
      Exit(nil);
    end;
  end;
end;

class function TIndexCache.HashOf(const AText: string): string;
begin
  Result := THashFNV1a32.GetHashString(AText) + IntToHex(Length(AText), 1);
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Index.Cache', cTexts);

end.
