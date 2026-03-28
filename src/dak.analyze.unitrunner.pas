unit Dak.Analyze.UnitRunner;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.SysUtils,
  Dak.Analyze.Common, Dak.Diagnostics, Dak.FixInsightSettings, Dak.Messages, Dak.Types, Dak.Utils;

function RunAnalyzeUnit(const aOptions: TAppOptions): Integer;

implementation

uses
  Dak.PascalAnalyzerRunner;

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
    fOutRoot: string;
    fPaDir: string;
    fRunLog: string;
    fUnitPath: string;
    fUnitName: string;
    fExitCode: Integer;
    fPal: TPalSummary;
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
begin
  if not LoadSettings(fDiagnostics, '', fFixOptions, fFixIgnoreDefaults, fReportFilter, fPascalAnalyzer) then
  begin
    WriteLn(ErrOutput, 'Failed to read dak.ini.');
    fExitCode := 6;
    Exit(False);
  end;
  ApplySettingsOverrides(fOptions, fFixOptions, fFixIgnoreDefaults, fReportFilter, fPascalAnalyzer);
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

  if TryRunPalUnitLogged(fUnitPath, fPascalAnalyzer, fRunLog, lRunExit, lRunError) then
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

procedure TAnalyzeUnitRunner.WriteSummary;
begin
  if not fOptions.fAnalyzeWriteSummary then
    Exit;

  fSummaryPath := TPath.Combine(fOutRoot, 'summary.md');
  fSummaryText := BuildUnitSummary(fUnitName, fUnitPath, fOutRoot, fPal, fErrors.ToArray);
  WriteLogText(fSummaryPath, fSummaryText);
end;

function TAnalyzeUnitRunner.Execute: Integer;
begin
  try
    if not TryOpenLog then
      Exit(fExitCode);
    if not TryLoadSettings then
      Exit(fExitCode);
    if not TryPrepareUnit then
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
