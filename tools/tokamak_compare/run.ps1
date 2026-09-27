param([int]$Repeats = 3, [double]$Height = 2, [double]$Interval = 2, [double]$Gap = 0.3, [string]$OutputDir = 'feedback/tokamak-comparison')
$ErrorActionPreference = 'Stop'
if ($Repeats -lt 1 -or $Repeats -gt 20) { throw 'Repeats must be 1..20' }
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$out = [IO.Path]::GetFullPath((Join-Path $repo $OutputDir))
$exe = Join-Path $out 'tokamak_compare.exe'
if (!(Test-Path $exe)) { throw 'Run build.ps1 first' }
$records = @()
foreach ($mode in @('drop','stack')) {
    foreach ($repeat in 1..$Repeats) {
        $trace = Join-Path $out "$mode-$repeat.csv"
        $raw = & $exe $mode $Height.ToString([Globalization.CultureInfo]::InvariantCulture) $Interval.ToString([Globalization.CultureInfo]::InvariantCulture) $Gap.ToString([Globalization.CultureInfo]::InvariantCulture) $trace
        if ($LASTEXITCODE -ne 0) { throw "Tokamak $mode failed: $LASTEXITCODE" }
        $record = $raw | ConvertFrom-Json
        $record | Add-Member repeat $repeat
        $record | Add-Member trace_path $trace
        $records += $record
    }
}
$records | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out 'results.json') -Encoding UTF8
$records | Select-Object mode,repeat,first_contact_s,rebound_height_cubes,first_asleep_s,max_lateral_drift_cubes | Format-Table -AutoSize
