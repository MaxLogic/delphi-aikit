unit Dak.RemoveWith.Resolver;

interface

uses
  Dak.RemoveWith.Discovery, Dak.RemoveWith.SymbolMap, Dak.RemoveWith.Symbols;

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
    fSymbolMapKind: string;
    fSymbolMapSourceKind: string;
    fSymbolMapConfidence: string;
    fSymbolMapOwnerName: string;
    fSymbolMapReason: string;
    fMemberKind: TRemoveWithSymbolKind;
    fReason: string;
    fLine: Integer;
    fColumn: Integer;
    fSymbolMapFound: Boolean;
    fStatus: TRemoveWithIdentifierStatus;
  end;

  TRemoveWithResolverResult = record
    fClassifications: TArray<TRemoveWithIdentifierClassification>;
  end;

function RemoveWithIdentifierStatusToText(const aStatus: TRemoveWithIdentifierStatus): string;
function ResolveRemoveWithIdentifiers(const aInventory: TRemoveWithFactSet;
  const aScanResult: TRemoveWithScanResult; out aResult: TRemoveWithResolverResult; out aError: string): Boolean;
  overload;
function ResolveRemoveWithIdentifiers(const aInventory: TRemoveWithFactSet;
  const aScanResult: TRemoveWithScanResult; const aSymbolMapBridge: TRemoveWithSymbolMapBridge;
  out aResult: TRemoveWithResolverResult; out aError: string): Boolean; overload;
function ResolveRemoveWithIdentifiersFromSemanticFacts(const aInventory: TRemoveWithFactSet;
  const aScanResult: TRemoveWithScanResult; out aResult: TRemoveWithResolverResult;
  out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  DelphiSemantics.Model, DelphiSemantics.WithBinding,
  MaxLogic.StrUtils,
  Dak.RemoveWith.Expressions, Dak.RemoveWith.Model, Dak.RemoveWith.Source;

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

  TRemoveWithScopedLocalRange = record
    fName: string;
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

  TRemoveWithSemanticBindingEntries = TArray<TRemoveWithSemanticWithBinding>;

  TRemoveWithIdentifierResolver = record
  private
    class function DirectTypeName(const aTypeName: string): string; static;
    class function CanonicalSourceTypeName(const aInventory: TRemoveWithFactSet;
      const aTypeName: string): string; static;
    class function ElementTypeName(const aTypeName: string): string; static;
    class function IsDirectMemberKind(const aKind: TRemoveWithSymbolKind): Boolean; static;
    class function IsIdentifierChar(const aValue: Char): Boolean; static;
    class function IsKeyword(const aName: string): Boolean; static;
    class function IsControlCharacterLiteralStart(const aText: string; const aOffset,
      aEndOffset: Integer): Boolean; static;
    class function IsWhitespace(const aValue: Char): Boolean; static;
    class function PreviousNonWhitespaceChar(const aText: string; const aOffset: Integer): Char; static;
    class function NextNonWhitespaceChar(const aText: string; const aOffset: Integer): Char; static;
    class function LastIdentifierSegment(const aText: string): string; static;
    class function ArrayElementTypeName(const aInventory: TRemoveWithFactSet;
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
    class function FindRoutineForStatement(const aInventory: TRemoveWithFactSet;
      const aStatement: TRemoveWithStatementInfo; out aRoutineName: string): Boolean; static;
    class function FindMemberCandidates(const aInventory: TRemoveWithFactSet; const aOwnerType,
      aName: string): TArray<TRemoveWithSymbolInfo>; static;
    class function FindDefaultPropertyCandidate(const aInventory: TRemoveWithFactSet;
      const aOwnerType: string): Boolean; static;
    class function FindDefaultPropertySymbol(const aInventory: TRemoveWithFactSet; const aOwnerType: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindLexicalParentRoutineName(const aInventory: TRemoveWithFactSet;
      const aRoutineName: string; out aParentRoutineName: string): Boolean; static;
    class function RoutineSymbolContainsLine(const aRoutine: TRemoveWithSymbolInfo; const aFilePath: string;
      const aLine: Integer): Boolean; static;
    class function SymbolFileMatches(const aSymbol: TRemoveWithSymbolInfo; const aFilePath: string): Boolean; static;
    class function FindScopeSymbol(const aInventory: TRemoveWithFactSet; const aRoutineName,
      aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindScopeSymbolAtLocation(const aInventory: TRemoveWithFactSet; const aFilePath: string;
      const aLine: Integer; const aRoutineName, aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindUnitNameSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindExternalUnitSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindTypeNameSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function HasSourceType(const aInventory: TRemoveWithFactSet; const aTypeName: string): Boolean;
      static;
    class function IsExternalType(const aInventory: TRemoveWithFactSet; const aTypeName: string): Boolean;
      static;
    class function HasExternalAncestor(const aInventory: TRemoveWithFactSet; const aTypeName: string): Boolean;
      static;
    class function PointerTargetType(const aInventory: TRemoveWithFactSet; const aTypeName: string): string;
      static;
    class function IsHelperType(const aInventory: TRemoveWithFactSet; const aTypeName: string): Boolean;
      static;
    class function FindAncestorMember(const aInventory: TRemoveWithFactSet; const aOwnerType,
      aName: string; out aSourceOwnerType: string): Boolean; static;
    class function ResolutionKindForCandidate(const aInventory: TRemoveWithFactSet; const aReceiverType: string;
      const aCandidate: TRemoveWithSymbolInfo; out aSourceOwnerType: string): string; static;
    class function CandidateDeclaresOverride(const aCandidate: TRemoveWithSymbolInfo): Boolean; static;
    class function AllCandidatesAreMethods(const aCandidates: TArray<TRemoveWithSymbolInfo>): Boolean; static;
    class function CandidatesShareSourceOwner(const aCandidates: TArray<TRemoveWithSymbolInfo>): Boolean; static;
    class function IsCallUse(const aSource: TRemoveWithSourceBuffer; const aUse: TRemoveWithIdentifierUse): Boolean;
      static;
    class function IsAssignmentTargetUse(const aSource: TRemoveWithSourceBuffer;
      const aUse: TRemoveWithIdentifierUse): Boolean; static;
    class function FindSemanticExternalRoutineSymbol(const aInventory: TRemoveWithFactSet; const aName: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function IsDelphiIntrinsicRoutineUse(const aInventory: TRemoveWithFactSet;
      const aSource: TRemoveWithSourceBuffer; const aUse: TRemoveWithIdentifierUse): Boolean; static;
    class function IsDelphiIntrinsicTypeName(const aName: string): Boolean; static;
    class function IsDelphiIntrinsicUnitName(const aName: string): Boolean; static;
    class function FindSymbolMapCompilerIntrinsic(const aBridge: TRemoveWithSymbolMapBridge; const aName,
      aKind: string; out aLookup: TRemoveWithSymbolMapLookup): Boolean; static;
    class function FindSymbolMapExternalRoutine(const aBridge: TRemoveWithSymbolMapBridge; const aName: string;
      out aLookup: TRemoveWithSymbolMapLookup): Boolean; static;
    class function ShouldLookupSymbolMapRoutineIntrinsic(const aSource: TRemoveWithSourceBuffer;
      const aUse: TRemoveWithIdentifierUse): Boolean; static;
    class function IsVisibleRtlRoutineUse(const aInventory: TRemoveWithFactSet;
      const aSource: TRemoveWithSourceBuffer; const aUse: TRemoveWithIdentifierUse): Boolean; static;
    class function IsExternalRoutineCall(const aInventory: TRemoveWithFactSet; const aSource: TRemoveWithSourceBuffer;
      const aUse: TRemoveWithIdentifierUse): Boolean; static;
    class function PlaceholderRecordTypeName(const aTypeName: string): Boolean; static;
    class function ReceiversAllowUnresolvedFallback(const aInventory: TRemoveWithFactSet;
      const aReceivers: TArray<TRemoveWithReceiverScope>): Boolean; static;
    class function IsQualifiedUse(const aSource: TRemoveWithSourceBuffer; const aUse: TRemoveWithIdentifierUse):
      Boolean; static;
    class function SemanticBindingMatchesStatement(const aBinding: TDelphiSemanticWithBinding;
      const aStatement: TRemoveWithStatementInfo): Boolean; overload; static;
    class function SemanticBindingMatchesStatement(const aEntry: TRemoveWithSemanticWithBinding;
      const aStatement: TRemoveWithStatementInfo): Boolean; overload; static;
    class function NormalizedSemanticSelectorText(const aSelectorText: string): string; static;
    class function TryFindSemanticBindingForStatement(const aInventory: TRemoveWithFactSet;
      const aStatement: TRemoveWithStatementInfo; out aBinding: TDelphiSemanticWithBinding): Boolean; static;
    class function SemanticBindingBlocksStatement(const aInventory: TRemoveWithFactSet;
      const aStatement: TRemoveWithStatementInfo): Boolean; static;
    class function TryApplySemanticSelectorInfo(const aInventory: TRemoveWithFactSet;
      const aBinding: TDelphiSemanticWithBinding;
      const aSelectorText: string; var aInfo: TRemoveWithSelectorTypeInfo): Boolean; static;
    class function TryFindSemanticReferenceForUse(const aBinding: TDelphiSemanticWithBinding;
      const aUse: TRemoveWithIdentifierUse; out aReference: TDelphiSemanticBoundReference): Boolean; static;
    class function SemanticKindToRemoveWithKind(const aKind: string): TRemoveWithSymbolKind; static;
    class function SemanticTypeNamesMatch(const aInventory: TRemoveWithFactSet; const aLeft,
      aRight: string): Boolean; static;
    class function ResolveSelectorFromReceivers(const aInventory: TRemoveWithFactSet;
      const aReceivers: TArray<TRemoveWithReceiverScope>; const aSelectorText: string;
      out aInfo: TRemoveWithSelectorTypeInfo): Boolean; static;
    class function SelectorUsesUnsupportedProperty(const aInventory: TRemoveWithFactSet; const aRoutineName,
      aSelectorText: string): Boolean; static;
    class procedure NormalizeSelectorInfo(const aInventory: TRemoveWithFactSet; const aRoutineName,
      aSelectorText: string; var aInfo: TRemoveWithSelectorTypeInfo); static;
    class procedure AddClassification(var aResult: TRemoveWithResolverResult;
      const aClassification: TRemoveWithIdentifierClassification); static;
    class function ShouldEnrichWithSymbolMap(const aClassification: TRemoveWithIdentifierClassification): Boolean;
      static;
    class procedure EnrichWithSymbolMap(const aBridge: TRemoveWithSymbolMapBridge;
      var aClassification: TRemoveWithIdentifierClassification); static;
    class procedure EnrichWithSemanticFacts(const aInventory: TRemoveWithFactSet;
      var aClassification: TRemoveWithIdentifierClassification); static;
    class procedure CollectIdentifierUses(const aSource: TRemoveWithSourceBuffer;
      const aBodyOffsets: TRemoveWithOffsetRange; const aSkipRanges: TArray<TRemoveWithOffsetRange>;
      out aUses: TArray<TRemoveWithIdentifierUse>); static;
    class procedure BuildReceiverStack(const aInventory: TRemoveWithFactSet;
      const aScanResult: TRemoveWithScanResult; const aStatement: TRemoveWithStatementInfo;
      const aRoutineName, aSelectorRoutineName: string; const aBinding: TDelphiSemanticWithBinding;
      out aReceivers: TArray<TRemoveWithReceiverScope>); static;
    class function ClassifyUse(const aInventory: TRemoveWithFactSet; const aSource: TRemoveWithSourceBuffer;
      const aRoutineName: string; const aReceivers: TArray<TRemoveWithReceiverScope>;
      const aBinding: TDelphiSemanticWithBinding; const aUse: TRemoveWithIdentifierUse;
      const aSymbolMapBridge: TRemoveWithSymbolMapBridge;
      out aClassification: TRemoveWithIdentifierClassification): Boolean; static;
    class procedure ResolveStatement(const aInventory: TRemoveWithFactSet;
      const aScanResult: TRemoveWithScanResult; const aStatement: TRemoveWithStatementInfo;
      const aSource: TRemoveWithSourceBuffer; const aSymbolMapBridge: TRemoveWithSymbolMapBridge;
      const aInactiveRanges: TArray<TRemoveWithInactiveRange>;
      var aResult: TRemoveWithResolverResult); static;
  public
    class function Resolve(const aInventory: TRemoveWithFactSet; const aScanResult: TRemoveWithScanResult;
      out aResult: TRemoveWithResolverResult; out aError: string): Boolean; overload; static;
    class function Resolve(const aInventory: TRemoveWithFactSet; const aScanResult: TRemoveWithScanResult;
      const aSymbolMapBridge: TRemoveWithSymbolMapBridge; out aResult: TRemoveWithResolverResult;
      out aError: string): Boolean; overload; static;
  end;

var
  GResolverAncestorMemberCache: TDictionary<string, TRemoveWithTextLookup>;
  GResolverBoolCache: TDictionary<string, Boolean>;
  GResolverContainingStatementsById: TDictionary<string, TArray<TRemoveWithStatementInfo>>;
  GResolverExternalUnitCache: TDictionary<string, TRemoveWithSymbolLookup>;
  GResolverMemberCandidateCache: TDictionary<string, TArray<TRemoveWithSymbolInfo>>;
  GResolverNestedStatementsById: TDictionary<string, TArray<TRemoveWithStatementInfo>>;
  GResolverParentRoutineByName: TDictionary<string, string>;
  GResolverRoutinesByFile: TDictionary<string, TArray<TRemoveWithSymbolInfo>>;
  GResolverScopeSymbolCache: TDictionary<string, TRemoveWithSymbolLookup>;
  GResolverSemanticBindingsByStatementRange: TDictionary<string, TRemoveWithSemanticBindingEntries>;
  GResolverTypeNameCache: TDictionary<string, TRemoveWithSymbolLookup>;
  GResolverUnitNameCache: TDictionary<string, TRemoveWithSymbolLookup>;

function ResolverCacheKey(const aFirst, aSecond: string): string; overload;
const
  cSeparator = #31;
begin
  Result := aFirst + cSeparator + aSecond;
end;

function SemanticBindingRangeKey(const aFilePath: string; const aLine,
  aColumn: Integer): string;
begin
  Result := TPath.GetFullPath(aFilePath) + #31 + IntToStr(aLine) + #31 +
    IntToStr(aColumn);
end;

function ResolverCacheKey(const aFirst, aSecond, aThird: string): string; overload;
const
  cSeparator = #31;
begin
  Result := aFirst + cSeparator + aSecond + cSeparator + aThird;
end;

function SymbolKindForModelMemberKind(const aKind: TRemoveWithModelMemberKind): TRemoveWithSymbolKind;
begin
  case aKind of
    TRemoveWithModelMemberKind.rwmmProperty:
      Result := TRemoveWithSymbolKind.rwskProperty;
    TRemoveWithModelMemberKind.rwmmMethod:
      Result := TRemoveWithSymbolKind.rwskMethod;
    TRemoveWithModelMemberKind.rwmmConstant:
      Result := TRemoveWithSymbolKind.rwskConstant;
    TRemoveWithModelMemberKind.rwmmClassVar:
      Result := TRemoveWithSymbolKind.rwskClassVar;
  else
    Result := TRemoveWithSymbolKind.rwskField;
  end;
end;

function SymbolKindForModelRoutineSymbolKind(
  const aKind: TRemoveWithModelRoutineSymbolKind): TRemoveWithSymbolKind;
begin
  case aKind of
    TRemoveWithModelRoutineSymbolKind.rwmrsParameter:
      Result := TRemoveWithSymbolKind.rwskParameter;
  else
    Result := TRemoveWithSymbolKind.rwskLocalVariable;
  end;
end;

function TypeCategoryForModelKind(const aKind: TRemoveWithModelTypeKind): TRemoveWithTypeCategory;
begin
  case aKind of
    TRemoveWithModelTypeKind.rwmtRecord:
      Result := TRemoveWithTypeCategory.rwtcRecord;
    TRemoveWithModelTypeKind.rwmtClass:
      Result := TRemoveWithTypeCategory.rwtcClass;
    TRemoveWithModelTypeKind.rwmtInterface:
      Result := TRemoveWithTypeCategory.rwtcInterface;
  else
    Result := TRemoveWithTypeCategory.rwtcUnknown;
  end;
end;

function SymbolFromModelMember(const aMember: TRemoveWithModelMemberInfo): TRemoveWithSymbolInfo;
begin
  Result := Default(TRemoveWithSymbolInfo);
  Result.fName := aMember.fName;
  Result.fTypeName := aMember.fTypeName;
  Result.fOwnerType := aMember.fOwnerType;
  Result.fSourceOwnerType := aMember.fOwnerType;
  Result.fIsDefault := aMember.fIsDefault;
  Result.fKind := SymbolKindForModelMemberKind(aMember.fKind);
end;

function SymbolFromModelRoutineSymbol(const aSymbol: TRemoveWithModelRoutineSymbolInfo): TRemoveWithSymbolInfo;
begin
  Result := Default(TRemoveWithSymbolInfo);
  Result.fName := aSymbol.fName;
  Result.fTypeName := aSymbol.fTypeName;
  Result.fRoutineName := aSymbol.fRoutineName;
  Result.fKind := SymbolKindForModelRoutineSymbolKind(aSymbol.fKind);
end;

function SymbolFromModelType(const aTypeInfo: TRemoveWithModelTypeInfo): TRemoveWithSymbolInfo;
begin
  Result := Default(TRemoveWithSymbolInfo);
  Result.fName := aTypeInfo.fName;
  Result.fTypeName := aTypeInfo.fName;
  Result.fRelatedTypeName := aTypeInfo.fRelatedTypeName;
  Result.fIsHelper := aTypeInfo.fKind = TRemoveWithModelTypeKind.rwmtHelper;
  Result.fTypeCategory := TypeCategoryForModelKind(aTypeInfo.fKind);
  Result.fKind := TRemoveWithSymbolKind.rwskTypeMember;
end;

function SymbolFromModelUnit(const aUnitModel: TRemoveWithUnitModel): TRemoveWithSymbolInfo;
begin
  Result := Default(TRemoveWithSymbolInfo);
  Result.fName := aUnitModel.fUnitName;
  Result.fUnitName := aUnitModel.fUnitName;
  Result.fFilePath := aUnitModel.fFilePath;
  Result.fKind := TRemoveWithSymbolKind.rwskUnitName;
end;

procedure AddResolverSemanticBindingBucket(
  const aIndex: TDictionary<string, TRemoveWithSemanticBindingEntries>;
  const aKey: string; const aEntry: TRemoveWithSemanticWithBinding);
var
  lEntries: TRemoveWithSemanticBindingEntries;
  lIndex: Integer;
begin
  if not aIndex.TryGetValue(aKey, lEntries) then
    lEntries := nil;
  lIndex := Length(lEntries);
  SetLength(lEntries, lIndex + 1);
  lEntries[lIndex] := aEntry;
  aIndex.AddOrSetValue(aKey, lEntries);
end;

procedure BeginResolverSemanticBindingCache(const aInventory: TRemoveWithFactSet);
var
  lEntry: TRemoveWithSemanticWithBinding;
begin
  GResolverSemanticBindingsByStatementRange := TDictionary<string, TRemoveWithSemanticBindingEntries>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  for lEntry in aInventory.fDelphiSemanticWithBindingEntries do
    AddResolverSemanticBindingBucket(GResolverSemanticBindingsByStatementRange,
      SemanticBindingRangeKey(lEntry.fFilePath, lEntry.fBinding.Line, lEntry.fBinding.Column),
      lEntry);
end;

procedure EndResolverCache; forward;

procedure BeginResolverCache(const aInventory: TRemoveWithFactSet);
begin
  try
    GResolverAncestorMemberCache := TDictionary<string, TRemoveWithTextLookup>.Create(
      TFastCaseAwareComparer.OrdinalIgnoreCase);
    GResolverBoolCache := TDictionary<string, Boolean>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
    GResolverContainingStatementsById := nil;
    GResolverExternalUnitCache := TDictionary<string, TRemoveWithSymbolLookup>.Create(
      TFastCaseAwareComparer.OrdinalIgnoreCase);
    GResolverMemberCandidateCache := TDictionary<string, TArray<TRemoveWithSymbolInfo>>.Create(
      TFastCaseAwareComparer.OrdinalIgnoreCase);
    GResolverNestedStatementsById := nil;
    GResolverParentRoutineByName := nil;
    GResolverRoutinesByFile := nil;
    GResolverScopeSymbolCache := TDictionary<string, TRemoveWithSymbolLookup>.Create(
      TFastCaseAwareComparer.OrdinalIgnoreCase);
    BeginResolverSemanticBindingCache(aInventory);
    GResolverTypeNameCache := TDictionary<string, TRemoveWithSymbolLookup>.Create(
      TFastCaseAwareComparer.OrdinalIgnoreCase);
    GResolverUnitNameCache := TDictionary<string, TRemoveWithSymbolLookup>.Create(
      TFastCaseAwareComparer.OrdinalIgnoreCase);
  except
    EndResolverCache;
    raise;
  end;
end;

procedure EndResolverCache;
begin
  GResolverUnitNameCache.Free;
  GResolverUnitNameCache := nil;
  GResolverTypeNameCache.Free;
  GResolverTypeNameCache := nil;
  GResolverScopeSymbolCache.Free;
  GResolverScopeSymbolCache := nil;
  GResolverSemanticBindingsByStatementRange.Free;
  GResolverSemanticBindingsByStatementRange := nil;
  GResolverMemberCandidateCache.Free;
  GResolverMemberCandidateCache := nil;
  GResolverNestedStatementsById.Free;
  GResolverNestedStatementsById := nil;
  GResolverParentRoutineByName.Free;
  GResolverParentRoutineByName := nil;
  GResolverRoutinesByFile.Free;
  GResolverRoutinesByFile := nil;
  GResolverExternalUnitCache.Free;
  GResolverExternalUnitCache := nil;
  GResolverBoolCache.Free;
  GResolverBoolCache := nil;
  GResolverContainingStatementsById.Free;
  GResolverContainingStatementsById := nil;
  GResolverAncestorMemberCache.Free;
  GResolverAncestorMemberCache := nil;
end;

procedure AddResolverStatementBucket(
  const aBuckets: TDictionary<string, TList<TRemoveWithStatementInfo>>;
  const aStatementId: string; const aStatement: TRemoveWithStatementInfo);
var
  lList: TList<TRemoveWithStatementInfo>;
begin
  if not aBuckets.TryGetValue(aStatementId, lList) then
  begin
    lList := TList<TRemoveWithStatementInfo>.Create;
    aBuckets.Add(aStatementId, lList);
  end;
  lList.Add(aStatement);
end;

function BuildResolverStatementIndex(
  const aBuckets: TDictionary<string, TList<TRemoveWithStatementInfo>>):
  TDictionary<string, TArray<TRemoveWithStatementInfo>>;
var
  lIndex: TDictionary<string, TArray<TRemoveWithStatementInfo>>;
  lPair: TPair<string, TList<TRemoveWithStatementInfo>>;
begin
  lIndex := TDictionary<string, TArray<TRemoveWithStatementInfo>>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for lPair in aBuckets do
      lIndex.Add(lPair.Key, lPair.Value.ToArray);
    Result := lIndex;
    lIndex := nil;
  finally
    lIndex.Free;
  end;
end;

procedure BeginResolverStatementContextCache(const aScanResult: TRemoveWithScanResult);
var
  lContainingBuckets: TDictionary<string, TList<TRemoveWithStatementInfo>>;
  lNestedBuckets: TDictionary<string, TList<TRemoveWithStatementInfo>>;
  lOuterStatement: TRemoveWithStatementInfo;
  lPair: TPair<string, TList<TRemoveWithStatementInfo>>;
  lStatement: TRemoveWithStatementInfo;
begin
  lContainingBuckets := TDictionary<string, TList<TRemoveWithStatementInfo>>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  lNestedBuckets := TDictionary<string, TList<TRemoveWithStatementInfo>>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for lStatement in aScanResult.fWithStatements do
      for lOuterStatement in aScanResult.fWithStatements do
      begin
        if TRemoveWithIdentifierResolver.StatementContains(lOuterStatement, lStatement) then
          AddResolverStatementBucket(lContainingBuckets, lStatement.fId,
            lOuterStatement);
        if TRemoveWithIdentifierResolver.StatementContains(lStatement, lOuterStatement) then
          AddResolverStatementBucket(lNestedBuckets, lStatement.fId,
            lOuterStatement);
      end;
    GResolverContainingStatementsById := BuildResolverStatementIndex(lContainingBuckets);
    GResolverNestedStatementsById := BuildResolverStatementIndex(lNestedBuckets);
  finally
    for lPair in lNestedBuckets do
      lPair.Value.Free;
    lNestedBuckets.Free;
    for lPair in lContainingBuckets do
      lPair.Value.Free;
    lContainingBuckets.Free;
  end;
end;

procedure EndResolverStatementContextCache;
begin
  GResolverNestedStatementsById.Free;
  GResolverNestedStatementsById := nil;
  GResolverContainingStatementsById.Free;
  GResolverContainingStatementsById := nil;
end;

procedure EnsureResolverRoutinesByFile(const aInventory: TRemoveWithFactSet);
var
  lBuckets: TDictionary<string, TList<TRemoveWithSymbolInfo>>;
  lIndex: TDictionary<string, TArray<TRemoveWithSymbolInfo>>;
  lList: TList<TRemoveWithSymbolInfo>;
  lPair: TPair<string, TList<TRemoveWithSymbolInfo>>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if GResolverRoutinesByFile <> nil then
    Exit;

  lBuckets := TDictionary<string, TList<TRemoveWithSymbolInfo>>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for lSymbol in aInventory.fSymbols do
    begin
      if (lSymbol.fKind <> TRemoveWithSymbolKind.rwskRoutine) or (lSymbol.fFilePath = '') then
        Continue;
      if not lBuckets.TryGetValue(lSymbol.fFilePath, lList) then
      begin
        lList := TList<TRemoveWithSymbolInfo>.Create;
        lBuckets.Add(lSymbol.fFilePath, lList);
      end;
      lList.Add(lSymbol);
    end;

    lIndex := TDictionary<string, TArray<TRemoveWithSymbolInfo>>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
    try
      for lPair in lBuckets do
        lIndex.Add(lPair.Key, lPair.Value.ToArray);
      GResolverRoutinesByFile := lIndex;
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

function UnsupportedRoleCanRemainUnchanged(const aRole: string): Boolean;
begin
  Result := MatchText(aRole, ['type-name', 'variable-declaration']);
end;

procedure AddScopedLocalName(var aNames: TArray<TRemoveWithScopedLocalRange>; const aName: string;
  const aStartOffset, aEndOffset: Integer);
var
  lIndex: Integer;
  lNameRange: TRemoveWithScopedLocalRange;
begin
  if aName = '' then
    Exit;
  for lNameRange in aNames do
  begin
    if SameText(lNameRange.fName, aName) and (lNameRange.fStartOffset = aStartOffset) and
      (lNameRange.fEndOffset = aEndOffset) then
      Exit;
  end;
  lIndex := Length(aNames);
  SetLength(aNames, lIndex + 1);
  aNames[lIndex].fName := aName;
  aNames[lIndex].fStartOffset := aStartOffset;
  aNames[lIndex].fEndOffset := aEndOffset;
end;

function ScopedLocalNameExistsAt(const aNames: TArray<TRemoveWithScopedLocalRange>; const aName: string;
  const aOffset: Integer): Boolean;
var
  lNameRange: TRemoveWithScopedLocalRange;
begin
  Result := False;
  for lNameRange in aNames do
  begin
    if SameText(lNameRange.fName, aName) and (aOffset >= lNameRange.fStartOffset) and
      (aOffset <= lNameRange.fEndOffset) then
      Exit(True);
  end;
end;

function IsGenericTypeNameUse(const aSource: TRemoveWithSourceBuffer; const aUse: TRemoveWithIdentifierUse): Boolean;
var
  lDepth: Integer;
  lLessThanOffset: Integer;
  lNextOffset: Integer;
begin
  Result := False;
  lLessThanOffset := aUse.fEndOffset + 1;
  if (lLessThanOffset > Length(aSource.fText)) or (aSource.fText[lLessThanOffset] <> '<') then
    Exit;

  lNextOffset := lLessThanOffset + 1;
  while (lNextOffset <= Length(aSource.fText)) and
    CharInSet(aSource.fText[lNextOffset], [#9, #10, #13, ' ']) do
    Inc(lNextOffset);
  if (lNextOffset > Length(aSource.fText)) or
    not CharInSet(aSource.fText[lNextOffset], ['A'..'Z', 'a'..'z', '_']) then
    Exit;

  lDepth := 1;
  lNextOffset := lLessThanOffset + 1;
  while lNextOffset <= Length(aSource.fText) do
  begin
    if aSource.fText[lNextOffset] = '''' then
    begin
      Inc(lNextOffset);
      while lNextOffset <= Length(aSource.fText) do
      begin
        if aSource.fText[lNextOffset] = '''' then
        begin
          Inc(lNextOffset);
          if (lNextOffset <= Length(aSource.fText)) and (aSource.fText[lNextOffset] = '''') then
          begin
            Inc(lNextOffset);
            Continue;
          end;
          Break;
        end;
        Inc(lNextOffset);
      end;
      Continue;
    end;
    if CharInSet(aSource.fText[lNextOffset], [';', #10, #13]) then
      Exit;
    if aSource.fText[lNextOffset] = '<' then
      Inc(lDepth)
    else if aSource.fText[lNextOffset] = '>' then
    begin
      Dec(lDepth);
      if lDepth = 0 then
      begin
        Inc(lNextOffset);
        while (lNextOffset <= Length(aSource.fText)) and
          CharInSet(aSource.fText[lNextOffset], [#9, #10, #13, ' ']) do
          Inc(lNextOffset);
        Exit((lNextOffset > Length(aSource.fText)) or
          CharInSet(aSource.fText[lNextOffset], ['.', '(', ')', ',', ';', ']', ':', '=']));
      end;
    end;
    Inc(lNextOffset);
  end;
end;

function ReadIdentifierAt(const aText: string; var aOffset: Integer; const aEndOffset: Integer): string;
var
  lStartOffset: Integer;
begin
  Result := '';
  while (aOffset <= aEndOffset) and CharInSet(aText[aOffset], [#9, #10, #13, ' ']) do
    Inc(aOffset);
  if (aOffset > aEndOffset) or not CharInSet(aText[aOffset], ['A'..'Z', 'a'..'z', '_']) then
    Exit;
  lStartOffset := aOffset;
  while (aOffset <= aEndOffset) and CharInSet(aText[aOffset], ['A'..'Z', 'a'..'z', '_', '0'..'9']) do
    Inc(aOffset);
  Result := Copy(aText, lStartOffset, aOffset - lStartOffset);
end;

procedure SkipDelimitedText(const aText: string; var aOffset: Integer; const aEndOffset: Integer);
begin
  Inc(aOffset);
  while aOffset <= aEndOffset do
  begin
    if aText[aOffset] = '''' then
    begin
      Inc(aOffset);
      if (aOffset <= aEndOffset) and (aText[aOffset] = '''') then
      begin
        Inc(aOffset);
        Continue;
      end;
      Break;
    end;
    Inc(aOffset);
  end;
end;

procedure SkipBraceText(const aText: string; var aOffset: Integer; const aEndOffset: Integer);
begin
  while (aOffset <= aEndOffset) and (aText[aOffset] <> '}') do
    Inc(aOffset);
  Inc(aOffset);
end;

procedure SkipParenText(const aText: string; var aOffset: Integer; const aEndOffset: Integer);
begin
  Inc(aOffset, 2);
  while (aOffset < aEndOffset) and ((aText[aOffset] <> '*') or (aText[aOffset + 1] <> ')')) do
    Inc(aOffset);
  Inc(aOffset, 2);
end;

procedure SkipLineText(const aText: string; var aOffset: Integer; const aEndOffset: Integer);
begin
  Inc(aOffset, 2);
  while (aOffset <= aEndOffset) and not CharInSet(aText[aOffset], [#10, #13]) do
    Inc(aOffset);
end;

function FindScopedLocalEndOffset(const aSource: TRemoveWithSourceBuffer; const aBodyOffsets: TRemoveWithOffsetRange;
  const aDeclarationOffset: Integer): Integer;
var
  lDeclarationDepth: Integer;
  lDepth: Integer;
  lEndOffset: Integer;
  lOffset: Integer;
  lTokenStartOffset: Integer;
  lToken: string;
begin
  Result := RemoveWithInclusiveEndOffset(aSource, aBodyOffsets.fEndOffset);
  lDeclarationDepth := -1;
  lDepth := 0;
  lEndOffset := Result;
  lOffset := aBodyOffsets.fStartOffset;
  while lOffset <= lEndOffset do
  begin
    if aSource.fText[lOffset] = '''' then
    begin
      SkipDelimitedText(aSource.fText, lOffset, lEndOffset);
      Continue;
    end;
    if aSource.fText[lOffset] = '{' then
    begin
      SkipBraceText(aSource.fText, lOffset, lEndOffset);
      Continue;
    end;
    if (lOffset < lEndOffset) and (aSource.fText[lOffset] = '(') and (aSource.fText[lOffset + 1] = '*') then
    begin
      SkipParenText(aSource.fText, lOffset, lEndOffset);
      Continue;
    end;
    if (lOffset < lEndOffset) and (aSource.fText[lOffset] = '/') and (aSource.fText[lOffset + 1] = '/') then
    begin
      SkipLineText(aSource.fText, lOffset, lEndOffset);
      Continue;
    end;
    if not CharInSet(aSource.fText[lOffset], ['A'..'Z', 'a'..'z', '_']) then
    begin
      Inc(lOffset);
      Continue;
    end;

    lTokenStartOffset := lOffset;
    lToken := ReadIdentifierAt(aSource.fText, lOffset, lEndOffset);
    if (lDeclarationDepth < 0) and (lTokenStartOffset >= aDeclarationOffset) then
      lDeclarationDepth := lDepth;

    if MatchText(lToken, ['begin', 'case', 'try']) then
    begin
      Inc(lDepth)
    end
    else if SameText(lToken, 'end') then
    begin
      if (lTokenStartOffset > aDeclarationOffset) and (lDeclarationDepth >= 0) and
        (lDepth <= lDeclarationDepth) then
        Exit(lTokenStartOffset - 1);
      if lDepth > 0 then
        Dec(lDepth);
    end;
  end;
end;

procedure CollectScopedLocalNames(const aSource: TRemoveWithSourceBuffer;
  const aBodyOffsets: TRemoveWithOffsetRange; out aNames: TArray<TRemoveWithScopedLocalRange>);
var
  lDeclarationEndOffset: Integer;
  lDeclarationStartOffset: Integer;
  lEndOffset: Integer;
  lName: string;
  lNextOffset: Integer;
  lToken: string;
  i: Integer;
begin
  aNames := nil;
  lEndOffset := RemoveWithInclusiveEndOffset(aSource, aBodyOffsets.fEndOffset);
  i := aBodyOffsets.fStartOffset;
  while i <= lEndOffset do
  begin
    if aSource.fText[i] = '''' then
    begin
      SkipDelimitedText(aSource.fText, i, lEndOffset);
      Continue;
    end;
    if aSource.fText[i] = '{' then
    begin
      SkipBraceText(aSource.fText, i, lEndOffset);
      Continue;
    end;
    if (i < lEndOffset) and (aSource.fText[i] = '(') and (aSource.fText[i + 1] = '*') then
    begin
      SkipParenText(aSource.fText, i, lEndOffset);
      Continue;
    end;
    if (i < lEndOffset) and (aSource.fText[i] = '/') and (aSource.fText[i + 1] = '/') then
    begin
      SkipLineText(aSource.fText, i, lEndOffset);
      Continue;
    end;
    if not CharInSet(aSource.fText[i], ['A'..'Z', 'a'..'z', '_']) then
    begin
      Inc(i);
      Continue;
    end;

    lToken := ReadIdentifierAt(aSource.fText, i, lEndOffset);
    if SameText(lToken, 'var') then
    begin
      lNextOffset := i;
      lDeclarationStartOffset := lNextOffset;
      lName := ReadIdentifierAt(aSource.fText, lNextOffset, lEndOffset);
      lDeclarationEndOffset := FindScopedLocalEndOffset(aSource, aBodyOffsets, lDeclarationStartOffset);
      AddScopedLocalName(aNames, lName, lDeclarationStartOffset, lDeclarationEndOffset);
    end else if SameText(lToken, 'on') then
    begin
      lNextOffset := i;
      lDeclarationStartOffset := lNextOffset;
      lName := ReadIdentifierAt(aSource.fText, lNextOffset, lEndOffset);
      lDeclarationEndOffset := FindScopedLocalEndOffset(aSource, aBodyOffsets, lDeclarationStartOffset);
      AddScopedLocalName(aNames, lName, lDeclarationStartOffset, lDeclarationEndOffset);
    end;
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

class function TRemoveWithIdentifierResolver.PlaceholderRecordTypeName(const aTypeName: string): Boolean;
begin
  Result := MatchText(Trim(aTypeName), ['PACKED', 'RECORD']);
end;

class function TRemoveWithIdentifierResolver.CanonicalSourceTypeName(const aInventory: TRemoveWithFactSet;
  const aTypeName: string): string;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeName: string;
begin
  lTypeName := Trim(aTypeName);
  if StartsText('^', lTypeName) then
    Delete(lTypeName, 1, 1);
  if lTypeName = '' then
    Exit('');

  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
      begin
        if (lSymbol.fTypeCategory = TRemoveWithTypeCategory.rwtcUnknown) and (lSymbol.fTypeName <> '') and
          not MatchText(lSymbol.fTypeName, ['class', 'interface', 'record', 'object', 'enum']) and
          not SameText(lSymbol.fTypeName, lTypeName) then
          Exit(CanonicalSourceTypeName(aInventory, lSymbol.fTypeName));
        Exit(lTypeName);
      end;
    end;
  end;

  Result := DirectTypeName(lTypeName);
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

  if not StartsText('TArray<', lText) then
    Exit;
  lStartPos := Pos('<', lText);
  lEndPos := LastDelimiter('>', lText);
  if (lStartPos > 0) and (lEndPos > lStartPos) then
    Result := Trim(Copy(lText, lStartPos + 1, lEndPos - lStartPos - 1));
end;

class function TRemoveWithIdentifierResolver.ArrayElementTypeName(const aInventory: TRemoveWithFactSet;
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
  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
        Exit(ElementTypeName(lSymbol.fTypeName));
    end;
  end;
  lTypeName := CanonicalSourceTypeName(aInventory, aTypeName);
  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lTypeName, lSymbols) then
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
    'if', 'implementation', 'in', 'inherited', 'interface', 'is', 'mod', 'nil', 'not', 'of', 'on', 'or', 'out',
    'procedure', 'program', 'property', 'record', 'repeat', 'result', 'self', 'set', 'shl', 'shr', 'then', 'to',
    'true', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor']);
end;

class function TRemoveWithIdentifierResolver.IsControlCharacterLiteralStart(const aText: string;
  const aOffset, aEndOffset: Integer): Boolean;
begin
  Result := (aOffset < aEndOffset) and (aText[aOffset] = '^') and
    CharInSet(aText[aOffset + 1], ['A'..'Z', 'a'..'z', '@', '[', '\', ']', '^', '_']);
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

class function TRemoveWithIdentifierResolver.FindRoutineForStatement(const aInventory: TRemoveWithFactSet;
  const aStatement: TRemoveWithStatementInfo; out aRoutineName: string): Boolean;
var
  lBestLine: Integer;
  lRoutines: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  aRoutineName := '';
  lBestLine := 0;
  EnsureResolverRoutinesByFile(aInventory);
  if not GResolverRoutinesByFile.TryGetValue(aStatement.fFilePath, lRoutines) then
    Exit(False);
  for lSymbol in lRoutines do
  begin
    if (lSymbol.fLine <= aStatement.fLine) and ((lSymbol.fEndLine = 0) or
      (aStatement.fLine <= lSymbol.fEndLine)) and (lSymbol.fLine > lBestLine) then
    begin
      lBestLine := lSymbol.fLine;
      aRoutineName := lSymbol.fName;
      Result := True;
    end;
  end;
end;

class function TRemoveWithIdentifierResolver.FindMemberCandidates(const aInventory: TRemoveWithFactSet;
  const aOwnerType, aName: string): TArray<TRemoveWithSymbolInfo>;
var
  lKey: string;
  lList: TList<TRemoveWithSymbolInfo>;
  lMember: TRemoveWithModelMemberInfo;
  lModelMembers: TArray<TRemoveWithModelMemberInfo>;
  lOwnerType: string;
  lCandidate: TRemoveWithSymbolInfo;
  lRelatedTypeName: string;
  lSemanticMembers: TArray<TRemoveWithSymbolInfo>;
  lSimpleOwnerType: string;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lCandidateKeys: TDictionary<string, Byte>;

  function CandidateKey(const aSymbol: TRemoveWithSymbolInfo): string;
  begin
    Result := UpperCase(aSymbol.fName) + #31 +
      UpperCase(CanonicalSourceTypeName(aInventory, aSymbol.fTypeName)) + #31 +
      UpperCase(CanonicalSourceTypeName(aInventory, aSymbol.fOwnerType)) + #31 +
      UpperCase(CanonicalSourceTypeName(aInventory, aSymbol.fSourceOwnerType)) + #31 +
      IntToStr(Ord(aSymbol.fKind));
  end;

  function HelperTargetsOwner(const aHelperType, aOwnerType: string): Boolean;
  var
    lHelperSymbols: TArray<TRemoveWithSymbolInfo>;
    lHelperSymbol: TRemoveWithSymbolInfo;
  begin
    Result := False;
    if (aHelperType = '') or (aOwnerType = '') then
      Exit;

    if not FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, aHelperType,
      lHelperSymbols) then
      Exit;

    for lHelperSymbol in lHelperSymbols do
    begin
      if (lHelperSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and lHelperSymbol.fIsHelper and
        SameText(CanonicalSourceTypeName(aInventory, lHelperSymbol.fRelatedTypeName), aOwnerType) then
        Exit(True);
    end;
  end;

  procedure AddCandidate(const aSymbol: TRemoveWithSymbolInfo);
  var
    lCandidate: TRemoveWithSymbolInfo;
    lCandidateKey: string;
    lNestedTypeName: string;
  begin
    lCandidate := aSymbol;
    if SameText(CanonicalSourceTypeName(aInventory, lCandidate.fTypeName), lCandidate.fName) then
    begin
      lNestedTypeName := CanonicalSourceTypeName(aInventory, lCandidate.fOwnerType + '.' + lCandidate.fName);
      if Pos('.', lNestedTypeName) > 0 then
        lCandidate.fTypeName := lNestedTypeName;
    end;
    lCandidateKey := CandidateKey(lCandidate);
    if lCandidateKeys.ContainsKey(lCandidateKey) then
      Exit;
    lCandidateKeys.Add(lCandidateKey, 1);
    lList.Add(lCandidate);
  end;
begin
  lOwnerType := CanonicalSourceTypeName(aInventory, aOwnerType);
  lKey := ResolverCacheKey('member', lOwnerType, aName);
  if (GResolverMemberCandidateCache <> nil) and GResolverMemberCandidateCache.TryGetValue(lKey, Result) then
    Exit;

  lList := TList<TRemoveWithSymbolInfo>.Create;
  lCandidateKeys := TDictionary<string, Byte>.Create;
  try
    lSimpleOwnerType := DirectTypeName(aOwnerType);
    if not FindRemoveWithFactSetMembers(aInventory, lOwnerType, aName, lSemanticMembers) then
    begin
      if not FindRemoveWithFactSetMembers(aInventory, lSimpleOwnerType, aName, lSemanticMembers) then
        lSemanticMembers := nil;
    end;
    if Length(lSemanticMembers) > 0 then
    begin
      for lSymbol in lSemanticMembers do
        if IsDirectMemberKind(lSymbol.fKind) and (not PlaceholderRecordTypeName(lSymbol.fTypeName)) then
          AddCandidate(lSymbol);
    end;
    if (lList.Count = 0) and FindRemoveWithFactSetSymbolsByName(aInventory, aName,
      lSymbols) then
    begin
      for lSymbol in lSymbols do
      begin
        if (SameText(lSymbol.fOwnerType, lOwnerType) or SameText(lSymbol.fOwnerType, lSimpleOwnerType)) and
          (lSymbol.fRoutineName = '') and IsDirectMemberKind(lSymbol.fKind) and
          (not PlaceholderRecordTypeName(lSymbol.fTypeName)) then
          AddCandidate(lSymbol);
      end;
    end;
    if (lList.Count = 0) and FindRemoveWithFactSetSymbolsByName(aInventory, aName,
      lSymbols) then
    begin
      for lSymbol in lSymbols do
      begin
        if (lSymbol.fRoutineName = '') and IsDirectMemberKind(lSymbol.fKind) and
          HelperTargetsOwner(lSymbol.fOwnerType, lOwnerType) then
        begin
          lCandidate := lSymbol;
          lCandidate.fSourceOwnerType := lSymbol.fOwnerType;
          lCandidate.fOwnerType := lOwnerType;
          AddCandidate(lCandidate);
        end;
      end;
    end;
    if (lList.Count = 0) and FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory,
      lOwnerType, lSymbols) then
    begin
      for lSymbol in lSymbols do
      begin
        if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and
          (lSymbol.fRelatedTypeName <> '') then
        begin
          lRelatedTypeName := DirectTypeName(lSymbol.fRelatedTypeName);
          if (lRelatedTypeName <> '') and (not SameText(lRelatedTypeName, lOwnerType)) then
          begin
            Result := FindMemberCandidates(aInventory, lRelatedTypeName, aName);
            if GResolverMemberCandidateCache <> nil then
              GResolverMemberCandidateCache.Add(lKey, Result);
            Exit;
          end;
        end;
      end;
    end;
    Result := lList.ToArray;
    if GResolverMemberCandidateCache <> nil then
      GResolverMemberCandidateCache.Add(lKey, Result);
  finally
    lCandidateKeys.Free;
    lList.Free;
  end;
end;

class function TRemoveWithIdentifierResolver.FindDefaultPropertyCandidate(
  const aInventory: TRemoveWithFactSet; const aOwnerType: string): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := FindDefaultPropertySymbol(aInventory, aOwnerType, lSymbol);
end;

class function TRemoveWithIdentifierResolver.FindDefaultPropertySymbol(
  const aInventory: TRemoveWithFactSet; const aOwnerType: string;
  out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lKey: string;
  lOwnerType: string;
begin
  aSymbol := Default(TRemoveWithSymbolInfo);
  lOwnerType := DirectTypeName(aOwnerType);
  lKey := ResolverCacheKey('default-property', lOwnerType);
  if (GResolverBoolCache <> nil) and GResolverBoolCache.TryGetValue(lKey, Result) and (not Result) then
    Exit(False);

  Result := FindRemoveWithFactSetDefaultProperty(aInventory, lOwnerType, aSymbol);
  if GResolverBoolCache <> nil then
    GResolverBoolCache.AddOrSetValue(lKey, Result);
end;

procedure EnsureResolverParentRoutineIndex(const aInventory: TRemoveWithFactSet);
var
  lCurrentRoutine: TRemoveWithSymbolInfo;
  lParentLine: Integer;
  lParentRoutineName: string;
  lRoutine: TRemoveWithSymbolInfo;
  lRoutines: TList<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if GResolverParentRoutineByName <> nil then
    Exit;

  GResolverParentRoutineByName := TDictionary<string, string>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  lRoutines := TList<TRemoveWithSymbolInfo>.Create;
  try
    for lSymbol in aInventory.fSymbols do
      if (lSymbol.fKind = TRemoveWithSymbolKind.rwskRoutine) and (lSymbol.fEndLine > 0) then
        lRoutines.Add(lSymbol);

    for lCurrentRoutine in lRoutines do
    begin
      lParentLine := 0;
      lParentRoutineName := '';
      for lRoutine in lRoutines do
      begin
        if SameText(lRoutine.fName, lCurrentRoutine.fName) then
          Continue;
        if (lRoutine.fLine >= lCurrentRoutine.fLine) or
          (lRoutine.fEndLine < lCurrentRoutine.fEndLine) then
          Continue;
        if lRoutine.fLine > lParentLine then
        begin
          lParentLine := lRoutine.fLine;
          lParentRoutineName := lRoutine.fName;
        end;
      end;
      if lParentRoutineName <> '' then
        GResolverParentRoutineByName.AddOrSetValue(lCurrentRoutine.fName,
          lParentRoutineName);
    end;
  finally
    lRoutines.Free;
  end;
end;

class function TRemoveWithIdentifierResolver.FindLexicalParentRoutineName(
  const aInventory: TRemoveWithFactSet; const aRoutineName: string;
  out aParentRoutineName: string): Boolean;
begin
  aParentRoutineName := '';
  if aRoutineName = '' then
    Exit(False);

  EnsureResolverParentRoutineIndex(aInventory);
  Result := GResolverParentRoutineByName.TryGetValue(aRoutineName,
    aParentRoutineName);
end;

class function TRemoveWithIdentifierResolver.FindScopeSymbol(const aInventory: TRemoveWithFactSet;
  const aRoutineName, aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
const
  cKinds: array [0..5] of TRemoveWithSymbolKind = (TRemoveWithSymbolKind.rwskLocalVariable,
    TRemoveWithSymbolKind.rwskParameter, TRemoveWithSymbolKind.rwskCurrentClassMember,
    TRemoveWithSymbolKind.rwskUnitGlobal, TRemoveWithSymbolKind.rwskConstant, TRemoveWithSymbolKind.rwskRoutine);
var
  lKey: string;
  lKind: TRemoveWithSymbolKind;
  lLookup: TRemoveWithSymbolLookup;
  lParentChecked: Boolean;
  lParentRoutineName: string;
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
  if FindRemoveWithFactSetRoutineSymbol(aInventory, aRoutineName, aName, aSymbol) then
  begin
    if GResolverScopeSymbolCache <> nil then
    begin
      lLookup.fFound := True;
      lLookup.fSymbol := aSymbol;
      GResolverScopeSymbolCache.Add(lKey, lLookup);
    end;
    Exit(True);
  end;
  if not FindRemoveWithFactSetSymbolsByName(aInventory, aName, lSymbols) then
  begin
    if GResolverScopeSymbolCache <> nil then
    begin
      lLookup := Default(TRemoveWithSymbolLookup);
      GResolverScopeSymbolCache.Add(lKey, lLookup);
    end;
    Exit(False);
  end;
  lParentChecked := False;
  for lKind in cKinds do
  begin
    if (not lParentChecked) and (lKind = TRemoveWithSymbolKind.rwskUnitGlobal) then
    begin
      lParentChecked := True;
      if FindLexicalParentRoutineName(aInventory, aRoutineName, lParentRoutineName) and
        FindScopeSymbol(aInventory, lParentRoutineName, aName, aSymbol) then
      begin
        if GResolverScopeSymbolCache <> nil then
        begin
          lLookup.fFound := True;
          lLookup.fSymbol := aSymbol;
          GResolverScopeSymbolCache.Add(lKey, lLookup);
        end;
        Exit(True);
      end;
    end;

    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind <> lKind then
        Continue;
      if lKind in [TRemoveWithSymbolKind.rwskLocalVariable, TRemoveWithSymbolKind.rwskParameter,
        TRemoveWithSymbolKind.rwskCurrentClassMember] then
      begin
        if not SameText(lSymbol.fRoutineName, aRoutineName) then
          Continue;
      end else if lKind = TRemoveWithSymbolKind.rwskConstant then
      begin
        if (lSymbol.fRoutineName <> '') and not SameText(lSymbol.fRoutineName, aRoutineName) then
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

class function TRemoveWithIdentifierResolver.RoutineSymbolContainsLine(const aRoutine: TRemoveWithSymbolInfo;
  const aFilePath: string; const aLine: Integer): Boolean;
begin
  Result := (aRoutine.fKind = TRemoveWithSymbolKind.rwskRoutine) and
    ((aRoutine.fFilePath = '') or SameText(TPath.GetFullPath(aRoutine.fFilePath), TPath.GetFullPath(aFilePath))) and
    (aRoutine.fLine <= aLine) and ((aRoutine.fEndLine = 0) or (aLine <= aRoutine.fEndLine));
end;

class function TRemoveWithIdentifierResolver.SymbolFileMatches(const aSymbol: TRemoveWithSymbolInfo;
  const aFilePath: string): Boolean;
begin
  Result := (aSymbol.fFilePath <> '') and (aFilePath <> '') and
    SameText(TPath.GetFullPath(aSymbol.fFilePath), TPath.GetFullPath(aFilePath));
end;

class function TRemoveWithIdentifierResolver.FindScopeSymbolAtLocation(
  const aInventory: TRemoveWithFactSet; const aFilePath: string; const aLine: Integer;
  const aRoutineName, aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
const
  cLocalKinds: array [0..3] of TRemoveWithSymbolKind = (TRemoveWithSymbolKind.rwskLocalVariable,
    TRemoveWithSymbolKind.rwskParameter, TRemoveWithSymbolKind.rwskCurrentClassMember,
    TRemoveWithSymbolKind.rwskConstant);
var
  lBestRoutineLine: Integer;
  lKind: TRemoveWithSymbolKind;
  lRoutine: TRemoveWithSymbolInfo;
  lRoutineSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if FindScopeSymbol(aInventory, aRoutineName, aName, aSymbol) then
    Exit(True);

  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  if not FindRemoveWithFactSetSymbolsByName(aInventory, aName, lSymbols) then
    Exit(False);

  lBestRoutineLine := 0;
  for lKind in cLocalKinds do
  begin
    for lSymbol in lSymbols do
    begin
      if (lSymbol.fKind <> lKind) or (lSymbol.fRoutineName = '') then
        Continue;
      if not FindRemoveWithFactSetSymbolsByName(aInventory, lSymbol.fRoutineName,
        lRoutineSymbols) then
        Continue;
      for lRoutine in lRoutineSymbols do
      begin
        if RoutineSymbolContainsLine(lRoutine, aFilePath, aLine) and (lRoutine.fLine >= lBestRoutineLine) then
        begin
          lBestRoutineLine := lRoutine.fLine;
          aSymbol := lSymbol;
          Result := True;
        end;
      end;
    end;
    if Result then
      Exit(True);
  end;

  for lSymbol in lSymbols do
  begin
    if not (lSymbol.fKind in [TRemoveWithSymbolKind.rwskUnitGlobal, TRemoveWithSymbolKind.rwskConstant,
      TRemoveWithSymbolKind.rwskRoutine]) then
      Continue;
    if (lSymbol.fRoutineName <> '') or not SymbolFileMatches(lSymbol, aFilePath) then
      Continue;
    aSymbol := lSymbol;
    Exit(True);
  end;
end;

class function TRemoveWithIdentifierResolver.FindUnitNameSymbol(const aInventory: TRemoveWithFactSet;
  const aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lLookup: TRemoveWithSymbolLookup;
  lSymbols: TArray<TRemoveWithSymbolInfo>;

  function TryUseUnitSymbols(const aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
  var
    lCandidate: TRemoveWithSymbolInfo;
  begin
    Result := False;
    for lCandidate in aSymbols do
    begin
      if lCandidate.fKind = TRemoveWithSymbolKind.rwskUnitName then
      begin
        aSymbol := lCandidate;
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
begin
  if (GResolverUnitNameCache <> nil) and GResolverUnitNameCache.TryGetValue(aName, lLookup) then
  begin
    aSymbol := lLookup.fSymbol;
    Exit(lLookup.fFound);
  end;

  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  if FindRemoveWithFactSetUnitOrGlobal(aInventory, aName, lSymbols) and
    TryUseUnitSymbols(lSymbols) then
    Exit(True);
  if FindRemoveWithFactSetUnitOrGlobalPrefix(aInventory, aName, lSymbols) and
    TryUseUnitSymbols(lSymbols) then
    Exit(True);
  if GResolverUnitNameCache <> nil then
  begin
    lLookup := Default(TRemoveWithSymbolLookup);
    GResolverUnitNameCache.Add(aName, lLookup);
  end;
end;

class function TRemoveWithIdentifierResolver.FindExternalUnitSymbol(const aInventory: TRemoveWithFactSet;
  const aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lLookup: TRemoveWithSymbolLookup;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;

  function TryUseExternalUnitSymbols(const aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
  var
    lCandidate: TRemoveWithSymbolInfo;
  begin
    Result := False;
    for lCandidate in aSymbols do
    begin
      if (lCandidate.fKind = TRemoveWithSymbolKind.rwskExternal) and
        (lCandidate.fTypeName = '') then
      begin
        aSymbol := lCandidate;
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
begin
  if (GResolverExternalUnitCache <> nil) and GResolverExternalUnitCache.TryGetValue(aName, lLookup) then
  begin
    aSymbol := lLookup.fSymbol;
    Exit(lLookup.fFound);
  end;

  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  if FindRemoveWithFactSetUnitOrGlobal(aInventory, aName, lSymbols) and
    TryUseExternalUnitSymbols(lSymbols) then
    Exit(True);
  if FindRemoveWithFactSetUnitOrGlobalPrefix(aInventory, aName, lSymbols) and
    TryUseExternalUnitSymbols(lSymbols) then
    Exit(True);
  if FindRemoveWithFactSetSymbolsByName(aInventory, aName, lSymbols) then
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

class function TRemoveWithIdentifierResolver.FindTypeNameSymbol(const aInventory: TRemoveWithFactSet;
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
  if IsDelphiIntrinsicTypeName(aName) then
  begin
    aSymbol.fName := aName;
    aSymbol.fTypeName := aName;
    aSymbol.fKind := TRemoveWithSymbolKind.rwskTypeMember;
    if GResolverTypeNameCache <> nil then
    begin
      lLookup.fFound := True;
      lLookup.fSymbol := aSymbol;
      GResolverTypeNameCache.Add(aName, lLookup);
    end;
    Exit(True);
  end;

  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, aName, lSymbols) then
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

class function TRemoveWithIdentifierResolver.HasSourceType(const aInventory: TRemoveWithFactSet;
  const aTypeName: string): Boolean;
var
  lKey: string;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeName: string;
begin
  lTypeName := CanonicalSourceTypeName(aInventory, aTypeName);
  if lTypeName = '' then
    Exit(False);
  lKey := ResolverCacheKey('source-type', lTypeName);
  if (GResolverBoolCache <> nil) and GResolverBoolCache.TryGetValue(lKey, Result) then
    Exit;

  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lTypeName, lSymbols) then
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

class function TRemoveWithIdentifierResolver.IsExternalType(const aInventory: TRemoveWithFactSet;
  const aTypeName: string): Boolean;
var
  lKey: string;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeName: string;
begin
  lTypeName := CanonicalSourceTypeName(aInventory, aTypeName);
  lKey := ResolverCacheKey('external-type', lTypeName);
  if (GResolverBoolCache <> nil) and GResolverBoolCache.TryGetValue(lKey, Result) then
    Exit;

  if FindRemoveWithFactSetSymbolsByName(aInventory, lTypeName, lSymbols) then
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

class function TRemoveWithIdentifierResolver.HasExternalAncestor(const aInventory: TRemoveWithFactSet;
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
    if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lCurrentType, lSymbols) then
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

class function TRemoveWithIdentifierResolver.PointerTargetType(const aInventory: TRemoveWithFactSet;
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
  Result := RemoveWithFactSetPointerTargetType(aInventory, lTypeName);
  if Result <> '' then
    Exit;
  if StartsText('P', lTypeName) and (Length(lTypeName) > 1) and
    HasSourceType(aInventory, Copy(lTypeName, 2, MaxInt)) then
    Exit(Copy(lTypeName, 2, MaxInt));
  Result := '';
end;

class function TRemoveWithIdentifierResolver.FindAncestorMember(const aInventory: TRemoveWithFactSet;
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
    if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lCurrentType, lSymbols) then
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

class function TRemoveWithIdentifierResolver.IsHelperType(const aInventory: TRemoveWithFactSet;
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

  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lTypeName, lSymbols) then
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
  const aInventory: TRemoveWithFactSet; const aReceiverType: string;
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
    if (aCandidate.fKind = TRemoveWithSymbolKind.rwskMethod) and
      (aCandidate.fIsOverride or CandidateDeclaresOverride(aCandidate)) then
      Exit('overridden');
    Exit('hidden');
  end;

  Result := 'direct';
end;

class function TRemoveWithIdentifierResolver.CandidateDeclaresOverride(
  const aCandidate: TRemoveWithSymbolInfo): Boolean;
var
  lLines: TArray<string>;
begin
  Result := False;
  if (aCandidate.fFilePath = '') or (aCandidate.fLine <= 0) or (not TFile.Exists(aCandidate.fFilePath)) then
    Exit;

  lLines := TFile.ReadAllLines(aCandidate.fFilePath, TEncoding.UTF8);
  if aCandidate.fLine > Length(lLines) then
    Exit;

  Result := ContainsText(lLines[aCandidate.fLine - 1], 'override');
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

class function TRemoveWithIdentifierResolver.IsAssignmentTargetUse(const aSource: TRemoveWithSourceBuffer;
  const aUse: TRemoveWithIdentifierUse): Boolean;
var
  lOffset: Integer;
begin
  lOffset := aUse.fEndOffset + 1;
  while (lOffset <= Length(aSource.fText)) and CharInSet(aSource.fText[lOffset], [#9, #10, #13, ' ']) do
    Inc(lOffset);
  Result := (lOffset < Length(aSource.fText)) and (aSource.fText[lOffset] = ':') and
    (aSource.fText[lOffset + 1] = '=');
end;

class function TRemoveWithIdentifierResolver.FindSemanticExternalRoutineSymbol(
  const aInventory: TRemoveWithFactSet; const aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lSourceKind: string;
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
begin
  aSymbol := Default(TRemoveWithSymbolInfo);
  if not FindRemoveWithFactSetSymbolsByName(aInventory, aName, lSymbols) then
    Exit(False);
  Result := True;

  for lSymbol in lSymbols do
  begin
    lSourceKind := lSymbol.fSourceOwnerType;
    if lSourceKind = '' then
      lSourceKind := lSymbol.fUnitName;
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskRoutine) and
      (SameText(lSourceKind, 'compiler-intrinsic') or SameText(lSourceKind, 'rtl-source')) then
    begin
      aSymbol := lSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TRemoveWithIdentifierResolver.IsDelphiIntrinsicRoutineUse(
  const aInventory: TRemoveWithFactSet; const aSource: TRemoveWithSourceBuffer;
  const aUse: TRemoveWithIdentifierUse): Boolean;
var
  lNextChar: Char;
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  if not FindSemanticExternalRoutineSymbol(aInventory, aUse.fName, lSymbol) then
    Exit;

  lNextChar := NextNonWhitespaceChar(aSource.fText, aUse.fEndOffset + 1);
  Result := CharInSet(lNextChar, ['(', '<']) or SameText(aUse.fName, 'IOResult');
end;

class function TRemoveWithIdentifierResolver.IsDelphiIntrinsicTypeName(const aName: string): Boolean;
begin
  Result := MatchText(aName, ['AnsiChar', 'AnsiString', 'Array', 'Boolean', 'Byte', 'Cardinal', 'Char', 'Currency',
    'Date', 'DateTime', 'Double', 'Extended', 'Int8', 'Int16', 'Int32', 'Int64', 'Integer', 'LongInt', 'LongWord',
    'NativeInt', 'NativeUInt', 'PAnsiChar', 'PByte', 'PChar', 'Pointer', 'PWideChar', 'Real', 'ShortInt', 'ShortString',
    'Single', 'SmallInt', 'String', 'UInt8', 'UInt16', 'UInt32', 'UInt64', 'Variant', 'WideChar', 'WideString',
    'Word']);
end;

class function TRemoveWithIdentifierResolver.IsDelphiIntrinsicUnitName(const aName: string): Boolean;
begin
  Result := SameText(aName, 'System');
end;

class function TRemoveWithIdentifierResolver.FindSymbolMapCompilerIntrinsic(
  const aBridge: TRemoveWithSymbolMapBridge; const aName, aKind: string;
  out aLookup: TRemoveWithSymbolMapLookup): Boolean;
var
  lError: string;
begin
  aLookup := Default(TRemoveWithSymbolMapLookup);
  if not aBridge.fPrepared then
    Exit(False);
  if not FindRemoveWithSymbolMapDefinition(aBridge, aName, '', aLookup, lError) then
    Exit(False);

  Result := aLookup.fFound and SameText(aLookup.fSourceKind, 'compiler-intrinsic') and
    SameText(aLookup.fConfidence, 'exact') and SameText(aLookup.fKind, aKind);
end;

class function TRemoveWithIdentifierResolver.FindSymbolMapExternalRoutine(
  const aBridge: TRemoveWithSymbolMapBridge; const aName: string;
  out aLookup: TRemoveWithSymbolMapLookup): Boolean;
var
  lError: string;
begin
  aLookup := Default(TRemoveWithSymbolMapLookup);
  if not aBridge.fPrepared then
    Exit(False);
  if not FindRemoveWithSymbolMapDefinition(aBridge, aName, '', aLookup, lError) then
    Exit(False);

  Result := aLookup.fFound and SameText(aLookup.fKind, 'routine') and
    SameText(aLookup.fConfidence, 'exact') and
    (SameText(aLookup.fSourceKind, 'compiler-intrinsic') or SameText(aLookup.fSourceKind, 'rtl-source'));
end;

class function TRemoveWithIdentifierResolver.ShouldLookupSymbolMapRoutineIntrinsic(
  const aSource: TRemoveWithSourceBuffer; const aUse: TRemoveWithIdentifierUse): Boolean;
begin
  Result := IsCallUse(aSource, aUse) or SameText(aUse.fName, 'IOResult');
end;

class function TRemoveWithIdentifierResolver.IsVisibleRtlRoutineUse(
  const aInventory: TRemoveWithFactSet; const aSource: TRemoveWithSourceBuffer;
  const aUse: TRemoveWithIdentifierUse): Boolean;
begin
  Result := False;
  if not IsCallUse(aSource, aUse) then
    Exit;

  Result := IsDelphiIntrinsicRoutineUse(aInventory, aSource, aUse);
end;

class function TRemoveWithIdentifierResolver.IsExternalRoutineCall(const aInventory: TRemoveWithFactSet;
  const aSource: TRemoveWithSourceBuffer; const aUse: TRemoveWithIdentifierUse): Boolean;
begin
  Result := IsDelphiIntrinsicRoutineUse(aInventory, aSource, aUse);
end;

class function TRemoveWithIdentifierResolver.ReceiversAllowUnresolvedFallback(
  const aInventory: TRemoveWithFactSet; const aReceivers: TArray<TRemoveWithReceiverScope>): Boolean;
var
  lReceiver: TRemoveWithReceiverScope;
begin
  Result := Length(aReceivers) > 0;
  if not Result then
    Exit;

  for lReceiver in aReceivers do
  begin
    if (lReceiver.fStatus <> TRemoveWithSelectorTypeStatus.rwstsResolved) or (lReceiver.fTypeName = '') or
      (not HasSourceType(aInventory, lReceiver.fTypeName)) then
      Exit(False);
  end;
end;

class function TRemoveWithIdentifierResolver.IsQualifiedUse(const aSource: TRemoveWithSourceBuffer;
  const aUse: TRemoveWithIdentifierUse): Boolean;
begin
  Result := NextNonWhitespaceChar(aSource.fText, aUse.fEndOffset + 1) = '.';
end;

class function TRemoveWithIdentifierResolver.SemanticBindingMatchesStatement(
  const aBinding: TDelphiSemanticWithBinding; const aStatement: TRemoveWithStatementInfo): Boolean;
var
  lBindingSelector: string;
  lStatementSelector: string;
begin
  lBindingSelector := NormalizedSemanticSelectorText(aBinding.SelectorText);
  lStatementSelector := NormalizedSemanticSelectorText(aStatement.fSelectorText);
  Result := SameText(TPath.GetFullPath(aBinding.FileName), TPath.GetFullPath(aStatement.fFilePath)) and
    SameText(lBindingSelector, lStatementSelector) and
    (aBinding.Line = aStatement.fLine) and (aBinding.Column = aStatement.fColumn);
end;

class function TRemoveWithIdentifierResolver.SemanticBindingMatchesStatement(
  const aEntry: TRemoveWithSemanticWithBinding; const aStatement: TRemoveWithStatementInfo): Boolean;
begin
  Result := SameText(TPath.GetFullPath(aEntry.fFilePath), TPath.GetFullPath(aStatement.fFilePath)) and
    SemanticBindingMatchesStatement(aEntry.fBinding, aStatement);
end;

class function TRemoveWithIdentifierResolver.NormalizedSemanticSelectorText(const aSelectorText: string): string;
begin
  Result := StringReplace(Trim(aSelectorText), ' ', '', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '', [rfReplaceAll]);
end;

class function TRemoveWithIdentifierResolver.TryFindSemanticBindingForStatement(
  const aInventory: TRemoveWithFactSet; const aStatement: TRemoveWithStatementInfo;
  out aBinding: TDelphiSemanticWithBinding): Boolean;
var
  lEntries: TRemoveWithSemanticBindingEntries;
  lEntry: TRemoveWithSemanticWithBinding;
begin
  aBinding := Default(TDelphiSemanticWithBinding);
  if Assigned(GResolverSemanticBindingsByStatementRange) and
    GResolverSemanticBindingsByStatementRange.TryGetValue(
    SemanticBindingRangeKey(aStatement.fFilePath, aStatement.fLine, aStatement.fColumn),
    lEntries) then
  begin
    for lEntry in lEntries do
    begin
      if SemanticBindingMatchesStatement(lEntry, aStatement) then
      begin
        aBinding := lEntry.fBinding;
        Exit(True);
      end;
    end;
    Exit(False);
  end;
  if Assigned(GResolverSemanticBindingsByStatementRange) then
    Exit(False);
  for lEntry in aInventory.fDelphiSemanticWithBindingEntries do
  begin
    if SemanticBindingMatchesStatement(lEntry, aStatement) then
    begin
      aBinding := lEntry.fBinding;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TRemoveWithIdentifierResolver.SemanticBindingBlocksStatement(
  const aInventory: TRemoveWithFactSet; const aStatement: TRemoveWithStatementInfo): Boolean;
var
  lBinding: TDelphiSemanticWithBinding;
begin
  Result := TryFindSemanticBindingForStatement(aInventory, aStatement, lBinding) and
    lBinding.HasScopedDeclaration;
end;

class function TRemoveWithIdentifierResolver.TryApplySemanticSelectorInfo(
  const aInventory: TRemoveWithFactSet; const aBinding: TDelphiSemanticWithBinding; const aSelectorText: string;
  var aInfo: TRemoveWithSelectorTypeInfo): Boolean;
var
  lSelector: TDelphiSemanticWithSelectorBinding;
  lSelectorText: string;
begin
  Result := False;
  lSelectorText := NormalizedSemanticSelectorText(aSelectorText);
  for lSelector in aBinding.Selectors do
  begin
    if SameText(NormalizedSemanticSelectorText(lSelector.SelectorText), lSelectorText) and
      SameText(lSelector.Status, 'resolved') and (Trim(lSelector.TypeName) <> '') and
      HasSourceType(aInventory, lSelector.TypeName) and (not IsExternalType(aInventory, lSelector.TypeName)) then
    begin
      aInfo.fSelectorText := aSelectorText;
      aInfo.fTypeName := Trim(lSelector.TypeName);
      aInfo.fReason := '';
      aInfo.fAddressable := True;
      aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsResolved;
      Exit(True);
    end;
  end;
end;

class function TRemoveWithIdentifierResolver.TryFindSemanticReferenceForUse(
  const aBinding: TDelphiSemanticWithBinding; const aUse: TRemoveWithIdentifierUse;
  out aReference: TDelphiSemanticBoundReference): Boolean;
var
  lReference: TDelphiSemanticBoundReference;
begin
  aReference := Default(TDelphiSemanticBoundReference);
  for lReference in aBinding.References do
  begin
    if SameText(lReference.Name, aUse.fName) and (lReference.Line = aUse.fLine) and
      (lReference.Column = aUse.fColumn) then
    begin
      aReference := lReference;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TRemoveWithIdentifierResolver.SemanticKindToRemoveWithKind(
  const aKind: string): TRemoveWithSymbolKind;
begin
  if SameText(aKind, 'field') then
    Result := TRemoveWithSymbolKind.rwskField
  else if SameText(aKind, 'property') then
    Result := TRemoveWithSymbolKind.rwskProperty
  else if SameText(aKind, 'method') then
    Result := TRemoveWithSymbolKind.rwskMethod
  else if SameText(aKind, 'constant') then
    Result := TRemoveWithSymbolKind.rwskConstant
  else if SameText(aKind, 'class-var') then
    Result := TRemoveWithSymbolKind.rwskClassVar
  else
    Result := TRemoveWithSymbolKind.rwskField;
end;

class function TRemoveWithIdentifierResolver.SemanticTypeNamesMatch(
  const aInventory: TRemoveWithFactSet; const aLeft, aRight: string): Boolean;
var
  lLeft: string;
  lRight: string;
begin
  lLeft := CanonicalSourceTypeName(aInventory, aLeft);
  lRight := CanonicalSourceTypeName(aInventory, aRight);
  Result := SameText(lLeft, lRight) or SameText(DirectTypeName(lLeft), DirectTypeName(lRight));
end;

class function TRemoveWithIdentifierResolver.ResolveSelectorFromReceivers(
  const aInventory: TRemoveWithFactSet; const aReceivers: TArray<TRemoveWithReceiverScope>;
  const aSelectorText: string; out aInfo: TRemoveWithSelectorTypeInfo): Boolean;
var
  lCandidate: TRemoveWithSymbolInfo;
  lCandidates: TArray<TRemoveWithSymbolInfo>;
  lCurrentType: string;
  lDefaultProperty: TRemoveWithSymbolInfo;
  lIndexedTypeName: string;
  lName: string;
  lPaths: TArray<string>;
  i: Integer;
  j: Integer;

  function TrySelectSelectorCandidate(
    const aCandidates: TArray<TRemoveWithSymbolInfo>;
    out aCandidate: TRemoveWithSymbolInfo): Boolean;
  var
    lExpectedKind: TRemoveWithSymbolKind;
    lExpectedTypeName: string;
    lSymbol: TRemoveWithSymbolInfo;
  begin
    aCandidate := Default(TRemoveWithSymbolInfo);
    if Length(aCandidates) = 0 then
      Exit(False);

    aCandidate := aCandidates[0];
    lExpectedKind := aCandidate.fKind;
    lExpectedTypeName := CanonicalSourceTypeName(aInventory, aCandidate.fTypeName);
    for lSymbol in aCandidates do
    begin
      if lSymbol.fKind <> lExpectedKind then
        Exit(False);
      if not SameText(CanonicalSourceTypeName(aInventory, lSymbol.fTypeName),
        lExpectedTypeName) then
        Exit(False);
    end;
    Result := True;
  end;
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
    if not TrySelectSelectorCandidate(lCandidates, lCandidate) then
      Continue;
    if lCandidate.fKind = TRemoveWithSymbolKind.rwskProperty then
    begin
      aInfo.fReason := 'property-selector';
      aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
      aInfo.fAddressable := False;
      Exit(True);
    end;
    if lCandidate.fKind = TRemoveWithSymbolKind.rwskMethod then
    begin
      aInfo.fReason := 'call-selector';
      aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
      aInfo.fAddressable := False;
      Exit(True);
    end;

    lCurrentType := lCandidate.fTypeName;
    if SelectorSegmentDerefBeforeIndex(lPaths[0]) then
      lCurrentType := PointerTargetType(aInventory, lCurrentType);
    if SelectorSegmentIndexed(lPaths[0]) then
    begin
      lIndexedTypeName := ArrayElementTypeName(aInventory, lCurrentType);
      if lIndexedTypeName <> '' then
        lCurrentType := lIndexedTypeName
      else if FindDefaultPropertySymbol(aInventory, lCurrentType, lDefaultProperty) then
      begin
        if SelectorSegmentDerefAfterIndex(lPaths[0]) then
          lCurrentType := lDefaultProperty.fTypeName
        else
        begin
          aInfo.fReason := 'property-selector';
          aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
          aInfo.fAddressable := False;
          Exit(True);
        end;
      end else
        lCurrentType := '';
    end;
    if SelectorSegmentDerefAfterIndex(lPaths[0]) then
      lCurrentType := PointerTargetType(aInventory, lCurrentType);

    for j := 1 to High(lPaths) do
    begin
      lName := SelectorSegmentName(lPaths[j]);
      lCandidates := FindMemberCandidates(aInventory, lCurrentType, lName);
      if not TrySelectSelectorCandidate(lCandidates, lCandidate) then
      begin
        lCurrentType := '';
        Break;
      end;
      if lCandidate.fKind = TRemoveWithSymbolKind.rwskProperty then
      begin
        aInfo.fReason := 'property-selector';
        aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
        aInfo.fAddressable := False;
        Exit(True);
      end;
      if lCandidate.fKind = TRemoveWithSymbolKind.rwskMethod then
      begin
        aInfo.fReason := 'call-selector';
        aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
        aInfo.fAddressable := False;
        Exit(True);
      end;
      lCurrentType := lCandidate.fTypeName;
      if SelectorSegmentDerefBeforeIndex(lPaths[j]) then
        lCurrentType := PointerTargetType(aInventory, lCurrentType);
      if SelectorSegmentIndexed(lPaths[j]) then
      begin
        lIndexedTypeName := ArrayElementTypeName(aInventory, lCurrentType);
        if lIndexedTypeName <> '' then
          lCurrentType := lIndexedTypeName
        else if FindDefaultPropertySymbol(aInventory, lCurrentType, lDefaultProperty) then
        begin
          if SelectorSegmentDerefAfterIndex(lPaths[j]) then
            lCurrentType := lDefaultProperty.fTypeName
          else
          begin
            aInfo.fReason := 'property-selector';
            aInfo.fStatus := TRemoveWithSelectorTypeStatus.rwstsUnsupported;
            aInfo.fAddressable := False;
            Exit(True);
          end;
        end else
          lCurrentType := '';
      end;
      if SelectorSegmentDerefAfterIndex(lPaths[j]) then
        lCurrentType := PointerTargetType(aInventory, lCurrentType);
    end;

    if lCurrentType <> '' then
    begin
      aInfo.fTypeName := CanonicalSourceTypeName(aInventory, lCurrentType);
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
  const aInventory: TRemoveWithFactSet; const aRoutineName, aSelectorText: string): Boolean;
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
  end;
end;

class procedure TRemoveWithIdentifierResolver.NormalizeSelectorInfo(const aInventory: TRemoveWithFactSet;
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

class function TRemoveWithIdentifierResolver.ShouldEnrichWithSymbolMap(
  const aClassification: TRemoveWithIdentifierClassification): Boolean;
begin
  Result := False;
  if aClassification.fIdentifier = '' then
    Exit;
  if (aClassification.fReceiverType <> '') and
    (aClassification.fStatus = TRemoveWithIdentifierStatus.rwisResolved) then
    Exit(True);

  case aClassification.fMemberKind of
    TRemoveWithSymbolKind.rwskUnitGlobal, TRemoveWithSymbolKind.rwskTypeMember,
    TRemoveWithSymbolKind.rwskConstant, TRemoveWithSymbolKind.rwskRoutine, TRemoveWithSymbolKind.rwskUnitName,
    TRemoveWithSymbolKind.rwskExternal:
      Exit(True);
  end;

  Result := MatchText(aClassification.fResolutionKind, ['external-routine-call', 'type-name', 'qualified-unit',
    'external-unit', 'type-qualifier']);
end;

class procedure TRemoveWithIdentifierResolver.EnrichWithSymbolMap(const aBridge: TRemoveWithSymbolMapBridge;
  var aClassification: TRemoveWithIdentifierClassification);
var
  lError: string;
  lLookup: TRemoveWithSymbolMapLookup;
  lOwnerName: string;
begin
  if (not aBridge.fPrepared) or (not ShouldEnrichWithSymbolMap(aClassification)) then
    Exit;

  lOwnerName := DirectTypeName(aClassification.fReceiverType);
  if not FindRemoveWithSymbolMapDefinition(aBridge, aClassification.fIdentifier, lOwnerName, lLookup, lError) then
  begin
    aClassification.fSymbolMapReason := 'lookup-error';
    Exit;
  end;
  if (not lLookup.fFound) and (lOwnerName <> '') and
    FindRemoveWithSymbolMapDefinition(aBridge, aClassification.fIdentifier, '', lLookup, lError) and
    lLookup.fFound then
    lOwnerName := '';

  aClassification.fSymbolMapFound := lLookup.fFound;
  if lLookup.fFound then
  begin
    aClassification.fSymbolMapKind := lLookup.fKind;
    aClassification.fSymbolMapSourceKind := lLookup.fSourceKind;
    aClassification.fSymbolMapConfidence := lLookup.fConfidence;
    aClassification.fSymbolMapOwnerName := lLookup.fOwnerName;
    aClassification.fSymbolMapReason := '';
  end else begin
    aClassification.fSymbolMapReason := 'miss';
    if lOwnerName <> '' then
      aClassification.fSymbolMapOwnerName := lOwnerName;
  end;
end;

class procedure TRemoveWithIdentifierResolver.EnrichWithSemanticFacts(const aInventory: TRemoveWithFactSet;
  var aClassification: TRemoveWithIdentifierClassification);
var
  lSourceKind: string;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if aClassification.fSymbolMapFound or (not ShouldEnrichWithSymbolMap(aClassification)) then
  begin
    if (aClassification.fStatus = TRemoveWithIdentifierStatus.rwisUnresolved) and
      SameText(aClassification.fReason, 'symbol-not-found') then
      aClassification.fSymbolMapReason := 'miss';
    Exit;
  end;

  if SameText(aClassification.fResolutionKind, 'external-routine-call') and
    FindSemanticExternalRoutineSymbol(aInventory, aClassification.fIdentifier, lSymbol) then
  begin
    lSourceKind := lSymbol.fSourceOwnerType;
    if lSourceKind = '' then
      lSourceKind := lSymbol.fUnitName;
    aClassification.fSymbolMapFound := True;
    aClassification.fSymbolMapKind := 'routine';
    aClassification.fSymbolMapSourceKind := lSourceKind;
    aClassification.fSymbolMapConfidence := 'exact';
    aClassification.fSymbolMapReason := '';
    Exit;
  end;

  if aClassification.fStatus = TRemoveWithIdentifierStatus.rwisResolved then
  begin
    aClassification.fSymbolMapFound := True;
    aClassification.fSymbolMapKind := RemoveWithSymbolKindToText(aClassification.fMemberKind);
    aClassification.fSymbolMapSourceKind := 'project';
    aClassification.fSymbolMapConfidence := 'exact';
    aClassification.fSymbolMapOwnerName := DirectTypeName(aClassification.fReceiverType);
    aClassification.fSymbolMapReason := '';
    Exit;
  end;

  if MatchText(aClassification.fResolutionKind, ['type-name', 'qualified-unit', 'external-unit',
    'type-qualifier']) then
  begin
    aClassification.fSymbolMapFound := True;
    aClassification.fSymbolMapKind := RemoveWithSymbolKindToText(aClassification.fMemberKind);
    if aClassification.fMemberKind = TRemoveWithSymbolKind.rwskExternal then
      aClassification.fSymbolMapSourceKind := 'rtl-source'
    else
      aClassification.fSymbolMapSourceKind := 'project';
    aClassification.fSymbolMapConfidence := 'exact';
    aClassification.fSymbolMapReason := '';
  end;
end;

class procedure TRemoveWithIdentifierResolver.CollectIdentifierUses(const aSource: TRemoveWithSourceBuffer;
  const aBodyOffsets: TRemoveWithOffsetRange; const aSkipRanges: TArray<TRemoveWithOffsetRange>;
  out aUses: TArray<TRemoveWithIdentifierUse>);
var
  lEndOffset: Integer;
  lList: TList<TRemoveWithIdentifierUse>;
  lNextOffset: Integer;
  lPreviousChar: Char;
  lSkipNextIdentifier: Boolean;
  lUse: TRemoveWithIdentifierUse;
  i: Integer;
begin
  lList := TList<TRemoveWithIdentifierUse>.Create;
  try
    lEndOffset := RemoveWithInclusiveEndOffset(aSource, aBodyOffsets.fEndOffset);
    lSkipNextIdentifier := False;
    i := aBodyOffsets.fStartOffset;
    while i <= lEndOffset do
    begin
      if OffsetInRanges(i, aSkipRanges) then
      begin
        Inc(i);
        Continue;
      end;

      if aSource.fText[i] = '''' then
      begin
        Inc(i);
        while i <= lEndOffset do
        begin
          if aSource.fText[i] = '''' then
          begin
            Inc(i);
            if (i <= lEndOffset) and (aSource.fText[i] = '''') then
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
        while (i <= lEndOffset) and (aSource.fText[i] <> '}') do
          Inc(i);
        Inc(i);
        Continue;
      end;

      if (i < lEndOffset) and (aSource.fText[i] = '(') and (aSource.fText[i + 1] = '*') then
      begin
        Inc(i, 2);
        while (i < lEndOffset) and
          ((aSource.fText[i] <> '*') or (aSource.fText[i + 1] <> ')')) do
          Inc(i);
        Inc(i, 2);
        Continue;
      end;

      if (i < lEndOffset) and (aSource.fText[i] = '/') and (aSource.fText[i + 1] = '/') then
      begin
        Inc(i, 2);
        while (i <= lEndOffset) and not CharInSet(aSource.fText[i], [#10, #13]) do
          Inc(i);
        Continue;
      end;

      if aSource.fText[i] = '$' then
      begin
        Inc(i);
        while (i <= lEndOffset) and CharInSet(aSource.fText[i], ['0'..'9', 'A'..'F', 'a'..'f']) do
          Inc(i);
        Continue;
      end;

      if IsControlCharacterLiteralStart(aSource.fText, i, lEndOffset) then
      begin
        Inc(i, 2);
        Continue;
      end;

      if CharInSet(aSource.fText[i], ['A'..'Z', 'a'..'z', '_']) then
      begin
        if (i > 1) and IsIdentifierChar(aSource.fText[i - 1]) then
        begin
          while (i <= lEndOffset) and IsIdentifierChar(aSource.fText[i]) do
            Inc(i);
          Continue;
        end;
        lUse := Default(TRemoveWithIdentifierUse);
        lUse.fStartOffset := i;
        while (i <= lEndOffset) and IsIdentifierChar(aSource.fText[i]) do
          Inc(i);
        lUse.fEndOffset := i - 1;
        lUse.fName := Copy(aSource.fText, lUse.fStartOffset, lUse.fEndOffset - lUse.fStartOffset + 1);
        if SameText(lUse.fName, 'goto') then
        begin
          lSkipNextIdentifier := True;
          Continue;
        end;
        if lSkipNextIdentifier then
        begin
          lSkipNextIdentifier := False;
          Continue;
        end;
        lPreviousChar := PreviousNonWhitespaceChar(aSource.fText, lUse.fStartOffset);
        lNextOffset := lUse.fEndOffset + 1;
        while (lNextOffset <= Length(aSource.fText)) and
          CharInSet(aSource.fText[lNextOffset], [#9, #10, #13, ' ']) do
          Inc(lNextOffset);
        if (lNextOffset <= Length(aSource.fText)) and (aSource.fText[lNextOffset] = ':') and
          ((lNextOffset = Length(aSource.fText)) or (aSource.fText[lNextOffset + 1] <> '=')) and
          (lPreviousChar <> '(') then
          Continue;
        if (not IsKeyword(lUse.fName)) and (lPreviousChar <> '.') then
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

class procedure TRemoveWithIdentifierResolver.BuildReceiverStack(const aInventory: TRemoveWithFactSet;
  const aScanResult: TRemoveWithScanResult; const aStatement: TRemoveWithStatementInfo;
  const aRoutineName, aSelectorRoutineName: string; const aBinding: TDelphiSemanticWithBinding;
  out aReceivers: TArray<TRemoveWithReceiverScope>);
var
  lInfo: TRemoveWithSelectorTypeInfo;
  lList: TList<TRemoveWithReceiverScope>;
  lReceiver: TRemoveWithReceiverScope;
  lSelector: string;
  lSelectors: TArray<string>;
  lStatement: TRemoveWithStatementInfo;
  lStatements: TArray<TRemoveWithStatementInfo>;
begin
  lList := TList<TRemoveWithReceiverScope>.Create;
  try
    if Assigned(GResolverContainingStatementsById) and
      GResolverContainingStatementsById.TryGetValue(aStatement.fId, lStatements) then
    begin
    end else
      lStatements := nil;
    for lStatement in lStatements do
    begin
      lSelectors := SplitSelectorList(lStatement.fSelectorText);
      for lSelector in lSelectors do
      begin
        if (lList.Count > 0) and (Pos('.', lSelector) = 0) and (Pos('[', lSelector) = 0) and
          (Pos('^', lSelector) = 0) and ResolveSelectorFromReceivers(aInventory, lList.ToArray, lSelector,
          lInfo) then
        begin
        end else begin
          if not ResolveRemoveWithSelectorType(aInventory, aRoutineName, lSelector, lInfo) then
            lInfo := Default(TRemoveWithSelectorTypeInfo);
          NormalizeSelectorInfo(aInventory, aRoutineName, lSelector, lInfo);
          if (lInfo.fStatus <> TRemoveWithSelectorTypeStatus.rwstsResolved) and
            ResolveSelectorFromReceivers(aInventory, lList.ToArray, lSelector, lInfo) then
          begin
          end;
          if (lInfo.fStatus = TRemoveWithSelectorTypeStatus.rwstsResolved) and (lInfo.fTypeName = '') and
            TryApplySemanticSelectorInfo(aInventory, aBinding, lSelector, lInfo) then
          begin
          end;
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
      if (lList.Count > 0) and (Pos('.', lSelector) = 0) and (Pos('[', lSelector) = 0) and
        (Pos('^', lSelector) = 0) and ResolveSelectorFromReceivers(aInventory, lList.ToArray, lSelector,
        lInfo) then
      begin
      end else begin
        if not ResolveRemoveWithSelectorType(aInventory, aRoutineName, lSelector, lInfo) then
          lInfo := Default(TRemoveWithSelectorTypeInfo);
        NormalizeSelectorInfo(aInventory, aRoutineName, lSelector, lInfo);
        if (lInfo.fStatus <> TRemoveWithSelectorTypeStatus.rwstsResolved) and
          ResolveSelectorFromReceivers(aInventory, lList.ToArray, lSelector, lInfo) then
        begin
        end;
        if (lInfo.fStatus = TRemoveWithSelectorTypeStatus.rwstsResolved) and (lInfo.fTypeName = '') and
          TryApplySemanticSelectorInfo(aInventory, aBinding, lSelector, lInfo) then
        begin
        end;
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

class function TRemoveWithIdentifierResolver.ClassifyUse(const aInventory: TRemoveWithFactSet;
  const aSource: TRemoveWithSourceBuffer; const aRoutineName: string;
  const aReceivers: TArray<TRemoveWithReceiverScope>; const aBinding: TDelphiSemanticWithBinding;
  const aUse: TRemoveWithIdentifierUse; const aSymbolMapBridge: TRemoveWithSymbolMapBridge;
  out aClassification: TRemoveWithIdentifierClassification): Boolean;
var
  lCandidates: TArray<TRemoveWithSymbolInfo>;
  lHadResolvedReceiver: Boolean;
  lReference: TDelphiSemanticBoundReference;
  lReceiver: TRemoveWithReceiverScope;
  lResolvedReceiverText: string;
  lResolvedReceiverType: string;
  lSourceOwnerType: string;
  lSymbolMapLookup: TRemoveWithSymbolMapLookup;
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
  lHadResolvedReceiver := False;
  lResolvedReceiverText := '';
  lResolvedReceiverType := '';
  Result := True;

  if IsQualifiedUse(aSource, aUse) and
    FindSymbolMapCompilerIntrinsic(aSymbolMapBridge, aUse.fName, 'unit', lSymbolMapLookup) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskExternal;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'qualified-unit';
    aClassification.fReason := 'unit-qualifier';
    Exit(True);
  end;

  if IsQualifiedUse(aSource, aUse) and IsDelphiIntrinsicUnitName(aUse.fName) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskExternal;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'qualified-unit';
    aClassification.fReason := 'unit-qualifier';
    Exit(True);
  end;

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
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'qualified-unit';
    aClassification.fReason := 'unit-qualifier';
    Exit(True);
  end;

  if IsQualifiedUse(aSource, aUse) and FindTypeNameSymbol(aInventory, aUse.fName, lSymbol) then
  begin
    aClassification.fMemberKind := lSymbol.fKind;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'type-qualifier';
    aClassification.fReason := 'type-qualifier';
    Exit(True);
  end;

  if TryFindSemanticReferenceForUse(aBinding, aUse, lReference) and
    SameText(lReference.Classification, 'member') and (lReference.ReceiverTypeName <> '') then
  begin
    for i := High(aReceivers) downto 0 do
    begin
      if (aReceivers[i].fStatus = TRemoveWithSelectorTypeStatus.rwstsResolved) and
        SemanticTypeNamesMatch(aInventory, aReceivers[i].fTypeName, lReference.ReceiverTypeName) then
      begin
        aClassification.fReceiverText := aReceivers[i].fSelectorText;
        aClassification.fReceiverType := lReference.ReceiverTypeName;
        lCandidates := FindMemberCandidates(aInventory, aReceivers[i].fTypeName, aUse.fName);
        if Length(lCandidates) > 0 then
        begin
          aClassification.fMemberKind := lCandidates[0].fKind;
          aClassification.fResolutionKind := ResolutionKindForCandidate(aInventory, aReceivers[i].fTypeName,
            lCandidates[0], lSourceOwnerType);
          aClassification.fSourceOwnerType := lSourceOwnerType;
        end else
        begin
          aClassification.fMemberKind := SemanticKindToRemoveWithKind(lReference.Kind);
          aClassification.fResolutionKind := 'direct';
        end;
        aClassification.fStatus := TRemoveWithIdentifierStatus.rwisResolved;
        aClassification.fReason := '';
        Exit(True);
      end;
    end;
  end;

  if IsGenericTypeNameUse(aSource, aUse) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskTypeMember;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'type-name';
    aClassification.fReason := 'type-name';
    Exit(True);
  end;

  for i := High(aReceivers) downto 0 do
  begin
    if aReceivers[i].fStatus = TRemoveWithSelectorTypeStatus.rwstsResolved then
    begin
      lHadResolvedReceiver := True;
      Break;
    end;
  end;

  if (not lHadResolvedReceiver) and ShouldLookupSymbolMapRoutineIntrinsic(aSource, aUse) and
    FindSymbolMapExternalRoutine(aSymbolMapBridge, aUse.fName, lSymbolMapLookup) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskRoutine;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'external-routine-call';
    aClassification.fReason := 'external-routine-call';
    Exit(True);
  end else if (not lHadResolvedReceiver) and IsVisibleRtlRoutineUse(aInventory, aSource, aUse) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskRoutine;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'external-routine-call';
    aClassification.fReason := 'external-routine-call';
    Exit(True);
  end else if (not lHadResolvedReceiver) and IsExternalRoutineCall(aInventory, aSource, aUse) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskRoutine;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'external-routine-call';
    aClassification.fReason := 'external-routine-call';
    Exit(True);
  end;

  lHadResolvedReceiver := False;

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
      end else if not lHadResolvedReceiver then
      begin
        lHadResolvedReceiver := True;
        lResolvedReceiverText := aReceivers[i].fSelectorText;
        lResolvedReceiverType := aReceivers[i].fTypeName;
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

  if lHadResolvedReceiver and (lResolvedReceiverType <> '') and (not HasSourceType(aInventory, lResolvedReceiverType)) and
    (not IsCallUse(aSource, aUse)) and (not IsAssignmentTargetUse(aSource, aUse)) then
  begin
    aClassification.fReceiverText := lResolvedReceiverText;
    aClassification.fReceiverType := lResolvedReceiverType;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisExternal;
    aClassification.fResolutionKind := 'external-only';
    aClassification.fReason := 'type-source-not-indexed';
    Exit(True);
  end;

  if IsVisibleRtlRoutineUse(aInventory, aSource, aUse) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskRoutine;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'external-routine-call';
    aClassification.fReason := 'external-routine-call';
  end else if IsExternalRoutineCall(aInventory, aSource, aUse) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskRoutine;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'external-routine-call';
    aClassification.fReason := 'external-routine-call';
  end else if FindScopeSymbolAtLocation(aInventory, aSource.fPath, aUse.fLine, aRoutineName, aUse.fName, lSymbol) then
  begin
    aClassification.fMemberKind := lSymbol.fKind;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'unchanged';
    aClassification.fReason := 'routine-scope';
  end else if FindTypeNameSymbol(aInventory, aUse.fName, lSymbol) then
  begin
    aClassification.fMemberKind := lSymbol.fKind;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'type-name';
    aClassification.fReason := 'type-name';
  end else if FindSymbolMapCompilerIntrinsic(aSymbolMapBridge, aUse.fName, 'type', lSymbolMapLookup) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskTypeMember;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'type-name';
    aClassification.fReason := 'type-name';
  end else if ShouldLookupSymbolMapRoutineIntrinsic(aSource, aUse) and
    FindSymbolMapExternalRoutine(aSymbolMapBridge, aUse.fName, lSymbolMapLookup) then
  begin
    aClassification.fMemberKind := TRemoveWithSymbolKind.rwskRoutine;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnchanged;
    aClassification.fResolutionKind := 'external-routine-call';
    aClassification.fReason := 'external-routine-call';
  end else if lHadResolvedReceiver and IsAssignmentTargetUse(aSource, aUse) then
  begin
    aClassification.fReceiverText := lResolvedReceiverText;
    aClassification.fReceiverType := lResolvedReceiverType;
    aClassification.fStatus := TRemoveWithIdentifierStatus.rwisUnresolved;
    aClassification.fResolutionKind := 'unresolved';
    aClassification.fReason := 'receiver-member-not-found';
  end;

end;

class procedure TRemoveWithIdentifierResolver.ResolveStatement(const aInventory: TRemoveWithFactSet;
  const aScanResult: TRemoveWithScanResult; const aStatement: TRemoveWithStatementInfo;
  const aSource: TRemoveWithSourceBuffer; const aSymbolMapBridge: TRemoveWithSymbolMapBridge;
  const aInactiveRanges: TArray<TRemoveWithInactiveRange>;
  var aResult: TRemoveWithResolverResult);
var
  lBodyOffsets: TRemoveWithOffsetRange;
  lClassification: TRemoveWithIdentifierClassification;
  lBinding: TDelphiSemanticWithBinding;
  lInactiveRange: TRemoveWithInactiveRange;
  lReceivers: TArray<TRemoveWithReceiverScope>;
  lRoutineName: string;
  lSelectorRoutineName: string;
  lSkipRanges: TList<TRemoveWithOffsetRange>;
  lScopedLocalNames: TArray<TRemoveWithScopedLocalRange>;
  lStatement: TRemoveWithStatementInfo;
  lStatements: TArray<TRemoveWithStatementInfo>;
  lUse: TRemoveWithIdentifierUse;
  lUses: TArray<TRemoveWithIdentifierUse>;
  lWithOffsets: TRemoveWithOffsetRange;
begin
  if not RangeOffsets(aSource, aStatement.fBodyRange, lBodyOffsets) then
    Exit;
  if not TryFindSemanticBindingForStatement(aInventory, aStatement, lBinding) then
    lBinding := Default(TDelphiSemanticWithBinding);
  if aStatement.fHasUnsupportedIdentifierRoleInBody and
    not UnsupportedRoleCanRemainUnchanged(aStatement.fUnsupportedIdentifierRole) then
    Exit;
  if not FindRoutineForStatement(aInventory, aStatement, lRoutineName) then
    lRoutineName := '';
  lSelectorRoutineName := '';
  if (lBinding.RoutineName <> '') and (not SameText(lBinding.RoutineName, lRoutineName)) and
    (Pos('.', lRoutineName) > 0) and (Pos('.', lBinding.RoutineName) = 0) then
    lSelectorRoutineName := lBinding.RoutineName;

  BuildReceiverStack(aInventory, aScanResult, aStatement, lRoutineName, lSelectorRoutineName, lBinding, lReceivers);
  lSkipRanges := TList<TRemoveWithOffsetRange>.Create;
  try
    for lInactiveRange in aInactiveRanges do
    begin
      lWithOffsets.fStartOffset := lInactiveRange.fStartOffset;
      lWithOffsets.fEndOffset := lInactiveRange.fEndOffset;
      lSkipRanges.Add(lWithOffsets);
    end;
    if Assigned(GResolverNestedStatementsById) and
      GResolverNestedStatementsById.TryGetValue(aStatement.fId, lStatements) then
    begin
    end else
      lStatements := nil;
    for lStatement in lStatements do
    begin
      if RangeOffsets(aSource, lStatement.fRange, lWithOffsets) then
        lSkipRanges.Add(lWithOffsets);
    end;
    CollectIdentifierUses(aSource, lBodyOffsets, lSkipRanges.ToArray, lUses);
    CollectScopedLocalNames(aSource, lBodyOffsets, lScopedLocalNames);
  finally
    lSkipRanges.Free;
  end;

  for lUse in lUses do
  begin
    if ScopedLocalNameExistsAt(lScopedLocalNames, lUse.fName, lUse.fStartOffset) then
      Continue;
    if not ClassifyUse(aInventory, aSource, lRoutineName, lReceivers, lBinding, lUse, aSymbolMapBridge,
      lClassification) then
      Continue;
    EnrichWithSymbolMap(aSymbolMapBridge, lClassification);
    EnrichWithSemanticFacts(aInventory, lClassification);
    lClassification.fStatementId := aStatement.fId;
    lClassification.fFilePath := aStatement.fFilePath;
    AddClassification(aResult, lClassification);
  end;
end;

class function TRemoveWithIdentifierResolver.Resolve(const aInventory: TRemoveWithFactSet;
  const aScanResult: TRemoveWithScanResult; out aResult: TRemoveWithResolverResult; out aError: string): Boolean;
var
  lBridge: TRemoveWithSymbolMapBridge;
begin
  lBridge := Default(TRemoveWithSymbolMapBridge);
  Result := Resolve(aInventory, aScanResult, lBridge, aResult, aError);
end;

class function TRemoveWithIdentifierResolver.Resolve(const aInventory: TRemoveWithFactSet;
  const aScanResult: TRemoveWithScanResult; const aSymbolMapBridge: TRemoveWithSymbolMapBridge;
  out aResult: TRemoveWithResolverResult; out aError: string): Boolean;
var
  lCurrentPath: string;
  lInactiveRanges: TArray<TRemoveWithInactiveRange>;
  lResolverCacheStarted: Boolean;
  lSelectorCacheStarted: Boolean;
  lSource: TRemoveWithSourceBuffer;
  lStatement: TRemoveWithStatementInfo;
  lStatementContextCacheStarted: Boolean;
begin
  aResult := Default(TRemoveWithResolverResult);
  aError := '';
  Result := False;
  lCurrentPath := '';
  lResolverCacheStarted := False;
  lSelectorCacheStarted := False;
  lSource := Default(TRemoveWithSourceBuffer);
  lStatementContextCacheStarted := False;
  try
    try
      BeginResolverCache(aInventory);
      lResolverCacheStarted := True;
      BeginRemoveWithSelectorTypeCache(aInventory);
      lSelectorCacheStarted := True;
      BeginResolverStatementContextCache(aScanResult);
      lStatementContextCacheStarted := True;
      for lStatement in aScanResult.fWithStatements do
      begin
        if not SameText(lCurrentPath, lStatement.fFilePath) then
        begin
          if not LoadRemoveWithSource(lStatement.fFilePath, lSource, aError) then
            Exit(False);
          lCurrentPath := lStatement.fFilePath;
          lInactiveRanges := RemoveWithInactiveDirectiveRanges(lSource, aInventory.fParserDefines);
        end;
        ResolveStatement(aInventory, aScanResult, lStatement, lSource, aSymbolMapBridge,
          lInactiveRanges, aResult);
      end;
      Result := True;
    except
      on E: Exception do
        aError := E.Message;
    end;
  finally
    if lStatementContextCacheStarted then
      EndResolverStatementContextCache;
    if lSelectorCacheStarted then
      EndRemoveWithSelectorTypeCache;
    if lResolverCacheStarted then
      EndResolverCache;
  end;
end;

function ResolveRemoveWithIdentifiers(const aInventory: TRemoveWithFactSet;
  const aScanResult: TRemoveWithScanResult; out aResult: TRemoveWithResolverResult; out aError: string): Boolean;
var
  lBridge: TRemoveWithSymbolMapBridge;
begin
  lBridge := Default(TRemoveWithSymbolMapBridge);
  Result := TRemoveWithIdentifierResolver.Resolve(aInventory, aScanResult, lBridge, aResult, aError);
end;

function ResolveRemoveWithIdentifiers(const aInventory: TRemoveWithFactSet;
  const aScanResult: TRemoveWithScanResult; const aSymbolMapBridge: TRemoveWithSymbolMapBridge;
  out aResult: TRemoveWithResolverResult; out aError: string): Boolean;
begin
  Result := TRemoveWithIdentifierResolver.Resolve(aInventory, aScanResult, aSymbolMapBridge, aResult, aError);
end;

function SemanticReferenceKindToRemoveWithKind(const aKind: string): TRemoveWithSymbolKind;
begin
  if SameText(aKind, 'field') then
    Result := TRemoveWithSymbolKind.rwskField
  else if SameText(aKind, 'property') then
    Result := TRemoveWithSymbolKind.rwskProperty
  else if SameText(aKind, 'method') then
    Result := TRemoveWithSymbolKind.rwskMethod
  else if SameText(aKind, 'constant') then
    Result := TRemoveWithSymbolKind.rwskConstant
  else if SameText(aKind, 'class-var') then
    Result := TRemoveWithSymbolKind.rwskClassVar
  else if SameText(aKind, 'routine') or SameText(aKind, 'intrinsic-routine') then
    Result := TRemoveWithSymbolKind.rwskRoutine
  else
    Result := TRemoveWithSymbolKind.rwskField;
end;

function SemanticReferenceStatus(const aReference: TDelphiSemanticBoundReference):
  TRemoveWithIdentifierStatus;
begin
  if SameText(aReference.Classification, 'member') then
    Result := TRemoveWithIdentifierStatus.rwisResolved
  else if SameText(aReference.Classification, 'unsupported') then
    Result := TRemoveWithIdentifierStatus.rwisUnsupported
  else if SameText(aReference.Classification, 'unresolved') then
    Result := TRemoveWithIdentifierStatus.rwisUnresolved
  else if SameText(aReference.Classification, 'ambiguous') then
    Result := TRemoveWithIdentifierStatus.rwisAmbiguousToDak
  else
    Result := TRemoveWithIdentifierStatus.rwisUnchanged;
end;

function SemanticReferenceReason(const aReference: TDelphiSemanticBoundReference): string;
begin
  Result := aReference.ReasonCode;
  if Result = '' then
    Result := aReference.Classification;
end;

function SemanticReferenceResolutionKind(
  const aReference: TDelphiSemanticBoundReference): string;
begin
  Result := aReference.LookupSource;
  if SameText(Result, 'receiver') then
  begin
    if EndsText('Helper', aReference.ReceiverTypeName) or
      ContainsText(aReference.ReceiverTypeName, 'HelperFor') then
      Result := 'helper'
    else
      Result := 'direct';
  end;
end;

function ReceiverTextForSemanticReference(const aBinding: TDelphiSemanticWithBinding;
  const aReference: TDelphiSemanticBoundReference): string;
var
  i: Integer;
begin
  Result := '';
  for i := High(aBinding.Selectors) downto 0 do
    if SameText(aBinding.Selectors[i].TypeName, aReference.ReceiverTypeName) then
      Exit(aBinding.Selectors[i].SelectorText);
  if (Result = '') and (Length(aBinding.Selectors) = 1) then
    Result := aBinding.Selectors[0].SelectorText;
end;

procedure AddSemanticClassification(
  const aClassifications: TList<TRemoveWithIdentifierClassification>;
  const aStatementId: string; const aBinding: TDelphiSemanticWithBinding;
  const aReference: TDelphiSemanticBoundReference);
var
  lClassification: TRemoveWithIdentifierClassification;
begin
  lClassification := Default(TRemoveWithIdentifierClassification);
  lClassification.fStatementId := aStatementId;
  lClassification.fFilePath := aBinding.FileName;
  lClassification.fIdentifier := aReference.Name;
  lClassification.fReceiverText := ReceiverTextForSemanticReference(aBinding, aReference);
  lClassification.fReceiverType := aReference.ReceiverTypeName;
  lClassification.fResolutionKind := SemanticReferenceResolutionKind(aReference);
  if lClassification.fResolutionKind = '' then
    lClassification.fResolutionKind := aReference.Classification;
  if SameText(lClassification.fResolutionKind, 'direct') then
    lClassification.fSourceOwnerType := ''
  else
    lClassification.fSourceOwnerType := aReference.ReceiverTypeName;
  lClassification.fMemberKind := SemanticReferenceKindToRemoveWithKind(aReference.Kind);
  lClassification.fReason := SemanticReferenceReason(aReference);
  if SameText(aReference.Classification, 'member') then
  lClassification.fReason := '';
  lClassification.fLine := aReference.Line;
  lClassification.fColumn := aReference.Column;
  lClassification.fStatus := SemanticReferenceStatus(aReference);
  aClassifications.Add(lClassification);
end;

function SemanticMemberHasDakScopeShadow(const aInventory: TRemoveWithFactSet;
  const aBinding: TDelphiSemanticWithBinding; const aStatement: TRemoveWithStatementInfo): Boolean;
var
  lReference: TDelphiSemanticBoundReference;
  lRoutineName: string;
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  if not TRemoveWithIdentifierResolver.FindRoutineForStatement(aInventory, aStatement,
    lRoutineName) then
    lRoutineName := '';

  for lReference in aBinding.References do
  begin
    if (not SameText(lReference.Classification, 'member')) or (lReference.Name = '') then
      Continue;
    if TRemoveWithIdentifierResolver.FindScopeSymbolAtLocation(aInventory,
      aStatement.fFilePath, lReference.Line, lRoutineName, lReference.Name, lSymbol) and
      (lSymbol.fKind = TRemoveWithSymbolKind.rwskRoutine) then
      Exit(True);
  end;
end;

function SemanticStatementNeedsDakFallback(const aInventory: TRemoveWithFactSet;
  const aBinding: TDelphiSemanticWithBinding; const aStatement: TRemoveWithStatementInfo): Boolean;
var
  lReference: TDelphiSemanticBoundReference;
begin
  if aBinding.HasScopedDeclaration or aStatement.fHasScopedDeclarationInBody then
    Exit(True);

  if SemanticMemberHasDakScopeShadow(aInventory, aBinding, aStatement) then
    Exit(True);

  if (aStatement.fSelectorCount > 1) or (Length(aBinding.Selectors) > 1) then
    Exit(True);

  for lReference in aBinding.References do
    if not (SameText(lReference.Classification, 'member') or
      SameText(lReference.Classification, 'lexical') or
      SameText(lReference.Classification, 'intrinsic')) then
      Exit(True)
    else if SameText(lReference.Classification, 'lexical') and (lReference.Name <> '') and
      CharInSet(lReference.Name[1], ['A'..'Z']) then
      Exit(True)
    else if SameText(lReference.Classification, 'member') and
      ContainsText(lReference.ReceiverTypeName, 'HelperFor') then
      Exit(True);

  Result := False;
end;

procedure AddFallbackStatement(var aScanResult: TRemoveWithScanResult;
  const aStatement: TRemoveWithStatementInfo);
var
  lIndex: Integer;
begin
  lIndex := Length(aScanResult.fWithStatements);
  SetLength(aScanResult.fWithStatements, lIndex + 1);
  aScanResult.fWithStatements[lIndex] := aStatement;
end;

function SemanticStatementContains(const aOuter, aInner: TRemoveWithStatementInfo): Boolean;
begin
  Result := ((aOuter.fRange.fStartLine < aInner.fRange.fStartLine) or
    ((aOuter.fRange.fStartLine = aInner.fRange.fStartLine) and
    (aOuter.fRange.fStartColumn <= aInner.fRange.fStartColumn))) and
    ((aOuter.fRange.fEndLine > aInner.fRange.fEndLine) or
    ((aOuter.fRange.fEndLine = aInner.fRange.fEndLine) and
    (aOuter.fRange.fEndColumn >= aInner.fRange.fEndColumn)));
end;

function SemanticStatementNeedsFallbackContext(const aCandidate,
  aTarget: TRemoveWithStatementInfo): Boolean;
begin
  Result := SameText(TPath.GetFullPath(aCandidate.fFilePath),
    TPath.GetFullPath(aTarget.fFilePath)) and
    (SemanticStatementContains(aCandidate, aTarget) or
    SemanticStatementContains(aTarget, aCandidate));
end;

procedure ExpandFallbackScanContext(var aFallbackScanResult: TRemoveWithScanResult;
  const aFullScanResult: TRemoveWithScanResult);
var
  lCandidate: TRemoveWithStatementInfo;
  lContextIds: TDictionary<string, Byte>;
  lTarget: TRemoveWithStatementInfo;
  lTargets: TArray<TRemoveWithStatementInfo>;
begin
  lTargets := Copy(aFallbackScanResult.fWithStatements);
  aFallbackScanResult.fWithStatements := nil;
  lContextIds := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for lCandidate in aFullScanResult.fWithStatements do
      for lTarget in lTargets do
        if SemanticStatementNeedsFallbackContext(lCandidate, lTarget) and
          (not lContextIds.ContainsKey(lCandidate.fId)) then
        begin
          lContextIds.Add(lCandidate.fId, 0);
          AddFallbackStatement(aFallbackScanResult, lCandidate);
          Break;
        end;
  finally
    lContextIds.Free;
  end;
end;

procedure AppendResolverClassifications(
  const aClassifications: TList<TRemoveWithIdentifierClassification>;
  const aSource: TRemoveWithResolverResult; const aStatementIds: TDictionary<string, Byte>);
var
  lClassification: TRemoveWithIdentifierClassification;
begin
  for lClassification in aSource.fClassifications do
  begin
    if not aStatementIds.ContainsKey(lClassification.fStatementId) then
      Continue;
    aClassifications.Add(lClassification);
  end;
end;

function SemanticStatementIndexKey(const aFilePath: string; const aLine,
  aColumn: Integer): string;
begin
  Result := TPath.GetFullPath(aFilePath) + #31 + IntToStr(aLine) + #31 +
    IntToStr(aColumn);
end;

function BuildSemanticStatementIndex(const aScanResult: TRemoveWithScanResult):
  TDictionary<string, TRemoveWithStatementInfo>;
var
  lStatement: TRemoveWithStatementInfo;
begin
  Result := TDictionary<string, TRemoveWithStatementInfo>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  for lStatement in aScanResult.fWithStatements do
    Result.AddOrSetValue(SemanticStatementIndexKey(lStatement.fFilePath,
      lStatement.fRange.fStartLine, lStatement.fRange.fStartColumn), lStatement);
end;

function ResolveRemoveWithIdentifiersFromSemanticFacts(const aInventory: TRemoveWithFactSet;
  const aScanResult: TRemoveWithScanResult; out aResult: TRemoveWithResolverResult;
  out aError: string): Boolean;
var
  lBindingEntry: TRemoveWithSemanticWithBinding;
  lClassifications: TList<TRemoveWithIdentifierClassification>;
  lFallbackResult: TRemoveWithResolverResult;
  lFallbackScanResult: TRemoveWithScanResult;
  lReference: TDelphiSemanticBoundReference;
  lStatement: TRemoveWithStatementInfo;
  lStatementsByRange: TDictionary<string, TRemoveWithStatementInfo>;
  lStatementIds: TDictionary<string, Byte>;
  lStatementId: string;
  lUseSemanticFacts: Boolean;
begin
  aResult := Default(TRemoveWithResolverResult);
  aError := '';
  lFallbackScanResult := Default(TRemoveWithScanResult);
  lFallbackScanResult.fFiles := Copy(aScanResult.fFiles);
  lFallbackScanResult.fWarnings := Copy(aScanResult.fWarnings);
  lClassifications := TList<TRemoveWithIdentifierClassification>.Create;
  lStatementsByRange := BuildSemanticStatementIndex(aScanResult);
  lStatementIds := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for lBindingEntry in aInventory.fDelphiSemanticWithBindingEntries do
    begin
      lStatementId := lBindingEntry.fBinding.SemanticId;
      lUseSemanticFacts := True;
      if lStatementsByRange.TryGetValue(SemanticStatementIndexKey(lBindingEntry.fBinding.FileName,
        lBindingEntry.fBinding.Line, lBindingEntry.fBinding.Column), lStatement) then
      begin
        lStatementId := lStatement.fId;
        lUseSemanticFacts := not SemanticStatementNeedsDakFallback(aInventory,
          lBindingEntry.fBinding, lStatement);
        if not lUseSemanticFacts then
        begin
          AddFallbackStatement(lFallbackScanResult, lStatement);
          lStatementIds.AddOrSetValue(lStatement.fId, 0);
        end;
      end;
    if lUseSemanticFacts then
      for lReference in lBindingEntry.fBinding.References do
        AddSemanticClassification(lClassifications, lStatementId, lBindingEntry.fBinding,
          lReference);
    end;
    if Length(lFallbackScanResult.fWithStatements) > 0 then
    begin
      ExpandFallbackScanContext(lFallbackScanResult, aScanResult);
      if not ResolveRemoveWithIdentifiers(aInventory, lFallbackScanResult,
        lFallbackResult, aError) then
        Exit(False);
      AppendResolverClassifications(lClassifications, lFallbackResult, lStatementIds);
    end;
    aResult.fClassifications := lClassifications.ToArray;
  finally
    lStatementIds.Free;
    lStatementsByRange.Free;
    lClassifications.Free;
  end;
  Result := True;
end;

end.
