unit Dak.Analyze.UnitRunner;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.SysUtils,
  Dak.Analyze.Common, Dak.Diagnostics, Dak.Messages, Dak.Settings, Dak.Types, Dak.Utils;

function RunAnalyzeUnit(const aOptions: TAppOptions): Integer;

implementation

uses
  System.Diagnostics,
  Dak.PascalAnalyzer.Artifacts, Dak.PascalAnalyzerRunner;

type
  TAnalyzeUnitRunner = class
  private
    fOptions: TAppOptions;
    fDiagnostics: TDiagnostics;
    fErrors: TList<string>;
    fFixOptions: TFixInsightExtraOptions;
    fFixIgnoreDefaults: TFixInsightIgnoreDefaults;
    fReportFilter: TReportFilterDefaults;
    fPascalAnalyzer: TPascalAnalyzerDefaults;
    fSettings: TDakSettings;
    fParams: TFixInsightParams;
    fOutRoot: string;
    fPaDir: string;
    fRunLog: string;
    fUnitPath: string;
    fUnitName: string;
    fProjectContextPath: string;
    fExitCode: Integer;
    fPal: TPalSummary;
    fPalDurationMs: Int64;
    fSummaryPath: string;
    fSummaryText: string;
    procedure AddError(const aMessage: string; const aExitCode: Integer);
    function TryOpenLog: Boolean;
    function TryLoadSettings: Boolean;
    function TryPrepareUnit: Boolean;
    procedure PrepareOutputTree;
    procedure RunPascalAnalyzer;
    procedure WriteSummary;
  public
    constructor Create(const aOptions: TAppOptions);
    destructor Destroy; override;
    function Execute: Integer;
  end;

constructor TAnalyzeUnitRunner.Create(const aOptions: TAppOptions);
begin
  inherited Create;
  fOptions := aOptions;
  fDiagnostics := TDiagnostics.Create;
  fErrors := TList<string>.Create;
  fExitCode := 0;
end;

destructor TAnalyzeUnitRunner.Destroy;
begin
  fErrors.Free;
  fDiagnostics.Free;
  inherited Destroy;
end;

procedure TAnalyzeUnitRunner.AddError(const aMessage: string; const aExitCode: Integer);
begin
  fErrors.Add(aMessage);
  if (fExitCode = 0) and (aExitCode <> 0) then
    fExitCode := aExitCode;
end;

function TAnalyzeUnitRunner.TryOpenLog: Boolean;
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

function TAnalyzeUnitRunner.TryLoadSettings: Boolean;
var
  lError: string;
  lErrorCode: Integer;
  lOptions: TAppOptions;
  lProjectDproj: string;
  lProjectName: string;
begin
  if fOptions.fHasProjectContextPath then
  begin
    lOptions := fOptions;
    lOptions.fDprojPath := fOptions.fProjectContextPath;
    if not TryPrepareProjectParams(lOptions, fDiagnostics, fParams, fFixOptions, fFixIgnoreDefaults, fReportFilter,
      fPascalAnalyzer, fSettings, lProjectName, lProjectDproj, lError, lErrorCode) then
    begin
      WriteLn(ErrOutput, lError);
      fExitCode := lErrorCode;
      Exit(False);
    end;
    fProjectContextPath := lProjectDproj;
    Exit(True);
  end;

  if fOptions.fHasWorkspaceRoot then
    Result := LoadDakSettings(fDiagnostics, fUnitPath, nil, fOptions.fWorkspaceRoot, fSettings)
  else
    Result := LoadDakSettings(fDiagnostics, fUnitPath, nil, fSettings);
  if not Result then
  begin
    if fSettings.fError <> '' then
      WriteLn(ErrOutput, fSettings.fError)
    else
      WriteLn(ErrOutput, 'Failed to read dak.ini.');
    fExitCode := 6;
    Exit(False);
  end;
  fFixOptions := fSettings.fFixInsight;
  fFixIgnoreDefaults := fSettings.fFixInsightIgnore;
  fReportFilter := fSettings.fReportFilter;
  fPascalAnalyzer := fSettings.fPascalAnalyzer;
  ApplySettingsOverrides(fOptions, fFixOptions, fFixIgnoreDefaults, fReportFilter, fPascalAnalyzer);
  ApplyPascalAnalyzerIgnoreOverride(fOptions, fSettings.fPascalAnalyzerIgnore);
  fSettings.fFixInsight := fFixOptions;
  fSettings.fFixInsightIgnore := fFixIgnoreDefaults;
  fSettings.fReportFilter := fReportFilter;
  fSettings.fPascalAnalyzer := fPascalAnalyzer;
  fDiagnostics.AddWarning(rsAnalyzeUnitPalIniContext);
  Result := True;
end;

function TAnalyzeUnitRunner.TryPrepareUnit: Boolean;
var
  lUnitPath: string;
  lError: string;
begin
  if not TryNormalizeInputPath(fOptions.fUnitPath, lUnitPath, lError) then
  begin
    WriteLn(ErrOutput, lError);
    fExitCode := 3;
    Exit(False);
  end;

  fUnitPath := TPath.GetFullPath(lUnitPath);
  if not FileExists(fUnitPath) then
  begin
    WriteLn(ErrOutput, Format(SFileNotFound, [fUnitPath]));
    fExitCode := 3;
    Exit(False);
  end;
  fUnitName := TPath.GetFileNameWithoutExtension(fUnitPath);
  Result := True;
end;

procedure TAnalyzeUnitRunner.PrepareOutputTree;
begin
  fOutRoot := BuildUnitOutputRoot(fOptions.fAnalyzeOutPath, fUnitPath, fUnitName);
  if fOptions.fAnalyzeClean and DirectoryExists(fOutRoot) then
    TDirectory.Delete(fOutRoot, True);
  TDirectory.CreateDirectory(fOutRoot);

  fPaDir := TPath.Combine(fOutRoot, 'pascal-analyzer');
  TDirectory.CreateDirectory(fPaDir);

  fRunLog := TPath.Combine(fOutRoot, 'run.log');
  if fOptions.fAnalyzeClean or (not FileExists(fRunLog)) then
    WriteLogText(fRunLog, '');
end;

procedure TAnalyzeUnitRunner.RunPascalAnalyzer;
var
  lPalCounts: TPalFindingCounts;
  lRunExit: Cardinal;
  lRunError: string;
  lPaReportRoot: string;
  lPalPostError: string;
  lRan: Boolean;
  lStopwatch: TStopwatch;
  lStdErrLogPath: string;
  lStdOutLogPath: string;
  lUnitParams: TFixInsightParams;
begin
  fPal := Default(TPalSummary);
  fPalDurationMs := 0;
  if fOptions.fHasProjectContextPath then
    fPal.Context := 'Project: ' + fProjectContextPath
  else
    fPal.Context := rsAnalyzeUnitPalIniContext;
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
  lStdOutLogPath := TPath.Combine(fPaDir, 'pascal-analyzer.stdout.log');
  lStdErrLogPath := TPath.Combine(fPaDir, 'pascal-analyzer.stderr.log');

  lStopwatch := TStopwatch.StartNew;
  try
    if fOptions.fHasProjectContextPath then
    begin
      lUnitParams := fParams;
      lUnitParams.fProjectDpr := fUnitPath;
      lRan := TryRunPalLogged(lUnitParams, fPascalAnalyzer, lStdOutLogPath, lStdErrLogPath, fRunLog, lRunExit,
        lRunError);
    end else
      lRan := TryRunPalUnitLogged(fUnitPath, fPascalAnalyzer, lStdOutLogPath, lStdErrLogPath, fRunLog, lRunExit,
        lRunError);
  finally
    lStopwatch.Stop;
    fPalDurationMs := lStopwatch.ElapsedMilliseconds;
  end;

  if lRan then
  begin
    fPal.ExitCode := Integer(lRunExit);
    if fPal.ExitCode <> 0 then
      AddError(Format('Pascal Analyzer failed (exit=%d).', [fPal.ExitCode]), fPal.ExitCode)
    else
    begin
      try
        if fOptions.fHasProjectContextPath then
        begin
          lPaReportRoot := TPath.Combine(fPal.OutputRoot, fUnitName);
          if not FileExists(TPath.Combine(lPaReportRoot, 'Status.xml')) then
          begin
            lPalPostError := 'Status.xml not found in expected report folder: ' + lPaReportRoot;
            lPaReportRoot := '';
          end;
        end else if not TryFindPalReportRoot(fPal.OutputRoot, lPaReportRoot, lPalPostError) then
          lPaReportRoot := '';
        if lPaReportRoot <> '' then
        begin
          fPal.ReportRoot := lPaReportRoot;
          ReadStatusSummary(TPath.Combine(lPaReportRoot, 'Status.xml'), fPal.Version, fPal.Compiler);
          if not TryGeneratePalArtifactsWithCounts(lPaReportRoot, fPal.OutputRoot, lPalCounts, lPalPostError) then
            AddError('PAL findings generation failed: ' + lPalPostError, 6);
          fPal.Warnings := lPalCounts.Warnings;
          fPal.StrongWarnings := lPalCounts.StrongWarnings;
          fPal.Optimizations := lPalCounts.Optimizations;
        end else begin
          AddError('PAL report root not found: ' + lPalPostError, 6);
        end;
      except
        on E: Exception do
          AddError('PAL post-processing failed: ' + E.ClassName + ': ' + E.Message, 6);
      end;
    end;
  end else
  begin
    fPal.ExitCode := -1;
    AddError('Pascal Analyzer failed: ' + lRunError, 6);
  end;
  WriteToolLog(TPath.Combine(fPaDir, 'pascal-analyzer.log'), 'PALCMD', fPal.ExitCode, lRunError);
end;

procedure TAnalyzeUnitRunner.WriteSummary;
begin
  if not fOptions.fAnalyzeWriteSummary then
    Exit;

  fSummaryPath := TPath.Combine(fOutRoot, 'summary.md');
  fSummaryText := BuildUnitSummary(fUnitName, fUnitPath, fOutRoot, fPal, fErrors.ToArray);
  WriteLogText(fSummaryPath, fSummaryText);
  WriteUnitStatusSeed(fOutRoot, fUnitPath, fProjectContextPath, fParams, fSettings, fPascalAnalyzer,
    fPal, fPalDurationMs, fExitCode, fOptions.fAnalyzePal, fErrors.ToArray);
end;

function TAnalyzeUnitRunner.Execute: Integer;
begin
  try
    if not TryOpenLog then
      Exit(fExitCode);
    if not TryPrepareUnit then
      Exit(fExitCode);
    if not TryLoadSettings then
      Exit(fExitCode);
    PrepareOutputTree;
    RunPascalAnalyzer;
    WriteSummary;
  finally
    fDiagnostics.WriteToStderr;
  end;
  Result := fExitCode;
end;
function RunAnalyzeUnit(const aOptions: TAppOptions): Integer;
var
  lRunner: TAnalyzeUnitRunner;
begin
  lRunner := TAnalyzeUnitRunner.Create(aOptions);
  try
    Result := lRunner.Execute;
  finally
    lRunner.Free;
  end;
end;
end.
