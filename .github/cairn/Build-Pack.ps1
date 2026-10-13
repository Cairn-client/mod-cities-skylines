# Copyright (C) 2026 the Cairn contributors. SPDX-License-Identifier: MIT (as the project it is part of)
<#
.SYNOPSIS
    Builds the Cairn mod pack for Cities: Skylines (CSM): release\Cairn-Pack-cities-skylines-<version>.zip and release\pack-index.json
    (what the Cairn launcher reads to see a newer pack exists).

.DESCRIPTION
    An *external* pack whose root is the player's local application data (docs in the launcher repository: docs/PACKS.md, installRoot
    "local-appdata"): Cities: Skylines loads its local mods from %LOCALAPPDATA%\Colossal Order\Cities_Skylines\Addons\Mods\<mod>, not
    from its game folder. The pack holds what the project's own install step copies, the mod's DLLs:

      mod\*.dll      the DLLs of src\csm\bin\Release, put in Addons\Mods\CSM
      pack.json      the contract with the launcher
      manifest.txt   MOD|<path>|<size>|<sha256>, one line per file

    The pack's version is the VERSION file (strict X.Y.Z, this project's own); CSM's own version (the assembly version the build was given)
    is the pack's "upstream". The player enables the mod in the game's content manager.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $BuildDir,        # src\csm\bin\Release
    [Parameter(Mandatory)][string] $UpstreamVersion  # the version the build stamped, yymm.run
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$version = (Get-Content (Join-Path $root 'VERSION') -TotalCount 1).Trim()
if ($version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw "VERSION must be strict X.Y.Z, got '$version'" }
if ($UpstreamVersion -cnotmatch '^[0-9]+\.[0-9]+$') { throw "upstream version must be like 2610.42, got '$UpstreamVersion'" }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$release = Join-Path $root 'release'
$stage = Join-Path $release 'pack-stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$mod = Join-Path $stage 'mod'
New-Item -ItemType Directory -Force -Path $mod | Out-Null

$dlls = @(Get-ChildItem (Join-Path $BuildDir '*.dll'))
if ($dlls.Count -eq 0) { throw "the build made no DLLs in $BuildDir" }
foreach ($d in $dlls) { Copy-Item $d.FullName $mod }
if (-not (Test-Path (Join-Path $mod 'CSM.dll'))) { throw 'the build did not make CSM.dll' }
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $mod 'LICENSE')

function Get-Sha256([string] $Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

# a launcher before 0.3.23 would put this pack in the game's folder: it is refused there
$launcherMin = '0.3.23'
$packJson = [ordered]@{
    schema      = 2
    id          = 'cities-skylines'
    game        = 'cities-skylines'
    version     = $version
    upstream    = $UpstreamVersion
    kind        = 'external'
    installRoot = 'local-appdata'
    installDir  = 'Colossal Order/Cities_Skylines/Addons/Mods/CSM'
    launcherMin = $launcherMin
}
[IO.File]::WriteAllText((Join-Path $stage 'pack.json'), (($packJson | ConvertTo-Json) + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$lines = New-Object System.Collections.Generic.List[string]
foreach ($f in Get-ChildItem $mod -Recurse -File | Sort-Object FullName) {
    $rel = $f.FullName.Substring($mod.Length + 1)
    $lines.Add(('MOD|{0}|{1}|{2}' -f $rel, $f.Length, (Get-Sha256 $f.FullName)))
}
[IO.File]::WriteAllText((Join-Path $stage 'manifest.txt'), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

$zipName = "Cairn-Pack-cities-skylines-$version.zip"
$zipPath = Join-Path $release $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$fs = [IO.File]::Open($zipPath, 'Create')
try {
    $z = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in Get-ChildItem $stage -Recurse -File) {
            $rel = $f.FullName.Substring($stage.Length + 1) -replace '\\', '/'
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $f.FullName, $rel, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $z.Dispose() }
} finally { $fs.Dispose() }

$index = [ordered]@{
    schema      = 2
    id          = 'cities-skylines'
    game        = 'cities-skylines'
    version     = $version
    upstream    = $UpstreamVersion
    kind        = 'external'
    file        = $zipName
    sha256      = Get-Sha256 $zipPath
    size        = (Get-Item $zipPath).Length
    launcherMin = $launcherMin
}
[IO.File]::WriteAllText((Join-Path $release 'pack-index.json'), (($index | ConvertTo-Json) + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "pack: $zipPath ($([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB), version $version, CSM $UpstreamVersion, $($lines.Count) files"
