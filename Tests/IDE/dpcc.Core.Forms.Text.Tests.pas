unit dpcc.Core.Forms.Text.Tests;

// Formulardatei eines offenen Designers (TDpccFormText.FormFileOf): aus den Moduldateien des Designers
// (IDesigner.ModuleFileNames), nie über den Namen der Wurzel. Mehrere Formulare "Form1" in einer Projektgruppe
// schickten sonst den Text von Formular A als .dfm von B an den Server.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccFormFileTests = class
  public
    /// <summary>Nennt der Designer eine .dfm bzw. .fmx, gilt sie, gleich welcher Unit-Name daneben steht.</summary>
    [Test]
    procedure FormFileOfDesignerWins;
    /// <summary>Ohne Formulardatei: neben der Unit die .dfm, die .fmx nur, wenn es nur diese gibt.</summary>
    [Test]
    procedure DerivedFromUnitFile;
    /// <summary>Ohne beides keine Datei: Das Formular geht nicht an den Server.</summary>
    [Test]
    procedure UnknownWithoutFiles;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Forms.Text;

/// <summary>Prüfung auf vorhandene Dateien: nur die aus AFiles (ohne Groß-/Kleinschreibung).</summary>
function ExistsIn(const AFiles: TArray<string>): TFunc<string, Boolean>;
var
  mFiles: TArray<string>;
begin
  mFiles := AFiles;
  Result :=
    function(AFileName: string): Boolean
    var
      mFile: string;
    begin
      Result := False;
      for mFile in mFiles do
      begin
        if SameText(mFile, AFileName) then
        begin
          Exit(True);
        end;
      end;
    end;
end;

procedure TDpccFormFileTests.FormFileOfDesignerWins;
begin
  // Zwei Projekte mit je einem Form1: Jeder Designer nennt seine eigene Datei.
  Assert.AreEqual('C:\P1\Unit1.dfm', TDpccFormText.FormFileOf('C:\P1\Unit1.pas', 'C:\P1\Unit1.dfm', nil));
  Assert.AreEqual('C:\P2\Unit1.dfm', TDpccFormText.FormFileOf('C:\P2\Unit1.pas', 'C:\P2\Unit1.dfm', nil));
  Assert.AreEqual('C:\P\Haupt.fmx', TDpccFormText.FormFileOf('C:\P\Haupt.pas', 'C:\P\Haupt.fmx',
    ExistsIn(['C:\P\Haupt.dfm'])));
end;

procedure TDpccFormFileTests.DerivedFromUnitFile;
begin
  Assert.AreEqual('C:\P\Haupt.dfm', TDpccFormText.FormFileOf('C:\P\Haupt.pas', '', nil));
  Assert.AreEqual('C:\P\Haupt.dfm', TDpccFormText.FormFileOf('C:\P\Haupt.pas', 'C:\P\Haupt.h',
    ExistsIn(['C:\P\Haupt.dfm', 'C:\P\Haupt.fmx'])));
  Assert.AreEqual('C:\P\Haupt.fmx', TDpccFormText.FormFileOf('C:\P\Haupt.pas', '', ExistsIn(['C:\P\Haupt.fmx'])));
end;

procedure TDpccFormFileTests.UnknownWithoutFiles;
begin
  Assert.AreEqual('', TDpccFormText.FormFileOf('', '', nil));
  Assert.AreEqual('', TDpccFormText.FormFileOf('', 'C:\P\Haupt.h', ExistsIn(['C:\P\Haupt.dfm'])));
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccFormFileTests);

end.
