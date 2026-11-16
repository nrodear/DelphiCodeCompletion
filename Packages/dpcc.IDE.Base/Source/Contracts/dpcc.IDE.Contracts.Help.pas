unit dpcc.IDE.Contracts.Help;

// Vertrag zwischen Base und Modulen (#1886, Modulregel 6): „Hilfe zum Element“. Ein Modul, das Hilfe
// zeigen kann (dpcc.IDE.Help), stellt über seinen Scope eine IDpccHelpProvider bereit. Base meldet nur die
// Kennung des Elements unter dem Fokus: die Regel eines Befunds, den Schlüssel einer Einstellung oder die Kennung
// eines dpcc-Fensters (Identifier des Dockfensters). Ohne laufenden Anbieter bleibt F1 bei der IDE. Nur Typen
// und Interfaces, kein Code.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Art des Elements: Regel eines Befunds, Einstellung (x-key) oder dpcc-Fenster.</summary>
  TDpccHelpKind = (Rule, Setting, Window);
{$SCOPEDENUMS OFF}

  /// <summary>Element, zu dem Hilfe gewünscht ist. Id: Regel-ID, Schlüssel bzw. Kennung des Fensters.</summary>
  TDpccHelpTopic = record
    Kind: TDpccHelpKind;
    Id: string;
  end;

  /// <summary>Zeigt Hilfe zu einem Element. Aufrufe im Hauptthread der IDE.</summary>
  IDpccHelpProvider = interface
    ['{07357BFF-2263-42DA-8CEE-EA0618F3AB4C}']
    /// <summary>Kennt der Anbieter eine Seite zu ATopic?</summary>
    function HasHelp(const ATopic: TDpccHelpTopic): Boolean;
    /// <summary>Seite zu ATopic öffnen; False, wenn der Anbieter keine kennt.</summary>
    function ShowHelp(const ATopic: TDpccHelpTopic): Boolean;
  end;

implementation

end.
