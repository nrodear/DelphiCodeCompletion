unit dpcc.Common.Lsp.Definition.NoTarget.Tests;

// Sprung ohne Ziel (dpcc/noTarget): Vor der leeren Antwort auf textDocument/declaration bzw. definition meldet der
// Server den Grund (noDocument, noIdentifier, unresolved, unitNotFound, noSource, inactiveBranch) samt Name und
// Stelle, und zwar vor der Antwort. Führt die Auflösung nur in eine Ersatz-Unit der IDE, lädt er vorher die echte
// Quelle nach (sie war sonst still verdeckt). Über den Verteiler ohne Scheduler: Handler und Antwort im Testthread.

interface

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract,
  dpcc.Common.Documents.Contract,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Lsp.Definition;

type
  [TestFixture]
  TLspDefinitionNoTargetTests = class
  private
    FInner: ISymbolIndex;
    FIde: ISymbolIndex;
    FIndex: ISymbolIndex;
    FStore: IDocumentStore;
    FDispatcher: TJsonRpcDispatcher;
    FDefinition: TLspDefinition;
    /// <summary>Ereignisse in Reihenfolge: "notify|Methode|Grund|Name|Zeile|Zeichen" und "response|Anzahl"
    /// (-1 = null).</summary>
    FEvents: TList<string>;
    /// <summary>Legt Verteiler und TLspDefinition mit AEnsureUnit an (nil = ohne Nachladen).</summary>
    procedure Attach(const AEnsureUnit: TEnsureUnitFunc);
    /// <summary>Öffnet AText unter AFileName.</summary>
    procedure Open(const AFileName, AText: string);
    /// <summary>Schickt AMethod für AFileName an der Stelle von AMarker (AOccurrence-tes Vorkommen in AText) und
    /// hält die Antwort in FEvents fest.</summary>
    procedure Request(const AMethod, AFileName, AText, AMarker: string; AOccurrence: Integer);
    /// <summary>Genau eine Meldung, danach die leere Antwort; liefert die Felder der Meldung.</summary>
    function SingleNoTarget: TArray<string>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Unbekanntes Dokument: noDocument, Antwort null.</summary>
    [Test]
    procedure UnknownDocumentIsNoDocument;
    /// <summary>Stelle im Kommentar: noIdentifier.</summary>
    [Test]
    procedure CommentIsNoIdentifier;
    /// <summary>Unbekannter Bezeichner: unresolved mit seinem Namen.</summary>
    [Test]
    procedure UnknownNameIsUnresolved;
    /// <summary>Typ aus einer Unit in uses, die es nicht gibt (requires-Package ohne gefundene .dpk): unitNotFound
    /// mit dem Namen der Unit.</summary>
    [Test]
    procedure MissingUsedUnitIsUnitNotFound;
    /// <summary>Typ nur in einer Ersatz-Unit der IDE (Package ohne Quelltext): noSource mit dem Namen der Unit.
    /// </summary>
    [Test]
    procedure IdeUnitOnlyIsNoSource;
    /// <summary>Ersatz-Unit der IDE, aber die Quelle ist über EnsureUnit zu finden: Ziel ist die echte Unit, keine
    /// Meldung.</summary>
    [Test]
    procedure IdeUnitLoadsRealSource;
    /// <summary>Deklaration nur im nicht geltenden Zweig einer benutzten Unit: inactiveBranch.</summary>
    [Test]
    procedure InactiveDeclarationInUsedUnit;
    /// <summary>Mit Ziel keine Meldung; textDocument/definition nennt seine Methode.</summary>
    [Test]
    procedure FoundTargetSendsNothing;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Documents.Providers.DocumentStore,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Lsp.IdeIndex,
  dpcc.Common.Lsp.IdeUnits;

const
  cMainFile = 'C:\P\Haupt.pas';
  cUnitBFile = 'C:\Q\UnitB.pas';

  cUnitB =
    'unit UnitB;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TQType = class'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUsesB =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses UnitB;'#10 +
    'var'#10 +
    '  Wert: TQType;'#10 +
    'implementation'#10 +
    'end.';

  cUnknown =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure Rufe;'#10 +
    'begin'#10 +
    '  // Hinweis im Kommentar'#10 +
    '  Unbekannt;'#10 +
    'end;'#10 +
    'end.';

  cBplText =
    'unit Vendor.Bpl;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBplThing = class end;'#10 +
    'implementation'#10 +
    'end.';

  cUsesBpl =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Vendor.Bpl;'#10 +
    'var B: TBplThing;'#10 +
    'implementation'#10 +
    'end.';

  cZweige =
    'unit Zweige;'#10 +
    'interface'#10 +
    '{$IFDEF NIE}'#10 +
    'procedure Weg;'#10 +
    '{$ENDIF}'#10 +
    'implementation'#10 +
    'end.';

  cUsesZweige =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Zweige;'#10 +
    'implementation'#10 +
    'procedure Rufe;'#10 +
    'begin'#10 +
    '  Weg;'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition;
var
  mIndex, mFound, mLine, mLineStart: Integer;
begin
  mFound := 0;
  mIndex := 0;
  repeat
    mIndex := Pos(AMarker, AText, mIndex + 1);
    if mIndex = 0 then
    begin
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    end;
    Inc(mFound);
  until mFound = AOccurrence;
  mLine := 0;
  mLineStart := 1;
  for mFound := 1 to mIndex - 1 do
  begin
    if AText[mFound] = #10 then
    begin
      Inc(mLine);
      mLineStart := mFound + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

{ TLspDefinitionNoTargetTests }

procedure TLspDefinitionNoTargetTests.Setup;
begin
  // Wie der Server: der gemeinsame Index zuerst, die Ersatz-Units der IDE nur für Units ohne Quelltext.
  FInner := TSymbolIndex.Create;
  FIde := TSymbolIndex.Create;
  FIndex := TIdeIndex.Create(FInner, FIde);
  FStore := TDocumentStore.Create;
  FEvents := TList<string>.Create;
end;

procedure TLspDefinitionNoTargetTests.TearDown;
begin
  FreeAndNil(FDefinition);
  FreeAndNil(FDispatcher);
  FreeAndNil(FEvents);
  FStore := nil;
  FIndex := nil;
  FIde := nil;
  FInner := nil;
end;

procedure TLspDefinitionNoTargetTests.Attach(const AEnsureUnit: TEnsureUnitFunc);
var
  mEvents: TList<string>;
begin
  mEvents := FEvents;
  FDispatcher := TJsonRpcDispatcher.Create;
  FDefinition := TLspDefinition.Create(FStore, FIndex, AEnsureUnit);
  FDefinition.Notify :=
    procedure(const AMethod: string; AParams: TJSONObject)
    begin
      try
        mEvents.Add(String.Join('|', [AMethod + '|' + AParams.GetValue<string>('method'),
          AParams.GetValue<string>('reason'), AParams.GetValue<string>('name'),
          IntToStr(AParams.GetValue<Integer>('line')), IntToStr(AParams.GetValue<Integer>('character')),
          BoolToStr(AParams.GetValue<Boolean>('indexing'), True)]));
      finally
        AParams.Free;
      end;
    end;
  FDefinition.Indexing :=
    function: Boolean
    begin
      Result := True;
    end;
  FDefinition.Attach(FDispatcher);
end;

procedure TLspDefinitionNoTargetTests.Open(const AFileName, AText: string);
begin
  FStore.Open(TDocumentUris.FromPath(AFileName), 'pascal', 1, AText);
end;

procedure TLspDefinitionNoTargetTests.Request(const AMethod, AFileName, AText, AMarker: string; AOccurrence: Integer);
var
  mPosition: TTextPosition;
  mMessage, mParams, mResponse: TJSONObject;
  mResult: TJSONValue;
  mCount: Integer;
begin
  mPosition := PositionOf(AText, AMarker, AOccurrence);
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', TDocumentUris.FromPath(AFileName))));
  mParams.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(mPosition.Line))
    .AddPair('character', TJSONNumber.Create(mPosition.Character)));
  mMessage := TJSONObject.Create;
  try
    mMessage.AddPair('jsonrpc', '2.0');
    mMessage.AddPair('id', TJSONNumber.Create(1));
    mMessage.AddPair('method', AMethod);
    mMessage.AddPair('params', mParams);
    mResponse := FDispatcher.DispatchMessage(mMessage);
  finally
    mMessage.Free;
  end;
  try
    Assert.IsNotNull(mResponse, 'Antwort im aufrufenden Thread');
    mResult := mResponse.GetValue('result');
    Assert.IsNotNull(mResult, 'Ergebnis statt Fehler');
    mCount := -1;
    if mResult is TJSONArray then
    begin
      mCount := TJSONArray(mResult).Count;
    end;
    FEvents.Add('response|' + IntToStr(mCount));
  finally
    mResponse.Free;
  end;
end;

function TLspDefinitionNoTargetTests.SingleNoTarget: TArray<string>;
var
  mResponse: string;
begin
  Assert.AreEqual(2, FEvents.Count, 'eine Meldung und eine Antwort: ' + String.Join(' / ', FEvents.ToArray));
  Result := FEvents[0].Split(['|']);
  Assert.AreEqual(TLspDefinition.cNoTargetMethod, Result[0], 'zuerst die Meldung, dann die Antwort');
  mResponse := FEvents[1];
  Assert.IsTrue(mResponse.StartsWith('response|'), 'danach die Antwort');
  Assert.IsTrue((mResponse = 'response|0') or (mResponse = 'response|-1'), 'Antwort leer: ' + mResponse);
end;

procedure TLspDefinitionNoTargetTests.UnknownDocumentIsNoDocument;
var
  mFields: TArray<string>;
begin
  Attach(nil);
  Request(TLspDefinition.cDeclarationMethod, cMainFile, cUsesB, 'TQType', 1);
  mFields := SingleNoTarget;
  Assert.AreEqual(TLspDefinition.cDeclarationMethod, mFields[1], 'Methode');
  Assert.AreEqual(TLspDefinition.cReasonNoDocument, mFields[2], 'Grund');
  Assert.AreEqual('', mFields[3], 'ohne Name');
  Assert.AreEqual('4', mFields[4], 'Zeile 0-basiert');
  Assert.AreEqual('8', mFields[5], 'Zeichen 0-basiert');
  Assert.AreEqual('True', mFields[6], 'indexing aus dem Rückruf');
  Assert.AreEqual('response|-1', FEvents[1], 'Antwort null');
end;

procedure TLspDefinitionNoTargetTests.CommentIsNoIdentifier;
var
  mFields: TArray<string>;
begin
  Attach(nil);
  Open(cMainFile, cUnknown);
  Request(TLspDefinition.cDeclarationMethod, cMainFile, cUnknown, 'Hinweis', 1);
  mFields := SingleNoTarget;
  Assert.AreEqual(TLspDefinition.cReasonNoIdentifier, mFields[2], 'Grund');
  Assert.AreEqual('', mFields[3], 'ohne Name');
end;

procedure TLspDefinitionNoTargetTests.UnknownNameIsUnresolved;
var
  mFields: TArray<string>;
begin
  Attach(nil);
  Open(cMainFile, cUnknown);
  Request(TLspDefinition.cDeclarationMethod, cMainFile, cUnknown, 'Unbekannt', 1);
  mFields := SingleNoTarget;
  Assert.AreEqual(TLspDefinition.cReasonUnresolved, mFields[2], 'Grund');
  Assert.AreEqual('Unbekannt', mFields[3], 'Bezeichner');
end;

procedure TLspDefinitionNoTargetTests.MissingUsedUnitIsUnitNotFound;
var
  mFields: TArray<string>;
begin
  // Nachladen ohne Erfolg wie im Server, wenn die .dpk des requires-Packages nirgends liegt.
  Attach(
    function(const AUnitName: string): Boolean
    begin
      Result := False;
    end);
  Open(cMainFile, cUsesB);
  Request(TLspDefinition.cDeclarationMethod, cMainFile, cUsesB, 'TQType', 1);
  mFields := SingleNoTarget;
  Assert.AreEqual(TLspDefinition.cReasonUnitNotFound, mFields[2], 'Grund');
  Assert.AreEqual('UnitB', mFields[3], 'Name der Unit');
end;

procedure TLspDefinitionNoTargetTests.IdeUnitOnlyIsNoSource;
var
  mFields: TArray<string>;
begin
  FIde.AddUnit(TIndexExtractor.ExtractText(cBplText, TIdeUnits.PathOf('Vendor.Bpl'), nil));
  Attach(nil);
  Open(cMainFile, cUsesBpl);
  Request(TLspDefinition.cDeclarationMethod, cMainFile, cUsesBpl, 'TBplThing;', 1);
  mFields := SingleNoTarget;
  Assert.AreEqual(TLspDefinition.cReasonNoSource, mFields[2], 'Grund');
  Assert.AreEqual('Vendor.Bpl', mFields[3], 'Name der Unit');
end;

procedure TLspDefinitionNoTargetTests.IdeUnitLoadsRealSource;
var
  mInner: ISymbolIndex;
  mAsked: string;
begin
  FIde.AddUnit(TIndexExtractor.ExtractText(cBplText, TIdeUnits.PathOf('Vendor.Bpl'), nil));
  mInner := FInner;
  mAsked := '';
  // Die Quelle liegt in einem Ordner, den das Nachladen kennt (etwa Suchpfad oder Zusatzordner).
  Attach(
    function(const AUnitName: string): Boolean
    begin
      mAsked := mAsked + AUnitName + ';';
      Result := SameText(AUnitName, 'Vendor.Bpl');
      if Result then
      begin
        mInner.AddUnit(TIndexExtractor.ExtractText(cBplText, 'C:\Lib\Vendor.Bpl.pas', nil));
      end;
    end);
  Open(cMainFile, cUsesBpl);
  Request(TLspDefinition.cDeclarationMethod, cMainFile, cUsesBpl, 'TBplThing;', 1);
  Assert.AreEqual(1, FEvents.Count, 'keine Meldung: ' + String.Join(' / ', FEvents.ToArray));
  Assert.AreEqual('response|1', FEvents[0], 'Ziel in der echten Unit');
  Assert.IsTrue(Pos('Vendor.Bpl;', mAsked) > 0, 'echte Quelle nachgeladen: ' + mAsked);
end;

procedure TLspDefinitionNoTargetTests.InactiveDeclarationInUsedUnit;
var
  mFields: TArray<string>;
begin
  FInner.AddUnit(TIndexExtractor.ExtractText(cZweige, 'C:\P\Zweige.pas', TArray<string>.Create('MSWINDOWS')));
  Attach(nil);
  Open(cMainFile, cUsesZweige);
  Request(TLspDefinition.cDefinitionMethod, cMainFile, cUsesZweige, 'Weg;', 1);
  mFields := SingleNoTarget;
  Assert.AreEqual(TLspDefinition.cDefinitionMethod, mFields[1], 'Methode');
  Assert.AreEqual(TLspDefinition.cReasonInactiveBranch, mFields[2], 'Grund');
  Assert.AreEqual('Weg', mFields[3], 'Bezeichner');
end;

procedure TLspDefinitionNoTargetTests.FoundTargetSendsNothing;
begin
  FInner.AddUnit(TIndexExtractor.ExtractText(cUnitB, cUnitBFile, nil));
  Attach(nil);
  Open(cMainFile, cUsesB);
  Request(TLspDefinition.cDefinitionMethod, cMainFile, cUsesB, 'TQType', 1);
  Assert.AreEqual(1, FEvents.Count, 'keine Meldung: ' + String.Join(' / ', FEvents.ToArray));
  Assert.AreEqual('response|1', FEvents[0], 'ein Ziel');
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDefinitionNoTargetTests);

end.
