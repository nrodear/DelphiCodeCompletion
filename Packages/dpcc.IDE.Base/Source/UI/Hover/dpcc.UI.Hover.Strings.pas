unit dpcc.UI.Hover.Strings;

// Oberflächentexte des Features Hover auf Deutsch und Englisch. Die Sprache bestimmt
// `TDpccStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `dpcc.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.
// Seit S3b wieder die Texte des vollen Inhalts (Vererbung, Wert im Debugger, published-Mitglieder); Texte von
// Aktionen, Verlauf, Problemen, Erklärungen und Beispielen gibt es im schlichten Tooltip nicht.

interface

{$SCOPEDENUMS ON}

type
  TDpccHoverTextId = (
    AccessHover, HoverInheritance, HoverTargetType, HoverDebugPending, PublishedSummary, PublishedProperties,
    PublishedEvents, PublishedName, PublishedType, PublishedDefault, PublishedDeclared, PublishedImplicit,
    PublishedMoreProperties, PublishedMoreEvents, PublishedEventsNote, PublishedArrayProperty,
    PublishedDefaultProperty, PublishedDefaultPropertyNote, PublishedVclNote);

  TDpccHoverStrings = class
  public
    class function Text(AId: TDpccHoverTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TDpccHoverTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.UI.Strings;

const
  cTexts: array[TDpccLanguage, TDpccHoverTextId] of string = (
    ('dpcc Tooltip',
     'Vererbung',
     'Zieltyp %s',
     'wird ausgewertet …',
     'published: %d Properties · %d Ereignisse',
     'Properties',
     'Ereignisse',
     'Name',
     'Typ',
     'Vorgabe',
     'deklariert in',
     'implizit',
     '+ %d weitere Properties',
     '+ %d weitere Ereignisse',
     'erkannt am Methodenzeiger-Typ, nicht am Namen',
     'Array-Property',
     'Standard-Property',
     '„default“ heißt hier nicht Vorgabewert',
     'geerbte aus der VCL nur mit VCL-Quellen im Index'),
    ('dpcc tooltip',
     'Inheritance',
     'Target type %s',
     'evaluating …',
     'published: %d properties · %d events',
     'Properties',
     'Events',
     'Name',
     'Type',
     'Default',
     'declared in',
     'implicit',
     '+ %d more properties',
     '+ %d more events',
     'detected by method pointer type, not by name',
     'Array property',
     'Default property',
     '"default" does not mean a default value here',
     'inherited VCL members only with VCL sources in the index'));

{ TDpccHoverStrings }

class function TDpccHoverStrings.Text(AId: TDpccHoverTextId): string;
begin
  Result := cTexts[TDpccStrings.Language, AId];
end;

class function TDpccHoverStrings.Fmt(AId: TDpccHoverTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
