param(
  [Parameter(Mandatory = $true)]
  [string]$BdsRoot
)

$ErrorActionPreference = 'Stop'

$props = ''

try {
  $root = [IO.Path]::GetFullPath($BdsRoot).TrimEnd('\')
  $version = [IO.Path]::GetFileName($root)
  if ($version -notmatch '^\d+\.\d+$') {
    Write-Output 'MSBUILD_ENV_PROPS='
    exit 0
  }

  $appData = [Environment]::GetFolderPath('ApplicationData')
  if ([string]::IsNullOrWhiteSpace($appData)) {
    Write-Output 'MSBUILD_ENV_PROPS='
    exit 0
  }

  $envProjPath = Join-Path $appData ('Embarcadero\BDS\' + $version + '\environment.proj')
  if (-not (Test-Path -LiteralPath $envProjPath -PathType Leaf)) {
    Write-Output 'MSBUILD_ENV_PROPS='
    exit 0
  }

  [xml]$xml = Get-Content -LiteralPath $envProjPath -ErrorAction Stop
  $items = New-Object 'System.Collections.Generic.List[string]'
  $groups = $xml.SelectNodes("/*[local-name()='Project']/*[local-name()='PropertyGroup']")

  foreach ($group in $groups) {
    foreach ($child in $group.ChildNodes) {
      if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) {
        continue
      }

      $key = $child.LocalName
      if ([string]::IsNullOrWhiteSpace($key)) {
        continue
      }
      if (-not ($key -match '^[A-Za-z_][A-Za-z0-9_]*$')) {
        continue
      }
      if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($key))) {
        continue
      }

      $val = $child.InnerText.Trim()
      if ([string]::IsNullOrWhiteSpace($val)) {
        continue
      }

      $val = $val.Replace('"', '""')
      if ($val.IndexOf(' ') -ge 0) {
        $items.Add('/p:' + $key + '="' + $val + '"')
      } else {
        $items.Add('/p:' + $key + '=' + $val)
      }
    }
  }

  $props = ($items -join ' ').Trim()
} catch {
}

Write-Output ('MSBUILD_ENV_PROPS=' + $props)
