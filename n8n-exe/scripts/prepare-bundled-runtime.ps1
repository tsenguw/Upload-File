[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $projectRoot "n8n-runtime"
$nodeExecutable = Join-Path $runtimeRoot "node.exe"
$archiver = Join-Path $projectRoot "7za.exe"
$nodeArchive = Join-Path $projectRoot "runtime.7z"

if (-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)) {
    throw "Runtime source directory is missing: $runtimeRoot"
}

if (-not (Test-Path -LiteralPath $nodeExecutable -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $archiver -PathType Leaf) -or -not (Test-Path -LiteralPath $nodeArchive -PathType Leaf)) {
        throw "Bundled Node.js source or extraction tools are missing."
    }

    Write-Host "Preparing bundled Node.js runtime..."
    & $archiver x -y $nodeArchive ("-o" + $runtimeRoot) | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Could not extract bundled Node.js (exit code $LASTEXITCODE)."
    }
}

Write-Host "Bundled runtime source is ready: $runtimeRoot"
