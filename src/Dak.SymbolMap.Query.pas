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
  System.Generics.Collections, System.SysUtils,
  FireDAC.Comp.Client, FireDAC.Phys.SQLite,
  DelphiSemantics.CompilerProfile, DelphiSemantics.Model, DelphiSemantics.Query;

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

function SemanticSourceKind(const aSourceKind: string): string;
begin
  if SameText(aSourceKind, 'project') then
    Exit('project-source');
  if SameText(aSourceKind, 'compiler-intrinsic') then
    Exit('compiler-profile');
  Result := aSourceKind;
end;

function DakSourceKind(const aSourceKind: string): string;
begin
  if SameText(aSourceKind, 'project-source') then
    Exit('project');
  if SameText(aSourceKind, 'compiler-profile') then
    Exit('compiler-intrinsic');
  Result := aSourceKind;
end;

function SemanticIntrinsicKind(const aKind: string): string;
begin
  if SameText(aKind, 'routine') then
    Exit('intrinsic-routine');
  if SameText(aKind, 'type') then
    Exit('intrinsic-type');
  if SameText(aKind, 'unit') then
    Exit('intrinsic-unit');
  Result := aKind;
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

procedure AddScopeEntry(var aEntries: TArray<TSymbolMapUnitScopeEntry>; const aUnitCacheKey: string;
  const aScope: TSymbolMapUnitScope);
var
  i: Integer;
  lIndex: Integer;
begin
  if aUnitCacheKey = '' then
    Exit;
  for i := 0 to High(aEntries) do
    if SameText(aEntries[i].fUnitCacheKey, aUnitCacheKey) then
    begin
      aEntries[i].fScope := aScope;
      Exit;
    end;
  lIndex := Length(aEntries);
  SetLength(aEntries, lIndex + 1);
  aEntries[lIndex].fUnitCacheKey := aUnitCacheKey;
  aEntries[lIndex].fScope := aScope;
end;

function LoadProjectUnitScopeEntries(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  out aEntries: TArray<TSymbolMapUnitScopeEntry>; out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lProjectKey: string;
  lQuery: TFDQuery;
  lScope: TSymbolMapUnitScope;
begin
  Result := False;
  SetLength(aEntries, 0);
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
        AddScopeEntry(aEntries, lQuery.FieldByName('unit_cache_key').AsWideString, lScope);
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
  var aEntries: TArray<TSymbolMapUnitScopeEntry>; out aError: string);
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
        'where profile_unit.profile_key = :profile_key order by profile_unit.unit_name';
      lQuery.ParamByName('profile_key').AsString := aProfile.fProfileKey;
      lQuery.Open;
      while not lQuery.Eof do
      begin
        lScope.fUnitName := lQuery.FieldByName('unit_name').AsWideString;
        lScope.fFilePath := lQuery.FieldByName('file_path_sample').AsWideString;
        lScope.fSourceKind := lQuery.FieldByName('source_kind').AsWideString;
        AddScopeEntry(aEntries, lQuery.FieldByName('unit_cache_key').AsWideString, lScope);
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
begin
  Result := False;
  if not LoadProjectUnitScopeEntries(aContext, aStatus, aEntries, aError) then
    Exit(False);
  try
    if aIncludeCompilerScopes then
      AddCompilerUnitScopeEntries(aStatus, aProfile, aEntries, aError);
    Result := True;
  except
    on E: Exception do
    begin
      SetLength(aEntries, 0);
      aError := E.Message;
    end;
  end;
end;

procedure LoadSemanticUnitHeader(const aConnection: TFDConnection; const aUnitCacheKey: string;
  const aScope: TSymbolMapUnitScope; var aModel: TDelphiSemanticUnitModel);
var
  lQuery: TFDQuery;
begin
  aModel := Default(TDelphiSemanticUnitModel);
  aModel.Success := True;
  aModel.UnitName := aScope.fUnitName;
  aModel.FileName := aScope.fFilePath;
  lQuery := TFDQuery.Create(nil);
  try
    lQuery.Connection := aConnection;
    lQuery.SQL.Text := 'select unit_name, file_path_sample from unit_models where unit_cache_key = :unit_cache_key';
    lQuery.ParamByName('unit_cache_key').AsString := aUnitCacheKey;
    lQuery.Open;
    if not lQuery.Eof then
    begin
      if aModel.UnitName = '' then
        aModel.UnitName := lQuery.FieldByName('unit_name').AsWideString;
      if aModel.FileName = '' then
        aModel.FileName := lQuery.FieldByName('file_path_sample').AsWideString;
    end;
  finally
    lQuery.Free;
  end;
end;

procedure LoadSemanticSymbols(const aConnection: TFDConnection; const aUnitCacheKey: string;
  const aDeclarations: TList<TDelphiSemanticDeclaration>; const aRoutines: TList<TDelphiSemanticRoutine>);
var
  lDeclaration: TDelphiSemanticDeclaration;
  lQuery: TFDQuery;
  lRoutine: TDelphiSemanticRoutine;
begin
  lQuery := TFDQuery.Create(nil);
  try
    lQuery.Connection := aConnection;
    lQuery.SQL.Text := 'select * from symbols where unit_cache_key = :unit_cache_key ' +
      'order by case section_kind when ''interface'' then 0 else 1 end, line_no, col_no';
    lQuery.ParamByName('unit_cache_key').AsString := aUnitCacheKey;
    lQuery.Open;
    while not lQuery.Eof do
    begin
      if SameText(lQuery.FieldByName('kind').AsWideString, 'routine') then
      begin
        lRoutine := Default(TDelphiSemanticRoutine);
        lRoutine.Name := lQuery.FieldByName('name').AsWideString;
        lRoutine.OwnerName := lQuery.FieldByName('owner_name').AsWideString;
        lRoutine.SectionKind := lQuery.FieldByName('section_kind').AsWideString;
        lRoutine.Signature := lQuery.FieldByName('signature').AsWideString;
        lRoutine.ReturnType := lQuery.FieldByName('type_name').AsWideString;
        lRoutine.Line := lQuery.FieldByName('line_no').AsInteger;
        lRoutine.Column := lQuery.FieldByName('col_no').AsInteger;
        aRoutines.Add(lRoutine);
      end else begin
        lDeclaration := Default(TDelphiSemanticDeclaration);
        lDeclaration.Name := lQuery.FieldByName('name').AsWideString;
        lDeclaration.Kind := lQuery.FieldByName('kind').AsWideString;
        lDeclaration.TypeName := lQuery.FieldByName('type_name').AsWideString;
        lDeclaration.SectionKind := lQuery.FieldByName('section_kind').AsWideString;
        lDeclaration.Line := lQuery.FieldByName('line_no').AsInteger;
        lDeclaration.Column := lQuery.FieldByName('col_no').AsInteger;
        aDeclarations.Add(lDeclaration);
      end;
      lQuery.Next;
    end;
  finally
    lQuery.Free;
  end;
end;

procedure LoadSemanticMembers(const aConnection: TFDConnection; const aUnitCacheKey: string;
  const aMembers: TList<TDelphiSemanticMember>);
var
  lMember: TDelphiSemanticMember;
  lQuery: TFDQuery;
begin
  lQuery := TFDQuery.Create(nil);
  try
    lQuery.Connection := aConnection;
    lQuery.SQL.Text := 'select * from members where unit_cache_key = :unit_cache_key order by line_no, col_no';
    lQuery.ParamByName('unit_cache_key').AsString := aUnitCacheKey;
    lQuery.Open;
    while not lQuery.Eof do
    begin
      lMember := Default(TDelphiSemanticMember);
      lMember.OwnerName := lQuery.FieldByName('owner_name').AsWideString;
      lMember.Name := lQuery.FieldByName('member_name').AsWideString;
      lMember.Kind := lQuery.FieldByName('kind').AsWideString;
      lMember.TypeName := lQuery.FieldByName('type_name').AsWideString;
      lMember.Visibility := lQuery.FieldByName('visibility').AsWideString;
      lMember.IsDefault := lQuery.FieldByName('is_default').AsInteger <> 0;
      lMember.IsIndexed := lQuery.FieldByName('is_indexed').AsInteger <> 0;
      lMember.Line := lQuery.FieldByName('line_no').AsInteger;
      lMember.Column := lQuery.FieldByName('col_no').AsInteger;
      aMembers.Add(lMember);
      lQuery.Next;
    end;
  finally
    lQuery.Free;
  end;
end;

procedure LoadSemanticReferences(const aConnection: TFDConnection; const aUnitCacheKey: string;
  const aReferences: TList<TDelphiSemanticReference>);
var
  lQuery: TFDQuery;
  lReference: TDelphiSemanticReference;
begin
  lQuery := TFDQuery.Create(nil);
  try
    lQuery.Connection := aConnection;
    lQuery.SQL.Text := 'select * from unit_references where unit_cache_key = :unit_cache_key order by line_no, col_no';
    lQuery.ParamByName('unit_cache_key').AsString := aUnitCacheKey;
    lQuery.Open;
    while not lQuery.Eof do
    begin
      lReference := Default(TDelphiSemanticReference);
      lReference.Name := lQuery.FieldByName('name').AsWideString;
      lReference.Role := lQuery.FieldByName('role').AsWideString;
      lReference.SectionKind := lQuery.FieldByName('section_kind').AsWideString;
      lReference.Line := lQuery.FieldByName('line_no').AsInteger;
      lReference.Column := lQuery.FieldByName('col_no').AsInteger;
      lReference.EndLine := lQuery.FieldByName('end_line_no').AsInteger;
      lReference.EndColumn := lQuery.FieldByName('end_col_no').AsInteger;
      aReferences.Add(lReference);
      lQuery.Next;
    end;
  finally
    lQuery.Free;
  end;
end;

function LoadSemanticUnitModel(const aStatus: TSymbolMapCacheStatus; const aUnitCacheKey: string;
  const aScope: TSymbolMapUnitScope; out aModel: TDelphiSemanticUnitModel; out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDeclarations: TList<TDelphiSemanticDeclaration>;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lMembers: TList<TDelphiSemanticMember>;
  lReferences: TList<TDelphiSemanticReference>;
  lRoutines: TList<TDelphiSemanticRoutine>;
begin
  Result := False;
  aModel := Default(TDelphiSemanticUnitModel);
  if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  lDeclarations := TList<TDelphiSemanticDeclaration>.Create;
  lMembers := TList<TDelphiSemanticMember>.Create;
  lReferences := TList<TDelphiSemanticReference>.Create;
  lRoutines := TList<TDelphiSemanticRoutine>.Create;
  try
    try
      LoadSemanticUnitHeader(lConnection, aUnitCacheKey, aScope, aModel);
      LoadSemanticSymbols(lConnection, aUnitCacheKey, lDeclarations, lRoutines);
      LoadSemanticMembers(lConnection, aUnitCacheKey, lMembers);
      LoadSemanticReferences(lConnection, aUnitCacheKey, lReferences);
      aModel.Declarations := lDeclarations.ToArray;
      aModel.Members := lMembers.ToArray;
      aModel.Routines := lRoutines.ToArray;
      aModel.References := lReferences.ToArray;
      Result := True;
    except
      on E: Exception do
      begin
        aError := E.Message;
      end;
    end;
  finally
    lRoutines.Free;
    lReferences.Free;
    lMembers.Free;
    lDeclarations.Free;
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function LoadSemanticCompilerProfile(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; out aSemanticProfile: TDelphiSemanticCompilerProfile;
  out aError: string): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lIndex: Integer;
  lQuery: TFDQuery;
begin
  Result := False;
  aSemanticProfile := Default(TDelphiSemanticCompilerProfile);
  aSemanticProfile.Name := aProfile.fProfileKey;
  aSemanticProfile.ProfileKey := aProfile.fProfileKey;
  aSemanticProfile.DelphiVersion := aProfile.fDelphiVersion;
  aSemanticProfile.Platform := aProfile.fPlatform;
  aSemanticProfile.IntrinsicSeedVersion := aProfile.fIntrinsicSeedVersion;
  aSemanticProfile.RtlSourceRoot := aContext.fRtlSourceRoot;
  if not OpenQueryConnection(aStatus.fCentralDbPath, lDriverLink, lConnection, aError) then
    Exit(False);
  try
    lQuery := TFDQuery.Create(nil);
    try
      lQuery.Connection := lConnection;
      lQuery.SQL.Text := 'select * from compiler_intrinsics where profile_key = :profile_key order by name';
      lQuery.ParamByName('profile_key').AsString := aProfile.fProfileKey;
      lQuery.Open;
      while not lQuery.Eof do
      begin
        lIndex := Length(aSemanticProfile.IntrinsicSymbols);
        SetLength(aSemanticProfile.IntrinsicSymbols, lIndex + 1);
        aSemanticProfile.IntrinsicSymbols[lIndex].Name := lQuery.FieldByName('name').AsWideString;
        aSemanticProfile.IntrinsicSymbols[lIndex].Kind := SemanticIntrinsicKind(lQuery.FieldByName('kind').AsWideString);
        aSemanticProfile.IntrinsicSymbols[lIndex].Signature := lQuery.FieldByName('signature').AsWideString;
        aSemanticProfile.IntrinsicSymbols[lIndex].Notes := lQuery.FieldByName('notes').AsWideString;
        aSemanticProfile.IntrinsicSymbols[lIndex].OwnerName := 'compiler';
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

procedure AddIndexedSemanticModel(var aContext: TDelphiSemanticSymbolQueryContext;
  const aModel: TDelphiSemanticUnitModel; const aSourceKind: string);
var
  lIndex: Integer;
begin
  lIndex := Length(aContext.IndexedUnitModels);
  SetLength(aContext.IndexedUnitModels, lIndex + 1);
  SetLength(aContext.IndexedUnitSourceKinds, lIndex + 1);
  aContext.IndexedUnitModels[lIndex] := aModel;
  aContext.IndexedUnitSourceKinds[lIndex] := aSourceKind;
end;

function BuildSemanticQueryContext(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; out aSemanticContext: TDelphiSemanticSymbolQueryContext;
  out aError: string; const aIncludeCompilerScopes: Boolean = True): Boolean;
var
  lEntry: TSymbolMapUnitScopeEntry;
  lHasPrimary: Boolean;
  lModel: TDelphiSemanticUnitModel;
  lScopeEntries: TArray<TSymbolMapUnitScopeEntry>;
  lSourceKind: string;
begin
  Result := False;
  aSemanticContext := Default(TDelphiSemanticSymbolQueryContext);
  if not LoadVisibleUnitScopeEntries(aContext, aStatus, aProfile, lScopeEntries, aError,
    aIncludeCompilerScopes) then
    Exit(False);
  if not LoadSemanticCompilerProfile(aContext, aStatus, aProfile, aSemanticContext.CompilerProfile, aError) then
    Exit(False);

  lHasPrimary := False;
  for lEntry in lScopeEntries do
  begin
    if not LoadSemanticUnitModel(aStatus, lEntry.fUnitCacheKey, lEntry.fScope, lModel, aError) then
      Exit(False);
    lSourceKind := SemanticSourceKind(lEntry.fScope.fSourceKind);
    if (not lHasPrimary) and SameText(lSourceKind, 'project-source') then
    begin
      aSemanticContext.UnitModel := lModel;
      lHasPrimary := True;
    end else begin
      AddIndexedSemanticModel(aSemanticContext, lModel, lSourceKind);
    end;
  end;

  if (not lHasPrimary) and (Length(aSemanticContext.IndexedUnitModels) > 0) then
  begin
    aSemanticContext.UnitModel := aSemanticContext.IndexedUnitModels[0];
    for var i := 1 to High(aSemanticContext.IndexedUnitModels) do
      aSemanticContext.IndexedUnitModels[i - 1] := aSemanticContext.IndexedUnitModels[i];
    for var i := 1 to High(aSemanticContext.IndexedUnitSourceKinds) do
      aSemanticContext.IndexedUnitSourceKinds[i - 1] := aSemanticContext.IndexedUnitSourceKinds[i];
    SetLength(aSemanticContext.IndexedUnitModels, Length(aSemanticContext.IndexedUnitModels) - 1);
    SetLength(aSemanticContext.IndexedUnitSourceKinds, Length(aSemanticContext.IndexedUnitSourceKinds) - 1);
    lHasPrimary := True;
  end;

  Result := lHasPrimary;
end;

function DefinitionFromSemanticResult(const aResult: TDelphiSemanticSymbolQueryResult): TSymbolMapDefinition;
begin
  Result := Default(TSymbolMapDefinition);
  Result.fFound := aResult.Found;
  Result.fName := aResult.Name;
  Result.fKind := DakSymbolKind(aResult.Kind);
  Result.fOwnerName := aResult.OwnerName;
  Result.fUnitName := aResult.UnitName;
  Result.fFilePath := aResult.FileName;
  Result.fSourceKind := DakSourceKind(aResult.SourceKind);
  Result.fConfidence := 'exact';
  if SameText(aResult.Confidence, 'member-name-match') or SameText(aResult.Confidence, 'declaration-name-match') or
    SameText(aResult.Confidence, 'routine-name-match') or SameText(aResult.Confidence, 'intrinsic-name-match') then
    Result.fConfidence := 'exact'
  else if aResult.Confidence <> '' then
    Result.fConfidence := aResult.Confidence;
  Result.fSignature := aResult.Signature;
  Result.fTypeName := aResult.TypeName;
  Result.fLine := aResult.Line;
  Result.fCol := aResult.Column;
  Result.fEndLine := aResult.EndLine;
  Result.fEndCol := aResult.EndColumn;
end;

function SearchDefinitionFromSemanticResult(const aResult: TDelphiSemanticSymbolQueryResult):
  TSymbolMapDefinition;
begin
  Result := DefinitionFromSemanticResult(aResult);
  if SameText(aResult.Confidence, 'member-name-match') or SameText(aResult.Confidence, 'declaration-name-match') or
    SameText(aResult.Confidence, 'routine-name-match') or SameText(aResult.Confidence, 'intrinsic-name-match') then
    Result.fConfidence := 'name-match';
end;

function SemanticSearchPhaseRank(const aResult: TDelphiSemanticSymbolQueryResult): Integer;
begin
  if SameText(aResult.Confidence, 'member-name-match') then
    Exit(0);
  if SameText(aResult.Confidence, 'intrinsic-name-match') or SameText(aResult.SourceKind, 'compiler-profile') then
    Exit(2);
  Result := 1;
end;

function SemanticSectionRank(const aSectionKind: string): Integer;
begin
  if SameText(aSectionKind, 'interface') then
    Exit(0);
  if SameText(aSectionKind, 'implementation') then
    Exit(1);
  Result := 2;
end;

function CompareSemanticSearchResults(const aLeft, aRight: TDelphiSemanticSymbolQueryResult): Integer;
var
  lLeftPhase: Integer;
  lRightPhase: Integer;
begin
  lLeftPhase := SemanticSearchPhaseRank(aLeft);
  lRightPhase := SemanticSearchPhaseRank(aRight);
  Result := lLeftPhase - lRightPhase;
  if Result <> 0 then
    Exit;

  if lLeftPhase = 0 then
  begin
    Result := CompareText(aLeft.OwnerName, aRight.OwnerName);
    if Result <> 0 then
      Exit;
  end else if lLeftPhase = 1 then
  begin
    Result := SemanticSectionRank(aLeft.SectionKind) - SemanticSectionRank(aRight.SectionKind);
    if Result <> 0 then
      Exit;
  end;

  Result := CompareText(aLeft.Name, aRight.Name);
  if Result <> 0 then
    Exit;
  Result := CompareText(aLeft.OwnerName, aRight.OwnerName);
  if Result <> 0 then
    Exit;
  Result := CompareText(aLeft.UnitName, aRight.UnitName);
  if Result <> 0 then
    Exit;
  Result := aLeft.Line - aRight.Line;
  if Result <> 0 then
    Exit;
  Result := aLeft.Column - aRight.Column;
end;

procedure SortSemanticResultsForDakSearch(var aResults: TArray<TDelphiSemanticSymbolQueryResult>);
var
  i: Integer;
  j: Integer;
  lTemp: TDelphiSemanticSymbolQueryResult;
begin
  for i := 0 to High(aResults) - 1 do
    for j := i + 1 to High(aResults) do
      if CompareSemanticSearchResults(aResults[i], aResults[j]) > 0 then
      begin
        lTemp := aResults[i];
        aResults[i] := aResults[j];
        aResults[j] := lTemp;
      end;
end;

procedure ApplySemanticResultLimit(var aResults: TArray<TDelphiSemanticSymbolQueryResult>; const aLimit: Integer);
begin
  if (aLimit > 0) and (Length(aResults) > aLimit) then
    SetLength(aResults, aLimit);
end;

function ReferenceFromSemanticResult(const aResult: TDelphiSemanticSymbolReferenceResult): TSymbolMapReference;
begin
  Result := Default(TSymbolMapReference);
  Result.fName := aResult.Name;
  Result.fUnitName := aResult.UnitName;
  Result.fFilePath := aResult.FileName;
  Result.fSourceKind := DakSourceKind(aResult.SourceKind);
  Result.fConfidence := aResult.Confidence;
  Result.fRole := aResult.Role;
  Result.fSectionKind := aResult.SectionKind;
  Result.fLine := aResult.Line;
  Result.fCol := aResult.Column;
  Result.fEndLine := aResult.EndLine;
  Result.fEndCol := aResult.EndColumn;
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
  Result := DescribeSymbolMapDefinition(aContext, aStatus, aProfile, aName, aOwnerName, aDefinition, aError);
end;

function FindSymbolMapDefinitionByPosition(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aFilePath: string; const aLine, aCol: Integer;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
var
  lResult: TDelphiSemanticSymbolQueryResult;
  lSemanticContext: TDelphiSemanticSymbolQueryContext;
begin
  Result := False;
  aDefinition := Default(TSymbolMapDefinition);
  if not BuildSemanticQueryContext(aContext, aStatus, aProfile, lSemanticContext, aError) then
    Exit(False);
  lResult := TDelphiSemanticSymbolQuery.FindDefinitionAtPosition(lSemanticContext, aFilePath, aLine, aCol);
  aDefinition := DefinitionFromSemanticResult(lResult);
  Result := True;
end;

function SearchSymbolMapDefinitions(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aQuery: string; const aLimit: Integer;
  out aDefinitions: TArray<TSymbolMapDefinition>; out aError: string): Boolean;
var
  i: Integer;
  lResults: TArray<TDelphiSemanticSymbolQueryResult>;
  lSemanticContext: TDelphiSemanticSymbolQueryContext;
begin
  Result := False;
  SetLength(aDefinitions, 0);
  if not BuildSemanticQueryContext(aContext, aStatus, aProfile, lSemanticContext, aError) then
    Exit(False);
  lResults := TDelphiSemanticSymbolQuery.SearchAllMatches(lSemanticContext, aQuery, 0);
  SortSemanticResultsForDakSearch(lResults);
  ApplySemanticResultLimit(lResults, aLimit);
  SetLength(aDefinitions, Length(lResults));
  for i := 0 to High(lResults) do
    aDefinitions[i] := SearchDefinitionFromSemanticResult(lResults[i]);
  Result := True;
end;

function DescribeSymbolMapDefinition(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aName, aOwnerName: string;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
var
  lResult: TDelphiSemanticSymbolQueryResult;
  lSemanticContext: TDelphiSemanticSymbolQueryContext;
begin
  Result := False;
  aDefinition := Default(TSymbolMapDefinition);
  if not BuildSemanticQueryContext(aContext, aStatus, aProfile, lSemanticContext, aError) then
    Exit(False);
  if aOwnerName <> '' then
    lResult := TDelphiSemanticSymbolQuery.DescribeOwnedMember(lSemanticContext, aOwnerName, aName)
  else
    lResult := TDelphiSemanticSymbolQuery.FindDefinitionByName(lSemanticContext, aName);
  aDefinition := DefinitionFromSemanticResult(lResult);
  Result := True;
end;

function FindSymbolMapReferences(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  const aProfile: TSymbolMapCompilerProfileResult; const aSymbol: string; const aLimit: Integer;
  out aReferences: TArray<TSymbolMapReference>; out aError: string): Boolean;
var
  i: Integer;
  lReferences: TArray<TDelphiSemanticSymbolReferenceResult>;
  lSemanticContext: TDelphiSemanticSymbolQueryContext;
begin
  Result := False;
  SetLength(aReferences, 0);
  if not BuildSemanticQueryContext(aContext, aStatus, aProfile, lSemanticContext, aError, False) then
    Exit(False);
  lReferences := TDelphiSemanticSymbolQuery.FindTokenReferences(lSemanticContext, aSymbol, aLimit);
  SetLength(aReferences, Length(lReferences));
  for i := 0 to High(lReferences) do
    aReferences[i] := ReferenceFromSemanticResult(lReferences[i]);
  Result := True;
end;

end.
