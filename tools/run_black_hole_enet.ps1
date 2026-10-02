# Bontago-8or.25: host + one lagged client on loopback, hard 180 s deadline.
param([string]$Path = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path, [int]$Port = 47793, [int]$Lag = 150, [string]$Out = $env:TEMP)
$scene = "res://tests/bench/black_hole_enet.tscn"
$h = $null; $c = $null
try {
	$h = Start-Process godot -ArgumentList @("--headless","--path",$Path,$scene,"--","--headless-host","--port=$Port","--expect-peers=2") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\bh_host.log" -RedirectStandardError "$Out\bh_host.err"
	Start-Sleep 3
	$c = Start-Process godot -ArgumentList @("--headless","--path",$Path,$scene,"--","--join=127.0.0.1:$Port","--sim-lag=$Lag") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\bh_client.log" -RedirectStandardError "$Out\bh_client.err"
	$null = $h.Handle; $null = $c.Handle
	$deadline = (Get-Date).AddSeconds(180)
	while (((Get-Date) -lt $deadline) -and (-not ($h.HasExited -and $c.HasExited))) { Start-Sleep 1 }
} finally {
	foreach ($p in @($h, $c)) { if ($p -and -not $p.HasExited) { Write-Host "deadline: killing tree $($p.Id)"; taskkill /T /F /PID $p.Id | Out-Null } }
}
Get-Content "$Out\bh_host.log","$Out\bh_client.log" | Select-String "BHENET"
