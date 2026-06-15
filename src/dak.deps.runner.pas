unit Dak.Deps.Runner;

interface

uses
  Dak.Types;

function RunDepsCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  DelphiSemantics.Graph, DelphiSemantics.ProjectContext, DelphiSemantics.ProjectSession,
  Dak.ExitCodes,
  Dak.Project.Semantics,
  Dak.Semantics.Session;

type
  TDepsNodeResolution = (dnrResolved, dnrUnresolved, dnrParserProblem);
  TDepsEdgeKind = (dekProject, dekContains, dekInterface, dekImplementation);

  TDepsNodeInfo = class
  public
    fIsProjectUnit: Boolean;
    fName: string;
    fPath: string;
    fResolution: TDepsNodeResolution;
  end;

  TDepsEdgeInfo = record
    fEdgeKind: TDepsEdgeKind;
    fFromName: string;
    fToName: string;
  end;

  TDepsParserProblemInfo = record
    fDescription: string;
    fFileName: string;
    fUnitName: string;
  end;

  TDepsSccInfo = class
  public
    fInternalEdgeCount: Integer;
    fMembers: TStringList;
    fRepresentativeCycle: string;
    fSccId: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TDepsHotspotResult = class
  public
    fCycles: TStringList;
    fCycleEdgeKeys: THashSet<string>;
    fEdgeRanks: TDictionary<string, Integer>;
    fEdgeSccIds: TDictionary<string, Integer>;
    fNodeSccIds: TDictionary<string, Integer>;
    fSccs: TObjectList<TDepsSccInfo>;
    fUnitScores: TDictionary<string, Integer>;
    constructor Create;
    destructor Destroy; override;
  end;

  TDepsGraphBuilder = class
  private
    fContext: TProjectAnalysisContext;
    fOptions: TAppOptions;
    fEdges: TList<TDepsEdgeInfo>;
    fEdgeKeys: THashSet<string>;
    fNodes: TObjectDictionary<string, TDepsNodeInfo>;
    fParserProblems: TList<TDepsParserProblemInfo>;
    fSccData: TDepsHotspotResult;
    fUnresolvedUnits: THashSet<string>;
    class procedure AddScore(const aScores: TDictionary<string, Integer>; const aKey: string; const aDelta: Integer); static;
    class function BuildEdgeKey(const aEdge: TDepsEdgeInfo): string; static;
    class function CycleContainsUnit(const aCycleText, aUnitName: string): Boolean; static;
    class function EdgeHotspotSortRank(aEdgeKind: TDepsEdgeKind): Integer; static;
    class function EdgeRefactorabilityHint(aEdgeKind: TDepsEdgeKind): string; static;
    class function EdgeKindToText(aEdgeKind: TDepsEdgeKind): string; static;
    function GetSortedCycleComponents: TList<TDepsSccInfo>;
    class function IsFrameworkUnitName(const aUnitName: string): Boolean; static;
    class function SemanticEdgeKind(const aSectionKind: string): TDepsEdgeKind; static;
    class function SemanticNodeResolution(const aStatus: string): TDepsNodeResolution; static;
    function GetSortedHotspotEdges: TList<TDepsEdgeInfo>;
    function GetSortedHotspotUnitNames: TList<string>;
    function BuildSccData: TDepsHotspotResult;
    function GetSortedEdgeList: TList<TDepsEdgeInfo>;
    function GetSortedNodeNames: TStringList;
    function GetSortedParserProblems: TList<TDepsParserProblemInfo>;
    function GetSortedUnresolvedUnits: TStringList;
    function IsProjectUnitPath(const aFileName: string): Boolean;
    procedure MergeEdge(const aFromName, aToName: string; aEdgeKind: TDepsEdgeKind);
    procedure MergeSemanticGraph(const aGraph: TDelphiSemanticDependencyGraph);
    procedure MergeNode(const aNodeName, aPath: string; aResolution: TDepsNodeResolution);
    class function ResolutionToText(aResolution: TDepsNodeResolution): string; static;
  public
    constructor Create(const aContext: TProjectAnalysisContext; const aOptions: TAppOptions);
    destructor Destroy; override;
    procedure Build;
    function DefaultOutputPath(aFormat: TDepsFormat): string;
    function RenderJson: string;
    function RenderText(const aFocusUnitName: string; aTopLimit: Integer): string;
  end;

  TDepsCommandRunner = class
  private
    fContext: TProjectAnalysisContext;
    fOptions: TAppOptions;
    function ResolveOutputPath: string;
    function TryBuildContext(out aError: string): Boolean;
    procedure WriteOutput(const aOutputText, aOutputPath: string);
  public
    constructor Create(const aOptions: TAppOptions);
    function Execute: Integer;
  end;

class procedure TDepsGraphBuilder.AddScore(const aScores: TDictionary<string, Integer>; const aKey: string;
  const aDelta: Integer);
var
  lScore: Integer;
begin
  if not aScores.TryGetValue(aKey, lScore) then
  begin
    lScore := 0;
  end;
  aScores.AddOrSetValue(aKey, lScore + aDelta);
end;

constructor TDepsHotspotResult.Create;
begin
  inherited Create;
  fCycles := TStringList.Create;
  fCycleEdgeKeys := THashSet<string>.Create;
  fEdgeRanks := TDictionary<string, Integer>.Create;
  fEdgeSccIds := TDictionary<string, Integer>.Create;
  fNodeSccIds := TDictionary<string, Integer>.Create;
  fSccs := TObjectList<TDepsSccInfo>.Create(True);
  fUnitScores := TDictionary<string, Integer>.Create;
end;

destructor TDepsHotspotResult.Destroy;
begin
  fUnitScores.Free;
  fSccs.Free;
  fNodeSccIds.Free;
  fEdgeSccIds.Free;
  fEdgeRanks.Free;
  fCycleEdgeKeys.Free;
  fCycles.Free;
  inherited Destroy;
end;

constructor TDepsSccInfo.Create;
begin
  inherited Create;
  fMembers := TStringList.Create;
  fMembers.Sorted := True;
  fMembers.Duplicates := dupIgnore;
end;

destructor TDepsSccInfo.Destroy;
begin
  fMembers.Free;
  inherited Destroy;
end;

function TDepsGraphBuilder.BuildSccData: TDepsHotspotResult;
var
  lComponentInfo: TDepsSccInfo;
  lComponentInfoRef: TDepsSccInfo;
  lComponent: TDelphiSemanticTypedSccComponent;
  lEdge: TDepsEdgeInfo;
  lEdgeId: Integer;
  lEdgeKey: string;
  lEdgeRank: Integer;
  lEdgeScore: Integer;
  lNode: TDepsNodeInfo;
  lNodeId: Integer;
  lNodeIdByName: TDictionary<string, Integer>;
  lNodeList: TStringList;
  lResult: TDepsHotspotResult;
  lSccResult: TDelphiSemanticTypedSccResult;
  lTypedEdge: TDelphiSemanticTypedSccEdge;
  lTypedEdges: TList<TDelphiSemanticTypedSccEdge>;
  lUnitScore: Integer;

  function RepresentativeCycleText(const aComponent: TDelphiSemanticTypedSccComponent):
    string;
  var
    lPathNames: TArray<string>;
    i: Integer;
  begin
    SetLength(lPathNames, Length(aComponent.RepresentativePath));
    for i := 0 to High(aComponent.RepresentativePath) do
      lPathNames[i] := lNodeList[aComponent.RepresentativePath[i]];
    Result := String.Join(' -> ', lPathNames);
  end;
begin
  lResult := TDepsHotspotResult.Create;
  lNodeIdByName := TDictionary<string, Integer>.Create;
  lNodeList := TStringList.Create;
  lTypedEdges := TList<TDelphiSemanticTypedSccEdge>.Create;
  try
    try
      lNodeList.Sorted := True;
      lNodeList.Duplicates := dupIgnore;
      for lNode in fNodes.Values do
        if lNode.fIsProjectUnit and (lNode.fResolution = TDepsNodeResolution.dnrResolved) then
          lNodeList.Add(lNode.fName);

      for lNodeId := 0 to Pred(lNodeList.Count) do
        lNodeIdByName.Add(lNodeList[lNodeId], lNodeId);

      for lEdgeId := 0 to Pred(fEdges.Count) do
      begin
        lEdge := fEdges[lEdgeId];
        if not lNodeIdByName.TryGetValue(lEdge.fFromName, lTypedEdge.SourceNodeId) or
          not lNodeIdByName.TryGetValue(lEdge.fToName, lTypedEdge.TargetNodeId) then
          Continue;
        lTypedEdge.EdgeId := lEdgeId;
        lTypedEdges.Add(lTypedEdge);
      end;

      lSccResult := TDelphiSemanticTypedSccAnalyzer.Analyze(lNodeList.Count,
        lTypedEdges.ToArray);

      for lComponent in lSccResult.Components do
      begin
        lComponentInfo := TDepsSccInfo.Create;
        try
          lComponentInfo.fSccId := lComponent.SccId;
          for lNodeId in lComponent.NodeIds do
          begin
            lComponentInfo.fMembers.Add(lNodeList[lNodeId]);
            lResult.fNodeSccIds.Add(lNodeList[lNodeId], lComponent.SccId);
          end;
          lComponentInfo.fInternalEdgeCount := Length(lComponent.EdgeIds);
          lComponentInfo.fRepresentativeCycle := RepresentativeCycleText(lComponent);
          lResult.fCycles.Add(lComponentInfo.fRepresentativeCycle);
          lResult.fSccs.Add(lComponentInfo);
          lComponentInfoRef := lComponentInfo;
          lComponentInfo := nil;

          for lEdgeId in lComponent.EdgeIds do
          begin
            lEdge := fEdges[lEdgeId];
            AddScore(lResult.fUnitScores, lEdge.fFromName, 1);
            AddScore(lResult.fUnitScores, lEdge.fToName, 1);
            lEdgeKey := BuildEdgeKey(lEdge);
            lResult.fCycleEdgeKeys.Add(lEdgeKey);
            lResult.fEdgeSccIds.Add(lEdgeKey, lComponentInfoRef.fSccId);
          end;
        finally
          lComponentInfo.Free;
        end;
      end;

      for lEdge in fEdges do
      begin
        lEdgeKey := BuildEdgeKey(lEdge);
        if not lResult.fCycleEdgeKeys.Contains(lEdgeKey) then
        begin
          Continue;
        end;
        lEdgeRank := 0;
        if lResult.fUnitScores.TryGetValue(lEdge.fFromName, lUnitScore) then
        begin
          Inc(lEdgeRank, lUnitScore);
        end;
        if lResult.fUnitScores.TryGetValue(lEdge.fToName, lEdgeScore) then
        begin
          Inc(lEdgeRank, lEdgeScore);
        end;
        lResult.fEdgeRanks.Add(lEdgeKey, lEdgeRank);
      end;
    except
      lResult.Free;
      raise;
    end;
    Result := lResult;
  finally
    lTypedEdges.Free;
    lNodeList.Free;
    lNodeIdByName.Free;
  end;
end;

class function TDepsGraphBuilder.BuildEdgeKey(const aEdge: TDepsEdgeInfo): string;
begin
  Result := LowerCase(aEdge.fFromName) + '|' + LowerCase(aEdge.fToName) + '|' + IntToStr(Ord(aEdge.fEdgeKind));
end;

class function TDepsGraphBuilder.CycleContainsUnit(const aCycleText, aUnitName: string): Boolean;
var
  lCycleUnit: string;
begin
  if (Trim(aCycleText) = '') or (Trim(aUnitName) = '') then
  begin
    Exit(False);
  end;
  for lCycleUnit in SplitString(aCycleText, ' -> ') do
  begin
    if SameText(lCycleUnit, aUnitName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDepsGraphBuilder.EdgeHotspotSortRank(aEdgeKind: TDepsEdgeKind): Integer;
begin
  case aEdgeKind of
    TDepsEdgeKind.dekImplementation:
      Result := 0;
    TDepsEdgeKind.dekInterface:
      Result := 1;
  else
    Result := 10 + Ord(aEdgeKind);
  end;
end;

class function TDepsGraphBuilder.EdgeRefactorabilityHint(aEdgeKind: TDepsEdgeKind): string;
begin
  case aEdgeKind of
    TDepsEdgeKind.dekImplementation:
      Result := 'easier';
    TDepsEdgeKind.dekInterface:
      Result := 'harder';
  else
    Result := 'neutral';
  end;
end;

constructor TDepsGraphBuilder.Create(const aContext: TProjectAnalysisContext;
  const aOptions: TAppOptions);
begin
  inherited Create;
  fContext := aContext;
  fOptions := aOptions;
  fEdges := TList<TDepsEdgeInfo>.Create;
  fEdgeKeys := THashSet<string>.Create;
  fNodes := TObjectDictionary<string, TDepsNodeInfo>.Create([doOwnsValues]);
  fParserProblems := TList<TDepsParserProblemInfo>.Create;
  fUnresolvedUnits := THashSet<string>.Create;
end;

function TDepsGraphBuilder.DefaultOutputPath(aFormat: TDepsFormat): string;
begin
  if aFormat = TDepsFormat.dfText then
    Result := TPath.Combine(TPath.Combine(fContext.DakProjectRoot, 'deps'), 'deps.txt')
  else
    Result := TPath.Combine(TPath.Combine(fContext.DakProjectRoot, 'deps'), 'deps.json');
end;

destructor TDepsGraphBuilder.Destroy;
begin
  fSccData.Free;
  fUnresolvedUnits.Free;
  fParserProblems.Free;
  fNodes.Free;
  fEdgeKeys.Free;
  fEdges.Free;
  inherited Destroy;
end;

class function TDepsGraphBuilder.EdgeKindToText(aEdgeKind: TDepsEdgeKind): string;
begin
  case aEdgeKind of
    TDepsEdgeKind.dekProject:
      Result := 'project';
    TDepsEdgeKind.dekContains:
      Result := 'contains';
    TDepsEdgeKind.dekInterface:
      Result := 'interface';
  else
    Result := 'implementation';
  end;
end;

function TDepsGraphBuilder.GetSortedCycleComponents: TList<TDepsSccInfo>;
var
  lSccInfo: TDepsSccInfo;
begin
  Result := TList<TDepsSccInfo>.Create;
  if not Assigned(fSccData) then
  begin
    Exit;
  end;
  for lSccInfo in fSccData.fSccs do
  begin
    Result.Add(lSccInfo);
  end;
  Result.Sort(TComparer<TDepsSccInfo>.Construct(
    function(const aLeft, aRight: TDepsSccInfo): Integer
    begin
      Result := aRight.fMembers.Count - aLeft.fMembers.Count;
      if Result <> 0 then
      begin
        Exit;
      end;
      Result := aLeft.fSccId - aRight.fSccId;
    end));
end;

class function TDepsGraphBuilder.IsFrameworkUnitName(const aUnitName: string): Boolean;
begin
  Result :=
    StartsText('System.', aUnitName) or
    StartsText('Winapi.', aUnitName) or
    StartsText('Vcl.', aUnitName) or
    StartsText('FMX.', aUnitName) or
    StartsText('Xml.', aUnitName) or
    StartsText('Data.', aUnitName) or
    StartsText('Soap.', aUnitName) or
    StartsText('Web.', aUnitName) or
    StartsText('Datasnap.', aUnitName) or
    StartsText('Macapi.', aUnitName) or
    StartsText('Posix.', aUnitName);
end;

class function TDepsGraphBuilder.SemanticEdgeKind(const aSectionKind: string): TDepsEdgeKind;
begin
  if SameText(aSectionKind, 'project') then
  begin
    Result := TDepsEdgeKind.dekProject;
  end else if SameText(aSectionKind, 'contains') then
  begin
    Result := TDepsEdgeKind.dekContains;
  end else if SameText(aSectionKind, 'implementation') then
  begin
    Result := TDepsEdgeKind.dekImplementation;
  end else
  begin
    Result := TDepsEdgeKind.dekInterface;
  end;
end;

class function TDepsGraphBuilder.SemanticNodeResolution(const aStatus: string): TDepsNodeResolution;
begin
  if SameText(aStatus, 'unresolved') then
  begin
    Result := TDepsNodeResolution.dnrUnresolved;
  end else
  begin
    Result := TDepsNodeResolution.dnrResolved;
  end;
end;

function TDepsGraphBuilder.GetSortedEdgeList: TList<TDepsEdgeInfo>;
var
  lEdge: TDepsEdgeInfo;
begin
  Result := TList<TDepsEdgeInfo>.Create;
  for lEdge in fEdges do
  begin
    Result.Add(lEdge);
  end;
  Result.Sort(TComparer<TDepsEdgeInfo>.Construct(
    function(const aLeft, aRight: TDepsEdgeInfo): Integer
    begin
      Result := CompareText(aLeft.fFromName, aRight.fFromName);
      if Result <> 0 then
      begin
        Exit;
      end;
      Result := CompareText(aLeft.fToName, aRight.fToName);
      if Result <> 0 then
      begin
        Exit;
      end;
      Result := Ord(aLeft.fEdgeKind) - Ord(aRight.fEdgeKind);
    end));
end;

function TDepsGraphBuilder.GetSortedNodeNames: TStringList;
var
  lNodeName: string;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  for lNodeName in fNodes.Keys do
  begin
    Result.Add(lNodeName);
  end;
end;

function TDepsGraphBuilder.GetSortedHotspotEdges: TList<TDepsEdgeInfo>;
var
  lEdge: TDepsEdgeInfo;
  lEdgeKey: string;
begin
  Result := TList<TDepsEdgeInfo>.Create;
  if not Assigned(fSccData) then
  begin
    Exit;
  end;
  for lEdge in fEdges do
  begin
    lEdgeKey := BuildEdgeKey(lEdge);
    if fSccData.fEdgeRanks.ContainsKey(lEdgeKey) then
    begin
      Result.Add(lEdge);
    end;
  end;
  Result.Sort(TComparer<TDepsEdgeInfo>.Construct(
    function(const aLeft, aRight: TDepsEdgeInfo): Integer
    var
      lLeftKey: string;
      lRightKey: string;
    begin
      lLeftKey := BuildEdgeKey(aLeft);
      lRightKey := BuildEdgeKey(aRight);
      Result := fSccData.fEdgeRanks.Items[lRightKey] - fSccData.fEdgeRanks.Items[lLeftKey];
      if Result <> 0 then
      begin
        Exit;
      end;
      Result := EdgeHotspotSortRank(aLeft.fEdgeKind) - EdgeHotspotSortRank(aRight.fEdgeKind);
      if Result <> 0 then
      begin
        Exit;
      end;
      Result := CompareText(aLeft.fFromName, aRight.fFromName);
      if Result <> 0 then
      begin
        Exit;
      end;
      Result := CompareText(aLeft.fToName, aRight.fToName);
    end));
end;

function TDepsGraphBuilder.GetSortedHotspotUnitNames: TList<string>;
var
  lUnitName: string;
begin
  Result := TList<string>.Create;
  if not Assigned(fSccData) then
  begin
    Exit;
  end;
  for lUnitName in fSccData.fUnitScores.Keys do
  begin
    Result.Add(lUnitName);
  end;
  Result.Sort(TComparer<string>.Construct(
    function(const aLeft, aRight: string): Integer
    var
      lLeftScore: Integer;
      lRightScore: Integer;
    begin
      lLeftScore := fSccData.fUnitScores.Items[aLeft];
      lRightScore := fSccData.fUnitScores.Items[aRight];
      Result := lRightScore - lLeftScore;
      if Result <> 0 then
      begin
        Exit;
      end;
      Result := CompareText(aLeft, aRight);
    end));
end;

function TDepsGraphBuilder.GetSortedParserProblems: TList<TDepsParserProblemInfo>;
var
  lProblem: TDepsParserProblemInfo;
begin
  Result := TList<TDepsParserProblemInfo>.Create;
  for lProblem in fParserProblems do
  begin
    Result.Add(lProblem);
  end;
  Result.Sort(TComparer<TDepsParserProblemInfo>.Construct(
    function(const aLeft, aRight: TDepsParserProblemInfo): Integer
    begin
      Result := CompareText(aLeft.fUnitName, aRight.fUnitName);
      if Result <> 0 then
      begin
        Exit;
      end;
      Result := CompareText(aLeft.fFileName, aRight.fFileName);
    end));
end;

function TDepsGraphBuilder.GetSortedUnresolvedUnits: TStringList;
var
  lUnitName: string;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  for lUnitName in fUnresolvedUnits do
  begin
    Result.Add(lUnitName);
  end;
end;

function TDepsGraphBuilder.IsProjectUnitPath(const aFileName: string): Boolean;
var
  lFileDir: string;
  lFullName: string;
  lProjectDir: string;
begin
  if aFileName = '' then
  begin
    Exit(False);
  end;
  lFullName := TPath.GetFullPath(aFileName);
  lFileDir := IncludeTrailingPathDelimiter(TPath.GetDirectoryName(lFullName));
  lProjectDir := IncludeTrailingPathDelimiter(TPath.GetFullPath(fContext.ProjectDir));
  Result := SameText(Copy(lFileDir, 1, Length(lProjectDir)), lProjectDir);
end;

procedure TDepsGraphBuilder.MergeEdge(const aFromName, aToName: string; aEdgeKind: TDepsEdgeKind);
var
  lEdge: TDepsEdgeInfo;
  lEdgeKey: string;
begin
  if (Trim(aFromName) = '') or (Trim(aToName) = '') then
  begin
    Exit;
  end;
  lEdge.fFromName := aFromName;
  lEdge.fToName := aToName;
  lEdge.fEdgeKind := aEdgeKind;
  lEdgeKey := BuildEdgeKey(lEdge);
  if fEdgeKeys.Add(lEdgeKey) then
  begin
    fEdges.Add(lEdge);
  end;
end;

procedure TDepsGraphBuilder.MergeSemanticGraph(const aGraph: TDelphiSemanticDependencyGraph);
var
  lEdge: TDelphiSemanticDependencyEdge;
  lNode: TDelphiSemanticDependencyNode;
  lParserProblem: TDelphiSemanticDependencyParserProblem;
  lParserProblemInfo: TDepsParserProblemInfo;
  lUnitName: string;
begin
  for lNode in aGraph.Nodes do
  begin
    MergeNode(lNode.UnitName, lNode.FileName, SemanticNodeResolution(lNode.Status));
  end;
  for lEdge in aGraph.Edges do
  begin
    MergeEdge(lEdge.SourceUnit, lEdge.TargetUnit, SemanticEdgeKind(lEdge.SectionKind));
  end;
  for lUnitName in aGraph.UnresolvedUnits do
  begin
    fUnresolvedUnits.Add(lUnitName);
    MergeNode(lUnitName, '', TDepsNodeResolution.dnrUnresolved);
  end;
  for lParserProblem in aGraph.ParserProblems do
  begin
    lParserProblemInfo := Default(TDepsParserProblemInfo);
    lParserProblemInfo.fUnitName := lParserProblem.UnitName;
    lParserProblemInfo.fFileName := lParserProblem.FileName;
    lParserProblemInfo.fDescription := lParserProblem.Description;
    fParserProblems.Add(lParserProblemInfo);
    MergeNode(lParserProblemInfo.fUnitName, lParserProblemInfo.fFileName,
      TDepsNodeResolution.dnrParserProblem);
  end;
end;

procedure TDepsGraphBuilder.MergeNode(const aNodeName, aPath: string; aResolution: TDepsNodeResolution);
var
  lNode: TDepsNodeInfo;
  lPath: string;
begin
  if Trim(aNodeName) = '' then
  begin
    Exit;
  end;
  if not fNodes.TryGetValue(aNodeName, lNode) then
  begin
    lNode := TDepsNodeInfo.Create;
    lNode.fName := aNodeName;
    lNode.fResolution := aResolution;
    if aPath <> '' then
    begin
      lPath := TPath.GetFullPath(aPath);
      lNode.fPath := lPath;
      lNode.fIsProjectUnit := IsProjectUnitPath(lPath);
    end;
    fNodes.Add(aNodeName, lNode);
    Exit;
  end;

  if (lNode.fPath = '') and (aPath <> '') then
  begin
    lPath := TPath.GetFullPath(aPath);
    lNode.fPath := lPath;
    lNode.fIsProjectUnit := IsProjectUnitPath(lPath);
  end;
  if Ord(aResolution) > Ord(lNode.fResolution) then
  begin
    lNode.fResolution := aResolution;
  end;
end;

procedure TDepsGraphBuilder.Build;
var
  lError: string;
  lSemanticGraph: TDelphiSemanticDependencyGraph;
  lSessionOptions: TDelphiSemanticOptions;
  lSessionResult: TDelphiSemanticProjectSessionResult;
begin
  FreeAndNil(fSccData);
  lSessionOptions := BuildSemanticSessionOptions(fContext.ProjectPath, fOptions.fConfig,
    fOptions.fPlatform, fOptions.fDelphiVersion, fOptions.fRsVarsPath,
    fOptions.fEnvOptionsPath, '');
  if not OpenSemanticProjectSession(lSessionOptions, lSessionResult, lError) then
    Exit;
  try
    lSemanticGraph := lSessionResult.Session.BuildDependencyGraph;
    MergeSemanticGraph(lSemanticGraph);
  finally
    lSessionResult.Session.Free;
  end;
  fSccData := BuildSccData;
end;

function TDepsGraphBuilder.RenderJson: string;
var
  lCycleComponentJson: TJSONObject;
  lCycleComponents: TJSONArray;
  lCycleComponentValue: TDepsSccInfo;
  lCycleText: string;
  lCyclesJson: TJSONArray;
  lMembersJson: TJSONArray;
  lEdge: TDepsEdgeInfo;
  lEdgeIsCycleEdge: Boolean;
  lEdgeHotspotEdge: TDepsEdgeInfo;
  lEdgeHotspotJson: TJSONArray;
  lEdgeHotspotList: TList<TDepsEdgeInfo>;
  lEdgeKey: string;
  lEdgeRank: Integer;
  lEdgeSccId: Integer;
  lEdgeList: TList<TDepsEdgeInfo>;
  lEdges: TJSONArray;
  lNode: TDepsNodeInfo;
  lNodeJson: TJSONObject;
  lNodeNames: TStringList;
  lNodes: TJSONArray;
  lParserProblem: TDepsParserProblemInfo;
  lParserProblemList: TList<TDepsParserProblemInfo>;
  lParserProblems: TJSONArray;
  lProjectJson: TJSONObject;
  lResolvedCount: Integer;
  lRefactorabilityHint: string;
  lRoot: TJSONObject;
  lSccId: Integer;
  lSccList: TList<TDepsSccInfo>;
  lSummary: TJSONObject;
  lUnitInCycle: Boolean;
  lUnitHotspotJson: TJSONArray;
  lUnitHotspotNames: TList<string>;
  lUnitName: string;
  lUnitScore: Integer;
  lUnresolvedJson: TJSONArray;
  lUnresolvedUnits: TStringList;
begin
  lRoot := TJSONObject.Create;
  try
    lProjectJson := TJSONObject.Create;
    lProjectJson.AddPair('name', fContext.ProjectName);
    lProjectJson.AddPair('path', fContext.ProjectPath);
    lProjectJson.AddPair('mainSource', fContext.MainSourcePath);
    lProjectJson.AddPair('contextMode', ProjectAnalysisContextQualityToText(fContext.Quality));
    if fContext.ContextNote <> '' then
      lProjectJson.AddPair('contextNote', fContext.ContextNote);
    lRoot.AddPair('project', lProjectJson);

    lResolvedCount := 0;
    for lNode in fNodes.Values do
    begin
      if lNode.fResolution = TDepsNodeResolution.dnrResolved then
      begin
        Inc(lResolvedCount);
      end;
    end;
    lSummary := TJSONObject.Create;
    lSummary.AddPair('nodeCount', TJSONNumber.Create(fNodes.Count));
    lSummary.AddPair('resolvedNodeCount', TJSONNumber.Create(lResolvedCount));
    lSummary.AddPair('edgeCount', TJSONNumber.Create(fEdges.Count));
    lSummary.AddPair('unresolvedUnitCount', TJSONNumber.Create(fUnresolvedUnits.Count));
    lSummary.AddPair('parserProblemCount', TJSONNumber.Create(fParserProblems.Count));
    lRoot.AddPair('summary', lSummary);

    lNodes := TJSONArray.Create;
    lRoot.AddPair('nodes', lNodes);
    lNodeNames := GetSortedNodeNames;
    try
      for lUnitName in lNodeNames do
      begin
        lNode := fNodes.Items[lUnitName];
        lNodeJson := TJSONObject.Create;
        lNodeJson.AddPair('name', lNode.fName);
        if lNode.fPath <> '' then
        begin
          lNodeJson.AddPair('path', lNode.fPath);
        end;
        lNodeJson.AddPair('isProjectUnit', TJSONBool.Create(lNode.fIsProjectUnit));
        lNodeJson.AddPair('resolution', ResolutionToText(lNode.fResolution));
        lUnitInCycle := False;
        if Assigned(fSccData) then
        begin
          lUnitInCycle := fSccData.fUnitScores.TryGetValue(lNode.fName, lUnitScore);
        end;
        if lUnitInCycle then
        begin
          lNodeJson.AddPair('unitCycleScore', TJSONNumber.Create(lUnitScore));
        end else
        begin
          lNodeJson.AddPair('unitCycleScore', TJSONNumber.Create(0));
        end;
        lSccId := 0;
        if Assigned(fSccData) then
        begin
          lUnitInCycle := fSccData.fNodeSccIds.TryGetValue(lNode.fName, lSccId);
        end else
        begin
          lUnitInCycle := False;
        end;
        if lUnitInCycle then
        begin
          lNodeJson.AddPair('sccId', TJSONNumber.Create(lSccId));
        end else
        begin
          lNodeJson.AddPair('sccId', TJSONNull.Create);
        end;
        lNodes.AddElement(lNodeJson);
      end;
    finally
      lNodeNames.Free;
    end;

    lEdges := TJSONArray.Create;
    lRoot.AddPair('edges', lEdges);
    lEdgeList := GetSortedEdgeList;
    try
      for lEdge in lEdgeList do
      begin
        lEdgeKey := BuildEdgeKey(lEdge);
        lEdgeIsCycleEdge := False;
        if Assigned(fSccData) then
        begin
          lEdgeIsCycleEdge := fSccData.fCycleEdgeKeys.Contains(lEdgeKey);
        end;
        lEdges.AddElement(TJSONObject.Create
          .AddPair('from', lEdge.fFromName)
          .AddPair('to', lEdge.fToName)
          .AddPair('edgeKind', EdgeKindToText(lEdge.fEdgeKind))
          .AddPair('isCycleEdge', TJSONBool.Create(lEdgeIsCycleEdge)));
      end;
    finally
      lEdgeList.Free;
    end;

    lUnresolvedJson := TJSONArray.Create;
    lRoot.AddPair('unresolvedUnits', lUnresolvedJson);
    lUnresolvedUnits := GetSortedUnresolvedUnits;
    try
      for lUnitName in lUnresolvedUnits do
      begin
        lUnresolvedJson.AddElement(TJSONString.Create(lUnitName));
      end;
    finally
      lUnresolvedUnits.Free;
    end;

    lParserProblems := TJSONArray.Create;
    lRoot.AddPair('parserProblems', lParserProblems);
    lParserProblemList := GetSortedParserProblems;
    try
      for lParserProblem in lParserProblemList do
      begin
        lParserProblems.AddElement(TJSONObject.Create
          .AddPair('unitName', lParserProblem.fUnitName)
          .AddPair('fileName', lParserProblem.fFileName)
          .AddPair('description', lParserProblem.fDescription));
      end;
    finally
      lParserProblemList.Free;
    end;

    lSccList := GetSortedCycleComponents;
    try
      lCyclesJson := TJSONArray.Create;
      lRoot.AddPair('cycles', lCyclesJson);
      for lCycleComponentValue in lSccList do
      begin
        lCyclesJson.AddElement(TJSONString.Create(lCycleComponentValue.fRepresentativeCycle));
      end;

      lCycleComponents := TJSONArray.Create;
      lRoot.AddPair('cycleComponents', lCycleComponents);
      for lCycleComponentValue in lSccList do
      begin
        lCycleComponentJson := TJSONObject.Create;
        lCycleComponentJson.AddPair('sccId', TJSONNumber.Create(lCycleComponentValue.fSccId));
        lCycleComponentJson.AddPair('sccSize', TJSONNumber.Create(lCycleComponentValue.fMembers.Count));
        lCycleComponentJson.AddPair('sccInternalEdgeCount', TJSONNumber.Create(lCycleComponentValue.fInternalEdgeCount));
        lMembersJson := TJSONArray.Create;
        lCycleComponentJson.AddPair('members', lMembersJson);
        for lUnitName in lCycleComponentValue.fMembers do
        begin
          lMembersJson.AddElement(TJSONString.Create(lUnitName));
        end;
        lCycleComponentJson.AddPair('representativeCycle', lCycleComponentValue.fRepresentativeCycle);
        lCycleComponents.AddElement(lCycleComponentJson);
      end;
    finally
      lSccList.Free;
    end;

    lUnitHotspotJson := TJSONArray.Create;
    lRoot.AddPair('unitHotspots', lUnitHotspotJson);
    lUnitHotspotNames := GetSortedHotspotUnitNames;
    try
      for lUnitName in lUnitHotspotNames do
      begin
        lUnitScore := fSccData.fUnitScores.Items[lUnitName];
        lSccId := fSccData.fNodeSccIds.Items[lUnitName];
        lUnitHotspotJson.AddElement(TJSONObject.Create
          .AddPair('name', lUnitName)
          .AddPair('unitCycleScore', TJSONNumber.Create(lUnitScore))
          .AddPair('sccId', TJSONNumber.Create(lSccId)));
      end;
    finally
      lUnitHotspotNames.Free;
    end;

    lEdgeHotspotJson := TJSONArray.Create;
    lRoot.AddPair('edgeHotspots', lEdgeHotspotJson);
    lEdgeHotspotList := GetSortedHotspotEdges;
    try
      for lEdgeHotspotEdge in lEdgeHotspotList do
      begin
        lEdgeKey := BuildEdgeKey(lEdgeHotspotEdge);
        lEdgeRank := fSccData.fEdgeRanks.Items[lEdgeKey];
        lEdgeSccId := fSccData.fEdgeSccIds.Items[lEdgeKey];
        lRefactorabilityHint := EdgeRefactorabilityHint(lEdgeHotspotEdge.fEdgeKind);
        lEdgeHotspotJson.AddElement(TJSONObject.Create
          .AddPair('from', lEdgeHotspotEdge.fFromName)
          .AddPair('to', lEdgeHotspotEdge.fToName)
          .AddPair('edgeKind', EdgeKindToText(lEdgeHotspotEdge.fEdgeKind))
          .AddPair('edgeHotspotRank', TJSONNumber.Create(lEdgeRank))
          .AddPair('refactorabilityHint', lRefactorabilityHint)
          .AddPair('sccId', TJSONNumber.Create(lEdgeSccId)));
      end;
    finally
      lEdgeHotspotList.Free;
    end;

    Result := lRoot.Format(2);
  finally
    lRoot.Free;
  end;
end;

function TDepsGraphBuilder.RenderText(const aFocusUnitName: string; aTopLimit: Integer): string;
var
  lBuilder: TStringBuilder;
  lCycleComponents: TList<TDepsSccInfo>;
  lCycleText: string;
  lEdge: TDepsEdgeInfo;
  lEdgeList: TList<TDepsEdgeInfo>;
  lHotspotEdges: TList<TDepsEdgeInfo>;
  lHotspotUnits: TList<string>;
  lHintLabel: string;
  lLimitCount: Integer;
  lNode: TDepsNodeInfo;
  lNodeName: string;
  lNodeNames: TStringList;
  lParserProblem: TDepsParserProblemInfo;
  lParserProblemList: TList<TDepsParserProblemInfo>;
  lRank: Integer;
  lUnitName: string;
  lUnitScore: Integer;
  lUnresolvedUnits: TStringList;
begin
  if aTopLimit < 0 then
  begin
    aTopLimit := 0;
  end;

  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('Project: ' + fContext.ProjectName);
    lBuilder.AppendLine('Context mode: ' + ProjectAnalysisContextQualityToText(fContext.Quality));
    lBuilder.AppendLine(Format('Summary: nodes=%d edges=%d unresolved=%d parserProblems=%d',
      [fNodes.Count, fEdges.Count, fUnresolvedUnits.Count, fParserProblems.Count]));
    if fContext.ContextNote <> '' then
    begin
      lBuilder.AppendLine('Context: ' + fContext.ContextNote);
    end;

    lCycleComponents := GetSortedCycleComponents;
    try
      if lCycleComponents.Count > 0 then
      begin
        lBuilder.AppendLine(Format('Cycle components (%d):', [lCycleComponents.Count]));
        for var lSccInfo in lCycleComponents do
        begin
          lBuilder.AppendLine(Format('  SCC #%d  members=%d  internalEdges=%d',
            [lSccInfo.fSccId, lSccInfo.fMembers.Count, lSccInfo.fInternalEdgeCount]));
          lBuilder.AppendLine('    Representative cycle: ' + lSccInfo.fRepresentativeCycle);
          lBuilder.AppendLine('    Members: ' + String.Join(', ', lSccInfo.fMembers.ToStringArray));
        end;
      end;
    finally
      lCycleComponents.Free;
    end;

    lHotspotUnits := GetSortedHotspotUnitNames;
    try
      if lHotspotUnits.Count > 0 then
      begin
        if aTopLimit = 0 then
        begin
          lBuilder.AppendLine('Top cycle units (all):');
        end else
        begin
          lBuilder.AppendLine(Format('Top cycle units (up to %d):', [aTopLimit]));
        end;
        lLimitCount := lHotspotUnits.Count;
        if (aTopLimit > 0) and (lLimitCount > aTopLimit) then
        begin
          lLimitCount := aTopLimit;
        end;
        for lRank := 0 to lLimitCount - 1 do
        begin
          lUnitName := lHotspotUnits[lRank];
          lUnitScore := fSccData.fUnitScores.Items[lUnitName];
          lBuilder.AppendLine(Format('  %d. %s  score=%d  scc=#%d',
            [lRank + 1, lUnitName, lUnitScore, fSccData.fNodeSccIds.Items[lUnitName]]));
        end;
      end;
    finally
      lHotspotUnits.Free;
    end;

    lHotspotEdges := GetSortedHotspotEdges;
    try
      if lHotspotEdges.Count > 0 then
      begin
        if aTopLimit = 0 then
        begin
          lBuilder.AppendLine('Top cycle edges (all):');
        end else
        begin
          lBuilder.AppendLine(Format('Top cycle edges (up to %d):', [aTopLimit]));
        end;
        lLimitCount := lHotspotEdges.Count;
        if (aTopLimit > 0) and (lLimitCount > aTopLimit) then
        begin
          lLimitCount := aTopLimit;
        end;
        for lRank := 0 to lLimitCount - 1 do
        begin
          lEdge := lHotspotEdges[lRank];
          lHintLabel := EdgeRefactorabilityHint(lEdge.fEdgeKind);
          if lHintLabel = 'easier' then
          begin
            lHintLabel := 'preferred-cut';
          end else if lHintLabel = 'harder' then
          begin
            lHintLabel := 'harder-cut';
          end else
          begin
            lHintLabel := 'neutral-cut';
          end;
          lBuilder.AppendLine(Format('  %d. %s -> %s [%s] rank=%d scc=#%d %s',
            [lRank + 1, lEdge.fFromName, lEdge.fToName, EdgeKindToText(lEdge.fEdgeKind),
              fSccData.fEdgeRanks.Items[BuildEdgeKey(lEdge)], fSccData.fEdgeSccIds.Items[BuildEdgeKey(lEdge)], lHintLabel]));
        end;
      end;
    finally
      lHotspotEdges.Free;
    end;

    lUnresolvedUnits := GetSortedUnresolvedUnits;
    try
      if lUnresolvedUnits.Count > 0 then
      begin
        lBuilder.AppendLine('Unresolved units:');
        for lUnitName in lUnresolvedUnits do
        begin
          if not IsFrameworkUnitName(lUnitName) then
          begin
            lBuilder.AppendLine('  - ' + lUnitName);
          end;
        end;
      end;
    finally
      lUnresolvedUnits.Free;
    end;

    lParserProblemList := GetSortedParserProblems;
    try
      if lParserProblemList.Count > 0 then
      begin
        lBuilder.AppendLine('Parser problems:');
        for lParserProblem in lParserProblemList do
        begin
          lBuilder.AppendLine(Format('  - %s (%s): %s',
            [lParserProblem.fUnitName, lParserProblem.fFileName, lParserProblem.fDescription]));
        end;
      end;
    finally
      lParserProblemList.Free;
    end;

    if aFocusUnitName <> '' then
    begin
      lBuilder.AppendLine('Focus unit: ' + aFocusUnitName);
      if fNodes.TryGetValue(aFocusUnitName, lNode) then
      begin
        lBuilder.AppendLine('  Resolution: ' + ResolutionToText(lNode.fResolution));
        if lNode.fPath <> '' then
        begin
          lBuilder.AppendLine('  Path: ' + lNode.fPath);
        end;
      end;
      lBuilder.AppendLine('  Outgoing:');
      lEdgeList := GetSortedEdgeList;
      try
        for lEdge in lEdgeList do
        begin
          if SameText(lEdge.fFromName, aFocusUnitName) then
          begin
            lBuilder.AppendLine(Format('    %s -> %s [%s]',
              [lEdge.fFromName, lEdge.fToName, EdgeKindToText(lEdge.fEdgeKind)]));
          end;
        end;
      finally
        lEdgeList.Free;
      end;
      if Assigned(fSccData) then
      begin
        for lCycleText in fSccData.fCycles do
        begin
          if CycleContainsUnit(lCycleText, aFocusUnitName) then
          begin
            lBuilder.AppendLine('  Cycle component: ' + lCycleText);
          end;
        end;
      end;
    end else
    begin
      lBuilder.AppendLine('Resolved project units:');
      lNodeNames := GetSortedNodeNames;
      try
        for lNodeName in lNodeNames do
        begin
          lNode := fNodes.Items[lNodeName];
          if lNode.fIsProjectUnit and (lNode.fResolution = TDepsNodeResolution.dnrResolved) then
          begin
            lBuilder.AppendLine('  - ' + lNode.fName);
          end;
        end;
      finally
        lNodeNames.Free;
      end;
    end;

    Result := TrimRight(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

class function TDepsGraphBuilder.ResolutionToText(aResolution: TDepsNodeResolution): string;
begin
  case aResolution of
    TDepsNodeResolution.dnrResolved:
      Result := 'resolved';
    TDepsNodeResolution.dnrUnresolved:
      Result := 'unresolved';
  else
    Result := 'parserProblem';
  end;
end;

constructor TDepsCommandRunner.Create(const aOptions: TAppOptions);
begin
  inherited Create;
  fOptions := aOptions;
end;

function TDepsCommandRunner.Execute: Integer;
var
  lError: string;
  lGraphBuilder: TDepsGraphBuilder;
  lOutputPath: string;
  lOutputText: string;
begin
  if not TryBuildContext(lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitInvalidProjectInput);
  end;

  lGraphBuilder := TDepsGraphBuilder.Create(fContext, fOptions);
  try
    lGraphBuilder.Build;
    if fOptions.fDepsFormat = TDepsFormat.dfText then
      lOutputText := lGraphBuilder.RenderText(fOptions.fDepsUnitName, fOptions.fDepsTopLimit)
    else
      lOutputText := lGraphBuilder.RenderJson;
    lOutputPath := ResolveOutputPath;
    WriteOutput(lOutputText, lOutputPath);
  finally
    lGraphBuilder.Free;
  end;

  Result := cExitSuccess;
end;

function TDepsCommandRunner.ResolveOutputPath: string;
begin
  if fOptions.fHasDepsOutputPath and (Trim(fOptions.fDepsOutputPath) <> '') then
    Result := fOptions.fDepsOutputPath
  else if fOptions.fDepsFormat = TDepsFormat.dfText then
    Result := TPath.Combine(TPath.Combine(fContext.DakProjectRoot, 'deps'), 'deps.txt')
  else
    Result := TPath.Combine(TPath.Combine(fContext.DakProjectRoot, 'deps'), 'deps.json');
end;

function TDepsCommandRunner.TryBuildContext(out aError: string): Boolean;
begin
  Result := TryBuildProjectAnalysisContext(fOptions, TProjectAnalysisContextRequirement.AllowDegraded,
    fContext, aError);
end;

procedure TDepsCommandRunner.WriteOutput(const aOutputText, aOutputPath: string);
var
  lOutputDir: string;
begin
  WriteLn(aOutputText);
  if (aOutputPath <> '') and (aOutputPath <> '-') then
  begin
    lOutputDir := TPath.GetDirectoryName(aOutputPath);
    if lOutputDir <> '' then
    begin
      TDirectory.CreateDirectory(lOutputDir);
    end;
    TFile.WriteAllText(aOutputPath, aOutputText, TEncoding.UTF8);
  end;
end;

function RunDepsCommand(const aOptions: TAppOptions): Integer;
var
  lRunner: TDepsCommandRunner;
begin
  lRunner := TDepsCommandRunner.Create(aOptions);
  try
    Result := lRunner.Execute;
  finally
    lRunner.Free;
  end;
end;

end.
