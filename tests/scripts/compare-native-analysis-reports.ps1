#Requires -Version 7.0
# Development proof helper for the native report replay/verification candidate. Not part of the delivered workflow.
# Dot-sourced by verify-native-analysis-migration.ps1, which supplies the shared process, sample and budget helpers.

# The artifacts owned by T-324: everything the reference replay publishes except the policy stage
# (baseline, delta, history, trend), which T-325 adds to the Full set.
$script:MigrationReportArtifactSets = @{
    T324 = @('external-summary.md', 'fixinsight/fi-findings.jsonl', 'metrics.md', 'pascal-analyzer/pal-findings.jsonl',
        'run.log', 'static-analysis.full.sarif', 'static-analysis.sarif', 'summary.json', 'summary.md', 'triage.md')
}
$script:MigrationReportPolicyArtifacts = @('baseline.json', 'baseline.md', 'delta.json', 'delta.md', 'history.jsonl', 'trend.md')

function Get-MigrationReportSummaryProjection {
    param([string]$Text, [string]$ArtifactSet)
    # summary.json for the T324 set: the policy stage members, the engine identity and the fingerprint
    # that covers that identity are outside the comparison; every other member must match exactly.
    $document = [System.Text.Json.JsonDocument]::Parse($Text)
    try { Assert-MigrationJsonKey -Element $document.RootElement } finally { $document.Dispose() }
    $data = ConvertFrom-Json -InputObject $Text -AsHashtable -NoEnumerate -DateKind String -Depth 100
    if ($ArtifactSet -eq 'T324') {
        foreach ($name in @('baseline', 'delta', 'history', 'trend')) { if ($data.artifacts) { $data.artifacts.Remove($name) } }
        if ($data.status) { $data.status.Remove('policy') }
        if ($data.provenance) { $data.provenance.Remove('dak') }
        if ($data.compatibility) {
            if ($data.compatibility.context) { $data.compatibility.context.Remove('dak') }
            $data.compatibility.Remove('sha256')
        }
    }
    return ConvertTo-Json -InputObject $data -Depth 100 -Compress
}

function Compare-MigrationReportReplay {
    param([string]$Reference, [string]$Candidate, [string]$ArtifactSet)
    $expected = @($script:MigrationReportArtifactSets[$ArtifactSet] | Sort-Object -CaseSensitive)
    if (-not $expected.Count) { throw "Unknown report artifact set: $ArtifactSet" }
    # The manifest helper returns one wrapped array; assign before filtering so the pipeline sees its records.
    $referenceManifest = Get-MigrationArtifactManifest -Root $Reference -ComparisonProfile Replay
    $referenceFiles = @($referenceManifest | Where-Object { $_.path -cin $expected })
    $candidateFiles = Get-MigrationArtifactManifest -Root $Candidate -ComparisonProfile Replay
    if (($referenceFiles.path -join "`n") -cne ($expected -join "`n")) { throw 'Reference replay artifacts are incomplete for the requested set.' }
    # The candidate must publish exactly the owned set: the policy artifacts stay untouched (absent) until T-325.
    if (($candidateFiles.path -join "`n") -cne ($expected -join "`n")) { throw "Candidate artifact inventory differs: $($candidateFiles.path -join ', ')" }
    foreach ($policyArtifact in $script:MigrationReportPolicyArtifacts) {
        if (Test-Path -LiteralPath (Join-Path $Candidate $policyArtifact)) { throw "Candidate touched a policy artifact: $policyArtifact" }
    }
    $differences = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $referenceFiles.Count; $index++) {
        $path = $referenceFiles[$index].path
        if ($path -ceq 'summary.json') {
            $referenceText = Get-MigrationReportSummaryProjection -Text (Get-MigrationUtf8Text ([IO.File]::ReadAllBytes((Join-Path $Reference $path)))) -ArtifactSet $ArtifactSet
            $candidateText = Get-MigrationReportSummaryProjection -Text (Get-MigrationUtf8Text ([IO.File]::ReadAllBytes((Join-Path $Candidate $path)))) -ArtifactSet $ArtifactSet
            if ($referenceText -cne $candidateText) { $differences.Add($path) }
        } elseif ($referenceFiles[$index].comparison_sha256 -cne $candidateFiles[$index].comparison_sha256) { $differences.Add($path) }
    }
    if ($differences.Count) { throw "Report artifacts differ: $($differences -join ', ')" }
    return [pscustomobject]@{ equal = $true; profile = 'Replay'; artifact_set = $ArtifactSet; files = $candidateFiles; reference_files = $referenceFiles }
}

function Get-MigrationReportTreeHash {
    param([string]$Root)
    $files = Get-MigrationArtifactManifest -Root $Root -ComparisonProfile Exact
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes((($files | ForEach-Object { $_.path + ':' + $_.sha256 }) -join "`n"))))
}

function Compare-MigrationReportVerification {
    param([string]$ReferenceStdout, [string]$CandidateStdout, [string]$TreeHashBefore, [string]$TreeHashAfter)
    # The verification prints one JSON line; the reference wrote it through Python's text-mode stdout.
    $reference = (Get-MigrationUtf8Text ([IO.File]::ReadAllBytes($ReferenceStdout))).Replace("`r`n", "`n").TrimEnd("`n")
    $candidate = (Get-MigrationUtf8Text ([IO.File]::ReadAllBytes($CandidateStdout))).Replace("`r`n", "`n").TrimEnd("`n")
    if ($reference -cne $candidate) { throw "Verification output differs: $candidate" }
    if ($TreeHashBefore -cne $TreeHashAfter) { throw 'Verification modified the analysis output.' }
    return [pscustomobject]@{ equal = $true; profile = 'Exact'; stdout = $candidate; read_only = $true }
}

function Invoke-MigrationReportComparison {
    [CmdletBinding()]
    param([string]$EvidenceRoot, [string]$Executable, [string]$ResultRoot, [switch]$Benchmark, [ValidateSet('T324')][string]$ArtifactSet = 'T324')
    . (Join-Path $PSScriptRoot 'compare-native-analysis-artifacts.ps1')
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $executablePath = Resolve-MigrationOutputPath -Path $Executable -Root $repoRoot
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) { throw 'Missing candidate executable.' }
    $scratchRoot = Join-Path $EvidenceRoot 'scratch'
    $batchRoot = Resolve-MigrationOutputPath $ResultRoot (Join-Path $EvidenceRoot 'measurements')
    if (Test-Path -LiteralPath $batchRoot) { throw 'Report comparison evidence already exists.' }
    $budgetPath = Join-Path $EvidenceRoot 'frozen-budgets.json'
    $budgetHash = (Get-FileHash -LiteralPath $budgetPath).Hash
    $budgets = Get-Content -LiteralPath $budgetPath -Raw | ConvertFrom-Json
    $scenarios = @($budgets.scenarios | Where-Object area -EQ Reports)
    if ($scenarios.Count -ne 4) { throw 'Expected four frozen report scenarios.' }
    $childEnvironment = Get-MigrationWorkspaceEnvironment
    $processTemp = Resolve-MigrationOutputPath -Path (Join-Path $scratchRoot 'process-temp') -Root $scratchRoot
    [void][IO.Directory]::CreateDirectory($processTemp)
    $childEnvironment.TEMP = $processTemp
    $childEnvironment.TMP = $processTemp
    [void][IO.Directory]::CreateDirectory($batchRoot)
    $candidateHash = (Get-FileHash -LiteralPath $executablePath).Hash
    $results = foreach ($frozen in $scenarios) {
        $manifest = Get-Content -LiteralPath (Join-Path $EvidenceRoot $frozen.collection_manifest) -Raw | ConvertFrom-Json
        $scenario = @($manifest.scenarios | Where-Object name -CEQ $frozen.name)
        if ($scenario.Count -ne 1) { throw 'Frozen report scenario is missing or duplicated.' }
        $scenario = $scenario[0]
        $verify = $frozen.comparison_profile -eq 'Exact'
        if (-not $verify -and $frozen.comparison_profile -ne 'Replay') { throw "Unsupported report comparison profile: $($frozen.comparison_profile)" }
        if ($scenario.arguments.Count -ne (2 + [int]$verify) -or ($verify -and $scenario.arguments[1] -ne '--verify') -or $scenario.expected_exit -ne 0) { throw 'Frozen report scenario command is not the expected postprocess replay or verification.' }
        [void](Resolve-MigrationOutputPath -Path $scenario.output -Root $scratchRoot)
        [void](Resolve-MigrationOutputPath -Path $scenario.reset_source -Root (Join-Path $EvidenceRoot 'seeds'))
        $referenceSample = Join-Path ([IO.Path]::GetDirectoryName((Join-Path $EvidenceRoot $frozen.measurements))) 'cold-1'
        $scenarioRoot = Resolve-MigrationOutputPath (Join-Path $batchRoot $scenario.name) $batchRoot
        [void][IO.Directory]::CreateDirectory($scenarioRoot)
        $schedule = if ($Benchmark) {
            foreach ($phase in @('cold', 'warmup', 'warm')) {
                $count = switch ($phase) { cold { 5 } warmup { 2 } warm { 10 } }
                for ($index = 1; $index -le $count; $index++) { [pscustomobject]@{ phase = $phase; index = $index } }
            }
        } else { [pscustomobject]@{ phase = 'compare'; index = 1 } }
        $samples = @()
        $records = foreach ($entry in $schedule) {
            $sampleRoot = if ($Benchmark) { Resolve-MigrationOutputPath (Join-Path $scenarioRoot "$($entry.phase)-$($entry.index)") $scenarioRoot } else { $scenarioRoot }
            [void][IO.Directory]::CreateDirectory($sampleRoot)
            Initialize-MigrationSample -Seed $scenario.reset_source -Output $scenario.output -ScratchRoot $scratchRoot
            try {
                $environment = $childEnvironment.Clone()
                foreach ($key in $scenario.environment.PSObject.Properties.Name) { $environment[$key] = $scenario.environment.$key }
                $arguments = @('analyze-report', '--out', $scenario.output)
                if ($verify) { $arguments += '--verify' }
                $treeBefore = if ($verify) { Get-MigrationReportTreeHash -Root $scenario.output } else { '' }
                $process = Invoke-MigrationProcess -Executable $executablePath -Arguments $arguments -WorkingDirectory $scenario.working_directory -Environment $environment -LogPath (Join-Path $sampleRoot 'process')
                if ($process.exit_code -ne 0 -or $process.timed_out -or $process.drain_timed_out) { throw "Native report $(if ($verify) {'verification'} else {'replay'}) failed: $($scenario.name); raw evidence retained." }
                $comparison = if ($verify) {
                    Compare-MigrationReportVerification -ReferenceStdout (Join-Path $referenceSample 'process.stdout') -CandidateStdout (Join-Path $sampleRoot 'process.stdout') -TreeHashBefore $treeBefore -TreeHashAfter (Get-MigrationReportTreeHash -Root $scenario.output)
                } else {
                    Compare-MigrationReportReplay -Reference (Join-Path $referenceSample 'artifacts') -Candidate $scenario.output -ArtifactSet $ArtifactSet
                }
            } finally {
                # The scratch output belongs to this sample only; the next sample starts from the pristine seed.
                [void](Resolve-MigrationOutputPath -Path $scenario.output -Root $scratchRoot)
                if (Test-Path -LiteralPath $scenario.output) { [IO.Directory]::Delete($scenario.output, $true) }
            }
            if ($Benchmark) {
                $process | Add-Member -NotePropertyName phase -NotePropertyValue $entry.phase
                $process | Add-Member -NotePropertyName index -NotePropertyValue $entry.index
                $samples += $process
            }
            $record = [pscustomobject]@{ name = $scenario.name; comparison = $comparison; process = $process; reference_sample = $referenceSample }
            $record | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $sampleRoot 'comparison.json')
            $record
        }
        if ($Benchmark) {
            $assessment = Get-MigrationWorkspaceBudgetResult -Samples $samples -Budget $frozen.budget
            $scenarioResult = [pscustomobject]@{ name = $scenario.name; assessment = $assessment; samples = @($samples); comparisons = @($records) }
            $scenarioResult | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $scenarioRoot 'measurements.json')
            if (-not $assessment.passed) { throw "Report budget exceeded: $($scenario.name): $($assessment.violations -join ', '); raw samples retained." }
            $scenarioResult
        } else { $records }
    }
    if ((Get-FileHash -LiteralPath $executablePath).Hash -ne $candidateHash) { throw 'Candidate executable changed during comparison.' }
    if ((Get-FileHash -LiteralPath $budgetPath).Hash -ne $budgetHash) { throw 'Frozen budget changed during the batch.' }
    $scope = if ($Benchmark) { "Four report scenarios: $ArtifactSet replay artifact equality, exact verification output, frozen cold/warm latency and root-memory budgets." } else { "Report correctness only ($ArtifactSet replay artifacts, exact verification output); no performance acceptance." }
    $result = [pscustomobject]@{ passed = $true; candidate = $executablePath; candidate_sha256 = $candidateHash; budget_sha256 = $budgetHash; artifact_set = $ArtifactSet; scenarios = @($results); scope = $scope }
    $resultFile = if ($Benchmark) { 'benchmark.json' } else { 'comparison.json' }
    $result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $batchRoot $resultFile)
    return $result
}
