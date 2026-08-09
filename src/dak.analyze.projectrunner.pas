unit Dak.Analyze.ProjectRunner;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.SysUtils,
  Dak.Analyze.Common, Dak.Diagnostics, Dak.Messages, Dak.Settings, Dak.Types;

function RunAnalyzeProject(const aOptions: TAppOptions): Integer;

implementation

uses
  System.Diagnostics, System.Hash, System.JSON, System.StrUtils,
  Dak.PascalAnalyzer.Artifacts, Dak.PascalAnalyzerRunner;

type
  TAnalyzeProjectRunner = class
  private
    fOptions: TAppOptions;
    fDiagnostics: TDiagnostics;
    fErrors: TList<string>;
    fFixOptions: TFixInsightExtraOptions;
    fFixIgnoreDefaults: TFixInsightIgnoreDefaults;
    fReportFilter: TReportFilterDefaults;
    fPascalAnalyzer: TPascalAnalyzerDefaults;
    fSettings: TDakSettings;
    fParams: TFixInsightParams;
    fProjectDproj: string;
    fProjectName: string;
    fOutRoot: string;
    fFixDir: string;
    fPaDir: string;
    fRunLog: string;
    fFixTxtPath: string;
    fFixXmlPath: string;
    fFixCsvPath: string;
    fFixTxtRan: Boolean;
    fFixXmlRan: Boolean;
    fFixCsvRan: Boolean;
    fFixTxtExit: Integer;
    fFixXmlExit: Integer;
    fFixCsvExit: Integer;
    fFixTxtDurationMs: Int64;
    fFixXmlDurationMs: Int64;
    fFixCsvDurationMs: Int64;
    fFixCounts: TFixInsightCounts;
    fExitCode: Integer;
    fPal: TPalSummary;
    fPalDurationMs: Int64;
    fSummaryPath: string;
    fSummaryText: string;
    procedure AddError(const aMessage: string; const aExitCode: Integer);
    function TryOpenLog: Boolean;
    function TryPrepareParams: Boolean;
    procedure PrepareOutputTree;
    procedure PrepareFixInsightParams;
    procedure InitFixInsightDefaults;
    procedure RunFixInsightReports;
    procedure RunFixInsightReport(const aFormat: TReportFormat; const aOutputPath: string; const aLabel: string;
      var aRan: Boolean; var aExitCode: Integer; var aDurationMs: Int64);
    procedure RunPascalAnalyzer;
    procedure WriteSummary;
    procedure WriteStatusSeed;
  public
    constructor Create(const aOptions: TAppOptions);
    destructor Destroy; override;
    function Execute: Integer;
  end;

constructor TAnalyzeProjectRunner.Create(const aOptions: TAppOptions);
begin
  inherited Create;
  fOptions := aOptions;
  fDiagnostics := TDiagnostics.Create;
  fErrors := TList<string>.Create;
  fExitCode := 0;
end;

destructor TAnalyzeProjectRunner.Destroy;
begin
  fErrors.Free;
  fDiagnostics.Free;
  inherited Destroy;
end;

procedure TAnalyzeProjectRunner.AddError(const aMessage: string; const aExitCode: Integer);
begin
  fErrors.Add(aMessage);
  if (fExitCode = 0) and (aExitCode <> 0) then
    fExitCode := aExitCode;
end;

function TAnalyzeProjectRunner.TryOpenLog: Boolean;
var
  lError: string;
begin
  Result := True;
  fDiagnostics.Verbose := fOptions.fVerbose;
  if fOptions.fHasLogFile then
  begin
    if not fDiagnostics.TryOpenLogFile(TPath.GetFullPath(fOptions.fLogFile), lError) then
    begin
      WriteLn(ErrOutput, lError);
      fExitCode := 6;
      Exit(False);
    end;
    if fOptions.fHasLogTee then
      fDiagnostics.LogToStderr := fOptions.fLogTee
    else
      fDiagnostics.LogToStderr := False;
  end;
end;

function TAnalyzeProjectRunner.TryPrepareParams: Boolean;
var
  lError: string;
  lErrorCode: Integer;
begin
  if not TryPrepareProjectParams(fOptions, fDiagnostics, fParams, fFixOptions, fFixIgnoreDefaults, fReportFilter,
    fPascalAnalyzer, fSettings, fProjectName, fProjectDproj, lError, lErrorCode) then
  begin
    WriteLn(ErrOutput, lError);
    fExitCode := lErrorCode;
    Exit(False);
  end;
  Result := True;
end;

procedure TAnalyzeProjectRunner.PrepareOutputTree;
begin
  fOutRoot := BuildOutputRoot(fOptions.fAnalyzeOutPath, fProjectDproj, fProjectName);
  if fOptions.fAnalyzeClean and DirectoryExists(fOutRoot) then
    TDirectory.Delete(fOutRoot, True);
  TDirectory.CreateDirectory(fOutRoot);

  fFixDir := TPath.Combine(fOutRoot, 'fixinsight');
  fPaDir := TPath.Combine(fOutRoot, 'pascal-analyzer');
  TDirectory.CreateDirectory(fFixDir);
  TDirectory.CreateDirectory(fPaDir);

  fRunLog := TPath.Combine(fOutRoot, 'run.log');
  if fOptions.fAnalyzeClean or (not FileExists(fRunLog)) then
    WriteLogText(fRunLog, '');
end;

procedure TAnalyzeProjectRunner.PrepareFixInsightParams;
begin
  fParams.fFixIgnore := fFixOptions.fIgnore;
  fParams.fFixSettings := fFixOptions.fSettings;
  fParams.fFixSilent := fFixOptions.fSilent;
  fParams.fTimeoutSec := fFixOptions.fTimeoutSec;
  if fParams.fFixSettings <> '' then
    fParams.fFixSettings := TPath.GetFullPath(fParams.fFixSettings);
end;

procedure TAnalyzeProjectRunner.InitFixInsightDefaults;
begin
  fFixTxtPath := TPath.Combine(fFixDir, 'fixinsight.txt');
  fFixXmlPath := TPath.Combine(fFixDir, 'fixinsight.xml');
  fFixCsvPath := TPath.Combine(fFixDir, 'fixinsight.csv');

  fFixTxtRan := False;
  fFixXmlRan := False;
  fFixCsvRan := False;
  fFixTxtExit := -1;
  fFixXmlExit := -1;
  fFixCsvExit := -1;
  fFixTxtDurationMs := 0;
  fFixXmlDurationMs := 0;
  fFixCsvDurationMs := 0;
end;

procedure TAnalyzeProjectRunner.RunFixInsightReport(const aFormat: TReportFormat; const aOutputPath: string;
  const aLabel: string; var aRan: Boolean; var aExitCode: Integer; var aDurationMs: Int64);
var
  lRunExit: Cardinal;
  lRunError: string;
  lLogPath: string;
  lStopwatch: TStopwatch;
  lStdErrLogPath: string;
  lStdOutLogPath: string;
begin
  aRan := True;
  fParams.fFixOutput := TPath.GetFullPath(aOutputPath);
  if aFormat = TReportFormat.rfXml then
  begin
    fParams.fFixXml := True;
    fParams.fFixCsv := False;
    lLogPath := TPath.Combine(fFixDir, 'fixinsight.xml.log');
  end else if aFormat = TReportFormat.rfCsv then
  begin
    fParams.fFixXml := False;
    fParams.fFixCsv := True;
    lLogPath := TPath.Combine(fFixDir, 'fixinsight.csv.log');
  end
  else
  begin
    fParams.fFixXml := False;
    fParams.fFixCsv := False;
    lLogPath := TPath.Combine(fFixDir, 'fixinsight.txt.log');
  end;
  lStdOutLogPath := TPath.ChangeExtension(lLogPath, '.stdout.log');
  lStdErrLogPath := TPath.ChangeExtension(lLogPath, '.stderr.log');

  lStopwatch := TStopwatch.StartNew;
  try
    if TryRunFixInsightLogged(fParams, lStdOutLogPath, lStdErrLogPath, fRunLog, lRunExit, lRunError) then
    begin
      aExitCode := Integer(lRunExit);
      if aExitCode <> 0 then
        AddError(Format('%s failed (exit=%d).', [aLabel, aExitCode]), aExitCode);
    end else
    begin
      AddError(aLabel + ' failed: ' + lRunError, 6);
    end;
  finally
    lStopwatch.Stop;
    aDurationMs := lStopwatch.ElapsedMilliseconds;
  end;
  WriteToolLog(lLogPath, aLabel, aExitCode, lRunError);
end;

procedure TAnalyzeProjectRunner.RunFixInsightReports;
begin
  PrepareFixInsightParams;
  InitFixInsightDefaults;
  if not fOptions.fAnalyzeFixInsight then
    Exit;

  if TReportFormat.rfText in fOptions.fAnalyzeFiFormats then
    RunFixInsightReport(TReportFormat.rfText, fFixTxtPath, 'FixInsight TXT', fFixTxtRan, fFixTxtExit,
      fFixTxtDurationMs);
  if TReportFormat.rfXml in fOptions.fAnalyzeFiFormats then
    RunFixInsightReport(TReportFormat.rfXml, fFixXmlPath, 'FixInsight XML', fFixXmlRan, fFixXmlExit,
      fFixXmlDurationMs);
  if TReportFormat.rfCsv in fOptions.fAnalyzeFiFormats then
    RunFixInsightReport(TReportFormat.rfCsv, fFixCsvPath, 'FixInsight CSV', fFixCsvRan, fFixCsvExit,
      fFixCsvDurationMs);
end;

procedure TAnalyzeProjectRunner.RunPascalAnalyzer;
var
  lRunExit: Cardinal;
  lRunError: string;
  lPaReportRoot: string;
  lPalPostError: string;
  lPalCounts: TPalFindingCounts;
  lStopwatch: TStopwatch;
  lStdErrLogPath: string;
  lStdOutLogPath: string;
begin
  fPal := Default(TPalSummary);
  fPalDurationMs := 0;
  if not fOptions.fAnalyzePal then
    Exit;

  fPal.Ran := True;
  if fOptions.fHasPaOutput then
    fPascalAnalyzer.fOutput := TPath.GetFullPath(fOptions.fPaOutput)
  else if fPascalAnalyzer.fOutput <> '' then
    fPascalAnalyzer.fOutput := TPath.GetFullPath(fPascalAnalyzer.fOutput)
  else
    fPascalAnalyzer.fOutput := fPaDir;
  fPal.OutputRoot := fPascalAnalyzer.fOutput;
  lStdOutLogPath := TPath.Combine(fPaDir, 'pascal-analyzer.stdout.log');
  lStdErrLogPath := TPath.Combine(fPaDir, 'pascal-analyzer.stderr.log');

  lStopwatch := TStopwatch.StartNew;
  if TryRunPalLogged(fParams, fPascalAnalyzer, lStdOutLogPath, lStdErrLogPath, fRunLog, lRunExit, lRunError) then
  begin
    fPal.ExitCode := Integer(lRunExit);
    if fPal.ExitCode <> 0 then
      AddError(Format('Pascal Analyzer failed (exit=%d).', [fPal.ExitCode]), fPal.ExitCode)
    else
    begin
      try
        lPaReportRoot := TPath.Combine(fPal.OutputRoot, TPath.GetFileNameWithoutExtension(fParams.fProjectDpr));
        if FileExists(TPath.Combine(lPaReportRoot, 'Status.xml')) then
        begin
          fPal.ReportRoot := lPaReportRoot;
          ReadStatusSummary(TPath.Combine(lPaReportRoot, 'Status.xml'), fPal.Version, fPal.Compiler);
          if not TryGeneratePalArtifactsWithCounts(lPaReportRoot, fPal.OutputRoot, lPalCounts, lPalPostError) then
            AddError('PAL findings generation failed: ' + lPalPostError, 6);
          fPal.Warnings := lPalCounts.Warnings;
          fPal.StrongWarnings := lPalCounts.StrongWarnings;
          fPal.Optimizations := lPalCounts.Optimizations;
        end else
        begin
          lPalPostError := 'Status.xml not found in expected PAL report folder: ' + lPaReportRoot;
          AddError('PAL report root not found: ' + lPalPostError, 6);
        end;
      except
        on E: Exception do
          AddError('PAL post-processing failed: ' + E.ClassName + ': ' + E.Message, 6);
      end;
    end;
  end else
  begin
    fPal.ExitCode := -1;
    AddError('Pascal Analyzer failed: ' + lRunError, 6);
  end;
  lStopwatch.Stop;
  fPalDurationMs := lStopwatch.ElapsedMilliseconds;
  WriteToolLog(TPath.Combine(fPaDir, 'pascal-analyzer.log'), 'PALCMD', fPal.ExitCode, lRunError);
end;

procedure TAnalyzeProjectRunner.WriteStatusSeed;
var
  lAnalyzers: TJSONObject;
  lArtifacts: TJSONObject;
  lCompiler: TJSONObject;
  lConfigFiles: TJSONArray;
  lCounts: TJSONObject;
  lErrors: TJSONArray;
  lFixAnalyzer: TJSONObject;
  lFixComplete: Boolean;
  lFixCounts: TJSONObject;
  lFixQuality: string;
  lFixRuns: TJSONArray;
  lFormats: TJSONArray;
  lInput: string;
  lInputs: TJSONObject;
  lPalAnalyzer: TJSONObject;
  lPalComplete: Boolean;
  lPalCounts: TJSONObject;
  lPalQuality: string;
  lPalRuns: TJSONArray;
  lPolicy: TJSONObject;
  lPolicyOrigins: TJSONObject;
  lPolicySources: TJSONArray;
  lPolicyValues: TJSONObject;
  lRoot: TJSONObject;
  lSettingsPath: string;
  lStatus: TJSONObject;

  function HashArray(const aValues: TArray<string>): string;
  begin
    Result := LowerCase(THashSHA2.GetHashString(String.Join(#10, aValues)));
  end;

  function HashFile(const aPath: string): string;
  begin
    if (aPath = '') or (not FileExists(aPath)) then
      Exit('');
    Result := LowerCase(THashSHA2.GetHashStringFromFile(aPath));
  end;

  function StringListJson(const aValues: string): TJSONArray;
  var
    lValue: string;
  begin
    Result := TJSONArray.Create;
    for lValue in aValues.Split([';']) do
      if Trim(lValue) <> '' then
        Result.AddElement(TJSONString.Create(Trim(lValue)));
  end;

  function HasAnalyzerError(const aPrefixes: TArray<string>): Boolean;
  var
    lError: string;
    lPrefix: string;
  begin
    for lError in fErrors do
      for lPrefix in aPrefixes do
        if StartsText(lPrefix, lError) then
          Exit(True);
    Result := False;
  end;

  procedure AddFixRun(const aFormat: string; const aReportPath: string; const aRan: Boolean;
    const aExitCode: Integer; const aDurationMs: Int64);
  var
    lRun: TJSONObject;
    lRunArtifacts: TJSONObject;
  begin
    if not aRan then
      Exit;
    lRunArtifacts := TJSONObject.Create
      .AddPair('report', 'fixinsight/' + TPath.GetFileName(aReportPath))
      .AddPair('stdout', 'fixinsight/' + TPath.GetFileName(aReportPath) + '.stdout.log')
      .AddPair('stderr', 'fixinsight/' + TPath.GetFileName(aReportPath) + '.stderr.log')
      .AddPair('log', 'fixinsight/' + TPath.GetFileName(aReportPath) + '.log');
    lRun := TJSONObject.Create
      .AddPair('format', aFormat)
      .AddPair('exit_code', TJSONNumber.Create(aExitCode))
      .AddPair('duration_ms', TJSONNumber.Create(aDurationMs))
      .AddPair('parse_status', IfThen((aFormat = 'txt') and FileExists(aReportPath), 'complete',
        IfThen(aFormat = 'txt', 'unavailable', 'not_applicable')))
      .AddPair('artifacts', lRunArtifacts);
    lFixRuns.AddElement(lRun);
  end;

begin
  lFixComplete := (not fOptions.fAnalyzeFixInsight) or
    (((not (TReportFormat.rfText in fOptions.fAnalyzeFiFormats)) or (fFixTxtRan and (fFixTxtExit = 0))) and
    ((not (TReportFormat.rfXml in fOptions.fAnalyzeFiFormats)) or (fFixXmlRan and (fFixXmlExit = 0))) and
    ((not (TReportFormat.rfCsv in fOptions.fAnalyzeFiFormats)) or (fFixCsvRan and (fFixCsvExit = 0))) and
    (not HasAnalyzerError(['FixInsight'])));
  lPalComplete := (not fOptions.fAnalyzePal) or
    (fPal.Ran and (fPal.ExitCode = 0) and (fPal.ReportRoot <> '') and
    (not HasAnalyzerError(['PAL ', 'Pascal Analyzer'])));

  if not fOptions.fAnalyzeFixInsight then
    lFixQuality := 'complete'
  else if fFixTxtRan and FileExists(fFixTxtPath) then
    if lFixComplete then
      lFixQuality := 'complete'
    else
      lFixQuality := 'partial'
  else
    lFixQuality := 'unavailable';
  if not fOptions.fAnalyzePal then
    lPalQuality := 'complete'
  else if lPalComplete then
    lPalQuality := 'complete'
  else
    lPalQuality := 'unavailable';

  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('schema_version', TJSONNumber.Create(2));
    lStatus := TJSONObject.Create
      .AddPair('infrastructure', IfThen(fExitCode = 0, 'complete', 'failed'))
      .AddPair('policy', 'not_evaluated');
    lRoot.AddPair('status', lStatus);
    lRoot.AddPair('subject', TJSONObject.Create
      .AddPair('kind', 'project')
      .AddPair('path', fParams.fProjectDpr)
      .AddPair('project_file', fProjectDproj));
    lRoot.AddPair('workspace', TJSONObject.Create
      .AddPair('selector', fSettings.fWorkspace.fSelector)
      .AddPair('root', fSettings.fWorkspace.fRoot)
      .AddPair('vcs', fSettings.fWorkspace.fVcs)
      .AddPair('source', fSettings.fWorkspace.fSource));

    lCompiler := TJSONObject.Create
      .AddPair('delphi', fParams.fDelphiVersion)
      .AddPair('platform', fParams.fPlatform)
      .AddPair('config', fParams.fConfig)
      .AddPair('search_path_sha256', HashArray(fParams.fUnitSearchPath));
    lRoot.AddPair('compiler', lCompiler);

    lFormats := TJSONArray.Create;
    if TReportFormat.rfText in fOptions.fAnalyzeFiFormats then
      lFormats.AddElement(TJSONString.Create('txt'));
    if TReportFormat.rfXml in fOptions.fAnalyzeFiFormats then
      lFormats.AddElement(TJSONString.Create('xml'));
    if TReportFormat.rfCsv in fOptions.fAnalyzeFiFormats then
      lFormats.AddElement(TJSONString.Create('csv'));
    lFixRuns := TJSONArray.Create;
    AddFixRun('txt', fFixTxtPath, fFixTxtRan, fFixTxtExit, fFixTxtDurationMs);
    AddFixRun('xml', fFixXmlPath, fFixXmlRan, fFixXmlExit, fFixXmlDurationMs);
    AddFixRun('csv', fFixCsvPath, fFixCsvRan, fFixCsvExit, fFixCsvDurationMs);
    lInput := String.Join('|', [String.Join(';', fParams.fDefines), HashArray(fParams.fUnitSearchPath),
      HashArray(fParams.fLibraryPath), String.Join(';', fParams.fUnitScopes), String.Join(';', fParams.fUnitAliases),
      fFixOptions.fIgnore, fFixOptions.fSettings, fFixOptions.fTimeoutSec.ToString]);
    lFixAnalyzer := TJSONObject.Create
      .AddPair('requested', TJSONBool.Create(fOptions.fAnalyzeFixInsight))
      .AddPair('status', IfThen(not fOptions.fAnalyzeFixInsight, 'not_requested',
        IfThen(lFixComplete, 'complete', 'failed')))
      .AddPair('executable', fParams.fFixInsightExe)
      .AddPair('options', TJSONObject.Create
        .AddPair('formats', lFormats)
        .AddPair('sha256', LowerCase(THashSHA2.GetHashString(lInput))))
      .AddPair('runs', lFixRuns)
      .AddPair('count_quality', lFixQuality);

    lPalRuns := TJSONArray.Create;
    if fPal.Ran then
      lPalRuns.AddElement(TJSONObject.Create
        .AddPair('exit_code', TJSONNumber.Create(fPal.ExitCode))
        .AddPair('duration_ms', TJSONNumber.Create(fPalDurationMs))
        .AddPair('parse_status', IfThen(lPalComplete, 'complete', 'unavailable'))
        .AddPair('artifacts', TJSONObject.Create
          .AddPair('stdout', 'pascal-analyzer/pascal-analyzer.stdout.log')
          .AddPair('stderr', 'pascal-analyzer/pascal-analyzer.stderr.log')
          .AddPair('log', 'pascal-analyzer/pascal-analyzer.log')));
    lInput := String.Join('|', [fPascalAnalyzer.fArgs, fPascalAnalyzer.fExcludeSearchFolders,
      fPascalAnalyzer.fExcludeFiles, fPascalAnalyzer.fTimeoutSec.ToString,
      HashArray(fParams.fDefines), HashArray(fParams.fUnitSearchPath)]);
    lPalAnalyzer := TJSONObject.Create
      .AddPair('requested', TJSONBool.Create(fOptions.fAnalyzePal))
      .AddPair('status', IfThen(not fOptions.fAnalyzePal, 'not_requested',
        IfThen(lPalComplete, 'complete', 'failed')))
      .AddPair('executable', fPascalAnalyzer.fPath)
      .AddPair('version', fPal.Version)
      .AddPair('options', TJSONObject.Create
        .AddPair('exclude_search_folders', fPascalAnalyzer.fExcludeSearchFolders)
        .AddPair('exclude_files', fPascalAnalyzer.fExcludeFiles)
        .AddPair('sha256', LowerCase(THashSHA2.GetHashString(lInput))))
      .AddPair('runs', lPalRuns)
      .AddPair('count_quality', lPalQuality);
    lAnalyzers := TJSONObject.Create
      .AddPair('fixinsight', lFixAnalyzer)
      .AddPair('pascal_analyzer', lPalAnalyzer);
    lRoot.AddPair('analyzers', lAnalyzers);

    lFixCounts := TJSONObject.Create.AddPair('quality', lFixQuality);
    if lFixQuality <> 'unavailable' then
      lFixCounts.AddPair('total', TJSONNumber.Create(fFixCounts.Total));
    lPalCounts := TJSONObject.Create.AddPair('quality', lPalQuality);
    if lPalQuality <> 'unavailable' then
    begin
      lPalCounts.AddPair('warnings', TJSONNumber.Create(fPal.Warnings));
      lPalCounts.AddPair('strong_warnings', TJSONNumber.Create(fPal.StrongWarnings));
      lPalCounts.AddPair('optimizations', TJSONNumber.Create(fPal.Optimizations));
      lPalCounts.AddPair('total', TJSONNumber.Create(fPal.Warnings + fPal.StrongWarnings + fPal.Optimizations));
    end;
    lCounts := TJSONObject.Create
      .AddPair('fixinsight', lFixCounts)
      .AddPair('pascal_analyzer', lPalCounts);
    if lFixComplete and lPalComplete and (lFixQuality = 'complete') and (lPalQuality = 'complete') then
      lCounts.AddPair('total', TJSONNumber.Create(fFixCounts.Total + fPal.Warnings + fPal.StrongWarnings +
        fPal.Optimizations));
    lRoot.AddPair('counts', lCounts);

    lConfigFiles := TJSONArray.Create;
    for lSettingsPath in fSettings.fLoadedPaths do
      lConfigFiles.AddElement(TJSONObject.Create
        .AddPair('path', lSettingsPath)
        .AddPair('sha256', HashFile(lSettingsPath)));
    lInputs := TJSONObject.Create
      .AddPair('project_sha256', HashFile(fProjectDproj))
      .AddPair('main_source_sha256', HashFile(fParams.fProjectDpr))
      .AddPair('config_manifests', lConfigFiles);
    lRoot.AddPair('inputs', lInputs);

    lPolicyValues := TJSONObject.Create
      .AddPair('gate_ownership', StringListJson(fSettings.fAnalysisPolicy.fGateOwnership))
      .AddPair('gate_metrics', StringListJson(fSettings.fAnalysisPolicy.fGateMetrics))
      .AddPair('fixinsight_ignore', StringListJson(fFixIgnoreDefaults.fWarnings))
      .AddPair('pal_ignore_rules', StringListJson(fSettings.fPascalAnalyzerIgnore.fRules))
      .AddPair('project_roots', StringListJson(fSettings.fAnalysisPolicy.fProjectRoots))
      .AddPair('third_party_roots', StringListJson(fSettings.fAnalysisPolicy.fThirdPartyRoots))
      .AddPair('exclude_path_masks', StringListJson(fReportFilter.fExcludePathMasks));
    lPolicySources := TJSONArray.Create;
    for lSettingsPath in fSettings.fAnalysisPolicy.fSources do
      lPolicySources.AddElement(TJSONString.Create(lSettingsPath));
    lPolicyOrigins := TJSONObject.Create
      .AddPair('pal_ignore_rules',
        StringListJson(fSettings.fPascalAnalyzerIgnore.fSources));
    lPolicy := TJSONObject.Create
      .AddPair('resolver', 'Dak.Settings')
      .AddPair('values', lPolicyValues)
      .AddPair('sources', lPolicySources)
      .AddPair('origins', lPolicyOrigins)
      .AddPair('sha256', fSettings.fAnalysisPolicy.fSha256)
      .AddPair('reporting_sha256', LowerCase(THashSHA2.GetHashString(
        'GateMetrics=' + fSettings.fAnalysisPolicy.fGateMetrics + #10 +
        'FixInsightIgnore=' + fFixIgnoreDefaults.fWarnings + #10 +
        'PascalAnalyzerIgnore=' + fSettings.fPascalAnalyzerIgnore.fRules + #10 +
        'ExcludePathMasks=' + fReportFilter.fExcludePathMasks)));
    lRoot.AddPair('policy', lPolicy);
    lErrors := TJSONArray.Create;
    for lInput in fErrors do
      lErrors.AddElement(TJSONString.Create(lInput));
    lRoot.AddPair('errors', lErrors);
    lArtifacts := TJSONObject.Create
      .AddPair('summary_markdown', 'summary.md')
      .AddPair('run_log', 'run.log');
    lRoot.AddPair('artifacts', lArtifacts);
    WriteLogText(TPath.Combine(fOutRoot, 'summary.json'), lRoot.Format(2));
  finally
    lRoot.Free;
  end;
end;

procedure TAnalyzeProjectRunner.WriteSummary;
begin
  if not fOptions.fAnalyzeWriteSummary then
    Exit;

  fSummaryPath := TPath.Combine(fOutRoot, 'summary.md');
  fSummaryText := BuildProjectSummary(fProjectName, fParams.fProjectDpr, fOutRoot, fFixTxtPath, fFixXmlPath,
    fFixCsvPath, fFixTxtRan, fFixXmlRan, fFixCsvRan, fFixTxtExit, fFixXmlExit, fFixCsvExit, fFixCounts, fPal,
    fErrors.ToArray);
  WriteLogText(fSummaryPath, fSummaryText);
  WriteStatusSeed;
end;

function TAnalyzeProjectRunner.Execute: Integer;
begin
  try
    if not TryOpenLog then
      Exit(fExitCode);
    if not TryPrepareParams then
      Exit(fExitCode);
    PrepareOutputTree;
    RunFixInsightReports;
    RunPascalAnalyzer;
    fFixCounts := Default(TFixInsightCounts);
    if fFixTxtRan and FileExists(fFixTxtPath) then
      CaptureFixInsightSummary(fFixTxtPath, fFixCounts);
    WriteSummary;
  finally
    fDiagnostics.WriteToStderr;
  end;
  Result := fExitCode;
end;
function RunAnalyzeProject(const aOptions: TAppOptions): Integer;
var
  lRunner: TAnalyzeProjectRunner;
begin
  lRunner := TAnalyzeProjectRunner.Create(aOptions);
  try
    Result := lRunner.Execute;
  finally
    lRunner.Free;
  end;
end;
end.
