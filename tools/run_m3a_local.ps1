# M3a local acceptance harness (docs/M3a_PLAN.md P4, "Testing without a
# second PC"). Launches 1 headless host + (Peers - 1) headless clients, all
# on 127.0.0.1, running tests/bench/m3a_acceptance.tscn, and aggregates their
# exit codes. Client 1 gets -SimLag / -SimLoss, which defaults to spec Part 4
# M3's acceptance condition itself: "a client with 100 ms of simulated lag
# and 2% packet loss sees smooth towers."
#
# Must run the scene, not a -s script: commit 12d2ec2's gotcha is that
# autoload identifiers (Net, Match) do not resolve when a .gd file is run
# with -s as a bare SceneTree, so m3a_acceptance has to be a .tscn the way
# m2_acceptance is (docs/M3a_PLAN.md "Testing without a second PC").
#
# Usage:
#   tools/run_m3a_local.ps1
#   tools/run_m3a_local.ps1 -Peers 4 -SimLag 100 -SimLoss 0.02
#   tools/run_m3a_local.ps1 -Peers 2 -SimLag 0 -SimLoss 0    # a clean run, no simulated link
#
# Exit code: 0 if every instance exited 0; the first non-zero exit code
# otherwise (an instance exiting 2 means it hit the "layer is still a stub"
# guard in m3a_acceptance.gd rather than actually failing an assertion — see
# that script's header).

param(
	[int]$Peers = 4,
	[int]$Port = 47778,
	[double]$SimLag = 100,
	[double]$SimLoss = 0.02,
	[string]$Godot = "godot",
	[int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

if ($Peers -lt 1) {
	Write-Error "Peers must be at least 1 (the host)."
	exit 1
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scenePath = "res://tests/bench/m3a_acceptance.tscn"
$logDir = Join-Path $env:TEMP "m3a_local_$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $logDir | Out-Null
Write-Host "M3A harness: logs in $logDir"

function Start-Instance {
	param([string]$Name, [string[]]$GameArgs)
	$outLog = Join-Path $logDir "$Name.out.log"
	$errLog = Join-Path $logDir "$Name.err.log"
	$allArgs = @("--headless", "--path", $repoRoot, $scenePath, "--") + $GameArgs
	$process = Start-Process -FilePath $Godot -ArgumentList $allArgs -PassThru -NoNewWindow `
		-RedirectStandardOutput $outLog -RedirectStandardError $errLog
	return [pscustomobject]@{ Name = $Name; Process = $process; OutLog = $outLog; ErrLog = $errLog }
}

$instances = @()
# DECISION (tools/run_m3a_local.ps1): m3a_acceptance.gd's own --expect-peers
# defaults to 1 (its "harness has no equivalent of --headless-host" flag,
# read directly off the command line rather than through
# Net.apply_command_line()). Without it here the host proceeded with a
# 2-player MatchConfig (MatchConfig.PLAYER_COUNT_MIN) while $Peers real
# peers had actually joined, so slot_of_peer() collisions in the host's
# per-slot counters masqueraded as duplicate/lost placements. The host must
# be told how many peers this run is actually bringing.
$instances += Start-Instance -Name "host" -GameArgs @("--headless-host", "--port=$Port", "--expect-peers=$Peers")

# The host needs a moment to bind and start advertising before a client
# dials in directly (tests/support/... has no equivalent for a live socket,
# so this is a real wait, not a poll-until-blocked check).
Start-Sleep -Seconds 2

for ($i = 1; $i -lt $Peers; $i++) {
	$clientArgs = @("--join=127.0.0.1:$Port")
	if ($i -eq 1) {
		$clientArgs += "--sim-lag=$SimLag"
		$clientArgs += "--sim-loss=$SimLoss"
	}
	$instances += Start-Instance -Name "client$i" -GameArgs $clientArgs
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
foreach ($instance in $instances) {
	$remaining = [Math]::Max(1, [int](($deadline - (Get-Date)).TotalMilliseconds))
	if (-not $instance.Process.WaitForExit($remaining)) {
		Write-Warning "$($instance.Name) did not exit within $TimeoutSeconds s; killing it."
		try { $instance.Process.Kill() } catch {}
	}
}

$exitCodes = @{}
foreach ($instance in $instances) {
	$code = $instance.Process.ExitCode
	$exitCodes[$instance.Name] = $code
	Write-Host "--- $($instance.Name) (exit $code) ---"
	if (Test-Path $instance.OutLog) { Get-Content $instance.OutLog | Where-Object { $_ -match "M3A_ACCEPT" } | ForEach-Object { Write-Host $_ } }
	if ((Test-Path $instance.ErrLog) -and ((Get-Item $instance.ErrLog).Length -gt 0)) {
		Write-Host "  (stderr, see $($instance.ErrLog))"
	}
}

$failed = $exitCodes.GetEnumerator() | Where-Object { $_.Value -ne 0 }
if ($failed) {
	Write-Host "M3A harness FAILED: $($failed.Name -join ', ') exited non-zero. Full logs in $logDir"
	exit 1
}
Write-Host "M3A harness PASSED ($Peers instances). Full logs in $logDir"
exit 0
