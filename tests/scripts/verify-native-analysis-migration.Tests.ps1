#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot 'verify-native-analysis-migration.ps1')
    $script:AllowedRoot = Join-Path $TestDrive 'allowed'
    [void][IO.Directory]::CreateDirectory($script:AllowedRoot)
}

Describe 'Migration proof path boundary' {
    It 'accepts an ordinary descendant without creating it' {
        $path = Join-Path $script:AllowedRoot 'new/output'
        Resolve-MigrationOutputPath -Path $path -Root $script:AllowedRoot |
            Should -Be ([IO.Path]::GetFullPath($path))
        Test-Path -LiteralPath $path | Should -BeFalse
    }

    It 'rejects a sibling whose name merely starts with the root' {
        { Resolve-MigrationOutputPath -Path ($script:AllowedRoot + '-other/output') -Root $script:AllowedRoot } |
            Should -Throw '*outside*'
    }

    It 'rejects an ancestor traversal and the root itself' {
        { Resolve-MigrationOutputPath -Path (Join-Path $script:AllowedRoot '../escaped') -Root $script:AllowedRoot } |
            Should -Throw '*outside*'
        { Resolve-MigrationOutputPath -Path $script:AllowedRoot -Root $script:AllowedRoot } |
            Should -Throw '*outside*'
    }

    It 'rejects a real junction even when the textual path is inside the root' {
        $target = Join-Path $TestDrive 'outside'
        [void][IO.Directory]::CreateDirectory($target)
        $junction = Join-Path $script:AllowedRoot 'junction'
        [void](New-Item -ItemType Junction -Path $junction -Target $target)
        { Resolve-MigrationOutputPath -Path (Join-Path $junction 'output') -Root $script:AllowedRoot } |
            Should -Throw '*reparse*'
    }
}

Describe 'Migration sample statistics' {
    It 'uses an even median and nearest-rank p95 while preserving sample order' {
        $values = @(10.0, 1.0, 9.0, 2.0, 8.0, 3.0, 7.0, 4.0, 6.0, 5.0)
        $result = Get-MigrationStatistic -Values $values
        $result.median | Should -Be 5.5
        $result.p95 | Should -Be 10.0
        $values[0] | Should -Be 10.0
    }

    It 'rejects empty and non-finite sample sets' {
        { Get-MigrationStatistic -Values @() } | Should -Throw '*sample*'
        { Get-MigrationStatistic -Values @(1, [double]::NaN) } | Should -Throw '*finite*'
    }
}

Describe 'Migration process evidence' {
    It 'captures a real child exit and both output streams without changing parent environment' {
        $before = $env:DAK_MIGRATION_TEST_VALUE
        $logPath = Join-Path $script:AllowedRoot 'child'
        $result = Invoke-MigrationProcess -Executable (Get-Process -Id $PID).Path -Arguments @(
            '-NoProfile', '-Command', '[Console]::Out.Write($env:DAK_MIGRATION_TEST_VALUE); [Console]::Error.Write("stderr"); exit 7'
        ) -WorkingDirectory $script:AllowedRoot -Environment @{ DAK_MIGRATION_TEST_VALUE = 'a "quoted" value' } -LogPath $logPath
        $result.exit_code | Should -Be 7
        $result.elapsed_ms | Should -BeGreaterThan 0
        $result.peak_working_set_bytes | Should -BeGreaterThan 0
        Get-Content -LiteralPath ($logPath + '.stdout') -Raw | Should -Be 'a "quoted" value'
        Get-Content -LiteralPath ($logPath + '.stderr') -Raw | Should -Be 'stderr'
        $env:DAK_MIGRATION_TEST_VALUE | Should -Be $before
    }

    It 'preserves a retained log instead of overwriting it' {
        $logPath = Join-Path $script:AllowedRoot 'retained'
        Set-Content -LiteralPath ($logPath + '.stdout') -Value 'retained evidence'
        { Invoke-MigrationProcess -Executable (Get-Process -Id $PID).Path -Arguments @('-NoProfile', '-Command', 'exit 0') `
            -WorkingDirectory $script:AllowedRoot -LogPath $logPath } | Should -Throw '*already exists*'
        Get-Content -LiteralPath ($logPath + '.stdout') | Should -Be 'retained evidence'
    }

    It 'bounds output draining when a descendant retains the stream after its parent exits' {
        $logPath = Join-Path $script:AllowedRoot 'descendant'
        $pidFile = Join-Path $script:AllowedRoot 'descendant.pid'
        $command = '$info = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path); $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.ArgumentList.Add("-NoProfile"); $info.ArgumentList.Add("-Command"); $info.ArgumentList.Add("Start-Sleep -Seconds 4"); $child = [Diagnostics.Process]::Start($info); [IO.File]::WriteAllText($env:DAK_CHILD_PID, [string]$child.Id); exit 0'
        $watch = [Diagnostics.Stopwatch]::StartNew()
        try {
            $result = Invoke-MigrationProcess -Executable (Get-Process -Id $PID).Path -Arguments @('-NoProfile', '-Command', $command) `
                -WorkingDirectory $script:AllowedRoot -LogPath $logPath -TimeoutSeconds 1 -Environment @{ DAK_CHILD_PID = $pidFile }
            $watch.Stop()
            $result.drain_timed_out | Should -BeTrue
            $watch.Elapsed.TotalSeconds | Should -BeLessThan 3
        }
        finally {
            if (Test-Path -LiteralPath $pidFile) {
                $child = Get-Process -Id ([int](Get-Content -LiteralPath $pidFile)) -ErrorAction SilentlyContinue
                if ($child -and -not $child.WaitForExit(6000)) { $child.Kill($true); [void]$child.WaitForExit(1000) }
            }
        }
    }
}

Describe 'Migration manifest validation' {
    It 'rejects an empty selection instead of reporting a passing baseline' {
        { Assert-MigrationScenario -Scenarios @() } | Should -Throw '*empty*'
    }

    It 'rejects missing proof fields before starting a process' {
        { Assert-MigrationScenario -Scenarios @(@{ name = 'example' }) } | Should -Throw '*executable*'
    }

    It 'rejects a manifest overriding the protected fixture environment' {
        $scenario = @{
            name = 'unsafe'; executable = 'unused'; arguments = @(); working_directory = 'unused'
            area = 'Reports'; reset_source = 'unused'; output = 'unused'; expected_exit = 0
            environment = @{ DAK_MAXTDB_FIXTURE = 'F:\projects\OEC\TE5\maxTdb' }
        }
        { Assert-MigrationScenario -Scenarios @($scenario) } | Should -Throw '*protected*'
    }

    It 'rejects writable output in the retained reference subtree before launching anything' {
        $repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $evidence = Join-Path $repo 'projects/.dak/DelphiAIKit/native-analysis-migration'
        $manifestPath = Join-Path $script:AllowedRoot 'unsafe-manifest.json'
        @{
            result_root = Join-Path $evidence ('measurements/test-' + [guid]::NewGuid().ToString('N'))
            scenarios = @(@{
                name = 'unsafe'; executable = 'missing-executable'; arguments = @(); working_directory = $repo
                area = 'Reports'; reset_source = Join-Path $evidence 'seeds/report-small'
                output = Join-Path $evidence 'python-reference/must-never-write'; expected_exit = 0
                environment = @{}
            })
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath
        { & (Join-Path $PSScriptRoot 'verify-native-analysis-migration.ps1') -Manifest $manifestPath } |
            Should -Throw '*outside the owned root*'
    }
}

Describe 'Migration sample preparation' {
    It 'refuses to overlay an earlier sample or discard an unrecognized file' {
        $seed = Join-Path $script:AllowedRoot 'seed'
        $output = Join-Path $script:AllowedRoot 'scratch/sample'
        [void][IO.Directory]::CreateDirectory($seed)
        [void][IO.Directory]::CreateDirectory($output)
        Set-Content -LiteralPath (Join-Path $seed 'input.txt') -Value 'seed'
        Set-Content -LiteralPath (Join-Path $output 'input.txt') -Value 'retained'
        Set-Content -LiteralPath (Join-Path $output 'cache.txt') -Value 'stale cache'
        { Initialize-MigrationSample -Seed $seed -Output $output -ScratchRoot (Join-Path $script:AllowedRoot 'scratch') } |
            Should -Throw '*already exists*'
        Get-Content -LiteralPath (Join-Path $output 'input.txt') | Should -Be 'retained'
        Get-Content -LiteralPath (Join-Path $output 'cache.txt') | Should -Be 'stale cache'
    }
}

Describe 'Retained baseline completeness' {
    BeforeEach {
        $script:Samples = @(
            foreach ($phase in @('cold', 'warmup', 'warm')) {
                $count = switch ($phase) { cold {5} warmup {2} warm {10} }
                foreach ($index in 1..$count) {
                    [pscustomobject]@{phase=$phase; index=$index; exit_code=0; timed_out=$false; drain_timed_out=$false; elapsed_ms=100.0+$index; peak_working_set_bytes=4096; memory_scope='root process'}
                }
            }
        )
    }

    It 'requires five cold, two priming and ten warm samples' {
        $result = Get-MigrationRetainedSampleSummary -Samples $script:Samples
        $result.cold.count | Should -Be 5
        $result.warm.count | Should -Be 10
        $result.warm.median | Should -Be 105.5
        { Get-MigrationRetainedSampleSummary -Samples $script:Samples[1..16] } | Should -Throw '*sample*'
    }

    It 'rejects duplicate sample identity and failed or incomplete processes' {
        $script:Samples[1].index = 1
        { Get-MigrationRetainedSampleSummary -Samples $script:Samples } | Should -Throw '*identity*'
        $script:Samples[1].index = 2
        $script:Samples[0].drain_timed_out = $true
        { Get-MigrationRetainedSampleSummary -Samples $script:Samples } | Should -Throw '*process*'
    }

    It 'rejects missing memory evidence and non-finite durations' {
        $script:Samples[0].peak_working_set_bytes = 0
        { Get-MigrationRetainedSampleSummary -Samples $script:Samples } | Should -Throw '*memory*'
        $script:Samples[0].peak_working_set_bytes = 4096
        $script:Samples[0].elapsed_ms = [double]::NaN
        { Get-MigrationRetainedSampleSummary -Samples $script:Samples } | Should -Throw '*duration*'
    }
}

Describe 'Frozen source inventory' {
    It 'detects an added source while excluding generated state' {
        $root=Join-Path $script:AllowedRoot 'inventory'
        [void][IO.Directory]::CreateDirectory((Join-Path $root 'nested'))
        [void][IO.Directory]::CreateDirectory((Join-Path $root '.dak'))
        [IO.File]::WriteAllText((Join-Path $root 'nested/Owned.pas'), 'unit Owned;')
        [IO.File]::WriteAllText((Join-Path $root '.dak/Generated.pas'), 'unit Generated;')
        $frozen=@('nested/Owned.pas')
        Assert-MigrationSourceInventory -Root $root -Expected $frozen
        [IO.File]::WriteAllText((Join-Path $root 'nested/Added.pas'), 'unit Added;')
        { Assert-MigrationSourceInventory -Root $root -Expected $frozen } | Should -Throw '*inventory*'
    }
}
