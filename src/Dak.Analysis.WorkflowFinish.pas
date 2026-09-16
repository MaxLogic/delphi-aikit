unit Dak.Analysis.WorkflowFinish;

{$SCOPEDENUMS ON}

interface

uses
  System.JSON,
  Dak.Diagnostics, Dak.Settings;

type
  // What the analyze workflow learned after the analyzers finished.
  TAnalysisWorkflowOutcome = record
    fExitCode: Integer;
    fFinalized: Boolean;
    fGatePass: Boolean;
    fDeltaPath: string;
    fSummaryMarkdown: string;
    // Lines for stderr, in the order the reference prints them.
    fDiagnostic: string;
  end;

// analyze.py main() after the analyzer child returns: read summary.md, finalize the report, verify
// it, evaluate the gate and map everything to the documented exit codes. A missing summary and a
// failed gate are both rejected results; a finalization failure over a successful analyzer run is
// an environment error and leaves a diagnostic beside the report. The analyzer's own failure wins.
function FinishAnalysisWorkflow(const aOutRoot, aTitle: string; aCapturedProvenance: TJSONObject;
  aAnalyzerExitCode: Integer): TAnalysisWorkflowOutcome;

// The analyze commands' two ends of the workflow, shared by the project and unit runners.
// capture_run_provenance before the analyzers: a failure is reported and finalization recaptures.
// The caller owns the result, which may be nil.
function CaptureAnalysisRunProvenance(const aWorkspace: TWorkspaceSettings; const aOutRoot: string;
  aDiagnostics: TDiagnostics): TJSONObject;
// After the analyzers: finish the workflow, echo summary.md as analyze.py printed it, report the
// outcome's stderr lines through the diagnostics and return the run's exit code.
function FinishAnalysisRun(const aOutRoot, aTitle: string; aCapturedProvenance: TJSONObject;
  aAnalyzerExitCode: Integer; aDiagnostics: TDiagnostics): Integer;
// A previous run's summary never survives into a new run, whether or not --clean was requested.
procedure RemoveStaleAnalysisSummary(const aOutRoot: string);
// The wrappers started DAK with cwd=workspace.root, so the analyzers and the recorded analysis_cwd do
// not depend on where the command was typed. Returns the caller's directory for LeaveAnalysisWorkspace.
function EnterAnalysisWorkspace(const aWorkspaceRoot: string): string;
procedure LeaveAnalysisWorkspace(const aCallerDirectory: string);

implementation

uses
  System.IOUtils, System.SysUtils,
  AutoFree,
  Dak.Analysis.ReportBundle, Dak.Analysis.ReportReplay, Dak.Analysis.ReportVerify,
  Dak.Analysis.ReportWriters, Dak.Analysis.Workspace, Dak.CommandOutput,
  dak.exitcodes;

const
  cDiagnosticName = 'postprocessor-error.txt';

procedure AddLine(var aOutcome: TAnalysisWorkflowOutcome; const aLine: string);
begin
  if aOutcome.fDiagnostic <> '' then
    aOutcome.fDiagnostic := aOutcome.fDiagnostic + sLineBreak;
  aOutcome.fDiagnostic := aOutcome.fDiagnostic + aLine;
end;

// The published summary.json, when it is a readable JSON object; nil otherwise.
function LoadSummaryObject(const aPath: string): TJSONObject;
var
  lValue: TJSONValue;
begin
  Result := nil;
  if not TFile.Exists(aPath) then
    Exit;
  try
    lValue := TJSONObject.ParseJSONValue(TFile.ReadAllText(aPath, TEncoding.UTF8));
  except
    // An unreadable summary is left alone, as the reference leaves it; the diagnostic file already
    // carries the failure.
    on E: Exception do
      Exit;
  end;
  if lValue is TJSONObject then
    Result := TJSONObject(lValue)
  else
    lValue.Free;
end;

// A member that the reference would create with setdefault: an existing member of another type is
// left untouched and nil is returned so the caller skips that part of the patch.
function DefaultMember(aObject: TJSONObject; const aName: string; aClass: TClass): TJSONValue;
var
  lValue: TJSONValue;
begin
  lValue := aObject.GetValue(aName);
  if lValue = nil then
  begin
    if aClass = TJSONArray then
      lValue := TJSONArray.Create
    else
      lValue := TJSONObject.Create;
    aObject.AddPair(aName, lValue);
  end;
  if lValue is aClass then
    Result := lValue
  else
    Result := nil;
end;

// _record_postprocessor_failure: the diagnostic file beside the report, and a summary.json that no
// longer claims a finalization it did not get. Returns the diagnostic path.
function RecordFinalizationFailure(const aOutRoot: string; aError: Exception): string;
var
  g: TGarbos;
  lArtifacts, lStatus: TJSONValue;
  lErrors: TJSONValue;
  lSummary: TJSONObject;
  lSummaryPath: string;
begin
  Result := TPath.Combine(aOutRoot, cDiagnosticName);
  WriteAnalysisText(Result, aError.ClassName + ': ' + aError.Message + #10);
  lSummaryPath := TPath.Combine(aOutRoot, 'summary.json');
  GC(lSummary, LoadSummaryObject(lSummaryPath), g);
  if lSummary = nil then
    Exit;
  lStatus := DefaultMember(lSummary, 'status', TJSONObject);
  if lStatus <> nil then
  begin
    JsonPutText(TJSONObject(lStatus), 'postprocessor', 'failed');
    JsonPutText(TJSONObject(lStatus), 'finalization', 'incomplete');
  end;
  lErrors := DefaultMember(lSummary, 'errors', TJSONArray);
  if lErrors <> nil then
    TJSONArray(lErrors).Add('Postprocessor failed: ' + aError.Message);
  lArtifacts := DefaultMember(lSummary, 'artifacts', TJSONObject);
  if lArtifacts <> nil then
    JsonPutText(TJSONObject(lArtifacts), 'postprocessor_diagnostic', cDiagnosticName);
  WriteAnalysisJsonDocument(lSummaryPath, lSummary);
end;

function FinishAnalysisWorkflow(const aOutRoot, aTitle: string; aCapturedProvenance: TJSONObject;
  aAnalyzerExitCode: Integer): TAnalysisWorkflowOutcome;
var
  g: TGarbos;
  lDiagnosticPath: string;
  lReport: TJSONObject;
  lSummaryPath: string;
begin
  Result := Default(TAnalysisWorkflowOutcome);
  Result.fGatePass := True;
  lSummaryPath := TPath.Combine(aOutRoot, 'summary.md');
  if not TFile.Exists(lSummaryPath) then
  begin
    AddLine(Result, 'Summary not found: ' + lSummaryPath);
    // The analyzers produced nothing to process. Their own failure is the better answer.
    if aAnalyzerExitCode <> 0 then
      Result.fExitCode := aAnalyzerExitCode
    else
      Result.fExitCode := cExitRejectedResult;
    Exit;
  end;
  Result.fSummaryMarkdown := TFile.ReadAllText(lSummaryPath, TEncoding.UTF8);

  lReport := nil;
  try
    GC(lReport, FinalizeAnalysisReport(aOutRoot, aTitle, aCapturedProvenance, aAnalyzerExitCode), g);
    Result.fFinalized := True;
    Result.fDeltaPath := JsonText(lReport, 'delta');
    Result.fGatePass := (lReport.GetValue('gate_pass') = nil) or
      TJSONBool(lReport.GetValue('gate_pass')).AsBoolean;
    if not Result.fGatePass then
      AddLine(Result, 'Static analysis gate failed (see: ' + Result.fDeltaPath + ')');
  except
    on E: Exception do
    begin
      if aAnalyzerExitCode <> 0 then
      begin
        // The analyzers already failed: theirs is the answer, and nothing is recorded over it.
        AddLine(Result, 'Post-processing failed after analyzer failure: ' + E.Message);
        Result.fExitCode := aAnalyzerExitCode;
        Exit;
      end;
      lDiagnosticPath := TPath.Combine(aOutRoot, cDiagnosticName);
      try
        lDiagnosticPath := RecordFinalizationFailure(aOutRoot, E);
      except
        // Recording is best effort: a report directory we cannot write to must not replace the
        // finalization failure we are about to report.
        on lRecordError: Exception do
          AddLine(Result, 'Postprocessor diagnostic could not be recorded: ' + lRecordError.Message);
      end;
      AddLine(Result, 'Post-processing failed after successful analyzer: ' + E.Message +
        ' (diagnostic: ' + lDiagnosticPath + ')');
      Result.fExitCode := cExitEnvironmentError;
      Exit;
    end;
  end;

  // Only a fully processed report has a bundle to check; an infrastructure failure publishes the
  // status seed and a refusing delta by design. The check reports rather than decides (D1).
  if lReport.GetValue('triage') <> nil then
    try
      // Verification raises on the first inconsistency; its result object carries nothing we report.
      VerifyAnalysisReport(aOutRoot).Free;
    except
      on E: Exception do
        AddLine(Result, 'Report verification: ' + E.Message);
    end;

  if aAnalyzerExitCode <> 0 then
    Result.fExitCode := aAnalyzerExitCode
  else if not Result.fGatePass then
    Result.fExitCode := cExitRejectedResult
  else
    Result.fExitCode := cExitSuccess;
end;

function CaptureAnalysisRunProvenance(const aWorkspace: TWorkspaceSettings; const aOutRoot: string;
  aDiagnostics: TDiagnostics): TJSONObject;
begin
  Result := nil;
  try
    Result := CaptureRunProvenance(aWorkspace, ParamStr(0), aOutRoot);
  except
    // Provenance is evidence, not a precondition: finalization recaptures it when we have none.
    on E: Exception do
      aDiagnostics.AddWarning('Run provenance capture: ' + E.Message);
  end;
end;

function FinishAnalysisRun(const aOutRoot, aTitle: string; aCapturedProvenance: TJSONObject;
  aAnalyzerExitCode: Integer; aDiagnostics: TDiagnostics): Integer;
var
  lError: string;
  lOutcome: TAnalysisWorkflowOutcome;
begin
  lOutcome := FinishAnalysisWorkflow(aOutRoot, aTitle, aCapturedProvenance, aAnalyzerExitCode);
  // analyze.py prints summary.md as it stood before finalization, with print's trailing line break.
  // The shared command writer keeps DAK's console behavior and tolerates a closed pipe.
  if lOutcome.fSummaryMarkdown <> '' then
    if not WriteCommandOutput(lOutcome.fSummaryMarkdown, '', copStdoutWhenNoPathOrDash, True, False, False,
      lError) then
      aDiagnostics.AddWarning('Summary output: ' + lError);
  if lOutcome.fDiagnostic <> '' then
    aDiagnostics.AddWarning(lOutcome.fDiagnostic);
  Result := lOutcome.fExitCode;
end;

function EnterAnalysisWorkspace(const aWorkspaceRoot: string): string;
begin
  Result := GetCurrentDir;
  // An unresolved workspace leaves the directory alone; settings loading has already reported it.
  if (aWorkspaceRoot <> '') and TDirectory.Exists(aWorkspaceRoot) then
    SetCurrentDir(aWorkspaceRoot);
end;

procedure LeaveAnalysisWorkspace(const aCallerDirectory: string);
begin
  if aCallerDirectory <> '' then
    SetCurrentDir(aCallerDirectory);
end;

procedure RemoveStaleAnalysisSummary(const aOutRoot: string);
var
  lStale: string;
begin
  for lStale in ['summary.md', 'summary.json'] do
    if TFile.Exists(TPath.Combine(aOutRoot, lStale)) then
      TFile.Delete(TPath.Combine(aOutRoot, lStale));
end;

end.
