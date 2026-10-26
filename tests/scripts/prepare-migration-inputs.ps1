# Developer test setup only. Never link writable scratch repositories to main.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$Destination
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$destinationPath = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $destinationPath) { throw "Migration destination already exists: $destinationPath" }
$common = (& git -C $RepositoryRoot rev-parse --path-format=absolute --git-common-dir).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot locate the main checkout for pinned migration inputs.' }
$mainRoot = Split-Path $common -Parent
$relativeRoot = 'projects\.dak\DelphiAIKit\native-analysis-migration'
$sourceRoot = Join-Path $mainRoot $relativeRoot
$seed = Get-Content -LiteralPath (Join-Path $sourceRoot 'seeds\report-small\summary.json') -Raw | ConvertFrom-Json
$suffix = '\projects\.dak\DelphiAIKit\native-analysis-migration\scratch\report-small\repo\Sample.dpr'
$subject = [string]$seed.subject.path
if (-not $subject.EndsWith($suffix, [StringComparison]::Ordinal)) { throw 'Unrecognized canonical migration subject.' }
$canonicalCheckout = $subject.Substring(0, $subject.Length - $suffix.Length)
[void][IO.Directory]::CreateDirectory($destinationPath)
[IO.File]::WriteAllText((Join-Path $destinationPath 'canonical-checkout.txt'), $canonicalCheckout)
foreach ($scenario in 'report-small', 'report-large') {
    $sourceRepo = Join-Path $sourceRoot "scratch\$scenario\repo"
    $targetRepo = Join-Path $destinationPath "scratch\$scenario\repo"
    [void][IO.Directory]::CreateDirectory((Split-Path $targetRepo -Parent))
    & git clone --quiet --no-hardlinks --no-local $sourceRepo $targetRepo
    if ($LASTEXITCODE -ne 0) { throw "Cannot clone pinned synthetic repository $scenario" }
    $oldRepo = Join-Path $canonicalCheckout "$relativeRoot\scratch\$scenario\repo"
    foreach ($bundle in @("seeds\$scenario", "measurements\report-baseline-01\$scenario\cold-1\artifacts")) {
        $source = Join-Path $sourceRoot $bundle
        $target = Join-Path $destinationPath $bundle
        $entries = @(Get-ChildItem -LiteralPath $source -Recurse -Force)
        if ($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw "Link in pinned bundle: $source" }
        foreach ($file in $entries | Where-Object { -not $_.PSIsContainer }) {
            $output = Join-Path $target ($file.FullName.Substring($source.Length + 1))
            [void][IO.Directory]::CreateDirectory((Split-Path $output -Parent))
            if ($bundle.StartsWith('seeds\', [StringComparison]::Ordinal)) {
                # Seed inputs must name the private clone. Reference bytes remain untouched.
                $text = [IO.File]::ReadAllText($file.FullName)
                foreach ($pair in @(@($oldRepo.Replace('\','\\'), $targetRepo.Replace('\','\\')),
                                    @($oldRepo.Replace('\','/'), $targetRepo.Replace('\','/')),
                                    @($oldRepo, $targetRepo))) {
                    $text = $text.Replace($pair[0], $pair[1])
                }
                [IO.File]::WriteAllText($output, $text, [Text.UTF8Encoding]::new($false))
            } else { [IO.File]::Copy($file.FullName, $output) }
        }
    }
}
$destinationPath
