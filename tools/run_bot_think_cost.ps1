# Bontago-1t5.62: Hard-bot think cost breakdown. Runs four headless bot matches ALONE one after another
# (Classic and Reach the Sky, 1 and 8 Hard bots; fixed seed) through the exclusive Godot slot and collects
# the BOT_THINK_COST lines into one summary file. Run it on an idle PC (it takes ~4 x Seconds of match time).
#
# -Seconds is the SceneTree timer the flow runs (--bot-think-cost-seconds): engine time, which a real-time headless
# match tracks 1:1 (match time ~ wall time). A failed scenario (Godot exit status or missing report) fails the runner.
#
# Usage: powershell -NoProfile -File tools/run_bot_think_cost.ps1 [-Seconds 180] [-Seed 1014] [-Path <checkout>] [-OutDir <dir>]
param(
	[int]$Seconds = 180,
	[int]$Seed = 1014,
	[string]$Path = (Split-Path -Parent $PSScriptRoot),
	[string]$OutDir = "M:/Bontago-tools/scratch/bot_think_cost"
)
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$summary = Join-Path $OutDir "summary.txt"
$failed = 0
Set-Content -Path $summary -Value ("BOT_THINK_COST run seconds=$Seconds seed=$Seed path=$Path")
$scenarios = @(
	@{ Mode = "classic"; Bots = 1 },
	@{ Mode = "classic"; Bots = 8 },
	@{ Mode = "sky"; Bots = 1 },
	@{ Mode = "sky"; Bots = 8 }
)
foreach ($s in $scenarios) {
	$name = "$($s.Mode)_$($s.Bots)bot"
	$file = Join-Path $OutDir "$name.txt"
	Write-Host "== $name =="
	python "$Path/tools/godot_slots.py" run --exclusive --label "bot_think_cost $name" -- godot --headless --path $Path -- --headless-host "--bots=$($s.Bots)" "--mode=$($s.Mode)" --bot-difficulty=hard "--match-seed=$Seed" --gifts=0 "--bot-think-cost=$file" "--bot-think-cost-seconds=$Seconds" 2>&1 | Tee-Object -FilePath (Join-Path $OutDir "$name.log") | Out-Null
	$code = $LASTEXITCODE
	if ($code -ne 0) { $failed++; Write-Host "scenario $name failed: exit $code"; Add-Content -Path $summary -Value "BOT_THINK_COST scenario=$name FAILED exit=$code" }
	Add-Content -Path $summary -Value "== $name =="
	if (Test-Path $file) { Add-Content -Path $summary -Value (Get-Content $file) } else { $failed++; Add-Content -Path $summary -Value "BOT_THINK_COST scenario=$name MISSING (see $name.log)" }
}
Write-Host "summary: $summary"
if ($failed -gt 0) { Write-Host "BOT_THINK_COST runner FAILED: $failed scenario(s)"; exit 1 }
