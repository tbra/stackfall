# Exports a Windows development build to build/windows/ (gitignored) that can be
# added to Steam as a non-Steam game, which is what gives the Steam overlay
# (invites, "Join Game") to a build not launched through Steam. Requires the
# Godot 4.7.2 export templates in %APPDATA%/Godot/export_templates/4.7.2.stable
# and the GodotSteam addon installed per README "Steam setup (development)".
#
# Usage:
#   tools/export_windows.ps1                 # release export
#   tools/export_windows.ps1 -Debug          # debug export (script errors visible)
#   tools/export_windows.ps1 -SkipSmoke      # skip the exported-exe bot-match smoke gate (default: 1200 frames, -SmokeFrames N)
#   tools/export_windows.ps1 -Path M:/some/worktree
param(
	[switch]$Debug,
	[string]$Path = "",
	[string]$Godot = "godot",
	[switch]$SkipSmoke,
	[int]$SmokeFrames = 1200
)

$ErrorActionPreference = "Stop"
if ($Path -eq "") {
	$Path = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")).Path
}
$outDir = Join-Path $Path "build/windows"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$exe = Join-Path $outDir "Stackfall.exe"

$templates = Join-Path $env:APPDATA "Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe"
if (-not (Test-Path $templates)) {
	Write-Error "Export templates missing: $templates (download Godot_v4.7.2-stable_export_templates.tpz and unzip its 'templates' folder there as 4.7.2.stable)."
	exit 2
}
$steamDll = Join-Path $Path "addons/godotsteam/win64/steam_api64.dll"
if (-not (Test-Path $steamDll)) {
	Write-Warning "GodotSteam addon not installed in $Path; the build will run LAN/direct IP only."
}

$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
Write-Host "Exporting ($mode) from $Path to $exe"
& $Godot --headless --path $Path $mode "Windows Desktop" $exe
if ($LASTEXITCODE -ne 0) {
	Write-Error "Export failed with exit code $LASTEXITCODE"
	exit $LASTEXITCODE
}

# Godot 4.7 copies the GDExtension DLLs flat next to the exe, but the loader
# then resolves the .gdextension's `res://addons/godotsteam/win64/...` entry
# relative to the exe directory and fails with "Error 126" (seen on the first
# export: NET_SMOKE loaded_extensions=[]). Mirror the addon layout under the
# build directory so both lookups succeed.
$addonOut = Join-Path $outDir "addons/godotsteam/win64"
New-Item -ItemType Directory -Force -Path $addonOut | Out-Null
foreach ($dll in @("libgodotsteam.windows.template_release.x86_64.dll", "libgodotsteam.windows.template_debug.x86_64.dll", "steam_api64.dll")) {
	$src = Join-Path $Path "addons/godotsteam/win64/$dll"
	if (Test-Path $src) { Copy-Item -Force $src (Join-Path $addonOut $dll) }
}

# Spacewar app id next to the exe: Steam's overlay/launch path reads it for a
# build that was not started by the Steam client itself.
Set-Content -Path (Join-Path $outDir "steam_appid.txt") -Value "480" -Encoding ascii -NoNewline

# assets-audio package: autoload/Sfx.gd resolves its asset root as
# <exe dir>/assets/original/audio in an export (OS.has_feature("editor") is
# false there), never through the import pipeline -- assets/original/ is
# gitignored (per-developer install, tools/install_original_assets.ps1), so
# mirror it beside the exe the same way the GodotSteam DLLs above are, or the
# exported build ships silent.
$originalAssets = Join-Path $Path "assets/original"
if (Test-Path $originalAssets) {
	Copy-Item -Recurse -Force $originalAssets (Join-Path $outDir "assets/original")
} else {
	Write-Warning "assets/original/ not installed in $Path; the export will run with no original-asset sound (see tools/install_original_assets.ps1)."
}

# Smoke gate (Bontago-8or.18): GUT runs from source, never from the PCK, so
# export-only regressions (e.g. .tres listed as .tres.remap, which once left the
# block bag empty -- feedback/playtest.md 2026-09-26) are invisible to the unit
# suite. Run a short headless bot match on the exported exe and require that
# blocks were actually placed. -SkipSmoke bypasses it for debug/iteration builds.
if (-not $SkipSmoke) {
	# Start-Process with redirected streams: the exe writes Steam's breakpad
	# notice to stderr, which under $ErrorActionPreference = "Stop" would turn a
	# plain `& $exe 2>&1` into a terminating NativeCommandError.
	$smokeLog = Join-Path $outDir "smoke_bots.log"
	$smokeErr = Join-Path $outDir "smoke_bots.err"
	$smokeArgs = @("--headless", "--quit-after", "$SmokeFrames", "--", "--headless-host", "--bots=4")
	$proc = Start-Process -FilePath $exe -ArgumentList $smokeArgs -WorkingDirectory $outDir -NoNewWindow -Wait -PassThru -RedirectStandardOutput $smokeLog -RedirectStandardError $smokeErr
	$last = Select-String -Path $smokeLog -Pattern 'HEADLESS_BOTS .*placements=(\d+)' | Select-Object -Last 1
	$placements = 0
	if ($last -and $last.Matches.Count -gt 0) { $placements = [int]$last.Matches[0].Groups[1].Value }
	Remove-Item -Force $smokeLog, $smokeErr -ErrorAction SilentlyContinue
	if ($placements -lt 1) {
		# Not Write-Error: under $ErrorActionPreference = "Stop" that would
		# terminate with exit 1 before the distinct gate code below.
		[Console]::Error.WriteLine("Export smoke gate FAILED: exported exe placed $placements blocks in $SmokeFrames frames (expected >= 1; exe exit $($proc.ExitCode)). Last line: $($last.Line)")
		exit 3
	}
	Write-Host "Smoke gate: exported exe bot match placed $placements blocks (exit $($proc.ExitCode); $($last.Line.Trim()))."
}

Get-ChildItem $outDir | ForEach-Object { "{0,12:N0}  {1}" -f $_.Length, $_.Name }
Write-Host ""
Write-Host "Add to Steam: Steam > Games > Add a Non-Steam Game to My Library > Browse > $exe"
Write-Host "Launch it from the Steam library so the overlay (Shift+Tab, invites, Join Game) is available."
