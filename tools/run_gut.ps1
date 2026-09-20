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
& $Godot --headless --path $Path -s addons/gut/gut_cmdln.gd "-gconfig=$configRes" -gexit
$code = $LASTEXITCODE
Remove-Item -Force $configFile -ErrorAction SilentlyContinue
exit $code
