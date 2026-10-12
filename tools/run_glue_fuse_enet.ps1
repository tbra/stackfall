# Glue fusion WP5: host + client + late joiner on loopback under a hard wall-clock deadline (pattern of
# run_glue_fall_enet.ps1). The late client starts once the host reports the group at rest.
param([string]$Path = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path, [int]$Port = (Get-Random -Minimum 20000 -Maximum 60000), [int]$Lag = 0, [string]$Out = $env:TEMP, [int]$TimeoutSeconds = 540)
$scene = "res://tests/bench/glue_fuse_enet.tscn"
. (Join-Path $PSScriptRoot "enet_result.ps1")
$procs = @()
$deadlineHit = $false
function Stop-Tree([object]$p) {
	if ($p -and -not $p.HasExited) {
		Write-Host "killing process tree $($p.Id)"
		try { $p.Kill($true) } catch { Write-Warning "kill $($p.Id): $_" }
	}
}
function Start-Godot([string]$name, [string[]]$extra) {
	$log = "${Out}\godot_$([guid]::NewGuid().ToString('N').Substring(0,6)).log"
	$args = @("--headless","--log-file",$log,"--path",$Path,$scene,"--") + $extra
	$p = Start-Process godot -ArgumentList $args -PassThru -NoNewWindow -RedirectStandardOutput "$Out\gfu_$name.log" -RedirectStandardError "$Out\gfu_$name.err"
	$null = $p.Handle
	return $p
}
Remove-Item "$Out\gfu_*.log" -ErrorAction SilentlyContinue
try {
	$h = Start-Godot "host" @("--headless-host","--port=$Port","--expect-peers=2"); $procs += $h
	Start-Sleep 3
	$c = Start-Godot "client" @("--join=127.0.0.1:$Port","--sim-lag=$Lag"); $procs += $c
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	$late = $null
	while (((Get-Date) -lt $deadline) -and (-not ($h.HasExited -and $c.HasExited -and ($late -eq $null -or $late.HasExited)))) {
		Start-Sleep 1
		if ($late -eq $null -and (Select-String -Path "$Out\gfu_host.log" -Pattern "at_rest_waiting_for_late_peer" -Quiet -ErrorAction SilentlyContinue)) {
			$late = Start-Godot "late" @("--join=127.0.0.1:$Port","--sim-lag=$Lag","--late"); $procs += $late
		}
	}
	if (-not ($h.HasExited -and $c.HasExited -and $late -ne $null -and $late.HasExited)) { $deadlineHit = $true; Write-Warning "hard deadline ($TimeoutSeconds s) exceeded" }
} finally {
	foreach ($p in $procs) { Stop-Tree $p }
}
foreach ($role in @("host", "client", "late")) { Get-Content "$Out\gfu_$role.log" -ErrorAction SilentlyContinue | Select-String "GFUSE|ERROR" }
exit (Write-EnetResult -DeadlineHit $deadlineHit -Logs @(
	@{ name = "host"; path = "$Out\gfu_host.log"; pass = 'GFUSE host strays=0' },
	@{ name = "client"; path = "$Out\gfu_client.log"; pass = 'GFUSE result=PASS' },
	@{ name = "late"; path = "$Out\gfu_late.log"; pass = 'GFUSE result=PASS' }))
