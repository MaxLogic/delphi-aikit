unit Dak.SymbolMap;

interface

uses
  Dak.Types;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.IOUtils, System.SysUtils,
  Dak.ExitCodes, Dak.SymbolMap.Cache, Dak.SymbolMap.Context, Dak.SymbolMap.Indexer;

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

function BuildIndexResultJson(const aModel: TSymbolMapUnitModel; const aHasUnit: Boolean): string;
begin
  if not aHasUnit then
    Exit('{"unitCount":0,"fatalDiagnostics":0,"symbolCount":0,"indexedUnits":[]}');

  Result := '{"unitCount":1,"fatalDiagnostics":0,"indexedUnits":[{' +
    '"unitName":"' + JsonEscape(aModel.fUnitName) + '",' +
    '"filePath":"' + JsonEscape(aModel.fFilePath) + '",' +
    '"encoding":"' + JsonEscape(aModel.fEncodingName) + '",' +
    '"usesCount":' + Length(aModel.fUses).ToString + ',' +
    '"symbolCount":' + Length(aModel.fSymbols).ToString + ',' +
    '"interfaceUses":' + JsonStringArray(SymbolMapUseNames(aModel, 'interface')) + ',' +
    '"implementationUses":' + JsonStringArray(SymbolMapUseNames(aModel, 'implementation')) + ',' +
    '"symbols":' + SymbolMapSymbolsJson(aModel.fSymbols) + ',' +
    '"diagnostics":' + SymbolMapDiagnosticsJson(aModel.fDiagnostics) +
    '}],"symbolCount":' + Length(aModel.fSymbols).ToString + '}';
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
  const aCacheStatus: TSymbolMapCacheStatus; const aIndexModel: TSymbolMapUnitModel; const aHasIndexUnit: Boolean);
begin
  WriteLn('symbol-map ', SymbolMapOperationToText(aOptions.fSymbolMapOperation), ': ok');
  WriteLn('project: ', aContext.fProject.fProjectPath);
  WriteLn('central-cache-root: ', aContext.fCentralCacheRoot);
  WriteLn('project-cache-root: ', aContext.fProjectCacheRoot);
  WriteLn('central-cache-db: ', aCacheStatus.fCentralDbPath);
  WriteLn('project-cache-db: ', aCacheStatus.fProjectDbPath);
  WriteLn('schema-version: ', aCacheStatus.fSchemaVersion);
  if aHasIndexUnit then
  begin
    WriteLn('indexed-unit: ', aIndexModel.fUnitName);
    WriteLn('uses-count: ', Length(aIndexModel.fUses));
  end;
end;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;
var
  lCacheStatus: TSymbolMapCacheStatus;
  lContext: TSymbolMapContext;
  lError: string;
  lHasIndexUnit: Boolean;
  lIndexModel: TSymbolMapUnitModel;
  lResultJson: string;
  lUnitPath: string;
begin
  lHasIndexUnit := False;
  lIndexModel := Default(TSymbolMapUnitModel);
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
    lUnitPath := TPath.GetFullPath(aOptions.fSymbolMapUnitPath);
    if not TryExtractSymbolMapUnitModel(lUnitPath, lIndexModel, lError) then
    begin
      WriteLn(ErrOutput, lError);
      Exit(cExitInvalidProjectInput);
    end;
    lHasIndexUnit := True;
    lResultJson := BuildIndexResultJson(lIndexModel, True);
  end else if aOptions.fSymbolMapOperation = TSymbolMapOperation.smoIndex then
    lResultJson := BuildIndexResultJson(lIndexModel, False);

  if aOptions.fSymbolMapFormat = TSymbolMapFormat.smfText then
    WriteSymbolMapTextShell(aOptions, lContext, lCacheStatus, lIndexModel, lHasIndexUnit)
  else
    WriteSymbolMapJsonShell(aOptions, lContext, lCacheStatus, lResultJson, '[]');

  Result := cExitSuccess;
end;

end.
