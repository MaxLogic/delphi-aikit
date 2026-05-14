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
  System.Generics.Collections, System.IOUtils, System.RegularExpressions, System.SysUtils,
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

procedure AddPath(var aPaths: TArray<string>; const aPath: string);
var
  lFullPath: string;
  lIndex: Integer;
  lPath: string;
begin
  lPath := Trim(aPath);
  if lPath = '' then
    Exit;
  lFullPath := TPath.GetFullPath(lPath);
  for lPath in aPaths do
  begin
    if SameText(lPath, lFullPath) then
      Exit;
  end;
  lIndex := Length(aPaths);
  SetLength(aPaths, lIndex + 1);
  aPaths[lIndex] := lFullPath;
end;

function CollectProjectIndexUnitPaths(const aContext: TSymbolMapContext): TArray<string>;
var
  lDprojText: string;
  lMatch: TMatch;
  lMatches: TMatchCollection;
  lPath: string;
begin
  SetLength(Result, 0);
  if TFile.Exists(aContext.fProject.fProjectPath) then
  begin
    lDprojText := TFile.ReadAllText(aContext.fProject.fProjectPath, TEncoding.UTF8);
    lMatches := TRegEx.Matches(lDprojText, '<DCCReference\s+Include="([^"]+\.pas)"',
      [roIgnoreCase]);
    for lMatch in lMatches do
    begin
      lPath := lMatch.Groups[1].Value;
      if not TPath.IsPathRooted(lPath) then
        lPath := TPath.Combine(aContext.fProject.fProjectDir, lPath);
      AddPath(Result, lPath);
    end;
  end;
  if TFile.Exists(aContext.fProject.fMainSourcePath) then
    AddPath(Result, aContext.fProject.fMainSourcePath);
end;

function IndexSymbolMapProject(const aContext: TSymbolMapContext; const aStatus: TSymbolMapCacheStatus;
  var aApiStatus: TSymbolMapApiStatus; out aError: string): Boolean;
var
  lIndexedUnit: TSymbolMapIndexedUnit;
  lUnitPath: string;
  lUnitPaths: TArray<string>;
begin
  Result := False;
  lUnitPaths := CollectProjectIndexUnitPaths(aContext);
  for lUnitPath in lUnitPaths do
  begin
    lIndexedUnit := Default(TSymbolMapIndexedUnit);
    if not TryExtractSymbolMapUnitModel(lUnitPath, lIndexedUnit.fModel, aError) then
      Exit(False);
    if not StoreSymbolMapUnitModel(aContext, aStatus, lIndexedUnit.fModel, lIndexedUnit.fStoreResult, aError) then
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
