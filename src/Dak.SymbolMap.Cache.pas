unit Dak.SymbolMap.Cache;

interface

uses
  Dak.SymbolMap.Context, Dak.SymbolMap.Indexer;

const
  cSymbolMapSchemaVersion = 1;

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

function EnsureSymbolMapCaches(const aContext: TSymbolMapContext; out aStatus: TSymbolMapCacheStatus;
  out aError: string): Boolean;
function StoreSymbolMapUnitModel(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModel: TSymbolMapUnitModel; out aResult: TSymbolMapCacheStoreResult; out aError: string): Boolean; overload;
function StoreSymbolMapUnitModel(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModel: TSymbolMapUnitModel; out aError: string): Boolean; overload;

implementation

uses
  System.Classes, System.Hash, System.IOUtils, System.SysUtils, System.Variants,
  Winapi.Windows,
  FireDAC.Comp.Client, FireDAC.Phys.SQLite;

const
  cCentralDbFileName = 'symbol-map.sqlite3';
  cProjectDbFileName = 'project-index.sqlite3';
  cCentralCacheMutexName = 'Local\DelphiAIKit.SymbolMap.Cache.v1';
  cSymbolMapParserVersion = 'symbol-map-parser-v1';
  cSymbolMapIncludeGraphHash = 'no-includes-v1';

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
  aConnection.ExecSQL('create table if not exists unit_models (' +
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
  aConnection.ExecSQL('create table if not exists compiler_profiles (' +
    'profile_key text primary key not null, delphi_version text not null, platform text not null, ' +
    'bds_root text not null, source_roots_hash text not null, intrinsic_seed_version text not null, ' +
    'indexed_at_utc text not null)');
  aConnection.ExecSQL('create table if not exists compiler_profile_units (' +
    'profile_key text not null, unit_name text not null, unit_cache_key text not null, source_kind text not null)');
  aConnection.ExecSQL('create table if not exists compiler_intrinsics (' +
    'profile_key text not null, name text not null, kind text not null, signature text not null, notes text not null)');
  aConnection.ExecSQL('create index if not exists idx_symbols_name on symbols(normalized_name)');
  aConnection.ExecSQL('create index if not exists idx_members_name on members(normalized_member_name)');
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

function AcquireCentralCacheMutex(out aHandle: THandle; out aError: string): Boolean;
var
  lWaitResult: Cardinal;
begin
  Result := False;
  aError := '';
  aHandle := CreateMutex(nil, False, cCentralCacheMutexName);
  if aHandle = 0 then
  begin
    aError := 'Failed to create Symbol Map cache mutex: ' + SysErrorMessage(GetLastError);
    Exit(False);
  end;

  lWaitResult := WaitForSingleObject(aHandle, 30000);
  if (lWaitResult = WAIT_OBJECT_0) or (lWaitResult = WAIT_ABANDONED) then
    Exit(True);

  aError := 'Timed out waiting for Symbol Map cache mutex.';
  CloseHandle(aHandle);
  aHandle := 0;
end;

function EnsureSymbolMapCaches(const aContext: TSymbolMapContext; out aStatus: TSymbolMapCacheStatus;
  out aError: string): Boolean;
var
  lMutexHandle: THandle;
begin
  Result := False;
  aError := '';
  aStatus := Default(TSymbolMapCacheStatus);
  aStatus.fSchemaVersion := cSymbolMapSchemaVersion;
  aStatus.fCentralDbPath := TPath.Combine(aContext.fCentralCacheRoot, cCentralDbFileName);
  aStatus.fProjectDbPath := TPath.Combine(aContext.fProjectCacheRoot, cProjectDbFileName);

  if not AcquireCentralCacheMutex(lMutexHandle, aError) then
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

  if not EnsureDatabase(aStatus.fProjectDbPath, False, aStatus.fProjectCreated, aError) then
    Exit(False);

  Result := True;
end;

function BoolToDbInt(const aValue: Boolean): Integer;
begin
  if aValue then
    Result := 1
  else
    Result := 0;
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

function NormalizeStringArray(const aValues: TArray<string>; const aSortValues: Boolean): string;
var
  lList: TStringList;
  lNormalized: string;
  lValue: string;
begin
  lList := TStringList.Create;
  try
    lList.CaseSensitive := False;
    lList.Sorted := aSortValues;
    if aSortValues then
      lList.Duplicates := dupIgnore;
    for lValue in aValues do
    begin
      lNormalized := LowerCase(Trim(lValue));
      if lNormalized <> '' then
        lList.Add(lNormalized);
    end;
    Result := lList.Text;
  finally
    lList.Free;
  end;
end;

function NormalizeDefines(const aDefines: TArray<string>; const aParserDefines: string): string;
var
  lParserDefines: TArray<string>;
begin
  if Length(aDefines) > 0 then
    Exit(NormalizeStringArray(aDefines, True));

  lParserDefines := aParserDefines.Split([';']);
  Result := NormalizeStringArray(lParserDefines, True);
end;

function BuildContextHash(const aContext: TSymbolMapContext): string;
var
  lBuilder: TStringBuilder;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('schema=' + cSymbolMapSchemaVersion.ToString);
    lBuilder.AppendLine('parser=' + cSymbolMapParserVersion);
    lBuilder.AppendLine('includeGraph=' + cSymbolMapIncludeGraphHash);
    lBuilder.AppendLine('delphi=' + LowerCase(Trim(aContext.fDelphiVersion)));
    lBuilder.AppendLine('platform=' + LowerCase(Trim(aContext.fPlatform)));
    lBuilder.AppendLine('defines=' + NormalizeDefines(aContext.fDefines, aContext.fProject.fParserDefines));
    lBuilder.AppendLine('unitScopes=' + NormalizeStringArray(aContext.fUnitScopes, False));
    lBuilder.AppendLine('unitAliases=' + NormalizeStringArray(aContext.fUnitAliases, False));
    Result := HashText(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

procedure BuildUnitCacheIdentity(const aContext: TSymbolMapContext; const aModel: TSymbolMapUnitModel;
  out aFileHash, aContextHash, aUnitCacheKey: string);
var
  lBytes: TBytes;
begin
  lBytes := TFile.ReadAllBytes(aModel.fFilePath);
  aFileHash := HashBytes(lBytes);
  aContextHash := BuildContextHash(aContext);
  aUnitCacheKey := HashText('unit|' + cSymbolMapSchemaVersion.ToString + '|' + cSymbolMapParserVersion + '|' +
    aFileHash + '|' + cSymbolMapIncludeGraphHash + '|' + aContextHash);
end;

function CentralUnitModelExists(const aConnection: TFDConnection; const aUnitCacheKey: string): Boolean;
begin
  Result := aConnection.ExecSQLScalar('select count(*) from unit_models where unit_cache_key = ?',
    [aUnitCacheKey]) > 0;
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

function StoreSymbolMapUnitModel(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModel: TSymbolMapUnitModel; out aResult: TSymbolMapCacheStoreResult; out aError: string): Boolean;
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
  if not AcquireCentralCacheMutex(lMutexHandle, aError) then
    Exit(False);
  try
  if not OpenCacheConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    try
      aResult.fCacheHit := CentralUnitModelExists(lConnection, lUnitCacheKey);
      if aResult.fCacheHit then
        Exit(True);
      lConnection.StartTransaction;
      try
        lConnection.ExecSQL('insert or replace into source_files(' +
          'file_hash, size_bytes, first_seen_utc, last_seen_utc) values (?, ?, ?, ?)',
          [aResult.fFileHash, TFile.GetSize(aModel.fFilePath), DateTimeToStr(Now), DateTimeToStr(Now)]);
        StoreUnitUses(lConnection, lUnitCacheKey, aModel);
        StoreSymbols(lConnection, lUnitCacheKey, aModel);
        lConnection.ExecSQL('delete from members where unit_cache_key = ?', [lUnitCacheKey]);
        for lMember in aModel.fMembers do
        begin
          lConnection.ExecSQL('insert into members(' +
            'unit_cache_key, owner_name, member_name, normalized_member_name, kind, type_name, visibility, ' +
            'is_default, is_indexed, line_no, col_no) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [lUnitCacheKey, lMember.fOwnerName, lMember.fMemberName, LowerCase(lMember.fMemberName), lMember.fKind,
            lMember.fTypeName, lMember.fVisibility, BoolToDbInt(lMember.fIsDefault),
            BoolToDbInt(lMember.fIsIndexed), lMember.fLine, lMember.fCol]);
        end;
        lConnection.ExecSQL('insert into unit_models(' +
          'unit_cache_key, unit_name, file_hash, file_path_sample, context_hash, parser_version, schema_version, ' +
          'diagnostics_json, parsed_at_utc) values (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [lUnitCacheKey, aModel.fUnitName, aResult.fFileHash, aModel.fFilePath, aResult.fContextHash,
          cSymbolMapParserVersion, cSymbolMapSchemaVersion, '', DateTimeToStr(Now)]);
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

function StoreSymbolMapUnitModel(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aModel: TSymbolMapUnitModel; out aError: string): Boolean;
var
  lResult: TSymbolMapCacheStoreResult;
begin
  Result := StoreSymbolMapUnitModel(aContext, aStatus, aModel, lResult, aError);
end;

end.
