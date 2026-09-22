<#
  setup.ps1 - one-time bootstrap for the DeepSeek Harness Windows launcher.

  What it does (idempotent - safe to re-run):
    1. Creates the harness layout next to this script (dsh-home, dsh-workspace).
    2. Installs a PORTABLE PowerShell 7 under %LOCALAPPDATA% when no PowerShell 7
       is available. Without it, dsh's PowerShell executor falls back to Windows
       PowerShell 5.1, which is the source of a whole class of command failures.
    3. Pins that pwsh 7 in <harness>\dsh-home\cordis.patch.yml. dsh applies the
       home-level patch to EVERY profile and hot-reloads it, so no restart is
       needed to activate it.
    4. Creates a desktop shortcut that runs start-dsh.ps1.

  ENCODING - THIS FILE MUST STAY PURE ASCII.
    Windows PowerShell 5.1 decodes a .ps1 that has no BOM using the system ANSI
    code page, not UTF-8. A non-ASCII byte can therefore break parsing outright:
    a mangled string literal loses its closing quote and the whole script fails
    with "TerminatorExpectedAtEndOfString". Pure ASCII is immune either way.

  Requires: Windows PowerShell 5.1 or newer, and internet access on first run.
#>

[CmdletBinding()]
param(
    # Where the harness lives. Defaults to the folder containing this script.
    [string] $HarnessRoot = (Split-Path -Parent $PSCommandPath),

    # Write the layout, patch and shortcut but do not download PowerShell 7.
    [switch] $SkipPowerShell7,

    # Do not create the shortcut at all.
    [switch] $SkipShortcut,

    # Where to put the "DeepSeek Harness" shortcut: Desktop (default) or StartMenu.
    # StartMenu keeps the desktop clear; the entry then shows up under Start > All
    # apps and is searchable, ready to be pinned to Start.
    [ValidateSet('Desktop', 'StartMenu')]
    [string] $ShortcutLocation = 'Desktop'
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 needs this before it can talk to GitHub over TLS.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    # Older runtimes may not know Tls12; leave the default in place.
}

function Write-Step {
    param([string] $Number, [string] $Text)
    Write-Host ''
    Write-Host ("[" + $Number + "] " + $Text) -ForegroundColor Cyan
}
function Write-Ok {
    param([string] $Text)
    Write-Host ("    ok    " + $Text) -ForegroundColor Green
}
function Write-Note {
    param([string] $Text)
    Write-Host ("          " + $Text) -ForegroundColor Gray
}
function Write-Warn {
    param([string] $Text)
    Write-Host ("    warn  " + $Text) -ForegroundColor Yellow
}

# Resolve the latest portable PowerShell 7 zip, falling back to a pinned URL
# when the GitHub API is unreachable (rate limits, proxies, offline mirrors).
function Get-PowerShell7ZipUrl {
    $pinned = 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/PowerShell-7.6.6-win-x64.zip'
    try {
        $api = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
        $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'dsh-setup' } -TimeoutSec 30
        $asset = $release.assets | Where-Object { $_.name -like '*-win-x64.zip' } | Select-Object -First 1
        if ($asset -and $asset.browser_download_url) {
            return [string] $asset.browser_download_url
        }
    } catch {
        Write-Note 'GitHub API unavailable; using the pinned release instead.'
    }
    return $pinned
}

# Write YAML without a BOM: Node and the YAML parsers read UTF-8, and a BOM can
# upset some of them. This is the opposite of the rule for .ps1 files.
function Write-Utf8NoBom {
    param([string] $Path, [string] $Text)
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

# ---------------------------------------------------------------------------

$HarnessRoot = (Resolve-Path -LiteralPath $HarnessRoot).Path
$dshHome     = Join-Path $HarnessRoot 'dsh-home'
$workspace   = Join-Path $HarnessRoot 'dsh-workspace'
$launcher    = Join-Path $HarnessRoot 'start-dsh.ps1'
$patchPath   = Join-Path $dshHome 'cordis.patch.yml'

Write-Host ''
Write-Host 'DeepSeek Harness - Windows setup' -ForegroundColor White
Write-Note ("harness root: " + $HarnessRoot)

# --- 0. prerequisites ------------------------------------------------------
Write-Step '0/4' 'Check prerequisites'

$node = Get-Command node -ErrorAction SilentlyContinue
$npx  = Get-Command npx  -ErrorAction SilentlyContinue
if ($node) {
    Write-Ok ("node " + ((& node --version 2>&1 | Out-String).Trim()) + "  (" + $node.Source + ")")
} else {
    Write-Warn 'node was not found on PATH.'
    Write-Note 'The launcher runs "npx @deepseek-ai/dsh web", so Node.js is required.'
    Write-Note 'Install the LTS build from https://nodejs.org and re-run this script.'
}
if ($npx) {
    Write-Ok ("npx   " + $npx.Source)
} else {
    Write-Warn 'npx was not found on PATH (it normally ships with Node.js).'
}

# --- 1. layout -------------------------------------------------------------
Write-Step '1/4' 'Create the harness layout'
New-Item -ItemType Directory -Force -Path $dshHome | Out-Null
New-Item -ItemType Directory -Force -Path $workspace | Out-Null
Write-Ok ("dsh-home      " + $dshHome)
Write-Ok ("dsh-workspace " + $workspace)

if (-not (Test-Path -LiteralPath $launcher)) {
    Write-Warn 'start-dsh.ps1 is missing from the harness root; copy it there.'

}

# --- 2. PowerShell 7 -------------------------------------------------------
Write-Step '2/4' 'Ensure a PowerShell 7 for the dsh shell executor'

$programFilesPwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
$portablePwsh     = Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\7\pwsh.exe'
$pwshPath         = $null
$pinNeeded        = $false

if (Test-Path -LiteralPath $programFilesPwsh) {
    # dsh probes this well-known location automatically, so no pin is required.
    $pwshPath = $programFilesPwsh
    Write-Ok ("PowerShell 7 already installed at " + $programFilesPwsh)
    Write-Note 'dsh finds this location by itself; no pwshPath pin is needed.'
}
elseif (Test-Path -LiteralPath $portablePwsh) {
    $pwshPath = $portablePwsh
    $pinNeeded = $true
    Write-Ok ("portable PowerShell 7 already present at " + $portablePwsh)
}
else {
    $onPath = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($onPath) {
        $pwshPath = $onPath.Source
        Write-Ok ("found pwsh on PATH: " + $pwshPath)
        Write-Note 'That is one of the dsh probes, but a pin is still written for determinism.'
        $pinNeeded = $true
    }
    elseif ($SkipPowerShell7) {
        Write-Warn 'PowerShell 7 not found and -SkipPowerShell7 was given.'
    }
    else {
        $destination = Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\7'
        $zipPath     = Join-Path $env:TEMP 'PowerShell-7-win-x64.zip'
        $url         = Get-PowerShell7ZipUrl
        Write-Note ("downloading " + $url)
        Write-Note 'This is roughly 100 MB and may take a few minutes.'

        $client = New-Object System.Net.WebClient
        $client.DownloadFile($url, $zipPath)

        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $destination | Out-Null

        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destination)
        } catch {
            Write-Note 'Fast extract failed; falling back to Expand-Archive.'
            Expand-Archive -LiteralPath $zipPath -DestinationPath $destination -Force
        }
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

        $pwshPath = Join-Path $destination 'pwsh.exe'
        $pinNeeded = $true
        Write-Ok ("installed portable PowerShell 7 at " + $destination)
    }
}

if ($pwshPath -and (Test-Path -LiteralPath $pwshPath)) {
    $reported = (& $pwshPath -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' | Out-String).Trim()
    Write-Ok ("pwsh reports version " + $reported)
    if ($reported -notmatch '^7\.') {
        Write-Warn 'That does not look like PowerShell 7; the pin may not help.'
    }
}

# --- 3. dsh patch ----------------------------------------------------------
Write-Step '3/4' 'Pin the shell executor in the home-level dsh patch'

if (-not $pinNeeded) {
    Write-Ok 'Nothing to pin: dsh resolves its shell without a patch.'
}
elseif (-not $pwshPath) {
    Write-Warn 'No pwsh path available; skipping the patch.'
}
else {
    # The profile patch REPLACES the targeted row's whole config, and the
    # dsh-base row for "pwsh-sandbox" carries no config, so replacing it with
    # only pwshPath loses nothing. Single quotes keep YAML from treating the
    # backslashes as escapes.
    $lines = @()
    $lines += '# dsh home-level user patch, applied after every bundle layer.'
    $lines += '# Written by setup.ps1: pin the PowerShell executor to the PowerShell 7'
    $lines += '# below. Without this pin dsh falls back to Windows PowerShell 5.1,'
    $lines += '# because pwsh is not on PATH and PS7 is absent from the well-known'
    $lines += '# location that dsh probes automatically.'
    $lines += '#'
    $lines += '# Delete this file to go back to automatic resolution.'
    $lines += '- id: pwsh-sandbox'
    $lines += '  config:'
    $lines += "    pwshPath: '" + $pwshPath + "'"
    $text = ($lines -join "`r`n") + "`r`n"

    $backup = $patchPath + '.bak'
    if (Test-Path -LiteralPath $patchPath) {
        Copy-Item -LiteralPath $patchPath -Destination $backup -Force
        Write-Note ("previous patch backed up to " + $backup)
    }
    Write-Utf8NoBom -Path $patchPath -Text $text
    Write-Ok ("wrote " + $patchPath)
    Write-Note ("row: pwsh-sandbox -> " + $pwshPath)
    Write-Note 'dsh hot-reloads this file; no restart is needed to activate it.'
}

# --- 4. desktop shortcut ---------------------------------------------------
Write-Step '4/4' 'Build the windowless launcher and create the shortcut'

# The supervisor is a PowerShell script, so it needs a console. On Windows 11
# with Windows Terminal as the default terminal application, launching a console
# app opens a Windows Terminal window even with -WindowStyle Hidden, because that
# flag only hides a console window that already exists. launcher.cs is compiled
# as a GUI-subsystem executable -- no console at all -- and starts the supervisor
# with CreateNoWindow, which asks Windows not to create a console window.
$launcherExe = Join-Path $HarnessRoot 'dsh-launch.exe'
$launcherCs  = Join-Path $HarnessRoot 'launcher.cs'

$buildNeeded = $true
if ((Test-Path -LiteralPath $launcherExe) -and (Test-Path -LiteralPath $launcherCs)) {
    if ((Get-Item -LiteralPath $launcherExe).LastWriteTime -ge (Get-Item -LiteralPath $launcherCs).LastWriteTime) {
        $buildNeeded = $false
        Write-Ok 'dsh-launch.exe is up to date'
    }
}

if ($buildNeeded) {
    $compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $compiler)) {
        $compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }

    if (-not (Test-Path -LiteralPath $compiler)) {
        Write-Warn 'the .NET Framework C# compiler (csc.exe) was not found'
        Write-Note 'the shortcut will fall back to launching PowerShell directly,'
        Write-Note 'which can show a Windows Terminal window.'
    }
    elseif (-not (Test-Path -LiteralPath $launcherCs)) {
        Write-Warn 'launcher.cs is missing; cannot build dsh-launch.exe'
    }
    else {
        $cscArgs = @(
            '/nologo', '/target:winexe', '/optimize+',
            ('/out:' + $launcherExe),
            '/r:System.dll', '/r:System.Windows.Forms.dll',
            $launcherCs
        )
        $buildOutput = & $compiler $cscArgs 2>&1
        if ((Test-Path -LiteralPath $launcherExe) -and (Get-Item -LiteralPath $launcherExe).Length -gt 0) {
            Write-Ok ('built dsh-launch.exe (' + (Get-Item -LiteralPath $launcherExe).Length + ' bytes, GUI subsystem)')
        }
        else {
            Write-Warn 'compiling dsh-launch.exe failed'
            $buildOutput | Select-Object -First 5 | ForEach-Object { Write-Note ([string] $_) }
        }
    }
}

if ($SkipShortcut) {
    Write-Warn 'shortcut skipped (-SkipShortcut)'
}
elseif (-not (Test-Path -LiteralPath $launcher)) {
    Write-Warn 'start-dsh.ps1 not found; not creating a shortcut.'
}
else {
    if ($ShortcutLocation -eq 'StartMenu') {
        $shortcutDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
        Write-Note 'placing the shortcut in the Start Menu; right-click it there'
        Write-Note 'and choose "Pin to Start" if you want a Start tile.'
    }
    else {
        $shortcutDir = [Environment]::GetFolderPath('Desktop')
    }
    New-Item -ItemType Directory -Force -Path $shortcutDir | Out-Null

    $lnkPath  = Join-Path $shortcutDir 'DeepSeek Harness.lnk'
    $shell    = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnkPath)

    if (Test-Path -LiteralPath $launcherExe) {
        $shortcut.TargetPath = $launcherExe
        $shortcut.Arguments  = ''
        Write-Ok 'shortcut targets dsh-launch.exe, so nothing appears on screen'
    }
    else {
        $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shortcut.Arguments  = '-WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcher + '"'
        Write-Warn 'shortcut falls back to powershell.exe; a window may appear'
    }

    $shortcut.WorkingDirectory = $HarnessRoot
    $shortcut.Description      = 'Start the local DeepSeek Harness web interface'
    $shortcut.WindowStyle      = 1

    $iconPath = Join-Path $HarnessRoot 'dsh.ico'
    if (Test-Path -LiteralPath $iconPath) {
        $shortcut.IconLocation = $iconPath + ',0'
        Write-Ok 'using dsh.ico for the shortcut icon'
    }
    else {
        Write-Note 'dsh.ico not present; run make-icon.ps1 after the first launch'
    }

    $shortcut.Save()
    Write-Ok ("created " + $lnkPath)
}

# --- summary ---------------------------------------------------------------
Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor White
Write-Host '  1. Double-click the "DeepSeek Harness" desktop shortcut.'
Write-Host '     Nothing appears on screen; the browser window opens by itself'
Write-Host '     after a few seconds. The first launch downloads dsh and is slow.'
Write-Host '  2. Closing that browser window stops the harness and the launcher.'
Write-Host '  3. Logs live in .\logs: dsh.log (server output), launcher.log'
Write-Host '     (the launcher own decisions).'
Write-Host '  4. If the window is ever left running with nothing attached, run'
Write-Host '     .\stop-dsh.cmd.'
Write-Host '  5. Optionally run .\make-icon.ps1 afterwards to build dsh.ico from'
Write-Host '     the frontend asset that the first launch installed.'
Write-Host ''
Write-Host 'Everything the harness creates lives under:' -ForegroundColor White
Write-Host ('  ' + $dshHome)
Write-Host '  (config, credentials, sessions, the isolated browser profile)'
Write-Host '  Delete that folder to reset the harness completely.'
Write-Host ''
