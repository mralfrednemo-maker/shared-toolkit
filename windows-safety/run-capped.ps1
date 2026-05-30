# run-capped.ps1 — Run a command inside a Windows Job Object with hard resource caps.
#
# Caps enforced on the entire process tree (child processes inherit the job):
#   - RAM:    48 GB  (leaves 16 GB for Windows + your Chrome + Claude Code)
#   - CPU:    70%    (leaves 30% for the OS and interactive apps)
#   - Priority: BelowNormal
#   - KillOnJobClose: yes  (Ctrl+C on wrapper kills everything)
#
# If the child tree exceeds RAM cap, the kernel terminates it — your laptop stays alive.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File run-capped.ps1 -- <command> <args...>
#
# Examples:
#   .\run-capped.ps1 -- python.exe C:\path\to\watchdog.py --question "..." --brief brief.txt
#   .\run-capped.ps1 -RamGB 32 -CpuPct 50 -- python.exe my-script.py
#
# Notes:
#   - Job Objects cap CPU + RAM cleanly. GPU is NOT capped (Windows limitation).
#     If the freeze was a GPU/WDDM hang, this won't prevent it — but it will
#     stop the runaway process from compounding the problem.
#   - Requires Windows PowerShell 5.1 or PowerShell 7+. No admin needed.

[CmdletBinding()]
param(
    [int]$RamGB = 48,
    [int]$CpuPct = 70,
    [ValidateSet('Idle','BelowNormal','Normal')]
    [string]$Priority = 'BelowNormal',
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Command
)

if (-not $Command -or $Command.Count -eq 0) {
    Write-Error "No command supplied. Usage: run-capped.ps1 -- <exe> <args...>"
    exit 2
}
# Strip leading '--' separator if present
if ($Command[0] -eq '--') { $Command = $Command[1..($Command.Count-1)] }

$exe  = $Command[0]
$args = if ($Command.Count -gt 1) { $Command[1..($Command.Count-1)] } else { @() }

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class JobObj {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr CreateJobObject(IntPtr a, string lpName);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProc);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_CPU_RATE_CONTROL_INFORMATION {
        public uint ControlFlags;
        public uint CpuRate;
    }

    public const int JobObjectExtendedLimitInformation = 9;
    public const int JobObjectCpuRateControlInformation = 15;

    public const uint LIMIT_JOB_MEMORY         = 0x00000200;
    public const uint LIMIT_KILL_ON_JOB_CLOSE   = 0x00002000;
    public const uint LIMIT_PRIORITY_CLASS      = 0x00000020;

    public const uint CPU_RATE_ENABLE           = 0x1;
    public const uint CPU_RATE_HARD_CAP         = 0x4;
}
"@

$job = [JobObj]::CreateJobObject([IntPtr]::Zero, $null)
if ($job -eq [IntPtr]::Zero) { throw "CreateJobObject failed" }

# Priority class mapping
$priorityClass = switch ($Priority) {
    'Idle'        { 0x00000040 }
    'BelowNormal' { 0x00004000 }
    'Normal'      { 0x00000020 }
}

$ext = New-Object JobObj+JOBOBJECT_EXTENDED_LIMIT_INFORMATION
$ext.BasicLimitInformation.LimitFlags =
    [JobObj]::LIMIT_JOB_MEMORY -bor
    [JobObj]::LIMIT_KILL_ON_JOB_CLOSE -bor
    [JobObj]::LIMIT_PRIORITY_CLASS
$ext.BasicLimitInformation.PriorityClass = $priorityClass
$ext.JobMemoryLimit = [UIntPtr]::new([uint64]$RamGB * 1GB)

$extSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][JobObj+JOBOBJECT_EXTENDED_LIMIT_INFORMATION])
$extPtr  = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($extSize)
try {
    [System.Runtime.InteropServices.Marshal]::StructureToPtr($ext, $extPtr, $false)
    if (-not [JobObj]::SetInformationJobObject($job, [JobObj]::JobObjectExtendedLimitInformation, $extPtr, [uint32]$extSize)) {
        throw "SetInformationJobObject(Extended) failed: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
} finally {
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($extPtr)
}

# CPU rate cap (0-10000 = 0.00% - 100.00%)
$cpu = New-Object JobObj+JOBOBJECT_CPU_RATE_CONTROL_INFORMATION
$cpu.ControlFlags = [JobObj]::CPU_RATE_ENABLE -bor [JobObj]::CPU_RATE_HARD_CAP
$cpu.CpuRate      = [uint32]($CpuPct * 100)

$cpuSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][JobObj+JOBOBJECT_CPU_RATE_CONTROL_INFORMATION])
$cpuPtr  = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($cpuSize)
try {
    [System.Runtime.InteropServices.Marshal]::StructureToPtr($cpu, $cpuPtr, $false)
    if (-not [JobObj]::SetInformationJobObject($job, [JobObj]::JobObjectCpuRateControlInformation, $cpuPtr, [uint32]$cpuSize)) {
        throw "SetInformationJobObject(CpuRate) failed: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
} finally {
    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($cpuPtr)
}

Write-Host "[run-capped] RAM cap: $RamGB GB | CPU cap: $CpuPct% | Priority: $Priority"
Write-Host "[run-capped] Exec: $exe $($args -join ' ')"

# Start suspended so we can assign to job BEFORE it forks children
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName  = $exe
$psi.Arguments = ($args | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
$psi.UseShellExecute = $false

$proc = [System.Diagnostics.Process]::Start($psi)
if (-not [JobObj]::AssignProcessToJobObject($job, $proc.Handle)) {
    Write-Warning "AssignProcessToJobObject failed: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
}

$proc.WaitForExit()
$code = $proc.ExitCode
[JobObj]::CloseHandle($job) | Out-Null
Write-Host "[run-capped] Child exited with code $code"
exit $code
