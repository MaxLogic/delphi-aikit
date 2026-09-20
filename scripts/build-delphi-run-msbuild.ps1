param(
  [Parameter(Mandatory = $true)]
  [string]$MsBuild,
  [Parameter(Mandatory = $true)]
  [string]$Project,
  [Parameter(Mandatory = $true)]
  [string]$ArgsFile,
  [Parameter(Mandatory = $true)]
  [string]$OutLog,
  [Parameter(Mandatory = $false)]
  [int]$TimeoutSec = 0
)

$ErrorActionPreference = 'Stop'

try {
  $argsText = ''
  if (Test-Path -LiteralPath $ArgsFile -PathType Leaf) {
    $argsText = [IO.File]::ReadAllText($ArgsFile).Trim()
  }

  $argList = New-Object 'System.Collections.Generic.List[string]'
  # Start-Process flattens ArgumentList; keep the project path as one native argument (T-352).
  $argList.Add('"' + $Project + '"')
  if (-not [string]::IsNullOrWhiteSpace($argsText)) {
    $matches = [regex]::Matches($argsText, '(?:"(?:[^"]|"")*"|\S+)')
    foreach ($match in $matches) {
      $token = $match.Value
      if ([string]::IsNullOrWhiteSpace($token)) {
        continue
      }
      $argList.Add($token)
    }
  }

  $errLog = $OutLog + '.stderr.tmp'
  if (Test-Path -LiteralPath $errLog) {
    Remove-Item -LiteralPath $errLog -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $OutLog) {
    Remove-Item -LiteralPath $OutLog -Force -ErrorAction SilentlyContinue
  }

  $proc = Start-Process -FilePath $MsBuild -ArgumentList $argList.ToArray() -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput $OutLog -RedirectStandardError $errLog
  # Keep the native handle while waiting; Windows PowerShell can otherwise expose
  # a null ExitCode after a fast child exits, turning a native failure into exit 0 (T-353).
  $null = $proc.Handle

  if ($TimeoutSec -gt 0) {
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
      try {
        $proc.Kill()
      } catch {
      }
      exit 124
    }
  }

  $proc.WaitForExit()
  if (Test-Path -LiteralPath $errLog -PathType Leaf) {
    Add-Content -LiteralPath $OutLog -Value (Get-Content -LiteralPath $errLog -ErrorAction SilentlyContinue)
    Remove-Item -LiteralPath $errLog -Force -ErrorAction SilentlyContinue
  }
  exit $proc.ExitCode
} catch {
  exit 125
}
