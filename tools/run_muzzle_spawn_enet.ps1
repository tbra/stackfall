# host + 1 lagged client over loopback ENet, hard wall-clock deadline.
param(
	[string]$Path = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
	[int]$Port = 47813,
	[int]$Lag = 60,
	[string]$Out = $env:TEMP,
	[int]$TimeoutSeconds = 150
)
$scene = "res://tests/enet/muzzle_spawn_enet.tscn"
. (Join-Path $PSScriptRoot "enet_result.ps1")
$procs = @()
$timedOut = $false
try {
	$h = Start-Process godot -ArgumentList @("--headless","--log-file","${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--headless-host","--port=$Port","--expect-peers=2") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\muz_host.log" -RedirectStandardError "$Out\muz_host.err"
	$null = $h.Handle
	$procs += $h
	Start-Sleep 3
	$c = Start-Process godot -ArgumentList @("--headless","--log-file","${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--join=127.0.0.1:$Port","--sim-lag=$Lag") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\muz_client.log" -RedirectStandardError "$Out\muz_client.err"
	$null = $c.Handle
	$procs += $c
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while ((Get-Date) -lt $deadline) {
		$allDone = $true
		foreach ($p in $procs) { if (-not $p.HasExited) { $allDone = $false } }
		if ($allDone) { break }
		Start-Sleep 1
	}
	foreach ($p in $procs) { if (-not $p.HasExited) { $timedOut = $true } }
} finally {
	foreach ($p in $procs) { if ($p -and -not $p.HasExited) { try { $p.Kill($true) } catch { } } }
}
foreach ($log in @("$Out\muz_host.log","$Out\muz_client.log")) {
	Write-Host "== $log"
	Get-Content $log | Select-String "MUZZLEENET"
}
foreach ($name in @("host","client")) {
	$n = 0
	foreach ($ext in @("log","err")) {
		$f = "$Out\muz_$name.$ext"
		if (Test-Path $f) { $n += @(Select-String -Path $f -Pattern "ERROR:|SCRIPT ERROR|Parse Error|WARNING:").Count }
	}
	Write-Host "ERRORLINES $name=$n"
}
if ($timedOut) { Write-Host "RESULT timeout" }
# The muzzle client prints no verdict of its own; only the fail scan applies to it.
exit (Write-EnetResult -DeadlineHit $timedOut -Logs @(
	@{ name = "host"; path = "$Out\muz_host.log"; pass = 'MUZZLEENET host result=PASS' },
	@{ name = "client"; path = "$Out\muz_client.log"; pass = $null }))
