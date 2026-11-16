unit dpcc.Windows.Diagnostics.Adapters.DebugOutputSink;

// Log-Senke für dpcc.Common.Logging: schreibt jeden Eintrag über
// OutputDebugString, sichtbar im Debugger oder in DebugView.

interface

uses
  dpcc.Common.Logging.Contract;

type
  TDebugOutputLogSink = class(TInterfacedObject, ILogSink)
  public
    { ILogSink }
    procedure Write(const AEntry: TLogEntry);
  end;

implementation

uses
  dpcc.Windows.Diagnostics.DebugOutput,
  dpcc.Common.Logging.EntryText;

{ TDebugOutputLogSink }

procedure TDebugOutputLogSink.Write(const AEntry: TLogEntry);
begin
  TDebugOutput.Write(TLogEntryText.PlainLine(AEntry));
end;

end.
