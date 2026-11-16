unit dpcc.IDE.Completion.SaveNotifier;

// Schlanker Speicher-Notifier (Rückbau R5, Ersatz für den Reloader): meldet jede gespeicherte Quelltextdatei an
// OnSaved, damit der Manager textDocument/didSave schickt. Ohne Timer und ohne Neuladen: Je offenes Modul hängt ein
// IOTAModuleNotifier, dessen AfterSave die Dateien der Quelltexteditoren des Moduls meldet (bei Projekten die
// .dpr/.dpk). Neu geöffnete Module findet ein IOTAIDENotifier (ofnFileOpened); beim Schließen meldet sich der
// Notifier über Destroyed selbst ab. Jeder Aufruf aus der IDE läuft über TDpccGuard (#493).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  ToolsAPI;

type
  TDpccSaveNotifier = class
  private type
    TModuleNotifier = class(TNotifierObject, IOTANotifier, IOTAModuleNotifier)
    private
      FOwner: TDpccSaveNotifier;
      FModule: IOTAModule;
      FIndex: Integer;
    public
      procedure AfterSave;
      procedure Destroyed;
      function CheckOverwrite: Boolean;
      procedure ModuleRenamed(const NewName: string);
      /// <summary>Beim Modul abmelden; mehrfach aufrufbar.</summary>
      procedure Detach;
    end;

    TIdeNotifier = class(TNotifierObject, IOTAIDENotifier)
    private
      FOwner: TDpccSaveNotifier;
    public
      procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
      procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
      procedure AfterCompile(Succeeded: Boolean); overload;
    end;
  private
    FOnSaved: TProc<string>;
    FModules: TList<TModuleNotifier>;
    FNotifier: TIdeNotifier;
    FNotifierRef: IOTAIDENotifier;
    FNotifierIndex: Integer;
    /// <summary>Jedes offene Modul bekommt einen Notifier (schon versorgte bleiben).</summary>
    procedure Sweep;
    procedure Attach(const AModule: IOTAModule);
    procedure Forget(ANotifier: TModuleNotifier);
    procedure Saved(const AModule: IOTAModule);
  public
    /// <summary>AOnSaved bekommt den vollen Namen jeder gespeicherten Quelltextdatei.</summary>
    constructor Create(const AOnSaved: TProc<string>);
    destructor Destroy; override;
  end;

implementation

uses
  dpcc.Core.Diagnostics.Guard;

{ TDpccSaveNotifier.TModuleNotifier }

procedure TDpccSaveNotifier.TModuleNotifier.AfterSave;
var
  mOwner: TDpccSaveNotifier;
  mModule: IOTAModule;
begin
  mOwner := FOwner;
  mModule := FModule;
  if (mOwner = nil) or (mModule = nil) then
  begin
    Exit;
  end;
  // Keine Exception an die IDE (#493).
  TDpccGuard.Run(TDpccFeature.Files,
    procedure
    begin
      mOwner.Saved(mModule);
    end);
end;

function TDpccSaveNotifier.TModuleNotifier.CheckOverwrite: Boolean;
begin
  Result := True;
end;

procedure TDpccSaveNotifier.TModuleNotifier.ModuleRenamed(const NewName: string);
begin
  // Der neue Name kommt mit dem nächsten Speichern über die Editoren des Moduls.
end;

procedure TDpccSaveNotifier.TModuleNotifier.Destroyed;
var
  mOwner: TDpccSaveNotifier;
begin
  mOwner := FOwner;
  if mOwner <> nil then
  begin
    mOwner.Forget(Self);
  end;
  // Zuletzt: Mit dem Abmelden kann die IDE die letzte Referenz freigeben.
  Detach;
end;

procedure TDpccSaveNotifier.TModuleNotifier.Detach;
var
  mModule: IOTAModule;
  mIndex: Integer;
begin
  mModule := FModule;
  mIndex := FIndex;
  FModule := nil;
  FOwner := nil;
  FIndex := -1;
  // Danach keine Felder mehr: RemoveNotifier kann dieses Objekt freigeben.
  if (mModule <> nil) and (mIndex >= 0) then
  begin
    mModule.RemoveNotifier(mIndex);
  end;
end;

{ TDpccSaveNotifier.TIdeNotifier }

procedure TDpccSaveNotifier.TIdeNotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string;
  var Cancel: Boolean);
var
  mOwner: TDpccSaveNotifier;
begin
  mOwner := FOwner;
  if (mOwner = nil) or (NotifyCode <> ofnFileOpened) then
  begin
    Exit;
  end;
  TDpccGuard.Run(TDpccFeature.Files,
    procedure
    begin
      mOwner.Sweep;
    end);
end;

procedure TDpccSaveNotifier.TIdeNotifier.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TDpccSaveNotifier.TIdeNotifier.AfterCompile(Succeeded: Boolean);
begin
end;

{ TDpccSaveNotifier }

constructor TDpccSaveNotifier.Create(const AOnSaved: TProc<string>);
var
  mServices: IOTAServices;
begin
  inherited Create;
  FOnSaved := AOnSaved;
  FModules := TList<TModuleNotifier>.Create;
  FNotifierIndex := -1;
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    FNotifier := TIdeNotifier.Create;
    FNotifier.FOwner := Self;
    FNotifierRef := FNotifier;
    FNotifierIndex := mServices.AddNotifier(FNotifierRef);
  end;
  // Schon offene Module (die IDE lädt das letzte Projekt oft vor dem Plugin).
  Sweep;
end;

destructor TDpccSaveNotifier.Destroy;
var
  mServices: IOTAServices;
  mNotifier: TModuleNotifier;
begin
  // Erst abmelden, dann freigeben (#493).
  if FNotifier <> nil then
  begin
    FNotifier.FOwner := nil;
  end;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    mServices.RemoveNotifier(FNotifierIndex);
  end;
  FNotifierRef := nil;
  for mNotifier in FModules.ToArray do
  begin
    mNotifier.Detach;
  end;
  FModules.Free;
  FOnSaved := nil;
  inherited;
end;

procedure TDpccSaveNotifier.Sweep;
var
  mServices: IOTAModuleServices;
  mIndex: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    Attach(mServices.Modules[mIndex]);
  end;
end;

procedure TDpccSaveNotifier.Attach(const AModule: IOTAModule);
var
  mNotifier: TModuleNotifier;
  mRef: IOTAModuleNotifier;
begin
  if (AModule = nil) or Supports(AModule, IOTAProjectGroup) then
  begin
    Exit;
  end;
  for mNotifier in FModules do
  begin
    if mNotifier.FModule = AModule then
    begin
      Exit;
    end;
  end;
  mNotifier := TModuleNotifier.Create;
  mNotifier.FOwner := Self;
  mNotifier.FModule := AModule;
  mRef := mNotifier;
  mNotifier.FIndex := AModule.AddNotifier(mRef);
  FModules.Add(mNotifier);
end;

procedure TDpccSaveNotifier.Forget(ANotifier: TModuleNotifier);
begin
  FModules.Remove(ANotifier);
end;

procedure TDpccSaveNotifier.Saved(const AModule: IOTAModule);
var
  mIndex: Integer;
  mEditor: IOTAEditor;
  mSource: IOTASourceEditor;
begin
  if not Assigned(FOnSaved) then
  begin
    Exit;
  end;
  // Die Quelltexte des Moduls: Unit (.pas), bei Projekten .dpr bzw. .dpk; Formulare (.dfm) nicht.
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    mEditor := AModule.ModuleFileEditors[mIndex];
    if Supports(mEditor, IOTASourceEditor, mSource) and (mSource.FileName <> '') then
    begin
      FOnSaved(mSource.FileName);
    end;
  end;
end;

end.
