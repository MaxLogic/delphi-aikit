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

  TRemoveWithPlanner = record
  private
    class function IsIdentifierChar(const aValue: Char): Boolean; static;
    class function SplitSelectorList(const aSelectorText: string): TArray<string>; static;
    class function StatementContains(const aOuter, aInner: TRemoveWithStatementInfo): Boolean; static;
    class function FindRoutineForStatement(const aInventory: TRemoveWithSymbolInventory;
      const aStatement: TRemoveWithStatementInfo; out aRoutineName: string): Boolean; static;
    class function FindRoutineLine(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
      aFilePath: string): Integer; static;
    class function RangeOffsets(const aSource: TRemoveWithSourceBuffer; const aRange: TRemoveWithRange;
      out aOffsets: TRemoveWithPlanOffsetRange): Boolean; static;
    class function SourceLineText(const aSource: TRemoveWithSourceBuffer; const aLine: Integer): string; static;
    class function IndentText(const aColumn: Integer): string; static;
    class function PreviousSignificantToken(const aSource: TRemoveWithSourceBuffer; const aOffset: Integer): string;
      static;
    class function StatementIsStandalone(const aSource: TRemoveWithSourceBuffer;
      const aStatement: TRemoveWithStatementInfo; out aReason: string): Boolean; static;
    class function TempInitializationText(const aStatement: TRemoveWithStatementInfo;
      const aSelectorTemps: TArray<TRemoveWithSelectorTemp>): string; static;
    class function TempDeclarationEdit(const aInventory: TRemoveWithSymbolInventory;
      const aSource: TRemoveWithSourceBuffer; const aStatement: TRemoveWithStatementInfo;
      const aRoutineName: string; const aSelectorTemps: TArray<TRemoveWithSelectorTemp>;
      out aEdit: TRemoveWithPlannedTextEdit): Boolean; static;
    class function HasNestedWith(const aScanResult: TRemoveWithScanResult;
      const aStatement: TRemoveWithStatementInfo): Boolean; static;
    class function FindClassification(const aResolverResult: TRemoveWithResolverResult; const aStatementId,
      aIdentifier: string; const aLine, aColumn: Integer;
      out aClassification: TRemoveWithIdentifierClassification): Boolean; static;
    class function FindSelectorTemp(const aSelectorTemps: TArray<TRemoveWithSelectorTemp>;
      const aSelectorText: string; out aSelectorTemp: TRemoveWithSelectorTemp): Boolean; static;
    class procedure AddStatement(var aPlanResult: TRemoveWithPlanResult;
      const aStatement: TRemoveWithPlannedStatement); static;
    class procedure AddEdit(var aStatement: TRemoveWithPlannedStatement;
      const aEdit: TRemoveWithPlannedTextEdit); static;
    class procedure AddTemp(var aStatement: TRemoveWithPlannedStatement;
      const aDecision: TRemoveWithTempDecision); static;
    class procedure AddSelectorTemp(var aSelectorTemps: TArray<TRemoveWithSelectorTemp>;
      const aSelectorTemp: TRemoveWithSelectorTemp); static;
    class procedure SkipStatement(var aPlanResult: TRemoveWithPlanResult; const aStatement: TRemoveWithStatementInfo;
      const aReason: string); static;
    class function BuildSelectorTemps(const aInventory: TRemoveWithSymbolInventory;
      const aStatement: TRemoveWithStatementInfo; const aRoutineName: string;
      out aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aReason: string): Boolean; static;
    class function RewrittenBodyText(const aSource: TRemoveWithSourceBuffer;
      const aStatement: TRemoveWithStatementInfo; const aResolverResult: TRemoveWithResolverResult;
      const aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aReplacementText, aReason: string): Boolean; static;
    class procedure PlanStatement(const aInventory: TRemoveWithSymbolInventory;
      const aScanResult: TRemoveWithScanResult; const aResolverResult: TRemoveWithResolverResult;
      const aStatement: TRemoveWithStatementInfo; const aSource: TRemoveWithSourceBuffer;
      var aPlanResult: TRemoveWithPlanResult); static;
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
  const aStatement: TRemoveWithStatementInfo; out aRoutineName: string): Boolean;
var
  lBestLine: Integer;
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  aRoutineName := '';
  lBestLine := 0;
  for lSymbol in aInventory.fSymbols do
  begin
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskRoutine) and SameText(lSymbol.fFilePath, aStatement.fFilePath) and
      (lSymbol.fLine <= aStatement.fLine) and (lSymbol.fLine > lBestLine) then
    begin
      lBestLine := lSymbol.fLine;
      aRoutineName := lSymbol.fName;
      Result := True;
    end;
  end;
end;

class function TRemoveWithPlanner.FindRoutineLine(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
  aFilePath: string): Integer;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  for lSymbol in aInventory.fSymbols do
  begin
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskRoutine) and SameText(lSymbol.fName, aRoutineName) and
      SameText(lSymbol.fFilePath, aFilePath) then
      Exit(lSymbol.fLine);
  end;
  Result := 0;
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

class function TRemoveWithPlanner.TempDeclarationEdit(const aInventory: TRemoveWithSymbolInventory;
  const aSource: TRemoveWithSourceBuffer; const aStatement: TRemoveWithStatementInfo; const aRoutineName: string;
  const aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aEdit: TRemoveWithPlannedTextEdit): Boolean;
var
  lBeginLine: Integer;
  lDeclarations: string;
  lDeclarationText: string;
  lHasVarSection: Boolean;
  lLine: Integer;
  lRoutineLine: Integer;
  lSelectorTemp: TRemoveWithSelectorTemp;
  lText: string;
begin
  Result := False;
  aEdit := Default(TRemoveWithPlannedTextEdit);
  if Length(aSelectorTemps) = 0 then
    Exit(False);

  lRoutineLine := FindRoutineLine(aInventory, aRoutineName, aStatement.fFilePath);
  if lRoutineLine = 0 then
    Exit(False);

  lBeginLine := 0;
  lHasVarSection := False;
  for lLine := lRoutineLine + 1 to aStatement.fLine do
  begin
    lText := Trim(SourceLineText(aSource, lLine));
    if SameText(lText, 'var') then
      lHasVarSection := True
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
  aEdit.fFilePath := aStatement.fFilePath;
  aEdit.fStatementId := aStatement.fId;
  aEdit.fRange.fStartLine := lBeginLine;
  aEdit.fRange.fStartColumn := 1;
  aEdit.fRange.fEndLine := lBeginLine;
  aEdit.fRange.fEndColumn := 1;
  aEdit.fReplacementText := lDeclarationText;
  Result := True;
end;

class function TRemoveWithPlanner.HasNestedWith(const aScanResult: TRemoveWithScanResult;
  const aStatement: TRemoveWithStatementInfo): Boolean;
var
  lStatement: TRemoveWithStatementInfo;
begin
  for lStatement in aScanResult.fWithStatements do
  begin
    if StatementContains(aStatement, lStatement) then
      Exit(True);
  end;
  Result := False;
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

class procedure TRemoveWithPlanner.SkipStatement(var aPlanResult: TRemoveWithPlanResult;
  const aStatement: TRemoveWithStatementInfo; const aReason: string);
var
  lPlannedStatement: TRemoveWithPlannedStatement;
begin
  lPlannedStatement := Default(TRemoveWithPlannedStatement);
  lPlannedStatement.fStatementId := aStatement.fId;
  lPlannedStatement.fFilePath := aStatement.fFilePath;
  lPlannedStatement.fStatus := 'skipped';
  lPlannedStatement.fReason := aReason;
  AddStatement(aPlanResult, lPlannedStatement);
end;

class function TRemoveWithPlanner.BuildSelectorTemps(const aInventory: TRemoveWithSymbolInventory;
  const aStatement: TRemoveWithStatementInfo; const aRoutineName: string;
  out aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aReason: string): Boolean;
var
  lDecision: TRemoveWithTempDecision;
  lReservedNames: TRemoveWithReservedTempNames;
  lSelector: string;
  lSelectorTemp: TRemoveWithSelectorTemp;
  lSelectors: TArray<string>;
begin
  Result := False;
  aReason := '';
  aSelectorTemps := nil;
  lReservedNames := Default(TRemoveWithReservedTempNames);
  lSelectors := SplitSelectorList(aStatement.fSelectorText);
  for lSelector in lSelectors do
  begin
    if not PlanRemoveWithTempPolicy(aInventory, aRoutineName, lSelector, lReservedNames, lDecision) then
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
  const aStatement: TRemoveWithStatementInfo; const aResolverResult: TRemoveWithResolverResult;
  const aSelectorTemps: TArray<TRemoveWithSelectorTemp>; out aReplacementText, aReason: string): Boolean;
var
  lBodyOffsets: TRemoveWithPlanOffsetRange;
  lClassification: TRemoveWithIdentifierClassification;
  lIdentifier: string;
  lLine: Integer;
  lColumn: Integer;
  lOffset: Integer;
  lQualifierText: string;
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

class procedure TRemoveWithPlanner.PlanStatement(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; const aResolverResult: TRemoveWithResolverResult;
  const aStatement: TRemoveWithStatementInfo; const aSource: TRemoveWithSourceBuffer;
  var aPlanResult: TRemoveWithPlanResult);
var
  lEdit: TRemoveWithPlannedTextEdit;
  lPlannedStatement: TRemoveWithPlannedStatement;
  lDeclarationEdit: TRemoveWithPlannedTextEdit;
  lReason: string;
  lReplacementText: string;
  lRoutineName: string;
  lSelectorTemp: TRemoveWithSelectorTemp;
  lSelectorTemps: TArray<TRemoveWithSelectorTemp>;
begin
  if HasNestedWith(aScanResult, aStatement) then
  begin
    SkipStatement(aPlanResult, aStatement, 'nested-with-not-planned');
    Exit;
  end;
  if not StatementIsStandalone(aSource, aStatement, lReason) then
  begin
    SkipStatement(aPlanResult, aStatement, lReason);
    Exit;
  end;

  if not FindRoutineForStatement(aInventory, aStatement, lRoutineName) then
    lRoutineName := '';
  if not BuildSelectorTemps(aInventory, aStatement, lRoutineName, lSelectorTemps, lReason) then
  begin
    SkipStatement(aPlanResult, aStatement, lReason);
    Exit;
  end;

  if not RewrittenBodyText(aSource, aStatement, aResolverResult, lSelectorTemps, lReplacementText, lReason) then
  begin
    SkipStatement(aPlanResult, aStatement, lReason);
    Exit;
  end;

  lPlannedStatement := Default(TRemoveWithPlannedStatement);
  lPlannedStatement.fStatementId := aStatement.fId;
  lPlannedStatement.fFilePath := aStatement.fFilePath;
  lPlannedStatement.fStatus := 'planned';
  lPlannedStatement.fReplacementText := TempInitializationText(aStatement, lSelectorTemps) +
    IndentText(aStatement.fColumn) + lReplacementText;
  for lSelectorTemp in lSelectorTemps do
    AddTemp(lPlannedStatement, lSelectorTemp.fDecision);

  if TempDeclarationEdit(aInventory, aSource, aStatement, lRoutineName, lSelectorTemps, lDeclarationEdit) then
    AddEdit(lPlannedStatement, lDeclarationEdit);

  lEdit := Default(TRemoveWithPlannedTextEdit);
  lEdit.fKind := 'replace-statement';
  lEdit.fFilePath := aStatement.fFilePath;
  lEdit.fStatementId := aStatement.fId;
  lEdit.fRange := aStatement.fRange;
  lEdit.fRange.fStartColumn := 1;
  lEdit.fReplacementText := lPlannedStatement.fReplacementText;
  AddEdit(lPlannedStatement, lEdit);
  AddStatement(aPlanResult, lPlannedStatement);
end;

class function TRemoveWithPlanner.Plan(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; const aResolverResult: TRemoveWithResolverResult;
  out aPlanResult: TRemoveWithPlanResult; out aError: string): Boolean;
var
  lCurrentPath: string;
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
      if not SameText(lCurrentPath, lStatement.fFilePath) then
      begin
        if not LoadRemoveWithSource(lStatement.fFilePath, lSource, aError) then
          Exit(False);
        lCurrentPath := lStatement.fFilePath;
      end;
      PlanStatement(aInventory, aScanResult, aResolverResult, lStatement, lSource, aPlanResult);
    end;
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
