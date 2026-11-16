unit dpcc.IDE.Completion.Leftovers;

// Letzter Schritt des Abbaus (#1233): dpcc-Komponenten, die nach dem Abbau noch an Formularen, Datenmodulen oder
// der Anwendung der IDE hängen, freigeben, solange ihr Code noch geladen ist. Seit Rückbau R5 (Wurzel
// dpcc.IDE.Completion.Register) ohne Module. Seit S7b liegt dpcc in drei Packages: Eigene Klassen sind die aus
// dpcc.IDE.Base, dpcc.UI (Popups, Hinweisfenster, Optionsseite) und dpcc.Core (TDpccPluginModules). Ein Vergleich
// mit HInstance sähe nur IDE.Base; die Fenster aus dpcc.UI blieben liegen und die IDE riefe beim Beenden ihren
// entladenen Code auf.

interface

/// <summary>dpcc-Komponenten, die nach dem Abbau noch einem Objekt der IDE gehören oder in einem ihrer Fenster
/// liegen, ins Protokoll und freigeben. Die IDE gäbe sie erst nach dem Entladen frei und riefe dabei Notification
/// bzw. den Destruktor in nicht mehr geladenem Code auf (Zugriffsverletzung in TComponent.Notification beim
/// Beenden).</summary>
procedure FreeLeftovers;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.PluginModules,
  // Meldet dpcc.IDE.Base bei TDpccPluginModules an; hier benutzt, damit es nach dieser Unit (und nach
  // dpcc.IDE.Completion.Register, das FreeLeftovers im Abbau ruft) beendet wird.
  dpcc.IDE.Foundation.Module;

type
  /// <summary>Streicht Funde, die beim Freigeben eines anderen Fundes mit frei werden.</summary>
  TLeftoverTracker = class(TComponent)
  public
    Found: TList<TComponent>;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

procedure TLeftoverTracker.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (Found <> nil) then
  begin
    Found.Remove(AComponent);
  end;
end;

/// <summary>Stammt die Klasse von AObject aus einem dpcc-Package (IDE.Base, UI, Core)?</summary>
function OwnClass(AObject: TObject): Boolean;
begin
  Result := (AObject <> nil) and TDpccPluginModules.OwnsClass(AObject.ClassType);
end;

/// <summary>„TEditWindow EditWindow_0 › TPanel EditorPanel“: Owner- bzw. Elternkette für das Protokoll.</summary>
function ChainOf(AComponent: TComponent): string;
var
  mItem: TComponent;
begin
  Result := '';
  mItem := AComponent;
  while mItem <> nil do
  begin
    if Result <> '' then
    begin
      Result := ' › ' + Result;
    end;
    Result := mItem.ClassName + ' ' + mItem.Name + Result;
    if mItem.Owner <> nil then
    begin
      mItem := mItem.Owner;
    end
    else if (mItem is TControl) and (TControl(mItem).Parent <> nil) then
    begin
      mItem := TControl(mItem).Parent;
    end
    else
    begin
      mItem := nil;
    end;
  end;
end;

/// <summary>AComponent als Fund aufnehmen, wenn ihre Klasse von dpcc stammt (einmal); sonst False.</summary>
function AddOwn(AComponent: TComponent; AFound: TList<TComponent>): Boolean;
begin
  Result := OwnClass(AComponent);
  if Result and not AFound.Contains(AComponent) then
  begin
    AFound.Add(AComponent);
  end;
end;

/// <summary>Nur die obersten dpcc-Komponenten unter AComponent sammeln: Ihre eigenen Kinder gehen mit ihnen.
/// </summary>
procedure CollectLeftovers(AComponent: TComponent; AFound: TList<TComponent>);
var
  mIndex: Integer;
  mControl: TWinControl;
begin
  for mIndex := 0 to AComponent.ComponentCount - 1 do
  begin
    if not AddOwn(AComponent.Components[mIndex], AFound) then
    begin
      CollectLeftovers(AComponent.Components[mIndex], AFound);
    end;
  end;
  if not (AComponent is TWinControl) then
  begin
    Exit;
  end;
  mControl := TWinControl(AComponent);
  for mIndex := 0 to mControl.ControlCount - 1 do
  begin
    // Fremde Kinder ohne eigenen Owner-Baum hier (der kommt über Components).
    if not AddOwn(mControl.Controls[mIndex], AFound) and (mControl.Controls[mIndex] is TWinControl) and
      (mControl.Controls[mIndex].Owner <> AComponent) then
    begin
      CollectLeftovers(mControl.Controls[mIndex], AFound);
    end;
  end;
end;

/// <summary>Modul einer Klasse ('' = unbekannt), für das Protokoll.</summary>
function ModuleOf(AClass: TClass): string;
var
  mBuffer: array[0..MAX_PATH] of Char;
begin
  Result := '';
  if GetModuleFileName(FindClassHInstance(AClass), mBuffer, MAX_PATH) > 0 then
  begin
    Result := ExtractFileName(mBuffer);
  end;
end;

/// <summary>Stammt das Modul aus der IDE selbst (coreide, vcl, rtl, bds.exe)?</summary>
function IdeModule(const AModule: string): Boolean;
begin
  Result := StartsText('coreide', AModule) or StartsText('vcl', AModule) or StartsText('rtl', AModule) or
    SameText(AModule, 'bds.exe');
end;

/// <summary>Komponenten eines Editorfensters mit Modul ihrer Klasse ins Protokoll, außer denen der IDE.</summary>
procedure LogFormComponents(AForm: TCustomForm);
var
  mIndex: Integer;
  mModule: string;
begin
  for mIndex := 0 to AForm.ComponentCount - 1 do
  begin
    mModule := ModuleOf(AForm.Components[mIndex].ClassType);
    if not IdeModule(mModule) then
    begin
      TDpccGuard.Log(Format('Beim Entladen in %s: %s "%s" aus %s', [AForm.Name,
        AForm.Components[mIndex].ClassName, AForm.Components[mIndex].Name, mModule]));
    end;
  end;
end;

/// <summary>Komponenten der Editorfenster mit Modul ihrer Klasse ins Protokoll (#1233): Beim Beenden ruft die IDE
/// Notification einer Komponente eines Editorfensters auf, deren Code schon entladen ist.</summary>
procedure LogEditorComponents;
var
  mIndex: Integer;
begin
  for mIndex := 0 to Screen.FormCount - 1 do
  begin
    if SameText(Screen.Forms[mIndex].ClassName, 'TEditWindow') then
    begin
      LogFormComponents(Screen.Forms[mIndex]);
    end;
  end;
end;

/// <summary>Funde aus allen Formularen, Datenmodulen und der Anwendung.</summary>
procedure CollectAll(AFound: TList<TComponent>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to Screen.FormCount - 1 do
  begin
    if OwnClass(Screen.Forms[mIndex]) then
    begin
      AFound.Add(Screen.Forms[mIndex]);
    end
    else
    begin
      CollectLeftovers(Screen.Forms[mIndex], AFound);
    end;
  end;
  for mIndex := 0 to Screen.DataModuleCount - 1 do
  begin
    if not OwnClass(Screen.DataModules[mIndex]) then
    begin
      CollectLeftovers(Screen.DataModules[mIndex], AFound);
    end;
  end;
  CollectLeftovers(Application, AFound);
end;

/// <summary>Funde von hinten freigeben; was dabei mit frei wird, streicht der Tracker.</summary>
procedure FreeFound(ATracker: TLeftoverTracker);
var
  mItem: TComponent;
begin
  for mItem in ATracker.Found do
  begin
    mItem.FreeNotification(ATracker);
  end;
  while ATracker.Found.Count > 0 do
  begin
    mItem := ATracker.Found.Last;
    TDpccGuard.Log('dpcc-Komponente nach dem Abbau noch vorhanden, wird freigegeben: ' + ChainOf(mItem));
    try
      mItem.Free;
    except
      on E: Exception do
      begin
        TDpccGuard.Log('Freigeben fehlgeschlagen: ' + E.ClassName);
      end;
    end;
    // Ohne Benachrichtigung (Ausnahme im Destruktor) nicht endlos.
    ATracker.Found.Remove(mItem);
  end;
end;

procedure FreeLeftovers;
var
  mTracker: TLeftoverTracker;
begin
  LogEditorComponents;
  mTracker := TLeftoverTracker.Create(nil);
  try
    mTracker.Found := TList<TComponent>.Create;
    CollectAll(mTracker.Found);
    FreeFound(mTracker);
  finally
    mTracker.Found.Free;
    mTracker.Found := nil;
    mTracker.Free;
  end;
end;

end.
