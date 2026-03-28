unit Dak.Resolve;

interface

uses
  Dak.Types;

function RunResolveCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.SysUtils,
  Dak.Diagnostics, Dak.ExitCodes, Dak.FixInsight, Dak.FixInsightRunner, Dak.FixInsightSettings, Dak.Messages,
  Dak.Output, Dak.PascalAnalyzerRunner, Dak.Project, Dak.Registry, Dak.ReportPostProcess, Dak.RsVars, Dak.Utils;

type
  TResolveCommandRunner = class
  private
    fOptions: TAppOptions;
    fParams: TFixInsightParams;
    fEnvVars: TDictionary<string, string>;
    fDiagnostics: TDiagnostics;
    fLibraryPath: string;
    fLibrarySource: TPropertySource;
    fFixOptions: TFixInsightExtraOptions;
    fFixIgnoreDefaults: TFixInsightIgnoreDefaults;
    fReportFilter: TReportFilterDefaults;
    fPascalAnalyzer: TPascalAnalyzerDefaults;
    fExitCode: Integer;
    fInputPath: string;
    function TryOpenLog: Boolean;
    function TryResolveProjectInput: Boolean;
    function TryLoadSettings: Boolean;
    function TryLoadRsVars: Boolean;
    function TryReadIdeConfig: Boolean;
    function TryBuildParams: Boolean;
    procedure ApplyFixInsightSettings;
    procedure ResolveFixInsightExecutable;
    procedure AddParameterSourceNotes;
    function TryWriteOutput: Boolean;
    function TryValidateFixInsightRequest: Boolean;
    function TryRunFixInsight: Boolean;
    function TryRunPascalAnalyzer: Boolean;
  public
    constructor Create(const aOptions: TAppOptions);
    destructor Destroy; override;
    function Execute: Integer;
  end;

function SourceToText(aSource: TPropertySource): string;
begin
  case aSource of
    TPropertySource.psDproj: Result := SSourceDproj;
    TPropertySource.psOptset: Result := SSourceOptset;
    TPropertySource.psRegistry: Result := SSourceRegistry;
    TPropertySource.psEnvOptions: Result := SSourceEnvOptions;
  else
    Result := SSourceUnknown;
  end;
end;

constructor TResolveCommandRunner.Create(const aOptions: TAppOptions);
begin
  inherited Create;
  fOptions := aOptions;
  fDiagnostics := TDiagnostics.Create;
  fEnvVars := nil;
  fExitCode := cExitSuccess;
end;

destructor TResolveCommandRunner.Destroy;
begin
  fDiagnostics.Free;
  fEnvVars.Free;
  inherited Destroy;
end;

function TResolveCommandRunner.TryOpenLog: Boolean;
var
  lError: string;
  lLogPath: string;
begin
  Result := True;
  if not fOptions.fHasLogFile then
    Exit(True);

  lLogPath := TPath.GetFullPath(fOptions.fLogFile);
  Result := fDiagnostics.TryOpenLogFile(lLogPath, lError);
  if not Result then
  begin
    WriteLn(ErrOutput, lError);
    fExitCode := cExitToolFailure;
    Exit(False);
  end;

  if fOptions.fHasLogTee then
    fDiagnostics.LogToStderr := fOptions.fLogTee
  else
    fDiagnostics.LogToStderr := False;
end;

function TResolveCommandRunner.TryResolveProjectInput: Boolean;
var
  lError: string;
begin
  fDiagnostics.AddInfo(Format(SInfoStep, ['Validate inputs']));
  fInputPath := fOptions.fDprojPath;
  Result := TryResolveDprojPath(fInputPath, fOptions.fDprojPath, lError);
  if not Result then
  begin
    WriteLn(ErrOutput, lError);
    fExitCode := cExitInvalidProjectInput;
    Exit(False);
  end;

  if not SameText(TPath.GetExtension(fInputPath), '.dproj') then
    fDiagnostics.AddNote(Format(SInfoAssociatedDproj, [fOptions.fDprojPath]));
end;

function TResolveCommandRunner.TryLoadSettings: Boolean;
begin
  fDiagnostics.AddInfo(Format(SInfoStep, ['Read dak.ini']));
  Result := LoadSettings(fDiagnostics, fOptions.fDprojPath, fFixOptions, fFixIgnoreDefaults, fReportFilter,
    fPascalAnalyzer);
  if not Result then
  begin
    fExitCode := cExitToolFailure;
    Exit(False);
  end;

  ApplySettingsOverrides(fOptions, fFixOptions, fFixIgnoreDefaults, fReportFilter, fPascalAnalyzer);
end;

function TResolveCommandRunner.TryLoadRsVars: Boolean;
var
  lError: string;
begin
  if fOptions.fVerbose then
    fDiagnostics.AddInfo(Format(SInfoOptions,
      [fOptions.fDprojPath, fOptions.fPlatform, fOptions.fConfig, fOptions.fDelphiVersion]));
  fDiagnostics.AddInfo(Format(SInfoStep, ['Load rsvars.bat']));

  Result := Dak.RsVars.TryLoadRsVars(fOptions.fDelphiVersion, fOptions.fRsVarsPath, fDiagnostics, lError);
  if not Result then
  begin
    WriteLn(ErrOutput, lError);
    fExitCode := cExitEnvironmentError;
  end;
end;

function TResolveCommandRunner.TryReadIdeConfig: Boolean;
var
  lError: string;
begin
  fDiagnostics.AddInfo(Format(SInfoStep, ['Read IDE registry and library path']));
  Result := Dak.Registry.TryReadIdeConfig(fOptions.fDelphiVersion, fOptions.fPlatform, fOptions.fEnvOptionsPath, fEnvVars,
    fLibraryPath, fLibrarySource, fDiagnostics, lError);
  if not Result then
  begin
    WriteLn(ErrOutput, lError);
    fExitCode := cExitEnvironmentError;
  end;
end;

function TResolveCommandRunner.TryBuildParams: Boolean;
var
  lError: string;
  lErrorCode: Integer;
begin
  fDiagnostics.AddInfo(Format(SInfoStep, ['Resolve project and option set']));
  Result := Dak.Project.TryBuildParams(fOptions, fEnvVars, fLibraryPath, fLibrarySource, fDiagnostics, fParams, lError,
    lErrorCode);
  if not Result then
  begin
    WriteLn(ErrOutput, lError);
    fExitCode := lErrorCode;
  end;
end;

procedure TResolveCommandRunner.ApplyFixInsightSettings;
begin
  fParams.fFixOutput := fFixOptions.fOutput;
  fParams.fFixIgnore := fFixOptions.fIgnore;
  fParams.fFixSettings := fFixOptions.fSettings;
  fParams.fFixSilent := fFixOptions.fSilent;
  fParams.fFixXml := fFixOptions.fXml;
  fParams.fFixCsv := fFixOptions.fCsv;
end;

procedure TResolveCommandRunner.ResolveFixInsightExecutable;
begin
  fDiagnostics.AddInfo(Format(SInfoStep, ['Resolve FixInsightCL.exe']));

  if fFixOptions.fExePath <> '' then
  begin
    fParams.fFixInsightExe := ResolveExePathFromConfiguredValue(fFixOptions.fExePath, 'FixInsightCL.exe');
    if (fParams.fFixInsightExe <> '') and FileExists(fParams.fFixInsightExe) then
      fDiagnostics.AddInfo(Format(SInfoFixInsightPath, [fParams.fFixInsightExe]))
    else
    begin
      fParams.fFixInsightExe := '';
      fDiagnostics.AddWarning(Format(SFixInsightPathInvalid, [fFixOptions.fExePath]));
    end;
  end;

  if (fParams.fFixInsightExe = '') and (not TryResolveFixInsightExe(fDiagnostics, fParams.fFixInsightExe)) then
    fDiagnostics.AddWarning(SFixInsightNotFound);
end;

procedure TResolveCommandRunner.AddParameterSourceNotes;
begin
  fDiagnostics.AddNote(Format(SSourceLibraryPath, [SourceToText(fParams.fLibrarySource)]));
  fDiagnostics.AddNote(Format(SSourceDefines, [SourceToText(fParams.fDefineSource)]));
  fDiagnostics.AddNote(Format(SSourceSearchPath, [SourceToText(fParams.fSearchPathSource)]));
  fDiagnostics.AddNote(Format(SSourceUnitScopes, [SourceToText(fParams.fUnitScopesSource)]));
  if Length(fParams.fUnitAliases) > 0 then
    fDiagnostics.AddNote(Format(SSourceUnitAliases, [SourceToText(fParams.fUnitAliasesSource)]));
end;

function TResolveCommandRunner.TryWriteOutput: Boolean;
var
  lError: string;
  lOutPath: string;
  lSkipOutput: Boolean;
begin
  AddParameterSourceNotes;

  lOutPath := '';
  if fOptions.fHasOutPath then
    lOutPath := fOptions.fOutPath;

  lSkipOutput := fOptions.fRunFixInsight and (not fOptions.fHasOutPath) and (not fOptions.fHasOutKind);
  if lSkipOutput then
    Exit(True);

  Result := WriteOutput(fParams, fOptions.fOutKind, lOutPath, lError);
  if not Result then
  begin
    WriteLn(ErrOutput, lError);
    fExitCode := cExitToolFailure;
  end;
end;

function TResolveCommandRunner.TryValidateFixInsightRequest: Boolean;
begin
  Result := True;
  if not fOptions.fRunFixInsight then
    Exit(True);

  fDiagnostics.AddInfo(Format(SInfoStep, ['Run FixInsightCL']));
  if fParams.fFixInsightExe <> '' then
    Exit(True);

  WriteLn(ErrOutput, SFixInsightExeMissing);
  fExitCode := cExitToolMissing;
  Result := False;
end;

function TResolveCommandRunner.TryRunFixInsight: Boolean;
var
  lFilterError: string;
  lFormat: TReportFormat;
  lReportPath: string;
  lRunError: string;
  lRunExit: Cardinal;
begin
  Result := True;
  if not fOptions.fRunFixInsight then
    Exit(True);

  if fParams.fFixOutput <> '' then
  begin
    fParams.fFixOutput := TPath.GetFullPath(fParams.fFixOutput);
    TDirectory.CreateDirectory(ExtractFilePath(fParams.fFixOutput));
  end;
  if fParams.fFixSettings <> '' then
    fParams.fFixSettings := TPath.GetFullPath(fParams.fFixSettings);

  Result := Dak.FixInsightRunner.TryRunFixInsight(fParams, lRunExit, lRunError);
  if not Result then
  begin
    WriteLn(ErrOutput, lRunError);
    fExitCode := cExitToolFailure;
    Exit(False);
  end;

  if lRunExit <> 0 then
  begin
    WriteLn(ErrOutput, Format(SFixInsightRunExit, [lRunExit]));
    fExitCode := Integer(lRunExit);
    Exit(False);
  end;

  if not HasAnyReportFilters(fReportFilter.fExcludePathMasks, fFixIgnoreDefaults.fWarnings) then
    Exit(True);

  if fParams.fFixOutput = '' then
  begin
    fDiagnostics.AddWarning('Report filtering requested but FixInsightCL --output is not set; skipping.');
    Exit(True);
  end;

  lFormat := TReportFormat.rfText;
  if fParams.fFixCsv then
    lFormat := TReportFormat.rfCsv
  else if fParams.fFixXml then
    lFormat := TReportFormat.rfXml;

  lReportPath := fParams.fFixOutput;
  Result := TryPostProcessFixInsightReport(lReportPath, lFormat, fReportFilter.fExcludePathMasks,
    fFixIgnoreDefaults.fWarnings, lFilterError);
  if not Result then
  begin
    WriteLn(ErrOutput, 'FixInsight report post-processing failed: ' + lFilterError);
    fExitCode := cExitToolFailure;
  end;
end;

function TResolveCommandRunner.TryRunPascalAnalyzer: Boolean;
var
  lPaExe: string;
  lPaOutputRoot: string;
  lPaReportRoot: string;
  lRunError: string;
  lRunExit: Cardinal;
begin
  Result := True;
  if not fOptions.fRunPascalAnalyzer then
    Exit(True);

  fDiagnostics.AddInfo(Format(SInfoStep, ['Run Pascal Analyzer (PALCMD)']));

  Result := TryResolvePalCmdExe(fPascalAnalyzer.fPath, lPaExe, lRunError);
  if not Result then
  begin
    WriteLn(ErrOutput, lRunError);
    fExitCode := cExitToolMissing;
    Exit(False);
  end;

  fPascalAnalyzer.fPath := lPaExe;
  Result := Dak.PascalAnalyzerRunner.TryRunPascalAnalyzer(fParams, fPascalAnalyzer, lRunExit, lRunError);
  if not Result then
  begin
    WriteLn(ErrOutput, lRunError);
    fExitCode := cExitToolFailure;
    Exit(False);
  end;

  if lRunExit <> 0 then
  begin
    WriteLn(ErrOutput, Format('PALCMD exited with code %d.', [lRunExit]));
    fExitCode := Integer(lRunExit);
    Exit(False);
  end;

  lPaOutputRoot := '';
  if fPascalAnalyzer.fOutput <> '' then
    lPaOutputRoot := TPath.GetFullPath(fPascalAnalyzer.fOutput);

  if lPaOutputRoot = '' then
    fDiagnostics.AddWarning('PAL output root not set; skipping pal-findings generation. Use --pa-output.')
  else if not TryFindPalReportRoot(lPaOutputRoot, lPaReportRoot, lRunError) then
    fDiagnostics.AddWarning('PAL report root not found; skipping pal-findings generation. ' + lRunError)
  else if not TryGeneratePalArtifacts(lPaReportRoot, lPaOutputRoot, lRunError) then
    fDiagnostics.AddWarning('PAL findings generation failed: ' + lRunError);
end;

function TResolveCommandRunner.Execute: Integer;
begin
  try
    fDiagnostics.Verbose := fOptions.fVerbose;

    if not TryOpenLog then
      Exit(fExitCode);
    if not TryResolveProjectInput then
      Exit(fExitCode);
    if not TryLoadSettings then
      Exit(fExitCode);
    if not TryLoadRsVars then
      Exit(fExitCode);
    if not TryReadIdeConfig then
      Exit(fExitCode);
    if not TryBuildParams then
      Exit(fExitCode);

    ApplyFixInsightSettings;
    ResolveFixInsightExecutable;

    if not TryWriteOutput then
      Exit(fExitCode);
    if not TryValidateFixInsightRequest then
      Exit(fExitCode);
    if not TryRunFixInsight then
      Exit(fExitCode);
    if not TryRunPascalAnalyzer then
      Exit(fExitCode);

    Result := fExitCode;
  finally
    fDiagnostics.WriteToStderr;
  end;
end;

function RunResolveCommand(const aOptions: TAppOptions): Integer;
var
  lRunner: TResolveCommandRunner;
begin
  lRunner := TResolveCommandRunner.Create(aOptions);
  try
    Result := lRunner.Execute;
  finally
    lRunner.Free;
  end;
end;

end.
