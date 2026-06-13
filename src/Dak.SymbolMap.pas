unit Dak.SymbolMap;

interface

uses
  Dak.Types;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.IOUtils, System.SysUtils,
  Dak.ExitCodes, Dak.SymbolMap.Cache, Dak.SymbolMap.Context, Dak.SymbolMap.Indexer, Dak.SymbolMap.Query;

type
  TSymbolMapIndexedUnit = record
    fModel: TSymbolMapUnitModel;
    fStoreResult: TSymbolMapCacheStoreResult;
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

function JsonEscape(const aValue: string): string;
var
  ch: Char;
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(aValue) do
  begin
    ch := aValue[i];
    case ch of
      '"':
        Result := Result + '\"';
      '\':
        Result := Result + '\\';
      #8:
        Result := Result + '\b';
      #9:
        Result := Result + '\t';
      #10:
        Result := Result + '\n';
      #12:
        Result := Result + '\f';
      #13:
        Result := Result + '\r';
    else
      if Ord(ch) < 32 then
        Result := Result + '\u' + IntToHex(Ord(ch), 4)
      else
        Result := Result + ch;
    end;
  end;
end;

function JsonStringArray(const aValues: TArray<string>): string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to High(aValues) do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + '"' + JsonEscape(aValues[i]) + '"';
  end;
  Result := Result + ']';
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

function SymbolMapDiagnosticsJson(const aValues: TArray<string>): string;
begin
  Result := JsonStringArray(aValues);
end;

function SymbolMapSymbolsJson(const aSymbols: TArray<TSymbolMapSymbolModel>): string;
var
  i: Integer;
  lSymbol: TSymbolMapSymbolModel;
begin
  Result := '[';
  for i := 0 to High(aSymbols) do
  begin
    if i > 0 then
      Result := Result + ',';
    lSymbol := aSymbols[i];
    Result := Result + '{' +
      '"name":"' + JsonEscape(lSymbol.fName) + '",' +
      '"kind":"' + JsonEscape(lSymbol.fKind) + '",' +
      '"unitName":"' + JsonEscape(lSymbol.fUnitName) + '",' +
      '"filePath":"' + JsonEscape(lSymbol.fFilePath) + '",' +
      '"ownerName":"' + JsonEscape(lSymbol.fOwnerName) + '",' +
      '"typeName":"' + JsonEscape(lSymbol.fTypeName) + '",' +
      '"signature":"' + JsonEscape(lSymbol.fSignature) + '",' +
      '"sectionKind":"' + JsonEscape(lSymbol.fSectionKind) + '",' +
      '"line":' + lSymbol.fLine.ToString + ',' +
      '"col":' + lSymbol.fCol.ToString + ',' +
      '"endLine":' + lSymbol.fEndLine.ToString + ',' +
      '"endCol":' + lSymbol.fEndCol.ToString +
      '}';
  end;
  Result := Result + ']';
end;

function SymbolMapMembersJson(const aMembers: TArray<TSymbolMapMemberModel>): string;
var
  i: Integer;
  lMember: TSymbolMapMemberModel;
begin
  Result := '[';
  for i := 0 to High(aMembers) do
  begin
    if i > 0 then
      Result := Result + ',';
    lMember := aMembers[i];
    Result := Result + '{' +
      '"ownerName":"' + JsonEscape(lMember.fOwnerName) + '",' +
      '"memberName":"' + JsonEscape(lMember.fMemberName) + '",' +
      '"kind":"' + JsonEscape(lMember.fKind) + '",' +
      '"typeName":"' + JsonEscape(lMember.fTypeName) + '",' +
      '"visibility":"' + JsonEscape(lMember.fVisibility) + '",' +
      '"signature":"' + JsonEscape(lMember.fSignature) + '",' +
      '"isDefault":' + LowerCase(BoolToStr(lMember.fIsDefault, True)) + ',' +
      '"isIndexed":' + LowerCase(BoolToStr(lMember.fIsIndexed, True)) + ',' +
      '"line":' + lMember.fLine.ToString + ',' +
      '"col":' + lMember.fCol.ToString + ',' +
      '"endLine":' + lMember.fEndLine.ToString + ',' +
      '"endCol":' + lMember.fEndCol.ToString +
      '}';
  end;
  Result := Result + ']';
end;

function SymbolMapIndexedUnitJson(const aUnit: TSymbolMapIndexedUnit): string;
begin
  Result := '{"unitName":"' + JsonEscape(aUnit.fModel.fUnitName) + '",' +
    '"filePath":"' + JsonEscape(aUnit.fModel.fFilePath) + '",' +
    '"encoding":"' + JsonEscape(aUnit.fModel.fEncodingName) + '",' +
    '"unitCacheKey":"' + JsonEscape(aUnit.fStoreResult.fUnitCacheKey) + '",' +
    '"fileHash":"' + JsonEscape(aUnit.fStoreResult.fFileHash) + '",' +
    '"contextHash":"' + JsonEscape(aUnit.fStoreResult.fContextHash) + '",' +
    '"centralCacheHit":' + LowerCase(BoolToStr(aUnit.fStoreResult.fCacheHit, True)) + ',' +
    '"usesCount":' + Length(aUnit.fModel.fUses).ToString + ',' +
    '"symbolCount":' + Length(aUnit.fModel.fSymbols).ToString + ',' +
    '"memberCount":' + Length(aUnit.fModel.fMembers).ToString + ',' +
    '"interfaceUses":' + JsonStringArray(SymbolMapUseNames(aUnit.fModel, 'interface')) + ',' +
    '"implementationUses":' + JsonStringArray(SymbolMapUseNames(aUnit.fModel, 'implementation')) + ',' +
    '"symbols":' + SymbolMapSymbolsJson(aUnit.fModel.fSymbols) + ',' +
    '"members":' + SymbolMapMembersJson(aUnit.fModel.fMembers) + ',' +
    '"diagnostics":' + SymbolMapDiagnosticsJson(aUnit.fModel.fDiagnostics) +
    '}';
end;

function BuildIndexResultJson(const aUnits: TArray<TSymbolMapIndexedUnit>): string;
var
  i: Integer;
  lHits: Integer;
  lMembers: Integer;
  lMisses: Integer;
  lSymbols: Integer;
begin
  lHits := 0;
  lMisses := 0;
  lSymbols := 0;
  lMembers := 0;
  Result := '{"unitCount":' + Length(aUnits).ToString + ',"fatalDiagnostics":0,"indexedUnits":[';
  for i := 0 to High(aUnits) do
  begin
    if i > 0 then
      Result := Result + ',';
    if aUnits[i].fStoreResult.fCacheHit then
      Inc(lHits)
    else
      Inc(lMisses);
    Inc(lSymbols, Length(aUnits[i].fModel.fSymbols));
    Inc(lMembers, Length(aUnits[i].fModel.fMembers));
    Result := Result + SymbolMapIndexedUnitJson(aUnits[i]);
  end;
  Result := Result + '],"symbolCount":' + lSymbols.ToString + ',"memberCount":' + lMembers.ToString +
    ',"centralCacheHits":' + lHits.ToString + ',"centralCacheMisses":' + lMisses.ToString + '}';
end;

function SymbolMapDefinitionJson(const aDefinition: TSymbolMapDefinition): string;
begin
  Result := '{"found":' + LowerCase(BoolToStr(aDefinition.fFound, True)) + ',' +
    '"name":"' + JsonEscape(aDefinition.fName) + '",' +
    '"kind":"' + JsonEscape(aDefinition.fKind) + '",' +
    '"ownerName":"' + JsonEscape(aDefinition.fOwnerName) + '",' +
    '"unitName":"' + JsonEscape(aDefinition.fUnitName) + '",' +
    '"filePath":"' + JsonEscape(aDefinition.fFilePath) + '",' +
    '"sourceKind":"' + JsonEscape(aDefinition.fSourceKind) + '",' +
    '"confidence":"' + JsonEscape(aDefinition.fConfidence) + '",' +
    '"signature":"' + JsonEscape(aDefinition.fSignature) + '",' +
    '"typeName":"' + JsonEscape(aDefinition.fTypeName) + '",' +
    '"line":' + aDefinition.fLine.ToString + ',' +
    '"col":' + aDefinition.fCol.ToString + ',' +
    '"endLine":' + aDefinition.fEndLine.ToString + ',' +
    '"endCol":' + aDefinition.fEndCol.ToString +
    '}';
end;

function SymbolMapDefinitionsJson(const aDefinitions: TArray<TSymbolMapDefinition>): string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to High(aDefinitions) do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + SymbolMapDefinitionJson(aDefinitions[i]);
  end;
  Result := Result + ']';
end;

function BuildDefinitionResultJson(const aDefinition: TSymbolMapDefinition): string;
begin
  Result := '{"definition":' + SymbolMapDefinitionJson(aDefinition) + '}';
end;

function BuildSearchResultJson(const aQuery: string; const aDefinitions: TArray<TSymbolMapDefinition>): string;
begin
  Result := '{"query":"' + JsonEscape(aQuery) + '","count":' + Length(aDefinitions).ToString +
    ',"definitions":' + SymbolMapDefinitionsJson(aDefinitions) + '}';
end;

function SymbolMapReferenceJson(const aReference: TSymbolMapReference): string;
begin
  Result := '{"name":"' + JsonEscape(aReference.fName) + '",' +
    '"unitName":"' + JsonEscape(aReference.fUnitName) + '",' +
    '"filePath":"' + JsonEscape(aReference.fFilePath) + '",' +
    '"sourceKind":"' + JsonEscape(aReference.fSourceKind) + '",' +
    '"confidence":"' + JsonEscape(aReference.fConfidence) + '",' +
    '"role":"' + JsonEscape(aReference.fRole) + '",' +
    '"sectionKind":"' + JsonEscape(aReference.fSectionKind) + '",' +
    '"line":' + aReference.fLine.ToString + ',' +
    '"col":' + aReference.fCol.ToString + ',' +
    '"endLine":' + aReference.fEndLine.ToString + ',' +
    '"endCol":' + aReference.fEndCol.ToString +
    '}';
end;

function SymbolMapReferencesJson(const aReferences: TArray<TSymbolMapReference>): string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to High(aReferences) do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + SymbolMapReferenceJson(aReferences[i]);
  end;
  Result := Result + ']';
end;

function BuildReferencesResultJson(const aSymbol: string; const aReferences: TArray<TSymbolMapReference>): string;
begin
  Result := '{"symbol":"' + JsonEscape(aSymbol) + '","count":' + Length(aReferences).ToString +
    ',"references":' + SymbolMapReferencesJson(aReferences) + '}';
end;

function CompilerProfileJson(const aCompilerProfile: TSymbolMapCompilerProfileResult): string;
begin
  Result := '{"profileKey":"' + JsonEscape(aCompilerProfile.fProfileKey) + '",' +
    '"delphiVersion":"' + JsonEscape(aCompilerProfile.fDelphiVersion) + '",' +
    '"platform":"' + JsonEscape(aCompilerProfile.fPlatform) + '",' +
    '"intrinsicSeedVersion":"' + JsonEscape(aCompilerProfile.fIntrinsicSeedVersion) + '",' +
    '"syntheticIntrinsicCount":' + aCompilerProfile.fIntrinsicCount.ToString + ',' +
    '"cacheHit":' + LowerCase(BoolToStr(aCompilerProfile.fCacheHit, True)) +
    '}';
end;

function RtlSourceJson(const aRtlSource: TSymbolMapRtlIndexResult): string;
begin
  Result := '{"status":"' + JsonEscape(aRtlSource.fStatus) + '",' +
    '"sourceRoot":"' + JsonEscape(aRtlSource.fSourceRoot) + '",' +
    '"unitsDiscovered":' + aRtlSource.fUnitsDiscovered.ToString + ',' +
    '"unitsIndexed":' + aRtlSource.fUnitsIndexed.ToString + ',' +
    '"cacheHit":' + LowerCase(BoolToStr(aRtlSource.fCacheHit, True)) + ',' +
    '"unitCacheHits":' + aRtlSource.fUnitCacheHits.ToString + ',' +
    '"unitCacheMisses":' + aRtlSource.fUnitCacheMisses.ToString + ',' +
    '"diagnosticsCount":' + aRtlSource.fDiagnosticsCount.ToString + ',' +
    '"diagnostics":' + aRtlSource.fDiagnosticsJson +
    '}';
end;

procedure WriteSymbolMapJsonShell(const aOptions: TAppOptions; const aContext: TSymbolMapContext;
  const aCacheStatus: TSymbolMapCacheStatus; const aCompilerProfile: TSymbolMapCompilerProfileResult;
  const aRtlSource: TSymbolMapRtlIndexResult; const aResultJson, aDiagnosticsJson: string);
var
  lOperation: string;
begin
  lOperation := SymbolMapOperationToText(aOptions.fSymbolMapOperation);
  WriteLn(
    '{"operation":"' + JsonEscape(lOperation) + '"' +
    ',"status":"ok"' +
    ',"project":{"path":"' + JsonEscape(aContext.fProject.fProjectPath) + '","name":"' +
      JsonEscape(aContext.fProject.fProjectName) + '","dir":"' + JsonEscape(aContext.fProject.fProjectDir) +
      '","mainSource":"' + JsonEscape(aContext.fProject.fMainSourcePath) + '","platform":"' +
      JsonEscape(aContext.fPlatform) + '","config":"' + JsonEscape(aContext.fConfig) + '"}' +
    ',"cache":{"centralRoot":"' + JsonEscape(aContext.fCentralCacheRoot) + '","projectRoot":"' +
      JsonEscape(aContext.fProjectCacheRoot) + '","centralDbPath":"' + JsonEscape(aCacheStatus.fCentralDbPath) +
      '","projectDbPath":"' + JsonEscape(aCacheStatus.fProjectDbPath) + '","schemaVersion":' +
      aCacheStatus.fSchemaVersion.ToString + ',"centralCreated":' +
      LowerCase(BoolToStr(aCacheStatus.fCentralCreated, True)) + ',"projectCreated":' +
      LowerCase(BoolToStr(aCacheStatus.fProjectCreated, True)) + '}' +
    ',"context":{"delphiVersion":"' + JsonEscape(aContext.fDelphiVersion) + '","hasDelphiContext":' +
      LowerCase(BoolToStr(aContext.fProject.fHasDelphiContext, True)) + ',"parserDefines":"' +
      JsonEscape(aContext.fProject.fParserDefines) + '","parserSearchPath":"' +
      JsonEscape(aContext.fProject.fParserSearchPath) + '","hasCompilerParams":' +
      LowerCase(BoolToStr(aContext.fHasCompilerParams, True)) + ',"defines":' +
      JsonStringArray(aContext.fDefines) + ',"unitSearchPath":' + JsonStringArray(aContext.fUnitSearchPath) +
      ',"libraryPath":' + JsonStringArray(aContext.fLibraryPath) + ',"unitScopes":' +
      JsonStringArray(aContext.fUnitScopes) + ',"unitAliases":' + JsonStringArray(aContext.fUnitAliases) +
      ',"rtlSourceRoot":"' + JsonEscape(aContext.fRtlSourceRoot) + '"}' +
    ',"compilerProfile":' + CompilerProfileJson(aCompilerProfile) +
    ',"rtlSource":' + RtlSourceJson(aRtlSource) +
    ',"query":{}' +
    ',"result":' + aResultJson +
    ',"diagnostics":' + aDiagnosticsJson +
    ',"timings":{"totalMs":0}}');
end;

procedure WriteSymbolMapTextShell(const aOptions: TAppOptions; const aContext: TSymbolMapContext;
  const aCacheStatus: TSymbolMapCacheStatus; const aCompilerProfile: TSymbolMapCompilerProfileResult;
  const aRtlSource: TSymbolMapRtlIndexResult; const aIndexedUnits: TArray<TSymbolMapIndexedUnit>);
var
  lUnit: TSymbolMapIndexedUnit;
begin
  WriteLn('symbol-map ', SymbolMapOperationToText(aOptions.fSymbolMapOperation), ': ok');
  WriteLn('project: ', aContext.fProject.fProjectPath);
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
  end;
end;

function TryIndexSymbolMapUnit(const aContext: TSymbolMapContext; const aCacheStatus: TSymbolMapCacheStatus;
  const aUnitPath: string; out aIndexedUnit: TSymbolMapIndexedUnit; out aError: string): Boolean;
var
  lUnitPath: string;
begin
  Result := False;
  aIndexedUnit := Default(TSymbolMapIndexedUnit);
  lUnitPath := TPath.GetFullPath(aUnitPath);
  if not TryExtractSymbolMapUnitModel(lUnitPath, aIndexedUnit.fModel, aError) then
    Exit(False);
  if not StoreSymbolMapUnitProjection(aContext, aCacheStatus, aIndexedUnit.fModel, aIndexedUnit.fStoreResult, aError) then
    Exit(False);
  Result := True;
end;

procedure AddIndexedUnit(var aUnits: TArray<TSymbolMapIndexedUnit>; const aUnit: TSymbolMapIndexedUnit); forward;

function TryIndexSymbolMapProject(const aContext: TSymbolMapContext; const aCacheStatus: TSymbolMapCacheStatus;
  var aIndexedUnits: TArray<TSymbolMapIndexedUnit>; out aError: string): Boolean;
var
  i: Integer;
  lIndexedUnit: TSymbolMapIndexedUnit;
  lModels: TArray<TSymbolMapUnitModel>;
  lStoreResults: TArray<TSymbolMapCacheStoreResult>;
  lUnitPath: string;
  lUnitPaths: TArray<string>;
begin
  Result := False;
  lUnitPaths := SymbolMapProjectSourceFilePaths(aContext, False);
  SetLength(lModels, Length(lUnitPaths));
  i := 0;
  for lUnitPath in lUnitPaths do
  begin
    lIndexedUnit := Default(TSymbolMapIndexedUnit);
    if not TryExtractSymbolMapUnitModel(lUnitPath, lIndexedUnit.fModel, aError) then
      Exit(False);
    lModels[i] := lIndexedUnit.fModel;
    Inc(i);
  end;
  if not StoreSymbolMapProjectProjection(aContext, aCacheStatus, lModels, lStoreResults, aError) then
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
  Result := TryIndexSymbolMapProject(aContext, aCacheStatus, aIndexedUnits, aError);
end;

procedure AddIndexedUnit(var aUnits: TArray<TSymbolMapIndexedUnit>; const aUnit: TSymbolMapIndexedUnit);
var
  lIndex: Integer;
begin
  lIndex := Length(aUnits);
  SetLength(aUnits, lIndex + 1);
  aUnits[lIndex] := aUnit;
end;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;
var
  lCacheStatus: TSymbolMapCacheStatus;
  lCompilerProfile: TSymbolMapCompilerProfileResult;
  lContext: TSymbolMapContext;
  lDefinition: TSymbolMapDefinition;
  lError: string;
  lIndexedUnit: TSymbolMapIndexedUnit;
  lIndexedUnits: TArray<TSymbolMapIndexedUnit>;
  lQueryDefinitions: TArray<TSymbolMapDefinition>;
  lReferences: TArray<TSymbolMapReference>;
  lResultJson: string;
  lRtlSource: TSymbolMapRtlIndexResult;
  lSymbol: string;
begin
  SetLength(lIndexedUnits, 0);
  lResultJson := '{}';
  if not TryBuildSymbolMapContext(aOptions, lContext, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitInvalidProjectInput);
  end;
  if not EnsureSymbolMapCaches(lContext, lCacheStatus, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitToolFailure);
  end;
  if not EnsureSymbolMapCompilerProfile(lContext, lCacheStatus, lCompilerProfile, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitToolFailure);
  end;
  lRtlSource := Default(TSymbolMapRtlIndexResult);
  lRtlSource.fStatus := 'not-indexed';
  lRtlSource.fDiagnosticsJson := '[]';
  if aOptions.fSymbolMapOperation = TSymbolMapOperation.smoIndex then
  begin
    if not IndexSymbolMapRtlSources(lContext, lCacheStatus, '', lCompilerProfile, lRtlSource, lError) then
    begin
      WriteLn(ErrOutput, lError);
      Exit(cExitToolFailure);
    end;
  end;
  if (aOptions.fSymbolMapOperation = TSymbolMapOperation.smoIndex) and (aOptions.fSymbolMapUnitPath <> '') then
  begin
    if not TryIndexSymbolMapUnit(lContext, lCacheStatus, aOptions.fSymbolMapUnitPath, lIndexedUnit, lError) then
    begin
      WriteLn(ErrOutput, lError);
      Exit(cExitToolFailure);
    end;
    AddIndexedUnit(lIndexedUnits, lIndexedUnit);
    lResultJson := BuildIndexResultJson(lIndexedUnits);
  end else if aOptions.fSymbolMapOperation = TSymbolMapOperation.smoIndex then
  begin
    if not TryIndexSymbolMapProject(lContext, lCacheStatus, lIndexedUnits, lError) then
    begin
      WriteLn(ErrOutput, lError);
      Exit(cExitToolFailure);
    end;
    lResultJson := BuildIndexResultJson(lIndexedUnits);
  end else if aOptions.fSymbolMapOperation in [TSymbolMapOperation.smoFindDefinition,
    TSymbolMapOperation.smoFindReferences, TSymbolMapOperation.smoSearchSymbols,
    TSymbolMapOperation.smoDescribeSymbol] then
  begin
    if not EnsureSymbolMapProjectIndexedForQuery(lContext, lCacheStatus, lIndexedUnits, lError) then
    begin
      WriteLn(ErrOutput, lError);
      Exit(cExitToolFailure);
    end;
    if aOptions.fSymbolMapOperation = TSymbolMapOperation.smoFindDefinition then
    begin
      if not FindSymbolMapDefinitionByPosition(lContext, lCacheStatus, lCompilerProfile,
        aOptions.fSymbolMapFilePath, aOptions.fSymbolMapLine, aOptions.fSymbolMapCol, lDefinition, lError) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(cExitToolFailure);
      end;
      lResultJson := BuildDefinitionResultJson(lDefinition);
    end else if aOptions.fSymbolMapOperation = TSymbolMapOperation.smoFindReferences then
    begin
      lSymbol := aOptions.fSymbolMapSymbol;
      if aOptions.fSymbolMapFilePath <> '' then
      begin
        if not FindSymbolMapReferencesByPosition(lContext, aOptions.fSymbolMapFilePath,
          aOptions.fSymbolMapLine, aOptions.fSymbolMapCol, aOptions.fSymbolMapLimit,
          lSymbol, lReferences, lError) then
        begin
          WriteLn(ErrOutput, lError);
          Exit(cExitToolFailure);
        end;
      end else if not FindSymbolMapReferences(lContext, lCacheStatus, lCompilerProfile, lSymbol,
        aOptions.fSymbolMapLimit, lReferences, lError) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(cExitToolFailure);
      end;
      lResultJson := BuildReferencesResultJson(lSymbol, lReferences);
    end else if aOptions.fSymbolMapOperation = TSymbolMapOperation.smoSearchSymbols then
    begin
      if not SearchSymbolMapDefinitions(lContext, lCacheStatus, lCompilerProfile, aOptions.fSymbolMapQuery,
        aOptions.fSymbolMapLimit, lQueryDefinitions, lError) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(cExitToolFailure);
      end;
      lResultJson := BuildSearchResultJson(aOptions.fSymbolMapQuery, lQueryDefinitions);
    end else
    begin
      if not DescribeSymbolMapDefinition(lContext, lCacheStatus, lCompilerProfile, aOptions.fSymbolMapSymbol,
        aOptions.fSymbolMapOwner, lDefinition, lError) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(cExitToolFailure);
      end;
      lResultJson := BuildDefinitionResultJson(lDefinition);
    end;
  end;

  if aOptions.fSymbolMapFormat = TSymbolMapFormat.smfText then
    WriteSymbolMapTextShell(aOptions, lContext, lCacheStatus, lCompilerProfile, lRtlSource, lIndexedUnits)
  else
    WriteSymbolMapJsonShell(aOptions, lContext, lCacheStatus, lCompilerProfile, lRtlSource, lResultJson, '[]');

  Result := cExitSuccess;
end;

end.
