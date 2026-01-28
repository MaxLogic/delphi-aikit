program DelphiConfigResolver;

{$APPTYPE CONSOLE}

uses
  System.Generics.Collections, System.IOUtils, System.SysUtils,
  Winapi.Windows,
  Xml.omnixmldom, Xml.xmldom,
  Dcr.Cli in '..\src\Dcr.Cli.pas', Dcr.diagnostics in '..\src\Dcr.Diagnostics.pas',
  Dcr.FixInsight in '..\src\Dcr.FixInsight.pas',
  Dcr.FixInsightRunner in '..\src\Dcr.FixInsightRunner.pas',
  Dcr.FixInsightSettings in '..\src\Dcr.FixInsightSettings.pas',
  Dcr.Messages in '..\src\Dcr.Messages.pas', Dcr.MacroExpander in '..\src\Dcr.MacroExpander.pas',
  Dcr.MsBuild in '..\src\Dcr.MsBuild.pas', Dcr.output in '..\src\Dcr.Output.pas',
  Dcr.Project in '..\src\Dcr.Project.pas', Dcr.Registry in '..\src\Dcr.Registry.pas',
  Dcr.PascalAnalyzerRunner in '..\src\Dcr.PascalAnalyzerRunner.pas',
  Dcr.ReportPostProcess in '..\src\Dcr.ReportPostProcess.pas',
  Dcr.RsVars in '..\src\Dcr.RsVars.pas',
  Dcr.Types in '..\src\Dcr.Types.pas';

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
  lBuffer: string;
begin
  if aValue = '' then
    Exit('');
  lRequired := ExpandEnvironmentStrings(PChar(aValue), nil, 0);
  if lRequired = 0 then
    Exit(aValue);
  SetLength(lBuffer, lRequired);
  if ExpandEnvironmentStrings(PChar(aValue), PChar(lBuffer), Length(lBuffer)) = 0 then
    Exit(aValue);
  SetLength(lBuffer, StrLen(PChar(lBuffer)));
  Result := lBuffer;
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

function TryResolveDprojPath(const aInputPath: string; out aDprojPath: string; out aError: string): Boolean;
var
  lExt: string;
  lCandidate: string;
begin
  aError := '';
  aDprojPath := TPath.GetFullPath(aInputPath);
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

  Result := FileExists(aDprojPath);
  if not Result then
    aError := Format(SFileNotFound, [aDprojPath]);
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
  lOutPath: string;
  lOk: boolean;
  lRunExit: Cardinal;
  lRunError: string;
  lLogPath: string;
  lPaOutputRoot: string;
  lPaReportRoot: string;
  lSkipOutput: Boolean;
  lInputPath: string;
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
        WriteUsage;
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
          WriteUsage;
          lExitCode := 2;
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
        lDiagnostics.AddInfo(Format(SInfoStep, ['Read settings.ini']));
        lOk := LoadSettings(lDiagnostics, lFixOptions, lFixIgnoreDefaults, lReportFilter, lPascalAnalyzer);
        if not lOk then
        begin
          lExitCode := 6;
        end else
          ApplySettingsOverrides(lOptions, lFixOptions, lFixIgnoreDefaults, lReportFilter, lPascalAnalyzer);
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

