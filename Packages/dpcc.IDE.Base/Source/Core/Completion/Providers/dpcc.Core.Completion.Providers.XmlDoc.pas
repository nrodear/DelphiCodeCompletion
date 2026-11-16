unit dpcc.Core.Completion.Providers.XmlDoc;

// XMLDoc-Tags in ///-Kommentaren (#435): Nach "/// <" schlägt dpcc die Tags
// vor, bei <param> je Parameter der folgenden Deklaration einen Eintrag,
// <returns> nur bei Funktionen. Lokal, ohne Server. Der Einfügetext markiert
// mit "$0", wo der Cursor danach steht (zwischen den Tags).

interface

uses
  System.SysUtils,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Internals.Async;

type
  TDpccXmlDoc = class
  public
    /// <summary>Steht der Cursor nach "/// &lt;" (ggf. mit angefangenem Tag)? ALineBefore: Zeile bis zum
    /// Cursor.</summary>
    class function IsTagContext(const ALineBefore: string): Boolean; static;
    /// <summary>Deklaration nach der Zeile ALine (0-basiert): die nächsten Zeilen ohne ///, bis ";"
    /// außerhalb von Klammern; '' ohne.</summary>
    class function FollowingDeclaration(const AText: string; ALine: Integer): string; static;
    /// <summary>Parameternamen einer Deklaration in Reihenfolge.</summary>
    class function ParamNames(const ADeclaration: string): TArray<string>; static;
    /// <summary>Vorschläge für ADeclaration.</summary>
    class function TagItems(const ADeclaration: string): TDpccCompletionItems; static;
  end;

  TDpccXmlDocCompletionProvider = class(TDpccAsyncCompletionProvider)
  public
    /// <summary>Name der Quelle für die Sicherung (#493) und ihre Meldungen, in der Sprache der Oberfläche.
    /// </summary>
    class function ProviderTitle: string; static;
    constructor Create;
  protected
    function Fetch(const AContext: TDpccContext; AData: TObject; const ACancelled: TDpccCancelledFunc;
      const AEmit: TDpccEmitProc; out AState: TDpccFetchState): TDpccCompletionItems; override;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Classes,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TXmlDocText = (CompletionXMLDoc);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TXmlDocText] of string = (
    ('Vervollständigung (XMLDoc)'),
    ('Completion (XMLDoc)'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TXmlDocText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
end;

function Tag(const AName, AInsert: string; ARank: Integer): TDpccCompletionItem;
begin
  Result := Default(TDpccCompletionItem);
  Result.Name := AName;
  Result.InsertText := AInsert;
  Result.Kind := TDpccItemKind.XmlDocTag;
  Result.Rank := ARank;
  Result.UnitUsed := True;
end;

{ TDpccXmlDoc }

class function TDpccXmlDoc.IsTagContext(const ALineBefore: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if not TrimLeft(ALineBefore).StartsWith('///') then
  begin
    Exit;
  end;
  // Angefangenen Tagnamen überspringen, dann muss "<" stehen.
  mIndex := Length(ALineBefore);
  while (mIndex > 0) and CharInSet(ALineBefore[mIndex], ['A'..'Z', 'a'..'z']) do
  begin
    Dec(mIndex);
  end;
  Result := (mIndex > 0) and (ALineBefore[mIndex] = '<');
end;

class function TDpccXmlDoc.FollowingDeclaration(const AText: string; ALine: Integer): string;
var
  mAll: TArray<string>;
  mIndex, mDepth, mPosition: Integer;
  mLine: string;
begin
  Result := '';
  mAll := Lines(AText);
  mDepth := 0;
  for mIndex := ALine + 1 to Min(High(mAll), ALine + 12) do
  begin
    mLine := Trim(mAll[mIndex]);
    if mLine.StartsWith('///') or ((Result = '') and ((mLine = '') or mLine.StartsWith('['))) then
    begin
      Continue;
    end;
    Result := Result + ' ' + mLine;
    for mPosition := 1 to Length(mLine) do
      case mLine[mPosition] of
        '(': Inc(mDepth);
        ')': Dec(mDepth);
        ';':
          if mDepth <= 0 then
          begin
            Exit(Trim(Result));
          end;
      end;
  end;
  Result := Trim(Result);
end;

/// <summary>Text zwischen der ersten "(" in ADeclaration und der passenden ")"; '' ohne Klammer.</summary>
function ParameterList(const ADeclaration: string): string;
var
  mOpen, mClose, mDepth: Integer;
begin
  Result := '';
  mOpen := Pos('(', ADeclaration);
  if mOpen = 0 then
  begin
    Exit;
  end;
  mClose := mOpen;
  mDepth := 0;
  repeat
    case ADeclaration[mClose] of
      '(': Inc(mDepth);
      ')': Dec(mDepth);
    end;
    Inc(mClose);
  until (mDepth = 0) or (mClose > Length(ADeclaration));
  Result := Copy(ADeclaration, mOpen + 1, mClose - mOpen - 2);
end;

/// <summary>Namen einer Parametergruppe: "const A, B: string = ''" → A, B.</summary>
function GroupNames(const AGroup: string): TArray<string>;
var
  mNames, mName: string;
begin
  Result := nil;
  mNames := AGroup;
  if Pos(':', mNames) > 0 then
  begin
    mNames := Copy(mNames, 1, Pos(':', mNames) - 1);
  end;
  mNames := Trim(mNames);
  for mName in ['const ', 'var ', 'out ', 'constref '] do
  begin
    if StartsText(mName, mNames) then
    begin
      mNames := Trim(Copy(mNames, Length(mName) + 1, MaxInt));
    end;
  end;
  for mName in mNames.Split([',']) do
  begin
    if Trim(mName) <> '' then
    begin
      Result := Result + [Trim(mName)];
    end;
  end;
end;

class function TDpccXmlDoc.ParamNames(const ADeclaration: string): TArray<string>;
var
  mGroup: string;
begin
  Result := nil;
  for mGroup in ParameterList(ADeclaration).Split([';']) do
  begin
    Result := Result + GroupNames(mGroup);
  end;
end;

class function TDpccXmlDoc.TagItems(const ADeclaration: string): TDpccCompletionItems;
var
  mName: string;
  mRank: Integer;
  mIsFunction: Boolean;
begin
  mRank := 0;
  Result := [Tag('summary', 'summary>$0</summary>', mRank)];
  for mName in ParamNames(ADeclaration) do
  begin
    Inc(mRank);
    Result := Result + [Tag(Format('param name="%s"', [mName]), Format('param name="%s">$0</param>', [mName]), mRank)];
  end;
  mIsFunction := StartsText('function ', TrimLeft(ADeclaration)) or StartsText('class function ', TrimLeft(ADeclaration));
  if mIsFunction then
  begin
    Result := Result + [Tag('returns', 'returns>$0</returns>', mRank + 1)];
  end;
  Result := Result + [Tag('remarks', 'remarks>$0</remarks>', mRank + 2),
    Tag('exception cref=""', 'exception cref="$0"></exception>', mRank + 3),
    Tag('see cref=""', 'see cref="$0"/>', mRank + 4), Tag('value', 'value>$0</value>', mRank + 5),
    Tag('para', 'para>$0</para>', mRank + 6), Tag('c', 'c>$0</c>', mRank + 7),
    Tag('code', 'code>$0</code>', mRank + 8)];
end;

{ TDpccXmlDocCompletionProvider }

class function TDpccXmlDocCompletionProvider.ProviderTitle: string;
begin
  Result := UiText(TXmlDocText.CompletionXMLDoc);
end;

constructor TDpccXmlDocCompletionProvider.Create;
begin
  inherited Create;
  Name := ProviderTitle;
end;

function TDpccXmlDocCompletionProvider.Fetch(const AContext: TDpccContext; AData: TObject;
  const ACancelled: TDpccCancelledFunc; const AEmit: TDpccEmitProc;
    out AState: TDpccFetchState): TDpccCompletionItems;
var
  mAll: TArray<string>;
begin
  AState := Default(TDpccFetchState);
  Result := nil;
  mAll := Lines(AContext.Text);
  if (AContext.Line < 0) or (AContext.Line > High(mAll)) then
  begin
    Exit;
  end;
  if not TDpccXmlDoc.IsTagContext(Copy(mAll[AContext.Line], 1, AContext.Character)) then
  begin
    Exit;
  end;
  Result := TDpccXmlDoc.TagItems(TDpccXmlDoc.FollowingDeclaration(AContext.Text, AContext.Line));
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Completion.Providers.XmlDoc', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
