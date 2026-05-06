unit Dak.RemoveWith.SymbolMap;

interface

uses
  System.Generics.Collections,
  Dak.SymbolMap.Api, Dak.Types;

type
  TRemoveWithSymbolMapLookup = record
    fFound: Boolean;
    fName: string;
    fKind: string;
    fOwnerName: string;
    fSourceKind: string;
    fConfidence: string;
    fTypeName: string;
    fUnitName: string;
    fFilePath: string;
    fLine: Integer;
    fColumn: Integer;
  end;

  TRemoveWithSymbolMapBridge = record
    fSession: TSymbolMapApiSession;
    fStatus: TSymbolMapApiStatus;
    fLookupCache: TDictionary<string, TRemoveWithSymbolMapLookup>;
    fPrepared: Boolean;
    fPrepareCount: Integer;
    fError: string;
  end;

function PrepareRemoveWithSymbolMapBridge(const aOptions: TAppOptions; out aBridge: TRemoveWithSymbolMapBridge;
  out aError: string): Boolean;
procedure FinalizeRemoveWithSymbolMapBridge(var aBridge: TRemoveWithSymbolMapBridge);
function FindRemoveWithSymbolMapDefinition(const aBridge: TRemoveWithSymbolMapBridge; const aName,
  aOwnerName: string; out aLookup: TRemoveWithSymbolMapLookup; out aError: string): Boolean;

implementation

uses
  System.SysUtils,
  Dak.SymbolMap.Query;

function LookupCacheKey(const aName, aOwnerName: string): string;
const
  cSeparator = #31;
begin
  Result := LowerCase(aOwnerName) + cSeparator + LowerCase(aName);
end;

function LookupFromDefinition(const aDefinition: TSymbolMapDefinition): TRemoveWithSymbolMapLookup;
begin
  Result := Default(TRemoveWithSymbolMapLookup);
  Result.fFound := aDefinition.fFound;
  Result.fName := aDefinition.fName;
  Result.fKind := aDefinition.fKind;
  Result.fOwnerName := aDefinition.fOwnerName;
  Result.fSourceKind := aDefinition.fSourceKind;
  Result.fConfidence := aDefinition.fConfidence;
  Result.fTypeName := aDefinition.fTypeName;
  Result.fUnitName := aDefinition.fUnitName;
  Result.fFilePath := aDefinition.fFilePath;
  Result.fLine := aDefinition.fLine;
  Result.fColumn := aDefinition.fCol;
end;

function PrepareRemoveWithSymbolMapBridge(const aOptions: TAppOptions; out aBridge: TRemoveWithSymbolMapBridge;
  out aError: string): Boolean;
begin
  aBridge := Default(TRemoveWithSymbolMapBridge);
  Result := PrepareSymbolMapApiSession(aOptions, aBridge.fSession, aError);
  aBridge.fPrepared := Result;
  if Result then
  begin
    aBridge.fStatus := aBridge.fSession.fStatus;
    aBridge.fLookupCache := TDictionary<string, TRemoveWithSymbolMapLookup>.Create;
    aBridge.fPrepareCount := 1;
  end else begin
    aBridge.fError := aError;
  end;
end;

procedure FinalizeRemoveWithSymbolMapBridge(var aBridge: TRemoveWithSymbolMapBridge);
begin
  aBridge.fLookupCache.Free;
  aBridge.fLookupCache := nil;
  aBridge.fPrepared := False;
end;

function FindRemoveWithSymbolMapDefinition(const aBridge: TRemoveWithSymbolMapBridge; const aName,
  aOwnerName: string; out aLookup: TRemoveWithSymbolMapLookup; out aError: string): Boolean;
var
  lKey: string;
  lResult: TSymbolMapApiLookupResult;
begin
  aLookup := Default(TRemoveWithSymbolMapLookup);
  if not aBridge.fPrepared then
  begin
    aError := aBridge.fError;
    if aError = '' then
      aError := 'Remove-with Symbol Map bridge is not prepared.';
    Exit(False);
  end;

  lKey := LookupCacheKey(aName, aOwnerName);
  if Assigned(aBridge.fLookupCache) and aBridge.fLookupCache.TryGetValue(lKey, aLookup) then
    Exit(True);

  Result := LookupSymbolMapDefinitionByName(aBridge.fSession, aName, aOwnerName, lResult, aError);
  if Result then
  begin
    aLookup := LookupFromDefinition(lResult.fDefinition);
    if Assigned(aBridge.fLookupCache) then
      aBridge.fLookupCache.AddOrSetValue(lKey, aLookup);
  end;
end;

end.
