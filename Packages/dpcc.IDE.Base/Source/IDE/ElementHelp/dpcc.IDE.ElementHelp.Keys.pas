unit dpcc.IDE.ElementHelp.Keys;

// F1 zu dpcc-Elementen (#1886) für Base: fragt den laufenden Anbieter von IDpccHelpProvider
// (dpcc.IDE.Contracts.Help, Modul Hilfe) bei jedem Aufruf neu über die Registry (Regel 3: das Modul kann
// inzwischen fort sein). AddKey hängt an einen Frame (dpcc-Fenster, Optionsseite) eine Aktion mit F1: Sie ist
// nur aktiv, solange ein Anbieter zur Kennung unter dem Fokus eine Seite kennt; sonst geht F1 wie vorher an die
// IDE. Jedes dpcc-Dockfenster bekommt F1 über TDpccIdeDockWindow.OnFrameCreated: Kennung ist das Fenster
// selbst, SetWindowTopic kann je Fenster eine genauere liefern (dpcc-Prüfung: Regel des gewählten Befunds).
// Nur im Hauptthread verwenden.

interface

uses
  System.Classes,
  dpcc.IDE.Contracts.Help;

type
  /// <summary>Kennung des Elements unter dem Fokus; False ohne.</summary>
  TDpccHelpTopicFunc = reference to function(out ATopic: TDpccHelpTopic): Boolean;

  TDpccIdeHelp = class
  public const
    /// <summary>Kennung der Optionsseite „dpcc“ ohne Einstellung unter dem Fokus.</summary>
    cOptionsWindow = 'DpccOptions';
  public
    class function Topic(AKind: TDpccHelpKind; const AId: string): TDpccHelpTopic; static;
    /// <summary>Kennt ein laufendes Modul eine Seite zu ATopic?</summary>
    class function Available(const ATopic: TDpccHelpTopic): Boolean; static;
    /// <summary>Seite zu ATopic zeigen; False ohne Anbieter oder ohne Seite.</summary>
    class function Show(const ATopic: TDpccHelpTopic): Boolean; static;
    /// <summary>F1 in AOwner (Frame eines dpcc-Fensters, Optionsseite): Hilfe zu ATopicOf. Die Aktion gehört
    /// AOwner und geht mit ihm.</summary>
    class procedure AddKey(AOwner: TComponent; const ATopicOf: TDpccHelpTopicFunc); static;
    /// <summary>Genauere Kennung für F1 im Dockfenster AWindow; ohne bzw. bei False gilt das Fenster.</summary>
    class procedure SetWindowTopic(const AWindow: string; const ATopicOf: TDpccHelpTopicFunc); static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.ActnList,
  Vcl.Forms,
  Vcl.Menus,
  dpcc.IDE.Foundation.DockWindow,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Modules.Registry,
  dpcc.Core.Modules.Contributions;

type
  /// <summary>Hält Aktion und Rückruf; gehört dem Frame.</summary>
  THelpKey = class(TComponent)
  private
    FTopicOf: TDpccHelpTopicFunc;
    procedure ActionUpdate(Sender: TObject);
    procedure ActionExecute(Sender: TObject);
  end;

var
  /// <summary>Genauere Kennungen je Dockfenster (SetWindowTopic).</summary>
  GWindowTopics: TDictionary<string, TDpccHelpTopicFunc>;

/// <summary>Erster laufender Anbieter; False ohne.</summary>
function Find(out AProvider: IDpccHelpProvider): Boolean;
var
  mItem: IInterface;
begin
  AProvider := nil;
  for mItem in TDpccModuleContributions.Active(DpccModuleRegistry, IDpccHelpProvider) do
  begin
    if Supports(mItem, IDpccHelpProvider, AProvider) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ THelpKey }

procedure THelpKey.ActionUpdate(Sender: TObject);
var
  mTopic: TDpccHelpTopic;
begin
  (Sender as TAction).Enabled := Assigned(FTopicOf) and FTopicOf(mTopic) and TDpccIdeHelp.Available(mTopic);
end;

procedure THelpKey.ActionExecute(Sender: TObject);
var
  mTopic: TDpccHelpTopic;
begin
  if Assigned(FTopicOf) and FTopicOf(mTopic) then
  begin
    TDpccIdeHelp.Show(mTopic);
  end;
end;

{ TDpccIdeHelp }

class function TDpccIdeHelp.Topic(AKind: TDpccHelpKind; const AId: string): TDpccHelpTopic;
begin
  Result.Kind := AKind;
  Result.Id := AId;
end;

class function TDpccIdeHelp.Available(const ATopic: TDpccHelpTopic): Boolean;
var
  mProvider: IDpccHelpProvider;
begin
  Result := (ATopic.Id <> '') and Find(mProvider) and mProvider.HasHelp(ATopic);
end;

class function TDpccIdeHelp.Show(const ATopic: TDpccHelpTopic): Boolean;
var
  mProvider: IDpccHelpProvider;
begin
  Result := False;
  if (ATopic.Id <> '') and Find(mProvider) then
  begin
    try
      Result := mProvider.ShowHelp(ATopic);
    except
      on mError: Exception do
      begin
        TDpccGuard.Log('F1 ' + ATopic.Id + ': ' + mError.Message);
      end;
    end;
  end;
end;

class procedure TDpccIdeHelp.AddKey(AOwner: TComponent; const ATopicOf: TDpccHelpTopicFunc);
var
  mKey: THelpKey;
  mList: TActionList;
  mAction: TAction;
begin
  if AOwner = nil then
  begin
    Exit;
  end;
  mKey := THelpKey.Create(AOwner);
  mKey.FTopicOf := ATopicOf;
  mList := TActionList.Create(AOwner);
  mAction := TAction.Create(mList);
  mAction.ActionList := mList;
  mAction.ShortCut := ShortCut(VK_F1, []);
  mAction.OnUpdate := mKey.ActionUpdate;
  mAction.OnExecute := mKey.ActionExecute;
end;

class procedure TDpccIdeHelp.SetWindowTopic(const AWindow: string; const ATopicOf: TDpccHelpTopicFunc);
begin
  GWindowTopics.AddOrSetValue(AWindow, ATopicOf);
end;

/// <summary>F1 für den neuen Frame des Dockfensters AWindow.</summary>
procedure WindowFrameCreated(AWindow: string; AFrame: TCustomFrame);
begin
  TDpccIdeHelp.AddKey(AFrame,
    function(out ATopic: TDpccHelpTopic): Boolean
    var
      mTopicOf: TDpccHelpTopicFunc;
    begin
      Result := GWindowTopics.TryGetValue(AWindow, mTopicOf) and Assigned(mTopicOf) and mTopicOf(ATopic);
      if not Result then
      begin
        ATopic := TDpccIdeHelp.Topic(TDpccHelpKind.Window, AWindow);
        Result := True;
      end;
    end);
end;

initialization
  GWindowTopics := TDictionary<string, TDpccHelpTopicFunc>.Create;
  TDpccIdeDockWindow.OnFrameCreated := WindowFrameCreated;

finalization
  TDpccIdeDockWindow.OnFrameCreated := nil;
  FreeAndNil(GWindowTopics);

end.
