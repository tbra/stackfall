# Bontago-1pi.46 R3: match-reset fingerprint over real ENet. Runs tests/bench/reset_enet.gd
# twice -- mode "fresh" (host + lagged client start match B on a fresh launch, fingerprints
# written to -Out) then mode "dirty" (they play match A, Replay, a client leave/re-join, then
# B, and diff against the fresh fingerprints) -- under one shared hard deadline.
# Modelled on tools/run_qol_enet.ps1: Process.Kill($true) ends the whole process tree (the
# godot shim spawns the real console exe), and a finally block does it again.
# -Port 0 (default) picks a random free UDP port per run so parallel runs never collide.
# Exit code: 0 when every peer of both runs prints "result=PASS" (verdict PASS) or "result=PENDING"
# (only the known seat gap differs, verdict PENDING); 1 otherwise or when a deadline was hit.
param([string]$Path = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path, [int]$Port = 0, [int]$Lag = 50, [string]$Out = $env:TEMP, [int]$TimeoutSeconds = 900)
$scene = "res://tests/bench/reset_enet.tscn"
$deadlineAt = (Get-Date).AddSeconds($TimeoutSeconds)
$script:deadlineHit = $false
$script:pending = $false
$script:procs = @()
function Stop-Tree([object]$p) {
	if ($p -and -not $p.HasExited) {
		Write-Host "killing process tree $($p.Id)"
		try { $p.Kill($true) } catch { Write-Warning "kill $($p.Id): $_" }
	}
}
function Get-FreeUdpPort {
	$udp = New-Object System.Net.Sockets.UdpClient(0)
	try { return ([System.Net.IPEndPoint]$udp.Client.LocalEndPoint).Port } finally { $udp.Close() }
}
function Invoke-Pair([string]$mode, [int]$pairPort) {
	foreach ($f in @("reset_${mode}_host.log", "reset_${mode}_host.err", "reset_${mode}_client.log", "reset_${mode}_client.err")) { Remove-Item -ErrorAction SilentlyContinue "$Out\$f" }
	$h = Start-Process godot -ArgumentList @("--headless","--log-file","${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--agent-probe","--headless-host","--port=$pairPort","--mode=$mode","--out-dir=$Out") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\reset_${mode}_host.log" -RedirectStandardError "$Out\reset_${mode}_host.err"
	$null = $h.Handle
	$script:procs += $h
	Start-Sleep 3
	$c = Start-Process godot -ArgumentList @("--headless","--log-file","${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--agent-probe","--join=127.0.0.1:$pairPort","--sim-lag=$Lag","--mode=$mode","--out-dir=$Out") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\reset_${mode}_client.log" -RedirectStandardError "$Out\reset_${mode}_client.err"
	$null = $c.Handle
	$script:procs += $c
	while (((Get-Date) -lt $deadlineAt) -and (-not ($h.HasExited -and $c.HasExited))) { Start-Sleep 1 }
	if (-not ($h.HasExited -and $c.HasExited)) { $script:deadlineHit = $true; Write-Warning "hard deadline ($TimeoutSeconds s) exceeded in mode $mode" }
	Stop-Tree $h
	Stop-Tree $c
}
foreach ($f in @("fp_host.var", "fp_client.var")) { Remove-Item -ErrorAction SilentlyContinue "$Out\$f" }
$verdicts = @{}
try {
	foreach ($mode in @("fresh", "dirty")) {
		$pairPort = if ($Port -gt 0) { $Port } else { Get-FreeUdpPort }
		Write-Host "reset_enet: mode=$mode port=$pairPort lag=${Lag}ms out=$Out"
		Invoke-Pair $mode $pairPort
		foreach ($role in @("host", "client")) {
			$lines = @(Get-Content "$Out\reset_${mode}_${role}.log" -ErrorAction SilentlyContinue | Select-String "RESETENET")
			$lines | Where-Object { $_.Line -notmatch " fp (countdown|playing) " } | ForEach-Object { $_.Line }
			$verdicts["$mode/$role"] = @($lines | Where-Object { $_.Line -match "RESETENET $role result=(PASS|PENDING)" }).Count -eq 1
			if (@($lines | Where-Object { $_.Line -match "RESETENET $role result=PENDING" }).Count -gt 0) { $script:pending = $true }
		}
		if (-not $verdicts["$mode/host"] -or -not $verdicts["$mode/client"]) { break }
	}
} finally {
	foreach ($p in $script:procs) { Stop-Tree $p }
}
$failed = @($verdicts.Values | Where-Object { -not $_ }).Count
$allPass = ($verdicts.Count -eq 4) -and ($failed -eq 0)
$verdict = if ($allPass -and -not $script:deadlineHit) { if ($script:pending) { "PENDING" } else { "PASS" } } else { "FAIL" }
$summary = ($verdicts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join " "
Write-Host "RESETENET verdict=$verdict $summary deadline_hit=$($script:deadlineHit) logs=$Out\reset_<mode>_<role>.log"
if ($verdict -eq "FAIL") { exit 1 }
exit 0
