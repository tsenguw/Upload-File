[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [string]$NodeModulesPath = (Join-Path $PSScriptRoot "n8n-runtime\node_modules")
)

$ErrorActionPreference = 'Stop'
$nodeModulesPath = [System.IO.Path]::GetFullPath($NodeModulesPath)

if (-not (Test-Path -LiteralPath $nodeModulesPath -PathType Container)) {
    throw "node_modules directory does not exist: $nodeModulesPath"
}

$removedFiles = 0
$removedBytes = [int64]0
$removedDirectories = 0
$minifiedPackageCount = 0
$minifiedPackageBytes = [int64]0
$runtimeRoot = Split-Path -Parent $nodeModulesPath
$runtimeNode = Join-Path $runtimeRoot 'node.exe'
$packageJsonMinifier = Join-Path $PSScriptRoot 'scripts\minify-package-json.js'

function Remove-SafeRuntimeFile {
    param([System.IO.FileInfo]$File)

    if ($WhatIfPreference) {
        Write-Output "WhatIf: remove non-runtime build artifact $($File.FullName)"
        return
    }

    $script:removedFiles++
    $script:removedBytes += $File.Length
    Remove-Item -LiteralPath $File.FullName -Force
}

function Remove-SafeRuntimeDirectory {
    param([System.IO.DirectoryInfo]$Directory)

    if ($WhatIfPreference) {
        Write-Output "WhatIf: remove development-only directory $($Directory.FullName)"
        return
    }

    $size = (Get-ChildItem -LiteralPath $Directory.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $size) { $size = 0 }
    $script:removedDirectories++
    $script:removedBytes += [int64]$size
    Remove-Item -LiteralPath $Directory.FullName -Recurse -Force
}

Write-Output "Cleaning runtime: $nodeModulesPath"
Write-Output 'Keeping all .js, .cjs, .mjs, .ts, tests, examples, docs, and package directories.'

# Phase 1 - Delete TypeScript declarations and JavaScript source maps.
# Node.js does not execute these files; stack traces may lose source-map mapping only.
$safeFilePatterns = @('*.d.ts', '*.js.map', '*.cjs.map', '*.mjs.map')
foreach ($pattern in $safeFilePatterns) {
    Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-SafeRuntimeFile $_ }
}

# Phase 2 - Delete repository metadata.
# .github contains CI and issue-template files, never n8n runtime code.
Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -Directory -Filter '.github' -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-SafeRuntimeDirectory $_ }

$safeMetadataPatterns = @('.npmignore', '.gitignore', '.gitattributes', '.editorconfig', '.eslint*', '.prettier*', 'Makefile', 'Makefile.*', '*.gyp', '*.gypi')
foreach ($pattern in $safeMetadataPatterns) {
    Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-SafeRuntimeFile $_ }
}

# Phase 3 - Delete explicit non-Windows native prebuild folders.
# Windows binaries and all generic/native runtime files remain untouched.
Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -Directory -Filter 'prebuilds' -ErrorAction SilentlyContinue |
    ForEach-Object {
        Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^(linux|darwin|freebsd|android)(-|$)' } |
            ForEach-Object { Remove-SafeRuntimeDirectory $_ }
    }

# Phase 4 - Delete top-level packages that explicitly declare a non-Windows OS.
# The package.json `os` field is checked, so names alone never decide deletion.
$topLevelItems = Get-ChildItem -LiteralPath $nodeModulesPath -Directory -Force -ErrorAction SilentlyContinue
$topLevelPackages = foreach ($item in $topLevelItems) {
    if ($item.Name.StartsWith('@')) {
        Get-ChildItem -LiteralPath $item.FullName -Directory -Force -ErrorAction SilentlyContinue
    } else {
        $item
    }
}

$nonWindowsPackageCount = 0
foreach ($packageDirectory in $topLevelPackages) {
    $manifestPath = Join-Path $packageDirectory.FullName 'package.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $supportedOs = @($manifest.os | ForEach-Object { [string]$_ })
        if ($supportedOs.Count -eq 0 -or $supportedOs -contains 'win32') { continue }
        if ($supportedOs | Where-Object { $_ -in @('linux', 'darwin', 'freebsd', 'android', 'sunos', 'aix') }) {
            $nonWindowsPackageCount++
            Remove-SafeRuntimeDirectory $packageDirectory
        }
    } catch {
        Write-Warning "Skipping unreadable package manifest: $manifestPath"
    }
}
Write-Output "Removed $nonWindowsPackageCount top-level non-Windows packages."

# Phase 5 - Delete CI, Docker, documentation-tool metadata, and nested lock files.
# Generic names such as HISTORY, SECURITY, tests, examples, and docs are deliberately excluded.
$developmentFilePatterns = @(
    '.travis.yml', 'appveyor.yml',
    'azure-pipelines.yml', 'bitbucket-pipelines.yml', 'Dockerfile', 'Dockerfile.*',
    'docker-compose.yml', 'docker-compose.yaml', 'Vagrantfile', 'typedoc.json',
    'typedoc.*', 'renovate.json', 'renovate.json5', 'package-lock.json',
    'npm-shrinkwrap.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lock', 'bun.lockb'
)
foreach ($pattern in $developmentFilePatterns) {
    Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-SafeRuntimeFile $_ }
}

# Phase 6 - Delete explicitly named development/coverage directories.
$developmentDirectoryNames = @('.circleci', '.husky', '.changeset', '.devcontainer', '.vscode', '.idea', '.nyc_output', 'coverage')
foreach ($directoryName in $developmentDirectoryNames) {
    Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -Directory -Filter $directoryName -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object { Remove-SafeRuntimeDirectory $_ }
}

# Phase 7 - Delete empty directories left behind by earlier phases.
do {
    $removedEmptyDirectory = $false
    Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if ((Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
                Remove-SafeRuntimeDirectory $_
                $removedEmptyDirectory = $true
            }
        }
} while ($removedEmptyDirectory -and -not $WhatIfPreference)

# Phase 8 - Minify package.json files without changing JSON fields or values.
# The bundled Node.js runtime parses and serializes JSON; invalid manifests are left unchanged.
if ($WhatIfPreference) {
    Write-Output "WhatIf: minify package.json files below $nodeModulesPath"
} elseif ((Test-Path -LiteralPath $runtimeNode -PathType Leaf) -and (Test-Path -LiteralPath $packageJsonMinifier -PathType Leaf)) {
    $minifierResult = & $runtimeNode $packageJsonMinifier $nodeModulesPath
    if ($LASTEXITCODE -ne 0) {
        throw "package.json minification failed with exit code $LASTEXITCODE"
    }
    $minifierSummary = $minifierResult | ConvertFrom-Json
    $minifiedPackageCount = $minifierSummary.filesProcessed
    $minifiedPackageBytes = [int64]$minifierSummary.bytesSaved
} else {
    Write-Warning "Skipping package.json minification because node.exe or the minifier script is missing."
}

$requiredFiles = @(
    'n8n\bin\n8n',
    'sqlite3\build\Release\node_sqlite3.node',
    '@n8n\ai-workflow-builder\dist\prompts\chains\parameter-updater\examples\index.js',
    '@n8n\ai-workflow-builder\node_modules\langchain\dist\agents\tests\utils.cjs'
)
$missingFiles = @($requiredFiles | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $nodeModulesPath $_) -PathType Leaf)
})
if ($missingFiles.Count -gt 0) {
    throw "Cleanup validation failed. Required runtime files are missing: $($missingFiles -join ', ')"
}

$remainingBytes = (Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -File -ErrorAction Stop |
    Measure-Object -Property Length -Sum).Sum

Write-Output "Cleanup complete. Removed $removedFiles files and $removedDirectories directories ($([math]::Round($removedBytes / 1MB, 1)) MB)."
Write-Output "Minified $minifiedPackageCount package.json files ($([math]::Round($minifiedPackageBytes / 1MB, 2)) MB saved)."
Write-Output "Remaining runtime size: $([math]::Round($remainingBytes / 1GB, 2)) GB"
