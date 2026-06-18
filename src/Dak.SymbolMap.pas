unit Dak.SymbolMap;

interface

uses
  Dak.Types;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
  Dak.ExitCodes, Dak.SymbolMap.Cache, Dak.SymbolMap.Context, Dak.SymbolMap.Indexer, Dak.SymbolMap.Query;

type
  TSymbolMapIndexedUnit = record
    fModel: TSymbolMapUnitModel;
    fStoreResult: TSymbolMapCacheStoreResult;
  end;

  TSymbolMapCommandState = record
    fCacheStatus: TSymbolMapCacheStatus;
    fCompilerProfile: TSymbolMapCompilerProfileResult;
    fContext: TSymbolMapContext;
    fIndexedUnits: TArray<TSymbolMapIndexedUnit>;
    fResultJson: string;
    fRtlSource: TSymbolMapRtlIndexResult;
  end;

function SymbolMapOperationToText(const aOperation: TSymbolMapOperation): string;
begin
  case aOperation of
    TSymbolMapOperation.smoIndex:
      Result := 'index';
    TSymbolMapOperation.smoFindDefinition:
      Result := 'find-definition';
    TSymbolMapOperation.smoFindReferences:
      Result := 'find-references';
    TSymbolMapOperation.smoSearchSymbols:
      Result := 'search-symbols';
    TSymbolMapOperation.smoDescribeSymbol:
      Result := 'describe-symbol';
    TSymbolMapOperation.smoStats:
      Result := 'stats';
  else
    Result := 'none';
  end;
end;

function JsonValueText(const aValue: TJSONValue): string;
begin
  try
    Result := aValue.ToJSON;
  finally
    aValue.Free;
  end;
end;

function BuildJsonStringArray(const aValues: TArray<string>): TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(aValues) do
    Result.Add(aValues[i]);
end;

function BuildJsonArrayFromTextOrEmpty(const aJson: string): TJSONArray;
var
  lValue: TJSONValue;
begin
  lValue := TJSONObject.ParseJSONValue(aJson);
  if lValue is TJSONArray then
    Exit(TJSONArray(lValue));

  lValue.Free;
  Result := TJSONArray.Create;
end;

function BuildJsonObjectFromTextOrEmpty(const aJson: string): TJSONObject;
var
  lValue: TJSONValue;
begin
  lValue := TJSONObject.ParseJSONValue(aJson);
  if lValue is TJSONObject then
    Exit(TJSONObject(lValue));

  lValue.Free;
  Result := TJSONObject.Create;
end;

function SymbolMapUseNames(const aModel: TSymbolMapUnitModel; const aSectionKind: string): TArray<string>;
var
  i: Integer;
  lIndex: Integer;
begin
  SetLength(Result, 0);
  for i := 0 to High(aModel.fUses) do
  begin
    if not SameText(aModel.fUses[i].fSectionKind, aSectionKind) then
      Continue;
    lIndex := Length(Result);
    SetLength(Result, lIndex + 1);
    Result[lIndex] := aModel.fUses[i].fUnitName;
  end;
end;

function BuildSymbolMapSymbolObject(const aSymbol: TSymbolMapSymbolModel): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', aSymbol.fName);
  Result.AddPair('kind', aSymbol.fKind);
  Result.AddPair('unitName', aSymbol.fUnitName);
  Result.AddPair('filePath', aSymbol.fFilePath);
  Result.AddPair('ownerName', aSymbol.fOwnerName);
  Result.AddPair('typeName', aSymbol.fTypeName);
  Result.AddPair('signature', aSymbol.fSignature);
  Result.AddPair('sectionKind', aSymbol.fSectionKind);
  Result.AddPair('line', TJSONNumber.Create(aSymbol.fLine));
  Result.AddPair('col', TJSONNumber.Create(aSymbol.fCol));
  Result.AddPair('endLine', TJSONNumber.Create(aSymbol.fEndLine));
  Result.AddPair('endCol', TJSONNumber.Create(aSymbol.fEndCol));
end;

function BuildSymbolMapSymbolsArray(const aSymbols: TArray<TSymbolMapSymbolModel>): TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(aSymbols) do
    Result.AddElement(BuildSymbolMapSymbolObject(aSymbols[i]));
end;

function BuildSymbolMapMemberObject(const aMember: TSymbolMapMemberModel): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('ownerName', aMember.fOwnerName);
  Result.AddPair('memberName', aMember.fMemberName);
  Result.AddPair('kind', aMember.fKind);
  Result.AddPair('typeName', aMember.fTypeName);
  Result.AddPair('visibility', aMember.fVisibility);
  Result.AddPair('signature', aMember.fSignature);
  Result.AddPair('isDefault', TJSONBool.Create(aMember.fIsDefault));
  Result.AddPair('isIndexed', TJSONBool.Create(aMember.fIsIndexed));
  Result.AddPair('line', TJSONNumber.Create(aMember.fLine));
  Result.AddPair('col', TJSONNumber.Create(aMember.fCol));
  Result.AddPair('endLine', TJSONNumber.Create(aMember.fEndLine));
  Result.AddPair('endCol', TJSONNumber.Create(aMember.fEndCol));
end;

function BuildSymbolMapMembersArray(const aMembers: TArray<TSymbolMapMemberModel>): TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(aMembers) do
    Result.AddElement(BuildSymbolMapMemberObject(aMembers[i]));
end;

function BuildSymbolMapIndexedUnitObject(const aUnit: TSymbolMapIndexedUnit): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('unitName', aUnit.fModel.fUnitName);
  Result.AddPair('filePath', aUnit.fModel.fFilePath);
  Result.AddPair('encoding', aUnit.fModel.fEncodingName);
  Result.AddPair('unitCacheKey', aUnit.fStoreResult.fUnitCacheKey);
  Result.AddPair('fileHash', aUnit.fStoreResult.fFileHash);
  Result.AddPair('contextHash', aUnit.fStoreResult.fContextHash);
  Result.AddPair('centralCacheHit', TJSONBool.Create(aUnit.fStoreResult.fCacheHit));
  Result.AddPair('parseAvoided', TJSONBool.Create(aUnit.fStoreResult.fParseAvoided));
  Result.AddPair('usesCount', TJSONNumber.Create(Length(aUnit.fModel.fUses)));
  Result.AddPair('symbolCount', TJSONNumber.Create(Length(aUnit.fModel.fSymbols)));
  Result.AddPair('memberCount', TJSONNumber.Create(Length(aUnit.fModel.fMembers)));
  Result.AddPair('interfaceUses', BuildJsonStringArray(SymbolMapUseNames(aUnit.fModel,
    'interface')));
  Result.AddPair('implementationUses', BuildJsonStringArray(SymbolMapUseNames(aUnit.fModel,
    'implementation')));
  Result.AddPair('symbols', BuildSymbolMapSymbolsArray(aUnit.fModel.fSymbols));
  Result.AddPair('members', BuildSymbolMapMembersArray(aUnit.fModel.fMembers));
  Result.AddPair('diagnostics', BuildJsonStringArray(aUnit.fModel.fDiagnostics));
end;

function BuildIndexResultJson(const aUnits: TArray<TSymbolMapIndexedUnit>): string;
var
  i: Integer;
  lHits: Integer;
  lIndexedUnits: TJSONArray;
  lMembers: Integer;
  lMisses: Integer;
  lRoot: TJSONObject;
  lSymbols: Integer;
begin
  lHits := 0;
  lMisses := 0;
  lSymbols := 0;
  lMembers := 0;
  lRoot := TJSONObject.Create;
  lIndexedUnits := TJSONArray.Create;
  lRoot.AddPair('unitCount', TJSONNumber.Create(Length(aUnits)));
  lRoot.AddPair('fatalDiagnostics', TJSONNumber.Create(0));
  for i := 0 to High(aUnits) do
  begin
    if aUnits[i].fStoreResult.fCacheHit then
      Inc(lHits)
    else
      Inc(lMisses);
    Inc(lSymbols, Length(aUnits[i].fModel.fSymbols));
    Inc(lMembers, Length(aUnits[i].fModel.fMembers));
    lIndexedUnits.AddElement(BuildSymbolMapIndexedUnitObject(aUnits[i]));
  end;
  lRoot.AddPair('indexedUnits', lIndexedUnits);
  lRoot.AddPair('symbolCount', TJSONNumber.Create(lSymbols));
  lRoot.AddPair('memberCount', TJSONNumber.Create(lMembers));
  lRoot.AddPair('centralCacheHits', TJSONNumber.Create(lHits));
  lRoot.AddPair('centralCacheMisses', TJSONNumber.Create(lMisses));
  Result := JsonValueText(lRoot);
end;

function BuildSymbolMapDefinitionObject(const aDefinition: TSymbolMapDefinition): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('found', TJSONBool.Create(aDefinition.fFound));
  Result.AddPair('name', aDefinition.fName);
  Result.AddPair('kind', aDefinition.fKind);
  Result.AddPair('ownerName', aDefinition.fOwnerName);
  Result.AddPair('unitName', aDefinition.fUnitName);
  Result.AddPair('filePath', aDefinition.fFilePath);
  Result.AddPair('sourceKind', aDefinition.fSourceKind);
  Result.AddPair('confidence', aDefinition.fConfidence);
  Result.AddPair('signature', aDefinition.fSignature);
  Result.AddPair('typeName', aDefinition.fTypeName);
  Result.AddPair('line', TJSONNumber.Create(aDefinition.fLine));
  Result.AddPair('col', TJSONNumber.Create(aDefinition.fCol));
  Result.AddPair('endLine', TJSONNumber.Create(aDefinition.fEndLine));
  Result.AddPair('endCol', TJSONNumber.Create(aDefinition.fEndCol));
end;

function BuildSymbolMapDefinitionsArray(const aDefinitions: TArray<TSymbolMapDefinition>):
  TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(aDefinitions) do
    Result.AddElement(BuildSymbolMapDefinitionObject(aDefinitions[i]));
end;

function BuildDefinitionResultJson(const aDefinition: TSymbolMapDefinition): string;
var
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  lRoot.AddPair('definition', BuildSymbolMapDefinitionObject(aDefinition));
  Result := JsonValueText(lRoot);
end;

function BuildSearchResultJson(const aQuery: string; const aDefinitions: TArray<TSymbolMapDefinition>): string;
var
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  lRoot.AddPair('query', aQuery);
  lRoot.AddPair('count', TJSONNumber.Create(Length(aDefinitions)));
  lRoot.AddPair('definitions', BuildSymbolMapDefinitionsArray(aDefinitions));
  Result := JsonValueText(lRoot);
end;

function BuildSymbolMapReferenceObject(const aReference: TSymbolMapReference): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', aReference.fName);
  Result.AddPair('unitName', aReference.fUnitName);
  Result.AddPair('filePath', aReference.fFilePath);
  Result.AddPair('sourceKind', aReference.fSourceKind);
  Result.AddPair('confidence', aReference.fConfidence);
  Result.AddPair('role', aReference.fRole);
  Result.AddPair('sectionKind', aReference.fSectionKind);
  Result.AddPair('line', TJSONNumber.Create(aReference.fLine));
  Result.AddPair('col', TJSONNumber.Create(aReference.fCol));
  Result.AddPair('endLine', TJSONNumber.Create(aReference.fEndLine));
  Result.AddPair('endCol', TJSONNumber.Create(aReference.fEndCol));
end;

function BuildSymbolMapReferencesArray(const aReferences: TArray<TSymbolMapReference>):
  TJSONArray;
var
  i: Integer;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(aReferences) do
    Result.AddElement(BuildSymbolMapReferenceObject(aReferences[i]));
end;

function BuildReferencesResultJson(const aSymbol: string; const aReferences: TArray<TSymbolMapReference>): string;
var
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  lRoot.AddPair('symbol', aSymbol);
  lRoot.AddPair('count', TJSONNumber.Create(Length(aReferences)));
  lRoot.AddPair('references', BuildSymbolMapReferencesArray(aReferences));
  Result := JsonValueText(lRoot);
end;

function BuildCompilerProfileObject(
  const aCompilerProfile: TSymbolMapCompilerProfileResult): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('profileKey', aCompilerProfile.fProfileKey);
  Result.AddPair('delphiVersion', aCompilerProfile.fDelphiVersion);
  Result.AddPair('platform', aCompilerProfile.fPlatform);
  Result.AddPair('intrinsicSeedVersion', aCompilerProfile.fIntrinsicSeedVersion);
  Result.AddPair('syntheticIntrinsicCount',
    TJSONNumber.Create(aCompilerProfile.fIntrinsicCount));
  Result.AddPair('cacheHit', TJSONBool.Create(aCompilerProfile.fCacheHit));
end;

function BuildRtlSourceObject(const aRtlSource: TSymbolMapRtlIndexResult): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', aRtlSource.fStatus);
  Result.AddPair('sourceRoot', aRtlSource.fSourceRoot);
  Result.AddPair('unitsDiscovered', TJSONNumber.Create(aRtlSource.fUnitsDiscovered));
  Result.AddPair('unitsIndexed', TJSONNumber.Create(aRtlSource.fUnitsIndexed));
  Result.AddPair('cacheHit', TJSONBool.Create(aRtlSource.fCacheHit));
  Result.AddPair('unitCacheHits', TJSONNumber.Create(aRtlSource.fUnitCacheHits));
  Result.AddPair('unitCacheMisses', TJSONNumber.Create(aRtlSource.fUnitCacheMisses));
  Result.AddPair('diagnosticsCount', TJSONNumber.Create(aRtlSource.fDiagnosticsCount));
  Result.AddPair('diagnostics', BuildJsonArrayFromTextOrEmpty(aRtlSource.fDiagnosticsJson));
end;

procedure WriteSymbolMapJsonShell(const aOptions: TAppOptions; const aContext: TSymbolMapContext;
  const aCacheStatus: TSymbolMapCacheStatus; const aCompilerProfile: TSymbolMapCompilerProfileResult;
  const aRtlSource: TSymbolMapRtlIndexResult; const aResultJson, aDiagnosticsJson: string);
var
  lCacheObject: TJSONObject;
  lContextObject: TJSONObject;
  lOperation: string;
  lProjectObject: TJSONObject;
  lRoot: TJSONObject;
  lTimingsObject: TJSONObject;
begin
  lOperation := SymbolMapOperationToText(aOptions.fSymbolMapOperation);

  lProjectObject := TJSONObject.Create;
  lProjectObject.AddPair('path', aContext.fProject.ProjectPath);
  lProjectObject.AddPair('name', aContext.fProject.ProjectName);
  lProjectObject.AddPair('dir', aContext.fProject.ProjectDir);
  lProjectObject.AddPair('mainSource', aContext.fProject.MainSourcePath);
  lProjectObject.AddPair('platform', aContext.fPlatform);
  lProjectObject.AddPair('config', aContext.fConfig);

  lCacheObject := TJSONObject.Create;
  lCacheObject.AddPair('centralRoot', aContext.fCentralCacheRoot);
  lCacheObject.AddPair('projectRoot', aContext.fProjectCacheRoot);
  lCacheObject.AddPair('centralDbPath', aCacheStatus.fCentralDbPath);
  lCacheObject.AddPair('projectDbPath', aCacheStatus.fProjectDbPath);
  lCacheObject.AddPair('schemaVersion', TJSONNumber.Create(aCacheStatus.fSchemaVersion));
  lCacheObject.AddPair('centralCreated', TJSONBool.Create(aCacheStatus.fCentralCreated));
  lCacheObject.AddPair('projectCreated', TJSONBool.Create(aCacheStatus.fProjectCreated));

  lContextObject := TJSONObject.Create;
  lContextObject.AddPair('delphiVersion', aContext.fDelphiVersion);
  lContextObject.AddPair('contextMode',
    ProjectAnalysisContextQualityToText(aContext.fProject.Quality));
  lContextObject.AddPair('contextNote', aContext.fProject.ContextNote);
  lContextObject.AddPair('hasDelphiContext',
    TJSONBool.Create(aContext.fProject.HasDelphiContext));
  lContextObject.AddPair('parserDefines', aContext.fProject.ParserDefines);
  lContextObject.AddPair('parserSearchPath', aContext.fProject.ParserSearchPath);
  lContextObject.AddPair('hasCompilerParams', TJSONBool.Create(aContext.fHasCompilerParams));
  lContextObject.AddPair('defines', BuildJsonStringArray(aContext.fDefines));
  lContextObject.AddPair('unitSearchPath', BuildJsonStringArray(aContext.fUnitSearchPath));
  lContextObject.AddPair('libraryPath', BuildJsonStringArray(aContext.fLibraryPath));
  lContextObject.AddPair('unitScopes', BuildJsonStringArray(aContext.fUnitScopes));
  lContextObject.AddPair('unitAliases', BuildJsonStringArray(aContext.fUnitAliases));
  lContextObject.AddPair('rtlSourceRoot', aContext.fRtlSourceRoot);

  lTimingsObject := TJSONObject.Create;
  lTimingsObject.AddPair('totalMs', TJSONNumber.Create(0));

  lRoot := TJSONObject.Create;
  lRoot.AddPair('operation', lOperation);
  lRoot.AddPair('status', 'ok');
  lRoot.AddPair('project', lProjectObject);
  lRoot.AddPair('cache', lCacheObject);
  lRoot.AddPair('context', lContextObject);
  lRoot.AddPair('compilerProfile', BuildCompilerProfileObject(aCompilerProfile));
  lRoot.AddPair('rtlSource', BuildRtlSourceObject(aRtlSource));
  lRoot.AddPair('query', TJSONObject.Create);
  lRoot.AddPair('result', BuildJsonObjectFromTextOrEmpty(aResultJson));
  lRoot.AddPair('diagnostics', BuildJsonArrayFromTextOrEmpty(aDiagnosticsJson));
  lRoot.AddPair('timings', lTimingsObject);
  WriteLn(JsonValueText(lRoot));
end;

procedure WriteSymbolMapTextShell(const aOptions: TAppOptions; const aContext: TSymbolMapContext;
  const aCacheStatus: TSymbolMapCacheStatus; const aCompilerProfile: TSymbolMapCompilerProfileResult;
  const aRtlSource: TSymbolMapRtlIndexResult; const aIndexedUnits: TArray<TSymbolMapIndexedUnit>);
var
  lUnit: TSymbolMapIndexedUnit;
begin
  WriteLn('symbol-map ', SymbolMapOperationToText(aOptions.fSymbolMapOperation), ': ok');
  WriteLn('project: ', aContext.fProject.ProjectPath);
  WriteLn('context-mode: ', ProjectAnalysisContextQualityToText(aContext.fProject.Quality));
  if aContext.fProject.ContextNote <> '' then
    WriteLn('context-note: ', aContext.fProject.ContextNote);
  WriteLn('central-cache-root: ', aContext.fCentralCacheRoot);
  WriteLn('project-cache-root: ', aContext.fProjectCacheRoot);
  WriteLn('central-cache-db: ', aCacheStatus.fCentralDbPath);
  WriteLn('project-cache-db: ', aCacheStatus.fProjectDbPath);
  WriteLn('schema-version: ', aCacheStatus.fSchemaVersion);
  WriteLn('compiler-profile-key: ', aCompilerProfile.fProfileKey);
  WriteLn('compiler-profile-hit: ', LowerCase(BoolToStr(aCompilerProfile.fCacheHit, True)));
  WriteLn('synthetic-intrinsic-count: ', aCompilerProfile.fIntrinsicCount);
  WriteLn('rtl-source-status: ', aRtlSource.fStatus);
  WriteLn('rtl-source-root: ', aRtlSource.fSourceRoot);
  WriteLn('rtl-units-indexed: ', aRtlSource.fUnitsIndexed);
  WriteLn('rtl-unit-cache-hits: ', aRtlSource.fUnitCacheHits);
  WriteLn('rtl-unit-cache-misses: ', aRtlSource.fUnitCacheMisses);
  WriteLn('indexed-units: ', Length(aIndexedUnits));
  for lUnit in aIndexedUnits do
  begin
    WriteLn('indexed-unit: ', lUnit.fModel.fUnitName);
    WriteLn('unit-cache-key: ', lUnit.fStoreResult.fUnitCacheKey);
    WriteLn('central-cache-hit: ', LowerCase(BoolToStr(lUnit.fStoreResult.fCacheHit, True)));
    WriteLn('parse-avoided: ', LowerCase(BoolToStr(lUnit.fStoreResult.fParseAvoided, True)));
  end;
end;

function TryIndexSymbolMapUnit(const aContext: TSymbolMapContext; const aCacheStatus: TSymbolMapCacheStatus;
  const aUnitPath: string; const aForceRefresh: Boolean; out aIndexedUnit: TSymbolMapIndexedUnit;
  out aError: string): Boolean;
var
  lFound: Boolean;
  lUnitPath: string;
begin
  Result := False;
  aIndexedUnit := Default(TSymbolMapIndexedUnit);
  lUnitPath := TPath.GetFullPath(aUnitPath);
  if not aForceRefresh then
  begin
    if not TryLoadSymbolMapUnitProjection(aContext, aCacheStatus, lUnitPath, True,
      aIndexedUnit.fModel, aIndexedUnit.fStoreResult, lFound, aError) then
      Exit(False);
    if lFound then
      Exit(True);
  end;

  if not TryExtractSymbolMapUnitModel(lUnitPath, aIndexedUnit.fModel, aError) then
    Exit(False);
  if not StoreSymbolMapUnitProjection(aContext, aCacheStatus, aIndexedUnit.fModel, aForceRefresh,
    aIndexedUnit.fStoreResult, aError) then
    Exit(False);
  Result := True;
end;

procedure AddIndexedUnit(var aUnits: TArray<TSymbolMapIndexedUnit>; const aUnit: TSymbolMapIndexedUnit); forward;

function TryIndexSymbolMapProject(const aContext: TSymbolMapContext; const aCacheStatus: TSymbolMapCacheStatus;
  const aForceRefresh: Boolean; var aIndexedUnits: TArray<TSymbolMapIndexedUnit>; out aError: string): Boolean;
var
  i: Integer;
  lIndexedUnit: TSymbolMapIndexedUnit;
  lKnownResults: TArray<TSymbolMapCacheStoreResult>;
  lModels: TArray<TSymbolMapUnitModel>;
  lStoreResults: TArray<TSymbolMapCacheStoreResult>;
begin
  Result := False;
  if not TryBuildSymbolMapUnitModelsFromDelphiSemanticProjectIndex(aContext, False, lModels, aError) then
    Exit(False);
  SetLength(lKnownResults, Length(lModels));
  if not StoreSymbolMapProjectProjection(aContext, aCacheStatus, lModels, lKnownResults, aForceRefresh,
    lStoreResults, aError) then
    Exit(False);
  for i := 0 to High(lModels) do
  begin
    lIndexedUnit := Default(TSymbolMapIndexedUnit);
    lIndexedUnit.fModel := lModels[i];
    lIndexedUnit.fStoreResult := lStoreResults[i];
    AddIndexedUnit(aIndexedUnits, lIndexedUnit);
  end;
  Result := True;
end;

function EnsureSymbolMapProjectIndexedForQuery(const aContext: TSymbolMapContext;
  const aCacheStatus: TSymbolMapCacheStatus; var aIndexedUnits: TArray<TSymbolMapIndexedUnit>;
  out aError: string): Boolean;
begin
  Result := TryIndexSymbolMapProject(aContext, aCacheStatus, False, aIndexedUnits, aError);
end;

procedure AddIndexedUnit(var aUnits: TArray<TSymbolMapIndexedUnit>; const aUnit: TSymbolMapIndexedUnit);
var
  lIndex: Integer;
begin
  lIndex := Length(aUnits);
  SetLength(aUnits, lIndex + 1);
  aUnits[lIndex] := aUnit;
end;

function PrepareSymbolMapCommand(const aOptions: TAppOptions; out aState: TSymbolMapCommandState;
  out aError: string; out aExitCode: Integer): Boolean;
begin
  Result := False;
  aState := Default(TSymbolMapCommandState);
  SetLength(aState.fIndexedUnits, 0);
  aState.fResultJson := '{}';
  aState.fRtlSource := Default(TSymbolMapRtlIndexResult);
  aState.fRtlSource.fStatus := 'not-indexed';
  aState.fRtlSource.fDiagnosticsJson := '[]';
  aExitCode := cExitToolFailure;

  if not TryBuildSymbolMapContext(aOptions, aState.fContext, aError) then
  begin
    aExitCode := cExitInvalidProjectInput;
    Exit(False);
  end;
  if not EnsureSymbolMapCaches(aState.fContext, aState.fCacheStatus, aError) then
    Exit(False);
  if not EnsureSymbolMapCompilerProfile(aState.fContext, aState.fCacheStatus,
    aState.fCompilerProfile, aError) then
    Exit(False);
  Result := True;
end;

function RunSymbolMapIndexOperation(const aOptions: TAppOptions; var aState: TSymbolMapCommandState;
  out aError: string): Boolean;
var
  lIndexedUnit: TSymbolMapIndexedUnit;
begin
  Result := False;
  if aOptions.fSymbolMapUnitPath = '' then
  begin
    if not IndexSymbolMapRtlSources(aState.fContext, aState.fCacheStatus, '',
      aState.fCompilerProfile, aState.fRtlSource, aError) then
      Exit(False);
    if not TryIndexSymbolMapProject(aState.fContext, aState.fCacheStatus,
      aOptions.fSymbolMapRefresh = TSymbolMapRefresh.smrForce, aState.fIndexedUnits, aError) then
      Exit(False);
    aState.fResultJson := BuildIndexResultJson(aState.fIndexedUnits);
    Exit(True);
  end;

  if not TryIndexSymbolMapUnit(aState.fContext, aState.fCacheStatus, aOptions.fSymbolMapUnitPath,
    aOptions.fSymbolMapRefresh = TSymbolMapRefresh.smrForce, lIndexedUnit, aError) then
    Exit(False);
  AddIndexedUnit(aState.fIndexedUnits, lIndexedUnit);
  aState.fResultJson := BuildIndexResultJson(aState.fIndexedUnits);
  Result := True;
end;

function RunSymbolMapFindDefinition(const aOptions: TAppOptions; var aState: TSymbolMapCommandState;
  out aError: string): Boolean;
var
  lDefinition: TSymbolMapDefinition;
begin
  Result := FindSymbolMapDefinitionByPosition(aState.fContext, aState.fCacheStatus,
    aState.fCompilerProfile, aOptions.fSymbolMapFilePath, aOptions.fSymbolMapLine,
    aOptions.fSymbolMapCol, lDefinition, aError);
  if Result then
    aState.fResultJson := BuildDefinitionResultJson(lDefinition);
end;

function RunSymbolMapFindReferences(const aOptions: TAppOptions; var aState: TSymbolMapCommandState;
  out aError: string): Boolean;
var
  lReferences: TArray<TSymbolMapReference>;
  lSymbol: string;
begin
  lSymbol := aOptions.fSymbolMapSymbol;
  if aOptions.fSymbolMapFilePath <> '' then
  begin
    Result := FindSymbolMapReferencesByPosition(aState.fContext, aOptions.fSymbolMapFilePath,
      aOptions.fSymbolMapLine, aOptions.fSymbolMapCol, aOptions.fSymbolMapLimit,
      lSymbol, lReferences, aError);
  end else
  begin
    Result := FindSymbolMapReferences(aState.fContext, aState.fCacheStatus,
      aState.fCompilerProfile, lSymbol, aOptions.fSymbolMapLimit, lReferences, aError);
  end;
  if Result then
    aState.fResultJson := BuildReferencesResultJson(lSymbol, lReferences);
end;

function RunSymbolMapSearchSymbols(const aOptions: TAppOptions; var aState: TSymbolMapCommandState;
  out aError: string): Boolean;
var
  lDefinitions: TArray<TSymbolMapDefinition>;
begin
  Result := SearchSymbolMapDefinitions(aState.fContext, aState.fCacheStatus,
    aState.fCompilerProfile, aOptions.fSymbolMapQuery, aOptions.fSymbolMapLimit, lDefinitions, aError);
  if Result then
    aState.fResultJson := BuildSearchResultJson(aOptions.fSymbolMapQuery, lDefinitions);
end;

function RunSymbolMapDescribeSymbol(const aOptions: TAppOptions; var aState: TSymbolMapCommandState;
  out aError: string): Boolean;
var
  lDefinition: TSymbolMapDefinition;
begin
  Result := DescribeSymbolMapDefinition(aState.fContext, aState.fCacheStatus,
    aState.fCompilerProfile, aOptions.fSymbolMapSymbol, aOptions.fSymbolMapOwner, lDefinition, aError);
  if Result then
    aState.fResultJson := BuildDefinitionResultJson(lDefinition);
end;

function RunSymbolMapStatsOperation(var aState: TSymbolMapCommandState): Boolean;
begin
  aState.fResultJson := '{}';
  Result := True;
end;

function RunSymbolMapQueryOperation(const aOptions: TAppOptions; var aState: TSymbolMapCommandState;
  out aError: string): Boolean;
begin
  Result := False;
  if not EnsureSymbolMapProjectIndexedForQuery(aState.fContext, aState.fCacheStatus,
    aState.fIndexedUnits, aError) then
    Exit(False);

  case aOptions.fSymbolMapOperation of
    TSymbolMapOperation.smoFindDefinition:
      Result := RunSymbolMapFindDefinition(aOptions, aState, aError);
    TSymbolMapOperation.smoFindReferences:
      Result := RunSymbolMapFindReferences(aOptions, aState, aError);
    TSymbolMapOperation.smoSearchSymbols:
      Result := RunSymbolMapSearchSymbols(aOptions, aState, aError);
    TSymbolMapOperation.smoDescribeSymbol:
      Result := RunSymbolMapDescribeSymbol(aOptions, aState, aError);
  else
    Result := True;
  end;
end;

function RunSymbolMapOperation(const aOptions: TAppOptions; var aState: TSymbolMapCommandState;
  out aError: string): Boolean;
begin
  case aOptions.fSymbolMapOperation of
    TSymbolMapOperation.smoIndex:
      Result := RunSymbolMapIndexOperation(aOptions, aState, aError);
    TSymbolMapOperation.smoStats:
      Result := RunSymbolMapStatsOperation(aState);
    TSymbolMapOperation.smoFindDefinition, TSymbolMapOperation.smoFindReferences,
      TSymbolMapOperation.smoSearchSymbols, TSymbolMapOperation.smoDescribeSymbol:
      Result := RunSymbolMapQueryOperation(aOptions, aState, aError);
  else
    Result := True;
  end;
end;

procedure WriteSymbolMapCommandOutput(const aOptions: TAppOptions; const aState: TSymbolMapCommandState);
begin
  if aOptions.fSymbolMapFormat = TSymbolMapFormat.smfText then
    WriteSymbolMapTextShell(aOptions, aState.fContext, aState.fCacheStatus,
      aState.fCompilerProfile, aState.fRtlSource, aState.fIndexedUnits)
  else
    WriteSymbolMapJsonShell(aOptions, aState.fContext, aState.fCacheStatus,
      aState.fCompilerProfile, aState.fRtlSource, aState.fResultJson, '[]');
end;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;
var
  lError: string;
  lExitCode: Integer;
  lState: TSymbolMapCommandState;
begin
  if not PrepareSymbolMapCommand(aOptions, lState, lError, lExitCode) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(lExitCode);
  end;
  if not RunSymbolMapOperation(aOptions, lState, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitToolFailure);
  end;

  WriteSymbolMapCommandOutput(aOptions, lState);
  Result := cExitSuccess;
end;

end.
