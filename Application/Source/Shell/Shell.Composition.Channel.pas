unit Shell.Composition.Channel;

// Was eine Wurzel des Servers als Verbindung nach außen mitbekommt: Logger, Transport und Anonymisierer. Eigene Unit
// seit Schritt 2b: Die Wurzel (Shell.Composition.CompletionServer) liegt im Package dpcc.Server. Mitschnitt (--trace)
// und Auszug der Sitzung gab es nur im stdio-Betrieb des eigenen Server-Prozesses; sie entfallen seit S1.

interface

uses
  dpcc.Common.Logging.Contract,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.Diagnostics.Anonymizer;

type
  /// <summary>Verbindung einer Server-Wurzel nach außen.</summary>
  TShellServerChannel = record
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Anonymizer: ILogAnonymizer;
  end;

implementation

end.
