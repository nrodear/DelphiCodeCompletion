unit Shell.Composition.CompletionCapabilities.Tests;

// Capabilities der Wurzel der Completion (Auftrag NAV): Sie folgen aus den angemeldeten Anfragen. Mit
// TLspDefinition am Verteiler meldet der Server definitionProvider, declarationProvider und typeDefinitionProvider;
// vor NAV fehlten sie, und die IDE-Seite fragte bei Strg+Klick gar nicht erst (gegen den alten Stand:
// AttachedDefinitionIsAnnounced schlägt dort fehl, weil TLspDefinition nicht angemeldet war).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellCompletionCapabilitiesTests = class
  public
    [Test]
    procedure DefinitionProvidersFollowRequests;
    [Test]
    procedure WithoutDefinitionNoProviders;
    [Test]
    procedure AttachedDefinitionIsAnnounced;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Documents.Providers.DocumentStore,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Lsp.Hover,
  dpcc.Common.Lsp.Definition,
  Shell.Composition.CompletionCapabilities;

function HasTrue(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue(AName);
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

procedure TShellCompletionCapabilitiesTests.DefinitionProvidersFollowRequests;
var
  mCapabilities: TJSONObject;
begin
  mCapabilities := TShellCompletionCapabilities.Build([TLspHover.cMethod, TLspDefinition.cDefinitionMethod,
    TLspDefinition.cDeclarationMethod, TLspDefinition.cTypeDefinitionMethod], []);
  try
    Assert.IsTrue(HasTrue(mCapabilities, 'hoverProvider'), 'hoverProvider');
    Assert.IsTrue(HasTrue(mCapabilities, 'definitionProvider'), 'definitionProvider');
    Assert.IsTrue(HasTrue(mCapabilities, 'declarationProvider'), 'declarationProvider');
    Assert.IsTrue(HasTrue(mCapabilities, 'typeDefinitionProvider'), 'typeDefinitionProvider');
    // Weiter nicht gemeldet.
    Assert.IsNull(mCapabilities.GetValue('referencesProvider'), 'referencesProvider');
    Assert.IsNull(mCapabilities.GetValue('executeCommandProvider'), 'executeCommandProvider');
  finally
    mCapabilities.Free;
  end;
end;

procedure TShellCompletionCapabilitiesTests.WithoutDefinitionNoProviders;
var
  mCapabilities: TJSONObject;
begin
  mCapabilities := TShellCompletionCapabilities.Build([TLspHover.cMethod], []);
  try
    Assert.IsNull(mCapabilities.GetValue('definitionProvider'), 'definitionProvider');
    Assert.IsNull(mCapabilities.GetValue('declarationProvider'), 'declarationProvider');
    Assert.IsNull(mCapabilities.GetValue('typeDefinitionProvider'), 'typeDefinitionProvider');
  finally
    mCapabilities.Free;
  end;
end;

procedure TShellCompletionCapabilitiesTests.AttachedDefinitionIsAnnounced;
var
  mDispatcher: TJsonRpcDispatcher;
  mDefinition: TLspDefinition;
  mIndex: ISymbolIndex;
  mStore: IDocumentStore;
  mCapabilities: TJSONObject;
begin
  mIndex := TSymbolIndex.Create;
  mStore := TDocumentStore.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  mDefinition := TLspDefinition.Create(mStore, mIndex);
  try
    mDefinition.Attach(mDispatcher);
    mCapabilities := TShellCompletionCapabilities.Build(mDispatcher.Methods, []);
    try
      Assert.IsTrue(HasTrue(mCapabilities, 'definitionProvider'), 'definitionProvider');
      Assert.IsTrue(HasTrue(mCapabilities, 'declarationProvider'), 'declarationProvider');
      Assert.IsTrue(HasTrue(mCapabilities, 'typeDefinitionProvider'), 'typeDefinitionProvider');
    finally
      mCapabilities.Free;
    end;
  finally
    mDefinition.Free;
    mDispatcher.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCompletionCapabilitiesTests);

end.
