#Requires -Version 7.0
# Development proof helper for the native unit workflow (T-327). Not part of the delivered workflow.
# Dot-sourced by verify-native-analysis-migration.ps1. Built on compare-native-analysis-project.ps1:
# the same snapshot projection, stderr markers and live-run protocol.
#
# Deterministic scenarios use the DUnitX executable as PALCMD, run once through the pinned
# analyze-unit.py with the pinned reference DAK and once through the candidate's `analyze --unit`
# launched from the same environment with no translated switches. The two pinned live scenarios run
# the installed Pascal Analyzer on the read-only RemoveWithApplyFixture snapshot, with and without the
# project context.

function New-MigrationUnitFixture {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RepoRoot)
    $project = Join-Path $Root 'project'
    $units = Join-Path $project 'units'
    [void][IO.Directory]::CreateDirectory($units)
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests/fixtures/Sample.dproj') -Destination (Join-Path $project 'Sample.dproj')
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests/fixtures/Sample.dpr') -Destination (Join-Path $project 'Sample.dpr')
    $unit = Join-Path $units 'UnitOne.pas'
    [IO.File]::WriteAllText($unit, "unit UnitOne;`r`ninterface`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $project 'dak.ini'),
        "[Workspace]`r`nRoot=project`r`n[AnalysisPolicy]`r`nGateOwnership=repository;project`r`nProjectRoots=.`r`n",
        [Text.Encoding]::ASCII)
    return [pscustomobject]@{
        root = $Root; project_dir = $project; project = Join-Path $project 'Sample.dproj'; unit = $unit
        # analyze-unit.py: <unit dir>/.dak/_unit/<unit stem>
        out = Join-Path $units '.dak\_unit\UnitOne'
    }
}

function Invoke-MigrationUnitComparison {
    [CmdletBinding()]
    param([string]$EvidenceRoot, [string]$Executable, [string]$ResultRoot, [string[]]$ScenarioName)
    . (Join-Path $PSScriptRoot 'compare-native-analysis-artifacts.ps1')
    . (Join-Path $PSScriptRoot 'compare-native-analysis-policy.ps1')
    . (Join-Path $PSScriptRoot 'compare-native-analysis-project.ps1')
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $executablePath = Resolve-MigrationOutputPath -Path $Executable -Root $repoRoot
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) { throw 'Missing candidate executable.' }
    $batchRoot = Resolve-MigrationOutputPath $ResultRoot (Join-Path $EvidenceRoot 'measurements')
    if (Test-Path -LiteralPath $batchRoot) { throw 'Unit comparison evidence already exists.' }
    $analyzeUnitPy = Join-Path $EvidenceRoot 'python-reference/agentskills/dak-static-analysis/analyze-unit.py'
    if (-not (Test-Path -LiteralPath $analyzeUnitPy -PathType Leaf)) { throw 'Missing pinned analyze-unit.py.' }
    $referenceDak = Join-Path $EvidenceRoot 'tools/reference-release-v2/DelphiAIKit.exe'
    if (-not (Test-Path -LiteralPath $referenceDak -PathType Leaf)) { throw 'Missing pinned reference DAK.' }
    $python = (Get-Content -LiteralPath (Join-Path $EvidenceRoot 'corpus/doctor-missing-pal/process.json') -Raw |
        ConvertFrom-Json).executable
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Missing pinned Python interpreter.' }
    $palStandIn = Join-Path $repoRoot 'tests/DelphiAIKit.Tests.exe'
    if (-not (Test-Path -LiteralPath $palStandIn -PathType Leaf)) { throw 'Missing the PALCMD process fixture (tests/DelphiAIKit.Tests.exe).' }
    $scratchRoot = Join-Path $EvidenceRoot 'scratch'
    [void][IO.Directory]::CreateDirectory($batchRoot)
    $hashes = [ordered]@{
        candidate = (Get-FileHash -LiteralPath $executablePath).Hash
        reference_dak = (Get-FileHash -LiteralPath $referenceDak).Hash
        palcmd_fixture = (Get-FileHash -LiteralPath $palStandIn).Hash
    }

    $scenarios = @(
        [pscustomobject]@{ name = 'unit-standalone-success'; context = $false; environment = @{ DAK_TEST_PAL_EXIT = '0' } }
        [pscustomobject]@{ name = 'unit-context-success'; context = $true; environment = @{ DAK_TEST_PAL_EXIT = '0' } }
        [pscustomobject]@{ name = 'unit-context-analyzer-failed'; context = $true; environment = @{ DAK_TEST_PAL_EXIT = '7' } }
        [pscustomobject]@{ name = 'unit-no-summary'; context = $false
            environment = @{ DAK_TEST_PAL_EXIT = '0'; DAK_WRITE_SUMMARY = 'false' } }
    )
    $live = @((Get-Content -LiteralPath (Join-Path $EvidenceRoot 'unit-scenarios-v2.json') -Raw | ConvertFrom-Json).scenarios)
    foreach ($name in @('live-unit-context', 'live-unit-standalone')) {
        $entry = @($live | Where-Object name -CEQ $name)
        if ($entry.Count -ne 1) { throw "Expected the pinned $name scenario." }
        $scenarios += [pscustomobject]@{ name = $name; live = $entry[0] }
    }
    if ($ScenarioName) { $scenarios = @($scenarios | Where-Object { $_.name -cin $ScenarioName }) }
    if (-not $scenarios.Count) { throw 'No unit scenario selected.' }

    $results = foreach ($scenario in $scenarios) {
        $scenarioRoot = Resolve-MigrationOutputPath (Join-Path $batchRoot $scenario.name) $batchRoot
        [void][IO.Directory]::CreateDirectory($scenarioRoot)
        $engines = [ordered]@{}
        foreach ($engine in @('reference', 'candidate')) {
            if ($scenario.live) {
                # analyze-unit.py <unit> [<project context>] --workspace-root project
                $liveArguments = @($scenario.live.arguments)
                $candidateArguments = @('analyze', '--unit', $liveArguments[1])
                if ($liveArguments.Count -eq 5) { $candidateArguments += @('--project-context', $liveArguments[2]) }
                $candidateArguments += @('--workspace-root', 'project')
                $engines[$engine] = Invoke-MigrationProjectLiveRun -Scenario $scenario.live -Engine $engine `
                    -ScenarioRoot $scenarioRoot -ScratchRoot $scratchRoot -EvidenceRoot $EvidenceRoot -RepoRoot $repoRoot `
                    -Python $python -Candidate $executablePath -CandidateArguments $candidateArguments
                continue
            }
            $fixtureRoot = Resolve-MigrationOutputPath (Join-Path $scratchRoot ('unit/' + $scenario.name)) $scratchRoot
            Remove-MigrationPolicyFixture -Root $fixtureRoot -ScratchRoot $scratchRoot
            [void][IO.Directory]::CreateDirectory($fixtureRoot)
            try {
                $fixture = New-MigrationUnitFixture -Root $fixtureRoot -RepoRoot $repoRoot
                $environment = Get-MigrationWorkspaceEnvironment
                foreach ($name in @('PA_ARGS', 'FI_SETTINGS', 'FIXINSIGHT_SETTINGS')) { $environment[$name] = $null }
                $environment.PA_PATH = $palStandIn
                $environment.DAK_DELPHI = '23.0'
                $environment.DAK_PASCAL_ANALYZER = 'true'
                foreach ($name in @('DAK_GATE', 'DAK_CI', 'DAK_UPDATE_BASELINE')) { $environment[$name] = '0' }
                foreach ($name in $scenario.environment.Keys) { $environment[$name] = $scenario.environment[$name] }
                if ($engine -eq 'reference') {
                    $environment.DAK_EXE = $referenceDak
                    $tool = $python
                    $arguments = @($analyzeUnitPy, $fixture.unit)
                    if ($scenario.context) { $arguments += $fixture.project }
                    $arguments += @('--workspace-root', 'project')
                } else {
                    $tool = $executablePath
                    $arguments = @('analyze', '--unit', $fixture.unit)
                    if ($scenario.context) { $arguments += @('--project-context', $fixture.project) }
                    $arguments += @('--workspace-root', 'project')
                }
                $logPath = Join-Path $scenarioRoot $engine
                $process = Invoke-MigrationProcess -Executable $tool -Arguments $arguments `
                    -WorkingDirectory $fixture.project_dir -Environment $environment -LogPath $logPath -TimeoutSeconds 600
                if ($process.timed_out -or $process.drain_timed_out) { throw "Unit run did not complete: $($scenario.name)/$engine" }
                $stderr = if (Test-Path -LiteralPath ($logPath + '.stderr')) { Get-Content -LiteralPath ($logPath + '.stderr') -Raw } else { '' }
                $snapshot = if (Test-Path -LiteralPath $fixture.out) { Get-MigrationProjectSnapshot -Root $fixture.out } else { [ordered]@{} }
                $engines[$engine] = [pscustomobject]@{
                    exit = $process.exit_code
                    markers = @(Get-MigrationProjectStderrMarkers -Text $stderr)
                    snapshot = $snapshot
                }
            } finally {
                Remove-MigrationPolicyFixture -Root $fixtureRoot -ScratchRoot $scratchRoot
            }
        }
        $differences = Compare-MigrationPolicySnapshot -Reference $engines.reference.snapshot -Candidate $engines.candidate.snapshot
        $record = [pscustomobject]@{
            name = $scenario.name
            reference_exit = $engines.reference.exit
            candidate_exit = $engines.candidate.exit
            exits_equal = ($engines.reference.exit -eq $engines.candidate.exit)
            reference_markers = $engines.reference.markers
            candidate_markers = $engines.candidate.markers
            markers_equal = (($engines.reference.markers -join '|') -ceq ($engines.candidate.markers -join '|'))
            artifact_differences = $differences
            artifacts = @($engines.reference.snapshot.Keys)
        }
        $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $scenarioRoot 'comparison.json')
        if ($differences.Count) {
            foreach ($engine in @('reference', 'candidate')) {
                $snapshotRoot = Join-Path $scenarioRoot "$engine-snapshot"
                [void][IO.Directory]::CreateDirectory($snapshotRoot)
                foreach ($name in $engines[$engine].snapshot.Keys) {
                    [IO.File]::WriteAllText((Join-Path $snapshotRoot ($name -replace '/', '__')), [string]$engines[$engine].snapshot[$name])
                }
            }
        }
        $record
    }
    if ((Get-FileHash -LiteralPath $executablePath).Hash -ne $hashes.candidate) { throw 'Candidate executable changed during comparison.' }
    $failed = @($results | Where-Object { -not $_.exits_equal -or -not $_.markers_equal -or $_.artifact_differences.Count })
    $result = [pscustomobject]@{
        passed = ($failed.Count -eq 0); candidate = $executablePath; hashes = $hashes
        reference = $analyzeUnitPy; python = $python; scenarios = @($results)
        scope = ('Unit workflow outcomes compared run for run against the pinned analyze-unit.py and reference DAK, ' +
                 'with the candidate launched from the legacy environment alone; live scenarios use the installed ' +
                 'Pascal Analyzer on the pinned snapshot. Exclusions as in the Project comparison. Invalid input is ' +
                 'not compared: analyze-unit.py returned 2 from its own pre-check, DAK keeps its exit 3 contract.')
    }
    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $batchRoot 'comparison.json')
    if ($failed.Count) {
        throw ("Unit comparison differs: " + (($failed | ForEach-Object {
            "$($_.name) exit $($_.reference_exit)/$($_.candidate_exit) markers=$($_.markers_equal) artifacts: $($_.artifact_differences -join ', ')"
        }) -join '; '))
    }
    return $result
}
