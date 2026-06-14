$ErrorActionPreference = 'Stop'

function Start-DakChild {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [hashtable]$Environment = @{}
    )

    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FileName
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    if ($Arguments -is [array]) {
        foreach ($arg in $Arguments) {
            [void]$info.ArgumentList.Add([string]$arg)
        }
    } else {
        $info.Arguments = [string]$Arguments
    }
    foreach ($key in $Environment.Keys) {
        $info.Environment[$key] = [string]$Environment[$key]
    }

    $process = [Diagnostics.Process]::Start($info)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    return [pscustomobject]@{
        Process = $process
        StdoutTask = $stdoutTask
        StderrTask = $stderrTask
        LogPath = $LogPath
    }
}

function Complete-DakChild {
    param(
        [Parameter(Mandatory = $true)]$Run,
        [Parameter(Mandatory = $true)][int]$TimeoutMs
    )

    $stdout = ''
    $stderr = ''
    $exitCode = $null

    try {
        if (-not $Run.Process.WaitForExit($TimeoutMs)) {
            try { $Run.Process.Kill($true) } catch { try { $Run.Process.Kill() } catch {} }
            if (-not $Run.Process.WaitForExit(5000)) {
                Set-Content -LiteralPath $Run.LogPath -Value '' -Encoding UTF8
                throw "Process timed out and could not be stopped. Log: $($Run.LogPath)"
            }
            if (-not [Threading.Tasks.Task]::WaitAll(@($Run.StdoutTask, $Run.StderrTask), 5000)) {
                Set-Content -LiteralPath $Run.LogPath -Value '' -Encoding UTF8
                throw "Process timed out and output drain did not complete. Log: $($Run.LogPath)"
            }
            $stdout = $Run.StdoutTask.GetAwaiter().GetResult()
            $stderr = $Run.StderrTask.GetAwaiter().GetResult()
            Set-Content -LiteralPath $Run.LogPath -Value ($stdout + $stderr) -Encoding UTF8
            throw "Process timed out. Log: $($Run.LogPath)"
        }

        $Run.Process.WaitForExit()
        if (-not [Threading.Tasks.Task]::WaitAll(@($Run.StdoutTask, $Run.StderrTask), 5000)) {
            Set-Content -LiteralPath $Run.LogPath -Value '' -Encoding UTF8
            throw "Process output drain did not complete. Log: $($Run.LogPath)"
        }
        $stdout = $Run.StdoutTask.GetAwaiter().GetResult()
        $stderr = $Run.StderrTask.GetAwaiter().GetResult()
        $exitCode = $Run.Process.ExitCode
        Set-Content -LiteralPath $Run.LogPath -Value ($stdout + $stderr) -Encoding UTF8
        return [pscustomobject]@{
            ExitCode = $exitCode
            Stdout = $stdout
            Stderr = $stderr
            Text = $stdout + $stderr
            LogPath = $Run.LogPath
        }
    }
    finally {
        $Run.Process.Dispose()
    }
}

function Run-DakChild {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][object]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][int]$TimeoutMs,
        [hashtable]$Environment = @{}
    )

    $run = Start-DakChild `
        -FileName $FileName `
        -Arguments $Arguments `
        -WorkingDirectory $WorkingDirectory `
        -LogPath $LogPath `
        -Environment $Environment
    return Complete-DakChild -Run $run -TimeoutMs $TimeoutMs
}
