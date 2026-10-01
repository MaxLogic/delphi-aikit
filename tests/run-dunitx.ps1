<#
.SYNOPSIS
Run an already-built DUnitX executable with compact output and complete logs.
.PARAMETER TimeoutSeconds
Deadline for the whole test process. The default of 14400 seconds (4 hours)
covers the complete retained suite on a busy machine. On expiry the runner
stops the test process tree and reports a failure with exit code 124. Zero
means no limit: the run waits until the test process exits on its own. Negative
values are rejected as a parameter error. summary.json records the value as
timeoutSeconds (0 = no limit); timedOut is always false when there is no limit.
.EXAMPLE
.\tests\run-dunitx.ps1 -TestArguments '--run:Test.Cli.TCliTests'
#>
[CmdletBinding()]
param(
    [string]$ExecutablePath = '',
    [string[]]$TestArguments = @(),
    [string]$LogRoot = '',
    [ValidateRange(0, 604800)]
    [int]$TimeoutSeconds = 14400
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# DAK-380: Windows PowerShell 5.1 leaves $PSScriptRoot empty in parameter defaults
# under -File, so the defaults are resolved here, where both hosts set it.
if (-not $ExecutablePath) { $ExecutablePath = Join-Path $PSScriptRoot 'bin\Debug\DelphiAIKit.Tests.exe' }
if (-not $LogRoot) { $LogRoot = Join-Path $PSScriptRoot '.dak\DelphiAIKit.Tests\test-runs' }
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
$timedOut = $false
# Stream copies end when every holder of the pipe write ends has exited.
$streamCloseMilliseconds = 30000
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
    # DAK-369: 0 means no limit; WaitForExit(0) would return at once, -1 waits forever.
    $waitMilliseconds = if ($TimeoutSeconds -eq 0) { -1 } else { $TimeoutSeconds * 1000 }
    if (-not $process.WaitForExit($waitMilliseconds)) {
        $timedOut = $true
        try {
            $process.Kill($true)
        }
        catch [System.Management.Automation.MethodException] {
            # Windows PowerShell 5.1 (.NET Framework) has no tree overload.
            & taskkill.exe /PID $process.Id /T /F | Out-Null
        }
        if (-not $process.WaitForExit(10000)) {
            throw "DUnitX process $($process.Id) did not stop within 10 s after its $TimeoutSeconds s deadline."
        }
    }
    if (-not [Threading.Tasks.Task]::WaitAll(@($stdoutCopy, $stderrCopy), $streamCloseMilliseconds)) {
        throw "DUnitX output streams stayed open $($streamCloseMilliseconds / 1000) s after the process exited; a descendant still holds them."
    }
    if ($timedOut) {
        $processExitCode = 124
        $launchError = "DUnitX did not exit within $TimeoutSeconds s; the test process tree was stopped. Narrow the selection or raise -TimeoutSeconds."
        [IO.File]::WriteAllText((Join-Path $runDirectory 'runner-error.log'), $launchError)
    }
    else {
        $processExitCode = $process.ExitCode
    }
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
$stderrText = ''
if (Test-Path -LiteralPath $stderrPath) { $stderrText = [IO.File]::ReadAllText($stderrPath) }
$result = Get-DakTestSummary -Text $stdoutText -ErrorText $stderrText -ProcessExitCode $processExitCode
$summary = [ordered]@{
    status = $result.Status
    exitCode = $result.ExitCode
    processExitCode = $processExitCode
    timedOut = $timedOut
    timeoutSeconds = $TimeoutSeconds
    counts = $result.Counts
    shutdownLeakReport = $result.ShutdownLeakReport
    executable = $ExecutablePath
    arguments = $TestArguments
    durationSeconds = [math]::Round($timer.Elapsed.TotalSeconds, 3)
    stdout = $stdoutPath
    stderr = $stderrPath
    runnerError = $launchError
}
# UTF-8 without a BOM on both hosts; Set-Content -Encoding UTF8 adds one under 5.1.
[IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding $false))
Write-Output ("DUnitX {0}; exit={1}; processExit={2}; seconds={3}" -f $result.Status, $result.ExitCode, $processExitCode, $summary.durationSeconds)
if ($null -ne $result.Counts) {
    $c = $result.Counts
    Write-Output ("Found={0} Passed={1} Failed={2} Errored={3} Leaked={4} Ignored={5}" -f $c.Found, $c.Passed, $c.Failed, $c.Errored, $c.Leaked, $c.Ignored)
} else { Write-Output 'Counts unavailable: complete DUnitX footer not found.' }
if ($result.ShutdownLeakReport) { Write-Output 'Shutdown memory leak report found (FastMM, printed after the DUnitX counts); see stderr.' }
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
