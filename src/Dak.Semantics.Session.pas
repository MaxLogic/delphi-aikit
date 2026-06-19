unit Dak.Semantics.Session;

interface

uses
  System.Generics.Collections,
  DelphiSemantics.Api, DelphiSemantics.GlobalVars, DelphiSemantics.Graph,
  DelphiSemantics.ProjectContext, DelphiSemantics.Refactor, DelphiSemantics.Usage,
  Dak.Types;

type
  TDakSemanticCacheMetrics = record
    CacheHits: Integer;
    CacheMisses: Integer;
    Invalidations: Integer;
  end;

  TDakSemanticSymbolQueryMetrics = record
    CacheMetrics: TDakSemanticCacheMetrics;
    ExtractionMilliseconds: Int64;
    SessionOpenMilliseconds: Int64;
  end;

  TDakSemanticUnitCacheIdentity = record
    UnitCacheKey: string;
    FileHash: string;
    ContextHash: string;
    IncludeGraphHash: string;
    DefinesHash: string;
    SearchPathHash: string;
    ExtractionOptionsHash: string;
    CompilerProfileName: string;
    DelphiVersion: string;
    Configuration: string;
    Platform: string;
    ParserVersion: string;
    ModelVersion: string;
    SchemaVersion: string;
  end;

  TDakSemanticSymbolDefinition = record
    Found: Boolean;
    Name: string;
    Kind: string;
    TypeName: string;
    OwnerName: string;
    UnitName: string;
    SourceKind: string;
    Signature: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    EndLine: Integer;
    EndColumn: Integer;
  end;

  TDakSemanticUsageReference = record
    Name: string;
    UnitName: string;
    SourceKind: string;
    Role: string;
    SectionKind: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    EndLine: Integer;
    EndColumn: Integer;
  end;

  TDakSemanticReferenceQueryResult = record
    SymbolName: string;
    References: TArray<TDakSemanticUsageReference>;
  end;

  IDakSemanticProjectSession = interface
    ['{D4B4F27A-2642-4D2F-A260-156B2FF6A5AE}']
    function BuildDependencyGraph: TDelphiSemanticDependencyGraph;
    function BuildGlobalAnalysis(out aCacheIdentities:
      TArray<TDakSemanticUnitCacheIdentity>; out aCacheMetrics:
      TDakSemanticCacheMetrics; out aExtractionMilliseconds: Int64):
      TDelphiSemanticGlobalAnalysis;
    function BuildGlobalCacheIdentities: TArray<TDakSemanticUnitCacheIdentity>;
  end;

  IDakSemanticSymbolQueryContext = interface
    ['{1C0F51BE-9714-49E9-9B2D-E0E566ED4726}']
    function FindDefinitionAtPosition(const aFileName: string; const aLine,
      aColumn: Integer): TDakSemanticSymbolDefinition;
    function FindReferencesAtPosition(const aFileName: string; const aLine,
      aColumn, aLimit: Integer): TDakSemanticReferenceQueryResult;
    function FindUsagesAtPosition(const aFileName: string; const aLine,
      aColumn: Integer): TDelphiSemanticUsageResult;
    function FindUsagesByName(const aName: string): TDelphiSemanticUsageResult;
    function PlanRename(const aName, aNewName: string): TDelphiSemanticRenamePlan;
    function PlanRenameAtPosition(const aFileName: string; const aLine,
      aColumn: Integer; const aNewName: string): TDelphiSemanticRenamePlan;
    function ReferenceFallbackCount: Integer;
    function ReportDeadCode(const aProfile: string): TDelphiSemanticDeadCodeReport;
    function UnitModelCount: Integer;
  end;

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
  out aSession: IDakSemanticProjectSession; out aError: string;
  const aIncludeLineNumbers: Boolean = False): Boolean;
function OpenSemanticSymbolQueryContext(const aOptions: TDelphiSemanticOptions;
  out aContext: IDakSemanticSymbolQueryContext;
  out aMetrics: TDakSemanticSymbolQueryMetrics; out aError: string;
  const aIncludeLineNumbers: Boolean = False): Boolean;

implementation

uses
  System.Diagnostics, System.IOUtils, System.SysUtils,
  DelphiSemantics.Cache, DelphiSemantics.Model, DelphiSemantics.ProjectSession,
  DelphiSemantics.Query;

type
  TDakSemanticProjectSession = class(TInterfacedObject, IDakSemanticProjectSession)
  private
    fSession: TDelphiSemanticProjectSession;
  public
    constructor Create(const aSession: TDelphiSemanticProjectSession);
    destructor Destroy; override;
    function BuildDependencyGraph: TDelphiSemanticDependencyGraph;
    function BuildGlobalAnalysis(out aCacheIdentities:
      TArray<TDakSemanticUnitCacheIdentity>; out aCacheMetrics:
      TDakSemanticCacheMetrics; out aExtractionMilliseconds: Int64):
      TDelphiSemanticGlobalAnalysis;
    function BuildGlobalCacheIdentities: TArray<TDakSemanticUnitCacheIdentity>;
  end;

  TDakSemanticSymbolQueryContext = class(TInterfacedObject, IDakSemanticSymbolQueryContext)
  private
    fContext: TDelphiSemanticSymbolQueryContext;
  public
    constructor Create(const aContext: TDelphiSemanticSymbolQueryContext);
    function FindDefinitionAtPosition(const aFileName: string; const aLine,
      aColumn: Integer): TDakSemanticSymbolDefinition;
    function FindReferencesAtPosition(const aFileName: string; const aLine,
      aColumn, aLimit: Integer): TDakSemanticReferenceQueryResult;
    function FindUsagesAtPosition(const aFileName: string; const aLine,
      aColumn: Integer): TDelphiSemanticUsageResult;
    function FindUsagesByName(const aName: string): TDelphiSemanticUsageResult;
    function PlanRename(const aName, aNewName: string): TDelphiSemanticRenamePlan;
    function PlanRenameAtPosition(const aFileName: string; const aLine,
      aColumn: Integer; const aNewName: string): TDelphiSemanticRenamePlan;
    function ReferenceFallbackCount: Integer;
    function ReportDeadCode(const aProfile: string): TDelphiSemanticDeadCodeReport;
    function UnitModelCount: Integer;
  end;

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

function MapCacheMetrics(const aMetrics: TDelphiSemanticCacheMetrics):
  TDakSemanticCacheMetrics;
begin
  Result.CacheHits := aMetrics.CacheHits;
  Result.CacheMisses := aMetrics.CacheMisses;
  Result.Invalidations := aMetrics.Invalidations;
end;

function MapCacheIdentity(const aIdentity: TDelphiSemanticUnitCacheIdentity):
  TDakSemanticUnitCacheIdentity;
begin
  Result.UnitCacheKey := aIdentity.UnitCacheKey;
  Result.FileHash := aIdentity.FileHash;
  Result.ContextHash := aIdentity.ContextHash;
  Result.IncludeGraphHash := aIdentity.IncludeGraphHash;
  Result.DefinesHash := aIdentity.DefinesHash;
  Result.SearchPathHash := aIdentity.SearchPathHash;
  Result.ExtractionOptionsHash := aIdentity.ExtractionOptionsHash;
  Result.CompilerProfileName := aIdentity.CompilerProfileName;
  Result.DelphiVersion := aIdentity.DelphiVersion;
  Result.Configuration := aIdentity.Configuration;
  Result.Platform := aIdentity.Platform;
  Result.ParserVersion := aIdentity.ParserVersion;
  Result.ModelVersion := aIdentity.ModelVersion;
  Result.SchemaVersion := aIdentity.SchemaVersion;
end;

function MapCacheIdentities(const aIdentities:
  TArray<TDelphiSemanticUnitCacheIdentity>): TArray<TDakSemanticUnitCacheIdentity>;
var
  i: Integer;
begin
  SetLength(Result, Length(aIdentities));
  for i := 0 to High(aIdentities) do
    Result[i] := MapCacheIdentity(aIdentities[i]);
end;

function MapSymbolDefinition(const aResult: TDelphiSemanticSymbolQueryResult):
  TDakSemanticSymbolDefinition;
begin
  Result := Default(TDakSemanticSymbolDefinition);
  Result.Found := aResult.Found;
  Result.Name := aResult.Name;
  Result.Kind := aResult.Kind;
  Result.TypeName := aResult.TypeName;
  Result.OwnerName := aResult.OwnerName;
  Result.UnitName := aResult.UnitName;
  Result.SourceKind := aResult.SourceKind;
  Result.Signature := aResult.Signature;
  Result.FileName := aResult.FileName;
  Result.Line := aResult.Line;
  Result.Column := aResult.Column;
  Result.EndLine := aResult.EndLine;
  Result.EndColumn := aResult.EndColumn;
end;

function MapUsageReference(const aUsage: TDelphiSemanticUsage):
  TDakSemanticUsageReference;
begin
  Result.Name := aUsage.Name;
  Result.UnitName := aUsage.UnitName;
  Result.SourceKind := aUsage.SourceKind;
  Result.Role := aUsage.Role;
  Result.SectionKind := aUsage.SectionKind;
  Result.FileName := aUsage.FileName;
  Result.Line := aUsage.Line;
  Result.Column := aUsage.Column;
  Result.EndLine := aUsage.EndLine;
  Result.EndColumn := aUsage.EndColumn;
end;

function UnitModelDiagnosticsText(const aModel: TDelphiSemanticUnitModel): string;
var
  lDiagnostic: TDelphiSemanticModelDiagnostic;
begin
  Result := '';
  for lDiagnostic in aModel.Diagnostics do
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + lDiagnostic.Code + ': ' + lDiagnostic.Message;
    if lDiagnostic.Line > 0 then
      Result := Result + Format(' (line %d)', [lDiagnostic.Line]);
  end;
end;

function SnapshotVisibleScopeCount(const aContext:
  TDelphiSemanticSymbolQueryContext): Integer;
var
  lScope: TDelphiSemanticVisibleUnitScope;
begin
  Result := 0;
  if aContext.ProjectSnapshot = nil then
    Exit;

  for lScope in TDelphiSemanticSymbolQuery.GetVisibleUnitScopes(aContext) do
    if lScope.FileName <> '' then
      Inc(Result);
end;

function TryValidateSemanticContext(const aContext: TDelphiSemanticSymbolQueryContext;
  out aError: string): Boolean;
var
  lDiagnosticText: string;
  lModel: TDelphiSemanticUnitModel;
begin
  Result := False;
  aError := '';

  if (aContext.UnitModel.FileName <> '') and (not aContext.UnitModel.Success) then
  begin
    aError := 'Failed to build semantic model for project unit: ' +
      aContext.UnitModel.FileName;
    lDiagnosticText := UnitModelDiagnosticsText(aContext.UnitModel);
    if lDiagnosticText <> '' then
      aError := aError + sLineBreak + lDiagnosticText;
    Exit;
  end;

  if SnapshotVisibleScopeCount(aContext) > 0 then
    Exit(True);

  if aContext.UnitModel.FileName = '' then
  begin
    aError := 'Failed to build DelphiSemantics symbol query context.';
    Exit;
  end;

  for lModel in aContext.IndexedUnitModels do
    if not lModel.Success then
    begin
      aError := 'Failed to build semantic model for project unit: ' + lModel.FileName;
      lDiagnosticText := UnitModelDiagnosticsText(lModel);
      if lDiagnosticText <> '' then
        aError := aError + sLineBreak + lDiagnosticText;
      Exit;
    end;

  Result := True;
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

constructor TDakSemanticProjectSession.Create(
  const aSession: TDelphiSemanticProjectSession);
begin
  inherited Create;
  fSession := aSession;
end;

destructor TDakSemanticProjectSession.Destroy;
begin
  fSession.Free;
  inherited Destroy;
end;

function TDakSemanticProjectSession.BuildDependencyGraph:
  TDelphiSemanticDependencyGraph;
begin
  Result := fSession.BuildDependencyGraph;
end;

function TDakSemanticProjectSession.BuildGlobalAnalysis(out aCacheIdentities:
  TArray<TDakSemanticUnitCacheIdentity>; out aCacheMetrics:
  TDakSemanticCacheMetrics; out aExtractionMilliseconds: Int64):
  TDelphiSemanticGlobalAnalysis;
var
  lCacheIdentities: TArray<TDelphiSemanticUnitCacheIdentity>;
  lCacheMetrics: TDelphiSemanticCacheMetrics;
begin
  Result := fSession.BuildGlobalAnalysis(lCacheIdentities, lCacheMetrics,
    aExtractionMilliseconds);
  aCacheIdentities := MapCacheIdentities(lCacheIdentities);
  aCacheMetrics := MapCacheMetrics(lCacheMetrics);
end;

function TDakSemanticProjectSession.BuildGlobalCacheIdentities:
  TArray<TDakSemanticUnitCacheIdentity>;
begin
  Result := MapCacheIdentities(fSession.BuildGlobalCacheIdentities);
end;

constructor TDakSemanticSymbolQueryContext.Create(
  const aContext: TDelphiSemanticSymbolQueryContext);
begin
  inherited Create;
  fContext := aContext;
end;

function TDakSemanticSymbolQueryContext.FindDefinitionAtPosition(
  const aFileName: string; const aLine, aColumn: Integer):
  TDakSemanticSymbolDefinition;
begin
  Result := MapSymbolDefinition(TDelphiSemanticSymbolQuery.FindDefinitionAtPosition(
    fContext, aFileName, aLine, aColumn));
end;

function TDakSemanticSymbolQueryContext.FindReferencesAtPosition(
  const aFileName: string; const aLine, aColumn, aLimit: Integer):
  TDakSemanticReferenceQueryResult;
var
  i: Integer;
  lIndex: Integer;
  lResult: TDelphiSemanticUsageResult;
begin
  Result := Default(TDakSemanticReferenceQueryResult);
  lResult := TDelphiSemanticUsageFinder.FindUsagesAtPosition(fContext, aFileName,
    aLine, aColumn);
  if lResult.Status <> 'resolved' then
    Exit;

  Result.SymbolName := lResult.Symbol.Name;
  for i := 0 to High(lResult.Usages) do
  begin
    if (aLimit > 0) and (Length(Result.References) >= aLimit) then
      Break;
    lIndex := Length(Result.References);
    SetLength(Result.References, lIndex + 1);
    Result.References[lIndex] := MapUsageReference(lResult.Usages[i]);
  end;
end;

function TDakSemanticSymbolQueryContext.FindUsagesAtPosition(
  const aFileName: string; const aLine, aColumn: Integer):
  TDelphiSemanticUsageResult;
begin
  Result := TDelphiSemanticApi.FindUsagesAtPosition(fContext, aFileName, aLine,
    aColumn);
end;

function TDakSemanticSymbolQueryContext.FindUsagesByName(
  const aName: string): TDelphiSemanticUsageResult;
begin
  Result := TDelphiSemanticApi.FindUsagesByName(fContext, aName);
end;

function TDakSemanticSymbolQueryContext.PlanRename(const aName,
  aNewName: string): TDelphiSemanticRenamePlan;
begin
  Result := TDelphiSemanticApi.PlanRename(fContext, aName, aNewName);
end;

function TDakSemanticSymbolQueryContext.PlanRenameAtPosition(
  const aFileName: string; const aLine, aColumn: Integer;
  const aNewName: string): TDelphiSemanticRenamePlan;
begin
  Result := TDelphiSemanticApi.PlanRenameAtPosition(fContext, aFileName, aLine,
    aColumn, aNewName);
end;

function TDakSemanticSymbolQueryContext.ReferenceFallbackCount: Integer;
var
  lModel: TDelphiSemanticUnitModel;
begin
  if fContext.ProjectSnapshot <> nil then
    Exit(0);

  Result := fContext.UnitModel.Metrics.ReferenceReconciliationFallbackCount;
  for lModel in fContext.IndexedUnitModels do
    Inc(Result, lModel.Metrics.ReferenceReconciliationFallbackCount);
end;

function TDakSemanticSymbolQueryContext.ReportDeadCode(
  const aProfile: string): TDelphiSemanticDeadCodeReport;
begin
  Result := TDelphiSemanticApi.ReportDeadCode(fContext, aProfile);
end;

function TDakSemanticSymbolQueryContext.UnitModelCount: Integer;
begin
  Result := SnapshotVisibleScopeCount(fContext);
  if Result > 0 then
    Exit;

  if fContext.UnitModel.FileName <> '' then
    Inc(Result);
  Inc(Result, Length(fContext.IndexedUnitModels));
end;

function OpenSemanticProjectSession(const aOptions: TDelphiSemanticOptions;
  out aSession: IDakSemanticProjectSession; out aError: string;
  const aIncludeLineNumbers: Boolean = False): Boolean;
var
  lResult: TDelphiSemanticProjectSessionResult;
begin
  aError := '';
  aSession := nil;
  lResult := TDelphiSemanticProjectSession.Open(aOptions);
  Result := lResult.Success;
  if Result then
  begin
    aSession := TDakSemanticProjectSession.Create(lResult.Session);
    lResult.Session := nil;
    Exit;
  end;

  aError := SemanticSessionDiagnosticsText(lResult.Diagnostics, aIncludeLineNumbers);
  if aError = '' then
    aError := 'Failed to open DelphiSemantics project session.';
end;

function OpenSemanticSymbolQueryContext(const aOptions: TDelphiSemanticOptions;
  out aContext: IDakSemanticSymbolQueryContext;
  out aMetrics: TDakSemanticSymbolQueryMetrics; out aError: string;
  const aIncludeLineNumbers: Boolean = False): Boolean;
var
  lCacheMetrics: TDelphiSemanticCacheMetrics;
  lContext: TDelphiSemanticSymbolQueryContext;
  lSessionResult: TDelphiSemanticProjectSessionResult;
  lStopwatch: TStopwatch;
begin
  aContext := nil;
  aMetrics := Default(TDakSemanticSymbolQueryMetrics);
  aError := '';
  lStopwatch := TStopwatch.StartNew;
  lSessionResult := TDelphiSemanticProjectSession.Open(aOptions);
  if not lSessionResult.Success then
  begin
    aError := SemanticSessionDiagnosticsText(lSessionResult.Diagnostics,
      aIncludeLineNumbers);
    if aError = '' then
      aError := 'Failed to open DelphiSemantics project session.';
    Exit(False);
  end;
  aMetrics.SessionOpenMilliseconds := lStopwatch.ElapsedMilliseconds;
  try
    lContext := lSessionResult.Session.BuildSnapshotSymbolQueryContext(lCacheMetrics,
      aMetrics.ExtractionMilliseconds);
    aMetrics.CacheMetrics := MapCacheMetrics(lCacheMetrics);
    if not TryValidateSemanticContext(lContext, aError) then
      Exit(False);

    aContext := TDakSemanticSymbolQueryContext.Create(lContext);
    Result := True;
  finally
    lSessionResult.Session.Free;
  end;
end;

end.
