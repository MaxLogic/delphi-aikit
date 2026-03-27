unit Test.DfmCheck;

interface

uses
  DUnitX.TestFramework,
  System.Classes, System.IniFiles, System.IOUtils, System.RegularExpressions, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  Dak.DfmCheck, Dak.Types,
  Test.Support;

type
  TMockValidatorMode = (vmHappy, vmHappyParentBin, vmBroken, vmBrokenEventSignature, vmBuildFailGeneratedUnit,
    vmValidatorNonZeroNoFail);

  TMockDfmCheckRunner = class(TInterfacedObject, IDfmCheckProcessRunner)
  private
    fGeneratedDproj: string;
    fConfig: string;
    fMsBuildArguments: string;
    fMode: TMockValidatorMode;
    fPlatform: string;
    fRunCount: Integer;
    fValidatorArguments: string;
    function ReadFirstArg(const aArguments: string): string;
    function TryExtractLogFilePath(const aArguments: string; out aLogPath: string): Boolean;
    function TryReadMsBuildArgsFromBuildCmd(const aBuildCmdPath: string; out aMsBuildArgs: string;
      out aBuildLogPath: string): Boolean;
    function TrimMatchingQuotes(const aValue: string): string;
    procedure WriteValidatorLog(const aLogPath: string; const aLines: TArray<string>);
  public
    constructor Create(const aMode: TMockValidatorMode; const aConfig: string; const aPlatform: string);
    function Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
      const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
    property MsBuildArguments: string read fMsBuildArguments;
    property RunCount: Integer read fRunCount;
    property ValidatorArguments: string read fValidatorArguments;
  end;

  [TestFixture]
  TDfmCheckTests = class
  private
    procedure WriteInjectStubs(const aInjectDir: string);
    procedure CreateFixtureProject(out aProjectDproj: string);
    procedure CreateFixtureProjectWithInheritedSearchPath(out aProjectDproj: string);
    function JoinOutput(const aLines: TStrings): string;
  public
    [Test]
    procedure ResolveProjectPathMapsDprToSiblingDproj;
    [Test]
    procedure BuildExpectedPathsIsDeterministic;
    [Test]
    procedure ResolveBundledInjectDirWalksUpToAncestorToolsInject;
    [Test]
    procedure ResolveBundledInjectDirFallsBackToAncestorDocsInject;
    [Test]
    procedure PatchDprIsIdempotentAndPreservesSyntax;
    [Test]
    procedure PatchDprRewritesProgramNameAndRemovesMadExceptConditional;
    [Test]
    procedure PatchDprRewritesProgramNameWithUtf8Bom;
    [Test]
    procedure PatchDprInjectsAtMainBeginNotNestedBegin;
    [Test]
    procedure MapExitCodePropagatesToolAndCategoryCodes;
    [Test]
    procedure PipelineHappyPathWithMockRunner;
    [Test]
    procedure PipelineAddsUnitSearchPathWhenProjectInheritsOptsetSearchPath;
    [Test]
    procedure PipelineGeneratedRegisterPreservesNamespacedUnitNames;
    [Test]
    procedure PipelineBrokenDfmPropagatesValidatorExitAndFailText;
    [Test]
    procedure PipelineBrokenEventSignaturePropagatesValidatorExitAndFailText;
    [Test]
    procedure DfmCheckFailureIncludesResolvedSourceContextWhenPascalLocationIsKnown;
    [Test]
    procedure DfmCheckWarnsOnInvalidDiagnosticsIniValues;
    [Test]
    procedure PipelineBuildFailureInGeneratedUnitIsClassifiedAsGeneratorIncompatibility;
    [Test]
    procedure PipelineBuildFailureCleansGeneratedArtifactsByDefault;
    [Test]
    procedure PipelinePassesSelectedDfmFilterToValidator;
    [Test]
    procedure PipelineFindsValidatorExeInParentBin;
    [Test]
    procedure PipelineCleansGeneratedArtifactsByDefault;
    [Test]
    procedure PipelineAllModeCacheSkipsUnchangedDfmValidation;
    [Test]
    procedure PipelineAllModeCacheSkipsUpdateOnValidatorFailureWithoutFailLines;
    [Test]
    procedure PipelineAllModeUsesProgressWithoutQuietValidator;
    [Test]
    procedure IntegrationWrongEventSignatureProducesDfmFailure;
  end;

implementation

constructor TMockDfmCheckRunner.Create(const aMode: TMockValidatorMode; const aConfig: string; const aPlatform: string);
begin
  inherited Create;
  fMode := aMode;
  fConfig := aConfig;
  fPlatform := aPlatform;
  fRunCount := 0;
  fValidatorArguments := '';
end;

function TMockDfmCheckRunner.ReadFirstArg(const aArguments: string): string;
var
  lArgs: string;
  lPos: Integer;
begin
  lArgs := Trim(aArguments);
  if lArgs = '' then
    Exit('');
  if lArgs[1] = '"' then
  begin
    lPos := PosEx('"', lArgs, 2);
    if lPos > 1 then
      Exit(Copy(lArgs, 2, lPos - 2));
  end;
  lPos := Pos(' ', lArgs);
  if lPos > 0 then
    Result := Copy(lArgs, 1, lPos - 1)
  else
    Result := lArgs;
end;

function TMockDfmCheckRunner.TrimMatchingQuotes(const aValue: string): string;
var
  lValue: string;
begin
  lValue := Trim(aValue);
  if Length(lValue) >= 2 then
  begin
    if ((lValue[1] = '"') and (lValue[Length(lValue)] = '"')) or
      ((lValue[1] = '''') and (lValue[Length(lValue)] = '''')) then
      lValue := Copy(lValue, 2, Length(lValue) - 2);
  end;
  Result := Trim(lValue);
end;

function TMockDfmCheckRunner.TryReadMsBuildArgsFromBuildCmd(const aBuildCmdPath: string; out aMsBuildArgs: string;
  out aBuildLogPath: string): Boolean;
var
  lCmdLine: string;
  lCommandPart: string;
  lLines: TStringList;
  lLogPart: string;
  lRedirectPos: Integer;
  lTailPos: Integer;
  lText: string;
begin
  aMsBuildArgs := '';
  aBuildLogPath := '';
  if not FileExists(aBuildCmdPath) then
    Exit(False);

  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aBuildCmdPath, TEncoding.Default);
    for lText in lLines do
    begin
      lCmdLine := Trim(lText);
      if lCmdLine = '' then
        Continue;
      if StartsText('@echo off', LowerCase(lCmdLine)) then
        Continue;
      if StartsText('exit /b', LowerCase(lCmdLine)) then
        Continue;
      if Pos('msbuild', LowerCase(lCmdLine)) > 0 then
        Break;
      lCmdLine := '';
    end;
  finally
    lLines.Free;
  end;
  if lCmdLine = '' then
    Exit(False);

  lRedirectPos := Pos(' > ', lCmdLine);
  if lRedirectPos <= 0 then
    Exit(False);
  lCommandPart := Trim(Copy(lCmdLine, 1, lRedirectPos - 1));
  lLogPart := Trim(Copy(lCmdLine, lRedirectPos + 3, MaxInt));
  lTailPos := Pos(' 2>&1', lLogPart);
  if lTailPos > 0 then
    lLogPart := Trim(Copy(lLogPart, 1, lTailPos - 1));
  aBuildLogPath := TrimMatchingQuotes(lLogPart);

  if (lCommandPart <> '') and (lCommandPart[1] = '"') then
  begin
    lTailPos := PosEx('"', lCommandPart, 2);
    if lTailPos <= 0 then
      Exit(False);
    aMsBuildArgs := Trim(Copy(lCommandPart, lTailPos + 1, MaxInt));
  end else
  begin
    lTailPos := Pos(' ', lCommandPart);
    if lTailPos <= 0 then
      Exit(False);
    aMsBuildArgs := Trim(Copy(lCommandPart, lTailPos + 1, MaxInt));
  end;
  Result := aMsBuildArgs <> '';
end;

function TMockDfmCheckRunner.TryExtractLogFilePath(const aArguments: string; out aLogPath: string): Boolean;
var
  lEndQuote: Integer;
  lInlineMatch: TMatch;
  lSplitIndex: Integer;
  lTail: string;
begin
  aLogPath := '';
  lInlineMatch := TRegEx.Match(aArguments, '--log-file=("([^"]+)"|(\S+))', [roIgnoreCase]);
  if lInlineMatch.Success then
  begin
    if lInlineMatch.Groups[2].Value <> '' then
      aLogPath := lInlineMatch.Groups[2].Value
    else
      aLogPath := lInlineMatch.Groups[3].Value;
    Exit(Trim(aLogPath) <> '');
  end;

  lSplitIndex := Pos('--log-file', LowerCase(aArguments));
  if lSplitIndex <= 0 then
    Exit(False);
  lTail := Trim(Copy(aArguments, lSplitIndex + Length('--log-file'), MaxInt));
  if lTail = '' then
    Exit(False);
  if lTail[1] = '=' then
    lTail := Trim(Copy(lTail, 2, MaxInt));
  if lTail = '' then
    Exit(False);
  if lTail[1] = '"' then
  begin
    lEndQuote := PosEx('"', lTail, 2);
    if lEndQuote > 1 then
      aLogPath := Copy(lTail, 2, lEndQuote - 2)
    else
      aLogPath := TrimMatchingQuotes(lTail);
  end else
    aLogPath := TrimMatchingQuotes(lTail.Split([' '])[0]);
  Result := aLogPath <> '';
end;

procedure TMockDfmCheckRunner.WriteValidatorLog(const aLogPath: string; const aLines: TArray<string>);
var
  lLog: TStringList;
  lLine: string;
begin
  if Trim(aLogPath) = '' then
    Exit;
  lLog := TStringList.Create;
  try
    for lLine in aLines do
      lLog.Add(lLine);
    lLog.SaveToFile(aLogPath, TEncoding.UTF8);
  finally
    lLog.Free;
  end;
end;

function TMockDfmCheckRunner.Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
  const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
var
  lBuildArgs: string;
  lBuildLogPath: string;
  lDprojPath: string;
  lLogPath: string;
  lValidatorExePath: string;
  lValidatorLines: TArray<string>;
  lValidatorDir: string;
begin
  Result := True;
  aError := '';
  aExitCode := 0;
  Inc(fRunCount);

  if fRunCount = 1 then
  begin
    lBuildArgs := aArguments;
    lBuildLogPath := '';
    if SameText(TPath.GetExtension(aExePath), '.cmd') then
    begin
      if not TryReadMsBuildArgsFromBuildCmd(aExePath, lBuildArgs, lBuildLogPath) then
      begin
        aError := 'Mock expected build cmd file to contain msbuild invocation.';
        Exit(False);
      end;
    end;

    fMsBuildArguments := lBuildArgs;
    lDprojPath := ReadFirstArg(lBuildArgs);
    if lDprojPath = '' then
    begin
      aError := 'Mock expected generated dproj as first msbuild argument.';
      Exit(False);
    end;
    fGeneratedDproj := lDprojPath;

    if fMode = TMockValidatorMode.vmBuildFailGeneratedUnit then
    begin
      if lBuildLogPath <> '' then
        TFile.WriteAllText(lBuildLogPath,
          'Sample_DfmCheck_Register.pas(42): error E2003: Undeclared identifier: ''TMainForm''' + #13#10 +
          'Sample_DfmCheck.dpr(88): error F2063: Could not compile used unit ''Sample_DfmCheck_Register.pas''' +
          #13#10, TEncoding.UTF8);
      aExitCode := 1;
      Exit(True);
    end;

    if lBuildLogPath <> '' then
      TFile.WriteAllText(lBuildLogPath, '', TEncoding.UTF8);
    if fMode = TMockValidatorMode.vmHappyParentBin then
      lValidatorDir := TPath.Combine(TPath.Combine(TPath.Combine(ExtractFileDir(aWorkingDir), 'Bin'), fPlatform), fConfig)
    else
      lValidatorDir := TPath.Combine(TPath.Combine(aWorkingDir, fPlatform), fConfig);
    TDirectory.CreateDirectory(lValidatorDir);
    lValidatorExePath := TPath.Combine(lValidatorDir, TPath.GetFileNameWithoutExtension(lDprojPath) + '.exe');
    TFile.WriteAllText(lValidatorExePath, 'mock', TEncoding.ASCII);
    Exit(True);
  end;

  if fRunCount = 2 then
  begin
    fValidatorArguments := aArguments;
    SetLength(lValidatorLines, 0);
    if Assigned(aOutput) then
    begin
      if fMode = TMockValidatorMode.vmBroken then
      begin
        aOutput('FAIL MAINFORM -> EReadError: Property FullRowSelect does not exist');
        lValidatorLines := ['FAIL MAINFORM -> EReadError: Property FullRowSelect does not exist',
          'DFM stream validation summary: streamed=1 skipped=0 failed=1 requested=1 matched=1'];
      end
      else if fMode = TMockValidatorMode.vmBrokenEventSignature then
      begin
        aOutput('FAIL MAINFORM -> EReadError: Error reading MainForm.OnCreate: Type mismatch for method ''FormCreate''');
        lValidatorLines := ['FAIL MAINFORM -> EReadError: Error reading MainForm.OnCreate: Type mismatch for method ''FormCreate''',
          'DFM stream validation summary: streamed=1 skipped=0 failed=1 requested=1 matched=1'];
      end
      else if fMode = TMockValidatorMode.vmValidatorNonZeroNoFail then
      begin
        aOutput('FATAL INIT -> EAccessViolation: Access violation at address 00000000');
        lValidatorLines := ['FATAL INIT -> EAccessViolation: Access violation at address 00000000'];
      end else
      begin
        aOutput('OK   MAINFORM');
        lValidatorLines := ['OK   MAINFORM', 'DFM stream validation summary: streamed=1 skipped=0 failed=0 requested=1 matched=1'];
      end;
    end else
    begin
      if fMode = TMockValidatorMode.vmBroken then
        lValidatorLines := ['FAIL MAINFORM -> EReadError: Property FullRowSelect does not exist',
          'DFM stream validation summary: streamed=1 skipped=0 failed=1 requested=1 matched=1']
      else if fMode = TMockValidatorMode.vmBrokenEventSignature then
        lValidatorLines := ['FAIL MAINFORM -> EReadError: Error reading MainForm.OnCreate: Type mismatch for method ''FormCreate''',
          'DFM stream validation summary: streamed=1 skipped=0 failed=1 requested=1 matched=1']
      else if fMode = TMockValidatorMode.vmValidatorNonZeroNoFail then
        lValidatorLines := ['FATAL INIT -> EAccessViolation: Access violation at address 00000000']
      else
        lValidatorLines := ['OK   MAINFORM', 'DFM stream validation summary: streamed=1 skipped=0 failed=0 requested=1 matched=1'];
    end;
    if TryExtractLogFilePath(aArguments, lLogPath) then
      WriteValidatorLog(lLogPath, lValidatorLines);

    if (fMode = TMockValidatorMode.vmBroken) or (fMode = TMockValidatorMode.vmBrokenEventSignature) or
      (fMode = TMockValidatorMode.vmValidatorNonZeroNoFail) then
      aExitCode := 1
    else
      aExitCode := 0;
    Exit(True);
  end;

  aError := Format('Unexpected Run invocation #%d (exe=%s args=%s cwd=%s)', [fRunCount, aExePath, aArguments,
    aWorkingDir]);
  Result := False;
end;

procedure TDfmCheckTests.WriteInjectStubs(const aInjectDir: string);
begin
  TDirectory.CreateDirectory(aInjectDir);
  TFile.WriteAllText(TPath.Combine(aInjectDir, 'DfmStreamAll.pas'),
    'unit DfmStreamAll; interface implementation end.', TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(aInjectDir, 'DfmCheckRuntimeGuard.pas'),
    'unit DfmCheckRuntimeGuard; interface implementation end.', TEncoding.UTF8);
end;

procedure TDfmCheckTests.CreateFixtureProject(out aProjectDproj: string);
var
  lDprPath: string;
  lMainFormDfmPath: string;
  lMainFormPasPath: string;
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'dfm-check-fixture');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  aProjectDproj := TPath.Combine(lRoot, 'Sample.dproj');
  lDprPath := TPath.ChangeExtension(aProjectDproj, '.dpr');
  lMainFormPasPath := TPath.Combine(lRoot, 'MainForm.pas');
  lMainFormDfmPath := TPath.Combine(lRoot, 'MainForm.dfm');

  TFile.WriteAllText(aProjectDproj,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <MainSource>Sample.dpr</MainSource>' + #13#10 +
    '    <DCC_Define>madExcept;TRACE</DCC_Define>' + #13#10 +
    '    <DCC_UnitSearchPath>$(ProjectRoot)\Units;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '  <ItemGroup>' + #13#10 +
    '    <DCCReference Include="MainForm.pas"/>' + #13#10 +
    '  </ItemGroup>' + #13#10 +
    '  <ProjectExtensions>' + #13#10 +
    '    <BorlandProject>' + #13#10 +
    '      <Delphi.Personality>' + #13#10 +
    '        <Source>' + #13#10 +
    '          <Source Name="MainSource">Sample.dpr</Source>' + #13#10 +
    '        </Source>' + #13#10 +
    '      </Delphi.Personality>' + #13#10 +
    '    </BorlandProject>' + #13#10 +
    '  </ProjectExtensions>' + #13#10 +
    '</Project>' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(TPath.Combine(lRoot, 'dak.ini'),
    '[Build]' + #13#10 +
    'DelphiVersion=23.0' + #13#10, TEncoding.ASCII);

  TFile.WriteAllText(TPath.Combine(lRoot, 'rsvars.bat'),
    '@echo off' + #13#10 +
    'set DAK_TEST_RSVARS=1' + #13#10, TEncoding.ASCII);

  TFile.WriteAllText(lDprPath,
    'program Sample;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  Vcl.Forms,' + #13#10 +
    '  MainForm in ''MainForm.pas'' {MainForm};' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    'end.' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lMainFormPasPath,
    'unit MainForm;' + #13#10 +
    #13#10 +
    'interface' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  System.Classes, Vcl.Forms;' + #13#10 +
    #13#10 +
    'type' + #13#10 +
    '  TMainForm = class(TForm)' + #13#10 +
    '  public' + #13#10 +
    '    procedure FormCreate(Sender: TObject);' + #13#10 +
    '  end;' + #13#10 +
    #13#10 +
    'implementation' + #13#10 +
    #13#10 +
    '{$R *.dfm}' + #13#10 +
    #13#10 +
    'procedure TMainForm.FormCreate(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    'end;' + #13#10 +
    #13#10 +
    'end.' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lMainFormDfmPath,
    'object MainForm: TMainForm' + #13#10 +
    '  Caption = ''MainForm''' + #13#10 +
    'end' + #13#10, TEncoding.UTF8);
end;

procedure TDfmCheckTests.CreateFixtureProjectWithInheritedSearchPath(out aProjectDproj: string);
var
  lDprPath: string;
  lMainFormDfmPath: string;
  lMainFormPasPath: string;
  lOptsetPath: string;
  lRoot: string;
  lSourceDir: string;
begin
  lRoot := TPath.Combine(TempRoot, 'dfm-check-fixture-inherited-search-path');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);
  TDirectory.CreateDirectory(lRoot);

  lSourceDir := TPath.Combine(lRoot, 'src');
  TDirectory.CreateDirectory(lSourceDir);

  aProjectDproj := TPath.Combine(lRoot, 'Sample.dproj');
  lDprPath := TPath.ChangeExtension(aProjectDproj, '.dpr');
  lOptsetPath := TPath.Combine(lRoot, 'Fixture.optset');
  lMainFormPasPath := TPath.Combine(lSourceDir, 'MainForm.pas');
  lMainFormDfmPath := TPath.Combine(lSourceDir, 'MainForm.dfm');

  TFile.WriteAllText(aProjectDproj,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <MainSource>Sample.dpr</MainSource>' + #13#10 +
    '    <DCC_Define>madExcept;TRACE</DCC_Define>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '  <Import Project="Fixture.optset" Condition="Exists(''Fixture.optset'')"/>' + #13#10 +
    '  <ItemGroup>' + #13#10 +
    '    <DCCReference Include="src\MainForm.pas"/>' + #13#10 +
    '  </ItemGroup>' + #13#10 +
    '  <ProjectExtensions>' + #13#10 +
    '    <BorlandProject>' + #13#10 +
    '      <Delphi.Personality>' + #13#10 +
    '        <Source>' + #13#10 +
    '          <Source Name="MainSource">Sample.dpr</Source>' + #13#10 +
    '        </Source>' + #13#10 +
    '      </Delphi.Personality>' + #13#10 +
    '    </BorlandProject>' + #13#10 +
    '  </ProjectExtensions>' + #13#10 +
    '</Project>' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lOptsetPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <DCC_UnitSearchPath>$(ProjectRoot)\Shared;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '</Project>' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(TPath.Combine(lRoot, 'dak.ini'),
    '[Build]' + #13#10 +
    'DelphiVersion=23.0' + #13#10, TEncoding.ASCII);

  TFile.WriteAllText(TPath.Combine(lRoot, 'rsvars.bat'),
    '@echo off' + #13#10 +
    'set DAK_TEST_RSVARS=1' + #13#10, TEncoding.ASCII);

  TFile.WriteAllText(lDprPath,
    'program Sample;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  Vcl.Forms,' + #13#10 +
    '  MainForm in ''src\MainForm.pas'' {MainForm};' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    'end.' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lMainFormPasPath,
    'unit MainForm;' + #13#10 +
    #13#10 +
    'interface' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  System.Classes, Vcl.Forms;' + #13#10 +
    #13#10 +
    'type' + #13#10 +
    '  TMainForm = class(TForm)' + #13#10 +
    '  public' + #13#10 +
    '    procedure FormCreate(Sender: TObject);' + #13#10 +
    '  end;' + #13#10 +
    #13#10 +
    'implementation' + #13#10 +
    #13#10 +
    '{$R *.dfm}' + #13#10 +
    #13#10 +
    'procedure TMainForm.FormCreate(Sender: TObject);' + #13#10 +
    'begin' + #13#10 +
    'end;' + #13#10 +
    #13#10 +
    'end.' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lMainFormDfmPath,
    'object MainForm: TMainForm' + #13#10 +
    '  Caption = ''MainForm''' + #13#10 +
    'end' + #13#10, TEncoding.UTF8);
end;

function TDfmCheckTests.JoinOutput(const aLines: TStrings): string;
begin
  Result := String.Join(#13#10, aLines.ToStringArray);
end;

procedure TDfmCheckTests.ResolveProjectPathMapsDprToSiblingDproj;
var
  lDprojPath: string;
  lResolvedPath: string;
  lError: string;
begin
  CreateFixtureProject(lDprojPath);
  Assert.IsTrue(TryResolveDfmCheckProjectPath(TPath.ChangeExtension(lDprojPath, '.dpr'), lResolvedPath, lError),
    'Expected .dpr input to map to sibling .dproj. Error: ' + lError);
  Assert.AreEqual(lDprojPath, lResolvedPath);
end;

procedure TDfmCheckTests.BuildExpectedPathsIsDeterministic;
var
  lDprojPath: string;
  lPaths: TDfmCheckPaths;
begin
  CreateFixtureProject(lDprojPath);
  lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
  Assert.AreEqual(TPath.Combine(ExtractFilePath(lDprojPath), 'Sample_DfmCheck'),
    ExcludeTrailingPathDelimiter(lPaths.fGeneratedDir));
  Assert.AreEqual(TPath.Combine(lPaths.fGeneratedDir, 'Sample_DfmCheck.dproj'), lPaths.fGeneratedDproj);
  Assert.AreEqual(TPath.Combine(lPaths.fGeneratedDir, 'Sample_DfmCheck.dpr'), lPaths.fGeneratedDpr);
end;

procedure TDfmCheckTests.ResolveBundledInjectDirWalksUpToAncestorToolsInject;
var
  lError: string;
  lExePath: string;
  lExpectedInjectDir: string;
  lResolvedInjectDir: string;
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'dfm-check-bundled-inject-tools');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);

  lExpectedInjectDir := TPath.Combine(lRoot, 'tools\inject');
  WriteInjectStubs(lExpectedInjectDir);
  lExePath := TPath.Combine(lRoot, '_build_verify\tests-after-inject-fix\DelphiAIKit.exe');
  TDirectory.CreateDirectory(ExtractFileDir(lExePath));

  Assert.IsTrue(TryResolveBundledInjectDir(lExePath, lResolvedInjectDir, lError),
    'Expected ancestor tools\\inject to be discovered. Error: ' + lError);
  Assert.AreEqual(ExcludeTrailingPathDelimiter(lExpectedInjectDir), ExcludeTrailingPathDelimiter(lResolvedInjectDir));
end;

procedure TDfmCheckTests.ResolveBundledInjectDirFallsBackToAncestorDocsInject;
var
  lError: string;
  lExePath: string;
  lExpectedInjectDir: string;
  lResolvedInjectDir: string;
  lRoot: string;
begin
  lRoot := TPath.Combine(TempRoot, 'dfm-check-bundled-inject-docs');
  if TDirectory.Exists(lRoot) then
    TDirectory.Delete(lRoot, True);

  lExpectedInjectDir := TPath.Combine(lRoot, 'docs\delphi-dfm-checker\tools\inject');
  WriteInjectStubs(lExpectedInjectDir);
  lExePath := TPath.Combine(lRoot, '_build_verify\tests-after-inject-fix\DelphiAIKit.exe');
  TDirectory.CreateDirectory(ExtractFileDir(lExePath));

  Assert.IsTrue(TryResolveBundledInjectDir(lExePath, lResolvedInjectDir, lError),
    'Expected ancestor docs\\delphi-dfm-checker\\tools\\inject fallback to be discovered. Error: ' + lError);
  Assert.AreEqual(ExcludeTrailingPathDelimiter(lExpectedInjectDir), ExcludeTrailingPathDelimiter(lResolvedInjectDir));
end;

procedure TDfmCheckTests.PatchDprIsIdempotentAndPreservesSyntax;
var
  lInputText: string;
  lPatchedText: string;
  lPatchedTwiceText: string;
  lChanged: Boolean;
  lChangedTwice: Boolean;
  lError: string;
begin
  lInputText :=
    'program Sample_DfmCheck;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  System.SysUtils, Vcl.Forms;' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    '  Application.Initialize;' + #13#10 +
    'end.' + #13#10;

  Assert.IsTrue(TryPatchDfmCheckDpr(lInputText, lPatchedText, lChanged, lError), 'Patch failed: ' + lError);
  Assert.IsTrue(lChanged, 'Expected first patch call to modify the DPR.');
  Assert.IsTrue(Pos('DfmStreamAll,', lPatchedText) > 0, 'Expected DfmStreamAll to be injected into uses clause.');
  Assert.IsTrue(Pos('ExitCode := TDfmStreamAll.Run;', lPatchedText) > 0,
    'Expected ExitCode assignment to be injected before final end.');
  Assert.IsTrue(Pos('Halt(ExitCode);', lPatchedText) > 0,
    'Expected validator short-circuit halt in patched DPR.');
  Assert.IsTrue(Pos('uses', lPatchedText) > 0, 'Expected patched DPR to preserve uses keyword.');
  Assert.IsTrue(Pos(';', lPatchedText) > 0, 'Expected patched DPR to preserve uses syntax.');

  Assert.IsTrue(TryPatchDfmCheckDpr(lPatchedText, lPatchedTwiceText, lChangedTwice, lError),
    'Second patch pass failed: ' + lError);
  Assert.IsFalse(lChangedTwice, 'Expected second patch pass to be idempotent.');
  Assert.AreEqual(lPatchedText, lPatchedTwiceText);
end;

procedure TDfmCheckTests.PatchDprRewritesProgramNameAndRemovesMadExceptConditional;
var
  lChanged: Boolean;
  lError: string;
  lInputText: string;
  lPatchedText: string;
begin
  lInputText :=
    'program Sample;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  Vcl.Forms,' + #13#10 +
    '  {$IFDEF madExcept}' + #13#10 +
    '  madExcept,' + #13#10 +
    '  madLinkDisAsm,' + #13#10 +
    '  madListHardware,' + #13#10 +
    '  {$ENDIF madExcept}' + #13#10 +
    '  MainForm in ''MainForm.pas'' {MainForm};' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    'end.' + #13#10;

  Assert.IsTrue(TryPatchDfmCheckDpr(lInputText, lPatchedText, lChanged, lError,
    'Sample_DfmCheck_Register', 'Sample_DfmCheck'), 'Patch failed: ' + lError);
  Assert.IsTrue(lChanged, 'Expected program declaration and madExcept block rewrite.');
  Assert.IsTrue(ContainsText(lPatchedText, 'program Sample_DfmCheck;'),
    'Expected program declaration to use generated suffix name.');
  Assert.IsFalse(ContainsText(lPatchedText, '{$IFDEF madExcept}'),
    'Expected madExcept compiler conditional to be removed from generated DPR.');
  Assert.IsFalse(ContainsText(lPatchedText, 'madExcept,'),
    'Expected madExcept unit references to be removed from generated DPR.');
  Assert.IsTrue(ContainsText(lPatchedText, 'MainForm in ''MainForm.pas'' {MainForm};'),
    'Expected regular form unit entries to remain in uses clause.');
end;

procedure TDfmCheckTests.PatchDprRewritesProgramNameWithUtf8Bom;
var
  lBom: string;
  lChanged: Boolean;
  lError: string;
  lInputText: string;
  lPatchedText: string;
begin
  lBom := #$FEFF;
  lInputText := lBom +
    'Program Sample;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  Vcl.Forms;' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    'end.' + #13#10;

  Assert.IsTrue(TryPatchDfmCheckDpr(lInputText, lPatchedText, lChanged, lError,
    'Sample_DfmCheck_Register', 'Sample_DfmCheck'), 'Patch failed: ' + lError);
  Assert.IsTrue(lChanged, 'Expected program declaration rewrite for BOM-prefixed DPR.');
  Assert.IsTrue(ContainsText(lPatchedText, 'Program Sample_DfmCheck;'),
    'Expected BOM-prefixed DPR program declaration to be rewritten correctly.');
  Assert.IsFalse(ContainsText(lPatchedText, 'PProgram'),
    'Expected no duplicated leading character in rewritten program declaration.');
end;

procedure TDfmCheckTests.MapExitCodePropagatesToolAndCategoryCodes;
begin
  Assert.AreEqual(3, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecInvalidInput, 0));
  Assert.AreEqual(17, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecDfmCheckFailed, 17));
  Assert.AreEqual(37, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecGeneratorIncompatible, 0));
  Assert.AreEqual(34, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecBuildFailed, 0));
  Assert.AreEqual(9, MapDfmCheckExitCode(TDfmCheckErrorCategory.ecValidatorFailed, 9));
end;

procedure TDfmCheckTests.PatchDprInjectsAtMainBeginNotNestedBegin;
var
  lChanged: Boolean;
  lError: string;
  lIfBeginPos: Integer;
  lInputText: string;
  lInjectedPos: Integer;
  lPatchedText: string;
  lShowNegPos: Integer;
begin
  lInputText :=
    'program Sample_DfmCheck;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  System.SysUtils, Vcl.Forms;' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    '  ShowNeg(mWait);' + #13#10 +
    '  if PrimeInitialization.PerformInitialization then' + #13#10 +
    '  begin' + #13#10 +
    '    Application.CreateForm(TMainForm, MainForm);' + #13#10 +
    '  end;' + #13#10 +
    '  Application.Run;' + #13#10 +
    'end.' + #13#10;

  Assert.IsTrue(TryPatchDfmCheckDpr(lInputText, lPatchedText, lChanged, lError), 'Patch failed: ' + lError);
  Assert.IsTrue(lChanged, 'Expected nested-begin DPR to be patched.');

  lInjectedPos := Pos('ExitCode := TDfmStreamAll.Run;', lPatchedText);
  Assert.IsTrue(lInjectedPos > 0, 'Expected validator injection in patched DPR.');
  lShowNegPos := Pos('ShowNeg(mWait);', lPatchedText);
  Assert.IsTrue(lShowNegPos > 0, 'Expected ShowNeg call in patched DPR.');
  Assert.IsTrue(lInjectedPos < lShowNegPos,
    'Expected validator injection before splash/login initialization statements.');
  lIfBeginPos := Pos('if PrimeInitialization.PerformInitialization then' + #13#10 + '  begin', lPatchedText);
  Assert.IsTrue(lIfBeginPos > 0, 'Expected nested IF begin block to remain unchanged.');
  Assert.IsTrue(lInjectedPos < lIfBeginPos, 'Expected validator injection at main begin, not nested begin.');
end;

procedure TDfmCheckTests.PipelineHappyPathWithMockRunner;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPaths: TDfmCheckPaths;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lInjectedPos: Integer;
  lGeneratedDprojText: string;
  lPatchedDprText: string;
  lGeneratedUnitText: string;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-happy');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected happy mock pipeline to return success.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected error category for happy path.');
    Assert.AreEqual('', lError, 'Did not expect an error message in happy path.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('[dfm-check] Generating DFMCheck project...', lOutputText) > 0,
      'Missing DFMCheck generation stage log.');
    Assert.IsTrue(Pos('[dfm-check] Building generated DfmCheck project via MSBuild...', lOutputText) > 0,
      'Missing MSBuild stage log.');
    Assert.IsTrue(Pos('[dfm-check] Running validator exe...', lOutputText) > 0, 'Missing validator stage log.');
    Assert.IsTrue(Pos('OK   MAINFORM', lOutputText) > 0, 'Expected OK resource output from validator stage.');
    Assert.IsFalse(Pos('NON_DFM', lOutputText) > 0, 'Non-DFM resources should not be emitted in validator output.');
    Assert.IsTrue(Pos('/p:DCC_ForceExecute=true', lRunnerImpl.MsBuildArguments) > 0,
      'Expected forced response-file mode in MSBuild arguments.');
    Assert.IsTrue(Pos('/p:DCC_ExeOutput=', lRunnerImpl.MsBuildArguments) > 0,
      'Expected isolated exe output override in MSBuild arguments.');
    Assert.IsTrue(Pos('/p:DCC_DcuOutput=', lRunnerImpl.MsBuildArguments) > 0,
      'Expected isolated DCU output override in MSBuild arguments.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lPatchedDprText := TFile.ReadAllText(lPaths.fGeneratedDpr);
    Assert.IsTrue(Pos('DfmStreamAll,', lPatchedDprText) > 0, 'Expected DfmStreamAll in patched DPR.');
    Assert.IsTrue(Pos('DfmCheckRuntimeGuard,', lPatchedDprText) > 0,
      'Expected runtime guard unit in generated checker DPR.');
    Assert.IsTrue(Pos('Sample_DfmCheck_Register', lPatchedDprText) > 0,
      'Expected generated register unit in patched DPR uses clause.');
    Assert.IsTrue(Pos('ExitCode := TDfmStreamAll.Run;', lPatchedDprText) > 0,
      'Expected ExitCode assignment in patched DPR.');
    Assert.IsTrue(Pos('Halt(ExitCode);', lPatchedDprText) > 0, 'Expected validator short-circuit halt in DPR.');
    Assert.IsFalse(Pos('Application.Initialize;', lPatchedDprText) > 0,
      'Generated checker DPR must not execute application startup.');
    lInjectedPos := Pos('ExitCode := TDfmStreamAll.Run;', lPatchedDprText);
    Assert.IsTrue(lInjectedPos > 0, 'Expected generated checker DPR to execute validator entrypoint.');

    lGeneratedDprojText := TFile.ReadAllText(lPaths.fGeneratedDproj);
    Assert.IsTrue(Pos('DFMCheck', lGeneratedDprojText) > 0,
      'Generated checker DPROJ should define DFMCheck symbol.');
    Assert.IsTrue(Pos('NO_LOCALIZATION', lGeneratedDprojText) > 0,
      'Generated checker DPROJ should define NO_LOCALIZATION symbol.');
    Assert.IsFalse(Pos('madExcept', lGeneratedDprojText) > 0,
      'Generated checker DPROJ should remove madExcept symbol from defines.');
    Assert.IsTrue(Pos('<Source Name="MainSource">Sample_DfmCheck.dpr</Source>', lGeneratedDprojText) > 0,
      'Generated checker DPROJ should rewrite project extension MainSource entry.');
    Assert.IsTrue(Pos('$(DCC_UnitSearchPath)', lGeneratedDprojText) > 0,
      'Generated checker DPROJ should preserve macro-based search path tokens.');
    Assert.IsTrue(Pos('TRACE', lGeneratedDprojText) > 0,
      'Generated checker DPROJ should preserve unrelated compiler define symbols.');

    lGeneratedUnitText := TFile.ReadAllText(TPath.Combine(lPaths.fProjectDir, 'Sample_DfmCheck_Register.pas'));
    Assert.IsTrue(Pos('unit Sample_DfmCheck_Register;', lGeneratedUnitText) > 0,
      'Expected generated register unit for streaming class registration.');
    Assert.IsTrue(Pos('uses', lGeneratedUnitText) > 0, 'Expected generated register unit to keep form-unit linkage.');
    Assert.IsTrue(Pos('MainForm', lGeneratedUnitText) > 0, 'Expected generated register unit to keep MainForm in uses.');
    Assert.IsTrue(Pos('{$IF Declared(TMainForm)} RegisterClass(TMainForm); {$IFEND}', lGeneratedUnitText) > 0,
      'Expected generated register unit to register root form class for streaming.');
    Assert.IsFalse(Pos('.ClassName;', lGeneratedUnitText) > 0,
      'Generated register unit should not include compile-time ClassName checks.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineAddsUnitSearchPathWhenProjectInheritsOptsetSearchPath;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lGeneratedDprojText: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lSourceDir: string;
begin
  CreateFixtureProjectWithInheritedSearchPath(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-inherited-search-path');
  WriteInjectStubs(lInjectDir);
  lSourceDir := TPath.Combine(ExtractFilePath(lDprojPath), 'src');

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected inherited-search-path fixture to complete with mock runner.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Unexpected error category for inherited-search-path fixture.');
    Assert.AreEqual('', lError, 'Did not expect an error message for inherited-search-path fixture.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lGeneratedDprojText := TFile.ReadAllText(lPaths.fGeneratedDproj);
    Assert.IsTrue(Pos('<DCC_UnitSearchPath>', lGeneratedDprojText) > 0,
      'Generated checker DPROJ should synthesize DCC_UnitSearchPath when source project inherits it from an optset.');
    Assert.IsTrue(Pos(lSourceDir, lGeneratedDprojText) > 0,
      'Generated checker DPROJ should prepend discovered form unit directories.');
    Assert.IsTrue(Pos('$(DCC_UnitSearchPath)', lGeneratedDprojText) > 0,
      'Generated checker DPROJ should still preserve inherited DCC_UnitSearchPath macros.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
  end;
end;

procedure TDfmCheckTests.PipelineGeneratedRegisterPreservesNamespacedUnitNames;
var
  lCategory: TDfmCheckErrorCategory;
  lDprPath: string;
  lDprojPath: string;
  lError: string;
  lGeneratedUnitText: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lNamespacedDfmPath: string;
  lNamespacedPasPath: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lPaths: TDfmCheckPaths;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRoot: string;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lRoot := ExtractFileDir(lDprojPath);
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  lNamespacedPasPath := TPath.Combine(lRoot, 'sd3.WebBrowser.pas');
  lNamespacedDfmPath := TPath.ChangeExtension(lNamespacedPasPath, '.dfm');
  TFile.WriteAllText(lDprPath,
    'program Sample;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  Vcl.Forms,' + #13#10 +
    '  sd3.WebBrowser in ''sd3.WebBrowser.pas'' {Sd3WebBrowserDialog};' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    'end.' + #13#10, TEncoding.UTF8);
  TFile.WriteAllText(lNamespacedPasPath,
    'unit sd3.WebBrowser;' + #13#10 +
    #13#10 +
    'interface' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  System.Classes, Vcl.Forms;' + #13#10 +
    #13#10 +
    'type' + #13#10 +
    '  TSd3WebBrowserDialog = class(TForm)' + #13#10 +
    '  end;' + #13#10 +
    #13#10 +
    'implementation' + #13#10 +
    #13#10 +
    '{$R *.dfm}' + #13#10 +
    #13#10 +
    'end.' + #13#10, TEncoding.UTF8);
  TFile.WriteAllText(lNamespacedDfmPath,
    'object Sd3WebBrowserDialog: TSd3WebBrowserDialog' + #13#10 +
    '  Caption = ''Sd3WebBrowserDialog''' + #13#10 +
    'end' + #13#10, TEncoding.UTF8);

  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-namespaced');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'sd3.WebBrowser.dfm';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected namespaced fixture pipeline to return success.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Unexpected error category for namespaced unit fixture.');
    Assert.AreEqual('', lError, 'Did not expect an orchestration error for namespaced unit fixture.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lGeneratedUnitText := TFile.ReadAllText(TPath.Combine(lPaths.fProjectDir, 'Sample_DfmCheck_Register.pas'));
    Assert.IsTrue(Pos('sd3.WebBrowser', lGeneratedUnitText) > 0,
      'Expected generated register unit uses list to keep namespaced unit names.');
    Assert.IsTrue(Pos(#13#10 + '  WebBrowser,' + #13#10, lGeneratedUnitText) = 0,
      'Generated register unit must not drop namespace prefix from unit name.');
    Assert.IsTrue(Pos(#13#10 + '  WebBrowser;' + #13#10, lGeneratedUnitText) = 0,
      'Generated register unit must not emit stripped terminal unit names.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBrokenDfmPropagatesValidatorExitAndFailText;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-broken');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBroken, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(1, lResult, 'Expected validator non-zero exit to be propagated.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Expected validator failures to propagate exit code without remapping category.');
    Assert.AreEqual('', lError, 'Did not expect orchestration error text for validator-stream failure.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('FAIL MAINFORM -> EReadError: Property FullRowSelect does not exist', lOutputText) > 0,
      'Expected broken DFM FAIL line with streaming exception text.');
    Assert.IsTrue(Pos('pas=', lOutputText) > 0, 'Expected FAIL output to include related PAS file path.');
    Assert.IsTrue(Pos('dfm=', lOutputText) > 0, 'Expected FAIL output to include related DFM file path.');
    Assert.IsTrue(Pos('MainForm.pas', lOutputText) > 0, 'Expected related MainForm.pas path in FAIL output.');
    Assert.IsTrue(Pos('/p:DCC_ForceExecute=true', lRunnerImpl.MsBuildArguments) > 0,
      'Expected forced response-file mode in MSBuild arguments.');
    Assert.IsTrue(Pos('/p:DCC_ExeOutput=', lRunnerImpl.MsBuildArguments) > 0,
      'Expected isolated exe output override in MSBuild arguments.');
    Assert.IsTrue(Pos('/p:DCC_DcuOutput=', lRunnerImpl.MsBuildArguments) > 0,
      'Expected isolated DCU output override in MSBuild arguments.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBrokenEventSignaturePropagatesValidatorExitAndFailText;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-broken-event');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBrokenEventSignature, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(1, lResult, 'Expected validator non-zero exit to be propagated for wrong event signature.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Expected event-signature streaming failures to propagate exit code without remapping category.');
    Assert.AreEqual('', lError, 'Did not expect orchestration error text for event-signature stream failure.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('FAIL MAINFORM -> EReadError:', lOutputText) > 0,
      'Expected FAIL line for event-signature stream failure.');
    Assert.IsTrue(Pos('OnCreate', lOutputText) > 0,
      'Expected streaming exception text to include the failing event property.');
    Assert.IsTrue(Pos('FormCreate', lOutputText) > 0,
      'Expected streaming exception text to include the event handler method name.');
    Assert.IsTrue(Pos('[dfm-check] FAIL clue: member=MainForm.OnCreate', lOutputText) > 0,
      'Expected fail clue to include the failing member path.');
    Assert.IsTrue(Pos('[dfm-check] FAIL clue: handler=FormCreate', lOutputText) > 0,
      'Expected fail clue to include the handler name.');
    Assert.IsTrue(Pos('[dfm-check] FAIL clue: handler declaration line=', lOutputText) > 0,
      'Expected fail clue to include handler declaration line.');
    Assert.IsTrue(Pos('procedure TMainForm.FormCreate(Sender: TObject);', lOutputText) > 0,
      'Expected fail clue to include handler declaration signature.');
    Assert.IsTrue(Pos('[dfm-check] FAIL clue: verify handler signature matches event type for OnCreate.', lOutputText) > 0,
      'Expected fail clue to include event-signature guidance.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.DfmCheckFailureIncludesResolvedSourceContextWhenPascalLocationIsKnown;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', nil);
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBrokenEventSignature, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '23.0';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fSourceContextMode := TSourceContextMode.scmOn;
    lOptions.fHasSourceContextMode := True;
    lOptions.fSourceContextLines := 1;
    lOptions.fHasSourceContextLines := True;
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(1, lResult, 'Expected validator non-zero exit to be propagated for wrong event signature.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Expected event-signature streaming failures to propagate exit code without remapping category.');
    Assert.AreEqual('', lError, 'Did not expect orchestration error text for event-signature stream failure.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('source context:', LowerCase(lOutputText)) > 0,
      'Expected fail clue to include resolved source context.');
    Assert.IsTrue(Pos('procedure TMainForm.FormCreate(Sender: TObject);', lOutputText) > 0,
      'Expected fail clue to include the handler declaration line in source context.');
    Assert.IsTrue(Pos('begin', LowerCase(lOutputText)) > 0,
      'Expected fail clue to include surrounding source context lines.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', nil);
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.DfmCheckWarnsOnInvalidDiagnosticsIniValues;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lRoot: string;
begin
  CreateFixtureProject(lDprojPath);
  lRoot := ExtractFileDir(lDprojPath);
  TFile.WriteAllText(TPath.Combine(lRoot, 'dak.ini'),
    '[Build]' + #13#10 +
    'DelphiVersion=23.0' + #13#10 +
    '[Diagnostics]' + #13#10 +
    'SourceContext=autoo' + #13#10 +
    'SourceContextLines=abc' + #13#10, TEncoding.ASCII);

  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-invalid-diagnostics');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(lRoot, 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected happy mock pipeline to succeed with warning-only diagnostics config issue.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected error category for diagnostics warning case.');
    Assert.AreEqual('', lError, 'Did not expect orchestration error text for diagnostics warning case.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('[dfm-check] Warning: Invalid dak.ini SourceContext value: autoo', lOutputText) > 0,
      'Expected invalid SourceContext warning in dfm-check output. Output: ' + lOutputText);
    Assert.IsTrue(Pos('[dfm-check] Warning: Invalid dak.ini SourceContextLines value: abc', lOutputText) > 0,
      'Expected invalid SourceContextLines warning in dfm-check output. Output: ' + lOutputText);
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBuildFailureInGeneratedUnitIsClassifiedAsGeneratorIncompatibility;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-buildfail');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBuildFailGeneratedUnit, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(1, lResult, 'Expected non-zero build exit code to be propagated.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecGeneratorIncompatible, lCategory,
      'Expected generated checker unit compile failure to map to generator incompatibility.');
    Assert.IsTrue(Pos('generator incompatibility', LowerCase(lError)) > 0,
      'Expected incompatibility diagnostic in error message.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('Sample_DfmCheck_Register.pas(42): error E2003', lOutputText) > 0,
      'Expected generated checker unit compile error in build output.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBuildFailureCleansGeneratedArtifactsByDefault;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lPaths: TDfmCheckPaths;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lKeepArtifactsEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-buildfail-cleanup');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', nil);
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBuildFailGeneratedUnit, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(1, lResult, 'Expected non-zero build exit code to be propagated.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecGeneratorIncompatible, lCategory,
      'Expected generated checker unit compile failure to map to generator incompatibility.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsFalse(FileExists(lPaths.fGeneratedDpr),
      'Expected generated DPR to be cleaned up after build failure when keep-artifacts mode is off.');
    Assert.IsFalse(FileExists(lPaths.fGeneratedDproj),
      'Expected generated DPROJ to be cleaned up after build failure when keep-artifacts mode is off.');
    Assert.IsFalse(FileExists(TPath.Combine(lPaths.fProjectDir, 'Sample_DfmCheck_Register.pas')),
      'Expected generated register unit to be cleaned up after build failure when keep-artifacts mode is off.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelinePassesSelectedDfmFilterToValidator;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-filter');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm, Frames\DetailSubEditDocs.dfm';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected filtered validator run to complete successfully in mock mode.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected error category for filtered validator run.');
    Assert.IsTrue(Pos('--dfm=', lRunnerImpl.ValidatorArguments) > 0,
      'Expected validator invocation to include a --dfm filter argument.');
    Assert.IsTrue(Pos('DETAILSUBEDITDOCS', UpperCase(lRunnerImpl.ValidatorArguments)) > 0,
      'Expected normalized DETAILSUBEDITDOCS resource name in validator filter argument.');
    Assert.IsTrue(Pos('MAINFORM', UpperCase(lRunnerImpl.ValidatorArguments)) > 0,
      'Expected normalized MAINFORM resource name in validator filter argument.');
    Assert.IsFalse(Pos('--all', LowerCase(lRunnerImpl.ValidatorArguments)) > 0,
      'Did not expect --all when an explicit --dfm filter list is provided.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineFindsValidatorExeInParentBin;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-parent-bin');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappyParentBin, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected happy pipeline to find validator exe in parent Bin layout.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected error category for parent Bin layout.');
    Assert.AreEqual('', lError, 'Did not expect an error message for parent Bin layout.');

    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('OK   MAINFORM', lOutputText) > 0, 'Expected validator run output in parent Bin layout.');
    Assert.IsFalse(Pos('Could not find built _DfmCheck.exe', lOutputText) > 0,
      'Did not expect validator-not-found output in parent Bin layout.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineCleansGeneratedArtifactsByDefault;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lPaths: TDfmCheckPaths;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-cleanup');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', nil);
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected cleanup happy path to return success.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected error category for cleanup happy path.');
    Assert.AreEqual('', lError, 'Did not expect an error message in cleanup happy path.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsFalse(FileExists(lPaths.fGeneratedDpr), 'Expected generated DPR to be cleaned up by default.');
    Assert.IsFalse(FileExists(lPaths.fGeneratedDproj), 'Expected generated DPROJ to be cleaned up by default.');
    Assert.IsFalse(FileExists(TPath.Combine(lPaths.fProjectDir, 'Sample_DfmCheck_Register.pas')),
      'Expected generated register unit to be cleaned up by default.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineAllModeCacheSkipsUnchangedDfmValidation;
var
  lCachePath: string;
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunner: IDfmCheckProcessRunner;
  lRunnerFirst: TMockDfmCheckRunner;
  lRunnerSecond: TMockDfmCheckRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-cache');
  WriteInjectStubs(lInjectDir);
  lCachePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Sample.dfmcheck.cache');

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
    lOptions.fDfmCheckAll := True;
    lOptions.fVerbose := True;

    lRunnerFirst := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerFirst;
    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected first all-mode run to pass and populate cache.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected category for first all-mode cache run.');
    Assert.AreEqual('', lError, 'Unexpected error for first all-mode cache run.');
    Assert.IsTrue(FileExists(lCachePath), 'Expected all-mode run to create DFM cache file. Output: ' +
      JoinOutput(lOutputLines));
    Assert.IsTrue(lRunnerFirst.RunCount > 0, 'Expected first run to execute build/validator via runner.');

    lOutputLines.Clear;
    lRunnerSecond := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBuildFailGeneratedUnit, 'Release', 'Win32');
    lRunner := lRunnerSecond;
    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected second all-mode run to skip unchanged DFM validation via cache.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected category for cached all-mode skip.');
    Assert.AreEqual('', lError, 'Did not expect orchestration error for cached all-mode skip.');
    Assert.AreEqual(0, lRunnerSecond.RunCount, 'Expected cached all-mode skip to avoid invoking process runner.');
    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('[dfm-check] Cache: total=1 unchanged=1 validating=0', lOutputText) > 0,
      'Expected cache summary line for unchanged all-mode run.');
    Assert.IsTrue(Pos('[dfm-check] Result: OK', lOutputText) > 0,
      'Expected OK result for cached unchanged all-mode run.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineAllModeCacheSkipsUpdateOnValidatorFailureWithoutFailLines;
var
  lCacheHashAfterFailedRun: string;
  lCacheHashBeforeFailedRun: string;
  lCacheIni: TMemIniFile;
  lCachePath: string;
  lCacheSection: string;
  lCategory: TDfmCheckErrorCategory;
  lDfmPath: string;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunner: IDfmCheckProcessRunner;
  lRunnerFailNoLine: TMockDfmCheckRunner;
  lRunnerFirst: TMockDfmCheckRunner;
  lRunnerThird: TMockDfmCheckRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-cache-no-fail-lines');
  WriteInjectStubs(lInjectDir);
  lCachePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Sample.dfmcheck.cache');
  lCacheSection := 'Unit:MAINFORM';
  lDfmPath := TPath.Combine(ExtractFilePath(lDprojPath), 'MainForm.dfm');

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
    lOptions.fDfmCheckAll := True;
    lOptions.fVerbose := True;

    lRunnerFirst := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerFirst;
    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);
    Assert.AreEqual(0, lResult, 'Expected first all-mode run to pass and populate cache.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected category for first all-mode run.');
    Assert.AreEqual('', lError, 'Unexpected error for first all-mode run.');
    Assert.IsTrue(FileExists(lCachePath), 'Expected first all-mode run to create cache file.');

    lCacheIni := TMemIniFile.Create(lCachePath);
    try
      lCacheHashBeforeFailedRun := lCacheIni.ReadString(lCacheSection, 'DfmHash', '');
    finally
      lCacheIni.Free;
    end;
    Assert.IsTrue(lCacheHashBeforeFailedRun <> '', 'Expected non-empty cached DFM hash after first run.');

    TFile.WriteAllText(lDfmPath,
      'object MainForm: TMainForm' + #13#10 +
      '  Caption = ''MainFormChanged''' + #13#10 +
      'end' + #13#10, TEncoding.UTF8);

    lOutputLines.Clear;
    lRunnerFailNoLine := TMockDfmCheckRunner.Create(TMockValidatorMode.vmValidatorNonZeroNoFail, 'Release', 'Win32');
    lRunner := lRunnerFailNoLine;
    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);
    Assert.AreEqual(1, lResult,
      'Expected failed validator run when non-zero exit occurs without resource-level FAIL lines.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Expected validator non-zero exit to propagate without orchestration remapping.');
    Assert.AreEqual('', lError, 'Did not expect orchestration error text for validator failure path.');
    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('[dfm-check] Cache skipped: validator failed without resource-level FAIL lines.', lOutputText) > 0,
      'Expected cache skip diagnostic for validator failure without resource-level FAIL lines.');

    lCacheIni := TMemIniFile.Create(lCachePath);
    try
      lCacheHashAfterFailedRun := lCacheIni.ReadString(lCacheSection, 'DfmHash', '');
    finally
      lCacheIni.Free;
    end;
    Assert.AreEqual(lCacheHashBeforeFailedRun, lCacheHashAfterFailedRun,
      'Cache hash must remain unchanged when validator failed without resource-level FAIL lines.');

    lOutputLines.Clear;
    lRunnerThird := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerThird;
    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);
    Assert.AreEqual(0, lResult, 'Expected third all-mode run to revalidate and pass.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected category for third all-mode run.');
    Assert.AreEqual('', lError, 'Unexpected error for third all-mode run.');
    Assert.IsTrue(lRunnerThird.RunCount > 0,
      'Expected third all-mode run to execute runner because failed second run must not refresh cache.');
    lOutputText := JoinOutput(lOutputLines);
    Assert.IsTrue(Pos('[dfm-check] Cache: total=1 unchanged=0 validating=1', lOutputText) > 0,
      'Expected cache summary to show validation is required after failed run without FAIL lines.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineAllModeUsesProgressWithoutQuietValidator;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lKeepArtifactsEnv: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lPrevInjectEnv: string;
  lPrevMsBuildEnv: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-all-progress');
  WriteInjectStubs(lInjectDir);

  lPrevInjectEnv := GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lPrevMsBuildEnv := GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD');
  lKeepArtifactsEnv := GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lInjectDir));
  SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar('msbuild.exe'));
  SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar('true'));
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
    lOptions.fDfmCheckAll := True;

    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected all-mode validator run to pass in mock mode.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected all-mode category.');
    Assert.IsFalse(Pos('--quiet', LowerCase(lRunnerImpl.ValidatorArguments)) > 0,
      'All-mode should stream progress and must not force quiet validator output.');
    Assert.IsTrue(Pos('--progress', LowerCase(lRunnerImpl.ValidatorArguments)) > 0,
      'All-mode should include --progress for live CHECK lines.');
  finally
    SetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR', PChar(lPrevInjectEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_MSBUILD', PChar(lPrevMsBuildEnv));
    SetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS', PChar(lKeepArtifactsEnv));
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.IntegrationWrongEventSignatureProducesDfmFailure;
var
  lArgs: string;
  lDfmPath: string;
  lDprPath: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lMainFormPasPath: string;
  lOutputText: string;
  lProjectDir: string;
  lResolverPath: string;
  lRsVarsPath: string;
  lDelphiVersion: string;
begin
  if not SameText(Trim(GetEnvironmentVariable('DAK_DFMCHECK_INTEGRATION')), '1') then
    Assert.Pass('DAK_DFMCHECK_INTEGRATION is not set; skipping dfm-check integration test.');

  lRsVarsPath := Trim(GetEnvironmentVariable('DAK_DFMCHECK_RSVARS'));
  if lRsVarsPath = '' then
    lRsVarsPath := Trim(GetEnvironmentVariable('DAK_RSVARS_BAT'));
  if lRsVarsPath = '' then
    Assert.Pass('DAK_DFMCHECK_RSVARS is not set; skipping dfm-check integration test.');
  if not FileExists(lRsVarsPath) then
    Assert.Pass('Configured rsvars.bat path does not exist: ' + lRsVarsPath);

  EnsureResolverBuilt;
  lResolverPath := ResolverExePath;
  if not FileExists(lResolverPath) then
    Assert.Fail('Resolver exe not found for integration test: ' + lResolverPath);

  lDelphiVersion := Trim(GetEnvironmentVariable('DAK_DFMCHECK_DELPHI'));
  if lDelphiVersion = '' then
    lDelphiVersion := '23.0';

  lProjectDir := TPath.Combine(TempRoot, 'dfm-check-wrong-event-signature');
  if TDirectory.Exists(lProjectDir) then
    TDirectory.Delete(lProjectDir, True);
  TDirectory.CreateDirectory(lProjectDir);

  lDprojPath := TPath.Combine(lProjectDir, 'WrongEventSample.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  lMainFormPasPath := TPath.Combine(lProjectDir, 'MainForm.pas');
  lDfmPath := TPath.Combine(lProjectDir, 'MainForm.dfm');
  lLogPath := TPath.Combine(lProjectDir, 'dfm-check.log');

  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <MainSource>WrongEventSample.dpr</MainSource>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '</Project>' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lDprPath,
    'program WrongEventSample;' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  Vcl.Forms,' + #13#10 +
    '  MainForm in ''MainForm.pas'' {MainForm};' + #13#10 +
    #13#10 +
    '{$R *.res}' + #13#10 +
    #13#10 +
    'begin' + #13#10 +
    '  Application.Initialize;' + #13#10 +
    '  Application.CreateForm(TMainForm, MainForm);' + #13#10 +
    '  Application.Run;' + #13#10 +
    'end.' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lMainFormPasPath,
    'unit MainForm;' + #13#10 +
    #13#10 +
    'interface' + #13#10 +
    #13#10 +
    'uses' + #13#10 +
    '  System.Classes, Vcl.Forms;' + #13#10 +
    #13#10 +
    'type' + #13#10 +
    '  TMainForm = class(TForm)' + #13#10 +
    '    procedure FormCreate(Sender: TObject; badParam: Integer);' + #13#10 +
    '  end;' + #13#10 +
    #13#10 +
    'var' + #13#10 +
    '  MainForm: TMainForm;' + #13#10 +
    #13#10 +
    'implementation' + #13#10 +
    #13#10 +
    '{$R *.dfm}' + #13#10 +
    #13#10 +
    'procedure TMainForm.FormCreate(Sender: TObject; badParam: Integer);' + #13#10 +
    'begin' + #13#10 +
    'end;' + #13#10 +
    #13#10 +
    'end.' + #13#10, TEncoding.UTF8);

  TFile.WriteAllText(lDfmPath,
    'object MainForm: TMainForm' + #13#10 +
    '  OnCreate = FormCreate' + #13#10 +
    'end' + #13#10, TEncoding.UTF8);

  lArgs := 'dfm-check --dproj ' + QuoteArg(lDprojPath) +
    ' --delphi ' + lDelphiVersion +
    ' --config Release --platform Win32 --rsvars ' + QuoteArg(lRsVarsPath);
  Assert.IsTrue(RunProcess(lResolverPath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for dfm-check integration test.');

  if FileExists(lLogPath) then
    lOutputText := TFile.ReadAllText(lLogPath, TEncoding.UTF8)
  else
    lOutputText := '';

  Assert.IsTrue(lExitCode <> 0, 'Expected wrong event signature to produce non-zero dfm-check exit code.');
  Assert.IsTrue(Pos('FAIL ', lOutputText) > 0, 'Expected FAIL line in dfm-check output.');
  Assert.IsTrue((Pos('OnCreate', lOutputText) > 0) or (Pos('FormCreate', lOutputText) > 0),
    'Expected dfm-check output to mention failing event property/handler.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmCheckTests);

end.
