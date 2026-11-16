unit dpcc.UI.Completion.Strings.Tests;

// Texte des Features Vervollständigung: jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccCompletionStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguages;
    [Test]
    procedure FollowsLanguageOfBase;
  end;

implementation

uses
  dpcc.UI.Strings,
  dpcc.UI.Strings.Tests,
  dpcc.UI.Completion.Strings;

procedure TDpccCompletionStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TDpccCompletionTextId;
  mGerman: string;
  mCount: Integer;
  mSaved: TDpccLanguage;
begin
  mSaved := TDpccStrings.Language;
  mCount := 0;
  try
    for mId := Low(TDpccCompletionTextId) to High(TDpccCompletionTextId) do
    begin
      TDpccStrings.Language := TDpccLanguage.German;
      mGerman := TDpccCompletionStrings.Text(mId);
      TDpccStrings.Language := TDpccLanguage.English;
      AssertTextPair(mGerman, TDpccCompletionStrings.Text(mId), Ord(mId));
      Inc(mCount);
    end;
  finally
    TDpccStrings.Language := mSaved;
  end;
  Assert.AreEqual(Ord(High(TDpccCompletionTextId)) + 1, mCount, 'jede Id geprüft');
end;

procedure TDpccCompletionStringsTests.FollowsLanguageOfBase;
var
  mId: TDpccCompletionTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TDpccLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Features.
  mSaved := TDpccStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TDpccCompletionTextId) to High(TDpccCompletionTextId) do
    begin
      TDpccStrings.Language := TDpccLanguage.German;
      mGerman := TDpccCompletionStrings.Text(mId);
      TDpccStrings.Language := TDpccLanguage.English;
      if mGerman <> TDpccCompletionStrings.Text(mId) then
      begin
        Inc(mDiffers);
      end;
    end;
  finally
    TDpccStrings.Language := mSaved;
  end;
  Assert.IsTrue(mDiffers > 0, 'kein Text folgt der Sprache von Base');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccCompletionStringsTests);

end.
