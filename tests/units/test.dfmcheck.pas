unit Test.DfmCheck;

interface

uses
  DUnitX.TestFramework,
  System.Classes, System.IniFiles, System.IOUtils, System.RegularExpressions, System.StrUtils, System.SysUtils,
  System.Variants,
  Winapi.Windows,
  Dak.DfmCheck, Dak.Types,
  Test.Support,
  Xml.XMLDoc, Xml.XMLIntf;

type
  TMockValidatorMode = (vmHappy, vmHappyParentBin, vmBroken, vmBrokenEventSignature,
    vmWarnStandaloneActionImageBinding, vmBuildFailGeneratedUnit, vmBuildFailHighExitCode, vmBuildFailMadExceptLinked,
    vmValidatorNonZeroNoFail);

  TMockDfmCheckRunner = class(TInterfacedObject, IDfmCheckProcessRunner)
  private
    fGeneratedDproj: string;
    fConfig: string;
    fEnvironmentBlocks: TArray<string>;
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
      const aEnvironmentBlock: string; const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal;
      out aError: string): Boolean;
    property MsBuildArguments: string read fMsBuildArguments;
    property EnvironmentBlocks: TArray<string> read fEnvironmentBlocks;
    property RunCount: Integer read fRunCount;
    property ValidatorArguments: string read fValidatorArguments;
  end;

  [TestFixture]
  TDfmCheckTests = class
  private
    procedure WriteInjectStubs(const aInjectDir: string);
    procedure CreateFixtureProject(out aProjectDproj: string);
    procedure CreateFixtureProjectWithInheritedSearchPath(out aProjectDproj: string);
    function GetDfmCheckWorkRoot(const aProjectDproj: string): string;
    function GetSingleChildDirectory(const aParentDir: string): string;
    function JoinOutput(const aLines: TStrings): string;
  public
    [Test]
    procedure ResolveProjectPathMapsDprToSiblingDproj;
    [Test]
    procedure BuildExpectedPathsUseDakWorkspace;
    [Test]
    procedure BundledDfmStreamAllSupportsFrameConstructorFallback;
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
    procedure PipelineGeneratesMadExceptBlockerUnits;
    [Test]
    procedure PipelineAddsUnitSearchPathWhenProjectInheritsOptsetSearchPath;
    [Test]
    procedure PipelineRebasesRelativeProjectImportsForGeneratedProject;
    [Test]
    procedure PipelineRebasesRelativeItemIncludesForGeneratedProject;
    [Test]
    procedure PipelineForcesGeneratedProjectToRunAsInvoker;
    [Test]
    procedure PipelineRebasesSingleQuotedRelativeProjectImportsForGeneratedProject;
    [Test]
    procedure PipelinePreservesBackslashDigitSearchPathsForGeneratedProject;
    [Test]
    procedure PipelinePreservesEffectiveSearchPathForGeneratedProject;
    [Test]
    procedure PipelineKeepsReferenceSourceDirsAfterEffectiveSearchPath;
    [Test]
    procedure PipelineKeepsRepoLocalReferenceSourceDirsAfterEffectiveSearchPath;
    [Test]
    procedure PipelineFailsClosedWhenStrictProjectContextIsUnavailable;
    [Test]
    procedure PipelineStrictContextUsesDefaultConfigPlatform;
    [Test]
    procedure PipelineGeneratedRegisterPreservesNamespacedUnitNames;
    [Test]
    procedure PipelineBrokenDfmPropagatesValidatorExitAndFailText;
    [Test]
    procedure PipelineBrokenEventSignaturePropagatesValidatorExitAndFailText;
    [Test]
    procedure PipelineWarningStandaloneActionImageBindingIsDiagnosedAsFailure;
    [Test]
    procedure DfmCheckFailureIncludesResolvedSourceContextWhenPascalLocationIsKnown;
    [Test]
    procedure DfmCheckWarnsOnInvalidDiagnosticsIniValues;
    [Test]
    procedure DfmCheckWindowCleanupUsesNativeUnsignedStyles;
    [Test]
    procedure PipelineBuildFailureInGeneratedUnitIsClassifiedAsGeneratorIncompatibility;
    [Test]
    procedure PipelineMadExceptBuildFailureExplainsDfmCheckGuards;
    [Test]
    procedure PipelineBuildFailureCleansGeneratedArtifactsByDefault;
    [Test]
    procedure PipelineBuildFailureWithHighExitCodeDoesNotOverflow;
    [Test]
    procedure PipelinePassesSelectedDfmFilterToValidator;
    [Test]
    procedure PipelineFindsValidatorExeInParentBin;
    [Test]
    procedure PipelineKeepArtifactsStoresOwnedRunUnderDakWorkspace;
    [Test]
    procedure PipelinePrunesStaleDakRunsBeforeGeneratingNewWorkspace;
    [Test]
    procedure PipelineCleansGeneratedArtifactsByDefault;
    [Test]
    procedure PipelineAllModeCacheHashingDoesNotOverflowWithDebugChecks;
    [Test]
    procedure DfmCheckCacheWritesAreSerializedAndAtomic;
    [Test]
    procedure PipelineAllModeCacheSkipsUnchangedDfmValidation;
    [Test]
    procedure PipelineAllModeCacheSkipsUpdateOnValidatorFailureWithoutFailLines;
    [Test]
    procedure PipelineBuildTimeoutPreservesDiagnosticsAndSkipsCache;
    [Test]
    procedure PipelineAllModeUsesProgressWithoutQuietValidator;
    [Test]
    procedure IntegrationWrongEventSignatureProducesDfmFailure;
  end;

implementation

function ReadGeneratedDpr(const aPaths: TDfmCheckPaths): string;
begin
  Result := TFile.ReadAllText(aPaths.fGeneratedDpr);
end;

function ReadGeneratedDprojText(const aPaths: TDfmCheckPaths): string;
begin
  Result := TFile.ReadAllText(aPaths.fGeneratedDproj);
end;

function ReadGeneratedRegisterUnit(const aPaths: TDfmCheckPaths): string;
begin
  Result := TFile.ReadAllText(aPaths.fGeneratedRegisterUnit);
end;

function LoadGeneratedDprojXml(const aPaths: TDfmCheckPaths): IXMLDocument;
begin
  Result := TXMLDocument.Create(nil);
  Result.LoadFromXML(ReadGeneratedDprojText(aPaths));
  Result.Active := True;
end;

function XmlNodeNameMatches(const aNode: IXMLNode; const aName: string): Boolean;
var
  lName: string;
begin
  lName := aNode.LocalName;
  if lName = '' then
    lName := aNode.NodeName;
  Result := SameText(lName, aName);
end;

procedure CollectXmlElementTexts(const aNode: IXMLNode; const aName: string; const aValues: TStrings);
var
  i: Integer;
  lNode: IXMLNode;
begin
  if aNode = nil then
    Exit;
  if (aNode.NodeType = ntElement) and XmlNodeNameMatches(aNode, aName) then
    aValues.Add(aNode.Text);

  for i := 0 to aNode.ChildNodes.Count - 1 do
  begin
    lNode := aNode.ChildNodes[i];
    CollectXmlElementTexts(lNode, aName, aValues);
  end;
end;

function DprojElementTextContains(const aDoc: IXMLDocument; const aName: string; const aText: string): Boolean;
var
  i: Integer;
  lValues: TStringList;
begin
  Result := False;
  lValues := TStringList.Create;
  try
    CollectXmlElementTexts(aDoc.DocumentElement, aName, lValues);
    for i := 0 to lValues.Count - 1 do
      if ContainsText(lValues[i], aText) then
        Exit(True);
  finally
    lValues.Free;
  end;
end;

function TextContainsSemicolonToken(const aText: string; const aToken: string): Boolean;
var
  lText: string;
  lToken: string;
begin
  lText := StringReplace(aText, ' ', '', [rfReplaceAll]);
  lText := StringReplace(lText, #9, '', [rfReplaceAll]);
  lToken := StringReplace(aToken, ' ', '', [rfReplaceAll]);
  lToken := StringReplace(lToken, #9, '', [rfReplaceAll]);
  Result := ContainsText(';' + lText + ';', ';' + lToken + ';');
end;

function DprojElementTextHasToken(const aDoc: IXMLDocument; const aName: string; const aToken: string): Boolean;
var
  i: Integer;
  lValues: TStringList;
begin
  Result := False;
  lValues := TStringList.Create;
  try
    CollectXmlElementTexts(aDoc.DocumentElement, aName, lValues);
    for i := 0 to lValues.Count - 1 do
      if TextContainsSemicolonToken(lValues[i], aToken) then
        Exit(True);
  finally
    lValues.Free;
  end;
end;

function DprojElementExists(const aDoc: IXMLDocument; const aName: string): Boolean;
var
  lValues: TStringList;
begin
  lValues := TStringList.Create;
  try
    CollectXmlElementTexts(aDoc.DocumentElement, aName, lValues);
    Result := lValues.Count > 0;
  finally
    lValues.Free;
  end;
end;

function DprojElementTextEquals(const aDoc: IXMLDocument; const aName: string; const aText: string): Boolean;
var
  i: Integer;
  lValues: TStringList;
begin
  Result := False;
  lValues := TStringList.Create;
  try
    CollectXmlElementTexts(aDoc.DocumentElement, aName, lValues);
    for i := 0 to lValues.Count - 1 do
      if SameText(lValues[i], aText) then
        Exit(True);
  finally
    lValues.Free;
  end;
end;

function DprojFirstElementText(const aDoc: IXMLDocument; const aName: string): string;
var
  lValues: TStringList;
begin
  Result := '';
  lValues := TStringList.Create;
  try
    CollectXmlElementTexts(aDoc.DocumentElement, aName, lValues);
    if lValues.Count > 0 then
      Result := lValues[0];
  finally
    lValues.Free;
  end;
end;

function TryFindDprojImportNode(const aNode: IXMLNode; const aProject: string; out aImportNode: IXMLNode): Boolean;
var
  i: Integer;
  lNode: IXMLNode;
begin
  aImportNode := nil;
  if aNode = nil then
    Exit(False);
  if (aNode.NodeType = ntElement) and XmlNodeNameMatches(aNode, 'Import') and
    aNode.HasAttribute('Project') and SameText(VarToStr(aNode.Attributes['Project']), aProject) then
  begin
    aImportNode := aNode;
    Exit(True);
  end;

  for i := 0 to aNode.ChildNodes.Count - 1 do
  begin
    lNode := aNode.ChildNodes[i];
    if TryFindDprojImportNode(lNode, aProject, aImportNode) then
      Exit(True);
  end;
  Result := False;
end;

function DprojHasImportProject(const aDoc: IXMLDocument; const aProject: string): Boolean;
var
  lImportNode: IXMLNode;
begin
  Result := TryFindDprojImportNode(aDoc.DocumentElement, aProject, lImportNode);
end;

procedure CollectXmlAttributeValues(const aNode: IXMLNode; const aElementName: string; const aAttributeName: string;
  const aValues: TStrings);
var
  i: Integer;
  lNode: IXMLNode;
begin
  if aNode = nil then
    Exit;
  if (aNode.NodeType = ntElement) and XmlNodeNameMatches(aNode, aElementName) and aNode.HasAttribute(aAttributeName)
  then
    aValues.Add(VarToStr(aNode.Attributes[aAttributeName]));

  for i := 0 to aNode.ChildNodes.Count - 1 do
  begin
    lNode := aNode.ChildNodes[i];
    CollectXmlAttributeValues(lNode, aElementName, aAttributeName, aValues);
  end;
end;

function DprojElementAttributeEquals(const aDoc: IXMLDocument; const aElementName: string; const aAttributeName: string;
  const aText: string): Boolean;
var
  i: Integer;
  lValues: TStringList;
begin
  Result := False;
  lValues := TStringList.Create;
  try
    CollectXmlAttributeValues(aDoc.DocumentElement, aElementName, aAttributeName, lValues);
    for i := 0 to lValues.Count - 1 do
      if SameText(lValues[i], aText) then
        Exit(True);
  finally
    lValues.Free;
  end;
end;

function DprojImportCondition(const aDoc: IXMLDocument; const aProject: string): string;
var
  lImportNode: IXMLNode;
begin
  Result := '';
  if TryFindDprojImportNode(aDoc.DocumentElement, aProject, lImportNode) and
    lImportNode.HasAttribute('Condition') then
    Result := VarToStr(lImportNode.Attributes['Condition']);
end;

function TryFindDprojSourceNode(const aNode: IXMLNode; const aName: string; out aSourceNode: IXMLNode): Boolean;
var
  i: Integer;
  lNode: IXMLNode;
begin
  aSourceNode := nil;
  if aNode = nil then
    Exit(False);
  if (aNode.NodeType = ntElement) and XmlNodeNameMatches(aNode, 'Source') and
    aNode.HasAttribute('Name') and SameText(VarToStr(aNode.Attributes['Name']), aName) then
  begin
    aSourceNode := aNode;
    Exit(True);
  end;

  for i := 0 to aNode.ChildNodes.Count - 1 do
  begin
    lNode := aNode.ChildNodes[i];
    if TryFindDprojSourceNode(lNode, aName, aSourceNode) then
      Exit(True);
  end;
  Result := False;
end;

function DprojSourceText(const aDoc: IXMLDocument; const aName: string): string;
var
  lSourceNode: IXMLNode;
begin
  Result := '';
  if TryFindDprojSourceNode(aDoc.DocumentElement, aName, lSourceNode) then
    Result := lSourceNode.Text;
end;

function NormalizedSourceText(const aText: string): string;
begin
  Result := StringReplace(aText, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

procedure AssertSourceContains(const aSourceText: string; const aExpected: string; const aMessage: string);
begin
  Assert.IsTrue(ContainsText(NormalizedSourceText(aSourceText), NormalizedSourceText(aExpected)), aMessage);
end;

procedure AssertSourceExcludes(const aSourceText: string; const aUnexpected: string; const aMessage: string);
begin
  Assert.IsFalse(ContainsText(NormalizedSourceText(aSourceText), NormalizedSourceText(aUnexpected)), aMessage);
end;

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
  const aEnvironmentBlock: string; const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal;
  out aError: string): Boolean;
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
  SetLength(fEnvironmentBlocks, Length(fEnvironmentBlocks) + 1);
  fEnvironmentBlocks[High(fEnvironmentBlocks)] := aEnvironmentBlock;

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

    if fMode = TMockValidatorMode.vmBuildFailHighExitCode then
    begin
      if lBuildLogPath <> '' then
        TFile.WriteAllText(lBuildLogPath,
          'MainForm.pas(42): error E2003: Undeclared identifier: ''BrokenSymbol''' + #13#10, TEncoding.UTF8);
      aExitCode := Cardinal($C0000005);
      Exit(True);
    end;

    if fMode = TMockValidatorMode.vmBuildFailMadExceptLinked then
    begin
      if lBuildLogPath <> '' then
        TFile.WriteAllText(lBuildLogPath,
          'madExcept.pas(5): error E2597: User-defined error: DAK_DFMCHECK_MADEXCEPT: ' +
          'madExcept-related code is not allowed in a DFM validator.' + #13#10, TEncoding.UTF8);
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
      end else if fMode = TMockValidatorMode.vmBrokenEventSignature then
      begin
        aOutput('FAIL MAINFORM -> EReadError: Error reading MainForm.OnCreate: Type mismatch for method ''FormCreate''');
        lValidatorLines := ['FAIL MAINFORM -> EReadError: Error reading MainForm.OnCreate: Type mismatch for method ''FormCreate''',
          'DFM stream validation summary: streamed=1 skipped=0 failed=1 requested=1 matched=1'];
      end else if fMode = TMockValidatorMode.vmWarnStandaloneActionImageBinding then
      begin
        aOutput('WARN MAINFORM -> EAccessViolation: Access violation at address 00B5A807 in module ' +
          '''Sample_DfmCheck.exe'' (offset 2BA807). Read of address 00000074');
        lValidatorLines := ['WARN MAINFORM -> EAccessViolation: Access violation at address 00B5A807 in module ' +
          '''Sample_DfmCheck.exe'' (offset 2BA807). Read of address 00000074',
          'DFM stream validation summary: streamed=1 skipped=0 failed=0 requested=1 matched=1'];
      end else if fMode = TMockValidatorMode.vmValidatorNonZeroNoFail then
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
      else if fMode = TMockValidatorMode.vmWarnStandaloneActionImageBinding then
        lValidatorLines := ['WARN MAINFORM -> EAccessViolation: Access violation at address 00B5A807 in module ' +
          '''Sample_DfmCheck.exe'' (offset 2BA807). Read of address 00000074',
          'DFM stream validation summary: streamed=1 skipped=0 failed=0 requested=1 matched=1']
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
  TFile.WriteAllText(TPath.Combine(lRoot, 'Sample.ico'), 'ico', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lRoot, 'Sample.Win32.ico'), 'ico', TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lRoot, 'Sample.Win64.ico'), 'ico', TEncoding.ASCII);
  TDirectory.CreateDirectory(TPath.Combine(lRoot, 'Resources'));
  TFile.WriteAllText(TPath.Combine(lRoot, 'Resources\nopreview.png'), 'png', TEncoding.ASCII);

  TFile.WriteAllText(aProjectDproj,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <MainSource>Sample.dpr</MainSource>' + #13#10 +
    '    <DCC_Define>madExcept;TRACE</DCC_Define>' + #13#10 +
    '    <Icon_MainIcon>Sample.ico</Icon_MainIcon>' + #13#10 +
    '    <PreBuildEvent><![CDATA[echo before' + #13#10 +
    '$(PreBuildEvent)]]></PreBuildEvent>' + #13#10 +
    '    <PostBuildEvent>echo after</PostBuildEvent>' + #13#10 +
    '    <DCC_UnitSearchPath>$(ProjectRoot)\Units;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '  <PropertyGroup Condition="''$(Base_Win32)''!=''''">' + #13#10 +
    '    <Icon_MainIcon>Sample.Win32.ico</Icon_MainIcon>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '  <PropertyGroup Condition="''$(Base_Win64)''!=''''">' + #13#10 +
    '    <Icon_MainIcon>Sample.Win64.ico</Icon_MainIcon>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '  <ItemGroup>' + #13#10 +
    '    <DCCReference Include="MainForm.pas"/>' + #13#10 +
    '    <RcItem Include="Resources\nopreview.png">' + #13#10 +
    '      <ResourceType>RCDATA</ResourceType>' + #13#10 +
    '      <ResourceId>no_preview_available_png</ResourceId>' + #13#10 +
    '    </RcItem>' + #13#10 +
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
    '  madExcept,' + #13#10 +
    '  madLinkDisAsm,' + #13#10 +
    '  madListHardware,' + #13#10 +
    '  madListProcesses,' + #13#10 +
    '  madListModules,' + #13#10 +
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

procedure TDfmCheckTests.BundledDfmStreamAllSupportsFrameConstructorFallback;
var
  lInjectPath: string;
  lInjectText: string;
begin
  lInjectPath := TPath.Combine(RepoRoot, 'tools\inject\DfmStreamAll.pas');
  Assert.IsTrue(FileExists(lInjectPath), 'Expected bundled inject DfmStreamAll.pas file.');
  lInjectText := TFile.ReadAllText(lInjectPath, TEncoding.UTF8);

  Assert.IsTrue(Pos('function ShouldUseConstructorFallbackForFrame', lInjectText) > 0,
    'Expected bundled inject file to expose frame constructor fallback logic.');
  Assert.IsTrue(Pos('EComponentError: A component named ', lInjectText) > 0,
    'Expected bundled inject file to detect duplicate-component frame streaming failures.');
  Assert.IsTrue(Pos('frame constructor fallback', lInjectText) > 0,
    'Expected bundled inject file to report constructor fallback context for frame retries.');
  Assert.IsTrue(Pos('OutputDebugString(PChar(aText));', lInjectText) > 0,
    'Expected bundled inject file to use OutputDebugString when stdout is unavailable.');
  Assert.IsTrue(Pos('if ShouldReraiseUnderDebugger then', lInjectText) > 0,
    'Expected bundled inject file to re-raise streaming exceptions under the debugger.');
  Assert.IsTrue(Pos('function DefaultDebugTraceLogPath: string;', lInjectText) > 0,
    'Expected bundled inject file to declare a debugger-only trace log path helper.');
  Assert.IsTrue(Pos('TRACE ', lInjectText) > 0,
    'Expected bundled inject file to emit debugger trace log lines.');
  Assert.IsFalse(Pos('lReader.ReadSignature;', lInjectText) > 0,
    'Bundled inject file should not use exception-driven ReadSignature probing.');
  Assert.IsTrue(Pos('Unexpected DFM signature bytes:', lInjectText) > 0,
    'Expected bundled inject file to report signature bytes without raising exceptions.');
  Assert.IsFalse(Pos('Writeln(aText);', lInjectText) > 0,
    'Bundled inject file must not call Writeln when stdout is unavailable.');
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

function TDfmCheckTests.GetDfmCheckWorkRoot(const aProjectDproj: string): string;
begin
  Result := TPath.Combine(ExtractFilePath(aProjectDproj), '.dak\' +
    TPath.GetFileNameWithoutExtension(aProjectDproj) + '\dfm-check');
end;

function TDfmCheckTests.GetSingleChildDirectory(const aParentDir: string): string;
var
  lDirectories: TArray<string>;
begin
  lDirectories := TDirectory.GetDirectories(aParentDir, '*', TSearchOption.soTopDirectoryOnly);
  Assert.AreEqual(1, Integer(Length(lDirectories)), 'Expected exactly one child directory under ' + aParentDir + '.');
  Result := lDirectories[0];
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

procedure TDfmCheckTests.BuildExpectedPathsUseDakWorkspace;
var
  lDakRoot: string;
  lDprojPath: string;
  lPaths: TDfmCheckPaths;
begin
  CreateFixtureProject(lDprojPath);
  lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
  lDakRoot := TPath.Combine(ExtractFilePath(lDprojPath), '.dak\Sample\dfm-check');
  Assert.AreEqual(ExcludeTrailingPathDelimiter(TPath.Combine(lDakRoot, 'generated')),
    ExcludeTrailingPathDelimiter(lPaths.fGeneratedDir));
  Assert.AreEqual(TPath.Combine(lPaths.fGeneratedDir, 'Sample_DfmCheck.dproj'), lPaths.fGeneratedDproj);
  Assert.AreEqual(TPath.Combine(lPaths.fGeneratedDir, 'Sample_DfmCheck.dpr'), lPaths.fGeneratedDpr);
  Assert.AreEqual(TPath.Combine(lPaths.fGeneratedDir, 'Sample_DfmCheck_Register.pas'), lPaths.fGeneratedRegisterUnit);
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
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lPaths: TDfmCheckPaths;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lInjectedPos: Integer;
  lGeneratedXmlDoc: IXMLDocument;
  lPatchedDprText: string;
  lGeneratedUnitText: string;
  lWinapiPos: Integer;
  lMadExceptPos: Integer;
  lSourceDprojBefore: string;
  lSourceDprBefore: string;
  lSourceDprText: string;
begin
  CreateFixtureProject(lDprojPath);
  lSourceDprojBefore := TFile.ReadAllText(lDprojPath);
  lSourceDprBefore := TFile.ReadAllText(TPath.ChangeExtension(lDprojPath, '.dpr'));
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-happy');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    Assert.IsTrue(Pos('DAK_TEST_RSVARS=1' + #0, lRunnerImpl.EnvironmentBlocks[0]) > 0,
      'Expected generated build child environment to receive rsvars snapshot values.');
    Assert.IsTrue(Pos('DAK_TEST_RSVARS=1' + #0, lRunnerImpl.EnvironmentBlocks[1]) > 0,
      'Expected validator child environment to receive rsvars snapshot values.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lPatchedDprText := ReadGeneratedDpr(lPaths);
    AssertSourceContains(lPatchedDprText, 'ExitCode := TDfmStreamAll.Run;',
      'Expected ExitCode assignment in patched DPR.');
    AssertSourceContains(lPatchedDprText, 'Halt(ExitCode);', 'Expected validator short-circuit halt in DPR.');
    AssertSourceExcludes(lPatchedDprText, 'Application.Initialize;',
      'Generated checker DPR must not execute application startup.');
    AssertSourceExcludes(lPatchedDprText, 'madExcept,',
      'Generated checker DPR should not add optional madExcept startup units.');
    lSourceDprText := TFile.ReadAllText(TPath.ChangeExtension(lDprojPath, '.dpr'));
    lMadExceptPos := Pos('madExcept,', lSourceDprText);
    lWinapiPos := Pos('Winapi.Windows,', lPatchedDprText);
    Assert.IsTrue((lMadExceptPos > 0) and (lWinapiPos > 0),
      'Expected fixture source DPR to use madExcept while generated DPR still uses Winapi.Windows.');
    AssertSourceExcludes(lPatchedDprText, 'Writeln(ErrOutput,',
      'Generated checker DPR must not write fatal-init diagnostics through ErrOutput when no console exists.');
    AssertSourceContains(lPatchedDprText, 'OutputDebugString(',
      'Generated checker DPR should surface fatal-init diagnostics through OutputDebugString.');
    AssertSourceContains(lPatchedDprText, 'DfmStreamAll in ''DfmStreamAll.pas'',',
      'Generated checker DPR should reference DfmStreamAll with an in-clause for IDE call stacks.');
    AssertSourceContains(lPatchedDprText, 'Sample_DfmCheck_Register in ''Sample_DfmCheck_Register.pas'',',
      'Generated checker DPR should reference the register unit with an in-clause for IDE call stacks.');
    AssertSourceContains(lPatchedDprText, 'DfmCheckRuntimeGuard in ''DfmCheckRuntimeGuard.pas'';',
      'Generated checker DPR should reference DfmCheckRuntimeGuard with an in-clause for IDE call stacks.');
    lInjectedPos := Pos('ExitCode := TDfmStreamAll.Run;', lPatchedDprText);
    Assert.IsTrue(lInjectedPos > 0, 'Expected generated checker DPR to execute validator entrypoint.');

    lGeneratedXmlDoc := LoadGeneratedDprojXml(lPaths);
    Assert.IsNotNull(lGeneratedXmlDoc.DocumentElement, 'Generated checker DPROJ should remain valid XML.');
    Assert.AreEqual('Project', lGeneratedXmlDoc.DocumentElement.NodeName,
      'Generated checker DPROJ should keep the MSBuild Project root node.');
    Assert.IsTrue(DprojElementTextHasToken(lGeneratedXmlDoc, 'DCC_Define', 'DFMCheck'),
      'Generated checker DPROJ should define DFMCheck symbol.');
    Assert.IsTrue(DprojElementTextHasToken(lGeneratedXmlDoc, 'DCC_Define', 'NO_LOCALIZATION'),
      'Generated checker DPROJ should define NO_LOCALIZATION symbol.');
    Assert.IsFalse(DprojElementTextHasToken(lGeneratedXmlDoc, 'DCC_Define', 'madExcept'),
      'Generated checker DPROJ must exclude madExcept from the validation process.');
    Assert.AreEqual('Sample_DfmCheck.dpr', DprojSourceText(lGeneratedXmlDoc, 'MainSource'),
      'Generated checker DPROJ should rewrite project extension MainSource entry.');
    Assert.IsTrue(DprojElementTextEquals(lGeneratedXmlDoc, 'Icon_MainIcon',
      TPath.Combine(ExtractFilePath(lDprojPath), 'Sample.ico')),
      'Generated checker DPROJ should rebase source-relative icon paths to the source project directory.');
    Assert.IsTrue(DprojElementTextEquals(lGeneratedXmlDoc, 'Icon_MainIcon',
      TPath.Combine(ExtractFilePath(lDprojPath), 'Sample.Win32.ico')),
      'Generated checker DPROJ should rebase Win32 icon override paths to the source project directory.');
    Assert.IsTrue(DprojElementTextEquals(lGeneratedXmlDoc, 'Icon_MainIcon',
      TPath.Combine(ExtractFilePath(lDprojPath), 'Sample.Win64.ico')),
      'Generated checker DPROJ should rebase Win64 icon override paths to the source project directory.');
    Assert.IsFalse(DprojElementTextContains(lGeneratedXmlDoc, 'PreBuildEvent', 'echo before'),
      'Generated checker DPROJ must not keep source-project pre-build events.');
    Assert.IsFalse(DprojElementTextContains(lGeneratedXmlDoc, 'PostBuildEvent', 'echo after'),
      'Generated checker DPROJ must not keep source-project post-build events.');
    Assert.IsTrue(DprojElementTextContains(lGeneratedXmlDoc, 'DCC_UnitSearchPath', '$(DCC_UnitSearchPath)'),
      'Generated checker DPROJ should preserve macro-based search path tokens.');
    Assert.IsTrue(DprojElementTextHasToken(lGeneratedXmlDoc, 'DCC_Define', 'TRACE'),
      'Generated checker DPROJ should preserve unrelated compiler define symbols.');
    Assert.AreEqual(lSourceDprojBefore, TFile.ReadAllText(lDprojPath),
      'DFM-check generation must not modify the source DPROJ.');
    Assert.AreEqual(lSourceDprBefore, TFile.ReadAllText(TPath.ChangeExtension(lDprojPath, '.dpr')),
      'DFM-check generation must not modify the source DPR.');

    lGeneratedUnitText := ReadGeneratedRegisterUnit(lPaths);
    AssertSourceContains(lGeneratedUnitText, 'unit Sample_DfmCheck_Register;',
      'Expected generated register unit for streaming class registration.');
    AssertSourceContains(lGeneratedUnitText, 'uses', 'Expected generated register unit to keep form-unit linkage.');
    AssertSourceContains(lGeneratedUnitText, 'MainForm', 'Expected generated register unit to keep MainForm in uses.');
    AssertSourceContains(lGeneratedUnitText, '{$IF Declared(TMainForm)} RegisterClass(TMainForm); {$IFEND}',
      'Expected generated register unit to register root form class for streaming.');
    AssertSourceExcludes(lGeneratedUnitText, '.ClassName;',
      'Generated register unit should not include compile-time ClassName checks.');
  finally
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineGeneratesMadExceptBlockerUnits;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lEnvGuard: IInterface;
  lInjectDir: string;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lResult: Integer;
  lRunner: IDfmCheckProcessRunner;
  lUnitName: string;
  lUnitPath: string;
  lUnitText: string;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-madexcept-blockers');
  WriteInjectStubs(lInjectDir);
  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  try
    lRunner := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected fixture pipeline to generate blocker units.');
    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project: ' + lError);
    for lUnitName in ['madExcept', 'madLinkDisAsm', 'madListHardware', 'madListProcesses', 'madListModules'] do
    begin
      lUnitPath := TPath.Combine(lPaths.fGeneratedDir, lUnitName + '.pas');
      Assert.IsTrue(FileExists(lUnitPath), 'Expected generated blocker unit: ' + lUnitPath);
      lUnitText := TFile.ReadAllText(lUnitPath);
      AssertSourceContains(lUnitText, '{$MESSAGE FATAL', 'Expected blocker to stop madExcept linkage.');
      AssertSourceContains(lUnitText, 'DAK_DFMCHECK_MADEXCEPT', 'Expected machine-readable blocker marker.');
    end;
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelineAddsUnitSearchPathWhenProjectInheritsOptsetSearchPath;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lGeneratedDprText: string;
  lGeneratedXmlDoc: IXMLDocument;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lSourceDir: string;
begin
  CreateFixtureProjectWithInheritedSearchPath(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-inherited-search-path');
  WriteInjectStubs(lInjectDir);
  lSourceDir := TPath.Combine(ExtractFilePath(lDprojPath), 'src');

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '23.0';
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
    lGeneratedDprText := ReadGeneratedDpr(lPaths);
    AssertSourceExcludes(lGeneratedDprText, 'madExcept,',
      'Generated checker DPR should not inject madExcept when the source DPR does not use it.');
    lGeneratedXmlDoc := LoadGeneratedDprojXml(lPaths);
    Assert.IsTrue(DprojElementExists(lGeneratedXmlDoc, 'DCC_UnitSearchPath'),
      'Generated checker DPROJ should synthesize DCC_UnitSearchPath when source project inherits it from an optset.');
    Assert.IsTrue(DprojElementTextContains(lGeneratedXmlDoc, 'DCC_UnitSearchPath', lSourceDir),
      'Generated checker DPROJ should prepend discovered form unit directories.');
    Assert.IsTrue(DprojElementTextContains(lGeneratedXmlDoc, 'DCC_UnitSearchPath', '$(DCC_UnitSearchPath)'),
      'Generated checker DPROJ should still preserve inherited DCC_UnitSearchPath macros.');
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelineRebasesRelativeProjectImportsForGeneratedProject;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lGeneratedXmlDoc: IXMLDocument;
  lImportPath: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProjectWithInheritedSearchPath(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-import-rebase');
  WriteInjectStubs(lInjectDir);
  lImportPath := TPath.Combine(ExtractFilePath(lDprojPath), 'Fixture.optset');

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '23.0';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected import-rebase fixture to complete with mock runner.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Unexpected error category for import-rebase fixture.');
    Assert.AreEqual('', lError, 'Did not expect an error message for import-rebase fixture.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lGeneratedXmlDoc := LoadGeneratedDprojXml(lPaths);
    Assert.IsTrue(DprojHasImportProject(lGeneratedXmlDoc, lImportPath),
      'Generated checker DPROJ should rewrite relative import paths to the source project location.');
    Assert.IsFalse(DprojHasImportProject(lGeneratedXmlDoc, 'Fixture.optset'),
      'Generated checker DPROJ should not keep source-relative import paths after relocation.');
    Assert.AreEqual('Exists(''' + lImportPath + ''')', DprojImportCondition(lGeneratedXmlDoc, lImportPath),
      'Generated checker DPROJ should rewrite relative Exists(...) import conditions to the source project location.');
    Assert.AreNotEqual('Exists(''Fixture.optset'')', DprojImportCondition(lGeneratedXmlDoc, lImportPath),
      'Generated checker DPROJ should not keep relative Exists(...) import conditions after relocation.');
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelineRebasesRelativeItemIncludesForGeneratedProject;
var
  lCategory: TDfmCheckErrorCategory;
  lDccReferencePath: string;
  lDprojPath: string;
  lError: string;
  lGeneratedXmlDoc: IXMLDocument;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lRcItemPath: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-item-rebase');
  WriteInjectStubs(lInjectDir);
  lDccReferencePath := TPath.Combine(ExtractFilePath(lDprojPath), 'MainForm.pas');
  lRcItemPath := TPath.Combine(ExtractFilePath(lDprojPath), 'Resources\nopreview.png');

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '23.0';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.IsTrue((lResult = 0) or (lResult = 30),
      'Expected item-rebase fixture to generate artifacts before any environment-specific pipeline failure.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lGeneratedXmlDoc := LoadGeneratedDprojXml(lPaths);
    Assert.IsTrue(DprojElementAttributeEquals(lGeneratedXmlDoc, 'DCCReference', 'Include', lDccReferencePath),
      'Generated checker DPROJ should rebase source-relative DCCReference items.');
    Assert.IsTrue(DprojElementAttributeEquals(lGeneratedXmlDoc, 'RcItem', 'Include', lRcItemPath),
      'Generated checker DPROJ should rebase source-relative RcItem payload paths.');
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelineForcesGeneratedProjectToRunAsInvoker;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lDprojText: string;
  lError: string;
  lGeneratedXmlDoc: IXMLDocument;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lDprojText := TFile.ReadAllText(lDprojPath, TEncoding.UTF8);
  lDprojText := StringReplace(lDprojText,
    '    <DCC_Define>madExcept;TRACE</DCC_Define>' + #13#10,
    '    <DCC_Define>madExcept;TRACE</DCC_Define>' + #13#10 +
    '    <AppExecutionLevel>requireAdministrator</AppExecutionLevel>' + #13#10, []);
  TFile.WriteAllText(lDprojPath, lDprojText, TEncoding.UTF8);

  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-app-execution-level');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '23.0';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected app-execution-level fixture to complete with mock runner.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Unexpected error category for app-execution-level fixture.');
    Assert.AreEqual('', lError, 'Did not expect an error message for app-execution-level fixture.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lGeneratedXmlDoc := LoadGeneratedDprojXml(lPaths);
    Assert.IsTrue(DprojElementTextEquals(lGeneratedXmlDoc, 'AppExecutionLevel', 'asInvoker'),
      'Generated checker DPROJ should not inherit requireAdministrator from the source project.');
    Assert.IsFalse(DprojElementTextEquals(lGeneratedXmlDoc, 'AppExecutionLevel', 'requireAdministrator'),
      'Generated checker DPROJ should be runnable by the compile gate without elevation.');
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelineRebasesSingleQuotedRelativeProjectImportsForGeneratedProject;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lDprojText: string;
  lError: string;
  lGeneratedXmlDoc: IXMLDocument;
  lImportFileName: string;
  lImportNode: IXMLNode;
  lImportPath: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProjectWithInheritedSearchPath(lDprojPath);
  lImportFileName := 'Fixture Path ' + #$017C + '.optset';
  lImportPath := TPath.Combine(ExtractFilePath(lDprojPath), lImportFileName);
  TFile.Move(TPath.Combine(ExtractFilePath(lDprojPath), 'Fixture.optset'), lImportPath);
  lDprojText := TFile.ReadAllText(lDprojPath, TEncoding.UTF8);
  lDprojText := StringReplace(lDprojText,
    '<Import Project="Fixture.optset" Condition="Exists(''Fixture.optset'')"/>',
    '<Import Condition="Exists( &apos;' + lImportFileName + '&apos; )" Project=''' + lImportFileName + '''/>', []);
  TFile.WriteAllText(lDprojPath, lDprojText, TEncoding.UTF8);

  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-single-quoted-import-rebase');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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

    Assert.AreEqual(0, lResult, 'Expected single-quoted import fixture to complete with mock runner.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Unexpected error category for single-quoted import fixture.');
    Assert.AreEqual('', lError, 'Did not expect an error message for single-quoted import fixture.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lGeneratedXmlDoc := LoadGeneratedDprojXml(lPaths);
    lImportNode := nil;
    TryFindDprojImportNode(lGeneratedXmlDoc.DocumentElement, lImportPath, lImportNode);

    Assert.IsNotNull(lImportNode,
      'Generated checker DPROJ should rewrite single-quoted relative import paths to the source project location.');
    Assert.AreEqual(lImportPath, VarToStr(lImportNode.Attributes['Project']),
      'Generated checker DPROJ should not keep single-quoted relative import paths after relocation.');
    Assert.AreEqual('Exists( ''' + lImportPath + ''' )', VarToStr(lImportNode.Attributes['Condition']),
      'Generated checker DPROJ should rewrite single-quoted relative Exists(...) import conditions.');
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelinePreservesBackslashDigitSearchPathsForGeneratedProject;
var
  lAppDataDir: string;
  lBackslashDigitDir: string;
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lEnvOptionsPath: string;
  lError: string;
  lGeneratedDprojText: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-backslash-digit-path');
  WriteInjectStubs(lInjectDir);
  lBackslashDigitDir := TPath.Combine(ExtractFilePath(lDprojPath), '3rdParty');
  TDirectory.CreateDirectory(lBackslashDigitDir);
  lEnvOptionsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvOptions.proj');
  TFile.WriteAllText(lEnvOptionsPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <DelphiLibraryPath>' + lBackslashDigitDir + '</DelphiLibraryPath>' + #13#10 +
    '    <DCC_UnitSearchPath>' + lBackslashDigitDir + ';$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '</Project>' + #13#10, TEncoding.UTF8);

  lAppDataDir := TPath.Combine(ExtractFilePath(lDprojPath), 'fake-appdata');
  lEnvGuard := SetScopedEnvironmentVariables([
    'APPDATA', lAppDataDir,
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '99.9';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
    lOptions.fHasEnvOptionsPath := True;
    lOptions.fEnvOptionsPath := lEnvOptionsPath;

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected backslash-digit path fixture to complete with mock runner.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Unexpected error category for backslash-digit path fixture.');
    Assert.AreEqual('', lError, 'Did not expect an error message for backslash-digit path fixture.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lGeneratedDprojText := ReadGeneratedDprojText(lPaths);
    Assert.IsTrue(Pos(lBackslashDigitDir, lGeneratedDprojText) > 0,
      'Generated checker DPROJ should preserve paths containing backslash followed by a digit. Output: ' +
      lGeneratedDprojText);
    Assert.IsFalse(Pos(StringReplace(lBackslashDigitDir, '\3', '', [rfIgnoreCase]), lGeneratedDprojText) > 0,
      'Generated checker DPROJ should not corrupt \3 path segments. Output: ' + lGeneratedDprojText);
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelinePreservesEffectiveSearchPathForGeneratedProject;
var
  lAppDataDir: string;
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lEnvOptionsPath: string;
  lEnvSearchDir: string;
  lError: string;
  lGeneratedSearchPath: string;
  lGeneratedXmlDoc: IXMLDocument;
  lIdeLibraryDir: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lSourceDir: string;
  lEnvSearchPos: Integer;
  lIdeLibraryPos: Integer;
  lSourceDirPos: Integer;
begin
  CreateFixtureProjectWithInheritedSearchPath(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-effective-search-path');
  WriteInjectStubs(lInjectDir);
  lSourceDir := TPath.Combine(ExtractFilePath(lDprojPath), 'src');
  lEnvSearchDir := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvSearch');
  lIdeLibraryDir := TPath.Combine(ExtractFilePath(lDprojPath), 'IdeLibrary');
  TDirectory.CreateDirectory(lEnvSearchDir);
  TDirectory.CreateDirectory(lIdeLibraryDir);
  lEnvOptionsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvOptions.proj');
  TFile.WriteAllText(lEnvOptionsPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <DelphiLibraryPath>' + lIdeLibraryDir + '</DelphiLibraryPath>' + #13#10 +
    '    <DCC_UnitSearchPath>' + lEnvSearchDir + ';$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '</Project>' + #13#10, TEncoding.UTF8);

  lAppDataDir := TPath.Combine(ExtractFilePath(lDprojPath), 'fake-appdata');
  lEnvGuard := SetScopedEnvironmentVariables([
    'APPDATA', lAppDataDir,
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '99.9';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
    lOptions.fHasEnvOptionsPath := True;
    lOptions.fEnvOptionsPath := lEnvOptionsPath;

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected effective-search-path fixture to complete with mock runner.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Unexpected error category for effective-search-path fixture.');
    Assert.AreEqual('', lError, 'Did not expect an error message for effective-search-path fixture.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lGeneratedXmlDoc := LoadGeneratedDprojXml(lPaths);
    lGeneratedSearchPath := DprojFirstElementText(lGeneratedXmlDoc, 'DCC_UnitSearchPath');
    Assert.AreNotEqual('', lGeneratedSearchPath,
      'Generated checker DPROJ should synthesize DCC_UnitSearchPath from the effective project/build search path.');
    lSourceDirPos := Pos(lSourceDir, lGeneratedSearchPath);
    lEnvSearchPos := Pos(lEnvSearchDir, lGeneratedSearchPath);
    lIdeLibraryPos := Pos(lIdeLibraryDir, lGeneratedSearchPath);
    Assert.IsTrue(lSourceDirPos > 0,
      'Generated checker DPROJ should keep discovered form unit directories.');
    Assert.IsTrue(lEnvSearchPos > 0,
      'Generated checker DPROJ should keep EnvOptions DCC_UnitSearchPath entries used by the normal build model.');
    Assert.IsTrue(lIdeLibraryPos > 0,
      'Generated checker DPROJ should keep IDE/library-path entries used by the normal build model.');
    Assert.IsTrue(lSourceDirPos < lEnvSearchPos,
      'Generated checker DPROJ should keep project form-unit directories ahead of inherited EnvOptions search paths.');
    Assert.IsTrue(lSourceDirPos < lIdeLibraryPos,
      'Generated checker DPROJ should keep project form-unit directories ahead of IDE/library-path entries.');
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelineKeepsReferenceSourceDirsAfterEffectiveSearchPath;
var
  lCategory: TDfmCheckErrorCategory;
  lDprPath: string;
  lDprText: string;
  lDprojPath: string;
  lEnvOptionsPath: string;
  lError: string;
  lGeneratedSearchPath: string;
  lGeneratedXmlDoc: IXMLDocument;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lProjectText: string;
  lReferenceSourceDir: string;
  lReferenceSourcePath: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lCompiledLibraryDir: string;
  lCompiledLibraryPos: Integer;
  lReferenceSourcePos: Integer;
begin
  CreateFixtureProjectWithInheritedSearchPath(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-reference-source-order');
  WriteInjectStubs(lInjectDir);
  TDirectory.CreateDirectory(TPath.Combine(ExtractFilePath(lDprojPath), '.svn'));
  lCompiledLibraryDir := TPath.Combine(ExtractFilePath(lDprojPath), 'CompiledLibrary');
  lReferenceSourceDir := TPath.Combine(TempRoot, 'dfm-check-external-reference-source');
  lReferenceSourcePath := TPath.Combine(lReferenceSourceDir, 'LegacyWidget.pas');
  TDirectory.CreateDirectory(lCompiledLibraryDir);
  TDirectory.CreateDirectory(lReferenceSourceDir);
  TFile.WriteAllText(lReferenceSourcePath, 'unit LegacyWidget; interface implementation end.', TEncoding.UTF8);
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  lDprText := TFile.ReadAllText(lDprPath, TEncoding.UTF8);
  lDprText := StringReplace(lDprText,
    '  MainForm in ''src\MainForm.pas'' {MainForm};',
    '  MainForm in ''src\MainForm.pas'' {MainForm},' + #13#10 +
    '  LegacyWidget in ''' + lReferenceSourcePath + ''';', []);
  TFile.WriteAllText(lDprPath, lDprText, TEncoding.UTF8);

  lProjectText := TFile.ReadAllText(lDprojPath, TEncoding.UTF8);
  lProjectText := StringReplace(lProjectText, '</Project>',
    '  <ItemGroup>' + #13#10 +
    '    <DCCReference Include="' + lReferenceSourcePath + '"/>' + #13#10 +
    '  </ItemGroup>' + #13#10 +
    '</Project>', []);
  TFile.WriteAllText(lDprojPath, lProjectText, TEncoding.UTF8);

  lEnvOptionsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'EnvOptions.proj');
  TFile.WriteAllText(lEnvOptionsPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <DelphiLibraryPath>' + lCompiledLibraryDir + '</DelphiLibraryPath>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '</Project>' + #13#10, TEncoding.UTF8);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '99.9';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
    lOptions.fHasEnvOptionsPath := True;
    lOptions.fEnvOptionsPath := lEnvOptionsPath;

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected reference-source-order fixture to complete with mock runner.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Unexpected error category for reference-source-order fixture.');
    Assert.AreEqual('', lError, 'Did not expect an error message for reference-source-order fixture.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lGeneratedXmlDoc := LoadGeneratedDprojXml(lPaths);
    lGeneratedSearchPath := DprojFirstElementText(lGeneratedXmlDoc, 'DCC_UnitSearchPath');
    lCompiledLibraryPos := Pos(lCompiledLibraryDir, lGeneratedSearchPath);
    lReferenceSourcePos := Pos(lReferenceSourceDir, lGeneratedSearchPath);
    Assert.IsTrue(lCompiledLibraryPos > 0,
      'Generated checker DPROJ should keep compiled library paths from the effective build context.');
    Assert.AreEqual(0, lReferenceSourcePos,
      'Generated checker DPROJ should not add non-form reference source directories to the compiler search path.');
    Assert.IsFalse(DprojElementAttributeEquals(lGeneratedXmlDoc, 'DCCReference', 'Include', lReferenceSourcePath),
      'Generated checker DPROJ should not compile non-form source references from the source project.');
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelineKeepsRepoLocalReferenceSourceDirsAfterEffectiveSearchPath;
var
  lAppDir: string;
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lDprPath: string;
  lError: string;
  lExternalDir: string;
  lExternalPath: string;
  lGeneratedSearchPath: string;
  lGeneratedXmlDoc: IXMLDocument;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lLocalDir: string;
  lLocalPath: string;
  lMainFormDfmPath: string;
  lMainFormPasPath: string;
  lOptions: TAppOptions;
  lPaths: TDfmCheckPaths;
  lRepoRoot: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  lRepoRoot := TPath.Combine(TempRoot, 'dfm-check-repo-local-reference-source');
  if TDirectory.Exists(lRepoRoot) then
    TDirectory.Delete(lRepoRoot, True);
  TDirectory.CreateDirectory(TPath.Combine(lRepoRoot, '.svn'));
  lAppDir := TPath.Combine(lRepoRoot, 'App');
  lLocalDir := TPath.Combine(lRepoRoot, 'Schnittstellen2\SilverDat3\soap');
  lExternalDir := TPath.Combine(TempRoot, 'dfm-check-outside-repo-reference-source');
  TDirectory.CreateDirectory(TPath.Combine(lAppDir, 'src'));
  TDirectory.CreateDirectory(lLocalDir);
  TDirectory.CreateDirectory(lExternalDir);

  lDprojPath := TPath.Combine(lAppDir, 'Sample.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  lMainFormPasPath := TPath.Combine(lAppDir, 'src\MainForm.pas');
  lMainFormDfmPath := TPath.Combine(lAppDir, 'src\MainForm.dfm');
  lLocalPath := TPath.Combine(lLocalDir, 'LocalGenerated.pas');
  lExternalPath := TPath.Combine(lExternalDir, 'ExternalGenerated.pas');
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-repo-local-reference-source');
  WriteInjectStubs(lInjectDir);

  TFile.WriteAllText(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + #13#10 +
    '  <PropertyGroup>' + #13#10 +
    '    <MainSource>Sample.dpr</MainSource>' + #13#10 +
    '    <DCC_Define>TRACE</DCC_Define>' + #13#10 +
    '  </PropertyGroup>' + #13#10 +
    '  <ItemGroup>' + #13#10 +
    '    <DCCReference Include="src\MainForm.pas"/>' + #13#10 +
    '    <DCCReference Include="..\Schnittstellen2\SilverDat3\soap\LocalGenerated.pas"/>' + #13#10 +
    '    <DCCReference Include="' + lExternalPath + '"/>' + #13#10 +
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

  TFile.WriteAllText(TPath.Combine(lAppDir, 'dak.ini'),
    '[Build]' + #13#10 +
    'DelphiVersion=23.0' + #13#10, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(lAppDir, 'rsvars.bat'),
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
    '  end;' + #13#10 +
    #13#10 +
    'implementation' + #13#10 +
    #13#10 +
    '{$R *.dfm}' + #13#10 +
    #13#10 +
    'end.' + #13#10, TEncoding.UTF8);
  TFile.WriteAllText(lMainFormDfmPath,
    'object MainForm: TMainForm' + #13#10 +
    '  Caption = ''MainForm''' + #13#10 +
    'end' + #13#10, TEncoding.UTF8);
  TFile.WriteAllText(lLocalPath, 'unit LocalGenerated; interface implementation end.', TEncoding.UTF8);
  TFile.WriteAllText(lExternalPath, 'unit ExternalGenerated; interface implementation end.', TEncoding.UTF8);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '99.9';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(lAppDir, 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected repo-local reference-source fixture to complete with mock runner.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Unexpected error category for repo-local reference-source fixture.');
    Assert.AreEqual('', lError, 'Did not expect an error message for repo-local reference-source fixture.');

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);
    Assert.IsTrue(TryLocateGeneratedDfmCheckProject(lPaths, lError), 'Expected generated project to be locatable.');
    lGeneratedXmlDoc := LoadGeneratedDprojXml(lPaths);
    lGeneratedSearchPath := DprojFirstElementText(lGeneratedXmlDoc, 'DCC_UnitSearchPath');
    Assert.IsTrue(Pos(lLocalDir, lGeneratedSearchPath) > 0,
      'Generated checker DPROJ should keep repo-local reference source directories.');
    Assert.AreEqual(0, Pos(lExternalDir, lGeneratedSearchPath),
      'Generated checker DPROJ should not add reference source directories outside the checkout.');
    Assert.IsTrue(DprojElementAttributeEquals(lGeneratedXmlDoc, 'DCCReference', 'Include', lLocalPath),
      'Generated checker DPROJ should preserve exact repo-local source references.');
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelineFailsClosedWhenStrictProjectContextIsUnavailable;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProjectWithInheritedSearchPath(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-strict-context-missing');
  WriteInjectStubs(lInjectDir);
  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe'
  ]);
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'missing-rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreNotEqual(0, lResult, 'Expected DFMCheck to fail closed without strict semantic context.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecDfmCheckFailed, lCategory,
      'Unexpected error category for strict context failure.');
    Assert.IsTrue(ContainsText(lError, 'Delphi IDE context could not be resolved'),
      'Expected strict context failure to report the degradation reason. Error: ' + lError);
    Assert.AreEqual(0, lRunnerImpl.RunCount, 'DFMCheck must not invoke external tools after strict context failure.');
  finally
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelineStrictContextUsesDefaultConfigPlatform;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProjectWithInheritedSearchPath(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-default-context');
  WriteInjectStubs(lInjectDir);
  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe'
  ]);
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected omitted config/platform to use dfm-check defaults.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Unexpected error category for defaulted config/platform.');
    Assert.AreEqual('', lError, 'Did not expect an error when config/platform are omitted.');
    Assert.IsTrue(ContainsText(lRunnerImpl.MsBuildArguments, '/p:Config=Release'),
      'Expected default Release config in MSBuild arguments: ' + lRunnerImpl.MsBuildArguments);
    Assert.IsTrue(ContainsText(lRunnerImpl.MsBuildArguments, '/p:Platform=Win32'),
      'Expected default Win32 platform in MSBuild arguments: ' + lRunnerImpl.MsBuildArguments);
  finally
    lEnvGuard := nil;
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
  lEnvGuard: IInterface;
  lNamespacedDfmPath: string;
  lNamespacedPasPath: string;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lPaths: TDfmCheckPaths;
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

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    lGeneratedUnitText := ReadGeneratedRegisterUnit(lPaths);
    AssertSourceContains(lGeneratedUnitText, 'sd3.WebBrowser',
      'Expected generated register unit uses list to keep namespaced unit names.');
    AssertSourceExcludes(lGeneratedUnitText, #10 + '  WebBrowser,' + #10,
      'Generated register unit must not drop namespace prefix from unit name.');
    AssertSourceExcludes(lGeneratedUnitText, #10 + '  WebBrowser;' + #10,
      'Generated register unit must not emit stripped terminal unit names.');
  finally
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBrokenDfmPropagatesValidatorExitAndFailText;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-broken');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBrokenEventSignaturePropagatesValidatorExitAndFailText;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-broken-event');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineWarningStandaloneActionImageBindingIsDiagnosedAsFailure;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lRootDir: string;
begin
  CreateFixtureProject(lDprojPath);
  lRootDir := ExtractFilePath(lDprojPath);
  TFile.WriteAllText(TPath.Combine(lRootDir, 'MainForm.dfm'),
    'object MainForm: TMainForm' + #13#10 +
    '  object btnCompleteTask: TBitBtn' + #13#10 +
    '    Action = actCompleteTask' + #13#10 +
    '    ImageName = ''task-complete''' + #13#10 +
    '    Images = TaskButtonImages' + #13#10 +
    '  end' + #13#10 +
    '  object actCompleteTask: TAction' + #13#10 +
    '    Caption = ''Complete task''' + #13#10 +
    '  end' + #13#10 +
    '  object TaskButtonImages: TVirtualImageList' + #13#10 +
    '  end' + #13#10 +
    'end' + #13#10, TEncoding.UTF8);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-warning-diagnosis');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmWarnStandaloneActionImageBinding, 'Release', 'Win32');
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

    lOutputText := JoinOutput(lOutputLines);

    Assert.AreEqual(1, lResult, 'Expected diagnosed warning to be promoted to a dfm-check failure. Output: ' +
      lOutputText);
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory,
      'Expected diagnosed warning to stay a validator result, not an orchestration failure.');
    Assert.AreEqual('', lError, 'Did not expect orchestration error text for warning diagnosis.');
    Assert.IsTrue(Pos('WARN MAINFORM -> EAccessViolation:', lOutputText) > 0,
      'Expected original validator warning to remain visible.');
    Assert.IsTrue(Pos('[dfm-check] FAIL diagnosis: resource=MAINFORM', lOutputText) > 0,
      'Expected diagnosed warning to emit an explicit failure summary.');
    Assert.IsTrue(Pos('MainForm.dfm:', lOutputText) > 0,
      'Expected diagnosed warning summary to include the DFM file path and line.');
    Assert.IsTrue(Pos('[dfm-check] WARN target: resource=MAINFORM', lOutputText) > 0,
      'Expected warning diagnostics to identify the resource.');
    Assert.IsTrue(Pos('component=btnCompleteTask', lOutputText) > 0,
      'Expected warning diagnostics to identify the suspicious button.');
    Assert.IsTrue(Pos('action=actcompletetask', LowerCase(lOutputText)) > 0,
      'Expected warning diagnostics to include the referenced action.');
    Assert.IsTrue(Pos('standalone taction', LowerCase(lOutputText)) > 0,
      'Expected warning diagnostics to explain that the action is not hosted in a TActionList.');
    Assert.IsTrue(Pos('TActionList', lOutputText) > 0,
      'Expected warning diagnostics to suggest a TActionList-based fix.');
    Assert.IsTrue(Pos('[dfm-check] Result: FAIL', lOutputText) > 0,
      'Expected diagnosed warning to make the final result fail.');
  finally
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.DfmCheckFailureIncludesResolvedSourceContextWhenPascalLocationIsKnown;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lEnvGuard: IInterface;
  lInjectGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectGuard := ClearScopedEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR');
  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    lEnvGuard := nil;
    lInjectGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.DfmCheckWarnsOnInvalidDiagnosticsIniValues;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
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

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.DfmCheckWindowCleanupUsesNativeUnsignedStyles;
var
  lSourceText: string;
begin
  lSourceText := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\Dak.DfmCheck.pas'));

  AssertSourceContains(lSourceText, 'GetWindowLongPtr(aWnd, GWL_STYLE)',
    'Window cleanup must use pointer-width style retrieval.');
  AssertSourceContains(lSourceText, 'lWindowStyle: NativeUInt;',
    'Window cleanup must keep high-bit Win32 style values out of signed Longint range checks.');
  AssertSourceExcludes(lSourceText, 'lWindowStyle: Longint;',
    'Window cleanup must not narrow Win32 style bitmasks to signed Longint.');
end;

procedure TDfmCheckTests.PipelineBuildFailureInGeneratedUnitIsClassifiedAsGeneratorIncompatibility;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-buildfail');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe'
  ]);
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
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineMadExceptBuildFailureExplainsDfmCheckGuards;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lResult: Integer;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-madexcept-buildfail');
  WriteInjectStubs(lInjectDir);
  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe'
  ]);
  try
    lRunner := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBuildFailMadExceptLinked, 'Release', 'Win32');
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckFilter := 'MainForm.dfm';
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    lResult := RunDfmCheckPipeline(lOptions, lRunner, nil, lCategory, lError);

    Assert.AreEqual(30, lResult, 'Expected madExcept source-preparation failure exit code.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecDfmCheckFailed, lCategory,
      'Expected madExcept linkage to be classified as a DFM-check preparation failure.');
    Assert.IsTrue(Pos('{$IFNDEF DFMCheck}', lError) > 0, 'Expected exact opening compiler guard guidance.');
    Assert.IsTrue(Pos('{$ENDIF}', lError) > 0, 'Expected exact closing compiler guard guidance.');
    Assert.IsTrue(Pos('uses entries and calls', lError) > 0,
      'Expected guidance to cover both madExcept units and related calls.');
    Assert.IsTrue(Pos('DAK defines DFMCheck automatically', lError) > 0,
      'Expected guidance to explain that no project configuration is required.');
  finally
    lEnvGuard := nil;
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
  lEnvGuard: IInterface;
  lKeepArtifactsGuard: IInterface;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-buildfail-cleanup');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe'
  ]);
  lKeepArtifactsGuard := ClearScopedEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
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
    lKeepArtifactsGuard := nil;
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBuildFailureWithHighExitCodeDoesNotOverflow;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-high-exit');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  lResult := -1;
  lOutputLines := TStringList.Create;
  try
    lRunnerImpl := TMockDfmCheckRunner.Create(TMockValidatorMode.vmBuildFailHighExitCode, 'Release', 'Win32');
    lRunner := lRunnerImpl;
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fDfmCheckAll := True;
    lOptions.fVerbose := True;
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');

    try
      lResult := RunDfmCheckPipeline(lOptions, lRunner,
        procedure(const aLine: string)
        begin
          lOutputLines.Add(aLine);
        end, lCategory, lError);
    except
      on E: Exception do
        Assert.Fail('Expected high build exit code to avoid overflow, but got ' + E.ClassName + ': ' + E.Message);
    end;

    lOutputText := JoinOutput(lOutputLines);
    Assert.AreEqual(TDfmCheckErrorCategory.ecBuildFailed, lCategory,
      'Expected non-generator build failure category for high exit code path.');
    Assert.AreEqual(34, lResult, 'Expected high build exit code to map to generic build failure exit code.');
    Assert.AreEqual('MSBuild exited with code 3221225477 (0xC0000005).', lError,
      'Expected exact high-exit-code error text.');
    Assert.IsTrue(Pos('[dfm-check] Build diagnostics (errors):', lOutputText) > 0,
      'Expected build diagnostics output for high build exit code path.');
    Assert.IsTrue(Pos('MainForm.pas(42): error E2003: Undeclared identifier: ''BrokenSymbol''', lOutputText) > 0,
      'Expected verbose build diagnostics to include the failing compiler error line.');
  finally
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelinePassesSelectedDfmFilterToValidator;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-filter');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineFindsValidatorExeInParentBin;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-parent-bin');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineKeepArtifactsStoresOwnedRunUnderDakWorkspace;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lGeneratedDir: string;
  lGeneratedIdentCachePath: string;
  lGeneratedLocalPath: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lKeepArtifactsGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lResult: Integer;
  lRunDir: string;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lRunsDir: string;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-keep-dak-run');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
  lOutputLines := TStringList.Create;
  try
    lGeneratedLocalPath := TPath.Combine(ExtractFilePath(lDprojPath), 'Sample_DfmCheck.dproj.local');
    lGeneratedIdentCachePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Sample_DfmCheck.identcache');
    TFile.WriteAllText(lGeneratedLocalPath, 'local', TEncoding.ASCII);
    TFile.WriteAllText(lGeneratedIdentCachePath, 'identcache', TEncoding.ASCII);

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

    Assert.AreEqual(0, lResult, 'Expected keep-artifacts pipeline to return success.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected error category for keep-artifacts path.');
    Assert.AreEqual('', lError, 'Did not expect an error message for keep-artifacts path.');

    lRunsDir := TPath.Combine(GetDfmCheckWorkRoot(lDprojPath), 'runs');
    Assert.IsTrue(DirectoryExists(lRunsDir), 'Expected owned dfm-check runs directory under sibling .dak root.');
    lRunDir := GetSingleChildDirectory(lRunsDir);
    lGeneratedDir := TPath.Combine(lRunDir, 'generated');
    Assert.IsTrue(FileExists(TPath.Combine(lGeneratedDir, 'Sample_DfmCheck.dpr')),
      'Expected generated DPR to stay under the preserved owned run workspace.');
    Assert.IsTrue(FileExists(TPath.Combine(lGeneratedDir, 'Sample_DfmCheck.dproj')),
      'Expected generated DPROJ to stay under the preserved owned run workspace.');
    Assert.IsTrue(FileExists(TPath.Combine(lGeneratedDir, 'Sample_DfmCheck_Register.pas')),
      'Expected generated register unit to stay under the preserved owned run workspace.');
    Assert.IsFalse(FileExists(TPath.Combine(ExtractFilePath(lDprojPath), 'Sample_DfmCheck.dpr')),
      'Did not expect generated DPR next to the source project when artifacts are kept.');
    Assert.IsFalse(FileExists(TPath.Combine(ExtractFilePath(lDprojPath), 'Sample_DfmCheck.dproj')),
      'Did not expect generated DPROJ next to the source project when artifacts are kept.');
    Assert.IsFalse(FileExists(TPath.Combine(ExtractFilePath(lDprojPath), 'Sample_DfmCheck_Register.pas')),
      'Did not expect generated register unit next to the source project when artifacts are kept.');
    Assert.IsFalse(FileExists(lGeneratedLocalPath),
      'Did not expect generated .dproj.local sidecar next to the source project when artifacts are kept.');
    Assert.IsFalse(FileExists(lGeneratedIdentCachePath),
      'Did not expect generated .identcache sidecar next to the source project when artifacts are kept.');
  finally
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelinePrunesStaleDakRunsBeforeGeneratingNewWorkspace;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lResult: Integer;
  lRunDir: string;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
  lRunsDir: string;
  lStaleRunDir: string;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-stale-prune');
  WriteInjectStubs(lInjectDir);

  lRunsDir := TPath.Combine(GetDfmCheckWorkRoot(lDprojPath), 'runs');
  lStaleRunDir := TPath.Combine(lRunsDir, 'stale-run');
  TDirectory.CreateDirectory(TPath.Combine(lStaleRunDir, 'generated'));
  TFile.WriteAllText(TPath.Combine(lStaleRunDir, 'generated\stale.txt'), 'stale', TEncoding.ASCII);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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

    Assert.AreEqual(0, lResult, 'Expected stale-run pruning path to return success.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected error category for stale-run pruning path.');
    Assert.AreEqual('', lError, 'Did not expect an error message for stale-run pruning path.');
    Assert.IsFalse(DirectoryExists(lStaleRunDir), 'Expected stale owned run directory to be pruned before the new run.');
    lRunDir := GetSingleChildDirectory(lRunsDir);
    Assert.IsTrue(FileExists(TPath.Combine(lRunDir, 'generated\Sample_DfmCheck.dpr')),
      'Expected current run workspace to remain after stale-run pruning.');
  finally
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineCleansGeneratedArtifactsByDefault;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lGeneratedIdentCachePath: string;
  lGeneratedLocalPath: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lKeepArtifactsGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lPaths: TDfmCheckPaths;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-cleanup');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe'
  ]);
  lKeepArtifactsGuard := ClearScopedEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  lOutputLines := TStringList.Create;
  try
    lGeneratedLocalPath := TPath.Combine(ExtractFilePath(lDprojPath), 'Sample_DfmCheck.dproj.local');
    lGeneratedIdentCachePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Sample_DfmCheck.identcache');
    TFile.WriteAllText(lGeneratedLocalPath, 'local', TEncoding.ASCII);
    TFile.WriteAllText(lGeneratedIdentCachePath, 'identcache', TEncoding.ASCII);

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
    Assert.IsFalse(FileExists(lGeneratedLocalPath), 'Expected generated .dproj.local sidecar to be cleaned up.');
    Assert.IsFalse(FileExists(lGeneratedIdentCachePath), 'Expected generated .identcache sidecar to be cleaned up.');
  finally
    lKeepArtifactsGuard := nil;
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineAllModeCacheHashingDoesNotOverflowWithDebugChecks;
var
  lCachePath: string;
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lResult: Integer;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-cache-overflow');
  WriteInjectStubs(lInjectDir);
  lCachePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Sample.dfmcheck.cache');

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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

    lRunner := TMockDfmCheckRunner.Create(TMockValidatorMode.vmHappy, 'Release', 'Win32');
    lResult := RunDfmCheckPipeline(lOptions, lRunner,
      procedure(const aLine: string)
      begin
        lOutputLines.Add(aLine);
      end, lCategory, lError);

    Assert.AreEqual(0, lResult, 'Expected all-mode cache preparation to succeed without integer overflow.');
    Assert.AreEqual(TDfmCheckErrorCategory.ecNone, lCategory, 'Unexpected category for overflow regression path.');
    Assert.AreEqual('', lError, 'Did not expect an orchestration error for overflow regression path.');
    Assert.IsTrue(FileExists(lCachePath), 'Expected cache file to be written after successful hash computation.');
  finally
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.DfmCheckCacheWritesAreSerializedAndAtomic;
var
  lSource: string;
begin
  lSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.dfmcheck.pas'), TEncoding.UTF8);

  Assert.IsTrue(ContainsText(lSource, 'BuildDfmCacheMutexName'),
    'Expected DFMCheck cache writes to derive a mutex from the cache/project identity.');
  Assert.IsTrue(ContainsText(lSource, 'CreateMutex'),
    'Expected DFMCheck cache writes to use a Windows mutex.');
  Assert.IsTrue(ContainsText(lSource, 'MoveFileEx'),
    'Expected DFMCheck cache writes to publish through an atomic replacement.');
  Assert.IsFalse(TRegEx.IsMatch(lSource, 'lCacheIni\.UpdateFile\s*;', [roIgnoreCase]),
    'Expected no direct TMemIniFile.UpdateFile write to the final DFMCheck cache path.');
end;

procedure TDfmCheckTests.PipelineAllModeCacheSkipsUnchangedDfmValidation;
var
  lCachePath: string;
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
  lResult: Integer;
  lRunner: IDfmCheckProcessRunner;
  lRunnerFirst: TMockDfmCheckRunner;
  lRunnerSecond: TMockDfmCheckRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-cache');
  WriteInjectStubs(lInjectDir);
  lCachePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Sample.dfmcheck.cache');

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    lEnvGuard := nil;
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
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lOutputText: string;
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

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    lEnvGuard := nil;
    lOutputLines.Free;
  end;
end;

procedure TDfmCheckTests.PipelineBuildTimeoutPreservesDiagnosticsAndSkipsCache;
var
  lBuildLogFound: Boolean;
  lBuildLogPath: string;
  lBuildLogPaths: TArray<string>;
  lBuildLogText: string;
  lBuildScriptPath: string;
  lCachePath: string;
  i: Integer;
  lDprojPath: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lKeepArtifactsGuard: IInterface;
  lOptions: TAppOptions;
  lResult: Integer;
  lRunsRoot: string;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-build-timeout');
  WriteInjectStubs(lInjectDir);
  lCachePath := TPath.Combine(ExtractFilePath(lDprojPath), 'Sample.dfmcheck.cache');
  lBuildScriptPath := TPath.Combine(TempRoot, 'dfm-check-hanging-msbuild.cmd');
  TFile.WriteAllText(lBuildScriptPath,
    '@echo off' + #13#10 +
    'echo fake msbuild entered' + #13#10 +
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds 10"' + #13#10 +
    'exit /b 0' + #13#10, TEncoding.Default);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', lBuildScriptPath,
    'DAK_DFMCHECK_TIMEOUT_MS', '250'
  ]);
  lKeepArtifactsGuard := ClearScopedEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS');
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win32';
    lOptions.fHasRsVarsPath := True;
    lOptions.fRsVarsPath := TPath.Combine(ExtractFilePath(lDprojPath), 'rsvars.bat');
    lOptions.fDfmCheckAll := True;
    lOptions.fVerbose := True;

    lResult := RunDfmCheckCommand(lOptions);

    Assert.IsTrue(lResult <> 0, 'Expected timeout to produce non-zero dfm-check result.');
    Assert.IsFalse(FileExists(lCachePath), 'Timeout must not create or refresh the all-mode success cache.');

    lRunsRoot := TPath.Combine(GetDfmCheckWorkRoot(lDprojPath), 'runs');
    Assert.IsTrue(TDirectory.Exists(lRunsRoot), 'Timeout diagnostics should keep the run root.');
    lBuildLogFound := False;
    lBuildLogPaths := TDirectory.GetFiles(lRunsRoot, '_DfmCheckBuild.log', TSearchOption.soAllDirectories);
    for lBuildLogPath in lBuildLogPaths do
    begin
      lBuildLogText := '';
      for i := 1 to 20 do
      begin
        try
          lBuildLogText := TFile.ReadAllText(lBuildLogPath, TEncoding.UTF8);
          Break;
        except
          Sleep(50);
        end;
      end;
      if ContainsText(lBuildLogText, 'timed out') then
      begin
        lBuildLogFound := True;
        Break;
      end;
    end;
    Assert.IsTrue(lBuildLogFound, 'Timeout diagnostics should keep a generated build log with the timeout reason.');
  finally
    lKeepArtifactsGuard := nil;
    lEnvGuard := nil;
  end;
end;

procedure TDfmCheckTests.PipelineAllModeUsesProgressWithoutQuietValidator;
var
  lCategory: TDfmCheckErrorCategory;
  lDprojPath: string;
  lError: string;
  lInjectDir: string;
  lEnvGuard: IInterface;
  lOptions: TAppOptions;
  lOutputLines: TStringList;
  lResult: Integer;
  lRunnerImpl: TMockDfmCheckRunner;
  lRunner: IDfmCheckProcessRunner;
begin
  CreateFixtureProject(lDprojPath);
  lInjectDir := TPath.Combine(TempRoot, 'dfm-check-inject-all-progress');
  WriteInjectStubs(lInjectDir);

  lEnvGuard := SetScopedEnvironmentVariables([
    'DAK_DFMCHECK_INJECT_DIR', lInjectDir,
    'DAK_DFMCHECK_MSBUILD', 'msbuild.exe',
    'DAK_DFMCHECK_KEEP_ARTIFACTS', 'true'
  ]);
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
    lEnvGuard := nil;
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
