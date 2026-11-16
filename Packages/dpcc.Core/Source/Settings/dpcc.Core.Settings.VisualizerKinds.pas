unit dpcc.Core.Settings.VisualizerKinds;

// Arten und Grenzen der Visualisierer (#835) für debug.visualizers.*: Namen
// der Arten (types), Auswertungsstufe (evaluation), Namensfelder (nameFields)
// und die Grenzen von maxLength, timeoutMs und maxImagePixels. Liegt bei den
// Einstellungen, damit der Parser ohne den Debug-Kern auskommt (sonst
// Feature-Zyklus Settings -> Debug -> Files/Hover/Lsp -> Settings); die
// Ersatztexte und Ansichten rechnet dpcc.Core.Debug.Visualizers.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TDpccVisualizerKind = (Lists, Dictionaries, DataSets, Bytes, Json, Colors, Guid, Geometry, Graphics);
  /// <summary>Wie weit dpcc für einen Wert auswerten darf (debug.visualizers.evaluation): nur Felder, auch Getter
  /// von Eigenschaften, auch Funktionsaufrufe.</summary>
  TDpccVisualizerEvaluation = (Fields, Properties, Calls);
  {$SCOPEDENUMS OFF}

  TDpccVisualizerKinds = set of TDpccVisualizerKind;

  TDpccVisualizerSettings = class
  public const
    cDefaultMaxLength = 120;
    cMinMaxLength = 20;
    cMaxMaxLength = 2000;
    cDefaultTimeoutMs = 200;
    cMinTimeoutMs = 20;
    cMaxTimeoutMs = 5000;
    cDefaultMaxImagePixels = 4000000;
    cMinMaxImagePixels = 10000;
    cMaxMaxImagePixels = 64000000;
    cAllKinds = [Low(TDpccVisualizerKind)..High(TDpccVisualizerKind)];
    cKindNames: array[TDpccVisualizerKind] of string = ('lists', 'dictionaries', 'dataSets', 'bytes', 'json',
      'colors', 'guid', 'geometry', 'graphics');
    cEvaluationNames: array[TDpccVisualizerEvaluation] of string = ('fields', 'properties', 'calls');
    cDefaultNameFields = 'Name,Caption,Text';
  public
    /// <summary>Kommagetrennte Arten wie in debug.visualizers.types; unbekannte fallen weg, '' = keine.</summary>
    class function ParseKinds(const AText: string): TDpccVisualizerKinds; static;
    class function KindsText(AKinds: TDpccVisualizerKinds): string; static;
    /// <summary>Normalisiert die Liste: bekannte Namen in fester Reihenfolge, Groß-/Kleinschreibung wie oben.</summary>
    class function NormalizeKinds(const AText: string): string; static;
    class function ParseEvaluation(const AText: string): TDpccVisualizerEvaluation; static;
    /// <summary>Kommagetrennte Feldnamen (debug.visualizers.nameFields), getrimmt, ohne leere und doppelte.</summary>
    class function ParseNameFields(const AText: string): TArray<string>; static;
    class function NormalizeNameFields(const AText: string): string; static;
  end;

implementation

{ TDpccVisualizerSettings }

class function TDpccVisualizerSettings.ParseKinds(const AText: string): TDpccVisualizerKinds;
var
  mPart: string;
  mKind: TDpccVisualizerKind;
begin
  Result := [];
  for mPart in AText.Split([',', ';']) do
  begin
    for mKind := Low(TDpccVisualizerKind) to High(TDpccVisualizerKind) do
    begin
      if SameText(Trim(mPart), cKindNames[mKind]) then
      begin
        Include(Result, mKind);
      end;
    end;
  end;
end;

class function TDpccVisualizerSettings.KindsText(AKinds: TDpccVisualizerKinds): string;
var
  mKind: TDpccVisualizerKind;
begin
  Result := '';
  for mKind := Low(TDpccVisualizerKind) to High(TDpccVisualizerKind) do
  begin
    if mKind in AKinds then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cKindNames[mKind];
    end;
  end;
end;

class function TDpccVisualizerSettings.NormalizeKinds(const AText: string): string;
begin
  Result := KindsText(ParseKinds(AText));
end;

class function TDpccVisualizerSettings.ParseEvaluation(const AText: string): TDpccVisualizerEvaluation;
var
  mItem: TDpccVisualizerEvaluation;
begin
  for mItem := Low(TDpccVisualizerEvaluation) to High(TDpccVisualizerEvaluation) do
  begin
    if SameText(Trim(AText), cEvaluationNames[mItem]) then
    begin
      Exit(mItem);
    end;
  end;
  Result := TDpccVisualizerEvaluation.Properties;
end;

class function TDpccVisualizerSettings.ParseNameFields(const AText: string): TArray<string>;
var
  mPart, mName, mKnown: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mPart in AText.Split([',', ';']) do
  begin
    mName := Trim(mPart);
    if (mName = '') or not IsValidIdent(mName) then
    begin
      Continue;
    end;
    mSeen := False;
    for mKnown in Result do
    begin
      if SameText(mKnown, mName) then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TDpccVisualizerSettings.NormalizeNameFields(const AText: string): string;
begin
  Result := string.Join(',', ParseNameFields(AText));
end;

end.
