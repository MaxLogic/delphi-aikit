unit Test.NativeAnalysisWorkspace.Command;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TNativeWorkspaceCommandTests = class
  public
    [TestCase('Project', '0')]
    [TestCase('StandaloneUnit', '1')]
    [TestCase('ContextualUnit', '2')]
    procedure InspectionPreservesWorkspaceAndReports(aMode: Integer);
    [TestCase('MissingProject', '0')]
    [TestCase('InvalidUnitExtension', '1')]
    [TestCase('InvalidSelector', '2')]
    [TestCase('MissingContext', '3')]
    procedure InvalidInputReturnsUsageFailure(aMode: Integer);
    [TestCase('Human', 'false')]
    [TestCase('Json', 'true')]
    procedure InspectionProcessReportsPartialDakEvidence(aJson: Boolean);
    [Test]
    procedure InspectionReportsLockedSourceAsCaptureFailure;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Dak.Analysis.WorkspaceCommand, Dak.Types,
  Test.Support;

procedure TNativeWorkspaceCommandTests.InspectionPreservesWorkspaceAndReports(aMode: Integer);
var
  g: TGarbos;
  lDocument: TJSONObject;
  lError: string;
  lExpectedRoot: string;
  lOptions: TAppOptions;
  lParent: string;
  lProject: string;
  lProjectRoot: string;
  lProvenance: TJSONObject;
  lReport: string;
  lUnit: string;
  lUnitRoot: string;
  lWorkspace: TJSONObject;
begin
  lParent := UniqueTempPath('native-workspace-command');
  lProjectRoot := TPath.Combine(lParent, 'project');
  lUnitRoot := TPath.Combine(lParent, 'units');
  TDirectory.CreateDirectory(lProjectRoot);
  TDirectory.CreateDirectory(lUnitRoot);
  try
    lProject := TPath.Combine(lProjectRoot, 'App.dproj');
    lUnit := TPath.Combine(lUnitRoot, 'Main.pas');
    TFile.WriteAllText(lProject, '<Project/>');
    TFile.WriteAllText(lUnit, 'unit Main; interface implementation end.');
    TFile.WriteAllText(TPath.Combine(lProjectRoot, 'dak.ini'), '[Workspace]' + sLineBreak + 'Root=project');
    TFile.WriteAllText(TPath.Combine(lUnitRoot, 'dak.ini'), '[Workspace]' + sLineBreak + 'Root=project');
    lReport := TPath.Combine(lProjectRoot, '.dak\App\baseline.json');
    TDirectory.CreateDirectory(ExtractFileDir(lReport));
    TFile.WriteAllText(lReport, 'existing baseline sentinel');
    lOptions := Default(TAppOptions);
    lOptions.fCommand := TCommandKind.ckAnalyzeWorkspace;
    lOptions.fWorkspaceJson := True;
    lExpectedRoot := lProjectRoot;
    if aMode = 0 then
      lOptions.fDprojPath := lProject
    else
    begin
      lOptions.fUnitPath := lUnit;
      if aMode = 1 then
        lExpectedRoot := lUnitRoot
      else
      begin
        lOptions.fHasProjectContextPath := True;
        lOptions.fProjectContextPath := lProject;
      end;
    end;
    // An explicit scratch hint must not cause inspection to create or clean output.
    lOptions.fHasAnalyzeOutPath := True;
    lOptions.fAnalyzeOutPath := TPath.Combine(lParent, 'uncreated-output');
    Assert.AreEqual(0, InspectAnalysisWorkspace(lOptions, lDocument, lError), lError);
    GC(lDocument, g);
    Assert.AreEqual(2, lDocument.Count);
    lWorkspace := lDocument.GetValue<TJSONObject>('workspace');
    Assert.AreEqual(4, lWorkspace.Count);
    Assert.AreEqual(lExpectedRoot, lWorkspace.GetValue<string>('root'));
    Assert.AreEqual('project', lWorkspace.GetValue<string>('selector'));
    Assert.AreEqual('none', lWorkspace.GetValue<string>('vcs'));
    Assert.AreEqual(TPath.Combine(lExpectedRoot, 'dak.ini'), lWorkspace.GetValue<string>('source'));
    lProvenance := lDocument.GetValue<TJSONObject>('provenance');
    Assert.AreEqual(2, lProvenance.Count);
    Assert.AreEqual(lExpectedRoot, lProvenance.GetValue<TJSONObject>('target').GetValue<string>('root'));
    Assert.AreEqual(ParamStr(0), lProvenance.GetValue<TJSONObject>('dak').GetValue<string>('executable'));
    Assert.IsFalse(TDirectory.Exists(lOptions.fAnalyzeOutPath));
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(lUnitRoot, '.dak')));
    Assert.AreEqual('existing baseline sentinel', TFile.ReadAllText(lReport));
  finally
    DeleteTempPath(lParent);
  end;
end;

procedure TNativeWorkspaceCommandTests.InvalidInputReturnsUsageFailure(aMode: Integer);
var
  lDocument: TJSONObject;
  lError: string;
  lOptions: TAppOptions;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-workspace-invalid');
  TDirectory.CreateDirectory(lRoot);
  try
    lOptions := Default(TAppOptions);
    lOptions.fCommand := TCommandKind.ckAnalyzeWorkspace;
    lOptions.fDprojPath := TPath.Combine(lRoot, 'Missing.dproj');
    case aMode of
      1:
        begin
          lOptions.fDprojPath := '';
          lOptions.fUnitPath := TPath.Combine(lRoot, 'Wrong.txt');
          TFile.WriteAllText(lOptions.fUnitPath, 'not a Pascal unit');
        end;
      2:
        begin
          TFile.WriteAllText(lOptions.fDprojPath, '<Project/>');
          lOptions.fHasWorkspaceRoot := True;
          lOptions.fWorkspaceRoot := TPath.Combine(lRoot, 'missing-selector');
        end;
      3:
        begin
          lOptions.fDprojPath := '';
          lOptions.fUnitPath := TPath.Combine(lRoot, 'Main.pas');
          TFile.WriteAllText(lOptions.fUnitPath, 'unit Main;');
          lOptions.fHasProjectContextPath := True;
          lOptions.fProjectContextPath := TPath.Combine(lRoot, 'Missing.dproj');
        end;
    end;
    Assert.AreEqual(2, InspectAnalysisWorkspace(lOptions, lDocument, lError));
    Assert.IsNull(lDocument);
    Assert.IsNotEmpty(lError);
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeWorkspaceCommandTests.InspectionProcessReportsPartialDakEvidence(aJson: Boolean);
var
  g: TGarbos;
  lArguments: string;
  lDocument: TJSONObject;
  lEnvironment: IInterface;
  lExitCode: Cardinal;
  lLog: string;
  lOutput: string;
  lRoot: string;
  lUnit: string;
begin
  lRoot := UniqueTempPath('native-workspace-process');
  TDirectory.CreateDirectory(lRoot);
  try
    lUnit := TPath.Combine(lRoot, 'Main.pas');
    lLog := TPath.Combine(lRoot, 'process.log');
    TFile.WriteAllText(lUnit, 'unit Main; interface implementation end.');
    TFile.WriteAllText(TPath.Combine(lRoot, 'dak.ini'), '[Workspace]' + sLineBreak + 'Root=project');
    EnsureResolverBuilt;
    lArguments := 'analyze-workspace --unit ' + QuoteArg(lUnit);
    if aJson then
      lArguments := lArguments + ' --json';
    lEnvironment := SetScopedEnvironmentVariable('PATH', '');
    Assert.IsTrue(RunResolverProcess(lArguments, lRoot, lLog, lExitCode));
    Assert.AreEqual<Cardinal>(3, lExitCode, ReadUtf8TextFile(lLog));
    lOutput := ReadUtf8TextFile(lLog);
    if aJson then
    begin
      GC(lDocument, ParseJsonObject(lOutput), g);
      Assert.AreEqual('not_applicable', lDocument.GetValue<TJSONObject>('provenance')
        .GetValue<TJSONObject>('target').GetValue<string>('status'));
      Assert.AreEqual('unavailable', lDocument.GetValue<TJSONObject>('provenance')
        .GetValue<TJSONObject>('dak').GetValue<string>('status'));
    end else begin
      Assert.IsTrue(lOutput.Contains('Target provenance: not_applicable'), lOutput);
      Assert.IsTrue(lOutput.Contains('DAK provenance: unavailable'), lOutput);
    end;
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(lRoot, '.dak')));
  finally
    lEnvironment := nil;
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeWorkspaceCommandTests.InspectionReportsLockedSourceAsCaptureFailure;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lError: string;
  lLock: TFileStream;
  lOptions: TAppOptions;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-workspace-locked');
  TDirectory.CreateDirectory(lRoot);
  try
    lOptions := Default(TAppOptions);
    lOptions.fCommand := TCommandKind.ckAnalyzeWorkspace;
    lOptions.fUnitPath := TPath.Combine(lRoot, 'Main.pas');
    lOptions.fHasWorkspaceRoot := True;
    lOptions.fWorkspaceRoot := 'project';
    TFile.WriteAllText(lOptions.fUnitPath, 'unit Main;');
    GC(lLock, TFileStream.Create(lOptions.fUnitPath, fmOpenRead or fmShareExclusive), g);
    Assert.AreEqual(4, InspectAnalysisWorkspace(lOptions, lDocument, lError));
    Assert.IsNull(lDocument);
    Assert.IsNotEmpty(lError);
  finally
    g.Clear;
    DeleteTempPath(lRoot);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeWorkspaceCommandTests);

end.
