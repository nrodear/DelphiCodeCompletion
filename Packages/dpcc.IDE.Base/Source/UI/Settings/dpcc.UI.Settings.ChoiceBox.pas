unit dpcc.UI.Settings.ChoiceBox;

// Auswahlliste der Optionsseiten (aus dpcc.UI.Settings.Page herausgelöst,
// damit Dialoge der Seite sie nutzen, ohne die Seite einzubinden, #1450).

interface

uses
  System.Classes,
  Vcl.StdCtrls;

type
  /// <summary>Auswahlliste, die Einträge und Auswahl ohne Fensterhandle hält: Die IDE erzeugt und lädt die
  /// Optionsseiten, bevor sie ein übergeordnetes Fenster haben; Items.Add bräuchte dann schon eins.</summary>
  TDpccChoiceBox = class(TComboBox)
  private
    FChoices: TArray<string>;
    FChoice: Integer;
    function GetChoice: Integer;
    procedure SetChoice(AValue: Integer);
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetChoices(const AItems: array of string);
    /// <summary>Gewählter Eintrag, -1 = keiner; gilt auch ohne Fenster.</summary>
    property Choice: Integer read GetChoice write SetChoice;
  end;

implementation

{ TDpccChoiceBox }

constructor TDpccChoiceBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Style := csDropDownList;
  FChoice := -1;
end;

procedure TDpccChoiceBox.SetChoices(const AItems: array of string);
var
  mIndex: Integer;
begin
  SetLength(FChoices, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    FChoices[mIndex] := AItems[mIndex];
  end;
  if HandleAllocated then
  begin
    Items.Clear;
    for mIndex := 0 to High(FChoices) do
    begin
      Items.Add(FChoices[mIndex]);
    end;
    ItemIndex := FChoice;
  end;
end;

procedure TDpccChoiceBox.CreateWnd;
var
  mItem: string;
begin
  inherited CreateWnd;
  if Items.Count = 0 then
  begin
    for mItem in FChoices do
    begin
      Items.Add(mItem);
    end;
  end;
  ItemIndex := FChoice;
end;

procedure TDpccChoiceBox.DestroyWnd;
begin
  // Auswahl sichern, bevor das Fenster wegfällt (RecreateWnd); CreateWnd setzt sie wieder. So ändert der
  // Getter nichts (getter-side-effect, #1052).
  FChoice := ItemIndex;
  inherited DestroyWnd;
end;

function TDpccChoiceBox.GetChoice: Integer;
begin
  if HandleAllocated then
  begin
    Result := ItemIndex;
  end
  else
  begin
    Result := FChoice;
  end;
end;

procedure TDpccChoiceBox.SetChoice(AValue: Integer);
begin
  FChoice := AValue;
  if HandleAllocated then
  begin
    ItemIndex := AValue;
  end;
end;

end.
