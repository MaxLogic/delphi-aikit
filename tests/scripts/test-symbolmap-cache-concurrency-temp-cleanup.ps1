$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Dak.ChildProcess.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scriptPath = Join-Path $PSScriptRoot 'test-symbolmap-cache-concurrency.ps1'
$tempRoot = [IO.Path]::GetTempPath()
$logPath = Join-Path $tempRoot ('symbol-map-temp-cleanup-proof-' + [guid]::NewGuid().ToString('N') + '.log')
$cleanupPrefix = 'symbol-map-cleanup-proof-' + [guid]::NewGuid().ToString('N')
$keepPrefix = 'symbol-map-keep-proof-' + [guid]::NewGuid().ToString('N')

function Get-OwnedTempRoots([string]$Prefix) {
    Get-ChildItem -LiteralPath $tempRoot -Directory -Filter ($Prefix + '*') -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { $_.FullName }
}

function Remove-OwnedTempRoots([string]$Prefix) {
    foreach ($root in Get-OwnedTempRoots $Prefix) {
        $fullPath = [IO.Path]::GetFullPath($root)
        $tempPath = [IO.Path]::GetFullPath($tempRoot)
        if (-not $tempPath.EndsWith([IO.Path]::DirectorySeparatorChar)) {
            $tempPath += [IO.Path]::DirectorySeparatorChar
        }
        $leafName = Split-Path -Leaf $fullPath
        if (-not $fullPath.StartsWith($tempPath, [StringComparison]::OrdinalIgnoreCase) -or
            -not $leafName.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove non-owned temp root: $root"
        }
        Remove-Item -LiteralPath $fullPath -Recurse -Force
    }
}

$leakedRoots = @()
$keptRoots = @()

try {
    $result = Run-DakChild `
        -FileName 'pwsh' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath,
            '-TempNamePrefix', $cleanupPrefix) `
        -WorkingDirectory $repoRoot `
        -LogPath $logPath `
        -TimeoutMs 420000

    if ($result.ExitCode -ne 0) {
        throw "SymbolMap concurrency proof failed with exit $($result.ExitCode). Log: $logPath"
    }

    $leakedRoots = @(Get-OwnedTempRoots $cleanupPrefix)
    if ($leakedRoots.Count -ne 0) {
        throw "Expected no owned SymbolMap temp roots after successful run. New roots: $($leakedRoots -join ', ')"
    }

    $guardLog = [IO.Path]::ChangeExtension($logPath, '.guard.log')
    $guard = Run-DakChild `
        -FileName 'pwsh' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath,
            '-SelfTestCleanupGuards', '-TempNamePrefix', ($cleanupPrefix + '-guard')) `
        -WorkingDirectory $repoRoot `
        -LogPath $guardLog `
        -TimeoutMs 30000
    if ($guard.ExitCode -ne 0) {
        throw "SymbolMap cleanup guard self-test failed with exit $($guard.ExitCode). Log: $guardLog"
    }

    $keepLog = [IO.Path]::ChangeExtension($logPath, '.keep.log')
    $keep = Run-DakChild `
        -FileName 'pwsh' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath,
            '-KeepTemp', '-TempNamePrefix', $keepPrefix) `
        -WorkingDirectory $repoRoot `
        -LogPath $keepLog `
        -TimeoutMs 420000
    if ($keep.ExitCode -ne 0) {
        throw "SymbolMap KeepTemp proof failed with exit $($keep.ExitCode). Log: $keepLog"
    }
    $keptRoots = @(Get-OwnedTempRoots $keepPrefix)
    if ($keptRoots.Count -eq 0) {
        throw "Expected -KeepTemp to preserve owned SymbolMap temp roots for prefix $keepPrefix"
    }
    Remove-OwnedTempRoots $keepPrefix

    $source = Get-Content -LiteralPath $scriptPath -Raw
    foreach ($required in @('KeepTemp', 'Remove-SymbolMapTempRoot', 'finally', 'StartsWith')) {
        if (-not $source.Contains($required)) {
            throw "Expected cleanup safety source marker missing: $required"
        }
    }

    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $guardLog -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $keepLog -Force -ErrorAction SilentlyContinue
    Write-Host 'PASS: successful SymbolMap concurrency run leaves no new symbol-map-* temp roots.'
}
catch {
    Write-Host "Preserving SymbolMap cleanup proof log: $logPath"
    if ($leakedRoots.Count -gt 0) {
        Write-Host "Preserving leaked owned SymbolMap roots: $($leakedRoots -join ', ')"
    }
    if ($keptRoots.Count -gt 0) {
        Write-Host "Cleaning up owned -KeepTemp proof roots after failure: $($keptRoots -join ', ')"
        Remove-OwnedTempRoots $keepPrefix
    }
    throw
}
