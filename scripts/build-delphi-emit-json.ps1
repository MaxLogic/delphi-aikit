param(
  [Parameter(Mandatory = $true)]
  [string]$Project,
  [Parameter(Mandatory = $true)]
  [string]$Config,
  [Parameter(Mandatory = $true)]
  [string]$Platform,
  [Parameter(Mandatory = $true)]
  [string]$Target,
  [Parameter(Mandatory = $true)]
  [int]$ExitCode,
  [Parameter(Mandatory = $true)]
  [int]$ErrorCount,
  [Parameter(Mandatory = $true)]
  [int]$WarningCount,
  [Parameter(Mandatory = $true)]
  [int]$HintCount,
  [Parameter(Mandatory = $true)]
  [int]$MaxFindings,
  [Parameter(Mandatory = $true)]
  [string]$BuildStart,
  [Parameter(Mandatory = $false)]
  [string]$OutputPath = '',
  [Parameter(Mandatory = $false)]
  [string]$OutputStale = '0',
  [Parameter(Mandatory = $false)]
  [string]$OutputMessage = '',
  [Parameter(Mandatory = $false)]
  [string]$OutLog = '',
  [Parameter(Mandatory = $false)]
  [string]$ErrLog = '',
  [Parameter(Mandatory = $false)]
  [string]$IncludeWarnings = '0',
  [Parameter(Mandatory = $false)]
  [string]$IncludeHints = '0',
  [Parameter(Mandatory = $false)]
  [string]$TimedOut = '0',
  [Parameter(Mandatory = $false)]
  [string]$Status = ''
)

$ErrorActionPreference = 'Stop'

function As-Bool([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }
  return ($Value -eq '1') -or $Value.Equals('true', [StringComparison]::OrdinalIgnoreCase)
}

function Read-Findings([string]$PathText, [string[]]$Patterns, [int]$Limit) {
  $results = New-Object 'System.Collections.Generic.List[string]'
  if ([string]::IsNullOrWhiteSpace($PathText)) {
    return @()
  }
  if (-not (Test-Path -LiteralPath $PathText -PathType Leaf)) {
    return @()
  }
  foreach ($line in Get-Content -LiteralPath $PathText -ErrorAction SilentlyContinue) {
    foreach ($pattern in $Patterns) {
      if ($line -match $pattern) {
        $results.Add($line.Trim())
        break
      }
    }
    if ($results.Count -ge $Limit) {
      break
    }
  }
  return $results.ToArray()
}

if ($MaxFindings -lt 1) {
  $MaxFindings = 5
}

$includeWarningsBool = As-Bool $IncludeWarnings
$includeHintsBool = As-Bool $IncludeHints
$timedOutBool = As-Bool $TimedOut
$staleBool = As-Bool $OutputStale

try {
  $start = [DateTimeOffset]::Parse($BuildStart)
  $timeMs = [int64]([DateTimeOffset]::Now - $start).TotalMilliseconds
  if ($timeMs -lt 0) {
    $timeMs = 0
  }
} catch {
  $timeMs = 0
}

$errorLines = Read-Findings $ErrLog @(':\s+error\s+', ':\s+fatal\s+') $MaxFindings
if ($errorLines.Count -eq 0) {
  $errorLines = Read-Findings $OutLog @(':\s+error\s+', ':\s+fatal\s+') $MaxFindings
}

$warningLines = @()
if ($includeWarningsBool) {
  $warningLines = Read-Findings $OutLog @(':\s+warning\s+W\d+:') $MaxFindings
}

$hintLines = @()
if ($includeHintsBool) {
  $hintLines = Read-Findings $OutLog @(':\s+hint\s+H\d+:', ' hint warning\s+H\d+:') $MaxFindings
}

$statusValue = $Status
if ([string]::IsNullOrWhiteSpace($statusValue)) {
  if ($timedOutBool) {
    $statusValue = 'timeout'
  } elseif (($ExitCode -ne 0) -or ($ErrorCount -gt 0)) {
    $statusValue = 'error'
  } elseif ($staleBool) {
    $statusValue = 'output_locked'
  } elseif ($WarningCount -gt 0) {
    $statusValue = 'warnings'
  } elseif ($HintCount -gt 0) {
    $statusValue = 'hints'
  } else {
    $statusValue = 'ok'
  }
}

$obj = [ordered]@{
  status = $statusValue
  project = [IO.Path]::GetFileName($Project)
  project_path = $Project
  config = $Config
  platform = $Platform
  target = $Target
  time_ms = $timeMs
  exit_code = $ExitCode
  errors = $ErrorCount
  warnings = $WarningCount
  hints = $HintCount
  max_findings = $MaxFindings
  output = $OutputPath
  output_stale = $staleBool
  output_message = $OutputMessage
  issues = [ordered]@{
    errors = @($errorLines)
    warnings = @($warningLines)
    hints = @($hintLines)
  }
}

$obj | ConvertTo-Json -Depth 6 -Compress
