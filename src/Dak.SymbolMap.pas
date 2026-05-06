unit Dak.SymbolMap;

interface

uses
  Dak.Types;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.RegularExpressions, System.SysUtils,
  Dak.ExitCodes, Dak.SymbolMap.Cache, Dak.SymbolMap.Context, Dak.SymbolMap.Indexer;

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

procedure WriteSymbolMapJsonShell(const aOptions: TAppOptions; const aContext: TSymbolMapContext;
  const aCacheStatus: TSymbolMapCacheStatus; const aResultJson, aDiagnosticsJson: string);
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
      JsonStringArray(aContext.fUnitScopes) + ',"unitAliases":' + JsonStringArray(aContext.fUnitAliases) + '}' +
    ',"query":{}' +
    ',"result":' + aResultJson +
    ',"diagnostics":' + aDiagnosticsJson +
    ',"timings":{"totalMs":0}}');
end;

procedure WriteSymbolMapTextShell(const aOptions: TAppOptions; const aContext: TSymbolMapContext;
  const aCacheStatus: TSymbolMapCacheStatus; const aIndexedUnits: TArray<TSymbolMapIndexedUnit>);
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
  WriteLn('indexed-units: ', Length(aIndexedUnits));
  for lUnit in aIndexedUnits do
  begin
    WriteLn('indexed-unit: ', lUnit.fModel.fUnitName);
    WriteLn('unit-cache-key: ', lUnit.fStoreResult.fUnitCacheKey);
    WriteLn('central-cache-hit: ', LowerCase(BoolToStr(lUnit.fStoreResult.fCacheHit, True)));
  end;
end;

function CollectProjectIndexUnitPaths(const aContext: TSymbolMapContext): TArray<string>;
var
  lDprojText: string;
  lIncludePath: string;
  lMatch: TMatch;
  lMatches: TMatchCollection;
  lPath: string;
  lPaths: TList<string>;
  lSeen: TDictionary<string, Boolean>;
begin
  SetLength(Result, 0);
  if not TFile.Exists(aContext.fProject.fProjectPath) then
    Exit;
  lDprojText := TFile.ReadAllText(aContext.fProject.fProjectPath);
  lMatches := TRegEx.Matches(lDprojText, '<DCCReference\b[^>]*\bInclude\s*=\s*"([^"]+)"', [roIgnoreCase]);
  lPaths := TList<string>.Create;
  lSeen := TDictionary<string, Boolean>.Create;
  try
    for lMatch in lMatches do
    begin
      if (not lMatch.Success) or (lMatch.Groups.Count < 2) then
        Continue;
      lIncludePath := Trim(lMatch.Groups[1].Value);
      if not SameText(TPath.GetExtension(lIncludePath), '.pas') then
        Continue;
      if TPath.IsPathRooted(lIncludePath) then
        lPath := TPath.GetFullPath(lIncludePath)
      else
        lPath := TPath.GetFullPath(TPath.Combine(aContext.fProject.fProjectDir, lIncludePath));
      if (not TFile.Exists(lPath)) or lSeen.ContainsKey(LowerCase(lPath)) then
        Continue;
      lSeen.Add(LowerCase(lPath), True);
      lPaths.Add(lPath);
    end;
    Result := lPaths.ToArray;
  finally
    lSeen.Free;
    lPaths.Free;
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
  if not StoreSymbolMapUnitModel(aContext, aCacheStatus, aIndexedUnit.fModel, aIndexedUnit.fStoreResult, aError) then
    Exit(False);
  Result := True;
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
  lContext: TSymbolMapContext;
  lError: string;
  lIndexedUnit: TSymbolMapIndexedUnit;
  lIndexedUnits: TArray<TSymbolMapIndexedUnit>;
  lResultJson: string;
  lUnitPaths: TArray<string>;
  lUnitPath: string;
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
    lUnitPaths := CollectProjectIndexUnitPaths(lContext);
    for lUnitPath in lUnitPaths do
    begin
      if not TryIndexSymbolMapUnit(lContext, lCacheStatus, lUnitPath, lIndexedUnit, lError) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(cExitToolFailure);
      end;
      AddIndexedUnit(lIndexedUnits, lIndexedUnit);
    end;
    lResultJson := BuildIndexResultJson(lIndexedUnits);
  end;

  if aOptions.fSymbolMapFormat = TSymbolMapFormat.smfText then
    WriteSymbolMapTextShell(aOptions, lContext, lCacheStatus, lIndexedUnits)
  else
    WriteSymbolMapJsonShell(aOptions, lContext, lCacheStatus, lResultJson, '[]');

  Result := cExitSuccess;
end;

end.
