unit Dak.GlobalVars;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Hash,
  System.IOUtils,
  System.JSON,
  System.Math,
  System.Masks,
  System.StrUtils,
  System.SysUtils,
  System.Variants,
  Xml.XMLDoc,
  Xml.XMLIntf,
  DelphiAST.Classes,
  DelphiAST.Consts,
  DelphiAST.ProjectIndexer,
  DelphiSemantics.GlobalVars,
  DelphiSemantics.Model,
  Dak.Types;

function RunGlobalVarsCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  Dak.Messages,
  Dak.Project,
  FireDAC.DApt,
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

const
  cGlobalVarsCacheSchemaVersion = '2';

type
  TGlobalVarKind = (gvkVar, gvkThreadVar, gvkTypedConst, gvkClassVar);
  TAccessKind = (akRead, akWrite, akReadWrite);

  TGlobalVarRef = record
    UnitName: string;
    RoutineName: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    Access: TAccessKind;
  end;
TGlobalVarAmbiguity = record
    Name: string;
    UnitName: string;
    RoutineName: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    Access: TAccessKind;
    Candidates: string;
  end;

  TGlobalVarSymbol = class
  public
    Name: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    TypeName: string;
    Kind: TGlobalVarKind;
    UsedBy: TList<TGlobalVarRef>;
    constructor Create;
    destructor Destroy; override;
  end;
TProjectInfo = record
    ProjectPath: string;
    ProjectName: string;
    MainSourcePath: string;
    ParserDefines: string;
    ParserSearchPath: string;
    OutputPath: string;
    CachePath: string;
    ReportsPath: string;
    TempPath: string;
  end;

  TSourceAnalyzer = class
  private
    fProject: TProjectInfo;
fVisitedFiles: TDictionary<string, Byte>;
    fSymbols: TObjectList<TGlobalVarSymbol>;
    fAmbiguities: TList<TGlobalVarAmbiguity>;
class function NormalizeKey(const aValue: string): string; static;
class function BuildInputHash(const aProjectPath: string; const aFiles: TArray<string>): string; static;
    class function AccessToText(const aAccess: TAccessKind): string; static;
    class function KindToText(const aKind: TGlobalVarKind): string; static;
  public
    constructor Create(const aProject: TProjectInfo);
    destructor Destroy; override;
    function Analyze(out aInputHash: string): TObjectList<TGlobalVarSymbol>;
    function GetVisitedFiles: TArray<string>;
    property Ambiguities: TList<TGlobalVarAmbiguity> read fAmbiguities;
  end;

constructor TGlobalVarSymbol.Create;
begin
  inherited Create;
  UsedBy := TList<TGlobalVarRef>.Create;
end;

destructor TGlobalVarSymbol.Destroy;
begin
  UsedBy.Free;
  inherited Destroy;
end;
constructor TSourceAnalyzer.Create(const aProject: TProjectInfo);
begin
  inherited Create;
  fProject := aProject;
fVisitedFiles := TDictionary<string, Byte>.Create;
  fSymbols := TObjectList<TGlobalVarSymbol>.Create(True);
  fAmbiguities := TList<TGlobalVarAmbiguity>.Create;
end;

destructor TSourceAnalyzer.Destroy;
begin
  fAmbiguities.Free;
  fSymbols.Free;
  fVisitedFiles.Free;
inherited Destroy;
end;

class function TSourceAnalyzer.NormalizeKey(const aValue: string): string;
begin
  Result := AnsiLowerCase(Trim(aValue));
end;
class function TSourceAnalyzer.BuildInputHash(const aProjectPath: string; const aFiles: TArray<string>): string;
var
  lBuilder: TStringBuilder;
  lFiles: TStringList;
  lFileName: string;
  lIndex: Integer;
begin
  lFiles := TStringList.Create;
  lBuilder := TStringBuilder.Create;
  try
    lFiles.CaseSensitive := False;
    lFiles.Sorted := True;
    lFiles.Duplicates := dupIgnore;
    for lIndex := 0 to High(aFiles) do
    begin
      lFiles.Add(aFiles[lIndex]);
    end;
    lBuilder.AppendLine(TPath.GetFullPath(aProjectPath));
    for lIndex := 0 to lFiles.Count - 1 do
    begin
      lFileName := lFiles[lIndex];
      lBuilder.AppendLine(lFileName);
      lBuilder.AppendLine(DateTimeToStr(TFile.GetLastWriteTimeUtc(lFileName)));
      lBuilder.AppendLine(IntToStr(TFile.GetSize(lFileName)));
    end;
    Result := THashSHA2.GetHashString(lBuilder.ToString);
  finally
    lBuilder.Free;
    lFiles.Free;
  end;
end;

class function TSourceAnalyzer.AccessToText(const aAccess: TAccessKind): string;
begin
  case aAccess of
    akRead:
      Result := 'read';
    akWrite:
      Result := 'write';
  else
    Result := 'readwrite';
  end;
end;

class function TSourceAnalyzer.KindToText(const aKind: TGlobalVarKind): string;
begin
  case aKind of
    gvkVar:
      Result := 'var';
    gvkThreadVar:
      Result := 'threadvar';
    gvkTypedConst:
      Result := 'typedconst';
  else
    Result := 'classvar';
  end;
end;
function SplitSemanticListText(const aText: string): TArray<string>;
var
  lItems: TArray<string>;
  lPart: string;
  lResult: TList<string>;
begin
  lResult := TList<string>.Create;
  try
    lItems := SplitString(aText, ';');
    for lPart in lItems do
    begin
      if Trim(lPart) <> '' then
      begin
        lResult.Add(Trim(lPart));
      end;
    end;
    Result := lResult.ToArray;
  finally
    lResult.Free;
  end;
end;
function GlobalVarKindForSemanticGlobalKind(const aKind: string; out aGlobalKind: TGlobalVarKind): Boolean;
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

function AccessKindForSemanticAccess(const aAccess: string): TAccessKind;
begin
  if SameText(aAccess, 'read') then
    Result := TAccessKind.akRead
  else if SameText(aAccess, 'write') then
    Result := TAccessKind.akWrite
  else
    Result := TAccessKind.akReadWrite;
end;

function SemanticGlobalKey(const aUnitName, aName: string): string;
begin
  Result := AnsiLowerCase(Trim(aUnitName)) + '.' + AnsiLowerCase(Trim(aName));
end;

procedure AddSemanticUsage(const aSymbolsByKey: TDictionary<string, TGlobalVarSymbol>;
  const aUsage: TDelphiSemanticGlobalUsage);
var
  lRef: TGlobalVarRef;
  lSymbol: TGlobalVarSymbol;
begin
  if not aSymbolsByKey.TryGetValue(SemanticGlobalKey(aUsage.DeclaringUnitName, aUsage.Name),
    lSymbol) then
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

function TSourceAnalyzer.Analyze(out aInputHash: string): TObjectList<TGlobalVarSymbol>;
var
  lAnalysis: TDelphiSemanticGlobalAnalysis;
  lDeclaration: TDelphiSemanticGlobalDeclaration;
  lFiles: TArray<string>;
  lIndex: Integer;
  lIndexer: TProjectIndexer;
  lIndexedUnit: TProjectIndexer.TUnitInfo;
  lKind: TGlobalVarKind;
  lModels: TList<TDelphiSemanticUnitModel>;
  lOptions: TDelphiSemanticModelOptions;
  lSymbol: TGlobalVarSymbol;
  lSymbolsByKey: TDictionary<string, TGlobalVarSymbol>;
  lUsage: TDelphiSemanticGlobalUsage;
  lAmbiguity: TDelphiSemanticGlobalAmbiguity;
  lFullName: string;
begin
  lModels := nil;
  lIndexer := nil;
  lSymbolsByKey := nil;
  try
    lModels := TList<TDelphiSemanticUnitModel>.Create;
    lIndexer := TProjectIndexer.Create;
    lSymbolsByKey := TDictionary<string, TGlobalVarSymbol>.Create;

    lIndexer.Defines := fProject.ParserDefines;
    lIndexer.SearchPath := fProject.ParserSearchPath;
    lIndexer.Index(fProject.MainSourcePath);
    for lIndexedUnit in lIndexer.ParsedUnits do
    begin
      lFullName := Trim(lIndexedUnit.Path);
      if lFullName = '' then
        Continue;

      lFullName := TPath.GetFullPath(lFullName);
      if not TFile.Exists(lFullName) then
        Continue;

      if fVisitedFiles.ContainsKey(NormalizeKey(lFullName)) then
        Continue;

      fVisitedFiles.Add(NormalizeKey(lFullName), 1);
      lOptions := Default(TDelphiSemanticModelOptions);
      lOptions.SourceFileName := lFullName;
      lOptions.ProjectContextApplied := True;
      lOptions.Defines := SplitSemanticListText(fProject.ParserDefines);
      lOptions.SearchPaths := SplitSemanticListText(fProject.ParserSearchPath);
      lModels.Add(TDelphiSemanticUnitModelExtractor.ExtractFromFile(lOptions));
    end;

    lAnalysis := TDelphiSemanticGlobalAnalyzer.AnalyzeUnits(lModels.ToArray);
    for lDeclaration in lAnalysis.Declarations do
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
      fSymbols.Add(lSymbol);
      lSymbolsByKey.AddOrSetValue(SemanticGlobalKey(lSymbol.UnitName, lSymbol.Name), lSymbol);
    end;

    for lUsage in lAnalysis.Usages do
      AddSemanticUsage(lSymbolsByKey, lUsage);

    for lAmbiguity in lAnalysis.Ambiguities do
      AddSemanticAmbiguity(fAmbiguities, lAmbiguity);

    SetLength(lFiles, fVisitedFiles.Count);
    lIndex := 0;
    for lFullName in fVisitedFiles.Keys do
    begin
      lFiles[lIndex] := lFullName;
      Inc(lIndex);
    end;
    aInputHash := BuildInputHash(fProject.ProjectPath, lFiles);
    Result := fSymbols;
  finally
    lSymbolsByKey.Free;
    lIndexer.Free;
    lModels.Free;
  end;
end;

function TSourceAnalyzer.GetVisitedFiles: TArray<string>;
var
  lPair: TPair<string, Byte>;
  lIndex: Integer;
begin
  SetLength(Result, fVisitedFiles.Count);
  lIndex := 0;
  for lPair in fVisitedFiles do
  begin
    Result[lIndex] := lPair.Key;
    Inc(lIndex);
  end;
end;

function BuildProjectInfo(const aOptions: TAppOptions): TProjectInfo;
var
  lContext: TProjectAnalysisContext;
  lError: string;
begin
  if not TryBuildProjectAnalysisContext(aOptions, lContext, lError) then
  begin
    raise Exception.Create(lError);
  end;

  Result.ProjectPath := lContext.fProjectPath;
  Result.ProjectName := lContext.fProjectName;
  Result.MainSourcePath := lContext.fMainSourcePath;
  Result.ParserDefines := lContext.fParserDefines;
  Result.ParserSearchPath := lContext.fParserSearchPath;
  Result.OutputPath := TPath.Combine(lContext.fDakProjectRoot, 'global-vars');
  Result.CachePath := TPath.Combine(Result.OutputPath, 'cache');
  Result.ReportsPath := TPath.Combine(Result.OutputPath, 'reports');
  Result.TempPath := TPath.Combine(Result.OutputPath, 'tmp');
end;

procedure EnsureProjectFolders(const aProject: TProjectInfo);
begin
  TDirectory.CreateDirectory(aProject.CachePath);
  TDirectory.CreateDirectory(aProject.ReportsPath);
  TDirectory.CreateDirectory(aProject.TempPath);
end;

function CacheFileName(const aProject: TProjectInfo; const aOptions: TAppOptions): string;
begin
  if aOptions.fHasGlobalVarsCachePath and (Trim(aOptions.fGlobalVarsCachePath) <> '') then
  begin
    Result := aOptions.fGlobalVarsCachePath;
  end else
  begin
    Result := TPath.Combine(aProject.CachePath, 'global-vars-cache.sqlite3');
  end;
end;

function FileStampUtc(const aFileName: string): string;
begin
  Result := FormatDateTime('yyyymmddhhnnsszzz', TFile.GetLastWriteTimeUtc(aFileName));
end;

procedure EnsureCacheSchema(const aConnection: TFDConnection);
begin
  aConnection.ExecSQL('create table if not exists meta (key_name text primary key, value_text text not null)');
  aConnection.ExecSQL('create table if not exists files (path text primary key, stamp_utc text not null, size_bytes integer not null)');
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

procedure OpenCacheConnection(const aCacheFileName: string; out aDriverLink: TFDPhysSQLiteDriverLink;
  out aConnection: TFDConnection);
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

procedure SaveCachedSymbols(const aCacheFileName, aProjectPath, aInputHash: string; const aFiles: TArray<string>;
  const aSymbols: TObjectList<TGlobalVarSymbol>; const aAmbiguities: TList<TGlobalVarAmbiguity>);
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lFileName: string;
  lSymbol: TGlobalVarSymbol;
  lRef: TGlobalVarRef;
  lAmbiguity: TGlobalVarAmbiguity;
  lSymbolId: Int64;
begin
  TDirectory.CreateDirectory(TPath.GetDirectoryName(aCacheFileName));
  OpenCacheConnection(aCacheFileName, lDriverLink, lConnection);
  try
    EnsureCacheSchema(lConnection);
    lConnection.StartTransaction;
    try
      lConnection.ExecSQL('delete from meta');
      lConnection.ExecSQL('delete from files');
      lConnection.ExecSQL('delete from refs');
      lConnection.ExecSQL('delete from symbols');
      lConnection.ExecSQL('delete from ambiguities');
      lConnection.ExecSQL('insert into meta(key_name, value_text) values (?, ?)',
        ['schema_version', cGlobalVarsCacheSchemaVersion]);
      lConnection.ExecSQL('insert into meta(key_name, value_text) values (?, ?)', ['project_path', TPath.GetFullPath(aProjectPath)]);
      lConnection.ExecSQL('insert into meta(key_name, value_text) values (?, ?)', ['input_hash', aInputHash]);
      lConnection.ExecSQL('insert into files(path, stamp_utc, size_bytes) values (?, ?, ?)',
        [TPath.GetFullPath(aProjectPath), FileStampUtc(aProjectPath), TFile.GetSize(aProjectPath)]);
      for lFileName in aFiles do
      begin
        lConnection.ExecSQL('insert or replace into files(path, stamp_utc, size_bytes) values (?, ?, ?)',
          [TPath.GetFullPath(lFileName), FileStampUtc(lFileName), TFile.GetSize(lFileName)]);
      end;
      for lSymbol in aSymbols do
      begin
        lConnection.ExecSQL('insert into symbols(unit_name, file_name, name, type_name, kind, line_no, col_no) values (?, ?, ?, ?, ?, ?, ?)',
          [lSymbol.UnitName, lSymbol.FileName, lSymbol.Name, lSymbol.TypeName, TSourceAnalyzer.KindToText(lSymbol.Kind),
          lSymbol.Line, lSymbol.Column]);
        lSymbolId := lConnection.ExecSQLScalar('select last_insert_rowid()');
        for lRef in lSymbol.UsedBy do
        begin
          lConnection.ExecSQL('insert into refs(symbol_id, unit_name, routine_name, file_name, line_no, col_no, access_kind) values (?, ?, ?, ?, ?, ?, ?)',
            [lSymbolId, lRef.UnitName, lRef.RoutineName, lRef.FileName, lRef.Line, lRef.Column,
            TSourceAnalyzer.AccessToText(lRef.Access)]);
        end;
      end;
      for lAmbiguity in aAmbiguities do
      begin
        lConnection.ExecSQL('insert into ambiguities(name, unit_name, routine_name, file_name, line_no, col_no, access_kind, candidates) values (?, ?, ?, ?, ?, ?, ?, ?)',
          [lAmbiguity.Name, lAmbiguity.UnitName, lAmbiguity.RoutineName, lAmbiguity.FileName, lAmbiguity.Line,
          lAmbiguity.Column, TSourceAnalyzer.AccessToText(lAmbiguity.Access), lAmbiguity.Candidates]);
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

function TryLoadCachedSymbols(const aCacheFileName, aProjectPath: string; out aSymbols: TObjectList<TGlobalVarSymbol>;
  out aAmbiguities: TList<TGlobalVarAmbiguity>): Boolean;
var
  lConnection: TFDConnection;
  lDriverLink: TFDPhysSQLiteDriverLink;
  lQuery: TFDQuery;
  lExpected: string;
  lSymbolById: TDictionary<Int64, TGlobalVarSymbol>;
  lSymbol: TGlobalVarSymbol;
  lRef: TGlobalVarRef;
  lAmbiguity: TGlobalVarAmbiguity;
begin
  Result := False;
  aSymbols := nil;
  aAmbiguities := nil;
  if not TFile.Exists(aCacheFileName) then
  begin
    Exit;
  end;
  OpenCacheConnection(aCacheFileName, lDriverLink, lConnection);
  lSymbolById := TDictionary<Int64, TGlobalVarSymbol>.Create;
  lQuery := TFDQuery.Create(nil);
  try
    lQuery.Connection := lConnection;
    EnsureCacheSchema(lConnection);
    lExpected := VarToStr(lConnection.ExecSQLScalar(
      'select value_text from meta where key_name = ?', ['schema_version']));
    if lExpected <> cGlobalVarsCacheSchemaVersion then
    begin
      Exit;
    end;
    lExpected := VarToStr(lConnection.ExecSQLScalar(
      'select value_text from meta where key_name = ?', ['project_path']));
    if not SameText(TPath.GetFullPath(aProjectPath), lExpected) then
    begin
      Exit;
    end;
    lQuery.SQL.Text := 'select path, stamp_utc, size_bytes from files';
    lQuery.Open;
    while not lQuery.Eof do
    begin
      if (not TFile.Exists(lQuery.Fields[0].AsString))
        or (FileStampUtc(lQuery.Fields[0].AsString) <> lQuery.Fields[1].AsString)
        or (TFile.GetSize(lQuery.Fields[0].AsString) <> lQuery.Fields[2].AsLargeInt) then
      begin
        Exit;
      end;
      lQuery.Next;
    end;
    aSymbols := TObjectList<TGlobalVarSymbol>.Create(True);
    aAmbiguities := TList<TGlobalVarAmbiguity>.Create;
    lQuery.Close;
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
    lQuery.Free;
    lSymbolById.Free;
    lConnection.Free;
    lDriverLink.Free;
  end;
end;

function MatchPatternText(const aValue, aPattern: string): Boolean;
var
  lMask: string;
begin
  lMask := aPattern;
  if (Pos('*', lMask) = 0) and (Pos('?', lMask) = 0) then
  begin
    lMask := '*' + lMask + '*';
  end;
  Result := MatchesMask(UpperCase(aValue), UpperCase(lMask));
end;

function RefMatchesAccess(const aRef: TGlobalVarRef; const aOptions: TAppOptions): Boolean;
begin
  if aOptions.fGlobalVarsReadsOnly then
  begin
    Exit(aRef.Access in [akRead, akReadWrite]);
  end;
  if aOptions.fGlobalVarsWritesOnly then
  begin
    Exit(aRef.Access in [akWrite, akReadWrite]);
  end;
  Result := True;
end;

function SymbolMatchesFilters(const aSymbol: TGlobalVarSymbol; const aOptions: TAppOptions): Boolean;
var
  lRef: TGlobalVarRef;
begin
  Result := True;
  if aOptions.fHasGlobalVarsUnitFilter and not MatchPatternText(aSymbol.UnitName, aOptions.fGlobalVarsUnitFilter) then
  begin
    Exit(False);
  end;
  if aOptions.fHasGlobalVarsNameFilter and not MatchPatternText(aSymbol.Name, aOptions.fGlobalVarsNameFilter) then
  begin
    Exit(False);
  end;
  if aOptions.fGlobalVarsUnusedOnly then
  begin
    Exit(aSymbol.UsedBy.Count = 0);
  end;
  if aOptions.fGlobalVarsReadsOnly or aOptions.fGlobalVarsWritesOnly then
  begin
    for lRef in aSymbol.UsedBy do
    begin
      if RefMatchesAccess(lRef, aOptions) then
      begin
        Exit(True);
      end;
    end;
    Exit(False);
  end;
end;

function GlobalVarsFilterText(const aOptions: TAppOptions): string;
var
  lParts: TStringList;
begin
  lParts := TStringList.Create;
  try
    if aOptions.fGlobalVarsUnusedOnly then
      lParts.Add('unused-only');
    if aOptions.fGlobalVarsReadsOnly then
      lParts.Add('reads-only');
    if aOptions.fGlobalVarsWritesOnly then
      lParts.Add('writes-only');
    if aOptions.fHasGlobalVarsUnitFilter then
      lParts.Add('unit=' + aOptions.fGlobalVarsUnitFilter);
    if aOptions.fHasGlobalVarsNameFilter then
      lParts.Add('name=' + aOptions.fGlobalVarsNameFilter);
    if lParts.Count = 0 then
      Result := 'all'
    else
    begin
      Result := StringReplace(Trim(lParts.Text), sLineBreak, ';', [rfReplaceAll]);
      if Result.EndsWith(';') then
      begin
        Delete(Result, Length(Result), 1);
      end;
    end;
  finally
    lParts.Free;
  end;
end;

function CountUnusedSymbols(const aSymbols: TObjectList<TGlobalVarSymbol>): Integer;
var
  lSymbol: TGlobalVarSymbol;
begin
  Result := 0;
  for lSymbol in aSymbols do
  begin
    if lSymbol.UsedBy.Count = 0 then
    begin
      Inc(Result);
    end;
  end;
end;

function BuildFilteredSymbols(const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aOptions: TAppOptions): TObjectList<TGlobalVarSymbol>;
var
  lSymbol: TGlobalVarSymbol;
begin
  Result := TObjectList<TGlobalVarSymbol>.Create(False);
  for lSymbol in aSymbols do
  begin
    if not SymbolMatchesFilters(lSymbol, aOptions) then
    begin
      Continue;
    end;
    Result.Add(lSymbol);
  end;
end;

procedure AppendSummaryJson(const aRoot: TJSONObject; const aAllSymbols,
  aFilteredSymbols: TObjectList<TGlobalVarSymbol>; const aAmbiguities: TList<TGlobalVarAmbiguity>;
  const aOptions: TAppOptions);
var
  lSummary: TJSONObject;
  lUnusedCount: Integer;
begin
  lUnusedCount := CountUnusedSymbols(aAllSymbols);
  lSummary := TJSONObject.Create;
  lSummary.AddPair('total', TJSONNumber.Create(aAllSymbols.Count));
  lSummary.AddPair('used', TJSONNumber.Create(aAllSymbols.Count - lUnusedCount));
  lSummary.AddPair('unused', TJSONNumber.Create(lUnusedCount));
  lSummary.AddPair('ambiguities', TJSONNumber.Create(aAmbiguities.Count));
  lSummary.AddPair('emitted', TJSONNumber.Create(aFilteredSymbols.Count));
  lSummary.AddPair('filter', GlobalVarsFilterText(aOptions));
  aRoot.AddPair('summary', lSummary);
end;

function RenderJson(const aAllSymbols, aFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aOptions: TAppOptions): string;
var
  lRoot: TJSONObject;
  lSymbols: TJSONArray;
  lAmbiguitiesJson: TJSONArray;
  lSymbol: TGlobalVarSymbol;
  lItem: TJSONObject;
  lUsedBy: TJSONArray;
  lRef: TGlobalVarRef;
  lAmbiguity: TGlobalVarAmbiguity;
begin
  lRoot := TJSONObject.Create;
  try
    AppendSummaryJson(lRoot, aAllSymbols, aFilteredSymbols, aAmbiguities, aOptions);
    lSymbols := TJSONArray.Create;
    lRoot.AddPair('symbols', lSymbols);
    for lSymbol in aFilteredSymbols do
    begin
      lItem := TJSONObject.Create;
      lItem.AddPair('declaringUnit', lSymbol.UnitName);
      lItem.AddPair('fileName', lSymbol.FileName);
      lItem.AddPair('name', lSymbol.Name);
      lItem.AddPair('type', lSymbol.TypeName);
      lItem.AddPair('kind', TSourceAnalyzer.KindToText(lSymbol.Kind));
      lItem.AddPair('line', TJSONNumber.Create(lSymbol.Line));
      lItem.AddPair('column', TJSONNumber.Create(lSymbol.Column));
      lUsedBy := TJSONArray.Create;
      for lRef in lSymbol.UsedBy do
      begin
        lUsedBy.AddElement(TJSONObject.Create
          .AddPair('unit', lRef.UnitName)
          .AddPair('routine', lRef.RoutineName)
          .AddPair('file', lRef.FileName)
          .AddPair('line', TJSONNumber.Create(lRef.Line))
          .AddPair('column', TJSONNumber.Create(lRef.Column))
          .AddPair('access', TSourceAnalyzer.AccessToText(lRef.Access)));
      end;
      lItem.AddPair('usedBy', lUsedBy);
      lSymbols.AddElement(lItem);
    end;
    lAmbiguitiesJson := TJSONArray.Create;
    lRoot.AddPair('ambiguities', lAmbiguitiesJson);
    for lAmbiguity in aAmbiguities do
    begin
      lAmbiguitiesJson.AddElement(TJSONObject.Create
        .AddPair('name', lAmbiguity.Name)
        .AddPair('unit', lAmbiguity.UnitName)
        .AddPair('routine', lAmbiguity.RoutineName)
        .AddPair('file', lAmbiguity.FileName)
        .AddPair('line', TJSONNumber.Create(lAmbiguity.Line))
        .AddPair('column', TJSONNumber.Create(lAmbiguity.Column))
        .AddPair('access', TSourceAnalyzer.AccessToText(lAmbiguity.Access))
        .AddPair('candidates', lAmbiguity.Candidates));
    end;
    Result := lRoot.Format(2);
  finally
    lRoot.Free;
  end;
end;

function RenderText(const aAllSymbols, aFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aOptions: TAppOptions): string;
var
  lBuilder: TStringBuilder;
  lSymbol: TGlobalVarSymbol;
  lRef: TGlobalVarRef;
  lUnusedCount: Integer;
  lAmbiguity: TGlobalVarAmbiguity;
begin
  lBuilder := TStringBuilder.Create;
  try
    lUnusedCount := CountUnusedSymbols(aAllSymbols);
    lBuilder.AppendLine(Format('Summary: total=%d used=%d unused=%d ambiguities=%d emitted=%d filter=%s',
      [aAllSymbols.Count, aAllSymbols.Count - lUnusedCount, lUnusedCount, aAmbiguities.Count, aFilteredSymbols.Count,
      GlobalVarsFilterText(aOptions)]));
    for lSymbol in aFilteredSymbols do
    begin
      lBuilder.AppendLine(Format('%s.%s: %s [%s] (%s:%d)', [lSymbol.UnitName, lSymbol.Name, lSymbol.TypeName, TSourceAnalyzer.KindToText(lSymbol.Kind), lSymbol.FileName, lSymbol.Line]));
      if lSymbol.UsedBy.Count = 0 then
      begin
        lBuilder.AppendLine('  used by: none');
      end else
      begin
        lBuilder.AppendLine('  used by:');
        for lRef in lSymbol.UsedBy do
        begin
          lBuilder.AppendLine(Format('    %s.%s [%s] (%s:%d)', [lRef.UnitName, lRef.RoutineName, TSourceAnalyzer.AccessToText(lRef.Access), lRef.FileName, lRef.Line]));
        end;
      end;
    end;
    if aAmbiguities.Count > 0 then
    begin
      lBuilder.AppendLine;
      lBuilder.AppendLine('Ambiguities:');
      for lAmbiguity in aAmbiguities do
      begin
        lBuilder.AppendLine(Format('  %s in %s.%s [%s] (%s:%d) candidates=%s',
          [lAmbiguity.Name, lAmbiguity.UnitName, lAmbiguity.RoutineName,
          TSourceAnalyzer.AccessToText(lAmbiguity.Access), lAmbiguity.FileName, lAmbiguity.Line, lAmbiguity.Candidates]));
      end;
    end;
    Result := TrimRight(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

function RunGlobalVarsCommand(const aOptions: TAppOptions): Integer;
var
  lProject: TProjectInfo;
  lAnalyzer: TSourceAnalyzer;
  lSymbols: TObjectList<TGlobalVarSymbol>;
  lCacheSymbols: TObjectList<TGlobalVarSymbol>;
  lFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  lAmbiguities: TList<TGlobalVarAmbiguity>;
  lCacheAmbiguities: TList<TGlobalVarAmbiguity>;
  lOutputText: string;
  lOutputPath: string;
  lInputHash: string;
  lVisitedFiles: TArray<string>;
  lCacheFileName: string;
begin
  Result := 0;
  lProject := BuildProjectInfo(aOptions);
  EnsureProjectFolders(lProject);
  lCacheFileName := CacheFileName(lProject, aOptions);
  lAnalyzer := nil;
  lCacheSymbols := nil;
  lCacheAmbiguities := nil;
  lSymbols := nil;
  lAmbiguities := nil;
  try
    if (aOptions.fGlobalVarsRefresh <> TGlobalVarsRefresh.gvrForce)
      and TryLoadCachedSymbols(lCacheFileName, lProject.ProjectPath, lCacheSymbols, lCacheAmbiguities) then
    begin
      lSymbols := lCacheSymbols;
      lAmbiguities := lCacheAmbiguities;
    end else
    begin
      lAnalyzer := TSourceAnalyzer.Create(lProject);
      lSymbols := lAnalyzer.Analyze(lInputHash);
      lVisitedFiles := lAnalyzer.GetVisitedFiles;
      lAmbiguities := lAnalyzer.Ambiguities;
      SaveCachedSymbols(lCacheFileName, lProject.ProjectPath, lInputHash, lVisitedFiles, lSymbols, lAmbiguities);
    end;
    lFilteredSymbols := BuildFilteredSymbols(lSymbols, aOptions);
    try
      if aOptions.fGlobalVarsFormat = TGlobalVarsFormat.gvfJson then
      begin
        lOutputText := RenderJson(lSymbols, lFilteredSymbols, lAmbiguities, aOptions);
      end else
      begin
        lOutputText := RenderText(lSymbols, lFilteredSymbols, lAmbiguities, aOptions);
      end;
    finally
      lFilteredSymbols.Free;
    end;
    if aOptions.fHasGlobalVarsOutputPath and (Trim(aOptions.fGlobalVarsOutputPath) <> '') then
    begin
      lOutputPath := aOptions.fGlobalVarsOutputPath;
    end else if aOptions.fGlobalVarsFormat = TGlobalVarsFormat.gvfJson then
    begin
      lOutputPath := TPath.Combine(lProject.ReportsPath, 'global-vars.json');
    end else
    begin
      lOutputPath := TPath.Combine(lProject.ReportsPath, 'global-vars.txt');
    end;
    if lOutputPath = '-' then
    begin
      WriteLn(lOutputText);
    end else
    begin
      if TPath.GetDirectoryName(lOutputPath) <> '' then
      begin
        TDirectory.CreateDirectory(TPath.GetDirectoryName(lOutputPath));
      end;
      TFile.WriteAllText(lOutputPath, lOutputText, TEncoding.UTF8);
      WriteLn('Wrote: ' + lOutputPath);
    end;
  finally
    lCacheAmbiguities.Free;
    lCacheSymbols.Free;
    lAnalyzer.Free;
  end;
end;

end.
