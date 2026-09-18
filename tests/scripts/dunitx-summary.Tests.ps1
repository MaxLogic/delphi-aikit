BeforeAll {
    . (Join-Path $PSScriptRoot 'dunitx-summary.ps1')
    $good = @'
DUnitX - Starting Tests.
Tests Found   : 3
Tests Ignored : 0
Tests Passed  : 3
Tests Leaked  : 0
Tests Failed  : 0
Tests Errored : 0
'@
}

Describe 'DUnitX summary evidence' {
    It 'recognizes complete passing counts' {
        $result = Get-DakTestSummary -Text $good -ProcessExitCode 0
        $result.Status | Should -Be 'passed'
        $result.ExitCode | Should -Be 0
        $result.Counts.Found | Should -Be 3
        $result.Counts.Passed | Should -Be 3
    }

    It 'rejects <Name> despite a zero process exit' -ForEach @(
        @{ Name = 'failed test'; Old = 'Passed  : 3'; New = 'Passed  : 2'; Old2 = 'Failed  : 0'; New2 = 'Failed  : 1'; Status = 'failed' }
        @{ Name = 'ignored test'; Old = 'Passed  : 3'; New = 'Passed  : 2'; Old2 = 'Ignored : 0'; New2 = 'Ignored : 1'; Status = 'failed' }
        @{ Name = 'errored test'; Old = 'Passed  : 3'; New = 'Passed  : 2'; Old2 = 'Errored : 0'; New2 = 'Errored : 1'; Status = 'failed' }
        @{ Name = 'leaked test'; Old = 'Passed  : 3'; New = 'Passed  : 2'; Old2 = 'Leaked  : 0'; New2 = 'Leaked  : 1'; Status = 'failed' }
    ) {
        $log = $good.Replace($Old, $New).Replace($Old2, $New2)
        $result = Get-DakTestSummary -Text $log -ProcessExitCode 0
        $result.Status | Should -Be $Status
        $result.ExitCode | Should -Be 1
    }

    It 'rejects empty selection, incomplete counts and contradictory totals' {
        foreach ($log in @($good.Replace(': 3', ': 0'), $good.Replace('Tests Errored : 0', ''), $good.Replace('Found   : 3', 'Found   : 9'))) {
            (Get-DakTestSummary -Text $log -ProcessExitCode 0).ExitCode | Should -Be 1
        }
    }

    It 'does not combine partial footers or trust a prior passing footer' {
        $log = $good + "`nTests Found : 7`nTests Passed : 7"
        (Get-DakTestSummary -Text $log -ProcessExitCode 0).Status | Should -Be 'incomplete'
    }

    It 'preserves a failing process status even with passing counts' {
        (Get-DakTestSummary -Text $good -ProcessExitCode 37).ExitCode | Should -Be 37
    }

    # T-347: FastMM prints its shutdown leak report after DUnitX has already counted Leaked=0.
    It 'fails a passing run whose <Stream> carries a shutdown leak report' -ForEach @(
        @{ Stream = 'stderr' }
        @{ Stream = 'stdout' }
    ) {
        $report = "Unexpected Memory Leak`r`nAn unexpected memory leak has occurred. The unexpected small block leaks are:`r`n`r`n9 - 24 bytes: UnicodeString x 12`r`n"
        if ($Stream -eq 'stderr') {
            $result = Get-DakTestSummary -Text $good -ErrorText $report -ProcessExitCode 0
        } else {
            $result = Get-DakTestSummary -Text ($good + "`r`n" + $report) -ProcessExitCode 0
        }
        $result.Status | Should -Be 'failed'
        $result.ExitCode | Should -Be 1
        $result.ShutdownLeakReport | Should -BeTrue
        $result.Counts.Leaked | Should -Be 0
    }

    It 'keeps a clean run passing when stderr has other diagnostics' {
        $result = Get-DakTestSummary -Text $good -ErrorText "diagnostic on stderr`r`n" -ProcessExitCode 0
        $result.Status | Should -Be 'passed'
        $result.ShutdownLeakReport | Should -BeFalse
    }
}

Describe 'Compact runner with real child-process streams' {
    It 'preserves noisy stdout, stderr and arguments while emitting a bounded passing summary' {
        $hostExecutable = (Get-Process -Id $PID).Path
        $runner = Join-Path $PSScriptRoot '..\run-dunitx.ps1'
        $fixture = Join-Path $TestDrive 'console emitter.ps1'
        $logRoot = Join-Path $TestDrive 'run logs'
        $value = 'path with spaces "quoted" trailing\'
        # This is a console-format fixture, not a replacement for product tests.
        $body = @'
param([string]$Value)
$bytes = [Text.Encoding]::UTF8.GetBytes(('noise-' * 12000) + "`r`nargument=" + $Value + "`r`n")
$out = [Console]::OpenStandardOutput()
$out.Write($bytes, 0, $bytes.Length)
$err = [Console]::OpenStandardError()
$warning = [Text.Encoding]::UTF8.GetBytes("diagnostic on stderr`r`n")
$err.Write($warning, 0, $warning.Length)
'@
        $body += "`r`n[Console]::WriteLine(@'`r`n$good`r`n'@)`r`n"
        [IO.File]::WriteAllText($fixture, $body)
        $command = "& '$runner' -ExecutablePath '$hostExecutable' -LogRoot '$logRoot' -TestArguments @('-NoProfile','-NonInteractive','-File','$fixture', '$value')"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $console = @(& $hostExecutable -NoProfile -NonInteractive -EncodedCommand $encoded)
        $LASTEXITCODE | Should -Be 0
        $console.Count | Should -BeLessOrEqual 6
        $console -join "`n" | Should -Match 'Found=3 Passed=3'
        $summaryFile = Get-ChildItem -LiteralPath $logRoot -Filter summary.json -Recurse
        $summary = Get-Content -LiteralPath $summaryFile.FullName -Raw | ConvertFrom-Json
        $summary.counts.Passed | Should -Be 3
        $raw = [IO.File]::ReadAllBytes($summary.stdout)
        $expectedPrefix = [Text.Encoding]::UTF8.GetBytes(('noise-' * 12000) + "`r`nargument=" + $value + "`r`n")
        [Convert]::ToBase64String($raw[0..($expectedPrefix.Length - 1)]) | Should -Be ([Convert]::ToBase64String($expectedPrefix))
        [IO.File]::ReadAllText($summary.stderr) | Should -Be "diagnostic on stderr`r`n"
    }

    It 'fails a passing child process that prints a shutdown leak report on stderr' {
        $hostExecutable = (Get-Process -Id $PID).Path
        $runner = Join-Path $PSScriptRoot '..\run-dunitx.ps1'
        $fixture = Join-Path $TestDrive 'leaking emitter.ps1'
        $logRoot = Join-Path $TestDrive 'leak logs'
        # Console-format fixture: the passing DUnitX footer, then FastMM's report on stderr at exit.
        $body = "[Console]::WriteLine(@'`r`n$good`r`n'@)`r`n" +
            "[Console]::Error.WriteLine('Unexpected Memory Leak')`r`n" +
            "[Console]::Error.WriteLine('An unexpected memory leak has occurred. The unexpected small block leaks are:')`r`n"
        [IO.File]::WriteAllText($fixture, $body)
        $command = "& '$runner' -ExecutablePath '$hostExecutable' -LogRoot '$logRoot' -TestArguments @('-NoProfile','-NonInteractive','-File','$fixture')"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $console = @(& $hostExecutable -NoProfile -NonInteractive -EncodedCommand $encoded)
        $LASTEXITCODE | Should -Be 1
        $console -join "`n" | Should -Match 'Shutdown memory leak report found'
        $summaryFile = Get-ChildItem -LiteralPath $logRoot -Filter summary.json -Recurse
        $summary = Get-Content -LiteralPath $summaryFile.FullName -Raw | ConvertFrom-Json
        $summary.status | Should -Be 'failed'
        $summary.shutdownLeakReport | Should -BeTrue
        $summary.counts.Leaked | Should -Be 0
    }

    It 'reports launch failure without inventing test counts' {
        $hostExecutable = (Get-Process -Id $PID).Path
        $runner = Join-Path $PSScriptRoot '..\run-dunitx.ps1'
        $logRoot = Join-Path $TestDrive 'missing executable logs'
        $console = @(& $hostExecutable -NoProfile -NonInteractive -File $runner -ExecutablePath (Join-Path $TestDrive 'missing.exe') -LogRoot $logRoot)
        $LASTEXITCODE | Should -Be 1
        $console -join "`n" | Should -Match 'Counts unavailable'
        @(Get-ChildItem -LiteralPath $logRoot -Filter runner-error.log -Recurse).Count | Should -Be 1
    }
}
