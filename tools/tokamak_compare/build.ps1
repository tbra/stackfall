param([string]$SourceRoot = "feedback/tokamak_release", [string]$OutputDir = "feedback/tokamak-comparison", [string]$Compiler = "feedback/tokamak-comparison/zig-windows-x86_64-0.13.0/zig.exe")
$ErrorActionPreference = "Stop"
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$source = (Resolve-Path (Join-Path $repo $SourceRoot)).Path
$out = [IO.Path]::GetFullPath((Join-Path $repo $OutputDir))
New-Item -ItemType Directory -Force -Path $out | Out-Null
$previousGlobalCache = $env:ZIG_GLOBAL_CACHE_DIR
$previousLocalCache = $env:ZIG_LOCAL_CACHE_DIR
$files = Get-ChildItem (Join-Path $source 'tokamaksrc/src') -Filter '*.cpp' | Where-Object { $_.Name -notin @('perflinux.cpp','test.cpp') } | Select-Object -ExpandProperty FullName
try {
    $env:ZIG_GLOBAL_CACHE_DIR = Join-Path $out 'zig-cache'
    $env:ZIG_LOCAL_CACHE_DIR = Join-Path $out 'zig-local-cache'
    & (Join-Path $repo $Compiler) c++ -target x86-windows-gnu -std=c++14 -O2 -Wno-everything -I (Join-Path $source 'include') -I (Join-Path $source 'tokamaksrc/src') (Join-Path $PSScriptRoot 'main.cpp') @files -o (Join-Path $out 'tokamak_compare.exe') *> (Join-Path $out 'build.log')
    if ($LASTEXITCODE -ne 0) { Get-Content (Join-Path $out 'build.log') -Tail 35; throw 'Tokamak compile failed; see build.log' }
} finally {
    $env:ZIG_GLOBAL_CACHE_DIR = $previousGlobalCache
    $env:ZIG_LOCAL_CACHE_DIR = $previousLocalCache
}
Write-Output (Join-Path $out 'tokamak_compare.exe')
