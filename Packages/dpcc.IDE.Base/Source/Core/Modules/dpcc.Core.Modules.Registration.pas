unit dpcc.Core.Modules.Registration;

// Gemeinsame Grundlage der Anmeldungen in Base (#1455, Regel 4): Revoke löst
// eine Anmeldung genau einmal; Detach markiert sie als gelöst, ohne den
// Besitzer zu rufen, wenn die Ablage vor ihr abgebaut wird (sonst zeigte ein
// späteres Revoke in freigegebenen Speicher).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  dpcc.Core.Modules.Contract;

type
  TDpccRegistration = class(TInterfacedObject, IDpccRegistration)
  private
    FLock: TCriticalSection;
    FRevoked: Boolean;
    function TryClaim: Boolean;
  protected
    /// <summary>Löst die Anmeldung bei ihrer Ablage; genau einmal gerufen, nie nach Detach.</summary>
    procedure DoRevoke; virtual; abstract;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Revoke;
    function IsRevoked: Boolean;
    /// <summary>Ablage abgebaut: als gelöst markieren, ohne DoRevoke.</summary>
    procedure Detach;
  end;

implementation

{ TDpccRegistration }

constructor TDpccRegistration.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TDpccRegistration.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TDpccRegistration.TryClaim: Boolean;
begin
  FLock.Acquire;
  try
    Result := not FRevoked;
    FRevoked := True;
  finally
    FLock.Release;
  end;
end;

procedure TDpccRegistration.Revoke;
begin
  if TryClaim then
  begin
    DoRevoke;
  end;
end;

function TDpccRegistration.IsRevoked: Boolean;
begin
  FLock.Acquire;
  try
    Result := FRevoked;
  finally
    FLock.Release;
  end;
end;

procedure TDpccRegistration.Detach;
begin
  TryClaim;
end;

end.
