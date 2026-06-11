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
  System.Variants,
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

procedure SaveIdentity(const aConnection: TFDConnection;
  const aIdentity: TDelphiSemanticUnitCacheIdentity);
begin
  aConnection.ExecSQL('insert into unit_identities(unit_cache_key, file_hash, context_hash, ' +
    'include_graph_hash, defines_hash, search_path_hash, extraction_options_hash, ' +
    'compiler_profile, delphi_version, configuration, platform, parser_version, model_version, ' +
    'schema_version) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [aIdentity.UnitCacheKey, aIdentity.FileHash, aIdentity.ContextHash,
    aIdentity.IncludeGraphHash, aIdentity.DefinesHash, aIdentity.SearchPathHash,
    aIdentity.ExtractionOptionsHash, aIdentity.CompilerProfileName, aIdentity.DelphiVersion,
    aIdentity.Configuration, aIdentity.Platform, aIdentity.ParserVersion,
    aIdentity.ModelVersion, aIdentity.SchemaVersion]);
end;

procedure SaveCachedSymbols(const aCacheFileName, aProjectPath, aIdentityHash: string;
  const aIdentities: TArray<TDelphiSemanticUnitCacheIdentity>;
  const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>);
var
  lAmbiguity: TGlobalVarAmbiguity;
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lIdentity: TDelphiSemanticUnitCacheIdentity;
  lRef: TGlobalVarRef;
  lSymbol: TGlobalVarSymbol;
  lSymbolId: Int64;
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
      lConnection.ExecSQL('insert into meta(key_name, value_text) values (?, ?)',
        ['schema_version', cGlobalVarsCacheSchemaVersion]);
      lConnection.ExecSQL('insert into meta(key_name, value_text) values (?, ?)',
        ['project_path', TPath.GetFullPath(aProjectPath)]);
      lConnection.ExecSQL('insert into meta(key_name, value_text) values (?, ?)',
        ['identity_hash', aIdentityHash]);
      for lIdentity in aIdentities do
        SaveIdentity(lConnection, lIdentity);

      for lSymbol in aSymbols do
      begin
        lConnection.ExecSQL('insert into symbols(unit_name, file_name, name, type_name, kind, line_no, col_no) values (?, ?, ?, ?, ?, ?, ?)',
          [lSymbol.UnitName, lSymbol.FileName, lSymbol.Name, lSymbol.TypeName,
          GlobalVarKindToText(lSymbol.Kind), lSymbol.Line, lSymbol.Column]);
        lSymbolId := lConnection.ExecSQLScalar('select last_insert_rowid()');
        for lRef in lSymbol.UsedBy do
          lConnection.ExecSQL('insert into refs(symbol_id, unit_name, routine_name, file_name, line_no, col_no, access_kind) values (?, ?, ?, ?, ?, ?, ?)',
            [lSymbolId, lRef.UnitName, lRef.RoutineName, lRef.FileName, lRef.Line,
            lRef.Column, AccessToText(lRef.Access)]);
      end;

      for lAmbiguity in aAmbiguities do
        lConnection.ExecSQL('insert into ambiguities(name, unit_name, routine_name, file_name, line_no, col_no, access_kind, candidates) values (?, ?, ?, ?, ?, ?, ?, ?)',
          [lAmbiguity.Name, lAmbiguity.UnitName, lAmbiguity.RoutineName,
          lAmbiguity.FileName, lAmbiguity.Line, lAmbiguity.Column,
          AccessToText(lAmbiguity.Access), lAmbiguity.Candidates]);
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
    lExpected := VarToStr(lConnection.ExecSQLScalar(
      'select value_text from meta where key_name = ?', ['schema_version']));
    if lExpected <> cGlobalVarsCacheSchemaVersion then
      Exit;

    lExpected := VarToStr(lConnection.ExecSQLScalar(
      'select value_text from meta where key_name = ?', ['project_path']));
    if not SameText(TPath.GetFullPath(aProjectPath), lExpected) then
      Exit;

    lExpected := VarToStr(lConnection.ExecSQLScalar(
      'select value_text from meta where key_name = ?', ['identity_hash']));
    if not SameText(aIdentityHash, lExpected) then
      Exit;

    aSymbols := TObjectList<TGlobalVarSymbol>.Create(True);
    aAmbiguities := TList<TGlobalVarAmbiguity>.Create;
    lQuery.SQL.Text := 'select id, unit_name, file_name, name, type_name, kind, line_no, col_no from symbols order by id';
    lQuery.Open;
    while not lQuery.Eof do
    begin
      lSymbol := TGlobalVarSymbol.Create;
      lSymbol.UnitName := lQuery.FieldByName('unit_name').AsString;
      lSymbol.FileName := lQuery.FieldByName('file_name').AsString;
      lSymbol.Name := lQuery.FieldByName('name').AsString;
      lSymbol.TypeName := lQuery.FieldByName('type_name').AsString;
      lSymbol.Line := lQuery.FieldByName('line_no').AsInteger;
      lSymbol.Column := lQuery.FieldByName('col_no').AsInteger;
      if SameText(lQuery.FieldByName('kind').AsString, 'threadvar') then
        lSymbol.Kind := gvkThreadVar
      else if SameText(lQuery.FieldByName('kind').AsString, 'typedconst') then
        lSymbol.Kind := gvkTypedConst
      else if SameText(lQuery.FieldByName('kind').AsString, 'classvar') then
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
        lRef.UnitName := lQuery.FieldByName('unit_name').AsString;
        lRef.RoutineName := lQuery.FieldByName('routine_name').AsString;
        lRef.FileName := lQuery.FieldByName('file_name').AsString;
        lRef.Line := lQuery.FieldByName('line_no').AsInteger;
        lRef.Column := lQuery.FieldByName('col_no').AsInteger;
        if SameText(lQuery.FieldByName('access_kind').AsString, 'write') then
          lRef.Access := akWrite
        else if SameText(lQuery.FieldByName('access_kind').AsString, 'readwrite') then
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
      lAmbiguity.Name := lQuery.FieldByName('name').AsString;
      lAmbiguity.UnitName := lQuery.FieldByName('unit_name').AsString;
      lAmbiguity.RoutineName := lQuery.FieldByName('routine_name').AsString;
      lAmbiguity.FileName := lQuery.FieldByName('file_name').AsString;
      lAmbiguity.Line := lQuery.FieldByName('line_no').AsInteger;
      lAmbiguity.Column := lQuery.FieldByName('col_no').AsInteger;
      if SameText(lQuery.FieldByName('access_kind').AsString, 'write') then
        lAmbiguity.Access := akWrite
      else if SameText(lQuery.FieldByName('access_kind').AsString, 'readwrite') then
        lAmbiguity.Access := akReadWrite
      else
        lAmbiguity.Access := akRead;
      lAmbiguity.Candidates := lQuery.FieldByName('candidates').AsString;
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
