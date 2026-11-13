# Installs or updates PIF Online in an installed copy of Pokemon Infinite Fusion 2.
# In PowerShell:
#   irm https://github.com/AurelienBaraquin/pif-online/releases/latest/download/install.ps1 | iex
# Optional environment variables:
#   PIF_GAME_DIR     the game folder, when it cannot be found automatically
#   PIF_RELEASE_URL  where to download the release files (another version or a mirror)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$ReleaseUrl = 'https://github.com/AurelienBaraquin/pif-online/releases/latest/download'
$GameFolderName = 'InfiniteFusion2'
$GameExe = 'InfiniteFusion2.exe'
$GameTitle = 'infinitefusion-hoenn'
$SettingsScript = 'Data\Scripts\001_Settings.rb'
$OverlayName = '998_Multiplayer'
$OverlayEntry = 'game_hooks\z_install\001_install.rb'
$ClientZip = 'PIF-Online-Client.zip'

function Write-Step([string] $Text) {
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Test-GameFolder([string] $Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath (Join-Path $Path $GameExe) -PathType Leaf)) { return $false }
    $ini = Join-Path $Path 'Game.ini'
    if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) { return $false }
    $title = Select-String -LiteralPath $ini -Pattern '^\s*Title\s*=\s*(.+?)\s*$' | Select-Object -First 1
    return $null -ne $title -and $title.Matches[0].Groups[1].Value -eq $GameTitle
}

# The official launcher saves where it installed the game.
function Get-LauncherPath {
    $config = Join-Path $env:APPDATA 'infinitefusion_common\launcher_config.json'
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return $null }
    try {
        $saved = (Get-Content -LiteralPath $config -Raw | ConvertFrom-Json).last_install_path_hoenn
    } catch {
        Write-Warning "Cannot read ${config}: $($_.Exception.Message)"
        return $null
    }
    return $saved
}

function Find-Game {
    $candidates = @(
        $env:PIF_GAME_DIR,
        (Get-LauncherPath),
        (Join-Path $HOME 'Downloads\InfiniteFusion'),
        (Join-Path $HOME 'Desktop'),
        (Join-Path $HOME 'Documents'),
        'C:\Games',
        'C:\'
    ) | Where-Object { $_ }
    foreach ($base in $candidates) {
        foreach ($path in @($base, (Join-Path $base $GameFolderName))) {
            if (Test-GameFolder $path) { return (Resolve-Path -LiteralPath $path).Path }
        }
    }
    Write-Host "Pokemon Infinite Fusion 2 was not found automatically."
    while ($true) {
        $answer = (Read-Host "Paste the game folder (the one containing $GameExe), or leave empty to stop").Trim('"', ' ')
        if (-not $answer) { throw 'No game folder given.' }
        if (Test-GameFolder $answer) { return (Resolve-Path -LiteralPath $answer).Path }
        Write-Host "No $GameExe of Pokemon Infinite Fusion 2 in that folder."
    }
}

function Get-GameVersion([string] $GamePath) {
    $line = Select-String -LiteralPath (Join-Path $GamePath $SettingsScript) -Pattern 'HOENN_VERSION_NUMBER\s*=\s*"([^"]+)"' |
        Select-Object -First 1
    if ($null -eq $line) { throw "Cannot read the game version in $SettingsScript." }
    return $line.Matches[0].Groups[1].Value
}

# Only this copy matters: other copies of the game may stay open.
function Assert-GameClosed([string] $GamePath) {
    $folder = $GamePath.TrimEnd('\') + '\'
    $running = Get-Process -Name 'InfiniteFusion2', 'InfiniteFusion2-performance' -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Path -or $_.Path.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase) }
    if ($running) { throw 'The game is running. Close it, then run the installer again.' }
}

function Assert-Writable([string] $GamePath) {
    $probe = Join-Path $GamePath ('pif-online-' + [guid]::NewGuid() + '.tmp')
    try {
        Set-Content -LiteralPath $probe -Value 'test'
        Remove-Item -LiteralPath $probe
    } catch {
        throw "Cannot write in $GamePath. Move the game out of protected folders such as Program Files, or run PowerShell as administrator."
    }
}

function Save-ReleaseFile([string] $Name, [string] $Folder) {
    $target = Join-Path $Folder $Name
    Invoke-WebRequest -Uri "$ReleaseUrl/$Name" -OutFile $target -UseBasicParsing
    return $target
}

function Assert-Checksum([string] $File, [string] $SumsFile) {
    $name = Split-Path $File -Leaf
    $expected = Get-Content -LiteralPath $SumsFile | ForEach-Object {
        $parts = $_ -split '\s+\*?', 2
        if ($parts.Count -eq 2 -and $parts[1] -eq $name) { $parts[0] }
    } | Select-Object -First 1
    if (-not $expected) { throw "$name is missing from the release checksums." }
    $actual = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
    if ($actual -ne $expected) { throw "$name is corrupted (checksum mismatch). Run the installer again." }
}

function Install-Overlay([string] $GamePath, [string] $Zip, [string] $WorkFolder) {
    $unpacked = Join-Path $WorkFolder 'client'
    Expand-Archive -LiteralPath $Zip -DestinationPath $unpacked
    $source = Join-Path $unpacked "Data\Scripts\$OverlayName"
    if (-not (Test-Path -LiteralPath (Join-Path $source $OverlayEntry) -PathType Leaf)) {
        throw "$ClientZip does not contain PIF Online."
    }
    # The game runs every file under Data\Scripts: a stale file from an older
    # version would still load, so the folder is replaced, never merged.
    $target = Join-Path $GamePath "Data\Scripts\$OverlayName"
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    Copy-Item -LiteralPath $source -Destination $target -Recurse
    $expected = @(Get-ChildItem -LiteralPath $source -Recurse -File).Count
    $copied = @(Get-ChildItem -LiteralPath $target -Recurse -File).Count
    if ($copied -ne $expected) { throw "Only $copied of $expected files were copied to $target." }
    return $expected
}

function Install-PifOnline {
    if ($env:PIF_RELEASE_URL) { $script:ReleaseUrl = $env:PIF_RELEASE_URL.TrimEnd('/') }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $work = Join-Path ([IO.Path]::GetTempPath()) ('pif-online-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $work | Out-Null
    try {
        Write-Step 'Looking for Pokemon Infinite Fusion 2'
        $game = Find-Game
        Write-Host "    Found: $game"

        Write-Step 'Checking the game version'
        $supported = Get-Content -LiteralPath (Save-ReleaseFile 'supported-game.json' $work) -Raw | ConvertFrom-Json
        $version = Get-GameVersion $game
        if ($version -ne $supported.version) {
            throw "Your game is version $version, but this PIF Online release supports version $($supported.version). Update the game with the official launcher, or install the PIF Online release made for your version."
        }
        Write-Host "    Version $version (supported)"

        Write-Step 'Checking the game folder'
        Assert-GameClosed $game
        Assert-Writable $game

        Write-Step 'Downloading PIF Online'
        $zip = Save-ReleaseFile $ClientZip $work
        Assert-Checksum $zip (Save-ReleaseFile 'SHA256SUMS' $work)

        Write-Step 'Installing'
        $count = Install-Overlay $game $zip $work
        Write-Host "    $count files installed in Data\Scripts\$OverlayName"

        Write-Host ''
        Write-Host 'PIF Online is installed.' -ForegroundColor Green
        Write-Host 'Start the game, load your save, then open Pause > Multiplayer > Add a server.'
    } catch {
        Write-Host ''
        Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Install-PifOnline
