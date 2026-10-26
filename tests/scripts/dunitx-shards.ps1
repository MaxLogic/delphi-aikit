function Read-DakShardSummary {
    [CmdletBinding()]
    param([string]$LogDirectory)
    $files = @(Get-ChildItem -LiteralPath $LogDirectory -Directory | Where-Object Name -Match '^run-[0-9a-f]{32}$' |
        ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'summary.json') -ErrorAction Stop })
    if ($files.Count -ne 1) { throw "Missing/ambiguous shard summary in $LogDirectory" }
    Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
}

function Read-DakCaseResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$XmlPath)
    $document = [Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    $document.Load($XmlPath)
    foreach ($node in $document.SelectNodes('//test-case')) {
        $fixture = $node.SelectSingleNode('ancestor::test-suite[@type="Fixture"][1]')
        if ($null -eq $fixture) { throw "Case without fixture in $XmlPath" }
        [pscustomobject]@{
            id = $fixture.GetAttribute('name') + '.' + $node.GetAttribute('name')
            result = $node.GetAttribute('result')
            detail = $node.InnerText
            seconds = [double]::Parse($node.GetAttribute('time'), [Globalization.CultureInfo]::InvariantCulture)
        }
    }
}

function Merge-DakShardResult {
    [CmdletBinding()]
    param([AllowEmptyCollection()][object[]]$Summaries, [AllowEmptyCollection()][object[]]$Cases)
    $counts = [ordered]@{Found=0L;Passed=0L;Failed=0L;Errored=0L;Leaked=0L;Ignored=0L}
    $exitCode = 0
    $shutdownLeak = $false
    $identities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $caseCounts = @{Passed=0L;Failed=0L;Errored=0L;Leaked=0L;Ignored=0L}
    foreach ($case in $Cases) {
        if (-not $identities.Add($case.id)) { throw "Duplicate test identity: $($case.id)" }
        if ($case.result -ne 'Success') { $exitCode = 1 }
        switch ($case.result) {
            'Success' { $caseCounts.Passed++ }
            'Failure' { $caseCounts.Failed++ }
            'Error' { $caseCounts.Errored++ }
            'MemoryLeak' { $caseCounts.Leaked++ }
            { $_ -in 'Ignored','Skipped','Inconclusive','NotRunnable' } { $caseCounts.Ignored++ }
            default { $caseCounts.Errored++ }
        }
    }
    foreach ($summary in $Summaries) {
        if ($summary.exitCode -ne 0 -or $summary.processExitCode -ne 0) { $exitCode = 1 }
        if ($summary.shutdownLeakReport) { $shutdownLeak = $true; $exitCode = 1 }
        if ($null -eq $summary.counts) { $exitCode = 1; continue }
        foreach ($field in @($counts.Keys)) { $counts[$field] += [long]$summary.counts.$field }
    }
    if ($counts.Found -eq 0 -or $counts.Found -ne $Cases.Count -or
        $counts.Found -ne ($counts.Passed+$counts.Failed+$counts.Errored+$counts.Leaked+$counts.Ignored) -or
        ($counts.Failed+$counts.Errored+$counts.Leaked+$counts.Ignored) -gt 0) { $exitCode = 1 }
    # Neither a misleading fixture success nor contradictory footer counts can erase case errors.
    $footerCounts = [ordered]@{}
    foreach ($field in $counts.Keys) { $footerCounts[$field] = $counts[$field] }
    foreach ($field in 'Failed','Errored','Leaked','Ignored') { $counts[$field] = [math]::Max($counts[$field], $caseCounts[$field]) }
    $counts.Passed = [math]::Min($counts.Passed, $caseCounts.Passed)
    [pscustomobject]@{exitCode=$exitCode;counts=$counts;shutdownLeakReport=$shutdownLeak;
        footerCounts=$footerCounts;failures=@($Cases | Where-Object result -ne 'Success')}
}

function Get-DakShardPlan {
    [CmdletBinding()]
    param([object[]]$Groups, [ValidateRange(1,16)][int]$ShardCount)
    $shards = @(1..$ShardCount | ForEach-Object {
        [pscustomobject]@{number=$_;seconds=0.0;selectors=[Collections.Generic.List[string]]::new()}
    })
    foreach ($group in $Groups | Sort-Object seconds -Descending) {
        $shard = $shards | Sort-Object seconds,number | Select-Object -First 1
        foreach ($selector in $group.selectors) { $shard.selectors.Add($selector) }
        $shard.seconds += $group.seconds
    }
    $shards | Where-Object { $_.selectors.Count -gt 0 }
}

function Get-DakRegisteredTest {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string]$ExecutablePath, [string]$LogDirectory, [string]$TestsRoot)
    $path = Join-Path $LogDirectory 'registered-tests.json'
    $process = [Diagnostics.Process]::new()
    try {
        $process.StartInfo.FileName = $ExecutablePath
        $process.StartInfo.ArgumentList.Add('--exclude:MaxTdbProof')
        $process.StartInfo.Environment['DAK_TEST_LIST_PATH'] = $path
        $process.StartInfo.WorkingDirectory = $TestsRoot
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) { throw 'Binary roster enumeration exceeded 60 seconds.' }
        if (-not [Threading.Tasks.Task]::WaitAll(@($stdout,$stderr),10000)) { throw 'Binary roster streams remained open.' }
        $stdout.Result | Set-Content -LiteralPath (Join-Path $LogDirectory 'roster-stdout.log')
        $stderr.Result | Set-Content -LiteralPath (Join-Path $LogDirectory 'roster-stderr.log')
        if ($process.ExitCode -ne 0) { throw "Binary roster enumeration exited $($process.ExitCode)." }
        $roster = @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
        if ($roster.Count -eq 0) { throw 'Binary registered test roster is empty.' }
        $identities = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($row in $roster) {
            if (-not $row.id -or -not $row.fixture -or -not $row.selector) { throw 'Incomplete binary roster entry.' }
            if (-not $identities.Add($row.id)) { throw "Ambiguous registered test identity: $($row.id)" }
        }
        $roster
    } finally {
        if ($process.Id -and -not $process.HasExited) { $process.Kill($true); [void]$process.WaitForExit(10000) }
        $process.Dispose()
    }
}

function Compare-DakRoster {
    [CmdletBinding()]
    [OutputType([string])]
    param([object[]]$Roster, [AllowEmptyCollection()][object[]]$Cases)
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in $Roster) { if (-not $expected.Add($row.id)) { "Duplicate registered case: $($row.id)" } }
    $executed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($case in $Cases) {
        if (-not $executed.Add($case.id)) { "Duplicate executed case: $($case.id)" }
        if (-not $expected.Contains($case.id)) { "Unregistered executed case: $($case.id)" }
    }
    foreach ($id in $expected) { if (-not $executed.Contains($id)) { "Missing registered case: $id" } }
}

function Get-DakFixtureGroup {
    [CmdletBinding()]
    param([string]$TestsRoot, [Parameter(Mandatory)][object[]]$Roster)
    $measurements = Get-Content -LiteralPath (Join-Path $TestsRoot 'scripts\fixture-durations.json') -Raw | ConvertFrom-Json
    $weights = @{}
    foreach ($row in $measurements) { $weights[$row.selection] = $row.seconds }
    $migration = [Collections.Generic.List[string]]::new()
    foreach ($fixture in $Roster | Group-Object fixture) {
        $selector = $fixture.Name
        $seconds = if ($weights.ContainsKey($selector)) { [double]$weights[$selector] } else { 0.1 }
        if ($selector -match '\.(TNativeAnalysisReplayTests|TNativeAnalysisVerifyTests)$') {
            $migration.Add($selector)
        } elseif ($selector -eq 'Test.FixInsight.TFixInsightTests') {
            $selections = @($fixture.Group.selector | Sort-Object -Unique)
            foreach ($method in $selections) {
                $weight = if ($method.EndsWith('.FixInsightRawReportsPreserveFilteredEvidence', [StringComparison]::Ordinal)) { [math]::Max(0.1, $seconds-1) } else { 0.25 }
                [pscustomobject]@{selectors=@($method);seconds=$weight}
            }
        } else {
            # DUnitX parses each run-list line as a comma-separated expression. Whole-fixture
            # selectors keep parameterized case names (including literal commas) intact.
            [pscustomobject]@{selectors=@($selector);seconds=$seconds}
        }
    }
    # Replay and Verify share scratch/report-* and must stay in one process.
    if ($migration.Count -gt 0) { [pscustomobject]@{selectors=@($migration);seconds=100.0} }
}
