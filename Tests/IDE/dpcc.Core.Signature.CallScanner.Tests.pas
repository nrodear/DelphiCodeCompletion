unit dpcc.Core.Signature.CallScanner.Tests;

// Tests für den Aufruf am Caret im Parameter-Hint der IDE (dpcc.Core.Signature.CallScanner), Auftrag L3 Punkt 7:
// Typargumente vor der Klammer und Index-Properties, gleich wie die Parameterhilfe des Servers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccCallScannerTests = class
  public
    /// <summary>Foo&lt;Integer&gt;( ist ein Aufruf von Foo; "&lt;&gt;" bleibt der Operator.</summary>
    [Test]
    procedure TypeArgumentsBeforeParenthesis;
    /// <summary>Liste[ ohne offenen Aufruf; in Foo(Liste[ bleibt es bei Foo; array[ ist keiner.</summary>
    [Test]
    procedure IndexPropertyWithoutCall;
  end;

implementation

uses
  dpcc.Core.Signature.CallScanner;

function ScanEnd(const AText: string): TDpccCallSite;
begin
  Result := TDpccCallScanner.Scan(AText, Length(AText));
end;

procedure TDpccCallScannerTests.TypeArgumentsBeforeParenthesis;
var
  Site: TDpccCallSite;
begin
  Site := ScanEnd('  Foo(1, Bar<Integer>(2, ');
  Assert.IsTrue(Site.Found);
  Assert.AreEqual('Bar', Site.Name);
  Assert.AreEqual(1, Site.ActiveParameter);
  Assert.AreEqual(1, Integer(Length(Site.Outer)));
  Assert.AreEqual('Foo', Site.Outer[0]);
  Site := ScanEnd('  X := Liste.Wandle<TList<string>, Integer>(');
  Assert.IsTrue(Site.Found);
  Assert.AreEqual('Wandle', Site.Name);
  Assert.IsFalse(ScanEnd('  if A <> (B').Found, 'ungleich');
  Assert.IsFalse(ScanEnd('  if A > (B').Found, 'größer');
end;

procedure TDpccCallScannerTests.IndexPropertyWithoutCall;
var
  Site: TDpccCallSite;
begin
  Site := ScanEnd('  X := Liste[1, ');
  Assert.IsTrue(Site.Found);
  Assert.AreEqual('Liste', Site.Name);
  Assert.AreEqual(1, Site.ActiveParameter);
  Assert.AreEqual(Pos('[', '  X := Liste[1, ') - 1, Site.OpenParen);
  Site := ScanEnd('  Foo(Liste[1, ');
  Assert.AreEqual('Foo', Site.Name);
  Assert.AreEqual(0, Site.ActiveParameter);
  Assert.IsFalse(ScanEnd('  A: array[0..').Found);
  Assert.IsFalse(ScanEnd('  S: string[').Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccCallScannerTests);

end.
