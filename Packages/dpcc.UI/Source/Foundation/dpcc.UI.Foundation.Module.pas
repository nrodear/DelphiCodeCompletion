unit dpcc.UI.Foundation.Module;

// Meldet dpcc.UI bei TDpccPluginModules an (S7b): Beim Entladen gibt dpcc.IDE.Completion.Leftovers Popups,
// Hinweisfenster und die Optionsseite frei, die noch an Fenstern der IDE hängen. Deren Klassen liegen in diesem
// Package; ohne Anmeldung blieben sie liegen und die IDE riefe beim Beenden entladenen Code auf.

interface

implementation

uses
  dpcc.Core.Diagnostics.PluginModules;

initialization
  TDpccPluginModules.Add(HInstance);

finalization
  TDpccPluginModules.Remove(HInstance);

end.
