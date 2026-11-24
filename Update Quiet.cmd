@echo off
rem Update Quiet: double-click it, with World of Warcraft closed, to get the newest Quiet addons for WoW Forever.
rem (The whole job is on the one line below: this file may be replaced by a newer one while it runs.)
set "QUIET_SELF=%~f0" & powershell -NoProfile -ExecutionPolicy Bypass -Command "$t = Get-Content -Raw -LiteralPath $env:QUIET_SELF; $m = '#' + 'POWERSHELL#'; Invoke-Expression $t.Substring($t.IndexOf($m) + $m.Length)" & echo. & pause & exit /b

#POWERSHELL#
$ErrorActionPreference = 'Stop'
$Repo = 'AdmiralArg/quiet-addons'
$Asset = 'Quiet-addons.zip'
$Here = Join-Path $env:LOCALAPPDATA 'QuietAddons'

function Say($text) { Write-Host $text }
function Stop-With($text) {
    Write-Host ''
    Write-Host $text -ForegroundColor Yellow
    exit 1
}

Say 'Quiet addons for WoW Forever: looking for updates...'
Say ''

if (Get-Process -Name 'Wow', 'Wow-64' -ErrorAction SilentlyContinue) {
    Stop-With 'World of Warcraft is open. Close it, then press Update Quiet again.'
}

# ---------- where the addons go: WoW Forever's Interface\AddOns ----------
function Test-Forever($path) {
    return $path -and (Test-Path -LiteralPath $path) -and ($path -match '_forever_')
}
function Find-AddOns {
    # (where this file is: in AddOns itself, or in the WoW folder above it)
    $dir = Split-Path -Parent $env:QUIET_SELF
    while ($dir) {
        if ((Split-Path -Leaf $dir) -eq 'AddOns' -and (Test-Forever $dir)) { return $dir }
        foreach ($sub in '_forever_\Interface\AddOns', 'Interface\AddOns') {
            $p = Join-Path $dir $sub
            if (Test-Forever $p) { return $p }
        }
        $parent = Split-Path -Parent $dir
        if (-not $parent -or $parent -eq $dir) { break }
        $dir = $parent
    }
    # (the folder found last time)
    $saved = Join-Path $Here 'addons-folder.txt'
    if (Test-Path $saved) {
        $p = (Get-Content -Raw $saved).Trim()
        if (Test-Forever $p) { return $p }
    }
    # (where Battle.net put World of Warcraft, and the usual places)
    $roots = @()
    foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
                     'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
        try {
            $install = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
            if ($install) { $roots += $install.TrimEnd('\'); $roots += (Split-Path -Parent $install.TrimEnd('\')) }
        } catch { }
    }
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })) {
        foreach ($rel in 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft',
                         'World of Warcraft', 'Games\World of Warcraft') {
            $roots += (Join-Path $drive $rel)
        }
    }
    foreach ($root in $roots) {
        $forever = Join-Path $root '_forever_'
        if (Test-Path -LiteralPath $forever) {
            $p = Join-Path $forever 'Interface\AddOns'
            if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
            return $p
        }
    }
    # (else: asked)
    Add-Type -AssemblyName System.Windows.Forms
    $pick = New-Object System.Windows.Forms.FolderBrowserDialog
    $pick.Description = 'Where is World of Warcraft? Pick its folder (the one with _forever_ in it).'
    if ($pick.ShowDialog() -ne 'OK') { return $null }
    foreach ($p in (Join-Path $pick.SelectedPath '_forever_\Interface\AddOns'),
                   (Join-Path $pick.SelectedPath 'Interface\AddOns'), $pick.SelectedPath) {
        if ($p -match '_forever_\\Interface\\AddOns$' -and (Test-Path -LiteralPath (Split-Path -Parent (Split-Path -Parent $p)))) {
            if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
            return $p
        }
    }
    return $null
}

$addons = Find-AddOns
if (-not $addons) { Stop-With "WoW Forever's folder wasn't found. Put this file in your World of Warcraft folder and press it again." }
New-Item -ItemType Directory -Path $Here -Force | Out-Null
Set-Content -Path (Join-Path $Here 'addons-folder.txt') -Value $addons -Encoding UTF8
Say "Your addons folder: $addons"

# ---------- the newest release, from GitHub ----------
$tmp = Join-Path $env:TEMP ('quiet-update-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$zip = Join-Path $tmp $Asset
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$tag, $url = $null, $null

# (open to anyone: no sign-in)
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'quiet-addons-update' }
    $file = $release.assets | Where-Object { $_.name -eq $Asset } | Select-Object -First 1
    if ($file) { $tag, $url = $release.tag_name, $file.browser_download_url }
} catch { }

# (kept private: through GitHub's own sign-in tool, signed in once)
if (-not $tag) {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Say ''
        Say 'The Quiet addons are kept in a private place on GitHub. The first time, this needs:'
        Say '  1. A free GitHub account (github.com/signup). Send your GitHub name to whoever sent you this,'
        Say '     and accept the invitation you then get (by e-mail, or on github.com).'
        Say "  2. GitHub's small sign-in tool on this PC."
        Say ''
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $answer = Read-Host "Install GitHub's sign-in tool now? (y/n)"
            if ($answer -match '^[yYjJ]') {
                & winget install --id GitHub.cli --exact --source winget
                $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
                $gh = Get-Command gh -ErrorAction SilentlyContinue
            }
        }
        if (-not $gh) { Stop-With "Install GitHub's sign-in tool from https://cli.github.com, then press Update Quiet again." }
    }
    & gh auth status --hostname github.com *> $null
    if ($LASTEXITCODE -ne 0) {
        Say ''
        Say 'Sign in to GitHub, once: a code is shown here, and your browser opens to type it in.'
        & gh auth login --hostname github.com --git-protocol https --web
        if ($LASTEXITCODE -ne 0) { Stop-With 'Not signed in. Press Update Quiet again to try once more.' }
    }
    $tag = & gh release view --repo $Repo --json tagName --jq .tagName 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tag) {
        Stop-With ("Your GitHub account can't see the Quiet addons yet. Send your GitHub name to whoever sent you " +
            'this, accept the invitation (by e-mail, or on github.com), then press Update Quiet again.')
    }
}

$mark = Join-Path $addons '.quiet-version'
if ((Test-Path $mark) -and ((Get-Content -Raw $mark).Trim() -eq $tag)) {
    Remove-Item -LiteralPath $tmp -Recurse -Force
    Say ''
    Say "You have the newest already ($tag). Nothing to do."
    exit 0
}

Say "Downloading $tag..."
if ($url) {
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
} else {
    & gh release download $tag --repo $Repo --pattern $Asset --dir $tmp --clobber
    if ($LASTEXITCODE -ne 0) { Stop-With 'The download failed. Press Update Quiet again in a moment.' }
}

# ---------- in place: each Quiet addon's folder replaced whole, nothing else touched ----------
# (your settings are in WTF, not here: they stay as they are)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$out = Join-Path $tmp 'unpacked'
[IO.Compression.ZipFile]::ExtractToDirectory($zip, $out)
$folders = @(Get-ChildItem -LiteralPath $out -Directory)
if ($folders.Count -lt 3) { Stop-With "That download doesn't look like the Quiet addons. Nothing was changed." }
foreach ($folder in $folders) {
    $dest = Join-Path $addons $folder.Name
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    Move-Item -LiteralPath $folder.FullName -Destination $dest
}
foreach ($loose in (Get-ChildItem -LiteralPath $out -File)) {
    Copy-Item -LiteralPath $loose.FullName -Destination (Join-Path $addons $loose.Name) -Force
}
Set-Content -Path $mark -Value $tag -Encoding ASCII
Remove-Item -LiteralPath $tmp -Recurse -Force

Say ''
Say "Done: the Quiet addons are up to date ($tag). Start the game."
Say "Next time, press Update Quiet in your addons folder again."
