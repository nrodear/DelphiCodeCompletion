unit dpcc.Text.Product.Version;

// Eine Versionsangabe für Server und Plugin (seit S1: 0.1.0, wie VerInfo in den .dproj der Gruppe dpcc_d13).
// Tools/Set-Version.ps1 schreibt nur hier, Tools/Check-Version.ps1 liest hier;
// dpcc.Common.Product.Version und dpcc.Core.Product.Version verweisen auf
// diese Konstante.

interface

type
  /// <summary>Version von dpcc (SemVer).</summary>
  TDpccVersion = record
  public const
    cVersion = '0.1.0';
  end;

implementation

end.
