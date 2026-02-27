param(
  [Parameter(Mandatory = $true)]
  [string]$Dproj,

  [Parameter(Mandatory = $true)]
  [string]$DfmCheckExe,

  [string]$Config = "Release",
  [string]$Platform = "Win32",
  [string]$RsVarsBat = ""
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
$cliExe = Join-Path $repoRoot "bin\DelphiAIKit.exe"

if (!(Test-Path $cliExe)) {
  throw "DelphiAIKit.exe not found: $cliExe"
}

$args = @(
  "dfm-check",
  "--dproj", $Dproj,
  "--dfmcheck", $DfmCheckExe,
  "--config", $Config,
  "--platform", $Platform
)

if ($RsVarsBat -ne "") {
  $args += @("--rsvars", $RsVarsBat)
}

Write-Host "Running DelphiAIKit dfm-check..."
Write-Host "  Dproj      : $Dproj"
Write-Host "  DFMCheck   : $DfmCheckExe"
Write-Host "  Config     : $Config"
Write-Host "  Platform   : $Platform"
if ($RsVarsBat -ne "") { Write-Host "  RsVars     : $RsVarsBat" }

& $cliExe @args
exit $LASTEXITCODE
