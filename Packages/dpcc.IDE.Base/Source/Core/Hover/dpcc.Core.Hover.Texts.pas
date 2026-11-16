unit dpcc.Core.Hover.Texts;

// Texte des Hover-Tooltips: Das Fenster (dpcc.UI.Hover.Tip) füllt sie aus dpcc.UI.Strings bzw.
// dpcc.UI.Hover.Strings, der Inhalt (dpcc.Core.Hover.Plain) liest sie nur.
// Seit S3b nur noch Texte des Inhalts: Beschriftungen von Aktionen, Verlauf, Problemen, Erklärungen und
// Beispielen gibt es im schlichten Tooltip nicht.

interface

type
  /// <summary>Texte der Oberfläche in ihrer Sprache (Core kennt dpcc.UI.Strings nicht).</summary>
  TDpccHoverTexts = record
    /// <summary>Art zu Data.Kind (Klasse, Methode …); '' wenn unbekannt.</summary>
    KindCaption: string;
    Inheritance: string;
    /// <summary>Format mit %s für den Typ der Kette.</summary>
    TargetType: string;
    /// <summary>Statt des Werts, solange der Debugger noch auswertet (#891).</summary>
    DebugPending: string;
    /// <summary>published-Mitglieder (#110): Format mit %d, %d für Properties und Ereignisse; Abschnitte,
    /// Spaltenköpfe, Formate „+ %d weitere …“ und Hinweise.</summary>
    PublishedSummary: string;
    PublishedProperties: string;
    PublishedEvents: string;
    PublishedName: string;
    PublishedType: string;
    PublishedDefault: string;
    PublishedDeclared: string;
    PublishedImplicit: string;
    PublishedMoreProperties: string;
    PublishedMoreEvents: string;
    PublishedEventsNote: string;
    PublishedArrayProperty: string;
    PublishedDefaultProperty: string;
    PublishedDefaultPropertyNote: string;
    PublishedVclNote: string;
  end;

implementation

end.
