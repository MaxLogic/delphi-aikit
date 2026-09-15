#Requires -Version 7.0
BeforeAll {
    . (Join-Path $PSScriptRoot 'verify-native-analysis-migration.ps1')
    . (Join-Path $PSScriptRoot 'compare-native-analysis-doctor.ps1')
    $script:Native = @'
Delphi static analysis doctor
mode: checks
settings.files: []
settings.workspace.root: C:\case
settings.workspace.selector: project
settings.workspace.vcs: none
settings.workspace.source: command_line
settings.resolved.fixinsight.silent: false
settings.resolved.fixinsight.settings: 
settings.resolved.report_filter.exclude_path_masks: 
settings.resolved.fixinsight_ignore.warnings: 
settings.resolved.pascal_analyzer.path: C:\missing\palcmd.exe
settings.resolved.pascal_analyzer.args: 
settings.resolved.pascal_analyzer.exclude_search_folders: 
settings.resolved.pascal_analyzer.exclude_files: 
settings.resolved.diagnostics.ignore_unknown_macros: 
settings.resolved.diagnostics.ignore_missing_paths: 
settings.resolved.analysis_policy.gate_ownership[1]: project
settings.resolved.analysis_policy.gate_ownership[2]: repository
settings.resolved.analysis_policy.gate_metrics: []
settings.resolved.analysis_policy.project_roots: []
settings.resolved.analysis_policy.third_party_roots: []
settings.resolved.analysis_policy.pal_ignore_rules: []
settings.resolved.analysis_policy.sources: []
settings.resolved.analysis_policy.origins.pal_ignore_rules: []
settings.resolved.analysis_policy.sha256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
settings.origins.PascalAnalyzer.Path[1]: PA_PATH environment variable
settings.environment.DAK_DELPHI: 23.0
settings.environment.DAK_PLATFORM: Win64
settings.environment.PA_PATH: C:\missing\palcmd.exe
checks[1].name: fixinsight
checks[1].source: PATH/registry discovery
checks[1].path: 
checks[1].status: unavailable
checks[2].name: compiler
checks[2].kind: configuration
checks[2].bds_version: 23.0
checks[2].platform: Win64
checks[2].status: unavailable
checks[2].error: configuration missing
checks[3].name: pal_path
checks[3].status: unavailable
diagnostics[1]: PALCMD executable not found at: C:\missing\palcmd.exe
subject.path: C:\case\sample.dproj
subject.exists: true
subject.output_root: C:\case\.dak\sample
exit_code: 3
'@
    $script:Reference = @'
# Delphi static analysis doctor

- Python: 3.13.15
- Platform: Windows-11
- WSL: False
- Skill dir: C:\reference
- CWD: C:\case

## Resolver
- DAK_EXE: C:\case\DelphiAIKit.exe
- DelphiAIKit.exe: C:\case\DelphiAIKit.exe
- Workspace selector: project
- Workspace root: C:\case
- Workspace VCS: none
- Workspace source: command_line
- dak.ini: <missing>

## Run options (env)
- DAK_DELPHI=23.0
- DAK_PLATFORM=Win64
- PA_PATH=C:\missing\palcmd.exe

## Target
- Path: C:\case\sample.dproj
- Exists: True
- Output root: C:\case\.dak\sample
- Parity check: after a run, inspect `run.log` for FixInsightCL args (`--libpath`, `--unitscopes`).

## Optional discovery checks (DAK_DOCTOR_RUN)
- where FixInsightCL.exe: exit=1 INFO: Could not find files for the given pattern(s).
- where PALCMD.exe: exit=1 INFO: Could not find files for the given pattern(s).

## Pascal Analyzer
ERROR: PALCMD executable not found at: C:\missing\palcmd.exe
'@
    $nativeSuccess = @'
checks[3].status: available
checks[3].path: C:\missing\palcmd.exe
checks[4].name: pal_help
checks[4].timeout_seconds: 15
checks[4].exit_code: 0
checks[4].timed_out: false
checks[4].version: 9.13.1.0
checks[4].architecture: 64-bit
checks[4].help_available: true
checks[4].supported_flags[1]: /CD12W32
checks[4].supported_flags[2]: /CD12W64
checks[4].status: available
checks[5].name: pal_target
checks[5].bds_version: 23.0
checks[5].platform: Win64
checks[5].delphi: 12
checks[5].flag: /CD12W64
checks[5].status: supported
diagnostics: []
subject.path: C:\case\sample.dproj
subject.exists: true
subject.output_root: C:\case\.dak\sample
exit_code: 0
'@
    $referenceSuccess = @'
- Executable: C:\missing\palcmd.exe
- Architecture: 64-bit
- Version: 9.13.1.0
- Help: available
- Delphi 12 Win64: supported (/CD12W64)
- Delphi 13 Win64: not listed by PAL help
- Requested target: Delphi 12 Win64: supported (/CD12W64)
'@
    $script:NativeSuccess = $script:Native.Substring(0,$script:Native.IndexOf('checks[3].status:'))+$nativeSuccess
    $script:ReferenceSuccess = $script:Reference.Substring(0,$script:Reference.IndexOf('ERROR:'))+$referenceSuccess
    $script:NativeSettings = $script:NativeSuccess.Replace('settings.files: []','settings.files[1]: C:\case\dak.ini')
    $replacements = [ordered]@{
        'fixinsight.silent: false'='fixinsight.silent: true'
        'fixinsight.settings: '='fixinsight.settings: doctor-settings.ficfg'
        'report_filter.exclude_path_masks: '='report_filter.exclude_path_masks: *vendor*;*generated*'
        'fixinsight_ignore.warnings: '='fixinsight_ignore.warnings: W502;C101'
        'pascal_analyzer.args: '='pascal_analyzer.args: /W2'
        'diagnostics.ignore_unknown_macros: '='diagnostics.ignore_unknown_macros: DOCTOR_MACRO'
        'diagnostics.ignore_missing_paths: '='diagnostics.ignore_missing_paths: *optional*'
        'analysis_policy.project_roots: []'='analysis_policy.project_roots[1]: C:\case'
        'analysis_policy.third_party_roots: []'='analysis_policy.third_party_roots[1]: C:\case\vendor'
        'analysis_policy.pal_ignore_rules: []'='analysis_policy.pal_ignore_rules[1]: PAL.Warnings.UnusedLocalVariables'
        'analysis_policy.sources: []'='analysis_policy.sources[1]: C:\case\dak.ini'
        'analysis_policy.origins.pal_ignore_rules: []'='analysis_policy.origins.pal_ignore_rules[1]: C:\case\dak.ini'
    }
    foreach ($key in $replacements.Keys) { $script:NativeSettings=$script:NativeSettings.Replace($key,$replacements[$key]) }
    $originLines = @'
settings.origins.FixInsightCL.Settings[1]: C:\case\dak.ini
settings.origins.FixInsightCL.Silent[1]: C:\case\dak.ini
settings.origins.FixInsightIgnore.Warnings[1]: C:\case\dak.ini
settings.origins.PascalAnalyzerIgnore.Rules[1]: C:\case\dak.ini
settings.origins.ReportFilter.ExcludePathMasks[1]: C:\case\dak.ini
settings.origins.PascalAnalyzer.Path[1]: PA_PATH environment variable
settings.origins.PascalAnalyzer.Args[1]: C:\case\dak.ini
settings.origins.Diagnostics.IgnoreUnknownMacros[1]: C:\case\dak.ini
settings.origins.Diagnostics.IgnoreMissingPaths[1]: C:\case\dak.ini
settings.origins.AnalysisPolicy.GateOwnership[1]: C:\case\dak.ini
settings.origins.AnalysisPolicy.ProjectRoots[1]: C:\case\dak.ini
settings.origins.AnalysisPolicy.ThirdPartyRoots[1]: C:\case\dak.ini
'@
    $script:NativeSettings=$script:NativeSettings.Replace('settings.origins.PascalAnalyzer.Path[1]: PA_PATH environment variable',$originLines)
    $preview = @'
- dak.ini: C:\case\dak.ini

## dak.ini (high-signal)
- FixInsightCL.Silent=true
- FixInsightCL.Settings=doctor-settings.ficfg
- ReportFilter.ExcludePathMasks=*vendor*;*generated*
- FixInsightIgnore.Warnings=W502;C101
- PascalAnalyzerIgnore.Rules=PAL.Warnings.UnusedLocalVariables
- PascalAnalyzer.Path=C:\missing\palcmd.exe
- PascalAnalyzer.Args=/W2
- AnalysisPolicy.GateOwnership=project;repository
- AnalysisPolicy.ProjectRoots=C:\case
- AnalysisPolicy.ThirdPartyRoots=C:\case\vendor
- AnalysisPolicy.Sources=C:\case\dak.ini
- Diagnostics.IgnoreUnknownMacros=DOCTOR_MACRO
- Diagnostics.IgnoreMissingPaths=*optional*
- PascalAnalyzer.Path exists: True (C:\missing\palcmd.exe)
'@
    $script:ReferenceSettings=$script:ReferenceSuccess.Replace('- dak.ini: <missing>',$preview)
}
Describe 'Doctor complete human comparison' {
    It 'pins the isolated MaxTdb fixture and removes inherited test output without changing the parent environment' {
        $beforeFixture = $env:DAK_MAXTDB_FIXTURE
        $beforeOutput = $env:DAK_TEST_OUTPUT_ROOT
        try {
            $env:DAK_MAXTDB_FIXTURE = 'C:\unrelated\production'
            $env:DAK_TEST_OUTPUT_ROOT = 'C:\unrelated\output'
            $environment = Get-MigrationDoctorEnvironment
            $environment.DAK_MAXTDB_FIXTURE | Should -Be 'F:\projects\MaxLogic\DelphiAiKit\tests\fixtures\test-projects\semantic-isolated-t311\maxTdb'
            $environment.ContainsKey('DAK_TEST_OUTPUT_ROOT') | Should -BeTrue
            $environment.DAK_TEST_OUTPUT_ROOT | Should -BeNullOrEmpty
            $env:DAK_MAXTDB_FIXTURE | Should -Be 'C:\unrelated\production'
            $env:DAK_TEST_OUTPUT_ROOT | Should -Be 'C:\unrelated\output'
            $env:DAK_TEST_OUTPUT_ROOT = $null
            (Get-MigrationDoctorEnvironment).ContainsKey('DAK_TEST_OUTPUT_ROOT') | Should -BeTrue
        } finally {
            $env:DAK_MAXTDB_FIXTURE = $beforeFixture
            $env:DAK_TEST_OUTPUT_ROOT = $beforeOutput
        }
    }
    It 'rejects unrecognized human output rather than certifying exit equality' {
        { Compare-MigrationDoctor -ReferenceText 'unknown reference output' -CandidateText 'unknown native output' -ExitCode 0 } | Should -Throw
    }
    It 'compares the complete missing-PAL human result and retains implementation diagnostics' {
        $result = Compare-MigrationDoctor $script:Reference $script:Native 3
        $result.passed | Should -BeTrue
        $result.reference_only['- where PALCMD.exe:'] | Should -BeLike 'exit=1*'
        $result.native_fields['checks[2].error'] | Should -Be 'configuration missing'
    }
    It 'rejects a changed diagnostic, subject, environment path, omitted field and extra output' {
        foreach ($changed in @(
            $script:Reference.Replace('ERROR: PALCMD executable','ERROR: Different executable'),
            $script:Reference.Replace('sample.dproj','other.dproj'),
            $script:Reference.Replace('- PA_PATH=C:\missing','- PA_PATH=C:\other'),
            $script:Reference.Replace('- Exists: True',''),
            ($script:Reference+"`nunknown data"))) {
            { Compare-MigrationDoctor $changed $script:Native 3 } | Should -Throw
        }
    }
    It 'rejects omitted and reordered native checks and duplicate metadata' {
        foreach ($changed in @(
            $script:Native.Replace('checks[3].name: pal_path','checks[3].name: compiler'),
            $script:Native.Replace('checks[2].kind: configuration','checks[2].other: configuration'),
            $script:Native.Replace('checks[3].status: unavailable','checks[3].status: available'),
            ($script:Native+"`nextra: value"))) {
            { Compare-MigrationDoctor $script:Reference $changed 3 } | Should -Throw
        }
        { Compare-MigrationDoctor ($script:Reference+"`n- Python: another") $script:Native 3 } | Should -Throw
    }
    It 'compares real-output-shaped supported capabilities without JSON parity' {
        (Compare-MigrationDoctor $script:ReferenceSuccess $script:NativeSuccess 0).passed | Should -BeTrue
        { Compare-MigrationDoctor ($script:ReferenceSuccess.Replace('9.13.1.0','9.12.0.0')) $script:NativeSuccess 0 } | Should -Throw
        { Compare-MigrationDoctor ($script:ReferenceSuccess.Replace('not listed by PAL help','supported (/CD13W64)')) $script:NativeSuccess 0 } | Should -Throw
        { Compare-MigrationDoctor $script:ReferenceSuccess ($script:NativeSuccess.Replace('/CD12W32','/CD13W64')) 0 } | Should -Throw
    }
    It 'compares configured settings, ownership and diagnostics with exact source paths' {
        (Compare-MigrationDoctor $script:ReferenceSettings $script:NativeSettings 0 -Settings).passed | Should -BeTrue
        foreach ($pair in @(@('Silent=true','Silent=false'),@('W502;C101','C101;W502'),
            @('project;repository','repository;project'),@('DOCTOR_MACRO','OTHER_MACRO'),
            @('AnalysisPolicy.Sources=C:\case\dak.ini','AnalysisPolicy.Sources=C:\other\dak.ini'),
            @('PascalAnalyzer.Args=/W2','PascalAnalyzer.Args=/W3'))) {
            { Compare-MigrationDoctor ($script:ReferenceSettings.Replace($pair[0],$pair[1])) $script:NativeSettings 0 -Settings } | Should -Throw
        }
        { Compare-MigrationDoctor $script:ReferenceSettings ($script:NativeSettings.Replace('settings.origins.FixInsightCL.Settings[1]: C:\case\dak.ini','settings.origins.FixInsightCL.Settings[1]: C:\other\dak.ini')) 0 -Settings } | Should -Throw
    }
    It 'rejects evidence replacement and escaping output before starting a process' {
        $root = Join-Path $TestDrive 'evidence'
        $batch = Join-Path $root 'measurements/existing'
        [void][IO.Directory]::CreateDirectory($batch)
        $candidate = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) 'bin/DelphiAIKit.exe'
        { Invoke-MigrationDoctorComparison $root $candidate $batch } | Should -Throw '*already exists*'
        { Invoke-MigrationDoctorComparison $root $candidate (Join-Path $root '../escaped') } | Should -Throw '*outside*'
    }
}
