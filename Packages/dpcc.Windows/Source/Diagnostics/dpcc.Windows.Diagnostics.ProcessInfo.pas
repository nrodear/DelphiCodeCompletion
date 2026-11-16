unit dpcc.Windows.Diagnostics.ProcessInfo;

// Platform-Feature "Diagnostics": Angaben zum eigenen Prozess für die Start-
// und Endzeile des Diagnoselogs (#647), z. B. die Zahl der Threads.
// Speicher des Prozesses (Selbstmessung a0): Private Bytes, Working Set und Spitze über GetProcessMemoryInfo, dazu
// die größte freie Region des Adressraums (VirtualQuery). GetMemoryManagerState sieht in der IDE nichts, weil dort
// der gemeinsame Speichermanager borlndmm.dll arbeitet.

interface

type
  /// <summary>Speicher des eigenen Prozesses in Byte; Valid = False, wenn die Abfrage scheiterte.</summary>
  TProcessMemory = record
    /// <summary>Zugesagter privater Speicher (PROCESS_MEMORY_COUNTERS_EX.PrivateUsage).</summary>
    PrivateBytes: Int64;
    WorkingSetBytes: Int64;
    /// <summary>Höchster Stand der privaten Zusage seit Prozessstart (PeakPagefileUsage).</summary>
    PeakPrivateBytes: Int64;
    /// <summary>Größte zusammenhängende freie Region des Adressraums (MEM_FREE); -1 = unbekannt.</summary>
    LargestFreeBytes: Int64;
    Valid: Boolean;
  end;

  TProcessInfo = record
  public
    /// <summary>Speicher des eigenen Prozesses (a0); die freie Region kostet einen Lauf über den Adressraum
    /// (einige tausend Regionen, unter 1 ms bis wenige ms).</summary>
    class function Memory: TProcessMemory; static;
    /// <summary>Größte freie Region des Adressraums in Byte; -1, wenn die Abfrage scheitert.</summary>
    class function LargestFreeRegion: Int64; static;
    /// <summary>Threads des eigenen Prozesses; -1, wenn die Abfrage scheitert.</summary>
    class function ThreadCount: Integer; static;
    /// <summary>Benutzer- und Rechnername; der Filter des Diagnoselogs verwirft Zeilen, die sie enthalten.</summary>
    class function IdentityNames: TArray<string>; static;
    /// <summary>Rechenzeit (Kernel und Benutzer) des aufrufenden Threads in ms; -1, wenn die Abfrage scheitert.
    /// Liegt sie weit unter der Laufzeit einer Anfrage, hat der Thread gewartet (#647).</summary>
    class function ThreadCpuMs: Int64; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.TlHelp32,
  Winapi.PsAPI,
  System.SysUtils;

class function TProcessInfo.LargestFreeRegion: Int64;
var
  mSystem: TSystemInfo;
  mAddress, mLast, mNext: Int64;
  mInfo: TMemoryBasicInformation;
begin
  Result := -1;
  GetSystemInfo(mSystem);
  // In Int64 gerechnet: Im 32-Bit-Prozess mit 4 GB Adressraum endet die letzte Region an 2^32.
  mAddress := Int64(NativeUInt(mSystem.lpMinimumApplicationAddress));
  mLast := Int64(NativeUInt(mSystem.lpMaximumApplicationAddress));
  while mAddress < mLast do
  begin
    if VirtualQuery(Pointer(NativeUInt(mAddress)), mInfo, SizeOf(mInfo)) <> SizeOf(mInfo) then
    begin
      Break;
    end;
    if (mInfo.State = MEM_FREE) and (Int64(mInfo.RegionSize) > Result) then
    begin
      Result := Int64(mInfo.RegionSize);
    end;
    mNext := Int64(NativeUInt(mInfo.BaseAddress)) + Int64(mInfo.RegionSize);
    if mNext <= mAddress then
    begin
      Break;
    end;
    mAddress := mNext;
  end;
end;

class function TProcessInfo.Memory: TProcessMemory;
var
  mCounters: TProcessMemoryCountersEx;
begin
  Result := Default(TProcessMemory);
  Result.LargestFreeBytes := LargestFreeRegion;
  FillChar(mCounters, SizeOf(mCounters), 0);
  mCounters.cb := SizeOf(mCounters);
  if not GetProcessMemoryInfo(GetCurrentProcess, PPROCESS_MEMORY_COUNTERS(@mCounters), SizeOf(mCounters)) then
  begin
    Exit;
  end;
  Result.PrivateBytes := mCounters.PrivateUsage;
  Result.WorkingSetBytes := mCounters.WorkingSetSize;
  Result.PeakPrivateBytes := mCounters.PeakPagefileUsage;
  Result.Valid := True;
end;

class function TProcessInfo.ThreadCount: Integer;
var
  mSnapshot: THandle;
  mEntry: TThreadEntry32;
  mProcessId: DWORD;
begin
  mSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if mSnapshot = INVALID_HANDLE_VALUE then
  begin
    Exit(-1);
  end;
  try
    mProcessId := GetCurrentProcessId;
    Result := 0;
    mEntry.dwSize := SizeOf(mEntry);
    if Thread32First(mSnapshot, mEntry) then
      repeat
        if mEntry.th32OwnerProcessID = mProcessId then
        begin
          Inc(Result);
        end;
      until not Thread32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
  end;
end;

class function TProcessInfo.ThreadCpuMs: Int64;
var
  mCreation, mExited, mKernel, mUser: TFileTime;
begin
  if not GetThreadTimes(GetCurrentThread, mCreation, mExited, mKernel, mUser) then
  begin
    Exit(-1);
  end;
  // FILETIME zählt in 100 ns.
  Result := (Int64(mKernel.dwHighDateTime) shl 32 + mKernel.dwLowDateTime +
    Int64(mUser.dwHighDateTime) shl 32 + mUser.dwLowDateTime) div 10000;
end;

class function TProcessInfo.IdentityNames: TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in TArray<string>.Create(GetEnvironmentVariable('USERNAME'), GetEnvironmentVariable('COMPUTERNAME'),
    GetEnvironmentVariable('USERDOMAIN')) do
  begin
    if mName <> '' then
    begin
      Result := Result + [mName];
    end;
  end;
end;

end.
