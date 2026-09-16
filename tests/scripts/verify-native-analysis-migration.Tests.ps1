#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot 'verify-native-analysis-migration.ps1')
    $script:AllowedRoot = Join-Path $TestDrive 'allowed'
    [void][IO.Directory]::CreateDirectory($script:AllowedRoot)
}

Describe 'Workspace comparison child environment' {
    It 'pins the authorized fixture and explicitly removes test output while preserving parent values' {
        $beforeFixture = $env:DAK_MAXTDB_FIXTURE
        $beforeOutput = $env:DAK_TEST_OUTPUT_ROOT
        try {
            $env:DAK_MAXTDB_FIXTURE = 'C:\unrelated\production'
            $env:DAK_TEST_OUTPUT_ROOT = 'C:\unrelated\output'
            $environment = Get-MigrationWorkspaceEnvironment
            $environment.DAK_MAXTDB_FIXTURE | Should -Be 'F:\projects\MaxLogic\DelphiAiKit\tests\fixtures\test-projects\semantic-isolated-t311\maxTdb'
            $environment.ContainsKey('DAK_TEST_OUTPUT_ROOT') | Should -BeTrue
            $environment.DAK_TEST_OUTPUT_ROOT | Should -BeNullOrEmpty
            $environment.PYTHONDONTWRITEBYTECODE | Should -Be '1'
            $environment.MAXLOGIC_MADEXCEPT_AI | Should -Be '1'
            $environment.DAK_DOCTOR_RUN | Should -BeNullOrEmpty
            $env:DAK_MAXTDB_FIXTURE | Should -Be 'C:\unrelated\production'
            $env:DAK_TEST_OUTPUT_ROOT | Should -Be 'C:\unrelated\output'
            $env:DAK_TEST_OUTPUT_ROOT = $null
            (Get-MigrationWorkspaceEnvironment).ContainsKey('DAK_TEST_OUTPUT_ROOT') | Should -BeTrue
        } finally {
            $env:DAK_MAXTDB_FIXTURE = $beforeFixture
            $env:DAK_TEST_OUTPUT_ROOT = $beforeOutput
        }
    }
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

Describe 'Workspace semantic comparison' {
    BeforeAll {
        $script:WorkspaceReference = '{"workspace":{"root":"fixture"},"provenance":{"target":{"paths":["a","b"],"dirty":false,"revision":null},"dak":{"head":"old"}}}'
        $script:WorkspaceCandidate = '{"provenance":{"dak":{"head":"new"},"target":{"revision":null,"dirty":false,"paths":["a","b"]}},"workspace":{"root":"fixture"}}'
    }
    It 'compares complete records despite object key order and validated engine identity' {
        (Compare-MigrationWorkspace $script:WorkspaceReference $script:WorkspaceCandidate '{"head":"new"}').equal | Should -BeTrue
    }
    It 'rejects unvalidated identity and every target semantic change' {
        { Compare-MigrationWorkspace $script:WorkspaceReference $script:WorkspaceCandidate '{"head":"wrong"}' } | Should -Throw '*identity*'
        foreach ($pair in @(@('"a","b"','"b","a"'), @('false','"false"'), @('"revision":null,',''), @('null','"changed"'), @('"root":"fixture"','"root":"other"'))) {
            $changed = $script:WorkspaceCandidate.Replace($pair[0], $pair[1])
            { Compare-MigrationWorkspace $script:WorkspaceReference $changed '{"head":"new"}' } | Should -Throw '*differs*'
        }
    }
    It 'rejects duplicate fields instead of silently replacing them' {
        { Compare-MigrationWorkspace $script:WorkspaceReference $script:WorkspaceCandidate.Replace('"dirty":false','"dirty":false,"dirty":false') '{"head":"new"}' } | Should -Throw '*Duplicate*'
    }
}

Describe 'Workspace benchmark budgets' {
    BeforeEach {
        $script:Budget = [pscustomobject]@{median_ms=100;p95_ms=150;peak_root_bytes=4096}
        $script:BudgetSamples = @(foreach ($phase in @('cold','warmup','warm')) {
            $count = switch ($phase) {cold {5} warmup {2} warm {10}}
            for ($index=1; $index -le $count; $index++) {
                [pscustomobject]@{phase=$phase;index=$index;exit_code=0;timed_out=$false;drain_timed_out=$false;elapsed_ms=100;peak_working_set_bytes=4096;memory_scope='root'}
            }
        })
    }
    It 'accepts inclusive limits and discards priming durations from latency statistics' {
        $script:BudgetSamples[5].elapsed_ms=9999
        $result=Get-MigrationWorkspaceBudgetResult -Samples $script:BudgetSamples -Budget $script:Budget
        $result.passed | Should -BeTrue
        $result.statistics.cold.count | Should -Be 5
        $result.statistics.warm.count | Should -Be 10
    }
    It 'rejects each phase median and tail separately and any sample memory excess' {
        foreach ($phase in @('cold','warm')) {
            $selected=@($script:BudgetSamples | Where-Object phase -EQ $phase)
            foreach ($sample in $selected) {$sample.elapsed_ms=101}
            (Get-MigrationWorkspaceBudgetResult $script:BudgetSamples $script:Budget).violations | Should -Contain "$phase median_ms"
            foreach ($sample in $selected) {$sample.elapsed_ms=100}
            $selected[0].elapsed_ms=151
            (Get-MigrationWorkspaceBudgetResult $script:BudgetSamples $script:Budget).violations | Should -Contain "$phase p95_ms"
            $selected[0].elapsed_ms=100
        }
        $script:BudgetSamples[5].peak_working_set_bytes=4097
        (Get-MigrationWorkspaceBudgetResult $script:BudgetSamples $script:Budget).passed | Should -BeFalse
    }
    It 'rejects incomplete samples and missing or nonfinite budget limits' {
        {Get-MigrationWorkspaceBudgetResult $script:BudgetSamples[1..16] $script:Budget} | Should -Throw '*samples*'
        $script:Budget.median_ms=[double]::NaN
        {Get-MigrationWorkspaceBudgetResult $script:BudgetSamples $script:Budget} | Should -Throw '*budget*'
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

Describe 'Report benchmark reference control' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'compare-native-analysis-reports.ps1')
        $script:Frozen = [pscustomobject]@{ cold = [pscustomobject]@{ median = 2000.0 }; warm = [pscustomobject]@{ median = 1000.0 } }
        function New-ControlSample { param([string]$Phase, [double]$Ms) [pscustomobject]@{ phase = $Phase; elapsed_ms = $Ms } }
    }

    It 'takes the larger of the cold ratio and the averaged warm ratio' {
        $control = Get-MigrationReferenceControl -Frozen $script:Frozen -Samples @(
            (New-ControlSample cold 2400), (New-ControlSample warm 1500), (New-ControlSample warm 1700))
        $control.cold_ratio | Should -Be 1.2
        $control.warm_median_ms | Should -Be 1600
        $control.warm_ratio | Should -Be 1.6
        $control.ratio | Should -Be 1.6
        $control.environment_drift | Should -BeTrue
    }

    It 'treats the threshold itself as a usable machine' {
        $control = Get-MigrationReferenceControl -Frozen $script:Frozen -Samples @(
            (New-ControlSample cold 3000), (New-ControlSample warm 1500), (New-ControlSample warm 1500))
        $control.ratio | Should -Be 1.5
        $control.environment_drift | Should -BeFalse
    }

    It 'rejects a malformed control instead of guessing' {
        { Get-MigrationReferenceControl -Frozen $script:Frozen -Samples @((New-ControlSample cold 1), (New-ControlSample warm 1)) } |
            Should -Throw '*one cold and two warm*'
        { Get-MigrationReferenceControl -Frozen $script:Frozen -Samples @(
            (New-ControlSample cold 0), (New-ControlSample warm 1), (New-ControlSample warm 1)) } | Should -Throw '*duration*'
        $badFrozen = [pscustomobject]@{ cold = [pscustomobject]@{ median = 0 }; warm = [pscustomobject]@{ median = 1 } }
        { Get-MigrationReferenceControl -Frozen $badFrozen -Samples @(
            (New-ControlSample cold 1), (New-ControlSample warm 1), (New-ControlSample warm 1)) } | Should -Throw '*frozen reference median*'
    }

    It 'separates a pass, a regression and an unmeasurable machine' {
        $pass = [pscustomobject]@{ passed = $true }
        $miss = [pscustomobject]@{ passed = $false }
        $good = [pscustomobject]@{ environment_drift = $false }
        $drift = [pscustomobject]@{ environment_drift = $true }
        Get-MigrationBudgetVerdict -Assessment $pass -Control $drift | Should -Be 'passed'
        Get-MigrationBudgetVerdict -Assessment $miss -Control $good | Should -Be 'failed'
        Get-MigrationBudgetVerdict -Assessment $miss -Control $drift | Should -Be 'not_measurable_here'
    }
}

Describe 'Project comparison projection' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'compare-native-analysis-artifacts.ps1')
        . (Join-Path $PSScriptRoot 'compare-native-analysis-policy.ps1')
        . (Join-Path $PSScriptRoot 'compare-native-analysis-project.ps1')
        function New-ProjectSnapshotRoot {
            param([string]$Name, [hashtable]$Files)
            $root = Join-Path $script:AllowedRoot $Name
            foreach ($relative in $Files.Keys) {
                $path = Join-Path $root $relative
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
                [IO.File]::WriteAllText($path, $Files[$relative])
            }
            return $root
        }
    }

    It 'masks clocks, analyzer timings and staging names but nothing else' {
        $reference = New-ProjectSnapshotRoot 'project-projection-a' @{
            'trend.md' = "| 2026-09-16T15:07:19 | 2 |`n"
            'run.log' = "[2026-09-16T15:07:18] CHILD`nARTIFACT: C:\t\dak-pal\{4FA34380-FE6B-44EE-BEE5-14E55F4B1320}`n"
            'pascal-analyzer/P/Status.xml' = "<created>16.09.2026 15:15:13</created><seconds>0,40</seconds><lines_per_second>9250</lines_per_second><warnings>3</warnings>"
            'summary.json' = '{"analyzers":{"fixinsight":{"runs":[{"duration_ms":94,"exit_code":0}]}}}'
        }
        $candidate = New-ProjectSnapshotRoot 'project-projection-b' @{
            'trend.md' = "| 2026-09-16T15:07:20 | 2 |`n"
            'run.log' = "[2026-09-16T15:07:19] CHILD`nARTIFACT: C:\t\dak-pal\{7FF363C8-B637-46F6-99BF-FEEA78C16BE8}`n"
            'pascal-analyzer/P/Status.xml' = "<created>16.09.2026 15:15:17</created><seconds>0,41</seconds><lines_per_second>12333</lines_per_second><warnings>3</warnings>"
            'summary.json' = '{"analyzers":{"fixinsight":{"runs":[{"duration_ms":132,"exit_code":0}]}}}'
        }
        $differences = Compare-MigrationPolicySnapshot -Reference (Get-MigrationProjectSnapshot -Root $reference) `
            -Candidate (Get-MigrationProjectSnapshot -Root $candidate)
        $differences | Should -BeNullOrEmpty
    }

    It 'still reports a changed result next to a masked clock' {
        $reference = New-ProjectSnapshotRoot 'project-projection-c' @{
            'trend.md' = "| 2026-09-16T15:07:19 | 2 |`n"
            'pascal-analyzer/P/Status.xml' = "<created>x</created><warnings>3</warnings>"
            'summary.json' = '{"analyzers":{"fixinsight":{"runs":[{"duration_ms":94,"exit_code":0}]}}}'
        }
        $candidate = New-ProjectSnapshotRoot 'project-projection-d' @{
            'trend.md' = "| 2026-09-16T15:07:20 | 3 |`n"
            'pascal-analyzer/P/Status.xml' = "<created>y</created><warnings>4</warnings>"
            'summary.json' = '{"analyzers":{"fixinsight":{"runs":[{"duration_ms":94,"exit_code":7}]}}}'
        }
        $differences = Compare-MigrationPolicySnapshot -Reference (Get-MigrationProjectSnapshot -Root $reference) `
            -Candidate (Get-MigrationProjectSnapshot -Root $candidate)
        $differences | Should -Be @('differs: pascal-analyzer/P/Status.xml', 'differs: summary.json', 'differs: trend.md')
    }

    It 'masks a staging GUID inside a JSON message but not the message around it' {
        $reference = New-ProjectSnapshotRoot 'project-projection-e' @{
            'summary.json' = '{"errors":["PAL failed (exit=7). Retained PAL staging directory: C:\\t\\{9357E62F-4514-4AF7-A925-82EABFFC445A}"]}'
        }
        $candidate = New-ProjectSnapshotRoot 'project-projection-f' @{
            'summary.json' = '{"errors":["PAL failed (exit=7). Retained PAL staging directory: C:\\t\\{A1910F9B-DBC0-49EC-9C9A-BBCFD6A620E5}"]}'
        }
        $changed = New-ProjectSnapshotRoot 'project-projection-g' @{
            'summary.json' = '{"errors":["PAL failed (exit=8). Retained PAL staging directory: C:\\t\\{A1910F9B-DBC0-49EC-9C9A-BBCFD6A620E5}"]}'
        }
        $referenceSnapshot = Get-MigrationProjectSnapshot -Root $reference
        Compare-MigrationPolicySnapshot -Reference $referenceSnapshot -Candidate (Get-MigrationProjectSnapshot -Root $candidate) |
            Should -BeNullOrEmpty
        Compare-MigrationPolicySnapshot -Reference $referenceSnapshot -Candidate (Get-MigrationProjectSnapshot -Root $changed) |
            Should -Be @('differs: summary.json')
    }

    It 'keeps only the result-deciding stderr lines, once each' {
        $text = "noise`nStatic analysis gate failed (see: C:\x\delta.md)`nStatic analysis gate failed (see: again)`nSummary not found: C:\y`n"
        Get-MigrationProjectStderrMarkers -Text $text | Should -Be @('Static analysis gate failed (see', 'Summary not found')
    }
}
