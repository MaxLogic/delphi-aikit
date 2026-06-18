unit Dak.SymbolMap.Api;

interface

uses
  Dak.SymbolMap.Cache, Dak.SymbolMap.Context, Dak.SymbolMap.Query, Dak.Types;

type
  TSymbolMapApiStatus = record
    fCacheStatus: TSymbolMapCacheStatus;
    fCompilerProfile: TSymbolMapCompilerProfileResult;
    fProjectIndexed: Boolean;
    fDiagnostics: TArray<string>;
  end;

  TSymbolMapApiLookupResult = record
    fDefinition: TSymbolMapDefinition;
    fStatus: TSymbolMapApiStatus;
  end;

  TSymbolMapApiSession = record
  private
    fApiContext: TSymbolMapContext;
    fApiStatus: TSymbolMapApiStatus;
    fIsPrepared: Boolean;
  public
    function DescribeDefinitionByName(const aName, aOwnerName: string; out aDefinition: TSymbolMapDefinition;
      out aError: string): Boolean;
    function LookupDefinitionByName(const aName, aOwnerName: string; out aResult: TSymbolMapApiLookupResult;
      out aError: string): Boolean;
    function LookupDefinitionByPosition(const aFilePath: string; const aLine, aCol: Integer;
      out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
    property Prepared: Boolean read fIsPrepared;
    property Status: TSymbolMapApiStatus read fApiStatus;
  end;

function PrepareSymbolMapApiSession(const aOptions: TAppOptions; out aSession: TSymbolMapApiSession;
  out aError: string): Boolean;
function LookupSymbolMapDefinitionByName(const aSession: TSymbolMapApiSession; const aName, aOwnerName: string;
  out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
function LookupSymbolMapDefinitionByPosition(const aSession: TSymbolMapApiSession; const aFilePath: string;
  const aLine, aCol: Integer; out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
function ResolveSymbolMapDefinitionByName(const aOptions: TAppOptions; const aName, aOwnerName: string;
  out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
function ResolveSymbolMapDefinitionByPosition(const aOptions: TAppOptions; const aFilePath: string;
  const aLine, aCol: Integer; out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;

implementation

uses
  System.SysUtils,
  Dak.SymbolMap.Indexer;

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

function IndexSymbolMapProject(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  var aApiStatus: TSymbolMapApiStatus; out aError: string): Boolean;
var
  lModels: TArray<TSymbolMapUnitModel>;
  lStoreResults: TArray<TSymbolMapCacheStoreResult>;
begin
  Result := False;
  if not TryBuildSymbolMapUnitModelsFromDelphiSemanticProjectIndex(aContext, True, lModels, aError) then
    Exit(False);
  if not StoreSymbolMapProjectProjection(aContext, aStatus, lModels, lStoreResults, aError) then
    Exit(False);
  if Length(lStoreResults) <> Length(lModels) then
  begin
    aError := 'Symbol Map project projection result count mismatch.';
    Exit(False);
  end;
  aApiStatus.fProjectIndexed := True;
  Result := True;
end;

function PrepareSymbolMapApi(const aOptions: TAppOptions; out aContext: TSymbolMapContext;
  out aStatus: TSymbolMapApiStatus; out aError: string): Boolean;
var
  lRtlSource: TSymbolMapRtlIndexResult;
begin
  Result := False;
  aStatus := Default(TSymbolMapApiStatus);
  aError := '';
  if not TryBuildSymbolMapContext(aOptions, aContext, aError) then
    Exit(False);
  if not EnsureSymbolMapCaches(aContext, aStatus.fCacheStatus, aError) then
    Exit(False);
  if not EnsureSymbolMapCompilerProfile(aContext, aStatus.fCacheStatus, aStatus.fCompilerProfile, aError) then
    Exit(False);
  if not IndexSymbolMapRtlSources(aContext, aStatus.fCacheStatus, '', aStatus.fCompilerProfile, lRtlSource,
    aError) then
    Exit(False);
  if lRtlSource.fStatus = 'missing-source-root' then
    AddDiagnostic(aStatus.fDiagnostics, lRtlSource.fDiagnosticsJson);
  if not IndexSymbolMapProject(aContext, aStatus.fCacheStatus, aStatus, aError) then
    Exit(False);
  if aStatus.fCompilerProfile.fProfileKey = '' then
    AddDiagnostic(aStatus.fDiagnostics, 'missing-compiler-profile');
  Result := True;
end;

function PrepareSymbolMapApiSession(const aOptions: TAppOptions; out aSession: TSymbolMapApiSession;
  out aError: string): Boolean;
begin
  aSession := Default(TSymbolMapApiSession);
  Result := PrepareSymbolMapApi(aOptions, aSession.fApiContext, aSession.fApiStatus, aError);
  aSession.fIsPrepared := Result;
end;

function TSymbolMapApiSession.DescribeDefinitionByName(const aName, aOwnerName: string;
  out aDefinition: TSymbolMapDefinition; out aError: string): Boolean;
begin
  aDefinition := Default(TSymbolMapDefinition);
  if not fIsPrepared then
  begin
    aError := 'Symbol Map API session is not prepared.';
    Exit(False);
  end;
  Result := DescribeSymbolMapDefinition(fApiContext, fApiStatus.fCacheStatus, fApiStatus.fCompilerProfile,
    aName, aOwnerName, aDefinition, aError);
end;

function TSymbolMapApiSession.LookupDefinitionByName(const aName, aOwnerName: string;
  out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
begin
  Result := False;
  aResult := Default(TSymbolMapApiLookupResult);
  aResult.fStatus := fApiStatus;
  if not fIsPrepared then
  begin
    aError := 'Symbol Map API session is not prepared.';
    Exit(False);
  end;
  Result := FindSymbolMapDefinitionByName(fApiContext, fApiStatus.fCacheStatus, fApiStatus.fCompilerProfile,
    aName, aOwnerName, aResult.fDefinition, aError);
end;

function TSymbolMapApiSession.LookupDefinitionByPosition(const aFilePath: string; const aLine, aCol: Integer;
  out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
begin
  Result := False;
  aResult := Default(TSymbolMapApiLookupResult);
  aResult.fStatus := fApiStatus;
  if not fIsPrepared then
  begin
    aError := 'Symbol Map API session is not prepared.';
    Exit(False);
  end;
  Result := FindSymbolMapDefinitionByPosition(fApiContext, fApiStatus.fCacheStatus, fApiStatus.fCompilerProfile,
    aFilePath, aLine, aCol, aResult.fDefinition, aError);
end;

function LookupSymbolMapDefinitionByName(const aSession: TSymbolMapApiSession; const aName, aOwnerName: string;
  out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
begin
  Result := aSession.LookupDefinitionByName(aName, aOwnerName, aResult, aError);
end;

function LookupSymbolMapDefinitionByPosition(const aSession: TSymbolMapApiSession; const aFilePath: string;
  const aLine, aCol: Integer; out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
begin
  Result := aSession.LookupDefinitionByPosition(aFilePath, aLine, aCol, aResult, aError);
end;

function ResolveSymbolMapDefinitionByName(const aOptions: TAppOptions; const aName, aOwnerName: string;
  out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
var
  lSession: TSymbolMapApiSession;
begin
  Result := False;
  aResult := Default(TSymbolMapApiLookupResult);
  if not PrepareSymbolMapApiSession(aOptions, lSession, aError) then
  begin
    aResult.fStatus := lSession.Status;
    Exit(False);
  end;
  Result := LookupSymbolMapDefinitionByName(lSession, aName, aOwnerName, aResult, aError);
end;

function ResolveSymbolMapDefinitionByPosition(const aOptions: TAppOptions; const aFilePath: string;
  const aLine, aCol: Integer; out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
var
  lSession: TSymbolMapApiSession;
begin
  Result := False;
  aResult := Default(TSymbolMapApiLookupResult);
  if not PrepareSymbolMapApiSession(aOptions, lSession, aError) then
  begin
    aResult.fStatus := lSession.Status;
    Exit(False);
  end;
  Result := LookupSymbolMapDefinitionByPosition(lSession, aFilePath, aLine, aCol, aResult, aError);
end;

end.
