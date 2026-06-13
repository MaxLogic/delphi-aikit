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
    fContext: TSymbolMapContext;
    fStatus: TSymbolMapApiStatus;
    fPrepared: Boolean;
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
  System.Generics.Collections, System.SysUtils,
  Dak.SymbolMap.Indexer;

type
  TSymbolMapIndexedUnit = record
    fModel: TSymbolMapUnitModel;
    fStoreResult: TSymbolMapCacheStoreResult;
  end;

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
  i: Integer;
  lIndexedUnit: TSymbolMapIndexedUnit;
  lModels: TArray<TSymbolMapUnitModel>;
  lStoreResults: TArray<TSymbolMapCacheStoreResult>;
  lUnitPath: string;
  lUnitPaths: TArray<string>;
begin
  Result := False;
  lUnitPaths := SymbolMapProjectSourceFilePaths(aContext, True);
  SetLength(lModels, Length(lUnitPaths));
  i := 0;
  for lUnitPath in lUnitPaths do
  begin
    lIndexedUnit := Default(TSymbolMapIndexedUnit);
    if not TryExtractSymbolMapUnitModel(lUnitPath, lIndexedUnit.fModel, aError) then
      Exit(False);
    lModels[i] := lIndexedUnit.fModel;
    Inc(i);
  end;
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
  Result := PrepareSymbolMapApi(aOptions, aSession.fContext, aSession.fStatus, aError);
  aSession.fPrepared := Result;
end;

function LookupSymbolMapDefinitionByName(const aSession: TSymbolMapApiSession; const aName, aOwnerName: string;
  out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
begin
  Result := False;
  aResult := Default(TSymbolMapApiLookupResult);
  aResult.fStatus := aSession.fStatus;
  if not aSession.fPrepared then
  begin
    aError := 'Symbol Map API session is not prepared.';
    Exit(False);
  end;
  Result := FindSymbolMapDefinitionByName(aSession.fContext, aSession.fStatus.fCacheStatus,
    aSession.fStatus.fCompilerProfile, aName, aOwnerName, aResult.fDefinition, aError);
end;

function LookupSymbolMapDefinitionByPosition(const aSession: TSymbolMapApiSession; const aFilePath: string;
  const aLine, aCol: Integer; out aResult: TSymbolMapApiLookupResult; out aError: string): Boolean;
begin
  Result := False;
  aResult := Default(TSymbolMapApiLookupResult);
  aResult.fStatus := aSession.fStatus;
  if not aSession.fPrepared then
  begin
    aError := 'Symbol Map API session is not prepared.';
    Exit(False);
  end;
  Result := FindSymbolMapDefinitionByPosition(aSession.fContext, aSession.fStatus.fCacheStatus,
    aSession.fStatus.fCompilerProfile, aFilePath, aLine, aCol, aResult.fDefinition, aError);
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
    aResult.fStatus := lSession.fStatus;
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
    aResult.fStatus := lSession.fStatus;
    Exit(False);
  end;
  Result := LookupSymbolMapDefinitionByPosition(lSession, aFilePath, aLine, aCol, aResult, aError);
end;

end.
