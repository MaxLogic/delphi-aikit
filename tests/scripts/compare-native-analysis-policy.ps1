#Requires -Version 7.0
# Development proof helper for the native policy stage. Not part of the delivered workflow.
# Dot-sourced by verify-native-analysis-migration.ps1, which supplies the shared process helpers.
#
# There is no frozen snapshot for gated policy outcomes, so each scenario is run twice on an
# identical freshly built fixture: once through the pinned Python reference and once through the
# native candidate. The published artifacts and the process exit are then compared directly.

# Clocks, the engine identity and the interpreter version are the only differences a faithful port
# may show. The compatibility fingerprint covers the DAK executable, so it differs between the two
# engines wherever it appears, including inside a gate reason or a Markdown line.
$script:MigrationPolicyClockKeys = @('timestamp', 'created_at', 'summary_timestamp')
$script:MigrationPolicyFingerprint = [regex]'(?i)[0-9a-f]{64}'

function New-MigrationPolicyFixture {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$GitExecutable)
    $repo = Join-Path $Root 'repo'
    $external = Join-Path $Root 'external'
    [void][IO.Directory]::CreateDirectory((Join-Path $repo 'src'))
    [void][IO.Directory]::CreateDirectory((Join-Path $repo 'extras'))
    [void][IO.Directory]::CreateDirectory($external)
    [IO.File]::WriteAllText((Join-Path $repo 'src\Owned.pas'), "unit Owned;`n")
    [IO.File]::WriteAllText((Join-Path $repo 'extras\RepoOnly.pas'), "unit RepoOnly;`n")
    [IO.File]::WriteAllText((Join-Path $repo 'Sample.dproj'),
        '<Project><ItemGroup><DCCReference Include="src\Owned.pas"/></ItemGroup></Project>')
    [IO.File]::WriteAllText((Join-Path $repo 'Sample.dpr'), "program Sample;`nbegin`nend.`n")
    [IO.File]::WriteAllText((Join-Path $repo '.gitignore'), ".dak/`n")
    [IO.File]::WriteAllText((Join-Path $external 'External.pas'), "unit External;`n")
    # Fixed identity and dates make the commit hash a function of the content alone, so the two
    # engines see byte-identical repositories and nothing has to be masked out of the comparison.
    $previous = @{}
    foreach ($name in @('GIT_AUTHOR_DATE', 'GIT_COMMITTER_DATE')) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, '2026-07-17T12:00:00+00:00')
    }
    try {
        foreach ($arguments in @(
            @('init', '-q', '-b', 'main'),
            @('add', '.'),
            @('-c', 'user.name=dak-test', '-c', 'user.email=dak@example.invalid', 'commit', '-qm', 'fixture'))) {
            $process = Start-Process -FilePath $GitExecutable -ArgumentList $arguments -WorkingDirectory $repo `
                -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -ne 0) { throw "git $($arguments -join ' ') failed in $repo" }
        }
    } finally {
        foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name, $previous[$name]) }
    }
    $out = Join-Path $repo '.dak\Sample\policy'
    [void][IO.Directory]::CreateDirectory($out)
    return [pscustomobject]@{
        root = $Root; repo = $repo; external = $external; out = $out
        project = Join-Path $repo 'Sample.dproj'
        main_source = Join-Path $repo 'Sample.dpr'
        external_source = Join-Path $external 'External.pas'
    }
}

function Write-MigrationPolicyRun {
    param([Parameter(Mandatory)][object]$Fixture, [string[]]$FindingPaths = @(), [string]$SearchHash = ('1' * 64))
    $out = $Fixture.out
    $rows = foreach ($path in $FindingPaths) {
        [ordered]@{ tool = 'FixInsight'; code = 'W101'; kind = 'W'; file = $path; path = $path
            line = 1; col = 1; message = 'fixture warning' } | ConvertTo-Json -Compress
    }
    $rows = @($rows)
    $topCodes = if ($rows.Count) { "  - W101: $($rows.Count)`n" } else { '' }
    [IO.File]::WriteAllText((Join-Path $out 'summary.md'),
        "# Static analysis`n`n- Timestamp: 2026-07-17T12:00:00Z`n" +
        "- Project: ``$($Fixture.main_source)```n`n## FixInsight`n`n" +
        "- Findings (by code): $($rows.Count)`n$topCodes`n" +
        "## Pascal Analyzer`n`n- Version: 9.21.3`n- Compiler target: Delphi 13 (Win64)`n" +
        "- Totals: warnings=0, strong_warnings=0, optimizations=0, total=0`n")
    [void][IO.Directory]::CreateDirectory((Join-Path $out 'fixinsight'))
    [void][IO.Directory]::CreateDirectory((Join-Path $out 'pascal-analyzer'))
    $jsonl = if ($rows.Count) { ($rows -join "`n") + "`n" } else { '' }
    [IO.File]::WriteAllText((Join-Path $out 'fixinsight\fi-findings.jsonl'), $jsonl)
    [IO.File]::WriteAllText((Join-Path $out 'pascal-analyzer\pal-findings.jsonl'), '')
    [IO.File]::WriteAllText((Join-Path $out 'run.log'),
        "CMD: palcmd.exe `"$($Fixture.main_source)`" /S=`"$(Join-Path $Fixture.repo 'src')`" /CD13W64`n")
    $seed = [ordered]@{
        schema_version = 2
        status = [ordered]@{ infrastructure = 'complete'; policy = 'not_evaluated' }
        subject = [ordered]@{ kind = 'project'; path = $Fixture.main_source; project_file = $Fixture.project }
        compiler = [ordered]@{ delphi = '23.0'; platform = 'Win64'; config = 'Debug'; search_path_sha256 = $SearchHash }
        analyzers = [ordered]@{
            fixinsight = [ordered]@{ requested = $true; status = 'complete'; version = '2023.12'
                options = [ordered]@{ sha256 = ('3' * 64) }; count_quality = 'complete'; runs = @() }
            pascal_analyzer = [ordered]@{ requested = $true; status = 'complete'; version = '9.21.3'
                options = [ordered]@{ sha256 = ('4' * 64) }; count_quality = 'complete'; runs = @() }
        }
        inputs = [ordered]@{ project_sha256 = ('5' * 64); main_source_sha256 = ('6' * 64)
            config_manifests = @([ordered]@{ path = (Join-Path $Fixture.repo 'dak.ini'); sha256 = ('7' * 64) }) }
        policy = [ordered]@{ resolver = 'Dak.Settings'
            values = [ordered]@{ gate_ownership = @('project', 'repository'); project_roots = @(); third_party_roots = @() }
            sources = @((Join-Path $Fixture.repo 'dak.ini')); sha256 = ('2' * 64) }
        errors = @()
        artifacts = [ordered]@{ summary_markdown = 'summary.md' }
    }
    [IO.File]::WriteAllText((Join-Path $out 'summary.json'), ($seed | ConvertTo-Json -Depth 10 -Compress))
}

# The published artifacts, with clocks and engine identity replaced so two engines can be compared.
function Get-MigrationPolicySnapshot {
    param([Parameter(Mandatory)][string]$Root)
    $snapshot = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName -CaseSensitive) {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
        $text = Get-MigrationUtf8Text ([IO.File]::ReadAllBytes($file.FullName))
        if ($relative -cmatch '\.jsonl$') {
            $lines = foreach ($line in [regex]::Split($text, '\r?\n')) {
                if (-not $line.Trim()) { continue }
                ConvertTo-Json -InputObject (Clear-MigrationPolicyVolatile -Value (
                    ConvertFrom-Json -InputObject $line -AsHashtable -NoEnumerate -DateKind String -Depth 100)) -Depth 100 -Compress
            }
            $snapshot[$relative] = @($lines) -join "`n"
        } elseif ($relative -cmatch '\.(json|sarif)$') {
            $snapshot[$relative] = ConvertTo-Json -InputObject (Clear-MigrationPolicyVolatile -Value (
                ConvertFrom-Json -InputObject $text -AsHashtable -NoEnumerate -DateKind String -Depth 100)) -Depth 100 -Compress
        } else {
            $normalized = [regex]::Replace($text, '(?m)^(- (?:Timestamp|Updated): ).*$', '${1}<clock>')
            $snapshot[$relative] = $script:MigrationPolicyFingerprint.Replace($normalized, '<sha256>')
        }
    }
    return $snapshot
}

function Clear-MigrationPolicyVolatile {
    param($Value)
    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($key in $Value.Keys) {
            if ($key -cin @('dak', 'compatibility', 'python')) { continue }
            if ($key -cin $script:MigrationPolicyClockKeys) { $out[$key] = '<clock>'; continue }
            $out[$key] = Clear-MigrationPolicyVolatile -Value $Value[$key]
        }
        return $out
    }
    if ($Value -is [System.Collections.IList] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { Clear-MigrationPolicyVolatile -Value $_ })
    }
    if ($Value -is [string]) { return $script:MigrationPolicyFingerprint.Replace($Value, '<sha256>') }
    return $Value
}

# Git marks its object and pack files read-only, so they are cleared before the tree is removed.
function Remove-MigrationPolicyFixture {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$ScratchRoot)
    [void](Resolve-MigrationOutputPath -Path $Root -Root $ScratchRoot)
    if (-not (Test-Path -LiteralPath $Root)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -Force -File) {
        if ($file.IsReadOnly) { $file.IsReadOnly = $false }
    }
    [IO.Directory]::Delete($Root, $true)
}

function Compare-MigrationPolicySnapshot {
    param([Parameter(Mandatory)]$Reference, [Parameter(Mandatory)]$Candidate)
    $differences = [Collections.Generic.List[string]]::new()
    foreach ($name in $Reference.Keys) {
        if (-not $Candidate.Contains($name)) { $differences.Add("missing: $name"); continue }
        if ($Reference[$name] -cne $Candidate[$name]) { $differences.Add("differs: $name") }
    }
    foreach ($name in $Candidate.Keys) {
        if (-not $Reference.Contains($name)) { $differences.Add("unexpected: $name") }
    }
    return @($differences)
}

function Invoke-MigrationPolicyComparison {
    [CmdletBinding()]
    param([string]$EvidenceRoot, [string]$Executable, [string]$ResultRoot)
    . (Join-Path $PSScriptRoot 'compare-native-analysis-artifacts.ps1')
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $executablePath = Resolve-MigrationOutputPath -Path $Executable -Root $repoRoot
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) { throw 'Missing candidate executable.' }
    $batchRoot = Resolve-MigrationOutputPath $ResultRoot (Join-Path $EvidenceRoot 'measurements')
    if (Test-Path -LiteralPath $batchRoot) { throw 'Policy comparison evidence already exists.' }
    $reference = Join-Path $EvidenceRoot 'python-reference/agentskills/dak-static-analysis/postprocess.py'
    if (-not (Test-Path -LiteralPath $reference -PathType Leaf)) { throw 'Missing pinned Python reference.' }
    $python = (Get-Content -LiteralPath (Join-Path $EvidenceRoot 'corpus/doctor-missing-pal/process.json') -Raw |
        ConvertFrom-Json).executable
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Missing pinned Python interpreter.' }
    $git = (Get-Command git -ErrorAction Stop).Source
    $scratchRoot = Join-Path $EvidenceRoot 'scratch'
    [void][IO.Directory]::CreateDirectory($batchRoot)
    $candidateHash = (Get-FileHash -LiteralPath $executablePath).Hash

    # Each scenario is a list of runs; every run writes the inputs then publishes once.
    $scenarios = @(
        [pscustomobject]@{ name = 'gate-off-creates-baseline'
            runs = @(@{ findings = @(); environment = @{} }) }
        [pscustomobject]@{ name = 'gate-on-clean-passes'
            runs = @(@{ findings = @(); environment = @{} }, @{ findings = @(); environment = @{ DAK_GATE = '1' } }) }
        [pscustomobject]@{ name = 'gate-on-new-owned-fails'
            runs = @(@{ findings = @(); environment = @{} }, @{ findings = @('src/Owned.pas'); environment = @{ DAK_GATE = '1' } }) }
        [pscustomobject]@{ name = 'gate-on-third-party-passes'
            runs = @(@{ findings = @(); environment = @{} }, @{ findings = @('<external>'); environment = @{ DAK_GATE = '1' } }) }
        [pscustomobject]@{ name = 'unknown-ownership-blocks-first-baseline'
            runs = @(@{ findings = @('Missing.pas'); environment = @{ DAK_GATE = '1' } }) }
        [pscustomobject]@{ name = 'accepted-update-replaces-baseline'
            runs = @(@{ findings = @(); environment = @{} },
                     @{ findings = @('src/Owned.pas'); environment = @{ DAK_UPDATE_BASELINE = '1' } }) }
        [pscustomobject]@{ name = 'incompatible-update-preserves-baseline'
            runs = @(@{ findings = @(); environment = @{} },
                     @{ findings = @(); search_hash = ('9' * 64); environment = @{ DAK_GATE = '1'; DAK_UPDATE_BASELINE = '1' } }) }
    )

    $results = foreach ($scenario in $scenarios) {
        $scenarioRoot = Resolve-MigrationOutputPath (Join-Path $batchRoot $scenario.name) $batchRoot
        [void][IO.Directory]::CreateDirectory($scenarioRoot)
        $engines = [ordered]@{}
        foreach ($engine in @('reference', 'candidate')) {
            # Both engines use the same path so the absolute paths inside the artifacts agree.
            $fixtureRoot = Resolve-MigrationOutputPath (Join-Path $scratchRoot ('policy/' + $scenario.name)) $scratchRoot
            Remove-MigrationPolicyFixture -Root $fixtureRoot -ScratchRoot $scratchRoot
            [void][IO.Directory]::CreateDirectory($fixtureRoot)
            try {
                $fixture = New-MigrationPolicyFixture -Root $fixtureRoot -GitExecutable $git
                $exits = @()
                $index = 0
                foreach ($run in $scenario.runs) {
                    $index++
                    $paths = @($run.findings | ForEach-Object {
                        if ($_ -ceq '<external>') { $fixture.external_source } else { $_ } })
                    $hash = if ($run.search_hash) { $run.search_hash } else { ('1' * 64) }
                    Write-MigrationPolicyRun -Fixture $fixture -FindingPaths $paths -SearchHash $hash
                    $environment = Get-MigrationWorkspaceEnvironment
                    $environment.DAK_BASELINE = Join-Path $fixture.out 'baseline.json'
                    foreach ($name in @('DAK_GATE', 'DAK_CI', 'DAK_UPDATE_BASELINE')) { $environment[$name] = '0' }
                    foreach ($name in $run.environment.Keys) { $environment[$name] = $run.environment[$name] }
                    $arguments = if ($engine -eq 'reference') { @($reference, $fixture.out) }
                        else { @('analyze-report', '--out', $fixture.out) }
                    $tool = if ($engine -eq 'reference') { $python } else { $executablePath }
                    $process = Invoke-MigrationProcess -Executable $tool -Arguments $arguments `
                        -WorkingDirectory $fixture.repo -Environment $environment `
                        -LogPath (Join-Path $scenarioRoot "$engine-run$index")
                    if ($process.timed_out -or $process.drain_timed_out) { throw "Policy run did not complete: $($scenario.name)/$engine" }
                    $exits += $process.exit_code
                }
                $engines[$engine] = [pscustomobject]@{
                    exits = @($exits)
                    snapshot = Get-MigrationPolicySnapshot -Root $fixture.out
                }
            } finally {
                Remove-MigrationPolicyFixture -Root $fixtureRoot -ScratchRoot $scratchRoot
            }
        }
        $differences = Compare-MigrationPolicySnapshot -Reference $engines.reference.snapshot -Candidate $engines.candidate.snapshot
        $exitsEqual = ($engines.reference.exits -join ',') -ceq ($engines.candidate.exits -join ',')
        $record = [pscustomobject]@{
            name = $scenario.name
            reference_exits = $engines.reference.exits
            candidate_exits = $engines.candidate.exits
            exits_equal = $exitsEqual
            artifact_differences = $differences
            artifacts = @($engines.reference.snapshot.Keys)
        }
        $record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $scenarioRoot 'comparison.json')
        # Retain both normalized snapshots whenever they disagree, so the difference is inspectable.
        if ($differences.Count) {
            foreach ($engine in @('reference', 'candidate')) {
                $snapshotRoot = Join-Path $scenarioRoot "$engine-snapshot"
                [void][IO.Directory]::CreateDirectory($snapshotRoot)
                foreach ($name in $engines[$engine].snapshot.Keys) {
                    $target = Join-Path $snapshotRoot ($name -replace '/', '__')
                    [IO.File]::WriteAllText($target, [string]$engines[$engine].snapshot[$name])
                }
            }
        }
        if (-not $exitsEqual) {
            throw "Policy exit mismatch: $($scenario.name): reference=$($engines.reference.exits -join ',') candidate=$($engines.candidate.exits -join ',')"
        }
        if ($differences.Count) {
            throw "Policy artifacts differ: $($scenario.name): $($differences -join ', ')"
        }
        $record
    }
    if ((Get-FileHash -LiteralPath $executablePath).Hash -ne $candidateHash) { throw 'Candidate executable changed during comparison.' }
    $result = [pscustomobject]@{
        passed = $true; candidate = $executablePath; candidate_sha256 = $candidateHash
        reference = $reference; python = $python; scenarios = @($results)
        scope = ('Policy decisions and published artifacts compared run for run against the pinned Python ' +
                 'reference on identical fresh fixtures; clocks and engine identity are excluded. ' +
                 'No performance acceptance.')
    }
    $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $batchRoot 'comparison.json')
    return $result
}
