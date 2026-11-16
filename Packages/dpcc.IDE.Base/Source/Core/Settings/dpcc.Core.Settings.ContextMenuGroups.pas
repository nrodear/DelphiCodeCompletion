unit dpcc.Core.Settings.ContextMenuGroups;

// Untermenüs von dpcc im Kontextmenü des Editors für
// commands.editorContextMenu.groups: kommagetrennte feste Kennungen
// ("navigation,edit,analysis,findings,debug,tests,notes"); unbekannte fallen
// weg, die Reihenfolge ist fest. Liegt bei den Einstellungen, damit der Parser
// ohne das Kontextmenü auskommt. Die Kennungen debug, tests und notes setzen
// die Module an ihren Einträgen (TDpccMenuEntry.Group).

interface

type
{$SCOPEDENUMS ON}
  TDpccContextMenuGroup = (Navigation, Edit, Analysis, Findings, Debug, Tests, Notes);
{$SCOPEDENUMS OFF}
  TDpccContextMenuGroups = set of TDpccContextMenuGroup;

  TDpccContextMenuGroupNames = class
  public const
    cAll = [TDpccContextMenuGroup.Navigation, TDpccContextMenuGroup.Edit, TDpccContextMenuGroup.Analysis,
      TDpccContextMenuGroup.Findings, TDpccContextMenuGroup.Debug, TDpccContextMenuGroup.Tests,
      TDpccContextMenuGroup.Notes];
  public
    class function Name(AGroup: TDpccContextMenuGroup): string; static;
    class function Parse(const AText: string): TDpccContextMenuGroups; static;
    class function Text(AGroups: TDpccContextMenuGroups): string; static;
    /// <summary>Bekannte Namen in fester Reihenfolge, ohne Doppelte.</summary>
    class function Normalize(const AText: string): string; static;
    /// <summary>Zeigt die Einstellung AText das Untermenü mit der Kennung AKey? '' und unbekannte Kennungen
    /// (etwa eines neueren Moduls) immer.</summary>
    class function Shown(const AText, AKey: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

const
  cNames: array[TDpccContextMenuGroup] of string = ('navigation', 'edit', 'analysis', 'findings', 'debug', 'tests',
    'notes');

class function TDpccContextMenuGroupNames.Name(AGroup: TDpccContextMenuGroup): string;
begin
  Result := cNames[AGroup];
end;

class function TDpccContextMenuGroupNames.Parse(const AText: string): TDpccContextMenuGroups;
var
  mPart: string;
  mGroup: TDpccContextMenuGroup;
begin
  Result := [];
  for mPart in AText.Split([',', ';', ' ']) do
  begin
    for mGroup := Low(TDpccContextMenuGroup) to High(TDpccContextMenuGroup) do
    begin
      if SameText(Trim(mPart), cNames[mGroup]) then
      begin
        Include(Result, mGroup);
      end;
    end;
  end;
end;

class function TDpccContextMenuGroupNames.Text(AGroups: TDpccContextMenuGroups): string;
var
  mGroup: TDpccContextMenuGroup;
begin
  Result := '';
  for mGroup := Low(TDpccContextMenuGroup) to High(TDpccContextMenuGroup) do
  begin
    if mGroup in AGroups then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cNames[mGroup];
    end;
  end;
end;

class function TDpccContextMenuGroupNames.Normalize(const AText: string): string;
begin
  Result := Text(Parse(AText));
end;

class function TDpccContextMenuGroupNames.Shown(const AText, AKey: string): Boolean;
var
  mGroup: TDpccContextMenuGroup;
begin
  Result := True;
  for mGroup := Low(TDpccContextMenuGroup) to High(TDpccContextMenuGroup) do
  begin
    if SameText(AKey, cNames[mGroup]) then
    begin
      Result := mGroup in Parse(AText);
      Exit;
    end;
  end;
end;

end.
