unit Test.DfmInspect;

interface

uses
  DUnitX.TestFramework,
  System.IOUtils,
  System.SysUtils,
  Dak.DfmInspect,
  Test.Support;

type
  [TestFixture]
  TDfmInspectTests = class
  public
    [Test]
    procedure TreeFormatPrintsComponentHierarchy;
    [Test]
    procedure SummaryFormatPrintsCountsAndEvents;
    [Test]
    procedure AcceptsWslStyleDfmPath;
    [Test]
    procedure RejectsUnsupportedLinuxAbsolutePath;
    [Test]
    procedure MissingDfmReturnsInputFileExitCode;
    [Test]
    procedure CollectionPropertiesDoNotLeakWhenQuotedTextContainsGreaterThan;
    [Test]
    procedure HelpCommandShowsUsageWhenDfmValueUsesSeparateToken;
  end;

implementation

function ToWslPath(const aWindowsPath: string): string;
var
  lDrive: string;
  lPath: string;
  lRest: string;
begin
  lPath := Trim(aWindowsPath);
  if (Length(lPath) >= 3) and (lPath[2] = ':') and CharInSet(lPath[1], ['A'..'Z', 'a'..'z']) then
  begin
    lDrive := LowerCase(lPath[1]);
    lRest := Copy(lPath, 3, MaxInt);
    while lRest.StartsWith('\') or lRest.StartsWith('/') do
      lRest := Copy(lRest, 2, MaxInt);
    lRest := lRest.Replace('\', '/', [rfReplaceAll]);
    if lRest = '' then
      Exit('/mnt/' + lDrive);
    Exit('/mnt/' + lDrive + '/' + lRest);
  end;
  Result := lPath.Replace('\', '/', [rfReplaceAll]);
end;

procedure TDfmInspectTests.TreeFormatPrintsComponentHierarchy;
var
  lArgs: string;
  lDfmPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lDfmPath := TPath.Combine(RepoRoot, 'tests\fixtures\MainForm.dfm');
  lLogPath := TPath.Combine(TempRoot, 'dfm-inspect-tree.log');
  lArgs := 'dfm-inspect --dfm ' + QuoteArg(lDfmPath) + ' --format tree';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for dfm-inspect tree test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected dfm-inspect tree run to succeed. See: ' + lLogPath);

  lOutputText := '';
  if FileExists(lLogPath) then
    lOutputText := TFile.ReadAllText(lLogPath);

  Assert.IsTrue(Pos('MainForm: TMainForm', lOutputText) > 0,
    'Expected tree output to include the root form. Output: ' + lLogPath);
  Assert.IsTrue(Pos('pnlMain: TPanel', lOutputText) > 0,
    'Expected tree output to include the panel child. Output: ' + lLogPath);
  Assert.IsTrue(Pos('BtnSave: TButton', lOutputText) > 0,
    'Expected tree output to include the button child. Output: ' + lLogPath);
end;

procedure TDfmInspectTests.SummaryFormatPrintsCountsAndEvents;
var
  lArgs: string;
  lDfmPath: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lDfmPath := TPath.Combine(RepoRoot, 'tests\fixtures\MainForm.dfm');
  lLogPath := TPath.Combine(TempRoot, 'dfm-inspect-summary.log');
  lArgs := 'dfm-inspect --dfm ' + QuoteArg(lDfmPath) + ' --format summary';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for dfm-inspect summary test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected dfm-inspect summary run to succeed. See: ' + lLogPath);

  lOutputText := '';
  if FileExists(lLogPath) then
    lOutputText := TFile.ReadAllText(lLogPath);

  Assert.IsTrue(Pos('Form: MainForm (TMainForm)', lOutputText) > 0,
    'Expected summary output to include the root form. Output: ' + lLogPath);
  Assert.IsTrue(Pos('Components: 4', lOutputText) > 0,
    'Expected summary output to include total component count. Output: ' + lLogPath);
  Assert.IsTrue(Pos('MainForm.OnCreate = FormCreate', lOutputText) > 0,
    'Expected summary output to include the root event binding. Output: ' + lLogPath);
  Assert.IsTrue(Pos('BtnSave.OnClick = BtnSaveClick', lOutputText) > 0,
    'Expected summary output to include child event bindings. Output: ' + lLogPath);
end;

procedure TDfmInspectTests.AcceptsWslStyleDfmPath;
var
  lDfmPath: string;
  lError: string;
  lOutputText: string;
begin
  lDfmPath := ToWslPath(TPath.Combine(RepoRoot, 'tests\fixtures\MainForm.dfm'));

  Assert.IsTrue(TryInspectDfmFile(lDfmPath, 'summary', lOutputText, lError),
    'Expected TryInspectDfmFile to accept /mnt/... paths. Error: ' + lError);
  Assert.IsTrue(Pos('Form: MainForm (TMainForm)', lOutputText) > 0,
    'Expected summary output when using a /mnt/... DFM path. Output: ' + lOutputText);
end;

procedure TDfmInspectTests.RejectsUnsupportedLinuxAbsolutePath;
var
  lError: string;
  lOutputText: string;
begin
  lOutputText := '';
  Assert.IsFalse(TryInspectDfmFile('/home/not-supported/MainForm.dfm', 'tree', lOutputText, lError),
    'Expected unsupported Linux path to be rejected consistently.');
  Assert.IsTrue(Pos('Unsupported Linux path format', lError) > 0,
    'Expected unsupported Linux path error message. Actual: ' + lError);
end;

procedure TDfmInspectTests.MissingDfmReturnsInputFileExitCode;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'dfm-inspect-missing.log');
  lArgs := 'dfm-inspect --dfm ' + QuoteArg(TPath.Combine(RepoRoot, 'tests\fixtures\MissingForm.dfm')) + ' --format tree';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for missing DFM test.');
  Assert.AreEqual(Cardinal(3), lExitCode,
    'Expected missing DFM input to return exit code 3. See: ' + lLogPath);

  lOutputText := '';
  if FileExists(lLogPath) then
    lOutputText := TFile.ReadAllText(lLogPath);
  Assert.IsTrue(Pos('File not found', lOutputText) > 0,
    'Expected missing DFM error message. Output: ' + lLogPath);
end;

procedure TDfmInspectTests.CollectionPropertiesDoNotLeakWhenQuotedTextContainsGreaterThan;
var
  lDfmPath: string;
  lError: string;
  lOutputText: string;
begin
  lDfmPath := TPath.Combine(RepoRoot, 'tests\fixtures\CollectionCaptionForm.dfm');

  Assert.IsTrue(TryInspectDfmFile(lDfmPath, 'tree', lOutputText, lError),
    'Expected collection fixture to parse. Error: ' + lError);
  Assert.IsFalse(Pos('Width = 100', lOutputText) > 0,
    'Did not expect collection item Width to leak onto the form tree output.');
  Assert.IsTrue(Pos('Caption = ''Collection test''', lOutputText) > 0,
    'Expected root form properties to remain intact. Output: ' + lOutputText);
end;

procedure TDfmInspectTests.HelpCommandShowsUsageWhenDfmValueUsesSeparateToken;
var
  lArgs: string;
  lExitCode: Cardinal;
  lLogPath: string;
  lOutputText: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, 'dfm-inspect-help.log');
  lArgs := 'dfm-inspect --dfm tests\fixtures\MainForm.dfm --help';

  Assert.IsTrue(RunProcess(ResolverExePath, lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for dfm-inspect help test.');
  Assert.AreEqual(Cardinal(0), lExitCode,
    'Expected command-specific help to succeed when --dfm uses a separate token. See: ' + lLogPath);

  lOutputText := '';
  if FileExists(lLogPath) then
    lOutputText := TFile.ReadAllText(lLogPath);
  Assert.IsTrue(Pos('DelphiAIKit.exe dfm-inspect --dfm', lOutputText) > 0,
    'Expected dfm-inspect usage text. Output: ' + lLogPath);
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmInspectTests);

end.
