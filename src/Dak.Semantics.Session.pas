unit Dak.Semantics.Session;

interface

uses
  System.Generics.Collections,
  DelphiSemantics.Api, DelphiSemantics.Cache, DelphiSemantics.ProjectContext,
  DelphiSemantics.ProjectSession, DelphiSemantics.Query,
  Dak.Types;

function BuildSemanticApiOptions(const aOptions: TAppOptions;
  const aEnvironmentVariables: TDictionary<string, string>;
  const aSearchPaths: TArray<string>): TDelphiSemanticApiOptions;
function BuildSemanticSessionOptions(const aProjectPath, aConfiguration, aPlatform,
  aDelphiVersion, aRsVarsPath, aEnvOptionsPath, aCacheFileName: string):
  TDelphiSemanticOptions;
function SemanticSessionDiagnosticsText(
  const aDiagnostics: TArray<TDelphiSemanticDiagnostic>;
  const aIncludeLineNumbers: Boolean = False): string;
function OpenSemanticProjectSession(const aOptions: TDelphiSemanticOptions;
  out aResult: TDelphiSemanticProjectSessionResult; out aError: string;
  const aIncludeLineNumbers: Boolean = False): Boolean;
function OpenSemanticSymbolQueryContext(const aOptions: TDelphiSemanticOptions;
  out aContext: TDelphiSemanticSymbolQueryContext;
  out aCacheMetrics: TDelphiSemanticCacheMetrics; out aExtractionMilliseconds: Int64;
  out aSessionOpenMilliseconds: Int64; out aError: string;
  const aIncludeLineNumbers: Boolean = False): Boolean;

implementation

uses
  System.Diagnostics, System.IOUtils, System.SysUtils;

function SemanticEnvironmentProperties(const aEnvironmentVariables: TDictionary<string, string>):
  TArray<TDelphiSemanticProperty>;
var
  i: Integer;
  lPair: TPair<string, string>;
begin
  if aEnvironmentVariables = nil then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  SetLength(Result, aEnvironmentVariables.Count);
  i := 0;
  for lPair in aEnvironmentVariables do
  begin
    Result[i].Name := lPair.Key;
    Result[i].Value := lPair.Value;
    Inc(i);
  end;
end;

function BuildSemanticApiOptions(const aOptions: TAppOptions;
  const aEnvironmentVariables: TDictionary<string, string>;
  const aSearchPaths: TArray<string>): TDelphiSemanticApiOptions;
begin
  Result := Default(TDelphiSemanticApiOptions);
  Result.Configuration := aOptions.fConfig;
  Result.Platform := aOptions.fPlatform;
  Result.DelphiVersion := aOptions.fDelphiVersion;
  Result.ProjectFileName := aOptions.fDprojPath;
  Result.RsVarsPath := aOptions.fRsVarsPath;
  Result.EnvOptionsPath := aOptions.fEnvOptionsPath;
  Result.EnvironmentVariables := SemanticEnvironmentProperties(aEnvironmentVariables);
  Result.SearchPaths := Copy(aSearchPaths);
  Result.Cache.DelphiVersion := aOptions.fDelphiVersion;
  Result.Cache.Configuration := aOptions.fConfig;
  Result.Cache.Platform := aOptions.fPlatform;
end;

function BuildSemanticSessionOptions(const aProjectPath, aConfiguration, aPlatform,
  aDelphiVersion, aRsVarsPath, aEnvOptionsPath, aCacheFileName: string):
  TDelphiSemanticOptions;
begin
  Result := Default(TDelphiSemanticOptions);
  Result.ProjectPath := aProjectPath;
  Result.Configuration := aConfiguration;
  Result.Platform := aPlatform;
  Result.DelphiVersion := aDelphiVersion;
  Result.RsVarsPath := aRsVarsPath;
  Result.EnvOptionsPath := aEnvOptionsPath;
  if Trim(aCacheFileName) <> '' then
    Result.SqliteCacheFileName := TPath.GetFullPath(aCacheFileName);
end;

function SemanticSessionDiagnosticsText(
  const aDiagnostics: TArray<TDelphiSemanticDiagnostic>;
  const aIncludeLineNumbers: Boolean = False): string;
var
  lDiagnostic: TDelphiSemanticDiagnostic;
begin
  Result := '';
  for lDiagnostic in aDiagnostics do
  begin
    if Result <> '' then
      Result := Result + sLineBreak;
    Result := Result + lDiagnostic.Code + ': ' + lDiagnostic.Message;
    if lDiagnostic.FileName <> '' then
      Result := Result + ' (' + lDiagnostic.FileName + ')';
    if aIncludeLineNumbers and (lDiagnostic.Line > 0) then
      Result := Result + Format(' line %d', [lDiagnostic.Line]);
  end;
end;

function OpenSemanticProjectSession(const aOptions: TDelphiSemanticOptions;
  out aResult: TDelphiSemanticProjectSessionResult; out aError: string;
  const aIncludeLineNumbers: Boolean = False): Boolean;
begin
  aError := '';
  aResult := TDelphiSemanticProjectSession.Open(aOptions);
  Result := aResult.Success;
  if Result then
    Exit;

  aError := SemanticSessionDiagnosticsText(aResult.Diagnostics, aIncludeLineNumbers);
  if aError = '' then
    aError := 'Failed to open DelphiSemantics project session.';
end;

function OpenSemanticSymbolQueryContext(const aOptions: TDelphiSemanticOptions;
  out aContext: TDelphiSemanticSymbolQueryContext;
  out aCacheMetrics: TDelphiSemanticCacheMetrics; out aExtractionMilliseconds: Int64;
  out aSessionOpenMilliseconds: Int64; out aError: string;
  const aIncludeLineNumbers: Boolean = False): Boolean;
var
  lSessionResult: TDelphiSemanticProjectSessionResult;
  lStopwatch: TStopwatch;
begin
  aContext := Default(TDelphiSemanticSymbolQueryContext);
  aCacheMetrics := Default(TDelphiSemanticCacheMetrics);
  aExtractionMilliseconds := 0;
  aSessionOpenMilliseconds := 0;
  lStopwatch := TStopwatch.StartNew;
  if not OpenSemanticProjectSession(aOptions, lSessionResult, aError,
    aIncludeLineNumbers) then
    Exit(False);
  aSessionOpenMilliseconds := lStopwatch.ElapsedMilliseconds;

  try
    aContext := lSessionResult.Session.BuildSymbolQueryContext(aCacheMetrics,
      aExtractionMilliseconds);
    Result := True;
  finally
    lSessionResult.Session.Free;
  end;
end;

end.
