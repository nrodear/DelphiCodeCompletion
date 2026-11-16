program dpcc.Completion.Tests;

// Sicherheitsnetz fuer den Completion-Schnitt (docs\Konzept-Completion-Schnitt.md, Abschnitt 5 und Schritt 1):
// Completion-, Hover- und Signaturhilfe-Tests (Server- und IDE-Seite, ohne ToolsAPI).

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  // Muss als erste Unit stehen: zählt den Speicherrest beim Beenden (#177).
  dpcc.Common.Diagnostics.ShutdownLeaks,
  System.SysUtils,
  System.IOUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  {$ENDIF}
  DUnitX.TestFramework,
  dpcc.Common.Lsp.Completion.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Tests.pas',
  dpcc.Common.Lsp.Completion.TestSupport in 'Common\Lsp\dpcc.Common.Lsp.Completion.TestSupport.pas',
  dpcc.Common.Lsp.Completion.Proposals.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Proposals.Tests.pas',
  dpcc.Common.Lsp.Completion.Handle.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Handle.Tests.pas',
  dpcc.Common.Lsp.Completion.Contexts.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Contexts.Tests.pas',
  dpcc.Common.Lsp.CompletionEnums.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionEnums.Tests.pas',
  dpcc.Common.Lsp.CompletionGenerics.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionGenerics.Tests.pas',
  dpcc.Common.Lsp.CompletionAttributes.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionAttributes.Tests.pas',
  dpcc.Common.Lsp.CompletionAnonymous.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionAnonymous.Tests.pas',
  dpcc.Common.Lsp.CompletionWith.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionWith.Tests.pas',
  dpcc.Common.Lsp.CompletionExceptions.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionExceptions.Tests.pas',
  dpcc.Common.Lsp.CompletionSyntax.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionSyntax.Tests.pas',
  dpcc.Common.Lsp.CompletionUses.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionUses.Tests.pas',
  dpcc.Common.Lsp.CompletionInherited.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionInherited.Tests.pas',
  dpcc.Common.Lsp.CompletionSameNames.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionSameNames.Tests.pas',
  dpcc.Common.Lsp.CompletionRequest.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionRequest.Tests.pas',
  dpcc.Common.Lsp.CompletionCollector.Tests in 'Common\Lsp\dpcc.Common.Lsp.CompletionCollector.Tests.pas',
  dpcc.Common.Lsp.Internals.CompletionSource.Tests in 'Common\Lsp\dpcc.Common.Lsp.Internals.CompletionSource.Tests.pas',
  dpcc.Common.Lsp.SignatureHelp.Tests in 'Common\Lsp\dpcc.Common.Lsp.SignatureHelp.Tests.pas',
  dpcc.Common.Lsp.Hover.Tests in 'Common\Lsp\dpcc.Common.Lsp.Hover.Tests.pas',
  dpcc.Common.Lsp.Hover.Parts.Tests in 'Common\Lsp\dpcc.Common.Lsp.Hover.Parts.Tests.pas',
  dpcc.Common.Lsp.Hover.UnitContents.Tests in 'Common\Lsp\dpcc.Common.Lsp.Hover.UnitContents.Tests.pas',
  dpcc.Common.Lsp.HoverTypes.Tests in 'Common\Lsp\dpcc.Common.Lsp.HoverTypes.Tests.pas',
  dpcc.Common.Lsp.HoverValues.Tests in 'Common\Lsp\dpcc.Common.Lsp.HoverValues.Tests.pas',
  dpcc.Tests.LeakMonitor in 'Support\dpcc.Tests.LeakMonitor.pas',
  dpcc.Core.Localization.Language in '..\Packages\dpcc.IDE.Base\Source\Core\Localization\dpcc.Core.Localization.Language.pas',
  dpcc.Core.Lsp.Client in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.Client.pas',
  dpcc.Core.Lsp.Contract in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.Contract.pas',
  dpcc.Core.Lsp.Session.Json in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.Session.Json.pas',
  dpcc.Core.Lsp.Session.Base in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.Session.Base.pas',
  dpcc.Core.Lsp.Session.Requests in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.Session.Requests.pas',
  dpcc.Core.Lsp.Session in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.Session.pas',
  dpcc.Core.Lsp.TextChanges in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.TextChanges.pas',
  dpcc.Core.Lsp.Uris in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.Uris.pas',
  dpcc.Core.Lsp.WorkspaceEdits in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.WorkspaceEdits.pas',
  dpcc.Core.Lsp.Adapters.InProcess in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.Adapters.InProcess.pas',
  dpcc.Core.Lsp.Adapters.InProcess.Tests in 'IDE\dpcc.Core.Lsp.Adapters.InProcess.Tests.pas',
  dpcc.Core.Completion.Contract in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Contract.pas',
  dpcc.Core.Completion.Internals.Async in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\Internals\dpcc.Core.Completion.Internals.Async.pas',
  dpcc.Core.Completion.Composite in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Composite.pas',
  dpcc.Core.Completion.Providers.Fixed in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\Providers\dpcc.Core.Completion.Providers.Fixed.pas',
  dpcc.Core.Completion.Providers.Server in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\Providers\dpcc.Core.Completion.Providers.Server.pas',
  dpcc.Core.Completion.Tests in 'IDE\dpcc.Core.Completion.Tests.pas',
  dpcc.Core.Completion.Matching in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Matching.pas',
  dpcc.Core.Completion.Controller in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Controller.pas',
  dpcc.Core.Completion.Controller.Tests in 'IDE\dpcc.Core.Completion.Controller.Tests.pas',
  dpcc.Core.Signature.Contract in '..\Packages\dpcc.IDE.Base\Source\Core\Signature\dpcc.Core.Signature.Contract.pas',
  dpcc.Core.Hover.Contract in '..\Packages\dpcc.IDE.Base\Source\Core\Hover\dpcc.Core.Hover.Contract.pas',
  dpcc.Core.Style.Wrap in '..\Packages\dpcc.IDE.Base\Source\Core\Style\dpcc.Core.Style.Wrap.pas',
  dpcc.Core.Hover.Plain in '..\Packages\dpcc.IDE.Base\Source\Core\Hover\dpcc.Core.Hover.Plain.pas',
  dpcc.Core.Hover.Plain.Tests in 'IDE\dpcc.Core.Hover.Plain.Tests.pas',
  dpcc.Core.Hover.DebugValue in '..\Packages\dpcc.IDE.Base\Source\Core\Hover\dpcc.Core.Hover.DebugValue.pas',
  dpcc.Core.Hover.DebugValue.Tests in 'IDE\dpcc.Core.Hover.DebugValue.Tests.pas',
  dpcc.Core.Hover.Texts in '..\Packages\dpcc.IDE.Base\Source\Core\Hover\dpcc.Core.Hover.Texts.pas',
  dpcc.Core.Hover.Contract.Tests in 'IDE\dpcc.Core.Hover.Contract.Tests.pas',
  dpcc.Core.Documentation.Typeset in '..\Packages\dpcc.IDE.Base\Source\Core\Documentation\dpcc.Core.Documentation.Typeset.pas',
  dpcc.Core.Style.Syntax in '..\Packages\dpcc.IDE.Base\Source\Core\Style\dpcc.Core.Style.Syntax.pas',
  dpcc.Core.Editor.CloseRules in '..\Packages\dpcc.IDE.Base\Source\Core\Editor\dpcc.Core.Editor.CloseRules.pas',
  dpcc.Core.Editor.CloseRules.Tests in 'IDE\dpcc.Core.Editor.CloseRules.Tests.pas',
  dpcc.Core.Documentation.Contract in '..\Packages\dpcc.IDE.Base\Source\Core\Documentation\dpcc.Core.Documentation.Contract.pas',
  dpcc.Core.Documentation.Layout in '..\Packages\dpcc.IDE.Base\Source\Core\Documentation\dpcc.Core.Documentation.Layout.pas',
  dpcc.Core.Signature.Format in '..\Packages\dpcc.IDE.Base\Source\Core\Signature\dpcc.Core.Signature.Format.pas',
  dpcc.Core.Style.Color in '..\Packages\dpcc.IDE.Base\Source\Core\Style\dpcc.Core.Style.Color.pas',
  dpcc.Core.Style.Signal in '..\Packages\dpcc.IDE.Base\Source\Core\Style\dpcc.Core.Style.Signal.pas',
  dpcc.Core.Style.Palette in '..\Packages\dpcc.IDE.Base\Source\Core\Style\dpcc.Core.Style.Palette.pas',
  dpcc.Core.Completion.Presentation in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Presentation.pas',
  dpcc.Core.Completion.Word in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Word.pas',
  dpcc.Core.Settings.OverviewKinds in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.OverviewKinds.pas',
  dpcc.Core.Settings.ContextMenuGroups in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.ContextMenuGroups.pas',
  dpcc.Core.Settings.Plugin in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.pas',
  dpcc.Core.Settings.Plugin.Store in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Store.pas',
  dpcc.Core.Settings.Plugin.Bookmarks in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Bookmarks.pas',
  dpcc.Core.Settings.Plugin.Build in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Build.pas',
  dpcc.Core.Settings.Plugin.CodeActions in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.CodeActions.pas',
  dpcc.Core.Settings.Plugin.Completion in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Completion.pas',
  dpcc.Core.Settings.Plugin.Debug in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Debug.pas',
  dpcc.Core.Settings.Plugin.Editor in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Editor.pas',
  dpcc.Core.Settings.Plugin.General in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.General.pas',
  dpcc.Core.Settings.Plugin.Highlighting in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Highlighting.pas',
  dpcc.Core.Settings.Plugin.Issues in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Issues.pas',
  dpcc.Core.Settings.Plugin.Keys in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Keys.pas',
  dpcc.Core.Settings.Plugin.Rules in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Rules.pas',
  dpcc.Core.Settings.Plugin.VersionControl in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.VersionControl.pas',
  dpcc.Core.Settings.Plugin.Welcome in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Plugin.Welcome.pas',
  dpcc.Core.Settings.JsonText in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.JsonText.pas',
  dpcc.Core.Settings.Scopes in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Scopes.pas',
  dpcc.Core.Settings.SchemaData in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.SchemaData.pas',
  dpcc.Core.Settings.PluginSchemaData in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.PluginSchemaData.pas',
  dpcc.Core.Settings.Catalog in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Catalog.pas',
  dpcc.Core.Settings.Transfer in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Transfer.pas',
  dpcc.Core.Settings.Experimental in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Experimental.pas',
  dpcc.Core.Settings.Groups in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Groups.pas',
  dpcc.Core.Settings.ModuleSwitches in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.ModuleSwitches.pas',
  dpcc.Core.Settings.NodeScope in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.NodeScope.pas',
  dpcc.Core.Settings.Schema in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Schema.pas',
  dpcc.Core.Commands.KeyConflicts in '..\Packages\dpcc.IDE.Base\Source\Core\Commands\dpcc.Core.Commands.KeyConflicts.pas',
  dpcc.Core.Settings.CompletionView in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.CompletionView.pas',
  dpcc.Core.Settings.Search in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Search.pas',
  dpcc.Core.Settings.CompletionView.Tests in 'IDE\dpcc.Core.Settings.CompletionView.Tests.pas',
  dpcc.Core.Settings.MasterSwitch in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.MasterSwitch.pas',
  dpcc.Core.Settings.MasterSwitch.Tests in 'IDE\dpcc.Core.Settings.MasterSwitch.Tests.pas',
  dpcc.Core.Diagnostics.LogRedaction in '..\Packages\dpcc.IDE.Base\Source\Core\Diagnostics\dpcc.Core.Diagnostics.LogRedaction.pas',
  dpcc.Core.Diagnostics.Guard in '..\Packages\dpcc.IDE.Base\Source\Core\Diagnostics\dpcc.Core.Diagnostics.Guard.pas',
  dpcc.Core.Diagnostics.MainThread in '..\Packages\dpcc.IDE.Base\Source\Core\Diagnostics\dpcc.Core.Diagnostics.MainThread.pas',
  dpcc.Core.Diagnostics.Shutdown in '..\Packages\dpcc.IDE.Base\Source\Core\Diagnostics\dpcc.Core.Diagnostics.Shutdown.pas',
  dpcc.Core.Diagnostics.TimeLimit in '..\Packages\dpcc.IDE.Base\Source\Core\Diagnostics\dpcc.Core.Diagnostics.TimeLimit.pas',
  dpcc.Core.Product.Version in '..\Packages\dpcc.IDE.Base\Source\Core\Product\dpcc.Core.Product.Version.pas',
  dpcc.Core.Lsp.Progress in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.Progress.pas',
  dpcc.Core.Lsp.Crashes in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.Crashes.pas',
  dpcc.Core.Settings.SchemaCheck in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.SchemaCheck.pas',
  dpcc.Core.Completion.Ranking in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Ranking.pas',
  dpcc.Core.Completion.Sets in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Sets.pas',
  dpcc.Core.Completion.Sets.Tests in 'IDE\dpcc.Core.Completion.Sets.Tests.pas',
  dpcc.Core.Completion.Width in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Width.pas',
  dpcc.Core.Completion.Width.Tests in 'IDE\dpcc.Core.Completion.Width.Tests.pas',
  dpcc.Core.Completion.Declare.Tests in 'IDE\dpcc.Core.Completion.Declare.Tests.pas',
  dpcc.Core.Completion.Usage in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Usage.pas',
  dpcc.Core.Completion.Ranking.Tests in 'IDE\dpcc.Core.Completion.Ranking.Tests.pas',
  dpcc.Core.Completion.Favorites in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Favorites.pas',
  dpcc.Core.Completion.Favorites.Tests in 'IDE\dpcc.Core.Completion.Favorites.Tests.pas',
  dpcc.UI.Strings in '..\Packages\dpcc.IDE.Base\Source\UI\dpcc.UI.Strings.pas',
  dpcc.UI.Strings.Tests in 'IDE\dpcc.UI.Strings.Tests.pas',
  dpcc.UI.Completion.Strings in '..\Packages\dpcc.IDE.Base\Source\UI\Completion\dpcc.UI.Completion.Strings.pas',
  dpcc.UI.Completion.Strings.Tests in 'IDE\dpcc.UI.Completion.Strings.Tests.pas',
  dpcc.Core.Completion.Providers.XmlDoc in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\Providers\dpcc.Core.Completion.Providers.XmlDoc.pas',
  dpcc.Core.Completion.Placeholders in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Placeholders.pas',
  dpcc.Core.Completion.Placeholders.Tests in 'IDE\dpcc.Core.Completion.Placeholders.Tests.pas',
  dpcc.Core.Completion.ServerPlaceholders in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.ServerPlaceholders.pas',
  dpcc.Core.Completion.ServerPlaceholders.Tests in 'IDE\dpcc.Core.Completion.ServerPlaceholders.Tests.pas',
  dpcc.Core.Generate.Contract in '..\Packages\dpcc.IDE.Base\Source\Core\Generate\dpcc.Core.Generate.Contract.pas',
  dpcc.Core.Completion.Parentheses in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Parentheses.pas',
  dpcc.Core.Completion.Parentheses.Tests in 'IDE\dpcc.Core.Completion.Parentheses.Tests.pas',
  dpcc.Core.Completion.Preview in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\dpcc.Core.Completion.Preview.pas',
  dpcc.Core.Build.Events in '..\Packages\dpcc.IDE.Base\Source\Core\Build\dpcc.Core.Build.Events.pas',
  dpcc.Core.Files.WatchedChanges in '..\Packages\dpcc.IDE.Base\Source\Core\Files\dpcc.Core.Files.WatchedChanges.pas',
  dpcc.Core.Files.Contract in '..\Packages\dpcc.IDE.Base\Source\Core\Files\dpcc.Core.Files.Contract.pas',
  dpcc.Core.Files.TextFile in '..\Packages\dpcc.IDE.Base\Source\Core\Files\dpcc.Core.Files.TextFile.pas',
  dpcc.Core.Files.DataFile in '..\Packages\dpcc.IDE.Base\Source\Core\Files\dpcc.Core.Files.DataFile.pas',
  dpcc.Core.Projects.Contract in '..\Packages\dpcc.IDE.Base\Source\Core\Projects\dpcc.Core.Projects.Contract.pas',
  dpcc.Core.InlayHints.Store in '..\Packages\dpcc.IDE.Base\Source\Core\InlayHints\dpcc.Core.InlayHints.Store.pas',
  dpcc.Core.Status.Contract in '..\Packages\dpcc.IDE.Base\Source\Core\Status\dpcc.Core.Status.Contract.pas',
  dpcc.Core.Build.PipelineSettings in '..\Packages\dpcc.IDE.Base\Source\Core\Build\dpcc.Core.Build.PipelineSettings.pas',
  dpcc.Core.Notifications.Contract in '..\Packages\dpcc.IDE.Base\Source\Core\Notifications\dpcc.Core.Notifications.Contract.pas',
  dpcc.Core.Notifications.Sources in '..\Packages\dpcc.IDE.Base\Source\Core\Notifications\dpcc.Core.Notifications.Sources.pas',
  dpcc.Core.Settings.History in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.History.pas',
  dpcc.Core.Settings.Renames in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Renames.pas',
  dpcc.Core.Settings.QueryMigration in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.QueryMigration.pas',
  dpcc.Core.Diagnostics.Timing in '..\Packages\dpcc.IDE.Base\Source\Core\Diagnostics\dpcc.Core.Diagnostics.Timing.pas',
  dpcc.Core.Diagnostics.PluginTimings in '..\Packages\dpcc.IDE.Base\Source\Core\Diagnostics\dpcc.Core.Diagnostics.PluginTimings.pas',
  dpcc.Core.Settings.Reassigned in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.Reassigned.pas',
  dpcc.Core.Settings.ProblemsUpdate in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.ProblemsUpdate.pas',
  dpcc.Core.Editor.StatementCompletion in '..\Packages\dpcc.IDE.Base\Source\Core\Editor\dpcc.Core.Editor.StatementCompletion.pas',
  dpcc.Core.Editor.StatementCompletion.Tests in 'IDE\dpcc.Core.Editor.StatementCompletion.Tests.pas',
  dpcc.Core.Build.Messages in '..\Packages\dpcc.IDE.Base\Source\Core\Build\dpcc.Core.Build.Messages.pas',
  dpcc.Core.Build.Verdict in '..\Packages\dpcc.IDE.Base\Source\Core\Build\dpcc.Core.Build.Verdict.pas',
  dpcc.Core.Build.OpenBuildSettings in '..\Packages\dpcc.IDE.Base\Source\Core\Build\dpcc.Core.Build.OpenBuildSettings.pas',
  dpcc.Core.Settings.ToolbarItems in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.ToolbarItems.pas',
  dpcc.Core.Settings.StatusBarItems in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.StatusBarItems.pas',
  Shell.Composition.Completion.Tests in 'Application\Shell\Shell.Composition.Completion.Tests.pas',
  Shell.Composition.InProcess.Tests in 'Application\Shell\Shell.Composition.InProcess.Tests.pas',
  dpcc.Common.Lsp.Completion.Postfix.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Postfix.Tests.pas',
  dpcc.Common.Lsp.Completion.Names.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Names.Tests.pas',
  dpcc.Common.Lsp.Completion.Hooks.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Hooks.Tests.pas',
  dpcc.Common.Lsp.Completion.InheritedCalls.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.InheritedCalls.Tests.pas',
  dpcc.Common.Lsp.ExpressionCompletion.Tests in 'Common\Lsp\dpcc.Common.Lsp.ExpressionCompletion.Tests.pas',
  dpcc.Core.Completion.Providers.Expression in '..\Packages\dpcc.IDE.Base\Source\Core\Completion\Providers\dpcc.Core.Completion.Providers.Expression.pas',
  dpcc.Core.Completion.Providers.Expression.Tests in 'IDE\dpcc.Core.Completion.Providers.Expression.Tests.pas',
  dpcc.Core.Lsp.DataFlow in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.DataFlow.pas',
  dpcc.Core.Lsp.AccessChains in '..\Packages\dpcc.IDE.Base\Source\Core\Lsp\dpcc.Core.Lsp.AccessChains.pas',
  dpcc.Core.Settings.VisualizerKinds in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.VisualizerKinds.pas',
  dpcc.Core.Settings.EventBreakNames in '..\Packages\dpcc.IDE.Base\Source\Core\Settings\dpcc.Core.Settings.EventBreakNames.pas',
  dpcc.Core.Lsp.Client.MethodNotFound.Tests in 'IDE\dpcc.Core.Lsp.Client.MethodNotFound.Tests.pas';

// Speicherrest beim Beenden in den Testbericht (Konsole) statt in einen Dialog (#177).
procedure ReportShutdownLeak(ABytes: Int64);
begin
  System.Writeln(TShutdownLeaks.Describe(ABytes));
end;

{$IFNDEF TESTINSIGHT}
var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
  NUnitLogger: ITestLogger;
{$ENDIF}
begin
  {$IFDEF DEBUG}
  TShutdownLeaks.Enable(ReportShutdownLeak);
  {$ENDIF}
  // Protokoll der Absturzsicherung in einen eigenen Ordner: Die Tests lösen absichtlich Fehler aus („Fehler in
  // Quelle Testquelle“), die sonst im dpcc.log der installierten dpcc-Version landen und bei der Fehlersuche wie
  // echte Fehler aussehen.
  TDpccGuard.RotatingLog.Folder := TPath.Combine(TPath.GetTempPath, 'dpccCompletionTests' + PathDelim + 'Logs');
  RegisterLeakMonitor;
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
{$ELSE}
  try
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := False;

    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      Logger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      Runner.AddLogger(Logger);
    end;
    NUnitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    Runner.AddLogger(NUnitLogger);

    Results := Runner.Execute;
    // Ein Speicherleck zählt als Fehlschlag.
    if (not Results.AllPassed) or (Results.MemoryLeakCount > 0) then
    begin
      System.ExitCode := EXIT_ERRORS;
    end;

    {$IFNDEF CI}
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Fertig. <Enter> zum Beenden drücken.');
      System.Readln;
    end;
    {$ENDIF}
  except
    on E: Exception do
    begin
      System.Writeln(E.ClassName, ': ', E.Message);
      System.ExitCode := EXIT_ERRORS;
    end;
  end;
{$ENDIF}
end.
