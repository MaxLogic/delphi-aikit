#Requires -Version 7.0
# Development proof helper (T-329): the live Project and Unit benchmarks and the all-area benchmark.
# Dot-sourced by verify-native-analysis-migration.ps1 after the project, policy, artifact and report helpers.
#
# Each frozen live scenario runs the candidate with the scenario's recorded environment and no DAK_EXE:
# five cold samples, two discarded warmups and ten warm samples, each from a removed output directory, as
# the T-321 manifest recorded. Every sample's output must equal the first sample's projected snapshot, and
# that snapshot must equal a pinned-reference run made on the same machine. Three reference runs (one cold,
# two warm) also form the D4 reference control, so a slow machine is reported as not measurable instead of
# as a regression. Analyzer time comes from the analyzer run durations in summary.json; the rest of the
# root wall time is reported as DAK overhead.

function Get-MigrationLiveCandidateArguments {
    param([Parameter(Mandatory)]$Scenario)
    $recorded = @($Scenario.arguments)
    if ($Scenario.area -eq 'Project') { return @('analyze', '--project', $Scenario.subject, '--workspace-root', 'project') }
    # analyze-unit.py <unit> [<project context>] --workspace-root project
    $arguments = @('analyze', '--unit', $recorded[1])
    if ($recorded.Count -eq 5) { $arguments += @('--project-context', $recorded[2]) }
    return $arguments + @('--workspace-root', 'project')
}

function Invoke-MigrationLiveSample {
    param([Parameter(Mandatory)]$Scenario, [Parameter(Mandatory)][string]$Tool, [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][hashtable]$Environment, [Parameter(Mandatory)][string]$LogPath, [Parameter(Mandatory)][string]$ScratchRoot)
    $output = Resolve-MigrationOutputPath -Path $Scenario.output -Root $ScratchRoot
    if (Test-Path -LiteralPath $output) { Remove-MigrationPolicyFixture -Root $output -ScratchRoot $ScratchRoot }
    $process = Invoke-MigrationProcess -Executable $Tool -Arguments $Arguments -WorkingDirectory $Scenario.working_directory `
        -Environment $Environment -LogPath $LogPath -TimeoutSeconds 900
    if ($process.timed_out -or $process.drain_timed_out) { throw "Live sample did not complete: $($Scenario.name)" }
    if ($process.exit_code -ne $Scenario.expected_exit) { throw "Live sample exit $($process.exit_code), expected $($Scenario.expected_exit): $($Scenario.name); raw evidence retained." }
    $analyzerMs = 0.0
    $summaryPath = Join-Path $output 'summary.json'
    if (Test-Path -LiteralPath $summaryPath) {
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
        foreach ($analyzer in $summary.analyzers.PSObject.Properties.Value) {
            foreach ($run in @($analyzer.runs)) { if ($null -ne $run.duration_ms) { $analyzerMs += [double]$run.duration_ms } }
        }
    }
    $process | Add-Member -NotePropertyName analyzer_ms -NotePropertyValue $analyzerMs
    $process | Add-Member -NotePropertyName workflow_overhead_ms -NotePropertyValue ($process.elapsed_ms - $analyzerMs)
    $snapshot = if (Test-Path -LiteralPath $output) { Get-MigrationProjectSnapshot -Root $output } else { [ordered]@{} }
    return [pscustomobject]@{ process = $process; snapshot = $snapshot }
}

function Invoke-MigrationLiveBenchmark {
    param([Parameter(Mandatory)][string]$EvidenceRoot, [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$ResultRoot, [Parameter(Mandatory)][ValidateSet('Project', 'Unit')][string]$Area)
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $executablePath = Resolve-MigrationOutputPath -Path $Executable -Root $repoRoot
    $scratchRoot = Join-Path $EvidenceRoot 'scratch'
    $batchRoot = Resolve-MigrationOutputPath $ResultRoot (Join-Path $EvidenceRoot 'measurements')
    if (Test-Path -LiteralPath $batchRoot) { throw 'Live benchmark evidence already exists.' }
    $budgetPath = Join-Path $EvidenceRoot 'frozen-budgets.json'
    $budgetHash = (Get-FileHash -LiteralPath $budgetPath).Hash
    $frozenScenarios = @((Get-Content -LiteralPath $budgetPath -Raw | ConvertFrom-Json).scenarios | Where-Object area -EQ $Area)
    $expected = if ($Area -eq 'Project') { 1 } else { 2 }
    if ($frozenScenarios.Count -ne $expected) { throw "Expected $expected frozen $Area scenarios." }
    $python = (Get-Content -LiteralPath (Join-Path $EvidenceRoot 'corpus/doctor-missing-pal/process.json') -Raw | ConvertFrom-Json).executable
    [void][IO.Directory]::CreateDirectory($batchRoot)
    $candidateHash = (Get-FileHash -LiteralPath $executablePath).Hash
    Assert-MigrationProjectLiveSource -ScratchRoot $scratchRoot

    $results = foreach ($frozen in $frozenScenarios) {
        $manifest = Get-Content -LiteralPath (Join-Path $EvidenceRoot $frozen.collection_manifest) -Raw | ConvertFrom-Json
        $scenario = @($manifest.scenarios | Where-Object name -CEQ $frozen.name)
        if ($scenario.Count -ne 1) { throw "Frozen live scenario is missing or duplicated: $($frozen.name)" }
        $scenario = $scenario[0]
        $scenarioRoot = Resolve-MigrationOutputPath (Join-Path $batchRoot $scenario.name) $batchRoot
        [void][IO.Directory]::CreateDirectory($scenarioRoot)
        $baseEnvironment = Get-MigrationWorkspaceEnvironment
        foreach ($name in @('PA_PATH', 'PA_ARGS', 'FI_SETTINGS', 'FIXINSIGHT_SETTINGS')) { $baseEnvironment[$name] = $null }
        $baseEnvironment.TEMP = Join-Path $scratchRoot 'process-temp'
        $baseEnvironment.TMP = $baseEnvironment.TEMP
        [void][IO.Directory]::CreateDirectory($baseEnvironment.TEMP)
        foreach ($property in $scenario.environment.PSObject.Properties) { $baseEnvironment[$property.Name] = [string]$property.Value }
        $candidateEnvironment = $baseEnvironment.Clone()
        $candidateEnvironment.DAK_EXE = $null
        $candidateArguments = Get-MigrationLiveCandidateArguments -Scenario $scenario

        $samples = @()
        $first = $null
        $differences = [Collections.Generic.List[string]]::new()
        foreach ($phase in @('cold', 'warmup', 'warm')) {
            $count = switch ($phase) { cold { 5 } warmup { 2 } warm { 10 } }
            for ($index = 1; $index -le $count; $index++) {
                $sample = Invoke-MigrationLiveSample -Scenario $scenario -Tool $executablePath -Arguments $candidateArguments `
                    -Environment $candidateEnvironment -LogPath (Join-Path $scenarioRoot "$phase-$index") -ScratchRoot $scratchRoot
                if ($null -eq $first) { $first = $sample.snapshot }
                else {
                    foreach ($difference in @(Compare-MigrationPolicySnapshot -Reference $first -Candidate $sample.snapshot)) {
                        $differences.Add("$phase-${index}: $difference")
                    }
                }
                # Warmups are retained with their phase; the budget statistics discard them.
                $sample.process | Add-Member -NotePropertyName phase -NotePropertyValue $phase
                $sample.process | Add-Member -NotePropertyName index -NotePropertyValue $index
                $samples += $sample.process
            }
        }
        $assessment = Get-MigrationWorkspaceBudgetResult -Samples $samples -Budget $frozen.budget

        # Reference runs on the same machine: output parity with the first one, timing control from all three.
        $controlSamples = @()
        $referenceParity = @()
        foreach ($entry in @(@{ phase = 'cold'; index = 1 }, @{ phase = 'warm'; index = 1 }, @{ phase = 'warm'; index = 2 })) {
            $reference = Invoke-MigrationLiveSample -Scenario $scenario -Tool $python -Arguments @($scenario.arguments) `
                -Environment $baseEnvironment -LogPath (Join-Path $scenarioRoot "reference-control-$($entry.phase)-$($entry.index)") -ScratchRoot $scratchRoot
            if ($entry.phase -eq 'cold') { $referenceParity = @(Compare-MigrationPolicySnapshot -Reference $reference.snapshot -Candidate $first) }
            $reference.process | Add-Member -NotePropertyName phase -NotePropertyValue $entry.phase
            $reference.process | Add-Member -NotePropertyName index -NotePropertyValue $entry.index
            $controlSamples += $reference.process
        }
        $frozenReference = Get-Content -LiteralPath (Join-Path $EvidenceRoot $frozen.measurements) -Raw | ConvertFrom-Json
        $control = Get-MigrationReferenceControl -Samples $controlSamples -Frozen $frozenReference
        $verdict = Get-MigrationBudgetVerdict -Assessment $assessment -Control $control
        $parityPassed = ($differences.Count -eq 0) -and ($referenceParity.Count -eq 0)
        $measured = @($samples | Where-Object phase -NE 'warmup')
        $overhead = @($measured | ForEach-Object workflow_overhead_ms | Sort-Object)
        $analyzer = @($measured | ForEach-Object analyzer_ms | Sort-Object)
        $scenarioResult = [pscustomobject]@{
            name = $scenario.name; area = $Area; verdict = $verdict; parity_passed = $parityPassed
            sample_differences = @($differences); reference_differences = $referenceParity
            assessment = $assessment; reference_control = $control
            analyzer_ms_median = $analyzer[[int][Math]::Floor(($analyzer.Count - 1) / 2)]
            workflow_overhead_ms_median = $overhead[[int][Math]::Floor(($overhead.Count - 1) / 2)]
            samples = $samples; reference_control_samples = $controlSamples
        }
        $scenarioResult | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $scenarioRoot 'measurements.json')
        $scenarioResult
    }
    if ((Get-FileHash -LiteralPath $executablePath).Hash -ne $candidateHash) { throw 'Candidate executable changed during the benchmark.' }
    if ((Get-FileHash -LiteralPath $budgetPath).Hash -ne $budgetHash) { throw 'Frozen budget changed during the benchmark.' }
    $result = [pscustomobject]@{
        passed = (@($results | Where-Object { $_.verdict -ne 'passed' -or -not $_.parity_passed }).Count -eq 0)
        area = $Area; candidate = $executablePath; candidate_sha256 = $candidateHash; budget_sha256 = $budgetHash
        scenarios = @($results)
        scope = "$Area live scenarios: output equality across all samples and with the pinned reference run, frozen cold/warm latency and root-memory budgets with the D4 reference control."
    }
    $result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $batchRoot 'benchmark.json')
    return $result
}

function Invoke-MigrationBenchmarkAll {
    # Every frozen scenario of every area, one area after another. An area that fails or cannot be measured
    # does not stop the others; the overall result passes only when every area passes.
    param([Parameter(Mandatory)][string]$EvidenceRoot, [Parameter(Mandatory)][string]$Executable, [Parameter(Mandatory)][string]$ResultRoot)
    $batchRoot = Resolve-MigrationOutputPath $ResultRoot (Join-Path $EvidenceRoot 'measurements')
    [void][IO.Directory]::CreateDirectory($batchRoot)
    $areas = [ordered]@{}
    foreach ($area in @('Workspace', 'Reports', 'Project', 'Unit')) {
        $areaRoot = Join-Path $batchRoot $area.ToLowerInvariant()
        try {
            $outcome = switch ($area) {
                'Workspace' { Invoke-MigrationWorkspaceComparison -EvidenceRoot $EvidenceRoot -Executable $Executable -ResultRoot $areaRoot -Benchmark }
                'Reports' { Invoke-MigrationReportComparison -EvidenceRoot $EvidenceRoot -Executable $Executable -ResultRoot $areaRoot -Benchmark -ArtifactSet Full }
                default { Invoke-MigrationLiveBenchmark -EvidenceRoot $EvidenceRoot -Executable $Executable -ResultRoot $areaRoot -Area $area }
            }
            $areas[$area] = [pscustomobject]@{ passed = [bool]$outcome.passed; error = $null; result = (Join-Path $areaRoot 'benchmark.json') }
        } catch {
            $areas[$area] = [pscustomobject]@{ passed = $false; error = $_.Exception.Message; result = $areaRoot }
        }
    }
    $result = [pscustomobject]@{
        passed = (@($areas.Values | Where-Object { -not $_.passed }).Count -eq 0)
        candidate = $Executable; candidate_sha256 = (Get-FileHash -LiteralPath $Executable).Hash
        areas = $areas
        scope = 'All frozen T-321 scenarios with five cold and ten warm samples each; parity, budgets and the reference control per area.'
    }
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $batchRoot 'benchmark-all.json')
    return $result
}
