unit dpcc.Core.Editor.HelpInsightRule;

// Fenster von Help Insight der IDE verbergen (Auftrag HI1), ohne IDE, ohne VCL und ohne Windows:
// Die IDE zeigt beim Verweilen der Maus über einem Bezeichner ihr eigenes Help-Insight-Fenster (Klasse
// THelpInsightWindow aus coreide, Inhalt von DelphiLSP), unter Delphi 12 auch dann, wenn dpcc den Registry-Wert
// "Help Insight" auf False gesetzt hat, und sogar über dem offenen Popup der Vervollständigung von dpcc. Die
// IDE-Schicht (dpcc.IDE.Hover.HelpInsightHide) verbirgt ein solches Fenster deshalb zur Laufzeit, sobald es sichtbar
// wird, und fragt hier, ob:
//   - dpcc aus oder abgemeldet: nie (dann gehört Help Insight der IDE);
//   - dpcc an und eigener Tooltip an (HoverTooltip): immer, Grund OwnTooltip (sonst wären es zwei Tooltips);
//   - dpcc an, eigener Tooltip aus, Popup der Vervollständigung offen: Grund PopupOpen (das Fenster verdeckte sonst
//     die Liste);
//   - sonst nicht.
// Nur Fenster der Klasse cWindowClass (ohne Groß-/Kleinschreibung); jedes andere Fenster bleibt, wie es ist.
// Dazu die Diagnosezeile fürs Protokoll (dpcc.log, nie übersetzt): welcher Wert "Help Insight" an den Orten
// DiagnosisKeys steht, ein fehlender Schlüssel oder Wert als solcher benannt.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Warum dpcc ein Fenster von Help Insight verbirgt; None = nicht verbergen.</summary>
  TDpccHelpInsightHideReason = (None, OwnTooltip, PopupOpen);

  /// <summary>Gelesener Stand von "Help Insight" an einem Ort (für die Diagnosezeile).</summary>
  TDpccHelpInsightRegEntry = record
    /// <summary>Schlüssel relativ zum Basisschlüssel der IDE, z. B. "Code Insight\Borland.EditOptions.Pascal".
    /// </summary>
    Key: string;
    KeyExists: Boolean;
    ValueExists: Boolean;
    /// <summary>Text des Werts; bei REG_DWORD die Zahl dezimal.</summary>
    Value: string;
    class function Create(const AKey: string; AKeyExists, AValueExists: Boolean;
      const AValue: string): TDpccHelpInsightRegEntry; static;
  end;

  TDpccHelpInsightRule = record
  public const
    /// <summary>Fensterklasse von Help Insight der IDE (coreide), an genau dieser Stelle.</summary>
    cWindowClass = 'THelpInsightWindow';
    /// <summary>Ort der Code-Insight-Schalter für HTML (nur für die Diagnose gelesen).</summary>
    cHtmlKey = 'Code Insight\Borland.EditOptions.HTML';
    /// <summary>Name des Registry-Werts.</summary>
    cValueName = 'Help Insight';
  public
    /// <summary>Ist AClassName die Klasse des Help-Insight-Fensters (ohne Groß-/Kleinschreibung)?</summary>
    class function IsHelpInsightWindow(const AClassName: string): Boolean; static;
    /// <summary>Grund zum Verbergen eines sichtbar werdenden Fensters der Klasse AClassName: AActive = dpcc an und
    /// angemeldet, AOwnTooltip = eigener Tooltip an (HoverTooltip), APopupOpen = Popup der Vervollständigung von
    /// dpcc offen. Ist der eigene Tooltip an, heißt der Grund OwnTooltip, auch wenn das Popup offen ist.</summary>
    class function Decide(const AClassName: string; AActive, AOwnTooltip, APopupOpen: Boolean)
      : TDpccHelpInsightHideReason; static;
    /// <summary>Decide &lt;&gt; None.</summary>
    class function ShouldHide(const AClassName: string; AActive, AOwnTooltip, APopupOpen: Boolean): Boolean;
      static;
    /// <summary>Grund fürs Protokoll (nie übersetzt): „eigener Tooltip an“, „Popup offen“ bzw. „keiner“.</summary>
    class function ReasonText(AReason: TDpccHelpInsightHideReason): string; static;
    /// <summary>Orte, deren Wert "Help Insight" die Diagnose beim Start liest: der Ort von DelphiLSP,
    /// Borland.EditOptions.Pascal und Borland.EditOptions.HTML.</summary>
    class function DiagnosisKeys: TArray<string>; static;
    /// <summary>Text eines Eintrags: der Wert, „Wert fehlt“ bzw. „Schlüssel fehlt“.</summary>
    class function EntryText(const AEntry: TDpccHelpInsightRegEntry): string; static;
    /// <summary>Zeile fürs Protokoll, z. B. „Help Insight in der Registry (23.0): Borland.EditOptions.Pascal =
    /// (Schlüssel fehlt); …“. Orte ohne den Teil "Code Insight\".</summary>
    class function RegistryLine(const ABaseKey: string; const AEntries: TArray<TDpccHelpInsightRegEntry>): string;
      static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Editor.CodeInsightKeys,
  dpcc.Core.Settings.IdeCheck;

{ TDpccHelpInsightRegEntry }

class function TDpccHelpInsightRegEntry.Create(const AKey: string; AKeyExists, AValueExists: Boolean;
  const AValue: string): TDpccHelpInsightRegEntry;
begin
  Result.Key := AKey;
  Result.KeyExists := AKeyExists;
  // Ohne Schlüssel gibt es auch keinen Wert.
  Result.ValueExists := AKeyExists and AValueExists;
  Result.Value := '';
  if Result.ValueExists then
  begin
    Result.Value := AValue;
  end;
end;

{ TDpccHelpInsightRule }

class function TDpccHelpInsightRule.IsHelpInsightWindow(const AClassName: string): Boolean;
begin
  Result := SameText(AClassName, cWindowClass);
end;

class function TDpccHelpInsightRule.Decide(const AClassName: string; AActive, AOwnTooltip,
  APopupOpen: Boolean): TDpccHelpInsightHideReason;
begin
  Result := TDpccHelpInsightHideReason.None;
  // dpcc aus bzw. abgemeldet oder ein anderes Fenster: nichts verbergen.
  if not AActive or not IsHelpInsightWindow(AClassName) then
  begin
    Exit;
  end;
  if AOwnTooltip then
  begin
    Result := TDpccHelpInsightHideReason.OwnTooltip;
  end
  else if APopupOpen then
  begin
    Result := TDpccHelpInsightHideReason.PopupOpen;
  end;
end;

class function TDpccHelpInsightRule.ShouldHide(const AClassName: string; AActive, AOwnTooltip,
  APopupOpen: Boolean): Boolean;
begin
  Result := Decide(AClassName, AActive, AOwnTooltip, APopupOpen) <> TDpccHelpInsightHideReason.None;
end;

class function TDpccHelpInsightRule.ReasonText(AReason: TDpccHelpInsightHideReason): string;
const
  cTexts: array[TDpccHelpInsightHideReason] of string = ('keiner', 'eigener Tooltip an', 'Popup offen');
begin
  Result := cTexts[AReason];
end;

class function TDpccHelpInsightRule.DiagnosisKeys: TArray<string>;
begin
  Result := [TDpccIdeCheck.cLspKey, TDpccIdeCheck.cPascalKey, cHtmlKey];
end;

class function TDpccHelpInsightRule.EntryText(const AEntry: TDpccHelpInsightRegEntry): string;
begin
  if not AEntry.KeyExists then
  begin
    Result := '(Schlüssel fehlt)';
  end
  else if not AEntry.ValueExists then
  begin
    Result := '(Wert fehlt)';
  end
  else
  begin
    Result := AEntry.Value;
  end;
end;

/// <summary>AKey ohne führendes "Code Insight\".</summary>
function ShortKey(const AKey: string): string;
const
  cPrefix = TDpccIdeCheck.cCodeInsightRoot + '\';
begin
  Result := AKey;
  if Result.StartsWith(cPrefix, True) then
  begin
    Result := Result.Substring(Length(cPrefix));
  end;
end;

class function TDpccHelpInsightRule.RegistryLine(const ABaseKey: string;
  const AEntries: TArray<TDpccHelpInsightRegEntry>): string;
var
  mVersion, mParts: string;
  mEntry: TDpccHelpInsightRegEntry;
begin
  mVersion := TDpccCodeInsightKeys.VersionText(ABaseKey);
  if mVersion = '' then
  begin
    mVersion := '?';
  end;
  mParts := '';
  for mEntry in AEntries do
  begin
    if mParts <> '' then
    begin
      mParts := mParts + '; ';
    end;
    mParts := mParts + ShortKey(mEntry.Key) + ' = ' + EntryText(mEntry);
  end;
  if mParts = '' then
  begin
    mParts := '(nichts gelesen)';
  end;
  Result := Format('Help Insight in der Registry (%s): %s', [mVersion, mParts]);
end;

end.
