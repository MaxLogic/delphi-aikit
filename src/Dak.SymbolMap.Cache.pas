unit Dak.SymbolMap.Cache;

interface

uses
  Dak.SymbolMap.Context;

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

function EnsureSymbolMapCaches(const aContext: TSymbolMapContext; out aStatus: TSymbolMapCacheStatus;
  out aError: string): Boolean;

implementation

uses
  System.IOUtils, System.SysUtils, System.Variants,
  Winapi.Windows,
  FireDAC.Comp.Client, FireDAC.Phys.SQLite;

const
  cCentralDbFileName = 'symbol-map.sqlite3';
  cProjectDbFileName = 'project-index.sqlite3';
  cCentralCacheMutexName = 'Local\DelphiAIKit.SymbolMap.Cache.v1';

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

end.
