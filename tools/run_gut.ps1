# Targeted GUT runner. The repo's .gutconfig.json always adds res://tests/, so
# `-gselect` on its own still runs the whole suite (~20 min). This writes a
# throwaway config that names only the requested script(s), so an iteration
# loop takes seconds. Run the full suite once at the end of a package
# (CLAUDE.md "Headless unit tests"); this is for the loop, not the gate.
#
# Usage:
#   tools/run_gut.ps1 test_net_session                 # one script (prefix/suffix optional)
#   tools/run_gut.ps1 test_net_session,test_steam_client
#   tools/run_gut.ps1 test_match_net -Unit test_a_client_ignores   # one test by name substring
#   tools/run_gut.ps1 -Dir res://tests/unit/net        # a directory instead of scripts
#   tools/run_gut.ps1 test_field -Path M:/Bontago-worktrees/x      # another checkout
#
# Exit code (Bontago-mv0.13): GUT 9.6.1's own -gexit path does set a non-zero
# process exit code when Gut.get_fail_count() > 0 (see
# addons/gut/gui/GutRunner.gd _handle_quit/_end_run) -- that part works. But a
# *fresh* checkout/worktree that hasn't had its global class_name cache built
# yet (no prior `--editor --quit` run) can fail to load a class_name-using
# autoload (observed: net/MatchNet.gd, "Could not find type X in the current
# scope") before GUT ever starts. That path never reaches _handle_quit at all,
# so no "Totals" block is printed and the process can still exit 0 despite
# zero tests having run. This is why CLAUDE.md's open-project check
# (`godot --headless --editor --path . --quit`) must be green before trusting
# any headless test result. To make this runner defend itself anyway (not
# just document it), it now captures stdout/stderr to a log, still streams it
# live, and forces a non-zero exit if $LASTEXITCODE was 0 but the log shows no
# "Totals" section, a "Failing Tests" count above 0, or a "SCRIPT ERROR" line.
#
# Self-test: `tests/unit/test_zz_throwaway_fail.gd` (deliberately-failing
# throwaway, deleted after use) reproduced exit 0 on a stale cache and exit 1
# once `godot --headless --editor --path . --quit` had primed the cache and
# again after the fallback parsing below was added; a normal passing script
# still exits 0. See the Bontago-mv0.13 checkpoint for the transcripts.
param(
	[Parameter(Position = 0)][string[]]$Scripts = @(),
	[string]$Dir = "",
	[string]$Unit = "",
	[string]$Path = "",
	[string]$Godot = "godot",
	[int]$LogLevel = 1
)

$ErrorActionPreference = "Stop"
if ($Path -eq "") {
	# $PSScriptRoot is not yet set while parameter defaults are evaluated
	# under Windows PowerShell 5.1, so resolve the repo root here instead.
	$Path = (Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")).Path
}
if ($Scripts.Count -eq 0 -and $Dir -eq "") {
	Write-Error "Name at least one test script (e.g. test_net_session) or pass -Dir."
	exit 2
}

# `powershell -File` hands a comma-separated list over as one string.
$Scripts = @($Scripts | ForEach-Object { $_ -split ',' } | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
$testsToRun = @()
foreach ($s in $Scripts) {
	$name = $s
	if (-not $name.StartsWith("test_")) { $name = "test_$name" }
	if (-not $name.EndsWith(".gd")) { $name = "$name.gd" }
	$candidates = Get-ChildItem -Path (Join-Path $Path "tests") -Recurse -Filter $name -ErrorAction SilentlyContinue
	if (-not $candidates) {
		Write-Error "No test script named $name under $Path/tests"
		exit 2
	}
	foreach ($c in $candidates) {
		$rel = $c.FullName.Substring($Path.Length).TrimStart('\', '/').Replace('\', '/')
		$testsToRun += "res://$rel"
	}
}

$config = [ordered]@{
	log_level = $LogLevel
	should_exit = $true
	should_exit_on_success = $true
	prefix = "test_"
	suffix = ".gd"
}
if ($Dir -ne "") {
	$config["dirs"] = @($Dir)
	$config["include_subdirs"] = $true
} else {
	$config["dirs"] = @()
	$config["tests"] = $testsToRun
}
if ($Unit -ne "") { $config["unit_test_name"] = $Unit }

$configDir = Join-Path $Path "tests/.gut_targeted"
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
$configFile = Join-Path $configDir ("run_" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".json")
($config | ConvertTo-Json -Depth 4) | Out-File -FilePath $configFile -Encoding ascii
$configRes = "res://tests/.gut_targeted/" + (Split-Path $configFile -Leaf)

Write-Host "GUT targeted: $($testsToRun -join ', ')$Dir (config $configRes)"
$outLog = Join-Path $configDir ("out_" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".log")
# `2>&1` merges the native process's stderr lines into the pipeline as
# ErrorRecord objects (not plain strings). Under $ErrorActionPreference =
# "Stop" (set above) that throws a terminating exception on the *first*
# stderr line Godot writes -- and Godot writes plenty of stderr even on a
# clean run (SCRIPT ERROR/WARNING lines) -- aborting this script before it
# ever reaches the exit-code logic below. Relax to "Continue" just for this
# call so stderr lines flow through and get captured like any other output.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $Godot --headless --path $Path -s addons/gut/gut_cmdln.gd "-gconfig=$configRes" -gexit 2>&1 | Tee-Object -FilePath $outLog
$code = $LASTEXITCODE
$ErrorActionPreference = $prevEap

$outText = ""
if (Test-Path $outLog) { $outText = Get-Content -Raw -LiteralPath $outLog -ErrorAction SilentlyContinue }

if ($code -eq 0) {
	$hasTotals = $outText -match 'Totals'
	$failingCount = 0
	if ($outText -match 'Failing Tests\s+(\d+)') { $failingCount = [int]$Matches[1] }
	$hasScriptError = $outText -match 'SCRIPT ERROR'

	if (-not $hasTotals) {
		Write-Host "run_gut.ps1: no GUT 'Totals' summary in the output (likely a fatal load error before tests ran) -- forcing exit 1." -ForegroundColor Red
		$code = 1
	} elseif ($failingCount -gt 0) {
		Write-Host "run_gut.ps1: GUT reported $failingCount failing test(s) but exited 0 -- forcing exit 1." -ForegroundColor Red
		$code = 1
	} elseif ($hasScriptError) {
		Write-Host "run_gut.ps1: SCRIPT ERROR found in output -- forcing exit 1." -ForegroundColor Red
		$code = 1
	}
}

Remove-Item -Force $configFile -ErrorAction SilentlyContinue
Remove-Item -Force $outLog -ErrorAction SilentlyContinue
exit $code
