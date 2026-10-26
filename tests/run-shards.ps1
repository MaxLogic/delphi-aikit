#Requires -Version 7.0
<#
.SYNOPSIS
Run the complete default DUnitX selection in isolated, duration-balanced processes.
.PARAMETER SerialSummary
Compare every case result with a serial run-dunitx summary made from the same binary
with --xmlfile enabled. Missing, extra, duplicate or changed results fail the gate.
#>
[CmdletBinding()]
param(
    [ValidateRange(1,16)][int]$ShardCount = 4,
    [string]$ExecutablePath = '',
    [string]$LogRoot = '',
    [string]$OutputRoot = '',
    [string[]]$Run = @(),
    [string]$SerialSummary = '',
    [ValidateRange(1,604800)][int]$TimeoutSeconds = 14400
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\dunitx-shards.ps1')
if (-not $ExecutablePath) { $ExecutablePath = Join-Path $PSScriptRoot 'bin\Debug\DelphiAIKit.Tests.exe' }
$ExecutablePath = (Resolve-Path -LiteralPath $ExecutablePath).Path
$binaryHash = (Get-FileHash -LiteralPath $ExecutablePath -Algorithm SHA256).Hash
if (-not $LogRoot) { $LogRoot = Join-Path $PSScriptRoot '.dak\DelphiAIKit.Tests\test-runs' }
if (-not $OutputRoot) { $OutputRoot = $env:DAK_TEST_OUTPUT_ROOT }
if (-not $OutputRoot) { $OutputRoot = [IO.Path]::GetTempPath() }
$token = 's-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$runRoot = Join-Path ([IO.Path]::GetFullPath($LogRoot)) $token
$scratchRoot = Join-Path ([IO.Path]::GetFullPath($OutputRoot)) $token
if ((Join-Path $scratchRoot '16\out').Length -gt 89) { throw 'Shard output root would exceed the DUnitX 89-character limit. Set -OutputRoot to a shorter owned root.' }
[void][IO.Directory]::CreateDirectory($runRoot)
$serialCases = @()
if ($SerialSummary) {
    $serial = Get-Content -LiteralPath $SerialSummary -Raw | ConvertFrom-Json
    if ($serial.executableSha256 -ne $binaryHash) { throw 'Serial proof was produced by a different test binary.' }
    $xmlArgument = @($serial.arguments | Where-Object { $_.StartsWith('--xmlfile:', [StringComparison]::Ordinal) })
    if ($xmlArgument.Count -ne 1) { throw 'Serial proof must contain exactly one --xmlfile argument.' }
    $serialCases = @(Read-DakCaseResult $xmlArgument[0].Substring(10))
}
$roster = @(Get-DakRegisteredTest -ExecutablePath $ExecutablePath -LogDirectory $runRoot -TestsRoot $PSScriptRoot)
if ($Run.Count -gt 0) {
    $roster = @($roster | Where-Object {
        $row = $_
        @($Run | Where-Object { $row.fixture.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) -or $row.selector.Equals($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    })
}
if ($roster.Count -eq 0) { throw 'The requested registered test selection is empty.' }
$roster | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runRoot 'selected-roster.json')
$groups = @(Get-DakFixtureGroup -TestsRoot $PSScriptRoot -Roster $roster)
if ($groups.Count -eq 0) { throw 'The requested shard selection is empty.' }
$plan = @(Get-DakShardPlan -Groups $groups -ShardCount $ShardCount)
$plan | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runRoot 'plan.json')
$timer = [Diagnostics.Stopwatch]::StartNew()
$children = [Collections.Generic.List[object]]::new()
$summaries = [Collections.Generic.List[object]]::new()
$cases = [Collections.Generic.List[object]]::new()
$infrastructureErrors = [Collections.Generic.List[string]]::new()
try {
    foreach ($shard in $plan) {
        $logs = Join-Path $runRoot ([string]$shard.number)
        $scratch = Join-Path $scratchRoot ([string]$shard.number)
        foreach ($directory in @($logs, (Join-Path $scratch 'tmp'), (Join-Path $scratch 'out'))) { [void][IO.Directory]::CreateDirectory($directory) }
        $runList = Join-Path $logs 'selection.txt'
        $shard.selectors | Set-Content -LiteralPath $runList
        $xml = Join-Path $logs 'cases.xml'
        $argumentsPath = Join-Path $logs 'arguments.json'
        @(('--runlist:'+$runList), '--exclude:MaxTdbProof', ('--xmlfile:'+$xml)) | ConvertTo-Json | Set-Content -LiteralPath $argumentsPath
        $process = [Diagnostics.Process]::new()
        $process.StartInfo.FileName = (Get-Process -Id $PID).Path
        foreach ($argument in @('-NoProfile','-NonInteractive','-File',(Join-Path $PSScriptRoot 'run-dunitx.ps1'),'-ExecutablePath',$ExecutablePath,'-LogRoot',$logs,'-ArgumentFile',$argumentsPath,'-TimeoutSeconds',[string]$TimeoutSeconds)) { $process.StartInfo.ArgumentList.Add($argument) }
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.Environment['TEMP'] = Join-Path $scratch 'tmp'
        $process.StartInfo.Environment['TMP'] = Join-Path $scratch 'tmp'
        $process.StartInfo.Environment['DAK_TEST_OUTPUT_ROOT'] = Join-Path $scratch 'out'
        $stdout = [IO.File]::Create((Join-Path $logs 'wrapper-stdout.log'))
        $stderr = [IO.File]::Create((Join-Path $logs 'wrapper-stderr.log'))
        try {
            [void]$process.Start()
            $children.Add([pscustomobject]@{number=$shard.number;process=$process;stdout=$stdout;stderr=$stderr;
                copyOut=$process.StandardOutput.BaseStream.CopyToAsync($stdout);copyErr=$process.StandardError.BaseStream.CopyToAsync($stderr);logs=$logs;xml=$xml;exitCode=$null;startedAt=[datetime]::UtcNow})
        } catch { $stdout.Dispose(); $stderr.Dispose(); $process.Dispose(); throw }
    }
    foreach ($child in $children) {
        # Each started child keeps its own deadline, even when a sibling's evidence is corrupt.
        try {
            $remaining = [math]::Max(1, (($TimeoutSeconds+120)*1000)-([datetime]::UtcNow-$child.startedAt).TotalMilliseconds)
            if (-not $child.process.WaitForExit([int]$remaining)) {
                $child.process.Kill($true)
                [void]$child.process.WaitForExit(10000)
                $infrastructureErrors.Add("Shard $($child.number) exceeded its wrapper deadline.")
            }
            $child.exitCode = $child.process.ExitCode
            if (-not [Threading.Tasks.Task]::WaitAll(@($child.copyOut,$child.copyErr),30000)) { throw 'Streams remained open.' }
        } catch { $infrastructureErrors.Add("Shard $($child.number) process/streams: $_") }
        finally { $child.stdout.Dispose(); $child.stderr.Dispose() }
        try {
            $summary = Read-DakShardSummary $child.logs
            if ($child.exitCode -ne 0) { $summary.exitCode = $child.exitCode }
            $summaries.Add($summary)
        } catch { $infrastructureErrors.Add("Shard $($child.number) summary: $_") }
        try {
            foreach ($case in Read-DakCaseResult $child.xml) { $cases.Add($case) }
        } catch { $infrastructureErrors.Add("Shard $($child.number) XML: $_") }
        Write-Output "Shard $($child.number): exit=$($child.exitCode); logs=$($child.logs)"
    }
} catch { $infrastructureErrors.Add($_.ToString()) }
finally {
    foreach ($child in $children) {
        if (-not $child.process.HasExited) { $child.process.Kill($true); [void]$child.process.WaitForExit(10000) }
        $child.stdout.Dispose(); $child.stderr.Dispose(); $child.process.Dispose()
    }
    $timer.Stop()
}
try { $aggregate = Merge-DakShardResult -Summaries @($summaries) -Cases @($cases) }
catch { $infrastructureErrors.Add($_.ToString()); $aggregate = [pscustomobject]@{exitCode=1;counts=$null;shutdownLeakReport=$false;failures=@()} }
$differences = [Collections.Generic.List[string]]::new()
if ($SerialSummary) {
    $reference = @{}
    foreach ($case in $serialCases) {
        if ($reference.ContainsKey($case.id)) { $differences.Add("Duplicate serial case: $($case.id)") }
        $reference[$case.id] = $case.result
    }
    foreach ($case in $cases) {
        if (-not $reference.ContainsKey($case.id)) { $differences.Add("Extra case: $($case.id)") }
        elseif ($reference[$case.id] -ne $case.result) { $differences.Add("Changed result: $($case.id)") }
        $reference.Remove($case.id)
    }
    foreach ($missing in $reference.Keys) { $differences.Add("Missing case: $missing") }
}
$rosterDifferences = @(Compare-DakRoster -Roster $roster -Cases @($cases))
if ((Get-FileHash -LiteralPath $ExecutablePath -Algorithm SHA256).Hash -ne $binaryHash) { $infrastructureErrors.Add('Test binary changed during the gate.') }
if ($infrastructureErrors.Count -gt 0 -or $differences.Count -gt 0 -or $rosterDifferences.Count -gt 0) { $aggregate.exitCode = 1 }
$criticalPathSeconds = if ($cases.Count -gt 0) { ($cases | Measure-Object seconds -Maximum).Maximum } else { 0 }
$result = [ordered]@{exitCode=$aggregate.exitCode;counts=$aggregate.counts;failures=$aggregate.failures;
    shutdownLeakReport=$aggregate.shutdownLeakReport;errors=@($infrastructureErrors);comparisonDifferences=@($differences);rosterDifferences=$rosterDifferences;registeredCount=$roster.Count;
    durationSeconds=$timer.Elapsed.TotalSeconds;executableSha256=$binaryHash;serialSummary=$SerialSummary;
    criticalPathCaseSeconds=$criticalPathSeconds;shards=@($children | Select-Object number,exitCode,logs);
    ownedOutputRoot=$scratchRoot}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'aggregate.json')
$cases | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runRoot 'cases.json')
Write-Output ($result | ConvertTo-Json -Depth 4)
Write-Output "Aggregate: $runRoot\aggregate.json"
exit $aggregate.exitCode
