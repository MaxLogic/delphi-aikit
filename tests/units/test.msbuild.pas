unit Test.MsBuild;

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  Xml.omnixmldom, Xml.xmldom,
  DelphiSemantics.Api,
  Dak.Diagnostics, Dak.MsBuild, Dak.Project, Dak.RadStudio.Locator, Dak.Types,
  Test.Support;

type
  [TestFixture]
  TMsBuildTests = class
  private
    procedure AssertConditionAccepted(const aCondition: string);
    procedure AssertConditionSetsMainSource(const aCondition: string);
    procedure AssertConditionRejected(const aCondition: string);
  public
    [Test]
    procedure AcceptsSimpleValidCondition;
    [Test]
    procedure AcceptsConditionWithoutWhitespaceAroundOr;
    [Test]
    procedure AcceptsComparisonWithWhitespaceAroundNotEqualOperator;
    [Test]
    procedure AcceptsExistsConditionForRelativeImportPath;
    [Test]
    procedure AcceptsNegatedExistsConditionForMissingPath;
    [Test]
    procedure AcceptsNegatedHasTrailingSlashCondition;
    [Test]
    procedure AcceptsHasTrailingSlashConditionWhenPathAlreadyEndsWithSlash;
    [Test]
    procedure AcceptsUnquotedHasTrailingSlashArgumentWithSpaces;
    [Test]
    procedure RejectsTrailingUnknownTokenInCondition;
    [Test]
    procedure RejectsTrailingInvalidOperatorInCondition;
    [Test]
    procedure RejectsUnterminatedQuotedLiteralInCondition;
    [Test]
    procedure EvaluatesImportedPropertyGroupsWhenImportConditionMatches;
    [Test]
    procedure PropertyValueWithQuotedEmptyLiteralDoesNotBreakLaterCondition;
    [Test]
    procedure SelfReferenceFallsBackToEmptyWhenPropertyWasUndefined;
    [Test]
    procedure ProjectSourceLookupExposesStableMetadataForSemanticConsumers;
    [Test]
    procedure ProjectParamsUseRequestedPlatformWhenProjectSetsPlatform;
    [Test]
    procedure DegradedProjectAnalysisContextKeepsProjectDefines;
    [Test]
    procedure StrictProjectAnalysisContextFailsOnDegradedContext;
    [Test]
    procedure ProjectAnalysisCommandCallersChooseExplicitContextPolicy;
    [Test]
    procedure ProjectAnalysisContextDelegatesSemanticAuthority;
    [Test]
    procedure ResolveRunnerDelegatesProjectFactsToSemanticContext;
    [Test]
    procedure ProjectContextParamsPreserveResolveFactsAndNormalizeLibraryPaths;
    [Test]
    procedure ProjectAnalysisContextExposesReadOnlyProperties;
    [Test]
    procedure ProjectAnalysisContextMatchesSemanticProjectContext;
    [Test]
    procedure RadStudioLocatorConsolidatesInstallDiscovery;
    [Test]
    procedure RadStudioLocatorPreservesDiscoveryPrecedence;
  end;

implementation

function ArrayText(const aItems: TArray<string>): string;
begin
  Result := String.Join(';', aItems);
end;

procedure BuildConditionProject(const aCondition: string; out aProjectPath: string);
var
  lRoot: string;
  lProjectXml: TStringBuilder;
begin
  lRoot := TPath.Combine(TempRoot, 'msbuild-conditions');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  aProjectPath := TPath.Combine(lRoot, 'ConditionCheck.dproj');
  lProjectXml := TStringBuilder.Create;
  try
    lProjectXml.AppendLine('<Project>');
    lProjectXml.AppendLine('  <PropertyGroup Condition="' + aCondition + '">');
    lProjectXml.AppendLine('    <MainSource>ConditionCheck.dpr</MainSource>');
    lProjectXml.AppendLine('  </PropertyGroup>');
    lProjectXml.AppendLine('</Project>');
    TFile.WriteAllText(aProjectPath, lProjectXml.ToString, TEncoding.UTF8);
  finally
    lProjectXml.Free;
  end;
end;

procedure BuildPropertyProject(const aPropertyName: string; const aPropertyValue: string; out aProjectPath: string);
var
  lRoot: string;
  lProjectXml: TStringBuilder;
begin
  lRoot := TPath.Combine(TempRoot, 'msbuild-properties');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  aProjectPath := TPath.Combine(lRoot, 'PropertyCheck.dproj');
  lProjectXml := TStringBuilder.Create;
  try
    lProjectXml.AppendLine('<Project>');
    lProjectXml.AppendLine('  <PropertyGroup>');
    lProjectXml.AppendLine('    <' + aPropertyName + '>' + aPropertyValue + '</' + aPropertyName + '>');
    lProjectXml.AppendLine('  </PropertyGroup>');
    lProjectXml.AppendLine('</Project>');
    TFile.WriteAllText(aProjectPath, lProjectXml.ToString, TEncoding.UTF8);
  finally
    lProjectXml.Free;
  end;
end;

procedure BuildImportProject(out aProjectPath: string; out aImportedPropsPath: string);
var
  lProjectXml: TStringBuilder;
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'msbuild-imports');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  aProjectPath := TPath.Combine(lRoot, 'ImportCheck.dproj');
  aImportedPropsPath := TPath.Combine(lRoot, 'Imported.props');
  TFile.WriteAllText(aImportedPropsPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <ImportedValue>from-import</ImportedValue>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak, TEncoding.UTF8);

  lProjectXml := TStringBuilder.Create;
  try
    lProjectXml.AppendLine('<Project>');
    lProjectXml.AppendLine('  <PropertyGroup>');
    lProjectXml.AppendLine('    <EnableImportedProps>true</EnableImportedProps>');
    lProjectXml.AppendLine('  </PropertyGroup>');
    lProjectXml.AppendLine(
      '  <Import Project="Imported.props" Condition="''$(EnableImportedProps)''==''true'' And Exists(''Imported.props'')"/>');
    lProjectXml.AppendLine('</Project>');
    TFile.WriteAllText(aProjectPath, lProjectXml.ToString, TEncoding.UTF8);
  finally
    lProjectXml.Free;
  end;
end;

procedure BuildProjectMetadataProject(out aProjectPath, aMainSourcePath, aReferenceDir, aSearchDir: string);
var
  lProjectXml: TStringBuilder;
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'msbuild-project-metadata');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  aReferenceDir := TPath.Combine(lRoot, 'src');
  aSearchDir := TPath.Combine(lRoot, 'shared');
  TDirectory.CreateDirectory(aReferenceDir);
  TDirectory.CreateDirectory(aSearchDir);
  aProjectPath := TPath.Combine(lRoot, 'MetadataCheck.dproj');
  aMainSourcePath := TPath.Combine(lRoot, 'MetadataCheck.dpr');
  TFile.WriteAllText(aMainSourcePath, 'program MetadataCheck;' + sLineBreak + 'begin' + sLineBreak + 'end.',
    TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(aReferenceDir, 'MetadataUnit.pas'),
    'unit MetadataUnit;' + sLineBreak + 'interface' + sLineBreak + 'implementation' + sLineBreak + 'end.',
    TEncoding.UTF8);

  lProjectXml := TStringBuilder.Create;
  try
    lProjectXml.AppendLine('<Project>');
    lProjectXml.AppendLine('  <PropertyGroup Condition="''$(Config)''==''Debug'' and ''$(Platform)''==''Win32''">');
    lProjectXml.AppendLine('    <MainSource>MetadataCheck.dpr</MainSource>');
    lProjectXml.AppendLine('    <DCC_UnitSearchPath>shared</DCC_UnitSearchPath>');
    lProjectXml.AppendLine('    <DCC_Namespace>Project.Scope;Shared.Scope</DCC_Namespace>');
    lProjectXml.AppendLine('    <DCC_UnitAliases>Legacy.Unit=Modern.Unit</DCC_UnitAliases>');
    lProjectXml.AppendLine('  </PropertyGroup>');
    lProjectXml.AppendLine('  <ItemGroup>');
    lProjectXml.AppendLine('    <DCCReference Include="src\MetadataUnit.pas"/>');
    lProjectXml.AppendLine('  </ItemGroup>');
    lProjectXml.AppendLine('</Project>');
    TFile.WriteAllText(aProjectPath, lProjectXml.ToString, TEncoding.UTF8);
  finally
    lProjectXml.Free;
  end;
end;

procedure BuildTargetPlatformProject(const aRootName: string; out aProjectPath, aRoot: string);
begin
  aRoot := TPath.Combine(TempRoot, aRootName);
  if TDirectory.Exists(aRoot) then
    TDirectory.Delete(aRoot, True);
  TDirectory.CreateDirectory(aRoot);

  TFile.WriteAllText(TPath.Combine(aRoot, 'TargetPlatformCheck.dpr'),
    'program TargetPlatformCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.', TEncoding.UTF8);
  aProjectPath := TPath.Combine(aRoot, 'TargetPlatformCheck.dproj');
  TFile.WriteAllText(aProjectPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>TargetPlatformCheck.dpr</MainSource>' + sLineBreak +
    '    <Platform>Win32</Platform>' + sLineBreak +
    '    <DCC_Define>PROJECT_OVERRIDE</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Platform)''==''Linux64''">' + sLineBreak +
    '    <DCC_Define>LINUX_PROJECT_BRANCH;$(DCC_Define)</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Platform)''==''Win32''">' + sLineBreak +
    '    <DCC_Define>WIN32_PROJECT_BRANCH;$(DCC_Define)</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>', TEncoding.UTF8);
end;

procedure TMsBuildTests.AssertConditionAccepted(const aCondition: string);
var
  lProjectPath: string;
  lProps: TDictionary<string, string>;
  lEnv: TDictionary<string, string>;
  lDiagnostics: TDiagnostics;
  lEvaluator: TMsBuildEvaluator;
  lError: string;
begin
  BuildConditionProject(aCondition, lProjectPath);

  lProps := TDictionary<string, string>.Create;
  lEnv := TDictionary<string, string>.Create;
  lDiagnostics := TDiagnostics.Create;
  try
    lEvaluator := TMsBuildEvaluator.Create(lProps, lEnv, lDiagnostics);
    try
      lError := '';
      Assert.IsTrue(lEvaluator.EvaluateFile(lProjectPath, lError),
        'Expected valid condition to be accepted: ' + aCondition + ' Error: ' + lError);
    finally
      lEvaluator.Free;
    end;
  finally
    lDiagnostics.Free;
    lEnv.Free;
    lProps.Free;
  end;
end;

procedure TMsBuildTests.AssertConditionSetsMainSource(const aCondition: string);
var
  lMainSource: string;
  lProjectPath: string;
  lProps: TDictionary<string, string>;
  lEnv: TDictionary<string, string>;
  lDiagnostics: TDiagnostics;
  lEvaluator: TMsBuildEvaluator;
  lError: string;
begin
  BuildConditionProject(aCondition, lProjectPath);

  lProps := TDictionary<string, string>.Create;
  lEnv := TDictionary<string, string>.Create;
  lDiagnostics := TDiagnostics.Create;
  try
    lEvaluator := TMsBuildEvaluator.Create(lProps, lEnv, lDiagnostics);
    try
      lError := '';
      Assert.IsTrue(lEvaluator.EvaluateFile(lProjectPath, lError),
        'Expected valid condition to be accepted: ' + aCondition + ' Error: ' + lError);
    finally
      lEvaluator.Free;
    end;
    Assert.IsTrue(lProps.TryGetValue('MainSource', lMainSource),
      'Expected condition to evaluate true and set MainSource: ' + aCondition);
    Assert.AreEqual('ConditionCheck.dpr', lMainSource);
  finally
    lDiagnostics.Free;
    lEnv.Free;
    lProps.Free;
  end;
end;

procedure TMsBuildTests.AssertConditionRejected(const aCondition: string);
var
  lProjectPath: string;
  lProps: TDictionary<string, string>;
  lEnv: TDictionary<string, string>;
  lDiagnostics: TDiagnostics;
  lEvaluator: TMsBuildEvaluator;
  lError: string;
begin
  BuildConditionProject(aCondition, lProjectPath);

  lProps := TDictionary<string, string>.Create;
  lEnv := TDictionary<string, string>.Create;
  lDiagnostics := TDiagnostics.Create;
  try
    lEvaluator := TMsBuildEvaluator.Create(lProps, lEnv, lDiagnostics);
    try
      lError := '';
      Assert.IsFalse(lEvaluator.EvaluateFile(lProjectPath, lError),
        'Expected invalid condition to be rejected: ' + aCondition + ' Error: ' + lError);
      Assert.IsTrue(Pos('Unsupported or invalid Condition', lError) > 0,
        'Expected parse error details in evaluator output. Actual: ' + lError);
    finally
      lEvaluator.Free;
    end;
  finally
    lDiagnostics.Free;
    lEnv.Free;
    lProps.Free;
  end;
end;

procedure TMsBuildTests.AcceptsSimpleValidCondition;
begin
  AssertConditionAccepted('''Debug''==''Debug''');
end;

procedure TMsBuildTests.AcceptsConditionWithoutWhitespaceAroundOr;
begin
  AssertConditionAccepted(#39 + 'Debug' + #39 + '==' + #39 + 'Debug' + #39 + 'or' +
    #39 + 'Release' + #39 + '==' + #39 + 'Debug' + #39);
end;

procedure TMsBuildTests.AcceptsComparisonWithWhitespaceAroundNotEqualOperator;
begin
  AssertConditionAccepted('''Debug'' != ''Release''');
end;

procedure TMsBuildTests.AcceptsExistsConditionForRelativeImportPath;
var
  lCondition: string;
begin
  lCondition := '''Debug''==''Debug'' and Exists(''' + TPath.Combine(TempRoot, 'msbuild-exists-check.txt') + ''')';
  TFile.WriteAllText(TPath.Combine(TempRoot, 'msbuild-exists-check.txt'), 'ok', TEncoding.ASCII);
  AssertConditionSetsMainSource(lCondition);
end;

procedure TMsBuildTests.AcceptsNegatedExistsConditionForMissingPath;
var
  lCondition: string;
begin
  lCondition := '''Debug''==''Debug'' and !Exists(''' + TPath.Combine(TempRoot, 'msbuild-missing-check.txt') + ''')';
  AssertConditionSetsMainSource(lCondition);
end;

procedure TMsBuildTests.AcceptsNegatedHasTrailingSlashCondition;
begin
  AssertConditionSetsMainSource('''bin''!='''' and !HasTrailingSlash(''bin'')');
end;

procedure TMsBuildTests.AcceptsHasTrailingSlashConditionWhenPathAlreadyEndsWithSlash;
begin
  AssertConditionSetsMainSource('''bin\''!='''' and HasTrailingSlash(''bin\'')');
end;

procedure TMsBuildTests.AcceptsUnquotedHasTrailingSlashArgumentWithSpaces;
begin
  AssertConditionSetsMainSource('''C:\Build Output''!='''' and !HasTrailingSlash(C:\Build Output)');
end;

procedure TMsBuildTests.RejectsTrailingUnknownTokenInCondition;
begin
  AssertConditionRejected('''Debug''==''Debug'' trailing');
end;

procedure TMsBuildTests.RejectsTrailingInvalidOperatorInCondition;
begin
  AssertConditionRejected('''Debug''==''Debug'' =');
end;

procedure TMsBuildTests.RejectsUnterminatedQuotedLiteralInCondition;
begin
  AssertConditionRejected(#39 + 'Debug' + #39 + '==' + #39 + 'Debug');
end;

procedure TMsBuildTests.EvaluatesImportedPropertyGroupsWhenImportConditionMatches;
var
  lDiagnostics: TDiagnostics;
  lEnv: TDictionary<string, string>;
  lError: string;
  lEvaluator: TMsBuildEvaluator;
  lImportedPropsPath: string;
  lImportedValue: string;
  lProjectPath: string;
  lProps: TDictionary<string, string>;
begin
  BuildImportProject(lProjectPath, lImportedPropsPath);
  Assert.IsTrue(FileExists(lImportedPropsPath), 'Expected imported props fixture file to exist.');

  lProps := TDictionary<string, string>.Create;
  lEnv := TDictionary<string, string>.Create;
  lDiagnostics := TDiagnostics.Create;
  try
    lEvaluator := TMsBuildEvaluator.Create(lProps, lEnv, lDiagnostics);
    try
      lError := '';
      Assert.IsTrue(lEvaluator.EvaluateFile(lProjectPath, lError),
        'Expected import-aware evaluation to succeed. Error: ' + lError);
    finally
      lEvaluator.Free;
    end;

    Assert.IsTrue(lProps.TryGetValue('ImportedValue', lImportedValue),
      'Expected imported property group to be evaluated.');
    Assert.AreEqual('from-import', lImportedValue,
      'Expected imported property to come from the imported props file.');
  finally
    lDiagnostics.Free;
    lEnv.Free;
    lProps.Free;
  end;
end;

procedure TMsBuildTests.PropertyValueWithQuotedEmptyLiteralDoesNotBreakLaterCondition;
var
  lProjectPath: string;
  lRoot: string;
  lProps: TDictionary<string, string>;
  lEnv: TDictionary<string, string>;
  lDiagnostics: TDiagnostics;
  lEvaluator: TMsBuildEvaluator;
  lError: string;
begin
  lRoot := TPath.Combine(TempRoot, 'msbuild-quoted-empty-property');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);
  lProjectPath := TPath.Combine(lRoot, 'QuotedEmptyProperty.dproj');
  TFile.WriteAllText(lProjectPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <LANGDIR>''''</LANGDIR>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <DCC_TranslatedLibraryPath Condition="''$(LANGDIR)'' != ''''">translated</DCC_TranslatedLibraryPath>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak, TEncoding.UTF8);

  lProps := TDictionary<string, string>.Create;
  lEnv := TDictionary<string, string>.Create;
  lDiagnostics := TDiagnostics.Create;
  try
    lEvaluator := TMsBuildEvaluator.Create(lProps, lEnv, lDiagnostics);
    try
      lError := '';
      Assert.IsTrue(lEvaluator.EvaluateFile(lProjectPath, lError),
        'Expected quoted empty literal property condition to parse. Error: ' + lError);
    finally
      lEvaluator.Free;
    end;
  finally
    lDiagnostics.Free;
    lEnv.Free;
    lProps.Free;
  end;
end;

procedure TMsBuildTests.SelfReferenceFallsBackToEmptyWhenPropertyWasUndefined;
var
  lProjectPath: string;
  lProps: TDictionary<string, string>;
  lEnv: TDictionary<string, string>;
  lDiagnostics: TDiagnostics;
  lEvaluator: TMsBuildEvaluator;
  lError: string;
  lPreBuildEvent: string;
begin
  BuildPropertyProject('PreBuildEvent', 'echo before$(PreBuildEvent)', lProjectPath);
  lProps := TDictionary<string, string>.Create;
  lEnv := TDictionary<string, string>.Create;
  lDiagnostics := TDiagnostics.Create;
  try
    lEvaluator := TMsBuildEvaluator.Create(lProps, lEnv, lDiagnostics);
    try
      lError := '';
      Assert.IsTrue(lEvaluator.EvaluateFile(lProjectPath, lError),
        'Expected property evaluation to succeed. Error: ' + lError);
    finally
      lEvaluator.Free;
    end;
    Assert.IsTrue(lProps.TryGetValue('PreBuildEvent', lPreBuildEvent),
      'Expected PreBuildEvent property to be set.');
    Assert.AreEqual('echo before', lPreBuildEvent,
      'Expected self-reference to resolve to empty text when no prior property value exists.');
  finally
    lDiagnostics.Free;
    lEnv.Free;
    lProps.Free;
  end;
end;

procedure TMsBuildTests.ProjectSourceLookupExposesStableMetadataForSemanticConsumers;
var
  lError: string;
  lLookup: TProjectSourceLookup;
  lMainSourcePath: string;
  lProjectPath: string;
  lReferenceDir: string;
  lSearchDir: string;
  lSearchPathText: string;
begin
  BuildProjectMetadataProject(lProjectPath, lMainSourcePath, lReferenceDir, lSearchDir);
  Assert.IsTrue(TryBuildProjectSourceLookup(lProjectPath, 'Debug', 'Win32', '23.0', nil, nil, lLookup, lError),
    'Expected project source lookup. Error: ' + lError);
  Assert.AreEqual(TPath.GetFullPath(lProjectPath), lLookup.fProjectDproj);
  Assert.AreEqual(TPath.GetDirectoryName(lProjectPath), lLookup.fProjectDir);
  Assert.AreEqual(TPath.GetFullPath(lMainSourcePath), lLookup.fMainSourcePath);
  lSearchPathText := String.Join(';', lLookup.fSearchPaths);
  Assert.IsTrue(Pos(TPath.GetFullPath(lReferenceDir), lSearchPathText) > 0,
    'Expected DCCReference directory in search paths: ' + lSearchPathText);
  Assert.IsTrue(Pos(TPath.GetFullPath(lSearchDir), lSearchPathText) > 0,
    'Expected DCC_UnitSearchPath directory in search paths: ' + lSearchPathText);
end;

procedure TMsBuildTests.ProjectParamsUseRequestedPlatformWhenProjectSetsPlatform;
var
  lDefineText: string;
  lEnv: TDictionary<string, string>;
  lError: string;
  lErrorCode: Integer;
  lOptions: TAppOptions;
  lParams: TFixInsightParams;
  lProjectPath: string;
  lRoot: string;
begin
  BuildTargetPlatformProject('msbuild-target-platform-params', lProjectPath, lRoot);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lProjectPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Linux64';
  lOptions.fDelphiVersion := '23.0';

  lEnv := TDictionary<string, string>.Create;
  try
    Assert.IsTrue(TryBuildParams(lOptions, lEnv, lRoot, TPropertySource.psDproj, nil, lParams,
      lError, lErrorCode), 'Expected params to build. Error: ' + lError);
  finally
    lEnv.Free;
  end;

  lDefineText := String.Join(';', lParams.fDefines);
  Assert.AreEqual('Linux64', lParams.fPlatform);
  Assert.IsTrue(Pos('PROJECT_OVERRIDE', lDefineText) > 0, 'PROJECT_OVERRIDE');
  Assert.IsTrue(Pos('LINUX_PROJECT_BRANCH', lDefineText) > 0, 'LINUX_PROJECT_BRANCH');
  Assert.AreEqual(0, Pos('WIN32_PROJECT_BRANCH', lDefineText), 'WIN32_PROJECT_BRANCH');
  Assert.IsTrue(Pos('LINUX', lDefineText) > 0, 'LINUX');
  Assert.IsTrue(Pos('POSIX', lDefineText) > 0, 'POSIX');
  Assert.IsTrue(Pos('CPUX64', lDefineText) > 0, 'CPUX64');
  Assert.AreEqual(0, Pos('MSWINDOWS', lDefineText), 'MSWINDOWS');
  Assert.AreEqual(0, Pos('WIN32', lDefineText), 'WIN32');
end;

procedure TMsBuildTests.DegradedProjectAnalysisContextKeepsProjectDefines;
var
  lContext: TProjectAnalysisContext;
  lError: string;
  lOptions: TAppOptions;
  lProjectPath: string;
  lRoot: string;
begin
  BuildTargetPlatformProject('msbuild-target-platform-degraded', lProjectPath, lRoot);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lProjectPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Linux64';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := TPath.Combine(lRoot, 'missing-rsvars.bat');

  Assert.IsTrue(TryBuildProjectAnalysisContext(lOptions, lContext, lError),
    'Expected degraded project context. Error: ' + lError);
  Assert.IsFalse(lContext.HasDelphiContext, 'Expected missing rsvars to force degraded context.');
  Assert.AreEqual(TProjectAnalysisContextQuality.pcqDegradedProjectOnly, lContext.Quality,
    'Expected structured degraded context quality.');
  Assert.IsTrue(Pos('PROJECT_OVERRIDE', lContext.ParserDefines) > 0, 'PROJECT_OVERRIDE');
  Assert.IsTrue(Pos('LINUX_PROJECT_BRANCH', lContext.ParserDefines) > 0, 'LINUX_PROJECT_BRANCH');
  Assert.AreEqual(0, Pos('WIN32_PROJECT_BRANCH', lContext.ParserDefines), 'WIN32_PROJECT_BRANCH');
  Assert.IsTrue(Pos('LINUX', lContext.ParserDefines) > 0, 'LINUX');
  Assert.IsTrue(Pos('POSIX', lContext.ParserDefines) > 0, 'POSIX');
  Assert.IsTrue(Pos('CPUX64', lContext.ParserDefines) > 0, 'CPUX64');
  Assert.AreEqual(0, Pos('MSWINDOWS', lContext.ParserDefines), 'MSWINDOWS');
  Assert.AreEqual(0, Pos('WIN32', lContext.ParserDefines), 'WIN32');
end;

procedure TMsBuildTests.StrictProjectAnalysisContextFailsOnDegradedContext;
var
  lContext: TProjectAnalysisContext;
  lError: string;
  lOptions: TAppOptions;
  lProjectPath: string;
  lRoot: string;
begin
  BuildTargetPlatformProject('msbuild-target-platform-strict-context', lProjectPath, lRoot);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lProjectPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Linux64';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := TPath.Combine(lRoot, 'missing-rsvars.bat');

  Assert.IsFalse(TryBuildProjectAnalysisContext(lOptions,
    TProjectAnalysisContextRequirement.StrictSemantic, lContext, lError),
    'Strict semantic context must fail closed when rsvars cannot be resolved.');
  Assert.IsTrue(ContainsText(lError, 'Delphi IDE context could not be resolved'),
    'Expected strict-context error to include the degradation reason. Error: ' + lError);
end;

procedure TMsBuildTests.ProjectAnalysisCommandCallersChooseExplicitContextPolicy;
const
  cCommandSources: array[0..4] of string = (
    'src\dak.dfmcheck.pas',
    'src\dak.deps.runner.pas',
    'src\dak.globalvars.pas',
    'src\Dak.RemoveWith.Model.pas',
    'src\Dak.SymbolMap.Context.pas');
var
  lPath: string;
  lSource: string;
begin
  for lPath in cCommandSources do
  begin
    lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, lPath), TEncoding.UTF8);
    Assert.IsTrue(ContainsText(lSource, 'TProjectAnalysisContextRequirement.AllowDegraded') or
      ContainsText(lSource, 'TProjectAnalysisContextRequirement.StrictSemantic'),
      'Expected explicit project-analysis context policy in ' + lPath);
    Assert.IsFalse(ContainsText(lSource, 'TryBuildProjectAnalysisContext(aOptions, lContext') or
      ContainsText(lSource, 'TryBuildProjectAnalysisContext(lOptions, aContext.fProject') or
      ContainsText(lSource, 'TryBuildProjectAnalysisContext(fOptions, fContext'),
      'Command context callers must not use the implicit degraded-context overload in ' + lPath);
  end;
end;

procedure TMsBuildTests.ProjectAnalysisContextDelegatesSemanticAuthority;
var
  lBody: string;
  lEndIndex: Integer;
  lImplementationIndex: Integer;
  lSource: string;
  lStartIndex: Integer;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.project.pas'), TEncoding.UTF8);
  lImplementationIndex := Pos('implementation', lSource);
  Assert.IsTrue(lImplementationIndex > 0, 'Expected implementation section.');

  lStartIndex := Pos('function TryBuildProjectAnalysisContext',
    Copy(lSource, lImplementationIndex, MaxInt));
  if lStartIndex > 0 then
    Inc(lStartIndex, lImplementationIndex - 1);
  lEndIndex := Pos('function CreateProjectAnalysisIndexer',
    Copy(lSource, lStartIndex, MaxInt));
  if lEndIndex > 0 then
    Inc(lEndIndex, lStartIndex - 1);

  Assert.IsTrue(lStartIndex > 0, 'Expected TryBuildProjectAnalysisContext implementation.');
  Assert.IsTrue(lEndIndex > lStartIndex, 'Expected CreateProjectAnalysisIndexer after analysis context.');

  lBody := Copy(lSource, lStartIndex, lEndIndex - lStartIndex);
  Assert.IsTrue(ContainsText(lBody, 'TDelphiSemanticApi.LoadProjectContext'),
    'Project-analysis context should load semantic project context directly.');
  Assert.IsFalse(ContainsText(lBody, 'TryBuildParams('),
    'Project-analysis context must not rebuild parser context through DAK FixInsight params.');
  Assert.IsFalse(ContainsText(lBody, 'TMsBuildEvaluator'),
    'Project-analysis context must not evaluate MSBuild independently.');
end;

procedure TMsBuildTests.ResolveRunnerDelegatesProjectFactsToSemanticContext;
var
  lBody: string;
  lGuardBody: string;
  lEndIndex: Integer;
  lSource: string;
  lStartIndex: Integer;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.resolve.runner.pas'), TEncoding.UTF8);
  lStartIndex := Pos('function TResolveCommandRunner.TryBuildProjectParams', lSource);
  lEndIndex := Pos('procedure TResolveCommandRunner.ApplyFixInsightSettings',
    Copy(lSource, lStartIndex, MaxInt));
  if lEndIndex > 0 then
    Inc(lEndIndex, lStartIndex - 1);

  Assert.IsTrue(lStartIndex > 0, 'Expected TryBuildProjectParams implementation.');
  Assert.IsTrue(lEndIndex > lStartIndex, 'Expected next resolve-runner method after TryBuildProjectParams.');

  lBody := Copy(lSource, lStartIndex, lEndIndex - lStartIndex);
  Assert.IsTrue(ContainsText(lBody, 'TryBuildProjectAnalysisContext'),
    'resolve should consume DelphiSemantics project context for project/compiler facts.');
  Assert.IsTrue(ContainsText(lBody, 'TryBuildParamsFromProjectContext(fOptions, fProjectContext, fEnvVars'),
    'resolve should pass the merged IDE environment to the context adapter.');
  Assert.IsFalse(ContainsText(lBody, 'Dak.Project.TryBuildParams'),
    'resolve should not rebuild semantic project params through DAK TryBuildParams.');
  lGuardBody := StringReplace(lBody, 'TryBuildParamsFromProjectContext(', '', [rfReplaceAll]);
  Assert.IsFalse(ContainsText(lGuardBody, 'TryBuildParams('),
    'resolve should not call the old project-param builder, even unqualified.');
end;

procedure TMsBuildTests.ProjectContextParamsPreserveResolveFactsAndNormalizeLibraryPaths;
var
  lContext: TProjectAnalysisContext;
  lEnv: TDictionary<string, string>;
  lError: string;
  lErrorCode: Integer;
  lLibDir: string;
  lMainSourcePath: string;
  lOptions: TAppOptions;
  lParams: TFixInsightParams;
  lProjectDir: string;
  lSearchDir: string;
begin
  lProjectDir := TPath.Combine(TempRoot, 'msbuild-context-params');
  if TDirectory.Exists(lProjectDir) then
    TDirectory.Delete(lProjectDir, True);
  TDirectory.CreateDirectory(lProjectDir);
  lSearchDir := TPath.Combine(lProjectDir, 'src');
  lLibDir := TPath.Combine(lProjectDir, 'lib');
  TDirectory.CreateDirectory(lSearchDir);
  TDirectory.CreateDirectory(lLibDir);
  lMainSourcePath := TPath.Combine(lProjectDir, 'ContextParams.dpr');
  TFile.WriteAllText(lMainSourcePath,
    'program ContextParams;' + sLineBreak + 'begin' + sLineBreak + 'end.',
    TEncoding.UTF8);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := TPath.Combine(lProjectDir, 'ContextParams.dproj');
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win64';
  lOptions.fDelphiVersion := '23.0';

  lContext := TProjectAnalysisContext.Create(lOptions.fDprojPath, 'ContextParams',
    lProjectDir, lMainSourcePath, TArray<string>.Create(lMainSourcePath),
    'SEMANTIC_DEFINE;SECOND_DEFINE', lSearchDir,
    TArray<string>.Create('Vcl', 'System'), TArray<string>.Create('Legacy=Modern'),
    TPath.Combine(lProjectDir, '.dak\ContextParams'), True, '');

  lEnv := TDictionary<string, string>.Create;
  try
    lEnv.Add('IDE_ONLY_LIB', lLibDir);
    Assert.IsTrue(TryBuildParamsFromProjectContext(lOptions, lContext, lEnv,
      '$(IDE_ONLY_LIB);$(IDE_ONLY_LIB)', TPropertySource.psEnvOptions, nil, lParams,
      lError, lErrorCode), 'Expected context params. Error: ' + lError);
  finally
    lEnv.Free;
  end;

  Assert.AreEqual(lMainSourcePath, lParams.fProjectDpr);
  Assert.AreEqual('SEMANTIC_DEFINE;SECOND_DEFINE', ArrayText(lParams.fDefines));
  Assert.AreEqual(2, Integer(Length(lParams.fUnitSearchPath)));
  Assert.AreEqual(lSearchDir, lParams.fUnitSearchPath[0]);
  Assert.IsTrue(Pos(lLibDir, ArrayText(lParams.fUnitSearchPath)) > 0,
    'Expected normalized library path in combined search path.');
  Assert.AreEqual(lLibDir, ArrayText(lParams.fLibraryPath));
  Assert.AreEqual('Vcl;System', ArrayText(lParams.fUnitScopes));
  Assert.AreEqual('Legacy=Modern', ArrayText(lParams.fUnitAliases));
  Assert.AreEqual('Release', lParams.fConfig);
  Assert.AreEqual('Win64', lParams.fPlatform);
  Assert.AreEqual(Integer(TPropertySource.psEnvOptions), Integer(lParams.fLibrarySource));
  Assert.AreEqual(Integer(TPropertySource.psUnknown), Integer(lParams.fDefineSource));
  Assert.AreEqual(Integer(TPropertySource.psUnknown), Integer(lParams.fSearchPathSource));
  Assert.AreEqual(Integer(TPropertySource.psUnknown), Integer(lParams.fUnitScopesSource));
  Assert.AreEqual(Integer(TPropertySource.psUnknown), Integer(lParams.fUnitAliasesSource));
end;

procedure TMsBuildTests.ProjectAnalysisContextExposesReadOnlyProperties;
var
  lAliases: TArray<string>;
  lContext: TProjectAnalysisContext;
  lMutated: TArray<string>;
  lSource: string;
  lVariant: TProjectAnalysisContext;
begin
  lAliases := TArray<string>.Create('UnitA=UnitB');
  lContext := TProjectAnalysisContext.Create('Project.dproj', 'Project',
    'C:\Project', 'C:\Project\Project.dpr',
    TArray<string>.Create('C:\Project\Unit1.pas'), 'A;B',
    'C:\Project;C:\Lib', TArray<string>.Create('Vcl', 'System'), lAliases,
    'C:\Project\.dak\Project', True, '');
  lAliases[0] := 'Changed=Alias';
  Assert.AreEqual('UnitA=UnitB', lContext.UnitAliases[0],
    'Constructor should copy array inputs.');

  lMutated := lContext.SourceFileNames;
  lMutated[0] := 'Changed.pas';
  Assert.AreEqual('C:\Project\Unit1.pas', lContext.SourceFileNames[0],
    'Source-file property should return a copy.');
  lMutated := lContext.UnitScopes;
  lMutated[0] := 'ChangedScope';
  Assert.AreEqual('Vcl', lContext.UnitScopes[0],
    'Unit-scope property should return a copy.');
  lMutated := lContext.UnitAliases;
  lMutated[0] := 'Changed=Again';
  Assert.AreEqual('UnitA=UnitB', lContext.UnitAliases[0],
    'Unit-alias property should return a copy.');

  lVariant := lContext.WithParserDefines('RTL');
  Assert.AreEqual('RTL', lVariant.ParserDefines);
  Assert.AreEqual(lContext.ProjectPath, lVariant.ProjectPath);
  Assert.AreEqual(lContext.ParserSearchPath, lVariant.ParserSearchPath);
  Assert.AreEqual(lContext.UnitAliases[0], lVariant.UnitAliases[0]);

  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.SymbolMap.Cache.pas'),
    TEncoding.UTF8);
  Assert.IsFalse(ContainsText(lSource, '.fProject.fParserDefines :='),
    'SymbolMap should use an explicit helper for alternate project contexts.');
  Assert.IsTrue(ContainsText(lSource, 'WithRtlSourceRoot'),
    'RTL SymbolMap contexts should be created through the explicit context helper.');
end;

procedure TMsBuildTests.ProjectAnalysisContextMatchesSemanticProjectContext;
var
  lContext: TProjectAnalysisContext;
  lError: string;
  lMainSourcePath: string;
  lOptions: TAppOptions;
  lProjectPath: string;
  lReferenceDir: string;
  lSearchDir: string;
  lSemanticOptions: TDelphiSemanticApiOptions;
  lSemanticResult: TDelphiSemanticContextResult;
begin
  BuildProjectMetadataProject(lProjectPath, lMainSourcePath, lReferenceDir, lSearchDir);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lProjectPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';

  lSemanticOptions := Default(TDelphiSemanticApiOptions);
  lSemanticOptions.Configuration := lOptions.fConfig;
  lSemanticOptions.Platform := lOptions.fPlatform;
  lSemanticOptions.DelphiVersion := lOptions.fDelphiVersion;

  lSemanticResult := TDelphiSemanticApi.LoadProjectContext(lProjectPath, lSemanticOptions);
  Assert.IsTrue(lSemanticResult.Success, 'Expected semantic project context.');
  Assert.IsTrue(TryBuildProjectAnalysisContext(lOptions, lContext, lError),
    'Expected DAK project analysis context. Error: ' + lError);

  Assert.AreEqual(lSemanticResult.Project.ProjectFileName, lContext.ProjectPath);
  Assert.AreEqual(lSemanticResult.Project.ProjectDirectory, lContext.ProjectDir);
  Assert.AreEqual(lSemanticResult.Project.ProjectName, lContext.ProjectName);
  Assert.AreEqual(lSemanticResult.Project.MainSourceFileName, lContext.MainSourcePath);
  Assert.AreEqual(ArrayText(lSemanticResult.Project.Defines), lContext.ParserDefines);
  Assert.AreEqual(ArrayText(lSemanticResult.Project.UnitScopeNames), ArrayText(lContext.UnitScopes));
  Assert.AreEqual(ArrayText(lSemanticResult.Project.UnitAliases), ArrayText(lContext.UnitAliases));
  Assert.IsTrue(ContainsText(lContext.ParserSearchPath, TPath.GetFullPath(lReferenceDir)),
    'Expected DAK context reference dir from semantic source lookup.');
  Assert.IsTrue(ContainsText(lContext.ParserSearchPath, TPath.GetFullPath(lSearchDir)),
    'Expected DAK context search dir from semantic source lookup.');
end;

procedure TMsBuildTests.RadStudioLocatorConsolidatesInstallDiscovery;
var
  lBuildRunnerSource: string;
  lLocatorPath: string;
  lLocatorSource: string;
  lLspRunnerSource: string;
  lRemoveWithSource: string;
  lRsVarsSource: string;
  lSymbolMapCacheSource: string;
  lSymbolMapSource: string;
begin
  lLocatorPath := TPath.Combine(RepoRoot, 'src\Dak.RadStudio.Locator.pas');
  Assert.IsTrue(TFile.Exists(lLocatorPath), 'Expected shared RAD Studio locator unit.');

  lLocatorSource := TFile.ReadAllText(lLocatorPath, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lLocatorSource, 'ResolveRsVarsPath'), 'Expected shared rsvars path resolver.');
  Assert.IsTrue(ContainsText(lLocatorSource, 'ResolveBdsRoot'), 'Expected shared BDS root resolver.');
  Assert.IsTrue(ContainsText(lLocatorSource, 'BuildDelphiLspCandidatePaths'),
    'Expected shared DelphiLSP candidate resolver.');
  Assert.IsTrue(ContainsText(lLocatorSource, 'ResolveRtlSourceRoot'), 'Expected shared RTL source root resolver.');
  Assert.IsTrue(ContainsText(lLocatorSource, 'TDelphiSemanticCompilerProfileBuilder.ResolveRtlSourceRoot'),
    'Expected RTL source root authority to stay in DelphiSemantics.');

  lRsVarsSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.rsvars.pas'), TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lRsVarsSource, 'ResolveRsVarsPath'),
    'Expected rsvars loading to delegate path discovery to the shared locator.');
  Assert.IsFalse(ContainsText(lRsVarsSource, 'ProgramFiles'),
    'rsvars should not own ProgramFiles RAD Studio probing.');

  lBuildRunnerSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.Build.Runner.pas'), TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lBuildRunnerSource, 'ResolveBdsRoot'),
    'Expected build runner to delegate BDS root discovery to the shared locator.');

  lLspRunnerSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.lsp.runner.pas'), TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lLspRunnerSource, 'BuildDelphiLspCandidatePaths'),
    'Expected LSP runner to delegate DelphiLSP discovery candidates to the shared locator.');

  lSymbolMapSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.SymbolMap.Context.pas'), TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lSymbolMapSource, 'ResolveRtlSourceRoot'),
    'Expected SymbolMap context to delegate RTL source root discovery to the shared locator.');

  lSymbolMapCacheSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.SymbolMap.Cache.pas'), TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lSymbolMapCacheSource, 'ResolveRtlSourceRoot'),
    'Expected SymbolMap cache fallback to delegate RTL source root discovery to the shared locator.');
  Assert.IsFalse(ContainsText(lSymbolMapCacheSource,
    TPath.Combine('C:\Program Files (x86)', 'Embarcadero\Studio\23.0\source')),
    'SymbolMap cache must not own a hard-coded RTL source fallback.');

  lRemoveWithSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.RemoveWith.Symbols.pas'),
    TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lRemoveWithSource, 'ResolveRtlSourceRoot'),
    'Expected remove-with symbol inventory to delegate RTL source root discovery to the shared locator.');
end;

procedure TMsBuildTests.RadStudioLocatorPreservesDiscoveryPrecedence;
var
  lBdsRoot: string;
  lCandidates: TArray<string>;
  lEnvBlock: string;
  lExpectedMissingBdsRoot: string;
  lExpectedMissingRsVars: string;
  lMissingVersion: string;
  lProgramFiles: string;
  lProgramFilesX86: string;
  lRoot: string;
  lRsVarsPath: string;
begin
  lRoot := TPath.Combine(TempRoot, 'rad-studio-locator');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  lBdsRoot := TPath.Combine(lRoot, 'BdsRoot');
  lRsVarsPath := TPath.Combine(lBdsRoot, 'bin\rsvars.bat');
  TDirectory.CreateDirectory(ExtractFileDir(lRsVarsPath));
  TFile.WriteAllText(lRsVarsPath, '@echo off', TEncoding.ASCII);

  Assert.AreEqual(lRsVarsPath, ResolveRsVarsPath('23.0', lRsVarsPath),
    'Explicit rsvars path should win.');
  Assert.AreEqual(TPath.GetFullPath(lBdsRoot), ResolveBdsRoot('23.0', '', lBdsRoot),
    'Environment BDS root should win when no explicit rsvars is provided.');
  Assert.AreEqual(TPath.GetFullPath(lBdsRoot), ResolveBdsRoot('23.0', lRsVarsPath, ''),
    'Explicit rsvars path should derive the install root.');
  Assert.AreEqual(TPath.GetFullPath(TPath.Combine(lBdsRoot, 'source')), ResolveRtlSourceRoot('23.0', lRsVarsPath),
    'RTL source root should be delegated through the semantic compiler-profile resolver.');

  lEnvBlock := 'BDS=' + lBdsRoot + #0#0;
  lCandidates := BuildDelphiLspCandidatePaths('23.0', lEnvBlock);
  Assert.IsTrue(Length(lCandidates) >= 3, 'Expected root, bin64, and bin DelphiLSP candidates.');
  Assert.AreEqual(TPath.GetFullPath(TPath.Combine(lBdsRoot, 'DelphiLSP.exe')), lCandidates[0],
    'Environment BDS root executable should be the first LSP candidate.');
  Assert.AreEqual(TPath.GetFullPath(TPath.Combine(lBdsRoot, 'bin64\DelphiLSP.exe')), lCandidates[1],
    'bin64 executable should follow the BDS root executable.');

  lMissingVersion := '99.0';
  lProgramFilesX86 := Trim(GetEnvironmentVariable('ProgramFiles(x86)'));
  lProgramFiles := Trim(GetEnvironmentVariable('ProgramFiles'));
  if lProgramFiles <> '' then
    lExpectedMissingRsVars := TPath.Combine(lProgramFiles,
      'Embarcadero\RAD Studio\' + lMissingVersion + '\bin\rsvars.bat')
  else if lProgramFilesX86 <> '' then
    lExpectedMissingRsVars := TPath.Combine(lProgramFilesX86,
      'Embarcadero\RAD Studio\' + lMissingVersion + '\bin\rsvars.bat')
  else
    lExpectedMissingRsVars := 'C:\Program Files (x86)\Embarcadero\Studio\' + lMissingVersion + '\bin\rsvars.bat';
  Assert.AreEqual(TPath.GetFullPath(lExpectedMissingRsVars), ResolveRsVarsPath(lMissingVersion, ''),
    'Missing rsvars fallback should preserve the previous environment-derived candidate order.');

  lExpectedMissingBdsRoot := TPath.Combine('C:\Program Files (x86)\Embarcadero\Studio', lMissingVersion);
  Assert.AreEqual(TPath.GetFullPath(lExpectedMissingBdsRoot), ResolveBdsRoot(lMissingVersion, '', ''),
    'Missing BDS root fallback should preserve the previous hardcoded install root.');
end;

initialization
  TDUnitX.RegisterTestFixture(TMsBuildTests);

end.
