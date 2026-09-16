#Requires -Version 7.0
# Development proof helper for the native project workflow (T-326). Not part of the delivered workflow.
# Dot-sourced by verify-native-analysis-migration.ps1, which supplies the shared process helpers, and
# reuses the snapshot and projection rules of compare-native-analysis-policy.ps1.
#
# Each scenario builds one deterministic project fixture whose FixInsight is the DUnitX executable's
# process fixture, then runs it twice at the same path: through the pinned analyze.py with the pinned
# reference DAK, and through the candidate as `analyze --project` launched with the same environment.
# The candidate gets no translated switches, so the comparison also proves that DAK reads the legacy
# environment itself (D2). The whole output directory, the exit code and the decisive stderr lines are
# compared.

# A live run writes wall-clock times the replay corpus pinned: ISO timestamps inside Markdown and log
# text, and each analyzer run's duration_ms. Nothing else is treated as volatile.
$script:MigrationProjectTimestamp = [regex]'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?'
# Pascal Analyzer stamps each XML report with its own local creation time, and DAK stages PAL output
# in a fresh GUID-named directory per run. Both are per-run identities, not results.
$script:MigrationProjectPalCreated = [regex]'<created>[^<]*</created>'
# Status.xml also records how long the analyzer took and its resulting throughput.
$script:MigrationProjectPalTiming = [regex]'<(lines_per_second|seconds)>[^<]*</\1>'
$script:MigrationProjectGuid = [regex]'\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'
$script:MigrationProjectStderrMarkers = @(
    'Static analysis gate failed (see: ',
    'Post-processing failed after successful analyzer: ',
    'Post-processing failed after analyzer failure: ',
    'Summary not found: ')

function New-MigrationProjectFixture {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$FixInsightExecutable)
    $project = Join-Path $Root 'project'
    [void][IO.Directory]::CreateDirectory($project)
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests/fixtures/Sample.dproj') -Destination (Join-Path $project 'Sample.dproj')
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'tests/fixtures/Sample.dpr') -Destination (Join-Path $project 'Sample.dpr')
    [IO.File]::WriteAllText((Join-Path $project 'dak.ini'),
        "[Workspace]`r`nRoot=project`r`n[FixInsightCL]`r`nPath=$FixInsightExecutable`r`n" +
        "[AnalysisPolicy]`r`nGateOwnership=repository;project`r`nProjectRoots=.`r`n",
        [Text.Encoding]::ASCII)
    return [pscustomobject]@{
        root = $Root; project_dir = $project
        project = Join-Path $project 'Sample.dproj'
        out = Join-Path $project '.dak\Sample'
    }
}

# Only the lines that decide or explain a run's result; everything else on stderr is diagnostic noise
# whose wording belongs to each engine.
function Get-MigrationProjectStderrMarkers {
    param([string]$Text)
    $found = foreach ($line in [regex]::Split([string]$Text, '\r?\n')) {
        foreach ($marker in $script:MigrationProjectStderrMarkers) {
            if ($line.Contains($marker)) { $marker.TrimEnd(' ', ':', '(') }
        }
    }
    return @($found | Sort-Object -Unique)
}

function Clear-MigrationProjectDuration {
    param($Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($key in $Value.Keys) {
            if ($key -ceq 'duration_ms') { $out[$key] = '<duration>'; continue }
            $out[$key] = Clear-MigrationProjectDuration -Value $Value[$key]
        }
        return $out
    }
    if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { Clear-MigrationProjectDuration -Value $_ })
    }
    # A retained PAL staging directory is named after a fresh GUID, also inside error messages.
    if ($Value -is [string]) { return $script:MigrationProjectGuid.Replace($Value, '{<staging>}') }
    return $Value
}

function Get-MigrationProjectSnapshot {
    param([Parameter(Mandatory)][string]$Root)
    $snapshot = Get-MigrationPolicySnapshot -Root $Root
    foreach ($name in @($snapshot.Keys)) {
        if ($name -ceq 'postprocessor-error.txt') {
            # The reference writes a Python traceback; its presence is the contract, not its text.
            $snapshot[$name] = '<diagnostic>'
        } elseif ($name -cmatch '\.json$') {
            $snapshot[$name] = ConvertTo-Json -Depth 100 -Compress -InputObject (Clear-MigrationProjectDuration -Value (
                ConvertFrom-Json -InputObject ([string]$snapshot[$name]) -AsHashtable -NoEnumerate -DateKind String -Depth 100))
        } elseif ($name -cnotmatch '\.(jsonl|sarif)$') {
            $text = $script:MigrationProjectTimestamp.Replace([string]$snapshot[$name], '<clock>')
            $text = $script:MigrationProjectPalCreated.Replace($text, '<created><clock></created>')
            $text = $script:MigrationProjectPalTiming.Replace($text, '<$1><clock></$1>')
            $snapshot[$name] = $script:MigrationProjectGuid.Replace($text, '{<staging>}')
        }
    }
    return $snapshot
}

function Assert-MigrationProjectLiveSource {
    param([Parameter(Mandatory)][string]$ScratchRoot)
    $origin = Get-Content -LiteralPath (Join-Path $ScratchRoot 'live-project/snapshot-origin.json') -Raw | ConvertFrom-Json
    foreach ($file in $origin.files) {
        [void](Resolve-MigrationOutputPath -Path $file.snapshot -Root $ScratchRoot)
        if ((Get-FileHash -LiteralPath $file.snapshot).Hash -ne $file.sha256) { throw "Live source snapshot changed: $($file.snapshot)" }
    }
}

function Invoke-MigrationProjectLiveRun {
    param([Parameter(Mandatory)]$Scenario, [Parameter(Mandatory)][string]$Engine,
        [Parameter(Mandatory)][string]$ScenarioRoot, [Parameter(Mandatory)][string]$ScratchRoot,
        [Parameter(Mandatory)][string]$EvidenceRoot, [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Python, [Parameter(Mandatory)][string]$Candidate,
        [string[]]$CandidateArguments)
    Assert-MigrationProjectLiveSource -ScratchRoot $ScratchRoot
    $output = Resolve-MigrationOutputPath -Path $Scenario.output -Root $ScratchRoot
    if (Test-Path -LiteralPath $output) { Remove-MigrationPolicyFixture -Root $output -ScratchRoot $ScratchRoot }
    $environment = Get-MigrationWorkspaceEnvironment
    foreach ($name in @('PA_PATH', 'PA_ARGS', 'FI_SETTINGS', 'FIXINSIGHT_SETTINGS')) { $environment[$name] = $null }
    $environment.TEMP = Join-Path $ScratchRoot 'process-temp'
    $environment.TMP = $environment.TEMP
    [void][IO.Directory]::CreateDirectory($environment.TEMP)
    foreach ($property in $Scenario.environment.PSObject.Properties) { $environment[$property.Name] = [string]$property.Value }
    if ($Engine -eq 'reference') {
        $tool = $Python
        $arguments = @($Scenario.arguments)
    } else {
        # The candidate gets the scenario's environment and no translated switches.
        $environment.DAK_EXE = $null
        $tool = $Candidate
        $arguments = if ($CandidateArguments) { @($CandidateArguments) }
            else { @('analyze', '--project', $Scenario.subject, '--workspace-root', 'project') }
    }
    $logPath = Join-Path $ScenarioRoot $Engine
    $process = Invoke-MigrationProcess -Executable $tool -Arguments $arguments -WorkingDirectory $Scenario.working_directory `
        -Environment $environment -LogPath $logPath -TimeoutSeconds 900
    if ($process.timed_out -or $process.drain_timed_out) { throw "Live project run did not complete: $Engine" }
    $stderr = if (Test-Path -LiteralPath ($logPath + '.stderr')) { Get-Content -LiteralPath ($logPath + '.stderr') -Raw } else { '' }
    $snapshot = if (Test-Path -LiteralPath $output) { Get-MigrationProjectSnapshot -Root $output } else { [ordered]@{} }
    # Keep the raw live output; the next engine's run starts from an empty directory.
    if (Test-Path -LiteralPath $output) { Move-Item -LiteralPath $output -Destination (Join-Path $ScenarioRoot "$Engine-output") }
    return [pscustomobject]@{
        exit = $process.exit_code
        markers = @(Get-MigrationProjectStderrMarkers -Text $stderr)
        snapshot = $snapshot
    }
}

function Invoke-MigrationProjectComparison {
    [CmdletBinding()]
    param([string]$EvidenceRoot, [string]$Executable, [string]$ResultRoot, [string[]]$ScenarioName)
    . (Join-Path $PSScriptRoot 'compare-native-analysis-artifacts.ps1')
    . (Join-Path $PSScriptRoot 'compare-native-analysis-policy.ps1')
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $executablePath = Resolve-MigrationOutputPath -Path $Executable -Root $repoRoot
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) { throw 'Missing candidate executable.' }
    $batchRoot = Resolve-MigrationOutputPath $ResultRoot (Join-Path $EvidenceRoot 'measurements')
    if (Test-Path -LiteralPath $batchRoot) { throw 'Project comparison evidence already exists.' }
    $analyzePy = Join-Path $EvidenceRoot 'python-reference/agentskills/dak-static-analysis/analyze.py'
    if (-not (Test-Path -LiteralPath $analyzePy -PathType Leaf)) { throw 'Missing pinned analyze.py.' }
    $referenceDak = Join-Path $EvidenceRoot 'tools/reference-release-v2/DelphiAIKit.exe'
    if (-not (Test-Path -LiteralPath $referenceDak -PathType Leaf)) { throw 'Missing pinned reference DAK.' }
    $python = (Get-Content -LiteralPath (Join-Path $EvidenceRoot 'corpus/doctor-missing-pal/process.json') -Raw |
        ConvertFrom-Json).executable
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Missing pinned Python interpreter.' }
    $fixInsight = Join-Path $repoRoot 'tests/DelphiAIKit.Tests.exe'
    if (-not (Test-Path -LiteralPath $fixInsight -PathType Leaf)) { throw 'Missing the FixInsight process fixture (tests/DelphiAIKit.Tests.exe).' }
    $scratchRoot = Join-Path $EvidenceRoot 'scratch'
    [void][IO.Directory]::CreateDirectory($batchRoot)
    $hashes = [ordered]@{
        candidate = (Get-FileHash -LiteralPath $executablePath).Hash
        reference_dak = (Get-FileHash -LiteralPath $referenceDak).Hash
        fixinsight_fixture = (Get-FileHash -LiteralPath $fixInsight).Hash
    }

    $scenarios = @(
        [pscustomobject]@{ name = 'project-success'; environment = @{ DAK_TEST_FIXINSIGHT_EXIT = '0' } }
        [pscustomobject]@{ name = 'project-analyzer-failed'; environment = @{ DAK_TEST_FIXINSIGHT_EXIT = '7' } }
        [pscustomobject]@{ name = 'project-gate-failed'
            environment = @{ DAK_TEST_FIXINSIGHT_EXIT = '0'; DAK_TEST_FIXINSIGHT_FILE = 'Z:\nowhere\Absent.pas'; DAK_GATE = '1' } }
        [pscustomobject]@{ name = 'project-finalization-failed'
            environment = @{ DAK_TEST_FIXINSIGHT_EXIT = '0'; DAK_TEST_FIXINSIGHT_MALFORMED = '1' } }
        [pscustomobject]@{ name = 'project-no-summary'
            environment = @{ DAK_TEST_FIXINSIGHT_EXIT = '0'; DAK_WRITE_SUMMARY = 'false' } }
    )
    # The pinned live scenario runs the installed FixInsight and Pascal Analyzer on a read-only source
    # snapshot. Both engines run today on the same machine, so analyzer version drift since the freeze
    # affects them equally; the source snapshot is hash-checked first.
    $live = @((Get-Content -LiteralPath (Join-Path $EvidenceRoot 'project-scenarios.json') -Raw | ConvertFrom-Json).scenarios |
        Where-Object name -CEQ 'live-project')
    if ($live.Count -ne 1) { throw 'Expected the pinned live-project scenario.' }
    $scenarios += [pscustomobject]@{ name = 'live-project'; live = $live[0] }
    if ($ScenarioName) { $scenarios = @($scenarios | Where-Object { $_.name -cin $ScenarioName }) }
    if (-not $scenarios.Count) { throw 'No project scenario selected.' }

    $results = foreach ($scenario in $scenarios) {
        $scenarioRoot = Resolve-MigrationOutputPath (Join-Path $batchRoot $scenario.name) $batchRoot
        [void][IO.Directory]::CreateDirectory($scenarioRoot)
        $engines = [ordered]@{}
        foreach ($engine in @('reference', 'candidate')) {
            if ($scenario.live) {
                $engines[$engine] = Invoke-MigrationProjectLiveRun -Scenario $scenario.live -Engine $engine `
                    -ScenarioRoot $scenarioRoot -ScratchRoot $scratchRoot -EvidenceRoot $EvidenceRoot -RepoRoot $repoRoot `
                    -Python $python -Candidate $executablePath
                continue
            }
            # Both engines use the same path so the absolute paths inside the artifacts agree.
            $fixtureRoot = Resolve-MigrationOutputPath (Join-Path $scratchRoot ('project/' + $scenario.name)) $scratchRoot
            Remove-MigrationPolicyFixture -Root $fixtureRoot -ScratchRoot $scratchRoot
            [void][IO.Directory]::CreateDirectory($fixtureRoot)
            try {
                $fixture = New-MigrationProjectFixture -Root $fixtureRoot -RepoRoot $repoRoot -FixInsightExecutable $fixInsight
                $environment = Get-MigrationWorkspaceEnvironment
                # DAK now reads these itself, so an ambient value would leak into one engine only.
                foreach ($name in @('PA_PATH', 'PA_ARGS', 'FI_SETTINGS', 'FIXINSIGHT_SETTINGS')) { $environment[$name] = $null }
                $environment.DAK_PLATFORM = 'Win64'
                $environment.DAK_CONFIG = 'Debug'
                $environment.DAK_DELPHI = '23.0'
                $environment.DAK_FIXINSIGHT = 'true'
                $environment.DAK_PASCAL_ANALYZER = 'false'
                $environment.DAK_FI_FORMATS = 'txt'
                foreach ($name in @('DAK_GATE', 'DAK_CI', 'DAK_UPDATE_BASELINE')) { $environment[$name] = '0' }
                foreach ($name in $scenario.environment.Keys) { $environment[$name] = $scenario.environment[$name] }
                if ($engine -eq 'reference') {
                    $environment.DAK_EXE = $referenceDak
                    $tool = $python
                    $arguments = @($analyzePy, $fixture.project, '--workspace-root', 'project')
                } else {
                    $tool = $executablePath
                    $arguments = @('analyze', '--project', $fixture.project, '--workspace-root', 'project')
                }
                $logPath = Join-Path $scenarioRoot $engine
                $process = Invoke-MigrationProcess -Executable $tool -Arguments $arguments `
                    -WorkingDirectory $fixture.project_dir -Environment $environment -LogPath $logPath -TimeoutSeconds 600
                if ($process.timed_out -or $process.drain_timed_out) { throw "Project run did not complete: $($scenario.name)/$engine" }
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
        $exitsEqual = $engines.reference.exit -eq $engines.candidate.exit
        $markersEqual = ($engines.reference.markers -join '|') -ceq ($engines.candidate.markers -join '|')
        $record = [pscustomobject]@{
            name = $scenario.name
            reference_exit = $engines.reference.exit
            candidate_exit = $engines.candidate.exit
            exits_equal = $exitsEqual
            reference_markers = $engines.reference.markers
            candidate_markers = $engines.candidate.markers
            markers_equal = $markersEqual
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
        reference = $analyzePy; python = $python; scenarios = @($results)
        scope = ('Deterministic project workflow outcomes compared run for run against the pinned analyze.py ' +
                 'and reference DAK on identical fresh fixtures, with the candidate launched from the legacy ' +
                 'environment alone. Clocks, engine identity, the interpreter version, analyzer log durations ' +
                 'and the postprocessor traceback text are excluded. No performance acceptance.')
    }
    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $batchRoot 'comparison.json')
    if ($failed.Count) {
        throw ("Project comparison differs: " + (($failed | ForEach-Object {
            "$($_.name) exit $($_.reference_exit)/$($_.candidate_exit) markers=$($_.markers_equal) artifacts: $($_.artifact_differences -join ', ')"
        }) -join '; '))
    }
    return $result
}
