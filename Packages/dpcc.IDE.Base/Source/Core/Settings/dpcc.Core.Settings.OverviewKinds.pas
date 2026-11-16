unit dpcc.Core.Settings.OverviewKinds;

// Arten der Übersichtsleiste (#519) für editor.overviewRulerKinds:
// kommagetrennte Namen ("diagnostics,search,changes,breakpoints,bookmarks,
// cursor"); unbekannte fallen weg, die Reihenfolge ist fest. Liegt bei den
// Einstellungen, damit der Parser ohne den Editor-Kern auskommt; die Marken
// selbst rechnet dpcc.Core.Editor.Overview.

interface

type
{$SCOPEDENUMS ON}
  TDpccOverviewKind = (Diagnostics, Search, Changes, Breakpoints, Bookmarks, Cursor);
{$SCOPEDENUMS OFF}
  TDpccOverviewKinds = set of TDpccOverviewKind;

  TDpccOverviewKindNames = class
  public const
    cAll = [TDpccOverviewKind.Diagnostics, TDpccOverviewKind.Search, TDpccOverviewKind.Changes,
      TDpccOverviewKind.Breakpoints, TDpccOverviewKind.Bookmarks, TDpccOverviewKind.Cursor];
  public
    class function Name(AKind: TDpccOverviewKind): string; static;
    class function Parse(const AText: string): TDpccOverviewKinds; static;
    class function Text(AKinds: TDpccOverviewKinds): string; static;
    /// <summary>Bekannte Namen in fester Reihenfolge, ohne Doppelte.</summary>
    class function Normalize(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  cNames: array[TDpccOverviewKind] of string = ('diagnostics', 'search', 'changes', 'breakpoints', 'bookmarks',
    'cursor');

class function TDpccOverviewKindNames.Name(AKind: TDpccOverviewKind): string;
begin
  Result := cNames[AKind];
end;

class function TDpccOverviewKindNames.Parse(const AText: string): TDpccOverviewKinds;
var
  mPart: string;
  mKind: TDpccOverviewKind;
begin
  Result := [];
  for mPart in AText.Split([',', ';', ' ']) do
  begin
    for mKind := Low(TDpccOverviewKind) to High(TDpccOverviewKind) do
    begin
      if SameText(Trim(mPart), cNames[mKind]) then
      begin
        Include(Result, mKind);
      end;
    end;
  end;
end;

class function TDpccOverviewKindNames.Text(AKinds: TDpccOverviewKinds): string;
var
  mKind: TDpccOverviewKind;
begin
  Result := '';
  for mKind := Low(TDpccOverviewKind) to High(TDpccOverviewKind) do
  begin
    if mKind in AKinds then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cNames[mKind];
    end;
  end;
end;

class function TDpccOverviewKindNames.Normalize(const AText: string): string;
begin
  Result := Text(Parse(AText));
end;

end.
