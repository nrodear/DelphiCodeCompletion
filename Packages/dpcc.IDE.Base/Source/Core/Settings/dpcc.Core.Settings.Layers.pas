unit dpcc.Core.Settings.Layers;

// Ebenen der Einstellungen im Dialog (#227): Standard aus dem Schema, globale
// Datei %APPDATA%\dpcc\settings.json und dpcc.json des Projekts. Vorrang wie
// im Server: Projekt vor global vor Standard. Bearbeitet wird genau eine Datei
// (global oder Projekt); im Projekt zeigt das Modell, was global gilt, und
// „Auf global zurücksetzen“ entfernt den Schlüssel aus dpcc.json.
// Geschrieben wird als Textersetzung (TDpccJsonText): Kommentare, Reihenfolge,
// Einrückung und unbekannte Schlüssel bleiben; ohne Änderung bleibt der Text
// gleich.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  dpcc.Core.Settings.Schema;

type
{$SCOPEDENUMS ON}
  /// <summary>Woher der wirksame Wert einer Einstellung kommt.</summary>
  TDpccSettingOrigin = (Default_, Global, Project);
{$SCOPEDENUMS OFF}

  TDpccSettingsModel = class
  private
    FFields: TArray<TDpccSettingField>;
    FText: string;
    FGlobal: Boolean;
    FOriginal: TArray<string>;
    FCurrent: TArray<string>;
    FInherited: TArray<string>;
    // Änderungen unterhalb eines Felds (einzelne Regel in "rules"), in Reihenfolge; die letzte gilt.
    FPaths: TArray<TPair<string, string>>;
    function GetCount: Integer;
    function GetField(AIndex: Integer): TDpccSettingField;
  public
    /// <summary>AText: Inhalt der bearbeiteten Datei ('' wenn es sie nicht gibt). AGlobalText: Inhalt der
    /// globalen Datei; nur im Projektmodus (AGlobal = False) bedeutsam.</summary>
    constructor Create(const AFields: TArray<TDpccSettingField>; const AText, AGlobalText: string;
      AGlobal: Boolean);
    /// <summary>Feld mit APath; -1 ohne.</summary>
    function IndexOf(const APath: string): Integer;
    /// <summary>Wert in der bearbeiteten Datei beim Öffnen bzw. jetzt; '' = nicht gesetzt.</summary>
    function Original(AIndex: Integer): string;
    function Current(AIndex: Integer): string;
    /// <summary>Wert der globalen Datei (Projektmodus); '' im globalen Modus.</summary>
    function Inherited_(AIndex: Integer): string;
    /// <summary>Was ohne Wert in der bearbeiteten Datei gilt: global, sonst Standard; '' ohne beides.</summary>
    function Fallback(AIndex: Integer): string;
    /// <summary>Wirksamer Wert: eigener, sonst Fallback.</summary>
    function Effective(AIndex: Integer): string;
    function Origin(AIndex: Integer): TDpccSettingOrigin;
    /// <summary>Bedienelement nach der Art des Felds (Kontrollkästchen, Zahl, Auswahl, Liste); False für
    /// Complex und für Werte, die nicht zur Art passen (z. B. profile als Objekt): Die bearbeitet der Dialog
    /// als JSON-Text.</summary>
    function Typed(AIndex: Integer): Boolean;
    /// <summary>Setzt den eigenen Wert (JSON-Text); '' entfernt ihn.</summary>
    procedure SetValue(AIndex: Integer; const AJson: string);
    /// <summary>Eigenen Wert entfernen: im Projekt „Auf global zurücksetzen“, global „Auf Standard“.</summary>
    procedure Reset(AIndex: Integer);
    /// <summary>Ändert einen Pfad unterhalb eines Felds, z. B. "rules.no-with", ohne den übrigen Wert neu zu
    /// schreiben; '' entfernt ihn.</summary>
    procedure SetPath(const APath, AJson: string);
    /// <summary>Geänderte Pfade mit JSON-Text, '' = entfernen.</summary>
    function Changes: TArray<TPair<string, string>>;
    function Modified: Boolean;
    /// <summary>Neuer Inhalt der Datei; ohne Änderung genau der alte Text.</summary>
    function ResultText: string;
    property Count: Integer read GetCount;
    property Fields[AIndex: Integer]: TDpccSettingField read GetField;
    property AllFields: TArray<TDpccSettingField> read FFields;
    property Global: Boolean read FGlobal;
    property Text: string read FText;
  end;

  TDpccSettingsFiles = class
  public const
    cGlobalFolder = 'dpcc';
    cGlobalName = 'settings.json';
    cProjectName = 'dpcc.json';
  public
    /// <summary>Globale Datei unter AAppData (%APPDATA%); '' ohne AAppData. Wie der Server.</summary>
    class function GlobalFile(const AAppData: string): string; static;
  end;

implementation

uses
  System.IOUtils,
  dpcc.Core.Settings.JsonText;

{ TDpccSettingsModel }

constructor TDpccSettingsModel.Create(const AFields: TArray<TDpccSettingField>; const AText, AGlobalText: string;
  AGlobal: Boolean);
var
  mRoot, mGlobalRoot: TJSONObject;
  mIndex: Integer;
begin
  inherited Create;
  FFields := AFields;
  FText := AText;
  FGlobal := AGlobal;
  SetLength(FOriginal, Length(FFields));
  SetLength(FCurrent, Length(FFields));
  SetLength(FInherited, Length(FFields));
  mRoot := TDpccJsonText.Parse(AText);
  mGlobalRoot := nil;
  if not AGlobal then
  begin
    mGlobalRoot := TDpccJsonText.Parse(AGlobalText);
  end;
  try
    for mIndex := 0 to High(FFields) do
    begin
      if mRoot <> nil then
      begin
        FOriginal[mIndex] := TDpccJsonText.ValueAt(mRoot, FFields[mIndex].Path);
      end;
      FCurrent[mIndex] := FOriginal[mIndex];
      if mGlobalRoot <> nil then
      begin
        FInherited[mIndex] := TDpccJsonText.ValueAt(mGlobalRoot, FFields[mIndex].Path);
      end;
    end;
  finally
    mGlobalRoot.Free;
    mRoot.Free;
  end;
end;

function TDpccSettingsModel.GetCount: Integer;
begin
  Result := Length(FFields);
end;

function TDpccSettingsModel.GetField(AIndex: Integer): TDpccSettingField;
begin
  Result := FFields[AIndex];
end;

function TDpccSettingsModel.IndexOf(const APath: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FFields) do
  begin
    if SameText(FFields[mIndex].Path, APath) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TDpccSettingsModel.Original(AIndex: Integer): string;
begin
  Result := FOriginal[AIndex];
end;

function TDpccSettingsModel.Current(AIndex: Integer): string;
begin
  Result := FCurrent[AIndex];
end;

function TDpccSettingsModel.Inherited_(AIndex: Integer): string;
begin
  Result := FInherited[AIndex];
end;

function TDpccSettingsModel.Fallback(AIndex: Integer): string;
begin
  Result := FInherited[AIndex];
  if Result = '' then
  begin
    Result := FFields[AIndex].DefaultJson;
  end;
end;

function TDpccSettingsModel.Effective(AIndex: Integer): string;
begin
  Result := FCurrent[AIndex];
  if Result = '' then
  begin
    Result := Fallback(AIndex);
  end;
end;

function TDpccSettingsModel.Origin(AIndex: Integer): TDpccSettingOrigin;
begin
  if FCurrent[AIndex] <> '' then
  begin
    if FGlobal then
    begin
      Result := TDpccSettingOrigin.Global;
    end
    else
    begin
      Result := TDpccSettingOrigin.Project;
    end;
  end
  else if FInherited[AIndex] <> '' then
  begin
    Result := TDpccSettingOrigin.Global;
  end
  else
  begin
    Result := TDpccSettingOrigin.Default_;
  end;
end;

function TDpccSettingsModel.Typed(AIndex: Integer): Boolean;
begin
  Result := (FFields[AIndex].Kind <> TDpccSettingKind.Complex) and FFields[AIndex].Accepts(FOriginal[AIndex]) and
    FFields[AIndex].Accepts(Fallback(AIndex));
end;

procedure TDpccSettingsModel.SetValue(AIndex: Integer; const AJson: string);
begin
  FCurrent[AIndex] := AJson;
end;

procedure TDpccSettingsModel.Reset(AIndex: Integer);
begin
  FCurrent[AIndex] := '';
end;

function TDpccSettingsModel.Changes: TArray<TPair<string, string>>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(FFields) do
  begin
    if FCurrent[mIndex] <> FOriginal[mIndex] then
    begin
      Result := Result + [TPair<string, string>.Create(FFields[mIndex].Path, FCurrent[mIndex])];
    end;
  end;
  Result := Result + FPaths;
end;

procedure TDpccSettingsModel.SetPath(const APath, AJson: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FPaths) do
  begin
    if SameText(FPaths[mIndex].Key, APath) then
    begin
      FPaths[mIndex].Value := AJson;
      Exit;
    end;
  end;
  FPaths := FPaths + [TPair<string, string>.Create(APath, AJson)];
end;

function TDpccSettingsModel.Modified: Boolean;
begin
  Result := Length(Changes) > 0;
end;

function TDpccSettingsModel.ResultText: string;
var
  mPending: TArray<TPair<string, string>>;
begin
  mPending := Changes;
  if Length(mPending) = 0 then
  begin
    Exit(FText);
  end;
  Result := TDpccJsonText.ApplyChanges(FText, mPending);
end;

{ TDpccSettingsFiles }

class function TDpccSettingsFiles.GlobalFile(const AAppData: string): string;
begin
  Result := '';
  if AAppData <> '' then
  begin
    Result := TPath.Combine(TPath.Combine(AAppData, cGlobalFolder), cGlobalName);
  end;
end;

end.
