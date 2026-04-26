unit Dak.RemoveWith.Discovery;

interface

uses
  Dak.Types;

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
    fNestingDepth: Integer;
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
  out aScanResult: TRemoveWithScanResult; out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  DelphiAST.Classes, DelphiAST.Consts, DelphiAST.ProjectIndexer,
  Dak.Project, Dak.Utils;

type
  TRemoveWithDiscoveryHelper = record
  private
    class function NormalizePathKey(const aPath: string): string; static;
    class function IsCommentNode(const aNode: TSyntaxNode): Boolean; static;
    class function IsIdentifierChar(const aValue: Char): Boolean; static;
    class function FindWithKeyword(const aLine: string; const aStartColumn: Integer): Integer; static;
    class function CountSelectors(const aSelectorText: string): Integer; static;
    class function IsRootedPath(const aPath: string): Boolean; static;
    class function ExtractSelectorText(const aLines: TArray<string>; const aLine, aColumn: Integer): string; static;
    class function FindBodyNode(const aWithNode: TSyntaxNode): TSyntaxNode; static;
    class function NodeRange(const aNode: TSyntaxNode): TRemoveWithRange; static;
    class procedure AddFile(var aScanResult: TRemoveWithScanResult; const aPath: string; const aWithCount: Integer);
      static;
    class procedure AddWarning(var aScanResult: TRemoveWithScanResult; const aPath: string; const aLine,
      aColumn: Integer; const aCode, aMessage: string); static;
    class procedure AddWithStatement(var aScanResult: TRemoveWithScanResult; const aInfo: TRemoveWithStatementInfo);
      static;
    class procedure CollectFromNode(const aNode: TSyntaxNode; const aFilePath: string; const aLines: TArray<string>;
      const aDepth: Integer; var aScanResult: TRemoveWithScanResult); static;
    class function ShouldScanPath(const aOptions: TAppOptions; const aPath, aDirKey, aUnitKey: string): Boolean; static;
    class function ShouldReportProblem(const aOptions: TAppOptions; const aProblemPath, aProjectDir, aDirKey,
      aUnitKey: string): Boolean; static;
    class function ProblemCode(const aProblemType: TProjectIndexer.TProblemType): string; static;
  end;

class function TRemoveWithDiscoveryHelper.NormalizePathKey(const aPath: string): string;
begin
  Result := AnsiLowerCase(TPath.GetFullPath(aPath));
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

class function TRemoveWithDiscoveryHelper.FindWithKeyword(const aLine: string; const aStartColumn: Integer): Integer;
var
  lIndex: Integer;
  lStart: Integer;
begin
  Result := 0;
  lStart := aStartColumn;
  if lStart < 1 then
    lStart := 1;

  for lIndex := lStart to Length(aLine) - 3 do
  begin
    if SameText(Copy(aLine, lIndex, 4), 'with') and
      ((lIndex = 1) or (not IsIdentifierChar(aLine[lIndex - 1]))) and
      ((lIndex + 4 > Length(aLine)) or (not IsIdentifierChar(aLine[lIndex + 4]))) then
      Exit(lIndex);
  end;
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
  for lIndex := 1 to Length(aSelectorText) do
  begin
    if aSelectorText[lIndex] = '''' then
    begin
      lQuoteOpen := not lQuoteOpen;
      Continue;
    end;

    if lQuoteOpen then
      Continue;
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
  end;
end;

class function TRemoveWithDiscoveryHelper.IsRootedPath(const aPath: string): Boolean;
begin
  Result := (aPath <> '') and (TPath.IsPathRooted(aPath) or ((Length(aPath) >= 3) and (aPath[2] = ':')));
end;

class function TRemoveWithDiscoveryHelper.ExtractSelectorText(const aLines: TArray<string>; const aLine,
  aColumn: Integer): string;
var
  lBracketDepth: Integer;
  lBuilder: TStringBuilder;
  lCharIndex: Integer;
  lLineIndex: Integer;
  lLineText: string;
  lParenDepth: Integer;
  lQuoteOpen: Boolean;
  lStartColumn: Integer;
  lWithIndex: Integer;
begin
  Result := '';
  if (aLine < 1) or (aLine > Length(aLines)) then
    Exit;

  lLineText := aLines[aLine - 1];
  lWithIndex := FindWithKeyword(lLineText, aColumn);
  if lWithIndex = 0 then
    Exit;

  lBuilder := TStringBuilder.Create;
  try
    lParenDepth := 0;
    lBracketDepth := 0;
    lQuoteOpen := False;
    for lLineIndex := aLine to Length(aLines) do
    begin
      lLineText := aLines[lLineIndex - 1];
      if lLineIndex = aLine then
        lStartColumn := lWithIndex + 4
      else
      begin
        lStartColumn := 1;
        if lBuilder.Length > 0 then
          lBuilder.Append(' ');
      end;

      lCharIndex := lStartColumn;
      while (lLineIndex > aLine) and (lCharIndex <= Length(lLineText)) and CharInSet(lLineText[lCharIndex], [#9, ' ']) do
        Inc(lCharIndex);

      while lCharIndex <= Length(lLineText) do
      begin
        if lLineText[lCharIndex] = '''' then
        begin
          lBuilder.Append(lLineText[lCharIndex]);
          if (lCharIndex < Length(lLineText)) and (lLineText[lCharIndex + 1] = '''') then
          begin
            Inc(lCharIndex);
            lBuilder.Append(lLineText[lCharIndex]);
          end else
            lQuoteOpen := not lQuoteOpen;
          Inc(lCharIndex);
          Continue;
        end;

        if not lQuoteOpen then
        begin
          if (lParenDepth = 0) and (lBracketDepth = 0) and SameText(Copy(lLineText, lCharIndex, 2), 'do') and
            ((lCharIndex = 1) or (not IsIdentifierChar(lLineText[lCharIndex - 1]))) and
            ((lCharIndex + 2 > Length(lLineText)) or (not IsIdentifierChar(lLineText[lCharIndex + 2]))) then
            Exit(Trim(lBuilder.ToString));

          if lLineText[lCharIndex] = '(' then
            Inc(lParenDepth)
          else if (lLineText[lCharIndex] = ')') and (lParenDepth > 0) then
            Dec(lParenDepth)
          else if lLineText[lCharIndex] = '[' then
            Inc(lBracketDepth)
          else if (lLineText[lCharIndex] = ']') and (lBracketDepth > 0) then
            Dec(lBracketDepth);
        end;

        lBuilder.Append(lLineText[lCharIndex]);
        Inc(lCharIndex);
      end;
    end;
    Result := Trim(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
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

class function TRemoveWithDiscoveryHelper.NodeRange(const aNode: TSyntaxNode): TRemoveWithRange;
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
    Result.fEndLine := aNode.Line;
    Result.fEndColumn := aNode.Col;
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
  const aLines: TArray<string>; const aDepth: Integer; var aScanResult: TRemoveWithScanResult);
var
  lBodyNode: TSyntaxNode;
  lChild: TSyntaxNode;
  lInfo: TRemoveWithStatementInfo;
  lNextDepth: Integer;
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
    lInfo.fSelectorText := ExtractSelectorText(aLines, aNode.Line, aNode.Col);
    lInfo.fSelectorCount := CountSelectors(lInfo.fSelectorText);
    lInfo.fNestingDepth := aDepth;
    lInfo.fBodyRange := NodeRange(lBodyNode);
    lInfo.fRange.fStartLine := aNode.Line;
    lInfo.fRange.fStartColumn := aNode.Col;
    lInfo.fRange.fEndLine := lInfo.fBodyRange.fEndLine;
    lInfo.fRange.fEndColumn := lInfo.fBodyRange.fEndColumn;
    AddWithStatement(aScanResult, lInfo);
    lNextDepth := aDepth + 1;
  end;

  for lChild in aNode.ChildNodes do
  begin
    CollectFromNode(lChild, aFilePath, aLines, lNextDepth, aScanResult);
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
  lContext: TProjectAnalysisContext;
  lDirKey: string;
  lFilePath: string;
  lIndexer: TProjectIndexer;
  lInitialWithCount: Integer;
  lProblem: TProjectIndexer.TProblemInfo;
  lUnit: TProjectIndexer.TUnitInfo;
  lUnitKey: string;
begin
  aScanResult := Default(TRemoveWithScanResult);
  aError := '';
  lDirKey := '';
  lUnitKey := '';

  if not TryBuildProjectAnalysisContext(aOptions, lContext, aError) then
    Exit(False);

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

  lIndexer := TProjectIndexer.Create;
  try
    lIndexer.Defines := lContext.fParserDefines;
    lIndexer.SearchPath := lContext.fParserSearchPath;
    lIndexer.Index(lContext.fMainSourcePath);

    for lProblem in lIndexer.Problems do
    begin
      if TRemoveWithDiscoveryHelper.ShouldReportProblem(aOptions, lProblem.FileName, lContext.fProjectDir, lDirKey,
        lUnitKey) then
      begin
        TRemoveWithDiscoveryHelper.AddWarning(aScanResult, lProblem.FileName, 0, 0,
          TRemoveWithDiscoveryHelper.ProblemCode(lProblem.ProblemType), lProblem.Description);
      end;
    end;

    for lUnit in lIndexer.ParsedUnits do
    begin
      lFilePath := Trim(lUnit.Path);
      if (lFilePath = '') or (not TFile.Exists(lFilePath)) then
        Continue;
      lFilePath := TPath.GetFullPath(lFilePath);
      if not TRemoveWithDiscoveryHelper.ShouldScanPath(aOptions, lFilePath, lDirKey, lUnitKey) then
        Continue;

      lInitialWithCount := Length(aScanResult.fWithStatements);
      if Assigned(lUnit.SyntaxTree) then
        TRemoveWithDiscoveryHelper.CollectFromNode(lUnit.SyntaxTree, lFilePath, TFile.ReadAllLines(lFilePath), 0,
          aScanResult)
      else
        TRemoveWithDiscoveryHelper.AddWarning(aScanResult, lFilePath, 0, 0, 'missing-syntax-tree',
          'DelphiAST did not return a syntax tree for the selected file.');
      TRemoveWithDiscoveryHelper.AddFile(aScanResult, lFilePath,
        Length(aScanResult.fWithStatements) - lInitialWithCount);
    end;
  finally
    lIndexer.Free;
  end;

  Result := True;
end;

end.
