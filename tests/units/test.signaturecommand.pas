unit Test.SignatureCommand;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  [Category('RefactoringLightAlign')]
  TSignatureCommandTests = class
  public
    [Test] procedure ComparesParseableNameDriftWithoutMutation;
    [Test] procedure UnknownSelectorIsExplicitlyIncomplete;
    [Test] procedure BrokenBaselineRetainsNonApplicableAlignmentSuggestion;
    [Test] procedure AlignedBaselineReturnsSuccessfulNoChange;
    [Test] procedure BuildHookInvalidatesAlignmentSuggestion;
    [Test] procedure PublishesAndRevalidatesNoChangeArtifact;
    [Test] procedure FailedBaselineDoesNotPublishArtifact;
    [Test] procedure UnusableLogDirectoryIsNamedInDiagnostic;
    [Test]
    [TestCase('Existing output', 'existing')]
    [TestCase('Comparison request', 'compare')]
    procedure RefusedArtifactOutputPreservesFiles(const aFault: string);
    [Test]
    [TestCase('Context', 'context')]
    [TestCase('Operation intent', 'intent')]
    procedure TamperedAlignmentArtifactDoesNotApply(const aFault: string);
    [Test]
    [TestCase('Oversized', 'oversized')]
    [TestCase('Invalid UTF8', 'utf8')]
    procedure InvalidRequestBytesAreBlocked(const aFault: string);
    [Test]
    [TestCase('Unknown schema', 'schema')]
    [TestCase('Unavailable operation', 'operation')]
    [TestCase('String offset', 'offset-type')]
    [TestCase('Zero offset', 'offset-zero')]
    [TestCase('Unknown field', 'extra')]
    [TestCase('Invalid JSON', 'json')]
    procedure InvalidRequestReturnsBlockedReport(const aFault: string);
  end;

implementation

uses
  System.Hash, System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Test.Support;

type
  TSignatureFixture = record
    fDirectory, fProject, fSource, fRequest, fLog, fSourceHash: string;
  end;

function CreateSignatureFixture: TSignatureFixture;
var
  id: TGUID;
  lSource: string;
  lRequest, lDeclaration: TJSONObject;
begin
  CreateGUID(id);
  Result.fDirectory := TPath.Combine(RepoRoot,
    'tests\.dak\DelphiAIKit.Tests\refactoring-light-align\fixtures\' + GUIDToString(id));
  ForceDirectories(Result.fDirectory);
  Result.fProject := TPath.Combine(Result.fDirectory, 'Alignment.dproj');
  Result.fSource := TPath.Combine(Result.fDirectory, 'Subject.pas');
  Result.fRequest := TPath.Combine(Result.fDirectory, 'request.json');
  Result.fLog := TPath.Combine(Result.fDirectory, 'report.json');
  lSource := 'unit Subject;'#13#10'interface'#13#10'type'#13#10 +
    '  TValue = (one, two);'#13#10'  TSubject = class'#13#10'  public'#13#10 +
    '    procedure SetValue(var aValue: TValue);'#13#10'  end;'#13#10 +
    'implementation'#13#10'procedure TSubject.SetValue(var aOldValue: TValue);'#13#10 +
    'begin aOldValue := two; end;'#13#10'end.'#13#10;
  TFile.WriteAllText(Result.fSource, lSource, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(Result.fDirectory, 'Alignment.dpr'),
    'program Alignment; uses Subject in ''Subject.pas''; begin end.', TEncoding.UTF8);
  TFile.WriteAllText(Result.fProject,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>Alignment.dpr</MainSource></PropertyGroup>' +
    '<ItemGroup><DCCReference Include="Subject.pas"/></ItemGroup></Project>', TEncoding.UTF8);
  lRequest := TJSONObject.Create;
  try
    lRequest.AddPair('schemaVersion', TJSONNumber.Create(1));
    lRequest.AddPair('operation', 'compare');
    lDeclaration := TJSONObject.Create;
    lRequest.AddPair('declaration', lDeclaration);
    lDeclaration.AddPair('fileName', Result.fSource);
    lDeclaration.AddPair('offset', TJSONNumber.Create(Pos('SetValue', lSource)));
    TFile.WriteAllText(Result.fRequest, lRequest.ToJSON, TEncoding.UTF8);
  finally
    lRequest.Free;
  end;
  Result.fSourceHash := THashSHA2.GetHashStringFromFile(Result.fSource);
end;

procedure TSignatureCommandTests.ComparesParseableNameDriftWithoutMutation;
var
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lReport: TJSONObject;
begin
  lFixture := CreateSignatureFixture;
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  lReport := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lReport, 'Comparison must return a versioned JSON report');
    Assert.AreEqual(Cardinal(0), lExit, lReport.ToJSON);
    Assert.AreEqual(1, lReport.GetValue<Integer>('schemaVersion'));
    Assert.AreEqual('signature.compare', lReport.GetValue<string>('operation'));
    Assert.AreEqual('name-drift', lReport.FindValue('comparison.status').Value);
    Assert.IsNotNull(lReport.FindValue('comparison.declaration'));
    Assert.IsNotNull(lReport.FindValue('comparison.implementation'));
    Assert.AreEqual('aValue', lReport.FindValue('comparison.declaration.parameters[0].name').Value);
    Assert.AreEqual('aOldValue', lReport.FindValue('comparison.implementation.parameters[0].name').Value);
    Assert.AreEqual('not-run', lReport.FindValue('buildVerification.status').Value);
    Assert.IsFalse((lReport.GetValue('applicable') as TJSONBool).AsBoolean);
    Assert.AreEqual(lFixture.fSourceHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
  finally
    lReport.Free;
  end;
end;

function InvalidSignatureRequest(const aFault: string): string;
begin
  Result := '{"schemaVersion":1,"operation":"compare",' +
    '"declaration":{"fileName":"Subject.pas","offset":1}}';
  if aFault = 'schema' then
    Result := StringReplace(Result, '"schemaVersion":1', '"schemaVersion":2', [])
  else if aFault = 'operation' then
    Result := StringReplace(Result, '"compare"', '"unsupported"', [])
  else if aFault = 'offset-type' then
    Result := StringReplace(Result, '"offset":1', '"offset":"1"', [])
  else if aFault = 'offset-zero' then
    Result := StringReplace(Result, '"offset":1', '"offset":0', [])
  else if aFault = 'extra' then
    Result := StringReplace(Result, '"schemaVersion":1', '"extra":true,"schemaVersion":1', [])
  else if aFault = 'json' then
    Result := '{';
end;

procedure TSignatureCommandTests.InvalidRequestReturnsBlockedReport(const aFault: string);
var
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lReport: TJSONObject;
begin
  lFixture := CreateSignatureFixture;
  TFile.WriteAllText(lFixture.fRequest, InvalidSignatureRequest(aFault), TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  lReport := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lReport);
    Assert.AreEqual(Cardinal(3), lExit, lReport.ToJSON);
    Assert.AreEqual(1, lReport.GetValue<Integer>('schemaVersion'));
    Assert.AreEqual('blocked', lReport.GetValue<string>('status'));
    Assert.IsFalse((lReport.GetValue('applicable') as TJSONBool).AsBoolean);
    Assert.IsFalse((lReport.FindValue('scope.complete') as TJSONBool).AsBoolean);
    Assert.IsTrue(lReport.GetValue<TJSONArray>('diagnostics').Count > 0);
    Assert.AreEqual(0, lReport.GetValue<TJSONArray>('artifacts').Count);
    Assert.AreEqual(lFixture.fSourceHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
  finally
    lReport.Free;
  end;
end;

procedure TSignatureCommandTests.UnknownSelectorIsExplicitlyIncomplete;
var
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lReport: TJSONObject;
begin
  lFixture := CreateSignatureFixture;
  TFile.WriteAllText(lFixture.fRequest, InvalidSignatureRequest('selector'), TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  lReport := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lReport);
    Assert.AreEqual(Cardinal(3), lExit, lReport.ToJSON);
    Assert.AreEqual('incomplete', lReport.GetValue<string>('status'));
    Assert.AreEqual('unknown', lReport.FindValue('comparison.status').Value);
    Assert.IsFalse((lReport.FindValue('scope.complete') as TJSONBool).AsBoolean);
    Assert.IsFalse((lReport.GetValue('applicable') as TJSONBool).AsBoolean);
    Assert.AreEqual(0, lReport.GetValue<TJSONArray>('artifacts').Count);
    Assert.AreEqual(lFixture.fSourceHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
  finally
    lReport.Free;
  end;
end;

procedure PrepareNativeAlignment(const aFixture: TSignatureFixture);
begin
  TFile.WriteAllText(aFixture.fProject,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>Alignment.dpr</MainSource><Config>Debug</Config>' +
    '<Platform>Win64</Platform><AppType>Console</AppType><FrameworkType>None</FrameworkType>' +
    '<DCC_Namespace>System;Winapi;System.Win</DCC_Namespace>' +
    '<DCC_ExeOutput>.dak\Alignment\bin</DCC_ExeOutput>' +
    '<DCC_DcuOutput>.dak\Alignment\dcu</DCC_DcuOutput></PropertyGroup>' +
    '<ItemGroup><DelphiCompile Include="Alignment.dpr"><MainSource>MainSource</MainSource>' +
    '</DelphiCompile><DCCReference Include="Subject.pas"/></ItemGroup>' +
    '<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets"/></Project>', TEncoding.UTF8);
  TFile.WriteAllText(aFixture.fRequest,
    StringReplace(TFile.ReadAllText(aFixture.fRequest, TEncoding.UTF8),
      '"compare"', '"align"', []), TEncoding.UTF8);
end;

procedure TSignatureCommandTests.BrokenBaselineRetainsNonApplicableAlignmentSuggestion;
var
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lReport: TJSONObject;
  lEdits: TJSONArray;
  lProjectHash, lProgramHash, lProgram: string;
  i: Integer;
begin
  lFixture := CreateSignatureFixture;
  lProgram := TPath.Combine(lFixture.fDirectory, 'Alignment.dpr');
  PrepareNativeAlignment(lFixture);
  lProjectHash := THashSHA2.GetHashStringFromFile(lFixture.fProject);
  lProgramHash := THashSHA2.GetHashStringFromFile(lProgram);
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  lReport := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lReport, 'Alignment must return a structured report');
    Assert.AreEqual('signature.align-implementation', lReport.GetValue<string>('operation'));
    Assert.AreEqual(Cardinal(3), lExit, lReport.ToJSON);
    Assert.AreEqual('repair-suggestion', lReport.GetValue<string>('status'));
    Assert.IsFalse((lReport.GetValue('applicable') as TJSONBool).AsBoolean);
    Assert.AreEqual('failed', lReport.FindValue('buildVerification.status').Value);
    Assert.IsTrue(Pos('E2037', lReport.FindValue('buildVerification').ToJSON) > 0,
      'Retain the actual compiler declaration-mismatch diagnostic');
    lEdits := lReport.GetValue<TJSONArray>('suggestedEdits');
    Assert.IsNotNull(lEdits, 'Keep useful repairs despite a failed baseline');
    Assert.AreEqual(2, lEdits.Count, 'Implementation parameter and its bound body reference');
    for i := 0 to lEdits.Count - 1 do
    begin
      Assert.AreEqual('aOldValue', TJSONObject(lEdits.Items[i]).GetValue<string>('expectedText'));
      Assert.AreEqual('aValue', TJSONObject(lEdits.Items[i]).GetValue<string>('replacementText'));
    end;
    Assert.AreEqual(0, lReport.GetValue<TJSONArray>('artifacts').Count);
    Assert.AreEqual(lFixture.fSourceHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
    Assert.AreEqual(lProjectHash, THashSHA2.GetHashStringFromFile(lFixture.fProject));
    Assert.AreEqual(lProgramHash, THashSHA2.GetHashStringFromFile(lProgram));
  finally
    lReport.Free;
  end;
end;

// DAK-385: when the baseline's log directory cannot be created the compiler never runs; the diagnostic users
// see names that failure instead of reporting a failed baseline only.
procedure TSignatureCommandTests.UnusableLogDirectoryIsNamedInDiagnostic;
var
  lDiagnostic: TJSONValue;
  lExit: Cardinal;
  lFixture: TSignatureFixture;
  lFound: Boolean;
  lMessage: string;
  lReport: TJSONObject;
  lSignatureDir: string;
begin
  lFixture := CreateSignatureFixture;
  PrepareNativeAlignment(lFixture);
  // A file where the signature log folder belongs makes the directory impossible to create.
  lSignatureDir := TPath.Combine(lFixture.fDirectory, '.dak\Alignment\signature');
  ForceDirectories(ExtractFileDir(lSignatureDir));
  TFile.WriteAllText(lSignatureDir, 'not a directory');
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  lReport := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lReport, 'Alignment must return a structured report');
    Assert.AreEqual(Cardinal(3), lExit, lReport.ToJSON);
    Assert.AreEqual('failed', lReport.FindValue('buildVerification.status').Value);
    lFound := False;
    for lDiagnostic in lReport.GetValue<TJSONArray>('diagnostics') do
      if TJSONObject(lDiagnostic).GetValue<string>('reason') = 'build.baseline-failed' then
      begin
        lFound := True;
        lMessage := TJSONObject(lDiagnostic).GetValue<string>('message');
        Assert.IsTrue(lMessage.Contains('DAK working directory could not be created under ' + lSignatureDir),
          lMessage);
      end;
    Assert.IsTrue(lFound, 'the baseline diagnostic is reported: ' + lReport.ToJSON);
    Assert.AreEqual(lFixture.fSourceHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
  finally
    lReport.Free;
  end;
end;

procedure TSignatureCommandTests.AlignedBaselineReturnsSuccessfulNoChange;
var
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lReport: TJSONObject;
begin
  lFixture := CreateSignatureFixture;
  PrepareNativeAlignment(lFixture);
  TFile.WriteAllText(lFixture.fSource, StringReplace(TFile.ReadAllText(lFixture.fSource,
    TEncoding.UTF8), 'aOldValue', 'aValue', [rfReplaceAll]), TEncoding.UTF8);
  lFixture.fSourceHash := THashSHA2.GetHashStringFromFile(lFixture.fSource);
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  lReport := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lReport);
    Assert.AreEqual(Cardinal(0), lExit, lReport.ToJSON);
    Assert.AreEqual('no-change', lReport.GetValue<string>('status'));
    Assert.AreEqual('passed', lReport.FindValue('buildVerification.status').Value);
    Assert.AreEqual(0, lReport.GetValue<TJSONArray>('suggestedEdits').Count);
    Assert.AreEqual(0, lReport.FindValue('summary.editCount').GetValue<Integer>);
    Assert.AreEqual(lFixture.fSourceHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
  finally
    lReport.Free;
  end;
end;

procedure TSignatureCommandTests.BuildHookInvalidatesAlignmentSuggestion;
var
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lReport: TJSONObject;
  lText: string;
begin
  lFixture := CreateSignatureFixture;
  PrepareNativeAlignment(lFixture);
  lText := TFile.ReadAllText(lFixture.fProject, TEncoding.UTF8);
  lText := StringReplace(lText, '</Project>',
    '<Target Name="ChangeAlignmentInput" BeforeTargets="_PasCoreCompile"><WriteLinesToFile File="$(MSBuildProjectDirectory)\Subject.pas"' +
    ' Lines="// build hook changed input" Overwrite="false"/></Target></Project>', []);
  TFile.WriteAllText(lFixture.fProject, lText, TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.IsTrue(Pos('// build hook changed input', TFile.ReadAllText(lFixture.fSource,
    TEncoding.UTF8)) > 0, 'The real build hook must run and its bytes must be preserved');
  lReport := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lReport);
    Assert.AreEqual(Cardinal(3), lExit, lReport.ToJSON);
    Assert.AreEqual('blocked', lReport.GetValue<string>('status'));
    Assert.IsTrue(Pos('build.inputs-changed', lReport.ToJSON) > 0, lReport.ToJSON);
    Assert.IsFalse((lReport.GetValue('applicable') as TJSONBool).AsBoolean);
    Assert.IsFalse((lReport.FindValue('scope.complete') as TJSONBool).AsBoolean);
    Assert.AreEqual(0, lReport.GetValue<TJSONArray>('suggestedEdits').Count);
    Assert.AreEqual(0, lReport.GetValue<TJSONArray>('artifacts').Count);
  finally
    lReport.Free;
  end;
end;

procedure TSignatureCommandTests.PublishesAndRevalidatesNoChangeArtifact;
var
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lReport: TJSONObject;
  lPlan, lHash: string;
begin
  lFixture := CreateSignatureFixture;
  PrepareNativeAlignment(lFixture);
  TFile.WriteAllText(lFixture.fSource, StringReplace(TFile.ReadAllText(lFixture.fSource,
    TEncoding.UTF8), 'aOldValue', 'aValue', [rfReplaceAll]), TEncoding.UTF8);
  lPlan := TPath.Combine(lFixture.fDirectory, 'plan.json');
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) + ' --plan-out ' + QuoteArg(lPlan) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(Cardinal(0), lExit, ReadUtf8TextFile(lFixture.fLog));
  Assert.IsTrue(TFile.Exists(lPlan), 'Successful no-change planning can retain an exact artifact');
  lReport := TJSONObject.ParseJSONValue(TFile.ReadAllText(lPlan, TEncoding.UTF8)) as TJSONObject;
  try
    Assert.IsNotNull(lReport);
    Assert.AreEqual('signature.align-implementation', lReport.GetValue<string>('operation'));
    Assert.AreEqual('no-change', lReport.GetValue<string>('status'));
    Assert.IsTrue((lReport.FindValue('verification.sameIntentFeatureReplan') as TJSONBool).AsBoolean);
  finally
    lReport.Free;
  end;
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lFixture.fProject) +
    ' --apply-plan ' + QuoteArg(lPlan) + ' --config Debug --platform Win64 --delphi 23.0',
    lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(Cardinal(0), lExit, ReadUtf8TextFile(lFixture.fLog));
  TFile.AppendAllText(lFixture.fSource, '// changed after planning'#13#10, TEncoding.UTF8);
  lHash := THashSHA2.GetHashStringFromFile(lFixture.fSource);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lFixture.fProject) +
    ' --apply-plan ' + QuoteArg(lPlan) + ' --config Debug --platform Win64 --delphi 23.0',
    lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(Cardinal(3), lExit, ReadUtf8TextFile(lFixture.fLog));
  Assert.IsTrue(Pos('artifact.stale-context', ReadUtf8TextFile(lFixture.fLog)) > 0);
  Assert.AreEqual(lHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
end;

procedure TSignatureCommandTests.RefusedArtifactOutputPreservesFiles(const aFault: string);
var
  g: TGarbos;
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lPlan, lHash: string;
  lReport: TJSONObject;
begin
  lFixture := CreateSignatureFixture;
  PrepareNativeAlignment(lFixture);
  TFile.WriteAllText(lFixture.fSource, StringReplace(TFile.ReadAllText(lFixture.fSource,
    TEncoding.UTF8), 'aOldValue', 'aValue', [rfReplaceAll]), TEncoding.UTF8);
  lHash := THashSHA2.GetHashStringFromFile(lFixture.fSource);
  lPlan := TPath.Combine(lFixture.fDirectory, 'plan.json');
  if aFault = 'existing' then
    TFile.WriteAllText(lPlan, 'keep existing bytes', TEncoding.UTF8)
  else
    TFile.WriteAllText(lFixture.fRequest, StringReplace(TFile.ReadAllText(lFixture.fRequest,
      TEncoding.UTF8), '"align"', '"compare"', []), TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) + ' --plan-out ' + QuoteArg(lPlan) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(Cardinal(3), lExit, ReadUtf8TextFile(lFixture.fLog));
  lReport := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  GC(lReport, g);
  Assert.IsNotNull(lReport);
  Assert.AreEqual('blocked', lReport.GetValue<string>('status'));
  Assert.IsFalse(lReport.GetValue<Boolean>('scope.complete'));
  Assert.IsFalse(lReport.GetValue<Boolean>('applicable'));
  Assert.AreEqual(0, lReport.GetValue<TJSONArray>('artifacts').Count);
  Assert.AreEqual(lHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
  if aFault = 'existing' then
  begin
    Assert.AreEqual('keep existing bytes', TFile.ReadAllText(lPlan, TEncoding.UTF8));
    Assert.IsTrue(ReadUtf8TextFile(lFixture.fLog).Contains('artifact.output-not-new'));
  end else begin
    Assert.IsFalse(TFile.Exists(lPlan));
    Assert.IsTrue(ReadUtf8TextFile(lFixture.fLog).Contains('request.plan-requires-align'));
  end;
end;

procedure TSignatureCommandTests.InvalidRequestBytesAreBlocked(const aFault: string);
var
  g: TGarbos;
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lBytes: TBytes;
  lReport: TJSONObject;
begin
  lFixture := CreateSignatureFixture;
  if aFault = 'oversized' then
    TFile.AppendAllText(lFixture.fRequest, StringOfChar(' ', 65536), TEncoding.UTF8)
  else
  begin
    lBytes := TFile.ReadAllBytes(lFixture.fRequest);
    SetLength(lBytes, Length(lBytes) + 1);
    lBytes[High(lBytes)] := $FF;
    TFile.WriteAllBytes(lFixture.fRequest, lBytes);
  end;
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(Cardinal(3), lExit, ReadUtf8TextFile(lFixture.fLog));
  lReport := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  GC(lReport, g);
  Assert.IsNotNull(lReport);
  Assert.AreEqual('blocked', lReport.GetValue<string>('status'));
  Assert.IsTrue(lReport.ToJSON.Contains('request.invalid'), lReport.ToJSON);
  Assert.AreEqual(lFixture.fSourceHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
end;

procedure TSignatureCommandTests.TamperedAlignmentArtifactDoesNotApply(const aFault: string);
var
  g: TGarbos;
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lPlan, lHash: string;
  lArtifact, lRequest: TJSONObject;
begin
  lFixture := CreateSignatureFixture;
  PrepareNativeAlignment(lFixture);
  TFile.WriteAllText(lFixture.fSource, StringReplace(TFile.ReadAllText(lFixture.fSource,
    TEncoding.UTF8), 'aOldValue', 'aValue', [rfReplaceAll]), TEncoding.UTF8);
  lHash := THashSHA2.GetHashStringFromFile(lFixture.fSource);
  lPlan := TPath.Combine(lFixture.fDirectory, 'plan.json');
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) + ' --plan-out ' + QuoteArg(lPlan) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(Cardinal(0), lExit, ReadUtf8TextFile(lFixture.fLog));
  lArtifact := TJSONObject.ParseJSONValue(TFile.ReadAllText(lPlan, TEncoding.UTF8)) as TJSONObject;
  GC(lArtifact, g);
  Assert.IsNotNull(lArtifact);
  if aFault = 'context' then
  begin
    lArtifact.RemovePair('contextFingerprint').Free;
    lArtifact.AddPair('contextFingerprint', 'forged');
  end else begin
    lRequest := lArtifact.GetValue<TJSONObject>('request');
    lRequest.RemovePair('operation').Free;
    lRequest.AddPair('operation', 'compare');
  end;
  TFile.WriteAllText(lPlan, lArtifact.ToJSON, TEncoding.UTF8);
  Assert.IsTrue(RunResolverProcess('refactor-apply --project ' + QuoteArg(lFixture.fProject) +
    ' --apply-plan ' + QuoteArg(lPlan) + ' --config Debug --platform Win64 --delphi 23.0',
    lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(Cardinal(3), lExit, ReadUtf8TextFile(lFixture.fLog));
  if aFault = 'context' then
    Assert.IsTrue(ReadUtf8TextFile(lFixture.fLog).Contains('artifact.stale-context'))
  else
    Assert.IsTrue(ReadUtf8TextFile(lFixture.fLog).Contains('request.operation-unsupported'));
  Assert.AreEqual(lHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
end;

procedure TSignatureCommandTests.FailedBaselineDoesNotPublishArtifact;
var
  lFixture: TSignatureFixture;
  lExit: Cardinal;
  lReport: TJSONObject;
  lPlan: string;
begin
  lFixture := CreateSignatureFixture;
  PrepareNativeAlignment(lFixture);
  lPlan := TPath.Combine(lFixture.fDirectory, 'plan.json');
  Assert.IsTrue(RunResolverProcess('signature --project ' + QuoteArg(lFixture.fProject) +
    ' --request ' + QuoteArg(lFixture.fRequest) + ' --plan-out ' + QuoteArg(lPlan) +
    ' --config Debug --platform Win64 --delphi 23.0 --format json',
    lFixture.fDirectory, lFixture.fLog, lExit));
  Assert.AreEqual(Cardinal(3), lExit, ReadUtf8TextFile(lFixture.fLog));
  lReport := TJSONObject.ParseJSONValue(ReadUtf8TextFile(lFixture.fLog)) as TJSONObject;
  try
    Assert.IsNotNull(lReport);
    Assert.AreEqual('repair-suggestion', lReport.GetValue<string>('status'));
    Assert.AreEqual(2, lReport.GetValue<TJSONArray>('suggestedEdits').Count);
    Assert.AreEqual(0, lReport.GetValue<TJSONArray>('artifacts').Count);
    Assert.IsFalse(TFile.Exists(lPlan));
    Assert.AreEqual(lFixture.fSourceHash, THashSHA2.GetHashStringFromFile(lFixture.fSource));
  finally
    lReport.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSignatureCommandTests);

end.
