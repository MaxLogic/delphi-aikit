param(
  [Parameter(Mandatory = $false)]
  [string]$SettingPath
)

$ErrorActionPreference = 'Stop'

$settingFound = $false
$found = ''
$setting = ''
if (-not [string]::IsNullOrWhiteSpace($SettingPath)) {
  $setting = [Environment]::ExpandEnvironmentVariables($SettingPath.Trim())
}

$cands = New-Object 'System.Collections.Generic.List[string]'

function Add-Candidate([string]$PathText) {
  if ([string]::IsNullOrWhiteSpace($PathText)) {
    return
  }
  if (-not $script:cands.Contains($PathText)) {
    $script:cands.Add($PathText)
  }
}

if ($setting -ne '') {
  if ([IO.Path]::GetExtension($setting).Equals('.exe', [StringComparison]::OrdinalIgnoreCase)) {
    Add-Candidate $setting
  } else {
    Add-Candidate (Join-Path $setting 'madExceptPatch.exe')
  }
}

if ($setting -ne '') {
  foreach ($cand in $cands) {
    if (Test-Path -LiteralPath $cand -PathType Leaf) {
      $settingFound = $true
      break
    }
  }
}

$cmd = Get-Command madExceptPatch.exe -ErrorAction SilentlyContinue
if ($cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Path)) {
  Add-Candidate $cmd.Path
}

if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
  Add-Candidate (Join-Path $env:ProgramFiles 'madCollection\madExcept\Tools\madExceptPatch.exe')
  Add-Candidate (Join-Path $env:ProgramFiles 'madCollection\madExcept\tools\madExceptPatch.exe')
}
if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
  Add-Candidate (Join-Path ${env:ProgramFiles(x86)} 'madCollection\madExcept\Tools\madExceptPatch.exe')
  Add-Candidate (Join-Path ${env:ProgramFiles(x86)} 'madCollection\madExcept\tools\madExceptPatch.exe')
}
if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
  Add-Candidate (Join-Path $env:ProgramData 'madCollection\madExcept\Tools\madExceptPatch.exe')
  Add-Candidate (Join-Path $env:ProgramData 'madCollection\madExcept\tools\madExceptPatch.exe')
}

foreach ($cand in $cands) {
  if (Test-Path -LiteralPath $cand -PathType Leaf) {
    $found = [IO.Path]::GetFullPath($cand)
    break
  }
}

Write-Output ('MADEXCEPT_PATCH_EXE=' + $found)
if (($setting -ne '') -and (-not $settingFound)) {
  Write-Output 'MADEXCEPT_PATCH_SETTING_INVALID=1'
} else {
  Write-Output 'MADEXCEPT_PATCH_SETTING_INVALID='
}
