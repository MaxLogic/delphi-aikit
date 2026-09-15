unit Dak.Analysis.Doctor;

interface

uses
  Dak.Types;

function RunAnalyzeDoctorCommand(const aOptions: TAppOptions): Integer;
function RunAnalyzeDoctorError(const aOptions: TAppOptions; const aError: string): Integer;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Dak.Analyze.Common, Dak.CommandOutput, Dak.ExitCodes, Dak.FixInsight, Dak.PascalAnalyzer.Help,
  Dak.PascalAnalyzerRunner, Dak.Registry, Dak.Settings, Dak.Utils;

function CreateDoctorDocument(const aOptions: TAppOptions): TJSONObject;
var
  lChecks: Boolean;
begin
  lChecks := Trim(GetEnvironmentVariable('DAK_DOCTOR_RUN')) <> '';
  if aOptions.fHasDoctorRunChecks then
    lChecks := aOptions.fDoctorRunChecks;
  Result := TJSONObject.Create;
  Result.AddPair('schema_version', TJSONNumber.Create(1));
  if lChecks then
    Result.AddPair('mode', 'checks')
  else
    Result.AddPair('mode', 'preview');
  Result.AddPair('subject', TJSONNull.Create);
  Result.AddPair('settings', TJSONObject.Create);
  Result.AddPair('checks', TJSONArray.Create);
  Result.AddPair('diagnostics', TJSONArray.Create);
end;

function AddDoctorCheck(const aDocument: TJSONObject; const aName: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  aDocument.GetValue<TJSONArray>('checks').AddElement(Result);
  Result.AddPair('name', aName);
end;

function CheckPal(const aOptions: TAppOptions; const aSettings: TPascalAnalyzerDefaults;
  const aDocument: TJSONObject): Integer;
const
  cDoctorHelpTimeoutSec = 15;
var
  lCheck: TJSONObject;
  lDelphiKey: string;
  lError: string;
  lExitCode: Cardinal;
  lFlag: string;
  lFlags: TJSONArray;
  lHelp: TPalHelpInfo;
  lHelpText: string;
  lPath: string;
  lProbeSucceeded: Boolean;
  lTimedOut: Boolean;
  lTimeoutSec: Integer;
begin
  Result := 3;
  lCheck := AddDoctorCheck(aDocument, 'pal_path');
  if not TryResolvePalCmdExe(aSettings.fPath, lPath, lError) then
  begin
    lCheck.AddPair('status', 'unavailable');
    aDocument.GetValue<TJSONArray>('diagnostics').Add(lError);
    Exit;
  end;
  lCheck.AddPair('status', 'available');
  lCheck.AddPair('path', lPath);

  // Capture once. Doctor requires successful help; analysis retains its older fallback policy.
  lTimeoutSec := aSettings.fTimeoutSec;
  if lTimeoutSec <= 0 then
    lTimeoutSec := cDoctorHelpTimeoutSec;
  lProbeSucceeded := TryCapturePalCmdHelp(lPath, lTimeoutSec, lHelpText,
    lExitCode, lTimedOut, lError);
  lHelp := ParsePalHelp(lHelpText);
  lCheck := AddDoctorCheck(aDocument, 'pal_help');
  lCheck.AddPair('timeout_seconds', TJSONNumber.Create(lTimeoutSec));
  lCheck.AddPair('exit_code', TJSONNumber.Create(lExitCode));
  lCheck.AddPair('timed_out', TJSONBool.Create(lTimedOut));
  lCheck.AddPair('version', lHelp.fVersion);
  lCheck.AddPair('architecture', lHelp.fArchitecture);
  lCheck.AddPair('help_available', TJSONBool.Create(lHelp.fHelpAvailable));
  lFlags := TJSONArray.Create;
  lCheck.AddPair('supported_flags', lFlags);
  for lFlag in lHelp.fSupportedFlags do
    lFlags.Add(lFlag);
  if not lProbeSucceeded or (lExitCode <> 0) or not lHelp.fHelpAvailable then
  begin
    lCheck.AddPair('status', 'unavailable');
    if lError = '' then
      lError := Format('PALCMD help failed (exit=%d).', [lExitCode]);
    aDocument.GetValue<TJSONArray>('diagnostics').Add(lError);
    Exit;
  end;
  lCheck.AddPair('status', 'available');
  if aOptions.fDelphiVersion <> '' then
  begin
    lCheck := AddDoctorCheck(aDocument, 'pal_target');
    lCheck.AddPair('bds_version', aOptions.fDelphiVersion);
    lCheck.AddPair('platform', aOptions.fPlatform);
    if not TryResolvePalTargetFlag(aOptions.fDelphiVersion, aOptions.fPlatform,
      lDelphiKey, lFlag, lError) then
    begin
      lCheck.AddPair('status', 'unsupported');
      aDocument.GetValue<TJSONArray>('diagnostics').Add(lError);
      Exit;
    end;
    lCheck.AddPair('delphi', lDelphiKey);
    lCheck.AddPair('flag', lFlag);
    if not PalHelpSupportsTarget(lHelp, lFlag) then
    begin
      lCheck.AddPair('status', 'unsupported');
      aDocument.GetValue<TJSONArray>('diagnostics').Add(
        'Requested Delphi/platform target is not supported by PALCMD help.');
      Exit;
    end;
    lCheck.AddPair('status', 'supported');
  end;
  Result := cExitSuccess;
end;

procedure CheckOptionalTools(const aOptions: TAppOptions; const aSettings: TDakSettings;
  const aDocument: TJSONObject);
var
  lAvailable: Boolean;
  lCheck: TJSONObject;
  lEnvironment: TDictionary<string, string>;
  lError: string;
  lLibraryPath: string;
  lPath: string;
  lSource: TPropertySource;
begin
  lCheck := AddDoctorCheck(aDocument, 'fixinsight');
  if aSettings.fFixInsight.fExePath <> '' then
  begin
    lPath := ResolveExePathFromConfiguredValue(aSettings.fFixInsight.fExePath, 'FixInsightCL.exe', '');
    lAvailable := TFile.Exists(lPath);
    lCheck.AddPair('source', 'settings');
  end else begin
    lAvailable := TryResolveFixInsightExe(nil, lPath);
    lCheck.AddPair('source', 'PATH/registry discovery');
  end;
  lCheck.AddPair('path', lPath);
  if lAvailable then
    lCheck.AddPair('status', 'available')
  else
    lCheck.AddPair('status', 'unavailable');

  lCheck := AddDoctorCheck(aDocument, 'compiler');
  // This is configuration discovery, not a compiler invocation or build validation.
  lCheck.AddPair('kind', 'configuration');
  lCheck.AddPair('bds_version', aOptions.fDelphiVersion);
  lCheck.AddPair('platform', aOptions.fPlatform);
  if aOptions.fDelphiVersion = '' then
  begin
    lCheck.AddPair('status', 'not_requested');
    Exit;
  end;
  lEnvironment := nil;
  try
    if not TryReadIdeConfig(aOptions.fDelphiVersion, aOptions.fPlatform, '', lEnvironment,
      lLibraryPath, lSource, nil, lError) then
    begin
      lCheck.AddPair('status', 'unavailable');
      lCheck.AddPair('error', lError);
      Exit;
    end;
    lCheck.AddPair('status', 'available');
    lCheck.AddPair('library_path', lLibraryPath);
    if lSource = TPropertySource.psEnvOptions then
      lCheck.AddPair('source', 'env_options')
    else
      lCheck.AddPair('source', 'registry');
  finally
    lEnvironment.Free;
  end;
end;

procedure AddEnvironmentPreview(const aSettings: TJSONObject);
const
  cNames: array[0..18] of string = ('DAK_DELPHI', 'DAK_PLATFORM', 'DAK_CONFIG', 'DAK_FI_FORMATS',
    'DAK_FIXINSIGHT', 'DAK_PASCAL_ANALYZER', 'DAK_PAL', 'PA_PATH', 'DAK_EXCLUDE_PATH_MASKS',
    'DAK_FI_IGNORE_RULES', 'DAK_IGNORE_WARNING_IDS', 'DAK_PAL_IGNORE_RULES', 'DAK_OUT',
    'DAK_CLEAN', 'DAK_WRITE_SUMMARY', 'DAK_BASELINE', 'DAK_UPDATE_BASELINE', 'DAK_GATE', 'DAK_CI');
var
  lEnvironment: TJSONObject;
  lName: string;
  lValue: string;
begin
  lEnvironment := TJSONObject.Create;
  aSettings.AddPair('environment', lEnvironment);
  for lName in cNames do
  begin
    lValue := Trim(GetEnvironmentVariable(lName));
    if lValue <> '' then
      lEnvironment.AddPair(lName, lValue);
  end;
end;

function JsonStrings(const aValues: array of string): TJSONArray;
var
  lValue: string;
begin
  Result := TJSONArray.Create;
  for lValue in aValues do
    if Trim(lValue) <> '' then
      Result.Add(Trim(lValue));
end;

function JsonList(const aValue: string): TJSONArray;
begin
  Result := JsonStrings(aValue.Split([';']));
end;

procedure AddResolvedSettings(const aDocument: TJSONObject; const aSettings: TDakSettings);
var
  lOrigin: TSettingsValueOrigin;
  lOrigins: TJSONObject;
  lPolicy: TJSONObject;
  lResolved: TJSONObject;
begin
  lResolved := TJSONObject.Create;
  aDocument.AddPair('resolved', lResolved);
  lResolved.AddPair('fixinsight', TJSONObject.Create
    .AddPair('silent', TJSONBool.Create(aSettings.fFixInsight.fSilent))
    .AddPair('settings', aSettings.fFixInsight.fSettings));
  lResolved.AddPair('report_filter', TJSONObject.Create
    .AddPair('exclude_path_masks', aSettings.fReportFilter.fExcludePathMasks));
  lResolved.AddPair('fixinsight_ignore', TJSONObject.Create
    .AddPair('warnings', aSettings.fFixInsightIgnore.fWarnings));
  lResolved.AddPair('pascal_analyzer', TJSONObject.Create
    .AddPair('path', aSettings.fPascalAnalyzer.fPath)
    .AddPair('args', aSettings.fPascalAnalyzer.fArgs)
    .AddPair('exclude_search_folders', aSettings.fPascalAnalyzer.fExcludeSearchFolders)
    .AddPair('exclude_files', aSettings.fPascalAnalyzer.fExcludeFiles));
  lResolved.AddPair('diagnostics', TJSONObject.Create
    .AddPair('ignore_unknown_macros', aSettings.fIgnoreUnknownMacros)
    .AddPair('ignore_missing_paths', aSettings.fIgnoreMissingPaths));
  lPolicy := TJSONObject.Create
    .AddPair('gate_ownership', JsonList(aSettings.fAnalysisPolicy.fGateOwnership))
    .AddPair('gate_metrics', JsonList(aSettings.fAnalysisPolicy.fGateMetrics))
    .AddPair('project_roots', JsonList(aSettings.fAnalysisPolicy.fProjectRoots))
    .AddPair('third_party_roots', JsonList(aSettings.fAnalysisPolicy.fThirdPartyRoots))
    .AddPair('pal_ignore_rules', JsonList(aSettings.fPascalAnalyzerIgnore.fRules))
    .AddPair('sources', JsonStrings(aSettings.fAnalysisPolicy.fSources))
    .AddPair('origins', TJSONObject.Create
      .AddPair('pal_ignore_rules', JsonList(aSettings.fPascalAnalyzerIgnore.fSources)))
    .AddPair('sha256', aSettings.fAnalysisPolicy.fSha256);
  lResolved.AddPair('analysis_policy', lPolicy);
  lOrigins := TJSONObject.Create;
  aDocument.AddPair('origins', lOrigins);
  for lOrigin in aSettings.fOrigins do
    lOrigins.AddPair(lOrigin.fName, JsonStrings(lOrigin.fSources));
end;

function PopulateDoctorDocument(const aOptions: TAppOptions; const aDocument: TJSONObject): Integer;
var
  lError: string;
  lFiles: TJSONArray;
  lOutputRoot: string;
  lPath: string;
  lSettings: TDakSettings;
  lSettingsJson: TJSONObject;
  lSubject: string;
  lSubjectJson: TJSONObject;
  lWorkspace: TJSONObject;
begin
  Result := cExitInvalidArgs;
  lSubject := aOptions.fDprojPath;
  if aOptions.fUnitPath <> '' then
    lSubject := aOptions.fUnitPath;
  if lSubject <> '' then
  begin
    if not TryResolveAbsolutePath(lSubject, lPath, lError) then
    begin
      aDocument.GetValue<TJSONArray>('diagnostics').Add(lError);
      Exit;
    end;
    lSubject := lPath;
    lSubjectJson := TJSONObject.Create;
    lSubjectJson.AddPair('path', lSubject);
    lSubjectJson.AddPair('exists', TJSONBool.Create(TFile.Exists(lSubject)));
    aDocument.RemovePair('subject').Free;
    aDocument.AddPair('subject', lSubjectJson);
    lOutputRoot := Trim(GetEnvironmentVariable('DAK_OUT'));
    if lOutputRoot <> '' then
    begin
      if not TryResolveAbsolutePath(lOutputRoot, lPath, lError) then
      begin
        aDocument.GetValue<TJSONArray>('diagnostics').Add(lError);
        Exit;
      end;
      lOutputRoot := lPath;
    end;
    if aOptions.fUnitPath <> '' then
      lOutputRoot := BuildUnitOutputRoot(lOutputRoot, lSubject, TPath.GetFileNameWithoutExtension(lSubject))
    else
      lOutputRoot := BuildOutputRoot(lOutputRoot, lSubject, TPath.GetFileNameWithoutExtension(lSubject));
    lSubjectJson.AddPair('output_root', lOutputRoot);
  end;
  if not LoadDakSettings(nil, lSubject, nil, aOptions.fWorkspaceRoot, lSettings) then
  begin
    aDocument.GetValue<TJSONArray>('diagnostics').Add(lSettings.fError);
    Exit;
  end;
  ApplyAnalysisSettingsOverrides(aOptions, lSettings);
  if not TryValidatePalExtraArgs(lSettings.fPascalAnalyzer, lError) then
  begin
    aDocument.GetValue<TJSONArray>('diagnostics').Add(lError);
    Exit;
  end;
  lSettingsJson := aDocument.GetValue<TJSONObject>('settings');
  lFiles := TJSONArray.Create;
  lSettingsJson.AddPair('files', lFiles);
  for lPath in lSettings.fLoadedPaths do
    lFiles.Add(lPath);
  lWorkspace := TJSONObject.Create;
  lSettingsJson.AddPair('workspace', lWorkspace);
  lWorkspace.AddPair('root', lSettings.fWorkspace.fRoot);
  lWorkspace.AddPair('selector', lSettings.fWorkspace.fSelector);
  lWorkspace.AddPair('vcs', lSettings.fWorkspace.fVcs);
  lWorkspace.AddPair('source', lSettings.fWorkspace.fSource);
  AddResolvedSettings(lSettingsJson, lSettings);
  AddEnvironmentPreview(lSettingsJson);
  Result := cExitSuccess;
  if aDocument.GetValue<string>('mode') <> 'checks' then
    Exit;
  CheckOptionalTools(aOptions, lSettings, aDocument);
  Result := CheckPal(aOptions, lSettings.fPascalAnalyzer, aDocument);
end;

procedure AppendHumanValue(const aText: TStringBuilder; const aPath: string; const aValue: TJSONValue);
var
  i: Integer;
  lPair: TJSONPair;
begin
  if aValue is TJSONObject then
  begin
    for lPair in TJSONObject(aValue) do
      AppendHumanValue(aText, aPath + '.' + lPair.JsonString.Value, lPair.JsonValue);
  end else if aValue is TJSONArray then
  begin
    if TJSONArray(aValue).Count = 0 then
      aText.AppendLine(aPath + ': []');
    for i := 0 to TJSONArray(aValue).Count - 1 do
      AppendHumanValue(aText, aPath + '[' + IntToStr(i + 1) + ']', TJSONArray(aValue).Items[i]);
  end else if aValue is TJSONNull then
    aText.AppendLine(aPath + ': <none>')
  else
    aText.AppendLine(aPath + ': ' + aValue.Value);
end;

function WriteDoctorDocument(const aOptions: TAppOptions; const aDocument: TJSONObject;
  aExitCode: Integer): Integer;
var
  g: TGarbos;
  lBuilder: TStringBuilder;
  lError: string;
  lPair: TJSONPair;
  lText: string;
begin
  Result := aExitCode;
  aDocument.AddPair('exit_code', TJSONNumber.Create(Result));
  if aOptions.fDoctorJson then
    lText := aDocument.ToJSON
  else
  begin
    GC(lBuilder, TStringBuilder.Create, g);
    lBuilder.AppendLine('Delphi static analysis doctor');
    for lPair in aDocument do
      if lPair.JsonString.Value <> 'schema_version' then
        AppendHumanValue(lBuilder, lPair.JsonString.Value, lPair.JsonValue);
    lText := lBuilder.ToString;
  end;
  if not WriteCommandOutput(lText, '', TCommandOutputPolicy.copStdoutWhenNoPathOrDash,
    True, False, False, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Result := cExitEnvironmentError;
  end;
end;

function RunAnalyzeDoctorCommand(const aOptions: TAppOptions): Integer;
var
  g: TGarbos;
  lDocument: TJSONObject;
begin
  GC(lDocument, CreateDoctorDocument(aOptions), g);
  Result := PopulateDoctorDocument(aOptions, lDocument);
  Result := WriteDoctorDocument(aOptions, lDocument, Result);
end;

function RunAnalyzeDoctorError(const aOptions: TAppOptions; const aError: string): Integer;
var
  g: TGarbos;
  lDocument: TJSONObject;
begin
  GC(lDocument, CreateDoctorDocument(aOptions), g);
  lDocument.GetValue<TJSONArray>('diagnostics').Add(aError);
  Result := WriteDoctorDocument(aOptions, lDocument, cExitInvalidArgs);
end;

end.
