# Bontago-1pi.32: loading-ready gate, host + one client on loopback under a hard wall-clock deadline.
# Follows tools/run_m3a_local.ps1: Process.Kill($true) ends the whole process
# tree (the godot shim spawns the real console exe), and a finally block does it
# again so an error or Ctrl+C cannot orphan a child.
param([string]$Path = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path, [int]$Port = 47795, [int]$Lag = 50, [string]$Out = $env:TEMP, [int]$TimeoutSeconds = 60, [switch]$Late)
$scene = "res://tests/bench/loading_ready_enet.tscn"
$procs = @()
function Stop-Tree([object]$p) {
	if ($p -and -not $p.HasExited) {
		Write-Host "killing process tree $($p.Id)"
		try { $p.Kill($true) } catch { Write-Warning "kill $($p.Id): $_" }
	}
}
try {
	$hostArgs = @("--headless","--log-file","$Outgodot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--headless-host","--port=$Port","--expect-peers=2")
	if ($Late) { $hostArgs += "--late-step" }
	$h = Start-Process godot -ArgumentList $hostArgs -PassThru -NoNewWindow -RedirectStandardOutput "$Out\lr_host.log" -RedirectStandardError "$Out\lr_host.err"
	$null = $h.Handle
	$procs += $h
	Start-Sleep 3
	$c = Start-Process godot -ArgumentList @("--headless","--log-file","$Outgodot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--join=127.0.0.1:$Port","--sim-lag=$Lag") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\lr_client.log" -RedirectStandardError "$Out\lr_client.err"
	$null = $c.Handle
	$procs += $c
	if ($Late) {
		# Bontago-1pi.42: a third peer joins while the host's gate is still closed (the
		# host holds its own ready press until that peer is seated).
		Start-Sleep 5
		$l = Start-Process godot -ArgumentList @("--headless","--log-file","$Outgodot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--join=127.0.0.1:$Port","--sim-lag=$Lag","--late-joiner") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\lr_late.log" -RedirectStandardError "$Out\lr_late.err"
		$null = $l.Handle
		$procs += $l
	}
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while (((Get-Date) -lt $deadline) -and (-not (($procs | Where-Object { -not $_.HasExited }).Count -eq 0))) { Start-Sleep 1 }
	if (($procs | Where-Object { -not $_.HasExited }).Count -gt 0) { Write-Warning "hard deadline ($TimeoutSeconds s) exceeded" }
} finally {
	foreach ($p in $procs) { Stop-Tree $p }
}
Get-Content "$Out\lr_host.log" | Select-String "LRENET"
Get-Content "$Out\lr_client.log" | Select-String "LRENET"
if ($Late -and (Test-Path "$Out\lr_late.log")) { Get-Content "$Out\lr_late.log" | Select-String "LRENET" }
