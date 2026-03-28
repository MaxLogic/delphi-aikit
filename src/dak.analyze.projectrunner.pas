unit Dak.Analyze.ProjectRunner;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.SysUtils,
  Dak.Analyze.Common, Dak.Diagnostics, Dak.FixInsightSettings, Dak.Messages, Dak.ReportPostProcess, Dak.Types;

function RunAnalyzeProject(const aOptions: TAppOptions): Integer;

implementation

uses
  Dak.PascalAnalyzerRunner;

type
  TAnalyzeProjectRunner = class
  private
    fOptions: TAppOptions;
    fDiagnostics: TDiagnostics;
    fErrors: TList<string>;
    fFixOptions: TFixInsightExtraOptions;
    fFixIgnoreDefaults: TFixInsightIgnoreDefaults;
    fReportFilter: TReportFilterDefaults;
    fPascalAnalyzer: TPascalAnalyzerDefaults;
    fParams: TFixInsightParams;
    fProjectDproj: string;
    fProjectName: string;
    fOutRoot: string;
    fFixDir: string;
    fPaDir: string;
    fRunLog: string;
    fFixTxtPath: string;
    fFixXmlPath: string;
    fFixCsvPath: string;
    fFixTxtRan: Boolean;
    fFixXmlRan: Boolean;
    fFixCsvRan: Boolean;
    fFixTxtExit: Integer;
    fFixXmlExit: Integer;
    fFixCsvExit: Integer;
    fFixCounts: TFixInsightCounts;
    fExitCode: Integer;
    fPal: TPalSummary;
    fSummaryPath: string;
    fSummaryText: string;
    procedure AddError(const aMessage: string; const aExitCode: Integer);
    function TryOpenLog: Boolean;
    function TryPrepareParams: Boolean;
    procedure PrepareOutputTree;
    procedure PrepareFixInsightParams;
    procedure InitFixInsightDefaults;
    procedure RunFixInsightReports;
    procedure RunFixInsightReport(const aFormat: TReportFormat; const aOutputPath: string; const aLabel: string;
      var aRan: Boolean; var aExitCode: Integer);
    procedure RunPascalAnalyzer;
    procedure WriteSummary;
    function ShouldFilterReports: Boolean;
  public
    constructor Create(const aOptions: TAppOptions);
    destructor Destroy; override;
    function Execute: Integer;
  end;

constructor TAnalyzeProjectRunner.Create(const aOptions: TAppOptions);
begin
  inherited Create;
  fOptions := aOptions;
  fDiagnostics := TDiagnostics.Create;
  fErrors := TList<string>.Create;
  fExitCode := 0;
end;

destructor TAnalyzeProjectRunner.Destroy;
begin
  fErrors.Free;
  fDiagnostics.Free;
  inherited Destroy;
end;

procedure TAnalyzeProjectRunner.AddError(const aMessage: string; const aExitCode: Integer);
begin
  fErrors.Add(aMessage);
  if (fExitCode = 0) and (aExitCode <> 0) then
    fExitCode := aExitCode;
end;

function TAnalyzeProjectRunner.TryOpenLog: Boolean;
var
  lError: string;
begin
  Result := True;
  fDiagnostics.Verbose := fOptions.fVerbose;
  if fOptions.fHasLogFile then
  begin
    if not fDiagnostics.TryOpenLogFile(TPath.GetFullPath(fOptions.fLogFile), lError) then
    begin
      WriteLn(ErrOutput, lError);
      fExitCode := 6;
      Exit(False);
    end;
    if fOptions.fHasLogTee then
      fDiagnostics.LogToStderr := fOptions.fLogTee
    else
      fDiagnostics.LogToStderr := False;
  end;
end;

function TAnalyzeProjectRunner.TryPrepareParams: Boolean;
var
  lError: string;
  lErrorCode: Integer;
begin
  if not TryPrepareProjectParams(fOptions, fDiagnostics, fParams, fFixOptions, fFixIgnoreDefaults, fReportFilter,
    fPascalAnalyzer, fProjectName, fProjectDproj, lError, lErrorCode) then
  begin
    WriteLn(ErrOutput, lError);
    fExitCode := lErrorCode;
    Exit(False);
  end;
  Result := True;
end;

procedure TAnalyzeProjectRunner.PrepareOutputTree;
begin
  fOutRoot := BuildOutputRoot(fOptions.fAnalyzeOutPath, fProjectDproj, fProjectName);
  if fOptions.fAnalyzeClean and DirectoryExists(fOutRoot) then
    TDirectory.Delete(fOutRoot, True);
  TDirectory.CreateDirectory(fOutRoot);

  fFixDir := TPath.Combine(fOutRoot, 'fixinsight');
  fPaDir := TPath.Combine(fOutRoot, 'pascal-analyzer');
  TDirectory.CreateDirectory(fFixDir);
  TDirectory.CreateDirectory(fPaDir);

  fRunLog := TPath.Combine(fOutRoot, 'run.log');
  if fOptions.fAnalyzeClean or (not FileExists(fRunLog)) then
    WriteLogText(fRunLog, '');
end;

procedure TAnalyzeProjectRunner.PrepareFixInsightParams;
begin
  fParams.fFixIgnore := fFixOptions.fIgnore;
  fParams.fFixSettings := fFixOptions.fSettings;
  fParams.fFixSilent := fFixOptions.fSilent;
  if fParams.fFixSettings <> '' then
    fParams.fFixSettings := TPath.GetFullPath(fParams.fFixSettings);
end;

procedure TAnalyzeProjectRunner.InitFixInsightDefaults;
begin
  fFixTxtPath := TPath.Combine(fFixDir, 'fixinsight.txt');
  fFixXmlPath := TPath.Combine(fFixDir, 'fixinsight.xml');
  fFixCsvPath := TPath.Combine(fFixDir, 'fixinsight.csv');

  fFixTxtRan := False;
  fFixXmlRan := False;
  fFixCsvRan := False;
  fFixTxtExit := -1;
  fFixXmlExit := -1;
  fFixCsvExit := -1;
end;

function TAnalyzeProjectRunner.ShouldFilterReports: Boolean;
begin
  Result := HasAnyReportFilters(fReportFilter.fExcludePathMasks, fFixIgnoreDefaults.fWarnings);
end;

procedure TAnalyzeProjectRunner.RunFixInsightReport(const aFormat: TReportFormat; const aOutputPath: string;
  const aLabel: string; var aRan: Boolean; var aExitCode: Integer);
var
  lRunExit: Cardinal;
  lRunError: string;
  lFilterError: string;
  lLogPath: string;
begin
  aRan := True;
  fParams.fFixOutput := TPath.GetFullPath(aOutputPath);
  if aFormat = TReportFormat.rfXml then
  begin
    fParams.fFixXml := True;
    fParams.fFixCsv := False;
    lLogPath := TPath.Combine(fFixDir, 'fixinsight.xml.log');
  end else if aFormat = TReportFormat.rfCsv then
  begin
    fParams.fFixXml := False;
    fParams.fFixCsv := True;
    lLogPath := TPath.Combine(fFixDir, 'fixinsight.csv.log');
  end
  else
  begin
    fParams.fFixXml := False;
    fParams.fFixCsv := False;
    lLogPath := TPath.Combine(fFixDir, 'fixinsight.txt.log');
  end;

  if TryRunFixInsightLogged(fParams, fRunLog, lRunExit, lRunError) then
  begin
    aExitCode := Integer(lRunExit);
    if aExitCode <> 0 then
      AddError(Format('%s failed (exit=%d).', [aLabel, aExitCode]), aExitCode)
    else if ShouldFilterReports then
    begin
      if not TryPostProcessFixInsightReport(fParams.fFixOutput, aFormat, fReportFilter.fExcludePathMasks,
        fFixIgnoreDefaults.fWarnings, lFilterError) then
      begin
        AddError(aLabel + ' post-processing failed: ' + lFilterError, 6);
      end;
    end;
  end else
  begin
    AddError(aLabel + ' failed: ' + lRunError, 6);
  end;
  WriteToolLog(lLogPath, aLabel, aExitCode, lRunError);
end;

procedure TAnalyzeProjectRunner.RunFixInsightReports;
begin
  PrepareFixInsightParams;
  InitFixInsightDefaults;
  if not fOptions.fAnalyzeFixInsight then
    Exit;

  if TReportFormat.rfText in fOptions.fAnalyzeFiFormats then
    RunFixInsightReport(TReportFormat.rfText, fFixTxtPath, 'FixInsight TXT', fFixTxtRan, fFixTxtExit);
  if TReportFormat.rfXml in fOptions.fAnalyzeFiFormats then
    RunFixInsightReport(TReportFormat.rfXml, fFixXmlPath, 'FixInsight XML', fFixXmlRan, fFixXmlExit);
  if TReportFormat.rfCsv in fOptions.fAnalyzeFiFormats then
    RunFixInsightReport(TReportFormat.rfCsv, fFixCsvPath, 'FixInsight CSV', fFixCsvRan, fFixCsvExit);
end;

procedure TAnalyzeProjectRunner.RunPascalAnalyzer;
var
  lRunExit: Cardinal;
  lRunError: string;
  lPaReportRoot: string;
  lPalPostError: string;
begin
  fPal := Default(TPalSummary);
  if not fOptions.fAnalyzePal then
    Exit;

  fPal.Ran := True;
  if fOptions.fHasPaOutput then
    fPascalAnalyzer.fOutput := TPath.GetFullPath(fOptions.fPaOutput)
  else if fPascalAnalyzer.fOutput <> '' then
    fPascalAnalyzer.fOutput := TPath.GetFullPath(fPascalAnalyzer.fOutput)
  else
    fPascalAnalyzer.fOutput := fPaDir;
  fPal.OutputRoot := fPascalAnalyzer.fOutput;

  if TryRunPalLogged(fParams, fPascalAnalyzer, fRunLog, lRunExit, lRunError) then
  begin
    fPal.ExitCode := Integer(lRunExit);
    if fPal.ExitCode <> 0 then
      AddError(Format('Pascal Analyzer failed (exit=%d).', [fPal.ExitCode]), fPal.ExitCode)
    else
    begin
      try
        if TryFindPalReportRoot(fPal.OutputRoot, lPaReportRoot, lPalPostError) then
        begin
          fPal.ReportRoot := lPaReportRoot;
          ReadStatusSummary(TPath.Combine(lPaReportRoot, 'Status.xml'), fPal.Version, fPal.Compiler);
          fPal.Warnings := GetSectionCountTotal(TPath.Combine(lPaReportRoot, 'Warnings.xml'));
          fPal.StrongWarnings := GetSectionCountTotal(TPath.Combine(lPaReportRoot, 'Strong Warnings.xml'));
          fPal.Exceptions := GetSectionCountTotal(TPath.Combine(lPaReportRoot, 'Exception.xml'));
          if not TryGeneratePalArtifacts(lPaReportRoot, fPal.OutputRoot, lPalPostError) then
            fDiagnostics.AddWarning('PAL findings generation failed: ' + lPalPostError);
        end else
        begin
          fDiagnostics.AddWarning('PAL report root not found: ' + lPalPostError);
        end;
      except
        on E: Exception do
          fDiagnostics.AddWarning('PAL post-processing failed: ' + E.ClassName + ': ' + E.Message);
      end;
    end;
  end else
  begin
    fPal.ExitCode := -1;
    AddError('Pascal Analyzer failed: ' + lRunError, 6);
  end;
  WriteToolLog(TPath.Combine(fPaDir, 'pascal-analyzer.log'), 'PALCMD', fPal.ExitCode, lRunError);
end;

procedure TAnalyzeProjectRunner.WriteSummary;
begin
  if not fOptions.fAnalyzeWriteSummary then
    Exit;

  fSummaryPath := TPath.Combine(fOutRoot, 'summary.md');
  fSummaryText := BuildProjectSummary(fProjectName, fParams.fProjectDpr, fOutRoot, fFixTxtPath, fFixXmlPath,
    fFixCsvPath, fFixTxtRan, fFixXmlRan, fFixCsvRan, fFixTxtExit, fFixXmlExit, fFixCsvExit, fFixCounts, fPal,
    fErrors.ToArray);
  WriteLogText(fSummaryPath, fSummaryText);
end;

function TAnalyzeProjectRunner.Execute: Integer;
begin
  try
    if not TryOpenLog then
      Exit(fExitCode);
    if not TryPrepareParams then
      Exit(fExitCode);
    PrepareOutputTree;
    RunFixInsightReports;
    RunPascalAnalyzer;
    fFixCounts := Default(TFixInsightCounts);
    if fFixTxtRan and FileExists(fFixTxtPath) then
      CaptureFixInsightSummary(fFixTxtPath, fFixCounts);
    WriteSummary;
  finally
    fDiagnostics.WriteToStderr;
  end;
  Result := fExitCode;
end;
function RunAnalyzeProject(const aOptions: TAppOptions): Integer;
var
  lRunner: TAnalyzeProjectRunner;
begin
  lRunner := TAnalyzeProjectRunner.Create(aOptions);
  try
    Result := lRunner.Execute;
  finally
    lRunner.Free;
  end;
end;
end.
