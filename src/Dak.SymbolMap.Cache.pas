unit Dak.SymbolMap.Cache;

interface

uses
  Dak.SymbolMap.Context, Dak.SymbolMap.Indexer;

const
  cSymbolMapSchemaVersion = 2;

type
  TSymbolMapCacheStatus = record
    fCentralDbPath: string;
    fProjectDbPath: string;
    fSchemaVersion: Integer;
    fCentralCreated: Boolean;
    fProjectCreated: Boolean;
  end;

  TSymbolMapCacheStoreResult = record
    fUnitCacheKey: string;
    fFileHash: string;
    fContextHash: string;
    fCacheHit: Boolean;
  end;

  TSymbolMapCompilerProfileResult = record
    fProfileKey: string;
    fDelphiVersion: string;
    fPlatform: string;
    fIntrinsicSeedVersion: string;
    fIntrinsicCount: Integer;
    fCacheHit: Boolean;
  end;

  TSymbolMapRtlIndexResult = record
    fStatus: string;
    fSourceRoot: string;
    fUnitsDiscovered: Integer;
    fUnitsIndexed: Integer;
    fCacheHit: Boolean;
    fUnitCacheHits: Integer;
    fUnitCacheMisses: Integer;
    fDiagnosticsCount: Integer;
    fDiagnosticsJson: string;
  end;

function EnsureSymbolMapCaches(const aContext: TSymbolMapContext; out aStatus: TSymbolMapCacheStatus;
  out aError: string): Boolean;
function EnsureSymbolMapCompilerProfile(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  out aResult: TSymbolMapCompilerProfileResult; out aError: string): Boolean;
function EnsureSymbolMapCompilerProfileForRoot(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aRtlSourceRoot: string; out aResult: TSymbolMapCompilerProfileResult; out aError: string): Boolean;
function IndexSymbolMapRtlSources(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aSourceRoot: string; var aProfile: TSymbolMapCompilerProfileResult; out aResult: TSymbolMapRtlIndexResult;
  out aError: string): Boolean;
function BuildSymbolMapProjectKey(const aContext: TSymbolMapContext): string;
function StoreSymbolMapProjectProjection(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModels: TArray<TSymbolMapUnitModel>; out aResults: TArray<TSymbolMapCacheStoreResult>;
  out aError: string): Boolean;
function StoreSymbolMapUnitProjection(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModel: TSymbolMapUnitModel; out aResult: TSymbolMapCacheStoreResult; out aError: string): Boolean; overload;
function StoreSymbolMapUnitProjection(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModel: TSymbolMapUnitModel; out aError: string): Boolean; overload;

implementation

uses
  System.Classes, System.Generics.Collections, System.Hash, System.IOUtils, System.StrUtils, System.SysUtils,
  System.Variants,
  Winapi.Windows,
  FireDAC.Comp.Client, FireDAC.Phys.SQLite,
  DelphiSemantics.Cache, DelphiSemantics.CompilerProfile, DelphiSemantics.Model,
  DelphiSemantics.Preprocess,
  Dak.RadStudio.Locator;

type
  TSymbolMapIntrinsicSeed = record
    fName: string;
    fKind: string;
    fSignature: string;
    fNotes: string;
  end;

  TCompilerProfileUnitProjection = record
    fUnitName: string;
    fUnitCacheKey: string;
    fFilePath: string;
  end;

const
  cCentralDbFileName = 'symbol-map.sqlite3';
  cProjectDbFileName = 'project-index.sqlite3';
  cCentralCacheMutexPrefix = 'Local\DelphiAIKit.SymbolMap.Cache.';
  cProjectCacheMutexPrefix = 'Local\DelphiAIKit.SymbolMap.ProjectCache.';
  cSymbolMapParserVersion = 'symbol-map-parser-v3';

function StoreSymbolMapUnitProjectionInternal(const aContext: TSymbolMapContext;
  const aStatus: TSymbolMapCacheStatus; const aModel: TSymbolMapUnitModel;
  out aResult: TSymbolMapCacheStoreResult; out aError: string;
  const aLinkProjectUnit: Boolean): Boolean; forward;

function BuildSymbolMapIncludeGraphHash(const aContext: TSymbolMapContext; const aSourceFileName: string):
  string;
var
  lOptions: TDelphiSemanticPreprocessOptions;
  lResult: TDelphiSemanticPreprocessResult;
begin
  lOptions := Default(TDelphiSemanticPreprocessOptions);
  lOptions.SourceFileName := aSourceFileName;
  lOptions.Defines := aContext.fDefines;
  lOptions.SearchPaths := aContext.fUnitSearchPath;
  lResult := TDelphiSemanticPreprocessor.PreprocessFile(lOptions);
  Result := lResult.IncludeGraphHash;
end;

function SemanticIdentityContext(const aContext: TSymbolMapContext; const aIncludeGraphHash: string):
  TDelphiSemanticCacheIdentityContext;
begin
  Result := Default(TDelphiSemanticCacheIdentityContext);
  Result.SchemaVersion := cSymbolMapSchemaVersion.ToString;
  Result.ParserVersion := cSymbolMapParserVersion;
  Result.IncludeGraphHash := aIncludeGraphHash;
  Result.DelphiVersion := aContext.fDelphiVersion;
  Result.Platform := aContext.fPlatform;
  Result.ParserDefines := aContext.fProject.ParserDefines;
  Result.Defines := aContext.fDefines;
  Result.UnitScopes := aContext.fUnitScopes;
  Result.UnitAliases := aContext.fUnitAliases;
  Result.ProjectPath := aContext.fProject.ProjectPath;
  Result.Configuration := aContext.fConfig;
  Result.SearchPaths := aContext.fUnitSearchPath;
  Result.CentralCacheRoot := aContext.fCentralCacheRoot;
end;

function OpenCacheConnection(const aDbPath: string; out aDriverLink: TFDPhysSQLiteDriverLink;
  out aConnection: TFDConnection; out aError: string): Boolean;
begin
  Result := False;
  aError := '';
  aDriverLink := nil;
  aConnection := nil;
  try
    ForceDirectories(TPath.GetDirectoryName(aDbPath));
    aDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
    aConnection := TFDConnection.Create(nil);
    aConnection.LoginPrompt := False;
    aConnection.Params.Values['DriverID'] := 'SQLite';
    aConnection.Params.Values['Database'] := aDbPath;
    aConnection.Connected := True;
    Result := True;
  except
    on E: Exception do
    begin
      aConnection.Free;
      aDriverLink.Free;
      aConnection := nil;
      aDriverLink := nil;
      aError := E.Message;
    end;
  end;
end;

function TryReadSchemaVersion(const aConnection: TFDConnection; out aVersion: string): Boolean;
var
  lValue: Variant;
begin
  aVersion := '';
  lValue := aConnection.ExecSQLScalar('select value_text from meta where key_name = ''schema_version''');
  if VarIsNull(lValue) then
    Exit(True);
  aVersion := VarToStr(lValue);
  Result := True;
end;

procedure EnsureCommonSchema(const aConnection: TFDConnection);
begin
  aConnection.ExecSQL('create table if not exists meta (' +
    'key_name text primary key not null, value_text text not null)');
end;

procedure EnsureCentralSchema(const aConnection: TFDConnection);
begin
  EnsureCommonSchema(aConnection);
  aConnection.ExecSQL('create table if not exists source_files (' +
    'file_hash text primary key not null, size_bytes integer not null, first_seen_utc text not null, ' +
    'last_seen_utc text not null)');
  aConnection.ExecSQL('create table if not exists symbol_map_units (' +
    'unit_cache_key text primary key not null, unit_name text not null, file_hash text not null, ' +
    'file_path_sample text not null, context_hash text not null, parser_version text not null, ' +
    'schema_version integer not null, diagnostics_json text not null, parsed_at_utc text not null)');
  aConnection.ExecSQL('create table if not exists unit_uses (' +
    'unit_cache_key text not null, used_unit_name text not null, section_kind text not null, ' +
    'line_no integer not null, col_no integer not null)');
  aConnection.ExecSQL('create table if not exists symbols (' +
    'unit_cache_key text not null, symbol_id text not null, name text not null, normalized_name text not null, ' +
    'full_name text not null, kind text not null, owner_name text not null, type_name text not null, ' +
    'signature text not null, visibility text not null, section_kind text not null, flags text not null, ' +
    'line_no integer not null, col_no integer not null, end_line_no integer not null, end_col_no integer not null)');
  aConnection.ExecSQL('create table if not exists members (' +
    'unit_cache_key text not null, owner_name text not null, member_name text not null, ' +
    'normalized_member_name text not null, kind text not null, type_name text not null, visibility text not null, ' +
    'is_default integer not null, is_indexed integer not null, line_no integer not null, col_no integer not null)');
  aConnection.ExecSQL('create table if not exists symbol_map_references (' +
    'unit_cache_key text not null, name text not null, normalized_name text not null, role text not null, ' +
    'section_kind text not null, line_no integer not null, col_no integer not null, end_line_no integer not null, ' +
    'end_col_no integer not null)');
  aConnection.ExecSQL('create table if not exists compiler_profiles (' +
    'profile_key text primary key not null, delphi_version text not null, platform text not null, ' +
    'bds_root text not null, source_roots_hash text not null, intrinsic_seed_version text not null, ' +
    'indexed_at_utc text not null)');
  aConnection.ExecSQL('create table if not exists compiler_profile_units (' +
    'profile_key text not null, unit_name text not null, unit_cache_key text not null, file_path_sample text not null, ' +
    'source_kind text not null)');
  aConnection.ExecSQL('create table if not exists compiler_intrinsics (' +
    'profile_key text not null, name text not null, kind text not null, signature text not null, notes text not null)');
  aConnection.ExecSQL('create index if not exists idx_compiler_intrinsics_name on ' +
    'compiler_intrinsics(profile_key, name)');
  aConnection.ExecSQL('create index if not exists idx_symbols_name on symbols(normalized_name)');
  aConnection.ExecSQL('create index if not exists idx_members_name on members(normalized_member_name)');
  aConnection.ExecSQL('create index if not exists idx_symbol_map_references_name on symbol_map_references(normalized_name)');
end;

procedure EnsureProjectSchema(const aConnection: TFDConnection);
begin
  EnsureCommonSchema(aConnection);
  aConnection.ExecSQL('create table if not exists project_context (' +
    'project_key text primary key not null, project_path text not null, config text not null, platform text not null, ' +
    'delphi_version text not null, defines_hash text not null, search_path_hash text not null, ' +
    'unit_scope_hash text not null, alias_hash text not null, central_cache_path text not null, indexed_at_utc text not null)');
  aConnection.ExecSQL('create table if not exists project_units (' +
    'project_key text not null, unit_name text not null, file_path text not null, unit_cache_key text not null, ' +
    'source_kind text not null, resolution_rank integer not null)');
  aConnection.ExecSQL('create table if not exists project_symbols (' +
    'project_key text not null, normalized_name text not null, unit_cache_key text not null, symbol_id text not null, ' +
    'visibility_rank integer not null, source_kind text not null)');
  aConnection.ExecSQL('create index if not exists idx_project_symbols_name on project_symbols(project_key, normalized_name)');
end;

function ValidateSchemaVersion(const aConnection: TFDConnection; out aError: string): Boolean;
var
  lVersion: string;
begin
  Result := False;
  aError := '';
  try
    if not TryReadSchemaVersion(aConnection, lVersion) then
      Exit(False);
    if (lVersion <> '') and (lVersion <> cSymbolMapSchemaVersion.ToString) then
    begin
      aError := 'Unsupported Symbol Map cache schema version: ' + lVersion;
      Exit(False);
    end;
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
end;

procedure WriteSchemaVersion(const aConnection: TFDConnection);
begin
  aConnection.ExecSQL('insert or replace into meta(key_name, value_text) values (''schema_version'', ?)',
    [cSymbolMapSchemaVersion.ToString]);
end;

function EnsureDatabase(const aDbPath: string; const aCentral: Boolean; out aCreated: Boolean;
  out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  Result := False;
  aError := '';
  aCreated := not TFile.Exists(aDbPath);
  if not OpenCacheConnection(aDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    try
      EnsureCommonSchema(lConnection);
      if not ValidateSchemaVersion(lConnection, aError) then
        Exit(False);
      if aCentral then
        EnsureCentralSchema(lConnection)
      else
        EnsureProjectSchema(lConnection);
      WriteSchemaVersion(lConnection);
      Result := True;
    except
      on E: Exception do
        aError := E.Message;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function BuildCacheMutexName(const aPrefix, aDbPath: string): string;
begin
  Result := aPrefix + THashSHA2.GetHashString(LowerCase(TPath.GetFullPath(aDbPath)));
end;

function AcquireCacheMutex(const aDbPath, aPrefix, aDescription: string; out aHandle: THandle;
  out aError: string): Boolean;
var
  lMutexName: string;
  lWaitResult: Cardinal;
begin
  Result := False;
  aError := '';
  lMutexName := BuildCacheMutexName(aPrefix, aDbPath);
  aHandle := CreateMutex(nil, False, PChar(lMutexName));
  if aHandle = 0 then
  begin
    aError := 'Failed to create Symbol Map ' + aDescription + ' mutex: ' + SysErrorMessage(GetLastError);
    Exit(False);
  end;

  lWaitResult := WaitForSingleObject(aHandle, 30000);
  if (lWaitResult = WAIT_OBJECT_0) or (lWaitResult = WAIT_ABANDONED) then
    Exit(True);

  aError := 'Timed out waiting for Symbol Map ' + aDescription + ' mutex: ' + lMutexName;
  CloseHandle(aHandle);
  aHandle := 0;
end;

function AcquireCentralCacheMutex(const aCentralDbPath: string; out aHandle: THandle; out aError: string): Boolean;
begin
  Result := AcquireCacheMutex(aCentralDbPath, cCentralCacheMutexPrefix, 'central cache', aHandle, aError);
end;

function AcquireProjectCacheMutex(const aProjectDbPath: string; out aHandle: THandle; out aError: string): Boolean;
begin
  Result := AcquireCacheMutex(aProjectDbPath, cProjectCacheMutexPrefix, 'project cache', aHandle, aError);
end;

function EnsureSymbolMapCaches(const aContext: TSymbolMapContext; out aStatus: TSymbolMapCacheStatus;
  out aError: string): Boolean;
var
  lMutexHandle: THandle;
  lProjectMutexHandle: THandle;
begin
  Result := False;
  aError := '';
  aStatus := Default(TSymbolMapCacheStatus);
  aStatus.fSchemaVersion := cSymbolMapSchemaVersion;
  aStatus.fCentralDbPath := TPath.Combine(aContext.fCentralCacheRoot, cCentralDbFileName);
  aStatus.fProjectDbPath := TPath.Combine(aContext.fProjectCacheRoot, cProjectDbFileName);

  if not AcquireCentralCacheMutex(aStatus.fCentralDbPath, lMutexHandle, aError) then
    Exit(False);
  try
    if not EnsureDatabase(aStatus.fCentralDbPath, True, aStatus.fCentralCreated, aError) then
      Exit(False);
  finally
    if lMutexHandle <> 0 then
    begin
      ReleaseMutex(lMutexHandle);
      CloseHandle(lMutexHandle);
    end;
  end;

  if not AcquireProjectCacheMutex(aStatus.fProjectDbPath, lProjectMutexHandle, aError) then
    Exit(False);
  try
    if not EnsureDatabase(aStatus.fProjectDbPath, False, aStatus.fProjectCreated, aError) then
      Exit(False);
  finally
    if lProjectMutexHandle <> 0 then
    begin
      ReleaseMutex(lProjectMutexHandle);
      CloseHandle(lProjectMutexHandle);
    end;
  end;

  Result := True;
end;

function BoolToDbInt(const aValue: Boolean): Integer;
begin
  if aValue then
    Result := 1
  else
    Result := 0;
end;

function NormalizeProfilePart(const aValue, aFallback: string): string;
begin
  Result := Trim(aValue);
  if Result = '' then
    Result := aFallback;
end;

function HashBytes(const aBytes: TBytes): string;
var
  lHash: THashSHA2;
begin
  lHash := THashSHA2.Create;
  if Length(aBytes) > 0 then
    lHash.Update(aBytes);
  Result := lHash.HashAsString;
end;

function HashText(const aText: string): string;
begin
  Result := THashSHA2.GetHashString(aText);
end;

function BuildContextHash(const aContext: TSymbolMapContext): string;
begin
  Result := TDelphiSemanticCacheIdentityBuilder.BuildContextHash(SemanticIdentityContext(aContext, ''));
end;

procedure BuildUnitCacheIdentity(const aContext: TSymbolMapContext; const aModel: TSymbolMapUnitModel;
  out aFileHash, aContextHash, aUnitCacheKey: string);
var
  lIdentityContext: TDelphiSemanticCacheIdentityContext;
  lIdentity: TDelphiSemanticUnitCacheIdentity;
begin
  lIdentityContext := SemanticIdentityContext(aContext, BuildSymbolMapIncludeGraphHash(aContext,
    aModel.fFilePath));
  lIdentity := TDelphiSemanticCacheIdentityBuilder.BuildUnitIdentity(aModel.fFilePath, lIdentityContext);
  aFileHash := lIdentity.FileHash;
  aContextHash := lIdentity.ContextHash;
  aUnitCacheKey := lIdentity.UnitCacheKey;
end;

function BuildSymbolMapProjectKey(const aContext: TSymbolMapContext): string;
begin
  Result := TDelphiSemanticCacheIdentityBuilder.BuildProjectIdentity(
    SemanticIdentityContext(aContext, '')).ProjectKey;
end;

procedure AddIntrinsicSeed(var aSeeds: TArray<TSymbolMapIntrinsicSeed>; const aName, aKind, aSignature,
  aNotes: string);
var
  lIndex: Integer;
begin
  lIndex := Length(aSeeds);
  SetLength(aSeeds, lIndex + 1);
  aSeeds[lIndex].fName := aName;
  aSeeds[lIndex].fKind := aKind;
  aSeeds[lIndex].fSignature := aSignature;
  aSeeds[lIndex].fNotes := aNotes;
end;

function BuildIntrinsicSeeds: TArray<TSymbolMapIntrinsicSeed>;
var
  lProfile: TDelphiSemanticCompilerProfile;
  lSymbol: TDelphiSemanticIntrinsicSymbol;

  function LegacyKind(const aKind: string): string;
  begin
    if SameText(aKind, 'intrinsic-routine') then
      Exit('routine');
    if SameText(aKind, 'intrinsic-type') then
      Exit('type');
    if SameText(aKind, 'intrinsic-unit') then
      Exit('unit');
    Result := aKind;
  end;

begin
  SetLength(Result, 0);
  lProfile := TDelphiSemanticCompilerProfileBuilder.ProfileForTarget('', '', '', '');
  for lSymbol in lProfile.IntrinsicSymbols do
    AddIntrinsicSeed(Result, lSymbol.Name, LegacyKind(lSymbol.Kind), lSymbol.Signature,
      lSymbol.Notes);
end;

function BuildSemanticCompilerProfile(const aContext: TSymbolMapContext;
  const aRtlSourceRoot: string; out aDelphiVersion, aPlatform: string):
  TDelphiSemanticCompilerProfile;
var
  lSourceRoot: string;
begin
  aDelphiVersion := NormalizeProfilePart(aContext.fDelphiVersion, 'unknown');
  aPlatform := NormalizeProfilePart(aContext.fPlatform, 'Win32');
  lSourceRoot := LowerCase(Trim(aRtlSourceRoot));
  if lSourceRoot = '' then
    lSourceRoot := LowerCase(Trim(aContext.fRtlSourceRoot));
  Result := TDelphiSemanticCompilerProfileBuilder.ProfileForTarget('', aDelphiVersion,
    aPlatform, lSourceRoot);
end;

function CentralUnitProjectionExists(const aConnection: TFDConnection; const aUnitCacheKey: string): Boolean;
begin
  Result := aConnection.ExecSQLScalar('select count(*) from symbol_map_units where unit_cache_key = ?',
    [aUnitCacheKey]) > 0;
end;

function CentralCompilerProfileExists(const aConnection: TFDConnection; const aProfileKey,
  aIntrinsicSeedVersion: string): Boolean;
begin
  Result := aConnection.ExecSQLScalar(
    'select count(*) from compiler_profiles where profile_key = ? and intrinsic_seed_version = ?',
    [aProfileKey, aIntrinsicSeedVersion]) > 0;
end;

function CountCompilerIntrinsics(const aConnection: TFDConnection; const aProfileKey: string): Integer;
begin
  Result := aConnection.ExecSQLScalar('select count(*) from compiler_intrinsics where profile_key = ?',
    [aProfileKey]);
end;

function CompilerIntrinsicsMatchSeeds(const aConnection: TFDConnection; const aProfileKey: string): Boolean;
var
  lSeed: TSymbolMapIntrinsicSeed;
  lSeeds: TArray<TSymbolMapIntrinsicSeed>;
begin
  lSeeds := BuildIntrinsicSeeds;
  if CountCompilerIntrinsics(aConnection, aProfileKey) <> Length(lSeeds) then
    Exit(False);

  for lSeed in lSeeds do
  begin
    if aConnection.ExecSQLScalar(
      'select count(*) from compiler_intrinsics where profile_key = ? and lower(name) = lower(?) ' +
      'and kind = ? and signature = ? and notes = ?',
      [aProfileKey, lSeed.fName, lSeed.fKind, lSeed.fSignature, lSeed.fNotes]) <> 1 then
      Exit(False);
  end;

  Result := True;
end;

procedure StoreCompilerIntrinsics(const aConnection: TFDConnection; const aProfileKey: string;
  out aIntrinsicCount: Integer);
var
  lSeed: TSymbolMapIntrinsicSeed;
  lSeeds: TArray<TSymbolMapIntrinsicSeed>;
begin
  lSeeds := BuildIntrinsicSeeds;
  aConnection.ExecSQL('delete from compiler_intrinsics where profile_key = ?', [aProfileKey]);
  for lSeed in lSeeds do
  begin
    aConnection.ExecSQL('insert into compiler_intrinsics(profile_key, name, kind, signature, notes) ' +
      'values (?, ?, ?, ?, ?)', [aProfileKey, lSeed.fName, lSeed.fKind, lSeed.fSignature, lSeed.fNotes]);
  end;
  aIntrinsicCount := Length(lSeeds);
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

procedure AddDiagnostic(var aDiagnostics: TArray<string>; const aMessage: string);
var
  lIndex: Integer;
begin
  if aMessage = '' then
    Exit;
  lIndex := Length(aDiagnostics);
  SetLength(aDiagnostics, lIndex + 1);
  aDiagnostics[lIndex] := aMessage;
end;

function DiagnosticsJson(const aDiagnostics: TArray<string>): string;
var
  i: Integer;
begin
  Result := '[';
  for i := 0 to High(aDiagnostics) do
  begin
    if i > 0 then
      Result := Result + ',';
    Result := Result + '"' + JsonEscape(aDiagnostics[i]) + '"';
  end;
  Result := Result + ']';
end;

function DefaultRtlSourceUnits: TArray<string>;
begin
  Result := ['System', 'SysUtils', 'Classes', 'Math', 'Types', 'Variants', 'TypInfo', 'SysInit',
    'UITypes'];
end;

function NormalizeRtlSourceRoot(const aContext: TSymbolMapContext; const aSourceRoot: string): string;
begin
  Result := Trim(aSourceRoot);
  if Result <> '' then
    Exit(TPath.GetFullPath(Result));

  Result := Trim(aContext.fRtlSourceRoot);
  if Result <> '' then
    Exit(TPath.GetFullPath(Result));

  Result := ResolveRtlSourceRoot(aContext.fDelphiVersion, aContext.fRsVarsPath);
  if Result <> '' then
    Result := TPath.GetFullPath(Result);
end;

function CollectRtlSourceFiles(const aSourceRoot: string; out aDiagnostics: TArray<string>): TArray<string>;
var
  lRtlRoot: string;
begin
  SetLength(Result, 0);
  SetLength(aDiagnostics, 0);
  lRtlRoot := TPath.Combine(aSourceRoot, 'rtl');
  if not TDirectory.Exists(lRtlRoot) then
  begin
    AddDiagnostic(aDiagnostics, 'missing-rtl-source-root: ' + lRtlRoot);
    Exit;
  end;

  Result := TDelphiSemanticCompilerProfileBuilder.DiscoverRtlSourceFiles(aSourceRoot,
    DefaultRtlSourceUnits);
end;

function EnsureSymbolMapCompilerProfile(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  out aResult: TSymbolMapCompilerProfileResult; out aError: string): Boolean;
begin
  Result := EnsureSymbolMapCompilerProfileForRoot(aContext, aStatus, aContext.fRtlSourceRoot, aResult, aError);
end;

function EnsureSymbolMapCompilerProfileForRoot(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aRtlSourceRoot: string; out aResult: TSymbolMapCompilerProfileResult; out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lMutexHandle: THandle;
  lProfile: TDelphiSemanticCompilerProfile;
begin
  Result := False;
  aResult := Default(TSymbolMapCompilerProfileResult);
  aError := '';
  lProfile := BuildSemanticCompilerProfile(aContext, aRtlSourceRoot, aResult.fDelphiVersion,
    aResult.fPlatform);
  aResult.fIntrinsicSeedVersion := lProfile.IntrinsicSeedVersion;
  aResult.fProfileKey := lProfile.ProfileKey;
  if not AcquireCentralCacheMutex(aStatus.fCentralDbPath, lMutexHandle, aError) then
    Exit(False);
  try
    if not OpenCacheConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
      Exit(False);
    try
      try
        aResult.fCacheHit := CentralCompilerProfileExists(lConnection, aResult.fProfileKey,
          aResult.fIntrinsicSeedVersion) and
          CompilerIntrinsicsMatchSeeds(lConnection, aResult.fProfileKey);
        if aResult.fCacheHit then
        begin
          aResult.fIntrinsicCount := CountCompilerIntrinsics(lConnection, aResult.fProfileKey);
          Exit(True);
        end;

        lConnection.StartTransaction;
        try
          StoreCompilerIntrinsics(lConnection, aResult.fProfileKey, aResult.fIntrinsicCount);
          lConnection.ExecSQL('insert or replace into compiler_profiles(' +
            'profile_key, delphi_version, platform, bds_root, source_roots_hash, intrinsic_seed_version, ' +
            'indexed_at_utc) values (?, ?, ?, ?, ?, ?, ?)',
            [aResult.fProfileKey, aResult.fDelphiVersion, aResult.fPlatform, '', 'none',
            aResult.fIntrinsicSeedVersion, DateTimeToStr(Now)]);
          lConnection.Commit;
        except
          lConnection.Rollback;
          raise;
        end;
        Result := True;
      except
        on E: Exception do
          aError := E.Message;
      end;
    finally
      lConnection.Free;
      lDriverLink.Free;
    end;
  finally
    if lMutexHandle <> 0 then
    begin
      ReleaseMutex(lMutexHandle);
      CloseHandle(lMutexHandle);
    end;
  end;
end;

function CompilerProfileUnitCount(const aConnection: TFDConnection; const aProfileKey: string): Integer;
begin
  Result := aConnection.ExecSQLScalar('select count(*) from compiler_profile_units where profile_key = ?',
    [aProfileKey]);
end;

function CompilerProfileSourceRootsHash(const aConnection: TFDConnection; const aProfileKey: string): string;
begin
  Result := VarToStr(aConnection.ExecSQLScalar(
    'select source_roots_hash from compiler_profiles where profile_key = ?', [aProfileKey]));
end;

function BuildRtlSourceRootsHash(const aSourceRoot: string; const aUnitFiles: TArray<string>): string;
var
  lBuilder: TStringBuilder;
  lFile: string;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine(TPath.GetFullPath(aSourceRoot));
    for lFile in aUnitFiles do
      lBuilder.AppendLine(TPath.GetFileName(lFile) + '=' + HashBytes(TFile.ReadAllBytes(lFile)));
    Result := HashText(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

procedure ClearCompilerProfileUnits(const aConnection: TFDConnection; const aProfileKey: string);
begin
  aConnection.ExecSQL('delete from compiler_profile_units where profile_key = ?', [aProfileKey]);
end;

procedure UpdateCompilerProfileSourceRootsHash(const aConnection: TFDConnection; const aProfileKey,
  aSourceRootsHash: string);
begin
  aConnection.ExecSQL('update compiler_profiles set source_roots_hash = ?, indexed_at_utc = ? where profile_key = ?',
    [aSourceRootsHash, DateTimeToStr(Now), aProfileKey]);
end;

procedure InsertCompilerProfileUnit(const aConnection: TFDConnection; const aProfileKey, aUnitName,
  aUnitCacheKey, aFilePath: string);
begin
  aConnection.ExecSQL('insert into compiler_profile_units(profile_key, unit_name, unit_cache_key, ' +
    'file_path_sample, source_kind) values (?, ?, ?, ?, ?)',
    [aProfileKey, aUnitName, aUnitCacheKey, aFilePath, 'rtl-source']);
end;

procedure StoreCompilerProfileUnit(const aStatus: TSymbolMapCacheStatus; const aProfileKey: string;
  const aUnitModel: TSymbolMapUnitModel; const aUnitCacheKey: string);
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lError: string;
  lMutexHandle: THandle;
begin
  if not AcquireCentralCacheMutex(aStatus.fCentralDbPath, lMutexHandle, lError) then
    raise Exception.Create(lError);
  try
    if not OpenCacheConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, lError) then
      raise Exception.Create(lError);
    try
      InsertCompilerProfileUnit(lConnection, aProfileKey, aUnitModel.fUnitName, aUnitCacheKey,
        aUnitModel.fFilePath);
    finally
      lConnection.Free;
      lDriverLink.Free;
    end;
  finally
    if lMutexHandle <> 0 then
    begin
      ReleaseMutex(lMutexHandle);
      CloseHandle(lMutexHandle);
    end;
  end;
end;

function IndexSymbolMapRtlSources(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aSourceRoot: string; var aProfile: TSymbolMapCompilerProfileResult; out aResult: TSymbolMapRtlIndexResult;
  out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lCache: TDelphiSemanticUnitCache;
  lCacheOptions: TDelphiSemanticCacheOptions;
  lDiagnostics: TArray<string>;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lExistingCount: Integer;
  lModel: TSymbolMapUnitModel;
  lMutexHandle: THandle;
  lProfileUnit: TCompilerProfileUnitProjection;
  lProfileUnits: TArray<TCompilerProfileUnitProjection>;
  lProfileModels: TDelphiSemanticCompilerProfile;
  lRoot: string;
  lRtlContext: TSymbolMapContext;
  lSemanticModel: TDelphiSemanticUnitModel;
  lSourceRootsHash: string;
  lStoredSourceRootsHash: string;
  lStoreResult: TSymbolMapCacheStoreResult;
  lUnitFiles: TArray<string>;
begin
  Result := False;
  aResult := Default(TSymbolMapRtlIndexResult);
  aError := '';
  lRoot := NormalizeRtlSourceRoot(aContext, aSourceRoot);
  aResult.fSourceRoot := lRoot;
  if not EnsureSymbolMapCompilerProfileForRoot(aContext, aStatus, lRoot, aProfile, aError) then
    Exit(False);
  lRtlContext := aContext.WithRtlSourceRoot(lRoot);
  lMutexHandle := 0;
  try
    lUnitFiles := CollectRtlSourceFiles(lRoot, lDiagnostics);
    aResult.fDiagnosticsJson := DiagnosticsJson(lDiagnostics);
    aResult.fDiagnosticsCount := Length(lDiagnostics);
    aResult.fUnitsDiscovered := Length(lUnitFiles);
    if Length(lUnitFiles) = 0 then
    begin
      if aResult.fDiagnosticsCount > 0 then
        aResult.fStatus := 'missing-source-root'
      else
        aResult.fStatus := 'no-rtl-units';
      Exit(True);
    end;

    lSourceRootsHash := BuildRtlSourceRootsHash(lRoot, lUnitFiles);
    if not AcquireCentralCacheMutex(aStatus.fCentralDbPath, lMutexHandle, aError) then
      Exit(False);
    try
      if not OpenCacheConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
        Exit(False);
      try
        lExistingCount := CompilerProfileUnitCount(lConnection, aProfile.fProfileKey);
        lStoredSourceRootsHash := CompilerProfileSourceRootsHash(lConnection, aProfile.fProfileKey);
      finally
        lConnection.Free;
        lDriverLink.Free;
      end;
    finally
      if lMutexHandle <> 0 then
      begin
        ReleaseMutex(lMutexHandle);
        CloseHandle(lMutexHandle);
        lMutexHandle := 0;
      end;
    end;
    aResult.fCacheHit := (lExistingCount = Length(lUnitFiles)) and (lStoredSourceRootsHash = lSourceRootsHash);
    if aResult.fCacheHit then
    begin
      aResult.fStatus := 'cache-hit';
      aResult.fUnitsIndexed := lExistingCount;
      aResult.fUnitCacheHits := lExistingCount;
      Exit(True);
    end;

    lCacheOptions := Default(TDelphiSemanticCacheOptions);
    lCacheOptions.CompilerProfileName := aProfile.fProfileKey;
    lCache := TDelphiSemanticUnitCache.Create(lCacheOptions);
    try
      lProfileModels := TDelphiSemanticCompilerProfileBuilder.ProfileForTargetFromRtlSourceRoot(
        lCache, aProfile.fProfileKey, aProfile.fDelphiVersion, aProfile.fPlatform, lRoot,
        DefaultRtlSourceUnits);
    finally
      lCache.Free;
    end;

    for lSemanticModel in lProfileModels.RtlSourceUnitModels do
    begin
      lModel := SymbolMapUnitModelFromDelphiSemanticModel(lSemanticModel);
      if not StoreSymbolMapUnitProjectionInternal(lRtlContext, aStatus, lModel, lStoreResult, aError, True) then
        Exit(False);
      if lStoreResult.fCacheHit then
        Inc(aResult.fUnitCacheHits)
      else
        Inc(aResult.fUnitCacheMisses);
      lProfileUnit.fUnitName := lModel.fUnitName;
      lProfileUnit.fUnitCacheKey := lStoreResult.fUnitCacheKey;
      lProfileUnit.fFilePath := lModel.fFilePath;
      SetLength(lProfileUnits, Length(lProfileUnits) + 1);
      lProfileUnits[High(lProfileUnits)] := lProfileUnit;
      Inc(aResult.fUnitsIndexed);
    end;
    if not AcquireCentralCacheMutex(aStatus.fCentralDbPath, lMutexHandle, aError) then
      Exit(False);
    try
      if not OpenCacheConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
        Exit(False);
      try
        lConnection.StartTransaction;
        try
          ClearCompilerProfileUnits(lConnection, aProfile.fProfileKey);
          for lProfileUnit in lProfileUnits do
            InsertCompilerProfileUnit(lConnection, aProfile.fProfileKey, lProfileUnit.fUnitName,
              lProfileUnit.fUnitCacheKey, lProfileUnit.fFilePath);
          UpdateCompilerProfileSourceRootsHash(lConnection, aProfile.fProfileKey, lSourceRootsHash);
          lConnection.Commit;
        except
          lConnection.Rollback;
          raise;
        end;
      finally
        lConnection.Free;
        lDriverLink.Free;
      end;
    finally
      if lMutexHandle <> 0 then
      begin
        ReleaseMutex(lMutexHandle);
        CloseHandle(lMutexHandle);
        lMutexHandle := 0;
      end;
    end;
    aResult.fStatus := 'indexed';
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
end;

procedure StoreUnitUses(const aConnection: TFDConnection; const aUnitCacheKey: string;
  const aModel: TSymbolMapUnitModel);
var
  lUse: TSymbolMapUnitUse;
begin
  aConnection.ExecSQL('delete from unit_uses where unit_cache_key = ?', [aUnitCacheKey]);
  for lUse in aModel.fUses do
  begin
    aConnection.ExecSQL('insert into unit_uses(unit_cache_key, used_unit_name, section_kind, line_no, col_no) ' +
      'values (?, ?, ?, ?, ?)', [aUnitCacheKey, lUse.fUnitName, lUse.fSectionKind, lUse.fLine, lUse.fCol]);
  end;
end;

procedure StoreSymbols(const aConnection: TFDConnection; const aUnitCacheKey: string;
  const aModel: TSymbolMapUnitModel);
var
  i: Integer;
  lFullName: string;
  lSymbol: TSymbolMapSymbolModel;
begin
  aConnection.ExecSQL('delete from symbols where unit_cache_key = ?', [aUnitCacheKey]);
  for i := 0 to High(aModel.fSymbols) do
  begin
    lSymbol := aModel.fSymbols[i];
    if lSymbol.fOwnerName <> '' then
      lFullName := lSymbol.fOwnerName + '.' + lSymbol.fName
    else
      lFullName := lSymbol.fName;
    aConnection.ExecSQL('insert into symbols(' +
      'unit_cache_key, symbol_id, name, normalized_name, full_name, kind, owner_name, type_name, signature, ' +
      'visibility, section_kind, flags, line_no, col_no, end_line_no, end_col_no) ' +
      'values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [aUnitCacheKey, aUnitCacheKey + ':' + i.ToString, lSymbol.fName, LowerCase(lSymbol.fName), lFullName,
      lSymbol.fKind, lSymbol.fOwnerName, lSymbol.fTypeName, lSymbol.fSignature, '', lSymbol.fSectionKind, '',
      lSymbol.fLine, lSymbol.fCol, lSymbol.fEndLine, lSymbol.fEndCol]);
  end;
end;

procedure StoreUnitReferences(const aConnection: TFDConnection; const aUnitCacheKey: string;
  const aModel: TSymbolMapUnitModel);
var
  lReference: TSymbolMapReferenceModel;
begin
  aConnection.ExecSQL('delete from symbol_map_references where unit_cache_key = ?', [aUnitCacheKey]);
  for lReference in aModel.fReferences do
  begin
    aConnection.ExecSQL('insert into symbol_map_references(' +
      'unit_cache_key, name, normalized_name, role, section_kind, line_no, col_no, end_line_no, end_col_no) ' +
      'values (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [aUnitCacheKey, lReference.fName, LowerCase(lReference.fName), lReference.fRole, lReference.fSectionKind,
      lReference.fLine, lReference.fCol, lReference.fEndLine, lReference.fEndCol]);
  end;
end;

procedure StoreProjectContextRow(const aConnection: TFDConnection; const aContext: TSymbolMapContext;
  const aStatus: TSymbolMapCacheStatus; const aProjectIdentity: TDelphiSemanticProjectCacheIdentity;
  const aProjectKey: string);
begin
  aConnection.ExecSQL('insert or replace into project_context(' +
    'project_key, project_path, config, platform, delphi_version, defines_hash, search_path_hash, ' +
    'unit_scope_hash, alias_hash, central_cache_path, indexed_at_utc) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [aProjectKey, aContext.fProject.ProjectPath, aContext.fConfig, aContext.fPlatform,
    aContext.fDelphiVersion, aProjectIdentity.DefinesHash, aProjectIdentity.SearchPathHash,
    aProjectIdentity.UnitScopeHash, aProjectIdentity.AliasHash, aStatus.fCentralDbPath, DateTimeToStr(Now)]);
end;

procedure InsertProjectUnitRows(const aConnection: TFDConnection; const aProjectKey: string;
  const aModel: TSymbolMapUnitModel; const aUnitCacheKey: string);
var
  i: Integer;
  lSymbol: TSymbolMapSymbolModel;
  lVisibilityRank: Integer;
begin
  aConnection.ExecSQL('insert into project_units(' +
    'project_key, unit_name, file_path, unit_cache_key, source_kind, resolution_rank) values (?, ?, ?, ?, ?, ?)',
    [aProjectKey, aModel.fUnitName, aModel.fFilePath, aUnitCacheKey, 'project', 0]);
  for i := 0 to High(aModel.fSymbols) do
  begin
    lSymbol := aModel.fSymbols[i];
    if SameText(lSymbol.fSectionKind, 'interface') then
      lVisibilityRank := 0
    else
      lVisibilityRank := 1;
    aConnection.ExecSQL('insert into project_symbols(' +
      'project_key, normalized_name, unit_cache_key, symbol_id, visibility_rank, source_kind) ' +
      'values (?, ?, ?, ?, ?, ?)',
      [aProjectKey, LowerCase(lSymbol.fName), aUnitCacheKey, aUnitCacheKey + ':' + i.ToString,
      lVisibilityRank, 'project']);
  end;
end;

procedure StoreProjectUnitReference(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModel: TSymbolMapUnitModel; const aUnitCacheKey: string; out aError: string);
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lProjectIdentity: TDelphiSemanticProjectCacheIdentity;
  lProjectKey: string;
  lProjectMutexHandle: THandle;
begin
  if not AcquireProjectCacheMutex(aStatus.fProjectDbPath, lProjectMutexHandle, aError) then
    raise Exception.Create(aError);
  try
    if not OpenCacheConnection(aStatus.fProjectDbPath, lDriverLink, lConnection, aError) then
      raise Exception.Create(aError);
    try
      lProjectIdentity := TDelphiSemanticCacheIdentityBuilder.BuildProjectIdentity(
        SemanticIdentityContext(aContext, ''));
      lProjectKey := lProjectIdentity.ProjectKey;
      lConnection.StartTransaction;
      try
        StoreProjectContextRow(lConnection, aContext, aStatus, lProjectIdentity, lProjectKey);
        lConnection.ExecSQL('delete from project_symbols where project_key = ? and unit_cache_key in ' +
          '(select unit_cache_key from project_units where project_key = ? and file_path = ?)',
          [lProjectKey, lProjectKey, aModel.fFilePath]);
        lConnection.ExecSQL('delete from project_units where project_key = ? and file_path = ?',
          [lProjectKey, aModel.fFilePath]);
        InsertProjectUnitRows(lConnection, lProjectKey, aModel, aUnitCacheKey);
        lConnection.Commit;
      except
        lConnection.Rollback;
        raise;
      end;
    finally
      lConnection.Free;
      lDriverLink.Free;
    end;
  finally
    if lProjectMutexHandle <> 0 then
    begin
      ReleaseMutex(lProjectMutexHandle);
      CloseHandle(lProjectMutexHandle);
    end;
  end;
end;

function StoreSymbolMapUnitProjectionInternal(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModel: TSymbolMapUnitModel; out aResult: TSymbolMapCacheStoreResult; out aError: string;
  const aLinkProjectUnit: Boolean): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lMember: TSymbolMapMemberModel;
  lMutexHandle: THandle;
  lUnitCacheKey: string;
begin
  Result := False;
  aResult := Default(TSymbolMapCacheStoreResult);
  aError := '';
  BuildUnitCacheIdentity(aContext, aModel, aResult.fFileHash, aResult.fContextHash, aResult.fUnitCacheKey);
  lUnitCacheKey := aResult.fUnitCacheKey;
  if not AcquireCentralCacheMutex(aStatus.fCentralDbPath, lMutexHandle, aError) then
    Exit(False);
  try
    if not OpenCacheConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
      Exit(False);
    try
      try
        aResult.fCacheHit := CentralUnitProjectionExists(lConnection, lUnitCacheKey);
        if not aResult.fCacheHit then
        begin
          lConnection.StartTransaction;
          try
            lConnection.ExecSQL('insert or replace into source_files(' +
              'file_hash, size_bytes, first_seen_utc, last_seen_utc) values (?, ?, ?, ?)',
              [aResult.fFileHash, TFile.GetSize(aModel.fFilePath), DateTimeToStr(Now), DateTimeToStr(Now)]);
            StoreUnitUses(lConnection, lUnitCacheKey, aModel);
            StoreSymbols(lConnection, lUnitCacheKey, aModel);
            StoreUnitReferences(lConnection, lUnitCacheKey, aModel);
            lConnection.ExecSQL('delete from members where unit_cache_key = ?', [lUnitCacheKey]);
            for lMember in aModel.fMembers do
            begin
              lConnection.ExecSQL('insert into members(' +
                'unit_cache_key, owner_name, member_name, normalized_member_name, kind, type_name, visibility, ' +
                'is_default, is_indexed, line_no, col_no) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                [lUnitCacheKey, lMember.fOwnerName, lMember.fMemberName, LowerCase(lMember.fMemberName),
                lMember.fKind, lMember.fTypeName, lMember.fVisibility, BoolToDbInt(lMember.fIsDefault),
                BoolToDbInt(lMember.fIsIndexed), lMember.fLine, lMember.fCol]);
            end;
            lConnection.ExecSQL('insert into symbol_map_units(' +
              'unit_cache_key, unit_name, file_hash, file_path_sample, context_hash, parser_version, ' +
              'schema_version, diagnostics_json, parsed_at_utc) values (?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [lUnitCacheKey, aModel.fUnitName, aResult.fFileHash, aModel.fFilePath, aResult.fContextHash,
              cSymbolMapParserVersion, cSymbolMapSchemaVersion, '', DateTimeToStr(Now)]);
            lConnection.Commit;
          except
            lConnection.Rollback;
            raise;
          end;
        end;
      except
        on E: Exception do
        begin
          aError := E.Message;
          Exit(False);
        end;
      end;
    finally
      lConnection.Free;
      lDriverLink.Free;
    end;
  finally
    if lMutexHandle <> 0 then
    begin
      ReleaseMutex(lMutexHandle);
      CloseHandle(lMutexHandle);
    end;
  end;

  if aLinkProjectUnit then
  begin
    try
      StoreProjectUnitReference(aContext, aStatus, aModel, lUnitCacheKey, aError);
      Result := True;
    except
      on E: Exception do
        aError := E.Message;
    end;
  end else begin
    Result := True;
  end;
end;

function StoreSymbolMapProjectProjection(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModels: TArray<TSymbolMapUnitModel>; out aResults: TArray<TSymbolMapCacheStoreResult>;
  out aError: string): Boolean;
var
  i: Integer;
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lProjectIdentity: TDelphiSemanticProjectCacheIdentity;
  lProjectKey: string;
  lProjectMutexHandle: THandle;
begin
  Result := False;
  aError := '';
  SetLength(aResults, Length(aModels));
  for i := 0 to High(aModels) do
    if not StoreSymbolMapUnitProjectionInternal(aContext, aStatus, aModels[i], aResults[i], aError, False) then
      Exit(False);

  lProjectMutexHandle := 0;
  if not AcquireProjectCacheMutex(aStatus.fProjectDbPath, lProjectMutexHandle, aError) then
    Exit(False);
  try
    if not OpenCacheConnection(aStatus.fProjectDbPath, lDriverLink, lConnection, aError) then
      Exit(False);
    try
      lProjectIdentity := TDelphiSemanticCacheIdentityBuilder.BuildProjectIdentity(
        SemanticIdentityContext(aContext, ''));
      lProjectKey := lProjectIdentity.ProjectKey;
      lConnection.StartTransaction;
      try
        StoreProjectContextRow(lConnection, aContext, aStatus, lProjectIdentity, lProjectKey);
        lConnection.ExecSQL('delete from project_symbols where project_key = ?', [lProjectKey]);
        lConnection.ExecSQL('delete from project_units where project_key = ?', [lProjectKey]);
        for i := 0 to High(aModels) do
          InsertProjectUnitRows(lConnection, lProjectKey, aModels[i], aResults[i].fUnitCacheKey);
        lConnection.Commit;
        Result := True;
      except
        on E: Exception do
        begin
          lConnection.Rollback;
          aError := E.Message;
        end;
      end;
    finally
      lConnection.Free;
      lDriverLink.Free;
    end;
  finally
    if lProjectMutexHandle <> 0 then
    begin
      ReleaseMutex(lProjectMutexHandle);
      CloseHandle(lProjectMutexHandle);
    end;
  end;
end;

function StoreSymbolMapUnitProjection(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModel: TSymbolMapUnitModel; out aResult: TSymbolMapCacheStoreResult; out aError: string): Boolean;
begin
  Result := StoreSymbolMapUnitProjectionInternal(aContext, aStatus, aModel, aResult, aError, True);
end;

function StoreSymbolMapUnitProjection(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModel: TSymbolMapUnitModel; out aError: string): Boolean;
var
  lResult: TSymbolMapCacheStoreResult;
begin
  Result := StoreSymbolMapUnitProjection(aContext, aStatus, aModel, lResult, aError);
end;

end.
