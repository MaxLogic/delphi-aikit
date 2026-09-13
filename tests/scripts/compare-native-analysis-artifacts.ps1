#Requires -Version 7.5

# Development proof helper. This file is not part of the delivered workflow.
function Get-MigrationUtf8Text {
    param([byte[]]$Bytes)
    try { $text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes) }
    catch [Text.DecoderFallbackException] { throw 'Malformed UTF-8 in a projected artifact.' }
    if ($text.StartsWith([string][char]0xFEFF, [StringComparison]::Ordinal)) { $text = $text.Substring(1) }
    return $text
}

function Assert-MigrationJsonKey {
    param([System.Text.Json.JsonElement]$Element)
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $keys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $keys.Add($property.Name)) { throw "Duplicate JSON field: $($property.Name)" }
            Assert-MigrationJsonKey -Element $property.Value
        }
    } elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-MigrationJsonKey -Element $item }
    }
}

function Get-MigrationClockToken {
    param([object]$Value, [switch]$Pal)
    if ($Value -isnot [string]) { throw 'Clock must be a string.' }
    $formats = if ($Pal) { @('dd.MM.yyyy HH:mm:ss') } else { @('yyyy-MM-ddTHH:mm:ss', 'yyyy-MM-ddTHH:mm:sszzz', 'yyyy-MM-ddTHH:mm:ss.FFFFFFFzzz', 'yyyy-MM-ddTHH:mm:ss.FFFFFFFZ') }
    $parsed = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParseExact($Value, [string[]]$formats, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        throw "Malformed generated clock: $Value"
    }
    return '<clock>'
}

function Get-MigrationJsonProjection {
    param([string]$Text, [string]$RelativePath, [string]$ComparisonProfile)
    $document = [System.Text.Json.JsonDocument]::Parse($Text)
    try { Assert-MigrationJsonKey -Element $document.RootElement } finally { $document.Dispose() }
    $data = ConvertFrom-Json -InputObject $Text -AsHashtable -NoEnumerate -DateKind String -Depth 100
    if ($ComparisonProfile -eq 'Live') {
        switch -Exact ($RelativePath) {
            'summary.json' {
                $data.timestamp = Get-MigrationClockToken $data.timestamp
                foreach ($analyzer in @('fixinsight', 'pascal_analyzer')) {
                    foreach ($run in $data.analyzers[$analyzer].runs) {
                        $duration = $run.duration_ms
                        if ($null -eq $duration -or $duration -is [string] -or $duration -is [bool] -or -not [double]::IsFinite([double]$duration) -or $duration -lt 0) {
                            throw 'Stage duration must be a finite nonnegative number.'
                        }
                        $run.duration_ms = '<duration>'
                    }
                }
            }
            'baseline.json' {
                $data.created_at = Get-MigrationClockToken $data.created_at
                $data.summary.timestamp = Get-MigrationClockToken $data.summary.timestamp
            }
            'delta.json' {
                $data.baseline.timestamp = Get-MigrationClockToken $data.baseline.timestamp
                $data.current.timestamp = Get-MigrationClockToken $data.current.timestamp
            }
            'history.jsonl' {
                $data.summary_timestamp = Get-MigrationClockToken $data.summary_timestamp
            }
        }
    }
    if ($ComparisonProfile -ne 'Exact' -and $RelativePath -ceq 'history.jsonl') {
        $data.timestamp = Get-MigrationClockToken $data.timestamp
    }
    return ConvertTo-Json -InputObject $data -Depth 100 -Compress
}

function Get-MigrationArtifactProjection {
    param([string]$Text, [string]$RelativePath, [string]$ComparisonProfile, [string]$PalStageRoot)
    if ($ComparisonProfile -eq 'Exact') { return $Text }
    if ($RelativePath -cmatch '\.(json|sarif)$') {
        return Get-MigrationJsonProjection -Text $Text -RelativePath $RelativePath -ComparisonProfile $ComparisonProfile
    }
    if ($RelativePath -cmatch '\.jsonl$') {
        $lines = foreach ($line in [regex]::Split($Text, '\r?\n')) {
            if ($line.Length -eq 0) { '' } else { Get-MigrationJsonProjection -Text $line -RelativePath $RelativePath -ComparisonProfile $ComparisonProfile }
        }
        return $lines -join "`n"
    }
    if ($ComparisonProfile -eq 'Live' -and $RelativePath -cmatch '^pascal-analyzer/.+\.xml$') {
        $settings = [Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($Text), $settings)
        $xml = [Xml.XmlDocument]::new()
        $xml.PreserveWhitespace = $true
        try { $xml.Load($reader) } finally { $reader.Dispose() }
        $created = $xml.SelectNodes('/report/created')
        if ($created.Count -ne 1) { throw 'Expected one PAL report creation clock.' }
        $created[0].InnerText = Get-MigrationClockToken $created[0].InnerText -Pal
        if ($RelativePath.EndsWith('/Status.xml', [StringComparison]::Ordinal)) {
            $overview = '/report/section[@name="Overview"]'
            foreach ($suffix in @('/parse_speed/seconds', '/parse_speed/lines_per_second', '/total_time/seconds')) {
                $nodes = $xml.SelectNodes($overview + $suffix)
                if ($nodes.Count -ne 1 -or $nodes[0].InnerText -cnotmatch '^\d+(?:[,.]\d+)?$') { throw "Invalid PAL timing field: $suffix" }
                $nodes[0].InnerText = '<timing>'
            }
            $nodes = $xml.SelectNodes($overview + '/time_for_reports/seconds')
            if ($nodes.Count -ne 1 -or $nodes[0].InnerText -cnotmatch '^\d+(?:[,.]\d+)?(?<suffix> seconds \(for \d+ reports in \d+ threads\))$') { throw 'Invalid PAL report timing.' }
            $nodes[0].InnerText = '<timing>' + $Matches.suffix
            foreach ($node in $xml.SelectNodes($overview + '/outout_folder')) {
                if (-not $PalStageRoot -or -not $node.InnerText.StartsWith($PalStageRoot + '\', [StringComparison]::Ordinal)) { throw 'PAL staging root does not match the run log.' }
                $node.InnerText = '<pal-stage>' + $node.InnerText.Substring($PalStageRoot.Length)
            }
        }
        return $xml.OuterXml
    }
    $patterns = [Collections.Generic.List[string]]::new()
    if ($RelativePath -ceq 'triage.md' -or ($ComparisonProfile -eq 'Live' -and $RelativePath -cin @('summary.md', 'baseline.md'))) {
        $patterns.Add('(?m)(?<prefix>^- Timestamp: )(?<clock>[^\r\n]+)')
    }
    if ($RelativePath -ceq 'trend.md') {
        $patterns.Add('(?m)(?<prefix>^- Updated: )(?<clock>[^\r\n]+)')
        if ($ComparisonProfile -eq 'Live') { $patterns.Add('(?m)(?<prefix>^\| )(?<clock>\d{4}-[^|\r\n]+?)(?= \|)') }
    }
    if ($ComparisonProfile -eq 'Live') {
        if ($RelativePath -ceq 'delta.md') { $patterns.Add('(?m)(?<prefix>^- (?:Baseline|Current): `[^`\r\n]+` \()(?<clock>[^)\r\n]+)(?=\))') }
        if ($RelativePath -cin @('fixinsight/fixinsight.txt.log', 'pascal-analyzer/pascal-analyzer.log')) { $patterns.Add('(?<prefix>\ATimestamp: )(?<clock>[^\r\n]+)') }
        if ($RelativePath -ceq 'run.log') { $patterns.Add('(?m)(?<prefix>^\[)(?<clock>[^\]\r\n]+)(?=\] )') }
    }
    foreach ($pattern in $patterns) {
        $Text = [regex]::Replace($Text, $pattern, { param($match) $match.Groups['prefix'].Value + (Get-MigrationClockToken $match.Groups['clock'].Value) })
    }
    if ($ComparisonProfile -eq 'Live' -and $RelativePath -ceq 'run.log' -and $PalStageRoot) {
        # Only the exact staging root found in this log's PAL /R argument is volatile.
        # Preserve all suffixes, commands, option values and publication destinations.
        $Text = $Text.Replace($PalStageRoot, '<pal-stage>')
    }
    return $Text
}

function Get-MigrationArtifactManifest {
    param([string]$Root, [string]$ComparisonProfile, [string]$PalTempRoot)
    $resolvedRoot = (Get-Item -LiteralPath $Root -Force -ErrorAction Stop).FullName
    $items = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction Stop)
    if (@($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) { throw 'Artifact inventory contains a reparse point.' }
    $stageRoot = ''
    $logPath = Join-Path $resolvedRoot 'run.log'
    if ($ComparisonProfile -eq 'Live' -and (Test-Path -LiteralPath $logPath)) {
        if (-not $PalTempRoot) { throw 'Live log comparison requires the pinned PAL temporary root.' }
        $stagePattern = [regex]::Escape($PalTempRoot.TrimEnd('\')) + '\\\{[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}'
        $stageRoots = @([regex]::Matches((Get-MigrationUtf8Text ([IO.File]::ReadAllBytes($logPath))), $stagePattern) | ForEach-Object Value | Sort-Object -Unique)
        if ($stageRoots.Count -ne 1) { throw 'Expected exactly one consistent PAL staging root in the run log.' }
        $stageRoot = $stageRoots[0]
    }
    $records = foreach ($file in $items | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName -CaseSensitive) {
        $relative = [IO.Path]::GetRelativePath($resolvedRoot, $file.FullName).Replace('\', '/')
        $raw = [IO.File]::ReadAllBytes($file.FullName)
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($raw))
        $normalizedHash = $hash
        $projectedText = $relative -cmatch '\.(json|jsonl|sarif)$' -or
            ($ComparisonProfile -eq 'Live' -and $relative -cmatch '^pascal-analyzer/.+\.xml$') -or
            $relative -cin @('triage.md', 'trend.md', 'summary.md', 'baseline.md', 'delta.md', 'run.log', 'fixinsight/fixinsight.txt.log', 'pascal-analyzer/pascal-analyzer.log')
        if ($ComparisonProfile -eq 'Replay') { $projectedText = $relative -cin @('triage.md', 'trend.md', 'history.jsonl') }
        if ($ComparisonProfile -ne 'Exact' -and $projectedText) {
            $projection = Get-MigrationArtifactProjection -Text (Get-MigrationUtf8Text $raw) -RelativePath $relative -ComparisonProfile $ComparisonProfile -PalStageRoot $stageRoot
            $normalizedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($projection)))
        }
        [pscustomobject]@{ path = $relative; bytes = $raw.Length; sha256 = $hash; comparison_sha256 = $normalizedHash }
    }
    return ,@($records)
}

function Compare-MigrationArtifact {
    [CmdletBinding()]
    param([string]$Reference, [string]$Candidate, [ValidateSet('Exact', 'Replay', 'Live')][string]$ComparisonProfile = 'Exact', [string]$PalTempRoot)
    $referenceFiles = Get-MigrationArtifactManifest -Root $Reference -ComparisonProfile $ComparisonProfile -PalTempRoot $PalTempRoot
    $candidateFiles = Get-MigrationArtifactManifest -Root $Candidate -ComparisonProfile $ComparisonProfile -PalTempRoot $PalTempRoot
    if ($referenceFiles.Count -eq 0) { throw 'Reference artifact inventory is empty.' }
    if (($referenceFiles.path -join "`n") -cne ($candidateFiles.path -join "`n")) { throw 'Artifact inventory differs.' }
    for ($index = 0; $index -lt $referenceFiles.Count; $index++) {
        if ($referenceFiles[$index].comparison_sha256 -cne $candidateFiles[$index].comparison_sha256) { throw "Artifact differs: $($referenceFiles[$index].path)" }
    }
    return [pscustomobject]@{ equal = $true; profile = $ComparisonProfile; files = $candidateFiles; reference_files = $referenceFiles }
}
