[CmdletBinding(DefaultParameterSetName='Launch')]
param(
    [Parameter(Mandatory, ParameterSetName='Launch')]
    [string]$MpvPath,

    [Parameter(Mandatory, ParameterSetName='Attach')]
    [int]$ProcessId,

    [Parameter(ParameterSetName='Launch')]
    [string]$ConfigDir = "$env:APPDATA\mpv",

    [Parameter(ParameterSetName='Launch')]
    [string[]]$MediaPaths = @(),

    [ValidateRange(1, 72)]
    [int]$DurationHours = 8,

    [ValidateRange(10, 3600)]
    [int]$SampleIntervalSeconds = 600,

    [ValidateRange(64, 1048576)]
    [int]$MaxCacheMB = 512,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\soak-results'),

    [switch]$KeepLaunchedMpv
)

$ErrorActionPreference = 'Stop'
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvPath = Join-Path $OutputDirectory "uosc-waveform-soak-$timestamp.csv"
$summaryPath = Join-Path $OutputDirectory "uosc-waveform-soak-$timestamp.txt"
$launched = $false
$mpv = $null

function Get-ChildProcesses([int]$ParentId) {
    @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ParentId" -ErrorAction SilentlyContinue)
}

function Get-CacheSnapshot([string]$Root) {
    if (-not (Test-Path $Root)) {
        return [pscustomobject]@{ Bytes = 0L; Payloads = 0; Manifests = 0; Temps = 0; Locks = 0; OldAux = 0 }
    }
    $files = @(Get-ChildItem $Root -File -ErrorAction SilentlyContinue)
    $cutoff = (Get-Date).AddMinutes(-15)
    [pscustomobject]@{
        Bytes = [long](($files | Measure-Object Length -Sum).Sum)
        Payloads = @($files | Where-Object Extension -eq '.bgra').Count
        Manifests = @($files | Where-Object Extension -eq '.meta').Count
        Temps = @($files | Where-Object Name -Match '\.tmp(\.meta\.tmp)?$').Count
        Locks = @($files | Where-Object Extension -eq '.lock').Count
        OldAux = @($files | Where-Object { ($_.Extension -eq '.lock' -or $_.Name -match '\.tmp') -and $_.LastWriteTime -lt $cutoff }).Count
    }
}

try {
    if ($PSCmdlet.ParameterSetName -eq 'Launch') {
        $resolvedMpv = (Resolve-Path $MpvPath).Path
        $arguments = @("--config-dir=$ConfigDir", '--idle=yes', '--keep-open=yes', '--loop-playlist=inf')
        foreach ($media in $MediaPaths) { $arguments += [IO.Path]::GetFullPath($media) }
        $mpv = Start-Process -FilePath $resolvedMpv -ArgumentList $arguments -PassThru
        $launched = $true
        Start-Sleep -Seconds 3
    } else {
        $mpv = Get-Process -Id $ProcessId -ErrorAction Stop
        $ConfigDir = "$env:APPDATA\mpv"
    }

    $cacheDir = Join-Path $ConfigDir 'cache\uosc-waveform'
    $started = Get-Date
    $deadline = $started.AddHours($DurationHours)
    $lastCpu = [double]$mpv.CPU
    $lastSample = Get-Date
    $rows = [Collections.Generic.List[object]]::new()
    $failures = [Collections.Generic.List[string]]::new()

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $SampleIntervalSeconds
        $mpv.Refresh()
        if ($mpv.HasExited) { $failures.Add('mpv exited before the soak deadline'); break }

        $now = Get-Date
        $elapsedSeconds = [Math]::Max(0.001, ($now - $lastSample).TotalSeconds)
        $cpuNow = [double]$mpv.CPU
        $cpuPercent = (($cpuNow - $lastCpu) / $elapsedSeconds) * 100.0
        $lastCpu = $cpuNow
        $lastSample = $now

        $children = Get-ChildProcesses $mpv.Id
        $ffmpegCim = @($children | Where-Object Name -Match '^ffmpeg(\.exe)?$')
        $ffmpegProcesses = @()
        foreach ($child in $ffmpegCim) {
            $process = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
            if ($process) { $ffmpegProcesses += $process }
        }
        $ffmpegPrivate = [long](($ffmpegProcesses | Measure-Object PrivateMemorySize64 -Sum).Sum)
        $cache = Get-CacheSnapshot $cacheDir
        $row = [pscustomobject]@{
            Timestamp = $now.ToString('o')
            ElapsedMinutes = [Math]::Round(($now - $started).TotalMinutes, 2)
            MpvCpuPercentOneCore = [Math]::Round($cpuPercent, 2)
            MpvWorkingSetMB = [Math]::Round($mpv.WorkingSet64 / 1MB, 2)
            MpvPrivateMB = [Math]::Round($mpv.PrivateMemorySize64 / 1MB, 2)
            MpvHandles = $mpv.HandleCount
            FfmpegCount = $ffmpegProcesses.Count
            FfmpegPrivateMB = [Math]::Round($ffmpegPrivate / 1MB, 2)
            CacheMB = [Math]::Round($cache.Bytes / 1MB, 2)
            CachePayloads = $cache.Payloads
            CacheManifests = $cache.Manifests
            CacheTemps = $cache.Temps
            CacheLocks = $cache.Locks
            CacheOldAux = $cache.OldAux
        }
        $rows.Add($row)
        $row | Export-Csv -Path $csvPath -NoTypeInformation -Append
        Write-Host ($row | Format-List | Out-String)

        if ($ffmpegProcesses.Count -gt 1) { $failures.Add("more than one FFmpeg child at $($row.Timestamp)") }
        if ($cache.OldAux -gt 0) { $failures.Add("stale .tmp/.lock files at $($row.Timestamp)") }
        if ($cache.Bytes -gt ($MaxCacheMB * 1MB * 1.10)) { $failures.Add("cache exceeded 110% of configured target at $($row.Timestamp)") }
        if ($cache.Payloads -ne $cache.Manifests) { $failures.Add("cache payload/manifest count mismatch at $($row.Timestamp)") }
    }

    if ($rows.Count -ge 6) {
        $first = $rows[0]
        $last = $rows[$rows.Count - 1]
        $privateGrowth = $last.MpvPrivateMB - $first.MpvPrivateMB
        $handleGrowth = $last.MpvHandles - $first.MpvHandles
        if ($privateGrowth -gt 128) { $failures.Add("mpv private memory grew by $privateGrowth MB") }
        if ($handleGrowth -gt 256) { $failures.Add("mpv handles grew by $handleGrowth") }
    }

    $summary = @(
        'uosc-waveform Windows soak',
        "started=$($started.ToString('o'))",
        "finished=$((Get-Date).ToString('o'))",
        "mpv_pid=$($mpv.Id)",
        "samples=$($rows.Count)",
        "csv=$csvPath",
        "result=$(if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' })",
        'failures:'
    ) + $(if ($failures.Count -eq 0) { @('none') } else { @($failures | Select-Object -Unique) })
    $summary | Set-Content -Encoding UTF8 $summaryPath
    Get-Content $summaryPath
    if ($failures.Count -ne 0) { exit 1 }
} finally {
    if ($launched -and $mpv -and -not $KeepLaunchedMpv) {
        Stop-Process -Id $mpv.Id -ErrorAction SilentlyContinue
    }
}
