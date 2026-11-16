unit dpcc.Core.Completion.Placeholders.Tests;

// Tests für Text mit Platzhaltern und den Platzhalter-Modus (#51), ohne Editor. Bis S2 standen sie bei den Tests der
// Code-Vorlagen; die Code-Vorlagen selbst gibt es nicht mehr.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Einsetzen (TDpccPlaceholderText.Expand) und Übernahme aus der LSP-Syntax des Servers (FromLsp).
  /// </summary>
  [TestFixture]
  TDpccPlaceholderTextTests = class
  public
    [Test]
    procedure ExpandsWithIndentAndLinkedDefaults;
    [Test]
    procedure KeepsHexNumbers;
    [Test]
    procedure DoubleDollarIsText;
    [Test]
    procedure ConvertsServerPlaceholders;
    [Test]
    procedure TagsPostfixAndPlaceholderItems;
  end;

  [TestFixture]
  TDpccPlaceholderSessionTests = class
  public
    [Test]
    procedure TabWalksThroughPlaceholders;
    [Test]
    procedure TypingUpdatesLinkedPlaceholders;
    [Test]
    procedure TypingAfterPlaceholderMovesFollowingOnes;
    [Test]
    procedure EditOutsideEndsSession;
    [Test]
    procedure WithoutEndMarkerEndsBehindText;
    [Test]
    procedure LocatesOffsets;
    [Test]
    procedure LinkedFieldOutsideText;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Presentation,
  dpcc.Core.Completion.Placeholders;

const
  TryFinally = '${1:List} := ${2:TStringList}.Create;'#10'try'#10'  $0'#10'finally'#10'  ${1}.Free;'#10'end;';

function Replace(const AText: string; AStart, AStop: Integer; const AValue: string): string;
begin
  Result := Copy(AText, 1, AStart) + AValue + Copy(AText, AStop + 1, MaxInt);
end;

function Apply(const AText: string; const AEdits: TDpccPlaceholderEdits): string;
var
  Index: Integer;
begin
  Result := AText;
  for Index := High(AEdits) downto 0 do
  begin
    Result := Replace(Result, AEdits[Index].Start, AEdits[Index].Stop, AEdits[Index].Text);
  end;
end;

{ TDpccPlaceholderTextTests }

procedure TDpccPlaceholderTextTests.ExpandsWithIndentAndLinkedDefaults;
var
  Expansion: TDpccPlaceholderExpansion;
begin
  Expansion := TDpccPlaceholderText.Expand(TryFinally, '    ', #13#10);
  Assert.AreEqual('List := TStringList.Create;'#13#10'    try'#13#10'      '#13#10'    finally'#13#10 +
    '      List.Free;'#13#10'    end;', Expansion.Text);
  Assert.AreEqual(4, Integer(Length(Expansion.Stops)));
  // List, TStringList, $0, zweites List mit dem Vorgabetext des ersten.
  Assert.AreEqual(1, Expansion.Stops[0].Number);
  Assert.AreEqual(0, Expansion.Stops[0].Start);
  Assert.AreEqual(4, Expansion.Stops[0].Length);
  Assert.AreEqual(2, Expansion.Stops[1].Number);
  Assert.AreEqual('TStringList', Copy(Expansion.Text, Expansion.Stops[1].Start + 1, Expansion.Stops[1].Length));
  Assert.AreEqual(0, Expansion.Stops[2].Number);
  Assert.AreEqual(0, Expansion.Stops[2].Length);
  Assert.AreEqual(1, Expansion.Stops[3].Number);
  Assert.AreEqual('List', Copy(Expansion.Text, Expansion.Stops[3].Start + 1, Expansion.Stops[3].Length));
  Assert.IsTrue(Expansion.HasPlaceholders);
  Assert.AreEqual('A := B;', TDpccPlaceholderText.PlainText('${1:A} := ${2:B};$0'));
  Assert.IsFalse(TDpccPlaceholderText.Expand('Exit;$0', '', #10).HasPlaceholders);
end;

procedure TDpccPlaceholderTextTests.KeepsHexNumbers;
var
  Expansion: TDpccPlaceholderExpansion;
begin
  Expansion := TDpccPlaceholderText.Expand('Mask := $FF or $0F or $10 or $0A;${x} $', '', #10);
  Assert.AreEqual('Mask := $FF or $0F or $10 or $0A;${x} $', Expansion.Text);
  Assert.AreEqual(0, Integer(Length(Expansion.Stops)));
  Assert.AreEqual('{$IFDEF X}Y{$ENDIF}', TDpccPlaceholderText.PlainText('{$IFDEF X}${1:Y}{$ENDIF}'));
end;

procedure TDpccPlaceholderTextTests.DoubleDollarIsText;
var
  Expansion: TDpccPlaceholderExpansion;
begin
  Expansion := TDpccPlaceholderText.Expand('X := Y and $$1;$0', '', #10);
  Assert.AreEqual('X := Y and $1;', Expansion.Text);
  Assert.AreEqual(1, Integer(Length(Expansion.Stops)));
  Assert.AreEqual(0, Expansion.Stops[0].Number);
end;

procedure TDpccPlaceholderTextTests.ConvertsServerPlaceholders;
var
  Expansion: TDpccPlaceholderExpansion;
begin
  // LSP-Syntax des Servers (#51, insertTextFormat 2) im eigenen Format.
  Assert.AreEqual('property ${1:Farbe}: TColor;$0', TDpccPlaceholderText.FromLsp('property ${1:Farbe}: TColor;$0'));
  Assert.AreEqual('X := $$FF; a}b\c', TDpccPlaceholderText.FromLsp('X := \$FF; a\}b\\c'));
  Assert.AreEqual('${1} ${2:ja}', TDpccPlaceholderText.FromLsp('$1 ${2|ja,nein|}'));
  Assert.AreEqual('${1:Liste.Free} $$FF',
    TDpccPlaceholderText.FromLsp('${1:${2:Liste}.Free} ${TM_SELECTED_TEXT}$FF'));
  Assert.AreEqual('a$$b', TDpccPlaceholderText.FromLsp('a$b'));
  // Eingesetzt: Platzhalter und Endposition, Hexzahl als Text.
  Expansion := TDpccPlaceholderText.Expand(
    TDpccPlaceholderText.FromLsp('if F <> \$FF then'#10'  ${1:Invalidate};$0'), '  ', #10);
  Assert.AreEqual('if F <> $FF then'#10'    Invalidate;', Expansion.Text);
  Assert.AreEqual(2, Integer(Length(Expansion.Stops)));
  Assert.AreEqual(1, Expansion.Stops[0].Number);
end;

procedure TDpccPlaceholderTextTests.TagsPostfixAndPlaceholderItems;
var
  Item: TDpccCompletionItem;
  Tags: TDpccTags;
begin
  Item := Default(TDpccCompletionItem);
  Item.Name := 'notnil';
  Item.Kind := TDpccItemKind.Snippet;
  Item.PlaceholderText := 'if Assigned(X) then'#10'  $0';
  Item.Postfix := True;
  Tags := TDpccItemPresentation.Tags(Item);
  Assert.AreEqual(1, Integer(Length(Tags)));
  Assert.AreEqual('Postfix', Tags[0].Text);
  // Übrige Einträge mit Platzhaltern (etwa das Gerüst einer anonymen Methode) tragen die Marke „Vorlage“.
  Item.Name := 'procedure';
  Item.PlaceholderText := 'procedure'#10'begin'#10'  $0'#10'end';
  Item.Postfix := False;
  Tags := TDpccItemPresentation.Tags(Item);
  Assert.AreEqual(1, Integer(Length(Tags)));
  Assert.AreEqual('Vorlage', Tags[0].Text);
end;

{ TDpccPlaceholderSessionTests }

function Start(const ABefore, ABody, AAfter: string; out ADocument: string): TDpccPlaceholderSession;
var
  Expansion: TDpccPlaceholderExpansion;
begin
  Expansion := TDpccPlaceholderText.Expand(ABody, '  ', #10);
  ADocument := ABefore + Expansion.Text + AAfter;
  Result := TDpccPlaceholderSession.Create(ADocument, Length(ABefore), Expansion);
end;

procedure TDpccPlaceholderSessionTests.TabWalksThroughPlaceholders;
var
  Session: TDpccPlaceholderSession;
  Document: string;
begin
  Session := Start('begin'#10'  ', TryFinally, #10'end;', Document);
  try
    Assert.AreEqual(1, Session.CurrentNumber);
    Assert.AreEqual(1, Session.Position);
    Assert.AreEqual(2, Integer(Session.Count));
    Assert.AreEqual(8, Session.Current.Start);
    Assert.AreEqual('List', Session.FieldText(Session.Current));
    Assert.AreEqual(3, Integer(Length(Session.Fields)));
    Session.Previous;
    Assert.AreEqual(1, Session.CurrentNumber);
    Assert.IsTrue(Session.Next);
    Assert.AreEqual('TStringList', Session.FieldText(Session.Current));
    Assert.AreEqual(2, Session.Position);
    Session.Previous;
    Assert.AreEqual(1, Session.CurrentNumber);
    Assert.IsTrue(Session.Next);
    // Nach dem letzten Platzhalter: Endposition in der leeren Zeile zwischen try und finally.
    Assert.IsFalse(Session.Next);
    Assert.AreEqual(0, Session.CurrentNumber);
    Assert.AreEqual(Pos('try'#10'    ', Document) + 7, Session.FinalOffset);
  finally
    Session.Free;
  end;
end;

procedure TDpccPlaceholderSessionTests.TypingUpdatesLinkedPlaceholders;
var
  Session: TDpccPlaceholderSession;
  Document: string;
  Edits: TDpccPlaceholderEdits;
begin
  Session := Start('', TryFinally, '', Document);
  try
    // Die markierte Vorgabe "List" wird durch "I" ersetzt, dann "tems" getippt.
    Document := Replace(Document, 0, 4, 'I');
    Assert.IsTrue(Session.Update(Document));
    Document := Replace(Document, 1, 1, 'tems');
    Assert.IsTrue(Session.Update(Document));
    Assert.AreEqual('Items', Session.FieldText(Session.Current));
    Edits := Session.MirrorEdits;
    Assert.AreEqual(1, Integer(Length(Edits)));
    Assert.AreEqual('Items', Edits[0].Text);
    Document := Apply(Document, Edits);
    Session.Applied(Edits);
    Assert.AreEqual(Document, Session.Text);
    Assert.AreEqual('Items := TStringList.Create;'#10'  try'#10'    '#10'  finally'#10'    Items.Free;'#10'  end;', Document);
    // Die Benachrichtigung über das Angleichen ändert nichts mehr.
    Assert.IsTrue(Session.Update(Document));
    Assert.AreEqual(0, Integer(Length(Session.MirrorEdits)));
    // Im verknüpften Platzhalter getippt: Er wird zur Vorlage.
    Document := Replace(Document, Pos('Items.Free', Document) + 4, Pos('Items.Free', Document) + 4, 'X');
    Assert.IsTrue(Session.Update(Document));
    Edits := Session.MirrorEdits;
    Assert.AreEqual('ItemsX', Edits[0].Text);
    Assert.AreEqual(0, Edits[0].Start);
    Document := Apply(Document, Edits);
    Session.Applied(Edits);
    Assert.StartsWith('ItemsX := TStringList', Document);
    Assert.AreEqual(Document, Session.Text);
    // Alles bis auf einen leeren Platzhalter löschen geht auch.
    Session.Previous;
    Document := Replace(Document, 0, 6, '');
    Assert.IsTrue(Session.Update(Document));
    Assert.AreEqual(0, Session.Current.Length);
  finally
    Session.Free;
  end;
end;

procedure TDpccPlaceholderSessionTests.TypingAfterPlaceholderMovesFollowingOnes;
var
  Session: TDpccPlaceholderSession;
  Document: string;
  Final: Integer;
begin
  Session := Start('x', TryFinally, '', Document);
  try
    Assert.IsTrue(Session.Next);
    Final := Session.FinalOffset;
    // Am Ende von "TStringList" ein "." anhängen; dahinter steht schon einer, die Stelle ist also mehrdeutig.
    Document := Replace(Document, Session.Current.Stop, Session.Current.Stop, '.');
    Assert.IsTrue(Session.Update(Document));
    Assert.AreEqual('TStringList.', Session.FieldText(Session.Current));
    Assert.AreEqual(Final + 1, Session.FinalOffset);
    Assert.AreEqual(0, Integer(Length(Session.MirrorEdits)));
  finally
    Session.Free;
  end;
end;

procedure TDpccPlaceholderSessionTests.EditOutsideEndsSession;
var
  Session: TDpccPlaceholderSession;
  Document: string;
begin
  Session := Start('begin'#10, TryFinally, '', Document);
  try
    Assert.IsFalse(Session.Update(Replace(Document, 0, 0, '//')));
  finally
    Session.Free;
  end;
  // Änderung im Platzhalter 2, während 1 aktiv ist: auch vorbei.
  Session := Start('', TryFinally, '', Document);
  try
    Assert.IsFalse(Session.Update(Replace(Document, 9, 9, 'X')));
  finally
    Session.Free;
  end;
end;

procedure TDpccPlaceholderSessionTests.WithoutEndMarkerEndsBehindText;
var
  Session: TDpccPlaceholderSession;
  Document: string;
begin
  Session := Start('a ', 'Exit(${1:False});', ' b', Document);
  try
    Assert.AreEqual(1, Integer(Session.Count));
    Assert.IsFalse(Session.Next);
    Assert.AreEqual(Integer(Length('a Exit(False);')), Session.FinalOffset);
  finally
    Session.Free;
  end;
end;

procedure TDpccPlaceholderSessionTests.LocatesOffsets;
var
  Line, Character: Integer;
begin
  TDpccPlaceholderSession.Locate('ab'#13#10'cde'#10'f', 0, Line, Character);
  Assert.AreEqual(0, Line);
  Assert.AreEqual(0, Character);
  TDpccPlaceholderSession.Locate('ab'#13#10'cde'#10'f', 6, Line, Character);
  Assert.AreEqual(1, Line);
  Assert.AreEqual(2, Character);
  TDpccPlaceholderSession.Locate('ab'#13#10'cde'#10'f', 99, Line, Character);
  Assert.AreEqual(2, Line);
  Assert.AreEqual(1, Character);
end;

procedure TDpccPlaceholderSessionTests.LinkedFieldOutsideText;
const
  Declaration = '  SName = ''Name'';'#10;
var
  Session: TDpccPlaceholderSession;
  Document: string;
  Edits: TDpccPlaceholderEdits;
  Field: TDpccPlaceholderField;
begin
  // resourcestring auslagern (#473): Der Name steht in der Deklaration davor und im Literal.
  Session := Start(Declaration + 'begin'#10'  ShowMessage(', '${1:SName}', ');', Document);
  try
    Field.Number := 1;
    Field.Start := 2;
    Field.Length := 5;
    Session.Link(Field);
    // Unbekannte Nummer und Endposition werden übergangen.
    Field.Number := 7;
    Session.Link(Field);
    Field.Number := 0;
    Session.Link(Field);
    Assert.AreEqual(2, Integer(Length(Session.Fields)));
    Assert.AreEqual(1, Integer(Session.Count));
    Assert.AreEqual('SName', Session.FieldText(Session.Current));
    // Im Literal getippt: Die Deklaration davor folgt, der Platzhalter im Literal rückt nach.
    Document := Replace(Document, Session.Current.Start, Session.Current.Stop, 'SFrage');
    Assert.IsTrue(Session.Update(Document));
    Edits := Session.MirrorEdits;
    Assert.AreEqual(1, Integer(Length(Edits)));
    Assert.AreEqual(2, Edits[0].Start);
    Assert.AreEqual('SFrage', Edits[0].Text);
    Document := Apply(Document, Edits);
    Session.Applied(Edits);
    Assert.AreEqual(Document, Session.Text);
    Assert.AreEqual('  SFrage = ''Name'';'#10'begin'#10'  ShowMessage(SFrage);', Document);
    Assert.AreEqual(Pos('(SFrage', Document), Session.Current.Start);
    Assert.AreEqual('SFrage', Session.FieldText(Session.Current));
  finally
    Session.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccPlaceholderTextTests);
  TDUnitX.RegisterTestFixture(TDpccPlaceholderSessionTests);

end.
