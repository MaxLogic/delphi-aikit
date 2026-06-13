unit Dak.RemoveWith.Symbols;

interface

uses
  DelphiSemantics.Api, DelphiSemantics.Api.RemoveWith,
  Dak.RemoveWith.Model, Dak.Types;

type
  TRemoveWithTypeCategory = (rwtcUnknown, rwtcRecord, rwtcClass, rwtcInterface);

  TRemoveWithSymbolKind = (rwskLocalVariable, rwskParameter, rwskCurrentClassMember, rwskUnitGlobal,
    rwskTypeMember, rwskField, rwskProperty, rwskMethod, rwskConstant, rwskClassVar, rwskRoutine, rwskUnitName,
    rwskExternal);

  TRemoveWithSymbolInfo = record
    fName: string;
    fTypeName: string;
    fOwnerType: string;
    fSourceOwnerType: string;
    fRelatedTypeName: string;
    fRoutineName: string;
    fUnitName: string;
    fFilePath: string;
    fLine: Integer;
    fEndLine: Integer;
    fColumn: Integer;
    fUnsupportedReason: string;
    fIsHelper: Boolean;
    fIsOverride: Boolean;
    fIsDefault: Boolean;
    fTypeCategory: TRemoveWithTypeCategory;
    fKind: TRemoveWithSymbolKind;
  end;

  TRemoveWithSemanticWithBinding = record
    fFilePath: string;
    fBinding: TDelphiSemanticWithBinding;
  end;

  TRemoveWithFactSet = record
    fContextFingerprint: string;
    fSymbols: TArray<TRemoveWithSymbolInfo>;
    fDelphiSemanticLookupIndex: TDelphiSemanticRemoveWithLookupIndex;
    fDelphiSemanticUnitModels: TArray<TDelphiSemanticUnitModel>;
    fDelphiSemanticWithBindingEntries: TArray<TRemoveWithSemanticWithBinding>;
    fDelphiSemanticRemoveWithPlan: TDelphiSemanticRemoveWithPlan;
    fParserDefines: string;
  end;

  TRemoveWithFactSetPhaseMetrics = record
    fSemanticProjectFactsMs: Int64;
    fSemanticCompatibilityFactsMs: Int64;
    fSemanticBindingMs: Int64;
    fSemanticPlanDtoMs: Int64;
    fDakLookupIndexMs: Int64;
    fDakLookupCacheHits: Int64;
    fDakLookupCacheMisses: Int64;
    fSemanticModelExtractionMs: Int64;
    fSemanticInventoryBuildMs: Int64;
    fSemanticScopeIndexBuildMs: Int64;
    fSemanticSelectorBindingMs: Int64;
    fSemanticReferenceBindingMs: Int64;
    fSemanticReceiverMemberResolveMs: Int64;
    fSemanticLexicalResolveMs: Int64;
    fSemanticReferenceCacheHitCount: Int64;
    fSemanticReferenceCacheMissCount: Int64;
    fSemanticLookupIndexBuildMs: Int64;
    fSemanticBindingIndexBuildMs: Int64;
    fSemanticInventoryExpansionMs: Int64;
    fSemanticCacheHits: Int64;
    fSemanticCacheMisses: Int64;
    fSemanticCacheInvalidations: Int64;
    fProjectFactsCacheHits: Int64;
    fProjectFactsCacheMisses: Int64;
    fProjectFactsCacheInvalidations: Int64;
    fSnapshotSqlWriteMs: Int64;
    fSnapshotSqlReadMs: Int64;
    fSnapshotDeserializeMs: Int64;
    fSnapshotIndexRebuildMs: Int64;
    fRtlSourceEnrichmentMs: Int64;
    fExternalUnitSymbolsMs: Int64;
    fExternalTypeSymbolsMs: Int64;
    fProblemSymbolAssemblyMs: Int64;
  end;

function RemoveWithSymbolKindToText(const aKind: TRemoveWithSymbolKind): string;
function RemoveWithTypeCategoryToText(const aCategory: TRemoveWithTypeCategory): string;
function RemoveWithFactSetLookupIndexBuildMilliseconds(const aInventory: TRemoveWithFactSet):
  Int64;
function RemoveWithFactSetLookupIndexHitCount(const aInventory: TRemoveWithFactSet): Int64;
function RemoveWithFactSetLookupIndexMissCount(const aInventory: TRemoveWithFactSet): Int64;
function FindRemoveWithFactSetMembers(const aInventory: TRemoveWithFactSet; const aOwnerType,
  aName: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
function FindRemoveWithFactSetRoutineSymbol(const aInventory: TRemoveWithFactSet;
  const aRoutineName, aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
function RemoveWithFactSetPointerTargetType(const aInventory: TRemoveWithFactSet;
  const aTypeName: string): string;
function FindRemoveWithFactSetDeclarationOrTypeAlias(const aInventory: TRemoveWithFactSet;
  const aName: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
function FindRemoveWithFactSetUnitOrGlobal(const aInventory: TRemoveWithFactSet;
  const aName: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
function FindRemoveWithFactSetUnitOrGlobalPrefix(const aInventory: TRemoveWithFactSet;
  const aName: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
function FindRemoveWithFactSetSymbolsByName(const aInventory: TRemoveWithFactSet;
  const aName: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
function FindRemoveWithFactSetSymbolsByOwnerType(const aInventory: TRemoveWithFactSet;
  const aOwnerType: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
function FindRemoveWithFactSetDefaultProperty(const aInventory: TRemoveWithFactSet;
  const aOwnerType: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
function BuildRemoveWithFactSet(const aOptions: TAppOptions; out aInventory: TRemoveWithFactSet;
  out aError: string): Boolean; overload;
function BuildRemoveWithFactSet(const aOptions: TAppOptions; out aInventory: TRemoveWithFactSet;
  out aError: string; out aPhaseMetrics: TRemoveWithFactSetPhaseMetrics): Boolean; overload;
function BuildRemoveWithFactSet(const aOptions: TAppOptions; const aProjectModel: TRemoveWithProjectModel;
  out aInventory: TRemoveWithFactSet; out aError: string): Boolean; overload;
function BuildRemoveWithFactSet(const aOptions: TAppOptions; const aProjectModel: TRemoveWithProjectModel;
  out aInventory: TRemoveWithFactSet; out aError: string;
  out aPhaseMetrics: TRemoveWithFactSetPhaseMetrics): Boolean; overload;
function BuildRemoveWithFactSet(const aOptions: TAppOptions; const aProjectModel: TRemoveWithProjectModel;
  const aBodyAnalysisSourceFileNames: TArray<string>; out aInventory: TRemoveWithFactSet;
  out aError: string; out aPhaseMetrics: TRemoveWithFactSetPhaseMetrics): Boolean; overload;

implementation

uses
  System.Classes, System.Diagnostics, System.Generics.Collections, System.IOUtils, System.StrUtils,
  System.SysUtils,
  DelphiAST.ProjectIndexer,
  DelphiSemantics.Cache, DelphiSemantics.CompilerProfile,
  DelphiSemantics.Model,
  MaxLogic.StrUtils;

procedure LogRemoveWithSymbolProgress(const aOptions: TAppOptions; const aMessage: string);
begin
  if not aOptions.fVerbose then
    Exit;
  WriteLn(ErrOutput, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now) + ' [remove-with:symbols] ' +
    aMessage);
  Flush(ErrOutput);
end;

type
  TRemoveWithSymbolInventoryContext = class
  private
    fLogicalSymbolKeys: TDictionary<string, Byte>;
    fSymbolKeys: TDictionary<string, Byte>;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TRemoveWithSymbolBuilder = record
  private
    class function SameSymbol(const aLeft, aRight: TRemoveWithSymbolInfo): Boolean; static;
    class function SameLogicalNonRoutineSymbol(const aLeft, aRight: TRemoveWithSymbolInfo): Boolean; static;
    class function SymbolIdentityKey(const aSymbol: TRemoveWithSymbolInfo): string; static;
    class function LogicalSymbolIdentityKey(const aSymbol: TRemoveWithSymbolInfo): string; static;
    class function CleanLine(const aLine: string): string; static;
    class function IsIdentifierChar(const aValue: Char): Boolean; static;
    class function IsTopLevelLine(const aLine: string): Boolean; static;
    class function IsVisibilityLine(const aLine: string): Boolean; static;
    class function IsRoutineStart(const aLine: string): Boolean; static;
    class function IsAttributeLine(const aLine: string): Boolean; static;
    class function IsConditionalDirectiveLine(const aLine: string): Boolean; static;
    class function IsConditionalStartDirective(const aLine: string): Boolean; static;
    class function IsConditionalEndDirective(const aLine: string): Boolean; static;
    class function IsMultilineDeclarationStart(const aLine: string): Boolean; static;
    class function TryDeclaration(const aLine: string; out aNames: TArray<string>; out aTypeName: string): Boolean;
      static;
    class function TryConstDeclaration(const aLine: string; out aName: string; out aTypeName: string): Boolean; static;
    class function TryPropertyDeclaration(const aLine: string; out aName, aTypeName: string;
      out aIsDefault: Boolean): Boolean; static;
    class function TryEnumValues(const aTypeText: string; out aNames: TArray<string>): Boolean; static;
    class function TryTypeAlias(const aLine: string; out aName: string; out aTypeName: string): Boolean; static;
    class function TryTypeStart(const aLine: string; out aName: string;
      out aCategory: TRemoveWithTypeCategory): Boolean; static;
    class function TryVariantTagDeclaration(const aLine: string; out aName, aTypeName: string): Boolean; static;
    class function VariantFieldDeclarationLine(const aLine: string): string; static;
    class function TryTypeRelation(const aLine: string; out aRelatedTypeName: string; out aIsHelper: Boolean): Boolean;
      static;
    class function TryRoutineName(const aLine: string; out aName: string): Boolean; static;
    class function TryRoutineOwner(const aRoutineName: string; out aOwnerType: string): Boolean; static;
    class function EndTerminatedBlockOpenCount(const aText: string): Integer; static;
    class function TokenCount(const aText, aToken: string): Integer; static;
    class function FindRoutineEndLine(const aLines: TArray<string>; const aStartIndex: Integer): Integer; static;
    class function CollectDeclarationText(const aLines: TArray<string>; const aStartLine: Integer): string; overload;
      static;
    class function CollectDeclarationText(const aLines: TArray<string>; const aStartLine: Integer;
      out aEndLine: Integer): string; overload; static;
    class function CollectTypeStartText(const aLines: TArray<string>; const aStartLine: Integer): string; static;
    class function FindColumn(const aLine, aName: string): Integer; static;
    class function IsDirectMemberKind(const aKind: TRemoveWithSymbolKind): Boolean; static;
    class function IsBuiltInTypeName(const aTypeName: string): Boolean; static;
    class function OwnerHasOwnMember(const aInventory: TRemoveWithFactSet; const aOwnerType,
      aName: string): Boolean; static;
    class function SimpleTypeName(const aTypeName: string): string; static;
    class function UnsupportedReasonForTypeStart(const aTypeName, aPendingReason: string;
      const aConditionalDepth: Integer): string; static;
    class function FindNameSource(const aLines: TArray<string>; const aStartIndex, aEndIndex: Integer;
      const aName: string; out aLineNumber: Integer; out aLineText: string): Boolean; static;
    class function DecodeSourceText(const aBytes: TBytes): string; static;
    class function ReadSourceLines(const aFilePath: string): TArray<string>; static;
    class procedure AddSymbol(const aContext: TRemoveWithSymbolInventoryContext;
      var aInventory: TRemoveWithFactSet; const aSymbol: TRemoveWithSymbolInfo);
      static;
    class procedure MarkTypeUnsupported(const aContext: TRemoveWithSymbolInventoryContext;
      var aInventory: TRemoveWithFactSet; const aTypeName,
      aReason: string); static;
    class procedure AddNamedSymbols(const aContext: TRemoveWithSymbolInventoryContext;
      var aInventory: TRemoveWithFactSet; const aNames: TArray<string>;
      const aTypeName, aOwnerType, aRoutineName, aUnitName, aFilePath: string; const aLineNumber: Integer;
      const aLineText: string; const aKind: TRemoveWithSymbolKind); static;
    class procedure AddNamedSymbolsFromSource(const aContext: TRemoveWithSymbolInventoryContext;
      var aInventory: TRemoveWithFactSet;
      const aNames: TArray<string>; const aTypeName, aOwnerType, aRoutineName, aUnitName, aFilePath: string;
      const aLines: TArray<string>; const aStartIndex, aEndIndex: Integer; const aKind: TRemoveWithSymbolKind);
      static;
    class procedure AddExternalTypeSymbols(const aContext: TRemoveWithSymbolInventoryContext;
      var aInventory: TRemoveWithFactSet); static;
  end;

constructor TRemoveWithSymbolInventoryContext.Create;
begin
  inherited Create;
  fSymbolKeys := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    fLogicalSymbolKeys := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  except
    FreeAndNil(fSymbolKeys);
    raise;
  end;
end;

destructor TRemoveWithSymbolInventoryContext.Destroy;
begin
  fLogicalSymbolKeys.Free;
  fSymbolKeys.Free;
  inherited;
end;

procedure AppendDelphiSemanticModel(var aInventory: TRemoveWithFactSet;
  const aModel: TDelphiSemanticUnitModel);
var
  lIndex: Integer;
begin
  lIndex := Length(aInventory.fDelphiSemanticUnitModels);
  SetLength(aInventory.fDelphiSemanticUnitModels, lIndex + 1);
  aInventory.fDelphiSemanticUnitModels[lIndex] := aModel;
end;

procedure AppendDelphiSemanticBindings(var aInventory: TRemoveWithFactSet;
  const aBindings: TArray<TDelphiSemanticWithBinding>);
var
  lBinding: TDelphiSemanticWithBinding;
  lEntryIndex: Integer;
begin
  for lBinding in aBindings do
  begin
    lEntryIndex := Length(aInventory.fDelphiSemanticWithBindingEntries);
    SetLength(aInventory.fDelphiSemanticWithBindingEntries, lEntryIndex + 1);
    aInventory.fDelphiSemanticWithBindingEntries[lEntryIndex].fFilePath := lBinding.FileName;
    aInventory.fDelphiSemanticWithBindingEntries[lEntryIndex].fBinding := lBinding;
  end;
end;

function DelphiSemanticKindToRemoveWithKind(const aSymbolClass: string;
  out aKind: TRemoveWithSymbolKind): Boolean;
begin
  Result := True;
  if SameText(aSymbolClass, 'local') then
    aKind := TRemoveWithSymbolKind.rwskLocalVariable
  else if SameText(aSymbolClass, 'parameter') then
    aKind := TRemoveWithSymbolKind.rwskParameter
  else if SameText(aSymbolClass, 'current-class-member') then
    aKind := TRemoveWithSymbolKind.rwskCurrentClassMember
  else if SameText(aSymbolClass, 'unit-global') then
    aKind := TRemoveWithSymbolKind.rwskUnitGlobal
  else if SameText(aSymbolClass, 'type-member') then
    aKind := TRemoveWithSymbolKind.rwskTypeMember
  else if SameText(aSymbolClass, 'field') then
    aKind := TRemoveWithSymbolKind.rwskField
  else if SameText(aSymbolClass, 'property') then
    aKind := TRemoveWithSymbolKind.rwskProperty
  else if SameText(aSymbolClass, 'method') then
    aKind := TRemoveWithSymbolKind.rwskMethod
  else if SameText(aSymbolClass, 'constant') then
    aKind := TRemoveWithSymbolKind.rwskConstant
  else if SameText(aSymbolClass, 'class-var') then
    aKind := TRemoveWithSymbolKind.rwskClassVar
  else if SameText(aSymbolClass, 'routine') then
    aKind := TRemoveWithSymbolKind.rwskRoutine
  else if SameText(aSymbolClass, 'unit') then
    aKind := TRemoveWithSymbolKind.rwskUnitName
  else if SameText(aSymbolClass, 'external') then
    aKind := TRemoveWithSymbolKind.rwskExternal
  else
    Result := False;
end;

function DelphiSemanticTypeCategoryToRemoveWithCategory(const aTypeCategory: string):
  TRemoveWithTypeCategory;
begin
  if SameText(aTypeCategory, 'record') then
    Result := TRemoveWithTypeCategory.rwtcRecord
  else if SameText(aTypeCategory, 'class') then
    Result := TRemoveWithTypeCategory.rwtcClass
  else if SameText(aTypeCategory, 'interface') then
    Result := TRemoveWithTypeCategory.rwtcInterface
  else
    Result := TRemoveWithTypeCategory.rwtcUnknown;
end;

function ShouldTranslateDelphiSemanticSymbol(const aSymbol: TDelphiSemanticInventorySymbol):
  Boolean;
begin
  Result := True;
  if SameText(aSymbol.SymbolClass, 'local') or SameText(aSymbol.SymbolClass, 'parameter') then
    Exit(aSymbol.Line > 0);
  if SameText(aSymbol.SymbolClass, 'routine') and (aSymbol.SectionKind <> '') then
    Exit(False);
end;

procedure AppendDelphiSemanticSymbols(const aContext: TRemoveWithSymbolInventoryContext;
  var aInventory: TRemoveWithFactSet;
  const aSemanticSymbols: TArray<TDelphiSemanticInventorySymbol>); forward;
function RemoveWithSymbolFromDelphiSemanticSymbol(
  const aSemanticSymbol: TDelphiSemanticInventorySymbol;
  out aSymbol: TRemoveWithSymbolInfo): Boolean; forward;

procedure AppendDelphiSemanticSymbols(const aContext: TRemoveWithSymbolInventoryContext;
  var aInventory: TRemoveWithFactSet;
  const aSemanticSymbols: TArray<TDelphiSemanticInventorySymbol>);
var
  lSemanticSymbol: TDelphiSemanticInventorySymbol;
  lSymbol: TRemoveWithSymbolInfo;
begin
  for lSemanticSymbol in aSemanticSymbols do
  begin
    if not RemoveWithSymbolFromDelphiSemanticSymbol(lSemanticSymbol, lSymbol) then
      Continue;
    TRemoveWithSymbolBuilder.AddSymbol(aContext, aInventory, lSymbol);
  end;
end;

function RemoveWithSymbolFromDelphiSemanticSymbol(
  const aSemanticSymbol: TDelphiSemanticInventorySymbol;
  out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lKind: TRemoveWithSymbolKind;
begin
  Result := False;
  if not ShouldTranslateDelphiSemanticSymbol(aSemanticSymbol) then
    Exit;
  if SameText(aSemanticSymbol.SymbolClass, 'declaration') then
  begin
    if not (SameText(aSemanticSymbol.Kind, 'type') or SameText(aSemanticSymbol.Kind, 'type-alias')) then
      Exit;
    lKind := TRemoveWithSymbolKind.rwskTypeMember;
  end else if SameText(aSemanticSymbol.SymbolClass, 'member') then
  begin
    if not DelphiSemanticKindToRemoveWithKind(aSemanticSymbol.Kind, lKind) then
      Exit;
  end else if not DelphiSemanticKindToRemoveWithKind(aSemanticSymbol.SymbolClass, lKind) then
    Exit;

  aSymbol := Default(TRemoveWithSymbolInfo);
  aSymbol.fName := aSemanticSymbol.Name;
  aSymbol.fTypeName := aSemanticSymbol.TypeName;
  aSymbol.fOwnerType := aSemanticSymbol.OwnerType;
  if aSymbol.fOwnerType = '' then
    aSymbol.fOwnerType := aSemanticSymbol.OwnerName;
  aSymbol.fSourceOwnerType := aSemanticSymbol.SourceOwnerType;
  aSymbol.fRelatedTypeName := aSemanticSymbol.RelatedTypeName;
  aSymbol.fRoutineName := aSemanticSymbol.RoutineName;
  aSymbol.fUnitName := aSemanticSymbol.UnitName;
  aSymbol.fFilePath := aSemanticSymbol.FileName;
  aSymbol.fLine := aSemanticSymbol.Line;
  aSymbol.fEndLine := aSemanticSymbol.EndLine;
  aSymbol.fColumn := aSemanticSymbol.Column;
  aSymbol.fUnsupportedReason := aSemanticSymbol.UnsupportedReason;
  aSymbol.fIsHelper := aSemanticSymbol.IsHelper;
  aSymbol.fIsOverride := aSemanticSymbol.IsOverride;
  aSymbol.fIsDefault := aSemanticSymbol.IsDefault;
  aSymbol.fTypeCategory := DelphiSemanticTypeCategoryToRemoveWithCategory(
    aSemanticSymbol.TypeCategory);
  aSymbol.fKind := lKind;
  Result := True;
end;

function RemoveWithFactSetLookupIndexBuildMilliseconds(const aInventory: TRemoveWithFactSet):
  Int64;
begin
  Result := aInventory.fDelphiSemanticLookupIndex.Metrics.BuildMilliseconds;
end;

function RemoveWithFactSetLookupIndexHitCount(const aInventory: TRemoveWithFactSet): Int64;
begin
  Result := aInventory.fDelphiSemanticLookupIndex.Metrics.HitCount;
end;

function RemoveWithFactSetLookupIndexMissCount(const aInventory: TRemoveWithFactSet): Int64;
begin
  Result := aInventory.fDelphiSemanticLookupIndex.Metrics.MissCount;
end;

function RemoveWithSymbolsFromSemanticSymbols(
  const aSemanticSymbols: TArray<TDelphiSemanticInventorySymbol>):
  TArray<TRemoveWithSymbolInfo>;
var
  lSemanticSymbol: TDelphiSemanticInventorySymbol;
  lSymbols: TList<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  lSymbols := TList<TRemoveWithSymbolInfo>.Create;
  try
    for lSemanticSymbol in aSemanticSymbols do
      if RemoveWithSymbolFromDelphiSemanticSymbol(lSemanticSymbol, lSymbol) then
        lSymbols.Add(lSymbol);
    Result := lSymbols.ToArray;
  finally
    lSymbols.Free;
  end;
end;

function FindRemoveWithFactSetMembers(const aInventory: TRemoveWithFactSet; const aOwnerType,
  aName: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
var
  lSemanticSymbols: TArray<TDelphiSemanticInventorySymbol>;
begin
  lSemanticSymbols := aInventory.fDelphiSemanticLookupIndex.FindMembersByOwnerAndName(
    aOwnerType, aName);
  aSymbols := RemoveWithSymbolsFromSemanticSymbols(lSemanticSymbols);
  Result := Length(aSymbols) > 0;
end;

function FindRemoveWithFactSetRoutineSymbol(const aInventory: TRemoveWithFactSet;
  const aRoutineName, aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lSemanticSymbol: TDelphiSemanticInventorySymbol;
begin
  aSymbol := Default(TRemoveWithSymbolInfo);
  if not aInventory.fDelphiSemanticLookupIndex.FindRoutineSymbol(aRoutineName, aName,
    lSemanticSymbol) then
    Exit(False);
  Result := RemoveWithSymbolFromDelphiSemanticSymbol(lSemanticSymbol, aSymbol);
end;

function RemoveWithFactSetPointerTargetType(const aInventory: TRemoveWithFactSet;
  const aTypeName: string): string;
var
  lTypeName: string;
begin
  Result := '';
  lTypeName := Trim(aTypeName);
  if StartsText('^', lTypeName) then
    Exit(Trim(Copy(lTypeName, 2, MaxInt)));

  Result := aInventory.fDelphiSemanticLookupIndex.PointerTargetType(lTypeName);
end;

function FindRemoveWithFactSetDeclarationOrTypeAlias(const aInventory: TRemoveWithFactSet;
  const aName: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
var
  lSemanticSymbols: TArray<TDelphiSemanticInventorySymbol>;
begin
  lSemanticSymbols := aInventory.fDelphiSemanticLookupIndex.FindDeclarationOrTypeAliasByName(
    aName);
  aSymbols := RemoveWithSymbolsFromSemanticSymbols(lSemanticSymbols);
  Result := Length(aSymbols) > 0;
end;

function FindRemoveWithFactSetUnitOrGlobal(const aInventory: TRemoveWithFactSet;
  const aName: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
var
  lSemanticSymbols: TArray<TDelphiSemanticInventorySymbol>;
begin
  lSemanticSymbols := aInventory.fDelphiSemanticLookupIndex.FindUnitOrGlobalByName(aName);
  aSymbols := RemoveWithSymbolsFromSemanticSymbols(lSemanticSymbols);
  Result := Length(aSymbols) > 0;
end;

function FindRemoveWithFactSetUnitOrGlobalPrefix(const aInventory: TRemoveWithFactSet;
  const aName: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
var
  lSemanticSymbols: TArray<TDelphiSemanticInventorySymbol>;
begin
  lSemanticSymbols := aInventory.fDelphiSemanticLookupIndex.FindUnitOrGlobalByPrefix(aName);
  aSymbols := RemoveWithSymbolsFromSemanticSymbols(lSemanticSymbols);
  Result := Length(aSymbols) > 0;
end;

function FindRemoveWithFactSetSymbolsByName(const aInventory: TRemoveWithFactSet;
  const aName: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
var
  lSemanticSymbols: TArray<TDelphiSemanticInventorySymbol>;
begin
  lSemanticSymbols := aInventory.fDelphiSemanticLookupIndex.FindSymbolsByName(aName);
  aSymbols := RemoveWithSymbolsFromSemanticSymbols(lSemanticSymbols);
  Result := Length(aSymbols) > 0;
end;

function FindRemoveWithFactSetSymbolsByOwnerType(const aInventory: TRemoveWithFactSet;
  const aOwnerType: string; out aSymbols: TArray<TRemoveWithSymbolInfo>): Boolean;
var
  lSemanticSymbols: TArray<TDelphiSemanticInventorySymbol>;
begin
  lSemanticSymbols := aInventory.fDelphiSemanticLookupIndex.FindSymbolsByOwnerType(
    aOwnerType);
  aSymbols := RemoveWithSymbolsFromSemanticSymbols(lSemanticSymbols);
  Result := Length(aSymbols) > 0;
end;

function FindRemoveWithFactSetDefaultProperty(const aInventory: TRemoveWithFactSet;
  const aOwnerType: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
begin
  aSymbol := Default(TRemoveWithSymbolInfo);
  if not FindRemoveWithFactSetSymbolsByOwnerType(aInventory, aOwnerType, lSymbols) then
    Exit(False);
  for lSymbol in lSymbols do
  begin
    if (lSymbol.fKind = TRemoveWithSymbolKind.rwskProperty) and lSymbol.fIsDefault then
    begin
      aSymbol := lSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

function IsRtlSourceCandidateUnit(const aUnitName: string): Boolean;
begin
  if SameText(aUnitName, 'Classes') or SameText(aUnitName, 'System.Classes') then
    Exit(False);

  Result := (Pos('.', aUnitName) > 0) and MatchText(Copy(aUnitName, 1, Pos('.', aUnitName) - 1),
    ['System', 'Winapi', 'Vcl', 'FMX']);
  if Result then
    Exit;

  Result := MatchText(aUnitName, ['Contnrs', 'DateUtils', 'Generics.Collections',
    'IOUtils', 'Masks', 'Math', 'StrUtils', 'SysUtils', 'Types', 'Variants', 'Windows']);
end;

procedure AddRtlUnitName(const aUnitNames: TDictionary<string, Byte>; const aUnitName: string);
var
  lUnitName: string;
begin
  lUnitName := Trim(aUnitName);
  if (lUnitName = '') or not IsRtlSourceCandidateUnit(lUnitName) then
    Exit;

  aUnitNames.AddOrSetValue(lUnitName, 1);
end;

function CollectRtlUnitNames(const aProjectModel: TRemoveWithProjectModel;
  const aInventory: TRemoveWithFactSet): TArray<string>;
var
  lUnitName: string;
  lUnitNames: TDictionary<string, Byte>;
  lUnitModel: TRemoveWithUnitModel;
  lSemanticModel: TDelphiSemanticUnitModel;
begin
  lUnitNames := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for lUnitModel in aProjectModel.UnitModels do
      for lUnitName in lUnitModel.fUses do
        AddRtlUnitName(lUnitNames, lUnitName);
    for lSemanticModel in aInventory.fDelphiSemanticUnitModels do
    begin
      for lUnitName in lSemanticModel.InterfaceUses do
        AddRtlUnitName(lUnitNames, lUnitName);
      for lUnitName in lSemanticModel.ImplementationUses do
        AddRtlUnitName(lUnitNames, lUnitName);
    end;
    Result := lUnitNames.Keys.ToArray;
  finally
    lUnitNames.Free;
  end;
end;

function HasUsableDelphiSemanticModel(const aModel: TDelphiSemanticUnitModel): Boolean;
begin
  Result := aModel.Success or (Length(aModel.Declarations) > 0) or (Length(aModel.Members) > 0) or
    (Length(aModel.Routines) > 0) or (Length(aModel.Locals) > 0);
end;

procedure AddRtlSourceModelSymbol(const aContext: TRemoveWithSymbolInventoryContext;
  var aInventory: TRemoveWithFactSet; const aName,
  aTypeName, aOwnerName, aUnitName, aFileName: string; const aKind: TRemoveWithSymbolKind;
  const aLine, aColumn: Integer; const aTypeCategory: TRemoveWithTypeCategory = TRemoveWithTypeCategory.rwtcUnknown);
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  if aName = '' then
    Exit;

  lSymbol := Default(TRemoveWithSymbolInfo);
  lSymbol.fName := aName;
  lSymbol.fTypeName := aTypeName;
  lSymbol.fOwnerType := aOwnerName;
  lSymbol.fUnitName := aUnitName;
  lSymbol.fFilePath := aFileName;
  lSymbol.fLine := aLine;
  lSymbol.fEndLine := aLine;
  lSymbol.fColumn := aColumn;
  if lSymbol.fColumn <= 0 then
    lSymbol.fColumn := 1;
  lSymbol.fTypeCategory := aTypeCategory;
  lSymbol.fKind := aKind;
  TRemoveWithSymbolBuilder.AddSymbol(aContext, aInventory, lSymbol);
end;

procedure AppendRtlSourceModelSymbols(const aContext: TRemoveWithSymbolInventoryContext;
  var aInventory: TRemoveWithFactSet;
  const aModel: TDelphiSemanticUnitModel);
var
  lDeclaration: TDelphiSemanticDeclaration;
  lKind: TRemoveWithSymbolKind;
  lMember: TDelphiSemanticMember;
  lRoutine: TDelphiSemanticRoutine;
begin
  for lDeclaration in aModel.Declarations do
  begin
    if SameText(lDeclaration.Kind, 'type') or SameText(lDeclaration.Kind, 'type-alias') then
      AddRtlSourceModelSymbol(aContext, aInventory, lDeclaration.Name, lDeclaration.TypeName, '',
        aModel.UnitName, aModel.FileName, TRemoveWithSymbolKind.rwskTypeMember,
        lDeclaration.Line, lDeclaration.Column,
        DelphiSemanticTypeCategoryToRemoveWithCategory(lDeclaration.TypeName))
    else if SameText(lDeclaration.Kind, 'routine') then
      AddRtlSourceModelSymbol(aContext, aInventory, lDeclaration.Name, lDeclaration.TypeName, '',
        aModel.UnitName, aModel.FileName, TRemoveWithSymbolKind.rwskRoutine,
        lDeclaration.Line, lDeclaration.Column)
    else if SameText(lDeclaration.Kind, 'const') or SameText(lDeclaration.Kind, 'typed-const') or
      SameText(lDeclaration.Kind, 'resourcestring') or SameText(lDeclaration.Kind, 'enum-value') then
      AddRtlSourceModelSymbol(aContext, aInventory, lDeclaration.Name, lDeclaration.TypeName,
        lDeclaration.BaseTypeName, aModel.UnitName, aModel.FileName,
        TRemoveWithSymbolKind.rwskConstant, lDeclaration.Line, lDeclaration.Column);
  end;

  for lRoutine in aModel.Routines do
    AddRtlSourceModelSymbol(aContext, aInventory, lRoutine.Name, lRoutine.ReturnType, '',
      aModel.UnitName, aModel.FileName, TRemoveWithSymbolKind.rwskRoutine,
      lRoutine.Line, lRoutine.Column);

  for lMember in aModel.Members do
  begin
    if SameText(lMember.Kind, 'property') then
      lKind := TRemoveWithSymbolKind.rwskProperty
    else if SameText(lMember.Kind, 'method') then
      lKind := TRemoveWithSymbolKind.rwskMethod
    else
      lKind := TRemoveWithSymbolKind.rwskField;
    AddRtlSourceModelSymbol(aContext, aInventory, lMember.Name, lMember.TypeName, lMember.OwnerName,
      aModel.UnitName, aModel.FileName, lKind, lMember.Line, lMember.Column);
  end;
end;

procedure AppendDelphiSemanticRtlSourceModels(const aContext: TRemoveWithSymbolInventoryContext;
  const aOptions: TAppOptions;
  const aProjectModel: TRemoveWithProjectModel; var aInventory: TRemoveWithFactSet);
var
  lCache: TDelphiSemanticUnitCache;
  lCacheOptions: TDelphiSemanticCacheOptions;
  lProfile: TDelphiSemanticCompilerProfile;
  lRtlSourceRoot: string;
  lSemanticModel: TDelphiSemanticUnitModel;
  lUnitNames: TArray<string>;
begin
  lUnitNames := CollectRtlUnitNames(aProjectModel, aInventory);
  LogRemoveWithSymbolProgress(aOptions, Format('rtl-source units=%d', [Length(lUnitNames)]));
  if Length(lUnitNames) = 0 then
    Exit;

  lRtlSourceRoot := TDelphiSemanticCompilerProfileBuilder.ResolveRtlSourceRoot(
    aOptions.fDelphiVersion, aOptions.fRsVarsPath);
  LogRemoveWithSymbolProgress(aOptions, 'rtl-source root=' + lRtlSourceRoot);
  if lRtlSourceRoot = '' then
    Exit;

  lCacheOptions := Default(TDelphiSemanticCacheOptions);
  lCacheOptions.CompilerProfileName := Format('DAK-%s-%s-%s', [aOptions.fDelphiVersion,
    aOptions.fPlatform, aOptions.fConfig]);
  lCacheOptions.DelphiVersion := aOptions.fDelphiVersion;
  lCacheOptions.Configuration := aOptions.fConfig;
  lCacheOptions.Platform := aOptions.fPlatform;
  lCache := TDelphiSemanticUnitCache.Create(lCacheOptions);
  try
    lProfile := TDelphiSemanticCompilerProfileBuilder.ProfileForTargetFromRtlSourceRoot(lCache,
      lCacheOptions.CompilerProfileName, aOptions.fDelphiVersion, aOptions.fPlatform,
    lRtlSourceRoot, lUnitNames);
    LogRemoveWithSymbolProgress(aOptions, Format('rtl-source models=%d',
      [Length(lProfile.RtlSourceUnitModels)]));
    for lSemanticModel in lProfile.RtlSourceUnitModels do
    begin
      LogRemoveWithSymbolProgress(aOptions, Format('rtl-source model unit=%s success=%s declarations=%d members=%d',
        [lSemanticModel.UnitName, BoolToStr(lSemanticModel.Success, True),
        Length(lSemanticModel.Declarations), Length(lSemanticModel.Members)]));
      if not HasUsableDelphiSemanticModel(lSemanticModel) then
        Continue;
      AppendDelphiSemanticModel(aInventory, lSemanticModel);
      AppendRtlSourceModelSymbols(aContext, aInventory, lSemanticModel);
    end;
  finally
    lCache.Free;
  end;
end;

function BuildProjectSemanticOptions(const aOptions: TAppOptions;
  const aProjectModel: TRemoveWithProjectModel): TDelphiSemanticApiOptions;
var
  lCacheDir: string;
  lProjectDir: string;
  lUnitFileName: string;
  lSourceFileNames: TList<string>;
  lUnitModel: TRemoveWithUnitModel;
begin
  Result := Default(TDelphiSemanticApiOptions);
  Result.ProjectFileName := aProjectModel.ProjectPath;
  Result.Configuration := aOptions.fConfig;
  Result.Platform := aOptions.fPlatform;
  Result.DelphiVersion := aOptions.fDelphiVersion;
  Result.RsVarsPath := aOptions.fRsVarsPath;
  Result.EnvOptionsPath := aOptions.fEnvOptionsPath;
  lProjectDir := IncludeTrailingPathDelimiter(TPath.GetDirectoryName(aProjectModel.ProjectPath));
  lSourceFileNames := TList<string>.Create;
  try
    for lUnitModel in aProjectModel.UnitModels do
    begin
      lUnitFileName := Trim(lUnitModel.fFilePath);
      if lUnitFileName = '' then
        Continue;
      lUnitFileName := TPath.GetFullPath(lUnitFileName);
      if StartsText(lProjectDir, lUnitFileName) then
        lSourceFileNames.Add(lUnitFileName);
    end;
    Result.AdditionalSourceFileNames := lSourceFileNames.ToArray;
  finally
    lSourceFileNames.Free;
  end;
  Result.Cache.DelphiVersion := aOptions.fDelphiVersion;
  Result.Cache.Configuration := aOptions.fConfig;
  Result.Cache.Platform := aOptions.fPlatform;
  Result.SkipWithBindingSemanticGraph := True;
  if aOptions.fHasRemoveWithSemanticCachePath and
    (Trim(aOptions.fRemoveWithSemanticCachePath) <> '') then
  begin
    Result.Cache.SqliteCacheFileName := aOptions.fRemoveWithSemanticCachePath;
    lCacheDir := TPath.GetDirectoryName(Result.Cache.SqliteCacheFileName);
    if lCacheDir <> '' then
      TDirectory.CreateDirectory(lCacheDir);
  end;
end;

function BuildProjectSemanticFacts(const aContext: TRemoveWithSymbolInventoryContext;
  const aOptions: TAppOptions;
  const aProjectModel: TRemoveWithProjectModel;
  const aBodyAnalysisSourceFileNames: TArray<string>;
  var aInventory: TRemoveWithFactSet;
  var aPhaseMetrics: TRemoveWithFactSetPhaseMetrics;
  out aError: string): Boolean;
var
  lFacts: TDelphiSemanticProjectWithBindingFacts;
  lModel: TDelphiSemanticUnitModel;
  lOptions: TDelphiSemanticApiOptions;
  lPlanStopwatch: TStopwatch;
  lRequest: TDelphiSemanticRemoveWithRequest;
  lStopwatch: TStopwatch;
begin
  Result := False;
  aError := '';
  lOptions := BuildProjectSemanticOptions(aOptions, aProjectModel);
  lRequest := Default(TDelphiSemanticRemoveWithRequest);
  lRequest.Options := lOptions;
  lRequest.BodyAnalysisSourceFileNames := Copy(aBodyAnalysisSourceFileNames);
  lStopwatch := TStopwatch.StartNew;
  try
    lFacts := TDelphiSemanticRemoveWithApi.BuildProjectWithBindingFacts(lRequest);
  except
    on E: Exception do
    begin
      aError := 'DelphiSemantics project facts failed: ' + E.Message;
      Exit(False);
    end;
  end;
  lStopwatch.Stop;
  aPhaseMetrics.fSemanticProjectFactsMs := lStopwatch.ElapsedMilliseconds;
  aPhaseMetrics.fSemanticModelExtractionMs := lFacts.Metrics.ModelExtractionMilliseconds;
  aPhaseMetrics.fSemanticInventoryBuildMs := lFacts.Metrics.InventoryBuildMilliseconds;
  aPhaseMetrics.fSemanticInventoryExpansionMs := lFacts.Metrics.InventoryExpansionMilliseconds;
  aPhaseMetrics.fSemanticBindingMs := lFacts.Metrics.BindingBuildMilliseconds;
  aPhaseMetrics.fSemanticScopeIndexBuildMs := lFacts.Metrics.ScopeIndexBuildMilliseconds;
  aPhaseMetrics.fSemanticSelectorBindingMs := lFacts.Metrics.SelectorBindingMilliseconds;
  aPhaseMetrics.fSemanticReferenceBindingMs := lFacts.Metrics.ReferenceBindingMilliseconds;
  aPhaseMetrics.fSemanticReceiverMemberResolveMs :=
    lFacts.Metrics.ReceiverMemberResolveMilliseconds;
  aPhaseMetrics.fSemanticLexicalResolveMs := lFacts.Metrics.LexicalResolveMilliseconds;
  aPhaseMetrics.fSemanticReferenceCacheHitCount := lFacts.Metrics.ReferenceCacheHitCount;
  aPhaseMetrics.fSemanticReferenceCacheMissCount := lFacts.Metrics.ReferenceCacheMissCount;
  aPhaseMetrics.fSemanticLookupIndexBuildMs := lFacts.Metrics.LookupIndexBuildMilliseconds;
  aPhaseMetrics.fSemanticBindingIndexBuildMs := lFacts.Metrics.LookupIndexBuildMilliseconds;
  aPhaseMetrics.fSemanticCacheHits := lFacts.Metrics.SemanticCacheHits;
  aPhaseMetrics.fSemanticCacheMisses := lFacts.Metrics.SemanticCacheMisses;
  aPhaseMetrics.fSemanticCacheInvalidations :=
    lFacts.Metrics.SemanticCacheInvalidations;
  aPhaseMetrics.fProjectFactsCacheHits := lFacts.Metrics.ProjectFactsCacheHits;
  aPhaseMetrics.fProjectFactsCacheMisses := lFacts.Metrics.ProjectFactsCacheMisses;
  aPhaseMetrics.fProjectFactsCacheInvalidations :=
    lFacts.Metrics.ProjectFactsCacheInvalidations;
  aPhaseMetrics.fSnapshotSqlWriteMs := lFacts.Metrics.SnapshotSqlWriteMilliseconds;
  aPhaseMetrics.fSnapshotSqlReadMs := lFacts.Metrics.SnapshotSqlReadMilliseconds;
  aPhaseMetrics.fSnapshotDeserializeMs := lFacts.Metrics.SnapshotDeserializeMilliseconds;
  aPhaseMetrics.fSnapshotIndexRebuildMs := lFacts.Metrics.SnapshotIndexRebuildMilliseconds;
  if lFacts.ContextFingerprint = '' then
  begin
    aError := 'DelphiSemantics project facts did not return a context fingerprint.';
    Exit(False);
  end;
  if lFacts.Metrics.UnitCount = 0 then
  begin
    aError := 'DelphiSemantics project facts did not return any project units.';
    Exit(False);
  end;
  aInventory.fContextFingerprint := lFacts.ContextFingerprint;
  aInventory.fDelphiSemanticLookupIndex := lFacts.LookupIndex;
  lPlanStopwatch := TStopwatch.StartNew;
  try
    aInventory.fDelphiSemanticRemoveWithPlan := TDelphiSemanticRemoveWithApi.PlanRemoveWithSnapshot(lFacts);
  except
    on E: Exception do
    begin
      aError := 'DelphiSemantics remove-with plan failed: ' + E.Message;
      Exit(False);
    end;
  end;
  lPlanStopwatch.Stop;
  aPhaseMetrics.fSemanticPlanDtoMs := lPlanStopwatch.ElapsedMilliseconds;
  if not SameText(aInventory.fDelphiSemanticRemoveWithPlan.Status, 'planned') then
  begin
    aError := 'DelphiSemantics remove-with plan failed: ' +
      aInventory.fDelphiSemanticRemoveWithPlan.Diagnostic;
    Exit(False);
  end;
  if not SameText(aInventory.fContextFingerprint,
    aInventory.fDelphiSemanticRemoveWithPlan.ContextFingerprint) then
  begin
    aError := Format(
      'DelphiSemantics remove-with plan context fingerprint mismatch: facts=%s plan=%s',
      [aInventory.fContextFingerprint,
      aInventory.fDelphiSemanticRemoveWithPlan.ContextFingerprint]);
    Exit(False);
  end;
  AppendDelphiSemanticBindings(aInventory, lFacts.Bindings);
  lStopwatch := TStopwatch.StartNew;
  if not aOptions.fRemoveWithSkipCompatibilityFacts then
  begin
    for lModel in lFacts.UnitModels do
      AppendDelphiSemanticModel(aInventory, lModel);
    AppendDelphiSemanticSymbols(aContext, aInventory, lFacts.Symbols);
  end;
  lStopwatch.Stop;
  aPhaseMetrics.fSemanticCompatibilityFactsMs := lStopwatch.ElapsedMilliseconds;
  LogRemoveWithSymbolProgress(aOptions, Format(
    'semantic-project-facts graph=%s units=%d withStatements=%d bindings=%d symbols=%d planEdits=%d planSkipped=%d context=%s',
    [BoolToStr(lFacts.Metrics.SemanticGraphUsed, True), lFacts.Metrics.UnitCount,
    lFacts.Metrics.WithStatementCount, lFacts.Metrics.BindingCount,
    Length(lFacts.Symbols), Length(aInventory.fDelphiSemanticRemoveWithPlan.Edits),
    Length(aInventory.fDelphiSemanticRemoveWithPlan.SkippedStatements),
    lFacts.ContextFingerprint]));

  aPhaseMetrics.fRtlSourceEnrichmentMs := 0;

  Result := True;
end;

function RemoveWithSymbolKindToText(const aKind: TRemoveWithSymbolKind): string;
begin
  case aKind of
    TRemoveWithSymbolKind.rwskLocalVariable:
      Result := 'local-variable';
    TRemoveWithSymbolKind.rwskParameter:
      Result := 'parameter';
    TRemoveWithSymbolKind.rwskCurrentClassMember:
      Result := 'current-class-member';
    TRemoveWithSymbolKind.rwskUnitGlobal:
      Result := 'unit-global';
    TRemoveWithSymbolKind.rwskTypeMember:
      Result := 'type-member';
    TRemoveWithSymbolKind.rwskField:
      Result := 'field';
    TRemoveWithSymbolKind.rwskProperty:
      Result := 'property';
    TRemoveWithSymbolKind.rwskMethod:
      Result := 'method';
    TRemoveWithSymbolKind.rwskConstant:
      Result := 'constant';
    TRemoveWithSymbolKind.rwskClassVar:
      Result := 'class-var';
    TRemoveWithSymbolKind.rwskRoutine:
      Result := 'routine';
    TRemoveWithSymbolKind.rwskUnitName:
      Result := 'unit';
  else
    Result := 'external';
  end;
end;

function RemoveWithTypeCategoryToText(const aCategory: TRemoveWithTypeCategory): string;
begin
  case aCategory of
    TRemoveWithTypeCategory.rwtcRecord:
      Result := 'record';
    TRemoveWithTypeCategory.rwtcClass:
      Result := 'class';
    TRemoveWithTypeCategory.rwtcInterface:
      Result := 'interface';
  else
    Result := 'unknown';
  end;
end;

class function TRemoveWithSymbolBuilder.CleanLine(const aLine: string): string;
var
  lCommentPos: Integer;
  lEndPos: Integer;
  lStartPos: Integer;
begin
  Result := Trim(aLine);
  if Result = '' then
    Exit;
  if StartsText('{$', Result) or StartsText('(*$', Result) then
    Exit;

  repeat
    lStartPos := Pos('{', Result);
    if lStartPos = 0 then
      Break;
    if Copy(Result, lStartPos, 2) = '{$' then
      Break;
    lEndPos := PosEx('}', Result, lStartPos + 1);
    if lEndPos = 0 then
    begin
      Delete(Result, lStartPos, MaxInt);
      Break;
    end;
    Delete(Result, lStartPos, lEndPos - lStartPos + 1);
    Result := Trim(Result);
  until False;

  repeat
    lStartPos := Pos('(*', Result);
    if lStartPos = 0 then
      Break;
    if Copy(Result, lStartPos, 3) = '(*$' then
      Break;
    lEndPos := PosEx('*)', Result, lStartPos + 2);
    if lEndPos = 0 then
    begin
      Delete(Result, lStartPos, MaxInt);
      Break;
    end;
    Delete(Result, lStartPos, lEndPos - lStartPos + 2);
    Result := Trim(Result);
  until False;

  lCommentPos := Pos('//', Result);
  if lCommentPos > 0 then
    Result := Trim(Copy(Result, 1, lCommentPos - 1));
end;

class function TRemoveWithSymbolBuilder.IsIdentifierChar(const aValue: Char): Boolean;
begin
  Result := CharInSet(aValue, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

class function TRemoveWithSymbolBuilder.IsTopLevelLine(const aLine: string): Boolean;
begin
  Result := (Trim(aLine) <> '') and (TrimLeft(aLine) = aLine);
end;

class function TRemoveWithSymbolBuilder.IsVisibilityLine(const aLine: string): Boolean;
begin
  Result := MatchText(LowerCase(Trim(aLine)), ['private', 'protected', 'public', 'published',
    'strict private', 'strict protected']);
end;

class function TRemoveWithSymbolBuilder.IsRoutineStart(const aLine: string): Boolean;
var
  lText: string;
begin
  lText := LowerCase(Trim(aLine));
  Result := StartsText('procedure ', lText) or StartsText('function ', lText) or
    StartsText('class procedure ', lText) or StartsText('class function ', lText) or
    StartsText('constructor ', lText) or StartsText('destructor ', lText);
end;

class function TRemoveWithSymbolBuilder.IsAttributeLine(const aLine: string): Boolean;
begin
  Result := StartsText('[', Trim(aLine));
end;

class function TRemoveWithSymbolBuilder.IsConditionalDirectiveLine(const aLine: string): Boolean;
var
  lText: string;
begin
  lText := UpperCase(Trim(aLine));
  Result := StartsText('{$IF', lText) or StartsText('{$ELSE', lText) or StartsText('{$ELSEIF', lText) or
    StartsText('{$ENDIF', lText) or StartsText('{$IFEND', lText);
end;

class function TRemoveWithSymbolBuilder.IsConditionalStartDirective(const aLine: string): Boolean;
var
  lText: string;
begin
  lText := UpperCase(Trim(aLine));
  Result := StartsText('{$IF', lText) and (not StartsText('{$IFEND', lText));
end;

class function TRemoveWithSymbolBuilder.IsConditionalEndDirective(const aLine: string): Boolean;
var
  lText: string;
begin
  lText := UpperCase(Trim(aLine));
  Result := StartsText('{$ENDIF', lText) or StartsText('{$IFEND', lText);
end;

class function TRemoveWithSymbolBuilder.IsMultilineDeclarationStart(const aLine: string): Boolean;
var
  lText: string;
begin
  lText := Trim(aLine);
  Result := (Pos(',', lText) > 0) and (Pos(':', lText) = 0) and (Pos(';', lText) = 0) and
    (not IsRoutineStart(lText));
end;

class function TRemoveWithSymbolBuilder.TryDeclaration(const aLine: string; out aNames: TArray<string>;
  out aTypeName: string): Boolean;
var
  lColonPos: Integer;
  lEqualsPos: Integer;
  lLeft: string;
  lPart: string;
  lParts: TArray<string>;
  lRawPart: string;
  lRight: string;
  lSemiPos: Integer;
  lNames: TList<string>;
begin
  Result := False;
  SetLength(aNames, 0);
  aTypeName := '';
  lColonPos := Pos(':', aLine);
  if lColonPos = 0 then
    Exit;

  lLeft := Trim(Copy(aLine, 1, lColonPos - 1));
  if (lLeft = '') or IsRoutineStart(lLeft) or StartsText('property ', LowerCase(lLeft)) then
    Exit;

  lRight := Trim(Copy(aLine, lColonPos + 1, MaxInt));
  lEqualsPos := Pos('=', lRight);
  if lEqualsPos > 0 then
    lRight := Trim(Copy(lRight, 1, lEqualsPos - 1));
  lSemiPos := Pos(';', lRight);
  if lSemiPos > 0 then
    lRight := Trim(Copy(lRight, 1, lSemiPos - 1));
  if lRight = '' then
    Exit;

  lNames := TList<string>.Create;
  try
    lParts := lLeft.Split([',']);
    for lRawPart in lParts do
    begin
      lPart := Trim(lRawPart);
      if lPart <> '' then
        lNames.Add(lPart);
    end;
    aNames := lNames.ToArray;
  finally
    lNames.Free;
  end;
  aTypeName := lRight;
  Result := Length(aNames) > 0;
end;

class function TRemoveWithSymbolBuilder.TryConstDeclaration(const aLine: string; out aName: string;
  out aTypeName: string): Boolean;
var
  lColonPos: Integer;
  lEqualsPos: Integer;
begin
  Result := False;
  aName := '';
  aTypeName := '';
  lEqualsPos := Pos('=', aLine);
  if lEqualsPos = 0 then
    Exit;

  lColonPos := Pos(':', aLine);
  if (lColonPos > 0) and (lColonPos < lEqualsPos) then
  begin
    aName := Trim(Copy(aLine, 1, lColonPos - 1));
    aTypeName := Trim(Copy(aLine, lColonPos + 1, lEqualsPos - lColonPos - 1));
  end else
  begin
    aName := Trim(Copy(aLine, 1, lEqualsPos - 1));
    aTypeName := '';
  end;
  Result := aName <> '';
end;

class function TRemoveWithSymbolBuilder.TryEnumValues(const aTypeText: string;
  out aNames: TArray<string>): Boolean;
var
  lClosePos: Integer;
  lEqualsPos: Integer;
  lList: TList<string>;
  lName: string;
  lOpenPos: Integer;
  lPart: string;
  lParts: TArray<string>;
  lPrefix: string;
  lRawPart: string;
  lText: string;
  i: Integer;
begin
  Result := False;
  SetLength(aNames, 0);
  lText := Trim(aTypeText);
  lEqualsPos := Pos('=', lText);
  lOpenPos := Pos('(', lText);
  lClosePos := PosEx(')', lText, lOpenPos + 1);
  if (lEqualsPos = 0) or (lOpenPos <= lEqualsPos) or (lClosePos <= lOpenPos) then
    Exit;

  lPrefix := Copy(lText, 1, lOpenPos - 1);
  if ContainsText(lPrefix, 'procedure') or ContainsText(lPrefix, 'function') then
    Exit;

  lList := TList<string>.Create;
  try
    lParts := Copy(lText, lOpenPos + 1, lClosePos - lOpenPos - 1).Split([',']);
    for lRawPart in lParts do
    begin
      lPart := Trim(lRawPart);
      lName := '';
      i := 1;
      while (i <= Length(lPart)) and IsIdentifierChar(lPart[i]) do
      begin
        lName := lName + lPart[i];
        Inc(i);
      end;
      if lName <> '' then
        lList.Add(lName);
    end;
    aNames := lList.ToArray;
    Result := Length(aNames) > 0;
  finally
    lList.Free;
  end;
end;

class function TRemoveWithSymbolBuilder.TryPropertyDeclaration(const aLine: string; out aName, aTypeName: string;
  out aIsDefault: Boolean): Boolean;
var
  lBracketDepth: Integer;
  lMemberText: string;
  lNameEnd: Integer;
  lPropertyTypeEnd: Integer;
  lTypePos: Integer;
  i: Integer;
begin
  Result := False;
  aName := '';
  aTypeName := '';
  aIsDefault := False;
  if not StartsText('property ', LowerCase(aLine)) then
    Exit;

  lMemberText := Trim(Copy(aLine, Length('property ') + 1, MaxInt));
  aIsDefault := ContainsText(LowerCase(lMemberText), ' default');
  lBracketDepth := 0;
  lTypePos := 0;
  for i := 1 to Length(lMemberText) do
  begin
    if lMemberText[i] = '[' then
      Inc(lBracketDepth)
    else if (lMemberText[i] = ']') and (lBracketDepth > 0) then
      Dec(lBracketDepth)
    else if (lMemberText[i] = ':') and (lBracketDepth = 0) then
    begin
      lTypePos := i;
      Break;
    end;
  end;

  if lTypePos > 0 then
  begin
    aTypeName := Trim(Copy(lMemberText, lTypePos + 1, MaxInt));
    lPropertyTypeEnd := Pos(' read ', LowerCase(aTypeName));
    if lPropertyTypeEnd = 0 then
      lPropertyTypeEnd := Pos(' write ', LowerCase(aTypeName));
    if lPropertyTypeEnd = 0 then
      lPropertyTypeEnd := Pos(' index ', LowerCase(aTypeName));
    if lPropertyTypeEnd = 0 then
      lPropertyTypeEnd := Pos(' default', LowerCase(aTypeName));
    if lPropertyTypeEnd = 0 then
      lPropertyTypeEnd := Pos(';', aTypeName);
    if lPropertyTypeEnd > 0 then
      aTypeName := Trim(Copy(aTypeName, 1, lPropertyTypeEnd - 1));
    lMemberText := Trim(Copy(lMemberText, 1, lTypePos - 1));
  end;

  lNameEnd := Pos('[', lMemberText);
  if lNameEnd = 0 then
    lNameEnd := Pos(';', lMemberText);
  if lNameEnd > 0 then
    aName := Trim(Copy(lMemberText, 1, lNameEnd - 1))
  else
    aName := Trim(lMemberText);
  Result := aName <> '';
end;

class function TRemoveWithSymbolBuilder.TryTypeAlias(const aLine: string; out aName: string;
  out aTypeName: string): Boolean;
var
  lEqualsPos: Integer;
  lRight: string;
  lSemiPos: Integer;
begin
  Result := False;
  aName := '';
  aTypeName := '';
  lEqualsPos := Pos('=', aLine);
  if lEqualsPos = 0 then
    Exit;

  aName := Trim(Copy(aLine, 1, lEqualsPos - 1));
  lRight := Trim(Copy(aLine, lEqualsPos + 1, MaxInt));
  lSemiPos := Pos(';', lRight);
  if lSemiPos > 0 then
    lRight := Trim(Copy(lRight, 1, lSemiPos - 1));

  aTypeName := lRight;
  Result := (aName <> '') and (aTypeName <> '');
end;

class function TRemoveWithSymbolBuilder.TryTypeStart(const aLine: string; out aName: string;
  out aCategory: TRemoveWithTypeCategory): Boolean;
var
  lEqualsPos: Integer;
  lLower: string;
begin
  Result := False;
  aName := '';
  aCategory := TRemoveWithTypeCategory.rwtcUnknown;
  lEqualsPos := Pos('=', aLine);
  if lEqualsPos = 0 then
    Exit;

  lLower := LowerCase(aLine);
  if (Pos(' record', lLower) = 0) and (Pos(' class', lLower) = 0) and (Pos(' interface', lLower) = 0) then
    Exit;

  if Pos(' record', lLower) > 0 then
    aCategory := TRemoveWithTypeCategory.rwtcRecord
  else if Pos(' interface', lLower) > 0 then
    aCategory := TRemoveWithTypeCategory.rwtcInterface
  else if Pos(' class', lLower) > 0 then
    aCategory := TRemoveWithTypeCategory.rwtcClass;

  aName := Trim(Copy(aLine, 1, lEqualsPos - 1));
  Result := aName <> '';
end;

class function TRemoveWithSymbolBuilder.TryVariantTagDeclaration(const aLine: string; out aName,
  aTypeName: string): Boolean;
var
  lColonPos: Integer;
  lOfPos: Integer;
  lRest: string;
  lRestLower: string;
  lText: string;
begin
  Result := False;
  aName := '';
  aTypeName := '';
  lText := Trim(aLine);
  if not StartsText('case ', LowerCase(lText)) then
    Exit;

  lRest := Trim(Copy(lText, Length('case ') + 1, MaxInt));
  lRestLower := LowerCase(lRest);
  lColonPos := Pos(':', lRest);
  lOfPos := Pos(' of', lRestLower);
  if (lColonPos = 0) or (lOfPos = 0) or (lOfPos < lColonPos) then
    Exit;

  aName := Trim(Copy(lRest, 1, lColonPos - 1));
  aTypeName := Trim(Copy(lRest, lColonPos + 1, lOfPos - lColonPos - 1));
  Result := (aName <> '') and (aTypeName <> '');
end;

class function TRemoveWithSymbolBuilder.VariantFieldDeclarationLine(const aLine: string): string;
var
  lInnerText: string;
  lOpenPos: Integer;
  lText: string;
begin
  Result := aLine;
  lText := Trim(aLine);
  lOpenPos := Pos('(', lText);
  if (lOpenPos > 1) and (Pos(':', Copy(lText, 1, lOpenPos - 1)) > 0) then
  begin
    lInnerText := Copy(lText, lOpenPos + 1, MaxInt);
    if Pos(':', lInnerText) > 0 then
      lText := Trim(Copy(lText, lOpenPos, MaxInt));
  end;
  if StartsText('(', lText) then
  begin
    lText := Trim(Copy(lText, 2, MaxInt));
    if EndsText(');', lText) then
      Result := Trim(Copy(lText, 1, Length(lText) - 2)) + ';'
    else if EndsText(')', lText) then
      Result := Trim(Copy(lText, 1, Length(lText) - 1)) + ';'
    else
      Result := lText;
  end else if EndsText(');', lText) then
    Result := Trim(Copy(lText, 1, Length(lText) - 2)) + ';';
end;

class function TRemoveWithSymbolBuilder.TryTypeRelation(const aLine: string; out aRelatedTypeName: string;
  out aIsHelper: Boolean): Boolean;
var
  lClosePos: Integer;
  lLower: string;
  lRelationPos: Integer;
  lStartPos: Integer;
  lText: string;
begin
  aRelatedTypeName := '';
  aIsHelper := False;
  lText := Trim(aLine);
  lLower := LowerCase(lText);

  lRelationPos := Pos(' helper for ', lLower);
  if lRelationPos > 0 then
  begin
    aIsHelper := True;
    aRelatedTypeName := Trim(Copy(lText, lRelationPos + Length(' helper for '), MaxInt));
    lClosePos := Pos(';', aRelatedTypeName);
    if lClosePos > 0 then
      aRelatedTypeName := Trim(Copy(aRelatedTypeName, 1, lClosePos - 1));
    Exit(aRelatedTypeName <> '');
  end;
  if Pos(' helper(', lLower) > 0 then
  begin
    aIsHelper := True;
    Exit(False);
  end;

  lStartPos := Pos('class(', lLower);
  if lStartPos > 0 then
  begin
    Inc(lStartPos, Length('class('));
    lClosePos := PosEx(')', lText, lStartPos);
    if lClosePos > lStartPos then
      aRelatedTypeName := Trim(Copy(lText, lStartPos, lClosePos - lStartPos));
    lClosePos := Pos(',', aRelatedTypeName);
    if lClosePos > 0 then
      aRelatedTypeName := Trim(Copy(aRelatedTypeName, 1, lClosePos - 1));
  end;
  if aRelatedTypeName = '' then
  begin
    lStartPos := Pos('interface(', lLower);
    if lStartPos > 0 then
    begin
      Inc(lStartPos, Length('interface('));
      lClosePos := PosEx(')', lText, lStartPos);
      if lClosePos > lStartPos then
        aRelatedTypeName := Trim(Copy(lText, lStartPos, lClosePos - lStartPos));
    end;
  end;
  Result := aRelatedTypeName <> '';
end;

class function TRemoveWithSymbolBuilder.TryRoutineName(const aLine: string; out aName: string): Boolean;
var
  lNameEnd: Integer;
  lNameStart: Integer;
  lText: string;
begin
  Result := False;
  aName := '';
  lText := Trim(aLine);
  if StartsText('class procedure ', lText) then
    lNameStart := Length('class procedure ') + 1
  else if StartsText('class function ', lText) then
    lNameStart := Length('class function ') + 1
  else if StartsText('procedure ', lText) then
    lNameStart := Length('procedure ') + 1
  else if StartsText('function ', lText) then
    lNameStart := Length('function ') + 1
  else if StartsText('constructor ', lText) then
    lNameStart := Length('constructor ') + 1
  else if StartsText('destructor ', lText) then
    lNameStart := Length('destructor ') + 1
  else
    Exit;

  lNameEnd := lNameStart;
  while lNameEnd <= Length(lText) do
  begin
    if IsIdentifierChar(lText[lNameEnd]) or (lText[lNameEnd] = '.') then
      Inc(lNameEnd)
    else
      Break;
  end;
  aName := Copy(lText, lNameStart, lNameEnd - lNameStart);
  Result := aName <> '';
end;

class function TRemoveWithSymbolBuilder.TryRoutineOwner(const aRoutineName: string; out aOwnerType: string): Boolean;
var
  lDotPos: Integer;
begin
  lDotPos := LastDelimiter('.', aRoutineName);
  Result := lDotPos > 0;
  if Result then
    aOwnerType := Copy(aRoutineName, 1, lDotPos - 1)
  else
    aOwnerType := '';
end;

class function TRemoveWithSymbolBuilder.TokenCount(const aText, aToken: string): Integer;
var
  lEndPos: Integer;
  lStartPos: Integer;
  i: Integer;
begin
  Result := 0;
  i := 1;
  while i <= Length(aText) do
  begin
    if not IsIdentifierChar(aText[i]) then
    begin
      Inc(i);
      Continue;
    end;
    lStartPos := i;
    while (i <= Length(aText)) and IsIdentifierChar(aText[i]) do
      Inc(i);
    lEndPos := i - 1;
    if SameText(Copy(aText, lStartPos, lEndPos - lStartPos + 1), aToken) then
      Inc(Result);
  end;
end;

class function TRemoveWithSymbolBuilder.EndTerminatedBlockOpenCount(const aText: string): Integer;
begin
  Result := TokenCount(aText, 'begin') + TokenCount(aText, 'case') + TokenCount(aText, 'try') +
    TokenCount(aText, 'asm');
end;

class function TRemoveWithSymbolBuilder.FindRoutineEndLine(const aLines: TArray<string>;
  const aStartIndex: Integer): Integer;
var
  lDepth: Integer;
  lLine: string;
  lNestedEndLine: Integer;
  lStarted: Boolean;
  i: Integer;
begin
  Result := 0;
  lDepth := 0;
  lStarted := False;
  i := aStartIndex + 1;
  while i <= High(aLines) do
  begin
    lLine := LowerCase(CleanLine(aLines[i]));
    if lLine = '' then
    begin
      Inc(i);
      Continue;
    end;
    if not lStarted then
    begin
      if IsTopLevelLine(aLines[i]) and (IsRoutineStart(lLine) or SameText(lLine, 'implementation') or
        SameText(lLine, 'interface')) then
        Exit(0);
      if IsRoutineStart(lLine) then
      begin
        lNestedEndLine := FindRoutineEndLine(aLines, i);
        if lNestedEndLine > 0 then
        begin
          i := lNestedEndLine;
          Continue;
        end;
      end;
      if (TokenCount(lLine, 'begin') = 0) and (TokenCount(lLine, 'asm') = 0) then
      begin
        Inc(i);
        Continue;
      end;
      lStarted := True;
    end;
    Inc(lDepth, EndTerminatedBlockOpenCount(lLine));
    Dec(lDepth, TokenCount(lLine, 'end'));
    if lStarted and (lDepth <= 0) then
      Exit(i + 1);
    Inc(i);
  end;
end;

class function TRemoveWithSymbolBuilder.CollectDeclarationText(const aLines: TArray<string>;
  const aStartLine: Integer): string;
var
  lEndLine: Integer;
begin
  Result := CollectDeclarationText(aLines, aStartLine, lEndLine);
end;

class function TRemoveWithSymbolBuilder.CollectDeclarationText(const aLines: TArray<string>;
  const aStartLine: Integer; out aEndLine: Integer): string;
var
  lLine: string;
  lParenDepth: Integer;
  i: Integer;
  j: Integer;
begin
  Result := '';
  aEndLine := aStartLine;
  lParenDepth := 0;
  for i := aStartLine to High(aLines) do
  begin
    aEndLine := i;
    lLine := CleanLine(aLines[i]);
    if lLine <> '' then
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + lLine;
      for j := 1 to Length(lLine) do
      begin
        if lLine[j] = '(' then
          Inc(lParenDepth)
        else if (lLine[j] = ')') and (lParenDepth > 0) then
          Dec(lParenDepth);
      end;
    end;
    if (Pos(';', lLine) > 0) and (lParenDepth = 0) then
      Exit;
  end;
end;

class function TRemoveWithSymbolBuilder.CollectTypeStartText(const aLines: TArray<string>;
  const aStartLine: Integer): string;
var
  lLine: string;
  lText: string;
  i: Integer;
begin
  Result := '';
  for i := aStartLine to High(aLines) do
  begin
    lLine := CleanLine(aLines[i]);
    if lLine <> '' then
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + lLine;
      lText := LowerCase(Result);
      if (Pos(' class', lText) > 0) or (Pos(' record', lText) > 0) or (Pos(' interface', lText) > 0) or
        (Pos(';', lLine) > 0) then
        Exit;
    end;
  end;
end;

class function TRemoveWithSymbolBuilder.FindColumn(const aLine, aName: string): Integer;
begin
  Result := Pos(aName, aLine);
  if Result = 0 then
    Result := 1;
end;

class function TRemoveWithSymbolBuilder.IsDirectMemberKind(const aKind: TRemoveWithSymbolKind): Boolean;
begin
  Result := aKind in [TRemoveWithSymbolKind.rwskField, TRemoveWithSymbolKind.rwskProperty,
    TRemoveWithSymbolKind.rwskMethod, TRemoveWithSymbolKind.rwskConstant, TRemoveWithSymbolKind.rwskClassVar];
end;

class function TRemoveWithSymbolBuilder.IsBuiltInTypeName(const aTypeName: string): Boolean;
begin
  Result := MatchText(aTypeName, ['AnsiString', 'Array', 'Boolean', 'Byte', 'Cardinal', 'Char', 'Currency',
    'Date', 'DateTime', 'Double', 'Extended', 'Integer', 'Int64', 'NativeInt', 'NativeUInt', 'Pointer', 'Real',
    'ShortInt', 'Single', 'SmallInt', 'String', 'UInt64', 'Variant', 'WideChar', 'WideString', 'Word']);
end;

class function TRemoveWithSymbolBuilder.OwnerHasOwnMember(const aInventory: TRemoveWithFactSet;
  const aOwnerType, aName: string): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  for lSymbol in aInventory.fSymbols do
  begin
    if SameText(lSymbol.fOwnerType, aOwnerType) and (lSymbol.fSourceOwnerType = '') and
      SameText(lSymbol.fName, aName) and IsDirectMemberKind(lSymbol.fKind) then
      Exit(True);
  end;
  Result := False;
end;

class function TRemoveWithSymbolBuilder.SimpleTypeName(const aTypeName: string): string;
var
  lDelimiterPos: Integer;
  lTypeName: string;
begin
  lTypeName := Trim(aTypeName);
  if StartsText('^', lTypeName) then
    Delete(lTypeName, 1, 1);
  lDelimiterPos := Pos('<', lTypeName);
  if lDelimiterPos = 0 then
    lDelimiterPos := Pos('[', lTypeName);
  if lDelimiterPos = 0 then
    lDelimiterPos := Pos(' ', lTypeName);
  if lDelimiterPos > 0 then
    lTypeName := Trim(Copy(lTypeName, 1, lDelimiterPos - 1));
  lDelimiterPos := LastDelimiter('.', lTypeName);
  if lDelimiterPos > 0 then
    lTypeName := Copy(lTypeName, lDelimiterPos + 1, MaxInt);
  Result := lTypeName;
end;

class function TRemoveWithSymbolBuilder.UnsupportedReasonForTypeStart(const aTypeName, aPendingReason: string;
  const aConditionalDepth: Integer): string;
begin
  if aPendingReason <> '' then
    Exit(aPendingReason);
  if aConditionalDepth > 0 then
    Exit('unsupported-source-model-conditional-region');
  if Pos('<', aTypeName) > 0 then
    Exit('unsupported-source-model-generic-declaration');
  Result := '';
end;

class function TRemoveWithSymbolBuilder.FindNameSource(const aLines: TArray<string>; const aStartIndex,
  aEndIndex: Integer; const aName: string; out aLineNumber: Integer; out aLineText: string): Boolean;
var
  lEndIndex: Integer;
  i: Integer;
begin
  Result := False;
  aLineNumber := 0;
  aLineText := '';
  lEndIndex := aEndIndex;
  if lEndIndex > High(aLines) then
    lEndIndex := High(aLines);
  for i := aStartIndex to lEndIndex do
  begin
    if Pos(aName, aLines[i]) > 0 then
    begin
      aLineNumber := i + 1;
      aLineText := aLines[i];
      Exit(True);
    end;
  end;
end;

class function TRemoveWithSymbolBuilder.DecodeSourceText(const aBytes: TBytes): string;
var
  lOffset: Integer;
begin
  lOffset := 0;
  if (Length(aBytes) >= 3) and (aBytes[0] = $EF) and (aBytes[1] = $BB) and (aBytes[2] = $BF) then
    lOffset := 3;

  try
    Result := TEncoding.UTF8.GetString(aBytes, lOffset, Length(aBytes) - lOffset);
  except
    on E: EEncodingError do
      Result := TEncoding.Default.GetString(aBytes, lOffset, Length(aBytes) - lOffset);
  end;
end;

class function TRemoveWithSymbolBuilder.ReadSourceLines(const aFilePath: string): TArray<string>;
var
  i: Integer;
  lLines: TStringList;
  lText: string;
begin
  lText := DecodeSourceText(TFile.ReadAllBytes(aFilePath));
  lLines := TStringList.Create;
  try
    lLines.Text := lText;
    SetLength(Result, lLines.Count);
    for i := 0 to lLines.Count - 1 do
      Result[i] := lLines[i];
  finally
    lLines.Free;
  end;
end;

class function TRemoveWithSymbolBuilder.SameSymbol(const aLeft, aRight: TRemoveWithSymbolInfo): Boolean;
begin
  Result := (aLeft.fKind = aRight.fKind) and SameText(aLeft.fName, aRight.fName) and
    SameText(aLeft.fTypeName, aRight.fTypeName) and SameText(aLeft.fOwnerType, aRight.fOwnerType) and
    SameText(aLeft.fSourceOwnerType, aRight.fSourceOwnerType) and
    SameText(aLeft.fRelatedTypeName, aRight.fRelatedTypeName) and
    SameText(aLeft.fRoutineName, aRight.fRoutineName) and SameText(aLeft.fUnitName, aRight.fUnitName) and
    SameText(aLeft.fFilePath, aRight.fFilePath) and (aLeft.fLine = aRight.fLine) and
    (aLeft.fEndLine = aRight.fEndLine) and (aLeft.fColumn = aRight.fColumn) and
    (aLeft.fIsHelper = aRight.fIsHelper) and
    (aLeft.fIsOverride = aRight.fIsOverride) and (aLeft.fIsDefault = aRight.fIsDefault) and
    (aLeft.fTypeCategory = aRight.fTypeCategory) and
    SameText(aLeft.fUnsupportedReason, aRight.fUnsupportedReason);
end;

class function TRemoveWithSymbolBuilder.SameLogicalNonRoutineSymbol(const aLeft,
  aRight: TRemoveWithSymbolInfo): Boolean;
begin
  if aLeft.fKind in [TRemoveWithSymbolKind.rwskMethod, TRemoveWithSymbolKind.rwskRoutine] then
    Exit(False);

  Result := (aLeft.fKind = aRight.fKind) and SameText(aLeft.fName, aRight.fName) and
    SameText(aLeft.fTypeName, aRight.fTypeName) and SameText(aLeft.fOwnerType, aRight.fOwnerType) and
    SameText(aLeft.fSourceOwnerType, aRight.fSourceOwnerType) and
    SameText(aLeft.fRelatedTypeName, aRight.fRelatedTypeName) and
    SameText(aLeft.fRoutineName, aRight.fRoutineName) and SameText(aLeft.fUnitName, aRight.fUnitName) and
    SameText(aLeft.fFilePath, aRight.fFilePath) and (aLeft.fIsHelper = aRight.fIsHelper) and
    (aLeft.fIsOverride = aRight.fIsOverride) and (aLeft.fIsDefault = aRight.fIsDefault) and
    (aLeft.fTypeCategory = aRight.fTypeCategory) and SameText(aLeft.fUnsupportedReason, aRight.fUnsupportedReason);
end;

class function TRemoveWithSymbolBuilder.SymbolIdentityKey(const aSymbol: TRemoveWithSymbolInfo): string;
const
  cSeparator = #31;
begin
  Result := IntToStr(Ord(aSymbol.fKind)) + cSeparator + aSymbol.fName + cSeparator + aSymbol.fTypeName +
    cSeparator + aSymbol.fOwnerType + cSeparator + aSymbol.fSourceOwnerType + cSeparator +
    aSymbol.fRelatedTypeName + cSeparator + aSymbol.fRoutineName + cSeparator + aSymbol.fUnitName +
    cSeparator + aSymbol.fFilePath + cSeparator + IntToStr(aSymbol.fLine) + cSeparator +
    IntToStr(aSymbol.fEndLine) + cSeparator + IntToStr(aSymbol.fColumn) + cSeparator +
    IntToStr(Ord(aSymbol.fIsHelper)) + cSeparator + IntToStr(Ord(aSymbol.fIsOverride)) + cSeparator +
    IntToStr(Ord(aSymbol.fIsDefault)) + cSeparator + IntToStr(Ord(aSymbol.fTypeCategory)) + cSeparator +
    aSymbol.fUnsupportedReason;
end;

function IsLogicalNonRoutineSymbol(const aSymbol: TRemoveWithSymbolInfo): Boolean;
begin
  Result := aSymbol.fKind <> TRemoveWithSymbolKind.rwskRoutine;
end;

class function TRemoveWithSymbolBuilder.LogicalSymbolIdentityKey(
  const aSymbol: TRemoveWithSymbolInfo): string;
const
  cSeparator = #31;
begin
  Result := IntToStr(Ord(aSymbol.fKind)) + cSeparator + aSymbol.fName + cSeparator + aSymbol.fTypeName +
    cSeparator + aSymbol.fOwnerType + cSeparator + aSymbol.fSourceOwnerType + cSeparator +
    aSymbol.fRelatedTypeName + cSeparator + aSymbol.fRoutineName + cSeparator + aSymbol.fUnitName +
    cSeparator + aSymbol.fFilePath + cSeparator + IntToStr(Ord(aSymbol.fIsHelper)) + cSeparator +
    IntToStr(Ord(aSymbol.fIsOverride)) + cSeparator + IntToStr(Ord(aSymbol.fIsDefault)) + cSeparator +
    IntToStr(Ord(aSymbol.fTypeCategory)) + cSeparator + aSymbol.fUnsupportedReason;
end;

class procedure TRemoveWithSymbolBuilder.AddSymbol(const aContext: TRemoveWithSymbolInventoryContext;
  var aInventory: TRemoveWithFactSet; const aSymbol: TRemoveWithSymbolInfo);
var
  lIndex: Integer;
  lKey: string;
begin
  if IsLogicalNonRoutineSymbol(aSymbol) then
  begin
    lKey := LogicalSymbolIdentityKey(aSymbol);
    if aContext.fLogicalSymbolKeys.ContainsKey(lKey) then
      Exit;
    aContext.fLogicalSymbolKeys.Add(lKey, 1);
  end;

  lKey := SymbolIdentityKey(aSymbol);
  if aContext.fSymbolKeys.ContainsKey(lKey) then
    Exit;
  aContext.fSymbolKeys.Add(lKey, 1);

  lIndex := Length(aInventory.fSymbols);
  SetLength(aInventory.fSymbols, lIndex + 1);
  aInventory.fSymbols[lIndex] := aSymbol;
end;

class procedure TRemoveWithSymbolBuilder.MarkTypeUnsupported(const aContext: TRemoveWithSymbolInventoryContext;
  var aInventory: TRemoveWithFactSet; const aTypeName, aReason: string);
var
  i: Integer;
  lKey: string;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeName: string;
begin
  if aReason = '' then
    Exit;
  lTypeName := SimpleTypeName(aTypeName);
  for i := 0 to High(aInventory.fSymbols) do
  begin
    if (aInventory.fSymbols[i].fKind = TRemoveWithSymbolKind.rwskTypeMember) and
      SameText(aInventory.fSymbols[i].fName, lTypeName) then
    begin
      if aInventory.fSymbols[i].fUnsupportedReason = '' then
      begin
        lSymbol := aInventory.fSymbols[i];
        aContext.fSymbolKeys.Remove(SymbolIdentityKey(lSymbol));
        if IsLogicalNonRoutineSymbol(lSymbol) then
          aContext.fLogicalSymbolKeys.Remove(LogicalSymbolIdentityKey(lSymbol));
        aInventory.fSymbols[i].fUnsupportedReason := aReason;
        lKey := SymbolIdentityKey(aInventory.fSymbols[i]);
        if not aContext.fSymbolKeys.ContainsKey(lKey) then
          aContext.fSymbolKeys.Add(lKey, 1);
        if IsLogicalNonRoutineSymbol(aInventory.fSymbols[i]) then
        begin
          lKey := LogicalSymbolIdentityKey(aInventory.fSymbols[i]);
          if not aContext.fLogicalSymbolKeys.ContainsKey(lKey) then
            aContext.fLogicalSymbolKeys.Add(lKey, 1);
        end;
      end;
      Exit;
    end;
  end;
end;

class procedure TRemoveWithSymbolBuilder.AddNamedSymbols(const aContext: TRemoveWithSymbolInventoryContext;
  var aInventory: TRemoveWithFactSet;
  const aNames: TArray<string>; const aTypeName, aOwnerType, aRoutineName, aUnitName, aFilePath: string;
  const aLineNumber: Integer; const aLineText: string; const aKind: TRemoveWithSymbolKind);
var
  lName: string;
  lSymbol: TRemoveWithSymbolInfo;
begin
  for lName in aNames do
  begin
    lSymbol := Default(TRemoveWithSymbolInfo);
    lSymbol.fName := lName;
    lSymbol.fTypeName := aTypeName;
    lSymbol.fOwnerType := aOwnerType;
    lSymbol.fRoutineName := aRoutineName;
    lSymbol.fUnitName := aUnitName;
    lSymbol.fFilePath := aFilePath;
    lSymbol.fLine := aLineNumber;
    lSymbol.fColumn := FindColumn(aLineText, lName);
    lSymbol.fKind := aKind;
    AddSymbol(aContext, aInventory, lSymbol);
  end;
end;

class procedure TRemoveWithSymbolBuilder.AddNamedSymbolsFromSource(
  const aContext: TRemoveWithSymbolInventoryContext; var aInventory: TRemoveWithFactSet;
  const aNames: TArray<string>; const aTypeName, aOwnerType, aRoutineName, aUnitName, aFilePath: string;
  const aLines: TArray<string>; const aStartIndex, aEndIndex: Integer; const aKind: TRemoveWithSymbolKind);
var
  lLineNumber: Integer;
  lLineText: string;
  lName: string;
begin
  for lName in aNames do
  begin
    if not FindNameSource(aLines, aStartIndex, aEndIndex, lName, lLineNumber, lLineText) then
    begin
      lLineNumber := aStartIndex + 1;
      if (aStartIndex >= 0) and (aStartIndex <= High(aLines)) then
        lLineText := aLines[aStartIndex]
      else
        lLineText := lName;
    end;
    AddNamedSymbols(aContext, aInventory, [lName], aTypeName, aOwnerType, aRoutineName, aUnitName, aFilePath,
      lLineNumber, lLineText, aKind);
  end;
end;

class procedure TRemoveWithSymbolBuilder.AddExternalTypeSymbols(
  const aContext: TRemoveWithSymbolInventoryContext; var aInventory: TRemoveWithFactSet);
var
  lExternalSymbol: TRemoveWithSymbolInfo;
  lExternalTypes: TDictionary<string, Byte>;
  lSourceTypes: TDictionary<string, Byte>;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeKey: string;
  lTypeName: string;
begin
  lSourceTypes := TDictionary<string, Byte>.Create;
  try
    lExternalTypes := TDictionary<string, Byte>.Create;
    try
      for lSymbol in aInventory.fSymbols do
      begin
        if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
          lSourceTypes.AddOrSetValue(UpperCase(lSymbol.fName), 1);
      end;

      for lSymbol in aInventory.fSymbols do
      begin
        lTypeName := SimpleTypeName(lSymbol.fTypeName);
        if (lTypeName <> '') and (not IsBuiltInTypeName(lTypeName)) then
        begin
          lTypeKey := UpperCase(lTypeName);
          if (not lSourceTypes.ContainsKey(lTypeKey)) and (not lExternalTypes.ContainsKey(lTypeKey)) then
          begin
            lExternalTypes.Add(lTypeKey, 1);
            lExternalSymbol := Default(TRemoveWithSymbolInfo);
            lExternalSymbol.fName := lTypeName;
            lExternalSymbol.fTypeName := lTypeName;
            lExternalSymbol.fKind := TRemoveWithSymbolKind.rwskExternal;
            AddSymbol(aContext, aInventory, lExternalSymbol);
          end;
        end;

        lTypeName := SimpleTypeName(lSymbol.fRelatedTypeName);
        if (lTypeName = '') or IsBuiltInTypeName(lTypeName) then
          Continue;
        lTypeKey := UpperCase(lTypeName);
        if lSourceTypes.ContainsKey(lTypeKey) or lExternalTypes.ContainsKey(lTypeKey) then
          Continue;
        lExternalTypes.Add(lTypeKey, 1);
        lExternalSymbol := Default(TRemoveWithSymbolInfo);
        lExternalSymbol.fName := lTypeName;
        lExternalSymbol.fTypeName := lTypeName;
        lExternalSymbol.fKind := TRemoveWithSymbolKind.rwskExternal;
        AddSymbol(aContext, aInventory, lExternalSymbol);
      end;
    finally
      lExternalTypes.Free;
    end;
  finally
    lSourceTypes.Free;
  end;
end;

procedure AddExternalUsesUnits(const aContext: TRemoveWithSymbolInventoryContext;
  var aInventory: TRemoveWithFactSet;
  const aExistingUnits, aExternalUnits: TDictionary<string, Byte>; const aUnits: TArray<string>;
  const aSourceUnitName, aFilePath: string);
var
  lExternalSymbol: TRemoveWithSymbolInfo;
  lUnitKey: string;
  lUnitName: string;
  lUsedUnit: string;
begin
  for lUsedUnit in aUnits do
  begin
    lUnitName := Trim(lUsedUnit);
    if lUnitName = '' then
      Continue;

    lUnitKey := aFilePath + '|' + lUnitName;
    if aExistingUnits.ContainsKey(lUnitName) or aExternalUnits.ContainsKey(lUnitKey) then
      Continue;
    aExternalUnits.Add(lUnitKey, 1);
    lExternalSymbol := Default(TRemoveWithSymbolInfo);
    lExternalSymbol.fName := lUnitName;
    lExternalSymbol.fUnitName := aSourceUnitName;
    lExternalSymbol.fFilePath := aFilePath;
    lExternalSymbol.fKind := TRemoveWithSymbolKind.rwskExternal;
    TRemoveWithSymbolBuilder.AddSymbol(aContext, aInventory, lExternalSymbol);
  end;
end;

procedure AddExternalUnitSymbolsFromProjectFacts(const aContext: TRemoveWithSymbolInventoryContext;
  const aProjectModel: TRemoveWithProjectModel;
  var aInventory: TRemoveWithFactSet);
var
  lExistingUnits: TDictionary<string, Byte>;
  lExternalUnits: TDictionary<string, Byte>;
  lModel: TDelphiSemanticUnitModel;
  lSymbol: TRemoveWithSymbolInfo;
  lUnitModel: TRemoveWithUnitModel;
begin
  lExistingUnits := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    lExternalUnits := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
    try
      for lSymbol in aInventory.fSymbols do
      begin
        if lSymbol.fKind = TRemoveWithSymbolKind.rwskUnitName then
          lExistingUnits.AddOrSetValue(lSymbol.fName, 1)
        else if lSymbol.fKind = TRemoveWithSymbolKind.rwskExternal then
          lExternalUnits.AddOrSetValue(lSymbol.fFilePath + '|' + lSymbol.fName, 1);
      end;

      for lUnitModel in aProjectModel.UnitModels do
        AddExternalUsesUnits(aContext, aInventory, lExistingUnits, lExternalUnits, lUnitModel.fUses,
          lUnitModel.fUnitName, lUnitModel.fFilePath);

      for lModel in aInventory.fDelphiSemanticUnitModels do
      begin
        AddExternalUsesUnits(aContext, aInventory, lExistingUnits, lExternalUnits, lModel.InterfaceUses,
          lModel.UnitName, lModel.FileName);
        AddExternalUsesUnits(aContext, aInventory, lExistingUnits, lExternalUnits, lModel.ImplementationUses,
          lModel.UnitName, lModel.FileName);
      end;
    finally
      lExternalUnits.Free;
    end;
  finally
    lExistingUnits.Free;
  end;
end;

function BuildRemoveWithFactSet(const aOptions: TAppOptions; out aInventory: TRemoveWithFactSet;
  out aError: string): Boolean;
var
  lPhaseMetrics: TRemoveWithFactSetPhaseMetrics;
begin
  Result := BuildRemoveWithFactSet(aOptions, aInventory, aError, lPhaseMetrics);
end;

function BuildRemoveWithFactSet(const aOptions: TAppOptions; out aInventory: TRemoveWithFactSet;
  out aError: string; out aPhaseMetrics: TRemoveWithFactSetPhaseMetrics): Boolean;
var
  lModel: TRemoveWithProjectModel;
begin
  lModel := nil;
  aPhaseMetrics := Default(TRemoveWithFactSetPhaseMetrics);
  if not BuildRemoveWithProjectModel(aOptions, aOptions.fDprojPath, lModel, aError) then
    Exit(False);
  try
    Result := BuildRemoveWithFactSet(aOptions, lModel, aInventory, aError, aPhaseMetrics);
  finally
    lModel.Free;
  end;
end;

function BuildRemoveWithFactSet(const aOptions: TAppOptions; const aProjectModel: TRemoveWithProjectModel;
  out aInventory: TRemoveWithFactSet; out aError: string): Boolean;
var
  lPhaseMetrics: TRemoveWithFactSetPhaseMetrics;
begin
  Result := BuildRemoveWithFactSet(aOptions, aProjectModel, aInventory, aError, lPhaseMetrics);
end;

function BuildRemoveWithFactSet(const aOptions: TAppOptions; const aProjectModel: TRemoveWithProjectModel;
  out aInventory: TRemoveWithFactSet; out aError: string;
  out aPhaseMetrics: TRemoveWithFactSetPhaseMetrics): Boolean;
begin
  Result := BuildRemoveWithFactSet(aOptions, aProjectModel, nil, aInventory,
    aError, aPhaseMetrics);
end;

function BuildRemoveWithFactSet(const aOptions: TAppOptions; const aProjectModel: TRemoveWithProjectModel;
  const aBodyAnalysisSourceFileNames: TArray<string>; out aInventory: TRemoveWithFactSet;
  out aError: string; out aPhaseMetrics: TRemoveWithFactSetPhaseMetrics): Boolean;
var
  lContext: TRemoveWithSymbolInventoryContext;
  lProblem: TProjectIndexer.TProblemInfo;
  lStopwatch: TStopwatch;
  lSymbol: TRemoveWithSymbolInfo;
  lUnitIndex: Integer;
  lUnitModel: TRemoveWithUnitModel;
begin
  aInventory := Default(TRemoveWithFactSet);
  aError := '';
  aPhaseMetrics := Default(TRemoveWithFactSetPhaseMetrics);

  if not Assigned(aProjectModel) then
  begin
    aError := 'Remove-with project model is not assigned.';
    Exit(False);
  end;
  aInventory.fParserDefines := aProjectModel.Context.fParserDefines;

  lContext := TRemoveWithSymbolInventoryContext.Create;
  try
    if not BuildProjectSemanticFacts(lContext, aOptions, aProjectModel,
      aBodyAnalysisSourceFileNames, aInventory, aPhaseMetrics, aError) then
      Exit(False);

    lUnitIndex := 0;
    for lUnitModel in aProjectModel.UnitModels do
    begin
      if (Trim(lUnitModel.fFilePath) = '') or (not SameText(TPath.GetExtension(lUnitModel.fFilePath), '.pas')) then
        Continue;
      Inc(lUnitIndex);
      LogRemoveWithSymbolProgress(aOptions, Format('model-unit start index=%d unit=%s path=%s',
        [lUnitIndex, lUnitModel.fUnitName, lUnitModel.fFilePath]));
      lStopwatch := TStopwatch.StartNew;
      lStopwatch.Stop;
      LogRemoveWithSymbolProgress(aOptions, Format('model-unit done index=%d elapsedMs=%d symbols=%d',
        [lUnitIndex, lStopwatch.ElapsedMilliseconds, Length(aInventory.fSymbols)]));
    end;

    LogRemoveWithSymbolProgress(aOptions, 'external-units start');
    lStopwatch := TStopwatch.StartNew;
    AddExternalUnitSymbolsFromProjectFacts(lContext, aProjectModel, aInventory);
    lStopwatch.Stop;
    aPhaseMetrics.fExternalUnitSymbolsMs := lStopwatch.ElapsedMilliseconds;
    LogRemoveWithSymbolProgress(aOptions, Format('external-units done elapsedMs=%d symbols=%d',
      [lStopwatch.ElapsedMilliseconds, Length(aInventory.fSymbols)]));

    LogRemoveWithSymbolProgress(aOptions, 'external-types start');
    lStopwatch := TStopwatch.StartNew;
    TRemoveWithSymbolBuilder.AddExternalTypeSymbols(lContext, aInventory);
    lStopwatch.Stop;
    aPhaseMetrics.fExternalTypeSymbolsMs := lStopwatch.ElapsedMilliseconds;
    LogRemoveWithSymbolProgress(aOptions, Format('external-types done elapsedMs=%d symbols=%d',
      [lStopwatch.ElapsedMilliseconds, Length(aInventory.fSymbols)]));

    lStopwatch := TStopwatch.StartNew;
    for lProblem in aProjectModel.Indexer.Problems do
    begin
      lSymbol := Default(TRemoveWithSymbolInfo);
      lSymbol.fName := TPath.GetFileNameWithoutExtension(lProblem.FileName);
      lSymbol.fFilePath := lProblem.FileName;
      lSymbol.fKind := TRemoveWithSymbolKind.rwskExternal;
      TRemoveWithSymbolBuilder.AddSymbol(lContext, aInventory, lSymbol);
    end;
    lStopwatch.Stop;
    aPhaseMetrics.fProblemSymbolAssemblyMs := lStopwatch.ElapsedMilliseconds;
  finally
    lContext.Free;
  end;
  Result := True;
end;

end.
