unit dpcc.Core.Generate.Contract;

// Gruppen und Listen des Erzeugen-Menüs (#719), wie sie in den Einstellungen stehen
// (keys.generateMenu.groups, keys.generateMenu.hidden). Eigene Unit, damit die Einstellungen sie
// normalisieren können, ohne das Menü (und darüber den LSP-Client) zu importieren.

interface

type
  {$SCOPEDENUMS ON}
  /// <summary>Recent ist keine eigene Herkunft, nur die Gruppe „Zuletzt gewählt“ oben.</summary>
  TDpccGenerateGroup = (Recent, Generate, Surround, Templates);
  {$SCOPEDENUMS OFF}

  TDpccGenerateLists = record
    /// <summary>Durch Komma, Semikolon oder Zeilenwechsel getrennt; getrimmt, ohne leere Einträge.</summary>
    class function Split(const AText: string): TArray<string>; static;
    /// <summary>generate, surround, templates bzw. recent.</summary>
    class function GroupName(AGroup: TDpccGenerateGroup): string; static;
    class function TryParseGroup(const AName: string; out AGroup: TDpccGenerateGroup): Boolean; static;
    /// <summary>Bekannte Gruppen ohne Doppelte; leer bzw. ohne bekannte Gruppe: die Vorgabe.</summary>
    class function ParseGroups(const AText: string): TArray<TDpccGenerateGroup>; static;
    /// <summary>Für die Einstellung: "generate,surround,templates" in der gewählten Reihenfolge.</summary>
    class function NormalizeGroups(const AText: string): string; static;
    /// <summary>Für die Einstellung: getrimmt, ohne leere und doppelte Einträge, mit ", " verbunden.</summary>
    class function NormalizeHidden(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  cDefaultGroups: array[0..2] of TDpccGenerateGroup = (TDpccGenerateGroup.Generate, TDpccGenerateGroup.Surround,
    TDpccGenerateGroup.Templates);

class function TDpccGenerateLists.Split(const AText: string): TArray<string>;
var
  mItem: string;
begin
  Result := nil;
  for mItem in AText.Split([',', ';', #10]) do
  begin
    if Trim(mItem) <> '' then
    begin
      Result := Result + [Trim(mItem)];
    end;
  end;
end;

class function TDpccGenerateLists.GroupName(AGroup: TDpccGenerateGroup): string;
begin
  case AGroup of
    TDpccGenerateGroup.Generate:
      Result := 'generate';
    TDpccGenerateGroup.Surround:
      Result := 'surround';
    TDpccGenerateGroup.Templates:
      Result := 'templates';
  else
    Result := 'recent';
  end;
end;

class function TDpccGenerateLists.TryParseGroup(const AName: string; out AGroup: TDpccGenerateGroup): Boolean;
var
  mGroup: TDpccGenerateGroup;
begin
  for mGroup := Low(TDpccGenerateGroup) to High(TDpccGenerateGroup) do
  begin
    if SameText(Trim(AName), GroupName(mGroup)) then
    begin
      AGroup := mGroup;
      Exit(True);
    end;
  end;
  AGroup := TDpccGenerateGroup.Generate;
  Result := False;
end;

class function TDpccGenerateLists.ParseGroups(const AText: string): TArray<TDpccGenerateGroup>;
var
  mItem: string;
  mGroup, mKnown: TDpccGenerateGroup;
  mSeen: Boolean;
begin
  Result := nil;
  for mItem in Split(AText) do
  begin
    // "recent" ist keine Gruppe der Liste; dafür gibt es recentFirst.
    if not TryParseGroup(mItem, mGroup) or (mGroup = TDpccGenerateGroup.Recent) then
    begin
      Continue;
    end;
    mSeen := False;
    for mKnown in Result do
    begin
      if mKnown = mGroup then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mGroup];
    end;
  end;
  if Length(Result) = 0 then
  begin
    for mGroup in cDefaultGroups do
    begin
      Result := Result + [mGroup];
    end;
  end;
end;

class function TDpccGenerateLists.NormalizeGroups(const AText: string): string;
var
  mGroup: TDpccGenerateGroup;
begin
  Result := '';
  for mGroup in ParseGroups(AText) do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + GroupName(mGroup);
  end;
end;

class function TDpccGenerateLists.NormalizeHidden(const AText: string): string;
var
  mItem: string;
  mItems: TArray<string>;
begin
  mItems := nil;
  for mItem in Split(AText) do
  begin
    if IndexText(mItem, mItems) < 0 then
    begin
      mItems := mItems + [mItem];
    end;
  end;
  Result := string.Join(', ', mItems);
end;

end.
