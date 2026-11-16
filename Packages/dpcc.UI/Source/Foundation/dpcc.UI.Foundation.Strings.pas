unit dpcc.UI.Foundation.Strings;

// Oberflächentexte des Features IDE-Grundlagen auf Deutsch und Englisch. Die Sprache bestimmt
// `TDpccStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `dpcc.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TDpccFoundationTextId = (
    SymbolTitle, SymbolDescription);

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
    ('dpcc %s',
     'Delphi Pascal Code Completion: Vervollständigung, Parameterhilfe und Hover für Delphi.'),
    ('dpcc %s',
     'Delphi Pascal Code Completion: completion, parameter hints and hover for Delphi.'));

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
