unit Test.DfmInspect;

interface

uses
  DUnitX.TestFramework,
  System.IOUtils,
  System.StrUtils,
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
    procedure Utf8TextDfmWithoutBomKeepsCaptionText;
    [Test]
    procedure Utf16LeBomTextDfmKeepsCaptionText;
    [Test]
    procedure HelpCommandShowsUsageWhenDfmValueUsesSeparateToken;
    [Test]
    procedure OrderIndexHeadersParse;
    [Test]
    procedure DfmTextParserIsSharedByInspectAndCheck;
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for dfm-inspect tree test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected dfm-inspect tree run to succeed. See: ' + lLogPath);

  lOutputText := '';
  if FileExists(lLogPath) then
    lOutputText := ReadUtf8TextFile(lLogPath);

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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for dfm-inspect summary test.');
  Assert.AreEqual(Cardinal(0), lExitCode, 'Expected dfm-inspect summary run to succeed. See: ' + lLogPath);

  lOutputText := '';
  if FileExists(lLogPath) then
    lOutputText := ReadUtf8TextFile(lLogPath);

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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for missing DFM test.');
  Assert.AreEqual(Cardinal(3), lExitCode,
    'Expected missing DFM input to return exit code 3. See: ' + lLogPath);

  lOutputText := '';
  if FileExists(lLogPath) then
    lOutputText := ReadUtf8TextFile(lLogPath);
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

procedure TDfmInspectTests.Utf8TextDfmWithoutBomKeepsCaptionText;
var
  lBytes: TBytes;
  lDfmPath: string;
  lError: string;
  lExpectedCaption: string;
  lOutputText: string;
  lText: string;
begin
  lExpectedCaption := '''Caf' + Char($00E9) + '''';
  lDfmPath := TPath.Combine(TempRoot, 'Utf8CaptionForm.dfm');
  lText :=
    'object Utf8CaptionForm: TForm' + sLineBreak +
    '  Caption = ' + lExpectedCaption + sLineBreak +
    'end' + sLineBreak;
  lBytes := TEncoding.UTF8.GetBytes(lText);
  TFile.WriteAllBytes(lDfmPath, lBytes);

  Assert.IsTrue(TryInspectDfmFile(lDfmPath, 'tree', lOutputText, lError),
    'Expected UTF-8 DFM without BOM to parse. Error: ' + lError);
  Assert.IsTrue(Pos('Caption = ' + lExpectedCaption, lOutputText) > 0,
    'Expected UTF-8 caption text to survive source loading. Output: ' + lOutputText);
end;

procedure TDfmInspectTests.Utf16LeBomTextDfmKeepsCaptionText;
var
  lBody: TBytes;
  lBytes: TBytes;
  lDfmPath: string;
  lError: string;
  lExpectedCaption: string;
  lOutputText: string;
  lText: string;
begin
  lExpectedCaption := '''Caf' + Char($00E9) + '''';
  lDfmPath := TPath.Combine(TempRoot, 'Utf16CaptionForm.dfm');
  lText :=
    'object Utf16CaptionForm: TForm' + sLineBreak +
    '  Caption = ' + lExpectedCaption + sLineBreak +
    'end' + sLineBreak;
  lBody := TEncoding.Unicode.GetBytes(lText);
  SetLength(lBytes, Length(lBody) + 2);
  lBytes[0] := $FF;
  lBytes[1] := $FE;
  Move(lBody[0], lBytes[2], Length(lBody));
  TFile.WriteAllBytes(lDfmPath, lBytes);

  Assert.IsTrue(TryInspectDfmFile(lDfmPath, 'tree', lOutputText, lError),
    'Expected UTF-16LE BOM DFM to parse. Error: ' + lError);
  Assert.IsTrue(Pos('Caption = ' + lExpectedCaption, lOutputText) > 0,
    'Expected UTF-16LE caption text to survive source loading. Output: ' + lOutputText);
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

  Assert.IsTrue(RunResolverProcess(lArgs, RepoRoot, lLogPath, lExitCode),
    'Failed to start resolver for dfm-inspect help test.');
  Assert.AreEqual(Cardinal(0), lExitCode,
    'Expected command-specific help to succeed when --dfm uses a separate token. See: ' + lLogPath);

  lOutputText := '';
  if FileExists(lLogPath) then
    lOutputText := ReadUtf8TextFile(lLogPath);
  Assert.IsTrue(Pos('DelphiAIKit.exe dfm-inspect --dfm', lOutputText) > 0,
    'Expected dfm-inspect usage text. Output: ' + lLogPath);
end;

procedure TDfmInspectTests.OrderIndexHeadersParse;
var
  lDfmPath: string;
  lError: string;
  lOutputText: string;
begin
  lDfmPath := TPath.Combine(TempRoot, 'OrderIndexForm.dfm');
  TFile.WriteAllText(lDfmPath,
    'object OrderIndexForm: TForm' + sLineBreak +
    '  object Button1: TButton [0]' + sLineBreak +
    '    Caption = ''OK''' + sLineBreak +
    '  end' + sLineBreak +
    'end' + sLineBreak, TEncoding.UTF8);

  Assert.IsTrue(TryInspectDfmFile(lDfmPath, 'tree', lOutputText, lError),
    'Expected DFM object headers with order indexes to parse. Error: ' + lError);
  Assert.IsTrue(Pos('Button1: TButton', lOutputText) > 0,
    'Expected order-indexed component in tree output. Output: ' + lOutputText);
end;

procedure TDfmInspectTests.DfmTextParserIsSharedByInspectAndCheck;
var
  lCheckSource: string;
  lInspectSource: string;
  lSharedPath: string;
  lSharedSource: string;
begin
  lSharedPath := TPath.Combine(RepoRoot, 'src\Dak.DfmText.pas');
  Assert.IsTrue(TFile.Exists(lSharedPath),
    'DFM text parsing should live in a shared Dak.DfmText unit.');

  lSharedSource := TFile.ReadAllText(lSharedPath, TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lSharedSource, 'TDfmTextComponent'),
    'Shared parser should expose a component model.');
  Assert.IsTrue(ContainsText(lSharedSource, 'TryLoadDfmTextDocument'),
    'Shared parser should expose the document loading entry point.');

  lInspectSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.dfminspect.pas'), TEncoding.UTF8);
  lCheckSource := TFile.ReadAllText(TPath.Combine(RepoRoot, 'src\dak.dfmcheck.pas'), TEncoding.UTF8);
  Assert.IsTrue(ContainsText(lInspectSource, 'Dak.DfmText'),
    'dfm-inspect should consume the shared DFM text parser.');
  Assert.IsTrue(ContainsText(lCheckSource, 'Dak.DfmText'),
    'dfm-check should consume the shared DFM text parser.');
  Assert.IsFalse(ContainsText(lInspectSource, 'TDfmInspectComponent'),
    'dfm-inspect should not keep a private DFM component model.');
  Assert.IsFalse(ContainsText(lCheckSource, 'TDfmTextObjectInfo'),
    'dfm-check should not keep a private DFM text object model.');
  Assert.IsFalse(ContainsText(lInspectSource, 'TryParseComponentHeader') or
    ContainsText(lCheckSource, 'TryParseDfmTextObjects'),
    'DFM header/object parsing should be centralized in Dak.DfmText.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDfmInspectTests);

end.
