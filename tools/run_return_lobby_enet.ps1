# Bontago-1pi.50: pause-menu Return to lobby, host + one lagged client on loopback under a
# hard wall-clock deadline. Modelled on tools/run_reset_enet.ps1: Process.Kill($true) ends the
# whole process tree (the godot shim spawns the real console exe) and a finally block does it
# again. -Port 0 (default) picks a random free UDP port.
# Exit code: 0 when both peers print "result=PASS", 1 otherwise or when the deadline was hit.
param([string]$Path = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path, [int]$Port = 0, [int]$Lag = 50, [string]$Out = $env:TEMP, [int]$TimeoutSeconds = 150)
$scene = "res://tests/bench/return_lobby_enet.tscn"
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
if ($Port -le 0) { $Port = Get-FreeUdpPort }
foreach ($f in @("rl_host.log", "rl_host.err", "rl_client.log", "rl_client.err")) { Remove-Item -ErrorAction SilentlyContinue "$Out\$f" }
$deadlineHit = $false
try {
	Write-Host "return_lobby_enet: port=$Port lag=${Lag}ms out=$Out"
	$h = Start-Process godot -ArgumentList @("--headless","--path",$Path,$scene,"--","--agent-probe","--headless-host","--port=$Port") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\rl_host.log" -RedirectStandardError "$Out\rl_host.err"
	$null = $h.Handle
	$script:procs += $h
	Start-Sleep 3
	$c = Start-Process godot -ArgumentList @("--headless","--path",$Path,$scene,"--","--agent-probe","--join=127.0.0.1:$Port","--sim-lag=$Lag") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\rl_client.log" -RedirectStandardError "$Out\rl_client.err"
	$null = $c.Handle
	$script:procs += $c
	$deadlineAt = (Get-Date).AddSeconds($TimeoutSeconds)
	while (((Get-Date) -lt $deadlineAt) -and (-not ($h.HasExited -and $c.HasExited))) { Start-Sleep 1 }
	if (-not ($h.HasExited -and $c.HasExited)) { $deadlineHit = $true; Write-Warning "hard deadline ($TimeoutSeconds s) exceeded" }
} finally {
	foreach ($p in $script:procs) { Stop-Tree $p }
}
$ok = $true
foreach ($role in @("host", "client")) {
	$lines = @(Get-Content "$Out\rl_${role}.log" -ErrorAction SilentlyContinue | Select-String "RLENET")
	$lines | ForEach-Object { $_.Line }
	if (@($lines | Where-Object { $_.Line -match "RLENET $role result=PASS" }).Count -ne 1) { $ok = $false }
}
$verdict = if ($ok -and -not $deadlineHit) { "PASS" } else { "FAIL" }
Write-Host "RLENET verdict=$verdict deadline_hit=$deadlineHit logs=$Out\rl_<role>.log"
if ($verdict -eq "FAIL") { exit 1 }
exit 0
