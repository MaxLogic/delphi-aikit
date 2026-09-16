unit Dak.Analysis.ReportCommand;

interface

uses
  Dak.Types;

// analyze-report --out <existing output> [--verify] [--baseline <file>] [--update-baseline]:
// replay/finalize the reports of an analysis output directory, or verify them without writing.
// Mirrors postprocess.py's exit contract: 0 success, 2 usage, 3 a rejected result (failed gate
// or failed verification), 1 a broken run.
function RunAnalyzeReportCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
  Winapi.Windows,
  AutoFree,
  Dak.Analysis.JsonText, Dak.Analysis.ReportBundle, Dak.Analysis.ReportReplay, Dak.Analysis.ReportVerify,
  Dak.CommandOutput, Dak.ExitCodes;

function RunAnalyzeReportCommand(const aOptions: TAppOptions): Integer;
var
  g: TGarbos;
  lCounts, lDocument, lResult: TJSONObject;
  lError, lOutRoot, lText: string;
begin
  lOutRoot := Trim(aOptions.fAnalyzeOutPath);
  if lOutRoot = '' then
  begin
    WriteLn(ErrOutput, 'Usage: DelphiAIKit.exe analyze-report --out "<path-to-analysis-out-root>" [--verify]');
    Exit(cExitInvalidArgs);
  end;
  // The switches select the baseline the policy stage reads, the same selection the wrappers make
  // through the environment; an explicit switch wins over an inherited variable.
  // The switch parser already rejects a missing or empty --baseline value.
  if aOptions.fHasReportBaselinePath then
    SetEnvironmentVariable('DAK_BASELINE', PChar(TPath.GetFullPath(Trim(aOptions.fReportBaselinePath))));
  if aOptions.fReportUpdateBaseline then
    SetEnvironmentVariable('DAK_UPDATE_BASELINE', PChar('1'));
  lOutRoot := TPath.GetFullPath(lOutRoot);
  try
    if aOptions.fReportVerify then
    begin
      GC(lCounts, VerifyAnalysisReport(lOutRoot), g);
      GC(lDocument, TJSONObject.Create, g);
      lDocument.AddPair('ownership', JsonCloneValue(lCounts));
      lDocument.AddPair('verified', TJSONBool.Create(True));
      lText := TPythonJson.SortedLine(lDocument);
      Result := cExitSuccess;
    end else begin
      GC(lResult, FinalizeAnalysisReport(lOutRoot, nil, -1), g);
      lText := TPythonJson.Document(lResult).TrimRight([#10]);
      if (lResult.GetValue('gate_pass') is TJSONBool) and not TJSONBool(lResult.GetValue('gate_pass')).AsBoolean then
        Result := cExitRejectedResult
      else
        Result := cExitSuccess;
    end;
  except
    on e: Exception do
    begin
      // A rejected verification is a result; a failed replay is a broken run, as in the reference.
      if aOptions.fReportVerify then
      begin
        WriteLn(ErrOutput, 'ERROR: ' + e.Message);
        Exit(cExitRejectedResult);
      end;
      WriteLn(ErrOutput, e.ClassName + ': ' + e.Message);
      Exit(cExitUnhandledException);
    end;
  end;
  if not WriteCommandOutput(lText, '', TCommandOutputPolicy.copStdoutWhenNoPathOrDash, True, False, False, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Result := cExitEnvironmentError;
  end;
end;

end.
