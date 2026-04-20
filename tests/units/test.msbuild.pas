unit Test.MsBuild;

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.IOUtils,
  System.SysUtils,
  Xml.omnixmldom, Xml.xmldom,
  Dak.Diagnostics, Dak.MsBuild,
  Test.Support;

type
  [TestFixture]
  TMsBuildTests = class
  private
    procedure AssertConditionAccepted(const aCondition: string);
    procedure AssertConditionRejected(const aCondition: string);
  public
    [Test]
    procedure AcceptsSimpleValidCondition;
    [Test]
    procedure AcceptsConditionWithoutWhitespaceAroundOr;
    [Test]
    procedure AcceptsExistsConditionForRelativeImportPath;
    [Test]
    procedure RejectsTrailingUnknownTokenInCondition;
    [Test]
    procedure RejectsTrailingInvalidOperatorInCondition;
    [Test]
    procedure RejectsUnterminatedQuotedLiteralInCondition;
    [Test]
    procedure EvaluatesImportedPropertyGroupsWhenImportConditionMatches;
    [Test]
    procedure SelfReferenceFallsBackToEmptyWhenPropertyWasUndefined;
  end;

implementation

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

procedure TMsBuildTests.AcceptsExistsConditionForRelativeImportPath;
var
  lCondition: string;
begin
  lCondition := '''Debug''==''Debug'' and Exists(''' + TPath.Combine(TempRoot, 'msbuild-exists-check.txt') + ''')';
  TFile.WriteAllText(TPath.Combine(TempRoot, 'msbuild-exists-check.txt'), 'ok', TEncoding.ASCII);
  AssertConditionAccepted(lCondition);
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

initialization
  TDUnitX.RegisterTestFixture(TMsBuildTests);

end.
