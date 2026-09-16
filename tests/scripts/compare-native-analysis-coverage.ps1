#Requires -Version 7.0
# Coverage certification for the native analysis migration (T-328).
# Every original Python test case must carry a reviewed disposition, and every native
# DUnitX case named by a native or consolidated disposition must have executed and passed
# in the run this script starts. Python is never executed here: the reference test modules
# are read as text so the check keeps working after the runtime scripts are retired.

$script:MigrationCoverageStatuses = @('native', 'consolidated', 'retired')

function Get-MigrationPythonCaseInventory {
    # Returns "module|Class.test_name" keys for every unittest method in the reference modules.
    param([Parameter(Mandatory)][string]$TestsRoot)
    $keys = [Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $TestsRoot -Filter 'test_*.py' -File | Sort-Object Name) {
        $className = $null
        foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
            if ($line -match '^class\s+(\w+)\s*[\(:]') { $className = $Matches[1]; continue }
            if ($line -match '^    (?:async\s+)?def\s+(test_\w+)\s*\(') {
                if (-not $className) { throw "Test method $($Matches[1]) in $($file.Name) has no enclosing class." }
                $keys.Add("$($file.Name)|$className.$($Matches[1])")
            }
        }
    }
    return ,$keys.ToArray()
}

function Get-MigrationFixtureIndex {
    # Maps each DUnitX fixture class to its unit name. The runner discovers [TestFixture] classes through
    # RTTI as well as explicit registrations, so both declare a fixture.
    param([Parameter(Mandatory)][string]$UnitsRoot)
    $index = @{}
    foreach ($file in Get-ChildItem -LiteralPath $UnitsRoot -Filter '*.pas' -File) {
        $text = [IO.File]::ReadAllText($file.FullName)
        $unit = [regex]::Match($text, '(?im)^\s*unit\s+([\w.]+)\s*;')
        if (-not $unit.Success) { continue }
        $declarations = @([regex]::Matches($text, 'RegisterTestFixture\(\s*(T\w+)\s*[,)]')) +
            @([regex]::Matches($text, '(?i)\[TestFixture[^\]]*\]\s*(T\w+)\s*=\s*class'))
        foreach ($registration in $declarations) {
            $className = $registration.Groups[1].Value
            if ($index.ContainsKey($className) -and $index[$className] -ne $unit.Groups[1].Value) {
                throw "Fixture class $className is registered in both $($index[$className]) and $($unit.Groups[1].Value)."
            }
            $index[$className] = $unit.Groups[1].Value
        }
    }
    return $index
}

function ConvertTo-MigrationNativeCaseKey {
    # Accepts Unit.Class.Method[.Case] or Class.Method[.Case]; returns Class.Method[.Case].
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][hashtable]$FixtureIndex)
    # Pester contracts are named "Pester:<Describe>.<It>" and matched verbatim against Pester results.
    if ($Name.StartsWith('Pester:', [StringComparison]::Ordinal)) { return $Name.Trim() }
    $parts = $Name.Trim().Split('.')
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        if ($FixtureIndex.ContainsKey($parts[$i])) { return ($parts[$i..($parts.Count - 1)] -join '.') }
    }
    return $null
}

function Read-MigrationDunitxResults {
    # Reads a DUnitX NUnit XML file into Class.Method[.Case] -> result records.
    param([Parameter(Mandatory)][string]$Path)
    [xml]$document = [IO.File]::ReadAllText($Path)
    $results = @{}
    foreach ($fixture in $document.SelectNodes("//test-suite[@type='Fixture']")) {
        foreach ($case in $fixture.SelectNodes('results/test-case')) {
            $key = "$($fixture.name).$($case.name)"
            $results[$key] = [pscustomobject]@{
                executed = ($case.executed -eq 'True')
                success = ($case.success -eq 'True')
                result = [string]$case.result
            }
        }
    }
    return $results
}

function Get-MigrationCoverageVerdict {
    # Pure decision over the map, the discovered Python cases, the fixture index and DUnitX results.
    param(
        [Parameter(Mandatory)][object[]]$Cases,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DiscoveredCases,
        [Parameter(Mandatory)][hashtable]$FixtureIndex,
        [Parameter(Mandatory)][hashtable]$Results
    )
    $failures = [Collections.Generic.List[string]]::new()
    $mappedKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $counts = [ordered]@{ native = 0; consolidated = 0; retired = 0 }
    $executed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    foreach ($entry in $Cases) {
        $module = ([string]$entry.source).Split('/')[-1]
        $key = "$module|$($entry.case)"
        if (-not $mappedKeys.Add($key)) { $failures.Add("duplicate: $key is mapped twice"); continue }
        $coverage = $entry.coverage
        if ($null -eq $coverage) { $failures.Add("unmapped: $key has no reviewed coverage disposition"); continue }
        $status = [string]$coverage.status
        if ($status -notin $script:MigrationCoverageStatuses) { $failures.Add("unaccepted: $key has status '$status'"); continue }
        $counts[$status]++
        $reason = [string]$coverage.reason
        $nativeCases = @($coverage.native_cases | Where-Object { $_ })
        if ($status -ne 'native' -and [string]::IsNullOrWhiteSpace($reason)) {
            $failures.Add("unreviewed: $key is $status without a reason")
        }
        if ($status -eq 'retired') {
            if ($nativeCases.Count -gt 0) { $failures.Add("inconsistent: $key is retired but names native cases") }
            continue
        }
        if ($nativeCases.Count -eq 0) { $failures.Add("unproven: $key is $status without native cases"); continue }
        foreach ($nativeName in $nativeCases) {
            $nativeKey = ConvertTo-MigrationNativeCaseKey -Name $nativeName -FixtureIndex $FixtureIndex
            if (-not $nativeKey) { $failures.Add("missing fixture: $key names '$nativeName', which is not a registered fixture"); continue }
            # A method without a case suffix covers all of its TestCase variants.
            $matching = @($Results.Keys | Where-Object { $_ -eq $nativeKey -or $_.StartsWith($nativeKey + '.', [StringComparison]::Ordinal) })
            if ($matching.Count -eq 0) { $failures.Add("not executed: $key needs '$nativeKey', which did not run"); continue }
            foreach ($resultKey in $matching) {
                $result = $Results[$resultKey]
                if (-not $result.executed) { $failures.Add("not executed: $key needs '$resultKey', which was skipped") }
                elseif (-not $result.success) { $failures.Add("failed: $key needs '$resultKey', which ended $($result.result)") }
                else { [void]$executed.Add($resultKey) }
            }
        }
    }

    $discovered = [Collections.Generic.HashSet[string]]::new([string[]]$DiscoveredCases, [StringComparer]::Ordinal)
    foreach ($key in $discovered) { if (-not $mappedKeys.Contains($key)) { $failures.Add("discovery: $key exists in the reference but not in the map") } }
    foreach ($key in $mappedKeys) { if (-not $discovered.Contains($key)) { $failures.Add("discovery: $key is mapped but no longer exists in the reference") } }

    return [pscustomobject]@{
        passed = ($failures.Count -eq 0)
        case_count = $mappedKeys.Count
        discovered_count = $discovered.Count
        counts = $counts
        native_cases_passed = $executed.Count
        failures = @($failures)
    }
}

function Get-MigrationCoverageRunFilter {
    # DUnitX --run value selecting exactly the fixtures that the map references.
    param([Parameter(Mandatory)][object[]]$Cases, [Parameter(Mandatory)][hashtable]$FixtureIndex)
    $fixtures = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Cases) {
        foreach ($nativeName in @($entry.coverage.native_cases | Where-Object { $_ })) {
            $nativeKey = ConvertTo-MigrationNativeCaseKey -Name $nativeName -FixtureIndex $FixtureIndex
            if ($nativeKey -and -not $nativeKey.StartsWith('Pester:', [StringComparison]::Ordinal)) {
                $className = $nativeKey.Split('.')[0]
                [void]$fixtures.Add("$($FixtureIndex[$className]).$className")
            }
        }
    }
    return (@($fixtures) -join ',')
}

function Get-MigrationCoverageControls {
    # Proves the verdict still rejects a skipped case, a failed case and a dropped reference case.
    param([object[]]$Cases, [string[]]$DiscoveredCases, [hashtable]$FixtureIndex, [hashtable]$Results)
    $controls = [Collections.Generic.List[object]]::new()
    # Mutate a DUnitX result that a mapped case actually requires; an unreferenced test proves nothing.
    $required = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $Cases) {
        foreach ($nativeName in @($entry.coverage.native_cases | Where-Object { $_ })) {
            $nativeKey = ConvertTo-MigrationNativeCaseKey -Name $nativeName -FixtureIndex $FixtureIndex
            if ($nativeKey -and -not $nativeKey.StartsWith('Pester:', [StringComparison]::Ordinal)) { [void]$required.Add($nativeKey) }
        }
    }
    $firstKey = @($Results.Keys | Sort-Object | Where-Object { $required.Contains($_) })[0]
    if (-not $firstKey) { $firstKey = @($Results.Keys | Sort-Object)[0] }
    $missing = $Results.Clone(); $missing.Remove($firstKey)
    $failed = $Results.Clone(); $failed[$firstKey] = [pscustomobject]@{ executed = $true; success = $false; result = 'Failure' }
    $dropped = @($DiscoveredCases) + 'test_control.py|ControlTests.test_added_after_the_freeze'
    foreach ($control in @(
        @{ name = 'removed-native-result'; results = $missing; discovered = $DiscoveredCases; expect = 'not executed:' },
        @{ name = 'failed-native-result'; results = $failed; discovered = $DiscoveredCases; expect = 'failed:' },
        @{ name = 'unmapped-reference-case'; results = $Results; discovered = $dropped; expect = 'discovery:' })) {
        $verdict = Get-MigrationCoverageVerdict -Cases $Cases -DiscoveredCases $control.discovered -FixtureIndex $FixtureIndex -Results $control.results
        $intended = @($verdict.failures | Where-Object { $_.StartsWith($control.expect, [StringComparison]::Ordinal) })
        $controls.Add([pscustomobject]@{
            name = $control.name
            rejected = (-not $verdict.passed)
            intended_reason = ($intended.Count -gt 0)
            failures = @($verdict.failures)
        })
    }
    return ,$controls.ToArray()
}

function Invoke-MigrationCoverage {
    param(
        [Parameter(Mandatory)][string]$EvidenceRoot,
        [Parameter(Mandatory)][string]$TestExecutable,
        [Parameter(Mandatory)][string]$ResultRoot
    )
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $mapPath = Join-Path $EvidenceRoot 'coverage-current.json'
    $frozenPath = Join-Path $EvidenceRoot 'coverage-map.json'
    $cases = @((Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json).cases)
    $frozen = @((Get-Content -LiteralPath $frozenPath -Raw | ConvertFrom-Json).cases | ForEach-Object { "$($_.source)|$($_.case)" })
    $current = @($cases | ForEach-Object { "$($_.source)|$($_.case)" })
    $frozenDrift = @(Compare-Object -ReferenceObject $frozen -DifferenceObject $current | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
    $discovered = Get-MigrationPythonCaseInventory -TestsRoot (Join-Path $EvidenceRoot 'python-reference/agentskills/dak-static-analysis/tests')
    $fixtureIndex = Get-MigrationFixtureIndex -UnitsRoot (Join-Path $repoRoot 'tests/units')

    [void][IO.Directory]::CreateDirectory($ResultRoot)
    $xmlPath = Join-Path $ResultRoot 'dunitx-results.xml'
    $filter = Get-MigrationCoverageRunFilter -Cases $cases -FixtureIndex $fixtureIndex
    $environment = @{
        DAK_MAXTDB_FIXTURE = (Join-Path $repoRoot 'tests/fixtures/test-projects/semantic-isolated-t311/maxTdb')
        DAK_TEST_OUTPUT_ROOT = $null
    }
    $saved = @{}
    foreach ($name in $environment.Keys) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
    $started = [Diagnostics.Stopwatch]::StartNew()
    try {
        foreach ($name in $environment.Keys) { [Environment]::SetEnvironmentVariable($name, $environment[$name]) }
        $output = & $TestExecutable "--run:$filter" "--xmlfile:$xmlPath" '--hidebanner' '--exitbehavior:Continue' 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
    $started.Stop()
    [IO.File]::WriteAllLines((Join-Path $ResultRoot 'dunitx-output.txt'), [string[]]@($output | ForEach-Object { [string]$_ }))
    if (-not (Test-Path -LiteralPath $xmlPath)) { throw "DUnitX wrote no XML results (exit $exitCode)." }

    $results = Read-MigrationDunitxResults -Path $xmlPath
    # Documentation contracts run under Pester in their own session so this one keeps its state.
    $pesterPath = Join-Path $ResultRoot 'pester-results.json'
    $pesterScript = Join-Path $PSScriptRoot 'dak-static-analysis-docs.Tests.ps1'
    $pesterCommand = "`$r = Invoke-Pester -Path '$pesterScript' -PassThru -Output None; " +
        "@(`$r.Tests | ForEach-Object { [pscustomobject]@{ name = `$_.ExpandedPath; result = [string]`$_.Result } }) | " +
        "ConvertTo-Json -AsArray | Set-Content -LiteralPath '$pesterPath'"
    & pwsh -NoProfile -Command $pesterCommand
    if (-not (Test-Path -LiteralPath $pesterPath)) { throw 'Pester wrote no results.' }
    foreach ($test in (Get-Content -LiteralPath $pesterPath -Raw | ConvertFrom-Json)) {
        $results["Pester:$($test.name)"] = [pscustomobject]@{
            executed = ($test.result -ne 'NotRun' -and $test.result -ne 'Skipped')
            success = ($test.result -eq 'Passed')
            result = $test.result
        }
    }
    $verdict = Get-MigrationCoverageVerdict -Cases $cases -DiscoveredCases $discovered -FixtureIndex $fixtureIndex -Results $results
    $controls = Get-MigrationCoverageControls -Cases $cases -DiscoveredCases $discovered -FixtureIndex $fixtureIndex -Results $results
    $controlsHold = @($controls | Where-Object { -not ($_.rejected -and $_.intended_reason) }).Count -eq 0
    $failedInRun = @($results.Keys | Where-Object { -not $results[$_].success })
    $passed = $verdict.passed -and $controlsHold -and ($frozenDrift.Count -eq 0) -and ($exitCode -eq 0) -and ($failedInRun.Count -eq 0)

    $report = [ordered]@{
        passed = $passed
        test_executable = $TestExecutable
        test_executable_sha256 = (Get-FileHash -LiteralPath $TestExecutable).Hash
        coverage_map_sha256 = (Get-FileHash -LiteralPath $mapPath).Hash
        frozen_map_sha256 = (Get-FileHash -LiteralPath $frozenPath).Hash
        frozen_map_drift = $frozenDrift
        run_filter = $filter
        dunitx_exit_code = $exitCode
        dunitx_cases_run = $results.Count
        dunitx_cases_not_passed = $failedInRun
        duration_seconds = [math]::Round($started.Elapsed.TotalSeconds, 1)
        verdict = $verdict
        controls = $controls
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $ResultRoot 'coverage-result.json')
    return [pscustomobject]$report
}
