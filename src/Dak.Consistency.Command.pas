unit Dak.Consistency.Command;

interface

uses Dak.Types;

function RunConsistencyCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
  DelphiSemantics.Cache, DelphiSemantics.Consistency.GuidInventory, DelphiSemantics.Model,
  DelphiSemantics.ProjectContext, DelphiSemantics.ProjectSession, DelphiSemantics.Query,
  Dak.Consistency.Dfm, Dak.ExitCodes, Dak.RsVars, Dak.Semantics.Session;

procedure AddDiagnostic(const aDiagnostics: TJSONArray; const aReason, aFileName, aMessage: string);
var
  lItem: TJSONObject;
begin
  lItem := TJSONObject.Create;
  aDiagnostics.AddElement(lItem);
  lItem.AddPair('reason', aReason);
  lItem.AddPair('fileName', aFileName);
  lItem.AddPair('message', aMessage);
end;

procedure AppendGuidInventory(const aModels: TArray<TDelphiSemanticUnitModel>;
  const aGuids, aDiagnostics: TJSONArray; var aComplete: Boolean);
const
  cStatuses: array[TDelphiSemanticGuidStatus] of string =
    ('unique', 'valid-pair', 'duplicate', 'missing-guid', 'unknown');
var
  lInventory: TDelphiSemanticGuidInventory;
  lItem: TDelphiSemanticGuidInventoryItem;
  lJson: TJSONObject;
begin
  lInventory := TDelphiSemanticGuidInventoryPlanner.Inspect(aModels);
  if not lInventory.Complete then
  begin
    aComplete := False;
    AddDiagnostic(aDiagnostics, lInventory.Reason, '', 'GUID inventory is incomplete.');
  end;
  for lItem in lInventory.Items do
  begin
    lJson := TJSONObject.Create;
    aGuids.AddElement(lJson);
    lJson.AddPair('unitName', lItem.UnitName);
    lJson.AddPair('fileName', lItem.FileName);
    lJson.AddPair('name', lItem.Name);
    lJson.AddPair('guid', lItem.Guid);
    lJson.AddPair('isDispInterface', TJSONBool.Create(lItem.IsDispInterface));
    lJson.AddPair('status', cStatuses[lItem.Status]);
    if lItem.Status in [gsDuplicate, gsMissingGuid, gsUnknown] then
      AddDiagnostic(aDiagnostics, 'guid.' + cStatuses[lItem.Status], lItem.FileName, lItem.Name);
    if lItem.Status = gsUnknown then
      aComplete := False;
  end;
end;

function CollectModels(const aSession: TDelphiSemanticProjectSession;
  const aRoots, aDiagnostics: TJSONArray; var aComplete: Boolean): TArray<TDelphiSemanticUnitModel>;
var
  i: Integer;
  lCache: TDelphiSemanticCacheMetrics;
  lMilliseconds: Int64;
  lQuery: TDelphiSemanticSymbolQueryContext;
  lModel: TDelphiSemanticUnitModel;
  lFileName: string;
  lFound: Boolean;
begin
  lQuery := aSession.BuildSymbolQueryContext(lCache, lMilliseconds);
  Result := nil;
  if lQuery.UnitModel.FileName <> '' then
  begin
    SetLength(Result, Length(lQuery.IndexedUnitModels) + 1);
    Result[0] := lQuery.UnitModel;
    for i := 0 to High(lQuery.IndexedUnitModels) do
      Result[i + 1] := lQuery.IndexedUnitModels[i];
  end;
  for lFileName in aSession.Project.SourceFileNames do
  begin
    lFound := False;
    for lModel in Result do
      if SameFileName(lFileName, lModel.FileName) then
        lFound := True;
    if not lFound then
    begin
      aComplete := False;
      AddDiagnostic(aDiagnostics, 'scope.source-not-analyzed', lFileName, 'Expected source has no model.');
    end;
  end;
  for lModel in Result do
  begin
    aRoots.Add(lModel.FileName);
    if not lModel.Success or (lModel.ScopeModelStatus <> 'ast') or
      (Length(lModel.Diagnostics) > 0) or (lModel.RejectedDeclarationCount <> 0) then
    begin
      aComplete := False;
      AddDiagnostic(aDiagnostics, 'model.incomplete', lModel.FileName,
        'Source extraction has missing, rejected or diagnostic facts.');
    end;

  end;
end;

function TryBuildConsistencyOptions(const aOptions: TAppOptions;
  out aSemanticOptions: TDelphiSemanticOptions; out aReason: string): Boolean;
var
  i: Integer;
  lEnvironment: TRsVarsEnvironment;
begin
  Result := TryLoadRsVars(aOptions.fDelphiVersion, aOptions.fRsVarsPath, nil, lEnvironment, aReason);
  if not Result then
    Exit;
  aSemanticOptions := BuildSemanticSessionOptions(aOptions.fDprojPath, aOptions.fConfig, aOptions.fPlatform,
    aOptions.fDelphiVersion, aOptions.fRsVarsPath, aOptions.fEnvOptionsPath, '');
  SetLength(aSemanticOptions.EnvironmentVariables, Length(lEnvironment.Variables));
  for i := 0 to High(lEnvironment.Variables) do
  begin
    aSemanticOptions.EnvironmentVariables[i].Name := lEnvironment.Variables[i].Name;
    aSemanticOptions.EnvironmentVariables[i].Value := lEnvironment.Variables[i].Value;
  end;
end;

function InspectProject(const aOptions: TAppOptions; const aReport, aScope: TJSONObject;
  const aGuids, aDiagnostics: TJSONArray): string;
var
  lComplete: Boolean;
  lModels: TArray<TDelphiSemanticUnitModel>;
  lOpen: TDelphiSemanticProjectSessionResult;
  lOptions: TDelphiSemanticOptions;
  lReason: string;
  lRoots: TJSONArray;
begin
  Result := 'blocked';
  if not TryBuildConsistencyOptions(aOptions, lOptions, lReason) then
  begin
    AddDiagnostic(aDiagnostics, 'context.environment-unavailable', '', lReason);
    Exit;
  end;
  lOpen := TDelphiSemanticProjectSession.Open(lOptions);
  try
    if not lOpen.Success or not Assigned(lOpen.Session) then
    begin
      AddDiagnostic(aDiagnostics, 'context.open-failed', aOptions.fDprojPath,
        SemanticSessionDiagnosticsText(lOpen.Diagnostics));
      Exit;
    end;
    aReport.AddPair('contextFingerprint', lOpen.Session.Project.ContextFingerprint);
    lComplete := Length(lOpen.Session.Diagnostics) = 0;
    if not lComplete then
      AddDiagnostic(aDiagnostics, 'context.diagnostic', aOptions.fDprojPath,
        SemanticSessionDiagnosticsText(lOpen.Session.Diagnostics));
    lRoots := TJSONArray.Create;
    aScope.AddPair('analyzedRoots', lRoots);
    lModels := CollectModels(lOpen.Session, lRoots, aDiagnostics, lComplete);
    AppendGuidInventory(lModels, aGuids, aDiagnostics, lComplete);
    AppendDfmConsistency(lOpen.Session.Project, lModels, aReport.GetValue<TJSONArray>('events'),
      aDiagnostics, lComplete);
    aScope.AddPair('complete', TJSONBool.Create(lComplete));
    if lComplete then
      Result := 'ok'
    else
      Result := 'incomplete';
  finally
    lOpen.Session.Free;
  end;
end;

function RunConsistencyCommand(const aOptions: TAppOptions): Integer;
var
  lDiagnostics, lGuids: TJSONArray;
  lReport, lScope, lSummary: TJSONObject;
  lStatus: string;
begin
  Result := cExitRejectedResult;
  lReport := TJSONObject.Create;
  try
    lReport.AddPair('schemaVersion', TJSONNumber.Create(1));
    lReport.AddPair('operation', 'consistency.inspect');
    lReport.AddPair('project', ExpandFileName(aOptions.fDprojPath));
    lReport.AddPair('config', aOptions.fConfig);
    lReport.AddPair('platform', aOptions.fPlatform);
    lReport.AddPair('delphiVersion', aOptions.fDelphiVersion);
    lScope := TJSONObject.Create;
    lReport.AddPair('scope', lScope);
    lGuids := TJSONArray.Create;
    lReport.AddPair('guids', lGuids);
    lReport.AddPair('events', TJSONArray.Create);
    lDiagnostics := TJSONArray.Create;
    lReport.AddPair('diagnostics', lDiagnostics);
    try
      lStatus := InspectProject(aOptions, lReport, lScope, lGuids, lDiagnostics);
    except
      on E: Exception do
      begin
        lStatus := 'blocked';
        AddDiagnostic(lDiagnostics, 'consistency.inspection-failed', aOptions.fDprojPath, E.Message);
      end;
    end;
    if lScope.GetValue('complete') = nil then
      lScope.AddPair('complete', TJSONBool.Create(False));
    if lReport.GetValue('contextFingerprint') = nil then
      lReport.AddPair('contextFingerprint', '');
    lReport.AddPair('status', lStatus);
    lSummary := TJSONObject.Create;
    lReport.AddPair('summary', lSummary);
    lSummary.AddPair('guidCount', TJSONNumber.Create(lGuids.Count));
    lSummary.AddPair('eventCount', TJSONNumber.Create(lReport.GetValue<TJSONArray>('events').Count));
    lSummary.AddPair('diagnosticCount', TJSONNumber.Create(lDiagnostics.Count));
    lSummary.AddPair('omittedResultCount', TJSONNumber.Create(0));
    lReport.AddPair('artifacts', TJSONArray.Create);
    WriteLn(lReport.ToJSON);
    if lStatus = 'ok' then
      Result := cExitSuccess;
  finally
    lReport.Free;
  end;
end;

end.
