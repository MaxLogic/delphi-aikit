Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sourceRoot = Join-Path $repoRoot 'src'

$publicUnits = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($unit in @(
    'DelphiSemantics.Api',
    'DelphiSemantics.Api.ProjectOptions',
    'DelphiSemantics.Api.RemoveWith',
    'DelphiSemantics.Api.RemoveWith.Compatibility',
    'DelphiSemantics.Api.WithBinding',
    'DelphiSemantics.Version'
  )) {
  [void]$publicUnits.Add($unit)
}

$temporaryCompatibilityExceptions = @{}
foreach ($exception in @(
    @{
      Key = 'src\Dak.DeadCodeProfile.pas|DelphiSemantics.DeadCode'
      Task = 'T-450'
      Reason = 'DAK dead-code profile facade is the documented command-boundary adapter.'
    },
    @{
      Key = 'src\dak.deps.runner.pas|DelphiSemantics.Graph'
      Task = 'T-328'
      Reason = 'Deps runner is a temporary compatibility boundary until dependency graph APIs are facade-owned.'
    },
    @{
      Key = 'src\dak.deps.runner.pas|DelphiSemantics.ProjectContext'
      Task = 'T-328'
      Reason = 'Deps runner still needs project context while the public surface is enforced.'
    },
    @{
      Key = 'src\Dak.DfmText.pas|DelphiSemantics.Source'
      Task = 'T-328'
      Reason = 'Shared DFM text parsing keeps source provenance behind a DAK adapter.'
    },
    @{
      Key = 'src\Dak.GlobalVars.Semantics.pas|DelphiSemantics.GlobalVars'
      Task = 'T-328'
      Reason = 'Global-vars command adapter owns this Semantics analysis bridge.'
    },
    @{
      Key = 'src\Dak.GlobalVars.Semantics.pas|DelphiSemantics.ProjectContext'
      Task = 'T-328'
      Reason = 'Global-vars command adapter still maps project context directly.'
    },
    @{
      Key = 'src\dak.lsp.context.pas|DelphiSemantics.Lsp'
      Task = 'T-328'
      Reason = 'LSP context loader remains a temporary direct bridge.'
    },
    @{
      Key = 'src\dak.macroexpander.pas|DelphiSemantics.ProjectContext'
      Task = 'T-328'
      Reason = 'MSBuild macro expansion still relies on Semantics project context parsing.'
    },
    @{
      Key = 'src\dak.msbuild.pas|DelphiSemantics.ProjectContext'
      Task = 'T-328'
      Reason = 'MSBuild project loader still relies on Semantics project context parsing.'
    },
    @{
      Key = 'src\Dak.Project.BuildParams.pas|DelphiSemantics.CompilerProfile'
      Task = 'T-328'
      Reason = 'Project build parameter mapping still consumes compiler-profile discovery directly.'
    },
    @{
      Key = 'src\Dak.Project.Semantics.pas|DelphiSemantics.CompilerProfile'
      Task = 'T-328'
      Reason = 'Semantic project options still map compiler-profile values at the DAK boundary.'
    },
    @{
      Key = 'src\Dak.RadStudio.Locator.pas|DelphiSemantics.CompilerProfile'
      Task = 'T-328'
      Reason = 'RAD Studio locator still shares Semantics compiler-profile discovery.'
    },
    @{
      Key = 'src\Dak.Refactor.pas|DelphiSemantics.DeadCode'
      Task = 'T-450'
      Reason = 'Refactor command uses the DAK dead-code profile facade created by T-450.'
    },
    @{
      Key = 'src\Dak.Refactor.pas|DelphiSemantics.Model.Text'
      Task = 'T-434'
      Reason = 'Shared Pascal lexical helpers are intentionally centralized in Semantics.'
    },
    @{
      Key = 'src\Dak.Refactor.pas|DelphiSemantics.ProjectContext'
      Task = 'T-353'
      Reason = 'Refactor command keeps project context until snapshot-backed query contexts land.'
    },
    @{
      Key = 'src\Dak.Refactor.pas|DelphiSemantics.Refactor'
      Task = 'T-353'
      Reason = 'Refactor command keeps raw plan DTOs until the snapshot-backed facade is complete.'
    },
    @{
      Key = 'src\Dak.Refactor.pas|DelphiSemantics.Usage'
      Task = 'T-353'
      Reason = 'Refactor command keeps raw usage DTOs until the snapshot-backed facade is complete.'
    },
    @{
      Key = 'src\Dak.Refactor.RenameGuards.pas|DelphiSemantics.Refactor'
      Task = 'T-353'
      Reason = 'Rename guard still consumes Semantics refactor DTOs during the query-context migration.'
    },
    @{
      Key = 'src\Dak.RemoveWith.Discovery.pas|DelphiSemantics.Model.Text'
      Task = 'T-434'
      Reason = 'Shared Pascal lexical helpers are intentionally centralized in Semantics.'
    },
    @{
      Key = 'src\Dak.RemoveWith.Model.pas|DelphiSemantics.Model.Text'
      Task = 'T-434'
      Reason = 'Shared Pascal lexical helpers are intentionally centralized in Semantics.'
    },
    @{
      Key = 'src\Dak.RemoveWith.Planner.pas|DelphiSemantics.Model.Text'
      Task = 'T-434'
      Reason = 'Shared Pascal lexical helpers are intentionally centralized in Semantics.'
    },
    @{
      Key = 'src\Dak.RemoveWith.Resolver.pas|DelphiSemantics.Model'
      Task = 'T-328'
      Reason = 'Remove-with resolver remains a compatibility adapter around Semantics model facts.'
    },
    @{
      Key = 'src\Dak.RemoveWith.Resolver.pas|DelphiSemantics.Model.Text'
      Task = 'T-434'
      Reason = 'Shared Pascal lexical helpers are intentionally centralized in Semantics.'
    },
    @{
      Key = 'src\Dak.RemoveWith.Resolver.pas|DelphiSemantics.WithBinding'
      Task = 'T-328'
      Reason = 'Remove-with resolver still bridges legacy with-binding facts.'
    },
    @{
      Key = 'src\Dak.RemoveWith.Symbols.pas|DelphiSemantics.Cache'
      Task = 'T-331'
      Reason = 'Remove-with semantic planning still maps cache/compiler context directly.'
    },
    @{
      Key = 'src\Dak.RemoveWith.Symbols.pas|DelphiSemantics.CompilerProfile'
      Task = 'T-331'
      Reason = 'Remove-with apply verification owns the remaining compiler-context migration.'
    },
    @{
      Key = 'src\Dak.RemoveWith.Symbols.pas|DelphiSemantics.Model'
      Task = 'T-331'
      Reason = 'Remove-with semantic planning still projects Semantics model facts into DAK symbols.'
    },
    @{
      Key = 'src\Dak.RemoveWith.Symbols.pas|DelphiSemantics.Model.Text'
      Task = 'T-434'
      Reason = 'Shared Pascal lexical helpers are intentionally centralized in Semantics.'
    },
    @{
      Key = 'src\Dak.RemoveWith.TempPolicy.pas|DelphiSemantics.Model.Text'
      Task = 'T-434'
      Reason = 'Shared Pascal lexical helpers are intentionally centralized in Semantics.'
    },
    @{
      Key = 'src\Dak.Semantics.Session.pas|DelphiSemantics.GlobalVars'
      Task = 'T-328'
      Reason = 'Central DAK Semantics adapter owns this temporary global-vars bridge.'
    },
    @{
      Key = 'src\Dak.Semantics.Session.pas|DelphiSemantics.Graph'
      Task = 'T-328'
      Reason = 'Central DAK Semantics adapter owns this temporary dependency-graph bridge.'
    },
    @{
      Key = 'src\Dak.Semantics.Session.pas|DelphiSemantics.ProjectContext'
      Task = 'T-328'
      Reason = 'Central DAK Semantics adapter owns this project-context bridge.'
    },
    @{
      Key = 'src\Dak.Semantics.Session.pas|DelphiSemantics.Refactor'
      Task = 'T-353'
      Reason = 'Central adapter exposes raw refactor DTOs until snapshot-backed query contexts land.'
    },
    @{
      Key = 'src\Dak.Semantics.Session.pas|DelphiSemantics.Usage'
      Task = 'T-353'
      Reason = 'Central adapter exposes raw usage DTOs until snapshot-backed query contexts land.'
    },
    @{
      Key = 'src\Dak.Semantics.Session.pas|DelphiSemantics.Cache'
      Task = 'T-353'
      Reason = 'Central adapter still maps cache metrics from the project session.'
    },
    @{
      Key = 'src\Dak.Semantics.Session.pas|DelphiSemantics.Model'
      Task = 'T-353'
      Reason = 'Central adapter still validates model-only query contexts before T-353.'
    },
    @{
      Key = 'src\Dak.Semantics.Session.pas|DelphiSemantics.ProjectSession'
      Task = 'T-353'
      Reason = 'Central adapter owns raw project-session access until T-353 replaces the query path.'
    },
    @{
      Key = 'src\Dak.Semantics.Session.pas|DelphiSemantics.Query'
      Task = 'T-353'
      Reason = 'Central adapter owns raw query-context access until T-353 replaces the query path.'
    },
    @{
      Key = 'src\dak.sourcecontext.pas|DelphiSemantics.ProjectContext'
      Task = 'T-328'
      Reason = 'Source-context command still maps Semantics project context at the DAK boundary.'
    },
    @{
      Key = 'src\dak.sourcecontext.pas|DelphiSemantics.SourceContext'
      Task = 'T-328'
      Reason = 'Source-context command remains the DAK adapter for Semantics source facts.'
    },
    @{
      Key = 'src\Dak.SymbolMap.Cache.pas|DelphiSemantics.Cache'
      Task = 'T-442'
      Reason = 'SymbolMap cache projection still stores Semantics cache/model identity data.'
    },
    @{
      Key = 'src\Dak.SymbolMap.Cache.pas|DelphiSemantics.CompilerProfile'
      Task = 'T-442'
      Reason = 'SymbolMap cache projection still stores compiler-profile identity data.'
    },
    @{
      Key = 'src\Dak.SymbolMap.Cache.pas|DelphiSemantics.Model'
      Task = 'T-442'
      Reason = 'SymbolMap cache projection still persists Semantics model facts.'
    },
    @{
      Key = 'src\Dak.SymbolMap.Cache.pas|DelphiSemantics.Preprocess'
      Task = 'T-442'
      Reason = 'SymbolMap cache projection still persists preprocessing diagnostics.'
    },
    @{
      Key = 'src\Dak.SymbolMap.Indexer.pas|DelphiSemantics.Model'
      Task = 'T-442'
      Reason = 'Unit-level SymbolMap compatibility extractor still projects Semantics model facts.'
    },
    @{
      Key = 'src\Dak.SymbolMap.Indexer.pas|DelphiSemantics.Model.Text'
      Task = 'T-434'
      Reason = 'Shared Pascal lexical helpers are intentionally centralized in Semantics.'
    },
    @{
      Key = 'src\Dak.SymbolMap.Indexer.pas|DelphiSemantics.ProjectContext'
      Task = 'T-442'
      Reason = 'SymbolMap project indexing still maps Semantics project context.'
    },
    @{
      Key = 'src\Dak.SymbolMap.Indexer.pas|DelphiSemantics.ProjectSession'
      Task = 'T-442'
      Reason = 'SymbolMap project indexing uses the Semantics project session authority.'
    },
    @{
      Key = 'src\Dak.SymbolMap.Query.pas|DelphiSemantics.ProjectContext'
      Task = 'T-442'
      Reason = 'SymbolMap query projection still maps Semantics project context.'
    },
    @{
      Key = 'projects\DelphiAIKit.dproj|DelphiSemantics.Graph'
      Task = 'T-328'
      Reason = 'Build manifest keeps this internal unit until the deps facade is migrated.'
    },
    @{
      Key = 'projects\DelphiAIKit.dproj|DelphiSemantics.GlobalVars'
      Task = 'T-328'
      Reason = 'Build manifest keeps this internal unit until the global-vars facade is migrated.'
    },
    @{
      Key = 'projects\DelphiAIKit.dproj|DelphiSemantics.Lsp'
      Task = 'T-328'
      Reason = 'Build manifest keeps this internal unit until the LSP facade is migrated.'
    },
    @{
      Key = 'projects\DelphiAIKit.dproj|DelphiSemantics.Model'
      Task = 'T-328'
      Reason = 'Build manifest keeps this internal unit while DAK compatibility adapters still expose model DTOs.'
    },
    @{
      Key = 'projects\DelphiAIKit.dproj|DelphiSemantics.ProjectContext'
      Task = 'T-328'
      Reason = 'Build manifest keeps this internal unit while project-context callers remain direct.'
    },
    @{
      Key = 'projects\DelphiAIKit.dproj|DelphiSemantics.Source'
      Task = 'T-328'
      Reason = 'Build manifest keeps this internal unit while DAK source-text adapters remain direct.'
    },
    @{
      Key = 'projects\DelphiAIKit.dproj|DelphiSemantics.SourceContext'
      Task = 'T-328'
      Reason = 'Build manifest keeps this internal unit while source-context callers remain direct.'
    },
    @{
      Key = 'projects\DelphiAIKit.dproj|DelphiSemantics.WithBinding'
      Task = 'T-328'
      Reason = 'Build manifest keeps this internal unit while remove-with compatibility adapters remain direct.'
    },
    @{
      Key = 'tests\DelphiAIKit.Tests.dproj|DelphiSemantics.Graph'
      Task = 'T-328'
      Reason = 'Test manifest mirrors production Semantics references for the deps integration lane.'
    },
    @{
      Key = 'tests\DelphiAIKit.Tests.dproj|DelphiSemantics.GlobalVars'
      Task = 'T-328'
      Reason = 'Test manifest mirrors production Semantics references for the global-vars integration lane.'
    },
    @{
      Key = 'tests\DelphiAIKit.Tests.dproj|DelphiSemantics.Lsp'
      Task = 'T-328'
      Reason = 'Test manifest mirrors production Semantics references for the LSP integration lane.'
    },
    @{
      Key = 'tests\DelphiAIKit.Tests.dproj|DelphiSemantics.Model'
      Task = 'T-328'
      Reason = 'Test manifest mirrors production Semantics references while compatibility adapters expose model DTOs.'
    },
    @{
      Key = 'tests\DelphiAIKit.Tests.dproj|DelphiSemantics.ProjectContext'
      Task = 'T-328'
      Reason = 'Test manifest mirrors production Semantics references for project-context callers.'
    },
    @{
      Key = 'tests\DelphiAIKit.Tests.dproj|DelphiSemantics.Source'
      Task = 'T-328'
      Reason = 'Test manifest mirrors production Semantics references for DAK source-text adapters.'
    },
    @{
      Key = 'tests\DelphiAIKit.Tests.dproj|DelphiSemantics.SourceContext'
      Task = 'T-328'
      Reason = 'Test manifest mirrors production Semantics references for source-context callers.'
    },
    @{
      Key = 'tests\DelphiAIKit.Tests.dproj|DelphiSemantics.WithBinding'
      Task = 'T-328'
      Reason = 'Test manifest mirrors production Semantics references for remove-with compatibility adapters.'
    }
  )) {
  if ($temporaryCompatibilityExceptions.ContainsKey($exception.Key)) {
    throw "Duplicate DelphiSemantics compatibility exception: $($exception.Key)"
  }
  $temporaryCompatibilityExceptions[$exception.Key] = $exception
}

function ConvertTo-CommentFreeDelphiText {
  param([Parameter(Mandatory = $true)][string]$Text)

  $withoutBlockComments = [regex]::Replace($Text, '(?s)\{.*?\}|\(\*.*?\*\)', '')
  return [regex]::Replace($withoutBlockComments, '(?m)//.*$', '')
}

function Get-RelativeRepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $fullPath = [IO.Path]::GetFullPath($Path)
  if (-not $fullPath.StartsWith($repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Path is outside repo root. Path=$fullPath Root=$repoRoot"
  }
  return $fullPath.Substring($repoRoot.Length + 1)
}

function Get-DelphiSemanticsImport {
  $files = Get-ChildItem -LiteralPath $sourceRoot -Recurse -Filter '*.pas' -File |
    Where-Object { $_.FullName -notmatch '\\__history\\' } |
    Sort-Object FullName

  foreach ($file in $files) {
    $source = Get-Content -LiteralPath $file.FullName -Raw
    $sourceWithoutComments = ConvertTo-CommentFreeDelphiText $source
    $usesSections = [regex]::Matches($sourceWithoutComments, '(?is)\buses\b(?<body>.*?);')
    foreach ($usesSection in $usesSections) {
      foreach ($rawUnit in ($usesSection.Groups['body'].Value -split ',')) {
        $unit = $rawUnit.Trim()
        if ($unit -match '^DelphiSemantics\.[A-Za-z0-9_.]+$') {
          [pscustomobject]@{
            File = Get-RelativeRepoPath $file.FullName
            Unit = $unit
          }
        }
      }
    }
  }
}

function Get-DelphiSemanticsProjectReference {
  foreach ($projectFileName in @(
      (Join-Path $repoRoot 'projects\DelphiAIKit.dproj'),
      (Join-Path $repoRoot 'tests\DelphiAIKit.Tests.dproj')
    )) {
    if (-not (Test-Path -LiteralPath $projectFileName -PathType Leaf)) {
      throw "Project file not found: $projectFileName"
    }

    [xml]$project = Get-Content -LiteralPath $projectFileName -Raw
    $namespaceManager = [Xml.XmlNamespaceManager]::new($project.NameTable)
    $namespaceManager.AddNamespace('msb', 'http://schemas.microsoft.com/developer/msbuild/2003')
    $references = $project.SelectNodes('//msb:DCCReference', $namespaceManager)
    foreach ($reference in $references) {
      $include = [string]$reference.Include
      if ($include -notmatch '(?i)(^|[\\/])DelphiSemantics[\\/]src[\\/](?<unit>DelphiSemantics\.[A-Za-z0-9_.]+)\.pas$') {
        continue
      }

      [pscustomobject]@{
        File = Get-RelativeRepoPath $projectFileName
        Unit = $Matches['unit']
      }
    }
  }
}

function Test-TaskId {
  param([Parameter(Mandatory = $true)][string]$TaskId)

  return $TaskId -match '^T-\d{3,}$'
}

$imports = @(
  Get-DelphiSemanticsImport
  Get-DelphiSemanticsProjectReference
)
$violations = [System.Collections.Generic.List[string]]::new()
$seenInternalKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($import in $imports) {
  if ($publicUnits.Contains($import.Unit)) {
    continue
  }

  $key = "$($import.File)|$($import.Unit)"
  [void]$seenInternalKeys.Add($key)
  if (-not $temporaryCompatibilityExceptions.ContainsKey($key)) {
    $violations.Add("FORBIDDEN $($import.File) imports internal $($import.Unit) without a compatibility exception.")
    continue
  }

  $exception = $temporaryCompatibilityExceptions[$key]
  if (-not (Test-TaskId $exception.Task)) {
    $violations.Add("INVALID $key has no owning task ID.")
  }
  if ([string]::IsNullOrWhiteSpace($exception.Reason)) {
    $violations.Add("INVALID $key has no reason.")
  }
}

foreach ($key in $temporaryCompatibilityExceptions.Keys) {
  if (-not $seenInternalKeys.Contains($key)) {
    $violations.Add("STALE $key is listed as a compatibility exception but is not present in scanned source/project references.")
  }
}

if ($violations.Count -gt 0) {
  $message = "DelphiSemantics public-surface check failed with $($violations.Count) violation(s).`n" +
    ($violations -join "`n")
  throw $message
}

Write-Output "PASS DelphiSemantics public-surface check: $($imports.Count) imports, $($seenInternalKeys.Count) documented internal exceptions."
