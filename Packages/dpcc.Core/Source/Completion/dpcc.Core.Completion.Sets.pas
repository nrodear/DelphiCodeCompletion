unit dpcc.Core.Completion.Sets;

// Mengenmodus der Vervollständigung (#448), ohne Fenster: In einem Mengenkonstruktor
// ("Anchors := [akLeft, ") liefert der Server alle Werte des Elementtyps mit SetOf,
// Checked (steht schon in der Klammer) und SetRange (von "[" bis hinter "]"). Die
// Liste zeigt Kontrollkästchen, die Leertaste schaltet um, Enter schreibt die ganze
// Klammer neu: angehakte Werte in Deklarationsreihenfolge, bei {$SCOPEDENUMS ON} mit
// Typpräfix (InsertText). Esc verwirft.
//
// Interface implementieren (#466) nutzt dieselbe Liste: Batch-Einträge sind fehlende Methoden, alle angehakt.
// Enter entfernt das getippte Wort (SetRange) und übernimmt die AdditionalEdits der angehakten Einträge in
// Ordinal-Reihenfolge. Einfügungen an derselben Stelle (Abschnitt, Kommentar je Interface, Deklarationen bzw.
// Rümpfe) werden zu einer zusammengefasst, gleiche Texte nur einmal.
//
// Alle Felder zuweisen (#491) mit mehr als 15 Feldern: Übernehmen des Eintrags macht aus seinen Assignments
// dieselbe Liste (AssignItems), alle angehakt; Enter entfernt den Ausdruck und setzt die angehakten Zeilen ein.

interface

uses
  dpcc.Core.Completion.Contract;

type
  TDpccCompletionSets = class
  public
    /// <summary>Die Liste ist im Mengenmodus.</summary>
    class function Active(const AItems: TDpccCompletionItems): Boolean; static;
    class function CheckedCount(const AItems: TDpccCompletionItems): Integer; static;
    /// <summary>Neuer Klammerinhalt, z. B. "[akLeft, akTop]"; "[]" ohne angehakte Werte.</summary>
    class function Text(const AItems: TDpccCompletionItems): string; static;
    /// <summary>Eintrag, der beim Übernehmen die Klammer durch Text ersetzt (textEdit über SetRange).</summary>
    class function CommitItem(const AItems: TDpccCompletionItems): TDpccCompletionItem; static;
    /// <summary>Fasst Änderungen mit gleichem Bereich zusammen (#466): Texte in der Reihenfolge des ersten
    /// Auftretens, gleiche nur einmal.</summary>
    class function Merge(const AEdits: TArray<TDpccTextEdit>): TArray<TDpccTextEdit>; static;
    /// <summary>Liste für „Alle Felder zuweisen“ (#491): je Zeile aus AItem.Assignments ein angehakter Eintrag
    /// (Batch, Assign); SetRange ist der textEdit von AItem (der Ausdruck mit Punkt), jede Zeile kommt an dessen
    /// Ende. Leer ohne Assignments.</summary>
    class function AssignItems(const AItem: TDpccCompletionItem): TDpccCompletionItems; static;
  end;

implementation

uses
  System.SysUtils;

/// <summary>Angehakte Einträge nach Ordinal (wenige Einträge, Einfügen genügt).</summary>
function CheckedInOrder(const AItems: TDpccCompletionItems): TDpccCompletionItems;
var
  mItem, mMoved: TDpccCompletionItem;
  mIndex, mScan: Integer;
begin
  Result := nil;
  for mItem in AItems do
  begin
    if (mItem.SetOf <> '') and mItem.Checked then
    begin
      Result := Result + [mItem];
    end;
  end;
  for mIndex := 1 to High(Result) do
  begin
    mMoved := Result[mIndex];
    mScan := mIndex - 1;
    while (mScan >= 0) and (Result[mScan].Ordinal > mMoved.Ordinal) do
    begin
      Result[mScan + 1] := Result[mScan];
      Dec(mScan);
    end;
    Result[mScan + 1] := mMoved;
  end;
end;

function SameRange(const A, B: TDpccTextEdit): Boolean;
begin
  Result := (A.StartLine = B.StartLine) and (A.StartCharacter = B.StartCharacter) and (A.EndLine = B.EndLine) and
    (A.EndCharacter = B.EndCharacter);
end;

class function TDpccCompletionSets.Active(const AItems: TDpccCompletionItems): Boolean;
var
  mItem: TDpccCompletionItem;
begin
  for mItem in AItems do
  begin
    if mItem.SetOf <> '' then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDpccCompletionSets.CheckedCount(const AItems: TDpccCompletionItems): Integer;
var
  mItem: TDpccCompletionItem;
begin
  Result := 0;
  for mItem in AItems do
  begin
    if (mItem.SetOf <> '') and mItem.Checked then
    begin
      Inc(Result);
    end;
  end;
end;

class function TDpccCompletionSets.Text(const AItems: TDpccCompletionItems): string;
var
  mChosen: TDpccCompletionItems;
  mIndex: Integer;
begin
  mChosen := CheckedInOrder(AItems);
  Result := '';
  for mIndex := 0 to High(mChosen) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ', ';
    end;
    if mChosen[mIndex].InsertText <> '' then
    begin
      Result := Result + mChosen[mIndex].InsertText;
    end
    else
    begin
      Result := Result + mChosen[mIndex].Name;
    end;
  end;
  Result := '[' + Result + ']';
end;

class function TDpccCompletionSets.Merge(const AEdits: TArray<TDpccTextEdit>): TArray<TDpccTextEdit>;
var
  mEdit: TDpccTextEdit;
  mIndex, mFound: Integer;
  // Je Bereich die schon übernommenen Texte, mit #0 umschlossen.
  mSeen: TArray<string>;
begin
  Result := nil;
  mSeen := nil;
  for mEdit in AEdits do
  begin
    mFound := -1;
    for mIndex := 0 to High(Result) do
    begin
      if SameRange(Result[mIndex], mEdit) then
      begin
        mFound := mIndex;
        Break;
      end;
    end;
    if mFound < 0 then
    begin
      Result := Result + [mEdit];
      mSeen := mSeen + [#0 + mEdit.NewText + #0];
    end
    else if Pos(#0 + mEdit.NewText + #0, mSeen[mFound]) = 0 then
    begin
      mSeen[mFound] := mSeen[mFound] + mEdit.NewText + #0;
      Result[mFound].NewText := Result[mFound].NewText + mEdit.NewText;
    end;
  end;
end;

class function TDpccCompletionSets.AssignItems(const AItem: TDpccCompletionItem): TDpccCompletionItems;
var
  mIndex: Integer;
  mRange, mInsert: TDpccTextEdit;
  mTitle: string;
begin
  Result := nil;
  if not AItem.HasTextEdit then
  begin
    Exit;
  end;
  mRange := AItem.TextEdit;
  mRange.NewText := '';
  mInsert := mRange;
  mInsert.StartLine := mRange.EndLine;
  mInsert.StartCharacter := mRange.EndCharacter;
  // Überschrift mit dem Typ des Ausdrucks.
  mTitle := AItem.Signature;
  if mTitle = '' then
  begin
    mTitle := AItem.Name;
  end;
  SetLength(Result, Length(AItem.Assignments));
  for mIndex := 0 to High(AItem.Assignments) do
  begin
    Result[mIndex] := Default(TDpccCompletionItem);
    Result[mIndex].Name := AItem.Assignments[mIndex].Name;
    Result[mIndex].Signature := AItem.Assignments[mIndex].Detail;
    Result[mIndex].Kind := TDpccItemKind.Field;
    Result[mIndex].Batch := True;
    Result[mIndex].Assign := True;
    Result[mIndex].Ordinal := mIndex + 1;
    Result[mIndex].Checked := True;
    Result[mIndex].SetOf := mTitle;
    Result[mIndex].ExpectedType := mTitle;
    Result[mIndex].Fits := True;
    // Die Zusatzänderung ist kein uses-Eintrag.
    Result[mIndex].UnitUsed := True;
    Result[mIndex].SetRange := mRange;
    mInsert.NewText := AItem.Assignments[mIndex].Text;
    Result[mIndex].AdditionalEdits := [mInsert];
  end;
end;

class function TDpccCompletionSets.CommitItem(const AItems: TDpccCompletionItems): TDpccCompletionItem;
var
  mItem, mChosen: TDpccCompletionItem;
  mEdits: TArray<TDpccTextEdit>;
begin
  Result := Default(TDpccCompletionItem);
  // Interface implementieren (#466): das getippte Wort weg, die Änderungen der angehakten Methoden dazu.
  for mItem in AItems do
  begin
    if mItem.Batch then
    begin
      Result.Name := mItem.SetOf;
      Result.Kind := TDpccItemKind.Method;
      // Erzeugt Code: die Zusatzänderungen gelten auch ohne automatische uses-Einträge.
      Result.IsAction := True;
      Result.HasTextEdit := True;
      Result.TextEdit := mItem.SetRange;
      Result.TextEdit.NewText := '';
      mEdits := nil;
      for mChosen in CheckedInOrder(AItems) do
      begin
        mEdits := mEdits + mChosen.AdditionalEdits;
      end;
      Result.AdditionalEdits := Merge(mEdits);
      Exit;
    end;
  end;
  Result.Name := Text(AItems);
  Result.Kind := TDpccItemKind.EnumMember;
  Result.InsertText := Result.Name;
  for mItem in AItems do
  begin
    if mItem.SetOf <> '' then
    begin
      Result.HasTextEdit := True;
      Result.TextEdit := mItem.SetRange;
      Result.TextEdit.NewText := Result.Name;
      Break;
    end;
  end;
end;

end.
