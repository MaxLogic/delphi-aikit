param(
    [switch]$KeepTemp,
    [switch]$SelfTestCleanupGuards,
    [string]$TempNamePrefix = ''
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$resolver = Join-Path $repoRoot 'bin\DelphiAIKit.exe'
if (-not (Test-Path $resolver)) {
    throw "Resolver executable not found: $resolver"
}

. (Join-Path $PSScriptRoot 'Dak.ChildProcess.ps1')

$createdTempDirs = [System.Collections.Generic.List[string]]::new()

function Test-SymbolMapTempRoot([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $tempPath = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $tempPath.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $tempPath += [IO.Path]::DirectorySeparatorChar
    }
    $leafName = Split-Path -Leaf $fullPath
    return $fullPath.StartsWith($tempPath, [StringComparison]::OrdinalIgnoreCase) -and
        $leafName.StartsWith('symbol-map-', [StringComparison]::OrdinalIgnoreCase)
}

function Remove-SymbolMapTempRoot([string]$Path) {
    if (-not (Test-SymbolMapTempRoot $Path)) {
        throw "Refusing to remove path outside symbol-map temp roots: $Path"
    }
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Remove-CreatedTempRoots {
    for ($i = $createdTempDirs.Count - 1; $i -ge 0; $i--) {
        Remove-SymbolMapTempRoot $createdTempDirs[$i]
    }
}

function New-TempDir([string]$Name) {
    $leafBase = $Name
    if (-not [string]::IsNullOrWhiteSpace($TempNamePrefix)) {
        if ($Name.StartsWith('symbol-map-', [StringComparison]::OrdinalIgnoreCase)) {
            $leafBase = $TempNamePrefix + '-' + $Name.Substring('symbol-map-'.Length)
        } else {
            $leafBase = $TempNamePrefix + '-' + $Name
        }
    }
    $path = Join-Path ([IO.Path]::GetTempPath()) ($leafBase + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $resolvedPath = (Resolve-Path $path).Path
    if (-not (Test-SymbolMapTempRoot $resolvedPath)) {
        throw "Created temp root failed symbol-map containment check: $resolvedPath"
    }
    [void]$createdTempDirs.Add($resolvedPath)
    return $resolvedPath
}

function Invoke-CleanupGuardSelfTest {
    $unsafeRoot = Join-Path ([IO.Path]::GetTempPath()) ('dak-unsafe-cleanup-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $unsafeRoot -Force | Out-Null
    try {
        $blocked = $false
        try {
            Remove-SymbolMapTempRoot $unsafeRoot
        }
        catch {
            $blocked = $true
        }
        if (-not $blocked) {
            throw "Expected cleanup guard to reject unsafe temp root: $unsafeRoot"
        }
        if (-not (Test-Path -LiteralPath $unsafeRoot)) {
            throw "Cleanup guard deleted unsafe temp root: $unsafeRoot"
        }
    }
    finally {
        Remove-Item -LiteralPath $unsafeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $safeRoot = New-TempDir 'symbol-map-cleanup-selftest'
    Remove-CreatedTempRoots
    if (Test-Path -LiteralPath $safeRoot) {
        throw "Expected cleanup guard to remove safe symbol-map temp root: $safeRoot"
    }
    Write-Host 'PASS: SymbolMap temp cleanup guard rejects unsafe paths and removes owned roots.'
}

if ($SelfTestCleanupGuards) {
    Invoke-CleanupGuardSelfTest
    return
}

function Copy-FixtureProject([string]$TargetDir) {
    $fixture = Join-Path $repoRoot 'tests\fixtures\LspProjectFixture'
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Copy-Item (Join-Path $fixture 'LspProjectFixture.dproj') (Join-Path $TargetDir 'LspProjectFixture.dproj') -Force
    Copy-Item (Join-Path $fixture 'LspProjectFixture.dpr') (Join-Path $TargetDir 'LspProjectFixture.dpr') -Force
    Copy-Item (Join-Path $fixture 'Unit1.pas') (Join-Path $TargetDir 'Unit1.pas') -Force
    return (Resolve-Path (Join-Path $TargetDir 'LspProjectFixture.dproj')).Path
}

function Get-CacheMutexName([string]$CacheRoot) {
    $dbPath = [IO.Path]::GetFullPath((Join-Path $CacheRoot 'symbol-map.sqlite3')).ToLowerInvariant()
    $bytes = [Text.Encoding]::UTF8.GetBytes($dbPath)
    $hashBytes = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    $hash = ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    return "Local\DelphiAIKit.SymbolMap.Cache.$hash"
}

function Start-DakProcess([string]$Arguments, [string]$LogPath) {
    return Start-DakChild -FileName $resolver -Arguments $Arguments -WorkingDirectory $repoRoot -LogPath $LogPath
}

function Complete-DakProcess($Run, [int]$TimeoutMs) {
    $result = Complete-DakChild -Run $Run -TimeoutMs $TimeoutMs
    if ($result.ExitCode -ne 0) {
        throw "Process failed with exit $($result.ExitCode). Log: $($Run.LogPath)"
    }
    return $result.Stdout
}

function Invoke-JsonIndex([string]$ProjectPath, [string]$UnitPath, [string]$CacheRoot, [string]$LogPath) {
    $args = 'symbol-map index --project "{0}" --unit "{1}" --cache-root "{2}" --format json' -f `
        $ProjectPath, $UnitPath, $CacheRoot
    $run = Start-DakProcess $args $LogPath
    $jsonText = Complete-DakProcess $run 30000
    return $jsonText | ConvertFrom-Json
}

function Invoke-FullJsonIndex([string]$ProjectPath, [string]$CacheRoot, [string]$LogPath) {
    $args = 'symbol-map index --project "{0}" --cache-root "{1}" --format json' -f $ProjectPath, $CacheRoot
    $run = Start-DakProcess $args $LogPath
    $jsonText = Complete-DakProcess $run 60000
    return $jsonText | ConvertFrom-Json
}

$scriptSucceeded = $false
try {
$sameRoot = New-TempDir 'symbol-map-lock-same'
$otherRoot = New-TempDir 'symbol-map-lock-other'
$sameProject = Copy-FixtureProject (New-TempDir 'symbol-map-lock-same-project')
$otherProject = Copy-FixtureProject (New-TempDir 'symbol-map-lock-other-project')
$mutexName = Get-CacheMutexName $sameRoot
$created = $false
$mutex = [Threading.Mutex]::new($false, $mutexName, [ref]$created)

try {
    if (-not $mutex.WaitOne(0)) {
        throw "Could not acquire test mutex: $mutexName"
    }

    $sameLog = Join-Path $sameRoot 'same-root.log'
    $sameRun = Start-DakProcess ('symbol-map stats --project "{0}" --cache-root "{1}" --format json' -f $sameProject, $sameRoot) $sameLog
    Start-Sleep -Milliseconds 1200
    if ($sameRun.Process.HasExited) {
        $sameOut = (Complete-DakChild -Run $sameRun -TimeoutMs 1000).Text
        throw "Same-root stats was not serialized by the held cache mutex. Output: $sameOut"
    }

    $otherLog = Join-Path $otherRoot 'other-root.log'
    $otherRun = Start-DakProcess ('symbol-map stats --project "{0}" --cache-root "{1}" --format json' -f $otherProject, $otherRoot) $otherLog
    [void](Complete-DakProcess $otherRun 10000)
}
finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}

[void](Complete-DakProcess $sameRun 10000)

$projectRaceRoot = New-TempDir 'symbol-map-project-race'
$projectRaceProject = Copy-FixtureProject (New-TempDir 'symbol-map-project-race-project')
$projectRaceUnit = Join-Path (Split-Path -Parent $projectRaceProject) 'Unit1.pas'
$projectRuns = @()
for ($i = 0; $i -lt 4; $i++) {
    $projectRuns += Start-DakProcess ('symbol-map index --project "{0}" --unit "{1}" --cache-root "{2}" --format json' -f `
        $projectRaceProject, $projectRaceUnit, $projectRaceRoot) (Join-Path $projectRaceRoot "project-race-$i.log")
}
foreach ($run in $projectRuns) {
    [void](Complete-DakProcess $run 30000)
}

$rtlRaceRoot = New-TempDir 'symbol-map-rtl-race'
$rtlRaceProject = Copy-FixtureProject (New-TempDir 'symbol-map-rtl-race-project')
$rtlRuns = @(
    (Start-DakProcess ('symbol-map index --project "{0}" --cache-root "{1}" --format json' -f `
        $rtlRaceProject, $rtlRaceRoot) (Join-Path $rtlRaceRoot 'rtl-race-a.log')),
    (Start-DakProcess ('symbol-map index --project "{0}" --cache-root "{1}" --format json' -f `
        $rtlRaceProject, $rtlRaceRoot) (Join-Path $rtlRaceRoot 'rtl-race-b.log'))
)
foreach ($run in $rtlRuns) {
    # A cold full RTL profile index can exceed two minutes on slower machines.
    [void](Complete-DakProcess $run 300000)
}
$rtlCheck = Invoke-FullJsonIndex $rtlRaceProject $rtlRaceRoot (Join-Path $rtlRaceRoot 'rtl-race-check.log')
if (-not $rtlCheck.rtlSource.cacheHit) {
    throw 'Expected RTL profile cache hit after concurrent same-profile rebuilds.'
}
if ($rtlCheck.rtlSource.unitCacheHits -ne $rtlCheck.rtlSource.unitsDiscovered) {
    throw "Expected all RTL profile units to hit after concurrent rebuilds. Hits: $($rtlCheck.rtlSource.unitCacheHits), discovered: $($rtlCheck.rtlSource.unitsDiscovered)"
}

$includeRoot = New-TempDir 'symbol-map-include-script'
$includeProject = Copy-FixtureProject (New-TempDir 'symbol-map-include-project')
$includeDir = Split-Path -Parent $includeProject
$unitPath = Join-Path $includeDir 'SymbolMapIncludeScriptUnit.pas'
$includePath = Join-Path $includeDir 'SymbolMapIncludeScript.inc'
Set-Content -LiteralPath $unitPath -Value @(
    'unit SymbolMapIncludeScriptUnit;',
    'interface',
    '{$I SymbolMapIncludeScript.inc}',
    'implementation',
    'end.'
) -Encoding UTF8
Set-Content -LiteralPath $includePath -Value 'type TScriptIncludeOne = class end;' -Encoding UTF8

$first = Invoke-JsonIndex $includeProject $unitPath $includeRoot (Join-Path $includeRoot 'first-index.log')
Set-Content -LiteralPath $includePath -Value 'type TScriptIncludeTwo = class end;' -Encoding UTF8
$second = Invoke-JsonIndex $includeProject $unitPath $includeRoot (Join-Path $includeRoot 'second-index.log')

if ($first.result.centralCacheMisses -ne 1) {
    throw "Expected first include index to miss. Actual misses: $($first.result.centralCacheMisses)"
}
if ($second.result.centralCacheMisses -ne 1) {
    throw "Expected include-only edit to force a cache miss. Actual misses: $($second.result.centralCacheMisses)"
}
if ($first.result.indexedUnits[0].unitCacheKey -eq $second.result.indexedUnits[0].unitCacheKey) {
    throw 'Expected include-only edit to change the SymbolMap unit cache key.'
}

$scriptSucceeded = $true
Write-Host 'PASS: different cache roots run concurrently, same-root/project writes serialize, RTL publish stays deduplicated, include edits reindex.'
}
finally {
    if ($scriptSucceeded -and -not $KeepTemp) {
        Remove-CreatedTempRoots
    } else {
        Write-Host "Preserving SymbolMap temp roots: $($createdTempDirs -join ', ')"
    }
}
