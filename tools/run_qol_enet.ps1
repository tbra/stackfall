# Bontago-1pi.18.8 (QoL Q4): host + one lagged client on loopback, the QoL toggle
# matrix of tests/bench/qol_enet.gd, under a hard wall-clock deadline.
# Follows tools/run_m3a_local.ps1: Process.Kill($true) ends the whole process
# tree (the godot shim spawns the real console exe), and a finally block does it
# again so an error or Ctrl+C cannot orphan a child.
# -Port 0 (default) picks a random free UDP port so parallel runs never collide.
# Probe mode: --headless plus --agent-probe (the scene also lives under tests/bench/).
# Exit code: 0 only when BOTH peers print "result=PASS" and neither hit the deadline;
# 1 otherwise. Log lines (QOLENET ...) are echoed per peer for inspection.
param([string]$Path = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path, [int]$Port = 0, [int]$Lag = 50, [string]$Out = $env:TEMP, [int]$TimeoutSeconds = 180)
$scene = "res://tests/bench/qol_enet.tscn"
$procs = @()
$deadlineHit = $false
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
if ($Port -le 0) { $Port = Get-FreeUdpPort }
Write-Host "qol_enet: port=$Port lag=${Lag}ms deadline=${TimeoutSeconds}s out=$Out"
foreach ($f in @("qol_host.log", "qol_host.err", "qol_client.log", "qol_client.err")) { Remove-Item -ErrorAction SilentlyContinue "$Out\$f" }
try {
	$h = Start-Process godot -ArgumentList @("--headless","--path",$Path,$scene,"--","--agent-probe","--headless-host","--port=$Port","--expect-peers=2") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\qol_host.log" -RedirectStandardError "$Out\qol_host.err"
	$null = $h.Handle
	$procs += $h
	Start-Sleep 3
	$c = Start-Process godot -ArgumentList @("--headless","--path",$Path,$scene,"--","--agent-probe","--join=127.0.0.1:$Port","--sim-lag=$Lag") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\qol_client.log" -RedirectStandardError "$Out\qol_client.err"
	$null = $c.Handle
	$procs += $c
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while (((Get-Date) -lt $deadline) -and (-not ($h.HasExited -and $c.HasExited))) { Start-Sleep 1 }
	if (-not ($h.HasExited -and $c.HasExited)) { $deadlineHit = $true; Write-Warning "hard deadline ($TimeoutSeconds s) exceeded" }
} finally {
	foreach ($p in $procs) { Stop-Tree $p }
}
$hostLines = @(Get-Content "$Out\qol_host.log" -ErrorAction SilentlyContinue | Select-String "QOLENET")
$clientLines = @(Get-Content "$Out\qol_client.log" -ErrorAction SilentlyContinue | Select-String "QOLENET")
$hostLines
$clientLines
$hostPass = @($hostLines | Where-Object { $_.Line -match "QOLENET host result=PASS" }).Count -eq 1
$clientPass = @($clientLines | Where-Object { $_.Line -match "QOLENET client result=PASS" }).Count -eq 1
$anyFail = @(($hostLines + $clientLines) | Where-Object { $_.Line -match "ok=False|result=FAIL" }).Count -gt 0
$verdict = if ($hostPass -and $clientPass -and -not $anyFail -and -not $deadlineHit) { "PASS" } else { "FAIL" }
Write-Host "QOLENET verdict=$verdict host_pass=$hostPass client_pass=$clientPass deadline_hit=$deadlineHit logs=$Out\qol_host.log,$Out\qol_client.log"
if ($verdict -ne "PASS") { exit 1 }
exit 0
