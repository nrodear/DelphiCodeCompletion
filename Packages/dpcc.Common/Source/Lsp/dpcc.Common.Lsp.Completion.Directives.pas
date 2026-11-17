unit dpcc.Common.Lsp.Completion.Directives;

// Vervollständigung in Compilerdirektiven (#102): Direktivennamen nach "{$", Warnungen nach "{$WARN " und bedingte
// Symbole nach {$IFDEF , {$IFNDEF , {$DEFINE , {$UNDEF und in Defined(. Aus dpcc.Common.Lsp.Completion.Slash
// herausgelöst (Rückbau R2), damit die Schnellbefehle nach "/" entfallen können.
//
// Dateinamen nach {$I und {$INCLUDE (L3): die *.inc aus dem Ordner der Datei (mit getipptem Unterordner aus diesem)
// und aus den Ordnern der Include-Dateien, die die Unit laut Index schon einbindet (Kopf ohne Nachladen; so kommen
// Include-Ordner der Suchpfade dazu). Kein Lauf über die Bibliothekspfade; höchstens cMaxIncludeFolders Ordner und
// cMaxIncludeFiles Dateien. Eingefügt wird über ein textEdit vom Anfang des Namens bis zum Cursor.

interface

{$SCOPEDENUMS ON}

uses
  dpcc.Common.Lsp.ConditionalSymbols,
  dpcc.Common.Lsp.CompletionRequest;

const
  /// <summary>Höchstzahl der Ordner bzw. Dateien für {$I (L3).</summary>
  cMaxIncludeFolders = 8;
  cMaxIncludeFiles = 200;

type
  TCompletionDirectives = class
  public
    /// <summary>Bedingte Symbole nach {$IFDEF , {$IFNDEF , {$DEFINE , {$UNDEF und in Defined( (#102): Herkunft als
    /// Detail, Symbole, die hier nicht gelten, abgeschwächt am Ende.</summary>
    class function SymbolItems(ARequest: TCompletionRequest; const AContext: TConditionalContext;
      out AItems: TCompletionItems): Boolean; static;
    /// <summary>Vorschläge in einer offenen Direktive (#102), nach {$I und {$INCLUDE die Dateinamen (IncludeItems);
    /// False außerhalb.</summary>
    class function DirectiveItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
    /// <summary>Dateinamen nach {$I bzw. {$INCLUDE (L3, siehe oben); False, wenn der Cursor nicht im Namen steht.
    /// </summary>
    class function IncludeItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
    /// <summary>Steht der Cursor am Ende von ALineBefore im Dateinamen einer offenen {$I- bzw. {$INCLUDE-Direktive?
    /// APartial: schon Getipptes ohne Anführungszeichen, AStart: Spalte (0-basiert) seines Anfangs. {$I+} und
    /// {$I-} (Ein-/Ausgabeprüfung) zählen nicht.</summary>
    class function IncludeNameAt(const ALineBefore: string; out APartial: string; out AStart: Integer): Boolean;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.Rules.Contract,
  dpcc.Common.Lsp.CompilerDirectives,
  dpcc.Common.Lsp.CompletionCollector,
  dpcc.Common.Localization.Texts;

type
  /// <summary>Texte der Direktiven-Vervollständigung in beiden Sprachen (#1458).</summary>
  TDirectivesText = (CompilerWarning);

const
  cTexts: array[TDirectivesText] of TDpccText = (
    (De: 'Compiler-Warnung'; En: 'Compiler warning'));

{ TCompletionDirectives }

class function TCompletionDirectives.SymbolItems(ARequest: TCompletionRequest; const AContext: TConditionalContext;
  out AItems: TCompletionItems): Boolean;
var
  mPrefix: string;
  mSymbol: TConditionalSymbol;
  mItem: TCompletionItem;
begin
  AItems := Default(TCompletionItems);
  Result := TConditionalSymbols.IsSymbolContext(ARequest.LineBefore, mPrefix);
  if not Result or not AContext.CompletionEnabled then
  begin
    Exit;
  end;
  for mSymbol in TConditionalSymbols.Candidates(ARequest.Text, AContext) do
  begin
    mItem := Default(TCompletionItem);
    mItem.Name := mSymbol.Name;
    mItem.Kind := cKindConstant;
    mItem.Detail := mSymbol.Detail;
    mItem.Unavailable := not mSymbol.Active;
    AItems.Items := AItems.Items + [mItem];
  end;
end;

class function TCompletionDirectives.DirectiveItems(ARequest: TCompletionRequest;
  out AItems: TCompletionItems): Boolean;
var
  mNames: TArray<string>;
  mIsWarning: Boolean;
  mName: string;
  mItem: TCompletionItem;
  mInfo: TDirectiveInfo;
begin
  if IncludeItems(ARequest, AItems) then
  begin
    Exit(True);
  end;
  AItems := Default(TCompletionItems);
  Result := TCompilerDirectives.CompletionAt(ARequest.LineBefore, mNames, mIsWarning);
  if not Result then
  begin
    Exit;
  end;
  for mName in mNames do
  begin
    mItem := Default(TCompletionItem);
    mItem.Name := mName;
    mItem.Kind := cKindKeyword;
    if mIsWarning then
    begin
      mItem.Detail := cTexts[TDirectivesText.CompilerWarning].Text;
    end
    else if TCompilerDirectives.Find(mName, mInfo) then
    begin
      mItem.Detail := mInfo.Text;
    end;
    AItems.Items := AItems.Items + [mItem];
  end;
end;

class function TCompletionDirectives.IncludeNameAt(const ALineBefore: string; out APartial: string;
  out AStart: Integer): Boolean;
var
  mOpen, mIndex: Integer;
  mWord: string;
  mQuoted: Boolean;
begin
  Result := False;
  APartial := '';
  AStart := 0;
  mOpen := 0;
  // Letzte offene Direktive in der Zeile vor dem Cursor (wie TCompilerDirectives.CompletionAt).
  while PosEx('{$', ALineBefore, mOpen + 1) > 0 do
  begin
    mOpen := PosEx('{$', ALineBefore, mOpen + 1);
  end;
  if (mOpen = 0) or (PosEx('}', ALineBefore, mOpen) > 0) then
  begin
    Exit;
  end;
  mIndex := mOpen + 2;
  while (mIndex <= Length(ALineBefore)) and CharInSet(ALineBefore[mIndex], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(mIndex);
  end;
  mWord := UpperCase(Copy(ALineBefore, mOpen + 2, mIndex - mOpen - 2));
  // Erst nach einem Leerzeichen: {$I+} und {$I-} sind der Schalter, {$IF …} eine andere Direktive.
  if ((mWord <> 'I') and (mWord <> 'INCLUDE')) or (mIndex > Length(ALineBefore)) or
    (ALineBefore[mIndex] <> ' ') then
  begin
    Exit;
  end;
  while (mIndex <= Length(ALineBefore)) and (ALineBefore[mIndex] = ' ') do
  begin
    Inc(mIndex);
  end;
  mQuoted := (mIndex <= Length(ALineBefore)) and (ALineBefore[mIndex] = '''');
  if mQuoted then
  begin
    Inc(mIndex);
  end;
  APartial := Copy(ALineBefore, mIndex, MaxInt);
  // Ohne Anführungszeichen endet der Name am Leerzeichen, mit ihnen am schließenden.
  if (Pos('''', APartial) > 0) or (not mQuoted and (Pos(' ', APartial) > 0)) then
  begin
    APartial := '';
    Exit;
  end;
  AStart := mIndex - 1;
  Result := True;
end;

type
  /// <summary>Sammelt die Dateinamen für {$I (L3): je Eintrag der eingefügte Text einmal.</summary>
  TIncludeNames = record
    Range: TTextRange;
    Seen: TDictionary<string, Boolean>;
    Folders: TDictionary<string, Boolean>;
    Items: TArray<TCompletionItem>;
    Capped: Boolean;
    /// <summary>*.inc aus AFolder; APrefix steht beim Einfügen vor dem Namen (Unterordner).</summary>
    procedure AddFolder(const AFolder, APrefix: string);
    procedure AddFile(const AFolder, APrefix, AName: string);
  end;

procedure TIncludeNames.AddFile(const AFolder, APrefix, AName: string);
var
  mItem: TCompletionItem;
  mText: string;
begin
  mText := APrefix + AName;
  if Seen.ContainsKey(UpperCase(mText)) then
  begin
    Exit;
  end;
  if Length(Items) >= cMaxIncludeFiles then
  begin
    Capped := True;
    Exit;
  end;
  Seen.Add(UpperCase(mText), True);
  mItem := Default(TCompletionItem);
  mItem.Name := mText;
  // Gefiltert wird über den Dateinamen: Hinter "" tippt man nur ihn.
  mItem.FilterText := AName;
  mItem.Kind := cKindModule;
  mItem.Detail := ExcludeTrailingPathDelimiter(AFolder);
  mItem.HasTextEdit := True;
  mItem.TextEdit := TRuleEdit.Create(Range, mText);
  Items := Items + [mItem];
end;

procedure TIncludeNames.AddFolder(const AFolder, APrefix: string);
var
  mFolder: string;
  mSearch: TSearchRec;
begin
  mFolder := IncludeTrailingPathDelimiter(AFolder);
  if (AFolder = '') or Folders.ContainsKey(UpperCase(mFolder)) or (Folders.Count >= cMaxIncludeFolders) then
  begin
    Exit;
  end;
  Folders.Add(UpperCase(mFolder), True);
  if FindFirst(mFolder + '*.inc', faAnyFile, mSearch) <> 0 then
  begin
    Exit;
  end;
  try
    repeat
      if (mSearch.Attr and faDirectory) = 0 then
      begin
        AddFile(mFolder, APrefix, mSearch.Name);
      end;
    until Capped or (FindNext(mSearch) <> 0);
  finally
    FindClose(mSearch);
  end;
end;

class function TCompletionDirectives.IncludeItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean;
var
  mPartial, mBase, mSubDir, mFolder, mInclude: string;
  mStart: Integer;
  mNames: TIncludeNames;
  mHeader: TUnitIndex;
begin
  AItems := Default(TCompletionItems);
  Result := IncludeNameAt(ARequest.LineBefore, mPartial, mStart);
  if not Result then
  begin
    Exit;
  end;
  // Ohne Datei (neues Dokument) kein Ordner: sonst gälte das Arbeitsverzeichnis des Prozesses.
  mBase := '';
  if ARequest.FileName <> '' then
  begin
    mBase := IncludeTrailingPathDelimiter(ExtractFilePath(ARequest.FileName));
  end;
  mNames := Default(TIncludeNames);
  mNames.Range := TTextRange.Create(TTextPosition.Create(ARequest.Position.Line, mStart), ARequest.Position);
  mNames.Seen := TDictionary<string, Boolean>.Create;
  mNames.Folders := TDictionary<string, Boolean>.Create;
  try
    // Getippter Unterordner ("inc\Ve"): nur dort, eingefügt samt Ordner.
    mSubDir := Copy(mPartial, 1, LastDelimiter('\/', mPartial));
    if (mBase <> '') and (mSubDir <> '') then
    begin
      mNames.AddFolder(mBase + mSubDir, mSubDir);
    end
    else if mBase <> '' then
    begin
      mNames.AddFolder(mBase, '');
    end;
    // Ordner der Include-Dateien, die die Unit schon einbindet (Kopf, lädt nichts nach): unterhalb des eigenen
    // Ordners samt relativem Pfad, sonst (Suchpfad) nur der Name.
    if (mSubDir = '') and (ARequest.Index <> nil) and (ARequest.FileName <> '') and
      ARequest.Index.FindHeader(ARequest.FileName, mHeader) then
    begin
      for mInclude in mHeader.Includes do
      begin
        mFolder := ExtractFilePath(mInclude);
        if (mBase <> '') and StartsText(mBase, mFolder) then
        begin
          mNames.AddFolder(mFolder, Copy(mFolder, Length(mBase) + 1, MaxInt));
        end
        else
        begin
          mNames.AddFolder(mFolder, '');
        end;
      end;
    end;
    AItems.Items := mNames.Items;
    AItems.Incomplete := mNames.Capped;
  finally
    mNames.Folders.Free;
    mNames.Seen.Free;
  end;
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Lsp.Completion.Directives', cTexts);

end.
