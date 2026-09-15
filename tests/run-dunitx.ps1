<#
.SYNOPSIS
Run an already-built DUnitX executable with compact output and complete logs.
.EXAMPLE
.\tests\run-dunitx.ps1 -TestArguments '--run:Test.Cli.TCliTests'
#>
[CmdletBinding()]
param(
    [string]$ExecutablePath = (Join-Path $PSScriptRoot 'DelphiAIKit.Tests.exe'),
    [string[]]$TestArguments = @(),
    [string]$LogRoot = (Join-Path $PSScriptRoot '.dak\DelphiAIKit.Tests\test-runs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\dunitx-summary.ps1')

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW/CRT escaping, including quotes and trailing slashes.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    '"' + $escaped + '"'
}

$runDirectory = Join-Path ([IO.Path]::GetFullPath($LogRoot)) ('run-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($runDirectory)
$stdoutPath = Join-Path $runDirectory 'stdout.log'
$stderrPath = Join-Path $runDirectory 'stderr.log'
$summaryPath = Join-Path $runDirectory 'summary.json'
$process = New-Object System.Diagnostics.Process
$stdoutFile = $null
$stderrFile = $null
$timer = [Diagnostics.Stopwatch]::StartNew()
$launchError = $null
$processExitCode = 1
try {
    $resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath).Path
    $process.StartInfo.FileName = $resolvedExecutable
    $process.StartInfo.Arguments = (($TestArguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $process.StartInfo.WorkingDirectory = $PSScriptRoot
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $stdoutFile = [IO.File]::Create($stdoutPath)
    $stderrFile = [IO.File]::Create($stderrPath)
    [void]$process.Start()
    # Drain both streams concurrently to disk, without converting or dropping bytes.
    $stdoutCopy = $process.StandardOutput.BaseStream.CopyToAsync($stdoutFile)
    $stderrCopy = $process.StandardError.BaseStream.CopyToAsync($stderrFile)
    $process.WaitForExit()
    [void]$stdoutCopy.GetAwaiter().GetResult()
    [void]$stderrCopy.GetAwaiter().GetResult()
    $processExitCode = $process.ExitCode
}
catch {
    $launchError = $_.Exception.Message
    [IO.File]::WriteAllText((Join-Path $runDirectory 'runner-error.log'), $_.ToString())
}
finally {
    $timer.Stop()
    if ($null -ne $stdoutFile) { $stdoutFile.Dispose() }
    if ($null -ne $stderrFile) { $stderrFile.Dispose() }
    $process.Dispose()
}

$stdoutText = ''
if (Test-Path -LiteralPath $stdoutPath) { $stdoutText = [IO.File]::ReadAllText($stdoutPath) }
$result = Get-DakTestSummary -Text $stdoutText -ProcessExitCode $processExitCode
$summary = [ordered]@{
    status = $result.Status
    exitCode = $result.ExitCode
    processExitCode = $processExitCode
    counts = $result.Counts
    executable = $ExecutablePath
    arguments = $TestArguments
    durationSeconds = [math]::Round($timer.Elapsed.TotalSeconds, 3)
    stdout = $stdoutPath
    stderr = $stderrPath
    runnerError = $launchError
}
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Output ("DUnitX {0}; exit={1}; processExit={2}; seconds={3}" -f $result.Status, $result.ExitCode, $processExitCode, $summary.durationSeconds)
if ($null -ne $result.Counts) {
    $c = $result.Counts
    Write-Output ("Found={0} Passed={1} Failed={2} Errored={3} Leaked={4} Ignored={5}" -f $c.Found, $c.Passed, $c.Failed, $c.Errored, $c.Leaked, $c.Ignored)
} else { Write-Output 'Counts unavailable: complete DUnitX footer not found.' }
if ($result.ExitCode -ne 0) {
    if ($launchError) { Write-Output ('Runner error: ' + $launchError) }
    $failureStart = $stdoutText.IndexOf('Failing Tests', [StringComparison]::Ordinal)
    $details = if ($failureStart -ge 0) { $stdoutText.Substring($failureStart) } else { $stdoutText }
    $lines = @($details -split '\r?\n' | Where-Object { $_.Trim() })
    if ($failureStart -lt 0) { $lines = @($lines | Select-Object -Last 12) }
    Write-Output 'Failure excerpt (bounded; complete details in logs):'
    $lines | Select-Object -First 20 | ForEach-Object { $_.Substring(0, [math]::Min(400, $_.Length)) }
    if (Test-Path -LiteralPath $stderrPath) {
        Get-Content -LiteralPath $stderrPath -Tail 8 | ForEach-Object { $_.Substring(0, [math]::Min(400, $_.Length)) }
    }
}
Write-Output ('Full stdout: ' + $stdoutPath)
Write-Output ('Full stderr: ' + $stderrPath)
Write-Output ('Summary: ' + $summaryPath)
exit $result.ExitCode
