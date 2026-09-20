Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-support.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$buildBat = Join-Path $repoRoot 'build-delphi.bat'
$tempRoot = New-DakProofTempRoot 'dak-msbuild-exit'

try {
  Copy-Item -LiteralPath (Join-Path $repoRoot 'tests\fixtures\BuildOutputNameFixture') -Destination (Join-Path $tempRoot 'project') -Recurse
  $project = Join-Path $tempRoot 'project\Build.Output.Name.dproj'
  # Force a real MSBuild command-line rejection before its file loggers start.
  # The wrapper accepts platform text, so this reaches MSBuild, not CLI validation.
  $output = & cmd.exe /d /c "`"$buildBat`" `"$project`" -config Debug -platform `"Win64 /dak-invalid-switch`" -target Build -json -keep-logs" 2>&1 | Out-String
  $nativeExit = $LASTEXITCODE
  [IO.File]::WriteAllText((Join-Path $tempRoot 'wrapper-output.json'), $output)
  $start = $output.IndexOf('{')
  if ($start -lt 0) { throw "No JSON from wrapper (exit $nativeExit): $output" }
  $result = $output.Substring($start, $output.LastIndexOf('}') - $start + 1) | ConvertFrom-Json
  $logs = @(Get-ChildItem -LiteralPath $tempRoot -Recurse -Filter 'msbuild-out.log')
  if ($logs.Count -ne 1) { throw "Expected one real MSBuild output log, got $($logs.Count)" }
  Assert-Contains ([IO.File]::ReadAllText($logs[0].FullName)) 'MSB1001' 'The native invalid-switch control did not reach MSBuild.'
  if ($nativeExit -eq 0) { throw "MSBuild rejected the command but wrapper returned success: $output" }
  if ($result.status -ne 'error') { throw "Expected error status, got $($result.status): $output" }
  if ($result.errors -lt 1) { throw "Expected an error count: $output" }
  Remove-DakProofTempRoot $tempRoot
  Write-Output 'PASS native MSBuild failure propagation'
} catch {
  Write-DakProofFailureEvidence $tempRoot
  throw
}
