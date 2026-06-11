Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixtureRoot = Join-Path $repoRoot 'tests\fixtures\RemoveWithApplyFixture'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
  ('remove-with-build-verification-concurrency-' + [guid]::NewGuid().ToString('N'))
$exePath = Join-Path $repoRoot 'bin\DelphiAIKit.exe'

if (-not (Test-Path -LiteralPath $exePath)) {
  throw "DelphiAIKit.exe not found: $exePath"
}

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Needle,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if (-not $Text.Contains($Needle)) {
    throw $Message
  }
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

function Get-BuildVerificationMutexName {
  param([Parameter(Mandatory = $true)][string]$ProjectPath)

  $canonical = [System.IO.Path]::GetFullPath($ProjectPath).ToLowerInvariant()
  $safe = [System.Text.StringBuilder]::new()
  [uint64]$hash = 0
  foreach ($ch in $canonical.ToCharArray()) {
    $hash = (($hash * 131) + [int][char]$ch) % 0x100000000
    if ((($ch -ge 'a') -and ($ch -le 'z')) -or (($ch -ge '0') -and ($ch -le '9'))) {
      [void]$safe.Append($ch)
    } else {
      [void]$safe.Append('_')
    }
  }
  $prefix = $safe.ToString()
  if ($prefix.Length -gt 80) {
    $prefix = $prefix.Substring(0, 80)
  }
  return 'Local\DakRemoveWithBuildVerification-' + $prefix + '-' + $hash.ToString('X8')
}

function Copy-Fixture {
  param(
    [Parameter(Mandatory = $true)][string]$TargetDir
  )

  if (Test-Path -LiteralPath $TargetDir) {
    Remove-Item -LiteralPath $TargetDir -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TargetDir) | Out-Null
  Copy-Item -LiteralPath $fixtureRoot -Destination $TargetDir -Recurse
}

function Start-RemoveWithApply {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutPath,
    [Parameter(Mandatory = $true)][string]$ErrPath
  )

  Start-Job -ScriptBlock {
    param($ExePath, $ProjectPath, $OutPath, $ErrPath)
    & $ExePath remove-with --project $ProjectPath --all --mode apply --format json > $OutPath 2> $ErrPath
    [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      OutPath = $OutPath
      ErrPath = $ErrPath
    }
  } -ArgumentList $exePath, $ProjectPath, $OutPath, $ErrPath
}

function Receive-CompletedJob {
  param(
    [Parameter(Mandatory = $true)]$Job,
    [Parameter(Mandatory = $true)][int]$TimeoutSec
  )

  $completed = Wait-Job -Job $Job -Timeout $TimeoutSec
  if ($null -eq $completed) {
    Stop-Job -Job $Job
    Receive-Job -Job $Job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $Job -Force
    throw "Timed out waiting for job $($Job.Id)."
  }
  $result = Receive-Job -Job $Job
  Remove-Job -Job $Job
  return $result
}

function Assert-ApplyResult {
  param(
    [Parameter(Mandatory = $true)]$JobResult,
    [Parameter(Mandatory = $true)][string]$ProjectDir
  )

  if ($JobResult.ExitCode -ne 0) {
    $stderr = ''
    if (Test-Path -LiteralPath $JobResult.ErrPath) {
      $stderr = Get-Content -LiteralPath $JobResult.ErrPath -Raw
    }
    throw "remove-with apply failed with exit $($JobResult.ExitCode). $stderr"
  }

  $output = Get-Content -LiteralPath $JobResult.OutPath -Raw
  $json = $output | ConvertFrom-Json
  if ($json.status -ne 'applied') {
    throw "Expected applied status for $ProjectDir, got '$($json.status)'."
  }
  if ($json.verification.status -ne 'passed') {
    throw "Expected passed verification for $ProjectDir, got '$($json.verification.status)'."
  }

  foreach ($logPath in @($json.verification.stdoutLog, $json.verification.stderrLog)) {
    if ([string]::IsNullOrWhiteSpace($logPath)) {
      throw "Missing verification log path for $ProjectDir."
    }
    if (-not (Test-Path -LiteralPath $logPath)) {
      throw "Verification log does not exist: $logPath"
    }
    $resolvedLog = [System.IO.Path]::GetFullPath($logPath)
    $resolvedProjectDir = [System.IO.Path]::GetFullPath($ProjectDir)
    if (-not $resolvedLog.StartsWith($resolvedProjectDir, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Verification log escaped project workspace. Log=$resolvedLog Project=$resolvedProjectDir"
    }
  }
}

$transactionSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Dak.RemoveWith.Transaction.pas') -Raw
$buildRunnerSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\Dak.Build.Runner.pas') -Raw
Assert-Contains $transactionSource 'BuildVerificationMutexName(' `
  'Build verification must derive lock names from project identity.'
Assert-Contains $transactionSource 'CanonicalProjectIdentity(' `
  'Build verification must canonicalize the project identity before locking.'
Assert-NotContains $transactionSource 'Local\DakRemoveWithBuildVerification''' `
  'Build verification must not use the fixed global mutex name.'
Assert-NotContains $transactionSource 'WaitForSingleObject(lMutex, Winapi.Windows.INFINITE)' `
  'Build verification must not wait indefinitely on one global mutex.'
Assert-NotContains $transactionSource 'SetEnvironmentVariable(' `
  'Remove-with transaction must not mutate process environment state.'
Assert-Contains $buildRunnerSource 'fBuildDiagnosticsDir' `
  'Build runner must accept diagnostics through typed options.'

try {
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

  $projectADir = Join-Path $tempRoot 'copy-a'
  $projectBDir = Join-Path $tempRoot 'copy-b'
  Copy-Fixture $projectADir
  Copy-Fixture $projectBDir

  $projectA = Join-Path $projectADir 'RemoveWithApplyFixture.dproj'
  $projectB = Join-Path $projectBDir 'RemoveWithApplyFixture.dproj'
  $mutexA = Get-BuildVerificationMutexName $projectA
  $mutexB = Get-BuildVerificationMutexName $projectB

  if ($mutexA -eq $mutexB) {
    throw 'Disjoint project fixture copies must map to distinct build-verification mutexes.'
  }

  $heldMutex = [System.Threading.Mutex]::new($false, $mutexA)
  if (-not $heldMutex.WaitOne(0)) {
    throw "Could not acquire same-project mutex for concurrency proof: $mutexA"
  }

  $sameJob = $null
  $disjointJob = $null
  try {
    $sameJob = Start-RemoveWithApply $projectA (Join-Path $tempRoot 'same-project.json') `
      (Join-Path $tempRoot 'same-project.err.log')
    $disjointJob = Start-RemoveWithApply $projectB (Join-Path $tempRoot 'disjoint-project.json') `
      (Join-Path $tempRoot 'disjoint-project.err.log')

    Start-Sleep -Seconds 3
    if ($sameJob.State -ne 'Running') {
      throw "Expected same-project verification to wait on the held mutex, but job state is $($sameJob.State)."
    }

    $disjointResult = Receive-CompletedJob $disjointJob 45
    $disjointJob = $null
    Assert-ApplyResult $disjointResult $projectBDir
  } finally {
    $heldMutex.ReleaseMutex()
    $heldMutex.Dispose()
  }

  if ($null -ne $sameJob) {
    $sameResult = Receive-CompletedJob $sameJob 45
    Assert-ApplyResult $sameResult $projectADir
  }

  Remove-Item -LiteralPath $tempRoot -Recurse -Force
  Write-Host 'PASS remove-with build verification isolation contract'
} catch {
  Write-Host "Preserving failing-run evidence under $tempRoot"
  throw
}
