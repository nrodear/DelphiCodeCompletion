unit dpcc.Core.Problems.Contract;

// Probleme im Editor (#398): Diagnosen des Servers (Syntaxfehler, Regeltreffer,
// Compilermeldungen mit source "dcc") als Datensatz des Plugins. Positionen
// sind 0-basiert in UTF-16-Einheiten wie im LSP.
// TDpccIdeError (#1819): ein Fehler aus Error Insight der IDE, roh wie in
// TOTAError (früher vom Modul Prüfregeln geliefert; die Umrechnung ist seit S7a
// mit den übrigen Teilen der Prüfung entfernt).

interface

uses
  dpcc.Core.Lsp.Contract;

type
  /// <summary>Liegt im Lsp-Feature (die Protokollschicht liegt unten); Alias für bestehende Nutzer.</summary>
  TDpccProblemSeverity = dpcc.Core.Lsp.Contract.TDpccProblemSeverity;
  TDpccProblem = dpcc.Core.Lsp.Contract.TDpccProblem;
  TDpccProblemRelated = dpcc.Core.Lsp.Contract.TDpccProblemRelated;

  /// <summary>Ein Fehler aus Error Insight der IDE (#1819), Werte wie in TOTAError: Zeilen 1-basiert, Spalten
  /// (CharIndex) wie geliefert, Severity roh.</summary>
  TDpccIdeError = record
    Text: string;
    StartLine: Integer;
    StartCharIndex: Integer;
    StopLine: Integer;
    StopCharIndex: Integer;
    Severity: Integer;
  end;

implementation

end.
