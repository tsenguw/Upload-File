[CmdletBinding()]
param(
    [switch]$SkipCleanup
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $projectRoot "n8n-runtime"
$nodeModulesPath = Join-Path $runtimeRoot "node_modules"
$archiver = Join-Path $projectRoot "7za.exe"
$archivePath = Join-Path $projectRoot "n8n.7z"
$manifestPath = Join-Path $projectRoot "runtime-manifest.json"
$temporaryArchive = Join-Path $projectRoot ("n8n-{0}.tmp.7z" -f [guid]::NewGuid().ToString("N"))

if (-not (Test-Path -LiteralPath $archiver -PathType Leaf)) {
    throw "7za.exe was not found: $archiver"
}
if (-not (Test-Path -LiteralPath $nodeModulesPath -PathType Container)) {
    throw "n8n runtime node_modules was not found: $nodeModulesPath"
}

if (-not $SkipCleanup) {
    & (Join-Path $projectRoot "cleanup.ps1") -NodeModulesPath $nodeModulesPath
    if (-not $?) {
        throw "Runtime cleanup failed"
    }
}

$requiredFiles = @(
    "node_modules/n8n/bin/n8n",
    "node_modules/sqlite3/build/Release/node_sqlite3.node",
    "node_modules/@n8n/ai-workflow-builder/dist/prompts/chains/parameter-updater/registry.js",
    "node_modules/@n8n/ai-workflow-builder/dist/prompts/chains/parameter-updater/examples/index.js"
)
foreach ($relativePath in $requiredFiles) {
    $sourcePath = Join-Path $runtimeRoot ($relativePath -replace '/', '\\')
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Required runtime file is missing: $relativePath"
    }
}

try {
    Push-Location $runtimeRoot
    & $archiver a -t7z $temporaryArchive ".\node_modules" "-mx=9" "-ms=on" | Write-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create runtime archive (exit code $LASTEXITCODE)"
    }
}
finally {
    Pop-Location
}

Move-Item -LiteralPath $temporaryArchive -Destination $archivePath -Force
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    formatVersion = 1
    runtimeId = "sha256:$archiveHash"
    createdAt = (Get-Date).ToUniversalTime().ToString("o")
    requiredFiles = $requiredFiles
}
$manifestJson = $manifest | ConvertTo-Json
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, $manifestJson, $utf8WithoutBom)

Write-Host "Created $archivePath"
Write-Host "Runtime ID: $($manifest.runtimeId)"
