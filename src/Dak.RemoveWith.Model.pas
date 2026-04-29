unit Dak.RemoveWith.Model;

interface

uses
  DelphiAST.ProjectIndexer,
  Dak.Types;

type
  TRemoveWithModelRange = record
    fStartLine: Integer;
    fStartColumn: Integer;
    fEndLine: Integer;
    fEndColumn: Integer;
  end;

  TRemoveWithModelTypeKind = (rwmtUnknown, rwmtAlias, rwmtRecord, rwmtClass, rwmtInterface, rwmtHelper);
  TRemoveWithModelMemberKind = (rwmmField, rwmmProperty, rwmmMethod, rwmmConstant, rwmmClassVar);
  TRemoveWithModelRoutineSymbolKind = (rwmrsParameter, rwmrsLocal, rwmrsInlineLocal);

  TRemoveWithModelTypeInfo = record
    fName: string;
    fRelatedTypeName: string;
    fKind: TRemoveWithModelTypeKind;
    fRange: TRemoveWithModelRange;
  end;

  TRemoveWithModelMemberInfo = record
    fName: string;
    fTypeName: string;
    fOwnerType: string;
    fIsDefault: Boolean;
    fIsIndexed: Boolean;
    fIndexParameterCount: Integer;
    fKind: TRemoveWithModelMemberKind;
    fRange: TRemoveWithModelRange;
  end;

  TRemoveWithModelRoutineInfo = record
    fName: string;
    fOwnerType: string;
    fHasBody: Boolean;
    fRange: TRemoveWithModelRange;
  end;

  TRemoveWithModelRoutineSymbolInfo = record
    fName: string;
    fTypeName: string;
    fRoutineName: string;
    fKind: TRemoveWithModelRoutineSymbolKind;
    fRange: TRemoveWithModelRange;
  end;

  TRemoveWithModelWithStatementInfo = record
    fRoutineName: string;
    fSelectorText: string;
    fSelectorCount: Integer;
    fNestingDepth: Integer;
    fRange: TRemoveWithModelRange;
  end;

  TRemoveWithModelIdentifierReference = record
    fName: string;
    fRoutineName: string;
    fRole: string;
    fRange: TRemoveWithModelRange;
  end;

  TRemoveWithUnitModel = record
    fUnitName: string;
    fFilePath: string;
    fSourceText: string;
    fUses: TArray<string>;
    fTypes: TArray<TRemoveWithModelTypeInfo>;
    fMembers: TArray<TRemoveWithModelMemberInfo>;
    fRoutines: TArray<TRemoveWithModelRoutineInfo>;
    fRoutineSymbols: TArray<TRemoveWithModelRoutineSymbolInfo>;
    fWithStatements: TArray<TRemoveWithModelWithStatementInfo>;
    fIdentifierReferences: TArray<TRemoveWithModelIdentifierReference>;
  end;

  TRemoveWithProjectModel = class
  private
    fContext: TProjectAnalysisContext;
    fIndexer: TProjectIndexer;
    fIndexCount: Integer;
    fProjectPath: string;
    fUnitModels: TArray<TRemoveWithUnitModel>;
    procedure ExtractUnitModels;
  public
    constructor Create(const aProjectPath: string; const aContext: TProjectAnalysisContext);
    destructor Destroy; override;
    procedure Index;
    function ParsedUnitCount: Integer;
    function ProblemCount: Integer;
    property Context: TProjectAnalysisContext read fContext;
    property IndexCount: Integer read fIndexCount;
    property Indexer: TProjectIndexer read fIndexer;
    property ProjectPath: string read fProjectPath;
    property UnitModels: TArray<TRemoveWithUnitModel> read fUnitModels;
  end;

function BuildRemoveWithProjectModel(const aOptions: TAppOptions; const aProjectPath: string;
  out aModel: TRemoveWithProjectModel; out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  DelphiAST.Classes, DelphiAST.Consts,
  Dak.Project, Dak.RemoveWith.Source;

function FindChildNode(const aParent: TSyntaxNode; const aNodeType: TSyntaxNodeType): TSyntaxNode;
var
  lChild: TSyntaxNode;
begin
  Result := nil;
  if not Assigned(aParent) then
    Exit;

  for lChild in aParent.ChildNodes do
  begin
    if lChild.Typ = aNodeType then
      Exit(lChild);
  end;
end;

function FindAncestorNode(const aNode: TSyntaxNode; const aNodeType: TSyntaxNodeType): TSyntaxNode;
begin
  Result := aNode;
  while Assigned(Result) do
  begin
    if Result.Typ = aNodeType then
      Exit;
    Result := Result.ParentNode;
  end;
end;

procedure CollectNodes(const aRoot: TSyntaxNode; const aNodeType: TSyntaxNodeType; const aNodes: TList<TSyntaxNode>);
var
  lChild: TSyntaxNode;
begin
  if not Assigned(aRoot) then
    Exit;

  if aRoot.Typ = aNodeType then
    aNodes.Add(aRoot);
  for lChild in aRoot.ChildNodes do
    CollectNodes(lChild, aNodeType, aNodes);
end;

function HasDescendantNode(const aRoot: TSyntaxNode; const aNodeType: TSyntaxNodeType): Boolean;
var
  lChild: TSyntaxNode;
begin
  Result := False;
  if not Assigned(aRoot) then
    Exit;
  for lChild in aRoot.ChildNodes do
  begin
    if (lChild.Typ = aNodeType) or HasDescendantNode(lChild, aNodeType) then
      Exit(True);
  end;
end;

function ExtractNodeName(const aNode: TSyntaxNode): string;
begin
  Result := '';
  if not Assigned(aNode) then
    Exit;

  if aNode is TValuedSyntaxNode then
    Result := Trim(TValuedSyntaxNode(aNode).Value);
  if (Result = '') and aNode.HasAttribute(anName) then
    Result := Trim(aNode.GetAttribute(anName));
end;

function ExtractTypeName(const aNode: TSyntaxNode): string;
var
  lTypeNode: TSyntaxNode;
begin
  Result := '';
  lTypeNode := FindChildNode(aNode, ntType);
  if Assigned(lTypeNode) then
    Result := Trim(lTypeNode.GetAttribute(anName));
end;

function IsIdentifierName(const aName: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if (aName = '') or not CharInSet(aName[1], ['A'..'Z', 'a'..'z', '_']) then
    Exit;

  for i := 2 to Length(aName) do
  begin
    if not CharInSet(aName[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit;
  end;
  Result := True;
end;

function IsIdentifierChar(const aValue: Char): Boolean;
begin
  Result := CharInSet(aValue, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IsWordAt(const aText: string; const aOffset: Integer; const aWord: string): Boolean;
var
  lAfterOffset: Integer;
begin
  Result := False;
  if (aOffset < 1) or (aOffset + Length(aWord) - 1 > Length(aText)) then
    Exit;

  lAfterOffset := aOffset + Length(aWord);
  Result := SameText(Copy(aText, aOffset, Length(aWord)), aWord) and
    ((aOffset = 1) or (not IsIdentifierChar(aText[aOffset - 1]))) and
    ((lAfterOffset > Length(aText)) or (not IsIdentifierChar(aText[lAfterOffset])));
end;

procedure SkipString(const aText: string; var aOffset: Integer);
begin
  Inc(aOffset);
  while aOffset <= Length(aText) do
  begin
    if aText[aOffset] = '''' then
    begin
      if (aOffset < Length(aText)) and (aText[aOffset + 1] = '''') then
      begin
        Inc(aOffset, 2);
        Continue;
      end;
      Inc(aOffset);
      Exit;
    end;
    Inc(aOffset);
  end;
end;

procedure SkipBraceComment(const aText: string; var aOffset: Integer);
begin
  Inc(aOffset);
  while (aOffset <= Length(aText)) and (aText[aOffset] <> '}') do
    Inc(aOffset);
  if aOffset <= Length(aText) then
    Inc(aOffset);
end;

procedure SkipParenComment(const aText: string; var aOffset: Integer);
begin
  Inc(aOffset, 2);
  while (aOffset < Length(aText)) and ((aText[aOffset] <> '*') or (aText[aOffset + 1] <> ')')) do
    Inc(aOffset);
  if aOffset < Length(aText) then
    Inc(aOffset, 2);
end;

procedure SkipLineComment(const aText: string; var aOffset: Integer);
begin
  Inc(aOffset, 2);
  while (aOffset <= Length(aText)) and not CharInSet(aText[aOffset], [#10, #13]) do
    Inc(aOffset);
end;

function NormalizeModelText(const aText: string): string;
var
  i: Integer;
  lBuilder: TStringBuilder;
  lPendingSpace: Boolean;
begin
  lBuilder := TStringBuilder.Create;
  try
    lPendingSpace := False;
    for i := 1 to Length(aText) do
    begin
      if CharInSet(aText[i], [#9, #10, #13, ' ']) then
      begin
        if lBuilder.Length > 0 then
          lPendingSpace := True;
        Continue;
      end;

      if lPendingSpace then
      begin
        lBuilder.Append(' ');
        lPendingSpace := False;
      end;
      lBuilder.Append(aText[i]);
    end;
    Result := Trim(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

function ModelRangeForNode(const aNode: TSyntaxNode): TRemoveWithModelRange;
begin
  Result := Default(TRemoveWithModelRange);
  if not Assigned(aNode) then
    Exit;

  Result.fStartLine := aNode.Line;
  Result.fStartColumn := aNode.Col;
  if aNode is TCompoundSyntaxNode then
  begin
    Result.fEndLine := TCompoundSyntaxNode(aNode).EndLine;
    Result.fEndColumn := TCompoundSyntaxNode(aNode).EndCol;
  end else
  begin
    Result.fEndLine := aNode.Line;
    Result.fEndColumn := aNode.Col;
  end;
end;

function SourceLine(const aSource: TRemoveWithSourceBuffer; const aLine: Integer): string;
var
  lEndOffset: Integer;
  lStartOffset: Integer;
begin
  Result := '';
  if aLine <= 0 then
    Exit;
  if not RemoveWithOffsetForLineColumn(aSource, aLine, 1, lStartOffset) then
    Exit;

  lEndOffset := lStartOffset;
  while (lEndOffset <= Length(aSource.fText)) and not CharInSet(aSource.fText[lEndOffset], [#10, #13]) do
    Inc(lEndOffset);
  Result := Copy(aSource.fText, lStartOffset, lEndOffset - lStartOffset);
end;

function SourceSliceForRange(const aSource: TRemoveWithSourceBuffer; const aRange: TRemoveWithModelRange): string;
var
  lEndOffset: Integer;
  lLine: string;
  lStartOffset: Integer;
begin
  Result := '';
  if (aRange.fStartLine = aRange.fEndLine) and (aRange.fStartColumn = aRange.fEndColumn) then
  begin
    lLine := SourceLine(aSource, aRange.fStartLine);
    Exit(Copy(lLine, aRange.fStartColumn, MaxInt));
  end;
  if not RemoveWithOffsetForLineColumn(aSource, aRange.fStartLine, aRange.fStartColumn, lStartOffset) then
    Exit;
  if not RemoveWithOffsetForLineColumn(aSource, aRange.fEndLine, aRange.fEndColumn, lEndOffset) then
    lEndOffset := lStartOffset;
  if lEndOffset < lStartOffset then
    lEndOffset := lStartOffset;
  Result := Copy(aSource.fText, lStartOffset, lEndOffset - lStartOffset + 1);
end;

function CountSelectorsInText(const aText: string): Integer;
var
  i: Integer;
  lBracketDepth: Integer;
  lParenDepth: Integer;
begin
  if Trim(aText) = '' then
    Exit(0);

  Result := 1;
  lParenDepth := 0;
  lBracketDepth := 0;
  for i := 1 to Length(aText) do
  begin
    if aText[i] = '(' then
      Inc(lParenDepth)
    else if (aText[i] = ')') and (lParenDepth > 0) then
      Dec(lParenDepth)
    else if aText[i] = '[' then
      Inc(lBracketDepth)
    else if (aText[i] = ']') and (lBracketDepth > 0) then
      Dec(lBracketDepth)
    else if (aText[i] = ',') and (lParenDepth = 0) and (lBracketDepth = 0) then
      Inc(Result);
  end;
end;

function ExtractWithSelectorText(const aSource: TRemoveWithSourceBuffer; const aNode: TSyntaxNode): string;
var
  lBracketDepth: Integer;
  lDoPos: Integer;
  lOffset: Integer;
  lParenDepth: Integer;
  lSelectorStartOffset: Integer;
  lWithPos: Integer;
begin
  Result := '';
  if not RemoveWithOffsetForLineColumn(aSource, aNode.Line, aNode.Col, lWithPos) then
    Exit;

  while (lWithPos <= Length(aSource.fText)) and not IsWordAt(aSource.fText, lWithPos, 'with') do
    Inc(lWithPos);
  if lWithPos > Length(aSource.fText) then
    Exit;

  lOffset := lWithPos + Length('with');
  lSelectorStartOffset := lOffset;
  lParenDepth := 0;
  lBracketDepth := 0;
  lDoPos := 0;
  while lOffset <= Length(aSource.fText) do
  begin
    if aSource.fText[lOffset] = '''' then
    begin
      SkipString(aSource.fText, lOffset);
      Continue;
    end;
    if aSource.fText[lOffset] = '{' then
    begin
      SkipBraceComment(aSource.fText, lOffset);
      Continue;
    end;
    if (lOffset < Length(aSource.fText)) and (aSource.fText[lOffset] = '(') and
      (aSource.fText[lOffset + 1] = '*') then
    begin
      SkipParenComment(aSource.fText, lOffset);
      Continue;
    end;
    if (lOffset < Length(aSource.fText)) and (aSource.fText[lOffset] = '/') and
      (aSource.fText[lOffset + 1] = '/') then
    begin
      SkipLineComment(aSource.fText, lOffset);
      Continue;
    end;

    if (lParenDepth = 0) and (lBracketDepth = 0) and IsWordAt(aSource.fText, lOffset, 'do') then
    begin
      lDoPos := lOffset;
      Break;
    end;
    if aSource.fText[lOffset] = '(' then
      Inc(lParenDepth)
    else if (aSource.fText[lOffset] = ')') and (lParenDepth > 0) then
      Dec(lParenDepth)
    else if aSource.fText[lOffset] = '[' then
      Inc(lBracketDepth)
    else if (aSource.fText[lOffset] = ']') and (lBracketDepth > 0) then
      Dec(lBracketDepth);
    Inc(lOffset);
  end;

  if lDoPos = 0 then
    Exit;
  Result := NormalizeModelText(Copy(aSource.fText, lSelectorStartOffset, lDoPos - lSelectorStartOffset));
end;

function RoutineOwnerFromName(const aName: string): string;
var
  lDotPos: Integer;
begin
  Result := '';
  lDotPos := LastDelimiter('.', aName);
  if lDotPos > 0 then
    Result := Copy(aName, 1, lDotPos - 1);
end;

function TypeNameForNode(const aNode: TSyntaxNode): string;
var
  lNameNode: TSyntaxNode;
begin
  Result := ExtractTypeName(aNode);
  if Result <> '' then
    Exit;

  lNameNode := FindChildNode(aNode, ntType);
  Result := ExtractNodeName(lNameNode);
end;

function TypeKindFromNode(const aNode: TSyntaxNode): TRemoveWithModelTypeKind;
var
  lTypeNode: TSyntaxNode;
  lTypeText: string;
begin
  Result := TRemoveWithModelTypeKind.rwmtAlias;
  if HasDescendantNode(aNode, ntHelper) then
    Exit(TRemoveWithModelTypeKind.rwmtHelper);

  lTypeNode := FindChildNode(aNode, ntType);
  if Assigned(lTypeNode) then
  begin
    lTypeText := LowerCase(Trim(lTypeNode.GetAttribute(anType)));
    if lTypeText = 'class' then
      Exit(TRemoveWithModelTypeKind.rwmtClass);
    if (lTypeText = 'interface') or (lTypeText = 'dispinterface') then
      Exit(TRemoveWithModelTypeKind.rwmtInterface);
  end;

  if HasDescendantNode(aNode, ntField) or HasDescendantNode(aNode, ntProperty) or
    HasDescendantNode(aNode, ntMethod) then
    Exit(TRemoveWithModelTypeKind.rwmtRecord);
end;

function TypeOwnerName(const aNode: TSyntaxNode): string;
var
  lTypeNode: TSyntaxNode;
begin
  Result := '';
  lTypeNode := FindAncestorNode(aNode.ParentNode, ntTypeDecl);
  if Assigned(lTypeNode) then
    Result := ExtractNodeName(lTypeNode);
end;

function LastTextPosition(const aText, aPattern: string): Integer;
var
  lNextPos: Integer;
  lStartPos: Integer;
begin
  Result := 0;
  lStartPos := 1;
  repeat
    lNextPos := PosEx(aPattern, aText, lStartPos);
    if lNextPos > 0 then
    begin
      Result := lNextPos;
      lStartPos := lNextPos + Length(aPattern);
    end;
  until lNextPos = 0;
end;

function IsClassVarNode(const aNode: TSyntaxNode; const aSource: TRemoveWithSourceBuffer): Boolean;
var
  lClassVarPos: Integer;
  lConstPos: Integer;
  lFieldOffset: Integer;
  lOwnerOffset: Integer;
  lOwnerType: TSyntaxNode;
  lText: string;
begin
  Result := Assigned(aNode) and aNode.HasAttribute(anClass) and SameText(aNode.GetAttribute(anClass), 'true');
  if Result then
    Exit;

  lOwnerType := FindAncestorNode(aNode.ParentNode, ntTypeDecl);
  if not Assigned(lOwnerType) then
    Exit(False);
  if not RemoveWithOffsetForLineColumn(aSource, lOwnerType.Line, lOwnerType.Col, lOwnerOffset) then
    Exit(False);
  if not RemoveWithOffsetForLineColumn(aSource, aNode.Line, aNode.Col, lFieldOffset) then
    Exit(False);
  if lFieldOffset <= lOwnerOffset then
    Exit(False);

  lText := LowerCase(Copy(aSource.fText, lOwnerOffset, lFieldOffset - lOwnerOffset));
  lClassVarPos := LastTextPosition(lText, 'class var');
  if lClassVarPos = 0 then
    Exit(False);
  lConstPos := LastTextPosition(lText, 'const');
  Result := lClassVarPos > lConstPos;
end;

function RoutineNameForNode(const aNode: TSyntaxNode): string;
var
  lOwnerType: string;
begin
  Result := ExtractNodeName(aNode);
  lOwnerType := TypeOwnerName(aNode);
  if (lOwnerType <> '') and (Pos('.', Result) = 0) then
    Result := lOwnerType + '.' + Result;
end;

function WithAncestorDepth(const aNode: TSyntaxNode): Integer;
var
  lNode: TSyntaxNode;
begin
  Result := 0;
  lNode := aNode.ParentNode;
  while Assigned(lNode) do
  begin
    if lNode.Typ = ntWith then
      Inc(Result);
    lNode := lNode.ParentNode;
  end;
end;

procedure AddUse(var aUnitModel: TRemoveWithUnitModel; const aName: string);
var
  lIndex: Integer;
begin
  if aName = '' then
    Exit;
  lIndex := Length(aUnitModel.fUses);
  SetLength(aUnitModel.fUses, lIndex + 1);
  aUnitModel.fUses[lIndex] := aName;
end;

procedure AddType(var aUnitModel: TRemoveWithUnitModel; const aTypeInfo: TRemoveWithModelTypeInfo);
var
  lIndex: Integer;
begin
  if aTypeInfo.fName = '' then
    Exit;
  lIndex := Length(aUnitModel.fTypes);
  SetLength(aUnitModel.fTypes, lIndex + 1);
  aUnitModel.fTypes[lIndex] := aTypeInfo;
end;

procedure AddMember(var aUnitModel: TRemoveWithUnitModel; const aMember: TRemoveWithModelMemberInfo);
var
  lIndex: Integer;
begin
  if (aMember.fName = '') or (aMember.fOwnerType = '') then
    Exit;
  lIndex := Length(aUnitModel.fMembers);
  SetLength(aUnitModel.fMembers, lIndex + 1);
  aUnitModel.fMembers[lIndex] := aMember;
end;

procedure AddRoutine(var aUnitModel: TRemoveWithUnitModel; const aRoutine: TRemoveWithModelRoutineInfo);
var
  lIndex: Integer;
begin
  if aRoutine.fName = '' then
    Exit;
  lIndex := Length(aUnitModel.fRoutines);
  SetLength(aUnitModel.fRoutines, lIndex + 1);
  aUnitModel.fRoutines[lIndex] := aRoutine;
end;

procedure AddRoutineSymbol(var aUnitModel: TRemoveWithUnitModel; const aSymbol: TRemoveWithModelRoutineSymbolInfo);
var
  lIndex: Integer;
begin
  if (aSymbol.fName = '') or (aSymbol.fRoutineName = '') then
    Exit;
  lIndex := Length(aUnitModel.fRoutineSymbols);
  SetLength(aUnitModel.fRoutineSymbols, lIndex + 1);
  aUnitModel.fRoutineSymbols[lIndex] := aSymbol;
end;

procedure AddWithStatement(var aUnitModel: TRemoveWithUnitModel; const aStatement: TRemoveWithModelWithStatementInfo);
var
  lIndex: Integer;
begin
  if aStatement.fRoutineName = '' then
    Exit;
  lIndex := Length(aUnitModel.fWithStatements);
  SetLength(aUnitModel.fWithStatements, lIndex + 1);
  aUnitModel.fWithStatements[lIndex] := aStatement;
end;

procedure AddIdentifierReference(var aUnitModel: TRemoveWithUnitModel;
  const aReference: TRemoveWithModelIdentifierReference);
var
  lIndex: Integer;
begin
  if (aReference.fName = '') or (aReference.fRoutineName = '') then
    Exit;
  lIndex := Length(aUnitModel.fIdentifierReferences);
  SetLength(aUnitModel.fIdentifierReferences, lIndex + 1);
  aUnitModel.fIdentifierReferences[lIndex] := aReference;
end;

procedure ExtractUses(const aRoot: TSyntaxNode; var aUnitModel: TRemoveWithUnitModel);
var
  lUnitNode: TSyntaxNode;
  lUsesNode: TSyntaxNode;
  lUsesNodes: TList<TSyntaxNode>;
begin
  lUsesNodes := TList<TSyntaxNode>.Create;
  try
    CollectNodes(aRoot, ntUses, lUsesNodes);
    for lUsesNode in lUsesNodes do
    begin
      for lUnitNode in lUsesNode.ChildNodes do
      begin
        if lUnitNode.Typ = ntUnit then
          AddUse(aUnitModel, Trim(lUnitNode.GetAttribute(anName)));
      end;
    end;
  finally
    lUsesNodes.Free;
  end;
end;

procedure ExtractTypes(const aRoot: TSyntaxNode; const aSource: TRemoveWithSourceBuffer;
  var aUnitModel: TRemoveWithUnitModel);
var
  lNode: TSyntaxNode;
  lNodes: TList<TSyntaxNode>;
  lTypeInfo: TRemoveWithModelTypeInfo;
begin
  lNodes := TList<TSyntaxNode>.Create;
  try
    CollectNodes(aRoot, ntTypeDecl, lNodes);
    for lNode in lNodes do
    begin
      lTypeInfo := Default(TRemoveWithModelTypeInfo);
      lTypeInfo.fName := ExtractNodeName(lNode);
      lTypeInfo.fRelatedTypeName := ExtractTypeName(lNode);
      lTypeInfo.fKind := TypeKindFromNode(lNode);
      lTypeInfo.fRange := ModelRangeForNode(lNode);
      AddType(aUnitModel, lTypeInfo);
    end;
  finally
    lNodes.Free;
  end;
end;

procedure ExtractMembers(const aRoot: TSyntaxNode; const aSource: TRemoveWithSourceBuffer;
  var aUnitModel: TRemoveWithUnitModel);
var
  lMember: TRemoveWithModelMemberInfo;
  lNode: TSyntaxNode;
  lNodes: TList<TSyntaxNode>;
begin
  lNodes := TList<TSyntaxNode>.Create;
  try
    CollectNodes(aRoot, ntField, lNodes);
    CollectNodes(aRoot, ntProperty, lNodes);
    CollectNodes(aRoot, ntMethod, lNodes);
    CollectNodes(aRoot, ntConstant, lNodes);
    for lNode in lNodes do
    begin
      lMember := Default(TRemoveWithModelMemberInfo);
      lMember.fOwnerType := TypeOwnerName(lNode);
      if lMember.fOwnerType = '' then
        Continue;
      lMember.fName := ExtractNodeName(FindChildNode(lNode, ntName));
      if lMember.fName = '' then
      lMember.fName := ExtractNodeName(lNode);
      lMember.fTypeName := TypeNameForNode(lNode);
      lMember.fRange := ModelRangeForNode(lNode);
      lMember.fIsDefault := ContainsText(SourceSliceForRange(aSource, lMember.fRange), ' default');
      lMember.fIsIndexed := Assigned(FindChildNode(lNode, ntParameters));
      if lMember.fIsIndexed then
        lMember.fIndexParameterCount := Length(FindChildNode(lNode, ntParameters).ChildNodes);
      if lNode.Typ = ntProperty then
        lMember.fKind := TRemoveWithModelMemberKind.rwmmProperty
      else if lNode.Typ = ntMethod then
        lMember.fKind := TRemoveWithModelMemberKind.rwmmMethod
      else if lNode.Typ = ntConstant then
        lMember.fKind := TRemoveWithModelMemberKind.rwmmConstant
      else if IsClassVarNode(lNode, aSource) then
        lMember.fKind := TRemoveWithModelMemberKind.rwmmClassVar
      else
        lMember.fKind := TRemoveWithModelMemberKind.rwmmField;
      AddMember(aUnitModel, lMember);
    end;
  finally
    lNodes.Free;
  end;
end;

procedure ExtractRoutineDetails(const aMethodNode: TSyntaxNode; const aSource: TRemoveWithSourceBuffer;
  var aUnitModel: TRemoveWithUnitModel);
var
  lIdentifier: TRemoveWithModelIdentifierReference;
  lNode: TSyntaxNode;
  lNodes: TList<TSyntaxNode>;
  lRoutineName: string;
  lStatement: TRemoveWithModelWithStatementInfo;
  lSymbol: TRemoveWithModelRoutineSymbolInfo;
begin
  lRoutineName := RoutineNameForNode(aMethodNode);
  if not Assigned(FindChildNode(aMethodNode, ntStatements)) then
    Exit;

  lNodes := TList<TSyntaxNode>.Create;
  try
    CollectNodes(aMethodNode, ntParameter, lNodes);
    CollectNodes(aMethodNode, ntVariable, lNodes);
    for lNode in lNodes do
    begin
      if (lNode <> aMethodNode) and Assigned(FindAncestorNode(lNode.ParentNode, ntMethod)) and
        (FindAncestorNode(lNode.ParentNode, ntMethod) <> aMethodNode) then
        Continue;
      lSymbol := Default(TRemoveWithModelRoutineSymbolInfo);
      lSymbol.fName := ExtractNodeName(FindChildNode(lNode, ntName));
      if not IsIdentifierName(lSymbol.fName) then
        Continue;
      lSymbol.fTypeName := TypeNameForNode(lNode);
      lSymbol.fRoutineName := lRoutineName;
      lSymbol.fRange := ModelRangeForNode(lNode);
      if lNode.Typ = ntParameter then
        lSymbol.fKind := TRemoveWithModelRoutineSymbolKind.rwmrsParameter
      else if Assigned(FindAncestorNode(lNode.ParentNode, ntStatements)) then
        lSymbol.fKind := TRemoveWithModelRoutineSymbolKind.rwmrsInlineLocal
      else
        lSymbol.fKind := TRemoveWithModelRoutineSymbolKind.rwmrsLocal;
      AddRoutineSymbol(aUnitModel, lSymbol);
    end;

    lNodes.Clear;
    CollectNodes(aMethodNode, ntWith, lNodes);
    for lNode in lNodes do
    begin
      lStatement := Default(TRemoveWithModelWithStatementInfo);
      lStatement.fRoutineName := lRoutineName;
      lStatement.fSelectorText := ExtractWithSelectorText(aSource, lNode);
      lStatement.fSelectorCount := CountSelectorsInText(lStatement.fSelectorText);
      lStatement.fNestingDepth := WithAncestorDepth(lNode);
      lStatement.fRange := ModelRangeForNode(lNode);
      AddWithStatement(aUnitModel, lStatement);
    end;

    lNodes.Clear;
    CollectNodes(aMethodNode, ntIdentifier, lNodes);
    for lNode in lNodes do
    begin
      if not Assigned(FindAncestorNode(lNode.ParentNode, ntStatements)) then
        Continue;
      lIdentifier := Default(TRemoveWithModelIdentifierReference);
      lIdentifier.fName := Trim(lNode.GetAttribute(anName));
      if not IsIdentifierName(lIdentifier.fName) then
        Continue;
      lIdentifier.fRoutineName := lRoutineName;
      if Assigned(lNode.ParentNode) then
        lIdentifier.fRole := SyntaxNodeNames[lNode.ParentNode.Typ];
      lIdentifier.fRange := ModelRangeForNode(lNode);
      AddIdentifierReference(aUnitModel, lIdentifier);
    end;
  finally
    lNodes.Free;
  end;
end;

procedure ExtractRoutines(const aRoot: TSyntaxNode; const aSource: TRemoveWithSourceBuffer;
  var aUnitModel: TRemoveWithUnitModel);
var
  lNode: TSyntaxNode;
  lNodes: TList<TSyntaxNode>;
  lRoutine: TRemoveWithModelRoutineInfo;
begin
  lNodes := TList<TSyntaxNode>.Create;
  try
    CollectNodes(aRoot, ntMethod, lNodes);
    for lNode in lNodes do
    begin
      lRoutine := Default(TRemoveWithModelRoutineInfo);
      lRoutine.fName := RoutineNameForNode(lNode);
      lRoutine.fOwnerType := TypeOwnerName(lNode);
      if lRoutine.fOwnerType = '' then
        lRoutine.fOwnerType := RoutineOwnerFromName(lRoutine.fName);
      lRoutine.fHasBody := Assigned(FindChildNode(lNode, ntStatements));
      lRoutine.fRange := ModelRangeForNode(lNode);
      AddRoutine(aUnitModel, lRoutine);
      ExtractRoutineDetails(lNode, aSource, aUnitModel);
    end;
  finally
    lNodes.Free;
  end;
end;

function ExtractUnitModel(const aUnit: TProjectIndexer.TUnitInfo): TRemoveWithUnitModel;
var
  lError: string;
  lSource: TRemoveWithSourceBuffer;
begin
  Result := Default(TRemoveWithUnitModel);
  Result.fUnitName := aUnit.Name;
  Result.fFilePath := TPath.GetFullPath(aUnit.Path);
  if not Assigned(aUnit.SyntaxTree) then
    Exit;
  if not LoadRemoveWithSource(Result.fFilePath, lSource, lError) then
    Exit;

  Result.fSourceText := lSource.fText;
  ExtractUses(aUnit.SyntaxTree, Result);
  ExtractTypes(aUnit.SyntaxTree, lSource, Result);
  ExtractMembers(aUnit.SyntaxTree, lSource, Result);
  ExtractRoutines(aUnit.SyntaxTree, lSource, Result);
end;

constructor TRemoveWithProjectModel.Create(const aProjectPath: string; const aContext: TProjectAnalysisContext);
begin
  inherited Create;
  fProjectPath := aProjectPath;
  fContext := aContext;
  fIndexer := TProjectIndexer.Create;
  fIndexer.Defines := fContext.fParserDefines;
  fIndexer.SearchPath := fContext.fParserSearchPath;
end;

destructor TRemoveWithProjectModel.Destroy;
begin
  fIndexer.Free;
  inherited;
end;

procedure TRemoveWithProjectModel.Index;
begin
  fIndexer.Index(fContext.fMainSourcePath);
  Inc(fIndexCount);
end;

procedure TRemoveWithProjectModel.ExtractUnitModels;
var
  lIndex: Integer;
  lParsedPaths: TDictionary<string, Byte>;
  lUnit: TProjectIndexer.TUnitInfo;
  lUnitPath: string;
begin
  SetLength(fUnitModels, 0);
  lParsedPaths := TDictionary<string, Byte>.Create;
  try
    for lUnit in fIndexer.ParsedUnits do
    begin
      lUnitPath := Trim(lUnit.Path);
      if (lUnitPath = '') or (not SameText(TPath.GetExtension(lUnitPath), '.pas')) or
        (not TFile.Exists(lUnitPath)) then
        Continue;
      lUnitPath := TPath.GetFullPath(lUnitPath);
      if lParsedPaths.ContainsKey(UpperCase(lUnitPath)) then
        Continue;
      lParsedPaths.Add(UpperCase(lUnitPath), 1);
      lIndex := Length(fUnitModels);
      SetLength(fUnitModels, lIndex + 1);
      fUnitModels[lIndex] := ExtractUnitModel(lUnit);
    end;
  finally
    lParsedPaths.Free;
  end;
end;

function TRemoveWithProjectModel.ParsedUnitCount: Integer;
var
  lUnit: TProjectIndexer.TUnitInfo;
begin
  Result := 0;
  for lUnit in fIndexer.ParsedUnits do
    Inc(Result);
end;

function TRemoveWithProjectModel.ProblemCount: Integer;
var
  lProblem: TProjectIndexer.TProblemInfo;
begin
  Result := 0;
  for lProblem in fIndexer.Problems do
    Inc(Result);
end;

function BuildRemoveWithProjectModel(const aOptions: TAppOptions; const aProjectPath: string;
  out aModel: TRemoveWithProjectModel; out aError: string): Boolean;
var
  lContext: TProjectAnalysisContext;
begin
  aModel := nil;
  aError := '';
  if not TryBuildProjectAnalysisContext(aOptions, lContext, aError) then
    Exit(False);

  aModel := TRemoveWithProjectModel.Create(aProjectPath, lContext);
  try
    aModel.Index;
    aModel.ExtractUnitModels;
  except
    aModel.Free;
    aModel := nil;
    raise;
  end;
  Result := True;
end;

end.
