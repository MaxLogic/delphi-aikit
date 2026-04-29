unit Dak.RemoveWith.Resolver;

interface

uses
  Dak.RemoveWith.Discovery, Dak.RemoveWith.Symbols;

type
  TRemoveWithIdentifierStatus = (rwisResolved, rwisUnchanged, rwisExternal, rwisUnsupported, rwisUnresolved,
    rwisAmbiguousToDak);

  TRemoveWithIdentifierClassification = record
    fStatementId: string;
    fFilePath: string;
    fIdentifier: string;
    fReceiverText: string;
    fReceiverType: string;
    fResolutionKind: string;
    fSourceOwnerType: string;
    fMemberKind: TRemoveWithSymbolKind;
    fReason: string;
    fLine: Integer;
    fColumn: Integer;
    fStatus: TRemoveWithIdentifierStatus;
  end;

  TRemoveWithResolverResult = record
    fClassifications: TArray<TRemoveWithIdentifierClassification>;
  end;

function RemoveWithIdentifierStatusToText(const aStatus: TRemoveWithIdentifierStatus): string;
function ResolveRemoveWithIdentifiers(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; out aResult: TRemoveWithResolverResult; out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  MaxLogic.StrUtils,
  Dak.RemoveWith.Expressions, Dak.RemoveWith.Source;

type
  TRemoveWithReceiverScope = record
    fSelectorText: string;
    fTypeName: string;
    fReason: string;
    fStatus: TRemoveWithSelectorTypeStatus;
  end;

  TRemoveWithIdentifierUse = record
    fName: string;
    fLine: Integer;
    fColumn: Integer;
    fStartOffset: Integer;
    fEndOffset: Integer;
  end;

  TRemoveWithOffsetRange = record
    fStartOffset: Integer;
    fEndOffset: Integer;
  end;

  TRemoveWithSymbolLookup = record
    fFound: Boolean;
    fSymbol: TRemoveWithSymbolInfo;
  end;

  TRemoveWithTextLookup = record
    fFound: Boolean;
    fText: string;
  end;

  TRemoveWithIdentifierResolver = record
  private
    class function DirectTypeName(const aTypeName: string): string; static;
    class function ElementTypeName(const aTypeName: string): string; static;
    class function IsDirectMemberKind(const aKind: TRemoveWithSymbolKind): Boolean; static;
    class function IsIdentifierChar(const aValue: Char): Boolean; static;
    class function IsKeyword(const aName: string): Boolean; static;
    class function IsWhitespace(const aValue: Char): Boolean; static;
    class function PreviousNonWhitespaceChar(const aText: string; const aOffset: Integer): Char; static;
    class function NextNonWhitespaceChar(const aText: string; const aOffset: Integer): Char; static;
    class function LastIdentifierSegment(const aText: string): string; static;
    class function ArrayElementTypeName(const aInventory: TRemoveWithSymbolInventory;
      const aTypeName: string): string; static;
    class function SelectorSegmentName(const aText: string): string; static;
    class function SelectorSegmentDerefAfterIndex(const aText: string): Boolean; static;
    class function SelectorSegmentDerefBeforeIndex(const aText: string): Boolean; static;
    class function SelectorSegmentIndexed(const aText: string): Boolean; static;
    class function StatementContains(const aOuter, aInner: TRemoveWithStatementInfo): Boolean; static;
    class function RangeOffsets(const aSource: TRemoveWithSourceBuffer; const aRange: TRemoveWithRange;
      out aOffsets: TRemoveWithOffsetRange): Boolean; static;
    class function OffsetInRanges(const aOffset: Integer; const aRanges: TArray<TRemoveWithOffsetRange>): Boolean;
      static;
    class function SplitSelectorList(const aSelectorText: string): TArray<string>; static;
    class function SplitSelectorPath(const aSelectorText: string): TArray<string>; static;
    class function FindRoutineForStatement(const aInventory: TRemoveWithSymbolInventory;
      const aStatement: TRemoveWithStatementInfo; out aRoutineName: string): Boolean; static;
    class function FindMemberCandidates(const aInventory: TRemoveWithSymbolInventory; const aOwnerType,
      aName: string): TArray<TRemoveWithSymbolInfo>; static;
    class function FindDefaultPropertyCandidate(const aInventory: TRemoveWithSymbolInventory;
      const aOwnerType: string): Boolean; static;
    class function FindScopeSymbol(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
      aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindUnitNameSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindExternalUnitSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindTypeNameSymbol(const aInventory: TRemoveWithSymbolInventory; const aName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function HasSourceType(const aInventory: TRemoveWithSymbolInventory; const aTypeName: string): Boolean;
      static;
    class function IsExternalType(const aInventory: TRemoveWithSymbolInventory; const aTypeName: string): Boolean;
      static;
    class function HasExternalAncestor(const aInventory: TRemoveWithSymbolInventory; const aTypeName: string): Boolean;
      static;
    class function PointerTargetType(const aInventory: TRemoveWithSymbolInventory; const aTypeName: string): string;
      static;
    class function IsHelperType(const aInventory: TRemoveWithSymbolInventory; const aTypeName: string): Boolean;
      static;
    class function FindAncestorMember(const aInventory: TRemoveWithSymbolInventory; const aOwnerType,
      aName: string; out aSourceOwnerType: string): Boolean; static;
    class function ResolutionKindForCandidate(const aInventory: TRemoveWithSymbolInventory; const aReceiverType: string;
      const aCandidate: TRemoveWithSymbolInfo; out aSourceOwnerType: string): string; static;
    class function AllCandidatesAreMethods(const aCandidates: TArray<TRemoveWithSymbolInfo>): Boolean; static;
    class function CandidatesShareSourceOwner(const aCandidates: TArray<TRemoveWithSymbolInfo>): Boolean; static;
    class function IsCallUse(const aSource: TRemoveWithSourceBuffer; const aUse: TRemoveWithIdentifierUse): Boolean;
      static;
    class function IsKnownExternalRoutineCall(const aSource: TRemoveWithSourceBuffer;
      const aUse: TRemoveWithIdentifierUse): Boolean; static;
    class function IsQualifiedUse(const aSource: TRemoveWithSourceBuffer; const aUse: TRemoveWithIdentifierUse):
      Boolean; static;
    class function ResolveSelectorFromReceivers(const aInventory: TRemoveWithSymbolInventory;
      const aReceivers: TArray<TRemoveWithReceiverScope>; const aSelectorText: string;
      out aInfo: TRemoveWithSelectorTypeInfo): Boolean; static;
    class function SelectorUsesUnsupportedProperty(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
      aSelectorText: string): Boolean; static;
    class procedure NormalizeSelectorInfo(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
      aSelectorText: string; var aInfo: TRemoveWithSelectorTypeInfo); static;
    class procedure AddClassification(var aResult: TRemoveWithResolverResult;
      const aClassification: TRemoveWithIdentifierClassification); static;
    class procedure CollectIdentifierUses(const aSource: TRemoveWithSourceBuffer;
      const aBodyOffsets: TRemoveWithOffsetRange; const aSkipRanges: TArray<TRemoveWithOffsetRange>;
      out aUses: TArray<TRemoveWithIdentifierUse>); static;
    class procedure BuildReceiverStack(const aInventory: TRemoveWithSymbolInventory;
      const aScanResult: TRemoveWithScanResult; const aStatement: TRemoveWithStatementInfo;
      const aRoutineName: string; out aReceivers: TArray<TRemoveWithReceiverScope>); static;
    class function ClassifyUse(const aInventory: TRemoveWithSymbolInventory; const aSource: TRemoveWithSourceBuffer;
      const aRoutineName: string; const aReceivers: TArray<TRemoveWithReceiverScope>;
      const aUse: TRemoveWithIdentifierUse; out aClassification: TRemoveWithIdentifierClassification): Boolean;
      static;
    class procedure ResolveStatement(const aInventory: TRemoveWithSymbolInventory;
      const aScanResult: TRemoveWithScanResult; const aStatement: TRemoveWithStatementInfo;
      const aSource: TRemoveWithSourceBuffer; var aResult: TRemoveWithResolverResult); static;
  public
    class function Resolve(const aInventory: TRemoveWithSymbolInventory; const aScanResult: TRemoveWithScanResult;
      out aResult: TRemoveWithResolverResult; out aError: string): Boolean; static;
  end;

var
  GResolverAncestorMemberCache: TDictionary<string, TRemoveWithTextLookup>;
  GResolverBoolCache: TDictionary<string, Boolean>;
  GResolverExternalUnitCache: TDictionary<string, TRemoveWithSymbolLookup>;
  GResolverMemberCandidateCache: TDictionary<string, TArray<TRemoveWithSymbolInfo>>;
  GResolverScopeSymbolCache: TDictionary<string, TRemoveWithSymbolLookup>;
  GResolverSymbolNameIndex: TDictionary<string, TArray<TRemoveWithSymbolInfo>>;
  GResolverTypeNameCache: TDictionary<string, TRemoveWithSymbolLookup>;
  GResolverUnitNameCache: TDictionary<string, TRemoveWithSymbolLookup>;

function ResolverCacheKey(const aFirst, aSecond: string): string; overload;
const
  cSeparator = #31;
begin
  Result := aFirst + cSeparator + aSecond;
end;

function ResolverCacheKey(const aFirst, aSecond, aThird: string): string; overload;
const
  cSeparator = #31;
begin
  Result := aFirst + cSeparator + aSecond + cSeparator + aThird;
end;

procedure BeginResolverCache;
begin
  GResolverAncestorMemberCache := TDictionary<string, TRemoveWithTextLookup>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  GResolverBoolCache := TDictionary<string, Boolean>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  GResolverExternalUnitCache := TDictionary<string, TRemoveWithSymbolLookup>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  GResolverMemberCandidateCache := TDictionary<string, TArray<TRemoveWithSymbolInfo>>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  GResolverScopeSymbolCache := TDictionary<string, TRemoveWithSymbolLookup>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  GResolverSymbolNameIndex := nil;
  GResolverTypeNameCache := TDictionary<string, TRemoveWithSymbolLookup>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  GResolverUnitNameCache := TDictionary<string, TRemoveWithSymbolLookup>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
end;

procedure EndResolverCache;
begin
  GResolverUnitNameCache.Free;
  GResolverUnitNameCache := nil;
  GResolverTypeNameCache.Free;
  GResolverTypeNameCache := nil;
  GResolverScopeSymbolCache.Free;
  GResolverScopeSymbolCache := nil;
  GResolverSymbolNameIndex.Free;
  GResolverSymbolNameIndex := nil;
  GResolverMemberCandidateCache.Free;
  GResolverMemberCandidateCache := nil;
  GResolverExternalUnitCache.Free;
  GResolverExternalUnitCache := nil;
  GResolverBoolCache.Free;
  GResolverBoolCache := nil;
  GResolverAncestorMemberCache.Free;
  GResolverAncestorMemberCache := nil;
end;

procedure EnsureResolverSymbolNameIndex(const aInventory: TRemoveWithSymbolInventory);
var
  lBuckets: TDictionary<string, TList<TRemoveWithSymbolInfo>>;
  lIndex: TDictionary<string, TArray<TRemoveWithSymbolInfo>>;
  lList: TList<TRemoveWithSymbolInfo>;
  lPair: TPair<string, TList<TRemoveWithSymbolInfo>>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if GResolverSymbolNameIndex <> nil then
    Exit;

  lBuckets := TDictionary<string, TList<TRemoveWithSymbolInfo>>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for lSymbol in aInventory.fSymbols do
    begin
      if lSymbol.fName = '' then
        Continue;
      if not lBuckets.TryGetValue(lSymbol.fName, lList) then
      begin
        lList := TList<TRemoveWithSymbolInfo>.Create;
        lBuckets.Add(lSymbol.fName, lList);
      end;
      lList.Add(lSymbol);
    end;

    lIndex := TDictionary<string, TArray<TRemoveWithSymbolInfo>>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
    try
      for lPair in lBuckets do
        lIndex.Add(lPair.Key, lPair.Value.ToArray);
      GResolverSymbolNameIndex := lIndex;
      lIndex := nil;
    finally
      lIndex.Free;
    end;
  finally
    for lPair in lBuckets do
      lPair.Value.Free;
    lBuckets.Free;
  end;
end;

function RemoveWithIdentifierStatusToText(const aStatus: TRemoveWithIdentifierStatus): string;
begin
  case aStatus of
    TRemoveWithIdentifierStatus.rwisResolved:
      Result := 'resolved';
    TRemoveWithIdentifierStatus.rwisUnchanged:
      Result := 'unchanged';
    TRemoveWithIdentifierStatus.rwisExternal:
      Result := 'external';
    TRemoveWithIdentifierStatus.rwisUnsupported:
      Result := 'unsupported';
    TRemoveWithIdentifierStatus.rwisAmbiguousToDak:
      Result := 'ambiguous-to-DAK';
  else
    Result := 'unresolved';
  end;
end;

class function TRemoveWithIdentifierResolver.DirectTypeName(const aTypeName: string): string;
var
  lDelimiterPos: Integer;
begin
  Result := Trim(aTypeName);
  if StartsText('^', Result) then
    Delete(Result, 1, 1);
  lDelimiterPos := Pos('<', Result);
  if lDelimiterPos = 0 then
    lDelimiterPos := Pos('[', Result);
  if lDelimiterPos = 0 then
    lDelimiterPos := Pos(' ', Result);
  if lDelimiterPos > 0 then
    Result := Trim(Copy(Result, 1, lDelimiterPos - 1));
  lDelimiterPos := LastDelimiter('.', Result);
  if lDelimiterPos > 0 then
    Result := Copy(Result, lDelimiterPos + 1, MaxInt);
end;

class function TRemoveWithIdentifierResolver.ElementTypeName(const aTypeName: string): string;
var
  lEndPos: Integer;
  lOfPos: Integer;
  lStartPos: Integer;
  lText: string;
begin
  Result := '';
  lText := Trim(aTypeName);
  if StartsText('array of ', LowerCase(lText)) then
    Exit(Trim(Copy(lText, Length('array of ') + 1, MaxInt)));
  if StartsText('array[', LowerCase(lText)) or StartsText('array [', LowerCase(lText)) then
  begin
    lEndPos := Pos(']', lText);
    if lEndPos > 0 then
    begin
      lOfPos := Pos(' of ', LowerCase(Copy(lText, lEndPos + 1, MaxInt)));
      if lOfPos > 0 then
        Exit(Trim(Copy(lText, lEndPos + lOfPos + Length(' of '), MaxInt)));
    end;
  end;

  lStartPos := Pos('<', lText);
  lEndPos := LastDelimiter('>', lText);
  if (lStartPos > 0) and (lEndPos > lStartPos) then
    Result := Trim(Copy(lText, lStartPos + 1, lEndPos - lStartPos - 1));
end;

class function TRemoveWithIdentifierResolver.ArrayElementTypeName(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): string;
var
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeName: string;
begin
  Result := ElementTypeName(aTypeName);
  if Result <> '' then
    Exit;

  lTypeName := DirectTypeName(aTypeName);
  EnsureResolverSymbolNameIndex(aInventory);
  if GResolverSymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
        Exit(ElementTypeName(lSymbol.fTypeName));
    end;
  end;
end;

class function TRemoveWithIdentifierResolver.IsDirectMemberKind(const aKind: TRemoveWithSymbolKind): Boolean;
begin
  Result := aKind in [TRemoveWithSymbolKind.rwskField, TRemoveWithSymbolKind.rwskProperty,
    TRemoveWithSymbolKind.rwskMethod, TRemoveWithSymbolKind.rwskConstant, TRemoveWithSymbolKind.rwskClassVar];
end;

class function TRemoveWithIdentifierResolver.IsIdentifierChar(const aValue: Char): Boolean;
begin
  Result := CharInSet(aValue, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

class function TRemoveWithIdentifierResolver.IsKeyword(const aName: string): Boolean;
begin
  Result := MatchText(aName, ['and', 'array', 'as', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'div', 'do', 'downto', 'else', 'end', 'except', 'exit', 'false', 'finally', 'for', 'function',
    'if', 'implementation', 'in', 'inherited', 'interface', 'is', 'mod', 'nil', 'not', 'of', 'or', 'out',
    'procedure', 'program', 'property', 'record', 'repeat', 'result', 'self', 'set', 'shl', 'shr', 'then', 'to',
    'true', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor']);
end;

class function TRemoveWithIdentifierResolver.IsWhitespace(const aValue: Char): Boolean;
begin
  Result := CharInSet(aValue, [#9, #10, #13, ' ']);
end;

class function TRemoveWithIdentifierResolver.PreviousNonWhitespaceChar(const aText: string;
  const aOffset: Integer): Char;
var
  i: Integer;
begin
  Result := #0;
  i := aOffset - 1;
  while (i >= 1) and IsWhitespace(aText[i]) do
    Dec(i);
  if i >= 1 then
    Result := aText[i];
end;

class function TRemoveWithIdentifierResolver.NextNonWhitespaceChar(const aText: string;
  const aOffset: Integer): Char;
var
  i: Integer;
begin
  Result := #0;
  i := aOffset;
  while (i <= Length(aText)) and IsWhitespace(aText[i]) do
    Inc(i);
  if i <= Length(aText) then
    Result := aText[i];
end;

class function TRemoveWithIdentifierResolver.LastIdentifierSegment(const aText: string): string;
var
  lText: string;
  i: Integer;
begin
  lText := Trim(aText);
  i := Length(lText);
  while (i >= 1) and IsIdentifierChar(lText[i]) do
    Dec(i);
  Result := Copy(lText, i + 1, MaxInt);
end;

class function TRemoveWithIdentifierResolver.SelectorSegmentName(const aText: string): string;
var
  lBracketPos: Integer;
  lCaretPos: Integer;
  lText: string;
begin
  lText := Trim(aText);
  lCaretPos := Pos('^', lText);
  lBracketPos := Pos('[', lText);
  if (lBracketPos > 0) and ((lCaretPos = 0) or (lBracketPos < lCaretPos)) then
    lText := Trim(Copy(lText, 1, lBracketPos - 1));
  if (lCaretPos > 0) and ((lBracketPos = 0) or (lCaretPos < lBracketPos)) then
    lText := Trim(Copy(lText, 1, lCaretPos - 1));
  Result := LastIdentifierSegment(lText);
end;

class function TRemoveWithIdentifierResolver.SelectorSegmentDerefAfterIndex(const aText: string): Boolean;
var
  lBracketPos: Integer;
  lCaretPos: Integer;
begin
  lCaretPos := Pos('^', aText);
  lBracketPos := Pos('[', aText);
  Result := (lCaretPos > 0) and (lBracketPos > 0) and (lCaretPos > lBracketPos);
end;

class function TRemoveWithIdentifierResolver.SelectorSegmentDerefBeforeIndex(const aText: string): Boolean;
var
  lBracketPos: Integer;
  lCaretPos: Integer;
begin
  lCaretPos := Pos('^', aText);
  lBracketPos := Pos('[', aText);
  Result := (lCaretPos > 0) and ((lBracketPos = 0) or (lCaretPos < lBracketPos));
end;

class function TRemoveWithIdentifierResolver.SelectorSegmentIndexed(const aText: string): Boolean;
begin
  Result := Pos('[', aText) > 0;
end;

class function TRemoveWithIdentifierResolver.StatementContains(const aOuter,
  aInner: TRemoveWithStatementInfo): Boolean;
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

class function TRemoveWithIdentifierResolver.RangeOffsets(const aSource: TRemoveWithSourceBuffer;
  const aRange: TRemoveWithRange; out aOffsets: TRemoveWithOffsetRange): Boolean;
begin
  aOffsets := Default(TRemoveWithOffsetRange);
  Result := RemoveWithOffsetForLineColumn(aSource, aRange.fStartLine, aRange.fStartColumn,
    aOffsets.fStartOffset) and RemoveWithOffsetForLineColumn(aSource, aRange.fEndLine, aRange.fEndColumn,
    aOffsets.fEndOffset);
end;

class function TRemoveWithIdentifierResolver.OffsetInRanges(const aOffset: Integer;
  const aRanges: TArray<TRemoveWithOffsetRange>): Boolean;
var
  lRange: TRemoveWithOffsetRange;
begin
  for lRange in aRanges do
  begin
    if (aOffset >= lRange.fStartOffset) and (aOffset <= lRange.fEndOffset) then
      Exit(True);
  end;
  Result := False;
end;

class function TRemoveWithIdentifierResolver.SplitSelectorList(const aSelectorText: string): TArray<string>;
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

class function TRemoveWithIdentifierResolver.SplitSelectorPath(const aSelectorText: string): TArray<string>;
var
  lBracketDepth: Integer;
  lList: TList<string>;
  lStart: Integer;
  i: Integer;
begin
  lList := TList<string>.Create;
  try
    lBracketDepth := 0;
    lStart := 1;
    for i := 1 to Length(aSelectorText) do
    begin
      if aSelectorText[i] = '[' then
        Inc(lBracketDepth)
      else if (aSelectorText[i] = ']') and (lBracketDepth > 0) then
        Dec(lBracketDepth)
      else if (aSelectorText[i] = '.') and (lBracketDepth = 0) then
      begin
        lList.Add(Trim(Copy(aSelectorText, lStart, i - lStart)));
        lStart := i + 1;
      end;
    end;
    lList.Add(Trim(Copy(aSelectorText, lStart, MaxInt)));
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

class function TRemoveWithIdentifierResolver.FindRoutineForStatement(const aInventory: TRemoveWithSymbolInventory;
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

class function TRemoveWithIdentifierResolver.FindMemberCandidates(const aInventory: TRemoveWithSymbolInventory;
  const aOwnerType, aName: string): TArray<TRemoveWithSymbolInfo>;
var
  lKey: string;
  lList: TList<TRemoveWithSymbolInfo>;
  lOwnerType: string;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  lKey := ResolverCacheKey('member', DirectTypeName(aOwnerType), aName);
  if (GResolverMemberCandidateCache <> nil) and GResolverMemberCandidateCache.TryGetValue(lKey, Result) then
    Exit;

  lList := TList<TRemoveWithSymbolInfo>.Create;
  try
    lOwnerType := DirectTypeName(aOwnerType);
    EnsureResolverSymbolNameIndex(aInventory);
    if GResolverSymbolNameIndex.TryGetValue(aName, lSymbols) then
    begin
      for lSymbol in lSymbols do
      begin
        if SameText(lSymbol.fOwnerType, lOwnerType) and (lSymbol.fRoutineName = '') and
          IsDirectMemberKind(lSymbol.fKind) then
          lList.Add(lSymbol);
      end;
    end;
    Result := lList.ToArray;
    if GResolverMemberCandidateCache <> nil then
      GResolverMemberCandidateCache.Add(lKey, Result);
  finally
    lList.Free;
  end;
end;

class function TRemoveWithIdentifierResolver.FindDefaultPropertyCandidate(
  const aInventory: TRemoveWithSymbolInventory; const aOwnerType: string): Boolean;
var
  lKey: string;
  lOwnerType: string;
  lSymbol: TRemoveWithSymbolInfo;
begin
  lOwnerType := DirectTypeName(aOwnerType);
  lKey := ResolverCacheKey('default-property', lOwnerType);
  if (GResolverBoolCache <> nil) and GResolverBoolCache.TryGetValue(lKey, Result) then
    Exit;

  for lSymbol in aInventory.fSymbols do
  begin
    if SameText(lSymbol.fOwnerType, lOwnerType) and (lSymbol.fKind = TRemoveWithSymbolKind.rwskProperty) and
      lSymbol.fIsDefault then
    begin
      if GResolverBoolCache <> nil then
        GResolverBoolCache.Add(lKey, True);
      Exit(True);
    end;
  end;
  Result := False;
  if GResolverBoolCache <> nil then
    GResolverBoolCache.Add(lKey, Result);
end;

class function TRemoveWithIdentifierResolver.FindScopeSymbol(const aInventory: TRemoveWithSymbolInventory;
  const aRoutineName, aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
const
  cKinds: array [0..5] of TRemoveWithSymbolKind = (TRemoveWithSymbolKind.rwskLocalVariable,
    TRemoveWithSymbolKind.rwskParameter, TRemoveWithSymbolKind.rwskCurrentClassMember,
    TRemoveWithSymbolKind.rwskUnitGlobal, TRemoveWithSymbolKind.rwskConstant, TRemoveWithSymbolKind.rwskRoutine);
var
  lKey: string;
  lKind: TRemoveWithSymbolKind;
  lLookup: TRemoveWithSymbolLookup;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  lKey := ResolverCacheKey('scope', aRoutineName, aName);
  if (GResolverScopeSymbolCache <> nil) and GResolverScopeSymbolCache.TryGetValue(lKey, lLookup) then
  begin
    aSymbol := lLookup.fSymbol;
    Exit(lLookup.fFound);
  end;

  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  EnsureResolverSymbolNameIndex(aInventory);
  if not GResolverSymbolNameIndex.TryGetValue(aName, lSymbols) then
  begin
    if GResolverScopeSymbolCache <> nil then
    begin
      lLookup := Default(TRemoveWithSymbolLookup);
      GResolverScopeSymbolCache.Add(lKey, lLookup);
    end;
    Exit(False);
  end;
  for lKind in cKinds do
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind <> lKind then
        Continue;
      if lKind in [TRemoveWithSymbolKind.rwskLocalVariable, TRemoveWithSymbolKind.rwskParameter,
        TRemoveWithSymbolKind.rwskCurrentClassMember] then
      begin
        if not SameText(lSymbol.fRoutineName, aRoutineName) then
          Continue;
      end else if lSymbol.fRoutineName <> '' then
        Continue;

      aSymbol := lSymbol;
      if GResolverScopeSymbolCache <> nil then
      begin
        lLookup.fFound := True;
        lLookup.fSymbol := aSymbol;
        GResolverScopeSymbolCache.Add(lKey, lLookup);
      end;
      Exit(True);
    end;
  end;
  if GResolverScopeSymbolCache <> nil then
  begin
    lLookup := Default(TRemoveWithSymbolLookup);
    GResolverScopeSymbolCache.Add(lKey, lLookup);
  end;
end;

class function TRemoveWithIdentifierResolver.FindUnitNameSymbol(const aInventory: TRemoveWithSymbolInventory;
  const aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lLookup: TRemoveWithSymbolLookup;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if (GResolverUnitNameCache <> nil) and GResolverUnitNameCache.TryGetValue(aName, lLookup) then
  begin
    aSymbol := lLookup.fSymbol;
    Exit(lLookup.fFound);
  end;

  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  EnsureResolverSymbolNameIndex(aInventory);
  if GResolverSymbolNameIndex.TryGetValue(aName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskUnitName then
      begin
        aSymbol := lSymbol;
        if GResolverUnitNameCache <> nil then
        begin
          lLookup.fFound := True;
          lLookup.fSymbol := aSymbol;
          GResolverUnitNameCache.Add(aName, lLookup);
        end;
        Exit(True);
      end;
    end;
  end;
  if GResolverUnitNameCache <> nil then
  begin
    lLookup := Default(TRemoveWithSymbolLookup);
    GResolverUnitNameCache.Add(aName, lLookup);
  end;
end;

class function TRemoveWithIdentifierResolver.FindExternalUnitSymbol(const aInventory: TRemoveWithSymbolInventory;
  const aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lLookup: TRemoveWithSymbolLookup;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if (GResolverExternalUnitCache <> nil) and GResolverExternalUnitCache.TryGetValue(aName, lLookup) then
  begin
    aSymbol := lLookup.fSymbol;
    Exit(lLookup.fFound);
  end;

  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  EnsureResolverSymbolNameIndex(aInventory);
  if GResolverSymbolNameIndex.TryGetValue(aName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if (lSymbol.fKind = TRemoveWithSymbolKind.rwskExternal) and (lSymbol.fTypeName = '') then
      begin
        aSymbol := lSymbol;
        if GResolverExternalUnitCache <> nil then
        begin
          lLookup.fFound := True;
          lLookup.fSymbol := aSymbol;
          GResolverExternalUnitCache.Add(aName, lLookup);
        end;
        Exit(True);
      end;
    end;
  end;
  if GResolverExternalUnitCache <> nil then
  begin
    lLookup := Default(TRemoveWithSymbolLookup);
    GResolverExternalUnitCache.Add(aName, lLookup);
  end;
end;

class function TRemoveWithIdentifierResolver.FindTypeNameSymbol(const aInventory: TRemoveWithSymbolInventory;
  const aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lLookup: TRemoveWithSymbolLookup;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if (GResolverTypeNameCache <> nil) and GResolverTypeNameCache.TryGetValue(aName, lLookup) then
  begin
    aSymbol := lLookup.fSymbol;
    Exit(lLookup.fFound);
  end;

  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  EnsureResolverSymbolNameIndex(aInventory);
  if GResolverSymbolNameIndex.TryGetValue(aName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
      begin
        aSymbol := lSymbol;
        if GResolverTypeNameCache <> nil then
        begin
          lLookup.fFound := True;
          lLookup.fSymbol := aSymbol;
          GResolverTypeNameCache.Add(aName, lLookup);
        end;
        Exit(True);
      end;
    end;
  end;
  if GResolverTypeNameCache <> nil then
  begin
    lLookup := Default(TRemoveWithSymbolLookup);
    GResolverTypeNameCache.Add(aName, lLookup);
  end;
end;

class function TRemoveWithIdentifierResolver.HasSourceType(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): Boolean;
var
  lKey: string;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeName: string;
begin
  lTypeName := DirectTypeName(aTypeName);
  if lTypeName = '' then
    Exit(False);
  lKey := ResolverCacheKey('source-type', lTypeName);
  if (GResolverBoolCache <> nil) and GResolverBoolCache.TryGetValue(lKey, Result) then
    Exit;

  EnsureResolverSymbolNameIndex(aInventory);
  if GResolverSymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
      begin
        if GResolverBoolCache <> nil then
          GResolverBoolCache.Add(lKey, True);
        Exit(True);
      end;
    end;
  end;
  Result := False;
  if GResolverBoolCache <> nil then
    GResolverBoolCache.Add(lKey, Result);
end;

class function TRemoveWithIdentifierResolver.IsExternalType(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): Boolean;
var
  lKey: string;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeName: string;
begin
  lTypeName := DirectTypeName(aTypeName);
  lKey := ResolverCacheKey('external-type', lTypeName);
  if (GResolverBoolCache <> nil) and GResolverBoolCache.TryGetValue(lKey, Result) then
    Exit;

  EnsureResolverSymbolNameIndex(aInventory);
  if GResolverSymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskExternal then
      begin
        if GResolverBoolCache <> nil then
          GResolverBoolCache.Add(lKey, True);
        Exit(True);
      end;
    end;
  end;
  Result := False;
  if GResolverBoolCache <> nil then
    GResolverBoolCache.Add(lKey, Result);
end;

class function TRemoveWithIdentifierResolver.HasExternalAncestor(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): Boolean;
var
  lCurrentType: string;
  lKey: string;
  lRelatedType: string;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  lCurrentType := DirectTypeName(aTypeName);
  lKey := ResolverCacheKey('external-ancestor', lCurrentType);
  if (GResolverBoolCache <> nil) and GResolverBoolCache.TryGetValue(lKey, Result) then
    Exit;

  while lCurrentType <> '' do
  begin
    lRelatedType := '';
    EnsureResolverSymbolNameIndex(aInventory);
    if GResolverSymbolNameIndex.TryGetValue(lCurrentType, lSymbols) then
    begin
      for lSymbol in lSymbols do
      begin
        if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and (not lSymbol.fIsHelper) then
        begin
          lRelatedType := DirectTypeName(lSymbol.fRelatedTypeName);
          Break;
        end;
      end;
    end;
    if lRelatedType = '' then
    begin
      if GResolverBoolCache <> nil then
        GResolverBoolCache.Add(lKey, False);
      Exit(False);
    end;
    if IsExternalType(aInventory, lRelatedType) then
    begin
      if GResolverBoolCache <> nil then
        GResolverBoolCache.Add(lKey, True);
      Exit(True);
    end;
    lCurrentType := lRelatedType;
  end;
  if GResolverBoolCache <> nil then
    GResolverBoolCache.Add(lKey, Result);
end;

class function TRemoveWithIdentifierResolver.PointerTargetType(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): string;
var
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeName: string;
begin
  lTypeName := Trim(aTypeName);
  if StartsText('^', lTypeName) then
    Exit(Trim(Copy(lTypeName, 2, MaxInt)));

  lTypeName := DirectTypeName(lTypeName);
  EnsureResolverSymbolNameIndex(aInventory);
  if GResolverSymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and StartsText('^', Trim(lSymbol.fTypeName)) then
        Exit(Trim(Copy(Trim(lSymbol.fTypeName), 2, MaxInt)));
    end;
  end;
  Result := '';
end;

class function TRemoveWithIdentifierResolver.FindAncestorMember(const aInventory: TRemoveWithSymbolInventory;
  const aOwnerType, aName: string; out aSourceOwnerType: string): Boolean;
var
  lCandidates: TArray<TRemoveWithSymbolInfo>;
  lCurrentType: string;
  lKey: string;
  lLookup: TRemoveWithTextLookup;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  aSourceOwnerType := '';
  lCurrentType := DirectTypeName(aOwnerType);
  lKey := ResolverCacheKey('ancestor-member', lCurrentType, aName);
  if (GResolverAncestorMemberCache <> nil) and GResolverAncestorMemberCache.TryGetValue(lKey, lLookup) then
  begin
    aSourceOwnerType := lLookup.fText;
    Exit(lLookup.fFound);
  end;

  while lCurrentType <> '' do
  begin
    aSourceOwnerType := '';
    EnsureResolverSymbolNameIndex(aInventory);
    if GResolverSymbolNameIndex.TryGetValue(lCurrentType, lSymbols) then
    begin
      for lSymbol in lSymbols do
      begin
        if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and (not lSymbol.fIsHelper) then
        begin
          aSourceOwnerType := DirectTypeName(lSymbol.fRelatedTypeName);
          Break;
        end;
      end;
    end;
    if aSourceOwnerType = '' then
    begin
      if GResolverAncestorMemberCache <> nil then
      begin
        lLookup := Default(TRemoveWithTextLookup);
        GResolverAncestorMemberCache.Add(lKey, lLookup);
      end;
      Exit(False);
    end;

    lCandidates := FindMemberCandidates(aInventory, aSourceOwnerType, aName);
    if Length(lCandidates) > 0 then
    begin
      if GResolverAncestorMemberCache <> nil then
      begin
        lLookup.fFound := True;
        lLookup.fText := aSourceOwnerType;
        GResolverAncestorMemberCache.Add(lKey, lLookup);
      end;
      Exit(True);
    end;
    lCurrentType := aSourceOwnerType;
  end;
  if GResolverAncestorMemberCache <> nil then
  begin
    lLookup := Default(TRemoveWithTextLookup);
    GResolverAncestorMemberCache.Add(lKey, lLookup);
  end;
end;

class function TRemoveWithIdentifierResolver.IsHelperType(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): Boolean;
var
  lKey: string;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeName: string;
begin
  lTypeName := DirectTypeName(aTypeName);
  lKey := ResolverCacheKey('helper-type', lTypeName);
  if (GResolverBoolCache <> nil) and GResolverBoolCache.TryGetValue(lKey, Result) then
    Exit;

  EnsureResolverSymbolNameIndex(aInventory);
  if GResolverSymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and lSymbol.fIsHelper then
      begin
        if GResolverBoolCache <> nil then
          GResolverBoolCache.Add(lKey, True);
        Exit(True);
      end;
    end;
  end;
  Result := False;
  if GResolverBoolCache <> nil then
    GResolverBoolCache.Add(lKey, Result);
end;

class function TRemoveWithIdentifierResolver.ResolutionKindForCandidate(
  const aInventory: TRemoveWithSymbolInventory; const aReceiverType: string;
  const aCandidate: TRemoveWithSymbolInfo; out aSourceOwnerType: string): string;
begin
  aSourceOwnerType := aCandidate.fSourceOwnerType;
  if aSourceOwnerType <> '' then
  begin
    if IsHelperType(aInventory, aSourceOwnerType) then
      Exit('helper');
    Exit('inherited');
  end;

  if FindAncestorMember(aInventory, aReceiverType, aCandidate.fName, aSourceOwnerType) then
  begin
    aSourceOwnerType := '';
    if (aCandidate.fKind = TRemoveWithSymbolKind.rwskMethod) and aCandidate.fIsOverride then
      Exit('overridden');
    Exit('hidden');
  end;

  Result := 'direct';
end;

class function TRemoveWithIdentifierResolver.AllCandidatesAreMethods(
  const aCandidates: TArray<TRemoveWithSymbolInfo>): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := Length(aCandidates) > 0;
  for lSymbol in aCandidates do
  begin
    if lSymbol.fKind <> TRemoveWithSymbolKind.rwskMethod then
      Exit(False);
  end;
end;

class function TRemoveWithIdentifierResolver.CandidatesShareSourceOwner(
  const aCandidates: TArray<TRemoveWithSymbolInfo>): Boolean;
var
  lSourceOwnerType: string;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if Length(aCandidates) = 0 then
    Exit(False);

  lSourceOwnerType := aCandidates[0].fSourceOwnerType;
  for lSymbol in aCandidates do
  begin
    if not SameText(lSymbol.fSourceOwnerType, lSourceOwnerType) then
      Exit(False);
  end;
  Result := True;
end;

class function TRemoveWithIdentifierResolver.IsCallUse(const aSource: TRemoveWithSourceBuffer;
  const aUse: TRemoveWithIdentifierUse): Boolean;
begin
  Result := NextNonWhitespaceChar(aSource.fText, aUse.fEndOffset + 1) = '(';
end;

class function TRemoveWithIdentifierResolver.IsKnownExternalRoutineCall(const aSource: TRemoveWithSourceBuffer;
  const aUse: TRemoveWithIdentifierUse): Boolean;
begin
  Result := IsCallUse(aSource, aUse) and MatchText(aUse.fName, ['Abs', 'Addr', 'Assigned', 'Copy', 'Dec',
    'Dispose', 'Exclude', 'FillChar', 'FreeMem', 'GetMem', 'High', 'Inc', 'Include', 'IOResult', 'Length', 'Low',
    'Move', 'New', 'Ord', 'Pred', 'Seek', 'SetLength', 'SizeOf', 'Str']);
end;

class function TRemoveWithIdentifierResolver.IsQualifiedUse(const aSource: TRemoveWithSourceBuffer;
  const aUse: TRemoveWithIdentifierUse): Boolean;
begin
  Result := NextNonWhitespaceChar(aSource.fText, aUse.fEndOffset + 1) = '.';
end;

class function TRemoveWithIdentifierResolver.ResolveSelectorFromReceivers(
  const aInventory: TRemoveWithSymbolInventory; const aReceivers: TArray<TRemoveWithReceiverScope>;
  const aSelectorText: string; out aInfo: TRemoveWithSelectorTypeInfo): Boolean;
var
  lCandidates: TArray<TRemoveWithSymbolInfo>;
  lCurrentType: string;
  lIndexedTypeName: string;
  lName: string;
  lPaths: TArray<string>;
  i: Integer;
  j: Integer;
begin
  aInfo := Default(TRemoveWithSelectorTypeInfo);
  aInfo.fSelectorText := aSelectorText;
  lPaths := SplitSelectorPath(aSelectorText);
  if Length(lPaths) = 0 then
    Exit(False);

  lName := SelectorSegmentName(lPaths[0]);
  if lName = '' then
    Exit(False);

  for i := High(aReceivers) downto 0 do
  begin
    if aReceivers[i].fStatus <> TRemoveWithSelectorTypeStatus.rwstsResolved then
      Continue;

    lCandidates := FindMemberCandidates(aInventory, aReceivers[i].fTypeName, lName);
    if Length(lCandidates) <> 1 then
      Continue;
    if lCandidates[0].fKind = TRemoveWithSymbolKind.rwskProperty then
    begin
      aInfo.fReason := 'property-selector';
      aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
      aInfo.fAddressable := False;
      Exit(True);
    end;
    if lCandidates[0].fKind = TRemoveWithSymbolKind.rwskMethod then
    begin
      aInfo.fReason := 'call-selector';
      aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
      aInfo.fAddressable := False;
      Exit(True);
    end;

    lCurrentType := lCandidates[0].fTypeName;
    if SelectorSegmentDerefBeforeIndex(lPaths[0]) then
      lCurrentType := PointerTargetType(aInventory, lCurrentType);
    if SelectorSegmentIndexed(lPaths[0]) then
    begin
      lIndexedTypeName := ArrayElementTypeName(aInventory, lCurrentType);
      if lIndexedTypeName <> '' then
        lCurrentType := lIndexedTypeName
      else if FindDefaultPropertyCandidate(aInventory, lCurrentType) then
      begin
        aInfo.fReason := 'property-selector';
        aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
        aInfo.fAddressable := False;
        Exit(True);
      end else
        lCurrentType := '';
    end;
    if SelectorSegmentDerefAfterIndex(lPaths[0]) then
      lCurrentType := PointerTargetType(aInventory, lCurrentType);

    for j := 1 to High(lPaths) do
    begin
      lName := SelectorSegmentName(lPaths[j]);
      lCandidates := FindMemberCandidates(aInventory, lCurrentType, lName);
      if Length(lCandidates) <> 1 then
      begin
        lCurrentType := '';
        Break;
      end;
      if lCandidates[0].fKind = TRemoveWithSymbolKind.rwskProperty then
      begin
        aInfo.fReason := 'property-selector';
        aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
        aInfo.fAddressable := False;
        Exit(True);
      end;
      if lCandidates[0].fKind = TRemoveWithSymbolKind.rwskMethod then
      begin
        aInfo.fReason := 'call-selector';
        aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
        aInfo.fAddressable := False;
        Exit(True);
      end;
      lCurrentType := lCandidates[0].fTypeName;
      if SelectorSegmentDerefBeforeIndex(lPaths[j]) then
        lCurrentType := PointerTargetType(aInventory, lCurrentType);
      if SelectorSegmentIndexed(lPaths[j]) then
      begin
        lIndexedTypeName := ArrayElementTypeName(aInventory, lCurrentType);
        if lIndexedTypeName <> '' then
          lCurrentType := lIndexedTypeName
        else if FindDefaultPropertyCandidate(aInventory, lCurrentType) then
        begin
          aInfo.fReason := 'property-selector';
          aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
          aInfo.fAddressable := False;
          Exit(True);
        end else
          lCurrentType := '';
      end;
      if SelectorSegmentDerefAfterIndex(lPaths[j]) then
        lCurrentType := PointerTargetType(aInventory, lCurrentType);
    end;

    if lCurrentType <> '' then
    begin
      aInfo.fTypeName := DirectTypeName(lCurrentType);
      if (not HasSourceType(aInventory, aInfo.fTypeName)) and IsExternalType(aInventory, aInfo.fTypeName) then
      begin
        aInfo.fReason := 'type-source-not-indexed';
        aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsExternal;
        aInfo.fAddressable := False;
      end else
      begin
        aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsResolved;
        aInfo.fAddressable := True;
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TRemoveWithIdentifierResolver.SelectorUsesUnsupportedProperty(
  const aInventory: TRemoveWithSymbolInventory; const aRoutineName, aSelectorText: string): Boolean;
var
  lCandidates: TArray<TRemoveWithSymbolInfo>;
  lCurrentType: string;
  lName: string;
  lOwnerDot: Integer;
  lOwnerType: string;
  lPaths: TArray<string>;
  lSymbol: TRemoveWithSymbolInfo;
  i: Integer;
begin
  Result := False;
  lPaths := SplitSelectorPath(aSelectorText);
  if Length(lPaths) = 0 then
    Exit;

  lName := SelectorSegmentName(lPaths[0]);
  if lName = '' then
    Exit;

  lOwnerDot := LastDelimiter('.', aRoutineName);
  if lOwnerDot > 0 then
    lOwnerType := Copy(aRoutineName, 1, lOwnerDot - 1)
  else
    lOwnerType := '';

  if SameText(lName, 'Self') then
    lCurrentType := lOwnerType
  else
  begin
    if not FindScopeSymbol(aInventory, aRoutineName, lName, lSymbol) then
    begin
      lCandidates := FindMemberCandidates(aInventory, lOwnerType, lName);
      if Length(lCandidates) <> 1 then
        Exit;
      lSymbol := lCandidates[0];
    end;
    lCurrentType := lSymbol.fTypeName;
  end;

  if SelectorSegmentIndexed(lPaths[0]) and FindDefaultPropertyCandidate(aInventory, lCurrentType) then
    Exit(True);

  for i := 1 to High(lPaths) do
  begin
    lName := SelectorSegmentName(lPaths[i]);
    if lName = '' then
      Exit;
    lCandidates := FindMemberCandidates(aInventory, lCurrentType, lName);
    if Length(lCandidates) <> 1 then
      Exit;
    if lCandidates[0].fKind = TRemoveWithSymbolKind.rwskProperty then
      Exit(True);
    lCurrentType := lCandidates[0].fTypeName;
    if SelectorSegmentIndexed(lPaths[i]) and FindDefaultPropertyCandidate(aInventory, lCurrentType) then
      Exit(True);
  end;
end;

class procedure TRemoveWithIdentifierResolver.NormalizeSelectorInfo(const aInventory: TRemoveWithSymbolInventory;
  const aRoutineName, aSelectorText: string; var aInfo: TRemoveWithSelectorTypeInfo);
var
  lRootName: string;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if ((aInfo.fStatus in [TRemoveWithSelectorTypeStatus.rwstsExternal,
    TRemoveWithSelectorTypeStatus.rwstsUnresolved]) or
    ((aInfo.fStatus = TRemoveWithSelectorTypeStatus.rwstsResolved) and (aInfo.fTypeName = ''))) and
    SelectorUsesUnsupportedProperty(aInventory, aRoutineName, aSelectorText) then
  begin
    aInfo.fSelectorText := aSelectorText;
    aInfo.fTypeName := '';
    aInfo.fReason := 'property-selector';
    aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
    aInfo.fAddressable := False;
    Exit;
  end;

  if (aInfo.fStatus <> TRemoveWithSelectorTypeStatus.rwstsResolved) or (aInfo.fTypeName <> '') then
    Exit;

  if Pos('(', aSelectorText) > 0 then
  begin
    aInfo.fSelectorText := aSelectorText;
    aInfo.fReason := 'call-selector';
    aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
    aInfo.fAddressable := False;
    Exit;
  end;

  lRootName := LastIdentifierSegment(aSelectorText);
  if FindScopeSymbol(aInventory, aRoutineName, lRootName, lSymbol) and (lSymbol.fTypeName <> '') then
  begin
    aInfo.fSelectorText := aSelectorText;
    aInfo.fTypeName := DirectTypeName(lSymbol.fTypeName);
    aInfo.fReason := 'type-source-not-indexed';
    aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsExternal;
    aInfo.fAddressable := False;
  end;
end;

class procedure TRemoveWithIdentifierResolver.AddClassification(var aResult: TRemoveWithResolverResult;
  const aClassification: TRemoveWithIdentifierClassification);
var
  lIndex: Integer;
begin
  lIndex := Length(aResult.fClassifications);
  SetLength(aResult.fClassifications, lIndex + 1);
  aResult.fClassifications[lIndex] := aClassification;
end;

class procedure TRemoveWithIdentifierResolver.CollectIdentifierUses(const aSource: TRemoveWithSourceBuffer;
  const aBodyOffsets: TRemoveWithOffsetRange; const aSkipRanges: TArray<TRemoveWithOffsetRange>;
  out aUses: TArray<TRemoveWithIdentifierUse>);
var
  lList: TList<TRemoveWithIdentifierUse>;
  lUse: TRemoveWithIdentifierUse;
  i: Integer;
begin
  lList := TList<TRemoveWithIdentifierUse>.Create;
  try
    i := aBodyOffsets.fStartOffset;
    while i <= aBodyOffsets.fEndOffset do
    begin
      if OffsetInRanges(i, aSkipRanges) then
      begin
        Inc(i);
        Continue;
      end;

      if aSource.fText[i] = '''' then
      begin
        Inc(i);
        while i <= aBodyOffsets.fEndOffset do
        begin
          if aSource.fText[i] = '''' then
          begin
            Inc(i);
            if (i <= aBodyOffsets.fEndOffset) and (aSource.fText[i] = '''') then
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
        while (i <= aBodyOffsets.fEndOffset) and (aSource.fText[i] <> '}') do
          Inc(i);
        Inc(i);
        Continue;
      end;

      if (i < aBodyOffsets.fEndOffset) and (aSource.fText[i] = '(') and (aSource.fText[i + 1] = '*') then
      begin
        Inc(i, 2);
        while (i < aBodyOffsets.fEndOffset) and
          ((aSource.fText[i] <> '*') or (aSource.fText[i + 1] <> ')')) do
          Inc(i);
        Inc(i, 2);
        Continue;
      end;

      if (i < aBodyOffsets.fEndOffset) and (aSource.fText[i] = '/') and (aSource.fText[i + 1] = '/') then
      begin
        Inc(i, 2);
        while (i <= aBodyOffsets.fEndOffset) and not CharInSet(aSource.fText[i], [#10, #13]) do
          Inc(i);
        Continue;
      end;

      if CharInSet(aSource.fText[i], ['A'..'Z', 'a'..'z', '_']) then
      begin
        lUse := Default(TRemoveWithIdentifierUse);
        lUse.fStartOffset := i;
        while (i <= aBodyOffsets.fEndOffset) and IsIdentifierChar(aSource.fText[i]) do
          Inc(i);
        lUse.fEndOffset := i - 1;
        lUse.fName := Copy(aSource.fText, lUse.fStartOffset, lUse.fEndOffset - lUse.fStartOffset + 1);
        if (not IsKeyword(lUse.fName)) and
          (PreviousNonWhitespaceChar(aSource.fText, lUse.fStartOffset) <> '.') then
        begin
          RemoveWithLineColumnForOffset(aSource, lUse.fStartOffset, lUse.fLine, lUse.fColumn);
          lList.Add(lUse);
        end;
        Continue;
      end;
      Inc(i);
    end;
    aUses := lList.ToArray;
  finally
    lList.Free;
  end;
end;

class procedure TRemoveWithIdentifierResolver.BuildReceiverStack(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; const aStatement: TRemoveWithStatementInfo;
  const aRoutineName: string; out aReceivers: TArray<TRemoveWithReceiverScope>);
var
  lInfo: TRemoveWithSelectorTypeInfo;
  lList: TList<TRemoveWithReceiverScope>;
  lReceiver: TRemoveWithReceiverScope;
  lSelector: string;
  lSelectors: TArray<string>;
  lStatement: TRemoveWithStatementInfo;
begin
  lList := TList<TRemoveWithReceiverScope>.Create;
  try
    for lStatement in aScanResult.fWithStatements do
    begin
      if not StatementContains(lStatement, aStatement) then
        Continue;
      lSelectors := SplitSelectorList(lStatement.fSelectorText);
      for lSelector in lSelectors do
      begin
        if not ResolveRemoveWithSelectorType(aInventory, aRoutineName, lSelector, lInfo) then
          lInfo := Default(TRemoveWithSelectorTypeInfo);
        NormalizeSelectorInfo(aInventory, aRoutineName, lSelector, lInfo);
        if (lInfo.fStatus <> TRemoveWithSelectorTypeStatus.rwstsResolved) and
          ResolveSelectorFromReceivers(aInventory, lList.ToArray, lSelector, lInfo) then
        begin
        end;
        lReceiver := Default(TRemoveWithReceiverScope);
        lReceiver.fSelectorText := lSelector;
        lReceiver.fTypeName := lInfo.fTypeName;
        lReceiver.fReason := lInfo.fReason;
        lReceiver.fStatus := lInfo.fStatus;
        lList.Add(lReceiver);
      end;
    end;

    lSelectors := SplitSelectorList(aStatement.fSelectorText);
    for lSelector in lSelectors do
    begin
      if not ResolveRemoveWithSelectorType(aInventory, aRoutineName, lSelector, lInfo) then
        lInfo := Default(TRemoveWithSelectorTypeInfo);
      NormalizeSelectorInfo(aInventory, aRoutineName, lSelector, lInfo);
      if (lInfo.fStatus <> TRemoveWithSelectorTypeStatus.rwstsResolved) and
        ResolveSelectorFromReceivers(aInventory, lList.ToArray, lSelector, lInfo) then
      begin
      end;
      lReceiver := Default(TRemoveWithReceiverScope);
      lReceiver.fSelectorText := lSelector;
      lReceiver.fTypeName := lInfo.fTypeName;
      lReceiver.fReason := lInfo.fReason;
      lReceiver.fStatus := lInfo.fStatus;
      lList.Add(lReceiver);
    end;
    aReceivers := lList.ToArray;
  finally
    lList.Free;
  end;
end;

class function TRemoveWithIdentifierResolver.ClassifyUse(const aInventory: TRemoveWithSymbolInventory;
  const aSource: TRemoveWithSourceBuffer; const aRoutineName: string;
  const aReceivers: TArray<TRemoveWithReceiverScope>; const aUse: TRemoveWithIdentifierUse;
  out aClassification: TRemoveWithIdentifierClassification): Boolean;
var
  lCandidates: TArray<TRemoveWithSymbolInfo>;
  lReceiver: TRemoveWithReceiverScope;
  lSourceOwnerType: string;
  lSymbol: TRemoveWithSymbolInfo;
  i: Integer;
begin
  aClassification := Default(TRemoveWithIdentifierClassification);
  aClassification.fIdentifier := aUse.fName;
  aClassification.fLine := aUse.fLine;
  aClassification.fColumn := aUse.fColumn;
  aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnresolved;
  aClassification.fResolutionKind := 'unresolved';
  aClassification.fReason := 'symbol-not-found';
  Result := True;

  if IsQualifiedUse(aSource, aUse) and FindUnitNameSymbol(aInventory, aUse.fName, lSymbol) then
  begin
    aClassification.fMemberKind := lSymbol.fKind;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'qualified-unit';
    aClassification.fReason := 'unit-qualifier';
    Exit(True);
  end;

  if IsQualifiedUse(aSource, aUse) and FindExternalUnitSymbol(aInventory, aUse.fName, lSymbol) then
  begin
    aClassification.fMemberKind := lSymbol.fKind;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisExternal;
    aClassification.fResolutionKind := 'external-unit';
    aClassification.fReason := 'unit-source-not-indexed';
    Exit(True);
  end;

  if IsQualifiedUse(aSource, aUse) and FindTypeNameSymbol(aInventory, aUse.fName, lSymbol) then
  begin
    aClassification.fMemberKind := lSymbol.fKind;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnsupported;
    aClassification.fResolutionKind := 'type-qualifier';
    aClassification.fReason := 'unsupported-identifier-role';
    Exit(True);
  end;

  for i := High(aReceivers) downto 0 do
  begin
    if aReceivers[i].fStatus = TRemoveWithSelectorTypeStatus.rwstsResolved then
    begin
      lCandidates := FindMemberCandidates(aInventory, aReceivers[i].fTypeName, aUse.fName);
      if Length(lCandidates) = 1 then
      begin
        aClassification.fReceiverText := aReceivers[i].fSelectorText;
        aClassification.fReceiverType := aReceivers[i].fTypeName;
        aClassification.fMemberKind := lCandidates[0].fKind;
        aClassification.fResolutionKind := ResolutionKindForCandidate(aInventory, aReceivers[i].fTypeName,
          lCandidates[0], lSourceOwnerType);
        aClassification.fSourceOwnerType := lSourceOwnerType;
        aClassification.fStatus := TRemoveWithIdentifierStatus.rwisResolved;
        aClassification.fReason := '';
        Exit(True);
      end else if Length(lCandidates) > 1 then
      begin
        aClassification.fReceiverText := aReceivers[i].fSelectorText;
        aClassification.fReceiverType := aReceivers[i].fTypeName;
        aClassification.fMemberKind := lCandidates[0].fKind;
        aClassification.fResolutionKind := ResolutionKindForCandidate(aInventory, aReceivers[i].fTypeName,
          lCandidates[0], lSourceOwnerType);
        aClassification.fSourceOwnerType := lSourceOwnerType;
        if AllCandidatesAreMethods(lCandidates) and CandidatesShareSourceOwner(lCandidates) and
          IsCallUse(aSource, aUse) then
        begin
          aClassification.fStatus := TRemoveWithIdentifierStatus.rwisResolved;
          aClassification.fReason := '';
        end else
        begin
          aClassification.fStatus := TRemoveWithIdentifierStatus.rwisAmbiguousToDak;
          aClassification.fResolutionKind := 'ambiguous';
          aClassification.fSourceOwnerType := '';
          aClassification.fReason := 'multiple-member-candidates';
        end;
        Exit(True);
      end else if HasExternalAncestor(aInventory, aReceivers[i].fTypeName) then
      begin
        aClassification.fReceiverText := aReceivers[i].fSelectorText;
        aClassification.fReceiverType := aReceivers[i].fTypeName;
        aClassification.fResolutionKind := 'external-only';
        aClassification.fStatus := TRemoveWithIdentifierStatus.rwisExternal;
        aClassification.fReason := 'type-source-not-indexed';
        Exit(True);
      end;
    end else if aReceivers[i].fStatus = TRemoveWithSelectorTypeStatus.rwstsExternal then
    begin
      aClassification.fReceiverText := aReceivers[i].fSelectorText;
      aClassification.fReceiverType := aReceivers[i].fTypeName;
      aClassification.fResolutionKind := 'external-only';
      aClassification.fStatus := TRemoveWithIdentifierStatus.rwisExternal;
      aClassification.fReason := aReceivers[i].fReason;
      Exit(True);
    end else if aReceivers[i].fStatus = TRemoveWithSelectorTypeStatus.rwstsUnsupported then
    begin
      aClassification.fReceiverText := aReceivers[i].fSelectorText;
      aClassification.fResolutionKind := 'unsupported';
      aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnsupported;
      aClassification.fReason := aReceivers[i].fReason;
      Exit(True);
    end else if aReceivers[i].fStatus = TRemoveWithSelectorTypeStatus.rwstsUnresolved then
    begin
      aClassification.fReceiverText := aReceivers[i].fSelectorText;
      if MatchText(aReceivers[i].fReason, ['type-not-found', 'type-not-resolved']) then
      begin
        if (aReceivers[i].fTypeName = '') and SelectorSegmentIndexed(aReceivers[i].fSelectorText) then
        begin
          aClassification.fResolutionKind := 'unsupported';
          aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnsupported;
          aClassification.fReason := 'property-selector';
        end else
        begin
          aClassification.fReceiverType := aReceivers[i].fTypeName;
          aClassification.fResolutionKind := 'external-only';
          aClassification.fStatus := TRemoveWithIdentifierStatus.rwisExternal;
          aClassification.fReason := 'type-source-not-indexed';
        end;
      end else
      begin
        aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnresolved;
        aClassification.fResolutionKind := 'unresolved';
        aClassification.fReason := aReceivers[i].fReason;
      end;
      Exit(True);
    end;
  end;

  if Length(aReceivers) > 0 then
  begin
    lReceiver := aReceivers[High(aReceivers)];
    if (lReceiver.fStatus = TRemoveWithSelectorTypeStatus.rwstsResolved) and (lReceiver.fTypeName = '') then
    begin
      aClassification.fReceiverText := lReceiver.fSelectorText;
      if Pos('(', lReceiver.fSelectorText) > 0 then
      begin
        aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnsupported;
        aClassification.fResolutionKind := 'unsupported';
        aClassification.fReason := 'call-selector';
      end else
      begin
        if SelectorSegmentIndexed(lReceiver.fSelectorText) then
        begin
          aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnsupported;
          aClassification.fResolutionKind := 'unsupported';
          aClassification.fReason := 'property-selector';
        end else
        begin
          aClassification.fStatus := TRemoveWithIdentifierStatus.rwisExternal;
          aClassification.fResolutionKind := 'external-only';
          aClassification.fReason := 'type-source-not-indexed';
        end;
      end;
      Exit(True);
    end;
  end;

  if FindScopeSymbol(aInventory, aRoutineName, aUse.fName, lSymbol) then
  begin
    aClassification.fMemberKind := lSymbol.fKind;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'unchanged';
    aClassification.fReason := 'routine-scope';
  end else if IsKnownExternalRoutineCall(aSource, aUse) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskRoutine;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'known-external-routine';
    aClassification.fReason := 'known-external-routine';
  end;
end;

class procedure TRemoveWithIdentifierResolver.ResolveStatement(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; const aStatement: TRemoveWithStatementInfo;
  const aSource: TRemoveWithSourceBuffer; var aResult: TRemoveWithResolverResult);
var
  lBodyOffsets: TRemoveWithOffsetRange;
  lClassification: TRemoveWithIdentifierClassification;
  lReceivers: TArray<TRemoveWithReceiverScope>;
  lRoutineName: string;
  lSkipRanges: TList<TRemoveWithOffsetRange>;
  lStatement: TRemoveWithStatementInfo;
  lUse: TRemoveWithIdentifierUse;
  lUses: TArray<TRemoveWithIdentifierUse>;
  lWithOffsets: TRemoveWithOffsetRange;
begin
  if not RangeOffsets(aSource, aStatement.fBodyRange, lBodyOffsets) then
    Exit;
  if aStatement.fHasScopedDeclarationInBody then
    Exit;
  if aStatement.fHasUnsupportedIdentifierRoleInBody then
    Exit;
  if not FindRoutineForStatement(aInventory, aStatement, lRoutineName) then
    lRoutineName := '';

  BuildReceiverStack(aInventory, aScanResult, aStatement, lRoutineName, lReceivers);
  lSkipRanges := TList<TRemoveWithOffsetRange>.Create;
  try
    for lStatement in aScanResult.fWithStatements do
    begin
      if StatementContains(aStatement, lStatement) and RangeOffsets(aSource, lStatement.fRange, lWithOffsets) then
        lSkipRanges.Add(lWithOffsets);
    end;
    CollectIdentifierUses(aSource, lBodyOffsets, lSkipRanges.ToArray, lUses);
  finally
    lSkipRanges.Free;
  end;

  for lUse in lUses do
  begin
    if not ClassifyUse(aInventory, aSource, lRoutineName, lReceivers, lUse, lClassification) then
      Continue;
    lClassification.fStatementId := aStatement.fId;
    lClassification.fFilePath := aStatement.fFilePath;
    AddClassification(aResult, lClassification);
  end;
end;

class function TRemoveWithIdentifierResolver.Resolve(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; out aResult: TRemoveWithResolverResult; out aError: string): Boolean;
var
  lCurrentPath: string;
  lSource: TRemoveWithSourceBuffer;
  lStatement: TRemoveWithStatementInfo;
begin
  aResult := Default(TRemoveWithResolverResult);
  aError := '';
  Result := False;
  lCurrentPath := '';
  lSource := Default(TRemoveWithSourceBuffer);
  BeginResolverCache;
  try
    try
      for lStatement in aScanResult.fWithStatements do
      begin
        if not SameText(lCurrentPath, lStatement.fFilePath) then
        begin
          if not LoadRemoveWithSource(lStatement.fFilePath, lSource, aError) then
            Exit(False);
          lCurrentPath := lStatement.fFilePath;
        end;
        ResolveStatement(aInventory, aScanResult, lStatement, lSource, aResult);
      end;
      Result := True;
    except
      on E: Exception do
        aError := E.Message;
    end;
  finally
    EndResolverCache;
  end;
end;

function ResolveRemoveWithIdentifiers(const aInventory: TRemoveWithSymbolInventory;
  const aScanResult: TRemoveWithScanResult; out aResult: TRemoveWithResolverResult; out aError: string): Boolean;
begin
  Result := TRemoveWithIdentifierResolver.Resolve(aInventory, aScanResult, aResult, aError);
end;

end.
