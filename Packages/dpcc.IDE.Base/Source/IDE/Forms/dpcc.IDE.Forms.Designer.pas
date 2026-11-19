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
// - Änderungen des Servers an einem offenen Formular (Umbenennen eines
//   Handlers, #397) schreibt dpcc nicht auf die Platte, sonst überschreibt
//   der Designer sie beim Speichern: TDpccFormChanges vergleicht den
//   gesendeten mit dem geänderten Text, die Ereignis-Zuordnungen und einzeilige
//   Eigenschaften (Eigenschaftsregeln, #309) setzt dpcc im Designer über RTTI.
//   Andere Änderungen an offenen Formularen lehnt dpcc ab.
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
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  DesignIntf,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.WorkspaceEdits,
  dpcc.Core.Forms.Changes;

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
    /// <summary>Zuletzt gesendeter Text je Formulardatei (Schlüssel in Großbuchstaben).</summary>
    FTexts: TDictionary<string, string>;
    /// <summary>Wurzelkomponente → Formulardatei, für DesignerClosed.</summary>
    FRoots: TDictionary<TComponent, string>;
    /// <summary>Offene Designer je Wurzel samt Formulardatei (DesignerOpened bis DesignerClosed).</summary>
    FDesigners: TDictionary<TComponent, TOpenForm>;
    /// <summary>Wurzeln, die der laufende Abgleich aller Formulare noch senden muss.</summary>
    FPendingAll: TList<TComponent>;
    procedure Tick(Sender: TObject);
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
    /// <summary>Höchstens AMax Formulare des Abgleichs aller senden.</summary>
    procedure SyncPending(ASession: TLspSession; AMax: Integer);
    /// <summary>Nur die geänderten Formulare (FDirtyRoots) senden.</summary>
    procedure SyncDirty(ASession: TLspSession);
    procedure SyncForm(ASession: TLspSession; ARoot: TComponent; const ADesigner: IDesigner);
    /// <summary>Formulardatei des offenen Designers zu ARoot (gemerkt in FDesigners); '' wenn unbekannt.</summary>
    function FileNameOf(ARoot: TComponent): string;
    /// <summary>Offenes Formular zu AFileName.</summary>
    function FindOpen(const AFileName: string; out ARoot: TComponent; out ADesigner: IDesigner): Boolean;
    procedure Log(const AText: string);
  public
    /// <summary>ASessionOf: laufende Sitzung, ohne den Server zu starten; ALog: Diagnoseprotokoll.</summary>
    constructor Create(const ASessionOf: TFunc<TLspSession>; const ALog: TProc<string>);
    destructor Destroy; override;
    /// <summary>Alle offenen Formulare sofort an ASession schicken, z. B. vor dem Umbenennen.</summary>
    class procedure SyncNow(ASession: TLspSession); static;
    /// <summary>Zuletzt an den Server geschickter Text eines offenen Formulars.</summary>
    class function SentText(const AFileName: string; out AText: string): Boolean; static;
    /// <summary>Aktueller Stand eines offenen Formulars im Designer als Text, wie er an den Server ginge
    /// (#721); False, wenn es nicht offen ist.</summary>
    class function CurrentText(const AFileName: string; out AText: string): Boolean; static;
    /// <summary>Ist AFileName (.dfm/.fmx) gerade im Designer offen?</summary>
    class function IsOpen(const AFileName: string): Boolean; static;
    /// <summary>Lassen sich AEdits im offenen Formular ausführen? '' mit AChanges und AProperties, sonst der
    /// Grund.</summary>
    class function Check(const AFileName: string; const AEdits: TArray<TLspTextEdit>;
      out AChanges: TArray<TDpccFormEventChange>; out AProperties: TArray<TDpccFormPropertyChange>): string;
      static;
    /// <summary>Setzt Ereignis-Zuordnungen und Eigenschaften (#309) im Designer; '' bei Erfolg, sonst der
    /// Grund (nichts geändert).</summary>
    class function Apply(const AFileName: string; const AChanges: TArray<TDpccFormEventChange>;
      const AProperties: TArray<TDpccFormPropertyChange>): string; static;
  end;

implementation

uses
  System.TypInfo,
  Vcl.Forms,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Forms.Text,
  dpcc.IDE.Foundation.EditorSnapshot,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TDesignerText = (IsNotAnObjectProperty, IsNotSet, CannotBeSet, HasNoDefaultValue, NotAStringValue, IsNotANumber,
    TypeIsNotSetIn, ComponentNotFound, IsNotAnEvent, MethodIsMissingInThe, OpenInTheDesignerBut,
    OpenInTheDesignerThere, FormIsNoLongerOpen);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TDesignerText] of string = (
    ('%s ist keine Objekt-Eigenschaft',
     '%s ist nicht gesetzt',
     '%s lässt sich nicht setzen',
     '%s hat keinen Vorgabewert',
     '%s: kein String-Wert',
     '%s: %s ist keine Zahl',
     '%s: Typ wird im Designer nicht gesetzt',
     'Komponente %s nicht gefunden',
     '%s.%s ist kein Ereignis',
     'Methode %s fehlt in der Unit',
     'im Designer offen, aber noch nicht an den Server gemeldet',
     'im Designer offen; dort ändert dpcc nur Ereignis-Zuordnungen und einzeilige Eigenschaften (%s)',
     'Formular ist nicht mehr offen'),
    ('%s is not an object property',
     '%s is not set',
     '%s cannot be set',
     '%s has no default value',
     '%s: not a string value',
     '%s: %s is not a number',
     '%s: type is not set in the designer',
     'component %s not found',
     '%s.%s is not an event',
     'method %s is missing in the unit',
     'open in the designer, but not yet reported to the server',
     'open in the designer; there dpcc only changes event assignments and single-line properties (%s)',
     'form is no longer open'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TDesignerText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

const
  cSyncDelayMs = 500;
  /// <summary>Takt, solange der Abgleich aller Formulare läuft.</summary>
  cPendingIntervalMs = 100;
  /// <summary>Höchstens so viele Formulare je Takt beim Abgleich aller.</summary>
  cFormsPerTick = 2;

function Key(const AFileName: string): string;
begin
  Result := AnsiUpperCase(AFileName);
end;

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

function TextOf(ARoot: TComponent; const ADesigner: IDesigner): string;
var
  mDesigner: IDesigner;
begin
  Result := '';
  if (ARoot = nil) or (ADesigner = nil) then
  begin
    Exit;
  end;
  mDesigner := ADesigner;
  Result := TDpccFormText.Write(ARoot,
    function(AMethod: TMethod): string
    begin
      Result := mDesigner.GetMethodName(AMethod);
    end);
end;

const
  /// <summary>PropInfo.Default ohne default-Angabe (wie in System.Classes).</summary>
  cNoDefaultValue = Integer($80000000);

/// <summary>Löst APath (auch Font.Name) an AComponent auf; '' oder der Grund.</summary>
function ResolveProperty(AComponent: TObject; const APath: string; out AInstance: TObject;
  out AProp: PPropInfo): string;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  AInstance := AComponent;
  AProp := nil;
  mParts := APath.Split(['.']);
  if Length(mParts) = 0 then
  begin
    Exit('ohne Eigenschaft');
  end;
  for mIndex := 0 to High(mParts) - 1 do
  begin
    AProp := GetPropInfo(AInstance, mParts[mIndex]);
    if (AProp = nil) or (AProp^.PropType^.Kind <> tkClass) then
    begin
      Exit(Format(UiText(TDesignerText.IsNotAnObjectProperty), [mParts[mIndex]]));
    end;
    AInstance := GetObjectProp(AInstance, AProp);
    if AInstance = nil then
    begin
      Exit(Format(UiText(TDesignerText.IsNotSet), [mParts[mIndex]]));
    end;
  end;
  AProp := GetPropInfo(AInstance, mParts[High(mParts)]);
  if (AProp = nil) or (AProp^.SetProc = nil) then
  begin
    Exit(Format(UiText(TDesignerText.CannotBeSet), [APath]));
  end;
  Result := '';
end;

/// <summary>Zeile entfernt (Rückgängig, #721): zurück zum Vorgabewert der Deklaration.</summary>
function ResetValue(AInstance: TObject; AProp: PPropInfo; const APath: string; ACheckOnly: Boolean): string;
var
  mKind: TTypeKind;
begin
  Result := '';
  mKind := AProp^.PropType^.Kind;
  if (mKind in [tkInteger, tkChar, tkWChar, tkEnumeration, tkSet]) and (AProp^.Default <> cNoDefaultValue) then
  begin
    if not ACheckOnly then
    begin
      SetOrdProp(AInstance, AProp, AProp^.Default);
    end;
  end
  else if mKind in [tkString, tkLString, tkWString, tkUString] then
  begin
    if not ACheckOnly then
    begin
      SetStrProp(AInstance, AProp, '');
    end;
  end
  else
  begin
    Result := Format(UiText(TDesignerText.HasNoDefaultValue), [APath]);
  end;
end;

function AssignString(AInstance: TObject; AProp: PPropInfo; const AChange: TDpccFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mText: string;
begin
  Result := '';
  if not TDpccFormChanges.StringValue(AChange.Value, mText) then
  begin
    Result := Format(UiText(TDesignerText.NotAStringValue), [AChange.PropertyPath]);
  end
  else if not ACheckOnly then
  begin
    SetStrProp(AInstance, AProp, mText);
  end;
end;

/// <summary>Ganzzahl oder Bezeichner wie clRed oder crHandPoint.</summary>
function AssignInteger(AInstance: TObject; AProp: PPropInfo; const AChange: TDpccFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Integer;
  mIdentToInt: TIdentToInt;
begin
  Result := '';
  if not TryStrToInt(AChange.Value, mNumber) then
  begin
    mIdentToInt := FindIdentToInt(AProp^.PropType^);
    if not Assigned(mIdentToInt) or not mIdentToInt(AChange.Value, mNumber) then
    begin
      Exit(Format(UiText(TDesignerText.IsNotANumber), [AChange.PropertyPath, AChange.Value]));
    end;
  end;
  if not ACheckOnly then
  begin
    SetOrdProp(AInstance, AProp, mNumber);
  end;
end;

function AssignInt64(AInstance: TObject; AProp: PPropInfo; const AChange: TDpccFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Int64;
begin
  Result := '';
  if not TryStrToInt64(AChange.Value, mNumber) then
  begin
    Result := Format(UiText(TDesignerText.IsNotANumber), [AChange.PropertyPath, AChange.Value]);
  end
  else if not ACheckOnly then
  begin
    SetInt64Prop(AInstance, AProp, mNumber);
  end;
end;

function AssignEnumeration(AInstance: TObject; AProp: PPropInfo; const AChange: TDpccFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Integer;
begin
  Result := '';
  mNumber := GetEnumValue(AProp^.PropType^, AChange.Value);
  if mNumber < 0 then
  begin
    Result := Format('%s: unbekannter Wert %s', [AChange.PropertyPath, AChange.Value]);
  end
  else if not ACheckOnly then
  begin
    SetOrdProp(AInstance, AProp, mNumber);
  end;
end;

function AssignSet(AInstance: TObject; AProp: PPropInfo; const AChange: TDpccFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Integer;
begin
  Result := '';
  try
    mNumber := StringToSet(AProp, AChange.Value);
  except
    on EPropertyConvertError do
      Exit(Format('%s: unbekanntes Element in %s', [AChange.PropertyPath, AChange.Value]));
  end;
  if not ACheckOnly then
  begin
    SetOrdProp(AInstance, AProp, mNumber);
  end;
end;

function AssignFloat(AInstance: TObject; AProp: PPropInfo; const AChange: TDpccFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mFloat: Double;
begin
  Result := '';
  if not TryStrToFloat(AChange.Value, mFloat, TFormatSettings.Invariant) then
  begin
    Result := Format(UiText(TDesignerText.IsNotANumber), [AChange.PropertyPath, AChange.Value]);
  end
  else if not ACheckOnly then
  begin
    SetFloatProp(AInstance, AProp, mFloat);
  end;
end;

/// <summary>DFM-Wert aus AChange in die Eigenschaft; mit ACheckOnly nur prüfen. '' oder der Grund.</summary>
function AssignValue(AInstance: TObject; AProp: PPropInfo; const AChange: TDpccFormPropertyChange;
  ACheckOnly: Boolean): string;
begin
  if AChange.Removed then
  begin
    Exit(ResetValue(AInstance, AProp, AChange.PropertyPath, ACheckOnly));
  end;
  case AProp^.PropType^.Kind of
    tkString, tkLString, tkWString, tkUString:
      Result := AssignString(AInstance, AProp, AChange, ACheckOnly);
    tkInteger:
      Result := AssignInteger(AInstance, AProp, AChange, ACheckOnly);
    tkInt64:
      Result := AssignInt64(AInstance, AProp, AChange, ACheckOnly);
    tkEnumeration:
      Result := AssignEnumeration(AInstance, AProp, AChange, ACheckOnly);
    tkSet:
      Result := AssignSet(AInstance, AProp, AChange, ACheckOnly);
    tkFloat:
      Result := AssignFloat(AInstance, AProp, AChange, ACheckOnly);
  else
    Result := Format(UiText(TDesignerText.TypeIsNotSetIn), [AChange.PropertyPath]);
  end;
end;

/// <summary>Komponente AName unter ARoot; '' ist die Wurzel selbst.</summary>
function ComponentOf(ARoot: TComponent; const AName: string): TComponent;
begin
  Result := ARoot;
  if AName <> '' then
  begin
    Result := ARoot.FindComponent(AName);
  end;
end;

/// <summary>Ziele der Ereignis-Zuordnungen; '' oder der Grund.</summary>
function CheckEvents(ARoot: TComponent; const ADesigner: IDesigner; const AChanges: TArray<TDpccFormEventChange>;
  out ATargets: TArray<TComponent>; out AProperties: TArray<PPropInfo>): string;
var
  mChange: TDpccFormEventChange;
  mComponent: TComponent;
  mPropInfo: PPropInfo;
begin
  ATargets := nil;
  AProperties := nil;
  for mChange in AChanges do
  begin
    mComponent := ComponentOf(ARoot, mChange.Component);
    if mComponent = nil then
    begin
      Exit(Format(UiText(TDesignerText.ComponentNotFound), [mChange.Component]));
    end;
    mPropInfo := GetPropInfo(mComponent, mChange.EventName);
    if (mPropInfo = nil) or (mPropInfo^.PropType^.Kind <> tkMethod) then
    begin
      Exit(Format(UiText(TDesignerText.IsNotAnEvent), [mComponent.Name, mChange.EventName]));
    end;
    // Die Unit ist schon geändert; der Handler muss dort unter dem neuen Namen stehen.
    if not ADesigner.MethodExists(mChange.NewHandler) then
    begin
      Exit(Format(UiText(TDesignerText.MethodIsMissingInThe), [mChange.NewHandler]));
    end;
    ATargets := ATargets + [mComponent];
    AProperties := AProperties + [mPropInfo];
  end;
  Result := '';
end;

/// <summary>Ziele der Eigenschaften, Werte geprüft; '' oder der Grund.</summary>
function CheckProperties(ARoot: TComponent; const AProperties: TArray<TDpccFormPropertyChange>;
  out ATargets: TArray<TObject>; out AProps: TArray<PPropInfo>): string;
var
  mProp: TDpccFormPropertyChange;
  mComponent: TComponent;
  mInstance: TObject;
  mPropInfo: PPropInfo;
  mReason: string;
begin
  ATargets := nil;
  AProps := nil;
  for mProp in AProperties do
  begin
    mComponent := ComponentOf(ARoot, mProp.Component);
    if mComponent = nil then
    begin
      Exit(Format(UiText(TDesignerText.ComponentNotFound), [mProp.Component]));
    end;
    mReason := ResolveProperty(mComponent, mProp.PropertyPath, mInstance, mPropInfo);
    if mReason = '' then
    begin
      mReason := AssignValue(mInstance, mPropInfo, mProp, True);
    end;
    if mReason <> '' then
    begin
      Exit(Format('%s: %s', [mComponent.Name, mReason]));
    end;
    ATargets := ATargets + [mInstance];
    AProps := AProps + [mPropInfo];
  end;
  Result := '';
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
    begin
      mOwner.Closed(mRoot);
    end);
end;

{ TDpccIdeForms }

constructor TDpccIdeForms.Create(const ASessionOf: TFunc<TLspSession>; const ALog: TProc<string>);
begin
  inherited Create;
  FSessionOf := ASessionOf;
  FLog := ALog;
  FTexts := TDictionary<string, string>.Create;
  FRoots := TDictionary<TComponent, string>.Create;
  FDesigners := TDictionary<TComponent, TOpenForm>.Create;
  FPendingAll := TList<TComponent>.Create;
  FDirtyRoots := TList<TComponent>.Create;
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
  FDirtyRoots.Free;
  FPendingAll.Free;
  FDesigners.Free;
  FRoots.Free;
  FTexts.Free;
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
begin
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

procedure TDpccIdeForms.Tick(Sender: TObject);
var
  mSession: TLspSession;
begin
  TDpccGuard.Run(TDpccFeature.Forms,
    procedure
    begin
      mSession := nil;
      if Assigned(FSessionOf) then
      begin
        mSession := FSessionOf();
      end;
      if mSession = nil then
      begin
        FLastSession := nil;
        FPendingAll.Clear;
        Exit;
      end;
      // Neue Sitzung (Serverstart, Neustart): alles neu schicken.
      if mSession <> FLastSession then
      begin
        FLastSession := mSession;
        FTexts.Clear;
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
          SyncDirty(mSession);
        end;
      end;
      // Der Abgleich aller verteilt sich auf die Takte: Ein Formular in Text zu wandeln kostet im Hauptthread
      // spürbar Zeit.
      if FPendingAll.Count > 0 then
      begin
        SyncPending(mSession, cFormsPerTick);
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

procedure TDpccIdeForms.SyncPending(ASession: TLspSession; AMax: Integer);
var
  mRoot: TComponent;
  mForm: TOpenForm;
  mDone: Integer;
begin
  mDone := 0;
  while (FPendingAll.Count > 0) and (mDone < AMax) do
  begin
    mRoot := FPendingAll[0];
    FPendingAll.Delete(0);
    // Inzwischen geschlossen: übergehen.
    if FDesigners.TryGetValue(mRoot, mForm) then
    begin
      SyncForm(ASession, mRoot, mForm.Designer);
      Inc(mDone);
    end;
  end;
end;

procedure TDpccIdeForms.SyncDirty(ASession: TLspSession);
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
      SyncForm(ASession, mRoot, mForm.Designer);
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

function TDpccIdeForms.FindOpen(const AFileName: string; out ARoot: TComponent; out ADesigner: IDesigner): Boolean;
var
  mPair: TPair<TComponent, TOpenForm>;
begin
  ARoot := nil;
  ADesigner := nil;
  // Gemerkte Dateien; Remember hält sie eindeutig (ReleaseOthers).
  for mPair in FDesigners do
  begin
    if (mPair.Value.FileName <> '') and SameText(mPair.Value.FileName, AFileName) then
    begin
      ARoot := mPair.Key;
      ADesigner := mPair.Value.Designer;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TDpccIdeForms.SyncForm(ASession: TLspSession; ARoot: TComponent; const ADesigner: IDesigner);
var
  mText, mPrevious, mFileName: string;
  mForm: TOpenForm;
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
    mText := TextOf(ARoot, ADesigner);
    if (mText = '') or (FTexts.TryGetValue(Key(mFileName), mPrevious) and (mPrevious = mText)) then
    begin
      Exit;
    end;
    ASession.Sync(mFileName, mText);
    FTexts.AddOrSetValue(Key(mFileName), mText);
  except
    on E: Exception do
      Log(Format('Formular %s nicht gesendet: %s', [ExtractFileName(mFileName), E.Message]));
  end;
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
  FTexts.Remove(Key(mFileName));
  mSession := nil;
  if Assigned(FSessionOf) then
  begin
    mSession := FSessionOf();
  end;
  if mSession <> nil then
    try
      mSession.Close(mFileName);
    except
      on E: Exception do
        Log(Format('Formular %s nicht abgemeldet: %s', [ExtractFileName(mFileName), E.Message]));
    end;
end;

class procedure TDpccIdeForms.SyncNow(ASession: TLspSession);
begin
  if (FCurrent = nil) or (ASession = nil) then
  begin
    Exit;
  end;
  if ASession <> FCurrent.FLastSession then
  begin
    FCurrent.FLastSession := ASession;
    FCurrent.FTexts.Clear;
  end;
  FCurrent.FDirty := False;
  // Ausdrücklich verlangt (etwa vor dem Umbenennen): alle offenen Formulare sofort, aber nur mit offenem Designer.
  FCurrent.StartAll;
  FCurrent.SyncPending(ASession, MaxInt);
end;

class function TDpccIdeForms.SentText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := (FCurrent <> nil) and FCurrent.FTexts.TryGetValue(Key(AFileName), AText);
end;

class function TDpccIdeForms.CurrentText(const AFileName: string; out AText: string): Boolean;
var
  mRoot: TComponent;
  mDesigner: IDesigner;
begin
  AText := '';
  if (FCurrent <> nil) and FCurrent.FindOpen(AFileName, mRoot, mDesigner) then
  begin
    AText := TextOf(mRoot, mDesigner);
  end;
  Result := AText <> '';
end;

class function TDpccIdeForms.IsOpen(const AFileName: string): Boolean;
var
  mRoot: TComponent;
  mDesigner: IDesigner;
begin
  Result := (FCurrent <> nil) and FCurrent.FindOpen(AFileName, mRoot, mDesigner);
end;

class function TDpccIdeForms.Check(const AFileName: string; const AEdits: TArray<TLspTextEdit>;
  out AChanges: TArray<TDpccFormEventChange>; out AProperties: TArray<TDpccFormPropertyChange>): string;
var
  mSent, mEdited, mReason: string;
begin
  AChanges := nil;
  AProperties := nil;
  // Die Positionen des Servers beziehen sich auf den Text, den dpcc zuletzt geschickt hat.
  if (FCurrent = nil) or not FCurrent.FTexts.TryGetValue(Key(AFileName), mSent) then
  begin
    Exit(UiText(TDesignerText.OpenInTheDesignerBut));
  end;
  try
    mEdited := TLspEdits.Apply(mSent, AEdits);
  except
    on E: ELspEditError do
      Exit(E.Message);
  end;
  if not TDpccFormChanges.Diff(mSent, mEdited, AChanges, AProperties, mReason) then
  begin
    Exit(Format(UiText(TDesignerText.OpenInTheDesignerThere),
      [mReason]));
  end;
  Result := '';
end;

class function TDpccIdeForms.Apply(const AFileName: string; const AChanges: TArray<TDpccFormEventChange>;
  const AProperties: TArray<TDpccFormPropertyChange>): string;
var
  mDesigner: IDesigner;
  mRoot: TComponent;
  mTargets: TArray<TComponent>;
  mProperties, mValueProps: TArray<PPropInfo>;
  mValueTargets: TArray<TObject>;
  mIndex: Integer;
begin
  mRoot := nil;
  mDesigner := nil;
  if (FCurrent = nil) or not FCurrent.FindOpen(AFileName, mRoot, mDesigner) or (mRoot = nil) or
    (mDesigner = nil) then
  begin
    Exit(UiText(TDesignerText.FormIsNoLongerOpen));
  end;
  // Erst alles prüfen, dann setzen: Entweder alle Zuordnungen oder keine.
  Result := CheckEvents(mRoot, mDesigner, AChanges, mTargets, mProperties);
  if Result = '' then
  begin
    Result := CheckProperties(mRoot, AProperties, mValueTargets, mValueProps);
  end;
  if Result <> '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AChanges) do
  begin
    SetMethodProp(mTargets[mIndex], mProperties[mIndex], mDesigner.CreateMethod(AChanges[mIndex].NewHandler,
      GetTypeData(mProperties[mIndex]^.PropType^)));
  end;
  for mIndex := 0 to High(AProperties) do
  begin
    AssignValue(mValueTargets[mIndex], mValueProps[mIndex], AProperties[mIndex], False);
  end;
  if (Length(AChanges) > 0) or (Length(AProperties) > 0) then
  begin
    mDesigner.Modified;
    if FCurrent <> nil then
    begin
      FCurrent.Changed(mDesigner);
    end;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.IDE.Forms.Designer', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
