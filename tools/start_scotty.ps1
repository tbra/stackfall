param([int]$Port = 3000)

$ErrorActionPreference = 'Stop'
$scottyRoot = Join-Path $env:LOCALAPPDATA 'bead-me-up-scotty'
$nextCli = Join-Path $scottyRoot 'node_modules/next/dist/bin/next'
if (-not (Test-Path (Join-Path $scottyRoot '.next/BUILD_ID'))) {
    throw "Scotty is not built at $scottyRoot."
}
if ($Port -lt 1024 -or $Port -gt 65535) { throw 'Choose a port between 1024 and 65535.' }
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    throw "Port $Port is already in use. If Scotty is running, open http://127.0.0.1:$Port/p/bontago; otherwise choose -Port <number>."
}

$nodePath = (Get-Command node.exe).Source
$scottyProcess = Start-Process -FilePath $nodePath -ArgumentList @(
    ('"{0}"' -f $nextCli), 'start', '-H', '127.0.0.1', '-p', $Port
) -WorkingDirectory $scottyRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $scottyRoot 'server.log') `
    -RedirectStandardError (Join-Path $scottyRoot 'server-error.log')

Write-Host "Scotty started (PID $($scottyProcess.Id)): http://127.0.0.1:$Port/p/bontago"
Write-Host "Stop it with: Stop-Process -Id $($scottyProcess.Id)"
Write-Host "Logs: $scottyRoot\server.log and server-error.log"
