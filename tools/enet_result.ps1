# Bontago-fca.69: shared final verdict for the tools/run_*_enet.ps1 harnesses (dot-source it).
# Write-EnetResult prints exactly one line, `ENET RESULT PASS` or `ENET RESULT FAIL: <reason>`,
# and returns 0 / 1 for the caller to `exit` with. PASS needs: no hard-deadline kill, every log
# present, every log's pass marker matched, and no log holding a fail marker.
# Each -Logs entry: @{ name='host'; path='...'; pass='regex or $null'; fail='regex (optional)' }.
# A $null pass marker means that peer prints no verdict of its own (only the fail scan applies).
$script:EnetDefaultFail = 'result=(FAIL|DRIFT)|\bFAILURE\b'
function Write-EnetResult {
	param([Parameter(Mandatory)][object[]]$Logs, [bool]$DeadlineHit = $false)
	$reasons = @()
	if ($DeadlineHit) { $reasons += "hard deadline hit (process killed)" }
	foreach ($l in $Logs) {
		$failRe = if ($l.fail) { [string]$l.fail } else { $script:EnetDefaultFail }
		if (-not (Test-Path $l.path)) { $reasons += "$($l.name): log missing"; continue }
		$text = @(Get-Content $l.path -ErrorAction SilentlyContinue)
		if (@($text | Select-String -Pattern $failRe).Count -gt 0) { $reasons += "$($l.name): fail marker" }
		if ($l.pass -and @($text | Select-String -Pattern $l.pass).Count -eq 0) { $reasons += "$($l.name): no pass marker" }
	}
	if ($reasons.Count -eq 0) { Write-Host "ENET RESULT PASS"; return 0 }
	Write-Host ("ENET RESULT FAIL: " + ($reasons -join "; "))
	return 1
}
