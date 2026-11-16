unit dpcc.Core.Modules.Contributions;

// Beiträge der Module einsammeln (#1455, Regel 2 und 4): Base fragt die
// Registry bei Bedarf nach allen bereitgestellten Quellen, statt sie einmal
// beim Start zu lesen. So erscheinen und verschwinden Befehle, Menüeinträge
// und Hörer mit ihrem Modul. Ein Fehler in einem Beitrag hält die übrigen nicht
// an; ApplySettings und ThemeChanged liefern die Fehler als
// „Interface: Klasse: Meldung“.
// Es zählen nur Beiträge laufender Module (IsActive): Ein über seinen
// Schalter gestopptes Modul (#1454) bleibt angemeldet, zeigt aber keine
// Befehle, Menüeinträge und Tasten mehr und hört nichts. Beiträge ohne
// angemeldetes Modul als Besitzer (Base selbst) zählen immer.

interface

uses
  System.SysUtils,
  dpcc.Core.Modules.Contract;

type
  TDpccModuleContributions = class
  public
    /// <summary>Unter AIID bereitgestellte Objekte laufender Module (und solche ohne Modul) in Reihenfolge der
    /// Bereitstellung; ohne Registry leer.</summary>
    class function Active(const ARegistry: IDpccModuleRegistry; const AIID: TGUID): TArray<IInterface>; static;
    /// <summary>Alle Befehle in Reihenfolge der Bereitstellung; ohne Registry leer.</summary>
    class function Commands(const ARegistry: IDpccModuleRegistry): TArray<TDpccModuleCommand>; static;
    /// <summary>Befehl AId; False, wenn ihn kein Modul anbietet.</summary>
    class function FindCommand(const ARegistry: IDpccModuleRegistry; const AId: string;
      out ACommand: TDpccModuleCommand): Boolean; static;
    /// <summary>Sichtbar ist ein Befehl ohne Visible oder wenn Visible True liefert.</summary>
    class function IsVisible(const ACommand: TDpccModuleCommand): Boolean; static;
    /// <summary>Menüeinträge für APlace in Reihenfolge der Bereitstellung.</summary>
    class function MenuEntries(const ARegistry: IDpccModuleRegistry;
      APlace: TDpccMenuPlace): TArray<TDpccMenuEntry>; static;
    /// <summary>Eintrag ohne Befehl mit der Kennung AId an APlace (Caption gesetzt); False ohne.</summary>
    class function FindMenuEntry(const ARegistry: IDpccModuleRegistry; APlace: TDpccMenuPlace; const AId: string;
      out AEntry: TDpccMenuEntry): Boolean; static;
    /// <summary>Tastenkürzel aller Module; Einträge ohne Taste (0) oder ohne Attempt und Run fehlen.</summary>
    class function Keys(const ARegistry: IDpccModuleRegistry): TArray<TDpccModuleKey>; static;
    class function EditorViewActivated(const ARegistry: IDpccModuleRegistry): TArray<string>; static;
    class function ApplySettings(const ARegistry: IDpccModuleRegistry): TArray<string>; static;
    class function ThemeChanged(const ARegistry: IDpccModuleRegistry): TArray<string>; static;
    /// <summary>Erster nicht leerer Beitrag; '' ohne.</summary>
    class function HoverValue(const ARegistry: IDpccModuleRegistry; const AExpression: string;
      const ATypeChain: TArray<string>; const AText: string): string; static;
  end;

implementation

uses
  dpcc.Text.LogMarks;

class function TDpccModuleContributions.Active(const ARegistry: IDpccModuleRegistry;
  const AIID: TGUID): TArray<IInterface>;
var
  mItem: TDpccProvided;
  mModule: IDpccModule;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in ARegistry.Provisions(AIID) do
  begin
    if not ARegistry.FindModule(mItem.OwnerId, mModule) or mModule.IsActive then
    begin
      Result := Result + [mItem.Instance];
    end;
  end;
end;

class function TDpccModuleContributions.Commands(const ARegistry: IDpccModuleRegistry): TArray<TDpccModuleCommand>;
var
  mItem: IInterface;
  mSource: IDpccCommandSource;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IDpccCommandSource) do
  begin
    if Supports(mItem, IDpccCommandSource, mSource) then
    begin
      Result := Result + mSource.Commands;
    end;
  end;
end;

class function TDpccModuleContributions.FindCommand(const ARegistry: IDpccModuleRegistry; const AId: string;
  out ACommand: TDpccModuleCommand): Boolean;
var
  mCommand: TDpccModuleCommand;
begin
  Result := False;
  ACommand := Default(TDpccModuleCommand);
  for mCommand in Commands(ARegistry) do
  begin
    if SameText(mCommand.Id, AId) then
    begin
      ACommand := mCommand;
      Exit(True);
    end;
  end;
end;

class function TDpccModuleContributions.IsVisible(const ACommand: TDpccModuleCommand): Boolean;
begin
  Result := not Assigned(ACommand.Visible) or ACommand.Visible();
end;

class function TDpccModuleContributions.MenuEntries(const ARegistry: IDpccModuleRegistry;
  APlace: TDpccMenuPlace): TArray<TDpccMenuEntry>;
var
  mItem: IInterface;
  mSource: IDpccMenuSource;
  mEntry: TDpccMenuEntry;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IDpccMenuSource) do
  begin
    if Supports(mItem, IDpccMenuSource, mSource) then
    begin
      for mEntry in mSource.MenuEntries do
      begin
        if mEntry.Place = APlace then
        begin
          Result := Result + [mEntry];
        end;
      end;
    end;
  end;
end;

class function TDpccModuleContributions.FindMenuEntry(const ARegistry: IDpccModuleRegistry;
  APlace: TDpccMenuPlace; const AId: string; out AEntry: TDpccMenuEntry): Boolean;
var
  mEntry: TDpccMenuEntry;
begin
  Result := False;
  AEntry := Default(TDpccMenuEntry);
  for mEntry in MenuEntries(ARegistry, APlace) do
  begin
    if (mEntry.Caption <> '') and SameText(mEntry.CommandId, AId) then
    begin
      AEntry := mEntry;
      Exit(True);
    end;
  end;
end;

class function TDpccModuleContributions.Keys(const ARegistry: IDpccModuleRegistry): TArray<TDpccModuleKey>;
var
  mItem: IInterface;
  mSource: IDpccKeySource;
  mKey: TDpccModuleKey;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IDpccKeySource) do
  begin
    if Supports(mItem, IDpccKeySource, mSource) then
    begin
      for mKey in mSource.Keys do
      begin
        if (mKey.Key <> 0) and (Assigned(mKey.Attempt) or Assigned(mKey.Run)) then
        begin
          Result := Result + [mKey];
        end;
      end;
    end;
  end;
end;

class function TDpccModuleContributions.EditorViewActivated(const ARegistry: IDpccModuleRegistry): TArray<string>;
var
  mItem: IInterface;
  mListener: IDpccFollowsEditorView;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IDpccFollowsEditorView) do
  begin
    if Supports(mItem, IDpccFollowsEditorView, mListener) then
      try
        mListener.EditorViewActivated;
      except
        on mError: Exception do
          Result := Result + ['IDpccFollowsEditorView: ' + mError.ClassName + ': ' + TLogMarks.Text(mError.Message)];
      end;
  end;
end;

class function TDpccModuleContributions.ApplySettings(const ARegistry: IDpccModuleRegistry): TArray<string>;
var
  mItem: IInterface;
  mListener: IDpccAppliesSettings;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IDpccAppliesSettings) do
  begin
    if Supports(mItem, IDpccAppliesSettings, mListener) then
      try
        mListener.ApplySettings;
      except
        on mError: Exception do
          Result := Result + ['IDpccAppliesSettings: ' + mError.ClassName + ': ' + TLogMarks.Text(mError.Message)];
      end;
  end;
end;

class function TDpccModuleContributions.ThemeChanged(const ARegistry: IDpccModuleRegistry): TArray<string>;
var
  mItem: IInterface;
  mListener: IDpccFollowsTheme;
begin
  Result := nil;
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IDpccFollowsTheme) do
  begin
    if Supports(mItem, IDpccFollowsTheme, mListener) then
      try
        mListener.ThemeChanged;
      except
        on mError: Exception do
          Result := Result + ['IDpccFollowsTheme: ' + mError.ClassName + ': ' + TLogMarks.Text(mError.Message)];
      end;
  end;
end;

class function TDpccModuleContributions.HoverValue(const ARegistry: IDpccModuleRegistry; const AExpression: string;
  const ATypeChain: TArray<string>; const AText: string): string;
var
  mItem: IInterface;
  mSource: IDpccHoverValueSource;
begin
  Result := '';
  if ARegistry = nil then
  begin
    Exit;
  end;
  for mItem in Active(ARegistry, IDpccHoverValueSource) do
  begin
    if Supports(mItem, IDpccHoverValueSource, mSource) then
    begin
      Result := mSource.HoverValue(AExpression, ATypeChain, AText);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  end;
end;

end.
