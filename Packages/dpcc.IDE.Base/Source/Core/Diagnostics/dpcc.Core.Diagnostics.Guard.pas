unit dpcc.Core.Diagnostics.Guard;

// Absturzsicherheit (#493), Teil ohne Windows und Open Tools API:
// - TDpccGuard.Run: jeder Einstiegspunkt aus der IDE (Timer, Notifier,
//   Zeichnen, Tasten) läuft hierüber. Exceptions verlassen dpcc nie in
//   Richtung IDE; sie werden protokolliert und dem Feature angerechnet.
// - Sicherung: 3 Fehler eines Features innerhalb von 5 Minuten schalten nur
//   dieses Feature ab (Run tut dann nichts mehr), mit einer Warnung über
//   OnWarning und OnTripped (Eintrag in der Benachrichtigungszentrale).
//   Abgeschaltet bleibt es bis zum Neustart der IDE; der Zustand liegt nur im Speicher (nichts in Registry
//   oder Dateien). Eine Seite zum Wiedereinschalten gibt es seit S3 nicht mehr.
// - Ein Feature je sichtbarer Funktion: Eine gemeinsame Sicherung für viele
//   Units würde bei einem Zeichenfehler der Minimap auch Gliederung,
//   Brotkrumen und Sticky Scroll abschalten. EditorCommands gilt nur für
//   ausdrücklich aufgerufene Editorbefehle.
// - Derselbe Fehler (Klasse und Stelle) eines Features innerhalb von RepeatMs
//   nach dem zuletzt gezählten zählt nicht erneut und steht nicht einzeln im
//   Protokoll: Ein Zeichendurchlauf meldet einen Fehler sonst für jede Zeile
//   und löste die Sicherung in einer Millisekunde aus. Die nächste gezählte
//   Zeile nennt, wie oft er seit der letzten Meldung übergangen wurde.
// - Sicherung je Quelle (Provider): ReportProvider zählt Fehler einer
//   einzelnen Datenquelle, etwa der Vervollständigung vom Server; nach 3
//   Fehlern in 5 Minuten fällt nur diese Quelle aus, die übrigen laufen weiter.
// - Langsame Quelle: Eine Zeitüberschreitung ist kein Fehler und zählt nicht
//   zur Sicherung (sonst schaltete ein beschäftigter Rechner Quellen ab).
//   ReportProviderSlow schreibt je Quelle höchstens eine Zeile je
//   SlowLogSeconds mit der Zahl der übergangenen Meldungen.
// - Zeitmessung (Diagnose-Fenster, Reiter „Hauptthread“): Ist Timing gesetzt,
//   meldet Run Beginn und Ende jedes Aufrufs, ReportProviderSlow jede langsame
//   Quelle. Ohne Diagnosemodus ist Timing nil, und Run prüft nur dieses Feld.
//   Timing ist eine abstrakte Klasse, damit diese Unit den Rekorder
//   (dpcc.Core.Diagnostics.PluginTimings) nicht kennen muss.
// - RunIde: Arbeit der IDE innerhalb eines dpcc-Aufrufs (Projekt öffnen).
//   Ihre Zeit zählt wie ein modaler Dialog nicht als Zeit von dpcc; vorher
//   stand das Projektladen als 13,9 s der Willkommensseite da (#1987).
//   Exceptions laufen unverändert zum äußeren Run.
// - Laufende Funktion für den Einfrier-Wächter (#1988): Run legt das Feature
//   im Hauptthread auf einen kleinen Stapel fester Größe (ohne Sperre und
//   ohne Speicher), RunIde einen Eintrag „IDE“. CurrentFeatureName liest ihn
//   aus dem Wächter-Thread; vorher nannte ein Hänger nur Aktionen mit
//   TDpccActivity.Scope, und die meisten Einstiegspunkte (Zeichnen, Timer,
//   Notifier) liefen als „ohne dpcc“.
// - Disable schaltet ein Feature wie die Sicherung ab, auf Wunsch aus dem
//   Diagnose-Fenster; wieder an wie nach der Sicherung (Menü dpcc).
// - TDpccRotatingLog: Protokoll unter %LOCALAPPDATA%\dpcc\Logs, höchstens
//   5 Dateien à 1 MB. Jede Fehlerzeile nennt dpcc-Version, Feature bzw.
//   Quelle, Fehlerklasse, Meldung (eine Zeile, gekürzt) und den Stack-Trace;
//   nie Quelltext aus dem Editor. Den Stack-Trace liefert Exception.StackTrace
//   (falls ein Anbieter installiert ist), sonst der Haken StackOf
//   (dpcc.IDE.Diagnostics.StackCapture: Mitschnitt beim Auslösen).
// - Schreibfehler des Protokolls: Ein Fehler beim Rotieren darf das Anhängen
//   nicht verhindern, und kein Fehler darf still verschwinden. Ein
//   benannter Mutex je Ordner sperrt Rotieren und Schreiben über alle IDE-Prozesse
//   (die IDE des Benutzers und eine Bau-IDE teilen den Ordner;
//   ohne Sperre öffneten zwei Schreiber dieselbe Datei exklusiv). Scheitert
//   das Rotieren, wird trotzdem angehängt und der Grund einmal vermerkt.
//   Scheitert das Anhängen, zählt Add die verlorenen Zeilen, meldet den
//   ersten Fehler (und jeden neuen Grund) über OnError und schreibt beim
//   nächsten Gelingen eine Zeile über die Lücke.
// - Anonym (#1478): Jede Zeile läuft vor dem Schreiben durch
//   TDpccLogRedactor (dpcc.Core.Diagnostics.LogRedaction). Namen, Pfade und
//   fremder Text sind an der Stelle gekennzeichnet, an der die Zeile entsteht
//   (dpcc.Text.LogMarks); die Meldung einer Exception kennzeichnet ErrorText
//   bzw. ErrorLine. Klarnamen nur mit diagnostics.log.names (Redactor.Names).
//   Warnungen an die Oberfläche gehen ohne Kennzeichen im Klartext.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  dpcc.Core.Diagnostics.LogRedaction;

type
{$SCOPEDENUMS ON}
  TDpccFeature = (Completion, Signature, Hover, Pairs, Problems, Reloader, Palette, CheckOnSave, Watchdog, Server,
    Settings, Menu, Files, InlayHints, Results, EditorCommands, Forms, Build, Status, WelcomePage, ShortcutTips,
    Notes, Bookmarks, Notifications, Breadcrumbs, Outline, StickyScroll, Minimap, LineChanges, GutterColumn,
    RecursionMarkers, OverviewRuler, SelectionMatches, MultiCursor, LinkedEditing, CodeLens, NavHistory, Peek,
    SmartPaste, WrapSelection, Unwrap, Hide, Search, UnitSearch, Generate, ContinueLines, SlashCommands,
    GoToDefinition, EditorToolbar, QuickBookmarks, StatusBar, Architecture, UnitRelations, SymbolPath, Tasks, Debugger,
    ExitPoints, Reassigned, ExpressionType, MethodPlacement, IssueLinks,
    BlameIssues, Query, Hotspots, DesignerBar, Tracker, WelcomeUpdates, RegionFolds, SmartIndent,
    LearnedSuggestions);
{$SCOPEDENUMS OFF}

  TDpccFeatures = set of TDpccFeature;

  /// <summary>Protokoll gestört: Grund des Schreibfehlers; '' = schreibt wieder.</summary>
  TDpccLogError = reference to procedure(const AMessage: string);

  TDpccRotatingLog = class
  private
    FFolder: string;
    FMaxBytes: Int64;
    FMaxFiles: Integer;
    FLock: TCriticalSection;
    /// <summary>Seit dem letzten gelungenen Schreiben verlorene Zeilen.</summary>
    FFailed: Integer;
    /// <summary>Verlorene Zeilen seit dem Start.</summary>
    FLost: Integer;
    FLastError: string;
    FRotateError: string;
    FOnError: TDpccLogError;
    FRedactor: TDpccLogRedactor;
    procedure Rotate;
    /// <summary>Rotiert eine volle Datei; Zeile über ein gescheitertes Rotieren oder ''.</summary>
    function RotateIfFull(const AStamp: string): string;
    /// <summary>Schreibt ALine samt ausstehender Meldungen; die Sperre hält der Aufrufer.</summary>
    procedure WriteLocked(const ALine: string);
    function AppendLine(const ALine: string): string;
    function Clean(const AText: string): string;
  public
    /// <summary>So lange wartet Add auf einen anderen Prozess, der gerade schreibt; danach schreibt es trotzdem.
    /// </summary>
    const cLockTimeoutMs = 2000;
    constructor Create(const AFolder: string; AMaxBytes: Int64; AMaxFiles: Integer); overload;
    /// <summary>Wie oben mit AMaxFiles = 5.</summary>
    constructor Create(const AFolder: string; AMaxBytes: Int64); overload;
    /// <summary>Wie oben mit AMaxBytes = 1 MB und AMaxFiles = 5.</summary>
    constructor Create(const AFolder: string); overload;
    destructor Destroy; override;
    /// <summary>Zeile mit Zeitstempel anhängen. Wirft nie; ein Schreibfehler zählt die Zeile als verloren und meldet
    /// sich über OnError.</summary>
    procedure Add(const AText: string);
    /// <summary>Name des benannten Mutex für AFolder (Groß-/Kleinschreibung und Schlussstrich egal).</summary>
    class function MutexName(const AFolder: string): string; static;
    /// <summary>Aktuelle Datei (dpcc.log); ältere heißen dpcc.1.log … dpcc.4.log.</summary>
    function FileName: string;
    /// <summary>Ordner der Protokolldateien (Tests stellen ihn um).</summary>
    property Folder: string read FFolder write FFolder;
    /// <summary>Seit dem Start verlorene Zeilen.</summary>
    property Lost: Integer read FLost;
    /// <summary>Grund des letzten Schreibfehlers; '' = das letzte Schreiben gelang.</summary>
    property LastError: string read FLastError;
    /// <summary>Erster Schreibfehler nach einem gelungenen Schreiben und jeder neue Grund; '' sobald wieder
    /// geschrieben wird. Läuft außerhalb der Sperren im Thread des Schreibers und darf selbst protokollieren.
    /// </summary>
    property OnError: TDpccLogError read FOnError write FOnError;
    /// <summary>%LOCALAPPDATA%\dpcc\Logs.</summary>
    class function DefaultFolder: string; static;
    /// <summary>Anonymisiert jede Zeile vor dem Schreiben (#1478); gehört dem Protokoll.</summary>
    property Redactor: TDpccLogRedactor read FRedactor;
  end;

  TDpccFuse = class
  public const
    cLimit = 3;
    cWindowMinutes = 5;
    /// <summary>Derselbe Fehler eines Features so kurz nach dem zuletzt gezählten zählt nicht erneut.</summary>
    cRepeatMs = 1000;
    /// <summary>Langsame Quelle: höchstens eine Protokollzeile je Quelle in diesem Abstand.</summary>
    cSlowLogSeconds = 60;
  private
    FFailures: array[TDpccFeature] of TArray<TDateTime>;
    // Zuletzt gezählter Fehler je Feature (Schlüssel, Zeit) und übergangene Wiederholungen seitdem.
    FLastKey: array[TDpccFeature] of string;
    FLastCounted: array[TDpccFeature] of TDateTime;
    FRepeats: array[TDpccFeature] of Integer;
    FTripped: TDpccFeatures;
    FProviderFailures: TDictionary<string, TArray<TDateTime>>;
    // Kleingeschriebener Name → Name wie gemeldet.
    FProvidersTripped: TDictionary<string, string>;
    // Langsame Quellen, kleingeschriebener Name → Zeit der letzten Protokollzeile bzw. seitdem übergangene.
    FSlowLogged: TDictionary<string, TDateTime>;
    FSlowSkipped: TDictionary<string, Integer>;
    FClock: TFunc<TDateTime>;
    FLock: TCriticalSection;
    /// <summary>Zählt einen Fehler zu AStamps; True, wenn es Limit Fehler im Zeitfenster sind.</summary>
    function Count(var AStamps: TArray<TDateTime>): Boolean;
  public
    constructor Create(const AClock: TFunc<TDateTime>); overload;
    /// <summary>Wie oben mit AClock = nil.</summary>
    constructor Create; overload;
    destructor Destroy; override;
    /// <summary>Fehler zählen; True, wenn die Sicherung dadurch gerade auslöst.</summary>
    function Failed(AFeature: TDpccFeature): Boolean; overload;
    /// <summary>Wie Failed, mit dem Schlüssel des Fehlers (Klasse und Stelle). Derselbe Schlüssel innerhalb von
    /// RepeatMs nach dem zuletzt gezählten zählt nicht (ARepeat = True). ASkipped: so viele Wiederholungen des
    /// zuletzt gezählten Fehlers wurden seitdem übergangen.</summary>
    function Failed(AFeature: TDpccFeature; const AKey: string; out ARepeat: Boolean;
      out ASkipped: Integer): Boolean; overload;
    function Tripped(AFeature: TDpccFeature): Boolean;
    function TrippedSet: TDpccFeatures;
    procedure Reset(AFeature: TDpccFeature);
    /// <summary>Feature abschalten wie nach dem Auslösen, ohne Fehler zu zählen.</summary>
    procedure Trip(AFeature: TDpccFeature);
    /// <summary>Wie Failed, für eine einzelne Quelle (Name ohne Groß-/Kleinschreibung).</summary>
    function ProviderFailed(const AName: string): Boolean;
    function ProviderTripped(const AName: string): Boolean;
    function TrippedProviders: TArray<string>;
    procedure ResetProvider(const AName: string);
    /// <summary>Langsame Antwort der Quelle AName, kein Fehler: True, wenn eine Protokollzeile fällig ist (die
    /// erste, danach höchstens eine je SlowLogSeconds). ASkipped: seit der letzten Zeile übergangene Meldungen.
    /// </summary>
    function ProviderSlow(const AName: string; out ASkipped: Integer): Boolean;
    /// <summary>Alle Features und Quellen.</summary>
    procedure ResetAll;
  end;

  TDpccGuardMessage = reference to procedure(const AText: string);
  /// <summary>Stacktrace zur gerade behandelten Ausnahme; '' ohne.</summary>
  TDpccGuardStackFunc = reference to function(AE: Exception): string;
  /// <summary>Sicherung eines Features hat ausgelöst; AMessage ist die letzte Fehlermeldung (gekürzt).</summary>
  TDpccGuardTripped = reference to procedure(AFeature: TDpccFeature; const AMessage: string);

  /// <summary>Messpunkte von Run und ReportProviderSlow; der Rekorder des Diagnose-Fensters leitet hiervon ab.
  /// </summary>
  TDpccGuardTiming = class
  public
    /// <summary>Beginn eines Aufrufs; das Ergebnis geht unverändert an Leave.</summary>
    function Enter: Integer; virtual; abstract;
    /// <summary>Ende des Aufrufs, der mit Enter begann (auch nach einem Fehler).</summary>
    procedure Leave(AFeature: TDpccFeature; AToken: Integer); virtual; abstract;
    /// <summary>Zeit, die nicht dpcc gehört, beginnt im laufenden Aufruf: Arbeit der IDE (RunIde), ein modaler
    /// Dialog oder eine eigene Nachrichtenschleife; ohne Wirkung, wenn nicht überschrieben.</summary>
    procedure ModalBegin; virtual;
    /// <summary>Die mit ModalBegin begonnene Zeit ist zu Ende (auch nach einem Fehler).</summary>
    procedure ModalEnd; virtual;
    /// <summary>Die Quelle AName war zu langsam (Zeitlimit oder vorige Anfrage läuft noch).</summary>
    procedure ProviderSlow(const AName: string); virtual; abstract;
  end;

  TDpccGuard = class
  private class var
    FFuse: TDpccFuse;
    FLog: TDpccRotatingLog;
    FOnWarning: TDpccGuardMessage;
    FOnFailure: TProc<TDpccFeature>;
    FStackOf: TDpccGuardStackFunc;
    FOnTripped: TDpccGuardTripped;
    FTiming: TDpccGuardTiming;
    class function ErrorLine(const AWhere: string; AE: Exception): string; static;
  public
    /// <summary>Höchstlänge einer Fehlermeldung im Protokoll; mehr könnte Quelltext enthalten.</summary>
    const cMaxMessageLength = 300;
    class constructor Create;
    class destructor Destroy;
    /// <summary>Führt AProc geschützt aus; False bei Fehler oder abgeschaltetem Feature.</summary>
    class function Run(AFeature: TDpccFeature; const AProc: TProc): Boolean; static;
    /// <summary>AProc ist Arbeit der IDE (etwa IOTAActionServices.OpenProject): Ihre Zeit zählt im
    /// Diagnosemodus nicht als Zeit von dpcc. Fängt keine Exception; dafür sorgt das äußere Run.</summary>
    class procedure RunIde(const AProc: TProc); static;
    /// <summary>Name der innersten Funktion, die im Hauptthread über Run läuft; '' ohne oder während
    /// RunIde. Aus jedem Thread, ohne Sperre (der Einfrier-Wächter fragt, während der Hauptthread steht).
    /// </summary>
    class function CurrentFeatureName: string; static;
    /// <summary>Fehler aus einem eigenen except-Block melden (zählt wie in Run).</summary>
    class procedure Report(AFeature: TDpccFeature; AE: Exception); static;
    /// <summary>Feature durch die Sicherung abgeschaltet?</summary>
    class function Disabled(AFeature: TDpccFeature): Boolean; static;
    class procedure Enable(AFeature: TDpccFeature); static;
    class procedure EnableAll; static;
    /// <summary>Feature bis zum Neustart (oder bis Enable) abschalten, ohne Fehler; aus dem Diagnose-Fenster.
    /// </summary>
    class procedure Disable(AFeature: TDpccFeature); static;
    class function DisabledSet: TDpccFeatures; static;
    /// <summary>Protokolliert eine Zeile ins rotierende Protokoll.</summary>
    class procedure Log(const AText: string); static;
    /// <summary>„Klasse: Meldung“ mit gekennzeichneter, einzeiliger Meldung (#1478) für eine Protokollzeile.
    /// </summary>
    class function ErrorText(AE: Exception): string; static;
    /// <summary>AText einzeilig und gekürzt (SafeMessage), als fremder Text gekennzeichnet (#1478).</summary>
    class function MessageText(const AText: string): string; static;
    /// <summary>Klarnamen im Protokoll (diagnostics.log.names); Vorgabe aus.</summary>
    class procedure SetLogNames(AValue: Boolean); static;
    class function FeatureName(AFeature: TDpccFeature): string; static;
    /// <summary>Fehler der Quelle AName melden; nach 3 in 5 Minuten fällt nur sie aus.</summary>
    class procedure ReportProvider(const AName: string; AE: Exception); overload; static;
    class procedure ReportProvider(const AName, AMessage: string); overload; static;
    /// <summary>Quelle AName war zu langsam (Zeitlimit überschritten oder vorige Anfrage läuft noch): zählt nicht
    /// zur Sicherung; eine Protokollzeile je Quelle und SlowLogSeconds mit der Zahl der übergangenen.</summary>
    class procedure ReportProviderSlow(const AName, AText: string); static;
    /// <summary>Führt AProc für die Quelle AName geschützt aus; False bei Fehler oder abgeschalteter Quelle.</summary>
    class function RunProvider(const AName: string; const AProc: TProc): Boolean; static;
    class function ProviderDisabled(const AName: string): Boolean; static;
    class procedure EnableProvider(const AName: string); static;
    class function DisabledProviders: TArray<string>; static;
    /// <summary>Meldung einzeilig und gekürzt, damit kein Quelltext ins Protokoll gelangt.</summary>
    class function SafeMessage(const AText: string): string; static;
    /// <summary>Warnungen für die Meldungsansicht (nie als Dialog).</summary>
    class property OnWarning: TDpccGuardMessage read FOnWarning write FOnWarning;
    /// <summary>Nach jedem gezählten Fehler eines Features, aus jedem Thread (Startmarke des abgesicherten
    /// Starts, #722).</summary>
    class property OnFailure: TProc<TDpccFeature> read FOnFailure write FOnFailure;
    /// <summary>Stacktrace für Fehlerzeilen, wenn E.StackTrace leer ist (im except-Block aufgerufen).</summary>
    class property StackOf: TDpccGuardStackFunc read FStackOf write FStackOf;
    /// <summary>Nach dem Auslösen der Sicherung eines Features (Benachrichtigungszentrale), im Thread des Fehlers.
    /// </summary>
    class property OnTripped: TDpccGuardTripped read FOnTripped write FOnTripped;
    class property Fuse: TDpccFuse read FFuse;
    /// <summary>Messpunkte des Diagnose-Fensters; nil (Vorgabe) misst nichts. Gehört dem Setzenden.</summary>
    class property Timing: TDpccGuardTiming read FTiming write FTiming;
    class property RotatingLog: TDpccRotatingLog read FLog;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  dpcc.Text.LogMarks,
  dpcc.Core.Product.Version,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TGuardText = (FeatureTripped, SourceTripped);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TGuardText] of string = (
    ('dpcc: %s nach %d Fehlern in %d Minuten abgeschaltet (zuletzt: %s); bis zum Neustart der IDE.',
     'dpcc: Quelle „%s“ nach %d Fehlern in %d Minuten abgeschaltet (zuletzt: %s); bis zum Neustart der IDE, die übrigen Quellen laufen weiter.'),
    ('dpcc: %s switched off after %d errors in %d minutes (last: %s) until the IDE is restarted.',
     'dpcc: source "%s" switched off after %d errors in %d minutes (last: %s) until the IDE is restarted; the other sources keep running.'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TGuardText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

{ TDpccRotatingLog }

constructor TDpccRotatingLog.Create(const AFolder: string; AMaxBytes: Int64);
begin
  Create(AFolder, AMaxBytes, 5);
end;

constructor TDpccRotatingLog.Create(const AFolder: string);
begin
  Create(AFolder, 1024 * 1024, 5);
end;

constructor TDpccRotatingLog.Create(const AFolder: string; AMaxBytes: Int64; AMaxFiles: Integer);
begin
  inherited Create;
  FFolder := AFolder;
  FMaxBytes := AMaxBytes;
  FMaxFiles := AMaxFiles;
  FLock := TCriticalSection.Create;
  FRedactor := TDpccLogRedactor.Create(TDpccLogRedactor.EnvironmentIdentity);
end;

destructor TDpccRotatingLog.Destroy;
begin
  FRedactor.Free;
  FLock.Free;
  inherited;
end;

class function TDpccRotatingLog.MutexName(const AFolder: string): string;
var
  mKey: string;
  mHash: Cardinal;
  mIndex: Integer;
begin
  // FNV-1a über den Ordner; ein Mutexname darf außer nach „Local\“ keinen Backslash enthalten.
  mKey := UpperCase(ExcludeTrailingPathDelimiter(AFolder));
  mHash := 2166136261;
  for mIndex := 1 to Length(mKey) do
  begin
    mHash := Cardinal((UInt64(mHash xor Ord(mKey[mIndex])) * 16777619) and $FFFFFFFF);
  end;
  Result := 'Local\dpcc.Log.' + IntToHex(mHash, 8);
end;

class function TDpccRotatingLog.DefaultFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'dpcc'), 'Logs');
end;

function TDpccRotatingLog.FileName: string;
begin
  Result := TPath.Combine(FFolder, 'dpcc.log');
end;

procedure TDpccRotatingLog.Rotate;
var
  mIndex: Integer;
  mOlder, mNewer: string;
begin
  // dpcc.log → dpcc.1.log → … → dpcc.(Max-1).log; die älteste fällt weg.
  for mIndex := FMaxFiles - 1 downto 1 do
  begin
    mOlder := TPath.Combine(FFolder, Format('dpcc.%d.log', [mIndex]));
    if mIndex = 1 then
    begin
      mNewer := FileName;
    end
    else
    begin
      mNewer := TPath.Combine(FFolder, Format('dpcc.%d.log', [mIndex - 1]));
    end;
    if TFile.Exists(mOlder) then
    begin
      TFile.Delete(mOlder);
    end;
    if TFile.Exists(mNewer) then
    begin
      TFile.Move(mNewer, mOlder);
    end;
  end;
end;

/// <summary>Fehlermeldung fürs Protokoll: ohne den Ordner (enthält den Benutzernamen), einzeilig und gekürzt.</summary>
function TDpccRotatingLog.Clean(const AText: string): string;
begin
  Result := TDpccGuard.SafeMessage(StringReplace(AText, ExcludeTrailingPathDelimiter(FFolder), 'Logs',
    [rfReplaceAll, rfIgnoreCase]));
end;

/// <summary>Rotieren und Anhängen unter der prozessübergreifenden Sperre; '' = geschrieben, sonst der Grund. Nur
/// unter FLock.</summary>
function TDpccRotatingLog.RotateIfFull(const AStamp: string): string;
begin
  Result := '';
  if not TFile.Exists(FileName) or (TFile.GetSize(FileName) < FMaxBytes) then
  begin
    Exit;
  end;
  try
    Rotate;
    FRotateError := '';
  except
    // Rotieren gescheitert (z. B. eine ältere Datei ist woanders gesperrt): trotzdem anhängen, die Datei wird
    // dann größer. Früher ging dabei auch die Zeile verloren, bei jedem Versuch wieder.
    on E: Exception do
    begin
      if E.Message <> FRotateError then
      begin
        FRotateError := E.Message;
        Result := AStamp + 'Protokoll: Rotieren gescheitert (' + E.ClassName + ': ' + Clean(E.Message) +
          '); schreibe weiter in dpcc.log' + sLineBreak;
      end;
    end;
  end;
end;

procedure TDpccRotatingLog.WriteLocked(const ALine: string);
var
  mStamp, mLines: string;
begin
  mStamp := FormatDateTime('yyyy-mm-dd hh":"nn":"ss.zzz', Now) + ' ';
  mLines := RotateIfFull(mStamp);
  if FFailed > 0 then
  begin
    mLines := mLines + mStamp + Format('Protokoll: %d Zeilen nicht geschrieben (zuletzt: %s)',
      [FFailed, Clean(FLastError)]) + sLineBreak;
  end;
  TFile.AppendAllText(FileName, mLines + ALine, TEncoding.UTF8);
end;

function TDpccRotatingLog.AppendLine(const ALine: string): string;
var
  mLock: TMutex;
  mOwned: Boolean;
begin
  Result := '';
  try
    ForceDirectories(FFolder);
    // Je Zeile öffnen statt im Objekt halten: Der Ordner kann wechseln (Tests stellen ihn um), und eine gehaltene
    // Sperre bliebe samt Pfad stehen.
    mLock := TMutex.Create(nil, False, MutexName(FFolder));
    try
      // Abgebrochen heißt: Ein anderer Prozess endete beim Schreiben; die Sperre gehört dann uns.
      mOwned := mLock.WaitFor(cLockTimeoutMs) in [wrSignaled, wrAbandoned];
      try
        WriteLocked(ALine);
      finally
        if mOwned then
        begin
          mLock.Release;
        end;
      end;
    finally
      mLock.Free;
    end;
  except
    on E: Exception do
    begin
      Result := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

procedure TDpccRotatingLog.Add(const AText: string);
var
  mFailure, mError: string;
  mNotify: Boolean;
begin
  FLock.Enter;
  try
    mFailure := AppendLine(FormatDateTime('yyyy-mm-dd hh":"nn":"ss.zzz', Now) + ' ' + FRedactor.Redact(AText) +
      sLineBreak);
    if mFailure = '' then
    begin
      mNotify := FFailed > 0;
      FFailed := 0;
      FLastError := '';
    end
    else
    begin
      Inc(FFailed);
      Inc(FLost);
      mNotify := mFailure <> FLastError;
      FLastError := mFailure;
    end;
    mError := FLastError;
  finally
    FLock.Leave;
  end;
  // Außerhalb der Sperren: Der Empfänger darf selbst protokollieren.
  if mNotify and Assigned(FOnError) then
  begin
    FOnError(mError);
  end;
end;

{ TDpccFuse }

constructor TDpccFuse.Create;
begin
  Create(nil);
end;

constructor TDpccFuse.Create(const AClock: TFunc<TDateTime>);
begin
  inherited Create;
  FClock := AClock;
  if not Assigned(FClock) then
  begin
    FClock :=
      function: TDateTime
      begin
        Result := Now;
      end;
  end;
  FLock := TCriticalSection.Create;
  FProviderFailures := TDictionary<string, TArray<TDateTime>>.Create;
  FProvidersTripped := TDictionary<string, string>.Create;
  FSlowLogged := TDictionary<string, TDateTime>.Create;
  FSlowSkipped := TDictionary<string, Integer>.Create;
end;

destructor TDpccFuse.Destroy;
begin
  FSlowSkipped.Free;
  FSlowLogged.Free;
  FProvidersTripped.Free;
  FProviderFailures.Free;
  FLock.Free;
  inherited;
end;

function TDpccFuse.Count(var AStamps: TArray<TDateTime>): Boolean;
var
  mTime, mStamp: TDateTime;
  mRecent: TArray<TDateTime>;
begin
  mTime := FClock;
  mRecent := nil;
  for mStamp in AStamps do
  begin
    if MinutesBetween(mTime, mStamp) < cWindowMinutes then
    begin
      mRecent := mRecent + [mStamp];
    end;
  end;
  mRecent := mRecent + [mTime];
  AStamps := mRecent;
  Result := Length(mRecent) >= cLimit;
end;

function TDpccFuse.Failed(AFeature: TDpccFeature): Boolean;
var
  mRepeated: Boolean;
  mSkipped: Integer;
begin
  Result := Failed(AFeature, '', mRepeated, mSkipped);
end;

function TDpccFuse.Failed(AFeature: TDpccFeature; const AKey: string; out ARepeat: Boolean;
  out ASkipped: Integer): Boolean;
var
  mTime: TDateTime;
begin
  FLock.Enter;
  try
    Result := False;
    ARepeat := False;
    ASkipped := 0;
    mTime := FClock;
    // Fester Abstand ab dem zuletzt gezählten, nicht gleitend: Ein Fehler, der bei jedem Zeichnen kommt, zählt so
    // einmal je RepeatMs und löst die Sicherung weiterhin aus.
    if (AKey <> '') and (AKey = FLastKey[AFeature]) and
      (MilliSecondsBetween(mTime, FLastCounted[AFeature]) < cRepeatMs) then
    begin
      ARepeat := True;
      Inc(FRepeats[AFeature]);
      Exit;
    end;
    ASkipped := FRepeats[AFeature];
    FLastKey[AFeature] := AKey;
    FLastCounted[AFeature] := mTime;
    FRepeats[AFeature] := 0;
    if AFeature in FTripped then
    begin
      Exit;
    end;
    if Count(FFailures[AFeature]) then
    begin
      Include(FTripped, AFeature);
      Result := True;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccFuse.ProviderFailed(const AName: string): Boolean;
var
  mKey: string;
  mStamps: TArray<TDateTime>;
begin
  mKey := AnsiLowerCase(AName);
  FLock.Enter;
  try
    Result := False;
    if FProvidersTripped.ContainsKey(mKey) then
    begin
      Exit;
    end;
    if not FProviderFailures.TryGetValue(mKey, mStamps) then
    begin
      mStamps := nil;
    end;
    if Count(mStamps) then
    begin
      FProvidersTripped.Add(mKey, AName);
      Result := True;
    end;
    FProviderFailures.AddOrSetValue(mKey, mStamps);
  finally
    FLock.Leave;
  end;
end;

function TDpccFuse.ProviderSlow(const AName: string; out ASkipped: Integer): Boolean;
var
  mKey: string;
  mTime, mLogged: TDateTime;
begin
  mKey := AnsiLowerCase(AName);
  FLock.Enter;
  try
    mTime := FClock;
    if not FSlowSkipped.TryGetValue(mKey, ASkipped) then
    begin
      ASkipped := 0;
    end;
    Result := not FSlowLogged.TryGetValue(mKey, mLogged) or (SecondsBetween(mTime, mLogged) >= cSlowLogSeconds);
    if Result then
    begin
      FSlowLogged.AddOrSetValue(mKey, mTime);
      FSlowSkipped.AddOrSetValue(mKey, 0);
    end
    else
    begin
      FSlowSkipped.AddOrSetValue(mKey, ASkipped + 1);
      ASkipped := 0;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccFuse.ProviderTripped(const AName: string): Boolean;
begin
  FLock.Enter;
  try
    Result := FProvidersTripped.ContainsKey(AnsiLowerCase(AName));
  finally
    FLock.Leave;
  end;
end;

function TDpccFuse.TrippedProviders: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FProvidersTripped.Values.ToArray;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccFuse.ResetProvider(const AName: string);
var
  mKey: string;
begin
  mKey := AnsiLowerCase(AName);
  FLock.Enter;
  try
    FProvidersTripped.Remove(mKey);
    FProviderFailures.Remove(mKey);
  finally
    FLock.Leave;
  end;
end;

function TDpccFuse.Tripped(AFeature: TDpccFeature): Boolean;
begin
  FLock.Enter;
  try
    Result := AFeature in FTripped;
  finally
    FLock.Leave;
  end;
end;

function TDpccFuse.TrippedSet: TDpccFeatures;
begin
  FLock.Enter;
  try
    Result := FTripped;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccFuse.Reset(AFeature: TDpccFeature);
begin
  FLock.Enter;
  try
    Exclude(FTripped, AFeature);
    FFailures[AFeature] := nil;
    FLastKey[AFeature] := '';
    FRepeats[AFeature] := 0;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccFuse.Trip(AFeature: TDpccFeature);
begin
  FLock.Enter;
  try
    Include(FTripped, AFeature);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccFuse.ResetAll;
var
  mFeature: TDpccFeature;
begin
  for mFeature := Low(TDpccFeature) to High(TDpccFeature) do
  begin
    Reset(mFeature);
  end;
  FLock.Enter;
  try
    FProvidersTripped.Clear;
    FProviderFailures.Clear;
    FSlowLogged.Clear;
    FSlowSkipped.Clear;
  finally
    FLock.Leave;
  end;
end;

{ TDpccGuard }

class constructor TDpccGuard.Create;
begin
  FFuse := TDpccFuse.Create;
  FLog := TDpccRotatingLog.Create(TDpccRotatingLog.DefaultFolder);
end;

class destructor TDpccGuard.Destroy;
begin
  FOnWarning := nil;
  FStackOf := nil;
  FOnTripped := nil;
  FreeAndNil(FLog);
  FreeAndNil(FFuse);
end;

class function TDpccGuard.FeatureName(AFeature: TDpccFeature): string;
const
  cNames: array[TDpccLanguage, TDpccFeature] of string = (
    ('Vervollständigung', 'Parameter-Hint', 'Tooltip', 'Klammerpaare',
      'Probleme', 'Neuladen', 'Befehlspalette', 'Prüfung beim Speichern', 'Wächter', 'Server', 'Einstellungen', 'Menü',
      'Dateien', 'Inlay-Hints', 'Ergebnisfenster', 'Editorbefehle', 'Formulare', 'Compile-Ereignisse', 'Statusfeld',
      'Willkommensseite', 'Tastenkürzel-Tipps', 'Notizen', 'Lesezeichen',
      'Benachrichtigungen', 'Brotkrumenleiste', 'Gliederung', 'Mitlaufender Kopf', 'Minimap', 'Änderungsmarken',
      'dpcc-Spalte', 'Rekursionssymbole', 'Übersichtsleiste', 'Gleichen Text hervorheben', 'Mehrere Einfügemarken',
      'Bezeichner mitziehen', 'Code Lens', 'Navigationsverlauf', 'Definition einblenden', 'Einfügen mit uses-Ergänzung',
      'Markierung umschließen', 'Umschließung entfernen', 'Ausblenden am Element', 'dpcc-Suche', 'Units suchen',
      'Erzeugen-Menü', 'Kommentar und Muster fortsetzen', 'Schnellbefehle', 'Gehe zu Definition', 'Editorleiste',
      'Schnelle Lesezeichen', 'dpcc-Statusleiste', 'Architekturübersicht', 'Unit-Beziehungen',
      'Weg zwischen Symbolen', 'Projektaufgaben', 'Debuggen',
      'Austrittspunkte', 'Neu zugewiesene Variablen', 'Typ des Ausdrucks', 'Methodenreihenfolge',
      'Issue-Kennungen', 'Issues in der Zeilenhistorie', 'Code-Abfragen', 'Hotspots', 'Designer-Leiste', 'Tracker',
      'Willkommensseite: Aktualisieren', 'Regionen falten', 'Einrückung beim Tippen',
      'Gelernte Vorschläge'),
    ('Completion', 'Parameter hint', 'Tooltip', 'Bracket pairs',
      'Problems', 'Reload', 'Command palette', 'Check on save', 'Watchdog', 'Server', 'Settings', 'Menu',
      'Files', 'Inlay hints', 'Results window', 'Editor commands', 'Forms', 'Compile events', 'Status field',
      'Welcome page', 'Shortcut tips', 'Notes', 'Bookmarks',
      'Notifications', 'Breadcrumbs', 'Outline', 'Sticky scroll', 'Minimap', 'Change marks',
      'dpcc column', 'Recursion markers', 'Overview ruler', 'Highlight same text', 'Multiple carets',
      'Linked identifier editing', 'Code Lens', 'Navigation history', 'Peek definition', 'Paste with uses completion',
      'Surround selection', 'Remove surrounding', 'Hide at element', 'dpcc Search', 'Search units',
      'Generate menu', 'Continue comment and pattern', 'Quick commands', 'Go to definition', 'Editor toolbar',
      'Quick bookmarks', 'dpcc status bar', 'Architecture overview', 'Unit relations',
      'Path between symbols', 'Project tasks', 'Debugging',
      'Exit points', 'Reassigned variables', 'Type of expression', 'Method order',
      'Issue keys', 'Issues in line history', 'Code queries', 'Hotspots', 'Designer bar', 'Tracker',
      'Welcome page: updates', 'Region folding', 'Indent while typing',
      'Learned suggestions'));
begin
  Result := cNames[TDpccTextLanguage.Current, AFeature];
end;

class procedure TDpccGuard.Log(const AText: string);
begin
  if FLog <> nil then
  begin
    FLog.Add(AText);
  end;
end;

class function TDpccGuard.ErrorText(AE: Exception): string;
begin
  Result := AE.ClassName + ': ' + MessageText(AE.Message);
end;

class function TDpccGuard.MessageText(const AText: string): string;
begin
  Result := TLogMarks.Text(SafeMessage(AText));
end;

class procedure TDpccGuard.SetLogNames(AValue: Boolean);
begin
  if FLog <> nil then
  begin
    FLog.Redactor.Names := AValue;
  end;
end;

class function TDpccGuard.SafeMessage(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mCh: Char;
  mSpace: Boolean;
begin
  // Zeilenumbrüche und Steuerzeichen werden zu einem Leerzeichen; Folgen davon zu einem.
  mBuilder := TStringBuilder.Create;
  try
    mSpace := False;
    for mCh in AText do
    begin
      if CharInSet(mCh, [#0..#32]) then
      begin
        mSpace := True;
      end
      else
      begin
        if mSpace and (mBuilder.Length > 0) then
        begin
          mBuilder.Append(' ');
        end;
        mSpace := False;
        mBuilder.Append(mCh);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  if Length(Result) > cMaxMessageLength then
  begin
    Result := Copy(Result, 1, cMaxMessageLength) + '…';
  end;
end;

class function TDpccGuard.ErrorLine(const AWhere: string; AE: Exception): string;
var
  mTrace: string;
begin
  Result := Format('dpcc %s · Fehler in %s: %s', [TDpccPluginVersion.cVersion, AWhere, ErrorText(AE)]);
  // E.StackTrace nur mit installiertem Anbieter (JCL, madExcept); sonst der Mitschnitt des Plugins.
  mTrace := Trim(AE.StackTrace);
  if (mTrace = '') and Assigned(FStackOf) then
    try
      mTrace := Trim(FStackOf(AE));
    except
      // Sicherheitsnetz: Ein Fehler beim Auflösen darf die Fehlerzeile selbst nicht verhindern.
      on Inner: Exception do
        mTrace := 'nicht verfügbar (' + Inner.ClassName + ')';
    end;
  if mTrace <> '' then
  begin
    Result := Result + sLineBreak + '  Stack: ' + StringReplace(mTrace, sLineBreak, sLineBreak + '  ', [rfReplaceAll]);
  end;
end;

/// <summary>AText ins Protokoll und an TDpccGuard.OnWarning (Meldungsansicht).</summary>
procedure Warn(const AText: string);
begin
  TDpccGuard.Log(AText);
  if Assigned(TDpccGuard.FOnWarning) then
    try
      TDpccGuard.FOnWarning(TLogMarks.Plain(AText));
    except
      // Auch die Warnung darf nicht in die IDE durchschlagen.
    end;
end;

/// <summary>Klasse und Stelle (ExceptAddr) des gerade behandelten Fehlers; ohne Stelle Klasse und Meldung.
/// </summary>
function FailureKey(AE: Exception): string;
begin
  // ExceptAddr gehört zur gerade behandelten Ausnahme; Report läuft in deren except-Block.
  if ExceptAddr <> nil then
  begin
    Result := Format('%s@%p', [AE.ClassName, ExceptAddr]);
  end
  else
  begin
    Result := AE.ClassName + ': ' + AE.Message;
  end;
end;

class procedure TDpccGuard.Report(AFeature: TDpccFeature; AE: Exception);
var
  mFailure: TProc<TDpccFeature>;
  mTripped: TDpccGuardTripped;
  mFired, mRepeated: Boolean;
  mSkipped: Integer;
  mWhere: string;
begin
  mFired := False;
  mRepeated := False;
  mSkipped := 0;
  if FFuse <> nil then
  begin
    mFired := FFuse.Failed(AFeature, FailureKey(AE), mRepeated, mSkipped);
  end;
  // Derselbe Fehler kurz nach dem gezählten (etwa für jede Zeile eines Zeichendurchlaufs): nicht noch einmal
  // protokollieren und nicht zählen; die nächste gezählte Zeile nennt die Zahl.
  if mRepeated then
  begin
    Exit;
  end;
  mWhere := FeatureName(AFeature);
  if mSkipped > 0 then
  begin
    mWhere := Format('%s (seit der letzten Meldung %d Wiederholungen übergangen)', [mWhere, mSkipped]);
  end;
  Log(ErrorLine(mWhere, AE));
  mFailure := FOnFailure;
  if Assigned(mFailure) then
    try
      mFailure(AFeature);
    except
      // Die Meldung eines Fehlers darf selbst keinen auslösen.
    end;
  if not mFired then
  begin
    Exit;
  end;
  Warn(Format(UiText(TGuardText.FeatureTripped), [FeatureName(AFeature), TDpccFuse.cLimit, TDpccFuse.cWindowMinutes,
    TLogMarks.Text(SafeMessage(AE.Message))]));
  mTripped := FOnTripped;
  if Assigned(mTripped) then
    try
      mTripped(AFeature, SafeMessage(AE.Message));
    except
      // Auch der Eintrag in der Zentrale darf nicht in die IDE durchschlagen.
    end;
end;

class procedure TDpccGuard.ReportProvider(const AName: string; AE: Exception);
begin
  Log(ErrorLine('Quelle ' + AName, AE));
  if (FFuse <> nil) and FFuse.ProviderFailed(AName) then
  begin
    Warn(Format(UiText(TGuardText.SourceTripped), [AName, TDpccFuse.cLimit, TDpccFuse.cWindowMinutes,
      TLogMarks.Text(SafeMessage(AE.Message))]));
  end;
end;

class procedure TDpccGuard.ReportProvider(const AName, AMessage: string);
var
  mError: Exception;
begin
  mError := Exception.Create(AMessage);
  try
    ReportProvider(AName, mError);
  finally
    mError.Free;
  end;
end;

class procedure TDpccGuard.ReportProviderSlow(const AName, AText: string);
var
  mSkipped: Integer;
  mSuffix: string;
  mTiming: TDpccGuardTiming;
begin
  mTiming := FTiming;
  if mTiming <> nil then
  begin
    mTiming.ProviderSlow(AName);
  end;
  if (FFuse = nil) or not FFuse.ProviderSlow(AName, mSkipped) then
  begin
    Exit;
  end;
  mSuffix := '';
  if mSkipped > 0 then
  begin
    mSuffix := Format(' (dazu %d weitere seit der letzten Meldung)', [mSkipped]);
  end;
  Log(Format('Quelle %s langsam: %s%s; zählt nicht als Fehler', [AName, MessageText(AText), mSuffix]));
end;

class function TDpccGuard.RunProvider(const AName: string; const AProc: TProc): Boolean;
begin
  if ProviderDisabled(AName) then
  begin
    Exit(False);
  end;
  try
    AProc();
    Result := True;
  except
    on E: EAbort do
      Result := False;
    on E: Exception do
    begin
      ReportProvider(AName, E);
      Result := False;
    end;
  end;
end;

class function TDpccGuard.ProviderDisabled(const AName: string): Boolean;
begin
  Result := (FFuse <> nil) and FFuse.ProviderTripped(AName);
end;

class procedure TDpccGuard.EnableProvider(const AName: string);
begin
  if FFuse <> nil then
  begin
    FFuse.ResetProvider(AName);
  end;
  Log(Format('Quelle %s wieder eingeschaltet', [AName]));
end;

class function TDpccGuard.DisabledProviders: TArray<string>;
begin
  if FFuse = nil then
  begin
    Result := nil;
  end
  else
  begin
    Result := FFuse.TrippedProviders;
  end;
end;

type
  /// <summary>Was im Hauptthread gerade über TDpccGuard.Run bzw. RunIde läuft, innerstes oben. Nur der
  /// Hauptthread schreibt; der Einfrier-Wächter liest ohne Sperre (ganze Zahlen, Index begrenzt).</summary>
  TRunningStack = class
  public const
    cMax = 32;
    /// <summary>Eintrag von RunIde: Arbeit der IDE, keine Funktion von dpcc.</summary>
    cIde = -1;
  private class var
    FEntries: array[0..cMax - 1] of Integer;
    FDepth: Integer;
  public
    /// <summary>Im Hauptthread AEntry (Ord eines Features oder cIde) auflegen; Ergebnis für Leave, -1 in anderen
    /// Threads.</summary>
    class function Enter(AEntry: Integer): Integer; static;
    class procedure Leave(ADepth: Integer); static;
    /// <summary>Innerster Eintrag; False, wenn nichts läuft.</summary>
    class function Top(out AEntry: Integer): Boolean; static;
  end;

class function TRunningStack.Enter(AEntry: Integer): Integer;
begin
  Result := -1;
  if TThread.CurrentThread.ThreadID <> MainThreadID then
  begin
    Exit;
  end;
  Result := FDepth;
  // Erst der Eintrag, dann die Tiefe: Der Wächter liest nie einen alten Eintrag unter der neuen Tiefe.
  if Result < cMax then
  begin
    FEntries[Result] := AEntry;
  end;
  FDepth := Result + 1;
end;

class procedure TRunningStack.Leave(ADepth: Integer);
begin
  if ADepth >= 0 then
  begin
    FDepth := ADepth;
  end;
end;

class function TRunningStack.Top(out AEntry: Integer): Boolean;
var
  mDepth: Integer;
begin
  AEntry := 0;
  mDepth := FDepth;
  if mDepth > cMax then
  begin
    mDepth := cMax;
  end;
  Result := mDepth > 0;
  if Result then
  begin
    AEntry := FEntries[mDepth - 1];
  end;
end;

function RunGuarded(AFeature: TDpccFeature; const AProc: TProc): Boolean;
begin
  try
    AProc();
    Result := True;
  except
    on E: EAbort do
      Result := False;
    on E: Exception do
    begin
      TDpccGuard.Report(AFeature, E);
      Result := False;
    end;
  end;
end;

class function TDpccGuard.CurrentFeatureName: string;
var
  mEntry: Integer;
begin
  Result := '';
  if TRunningStack.Top(mEntry) and (mEntry >= Ord(Low(TDpccFeature))) and (mEntry <= Ord(High(TDpccFeature))) then
  begin
    Result := FeatureName(TDpccFeature(mEntry));
  end;
end;

class function TDpccGuard.Run(AFeature: TDpccFeature; const AProc: TProc): Boolean;
var
  mTiming: TDpccGuardTiming;
  mToken, mDepth: Integer;
begin
  if Disabled(AFeature) then
  begin
    Exit(False);
  end;
  mDepth := TRunningStack.Enter(Ord(AFeature));
  try
    // Einmal lesen: Schaltet der Diagnosemodus mitten im Aufruf um, endet der Aufruf beim selben Rekorder.
    mTiming := FTiming;
    if mTiming = nil then
    begin
      Exit(RunGuarded(AFeature, AProc));
    end;
    mToken := mTiming.Enter;
    try
      Result := RunGuarded(AFeature, AProc);
    finally
      mTiming.Leave(AFeature, mToken);
    end;
  finally
    TRunningStack.Leave(mDepth);
  end;
end;

class procedure TDpccGuard.RunIde(const AProc: TProc);
var
  mTiming: TDpccGuardTiming;
  mDepth: Integer;
begin
  mDepth := TRunningStack.Enter(TRunningStack.cIde);
  try
    mTiming := FTiming;
    if mTiming = nil then
    begin
      AProc();
      Exit;
    end;
    mTiming.ModalBegin;
    try
      AProc();
    finally
      mTiming.ModalEnd;
    end;
  finally
    TRunningStack.Leave(mDepth);
  end;
end;

{ TDpccGuardTiming }

procedure TDpccGuardTiming.ModalBegin;
begin
  // Ohne Rekorder nichts zu tun.
end;

procedure TDpccGuardTiming.ModalEnd;
begin
  // Ohne Rekorder nichts zu tun.
end;

class function TDpccGuard.Disabled(AFeature: TDpccFeature): Boolean;
begin
  Result := (FFuse <> nil) and FFuse.Tripped(AFeature);
end;

class function TDpccGuard.DisabledSet: TDpccFeatures;
begin
  if FFuse = nil then
  begin
    Result := [];
  end
  else
  begin
    Result := FFuse.TrippedSet;
  end;
end;

class procedure TDpccGuard.Disable(AFeature: TDpccFeature);
begin
  if FFuse <> nil then
  begin
    FFuse.Trip(AFeature);
  end;
  Log(Format('%s im Diagnose-Fenster bis zum Neustart ausgeschaltet', [FeatureName(AFeature)]));
end;

class procedure TDpccGuard.Enable(AFeature: TDpccFeature);
begin
  if FFuse <> nil then
  begin
    FFuse.Reset(AFeature);
  end;
  Log(Format('%s wieder eingeschaltet', [FeatureName(AFeature)]));
end;

class procedure TDpccGuard.EnableAll;
var
  mFeature: TDpccFeature;
  mName: string;
begin
  for mFeature in DisabledSet do
  begin
    Enable(mFeature);
  end;
  for mName in DisabledProviders do
  begin
    EnableProvider(mName);
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Diagnostics.Guard', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
