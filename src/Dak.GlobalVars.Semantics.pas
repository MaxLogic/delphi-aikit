unit Dak.GlobalVars.Semantics;

interface

uses
  System.Generics.Collections,
  DelphiSemantics.Cache,
  Dak.GlobalVars.Model,
  Dak.Types;

type
  TGlobalVarsSemanticIdentity = record
    IdentityHash: string;
    CacheIdentities: TArray<TDelphiSemanticUnitCacheIdentity>;
  end;

  TGlobalVarsSemanticAnalysis = class
  public
    Symbols: TObjectList<TGlobalVarSymbol>;
    Ambiguities: TList<TGlobalVarAmbiguity>;
    IdentityHash: string;
    CacheIdentities: TArray<TDelphiSemanticUnitCacheIdentity>;
    constructor Create;
    destructor Destroy; override;
  end;

function AnalyzeGlobalVarsProject(const aProject: TProjectInfo;
  const aOptions: TAppOptions): TGlobalVarsSemanticAnalysis;
function BuildGlobalVarsProjectIdentity(const aProject: TProjectInfo;
  const aOptions: TAppOptions): TGlobalVarsSemanticIdentity;

implementation

uses
  System.Classes,
  System.Hash,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  DelphiSemantics.GlobalVars,
  DelphiSemantics.ProjectContext,
  DelphiSemantics.ProjectSession;

constructor TGlobalVarsSemanticAnalysis.Create;
begin
  inherited Create;
  Symbols := TObjectList<TGlobalVarSymbol>.Create(True);
  Ambiguities := TList<TGlobalVarAmbiguity>.Create;
end;

destructor TGlobalVarsSemanticAnalysis.Destroy;
begin
  Ambiguities.Free;
  Symbols.Free;
  inherited Destroy;
end;

function AccessKindForSemanticAccess(const aAccess: string): TAccessKind;
begin
  if SameText(aAccess, 'read') then
    Result := TAccessKind.akRead
  else if SameText(aAccess, 'write') then
    Result := TAccessKind.akWrite
  else
    Result := TAccessKind.akReadWrite;
end;

function GlobalVarKindForSemanticGlobalKind(const aKind: string;
  out aGlobalKind: TGlobalVarKind): Boolean;
begin
  if SameText(aKind, 'var') then
  begin
    aGlobalKind := TGlobalVarKind.gvkVar;
    Exit(True);
  end;
  if SameText(aKind, 'threadvar') then
  begin
    aGlobalKind := TGlobalVarKind.gvkThreadVar;
    Exit(True);
  end;
  if SameText(aKind, 'typedconst') then
  begin
    aGlobalKind := TGlobalVarKind.gvkTypedConst;
    Exit(True);
  end;
  if SameText(aKind, 'classvar') then
  begin
    aGlobalKind := TGlobalVarKind.gvkClassVar;
    Exit(True);
  end;
  Result := False;
end;

function SemanticGlobalKey(const aUnitName, aName: string): string;
begin
  Result := AnsiLowerCase(aUnitName) + '.' + AnsiLowerCase(aName);
end;

procedure AddSemanticUsage(const aSymbolsByKey: TDictionary<string, TGlobalVarSymbol>;
  const aUsage: TDelphiSemanticGlobalUsage);
var
  lRef: TGlobalVarRef;
  lSymbol: TGlobalVarSymbol;
begin
  if not aSymbolsByKey.TryGetValue(SemanticGlobalKey(aUsage.DeclaringUnitName,
    aUsage.Name), lSymbol) then
    Exit;

  lRef.UnitName := aUsage.UnitName;
  lRef.RoutineName := aUsage.RoutineName;
  lRef.FileName := aUsage.FileName;
  lRef.Line := aUsage.Line;
  lRef.Column := aUsage.Column;
  lRef.Access := AccessKindForSemanticAccess(aUsage.Access);
  lSymbol.UsedBy.Add(lRef);
end;

procedure AddSemanticAmbiguity(const aAmbiguities: TList<TGlobalVarAmbiguity>;
  const aAmbiguity: TDelphiSemanticGlobalAmbiguity);
var
  lAmbiguity: TGlobalVarAmbiguity;
begin
  lAmbiguity.Name := aAmbiguity.Name;
  lAmbiguity.UnitName := aAmbiguity.UnitName;
  lAmbiguity.RoutineName := aAmbiguity.RoutineName;
  lAmbiguity.FileName := aAmbiguity.FileName;
  lAmbiguity.Line := aAmbiguity.Line;
  lAmbiguity.Column := aAmbiguity.Column;
  lAmbiguity.Access := AccessKindForSemanticAccess(aAmbiguity.Access);
  lAmbiguity.Candidates := aAmbiguity.Candidates;
  aAmbiguities.Add(lAmbiguity);
end;

function SessionDiagnosticsText(const aDiagnostics: TArray<TDelphiSemanticDiagnostic>):
  string;
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
  end;
end;

function SemanticOptions(const aProject: TProjectInfo; const aOptions: TAppOptions):
  TDelphiSemanticOptions;
begin
  Result := Default(TDelphiSemanticOptions);
  Result.ProjectPath := aProject.ProjectPath;
  Result.Configuration := aOptions.fConfig;
  Result.Platform := aOptions.fPlatform;
  Result.DelphiVersion := aOptions.fDelphiVersion;
  Result.RsVarsPath := aOptions.fRsVarsPath;
  Result.EnvOptionsPath := aOptions.fEnvOptionsPath;
  Result.SqliteCacheFileName := TPath.Combine(aProject.CachePath,
    'semantic-unit-cache.sqlite3');
end;

function IdentityHash(const aProject: TProjectInfo;
  const aIdentities: TArray<TDelphiSemanticUnitCacheIdentity>): string;
var
  lBuilder: TStringBuilder;
  lIdentity: TDelphiSemanticUnitCacheIdentity;
  lText: string;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('unitScopes');
    for lText in aProject.UnitScopes do
      lBuilder.AppendLine(lText);
    lBuilder.AppendLine('unitAliases');
    for lText in aProject.UnitAliases do
      lBuilder.AppendLine(lText);
    for lIdentity in aIdentities do
    begin
      lBuilder.AppendLine(lIdentity.UnitCacheKey);
      lBuilder.AppendLine(lIdentity.FileHash);
      lBuilder.AppendLine(lIdentity.ContextHash);
      lBuilder.AppendLine(lIdentity.IncludeGraphHash);
      lBuilder.AppendLine(lIdentity.DefinesHash);
      lBuilder.AppendLine(lIdentity.SearchPathHash);
      lBuilder.AppendLine(lIdentity.ExtractionOptionsHash);
      lBuilder.AppendLine(lIdentity.CompilerProfileName);
      lBuilder.AppendLine(lIdentity.DelphiVersion);
      lBuilder.AppendLine(lIdentity.Configuration);
      lBuilder.AppendLine(lIdentity.Platform);
      lBuilder.AppendLine(lIdentity.ParserVersion);
      lBuilder.AppendLine(lIdentity.ModelVersion);
      lBuilder.AppendLine(lIdentity.SchemaVersion);
    end;
    Result := THashSHA2.GetHashString(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

procedure CopySemanticAnalysis(const aAnalysis: TDelphiSemanticGlobalAnalysis;
  const aResult: TGlobalVarsSemanticAnalysis);
var
  lDeclaration: TDelphiSemanticGlobalDeclaration;
  lKind: TGlobalVarKind;
  lSymbol: TGlobalVarSymbol;
  lSymbolsByKey: TDictionary<string, TGlobalVarSymbol>;
  lUsage: TDelphiSemanticGlobalUsage;
  lAmbiguity: TDelphiSemanticGlobalAmbiguity;
begin
  lSymbolsByKey := TDictionary<string, TGlobalVarSymbol>.Create;
  try
    for lDeclaration in aAnalysis.Declarations do
    begin
      if not GlobalVarKindForSemanticGlobalKind(lDeclaration.Kind, lKind) then
        Continue;

      lSymbol := TGlobalVarSymbol.Create;
      lSymbol.Name := lDeclaration.Name;
      lSymbol.UnitName := lDeclaration.UnitName;
      lSymbol.FileName := lDeclaration.FileName;
      lSymbol.Line := lDeclaration.Line;
      lSymbol.Column := lDeclaration.Column;
      lSymbol.TypeName := lDeclaration.TypeName;
      lSymbol.Kind := lKind;
      aResult.Symbols.Add(lSymbol);
      lSymbolsByKey.AddOrSetValue(SemanticGlobalKey(lSymbol.UnitName, lSymbol.Name),
        lSymbol);
    end;

    for lUsage in aAnalysis.Usages do
      AddSemanticUsage(lSymbolsByKey, lUsage);

    for lAmbiguity in aAnalysis.Ambiguities do
      AddSemanticAmbiguity(aResult.Ambiguities, lAmbiguity);
  finally
    lSymbolsByKey.Free;
  end;
end;

function AnalyzeGlobalVarsProject(const aProject: TProjectInfo;
  const aOptions: TAppOptions): TGlobalVarsSemanticAnalysis;
var
  lAnalysis: TDelphiSemanticGlobalAnalysis;
  lCacheMetrics: TDelphiSemanticCacheMetrics;
  lExtractionMilliseconds: Int64;
  lOptions: TDelphiSemanticOptions;
  lSessionResult: TDelphiSemanticProjectSessionResult;
begin
  Result := TGlobalVarsSemanticAnalysis.Create;
  try
    lOptions := SemanticOptions(aProject, aOptions);
    lSessionResult := TDelphiSemanticProjectSession.Open(lOptions);
    if not lSessionResult.Success then
      raise Exception.Create(SessionDiagnosticsText(lSessionResult.Diagnostics));
    try
      lAnalysis := lSessionResult.Session.BuildGlobalAnalysis(Result.CacheIdentities,
        lCacheMetrics, lExtractionMilliseconds);
      Result.IdentityHash := IdentityHash(aProject, Result.CacheIdentities);
      CopySemanticAnalysis(lAnalysis, Result);
    finally
      lSessionResult.Session.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function BuildGlobalVarsProjectIdentity(const aProject: TProjectInfo;
  const aOptions: TAppOptions): TGlobalVarsSemanticIdentity;
var
  lOptions: TDelphiSemanticOptions;
  lSessionResult: TDelphiSemanticProjectSessionResult;
begin
  Result := Default(TGlobalVarsSemanticIdentity);
  lOptions := SemanticOptions(aProject, aOptions);
  lSessionResult := TDelphiSemanticProjectSession.Open(lOptions);
  if not lSessionResult.Success then
    raise Exception.Create(SessionDiagnosticsText(lSessionResult.Diagnostics));
  try
    Result.CacheIdentities := lSessionResult.Session.BuildGlobalCacheIdentities;
    Result.IdentityHash := IdentityHash(aProject, Result.CacheIdentities);
  finally
    lSessionResult.Session.Free;
  end;
end;

end.
