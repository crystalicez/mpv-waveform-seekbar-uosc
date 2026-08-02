$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Report = Join-Path $Root 'uosc-waveform-diagnostic-report.txt'
$Lines = New-Object System.Collections.Generic.List[string]
function Add-Line([string]$Text) { $Lines.Add($Text); Write-Host $Text }
function Check-Config([string]$Label, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    Add-Line ""
    Add-Line "[$Label] $Path"
    Add-Line ("  exists: " + (Test-Path $Path))
    Add-Line ("  waveform entry: " + (Test-Path (Join-Path $Path 'scripts\uosc-waveform.lua')))
    Add-Line ("  waveform modules: " + (Test-Path (Join-Path $Path 'scripts\uosc_waveform\controller.lua')))
    Add-Line ("  waveform config: " + (Test-Path (Join-Path $Path 'script-opts\uosc-waveform.conf')))
    Add-Line ("  uosc.lua: " + (Test-Path (Join-Path $Path 'scripts\uosc.lua')))
    Add-Line ("  uosc main.lua: " + (Test-Path (Join-Path $Path 'scripts\uosc\main.lua')))
    Add-Line ("  internal log: " + (Test-Path (Join-Path $Path 'uosc-waveform.log')))
}

Add-Line "uosc-waveform diagnostic"
Add-Line ("generated: " + (Get-Date -Format o))
Add-Line ("script root: " + $Root)

$mpvHere = Join-Path $Root 'mpv.exe'
$mpvnetHere = Join-Path $Root 'mpvnet.exe'
Add-Line ("mpv.exe next to script: " + (Test-Path $mpvHere))
Add-Line ("mpvnet.exe next to script: " + (Test-Path $mpvnetHere))
$mpvPath = (Get-Command mpv.exe).Source
$mpvnetPath = (Get-Command mpvnet.exe).Source
$ffmpegPath = (Get-Command ffmpeg.exe).Source
Add-Line ("mpv.exe on PATH: " + $(if ($mpvPath) {$mpvPath} else {'not found'}))
Add-Line ("mpvnet.exe on PATH: " + $(if ($mpvnetPath) {$mpvnetPath} else {'not found'}))
Add-Line ("ffmpeg.exe on PATH: " + $(if ($ffmpegPath) {$ffmpegPath} else {'not found'}))
Add-Line ("ffmpeg.exe next to player/package: " + (Test-Path (Join-Path $Root 'ffmpeg.exe')))
Add-Line ("MPV_HOME: " + $env:MPV_HOME)
Add-Line ("MPVNET_HOME: " + $env:MPVNET_HOME)

Check-Config 'package portable_config' (Join-Path $Root 'portable_config')
Check-Config 'mpv standard' (Join-Path $env:APPDATA 'mpv')
Check-Config 'mpv.net standard' (Join-Path $env:APPDATA 'mpv.net')
if ($env:MPV_HOME) { Check-Config 'MPV_HOME' $env:MPV_HOME }
if ($env:MPVNET_HOME) { Check-Config 'MPVNET_HOME' $env:MPVNET_HOME }
if (Test-Path $mpvHere) { Check-Config 'mpv portable beside executable' (Join-Path $Root 'portable_config') }
if (Test-Path $mpvnetHere) { Check-Config 'mpv.net portable beside executable' (Join-Path $Root 'portable_config') }

Add-Line ""
Add-Line "Startup is silent by default. Press Alt+Shift+W to show waveform status and paths."
Add-Line "Press Alt+Shift+W in the player for current state and actual log path."
$Lines | Set-Content -LiteralPath $Report -Encoding UTF8
Write-Host ""
Write-Host "Report written to: $Report"
Read-Host 'Press Enter to close'
