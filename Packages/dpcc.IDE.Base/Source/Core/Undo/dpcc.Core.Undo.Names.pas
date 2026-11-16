unit dpcc.Core.Undo.Names;

// Texte der Einstellungen undo.multiFile.onConflict und undo.multiFile.newFiles
// (#721) und ihre Aufzählungswerte. Steht im Root des Features Undo, weil ein
// Contract nur Typen und Interfaces enthält.

interface

uses
  dpcc.Core.Undo.Contract;

type
  TDpccUndoNames = class
  public
    /// <summary>"partial" oder "abort".</summary>
    class function ConflictModeName(AMode: TDpccUndoConflictMode): string; static;
    /// <summary>Unbekannter Text liefert Partial.</summary>
    class function ParseConflictMode(const AText: string): TDpccUndoConflictMode; static;
    /// <summary>"recycleBin", "delete" oder "keep".</summary>
    class function NewFilesName(AMode: TDpccNewFilesMode): string; static;
    /// <summary>Unbekannter Text liefert RecycleBin.</summary>
    class function ParseNewFiles(const AText: string): TDpccNewFilesMode; static;
  end;

implementation

uses
  System.SysUtils;

{ TDpccUndoNames }

class function TDpccUndoNames.ConflictModeName(AMode: TDpccUndoConflictMode): string;
begin
  if AMode = TDpccUndoConflictMode.Abort then
  begin
    Result := 'abort';
  end
  else
  begin
    Result := 'partial';
  end;
end;

class function TDpccUndoNames.ParseConflictMode(const AText: string): TDpccUndoConflictMode;
begin
  if SameText(Trim(AText), 'abort') then
  begin
    Result := TDpccUndoConflictMode.Abort;
  end
  else
  begin
    Result := TDpccUndoConflictMode.Partial;
  end;
end;

class function TDpccUndoNames.NewFilesName(AMode: TDpccNewFilesMode): string;
begin
  case AMode of
    TDpccNewFilesMode.Delete:
      Result := 'delete';
    TDpccNewFilesMode.Keep:
      Result := 'keep';
  else
    Result := 'recycleBin';
  end;
end;

class function TDpccUndoNames.ParseNewFiles(const AText: string): TDpccNewFilesMode;
begin
  if SameText(Trim(AText), 'delete') then
  begin
    Result := TDpccNewFilesMode.Delete;
  end
  else if SameText(Trim(AText), 'keep') then
  begin
    Result := TDpccNewFilesMode.Keep;
  end
  else
  begin
    Result := TDpccNewFilesMode.RecycleBin;
  end;
end;

end.
