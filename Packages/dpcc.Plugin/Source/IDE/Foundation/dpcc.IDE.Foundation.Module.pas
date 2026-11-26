unit dpcc.IDE.Foundation.Module;

// Meldet dpcc.Plugin bei TDpccPluginModules an (S7b): Reste beim Entladen (dpcc.IDE.Completion.Leftovers) und
// überfällige Threads (TDpccOverdueThreads) erkennen damit die Klassen und den Code dieses Packages. Abgemeldet wird
// in der finalization, also erst nach den Units, die diese hier benutzen (Leftovers, Register).

interface

implementation

uses
  dpcc.Core.Diagnostics.PluginModules;

initialization
  TDpccPluginModules.Add(HInstance);

finalization
  TDpccPluginModules.Remove(HInstance);

end.
