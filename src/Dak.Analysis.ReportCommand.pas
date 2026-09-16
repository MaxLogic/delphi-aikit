unit Dak.Analysis.ReportCommand;

interface

uses
  Dak.Types;

// analyze-report --out <existing output> [--verify]: replay/finalize the reports of an analysis
// output directory or verify them without writing. Mirrors postprocess.py's exit contract:
// 0 success, 2 usage, 3 a rejected result (failed gate or failed verification), 1 a broken run.
function RunAnalyzeReportCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
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
  // The baseline switches are parsed for the policy stage (T-325); refuse them here rather than
  // letting a caller believe a baseline decision was made.
  if aOptions.fHasReportBaselinePath or aOptions.fReportUpdateBaseline then
  begin
    WriteLn(ErrOutput, 'Baseline options are not available yet: this build replays and verifies reports only.');
    Exit(cExitInvalidArgs);
  end;
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
