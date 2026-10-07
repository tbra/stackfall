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
#   tools/run_m3a_local.ps1 -Peers 2 -ThrowPass               # + the M4 P2c-ii throw phase
#
# Exit code: 0 if every instance exited 0; the first non-zero exit code
# otherwise (an instance exiting 2 means it hit the "layer is still a stub"
# guard in m3a_acceptance.gd rather than actually failing an assertion — see
# that script's header). -ThrowPass passes tests/bench/m3a_acceptance.gd's own
# --throw-pass flag to every instance; a throw-phase failure there already
# makes that instance exit 1 (see m3a_acceptance.gd's _ready()), so no extra
# handling is needed here for "the ps1 fails on FAIL" -- the existing
# non-zero-exit check below already covers it.

param(
	[int]$Peers = 4,
	[int]$Port = 47778,
	[double]$SimLag = 100,
	[double]$SimLoss = 0.02,
	[string]$Godot = "godot",
	[int]$TimeoutSeconds = 120,
	[switch]$ThrowPass,
	[switch]$ReconnectPass,
	[int]$LateJoinAfter = 0
)

$ErrorActionPreference = "Stop"

if ($Peers -lt 1) {
	Write-Error "Peers must be at least 1 (the host)."
	exit 1
}

# Bontago-8or.11 (integrator): hard wall-clock timeout to prevent hung processes.
# Ensures that processes cannot hang indefinitely; they will be forcefully killed if exceeded.
[int]$hardTimeoutSeconds = $TimeoutSeconds
if ($LateJoinAfter -gt 0) {
	# Late-join scenario adds a few seconds of extra latency, but the total should still
	# fit within the standard TimeoutSeconds (120s). If not specified otherwise, use 120s for late-join too.
	# Timeline: host init (2s) + client connect (2s) + match start (5s) + placement phase (30s) +
	#           late joiner connect (4s) + late joiner replay ack (8s) + settle (1s) + margin (3s) = ~55s
	Write-Host "M3A harness: late-join detected, hard timeout set to $hardTimeoutSeconds seconds"
} else {
	# Standard run uses the default or specified TimeoutSeconds
	Write-Host "M3A harness: standard run, hard timeout set to $hardTimeoutSeconds seconds"
}
$hardDeadlineMs = [System.Diagnostics.Stopwatch]::GetTimestamp() + ([long]$hardTimeoutSeconds * [System.Diagnostics.Stopwatch]::Frequency)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scenePath = "res://tests/bench/m3a_acceptance.tscn"
$logDir = Join-Path $env:TEMP "m3a_local_$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $logDir | Out-Null
Write-Host "M3A harness: logs in $logDir"

function Start-Instance {
	param([string]$Name, [string[]]$GameArgs)
	$outLog = Join-Path $logDir "$Name.out.log"
	$errLog = Join-Path $logDir "$Name.err.log"
	$allArgs = @("--headless", "--log-file", (Join-Path $logDir "$Name.godot.log"), "--path", $repoRoot, $scenePath, "--") + $GameArgs
	$process = Start-Process -FilePath $Godot -ArgumentList $allArgs -PassThru -NoNewWindow `
		-RedirectStandardOutput $outLog -RedirectStandardError $errLog
	# Touch the handle: without this, PowerShell's Process object never caches
	# it and $process.ExitCode reads back $null after the child exits, so
	# every instance reported "(exit )" and the run was declared FAILED even
	# when all four peers printed M3A_ACCEPT result=PASS (found while
	# validating Bontago-mv0.1.4-.6).
	$null = $process.Handle
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
# Bontago-8or.11: --late-join-after triggers mid-match join testing; if set,
# the host expects one extra client to join after the match starts.
$expectedPeers = $Peers
if ($LateJoinAfter -gt 0) {
	$expectedPeers += 1
}
$hostArgs = @("--headless-host", "--port=$Port", "--expect-peers=$expectedPeers")
if ($ThrowPass) {
	$hostArgs += "--throw-pass"
}
if ($LateJoinAfter -gt 0) {
	$hostArgs += "--late-join-after=$LateJoinAfter"
}
# Bontago-fca.30: a real mid-match drop + rejoin of the slot-1 client.
if ($ReconnectPass) {
	$hostArgs += "--reconnect-pass"
}
$instances += Start-Instance -Name "host" -GameArgs $hostArgs

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
	if ($ThrowPass) {
		$clientArgs += "--throw-pass"
	}
	if ($ReconnectPass) {
		$clientArgs += "--reconnect-pass"
	}
	# Bontago-8or.11: pass late-join flag to initial clients so they stay alive longer
	if ($LateJoinAfter -gt 0) {
		$clientArgs += "--late-join-after=$LateJoinAfter"
	}
	$instances += Start-Instance -Name "client$i" -GameArgs $clientArgs
}

# Bontago-8or.11: late-join scenario --- spawn an extra client before regular clients.
# Start the late-join client immediately so it arrives quickly and gives the host time
# to wait for all expected peers before the placement phase begins.
# This ensures the late joiner is present in Net.peer_ids() during the placement phase,
# not after the regular clients have exited.
if ($LateJoinAfter -gt 0) {
	# Wait just long enough for the host to bind (1s is enough; default is 2s)
	$lateJoinWait = 2.5  # 2.5s from script start
	Write-Host "M3A harness: waiting $lateJoinWait seconds before starting late-join client"
	Start-Sleep -Seconds $lateJoinWait
	$lateClientArgs = @("--join=127.0.0.1:$Port", "--late-join", "--sim-lag=$SimLag", "--sim-loss=$SimLoss")
	if ($ThrowPass) {
		$lateClientArgs += "--throw-pass"
	}
	$instances += Start-Instance -Name "client_late" -GameArgs $lateClientArgs
}

# Bontago-8or.11: hard wall-clock timeout check with aggressive process termination.
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
foreach ($instance in $instances) {
	# Check hard deadline (wall-clock, not based on this loop's position)
	$nowMs = [System.Diagnostics.Stopwatch]::GetTimestamp()
	if ($nowMs -gt $hardDeadlineMs) {
		Write-Warning "Hard wall-clock deadline exceeded; killing all remaining processes"
		foreach ($inst in $instances) {
			if ($inst.Process -and -not $inst.Process.HasExited) {
				try {
					$inst.Process.Kill($true)  # Kill with children
					Write-Warning "Forcefully killed process: $($inst.Name) (PID $($inst.Process.Id))"
				} catch {
					Write-Warning "Failed to kill $($inst.Name): $_"
				}
			}
		}
		break
	}

	$remaining = [Math]::Max(1, [int](($deadline - (Get-Date)).TotalMilliseconds))
	if (-not $instance.Process.WaitForExit($remaining)) {
		Write-Warning "$($instance.Name) did not exit within $TimeoutSeconds s; killing it."
		try { $instance.Process.Kill($true) } catch {}
	}
}

$exitCodes = @{}
foreach ($instance in $instances) {
	$code = $instance.Process.ExitCode
	$exitCodes[$instance.Name] = $code
	Write-Host "--- $($instance.Name) (exit $code) ---"
	if (Test-Path $instance.OutLog) { Get-Content $instance.OutLog | Where-Object { $_ -match "M3A_ACCEPT|M3A_THROW" } | ForEach-Object { Write-Host $_ } }
	if ((Test-Path $instance.ErrLog) -and ((Get-Item $instance.ErrLog).Length -gt 0)) {
		Write-Host "  (stderr, see $($instance.ErrLog))"
	}
}

# Bontago-fca.30: a reconnect run must also be clean of engine errors/warnings
# (bad RPCs, dangling peers) in every instance's logs. The engine's
# quit-time "ObjectDB instances were leaked at exit" line is excluded: it also
# appears intermittently in runs without this pass (98 of the old run logs);
# live orphan nodes are asserted in-process instead (Performance monitor).
$logProblems = @()
if ($ReconnectPass) {
	foreach ($instance in $instances) {
		foreach ($log in @($instance.OutLog, $instance.ErrLog)) {
			if (Test-Path $log) {
				$hits = Select-String -Path $log -Pattern "ERROR:|SCRIPT ERROR|WARNING:|leaked|orphan" | Where-Object { $_.Line -notmatch "M3A_ACCEPT" -and $_.Line -notmatch "ObjectDB instances were leaked at exit" }
				foreach ($hit in $hits) { $logProblems += "$($instance.Name): $($hit.Line)" }
			}
		}
	}
	if ($logProblems.Count -gt 0) {
		Write-Host "M3A harness: reconnect pass found $($logProblems.Count) error/warning log line(s):"
		$logProblems | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
	}
}

$failed = $exitCodes.GetEnumerator() | Where-Object { $_.Value -ne 0 }
if ($failed) {
	Write-Host "M3A harness FAILED: $($failed.Name -join ', ') exited non-zero. Full logs in $logDir"
	exit 1
}
if ($logProblems.Count -gt 0) {
	Write-Host "M3A harness FAILED: engine errors/warnings in logs. Full logs in $logDir"
	exit 1
}
$totalInstances = $instances.Count
Write-Host "M3A harness PASSED ($totalInstances instances). Full logs in $logDir"
exit 0
