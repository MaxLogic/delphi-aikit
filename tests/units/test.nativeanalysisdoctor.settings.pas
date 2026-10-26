unit Test.NativeAnalysisDoctor.Settings;

interface

uses
  System.JSON,
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Slow')]
  TNativeAnalysisDoctorSettingsTests = class
  private
    fRoot: string;
    fProject: string;
    fEnvironment: IInterface;
    function Preview(const aTargetArgs: string): TJSONObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure EffectiveSettingsKeepDiagnosticsSeparateFromPolicy;
    [Test]
    procedure TwoIniFilesReportScalarWinnerAndOrderedListContributors;
    [Test]
    procedure EnvironmentReplacesPalPathAndArgsWithExactOrigins;
    [TestCase('Metrics', 'GateMetrics,PAL.Metric.One,gate_metrics')]
    [TestCase('ProjectRoots', 'ProjectRoots,source,project_roots')]
    [TestCase('ThirdPartyRoots', 'ThirdPartyRoots,vendor,third_party_roots')]
    procedure ExplicitEmptyPolicyRetainsTheClearingFile(const aKey, aValue, aJsonKey: string);
    [TestCase('ProjectDefault', 'false,false')]
    [TestCase('UnitDefault', 'true,false')]
    [TestCase('ProjectRelative', 'false,true')]
    [TestCase('UnitRelative', 'true,true')]
    procedure OutputRootIsPreviewOnly(aUnitTarget, aRelativeOutput: Boolean);
  end;

implementation

uses
  System.Hash, System.IOUtils, System.SysUtils,
  AutoFree,
  Test.Support;

procedure AssertStrings(const aObject: TJSONObject; const aKey: string; const aExpected: array of string);
var
  i: Integer;
  lItems: TJSONArray;
begin
  RequireJsonArrayKey(aObject, aKey, lItems);
  Assert.AreEqual<Integer>(Length(aExpected), lItems.Count, aKey);
  for i := 0 to High(aExpected) do
    Assert.AreEqual(aExpected[i], lItems.Items[i].Value, aKey + '[' + IntToStr(i) + ']');
end;

procedure TNativeAnalysisDoctorSettingsTests.Setup;
begin
  fRoot := UniqueTempPath('doctor-settings');
  TDirectory.CreateDirectory(fRoot);
  fProject := TPath.Combine(fRoot, 'Preview.dproj');
  TFile.WriteAllText(fProject, '<Project/>', TEncoding.ASCII);
  fEnvironment := SetScopedEnvironmentVariables([
    'DAK_DOCTOR_RUN', '', 'PA_PATH', '', 'PA_ARGS', '', 'DAK_OUT', '', 'DAK_WORKSPACE_ROOT', '']);
end;

procedure TNativeAnalysisDoctorSettingsTests.TearDown;
begin
  fEnvironment := nil;
  DeleteTempPath(fRoot);
end;

function TNativeAnalysisDoctorSettingsTests.Preview(const aTargetArgs: string): TJSONObject;
var
  lExePath: string;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
begin
  lExePath := ResolverExePath;
  Assert.IsTrue(TFile.Exists(lExePath), 'Expected coordinator-provided DAK candidate: ' + lExePath);
  lLog := TPath.Combine(fRoot, 'doctor.log');
  Assert.IsTrue(RunCommandProcess(lExePath, 'analyze-doctor ' + aTargetArgs +
    ' --workspace-root ' + QuoteArg(fRoot) + ' --run-checks false --json', fRoot, lLog, lExitCode));
  lOutput := ReadUtf8TextFile(lLog);
  Assert.AreEqual<Cardinal>(0, lExitCode, lOutput);
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(fRoot, '.dak')), 'Preview must not create workspace state');
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(TPath.GetDirectoryName(fProject), '.dak')),
    'Preview must not create project state');
  Result := ParseJsonObject(lOutput, 'Doctor settings preview');
end;

procedure TNativeAnalysisDoctorSettingsTests.EffectiveSettingsKeepDiagnosticsSeparateFromPolicy;
var
  g: TGarbos;
  lConfig: string;
  lDiagnostics: TJSONObject;
  lDocument: TJSONObject;
  lOrigins: TJSONObject;
  lPolicy: TJSONObject;
  lResolved: TJSONObject;
  lSettings: TJSONObject;
  lSources: TJSONObject;
  lSourceRoot: string;
  lVendorRoot: string;
begin
  lConfig := TPath.Combine(fRoot, 'dak.ini');
  lSourceRoot := TPath.Combine(fRoot, 'source');
  lVendorRoot := TPath.Combine(fRoot, 'vendor');
  TFile.WriteAllText(lConfig,
    '[FixInsightCL]' + sLineBreak + 'Silent=false' + sLineBreak + 'Settings=custom.ficfg' + sLineBreak +
    '[ReportFilter]' + sLineBreak + 'ExcludePathMasks=generated;vendor' + sLineBreak +
    '[FixInsightIgnore]' + sLineBreak + 'Warnings=W101;W102' + sLineBreak +
    '[PascalAnalyzer]' + sLineBreak + 'Path=missing-pal.exe' + sLineBreak + 'Args=/CD12W64' + sLineBreak +
    'ExcludeSearchFolders=cache;generated' + sLineBreak + 'ExcludeFiles=Old.pas;Other.pas' + sLineBreak +
    '[PascalAnalyzerIgnore]' + sLineBreak + 'Rules=PAL.Warn.One;PAL.Warn.Two' + sLineBreak +
    '[AnalysisPolicy]' + sLineBreak + 'GateOwnership=project;third_party' + sLineBreak +
    'GateMetrics=PAL.Metric.One' + sLineBreak + 'ProjectRoots=source' + sLineBreak +
    'ThirdPartyRoots=vendor' + sLineBreak +
    '[Diagnostics]' + sLineBreak + 'IgnoreUnknownMacros=CUSTOM;OPTIONAL' + sLineBreak +
    'IgnoreMissingPaths=missing;optional', TEncoding.UTF8);
  GC(lDocument, Preview('--project ' + QuoteArg(fProject)), g);
  RequireJsonObjectKey(lDocument, 'settings', lSettings);
  AssertStrings(lSettings, 'files', [lConfig]);
  RequireJsonObjectKey(lSettings, 'resolved', lResolved);
  Assert.IsFalse(lResolved.GetValue<Boolean>('fixinsight.silent'));
  Assert.AreEqual('custom.ficfg', lResolved.GetValue<string>('fixinsight.settings'));
  Assert.AreEqual('generated;vendor', lResolved.GetValue<string>('report_filter.exclude_path_masks'));
  Assert.AreEqual('W101;W102', lResolved.GetValue<string>('fixinsight_ignore.warnings'));
  Assert.AreEqual('missing-pal.exe', lResolved.GetValue<string>('pascal_analyzer.path'));
  Assert.AreEqual('/CD12W64', lResolved.GetValue<string>('pascal_analyzer.args'));
  Assert.AreEqual('cache;generated', lResolved.GetValue<string>('pascal_analyzer.exclude_search_folders'));
  Assert.AreEqual('Old.pas;Other.pas', lResolved.GetValue<string>('pascal_analyzer.exclude_files'));
  RequireJsonObjectKey(lResolved, 'diagnostics', lDiagnostics);
  Assert.AreEqual('CUSTOM;OPTIONAL', lDiagnostics.GetValue<string>('ignore_unknown_macros'));
  Assert.AreEqual('missing;optional', lDiagnostics.GetValue<string>('ignore_missing_paths'));
  RequireJsonObjectKey(lResolved, 'analysis_policy', lPolicy);
  Assert.IsNull(lPolicy.Values['ignore_unknown_macros']);
  Assert.IsNull(lPolicy.Values['ignore_missing_paths']);
  AssertStrings(lPolicy, 'gate_ownership', ['project', 'third_party']);
  AssertStrings(lPolicy, 'gate_metrics', ['PAL.Metric.One']);
  AssertStrings(lPolicy, 'project_roots', [lSourceRoot]);
  AssertStrings(lPolicy, 'third_party_roots', [lVendorRoot]);
  AssertStrings(lPolicy, 'pal_ignore_rules', ['PAL.Warn.One', 'PAL.Warn.Two']);
  AssertStrings(lPolicy, 'sources', [lConfig]);
  RequireJsonObjectKey(lPolicy, 'origins', lOrigins);
  AssertStrings(lOrigins, 'pal_ignore_rules', [lConfig]);
  Assert.AreEqual(LowerCase(THashSHA2.GetHashString(
    'GateOwnership=project;third_party' + #10 + 'GateMetrics=PAL.Metric.One' + #10 +
    'ProjectRoots=' + LowerCase(lSourceRoot) + #10 + 'ThirdPartyRoots=' + LowerCase(lVendorRoot))),
    lPolicy.GetValue<string>('sha256'));
  RequireJsonObjectKey(lSettings, 'origins', lSources);
  AssertStrings(lSources, 'FixInsightCL.Silent', [lConfig]);
  AssertStrings(lSources, 'Diagnostics.IgnoreUnknownMacros', [lConfig]);
  AssertStrings(lSources, 'Diagnostics.IgnoreMissingPaths', [lConfig]);
end;

procedure TNativeAnalysisDoctorSettingsTests.TwoIniFilesReportScalarWinnerAndOrderedListContributors;
var
  g: TGarbos;
  lChild: string;
  lChildConfig: string;
  lDocument: TJSONObject;
  lOrigins: TJSONObject;
  lResolved: TJSONObject;
  lRootConfig: string;
  lSettings: TJSONObject;
begin
  lChild := TPath.Combine(fRoot, 'child');
  TDirectory.CreateDirectory(lChild);
  fProject := TPath.Combine(lChild, 'Preview.dproj');
  TFile.WriteAllText(fProject, '<Project/>', TEncoding.ASCII);
  lRootConfig := TPath.Combine(fRoot, 'dak.ini');
  lChildConfig := TPath.Combine(lChild, 'dak.ini');
  TFile.WriteAllText(lRootConfig,
    '[FixInsightCL]' + sLineBreak + 'Silent=true' + sLineBreak + 'Settings=root.ficfg' + sLineBreak +
    '[ReportFilter]' + sLineBreak + 'ExcludePathMasks=vendor;shared' + sLineBreak +
    '[FixInsightIgnore]' + sLineBreak + 'Warnings=W101;W102', TEncoding.UTF8);
  TFile.WriteAllText(lChildConfig,
    '[FixInsightCL]' + sLineBreak + 'Silent=false' + sLineBreak + 'Settings=child.ficfg' + sLineBreak +
    '[ReportFilter]' + sLineBreak + 'ExcludePathMasks=SHARED;generated' + sLineBreak +
    '[FixInsightIgnore]' + sLineBreak + 'Warnings=w102;W103', TEncoding.UTF8);
  GC(lDocument, Preview('--project ' + QuoteArg(fProject)), g);
  RequireJsonObjectKey(lDocument, 'settings', lSettings);
  AssertStrings(lSettings, 'files', [lRootConfig, lChildConfig]);
  RequireJsonObjectKey(lSettings, 'resolved', lResolved);
  Assert.IsFalse(lResolved.GetValue<Boolean>('fixinsight.silent'));
  Assert.AreEqual('child.ficfg', lResolved.GetValue<string>('fixinsight.settings'));
  Assert.AreEqual('vendor;shared;generated', lResolved.GetValue<string>('report_filter.exclude_path_masks'));
  Assert.AreEqual('W101;W102;W103', lResolved.GetValue<string>('fixinsight_ignore.warnings'));
  RequireJsonObjectKey(lSettings, 'origins', lOrigins);
  AssertStrings(lOrigins, 'FixInsightCL.Silent', [lChildConfig]);
  AssertStrings(lOrigins, 'FixInsightCL.Settings', [lChildConfig]);
  AssertStrings(lOrigins, 'ReportFilter.ExcludePathMasks', [lRootConfig, lChildConfig]);
  AssertStrings(lOrigins, 'FixInsightIgnore.Warnings', [lRootConfig, lChildConfig]);
end;

procedure TNativeAnalysisDoctorSettingsTests.EnvironmentReplacesPalPathAndArgsWithExactOrigins;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lOrigins: TJSONObject;
  lPal: TJSONObject;
  lResolved: TJSONObject;
  lSettings: TJSONObject;
begin
  TFile.WriteAllText(TPath.Combine(fRoot, 'dak.ini'), '[PascalAnalyzer]' + sLineBreak +
    'Path=ini-pal.exe' + sLineBreak + 'Args=/Q', TEncoding.UTF8);
  lEnvironment := SetScopedEnvironmentVariables(['PA_PATH', 'environment-pal.exe', 'PA_ARGS', '/CD12W64']);
  try
    GC(lDocument, Preview('--project ' + QuoteArg(fProject)), g);
    RequireJsonObjectKey(lDocument, 'settings', lSettings);
    RequireJsonObjectKey(lSettings, 'resolved', lResolved);
    RequireJsonObjectKey(lResolved, 'pascal_analyzer', lPal);
    Assert.AreEqual('environment-pal.exe', lPal.GetValue<string>('path'));
    Assert.AreEqual('/CD12W64', lPal.GetValue<string>('args'));
    RequireJsonObjectKey(lSettings, 'origins', lOrigins);
    AssertStrings(lOrigins, 'PascalAnalyzer.Path', ['PA_PATH environment variable']);
    AssertStrings(lOrigins, 'PascalAnalyzer.Args', ['PA_ARGS environment variable']);
  finally
    lEnvironment := nil;
  end;
end;

procedure TNativeAnalysisDoctorSettingsTests.ExplicitEmptyPolicyRetainsTheClearingFile(
  const aKey, aValue, aJsonKey: string);
var
  g: TGarbos;
  lChild: string;
  lChildConfig: string;
  lDocument: TJSONObject;
  lOrigins: TJSONObject;
  lPolicy: TJSONObject;
  lSettings: TJSONObject;
begin
  lChild := TPath.Combine(fRoot, 'child');
  TDirectory.CreateDirectory(lChild);
  fProject := TPath.Combine(lChild, 'Preview.dproj');
  TFile.WriteAllText(fProject, '<Project/>', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(fRoot, 'dak.ini'),
    '[AnalysisPolicy]' + sLineBreak + aKey + '=' + aValue, TEncoding.UTF8);
  lChildConfig := TPath.Combine(lChild, 'dak.ini');
  TFile.WriteAllText(lChildConfig, '[AnalysisPolicy]' + sLineBreak + aKey + '=', TEncoding.UTF8);
  GC(lDocument, Preview('--project ' + QuoteArg(fProject)), g);
  RequireJsonObjectKey(lDocument, 'settings', lSettings);
  lPolicy := lSettings.GetValue<TJSONObject>('resolved.analysis_policy');
  AssertStrings(lPolicy, aJsonKey, []);
  RequireJsonObjectKey(lSettings, 'origins', lOrigins);
  AssertStrings(lOrigins, 'AnalysisPolicy.' + aKey, [lChildConfig]);
end;

procedure TNativeAnalysisDoctorSettingsTests.OutputRootIsPreviewOnly(aUnitTarget, aRelativeOutput: Boolean);
var
  g: TGarbos;
  lArguments: string;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lExpected: string;
  lSubject: TJSONObject;
  lTargetDir: string;
  lUnit: string;
begin
  lTargetDir := TPath.Combine(fRoot, 'subject');
  TDirectory.CreateDirectory(lTargetDir);
  fProject := TPath.Combine(lTargetDir, 'Preview.dproj');
  TFile.WriteAllText(fProject, '<Project/>', TEncoding.ASCII);
  if aUnitTarget then
  begin
    lUnit := TPath.Combine(lTargetDir, 'PreviewUnit.pas');
    TFile.WriteAllText(lUnit, 'unit PreviewUnit; interface implementation end.', TEncoding.ASCII);
    lArguments := '--unit ' + QuoteArg(lUnit);
    lExpected := TPath.Combine(lTargetDir, '.dak\_unit\PreviewUnit');
  end else begin
    lArguments := '--project ' + QuoteArg(fProject);
    lExpected := TPath.Combine(lTargetDir, '.dak\Preview');
  end;
  if aRelativeOutput then
  begin
    lEnvironment := SetScopedEnvironmentVariables(['DAK_OUT', 'relative-output']);
    lExpected := TPath.Combine(fRoot, 'relative-output');
  end;
  try
    GC(lDocument, Preview(lArguments), g);
    RequireJsonObjectKey(lDocument, 'subject', lSubject);
    RequireJsonStringKey(lSubject, 'output_root');
    Assert.AreEqual(lExpected, lSubject.GetValue<string>('output_root'));
    Assert.IsFalse(TDirectory.Exists(lExpected), 'Output preview must compute a path without creating it');
  finally
    lEnvironment := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisDoctorSettingsTests);

end.
