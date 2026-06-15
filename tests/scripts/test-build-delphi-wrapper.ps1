Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-support.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$buildBat = Join-Path $repoRoot 'build-delphi.bat'
$fixtureRoot = Join-Path $repoRoot 'tests\fixtures\RemoveWithApplyFixture'
$fixtureProject = Join-Path $fixtureRoot 'RemoveWithApplyFixture.dproj'
$projectName = [IO.Path]::GetFileNameWithoutExtension($fixtureProject)
$tempRoot = New-DakProofTempRoot 'dak-build-wrapper'
$startedUtc = [DateTime]::UtcNow
$runs = @()
$defaultRunDirsToRemove = @()

if (-not (Test-Path -LiteralPath $buildBat -PathType Leaf)) {
  throw "build-delphi.bat not found: $buildBat"
}
if (-not (Test-Path -LiteralPath $fixtureProject -PathType Leaf)) {
  throw "Build fixture project not found: $fixtureProject"
}

function New-WrapperProjectCopy {
  param([Parameter(Mandatory = $true)][string]$Name)

  $targetDir = Join-Path $tempRoot $Name
  if (Test-Path -LiteralPath $targetDir -PathType Container) {
    Remove-Item -LiteralPath $targetDir -Recurse -Force
  }
  Copy-Item -LiteralPath $fixtureRoot -Destination $targetDir -Recurse
  return Join-Path $targetDir 'RemoveWithApplyFixture.dproj'
}

function Get-DefaultLogParent {
  param([Parameter(Mandatory = $true)][string]$ProjectPath)

  $projectDir = Split-Path -Parent $ProjectPath
  return Join-Path $projectDir (Join-Path '.dak' (Join-Path $projectName 'build'))
}

function Start-WrapperBuild {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $false)][string]$LogParent = ''
  )

  $runRoot = Join-Path $tempRoot $Name
  $wrapperLogRoot = Join-Path $runRoot 'wrapper'
  $outRoot = Join-Path $runRoot 'out'
  New-Item -ItemType Directory -Force -Path $wrapperLogRoot, $outRoot | Out-Null

  $run = Start-DakProofJob $Name {
    param($BuildBat, $Project, $OutRoot, $WrapperLogRoot, $LogParent)

    $stdout = Join-Path $WrapperLogRoot 'wrapper.stdout.log'
    $stderr = Join-Path $WrapperLogRoot 'wrapper.stderr.log'
    $args = @($Project, '-config', 'Debug', '-platform', 'Win32', '-target', 'Build',
      '-test-output-dir', $OutRoot, '-keep-logs')
    if (-not [string]::IsNullOrWhiteSpace($LogParent)) {
      $args += @('-log-dir', $LogParent)
    }
    & $BuildBat @args > $stdout 2> $stderr
    [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      LogParent = $LogParent
      OutRoot = $OutRoot
      Stdout = $stdout
      Stderr = $stderr
    }
  } -ArgumentList $buildBat, $ProjectPath, $outRoot, $wrapperLogRoot, $LogParent
  $run | Add-Member -NotePropertyName LogParent -NotePropertyValue $LogParent

  return $run
}

function Complete-WrapperBuild {
  param(
    [Parameter(Mandatory = $true)]$Run,
    [Parameter(Mandatory = $true)][int]$TimeoutSec
  )

  $result = Receive-DakProofJob $Run $TimeoutSec
  if ($result.ExitCode -ne 0) {
    $stdout = if (Test-Path -LiteralPath $result.Stdout) { Get-Content -LiteralPath $result.Stdout -Raw } else { '' }
    $stderr = if (Test-Path -LiteralPath $result.Stderr) { Get-Content -LiteralPath $result.Stderr -Raw } else { '' }
    throw "Wrapper build '$($Run.Name)' failed with exit $($result.ExitCode).`nSTDOUT:`n$stdout`nSTDERR:`n$stderr"
  }
  return $result
}

function Require-LogSet {
  param(
    [Parameter(Mandatory = $true)][string]$LogRoot
  )

  $expectedNames = @('msbuild-full.log', 'msbuild-out.log', 'msbuild-errors.log')
  $resolvedRoot = [IO.Path]::GetFullPath($LogRoot)
  foreach ($name in $expectedNames) {
    $path = Join-Path $LogRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Expected wrapper log not found: $path"
    }
    $resolvedLog = [IO.Path]::GetFullPath($path)
    if (-not $resolvedLog.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Wrapper log escaped run log root. Log=$resolvedLog Root=$resolvedRoot"
    }
  }
}

function Get-RunDirSnapshot {
  param([Parameter(Mandatory = $true)][string]$Parent)

  $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  if (Test-Path -LiteralPath $Parent -PathType Container) {
    foreach ($dir in Get-ChildItem -LiteralPath $Parent -Directory -Filter 'run-*') {
      [void]$set.Add([IO.Path]::GetFullPath($dir.FullName))
    }
  }
  return ,$set
}

function Get-NewRunDirs {
  param(
    [Parameter(Mandatory = $true)][string]$Parent,
    [Parameter(Mandatory = $true)]$Before
  )

  if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
    return @()
  }
  return @(Get-ChildItem -LiteralPath $Parent -Directory -Filter 'run-*' |
    Where-Object { -not $Before.Contains([IO.Path]::GetFullPath($_.FullName)) })
}

function Require-NewRunLogs {
  param(
    [Parameter(Mandatory = $true)][string]$Parent,
    [Parameter(Mandatory = $true)]$Before,
    [Parameter(Mandatory = $true)][int]$ExpectedCount
  )

  $newDirs = @(Get-NewRunDirs $Parent $Before)
  if ($newDirs.Count -ne $ExpectedCount) {
    throw "Expected $ExpectedCount new run log directories under $Parent, found $($newDirs.Count)."
  }
  foreach ($dir in $newDirs) {
    Require-LogSet $dir.FullName
  }
  return $newDirs
}

function Remove-DefaultRunDirs {
  foreach ($dir in @($defaultRunDirsToRemove)) {
    if (($null -ne $dir) -and (Test-Path -LiteralPath $dir.FullName -PathType Container)) {
      Remove-Item -LiteralPath $dir.FullName -Recurse -Force
    }
  }
}

try {
  $defaultProjectA = New-WrapperProjectCopy 'default-project-a'
  $defaultProjectB = New-WrapperProjectCopy 'default-project-b'
  $defaultLogParentA = Get-DefaultLogParent $defaultProjectA
  $defaultLogParentB = Get-DefaultLogParent $defaultProjectB
  $defaultBeforeA = Get-RunDirSnapshot $defaultLogParentA
  $defaultBeforeB = Get-RunDirSnapshot $defaultLogParentB
  $runs = @()
  $runs += Start-WrapperBuild 'default-a' $defaultProjectA
  $runs += Start-WrapperBuild 'default-b' $defaultProjectB

  foreach ($run in $runs) {
    [void](Complete-WrapperBuild $run 90)
  }
  $defaultRunDirsToRemove = @(
    (Require-NewRunLogs $defaultLogParentA $defaultBeforeA 1),
    (Require-NewRunLogs $defaultLogParentB $defaultBeforeB 1)
  )

  $sharedProjectA = New-WrapperProjectCopy 'shared-project-a'
  $sharedProjectB = New-WrapperProjectCopy 'shared-project-b'
  $sharedLogParent = Join-Path $tempRoot 'shared log parent with spaces'
  $sharedBefore = Get-RunDirSnapshot $sharedLogParent
  $runs = @()
  $runs += Start-WrapperBuild 'shared-a' $sharedProjectA $sharedLogParent
  $runs += Start-WrapperBuild 'shared-b' $sharedProjectB $sharedLogParent

  foreach ($run in $runs) {
    [void](Complete-WrapperBuild $run 90)
  }
  [void](Require-NewRunLogs $sharedLogParent $sharedBefore 2)

  $newRootLogs = @(Get-ChildItem -LiteralPath $repoRoot -File -Include 'build_*.log', 'out_*.log', 'errors_*.log' |
    Where-Object { $_.LastWriteTimeUtc -ge $startedUtc })
  if ($newRootLogs.Count -gt 0) {
    throw "Wrapper created shared root logs: $($newRootLogs.FullName -join ', ')"
  }

  $source = Get-Content -LiteralPath $buildBat -Raw
  Assert-NotContains $source 'set "LOGDIR=%~dp0"' 'Wrapper must not default logs to its own directory.'
  Assert-NotContains $source 'build_%TS%.log' 'Wrapper must not use shared build_%TS%.log filenames.'
  Assert-NotContains $source 'errors_%TS%.log' 'Wrapper must not use shared errors_%TS%.log filenames.'
  Assert-Matches $source '-log-dir' 'Wrapper must expose a caller-supplied log directory option.'

  Remove-DakProofTempRoot $tempRoot
  Remove-DefaultRunDirs
  Write-Host 'PASS build-delphi wrapper log isolation'
} catch {
  Write-DakProofFailureEvidence $tempRoot
  Stop-DakProofJobs $runs
  Remove-DefaultRunDirs
  throw
}
