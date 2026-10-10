# CPU/Godot watchdog (promoted from scratch/cpumon, Bontago-fca.89) for the orchestrator (owner 2026-10-10: PC crashed under ~11 Godot processes).
# Samples every 10 s, appends to cpumon.log, and EXITS with an ALERT line when a limit is crossed
# (the orchestrator is re-invoked on exit). Exits quietly after MaxMinutes so it can be re-armed.
param(
    [int]$MaxGodot = 3,          # real Godot game processes (console wrappers excluded)
    [int]$CpuHighPct = 90,       # sustained CPU load threshold
    [int]$CpuHighSamples = 6,    # consecutive samples (6 x 10 s = 1 min)
    [double]$MinFreeGB = 3.0,
    [int]$MaxMinutes = 120,
    [string]$Log = "M:/Bontago-tools/scratch/cpumon/cpumon.log"
)
$deadline = (Get-Date).AddMinutes($MaxMinutes)
$high = 0
while ((Get-Date) -lt $deadline) {
    $load = (Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
    $freeGB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
    $godot = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match '^godot' -and $_.ProcessName -notmatch 'godot-ai' -and $_.ProcessName -notmatch 'console' })
    $n = $godot.Count
    $slotDir = if ($env:STACKFALL_GODOT_SLOTS_DIR) { $env:STACKFALL_GODOT_SLOTS_DIR } else { "M:/Bontago-tools/locks/godot_slots" }
    $slots = @(Get-ChildItem -Path $slotDir -Filter "slot_*.json" -ErrorAction SilentlyContinue).Count
    $line = '{0:HH:mm:ss} cpu={1}% free={2:N1}GB godot={3} slots={4}' -f (Get-Date), $load, $freeGB, $n, $slots
    Add-Content -Path $Log -Value $line
    if ($load -ge $CpuHighPct) { $high++ } else { $high = 0 }
    if ($n -gt $MaxGodot) { Write-Output "ALERT godot=$n > $MaxGodot | $line"; exit 2 }
    if ($high -ge $CpuHighSamples) { Write-Output "ALERT cpu>=$CpuHighPct% for $high samples | $line"; exit 3 }
    if ($freeGB -lt $MinFreeGB) { Write-Output "ALERT free RAM < $MinFreeGB GB | $line"; exit 4 }
    Start-Sleep -Seconds 10
}
Write-Output "cpumon: $MaxMinutes min elapsed without alert | last: $line"
exit 0
