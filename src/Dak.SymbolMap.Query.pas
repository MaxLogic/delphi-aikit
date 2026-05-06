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

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils, System.Variants,
  FireDAC.Comp.Client, FireDAC.Phys.SQLite,
  Dak.SymbolMap.Indexer;

type
  TSymbolMapUnitScope = record
    fUnitName: string;
    fFilePath: string;
    fSourceKind: string;
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

procedure AddDefinition(var aDefinitions: TArray<TSymbolMapDefinition>; const aDefinition: TSymbolMapDefinition;
  const aLimit: Integer);
var
  lDefinition: TSymbolMapDefinition;
  lIndex: Integer;
begin
  if (aLimit > 0) and (Length(aDefinitions) >= aLimit) then
    Exit;
  if not aDefinition.fFound then
    Exit;
  for lDefinition in aDefinitions do
  begin
    if SameText(lDefinition.fName, aDefinition.fName) and SameText(lDefinition.fKind, aDefinition.fKind) and
      SameText(lDefinition.fOwnerName, aDefinition.fOwnerName) and
      SameText(lDefinition.fFilePath, aDefinition.fFilePath) and (lDefinition.fLine = aDefinition.fLine) then
      Exit;
  end;
  lIndex := Length(aDefinitions);
  SetLength(aDefinitions, lIndex + 1);
  aDefinitions[lIndex] := aDefinition;
end;

procedure AddReference(var aReferences: TArray<TSymbolMapReference>; const aReference: TSymbolMapReference;
  const aLimit: Integer);
var
  lIndex: Integer;
begin
  if (aLimit > 0) and (Length(aReferences) >= aLimit) then
    Exit;
  lIndex := Length(aReferences);
  SetLength(aReferences, lIndex + 1);
  aReferences[lIndex] := aReference;
end;

function LoadProjectUnitScopes(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  out aScopes: TDictionary<string, TSymbolMapUnitScope>; out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lProjectKey: string;
  lQuery: TFDQuery;
  lScope: TSymbolMapUnitScope;
begin
  Result := False;
  aScopes := TDictionary<string, TSymbolMapUnitScope>.Create;
  lProjectKey := BuildSymbolMapProjectKey(aContext);
  if not OpenQueryConnection(aStatus.fProjectDbPath, lDriverLink, lConnection, aError) then
  begin
    aScopes.Free;
    aScopes := nil;
    Exit(False);
  end;
  try
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
          lScope.fUnitName := lQuery.FieldByName('unit_name').AsString;
          lScope.fFilePath := lQuery.FieldByName('file_path').AsString;
          lScope.fSourceKind := lQuery.FieldByName('source_kind').AsString;
          aScopes.AddOrSetValue(lQuery.FieldByName('unit_cache_key').AsString, lScope);
          lQuery.Next;
        end;
        Result := True;
      finally
        lQuery.Free;
      end;
    except
      on E: Exception do
      begin
        aScopes.Free;
        aScopes := nil;
        aError := E.Message;
      end;
    end;
  finally
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

procedure AddCompilerUnitScopes(const aStatus: TSymbolMapCacheStatus; const aProfile: TSymbolMapCompilerProfileResult;
  const aScopes: TDictionary<string, TSymbolMapUnitScope>; out aError: string);
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
      lQuery.SQL.Text := 'select profile_unit.unit_cache_key, profile_unit.unit_name, profile_unit.source_kind, ' +
        'unit_model.file_path_sample from compiler_profile_units profile_unit ' +
        'join unit_models unit_model on unit_model.unit_cache_key = profile_unit.unit_cache_key ' +
        'where profile_unit.profile_key = :profile_key';
      lQuery.ParamByName('profile_key').AsString := aProfile.fProfileKey;
      lQuery.Open;
      while not lQuery.Eof do
      begin
        lScope.fUnitName := lQuery.FieldByName('unit_name').AsString;
        lScope.fFilePath := lQuery.FieldByName('file_path_sample').AsString;
        lScope.fSourceKind := lQuery.FieldByName('source_kind').AsString;
        aScopes.AddOrSetValue(lQuery.FieldByName('unit_cache_key').AsString, lScope);
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

function LoadVisibleUnitScopes(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; out aScopes: TDictionary<string, TSymbolMapUnitScope>;
  out aError: string): Boolean;
begin
  Result := False;
  if not LoadProjectUnitScopes(aContext, aStatus, aScopes, aError) then
    Exit(False);
  try
    AddCompilerUnitScopes(aStatus, aProfile, aScopes, aError);
    Result := True;
  except
    on E: Exception do
    begin
      aScopes.Free;
      aScopes := nil;
      aError := E.Message;
    end;
  end;
end;

function DefinitionFromSymbolRow(const aQuery: TFDQuery; const aScope: TSymbolMapUnitScope;
  const aConfidence: string): TSymbolMapDefinition;
begin
  Result := Default(TSymbolMapDefinition);
  Result.fFound := True;
  Result.fName := aQuery.FieldByName('name').AsString;
  Result.fKind := aQuery.FieldByName('kind').AsString;
  Result.fOwnerName := aQuery.FieldByName('owner_name').AsString;
  Result.fUnitName := aScope.fUnitName;
  Result.fFilePath := aScope.fFilePath;
  Result.fSourceKind := aScope.fSourceKind;
  Result.fConfidence := aConfidence;
  Result.fSignature := aQuery.FieldByName('signature').AsString;
  Result.fTypeName := aQuery.FieldByName('type_name').AsString;
  Result.fLine := aQuery.FieldByName('line_no').AsInteger;
  Result.fCol := aQuery.FieldByName('col_no').AsInteger;
  Result.fEndLine := aQuery.FieldByName('end_line_no').AsInteger;
  Result.fEndCol := aQuery.FieldByName('end_col_no').AsInteger;
end;

function DefinitionFromMemberRow(const aQuery: TFDQuery; const aScope: TSymbolMapUnitScope;
  const aConfidence: string): TSymbolMapDefinition;
begin
  Result := Default(TSymbolMapDefinition);
  Result.fFound := True;
  Result.fName := aQuery.FieldByName('member_name').AsString;
  Result.fKind := aQuery.FieldByName('kind').AsString;
  Result.fOwnerName := aQuery.FieldByName('owner_name').AsString;
  Result.fUnitName := aScope.fUnitName;
  Result.fFilePath := aScope.fFilePath;
  Result.fSourceKind := aScope.fSourceKind;
  Result.fConfidence := aConfidence;
  Result.fTypeName := aQuery.FieldByName('type_name').AsString;
  Result.fLine := aQuery.FieldByName('line_no').AsInteger;
  Result.fCol := aQuery.FieldByName('col_no').AsInteger;
  Result.fEndLine := Result.fLine;
  Result.fEndCol := Result.fCol;
end;

function DefinitionFromIntrinsicRow(const aQuery: TFDQuery; const aConfidence: string): TSymbolMapDefinition;
begin
  Result := Default(TSymbolMapDefinition);
  Result.fFound := True;
  Result.fName := aQuery.FieldByName('name').AsString;
  Result.fKind := aQuery.FieldByName('kind').AsString;
  Result.fSourceKind := 'compiler-intrinsic';
  Result.fConfidence := aConfidence;
  Result.fSignature := aQuery.FieldByName('signature').AsString;
end;

function ReferenceFromRow(const aQuery: TFDQuery; const aScope: TSymbolMapUnitScope): TSymbolMapReference;
begin
  Result.fName := aQuery.FieldByName('name').AsString;
  Result.fUnitName := aScope.fUnitName;
  Result.fFilePath := aScope.fFilePath;
  Result.fSourceKind := aScope.fSourceKind;
  Result.fConfidence := 'token-name-match';
  Result.fRole := aQuery.FieldByName('role').AsString;
  Result.fSectionKind := aQuery.FieldByName('section_kind').AsString;
  Result.fLine := aQuery.FieldByName('line_no').AsInteger;
  Result.fCol := aQuery.FieldByName('col_no').AsInteger;
  Result.fEndLine := aQuery.FieldByName('end_line_no').AsInteger;
  Result.fEndCol := aQuery.FieldByName('end_col_no').AsInteger;
end;

function TryUnitDefinitionByFile(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aFilePath: string; out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lProjectKey: string;
  lQuery: TFDQuery;
begin
  Result := False;
  aDefinition := Default(TSymbolMapDefinition);
  lProjectKey := BuildSymbolMapProjectKey(aContext);
  if not OpenQueryConnection(aStatus.fProjectDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      lQuery.SQL.Text := 'select unit_name, file_path, source_kind from project_units where project_key = :project_key ' +
        'and lower(file_path) = :file_path order by resolution_rank limit 1';
      lQuery.ParamByName('project_key').AsString := lProjectKey;
      lQuery.ParamByName('file_path').AsString := LowerCase(TPath.GetFullPath(aFilePath));
      lQuery.Open;
      if not lQuery.Eof then
      begin
        aDefinition.fFound := True;
        aDefinition.fName := lQuery.FieldByName('unit_name').AsString;
        aDefinition.fKind := 'unit';
        aDefinition.fUnitName := aDefinition.fName;
        aDefinition.fFilePath := lQuery.FieldByName('file_path').AsString;
        aDefinition.fSourceKind := lQuery.FieldByName('source_kind').AsString;
        aDefinition.fConfidence := 'exact';
        aDefinition.fLine := 1;
        aDefinition.fCol := 1;
        aDefinition.fEndLine := 1;
        aDefinition.fEndCol := Length(aDefinition.fName) + 5;
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

function SearchCentralRows(const aStatus: TSymbolMapCacheStatus; const aScopes: TDictionary<string,
  TSymbolMapUnitScope>; const aName, aOwnerName: string; const aExact: Boolean; const aLimit: Integer;
  out aDefinitions: TArray<TSymbolMapDefinition>; out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDefinition: TSymbolMapDefinition;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lIsExact: Boolean;
  lNormalized: string;
  lQuery: TFDQuery;
  lScope: TSymbolMapUnitScope;
begin
  Result := False;
  SetLength(aDefinitions, 0);
  lNormalized := LowerCase(Trim(aName));
  lIsExact := aExact;
  if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      if lIsExact then
        lQuery.SQL.Text := 'select * from members where normalized_member_name = :name and lower(owner_name) = :owner ' +
          'order by owner_name, member_name'
      else
        lQuery.SQL.Text := 'select * from members where normalized_member_name like :name order by owner_name, member_name';
      lQuery.ParamByName('name').AsString := IfThen(lIsExact, lNormalized, '%' + lNormalized + '%');
      if lIsExact then
        lQuery.ParamByName('owner').AsString := LowerCase(aOwnerName);
      lQuery.Open;
      while not lQuery.Eof do
      begin
        if aScopes.TryGetValue(lQuery.FieldByName('unit_cache_key').AsString, lScope) then
        begin
          lDefinition := DefinitionFromMemberRow(lQuery, lScope, IfThen(lIsExact, 'exact', 'name-match'));
          AddDefinition(aDefinitions, lDefinition, aLimit);
        end;
        lQuery.Next;
      end;

      if (aLimit = 0) or (Length(aDefinitions) < aLimit) then
      begin
        lQuery.Close;
        if lIsExact then
          lQuery.SQL.Text := 'select * from symbols where normalized_name = :name ' +
            'order by case section_kind when ''interface'' then 0 else 1 end, ' +
            'case kind when ''type'' then 0 else 1 end, name'
        else
          lQuery.SQL.Text := 'select * from symbols where normalized_name like :name order by section_kind, name';
        lQuery.ParamByName('name').AsString := IfThen(lIsExact, lNormalized, '%' + lNormalized + '%');
        lQuery.Open;
        while not lQuery.Eof do
        begin
          if aScopes.TryGetValue(lQuery.FieldByName('unit_cache_key').AsString, lScope) then
          begin
            lDefinition := DefinitionFromSymbolRow(lQuery, lScope, IfThen(lIsExact, 'exact', 'name-match'));
            AddDefinition(aDefinitions, lDefinition, aLimit);
          end;
          lQuery.Next;
        end;
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

procedure AddIntrinsicRows(const aStatus: TSymbolMapCacheStatus; const aProfile: TSymbolMapCompilerProfileResult;
  const aName: string; const aExact: Boolean; const aLimit: Integer; var aDefinitions: TArray<TSymbolMapDefinition>;
  out aError: string);
var
  lConnection: TFDConnection;
  lDefinition: TSymbolMapDefinition;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lNormalized: string;
  lQuery: TFDQuery;
begin
  lNormalized := LowerCase(Trim(aName));
  if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    raise Exception.Create(aError);
  try
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      if aExact then
        lQuery.SQL.Text := 'select * from compiler_intrinsics where profile_key = :profile_key and lower(name) = :name order by name'
      else
        lQuery.SQL.Text := 'select * from compiler_intrinsics where profile_key = :profile_key and lower(name) like :name ' +
          'order by name';
      lQuery.ParamByName('profile_key').AsString := aProfile.fProfileKey;
      if aExact then
        lQuery.ParamByName('name').AsString := lNormalized
      else
        lQuery.ParamByName('name').AsString := '%' + lNormalized + '%';
      lQuery.Open;
      while not lQuery.Eof do
      begin
        lDefinition := DefinitionFromIntrinsicRow(lQuery, IfThen(aExact, 'exact', 'name-match'));
        AddDefinition(aDefinitions, lDefinition, aLimit);
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

function FirstDefinition(const aDefinitions: TArray<TSymbolMapDefinition>; out aDefinition: TSymbolMapDefinition):
  Boolean;
begin
  aDefinition := Default(TSymbolMapDefinition);
  Result := Length(aDefinitions) > 0;
  if Result then
    aDefinition := aDefinitions[0];
end;

function FindSymbolMapDefinitionByName(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aName, aOwnerName: string;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
begin
  Result := DescribeSymbolMapDefinition(aContext, aStatus, aProfile, aName, aOwnerName, aDefinition, aError);
end;

function FindLineOffset(const aText: string; const aLine, aCol: Integer): Integer;
var
  lCurrentCol: Integer;
  lCurrentLine: Integer;
  lIndex: Integer;
begin
  Result := 0;
  lCurrentLine := 1;
  lCurrentCol := 1;
  lIndex := 1;
  while lIndex <= Length(aText) do
  begin
    if (lCurrentLine = aLine) and (lCurrentCol = aCol) then
      Exit(lIndex);
    if aText[lIndex] = #13 then
    begin
      Inc(lIndex);
      if (lIndex <= Length(aText)) and (aText[lIndex] = #10) then
        Inc(lIndex);
      Inc(lCurrentLine);
      lCurrentCol := 1;
    end else if aText[lIndex] = #10 then
    begin
      Inc(lIndex);
      Inc(lCurrentLine);
      lCurrentCol := 1;
    end else begin
      Inc(lIndex);
      Inc(lCurrentCol);
    end;
  end;
end;

function IsIdentifierChar(const aChar: Char): Boolean;
begin
  Result := ((aChar >= 'A') and (aChar <= 'Z')) or ((aChar >= 'a') and (aChar <= 'z')) or
    ((aChar >= '0') and (aChar <= '9')) or (aChar = '_');
end;

function IdentifierAtPosition(const aText: string; const aLine, aCol: Integer): string;
var
  lEndIndex: Integer;
  lIndex: Integer;
  lStartIndex: Integer;
begin
  Result := '';
  lIndex := FindLineOffset(aText, aLine, aCol);
  if lIndex = 0 then
    Exit;
  if (lIndex <= Length(aText)) and not IsIdentifierChar(aText[lIndex]) and (lIndex > 1) and
    IsIdentifierChar(aText[lIndex - 1]) then
    Dec(lIndex);
  if (lIndex > Length(aText)) or not IsIdentifierChar(aText[lIndex]) then
    Exit;
  lStartIndex := lIndex;
  while (lStartIndex > 1) and IsIdentifierChar(aText[lStartIndex - 1]) do
    Dec(lStartIndex);
  lEndIndex := lIndex;
  while (lEndIndex <= Length(aText)) and IsIdentifierChar(aText[lEndIndex]) do
    Inc(lEndIndex);
  Result := Copy(aText, lStartIndex, lEndIndex - lStartIndex);
end;

function FindSymbolMapDefinitionByPosition(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aFilePath: string; const aLine, aCol: Integer;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
var
  lEncodingName: string;
  lText: string;
  lToken: string;
begin
  Result := False;
  aDefinition := Default(TSymbolMapDefinition);
  if not TryLoadSymbolMapSourceFile(aFilePath, lText, lEncodingName, aError) then
    Exit(False);
  lToken := IdentifierAtPosition(lText, aLine, aCol);
  if SameText(lToken, 'unit') then
    Exit(TryUnitDefinitionByFile(aContext, aStatus, aFilePath, aDefinition, aError));
  if lToken = '' then
  begin
    Result := True;
    Exit;
  end;
  Result := FindSymbolMapDefinitionByName(aContext, aStatus, aProfile, lToken, '', aDefinition, aError);
end;

function SearchSymbolMapDefinitions(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aQuery: string; const aLimit: Integer;
  out aDefinitions: TArray<TSymbolMapDefinition>; out aError: string): Boolean;
var
  lScopes: TDictionary<string, TSymbolMapUnitScope>;
begin
  Result := False;
  SetLength(aDefinitions, 0);
  if not LoadVisibleUnitScopes(aContext, aStatus, aProfile, lScopes, aError) then
    Exit(False);
  try
    if not SearchCentralRows(aStatus, lScopes, aQuery, '', False, aLimit, aDefinitions, aError) then
      Exit(False);
    try
      AddIntrinsicRows(aStatus, aProfile, aQuery, False, aLimit, aDefinitions, aError);
    except
      on E: Exception do
      begin
        aError := E.Message;
        Exit(False);
      end;
    end;
    Result := True;
  finally
    lScopes.Free;
  end;
end;

function DescribeSymbolMapDefinition(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aName, aOwnerName: string;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
var
  lDefinitions: TArray<TSymbolMapDefinition>;
  lScopes: TDictionary<string, TSymbolMapUnitScope>;
begin
  Result := False;
  aDefinition := Default(TSymbolMapDefinition);
  if not LoadVisibleUnitScopes(aContext, aStatus, aProfile, lScopes, aError) then
    Exit(False);
  try
    if not SearchCentralRows(aStatus, lScopes, aName, aOwnerName, True, 1, lDefinitions, aError) then
      Exit(False);
    if not FirstDefinition(lDefinitions, aDefinition) and (aOwnerName = '') then
    begin
      try
        AddIntrinsicRows(aStatus, aProfile, aName, True, 1, lDefinitions, aError);
      except
        on E: Exception do
        begin
          aError := E.Message;
          Exit(False);
        end;
      end;
      FirstDefinition(lDefinitions, aDefinition);
    end;
    Result := True;
  finally
    lScopes.Free;
  end;
end;

function FindSymbolMapReferences(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aSymbol: string; const aLimit: Integer;
  out aReferences: TArray<TSymbolMapReference>; out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lQuery: TFDQuery;
  lReference: TSymbolMapReference;
  lScope: TSymbolMapUnitScope;
  lScopes: TDictionary<string, TSymbolMapUnitScope>;
begin
  Result := False;
  SetLength(aReferences, 0);
  if not LoadProjectUnitScopes(aContext, aStatus, lScopes, aError) then
    Exit(False);
  try
    if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
      Exit(False);
    try
      lQuery := TFDQuery.Create(nil);
      try
        lQuery.Connection := lConnection;
        lQuery.SQL.Text := 'select * from unit_references where normalized_name = :name order by line_no, col_no';
        lQuery.ParamByName('name').AsString := LowerCase(Trim(aSymbol));
        lQuery.Open;
        while not lQuery.Eof do
        begin
          if lScopes.TryGetValue(lQuery.FieldByName('unit_cache_key').AsString, lScope) then
          begin
            lReference := ReferenceFromRow(lQuery, lScope);
            AddReference(aReferences, lReference, aLimit);
          end;
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
  finally
    lScopes.Free;
  end;
end;

end.
