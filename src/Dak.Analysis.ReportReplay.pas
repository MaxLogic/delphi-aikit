unit Dak.Analysis.ReportReplay;

{$SCOPEDENUMS ON}

interface

uses
  System.JSON;

// Finalizes one analysis output directory like postprocess.py's report-processing stage:
// normalized findings, ownership, projections, counts, SARIF, Markdown views and summary.json.
// Policy, baseline, delta, history and trend belong to the policy stage (T-325).
// Returns a caller-owned result object with the written artifact paths.
function FinalizeAnalysisReport(const aOutRoot: string; aCapturedProvenance: TJSONObject;
  aExecutionExitCode: Integer): TJSONObject; overload;
// The workflow passes the subject's own name, as analyze.py passes title=dproj.stem. Without it the
// title would follow the output folder, which the caller is free to point anywhere.
function FinalizeAnalysisReport(const aOutRoot, aTitle: string; aCapturedProvenance: TJSONObject;
  aExecutionExitCode: Integer): TJSONObject; overload;

implementation

uses
  System.Generics.Collections, System.Hash, System.IOUtils, System.StrUtils, System.SysUtils,
  AutoFree,
  Dak.Analysis.Findings, Dak.Analysis.FixInsightImport, Dak.Analysis.Ownership,
  Dak.Analysis.OwnershipContext, Dak.Analysis.Projections,
  Dak.Analysis.ReportBundle, Dak.Analysis.ReportPolicy, Dak.Analysis.ReportWriters,
  Dak.Analysis.SourceResolution, Dak.Analysis.Workspace, Dak.Settings;





function NullableClone(aValue: TJSONValue): TJSONValue;
begin
  if (aValue = nil) or (aValue is TJSONNull) then
    Result := TJSONNull.Create
  else
    Result := JsonCloneValue(aValue);
end;

function FileSha256OrNull(const aPath: string): TJSONValue;
begin
  if (aPath <> '') and TFile.Exists(aPath) then
    Result := TJSONString.Create(LowerCase(THashSHA2.GetHashStringFromFile(aPath)))
  else
    Result := TJSONNull.Create;
end;

// _enrich_provenance: reuse a captured provenance; otherwise inspect the workspace named by the
// seed or the subject's Git repository once and record the DAK identity beside it.
procedure EnrichProvenance(aSeed, aSummary: TJSONObject; const aOutRoot: string; aCaptured: TJSONObject);
var
  g: TGarbos;
  lCaptured, lDak, lInputs, lProvenance, lTarget, lWorkspace: TJSONObject;
  lSettings: TWorkspaceSettings;
  lSubject, lSubjectDirectory, lRoot: string;
  lFresh: TJSONObject;
begin
  lProvenance := JsonObjectMember(aSeed, 'provenance');
  if lProvenance = nil then
  begin
    lProvenance := TJSONObject.Create;
    aSeed.AddPair('provenance', lProvenance);
  end;
  lSubject := JsonText(aSummary, 'project');
  if lSubject = '' then
    lSubject := JsonText(aSummary, 'unit');
  lSubjectDirectory := '';
  if lSubject <> '' then
    lSubjectDirectory := TPath.GetDirectoryName(TPath.GetFullPath(lSubject));
  lFresh := nil;
  lCaptured := JsonObjectMember(aCaptured, 'target');
  if lCaptured <> nil then
    lTarget := JsonCloneValue(lCaptured) as TJSONObject
  else begin
    lWorkspace := JsonObjectMember(aSeed, 'workspace');
    lSettings := Default(TWorkspaceSettings);
    if lWorkspace <> nil then
    begin
      lSettings.fRoot := JsonText(lWorkspace, 'root');
      lSettings.fVcs := JsonText(lWorkspace, 'vcs');
      if lSettings.fVcs = '' then
        lSettings.fVcs := 'none';
    end else begin
      lRoot := '';
      if lSubjectDirectory <> '' then
        lRoot := FindNamedRepoRoot(lSubjectDirectory, '.git');
      lSettings.fRoot := lRoot;
      lSettings.fVcs := IfThen(lRoot = '', 'none', 'git');
    end;
    if (lSettings.fVcs = 'none') and (lSettings.fRoot = '') then
      lTarget := TJSONObject.Create.AddPair('vcs', 'none')
    else begin
      GC(lFresh, CaptureRunProvenance(lSettings, ParamStr(0), aOutRoot), g);
      lTarget := JsonCloneValue(JsonObjectMember(lFresh, 'target')) as TJSONObject;
      // The reference records the root only for a workspace named by the seed; a repository
      // inferred from the subject is identified without it.
      if lWorkspace = nil then
        lTarget.RemovePair('root').Free;
    end;
  end;
  lInputs := JsonObjectMember(aSeed, 'inputs');
  if lInputs = nil then
  begin
    lInputs := TJSONObject.Create;
    aSeed.AddPair('inputs', lInputs);
  end;
  if (lSubject <> '') and TFile.Exists(lSubject) and (lInputs.GetValue('project_sha256') = nil) then
    lInputs.AddPair('project_sha256', FileSha256OrNull(lSubject));
  JsonPut(lTarget, 'project_sha256', NullableClone(lInputs.GetValue('project_sha256')));
  JsonPut(lTarget, 'main_source_sha256', NullableClone(lInputs.GetValue('main_source_sha256')));
  if JsonArrayMember(lInputs, 'config_manifests') <> nil then
    JsonPut(lTarget, 'config_manifests', JsonCloneValue(JsonArrayMember(lInputs, 'config_manifests')))
  else
    JsonPut(lTarget, 'config_manifests', TJSONArray.Create);
  JsonPut(lProvenance, 'target', lTarget);
  lDak := JsonObjectMember(lProvenance, 'dak');
  if lDak = nil then
  begin
    lDak := TJSONObject.Create;
    lProvenance.AddPair('dak', lDak);
  end;
  lCaptured := JsonObjectMember(aCaptured, 'dak');
  if lCaptured = nil then
  begin
    if lFresh = nil then
    begin
      lSettings := Default(TWorkspaceSettings);
      lSettings.fVcs := 'none';
      lSettings.fRoot := aOutRoot;
      GC(lFresh, CaptureRunProvenance(lSettings, ParamStr(0), aOutRoot), g);
    end;
    lCaptured := JsonObjectMember(lFresh, 'dak');
  end;
  if lCaptured <> nil then
    for var lPair in lCaptured do
      JsonPut(lDak, lPair.JsonString.Value, JsonCloneValue(lPair.JsonValue));
  lSubject := Trim(JsonText(lDak, 'executable'));
  if lSubject = '' then
    lSubject := Trim(GetEnvironmentVariable('DAK_EXE'));
  if lSubject <> '' then
    JsonPut(lDak, 'executable_sha256', FileSha256OrNull(lSubject));
end;

function AnalyzerRequested(aSeed: TJSONObject; const aName: string): Boolean;
var
  lAnalyzer: TJSONObject;
begin
  lAnalyzer := JsonObjectMember(JsonObjectMember(aSeed, 'analyzers'), aName);
  Result := (lAnalyzer <> nil) and (lAnalyzer.GetValue('requested') is TJSONBool) and
    TJSONBool(lAnalyzer.GetValue('requested')).AsBoolean;
end;

function AnalyzerStatus(aSeed: TJSONObject; const aName: string): string;
begin
  Result := JsonText(JsonObjectMember(JsonObjectMember(aSeed, 'analyzers'), aName), 'status');
end;

// iter_records: a missing stream contributes no rows; the file itself is only rewritten when present.
function LoadRows(const aPath: string): TJSONArray;
begin
  if TFile.Exists(aPath) then
    Result := LoadAnalysisJsonLines(aPath)
  else
    Result := TJSONArray.Create;
end;

// _relative_artifact: an artifact that was not published has no entry, one inside the output root
// is named relative to it, and one published elsewhere keeps its absolute path.
function RelativeArtifact(const aOutRoot, aPath: string): string;
var
  lFull, lRoot: string;
begin
  Result := '';
  if aPath = '' then
    Exit;
  lFull := TPath.GetFullPath(aPath);
  if not (TFile.Exists(lFull) or TDirectory.Exists(lFull)) then
    Exit;
  lRoot := IncludeTrailingPathDelimiter(TPath.GetFullPath(aOutRoot));
  if lFull.StartsWith(lRoot, True) then
    Result := lFull.Substring(Length(lRoot)).Replace(PathDelim, '/')
  else
    Result := lFull;
end;

function StringsToArray(aValues: TJSONArray): TArray<string>;
var
  i: Integer;
begin
  SetLength(Result, aValues.Count);
  for i := 0 to aValues.Count - 1 do
    Result[i] := aValues.Items[i].Value;
end;

procedure WriteInfrastructureFailure(const aOutRoot, aTitle, aSummaryPath: string; aSeed: TJSONObject;
  const aErrors: TArray<string>; aResult: TJSONObject);
var
  lBaselinePath, lDeltaPath, lDeltaMdPath: string;
  lReasons: TJSONArray;
  lReasonLines: TList<string>;
  lError: string;
  lStatus, lArtifacts: TJSONObject;
  lDelta: TJSONObject;
begin
  lBaselinePath := Trim(GetEnvironmentVariable('DAK_BASELINE'));
  if lBaselinePath <> '' then
    lBaselinePath := TPath.GetFullPath(lBaselinePath)
  else
    lBaselinePath := TPath.Combine(aOutRoot, 'baseline.json');
  lDeltaPath := TPath.Combine(aOutRoot, 'delta.json');
  lDeltaMdPath := TPath.Combine(aOutRoot, 'delta.md');
  lReasons := TJSONArray.Create;
  lReasonLines := TList<string>.Create;
  try
    for lError in aErrors do
    begin
      lReasons.Add('Analyzer infrastructure error: ' + lError);
      lReasonLines.Add('- Analyzer infrastructure error: ' + lError);
    end;
    if lReasons.Count = 0 then
    begin
      lReasons.Add('Analyzer infrastructure status is incomplete.');
      lReasonLines.Add('- Analyzer infrastructure status is incomplete.');
    end;
    lDelta := TJSONObject.Create
      .AddPair('title', aTitle)
      .AddPair('baseline', TJSONObject.Create.AddPair('path', lBaselinePath).AddPair('created', TJSONBool.Create(False)))
      .AddPair('current', TJSONObject.Create.AddPair('summary_path', aSummaryPath))
      .AddPair('gate', TJSONObject.Create.AddPair('enabled', TJSONBool.Create(True))
        .AddPair('pass', TJSONBool.Create(False)).AddPair('reasons', lReasons));
    try
      WriteAnalysisJsonDocument(lDeltaPath, lDelta);
    finally
      lDelta.Free;
    end;
    WriteAnalysisText(lDeltaMdPath, '# Static analysis gate' + #10#10 + String.Join(#10, lReasonLines.ToArray) + #10);
  finally
    lReasonLines.Free;
  end;
  JsonPut(aSeed, 'schema_version', TJSONNumber.Create(2));
  lStatus := JsonObjectMember(aSeed, 'status');
  if lStatus = nil then
  begin
    lStatus := TJSONObject.Create;
    aSeed.AddPair('status', lStatus);
  end;
  JsonPutText(lStatus, 'infrastructure', 'failed');
  JsonPutText(lStatus, 'policy', 'not_evaluated');
  JsonPut(aSeed, 'errors', JsonStringArray(aErrors));
  lArtifacts := JsonObjectMember(aSeed, 'artifacts');
  if lArtifacts = nil then
  begin
    lArtifacts := TJSONObject.Create;
    aSeed.AddPair('artifacts', lArtifacts);
  end;
  JsonPutText(lArtifacts, 'summary_markdown', 'summary.md');
  JsonPutText(lArtifacts, 'delta', 'delta.md');
  JsonPutText(lArtifacts, 'delta_json', 'delta.json');
  WriteAnalysisJsonDocument(TPath.Combine(aOutRoot, 'summary.json'), aSeed);
  aResult.AddPair('baseline', lBaselinePath);
  aResult.AddPair('delta', lDeltaMdPath);
  aResult.AddPair('gate_pass', TJSONBool.Create(False));
  aResult.AddPair('baseline_created', TJSONBool.Create(False));
  aResult.AddPair('baseline_updated', TJSONBool.Create(False));
end;

function FinalizeAnalysisReport(const aOutRoot: string; aCapturedProvenance: TJSONObject;
  aExecutionExitCode: Integer): TJSONObject;
begin
  Result := FinalizeAnalysisReport(aOutRoot, '', aCapturedProvenance, aExecutionExitCode);
end;

function FinalizeAnalysisReport(const aOutRoot, aTitle: string; aCapturedProvenance: TJSONObject;
  aExecutionExitCode: Integer): TJSONObject;
var
  g: TGarbos;
  lActionable, lActive, lAnalyzer, lAnalyzers, lArtifacts, lCompatibility, lCompiler, lCounts,
    lPolicyContext, lResolvedPolicy, lRunContext, lSeed, lStatus, lSummary: TJSONObject;
  lContext: TAnalysisOwnershipContext;
  lDiagnostics: TArray<string>;
  lErrors: TList<string>;
  lFi, lPal: TJSONArray;
  lFiPath, lLegacyRoot, lOutRoot, lPalPath, lProjectDirectory, lSubject, lSummaryPath, lTitle: string;
  lWorkspaceRoot: string;
  lFullSarif, lMetrics, lExternal, lSarif, lTriage, lTriageChanged: string;
  lItem: TJSONValue;
  lPalRequested: Boolean;
  lPolicy: TAnalysisPolicyOutcome;
  lPolicyInput: TAnalysisPolicyInput;
  lSnapshot: TJSONObject;
  lHistory, lTrend: string;
  lResolver: TAnalysisSourceResolver;
  lName: string;
  lFailed: Boolean;
  lSarifCount: Integer;
  lTimestamp: string;
const
  cAnalyzers: array[0..1] of string = ('fixinsight', 'pascal_analyzer');
  cArtifactNames: array[0..13] of string = ('summary_markdown', 'fixinsight_jsonl', 'pascal_analyzer_jsonl',
    'baseline', 'delta', 'triage', 'triage_changed', 'triage_snippets', 'sarif', 'full_sarif',
    'external_summary', 'metrics', 'history', 'trend');
begin
  lOutRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(aOutRoot));
  lTitle := aTitle;
  if lTitle = '' then
    lTitle := TPath.GetFileName(lOutRoot);
  lSummaryPath := TPath.Combine(lOutRoot, 'summary.md');
  lFiPath := TPath.Combine(lOutRoot, 'fixinsight\fi-findings.jsonl');
  lPalPath := TPath.Combine(lOutRoot, 'pascal-analyzer\pal-findings.jsonl');
  Result := TJSONObject.Create;
  try
    GC(lSummary, ParseAnalysisSummaryMarkdown(lSummaryPath), g);
    GC(lRunContext, BuildAnalysisRunContext(lOutRoot, lSummary), g);
    GC(lSeed, LoadAnalysisStatusSeed(lOutRoot, lSummary, lRunContext, aExecutionExitCode >= 0), g);
    EnrichAnalyzerVersions(lSeed, lRunContext);
    lPolicyContext := JsonObjectMember(lSeed, 'policy');
    if lPolicyContext <> nil then
      lPolicyContext.RemovePair('status').Free;
    EnrichProvenance(lSeed, lSummary, lOutRoot, aCapturedProvenance);
    JsonPut(lSummary, 'provenance', JsonCloneValue(JsonObjectMember(lSeed, 'provenance')));
    // Infrastructure failures finalize a failed status without report processing.
    GC(lErrors, TList<string>.Create, g);
    if JsonArrayMember(lSummary, 'errors') <> nil then
      for lItem in JsonArrayMember(lSummary, 'errors') do
        lErrors.Add(lItem.Value);
    if (aExecutionExitCode >= 0) and (aExecutionExitCode <> 0) then
      lErrors.Insert(0, Format('DAK analyze failed (exit=%d).', [aExecutionExitCode]));
    lFailed := JsonText(JsonObjectMember(lSeed, 'status'), 'infrastructure') = 'failed';
    for lName in cAnalyzers do
      if AnalyzerRequested(lSeed, lName) and (AnalyzerStatus(lSeed, lName) <> 'complete') then
        lFailed := True;
    if lFailed and (JsonArrayMember(lSeed, 'errors') <> nil) then
      for lItem in JsonArrayMember(lSeed, 'errors') do
        if not lErrors.Contains(lItem.Value) then
          lErrors.Add(lItem.Value);
    if (lErrors.Count > 0) or lFailed then
    begin
      WriteInfrastructureFailure(lOutRoot, lTitle, lSummaryPath, lSeed, lErrors.ToArray, Result);
      Exit;
    end;
    ValidateAnalysisSummary(lSummary);
    lLegacyRoot := FindNamedRepoRoot(lOutRoot, '.git');
    lSubject := JsonText(lSummary, 'project');
    if lSubject = '' then
      lSubject := JsonText(lSummary, 'unit');
    lProjectDirectory := '';
    if lSubject <> '' then
    begin
      lProjectDirectory := TPath.GetDirectoryName(TPath.GetFullPath(lSubject));
      if lLegacyRoot = '' then
        lLegacyRoot := FindNamedRepoRoot(lProjectDirectory, '.git');
    end;
    // write_fixinsight_normalized: the analyzer's own fixinsight.txt becomes the normalized rows
    // the report stage reads. It runs before the empty-file rule so a real report is never
    // replaced by an empty one, and it does nothing when there is no text report to read.
    lWorkspaceRoot := JsonText(JsonObjectMember(lSeed, 'workspace'), 'root');
    if TDirectory.Exists(TPath.GetDirectoryName(lFiPath)) then
      WriteFixInsightNormalized(TPath.GetDirectoryName(lFiPath), lWorkspaceRoot,
        [lProjectDirectory, lWorkspaceRoot]);
    // Requested complete analyzers without a JSONL file own an empty one; an unrequested PAL
    // file is emptied.
    for lName in cAnalyzers do
      if AnalyzerRequested(lSeed, lName) and (AnalyzerStatus(lSeed, lName) = 'complete') then
      begin
        if (lName = 'fixinsight') and not TFile.Exists(lFiPath) then
          WriteAnalysisText(lFiPath, '');
        if (lName = 'pascal_analyzer') and not TFile.Exists(lPalPath) then
          WriteAnalysisText(lPalPath, '');
      end;
    lPalRequested := AnalyzerRequested(lSeed, 'pascal_analyzer');
    if (not lPalRequested) and TFile.Exists(lPalPath) then
      WriteAnalysisText(lPalPath, '');
    GC(lResolvedPolicy, ResolveAnalysisPolicy(lSeed), g);
    GC(lFi, LoadRows(lFiPath), g);
    GC(lPal, LoadRows(lPalPath), g);
    lContext := BuildAnalysisOwnershipContext(lSeed, lOutRoot, lLegacyRoot, lDiagnostics);
    GC(lResolver, TAnalysisSourceResolver.Create(lContext), g);
    if lFi <> nil then
      lResolver.AnnotateFixInsight(lFi);
    if lPal <> nil then
      lResolver.AnnotatePal(lPal);
    ApplyAnalysisReportProjections(lFi, lPal, lResolvedPolicy,
      StringsToArray(JsonArrayMember(lResolvedPolicy, 'exclude_path_masks')),
      JsonText(JsonObjectMember(JsonObjectMember(lSeed, 'analyzers'), 'pascal_analyzer'), 'version'),
      TPath.Combine(lOutRoot, 'pascal-analyzer'), lPalRequested);
    if TFile.Exists(lFiPath) then
      WriteAnalysisJsonLines(lFiPath, lFi);
    if TFile.Exists(lPalPath) then
      WriteAnalysisJsonLines(lPalPath, lPal);
    GC(lActionable, AnalysisActionableCounts(lSummary, lFi, lPal), g);
    WriteAnalysisSummaryOwnership(lSummaryPath, JsonObjectMember(lActionable, 'ownership'));
    // Rows without a rule identity are not publishable: each SARIF must carry every selected row.
    GC(lCounts, AnalysisReportProjections(lSummary, lFi, lPal), g);
    lSarif := WriteAnalysisSarif(lOutRoot, lFi, lPal, False, lSarifCount);
    if lSarifCount.ToString <> JsonText(JsonObjectMember(lCounts, 'actionable'), 'total') then
      raise EConvertError.CreateFmt('SARIF count mismatch: SARIF=%d, JSONL=%s',
        [lSarifCount, JsonText(JsonObjectMember(lCounts, 'actionable'), 'total')]);
    lFullSarif := WriteAnalysisSarif(lOutRoot, lFi, lPal, True, lSarifCount);
    if lSarifCount.ToString <> JsonText(JsonObjectMember(lCounts, 'raw'), 'total') then
      raise EConvertError.CreateFmt('SARIF count mismatch: SARIF=%d, JSONL=%s',
        [lSarifCount, JsonText(JsonObjectMember(lCounts, 'raw'), 'total')]);
    lExternal := WriteAnalysisExternalSummary(lOutRoot, lFi, lPal);
    lMetrics := WriteAnalysisMetricsSummary(lOutRoot, lFi, lPal);
    GC(lCompatibility, AnalysisCompatibilitySnapshot(lSeed, lContext), g);
    lPolicyInput := Default(TAnalysisPolicyInput);
    lPolicyInput.fOutRoot := lOutRoot;
    lPolicyInput.fTitle := lTitle;
    lPolicyInput.fSummaryPath := lSummaryPath;
    // Only a Git workspace contributes revision facts to the history rows.
    lPolicyInput.fRepoRoot := '';
    if SameText(JsonText(JsonObjectMember(lSeed, 'workspace'), 'vcs'), 'git') or
      SameText(JsonText(JsonObjectMember(JsonObjectMember(lSeed, 'provenance'), 'target'), 'vcs'), 'git') then
      lPolicyInput.fRepoRoot := lContext.fWorkspaceRoot;
    lPolicyInput.fSummary := lSummary;
    lPolicyInput.fSeed := lSeed;
    lPolicyInput.fRunContext := lRunContext;
    lPolicyInput.fResolvedPolicy := lResolvedPolicy;
    lPolicyInput.fActionable := lActionable;
    lPolicyInput.fCounts := lCounts;
    lPolicyInput.fCompatibility := lCompatibility;
    lPolicyInput.fFi := lFi;
    lPolicyInput.fPal := lPal;
    lPolicy := ApplyAnalysisReportPolicy(lPolicyInput);
    GC(lSnapshot, lPolicy.fSnapshot, g);
    lTriage := WriteAnalysisTriage(lOutRoot, lTitle, lFi, lPal, TAnalysisTriagePolicy.FromEnvironment);
    Result.AddPair('baseline', lPolicy.fBaselinePath);
    Result.AddPair('delta', lPolicy.fDeltaMdPath);
    Result.AddPair('gate_pass', TJSONBool.Create(lPolicy.fGatePass));
    Result.AddPair('policy_evaluated', TJSONBool.Create(lPolicy.fPolicyEvaluated));
    if lPolicy.fBaselineCreated then
      Result.AddPair('baseline_created', TJSONBool.Create(True));
    if lPolicy.fBaselineUpdated then
      Result.AddPair('baseline_updated', TJSONBool.Create(True));
    Result.AddPair('triage', lTriage);
    if AnalysisTruthyEnvironment('DAK_TRIAGE_SNIPPETS', False) and
      TFile.Exists(TPath.Combine(lOutRoot, 'triage-snippets.md')) then
      Result.AddPair('triage_snippets', TPath.Combine(lOutRoot, 'triage-snippets.md'));
    Result.AddPair('sarif', lSarif);
    Result.AddPair('full_sarif', lFullSarif);
    Result.AddPair('external_summary', lExternal);
    Result.AddPair('metrics', lMetrics);
    UpdateAnalysisHistoryAndTrend(lPolicyInput, lSnapshot, lHistory, lTrend);
    Result.AddPair('history', lHistory);
    Result.AddPair('trend', lTrend);
    if Trim(GetEnvironmentVariable('DAK_SCOPE')).ToLowerInvariant = 'changed' then
    begin
      lTriageChanged := WriteAnalysisTriageChanged(lOutRoot, lTitle, lSummary, lFi, lPal, lContext.fWorkspaceFiles);
      Result.AddPair('triage_changed', lTriageChanged);
    end;
    // summary.json (schema 3) from the enriched seed.
    JsonPut(lSeed, 'schema_version', TJSONNumber.Create(3));
    lTimestamp := JsonText(lSummary, 'timestamp');
    if lTimestamp = '' then
      JsonPut(lSeed, 'timestamp', TJSONNull.Create)
    else
      JsonPutText(lSeed, 'timestamp', lTimestamp);
    lStatus := JsonObjectMember(lSeed, 'status');
    if lStatus = nil then
    begin
      lStatus := TJSONObject.Create;
      lSeed.AddPair('status', lStatus);
    end;
    JsonPutText(lStatus, 'infrastructure', 'complete');
    JsonPutText(lStatus, 'postprocessor', 'complete');
    JsonPutText(lStatus, 'finalization', 'complete');
    JsonPutText(lStatus, 'ownership_resolution',
      IfThen(JsonText(JsonObjectMember(lCounts, 'unknown'), 'total') <> '0', 'failed', 'complete'));
    if lPolicy.fPolicyEvaluated then
      JsonPutText(lStatus, 'policy', IfThen(lPolicy.fGatePass, 'pass', 'fail'))
    else
      JsonPutText(lStatus, 'policy', 'not_evaluated');
    lCompiler := JsonObjectMember(lSeed, 'compiler');
    if lCompiler = nil then
    begin
      lCompiler := TJSONObject.Create;
      lSeed.AddPair('compiler', lCompiler);
    end;
    for lName in ['platform', 'config', 'delphi'] do
      if lCompiler.GetValue(lName) = nil then
        lCompiler.AddPair(lName, JsonText(lRunContext, lName));
    lAnalyzers := JsonObjectMember(lSeed, 'analyzers');
    if lAnalyzers = nil then
    begin
      lAnalyzers := TJSONObject.Create;
      lSeed.AddPair('analyzers', lAnalyzers);
    end;
    for lName in cAnalyzers do
    begin
      lAnalyzer := JsonObjectMember(lAnalyzers, lName);
      if lAnalyzer = nil then
      begin
        lAnalyzer := TJSONObject.Create;
        lAnalyzers.AddPair(lName, lAnalyzer);
      end;
      JsonPutText(lAnalyzer, 'count_quality', 'complete');
    end;
    EnrichAnalyzerVersions(lSeed, lRunContext);
    if lPolicyContext <> nil then
    begin
      lActive := TJSONObject.Create;
      for lName in ['gate_ownership', 'exclude_path_masks', 'gate_metrics', 'fixinsight_ignore', 'pal_ignore_rules'] do
        lActive.AddPair(lName, JsonCloneValue(JsonArrayMember(lResolvedPolicy, lName)));
      lActive.AddPair('triage', AnalysisActiveTriagePolicy);
      JsonPut(lPolicyContext, 'active', lActive);
    end;
    lAnalyzer := JsonObjectMember(lAnalyzers, 'pascal_analyzer');
    JsonPut(lAnalyzer, 'verified_rule_aliases', AnalysisPalRegisteredAliases(JsonText(lAnalyzer, 'version')));
    JsonPut(lSeed, 'counts', JsonCloneValue(lCounts));
    JsonPut(lSeed, 'compatibility', JsonCloneValue(lCompatibility));
    if JsonArrayMember(lSummary, 'errors') <> nil then
      JsonPut(lSeed, 'errors', JsonCloneValue(JsonArrayMember(lSummary, 'errors')))
    else
      JsonPut(lSeed, 'errors', TJSONArray.Create);
    lArtifacts := JsonObjectMember(lSeed, 'artifacts');
    if lArtifacts = nil then
    begin
      lArtifacts := TJSONObject.Create;
      lSeed.AddPair('artifacts', lArtifacts);
    end;
    // summary_json["artifacts"].update(artifacts): only artifacts that exist are added, and an entry
    // the seed already carries is kept rather than blanked.
    if RelativeArtifact(lOutRoot, lSummaryPath) <> '' then
      JsonPutText(lArtifacts, 'summary_markdown', RelativeArtifact(lOutRoot, lSummaryPath));
    if RelativeArtifact(lOutRoot, lFiPath) <> '' then
      JsonPutText(lArtifacts, 'fixinsight_jsonl', RelativeArtifact(lOutRoot, lFiPath));
    if RelativeArtifact(lOutRoot, lPalPath) <> '' then
      JsonPutText(lArtifacts, 'pascal_analyzer_jsonl', RelativeArtifact(lOutRoot, lPalPath));
    for lName in cArtifactNames do
      if (Result.GetValue(lName) <> nil) and (RelativeArtifact(lOutRoot, Result.GetValue(lName).Value) <> '') then
        JsonPutText(lArtifacts, lName, RelativeArtifact(lOutRoot, Result.GetValue(lName).Value));
    WriteAnalysisJsonDocument(TPath.Combine(lOutRoot, 'summary.json'), lSeed);
    Result.AddPair('summary_json', TPath.Combine(lOutRoot, 'summary.json'));
  except
    Result.Free;
    raise;
  end;
end;

end.
