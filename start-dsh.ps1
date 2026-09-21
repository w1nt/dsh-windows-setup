# ===========================================================================
# DeepSeek Harness - Windows launcher (supervisor)
#
# Runs with a HIDDEN console and stays alive for the whole session:
#   1. Rotates the logs: current run plus two previous ones.
#   2. Stops a leftover server from an earlier run, if one is still alive.
#   3. Starts "dsh web --no-open" hidden, redirecting its output into
#      logs\dsh.log - this is the text that used to scroll in the console.
#   4. Polls that log until dsh prints its authenticated URL.
#   5. Opens the URL in a chromeless app window on a DEDICATED browser
#      profile, so the harness stays out of your normal browsing.
#   6. Watches for that browser to exit, then stops the server and exits.
#
# Closing the browser window therefore shuts the harness down.
#
# Files it owns
#   logs\dsh.log        server output, current run
#   logs\dsh.1.log      server output, previous run
#   logs\dsh.2.log      server output, the run before that
#   logs\launcher.log   this supervisor's own decisions and diagnostics
#   run\server.pid      pid of the running server (used by stop-dsh.ps1)
#
# ENCODING NOTE - DO NOT ADD NON-ASCII CHARACTERS TO THIS FILE
#   Windows PowerShell 5.1 decodes a .ps1 that has no BOM using the system
#   ANSI code page, not UTF-8. A non-ASCII byte can break parsing outright:
#   a mangled string literal loses its closing quote and the whole script
#   fails with "TerminatorExpectedAtEndOfString". Pure ASCII is immune
#   whether or not a BOM is present.
#
# QUOTING NOTE - Start-Process -ArgumentList DOES NOT QUOTE AN ARRAY
#   Given an array it joins the elements with spaces and adds no quoting, so
#   any element containing a space is split into two arguments. The profile
#   path below contains a space whenever the user name does. Browser
#   arguments are therefore assembled as ONE quoted string, never an array.
#   The call operator "&" does quote correctly and is safe to use.
#
# Deliberately avoided: the automatic variable $PID. The server's own process
# id lives in $serverPid so nothing here clobbers $PID.
# ===========================================================================

[CmdletBinding()]
param(
    # How often to check whether the browser window is still open, in seconds.
    [int] $BrowserPollSeconds = 3,

    # Consecutive empty checks before the browser counts as closed. Absorbs the
    # brief gap while Chrome tears its process tree down.
    [int] $BrowserMissesBeforeStop = 2,

    # How long to wait for dsh to print its URL. Generous because a first run
    # downloads dsh itself.
    [int] $UrlTimeoutSeconds = 600,

    # How long to wait for the browser process to appear after we launch it.
    [int] $BrowserAppearTimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'

$root      = Split-Path -Parent $PSCommandPath
$workspace = Join-Path $root 'dsh-workspace'
$dshHome   = Join-Path $root 'dsh-home'
$logDir    = Join-Path $root 'logs'
$runDir    = Join-Path $root 'run'
$serverLog = Join-Path $logDir 'dsh.log'
$launchLog = Join-Path $logDir 'launcher.log'
$pidFile   = Join-Path $runDir 'server.pid'

foreach ($dir in @($workspace, $logDir, $runDir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# DSH_HOME is what makes this launch self-contained: config, credentials,
# sessions and the browser profile all live under .\dsh-home.
$env:DSH_HOME = $dshHome
$cachePath = Join-Path $dshHome 'npm-cache'
$env:npm_config_cache = $cachePath

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-LauncherLog {
    param([string] $Message)
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = '[' + $stamp + '] ' + $Message + "`r`n"
    try {
        [System.IO.File]::AppendAllText($launchLog, $line, $utf8NoBom)
    } catch {
        # Never let a logging failure take the launcher down.
    }
}

function Rotate-Log {
    param([string] $Path)
    $dir   = Split-Path -Parent $Path
    $base  = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext   = [System.IO.Path]::GetExtension($Path)
    $slot2 = Join-Path $dir ($base + '.2' + $ext)
    $slot1 = Join-Path $dir ($base + '.1' + $ext)
    if (Test-Path -LiteralPath $slot2) { Remove-Item -LiteralPath $slot2 -Force }
    if (Test-Path -LiteralPath $slot1) { Move-Item -LiteralPath $slot1 -Destination $slot2 -Force }
    if (Test-Path -LiteralPath $Path)  { Move-Item -LiteralPath $Path  -Destination $slot1 -Force }
}

# Read a file another process is still writing, without holding a lock on it.
function Read-TextShared {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        return $reader.ReadToEnd()
    } catch {
        return ''
    } finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
}

function Test-PortBusy {
    param([int] $Port)
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect('127.0.0.1', $Port)
        return $true
    } catch {
        return $false
    } finally {
        if ($client) { $client.Close() }
    }
}

# Stop a process and everything below it.
#
# Primary path is taskkill /T, which walks the child tree for us. That is the
# normal case for a user-run script. A restricted environment can refuse
# taskkill outright ("ERROR: Access denied"), and an orphaned server would then
# keep running with no window and no console - the worst outcome for this
# design. So there is a fallback that does not use taskkill at all: every
# process belonging to this harness mentions the npm cache directory inside
# .\dsh-home on its command line. Only node/cmd/npx rows are considered, so the
# browser and the supervisor itself are never matched.
function Stop-ProcessTree {
    param([int] $TargetPid)

    $null = & taskkill.exe /PID $TargetPid /T /F 2>&1
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue)) {
        return $true
    }

    Write-LauncherLog ('taskkill did not remove pid ' + $TargetPid + '; using the path-based fallback')

    $removed = 0
    foreach ($image in @("Name='node.exe'", "Name='cmd.exe'", "Name='npx.exe'")) {
        try {
            $rows = Get-CimInstance Win32_Process -Filter $image -ErrorAction Stop
            foreach ($row in $rows) {
                if ($row.CommandLine -and $row.CommandLine -like "*$cachePath*") {
                    try {
                        Stop-Process -Id $row.ProcessId -Force -ErrorAction Stop
                        $removed++
                    } catch {
                        Write-LauncherLog ('could not stop pid ' + $row.ProcessId + ': ' + $_.Exception.Message)
                    }
                }
            }
        } catch {
            Write-LauncherLog ('fallback query failed: ' + $_.Exception.Message)
        }
    }

    try { Stop-Process -Id $TargetPid -Force -ErrorAction Stop; $removed++ } catch { }
    Start-Sleep -Milliseconds 500

    $gone = -not (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue)
    Write-LauncherLog ('fallback stopped ' + $removed + ' processes; target gone: ' + $gone)
    return $gone
}

# Processes of the harness browser, identified by our profile path appearing in
# their command line. Verified on a machine where an unrelated Chrome is also
# running: the two sets separate cleanly (8 matching vs 20 not matching).
function Get-HarnessBrowserProcesses {
    param([string] $ImagePattern)
    try {
        $all = Get-CimInstance Win32_Process -Filter $ImagePattern -ErrorAction Stop
        return @($all | Where-Object { $_.CommandLine -and $_.CommandLine -like "*$browserProfile*" })
    } catch {
        Write-LauncherLog ('Win32_Process query failed: ' + $_.Exception.Message)
        return $null
    }
}

Write-LauncherLog '--- launcher start ---'

# --- 1. rotate logs ---------------------------------------------------------
Rotate-Log -Path $serverLog
Rotate-Log -Path $launchLog

# --- 2. stop a leftover server ---------------------------------------------
if (Test-Path -LiteralPath $pidFile) {
    $previous = 0
    [void][int]::TryParse((Read-TextShared -Path $pidFile).Trim(), [ref] $previous)
    if ($previous -gt 0) {
        if (Get-Process -Id $previous -ErrorAction SilentlyContinue) {
            Write-LauncherLog ('stopping leftover server, pid ' + $previous)
            [void](Stop-ProcessTree -TargetPid $previous)
            Start-Sleep -Seconds 2
        } else {
            Write-LauncherLog ('stale pid file, pid ' + $previous + ' is not running')
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

if (Test-PortBusy -Port 3080) {
    Write-LauncherLog 'WARNING: port 3080 is still in use; dsh may fail to bind'
}

# --- 3. start the server, hidden, output redirected into the log -----------
$browserProfile = Join-Path $dshHome 'browser-profile'

$browserCandidates = @()
$browserCandidates += "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
if (${env:ProgramFiles(x86)}) { $browserCandidates += "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" }
$browserCandidates += "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
$browserCandidates += "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
if (${env:ProgramFiles(x86)}) { $browserCandidates += "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" }

$browser = $browserCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

$browserImagePattern = "Name='chrome.exe'"
if ($browser -and ([System.IO.Path]::GetFileName($browser) -ieq 'msedge.exe')) {
    $browserImagePattern = "Name='msedge.exe'"
}

# cmd performs the redirect so stdout and stderr land in ONE file, which is
# what used to appear merged in the console window.
$serverCommand = 'npx @deepseek-ai/dsh web --no-open > "' + $serverLog + '" 2>&1'
$server = Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ' + $serverCommand) `
    -WorkingDirectory $workspace -WindowStyle Hidden -PassThru

$serverPid = $server.Id
Set-Content -LiteralPath $pidFile -Value ([string] $serverPid) -Encoding ASCII
Write-LauncherLog ('server started, cmd pid ' + $serverPid + '; console output goes to ' + $serverLog)

# --- 4. wait for the authenticated URL in the log --------------------------
$url = $null
$deadline = (Get-Date).AddSeconds($UrlTimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    if (-not (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)) {
        Write-LauncherLog 'server exited before printing a URL'
        break
    }
    $text = Read-TextShared -Path $serverLog
    if ($text) {
        $match = [regex]::Match($text, 'dsh web:\s+(http\S+)')
        if ($match.Success) {
            $url = $match.Groups[1].Value
            break
        }
    }
}

if (-not $url) {
    Write-LauncherLog 'no URL found; stopping the server. See logs\dsh.log for the reason.'
    [void](Stop-ProcessTree -TargetPid $serverPid)
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-LauncherLog ('url captured: ' + $url)

# --- 5. open the app window -------------------------------------------------
if (-not $browser) {
    Write-LauncherLog 'no Chrome or Edge found; leaving the server running. Open the URL from logs\dsh.log, and use stop-dsh.ps1 to stop it.'
    exit 0
}

# One quoted string, never an array: see the QUOTING NOTE at the top.
$argumentLine = '--app="' + $url + '"' +
    ' --user-data-dir="' + $browserProfile + '"' +
    ' --no-first-run --no-default-browser-check'

$browserProcess = Start-Process -FilePath $browser -ArgumentList $argumentLine -PassThru
$browserPid = $browserProcess.Id
Write-LauncherLog ('browser launched, pid ' + $browserPid)

# --- 6. watch the browser, then stop the server -----------------------------
$detected = $false
$appearDeadline = (Get-Date).AddSeconds($BrowserAppearTimeoutSeconds)
while ((Get-Date) -lt $appearDeadline) {
    Start-Sleep -Seconds 1
    $procs = Get-HarnessBrowserProcesses -ImagePattern $browserImagePattern
    if ($null -eq $procs) {
        if (Get-Process -Id $browserPid -ErrorAction SilentlyContinue) { $detected = $true; break }
    } elseif ($procs.Count -gt 0) {
        $detected = $true
        Write-LauncherLog ('browser detected, ' + $procs.Count + ' matching processes')
        break
    }
}

if (-not $detected) {
    Write-LauncherLog 'browser never appeared; stopping the server'
    [void](Stop-ProcessTree -TargetPid $serverPid)
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    exit 1
}

$misses = 0
while ($true) {
    Start-Sleep -Seconds $BrowserPollSeconds

    if (-not (Get-Process -Id $serverPid -ErrorAction SilentlyContinue)) {
        Write-LauncherLog 'server is gone; launcher exiting'
        break
    }

    $procs = Get-HarnessBrowserProcesses -ImagePattern $browserImagePattern
    if ($null -eq $procs) {
        # WMI unavailable: fall back to the process we launched directly.
        $alive = [bool](Get-Process -Id $browserPid -ErrorAction SilentlyContinue)
    } else {
        $alive = ($procs.Count -gt 0)
    }

    if ($alive) {
        $misses = 0
    } else {
        $misses++
        Write-LauncherLog ('browser not detected (' + $misses + ' of ' + $BrowserMissesBeforeStop + ')')
        if ($misses -ge $BrowserMissesBeforeStop) {
            Write-LauncherLog 'browser window closed; stopping the server'
            break
        }
    }
}

[void](Stop-ProcessTree -TargetPid $serverPid)
Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
Write-LauncherLog '--- launcher exit ---'
