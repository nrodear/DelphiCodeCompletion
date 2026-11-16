unit dpcc.Common.Product.Version;

// Platform-Feature "Product", Root: Name und Version des Servers.
// Wird u. a. für "serverInfo" in der Antwort auf "initialize" verwendet.
// Die Version steht nur in dpcc.Text.Product.Version.

interface

uses
  dpcc.Text.Product.Version;

type
  /// <summary>Name und Version von dpcc.</summary>
  TProductVersion = record
  public const
    cName = 'dpcc';
    cVersion = TDpccVersion.cVersion;
  end;

implementation

end.
