unit dpcc.Common.Editing.Contract;

// Gemeinsame Typen des Features Editing (#1450): Umgebung der uses-Aktionen
// (#284) und alles, was die Schnellbefehle mit "/" (#293) untereinander
// austauschen. Die Befehls-Units (*Commands) binden nur diese Unit ein, das
// Register in dpcc.Common.Editing.SlashCommands bindet die Befehls-Units ein;
// so entsteht kein Unit-Zyklus.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Projects.Contract;

const
  /// <summary>Art einer umschreibenden Code-Aktion (LSP CodeActionKind).</summary>
  cRewriteKind = 'refactor.rewrite';

type

  /// <summary>Was der Index über eine Unit weiß.</summary>
  TUsesUnitInfo = record
    Known: Boolean;
    HasInitialization: Boolean;
    /// <summary>Namen der interface-Symbole, auch Mitglieder.</summary>
    Names: TArray<string>;
    /// <summary>Namen der interface-Symbole auf Unit-Ebene samt Enum-Werten (#1925): nur sie braucht ein
    /// Bezeichner, der nicht hinter einem Punkt steht, aus dem uses.</summary>
    TopNames: TArray<string>;
    /// <summary>Namen der Mitglieder von Class- und Record-Helpern im interface (#1925): Hinter einem Punkt
    /// braucht nur ein Helper seine Unit im uses.</summary>
    HelperNames: TArray<string>;
    /// <summary>Die Formulardatei der geprüften Unit verweist auf ein Modul dieser Unit (Connection =
    /// Form1.Connection): Der Eintrag gilt als im implementation-Teil verwendet, die IDE braucht ihn
    /// (dfm-reference-unit-missing).</summary>
    UsedByForm: Boolean;
  end;

  TUsesUnitInfoFunc = reference to function(const AUnitName: string): TUsesUnitInfo;

  /// <summary>Nutzung der uses-Einträge aus der Namensauflösung (#1925, TUsesUsage). Bezeichner, deren
  /// Deklaration feststeht, zählen nur für die Unit dieser Deklaration; die übrigen vergleicht TUsesActions mit den
  /// Namen der Units wie zuvor, aber genauer: vor einem Punkt mit TopNames, dahinter mit HelperNames. Ohne Active
  /// gilt der großzügige Namensvergleich mit allen Namen.</summary>
  TUsesResolution = record
  public const
    cInterfacePart = 1;
    cImplementationPart = 2;
  public
    Active: Boolean;
    /// <summary>Offsets der Bezeichner mit bekannter Deklaration, aufsteigend.</summary>
    Settled: TArray<Integer>;
    /// <summary>uses-Einträge, wie sie dastehen, und je Eintrag die Teile (cInterfacePart, cImplementationPart),
    /// in denen ihn ein aufgelöster Bezeichner oder ein Rumpf einer gerufenen inline-Routine braucht.</summary>
    Units: TArray<string>;
    Masks: TArray<Integer>;
    function IsSettled(AOffset: Integer): Boolean;
    function MaskOf(const AName: string): Integer;
  end;

  /// <summary>Nutzung der uses-Einträge von AText (Token in AInactive zählen nicht); nicht Active, wenn sich der
  /// Text nicht auflösen lässt (Syntaxfehler, kein Index).</summary>
  TUsesResolveFunc = reference to function(const AText: string; const AInactive: TArray<TTextRange>): TUsesResolution;

  /// <summary>Units, deren interface ein Symbol AName auf Unit-Ebene deklariert.</summary>
  TUnitsDeclaringFunc = reference to function(const AName: string): TArray<string>;

  /// <summary>Alles, was die uses-Aktionen für ein Dokument brauchen.</summary>
  TUsesContext = record
    Info: TUsesUnitInfoFunc;
    Declaring: TUnitsDeclaringFunc;
    /// <summary>Einstellung "usesKeep".</summary>
    Keep: TArray<string>;
    /// <summary>Unit-Namespaces des Projekts (System für SysUtils).</summary>
    Namespaces: TArray<string>;
    /// <summary>Inaktive Zweige, deren uses bei der Prüfung nicht zählen (#621); nil = keine.</summary>
    Inactive: TArray<TTextRange>;
    /// <summary>Namensauflösung für die Datei (#1925); nil = nur Namensvergleich.</summary>
    Resolve: TUsesResolveFunc;
    /// <summary>Resolve für AText, sonst eine Nutzung ohne Active.</summary>
    function Resolution(const AText: string; const AInactive: TArray<TTextRange>): TUsesResolution;
  end;

  /// <summary>Zugriff auf Einstellungen für die Erzeugung aus TSlashContext (#301). Seit Rückbau R2/R3 ohne die
  /// übrigen Dienste der Schnellbefehle (Dateien, Projekt, Prüfregeln); kein Server setzt ihn mehr, TSlashContext.Host
  /// bleibt nil.</summary>
  ISlashHost = interface
    ['{8E4A2C61-3B7D-4F95-A0C8-5D1E9F27B364}']
    /// <summary>Einstellung AName zur Datei AUri (Namen in TSlashSettings); '' ohne.</summary>
    function Setting(const AUri, AName: string): string;
  end;

  /// <summary>Namen der Einstellungen, die Befehle über ISlashHost.Setting lesen.</summary>
  TSlashSettings = record
  public const
    /// <summary>Protokollaufruf für /log, /except und /measure (#304); '' = OutputDebugString.</summary>
    cLogCall = 'logCall';
    /// <summary>Palettenseite für /component (#299).</summary>
    cComponentPalette = 'componentPalette';
    cDefaultPalette = 'Eigene';
    /// <summary>completion.interfaceSection (#466) für /intf: private, protected oder public.</summary>
    cInterfaceSection = 'interfaceSection';
    /// <summary>Name hinter -o für /todo (#297); '' = git config user.name.</summary>
    cTodoOwner = 'todoOwner';
    /// <summary>Kategorie hinter -c für /todo (#297); '' = keine.</summary>
    cTodoCategory = 'todoCategory';
    /// <summary>/sortuses streicht ungenutzte Units (#297, #284); 'false' = nur sortieren.</summary>
    cSortUsesRemoveUnused = 'sortUsesRemoveUnused';
    /// <summary>/helper für Aufzählungen mit cNames, ToString und FromString (#875); 'false' = leerer
    /// Helper.</summary>
    cEnumHelper = 'enumHelper';
    /// <summary>/helper für Mengen mit Contains, ToText, Toggle und All (#875); 'false' = leerer Helper.</summary>
    cSetHelper = 'setHelper';
    /// <summary>classCompletion.typeComment (#1835): brace, line, summary, region oder off.</summary>
    cTypeComment = 'typeComment';
    /// <summary>classCompletion.bodyStubs (#1837); 'false' = leere Rümpfe.</summary>
    cBodyStubs = 'bodyStubs';
    /// <summary>classCompletion.lifecycleFirst (#1836); 'false' = Konstruktoren nicht vorziehen.</summary>
    cLifecycleFirst = 'lifecycleFirst';
  end;

  /// <summary>Ort und Inhalt der Befehlszeile.</summary>
  TSlashContext = record
    /// <summary>Ganzer Text der Datei, Befehlszeile noch enthalten.</summary>
    Text: string;
    /// <summary>Zeile des Befehls ab 0.</summary>
    Line: Integer;
    /// <summary>Ganze Befehlszeile.</summary>
    LineText: string;
    Name: string;
    /// <summary>Text nach dem Namen, ohne führende und folgende Leerzeichen.</summary>
    Arguments: string;
    Namespaces: TArray<string>;
    /// <summary>Symbolindex für Vorfahren und Interfaces aus anderen Units (#295); nil ohne.</summary>
    Index: ISymbolIndex;
    /// <summary>Eingestellte Delphi-Version (BDS-Nummer, #109); '' = unbekannt, alles erlaubt.</summary>
    DelphiVersion: string;
    /// <summary>Formatstil der Datei (#43); die Einrückung der Änderungen setzt Reindent danach um.</summary>
    Style: TFormatStyle;
    /// <summary>URI der Datei; '' ohne.</summary>
    Uri: string;
    /// <summary>Projekt und Editor; nil ohne (z. B. bei der Prüfung stehen gebliebener Zeilen).</summary>
    Host: ISlashHost;
    /// <summary>Aktionen, die erst nach erfolgreichem Befehl laufen (Defer); bei Hinweisen verworfen. nil, wenn
    /// nichts ausgeführt werden soll.</summary>
    Actions: TList<TProc>;
    /// <summary>Umschließen nur bis vor diese Zeile (Markierung im Erzeugen-Menü, #719); 0 = bis zum Ende des
    /// umgebenden Blocks.</summary>
    WrapUntil: Integer;
    /// <summary>Merkt AAction für nach dem Befehl vor; ohne Actions ohne Wirkung.</summary>
    procedure Defer(const AAction: TProc);
  end;

  // Code-Aktion samt Teilen (aus dpcc.Common.Editing.CodeActions, Rückbau R2/K3): Die Vervollständigung
  // („Parameter abgleichen“, #88) braucht nur den Record, nicht die Aktionen.
  /// <summary>Edits in einer anderen Datei als dem Dokument der Aktion, z. B. der Formulardatei (#309).</summary>
  TFileTextEdits = record
    FileName: string;
    Edits: TArray<TTextEdit>;
  end;

  /// <summary>Teil einer Code-Aktion, den der Client abwählen kann (gleiche Stellen, #2054).</summary>
  TCodeActionChoice = record
    Title: string;
    /// <summary>Stelle im Dokument, die der Teil ändert.</summary>
    Range: TTextRange;
    class function Create(const ATitle: string; const ARange: TTextRange): TCodeActionChoice; static;
  end;

  TCodeAction = record
    Title: string;
    Kind: string;
    /// <summary>Edits im Dokument der Aktion.</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Edits in weiteren Dateien (#309); nil = keine.</summary>
    FileEdits: TArray<TFileTextEdits>;
    IsPreferred: Boolean;
    /// <summary>Regelkennung des behobenen Treffers, sonst ''.</summary>
    RuleId: string;
    /// <summary>Bereich des behobenen Treffers, wenn RuleId gesetzt ist.</summary>
    DiagnosticRange: TTextRange;
    /// <summary>Befehl statt oder nach den Edits, z. B. für Dateiumwandlungen; '' ohne.</summary>
    Command: string;
    CommandArguments: TArray<string>;
    /// <summary>Kennung für Clients, die eine bestimmte Aktion suchen (UsesRemoveTag, #621); '' ohne.</summary>
    Tag: string;
    /// <summary>Text, den der Client vor dem Übernehmen als Vorschau zeigt (neue Signatur, #663); '' ohne.</summary>
    Preview: string;
    /// <summary>Grund, warum die Aktion hier nicht geht (Hinweis statt Aktion, #663); '' wenn sie geht.</summary>
    Disabled: string;
    /// <summary>Abwählbare Teile (#2054); nil ohne.</summary>
    Choices: TArray<TCodeActionChoice>;
    /// <summary>Je Edit in Edits die Indizes in Choices, die alle gewählt sein müssen; fehlt der Eintrag oder ist
    /// er leer, gilt der Edit immer.</summary>
    EditChoices: TArray<TArray<Integer>>;
  end;

implementation

uses
  System.StrUtils;

{ TCodeActionChoice }

class function TCodeActionChoice.Create(const ATitle: string; const ARange: TTextRange): TCodeActionChoice;
begin
  Result.Title := ATitle;
  Result.Range := ARange;
end;

{ TUsesResolution }

function TUsesResolution.IsSettled(AOffset: Integer): Boolean;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := High(Settled);
  while mLow <= mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if Settled[mMiddle] = AOffset then
    begin
      Exit(True);
    end;
    if Settled[mMiddle] < AOffset then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle - 1;
    end;
  end;
  Result := False;
end;

function TUsesResolution.MaskOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  mIndex := IndexText(AName, Units);
  if mIndex < 0 then
  begin
    Exit(0);
  end;
  Result := Masks[mIndex];
end;

{ TUsesContext }

function TUsesContext.Resolution(const AText: string; const AInactive: TArray<TTextRange>): TUsesResolution;
begin
  if Assigned(Resolve) then
  begin
    Result := Resolve(AText, AInactive);
  end
  else
  begin
    Result := Default(TUsesResolution);
  end;
end;

{ TSlashContext }

procedure TSlashContext.Defer(const AAction: TProc);
begin
  if Actions <> nil then
  begin
    Actions.Add(AAction);
  end;
end;

end.
