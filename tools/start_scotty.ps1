param(
    [ValidateRange(1024, 65535)][int]$Port = 3000,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$scottyRoot = Join-Path $env:LOCALAPPDATA 'bead-me-up-scotty'
$nextCli = Join-Path $scottyRoot 'node_modules/next/dist/bin/next'
if (-not (Test-Path (Join-Path $scottyRoot '.next/BUILD_ID'))) {
    throw "Scotty is not built at $scottyRoot."
}
$baseUrl = "http://127.0.0.1:$Port"
$projectPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
function Get-ScottyProject {
    try {
        $result = Invoke-RestMethod "$baseUrl/api/projects" -TimeoutSec 2
        return @($result.projects | Where-Object { $_.path -eq $projectPath }) | Select-Object -First 1
    } catch { return $null }
}

$project = Get-ScottyProject
if (-not $project) {
    # A port probe avoids the elevation required by Get-NetTCPConnection on some PCs.
    $portProbe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    try { $portProbe.Start() }
    catch { throw "Port $Port is occupied but did not identify this Scotty project. Choose -Port <number>; no existing process was stopped." }
    finally { $portProbe.Stop() }

    $nodePath = (Get-Command node.exe).Source
    $scottyProcess = Start-Process -FilePath $nodePath -ArgumentList @(
        ('"{0}"' -f $nextCli), 'start', '-H', '127.0.0.1', '-p', $Port
    ) -WorkingDirectory $scottyRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $scottyRoot "server-$Port.log") `
        -RedirectStandardError (Join-Path $scottyRoot "server-$Port-error.log")

    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $scottyProcess.Refresh()
        if ($scottyProcess.HasExited) { throw "Scotty exited. See $scottyRoot\server-$Port-error.log" }
        $project = Get-ScottyProject
        if ($project) { break }
        Start-Sleep -Milliseconds 300
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $project) { throw "Scotty did not become ready within 30 seconds. See $scottyRoot\server-$Port-error.log" }
    Write-Host "Scotty started (PID $($scottyProcess.Id)). Stop with: Stop-Process -Id $($scottyProcess.Id)"
} else {
    Write-Host 'Using the existing Scotty server.'
}

$projectId = [Uri]::EscapeDataString($project.id)
$health = Invoke-RestMethod "$baseUrl/api/p/$projectId/doctor" -TimeoutSec 15
if (-not $health.ok -or $health.kind -ne 'bd') { throw 'Scotty started but could not connect to live Beads.' }
$projectUrl = "$baseUrl/p/$projectId"
Write-Host "Connected to $($health.repoPath): $projectUrl"
if (-not $NoOpen) { Start-Process $projectUrl }
