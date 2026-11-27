program dpcc.LspServer;

{$APPTYPE CONSOLE}

// dpcc als eigenständiger Language Server über stdin/stdout (Stufe 1): derselbe Completion-Server wie im Plugin
// (Shell.Composition.CompletionServer), dazu der Dialekt der RAD-Studio-IDE, documentSymbol und das Lesen der
// Projektdaten aus workspace/didChangeConfiguration. Die IDE kann ihn an Stelle von DelphiLSP.exe starten. Alle Units
// sind statisch gelinkt (keine Laufzeit-Packages); gebaut für Win32 und Win64.
// Beschreibung: docs\de\lsp-server.md.

// 8 MB Stapel je Thread statt 1 MB (#1094): Parser und Namensauflösung begrenzen ihre Tiefe selbst, das ist das
// Netz darunter. Belegt wird nur, was ein Thread wirklich braucht.
{$MAXSTACKSIZE $00800000}
// 4 GB Adressraum unter Win32 wie bds.exe (LARGEADDRESSAWARE).
{$SETPEFLAGS $20}

uses
  Shell.LspServer.Main in 'Source\LspServer\Shell.LspServer.Main.pas',
  Shell.LspServer.Options in 'Source\LspServer\Shell.LspServer.Options.pas',
  Shell.LspServer.FileLog in 'Source\LspServer\Shell.LspServer.FileLog.pas',
  Shell.LspServer.StdStreams in 'Source\LspServer\Shell.LspServer.StdStreams.pas',
  Shell.LspServer.Host in 'Source\LspServer\Shell.LspServer.Host.pas',
  Shell.LspServer.RadStudio.Dialect in 'Source\LspServer\Shell.LspServer.RadStudio.Dialect.pas',
  Shell.LspServer.RadStudio.Settings in 'Source\LspServer\Shell.LspServer.RadStudio.Settings.pas',
  Shell.LspServer.DocumentSymbols in 'Source\LspServer\Shell.LspServer.DocumentSymbols.pas';

begin
  ExitCode := TLspServerMain.Run;
end.
