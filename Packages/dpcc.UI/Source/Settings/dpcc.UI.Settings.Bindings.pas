unit dpcc.UI.Settings.Bindings;

// Bindung der Steuerelemente der Optionsseite an Plugin-Einstellungen (#227, #1455): Jedes gebundene Element steht
// einmal mit dem Registry-Namen seiner Einstellung in der Liste; Laden und Speichern laufen über einen Speicher mit
// den Werten von TDpccPluginSettings (TDpccMemorySettingsStore.FromSettings, danach TDpccPluginSettings.Load).
// So steht eine einfache Einstellung nicht mehr als Feld, Laden und Speichern einzeln auf der Seite.
// Arten: Haken (0/1), Text (Zahlen bleiben Zahlen, sonst Text; beim Speichern ohne Leerraum am Rand),
// Tastenkürzel (Zahl im Speicher, Text wie „Strg+K“ im Feld) und Auswahl (gespeicherte Werte je Eintrag).

interface

uses
  System.Generics.Collections,
  Vcl.Controls,
  dpcc.Core.Settings.History;

type
  TDpccSettingsBindingKind = (sbkCheck, sbkText, sbkShortcut, sbkChoice);

  /// <summary>Element an einer Plugin-Einstellung: Registry-Name, Element, Art, bei einer Auswahl die gespeicherten
  /// Werte je Eintrag.</summary>
  TDpccSettingsValueBinding = record
    Name: string;
    Control: TControl;
    Kind: TDpccSettingsBindingKind;
    Values: TArray<string>;
  end;

  TDpccSettingsBindings = class
  private
    FItems: TList<TDpccSettingsValueBinding>;
    class procedure LoadOne(const AStore: IDpccMemorySettingsStore; const ABinding: TDpccSettingsValueBinding);
      static;
    class procedure SaveOne(const AStore: IDpccMemorySettingsStore; const ABinding: TDpccSettingsValueBinding);
      static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AControl muss zur Art passen: TCheckBox (Haken), TEdit (Text, Tastenkürzel), TDpccChoiceBox
    /// (Auswahl, AValues gleich lang wie die Einträge).</summary>
    procedure Add(const AName: string; AControl: TControl; AKind: TDpccSettingsBindingKind;
      const AValues: TArray<string>);
    procedure Load(const AStore: IDpccMemorySettingsStore);
    procedure Save(const AStore: IDpccMemorySettingsStore);
    procedure Clear;
    function Count: Integer;
    function Item(AIndex: Integer): TDpccSettingsValueBinding;
    /// <summary>Index von AValue in AValues ohne Rücksicht auf Groß-/Kleinschreibung; 0 ohne Treffer.</summary>
    class function ChoiceOf(const AValue: string; const AValues: array of string): Integer; static;
    /// <summary>Zahlen stehen als Zahl im Speicher (wie TDpccPluginSettings.Save), alles andere als Text; ein
    /// Text, der keine Zahl ist, lässt eine Zahl unverändert.</summary>
    class procedure WriteText(const AStore: IDpccMemorySettingsStore; const AName, AText: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.StdCtrls,
  Vcl.Menus,
  dpcc.UI.Settings.ChoiceBox;

constructor TDpccSettingsBindings.Create;
begin
  inherited Create;
  FItems := TList<TDpccSettingsValueBinding>.Create;
end;

destructor TDpccSettingsBindings.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TDpccSettingsBindings.Add(const AName: string; AControl: TControl; AKind: TDpccSettingsBindingKind;
  const AValues: TArray<string>);
var
  mBinding: TDpccSettingsValueBinding;
begin
  mBinding := Default(TDpccSettingsValueBinding);
  mBinding.Name := AName;
  mBinding.Control := AControl;
  mBinding.Kind := AKind;
  mBinding.Values := AValues;
  FItems.Add(mBinding);
end;

procedure TDpccSettingsBindings.Clear;
begin
  FItems.Clear;
end;

function TDpccSettingsBindings.Count: Integer;
begin
  Result := FItems.Count;
end;

function TDpccSettingsBindings.Item(AIndex: Integer): TDpccSettingsValueBinding;
begin
  Result := FItems[AIndex];
end;

procedure TDpccSettingsBindings.Load(const AStore: IDpccMemorySettingsStore);
var
  mBinding: TDpccSettingsValueBinding;
begin
  for mBinding in FItems do
  begin
    LoadOne(AStore, mBinding);
  end;
end;

procedure TDpccSettingsBindings.Save(const AStore: IDpccMemorySettingsStore);
var
  mBinding: TDpccSettingsValueBinding;
begin
  for mBinding in FItems do
  begin
    SaveOne(AStore, mBinding);
  end;
end;

class procedure TDpccSettingsBindings.LoadOne(const AStore: IDpccMemorySettingsStore;
  const ABinding: TDpccSettingsValueBinding);
begin
  case ABinding.Kind of
    sbkCheck:
      (ABinding.Control as TCheckBox).Checked := AStore.ReadInteger(ABinding.Name, 0) <> 0;
    sbkText:
      (ABinding.Control as TEdit).Text := AStore.Text(ABinding.Name);
    sbkShortcut:
      (ABinding.Control as TEdit).Text := ShortCutToText(TShortCut(AStore.ReadInteger(ABinding.Name, 0)));
    sbkChoice:
      (ABinding.Control as TDpccChoiceBox).Choice := ChoiceOf(AStore.Text(ABinding.Name), ABinding.Values);
  end;
end;

class procedure TDpccSettingsBindings.SaveOne(const AStore: IDpccMemorySettingsStore;
  const ABinding: TDpccSettingsValueBinding);
var
  mChoice: Integer;
begin
  case ABinding.Kind of
    sbkCheck:
      AStore.WriteInteger(ABinding.Name, Ord((ABinding.Control as TCheckBox).Checked));
    sbkText:
      WriteText(AStore, ABinding.Name, Trim((ABinding.Control as TEdit).Text));
    sbkShortcut:
      AStore.WriteInteger(ABinding.Name, Integer(TextToShortCut(Trim((ABinding.Control as TEdit).Text))));
    sbkChoice:
      begin
        mChoice := (ABinding.Control as TDpccChoiceBox).Choice;
        if (mChoice >= 0) and (mChoice <= High(ABinding.Values)) then
        begin
          WriteText(AStore, ABinding.Name, ABinding.Values[mChoice]);
        end;
      end;
  end;
end;

class function TDpccSettingsBindings.ChoiceOf(const AValue: string; const AValues: array of string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AValues) do
  begin
    if SameText(AValues[mIndex], AValue) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := 0;
end;

class procedure TDpccSettingsBindings.WriteText(const AStore: IDpccMemorySettingsStore; const AName, AText: string);
var
  mValue: Integer;
begin
  if AStore.HasInteger(AName) then
  begin
    if TryStrToInt(AText, mValue) then
    begin
      AStore.WriteInteger(AName, mValue);
    end;
  end
  else
  begin
    AStore.WriteString(AName, AText);
  end;
end;

end.
