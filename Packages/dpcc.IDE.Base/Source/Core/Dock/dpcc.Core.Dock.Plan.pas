unit dpcc.Core.Dock.Plan;

// Entscheidungen für dpcc-Dockfenster (#879), ohne VCL und Open Tools API.
// Die IDE gibt andockbare Fenster auch selbst frei (Entladen des Packages,
// Desktop-Wechsel, Beenden) und versteckt sie beim Schließen über das X
// samt Dock-Gastgeber. Ein Fenster gilt darum nur als brauchbar, wenn Form
// UND Frame noch leben; sichtbar ist es nur, wenn auch alle Gastgeber
// (Reiterseite, Dock-Fenster, Hauptfenster) sichtbar sind. Ein Fenster mit
// fester Vorgabe (etwa „dpcc-Architektur“ rechts, #1118) wird nur beim
// allerersten Anlegen dorthin gelegt; danach gilt der Desktop der IDE.

{$SCOPEDENUMS ON}

interface

type
  /// <summary>Was „Fenster zeigen“ tun muss.</summary>
  TDpccDockStep = (
    /// <summary>Keine andockbaren Fenster (keine INTAServices): nichts tun.</summary>
    Unavailable,
    /// <summary>Kein Fenster vorhanden: neu anlegen.</summary>
    CreateForm,
    /// <summary>Fenster ohne Frame (Frame freigegeben oder nie gemeldet): altes freigeben, neu anlegen.</summary>
    RecreateForm,
    /// <summary>Fenster und Frame leben: nur sichtbar machen (samt Gastgebern).</summary>
    RevealForm);

  TDpccDockPlan = record
  public
    /// <summary>Schritt beim Zeigen nach dem Zustand von Form und Frame.</summary>
    class function ShowStep(AServices, AFormAlive, AFrameAlive: Boolean): TDpccDockStep; static;
    /// <summary>Frame nur benutzen, wenn auch die Form noch lebt.</summary>
    class function FrameUsable(AFormAlive, AFrameAlive: Boolean): Boolean; static;
    /// <summary>Wirklich sichtbar: Form sichtbar und jeder Gastgeber bis oben (Reihenfolge innen nach außen).</summary>
    class function Shown(AFormVisible: Boolean; const AHostsVisible: array of Boolean): Boolean; static;
    /// <summary>Neu angelegtes, schwebendes Fenster an seinen Vorgabeplatz andocken: nur einmal (APlaced
    /// merkt sich das) und nur, wenn das Ziel selbst angedockt ist. Ein Fenster, das der Desktop schon
    /// angedockt wiederhergestellt hat, bleibt, wo es ist.</summary>
    class function DockToDefault(ACreated, AFloating, APlaced, ATargetDocked: Boolean): Boolean; static;
  end;

implementation

{ TDpccDockPlan }

class function TDpccDockPlan.ShowStep(AServices, AFormAlive, AFrameAlive: Boolean): TDpccDockStep;
begin
  if AFormAlive and AFrameAlive then
  begin
    Exit(TDpccDockStep.RevealForm);
  end;
  if not AServices then
  begin
    Exit(TDpccDockStep.Unavailable);
  end;
  if AFormAlive then
  begin
    Result := TDpccDockStep.RecreateForm;
  end
  else
  begin
    Result := TDpccDockStep.CreateForm;
  end;
end;

class function TDpccDockPlan.FrameUsable(AFormAlive, AFrameAlive: Boolean): Boolean;
begin
  Result := AFormAlive and AFrameAlive;
end;

class function TDpccDockPlan.Shown(AFormVisible: Boolean; const AHostsVisible: array of Boolean): Boolean;
var
  mVisible: Boolean;
begin
  Result := AFormVisible;
  for mVisible in AHostsVisible do
  begin
    Result := Result and mVisible;
  end;
end;

class function TDpccDockPlan.DockToDefault(ACreated, AFloating, APlaced, ATargetDocked: Boolean): Boolean;
begin
  Result := ACreated and AFloating and not APlaced and ATargetDocked;
end;

end.
