unit dpcc.Core.Diagnostics.PluginModules;

// Die Module (BPLs), aus denen das Plugin besteht (S7b). Seit der Teilung in dpcc.Core, dpcc.UI und dpcc.IDE.Base
// liegt der Code von dpcc in mehreren Packages; HInstance einer Unit nennt nur ihr eigenes. Wer wissen muss, ob eine
// Klasse von dpcc stammt (Reste beim Entladen, dpcc.IDE.Completion.Leftovers) oder welche Packages ein überfälliger
// Arbeiter-Thread festhalten muss (TDpccOverdueThreads), fragt hier.
// Jedes Package meldet sich im initialization-Teil einer eigenen Unit an und im finalization-Teil wieder ab:
// dpcc.Core in dieser Unit, dpcc.UI in dpcc.UI.Foundation.Module, dpcc.IDE.Base in dpcc.IDE.Foundation.Module.
// In einer Exe ohne Laufzeit-Packages (Tests) ist es nur das Modul der Exe.

interface

uses
  System.SysUtils;

type
  TDpccPluginModules = class
  public
    /// <summary>AModule (HInstance eines dpcc-Packages) anmelden; 0 und doppelte werden ignoriert.</summary>
    class procedure Add(AModule: HMODULE); static;
    /// <summary>AModule abmelden (finalization des Packages).</summary>
    class procedure Remove(AModule: HMODULE); static;
    /// <summary>Gehört AModule zu dpcc?</summary>
    class function Contains(AModule: HMODULE): Boolean; static;
    /// <summary>Liegt der Code von AClass in einem dpcc-Package? False für nil.</summary>
    class function OwnsClass(AClass: TClass): Boolean; static;
    /// <summary>Alle angemeldeten Module, zuerst angemeldete zuerst.</summary>
    class function All: TArray<HMODULE>; static;
  end;

implementation

uses
  System.SyncObjs,
  System.Generics.Collections;

const
  /// <summary>Plätze, die die Liste gleich zu Beginn bekommt (drei dpcc-Packages, Reserve): Wüchse sie erst beim
  /// Anmelden eines weiteren Moduls, bliebe der Speicher belegt und der Leckmonitor der Tests zählte ihn dem Test zu.
  /// </summary>
  cInitialModules = 8;

var
  Lock: TCriticalSection;
  Modules: TList<HMODULE>;

{ TDpccPluginModules }

class procedure TDpccPluginModules.Add(AModule: HMODULE);
begin
  if (AModule = 0) or (Lock = nil) then
  begin
    Exit;
  end;
  Lock.Enter;
  try
    if not Modules.Contains(AModule) then
    begin
      Modules.Add(AModule);
    end;
  finally
    Lock.Leave;
  end;
end;

class procedure TDpccPluginModules.Remove(AModule: HMODULE);
begin
  if Lock = nil then
  begin
    Exit;
  end;
  Lock.Enter;
  try
    Modules.Remove(AModule);
  finally
    Lock.Leave;
  end;
end;

class function TDpccPluginModules.Contains(AModule: HMODULE): Boolean;
begin
  if (AModule = 0) or (Lock = nil) then
  begin
    Exit(False);
  end;
  Lock.Enter;
  try
    Result := Modules.Contains(AModule);
  finally
    Lock.Leave;
  end;
end;

class function TDpccPluginModules.OwnsClass(AClass: TClass): Boolean;
begin
  Result := (AClass <> nil) and Contains(HMODULE(FindClassHInstance(AClass)));
end;

class function TDpccPluginModules.All: TArray<HMODULE>;
begin
  Result := nil;
  if Lock = nil then
  begin
    Exit;
  end;
  Lock.Enter;
  try
    Result := Modules.ToArray;
  finally
    Lock.Leave;
  end;
end;

initialization
  Lock := TCriticalSection.Create;
  Modules := TList<HMODULE>.Create;
  Modules.Capacity := cInitialModules;
  TDpccPluginModules.Add(HInstance);

finalization
  TDpccPluginModules.Remove(HInstance);
  FreeAndNil(Lock);
  FreeAndNil(Modules);

end.
