program DelphiAIKit;

{$APPTYPE CONSOLE}

uses
  madExcept,
  madLinkDisAsm,
  madListHardware,
  madListProcesses,
  madListModules,
  System.Generics.Collections, System.IOUtils, System.SysUtils,
  Winapi.Windows,
  Xml.omnixmldom, Xml.xmldom,
  DfmCheck_AppConsts in '..\lib\DFMCheck\Source\DfmCheck_AppConsts.pas',
  DfmCheck_DfmCheck in '..\lib\DFMCheck\Source\DfmCheck_DfmCheck.pas',
  DfmCheck_Options in '..\lib\DFMCheck\Source\DfmCheck_Options.pas',
  DfmCheck_PascalParser in '..\lib\DFMCheck\Source\DfmCheck_PascalParser.pas',
  DfmCheck_Utils in '..\lib\DFMCheck\Source\DfmCheck_Utils.pas',
  ProjectFileReader in '..\lib\DFMCheck\Source\Console\ProjectFileReader.pas',
  ToolsAPIRepl in '..\lib\DFMCheck\Source\Console\ToolsAPIRepl.pas',
  Dak.Analyze in '..\src\dak.analyze.pas', Dak.Build in '..\src\dak.build.pas',
  Dak.Cli in '..\src\dak.cli.pas',
  Dak.DfmCheck in '..\src\dak.dfmcheck.pas',
  Dak.DfmInspect in '..\src\dak.dfminspect.pas',
  Dak.Diagnostics in '..\src\dak.diagnostics.pas',
  Dak.FixInsight in '..\src\dak.fixinsight.pas',
  Dak.FixInsightRunner in '..\src\dak.fixinsightrunner.pas',
  Dak.GlobalVars in '..\src\dak.globalvars.pas',
  Dak.FixInsightSettings in '..\src\dak.fixinsightsettings.pas',
  Dak.Messages in '..\src\dak.messages.pas', Dak.MacroExpander in '..\src\dak.macroexpander.pas',
  Dak.MsBuild in '..\src\dak.msbuild.pas', Dak.Output in '..\src\dak.output.pas',
  Dak.Project in '..\src\dak.project.pas', Dak.Registry in '..\src\dak.registry.pas',
  Dak.PascalAnalyzerRunner in '..\src\dak.pascalanalyzerrunner.pas',
  Dak.ReportPostProcess in '..\src\dak.reportpostprocess.pas',
  Dak.RsVars in '..\src\dak.rsvars.pas',
  Dak.Types in '..\src\dak.types.pas';

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

function ExpandEnvVars(const aValue: string): string;
var
  lRequired: Cardinal;
  lBuffer: TArray<Char>;
begin
  if aValue = '' then
    Exit('');
  lRequired := ExpandEnvironmentStrings(PChar(aValue), nil, 0);
  if lRequired = 0 then
    Exit(aValue);
  SetLength(lBuffer, lRequired);
  if ExpandEnvironmentStrings(PChar(aValue), PChar(lBuffer), Length(lBuffer)) = 0 then
    Exit(aValue);
  Result := PChar(lBuffer);
end;

function ResolveFixInsightPath(const aValue: string): string;
var
  lValue: string;
begin
  lValue := Trim(ExpandEnvVars(aValue));
  if lValue = '' then
    Exit('');
  if not TPath.IsPathRooted(lValue) then
    lValue := TPath.Combine(ExtractFilePath(ParamStr(0)), lValue);
  if SameText(TPath.GetExtension(lValue), '.exe') then
    Result := lValue
  else
    Result := TPath.Combine(lValue, 'FixInsightCL.exe');
end;

function TryNormalizeInputPath(const aPath: string; out aNormalizedPath: string; out aError: string): Boolean;
var
  lDrive: Char;
  lPath: string;
begin
  aError := '';
  lPath := Trim(aPath);
  aNormalizedPath := lPath;
  if lPath = '' then
    Exit(True);

  if lPath[1] <> '/' then
    Exit(True);

  if SameText(Copy(lPath, 1, 5), '/mnt/') then
  begin
    if (Length(lPath) < 6) or (not CharInSet(lPath[6], ['A'..'Z', 'a'..'z'])) or
      ((Length(lPath) > 6) and (lPath[7] <> '/')) then
    begin
      aError := Format(SUnsupportedLinuxPath, [lPath]);
      Exit(False);
    end;

    lDrive := UpCase(lPath[6]);
    if Length(lPath) > 7 then
      lPath := Copy(lPath, 8, MaxInt)
    else
      lPath := '';
    lPath := lPath.Replace('/', '\', [rfReplaceAll]);
    if lPath = '' then
      aNormalizedPath := lDrive + ':\'
    else
      aNormalizedPath := lDrive + ':\' + lPath;
    Exit(True);
  end;

  aError := Format(SUnsupportedLinuxPath, [lPath]);
  Result := False;
end;

function TryResolveDprojPath(const aInputPath: string; out aDprojPath: string; out aError: string): Boolean;
var
  lInputPath: string;
  lExt: string;
  lCandidate: string;
begin
  aError := '';
  if not TryNormalizeInputPath(aInputPath, lInputPath, aError) then
    Exit(False);
  aDprojPath := TPath.GetFullPath(lInputPath);
  lExt := TPath.GetExtension(aDprojPath);
  if SameText(lExt, '.dproj') then
  begin
    Result := FileExists(aDprojPath);
    if not Result then
      aError := Format(SFileNotFound, [aDprojPath]);
    Exit;
  end;

  if SameText(lExt, '.dpr') or SameText(lExt, '.dpk') then
  begin
    lCandidate := TPath.ChangeExtension(aDprojPath, '.dproj');
    if FileExists(lCandidate) then
    begin
      aDprojPath := lCandidate;
      Exit(True);
    end;
    aError := Format(SAssociatedDprojMissing, [aDprojPath]);
    Exit(False);
  end;

  aError := Format(SUnsupportedProjectInput, [aDprojPath]);
  Result := False;
end;

var
  lOptions: TAppOptions;
  lParams: TFixInsightParams;
  lEnvVars: TDictionary<string, string>;
  lDiagnostics: TDiagnostics;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lFixOptions: TFixInsightExtraOptions;
  lFixIgnoreDefaults: TFixInsightIgnoreDefaults;
  lReportFilter: TReportFilterDefaults;
  lPascalAnalyzer: TPascalAnalyzerDefaults;
  lError: string;
  lErrorCode: integer;
  lExitCode: integer;
  lBuildExitCode: Integer;
  lDfmCheckExitCode: Integer;
  lOutPath: string;
  lOk: boolean;
  lRunExit: Cardinal;
  lRunError: string;
  lLogPath: string;
  lPaOutputRoot: string;
  lPaReportRoot: string;
  lSkipOutput: Boolean;
  lInputPath: string;
  lHelpCommand: TCommandKind;
  lHasHelpCommand: Boolean;
begin
  DefaultDOMVendor := sOmniXmlVendor;
  lExitCode := 0;
  lEnvVars := nil;
  lDiagnostics := TDiagnostics.Create;
  lOk := True;
  try
    try
      if IsHelpRequested then
      begin
        if not TryGetCommand(lHelpCommand, lHasHelpCommand, lError) then
        begin
          writeln(ErrOutput, SInvalidArgs);
          if lError <> '' then
            writeln(ErrOutput, lError);
          WriteUsage(TCommandKind.ckResolve, True);
          lExitCode := 2;
        end else
          WriteUsage(lHelpCommand, not lHasHelpCommand);
        lOk := False;
      end;

      if lOk then
      begin
        lOk := TryParseOptions(lOptions, lError);
        if not lOk then
        begin
          writeln(ErrOutput, SInvalidArgs);
          if lError <> '' then
            writeln(ErrOutput, lError);
          WriteUsage(lOptions.fCommand, False);
          lExitCode := 2;
        end;
      end;

      if lOk then
      begin
        if lOptions.fCommand = TCommandKind.ckBuild then
        begin
          if not TryRunBuild(lOptions, lBuildExitCode, lError) then
          begin
            writeln(ErrOutput, lError);
            lExitCode := 6;
          end else begin
            lExitCode := lBuildExitCode;
            if (lExitCode = 0) and lOptions.fBuildRunDfmCheck then
            begin
              WriteLn('[build] Running dfm-check validation...');
              lDfmCheckExitCode := RunDfmCheckCommand(lOptions);
              lExitCode := lDfmCheckExitCode;
            end;
          end;
          lOk := False;
        end else if lOptions.fCommand = TCommandKind.ckDfmCheck then
        begin
          lExitCode := RunDfmCheckCommand(lOptions);
          lOk := False;
        end else if lOptions.fCommand = TCommandKind.ckDfmInspect then
        begin
          lExitCode := RunDfmInspectCommand(lOptions);
          lOk := False;
        end else if lOptions.fCommand = TCommandKind.ckGlobalVars then
        begin
          lExitCode := RunGlobalVarsCommand(lOptions);
          lOk := False;
        end else if lOptions.fCommand <> TCommandKind.ckResolve then
        begin
          lExitCode := RunAnalyzeCommand(lOptions);
          lOk := False;
        end;
      end;

      if lOk then
        lDiagnostics.Verbose := lOptions.fVerbose;

      if lOk then
      begin
        if lOptions.fHasLogFile then
        begin
          lLogPath := TPath.GetFullPath(lOptions.fLogFile);
          lOk := lDiagnostics.TryOpenLogFile(lLogPath, lError);
          if not lOk then
          begin
            writeln(ErrOutput, lError);
            lExitCode := 6;
          end else
          begin
            if lOptions.fHasLogTee then
              lDiagnostics.LogToStderr := lOptions.fLogTee
            else
              lDiagnostics.LogToStderr := False;
          end;
        end;
      end;

      if lOk then
      begin
        lDiagnostics.AddInfo(Format(SInfoStep, ['Validate inputs']));
        lInputPath := lOptions.fDprojPath;
        lOk := TryResolveDprojPath(lInputPath, lOptions.fDprojPath, lError);
        if not lOk then
        begin
          writeln(ErrOutput, lError);
          lExitCode := 3;
        end else if not SameText(TPath.GetExtension(lInputPath), '.dproj') then
          lDiagnostics.AddNote(Format(SInfoAssociatedDproj, [lOptions.fDprojPath]));
      end;

      if lOk then
      begin
        lDiagnostics.AddInfo(Format(SInfoStep, ['Read dak.ini']));
        lOk := LoadSettings(lDiagnostics, lOptions.fDprojPath, lFixOptions, lFixIgnoreDefaults, lReportFilter,
          lPascalAnalyzer);
        if not lOk then
        begin
          lExitCode := 6;
        end else
          ApplySettingsOverrides(lOptions, lFixOptions, lFixIgnoreDefaults, lReportFilter, lPascalAnalyzer);
      end;

      if lOk then
      begin
        if lOptions.fVerbose then
          lDiagnostics.AddInfo(Format(SInfoOptions, [lOptions.fDprojPath, lOptions.fPlatform, lOptions.fConfig,
              lOptions.fDelphiVersion]));
        lDiagnostics.AddInfo(Format(SInfoStep, ['Load rsvars.bat']));
        if not TryLoadRsVars(lOptions.fDelphiVersion, lOptions.fRsVarsPath, lDiagnostics, lError) then
        begin
          writeln(ErrOutput, lError);
          lExitCode := 4;
          lOk := False;
        end;
      end;

      if lOk then
      begin
        lDiagnostics.AddInfo(Format(SInfoStep, ['Read IDE registry and library path']));
        lOk := TryReadIdeConfig(lOptions.fDelphiVersion, lOptions.fPlatform, lOptions.fEnvOptionsPath, lEnvVars,
          lLibraryPath, lLibrarySource, lDiagnostics, lError);
        if not lOk then
        begin
          writeln(ErrOutput, lError);
          lExitCode := 4;
        end;
      end;

      if lOk then
      begin
        lDiagnostics.AddInfo(Format(SInfoStep, ['Resolve project and option set']));
        lOk := TryBuildParams(lOptions, lEnvVars, lLibraryPath, lLibrarySource, lDiagnostics, lParams, lError,
          lErrorCode);
        if not lOk then
        begin
          writeln(ErrOutput, lError);
          lExitCode := lErrorCode;
        end;
      end;

      if lOk then
      begin
        lParams.fFixOutput := lFixOptions.fOutput;
        lParams.fFixIgnore := lFixOptions.fIgnore;
        lParams.fFixSettings := lFixOptions.fSettings;
        lParams.fFixSilent := lFixOptions.fSilent;
        lParams.fFixXml := lFixOptions.fXml;
        lParams.fFixCsv := lFixOptions.fCsv;
      end;

      if lOk then
      begin
        lDiagnostics.AddInfo(Format(SInfoStep, ['Resolve FixInsightCL.exe']));
        if lFixOptions.fExePath <> '' then
        begin
          lParams.fFixInsightExe := ResolveFixInsightPath(lFixOptions.fExePath);
          if (lParams.fFixInsightExe <> '') and FileExists(lParams.fFixInsightExe) then
          begin
            lDiagnostics.AddInfo(Format(SInfoFixInsightPath, [lParams.fFixInsightExe]));
          end else
          begin
            lParams.fFixInsightExe := '';
            lDiagnostics.AddWarning(Format(SFixInsightPathInvalid, [lFixOptions.fExePath]));
          end;
        end;
        if (lParams.fFixInsightExe = '') and (not TryResolveFixInsightExe(lDiagnostics, lParams.fFixInsightExe)) then
          lDiagnostics.AddWarning(SFixInsightNotFound);
      end;

      if lOk then
      begin
        lDiagnostics.AddNote(Format(SSourceLibraryPath, [SourceToText(lParams.fLibrarySource)]));
        lDiagnostics.AddNote(Format(SSourceDefines, [SourceToText(lParams.fDefineSource)]));
        lDiagnostics.AddNote(Format(SSourceSearchPath, [SourceToText(lParams.fSearchPathSource)]));
        lDiagnostics.AddNote(Format(SSourceUnitScopes, [SourceToText(lParams.fUnitScopesSource)]));
        if length(lParams.fUnitAliases) > 0 then
          lDiagnostics.AddNote(Format(SSourceUnitAliases, [SourceToText(lParams.fUnitAliasesSource)]));

        lOutPath := '';
        if lOptions.fHasOutPath then
          lOutPath := lOptions.fOutPath;

        lSkipOutput := lOptions.fRunFixInsight and (not lOptions.fHasOutPath) and (not lOptions.fHasOutKind);
        if not lSkipOutput then
        begin
          lOk := WriteOutput(lParams, lOptions.fOutKind, lOutPath, lError);
          if not lOk then
          begin
            writeln(ErrOutput, lError);
            lExitCode := 6;
          end;
        end;
      end;

      if lOk and lOptions.fRunFixInsight then
      begin
        lDiagnostics.AddInfo(Format(SInfoStep, ['Run FixInsightCL']));
        if (lParams.fFixInsightExe = '') then
        begin
          writeln(ErrOutput, SFixInsightExeMissing);
          lExitCode := 7;
          lOk := False;
        end;
      end;

      if lOk and lOptions.fRunFixInsight then
      begin
        if lParams.fFixOutput <> '' then
        begin
          // FixInsightCL resolves relative --output paths against the project folder.
          // We need a stable, deterministic output location because we post-process the report file.
          lParams.fFixOutput := TPath.GetFullPath(lParams.fFixOutput);
          TDirectory.CreateDirectory(ExtractFilePath(lParams.fFixOutput));
        end;
        if lParams.fFixSettings <> '' then
          lParams.fFixSettings := TPath.GetFullPath(lParams.fFixSettings);

        lOk := TryRunFixInsight(lParams, lRunExit, lRunError);
        if not lOk then
        begin
          writeln(ErrOutput, lRunError);
          lExitCode := 6;
        end else if lRunExit <> 0 then
        begin
          writeln(ErrOutput, Format(SFixInsightRunExit, [lRunExit]));
          lExitCode := Integer(lRunExit);
          lOk := False;
        end else if HasAnyReportFilters(lReportFilter.fExcludePathMasks, lFixIgnoreDefaults.fWarnings) then
        begin
          if lParams.fFixOutput = '' then
          begin
            // We only post-process file output; stdout-only output is left untouched.
            lDiagnostics.AddWarning('Report filtering requested but FixInsightCL --output is not set; skipping.');
          end else
          begin
            var lFormat: TReportFormat := TReportFormat.rfText;
            if lParams.fFixCsv then
              lFormat := TReportFormat.rfCsv
            else if lParams.fFixXml then
              lFormat := TReportFormat.rfXml;

            var lReportPath := lParams.fFixOutput;
            var lFilterError: string;
            if not TryPostProcessFixInsightReport(lReportPath, lFormat, lReportFilter.fExcludePathMasks,
              lFixIgnoreDefaults.fWarnings, lFilterError) then
            begin
              writeln(ErrOutput, 'FixInsight report post-processing failed: ' + lFilterError);
              lExitCode := 6;
              lOk := False;
            end;
          end;
        end;
      end;

      if lOk and lOptions.fRunPascalAnalyzer then
      begin
        lDiagnostics.AddInfo(Format(SInfoStep, ['Run Pascal Analyzer (PALCMD)']));

        var lPalExe: string;
        if not TryResolvePalCmdExe(lPascalAnalyzer.fPath, lPalExe, lRunError) then
        begin
          writeln(ErrOutput, lRunError);
          lExitCode := 7;
          lOk := False;
        end else
        begin
          lPascalAnalyzer.fPath := lPalExe;
          lOk := TryRunPascalAnalyzer(lParams, lPascalAnalyzer, lRunExit, lRunError);
          if not lOk then
          begin
            writeln(ErrOutput, lRunError);
            lExitCode := 6;
          end else if lRunExit <> 0 then
          begin
            writeln(ErrOutput, Format('PALCMD exited with code %d.', [lRunExit]));
            lExitCode := Integer(lRunExit);
            lOk := False;
          end else
          begin
            lPaOutputRoot := '';
            if lPascalAnalyzer.fOutput <> '' then
              lPaOutputRoot := TPath.GetFullPath(lPascalAnalyzer.fOutput);

            if lPaOutputRoot = '' then
              lDiagnostics.AddWarning('PAL output root not set; skipping pal-findings generation. Use --pa-output.')
            else if not TryFindPalReportRoot(lPaOutputRoot, lPaReportRoot, lRunError) then
              lDiagnostics.AddWarning('PAL report root not found; skipping pal-findings generation. ' + lRunError)
            else if not TryGeneratePalArtifacts(lPaReportRoot, lPaOutputRoot, lRunError) then
              lDiagnostics.AddWarning('PAL findings generation failed: ' + lRunError);
          end;
        end;
      end;
    except
      on e: Exception do
      begin
        writeln(ErrOutput, Format(SUnhandledException, [e.classname, e.Message]));
        lExitCode := 1;
      end;
    end;
  finally
    lDiagnostics.WriteToStderr;
    lDiagnostics.Free;
    lEnvVars.Free;
  end;

  Halt(lExitCode);
end.

