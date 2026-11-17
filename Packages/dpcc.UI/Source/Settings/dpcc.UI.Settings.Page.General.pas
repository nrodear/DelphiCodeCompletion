unit dpcc.UI.Settings.Page.General;

// Reiter „Allgemein“: Hauptschalter, „Index neu aufbauen“, „Zusätzliche Quellordner“ (index.extraSourceFolders, L2;
// ersetzt den Schalter „Office-Typbibliotheken und WinRT vorab indizieren“, index.officeAndWinRt) und der
// Hauptschalter der experimentellen Funktionen. Den
// Teil „Benachrichtigungen“ gibt es seit S7a nicht mehr (es gibt keine Benachrichtigungszentrale); Statusfeld,
// Diagnosemodus, Tastenkürzel-Tipps, „Extern geänderte Dateien neu laden“ und „Änderungen an nicht geöffneten
// Dateien“ seit S8 (sie waren versteckt und wirkten nicht).
// „Index neu aufbauen“ (S4, statt der Seite „Index“): Rückfrage, dann leert die IDE-Schicht die Index-Caches und baut
// den Index neu auf (OnRebuildIndex); die Seite zeigt nur das Ergebnis. Anzeigen und Schalter zum Server (Zustand,
// Version, Fenster „dpcc-Server“, „Prozesse am Projekt…“) gibt es seit S1 bzw. S4 nicht mehr.
// experimental.enabled bleibt versteckt gebaut: Der Wert wirkt weiter (settings.json, experimentelle Schlüssel des
// Servers wie completion.typeConversion), und Hinweis und Filter der Seite hängen daran.

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Allgemein“: Hauptschalter, „Index neu aufbauen“ und experimentelle Funktionen.</summary>
  TDpccSettingsGeneralPart = class(TDpccSettingsPagePart)
  private
    /// <summary>Hauptschalter der experimentellen Funktionen (#834), Hinweis darüber und Filter unten.</summary>
    FExperimentalEnabled: TCheckBox;
    /// <summary>„Index neu aufbauen“ (S4) und die Zeile mit dem Ergebnis.</summary>
    FRebuild: TButton;
    FRebuildInfo: TLabel;
    FOnRebuildIndex: TFunc<string>;
    FConfirmRebuild: TFunc<Boolean>;
    procedure AddRebuildRow;
    procedure RebuildClick(Sender: TObject);
    procedure SetOnRebuildIndex(const AValue: TFunc<string>);
  public
    procedure Build;
    property ExperimentalEnabled: TCheckBox read FExperimentalEnabled;
    /// <summary>Zum Testen: Knopf „Index neu aufbauen“ und die Zeile mit dem Ergebnis.</summary>
    property Rebuild: TButton read FRebuild;
    property RebuildInfo: TLabel read FRebuildInfo;
    /// <summary>„Index neu aufbauen“ (S4): leert die Index-Caches, baut den Index neu auf und liefert die Meldung
    /// für die Seite; nil = Knopf gesperrt.</summary>
    property OnRebuildIndex: TFunc<string> read FOnRebuildIndex write SetOnRebuildIndex;
    /// <summary>Rückfrage vor dem Neuaufbau; Standard: Dialog mit Ja/Nein.</summary>
    property ConfirmRebuild: TFunc<Boolean> read FConfirmRebuild write FConfirmRebuild;
  end;

implementation

uses
  System.UITypes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Dialogs,
  Vcl.Forms,
  Vcl.Themes,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings;

{ TDpccSettingsGeneralPart }

procedure TDpccSettingsGeneralPart.Build;
begin
  AddSheet(TDpccTextId.SettingsTabGeneral);
  BindCheck('Enabled', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsEnabled)));
  AddRebuildRow;
  // L2: zusätzliche Quellordner (settings.json, der Server liest denselben Wert); Vorgabe leer. Office-Typbibliotheken
  // und WinRT stehen immer im Katalog, ihr früherer Schalter ist entfallen.
  BindText('IndexExtraSourceFolders',
    AddTextLine(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexExtraSourceFolders)));
  // Hauptschalter der experimentellen Funktionen (#834).
  FExperimentalEnabled := BindCheck('ExperimentalEnabled',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExperimentalEnabled)));
end;

procedure TDpccSettingsGeneralPart.AddRebuildRow;
var
  mPanel: TWinControl;
begin
  // „Index neu aufbauen“ (S4): ersetzt die Knöpfe der früheren Seite „Index“.
  mPanel := AddPanel(32);
  FRebuild := TButton.Create(FPage);
  FRebuild.Parent := mPanel;
  FRebuild.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexRebuild);
  FRebuild.Left := 0;
  FRebuild.Top := FRebuild.ScaleValue(3);
  FRebuild.Width := FRebuild.ScaleValue(180);
  FRebuild.OnClick := RebuildClick;
  mPanel := AddPanel(20);
  FRebuildInfo := TLabel.Create(FPage);
  FRebuildInfo.Parent := mPanel;
  FRebuildInfo.Left := 0;
  FRebuildInfo.Top := FRebuildInfo.ScaleValue(2);
  // Gedämpfter Text in der Farbe des IDE-Themas (hell und dunkel).
  FRebuildInfo.Font.Color := StyleServices.GetSystemColor(clGrayText);
  Allow(FRebuild, False);
end;

procedure TDpccSettingsGeneralPart.SetOnRebuildIndex(const AValue: TFunc<string>);
begin
  FOnRebuildIndex := AValue;
  Allow(FRebuild, Assigned(FOnRebuildIndex));
end;

procedure TDpccSettingsGeneralPart.RebuildClick(Sender: TObject);
var
  mConfirmed: Boolean;
  mCursor: TCursor;
begin
  if not Assigned(FOnRebuildIndex) then
  begin
    Exit;
  end;
  if Assigned(FConfirmRebuild) then
  begin
    mConfirmed := FConfirmRebuild();
  end
  else
  begin
    mConfirmed := MessageDlg(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexRebuildConfirm),
      mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  end;
  if not mConfirmed then
  begin
    Exit;
  end;
  // Laufende Sitzung anhalten, Caches löschen und neu starten dauert ein paar Sekunden.
  mCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    FRebuildInfo.Caption := FOnRebuildIndex();
  finally
    Screen.Cursor := mCursor;
  end;
end;

end.
