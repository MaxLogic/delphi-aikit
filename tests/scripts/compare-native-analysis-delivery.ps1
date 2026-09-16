#Requires -Version 7.0
# Development verification helper (T-329): certifies the delivered static-analysis workflow. Dot-sourced by
# verify-native-analysis-migration.ps1 after compare-native-analysis-nopython.ps1 and the coverage helper.
# It checks that nothing delivered depends on or falls back to the five retired Python files, runs the
# command examples exactly as the documents print them against the staged package, reruns the mapped
# coverage and the launcher and documentation contracts, and requires every remaining Python mention in
# the repository to have a reviewed purpose.

$script:MigrationRetiredPythonFiles = @('analyze.py', 'analyze-unit.py', 'doctor.py', 'postprocess.py', 'workspace.py')

function Get-MigrationRetiredFileReferences {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$PackageRoot)
    $pattern = [regex]::new('(?<![\w-])(' + (($script:MigrationRetiredPythonFiles | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $references = [Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($PackageRoot, $file.FullName).Replace('\', '/')
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        # UTF-16 text can start at either byte alignment.
        $views = @([Text.Encoding]::Latin1.GetString($bytes), [Text.Encoding]::Unicode.GetString($bytes))
        if ($bytes.Length -gt 1) { $views += [Text.Encoding]::Unicode.GetString($bytes, 1, $bytes.Length - 1) }
        foreach ($view in $views) {
            foreach ($match in $pattern.Matches($view)) {
                $references.Add([pscustomobject]@{ scope = 'package'; file = $relative; line = 0; name = $match.Value; category = $null })
            }
        }
    }
    foreach ($file in @(& git -C $RepoRoot ls-files) | Where-Object { $_ -notlike 'lib/*' -and (Test-Path -LiteralPath (Join-Path $RepoRoot $_) -PathType Leaf) }) {
        $path = Join-Path $RepoRoot $file
        if ((Get-Item -LiteralPath $path).Length -gt 5MB) { continue }
        $lines = [IO.File]::ReadAllLines($path)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            foreach ($match in $pattern.Matches($lines[$i])) {
                $line = $lines[$i].Trim()
                $category = if ($file -like 'tests/*') { 'developer reference oracle or its test' }
                    elseif ($file -like 'src/*' -and ($line.StartsWith('//') -or $line.StartsWith('{'))) { 'source comment naming the ported reference' }
                    elseif ($file -like 'docs/*' -or $file -in @('TASKS.md', 'TASKS.ARCHIVE.md', 'CHANGELOG.md')) { 'historical or planning record' }
                    else { $null }
                $references.Add([pscustomobject]@{ scope = 'repository'; file = $file; line = $i + 1; name = $match.Value; category = $category })
            }
        }
    }
    return ,$references.ToArray()
}

function Get-MigrationDocumentedExamples {
    # The Windows and WSL command examples of SKILL.md's Run Commands section and the verification command,
    # exactly as printed.
    param([Parameter(Mandatory)][string]$SkillText)
    $examples = [Collections.Generic.List[object]]::new()
    $section = [regex]::Match($SkillText, '(?s)## Run Commands(.*?)\n## ').Groups[1].Value
    foreach ($match in [regex]::Matches($section, '(?m)^- ([^:]+): `([^`]+)`\s*$')) {
        $kind = if ($match.Groups[2].Value.StartsWith('bash ')) { 'wsl' } else { 'powershell' }
        $examples.Add([pscustomobject]@{ title = $match.Groups[1].Value.Trim(); kind = $kind; command = $match.Groups[2].Value })
    }
    $verify = [regex]::Match($SkillText, '`(DelphiAIKit\.exe analyze-report --out <output> --verify)`')
    if ($verify.Success) { $examples.Add([pscustomobject]@{ title = 'Verify a retained result'; kind = 'powershell'; command = $verify.Groups[1].Value }) }
    return ,$examples.ToArray()
}

function Invoke-MigrationDelivery {
    param(
        [Parameter(Mandatory)][string]$EvidenceRoot,
        [Parameter(Mandatory)][string]$CandidateExecutable,
        [Parameter(Mandatory)][string]$ResultRoot
    )
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    [void][IO.Directory]::CreateDirectory($ResultRoot)
    $failures = [Collections.Generic.List[string]]::new()
    $packageRoot = Join-Path $ResultRoot 'package'
    $inventory = New-MigrationDeliveryPackage -RepoRoot $repoRoot -CandidateExecutable $CandidateExecutable -Destination $packageRoot
    $skill = Join-Path $packageRoot 'agentskills/dak-static-analysis'
    $packageDak = Join-Path $packageRoot 'bin/DelphiAIKit.exe'

    # 1. No delivered dependency on, or fallback to, the retired files.
    $references = Get-MigrationRetiredFileReferences -RepoRoot $repoRoot -PackageRoot $packageRoot
    foreach ($reference in $references | Where-Object { -not $_.category }) {
        $failures.Add("retired Python file referenced by $($reference.scope) $($reference.file):$($reference.line): $($reference.name)")
    }
    foreach ($name in $script:MigrationRetiredPythonFiles) {
        if (@(& git -C $repoRoot ls-files -- "agentskills/*$name").Count -and (Test-Path (Join-Path $repoRoot "agentskills/dak-static-analysis/$name"))) {
            $failures.Add("retired file still present: $name")
        }
    }

    # 2. The documented examples, run as printed with only the placeholders filled in.
    $fixture = New-MigrationProjectFixture -Root (Join-Path $ResultRoot 'examples') -RepoRoot $repoRoot `
        -FixInsightExecutable (Join-Path $repoRoot 'tests/DelphiAIKit.Tests.exe')
    $unit = Join-Path $fixture.project_dir 'Unit1.pas'
    [IO.File]::WriteAllText($unit, "unit Unit1;`r`ninterface`r`nimplementation`r`nend.`r`n")
    $toWsl = { param([string]$Path) '/mnt/' + $Path.Substring(0, 1).ToLowerInvariant() + $Path.Substring(2).Replace('\', '/') }
    $examples = Get-MigrationDocumentedExamples -SkillText ([IO.File]::ReadAllText((Join-Path $skill 'SKILL.md')))
    if ($examples.Count -lt 7) { $failures.Add("expected the six launcher examples and the verification command, found $($examples.Count)") }
    $exampleRuns = foreach ($example in $examples) {
        $command = $example.command
        if ($example.kind -eq 'wsl') {
            $command = $command.Replace('<skill-root>', (& $toWsl $skill)).Replace('/mnt/c/path/to/MyProject.dproj', (& $toWsl $fixture.project)).Replace('/mnt/c/path/to/Unit1.pas', (& $toWsl $unit))
            $bashArguments = [regex]::Matches($command, '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') }
            $output = & wsl.exe --cd $fixture.project_dir -e env DAK_DELPHI=23.0 DAK_PASCAL_ANALYZER=true "PA_PATH=$(& $toWsl (Join-Path $repoRoot 'tests/DelphiAIKit.Tests.exe'))" DAK_TEST_PAL_EXIT=0 DAK_TEST_FIXINSIGHT_EXIT=0 "DAK_EXE=$packageDak" @bashArguments 2>&1 | Out-String
            $exit = $LASTEXITCODE
        } else {
            $command = $command.Replace('<skill-root>', $skill).Replace('C:\path\to\MyProject.dproj', $fixture.project).Replace('C:\path\to\Unit1.pas', $unit)
            $command = $command.Replace('<output>', "`"$($fixture.out)`"")
            if ($command.StartsWith('DelphiAIKit.exe ')) { $command = "& `"$packageDak`" " + $command.Substring('DelphiAIKit.exe '.Length) }
            $script = "`$env:DAK_DELPHI='23.0'; `$env:PA_PATH='$(Join-Path $repoRoot 'tests/DelphiAIKit.Tests.exe')'; `$env:DAK_TEST_PAL_EXIT='0'; " +
                "`$env:DAK_TEST_FIXINSIGHT_EXIT='0'; `$env:DAK_EXE='$packageDak'; Set-Location '$($fixture.project_dir)'; $command; exit `$LASTEXITCODE"
            $output = & pwsh -NoProfile -Command $script 2>&1 | Out-String
            $exit = $LASTEXITCODE
        }
        if ($exit -ne 0) { $failures.Add("documented example failed ($($example.title), exit $exit): $command") }
        [pscustomobject]@{ title = $example.title; kind = $example.kind; command = $command; exit_code = $exit
            output_tail = ($output.Trim() -split "`n" | Select-Object -Last 5) -join "`n" }
    }

    # 3. The mapped tests and the delivered-surface contracts remain green.
    $coverage = Invoke-MigrationCoverage -EvidenceRoot $EvidenceRoot -TestExecutable (Join-Path $repoRoot 'tests/DelphiAIKit.Tests.exe') `
        -ResultRoot (Join-Path $ResultRoot 'coverage')
    if (-not $coverage.passed) { $failures.Add("coverage certification failed: $(@($coverage.verdict.failures).Count) failures") }
    $contracts = foreach ($file in @('dak-static-analysis-docs.Tests.ps1', 'dak-static-analysis-launchers.Tests.ps1')) {
        $resultFile = Join-Path $ResultRoot ($file + '.json')
        & pwsh -NoProfile -Command "`$r = Invoke-Pester -Path '$(Join-Path $PSScriptRoot $file)' -PassThru -Output None; [pscustomobject]@{ passed = `$r.PassedCount; failed = `$r.FailedCount; notrun = `$r.NotRunCount + `$r.SkippedCount } | ConvertTo-Json | Set-Content '$resultFile'"
        $result = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
        if ($result.failed -or $result.notrun -or -not $result.passed) { $failures.Add("$file passed=$($result.passed) failed=$($result.failed) not run=$($result.notrun)") }
        [pscustomobject]@{ file = $file; passed = $result.passed; failed = $result.failed; not_run = $result.notrun }
    }

    # 4. Only reviewed test and reference code keeps optional Python usage.
    $usage = Get-MigrationRepositoryPythonUsage -RepoRoot $repoRoot
    foreach ($entry in $usage | Where-Object { -not $_.category }) { $failures.Add("unclassified Python reference: $($entry.file):$($entry.line)") }

    $report = [ordered]@{
        passed = ($failures.Count -eq 0)
        candidate = $CandidateExecutable
        candidate_sha256 = (Get-FileHash -LiteralPath $CandidateExecutable).Hash
        package = $inventory
        retired_file_references = $references
        documented_examples = @($exampleRuns)
        coverage = [ordered]@{ passed = $coverage.passed; cases = $coverage.verdict.case_count; native_cases_passed = $coverage.verdict.native_cases_passed; result = (Join-Path $ResultRoot 'coverage') }
        contracts = @($contracts)
        repository_python_usage_categories = @($usage | Group-Object category | ForEach-Object { [pscustomobject]@{ category = $_.Name; count = $_.Count } })
        failures = @($failures)
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ResultRoot 'delivery-result.json')
    return [pscustomobject]$report
}
