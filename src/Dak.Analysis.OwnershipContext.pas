unit Dak.Analysis.OwnershipContext;

interface

uses
  System.JSON,
  Dak.Analysis.Ownership;

function BuildAnalysisOwnershipContext(aSeed: TJSONObject;
  const aOutputRoot, aLegacyRoot: string; out aDiagnostics: TArray<string>): TAnalysisOwnershipContext;
// _checked_policy_roots and _maintained_nested_roots alone: the ownership boundaries the
// compatibility fingerprint covers, derived from the seed and the filesystem without any
// source inventory. Only fPolicyRoots and fMaintainedNestedRoots are filled.
function BuildAnalysisPolicyBoundaries(aSeed: TJSONObject): TAnalysisOwnershipContext;

implementation

uses
  System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.RegularExpressions,
  System.SysUtils,
  Dak.Analysis.ProjectSources, Dak.Analysis.SourceResolution, Dak.Analysis.Text, Dak.Analysis.Workspace;

function ObjectMember(aObject: TJSONObject; const aName: string): TJSONObject;
var
  lValue: TJSONValue;
begin
  Result := nil;
  if aObject = nil then
    Exit;
  lValue := aObject.GetValue(aName);
  if lValue is TJSONObject then
    Result := TJSONObject(lValue);
end;

function TextMember(aObject: TJSONObject; const aName: string): string;
var
  lValue: TJSONValue;
begin
  Result := '';
  if aObject = nil then
    Exit;
  lValue := aObject.GetValue(aName);
  if lValue is TJSONString then
    Result := lValue.Value;
end;

function SuppliedAbsolutePath(const aValue: string): string;
begin
  Result := aValue.Trim.Replace('/', '\');
  if not IsAbsoluteAnalysisPath(Result) then
    Result := '';
end;

function AbsolutePath(const aValue: string): string;
begin
  Result := SuppliedAbsolutePath(aValue);
  if Result <> '' then
    Result := ResolveFilesystemPath(Result);
end;

function ExistingDirectory(const aValue: string): string;
begin
  Result := AbsolutePath(aValue);
  if (Result <> '') and not TDirectory.Exists(Result) then
    Result := '';
end;

function PalSearchRoots(const aOutputRoot, aProjectDirectory: string): TArray<string>;
var
  lCommand: string;
  lLine: string;
  lMatch: TMatch;
  lPath: string;
  lRaw: string;
  lRoots: TList<string>;
  lRunLog: string;
  lSeen: TDictionary<string, Byte>;
  lValue: string;
begin
  Result := nil;
  lRunLog := TPath.Combine(aOutputRoot, 'run.log');
  if not TFile.Exists(lRunLog) then
    Exit;
  lCommand := '';
  for lLine in ReadAnalysisText(lRunLog).Split([#13, #10]) do
    if lLine.StartsWith('CMD:') and lLine.ToLower.Contains('palcmd.exe') then
      lCommand := lLine;
  lRoots := TList<string>.Create;
  lSeen := TDictionary<string, Byte>.Create(TIStringComparer.Ordinal);
  try
    for lMatch in TRegEx.Matches(lCommand, '(?:^|\s)/S=(?:"([^"]*)"|(\S+))') do
    begin
      lValue := lMatch.Groups[1].Value;
      if lValue = '' then
        lValue := lMatch.Groups[2].Value;
      for lRaw in lValue.Split([';']) do
      begin
        lPath := lRaw.Trim;
        if lPath = '' then
          Continue;
        if not IsAbsoluteAnalysisPath(lPath) then
        begin
          if aProjectDirectory = '' then
            Continue;
          lPath := TPath.Combine(aProjectDirectory, lPath);
        end;
        lPath := ExistingDirectory(lPath);
        if (lPath <> '') and not lSeen.ContainsKey(lPath) then
        begin
          lSeen.Add(lPath, 0);
          lRoots.Add(lPath);
        end;
      end;
    end;
    Result := lRoots.ToArray;
  finally
    lSeen.Free;
    lRoots.Free;
  end;
end;

procedure AddPolicyRoots(aValues: TJSONObject; const aName, aOwnership: string;
  aRoots: TList<TAnalysisOwnershipRoot>);
var
  lItem: TJSONValue;
  lRoot: TAnalysisOwnershipRoot;
  lValue: TJSONValue;
begin
  if aValues = nil then
    Exit;
  lValue := aValues.GetValue(aName);
  if not (lValue is TJSONArray) then
    Exit;
  // Policy validation owns the diagnostic; an invalid list must not be partially applied.
  for lItem in TJSONArray(lValue) do
    if not (lItem is TJSONString) or (lItem.Value.Trim = '') then
      Exit;
  for lItem in TJSONArray(lValue) do
  begin
    lRoot.fPath := ExistingDirectory(lItem.Value);
    if lRoot.fPath = '' then
      Continue;
    lRoot.fOwnership := aOwnership;
    aRoots.Add(lRoot);
  end;
end;

function RegisteredNestedRoots(aTarget: TJSONObject; const aWorkspace, aVcs: string): TArray<string>;
var
  lCandidates: TDictionary<string, Byte>;
  lItem: TJSONValue;
  lMatch: TMatch;
  lName: string;
  lOrdered: TArray<string>;
  lPath: string;
  lRoots: TList<string>;
  lValue: TJSONValue;
begin
  Result := nil;
  if aWorkspace = '' then
    Exit;
  lCandidates := TDictionary<string, Byte>.Create;
  try
    for lName in ['submodules', 'externals'] do
    begin
      if aTarget = nil then
        Break;
      lValue := aTarget.GetValue(lName);
      if not (lValue is TJSONArray) then
        Continue;
      for lItem in TJSONArray(lValue) do
        if lItem is TJSONObject then
        begin
          lPath := TextMember(TJSONObject(lItem), 'path');
          if lPath <> '' then
            lCandidates.AddOrSetValue(lPath, 0);
        end;
    end;
    lPath := TPath.Combine(aWorkspace, '.gitmodules');
    if SameText(aVcs, 'git') and TFile.Exists(lPath) then
      for lMatch in TRegEx.Matches(ReadAnalysisText(lPath), '^\s*path\s*=\s*(.+?)\s*$', [roMultiLine]) do
        lCandidates.AddOrSetValue(lMatch.Groups[1].Value, 0);
    lOrdered := lCandidates.Keys.ToArray;
    TArray.Sort<string>(lOrdered, TStringComparer.Ordinal);
    lRoots := TList<string>.Create;
    try
      for lPath in lOrdered do
      begin
        if IsAbsoluteAnalysisPath(lPath) then
          lName := ExistingDirectory(lPath)
        else
          lName := ExistingDirectory(TPath.Combine(aWorkspace, lPath));
        if lName <> '' then
          lRoots.Add(lName);
      end;
      Result := lRoots.ToArray;
    finally
      lRoots.Free;
    end;
  finally
    lCandidates.Free;
  end;
end;

procedure AddMaintainedNestedRoots(var aContext: TAnalysisOwnershipContext);
var
  lAncestor: string;
  lCombined: TList<string>;
  lMarker: string;
  lNested: string;
  lOrdered: TArray<string>;
  lParent: string;
  lPolicy: TAnalysisOwnershipRoot;
  lRoots: TDictionary<string, Byte>;
begin
  lRoots := TDictionary<string, Byte>.Create(TIStringComparer.Ordinal);
  try
    for lPolicy in aContext.fPolicyRoots do
    begin
      if lPolicy.fOwnership <> 'project' then
        Continue;
      lAncestor := lPolicy.fPath;
      while lAncestor <> '' do
      begin
        lMarker := TPath.Combine(lAncestor, '.git');
        if TFile.Exists(lMarker) or TDirectory.Exists(lMarker) or
          TFile.Exists(TPath.Combine(lAncestor, '.gitmodules')) then
        begin
          for lNested in RegisteredNestedRoots(nil, lAncestor, 'git') do
            if not SameText(lNested, lPolicy.fPath) and
              lNested.StartsWith(IncludeTrailingPathDelimiter(lPolicy.fPath), True) then
              lRoots.AddOrSetValue(lNested, 0);
          Break;
        end;
        lParent := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(lAncestor));
        if SameText(lParent, lAncestor) then
          Break;
        lAncestor := lParent;
      end;
    end;
    lOrdered := lRoots.Keys.ToArray;
    TArray.Sort<string>(lOrdered, TStringComparer.Ordinal);
    aContext.fMaintainedNestedRoots := Copy(lOrdered);
    lCombined := TList<string>.Create;
    try
      lCombined.AddRange(aContext.fNestedRoots);
      lCombined.AddRange(lOrdered);
      aContext.fNestedRoots := lCombined.ToArray;
    finally
      lCombined.Free;
    end;
  finally
    lRoots.Free;
  end;
end;

function BuildAnalysisPolicyBoundaries(aSeed: TJSONObject): TAnalysisOwnershipContext;
var
  lPolicy: TJSONObject;
  lRoots: TList<TAnalysisOwnershipRoot>;
begin
  Result := Default(TAnalysisOwnershipContext);
  lRoots := TList<TAnalysisOwnershipRoot>.Create;
  try
    lPolicy := ObjectMember(ObjectMember(aSeed, 'policy'), 'values');
    AddPolicyRoots(lPolicy, 'project_roots', 'project', lRoots);
    AddPolicyRoots(lPolicy, 'third_party_roots', 'third_party', lRoots);
    Result.fPolicyRoots := lRoots.ToArray;
  finally
    lRoots.Free;
  end;
  AddMaintainedNestedRoots(Result);
end;

function BuildAnalysisOwnershipContext(aSeed: TJSONObject;
  const aOutputRoot, aLegacyRoot: string; out aDiagnostics: TArray<string>): TAnalysisOwnershipContext;
var
  lDiagnostic: string;
  lDiagnostics: TList<string>;
  lPolicy: TJSONObject;
  lProject: string;
  lRoots: TList<TAnalysisOwnershipRoot>;
  lSubject: TJSONObject;
  lSubjectPath: string;
  lTarget: TJSONObject;
  lVcs: string;
  lWorkspace: TJSONObject;
begin
  Result := Default(TAnalysisOwnershipContext);
  aDiagnostics := nil;
  lDiagnostics := TList<string>.Create;
  try
    lWorkspace := ObjectMember(aSeed, 'workspace');
    lTarget := ObjectMember(ObjectMember(aSeed, 'provenance'), 'target');
    if lWorkspace <> nil then
    begin
      Result.fWorkspaceRoot := ExistingDirectory(TextMember(lWorkspace, 'root'));
      lVcs := TextMember(lWorkspace, 'vcs');
      if lVcs = '' then
        lVcs := TextMember(lTarget, 'vcs');
    end else if TextMember(lTarget, 'root') <> '' then
    begin
      Result.fWorkspaceRoot := ExistingDirectory(TextMember(lTarget, 'root'));
      lVcs := TextMember(lTarget, 'vcs');
    end else
    begin
      Result.fWorkspaceRoot := ExistingDirectory(aLegacyRoot);
      if Result.fWorkspaceRoot <> '' then
        lVcs := 'git';
    end;
    if lVcs = '' then
      lVcs := 'none';
    Result.fNestedRoots := RegisteredNestedRoots(lTarget, Result.fWorkspaceRoot, lVcs);
    lSubject := ObjectMember(aSeed, 'subject');
    // Relative references belong beside the supplied project, even when it is a file link.
    // The inventory resolves physical file identities separately.
    lSubjectPath := SuppliedAbsolutePath(TextMember(lSubject, 'path'));
    lProject := TextMember(lSubject, 'project_file');
    if lProject = '' then
      lProject := TextMember(lSubject, 'project_context');
    lProject := SuppliedAbsolutePath(lProject);
    if lProject <> '' then
      Result.fProjectDirectory := TPath.GetDirectoryName(lProject)
    else if lSubjectPath <> '' then
      Result.fProjectDirectory := TPath.GetDirectoryName(lSubjectPath);
    Result.fProjectFiles := CollectAnalysisProjectSources(lSubjectPath, lProject, lDiagnostic);
    Result.fSearchRoots := PalSearchRoots(aOutputRoot, Result.fProjectDirectory);
    if lDiagnostic <> '' then
      lDiagnostics.Add(lDiagnostic);
    try
      Result.fWorkspaceFiles := CollectAnalysisSourcePaths(Result.fWorkspaceRoot, lVcs, aOutputRoot);
    except
      on e: EInOutError do
        lDiagnostics.Add('Workspace source inventory: ' + e.Message);
      on e: EOSError do
        lDiagnostics.Add('Workspace source inventory: ' + e.Message);
    end;
    lRoots := TList<TAnalysisOwnershipRoot>.Create;
    try
      lPolicy := ObjectMember(ObjectMember(aSeed, 'policy'), 'values');
      AddPolicyRoots(lPolicy, 'project_roots', 'project', lRoots);
      AddPolicyRoots(lPolicy, 'third_party_roots', 'third_party', lRoots);
      Result.fPolicyRoots := lRoots.ToArray;
    finally
      lRoots.Free;
    end;
    AddMaintainedNestedRoots(Result);
    aDiagnostics := lDiagnostics.ToArray;
  finally
    lDiagnostics.Free;
  end;
end;

end.
