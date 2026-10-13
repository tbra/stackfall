# Bontago-1pi.11.90: launch the game windowed with the editor's remote debugger
# attached, so Debugger > Profiler / Visual Profiler / Monitors work on a real run.
# DECISION: engine --remote-debug is the simplest path (no addon, no code); the
# editor must already be open on this project with a debug server listening.
# Usage: tools/run_profiled.ps1 [-Port 6007] [-Path <checkout>] [extra game args]
param(
	[int]$Port = 6007,
	[string]$Path = "",
	[Parameter(ValueFromRemainingArguments = $true)][string[]]$GameArgs
)
if (-not $Path) { $Path = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$client = New-Object System.Net.Sockets.TcpClient
try { $client.Connect("127.0.0.1", $Port); $client.Close() }
catch {
	Write-Host "Nothing listening on 127.0.0.1:$Port. Open the editor on $Path and enable Debug > Keep Debug Server Open first."
	exit 1
}
& godot --path $Path --remote-debug "tcp://127.0.0.1:$Port" @GameArgs
