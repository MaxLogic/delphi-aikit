$ErrorActionPreference = 'Stop'

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

function New-DakProofTempRoot {
  param([Parameter(Mandatory = $true)][string]$Prefix)

  $path = Join-Path ([IO.Path]::GetTempPath()) ($Prefix + '-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  return $path
}

function Remove-DakProofTempRoot {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (Test-Path -LiteralPath $Path -PathType Container) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
}

function Write-DakProofFailureEvidence {
  param([Parameter(Mandatory = $true)][string]$Path)

  Write-Host "Preserving failing-run evidence under $Path"
}

function Start-DakProofJob {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
    [Parameter(Mandatory = $false)][object[]]$ArgumentList = @()
  )

  $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
  return [pscustomobject]@{
    Name = $Name
    Job = $job
  }
}

function Receive-DakProofJob {
  param(
    [Parameter(Mandatory = $true)]$Run,
    [Parameter(Mandatory = $true)][int]$TimeoutSec
  )

  $completed = Wait-Job -Job $Run.Job -Timeout $TimeoutSec
  if ($null -eq $completed) {
    Stop-Job -Job $Run.Job
    Receive-Job -Job $Run.Job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $Run.Job -Force
    throw "Timed out waiting for job '$($Run.Name)'."
  }

  $result = Receive-Job -Job $Run.Job
  Remove-Job -Job $Run.Job
  return $result
}

function Stop-DakProofJobs {
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
