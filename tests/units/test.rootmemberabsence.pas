unit Test.RootMemberAbsence;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRootMemberAbsenceTests = class
  public
    [Test]
    [TestCase('Win32 Halt0', 'win32,dcc32.exe,halt')]
    [TestCase('Win64 Halt0', 'win64,dcc64.exe,halt')]
    [TestCase('Win32 early exit', 'win32,dcc32.exe,exit')]
    [TestCase('Win64 early exit', 'win64,dcc64.exe,exit')]
    [TestCase('Write failure', 'win64,dcc64.exe,write-failure')]
    [TestCase('Flush failure', 'win64,dcc64.exe,flush-failure')]
    [TestCase('Large dependencies', 'win64,dcc64.exe,large-dependencies')]
    [TestCase('Large runtime', 'win64,dcc64.exe,large-runtime')]
    procedure ConsumerRefusesIncompleteOrFailedWitness(const aPlatform, aCompilerName, aMode: string);
    [Test]
    procedure ProviderCleanupPreservesUnknownFiles;
    [Test]
    [TestCase('Win32', 'win32,dcc32.exe')]
    [TestCase('Win64', 'win64,dcc64.exe')]
    procedure NativeWitnessDistinguishesExactNames(const aPlatform, aCompilerName: string);
    [Test]
    procedure MissingToolchainAndInvalidCompilerRemainUnavailable;
    [Test]
    procedure LockedInputsPreventDriftAndNewProviderRejectsCorruptSdk;
    [Test]
    procedure UnavailableScratchRetainsOptionalRefusal;
    [Test]
    procedure RetargetedSdkParentInvalidatesMemoizedEvidence;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.SysUtils,
  Winapi.Windows,
  maxLogic.ioutils,
  Dak.RootMemberAbsence, DelphiSemantics.RootMemberAbsence,
  Test.Support;

const
  cStudioRoot = 'C:\Program Files (x86)\Embarcadero\Studio\23.0';

procedure TRootMemberAbsenceTests.NativeWitnessDistinguishesExactNames(
  const aPlatform, aCompilerName: string);
var
  lCount: Integer;
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-root-' + aPlatform);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(
    TPath.Combine(cStudioRoot, 'bin\' + aCompilerName),
    TPath.Combine(cStudioRoot, 'lib\' + aPlatform + '\debug'), lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.AreNotEqual('', lProvider.EvidenceFingerprint);
  Assert.IsTrue(lProvider.IsNameAbsent('lPair'));
  Assert.IsTrue(lProvider.IsNameAbsent('LeftOnly'));
  Assert.IsFalse(lProvider.IsNameAbsent('ClassName'));
  Assert.IsFalse(lProvider.IsNameAbsent('Disposed'));
  Assert.IsFalse(lProvider.IsNameAbsent('GetDisposed'));
  lCount := Length(TDirectory.GetDirectories(TPath.Combine(lRoot, 'root-member-absence')));
  Assert.AreEqual(5, lCount);
  Assert.IsTrue(lProvider.IsNameAbsent('LPAIR'));
  Assert.IsFalse(lProvider.IsNameAbsent('CLASSNAME'));
  Assert.IsFalse(lProvider.IsNameAbsent(''));
  Assert.IsFalse(lProvider.IsNameAbsent('x); Halt(0)'));
  Assert.AreEqual(lCount,
    Integer(Length(TDirectory.GetDirectories(TPath.Combine(lRoot, 'root-member-absence')))),
    'Case-insensitive memoization and invalid names must not run additional probes.');
end;

procedure TRootMemberAbsenceTests.MissingToolchainAndInvalidCompilerRemainUnavailable;
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-root-unavailable');
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(lRoot, 'dcc64.exe'),
    TPath.Combine(lRoot, 'sdk'), lRoot, lReason);
  Assert.IsTrue(lProvider = nil);
  Assert.AreNotEqual('', lReason);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    TPath.Combine(lRoot, 'missing-sdk'), lRoot, lReason);
  Assert.IsTrue(lProvider = nil);
  Assert.AreNotEqual('', lReason);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(lRoot, 'unexpected.exe'),
    TPath.Combine(lRoot, 'sdk'), lRoot, lReason);
  Assert.IsTrue(lProvider = nil);
  Assert.AreEqual('unsupported-native-compiler', lReason);
end;

procedure TRootMemberAbsenceTests.LockedInputsPreventDriftAndNewProviderRejectsCorruptSdk;
var
  lBlocked: Boolean;
  lByte: Byte;
  lFingerprint: string;
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason: string;
  lRoot: string;
  lSdkRoot: string;
  lStream: TFileStream;
begin
  // Only task-owned SDK copies are mutated; the installed SDK stays read-only.
  lRoot := UniqueTempPath('native-root-input-lock');
  lSdkRoot := TPath.Combine(lRoot, 'sdk');
  TDirectory.CreateDirectory(lSdkRoot);
  TFile.Copy(TPath.Combine(cStudioRoot, 'lib\win64\debug\System.dcu'),
    TPath.Combine(lSdkRoot, 'System.dcu'));
  TFile.Copy(TPath.Combine(cStudioRoot, 'lib\win64\debug\SysInit.dcu'),
    TPath.Combine(lSdkRoot, 'SysInit.dcu'));
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    lSdkRoot, lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  lFingerprint := lProvider.EvidenceFingerprint;
  Assert.IsTrue(lProvider.IsNameAbsent('lPair'));
  lBlocked := False;
  lStream := nil;
  try
    try
      lStream := TFileStream.Create(TPath.Combine(lSdkRoot, 'SysInit.dcu'),
        fmOpenReadWrite or fmShareDenyNone);
    except
      on E: EFOpenError do
        lBlocked := True;
    end;
  finally
    lStream.Free;
  end;
  Assert.IsTrue(lBlocked, 'A provider must retain OS-enforced immutable inputs.');
  Assert.IsTrue(lProvider.IsNameAbsent('lPair'));
  lProvider := nil;
  lStream := TFileStream.Create(TPath.Combine(lSdkRoot, 'SysInit.dcu'),
    fmOpenReadWrite or fmShareDenyNone);
  try
    lStream.ReadBuffer(lByte, SizeOf(lByte));
    lByte := lByte xor $FF;
    lStream.Position := 0;
    lStream.WriteBuffer(lByte, SizeOf(lByte));
  finally
    lStream.Free;
  end;
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    lSdkRoot, lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.AreNotEqual(lFingerprint, lProvider.EvidenceFingerprint);
  Assert.IsFalse(lProvider.IsNameAbsent('lPair'),
    'A new input identity cannot reuse a prior successful name absence.');
end;

procedure TRootMemberAbsenceTests.UnavailableScratchRetainsOptionalRefusal;
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason: string;
  lRoot: string;
begin
  lRoot := UniqueTempPath('native-root-blocked-scratch');
  TDirectory.CreateDirectory(lRoot);
  TFile.WriteAllText(TPath.Combine(lRoot, 'root-member-absence'),
    'Task-owned scratch conflict.', TEncoding.UTF8);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    TPath.Combine(cStudioRoot, 'lib\win64\debug'), lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsFalse(lProvider.IsNameAbsent('lPair'));
end;

procedure TRootMemberAbsenceTests.RetargetedSdkParentInvalidatesMemoizedEvidence;
var
  lExitCode: Cardinal;
  lFirstRoot: string;
  lName: string;
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason: string;
  lRoot: string;
  lSdkAlias: string;
  lSecondRoot: string;
begin
  lRoot := UniqueTempPath('native-root-retarget');
  lFirstRoot := TPath.Combine(lRoot, 'sdk-first');
  lSecondRoot := TPath.Combine(lRoot, 'sdk-second');
  lSdkAlias := TPath.Combine(lRoot, 'sdk-alias');
  TDirectory.CreateDirectory(lFirstRoot);
  TDirectory.CreateDirectory(lSecondRoot);
  for lName in ['System.dcu', 'SysInit.dcu'] do
  begin
    TFile.Copy(CombinePath([cStudioRoot, 'lib', 'Win64', 'release', lName]),
      TPath.Combine(lFirstRoot, lName));
    TFile.Copy(CombinePath([cStudioRoot, 'lib', 'Win64', 'release', lName]),
      TPath.Combine(lSecondRoot, lName));
  end;
  Assert.IsTrue(RunProcess(GetEnvironmentVariable('COMSPEC'),
    '/d /c mklink /J "' + lSdkAlias + '" "' + lFirstRoot + '"', lRoot,
    TPath.Combine(lRoot, 'first-link.log'), lExitCode));
  Assert.AreEqual(Cardinal(0), lExitCode);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(CombinePath([cStudioRoot, 'bin', 'dcc64.exe']),
    lSdkAlias, lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(lProvider.IsNameAbsent('lPair'));
  Assert.IsTrue(lProvider.EvidenceFingerprint <> '');
  // Move only our junction, preserving both task-owned target directories and locked inputs.
  Assert.IsTrue(MoveFile(PChar(lSdkAlias), PChar(TPath.Combine(lRoot, 'prior-sdk-link'))));
  Assert.IsTrue(RunProcess(GetEnvironmentVariable('COMSPEC'),
    '/d /c mklink /J "' + lSdkAlias + '" "' + lSecondRoot + '"', lRoot,
    TPath.Combine(lRoot, 'second-link.log'), lExitCode));
  Assert.AreEqual(Cardinal(0), lExitCode);
  Assert.IsFalse(lProvider.IsNameAbsent('lPair'), 'A memo hit cannot retain a different physical input.');
  Assert.IsFalse(lProvider.IsNameAbsent('LeftOnly'));
  Assert.AreEqual('', lProvider.EvidenceFingerprint);
end;

type
  TWitnessFailureIO = class(TInterfacedObject, IDakNativeWitnessIO)
  private
    fMode: string;
    fInner: IDakNativeWitnessIO;
  public
    constructor Create(const aMode: string);
    procedure WriteText(const aFileName, aText: string; const aEncoding: TEncoding);
    function ReadTextBounded(const aFileName: string; const aLimit: Integer;
      const aEncoding: TEncoding): string;
    function FlushOutput(const aHandle: NativeUInt): Boolean;
  end;

constructor TWitnessFailureIO.Create(const aMode: string);
begin
  inherited Create;
  fMode := aMode;
  fInner := CreateNativeWitnessIO;
end;

procedure TWitnessFailureIO.WriteText(const aFileName, aText: string; const aEncoding: TEncoding);
var
  lText: string;
begin
  if fMode = 'write-failure' then
    raise EWriteError.Create('deliberate witness write failure');
  lText := aText;
  if SameText(TPath.GetExtension(aFileName), '.dpr') then
  begin
    if fMode = 'halt' then
      lText := StringReplace(lText, '  lProbe := TProbe.Create;',
        '  Halt(0);' + sLineBreak + '  lProbe := TProbe.Create;', [])
    else if fMode = 'exit' then
      lText := StringReplace(lText, '  lProbe := TProbe.Create;',
        '  Exit;' + sLineBreak + '  lProbe := TProbe.Create;', []);
  end;
  fInner.WriteText(aFileName, lText, aEncoding);
end;

function TWitnessFailureIO.ReadTextBounded(const aFileName: string; const aLimit: Integer;
  const aEncoding: TEncoding): string;
begin
  if ((fMode = 'large-dependencies') and SameText(TPath.GetExtension(aFileName), '.d')) or
    ((fMode = 'large-runtime') and SameText(TPath.GetFileName(aFileName), 'runtime.log')) then
    fInner.WriteText(aFileName, StringOfChar('x', aLimit + 1), aEncoding);
  Result := fInner.ReadTextBounded(aFileName, aLimit, aEncoding);
end;

function TWitnessFailureIO.FlushOutput(const aHandle: NativeUInt): Boolean;
begin
  Result := fInner.FlushOutput(aHandle) and (fMode <> 'flush-failure');
end;

procedure TRootMemberAbsenceTests.ConsumerRefusesIncompleteOrFailedWitness(
  const aPlatform, aCompilerName, aMode: string);
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason, lRoot, lRunRoot, lOutput: string;
  lIO: IDakNativeWitnessIO;
begin
  lRoot := UniqueTempPath('native-consumer-' + aMode + '-' + aPlatform);
  lIO := TWitnessFailureIO.Create(aMode);
  lProvider := TryCreateNativeImplicitRootMemberAbsence(
    TPath.Combine(cStudioRoot, 'bin\' + aCompilerName),
    TPath.Combine(cStudioRoot, 'lib\' + aPlatform + '\release'), lRoot, lIO, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsFalse(lProvider.IsNameAbsent('lPair'));
  lRunRoot := TDirectory.GetDirectories(TPath.Combine(lRoot, 'root-member-absence'))[0];
  if (aMode = 'halt') or (aMode = 'exit') then
  begin
    Assert.IsTrue(TFile.Exists(TPath.Combine(lRunRoot, 'runtime.log')),
      'Fresh compiler and runtime must both execute the mutated witness');
    Assert.IsFalse(TFile.Exists(TPath.Combine(lRunRoot, 'runtime.log.status')),
      'Exit zero alone must still refuse');
    lOutput := TFile.ReadAllText(TPath.Combine(lRunRoot, 'runtime.log'));
    Assert.AreEqual('', lOutput);
    Assert.IsTrue(TFile.ReadAllText(TPath.Combine(lRunRoot, 'result.txt')).Contains('absent=False'));
  end else if aMode = 'flush-failure' then
    Assert.IsTrue(TFile.Exists(TPath.Combine(lRunRoot, 'compiler.log.status')))
  else
  begin
    lOutput := TFile.ReadAllText(TPath.Combine(lRunRoot, 'refusal.txt'));
    if aMode = 'write-failure' then
      Assert.IsTrue(lOutput.Contains('deliberate witness write failure'), lOutput)
    else
      Assert.IsTrue(lOutput.Contains('size limit'), lOutput);
  end;
end;

procedure TRootMemberAbsenceTests.ProviderCleanupPreservesUnknownFiles;
var
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lReason, lRoot, lRunRoot, lUnknown: string;
begin
  lRoot := UniqueTempPath('native-cleanup');
  lProvider := TryCreateNativeImplicitRootMemberAbsence(
    TPath.Combine(cStudioRoot, 'bin\dcc64.exe'),
    TPath.Combine(cStudioRoot, 'lib\win64\release'), lRoot, lReason);
  Assert.IsTrue(lProvider <> nil, lReason);
  Assert.IsTrue(lProvider.IsNameAbsent('lPair'));
  lRunRoot := TDirectory.GetDirectories(TPath.Combine(lRoot, 'root-member-absence'))[0];
  lUnknown := TPath.Combine(lRunRoot, 'unrelated.keep');
  TFile.WriteAllText(lUnknown, 'preserve these bytes', TEncoding.ASCII);
  lProvider := nil;
  Assert.AreEqual('preserve these bytes', TFile.ReadAllText(lUnknown));
  Assert.AreEqual(1, Integer(Length(TDirectory.GetFiles(lRunRoot))));
end;

initialization
  TDUnitX.RegisterTestFixture(TRootMemberAbsenceTests);

end.
