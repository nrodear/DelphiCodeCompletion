unit dpcc.IDE.Completion.Adapters;

// Adapter des Kerns für die Wurzel dpcc.IDE.Completion.Register (Rückbau R5): Server im IDE-Prozess (Package
// dpcc.Server, seit S1 der einzige Betrieb), Ordnerbeobachter und die Quellen von Vervollständigung (Server,
// XML-Doku; eigene Code-Vorlagen gibt es seit S2 nicht mehr) und Parameter-Hint. Anders als die frühere
// Composition.Adapters ohne Änderungsprotokoll, Updates und Editorbefehle: Code-Aktionen gibt es nicht mehr
// (OpenCodeActions bleibt nil).

interface

uses
  dpcc.IDE.CodeInsight.Manager.State;

/// <summary>Server, Ordnerbeobachter und Quellen von Vervollständigung und Parameter-Hint.</summary>
function CompletionAdapters: TDpccCodeInsightAdapters;

implementation

uses
  System.SysUtils,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Adapters.InProcess,
  dpcc.Core.Files.WatchedChanges,
  dpcc.Core.Files.Adapters.FolderWatcher,
  dpcc.Core.Signature.Contract,
  dpcc.Core.Signature.Providers.Server,
  dpcc.Core.Completion.Providers.Server,
  dpcc.Core.Completion.Providers.XmlDoc,
  dpcc.IDE.Completion.Editor;

/// <summary>Quellen der Vervollständigung: Server und XML-Doku, mit Abbau.</summary>
function CompletionSources(const ASession: TDpccSessionFunc; const ALog: TDpccLogProc): TDpccCompletionSources;
var
  mServer: TDpccServerCompletionProvider;
begin
  mServer := TDpccServerCompletionProvider.Create(ASession);
  mServer.OnLog :=
    procedure(const AMessage: string)
    begin
      ALog(AMessage);
    end;
  // Die Schnittstellen halten die Quellen; die Funktion greift über das Objekt zu.
  Result.Server := mServer;
  Result.XmlDoc := TDpccXmlDocCompletionProvider.Create;
  Result.Shutdown :=
    procedure
    begin
      mServer.Shutdown;
    end;
end;

function CompletionAdapters: TDpccCodeInsightAdapters;
begin
  Result := Default(TDpccCodeInsightAdapters);
  // Closure statt Funktion: Eine Funktion ohne Parameter würde sonst sofort aufgerufen.
  Result.NewServer :=
    function: IDpccLspServer
    begin
      Result := TLspInProcessServer.Create;
    end;
  Result.NewFolderWatcher :=
    function(AChanges: TDpccWatchedChanges): IDpccFolderWatcher
    begin
      Result := TDpccFolderWatcher.Create(AChanges);
    end;
  Result.NewSignatureSource :=
    function(ASession: TDpccSessionFunc): IDpccSignatureSource
    begin
      Result := TDpccServerSignatureProvider.Create(ASession);
    end;
  Result.NewCompletionSources :=
    function(const ASession: TDpccSessionFunc; const ALog: TDpccLogProc): TDpccCompletionSources
    begin
      Result := CompletionSources(ASession, ALog);
    end;
end;

end.
