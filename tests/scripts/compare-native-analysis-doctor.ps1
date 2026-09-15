#Requires -Version 7.0
function Get-MigrationDoctorEnvironment {
    $environment = @{}
    foreach ($key in [Environment]::GetEnvironmentVariables().Keys) {
        if ([string]$key -match '^(DAK_|PA_|FI_|FIXINSIGHT_|PYTHON|WSL|GIT_)') { $environment[$key]=$null }
    }
    $environment.PATH = Join-Path $env:SystemRoot 'System32'
    $environment.PYTHONDONTWRITEBYTECODE='1'
    $environment.PYTHONIOENCODING='utf-8'
    $environment.PYTHONUTF8='1'
    $environment.MAXLOGIC_MADEXCEPT_AI='1'
    $environment.DAK_DOCTOR_RUN='1'
    $environment.DAK_DELPHI='23.0'
    $environment.DAK_PLATFORM='Win64'
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $environment.DAK_MAXTDB_FIXTURE = Join-Path $repoRoot 'tests/fixtures/test-projects/semantic-isolated-t311/maxTdb'
    $environment.DAK_TEST_OUTPUT_ROOT = $null
    return $environment
}

function Read-MigrationDoctorValue {
    param([hashtable]$Reader, [string]$Key, [string]$Pattern = '.*')
    if ($Reader.index -ge $Reader.lines.Count) { throw "Doctor omitted $Key." }
    $line = $Reader.lines[$Reader.index++]
    if ($line -cnotmatch ('^' + [regex]::Escape($Key) + ': (' + $Pattern + ')$')) {
        throw "Unexpected or reordered Doctor field: $line; expected $Key."
    }
    $value = $Matches[1]
    $Reader.values[$Key] = $value
    return $value
}

function Invoke-MigrationDoctorComparison {
    [CmdletBinding()]
    param([string]$EvidenceRoot, [string]$Executable, [string]$ResultRoot)
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $candidate = Resolve-MigrationOutputPath $Executable $repoRoot
    $batch = Resolve-MigrationOutputPath $ResultRoot (Join-Path $EvidenceRoot 'measurements')
    if (Test-Path -LiteralPath $batch) { throw 'Doctor comparison evidence already exists.' }
    $referenceRoot = Join-Path $EvidenceRoot 'python-reference'
    $manifestPath = Join-Path $EvidenceRoot 'reference-manifest.json'
    $referenceManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $inputsPath = Join-Path $EvidenceRoot 'baseline-inputs-v3.json'
    $baselinePath = Join-Path $EvidenceRoot 'scenarios.json'
    $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
    if ($baseline.input_manifest -cne 'baseline-inputs-v3.json' -or
        (Get-FileHash -LiteralPath $inputsPath).Hash -ine $baseline.input_manifest_sha256) { throw 'Frozen Doctor input manifest hash mismatch.' }
    $inputs = Get-Content -LiteralPath $inputsPath -Raw | ConvertFrom-Json
    $corpusRoot = Join-Path $EvidenceRoot 'corpus/doctor-missing-pal'
    $corpus = Get-Content -LiteralPath (Join-Path $corpusRoot 'process.json') -Raw | ConvertFrom-Json
    $python = $corpus.executable
    $palEntries = @($inputs.files | Where-Object { [IO.Path]::GetFileName($_.path) -ieq 'palcmd.exe' })
    if ($palEntries.Count -ne 1) { throw 'Expected one pinned real PAL executable.' }
    $pal = $palEntries[0].path
    $corpusText = Get-Content -LiteralPath (Join-Path $corpusRoot 'process.stdout') -Raw
    if ($corpusText -notmatch '(?m)^- PA_PATH=(.+)\r?$') { throw 'Missing retained unavailable PAL input.' }
    $missingPal = $Matches[1].TrimEnd("`r")
    if (Test-Path -LiteralPath $missingPal) { throw 'Retained missing PAL path now exists.' }
    $inputHashes = [ordered]@{}
    foreach ($path in @($candidate, $manifestPath, $inputsPath, $baselinePath, (Join-Path $corpusRoot 'process.json'),
        (Join-Path $corpusRoot 'process.stdout'), (Join-Path $corpusRoot 'process.stderr'), $corpus.arguments[1],
        (Join-Path ([IO.Path]::GetDirectoryName($candidate)) 'palcmd-map.json'), $python, $pal)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required real Doctor input: $path" }
        $inputHashes[$path]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    foreach ($path in @($python,$pal,$manifestPath,$corpus.arguments[1],(Join-Path $corpusRoot 'process.json'),
        (Join-Path $corpusRoot 'process.stdout'),(Join-Path $corpusRoot 'process.stderr'))) {
        $pinned = @($inputs.files | Where-Object path -EQ $path)
        if ($pinned.Count -ne 1 -or $inputHashes[$path] -ine $pinned[0].sha256) { throw "Pinned executable changed: $path" }
    }
    foreach ($file in $referenceManifest.files) {
        $path = Resolve-MigrationOutputPath (Join-Path $referenceRoot $file.path) $referenceRoot
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($hash -ine $file.sha256) { throw "Pinned Python reference changed: $path" }
        $inputHashes[$path]=$hash
    }
    $environment = Get-MigrationDoctorEnvironment
    [void][IO.Directory]::CreateDirectory($batch)
    $stage = Resolve-MigrationOutputPath (Join-Path $batch 'inputs') $batch
    [void][IO.Directory]::CreateDirectory($stage)
    $stagedExecutable = Join-Path $stage 'DelphiAIKit.exe'
    Copy-Item -LiteralPath $candidate -Destination $stagedExecutable
    $subject = Join-Path $stage ([IO.Path]::GetFileName($corpus.arguments[1]))
    Copy-Item -LiteralPath $corpus.arguments[1] -Destination $subject
    $map = Join-Path $stage 'palcmd-map.json'
    Copy-Item -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($candidate)) 'palcmd-map.json') -Destination $map
    foreach ($path in @($stagedExecutable,$subject,$map)) { $inputHashes[$path]=(Get-FileHash -LiteralPath $path).Hash }
    $configuredStage = Resolve-MigrationOutputPath (Join-Path $batch 'configured-inputs') $batch
    [void][IO.Directory]::CreateDirectory($configuredStage)
    foreach ($path in @($stagedExecutable,$subject,$map)) {
        $destination = Join-Path $configuredStage ([IO.Path]::GetFileName($path))
        Copy-Item -LiteralPath $path -Destination $destination
        $inputHashes[$destination]=(Get-FileHash -LiteralPath $destination).Hash
    }
    $ini = Join-Path $configuredStage 'dak.ini'
    # Explicit canonical spellings make Python's raw preview and native effective values comparable.
    # Neither interpreter invents omitted defaults; optional FI is discovery only.
    $settingsText = @"
[FixInsightCL]
Silent=true
Settings=doctor-settings.ficfg
[FixInsightIgnore]
Warnings=W502;C101
[ReportFilter]
ExcludePathMasks=*vendor*;*generated*
[PascalAnalyzerIgnore]
Rules=PAL.Warnings.UnusedLocalVariables
[PascalAnalyzer]
Path=$pal
Args=/W2
[AnalysisPolicy]
GateOwnership=project;repository
ProjectRoots=$configuredStage
ThirdPartyRoots=$(Join-Path $configuredStage 'vendor')
[Diagnostics]
IgnoreUnknownMacros=DOCTOR_MACRO
IgnoreMissingPaths=*optional*
"@
    [IO.File]::WriteAllText($ini, $settingsText)
    $inputHashes[$ini]=(Get-FileHash -LiteralPath $ini).Hash
    $environment.DAK_EXE=$stagedExecutable
    $environment.TEMP=Join-Path $batch 'process-temp'
    $environment.TMP=$environment.TEMP
    [void][IO.Directory]::CreateDirectory($environment.TEMP)
    $receipt = [ordered]@{candidate=$candidate;input_sha256=$inputHashes;environment=$environment;scope='Doctor correctness only; no frozen performance budget or JSON parity.'}
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $batch 'inputs.json')
    $results = foreach ($scenario in @(@{name='supported-pal';path=$pal;exit=0;stage=$stage;settings=$false},
        @{name='missing-pal';path=$missingPal;exit=3;stage=$stage;settings=$false},
        @{name='configured-pal';path=$pal;exit=0;stage=$configuredStage;settings=$true})) {
        $scenarioRoot = Join-Path $batch $scenario.name
        [void][IO.Directory]::CreateDirectory($scenarioRoot)
        $environment.PA_PATH=$scenario.path
        $scenarioExecutable = Join-Path $scenario.stage 'DelphiAIKit.exe'
        $scenarioSubject = Join-Path $scenario.stage ([IO.Path]::GetFileName($subject))
        $environment.DAK_EXE=$scenarioExecutable
        $environment | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $scenarioRoot 'environment.json')
        $reference = Invoke-MigrationProcess -Executable $python -Arguments @('-I','-B', (Join-Path $referenceRoot 'agentskills/dak-static-analysis/doctor.py'),$scenarioSubject,'--workspace-root','project') `
            -WorkingDirectory $scenario.stage -Environment $environment -LogPath (Join-Path $scenarioRoot 'reference')
        $native = Invoke-MigrationProcess -Executable $scenarioExecutable -Arguments @('analyze-doctor','--project',$scenarioSubject,'--workspace-root','project') `
            -WorkingDirectory $scenario.stage -Environment $environment -LogPath (Join-Path $scenarioRoot 'native')
        $streams = [ordered]@{}
        foreach ($name in @('reference','native')) {
            foreach ($extension in @('stdout','stderr','json')) {
                $path = Join-Path $scenarioRoot ($name+'.'+$extension)
                $streams[$name+'.'+$extension]=(Get-FileHash -LiteralPath $path).Hash
            }
        }
        $streams | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $scenarioRoot 'streams-sha256.json')
        foreach ($record in @($reference,$native)) {
            if ($record.exit_code -ne $scenario.exit -or $record.timed_out -or $record.drain_timed_out) { throw 'Doctor process failed; raw evidence retained.' }
        }
        foreach ($name in @('reference','native')) {
            if ([IO.File]::ReadAllText((Join-Path $scenarioRoot ($name+'.stderr'))) -cne '') { throw 'Unexpected Doctor stderr; raw evidence retained.' }
        }
        $comparison = Compare-MigrationDoctor -ReferenceText ([IO.File]::ReadAllText((Join-Path $scenarioRoot 'reference.stdout'))) `
            -CandidateText ([IO.File]::ReadAllText((Join-Path $scenarioRoot 'native.stdout'))) -ExitCode $scenario.exit -Settings:$scenario.settings
        if ($comparison.reference_only['- DAK_EXE:'] -cne $scenarioExecutable -or
            $comparison.reference_only['- Skill dir:'] -cne (Join-Path $referenceRoot 'agentskills/dak-static-analysis').Replace('/','\')) {
            throw 'Python used an unexpected executable or reference location.'
        }
        $comparison | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $scenarioRoot 'comparison.json')
        [pscustomobject]@{name=$scenario.name;comparison=$comparison;streams_sha256=$streams}
    }
    foreach ($path in $inputHashes.Keys) {
        if ((Get-FileHash -LiteralPath $path).Hash -cne $inputHashes[$path]) { throw "Doctor input changed during comparison: $path" }
    }
    foreach ($directory in @($stage,$configuredStage)) {
        $expectedFiles = @($inputHashes.Keys | Where-Object { [IO.Path]::GetDirectoryName($_) -eq $directory } | Sort-Object)
        $actualFiles = @(Get-ChildItem -LiteralPath $directory -Force -File -Recurse | ForEach-Object FullName | Sort-Object)
        if (($actualFiles -join "`n") -cne ($expectedFiles -join "`n") -or
            @(Get-ChildItem -LiteralPath $directory -Force -Directory).Count -ne 0) { throw 'Doctor created unexpected staged output.' }
    }
    if (Test-Path -LiteralPath $missingPal) { throw 'Missing PAL input was created during comparison.' }
    $result = [pscustomobject]@{passed=$true;inputs=$receipt;scenarios=@($results)}
    $result | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $batch 'comparison.json')
    return $result
}

function Read-MigrationDoctorArray {
    param([hashtable]$Reader, [string]$Key)
    $values = [Collections.Generic.List[string]]::new()
    if ($Reader.lines[$Reader.index] -ceq ($Key + ': []')) {
        [void](Read-MigrationDoctorValue $Reader $Key '\[\]')
    } else {
        while ($Reader.index -lt $Reader.lines.Count -and $Reader.lines[$Reader.index].StartsWith($Key+'[')) {
            $values.Add((Read-MigrationDoctorValue $Reader ($Key+'['+($values.Count+1)+']')))
        }
        if ($values.Count -eq 0) { throw "Doctor omitted array $Key." }
    }
    return ,$values.ToArray()
}

function Compare-MigrationDoctor {
    [CmdletBinding()]
    param([string]$ReferenceText, [string]$CandidateText, [ValidateSet(0,3)][int]$ExitCode, [switch]$Settings)
    # This grammar is deliberately limited to our isolated Win64 scenarios.
    # It reads human output, never synthesizes Python JSON or implements tool discovery.
    $lines = @($CandidateText.Replace("`r`n", "`n").TrimEnd("`n").Split("`n"))
    if ($lines[0] -cne 'Delphi static analysis doctor') { throw 'Unknown native Doctor banner.' }
    $reader = @{lines=$lines;index=1;values=[ordered]@{}}
    [void](Read-MigrationDoctorValue $reader 'mode' 'checks')
    $iniPath = ''
    if ($Settings) { $iniPath = Read-MigrationDoctorValue $reader 'settings.files[1]' '.+' }
    else { [void](Read-MigrationDoctorValue $reader 'settings.files' '\[\]') }
    $root = Read-MigrationDoctorValue $reader 'settings.workspace.root' '.+'
    [void](Read-MigrationDoctorValue $reader 'settings.workspace.selector' 'project')
    [void](Read-MigrationDoctorValue $reader 'settings.workspace.vcs' 'none')
    [void](Read-MigrationDoctorValue $reader 'settings.workspace.source' 'command_line')
    foreach ($key in @('fixinsight.silent','fixinsight.settings','report_filter.exclude_path_masks','fixinsight_ignore.warnings',
        'pascal_analyzer.path','pascal_analyzer.args','pascal_analyzer.exclude_search_folders','pascal_analyzer.exclude_files',
        'diagnostics.ignore_unknown_macros','diagnostics.ignore_missing_paths')) {
        [void](Read-MigrationDoctorValue $reader ('settings.resolved.'+$key))
    }
    $policy = @{}
    foreach ($key in @('gate_ownership','gate_metrics','project_roots','third_party_roots','pal_ignore_rules','sources','origins.pal_ignore_rules')) {
        $policy[$key] = Read-MigrationDoctorArray $reader ('settings.resolved.analysis_policy.'+$key)
    }
    [void](Read-MigrationDoctorValue $reader 'settings.resolved.analysis_policy.sha256' '[A-Fa-f0-9]{64}')
    if ($Settings) {
        foreach ($key in @('FixInsightCL.Settings','FixInsightCL.Silent','FixInsightIgnore.Warnings','PascalAnalyzerIgnore.Rules',
            'ReportFilter.ExcludePathMasks','PascalAnalyzer.Path','PascalAnalyzer.Args','Diagnostics.IgnoreUnknownMacros',
            'Diagnostics.IgnoreMissingPaths','AnalysisPolicy.GateOwnership','AnalysisPolicy.ProjectRoots','AnalysisPolicy.ThirdPartyRoots')) {
            $origin = if ($key -ceq 'PascalAnalyzer.Path') { 'PA_PATH environment variable' } else { $iniPath }
            [void](Read-MigrationDoctorValue $reader ('settings.origins.'+$key+'[1]') ([regex]::Escape($origin)))
        }
    } else { [void](Read-MigrationDoctorValue $reader 'settings.origins.PascalAnalyzer.Path[1]' 'PA_PATH environment variable') }
    [void](Read-MigrationDoctorValue $reader 'settings.environment.DAK_DELPHI' '23\.0')
    [void](Read-MigrationDoctorValue $reader 'settings.environment.DAK_PLATFORM' 'Win64')
    $pal = Read-MigrationDoctorValue $reader 'settings.environment.PA_PATH' '.+'
    if ($reader.values['settings.resolved.pascal_analyzer.path'] -cne $pal) { throw 'Effective PAL path differs from explicit environment.' }
    [void](Read-MigrationDoctorValue $reader 'checks[1].name' 'fixinsight')
    [void](Read-MigrationDoctorValue $reader 'checks[1].source' 'PATH/registry discovery')
    [void](Read-MigrationDoctorValue $reader 'checks[1].path')
    [void](Read-MigrationDoctorValue $reader 'checks[1].status' 'available|unavailable')
    [void](Read-MigrationDoctorValue $reader 'checks[2].name' 'compiler')
    [void](Read-MigrationDoctorValue $reader 'checks[2].kind' 'configuration')
    [void](Read-MigrationDoctorValue $reader 'checks[2].bds_version' '23\.0')
    [void](Read-MigrationDoctorValue $reader 'checks[2].platform' 'Win64')
    $compiler = Read-MigrationDoctorValue $reader 'checks[2].status' 'available|unavailable'
    if ($compiler -eq 'available') {
        [void](Read-MigrationDoctorValue $reader 'checks[2].library_path')
        [void](Read-MigrationDoctorValue $reader 'checks[2].source' 'registry|env_options')
    } else { [void](Read-MigrationDoctorValue $reader 'checks[2].error' '.+') }
    [void](Read-MigrationDoctorValue $reader 'checks[3].name' 'pal_path')
    $tail = [Collections.Generic.List[string]]::new()
    if ($ExitCode -eq 3) {
        [void](Read-MigrationDoctorValue $reader 'checks[3].status' 'unavailable')
        $diagnostic = Read-MigrationDoctorValue $reader 'diagnostics[1]' ([regex]::Escape('PALCMD executable not found at: '+$pal))
        $tail.Add('ERROR: '+$diagnostic)
    } else {
        [void](Read-MigrationDoctorValue $reader 'checks[3].status' 'available')
        [void](Read-MigrationDoctorValue $reader 'checks[3].path' ([regex]::Escape($pal)))
        [void](Read-MigrationDoctorValue $reader 'checks[4].name' 'pal_help')
        [void](Read-MigrationDoctorValue $reader 'checks[4].timeout_seconds' '[1-9][0-9]*')
        [void](Read-MigrationDoctorValue $reader 'checks[4].exit_code' '0')
        [void](Read-MigrationDoctorValue $reader 'checks[4].timed_out' 'false')
        $version = Read-MigrationDoctorValue $reader 'checks[4].version' '[0-9.]+'
        $architecture = Read-MigrationDoctorValue $reader 'checks[4].architecture' '(32|64)-bit'
        [void](Read-MigrationDoctorValue $reader 'checks[4].help_available' 'true')
        $flags = Read-MigrationDoctorArray $reader 'checks[4].supported_flags'
        $known = @('/CD12W32','/CD12W64','/CD13W32','/CD13W64')
        if (($flags -join ';') -cne (@($known | Where-Object { $_ -cin $flags }) -join ';')) { throw 'Unknown, duplicate or reordered PAL flags.' }
        [void](Read-MigrationDoctorValue $reader 'checks[4].status' 'available')
        [void](Read-MigrationDoctorValue $reader 'checks[5].name' 'pal_target')
        [void](Read-MigrationDoctorValue $reader 'checks[5].bds_version' '23\.0')
        [void](Read-MigrationDoctorValue $reader 'checks[5].platform' 'Win64')
        $delphi = Read-MigrationDoctorValue $reader 'checks[5].delphi' '12'
        $flag = Read-MigrationDoctorValue $reader 'checks[5].flag' '/CD12W64'
        [void](Read-MigrationDoctorValue $reader 'checks[5].status' 'supported')
        if ($flag -cnotin $flags) { throw 'Supported requested flag missing from help.' }
        [void](Read-MigrationDoctorValue $reader 'diagnostics' '\[\]')
        $tail.Add('- Executable: '+$pal)
        $tail.Add('- Architecture: '+$architecture)
        $tail.Add('- Version: '+$version)
        $tail.Add('- Help: available')
        # The reference displays exactly these two Win64 help rows, in this order.
        foreach ($label in @('12','13')) {
            $status = if ('/CD'+$label+'W64' -cin $flags) { 'supported (/CD'+$label+'W64)' } else { 'not listed by PAL help' }
            $tail.Add('- Delphi '+$label+' Win64: '+$status)
        }
        $tail.Add('- Requested target: Delphi '+$delphi+' Win64: supported ('+$flag+')')
    }
    $subject = Read-MigrationDoctorValue $reader 'subject.path' '.+'
    $exists = Read-MigrationDoctorValue $reader 'subject.exists' 'true'
    $output = Read-MigrationDoctorValue $reader 'subject.output_root' '.+'
    [void](Read-MigrationDoctorValue $reader 'exit_code' ([string]$ExitCode))
    if ($reader.index -ne $reader.lines.Count) { throw 'Unknown trailing native Doctor content.' }
    $referenceLines = @($ReferenceText.Replace("`r`n","`n").TrimEnd("`n").Split("`n") | Where-Object { $_ -cne '' })
    $referenceOnly = [ordered]@{}
    $shared = [Collections.Generic.List[string]]::new()
    foreach ($line in $referenceLines) {
        if ($line -cmatch '^(- (?:Python|Platform|WSL|Skill dir|CWD|DAK_EXE|DelphiAIKit.exe|where FixInsightCL.exe|where PALCMD.exe):) (.+)$') {
            if ($referenceOnly.Contains($Matches[1])) { throw 'Duplicate reference metadata.' }
            $referenceOnly[$Matches[1]]=$Matches[2]
            $shared.Add($Matches[1]+' <reference-only>')
        } else { $shared.Add($line) }
    }
    $settingsPreview = @()
    if ($Settings) {
        $settingsPreview += '## dak.ini (high-signal)'
        foreach ($mapping in @(
            @('FixInsightCL.Silent','fixinsight.silent'),@('FixInsightCL.Settings','fixinsight.settings'),
            @('ReportFilter.ExcludePathMasks','report_filter.exclude_path_masks'),@('FixInsightIgnore.Warnings','fixinsight_ignore.warnings'))) {
            $settingsPreview += '- '+$mapping[0]+'='+$reader.values['settings.resolved.'+$mapping[1]]
        }
        $settingsPreview += '- PascalAnalyzerIgnore.Rules='+($policy.pal_ignore_rules -join ';')
        $settingsPreview += '- PascalAnalyzer.Path='+$reader.values['settings.resolved.pascal_analyzer.path']
        $settingsPreview += '- PascalAnalyzer.Args='+$reader.values['settings.resolved.pascal_analyzer.args']
        $settingsPreview += '- AnalysisPolicy.GateOwnership='+($policy.gate_ownership -join ';')
        $settingsPreview += '- AnalysisPolicy.ProjectRoots='+($policy.project_roots -join ';')
        $settingsPreview += '- AnalysisPolicy.ThirdPartyRoots='+($policy.third_party_roots -join ';')
        $settingsPreview += '- AnalysisPolicy.Sources='+($policy.sources -join ', ')
        $settingsPreview += '- Diagnostics.IgnoreUnknownMacros='+$reader.values['settings.resolved.diagnostics.ignore_unknown_macros']
        $settingsPreview += '- Diagnostics.IgnoreMissingPaths='+$reader.values['settings.resolved.diagnostics.ignore_missing_paths']
        $settingsPreview += '- PascalAnalyzer.Path exists: True ('+$pal+')'
    }
    $iniDisplay = if ($Settings) { $iniPath } else { '<missing>' }
    $expected = @(
        '# Delphi static analysis doctor','- Python: <reference-only>','- Platform: <reference-only>',
        '- WSL: <reference-only>','- Skill dir: <reference-only>','- CWD: <reference-only>',
        '## Resolver','- DAK_EXE: <reference-only>','- DelphiAIKit.exe: <reference-only>',
        '- Workspace selector: project',('- Workspace root: '+$root),'- Workspace VCS: none','- Workspace source: command_line',
        ('- dak.ini: '+$iniDisplay)
    ) + $settingsPreview + @('## Run options (env)','- DAK_DELPHI=23.0','- DAK_PLATFORM=Win64',('- PA_PATH='+$pal),
        '## Target',('- Path: '+$subject),('- Exists: '+$exists.Substring(0,1).ToUpperInvariant()+$exists.Substring(1)),
        ('- Output root: '+$output),'- Parity check: after a run, inspect `run.log` for FixInsightCL args (`--libpath`, `--unitscopes`).',
        '## Optional discovery checks (DAK_DOCTOR_RUN)','- where FixInsightCL.exe: <reference-only>',
        '- where PALCMD.exe: <reference-only>','## Pascal Analyzer'
    ) + $tail.ToArray()
    if (($shared -join "`n") -cne ($expected -join "`n")) { throw 'Shared Doctor output differs, is omitted, unknown or reordered.' }
    if ($referenceOnly['- WSL:'] -cne 'False' -or $referenceOnly['- CWD:'] -cne $root -or
        $referenceOnly['- DAK_EXE:'] -cne $referenceOnly['- DelphiAIKit.exe:']) { throw 'Reference execution context differs.' }
    foreach ($key in @('- where FixInsightCL.exe:','- where PALCMD.exe:')) {
        if ($referenceOnly[$key] -cnotmatch '^exit=[0-9]+ .+$') { throw 'Invalid reference where diagnostic.' }
    }
    return [pscustomobject]@{
        passed=$true;exit_code=$ExitCode;shared=@($shared);reference_only=$referenceOnly;native_fields=$reader.values
        projection_contract='Windows project checks, with and without explicit INI. All shared human records retain order and exact values. Reference runtime/banner, DAK location and where diagnostics are retained separately; native defaults omitted by Python, per-setting origins, policy hash/metrics, PAL exclusion controls, FI/compiler discovery, help timing and Win32 flags have no Python human counterpart. Native JSON is separately tested, not compared here.'
    }
}
