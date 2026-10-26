unit Test.RemoveWith.LongPath;

interface

uses
  DUnitX.TestFramework;

type
  // T-263: remove-with on a valid project whose verification workspace path passes the classic 260
  // character limit must finish with a structured result instead of an unhandled EInOutError.
  [TestFixture]
  [Category('Slow')]
  TRemoveWithLongPathTests = class
  public
    [Test]
    procedure ApplyUnderALongVerificationWorkspaceFinishesTheTransaction;
  end;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
  Dak.Paths, Dak.RemoveWith.Transaction, Dak.Utils,
  Test.Support;

const
  cFixtureName = 'RemoveWithApplyFixture';
  // <project dir>\.dak\<name>\remove-with\<run token>\<preflight dir>\stdout.log beyond the project dir; DAK-385
  // derives it from the product's layout constants.
  cWorkspaceSuffixLength = Length('\.dak\') + Length(cFixtureName) + Length('\') +
    Length(cRemoveWithWorkspaceDirName) + Length('\') + cDakRunTokenLength + Length('\') +
    Length(cRemoveWithPreflightDirName) + Length('\stdout.log');

procedure TRemoveWithLongPathTests.ApplyUnderALongVerificationWorkspaceFinishesTheTransaction;
var
  lArgs, lDproj, lFile, lLog, lOutput, lPadded, lProjectDir, lRoot: string;
  lExit: Cardinal;
  lJson: TJSONValue;
  lTransaction: TJSONObject;
begin
  EnsureResolverBuilt;
  lRoot := UniqueNoRepoTempPath('rw-long');
  // Pad one directory so the preflight log path is at least 262 characters long.
  lPadded := TPath.Combine(lRoot, StringOfChar('p', 262 - cWorkspaceSuffixLength - Length(lRoot) - Length(cFixtureName) - 2));
  lProjectDir := TPath.Combine(lPadded, cFixtureName);
  try
    TDirectory.CreateDirectory(lProjectDir);
    for lFile in TDirectory.GetFiles(TPath.Combine(RepoRoot, 'tests\fixtures\' + cFixtureName)) do
      TFile.Copy(lFile, TPath.Combine(lProjectDir, TPath.GetFileName(lFile)));
    lDproj := TPath.Combine(lProjectDir, cFixtureName + '.dproj');
    Assert.IsTrue(Length(lProjectDir) + cWorkspaceSuffixLength >= 262, 'the fixture path must exceed MAX_PATH');

    lLog := TPath.Combine(lRoot, 'apply.log');
    lArgs := 'remove-with --project ' + QuoteArg(lDproj) +
      ' --all --mode apply --format json --delphi 23.0 --platform Win32 --config Debug';
    Assert.IsTrue(RunCommandProcess(ResolverExePath, lArgs, lRoot, lLog, lExit), 'remove-with must start');
    // An unhandled exception prints the system message in the ANSI code page, which is not UTF-8.
    try
      lOutput := TEncoding.UTF8.GetString(TFile.ReadAllBytes(lLog));
    except
      on EEncodingError do
        lOutput := TEncoding.ANSI.GetString(TFile.ReadAllBytes(lLog));
    end;
    Assert.IsFalse(lOutput.Contains('EInOutError'), 'no unhandled I/O exception: ' + lOutput);
    Assert.AreEqual(Cardinal(0), lExit, lOutput);
    lJson := ParseJsonValue(lOutput);
    try
      Assert.IsTrue(lJson is TJSONObject, 'structured JSON result: ' + lOutput);
      lTransaction := TJSONObject(lJson).GetValue('transaction') as TJSONObject;
      Assert.IsNotNull(lTransaction, lOutput);
      Assert.AreEqual('applied', lTransaction.GetValue<string>('status'), lOutput);
      // The manifest can itself sit at the limit, and this test process is not long-path aware.
      Assert.IsTrue(TFile.Exists(LongPathSafe(lTransaction.GetValue<string>('manifestPath'))),
        'the transaction manifest exists');
    finally
      lJson.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRemoveWithLongPathTests);

end.
