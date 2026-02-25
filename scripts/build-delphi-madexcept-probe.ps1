param(
  [Parameter(Mandatory = $true)]
  [string]$Project,
  [Parameter(Mandatory = $true)]
  [string]$Config,
  [Parameter(Mandatory = $true)]
  [string]$Platform
)

$ErrorActionPreference = 'Stop'

$required = '0'
$reason = ''
$dpr = ''
$mes = ''
$exe = ''
$defs = ''

try {
  $proj = [IO.Path]::GetFullPath($Project)
  $mes = [IO.Path]::ChangeExtension($proj, '.mes')

  [xml]$xml = Get-Content -LiteralPath $proj -ErrorAction Stop
  $props = @{}
  $props['Config'] = $Config
  $props['Platform'] = $Platform

  function Expand-Val([string]$Value) {
    if ($null -eq $Value) {
      return ''
    }
    return [regex]::Replace(
      $Value,
      '\$\(([^)]+)\)',
      {
        param($Match)
        $name = $Match.Groups[1].Value
        if ($script:props.ContainsKey($name)) {
          return $script:props[$name]
        }
        return ''
      }
    )
  }

  function Test-Cond([string]$ConditionText) {
    if ([string]::IsNullOrWhiteSpace($ConditionText)) {
      return $true
    }
    $expr = Expand-Val $ConditionText
    $expr = $expr -replace '==', ' -eq '
    $expr = $expr -replace '!=', ' -ne '
    $expr = $expr -replace '(?i)\band\b', '-and'
    $expr = $expr -replace '(?i)\bor\b', '-or'
    try {
      return [bool](Invoke-Expression $expr)
    } catch {
      return $false
    }
  }

  $groups = $xml.SelectNodes("/*[local-name()='Project']/*[local-name()='PropertyGroup']")
  foreach ($group in $groups) {
    if (-not (Test-Cond $group.Condition)) {
      continue
    }
    foreach ($child in $group.ChildNodes) {
      if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) {
        continue
      }
      if (-not (Test-Cond $child.Condition)) {
        continue
      }
      $props[$child.LocalName] = Expand-Val ($child.InnerText.Trim())
    }
  }

  $dprojBase = [IO.Path]::GetFileNameWithoutExtension($proj)
  $projDir = [IO.Path]::GetDirectoryName($proj)

  $mainSource = $props['MainSource']
  if ([string]::IsNullOrWhiteSpace($mainSource)) {
    $mainSource = $dprojBase + '.dpr'
  }
  if (-not [IO.Path]::IsPathRooted($mainSource)) {
    $mainSource = [IO.Path]::GetFullPath((Join-Path $projDir $mainSource))
  }
  $dpr = $mainSource
  $dprBase = [IO.Path]::GetFileNameWithoutExtension($dpr)

  $hasMes = Test-Path -LiteralPath $mes -PathType Leaf
  $hasDpr = Test-Path -LiteralPath $dpr -PathType Leaf

  $defines = ''
  if ($props.ContainsKey('DCC_Define')) {
    $defines = $props['DCC_Define']
  }
  $defs = $defines
  $hasMad = $false
  foreach ($item in $defines.Split(';')) {
    if ($item.Trim().Equals('madExcept', [StringComparison]::OrdinalIgnoreCase)) {
      $hasMad = $true
      break
    }
  }

  $sameBase = $dprojBase.Equals($dprBase, [StringComparison]::OrdinalIgnoreCase)

  $exeOut = ''
  if ($props.ContainsKey('DCC_ExeOutput')) {
    $exeOut = $props['DCC_ExeOutput']
  }
  if ([string]::IsNullOrWhiteSpace($exeOut)) {
    $exeDir = $projDir
  } elseif ([IO.Path]::IsPathRooted($exeOut)) {
    $exeDir = [IO.Path]::GetFullPath($exeOut)
  } else {
    $exeDir = [IO.Path]::GetFullPath((Join-Path $projDir $exeOut))
  }

  $exeBase = $dprojBase
  if ($props.ContainsKey('SanitizedProjectName') -and -not [string]::IsNullOrWhiteSpace($props['SanitizedProjectName'])) {
    $exeBase = $props['SanitizedProjectName']
  } elseif ($props.ContainsKey('ProjectName') -and -not [string]::IsNullOrWhiteSpace($props['ProjectName'])) {
    $exeBase = $props['ProjectName']
  }
  $exe = [IO.Path]::Combine($exeDir, $exeBase + '.exe')

  if (-not $hasDpr) {
    $reason = 'main-source-missing'
  } elseif (-not $hasMes) {
    $reason = 'mes-missing'
  } elseif (-not $sameBase) {
    $reason = 'name-mismatch'
  } elseif (-not $hasMad) {
    $reason = 'define-missing'
  } else {
    $required = '1'
    $reason = 'enabled'
  }
} catch {
  $reason = 'dproj-parse-failed'
}

Write-Output ('MADEXCEPT_PATCH_REQUIRED=' + $required)
Write-Output ('MADEXCEPT_PATCH_REASON=' + $reason)
Write-Output ('MADEXCEPT_DPR=' + $dpr)
Write-Output ('MADEXCEPT_MES=' + $mes)
Write-Output ('MADEXCEPT_TARGET_EXE=' + $exe)
Write-Output ('MADEXCEPT_DCC_DEFINE=' + $defs)
