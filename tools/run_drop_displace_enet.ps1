# Bontago-1pi.14: host + one lagged client on loopback, hard 180 s deadline.
param([string]$Path = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path, [int]$Port = 47791, [int]$Lag = 150, [string]$BPose = "-26.6,0.99,-0.1", [string]$Out = $env:TEMP)
$scene = "res://tests/bench/drop_displace_enet.tscn"
. (Join-Path $PSScriptRoot "enet_result.ps1")
$h = Start-Process godot -ArgumentList @("--headless","--log-file","${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--headless-host","--port=$Port","--expect-peers=2") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\dd_host.log" -RedirectStandardError "$Out\dd_host.err"
Start-Sleep 3
$c = Start-Process godot -ArgumentList @("--headless","--log-file","${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log","--path",$Path,$scene,"--","--join=127.0.0.1:$Port","--sim-lag=$Lag","--b-pose=$BPose") -PassThru -NoNewWindow -RedirectStandardOutput "$Out\dd_client.log" -RedirectStandardError "$Out\dd_client.err"
$null = $h.Handle; $null = $c.Handle
$deadline = (Get-Date).AddSeconds(180)
while (((Get-Date) -lt $deadline) -and (-not ($h.HasExited -and $c.HasExited))) { Start-Sleep 1 }
$deadlineHit = -not ($h.HasExited -and $c.HasExited)
foreach ($p in @($h, $c)) { if (-not $p.HasExited) { Write-Host "deadline: killing $($p.Id)"; Stop-Process -Id $p.Id -Force } }
Get-Content "$Out\dd_host.log" | Select-String "DROPDISP"
exit (Write-EnetResult -DeadlineHit $deadlineHit -Logs @(
	@{ name = "host"; path = "$Out\dd_host.log"; pass = 'DROPDISP result=PASS' },
	@{ name = "client"; path = "$Out\dd_client.log"; pass = $null }))
