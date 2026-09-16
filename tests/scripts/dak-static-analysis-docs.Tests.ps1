#Requires -Version 7.0
# Documentation contract for the dak-static-analysis skill (T-328), ported from
# test_skill_documentation.py. The implementation corpus is the native DAK source plus the delivered
# launchers, never the Python wrappers, so the contract keeps holding once T-329 retires them.

BeforeAll {
    $script:RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:SkillDir = Join-Path $script:RepoRoot 'agentskills/dak-static-analysis'
    function Read-Utf8 { param([string]$Path) [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) }

    $script:Documents = (@('SKILL.md', 'SETUP.md', 'references/triage.md', 'references/tooling.md',
        'references/fix-recipes.md') | ForEach-Object { Read-Utf8 (Join-Path $script:SkillDir $_) }) -join "`n"

    $implementationFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'src') -File | Where-Object {
            $_.Name -in @('dak.cli.pas', 'dak.messages.pas', 'Dak.Settings.pas') -or
            $_.Name -like 'Dak.Analysis.*.pas' -or $_.Name -like 'dak.analyze.*.pas'
        }
        Get-ChildItem -LiteralPath $script:SkillDir -File | Where-Object { $_.Extension -in @('.bat', '.cmd', '.sh') }
    )
    $script:Implementation = ($implementationFiles | ForEach-Object { Read-Utf8 $_.FullName }) -join "`n"

    $script:WorkspaceDocuments = (@(
        (Join-Path $script:RepoRoot 'README.md'), (Join-Path $script:RepoRoot 'spec.md'),
        (Join-Path $script:RepoRoot 'dak-template.ini'), (Join-Path $script:SkillDir 'SKILL.md'),
        (Join-Path $script:SkillDir 'SETUP.md'), (Join-Path $script:SkillDir 'references/tooling.md'),
        (Join-Path $script:SkillDir 'references/triage.md')) | ForEach-Object { Read-Utf8 $_ }) -join "`n"
}

Describe 'Skill documentation contract' {
    It 'resolves bundled resources from the loaded skill directory' {
        $skill = Read-Utf8 (Join-Path $script:SkillDir 'SKILL.md')
        $skill.Contains('directory containing this `SKILL.md`') | Should -BeTrue
        $skill.Contains('agentskills/dak-static-analysis') | Should -BeFalse
        $skill.Contains('agentskills\dak-static-analysis') | Should -BeFalse
        foreach ($resource in @('doctor.bat', 'analyze.bat', 'analyze-unit.bat', 'doctor.sh', 'analyze.sh', 'analyze-unit.sh')) {
            $skill | Should -Match ('<skill-root>[\\/]+' + [regex]::Escape($resource)) -Because $resource
            Test-Path -LiteralPath (Join-Path $script:SkillDir $resource) | Should -BeTrue -Because "$resource is delivered"
        }
    }

    It 'documents the native workflow without a Python runtime' {
        $skillDocuments = (Get-ChildItem -LiteralPath $script:SkillDir -Recurse -File -Include '*.md' |
            ForEach-Object { Read-Utf8 $_.FullName }) -join "`n"
        # Stating that no Python is needed is the one permitted mention.
        ($skillDocuments -replace '(?i)\b(?:needs )?no python\b', '') | Should -Not -Match '(?i)\bpython\b|\.py\b|\bpy -3\b'
        $script:Documents.Contains('DelphiAIKit.exe analyze-report --out <output> --verify') | Should -BeTrue
        foreach ($command in @('analyze --project', 'analyze-unit --unit', 'analyze-doctor')) {
            $script:Documents.Contains($command) | Should -BeTrue -Because "$command is the forwarded native command"
        }
        # The delivered skill folder holds no interpreter code at all.
        @(Get-ChildItem -LiteralPath $script:SkillDir -Recurse -File -Include '*.py', '*.pyc') | Should -BeNullOrEmpty
        foreach ($launcher in Get-ChildItem -LiteralPath $script:SkillDir -File | Where-Object { $_.Extension -in @('.bat', '.cmd', '.sh') }) {
            Read-Utf8 $launcher.FullName | Should -Not -Match '(?i)\bpython3?\b|\bpy\b|\.py\b' -Because $launcher.Name
        }
    }

    It 'documents only implemented filtering contracts' {
        $script:Documents.Contains('*\lib\*') | Should -BeFalse
        $script:Documents | Should -Not -Match 'PALOFF[^\r\n]*(?:STWA;|WARN1;|OPTI8;)'
        foreach ($phrase in @('Filtering decision table', 'Ownership-aware actionable projection',
            'Post-analysis path filter', 'Analyzer-specific report rule filter', 'reviewed `PALOFF` with reason',
            'Explicit PAL `/X` or `/XF`', 'static-analysis.full.sarif', 'external-summary.md', 'metrics.md',
            'unknown ownership', 'method length', 'parameter count', 'advisory', 'non-gating by default')) {
            $script:Documents.Contains($phrase) | Should -BeTrue -Because $phrase
        }

        # FixInsight's own switches, documented for its settings file, are not DAK switches.
        $externalOptions = @('--libpath', '--unitscopes')
        $options = [regex]::Matches($script:Documents, '--[a-z][a-z0-9-]*') | ForEach-Object Value | Sort-Object -Unique
        foreach ($option in $options | Where-Object { $_ -notin $externalOptions }) {
            $script:Implementation.Contains($option) | Should -BeTrue -Because "documented option $option"
        }

        $variables = [regex]::Matches($script:Documents, '\b(?:DAK|PA|FI|FIXINSIGHT)_[A-Z0-9_]+\b') |
            ForEach-Object Value | Sort-Object -Unique
        foreach ($variable in $variables) {
            $script:Implementation.Contains($variable) | Should -BeTrue -Because "documented variable $variable"
        }

        $pairs = [Collections.Generic.HashSet[string]]::new()
        foreach ($match in [regex]::Matches($script:Documents, '\[([A-Za-z][A-Za-z0-9]*)\]\.([A-Za-z][A-Za-z0-9]*)')) {
            [void]$pairs.Add($match.Groups[1].Value + '|' + $match.Groups[2].Value)
        }
        foreach ($match in [regex]::Matches($script:Documents, '\[([A-Za-z][A-Za-z0-9]*)\]\s+([A-Za-z][A-Za-z0-9]*)=')) {
            [void]$pairs.Add($match.Groups[1].Value + '|' + $match.Groups[2].Value)
        }
        $required = @('ReportFilter|ExcludePathMasks', 'FixInsightIgnore|Warnings', 'PascalAnalyzerIgnore|Rules',
            'PascalAnalyzer|ExcludeSearchFolders', 'PascalAnalyzer|ExcludeFiles', 'AnalysisPolicy|GateMetrics')
        foreach ($pair in $required) {
            [void]$pairs.Add($pair)
            $section, $key = $pair.Split('|')
            $script:Documents.Contains("[$section].$key") | Should -BeTrue -Because "[$section].$key is documented"
        }
        foreach ($pair in $pairs) {
            $section, $key = $pair.Split('|')
            $script:Implementation.Contains($section) | Should -BeTrue -Because "INI section $section"
            $script:Implementation.Contains($key) | Should -BeTrue -Because "INI key $section.$key"
        }

        $requiredArtifacts = @('summary.json', 'triage.md', 'triage-changed.md', 'static-analysis.sarif',
            'static-analysis.full.sarif', 'external-summary.md', 'metrics.md', 'baseline.json', 'delta.json')
        $artifacts = [regex]::Matches($script:Documents, '`(?:[^`\r\n]*/)?([a-z][a-z0-9-]*\.(?:jsonl|json|sarif|md|log))`',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object { $_.Groups[1].Value }
        foreach ($artifact in @($artifacts) + $requiredArtifacts | Sort-Object -Unique) {
            if ($artifact -in $requiredArtifacts) {
                $script:Documents.Contains($artifact) | Should -BeTrue -Because "$artifact is documented"
            }
            # A document the skill itself ships (SKILL.md, references/sources.md) is not a produced artifact.
            # Unlike the reference, report fixtures under tests/ do not count: they would pass any name.
            $isDocument = (Test-Path -LiteralPath (Join-Path $script:RepoRoot $artifact)) -or
                (Test-Path -LiteralPath (Join-Path $script:SkillDir $artifact)) -or
                (Test-Path -LiteralPath (Join-Path $script:SkillDir "references/$artifact"))
            ($isDocument -or $script:Implementation.Contains($artifact)) | Should -BeTrue -Because "documented artifact $artifact"
        }
    }

    It 'documents the workspace and provenance contract' {
        $template = Read-Utf8 (Join-Path $script:RepoRoot 'dak-template.ini')
        $template | Should -Match '(?m)^\[Workspace\]\s*$'
        $template | Should -Match '(?m)^Root=auto\s*$'
        foreach ($phrase in @('[Workspace].Root', '`--workspace-root`', 'closest ancestor', 'executable `dak.ini` fallback',
            'filesystem root', 'fixed root', '`auto`', '`git`', '`svn`', '`project`', 'revision', 'dirty',
            'changed_files', 'source_inputs', 'inventory', 'nested_roots', 'submodules', 'externals', 'complete',
            'available', 'fallback', 'unavailable', 'not_applicable', 'svn info --xml', 'svn status --xml',
            'svn list --xml -R', 'svnversion', 'bounded filesystem inventory', 'does not fail analysis')) {
            $script:WorkspaceDocuments.Contains($phrase) | Should -BeTrue -Because $phrase
        }
        $script:WorkspaceDocuments.Contains('repo root (folder containing `.git` or `.svn`)') | Should -BeFalse
        $script:WorkspaceDocuments.Contains('Repo root detection stops at the first folder') | Should -BeFalse
        # The selector list the documents describe is the one the native help prints.
        $script:Implementation.Contains('--workspace-root <auto|git|svn|project|path>') | Should -BeTrue
    }
}
