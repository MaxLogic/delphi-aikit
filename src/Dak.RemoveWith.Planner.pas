unit Dak.RemoveWith.Planner;

interface

uses
  Dak.RemoveWith.Discovery, Dak.RemoveWith.Resolver, Dak.RemoveWith.Symbols, Dak.RemoveWith.TempPolicy;

type
  TRemoveWithPlannedTextEdit = record
    fKind: string;
    fFilePath: string;
    fStatementId: string;
    fRange: TRemoveWithRange;
    fReplacementText: string;
  end;

  TRemoveWithPlannedStatement = record
    fStatementId: string;
    fFilePath: string;
    fStatus: string;
    fReason: string;
    fUnsupportedIdentifierRole: string;
    fReplacementText: string;
    fEdits: TArray<TRemoveWithPlannedTextEdit>;
    fTemps: TArray<TRemoveWithTempDecision>;
  end;

  TRemoveWithPlanResult = record
    fStatements: TArray<TRemoveWithPlannedStatement>;
  end;

function PlanRemoveWithRewrites(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; const aResolverResult: TRemoveWithResolverResult;
  out aPlanResult: TRemoveWithPlanResult; out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  Dak.RemoveWith.Source;

type
  TRemoveWithPlanOffsetRange = record
    fStartOffset: Integer;
    fEndOffset: Integer;
  end;

  TRemoveWithSelectorTemp = record
    fSelectorText: string;
    fQualifierText: string;
    fDecision: TRemoveWithTempDecision;
  end;

  TRemoveWithNestedReplacement = record
    fOffsets: TRemoveWithPlanOffsetRange;
    fReplacementText: string;
  end;

  TRemoveWithRoutinePlanState = record
    fFilePath: string;
    fRoutineName: string;
    fRoutineLine: Integer;
    fFirstPlanIndex: Integer;
    fReservedNames: TRemoveWithReservedTempNames;
    fSelectorTemps: TArray<TRemoveWithSelectorTemp>;
  end;

  TRemoveWithPlanner = record
  private
    class function IsIdentifierChar(const aValue: Char): Boolean; static;
    class function SplitSelectorList(const aSelectorText: string): TArray<string>; static;
    class function StatementContains(const aOuter, aInner: TRemoveWithStatementInfo): Boolean; static;
    class function FindRoutineForStatement(const aInventory: TRemoveWithSymbolInventory;
      const aStatement: TRemoveWithStatementInfo; out aRoutineName: string; out aRoutineLine: Integer): Boolean;
      static;
    class function RangeOffsets(const aSource: TRemoveWithSourceBuffer; const aRange: TRemoveWithRange;
      out aOffsets: TRemoveWithPlanOffsetRange): Boolean; static;
    class function SourceLineText(const aSource: TRemoveWithSourceBuffer; const aLine: Integer): string; static;
    class function IndentText(const aColumn: Integer): string; static;
    class function IsLocalRoutineDeclaration(const aText: string): Boolean; static;
    class function PreviousSignificantToken(const aSource: TRemoveWithSourceBuffer; const aOffset: Integer): string;
      static;
    class function StatementIsStandalone(const aSource: TRemoveWithSourceBuffer;
      const aStatement: TRemoveWithStatementInfo; out aReason: string): Boolean; static;
    class function TempInitializationText(const aStatement: TRemoveWithStatementInfo;
      const aSelectorTemps: TArray<TRemoveWithSelectorTemp>): string; static;
    class function TempDeclarationEdit(const aSource: TRemoveWithSourceBuffer;
      const aFilePath, aStatementId: string; const aRoutineLine: Integer;
      const aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aEdit: TRemoveWithPlannedTextEdit): Boolean; static;
    class function HasPlannedAncestorWith(const aScanResult: TRemoveWithScanResult;
      const aPlanResult: TRemoveWithPlanResult; const aStatement: TRemoveWithStatementInfo): Boolean; static;
    class function HasAncestorWith(const aScanResult: TRemoveWithScanResult;
      const aStatement: TRemoveWithStatementInfo): Boolean; static;
    class function IsDirectNestedStatement(const aScanResult: TRemoveWithScanResult;
      const aOuter, aInner: TRemoveWithStatementInfo): Boolean; static;
    class function NestedReplacementAtOffset(const aNestedReplacements: TArray<TRemoveWithNestedReplacement>;
      const aOffset: Integer; out aNestedReplacement: TRemoveWithNestedReplacement): Boolean; static;
    class function FindClassification(const aResolverResult: TRemoveWithResolverResult; const aStatementId,
      aIdentifier: string; const aLine, aColumn: Integer;
      out aClassification: TRemoveWithIdentifierClassification): Boolean; static;
    class function FindSelectorTemp(const aSelectorTemps: TArray<TRemoveWithSelectorTemp>;
      const aSelectorText: string; out aSelectorTemp: TRemoveWithSelectorTemp): Boolean; static;
    class procedure AddStatement(var aPlanResult: TRemoveWithPlanResult;
      const aStatement: TRemoveWithPlannedStatement); static;
    class procedure AddEdit(var aStatement: TRemoveWithPlannedStatement;
      const aEdit: TRemoveWithPlannedTextEdit); static;
    class procedure PrependEdit(var aStatement: TRemoveWithPlannedStatement;
      const aEdit: TRemoveWithPlannedTextEdit); static;
    class procedure AddTemp(var aStatement: TRemoveWithPlannedStatement;
      const aDecision: TRemoveWithTempDecision); static;
    class procedure AddSelectorTemp(var aSelectorTemps: TArray<TRemoveWithSelectorTemp>;
      const aSelectorTemp: TRemoveWithSelectorTemp); static;
    class procedure AddSelectorTemps(var aSelectorTemps: TArray<TRemoveWithSelectorTemp>;
      const aSourceTemps: TArray<TRemoveWithSelectorTemp>); static;
    class function SelectorTempsNeedDeclaration(const aSelectorTemps: TArray<TRemoveWithSelectorTemp>): Boolean;
      static;
    class function UnsupportedRoleForStatement(const aResolverResult: TRemoveWithResolverResult;
      const aStatement: TRemoveWithStatementInfo): string; static;
    class procedure SkipStatement(var aPlanResult: TRemoveWithPlanResult; const aStatement: TRemoveWithStatementInfo;
      const aReason, aUnsupportedIdentifierRole: string); static;
    class function CopyReservedNames(const aReservedNames: TRemoveWithReservedTempNames): TRemoveWithReservedTempNames;
      static;
    class function SameRoutineState(const aState: TRemoveWithRoutinePlanState; const aFilePath: string;
      const aRoutineLine: Integer): Boolean; static;
    class function EnsureRoutineState(var aStates: TArray<TRemoveWithRoutinePlanState>; const aFilePath,
      aRoutineName: string; const aRoutineLine: Integer): Integer; static;
    class function BuildSelectorTemps(const aInventory: TRemoveWithSymbolInventory;
      const aStatement: TRemoveWithStatementInfo; const aRoutineName: string;
      var aReservedNames: TRemoveWithReservedTempNames;
      out aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aReason: string): Boolean; static;
    class function RewrittenBodyText(const aSource: TRemoveWithSourceBuffer;
      const aStatement: TRemoveWithStatementInfo;
      const aNestedReplacements: TArray<TRemoveWithNestedReplacement>; const aResolverResult: TRemoveWithResolverResult;
      const aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aReplacementText, aReason: string): Boolean; static;
    class function BuildStatementReplacement(const aInventory: TRemoveWithSymbolInventory;
      const aScanResult: TRemoveWithScanResult; const aResolverResult: TRemoveWithResolverResult;
      const aStatement: TRemoveWithStatementInfo; const aSource: TRemoveWithSourceBuffer;
      const aRoutineName: string; const aInheritedTemps: TArray<TRemoveWithSelectorTemp>;
      var aReservedNames: TRemoveWithReservedTempNames;
      out aReplacementText: string;
      out aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aReason: string): Boolean; static;
    class function AddRoutineDeclarationEdits(const aRoutineStates: TArray<TRemoveWithRoutinePlanState>;
      var aPlanResult: TRemoveWithPlanResult; out aError: string): Boolean; static;
    class procedure PlanStatement(const aInventory: TRemoveWithSymbolInventory;
      const aScanResult: TRemoveWithScanResult; const aResolverResult: TRemoveWithResolverResult;
      const aStatement: TRemoveWithStatementInfo; const aSource: TRemoveWithSourceBuffer;
      var aRoutineStates: TArray<TRemoveWithRoutinePlanState>; var aPlanResult: TRemoveWithPlanResult); static;
  public
    class function Plan(const aInventory: TRemoveWithSymbolInventory; const aScanResult: TRemoveWithScanResult;
      const aResolverResult: TRemoveWithResolverResult; out aPlanResult: TRemoveWithPlanResult;
      out aError: string): Boolean; static;
  end;

class function TRemoveWithPlanner.IsIdentifierChar(const aValue: Char): Boolean;
begin
  Result := CharInSet(aValue, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

class function TRemoveWithPlanner.SplitSelectorList(const aSelectorText: string): TArray<string>;
var
  lBracketDepth: Integer;
  lList: TList<string>;
  lParenDepth: Integer;
  lQuoteOpen: Boolean;
  lStart: Integer;
  i: Integer;
begin
  lList := TList<string>.Create;
  try
    lBracketDepth := 0;
    lParenDepth := 0;
    lQuoteOpen := False;
    lStart := 1;
    i := 1;
    while i <= Length(aSelectorText) do
    begin
      if aSelectorText[i] = '''' then
      begin
        if lQuoteOpen and (i < Length(aSelectorText)) and (aSelectorText[i + 1] = '''') then
        begin
          Inc(i, 2);
          Continue;
        end;
        lQuoteOpen := not lQuoteOpen;
      end else if not lQuoteOpen then
      begin
        if aSelectorText[i] = '[' then
          Inc(lBracketDepth)
        else if (aSelectorText[i] = ']') and (lBracketDepth > 0) then
          Dec(lBracketDepth)
        else if aSelectorText[i] = '(' then
          Inc(lParenDepth)
        else if (aSelectorText[i] = ')') and (lParenDepth > 0) then
          Dec(lParenDepth)
        else if (aSelectorText[i] = ',') and (lBracketDepth = 0) and (lParenDepth = 0) then
        begin
          lList.Add(Trim(Copy(aSelectorText, lStart, i - lStart)));
          lStart := i + 1;
        end;
      end;
      Inc(i);
    end;
    lList.Add(Trim(Copy(aSelectorText, lStart, MaxInt)));
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

class function TRemoveWithPlanner.StatementContains(const aOuter, aInner: TRemoveWithStatementInfo): Boolean;
begin
  if not SameText(aOuter.fFilePath, aInner.fFilePath) or SameText(aOuter.fId, aInner.fId) then
    Exit(False);

  Result := ((aOuter.fRange.fStartLine < aInner.fRange.fStartLine) or
    ((aOuter.fRange.fStartLine = aInner.fRange.fStartLine) and
    (aOuter.fRange.fStartColumn <= aInner.fRange.fStartColumn))) and
    ((aOuter.fRange.fEndLine > aInner.fRange.fEndLine) or
    ((aOuter.fRange.fEndLine = aInner.fRange.fEndLine) and
    (aOuter.fRange.fEndColumn >= aInner.fRange.fEndColumn)));
end;

class function TRemoveWithPlanner.FindRoutineForStatement(const aInventory: TRemoveWithSymbolInventory;
  const aStatement: TRemoveWithStatementInfo; out aRoutineName: string; out aRoutineLine: Integer): Boolean;
var
  lBestLine: Integer;
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  aRoutineName := '';
  aRoutineLine := 0;
  lBestLine := 0;
  for lSymbol in aInventory.fSymbols do
  begin
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskRoutine) and SameText(lSymbol.fFilePath, aStatement.fFilePath) and
      (lSymbol.fLine <= aStatement.fLine) and (lSymbol.fLine > lBestLine) then
    begin
      lBestLine := lSymbol.fLine;
      aRoutineName := lSymbol.fName;
      aRoutineLine := lSymbol.fLine;
      Result := True;
    end;
  end;
end;

class function TRemoveWithPlanner.RangeOffsets(const aSource: TRemoveWithSourceBuffer;
  const aRange: TRemoveWithRange; out aOffsets: TRemoveWithPlanOffsetRange): Boolean;
begin
  aOffsets := Default(TRemoveWithPlanOffsetRange);
  Result := RemoveWithOffsetForLineColumn(aSource, aRange.fStartLine, aRange.fStartColumn,
    aOffsets.fStartOffset) and RemoveWithOffsetForLineColumn(aSource, aRange.fEndLine, aRange.fEndColumn,
    aOffsets.fEndOffset);
end;

class function TRemoveWithPlanner.SourceLineText(const aSource: TRemoveWithSourceBuffer; const aLine: Integer): string;
var
  lEndOffset: Integer;
  lStartOffset: Integer;
begin
  Result := '';
  if (aLine < 1) or (aLine > Length(aSource.fLineStarts)) then
    Exit;
  lStartOffset := aSource.fLineStarts[aLine - 1];
  if aLine < Length(aSource.fLineStarts) then
    lEndOffset := aSource.fLineStarts[aLine] - 1
  else
    lEndOffset := Length(aSource.fText);
  while (lEndOffset >= lStartOffset) and CharInSet(aSource.fText[lEndOffset], [#10, #13]) do
    Dec(lEndOffset);
  if lEndOffset >= lStartOffset then
    Result := Copy(aSource.fText, lStartOffset, lEndOffset - lStartOffset + 1);
end;

class function TRemoveWithPlanner.IndentText(const aColumn: Integer): string;
begin
  if aColumn <= 1 then
    Exit('');
  Result := StringOfChar(' ', aColumn - 1);
end;

class function TRemoveWithPlanner.IsLocalRoutineDeclaration(const aText: string): Boolean;
begin
  Result := StartsText('procedure ', aText) or StartsText('function ', aText) or
    StartsText('constructor ', aText) or StartsText('destructor ', aText);
end;

class function TRemoveWithPlanner.PreviousSignificantToken(const aSource: TRemoveWithSourceBuffer;
  const aOffset: Integer): string;
var
  i: Integer;
  lStartOffset: Integer;
begin
  Result := '';
  i := 1;
  while i < aOffset do
  begin
    if CharInSet(aSource.fText[i], [#9, #10, #13, ' ']) then
    begin
      Inc(i);
      Continue;
    end;
    if aSource.fText[i] = '''' then
    begin
      Inc(i);
      while i < aOffset do
      begin
        if aSource.fText[i] = '''' then
        begin
          Inc(i);
          if (i < aOffset) and (aSource.fText[i] = '''') then
          begin
            Inc(i);
            Continue;
          end;
          Break;
        end;
        Inc(i);
      end;
      Continue;
    end;
    if aSource.fText[i] = '{' then
    begin
      Inc(i);
      while (i < aOffset) and (aSource.fText[i] <> '}') do
        Inc(i);
      Inc(i);
      Continue;
    end;
    if (i + 1 < aOffset) and (aSource.fText[i] = '(') and (aSource.fText[i + 1] = '*') then
    begin
      Inc(i, 2);
      while (i + 1 < aOffset) and ((aSource.fText[i] <> '*') or (aSource.fText[i + 1] <> ')')) do
        Inc(i);
      Inc(i, 2);
      Continue;
    end;
    if (i + 1 < aOffset) and (aSource.fText[i] = '/') and (aSource.fText[i + 1] = '/') then
    begin
      Inc(i, 2);
      while (i < aOffset) and not CharInSet(aSource.fText[i], [#10, #13]) do
        Inc(i);
      Continue;
    end;
    if CharInSet(aSource.fText[i], ['A'..'Z', 'a'..'z', '_']) then
    begin
      lStartOffset := i;
      while (i < aOffset) and IsIdentifierChar(aSource.fText[i]) do
        Inc(i);
      Result := LowerCase(Copy(aSource.fText, lStartOffset, i - lStartOffset));
      Continue;
    end;
    Result := aSource.fText[i];
    Inc(i);
  end;
end;

class function TRemoveWithPlanner.StatementIsStandalone(const aSource: TRemoveWithSourceBuffer;
  const aStatement: TRemoveWithStatementInfo; out aReason: string): Boolean;
var
  lLineText: string;
  lOffsets: TRemoveWithPlanOffsetRange;
  lPrefix: string;
  lToken: string;
begin
  aReason := '';
  Result := False;
  lLineText := SourceLineText(aSource, aStatement.fLine);
  lPrefix := Trim(Copy(lLineText, 1, aStatement.fColumn - 1));
  if lPrefix <> '' then
  begin
    aReason := 'prefixed-with-statement';
    Exit;
  end;

  if not RangeOffsets(aSource, aStatement.fRange, lOffsets) then
  begin
    aReason := 'statement-range-not-resolved';
    Exit;
  end;

  lToken := PreviousSignificantToken(aSource, lOffsets.fStartOffset);
  if not MatchText(lToken, [';', 'begin']) then
  begin
    aReason := 'controlled-with-statement';
    Exit;
  end;
  Result := True;
end;

class function TRemoveWithPlanner.TempInitializationText(const aStatement: TRemoveWithStatementInfo;
  const aSelectorTemps: TArray<TRemoveWithSelectorTemp>): string;
var
  lSelectorTemp: TRemoveWithSelectorTemp;
  lStatementIndent: string;
begin
  Result := '';
  lStatementIndent := IndentText(aStatement.fColumn);
  for lSelectorTemp in aSelectorTemps do
  begin
    if lSelectorTemp.fDecision.fInitializationText <> '' then
      Result := Result + lStatementIndent + lSelectorTemp.fDecision.fInitializationText + sLineBreak;
  end;
end;

class function TRemoveWithPlanner.TempDeclarationEdit(const aSource: TRemoveWithSourceBuffer;
  const aFilePath, aStatementId: string; const aRoutineLine: Integer;
  const aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aEdit: TRemoveWithPlannedTextEdit): Boolean;
var
  lBeginLine: Integer;
  lDeclarations: string;
  lDeclarationText: string;
  lHasVarSection: Boolean;
  lLine: Integer;
  lSelectorTemp: TRemoveWithSelectorTemp;
  lText: string;
begin
  Result := False;
  aEdit := Default(TRemoveWithPlannedTextEdit);
  if Length(aSelectorTemps) = 0 then
    Exit(False);

  if aRoutineLine = 0 then
    Exit(False);

  lBeginLine := 0;
  lHasVarSection := False;
  for lLine := aRoutineLine + 1 to Length(aSource.fLineStarts) do
  begin
    lText := Trim(SourceLineText(aSource, lLine));
    if SameText(lText, 'var') then
      lHasVarSection := True
    else if IsLocalRoutineDeclaration(lText) then
    begin
      lBeginLine := lLine;
      Break;
    end
    else if SameText(lText, 'begin') then
    begin
      lBeginLine := lLine;
      Break;
    end;
  end;
  if lBeginLine = 0 then
    Exit(False);

  lDeclarations := '';
  for lSelectorTemp in aSelectorTemps do
  begin
    if lSelectorTemp.fDecision.fDeclarationText <> '' then
      lDeclarations := lDeclarations + '  ' + lSelectorTemp.fDecision.fDeclarationText + sLineBreak;
  end;
  if lDeclarations = '' then
    Exit(False);
  if not lHasVarSection then
    lDeclarationText := 'var' + sLineBreak + lDeclarations
  else
    lDeclarationText := lDeclarations;

  aEdit.fKind := 'declare-temp';
  aEdit.fFilePath := aFilePath;
  aEdit.fStatementId := aStatementId;
  aEdit.fRange.fStartLine := lBeginLine;
  aEdit.fRange.fStartColumn := 1;
  aEdit.fRange.fEndLine := lBeginLine;
  aEdit.fRange.fEndColumn := 1;
  aEdit.fReplacementText := lDeclarationText;
  Result := True;
end;

class function TRemoveWithPlanner.HasPlannedAncestorWith(const aScanResult: TRemoveWithScanResult;
  const aPlanResult: TRemoveWithPlanResult; const aStatement: TRemoveWithStatementInfo): Boolean;
var
  lPlannedStatement: TRemoveWithPlannedStatement;
  lStatement: TRemoveWithStatementInfo;
begin
  for lPlannedStatement in aPlanResult.fStatements do
  begin
    if lPlannedStatement.fStatus <> 'planned' then
      Continue;
    for lStatement in aScanResult.fWithStatements do
    begin
      if SameText(lStatement.fId, lPlannedStatement.fStatementId) and StatementContains(lStatement, aStatement) then
        Exit(True);
    end;
  end;
  Result := False;
end;

class function TRemoveWithPlanner.HasAncestorWith(const aScanResult: TRemoveWithScanResult;
  const aStatement: TRemoveWithStatementInfo): Boolean;
var
  lStatement: TRemoveWithStatementInfo;
begin
  for lStatement in aScanResult.fWithStatements do
  begin
    if StatementContains(lStatement, aStatement) then
      Exit(True);
  end;
  Result := False;
end;

class function TRemoveWithPlanner.IsDirectNestedStatement(const aScanResult: TRemoveWithScanResult;
  const aOuter, aInner: TRemoveWithStatementInfo): Boolean;
var
  lStatement: TRemoveWithStatementInfo;
begin
  Result := False;
  if not StatementContains(aOuter, aInner) then
    Exit;

  for lStatement in aScanResult.fWithStatements do
  begin
    if SameText(lStatement.fId, aOuter.fId) or SameText(lStatement.fId, aInner.fId) then
      Continue;
    if StatementContains(aOuter, lStatement) and StatementContains(lStatement, aInner) then
      Exit(False);
  end;
  Result := True;
end;

class function TRemoveWithPlanner.NestedReplacementAtOffset(
  const aNestedReplacements: TArray<TRemoveWithNestedReplacement>; const aOffset: Integer;
  out aNestedReplacement: TRemoveWithNestedReplacement): Boolean;
var
  lReplacement: TRemoveWithNestedReplacement;
begin
  Result := False;
  aNestedReplacement := Default(TRemoveWithNestedReplacement);
  for lReplacement in aNestedReplacements do
  begin
    if (aOffset >= lReplacement.fOffsets.fStartOffset) and (aOffset <= lReplacement.fOffsets.fEndOffset) then
    begin
      aNestedReplacement := lReplacement;
      Exit(True);
    end;
  end;
end;

class function TRemoveWithPlanner.FindClassification(const aResolverResult: TRemoveWithResolverResult;
  const aStatementId, aIdentifier: string; const aLine, aColumn: Integer;
  out aClassification: TRemoveWithIdentifierClassification): Boolean;
var
  lClassification: TRemoveWithIdentifierClassification;
begin
  Result := False;
  aClassification := Default(TRemoveWithIdentifierClassification);
  for lClassification in aResolverResult.fClassifications do
  begin
    if SameText(lClassification.fStatementId, aStatementId) and SameText(lClassification.fIdentifier, aIdentifier) and
      (lClassification.fLine = aLine) and (lClassification.fColumn = aColumn) then
    begin
      aClassification := lClassification;
      Exit(True);
    end;
  end;
end;

class function TRemoveWithPlanner.FindSelectorTemp(const aSelectorTemps: TArray<TRemoveWithSelectorTemp>;
  const aSelectorText: string; out aSelectorTemp: TRemoveWithSelectorTemp): Boolean;
var
  lSelectorTemp: TRemoveWithSelectorTemp;
begin
  Result := False;
  aSelectorTemp := Default(TRemoveWithSelectorTemp);
  for lSelectorTemp in aSelectorTemps do
  begin
    if SameText(lSelectorTemp.fSelectorText, aSelectorText) then
    begin
      aSelectorTemp := lSelectorTemp;
      Exit(True);
    end;
  end;
end;

class procedure TRemoveWithPlanner.AddStatement(var aPlanResult: TRemoveWithPlanResult;
  const aStatement: TRemoveWithPlannedStatement);
var
  lIndex: Integer;
begin
  lIndex := Length(aPlanResult.fStatements);
  SetLength(aPlanResult.fStatements, lIndex + 1);
  aPlanResult.fStatements[lIndex] := aStatement;
end;

class procedure TRemoveWithPlanner.AddEdit(var aStatement: TRemoveWithPlannedStatement;
  const aEdit: TRemoveWithPlannedTextEdit);
var
  lIndex: Integer;
begin
  lIndex := Length(aStatement.fEdits);
  SetLength(aStatement.fEdits, lIndex + 1);
  aStatement.fEdits[lIndex] := aEdit;
end;

class procedure TRemoveWithPlanner.PrependEdit(var aStatement: TRemoveWithPlannedStatement;
  const aEdit: TRemoveWithPlannedTextEdit);
var
  i: Integer;
begin
  SetLength(aStatement.fEdits, Length(aStatement.fEdits) + 1);
  for i := High(aStatement.fEdits) downto 1 do
    aStatement.fEdits[i] := aStatement.fEdits[i - 1];
  aStatement.fEdits[0] := aEdit;
end;

class procedure TRemoveWithPlanner.AddTemp(var aStatement: TRemoveWithPlannedStatement;
  const aDecision: TRemoveWithTempDecision);
var
  lIndex: Integer;
begin
  if aDecision.fTempName = '' then
    Exit;
  lIndex := Length(aStatement.fTemps);
  SetLength(aStatement.fTemps, lIndex + 1);
  aStatement.fTemps[lIndex] := aDecision;
end;

class procedure TRemoveWithPlanner.AddSelectorTemp(var aSelectorTemps: TArray<TRemoveWithSelectorTemp>;
  const aSelectorTemp: TRemoveWithSelectorTemp);
var
  lIndex: Integer;
begin
  lIndex := Length(aSelectorTemps);
  SetLength(aSelectorTemps, lIndex + 1);
  aSelectorTemps[lIndex] := aSelectorTemp;
end;

class procedure TRemoveWithPlanner.AddSelectorTemps(var aSelectorTemps: TArray<TRemoveWithSelectorTemp>;
  const aSourceTemps: TArray<TRemoveWithSelectorTemp>);
var
  lSelectorTemp: TRemoveWithSelectorTemp;
begin
  for lSelectorTemp in aSourceTemps do
    AddSelectorTemp(aSelectorTemps, lSelectorTemp);
end;

class function TRemoveWithPlanner.SelectorTempsNeedDeclaration(
  const aSelectorTemps: TArray<TRemoveWithSelectorTemp>): Boolean;
var
  lSelectorTemp: TRemoveWithSelectorTemp;
begin
  for lSelectorTemp in aSelectorTemps do
  begin
    if lSelectorTemp.fDecision.fDeclarationText <> '' then
      Exit(True);
  end;
  Result := False;
end;

class function TRemoveWithPlanner.UnsupportedRoleForStatement(const aResolverResult: TRemoveWithResolverResult;
  const aStatement: TRemoveWithStatementInfo): string;
var
  lClassification: TRemoveWithIdentifierClassification;
begin
  Result := aStatement.fUnsupportedIdentifierRole;
  if Result <> '' then
    Exit;

  for lClassification in aResolverResult.fClassifications do
  begin
    if SameText(lClassification.fStatementId, aStatement.fId) and
      SameText(lClassification.fReason, 'unsupported-identifier-role') then
    begin
      Result := lClassification.fResolutionKind;
      if Result = '' then
        Result := 'unclassified';
      Exit;
    end;
  end;
end;

class procedure TRemoveWithPlanner.SkipStatement(var aPlanResult: TRemoveWithPlanResult;
  const aStatement: TRemoveWithStatementInfo; const aReason, aUnsupportedIdentifierRole: string);
var
  lPlannedStatement: TRemoveWithPlannedStatement;
begin
  lPlannedStatement := Default(TRemoveWithPlannedStatement);
  lPlannedStatement.fStatementId := aStatement.fId;
  lPlannedStatement.fFilePath := aStatement.fFilePath;
  lPlannedStatement.fStatus := 'skipped';
  lPlannedStatement.fReason := aReason;
  lPlannedStatement.fUnsupportedIdentifierRole := aUnsupportedIdentifierRole;
  AddStatement(aPlanResult, lPlannedStatement);
end;

class function TRemoveWithPlanner.CopyReservedNames(
  const aReservedNames: TRemoveWithReservedTempNames): TRemoveWithReservedTempNames;
begin
  Result := Default(TRemoveWithReservedTempNames);
  Result.fNames := Copy(aReservedNames.fNames);
end;

class function TRemoveWithPlanner.SameRoutineState(const aState: TRemoveWithRoutinePlanState;
  const aFilePath: string; const aRoutineLine: Integer): Boolean;
begin
  Result := SameText(aState.fFilePath, aFilePath) and (aState.fRoutineLine = aRoutineLine);
end;

class function TRemoveWithPlanner.EnsureRoutineState(var aStates: TArray<TRemoveWithRoutinePlanState>;
  const aFilePath, aRoutineName: string; const aRoutineLine: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(aStates) do
  begin
    if SameRoutineState(aStates[i], aFilePath, aRoutineLine) then
      Exit(i);
  end;

  Result := Length(aStates);
  SetLength(aStates, Result + 1);
  aStates[Result] := Default(TRemoveWithRoutinePlanState);
  aStates[Result].fFilePath := aFilePath;
  aStates[Result].fRoutineName := aRoutineName;
  aStates[Result].fRoutineLine := aRoutineLine;
  aStates[Result].fFirstPlanIndex := -1;
end;

class function TRemoveWithPlanner.BuildSelectorTemps(const aInventory: TRemoveWithSymbolInventory;
  const aStatement: TRemoveWithStatementInfo; const aRoutineName: string;
  var aReservedNames: TRemoveWithReservedTempNames; out aSelectorTemps: TArray<TRemoveWithSelectorTemp>;
  out aReason: string): Boolean;
var
  lDecision: TRemoveWithTempDecision;
  lSelector: string;
  lSelectorTemp: TRemoveWithSelectorTemp;
  lSelectors: TArray<string>;
begin
  Result := False;
  aReason := '';
  aSelectorTemps := nil;
  lSelectors := SplitSelectorList(aStatement.fSelectorText);
  for lSelector in lSelectors do
  begin
    if not PlanRemoveWithTempPolicy(aInventory, aRoutineName, lSelector, aReservedNames, lDecision) then
    begin
      aReason := 'selector-type-not-resolved';
      Exit;
    end;
    if lDecision.fStrategy = TRemoveWithTempStrategy.rwtsSkip then
    begin
      aReason := lDecision.fReason;
      Exit;
    end;

    lSelectorTemp := Default(TRemoveWithSelectorTemp);
    lSelectorTemp.fSelectorText := lSelector;
    lSelectorTemp.fQualifierText := lDecision.fQualifierText;
    lSelectorTemp.fDecision := lDecision;
    AddSelectorTemp(aSelectorTemps, lSelectorTemp);
  end;
  Result := True;
end;

class function TRemoveWithPlanner.RewrittenBodyText(const aSource: TRemoveWithSourceBuffer;
  const aStatement: TRemoveWithStatementInfo;
  const aNestedReplacements: TArray<TRemoveWithNestedReplacement>; const aResolverResult: TRemoveWithResolverResult;
  const aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aReplacementText, aReason: string): Boolean;
var
  lBodyOffsets: TRemoveWithPlanOffsetRange;
  lClassification: TRemoveWithIdentifierClassification;
  lIdentifier: string;
  lLine: Integer;
  lColumn: Integer;
  lNestedReplacement: TRemoveWithNestedReplacement;
  lOffset: Integer;
  lQualifierText: string;
  lRelativeStart: Integer;
  lSelectorTemp: TRemoveWithSelectorTemp;
  i: Integer;
begin
  Result := False;
  aReplacementText := '';
  aReason := '';
  if not RangeOffsets(aSource, aStatement.fBodyRange, lBodyOffsets) then
  begin
    aReason := 'body-range-not-resolved';
    Exit;
  end;

  aReplacementText := RemoveWithTextSlice(aSource, lBodyOffsets.fStartOffset, lBodyOffsets.fEndOffset);
  i := Length(aReplacementText);
  while i >= 1 do
  begin
    if NestedReplacementAtOffset(aNestedReplacements, lBodyOffsets.fStartOffset + i, lNestedReplacement) then
    begin
      lRelativeStart := lNestedReplacement.fOffsets.fStartOffset - lBodyOffsets.fStartOffset + 1;
      Delete(aReplacementText, lRelativeStart,
        lNestedReplacement.fOffsets.fEndOffset - lNestedReplacement.fOffsets.fStartOffset + 1);
      Insert(lNestedReplacement.fReplacementText, aReplacementText, lRelativeStart);
      i := lRelativeStart - 2;
      Continue;
    end;

    if not CharInSet(aReplacementText[i], ['A'..'Z', 'a'..'z', '_']) then
    begin
      Dec(i);
      Continue;
    end;

    lOffset := i;
    while (i >= 1) and IsIdentifierChar(aReplacementText[i]) do
      Dec(i);
    lIdentifier := Copy(aReplacementText, i + 1, lOffset - i);
    if not RemoveWithLineColumnForOffset(aSource, lBodyOffsets.fStartOffset + i, lLine, lColumn) then
    begin
      aReason := 'identifier-range-not-resolved';
      Exit;
    end;
    if FindClassification(aResolverResult, aStatement.fId, lIdentifier, lLine, lColumn, lClassification) then
    begin
      if lClassification.fStatus = TRemoveWithIdentifierStatus.rwisResolved then
      begin
        if FindSelectorTemp(aSelectorTemps, lClassification.fReceiverText, lSelectorTemp) then
          lQualifierText := lSelectorTemp.fQualifierText
        else
          lQualifierText := lClassification.fReceiverText;
        Delete(aReplacementText, i + 1, lOffset - i);
        Insert(lQualifierText + '.' + lIdentifier, aReplacementText, i + 1);
      end else if lClassification.fStatus <> TRemoveWithIdentifierStatus.rwisUnchanged then
      begin
        aReason := lClassification.fReason;
        if aReason = '' then
          aReason := RemoveWithIdentifierStatusToText(lClassification.fStatus);
        Exit;
      end;
    end;
  end;
  Result := True;
end;

class function TRemoveWithPlanner.BuildStatementReplacement(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; const aResolverResult: TRemoveWithResolverResult;
  const aStatement: TRemoveWithStatementInfo; const aSource: TRemoveWithSourceBuffer;
  const aRoutineName: string; const aInheritedTemps: TArray<TRemoveWithSelectorTemp>;
  var aReservedNames: TRemoveWithReservedTempNames; out aReplacementText: string;
  out aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aReason: string): Boolean;
var
  lChildReplacementText: string;
  lChildTemps: TArray<TRemoveWithSelectorTemp>;
  lCurrentTemps: TArray<TRemoveWithSelectorTemp>;
  lEditRange: TRemoveWithRange;
  lIndex: Integer;
  lNestedStatements: TArray<TRemoveWithStatementInfo>;
  lReplacement: TRemoveWithNestedReplacement;
  lReplacements: TArray<TRemoveWithNestedReplacement>;
  lStatement: TRemoveWithStatementInfo;
  lVisibleTemps: TArray<TRemoveWithSelectorTemp>;
begin
  Result := False;
  aReplacementText := '';
  aSelectorTemps := nil;
  aReason := '';

  if not StatementIsStandalone(aSource, aStatement, aReason) then
    Exit;
  if aStatement.fHasScopedDeclarationInBody then
  begin
    aReason := 'scoped-declaration-in-with-body';
    Exit;
  end;
  if aStatement.fHasUnsupportedIdentifierRoleInBody then
  begin
    aReason := 'unsupported-identifier-role';
    Exit;
  end;
  if not BuildSelectorTemps(aInventory, aStatement, aRoutineName, aReservedNames, lCurrentTemps, aReason) then
    Exit;
  AddSelectorTemps(lVisibleTemps, aInheritedTemps);
  AddSelectorTemps(lVisibleTemps, lCurrentTemps);

  for lStatement in aScanResult.fWithStatements do
  begin
    if not IsDirectNestedStatement(aScanResult, aStatement, lStatement) then
      Continue;
    lIndex := Length(lNestedStatements);
    SetLength(lNestedStatements, lIndex + 1);
    lNestedStatements[lIndex] := lStatement;
  end;

  AddSelectorTemps(aSelectorTemps, lCurrentTemps);
  for lStatement in lNestedStatements do
  begin
    if not BuildStatementReplacement(aInventory, aScanResult, aResolverResult, lStatement, aSource, aRoutineName,
      lVisibleTemps, aReservedNames, lChildReplacementText, lChildTemps, aReason) then
      Exit;

    lEditRange := lStatement.fRange;
    lEditRange.fStartColumn := 1;
    lReplacement := Default(TRemoveWithNestedReplacement);
    if not RangeOffsets(aSource, lEditRange, lReplacement.fOffsets) then
    begin
      aReason := 'nested-statement-range-not-resolved';
      Exit;
    end;
    lReplacement.fReplacementText := lChildReplacementText;
    lIndex := Length(lReplacements);
    SetLength(lReplacements, lIndex + 1);
    lReplacements[lIndex] := lReplacement;
    AddSelectorTemps(aSelectorTemps, lChildTemps);
  end;

  if not RewrittenBodyText(aSource, aStatement, lReplacements, aResolverResult, lVisibleTemps,
    aReplacementText, aReason) then
    Exit;

  aReplacementText := TempInitializationText(aStatement, lCurrentTemps) + IndentText(aStatement.fColumn) +
    aReplacementText;
  Result := True;
end;

class function TRemoveWithPlanner.AddRoutineDeclarationEdits(
  const aRoutineStates: TArray<TRemoveWithRoutinePlanState>; var aPlanResult: TRemoveWithPlanResult;
  out aError: string): Boolean;
var
  lDeclarationEdit: TRemoveWithPlannedTextEdit;
  lSource: TRemoveWithSourceBuffer;
  lState: TRemoveWithRoutinePlanState;
begin
  Result := False;
  aError := '';
  lSource := Default(TRemoveWithSourceBuffer);
  for lState in aRoutineStates do
  begin
    if (lState.fFirstPlanIndex < 0) or (lState.fFirstPlanIndex > High(aPlanResult.fStatements)) then
      Continue;
    if not SelectorTempsNeedDeclaration(lState.fSelectorTemps) then
      Continue;
    if not LoadRemoveWithSource(lState.fFilePath, lSource, aError) then
      Exit(False);
    if not TempDeclarationEdit(lSource, lState.fFilePath,
      aPlanResult.fStatements[lState.fFirstPlanIndex].fStatementId, lState.fRoutineLine, lState.fSelectorTemps,
      lDeclarationEdit) then
    begin
      aError := 'temp-declaration-insertion-not-resolved';
      Exit(False);
    end;
    PrependEdit(aPlanResult.fStatements[lState.fFirstPlanIndex], lDeclarationEdit);
  end;
  Result := True;
end;

class procedure TRemoveWithPlanner.PlanStatement(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; const aResolverResult: TRemoveWithResolverResult;
  const aStatement: TRemoveWithStatementInfo; const aSource: TRemoveWithSourceBuffer;
  var aRoutineStates: TArray<TRemoveWithRoutinePlanState>; var aPlanResult: TRemoveWithPlanResult);
var
  lEdit: TRemoveWithPlannedTextEdit;
  lPlannedStatement: TRemoveWithPlannedStatement;
  lPlanIndex: Integer;
  lReason: string;
  lReplacementText: string;
  lReservedNames: TRemoveWithReservedTempNames;
  lRoutineIndex: Integer;
  lRoutineLine: Integer;
  lRoutineName: string;
  lSelectorTemp: TRemoveWithSelectorTemp;
  lSelectorTemps: TArray<TRemoveWithSelectorTemp>;
begin
  if not FindRoutineForStatement(aInventory, aStatement, lRoutineName, lRoutineLine) then
  begin
    lRoutineName := '';
    lRoutineLine := 0;
  end;
  lRoutineIndex := EnsureRoutineState(aRoutineStates, aStatement.fFilePath, lRoutineName, lRoutineLine);
  lReservedNames := CopyReservedNames(aRoutineStates[lRoutineIndex].fReservedNames);
  if not BuildStatementReplacement(aInventory, aScanResult, aResolverResult, aStatement, aSource, lRoutineName, nil,
    lReservedNames, lReplacementText, lSelectorTemps, lReason) then
  begin
    SkipStatement(aPlanResult, aStatement, lReason, UnsupportedRoleForStatement(aResolverResult, aStatement));
    Exit;
  end;

  lPlannedStatement := Default(TRemoveWithPlannedStatement);
  lPlannedStatement.fStatementId := aStatement.fId;
  lPlannedStatement.fFilePath := aStatement.fFilePath;
  lPlannedStatement.fStatus := 'planned';
  lPlannedStatement.fReplacementText := lReplacementText;
  for lSelectorTemp in lSelectorTemps do
    AddTemp(lPlannedStatement, lSelectorTemp.fDecision);

  lEdit := Default(TRemoveWithPlannedTextEdit);
  lEdit.fKind := 'replace-statement';
  lEdit.fFilePath := aStatement.fFilePath;
  lEdit.fStatementId := aStatement.fId;
  lEdit.fRange := aStatement.fRange;
  lEdit.fRange.fStartColumn := 1;
  lEdit.fReplacementText := lPlannedStatement.fReplacementText;
  AddEdit(lPlannedStatement, lEdit);
  lPlanIndex := Length(aPlanResult.fStatements);
  AddStatement(aPlanResult, lPlannedStatement);
  aRoutineStates[lRoutineIndex].fReservedNames := lReservedNames;
  if aRoutineStates[lRoutineIndex].fFirstPlanIndex < 0 then
    aRoutineStates[lRoutineIndex].fFirstPlanIndex := lPlanIndex;
  AddSelectorTemps(aRoutineStates[lRoutineIndex].fSelectorTemps, lSelectorTemps);
end;

class function TRemoveWithPlanner.Plan(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; const aResolverResult: TRemoveWithResolverResult;
  out aPlanResult: TRemoveWithPlanResult; out aError: string): Boolean;
var
  lCurrentPath: string;
  lRoutineStates: TArray<TRemoveWithRoutinePlanState>;
  lSource: TRemoveWithSourceBuffer;
  lStatement: TRemoveWithStatementInfo;
begin
  aPlanResult := Default(TRemoveWithPlanResult);
  aError := '';
  Result := False;
  lCurrentPath := '';
  lSource := Default(TRemoveWithSourceBuffer);
  try
    for lStatement in aScanResult.fWithStatements do
    begin
      if HasPlannedAncestorWith(aScanResult, aPlanResult, lStatement) then
        Continue;
      if HasAncestorWith(aScanResult, lStatement) then
      begin
        SkipStatement(aPlanResult, lStatement, 'ancestor-with-not-planned', '');
        Continue;
      end;
      if lStatement.fHasScopedDeclarationInBody then
      begin
        SkipStatement(aPlanResult, lStatement, 'scoped-declaration-in-with-body',
          lStatement.fUnsupportedIdentifierRole);
        Continue;
      end;
      if lStatement.fHasUnsupportedIdentifierRoleInBody then
      begin
        SkipStatement(aPlanResult, lStatement, 'unsupported-identifier-role', lStatement.fUnsupportedIdentifierRole);
        Continue;
      end;
      if not SameText(lCurrentPath, lStatement.fFilePath) then
      begin
        if not LoadRemoveWithSource(lStatement.fFilePath, lSource, aError) then
          Exit(False);
        lCurrentPath := lStatement.fFilePath;
      end;
      PlanStatement(aInventory, aScanResult, aResolverResult, lStatement, lSource, lRoutineStates, aPlanResult);
    end;
    if not AddRoutineDeclarationEdits(lRoutineStates, aPlanResult, aError) then
      Exit(False);
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
end;

function PlanRemoveWithRewrites(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; const aResolverResult: TRemoveWithResolverResult;
  out aPlanResult: TRemoveWithPlanResult; out aError: string): Boolean;
begin
  Result := TRemoveWithPlanner.Plan(aInventory, aScanResult, aResolverResult, aPlanResult, aError);
end;

end.
