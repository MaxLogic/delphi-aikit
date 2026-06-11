$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$testExe = Join-Path $repoRoot 'tests\DelphiAIKit.Tests.exe'
if (-not (Test-Path $testExe)) {
    throw "Test executable not found: $testExe"
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('dak-parallel-temp-roots-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

function Start-TestRun([string]$Name, [string]$Filter) {
    $logPath = Join-Path $tempRoot "$Name.log"
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $testExe
    $info.Arguments = '--hidebanner --consolemode:quiet -r:' + $Filter
    $info.WorkingDirectory = $repoRoot
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment['DAK_TEST_OUTPUT_ROOT'] = $tempRoot
    $info.Environment['DAK_TEST_KEEP_TEMP'] = '1'
    $process = [Diagnostics.Process]::Start($info)
    return [pscustomobject]@{ Name = $Name; Process = $process; LogPath = $logPath }
}

function Complete-TestRun($Run) {
    if (-not $Run.Process.WaitForExit(30000)) {
        try { $Run.Process.Kill() } catch {}
        throw "Timed out waiting for $($Run.Name). Log: $($Run.LogPath)"
    }
    $text = $Run.Process.StandardOutput.ReadToEnd() + $Run.Process.StandardError.ReadToEnd()
    Set-Content -LiteralPath $Run.LogPath -Value $text -Encoding UTF8
    if ($Run.Process.ExitCode -ne 0) {
        throw "$($Run.Name) failed with exit $($Run.Process.ExitCode). Log: $($Run.LogPath)`n$text"
    }
    if ($text -notmatch 'Tests Failed\s+:\s+0') {
        throw "$($Run.Name) did not report a clean DUnitX run. Log: $($Run.LogPath)`n$text"
    }
}

try {
    $runs = @(
        (Start-TestRun 'utils-a' 'Test.Utils'),
        (Start-TestRun 'utils-b' 'Test.Utils'),
        (Start-TestRun 'source-context-a' 'Test.SourceContext'),
        (Start-TestRun 'source-context-b' 'Test.SourceContext')
    )

    foreach ($run in $runs) {
        Complete-TestRun $run
    }

    $runRoots = @(Get-ChildItem -LiteralPath $tempRoot -Directory -Filter 'run-*')
    if ($runRoots.Count -lt 2) {
        throw "Expected at least two process-scoped run roots under $tempRoot."
    }
    foreach ($runRoot in $runRoots) {
        if ($runRoot.Name -notmatch '^run-\d+-') {
            throw "Unexpected run-root name: $($runRoot.FullName)"
        }
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force
    Write-Host 'PASS: two focused DAK test processes used process-scoped temp roots concurrently.'
}
catch {
    Write-Host "Preserving failing-run evidence under $tempRoot"
    throw
}
