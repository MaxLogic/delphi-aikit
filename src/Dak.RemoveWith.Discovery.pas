unit Dak.RemoveWith.Discovery;

interface

uses
  Dak.RemoveWith.Model, Dak.Types;

type
  TRemoveWithRange = record
    fStartLine: Integer;
    fStartColumn: Integer;
    fEndLine: Integer;
    fEndColumn: Integer;
  end;

  TRemoveWithFileInfo = record
    fPath: string;
    fScanned: Boolean;
    fWithStatementCount: Integer;
  end;

  TRemoveWithStatementInfo = record
    fId: string;
    fFilePath: string;
    fLine: Integer;
    fColumn: Integer;
    fSelectorText: string;
    fSelectorCount: Integer;
    fSelectorRange: TRemoveWithRange;
    fNestingDepth: Integer;
    fHasScopedDeclarationInBody: Boolean;
    fHasUnsupportedIdentifierRoleInBody: Boolean;
    fUnsupportedIdentifierRole: string;
    fRange: TRemoveWithRange;
    fBodyRange: TRemoveWithRange;
  end;

  TRemoveWithWarningInfo = record
    fFilePath: string;
    fLine: Integer;
    fColumn: Integer;
    fCode: string;
    fMessage: string;
  end;

  TRemoveWithScanResult = record
    fFiles: TArray<TRemoveWithFileInfo>;
    fWithStatements: TArray<TRemoveWithStatementInfo>;
    fWarnings: TArray<TRemoveWithWarningInfo>;
  end;

function DiscoverRemoveWithStatements(const aOptions: TAppOptions; const aProjectPath: string;
  out aScanResult: TRemoveWithScanResult; out aError: string): Boolean; overload;
function DiscoverRemoveWithStatements(const aOptions: TAppOptions; const aProjectModel: TRemoveWithProjectModel;
  out aScanResult: TRemoveWithScanResult; out aError: string): Boolean; overload;

implementation

uses
  System.IOUtils, System.StrUtils, System.SysUtils,
  DelphiAST.Classes, DelphiAST.Consts, DelphiAST.ProjectIndexer,
  Dak.RemoveWith.Source, Dak.Utils;

type
  TRemoveWithDiscoveryHelper = record
  private
    class function NormalizePathKey(const aPath: string): string; static;
    class function IsWhitespace(const aValue: Char): Boolean; static;
    class function IsCommentNode(const aNode: TSyntaxNode): Boolean; static;
    class function IsIdentifierChar(const aValue: Char): Boolean; static;
    class function IsWordAt(const aText: string; const aOffset: Integer; const aWord: string): Boolean; static;
    class function NextNonWhitespaceOffset(const aText: string; const aOffset: Integer): Integer; static;
    class function CountSelectors(const aSelectorText: string): Integer; static;
    class function IsRootedPath(const aPath: string): Boolean; static;
    class function NormalizeSelectorText(const aText: string): string; static;
    class procedure SkipString(const aText: string; var aOffset: Integer); static;
    class procedure SkipBraceComment(const aText: string; var aOffset: Integer); static;
    class procedure SkipParenComment(const aText: string; var aOffset: Integer); static;
    class procedure SkipLineComment(const aText: string; var aOffset: Integer); static;
    class function FindWithKeywordOffset(const aSource: TRemoveWithSourceBuffer; const aLine,
      aColumn: Integer; out aOffset: Integer): Boolean; static;
    class function ExtractSelectorInfo(const aSource: TRemoveWithSourceBuffer; const aLine,
      aColumn: Integer; out aSelectorText: string; out aSelectorRange: TRemoveWithRange;
      out aSelectorCount: Integer; out aWithRangeStart: TRemoveWithRange): Boolean; static;
    class function FindBodyNode(const aWithNode: TSyntaxNode): TSyntaxNode; static;
    class function BodyContainsScopedDeclaration(const aNode: TSyntaxNode): Boolean; static;
    class function UnsupportedIdentifierRoleForNode(const aNode: TSyntaxNode): string; static;
    class function BodyContainsUnsupportedIdentifierRole(const aNode: TSyntaxNode; out aRole: string): Boolean;
      static;
    class function BodySourceContainsUnsupportedIdentifierRole(const aSource: TRemoveWithSourceBuffer;
      const aRange: TRemoveWithRange; out aRole: string): Boolean; static;
    class function SemicolonContinuesStatement(const aText: string; const aOffset: Integer): Boolean; static;
    class function FindStatementEndOffset(const aSource: TRemoveWithSourceBuffer;
      const aStartOffset: Integer): Integer; static;
    class function NodeRange(const aNode: TSyntaxNode; const aSource: TRemoveWithSourceBuffer): TRemoveWithRange;
      static;
    class procedure AddFile(var aScanResult: TRemoveWithScanResult; const aPath: string; const aWithCount: Integer);
      static;
    class procedure AddWarning(var aScanResult: TRemoveWithScanResult; const aPath: string; const aLine,
      aColumn: Integer; const aCode, aMessage: string); static;
    class procedure AddWithStatement(var aScanResult: TRemoveWithScanResult; const aInfo: TRemoveWithStatementInfo);
      static;
    class procedure CollectFromNode(const aNode: TSyntaxNode; const aFilePath: string;
      const aSource: TRemoveWithSourceBuffer; const aDepth: Integer; var aScanResult: TRemoveWithScanResult); static;
    class function ShouldScanPath(const aOptions: TAppOptions; const aPath, aDirKey, aUnitKey: string): Boolean; static;
    class function ShouldReportProblem(const aOptions: TAppOptions; const aProblemPath, aProjectDir, aDirKey,
      aUnitKey: string): Boolean; static;
    class function ProblemCode(const aProblemType: TProjectIndexer.TProblemType): string; static;
  end;

class function TRemoveWithDiscoveryHelper.NormalizePathKey(const aPath: string): string;
begin
  Result := AnsiLowerCase(TPath.GetFullPath(aPath));
end;

class function TRemoveWithDiscoveryHelper.IsWhitespace(const aValue: Char): Boolean;
begin
  Result := CharInSet(aValue, [#9, #10, #13, ' ']);
end;

class function TRemoveWithDiscoveryHelper.IsCommentNode(const aNode: TSyntaxNode): Boolean;
begin
  Result := Assigned(aNode) and (aNode.Typ in [TSyntaxNodeType.ntAnsiComment, TSyntaxNodeType.ntBorComment,
    TSyntaxNodeType.ntSlashesComment]);
end;

class function TRemoveWithDiscoveryHelper.IsIdentifierChar(const aValue: Char): Boolean;
begin
  Result := CharInSet(aValue, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

class function TRemoveWithDiscoveryHelper.IsWordAt(const aText: string; const aOffset: Integer;
  const aWord: string): Boolean;
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

class function TRemoveWithDiscoveryHelper.NextNonWhitespaceOffset(const aText: string;
  const aOffset: Integer): Integer;
begin
  Result := aOffset;
  while (Result <= Length(aText)) and IsWhitespace(aText[Result]) do
    Inc(Result);
end;

class function TRemoveWithDiscoveryHelper.CountSelectors(const aSelectorText: string): Integer;
var
  lBracketDepth: Integer;
  lIndex: Integer;
  lParenDepth: Integer;
  lQuoteOpen: Boolean;
begin
  if Trim(aSelectorText) = '' then
    Exit(0);

  Result := 1;
  lParenDepth := 0;
  lBracketDepth := 0;
  lQuoteOpen := False;
  lIndex := 1;
  while lIndex <= Length(aSelectorText) do
  begin
    if (not lQuoteOpen) and (aSelectorText[lIndex] = '{') then
    begin
      while (lIndex <= Length(aSelectorText)) and (aSelectorText[lIndex] <> '}') do
        Inc(lIndex);
      Inc(lIndex);
      Continue;
    end;

    if (not lQuoteOpen) and (lIndex < Length(aSelectorText)) and (aSelectorText[lIndex] = '(') and
      (aSelectorText[lIndex + 1] = '*') then
    begin
      Inc(lIndex, 2);
      while (lIndex < Length(aSelectorText)) and
        ((aSelectorText[lIndex] <> '*') or (aSelectorText[lIndex + 1] <> ')')) do
        Inc(lIndex);
      Inc(lIndex, 2);
      Continue;
    end;

    if (not lQuoteOpen) and (lIndex < Length(aSelectorText)) and (aSelectorText[lIndex] = '/') and
      (aSelectorText[lIndex + 1] = '/') then
    begin
      Inc(lIndex, 2);
      while (lIndex <= Length(aSelectorText)) and not CharInSet(aSelectorText[lIndex], [#10, #13]) do
        Inc(lIndex);
      Continue;
    end;

    if aSelectorText[lIndex] = '''' then
    begin
      if lQuoteOpen and (lIndex < Length(aSelectorText)) and (aSelectorText[lIndex + 1] = '''') then
      begin
        Inc(lIndex, 2);
        Continue;
      end else
        lQuoteOpen := not lQuoteOpen;
      Inc(lIndex);
      Continue;
    end;

    if lQuoteOpen then
    begin
      Inc(lIndex);
      Continue;
    end;
    if aSelectorText[lIndex] = '(' then
      Inc(lParenDepth)
    else if (aSelectorText[lIndex] = ')') and (lParenDepth > 0) then
      Dec(lParenDepth)
    else if aSelectorText[lIndex] = '[' then
      Inc(lBracketDepth)
    else if (aSelectorText[lIndex] = ']') and (lBracketDepth > 0) then
      Dec(lBracketDepth)
    else if (aSelectorText[lIndex] = ',') and (lParenDepth = 0) and (lBracketDepth = 0) then
      Inc(Result);
    Inc(lIndex);
  end;
end;

class function TRemoveWithDiscoveryHelper.IsRootedPath(const aPath: string): Boolean;
begin
  Result := (aPath <> '') and (TPath.IsPathRooted(aPath) or ((Length(aPath) >= 3) and (aPath[2] = ':')));
end;

class function TRemoveWithDiscoveryHelper.NormalizeSelectorText(const aText: string): string;
var
  lBuilder: TStringBuilder;
  lIndex: Integer;
  lPendingSpace: Boolean;
begin
  lBuilder := TStringBuilder.Create;
  try
    lPendingSpace := False;
    for lIndex := 1 to Length(aText) do
    begin
      if IsWhitespace(aText[lIndex]) then
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
      lBuilder.Append(aText[lIndex]);
    end;
    Result := Trim(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

class procedure TRemoveWithDiscoveryHelper.SkipString(const aText: string; var aOffset: Integer);
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

class procedure TRemoveWithDiscoveryHelper.SkipBraceComment(const aText: string; var aOffset: Integer);
begin
  Inc(aOffset);
  while (aOffset <= Length(aText)) and (aText[aOffset] <> '}') do
    Inc(aOffset);
  if aOffset <= Length(aText) then
    Inc(aOffset);
end;

class procedure TRemoveWithDiscoveryHelper.SkipParenComment(const aText: string; var aOffset: Integer);
begin
  Inc(aOffset, 2);
  while (aOffset < Length(aText)) and ((aText[aOffset] <> '*') or (aText[aOffset + 1] <> ')')) do
    Inc(aOffset);
  if aOffset < Length(aText) then
    Inc(aOffset, 2);
end;

class procedure TRemoveWithDiscoveryHelper.SkipLineComment(const aText: string; var aOffset: Integer);
begin
  Inc(aOffset, 2);
  while (aOffset <= Length(aText)) and not CharInSet(aText[aOffset], [#10, #13]) do
    Inc(aOffset);
end;

class function TRemoveWithDiscoveryHelper.FindWithKeywordOffset(const aSource: TRemoveWithSourceBuffer;
  const aLine, aColumn: Integer; out aOffset: Integer): Boolean;
var
  lOffset: Integer;
begin
  aOffset := 0;
  Result := False;
  if not RemoveWithOffsetForLineColumn(aSource, aLine, aColumn, lOffset) then
    Exit;

  while (lOffset <= Length(aSource.fText)) and not CharInSet(aSource.fText[lOffset], [#10, #13]) do
  begin
    if IsWordAt(aSource.fText, lOffset, 'with') then
    begin
      aOffset := lOffset;
      Exit(True);
    end;
    Inc(lOffset);
  end;
end;

class function TRemoveWithDiscoveryHelper.ExtractSelectorInfo(const aSource: TRemoveWithSourceBuffer;
  const aLine, aColumn: Integer; out aSelectorText: string; out aSelectorRange: TRemoveWithRange;
  out aSelectorCount: Integer; out aWithRangeStart: TRemoveWithRange): Boolean;
var
  lBracketDepth: Integer;
  lEndOffset: Integer;
  lOffset: Integer;
  lParenDepth: Integer;
  lSelectorStartOffset: Integer;
  lStartOffset: Integer;
  lWithOffset: Integer;
begin
  aSelectorText := '';
  aSelectorRange := Default(TRemoveWithRange);
  aSelectorCount := 0;
  aWithRangeStart := Default(TRemoveWithRange);
  Result := False;
  if not FindWithKeywordOffset(aSource, aLine, aColumn, lWithOffset) then
    Exit;

  RemoveWithLineColumnForOffset(aSource, lWithOffset, aWithRangeStart.fStartLine, aWithRangeStart.fStartColumn);
  lOffset := lWithOffset + Length('with');
  lSelectorStartOffset := lOffset;
  lParenDepth := 0;
  lBracketDepth := 0;

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
      Break;

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

  if lOffset > Length(aSource.fText) then
    Exit;

  lStartOffset := lSelectorStartOffset;
  lEndOffset := lOffset - 1;
  while (lStartOffset <= lEndOffset) and IsWhitespace(aSource.fText[lStartOffset]) do
    Inc(lStartOffset);
  while (lEndOffset >= lStartOffset) and IsWhitespace(aSource.fText[lEndOffset]) do
    Dec(lEndOffset);
  if lEndOffset < lStartOffset then
    Exit;

  RemoveWithLineColumnForOffset(aSource, lStartOffset, aSelectorRange.fStartLine, aSelectorRange.fStartColumn);
  RemoveWithLineColumnForOffset(aSource, lEndOffset, aSelectorRange.fEndLine, aSelectorRange.fEndColumn);
  aSelectorText := RemoveWithTextSlice(aSource, lStartOffset, lEndOffset);
  aSelectorCount := CountSelectors(aSelectorText);
  aSelectorText := NormalizeSelectorText(aSelectorText);
  Result := True;
end;

class function TRemoveWithDiscoveryHelper.FindBodyNode(const aWithNode: TSyntaxNode): TSyntaxNode;
var
  lChild: TSyntaxNode;
begin
  Result := nil;
  for lChild in aWithNode.ChildNodes do
  begin
    if (lChild.Typ = TSyntaxNodeType.ntExpressions) or IsCommentNode(lChild) then
      Continue;
    Exit(lChild);
  end;
end;

class function TRemoveWithDiscoveryHelper.BodyContainsScopedDeclaration(const aNode: TSyntaxNode): Boolean;
var
  lChild: TSyntaxNode;
begin
  Result := False;
  if not Assigned(aNode) then
    Exit;
  if aNode.Typ in [TSyntaxNodeType.ntVariables, TSyntaxNodeType.ntExceptionHandler] then
    Exit(True);
  for lChild in aNode.ChildNodes do
  begin
    if BodyContainsScopedDeclaration(lChild) then
      Exit(True);
  end;
end;

class function TRemoveWithDiscoveryHelper.UnsupportedIdentifierRoleForNode(const aNode: TSyntaxNode): string;
begin
  Result := '';
  if not Assigned(aNode) then
    Exit;

  case aNode.Typ of
    TSyntaxNodeType.ntAttribute, TSyntaxNodeType.ntAttributes:
      Result := 'attribute';
    TSyntaxNodeType.ntCaseLabel, TSyntaxNodeType.ntCaseLabels:
      Result := 'case-label';
    TSyntaxNodeType.ntConstant, TSyntaxNodeType.ntConstants:
      Result := 'constant-declaration';
    TSyntaxNodeType.ntField, TSyntaxNodeType.ntFields:
      Result := 'field-declaration';
    TSyntaxNodeType.ntGoto:
      Result := 'goto-label';
    TSyntaxNodeType.ntLabel:
      Result := 'label';
    TSyntaxNodeType.ntMethod:
      Result := 'method-declaration';
    TSyntaxNodeType.ntNamedArgument:
      Result := 'named-argument';
    TSyntaxNodeType.ntParameter, TSyntaxNodeType.ntParameters:
      Result := 'parameter-declaration';
    TSyntaxNodeType.ntProperty:
      Result := 'property-declaration';
    TSyntaxNodeType.ntType, TSyntaxNodeType.ntTypeArgs, TSyntaxNodeType.ntTypeDecl, TSyntaxNodeType.ntTypeParam,
      TSyntaxNodeType.ntTypeParams, TSyntaxNodeType.ntTypeSection:
      Result := 'type-name';
    TSyntaxNodeType.ntVariable, TSyntaxNodeType.ntVariables:
      Result := 'variable-declaration';
  end;
end;

class function TRemoveWithDiscoveryHelper.BodyContainsUnsupportedIdentifierRole(const aNode: TSyntaxNode;
  out aRole: string): Boolean;
var
  lChild: TSyntaxNode;
begin
  Result := False;
  aRole := '';
  if not Assigned(aNode) then
    Exit;

  aRole := UnsupportedIdentifierRoleForNode(aNode);
  if aRole <> '' then
    Exit(True);

  for lChild in aNode.ChildNodes do
  begin
    if BodyContainsUnsupportedIdentifierRole(lChild, aRole) then
      Exit(True);
  end;
end;

class function TRemoveWithDiscoveryHelper.BodySourceContainsUnsupportedIdentifierRole(
  const aSource: TRemoveWithSourceBuffer; const aRange: TRemoveWithRange; out aRole: string): Boolean;
var
  lEndOffset: Integer;
  lIdentifierEndOffset: Integer;
  lNextOffset: Integer;
  lStartOffset: Integer;
  i: Integer;
begin
  Result := False;
  aRole := '';
  if not RemoveWithOffsetForLineColumn(aSource, aRange.fStartLine, aRange.fStartColumn, lStartOffset) then
    Exit;
  if not RemoveWithOffsetForLineColumn(aSource, aRange.fEndLine, aRange.fEndColumn, lEndOffset) then
    Exit;

  i := lStartOffset;
  while i <= lEndOffset do
  begin
    if aSource.fText[i] = '''' then
    begin
      SkipString(aSource.fText, i);
      Continue;
    end;

    if aSource.fText[i] = '{' then
    begin
      SkipBraceComment(aSource.fText, i);
      Continue;
    end;

    if (i < lEndOffset) and (aSource.fText[i] = '(') and (aSource.fText[i + 1] = '*') then
    begin
      SkipParenComment(aSource.fText, i);
      Continue;
    end;

    if (i < lEndOffset) and (aSource.fText[i] = '/') and (aSource.fText[i + 1] = '/') then
    begin
      SkipLineComment(aSource.fText, i);
      Continue;
    end;

    if CharInSet(aSource.fText[i], ['A'..'Z', 'a'..'z', '_']) then
    begin
      lIdentifierEndOffset := i;
      while (lIdentifierEndOffset <= lEndOffset) and IsIdentifierChar(aSource.fText[lIdentifierEndOffset]) do
        Inc(lIdentifierEndOffset);
      lNextOffset := NextNonWhitespaceOffset(aSource.fText, lIdentifierEndOffset);
      if (lNextOffset <= lEndOffset) and (aSource.fText[lNextOffset] = ':') and
        ((lNextOffset = lEndOffset) or (aSource.fText[lNextOffset + 1] <> '=')) then
      begin
        aRole := 'label';
        Exit(True);
      end;
      i := lIdentifierEndOffset;
      Continue;
    end;

    Inc(i);
  end;
end;

class function TRemoveWithDiscoveryHelper.SemicolonContinuesStatement(const aText: string;
  const aOffset: Integer): Boolean;
var
  lNextOffset: Integer;
begin
  lNextOffset := NextNonWhitespaceOffset(aText, aOffset + 1);
  Result := IsWordAt(aText, lNextOffset, 'else');
end;

class function TRemoveWithDiscoveryHelper.FindStatementEndOffset(const aSource: TRemoveWithSourceBuffer;
  const aStartOffset: Integer): Integer;
var
  lBlockDepth: Integer;
  lBracketDepth: Integer;
  lOffset: Integer;
  lParenDepth: Integer;
begin
  Result := aStartOffset;
  lOffset := aStartOffset;
  lBlockDepth := 0;
  lParenDepth := 0;
  lBracketDepth := 0;
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

    if (lParenDepth = 0) and (lBracketDepth = 0) and
      (IsWordAt(aSource.fText, lOffset, 'begin') or IsWordAt(aSource.fText, lOffset, 'case') or
      IsWordAt(aSource.fText, lOffset, 'try') or IsWordAt(aSource.fText, lOffset, 'repeat')) then
    begin
      Inc(lBlockDepth);
      Inc(lOffset);
      Continue;
    end;

    if (lParenDepth = 0) and (lBracketDepth = 0) and
      (IsWordAt(aSource.fText, lOffset, 'end') or IsWordAt(aSource.fText, lOffset, 'until')) and
      (lBlockDepth > 0) then
    begin
      Dec(lBlockDepth);
      Inc(lOffset);
      Continue;
    end;

    if aSource.fText[lOffset] = '(' then
      Inc(lParenDepth)
    else if (aSource.fText[lOffset] = ')') and (lParenDepth > 0) then
      Dec(lParenDepth)
    else if aSource.fText[lOffset] = '[' then
      Inc(lBracketDepth)
    else if (aSource.fText[lOffset] = ']') and (lBracketDepth > 0) then
      Dec(lBracketDepth)
    else if (aSource.fText[lOffset] = ';') and (lParenDepth = 0) and (lBracketDepth = 0) and
      (lBlockDepth = 0) and not SemicolonContinuesStatement(aSource.fText, lOffset) then
      Exit(lOffset);
    Inc(lOffset);
  end;
end;

class function TRemoveWithDiscoveryHelper.NodeRange(const aNode: TSyntaxNode;
  const aSource: TRemoveWithSourceBuffer): TRemoveWithRange;
var
  lEndOffset: Integer;
  lStartOffset: Integer;
begin
  Result := Default(TRemoveWithRange);
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
    if RemoveWithOffsetForLineColumn(aSource, aNode.Line, aNode.Col, lStartOffset) then
    begin
      lEndOffset := FindStatementEndOffset(aSource, lStartOffset);
      RemoveWithLineColumnForOffset(aSource, lEndOffset, Result.fEndLine, Result.fEndColumn);
    end else
    begin
      Result.fEndLine := aNode.Line;
      Result.fEndColumn := aNode.Col;
    end;
  end;
end;

class procedure TRemoveWithDiscoveryHelper.AddFile(var aScanResult: TRemoveWithScanResult; const aPath: string;
  const aWithCount: Integer);
var
  lIndex: Integer;
begin
  lIndex := Length(aScanResult.fFiles);
  SetLength(aScanResult.fFiles, lIndex + 1);
  aScanResult.fFiles[lIndex].fPath := aPath;
  aScanResult.fFiles[lIndex].fScanned := True;
  aScanResult.fFiles[lIndex].fWithStatementCount := aWithCount;
end;

class procedure TRemoveWithDiscoveryHelper.AddWarning(var aScanResult: TRemoveWithScanResult; const aPath: string;
  const aLine, aColumn: Integer; const aCode, aMessage: string);
var
  lIndex: Integer;
begin
  lIndex := Length(aScanResult.fWarnings);
  SetLength(aScanResult.fWarnings, lIndex + 1);
  aScanResult.fWarnings[lIndex].fFilePath := aPath;
  aScanResult.fWarnings[lIndex].fLine := aLine;
  aScanResult.fWarnings[lIndex].fColumn := aColumn;
  aScanResult.fWarnings[lIndex].fCode := aCode;
  aScanResult.fWarnings[lIndex].fMessage := aMessage;
end;

class procedure TRemoveWithDiscoveryHelper.AddWithStatement(var aScanResult: TRemoveWithScanResult;
  const aInfo: TRemoveWithStatementInfo);
var
  lIndex: Integer;
begin
  lIndex := Length(aScanResult.fWithStatements);
  SetLength(aScanResult.fWithStatements, lIndex + 1);
  aScanResult.fWithStatements[lIndex] := aInfo;
end;

class procedure TRemoveWithDiscoveryHelper.CollectFromNode(const aNode: TSyntaxNode; const aFilePath: string;
  const aSource: TRemoveWithSourceBuffer; const aDepth: Integer; var aScanResult: TRemoveWithScanResult);
var
  lBodyNode: TSyntaxNode;
  lChild: TSyntaxNode;
  lInfo: TRemoveWithStatementInfo;
  lNextDepth: Integer;
  lUnsupportedRole: string;
begin
  if not Assigned(aNode) then
    Exit;

  lNextDepth := aDepth;
  if aNode.Typ = TSyntaxNodeType.ntWith then
  begin
    lBodyNode := FindBodyNode(aNode);
    lInfo := Default(TRemoveWithStatementInfo);
    lInfo.fId := 'with-' + IntToStr(Length(aScanResult.fWithStatements) + 1);
    lInfo.fFilePath := aFilePath;
    lInfo.fLine := aNode.Line;
    lInfo.fColumn := aNode.Col;
    if ExtractSelectorInfo(aSource, aNode.Line, aNode.Col, lInfo.fSelectorText, lInfo.fSelectorRange,
      lInfo.fSelectorCount,
      lInfo.fRange) then
    begin
      lInfo.fLine := lInfo.fRange.fStartLine;
      lInfo.fColumn := lInfo.fRange.fStartColumn;
    end else
      lInfo.fSelectorCount := CountSelectors(lInfo.fSelectorText);
    lInfo.fNestingDepth := aDepth;
    lInfo.fBodyRange := NodeRange(lBodyNode, aSource);
    lInfo.fHasScopedDeclarationInBody := BodyContainsScopedDeclaration(lBodyNode);
    lInfo.fHasUnsupportedIdentifierRoleInBody := BodyContainsUnsupportedIdentifierRole(lBodyNode,
      lInfo.fUnsupportedIdentifierRole);
    if (not lInfo.fHasUnsupportedIdentifierRoleInBody) and
      BodySourceContainsUnsupportedIdentifierRole(aSource, lInfo.fBodyRange, lUnsupportedRole) then
    begin
      lInfo.fHasUnsupportedIdentifierRoleInBody := True;
      lInfo.fUnsupportedIdentifierRole := lUnsupportedRole;
    end;
    if lInfo.fRange.fStartLine = 0 then
    begin
      lInfo.fRange.fStartLine := aNode.Line;
      lInfo.fRange.fStartColumn := aNode.Col;
    end;
    lInfo.fRange.fEndLine := lInfo.fBodyRange.fEndLine;
    lInfo.fRange.fEndColumn := lInfo.fBodyRange.fEndColumn;
    AddWithStatement(aScanResult, lInfo);
    lNextDepth := aDepth + 1;
  end;

  for lChild in aNode.ChildNodes do
  begin
    CollectFromNode(lChild, aFilePath, aSource, lNextDepth, aScanResult);
  end;
end;

class function TRemoveWithDiscoveryHelper.ShouldScanPath(const aOptions: TAppOptions; const aPath, aDirKey,
  aUnitKey: string): Boolean;
var
  lPathKey: string;
begin
  lPathKey := NormalizePathKey(aPath);
  if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtAll then
    Exit(True);
  if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtUnit then
    Exit(SameText(lPathKey, aUnitKey));
  if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtDir then
    Exit(StartsText(aDirKey, lPathKey));
  Result := False;
end;

class function TRemoveWithDiscoveryHelper.ShouldReportProblem(const aOptions: TAppOptions; const aProblemPath,
  aProjectDir, aDirKey, aUnitKey: string): Boolean;
var
  lProblemPath: string;
begin
  if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtAll then
    Exit(True);

  lProblemPath := Trim(aProblemPath);
  if lProblemPath = '' then
    Exit(False);
  if IsRootedPath(lProblemPath) then
    lProblemPath := TPath.GetFullPath(lProblemPath)
  else
    lProblemPath := TPath.GetFullPath(TPath.Combine(aProjectDir, lProblemPath));
  Result := ShouldScanPath(aOptions, lProblemPath, aDirKey, aUnitKey);
end;

class function TRemoveWithDiscoveryHelper.ProblemCode(const aProblemType: TProjectIndexer.TProblemType): string;
begin
  case aProblemType of
    TProjectIndexer.TProblemType.ptCantFindFile:
      Result := 'cant-find-file';
    TProjectIndexer.TProblemType.ptCantOpenFile:
      Result := 'cant-open-file';
  else
    Result := 'cant-parse-file';
  end;
end;

function DiscoverRemoveWithStatements(const aOptions: TAppOptions; const aProjectPath: string;
  out aScanResult: TRemoveWithScanResult; out aError: string): Boolean;
var
  lModel: TRemoveWithProjectModel;
begin
  lModel := nil;
  if not BuildRemoveWithProjectModel(aOptions, aProjectPath, lModel, aError) then
    Exit(False);
  try
    Result := DiscoverRemoveWithStatements(aOptions, lModel, aScanResult, aError);
  finally
    lModel.Free;
  end;
end;

function DiscoverRemoveWithStatements(const aOptions: TAppOptions; const aProjectModel: TRemoveWithProjectModel;
  out aScanResult: TRemoveWithScanResult; out aError: string): Boolean;
var
  lContext: TProjectAnalysisContext;
  lDirKey: string;
  lFilePath: string;
  lInitialWithCount: Integer;
  lProblem: TProjectIndexer.TProblemInfo;
  lSource: TRemoveWithSourceBuffer;
  lSourceError: string;
  lUnit: TProjectIndexer.TUnitInfo;
  lUnitKey: string;
begin
  aScanResult := Default(TRemoveWithScanResult);
  aError := '';
  lDirKey := '';
  lUnitKey := '';

  if not Assigned(aProjectModel) then
  begin
    aError := 'Remove-with project model is not assigned.';
    Exit(False);
  end;

  lContext := aProjectModel.Context;

  if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtUnit then
  begin
    if not TryResolveAbsolutePath(aOptions.fRemoveWithUnitPath, lFilePath, aError) then
      Exit(False);
    lUnitKey := TRemoveWithDiscoveryHelper.NormalizePathKey(lFilePath);
  end else if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtDir then
  begin
    if not TryResolveAbsolutePath(aOptions.fRemoveWithDirPath, lFilePath, aError) then
      Exit(False);
    lDirKey := IncludeTrailingPathDelimiter(TRemoveWithDiscoveryHelper.NormalizePathKey(lFilePath));
  end;

  for lProblem in aProjectModel.Indexer.Problems do
  begin
    if TRemoveWithDiscoveryHelper.ShouldReportProblem(aOptions, lProblem.FileName, lContext.fProjectDir, lDirKey,
      lUnitKey) then
    begin
      TRemoveWithDiscoveryHelper.AddWarning(aScanResult, lProblem.FileName, 0, 0,
        TRemoveWithDiscoveryHelper.ProblemCode(lProblem.ProblemType), lProblem.Description);
    end;
  end;

  for lUnit in aProjectModel.Indexer.ParsedUnits do
  begin
    lFilePath := Trim(lUnit.Path);
    if (lFilePath = '') or (not TFile.Exists(lFilePath)) then
      Continue;
    lFilePath := TPath.GetFullPath(lFilePath);
    if not TRemoveWithDiscoveryHelper.ShouldScanPath(aOptions, lFilePath, lDirKey, lUnitKey) then
      Continue;

    lInitialWithCount := Length(aScanResult.fWithStatements);
    if Assigned(lUnit.SyntaxTree) then
    begin
      if TRemoveWithDiscoveryHelper.ShouldScanPath(aOptions, lFilePath, lDirKey, lUnitKey) and
        LoadRemoveWithSource(lFilePath, lSource, lSourceError) then
        TRemoveWithDiscoveryHelper.CollectFromNode(lUnit.SyntaxTree, lFilePath, lSource, 0, aScanResult)
      else
        TRemoveWithDiscoveryHelper.AddWarning(aScanResult, lFilePath, 0, 0, 'source-read-failed',
          'Could not read source text for range extraction: ' + lSourceError);
    end
    else
      TRemoveWithDiscoveryHelper.AddWarning(aScanResult, lFilePath, 0, 0, 'missing-syntax-tree',
        'DelphiAST did not return a syntax tree for the selected file.');
    TRemoveWithDiscoveryHelper.AddFile(aScanResult, lFilePath,
      Length(aScanResult.fWithStatements) - lInitialWithCount);
  end;

  Result := True;
end;

end.
