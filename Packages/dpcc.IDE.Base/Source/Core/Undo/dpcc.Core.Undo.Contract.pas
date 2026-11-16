unit dpcc.Core.Undo.Contract;

// dpcc-Änderungssätze (#721): Eine dpcc-Aktion, die mehr als eine Datei
// ändert (oder Dateien anlegt bzw. löscht), wird als ein Satz protokolliert:
// Aktion, Zeitpunkt und je Datei der Inhalt vorher und nachher samt Kodierung
// und Zeilenenden (#121). Das Ziel (IDpccUndoTarget) schreibt beim
// Zurücknehmen und Wiederherstellen: in der IDE offene Dateien über ihren
// Puffer, Formulare über den Designer, sonst die Platte. Der Speicher
// (IDpccUndoStore) sichert die Sätze über einen Neustart hinweg.

interface

uses
  System.SysUtils,
  dpcc.Core.Files.Contract;

type
{$SCOPEDENUMS ON}
  TDpccFileChangeKind = (Modified, Created, Deleted);
  /// <summary>undo.multiFile.onConflict: nur die Dateien ohne Konflikt zurücknehmen oder gar nichts.</summary>
  TDpccUndoConflictMode = (Partial, Abort);
  /// <summary>undo.multiFile.newFiles: neu angelegte Dateien beim Zurücknehmen.</summary>
  TDpccNewFilesMode = (RecycleBin, Delete, Keep);
  TDpccChangeSetState = (Applied, PartlyUndone, Undone);
  /// <summary>Warum eine Datei nicht zurückgenommen bzw. wiederhergestellt wurde.</summary>
  TDpccUndoProblemKind = (
    /// <summary>Die betroffenen Stellen wurden nach der Aktion geändert.</summary>
    ChangedSince,
    /// <summary>Die Datei gibt es (wieder), sie soll aber angelegt werden.</summary>
    Exists,
    /// <summary>Die Datei fehlt.</summary>
    Missing,
    /// <summary>Schreiben schlug fehl (Message).</summary>
    Failed);
{$SCOPEDENUMS OFF}

  TDpccFileChange = record
    FileName: string;
    Kind: TDpccFileChangeKind;
    /// <summary>Inhalt vor der Aktion; leer bei Created.</summary>
    Before: TDpccTextFileContent;
    /// <summary>Inhalt nach der Aktion; leer bei Deleted.</summary>
    After: TDpccTextFileContent;
    /// <summary>Projekt (.dproj), in das die Datei eingetragen ist bzw. war; '' = keins.</summary>
    Project: string;
    /// <summary>Diese Datei ist zurückgenommen.</summary>
    Undone: Boolean;
    class function Modified(const AFileName: string; const ABefore, AAfter: TDpccTextFileContent):
      TDpccFileChange; static;
    class function Created(const AFileName, AProject: string; const AContent: TDpccTextFileContent):
      TDpccFileChange; static;
    class function Deleted(const AFileName, AProject: string; const AContent: TDpccTextFileContent):
      TDpccFileChange; static;
  end;

  TDpccChangeSet = record
    Id: Integer;
    /// <summary>Was dpcc getan hat, z. B. „Umbenennen: Alt → Neu“.</summary>
    Action: string;
    Time: TDateTime;
    Files: TArray<TDpccFileChange>;
    function State: TDpccChangeSetState;
    /// <summary>Ungefähre Größe im Speicher in Byte (Texte vorher und nachher).</summary>
    function Size: Int64;
    /// <summary>Index der Datei oder -1.</summary>
    function IndexOf(const AFileName: string): Integer;
  end;

  TDpccUndoProblem = record
    FileName: string;
    Kind: TDpccUndoProblemKind;
    /// <summary>Bei Failed die Fehlermeldung.</summary>
    Message: string;
  end;

  TDpccUndoReport = record
    SetId: Integer;
    Action: string;
    /// <summary>Wiederherstellen statt Zurücknehmen.</summary>
    Redo: Boolean;
    /// <summary>Kein passender Satz (leeres Protokoll, unbekannte Kennung, schon zurückgenommen).</summary>
    NotFound: Boolean;
    /// <summary>Protokoll ausgeschaltet (undo.multiFile).</summary>
    Disabled: Boolean;
    /// <summary>Wegen Konflikten nichts geändert (undo.multiFile.onConflict = abort).</summary>
    Aborted: Boolean;
    /// <summary>Geänderte Dateien.</summary>
    Done: TArray<string>;
    Conflicts: TArray<TDpccUndoProblem>;
    Errors: TArray<TDpccUndoProblem>;
    /// <summary>Etwas geändert und kein Konflikt, kein Fehler.</summary>
    function Complete: Boolean;
  end;

  /// <summary>Schreibt Dateien beim Zurücknehmen und Wiederherstellen.
  /// Ausnahmen gelten als Fehler der Datei.</summary>
  IDpccUndoTarget = interface
    ['{6B1E4D27-3A95-4C08-9F72-E5D8A13C40B6}']
    /// <summary>Aktueller Inhalt (offener Puffer, Formular im Designer, sonst Platte); False, wenn die Datei
    /// fehlt.</summary>
    function Read(const AFileName: string; out AContent: TDpccTextFileContent): Boolean;
    /// <summary>Vorhandene Datei ändern; ein offener Puffer als ein Rückgängig-Schritt.</summary>
    procedure Write(const AFileName: string; const AContent: TDpccTextFileContent);
    /// <summary>Datei anlegen (wiederherstellen) und, wenn AProject gesetzt ist, ins Projekt eintragen.</summary>
    procedure CreateFile(const AFileName, AProject: string; const AContent: TDpccTextFileContent);
    /// <summary>Datei aus AProject austragen, schließen und nach AMode löschen, in den Papierkorb verschieben
    /// oder behalten.</summary>
    procedure RemoveFile(const AFileName, AProject: string; AMode: TDpccNewFilesMode);
  end;

  /// <summary>Sichert Sätze über einen Neustart hinweg.</summary>
  IDpccUndoStore = interface
    ['{0F3C7A52-8E41-4B6D-A2C9-71D4E06B5F83}']
    /// <summary>Satz (neu) sichern; ältere Sätze fallen weg, bis die Größenbegrenzung passt.</summary>
    procedure Save(const ASet: TDpccChangeSet);
    procedure Delete(AId: Integer);
    /// <summary>Alle gesicherten Sätze, älteste zuerst; unlesbare werden übergangen.</summary>
    function Load: TArray<TDpccChangeSet>;
    procedure Clear;
  end;

  TDpccUndoFileProc = reference to procedure(const AFileName, AProject: string);

  /// <summary>Haken des Plattenziels: Projekt und Papierkorb kennt nur die IDE-Schicht.</summary>
  TDpccUndoDiskHooks = record
    OnAddToProject: TDpccUndoFileProc;
    OnRemoveFromProject: TDpccUndoFileProc;
    /// <summary>Datei in den Papierkorb verschieben; nil = löschen.</summary>
    OnRecycle: TProc<string>;
  end;

  /// <summary>Legt das Plattenziel an; die Kompositionswurzel setzt den Adapter ein.</summary>
  TDpccUndoDiskFactory = reference to function(const AHooks: TDpccUndoDiskHooks): IDpccUndoTarget;
  /// <summary>Legt die Sicherung im Ordner AFolder an (AMaxBytes = 0: ohne Begrenzung, nur zum Leeren).</summary>
  TDpccUndoStoreFactory = reference to function(const AFolder: string; AMaxBytes: Int64): IDpccUndoStore;

implementation

{ TDpccFileChange }

class function TDpccFileChange.Modified(const AFileName: string; const ABefore,
  AAfter: TDpccTextFileContent): TDpccFileChange;
begin
  Result := Default(TDpccFileChange);
  Result.FileName := AFileName;
  Result.Kind := TDpccFileChangeKind.Modified;
  Result.Before := ABefore;
  Result.After := AAfter;
end;

class function TDpccFileChange.Created(const AFileName, AProject: string;
  const AContent: TDpccTextFileContent): TDpccFileChange;
begin
  Result := Default(TDpccFileChange);
  Result.FileName := AFileName;
  Result.Kind := TDpccFileChangeKind.Created;
  Result.After := AContent;
  Result.Project := AProject;
end;

class function TDpccFileChange.Deleted(const AFileName, AProject: string;
  const AContent: TDpccTextFileContent): TDpccFileChange;
begin
  Result := Default(TDpccFileChange);
  Result.FileName := AFileName;
  Result.Kind := TDpccFileChangeKind.Deleted;
  Result.Before := AContent;
  Result.Project := AProject;
end;

{ TDpccChangeSet }

function TDpccChangeSet.State: TDpccChangeSetState;
var
  mChange: TDpccFileChange;
  mUndone: Integer;
begin
  mUndone := 0;
  for mChange in Files do
  begin
    if mChange.Undone then
    begin
      Inc(mUndone);
    end;
  end;
  if mUndone = 0 then
  begin
    Result := TDpccChangeSetState.Applied;
  end
  else if mUndone = Length(Files) then
  begin
    Result := TDpccChangeSetState.Undone;
  end
  else
  begin
    Result := TDpccChangeSetState.PartlyUndone;
  end;
end;

function TDpccChangeSet.Size: Int64;
var
  mChange: TDpccFileChange;
begin
  Result := Length(Action) * SizeOf(Char);
  for mChange in Files do
  begin
    Inc(Result, Int64(Length(mChange.FileName) + Length(mChange.Before.Text) + Length(mChange.After.Text)) *
      SizeOf(Char));
  end;
end;

function TDpccChangeSet.IndexOf(const AFileName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Files) do
  begin
    if SameText(Files[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TDpccUndoReport }

function TDpccUndoReport.Complete: Boolean;
begin
  Result := (Length(Done) > 0) and (Length(Conflicts) = 0) and (Length(Errors) = 0) and not Aborted;
end;

end.
