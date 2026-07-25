[CmdletBinding()]
param(
    [Parameter()]
    [string]$NodeModulesPath = (Join-Path $PSScriptRoot "n8n-runtime\node_modules"),

    [switch]$Aggressive
)

$nodeModulesPath = $NodeModulesPath

if (-not (Test-Path $nodeModulesPath)) {
    Write-Error "node_modules 資料夾不存在於 $nodeModulesPath"
    exit 1
}

if (-not $Aggressive) {
    Write-Output "Skipping generic runtime cleanup. Package directory names and source extensions are not reliable indicators of unused n8n runtime code."
    return
}

Write-Output "=== 開始清理 node_modules ==="
Write-Output "路徑: $nodeModulesPath"

# ──── Phase 1: Remove common file types ────
Write-Output "`n[Phase 1] 移除 .ts/.js.map/.d.ts/.md/.markdown 檔案..."
$fileCount = 0
$fileSize = 0

$extensions = @('*.ts', '*.js.map', '*.d.ts', '*.md', '*.markdown')
foreach ($ext in $extensions) {
    Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -File -Filter $ext -ErrorAction SilentlyContinue | ForEach-Object {
        $fileCount++
        $fileSize += $_.Length
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }
}
Write-Output "  已移除 $fileCount 個檔案，約 $([math]::Round($fileSize / 1MB, 1)) MB"

# ──── Phase 2: Remove test/example/docs directories ────
Write-Output "`n[Phase 2] 移除 test/example/docs/.github 目錄..."
$dirCount = 0
$dirSize = 0

$dirNames = @('test', 'tests', '__tests__', 'demo', 'demos', 'docs', 'doc', '.github')
foreach ($dirName in $dirNames) {
    Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -Directory -Filter $dirName -ErrorAction SilentlyContinue | ForEach-Object {
        $size = (Get-ChildItem -Recurse -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $dirSize += $size
        $dirCount++
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Output "  已移除 $dirCount 個目錄，約 $([math]::Round($dirSize / 1MB, 1)) MB"

# ──── Phase 3: Remove non-Windows native binaries ────
Write-Output "`n[Phase 3] 移除非 Windows 原生二進位檔 (.node)..."
$nativeCount = 0
$nativeSize = 0

Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -File -Filter '*.node' -ErrorAction SilentlyContinue | Where-Object {
    $name = $_.Name.ToLower()
    # Keep only win32/msvc .node files
    ($name -match 'linux' -or $name -match 'darwin' -or $name -match 'freebsd' -or $name -match 'android') -and
    -not ($name -match 'win32' -or $name -match 'msvc')
} | ForEach-Object {
    $nativeCount++
    $nativeSize += $_.Length
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
}
Write-Output "  已移除 $nativeCount 個檔案，約 $([math]::Round($nativeSize / 1MB, 1)) MB"

# ──── Phase 4: Remove platform-specific node_modules with non-Windows binaries ────
Write-Output "`n[Phase 4] 移除非 Windows 平台特定目錄..."
$platformSize = 0
$platformCount = 0

# Handle @parcel/watcher, @msgpackr-extract, etc. prebuilds directories
$platformDirs = @(
    '*-linux-x64', '*-linux-arm64', '*-linux-arm',
    '*-darwin-x64', '*-darwin-arm64',
    '*-freebsd-x64', '*-android-*'
)
# Also remove prebuilds directories containing non-win32 files
$prebuildPaths = Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -Directory -Filter 'prebuilds' -ErrorAction SilentlyContinue
foreach ($prebuildDir in $prebuildPaths) {
    Get-ChildItem -LiteralPath $prebuildDir.FullName -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match 'linux|darwin|freebsd|android' -and $_.Name -notmatch 'win32|msvc'
    } | ForEach-Object {
        $s = (Get-ChildItem -Recurse -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $platformSize += $s
        $platformCount++
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}
# Also handle build/Release folders that might have non-win32 .node files
$buildReleaseDirs = Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -Directory -Filter 'Release' -ErrorAction SilentlyContinue
foreach ($dir in $buildReleaseDirs) {
    if ($dir.FullName -match '\\build\\Release$') {
        Get-ChildItem -LiteralPath $dir.FullName -File -Filter '*.node' -ErrorAction SilentlyContinue | Where-Object {
            $name = $_.Name.ToLower()
            ($name -match 'linux|darwin') -and -not ($name -match 'win32')
        } | ForEach-Object {
            $platformSize += $_.Length
            $platformCount++
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}
Write-Output "  已清理 $platformCount 個項目，約 $([math]::Round($platformSize / 1MB, 1)) MB"

# ──── Phase 5: Remove Makefile, .gyp, .gypi, .npmignore, etc. ────
Write-Output "`n[Phase 5] 移除建置輔助檔案 (Makefile, .gyp, .gitignore, etc)..."
$extraCount = 0
$extraSize = 0

$extraPatterns = @('Makefile', 'Makefile.*', '*.gyp', '*.gypi', '.npmignore', '.gitignore', '.eslint*', '.prettier*', '.editorconfig', '*.o', '*.obj', '*.a', '*.lo', '*.la')
foreach ($pattern in $extraPatterns) {
    Get-ChildItem -LiteralPath $nodeModulesPath -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
        $extraCount++
        $extraSize += $_.Length
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }
}
Write-Output "  已移除 $extraCount 個檔案，約 $([math]::Round($extraSize / 1MB, 1)) MB"

# ──── Summary ────
$totalCleaned = $fileSize + $dirSize + $nativeSize + $platformSize + $extraSize
$remainingSize = (Get-ChildItem -Recurse -LiteralPath $nodeModulesPath -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum

Write-Output "`n=== 清理完成 ==="
Write-Output "  總共釋放: $([math]::Round($totalCleaned / 1MB, 1)) MB"
Write-Output "  剩餘大小: $([math]::Round($remainingSize / 1MB, 1)) MB"
Write-Output "  壓縮率: $([math]::Round(($remainingSize * 100 / ($remainingSize + $totalCleaned)), 1))%"
