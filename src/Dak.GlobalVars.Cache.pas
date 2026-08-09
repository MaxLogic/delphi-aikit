unit Dak.GlobalVars.Cache;

interface

uses
  System.Generics.Collections,
  Dak.GlobalVars.Model,
  Dak.Semantics.Session;

const
  cGlobalVarsCacheSchemaVersion = '5';
  cGlobalVarsCacheBusyTimeoutMs = 30000;

type
  TGlobalVarsCacheLoadFilter = record
    HasUnitFilter: Boolean;
    UnitFilter: string;
    HasNameFilter: Boolean;
    NameFilter: string;
    UnusedOnly: Boolean;
    ReadsOnly: Boolean;
    WritesOnly: Boolean;
  end;

procedure SaveCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  const aIdentities: TArray<TDakSemanticUnitCacheIdentity>;
  const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>;
  const aRejectedImpossibleDeclarations: Integer = 0); overload;

procedure SaveCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  const aIdentities: TArray<TDakSemanticUnitCacheIdentity>;
  const aProject: TProjectInfo; const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>;
  const aRejectedImpossibleDeclarations: Integer = 0); overload;

function TryLoadCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  out aSymbols: TObjectList<TGlobalVarSymbol>;
  out aAmbiguities: TList<TGlobalVarAmbiguity>): Boolean; overload;

function TryLoadCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  const aFilter: TGlobalVarsCacheLoadFilter;
  out aSymbols: TObjectList<TGlobalVarSymbol>;
  out aAmbiguities: TList<TGlobalVarAmbiguity>;
  out aSummary: TGlobalVarsSummary): Boolean; overload;

function TryLoadCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  const aFilter: TGlobalVarsCacheLoadFilter; var aProject: TProjectInfo;
  out aSymbols: TObjectList<TGlobalVarSymbol>;
  out aAmbiguities: TList<TGlobalVarAmbiguity>;
  out aSummary: TGlobalVarsSummary): Boolean; overload;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.Async,
  FireDAC.Stan.Def,
  FireDAC.Stan.Error,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option;

procedure SetWideParam(const aQuery: TFDQuery; const aIndex: Integer; const aValue: string;
  const aDataType: TFieldType = ftWideString); forward;

procedure SetNamedWideParam(const aQuery: TFDQuery; const aName, aValue: string;
  const aDataType: TFieldType = ftWideString); forward;

function PatternToSqlLike(const aPattern: string): string;
var
  ch: Char;
  lPattern: string;
begin
  lPattern := aPattern;
  if (Pos('*', lPattern) = 0) and (Pos('?', lPattern) = 0) then
    lPattern := '*' + lPattern + '*';
  Result := '';
  for ch in lPattern do
  begin
    case ch of
      '*':
        Result := Result + '%';
      '?':
        Result := Result + '_';
      '\', '%', '_':
        Result := Result + '\' + ch;
    else
      Result := Result + ch;
    end;
  end;
end;

function AccessFilterSql(const aTableAlias: string; const aFilter: TGlobalVarsCacheLoadFilter):
  string;
begin
  if aFilter.ReadsOnly then
    Result := Format(' and %s.access_kind in (''read'', ''readwrite'')', [aTableAlias])
  else if aFilter.WritesOnly then
    Result := Format(' and %s.access_kind in (''write'', ''readwrite'')', [aTableAlias])
  else
    Result := '';
end;

procedure AppendSymbolWhere(var aSql: string; const aFilter: TGlobalVarsCacheLoadFilter);
begin
  if aFilter.HasUnitFilter then
    aSql := aSql + ' and upper(s.unit_name) like upper(:unit_filter) escape ''\''';
  if aFilter.HasNameFilter then
    aSql := aSql + ' and upper(s.name) like upper(:name_filter) escape ''\''';
  if aFilter.UnusedOnly then
    aSql := aSql + ' and not exists (select 1 from refs r where r.symbol_id = s.id)';
  if aFilter.ReadsOnly then
    aSql := aSql + ' and exists (select 1 from refs r where r.symbol_id = s.id and ' +
      'r.access_kind in (''read'', ''readwrite''))';
  if aFilter.WritesOnly then
    aSql := aSql + ' and exists (select 1 from refs r where r.symbol_id = s.id and ' +
      'r.access_kind in (''write'', ''readwrite''))';
end;

procedure AppendAmbiguityWhere(var aSql: string; const aFilter: TGlobalVarsCacheLoadFilter);
begin
  if aFilter.UnusedOnly then
  begin
    aSql := aSql + ' and 1 = 0';
    Exit;
  end;
  if aFilter.HasUnitFilter then
    aSql := aSql + ' and upper(a.unit_name) like upper(:unit_filter) escape ''\''';
  if aFilter.HasNameFilter then
    aSql := aSql + ' and upper(a.name) like upper(:name_filter) escape ''\''';
  aSql := aSql + AccessFilterSql('a', aFilter);
end;

procedure BindSymbolFilterParams(const aQuery: TFDQuery; const aFilter:
  TGlobalVarsCacheLoadFilter);
begin
  if aFilter.HasUnitFilter then
    SetNamedWideParam(aQuery, 'unit_filter', PatternToSqlLike(aFilter.UnitFilter));
  if aFilter.HasNameFilter then
    SetNamedWideParam(aQuery, 'name_filter', PatternToSqlLike(aFilter.NameFilter));
end;

procedure BindAmbiguityFilterParams(const aQuery: TFDQuery; const aFilter:
  TGlobalVarsCacheLoadFilter);
begin
  BindSymbolFilterParams(aQuery, aFilter);
end;

function NewQuery(const aConnection: TFDConnection; const aSql: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := aConnection;
  Result.SQL.Text := aSql;
end;

procedure SetWideParam(const aQuery: TFDQuery; const aIndex: Integer; const aValue: string;
  const aDataType: TFieldType = ftWideString);
begin
  while aQuery.Params.Count <= aIndex do
    aQuery.Params.Add;
  if aQuery.Params[aIndex].DataType <> aDataType then
    aQuery.Params[aIndex].DataType := aDataType;
  aQuery.Params[aIndex].AsWideString := aValue;
end;

procedure SetNamedWideParam(const aQuery: TFDQuery; const aName, aValue: string;
  const aDataType: TFieldType = ftWideString);
begin
  if aQuery.ParamByName(aName).DataType <> aDataType then
    aQuery.ParamByName(aName).DataType := aDataType;
  aQuery.ParamByName(aName).AsWideString := aValue;
end;

procedure ExecWideSql(const aConnection: TFDConnection; const aSql, aFirstValue,
  aSecondValue: string);
var
  lQuery: TFDQuery;
begin
  lQuery := NewQuery(aConnection, aSql);
  try
    SetWideParam(lQuery, 0, aFirstValue);
    SetWideParam(lQuery, 1, aSecondValue);
    lQuery.Prepare;
    lQuery.ExecSQL;
  finally
    lQuery.Free;
  end;
end;

function QueryWideString(const aConnection: TFDConnection; const aSql, aValue: string): string;
var
  lQuery: TFDQuery;
begin
  Result := '';
  lQuery := NewQuery(aConnection, aSql);
  try
    SetWideParam(lQuery, 0, aValue);
    lQuery.Open;
    if not lQuery.Eof then
      Result := lQuery.Fields[0].AsWideString;
  finally
    lQuery.Free;
  end;
end;

procedure EnsureCacheSchema(const aConnection: TFDConnection);
var
  lSchemaVersion: string;
begin
  aConnection.ExecSQL(
    'create table if not exists meta (key_name text primary key, value_text text not null)');
  lSchemaVersion := QueryWideString(aConnection,
    'select value_text from meta where key_name = ?', 'schema_version');
  if (lSchemaVersion <> '') and
    (lSchemaVersion <> cGlobalVarsCacheSchemaVersion) then
  begin
    aConnection.ExecSQL('drop table if exists refs');
    aConnection.ExecSQL('drop table if exists symbols');
    aConnection.ExecSQL('drop table if exists ambiguities');
    aConnection.ExecSQL('drop table if exists diagnostics');
    aConnection.ExecSQL('drop table if exists unit_identities');
    aConnection.ExecSQL('delete from meta');
  end;
  aConnection.ExecSQL('create table if not exists unit_identities (' +
    'unit_cache_key text primary key, file_hash text not null, context_hash text not null, ' +
    'include_graph_hash text not null, defines_hash text not null, search_path_hash text not null, ' +
    'extraction_options_hash text not null, compiler_profile text not null, delphi_version text not null, ' +
    'configuration text not null, platform text not null, parser_version text not null, ' +
    'model_version text not null, schema_version text not null)');
  aConnection.ExecSQL('create table if not exists symbols (' +
    'id integer primary key autoincrement, unit_name text not null, file_name text not null, name text not null, ' +
    'type_name text not null, kind text not null, owner_name text not null, ' +
    'declaration_role text not null, scope_kind text not null, owner_scope_id text not null, ' +
    'semantic_symbol_id text not null, line_no integer not null, col_no integer not null)');
  aConnection.ExecSQL('create table if not exists refs (' +
    'symbol_id integer not null, unit_name text not null, routine_name text not null, file_name text not null, ' +
    'routine_scope_id text not null, line_no integer not null, col_no integer not null, ' +
    'access_kind text not null)');
  aConnection.ExecSQL('create table if not exists ambiguities (' +
    'name text not null, unit_name text not null, routine_name text not null, file_name text not null, ' +
    'line_no integer not null, col_no integer not null, access_kind text not null, candidates text not null)');
  aConnection.ExecSQL('create table if not exists diagnostics (' +
    'code text not null, message text not null, file_name text not null, line_no integer not null)');
end;

procedure OpenCacheConnection(const aCacheFileName: string; out aDriverLink:
  TFDPhysSQLiteDriverLink; out aConnection: TFDConnection);
begin
  aDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  aConnection := TFDConnection.Create(nil);
  aConnection.LoginPrompt := False;
  aConnection.Params.Values['DriverID'] := 'SQLite';
  aConnection.Params.Values['Database'] := aCacheFileName;
  aConnection.Params.Values['BusyTimeout'] := IntToStr(cGlobalVarsCacheBusyTimeoutMs);
  aConnection.Params.Values['LockingMode'] := 'Normal';
  aConnection.Params.Values['OpenMode'] := 'CreateUTF8';
  aConnection.Connected := True;
end;

procedure PrepareIdentityQuery(const aConnection: TFDConnection; out aQuery: TFDQuery);
begin
  aQuery := NewQuery(aConnection, 'insert into unit_identities(unit_cache_key, file_hash, ' +
    'context_hash, include_graph_hash, defines_hash, search_path_hash, ' +
    'extraction_options_hash, compiler_profile, delphi_version, configuration, platform, ' +
    'parser_version, model_version, schema_version) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ' +
    '?, ?, ?)');
  aQuery.Params[0].DataType := ftWideString;
  aQuery.Params[1].DataType := ftWideString;
  aQuery.Params[2].DataType := ftWideString;
  aQuery.Params[3].DataType := ftWideString;
  aQuery.Params[4].DataType := ftWideString;
  aQuery.Params[5].DataType := ftWideString;
  aQuery.Params[6].DataType := ftWideString;
  aQuery.Params[7].DataType := ftWideString;
  aQuery.Params[8].DataType := ftWideString;
  aQuery.Params[9].DataType := ftWideString;
  aQuery.Params[10].DataType := ftWideString;
  aQuery.Params[11].DataType := ftWideString;
  aQuery.Params[12].DataType := ftWideString;
  aQuery.Params[13].DataType := ftWideString;
  aQuery.Prepare;
end;

procedure SaveIdentity(const aQuery: TFDQuery;
  const aIdentity: TDakSemanticUnitCacheIdentity);
begin
  SetWideParam(aQuery, 0, aIdentity.UnitCacheKey);
  SetWideParam(aQuery, 1, aIdentity.FileHash);
  SetWideParam(aQuery, 2, aIdentity.ContextHash);
  SetWideParam(aQuery, 3, aIdentity.IncludeGraphHash);
  SetWideParam(aQuery, 4, aIdentity.DefinesHash);
  SetWideParam(aQuery, 5, aIdentity.SearchPathHash);
  SetWideParam(aQuery, 6, aIdentity.ExtractionOptionsHash);
  SetWideParam(aQuery, 7, aIdentity.CompilerProfileName);
  SetWideParam(aQuery, 8, aIdentity.DelphiVersion);
  SetWideParam(aQuery, 9, aIdentity.Configuration);
  SetWideParam(aQuery, 10, aIdentity.Platform);
  SetWideParam(aQuery, 11, aIdentity.ParserVersion);
  SetWideParam(aQuery, 12, aIdentity.ModelVersion);
  SetWideParam(aQuery, 13, aIdentity.SchemaVersion);
  aQuery.ExecSQL;
end;

procedure SaveCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  const aIdentities: TArray<TDakSemanticUnitCacheIdentity>;
  const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>;
  const aRejectedImpossibleDeclarations: Integer); overload;
var
  lProject: TProjectInfo;
begin
  lProject := Default(TProjectInfo);
  SaveCachedSymbols(aCacheFileName, aProjectPath, aIdentityHash, aIdentities,
    lProject, aSymbols, aAmbiguities, aRejectedImpossibleDeclarations);
end;

procedure SaveCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  const aIdentities: TArray<TDakSemanticUnitCacheIdentity>;
  const aProject: TProjectInfo; const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>;
  const aRejectedImpossibleDeclarations: Integer); overload;
var
  lAmbiguity: TGlobalVarAmbiguity;
  lAmbiguityQuery: TFDQuery;
  lConnection: TFDConnection;
  lDiagnostic: TGlobalVarsDiagnostic;
  lDiagnosticQuery: TFDQuery;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lIdentity: TDakSemanticUnitCacheIdentity;
  lIdentityQuery: TFDQuery;
  lRef: TGlobalVarRef;
  lRefQuery: TFDQuery;
  lSymbol: TGlobalVarSymbol;
  lSymbolId: Int64;
  lSymbolQuery: TFDQuery;
begin
  TDirectory.CreateDirectory(TPath.GetDirectoryName(aCacheFileName));
  OpenCacheConnection(aCacheFileName, lDriverLink, lConnection);
  try
    EnsureCacheSchema(lConnection);
    lConnection.StartTransaction;
    try
      lConnection.ExecSQL('delete from meta');
      lConnection.ExecSQL('delete from unit_identities');
      lConnection.ExecSQL('delete from refs');
      lConnection.ExecSQL('delete from symbols');
      lConnection.ExecSQL('delete from ambiguities');
      lConnection.ExecSQL('delete from diagnostics');
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'schema_version', cGlobalVarsCacheSchemaVersion);
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'project_path', TPath.GetFullPath(aProjectPath));
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'identity_hash', aIdentityHash);
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'rejected_impossible_declarations', IntToStr(aRejectedImpossibleDeclarations));
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'semantic_fact_source', aProject.SemanticFactSource);
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'semantic_snapshot_unit_count', IntToStr(aProject.SemanticSnapshotUnitCount));
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'semantic_verified_scope_unit_count',
        IntToStr(aProject.SemanticVerifiedScopeUnitCount));
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'semantic_model_fallback_unit_count',
        IntToStr(aProject.SemanticModelFallbackUnitCount));
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'semantic_heuristic_fallback_unit_count',
        IntToStr(aProject.SemanticHeuristicFallbackUnitCount));
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'semantic_rejected_declaration_count',
        IntToStr(aProject.SemanticRejectedDeclarationCount));
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'semantic_source_revision', aProject.SemanticSourceRevision);
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'semantic_source_revision_source', aProject.SemanticSourceRevisionSource);
      lIdentityQuery := nil;
      lSymbolQuery := nil;
      lRefQuery := nil;
      lAmbiguityQuery := nil;
      lDiagnosticQuery := nil;
      try
        PrepareIdentityQuery(lConnection, lIdentityQuery);
        for lIdentity in aIdentities do
          SaveIdentity(lIdentityQuery, lIdentity);

        lSymbolQuery := NewQuery(lConnection, 'insert into symbols(unit_name, file_name, name, ' +
          'type_name, kind, owner_name, declaration_role, scope_kind, owner_scope_id, ' +
          'semantic_symbol_id, line_no, col_no) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
        lRefQuery := NewQuery(lConnection, 'insert into refs(symbol_id, unit_name, ' +
          'routine_name, routine_scope_id, file_name, line_no, col_no, access_kind) ' +
          'values (?, ?, ?, ?, ?, ?, ?, ?)');
        lAmbiguityQuery := NewQuery(lConnection, 'insert into ambiguities(name, unit_name, ' +
          'routine_name, file_name, line_no, col_no, access_kind, candidates) values (?, ?, ?, ' +
          '?, ?, ?, ?, ?)');
        lDiagnosticQuery := NewQuery(lConnection, 'insert into diagnostics(code, message, ' +
          'file_name, line_no) values (?, ?, ?, ?)');

        lSymbolQuery.Params[0].DataType := ftWideString;
        lSymbolQuery.Params[1].DataType := ftWideString;
        lSymbolQuery.Params[2].DataType := ftWideString;
        lSymbolQuery.Params[3].DataType := ftWideString;
        lSymbolQuery.Params[4].DataType := ftWideString;
        lSymbolQuery.Params[5].DataType := ftWideString;
        lSymbolQuery.Params[6].DataType := ftWideString;
        lSymbolQuery.Params[7].DataType := ftWideString;
        lSymbolQuery.Params[8].DataType := ftWideString;
        lSymbolQuery.Params[9].DataType := ftWideString;
        lSymbolQuery.Params[10].DataType := ftInteger;
        lSymbolQuery.Params[11].DataType := ftInteger;
        lSymbolQuery.Prepare;
        lRefQuery.Params[0].DataType := ftLargeint;
        lRefQuery.Params[1].DataType := ftWideString;
        lRefQuery.Params[2].DataType := ftWideString;
        lRefQuery.Params[3].DataType := ftWideString;
        lRefQuery.Params[4].DataType := ftWideString;
        lRefQuery.Params[5].DataType := ftInteger;
        lRefQuery.Params[6].DataType := ftInteger;
        lRefQuery.Params[7].DataType := ftWideString;
        lRefQuery.Prepare;
        lAmbiguityQuery.Params[0].DataType := ftWideString;
        lAmbiguityQuery.Params[1].DataType := ftWideString;
        lAmbiguityQuery.Params[2].DataType := ftWideString;
        lAmbiguityQuery.Params[3].DataType := ftWideString;
        lAmbiguityQuery.Params[4].DataType := ftInteger;
        lAmbiguityQuery.Params[5].DataType := ftInteger;
        lAmbiguityQuery.Params[6].DataType := ftWideString;
        lAmbiguityQuery.Params[7].DataType := ftWideString;
        lAmbiguityQuery.Prepare;
        lDiagnosticQuery.Params[0].DataType := ftWideString;
        lDiagnosticQuery.Params[1].DataType := ftWideString;
        lDiagnosticQuery.Params[2].DataType := ftWideString;
        lDiagnosticQuery.Params[3].DataType := ftInteger;
        lDiagnosticQuery.Prepare;

        for lSymbol in aSymbols do
        begin
          SetWideParam(lSymbolQuery, 0, lSymbol.UnitName);
          SetWideParam(lSymbolQuery, 1, lSymbol.FileName);
          SetWideParam(lSymbolQuery, 2, lSymbol.Name);
          SetWideParam(lSymbolQuery, 3, lSymbol.TypeName);
          SetWideParam(lSymbolQuery, 4, GlobalVarKindToText(lSymbol.Kind));
          SetWideParam(lSymbolQuery, 5, lSymbol.OwnerName);
          SetWideParam(lSymbolQuery, 6, lSymbol.DeclarationRole);
          SetWideParam(lSymbolQuery, 7, lSymbol.ScopeKind);
          SetWideParam(lSymbolQuery, 8, lSymbol.OwnerScopeId);
          SetWideParam(lSymbolQuery, 9, lSymbol.SymbolId);
          lSymbolQuery.Params[10].AsInteger := lSymbol.Line;
          lSymbolQuery.Params[11].AsInteger := lSymbol.Column;
          lSymbolQuery.ExecSQL;
          lSymbolId := lConnection.ExecSQLScalar('select last_insert_rowid()');
          for lRef in lSymbol.UsedBy do
          begin
            lRefQuery.Params[0].AsLargeInt := lSymbolId;
            SetWideParam(lRefQuery, 1, lRef.UnitName);
            SetWideParam(lRefQuery, 2, lRef.RoutineName);
            SetWideParam(lRefQuery, 3, lRef.RoutineScopeId);
            SetWideParam(lRefQuery, 4, lRef.FileName);
            lRefQuery.Params[5].AsInteger := lRef.Line;
            lRefQuery.Params[6].AsInteger := lRef.Column;
            SetWideParam(lRefQuery, 7, AccessToText(lRef.Access));
            lRefQuery.ExecSQL;
          end;
        end;

        for lAmbiguity in aAmbiguities do
        begin
          SetWideParam(lAmbiguityQuery, 0, lAmbiguity.Name);
          SetWideParam(lAmbiguityQuery, 1, lAmbiguity.UnitName);
          SetWideParam(lAmbiguityQuery, 2, lAmbiguity.RoutineName);
          SetWideParam(lAmbiguityQuery, 3, lAmbiguity.FileName);
          lAmbiguityQuery.Params[4].AsInteger := lAmbiguity.Line;
          lAmbiguityQuery.Params[5].AsInteger := lAmbiguity.Column;
          SetWideParam(lAmbiguityQuery, 6, AccessToText(lAmbiguity.Access));
          SetWideParam(lAmbiguityQuery, 7, lAmbiguity.Candidates);
          lAmbiguityQuery.ExecSQL;
        end;

        for lDiagnostic in aProject.SemanticDiagnostics do
        begin
          SetWideParam(lDiagnosticQuery, 0, lDiagnostic.Code);
          SetWideParam(lDiagnosticQuery, 1, lDiagnostic.Message);
          SetWideParam(lDiagnosticQuery, 2, lDiagnostic.FileName);
          lDiagnosticQuery.Params[3].AsInteger := lDiagnostic.Line;
          lDiagnosticQuery.ExecSQL;
        end;
      finally
        lDiagnosticQuery.Free;
        lAmbiguityQuery.Free;
        lRefQuery.Free;
        lSymbolQuery.Free;
        lIdentityQuery.Free;
      end;
      lConnection.Commit;
    except
      lConnection.Rollback;
      raise;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TryLoadCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  out aSymbols: TObjectList<TGlobalVarSymbol>;
  out aAmbiguities: TList<TGlobalVarAmbiguity>): Boolean; overload;
var
  lFilter: TGlobalVarsCacheLoadFilter;
  lSummary: TGlobalVarsSummary;
begin
  lFilter := Default(TGlobalVarsCacheLoadFilter);
  Result := TryLoadCachedSymbols(aCacheFileName, aProjectPath, aIdentityHash, lFilter,
    aSymbols, aAmbiguities, lSummary);
end;

function TryLoadCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  const aFilter: TGlobalVarsCacheLoadFilter;
  out aSymbols: TObjectList<TGlobalVarSymbol>;
  out aAmbiguities: TList<TGlobalVarAmbiguity>;
  out aSummary: TGlobalVarsSummary): Boolean; overload;
var
  lProject: TProjectInfo;
begin
  lProject := Default(TProjectInfo);
  Result := TryLoadCachedSymbols(aCacheFileName, aProjectPath, aIdentityHash, aFilter,
    lProject, aSymbols, aAmbiguities, aSummary);
end;

function TryLoadCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  const aFilter: TGlobalVarsCacheLoadFilter; var aProject: TProjectInfo;
  out aSymbols: TObjectList<TGlobalVarSymbol>;
  out aAmbiguities: TList<TGlobalVarAmbiguity>;
  out aSummary: TGlobalVarsSummary): Boolean; overload;
var
  lAmbiguity: TGlobalVarAmbiguity;
  lAccessField: TField;
  lCandidatesField: TField;
  lCodeField: TField;
  lColField: TField;
  lConnection: TFDConnection;
  lDiagnostic: TGlobalVarsDiagnostic;
  lDiagnostics: TList<TGlobalVarsDiagnostic>;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lExpected: string;
  lFileField: TField;
  lIdField: TField;
  lKindField: TField;
  lLineField: TField;
  lMessageField: TField;
  lNameField: TField;
  lOwnerField: TField;
  lOwnerScopeField: TField;
  lQuery: TFDQuery;
  lRef: TGlobalVarRef;
  lRoleField: TField;
  lRoutineField: TField;
  lRoutineScopeField: TField;
  lScopeField: TField;
  lSemanticSymbolField: TField;
  lSql: string;
  lSymbol: TGlobalVarSymbol;
  lSymbolById: TDictionary<Int64, TGlobalVarSymbol>;
  lSymbolIdField: TField;
  lTypeField: TField;
  lUnitField: TField;
begin
  Result := False;
  aSymbols := nil;
  aAmbiguities := nil;
  aSummary := Default(TGlobalVarsSummary);
  if not TFile.Exists(aCacheFileName) then
    Exit;

  OpenCacheConnection(aCacheFileName, lDriverLink, lConnection);
  lQuery := TFDQuery.Create(nil);
  lSymbolById := TDictionary<Int64, TGlobalVarSymbol>.Create;
  lDiagnostics := TList<TGlobalVarsDiagnostic>.Create;
  try
    lQuery.Connection := lConnection;
    EnsureCacheSchema(lConnection);
    lExpected := QueryWideString(lConnection, 'select value_text from meta where key_name = ?',
      'schema_version');
    if lExpected <> cGlobalVarsCacheSchemaVersion then
      Exit;

    lExpected := QueryWideString(lConnection, 'select value_text from meta where key_name = ?',
      'project_path');
    if not SameText(TPath.GetFullPath(aProjectPath), lExpected) then
      Exit;

    lExpected := QueryWideString(lConnection, 'select value_text from meta where key_name = ?',
      'identity_hash');
    if not SameText(aIdentityHash, lExpected) then
      Exit;

    aProject.SemanticFactSource := QueryWideString(lConnection,
      'select value_text from meta where key_name = ?', 'semantic_fact_source');
    aProject.SemanticSnapshotUnitCount := StrToIntDef(QueryWideString(lConnection,
      'select value_text from meta where key_name = ?',
      'semantic_snapshot_unit_count'), 0);
    aProject.SemanticVerifiedScopeUnitCount := StrToIntDef(QueryWideString(lConnection,
      'select value_text from meta where key_name = ?',
      'semantic_verified_scope_unit_count'), 0);
    aProject.SemanticModelFallbackUnitCount := StrToIntDef(QueryWideString(lConnection,
      'select value_text from meta where key_name = ?',
      'semantic_model_fallback_unit_count'), 0);
    aProject.SemanticHeuristicFallbackUnitCount := StrToIntDef(QueryWideString(lConnection,
      'select value_text from meta where key_name = ?',
      'semantic_heuristic_fallback_unit_count'), 0);
    aProject.SemanticRejectedDeclarationCount := StrToIntDef(QueryWideString(lConnection,
      'select value_text from meta where key_name = ?',
      'semantic_rejected_declaration_count'), 0);
    aProject.SemanticSourceRevision := QueryWideString(lConnection,
      'select value_text from meta where key_name = ?', 'semantic_source_revision');
    aProject.SemanticSourceRevisionSource := QueryWideString(lConnection,
      'select value_text from meta where key_name = ?',
      'semantic_source_revision_source');
    lQuery.SQL.Text := 'select code, message, file_name, line_no from diagnostics ' +
      'order by rowid';
    lQuery.Open;
    lCodeField := lQuery.FieldByName('code');
    lMessageField := lQuery.FieldByName('message');
    lFileField := lQuery.FieldByName('file_name');
    lLineField := lQuery.FieldByName('line_no');
    while not lQuery.Eof do
    begin
      lDiagnostic.Code := lCodeField.AsWideString;
      lDiagnostic.Message := lMessageField.AsWideString;
      lDiagnostic.FileName := lFileField.AsWideString;
      lDiagnostic.Line := lLineField.AsInteger;
      lDiagnostics.Add(lDiagnostic);
      lQuery.Next;
    end;
    aProject.SemanticDiagnostics := lDiagnostics.ToArray;
    lQuery.Close;

    aSymbols := TObjectList<TGlobalVarSymbol>.Create(True);
    aAmbiguities := TList<TGlobalVarAmbiguity>.Create;
    aSummary.Total := lConnection.ExecSQLScalar('select count(*) from symbols');
    aSummary.Used := lConnection.ExecSQLScalar(
      'select count(*) from symbols s where exists (select 1 from refs r where r.symbol_id = s.id)');
    aSummary.Unused := lConnection.ExecSQLScalar(
      'select count(*) from symbols s where not exists (select 1 from refs r where r.symbol_id = s.id)');
    aSummary.Ambiguities := lConnection.ExecSQLScalar('select count(*) from ambiguities');
    aSummary.RejectedImpossibleDeclarations := StrToIntDef(QueryWideString(lConnection,
      'select value_text from meta where key_name = ?',
      'rejected_impossible_declarations'), 0);

    lSql := 'select id, unit_name, file_name, name, type_name, kind, owner_name, ' +
      'declaration_role, scope_kind, owner_scope_id, semantic_symbol_id, line_no, ' +
      'col_no from symbols s where 1 = 1';
    AppendSymbolWhere(lSql, aFilter);
    lSql := lSql + ' order by s.id';
    lQuery.SQL.Text := lSql;
    BindSymbolFilterParams(lQuery, aFilter);
    lQuery.Open;
    lIdField := lQuery.FieldByName('id');
    lUnitField := lQuery.FieldByName('unit_name');
    lFileField := lQuery.FieldByName('file_name');
    lNameField := lQuery.FieldByName('name');
    lTypeField := lQuery.FieldByName('type_name');
    lKindField := lQuery.FieldByName('kind');
    lOwnerField := lQuery.FieldByName('owner_name');
    lRoleField := lQuery.FieldByName('declaration_role');
    lScopeField := lQuery.FieldByName('scope_kind');
    lOwnerScopeField := lQuery.FieldByName('owner_scope_id');
    lSemanticSymbolField := lQuery.FieldByName('semantic_symbol_id');
    lLineField := lQuery.FieldByName('line_no');
    lColField := lQuery.FieldByName('col_no');
    while not lQuery.Eof do
    begin
      lSymbol := TGlobalVarSymbol.Create;
      lSymbol.UnitName := lUnitField.AsWideString;
      lSymbol.FileName := lFileField.AsWideString;
      lSymbol.Name := lNameField.AsWideString;
      lSymbol.TypeName := lTypeField.AsWideString;
      lSymbol.OwnerName := lOwnerField.AsWideString;
      lSymbol.DeclarationRole := lRoleField.AsWideString;
      lSymbol.ScopeKind := lScopeField.AsWideString;
      lSymbol.OwnerScopeId := lOwnerScopeField.AsWideString;
      lSymbol.SymbolId := lSemanticSymbolField.AsWideString;
      lSymbol.Line := lLineField.AsInteger;
      lSymbol.Column := lColField.AsInteger;
      if SameText(lKindField.AsWideString, 'threadvar') then
        lSymbol.Kind := gvkThreadVar
      else if SameText(lKindField.AsWideString, 'typedconst') then
        lSymbol.Kind := gvkTypedConst
      else if SameText(lKindField.AsWideString, 'classvar') then
        lSymbol.Kind := gvkClassVar
      else
        lSymbol.Kind := gvkVar;
      aSymbols.Add(lSymbol);
      lSymbolById.Add(lIdField.AsLargeInt, lSymbol);
      lQuery.Next;
    end;
    aSummary.Emitted := aSymbols.Count;

    lQuery.Close;
    if not aFilter.UnusedOnly then
    begin
      lSql := 'select r.symbol_id, r.unit_name, r.routine_name, r.routine_scope_id, ' +
        'r.file_name, r.line_no, r.col_no, r.access_kind from refs r inner join symbols s ' +
        'on s.id = r.symbol_id where 1 = 1';
      AppendSymbolWhere(lSql, aFilter);
      lSql := lSql + AccessFilterSql('r', aFilter) + ' order by r.symbol_id, r.line_no, r.col_no';
      lQuery.SQL.Text := lSql;
      BindSymbolFilterParams(lQuery, aFilter);
      lQuery.Open;
      lSymbolIdField := lQuery.FieldByName('symbol_id');
      lUnitField := lQuery.FieldByName('unit_name');
      lRoutineField := lQuery.FieldByName('routine_name');
      lRoutineScopeField := lQuery.FieldByName('routine_scope_id');
      lFileField := lQuery.FieldByName('file_name');
      lLineField := lQuery.FieldByName('line_no');
      lColField := lQuery.FieldByName('col_no');
      lAccessField := lQuery.FieldByName('access_kind');
      while not lQuery.Eof do
      begin
        if lSymbolById.TryGetValue(lSymbolIdField.AsLargeInt, lSymbol) then
        begin
          lRef := Default(TGlobalVarRef);
          lRef.UnitName := lUnitField.AsWideString;
          lRef.RoutineName := lRoutineField.AsWideString;
          lRef.RoutineScopeId := lRoutineScopeField.AsWideString;
          lRef.FileName := lFileField.AsWideString;
          lRef.Line := lLineField.AsInteger;
          lRef.Column := lColField.AsInteger;
          if SameText(lAccessField.AsWideString, 'write') then
            lRef.Access := akWrite
          else if SameText(lAccessField.AsWideString, 'readwrite') then
            lRef.Access := akReadWrite
          else
            lRef.Access := akRead;
          lSymbol.UsedBy.Add(lRef);
        end;
        lQuery.Next;
      end;
    end;

    lQuery.Close;
    lSql := 'select name, unit_name, routine_name, file_name, line_no, col_no, ' +
      'access_kind, candidates from ambiguities a where 1 = 1';
    AppendAmbiguityWhere(lSql, aFilter);
    lSql := lSql + ' order by a.file_name, a.line_no, a.col_no';
    lQuery.SQL.Text := lSql;
    BindAmbiguityFilterParams(lQuery, aFilter);
    lQuery.Open;
    lNameField := lQuery.FieldByName('name');
    lUnitField := lQuery.FieldByName('unit_name');
    lRoutineField := lQuery.FieldByName('routine_name');
    lFileField := lQuery.FieldByName('file_name');
    lLineField := lQuery.FieldByName('line_no');
    lColField := lQuery.FieldByName('col_no');
    lAccessField := lQuery.FieldByName('access_kind');
    lCandidatesField := lQuery.FieldByName('candidates');
    while not lQuery.Eof do
    begin
      lAmbiguity.Name := lNameField.AsWideString;
      lAmbiguity.UnitName := lUnitField.AsWideString;
      lAmbiguity.RoutineName := lRoutineField.AsWideString;
      lAmbiguity.FileName := lFileField.AsWideString;
      lAmbiguity.Line := lLineField.AsInteger;
      lAmbiguity.Column := lColField.AsInteger;
      if SameText(lAccessField.AsWideString, 'write') then
        lAmbiguity.Access := akWrite
      else if SameText(lAccessField.AsWideString, 'readwrite') then
        lAmbiguity.Access := akReadWrite
      else
        lAmbiguity.Access := akRead;
      lAmbiguity.Candidates := lCandidatesField.AsWideString;
      aAmbiguities.Add(lAmbiguity);
      lQuery.Next;
    end;
    aSummary.EmittedAmbiguities := aAmbiguities.Count;
    Result := True;
  finally
    if not Result then
    begin
      aSymbols.Free;
      aSymbols := nil;
      aAmbiguities.Free;
      aAmbiguities := nil;
    end;
    lSymbolById.Free;
    lDiagnostics.Free;
    lQuery.Free;
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

end.
