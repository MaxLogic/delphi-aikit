Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$buildBat = Join-Path $repoRoot 'build-delphi.bat'
$project = Join-Path $repoRoot 'tests\fixtures\RemoveWithApplyFixture\RemoveWithApplyFixture.dproj'
$projectName = [IO.Path]::GetFileNameWithoutExtension($project)
$projectDir = Split-Path -Parent $project
$defaultLogParent = Join-Path $projectDir (Join-Path '.dak' (Join-Path $projectName 'build'))
$fixtureRes = Join-Path (Split-Path -Parent $project) 'RemoveWithApplyFixture.res'
$fixtureResExisted = Test-Path -LiteralPath $fixtureRes -PathType Leaf
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('dak-build-wrapper-' + [guid]::NewGuid().ToString('N'))
$startedUtc = [DateTime]::UtcNow
$runs = @()
$defaultRunDirsToRemove = @()

if (-not (Test-Path -LiteralPath $buildBat -PathType Leaf)) {
  throw "build-delphi.bat not found: $buildBat"
}
if (-not (Test-Path -LiteralPath $project -PathType Leaf)) {
  throw "Build fixture project not found: $project"
}

function Assert-NotContains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Needle,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if ($Text.Contains($Needle)) {
    throw $Message
  }
}

function Assert-Matches {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if ($Text -notmatch $Pattern) {
    throw $Message
  }
}

function Start-WrapperBuild {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $false)][string]$LogParent = ''
  )

  $runRoot = Join-Path $tempRoot $Name
  $wrapperLogRoot = Join-Path $runRoot 'wrapper'
  $outRoot = Join-Path $runRoot 'out'
  New-Item -ItemType Directory -Force -Path $wrapperLogRoot, $outRoot | Out-Null

  $job = Start-Job -ScriptBlock {
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
  } -ArgumentList $buildBat, $project, $outRoot, $wrapperLogRoot, $LogParent

  return [pscustomobject]@{
    Name = $Name
    Job = $job
    LogParent = $LogParent
  }
}

function Receive-WrapperBuild {
  param(
    [Parameter(Mandatory = $true)]$Run,
    [Parameter(Mandatory = $true)][int]$TimeoutSec
  )

  $completed = Wait-Job -Job $Run.Job -Timeout $TimeoutSec
  if ($null -eq $completed) {
    Stop-Job -Job $Run.Job
    Receive-Job -Job $Run.Job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $Run.Job -Force
    throw "Timed out waiting for wrapper build '$($Run.Name)'."
  }

  $result = Receive-Job -Job $Run.Job
  Remove-Job -Job $Run.Job
  if ($result.ExitCode -ne 0) {
    $stdout = if (Test-Path -LiteralPath $result.Stdout) { Get-Content -LiteralPath $result.Stdout -Raw } else { '' }
    $stderr = if (Test-Path -LiteralPath $result.Stderr) { Get-Content -LiteralPath $result.Stderr -Raw } else { '' }
    throw "Wrapper build '$($Run.Name)' failed with exit $($result.ExitCode).`nSTDOUT:`n$stdout`nSTDERR:`n$stderr"
  }
  return $result
}

function Stop-RemainingWrapperBuilds {
  param([object[]]$Runs)

  foreach ($run in @($Runs)) {
    if ($null -eq $run) {
      continue
    }
    $job = $run.Job
    if ($null -eq $job) {
      continue
    }
    if ($job.State -eq 'Running') {
      Stop-Job -Job $job
    }
    Receive-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
  }
}

function Assert-LogSet {
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

function Assert-NewRunLogs {
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
    Assert-LogSet $dir.FullName
  }
  return $newDirs
}

function Remove-GeneratedFixtureResource {
  if ((-not $fixtureResExisted) -and (Test-Path -LiteralPath $fixtureRes -PathType Leaf)) {
    Remove-Item -LiteralPath $fixtureRes -Force
  }
}

function Remove-DefaultRunDirs {
  foreach ($dir in @($defaultRunDirsToRemove)) {
    if (($null -ne $dir) -and (Test-Path -LiteralPath $dir.FullName -PathType Container)) {
      Remove-Item -LiteralPath $dir.FullName -Recurse -Force
    }
  }
}

try {
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

  $defaultBefore = Get-RunDirSnapshot $defaultLogParent
  $runs = @(
    (Start-WrapperBuild 'default-a'),
    (Start-WrapperBuild 'default-b')
  )

  foreach ($run in $runs) {
    [void](Receive-WrapperBuild $run 90)
  }
  $defaultRunDirsToRemove = @(Assert-NewRunLogs $defaultLogParent $defaultBefore 2)

  $sharedLogParent = Join-Path $tempRoot 'shared log parent with spaces'
  $sharedBefore = Get-RunDirSnapshot $sharedLogParent
  $runs = @(
    (Start-WrapperBuild 'shared-a' $sharedLogParent),
    (Start-WrapperBuild 'shared-b' $sharedLogParent)
  )

  foreach ($run in $runs) {
    [void](Receive-WrapperBuild $run 90)
  }
  [void](Assert-NewRunLogs $sharedLogParent $sharedBefore 2)

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

  Remove-Item -LiteralPath $tempRoot -Recurse -Force
  Remove-DefaultRunDirs
  Remove-GeneratedFixtureResource
  Write-Host 'PASS build-delphi wrapper log isolation'
} catch {
  Write-Host "Preserving failing-run evidence under $tempRoot"
  Stop-RemainingWrapperBuilds $runs
  Remove-DefaultRunDirs
  Remove-GeneratedFixtureResource
  throw
}
