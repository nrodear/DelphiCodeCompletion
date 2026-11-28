unit dpcc.Core.Editor.CodeInsightKeys;

// Orte der Code-Insight-Schalter der IDE in der Registry (#1246) und die
// Version aus dem Basisschlüssel. DelphiLSP liest seine Schalter unter
// Delphi 12 und 13 unter <Basis>\Code Insight\
// Borland.EditOptions.Borland.CodeInsight.LSP.Pascal. Gelesener Stand von
// Delphi 12 (BDS 23.0) auf dem Prüfrechner: unter Code Insight nur
// Borland.EditOptions.Borland.CodeInsight.LSP.Pascal, .HTML und .StyleSheet;
// Borland.EditOptions.Pascal (das Option Set aus GetOptionSetName des
// dpcc-Managers) nur mit den Werten, die dpcc selbst angelegt hatte. Die
// Annahme aus D12KEY, Delphi 12 lese es auch mit dpcc als Anbieter nicht, hat
// sich nicht bestätigt; seit HI1 setzt dpcc unter Delphi 12 wie unter 13 jeden
// vorhandenen der beiden Orte. Welche Orte dpcc in der Betriebsart dpcc
// setzt, bestimmt TDpccIdeCheck.DpccKeys (dpcc.Core.Settings.IdeCheck),
// nicht mehr die Version. Die frühere Annahme
// (bis D12-PREP), Delphi 12 lese die Schalter von DelphiLSP unter
// Borland.EditOptions.Pascal, traf nicht zu; VersionKey, Targets und Marker
// sind deshalb entfernt.
// Die Merker (was dpcc abgeschaltet hat) gelten je Version und Ort; vorher
// teilten sich Delphi 12 und 13 einen Merker, und die eine IDE drehte zurück,
// was die andere abgeschaltet hatte. Nur ab Delphi 13 gibt es noch Merker ohne
// Version und Ort (UsesLegacyMarker).

interface

type
  TDpccCodeInsightKeys = class
  public
    const
      /// <summary>Unter dem Basisschlüssel der IDE.</summary>
      cRoot = '\Code Insight';
      /// <summary>Option Set von DelphiLSP, unter Delphi 12 (BDS 23.0) und 13 (BDS 37.0) gleich.</summary>
      cProviderKey = 'Borland.EditOptions.Borland.CodeInsight.LSP.Pascal';
      /// <summary>Erste Hauptversion mit Merkern ohne Version und Ort (bis #1246, nur Delphi 13).</summary>
      cProviderVersion = 37;
      /// <summary>Registry-Profil ohne Schalter -r (Software\Embarcadero\BDS\&lt;Version&gt;).</summary>
      cDefaultProfile = 'BDS';
    /// <summary>Versionsteil des Basisschlüssels (…\BDS\23.0 → 23.0); '' ohne.</summary>
    class function VersionText(const ABaseKey: string): string; static;
    /// <summary>Hauptversion aus dem Basisschlüssel (…\BDS\23.0 → 23); 0 ohne.</summary>
    class function MajorVersion(const ABaseKey: string): Integer; static;
    /// <summary>Gilt der alte Merker ohne Version und Ort (bis #1246) für ASubKey? Nur für den Ort, an dem dpcc
    /// damals geschrieben hat, nur unter der Version, die ihn liest, und nur im Standardprofil.</summary>
    class function UsesLegacyMarker(const ABaseKey, ASubKey: string): Boolean; static;
    /// <summary>Registry-Profil des Basisschlüssels (…\Embarcadero\dpccSwitchTest\23.0 → dpccSwitchTest); '' ohne
    /// Version oder ohne Teil davor.</summary>
    class function ProfileText(const ABaseKey: string): string; static;
    /// <summary>Standardprofil (BDS) oder kein Profil erkennbar?</summary>
    class function IsDefaultProfile(const ABaseKey: string): Boolean; static;
    /// <summary>Geltungsbereich der Namen je Version unter HKCU\Software\dpcc\IdePlugin (Merker „IdeSet“,
    /// „OperatingMode“, „IdeAdopted &lt;Version&gt; …“): im Standardprofil nur die Version (…\BDS\23.0 → 23.0, wie
    /// bisher), mit eigenem Profil (bds -r) Profil und Version (…\dpccSwitchTest\23.0 → dpccSwitchTest 23.0), damit
    /// eine IDE mit eigenem Profil die Werte des Standardprofils weder liest noch ändert. '' ohne Version.</summary>
    class function ScopeText(const ABaseKey: string): string; static;
  end;

implementation

uses
  System.SysUtils;

class function TDpccCodeInsightKeys.VersionText(const ABaseKey: string): string;
var
  mKey: string;
  mSlash: Integer;
begin
  mKey := ABaseKey;
  while mKey.EndsWith('\') do
  begin
    mKey := mKey.Substring(0, mKey.Length - 1);
  end;
  mSlash := mKey.LastIndexOf('\');
  Result := mKey.Substring(mSlash + 1);
  if (Result = '') or not CharInSet(Result[1], ['0'..'9']) then
  begin
    Result := '';
  end;
end;

class function TDpccCodeInsightKeys.MajorVersion(const ABaseKey: string): Integer;
var
  mText: string;
  mDot: Integer;
begin
  mText := VersionText(ABaseKey);
  mDot := mText.IndexOf('.');
  if mDot >= 0 then
  begin
    mText := mText.Substring(0, mDot);
  end;
  Result := StrToIntDef(mText, 0);
end;

class function TDpccCodeInsightKeys.UsesLegacyMarker(const ABaseKey, ASubKey: string): Boolean;
begin
  Result := SameText(ASubKey, cProviderKey) and (MajorVersion(ABaseKey) >= cProviderVersion) and
    IsDefaultProfile(ABaseKey);
end;

class function TDpccCodeInsightKeys.ProfileText(const ABaseKey: string): string;
var
  mKey: string;
  mSlash: Integer;
begin
  Result := '';
  if VersionText(ABaseKey) = '' then
  begin
    Exit;
  end;
  mKey := ABaseKey;
  while mKey.EndsWith('\') do
  begin
    mKey := mKey.Substring(0, mKey.Length - 1);
  end;
  // Ohne die Version: der letzte Teil davor ist das Profil (Software\Embarcadero\<Profil>\<Version>).
  mKey := mKey.Substring(0, mKey.LastIndexOf('\') + 1);
  while mKey.EndsWith('\') do
  begin
    mKey := mKey.Substring(0, mKey.Length - 1);
  end;
  mSlash := mKey.LastIndexOf('\');
  Result := Trim(mKey.Substring(mSlash + 1));
end;

class function TDpccCodeInsightKeys.IsDefaultProfile(const ABaseKey: string): Boolean;
var
  mProfile: string;
begin
  mProfile := ProfileText(ABaseKey);
  Result := (mProfile = '') or SameText(mProfile, cDefaultProfile);
end;

class function TDpccCodeInsightKeys.ScopeText(const ABaseKey: string): string;
begin
  Result := VersionText(ABaseKey);
  if (Result <> '') and not IsDefaultProfile(ABaseKey) then
  begin
    Result := ProfileText(ABaseKey) + ' ' + Result;
  end;
end;

end.
