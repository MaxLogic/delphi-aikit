function Get-DakTestSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][int]$ProcessExitCode,
        [AllowEmptyString()][string]$ErrorText = ''
    )
    # FastMM writes its shutdown report after DUnitX has printed Leaked=0, usually to stderr (T-347).
    $leakPattern = '(?im)^Unexpected Memory Leak\s*$|An unexpected memory leak has occurred'
    $shutdownLeak = [regex]::IsMatch($Text, $leakPattern) -or [regex]::IsMatch($ErrorText, $leakPattern)
    $counts = $null
    $status = 'incomplete'
    # Match only the final footer as a block. Never fill a missing field from
    # an older run, and never accept exit zero as evidence of executed tests.
    $starts = [regex]::Matches($Text, '(?m)^Tests Found[ \t]*:')
    if ($starts.Count -gt 0) {
        $footer = $Text.Substring($starts[$starts.Count - 1].Index)
        $fields = @('Found', 'Ignored', 'Passed', 'Leaked', 'Failed', 'Errored')
        $pattern = '^' + (($fields | ForEach-Object {
            'Tests ' + $_ + '[ \t]*:[ \t]*(?<' + $_ + '>\d{1,9})[ \t]*(?:\r?\n|$)'
        }) -join '')
        $match = [regex]::Match($footer, $pattern)
        if ($match.Success) {
            $counts = [ordered]@{}
            foreach ($field in $fields) { $counts[$field] = [long]$match.Groups[$field].Value }
            if ($counts.Found -eq 0) { $status = 'empty' }
            elseif (($counts.Failed + $counts.Errored + $counts.Leaked + $counts.Ignored) -gt 0) { $status = 'failed' }
            elseif ($counts.Passed -eq $counts.Found) { $status = 'passed' }
        }
    }
    if ($shutdownLeak -and $status -eq 'passed') { $status = 'failed' }
    $exitCode = $ProcessExitCode
    if ($ProcessExitCode -ne 0) { $status = 'failed' }
    elseif ($status -ne 'passed') { $exitCode = 1 }
    [pscustomobject]@{ Status = $status; ExitCode = $exitCode; Counts = $counts; ShutdownLeakReport = $shutdownLeak }
}
