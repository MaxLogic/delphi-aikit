unit Test.App;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAppTests = class
  public
    [Test]
    procedure RunUnhandledExceptionsThroughMadExcept;
    [Test]
    procedure StructuredParseFailuresStayHandled;
    [Test]
    procedure ConfiguresMadExceptUploadOnStartup;
  end;

implementation

uses
  System.SysUtils,
  Dak.App, Dak.ExitCodes;

type
  TAppTestScenario = (atsDispatchSuccess, atsDispatchException, atsParseFailure);

  EAppTestFailure = class(Exception);

  TAppUnderTest = class(TDelphiAIKitApp)
  protected
    fConfiguredBugReportDir: string;
    fCrashReportingConfigured: Boolean;
    fDispatchExitCode: Integer;
    fParseExitCode: Integer;
    fScenario: TAppTestScenario;
    function HandleHelpIfRequested(out aExitCode: Integer): Boolean; override;
    function TryParseOptions(out aExitCode: Integer): Boolean; override;
    function DispatchCommand: Integer; override;
    function ResolveBugReportDir: string; override;
    procedure ApplyMadExceptSettings(const aBugReportDir: string); override;
  public
    class function RunInstance(aApp: TAppUnderTest): Integer; static;
  end;

class function TAppUnderTest.RunInstance(aApp: TAppUnderTest): Integer;
begin
  Result := RunApp(aApp);
end;

function TAppUnderTest.HandleHelpIfRequested(out aExitCode: Integer): Boolean;
begin
  aExitCode := cExitSuccess;
  Result := False;
end;

function TAppUnderTest.TryParseOptions(out aExitCode: Integer): Boolean;
begin
  if fScenario = TAppTestScenario.atsParseFailure then
  begin
    aExitCode := fParseExitCode;
    Exit(False);
  end;

  aExitCode := cExitSuccess;
  Result := True;
end;

function TAppUnderTest.DispatchCommand: Integer;
begin
  if fScenario = TAppTestScenario.atsDispatchException then
    raise EAppTestFailure.Create('dispatch failed');

  Result := fDispatchExitCode;
end;

function TAppUnderTest.ResolveBugReportDir: string;
begin
  Result := 'C:\dak-bugreports\';
end;

procedure TAppUnderTest.ApplyMadExceptSettings(const aBugReportDir: string);
begin
  fCrashReportingConfigured := True;
  fConfiguredBugReportDir := aBugReportDir;
end;

procedure TAppTests.RunUnhandledExceptionsThroughMadExcept;
var
  lApp: TAppUnderTest;
begin
  lApp := TAppUnderTest.Create;
  try
    lApp.fScenario := TAppTestScenario.atsDispatchException;

    try
      TAppUnderTest.RunInstance(lApp);
      Assert.Fail('Expected exception to escape the app runner.');
    except
      on E: EAppTestFailure do
        Assert.AreEqual('dispatch failed', E.Message);
      on E: Exception do
        Assert.Fail('Expected EAppTestFailure but got ' + E.ClassName + ': ' + E.Message);
    end;
  finally
    lApp.Free;
  end;
end;

procedure TAppTests.StructuredParseFailuresStayHandled;
var
  lApp: TAppUnderTest;
  lExitCode: Integer;
begin
  lApp := TAppUnderTest.Create;
  try
    lApp.fParseExitCode := cExitInvalidArgs;
    lApp.fScenario := TAppTestScenario.atsParseFailure;

    lExitCode := TAppUnderTest.RunInstance(lApp);

    Assert.AreEqual(cExitInvalidArgs, lExitCode);
  finally
    lApp.Free;
  end;
end;

procedure TAppTests.ConfiguresMadExceptUploadOnStartup;
var
  lApp: TAppUnderTest;
  lExitCode: Integer;
begin
  lApp := TAppUnderTest.Create;
  try
    lApp.fDispatchExitCode := 17;
    lApp.fScenario := TAppTestScenario.atsDispatchSuccess;

    lExitCode := TAppUnderTest.RunInstance(lApp);

    Assert.AreEqual(17, lExitCode);
    Assert.IsTrue(lApp.fCrashReportingConfigured, 'Expected startup to configure madExcept upload settings.');
    Assert.AreEqual('C:\dak-bugreports\', lApp.fConfiguredBugReportDir);
  finally
    lApp.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAppTests);

end.
