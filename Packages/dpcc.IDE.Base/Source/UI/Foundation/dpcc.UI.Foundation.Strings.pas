unit dpcc.UI.Foundation.Strings;

// Oberflächentexte des Features IDE-Grundlagen auf Deutsch und Englisch. Die Sprache bestimmt
// `TDpccStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `dpcc.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TDpccFoundationTextId = (
    KeyConflict, ForeignCompletion, ResultsCaption, SymbolTitle, SymbolDescription, TeamFileNoProject,
    TeamFileCreated, TeamFileCreateFailed, TeamFileIssueSyntax, TeamFileIssueSyntaxAt, TeamFileIssueVersion,
    TeamFileIssueUnknownKey, TeamFileIssueWrongType, TeamFileIssueInvalidValue, TeamFileIssueCredential,
    TeamFileIssueAbsolutePath, TeamFileIssueOutsidePath, StartProfilesTemporaryRestored, ResultsSureGroup,
    ResultsInferredGroup);

  TDpccFoundationStrings = class
  public
    class function Text(AId: TDpccFoundationTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TDpccFoundationTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.UI.Strings;

const
  cTexts: array[TDpccLanguage, TDpccFoundationTextId] of string = (
    ('dpcc: %0:s ist schon belegt (%1:s); dpcc überlässt die Taste und belegt sie nicht für %2:s. ' +
       'Entscheidung unter Tools > Optionen > Drittanbieter > dpcc > Tastenkonflikte.',
     'dpcc: %s bringt eine eigene Vervollständigung mit. Laufen beide, stören sie sich; ' +
       'eine davon abschalten (dpcc: Menü dpcc > Code Insight von dpcc). dpcc ändert fremde Erweiterungen nicht.',
     'dpcc-Ergebnisse',
     'dpcc %s',
     'Delphi Pascal Code Completion: Vervollständigung, Parameterhilfe und Hover für Delphi.',
     'Projektdatei .dpcc: Es ist kein Projekt geöffnet.',
     'Projektdatei .dpcc angelegt; sie gilt für alle im Team, sobald sie eingecheckt ist.',
     'Projektdatei .dpcc konnte nicht angelegt werden: %s',
     'Projektdatei .dpcc ist fehlerhaft (kein gültiges JSON-Objekt); dpcc nutzt die persönlichen Einstellungen.',
     'Projektdatei %s ist fehlerhaft: kein gültiges JSON in Zeile %d, Spalte %d; dpcc nutzt die persönlichen Einstellungen.',
     '.dpcc: "version" fehlt oder ist neuer als diese dpcc-Version; bekannte Einträge gelten.',
     '.dpcc: Unbekannter Eintrag "%s" wird ignoriert.',
     '.dpcc: "%s" hat den falschen Typ und wird ignoriert.',
     '.dpcc: Ungültiger Wert für "%s" wird ignoriert.',
     '.dpcc: "%s" sieht nach Zugangsdaten aus und wird ignoriert; Benutzer und Token gehören in den Anmeldespeicher von Windows.',
     '.dpcc: "%s" enthält einen absoluten Pfad und wird ignoriert; Pfade relativ zur Datei angeben.',
     '.dpcc: "%s" führt aus dem Projekt heraus und wird ignoriert.',
     'dpcc: Vorübergehende Startparameter von %s zurückgestellt.',
     'Sicher (%d)',
     'Erschlossen (%d) · vor dem Umbenennen prüfen'),
    ('dpcc: %0:s is already assigned (%1:s); dpcc leaves the key and does not use it for %2:s. ' +
       'Decide under Tools > Options > Third Party > dpcc > Key conflicts.',
     'dpcc: %s brings its own code completion. Running both interferes; ' +
       'switch one off (dpcc: menu dpcc > dpcc Code Insight). dpcc does not change other extensions.',
     'dpcc Results',
     'dpcc %s',
     'Delphi Pascal Code Completion: completion, parameter hints and hover for Delphi.',
     'Project file .dpcc: no project is open.',
     'Project file .dpcc created; it applies to the whole team once it is checked in.',
     'Could not create project file .dpcc: %s',
     'Project file .dpcc is invalid (not a valid JSON object); dpcc uses the personal settings.',
     'Project file %s is invalid: no valid JSON at line %d, column %d; dpcc uses the personal settings.',
     '.dpcc: "version" is missing or newer than this dpcc version; known entries apply.',
     '.dpcc: unknown entry "%s" is ignored.',
     '.dpcc: "%s" has the wrong type and is ignored.',
     '.dpcc: invalid value for "%s" is ignored.',
     '.dpcc: "%s" looks like credentials and is ignored; user names and tokens belong in the Windows Credential Manager.',
     '.dpcc: "%s" contains an absolute path and is ignored; use paths relative to the file.',
     '.dpcc: "%s" leads outside the project and is ignored.',
     'dpcc: Temporary run parameters of %s restored.',
     'Sure (%d)',
     'Inferred (%d) · check before renaming'));

{ TDpccFoundationStrings }

class function TDpccFoundationStrings.Text(AId: TDpccFoundationTextId): string;
begin
  Result := cTexts[TDpccStrings.Language, AId];
end;

class function TDpccFoundationStrings.Fmt(AId: TDpccFoundationTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
