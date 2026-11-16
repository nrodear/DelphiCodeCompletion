unit dpcc.Core.Product.Version;

// Version des Plugins (#493: steht in jeder Fehlerzeile des Protokolls). Die
// Versionsangabe steht nur in dpcc.Text.Product.Version, gemeinsam mit dem
// Server; Tools/Set-Version.ps1 schreibt sie dort.

interface

uses
  dpcc.Text.Product.Version;

type
  TDpccPluginVersion = class
  public const
    cVersion = TDpccVersion.cVersion;
  end;

implementation

end.
