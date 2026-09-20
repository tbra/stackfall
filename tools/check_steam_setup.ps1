<#
.SYNOPSIS
    Reports whether the local, untracked GodotSteam addon install is complete.

.DESCRIPTION
    res://addons/godotsteam/ is deliberately NOT committed to git (spike
    Bontago-mv0.2.1, written up in docs/M3b_RESEARCH.md's "Spike results"
    section). Godot only tries to load a .gdextension file if one exists on
    disk, so a machine that has never run the local Steam setup step (see
    README.md, "Steam setup (development)") gets a completely clean
    `godot --headless --editor --path . --quit` and plays fine over LAN/ENet
    -- that is a supported state, not an error.

    The one UNSUPPORTED state is a half-installed addon folder: the
    .gdextension file present without its Windows library, or without Valve's
    steam_api64.dll. Godot's GDExtensionManager prints ERROR lines on every
    project open in that case (confirmed empirically; see the research doc).
    This script tells you which state you're in and, if partial, exactly
    which files are missing.

.NOTES
    Read-only: never downloads, deletes, or modifies anything.
    Run from anywhere; paths are resolved relative to this script's location.
#>

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$addonDir = Join-Path $repoRoot 'addons/godotsteam'

if (-not (Test-Path $addonDir)) {
    Write-Host "No Steam addon installed (addons/godotsteam/ is absent)." -ForegroundColor Yellow
    Write-Host "This is a supported state: LAN/ENet play and 'godot --headless --editor --path . --quit' both work cleanly without it."
    Write-Host "To develop or test the Steam transport (M3b), see README.md, 'Steam setup (development)'."
    exit 0
}

# DECISION: only the Windows library is checked here because this project's
# development machines are Windows (CLAUDE.md, Environment). Add linux64/osx
# entries if a non-Windows dev machine joins the project.
$required = @(
    'godotsteam.gdextension',
    'win64/libgodotsteam.windows.template_debug.x86_64.dll',
    'win64/libgodotsteam.windows.template_release.x86_64.dll',
    'win64/steam_api64.dll'
)

$missing = @()
foreach ($rel in $required) {
    $full = Join-Path $addonDir $rel
    if (-not (Test-Path $full)) {
        $missing += $rel
    }
}

if ($missing.Count -eq 0) {
    Write-Host "Steam addon looks complete: $addonDir" -ForegroundColor Green
    Write-Host "Run 'godot --headless --path . -s res://tools/steam_probe.gd' to exercise Steam.steamInitEx()."
    exit 0
}

Write-Host "addons/godotsteam/ exists but is missing files Godot's GDExtension loader needs:" -ForegroundColor Red
foreach ($rel in $missing) {
    Write-Host "  - addons/godotsteam/$rel"
}
Write-Host ""
Write-Host "A half-installed addon folder is the one unsupported state: Godot will print ERROR"
Write-Host "lines from GDExtensionManager on every '--editor --quit' run (docs/M3b_RESEARCH.md,"
Write-Host "'Spike results'). Either finish the install (README.md, 'Steam setup (development)')"
Write-Host "or delete addons/godotsteam/ entirely to go back to the clean, Steam-free state."
exit 1
