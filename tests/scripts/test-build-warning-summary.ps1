Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-support.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$proofRoot = Join-Path $repoRoot ('tests\.dak\DelphiAIKit.Tests\warning-summary-' + [guid]::NewGuid().ToString('N'))
$projectRoot = Join-Path $proofRoot 'fixture'
$unitRoot = Join-Path $projectRoot 'units'
New-Item -ItemType Directory -Path $unitRoot -Force | Out-Null
$projectPath = Join-Path $projectRoot 'RemoveWithApplyFixture.dproj'
$template = Join-Path $repoRoot 'tests\fixtures\RemoveWithApplyFixture\RemoveWithApplyFixture.dproj'
$projectText = [IO.File]::ReadAllText($template).Replace('ApplyUnit.pas', 'units\Test.Support.pas')
[IO.File]::WriteAllText($projectPath, $projectText, [Text.Encoding]::ASCII)

# Deliberately compile one W1035 and one H2077, using real relative source paths.
$programText = @'
program RemoveWithApplyFixture;

{$APPTYPE CONSOLE}

uses Test.Support in 'units\Test.Support.pas';

begin
  WriteLn(ParseJsonObject(True));
  ProduceHint;
end.
'@
$unitText = @'
unit Test.Support;

interface

function ParseJsonObject(aValid: Boolean): Integer;
procedure ProduceHint;

implementation

{$WARNINGS ON}
{$HINTS ON}

function ParseJsonObject(aValid: Boolean): Integer;
begin
  if aValid then
    Result := 1;
end;

procedure ProduceHint;
var
  lUnused: Integer;
begin
  lUnused := 1;
end;

end.
'@
foreach ($source in @(
  @{ Name = 'RemoveWithApplyFixture.dpr'; Text = $programText },
  @{ Name = 'units\Test.Support.pas'; Text = $unitText }
)) {
  [IO.File]::WriteAllText((Join-Path $projectRoot $source.Name),
    ($source.Text -replace '\r?\n', "`r`n") + "`r`n", [Text.Encoding]::ASCII)
}

$cases = @(
  @{ Name = 'win64'; Platform = 'Win64'; Options = @(); Warnings = 1; Hints = 1 },
  @{ Name = 'win32'; Platform = 'Win32'; Options = @(); Warnings = 1; Hints = 1 },
  @{ Name = 'ignore-codes'; Platform = 'Win64'; Options = @('-ignore-warnings', 'W1035', '-ignore-hints', 'H2077'); Warnings = 0; Hints = 0 },
  @{ Name = 'exclude-source'; Platform = 'Win64'; Options = @('-exclude-path-masks', 'units\*'); Warnings = 0; Hints = 0 },
  @{ Name = 'unmatched-filters'; Platform = 'Win64'; Options = @('-ignore-warnings', 'W9999', '-ignore-hints', 'H9999', '-exclude-path-masks', 'vendor\*'); Warnings = 1; Hints = 1 }
)

foreach ($case in $cases) {
  $logRoot = Join-Path $proofRoot $case.Name
  $arguments = @($projectPath, '-ver', '23', '-config', 'Debug', '-platform', $case.Platform,
    '-target', 'Rebuild', '-log-dir', $logRoot, '-keep-logs', '-ai', '-show-warnings', '-show-hints') + $case.Options
  $output = & (Join-Path $repoRoot 'build-delphi.bat') @arguments 2>&1 | Out-String
  $exitCode = $LASTEXITCODE
  [IO.File]::WriteAllText((Join-Path $proofRoot ($case.Name + '.log')), $output)
  if ($exitCode -ne 0) {
    throw "Compiler fixture failed ($exitCode). Evidence: $proofRoot`n$output"
  }
  $rawLog = @(Get-ChildItem -LiteralPath $logRoot -Filter 'msbuild-out.log' -Recurse)
  if ($rawLog.Count -ne 1) {
    throw "Expected one raw compiler log. Evidence: $proofRoot"
  }
  $rawText = Get-Content -LiteralPath $rawLog[0].FullName -Raw
  Assert-Matches $rawText '(?im)^units\\+test\.support\.pas\(\d+.*warning W1035:' 'The real compiler must emit the relative-path W1035 fixture warning.'
  Assert-Matches $rawText '(?i)H2077:' 'The real compiler must emit the H2077 fixture hint.'
  $expected = 'SUCCESS. Warnings: {0}, Hints: {1}' -f $case.Warnings, $case.Hints
  Assert-Contains $output $expected "Incorrect $($case.Name) summary; expected '$expected'. Evidence: $proofRoot"
  Write-Output "PASS $($case.Name): $expected"
}
Write-Output "PASS build warning/hint summaries. Evidence: $proofRoot"
