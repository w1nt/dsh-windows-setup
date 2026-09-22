<#
  make-icon.ps1 - build <harness>\dsh.ico from the frontend asset of the
  installed dsh, then point the desktop shortcut at it.

  Why this is a separate step
    The source image (favicon.svg) only exists AFTER the first dsh launch,
    because that is when npx downloads @deepseek-ai/dsh-web-frontend. Run this
    once the harness has started successfully at least once.

  What it does
    1. Locates favicon.svg inside the harness npm cache.
    2. Renders it with a Chromium-based browser (headless screenshot), giving a
       coloured tile so the icon stays visible on both light and dark taskbars.
    3. Writes a multi-size .ico (16,24,32,48,64,128,256) to <harness>\dsh.ico.
    4. Re-points "DeepSeek Harness.lnk" on the desktop at that icon.

  The logo is DeepSeek's own frontend asset. This script only transforms a copy
  that is already on your machine; no image is redistributed with this repo.

  ENCODING - THIS FILE MUST STAY PURE ASCII. Windows PowerShell 5.1 decodes a
  .ps1 without a BOM using the system ANSI code page, and a non-ASCII byte can
  break parsing outright.
#>

[CmdletBinding()]
param(
    # Where the harness lives. Defaults to the folder containing this script.
    [string] $HarnessRoot = (Split-Path -Parent $PSCommandPath),

    # Supply the source SVG yourself instead of searching the npm cache.
    [string] $FaviconPath,

    # Tile colour behind the logo, as RRGGBB.
    [string] $TileColor = '4D6BFE',

    # Build the icon but leave the desktop shortcut alone.
    [switch] $SkipShortcut
)

$ErrorActionPreference = 'Stop'

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

$HarnessRoot = (Resolve-Path -LiteralPath $HarnessRoot).Path
$cacheRoot   = Join-Path $HarnessRoot 'dsh-home\npm-cache'
$iconPath    = Join-Path $HarnessRoot 'dsh.ico'
$work        = Join-Path $env:TEMP 'dsh-icon-build'

Write-Host ''
Write-Host 'DeepSeek Harness - build dsh.ico' -ForegroundColor White

# --- 1. locate the source asset --------------------------------------------
Write-Step '1/4' 'Locate favicon.svg'

if (-not $FaviconPath) {
    $candidates = @()
    if (Test-Path -LiteralPath $cacheRoot) {
        $candidates = Get-ChildItem -LiteralPath $cacheRoot -Recurse -File -Filter 'favicon.svg' -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like '*dsh-web-frontend*' } |
            Sort-Object LastWriteTime -Descending
    }
    if ($candidates.Count -gt 0) {
        $FaviconPath = $candidates[0].FullName
    }
}

if (-not $FaviconPath -or -not (Test-Path -LiteralPath $FaviconPath)) {
    Write-Host ''
    Write-Host 'Could not find favicon.svg.' -ForegroundColor Yellow
    Write-Host 'Make sure the harness has been launched at least once so that npx has'
    Write-Host 'downloaded @deepseek-ai/dsh-web-frontend, or pass -FaviconPath.'
    exit 1
}
Write-Ok $FaviconPath

# --- 2. render ---------------------------------------------------------------
Write-Step '2/4' 'Render the SVG with a headless browser'

$browsers = @()
$browsers += "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
if (${env:ProgramFiles(x86)}) { $browsers += "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe" }
$browsers += "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
$browsers += "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
if (${env:ProgramFiles(x86)}) { $browsers += "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" }

$browser = $browsers | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $browser) {
    Write-Host ''
    Write-Host 'No Chrome or Edge found; a browser is required to rasterise the SVG.' -ForegroundColor Yellow
    exit 1
}
Write-Ok $browser

if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null
Copy-Item -LiteralPath $FaviconPath -Destination (Join-Path $work 'logo.svg') -Force

# The upstream SVG is monochrome (black, or white under a dark colour scheme),
# so it would vanish against one taskbar shade or the other. A coloured tile
# with a white glyph is visible on both.
$html = @"
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent;width:256px;height:256px;overflow:hidden}
.tile{width:256px;height:256px;background:#$TileColor;border-radius:58px;display:flex;align-items:center;justify-content:center}
img{width:170px;height:170px;filter:brightness(0) invert(1)}
</style></head><body><div class="tile"><img src="logo.svg"></div></body></html>
"@
$htmlPath = Join-Path $work 'icon.html'
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($htmlPath, $html, $encoding)

$png      = Join-Path $work 'icon-256.png'
$fileUrl  = 'file:///' + ($htmlPath -replace '\\', '/')
$arguments = @(
    '--headless=new', '--no-sandbox', '--disable-gpu', '--disable-crash-reporter',
    '--hide-scrollbars', '--force-device-scale-factor=1', '--window-size=256,256',
    '--default-background-color=00000000', "--screenshot=$png", $fileUrl
)
$null = & $browser @arguments 2>&1
Start-Sleep -Seconds 2

if (-not (Test-Path -LiteralPath $png)) {
    Write-Host ''
    Write-Host 'The browser did not produce a screenshot.' -ForegroundColor Yellow
    Write-Host 'If you are running this from a restricted shell, try a normal console.'
    exit 1
}
Write-Ok ("rendered " + (Get-Item -LiteralPath $png).Length + " bytes")

# --- 3. build the .ico ------------------------------------------------------
Write-Step '3/4' 'Build the multi-size icon'

Add-Type -AssemblyName System.Drawing

$source = [System.Drawing.Image]::FromFile($png)
$sizes  = @(16, 24, 32, 48, 64, 128, 256)
$blobs  = @()

foreach ($size in $sizes) {
    $bitmap = New-Object System.Drawing.Bitmap $size, $size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.DrawImage($source, 0, 0, $size, $size)
    $graphics.Dispose()

    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $blobs += , $stream.ToArray()
    $bitmap.Dispose()
    $stream.Dispose()
}
$source.Dispose()

# ICO container: 6-byte header, one 16-byte directory entry per image, then the
# image payloads (PNG is allowed inside .ico since Vista).
$stream  = [System.IO.File]::Create($iconPath)
$writer  = New-Object System.IO.BinaryWriter($stream)
$writer.Write([UInt16]0)
$writer.Write([UInt16]1)
$writer.Write([UInt16]$sizes.Count)

$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $size = $sizes[$i]
    $length = $blobs[$i].Length
    $dimension = 0
    if ($size -lt 256) { $dimension = $size }
    $writer.Write([Byte]$dimension)
    $writer.Write([Byte]$dimension)
    $writer.Write([Byte]0)
    $writer.Write([Byte]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]32)
    $writer.Write([UInt32]$length)
    $writer.Write([UInt32]$offset)
    $offset += $length
}
foreach ($blob in $blobs) { $writer.Write($blob) }
$writer.Flush()
$writer.Close()
$stream.Close()

$check = New-Object System.Drawing.Icon($iconPath)
Write-Ok ("wrote " + $iconPath + " (" + (Get-Item -LiteralPath $iconPath).Length + " bytes, " + $sizes.Count + " sizes)")
$check.Dispose()

# --- 4. shortcut ------------------------------------------------------------
Write-Step '4/4' 'Point the DeepSeek Harness shortcut at the icon'

if ($SkipShortcut) {
    Write-Note 'skipped (-SkipShortcut)'
}
else {
    # The shortcut may live on the desktop or in the Start Menu, depending on how
    # setup.ps1 was invoked, so update whichever of them exist.
    $candidates = @()
    $candidates += (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DeepSeek Harness.lnk')
    $candidates += (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\DeepSeek Harness.lnk')

    $shell = New-Object -ComObject WScript.Shell
    $updated = 0
    foreach ($lnkPath in $candidates) {
        if (Test-Path -LiteralPath $lnkPath) {
            $shortcut = $shell.CreateShortcut($lnkPath)
            $shortcut.IconLocation = $iconPath + ',0'
            $shortcut.Save()
            Write-Ok ("updated " + $lnkPath)
            $updated++
        }
    }
    if ($updated -eq 0) {
        Write-Note 'no DeepSeek Harness shortcut found on the desktop or in the Start Menu.'
        Write-Note 'Run setup.ps1 first, or create one by hand.'
    }
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host 'Windows may cache taskbar and shortcut icons; sign out or restart' -ForegroundColor Gray
Write-Host 'Explorer if the old icon lingers.' -ForegroundColor Gray
Write-Host ''
