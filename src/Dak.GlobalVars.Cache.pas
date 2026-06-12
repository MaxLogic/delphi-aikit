unit Dak.GlobalVars.Cache;

interface

uses
  System.Generics.Collections,
  DelphiSemantics.Cache,
  Dak.GlobalVars.Model;

const
  cGlobalVarsCacheSchemaVersion = '3';

procedure SaveCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  const aIdentities: TArray<TDelphiSemanticUnitCacheIdentity>;
  const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>);

function TryLoadCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  out aSymbols: TObjectList<TGlobalVarSymbol>;
  out aAmbiguities: TList<TGlobalVarAmbiguity>): Boolean;

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

function NewQuery(const aConnection: TFDConnection; const aSql: string): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  Result.Connection := aConnection;
  Result.SQL.Text := aSql;
end;

procedure SetWideParam(const aQuery: TFDQuery; const aIndex: Integer; const aValue: string;
  const aDataType: TFieldType = ftWideString);
begin
  if aQuery.Params[aIndex].DataType <> aDataType then
    aQuery.Params[aIndex].DataType := aDataType;
  aQuery.Params[aIndex].AsWideString := aValue;
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
begin
  aConnection.ExecSQL(
    'create table if not exists meta (key_name text primary key, value_text text not null)');
  aConnection.ExecSQL('create table if not exists unit_identities (' +
    'unit_cache_key text primary key, file_hash text not null, context_hash text not null, ' +
    'include_graph_hash text not null, defines_hash text not null, search_path_hash text not null, ' +
    'extraction_options_hash text not null, compiler_profile text not null, delphi_version text not null, ' +
    'configuration text not null, platform text not null, parser_version text not null, ' +
    'model_version text not null, schema_version text not null)');
  aConnection.ExecSQL('create table if not exists symbols (' +
    'id integer primary key autoincrement, unit_name text not null, file_name text not null, name text not null, ' +
    'type_name text not null, kind text not null, line_no integer not null, col_no integer not null)');
  aConnection.ExecSQL('create table if not exists refs (' +
    'symbol_id integer not null, unit_name text not null, routine_name text not null, file_name text not null, ' +
    'line_no integer not null, col_no integer not null, access_kind text not null)');
  aConnection.ExecSQL('create table if not exists ambiguities (' +
    'name text not null, unit_name text not null, routine_name text not null, file_name text not null, ' +
    'line_no integer not null, col_no integer not null, access_kind text not null, candidates text not null)');
end;

procedure OpenCacheConnection(const aCacheFileName: string; out aDriverLink:
  TFDPhysSQLiteDriverLink; out aConnection: TFDConnection);
begin
  aDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  aConnection := TFDConnection.Create(nil);
  aConnection.LoginPrompt := False;
  aConnection.Params.Values['DriverID'] := 'SQLite';
  aConnection.Params.Values['Database'] := aCacheFileName;
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
  const aIdentity: TDelphiSemanticUnitCacheIdentity);
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
  const aIdentities: TArray<TDelphiSemanticUnitCacheIdentity>;
  const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>);
var
  lAmbiguity: TGlobalVarAmbiguity;
  lAmbiguityQuery: TFDQuery;
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lIdentity: TDelphiSemanticUnitCacheIdentity;
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
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'schema_version', cGlobalVarsCacheSchemaVersion);
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'project_path', TPath.GetFullPath(aProjectPath));
      ExecWideSql(lConnection, 'insert into meta(key_name, value_text) values (?, ?)',
        'identity_hash', aIdentityHash);
      lIdentityQuery := nil;
      lSymbolQuery := nil;
      lRefQuery := nil;
      lAmbiguityQuery := nil;
      try
        PrepareIdentityQuery(lConnection, lIdentityQuery);
        for lIdentity in aIdentities do
          SaveIdentity(lIdentityQuery, lIdentity);

        lSymbolQuery := NewQuery(lConnection, 'insert into symbols(unit_name, file_name, name, ' +
          'type_name, kind, line_no, col_no) values (?, ?, ?, ?, ?, ?, ?)');
        lRefQuery := NewQuery(lConnection, 'insert into refs(symbol_id, unit_name, ' +
          'routine_name, file_name, line_no, col_no, access_kind) values (?, ?, ?, ?, ?, ?, ?)');
        lAmbiguityQuery := NewQuery(lConnection, 'insert into ambiguities(name, unit_name, ' +
          'routine_name, file_name, line_no, col_no, access_kind, candidates) values (?, ?, ?, ' +
          '?, ?, ?, ?, ?)');

        lSymbolQuery.Params[0].DataType := ftWideString;
        lSymbolQuery.Params[1].DataType := ftWideString;
        lSymbolQuery.Params[2].DataType := ftWideString;
        lSymbolQuery.Params[3].DataType := ftWideString;
        lSymbolQuery.Params[4].DataType := ftWideString;
        lSymbolQuery.Params[5].DataType := ftInteger;
        lSymbolQuery.Params[6].DataType := ftInteger;
        lSymbolQuery.Prepare;
        lRefQuery.Params[0].DataType := ftLargeint;
        lRefQuery.Params[1].DataType := ftWideString;
        lRefQuery.Params[2].DataType := ftWideString;
        lRefQuery.Params[3].DataType := ftWideString;
        lRefQuery.Params[4].DataType := ftInteger;
        lRefQuery.Params[5].DataType := ftInteger;
        lRefQuery.Params[6].DataType := ftWideString;
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

        for lSymbol in aSymbols do
        begin
          SetWideParam(lSymbolQuery, 0, lSymbol.UnitName);
          SetWideParam(lSymbolQuery, 1, lSymbol.FileName);
          SetWideParam(lSymbolQuery, 2, lSymbol.Name);
          SetWideParam(lSymbolQuery, 3, lSymbol.TypeName);
          SetWideParam(lSymbolQuery, 4, GlobalVarKindToText(lSymbol.Kind));
          lSymbolQuery.Params[5].AsInteger := lSymbol.Line;
          lSymbolQuery.Params[6].AsInteger := lSymbol.Column;
          lSymbolQuery.ExecSQL;
          lSymbolId := lConnection.ExecSQLScalar('select last_insert_rowid()');
          for lRef in lSymbol.UsedBy do
          begin
            lRefQuery.Params[0].AsLargeInt := lSymbolId;
            SetWideParam(lRefQuery, 1, lRef.UnitName);
            SetWideParam(lRefQuery, 2, lRef.RoutineName);
            SetWideParam(lRefQuery, 3, lRef.FileName);
            lRefQuery.Params[4].AsInteger := lRef.Line;
            lRefQuery.Params[5].AsInteger := lRef.Column;
            SetWideParam(lRefQuery, 6, AccessToText(lRef.Access));
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
      finally
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
  out aAmbiguities: TList<TGlobalVarAmbiguity>): Boolean;
var
  lAmbiguity: TGlobalVarAmbiguity;
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lExpected: string;
  lQuery: TFDQuery;
  lRef: TGlobalVarRef;
  lSymbol: TGlobalVarSymbol;
  lSymbolById: TDictionary<Int64, TGlobalVarSymbol>;
begin
  Result := False;
  aSymbols := nil;
  aAmbiguities := nil;
  if not TFile.Exists(aCacheFileName) then
    Exit;

  OpenCacheConnection(aCacheFileName, lDriverLink, lConnection);
  lQuery := TFDQuery.Create(nil);
  lSymbolById := TDictionary<Int64, TGlobalVarSymbol>.Create;
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

    aSymbols := TObjectList<TGlobalVarSymbol>.Create(True);
    aAmbiguities := TList<TGlobalVarAmbiguity>.Create;
    lQuery.SQL.Text := 'select id, unit_name, file_name, name, type_name, kind, line_no, col_no from symbols order by id';
    lQuery.Open;
    while not lQuery.Eof do
    begin
      lSymbol := TGlobalVarSymbol.Create;
      lSymbol.UnitName := lQuery.FieldByName('unit_name').AsWideString;
      lSymbol.FileName := lQuery.FieldByName('file_name').AsWideString;
      lSymbol.Name := lQuery.FieldByName('name').AsWideString;
      lSymbol.TypeName := lQuery.FieldByName('type_name').AsWideString;
      lSymbol.Line := lQuery.FieldByName('line_no').AsInteger;
      lSymbol.Column := lQuery.FieldByName('col_no').AsInteger;
      if SameText(lQuery.FieldByName('kind').AsWideString, 'threadvar') then
        lSymbol.Kind := gvkThreadVar
      else if SameText(lQuery.FieldByName('kind').AsWideString, 'typedconst') then
        lSymbol.Kind := gvkTypedConst
      else if SameText(lQuery.FieldByName('kind').AsWideString, 'classvar') then
        lSymbol.Kind := gvkClassVar
      else
        lSymbol.Kind := gvkVar;
      aSymbols.Add(lSymbol);
      lSymbolById.Add(lQuery.FieldByName('id').AsLargeInt, lSymbol);
      lQuery.Next;
    end;

    lQuery.Close;
    lQuery.SQL.Text := 'select symbol_id, unit_name, routine_name, file_name, line_no, col_no, access_kind from refs order by symbol_id, line_no, col_no';
    lQuery.Open;
    while not lQuery.Eof do
    begin
      if lSymbolById.TryGetValue(lQuery.FieldByName('symbol_id').AsLargeInt, lSymbol) then
      begin
        lRef.UnitName := lQuery.FieldByName('unit_name').AsWideString;
        lRef.RoutineName := lQuery.FieldByName('routine_name').AsWideString;
        lRef.FileName := lQuery.FieldByName('file_name').AsWideString;
        lRef.Line := lQuery.FieldByName('line_no').AsInteger;
        lRef.Column := lQuery.FieldByName('col_no').AsInteger;
        if SameText(lQuery.FieldByName('access_kind').AsWideString, 'write') then
          lRef.Access := akWrite
        else if SameText(lQuery.FieldByName('access_kind').AsWideString, 'readwrite') then
          lRef.Access := akReadWrite
        else
          lRef.Access := akRead;
        lSymbol.UsedBy.Add(lRef);
      end;
      lQuery.Next;
    end;

    lQuery.Close;
    lQuery.SQL.Text := 'select name, unit_name, routine_name, file_name, line_no, col_no, access_kind, candidates from ambiguities order by file_name, line_no, col_no';
    lQuery.Open;
    while not lQuery.Eof do
    begin
      lAmbiguity.Name := lQuery.FieldByName('name').AsWideString;
      lAmbiguity.UnitName := lQuery.FieldByName('unit_name').AsWideString;
      lAmbiguity.RoutineName := lQuery.FieldByName('routine_name').AsWideString;
      lAmbiguity.FileName := lQuery.FieldByName('file_name').AsWideString;
      lAmbiguity.Line := lQuery.FieldByName('line_no').AsInteger;
      lAmbiguity.Column := lQuery.FieldByName('col_no').AsInteger;
      if SameText(lQuery.FieldByName('access_kind').AsWideString, 'write') then
        lAmbiguity.Access := akWrite
      else if SameText(lQuery.FieldByName('access_kind').AsWideString, 'readwrite') then
        lAmbiguity.Access := akReadWrite
      else
        lAmbiguity.Access := akRead;
      lAmbiguity.Candidates := lQuery.FieldByName('candidates').AsWideString;
      aAmbiguities.Add(lAmbiguity);
      lQuery.Next;
    end;
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
    lQuery.Free;
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

end.
