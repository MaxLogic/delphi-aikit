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
  Dak.Analyze in '..\src\dak.analyze.pas', Dak.Cli in '..\src\dak.cli.pas',
  Dak.Diagnostics in '..\src\dak.diagnostics.pas',
  Dak.FixInsight in '..\src\dak.fixinsight.pas',
  Dak.FixInsightRunner in '..\src\dak.fixinsightrunner.pas',
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

function QuoteCmdArg(const aValue: string): string;
begin
  if (aValue = '') or (Pos(' ', aValue) > 0) or (Pos('"', aValue) > 0) then
    Result := '"' + StringReplace(aValue, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := aValue;
end;

function NormalizeDelphiVerForBuild(const aValue: string): string;
var
  lDot: Integer;
begin
  Result := Trim(aValue);
  lDot := Pos('.', Result);
  if lDot > 0 then
    Result := Copy(Result, 1, lDot - 1);
end;

function TryRunBuildDelphi(const aOptions: TAppOptions; out aExitCode: Integer; out aError: string): Boolean;
var
  lBatPath: string;
  lRoot: string;
  lProjectPath: string;
  lCmdExe: string;
  lCmdLine: string;
  lWorkDir: string;
  lSi: TStartupInfo;
  lPi: TProcessInformation;
  lWait: Cardinal;
  lExit: Cardinal;
  lDelphiVer: string;
begin
  Result := False;
  aExitCode := 0;
  aError := '';

  lRoot := TPath.GetFullPath(TPath.Combine(ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))), '..'));
  lBatPath := TPath.Combine(lRoot, 'build-delphi.bat');
  if not FileExists(lBatPath) then
  begin
    aError := Format(SBuildBatMissing, [lBatPath]);
    Exit(False);
  end;

  lProjectPath := TPath.GetFullPath(aOptions.fDprojPath);
  lDelphiVer := NormalizeDelphiVerForBuild(aOptions.fDelphiVersion);
  if lDelphiVer = '' then
    lDelphiVer := aOptions.fDelphiVersion;

  lCmdExe := GetEnvironmentVariable('ComSpec');
  if lCmdExe = '' then
    lCmdExe := 'C:\Windows\System32\cmd.exe';

  lCmdLine := QuoteCmdArg(lCmdExe) + ' /C "call ' + QuoteCmdArg(lBatPath) + ' ' +
    QuoteCmdArg(lProjectPath) + ' -config ' + aOptions.fConfig + ' -platform ' + aOptions.fPlatform +
    ' -ver ' + lDelphiVer + '"';
  UniqueString(lCmdLine);
  lWorkDir := ExtractFilePath(lBatPath);

  FillChar(lSi, SizeOf(lSi), 0);
  lSi.cb := SizeOf(lSi);
  FillChar(lPi, SizeOf(lPi), 0);

  if not CreateProcess(PChar(lCmdExe), PChar(lCmdLine), nil, nil, True, 0, nil, PChar(lWorkDir), lSi, lPi) then
  begin
    aError := SysErrorMessage(GetLastError);
    Exit(False);
  end;
  try
    lWait := WaitForSingleObject(lPi.hProcess, INFINITE);
    if lWait <> WAIT_OBJECT_0 then
    begin
      aError := SysErrorMessage(GetLastError);
      Exit(False);
    end;
    if not GetExitCodeProcess(lPi.hProcess, lExit) then
    begin
      aError := SysErrorMessage(GetLastError);
      Exit(False);
    end;
    aExitCode := Integer(lExit);
    Result := True;
  finally
    CloseHandle(lPi.hThread);
    CloseHandle(lPi.hProcess);
  end;
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
          if not TryRunBuildDelphi(lOptions, lExitCode, lError) then
          begin
            writeln(ErrOutput, lError);
            lExitCode := 6;
          end;
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

