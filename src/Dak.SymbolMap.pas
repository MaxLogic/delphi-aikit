unit Dak.SymbolMap;

interface

uses
  Dak.Types;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.SysUtils,
  Dak.ExitCodes, Dak.SymbolMap.Context;

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

procedure WriteSymbolMapJsonShell(const aOptions: TAppOptions; const aContext: TSymbolMapContext);
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
      JsonEscape(aContext.fProjectCacheRoot) + '"}' +
    ',"context":{"delphiVersion":"' + JsonEscape(aContext.fDelphiVersion) + '","hasDelphiContext":' +
      LowerCase(BoolToStr(aContext.fProject.fHasDelphiContext, True)) + ',"parserDefines":"' +
      JsonEscape(aContext.fProject.fParserDefines) + '","parserSearchPath":"' +
      JsonEscape(aContext.fProject.fParserSearchPath) + '","hasCompilerParams":' +
      LowerCase(BoolToStr(aContext.fHasCompilerParams, True)) + ',"defines":' +
      JsonStringArray(aContext.fDefines) + ',"unitSearchPath":' + JsonStringArray(aContext.fUnitSearchPath) +
      ',"libraryPath":' + JsonStringArray(aContext.fLibraryPath) + ',"unitScopes":' +
      JsonStringArray(aContext.fUnitScopes) + ',"unitAliases":' + JsonStringArray(aContext.fUnitAliases) + '}' +
    ',"query":{}' +
    ',"result":{}' +
    ',"diagnostics":[]' +
    ',"timings":{"totalMs":0}}');
end;

procedure WriteSymbolMapTextShell(const aOptions: TAppOptions; const aContext: TSymbolMapContext);
begin
  WriteLn('symbol-map ', SymbolMapOperationToText(aOptions.fSymbolMapOperation), ': ok');
  WriteLn('project: ', aContext.fProject.fProjectPath);
  WriteLn('central-cache-root: ', aContext.fCentralCacheRoot);
  WriteLn('project-cache-root: ', aContext.fProjectCacheRoot);
end;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;
var
  lContext: TSymbolMapContext;
  lError: string;
begin
  if not TryBuildSymbolMapContext(aOptions, lContext, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitInvalidProjectInput);
  end;

  if aOptions.fSymbolMapFormat = TSymbolMapFormat.smfText then
    WriteSymbolMapTextShell(aOptions, lContext)
  else
    WriteSymbolMapJsonShell(aOptions, lContext);

  Result := cExitSuccess;
end;

end.
