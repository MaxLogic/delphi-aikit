unit Dak.GlobalVars;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Hash,
  System.IOUtils,
  System.JSON,
  System.Math,
  System.Masks,
  System.StrUtils,
  System.SysUtils,
  System.Variants,
  Xml.XMLDoc,
  Xml.XMLIntf,
  DelphiAST.Classes,
  DelphiAST.Consts,
  DelphiAST.ProjectIndexer,
  Dak.Types;

function RunGlobalVarsCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  Dak.FixInsightSettings,
  Dak.Messages,
  Dak.Project,
  Dak.Registry,
  Dak.RsVars,
  FireDAC.DApt,
  FireDAC.Comp.Client,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.Async,
  FireDAC.Stan.Def,
  FireDAC.Stan.Error,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option;

type
  TGlobalVarKind = (gvkVar, gvkThreadVar, gvkTypedConst, gvkClassVar);
  TAccessKind = (akRead, akWrite, akReadWrite);

  TGlobalVarRef = record
    UnitName: string;
    RoutineName: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    Access: TAccessKind;
  end;

  TIdentifierUsage = record
    Name: string;
    Line: Integer;
    Column: Integer;
    Access: TAccessKind;
  end;

  TGlobalVarAmbiguity = record
    Name: string;
    UnitName: string;
    RoutineName: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    Access: TAccessKind;
    Candidates: string;
  end;

  TGlobalVarSymbol = class
  public
    Name: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    TypeName: string;
    Kind: TGlobalVarKind;
    UsedBy: TList<TGlobalVarRef>;
    constructor Create;
    destructor Destroy; override;
  end;

  TRoutineInfo = record
    UnitName: string;
    FileName: string;
    Name: string;
    StartLine: Integer;
    EndLine: Integer;
    LocalNames: TDictionary<string, Byte>;
    IdentifierUsages: TList<TIdentifierUsage>;
  end;

  TUnitInfo = class
  public
    UnitName: string;
    FileName: string;
    UsesUnits: TArray<string>;
    Lines: TArray<string>;
    Symbols: TObjectList<TGlobalVarSymbol>;
    Routines: TList<TRoutineInfo>;
    constructor Create;
    destructor Destroy; override;
  end;

  TProjectInfo = record
    ProjectPath: string;
    ProjectName: string;
    MainSourcePath: string;
    ParserDefines: string;
    ParserSearchPath: string;
    OutputPath: string;
    CachePath: string;
    ReportsPath: string;
    TempPath: string;
  end;

  TSourceAnalyzer = class
  private
    fProject: TProjectInfo;
    fUnitsByName: TObjectDictionary<string, TUnitInfo>;
    fVisitedFiles: TDictionary<string, Byte>;
    fSymbols: TObjectList<TGlobalVarSymbol>;
    fAmbiguities: TList<TGlobalVarAmbiguity>;
    class function StripCommentPrefix(const aLine: string): string; static;
    class function NormalizeKey(const aValue: string): string; static;
    class function FindChildNode(const aParent: TSyntaxNode; const aNodeType: TSyntaxNodeType): TSyntaxNode; static;
    class function FindAncestorNode(const aNode: TSyntaxNode; const aNodeType: TSyntaxNodeType): TSyntaxNode; static;
    class procedure CollectNodes(const aRoot: TSyntaxNode; const aNodeType: TSyntaxNodeType; const aNodes: TList<TSyntaxNode>); static;
    class function CountOccurrences(const aText, aPattern: string): Integer; static;
    class function IsIdentifierChar(const aCh: Char): Boolean; static;
    class function FindWordPosition(const aText, aWord: string): Integer; static;
    class function SplitIdentifierList(const aText: string): TArray<string>; static;
    class function ExtractProjectEntryPoint(const aProjectPath: string): string; static;
    class function ExtractNodeName(const aNode: TSyntaxNode): string; static;
    class function ExtractTypeName(const aNode: TSyntaxNode): string; static;
    class function FindSectionKind(const aLines: TArray<string>; const aLine: Integer): TGlobalVarKind; static;
    class function IsClassVarDeclaration(const aLines: TArray<string>; const aLine: Integer): Boolean; static;
    class function IsTopLevelDeclarationNode(const aNode: TSyntaxNode): Boolean; static;
    class function IsMethodImplementationNode(const aNode: TSyntaxNode): Boolean; static;
    class function IsValidIdentifier(const aName: string): Boolean; static;
    class function IsDescendantOf(const aNode, aAncestor: TSyntaxNode): Boolean; static;
    procedure LoadIndexedUnits;
    class function ResolveUnitPath(const aBaseDir, aUnitSpec: string): string; static;
    class function TryExtractRoutineName(const aLine: string; out aName: string): Boolean; static;
    class function TryExtractDeclaration(const aLine: string; out aNames: TArray<string>; out aTypeName: string): Boolean; static;
    class function TryExtractTypedConst(const aLine: string; out aName: string; out aTypeName: string): Boolean; static;
    class function DetectAccess(const aLine, aSymbol: string): TAccessKind; static;
    class function IsWordBoundary(const aText: string; const aIndex: Integer): Boolean; static;
    class function IsSectionKeyword(const aText: string): Boolean; static;
    class function IsRoutineStart(const aText: string): Boolean; static;
    procedure LoadUnitRecursive(const aFileName: string);
    function ParseUnit(const aFileName: string; const aSyntaxTree: TSyntaxNode = nil): TUnitInfo;
    class function ParseUsesUnits(const aText: string): TArray<string>; static;
    class procedure ParseUsesFromAst(const aUnit: TUnitInfo; const aSyntaxTree: TSyntaxNode); static;
    class procedure ParseGlobalVarsFromAst(const aUnit: TUnitInfo; const aSyntaxTree: TSyntaxNode); static;
    class procedure ParseClassVarsFromAst(const aUnit: TUnitInfo; const aSyntaxTree: TSyntaxNode); static;
    class procedure ParseTypedConstsFromLines(const aUnit: TUnitInfo; const aLines: TArray<string>); static;
    class procedure CollectRoutineLocalNames(const aMethodNode: TSyntaxNode; const aLocalNames: TDictionary<string, Byte>); static;
    class procedure CollectRoutineUsages(const aMethodNode: TSyntaxNode; const aUsages: TList<TIdentifierUsage>); static;
    class procedure ParseRoutinesFromAst(const aUnit: TUnitInfo; const aSyntaxTree: TSyntaxNode); static;
    class procedure ParseGlobalVars(const aUnit: TUnitInfo; const aLines: TArray<string>); static;
    class procedure ParseClassVars(const aUnit: TUnitInfo; const aLines: TArray<string>); static;
    class procedure ParseRoutines(const aUnit: TUnitInfo; const aLines: TArray<string>); static;
    procedure ResolveUsages(const aUnit: TUnitInfo);
    class function BuildInputHash(const aProjectPath: string; const aFiles: TArray<string>): string; static;
    class function AccessToText(const aAccess: TAccessKind): string; static;
    class function KindToText(const aKind: TGlobalVarKind): string; static;
  public
    constructor Create(const aProject: TProjectInfo);
    destructor Destroy; override;
    function Analyze(out aInputHash: string): TObjectList<TGlobalVarSymbol>;
    function GetVisitedFiles: TArray<string>;
    property Ambiguities: TList<TGlobalVarAmbiguity> read fAmbiguities;
  end;

constructor TGlobalVarSymbol.Create;
begin
  inherited Create;
  UsedBy := TList<TGlobalVarRef>.Create;
end;

destructor TGlobalVarSymbol.Destroy;
begin
  UsedBy.Free;
  inherited Destroy;
end;

constructor TUnitInfo.Create;
begin
  inherited Create;
  Symbols := TObjectList<TGlobalVarSymbol>.Create(False);
  Routines := TList<TRoutineInfo>.Create;
end;

destructor TUnitInfo.Destroy;
var
  lRoutine: TRoutineInfo;
begin
  for lRoutine in Routines do
  begin
    lRoutine.IdentifierUsages.Free;
    lRoutine.LocalNames.Free;
  end;
  Routines.Free;
  Symbols.Free;
  inherited Destroy;
end;

constructor TSourceAnalyzer.Create(const aProject: TProjectInfo);
begin
  inherited Create;
  fProject := aProject;
  fUnitsByName := TObjectDictionary<string, TUnitInfo>.Create([doOwnsValues]);
  fVisitedFiles := TDictionary<string, Byte>.Create;
  fSymbols := TObjectList<TGlobalVarSymbol>.Create(False);
  fAmbiguities := TList<TGlobalVarAmbiguity>.Create;
end;

destructor TSourceAnalyzer.Destroy;
begin
  fAmbiguities.Free;
  fSymbols.Free;
  fVisitedFiles.Free;
  fUnitsByName.Free;
  inherited Destroy;
end;

class function TSourceAnalyzer.NormalizeKey(const aValue: string): string;
begin
  Result := AnsiLowerCase(Trim(aValue));
end;

class function TSourceAnalyzer.FindChildNode(const aParent: TSyntaxNode; const aNodeType: TSyntaxNodeType): TSyntaxNode;
var
  lChildNode: TSyntaxNode;
begin
  Result := nil;
  if not Assigned(aParent) then
  begin
    Exit;
  end;
  for lChildNode in aParent.ChildNodes do
  begin
    if lChildNode.Typ = aNodeType then
    begin
      Exit(lChildNode);
    end;
  end;
end;

class function TSourceAnalyzer.FindAncestorNode(const aNode: TSyntaxNode; const aNodeType: TSyntaxNodeType): TSyntaxNode;
begin
  Result := aNode;
  while Assigned(Result) do
  begin
    if Result.Typ = aNodeType then
    begin
      Exit;
    end;
    Result := Result.ParentNode;
  end;
end;

class procedure TSourceAnalyzer.CollectNodes(const aRoot: TSyntaxNode; const aNodeType: TSyntaxNodeType;
  const aNodes: TList<TSyntaxNode>);
var
  lChildNode: TSyntaxNode;
begin
  if not Assigned(aRoot) then
  begin
    Exit;
  end;
  if aRoot.Typ = aNodeType then
  begin
    aNodes.Add(aRoot);
  end;
  for lChildNode in aRoot.ChildNodes do
  begin
    CollectNodes(lChildNode, aNodeType, aNodes);
  end;
end;

class function TSourceAnalyzer.StripCommentPrefix(const aLine: string): string;
var
  lPos: Integer;
  lText: string;
begin
  lText := Trim(aLine);
  lPos := Pos('//', lText);
  if lPos > 0 then
  begin
    lText := Trim(Copy(lText, 1, lPos - 1));
  end;
  Result := lText;
end;

class function TSourceAnalyzer.CountOccurrences(const aText, aPattern: string): Integer;
var
  lPos: Integer;
  lNext: Integer;
begin
  Result := 0;
  if (aText = '') or (aPattern = '') then
  begin
    Exit;
  end;
  lPos := 1;
  repeat
    lNext := PosEx(aPattern, aText, lPos);
    if lNext > 0 then
    begin
      Inc(Result);
      lPos := lNext + Length(aPattern);
    end;
  until lNext = 0;
end;

class function TSourceAnalyzer.IsIdentifierChar(const aCh: Char): Boolean;
begin
  Result := CharInSet(aCh, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

class function TSourceAnalyzer.IsWordBoundary(const aText: string; const aIndex: Integer): Boolean;
begin
  Result := (aIndex < 1) or (aIndex > Length(aText)) or not IsIdentifierChar(aText[aIndex]);
end;

class function TSourceAnalyzer.FindWordPosition(const aText, aWord: string): Integer;
var
  lUpperText: string;
  lUpperWord: string;
  lStart: Integer;
begin
  Result := 0;
  lUpperText := UpperCase(aText);
  lUpperWord := UpperCase(aWord);
  lStart := 1;
  while True do
  begin
    Result := PosEx(lUpperWord, lUpperText, lStart);
    if Result = 0 then
    begin
      Exit;
    end;
    if IsWordBoundary(aText, Result - 1) and IsWordBoundary(aText, Result + Length(aWord)) then
    begin
      Exit;
    end;
    lStart := Result + Length(aWord);
  end;
end;

class function TSourceAnalyzer.SplitIdentifierList(const aText: string): TArray<string>;
var
  lParts: TArray<string>;
  lPart: string;
  lList: TList<string>;
  lIndex: Integer;
begin
  lList := TList<string>.Create;
  try
    lParts := aText.Split([',']);
    for lIndex := 0 to High(lParts) do
    begin
      lPart := Trim(lParts[lIndex]);
      if lPart <> '' then
      begin
        lList.Add(lPart);
      end;
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

class function TSourceAnalyzer.ExtractProjectEntryPoint(const aProjectPath: string): string;
var
  lDoc: IXMLDocument;
  lNode: IXMLNode;
  lMainSource: string;
  lRootDir: string;
begin
  lDoc := TXMLDocument.Create(nil);
  lDoc.LoadFromFile(aProjectPath);
  lDoc.Active := True;
  lNode := lDoc.DocumentElement.ChildNodes.FindNode('PropertyGroup');
  while lNode <> nil do
  begin
    if lNode.ChildNodes.FindNode('MainSource') <> nil then
    begin
      lMainSource := Trim(lNode.ChildNodes['MainSource'].Text);
      if lMainSource <> '' then
      begin
        Break;
      end;
    end;
    lNode := lNode.NextSibling;
    while (lNode <> nil) and not SameText(lNode.NodeName, 'PropertyGroup') do
    begin
      lNode := lNode.NextSibling;
    end;
  end;
  if lMainSource = '' then
  begin
    raise Exception.CreateFmt(SMainSourceMissingFile, [aProjectPath]);
  end;
  lRootDir := TPath.GetDirectoryName(aProjectPath);
  Result := TPath.GetFullPath(TPath.Combine(lRootDir, lMainSource));
end;

class function TSourceAnalyzer.ExtractNodeName(const aNode: TSyntaxNode): string;
begin
  Result := '';
  if not Assigned(aNode) then
  begin
    Exit;
  end;
  if aNode is TValuedSyntaxNode then
  begin
    Result := Trim(TValuedSyntaxNode(aNode).Value);
  end;
  if (Result = '') and aNode.HasAttribute(anName) then
  begin
    Result := Trim(aNode.GetAttribute(anName));
  end;
end;

class function TSourceAnalyzer.ExtractTypeName(const aNode: TSyntaxNode): string;
var
  lTypeNode: TSyntaxNode;
begin
  Result := '';
  if not Assigned(aNode) then
  begin
    Exit;
  end;
  lTypeNode := FindChildNode(aNode, ntType);
  if Assigned(lTypeNode) then
  begin
    Result := Trim(lTypeNode.GetAttribute(anName));
  end;
end;

class function TSourceAnalyzer.FindSectionKind(const aLines: TArray<string>; const aLine: Integer): TGlobalVarKind;
var
  i: Integer;
  lText: string;
begin
  Result := gvkVar;
  for i := Min(aLine - 1, High(aLines)) downto 0 do
  begin
    lText := Trim(StripCommentPrefix(aLines[i]));
    if lText = '' then
    begin
      Continue;
    end;
    if SameText(lText, 'threadvar') then
    begin
      Exit(gvkThreadVar);
    end;
    if SameText(lText, 'var') then
    begin
      Exit(gvkVar);
    end;
    if MatchText(LowerCase(lText), ['const', 'type', 'implementation', 'interface']) then
    begin
      Break;
    end;
  end;
end;

class function TSourceAnalyzer.IsClassVarDeclaration(const aLines: TArray<string>; const aLine: Integer): Boolean;
var
  i: Integer;
  lText: string;
  lLowerText: string;
begin
  Result := False;
  for i := Min(aLine - 1, High(aLines)) downto 0 do
  begin
    lText := Trim(StripCommentPrefix(aLines[i]));
    if lText = '' then
    begin
      Continue;
    end;
    lLowerText := LowerCase(lText);
    if StartsText('class var', lLowerText) then
    begin
      Exit(True);
    end;
    if StartsText('class procedure', lLowerText)
      or StartsText('class function', lLowerText)
      or StartsText('procedure', lLowerText)
      or StartsText('function', lLowerText)
      or StartsText('constructor', lLowerText)
      or StartsText('destructor', lLowerText)
      or StartsText('property', lLowerText)
      or StartsText('private', lLowerText)
      or StartsText('protected', lLowerText)
      or StartsText('public', lLowerText)
      or StartsText('published', lLowerText)
      or StartsText('strict private', lLowerText)
      or StartsText('strict protected', lLowerText)
      or SameText(lLowerText, 'end') then
    begin
      Break;
    end;
  end;
end;

class function TSourceAnalyzer.IsTopLevelDeclarationNode(const aNode: TSyntaxNode): Boolean;
begin
  Result := Assigned(aNode)
    and not Assigned(FindAncestorNode(aNode.ParentNode, ntMethod))
    and not Assigned(FindAncestorNode(aNode.ParentNode, ntTypeDecl));
end;

class function TSourceAnalyzer.IsMethodImplementationNode(const aNode: TSyntaxNode): Boolean;
begin
  Result := Assigned(aNode) and Assigned(FindChildNode(aNode, ntStatements));
end;

class function TSourceAnalyzer.IsValidIdentifier(const aName: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if aName = '' then
  begin
    Exit;
  end;
  if not CharInSet(aName[1], ['A'..'Z', 'a'..'z', '_']) then
  begin
    Exit;
  end;
  for i := 2 to Length(aName) do
  begin
    if not IsIdentifierChar(aName[i]) then
    begin
      Exit;
    end;
  end;
  Result := True;
end;

class function TSourceAnalyzer.IsDescendantOf(const aNode, aAncestor: TSyntaxNode): Boolean;
var
  lNode: TSyntaxNode;
begin
  Result := False;
  lNode := aNode;
  while Assigned(lNode) do
  begin
    if lNode = aAncestor then
    begin
      Exit(True);
    end;
    lNode := lNode.ParentNode;
  end;
end;

class function TSourceAnalyzer.ResolveUnitPath(const aBaseDir, aUnitSpec: string): string;
var
  lSpec: string;
  lInPos: Integer;
  lQuoted: string;
  lUnitName: string;
begin
  lSpec := Trim(aUnitSpec);
  lInPos := Pos(' in ', LowerCase(lSpec));
  if lInPos > 0 then
  begin
    lQuoted := Trim(Copy(lSpec, lInPos + 4, MaxInt));
    if (Length(lQuoted) >= 2) and (lQuoted[1] = '''') and (lQuoted[Length(lQuoted)] = '''') then
    begin
      lQuoted := Copy(lQuoted, 2, Length(lQuoted) - 2);
    end;
    if TPath.IsPathRooted(lQuoted) then
    begin
      Exit(TPath.GetFullPath(lQuoted));
    end;
    Exit(TPath.GetFullPath(TPath.Combine(aBaseDir, lQuoted)));
  end;
  lUnitName := Trim(lSpec);
  if lUnitName.EndsWith(';') then
  begin
    lUnitName := lUnitName.Substring(0, lUnitName.Length - 1);
  end;
  Result := TPath.GetFullPath(TPath.Combine(aBaseDir, lUnitName + '.pas'));
end;

class function TSourceAnalyzer.TryExtractRoutineName(const aLine: string; out aName: string): Boolean;
var
  lWork: string;
  lKeywordEnd: Integer;
  lBracket: Integer;
  lSemi: Integer;
begin
  Result := False;
  aName := '';
  lWork := StripCommentPrefix(aLine);
  if not IsRoutineStart(lWork) then
  begin
    Exit;
  end;
  lWork := Trim(lWork);
  if StartsText('class procedure ', lWork) then
  begin
    lKeywordEnd := Length('class procedure ');
  end else if StartsText('class function ', lWork) then
  begin
    lKeywordEnd := Length('class function ');
  end else if StartsText('procedure ', lWork) then
  begin
    lKeywordEnd := Length('procedure ');
  end else if StartsText('function ', lWork) then
  begin
    lKeywordEnd := Length('function ');
  end else if StartsText('constructor ', lWork) then
  begin
    lKeywordEnd := Length('constructor ');
  end else if StartsText('destructor ', lWork) then
  begin
    lKeywordEnd := Length('destructor ');
  end else
  begin
    Exit;
  end;
  lWork := Trim(Copy(lWork, lKeywordEnd + 1, MaxInt));
  lBracket := Pos('(', lWork);
  lSemi := Pos(';', lWork);
  if (lSemi > 0) and ((lBracket = 0) or (lSemi < lBracket)) then
  begin
    lBracket := lSemi;
  end;
  if lBracket > 0 then
  begin
    lWork := Trim(Copy(lWork, 1, lBracket - 1));
  end;
  if lWork <> '' then
  begin
    aName := lWork;
    Result := True;
  end;
end;

class function TSourceAnalyzer.TryExtractDeclaration(const aLine: string; out aNames: TArray<string>; out aTypeName: string): Boolean;
var
  lText: string;
  lColon: Integer;
  lSemi: Integer;
begin
  Result := False;
  SetLength(aNames, 0);
  aTypeName := '';
  lText := StripCommentPrefix(aLine);
  if Pos('=', lText) > 0 then
  begin
    Exit;
  end;
  lColon := Pos(':', lText);
  lSemi := Pos(';', lText);
  if (lColon <= 1) or (lSemi <= lColon) then
  begin
    Exit;
  end;
  aNames := SplitIdentifierList(Copy(lText, 1, lColon - 1));
  aTypeName := Trim(Copy(lText, lColon + 1, lSemi - lColon - 1));
  Result := (Length(aNames) > 0) and (aTypeName <> '');
end;

class function TSourceAnalyzer.TryExtractTypedConst(const aLine: string; out aName: string; out aTypeName: string): Boolean;
var
  lText: string;
  lColon: Integer;
  lEquals: Integer;
  lSemi: Integer;
begin
  Result := False;
  aName := '';
  aTypeName := '';
  lText := StripCommentPrefix(aLine);
  lColon := Pos(':', lText);
  lEquals := Pos('=', lText);
  lSemi := Pos(';', lText);
  if (lColon <= 1) or (lEquals <= lColon) or (lSemi <= lEquals) then
  begin
    Exit;
  end;
  aName := Trim(Copy(lText, 1, lColon - 1));
  aTypeName := Trim(Copy(lText, lColon + 1, lEquals - lColon - 1));
  Result := (aName <> '') and (aTypeName <> '');
end;

class function TSourceAnalyzer.DetectAccess(const aLine, aSymbol: string): TAccessKind;
var
  lAssignPos: Integer;
  lSymbolPos: Integer;
  lUpperLine: string;
begin
  Result := akRead;
  lUpperLine := UpperCase(aLine);
  lAssignPos := Pos(':=', lUpperLine);
  lSymbolPos := FindWordPosition(lUpperLine, UpperCase(aSymbol));
  if (lAssignPos > 0) and (lSymbolPos > 0) then
  begin
    if lSymbolPos < lAssignPos then
    begin
      if PosEx(UpperCase(aSymbol), lUpperLine, lAssignPos + 2) > 0 then
      begin
        Result := akReadWrite;
      end else
      begin
        Result := akWrite;
      end;
    end else
    begin
      Result := akRead;
    end;
  end;
end;

class function TSourceAnalyzer.IsSectionKeyword(const aText: string): Boolean;
var
  lText: string;
begin
  lText := LowerCase(Trim(aText));
  Result := MatchText(lText, ['type', 'const', 'var', 'threadvar', 'implementation', 'interface', 'initialization', 'finalization']);
end;

class function TSourceAnalyzer.IsRoutineStart(const aText: string): Boolean;
var
  lText: string;
begin
  lText := Trim(LowerCase(aText));
  Result := StartsText('procedure ', lText)
    or StartsText('function ', lText)
    or StartsText('constructor ', lText)
    or StartsText('destructor ', lText)
    or StartsText('class procedure ', lText)
    or StartsText('class function ', lText);
end;

class function TSourceAnalyzer.ParseUsesUnits(const aText: string): TArray<string>;
var
  lList: TList<string>;
  lWork: string;
  lItem: string;
  lBuffer: string;
  lIndex: Integer;
  lDepth: Integer;
begin
  lList := TList<string>.Create;
  try
    lWork := StringReplace(aText, sLineBreak, ' ', [rfReplaceAll]);
    if StartsText('uses', TrimLeft(lWork)) then
    begin
      Delete(lWork, 1, Pos('uses', LowerCase(lWork)) + Length('uses') - 1);
    end;
    lBuffer := '';
    lDepth := 0;
    for lIndex := 1 to Length(lWork) do
    begin
      if lWork[lIndex] = '''' then
      begin
        if lDepth = 0 then
        begin
          lDepth := 1;
        end else
        begin
          lDepth := 0;
        end;
      end;
      if (lWork[lIndex] = ',') and (lDepth = 0) then
      begin
        lItem := Trim(lBuffer);
        if lItem <> '' then
        begin
          lList.Add(lItem);
        end;
        lBuffer := '';
      end else if lWork[lIndex] = ';' then
      begin
        Break;
      end else
      begin
        lBuffer := lBuffer + lWork[lIndex];
      end;
    end;
    lItem := Trim(lBuffer);
    if lItem <> '' then
    begin
      lList.Add(lItem);
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

class procedure TSourceAnalyzer.ParseUsesFromAst(const aUnit: TUnitInfo; const aSyntaxTree: TSyntaxNode);
var
  lUsesNodes: TList<TSyntaxNode>;
  lUsesNode: TSyntaxNode;
  lUnitNode: TSyntaxNode;
  lUnitName: string;
  lNames: TList<string>;
begin
  lUsesNodes := TList<TSyntaxNode>.Create;
  lNames := TList<string>.Create;
  try
    CollectNodes(aSyntaxTree, ntUses, lUsesNodes);
    for lUsesNode in lUsesNodes do
    begin
      for lUnitNode in lUsesNode.ChildNodes do
      begin
        if lUnitNode.Typ <> ntUnit then
        begin
          Continue;
        end;
        lUnitName := Trim(lUnitNode.GetAttribute(anName));
        if lUnitName <> '' then
        begin
          lNames.Add(lUnitName);
        end;
      end;
    end;
    aUnit.UsesUnits := lNames.ToArray;
  finally
    lNames.Free;
    lUsesNodes.Free;
  end;
end;

class procedure TSourceAnalyzer.ParseGlobalVarsFromAst(const aUnit: TUnitInfo; const aSyntaxTree: TSyntaxNode);
var
  lNodes: TList<TSyntaxNode>;
  lNode: TSyntaxNode;
  lNameNode: TSyntaxNode;
  lName: string;
  lTypeName: string;
  lSymbol: TGlobalVarSymbol;
begin
  lNodes := TList<TSyntaxNode>.Create;
  try
    CollectNodes(aSyntaxTree, ntVariable, lNodes);
    for lNode in lNodes do
    begin
      if not IsTopLevelDeclarationNode(lNode) then
      begin
        Continue;
      end;
      lNameNode := FindChildNode(lNode, ntName);
      lName := ExtractNodeName(lNameNode);
      if not IsValidIdentifier(lName) then
      begin
        Continue;
      end;
      lTypeName := ExtractTypeName(lNode);
      if lTypeName = '' then
      begin
        Continue;
      end;
      lSymbol := TGlobalVarSymbol.Create;
      lSymbol.Name := lName;
      lSymbol.UnitName := aUnit.UnitName;
      lSymbol.FileName := aUnit.FileName;
      lSymbol.Line := lNode.Line;
      lSymbol.Column := lNode.Col;
      lSymbol.TypeName := lTypeName;
      lSymbol.Kind := FindSectionKind(aUnit.Lines, lNode.Line);
      aUnit.Symbols.Add(lSymbol);
    end;
  finally
    lNodes.Free;
  end;
end;

class procedure TSourceAnalyzer.ParseClassVarsFromAst(const aUnit: TUnitInfo; const aSyntaxTree: TSyntaxNode);
var
  lNodes: TList<TSyntaxNode>;
  lNode: TSyntaxNode;
  lNameNode: TSyntaxNode;
  lName: string;
  lTypeName: string;
  lSymbol: TGlobalVarSymbol;
begin
  lNodes := TList<TSyntaxNode>.Create;
  try
    CollectNodes(aSyntaxTree, ntField, lNodes);
    for lNode in lNodes do
    begin
      if not IsClassVarDeclaration(aUnit.Lines, lNode.Line) then
      begin
        Continue;
      end;
      lNameNode := FindChildNode(lNode, ntName);
      lName := ExtractNodeName(lNameNode);
      if not IsValidIdentifier(lName) then
      begin
        Continue;
      end;
      lTypeName := ExtractTypeName(lNode);
      if lTypeName = '' then
      begin
        Continue;
      end;
      lSymbol := TGlobalVarSymbol.Create;
      lSymbol.Name := lName;
      lSymbol.UnitName := aUnit.UnitName;
      lSymbol.FileName := aUnit.FileName;
      lSymbol.Line := lNode.Line;
      lSymbol.Column := lNode.Col;
      lSymbol.TypeName := lTypeName;
      lSymbol.Kind := gvkClassVar;
      aUnit.Symbols.Add(lSymbol);
    end;
  finally
    lNodes.Free;
  end;
end;

class procedure TSourceAnalyzer.ParseTypedConstsFromLines(const aUnit: TUnitInfo; const aLines: TArray<string>);
var
  lIndex: Integer;
  lText: string;
  lName: string;
  lTypeName: string;
  lInsideConst: Boolean;
  lSymbol: TGlobalVarSymbol;
begin
  lInsideConst := False;
  for lIndex := 0 to High(aLines) do
  begin
    lText := StripCommentPrefix(aLines[lIndex]);
    if lText = '' then
    begin
      Continue;
    end;
    if SameText(Trim(lText), 'const') then
    begin
      lInsideConst := True;
      Continue;
    end;
    if lInsideConst and (IsSectionKeyword(lText) or IsRoutineStart(lText)) and not SameText(Trim(lText), 'const') then
    begin
      lInsideConst := False;
    end;
    if not lInsideConst then
    begin
      Continue;
    end;
    if TryExtractTypedConst(lText, lName, lTypeName) and IsValidIdentifier(lName) then
    begin
      lSymbol := TGlobalVarSymbol.Create;
      lSymbol.Name := lName;
      lSymbol.UnitName := aUnit.UnitName;
      lSymbol.FileName := aUnit.FileName;
      lSymbol.Line := lIndex + 1;
      lSymbol.Column := Pos(lName, aLines[lIndex]);
      lSymbol.TypeName := lTypeName;
      lSymbol.Kind := gvkTypedConst;
      aUnit.Symbols.Add(lSymbol);
    end;
  end;
end;

class procedure TSourceAnalyzer.CollectRoutineLocalNames(const aMethodNode: TSyntaxNode;
  const aLocalNames: TDictionary<string, Byte>);

  procedure CollectNames(const aNode: TSyntaxNode);
  var
    lChildNode: TSyntaxNode;
    lNameNode: TSyntaxNode;
    lName: string;
  begin
    if not Assigned(aNode) then
    begin
      Exit;
    end;
    if (aNode <> aMethodNode) and (aNode.Typ = ntMethod) then
    begin
      Exit;
    end;
    if aNode.Typ in [ntParameter, ntVariable] then
    begin
      lNameNode := FindChildNode(aNode, ntName);
      lName := ExtractNodeName(lNameNode);
      if IsValidIdentifier(lName) then
      begin
        aLocalNames.AddOrSetValue(NormalizeKey(lName), 1);
      end;
    end;
    for lChildNode in aNode.ChildNodes do
    begin
      CollectNames(lChildNode);
    end;
  end;

begin
  CollectNames(aMethodNode);
end;

class procedure TSourceAnalyzer.CollectRoutineUsages(const aMethodNode: TSyntaxNode; const aUsages: TList<TIdentifierUsage>);
var
  lStatementsNode: TSyntaxNode;

  function IdentifierAccess(const aIdentifierNode: TSyntaxNode): TAccessKind;
  var
    lAssignNode: TSyntaxNode;
    lLhsNode: TSyntaxNode;
  begin
    Result := akRead;
    lAssignNode := FindAncestorNode(aIdentifierNode, ntAssign);
    if not Assigned(lAssignNode) then
    begin
      Exit;
    end;
    lLhsNode := FindChildNode(lAssignNode, ntLHS);
    if Assigned(lLhsNode) and IsDescendantOf(aIdentifierNode, lLhsNode) then
    begin
      Result := akWrite;
    end;
  end;

  procedure CollectIdentifiers(const aNode: TSyntaxNode);
  var
    lChildNode: TSyntaxNode;
    lUsage: TIdentifierUsage;
  begin
    if not Assigned(aNode) then
    begin
      Exit;
    end;
    if aNode.Typ = ntIdentifier then
    begin
      lUsage.Name := Trim(aNode.GetAttribute(anName));
      if IsValidIdentifier(lUsage.Name) then
      begin
        lUsage.Line := aNode.Line;
        lUsage.Column := aNode.Col;
        lUsage.Access := IdentifierAccess(aNode);
        aUsages.Add(lUsage);
      end;
    end;
    for lChildNode in aNode.ChildNodes do
    begin
      CollectIdentifiers(lChildNode);
    end;
  end;

begin
  lStatementsNode := FindChildNode(aMethodNode, ntStatements);
  if Assigned(lStatementsNode) then
  begin
    CollectIdentifiers(lStatementsNode);
  end;
end;

class procedure TSourceAnalyzer.ParseRoutinesFromAst(const aUnit: TUnitInfo; const aSyntaxTree: TSyntaxNode);
var
  lNodes: TList<TSyntaxNode>;
  lNode: TSyntaxNode;
  lRoutine: TRoutineInfo;
  lName: string;
begin
  lNodes := TList<TSyntaxNode>.Create;
  try
    CollectNodes(aSyntaxTree, ntMethod, lNodes);
    for lNode in lNodes do
    begin
      if not IsMethodImplementationNode(lNode) then
      begin
        Continue;
      end;
      lName := ExtractNodeName(lNode);
      if lName = '' then
      begin
        Continue;
      end;
      lRoutine.UnitName := aUnit.UnitName;
      lRoutine.FileName := aUnit.FileName;
      lRoutine.Name := lName;
      lRoutine.StartLine := lNode.Line;
      if lNode is TCompoundSyntaxNode then
      begin
        lRoutine.EndLine := TCompoundSyntaxNode(lNode).EndLine;
      end else
      begin
        lRoutine.EndLine := lNode.Line;
      end;
      lRoutine.LocalNames := TDictionary<string, Byte>.Create;
      lRoutine.IdentifierUsages := TList<TIdentifierUsage>.Create;
      CollectRoutineLocalNames(lNode, lRoutine.LocalNames);
      CollectRoutineUsages(lNode, lRoutine.IdentifierUsages);
      aUnit.Routines.Add(lRoutine);
    end;
  finally
    lNodes.Free;
  end;
end;

class procedure TSourceAnalyzer.ParseGlobalVars(const aUnit: TUnitInfo; const aLines: TArray<string>);
var
  lIndex: Integer;
  lMode: TGlobalVarKind;
  lText: string;
  lNames: TArray<string>;
  lName: string;
  lTypeName: string;
  lTypedConstName: string;
  lInRoutine: Boolean;
  lSymbol: TGlobalVarSymbol;
begin
  lMode := gvkVar;
  lInRoutine := False;
  for lIndex := 0 to High(aLines) do
  begin
    lText := StripCommentPrefix(aLines[lIndex]);
    if lText = '' then
    begin
      Continue;
    end;
    if IsRoutineStart(lText) then
    begin
      lInRoutine := True;
    end;
    if lInRoutine then
    begin
      if SameText(Trim(lText), 'end;') then
      begin
        lInRoutine := False;
      end;
      Continue;
    end;
    if SameText(Trim(lText), 'var') then
    begin
      lMode := gvkVar;
      Continue;
    end;
    if SameText(Trim(lText), 'threadvar') then
    begin
      lMode := gvkThreadVar;
      Continue;
    end;
    if SameText(Trim(lText), 'const') then
    begin
      lMode := gvkTypedConst;
      Continue;
    end;
    if SameText(Trim(lText), 'type') or StartsText('type ', TrimLeft(LowerCase(lText))) then
    begin
      Continue;
    end;
    if StartsText('class var', TrimLeft(LowerCase(lText))) then
    begin
      Continue;
    end;

    if (lMode in [gvkVar, gvkThreadVar]) and TryExtractDeclaration(lText, lNames, lTypeName) then
    begin
      for lName in lNames do
      begin
        lSymbol := TGlobalVarSymbol.Create;
        lSymbol.Name := lName;
        lSymbol.UnitName := aUnit.UnitName;
        lSymbol.FileName := aUnit.FileName;
        lSymbol.Line := lIndex + 1;
        lSymbol.Column := Pos(lName, aLines[lIndex]);
        lSymbol.TypeName := lTypeName;
        lSymbol.Kind := lMode;
        aUnit.Symbols.Add(lSymbol);
      end;
      Continue;
    end;

    if (lMode = gvkTypedConst) and TryExtractTypedConst(lText, lTypedConstName, lTypeName) then
    begin
      lSymbol := TGlobalVarSymbol.Create;
      lSymbol.Name := lTypedConstName;
      lSymbol.UnitName := aUnit.UnitName;
      lSymbol.FileName := aUnit.FileName;
      lSymbol.Line := lIndex + 1;
      lSymbol.Column := Pos(lTypedConstName, aLines[lIndex]);
      lSymbol.TypeName := lTypeName;
      lSymbol.Kind := gvkTypedConst;
      aUnit.Symbols.Add(lSymbol);
    end;
  end;
end;

class procedure TSourceAnalyzer.ParseClassVars(const aUnit: TUnitInfo; const aLines: TArray<string>);
var
  lIndex: Integer;
  lText: string;
  lInsideClassVar: Boolean;
  lNames: TArray<string>;
  lName: string;
  lTypeName: string;
  lSymbol: TGlobalVarSymbol;
begin
  lInsideClassVar := False;
  for lIndex := 0 to High(aLines) do
  begin
    lText := StripCommentPrefix(aLines[lIndex]);
    if lText = '' then
    begin
      Continue;
    end;
    if StartsText('class var', TrimLeft(LowerCase(lText))) then
    begin
      lInsideClassVar := True;
      lText := Trim(Copy(lText, Length('class var') + 1, MaxInt));
      if TryExtractDeclaration(lText, lNames, lTypeName) then
      begin
        for lName in lNames do
        begin
          lSymbol := TGlobalVarSymbol.Create;
          lSymbol.Name := lName;
          lSymbol.UnitName := aUnit.UnitName;
          lSymbol.FileName := aUnit.FileName;
          lSymbol.Line := lIndex + 1;
          lSymbol.Column := Pos(lName, aLines[lIndex]);
          lSymbol.TypeName := lTypeName;
          lSymbol.Kind := gvkClassVar;
          aUnit.Symbols.Add(lSymbol);
        end;
        lInsideClassVar := False;
      end;
      Continue;
    end;
    if lInsideClassVar then
    begin
      if TryExtractDeclaration(lText, lNames, lTypeName) then
      begin
        for lName in lNames do
        begin
          lSymbol := TGlobalVarSymbol.Create;
          lSymbol.Name := lName;
          lSymbol.UnitName := aUnit.UnitName;
          lSymbol.FileName := aUnit.FileName;
          lSymbol.Line := lIndex + 1;
          lSymbol.Column := Pos(lName, aLines[lIndex]);
          lSymbol.TypeName := lTypeName;
          lSymbol.Kind := gvkClassVar;
          aUnit.Symbols.Add(lSymbol);
        end;
      end else if IsSectionKeyword(lText) or StartsText('strict ', TrimLeft(LowerCase(lText))) or StartsText('public', TrimLeft(LowerCase(lText))) or StartsText('private', TrimLeft(LowerCase(lText))) or StartsText('protected', TrimLeft(LowerCase(lText))) or StartsText('published', TrimLeft(LowerCase(lText))) then
      begin
        lInsideClassVar := False;
      end;
    end;
  end;
end;

class procedure TSourceAnalyzer.ParseRoutines(const aUnit: TUnitInfo; const aLines: TArray<string>);
var
  lIndex: Integer;
  lText: string;
  lName: string;
  lRoutine: TRoutineInfo;
  lNestLevel: Integer;
  lHeaderDone: Boolean;
  lBeginCount: Integer;
  lEndCount: Integer;
  lLocalLine: string;
  lNames: TArray<string>;
  lParamsStart: Integer;
  lParamsEnd: Integer;
  lParams: string;
  lParamItems: TArray<string>;
  lParamItem: string;
  lParamNames: TArray<string>;
  lParamName: string;
  lTypeName: string;
begin
  lIndex := 0;
  while lIndex <= High(aLines) do
  begin
    lText := StripCommentPrefix(aLines[lIndex]);
    if TryExtractRoutineName(lText, lName) then
    begin
      lRoutine.UnitName := aUnit.UnitName;
      lRoutine.FileName := aUnit.FileName;
      lRoutine.Name := lName;
      lRoutine.StartLine := lIndex + 1;
      lRoutine.EndLine := lIndex + 1;
      lRoutine.LocalNames := TDictionary<string, Byte>.Create;
      lParamsStart := Pos('(', aLines[lIndex]);
      lParamsEnd := LastDelimiter(')', aLines[lIndex]);
      if (lParamsStart > 0) and (lParamsEnd > lParamsStart) then
      begin
        lParams := Copy(aLines[lIndex], lParamsStart + 1, lParamsEnd - lParamsStart - 1);
        lParamItems := lParams.Split([';']);
        for lParamItem in lParamItems do
        begin
          if TryExtractDeclaration(Trim(lParamItem) + ';', lParamNames, lTypeName) then
          begin
            for lParamName in lParamNames do
            begin
              lRoutine.LocalNames.AddOrSetValue(NormalizeKey(lParamName), 1);
            end;
          end;
        end;
      end;

      lNestLevel := 0;
      lHeaderDone := False;
      Inc(lIndex);
      while lIndex <= High(aLines) do
      begin
        lLocalLine := StripCommentPrefix(aLines[lIndex]);
        if not lHeaderDone then
        begin
          if SameText(Trim(lLocalLine), 'var') then
          begin
            Inc(lIndex);
            while lIndex <= High(aLines) do
            begin
              lLocalLine := StripCommentPrefix(aLines[lIndex]);
              if TryExtractDeclaration(lLocalLine, lNames, lTypeName) then
              begin
                for lParamName in lNames do
                begin
                  lRoutine.LocalNames.AddOrSetValue(NormalizeKey(lParamName), 1);
                end;
                Inc(lIndex);
                Continue;
              end;
              Break;
            end;
            Continue;
          end;
          if Pos('begin', LowerCase(lLocalLine)) > 0 then
          begin
            lHeaderDone := True;
            lBeginCount := CountOccurrences(LowerCase(lLocalLine), 'begin');
            lEndCount := CountOccurrences(LowerCase(lLocalLine), 'end');
            lNestLevel := lNestLevel + lBeginCount - lEndCount;
          end;
        end else
        begin
          lBeginCount := CountOccurrences(LowerCase(lLocalLine), 'begin');
          lEndCount := CountOccurrences(LowerCase(lLocalLine), 'end');
          lNestLevel := lNestLevel + lBeginCount - lEndCount;
          if (lNestLevel <= 0) and EndsText(';', Trim(lLocalLine)) then
          begin
            lRoutine.EndLine := lIndex + 1;
            Break;
          end;
        end;
        Inc(lIndex);
      end;
      if lRoutine.EndLine < lRoutine.StartLine then
      begin
        lRoutine.EndLine := lRoutine.StartLine;
      end;
      aUnit.Routines.Add(lRoutine);
      Continue;
    end;
    Inc(lIndex);
  end;
end;

procedure TSourceAnalyzer.ResolveUsages(const aUnit: TUnitInfo);
var
  lRoutine: TRoutineInfo;
  lRef: TGlobalVarRef;
  lUsage: TIdentifierUsage;
  lUsesUnit: string;
  lCanSeeSymbol: Boolean;
  lSymbol: TGlobalVarSymbol;
  lCandidates: TList<TGlobalVarSymbol>;
  lCandidateText: string;
  lAmbiguity: TGlobalVarAmbiguity;
begin
  lCandidates := TList<TGlobalVarSymbol>.Create;
  for lRoutine in aUnit.Routines do
  begin
    for lUsage in lRoutine.IdentifierUsages do
    begin
      if lRoutine.LocalNames.ContainsKey(NormalizeKey(lUsage.Name)) then
      begin
        Continue;
      end;
      lCandidates.Clear;
      for lSymbol in fSymbols do
      begin
        if not SameText(lUsage.Name, lSymbol.Name) then
        begin
          Continue;
        end;
        lCanSeeSymbol := SameText(lRoutine.UnitName, lSymbol.UnitName);
        if not lCanSeeSymbol then
        begin
          for lUsesUnit in aUnit.UsesUnits do
          begin
            if SameText(lUsesUnit, lSymbol.UnitName) then
            begin
              lCanSeeSymbol := True;
              Break;
            end;
          end;
        end;
        if not lCanSeeSymbol then
        begin
          Continue;
        end;
        lCandidates.Add(lSymbol);
      end;
      if lCandidates.Count = 1 then
      begin
        lRef.UnitName := lRoutine.UnitName;
        lRef.RoutineName := lRoutine.Name;
        lRef.FileName := lRoutine.FileName;
        lRef.Line := lUsage.Line;
        lRef.Column := lUsage.Column;
        lRef.Access := lUsage.Access;
        lCandidates[0].UsedBy.Add(lRef);
      end else if lCandidates.Count > 1 then
      begin
        lCandidateText := '';
        for lSymbol in lCandidates do
        begin
          if lCandidateText <> '' then
          begin
            lCandidateText := lCandidateText + '; ';
          end;
          lCandidateText := lCandidateText + lSymbol.UnitName + '.' + lSymbol.Name;
        end;
        lAmbiguity.Name := lUsage.Name;
        lAmbiguity.UnitName := lRoutine.UnitName;
        lAmbiguity.RoutineName := lRoutine.Name;
        lAmbiguity.FileName := lRoutine.FileName;
        lAmbiguity.Line := lUsage.Line;
        lAmbiguity.Column := lUsage.Column;
        lAmbiguity.Access := lUsage.Access;
        lAmbiguity.Candidates := lCandidateText;
        fAmbiguities.Add(lAmbiguity);
      end;
    end;
  end;
  lCandidates.Free;
end;

function TSourceAnalyzer.ParseUnit(const aFileName: string; const aSyntaxTree: TSyntaxNode): TUnitInfo;
var
  lLines: TArray<string>;
  lUnitName: string;
  lSymbol: TGlobalVarSymbol;
begin
  lLines := TFile.ReadAllLines(aFileName);
  Result := TUnitInfo.Create;
  Result.FileName := aFileName;
  Result.Lines := Copy(lLines);
  lUnitName := TPath.GetFileNameWithoutExtension(aFileName);
  Result.UnitName := lUnitName;
  if Assigned(aSyntaxTree) then
  begin
    ParseUsesFromAst(Result, aSyntaxTree);
    ParseGlobalVarsFromAst(Result, aSyntaxTree);
    ParseTypedConstsFromLines(Result, lLines);
    ParseClassVars(Result, lLines);
    ParseRoutinesFromAst(Result, aSyntaxTree);
  end else
  begin
    ParseGlobalVars(Result, lLines);
    ParseClassVars(Result, lLines);
    ParseRoutines(Result, lLines);
  end;
  for lSymbol in Result.Symbols do
  begin
    fSymbols.Add(lSymbol);
  end;
end;

procedure TSourceAnalyzer.LoadUnitRecursive(const aFileName: string);
begin
  // Retained only as a fallback path. Project traversal now uses DelphiAST.ProjectIndexer.
  if not TFile.Exists(aFileName) then
  begin
    Exit;
  end;
  if not fVisitedFiles.ContainsKey(NormalizeKey(TPath.GetFullPath(aFileName))) then
  begin
    fVisitedFiles.Add(NormalizeKey(TPath.GetFullPath(aFileName)), 1);
    fUnitsByName.AddOrSetValue(NormalizeKey(TPath.GetFileNameWithoutExtension(aFileName)), ParseUnit(TPath.GetFullPath(aFileName)));
  end;
end;

procedure TSourceAnalyzer.LoadIndexedUnits;
var
  lIndexer: TProjectIndexer;
  lIndexedUnit: TProjectIndexer.TUnitInfo;
  lFullName: string;
  lUnitInfo: TUnitInfo;
begin
  lIndexer := TProjectIndexer.Create;
  try
    lIndexer.Defines := fProject.ParserDefines;
    lIndexer.SearchPath := fProject.ParserSearchPath;
    lIndexer.Index(fProject.MainSourcePath);
    for lIndexedUnit in lIndexer.ParsedUnits do
    begin
      lFullName := Trim(lIndexedUnit.Path);
      if lFullName = '' then
      begin
        Continue;
      end;
      lFullName := TPath.GetFullPath(lFullName);
      if not TFile.Exists(lFullName) then
      begin
        Continue;
      end;
      if fVisitedFiles.ContainsKey(NormalizeKey(lFullName)) then
      begin
        Continue;
      end;
      fVisitedFiles.Add(NormalizeKey(lFullName), 1);
      lUnitInfo := ParseUnit(lFullName, lIndexedUnit.SyntaxTree);
      fUnitsByName.AddOrSetValue(NormalizeKey(lUnitInfo.UnitName), lUnitInfo);
    end;
  finally
    lIndexer.Free;
  end;
end;

class function TSourceAnalyzer.BuildInputHash(const aProjectPath: string; const aFiles: TArray<string>): string;
var
  lBuilder: TStringBuilder;
  lFiles: TStringList;
  lFileName: string;
  lIndex: Integer;
begin
  lFiles := TStringList.Create;
  lBuilder := TStringBuilder.Create;
  try
    lFiles.CaseSensitive := False;
    lFiles.Sorted := True;
    lFiles.Duplicates := dupIgnore;
    for lIndex := 0 to High(aFiles) do
    begin
      lFiles.Add(aFiles[lIndex]);
    end;
    lBuilder.AppendLine(TPath.GetFullPath(aProjectPath));
    for lIndex := 0 to lFiles.Count - 1 do
    begin
      lFileName := lFiles[lIndex];
      lBuilder.AppendLine(lFileName);
      lBuilder.AppendLine(DateTimeToStr(TFile.GetLastWriteTimeUtc(lFileName)));
      lBuilder.AppendLine(IntToStr(TFile.GetSize(lFileName)));
    end;
    Result := THashSHA2.GetHashString(lBuilder.ToString);
  finally
    lBuilder.Free;
    lFiles.Free;
  end;
end;

class function TSourceAnalyzer.AccessToText(const aAccess: TAccessKind): string;
begin
  case aAccess of
    akRead:
      Result := 'read';
    akWrite:
      Result := 'write';
  else
    Result := 'readwrite';
  end;
end;

class function TSourceAnalyzer.KindToText(const aKind: TGlobalVarKind): string;
begin
  case aKind of
    gvkVar:
      Result := 'var';
    gvkThreadVar:
      Result := 'threadvar';
    gvkTypedConst:
      Result := 'typedconst';
  else
    Result := 'classvar';
  end;
end;

function TSourceAnalyzer.Analyze(out aInputHash: string): TObjectList<TGlobalVarSymbol>;
var
  lFiles: TArray<string>;
  lIndex: Integer;
  lPair: TPair<string, Byte>;
  lUnitPair: TPair<string, TUnitInfo>;
begin
  LoadIndexedUnits;
  for lUnitPair in fUnitsByName do
  begin
    ResolveUsages(lUnitPair.Value);
  end;
  SetLength(lFiles, fVisitedFiles.Count);
  lIndex := 0;
  for lPair in fVisitedFiles do
  begin
    lFiles[lIndex] := lPair.Key;
    Inc(lIndex);
  end;
  aInputHash := BuildInputHash(fProject.ProjectPath, lFiles);
  Result := fSymbols;
end;

function TSourceAnalyzer.GetVisitedFiles: TArray<string>;
var
  lPair: TPair<string, Byte>;
  lIndex: Integer;
begin
  SetLength(Result, fVisitedFiles.Count);
  lIndex := 0;
  for lPair in fVisitedFiles do
  begin
    Result[lIndex] := lPair.Key;
    Inc(lIndex);
  end;
end;

function BuildProjectInfo(const aOptions: TAppOptions): TProjectInfo;
var
  lEnvVars: TDictionary<string, string>;
  lError: string;
  lErrorCode: Integer;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lParams: TFixInsightParams;
  lProjectPath: string;
  lProjectDir: string;
  lProjectName: string;
  lDakRoot: string;
  lDelphiVersion: string;
  lBuildOptions: TAppOptions;
begin
  lProjectPath := TPath.GetFullPath(aOptions.fDprojPath);
  lProjectDir := TPath.GetDirectoryName(lProjectPath);
  lProjectName := TPath.GetFileNameWithoutExtension(lProjectPath);
  lDakRoot := TPath.Combine(TPath.Combine(lProjectDir, '.dak'), lProjectName);
  Result.ProjectPath := lProjectPath;
  Result.ProjectName := lProjectName;
  Result.MainSourcePath := TSourceAnalyzer.ExtractProjectEntryPoint(lProjectPath);
  Result.ParserDefines := '';
  Result.ParserSearchPath := lProjectDir;
  lDelphiVersion := Trim(aOptions.fDelphiVersion);
  if lDelphiVersion = '' then
  begin
    if not LoadDefaultDelphiVersion(lProjectPath, lDelphiVersion) then
    begin
      lDelphiVersion := '';
    end;
  end;
  if (lDelphiVersion <> '') and (Pos('.', lDelphiVersion) = 0) then
  begin
    lDelphiVersion := lDelphiVersion + '.0';
  end;
  if lDelphiVersion <> '' then
  begin
    if TryLoadRsVars(lDelphiVersion, aOptions.fRsVarsPath, nil, lError) then
    begin
      if TryReadIdeConfig(lDelphiVersion, aOptions.fPlatform, aOptions.fEnvOptionsPath, lEnvVars, lLibraryPath,
        lLibrarySource, nil, lError) then
      begin
        try
          lBuildOptions := aOptions;
          lBuildOptions.fDelphiVersion := lDelphiVersion;
          if TryBuildParams(lBuildOptions, lEnvVars, lLibraryPath, lLibrarySource, nil, lParams, lError, lErrorCode) then
          begin
            Result.MainSourcePath := lParams.fProjectDpr;
            Result.ParserDefines := String.Join(';', lParams.fDefines);
            Result.ParserSearchPath := String.Join(';', lParams.fUnitSearchPath);
            if Result.ParserSearchPath = '' then
            begin
              Result.ParserSearchPath := lProjectDir;
            end else
            begin
              Result.ParserSearchPath := Result.ParserSearchPath + ';' + lProjectDir;
            end;
          end;
        finally
          lEnvVars.Free;
        end;
      end;
    end;
  end;
  Result.OutputPath := TPath.Combine(lDakRoot, 'global-vars');
  Result.CachePath := TPath.Combine(Result.OutputPath, 'cache');
  Result.ReportsPath := TPath.Combine(Result.OutputPath, 'reports');
  Result.TempPath := TPath.Combine(Result.OutputPath, 'tmp');
end;

procedure EnsureProjectFolders(const aProject: TProjectInfo);
begin
  TDirectory.CreateDirectory(aProject.CachePath);
  TDirectory.CreateDirectory(aProject.ReportsPath);
  TDirectory.CreateDirectory(aProject.TempPath);
end;

function CacheFileName(const aProject: TProjectInfo; const aOptions: TAppOptions): string;
begin
  if aOptions.fHasGlobalVarsCachePath and (Trim(aOptions.fGlobalVarsCachePath) <> '') then
  begin
    Result := aOptions.fGlobalVarsCachePath;
  end else
  begin
    Result := TPath.Combine(aProject.CachePath, 'global-vars-cache.sqlite3');
  end;
end;

function FileStampUtc(const aFileName: string): string;
begin
  Result := FormatDateTime('yyyymmddhhnnsszzz', TFile.GetLastWriteTimeUtc(aFileName));
end;

procedure EnsureCacheSchema(const aConnection: TFDConnection);
begin
  aConnection.ExecSQL('create table if not exists meta (key_name text primary key, value_text text not null)');
  aConnection.ExecSQL('create table if not exists files (path text primary key, stamp_utc text not null, size_bytes integer not null)');
  aConnection.ExecSQL('create table if not exists symbols (' +
    'id integer primary key autoincrement, unit_name text not null, file_name text not null, name text not null, ' +
    'type_name text not null, kind text not null, line_no integer not null, col_no integer not null)');
  aConnection.ExecSQL('create table if not exists refs (' +
    'symbol_id integer not null, unit_name text not null, routine_name text not null, file_name text not null, ' +
    'line_no integer not null, col_no integer not null, access_kind text not null)');
  aConnection.ExecSQL('create table if not exists ambiguities (' +
    'name text not null, unit_name text not null, routine_name text not null, file_name text not null, ' +
    'line_no integer not null, col_no integer not null, access_kind text not null, candidates text not null)');
end;

procedure OpenCacheConnection(const aCacheFileName: string; out aDriverLink: TFDPhysSQLiteDriverLink;
  out aConnection: TFDConnection);
begin
  aDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  aConnection := TFDConnection.Create(nil);
  aConnection.LoginPrompt := False;
  aConnection.Params.Values['DriverID'] := 'SQLite';
  aConnection.Params.Values['Database'] := aCacheFileName;
  aConnection.Params.Values['LockingMode'] := 'Normal';
  aConnection.Params.Values['OpenMode'] := 'CreateUTF8';
  aConnection.Connected := True;
end;

procedure SaveCachedSymbols(const aCacheFileName, aProjectPath, aInputHash: string; const aFiles: TArray<string>;
  const aSymbols: TObjectList<TGlobalVarSymbol>; const aAmbiguities: TList<TGlobalVarAmbiguity>);
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lFileName: string;
  lSymbol: TGlobalVarSymbol;
  lRef: TGlobalVarRef;
  lAmbiguity: TGlobalVarAmbiguity;
  lSymbolId: Int64;
begin
  TDirectory.CreateDirectory(TPath.GetDirectoryName(aCacheFileName));
  OpenCacheConnection(aCacheFileName, lDriverLink, lConnection);
  try
    EnsureCacheSchema(lConnection);
    lConnection.StartTransaction;
    try
      lConnection.ExecSQL('delete from meta');
      lConnection.ExecSQL('delete from files');
      lConnection.ExecSQL('delete from refs');
      lConnection.ExecSQL('delete from symbols');
      lConnection.ExecSQL('delete from ambiguities');
      lConnection.ExecSQL('insert into meta(key_name, value_text) values (?, ?)', ['schema_version', '1']);
      lConnection.ExecSQL('insert into meta(key_name, value_text) values (?, ?)', ['project_path', TPath.GetFullPath(aProjectPath)]);
      lConnection.ExecSQL('insert into meta(key_name, value_text) values (?, ?)', ['input_hash', aInputHash]);
      lConnection.ExecSQL('insert into files(path, stamp_utc, size_bytes) values (?, ?, ?)',
        [TPath.GetFullPath(aProjectPath), FileStampUtc(aProjectPath), TFile.GetSize(aProjectPath)]);
      for lFileName in aFiles do
      begin
        lConnection.ExecSQL('insert or replace into files(path, stamp_utc, size_bytes) values (?, ?, ?)',
          [TPath.GetFullPath(lFileName), FileStampUtc(lFileName), TFile.GetSize(lFileName)]);
      end;
      for lSymbol in aSymbols do
      begin
        lConnection.ExecSQL('insert into symbols(unit_name, file_name, name, type_name, kind, line_no, col_no) values (?, ?, ?, ?, ?, ?, ?)',
          [lSymbol.UnitName, lSymbol.FileName, lSymbol.Name, lSymbol.TypeName, TSourceAnalyzer.KindToText(lSymbol.Kind),
          lSymbol.Line, lSymbol.Column]);
        lSymbolId := lConnection.ExecSQLScalar('select last_insert_rowid()');
        for lRef in lSymbol.UsedBy do
        begin
          lConnection.ExecSQL('insert into refs(symbol_id, unit_name, routine_name, file_name, line_no, col_no, access_kind) values (?, ?, ?, ?, ?, ?, ?)',
            [lSymbolId, lRef.UnitName, lRef.RoutineName, lRef.FileName, lRef.Line, lRef.Column,
            TSourceAnalyzer.AccessToText(lRef.Access)]);
        end;
      end;
      for lAmbiguity in aAmbiguities do
      begin
        lConnection.ExecSQL('insert into ambiguities(name, unit_name, routine_name, file_name, line_no, col_no, access_kind, candidates) values (?, ?, ?, ?, ?, ?, ?, ?)',
          [lAmbiguity.Name, lAmbiguity.UnitName, lAmbiguity.RoutineName, lAmbiguity.FileName, lAmbiguity.Line,
          lAmbiguity.Column, TSourceAnalyzer.AccessToText(lAmbiguity.Access), lAmbiguity.Candidates]);
      end;
      lConnection.Commit;
    except
      lConnection.Rollback;
      raise;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TryLoadCachedSymbols(const aCacheFileName, aProjectPath: string; out aSymbols: TObjectList<TGlobalVarSymbol>;
  out aAmbiguities: TList<TGlobalVarAmbiguity>): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lQuery: TFDQuery;
  lExpected: string;
  lSymbolById: TDictionary<Int64, TGlobalVarSymbol>;
  lSymbol: TGlobalVarSymbol;
  lRef: TGlobalVarRef;
  lAmbiguity: TGlobalVarAmbiguity;
begin
  Result := False;
  aSymbols := nil;
  aAmbiguities := nil;
  if not TFile.Exists(aCacheFileName) then
  begin
    Exit;
  end;
  OpenCacheConnection(aCacheFileName, lDriverLink, lConnection);
  lSymbolById := TDictionary<Int64, TGlobalVarSymbol>.Create;
  lQuery := TFDQuery.Create(nil);
  try
    lQuery.Connection := lConnection;
    lExpected := VarToStr(lConnection.ExecSQLScalar('select value_text from meta where key_name = ?', ['project_path']));
    if not SameText(TPath.GetFullPath(aProjectPath), lExpected) then
    begin
      Exit;
    end;
    lQuery.SQL.Text := 'select path, stamp_utc, size_bytes from files';
    lQuery.Open;
    while not lQuery.Eof do
    begin
      if (not TFile.Exists(lQuery.Fields[0].AsString))
        or (FileStampUtc(lQuery.Fields[0].AsString) <> lQuery.Fields[1].AsString)
        or (TFile.GetSize(lQuery.Fields[0].AsString) <> lQuery.Fields[2].AsLargeInt) then
      begin
        Exit;
      end;
      lQuery.Next;
    end;
    aSymbols := TObjectList<TGlobalVarSymbol>.Create(True);
    aAmbiguities := TList<TGlobalVarAmbiguity>.Create;
    lQuery.Close;
    lQuery.SQL.Text := 'select id, unit_name, file_name, name, type_name, kind, line_no, col_no from symbols order by id';
    lQuery.Open;
    while not lQuery.Eof do
    begin
      lSymbol := TGlobalVarSymbol.Create;
      lSymbol.UnitName := lQuery.FieldByName('unit_name').AsString;
      lSymbol.FileName := lQuery.FieldByName('file_name').AsString;
      lSymbol.Name := lQuery.FieldByName('name').AsString;
      lSymbol.TypeName := lQuery.FieldByName('type_name').AsString;
      lSymbol.Line := lQuery.FieldByName('line_no').AsInteger;
      lSymbol.Column := lQuery.FieldByName('col_no').AsInteger;
      if SameText(lQuery.FieldByName('kind').AsString, 'threadvar') then
        lSymbol.Kind := gvkThreadVar
      else if SameText(lQuery.FieldByName('kind').AsString, 'typedconst') then
        lSymbol.Kind := gvkTypedConst
      else if SameText(lQuery.FieldByName('kind').AsString, 'classvar') then
        lSymbol.Kind := gvkClassVar
      else
        lSymbol.Kind := gvkVar;
      aSymbols.Add(lSymbol);
      lSymbolById.Add(lQuery.FieldByName('id').AsLargeInt, lSymbol);
      lQuery.Next;
    end;
    lQuery.Close;
    lQuery.SQL.Text := 'select symbol_id, unit_name, routine_name, file_name, line_no, col_no, access_kind from refs order by symbol_id, line_no, col_no';
    lQuery.Open;
    while not lQuery.Eof do
    begin
      if lSymbolById.TryGetValue(lQuery.FieldByName('symbol_id').AsLargeInt, lSymbol) then
      begin
        lRef.UnitName := lQuery.FieldByName('unit_name').AsString;
        lRef.RoutineName := lQuery.FieldByName('routine_name').AsString;
        lRef.FileName := lQuery.FieldByName('file_name').AsString;
        lRef.Line := lQuery.FieldByName('line_no').AsInteger;
        lRef.Column := lQuery.FieldByName('col_no').AsInteger;
        if SameText(lQuery.FieldByName('access_kind').AsString, 'write') then
          lRef.Access := akWrite
        else if SameText(lQuery.FieldByName('access_kind').AsString, 'readwrite') then
          lRef.Access := akReadWrite
        else
          lRef.Access := akRead;
        lSymbol.UsedBy.Add(lRef);
      end;
      lQuery.Next;
    end;
    lQuery.Close;
    lQuery.SQL.Text := 'select name, unit_name, routine_name, file_name, line_no, col_no, access_kind, candidates from ambiguities order by file_name, line_no, col_no';
    lQuery.Open;
    while not lQuery.Eof do
    begin
      lAmbiguity.Name := lQuery.FieldByName('name').AsString;
      lAmbiguity.UnitName := lQuery.FieldByName('unit_name').AsString;
      lAmbiguity.RoutineName := lQuery.FieldByName('routine_name').AsString;
      lAmbiguity.FileName := lQuery.FieldByName('file_name').AsString;
      lAmbiguity.Line := lQuery.FieldByName('line_no').AsInteger;
      lAmbiguity.Column := lQuery.FieldByName('col_no').AsInteger;
      if SameText(lQuery.FieldByName('access_kind').AsString, 'write') then
        lAmbiguity.Access := akWrite
      else if SameText(lQuery.FieldByName('access_kind').AsString, 'readwrite') then
        lAmbiguity.Access := akReadWrite
      else
        lAmbiguity.Access := akRead;
      lAmbiguity.Candidates := lQuery.FieldByName('candidates').AsString;
      aAmbiguities.Add(lAmbiguity);
      lQuery.Next;
    end;
    Result := True;
  finally
    if not Result then
    begin
      aSymbols.Free;
      aSymbols := nil;
      aAmbiguities.Free;
      aAmbiguities := nil;
    end;
    lQuery.Free;
    lSymbolById.Free;
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function MatchPatternText(const aValue, aPattern: string): Boolean;
var
  lMask: string;
begin
  lMask := aPattern;
  if (Pos('*', lMask) = 0) and (Pos('?', lMask) = 0) then
  begin
    lMask := '*' + lMask + '*';
  end;
  Result := MatchesMask(UpperCase(aValue), UpperCase(lMask));
end;

function RefMatchesAccess(const aRef: TGlobalVarRef; const aOptions: TAppOptions): Boolean;
begin
  if aOptions.fGlobalVarsReadsOnly then
  begin
    Exit(aRef.Access in [akRead, akReadWrite]);
  end;
  if aOptions.fGlobalVarsWritesOnly then
  begin
    Exit(aRef.Access in [akWrite, akReadWrite]);
  end;
  Result := True;
end;

function SymbolMatchesFilters(const aSymbol: TGlobalVarSymbol; const aOptions: TAppOptions): Boolean;
var
  lRef: TGlobalVarRef;
begin
  Result := True;
  if aOptions.fHasGlobalVarsUnitFilter and not MatchPatternText(aSymbol.UnitName, aOptions.fGlobalVarsUnitFilter) then
  begin
    Exit(False);
  end;
  if aOptions.fHasGlobalVarsNameFilter and not MatchPatternText(aSymbol.Name, aOptions.fGlobalVarsNameFilter) then
  begin
    Exit(False);
  end;
  if aOptions.fGlobalVarsUnusedOnly then
  begin
    Exit(aSymbol.UsedBy.Count = 0);
  end;
  if aOptions.fGlobalVarsReadsOnly or aOptions.fGlobalVarsWritesOnly then
  begin
    for lRef in aSymbol.UsedBy do
    begin
      if RefMatchesAccess(lRef, aOptions) then
      begin
        Exit(True);
      end;
    end;
    Exit(False);
  end;
end;

function GlobalVarsFilterText(const aOptions: TAppOptions): string;
var
  lParts: TStringList;
begin
  lParts := TStringList.Create;
  try
    if aOptions.fGlobalVarsUnusedOnly then
      lParts.Add('unused-only');
    if aOptions.fGlobalVarsReadsOnly then
      lParts.Add('reads-only');
    if aOptions.fGlobalVarsWritesOnly then
      lParts.Add('writes-only');
    if aOptions.fHasGlobalVarsUnitFilter then
      lParts.Add('unit=' + aOptions.fGlobalVarsUnitFilter);
    if aOptions.fHasGlobalVarsNameFilter then
      lParts.Add('name=' + aOptions.fGlobalVarsNameFilter);
    if lParts.Count = 0 then
      Result := 'all'
    else
    begin
      Result := StringReplace(Trim(lParts.Text), sLineBreak, ';', [rfReplaceAll]);
      if Result.EndsWith(';') then
      begin
        Delete(Result, Length(Result), 1);
      end;
    end;
  finally
    lParts.Free;
  end;
end;

function CountUnusedSymbols(const aSymbols: TObjectList<TGlobalVarSymbol>): Integer;
var
  lSymbol: TGlobalVarSymbol;
begin
  Result := 0;
  for lSymbol in aSymbols do
  begin
    if lSymbol.UsedBy.Count = 0 then
    begin
      Inc(Result);
    end;
  end;
end;

function BuildFilteredSymbols(const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aOptions: TAppOptions): TObjectList<TGlobalVarSymbol>;
var
  lSymbol: TGlobalVarSymbol;
begin
  Result := TObjectList<TGlobalVarSymbol>.Create(False);
  for lSymbol in aSymbols do
  begin
    if not SymbolMatchesFilters(lSymbol, aOptions) then
    begin
      Continue;
    end;
    Result.Add(lSymbol);
  end;
end;

procedure AppendSummaryJson(const aRoot: TJSONObject; const aAllSymbols,
  aFilteredSymbols: TObjectList<TGlobalVarSymbol>; const aAmbiguities: TList<TGlobalVarAmbiguity>;
  const aOptions: TAppOptions);
var
  lSummary: TJSONObject;
  lUnusedCount: Integer;
begin
  lUnusedCount := CountUnusedSymbols(aAllSymbols);
  lSummary := TJSONObject.Create;
  lSummary.AddPair('total', TJSONNumber.Create(aAllSymbols.Count));
  lSummary.AddPair('used', TJSONNumber.Create(aAllSymbols.Count - lUnusedCount));
  lSummary.AddPair('unused', TJSONNumber.Create(lUnusedCount));
  lSummary.AddPair('ambiguities', TJSONNumber.Create(aAmbiguities.Count));
  lSummary.AddPair('emitted', TJSONNumber.Create(aFilteredSymbols.Count));
  lSummary.AddPair('filter', GlobalVarsFilterText(aOptions));
  aRoot.AddPair('summary', lSummary);
end;

function RenderJson(const aAllSymbols, aFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aOptions: TAppOptions): string;
var
  lRoot: TJSONObject;
  lSymbols: TJSONArray;
  lAmbiguitiesJson: TJSONArray;
  lSymbol: TGlobalVarSymbol;
  lItem: TJSONObject;
  lUsedBy: TJSONArray;
  lRef: TGlobalVarRef;
  lAmbiguity: TGlobalVarAmbiguity;
begin
  lRoot := TJSONObject.Create;
  try
    AppendSummaryJson(lRoot, aAllSymbols, aFilteredSymbols, aAmbiguities, aOptions);
    lSymbols := TJSONArray.Create;
    lRoot.AddPair('symbols', lSymbols);
    for lSymbol in aFilteredSymbols do
    begin
      lItem := TJSONObject.Create;
      lItem.AddPair('declaringUnit', lSymbol.UnitName);
      lItem.AddPair('fileName', lSymbol.FileName);
      lItem.AddPair('name', lSymbol.Name);
      lItem.AddPair('type', lSymbol.TypeName);
      lItem.AddPair('kind', TSourceAnalyzer.KindToText(lSymbol.Kind));
      lItem.AddPair('line', TJSONNumber.Create(lSymbol.Line));
      lItem.AddPair('column', TJSONNumber.Create(lSymbol.Column));
      lUsedBy := TJSONArray.Create;
      for lRef in lSymbol.UsedBy do
      begin
        lUsedBy.AddElement(TJSONObject.Create
          .AddPair('unit', lRef.UnitName)
          .AddPair('routine', lRef.RoutineName)
          .AddPair('file', lRef.FileName)
          .AddPair('line', TJSONNumber.Create(lRef.Line))
          .AddPair('column', TJSONNumber.Create(lRef.Column))
          .AddPair('access', TSourceAnalyzer.AccessToText(lRef.Access)));
      end;
      lItem.AddPair('usedBy', lUsedBy);
      lSymbols.AddElement(lItem);
    end;
    lAmbiguitiesJson := TJSONArray.Create;
    lRoot.AddPair('ambiguities', lAmbiguitiesJson);
    for lAmbiguity in aAmbiguities do
    begin
      lAmbiguitiesJson.AddElement(TJSONObject.Create
        .AddPair('name', lAmbiguity.Name)
        .AddPair('unit', lAmbiguity.UnitName)
        .AddPair('routine', lAmbiguity.RoutineName)
        .AddPair('file', lAmbiguity.FileName)
        .AddPair('line', TJSONNumber.Create(lAmbiguity.Line))
        .AddPair('column', TJSONNumber.Create(lAmbiguity.Column))
        .AddPair('access', TSourceAnalyzer.AccessToText(lAmbiguity.Access))
        .AddPair('candidates', lAmbiguity.Candidates));
    end;
    Result := lRoot.Format(2);
  finally
    lRoot.Free;
  end;
end;

function RenderText(const aAllSymbols, aFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aOptions: TAppOptions): string;
var
  lBuilder: TStringBuilder;
  lSymbol: TGlobalVarSymbol;
  lRef: TGlobalVarRef;
  lUnusedCount: Integer;
  lAmbiguity: TGlobalVarAmbiguity;
begin
  lBuilder := TStringBuilder.Create;
  try
    lUnusedCount := CountUnusedSymbols(aAllSymbols);
    lBuilder.AppendLine(Format('Summary: total=%d used=%d unused=%d ambiguities=%d emitted=%d filter=%s',
      [aAllSymbols.Count, aAllSymbols.Count - lUnusedCount, lUnusedCount, aAmbiguities.Count, aFilteredSymbols.Count,
      GlobalVarsFilterText(aOptions)]));
    for lSymbol in aFilteredSymbols do
    begin
      lBuilder.AppendLine(Format('%s.%s: %s [%s] (%s:%d)', [lSymbol.UnitName, lSymbol.Name, lSymbol.TypeName, TSourceAnalyzer.KindToText(lSymbol.Kind), lSymbol.FileName, lSymbol.Line]));
      if lSymbol.UsedBy.Count = 0 then
      begin
        lBuilder.AppendLine('  used by: none');
      end else
      begin
        lBuilder.AppendLine('  used by:');
        for lRef in lSymbol.UsedBy do
        begin
          lBuilder.AppendLine(Format('    %s.%s [%s] (%s:%d)', [lRef.UnitName, lRef.RoutineName, TSourceAnalyzer.AccessToText(lRef.Access), lRef.FileName, lRef.Line]));
        end;
      end;
    end;
    if aAmbiguities.Count > 0 then
    begin
      lBuilder.AppendLine;
      lBuilder.AppendLine('Ambiguities:');
      for lAmbiguity in aAmbiguities do
      begin
        lBuilder.AppendLine(Format('  %s in %s.%s [%s] (%s:%d) candidates=%s',
          [lAmbiguity.Name, lAmbiguity.UnitName, lAmbiguity.RoutineName,
          TSourceAnalyzer.AccessToText(lAmbiguity.Access), lAmbiguity.FileName, lAmbiguity.Line, lAmbiguity.Candidates]));
      end;
    end;
    Result := TrimRight(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

function RunGlobalVarsCommand(const aOptions: TAppOptions): Integer;
var
  lProject: TProjectInfo;
  lAnalyzer: TSourceAnalyzer;
  lSymbols: TObjectList<TGlobalVarSymbol>;
  lCacheSymbols: TObjectList<TGlobalVarSymbol>;
  lFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  lAmbiguities: TList<TGlobalVarAmbiguity>;
  lCacheAmbiguities: TList<TGlobalVarAmbiguity>;
  lOutputText: string;
  lOutputPath: string;
  lInputHash: string;
  lVisitedFiles: TArray<string>;
  lCacheFileName: string;
begin
  Result := 0;
  lProject := BuildProjectInfo(aOptions);
  EnsureProjectFolders(lProject);
  lCacheFileName := CacheFileName(lProject, aOptions);
  lAnalyzer := nil;
  lCacheSymbols := nil;
  lCacheAmbiguities := nil;
  lSymbols := nil;
  lAmbiguities := nil;
  try
    if (aOptions.fGlobalVarsRefresh <> TGlobalVarsRefresh.gvrForce)
      and TryLoadCachedSymbols(lCacheFileName, lProject.ProjectPath, lCacheSymbols, lCacheAmbiguities) then
    begin
      lSymbols := lCacheSymbols;
      lAmbiguities := lCacheAmbiguities;
    end else
    begin
      lAnalyzer := TSourceAnalyzer.Create(lProject);
      lSymbols := lAnalyzer.Analyze(lInputHash);
      lVisitedFiles := lAnalyzer.GetVisitedFiles;
      lAmbiguities := lAnalyzer.Ambiguities;
      SaveCachedSymbols(lCacheFileName, lProject.ProjectPath, lInputHash, lVisitedFiles, lSymbols, lAmbiguities);
    end;
    lFilteredSymbols := BuildFilteredSymbols(lSymbols, aOptions);
    try
      if aOptions.fGlobalVarsFormat = TGlobalVarsFormat.gvfJson then
      begin
        lOutputText := RenderJson(lSymbols, lFilteredSymbols, lAmbiguities, aOptions);
      end else
      begin
        lOutputText := RenderText(lSymbols, lFilteredSymbols, lAmbiguities, aOptions);
      end;
    finally
      lFilteredSymbols.Free;
    end;
    if aOptions.fHasGlobalVarsOutputPath and (Trim(aOptions.fGlobalVarsOutputPath) <> '') then
    begin
      lOutputPath := aOptions.fGlobalVarsOutputPath;
    end else if aOptions.fGlobalVarsFormat = TGlobalVarsFormat.gvfJson then
    begin
      lOutputPath := TPath.Combine(lProject.ReportsPath, 'global-vars.json');
    end else
    begin
      lOutputPath := TPath.Combine(lProject.ReportsPath, 'global-vars.txt');
    end;
    if lOutputPath = '-' then
    begin
      WriteLn(lOutputText);
    end else
    begin
      if TPath.GetDirectoryName(lOutputPath) <> '' then
      begin
        TDirectory.CreateDirectory(TPath.GetDirectoryName(lOutputPath));
      end;
      TFile.WriteAllText(lOutputPath, lOutputText, TEncoding.UTF8);
      WriteLn('Wrote: ' + lOutputPath);
    end;
  finally
    lCacheAmbiguities.Free;
    lCacheSymbols.Free;
    lAnalyzer.Free;
  end;
end;

end.
