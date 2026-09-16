#Requires -Version 7.0
# Launcher contract for the dak-static-analysis skill (T-329): the .bat and .sh files find DelphiAIKit.exe,
# forward their arguments to the native commands, convert WSL paths and return DAK's exit code. Every case
# runs the real executable on a real fixture; nothing stands in for DAK.

BeforeAll {
    $script:RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:SkillDir = Join-Path $script:RepoRoot 'agentskills/dak-static-analysis'
    $script:Dak = Join-Path $script:RepoRoot 'bin/DelphiAIKit.exe'
    $script:TestsExe = Join-Path $script:RepoRoot 'tests/DelphiAIKit.Tests.exe'
    $script:SystemPath = "$env:SystemRoot\System32;$env:SystemRoot"

    function New-LauncherWorkspace {
        param([string]$Name)
        $workspace = Join-Path $TestDrive $Name
        $source = Join-Path $workspace 'src'
        [void][IO.Directory]::CreateDirectory($source)
        Copy-Item (Join-Path $script:RepoRoot 'tests/fixtures/Sample.dproj') $source
        Copy-Item (Join-Path $script:RepoRoot 'tests/fixtures/Sample.dpr') $source
        [IO.File]::WriteAllText((Join-Path $source 'Sample.pas'), 'unit Sample; interface implementation end.')
        return $workspace
    }

    # Runs a launcher through cmd.exe with an explicit environment; returns exit code and combined output.
    function Invoke-Launcher {
        param([string]$Launcher, [string[]]$Arguments, [string]$WorkingDirectory, [hashtable]$Environment)
        $names = @('DAK_EXE', 'DAK_DELPHI', 'DAK_OUT', 'DAK_FIXINSIGHT', 'DAK_PASCAL_ANALYZER', 'PA_PATH',
            'DAK_TEST_PAL_EXIT', 'DAK_GATE', 'PATH') + @($Environment.Keys)
        $saved = @{}
        foreach ($name in $names | Sort-Object -Unique) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
        try {
            foreach ($name in @('DAK_EXE', 'DAK_DELPHI', 'DAK_OUT', 'DAK_FIXINSIGHT', 'DAK_PASCAL_ANALYZER', 'PA_PATH', 'DAK_TEST_PAL_EXIT', 'DAK_GATE')) {
                [Environment]::SetEnvironmentVariable($name, $null)
            }
            foreach ($name in $Environment.Keys) { [Environment]::SetEnvironmentVariable($name, $Environment[$name]) }
            $quoted = @($Arguments | ForEach-Object { if ($_ -match '[\s]') { '"' + $_ + '"' } else { $_ } }) -join ' '
            Push-Location $WorkingDirectory
            try {
                $output = & cmd.exe /d /c "call `"$Launcher`" $quoted" 2>&1 | Out-String
                $exit = $LASTEXITCODE
            } finally {
                Pop-Location
            }
        } finally {
            foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
        }
        return [pscustomobject]@{ ExitCode = $exit; Output = $output }
    }

    function ConvertTo-WslPath {
        param([string]$Path)
        $full = [IO.Path]::GetFullPath($Path)
        return '/mnt/' + $full.Substring(0, 1).ToLowerInvariant() + $full.Substring(2).Replace('\', '/')
    }

    function Invoke-WslLauncher {
        param([string]$Launcher, [string[]]$Arguments, [string]$WorkingDirectory, [string[]]$Environment)
        $output = & wsl.exe --cd $WorkingDirectory -e env @Environment bash (ConvertTo-WslPath (Join-Path $script:SkillDir $Launcher)) @Arguments 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    }

    function Read-Summary { param([string]$Out) Get-Content -LiteralPath (Join-Path $Out 'summary.json') -Raw | ConvertFrom-Json }
}

Describe 'Windows analysis launchers' {
    It 'forwards the project and workspace selector to analyze and returns its exit code' {
        $workspace = New-LauncherWorkspace 'analyze'
        $out = Join-Path $TestDrive 'analyze-out'
        $result = Invoke-Launcher (Join-Path $script:SkillDir 'analyze.bat') @((Join-Path $workspace 'src\Sample.dproj'), '--workspace-root', '.') $workspace @{
            DAK_EXE = $script:Dak; DAK_DELPHI = '23.0'; DAK_OUT = $out; DAK_FIXINSIGHT = 'false'; DAK_PASCAL_ANALYZER = 'false' }
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Read-Summary $out).workspace.root | Should -Be $workspace
        (Read-Summary $out).subject.kind | Should -Be 'project'

        $missing = Invoke-Launcher (Join-Path $script:SkillDir 'analyze.bat') @((Join-Path $workspace 'src\Absent.dproj')) $workspace @{
            DAK_EXE = $script:Dak; DAK_DELPHI = '23.0'; DAK_OUT = (Join-Path $TestDrive 'absent-out') }
        $missing.ExitCode | Should -Be 3 -Because 'the launcher returns DAK''s own exit code'
    }

    It 'maps a positional project to the unit project context' {
        $workspace = New-LauncherWorkspace 'unit'
        $out = Join-Path $TestDrive 'unit-out'
        $result = Invoke-Launcher (Join-Path $script:SkillDir 'analyze-unit.bat') @((Join-Path $workspace 'src\Sample.pas'), (Join-Path $workspace 'src\Sample.dproj'), '--workspace-root', '.') $workspace @{
            DAK_EXE = $script:Dak; DAK_DELPHI = '23.0'; DAK_OUT = $out; PA_PATH = $script:TestsExe; DAK_TEST_PAL_EXIT = '0' }
        $result.ExitCode | Should -Be 0 -Because $result.Output
        $summary = Read-Summary $out
        $summary.workspace.root | Should -Be $workspace
        $summary.subject.kind | Should -Be 'unit'
        $summary.subject.project_context | Should -Be (Join-Path $workspace 'src\Sample.dproj')
    }

    It 'passes the subject to the doctor by file type and forwards help' {
        $workspace = New-LauncherWorkspace 'doctor'
        $project = Invoke-Launcher (Join-Path $script:SkillDir 'doctor.bat') @((Join-Path $workspace 'src\Sample.dproj'), '--json') $workspace @{ DAK_EXE = $script:Dak }
        $project.Output | Should -Match ([regex]::Escape((Join-Path $workspace 'src\Sample.dproj').Replace('\', '\\')))
        $unit = Invoke-Launcher (Join-Path $script:SkillDir 'doctor.bat') @((Join-Path $workspace 'src\Sample.pas'), '--json') $workspace @{ DAK_EXE = $script:Dak }
        $unit.Output | Should -Match ([regex]::Escape((Join-Path $workspace 'src\Sample.pas').Replace('\', '\\')))
        foreach ($launcher in 'analyze.bat', 'analyze-unit.bat', 'doctor.bat') {
            $help = Invoke-Launcher (Join-Path $script:SkillDir $launcher) @('--help') $workspace @{ DAK_EXE = $script:Dak }
            $help.ExitCode | Should -Be 0 -Because "$launcher --help: $($help.Output)"
            $help.Output | Should -Match '--workspace-root' -Because $launcher
        }
    }

    It 'finds DAK in the skill repository, never in an outer checkout, and rejects a missing DAK_EXE' {
        $repo = Join-Path $TestDrive 'tool-repo'
        $skill = Join-Path $repo 'agentskills/dak-static-analysis'
        [void][IO.Directory]::CreateDirectory($skill)
        [void][IO.Directory]::CreateDirectory((Join-Path $repo 'bin'))
        Copy-Item (Join-Path $script:SkillDir 'find-dak.cmd'), (Join-Path $script:SkillDir 'analyze.bat') $skill
        Copy-Item $script:Dak, (Join-Path $script:RepoRoot 'bin/palcmd-map.json'), (Join-Path $script:RepoRoot 'bin/dak.ini') (Join-Path $repo 'bin')
        $outer = Join-Path $TestDrive 'outer'
        [void][IO.Directory]::CreateDirectory((Join-Path $outer '.git'))
        [void][IO.Directory]::CreateDirectory((Join-Path $outer 'bin'))
        # An outer tool that cannot run: choosing it would fail the launch.
        [IO.File]::WriteAllText((Join-Path $outer 'bin/DelphiAIKit.exe'), 'not an executable')
        $workspace = Join-Path $outer 'workspace'
        Copy-Item (New-LauncherWorkspace 'discovery') $workspace -Recurse
        $out = Join-Path $TestDrive 'discovery-out'
        $result = Invoke-Launcher (Join-Path $skill 'analyze.bat') @((Join-Path $workspace 'src\Sample.dproj'), '--workspace-root', '.') $workspace @{
            PATH = $script:SystemPath; DAK_DELPHI = '23.0'; DAK_OUT = $out; DAK_FIXINSIGHT = 'false'; DAK_PASCAL_ANALYZER = 'false' }
        $result.ExitCode | Should -Be 0 -Because $result.Output
        (Read-Summary $out).workspace.root | Should -Be $workspace

        $missing = Invoke-Launcher (Join-Path $skill 'analyze.bat') @((Join-Path $workspace 'src\Sample.dproj')) $workspace @{
            DAK_EXE = (Join-Path $TestDrive 'nowhere/DelphiAIKit.exe'); PATH = $script:SystemPath }
        $missing.ExitCode | Should -Be 2
        $missing.Output | Should -Match 'DAK_EXE points to missing file'

        $usage = Invoke-Launcher (Join-Path $skill 'analyze.bat') @() $workspace @{ PATH = $script:SystemPath }
        $usage.ExitCode | Should -Be 2
        $usage.Output | Should -Match 'Usage:'
    }
}

Describe 'WSL analysis launchers' {
    It 'converts paths and environment for analyze and analyze-unit and forwards help' {
        $workspace = New-LauncherWorkspace 'wsl'
        $projectOut = Join-Path $TestDrive 'wsl-project-out'
        $environment = @("DAK_EXE=$script:Dak", 'DAK_DELPHI=23.0', 'DAK_FIXINSIGHT=false', 'DAK_PASCAL_ANALYZER=false',
            "DAK_OUT=$(ConvertTo-WslPath $projectOut)")
        $project = Invoke-WslLauncher 'analyze.sh' @('src/Sample.dproj', '--workspace-root', '.') $workspace $environment
        $project.ExitCode | Should -Be 0 -Because $project.Output
        (Read-Summary $projectOut).workspace.root | Should -Be $workspace

        $unitOut = Join-Path $TestDrive 'wsl-unit-out'
        $environment = @("DAK_EXE=$script:Dak", 'DAK_DELPHI=23.0', "PA_PATH=$(ConvertTo-WslPath $script:TestsExe)",
            'DAK_TEST_PAL_EXIT=0', "DAK_OUT=$(ConvertTo-WslPath $unitOut)")
        $unit = Invoke-WslLauncher 'analyze-unit.sh' @('src/Sample.pas', 'src/Sample.dproj', '--workspace-root', '.') $workspace $environment
        $unit.ExitCode | Should -Be 0 -Because $unit.Output
        $summary = Read-Summary $unitOut
        $summary.workspace.root | Should -Be $workspace
        $summary.subject.project_context | Should -Be (Join-Path $workspace 'src\Sample.dproj')

        foreach ($launcher in 'analyze.sh', 'analyze-unit.sh', 'doctor.sh') {
            $help = Invoke-WslLauncher $launcher @('--help') $workspace @("DAK_EXE=$script:Dak")
            $help.ExitCode | Should -Be 0 -Because "$launcher --help: $($help.Output)"
            $help.Output | Should -Match '--workspace-root' -Because $launcher
        }
        $missing = Invoke-WslLauncher 'analyze.sh' @('src/Absent.dproj') $workspace @("DAK_EXE=$script:Dak", 'DAK_DELPHI=23.0',
            "DAK_OUT=$(ConvertTo-WslPath (Join-Path $TestDrive 'wsl-absent-out'))")
        $missing.ExitCode | Should -Be 3 -Because $missing.Output
    }
}
