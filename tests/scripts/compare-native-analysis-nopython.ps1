#Requires -Version 7.0
# Development verification helper (T-329): proves that the delivered static-analysis workflow needs no
# Python. Dot-sourced by verify-native-analysis-migration.ps1. It stages the delivery package (the DAK
# runtime files from the candidate's folder plus the skill folder, in the repository layout the launchers
# expect), audits every package file and every tracked repository file for Python references, reads the
# executable's import tables, and runs the workflow and failure matrix from the package with every child
# process recorded. This is an audited and exercised package on the existing Windows installation, not a
# clean-Windows certification.

. (Join-Path $PSScriptRoot 'Dak.ProcessTrace.ps1')

$script:MigrationPythonPattern = [regex]::new('python|\.pyc?\b|\bpy\.exe\b|\bpyw?\.exe\b|\bpy -3\b|pythonhome|pythonpath',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:MigrationInterpreterImage = [regex]::new('^(?:python\d*(?:\.\d+)*|pythonw\d*|pyw?|powershell|pwsh|wscript|cscript|bash|sh|wsl|perl|ruby|node)\.exe$',
    [Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:MigrationDeliveredSkillFiles = @('SKILL.md', 'SETUP.md', 'README.md', 'analyze.bat', 'analyze-unit.bat', 'doctor.bat',
    'find-dak.cmd', 'analyze.sh', 'analyze-unit.sh', 'doctor.sh', 'find-dak.sh', 'references/fix-recipes.md',
    'references/sources.md', 'references/tooling.md', 'references/triage.md')

function New-MigrationDeliveryPackage {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$CandidateExecutable,
        [Parameter(Mandatory)][string]$Destination)
    $bin = Join-Path $Destination 'bin'
    $skill = Join-Path $Destination 'agentskills/dak-static-analysis'
    [void][IO.Directory]::CreateDirectory($bin)
    [void][IO.Directory]::CreateDirectory((Join-Path $skill 'references'))
    $candidateDir = [IO.Path]::GetDirectoryName($CandidateExecutable)
    foreach ($name in @('DelphiAIKit.exe', 'dak.ini', 'palcmd-map.json')) {
        $source = if ($name -eq 'DelphiAIKit.exe') { $CandidateExecutable } else { Join-Path $candidateDir $name }
        if (-not (Test-Path -LiteralPath $source)) { throw "Delivery runtime file is missing: $source" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $bin $name)
    }
    $skillSource = Join-Path $RepoRoot 'agentskills/dak-static-analysis'
    $present = @(Get-ChildItem -LiteralPath $skillSource -Recurse -File | ForEach-Object {
        [IO.Path]::GetRelativePath($skillSource, $_.FullName).Replace('\', '/') })
    $unexpected = @($present | Where-Object { $_ -notin $script:MigrationDeliveredSkillFiles })
    if ($unexpected.Count) { throw "The skill folder holds files outside the reviewed delivery list: $($unexpected -join ', ')" }
    foreach ($relative in $script:MigrationDeliveredSkillFiles) {
        Copy-Item -LiteralPath (Join-Path $skillSource $relative) -Destination (Join-Path $skill $relative)
    }
    return @(Get-ChildItem -LiteralPath $Destination -Recurse -File | ForEach-Object {
        [pscustomobject]@{
            path = [IO.Path]::GetRelativePath($Destination, $_.FullName).Replace('\', '/')
            bytes = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash
        } })
}

function Get-MigrationPythonHits {
    # Python references in one file, read both as single-byte text and as UTF-16LE so strings compiled
    # into an executable are found in either encoding.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$DisplayPath)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hits = [Collections.Generic.List[object]]::new()
    # A UTF-16 string can start at an odd byte offset, so the file is decoded from both alignments.
    $views = @(
        @{ name = 'single-byte'; text = [Text.Encoding]::Latin1.GetString($bytes) },
        @{ name = 'utf-16le'; text = [Text.Encoding]::Unicode.GetString($bytes) })
    if ($bytes.Length -gt 1) { $views += @{ name = 'utf-16le'; text = [Text.Encoding]::Unicode.GetString($bytes, 1, $bytes.Length - 1) } }
    foreach ($view in $views) {
        $text = $view.text
        foreach ($match in $script:MigrationPythonPattern.Matches($text)) {
            $start = [Math]::Max(0, $match.Index - 40)
            $length = [Math]::Min($text.Length - $start, $match.Length + 80)
            $context = ($text.Substring($start, $length) -replace '[^\x20-\x7E]', ' ').Trim()
            $hits.Add([pscustomobject]@{ file = $DisplayPath; encoding = $view.name; match = $match.Value; context = $context })
        }
    }
    return ,$hits.ToArray()
}

function Get-MigrationPeImports {
    # Imported and delay-imported DLL names of a PE32+ image.
    param([Parameter(Mandatory)][string]$Path)
    $b = [IO.File]::ReadAllBytes($Path)
    $pe = [BitConverter]::ToInt32($b, 0x3C)
    if ([BitConverter]::ToUInt32($b, $pe) -ne 0x4550) { throw "Not a PE image: $Path" }
    $sectionCount = [BitConverter]::ToUInt16($b, $pe + 6)
    $optionalSize = [BitConverter]::ToUInt16($b, $pe + 20)
    $optional = $pe + 24
    if ([BitConverter]::ToUInt16($b, $optional) -ne 0x20B) { throw "Not a PE32+ image: $Path" }
    $sections = for ($i = 0; $i -lt $sectionCount; $i++) {
        $s = $optional + $optionalSize + 40 * $i
        [pscustomobject]@{ va = [BitConverter]::ToUInt32($b, $s + 12); size = [Math]::Max([BitConverter]::ToUInt32($b, $s + 8), [BitConverter]::ToUInt32($b, $s + 16)); raw = [BitConverter]::ToUInt32($b, $s + 20) }
    }
    $offset = { param([uint32]$Rva) foreach ($section in $sections) { if ($Rva -ge $section.va -and $Rva -lt $section.va + $section.size) { return [int]($Rva - $section.va + $section.raw) } }; throw "RVA outside sections: $Rva" }
    $name = { param([uint32]$Rva) $o = & $offset $Rva; $e = $o; while ($b[$e] -ne 0) { $e++ }; [Text.Encoding]::ASCII.GetString($b, $o, $e - $o) }
    $names = [Collections.Generic.List[string]]::new()
    $importRva = [BitConverter]::ToUInt32($b, $optional + 112 + 8)
    if ($importRva) {
        $d = & $offset $importRva
        while ($true) {
            $nameRva = [BitConverter]::ToUInt32($b, $d + 12)
            if ($nameRva -eq 0 -and [BitConverter]::ToUInt32($b, $d) -eq 0) { break }
            $names.Add((& $name $nameRva)); $d += 20
        }
    }
    $delayRva = [BitConverter]::ToUInt32($b, $optional + 112 + 13 * 8)
    if ($delayRva) {
        $d = & $offset $delayRva
        while ($true) {
            $nameRva = [BitConverter]::ToUInt32($b, $d + 4)
            if ($nameRva -eq 0) { break }
            $names.Add((& $name $nameRva)); $d += 32
        }
    }
    return ,@($names | Sort-Object -Unique)
}

function Get-MigrationPackageHitReview {
    # The reviewed purpose of a Python reference inside the delivery package, or $null when unreviewed.
    param([Parameter(Mandatory)]$Hit)
    if ($Hit.file -like 'agentskills/*' -and $Hit.context -match '(?i)\b(?:needs )?no python\b') {
        return 'Documentation stating that the workflow needs no Python.'
    }
    # The run context lists os, release, python, wsl and analysis_cwd; DAK writes python as null because no
    # interpreter takes part. Only that exact field sequence is accepted.
    if ($Hit.file -eq 'bin/DelphiAIKit.exe' -and $Hit.encoding -eq 'utf-16le' -and $Hit.match -ieq 'python' -and
        $Hit.context -match '\brelease\s+python\s+wsl\s+analysis_cwd\b') {
        return 'Run-context JSON field name; DAK records it as null.'
    }
    return $null
}

function Get-MigrationRepositoryPythonUsage {
    # Every tracked, present repository file that mentions Python, classified by purpose. Vendored code
    # under lib/ is not ours to audit. Delivered files must be reviewed individually.
    param([Parameter(Mandatory)][string]$RepoRoot)
    $files = @(& git -C $RepoRoot ls-files) | Where-Object { $_ -notlike 'lib/*' -and (Test-Path -LiteralPath (Join-Path $RepoRoot $_) -PathType Leaf) }
    $usage = [Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        $path = Join-Path $RepoRoot $file
        if ((Get-Item -LiteralPath $path).Length -gt 5MB) { continue }
        $lines = [IO.File]::ReadAllLines($path)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if (-not $script:MigrationPythonPattern.IsMatch($lines[$i])) { continue }
            $line = $lines[$i].Trim()
            $category = $null
            # Identifiers that name ported Python-compatible text rules (TPythonJson, PythonText,
            # TrimPythonSpace, cPythonSpace) are not references to an interpreter.
            $bare = [regex]::Replace($line, '\b\w+Python\w*\b|\b\w*Python\w+\b', '')
            if ($line -match '(?i)\bno python\b') {
                $category = 'states that no Python is needed'
            } elseif ($file -like 'agentskills/dak-static-analysis/*') {
                $category = $null
            } elseif ($file -like 'src/*') {
                if ($line.StartsWith('//') -or $line.StartsWith('{') -or $line.StartsWith('(*')) { $category = 'source comment naming the migrated reference' }
                elseif (-not $script:MigrationPythonPattern.IsMatch($bare)) { $category = 'identifier naming a ported Python-compatible text rule' }
                elseif ($file -eq 'src/Dak.Analysis.Projections.pas' -and $i -lt 60) { $category = 'PSF license text for the ported fnmatch rules' }
                elseif ($file -eq 'src/Dak.Analysis.ReportBundle.pas' -and $line -match "AddPair\('python', TJSONNull\.Create\)") { $category = 'run-context field that records no interpreter (null)' }
            } elseif ($file -like 'tests/*') {
                $category = 'developer test or reference oracle'
            } elseif ($file -like 'docs/*' -or $file -in @('TASKS.md', 'TASKS.ARCHIVE.md', 'CHANGELOG.md')) {
                $category = 'historical or planning record'
            } elseif ($file -like '.githooks/*' -or $file -like 'scripts/*') {
                $category = 'developer-only repository hook unrelated to analysis'
            } elseif ($file -in @('.gitattributes', '.gitignore')) {
                $category = 'repository configuration for developer Python files'
            }
            $usage.Add([pscustomobject]@{ file = $file; line = $i + 1; category = $category; text = $line.Substring(0, [Math]::Min(160, $line.Length)) })
        }
    }
    return ,$usage.ToArray()
}

function Get-MigrationProcessVerdict {
    # Interpreters among the processes of one traced run. Shell hosts that a scenario is allowed to use are
    # passed explicitly; everything else that matches an interpreter image is a failure.
    param([Parameter(Mandatory)][object[]]$Processes, [string[]]$AllowedImages = @())
    $interpreters = @($Processes | Where-Object {
        $leaf = [IO.Path]::GetFileName([string]$_.image)
        $script:MigrationInterpreterImage.IsMatch($leaf) -and $leaf -notin $AllowedImages -or ([string]$_.image -match '(?i)\\python')
    })
    return [pscustomobject]@{ interpreters = $interpreters; images = @($Processes | ForEach-Object { [IO.Path]::GetFileName([string]$_.image) } | Sort-Object -Unique) }
}

function Invoke-MigrationNoPython {
    param(
        [Parameter(Mandatory)][string]$EvidenceRoot,
        [Parameter(Mandatory)][string]$CandidateExecutable,
        [Parameter(Mandatory)][string]$ResultRoot
    )
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    [void][IO.Directory]::CreateDirectory($ResultRoot)
    $packageRoot = Join-Path $ResultRoot 'package'
    $inventory = New-MigrationDeliveryPackage -RepoRoot $repoRoot -CandidateExecutable $CandidateExecutable -Destination $packageRoot
    $failures = [Collections.Generic.List[string]]::new()

    # Static audit of the package.
    foreach ($file in $inventory) {
        if ($file.path -match '(?i)\.(py|pyc|pyd|pyw|whl)$|(^|/)python[^/]*\.(dll|exe|zip)$|pyvenv\.cfg$') {
            $failures.Add("package file is interpreter content: $($file.path)")
        }
    }
    $packageHits = foreach ($file in $inventory) { Get-MigrationPythonHits -Path (Join-Path $packageRoot $file.path) -DisplayPath $file.path }
    $packageHits = @($packageHits | ForEach-Object { $_ | Add-Member -NotePropertyName review -NotePropertyValue (Get-MigrationPackageHitReview -Hit $_) -PassThru })
    foreach ($hit in $packageHits | Where-Object { -not $_.review }) {
        $failures.Add("unreviewed Python reference in $($hit.file) ($($hit.encoding)): $($hit.context)")
    }
    $imports = Get-MigrationPeImports -Path (Join-Path $packageRoot 'bin/DelphiAIKit.exe')
    foreach ($dll in $imports | Where-Object { $_ -match '(?i)python|^py' }) { $failures.Add("DelphiAIKit.exe imports $dll") }

    # Source and caller audit of the repository.
    $usage = Get-MigrationRepositoryPythonUsage -RepoRoot $repoRoot
    foreach ($entry in $usage | Where-Object { -not $_.category }) {
        $failures.Add("unclassified Python reference: $($entry.file):$($entry.line): $($entry.text)")
    }

    # Runtime matrix from the package. DAK_EXE is unset and PATH holds only Windows itself, so each
    # launcher must find the packaged executable; Python stays installed on this machine throughout.
    $skill = Join-Path $packageRoot 'agentskills/dak-static-analysis'
    $packageDak = Join-Path $packageRoot 'bin/DelphiAIKit.exe'
    $testsExe = Join-Path $repoRoot 'tests/DelphiAIKit.Tests.exe'
    $workRoot = Join-Path $ResultRoot 'work'
    $fixture = New-MigrationProjectFixture -Root (Join-Path $workRoot 'project-fixture') -RepoRoot $repoRoot -FixInsightExecutable $testsExe
    [IO.File]::WriteAllText((Join-Path $fixture.project_dir 'UnitOne.pas'), "unit UnitOne;`r`ninterface`r`nimplementation`r`nend.`r`n")
    $clean = @{}
    foreach ($name in [Environment]::GetEnvironmentVariables().Keys) {
        if ([string]$name -match '^(DAK_|PA_|FI_|FIXINSIGHT_|PYTHON)') { $clean[[string]$name] = $null }
    }
    $clean.PATH = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\Wbem"
    $clean.DAK_DELPHI = '23.0'
    $live = @((Get-Content -LiteralPath (Join-Path $EvidenceRoot 'project-scenarios.json') -Raw | ConvertFrom-Json).scenarios |
        Where-Object name -CEQ 'live-project')[0]
    Assert-MigrationProjectLiveSource -ScratchRoot (Join-Path $EvidenceRoot 'scratch')
    $liveOut = Join-Path $workRoot 'live-project-out'

    $bat = { param([string]$Launcher, [string[]]$Arguments)
        'cmd.exe /d /c ""' + (Join-Path $skill $Launcher) + '" ' + (($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ') + '"' }
    $exe = { param([string[]]$Arguments) '"' + $packageDak + '" ' + (($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' ') }
    $scenarios = @(
        @{ name = 'doctor-project'; command = (& $bat 'doctor.bat' @($fixture.project)); env = @{}; exit = 0 }
        @{ name = 'project-success'; command = (& $bat 'analyze.bat' @($fixture.project)); env = @{ DAK_TEST_FIXINSIGHT_EXIT = '0'; DAK_PASCAL_ANALYZER = 'false' }; exit = 0
           check = { if (-not (Test-Path (Join-Path $fixture.out 'static-analysis.sarif')) -or -not (Test-Path (Join-Path $fixture.out 'triage.md'))) { 'triage and SARIF were not published' } } }
        @{ name = 'verify-accepted'; command = (& $exe @('analyze-report', '--out', $fixture.out, '--verify')); env = @{}; exit = 0 }
        @{ name = 'baseline-update'; command = (& $bat 'analyze.bat' @($fixture.project)); env = @{ DAK_TEST_FIXINSIGHT_EXIT = '0'; DAK_PASCAL_ANALYZER = 'false'; DAK_UPDATE_BASELINE = '1' }; exit = 0
           check = { if (-not (Test-Path (Join-Path $fixture.out 'baseline.json'))) { 'no baseline.json after the update' } } }
        @{ name = 'gate-passed'; command = (& $bat 'analyze.bat' @($fixture.project)); env = @{ DAK_TEST_FIXINSIGHT_EXIT = '0'; DAK_PASCAL_ANALYZER = 'false'; DAK_GATE = '1' }; exit = 0 }
        @{ name = 'gate-failed'; command = (& $bat 'analyze.bat' @($fixture.project)); env = @{ DAK_TEST_FIXINSIGHT_EXIT = '0'; DAK_PASCAL_ANALYZER = 'false'; DAK_GATE = '1'; DAK_TEST_FIXINSIGHT_FILE = 'Z:\nowhere\Absent.pas' }; exit = 3 }
        @{ name = 'analyzer-failed'; command = (& $bat 'analyze.bat' @($fixture.project)); env = @{ DAK_TEST_FIXINSIGHT_EXIT = '7'; DAK_PASCAL_ANALYZER = 'false' }; exit = 7 }
        @{ name = 'finalization-failed'; command = (& $bat 'analyze.bat' @($fixture.project)); env = @{ DAK_TEST_FIXINSIGHT_EXIT = '0'; DAK_PASCAL_ANALYZER = 'false'; DAK_TEST_FIXINSIGHT_MALFORMED = '1' }; exit = 4 }
        @{ name = 'unit-context'; command = (& $bat 'analyze-unit.bat' @((Join-Path $fixture.project_dir 'UnitOne.pas'), $fixture.project)); env = @{ PA_PATH = $testsExe; DAK_TEST_PAL_EXIT = '0' }; exit = 0 }
        @{ name = 'missing-project'; command = (& $bat 'analyze.bat' @((Join-Path $fixture.project_dir 'Absent.dproj'))); env = @{}; exit = 3 }
        @{ name = 'missing-dak-exe'; command = (& $bat 'analyze.bat' @($fixture.project)); env = @{ DAK_EXE = (Join-Path $workRoot 'nowhere\DelphiAIKit.exe') }; exit = 2 }
        @{ name = 'live-project'; command = (& $bat 'analyze.bat' @($live.subject, '--workspace-root', 'project')); exit = 0
           env = (& { $e = @{}; foreach ($p in $live.environment.PSObject.Properties) { if ($p.Name -ne 'DAK_EXE') { $e[$p.Name] = [string]$p.Value } }; $e.DAK_OUT = $liveOut; $e.DAK_BASELINE = Join-Path $liveOut 'baseline.json'; $e }) }
    )
    $runs = [Collections.Generic.List[object]]::new()
    foreach ($scenario in $scenarios) {
        # Scenarios share one fixture output in order: the gated runs compare against the baseline the
        # update scenario accepted.
        $environment = $clean.Clone()
        foreach ($name in $scenario.env.Keys) { $environment[$name] = $scenario.env[$name] }
        $workingDirectory = if ($scenario.name -eq 'live-project') { $live.working_directory } else { $fixture.project_dir }
        $trace = Invoke-TracedProcess -CommandLine $scenario.command -WorkingDirectory $workingDirectory -Environment $environment `
            -LogPath (Join-Path $ResultRoot $scenario.name) -TimeoutSeconds 900
        $verdict = Get-MigrationProcessVerdict -Processes $trace.processes -AllowedImages @()
        $problems = @()
        if ($trace.exit_code -ne $scenario.exit) { $problems += "exit $($trace.exit_code), expected $($scenario.exit)" }
        if (-not $trace.complete) { $problems += "process evidence incomplete: $($trace.processes.Count) recorded, job total $($trace.job_total_processes)" }
        if ($verdict.interpreters.Count) { $problems += "interpreter started: $(($verdict.interpreters | ForEach-Object image) -join ', ')" }
        if (-not (@($trace.processes | Where-Object { $_.image -ieq $packageDak }).Count) -and $scenario.name -ne 'missing-dak-exe') {
            $problems += 'the packaged DelphiAIKit.exe did not run'
        }
        if ($scenario.check) { $problems += @(& $scenario.check | Where-Object { $_ }) }
        foreach ($problem in $problems) { $failures.Add("$($scenario.name): $problem") }
        if ($scenario.name -eq 'verify-accepted') {
            # A corrupted copy of the same output must be rejected by the packaged verifier.
            $corrupt = Join-Path $workRoot 'verify-rejected'
            Copy-Item -LiteralPath $fixture.out -Destination $corrupt -Recurse
            Add-Content -LiteralPath (Join-Path $corrupt 'triage.md') -Value '- [W999] corrupt'
            $rejected = Invoke-TracedProcess -CommandLine (& $exe @('analyze-report', '--out', $corrupt, '--verify')) -WorkingDirectory $workRoot `
                -Environment $clean -LogPath (Join-Path $ResultRoot 'verify-rejected') -TimeoutSeconds 300
            if ($rejected.exit_code -ne 3) { $failures.Add("verify-rejected: exit $($rejected.exit_code), expected 3") }
            if (-not $rejected.complete) { $failures.Add('verify-rejected: process evidence incomplete') }
            $runs.Add([pscustomobject]@{ name = 'verify-rejected'; exit_code = $rejected.exit_code; complete = $rejected.complete
                job_total_processes = $rejected.job_total_processes; processes = $rejected.processes; problems = @() })
        }
        $runs.Add([pscustomobject]@{ name = $scenario.name; exit_code = $trace.exit_code; complete = $trace.complete
            job_total_processes = $trace.job_total_processes; processes = $trace.processes; images = $verdict.images; problems = $problems })
    }

    # WSL launch: the Windows process started through interop is outside the job, so only the result and
    # the launcher text are evidence here.
    $wslOut = Join-Path $workRoot 'wsl-out'
    $wslFixture = $fixture.project.Replace('\', '/')
    $wslFixture = '/mnt/' + $wslFixture.Substring(0, 1).ToLowerInvariant() + $wslFixture.Substring(2)
    $wslOutLinux = '/mnt/' + $wslOut.Substring(0, 1).ToLowerInvariant() + $wslOut.Substring(2).Replace('\', '/')
    $wslLauncher = '/mnt/' + $skill.Substring(0, 1).ToLowerInvariant() + $skill.Substring(2).Replace('\', '/') + '/analyze.sh'
    $wslOutput = & wsl.exe --cd $fixture.project_dir -e env DAK_DELPHI=23.0 DAK_PASCAL_ANALYZER=false DAK_TEST_FIXINSIGHT_EXIT=0 "DAK_OUT=$wslOutLinux" bash $wslLauncher $wslFixture 2>&1 | Out-String
    $wslExit = $LASTEXITCODE
    if ($wslExit -ne 0 -or -not (Test-Path (Join-Path $wslOut 'summary.json'))) { $failures.Add("wsl-project: exit $wslExit; $wslOutput") }

    # Controls: the same checks must catch a Python child, planted interpreter content and a launcher that
    # calls Python.
    $controls = [Collections.Generic.List[object]]::new()
    $pythonTrace = Invoke-TracedProcess -CommandLine 'cmd.exe /d /c "python -c "import sys""' -WorkingDirectory $workRoot -Environment @{} `
        -LogPath (Join-Path $ResultRoot 'control-python-child') -TimeoutSeconds 120
    $controls.Add([pscustomobject]@{ name = 'python-child-detected'; held = ((Get-MigrationProcessVerdict -Processes $pythonTrace.processes).interpreters.Count -gt 0) })
    $planted = Join-Path $workRoot 'planted-launcher.bat'
    [IO.File]::WriteAllText($planted, "@echo off`r`npython `"%~dp0analyze.py`" %*`r`n")
    $plantedHits = @(Get-MigrationPythonHits -Path $planted -DisplayPath 'agentskills/dak-static-analysis/analyze.bat' |
        Where-Object { -not (Get-MigrationPackageHitReview -Hit $_) })
    $controls.Add([pscustomobject]@{ name = 'python-launcher-detected'; held = ($plantedHits.Count -gt 0) })
    $controls.Add([pscustomobject]@{ name = 'python-file-detected'; held = ('agentskills/dak-static-analysis/analyze.py' -match '(?i)\.(py|pyc|pyd|pyw|whl)$') })
    foreach ($control in $controls | Where-Object { -not $_.held }) { $failures.Add("control did not hold: $($control.name)") }

    $report = [ordered]@{
        passed = ($failures.Count -eq 0)
        scope = 'Audited and exercised delivery package on the existing Windows installation; not a clean-Windows certification.'
        candidate = $CandidateExecutable
        candidate_sha256 = (Get-FileHash -LiteralPath $CandidateExecutable).Hash
        package = $inventory
        package_imports = $imports
        package_python_hits = $packageHits
        repository_python_usage = $usage
        runs = $runs
        wsl = [ordered]@{ exit_code = $wslExit; note = 'Interop starts the Windows executable outside the job; evidence is the result and the launcher text.' }
        controls = $controls
        failures = @($failures)
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ResultRoot 'nopython-result.json')
    return [pscustomobject]$report
}
