# Bontago-1pi.188/189: beacon timer labels over ENet (-Mode classic|ctf). Based on run_live_scores_enet. Host + one client on loopback under a hard wall-clock deadline.
# Follows tools/run_m3a_local.ps1: Process.Kill($true) ends the whole process
# tree (the godot shim spawns the real console exe), and a finally block does it
# again so an error or Ctrl+C cannot orphan a child.
param([string]$Path = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path, [string]$Mode = "classic", [int]$Port = 47797, [int]$Lag = 50, [string]$Out = $env:TEMP, [int]$TimeoutSeconds = 180)
$scene = "res://tests/enet/beacon_timers_enet.tscn"
. (Join-Path $PSScriptRoot "enet_result.ps1")
$procs = @()
$deadlineHit = $false
function Stop-Tree([object]$p) {
	if ($p -and -not $p.HasExited) {
		Write-Host "killing process tree $($p.Id)"
		try { $p.Kill($true) } catch { Write-Warning "kill $($p.Id): $_" }
	}
}
try {
	$h = Start-Process godot -ArgumentList @("--headless","--log-file","${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--headless-host","--port=$Port","--expect-peers=2","--mode=$Mode") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\bt_host.log" -RedirectStandardError "$Out\bt_host.err"
	$null = $h.Handle
	$procs += $h
	Start-Sleep 3
	$c = Start-Process godot -ArgumentList @("--headless","--log-file","${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--join=127.0.0.1:$Port","--sim-lag=$Lag","--mode=$Mode") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\bt_client.log" -RedirectStandardError "$Out\bt_client.err"
	$null = $c.Handle
	$procs += $c
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while (((Get-Date) -lt $deadline) -and (-not ($h.HasExited -and $c.HasExited))) { Start-Sleep 1 }
	if (-not ($h.HasExited -and $c.HasExited)) { $deadlineHit = $true; Write-Warning "hard deadline ($TimeoutSeconds s) exceeded" }
} finally {
	foreach ($p in $procs) { Stop-Tree $p }
}
foreach ($role in @("host", "client")) { Get-Content "$Out\bt_$role.log" -ErrorAction SilentlyContinue | Select-String "BTENET" }
exit (Write-EnetResult -DeadlineHit $deadlineHit -Logs @(
	@{ name = "host"; path = "$Out\bt_host.log"; pass = $null },
	@{ name = "client"; path = "$Out\bt_client.log"; pass = 'BTENET result=PASS' }))
