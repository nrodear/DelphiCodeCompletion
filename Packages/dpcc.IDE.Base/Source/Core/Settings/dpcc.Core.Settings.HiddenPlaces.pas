unit dpcc.Core.Settings.HiddenPlaces;

// Ausgeblendete Stellen in der Projektdatei .dpcc (#628, #486), ohne VCL und
// Open Tools API. „Nur hier ausblenden“ und „In dieser Datei ausblenden“ an
// einem gezeichneten Element (außer Befunden mit Regel, die bekommen einen
// Unterdrückungskommentar #147) legen einen Eintrag im Abschnitt "hidden" an:
//   "hidden": [
//     {"setting": "BlockEndLabels", "file": "Source/Kunde.pas", "anchor": "TKunde.Speichern"},
//     {"setting": "InlayHints", "file": "Source/Kunde.pas"}
//   ]
// "setting" ist der Schlüssel der Einstellung des Elements, "file" der Pfad
// relativ zum Ordner der .dpcc (Trenner "/"), "anchor" der Anker des Elements
// (Name der Methode, Beschriftung oder normierte Codezeile); ohne "anchor" gilt
// der Eintrag für die ganze Datei. Der Anker hängt am Inhalt, nicht an der
// Zeilennummer: Einfügen von Zeilen darüber ändert nichts.
// TDpccHiddenIndex beantwortet beim Zeichnen schnell, ob ein Element
// ausgeblendet ist; AddTo und RemoveFrom ändern nur den Abschnitt "hidden" im
// Text der Datei (Kommentare und übrige Werte bleiben, TDpccJsonText).

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TDpccHiddenPlace = record
    /// <summary>Schlüssel der Einstellung des Elements, z. B. "BlockEndLabels".</summary>
    Setting: string;
    /// <summary>Pfad relativ zum Ordner der .dpcc, Trenner "/".</summary>
    FileName: string;
    /// <summary>Anker des Elements; '' = ganze Datei.</summary>
    Anchor: string;
    class function Create(const ASetting, AFileName, AAnchor: string): TDpccHiddenPlace; static;
    /// <summary>Gleiche Einstellung und Datei (ohne Groß-/Kleinschreibung, "\" wie "/") und gleicher Anker.
    /// </summary>
    function SameAs(const AOther: TDpccHiddenPlace): Boolean;
    function WholeFile: Boolean;
  end;

  TDpccHiddenPlaces = class
  public const
    cKey = 'hidden';
  public
    /// <summary>AFileName relativ zu AFolder mit "/"; False, wenn die Datei nicht unter AFolder liegt.</summary>
    class function Relative(const AFolder, AFileName: string; out ARelative: string): Boolean; static;
    /// <summary>Pfad mit "/" als Trenner, ohne "./" am Anfang.</summary>
    class function NormalizePath(const APath: string): string; static;
    class function IndexOf(const APlaces: TArray<TDpccHiddenPlace>; const APlace: TDpccHiddenPlace): Integer; static;
    /// <summary>JSON-Text des Abschnitts (Array, eine Zeile je Eintrag, eingerückt mit AIndent).</summary>
    class function ToJson(const APlaces: TArray<TDpccHiddenPlace>; const AIndent, ALineBreak: string): string; static;
    /// <summary>Text der .dpcc mit APlace im Abschnitt "hidden"; unverändert, wenn er schon drin steht. Leerer
    /// Text: ASkeleton als Grundlage.</summary>
    class function AddTo(const AText, ASkeleton: string; const APlace: TDpccHiddenPlace): string; static;
    /// <summary>Text der .dpcc ohne APlace; unverändert, wenn er fehlt.</summary>
    class function RemoveFrom(const AText: string; const APlace: TDpccHiddenPlace): string; static;
    /// <summary>Einträge aus dem Text der .dpcc (ohne Prüfung, für AddTo/RemoveFrom; das Lesen mit Prüfung
    /// übernimmt TDpccTeamFile.Parse).</summary>
    class function FromText(const AText: string): TArray<TDpccHiddenPlace>; static;
  end;

  /// <summary>Schnelle Abfrage beim Zeichnen; gilt für einen Stand der .dpcc.</summary>
  TDpccHiddenIndex = class
  private
    FFolder: string;
    /// <summary>"setting|datei" (klein) → Anker; '' im Wert steht für die ganze Datei.</summary>
    FAnchors: TObjectDictionary<string, TList<string>>;
    FLastFile: string;
    FLastRelative: string;
    FLastInside: Boolean;
    function Lookup(const ASetting, AFileName: string; out AAnchors: TList<string>): Boolean;
  public
    /// <summary>AFolder: Ordner der .dpcc; leer = keine Einträge wirksam.</summary>
    constructor Create(const APlaces: TArray<TDpccHiddenPlace>; const AFolder: string);
    destructor Destroy; override;
    function IsEmpty: Boolean;
    /// <summary>Element mit ASetting in AFileName (vollständiger Pfad) ganz ausgeblendet?</summary>
    function FileHidden(const ASetting, AFileName: string): Boolean;
    /// <summary>Element an AAnchor ausgeblendet (ganze Datei oder genau dieser Anker)?</summary>
    function Hidden(const ASetting, AFileName, AAnchor: string): Boolean;
  end;

implementation

uses
  System.JSON,
  dpcc.Text.Lines,
  dpcc.Core.Settings.JsonText;

function IsSeparator(ACh: Char): Boolean;
begin
  Result := (ACh = '\') or (ACh = '/');
end;

{ TDpccHiddenPlace }

class function TDpccHiddenPlace.Create(const ASetting, AFileName, AAnchor: string): TDpccHiddenPlace;
begin
  Result.Setting := ASetting;
  Result.FileName := TDpccHiddenPlaces.NormalizePath(AFileName);
  Result.Anchor := AAnchor;
end;

function TDpccHiddenPlace.SameAs(const AOther: TDpccHiddenPlace): Boolean;
begin
  Result := SameText(Setting, AOther.Setting) and
    SameText(TDpccHiddenPlaces.NormalizePath(FileName), TDpccHiddenPlaces.NormalizePath(AOther.FileName)) and
    (Anchor = AOther.Anchor);
end;

function TDpccHiddenPlace.WholeFile: Boolean;
begin
  Result := Anchor = '';
end;

{ TDpccHiddenPlaces }

class function TDpccHiddenPlaces.NormalizePath(const APath: string): string;
var
  mIndex: Integer;
begin
  Result := Trim(APath);
  for mIndex := 1 to Length(Result) do
  begin
    if Result[mIndex] = '\' then
    begin
      Result[mIndex] := '/';
    end;
  end;
  while Result.StartsWith('./') do
  begin
    Result := Copy(Result, 3, MaxInt);
  end;
end;

class function TDpccHiddenPlaces.Relative(const AFolder, AFileName: string; out ARelative: string): Boolean;
var
  mFolder, mFileName: string;
begin
  ARelative := '';
  mFolder := NormalizePath(AFolder);
  while (mFolder <> '') and IsSeparator(mFolder[Length(mFolder)]) do
  begin
    Delete(mFolder, Length(mFolder), 1);
  end;
  mFileName := NormalizePath(AFileName);
  Result := (mFolder <> '') and (Length(mFileName) > Length(mFolder) + 1) and
    SameText(Copy(mFileName, 1, Length(mFolder)), mFolder) and (mFileName[Length(mFolder) + 1] = '/');
  if Result then
  begin
    ARelative := Copy(mFileName, Length(mFolder) + 2, MaxInt);
  end;
  // Kein Ausbruch über "..": der Pfad bleibt unter dem Ordner.
  if Result and ((Pos('/../', '/' + ARelative + '/') > 0)) then
  begin
    ARelative := '';
    Result := False;
  end;
end;

class function TDpccHiddenPlaces.IndexOf(const APlaces: TArray<TDpccHiddenPlace>;
  const APlace: TDpccHiddenPlace): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(APlaces) do
  begin
    if APlaces[mIndex].SameAs(APlace) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TDpccHiddenPlaces.ToJson(const APlaces: TArray<TDpccHiddenPlace>;
  const AIndent, ALineBreak: string): string;
var
  mIndex: Integer;
  mItem: string;
begin
  if Length(APlaces) = 0 then
  begin
    Exit('[]');
  end;
  Result := '[';
  for mIndex := 0 to High(APlaces) do
  begin
    mItem := '{"setting": ' + TDpccJsonText.Quote(APlaces[mIndex].Setting) + ', "file": ' +
      TDpccJsonText.Quote(NormalizePath(APlaces[mIndex].FileName));
    if APlaces[mIndex].Anchor <> '' then
    begin
      mItem := mItem + ', "anchor": ' + TDpccJsonText.Quote(APlaces[mIndex].Anchor);
    end;
    mItem := mItem + '}';
    if mIndex < High(APlaces) then
    begin
      mItem := mItem + ',';
    end;
    Result := Result + ALineBreak + AIndent + '  ' + mItem;
  end;
  Result := Result + ALineBreak + AIndent + ']';
end;

class function TDpccHiddenPlaces.FromText(const AText: string): TArray<TDpccHiddenPlace>;
var
  mRoot: TJSONObject;
  mValue, mItem: TJSONValue;
  mPlace: TDpccHiddenPlace;
begin
  Result := nil;
  mRoot := TDpccJsonText.Parse(AText);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    mValue := mRoot.GetValue(cKey);
    if not (mValue is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mValue) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mPlace := TDpccHiddenPlace.Create(TJSONObject(mItem).GetValue<string>('setting', ''),
        TJSONObject(mItem).GetValue<string>('file', ''), TJSONObject(mItem).GetValue<string>('anchor', ''));
      if (mPlace.Setting <> '') and (mPlace.FileName <> '') then
      begin
        Result := Result + [mPlace];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TDpccHiddenPlaces.AddTo(const AText, ASkeleton: string; const APlace: TDpccHiddenPlace): string;
var
  mPlaces: TArray<TDpccHiddenPlace>;
begin
  Result := AText;
  if Trim(Result) = '' then
  begin
    Result := ASkeleton;
  end;
  mPlaces := FromText(Result);
  if IndexOf(mPlaces, APlace) >= 0 then
  begin
    Exit;
  end;
  mPlaces := mPlaces + [APlace];
  Result := TDpccJsonText.SetValue(Result, cKey, ToJson(mPlaces, '  ', TTextLines.LineBreakOf(Result)));
end;

class function TDpccHiddenPlaces.RemoveFrom(const AText: string; const APlace: TDpccHiddenPlace): string;
var
  mPlaces: TArray<TDpccHiddenPlace>;
  mIndex: Integer;
begin
  Result := AText;
  mPlaces := FromText(Result);
  mIndex := IndexOf(mPlaces, APlace);
  if mIndex < 0 then
  begin
    Exit;
  end;
  Delete(mPlaces, mIndex, 1);
  Result := TDpccJsonText.SetValue(Result, cKey, ToJson(mPlaces, '  ', TTextLines.LineBreakOf(Result)));
end;

{ TDpccHiddenIndex }

constructor TDpccHiddenIndex.Create(const APlaces: TArray<TDpccHiddenPlace>; const AFolder: string);
var
  mPlace: TDpccHiddenPlace;
  mName: string;
  mList: TList<string>;
begin
  inherited Create;
  FFolder := AFolder;
  FAnchors := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  if AFolder = '' then
  begin
    Exit;
  end;
  for mPlace in APlaces do
  begin
    mName := LowerCase(mPlace.Setting + '|' + TDpccHiddenPlaces.NormalizePath(mPlace.FileName));
    if not FAnchors.TryGetValue(mName, mList) then
    begin
      mList := TList<string>.Create;
      FAnchors.Add(mName, mList);
    end;
    mList.Add(mPlace.Anchor);
  end;
end;

destructor TDpccHiddenIndex.Destroy;
begin
  FAnchors.Free;
  inherited Destroy;
end;

function TDpccHiddenIndex.IsEmpty: Boolean;
begin
  Result := FAnchors.Count = 0;
end;

function TDpccHiddenIndex.Lookup(const ASetting, AFileName: string; out AAnchors: TList<string>): Boolean;
begin
  AAnchors := nil;
  if FAnchors.Count = 0 then
  begin
    Exit(False);
  end;
  // Beim Zeichnen kommt dieselbe Datei Zeile für Zeile: Pfad nur einmal umrechnen.
  if not SameFileName(AFileName, FLastFile) then
  begin
    FLastFile := AFileName;
    FLastInside := TDpccHiddenPlaces.Relative(FFolder, AFileName, FLastRelative);
  end;
  Result := FLastInside and FAnchors.TryGetValue(LowerCase(ASetting + '|' + FLastRelative), AAnchors);
end;

function TDpccHiddenIndex.FileHidden(const ASetting, AFileName: string): Boolean;
var
  mAnchors: TList<string>;
begin
  Result := Lookup(ASetting, AFileName, mAnchors) and mAnchors.Contains('');
end;

function TDpccHiddenIndex.Hidden(const ASetting, AFileName, AAnchor: string): Boolean;
var
  mAnchors: TList<string>;
begin
  Result := Lookup(ASetting, AFileName, mAnchors) and (mAnchors.Contains('') or
    ((AAnchor <> '') and mAnchors.Contains(AAnchor)));
end;

end.
