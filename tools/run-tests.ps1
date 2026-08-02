[CmdletBinding()]
param(
    [string]$LuaBin = $env:LUA_BIN,
    [switch]$SkipFfmpegIntegration
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Scripts = Join-Path $Root 'portable_config\scripts'
$Entry = Join-Path $Scripts 'uosc-waveform.lua'

if (-not $LuaBin) {
    foreach ($candidate in @('lua54.exe', 'lua5.4.exe', 'lua.exe', 'luajit.exe')) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) { $LuaBin = $candidate; break }
    }
}
if (-not $LuaBin) { throw 'No Lua interpreter found. Set LUA_BIN to the executable path.' }

$script:Passed = 0
$script:Failed = 0
$TempConfig = Join-Path ([IO.Path]::GetTempPath()) ("uosc-waveform-test-config-" + $PID)

function Invoke-TestCase {
    param([string]$Label, [string[]]$Arguments)
    Write-Host ($Label.PadRight(44)) -NoNewline
    & $LuaBin @Arguments
    if ($LASTEXITCODE -eq 0) {
        $script:Passed++
        Write-Host ' PASS'
    } else {
        $script:Failed++
        Write-Host ' FAIL'
    }
}

try {
    Get-ChildItem (Join-Path $Root 'tests\*.lua') | Sort-Object Name | ForEach-Object {
        $name = $_.BaseName
        Remove-Item $TempConfig -Recurse -Force -ErrorAction SilentlyContinue
        switch -Regex ($name) {
            '^syntax_check$' {
                $runtime = Get-ChildItem $Scripts -Recurse -File -Filter '*.lua' | Sort-Object FullName | ForEach-Object FullName
                Invoke-TestCase -Label $name -Arguments (@($_.FullName) + @($runtime))
                break
            }
            '^(controller_mouse_fade|controller_mouse_proximity|controller_nonstandard_uosc)$' {
                Invoke-TestCase -Label $name -Arguments @($_.FullName, $Scripts)
                break
            }
            '^(bootstrap_single_file|startup_osd_silent)$' {
                Invoke-TestCase -Label $name -Arguments @($_.FullName, $Entry, $TempConfig)
                break
            }
            default {
                Invoke-TestCase -Label $name -Arguments @($_.FullName, $Root)
            }
        }
    }

    Get-ChildItem (Join-Path $Root 'tests\stress\*.lua') | Sort-Object Name | ForEach-Object {
        Invoke-TestCase -Label ("stress/" + $_.BaseName) -Arguments @($_.FullName, $Root)
    }

    if (-not $SkipFfmpegIntegration -and $env:SKIP_FFMPEG_INTEGRATION -ne '1') {
        $python = Get-Command python.exe -ErrorAction SilentlyContinue
        $ffmpeg = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
        if ($python -and $ffmpeg) {
            Write-Host ('integration/ffmpeg_visual_parity'.PadRight(44)) -NoNewline
            & $python.Source (Join-Path $Root 'tests\integration\ffmpeg_visual_parity.py') --root $Root --lua $LuaBin --ffmpeg $ffmpeg.Source
            if ($LASTEXITCODE -eq 0) { $script:Passed++; Write-Host ' PASS' }
            else { $script:Failed++; Write-Host ' FAIL' }
            Write-Host ('integration/ffmpeg_memory_budget'.PadRight(44)) -NoNewline
            & $python.Source (Join-Path $Root 'tests\integration\ffmpeg_memory_budget.py') --root $Root --lua $LuaBin --ffmpeg $ffmpeg.Source
            if ($LASTEXITCODE -eq 0) { $script:Passed++; Write-Host ' PASS' }
            else { $script:Failed++; Write-Host ' FAIL' }
        } else {
            Write-Host 'integration/ffmpeg_visual_parity          SKIP (python or ffmpeg missing)'
        }
    }
} finally {
    Remove-Item $TempConfig -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "RESULT pass=$script:Passed fail=$script:Failed lua=$LuaBin"
if ($script:Failed -ne 0) { exit 1 }
