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

var
  lOptions: TAppOptions;
  lParams: TFixInsightParams;
  lEnvVars: TDictionary<string, string>;
  lDiagnostics: TDiagnostics;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lFixOptions: TFixInsightExtraOptions;
  lError: string;
  lErrorCode: integer;
  lExitCode: integer;
  lOutPath: string;
  lOk: boolean;
  lRunExit: Cardinal;
  lRunError: string;
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
        lDiagnostics.AddInfo(Format(SInfoStep, ['Read settings.ini']));
        lOk := LoadFixInsightDefaults(lDiagnostics, lFixOptions);
        if not lOk then
        begin
          lExitCode := 6;
        end else
          ApplyFixInsightOverrides(lOptions, lFixOptions);
      end;

      if lOk then
      begin
        lDiagnostics.AddInfo(Format(SInfoStep, ['Validate inputs']));
        lOptions.fDprojPath := TPath.GetFullPath(lOptions.fDprojPath);
        if not FileExists(lOptions.fDprojPath) then
        begin
          writeln(ErrOutput, Format(SFileNotFound, [lOptions.fDprojPath]));
          lExitCode := 3;
          lOk := False;
        end;
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
        writeln(ErrOutput, Format(SSourceLibraryPath, [SourceToText(lParams.fLibrarySource)]));
        writeln(ErrOutput, Format(SSourceDefines, [SourceToText(lParams.fDefineSource)]));
        writeln(ErrOutput, Format(SSourceSearchPath, [SourceToText(lParams.fSearchPathSource)]));
        writeln(ErrOutput, Format(SSourceUnitScopes, [SourceToText(lParams.fUnitScopesSource)]));
        if length(lParams.fUnitAliases) > 0 then
          writeln(ErrOutput, Format(SSourceUnitAliases, [SourceToText(lParams.fUnitAliasesSource)]));

        lOutPath := '';
        if lOptions.fHasOutPath then
          lOutPath := lOptions.fOutPath;

        lOk := WriteOutput(lParams, lOptions.fOutKind, lOutPath, lError);
        if not lOk then
        begin
          writeln(ErrOutput, lError);
          lExitCode := 6;
        end;
      end;

      if lOk and lOptions.fRunFixInsight then
      begin
        lDiagnostics.AddInfo(Format(SInfoStep, ['Run FixInsightCL']));
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

