unit Dak.RemoveWith;

interface

uses
  Dak.Types;

function RunRemoveWithCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.Diagnostics, System.IOUtils, System.SysUtils,
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
  lOutputText: string;
  lPlanResult: TRemoveWithPlanResult;
  lProjectModel: TRemoveWithProjectModel;
  lProjectName: string;
  lProjectPath: string;
  lResolverResult: TRemoveWithResolverResult;
  lRunId: string;
  lScanResult: TRemoveWithScanResult;
  lStopwatch: TStopwatch;
  lSymbolMapBridge: TRemoveWithSymbolMapBridge;
  lSymbolInventory: TRemoveWithSymbolInventory;
  lTransactionResult: TRemoveWithTransactionResult;
  lUnitPath: string;
  lWorkspaceRoot: string;
begin
  lApplySucceeded := True;
  lProjectModel := nil;
  lPlanResult := Default(TRemoveWithPlanResult);
  lResolverResult := Default(TRemoveWithResolverResult);
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
    LogRemoveWithDone(aOptions, 'project-model',
      Format('indexCount=%d parsedUnits=%d problems=%d main=%s',
      [lProjectModel.IndexCount, lProjectModel.ParsedUnitCount, lProjectModel.ProblemCount,
      lProjectModel.Context.fMainSourcePath]), lStopwatch);

    LogRemoveWithProgress(aOptions, 'discovery start');
    lStopwatch := TStopwatch.StartNew;
    if not DiscoverRemoveWithStatements(aOptions, lProjectModel, lScanResult, lError) then
    begin
      WriteLn(ErrOutput, lError);
      Exit(cExitToolFailure);
    end;
    lStopwatch.Stop;
    LogRemoveWithDone(aOptions, 'discovery',
      Format('files=%d withStatements=%d warnings=%d', [Length(lScanResult.fFiles),
      Length(lScanResult.fWithStatements), Length(lScanResult.fWarnings)]), lStopwatch);
    if aOptions.fRemoveWithMode <> TRemoveWithMode.rwmScan then
    begin
      LogRemoveWithProgress(aOptions, 'symbol-inventory start');
      lStopwatch := TStopwatch.StartNew;
      if not BuildRemoveWithSymbolInventory(aOptions, lProjectModel, lSymbolInventory, lError) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(cExitToolFailure);
      end;
      lStopwatch.Stop;
      LogRemoveWithDone(aOptions, 'symbol-inventory',
        Format('symbols=%d', [Length(lSymbolInventory.fSymbols)]), lStopwatch);

      LogRemoveWithProgress(aOptions, 'symbol-map-bridge start');
      lStopwatch := TStopwatch.StartNew;
      if not PrepareRemoveWithSymbolMapBridge(aOptions, lSymbolMapBridge, lError) then
      begin
        LogRemoveWithProgress(aOptions, 'symbol-map-bridge warning error=' + lError);
        lError := '';
      end;
      lStopwatch.Stop;
      LogRemoveWithDone(aOptions, 'symbol-map-bridge',
        Format('prepared=%s projectIndexed=%s', [BoolToStr(lSymbolMapBridge.fPrepared, True),
        BoolToStr(lSymbolMapBridge.fStatus.fProjectIndexed, True)]), lStopwatch);

      LogRemoveWithProgress(aOptions, 'resolver start');
      lStopwatch := TStopwatch.StartNew;
      if not ResolveRemoveWithIdentifiers(lSymbolInventory, lScanResult, lSymbolMapBridge, lResolverResult,
        lError) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(cExitToolFailure);
      end;
      lStopwatch.Stop;
      LogRemoveWithDone(aOptions, 'resolver',
        Format('classifications=%d', [Length(lResolverResult.fClassifications)]), lStopwatch);

      LogRemoveWithProgress(aOptions, 'planner start');
      lStopwatch := TStopwatch.StartNew;
      if not PlanRemoveWithRewrites(lSymbolInventory, lScanResult, lResolverResult, lPlanResult, lError) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(cExitToolFailure);
      end;
      lStopwatch.Stop;
      LogRemoveWithDone(aOptions, 'planner',
        Format('statements=%d planned=%d skipped=%d', [Length(lPlanResult.fStatements),
        CountRemoveWithPlannedStatements(lPlanResult, 'planned'), CountRemoveWithPlannedStatements(lPlanResult,
        'skipped')]), lStopwatch);

      if aOptions.fRemoveWithMode = TRemoveWithMode.rwmApply then
      begin
        LogRemoveWithProgress(aOptions, 'apply start');
        lStopwatch := TStopwatch.StartNew;
        lApplySucceeded := ApplyRemoveWithPlanTransactionally(aOptions, lProjectPath, lWorkspaceRoot, lPlanResult,
          lTransactionResult, lError);
        lStopwatch.Stop;
        LogRemoveWithDone(aOptions, 'apply', Format('status=%s files=%d',
          [RemoveWithTransactionStatusToText(lTransactionResult.fStatus), Length(lTransactionResult.fFiles)]),
          lStopwatch);
        if (not lApplySucceeded) and (lTransactionResult.fError = '') then
          lTransactionResult.fError := lError;
      end;
    end;

    if aOptions.fRemoveWithFormat = TRemoveWithFormat.rwfText then
      lOutputText := BuildRemoveWithTextReport(aOptions, lProjectPath, lWorkspaceRoot, lRunId, lUnitPath, lDirPath,
        lScanResult, lPlanResult, lTransactionResult)
    else
      lOutputText := BuildRemoveWithJsonReport(aOptions, lProjectPath, lWorkspaceRoot, lRunId, lUnitPath, lDirPath,
        lScanResult, lResolverResult, lPlanResult, lTransactionResult);
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
