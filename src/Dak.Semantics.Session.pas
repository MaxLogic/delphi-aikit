unit Dak.Semantics.Session;

interface

uses
  DelphiSemantics.Cache, DelphiSemantics.ProjectContext, DelphiSemantics.ProjectSession,
  DelphiSemantics.Query;

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
