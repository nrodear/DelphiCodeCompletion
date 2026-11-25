program dpcc.Completion.Tests;

// Sicherheitsnetz fuer den Completion-Schnitt (docs\Konzept-Completion-Schnitt.md, Abschnitt 5 und Schritt 1):
// Completion-, Hover- und Signaturhilfe-Tests (Server- und IDE-Seite, ohne ToolsAPI).

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}
// 4 GB Adressraum wie bds.exe (LARGEADDRESSAWARE): Das Messprogramm (dpcc.Memory.Bench.Tests) misst sonst gegen eine
// Grenze von 2 GB, die es in der IDE nicht gibt.
{$SETPEFLAGS $20}

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
  dpcc.Common.Lsp.Definition.Tests in 'Common\Lsp\dpcc.Common.Lsp.Definition.Tests.pas',
  dpcc.Common.Lsp.Definition.NoTarget.Tests in 'Common\Lsp\dpcc.Common.Lsp.Definition.NoTarget.Tests.pas',
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
  dpcc.Common.Index.Extractor.Tests in 'Common\Index\dpcc.Common.Index.Extractor.Tests.pas',
  dpcc.Common.Index.Extractor.Tokens.Tests in 'Common\Index\dpcc.Common.Index.Extractor.Tokens.Tests.pas',
  dpcc.Common.Index.Extractor.TypeText.Tests in 'Common\Index\dpcc.Common.Index.Extractor.TypeText.Tests.pas',
  dpcc.Common.Index.Extractor.Conditions.Tests in 'Common\Index\dpcc.Common.Index.Extractor.Conditions.Tests.pas',
  dpcc.Common.Index.Content.Tests in 'Common\Index\dpcc.Common.Index.Content.Tests.pas',
  dpcc.Common.Pascal.Parser.Tests in 'Common\Pascal\dpcc.Common.Pascal.Parser.Tests.pas',
  dpcc.Common.Pascal.Preprocessor.Tests in 'Common\Pascal\dpcc.Common.Pascal.Preprocessor.Tests.pas',
  dpcc.Common.Semantics.NameResolver.Tests in 'Common\Semantics\dpcc.Common.Semantics.NameResolver.Tests.pas',
  dpcc.Common.Semantics.NameResolver.Parts.Tests in 'Common\Semantics\dpcc.Common.Semantics.NameResolver.Parts.Tests.pas',
  dpcc.Common.Semantics.NameResolver.LanguageFeatures.Tests in 'Common\Semantics\dpcc.Common.Semantics.NameResolver.LanguageFeatures.Tests.pas',
  dpcc.Common.Lsp.Completion.Members.L3.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Members.L3.Tests.pas',
  dpcc.Common.Lsp.Completion.L3.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.L3.Tests.pas',
  dpcc.Common.Index.IncludeOwners.Tests in 'Common\Index\dpcc.Common.Index.IncludeOwners.Tests.pas',
  dpcc.Common.Lsp.Hover.L3.Tests in 'Common\Lsp\dpcc.Common.Lsp.Hover.L3.Tests.pas',
  dpcc.Common.Lsp.SignatureHelp.L3.Tests in 'Common\Lsp\dpcc.Common.Lsp.SignatureHelp.L3.Tests.pas',
  dpcc.Core.Signature.CallScanner in '..\Packages\dpcc.Core\Source\Signature\dpcc.Core.Signature.CallScanner.pas',
  dpcc.Core.Signature.CallScanner.Tests in 'IDE\dpcc.Core.Signature.CallScanner.Tests.pas',
  dpcc.Tests.LeakMonitor in 'Support\dpcc.Tests.LeakMonitor.pas',
  dpcc.Core.Localization.Language in '..\Packages\dpcc.Core\Source\Localization\dpcc.Core.Localization.Language.pas',
  dpcc.Core.Lsp.Client in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.Client.pas',
  dpcc.Core.Lsp.Contract in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.Contract.pas',
  dpcc.Core.Lsp.Session.Json in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.Session.Json.pas',
  dpcc.Core.Lsp.Session.Base in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.Session.Base.pas',
  dpcc.Core.Lsp.Session.Requests in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.Session.Requests.pas',
  dpcc.Core.Lsp.Session in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.Session.pas',
  dpcc.Core.Lsp.TextChanges in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.TextChanges.pas',
  dpcc.Core.Lsp.Uris in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.Uris.pas',
  dpcc.Core.Lsp.WorkspaceEdits in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.WorkspaceEdits.pas',
  dpcc.Core.Lsp.Adapters.InProcess in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.Adapters.InProcess.pas',
  dpcc.Core.Lsp.Adapters.InProcess.Tests in 'IDE\dpcc.Core.Lsp.Adapters.InProcess.Tests.pas',
  dpcc.Core.Lsp.GotoBothWays.Tests in 'IDE\dpcc.Core.Lsp.GotoBothWays.Tests.pas',
  dpcc.Core.Completion.Contract in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Contract.pas',
  dpcc.Core.Completion.Internals.Async in '..\Packages\dpcc.Core\Source\Completion\Internals\dpcc.Core.Completion.Internals.Async.pas',
  dpcc.Core.Completion.Composite in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Composite.pas',
  dpcc.Core.Completion.Providers.Fixed in 'Support\dpcc.Core.Completion.Providers.Fixed.pas',
  dpcc.Core.Completion.Providers.Server in '..\Packages\dpcc.Core\Source\Completion\Providers\dpcc.Core.Completion.Providers.Server.pas',
  dpcc.Core.Completion.Tests in 'IDE\dpcc.Core.Completion.Tests.pas',
  dpcc.Core.Completion.Matching in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Matching.pas',
  dpcc.Core.Completion.Controller in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Controller.pas',
  dpcc.Core.Completion.Controller.Tests in 'IDE\dpcc.Core.Completion.Controller.Tests.pas',
  dpcc.Core.Completion.Fallback in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Fallback.pas',
  dpcc.Core.Completion.Fallback.Tests in 'IDE\dpcc.Core.Completion.Fallback.Tests.pas',
  dpcc.Core.Completion.AutoOpen in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.AutoOpen.pas',
  dpcc.Core.Completion.AutoOpen.Tests in 'IDE\dpcc.Core.Completion.AutoOpen.Tests.pas',
  dpcc.Core.Signature.Contract in '..\Packages\dpcc.Core\Source\Signature\dpcc.Core.Signature.Contract.pas',
  dpcc.Core.Hover.Contract in '..\Packages\dpcc.Core\Source\Hover\dpcc.Core.Hover.Contract.pas',
  dpcc.Core.Style.Wrap in '..\Packages\dpcc.Core\Source\Style\dpcc.Core.Style.Wrap.pas',
  dpcc.Core.Hover.Plain in '..\Packages\dpcc.Core\Source\Hover\dpcc.Core.Hover.Plain.pas',
  dpcc.Core.Hover.Plain.Tests in 'IDE\dpcc.Core.Hover.Plain.Tests.pas',
  dpcc.Core.Hover.DebugValue in '..\Packages\dpcc.Core\Source\Hover\dpcc.Core.Hover.DebugValue.pas',
  dpcc.Core.Hover.DebugValue.Tests in 'IDE\dpcc.Core.Hover.DebugValue.Tests.pas',
  dpcc.Core.Hover.Texts in '..\Packages\dpcc.Core\Source\Hover\dpcc.Core.Hover.Texts.pas',
  dpcc.Core.Hover.Contract.Tests in 'IDE\dpcc.Core.Hover.Contract.Tests.pas',
  dpcc.Core.Style.Look.Tests in 'IDE\dpcc.Core.Style.Look.Tests.pas',
  dpcc.Core.Hover.Look.Tests in 'IDE\dpcc.Core.Hover.Look.Tests.pas',
  dpcc.Core.Documentation.Typeset in '..\Packages\dpcc.Core\Source\Documentation\dpcc.Core.Documentation.Typeset.pas',
  dpcc.Core.Style.Syntax in '..\Packages\dpcc.Core\Source\Style\dpcc.Core.Style.Syntax.pas',
  dpcc.Core.Editor.CloseRules in '..\Packages\dpcc.Core\Source\Editor\dpcc.Core.Editor.CloseRules.pas',
  dpcc.Core.Editor.CloseRules.Tests in 'IDE\dpcc.Core.Editor.CloseRules.Tests.pas',
  dpcc.Core.Editor.Navigation in '..\Packages\dpcc.Core\Source\Editor\dpcc.Core.Editor.Navigation.pas',
  dpcc.Core.Editor.Navigation.Tests in 'IDE\dpcc.Core.Editor.Navigation.Tests.pas',
  dpcc.Core.Editor.TabStops in '..\Packages\dpcc.Core\Source\Editor\dpcc.Core.Editor.TabStops.pas',
  dpcc.Core.Editor.TabStops.Tests in 'IDE\dpcc.Core.Editor.TabStops.Tests.pas',
  dpcc.Core.Editor.Prewarm in '..\Packages\dpcc.Core\Source\Editor\dpcc.Core.Editor.Prewarm.pas',
  dpcc.Core.Editor.Prewarm.Tests in 'IDE\dpcc.Core.Editor.Prewarm.Tests.pas',
  dpcc.Core.Documentation.Contract in '..\Packages\dpcc.Core\Source\Documentation\dpcc.Core.Documentation.Contract.pas',
  dpcc.Core.Documentation.Layout in '..\Packages\dpcc.Core\Source\Documentation\dpcc.Core.Documentation.Layout.pas',
  dpcc.Core.Signature.Format in '..\Packages\dpcc.Core\Source\Signature\dpcc.Core.Signature.Format.pas',
  dpcc.Core.Style.Color in '..\Packages\dpcc.Core\Source\Style\dpcc.Core.Style.Color.pas',
  dpcc.Core.Style.Palette in '..\Packages\dpcc.Core\Source\Style\dpcc.Core.Style.Palette.pas',
  dpcc.Core.Style.Look in '..\Packages\dpcc.Core\Source\Style\dpcc.Core.Style.Look.pas',
  dpcc.Core.Style.Look.Levels.Tests in 'IDE\dpcc.Core.Style.Look.Levels.Tests.pas',
  dpcc.Core.Style.Syntax.Types.Tests in 'IDE\dpcc.Core.Style.Syntax.Types.Tests.pas',
  dpcc.Core.Completion.Presentation in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Presentation.pas',
  dpcc.Core.Completion.Word in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Word.pas',
  dpcc.Core.Settings.Plugin in '..\Packages\dpcc.Core\Source\Settings\dpcc.Core.Settings.Plugin.pas',
  dpcc.Core.Settings.Plugin.Store in '..\Packages\dpcc.Core\Source\Settings\dpcc.Core.Settings.Plugin.Store.pas',
  dpcc.Core.Settings.JsonText in '..\Packages\dpcc.Core\Source\Settings\dpcc.Core.Settings.JsonText.pas',
  dpcc.Core.Settings.Scopes in '..\Packages\dpcc.Core\Source\Settings\dpcc.Core.Settings.Scopes.pas',
  dpcc.Core.Settings.CompletionView in '..\Packages\dpcc.Core\Source\Settings\dpcc.Core.Settings.CompletionView.pas',
  dpcc.Core.Settings.CompletionView.Tests in 'IDE\dpcc.Core.Settings.CompletionView.Tests.pas',
  dpcc.Core.Editor.CodeInsightKeys in '..\Packages\dpcc.Core\Source\Editor\dpcc.Core.Editor.CodeInsightKeys.pas',
  dpcc.Core.Settings.IdeCheck in '..\Packages\dpcc.Core\Source\Settings\dpcc.Core.Settings.IdeCheck.pas',
  dpcc.Core.Settings.IdeCheck.Tests in 'IDE\dpcc.Core.Settings.IdeCheck.Tests.pas',
  dpcc.Core.Editor.HelpInsightRule in '..\Packages\dpcc.Core\Source\Editor\dpcc.Core.Editor.HelpInsightRule.pas',
  dpcc.Core.Editor.HelpInsightRule.Tests in 'IDE\dpcc.Core.Editor.HelpInsightRule.Tests.pas',
  dpcc.Core.Lsp.SessionLifecycle in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.SessionLifecycle.pas',
  dpcc.Core.Lsp.SessionLifecycle.Tests in 'IDE\dpcc.Core.Lsp.SessionLifecycle.Tests.pas',
  dpcc.Core.Lsp.SessionStart in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.SessionStart.pas',
  dpcc.Core.Lsp.SessionStart.Tests in 'IDE\dpcc.Core.Lsp.SessionStart.Tests.pas',
  dpcc.Core.Lsp.LateAnswers in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.LateAnswers.pas',
  dpcc.Core.Lsp.LateAnswers.Tests in 'IDE\dpcc.Core.Lsp.LateAnswers.Tests.pas',
  dpcc.Core.Lsp.IdeSlices in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.IdeSlices.pas',
  dpcc.Core.Lsp.IdeSlices.Tests in 'IDE\dpcc.Core.Lsp.IdeSlices.Tests.pas',
  dpcc.Core.Settings.MasterSwitch in '..\Packages\dpcc.Core\Source\Settings\dpcc.Core.Settings.MasterSwitch.pas',
  dpcc.Core.Settings.MasterSwitch.Tests in 'IDE\dpcc.Core.Settings.MasterSwitch.Tests.pas',
  dpcc.Core.Diagnostics.LogRedaction in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.LogRedaction.pas',
  dpcc.Core.Diagnostics.LogWriter in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.LogWriter.pas',
  dpcc.Core.Diagnostics.Guard in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.Guard.pas',
  dpcc.Core.Diagnostics.MainThread in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.MainThread.pas',
  dpcc.Core.Diagnostics.Shutdown in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.Shutdown.pas',
  dpcc.Core.Diagnostics.TimeLimit in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.TimeLimit.pas',
  dpcc.Core.Diagnostics.PluginModules in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.PluginModules.pas',
  dpcc.Core.Diagnostics.UnloadSafety in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.UnloadSafety.pas',
  dpcc.Core.Diagnostics.WorkerSlot in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.WorkerSlot.pas',
  dpcc.Core.Diagnostics.ThreadList in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.ThreadList.pas',
  dpcc.Core.Product.Version in '..\Packages\dpcc.Core\Source\Product\dpcc.Core.Product.Version.pas',
  dpcc.Core.Lsp.Progress in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.Progress.pas',
  dpcc.Core.Lsp.Crashes in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.Crashes.pas',
  dpcc.Core.Completion.Ranking in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Ranking.pas',
  dpcc.Core.Completion.Sets in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Sets.pas',
  dpcc.Core.Completion.Sets.Tests in 'IDE\dpcc.Core.Completion.Sets.Tests.pas',
  dpcc.Core.Completion.Width in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Width.pas',
  dpcc.Core.Completion.Width.Tests in 'IDE\dpcc.Core.Completion.Width.Tests.pas',
  dpcc.Core.Completion.Declare.Tests in 'IDE\dpcc.Core.Completion.Declare.Tests.pas',
  dpcc.Core.Completion.Usage in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Usage.pas',
  dpcc.Core.Completion.Ranking.Tests in 'IDE\dpcc.Core.Completion.Ranking.Tests.pas',
  dpcc.Core.Completion.Favorites in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Favorites.pas',
  dpcc.Core.Completion.Favorites.Tests in 'IDE\dpcc.Core.Completion.Favorites.Tests.pas',
  dpcc.UI.Strings in '..\Packages\dpcc.UI\Source\dpcc.UI.Strings.pas',
  dpcc.UI.Strings.Tests in 'IDE\dpcc.UI.Strings.Tests.pas',
  dpcc.UI.Completion.Strings in '..\Packages\dpcc.UI\Source\Completion\dpcc.UI.Completion.Strings.pas',
  dpcc.UI.Completion.Strings.Tests in 'IDE\dpcc.UI.Completion.Strings.Tests.pas',
  dpcc.UI.Completion.RowColors in '..\Packages\dpcc.UI\Source\Completion\dpcc.UI.Completion.RowColors.pas',
  dpcc.UI.Completion.RowColors.Tests in 'IDE\dpcc.UI.Completion.RowColors.Tests.pas',
  dpcc.UI.Settings.ChoiceBox in '..\Packages\dpcc.UI\Source\Settings\dpcc.UI.Settings.ChoiceBox.pas',
  dpcc.UI.Settings.Strings in '..\Packages\dpcc.UI\Source\Settings\dpcc.UI.Settings.Strings.pas',
  dpcc.UI.Settings.Page in '..\Packages\dpcc.UI\Source\Settings\dpcc.UI.Settings.Page.pas' {DpccSettingsPage: TFrame},
  dpcc.UI.Settings.Page.Tests in 'IDE\dpcc.UI.Settings.Page.Tests.pas',
  dpcc.Core.Signature.Controller in '..\Packages\dpcc.Core\Source\Signature\dpcc.Core.Signature.Controller.pas',
  dpcc.UI.Foundation.Module in '..\Packages\dpcc.UI\Source\Foundation\dpcc.UI.Foundation.Module.pas',
  dpcc.UI.Popup.Accessibility in '..\Packages\dpcc.UI\Source\Popup\dpcc.UI.Popup.Accessibility.pas',
  dpcc.UI.Popup.Draw in '..\Packages\dpcc.UI\Source\Popup\dpcc.UI.Popup.Draw.pas',
  dpcc.UI.Popup.Window in '..\Packages\dpcc.UI\Source\Popup\dpcc.UI.Popup.Window.pas',
  dpcc.UI.Popup.Tip in '..\Packages\dpcc.UI\Source\Popup\dpcc.UI.Popup.Tip.pas',
  dpcc.UI.Popup.Styled in '..\Packages\dpcc.UI\Source\Popup\dpcc.UI.Popup.Styled.pas',
  dpcc.UI.Completion.PopupTexts in '..\Packages\dpcc.UI\Source\Completion\dpcc.UI.Completion.PopupTexts.pas',
  dpcc.UI.Completion.PopupState in '..\Packages\dpcc.UI\Source\Completion\dpcc.UI.Completion.PopupState.pas',
  dpcc.UI.Completion.PopupLayout in '..\Packages\dpcc.UI\Source\Completion\dpcc.UI.Completion.PopupLayout.pas',
  dpcc.UI.Completion.PopupPainter in '..\Packages\dpcc.UI\Source\Completion\dpcc.UI.Completion.PopupPainter.pas',
  dpcc.UI.Completion.Popup in '..\Packages\dpcc.UI\Source\Completion\dpcc.UI.Completion.Popup.pas',
  dpcc.UI.Documentation.View in '..\Packages\dpcc.UI\Source\Documentation\dpcc.UI.Documentation.View.pas',
  dpcc.UI.Hover.Strings in '..\Packages\dpcc.UI\Source\Hover\dpcc.UI.Hover.Strings.pas',
  dpcc.UI.Hover.Tip in '..\Packages\dpcc.UI\Source\Hover\dpcc.UI.Hover.Tip.pas',
  dpcc.UI.Signature.Hint in '..\Packages\dpcc.UI\Source\Signature\dpcc.UI.Signature.Hint.pas',
  dpcc.UI.Popup.Render.Tests in 'IDE\dpcc.UI.Popup.Render.Tests.pas',
  dpcc.Core.Completion.Providers.XmlDoc in '..\Packages\dpcc.Core\Source\Completion\Providers\dpcc.Core.Completion.Providers.XmlDoc.pas',
  dpcc.Core.Completion.Placeholders in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Placeholders.pas',
  dpcc.Core.Completion.Placeholders.Tests in 'IDE\dpcc.Core.Completion.Placeholders.Tests.pas',
  dpcc.Core.Completion.Parentheses in '..\Packages\dpcc.Core\Source\Completion\dpcc.Core.Completion.Parentheses.pas',
  dpcc.Core.Completion.Parentheses.Tests in 'IDE\dpcc.Core.Completion.Parentheses.Tests.pas',
  dpcc.Core.Diagnostics.PluginModules.Tests in 'IDE\dpcc.Core.Diagnostics.PluginModules.Tests.pas',
  dpcc.Core.Diagnostics.LogWriter.Tests in 'IDE\dpcc.Core.Diagnostics.LogWriter.Tests.pas',
  dpcc.Core.Build.Events in '..\Packages\dpcc.Core\Source\Build\dpcc.Core.Build.Events.pas',
  dpcc.Core.Files.WatchedChanges in '..\Packages\dpcc.Core\Source\Files\dpcc.Core.Files.WatchedChanges.pas',
  dpcc.Core.Files.Contract in '..\Packages\dpcc.Core\Source\Files\dpcc.Core.Files.Contract.pas',
  dpcc.Core.Files.TextFile in '..\Packages\dpcc.Core\Source\Files\dpcc.Core.Files.TextFile.pas',
  dpcc.Core.Files.DataFile in '..\Packages\dpcc.Core\Source\Files\dpcc.Core.Files.DataFile.pas',
  dpcc.Core.Projects.Contract in '..\Packages\dpcc.Core\Source\Projects\dpcc.Core.Projects.Contract.pas',
  dpcc.Core.Projects.ContextGate in '..\Packages\dpcc.Core\Source\Projects\dpcc.Core.Projects.ContextGate.pas',
  dpcc.Core.Projects.ContextGate.Tests in 'IDE\dpcc.Core.Projects.ContextGate.Tests.pas',
  dpcc.Core.Status.Contract in '..\Packages\dpcc.Core\Source\Status\dpcc.Core.Status.Contract.pas',
  dpcc.Core.Notifications.Contract in '..\Packages\dpcc.Core\Source\Notifications\dpcc.Core.Notifications.Contract.pas',
  dpcc.Core.Notifications.Sources in '..\Packages\dpcc.Core\Source\Notifications\dpcc.Core.Notifications.Sources.pas',
  dpcc.Core.Diagnostics.Timing in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.Timing.pas',
  dpcc.Core.Diagnostics.PluginTimings in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.PluginTimings.pas',
  dpcc.Core.Diagnostics.StartTimes in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.StartTimes.pas',
  dpcc.Core.Diagnostics.Hangs in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.Hangs.pas',
  dpcc.Core.Diagnostics.Hangs.Tests in 'IDE\dpcc.Core.Diagnostics.Hangs.Tests.pas',
  dpcc.Core.Diagnostics.Flow in '..\Packages\dpcc.Core\Source\Diagnostics\dpcc.Core.Diagnostics.Flow.pas',
  dpcc.Core.Diagnostics.Flow.Tests in 'IDE\dpcc.Core.Diagnostics.Flow.Tests.pas',
  Shell.Composition.Completion.Tests in 'Application\Shell\Shell.Composition.Completion.Tests.pas',
  Shell.Composition.InProcess.Tests in 'Application\Shell\Shell.Composition.InProcess.Tests.pas',
  Shell.Composition.CompletionCapabilities.Tests in 'Application\Shell\Shell.Composition.CompletionCapabilities.Tests.pas',
  Shell.Composition.PackageJump.Tests in 'Application\Shell\Shell.Composition.PackageJump.Tests.pas',
  Shell.Composition.Prewarm.Tests in 'Application\Shell\Shell.Composition.Prewarm.Tests.pas',
  dpcc.Common.Lsp.Completion.Postfix.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Postfix.Tests.pas',
  dpcc.Common.Lsp.Completion.Names.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Names.Tests.pas',
  dpcc.Common.Lsp.Completion.Hooks.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.Hooks.Tests.pas',
  dpcc.Common.Lsp.Completion.InheritedCalls.Tests in 'Common\Lsp\dpcc.Common.Lsp.Completion.InheritedCalls.Tests.pas',
  dpcc.Common.Lsp.ExpressionCompletion.Tests in 'Common\Lsp\dpcc.Common.Lsp.ExpressionCompletion.Tests.pas',
  dpcc.Core.Lsp.DataFlow in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.DataFlow.pas',
  dpcc.Core.Lsp.AccessChains in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.AccessChains.pas',
  dpcc.Core.Lsp.Client.MethodNotFound.Tests in 'IDE\dpcc.Core.Lsp.Client.MethodNotFound.Tests.pas',
  dpcc.Common.Memory.Tests in 'Common\dpcc.Common.Memory.Tests.pas',
  dpcc.Common.Memory.Phase1.Tests in 'Common\dpcc.Common.Memory.Phase1.Tests.pas',
  dpcc.Common.Memory.Phase2.Tests in 'Common\dpcc.Common.Memory.Phase2.Tests.pas',
  dpcc.Common.Memory.Phase3.Tests in 'Common\dpcc.Common.Memory.Phase3.Tests.pas',
  dpcc.Common.Memory.Phase4.Tests in 'Common\dpcc.Common.Memory.Phase4.Tests.pas',
  dpcc.Common.Memory.Phase5.Tests in 'Common\dpcc.Common.Memory.Phase5.Tests.pas',
  dpcc.Core.Lsp.IdeTypes in '..\Packages\dpcc.Core\Source\Lsp\dpcc.Core.Lsp.IdeTypes.pas',
  dpcc.Common.Sources.Tests in 'Common\dpcc.Common.Sources.Tests.pas',
  dpcc.Core.Forms.Text in '..\Packages\dpcc.Core\Source\Forms\dpcc.Core.Forms.Text.pas',
  dpcc.Core.Forms.Text.Tests in 'IDE\dpcc.Core.Forms.Text.Tests.pas',
  dpcc.Core.Forms.Sync in '..\Packages\dpcc.Core\Source\Forms\dpcc.Core.Forms.Sync.pas',
  dpcc.Core.Forms.Sync.Tests in 'IDE\dpcc.Core.Forms.Sync.Tests.pas',
  dpcc.Memory.Bench.Tests in 'Memory\dpcc.Memory.Bench.Tests.pas';

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
