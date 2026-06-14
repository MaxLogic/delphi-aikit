unit Dak.RemoveWith;

interface

uses
  Dak.Types;

function RunRemoveWithCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.Diagnostics, System.Generics.Collections, System.IOUtils, System.SysUtils,
  Dak.ExitCodes, Dak.RemoveWith.Discovery, Dak.RemoveWith.Model, Dak.RemoveWith.Output, Dak.RemoveWith.Planner,
  Dak.RemoveWith.Resolver, Dak.RemoveWith.SymbolMap, Dak.RemoveWith.Symbols, Dak.RemoveWith.Transaction, Dak.Utils;

procedure LogRemoveWithProgress(const aOptions: TAppOptions; const aMessage: string);
begin
  if not aOptions.fVerbose then
    Exit;
  WriteLn(ErrOutput, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now) + ' [remove-with] ' + aMessage);
  Flush(ErrOutput);
end;

procedure LogRemoveWithDone(const aOptions: TAppOptions; const aStepName, aDetails: string;
  const aStopwatch: TStopwatch);
var
  lMessage: string;
begin
  if not aOptions.fVerbose then
    Exit;

  lMessage := Format('%s done elapsedMs=%d', [aStepName, aStopwatch.ElapsedMilliseconds]);
  if aDetails <> '' then
    lMessage := lMessage + ' ' + aDetails;
  LogRemoveWithProgress(aOptions, lMessage);
end;

function CountRemoveWithPlannedStatements(const aPlanResult: TRemoveWithPlanResult; const aStatus: string): Integer;
var
  lStatement: TRemoveWithPlannedStatement;
begin
  Result := 0;
  for lStatement in aPlanResult.fStatements do
  begin
    if SameText(lStatement.fStatus, aStatus) then
      Inc(Result);
  end;
end;

function BodyAnalysisSourceFileNamesFromScanResult(const aScanResult: TRemoveWithScanResult):
  TArray<string>;
var
  lFile: TRemoveWithFileInfo;
  lFiles: TList<string>;
  lSeen: TDictionary<string, Byte>;
  lSourceFileName: string;
begin
  lFiles := TList<string>.Create;
  try
    lSeen := TDictionary<string, Byte>.Create;
    try
      for lFile in aScanResult.fFiles do
      begin
        if (not lFile.fScanned) or (Trim(lFile.fPath) = '') then
          Continue;
        lSourceFileName := TPath.GetFullPath(lFile.fPath);
        if lSeen.ContainsKey(lSourceFileName) then
          Continue;
        lSeen.Add(lSourceFileName, 0);
        lFiles.Add(lSourceFileName);
      end;
      Result := lFiles.ToArray;
    finally
      lSeen.Free;
    end;
  finally
    lFiles.Free;
  end;
end;

function NewRemoveWithRunId: string;
var
  lGuid: TGUID;
begin
  if CreateGUID(lGuid) <> 0 then
    Exit(FormatDateTime('yyyymmddhhnnsszzz', Now));

  Result := GUIDToString(lGuid);
  Result := StringReplace(Result, '{', '', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
  Result := LowerCase(Result);
end;

procedure WriteRemoveWithOutput(const aOptions: TAppOptions; const aOutputText: string);
var
  lOutputDir: string;
begin
  WriteLn(aOutputText);
  if (not aOptions.fHasRemoveWithOutputPath) or (Trim(aOptions.fRemoveWithOutputPath) = '') or
    (aOptions.fRemoveWithOutputPath = '-') then
    Exit;

  lOutputDir := TPath.GetDirectoryName(aOptions.fRemoveWithOutputPath);
  if lOutputDir <> '' then
    TDirectory.CreateDirectory(lOutputDir);
  TFile.WriteAllText(aOptions.fRemoveWithOutputPath, aOutputText, TEncoding.UTF8);
end;

function ResolveRemoveWithTargetPaths(const aOptions: TAppOptions; out aUnitPath, aDirPath, aError: string): Boolean;
begin
  aUnitPath := '';
  aDirPath := '';
  aError := '';

  if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtUnit then
  begin
    if not TryResolveAbsolutePath(aOptions.fRemoveWithUnitPath, aUnitPath, aError) then
      Exit(False);
    if not FileExists(aUnitPath) then
    begin
      aError := Format('File not found: %s', [aUnitPath]);
      Exit(False);
    end;
  end else if aOptions.fRemoveWithTargetKind = TRemoveWithTargetKind.rwtDir then
  begin
    if not TryResolveAbsolutePath(aOptions.fRemoveWithDirPath, aDirPath, aError) then
      Exit(False);
    if not TDirectory.Exists(aDirPath) then
    begin
      aError := Format('Directory not found: %s', [aDirPath]);
      Exit(False);
    end;
  end;

  Result := True;
end;

function RunRemoveWithCommand(const aOptions: TAppOptions): Integer;
var
  lDirPath: string;
  lApplySucceeded: Boolean;
  lError: string;
  lFactOptions: TAppOptions;
  lOutputText: string;
  lMetrics: TRemoveWithPlannerPhaseMetrics;
  lPlanResult: TRemoveWithPlanResult;
  lPlannerMs: Int64;
  lPlannerStopwatch: TStopwatch;
  lProjectModel: TRemoveWithProjectModel;
  lProjectName: string;
  lProjectPath: string;
  lResolverError: string;
  lResolverReportMetrics: TRemoveWithResolverReportMetrics;
  lBodyAnalysisSourceFileNames: TArray<string>;
  lApplyContext: TRemoveWithPlanApplyContext;
  lResolverResult: TRemoveWithResolverResult;
  lRunId: string;
  lScanResult: TRemoveWithScanResult;
  lStopwatch: TStopwatch;
  lSymbolMapBridge: TRemoveWithSymbolMapBridge;
  lSymbolInventory: TRemoveWithFactSet;
  lSymbolInventoryPhaseMetrics: TRemoveWithFactSetPhaseMetrics;
  lTransactionResult: TRemoveWithTransactionResult;
  lTotalStopwatch: TStopwatch;
  lUnitPath: string;
  lWorkspaceRoot: string;
begin
  lApplySucceeded := True;
  lMetrics := Default(TRemoveWithPlannerPhaseMetrics);
  lPlannerMs := 0;
  lPlannerStopwatch := Default(TStopwatch);
  lProjectModel := nil;
  lPlanResult := Default(TRemoveWithPlanResult);
  lResolverResult := Default(TRemoveWithResolverResult);
  lResolverReportMetrics := Default(TRemoveWithResolverReportMetrics);
  lSymbolMapBridge := Default(TRemoveWithSymbolMapBridge);
  lTransactionResult := Default(TRemoveWithTransactionResult);

  if not TryResolveDprojPath(aOptions.fDprojPath, lProjectPath, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitInvalidProjectInput);
  end;

  if not ResolveRemoveWithTargetPaths(aOptions, lUnitPath, lDirPath, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitInvalidProjectInput);
  end;

  lProjectName := TPath.GetFileNameWithoutExtension(lProjectPath);
  lTotalStopwatch := TStopwatch.StartNew;
  lRunId := NewRemoveWithRunId;
  lWorkspaceRoot := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetDirectoryName(lProjectPath), '.dak'), lProjectName),
    TPath.Combine('remove-with', lRunId));
  TDirectory.CreateDirectory(lWorkspaceRoot);
  LogRemoveWithProgress(aOptions, Format('start mode=%s project=%s workspace=%s',
    [RemoveWithModeToText(aOptions.fRemoveWithMode), lProjectPath, lWorkspaceRoot]));

  LogRemoveWithProgress(aOptions, 'project-model start');
  lStopwatch := TStopwatch.StartNew;
  if not BuildRemoveWithProjectModel(aOptions, lProjectPath, lProjectModel, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Exit(cExitToolFailure);
  end;
  try
    lStopwatch.Stop;
    lMetrics.fProjectModelMs := lStopwatch.ElapsedMilliseconds;
    lMetrics.fContextMode := ProjectAnalysisContextQualityToText(lProjectModel.Context.Quality);
    lMetrics.fContextNote := lProjectModel.Context.ContextNote;
    lMetrics.fProjectUnitCount := lProjectModel.IndexCount;
    lMetrics.fParsedUnitCount := lProjectModel.ParsedUnitCount;
    lMetrics.fProjectProblemCount := lProjectModel.ProblemCount;
    LogRemoveWithDone(aOptions, 'project-model',
      Format('indexCount=%d parsedUnits=%d problems=%d main=%s',
      [lProjectModel.IndexCount, lProjectModel.ParsedUnitCount, lProjectModel.ProblemCount,
      lProjectModel.Context.MainSourcePath]), lStopwatch);

    LogRemoveWithProgress(aOptions, 'discovery start');
    lStopwatch := TStopwatch.StartNew;
    if not DiscoverRemoveWithStatements(aOptions, lProjectModel, lScanResult, lError) then
    begin
      WriteLn(ErrOutput, lError);
      Exit(cExitToolFailure);
    end;
    lStopwatch.Stop;
    lMetrics.fDiscoveryMs := lStopwatch.ElapsedMilliseconds;
    lMetrics.fWithStatementCount := Length(lScanResult.fWithStatements);
    LogRemoveWithDone(aOptions, 'discovery',
      Format('files=%d withStatements=%d warnings=%d', [Length(lScanResult.fFiles),
      Length(lScanResult.fWithStatements), Length(lScanResult.fWarnings)]), lStopwatch);
    if aOptions.fRemoveWithMode <> TRemoveWithMode.rwmScan then
    begin
      LogRemoveWithProgress(aOptions, 'symbol-inventory start');
      lStopwatch := TStopwatch.StartNew;
      lBodyAnalysisSourceFileNames := BodyAnalysisSourceFileNamesFromScanResult(
        lScanResult);
      lFactOptions := aOptions;
      lFactOptions.fRemoveWithSkipCompatibilityFacts :=
        aOptions.fRemoveWithMode <> TRemoveWithMode.rwmScan;
      if not BuildRemoveWithFactSet(lFactOptions, lProjectModel,
        lBodyAnalysisSourceFileNames, lSymbolInventory, lError,
        lSymbolInventoryPhaseMetrics) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(cExitToolFailure);
      end;
      lStopwatch.Stop;
      lMetrics.fSymbolInventoryMs := lStopwatch.ElapsedMilliseconds;
      lMetrics.fSymbolInventoryPhaseMetrics := lSymbolInventoryPhaseMetrics;
      lMetrics.fSemanticProjectFactsMs := lSymbolInventoryPhaseMetrics.fSemanticProjectFactsMs;
      lMetrics.fSemanticCompatibilityFactsMs :=
        lSymbolInventoryPhaseMetrics.fSemanticCompatibilityFactsMs;
      lMetrics.fSemanticBindingMs := lSymbolInventoryPhaseMetrics.fSemanticBindingMs;
      lMetrics.fSemanticPlanDtoMs := lSymbolInventoryPhaseMetrics.fSemanticPlanDtoMs;
      lMetrics.fContextFingerprint := lSymbolInventory.fContextFingerprint;
      lMetrics.fSymbolCount := Length(lSymbolInventory.fSymbols);
      LogRemoveWithDone(aOptions, 'symbol-inventory',
        Format('symbols=%d', [Length(lSymbolInventory.fSymbols)]), lStopwatch);

      LogRemoveWithProgress(aOptions, 'symbol-map-bridge skipped; semantic project facts are authoritative');
      lMetrics.fSymbolMapBridgeMs := 0;

      if aOptions.fRemoveWithMode = TRemoveWithMode.rwmApply then
      begin
        lResolverReportMetrics := Default(TRemoveWithResolverReportMetrics);
        lResolverResult := Default(TRemoveWithResolverResult);
        lMetrics.fResolverMs := 0;
        lMetrics.fClassificationCount := 0;
        lMetrics.fResolverReportMetrics := lResolverReportMetrics;
        LogRemoveWithProgress(aOptions,
          'resolver skipped; semantic final DTO is authoritative for apply');

        LogRemoveWithProgress(aOptions, 'planner start');
        lStopwatch := TStopwatch.StartNew;
        if not PlanRemoveWithRewrites(lSymbolInventory, lScanResult, lResolverResult,
          lSymbolInventory.fDelphiSemanticRemoveWithPlan, lPlanResult, lError) then
        begin
          WriteLn(ErrOutput, lError);
          Exit(cExitToolFailure);
        end;
        lStopwatch.Stop;
        lPlannerMs := lStopwatch.ElapsedMilliseconds;
        lPlannerStopwatch := lStopwatch;
      end else
      begin
        LogRemoveWithProgress(aOptions, 'planner start');
        lStopwatch := TStopwatch.StartNew;
        if not PlanRemoveWithRewrites(lSymbolInventory, lScanResult,
          lResolverResult, lSymbolInventory.fDelphiSemanticRemoveWithPlan, lPlanResult,
          lError) then
        begin
          WriteLn(ErrOutput, lError);
          Exit(cExitToolFailure);
        end;
        lStopwatch.Stop;
        lPlannerMs := lStopwatch.ElapsedMilliseconds;
        lPlannerStopwatch := lStopwatch;

        if lFactOptions.fRemoveWithSkipCompatibilityFacts then
        begin
          lResolverReportMetrics := Default(TRemoveWithResolverReportMetrics);
          lResolverResult := Default(TRemoveWithResolverResult);
          lMetrics.fResolverMs := 0;
          lMetrics.fClassificationCount := 0;
          lMetrics.fResolverReportMetrics := lResolverReportMetrics;
          LogRemoveWithProgress(aOptions, 'semantic resolver projection start');
          lStopwatch := TStopwatch.StartNew;
          lResolverError := '';
          if ResolveRemoveWithIdentifiersFromSemanticFacts(lSymbolInventory, lScanResult,
            lResolverResult, lResolverError, lResolverReportMetrics, True) then
          begin
            lStopwatch.Stop;
            lMetrics.fResolverReportMetrics := lResolverReportMetrics;
            LogRemoveWithDone(aOptions, 'semantic resolver projection',
              Format('classifications=%d', [Length(lResolverResult.fClassifications)]),
              lStopwatch);
          end else
          begin
            lStopwatch.Stop;
            lResolverResult := Default(TRemoveWithResolverResult);
            LogRemoveWithProgress(aOptions, 'semantic resolver projection unavailable: ' +
              lResolverError);
          end;
        end else
        begin
          LogRemoveWithProgress(aOptions, 'resolver start');
          lStopwatch := TStopwatch.StartNew;
          lResolverError := '';
          lResolverReportMetrics := Default(TRemoveWithResolverReportMetrics);
          if ResolveRemoveWithIdentifiersFromSemanticFacts(lSymbolInventory, lScanResult,
            lResolverResult, lResolverError, lResolverReportMetrics, True) then
          begin
            lStopwatch.Stop;
            lMetrics.fResolverMs := lStopwatch.ElapsedMilliseconds;
            lMetrics.fDakLookupIndexMs := RemoveWithFactSetLookupIndexBuildMilliseconds(
              lSymbolInventory);
            lMetrics.fDakLookupCacheHits := RemoveWithFactSetLookupIndexHitCount(
              lSymbolInventory);
            lMetrics.fDakLookupCacheMisses := RemoveWithFactSetLookupIndexMissCount(
              lSymbolInventory);
            lMetrics.fDakResolverClassifyMs := lMetrics.fResolverMs -
              lMetrics.fDakLookupIndexMs;
            if lMetrics.fDakResolverClassifyMs < 0 then
              lMetrics.fDakResolverClassifyMs := 0;
            lMetrics.fClassificationCount := Length(lResolverResult.fClassifications);
            lMetrics.fResolverReportMetrics := lResolverReportMetrics;
            LogRemoveWithDone(aOptions, 'resolver',
              Format('classifications=%d', [Length(lResolverResult.fClassifications)]),
              lStopwatch);
          end else
          begin
            lStopwatch.Stop;
            lResolverResult := Default(TRemoveWithResolverResult);
            lMetrics.fResolverMs := 0;
            lMetrics.fClassificationCount := 0;
            LogRemoveWithProgress(aOptions, 'resolver report unavailable: ' +
              lResolverError);
          end;
        end;
      end;
      lMetrics.fPlannerMs := lPlannerMs;
      lMetrics.fDakPlannerRewriteMs := lMetrics.fPlannerMs;
      lMetrics.fPlannedEditCount := CountRemoveWithPlannedStatements(lPlanResult, 'planned');
      lMetrics.fSkippedStatementCount := CountRemoveWithPlannedStatements(lPlanResult, 'skipped');
      if lPlannerMs > High(Integer) then
        lPlanResult.fElapsedPlanningMs := High(Integer)
      else
        lPlanResult.fElapsedPlanningMs := Integer(lPlannerMs);
      LogRemoveWithDone(aOptions, 'planner',
        Format('statements=%d planned=%d skipped=%d', [Length(lPlanResult.fStatements),
        CountRemoveWithPlannedStatements(lPlanResult, 'planned'), CountRemoveWithPlannedStatements(lPlanResult,
        'skipped')]), lPlannerStopwatch);

      if aOptions.fRemoveWithMode = TRemoveWithMode.rwmApply then
      begin
        LogRemoveWithProgress(aOptions, 'apply start');
        lStopwatch := TStopwatch.StartNew;
        if BuildRemoveWithPlanApplyContext(lPlanResult, lApplyContext, lError) then
          lApplySucceeded := ApplyRemoveWithPlanTransactionally(aOptions, lProjectPath, lWorkspaceRoot, lPlanResult,
            lApplyContext, lTransactionResult, lError)
        else
          lApplySucceeded := False;
        lStopwatch.Stop;
        LogRemoveWithDone(aOptions, 'apply', Format('status=%s files=%d',
          [RemoveWithTransactionStatusToText(lTransactionResult.fStatus), Length(lTransactionResult.fFiles)]),
          lStopwatch);
        if (not lApplySucceeded) and (lTransactionResult.fError = '') then
          lTransactionResult.fError := lError;
      end;
    end;

    lTotalStopwatch.Stop;
    lMetrics.fTotalMs := lTotalStopwatch.ElapsedMilliseconds;
    if aOptions.fRemoveWithFormat = TRemoveWithFormat.rwfText then
      lOutputText := BuildRemoveWithTextReport(aOptions, lProjectPath, lWorkspaceRoot, lRunId, lUnitPath, lDirPath,
        lScanResult, lPlanResult, lTransactionResult, lMetrics)
    else
      lOutputText := BuildRemoveWithJsonReport(aOptions, lProjectPath, lWorkspaceRoot, lRunId, lUnitPath, lDirPath,
        lScanResult, lResolverResult, lPlanResult, lTransactionResult, lMetrics);
    WriteRemoveWithOutput(aOptions, lOutputText);
    LogRemoveWithProgress(aOptions, 'report written');
    if not lApplySucceeded then
      Exit(cExitToolFailure);
    Result := cExitSuccess;
  finally
    FinalizeRemoveWithSymbolMapBridge(lSymbolMapBridge);
    lProjectModel.Free;
  end;
end;

end.
