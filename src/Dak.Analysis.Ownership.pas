unit Dak.Analysis.Ownership;

interface

type
  TAnalysisOwnershipRoot = record
    fOwnership: string;
    fPath: string;
  end;

  // All paths are resolved absolute identities supplied by the per-run context builder.
  TAnalysisOwnershipContext = record
    fWorkspaceRoot: string;
    fProjectDirectory: string;
    fProjectFiles: TArray<string>;
    fWorkspaceFiles: TArray<string>;
    fNestedRoots: TArray<string>;
    // Nested repositories registered below maintained project roots; a subset of fNestedRoots
    // that the compatibility fingerprint records separately.
    fMaintainedNestedRoots: TArray<string>;
    fSearchRoots: TArray<string>;
    fPolicyRoots: TArray<TAnalysisOwnershipRoot>;
  end;

  TAnalysisSourceOwnership = record
    fOwnership: string;
    fRoot: string;
  end;

function ClassifyAnalysisSource(const aResolvedPath: string;
  const aContext: TAnalysisOwnershipContext): TAnalysisSourceOwnership;

implementation

uses
  System.IOUtils, System.SysUtils;

function IsWithinRoot(const aPath, aRoot: string): Boolean;
var
  lRoot: string;
begin
  if aRoot = '' then
    Exit(False);
  lRoot := ExcludeTrailingPathDelimiter(aRoot);
  Result := SameText(aPath, lRoot) or
    aPath.StartsWith(IncludeTrailingPathDelimiter(lRoot), True);
end;

function NearestRoot(const aPath: string; const aRoots: TArray<string>): string;
var
  lRoot: string;
begin
  Result := '';
  for lRoot in aRoots do
    if IsWithinRoot(aPath, lRoot) and (Length(lRoot) > Length(Result)) then
      Result := lRoot;
end;

function IsProjectFile(const aPath: string; const aContext: TAnalysisOwnershipContext): Boolean;
var
  lPath: string;
begin
  for lPath in aContext.fProjectFiles do
    if SameText(aPath, lPath) then
      Exit(True);
  Result := False;
end;

function TryPolicyOwnership(const aPath, aNestedRoot: string;
  const aContext: TAnalysisOwnershipContext; out aResult: TAnalysisSourceOwnership): Boolean;
var
  lConflict: Boolean;
  lMaintainedRoot: string;
  lPolicy: TAnalysisOwnershipRoot;
begin
  Result := False;
  aResult := Default(TAnalysisSourceOwnership);
  // Settings cannot hide a warning in automatically owned source.
  if (aNestedRoot = '') and (IsWithinRoot(aPath, aContext.fWorkspaceRoot) or
    ((aContext.fWorkspaceRoot = '') and IsProjectFile(aPath, aContext))) then
    Exit;
  lConflict := False;
  lMaintainedRoot := '';
  for lPolicy in aContext.fPolicyRoots do
  begin
    if not IsWithinRoot(aPath, lPolicy.fPath) then
      Continue;
    if (lPolicy.fOwnership = 'project') and (Length(lPolicy.fPath) > Length(lMaintainedRoot)) then
      lMaintainedRoot := lPolicy.fPath;
    if Length(lPolicy.fPath) > Length(aResult.fRoot) then
    begin
      aResult.fOwnership := lPolicy.fOwnership;
      aResult.fRoot := lPolicy.fPath;
      lConflict := False;
      Result := True;
    end else if (Length(lPolicy.fPath) = Length(aResult.fRoot)) and
      (lPolicy.fOwnership <> aResult.fOwnership) then
      lConflict := True;
  end;
  if not Result then
    Exit;
  if not lConflict and (lMaintainedRoot <> '') then
  begin
    if Length(aNestedRoot) > Length(lMaintainedRoot) then
    begin
      aResult.fOwnership := 'third_party';
      aResult.fRoot := aNestedRoot;
    end else if aResult.fOwnership = 'third_party' then
      lConflict := True;
  end;
  if lConflict then
  begin
    aResult.fOwnership := 'unknown';
    aResult.fRoot := '';
  end;
end;

function ClassifyAnalysisSource(const aResolvedPath: string;
  const aContext: TAnalysisOwnershipContext): TAnalysisSourceOwnership;
var
  lNestedRoot: string;
begin
  Result := Default(TAnalysisSourceOwnership);
  Result.fOwnership := 'unknown';
  if aResolvedPath = '' then
    Exit;
  lNestedRoot := NearestRoot(aResolvedPath, aContext.fNestedRoots);
  if TryPolicyOwnership(aResolvedPath, lNestedRoot, aContext, Result) then
    Exit;
  if lNestedRoot <> '' then
  begin
    Result.fOwnership := 'third_party';
    Result.fRoot := lNestedRoot;
  end else if (aContext.fWorkspaceRoot <> '') and
    not IsWithinRoot(aResolvedPath, aContext.fWorkspaceRoot) then
    Result.fOwnership := 'third_party'
  else if IsProjectFile(aResolvedPath, aContext) then
  begin
    Result.fOwnership := 'project';
    Result.fRoot := aContext.fProjectDirectory;
  end else if aContext.fWorkspaceRoot <> '' then
  begin
    Result.fOwnership := 'repository';
    Result.fRoot := aContext.fWorkspaceRoot;
  end else
    Result.fOwnership := 'third_party';
  if (Result.fOwnership = 'third_party') and (Result.fRoot = '') then
  begin
    Result.fRoot := NearestRoot(aResolvedPath, aContext.fSearchRoots);
    if Result.fRoot = '' then
      Result.fRoot := TPath.GetDirectoryName(aResolvedPath);
  end;
end;

end.
