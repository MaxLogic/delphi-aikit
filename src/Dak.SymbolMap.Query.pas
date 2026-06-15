unit Dak.SymbolMap.Query;

interface

uses
  Dak.SymbolMap.Cache, Dak.SymbolMap.Context;

type
  TSymbolMapDefinition = record
    fFound: Boolean;
    fName: string;
    fKind: string;
    fOwnerName: string;
    fUnitName: string;
    fFilePath: string;
    fSourceKind: string;
    fConfidence: string;
    fSignature: string;
    fTypeName: string;
    fLine: Integer;
    fCol: Integer;
    fEndLine: Integer;
    fEndCol: Integer;
  end;

  TSymbolMapReference = record
    fName: string;
    fUnitName: string;
    fFilePath: string;
    fSourceKind: string;
    fConfidence: string;
    fRole: string;
    fSectionKind: string;
    fLine: Integer;
    fCol: Integer;
    fEndLine: Integer;
    fEndCol: Integer;
  end;

function SymbolMapProjectHasIndexedUnits(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  out aError: string): Boolean;
function FindSymbolMapDefinitionByName(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aName, aOwnerName: string;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
function FindSymbolMapDefinitionByPosition(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aFilePath: string; const aLine, aCol: Integer;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
function SearchSymbolMapDefinitions(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aQuery: string; const aLimit: Integer;
  out aDefinitions: TArray<TSymbolMapDefinition>; out aError: string): Boolean;
function DescribeSymbolMapDefinition(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aName, aOwnerName: string;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
function FindSymbolMapReferences(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aSymbol: string; const aLimit: Integer;
  out aReferences: TArray<TSymbolMapReference>; out aError: string): Boolean;
function FindSymbolMapReferencesByPosition(const aContext: TSymbolMapContext; const aFilePath: string;
  const aLine, aCol, aLimit: Integer; out aSymbol: string;
  out aReferences: TArray<TSymbolMapReference>; out aError: string): Boolean;

implementation

uses
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,
  FireDAC.Comp.Client, FireDAC.Phys.SQLite,
  DelphiSemantics.ProjectContext,
  Dak.Semantics.Session;

type
  TSymbolMapUnitScope = record
    fUnitName: string;
    fFilePath: string;
    fSourceKind: string;
  end;

  TSymbolMapUnitScopeEntry = record
    fUnitCacheKey: string;
    fScope: TSymbolMapUnitScope;
  end;

function DakSourceKind(const aSourceKind: string): string;
begin
  if SameText(aSourceKind, 'project-source') or SameText(aSourceKind, 'project-snapshot') then
    Exit('project');
  if SameText(aSourceKind, 'compiler-profile') then
    Exit('compiler-intrinsic');
  Result := aSourceKind;
end;

function DakSymbolKind(const aKind: string): string;
begin
  if SameText(aKind, 'intrinsic-routine') then
    Exit('routine');
  if SameText(aKind, 'intrinsic-type') then
    Exit('type');
  if SameText(aKind, 'intrinsic-unit') then
    Exit('unit');
  Result := aKind;
end;

function SymbolMapSemanticSessionOptions(
  const aContext: TSymbolMapContext): TDelphiSemanticOptions;
var
  lCacheFileName: string;
begin
  lCacheFileName := '';
  if aContext.fProjectCacheRoot <> '' then
    lCacheFileName := TPath.Combine(aContext.fProjectCacheRoot,
      'semantic-unit-cache.sqlite3');
  Result := BuildSemanticSessionOptions(aContext.fProject.ProjectPath,
    aContext.fConfig, aContext.fPlatform, aContext.fDelphiVersion,
    aContext.fRsVarsPath, aContext.fEnvOptionsPath, lCacheFileName);
end;

function MapSemanticDefinition(const aResult: TDakSemanticSymbolDefinition):
  TSymbolMapDefinition;
begin
  Result := Default(TSymbolMapDefinition);
  Result.fFound := True;
  Result.fName := aResult.Name;
  Result.fKind := DakSymbolKind(aResult.Kind);
  Result.fOwnerName := aResult.OwnerName;
  Result.fUnitName := aResult.UnitName;
  Result.fFilePath := aResult.FileName;
  Result.fSourceKind := DakSourceKind(aResult.SourceKind);
  Result.fConfidence := 'semantic-resolved';
  Result.fSignature := aResult.Signature;
  Result.fTypeName := aResult.TypeName;
  Result.fLine := aResult.Line;
  Result.fCol := aResult.Column;
  Result.fEndLine := aResult.EndLine;
  Result.fEndCol := aResult.EndColumn;
end;

function MapSemanticUsage(const aUsage: TDakSemanticUsageReference): TSymbolMapReference;
begin
  Result := Default(TSymbolMapReference);
  Result.fName := aUsage.Name;
  Result.fUnitName := aUsage.UnitName;
  Result.fFilePath := aUsage.FileName;
  Result.fSourceKind := DakSourceKind(aUsage.SourceKind);
  Result.fConfidence := 'semantic-resolved';
  Result.fRole := aUsage.Role;
  Result.fSectionKind := aUsage.SectionKind;
  Result.fLine := aUsage.Line;
  Result.fCol := aUsage.Column;
  Result.fEndLine := aUsage.EndLine;
  Result.fEndCol := aUsage.EndColumn;
end;

function FindSemanticDefinitionByPosition(const aContext: TSymbolMapContext;
  const aFilePath: string; const aLine, aCol: Integer; out aDefinition: TSymbolMapDefinition;
  out aError: string): Boolean;
var
  lMetrics: TDakSemanticSymbolQueryMetrics;
  lQueryContext: IDakSemanticSymbolQueryContext;
  lResult: TDakSemanticSymbolDefinition;
  lSessionOptions: TDelphiSemanticOptions;
begin
  Result := False;
  aDefinition := Default(TSymbolMapDefinition);
  aError := '';
  lSessionOptions := SymbolMapSemanticSessionOptions(aContext);
  if not OpenSemanticSymbolQueryContext(lSessionOptions, lQueryContext, lMetrics,
    aError) then
    Exit(False);

  lResult := lQueryContext.FindDefinitionAtPosition(aFilePath, aLine, aCol);
  if lResult.Found then
    aDefinition := MapSemanticDefinition(lResult);
  Result := True;
end;

function FindSemanticReferencesByPosition(const aContext: TSymbolMapContext;
  const aFilePath: string; const aLine, aCol, aLimit: Integer; out aSymbol: string;
  out aReferences: TArray<TSymbolMapReference>; out aError: string): Boolean;
var
  i: Integer;
  lIndex: Integer;
  lMetrics: TDakSemanticSymbolQueryMetrics;
  lQueryContext: IDakSemanticSymbolQueryContext;
  lResult: TDakSemanticReferenceQueryResult;
  lSessionOptions: TDelphiSemanticOptions;
begin
  Result := False;
  aSymbol := '';
  SetLength(aReferences, 0);
  aError := '';
  lSessionOptions := SymbolMapSemanticSessionOptions(aContext);
  if not OpenSemanticSymbolQueryContext(lSessionOptions, lQueryContext, lMetrics,
    aError) then
    Exit(False);

  lResult := lQueryContext.FindReferencesAtPosition(aFilePath, aLine, aCol, aLimit);
  if lResult.SymbolName <> '' then
  begin
    aSymbol := lResult.SymbolName;
    for i := 0 to High(lResult.References) do
    begin
      lIndex := Length(aReferences);
      SetLength(aReferences, lIndex + 1);
      aReferences[lIndex] := MapSemanticUsage(lResult.References[i]);
    end;
  end;
  Result := True;
end;

function OpenQueryConnection(const aDbPath: string; out aDriverLink: TFDPhysSQLiteDriverLink;
  out aConnection: TFDConnection; out aError: string): Boolean;
begin
  Result := False;
  aDriverLink := nil;
  aConnection := nil;
  aError := '';
  try
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

procedure AddScopeEntry(const aEntries: TList<TSymbolMapUnitScopeEntry>; const aIndex: TDictionary<string, Integer>;
  const aUnitCacheKey: string; const aScope: TSymbolMapUnitScope);
var
  lEntry: TSymbolMapUnitScopeEntry;
  lIndex: Integer;
  lKey: string;
begin
  if aUnitCacheKey = '' then
    Exit;
  lKey := LowerCase(aUnitCacheKey);
  if aIndex.TryGetValue(lKey, lIndex) then
  begin
    lEntry := aEntries[lIndex];
    lEntry.fScope := aScope;
    aEntries[lIndex] := lEntry;
    Exit;
  end;
  lEntry.fUnitCacheKey := aUnitCacheKey;
  lEntry.fScope := aScope;
  aIndex.Add(lKey, aEntries.Count);
  aEntries.Add(lEntry);
end;

function LoadProjectUnitScopeEntries(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aEntries: TList<TSymbolMapUnitScopeEntry>; const aIndex: TDictionary<string, Integer>;
  out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lProjectKey: string;
  lQuery: TFDQuery;
  lScope: TSymbolMapUnitScope;
begin
  Result := False;
  lProjectKey := BuildSymbolMapProjectKey(aContext);
  if not OpenQueryConnection(aStatus.fProjectDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      lQuery.SQL.Text := 'select unit_cache_key, unit_name, file_path, source_kind from project_units ' +
        'where project_key = :project_key order by resolution_rank, unit_name';
      lQuery.ParamByName('project_key').AsString := lProjectKey;
      lQuery.Open;
      while not lQuery.Eof do
      begin
        lScope.fUnitName := lQuery.FieldByName('unit_name').AsWideString;
        lScope.fFilePath := lQuery.FieldByName('file_path').AsWideString;
        lScope.fSourceKind := lQuery.FieldByName('source_kind').AsWideString;
        AddScopeEntry(aEntries, aIndex, lQuery.FieldByName('unit_cache_key').AsWideString, lScope);
        lQuery.Next;
      end;
      Result := True;
    finally
      lQuery.Free;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

procedure AddCompilerUnitScopeEntries(const aStatus: TSymbolMapCacheStatus; const aProfile: TSymbolMapCompilerProfileResult;
  const aEntries: TList<TSymbolMapUnitScopeEntry>; const aIndex: TDictionary<string, Integer>; out aError: string);
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lQuery: TFDQuery;
  lScope: TSymbolMapUnitScope;
begin
  if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    raise Exception.Create(aError);
  try
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      lQuery.SQL.Text := 'select unit_cache_key, unit_name, source_kind, file_path_sample from compiler_profile_units ' +
        'where profile_key = :profile_key order by unit_name';
      lQuery.ParamByName('profile_key').AsString := aProfile.fProfileKey;
      lQuery.Open;
      while not lQuery.Eof do
      begin
        lScope.fUnitName := lQuery.FieldByName('unit_name').AsWideString;
        lScope.fFilePath := lQuery.FieldByName('file_path_sample').AsWideString;
        lScope.fSourceKind := lQuery.FieldByName('source_kind').AsWideString;
        AddScopeEntry(aEntries, aIndex, lQuery.FieldByName('unit_cache_key').AsWideString, lScope);
        lQuery.Next;
      end;
    finally
      lQuery.Free;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function LoadVisibleUnitScopeEntries(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; out aEntries: TArray<TSymbolMapUnitScopeEntry>;
  out aError: string; const aIncludeCompilerScopes: Boolean = True): Boolean;
var
  lIndex: TDictionary<string, Integer>;
  lEntries: TList<TSymbolMapUnitScopeEntry>;
begin
  Result := False;
  SetLength(aEntries, 0);
  lEntries := TList<TSymbolMapUnitScopeEntry>.Create;
  lIndex := nil;
  try
    lIndex := TDictionary<string, Integer>.Create;
    if not LoadProjectUnitScopeEntries(aContext, aStatus, lEntries, lIndex, aError) then
      Exit(False);
    try
      if aIncludeCompilerScopes then
        AddCompilerUnitScopeEntries(aStatus, aProfile, lEntries, lIndex, aError);
      aEntries := lEntries.ToArray;
      Result := True;
    except
      on E: Exception do
      begin
        SetLength(aEntries, 0);
        aError := E.Message;
      end;
    end;
  finally
    lIndex.Free;
    lEntries.Free;
  end;
end;

function TryFindCompilerIntrinsicDefinition(const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aName: string;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lQuery: TFDQuery;
begin
  Result := False;
  aDefinition := Default(TSymbolMapDefinition);
  if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      lQuery.SQL.Text := 'select name, kind, signature from compiler_intrinsics ' +
        'where profile_key = :profile_key and lower(name) = lower(:name)';
      lQuery.ParamByName('profile_key').AsString := aProfile.fProfileKey;
      lQuery.ParamByName('name').AsString := aName;
      lQuery.Open;
      if lQuery.Eof then
        Exit(False);

      aDefinition.fFound := True;
      aDefinition.fName := lQuery.FieldByName('name').AsWideString;
      aDefinition.fKind := lQuery.FieldByName('kind').AsWideString;
      aDefinition.fOwnerName := 'compiler';
      aDefinition.fSourceKind := 'compiler-intrinsic';
      aDefinition.fConfidence := 'exact';
      aDefinition.fSignature := lQuery.FieldByName('signature').AsWideString;
      Result := True;
    finally
      lQuery.Free;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function SqlStringLiteral(const aValue: string): string;
begin
  Result := '''' + StringReplace(aValue, '''', '''''', [rfReplaceAll]) + '''';
end;

procedure AttachProjectCache(const aConnection: TFDConnection; const aStatus: TSymbolMapCacheStatus);
begin
  aConnection.ExecSQL('attach database ' + SqlStringLiteral(aStatus.fProjectDbPath) + ' as projectdb');
end;

function DefinitionFromSymbolProjection(const aQuery: TFDQuery): TSymbolMapDefinition;
begin
  Result := Default(TSymbolMapDefinition);
  Result.fFound := True;
  Result.fName := aQuery.FieldByName('name').AsWideString;
  Result.fKind := DakSymbolKind(aQuery.FieldByName('kind').AsWideString);
  Result.fOwnerName := aQuery.FieldByName('owner_name').AsWideString;
  Result.fUnitName := aQuery.FieldByName('unit_name').AsWideString;
  Result.fFilePath := aQuery.FieldByName('file_path').AsWideString;
  Result.fSourceKind := aQuery.FieldByName('source_kind').AsWideString;
  Result.fConfidence := 'exact';
  Result.fSignature := aQuery.FieldByName('signature').AsWideString;
  Result.fTypeName := aQuery.FieldByName('type_name').AsWideString;
  Result.fLine := aQuery.FieldByName('line_no').AsInteger;
  Result.fCol := aQuery.FieldByName('col_no').AsInteger;
  Result.fEndLine := aQuery.FieldByName('end_line_no').AsInteger;
  Result.fEndCol := aQuery.FieldByName('end_col_no').AsInteger;
end;

function TryFindSymbolProjectionDefinition(const aContext: TSymbolMapContext;
  const aStatus: TSymbolMapCacheStatus; const aProfile: TSymbolMapCompilerProfileResult;
  const aName, aOwnerName: string; out aDefinition: TSymbolMapDefinition;
  out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lMemberOwnerClause: string;
  lProjectKey: string;
  lQuery: TFDQuery;
  lSymbolOwnerClause: string;
begin
  Result := False;
  aDefinition := Default(TSymbolMapDefinition);
  lProjectKey := BuildSymbolMapProjectKey(aContext);
  if aOwnerName <> '' then
  begin
    lMemberOwnerClause := 'and m.owner_name = :owner_name ';
    lSymbolOwnerClause := 'and s.owner_name = :owner_name ';
  end else begin
    lMemberOwnerClause := '';
    lSymbolOwnerClause := '';
  end;
  if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    AttachProjectCache(lConnection, aStatus);
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      lQuery.SQL.Text :=
        'select m.member_name as name, m.kind, m.owner_name, u.unit_name, u.file_path, u.source_kind, ' +
        ''''' as signature, m.type_name, m.line_no, m.col_no, m.line_no as end_line_no, m.col_no as end_col_no, ' +
        '0 as source_rank from members m join projectdb.project_units u on u.unit_cache_key = m.unit_cache_key ' +
        'where u.project_key = :project_key and lower(m.member_name) = lower(:name) ' + lMemberOwnerClause +
        'union all ' +
        'select s.name, s.kind, s.owner_name, u.unit_name, u.file_path, u.source_kind, s.signature, ' +
        's.type_name, s.line_no, s.col_no, s.end_line_no, s.end_col_no, 1 as source_rank ' +
        'from symbols s join projectdb.project_units u on u.unit_cache_key = s.unit_cache_key ' +
        'where u.project_key = :project_key and lower(s.name) = lower(:name) ' + lSymbolOwnerClause +
        'union all ' +
        'select s.name, s.kind, s.owner_name, cu.unit_name, cu.file_path_sample as file_path, ' +
        'cu.source_kind, s.signature, s.type_name, s.line_no, s.col_no, s.end_line_no, s.end_col_no, ' +
        '2 as source_rank from symbols s join compiler_profile_units cu on cu.unit_cache_key = s.unit_cache_key ' +
        'where cu.profile_key = :profile_key and lower(s.name) = lower(:name) ' + lSymbolOwnerClause +
        'order by source_rank, unit_name, line_no, col_no';
      lQuery.ParamByName('project_key').AsString := lProjectKey;
      lQuery.ParamByName('profile_key').AsString := aProfile.fProfileKey;
      lQuery.ParamByName('name').AsString := aName;
      if aOwnerName <> '' then
        lQuery.ParamByName('owner_name').AsString := aOwnerName;
      lQuery.Open;
      if lQuery.Eof then
        Exit(False);
      aDefinition := DefinitionFromSymbolProjection(lQuery);
      Result := True;
    finally
      lQuery.Free;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function SearchSymbolProjectionDefinitions(const aContext: TSymbolMapContext;
  const aStatus: TSymbolMapCacheStatus; const aProfile: TSymbolMapCompilerProfileResult;
  const aQueryText: string; const aLimit: Integer; out aDefinitions: TArray<TSymbolMapDefinition>;
  out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lIndex: Integer;
  lLimitSql: string;
  lProjectKey: string;
  lQuery: TFDQuery;
  lQueryPattern: string;
begin
  Result := False;
  SetLength(aDefinitions, 0);
  lProjectKey := BuildSymbolMapProjectKey(aContext);
  lQueryPattern := '%' + aQueryText + '%';
  if aLimit > 0 then
    lLimitSql := ' limit ' + aLimit.ToString
  else
    lLimitSql := '';
  if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    AttachProjectCache(lConnection, aStatus);
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      lQuery.SQL.Text :=
        'select m.member_name as name, m.kind, m.owner_name, u.unit_name, u.file_path, u.source_kind, ' +
        ''''' as signature, m.type_name, m.line_no, m.col_no, m.line_no as end_line_no, m.col_no as end_col_no, ' +
        '0 as source_rank from members m join projectdb.project_units u on u.unit_cache_key = m.unit_cache_key ' +
        'where u.project_key = :project_key and lower(m.member_name) like lower(:query) ' +
        'union all ' +
        'select s.name, s.kind, s.owner_name, u.unit_name, u.file_path, u.source_kind, s.signature, ' +
        's.type_name, s.line_no, s.col_no, s.end_line_no, s.end_col_no, 1 as source_rank ' +
        'from symbols s join projectdb.project_units u on u.unit_cache_key = s.unit_cache_key ' +
        'where u.project_key = :project_key and lower(s.name) like lower(:query) ' +
        'union all ' +
        'select s.name, s.kind, s.owner_name, cu.unit_name, cu.file_path_sample as file_path, ' +
        'cu.source_kind, s.signature, s.type_name, s.line_no, s.col_no, s.end_line_no, s.end_col_no, ' +
        '2 as source_rank from symbols s join compiler_profile_units cu on cu.unit_cache_key = s.unit_cache_key ' +
        'where cu.profile_key = :profile_key and lower(s.name) like lower(:query) ' +
        'union all ' +
        'select ci.name, ci.kind, ''compiler'' as owner_name, '''' as unit_name, '''' as file_path, ' +
        '''compiler-intrinsic'' as source_kind, ci.signature, '''' as type_name, 0 as line_no, 0 as col_no, ' +
        '0 as end_line_no, 0 as end_col_no, 3 as source_rank from compiler_intrinsics ci ' +
        'where ci.profile_key = :profile_key and lower(ci.name) like lower(:query) ' +
        'order by source_rank, owner_name, name, unit_name, line_no, col_no' + lLimitSql;
      lQuery.ParamByName('project_key').AsString := lProjectKey;
      lQuery.ParamByName('profile_key').AsString := aProfile.fProfileKey;
      lQuery.ParamByName('query').AsString := lQueryPattern;
      lQuery.Open;
      while not lQuery.Eof do
      begin
        lIndex := Length(aDefinitions);
        SetLength(aDefinitions, lIndex + 1);
        aDefinitions[lIndex] := DefinitionFromSymbolProjection(lQuery);
        aDefinitions[lIndex].fConfidence := 'name-match';
        lQuery.Next;
      end;
      Result := True;
    finally
      lQuery.Free;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function TryFindProjectedDeclarationAtPosition(const aContext: TSymbolMapContext;
  const aStatus: TSymbolMapCacheStatus; const aFilePath: string; const aLine, aCol: Integer;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lProjectKey: string;
  lQuery: TFDQuery;
begin
  Result := False;
  aDefinition := Default(TSymbolMapDefinition);
  lProjectKey := BuildSymbolMapProjectKey(aContext);
  if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    AttachProjectCache(lConnection, aStatus);
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      lQuery.SQL.Text :=
        'select u.unit_name as name, ''unit'' as kind, '''' as owner_name, u.unit_name, u.file_path, ' +
        'u.source_kind, '''' as signature, '''' as type_name, 1 as line_no, 1 as col_no, ' +
        '1 as end_line_no, 1 as end_col_no, 0 as source_rank from projectdb.project_units u ' +
        'where u.project_key = :project_key and u.file_path = :file_path and :line_no = 1 ' +
        'union all ' +
        'select s.name, s.kind, s.owner_name, u.unit_name, u.file_path, u.source_kind, s.signature, ' +
        's.type_name, s.line_no, s.col_no, s.end_line_no, s.end_col_no, 1 as source_rank ' +
        'from symbols s join projectdb.project_units u on u.unit_cache_key = s.unit_cache_key ' +
        'where u.project_key = :project_key and u.file_path = :file_path and s.line_no = :line_no ' +
        'and s.col_no <= :col_no and s.end_col_no >= :col_no ' +
        'union all ' +
        'select m.member_name as name, m.kind, m.owner_name, u.unit_name, u.file_path, u.source_kind, ' +
        ''''' as signature, m.type_name, m.line_no, m.col_no, m.line_no as end_line_no, ' +
        'm.col_no as end_col_no, 2 as source_rank from members m ' +
        'join projectdb.project_units u on u.unit_cache_key = m.unit_cache_key ' +
        'where u.project_key = :project_key and u.file_path = :file_path and m.line_no = :line_no ' +
        'and m.col_no <= :col_no order by source_rank, col_no desc limit 1';
      lQuery.ParamByName('project_key').AsString := lProjectKey;
      lQuery.ParamByName('file_path').AsString := aFilePath;
      lQuery.ParamByName('line_no').AsInteger := aLine;
      lQuery.ParamByName('col_no').AsInteger := aCol;
      lQuery.Open;
      if lQuery.Eof then
        Exit(False);
      aDefinition := DefinitionFromSymbolProjection(lQuery);
      Result := True;
    finally
      lQuery.Free;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function FindProjectedReferences(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aSymbol: string; const aLimit: Integer; out aReferences: TArray<TSymbolMapReference>;
  out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lIndex: Integer;
  lLimitSql: string;
  lProjectKey: string;
  lQuery: TFDQuery;
begin
  Result := False;
  SetLength(aReferences, 0);
  lProjectKey := BuildSymbolMapProjectKey(aContext);
  if aLimit > 0 then
    lLimitSql := ' limit ' + aLimit.ToString
  else
    lLimitSql := '';
  if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    AttachProjectCache(lConnection, aStatus);
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      lQuery.SQL.Text := 'select r.name, u.unit_name, u.file_path, u.source_kind, r.role, r.section_kind, ' +
        'r.line_no, r.col_no, r.end_line_no, r.end_col_no from symbol_map_references r ' +
        'join projectdb.project_units u on u.unit_cache_key = r.unit_cache_key ' +
        'where u.project_key = :project_key and lower(r.name) = lower(:name) ' +
        'order by u.file_path, r.line_no, r.col_no' + lLimitSql;
      lQuery.ParamByName('project_key').AsString := lProjectKey;
      lQuery.ParamByName('name').AsString := aSymbol;
      lQuery.Open;
      while not lQuery.Eof do
      begin
        lIndex := Length(aReferences);
        SetLength(aReferences, lIndex + 1);
        aReferences[lIndex].fName := lQuery.FieldByName('name').AsWideString;
        aReferences[lIndex].fUnitName := lQuery.FieldByName('unit_name').AsWideString;
        aReferences[lIndex].fFilePath := lQuery.FieldByName('file_path').AsWideString;
        aReferences[lIndex].fSourceKind := lQuery.FieldByName('source_kind').AsWideString;
        aReferences[lIndex].fConfidence := 'token-name-match';
        aReferences[lIndex].fRole := lQuery.FieldByName('role').AsWideString;
        aReferences[lIndex].fSectionKind := lQuery.FieldByName('section_kind').AsWideString;
        aReferences[lIndex].fLine := lQuery.FieldByName('line_no').AsInteger;
        aReferences[lIndex].fCol := lQuery.FieldByName('col_no').AsInteger;
        aReferences[lIndex].fEndLine := lQuery.FieldByName('end_line_no').AsInteger;
        aReferences[lIndex].fEndCol := lQuery.FieldByName('end_col_no').AsInteger;
        lQuery.Next;
      end;
      Result := True;
    finally
      lQuery.Free;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function SymbolMapProjectHasIndexedUnits(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lCount: Integer;
  lDriverLink: TFDPhysSQLiteDriverLink;
begin
  Result := False;
  if not OpenQueryConnection(aStatus.fProjectDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    lCount := lConnection.ExecSQLScalar('select count(*) from project_units where project_key = ?',
      [BuildSymbolMapProjectKey(aContext)]);
    Result := lCount > 0;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function FindSymbolMapDefinitionByName(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aName, aOwnerName: string;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
begin
  aDefinition := Default(TSymbolMapDefinition);
  if TryFindSymbolProjectionDefinition(aContext, aStatus, aProfile, aName, aOwnerName, aDefinition, aError) then
    Exit(True);
  if (aOwnerName = '') and TryFindCompilerIntrinsicDefinition(aStatus, aProfile, aName, aDefinition, aError) then
    Exit(True);
  Result := True;
end;

function FindSymbolMapDefinitionByPosition(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aFilePath: string; const aLine, aCol: Integer;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
begin
  aDefinition := Default(TSymbolMapDefinition);
  if not FindSemanticDefinitionByPosition(aContext, aFilePath, aLine, aCol, aDefinition,
    aError) then
    Exit(False);
  if aDefinition.fFound then
    Exit(True);

  if TryFindProjectedDeclarationAtPosition(aContext, aStatus, aFilePath, aLine, aCol, aDefinition, aError) then
    Exit(True);
  Result := True;
end;

function SearchSymbolMapDefinitions(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aQuery: string; const aLimit: Integer;
  out aDefinitions: TArray<TSymbolMapDefinition>; out aError: string): Boolean;
begin
  SetLength(aDefinitions, 0);
  Result := SearchSymbolProjectionDefinitions(aContext, aStatus, aProfile, aQuery, aLimit, aDefinitions, aError);
end;

function DescribeSymbolMapDefinition(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aName, aOwnerName: string;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
begin
  aDefinition := Default(TSymbolMapDefinition);
  if (aOwnerName = '') and TryFindCompilerIntrinsicDefinition(aStatus, aProfile, aName, aDefinition, aError) then
    Exit(True);
  if TryFindSymbolProjectionDefinition(aContext, aStatus, aProfile, aName, aOwnerName, aDefinition, aError) then
    Exit(True);
  Result := True;
end;

function FindSymbolMapReferences(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aSymbol: string; const aLimit: Integer;
  out aReferences: TArray<TSymbolMapReference>; out aError: string): Boolean;
begin
  SetLength(aReferences, 0);
  Result := FindProjectedReferences(aContext, aStatus, aSymbol, aLimit, aReferences, aError);
end;

function FindSymbolMapReferencesByPosition(const aContext: TSymbolMapContext; const aFilePath: string;
  const aLine, aCol, aLimit: Integer; out aSymbol: string;
  out aReferences: TArray<TSymbolMapReference>; out aError: string): Boolean;
begin
  Result := FindSemanticReferencesByPosition(aContext, aFilePath, aLine, aCol, aLimit,
    aSymbol, aReferences, aError);
end;

end.
