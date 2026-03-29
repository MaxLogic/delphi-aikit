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
  DelphiAST.Classes,
  DelphiAST.Consts,
  DelphiAST.ProjectIndexer,
  Dak.ExitCodes,
  Dak.Project;

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

  TDepsGraphBuilder = class
  private
    fContext: TProjectAnalysisContext;
    fEdges: TList<TDepsEdgeInfo>;
    fEdgeKeys: THashSet<string>;
    fNodes: TObjectDictionary<string, TDepsNodeInfo>;
    fParserProblems: TList<TDepsParserProblemInfo>;
    fUnresolvedUnits: THashSet<string>;
    class procedure AddReachableNodes(const aStartNodeName: string;
      const aAdjacency: TObjectDictionary<string, TList<string>>; const aVisited: THashSet<string>); static;
    class function BuildAdjacency(const aEdges: TList<TDepsEdgeInfo>; const aEligibleNodes: THashSet<string>;
      const aReverse: Boolean): TObjectDictionary<string, TList<string>>; static;
    class function BuildCycles(const aEdges: TList<TDepsEdgeInfo>;
      const aNodes: TObjectDictionary<string, TDepsNodeInfo>): TList<string>; static;
    class function BuildEdgeKey(const aEdge: TDepsEdgeInfo): string; static;
    class procedure CollectUsesEdges(const aOwnerName: string; const aUsesNode: TSyntaxNode;
      aEdgeKind: TDepsEdgeKind; const aEdges: TList<TDepsEdgeInfo>; const aEdgeKeys: THashSet<string>); static;
    class function CycleContainsUnit(const aCycleText, aUnitName: string): Boolean; static;
    class function EdgeKindToText(aEdgeKind: TDepsEdgeKind): string; static;
    class function ExtractUnitNameFromFileName(const aFileName: string): string; static;
    class function FindFirstChildNode(const aNode: TSyntaxNode; aNodeType: TSyntaxNodeType): TSyntaxNode; static;
    class function IsFrameworkUnitName(const aUnitName: string): Boolean; static;
    function GetSortedEdgeList: TList<TDepsEdgeInfo>;
    function GetSortedNodeNames: TStringList;
    function GetSortedParserProblems: TList<TDepsParserProblemInfo>;
    function GetSortedUnresolvedUnits: TStringList;
    function IsProjectUnitPath(const aFileName: string): Boolean;
    procedure MergeNode(const aNodeName, aPath: string; aResolution: TDepsNodeResolution);
    class function ResolutionToText(aResolution: TDepsNodeResolution): string; static;
  public
    constructor Create(const aContext: TProjectAnalysisContext);
    destructor Destroy; override;
    procedure Build;
    function DefaultOutputPath(aFormat: TDepsFormat): string;
    function RenderJson: string;
    function RenderText(const aFocusUnitName: string): string;
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

class procedure TDepsGraphBuilder.AddReachableNodes(const aStartNodeName: string;
  const aAdjacency: TObjectDictionary<string, TList<string>>; const aVisited: THashSet<string>);
var
  lCurrentName: string;
  lNeighborName: string;
  lNeighbors: TList<string>;
  lStack: TStack<string>;
begin
  lStack := TStack<string>.Create;
  try
    lStack.Push(aStartNodeName);
    while lStack.Count > 0 do
    begin
      lCurrentName := lStack.Pop;
      if not aVisited.Add(lCurrentName) then
      begin
        Continue;
      end;
      if not aAdjacency.TryGetValue(lCurrentName, lNeighbors) then
      begin
        Continue;
      end;
      for lNeighborName in lNeighbors do
      begin
        if not aVisited.Contains(lNeighborName) then
        begin
          lStack.Push(lNeighborName);
        end;
      end;
    end;
  finally
    lStack.Free;
  end;
end;

class function TDepsGraphBuilder.BuildAdjacency(const aEdges: TList<TDepsEdgeInfo>; const aEligibleNodes: THashSet<string>;
  const aReverse: Boolean): TObjectDictionary<string, TList<string>>;
var
  lEdge: TDepsEdgeInfo;
  lFromName: string;
  lList: TList<string>;
  lToName: string;
begin
  Result := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  for lEdge in aEdges do
  begin
    if not aEligibleNodes.Contains(lEdge.fFromName) or not aEligibleNodes.Contains(lEdge.fToName) then
    begin
      Continue;
    end;
    if aReverse then
    begin
      lFromName := lEdge.fToName;
      lToName := lEdge.fFromName;
    end else
    begin
      lFromName := lEdge.fFromName;
      lToName := lEdge.fToName;
    end;
    if not Result.TryGetValue(lFromName, lList) then
    begin
      lList := TList<string>.Create;
      Result.Add(lFromName, lList);
    end;
    if lList.IndexOf(lToName) < 0 then
    begin
      lList.Add(lToName);
    end;
  end;
end;

class function TDepsGraphBuilder.BuildCycles(const aEdges: TList<TDepsEdgeInfo>;
  const aNodes: TObjectDictionary<string, TDepsNodeInfo>): TList<string>;
var
  lBackwardReachable: THashSet<string>;
  lComponent: TStringList;
  lCycles: TList<string>;
  lEdge: TDepsEdgeInfo;
  lEligibleNodes: THashSet<string>;
  lForwardAdjacency: TObjectDictionary<string, TList<string>>;
  lForwardReachable: THashSet<string>;
  lHandled: THashSet<string>;
  lHasSelfLoop: Boolean;
  lNode: TDepsNodeInfo;
  lNodeList: TStringList;
  lRootName: string;
  lReverseAdjacency: TObjectDictionary<string, TList<string>>;
begin
  lCycles := TList<string>.Create;
  lEligibleNodes := THashSet<string>.Create;
  lHandled := THashSet<string>.Create;
  lNodeList := TStringList.Create;
  try
    lNodeList.Sorted := True;
    lNodeList.Duplicates := dupIgnore;
    for lNode in aNodes.Values do
    begin
      if lNode.fIsProjectUnit and (lNode.fResolution = TDepsNodeResolution.dnrResolved) then
      begin
        lEligibleNodes.Add(lNode.fName);
        lNodeList.Add(lNode.fName);
      end;
    end;

    lForwardAdjacency := BuildAdjacency(aEdges, lEligibleNodes, False);
    try
      lReverseAdjacency := BuildAdjacency(aEdges, lEligibleNodes, True);
      try
        for lRootName in lNodeList do
        begin
          if lHandled.Contains(lRootName) then
          begin
            Continue;
          end;

          lForwardReachable := THashSet<string>.Create;
          lBackwardReachable := THashSet<string>.Create;
          lComponent := TStringList.Create;
          try
            lComponent.Sorted := True;
            lComponent.Duplicates := dupIgnore;
            AddReachableNodes(lRootName, lForwardAdjacency, lForwardReachable);
            AddReachableNodes(lRootName, lReverseAdjacency, lBackwardReachable);
            for lNode in aNodes.Values do
            begin
              if lForwardReachable.Contains(lNode.fName) and lBackwardReachable.Contains(lNode.fName) then
              begin
                lComponent.Add(lNode.fName);
              end;
            end;

            lHasSelfLoop := False;
            if lComponent.Count = 1 then
            begin
              for lEdge in aEdges do
              begin
                if SameText(lEdge.fFromName, lRootName) and SameText(lEdge.fToName, lRootName) then
                begin
                  lHasSelfLoop := True;
                  Break;
                end;
              end;
            end;

            for lNode in aNodes.Values do
            begin
              if lComponent.IndexOf(lNode.fName) >= 0 then
              begin
                lHandled.Add(lNode.fName);
              end;
            end;

            if (lComponent.Count > 1) or lHasSelfLoop then
            begin
              lCycles.Add(String.Join(' -> ', lComponent.ToStringArray) + ' -> ' + lComponent[0]);
            end;
          finally
            lComponent.Free;
            lBackwardReachable.Free;
            lForwardReachable.Free;
          end;
        end;
      finally
        lReverseAdjacency.Free;
      end;
    finally
      lForwardAdjacency.Free;
    end;

    Result := lCycles;
  except
    lCycles.Free;
    raise;
  end;
  lNodeList.Free;
  lHandled.Free;
  lEligibleNodes.Free;
end;

class function TDepsGraphBuilder.BuildEdgeKey(const aEdge: TDepsEdgeInfo): string;
begin
  Result := LowerCase(aEdge.fFromName) + '|' + LowerCase(aEdge.fToName) + '|' + IntToStr(Ord(aEdge.fEdgeKind));
end;

class procedure TDepsGraphBuilder.CollectUsesEdges(const aOwnerName: string; const aUsesNode: TSyntaxNode;
  aEdgeKind: TDepsEdgeKind; const aEdges: TList<TDepsEdgeInfo>; const aEdgeKeys: THashSet<string>);
var
  lChildNode: TSyntaxNode;
  lEdge: TDepsEdgeInfo;
  lEdgeKey: string;
begin
  if not Assigned(aUsesNode) then
  begin
    Exit;
  end;
  for lChildNode in aUsesNode.ChildNodes do
  begin
    if lChildNode.Typ <> TSyntaxNodeType.ntUnit then
    begin
      Continue;
    end;
    lEdge.fFromName := aOwnerName;
    lEdge.fToName := Trim(lChildNode.GetAttribute(anName));
    lEdge.fEdgeKind := aEdgeKind;
    if lEdge.fToName = '' then
    begin
      Continue;
    end;
    lEdgeKey := BuildEdgeKey(lEdge);
    if aEdgeKeys.Add(lEdgeKey) then
    begin
      aEdges.Add(lEdge);
    end;
  end;
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

constructor TDepsGraphBuilder.Create(const aContext: TProjectAnalysisContext);
begin
  inherited Create;
  fContext := aContext;
  fEdges := TList<TDepsEdgeInfo>.Create;
  fEdgeKeys := THashSet<string>.Create;
  fNodes := TObjectDictionary<string, TDepsNodeInfo>.Create([doOwnsValues]);
  fParserProblems := TList<TDepsParserProblemInfo>.Create;
  fUnresolvedUnits := THashSet<string>.Create;
end;

function TDepsGraphBuilder.DefaultOutputPath(aFormat: TDepsFormat): string;
begin
  if aFormat = TDepsFormat.dfText then
    Result := TPath.Combine(TPath.Combine(fContext.fDakProjectRoot, 'deps'), 'deps.txt')
  else
    Result := TPath.Combine(TPath.Combine(fContext.fDakProjectRoot, 'deps'), 'deps.json');
end;

destructor TDepsGraphBuilder.Destroy;
begin
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

class function TDepsGraphBuilder.ExtractUnitNameFromFileName(const aFileName: string): string;
begin
  Result := TPath.GetFileNameWithoutExtension(aFileName);
end;

class function TDepsGraphBuilder.FindFirstChildNode(const aNode: TSyntaxNode; aNodeType: TSyntaxNodeType): TSyntaxNode;
begin
  Result := nil;
  if not Assigned(aNode) then
  begin
    Exit;
  end;
  if aNode.Typ = aNodeType then
  begin
    Exit(aNode);
  end;
  Result := aNode.FindNode(aNodeType);
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
  lProjectDir := IncludeTrailingPathDelimiter(TPath.GetFullPath(fContext.fProjectDir));
  Result := SameText(Copy(lFileDir, 1, Length(lProjectDir)), lProjectDir);
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
  lContainsNode: TSyntaxNode;
  lIndexer: TProjectIndexer;
  lImplementationNode: TSyntaxNode;
  lInterfaceNode: TSyntaxNode;
  lIsProjectSource: Boolean;
  lProblem: TProjectIndexer.TProblemInfo;
  lUnitInfo: TProjectIndexer.TUnitInfo;
  lUnitNode: TSyntaxNode;
  lUnitName: string;
  lUsesNode: TSyntaxNode;
  lProblemInfo: TDepsParserProblemInfo;
begin
  lIndexer := TProjectIndexer.Create;
  try
    lIndexer.Defines := fContext.fParserDefines;
    lIndexer.SearchPath := fContext.fParserSearchPath;
    lIndexer.Index(fContext.fMainSourcePath);

    for lUnitInfo in lIndexer.ParsedUnits do
    begin
      MergeNode(lUnitInfo.Name, lUnitInfo.Path, TDepsNodeResolution.dnrResolved);
      lIsProjectSource := SameText(TPath.GetExtension(lUnitInfo.Path), '.dpr');
      lUnitNode := FindFirstChildNode(lUnitInfo.SyntaxTree, TSyntaxNodeType.ntUnit);
      if not Assigned(lUnitNode) then
      begin
        Continue;
      end;

      if lIsProjectSource then
      begin
        lUsesNode := FindFirstChildNode(lUnitNode, TSyntaxNodeType.ntUses);
        CollectUsesEdges(lUnitInfo.Name, lUsesNode, TDepsEdgeKind.dekProject, fEdges, fEdgeKeys);
        lContainsNode := FindFirstChildNode(lUnitNode, TSyntaxNodeType.ntContains);
        CollectUsesEdges(lUnitInfo.Name, lContainsNode, TDepsEdgeKind.dekContains, fEdges, fEdgeKeys);
      end else
      begin
        lInterfaceNode := FindFirstChildNode(lUnitNode, TSyntaxNodeType.ntInterface);
        lUsesNode := FindFirstChildNode(lInterfaceNode, TSyntaxNodeType.ntUses);
        CollectUsesEdges(lUnitInfo.Name, lUsesNode, TDepsEdgeKind.dekInterface, fEdges, fEdgeKeys);
        lImplementationNode := FindFirstChildNode(lUnitNode, TSyntaxNodeType.ntImplementation);
        lUsesNode := FindFirstChildNode(lImplementationNode, TSyntaxNodeType.ntUses);
        CollectUsesEdges(lUnitInfo.Name, lUsesNode, TDepsEdgeKind.dekImplementation, fEdges, fEdgeKeys);
      end;
    end;

    for lUnitName in lIndexer.NotFoundUnits do
    begin
      lProblemInfo.fUnitName := ExtractUnitNameFromFileName(lUnitName);
      fUnresolvedUnits.Add(lProblemInfo.fUnitName);
      MergeNode(lProblemInfo.fUnitName, '', TDepsNodeResolution.dnrUnresolved);
    end;

    for lProblem in lIndexer.Problems do
    begin
      if lProblem.ProblemType <> TProjectIndexer.TProblemType.ptCantParseFile then
      begin
        Continue;
      end;
      lProblemInfo.fUnitName := ExtractUnitNameFromFileName(lProblem.FileName);
      lProblemInfo.fFileName := lProblem.FileName;
      lProblemInfo.fDescription := lProblem.Description;
      fParserProblems.Add(lProblemInfo);
      MergeNode(lProblemInfo.fUnitName, lProblemInfo.fFileName, TDepsNodeResolution.dnrParserProblem);
    end;
  finally
    lIndexer.Free;
  end;
end;

function TDepsGraphBuilder.RenderJson: string;
var
  lCycleList: TList<string>;
  lCyclesJson: TJSONArray;
  lEdge: TDepsEdgeInfo;
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
  lRoot: TJSONObject;
  lSummary: TJSONObject;
  lUnresolvedJson: TJSONArray;
  lUnresolvedUnits: TStringList;
begin
  lRoot := TJSONObject.Create;
  try
    lProjectJson := TJSONObject.Create;
    lProjectJson.AddPair('name', fContext.fProjectName);
    lProjectJson.AddPair('path', fContext.fProjectPath);
    lProjectJson.AddPair('mainSource', fContext.fMainSourcePath);
    if fContext.fHasDelphiContext then
      lProjectJson.AddPair('contextMode', 'full')
    else
      lProjectJson.AddPair('contextMode', 'degraded');
    if fContext.fContextNote <> '' then
      lProjectJson.AddPair('contextNote', fContext.fContextNote);
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
      for var lNodeName in lNodeNames do
      begin
        lNode := fNodes.Items[lNodeName];
        lNodeJson := TJSONObject.Create;
        lNodeJson.AddPair('name', lNode.fName);
        if lNode.fPath <> '' then
          lNodeJson.AddPair('path', lNode.fPath);
        lNodeJson.AddPair('isProjectUnit', TJSONBool.Create(lNode.fIsProjectUnit));
        lNodeJson.AddPair('resolution', ResolutionToText(lNode.fResolution));
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
        lEdges.AddElement(TJSONObject.Create
          .AddPair('from', lEdge.fFromName)
          .AddPair('to', lEdge.fToName)
          .AddPair('edgeKind', EdgeKindToText(lEdge.fEdgeKind)));
      end;
    finally
      lEdgeList.Free;
    end;

    lUnresolvedJson := TJSONArray.Create;
    lRoot.AddPair('unresolvedUnits', lUnresolvedJson);
    lUnresolvedUnits := GetSortedUnresolvedUnits;
    try
      for var lUnitName in lUnresolvedUnits do
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

    lCyclesJson := TJSONArray.Create;
    lRoot.AddPair('cycles', lCyclesJson);
    lCycleList := BuildCycles(fEdges, fNodes);
    try
      for var lCycleText in lCycleList do
      begin
        lCyclesJson.AddElement(TJSONString.Create(lCycleText));
      end;
    finally
      lCycleList.Free;
    end;

    Result := lRoot.Format(2);
  finally
    lRoot.Free;
  end;
end;

function TDepsGraphBuilder.RenderText(const aFocusUnitName: string): string;
var
  lBuilder: TStringBuilder;
  lCycleList: TList<string>;
  lEdge: TDepsEdgeInfo;
  lEdgeList: TList<TDepsEdgeInfo>;
  lNode: TDepsNodeInfo;
  lNodeNames: TStringList;
  lParserProblem: TDepsParserProblemInfo;
  lParserProblemList: TList<TDepsParserProblemInfo>;
  lUnresolvedUnits: TStringList;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('Project: ' + fContext.fProjectName);
    lBuilder.AppendLine(Format('Summary: nodes=%d edges=%d unresolved=%d parserProblems=%d',
      [fNodes.Count, fEdges.Count, fUnresolvedUnits.Count, fParserProblems.Count]));
    if fContext.fContextNote <> '' then
    begin
      lBuilder.AppendLine('Context: ' + fContext.fContextNote);
    end;

    lUnresolvedUnits := GetSortedUnresolvedUnits;
    try
      if lUnresolvedUnits.Count > 0 then
      begin
        lBuilder.AppendLine('Unresolved units:');
        for var lUnitName in lUnresolvedUnits do
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

    lCycleList := BuildCycles(fEdges, fNodes);
    try
      if lCycleList.Count > 0 then
      begin
        lBuilder.AppendLine('Cycles:');
        for var lCycleText in lCycleList do
        begin
          lBuilder.AppendLine('  - ' + lCycleText);
        end;
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
        for var lCycleText in lCycleList do
        begin
          if CycleContainsUnit(lCycleText, aFocusUnitName) then
          begin
            lBuilder.AppendLine('  Cycle component: ' + lCycleText);
          end;
        end;
      end else
      begin
        lBuilder.AppendLine('Resolved project units:');
        lNodeNames := GetSortedNodeNames;
        try
          for var lNodeName in lNodeNames do
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
    finally
      lCycleList.Free;
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

  lGraphBuilder := TDepsGraphBuilder.Create(fContext);
  try
    lGraphBuilder.Build;
    if fOptions.fDepsFormat = TDepsFormat.dfText then
      lOutputText := lGraphBuilder.RenderText(fOptions.fDepsUnitName)
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
    Result := TPath.Combine(TPath.Combine(fContext.fDakProjectRoot, 'deps'), 'deps.txt')
  else
    Result := TPath.Combine(TPath.Combine(fContext.fDakProjectRoot, 'deps'), 'deps.json');
end;

function TDepsCommandRunner.TryBuildContext(out aError: string): Boolean;
begin
  Result := TryBuildProjectAnalysisContext(fOptions, fContext, aError);
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
