# ===========================================================================
# DeepSeek Harness - stop script
#
# The normal way to stop the harness is to close its browser window: the
# launcher watches that window and shuts the server down. This script exists
# for the abnormal case - the launcher was killed from Task Manager, or the
# browser crashed and left the server running with nothing attached.
#
# It stops:
#   * the server recorded in run\server.pid, together with its child processes
#   * any browser process that is using .\dsh-home\browser-profile
#
# It never touches the browsers or processes you use day to day: the browser
# match is keyed on our own profile path appearing in the command line.
#
# ENCODING NOTE - DO NOT ADD NON-ASCII CHARACTERS TO THIS FILE
#   Windows PowerShell 5.1 decodes a .ps1 that has no BOM using the system ANSI
#   code page, not UTF-8, and a non-ASCII byte can break parsing outright.
# ===========================================================================

[CmdletBinding()]
param(
    # Leave the browser window open and only stop the server.
    [switch] $KeepBrowser
)

$ErrorActionPreference = 'Continue'

$root           = Split-Path -Parent $PSCommandPath
$dshHome        = Join-Path $root 'dsh-home'
$cachePath      = Join-Path $dshHome 'npm-cache'
$runDir         = Join-Path $root 'run'
$pidFile        = Join-Path $runDir 'server.pid'
$browserProfile = Join-Path $dshHome 'browser-profile'

function Write-Line {
    param([string] $Text, [string] $Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
}

Write-Host ''
Write-Host 'DeepSeek Harness - stop' -ForegroundColor White

$stoppedSomething = $false

# --- the server -------------------------------------------------------------
if (Test-Path -LiteralPath $pidFile) {
    $serverPid = 0
    [void][int]::TryParse((Get-Content -LiteralPath $pidFile -Raw).Trim(), [ref] $serverPid)
    if ($serverPid -gt 0) {
        if (Get-Process -Id $serverPid -ErrorAction SilentlyContinue) {
            Write-Line ('  stopping server, pid ' + $serverPid)
            $null = & taskkill.exe /PID $serverPid /T /F 2>&1
            Start-Sleep -Milliseconds 800

            # taskkill can be refused in restricted environments. Falling back to
            # a command-line sweep keeps an invisible orphaned server from
            # surviving, which is the failure this script exists to prevent.
            if (Get-Process -Id $serverPid -ErrorAction SilentlyContinue) {
                Write-Line '  taskkill did not finish the job; sweeping by command line' 'Yellow'
                foreach ($image in @("Name='node.exe'", "Name='cmd.exe'", "Name='npx.exe'")) {
                    try {
                        $rows = Get-CimInstance Win32_Process -Filter $image -ErrorAction Stop
                        foreach ($row in $rows) {
                            if ($row.CommandLine -and $row.CommandLine -like "*$cachePath*") {
                                Write-Line ('  stopping pid ' + $row.ProcessId)
                                try { Stop-Process -Id $row.ProcessId -Force -ErrorAction Stop } catch { }
                            }
                        }
                    } catch {
                        Write-Line ('  sweep query failed: ' + $_.Exception.Message) 'Yellow'
                    }
                }
                try { Stop-Process -Id $serverPid -Force -ErrorAction Stop } catch { }
                Start-Sleep -Milliseconds 500
                if (Get-Process -Id $serverPid -ErrorAction SilentlyContinue) {
                    Write-Line '  server is STILL running - stop it from Task Manager' 'Red'
                } else {
                    Write-Line '  server stopped by the fallback sweep'
                }
            }
            $stoppedSomething = $true
        } else {
            Write-Line ('  server pid ' + $serverPid + ' is not running')
        }
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
} else {
    Write-Line '  no run\server.pid; the launcher may not have started a server'
}

# --- the harness browser window --------------------------------------------
if ($KeepBrowser) {
    Write-Line '  leaving the browser window alone (-KeepBrowser)'
} else {
    $browserPids = @()
    foreach ($image in @("Name='chrome.exe'", "Name='msedge.exe'")) {
        try {
            $found = Get-CimInstance Win32_Process -Filter $image -ErrorAction Stop
            $browserPids += @($found | Where-Object { $_.CommandLine -and $_.CommandLine -like "*$browserProfile*" })
        } catch {
            Write-Line ('  could not query processes: ' + $_.Exception.Message) 'Yellow'
        }
    }

    if ($browserPids.Count -eq 0) {
        Write-Line '  no harness browser window is open'
    } else {
        foreach ($p in $browserPids) {
            $null = & taskkill.exe /PID $p.ProcessId /T /F 2>&1
        }
        Write-Line ('  closed the harness browser window (' + $browserPids.Count + ' processes)')
        $stoppedSomething = $true
    }
}

Write-Host ''
if ($stoppedSomething) {
    Write-Host 'Done.' -ForegroundColor Green
} else {
    Write-Host 'Nothing was running.' -ForegroundColor Green
}
Write-Host ''
