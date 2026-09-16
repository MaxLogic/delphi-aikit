#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Baseline', 'Compare', 'Coverage', 'NoPython', 'Benchmark', 'Delivery')]
    [string]$Mode = 'Baseline',
    [string]$Area = 'All',
    [string]$Manifest,
    [string]$CandidateExecutable,
    # Reports comparison scope: Full is the whole published set; T324 excludes the policy stage.
    [ValidateSet('T324', 'Full')][string]$ArtifactSet = 'Full'
)

function Resolve-MigrationOutputPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Output is outside the owned root: $fullPath"
    }
    $ancestor = $fullPath
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor) {
            $item = Get-Item -LiteralPath $ancestor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Output crosses a reparse point: $ancestor"
            }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $fullPath
}

function Get-MigrationStatistic {
    [CmdletBinding()]
    param([AllowEmptyCollection()][double[]]$Values)
    if ($Values.Count -eq 0) { throw 'At least one sample is required.' }
    foreach ($value in $Values) {
        if (-not [double]::IsFinite($value)) { throw 'Every sample must be finite.' }
    }
    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    $median = $sorted[$middle]
    if ($sorted.Count % 2 -eq 0) { $median = ($sorted[$middle - 1] + $median) / 2 }
    return [pscustomobject]@{
        count = $sorted.Count
        median = $median
        p95 = $sorted[[int][Math]::Ceiling($sorted.Count * 0.95) - 1]
        min = $sorted[0]
        max = $sorted[-1]
    }
}

function Invoke-MigrationProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [hashtable]$Environment = @{},
        [Parameter(Mandatory)][string]$LogPath,
        [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300
    )
    foreach ($extension in @('.stdout', '.stderr', '.json')) {
        if (Test-Path -LiteralPath ($LogPath + $extension)) { throw "Process evidence already exists: $LogPath$extension" }
    }
    $startInfo = [Diagnostics.ProcessStartInfo]::new($Executable)
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    foreach ($key in $Environment.Keys) {
        if ($null -eq $Environment[$key]) { [void]$startInfo.Environment.Remove($key) }
        else { $startInfo.Environment[$key] = [string]$Environment[$key] }
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $peakWorkingSet = 0L
    $timedOut = $false
    $started = $false
    try {
        if (-not $process.Start()) { throw "Could not start $Executable" }
        $started = $true
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        while (-not $process.HasExited) {
            $process.Refresh()
            $peakWorkingSet = [Math]::Max($peakWorkingSet, $process.PeakWorkingSet64)
            if ($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                $timedOut = $true
                $process.Kill($true)
                break
            }
            [void]$process.WaitForExit(10)
        }
        if (-not $process.WaitForExit(1000)) { throw 'Process did not exit after termination; evidence is incomplete.' }
        $processElapsed = $watch.Elapsed.TotalMilliseconds
        $remainingMs = [int][Math]::Max(1, $TimeoutSeconds * 1000 - $processElapsed)
        $drained = [Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($stdout, $stderr)).Wait($remainingMs)
        $watch.Stop()
        $record = [ordered]@{
            executable = $Executable
            arguments = $Arguments
            working_directory = $WorkingDirectory
            exit_code = $process.ExitCode
            timed_out = $timedOut
            drain_timed_out = -not $drained
            elapsed_ms = $processElapsed
            collection_elapsed_ms = $watch.Elapsed.TotalMilliseconds
            peak_working_set_bytes = $peakWorkingSet
            memory_scope = 'Sampled OS peak working set of the measured root process; excludes child tools.'
        }
        $outText = if ($stdout.IsCompletedSuccessfully) { $stdout.GetAwaiter().GetResult() } else { '[Incomplete stream: drain timed out.]' }
        $errText = if ($stderr.IsCompletedSuccessfully) { $stderr.GetAwaiter().GetResult() } else { '[Incomplete stream: drain timed out.]' }
        [IO.File]::WriteAllText($LogPath + '.stdout', $outText)
        [IO.File]::WriteAllText($LogPath + '.stderr', $errText)
        [IO.File]::WriteAllText($LogPath + '.json', ($record | ConvertTo-Json -Depth 6))
        return [pscustomobject]$record
    }
    finally {
        if ($started -and -not $process.HasExited) { $process.Kill($true) }
        $process.Dispose()
    }
}

function Assert-MigrationScenario {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Scenarios)
    if ($Scenarios.Count -eq 0) { throw 'Scenario selection is empty.' }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($scenario in $Scenarios) {
        foreach ($field in @('name', 'executable', 'arguments', 'working_directory', 'area', 'reset_source', 'output', 'expected_exit', 'environment')) {
            if (-not $scenario.Contains($field)) { throw "Scenario is missing $field." }
        }
        if ($scenario.name -notmatch '^[a-z0-9-]+$' -or -not $names.Add($scenario.name)) {
            throw "Invalid or duplicate scenario name: $($scenario.name)"
        }
        foreach ($key in $scenario.environment.Keys) {
            if ($key -in @('DAK_MAXTDB_FIXTURE', 'DAK_TEST_OUTPUT_ROOT')) {
                throw "Manifest cannot override protected environment variable: $key"
            }
        }
    }
}

function Initialize-MigrationSample {
    [CmdletBinding()]
    param([string]$Seed, [string]$Output, [string]$ScratchRoot)
    [void](Resolve-MigrationOutputPath -Path $Output -Root $ScratchRoot)
    if (Test-Path -LiteralPath $Output) { throw "Scratch output already exists; retain or inspect it before another run: $Output" }
    $files = @(Get-ChildItem -LiteralPath $Seed -Recurse -Force)
    foreach ($file in $files) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Seed contains a reparse point: $($file.FullName)" }
    }
    [void][IO.Directory]::CreateDirectory($Output)
    foreach ($file in $files | Where-Object { -not $_.PSIsContainer }) {
        $relative = [IO.Path]::GetRelativePath($Seed, $file.FullName)
        $destination = Resolve-MigrationOutputPath -Path (Join-Path $Output $relative) -Root $ScratchRoot
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
}

function Get-MigrationRetainedSampleSummary {
    param([object[]]$Samples)
    if ($Samples.Count -ne 17) { throw 'Expected 17 samples: five cold, two warmups, ten warm.' }
    $identities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($sample in $Samples) {
        $limit = switch ($sample.phase) { cold {5} warmup {2} warm {10} default {throw 'Unknown sample phase.'} }
        if ($sample.index -lt 1 -or $sample.index -gt $limit -or -not $identities.Add("$($sample.phase)-$($sample.index)")) { throw 'Invalid or duplicate sample identity.' }
        if ($null -eq $sample.exit_code -or $sample.exit_code -ne 0 -or $sample.timed_out -ne $false -or $sample.drain_timed_out -ne $false) { throw 'Failed or incomplete sample process.' }
        if ($null -eq $sample.elapsed_ms -or -not [double]::IsFinite([double]$sample.elapsed_ms) -or $sample.elapsed_ms -le 0) { throw 'Invalid sample duration.' }
        if ($sample.peak_working_set_bytes -le 0 -or -not $sample.memory_scope) { throw 'Missing peak memory evidence.' }
    }
    return [pscustomobject]@{
        cold = Get-MigrationStatistic -Values @($Samples | Where-Object phase -EQ cold | ForEach-Object elapsed_ms)
        warm = Get-MigrationStatistic -Values @($Samples | Where-Object phase -EQ warm | ForEach-Object elapsed_ms)
        peak_working_set_bytes = ($Samples | Measure-Object peak_working_set_bytes -Maximum).Maximum
    }
}

function Get-MigrationBaselineValidation {
    param([hashtable]$Configuration, [string]$EvidenceRoot)
    . (Join-Path $PSScriptRoot 'compare-native-analysis-artifacts.ps1')
    foreach ($field in @('source_revision', 'machine', 'collection_scope', 'budget_file', 'budget_sha256', 'input_manifest', 'input_manifest_sha256')) {
        if (-not $Configuration[$field]) { throw "Missing baseline field: $field" }
    }
    foreach ($field in @('os', 'architecture', 'processor', 'logical_processors', 'pwsh')) {
        if (-not $Configuration.machine[$field]) { throw "Missing machine field: $field" }
    }
    $budgetPath = Resolve-MigrationOutputPath -Path (Join-Path $EvidenceRoot $Configuration.budget_file) -Root $EvidenceRoot
    $inputPath = Resolve-MigrationOutputPath -Path (Join-Path $EvidenceRoot $Configuration.input_manifest) -Root $EvidenceRoot
    if ((Get-FileHash -LiteralPath $budgetPath).Hash -ne $Configuration.budget_sha256 -or
        (Get-FileHash -LiteralPath $inputPath).Hash -ne $Configuration.input_manifest_sha256) { throw 'Frozen baseline manifest hash mismatch.' }
    $inputs = Get-Content -LiteralPath $inputPath -Raw | ConvertFrom-Json -AsHashtable
    if (-not $inputs.files.Count) { throw 'Empty baseline input manifest.' }
    foreach ($file in $inputs.files) {
        $item = Get-Item -LiteralPath $file.path -Force -ErrorAction Stop
        if ($item.Length -ne $file.bytes -or (Get-FileHash -LiteralPath $item.FullName).Hash -ne $file.sha256) { throw "Baseline input changed: $($file.path)" }
    }
    if (-not $inputs.source_roots.Count) { throw 'Missing frozen source root inventories.' }
    $hashedPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $inputs.files) { [void]$hashedPaths.Add([IO.Path]::GetFullPath($file.path)) }
    foreach ($root in $inputs.source_roots) {
        [void](Resolve-MigrationOutputPath -Path $root.path -Root $EvidenceRoot)
        Assert-MigrationSourceInventory -Root $root.path -Expected $root.files
        foreach ($relative in $root.files) {
            if (-not $hashedPaths.Contains([IO.Path]::GetFullPath((Join-Path $root.path $relative)))) { throw 'Inventoried source has no retained input hash.' }
        }
    }
    $reference = Get-Content -LiteralPath (Join-Path $EvidenceRoot 'reference-manifest.json') -Raw | ConvertFrom-Json
    foreach ($file in $reference.files) {
        $path = Join-Path $EvidenceRoot ('python-reference/' + $file.path)
        if ((Get-FileHash -LiteralPath $path).Hash -ne $file.sha256) { throw "Pinned reference changed: $($file.path)" }
    }
    $coverage = Get-Content -LiteralPath (Join-Path $EvidenceRoot 'coverage-map.json') -Raw | ConvertFrom-Json
    $pythonProof = Get-Content -LiteralPath (Join-Path $EvidenceRoot 'python-baseline.run.json') -Raw | ConvertFrom-Json
    $pythonLog = [IO.File]::ReadAllText((Join-Path $EvidenceRoot 'python-baseline.log'))
    if ($pythonProof.exit_code -ne 0 -or $pythonLog -notmatch '(?s)Ran (\d+) tests in .*\r?\n\r?\nOK\s*$' -or
        [int]$Matches[1] -ne $coverage.cases.Count -or $pythonLog -match '(?im)\bskipped\b') { throw 'Python suite does not match complete unskipped coverage.' }
    $budgets = Get-Content -LiteralPath $budgetPath -Raw | ConvertFrom-Json -AsHashtable
    $requiredNames = @('report-small', 'report-large', 'report-small-verify', 'report-large-verify', 'workspace-git-small', 'workspace-git-large', 'workspace-none-small', 'workspace-none-large', 'workspace-svn', 'live-project', 'live-unit-context', 'live-unit-standalone')
    if ((@($requiredNames | Sort-Object) -join ',') -cne (@($budgets.scenarios.name | Sort-Object) -join ',')) { throw 'Incomplete or duplicate baseline scenario inventory.' }
    if (-not $budgets.frozen_before_native_implementation -or -not $budgets.cache_protocol -or -not $budgets.memory_scope -or -not $budgets.timing_scope) { throw 'Incomplete frozen measurement contract.' }
    $scenarioResults = foreach ($scenario in $budgets.scenarios) {
        foreach ($field in @('median_ms', 'p95_ms', 'peak_root_bytes')) {
            if ($scenario.budget[$field] -le 0 -or -not [double]::IsFinite([double]$scenario.budget[$field])) { throw "Missing or invalid scenario budget: $field" }
        }
        if (-not $scenario.input_shape -or $scenario.comparison_profile -notin @('Exact','Replay','Live')) { throw 'Missing input shape or comparison contract.' }
        $measurementPath = Resolve-MigrationOutputPath -Path (Join-Path $EvidenceRoot $scenario.measurements) -Root (Join-Path $EvidenceRoot 'measurements')
        $measurements = Get-Content -LiteralPath $measurementPath -Raw | ConvertFrom-Json
        if ($measurements.name -cne $scenario.name) { throw 'Scenario measurement identity mismatch.' }
        $statistics = Get-MigrationRetainedSampleSummary -Samples $measurements.samples
        foreach ($phase in @('cold','warm')) {
            foreach ($field in @('count','median','p95','min','max')) {
                if ($statistics.$phase.$field -ne $measurements.$phase.$field) { throw 'Retained sample statistics do not match raw values.' }
            }
        }
        $scenarioRoot = [IO.Path]::GetDirectoryName($measurementPath)
        $sampleResults = foreach ($sample in $measurements.samples) {
            $sampleRoot = Join-Path $scenarioRoot "$($sample.phase)-$($sample.index)"
            $process = Get-Content -LiteralPath (Join-Path $sampleRoot 'process.json') -Raw | ConvertFrom-Json
            foreach ($property in $process.PSObject.Properties) {
                if ((ConvertTo-Json -InputObject $property.Value -Compress -Depth 15) -cne (ConvertTo-Json -InputObject $sample.($property.Name) -Compress -Depth 15)) { throw "Raw process evidence differs: $sampleRoot / $($property.Name)" }
            }
            $comparison = Compare-MigrationArtifact -Reference (Join-Path $scenarioRoot 'cold-1/artifacts') -Candidate (Join-Path $sampleRoot 'artifacts') -ComparisonProfile $scenario.comparison_profile -PalTempRoot (Join-Path $EvidenceRoot 'scratch/process-temp/dak-pal')
            [pscustomobject]@{ phase=$sample.phase; index=$sample.index; elapsed_ms=$sample.elapsed_ms; peak_root_bytes=$sample.peak_working_set_bytes; reported_analyzer_stage_ms=$sample.analyzer_ms; outside_reported_stages_ms=$sample.workflow_overhead_ms; files=$comparison.files }
        }
        Write-Information "Validated $($scenario.name): 17 complete ordered artifact sets." -InformationAction Continue
        [pscustomobject]@{name=$scenario.name; statistics=$statistics; budget=$scenario.budget; input_shape=$scenario.input_shape; samples=$sampleResults; comparison_profile=$scenario.comparison_profile}
    }
    $policyRoot = Join-Path $EvidenceRoot 'corpus/policy-controls'
    $incompatible = Get-Content -LiteralPath (Join-Path $policyRoot 'incompatible/gate-process.json') -Raw | ConvertFrom-Json
    $gateOutput = Get-Content -LiteralPath (Join-Path $policyRoot 'incompatible/gate-process.stdout') -Raw | ConvertFrom-Json
    if ($incompatible.exit_code -ne 3 -or $gateOutput.gate_pass -ne $false -or $gateOutput.baseline_updated -ne $false) { throw 'Incompatible baseline control did not reject safely.' }
    foreach ($file in @('baseline.json','baseline.md')) {
        if ((Get-FileHash (Join-Path $policyRoot "incompatible/baseline/$file")).Hash -ne (Get-FileHash (Join-Path $policyRoot "incompatible/gate-output/$file")).Hash) { throw 'Incompatible control changed its accepted baseline.' }
    }
    $corrupt = Get-Content -LiteralPath (Join-Path $policyRoot 'corrupt/corrupt-verify.json') -Raw | ConvertFrom-Json
    if ($corrupt.exit_code -ne 3 -or [IO.File]::ReadAllText((Join-Path $policyRoot 'corrupt/corrupt-verify.stderr')) -notmatch 'compatibility') { throw 'Corruption control failed for the wrong reason.' }
    [void](Compare-MigrationArtifact -Reference (Join-Path $policyRoot 'corrupt/corrupt-input') -Candidate (Join-Path $policyRoot 'corrupt/corrupt-output') -ComparisonProfile Exact)
    $doctor = Get-Content -LiteralPath (Join-Path $EvidenceRoot 'corpus/doctor-missing-pal/result.json') -Raw | ConvertFrom-Json
    if ($doctor.result.exit_code -ne 3 -or -not [IO.File]::ReadAllText((Join-Path $EvidenceRoot 'corpus/doctor-missing-pal/process.stdout')).Contains($doctor.expected_diagnostic)) { throw 'Missing-tool doctor control is incomplete.' }
    $infrastructure = Get-Content -LiteralPath (Join-Path $EvidenceRoot 'measurements/project-smoke-01/process.json') -Raw | ConvertFrom-Json
    if ($infrastructure.exit_code -ne 6) { throw 'Retained missing-resource infrastructure failure changed.' }
    return [pscustomobject]@{
        passed=$true; scenario_count=$scenarioResults.Count; sample_count=$scenarioResults.Count*17
        python_cases=$coverage.cases.Count; input_files=$inputs.files.Count; source_revision=$Configuration.source_revision
        machine=$Configuration.machine; budget_sha256=$Configuration.budget_sha256; input_manifest_sha256=$Configuration.input_manifest_sha256
        comparison_helper_sha256=(Get-FileHash (Join-Path $PSScriptRoot 'compare-native-analysis-artifacts.ps1')).Hash
        verification_helper_sha256=(Get-FileHash $PSCommandPath).Hash
        scenarios=$scenarioResults; controls=@('incompatible-baseline-preserved','corrupt-verification-preserved','missing-explicit-pal','missing-pal-map-resource')
        scope='Reference baseline completeness and frozen candidate budgets; no native candidate performance or migration completion claim.'
    }
}

function Get-MigrationSourceInventory {
    param([string]$Root)
    $rootPath = [IO.Path]::GetFullPath($Root)
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($rootPath)
    $files = [Collections.Generic.List[string]]::new()
    while ($pending.Count) {
        $directory = $pending.Pop()
        foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($directory)) {
            $name = [IO.Path]::GetFileName($path)
            if ($name -in @('.git', '.svn', '.dak')) { continue }
            $attributes = [IO.File]::GetAttributes($path)
            if ($attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source inventory crosses a reparse point.' }
            if ($attributes -band [IO.FileAttributes]::Directory) { $pending.Push($path) }
            elseif ($name -eq '.gitignore' -or [IO.Path]::GetExtension($path) -in @('.pas', '.dpr', '.dproj', '.inc', '.dpk', '.dfm', '.fmx', '.cfg', '.ini', '.json')) {
                $files.Add([IO.Path]::GetRelativePath($rootPath, $path).Replace('\', '/'))
            }
        }
    }
    return ,@($files | Sort-Object -CaseSensitive)
}

function Assert-MigrationSourceInventory {
    param([string]$Root, [string[]]$Expected)
    $actual = Get-MigrationSourceInventory -Root $Root
    if (($actual -join "`n") -cne (@($Expected | Sort-Object -CaseSensitive) -join "`n")) { throw 'Frozen source inventory differs from current files.' }
}

function Compare-MigrationWorkspace {
    param([string]$ReferenceText, [string]$CandidateText, [string]$IdentityText)
    . (Join-Path $PSScriptRoot 'compare-native-analysis-artifacts.ps1')
    $documents = [Collections.Generic.List[System.Text.Json.JsonDocument]]::new()
    try {
        foreach ($text in @($ReferenceText, $CandidateText, $IdentityText)) {
            $document = [System.Text.Json.JsonDocument]::Parse($text)
            $documents.Add($document)
            Assert-MigrationJsonKey $document.RootElement
        }
        $identity = ConvertTo-MigrationWorkspaceJson $documents[2].RootElement
        $actualIdentity = $documents[1].RootElement.GetProperty('provenance').GetProperty('dak')
        if ((ConvertTo-MigrationWorkspaceJson $actualIdentity) -cne $identity) { throw 'Candidate DAK identity differs from independent evidence.' }
        $reference = ConvertTo-MigrationWorkspaceJson -Element $documents[0].RootElement -Path '$' -Identity $identity
        $candidate = ConvertTo-MigrationWorkspaceJson -Element $documents[1].RootElement -Path '$' -Identity $identity
        if ($reference -cne $candidate) { throw 'Workspace record differs.' }
        return [pscustomobject]@{equal=$true; identity=($IdentityText | ConvertFrom-Json); comparison_sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($candidate)))}
    } finally { foreach ($document in $documents) { $document.Dispose() } }
}

function ConvertTo-MigrationWorkspaceJson {
    param([System.Text.Json.JsonElement]$Element, [string]$Path = '$', [string]$Identity)
    if ($Path -ceq '$.provenance.dak' -and $Identity) { return $Identity }
    switch ($Element.ValueKind.ToString()) {
        Object {
            $properties = @($Element.EnumerateObject() | Sort-Object Name -CaseSensitive)
            $values = foreach ($property in $properties) {
                (ConvertTo-Json -InputObject $property.Name -Compress) + ':' + (ConvertTo-MigrationWorkspaceJson -Element $property.Value -Path ($Path+'.'+$property.Name) -Identity $Identity)
            }
            return '{' + ($values -join ',') + '}'
        }
        Array {
            $values = foreach ($item in $Element.EnumerateArray()) { ConvertTo-MigrationWorkspaceJson -Element $item -Path ($Path+'[]') -Identity $Identity }
            return '[' + ($values -join ',') + ']'
        }
        String { return ConvertTo-Json -InputObject $Element.GetString() -Compress }
        default { return $Element.GetRawText() }
    }
}

function Get-MigrationWorkspaceBudgetResult {
    param([object[]]$Samples, [object]$Budget)
    foreach ($field in @('median_ms','p95_ms','peak_root_bytes')) {
        $value=$Budget.$field
        if ($null -eq $value -or $value -is [string] -or $value -is [bool] -or -not [double]::IsFinite([double]$value) -or $value -le 0) { throw "Invalid workspace budget: $field" }
    }
    $statistics=Get-MigrationRetainedSampleSummary -Samples $Samples
    $violations=[Collections.Generic.List[string]]::new()
    foreach ($phase in @('cold','warm')) {
        if ($statistics.$phase.median -gt $Budget.median_ms) {$violations.Add("$phase median_ms")}
        if ($statistics.$phase.p95 -gt $Budget.p95_ms) {$violations.Add("$phase p95_ms")}
    }
    foreach ($sample in $Samples) {
        if ($sample.peak_working_set_bytes -gt $Budget.peak_root_bytes) {$violations.Add("$($sample.phase)-$($sample.index) peak_root_bytes")}
    }
    return [pscustomobject]@{passed=($violations.Count -eq 0);statistics=$statistics;budget=$Budget;violations=@($violations)}
}

function Get-MigrationWorkspaceEnvironment {
    $childEnvironment = @{PYTHONDONTWRITEBYTECODE='1'; MAXLOGIC_MADEXCEPT_AI='1'}
    foreach ($key in [Environment]::GetEnvironmentVariables().Keys) {
        if ([string]$key -like 'DAK_*' -or [string]$key -like 'GIT_*') { $childEnvironment[$key]=$null }
    }
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $childEnvironment.DAK_MAXTDB_FIXTURE = Join-Path $repoRoot 'tests/fixtures/test-projects/semantic-isolated-t311/maxTdb'
    $childEnvironment.DAK_TEST_OUTPUT_ROOT = $null
    return $childEnvironment
}

function Invoke-MigrationWorkspaceComparison {
    param([string]$EvidenceRoot, [string]$Executable, [string]$ResultRoot, [switch]$Benchmark)
    . (Join-Path $PSScriptRoot 'compare-native-analysis-artifacts.ps1')
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $executablePath = Resolve-MigrationOutputPath -Path $Executable -Root $repoRoot
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) { throw 'Missing candidate executable.' }
    $batchRoot = Resolve-MigrationOutputPath $ResultRoot (Join-Path $EvidenceRoot 'measurements')
    if (Test-Path -LiteralPath $batchRoot) { throw 'Workspace comparison evidence already exists.' }
    $budgetPath=Join-Path $EvidenceRoot 'frozen-budgets.json'
    $budgetHash=(Get-FileHash -LiteralPath $budgetPath).Hash
    $budgets = Get-Content -LiteralPath $budgetPath -Raw | ConvertFrom-Json
    $scenarios = @($budgets.scenarios | Where-Object area -EQ Workspace)
    if ($scenarios.Count -ne 5) { throw 'Expected five frozen workspace scenarios.' }
    $childEnvironment = Get-MigrationWorkspaceEnvironment
    [void][IO.Directory]::CreateDirectory($batchRoot)
    $candidateHash = (Get-FileHash -LiteralPath $executablePath).Hash
    $results = foreach ($frozen in $scenarios) {
        $manifest = Get-Content -LiteralPath (Join-Path $EvidenceRoot $frozen.collection_manifest) -Raw | ConvertFrom-Json
        $scenario = @($manifest.scenarios | Where-Object name -CEQ $frozen.name)
        if ($scenario.Count -ne 1) { throw 'Frozen workspace scenario is missing or duplicated.' }
        $scenario = $scenario[0]
        [void](Resolve-MigrationOutputPath -Path $scenario.subject -Root (Join-Path $EvidenceRoot 'scratch'))
        [void](Resolve-MigrationOutputPath -Path $scenario.working_directory -Root (Join-Path $EvidenceRoot 'scratch'))
        if ($scenario.selector -notin @('git','project','svn') -or -not (Test-Path -LiteralPath $scenario.subject -PathType Leaf)) { throw 'Invalid frozen workspace subject or selector.' }
        $scenarioRoot = Resolve-MigrationOutputPath (Join-Path $batchRoot $scenario.name) $batchRoot
        [void][IO.Directory]::CreateDirectory($scenarioRoot)
        $schedule = if ($Benchmark) {
            foreach ($phase in @('cold','warmup','warm')) {
                $count=switch ($phase) {cold {5} warmup {2} warm {10}}
                for ($index=1; $index -le $count; $index++) {[pscustomobject]@{phase=$phase;index=$index}}
            }
        } else { [pscustomobject]@{phase='compare';index=1} }
        $samples = @()
        $records = foreach ($entry in $schedule) {
        $sampleRoot = if ($Benchmark) { Resolve-MigrationOutputPath (Join-Path $scenarioRoot "$($entry.phase)-$($entry.index)") $scenarioRoot } else {$scenarioRoot}
        [void][IO.Directory]::CreateDirectory($sampleRoot)
        $scratch = Resolve-MigrationOutputPath (Join-Path $EvidenceRoot ('scratch/compare-workspace/'+[guid]::NewGuid().ToString())) (Join-Path $EvidenceRoot 'scratch')
        [void][IO.Directory]::CreateDirectory($scratch)
        # Capture the current engine identity independently with the pinned Python implementation.
        # Require both executables to belong to the same checkout, avoiding script-parent inference outside DAK.
        $driver = @'
import sys,json
from pathlib import Path
sys.path.insert(0,sys.argv[1])
from postprocess import _find_git_root,_dak_identity,_sha256_file
exe=Path(sys.argv[2]).resolve()
assert _find_git_root(exe.parent)==Path(sys.argv[3]).resolve(), 'Candidate must belong to the DAK checkout'
assert _find_git_root(Path(sys.argv[1]))==Path(sys.argv[3]).resolve(), 'Reference must belong to the DAK checkout'
identity=_dak_identity()
assert identity.get('status')=='complete', 'Independent DAK identity is incomplete'
identity.update(executable=str(exe),executable_sha256=_sha256_file(exe))
print(json.dumps(identity,ensure_ascii=False))
'@
        $identityProcess = Invoke-MigrationProcess -Executable $scenario.executable -Arguments @('-c',$driver,(Join-Path $EvidenceRoot 'python-reference/agentskills/dak-static-analysis'),$executablePath,$repoRoot) -WorkingDirectory $scenario.working_directory -Environment $childEnvironment -LogPath (Join-Path $sampleRoot 'identity')
        if ($identityProcess.exit_code -ne 0 -or $identityProcess.timed_out -or $identityProcess.drain_timed_out) { throw 'Independent identity capture failed.' }
        $process = Invoke-MigrationProcess -Executable $executablePath -Arguments @('analyze-workspace','--project',$scenario.subject,'--workspace-root',$scenario.selector,'--out',$scratch,'--json') -WorkingDirectory $scenario.working_directory -Environment $childEnvironment -LogPath (Join-Path $sampleRoot 'process')
        if ($process.exit_code -ne 0 -or $process.timed_out -or $process.drain_timed_out) { throw 'Native workspace capture failed.' }
        $referencePath = Join-Path ([IO.Path]::GetDirectoryName((Join-Path $EvidenceRoot $frozen.measurements))) 'cold-1/artifacts/workspace.json'
        $comparison = Compare-MigrationWorkspace -ReferenceText (Get-MigrationUtf8Text ([IO.File]::ReadAllBytes($referencePath))) -CandidateText (Get-MigrationUtf8Text ([IO.File]::ReadAllBytes((Join-Path $sampleRoot 'process.stdout')))) -IdentityText (Get-MigrationUtf8Text ([IO.File]::ReadAllBytes((Join-Path $sampleRoot 'identity.stdout'))))
        if ($Benchmark) {
            $process | Add-Member -NotePropertyName phase -NotePropertyValue $entry.phase
            $process | Add-Member -NotePropertyName index -NotePropertyValue $entry.index
            $samples += $process
        }
        $record=[pscustomobject]@{name=$scenario.name;comparison=$comparison;process=$process;reference_sha256=(Get-FileHash -LiteralPath $referencePath).Hash}
        $record | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $sampleRoot 'comparison.json')
        $record
        }
        if ($Benchmark) {
            $assessment=Get-MigrationWorkspaceBudgetResult -Samples $samples -Budget $frozen.budget
            $scenarioResult=[pscustomobject]@{name=$scenario.name;assessment=$assessment;samples=@($samples);comparisons=@($records)}
            $scenarioResult | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $scenarioRoot 'measurements.json')
            if (-not $assessment.passed) {throw "Workspace budget exceeded: $($scenario.name): $($assessment.violations -join ', '); raw samples retained."}
            $scenarioResult
        } else {$records}
    }
    if ((Get-FileHash -LiteralPath $executablePath).Hash -ne $candidateHash) { throw 'Candidate executable changed during comparison.' }
    if ((Get-FileHash -LiteralPath $budgetPath).Hash -ne $budgetHash) {throw 'Frozen budget changed during the batch.'}
    $scope=if ($Benchmark) {'Five workspace scenarios: full record equality and frozen cold/warm latency and root-memory budgets.'} else {'Workspace correctness only; no performance acceptance.'}
    $result = [pscustomobject]@{passed=$true;candidate=$executablePath;candidate_sha256=$candidateHash;budget_sha256=$budgetHash;scenarios=@($results);scope=$scope}
    $resultFile=if ($Benchmark) {'benchmark.json'} else {'comparison.json'}
    $result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $batchRoot $resultFile)
    return $result
}

function Get-MigrationWorkspaceArgument {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string]$ReferenceRoot, [string]$Subject, [string]$Selector, [string]$DakExecutable)
    # Development comparison only: invoke the pinned functions without duplicating their rules.
    $driver = @'
import sys, json
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from workspace import resolve_workspace
from postprocess import capture_run_provenance
subject = Path(sys.argv[2])
workspace = resolve_workspace(subject, sys.argv[3], cwd=subject.parent)
result = {"workspace": workspace._asdict(), "provenance": capture_run_provenance(subject, Path(sys.argv[4]), workspace)}
print(json.dumps(result, default=str, ensure_ascii=False, sort_keys=True))
'@
    return @('-c', $driver, $ReferenceRoot, $Subject, $Selector, $DakExecutable)
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $evidenceRoot = Join-Path $repoRoot 'projects/.dak/DelphiAIKit/native-analysis-migration'
    if ($Mode -eq 'Compare' -and $Area -eq 'Doctor') {
        if (-not $CandidateExecutable) { throw 'Compare Doctor requires CandidateExecutable.' }
        . (Join-Path $PSScriptRoot 'compare-native-analysis-doctor.ps1')
        $resultRoot = if ($Manifest) { (Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json).result_root } else { Join-Path $evidenceRoot ('measurements/doctor-compare-'+[guid]::NewGuid().ToString()) }
        Invoke-MigrationDoctorComparison -EvidenceRoot $evidenceRoot -Executable $CandidateExecutable -ResultRoot $resultRoot
        return
    }
    if ($Mode -in @('Compare','Benchmark') -and $Area -eq 'Workspace') {
        if (-not $CandidateExecutable) { throw "$Mode Workspace requires CandidateExecutable." }
        $resultRoot = if ($Manifest) { (Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json).result_root } else { Join-Path $evidenceRoot ('measurements/workspace-'+$Mode.ToLowerInvariant()+'-'+[guid]::NewGuid().ToString()) }
        Invoke-MigrationWorkspaceComparison -EvidenceRoot $evidenceRoot -Executable $CandidateExecutable -ResultRoot $resultRoot -Benchmark:($Mode -eq 'Benchmark')
        return
    }
    if ($Mode -eq 'Compare' -and $Area -eq 'Policy') {
        if (-not $CandidateExecutable) { throw 'Compare Policy requires CandidateExecutable.' }
        . (Join-Path $PSScriptRoot 'compare-native-analysis-policy.ps1')
        $resultRoot = if ($Manifest) { (Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json).result_root } else { Join-Path $evidenceRoot ('measurements/policy-compare-'+[guid]::NewGuid().ToString()) }
        Invoke-MigrationPolicyComparison -EvidenceRoot $evidenceRoot -Executable $CandidateExecutable -ResultRoot $resultRoot
        return
    }
    if ($Mode -in @('Compare','Benchmark') -and $Area -eq 'Reports') {
        if (-not $CandidateExecutable) { throw "$Mode Reports requires CandidateExecutable." }
        . (Join-Path $PSScriptRoot 'compare-native-analysis-reports.ps1')
        $resultRoot = if ($Manifest) { (Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json).result_root } else { Join-Path $evidenceRoot ('measurements/reports-'+$Mode.ToLowerInvariant()+'-'+[guid]::NewGuid().ToString()) }
        Invoke-MigrationReportComparison -EvidenceRoot $evidenceRoot -Executable $CandidateExecutable -ResultRoot $resultRoot -Benchmark:($Mode -eq 'Benchmark') -ArtifactSet $ArtifactSet
        return
    }
    if ($Mode -eq 'Compare' -and $Area -eq 'Project') {
        if (-not $CandidateExecutable) { throw 'Compare Project requires CandidateExecutable.' }
        . (Join-Path $PSScriptRoot 'compare-native-analysis-project.ps1')
        $resultRoot = if ($Manifest) { (Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json).result_root } else { Join-Path $evidenceRoot ('measurements/project-compare-'+[guid]::NewGuid().ToString()) }
        Invoke-MigrationProjectComparison -EvidenceRoot $evidenceRoot -Executable $CandidateExecutable -ResultRoot $resultRoot
        return
    }
    if ($Mode -eq 'Compare' -and $Area -eq 'Unit') {
        if (-not $CandidateExecutable) { throw 'Compare Unit requires CandidateExecutable.' }
        . (Join-Path $PSScriptRoot 'compare-native-analysis-unit.ps1')
        $resultRoot = if ($Manifest) { (Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json).result_root } else { Join-Path $evidenceRoot ('measurements/unit-compare-'+[guid]::NewGuid().ToString()) }
        Invoke-MigrationUnitComparison -EvidenceRoot $evidenceRoot -Executable $CandidateExecutable -ResultRoot $resultRoot
        return
    }
    if ($Mode -ne 'Baseline') { throw "Mode $Mode requires its native migration task; it is not certified yet." }
    $scratchRoot = Join-Path $evidenceRoot 'scratch'
    $seedRoot = Join-Path $evidenceRoot 'seeds'
    $measurementRoot = Join-Path $evidenceRoot 'measurements'
    if (-not $Manifest) { $Manifest = Join-Path $evidenceRoot 'scenarios.json' }
    $configuration = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json -AsHashtable
    if ($configuration.kind -eq 'retained-baseline-v1') {
        if ($Area -ne 'All') { throw 'Full retained baseline validation requires Area All.' }
        $validationPath = Resolve-MigrationOutputPath -Path $configuration.validation_output -Root $measurementRoot
        if (Test-Path -LiteralPath $validationPath) { throw 'Retained baseline validation already exists.' }
        $validation = Get-MigrationBaselineValidation -Configuration $configuration -EvidenceRoot $evidenceRoot
        $validation | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $validationPath
        Write-Output "Full baseline validated: $($validation.scenario_count) scenarios, $($validation.sample_count) samples."
        return
    }
    $scenarios = @($configuration.scenarios | Where-Object { $Area -eq 'All' -or $_.area -eq $Area })
    Assert-MigrationScenario -Scenarios $scenarios
    $batchRoot = Resolve-MigrationOutputPath -Path $configuration.result_root -Root $measurementRoot
    if (Test-Path -LiteralPath $batchRoot) { throw "Retained evidence already exists: $batchRoot" }
    foreach ($scenario in $scenarios) {
        [void](Resolve-MigrationOutputPath -Path $scenario.output -Root $scratchRoot)
        [void](Resolve-MigrationOutputPath -Path $scenario.reset_source -Root $seedRoot)
        if (-not (Test-Path -LiteralPath $scenario.executable -PathType Leaf)) { throw "Missing executable: $($scenario.executable)" }
        if (-not (Test-Path -LiteralPath $scenario.reset_source -PathType Container)) { throw "Missing seed: $($scenario.reset_source)" }
        if (Test-Path -LiteralPath $scenario.output) { throw "Scratch output already exists: $($scenario.output)" }
        # Extend this allowlist when each additional baseline workflow is prepared and reviewed.
        $referenceScript = Join-Path $evidenceRoot 'python-reference/agentskills/dak-static-analysis/postprocess.py'
        $expectedArguments = @($referenceScript, $scenario.output)
        if ($scenario.arguments.Count -eq 3 -and $scenario.arguments[1] -eq '--verify') {
            $expectedArguments = @($referenceScript, '--verify', $scenario.output)
        }
        if ($scenario.area -eq 'Workspace') {
            foreach ($field in @('subject', 'selector', 'dak_executable', 'source_count')) {
                if (-not $scenario.Contains($field)) { throw "Workspace scenario is missing $field." }
            }
            [void](Resolve-MigrationOutputPath -Path $scenario.subject -Root $scratchRoot)
            [void](Resolve-MigrationOutputPath -Path $scenario.dak_executable -Root (Join-Path $evidenceRoot 'tools'))
            if ($scenario.selector -notin @('project', 'git', 'svn')) { throw 'Unsupported workspace baseline selector.' }
            $expectedArguments = @(Get-MigrationWorkspaceArgument -ReferenceRoot ([IO.Path]::GetDirectoryName($referenceScript)) `
                -Subject $scenario.subject -Selector $scenario.selector -DakExecutable $scenario.dak_executable)
        }
        if ($scenario.area -in @('Project', 'Unit')) {
            [void](Resolve-MigrationOutputPath -Path $scenario.subject -Root $scratchRoot)
            [void](Resolve-MigrationOutputPath -Path $scenario.environment.DAK_EXE -Root (Join-Path $evidenceRoot 'tools'))
            $wrapper = if ($scenario.area -eq 'Project') { 'analyze.py' } else { 'analyze-unit.py' }
            $expectedArguments = @((Join-Path ([IO.Path]::GetDirectoryName($referenceScript)) $wrapper), $scenario.subject)
            if ($scenario.project_context) {
                [void](Resolve-MigrationOutputPath -Path $scenario.project_context -Root $scratchRoot)
                $expectedArguments += $scenario.project_context
            }
            $expectedArguments += @('--workspace-root', 'project')
            if ($scenario.environment.DAK_OUT -ne $scenario.output -or $scenario.environment.DAK_PLATFORM -ne 'Win64' -or
                $scenario.environment.DAK_CONFIG -ne 'Release' -or $scenario.environment.DAK_DELPHI -ne '23.0') {
                throw 'Live baseline requires isolated output and explicit Delphi 12 Win64 Release context.'
            }
            $isolatedPalIni = Join-Path $scratchRoot 'live-project/PAL.INI'
            if ($scenario.environment.PA_ARGS -ne ('/I="' + $isolatedPalIni + '"')) { throw 'Live PAL must use the pinned isolated INI.' }
        }
        if ($scenario.area -notin @('Reports', 'Workspace', 'Project', 'Unit') -or [IO.Path]::GetFileName($scenario.executable) -notmatch '^python[0-9.]*\.exe$' -or
            ($scenario.arguments | ConvertTo-Json -Compress) -cne ($expectedArguments | ConvertTo-Json -Compress)) {
            throw "Scenario command has not been approved for this workflow: $($scenario.name)"
        }
        [void](Resolve-MigrationOutputPath -Path $scenario.working_directory -Root $scratchRoot)
        foreach ($key in $scenario.environment.Keys) {
            $allowedEnvironment = @('DAK_BASELINE', 'DAK_GATE', 'DAK_CI', 'DAK_UPDATE_BASELINE', 'DAK_GATE_REQUIRE_CONTEXT_MATCH', 'DAK_GATE_INCLUDE_PATHS', 'DAK_GATE_EXCLUDE_PATHS')
            if ($scenario.area -in @('Project', 'Unit')) {
                $allowedEnvironment += @('DAK_EXE', 'DAK_OUT', 'DAK_PLATFORM', 'DAK_CONFIG', 'DAK_DELPHI', 'DAK_FIXINSIGHT', 'DAK_PASCAL_ANALYZER', 'DAK_CLEAN', 'DAK_WRITE_SUMMARY', 'PA_PATH', 'PA_ARGS')
            }
            if ($key -notin $allowedEnvironment) {
                throw "Unsupported scenario environment variable: $key"
            }
        }
        if ($scenario.environment.DAK_BASELINE -and
            [IO.Path]::GetFullPath($scenario.environment.DAK_BASELINE) -ne (Join-Path $scenario.output 'baseline.json')) {
            throw 'Baseline must remain inside the isolated report output.'
        }
    }
    [void][IO.Directory]::CreateDirectory($batchRoot)
    Copy-Item -LiteralPath $Manifest -Destination (Join-Path $batchRoot 'manifest.json')
    $results = @()
    foreach ($scenario in $scenarios) {
        $scenarioRoot = Join-Path $batchRoot $scenario.name
        [void][IO.Directory]::CreateDirectory($scenarioRoot)
        $samples = @()
        foreach ($phase in @('cold', 'warmup', 'warm')) {
            $count = switch ($phase) { 'cold' { 5 } 'warmup' { 2 } 'warm' { 10 } }
            for ($index = 1; $index -le $count; $index++) {
                Initialize-MigrationSample -Seed $scenario.reset_source -Output $scenario.output -ScratchRoot $scratchRoot
                $sampleRoot = Join-Path $scenarioRoot "$phase-$index"
                [void][IO.Directory]::CreateDirectory($sampleRoot)
                $childEnvironment = @{}
                foreach ($key in [Environment]::GetEnvironmentVariables().Keys) {
                    if ([string]$key -like 'DAK_*' -or [string]$key -like 'PA_*' -or [string]$key -like 'FI_*' -or [string]$key -like 'FIXINSIGHT_*') { $childEnvironment[$key] = $null }
                }
                $isolatedEnvironment = @{
                    DAK_MAXTDB_FIXTURE = Join-Path $repoRoot 'tests/fixtures/test-projects/semantic-isolated-t311/maxTdb'
                    DAK_TEST_OUTPUT_ROOT = $null
                    PYTHONDONTWRITEBYTECODE = '1'
                    MAXLOGIC_MADEXCEPT_AI = '1'
                    TEMP = Join-Path $scratchRoot 'process-temp'
                    TMP = Join-Path $scratchRoot 'process-temp'
                }
                [void](Resolve-MigrationOutputPath -Path $isolatedEnvironment.TEMP -Root $scratchRoot)
                [void][IO.Directory]::CreateDirectory($isolatedEnvironment.TEMP)
                foreach ($key in $isolatedEnvironment.Keys) { $childEnvironment[$key] = $isolatedEnvironment[$key] }
                foreach ($key in $scenario.environment.Keys) { $childEnvironment[$key] = $scenario.environment[$key] }
                $sample = Invoke-MigrationProcess -Executable $scenario.executable -Arguments $scenario.arguments `
                    -WorkingDirectory $scenario.working_directory -Environment $childEnvironment `
                    -LogPath (Join-Path $sampleRoot 'process')
                $sample | Add-Member -NotePropertyName phase -NotePropertyValue $phase
                $sample | Add-Member -NotePropertyName index -NotePropertyValue $index
                if ($scenario.area -in @('Project', 'Unit') -and $sample.exit_code -eq 0) {
                    $summary = Get-Content -LiteralPath (Join-Path $scenario.output 'summary.json') -Raw | ConvertFrom-Json
                    if ($summary.status.infrastructure -ne 'complete' -or $summary.status.finalization -ne 'complete') {
                        throw "Live analysis did not complete: $($scenario.name)"
                    }
                    $analyzerMs = 0.0
                    foreach ($analyzer in $summary.analyzers.PSObject.Properties.Value) {
                        foreach ($run in $analyzer.runs) { $analyzerMs += $run.duration_ms }
                    }
                    $sample | Add-Member -NotePropertyName analyzer_ms -NotePropertyValue $analyzerMs
                    $sample | Add-Member -NotePropertyName workflow_overhead_ms -NotePropertyValue ($sample.elapsed_ms - $analyzerMs)
                }
                if ($scenario.area -eq 'Workspace') {
                    Copy-Item -LiteralPath (Join-Path $sampleRoot 'process.stdout') -Destination (Join-Path $scenario.output 'workspace.json')
                    $workspaceResult = Get-Content -LiteralPath (Join-Path $scenario.output 'workspace.json') -Raw | ConvertFrom-Json
                    if ($workspaceResult.provenance.target.status -notin @('complete', 'not_applicable') -or
                        $workspaceResult.provenance.target.source_inputs.file_count -ne $scenario.source_count) {
                        throw "Workspace identity is incomplete or has an unexpected inventory: $($scenario.name)"
                    }
                }
                # Move the complete owned sample into retained evidence. The next run starts from a new directory.
                [void](Resolve-MigrationOutputPath -Path $scenario.output -Root $scratchRoot)
                $artifactPath = Resolve-MigrationOutputPath -Path (Join-Path $sampleRoot 'artifacts') -Root $measurementRoot
                if (Test-Path -LiteralPath $artifactPath) { throw "Retained artifacts already exist: $artifactPath" }
                Move-Item -LiteralPath $scenario.output -Destination $artifactPath
                if ($sample.timed_out -or $sample.drain_timed_out -or $sample.exit_code -ne $scenario.expected_exit) {
                    throw "Scenario $($scenario.name) failed in $phase sample $index; raw evidence retained."
                }
                $samples += $sample
                Write-Output "$($scenario.name) $phase $index/$count`: $([Math]::Round($sample.elapsed_ms, 1)) ms"
            }
        }
        $result = [ordered]@{
            name = $scenario.name
            cold = Get-MigrationStatistic -Values @($samples | Where-Object phase -EQ cold | ForEach-Object elapsed_ms)
            warm = Get-MigrationStatistic -Values @($samples | Where-Object phase -EQ warm | ForEach-Object elapsed_ms)
            samples = $samples
            certification = 'Timing collection only; output equivalence, complete scenario coverage and budgets require separate validation.'
        }
        [IO.File]::WriteAllText((Join-Path $scenarioRoot 'measurements.json'), ($result | ConvertTo-Json -Depth 8))
        $results += $result
    }
    [IO.File]::WriteAllText((Join-Path $batchRoot 'measurements.json'), ($results | ConvertTo-Json -Depth 9))
}
