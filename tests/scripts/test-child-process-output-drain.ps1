$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Dak.ChildProcess.ps1')

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('dak-child-output-drain-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $stdoutLog = Join-Path $tempRoot 'chatty-child.log'
    $childScript = @'
for ($i = 0; $i -lt 20000; $i++) {
    [Console]::Out.WriteLine(("stdout line {0:00000} " -f $i) + ('x' * 96))
    [Console]::Error.WriteLine(("stderr line {0:00000} " -f $i) + ('y' * 96))
}
'@

    $result = Run-DakChild `
        -FileName 'pwsh' `
        -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $childScript) `
        -WorkingDirectory $PSScriptRoot `
        -LogPath $stdoutLog `
        -TimeoutMs 30000

    if ($result.ExitCode -ne 0) {
        throw "Expected chatty child to exit cleanly, got $($result.ExitCode). Log: $stdoutLog"
    }

    $text = Get-Content -LiteralPath $stdoutLog -Raw
    if ($text -notmatch 'stdout line 19999' -or $text -notmatch 'stderr line 19999') {
        throw "Expected drained stdout and stderr tail lines in log: $stdoutLog"
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force
    Write-Host 'PASS: shared child-process helper drains chatty stdout and stderr before waiting.'
}
catch {
    Write-Host "Preserving failing-run evidence under $tempRoot"
    throw
}
