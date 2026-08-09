unit Test.FixInsight;

interface

uses
  System.Classes, System.Diagnostics, System.IOUtils, System.RegularExpressions, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  DUnitX.TestFramework,
  Dak.ExternalToolProcess,
  Test.Support;

type
  [TestFixture]
  TFixInsightTests = class
  private
    procedure AppendProgress(const aMessage: string);
    function RunFixInsightOutput(const aSuffix, aFormat, aMasks, aIds, aOutRoot: string): string;
    procedure RunFixInsightOutputs(const aSuffix, aMasks, aIds: string;
      out aTxt, aXml, aCsv: string);
    procedure ExtractIdsAndFile(const aText: string; out aId1, aId2, aFileName: string);
  public
    [Test]
    procedure FixInsightProcessWaitsAreBounded;
    [Test]
    procedure FixInsightTimeoutTerminatesChildProcess;
    [Test]
    procedure FixInsightRawReportsPreserveFilteredEvidence;
  end;

implementation

procedure TFixInsightTests.AppendProgress(const aMessage: string);
var
  lPath: string;
begin
  lPath := TPath.Combine(TempRoot, 'fixinsight-progress.log');
  TFile.AppendAllText(lPath, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now) + ' ' + aMessage + sLineBreak,
    TEncoding.UTF8);
end;

function TFixInsightTests.RunFixInsightOutput(const aSuffix, aFormat, aMasks, aIds, aOutRoot: string): string;
var
  lArgs: string;
  lExit: Cardinal;
  lLog: string;
  lLogName: string;
  lStopwatch: TStopwatch;
begin
  if TDirectory.Exists(aOutRoot) then
    TDirectory.Delete(aOutRoot, True);
  TDirectory.CreateDirectory(aOutRoot);

  lArgs := 'analyze --project ' + QuoteArg(TPath.Combine(RepoRoot, 'projects\\DelphiAIKit.dproj')) +
    ' --platform Win32 --config Release --delphi 23.0 --out ' + QuoteArg(aOutRoot) +
    ' --fixinsight true --pascal-analyzer false --fi-formats ' + aFormat;

  if aMasks <> '' then
    lArgs := lArgs + ' --exclude-path-masks ' + QuoteArg(aMasks);
  if aIds <> '' then
    lArgs := lArgs + ' --ignore-warning-ids ' + QuoteArg(aIds);

  lLogName := FormatDateTime('yyyymmddhhnnsszzz', Now) + '-fixinsight-' + aFormat + '.log';
  lLog := TPath.Combine(aOutRoot, lLogName);
  AppendProgress(Format('start suffix=%s format=%s log=%s', [aSuffix, aFormat, lLog]));
  WriteLn(Format('[fixinsight-test] start suffix=%s format=%s log=%s', [aSuffix, aFormat, lLog]));
  lStopwatch := TStopwatch.StartNew;
  if not RunResolverProcess(lArgs, RepoRoot, lLog, lExit) then
    Assert.Fail('Failed to start FixInsight analyze: ' + lLog);
  lStopwatch.Stop;
  AppendProgress(Format('done suffix=%s format=%s exit=%d elapsedMs=%d',
    [aSuffix, aFormat, lExit, lStopwatch.ElapsedMilliseconds]));
  WriteLn(Format('[fixinsight-test] done suffix=%s format=%s exit=%d elapsedMs=%d',
    [aSuffix, aFormat, lExit, lStopwatch.ElapsedMilliseconds]));
  if lExit <> 0 then
    Assert.Fail('FixInsight analyze failed, exit=' + lExit.ToString + '. See: ' + lLog);

  Result := TPath.Combine(aOutRoot, 'fixinsight\\fixinsight.' + aFormat);
  Assert.IsTrue(FileExists(Result), 'Missing FixInsight output: ' + Result);
end;

procedure TFixInsightTests.RunFixInsightOutputs(const aSuffix, aMasks, aIds: string;
  out aTxt, aXml, aCsv: string);
var
  lOutRoot: string;
begin
  lOutRoot := TPath.Combine(TempRoot, 'fixinsight-' + aSuffix + '-txt');
  aTxt := RunFixInsightOutput(aSuffix, 'txt', aMasks, aIds, lOutRoot);
  lOutRoot := TPath.Combine(TempRoot, 'fixinsight-' + aSuffix + '-xml');
  aXml := RunFixInsightOutput(aSuffix, 'xml', aMasks, aIds, lOutRoot);
  lOutRoot := TPath.Combine(TempRoot, 'fixinsight-' + aSuffix + '-csv');
  aCsv := RunFixInsightOutput(aSuffix, 'csv', aMasks, aIds, lOutRoot);
end;

procedure TFixInsightTests.ExtractIdsAndFile(const aText: string; out aId1, aId2, aFileName: string);
var
  lLines: TStringList;
  lLine: string;
  lMatch: TMatch;
  lFilePath: string;
  lId: string;
  function IsNewId(const aValue: string): Boolean;
  begin
    Result := (aValue <> '') and (not SameText(aValue, aId1)) and (not SameText(aValue, aId2));
  end;
begin
  aId1 := '';
  aId2 := '';
  aFileName := '';
  lFilePath := '';
  lLines := TStringList.Create;
  try
    lLines.Text := aText;
    for lLine in lLines do
    begin
      if StartsText('File:', lLine) and (lFilePath = '') then
      begin
        lFilePath := Trim(Copy(lLine, Length('File:') + 1, MaxInt));
        if lFilePath <> '' then
          aFileName := TPath.GetFileName(lFilePath);
      end;

      lMatch := TRegEx.Match(lLine, '^\s*([A-Z]\d{3})\b');
      if lMatch.Success then
      begin
        lId := lMatch.Groups[1].Value;
        if (aId1 = '') then
          aId1 := lId
        else if (aId2 = '') and IsNewId(lId) then
          aId2 := lId;
      end;
    end;
  finally
    lLines.Free;
  end;

  if (aId1 <> '') and (aId2 = '') then
    aId2 := aId1;
end;

procedure TFixInsightTests.FixInsightProcessWaitsAreBounded;
var
  lPath: string;
  lText: string;
begin
  lPath := TPath.Combine(RepoRoot, 'src\dak.fixinsightrunner.pas');
  lText := TFile.ReadAllText(lPath, TEncoding.UTF8);
  Assert.IsFalse(TRegEx.IsMatch(lText, 'WaitForSingleObject\s*\([^,]+,\s*INFINITE\s*\)', [roIgnoreCase]),
    'FixInsight subprocess waits must use bounded timeouts.');
end;

procedure TFixInsightTests.FixInsightTimeoutTerminatesChildProcess;
var
  lError: string;
  lExit: Cardinal;
  lProcess: THandle;
  lThread: THandle;
begin
  Assert.IsTrue(StartSlowPingProcess(lProcess, lThread, lError), lError);
  try
    Assert.IsFalse(TryWaitForExternalToolProcess('FixInsightCL.exe', lProcess, 1, lExit, lError),
      'Expected timeout failure.');
    Assert.AreEqual(Cardinal(cExternalToolTimeoutExitCode), lExit, 'Timeout exit code should be deterministic.');
    Assert.IsTrue(Pos('FixInsightCL.exe timed out after 1 seconds.', lError) > 0,
      'Timeout diagnostic should name FixInsight. Actual: ' + lError);
    Assert.IsTrue(WaitForSingleObject(lProcess, 0) = WAIT_OBJECT_0,
      'Timeout handling should terminate the child process.');
  finally
    if (lProcess <> 0) and (WaitForSingleObject(lProcess, 0) <> WAIT_OBJECT_0) then
      TerminateProcess(lProcess, 1);
    if lThread <> 0 then
      CloseHandle(lThread);
    if lProcess <> 0 then
      CloseHandle(lProcess);
  end;
end;

procedure TFixInsightTests.FixInsightRawReportsPreserveFilteredEvidence;
var
  lFixInsightExe: string;
  lBaseTxt, lBaseXml, lBaseCsv: string;
  lExclTxt, lExclXml, lExclCsv: string;
  lIdsTxt, lIdsXml, lIdsCsv: string;
  lText: string;
  lId1, lId2, lFileName: string;
  lMask: string;
  lIds: string;
begin
  EnsureResolverBuilt;
  RequireFixInsightOrSkip(lFixInsightExe);
  TFile.WriteAllText(TPath.Combine(TempRoot, 'fixinsight-progress.log'), '', TEncoding.UTF8);

  RunFixInsightOutputs('base', '', '', lBaseTxt, lBaseXml, lBaseCsv);
  lText := ReadUtf8TextFile(lBaseTxt);
  ExtractIdsAndFile(lText, lId1, lId2, lFileName);

  Assert.IsTrue(lId1 <> '', 'No FixInsight warning IDs found in baseline output.');
  Assert.IsTrue(lFileName <> '', 'No FixInsight file entries found in baseline output.');

  lMask := '*' + lFileName;
  RunFixInsightOutputs('exclude', lMask, '', lExclTxt, lExclXml, lExclCsv);

  Assert.IsTrue(ContainsText(ReadUtf8TextFile(lExclTxt), lFileName), 'Exclude mask erased raw text evidence.');
  Assert.IsTrue(ContainsText(ReadUtf8TextFile(lExclXml), lFileName), 'Exclude mask erased raw XML evidence.');
  Assert.IsTrue(ContainsText(ReadUtf8TextFile(lExclCsv), lFileName), 'Exclude mask erased raw CSV evidence.');

  lIds := lId1 + ';' + lId2;
  RunFixInsightOutputs('ignore-ids', '', lIds, lIdsTxt, lIdsXml, lIdsCsv);

  Assert.IsTrue(ContainsText(ReadUtf8TextFile(lIdsTxt), lId1), 'Rule policy erased raw text evidence.');
  Assert.IsTrue(ContainsText(ReadUtf8TextFile(lIdsTxt), lId2), 'Rule policy erased raw text evidence.');
  Assert.IsTrue(ContainsText(ReadUtf8TextFile(lIdsXml), lId1), 'Rule policy erased raw XML evidence.');
  Assert.IsTrue(ContainsText(ReadUtf8TextFile(lIdsXml), lId2), 'Rule policy erased raw XML evidence.');
  Assert.IsTrue(ContainsText(ReadUtf8TextFile(lIdsCsv), ',' + lId1 + ','), 'Rule policy erased raw CSV evidence.');
  Assert.IsTrue(ContainsText(ReadUtf8TextFile(lIdsCsv), ',' + lId2 + ','), 'Rule policy erased raw CSV evidence.');
end;

initialization
  TDUnitX.RegisterTestFixture(TFixInsightTests);

end.
