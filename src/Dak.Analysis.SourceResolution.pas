unit Dak.Analysis.SourceResolution;

interface

uses
  System.Generics.Collections, System.JSON,
  Dak.Analysis.Ownership;

type
  TAnalysisSourceResolver = class
  private
    fContext: TAnalysisOwnershipContext;
    fBasenames: TDictionary<string, string>;
    fResolved: TDictionary<string, string>;
    procedure AddSource(const aPath: string);
    function ResolveUncached(const aRawPath: string): string;
    function FixInsightDisplay(const aRawPath, aResolved: string): string;
  public
    constructor Create(const aContext: TAnalysisOwnershipContext);
    destructor Destroy; override;
    function Resolve(const aRawPath: string): string;
    procedure AnnotatePal(aRows: TJSONArray);
    procedure AnnotateFixInsight(aRows: TJSONArray);
  end;

function IsAbsoluteAnalysisPath(const aPath: string): Boolean;

implementation

uses
  System.Generics.Defaults, System.IOUtils, System.SysUtils,
  Dak.Analysis.Workspace;

function ExistingPath(const aPath: string; aRequireFile: Boolean): string;
begin
  Result := '';
  if TFile.Exists(aPath) or (not aRequireFile and TDirectory.Exists(aPath)) then
    Result := ResolveFilesystemPath(aPath);
end;

function IsAbsoluteAnalysisPath(const aPath: string): Boolean;
begin
  Result := aPath.StartsWith('\\') or
    ((Length(aPath) >= 3) and (aPath[2] = ':') and CharInSet(aPath[3], ['\', '/']));
end;

constructor TAnalysisSourceResolver.Create(const aContext: TAnalysisOwnershipContext);
var
  lPath: string;
begin
  inherited Create;
  fContext := aContext;
  fBasenames := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  fResolved := TDictionary<string, string>.Create;
  for lPath in fContext.fProjectFiles do
    AddSource(lPath);
  for lPath in fContext.fWorkspaceFiles do
    AddSource(lPath);
end;

destructor TAnalysisSourceResolver.Destroy;
begin
  fResolved.Free;
  fBasenames.Free;
  inherited;
end;

procedure TAnalysisSourceResolver.AddSource(const aPath: string);
var
  lName: string;
  lPrevious: string;
begin
  lName := TPath.GetFileName(aPath);
  if not fBasenames.TryGetValue(lName, lPrevious) then
    fBasenames.Add(lName, aPath)
  else if not SameText(lPrevious, aPath) then
    // An empty value permanently marks ambiguity, even if another occurrence repeats one file.
    fBasenames[lName] := '';
end;

function TAnalysisSourceResolver.ResolveUncached(const aRawPath: string): string;
var
  lCandidates: TDictionary<string, string>;
  lKey: string;
  lMapped: string;
  lPath: string;
  lPolicy: TAnalysisOwnershipRoot;
  lRoot: string;
begin
  Result := '';
  if aRawPath = '' then
    Exit;
  if IsAbsoluteAnalysisPath(aRawPath) then
    Exit(ExistingPath(aRawPath, False));
  lPath := aRawPath.Replace('/', '\');
  for lRoot in [fContext.fProjectDirectory, fContext.fWorkspaceRoot] do
    if lRoot <> '' then
    begin
      Result := ExistingPath(TPath.Combine(lRoot, lPath), True);
      if Result <> '' then
        Exit;
    end;
  for lRoot in fContext.fSearchRoots do
  begin
    Result := ExistingPath(TPath.Combine(lRoot, lPath), True);
    if Result <> '' then
      Exit;
  end;
  if not lPath.Contains('\') and fBasenames.TryGetValue(lPath, lMapped) and (lMapped <> '') then
  begin
    Result := ExistingPath(lMapped, True);
    if Result <> '' then
      Exit;
  end;
  lCandidates := TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  try
    for lPolicy in fContext.fPolicyRoots do
    begin
      lMapped := ExistingPath(TPath.Combine(lPolicy.fPath, lPath), True);
      if lMapped = '' then
        Continue;
      // Reference ambiguity includes policy identity, not only the physical target.
      lKey := lMapped + '|' + lPolicy.fOwnership + '|' + lPolicy.fPath;
      lCandidates.AddOrSetValue(lKey, lMapped);
    end;
    if lCandidates.Count = 1 then
      for lMapped in lCandidates.Values do
        Result := lMapped;
  finally
    lCandidates.Free;
  end;
end;

function TAnalysisSourceResolver.Resolve(const aRawPath: string): string;
var
  lRaw: string;
begin
  lRaw := aRawPath.Trim;
  if not fResolved.TryGetValue(lRaw, Result) then
  begin
    Result := ResolveUncached(lRaw);
    fResolved.Add(lRaw, Result);
  end;
end;

procedure SetTextMember(aObject: TJSONObject; const aName, aText: string; aEmptyIsNull: Boolean);
var
  lPair: TJSONPair;
  lValue: TJSONValue;
begin
  if aEmptyIsNull and (aText = '') then
    lValue := TJSONNull.Create
  else
    lValue := TJSONString.Create(aText);
  try
    lPair := aObject.Get(aName);
    if lPair = nil then
      aObject.AddPair(aName, lValue)
    else
      // The RTL setter frees the old owned value and preserves the member's position.
      lPair.JsonValue := lValue;
  except
    lValue.Free;
    raise;
  end;
end;

function SourceText(aObject: TJSONObject; const aName: string): string;
var
  lValue: TJSONValue;
begin
  lValue := aObject.GetValue(aName);
  if (lValue = nil) or (lValue is TJSONNull) then
    Exit('');
  Result := lValue.Value;
end;

procedure TAnalysisSourceResolver.AnnotatePal(aRows: TJSONArray);
var
  lDisplay: string;
  lItem: TJSONObject;
  lOwnership: TAnalysisSourceOwnership;
  lRaw: string;
  lResolved: string;
  lRootPrefix: string;
  lValue: TJSONValue;
begin
  lRootPrefix := IncludeTrailingPathDelimiter(fContext.fWorkspaceRoot);
  for lValue in aRows do
  begin
    if not (lValue is TJSONObject) then
      raise EConvertError.Create('Analysis finding must be a JSON object.');
    lItem := TJSONObject(lValue);
    lRaw := SourceText(lItem, 'source_path');
    if lRaw = '' then
      lRaw := SourceText(lItem, 'path');
    lRaw := lRaw.Trim;
    lResolved := Resolve(lRaw);
    lOwnership := ClassifyAnalysisSource(lResolved, fContext);
    SetTextMember(lItem, 'source_path', lRaw, True);
    SetTextMember(lItem, 'ownership', lOwnership.fOwnership, False);
    SetTextMember(lItem, 'ownership_root', lOwnership.fRoot.Replace('\', '/'), True);
    if lResolved = '' then
      lDisplay := lRaw
    else if (fContext.fWorkspaceRoot <> '') and lResolved.StartsWith(lRootPrefix, True) then
      lDisplay := Copy(lResolved, Length(lRootPrefix) + 1, MaxInt).Replace('\', '/')
    else if SameText(lResolved, fContext.fWorkspaceRoot) then
      lDisplay := '.'
    else
      lDisplay := lResolved.Replace('\', '/');
    SetTextMember(lItem, 'path', lDisplay, True);
  end;
end;

function RelativeDisplay(const aPath, aRoot: string; out aDisplay: string): Boolean;
var
  lPrefix: string;
begin
  Result := False;
  if aRoot = '' then
    Exit;
  if SameText(aPath, aRoot) then
  begin
    aDisplay := '.';
    Exit(True);
  end;
  lPrefix := IncludeTrailingPathDelimiter(aRoot);
  if aPath.StartsWith(lPrefix, True) then
  begin
    aDisplay := Copy(aPath, Length(lPrefix) + 1, MaxInt).Replace('\', '/');
    Result := True;
  end;
end;

function NormalizeDisplaySegments(const aText: string): string;
var
  lPart: string;
  lParts: TList<string>;
  lPrefix: string;
begin
  lPrefix := '';
  if aText.StartsWith('/') then
    lPrefix := '/';
  if aText.StartsWith('//') and not aText.StartsWith('///') then
    lPrefix := '//';
  lParts := TList<string>.Create;
  try
    for lPart in aText.Split(['/']) do
    begin
      if (lPart = '') or (lPart = '.') then
        Continue;
      if (lPart = '..') and (lParts.Count > 0) and (lParts.Last <> '..') then
        lParts.Delete(lParts.Count - 1)
      else if (lPart <> '..') or (lPrefix = '') then
        lParts.Add(lPart);
    end;
    Result := lPrefix + string.Join('/', lParts.ToArray);
    if Result = '' then
      Result := '.';
  finally
    lParts.Free;
  end;
end;

function TAnalysisSourceResolver.FixInsightDisplay(const aRawPath, aResolved: string): string;
var
  lAbsolute: Boolean;
  lCandidate: string;
  lMapped: string;
  lRaw: string;
  lRoot: string;
begin
  Result := '';
  lRaw := aRawPath.Trim.Replace('/', '\');
  if lRaw = '' then
    Exit;
  if (aResolved <> '') and RelativeDisplay(aResolved, fContext.fWorkspaceRoot, Result) then
    Exit;
  lAbsolute := IsAbsoluteAnalysisPath(lRaw) or lRaw.StartsWith('\');
  if fContext.fWorkspaceRoot <> '' then
  begin
    if lAbsolute then
    begin
      lCandidate := ResolveFilesystemPath(lRaw);
      if RelativeDisplay(lCandidate, fContext.fWorkspaceRoot, Result) then
        Exit;
      if fBasenames.TryGetValue(TPath.GetFileName(lRaw), lMapped) and (lMapped <> '') then
      begin
        if not RelativeDisplay(lMapped, fContext.fWorkspaceRoot, Result) then
          Result := lMapped.Replace('\', '/');
        Exit;
      end;
    end else
    begin
      for lRoot in [fContext.fProjectDirectory, fContext.fWorkspaceRoot] do
        if lRoot <> '' then
        begin
          lCandidate := ResolveFilesystemPath(TPath.Combine(lRoot, lRaw));
          if RelativeDisplay(lCandidate, fContext.fWorkspaceRoot, Result) then
            Exit;
        end;
      for lRoot in fContext.fSearchRoots do
      begin
        lCandidate := ResolveFilesystemPath(TPath.Combine(lRoot, lRaw));
        if RelativeDisplay(lCandidate, fContext.fWorkspaceRoot, Result) then
          Exit;
      end;
    end;
  end;
  Result := NormalizeDisplaySegments(lRaw.Replace('\', '/'));
end;

procedure TAnalysisSourceResolver.AnnotateFixInsight(aRows: TJSONArray);
var
  lItem: TJSONObject;
  lOwnership: TAnalysisSourceOwnership;
  lRaw: string;
  lResolved: string;
  lValue: TJSONValue;
begin
  for lValue in aRows do
  begin
    if not (lValue is TJSONObject) then
      raise EConvertError.Create('Analysis finding must be a JSON object.');
    lItem := TJSONObject(lValue);
    lRaw := SourceText(lItem, 'file');
    if lRaw = '' then
      lRaw := SourceText(lItem, 'path');
    lRaw := lRaw.Trim;
    lResolved := Resolve(lRaw);
    lOwnership := ClassifyAnalysisSource(lResolved, fContext);
    SetTextMember(lItem, 'ownership', lOwnership.fOwnership, False);
    SetTextMember(lItem, 'ownership_root', lOwnership.fRoot.Replace('\', '/'), True);
    SetTextMember(lItem, 'path', FixInsightDisplay(lRaw, lResolved), False);
  end;
end;

end.
