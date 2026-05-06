param(
  [Parameter(Mandatory = $false)]
  [string]$ToolRoot = '',

  [Parameter(Mandatory = $false)]
  [string]$Project = '',

  [Parameter(Mandatory = $false)]
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ToolRoot)) {
  $ToolRoot = $env:DAK_BUILD_SETTINGS_TOOL_ROOT
}
if ([string]::IsNullOrWhiteSpace($Project)) {
  $Project = $env:DAK_BUILD_SETTINGS_PROJECT
}
if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = $env:DAK_BUILD_SETTINGS_ROOT
}

function Add-UniqueValue {
  param(
    [Parameter(Mandatory = $true)]
    [System.Collections.Generic.List[string]]$List,

    [Parameter(Mandatory = $true)]
    [System.Collections.Generic.HashSet[string]]$Set,

    [string]$Value
  )

  $trimmed = $Value.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    return
  }

  if ($Set.Add($trimmed)) {
    $List.Add($trimmed)
  }
}

function Get-DakIniPaths {
  $paths = New-Object 'System.Collections.Generic.List[string]'
  $toolIni = [IO.Path]::Combine($ToolRoot, 'bin', 'dak.ini')
  if (Test-Path -LiteralPath $toolIni -PathType Leaf) {
    $paths.Add([IO.Path]::GetFullPath($toolIni))
  }

  $projectPath = [IO.Path]::GetFullPath($Project)
  $projectDir = [IO.Path]::GetDirectoryName($projectPath)
  $rootPath = [IO.Path]::GetFullPath($Root)
  $chain = New-Object 'System.Collections.Generic.List[string]'
  $current = $projectDir

  while ($current) {
    $chain.Add($current)
    if ($current.TrimEnd('\') -ieq $rootPath.TrimEnd('\')) {
      break
    }

    $parent = [IO.Directory]::GetParent($current)
    if ($null -eq $parent) {
      break
    }
    $current = $parent.FullName
  }

  $chain.Reverse()
  foreach ($dir in $chain) {
    $ini = [IO.Path]::Combine($dir, 'dak.ini')
    if (Test-Path -LiteralPath $ini -PathType Leaf) {
      $paths.Add([IO.Path]::GetFullPath($ini))
    }
  }

  return $paths
}

$warningValues = New-Object 'System.Collections.Generic.List[string]'
$hintValues = New-Object 'System.Collections.Generic.List[string]'
$excludeMasks = New-Object 'System.Collections.Generic.List[string]'
$warningSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$hintSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$maskSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$madExceptPath = ''

try {
  foreach ($ini in Get-DakIniPaths) {
    $section = ''
    foreach ($line in Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue) {
      $trimmed = $line.Trim()
      if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith(';')) {
        continue
      }

      if ($trimmed -match '^\[(.+)\]$') {
        $section = $Matches[1]
        continue
      }

      if ($section -eq 'BuildIgnore') {
        $match = [regex]::Match($trimmed, '^(Warnings|Hints|ExcludePathMasks)\s*=\s*(.*)$')
        if (-not $match.Success) {
          continue
        }

        $key = $match.Groups[1].Value
        $value = $match.Groups[2].Value
        foreach ($part in $value.Split(';')) {
          if ($key -eq 'Warnings') {
            Add-UniqueValue -List $warningValues -Set $warningSet -Value $part
          } elseif ($key -eq 'Hints') {
            Add-UniqueValue -List $hintValues -Set $hintSet -Value $part
          } else {
            Add-UniqueValue -List $excludeMasks -Set $maskSet -Value $part
          }
        }
        continue
      }

      if ($section -eq 'ReportFilter') {
        $match = [regex]::Match($trimmed, '^ExcludePathMasks\s*=\s*(.*)$')
        if (-not $match.Success) {
          continue
        }

        foreach ($part in $match.Groups[1].Value.Split(';')) {
          Add-UniqueValue -List $excludeMasks -Set $maskSet -Value $part
        }
        continue
      }

      if ($section -eq 'MadExcept') {
        $match = [regex]::Match($trimmed, '^Path\s*=\s*(.*)$')
        if (-not $match.Success) {
          continue
        }

        $value = [Environment]::ExpandEnvironmentVariables($match.Groups[1].Value.Trim())
        if (-not [string]::IsNullOrWhiteSpace($value)) {
          if (-not [IO.Path]::IsPathRooted($value)) {
            $value = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $ini) $value))
          }
          $madExceptPath = $value
        }
      }
    }
  }
} catch {
}

Write-Output ('INI_BUILD_IGNORE_WARNINGS=' + ($warningValues -join ';'))
Write-Output ('INI_BUILD_IGNORE_HINTS=' + ($hintValues -join ';'))
Write-Output ('INI_BUILD_EXCLUDE_PATH_MASKS=' + ($excludeMasks -join ';'))
Write-Output ('INI_MADEXCEPT_PATH=' + $madExceptPath)
