unit dpcc.Core.Settings.Search;

// Suche über die Einstellungen (#1884, zuerst #1903 für die Übersicht „dpcc“), ohne VCL und ohne Open Tools API.
// Grundlage ist der Plugin-Katalog; gesucht wird in
// - der Beschriftung in beiden Sprachen (x-caption, x-captionEn), unabhängig von der Sprache der IDE, dazu in
//   der Beschriftung des Elements auf der Optionsseite, wenn der Aufrufer sie kennt (ALabel),
// - dem Schlüssel (x-key, z. B. editor.minimap) und seinen Gliedern,
// - den Synonymen (x-keywords, z. B. „Tooltip“ an editor.hoverTooltip); die eines Hauptschalters gelten
//   abgeschwächt auch für seine Unteroptionen, Tastenkürzel (x-format shortcut) finden „Shortcut“ und „Taste“,
// - der Beschreibung und der Beschriftung von Bereich und Unterpunkt (schwach).
// Jedes Wort der Eingabe muss treffen; die Punkte addieren sich. Rangfolge wie in der Vervollständigung (#229):
// genau, Anfang, Wortanfang, Teilstring, dann Tippfehler (Editierabstand aus dpcc.Text wie #485: ab 4 Zeichen,
// bis 5 Zeichen einer, sonst zwei).
// Bei Gleichstand gilt die Reihenfolge des Katalogs. Einstellungen nicht installierter Module (AInstalled)
// fehlen; Zustände (x-state) ebenso, und alles, was der Completion-Schnitt nicht mehr anzeigt
// (dpcc.Core.Settings.CompletionView). Shown (Haken) schränkt weiter ein, etwa auf das, was die Seite zeigt.
// Annotate ergänzt den Zustand je Treffer nach den aktuellen Werten: geändert, gesperrt mit Grund, Modul aus.
// StateText fasst ihn mit der Quelle (.dpcc, dpcc.json) für die Trefferliste zusammen.

interface

uses
  System.SysUtils,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.Catalog,
  dpcc.Core.Settings.Groups;

type
  /// <summary>Treffer der Suche: Einstellung mit Beschriftung, Ort und Zustand.</summary>
  TDpccSettingHit = record
    /// <summary>Registry-Name (TDpccPluginSettings.Load/Save).</summary>
    Name: string;
    /// <summary>x-key, z. B. editor.minimap.</summary>
    Key: string;
    /// <summary>Beschriftung in der Sprache der Suche; ohne x-caption der erste Satz der Beschreibung, sonst der
    /// Schlüssel.</summary>
    Caption: string;
    /// <summary>Modulschalter (x-module) des Knotens; '' = Base.</summary>
    Module: string;
    AreaCaption: string;
    /// <summary>Unterpunkt im Baum (x-node); '' = Hauptknoten des Bereichs.</summary>
    NodeCaption: string;
    Score: Integer;
    Experimental: Boolean;
    /// <summary>Boolescher Schnellschalter (#604): in der Palette direkt umschaltbar.</summary>
    QuickToggle: Boolean;
    /// <summary>Pfad in der Projektdatei .dpcc bzw. dpcc.json, der den Wert im Projekt festlegen kann; '' ohne.
    /// </summary>
    TeamPath: string;
    ProjectPath: string;
    /// <summary>Nach Annotate: vom Standard abweichend.</summary>
    Modified: Boolean;
    /// <summary>Nach Annotate: Grund der Sperre; lrNone ohne.</summary>
    LockReason: TDpccLockReason;
    /// <summary>Nach Annotate: Beschriftung des sperrenden Hauptschalters.</summary>
    LockMaster: string;
    /// <summary>Nach Annotate: Der Modulschalter des Moduls ist aus.</summary>
    ModuleOff: Boolean;
    /// <summary>Bereich › Unterpunkt.</summary>
    function Path: string;
  end;

  /// <summary>Ist das Modul mit dem Modulschalter ASwitch installiert? ('' = Base, immer.)</summary>
  TDpccModuleInstalled = reference to function(const ASwitch: string): Boolean;
  /// <summary>Beschriftung des Elements der Einstellung AName auf der Optionsseite; '' ohne.</summary>
  TDpccSettingLabel = reference to function(const AName: string): string;

  /// <summary>Ist die Einstellung AName für diese Suche erreichbar?</summary>
  TDpccSettingShown = reference to function(const AName: string): Boolean;

  /// <summary>Was der Aufrufer zur Suche beisteuert; alles darf nil sein.</summary>
  TDpccSettingsSearchHooks = record
    /// <summary>nil = alle Module.</summary>
    Installed: TDpccModuleInstalled;
    /// <summary>nil = nur Katalogtexte.</summary>
    LabelOf: TDpccSettingLabel;
    /// <summary>nil = alles, was der Completion-Schnitt zeigt.</summary>
    Shown: TDpccSettingShown;
    class function Create(const AInstalled: TDpccModuleInstalled;
      const ALabelOf: TDpccSettingLabel): TDpccSettingsSearchHooks; overload; static;
    class function Create(const AInstalled: TDpccModuleInstalled; const ALabelOf: TDpccSettingLabel;
      const AShown: TDpccSettingShown): TDpccSettingsSearchHooks; overload; static;
  end;

  TDpccSettingsSearch = class
  public const
    cScoreExact = 1000;
    cScorePrefix = 800;
    cScoreWordStart = 700;
    cScoreKeyPart = 750;
    cScoreKeyPartPrefix = 650;
    cScoreSubstring = 500;
    cScoreKeySubstring = 450;
    cScoreKeyword = 700;
    cScoreKeywordPrefix = 550;
    cScoreInheritedKeyword = 350;
    cScoreInheritedPrefix = 250;
    cScoreDescription = 200;
    cScoreTypo = 150;
    /// <summary>Zwei vertauschte Nachbarbuchstaben (minimpa für minimap): näher als andere Tippfehler.</summary>
    cScoreSwap = 160;
    cScorePlace = 120;
  private
    class function TextScore(const AWord, AText: string): Integer; static;
    class function KeyScore(const AWord, AKey: string): Integer; static;
    class function KeywordScore(const AWord: string; const AKeywords: TArray<string>;
      AInherited: Boolean): Integer; static;
    class function TypoScore(const AWord: string; const ATexts: TArray<string>): Integer; static;
    class function WordScore(const AWord: string; const AEntry: TDpccCatalogEntry; const ALabel: string;
      const AInherited: TArray<string>; const APlace: string): Integer; static;
    class function InheritedKeywords(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups;
      const AName: string): TArray<string>; static;
    class function HitOf(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups;
      const AEntry: TDpccCatalogEntry; AEnglish: Boolean; const ALabel: string): TDpccSettingHit; static;
    class procedure SortHits(var AHits: TArray<TDpccSettingHit>); static;
  public
    /// <summary>Wörter der Eingabe in Kleinbuchstaben; Trennzeichen sind Leerzeichen.</summary>
    class function Words(const AText: string): TArray<string>; static;
    /// <summary>Punkte der Einstellung für AText (alle Wörter müssen treffen); 0 = kein Treffer.</summary>
    class function Score(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups; AIndex: Integer;
      const AText, ALabel: string): Integer; static;
    /// <summary>Plugin-Einstellungen (ohne Zustände) zu AText, beste zuerst, bei Gleichstand in
    /// Katalogreihenfolge; höchstens AMax. Leerer Text: keine Treffer. AHooks: installierte Module und
    /// Beschriftungen der Optionsseite.</summary>
    class function Find(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups; const AText: string;
      AEnglish: Boolean; AMax: Integer; const AHooks: TDpccSettingsSearchHooks): TArray<TDpccSettingHit>;
      overload; static;
    /// <summary>Wie oben, ohne Haken: alle Module, nur Katalogtexte.</summary>
    class function Find(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups; const AText: string;
      AEnglish: Boolean; AMax: Integer): TArray<TDpccSettingHit>; overload; static;
    /// <summary>Zustand der Treffer nach ASettings: geändert, gesperrt (Grund, Hauptschalter), Modul aus.</summary>
    class procedure Annotate(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups;
      const ASettings: TDpccPluginSettings; var AHits: TArray<TDpccSettingHit>; AEnglish: Boolean); static;
    /// <summary>Zustand als kurzer Text in der Sprache der Oberfläche, z. B. „● geändert · experimentell“;
    /// '' ohne Besonderheit.</summary>
    class function StateText(const AHit: TDpccSettingHit): string; static;
    /// <summary>Beschriftung von AEntry in der gewünschten Sprache mit Rückfall auf die andere, die
    /// Beschreibung (erster Satz) und den Schlüssel.</summary>
    class function CaptionOf(const AEntry: TDpccCatalogEntry; AEnglish: Boolean): string; static;
  end;

implementation

uses
  System.StrUtils,
  dpcc.Text.Fuzzy,
  dpcc.Core.Settings.History,
  dpcc.Core.Settings.NodeScope,
  dpcc.Core.Settings.Transfer,
  dpcc.Core.Settings.Experimental,
  dpcc.Core.Settings.ModuleSwitches,
  dpcc.Core.Settings.CompletionView,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TSearchText = (Modified, Experimental, LockedBy, LockedExperimental, ModuleOff, Team, Project, Separator);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TSearchText] of string = (
    ('● geändert', 'experimentell', 'gesperrt: %s ist aus', 'gesperrt: experimentelle Funktionen aus',
      'Modul aus', 'auch im Projekt (.dpcc: %s)', 'auch im Projekt (dpcc.json: %s)', ' · '),
    ('● modified', 'experimental', 'locked: %s is off', 'locked: experimental features off',
      'module off', 'also in the project (.dpcc: %s)', 'also in the project (dpcc.json: %s)', ' · '));

  /// <summary>Synonyme jedes Tastenkürzels (x-format shortcut).</summary>
  cShortcutKeywords: array[0..4] of string = ('shortcut', 'hotkey', 'taste', 'tastenkürzel', 'key'); // german-ok Suchwort

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TSearchText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

/// <summary>Erster Satz von AText (bis „. “).</summary>
function FirstSentence(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := AText;
  mIndex := Pos('. ', Result);
  if mIndex > 0 then
  begin
    Result := Copy(Result, 1, mIndex - 1);
  end;
end;

/// <summary>Zerlegt AText an Leerzeichen, Punkt, Bindestrich, Schrägstrich und Klammern in Wörter.</summary>
function SplitWords(const AText: string): TArray<string>;
begin
  Result := LowerCase(AText).Split([' ', '.', '-', '/', '(', ')', ',', ':', '„', '“', '"'],
    TStringSplitOptions.ExcludeEmpty);
end;

{ TDpccSettingHit }

function TDpccSettingHit.Path: string;
begin
  Result := AreaCaption;
  if NodeCaption <> '' then
  begin
    Result := Result + ' › ' + NodeCaption;
  end;
end;

{ TDpccSettingsSearchHooks }

class function TDpccSettingsSearchHooks.Create(const AInstalled: TDpccModuleInstalled;
  const ALabelOf: TDpccSettingLabel): TDpccSettingsSearchHooks;
begin
  Result := Create(AInstalled, ALabelOf, nil);
end;

class function TDpccSettingsSearchHooks.Create(const AInstalled: TDpccModuleInstalled;
  const ALabelOf: TDpccSettingLabel; const AShown: TDpccSettingShown): TDpccSettingsSearchHooks;
begin
  Result.Installed := AInstalled;
  Result.LabelOf := ALabelOf;
  Result.Shown := AShown;
end;

{ TDpccSettingsSearch }

class function TDpccSettingsSearch.Words(const AText: string): TArray<string>;
begin
  Result := LowerCase(Trim(AText)).Split([' '], TStringSplitOptions.ExcludeEmpty);
end;

class function TDpccSettingsSearch.CaptionOf(const AEntry: TDpccCatalogEntry; AEnglish: Boolean): string;
begin
  if AEnglish then
  begin
    Result := AEntry.CaptionEn;
    if Result = '' then
    begin
      Result := AEntry.Caption;
    end;
  end
  else
  begin
    Result := AEntry.Caption;
    if Result = '' then
    begin
      Result := AEntry.CaptionEn;
    end;
  end;
  if Result = '' then
  begin
    Result := FirstSentence(AEntry.Description);
  end;
  if Result = '' then
  begin
    Result := AEntry.Key;
  end;
end;

class function TDpccSettingsSearch.TextScore(const AWord, AText: string): Integer;
var
  mText, mPart: string;
begin
  mText := LowerCase(AText);
  if (mText = '') or (Pos(AWord, mText) = 0) then
  begin
    Exit(0);
  end;
  if mText = AWord then
  begin
    Exit(cScoreExact);
  end;
  if StartsStr(AWord, mText) then
  begin
    Exit(cScorePrefix);
  end;
  for mPart in SplitWords(mText) do
  begin
    if StartsStr(AWord, mPart) then
    begin
      Exit(cScoreWordStart);
    end;
  end;
  Result := cScoreSubstring;
end;

class function TDpccSettingsSearch.KeyScore(const AWord, AKey: string): Integer;
var
  mKey, mPart: string;
begin
  mKey := LowerCase(AKey);
  if (mKey = '') or (Pos(AWord, mKey) = 0) then
  begin
    Exit(0);
  end;
  if mKey = AWord then
  begin
    Exit(cScoreExact);
  end;
  Result := cScoreKeySubstring;
  for mPart in mKey.Split(['.']) do
  begin
    if mPart = AWord then
    begin
      Exit(cScoreKeyPart);
    end;
    if StartsStr(AWord, mPart) then
    begin
      Result := cScoreKeyPartPrefix;
    end;
  end;
end;

class function TDpccSettingsSearch.KeywordScore(const AWord: string; const AKeywords: TArray<string>;
  AInherited: Boolean): Integer;
var
  mKeyword: string;
begin
  Result := 0;
  for mKeyword in AKeywords do
  begin
    if SameText(mKeyword, AWord) then
    begin
      if AInherited then
      begin
        Exit(cScoreInheritedKeyword);
      end;
      Exit(cScoreKeyword);
    end;
    if StartsText(AWord, mKeyword) then
    begin
      if AInherited then
      begin
        Result := cScoreInheritedPrefix;
      end
      else
      begin
        Result := cScoreKeywordPrefix;
      end;
    end;
  end;
end;

/// <summary>Unterscheiden sich AWord und APart (ohne Groß-/Kleinschreibung) nur durch zwei vertauschte
/// Nachbarbuchstaben?</summary>
function SwappedOnce(const AWord, APart: string): Boolean;
var
  mWord, mPart: string;
  mIndex: Integer;
begin
  Result := False;
  mWord := LowerCase(AWord);
  mPart := LowerCase(APart);
  if (Length(mWord) <> Length(mPart)) or (mWord = mPart) then
  begin
    Exit;
  end;
  for mIndex := 1 to Length(mWord) - 1 do
  begin
    if mWord[mIndex] <> mPart[mIndex] then
    begin
      Result := (mWord[mIndex] = mPart[mIndex + 1]) and (mWord[mIndex + 1] = mPart[mIndex]) and
        (Copy(mWord, mIndex + 2, MaxInt) = Copy(mPart, mIndex + 2, MaxInt));
      Exit;
    end;
  end;
end;

const
  /// <summary>Kürzere Wortteile vergleicht die Tippfehlersuche nicht.</summary>
  cMinTypoPartLength = 3;

/// <summary>Tippfehlerwertung für einen Wortteil: ganzes Wort oder sein gleich langer Anfang
/// („minimpa“ → „minimap“, „hovr“ → „hover…“); 0 ohne Treffer.</summary>
function PartTypoScore(const AWord, APart: string; ALimit: Integer): Integer;
var
  mHead: string;
begin
  Result := 0;
  if Length(APart) < cMinTypoPartLength then
  begin
    Exit;
  end;
  mHead := Copy(APart, 1, Length(AWord));
  if SwappedOnce(AWord, APart) or SwappedOnce(AWord, mHead) then
  begin
    Result := TDpccSettingsSearch.cScoreSwap;
  end
  else if (TTextFuzzy.EditDistance(AWord, APart, ALimit) <= ALimit) or
    (TTextFuzzy.EditDistance(AWord, mHead, ALimit) <= ALimit) then
  begin
    Result := TDpccSettingsSearch.cScoreTypo;
  end;
end;

class function TDpccSettingsSearch.TypoScore(const AWord: string; const ATexts: TArray<string>): Integer;
var
  mText, mPart: string;
  mLimit, mScore: Integer;
begin
  Result := 0;
  if Length(AWord) < 4 then
  begin
    Exit;
  end;
  mLimit := 2;
  if Length(AWord) <= 5 then
  begin
    mLimit := 1;
  end;
  for mText in ATexts do
  begin
    for mPart in SplitWords(mText) do
    begin
      mScore := PartTypoScore(AWord, mPart, mLimit);
      if mScore = cScoreSwap then
      begin
        Exit(cScoreSwap);
      end;
      if mScore > Result then
      begin
        Result := mScore;
      end;
    end;
  end;
end;

/// <summary>Größere der beiden Zahlen.</summary>
function Larger(ALeft, ARight: Integer): Integer;
begin
  Result := ALeft;
  if ARight > Result then
  begin
    Result := ARight;
  end;
end;

class function TDpccSettingsSearch.WordScore(const AWord: string; const AEntry: TDpccCatalogEntry;
  const ALabel: string; const AInherited: TArray<string>; const APlace: string): Integer;
var
  mTexts: TArray<string>;
begin
  Result := Larger(TextScore(AWord, AEntry.Caption), TextScore(AWord, AEntry.CaptionEn));
  Result := Larger(Result, TextScore(AWord, ALabel));
  Result := Larger(Result, KeyScore(AWord, AEntry.Key));
  Result := Larger(Result, KeywordScore(AWord, AEntry.Keywords, False));
  Result := Larger(Result, KeywordScore(AWord, AInherited, True));
  if Result > 0 then
  begin
    Exit;
  end;
  if Pos(AWord, LowerCase(AEntry.Description)) > 0 then
  begin
    Exit(cScoreDescription);
  end;
  mTexts := Copy(AEntry.Keywords);
  Insert([AEntry.Caption, AEntry.CaptionEn, ALabel, AEntry.Key], mTexts, 0);
  Result := TypoScore(AWord, mTexts);
  if (Result = 0) and (Pos(AWord, LowerCase(APlace)) > 0) then
  begin
    Result := cScorePlace;
  end;
end;

class function TDpccSettingsSearch.InheritedKeywords(ACatalog: TDpccSettingsCatalog;
  AGroups: TDpccSettingsGroups; const AName: string): TArray<string>;
var
  mName: string;
  mIndex: Integer;
begin
  Result := nil;
  for mName in AGroups.AncestorsOf(AName) do
  begin
    mIndex := ACatalog.IndexOfName(mName);
    if mIndex >= 0 then
    begin
      Result := Result + ACatalog[mIndex].Keywords;
    end;
  end;
  mIndex := ACatalog.IndexOfName(AName);
  if (mIndex >= 0) and (ACatalog[mIndex].Format = 'shortcut') then
  begin
    for mName in cShortcutKeywords do
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TDpccSettingsSearch.Score(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups;
  AIndex: Integer; const AText, ALabel: string): Integer;
var
  mEntry: TDpccCatalogEntry;
  mWord, mPlace: string;
  mInherited: TArray<string>;
  mPoints: Integer;
begin
  Result := 0;
  mEntry := ACatalog[AIndex];
  mInherited := InheritedKeywords(ACatalog, AGroups, mEntry.Name);
  mPlace := ACatalog.AreaCaption(mEntry.Area, False) + ' ' + ACatalog.AreaCaption(mEntry.Area, True) + ' ' +
    AGroups.NodeCaption(AGroups.NodeOf(mEntry.Name), False) + ' ' + mEntry.Page;
  for mWord in Words(AText) do
  begin
    mPoints := WordScore(mWord, mEntry, ALabel, mInherited, mPlace);
    if mPoints = 0 then
    begin
      Exit(0);
    end;
    Inc(Result, mPoints);
  end;
end;

class function TDpccSettingsSearch.HitOf(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups;
  const AEntry: TDpccCatalogEntry; AEnglish: Boolean; const ALabel: string): TDpccSettingHit;
var
  mNode: string;
begin
  Result := Default(TDpccSettingHit);
  Result.Name := AEntry.Name;
  Result.Key := AEntry.Key;
  Result.Caption := ALabel;
  if Result.Caption = '' then
  begin
    Result.Caption := CaptionOf(AEntry, AEnglish);
  end;
  Result.Module := TDpccSettingsNodeScope.ModuleOf(ACatalog, AGroups, AEntry.Name);
  Result.AreaCaption := ACatalog.AreaCaption(AEntry.Area, AEnglish);
  mNode := AGroups.NodeOf(AEntry.Name);
  if mNode <> '' then
  begin
    Result.NodeCaption := AGroups.NodeCaption(mNode, AEnglish);
  end;
  Result.Experimental := AGroups.IsExperimental(AEntry.Name);
  Result.QuickToggle := AEntry.QuickToggle and (AEntry.Kind = akBoolean);
  Result.TeamPath := AEntry.TeamPath;
  Result.ProjectPath := AEntry.ProjectPath;
end;

class procedure TDpccSettingsSearch.SortHits(var AHits: TArray<TDpccSettingHit>);
var
  mIndex, mPlace: Integer;
  mHit: TDpccSettingHit;
begin
  // Einfügen von hinten: stabil, bei gleicher Punktzahl bleibt die Katalogreihenfolge.
  for mIndex := 1 to High(AHits) do
  begin
    mHit := AHits[mIndex];
    mPlace := mIndex;
    while (mPlace > 0) and (AHits[mPlace - 1].Score < mHit.Score) do
    begin
      AHits[mPlace] := AHits[mPlace - 1];
      Dec(mPlace);
    end;
    AHits[mPlace] := mHit;
  end;
end;

class function TDpccSettingsSearch.Find(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups;
  const AText: string; AEnglish: Boolean; AMax: Integer): TArray<TDpccSettingHit>;
begin
  Result := Find(ACatalog, AGroups, AText, AEnglish, AMax, TDpccSettingsSearchHooks.Create(nil, nil));
end;

class function TDpccSettingsSearch.Find(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups;
  const AText: string; AEnglish: Boolean; AMax: Integer; const AHooks: TDpccSettingsSearchHooks):
  TArray<TDpccSettingHit>;
var
  mIndex, mScore: Integer;
  mEntry: TDpccCatalogEntry;
  mHit: TDpccSettingHit;
  mLabel: string;
begin
  Result := nil;
  if Length(Words(AText)) = 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to ACatalog.Count - 1 do
  begin
    mEntry := ACatalog[mIndex];
    if (mEntry.Source <> asPlugin) or mEntry.State or not TDpccCompletionView.ShowsSetting(mEntry) then
    begin
      Continue;
    end;
    if Assigned(AHooks.Shown) and not AHooks.Shown(mEntry.Name) then
    begin
      Continue;
    end;
    mLabel := '';
    if Assigned(AHooks.LabelOf) then
    begin
      mLabel := AHooks.LabelOf(mEntry.Name);
    end;
    mScore := Score(ACatalog, AGroups, mIndex, AText, mLabel);
    if mScore = 0 then
    begin
      Continue;
    end;
    mHit := HitOf(ACatalog, AGroups, mEntry, AEnglish, mLabel);
    if Assigned(AHooks.Installed) and (mHit.Module <> '') and not AHooks.Installed(mHit.Module) then
    begin
      Continue;
    end;
    mHit.Score := mScore;
    Result := Result + [mHit];
  end;
  SortHits(Result);
  if Length(Result) > AMax then
  begin
    SetLength(Result, Larger(AMax, 0));
  end;
end;

class procedure TDpccSettingsSearch.Annotate(ACatalog: TDpccSettingsCatalog; AGroups: TDpccSettingsGroups;
  const ASettings: TDpccPluginSettings; var AHits: TArray<TDpccSettingHit>; AEnglish: Boolean);
var
  mStore: IDpccMemorySettingsStore;
  mModified: TArray<string>;
  mSwitches: TArray<TDpccModuleSwitch>;
  mLock: TDpccSettingsLock;
  mIndex, mMaster: Integer;
  mExperimentalOn: Boolean;
begin
  mStore := TDpccMemorySettingsStore.FromSettings(ASettings);
  mModified := TDpccSettingsTransfer.ModifiedNames(ACatalog, ASettings);
  mSwitches := TDpccModuleSwitches.Read(ACatalog);
  mExperimentalOn := mStore.ReadInteger(TDpccExperimental.cMasterName, 0) <> 0;
  for mIndex := 0 to High(AHits) do
  begin
    AHits[mIndex].Modified := MatchText(AHits[mIndex].Name, mModified);
    AHits[mIndex].ModuleOff := (AHits[mIndex].Module <> '') and
      not TDpccModuleSwitches.IsOn(ASettings, mSwitches, AHits[mIndex].Module);
    mLock := AGroups.LockOf(AHits[mIndex].Name,
      function(const AName: string): Boolean
      begin
        Result := mStore.ReadInteger(AName, 1) <> 0;
      end, mExperimentalOn);
    AHits[mIndex].LockReason := mLock.Reason;
    AHits[mIndex].LockMaster := '';
    mMaster := ACatalog.IndexOfName(mLock.Master);
    if mLock.Locked and (mMaster >= 0) then
    begin
      AHits[mIndex].LockMaster := CaptionOf(ACatalog[mMaster], AEnglish);
    end;
  end;
end;

class function TDpccSettingsSearch.StateText(const AHit: TDpccSettingHit): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if AHit.Modified then
  begin
    mParts := mParts + [UiText(TSearchText.Modified)];
  end;
  if AHit.Experimental then
  begin
    mParts := mParts + [UiText(TSearchText.Experimental)];
  end;
  if AHit.ModuleOff then
  begin
    mParts := mParts + [UiText(TSearchText.ModuleOff)];
  end
  else if AHit.LockReason = lrExperimental then
  begin
    mParts := mParts + [UiText(TSearchText.LockedExperimental)];
  end
  else if AHit.LockReason = lrMasterOff then
  begin
    mParts := mParts + [Format(UiText(TSearchText.LockedBy), [AHit.LockMaster])];
  end;
  if AHit.TeamPath <> '' then
  begin
    mParts := mParts + [Format(UiText(TSearchText.Team), [AHit.TeamPath])];
  end
  else if AHit.ProjectPath <> '' then
  begin
    mParts := mParts + [Format(UiText(TSearchText.Project), [AHit.ProjectPath])];
  end;
  Result := string.Join(UiText(TSearchText.Separator), mParts);
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Settings.Search', cTexts[TDpccLanguage.German],
    cTexts[TDpccLanguage.English]);

end.
