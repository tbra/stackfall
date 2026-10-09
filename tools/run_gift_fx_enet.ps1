# Bontago-1pi.85.17 (Gift fx J): host + three lagged clients on loopback under a hard wall-clock
# deadline (default 600 s). Process.Kill($true) ends the whole tree (the godot shim spawns the
# real console exe); the finally block does it again so an error cannot orphan a child.
# Prints every GFXENET line, then per-peer error-line counts. A deadline hit prints "timeout".
param(
	[string]$Path = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
	[int]$Port = 47795,
	[int]$Lag = 60,
	[string]$Out = $env:TEMP,
	[int]$TimeoutSeconds = 600,
	[switch]$WeatherOff
)
$scene = "res://tests/bench/gift_fx_enet.tscn"
. (Join-Path $PSScriptRoot "enet_result.ps1")
$procs = @()
$extra = @(); if ($WeatherOff) { $extra = @("--weather-off") }
function Stop-Tree([object]$p) {
	if ($p -and -not $p.HasExited) {
		Write-Host "killing process tree $($p.Id)"
		try { $p.Kill($true) } catch { Write-Warning "kill $($p.Id): $_" }
	}
}
$timedOut = $false
try {
	$h = Start-Process godot -ArgumentList (@("--headless","--log-file","${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--headless-host","--port=$Port","--expect-peers=4") + $extra) -PassThru -NoNewWindow -RedirectStandardOutput "$Out\gfx_host.log" -RedirectStandardError "$Out\gfx_host.err"
	$null = $h.Handle
	$procs += $h
	Start-Sleep 3
	foreach ($i in 1..3) {
		$c = Start-Process godot -ArgumentList @("--headless","--log-file","${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--join=127.0.0.1:$Port","--sim-lag=$Lag") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\gfx_client$i.log" -RedirectStandardError "$Out\gfx_client$i.err"
		$null = $c.Handle
		$procs += $c
	}
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while ((Get-Date) -lt $deadline) {
		$allDone = $true
		foreach ($p in $procs) { if (-not $p.HasExited) { $allDone = $false } }
		if ($allDone) { break }
		Start-Sleep 1
	}
	foreach ($p in $procs) { if (-not $p.HasExited) { $timedOut = $true } }
	if ($timedOut) { Write-Warning "timeout: hard deadline ($TimeoutSeconds s) exceeded" }
} finally {
	foreach ($p in $procs) { Stop-Tree $p }
}
$logs = @("$Out\gfx_host.log") + (1..3 | ForEach-Object { "$Out\gfx_client$_.log" })
$logSpecs = @(@{ name = "host"; path = "$Out\gfx_host.log"; pass = 'GFXENET host result=PASS' })
foreach ($i in 1..3) { $logSpecs += @{ name = "client$i"; path = "$Out\gfx_client$i.log"; pass = 'GFXENET client slot=\d+ result=PASS' } }
foreach ($log in $logs) {
	Write-Host "== $log"
	Get-Content $log | Select-String "GFXENET"
}
foreach ($name in @("host","client1","client2","client3")) {
	$n = 0
	foreach ($ext in @("log","err")) {
		$f = "$Out\gfx_$name.$ext"
		if (Test-Path $f) { $n += @(Select-String -Path $f -Pattern "ERROR:|SCRIPT ERROR|Parse Error|WARNING:").Count }
	}
	Write-Host "ERRORLINES $name=$n"
}
if ($timedOut) { Write-Host "RESULT timeout" }
exit (Write-EnetResult -DeadlineHit $timedOut -Logs $logSpecs)
