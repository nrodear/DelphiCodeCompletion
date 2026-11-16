unit dpcc.Core.CiBuild.Contract;

// Stand des Build-Servers (CI, #763) als Daten, ohne VCL, Open Tools API und
// Netz: Ergebnis und Testbericht des letzten Builds (TDpccCiBuild), Fehlerart
// einer Abfrage und der abgefragte Job (TDpccCiJob, aus der .dpcc #486 und
// der Versionsverwaltung #571; nie Zugangsdaten). Liegt in Base, weil die
// Projekt-Zusammenfassung (dpcc.Core.Projects.Summary) den Stand speichert
// (#1455, vorher in dpcc.Core.Ci.Contract); Abfrage, Anbieter und Transport
// bleiben im Modul Tracker (dpcc.Core.Ci.Contract).

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Ergebnis eines Builds auf dem Server.</summary>
  TDpccCiOutcome = (Unknown, Success, Unstable, Failure, Aborted, NotBuilt);

  /// <summary>Warum eine Abfrage nichts brachte.</summary>
  TDpccCiFetchError = (None, NotConfigured, Network, Timeout, Unauthorized, NotFound, Server, Invalid, Cancelled,
    UnknownProvider, NoCredentials);
{$SCOPEDENUMS OFF}

  /// <summary>Fehlgeschlagener Test auf dem Server.</summary>
  TDpccCiFailure = record
    /// <summary>Voller Name wie bei DUnitX (Klasse.Methode), damit „erneut ausführen“ ihn an --run geben kann.
    /// </summary>
    Test: string;
    /// <summary>Erste Zeile der Fehlermeldung; '' ohne.</summary>
    Message: string;
  end;

  /// <summary>Letzter abgeschlossener Build mit Testbericht.</summary>
  TDpccCiBuild = record
  public const
    /// <summary>Höchstens so viele fehlgeschlagene Tests werden gelesen und gespeichert.</summary>
    cMaxFailures = 50;
  public
    /// <summary>Build-Nummer; 0 = kein Build bekannt.</summary>
    Number: Integer;
    Outcome: TDpccCiOutcome;
    /// <summary>Start des Builds (UTC); 0 = unbekannt.</summary>
    StartedUtc: TDateTime;
    /// <summary>Dauer in ms; 0 = unbekannt.</summary>
    DurationMs: Int64;
    /// <summary>Der Build hat einen Testbericht (JUnit-Plugin).</summary>
    TestsKnown: Boolean;
    Passed: Integer;
    /// <summary>Alle fehlgeschlagenen Tests, auch über MaxFailures hinaus.</summary>
    Failed: Integer;
    Skipped: Integer;
    Failures: TArray<TDpccCiFailure>;
    class function Empty: TDpccCiBuild; static;
    /// <summary>"success", "unstable", "failure", "aborted", "notBuilt" bzw. "unknown".</summary>
    class function OutcomeKey(AOutcome: TDpccCiOutcome): string; static;
    /// <summary>Umkehrung von OutcomeKey; Unknown für fremde Texte.</summary>
    class function OutcomeOf(const AKey: string): TDpccCiOutcome; static;
    /// <summary>Kennung für Datei und Protokoll ("timeout", "unauthorized" …); '' für None.</summary>
    class function ErrorKey(AError: TDpccCiFetchError): string; static;
    class function ErrorOf(const AKey: string): TDpccCiFetchError; static;
  end;

  /// <summary>Was abgefragt wird; ohne Zugangsdaten.</summary>
  TDpccCiJob = record
    /// <summary>"jenkins".</summary>
    Provider: string;
    /// <summary>Adresse des Servers, z. B. "https://ci.firma.de" (ohne /job/…).</summary>
    Url: string;
    /// <summary>Job; Ordner mit „/“ getrennt, z. B. "team/kasse".</summary>
    Job: string;
    /// <summary>Multibranch-Job: abgefragt wird der Job des Branches.</summary>
    Multibranch: Boolean;
    /// <summary>Aktueller Branch des Projekts (#571); nur bei Multibranch Teil der Adresse.</summary>
    Branch: string;
    class function Create(const AProvider, AUrl, AJob: string; AMultibranch: Boolean;
      const ABranch: string): TDpccCiJob; static;
    /// <summary>Server, Job und (bei Multibranch) Branch bekannt.</summary>
    function Configured: Boolean;
    /// <summary>Branch, der zur Abfrage gehört: bei Multibranch Branch, sonst ''.</summary>
    function JobBranch: string;
    /// <summary>Kennung für Vergleich und Merker (klein, ohne „/“ am Ende).</summary>
    function Key: string;
    /// <summary>Schema, Rechner und Port in Kleinbuchstaben, z. B. "https://ci.firma.de:8443"; '' bei
    /// ungültiger Adresse.</summary>
    function Server: string;
    /// <summary>Name des Eintrags im Anmeldespeicher von Windows: "dpcc:ci:" + Server.</summary>
    function CredentialTarget: string;
    /// <summary>Server mit https://.</summary>
    function Secure: Boolean;
  end;

implementation

const
  cOutcomeKeys: array[TDpccCiOutcome] of string = ('unknown', 'success', 'unstable', 'failure', 'aborted',
    'notBuilt');
  cErrorKeys: array[TDpccCiFetchError] of string = ('', 'notConfigured', 'network', 'timeout', 'unauthorized',
    'notFound', 'server', 'invalid', 'cancelled', 'unknownProvider', 'noCredentials');

{ TDpccCiBuild }

class function TDpccCiBuild.Empty: TDpccCiBuild;
begin
  Result := Default(TDpccCiBuild);
  Result.Failures := nil;
end;

class function TDpccCiBuild.OutcomeKey(AOutcome: TDpccCiOutcome): string;
begin
  Result := cOutcomeKeys[AOutcome];
end;

class function TDpccCiBuild.OutcomeOf(const AKey: string): TDpccCiOutcome;
var
  mOutcome: TDpccCiOutcome;
begin
  for mOutcome := Low(TDpccCiOutcome) to High(TDpccCiOutcome) do
  begin
    if SameText(cOutcomeKeys[mOutcome], AKey) then
    begin
      Exit(mOutcome);
    end;
  end;
  Result := TDpccCiOutcome.Unknown;
end;

class function TDpccCiBuild.ErrorKey(AError: TDpccCiFetchError): string;
begin
  Result := cErrorKeys[AError];
end;

class function TDpccCiBuild.ErrorOf(const AKey: string): TDpccCiFetchError;
var
  mError: TDpccCiFetchError;
begin
  if AKey = '' then
  begin
    Exit(TDpccCiFetchError.None);
  end;
  for mError := Succ(Low(TDpccCiFetchError)) to High(TDpccCiFetchError) do
  begin
    if SameText(cErrorKeys[mError], AKey) then
    begin
      Exit(mError);
    end;
  end;
  // Unbekannte Kennung aus einer neueren Fassung: als Netzfehler zeigen.
  Result := TDpccCiFetchError.Network;
end;

{ TDpccCiJob }

class function TDpccCiJob.Create(const AProvider, AUrl, AJob: string; AMultibranch: Boolean;
  const ABranch: string): TDpccCiJob;
begin
  Result.Provider := LowerCase(Trim(AProvider));
  Result.Url := Trim(AUrl);
  while (Result.Url <> '') and (Result.Url[Length(Result.Url)] = '/') do
  begin
    Delete(Result.Url, Length(Result.Url), 1);
  end;
  Result.Job := Trim(AJob);
  while (Result.Job <> '') and (Result.Job[1] = '/') do
  begin
    Delete(Result.Job, 1, 1);
  end;
  while (Result.Job <> '') and (Result.Job[Length(Result.Job)] = '/') do
  begin
    Delete(Result.Job, Length(Result.Job), 1);
  end;
  Result.Multibranch := AMultibranch;
  Result.Branch := Trim(ABranch);
end;

function TDpccCiJob.Configured: Boolean;
begin
  Result := (Provider <> '') and (Server <> '') and (Job <> '') and (not Multibranch or (Branch <> ''));
end;

function TDpccCiJob.JobBranch: string;
begin
  Result := '';
  if Multibranch then
  begin
    Result := Branch;
  end;
end;

function TDpccCiJob.Key: string;
begin
  Result := LowerCase(Provider + '|' + Url + '|' + Job + '|' + JobBranch);
end;

function TDpccCiJob.Server: string;
var
  mRest: string;
  mScheme: string;
  mIndex: Integer;
begin
  Result := '';
  if SameText(Copy(Url, 1, 8), 'https://') then
  begin
    mScheme := 'https://';
  end
  else if SameText(Copy(Url, 1, 7), 'http://') then
  begin
    mScheme := 'http://';
  end
  else
  begin
    Exit;
  end;
  mRest := Copy(Url, Length(mScheme) + 1, MaxInt);
  mIndex := Pos('/', mRest);
  if mIndex > 0 then
  begin
    mRest := Copy(mRest, 1, mIndex - 1);
  end;
  // Benutzer in der Adresse („user@host“) lässt .dpcc nicht zu; hier trotzdem nie übernehmen.
  if (mRest = '') or (Pos('@', mRest) > 0) or (Pos(' ', mRest) > 0) then
  begin
    Exit;
  end;
  Result := LowerCase(mScheme + mRest);
end;

function TDpccCiJob.CredentialTarget: string;
begin
  Result := '';
  if Server <> '' then
  begin
    Result := 'dpcc:ci:' + Server;
  end;
end;

function TDpccCiJob.Secure: Boolean;
begin
  Result := SameText(Copy(Server, 1, 8), 'https://');
end;

end.
