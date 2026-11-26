unit dpcc.Core.Completion.Providers.Fixed;

// Datenquelle mit festen Einträgen (#408): für Tests der Oberfläche ohne
// Server (#415) und für den Fall eines langsamen Providers (#409, #431). Mit
// ADelayMs > 0 liefert sie erst nach dieser Zeit und lässt sich solange abbrechen.
// Seit S7a reine Testhilfe unter Tests\Support (nicht mehr im Package dpcc.Plugin, das Plugin benutzt sie nicht).

interface

uses
  System.SysUtils,
  System.Classes,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Internals.Async;

type
  TDpccFixedCompletionProvider = class(TDpccAsyncCompletionProvider)
  private
    FItems: TDpccCompletionItems;
    FDelayMs: Cardinal;
    FIncomplete: Boolean;
  protected
    function Fetch(const AContext: TDpccContext; AData: TObject; const ACancelled: TDpccCancelledFunc;
      const AEmit: TDpccEmitProc; out AState: TDpccFetchState): TDpccCompletionItems; override;
  public
    /// <summary>AIncomplete: meldet die Liste als gekürzt (#431).</summary>
    constructor Create(const AItems: TDpccCompletionItems; ADelayMs: Cardinal; AIncomplete: Boolean); overload;
    /// <summary>Wie oben mit AIncomplete = False.</summary>
    constructor Create(const AItems: TDpccCompletionItems; ADelayMs: Cardinal); overload;
    /// <summary>Wie oben ohne Verzögerung (ADelayMs = 0, AIncomplete = False).</summary>
    constructor Create(const AItems: TDpccCompletionItems); overload;
  end;

implementation


uses
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TFixedText = (CompletionFixed);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TFixedText] of string = (
    ('Vervollständigung (fest)'),
    ('Completion (fixed)'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TFixedText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;
{ TDpccFixedCompletionProvider }

constructor TDpccFixedCompletionProvider.Create(const AItems: TDpccCompletionItems; ADelayMs: Cardinal);
begin
  Create(AItems, ADelayMs, False);
end;

constructor TDpccFixedCompletionProvider.Create(const AItems: TDpccCompletionItems);
begin
  Create(AItems, 0, False);
end;

constructor TDpccFixedCompletionProvider.Create(const AItems: TDpccCompletionItems; ADelayMs: Cardinal;
  AIncomplete: Boolean);
begin
  inherited Create;
  Name := UiText(TFixedText.CompletionFixed);
  FItems := AItems;
  FDelayMs := ADelayMs;
  FIncomplete := AIncomplete;
end;

function TDpccFixedCompletionProvider.Fetch(const AContext: TDpccContext; AData: TObject;
  const ACancelled: TDpccCancelledFunc; const AEmit: TDpccEmitProc;
    out AState: TDpccFetchState): TDpccCompletionItems;
var
  mStart: UInt64;
begin
  AState := Default(TDpccFetchState);
  AState.Incomplete := FIncomplete;
  mStart := TThread.GetTickCount64;
  while TThread.GetTickCount64 - mStart < FDelayMs do
  begin
    if ACancelled() then
    begin
      Exit(nil);
    end;
    TThread.Sleep(5);
  end;
  Result := FItems;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Completion.Providers.Fixed', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
