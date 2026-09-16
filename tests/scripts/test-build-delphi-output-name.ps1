Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# T-264: build-delphi.bat -json must report the executable the compiler actually emitted and must not
# report a missing output as fresh. Both scenarios run real MSBuild on isolated copies of a fixture.

. (Join-Path $PSScriptRoot 'test-support.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$buildBat = Join-Path $repoRoot 'build-delphi.bat'
$fixtureRoot = Join-Path $repoRoot 'tests\fixtures\BuildOutputNameFixture'
$tempRoot = New-DakProofTempRoot 'dak-build-output-name'

function Invoke-JsonBuild {
  param([Parameter(Mandatory = $true)][string]$Project)
  $output = & cmd.exe /d /c "`"$buildBat`" `"$Project`" -config Debug -platform Win64 -target Build -json" 2>&1 | Out-String
  $exit = $LASTEXITCODE
  $start = $output.IndexOf('{')
  if ($start -lt 0) { throw "build-delphi.bat printed no JSON (exit $exit): $output" }
  return [pscustomobject]@{ ExitCode = $exit; Json = ($output.Substring($start, $output.LastIndexOf('}') - $start + 1) | ConvertFrom-Json); Raw = $output }
}

try {
  # 1. The DPR file name differs from the program identifier and SanitizedProjectName.
  $named = Join-Path $tempRoot 'file-name'
  Copy-Item -LiteralPath $fixtureRoot -Destination $named -Recurse
  $started = [DateTime]::UtcNow.AddSeconds(-2)
  $result = Invoke-JsonBuild -Project (Join-Path $named 'Build.Output.Name.dproj')
  $emitted = Join-Path $named 'bin\Build.Output.Name.exe'
  if ($result.ExitCode -ne 0) { throw "Build failed: $($result.Raw)" }
  if (-not (Test-Path -LiteralPath $emitted -PathType Leaf)) { throw "The compiler did not emit $emitted" }
  if ((Get-Item -LiteralPath $emitted).LastWriteTimeUtc -lt $started) { throw 'The emitted executable is not fresh.' }
  if ($result.Json.output -ne $emitted) { throw "Reported output $($result.Json.output), compiler emitted $emitted" }
  if ($result.Json.output_stale) { throw "A fresh output was reported stale: $($result.Raw)" }

  # 2. MSBuild succeeds but nothing is compiled, so the predicted output never exists.
  $missing = Join-Path $tempRoot 'missing-output'
  Copy-Item -LiteralPath $fixtureRoot -Destination $missing -Recurse
  $project = Join-Path $missing 'Build.Output.Name.dproj'
  $text = [IO.File]::ReadAllText($project)
  $marker = '<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets"'
  $cut = $text.IndexOf($marker)
  if ($cut -lt 0) { throw 'Fixture import not found.' }
  [IO.File]::WriteAllText($project, $text.Substring(0, $cut) + '<Target Name="Build" />' + "`r`n</Project>`r`n")
  $result = Invoke-JsonBuild -Project $project
  if ($result.ExitCode -ne 0) { throw "The empty build target should succeed: $($result.Raw)" }
  if (Test-Path -LiteralPath $result.Json.output) { throw "The scenario unexpectedly produced $($result.Json.output)" }
  if (-not $result.Json.output_stale) { throw "A missing output was reported fresh: $($result.Raw)" }
  if ($result.Json.status -ne 'output_missing') { throw "Expected status output_missing: $($result.Raw)" }
  if (-not ([string]$result.Json.output_message).Contains([string]$result.Json.output)) { throw "The message does not name the missing output: $($result.Raw)" }

  Remove-DakProofTempRoot $tempRoot
  Write-Host 'PASS build-delphi output name and freshness'
} catch {
  Write-DakProofFailureEvidence $tempRoot
  throw
}
