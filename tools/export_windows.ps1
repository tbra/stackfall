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
#   tools/export_windows.ps1 -Path M:/clean/worktree -AssetsFrom M:/Bontago
#       # copy the gitignored addons/godotsteam and assets/original from the main checkout into the worktree first
#   tools/export_windows.ps1 -AllowNoOriginalAssets   # export without assets/original (otherwise a missing folder is an error)
#   tools/export_windows.ps1 -OutDir C:/scratch/out   # export somewhere other than <Path>/build/windows
param(
	[switch]$Debug,
	[string]$Path = "",
	[string]$Godot = "godot",
	[switch]$SkipSmoke,
	[int]$SmokeFrames = 1200,
	[string]$AssetsFrom = "",
	[switch]$AllowNoOriginalAssets,
	[string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
if ($Path -eq "") {
	$Path = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")).Path
}

# Replace $dst with the CONTENTS of $src. Copy-Item -Recurse onto an existing
# directory nests a second copy (build/windows/assets/original/original), so the
# target is cleared first and the children are copied.
function Copy-DirContents([string]$src, [string]$dst) {
	if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
	New-Item -ItemType Directory -Force -Path $dst | Out-Null
	Copy-Item -Recurse -Force -Path (Join-Path $src "*") -Destination $dst
}

# Gitignored per-developer folders are absent from a clean worktree; pull them
# from the main checkout (-AssetsFrom) before anything reads them.
if ($AssetsFrom -ne "") {
	foreach ($rel in @("addons/godotsteam", "assets/original")) {
		$from = Join-Path $AssetsFrom $rel
		if (Test-Path $from) {
			Write-Host "Copying $rel from $AssetsFrom into $Path"
			Copy-DirContents $from (Join-Path $Path $rel)
		} else {
			Write-Warning "$rel not found in $AssetsFrom; nothing copied."
		}
	}
}
if (-not $AllowNoOriginalAssets -and -not (Test-Path (Join-Path $Path "assets/original"))) {
	[Console]::Error.WriteLine("assets/original/ is missing in $Path. Install it (tools/install_original_assets.ps1), pass -AssetsFrom <main checkout>, or pass -AllowNoOriginalAssets to export without original-asset sound.")
	exit 4
}

$outDir = if ($OutDir -ne "") { $OutDir } else { Join-Path $Path "build/windows" }
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

# Bontago-1pi.74: bake the git revision into res://build_info.cfg for the menu label.
& $Godot --headless --path $Path -s tools/stamp_build_info.gd
if ($LASTEXITCODE -ne 0) {
	Write-Warning "stamp_build_info failed; the build label will show the version only."
}

$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
Write-Host "Exporting ($mode) from $Path to $exe"
& $Godot --headless --path $Path $mode "Windows Desktop" $exe
$exportCode = $LASTEXITCODE
# Bontago-1pi.136: the stamp is packed into the export; drop it from the
# checkout so later dev runs never show this export's revision.
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $Path "build_info.cfg")
if ($exportCode -ne 0) {
	Write-Error "Export failed with exit code $exportCode"
	exit $exportCode
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

# Playtest share (owner 2026-10-01): with the 480 test AppID a plain launch
# skips Steam init (game/Main.gd), so testers get a launcher that opts in.
$launcher = "@echo off`r`nstart `"`" `"%~dp0Stackfall.exe`" -- --steam-online --steam-public-lobby`r`n"
Set-Content -Path (Join-Path $outDir "Play Online (Steam).bat") -Value $launcher -Encoding ascii -NoNewline
$readme = @"
Stackfall playtest build

ONLINE OVER STEAM
1. Make sure Steam is running and you are logged in.
2. Start the game with "Play Online (Steam).bat" (not Stackfall.exe directly).
3. Host: main menu > Host > "Host on Steam".
4. Friends: main menu > Join > Steam tab > Refresh, then pick the host's lobby
   (everyone must run this same build). The in-lobby "Invite friends" button
   only works if the game was launched from Steam (add Stackfall.exe as a
   Non-Steam Game with launch options: -- --steam-online --steam-public-lobby).
   The build uses Steam's shared test app (Spacewar, AppID 480), so Steam
   may show you as playing "Spacewar". That is expected.

LOCAL / LAN
Run Stackfall.exe directly for local play, bots, LAN or direct IP.

CONTROLLERS
In online mode Steam Input (test AppID) can capture gamepads; if a pad does
not respond, use keyboard and mouse or disable Steam Input for Spacewar.

Windows may warn about an unknown publisher: More info > Run anyway.
"@
Set-Content -Path (Join-Path $outDir "README-PLAYTEST.txt") -Value $readme -Encoding ascii

# Sfx loads effect files directly from <exe dir>/assets/effects in exports,
# not from the PCK. Mirror that folder beside the exe or the editor's working
# hover sound (and all other effects) becomes silent in a packaged build.
$effectAssets = Join-Path $Path "assets/effects"
if (Test-Path $effectAssets) {
	Copy-DirContents $effectAssets (Join-Path $outDir "assets/effects")
} else {
	Write-Warning "assets/effects/ not found in $Path; the exported build will have no effects."
}

# Keep the optional original assets beside the exe for other direct-file
# consumers. The source folder is gitignored and installed per developer.
$originalAssets = Join-Path $Path "assets/original"
if (Test-Path $originalAssets) {
	Copy-DirContents $originalAssets (Join-Path $outDir "assets/original")
} else {
	Write-Warning "assets/original/ not installed in $Path (-AllowNoOriginalAssets); the export will run with no original-asset sound (see tools/install_original_assets.ps1)."
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
