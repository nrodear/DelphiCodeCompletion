unit dpcc.IDE.Forms.Designer;

// Formularinhalt aus dem Designer an den Server (#402). Bei offenem Formular
// liegt der aktuelle Stand im Designer, nicht in der .dfm auf der Platte.
// - Senden: Jedes offene Formular geht als eigenes Dokument (uri der .dfm,
//   didOpen/didChange) an den Server; der liest offene Dokumente vor der
//   Platte. Der Text entsteht wie beim Speichern (TDpccFormText), die Namen
//   der Ereignis-Handler liefert der Designer (IDesigner.GetMethodName).
// - Änderungen im Designer (Komponente eingefügt, gelöscht, umbenannt,
//   Ereignis zugewiesen) meldet IDesignNotification; 500 ms danach geht der
//   neue Text an den Server, nur für die geänderten Formulare (vorher wurde
//   jedes offene Formular neu in Text gewandelt, im Diagnose-Fenster bis
//   266 ms je Änderung). Ein geschlossenes Formular meldet dpcc mit
//   didClose ab, danach gilt wieder die Datei. Nach einem Serverneustart
//   gehen alle Formulare neu an den Server.
// - Änderungen des Servers an offenen Formularen (#397, #309: Check, Apply, IsOpen, SentText; Ereignisse und
//   Eigenschaften über RTTI im Designer) sind entfallen: Sie hatten keinen Aufrufer mehr. Damit merkt sich dpcc auch
//   den gesendeten Text nicht mehr (früher FTexts, Grundlage für Check).
// - Nur Formulare mit offenem Designer (Hänger beim Öffnen einer Formular-Unit): dpcc geht nicht mehr über
//   ModuleFileEditors aller Module (das konnte Designer laden), sondern merkt sich die Designer aus DesignerOpened
//   bzw. der ersten Änderung (beim Laden des Plugins schon offene VCL-Designer aus Screen.CustomForms). Der Abgleich
//   aller Formulare (Start, neue Sitzung) verteilt sich auf die Takte des Timers, höchstens cFormsPerTick je Takt.
// - Formulardatei je Designer (doppelte Einträge der Vervollständigung): Sie kommt aus den Moduldateien des
//   Designers selbst (IDesigner.ModuleFileNames, TDpccFormText.FormFileOf), einmal je Wurzel ermittelt und in
//   FDesigners gemerkt. Vorher suchte FindFormModule das Modul über den Namen der Wurzel; in einer Projektgruppe
//   heißen mehrere Formulare "Form1", und der Text von Formular A ging als .dfm von B an den Server. Ohne bekannte
//   Datei sendet dpcc das Formular nicht und schreibt eine Zeile ins Diagnoselog; meldet ein neuer Designer eine
//   Datei, die noch ein alter hält, gilt der neue.
// - Ohne spürbare Arbeit im Hauptthread (IDE hängt nicht beim Laden von Formularen): Der Hauptthread schreibt nur die
//   Komponenten binär in einen Speicherstrom (TDpccFormText.WriteBinary; Komponenten und GetMethodName nur dort).
//   Gleicher Fingerabdruck (Größe, Hash) wie beim letzten Mal: fertig. Sonst wandelt ein Thread aus FThreads den
//   kopierten Strom in Text (ObjectBinaryToText, der teure Teil bei Bildlisten und Picture.Data); das Ergebnis kommt
//   über TDpccMainThread.Queue zurück. Ist die Sitzung dann noch dieselbe, sendet ein Arbeiter aus TDpccTimeLimit
//   (Post, ohne Warten) den Text (Session.Sync: Diff bzw. didOpen). Sync ist threadsicher (FDocLock der Sitzung, wie
//   bei der Vervollständigung); der Stopp einer Sitzung wartet auf diese Arbeiter (TDpccTimeLimit.WaitIdle), bevor er
//   sie freigibt. Darum sendet nicht schon der Umwandlungs-Thread: Der kann länger laufen, als der Stopp wartet.
//   Die Threads halten nur Kopien (Strom, Dateiname, Auftrag) und beim Senden die Sitzung, nie dieses Objekt, den
//   Designer oder Komponenten. Beim Entladen wartet Destroy begrenzt auf FThreads (TDpccThreadList).
// - Reihenfolge je Formular (TDpccFormSyncPlan): höchstens ein Auftrag je Datei, insgesamt höchstens zwei; eine
//   Änderung währenddessen läuft danach genau einmal (nur der neueste Stand). Neue Sitzung: Epoche wechselt, laufende
//   Ergebnisse werden verworfen. Schließt ein Formular während seines Auftrags, geht didClose erst nach dessen Senden.
// - Abgleich aller (Start, neue Sitzung): höchstens cFormsPerTick je Takt, ein großes Formular (letzter Strom ab
//   cLargeFormBytes oder noch nie gemessen) allein. Der 500-ms-Takt läuft weiter dauernd: Er bemerkt eine neue
//   Sitzung (es gibt keine Meldung dafür); ohne Arbeit kostet er nur den Vergleich der Sitzung.
// Hauptthread; Umwandeln und Senden im Hintergrund wie oben.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  DesignIntf,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Forms.Sync,
  dpcc.Core.Diagnostics.ThreadList;

type
  TDpccIdeForms = class
  private type
    TNotification = class(TInterfacedObject, IDesignNotification)
    private
      FOwner: TDpccIdeForms;
    public
      procedure ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemsModified(const ADesigner: IDesigner);
      procedure SelectionChanged(const ADesigner: IDesigner; const ASelection: IDesignerSelections);
      procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
      procedure DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
    end;

    /// <summary>Offener Designer mit seiner Formulardatei ('' = noch nicht bestimmt).</summary>
    TOpenForm = record
      Designer: IDesigner;
      FileName: string;
      /// <summary>Unbekannte Datei schon ins Diagnoselog geschrieben.</summary>
      Reported: Boolean;
    end;
  private class var
    FCurrent: TDpccIdeForms;
  private
    FSessionOf: TFunc<TLspSession>;
    FLog: TProc<string>;
    FNotification: TNotification;
    FNotificationRef: IDesignNotification;
    FTimer: TTimer;
    FDirty: Boolean;
    /// <summary>Alle Formulare senden (Start, neue Sitzung, Änderung ohne Designer); sonst nur FDirtyRoots.
    /// </summary>
    FAll: Boolean;
    /// <summary>Wurzeln der Formulare, die sich seit dem letzten Senden geändert haben; nur verglichen, nie
    /// benutzt (die Komponente kann inzwischen frei sein).</summary>
    FDirtyRoots: TList<TComponent>;
    FLastSession: TLspSession;
    /// <summary>Wurzelkomponente → Formulardatei, für DesignerClosed.</summary>
    FRoots: TDictionary<TComponent, string>;
    /// <summary>Offene Designer je Wurzel samt Formulardatei (DesignerOpened bis DesignerClosed).</summary>
    FDesigners: TDictionary<TComponent, TOpenForm>;
    /// <summary>Wurzeln, die der laufende Abgleich aller Formulare noch senden muss.</summary>
    FPendingAll: TList<TComponent>;
    /// <summary>Reihenfolge der Aufträge je Formulardatei.</summary>
    FPlan: TDpccFormSyncPlan;
    /// <summary>Umwandlungs-Threads (Binärstrom → Text); Destroy wartet begrenzt auf sie.</summary>
    FThreads: TDpccThreadList;
    procedure Tick(Sender: TObject);
    /// <summary>Laufende Sitzung oder nil.</summary>
    function CurrentSession: TLspSession;
    /// <summary>Auftrag beginnen: Umwandeln in Text im Hintergrund.</summary>
    procedure StartJob(const AJob: TDpccFormSyncJob);
    /// <summary>Text fertig (Hauptthread): Senden im Hintergrund anstoßen oder den Auftrag abschließen.</summary>
    procedure SendConverted(const AJob: TDpccFormSyncJob; const AText, AError: string);
    /// <summary>Auftrag abschließen: geschlossenes Formular abmelden, nächsten starten.</summary>
    procedure Settle(const AJob: TDpccFormSyncJob; ASucceeded: Boolean; const AText: string);
    /// <summary>Rückmeldungen der Threads (über TDpccMainThread.Queue); ohne lebendes Objekt verworfen.</summary>
    class procedure Converted(const AJob: TDpccFormSyncJob; const AText, AError: string); static;
    class procedure Sent(const AJob: TDpccFormSyncJob; const AText: string; ASucceeded: Boolean;
      const AError: string); static;
    /// <summary>Formular von ADesigner geändert; nil: welches, ist unbekannt (alle senden).</summary>
    procedure Changed(const ADesigner: IDesigner);
    /// <summary>ADesigner ist offen: merken, die Formulardatei beim ersten Mal (bzw. solange unbekannt) ermitteln.
    /// </summary>
    procedure Remember(const ADesigner: IDesigner);
    /// <summary>Andere Wurzeln, die noch AFileName halten (alter Designer derselben Datei), vergessen.</summary>
    procedure ReleaseOthers(ARoot: TComponent; const AFileName: string);
    procedure Closed(ARoot: TComponent);
    /// <summary>Beim Laden schon offene VCL-Designer (Screen.CustomForms) merken.</summary>
    procedure ScanOpenDesigners;
    /// <summary>Abgleich aller offenen Formulare beginnen; gesendet wird in SyncPending.</summary>
    procedure StartAll;
    /// <summary>Höchstens AMax Formulare des Abgleichs aller anstoßen, ein großes allein.</summary>
    procedure SyncPending(AMax: Integer);
    /// <summary>Nur die geänderten Formulare (FDirtyRoots) anstoßen.</summary>
    procedure SyncDirty;
    /// <summary>Binärstrom von ARoot (Hauptthread); bei neuem Stand Auftrag anstoßen.</summary>
    procedure SyncForm(ARoot: TComponent; const ADesigner: IDesigner);
    /// <summary>Formulardatei des offenen Designers zu ARoot (gemerkt in FDesigners); '' wenn unbekannt.</summary>
    function FileNameOf(ARoot: TComponent): string;
    procedure Log(const AText: string);
  public
    /// <summary>ASessionOf: laufende Sitzung, ohne den Server zu starten; ALog: Diagnoseprotokoll.</summary>
    constructor Create(const ASessionOf: TFunc<TLspSession>; const ALog: TProc<string>);
    destructor Destroy; override;
  end;

implementation

uses
  Vcl.Forms,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Hangs,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.TimeLimit,
  dpcc.Core.Forms.Text,
  dpcc.IDE.Foundation.EditorSnapshot;

const
  cSyncDelayMs = 500;
  /// <summary>Takt, solange der Abgleich aller Formulare läuft.</summary>
  cPendingIntervalMs = 100;
  /// <summary>Höchstens so viele Formulare je Takt beim Abgleich aller.</summary>
  cFormsPerTick = 2;
  /// <summary>Ab dieser Größe des letzten Binärstroms gilt ein Formular als groß: beim Abgleich aller allein im Takt.
  /// </summary>
  cLargeFormBytes = 64 * 1024;

/// <summary>Formulardatei des Designers ADesigner aus seinen eigenen Moduldateien (IDesigner.ModuleFileNames), nicht
/// über den Namen der Wurzel: Formularnamen sind in einer Projektgruppe nicht eindeutig (mehrere "Form1"). Fasst
/// weder Module noch ihre Editoren an (die könnten einen Designer laden). '' wenn unbekannt.</summary>
function DesignerFormFile(const ADesigner: IDesigner): string;
var
  mImplFileName, mIntfFileName, mFormFileName: string;
begin
  Result := '';
  if ADesigner = nil then
  begin
    Exit;
  end;
  mImplFileName := '';
  mIntfFileName := '';
  mFormFileName := '';
  ADesigner.ModuleFileNames(mImplFileName, mIntfFileName, mFormFileName);
  Result := TDpccFormText.FormFileOf(mImplFileName, mFormFileName,
    function(AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end);
end;

/// <summary>Binärstrom von ARoot mit den Handler-Namen des Designers; nur im Hauptthread. Leer ohne Wurzel.</summary>
function BinaryOf(ARoot: TComponent; const ADesigner: IDesigner): TBytes;
var
  mDesigner: IDesigner;
begin
  Result := nil;
  if (ARoot = nil) or (ADesigner = nil) then
  begin
    Exit;
  end;
  mDesigner := ADesigner;
  Result := TDpccFormText.WriteBinary(ARoot,
    function(AMethod: TMethod): string
    begin
      Result := mDesigner.GetMethodName(AMethod);
    end);
end;

/// <summary>Umwandeln im Hintergrund (Thread aus FThreads). Fängt nur den Auftrag ein (Kopie), nie das
/// Formular-Objekt; das Ergebnis geht über TDpccMainThread.Queue zurück (beim Entladen verworfen).</summary>
function ConvertWork(const AJob: TDpccFormSyncJob): TProc;
var
  mJob: TDpccFormSyncJob;
begin
  mJob := AJob;
  Result :=
    procedure
    var
      mText, mError: string;
    begin
      TThread.NameThreadForDebugging('dpcc.FormText');
      mText := '';
      mError := '';
      try
        if not TDpccShutdown.Signalled then
        begin
          mText := TDpccFormText.BinaryToText(mJob.Binary);
        end;
      except
        on E: Exception do
        begin
          mError := E.ClassName + ': ' + E.Message;
        end;
      end;
      // Den Strom braucht niemand mehr.
      mJob.Binary := nil;
      TDpccMainThread.Queue(TDpccFeature.Forms,
        procedure
        begin
          TDpccIdeForms.Converted(mJob, mText, mError);
        end);
    end;
end;

/// <summary>Senden im Hintergrund (Arbeiter aus TDpccTimeLimit). ASession lebt, bis der Stopp auf diese Arbeiter
/// gewartet hat (TDpccTimeLimit.WaitIdle); Sync ist threadsicher (FDocLock). Das Ergebnis geht über
/// TDpccMainThread.Queue zurück.</summary>
function SendWork(ASession: TLspSession; const AJob: TDpccFormSyncJob; const AText: string): TProc;
var
  mSession: TLspSession;
  mJob: TDpccFormSyncJob;
  mText: string;
begin
  mSession := ASession;
  mJob := AJob;
  mJob.Binary := nil;
  mText := AText;
  Result :=
    procedure
    var
      mOk: Boolean;
      mError: string;
    begin
      mOk := False;
      mError := '';
      try
        if not TDpccShutdown.Signalled then
        begin
          mSession.Sync(mJob.FileName, mText);
          mOk := True;
        end;
      except
        on E: Exception do
        begin
          mError := E.ClassName + ': ' + E.Message;
        end;
      end;
      TDpccMainThread.Queue(TDpccFeature.Forms,
        procedure
        begin
          TDpccIdeForms.Sent(mJob, mText, mOk, mError);
        end);
    end;
end;

{ TDpccIdeForms.TNotification }

procedure TDpccIdeForms.TNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
  begin
    FOwner.Changed(ADesigner);
  end;
end;

procedure TDpccIdeForms.TNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
  begin
    FOwner.Changed(ADesigner);
  end;
end;

procedure TDpccIdeForms.TNotification.ItemsModified(const ADesigner: IDesigner);
begin
  if FOwner <> nil then
  begin
    FOwner.Changed(ADesigner);
  end;
end;

procedure TDpccIdeForms.TNotification.SelectionChanged(const ADesigner: IDesigner;
  const ASelection: IDesignerSelections);
begin
end;

procedure TDpccIdeForms.TNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
  if FOwner <> nil then
  begin
    FOwner.Changed(ADesigner);
  end;
end;

procedure TDpccIdeForms.TNotification.DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
var
  mOwner: TDpccIdeForms;
  mRoot: TComponent;
begin
  mOwner := FOwner;
  if (mOwner = nil) or (ADesigner = nil) then
  begin
    Exit;
  end;
  mRoot := ADesigner.Root;
  TDpccGuard.Run(TDpccFeature.Forms,
    procedure
    var
      mActivity: IInterface;
    begin
      mActivity := TDpccActivity.Scope('Formular geschlossen');
      mOwner.Closed(mRoot);
    end);
end;

{ TDpccIdeForms }

constructor TDpccIdeForms.Create(const ASessionOf: TFunc<TLspSession>; const ALog: TProc<string>);
begin
  inherited Create;
  FSessionOf := ASessionOf;
  FLog := ALog;
  FRoots := TDictionary<TComponent, string>.Create;
  FDesigners := TDictionary<TComponent, TOpenForm>.Create;
  FPendingAll := TList<TComponent>.Create;
  FDirtyRoots := TList<TComponent>.Create;
  FPlan := TDpccFormSyncPlan.Create;
  FThreads := TDpccThreadList.Create;
  ScanOpenDesigners;
  FNotification := TNotification.Create;
  FNotification.FOwner := Self;
  FNotificationRef := FNotification;
  RegisterDesignNotification(FNotificationRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cSyncDelayMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  FDirty := True;
  FAll := True;
  FCurrent := Self;
end;

destructor TDpccIdeForms.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  FTimer.Free;
  FNotification.FOwner := nil;
  UnregisterDesignNotification(FNotificationRef);
  FNotificationRef := nil;
  // Begrenzt auf laufende Umwandlungen warten (TDpccShutdown.cStopMs); wer dann noch läuft, hält die dpcc-Packages
  // geladen. Ihre Rückmeldungen finden FCurrent = nil bzw. sind beim Entladen schon verworfen.
  FThreads.Free;
  FPlan.Free;
  FDirtyRoots.Free;
  FPendingAll.Free;
  FDesigners.Free;
  FRoots.Free;
  inherited;
end;

procedure TDpccIdeForms.Log(const AText: string);
begin
  if Assigned(FLog) then
  begin
    FLog(AText);
  end;
end;

procedure TDpccIdeForms.Remember(const ADesigner: IDesigner);
var
  mRoot: TComponent;
  mForm: TOpenForm;
begin
  if ADesigner = nil then
  begin
    Exit;
  end;
  mRoot := ADesigner.Root;
  if mRoot = nil then
  begin
    Exit;
  end;
  // Datei schon bekannt: nur den Designer nachführen. Remember läuft bei jeder Änderung (beim Ziehen je
  // Mausbewegung); die Datei wird je Wurzel einmal ermittelt.
  if FDesigners.TryGetValue(mRoot, mForm) and (mForm.FileName <> '') then
  begin
    if mForm.Designer <> ADesigner then
    begin
      mForm.Designer := ADesigner;
      FDesigners.AddOrSetValue(mRoot, mForm);
    end;
    Exit;
  end;
  mForm.Designer := ADesigner;
  mForm.FileName := '';
  try
    mForm.FileName := DesignerFormFile(ADesigner);
  except
    on E: Exception do
      Log('Formulardatei nicht ermittelt: ' + E.Message);
  end;
  if mForm.FileName <> '' then
  begin
    mForm.Reported := False;
    ReleaseOthers(mRoot, mForm.FileName);
  end;
  FDesigners.AddOrSetValue(mRoot, mForm);
end;

procedure TDpccIdeForms.ReleaseOthers(ARoot: TComponent; const AFileName: string);
var
  mPair: TPair<TComponent, TOpenForm>;
  mStale: TArray<TComponent>;
  mOther: TComponent;
begin
  mStale := nil;
  for mPair in FDesigners do
  begin
    if (mPair.Key <> ARoot) and SameText(mPair.Value.FileName, AFileName) then
    begin
      mStale := mStale + [mPair.Key];
    end;
  end;
  for mOther in mStale do
  begin
    // Ein später DesignerClosed des alten Designers meldet die Datei so nicht beim Server ab.
    FDesigners.Remove(mOther);
    FPendingAll.Remove(mOther);
    FDirtyRoots.Remove(mOther);
    FRoots.Remove(mOther);
    Log(Format('Formular %s: älterer Designer derselben Datei ersetzt', [ExtractFileName(AFileName)]));
  end;
end;

procedure TDpccIdeForms.ScanOpenDesigners;
var
  mIndex: Integer;
  mForm: TCustomForm;
  mDesigner: IDesigner;
begin
  // Nur VCL-Formulare mit gesetztem Designer; andere (FireMonkey) kommen mit DesignerOpened bzw. der ersten
  // Änderung dazu.
  try
    for mIndex := 0 to Screen.CustomFormCount - 1 do
    begin
      mForm := Screen.CustomForms[mIndex];
      if (mForm <> nil) and (mForm.Designer <> nil) and Supports(mForm.Designer, IDesigner, mDesigner) then
      begin
        Remember(mDesigner);
      end;
    end;
  except
    on E: Exception do
      Log('Offene Designer nicht gelesen: ' + E.Message);
  end;
end;

procedure TDpccIdeForms.Changed(const ADesigner: IDesigner);
var
  mRoot: TComponent;
  mActivity: IInterface;
begin
  mActivity := TDpccActivity.Scope('Designer-Meldung');
  mRoot := nil;
  if ADesigner <> nil then
  begin
    mRoot := ADesigner.Root;
    Remember(ADesigner);
  end;
  if mRoot = nil then
  begin
    FAll := True;
  end
  else if not FDirtyRoots.Contains(mRoot) then
  begin
    FDirtyRoots.Add(mRoot);
  end;
  // Der Designer schreibt Felder und Methoden ohne Editorereignis in die Unit.
  TDpccEditorSnapshots.Invalidate;
  // Erst nach einer Pause senden: Beim Ziehen kommt eine Meldung je Mausbewegung.
  FDirty := True;
  FTimer.Enabled := False;
  FTimer.Interval := cSyncDelayMs;
  FTimer.Enabled := True;
end;

function TDpccIdeForms.CurrentSession: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
  begin
    Result := FSessionOf();
  end;
end;

procedure TDpccIdeForms.Tick(Sender: TObject);
var
  mSession: TLspSession;
  mActivity: IInterface;
begin
  mActivity := TDpccActivity.Scope('Formular-Abgleich');
  TDpccGuard.Run(TDpccFeature.Forms,
    procedure
    begin
      mSession := CurrentSession;
      if mSession = nil then
      begin
        FLastSession := nil;
        FPendingAll.Clear;
        Exit;
      end;
      // Neue Sitzung (Serverstart, Neustart): alles neu schicken; Ergebnisse laufender Aufträge verwerfen.
      if mSession <> FLastSession then
      begin
        FLastSession := mSession;
        FPlan.Reset;
        FDirty := True;
        FAll := True;
      end;
      if FDirty then
      begin
        FDirty := False;
        if FAll then
        begin
          StartAll;
        end
        else
        begin
          SyncDirty;
        end;
      end;
      // Der Abgleich aller verteilt sich auf die Takte: Auch der Binärstrom kostet im Hauptthread etwas.
      if FPendingAll.Count > 0 then
      begin
        SyncPending(cFormsPerTick);
      end;
    end);
  // Solange der Abgleich aller läuft, öfter; sonst im gewohnten Takt.
  if FPendingAll.Count > 0 then
  begin
    if FTimer.Interval <> cPendingIntervalMs then
    begin
      FTimer.Interval := cPendingIntervalMs;
    end;
  end
  else if FTimer.Interval <> cSyncDelayMs then
  begin
    FTimer.Interval := cSyncDelayMs;
  end;
end;

procedure TDpccIdeForms.StartAll;
var
  mRoot: TComponent;
begin
  FAll := False;
  FDirtyRoots.Clear;
  FPendingAll.Clear;
  for mRoot in FDesigners.Keys do
  begin
    FPendingAll.Add(mRoot);
  end;
end;

procedure TDpccIdeForms.SyncPending(AMax: Integer);
var
  mRoots: TArray<TComponent>;
  mSizes: TArray<Int64>;
  mForm: TOpenForm;
  mSize: Int64;
  mIndex, mCount: Integer;
begin
  mRoots := nil;
  mSizes := nil;
  // Die nächsten offenen Formulare (inzwischen geschlossene fallen weg) mit der Größe ihres letzten Stroms; die Datei
  // nur aus FDesigners (FileNameOf könnte über ReleaseOthers FPendingAll ändern).
  mIndex := 0;
  while (mIndex < FPendingAll.Count) and (Length(mRoots) < AMax) do
  begin
    if FDesigners.TryGetValue(FPendingAll[mIndex], mForm) then
    begin
      mSize := 0;
      if mForm.FileName <> '' then
      begin
        mSize := FPlan.LastSize(mForm.FileName);
      end;
      mRoots := mRoots + [FPendingAll[mIndex]];
      mSizes := mSizes + [mSize];
      Inc(mIndex);
    end
    else
    begin
      FPendingAll.Delete(mIndex);
    end;
  end;
  mCount := TDpccFormSyncPlan.TickCount(mSizes, AMax, cLargeFormBytes);
  for mIndex := 0 to mCount - 1 do
  begin
    FPendingAll.Remove(mRoots[mIndex]);
    // SyncForm des vorigen kann über ReleaseOthers einen Designer vergessen haben.
    if FDesigners.TryGetValue(mRoots[mIndex], mForm) then
    begin
      SyncForm(mRoots[mIndex], mForm.Designer);
    end;
  end;
end;

procedure TDpccIdeForms.SyncDirty;
var
  mRoots: TArray<TComponent>;
  mRoot: TComponent;
  mForm: TOpenForm;
begin
  if FDirtyRoots.Count = 0 then
  begin
    Exit;
  end;
  // Kopie: SyncForm kann über Remember einen alten Designer aus FDirtyRoots nehmen (ReleaseOthers).
  mRoots := FDirtyRoots.ToArray;
  FDirtyRoots.Clear;
  for mRoot in mRoots do
  begin
    if FDesigners.TryGetValue(mRoot, mForm) then
    begin
      SyncForm(mRoot, mForm.Designer);
    end;
  end;
end;

function TDpccIdeForms.FileNameOf(ARoot: TComponent): string;
var
  mForm: TOpenForm;
begin
  Result := '';
  if not FDesigners.TryGetValue(ARoot, mForm) then
  begin
    Exit;
  end;
  if mForm.FileName = '' then
  begin
    // Beim Öffnen noch nicht bekannt: den Designer erneut fragen.
    Remember(mForm.Designer);
    if not FDesigners.TryGetValue(ARoot, mForm) then
    begin
      Exit;
    end;
  end;
  Result := mForm.FileName;
end;

procedure TDpccIdeForms.SyncForm(ARoot: TComponent; const ADesigner: IDesigner);
var
  mFileName: string;
  mForm: TOpenForm;
  mBinary: TBytes;
  mJob: TDpccFormSyncJob;
begin
  mFileName := '';
  try
    mFileName := FileNameOf(ARoot);
    if mFileName = '' then
    begin
      // Ohne eindeutige Datei nichts senden: Ein falscher Name hängt den Text an ein fremdes Formular.
      if FDesigners.TryGetValue(ARoot, mForm) and not mForm.Reported then
      begin
        mForm.Reported := True;
        FDesigners.AddOrSetValue(ARoot, mForm);
        Log('Formular nicht gesendet: Formulardatei des Designers unbekannt');
      end;
      Exit;
    end;
    FRoots.AddOrSetValue(ARoot, mFileName);
    // Im Hauptthread nur der Binärstrom (Komponenten darf nur er anfassen); unverändert: nichts weiter.
    mBinary := BinaryOf(ARoot, ADesigner);
    if Length(mBinary) = 0 then
    begin
      Exit;
    end;
    if FPlan.Offer(mFileName, mBinary, mJob) = TDpccFormOffer.Start then
    begin
      StartJob(mJob);
    end;
  except
    on E: Exception do
      Log(Format('Formular %s nicht gesendet: %s', [ExtractFileName(mFileName), E.Message]));
  end;
end;

procedure TDpccIdeForms.StartJob(const AJob: TDpccFormSyncJob);
begin
  try
    FThreads.Start(ConvertWork(AJob));
  except
    on E: Exception do
    begin
      // Kein Thread (selten): Auftrag als nicht gesendet abschließen; der nächste Stand geht neu los.
      Log(Format('Formular %s nicht gesendet: kein Thread (%s)', [ExtractFileName(AJob.FileName), E.Message]));
      Settle(AJob, False, '');
    end;
  end;
end;

procedure TDpccIdeForms.SendConverted(const AJob: TDpccFormSyncJob; const AText, AError: string);
var
  mSession: TLspSession;
  mPosted: Boolean;
begin
  // Formular geschlossen oder neue Sitzung: nicht senden (Settle meldet ein geschlossenes ab).
  if not FPlan.IsCurrent(AJob) then
  begin
    Settle(AJob, False, '');
    Exit;
  end;
  if AError <> '' then
  begin
    Log(Format('Formular %s nicht in Text gewandelt: %s', [ExtractFileName(AJob.FileName), AError]));
  end;
  mSession := CurrentSession;
  // Nur an die Sitzung, die der Takt kennt: Eine neue setzt der nächste Takt auf (Reset, alles neu).
  if (AText = '') or (mSession = nil) or (mSession <> FLastSession) then
  begin
    Settle(AJob, False, '');
    Exit;
  end;
  mPosted := False;
  try
    mPosted := TDpccTimeLimit.Post(SendWork(mSession, AJob, AText));
  except
    on E: Exception do
    begin
      Log(Format('Formular %s nicht gesendet: kein Arbeiter (%s)', [ExtractFileName(AJob.FileName), E.Message]));
    end;
  end;
  // Nicht gestartet (dpcc wird beendet): Der Auftrag ist hier zu Ende.
  if not mPosted then
  begin
    Settle(AJob, False, '');
  end;
end;

procedure TDpccIdeForms.Settle(const AJob: TDpccFormSyncJob; ASucceeded: Boolean; const AText: string);
var
  mDone: TDpccFormSyncDone;
  mSession: TLspSession;
begin
  mDone := FPlan.Finished(AJob, ASucceeded);
  if mDone.CloseFile <> '' then
  begin
    // Während des Auftrags geschlossen: erst jetzt abmelden, nach dessen Senden.
    mSession := CurrentSession;
    if mSession <> nil then
    begin
      try
        mSession.Close(mDone.CloseFile);
      except
        on E: Exception do
          Log(Format('Formular %s nicht abgemeldet: %s', [ExtractFileName(mDone.CloseFile), E.Message]));
      end;
    end;
  end;
  if mDone.HasNext then
  begin
    StartJob(mDone.Next);
  end;
end;

class procedure TDpccIdeForms.Converted(const AJob: TDpccFormSyncJob; const AText, AError: string);
var
  mActivity: IInterface;
begin
  mActivity := TDpccActivity.Scope('Formular-Abgleich: Text fertig');
  if FCurrent <> nil then
  begin
    FCurrent.SendConverted(AJob, AText, AError);
  end;
end;

class procedure TDpccIdeForms.Sent(const AJob: TDpccFormSyncJob; const AText: string; ASucceeded: Boolean;
  const AError: string);
var
  mActivity: IInterface;
begin
  mActivity := TDpccActivity.Scope('Formular-Abgleich: gesendet');
  if FCurrent = nil then
  begin
    Exit;
  end;
  if AError <> '' then
  begin
    FCurrent.Log(Format('Formular %s nicht gesendet: %s', [ExtractFileName(AJob.FileName), AError]));
  end;
  FCurrent.Settle(AJob, ASucceeded, AText);
end;

procedure TDpccIdeForms.Closed(ARoot: TComponent);
var
  mFileName: string;
  mSession: TLspSession;
begin
  FDesigners.Remove(ARoot);
  FPendingAll.Remove(ARoot);
  FDirtyRoots.Remove(ARoot);
  if not FRoots.TryGetValue(ARoot, mFileName) then
  begin
    Exit;
  end;
  FRoots.Remove(ARoot);
  // Läuft noch ein Auftrag, meldet Settle die Datei nach dessen Senden ab (sonst öffnete er sie beim Server wieder).
  if not FPlan.Close(mFileName) then
  begin
    Exit;
  end;
  mSession := CurrentSession;
  if mSession <> nil then
    try
      mSession.Close(mFileName);
    except
      on E: Exception do
        Log(Format('Formular %s nicht abgemeldet: %s', [ExtractFileName(mFileName), E.Message]));
    end;
end;

end.
