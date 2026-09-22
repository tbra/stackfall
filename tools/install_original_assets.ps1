<#
.SYNOPSIS
    Installs placeholder audio (and textures, if present) from a local
    original Bontago (2003) install into assets/original/, gitignored.

.DESCRIPTION
    HARD CONSTRAINT: the original's files are third-party copyrighted assets
    and this repo is public. assets/original/ is in .gitignore (whole folder,
    the same pattern addons/godotsteam/ uses) and this script never writes
    anywhere else. autoload/Sfx.gd loads these at runtime by filename, not
    through Godot's import pipeline, so a fresh checkout with no install
    still opens and plays cleanly with no sound (README "Original assets
    (optional)").

    Copies Audio/SoundFX/*.wav and Audio/Music/*.mp3 flat into
    assets/original/audio/ (config/AudioConfig.gd's filenames are flat, and
    SoundFX/Music never collide), and Textures/* (if present), if present,
    into assets/original/textures/ preserving each theme's subfolder (Artic/,
    Beach/, ... each contain their own top.jpg/left.jpg/... -- flattening
    those would silently overwrite one theme's faces with another's, which an
    earlier revision of this script did). Every filename is lowercased on the
    way in -- the original mixes case (e.g. Top.jpg / top.jpg) -- so lookups
    never have to special-case it. Idempotent: safe to re-run, re-copies
    every file each time (small SFX/texture set, no need for a skip-if-newer
    check).

.PARAMETER Source
    Root of the original install. Defaults to the machine this package was
    built on ("C:\Program Files (x86)\Bontago"); pass your own if different.

.PARAMETER Path
    Repo checkout to install into. Defaults to this script's repo root.

.NOTES
    Run once per developer machine, never from CI, never commits anything.
#>

param(
	[string]$Source = "C:\Program Files (x86)\Bontago",
	[string]$Path = ""
)

$ErrorActionPreference = 'Stop'

if ($Path -eq "") {
	$Path = (Resolve-Path (Join-Path (Split-Path -Parent $PSScriptRoot) ".")).Path
}

if (-not (Test-Path $Source)) {
	Write-Error "Original Bontago install not found at '$Source'. Pass -Source '<path to Bontago install>'."
	exit 1
}

$destRoot = Join-Path $Path "assets/original"
$installedCount = 0

# Audio/SoundFX/*.wav and Audio/Music/*.mp3 have no name collisions between
# each other, and config/AudioConfig.gd's filenames are flat (no subfolder),
# so audio is flattened into one directory.
function Install-Flat {
	param([string]$SrcDir, [string]$DestDir, [string]$Label)

	if (-not (Test-Path $SrcDir)) {
		Write-Host "No $Label at '$SrcDir' -- skipping." -ForegroundColor Yellow
		return
	}
	New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
	$files = Get-ChildItem -Path $SrcDir -File -Recurse
	foreach ($file in $files) {
		$destName = $file.Name.ToLowerInvariant()
		$destPath = Join-Path $DestDir $destName
		Copy-Item -Force -Path $file.FullName -Destination $destPath
		Write-Host "  installed $Label/$destName"
		$script:installedCount++
	}
}

# Textures/<Theme>/{top,bottom,left,right,front,back}.jpg repeats the same
# six filenames per theme -- each theme's subfolder is preserved (lowercased)
# so e.g. Artic/top.jpg and Beach/top.jpg don't collide.
function Install-PreservingSubfolders {
	param([string]$SrcDir, [string]$DestDir, [string]$Label)

	if (-not (Test-Path $SrcDir)) {
		Write-Host "No $Label at '$SrcDir' -- skipping." -ForegroundColor Yellow
		return
	}
	$files = Get-ChildItem -Path $SrcDir -File -Recurse
	foreach ($file in $files) {
		$relDir = (Split-Path -Parent $file.FullName).Substring($SrcDir.Length).TrimStart('\', '/').ToLowerInvariant()
		$destDirFull = if ($relDir -eq "") { $DestDir } else { Join-Path $DestDir $relDir }
		New-Item -ItemType Directory -Force -Path $destDirFull | Out-Null
		$destName = $file.Name.ToLowerInvariant()
		$destPath = Join-Path $destDirFull $destName
		Copy-Item -Force -Path $file.FullName -Destination $destPath
		Write-Host "  installed $Label/$(if ($relDir -eq '') { $destName } else { "$relDir/$destName" })"
		$script:installedCount++
	}
}

Write-Host "Installing original Bontago assets from '$Source' into '$destRoot' ..."

Install-Flat -SrcDir (Join-Path $Source "Audio") -DestDir (Join-Path $destRoot "audio") -Label "audio"
Install-PreservingSubfolders -SrcDir (Join-Path $Source "Textures") -DestDir (Join-Path $destRoot "textures") -Label "textures"

if ($installedCount -eq 0) {
	Write-Error "Found '$Source' but no Audio/ or Textures/ subfolder inside it -- nothing installed."
	exit 1
}

Write-Host "Done: $installedCount file(s) installed under '$destRoot'." -ForegroundColor Green

$gdignore = Join-Path $destRoot '.gdignore'
if (-not (Test-Path $gdignore)) { New-Item -ItemType File -Path $gdignore | Out-Null; Write-Host "  wrote .gdignore" }
