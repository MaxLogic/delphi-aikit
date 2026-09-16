Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# T-310: tests/run.bat bootstraps its DelphiAIKit host as Win64 even when DAK_PLATFORM=Win32 asks for Win32
# fixture analysis, and the fixture commands keep the requested Win32 platform. The real run.bat and build
# tooling run in an isolated tree with no prebuilt host; a small real Delphi stand-in plays the host so its
# invocations can be recorded. The repository's own bin executable is never touched.

. (Join-Path $PSScriptRoot 'test-support.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$tempRoot = New-DakProofTempRoot 'dak-run-bat-host'

function Get-PeMachine {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [IO.File]::ReadAllBytes($Path)
  $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
  if ([BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x4550) { throw "Not a PE image: $Path" }
  return [BitConverter]::ToUInt16($bytes, $peOffset + 4)
}

try {
  $tree = Join-Path $tempRoot 'tree'
  New-Item -ItemType Directory -Force -Path (Join-Path $tree 'tests\fixtures'), (Join-Path $tree 'projects'), (Join-Path $tree 'bin') | Out-Null
  Copy-Item -LiteralPath (Join-Path $repoRoot 'tests\run.bat') -Destination (Join-Path $tree 'tests\run.bat')
  Copy-Item -LiteralPath (Join-Path $repoRoot 'build-delphi.bat') -Destination (Join-Path $tree 'build-delphi.bat')
  Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts') -Destination (Join-Path $tree 'scripts') -Recurse
  Copy-Item -LiteralPath (Join-Path $repoRoot 'tests\fixtures\RunBatBootstrapHost\DelphiAIKit.dproj') -Destination (Join-Path $tree 'projects')
  Copy-Item -LiteralPath (Join-Path $repoRoot 'tests\fixtures\RunBatBootstrapHost\DelphiAIKit.dpr') -Destination (Join-Path $tree 'projects')
  Copy-Item -LiteralPath (Join-Path $repoRoot 'tests\fixtures\Sample.dproj') -Destination (Join-Path $tree 'tests\fixtures')
  $hostExe = Join-Path $tree 'bin\DelphiAIKit.exe'
  if (Test-Path -LiteralPath $hostExe) { throw 'The isolated tree must start without a host executable.' }

  $log = Join-Path $tempRoot 'run.log'
  $savedPlatform = $env:DAK_PLATFORM
  try {
    $env:DAK_PLATFORM = 'Win32'
    & cmd.exe /d /c "`"$(Join-Path $tree 'tests\run.bat')`"" > $log 2>&1
  } finally {
    $env:DAK_PLATFORM = $savedPlatform
  }

  if (-not (Test-Path -LiteralPath $hostExe -PathType Leaf)) { throw "run.bat did not bootstrap a host. Log: $log" }
  $machine = Get-PeMachine -Path $hostExe
  if ($machine -ne 0x8664) { throw ("The bootstrapped host is not Win64 (PE machine 0x{0:X4}). Log: {1}" -f $machine, $log) }

  $invocations = Join-Path $tree 'bin\invocations.log'
  if (-not (Test-Path -LiteralPath $invocations)) { throw "The host recorded no invocations. Log: $log" }
  $fixtureCall = @(Get-Content -LiteralPath $invocations | Where-Object { $_ -match '^resolve --project .*Sample\.dproj' }) | Select-Object -First 1
  if (-not $fixtureCall) { throw "No fixture resolve command was recorded. Log: $log" }
  if ($fixtureCall -notmatch '--platform Win32(\s|$)') { throw "The fixture command lost the requested Win32 platform: $fixtureCall" }

  Remove-DakProofTempRoot $tempRoot
  Write-Host 'PASS run.bat bootstraps a Win64 host and keeps Win32 fixture commands'
} catch {
  Write-DakProofFailureEvidence $tempRoot
  throw
}
