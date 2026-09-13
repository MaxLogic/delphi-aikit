#Requires -Version 7.0

BeforeAll {
    . (Join-Path $PSScriptRoot 'compare-native-analysis-artifacts.ps1')
}

Describe 'Complete migration artifact comparison' {
    BeforeEach {
        $script:Reference = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:Candidate = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        foreach ($directory in @($script:Reference, $script:Candidate)) {
            [void][IO.Directory]::CreateDirectory($directory)
            [IO.File]::WriteAllText((Join-Path $directory 'summary.json'), '{"timestamp":"2026-09-13T13:01:31","analyzers":{"fixinsight":{"runs":[{"duration_ms":4,"exit_code":0}]}},"ownership":{"project":2},"hash":"abc","findings":["first","second"]}')
            [IO.File]::WriteAllText((Join-Path $directory 'empty.log'), '')
        }
    }

    It 'compares all files including empty artifacts' {
        $result = Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live
        $result.files.Count | Should -Be 2
        $result.equal | Should -BeTrue
    }

    It 'allows only declared valid live clocks and stage durations' {
        $path = Join-Path $script:Candidate 'summary.json'
        [IO.File]::WriteAllText($path, [IO.File]::ReadAllText($path).Replace('13:01:31', '14:02:32').Replace('"duration_ms":4', '"duration_ms":500'))
        (Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live).equal | Should -BeTrue
        { Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Exact } | Should -Throw '*differs*'
    }

    It 'rejects missing or extra artifacts' {
        [IO.File]::WriteAllText((Join-Path $script:Candidate 'extra.log'), '')
        { Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live } | Should -Throw '*inventory*'
    }

    It 'retains finding order, ownership and hashes' {
        $path = Join-Path $script:Candidate 'summary.json'
        $original = [IO.File]::ReadAllText($path)
        foreach ($replacement in @(@('"first","second"', '"second","first"'), @('"project":2', '"project":1'), @('"abc"', '"different"'))) {
            [IO.File]::WriteAllText($path, $original.Replace($replacement[0], $replacement[1]))
            { Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live } | Should -Throw '*differs*'
        }
    }

    It 'rejects malformed clocks, negative durations and duplicate JSON fields' {
        $path = Join-Path $script:Candidate 'summary.json'
        $original = [IO.File]::ReadAllText($path)
        foreach ($replacement in @(@('2026-09-13T13:01:31', 'invalid'), @('"duration_ms":4', '"duration_ms":-1'), @('"project":2', '"project":2,"project":2'))) {
            [IO.File]::WriteAllText($path, $original.Replace($replacement[0], $replacement[1]))
            { Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live } | Should -Throw
        }
    }

    It 'does not normalize clocks buried in findings' {
        foreach ($directory in @($script:Reference, $script:Candidate)) {
            [IO.File]::WriteAllText((Join-Path $directory 'findings.jsonl'), '{"message":"2026-09-13T13:01:31","timestamp":"2026-09-13T13:01:31"}')
        }
        $path = Join-Path $script:Candidate 'findings.jsonl'
        [IO.File]::WriteAllText($path, [IO.File]::ReadAllText($path).Replace('13:01:31', '14:02:32'))
        { Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live } | Should -Throw '*differs*'
    }

    It 'compares unrecognized artifacts as bytes without lossy text decoding' {
        [IO.File]::WriteAllBytes((Join-Path $script:Reference 'unrecognized.bin'), [byte[]]@(255, 1))
        [IO.File]::WriteAllBytes((Join-Path $script:Candidate 'unrecognized.bin'), [byte[]]@(254, 1))
        { Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live } | Should -Throw '*differs*'
    }

    It 'rejects malformed UTF-8 rather than treating it as a replacement character' {
        $prefix=[Text.Encoding]::UTF8.GetBytes('{"message":"')
        $suffix=[Text.Encoding]::UTF8.GetBytes('"}')
        [IO.File]::WriteAllBytes((Join-Path $script:Reference 'findings.jsonl'), [byte[]]($prefix + @(239,191,189) + $suffix))
        [IO.File]::WriteAllBytes((Join-Path $script:Candidate 'findings.jsonl'), [byte[]]($prefix + @(255) + $suffix))
        { Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live } | Should -Throw '*UTF-8*'
    }

    It 'normalizes the pinned staging GUID while retaining its suffix and consistency' {
        $tempRoot = 'F:\isolated\dak-pal'
        $first = $tempRoot + '\{11111111-2222-3333-4444-555555555555}'
        $second = $tempRoot + '\{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}'
        [IO.File]::WriteAllText((Join-Path $script:Reference 'run.log'), "[2026-09-13T13:01:31] CHILD`nCMD: palcmd.exe /R=$first`nARTIFACT: $first\Report")
        $path = Join-Path $script:Candidate 'run.log'
        $text = "[2026-09-13T14:01:31] CHILD`nCMD: palcmd.exe /R=$second`nARTIFACT: $second\Report"
        [IO.File]::WriteAllText($path, $text)
        (Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live -PalTempRoot $tempRoot).equal | Should -BeTrue
        [IO.File]::WriteAllText($path, $text.Replace('\Report', '\OtherReport'))
        { Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live -PalTempRoot $tempRoot } | Should -Throw '*differs*'
        [IO.File]::WriteAllText($path, $text.Replace("ARTIFACT: $second", "ARTIFACT: $first"))
        { Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live -PalTempRoot $tempRoot } | Should -Throw '*consistent*'
    }

    It 'retains PAL compiler, report counts and ordered children' {
        $xml = '<report><created>13.09.2026 13:01:30</created><section name="Overview"><compiler>Delphi 12 (Win64)</compiler><parse_speed><sourcelines>36</sourcelines><seconds>0,00</seconds><lines_per_second>12333</lines_per_second></parse_speed><time_for_reports><seconds>0,23 seconds (for 51 reports in 32 threads)</seconds></time_for_reports><total_time><seconds>0,45</seconds></total_time></section><items><item>one</item><item>two</item></items></report>'
        foreach ($directory in @($script:Reference, $script:Candidate)) {
            [void][IO.Directory]::CreateDirectory((Join-Path $directory 'pascal-analyzer/Fixture'))
            [IO.File]::WriteAllText((Join-Path $directory 'pascal-analyzer/Fixture/Status.xml'), $xml)
        }
        $path = Join-Path $script:Candidate 'pascal-analyzer/Fixture/Status.xml'
        [IO.File]::WriteAllText($path, $xml.Replace('13:01:30', '14:01:30').Replace('0,23 seconds', '1,23 seconds').Replace('12333', '30000'))
        (Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live).equal | Should -BeTrue
        foreach ($replacement in @(@('Delphi 12', 'Delphi 11'), @('51 reports', '50 reports'), @('<item>one</item><item>two</item>', '<item>two</item><item>one</item>'))) {
            [IO.File]::WriteAllText($path, $xml.Replace($replacement[0], $replacement[1]))
            { Compare-MigrationArtifact -Reference $script:Reference -Candidate $script:Candidate -ComparisonProfile Live } | Should -Throw '*differs*'
        }
    }
}
