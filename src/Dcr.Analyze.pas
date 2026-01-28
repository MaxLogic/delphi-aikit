unit Dcr.Analyze;

interface

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.SysUtils,
  System.Variants,
  Xml.omnixmldom, Xml.XMLDoc, Xml.XMLIntf,
  Winapi.Windows,
  maxLogic.IOUtils, maxLogic.StrUtils,
  Dcr.Diagnostics, Dcr.FixInsight, Dcr.FixInsightRunner, Dcr.FixInsightSettings, Dcr.Messages,
  Dcr.PascalAnalyzerRunner, Dcr.Project, Dcr.Registry, Dcr.ReportPostProcess, Dcr.RsVars, Dcr.Types;

function RunAnalyzeCommand(const aOptions: TAppOptions): Integer;

implementation

type
  TFixInsightCounts = record
    Total: Integer;
    Top: TArray<TPair<string, Integer>>;
  end;

  TPalSummary = record
    Ran: Boolean;
    ExitCode: Integer;
    OutputRoot: string;
    ReportRoot: string;
    Version: string;
    Compiler: string;
    Warnings: Integer;
    StrongWarnings: Integer;
    Exceptions: Integer;
  end;

function FormatTimestamp: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
end;

procedure AppendLogText(const aPath: string; const aText: string);
var
  lEncoding: TEncoding;
begin
  lEncoding := TUTF8Encoding.Create(False);
  try
    TFile.AppendAllText(aPath, aText, lEncoding);
  finally
    lEncoding.Free;
  end;
end;

procedure WriteLogText(const aPath: string; const aText: string);
var
  lEncoding: TEncoding;
begin
  lEncoding := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(aPath, aText, lEncoding);
  finally
    lEncoding.Free;
  end;
end;

procedure AppendRunHeader(const aLogPath: string; const aWorkDir: string; const aCommandLine: string);
var
  lLines: TStringBuilder;
begin
  lLines := TStringBuilder.Create;
  try
    lLines.AppendLine('');
    lLines.AppendLine(StringOfChar('=', 78));
    lLines.AppendLine('[' + FormatTimestamp + '] RUN');
    lLines.AppendLine('CWD: ' + aWorkDir);
    lLines.AppendLine('CMD: ' + aCommandLine);
    AppendLogText(aLogPath, lLines.ToString);
  finally
    lLines.Free;
  end;
end;

function TryOpenLogHandle(const aLogPath: string; out aHandle: THandle; out aError: string): Boolean;
var
  lSec: TSecurityAttributes;
  lHandle: THandle;
begin
  Result := False;
  aError := '';
  aHandle := 0;

  FillChar(lSec, SizeOf(lSec), 0);
  lSec.nLength := SizeOf(lSec);
  lSec.bInheritHandle := True;

  lHandle := CreateFile(PChar(aLogPath), FILE_APPEND_DATA, FILE_SHARE_READ or FILE_SHARE_WRITE, @lSec,
    OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if lHandle = INVALID_HANDLE_VALUE then
  begin
    aError := 'Failed to open run.log: ' + SysErrorMessage(GetLastError);
    Exit(False);
  end;

  SetFilePointer(lHandle, 0, nil, FILE_END);
  aHandle := lHandle;
  Result := True;
end;

procedure WriteToolLog(const aLogPath: string; const aCommandLine: string; aExitCode: Integer;
  const aError: string);
var
  lLines: TStringBuilder;
begin
  lLines := TStringBuilder.Create;
  try
    lLines.AppendLine('Timestamp: ' + FormatTimestamp);
    if aCommandLine <> '' then
      lLines.AppendLine('CMD: ' + aCommandLine);
    lLines.AppendLine('Exit code: ' + aExitCode.ToString);
    if aError <> '' then
      lLines.AppendLine('Error: ' + aError);
    WriteLogText(aLogPath, lLines.ToString);
  finally
    lLines.Free;
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

function TryParseFixInsightRuleId(const aLine: string; out aRuleId: string): Boolean;
var
  lText: string;
  lCh: Char;
  i: Integer;
begin
  aRuleId := '';
  lText := TrimLeft(aLine);
  if Length(lText) < 4 then
    Exit(False);
  lCh := UpCase(lText[1]);
  if not (lCh in ['A'..'Z']) then
    Exit(False);
  for i := 2 to 4 do
    if not CharInSet(lText[i], ['0'..'9']) then
      Exit(False);
  aRuleId := lCh + Copy(lText, 2, 3);
  Result := True;
end;

procedure CountFixInsightCodes(const aPath: string; out aCounts: TDictionary<string, Integer>;
  out aTotal: Integer);
var
  lReader: TStreamReader;
  lLine: string;
  lRuleId: string;
  lCount: Integer;
begin
  aCounts := TDictionary<string, Integer>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  aTotal := 0;
  if not FileExists(aPath) then
    Exit;

  lReader := nil;
  try
    lReader := TStreamReader.Create(aPath, TEncoding.UTF8, True);
    while not lReader.EndOfStream do
    begin
      lLine := lReader.ReadLine;
      if TryParseFixInsightRuleId(lLine, lRuleId) then
      begin
        if aCounts.TryGetValue(lRuleId, lCount) then
          aCounts[lRuleId] := lCount + 1
        else
          aCounts.AddOrSetValue(lRuleId, 1);
        Inc(aTotal);
      end;
    end;
  finally
    lReader.Free;
  end;
end;

function CompareFixInsightPairs(const aLeft, aRight: TPair<string, Integer>): Integer;
begin
  if aLeft.Value = aRight.Value then
    Result := CompareText(aLeft.Key, aRight.Key)
  else if aLeft.Value > aRight.Value then
    Result := -1
  else
    Result := 1;
end;

function BuildTopFixInsightCodes(const aCounts: TDictionary<string, Integer>; aMax: Integer)
  : TArray<TPair<string, Integer>>;
var
  lList: TList<TPair<string, Integer>>;
  lPair: TPair<string, Integer>;
  lCount: Integer;
  i: Integer;
begin
  Result := nil;
  if (aCounts = nil) or (aCounts.Count = 0) then
    Exit;

  lList := TList<TPair<string, Integer>>.Create;
  try
    for lPair in aCounts do
      lList.Add(lPair);
    lList.Sort(TComparer<TPair<string, Integer>>.Construct(CompareFixInsightPairs));
    lCount := lList.Count;
    if lCount > aMax then
      lCount := aMax;
    SetLength(Result, lCount);
    for i := 0 to lCount - 1 do
      Result[i] := lList[i];
  finally
    lList.Free;
  end;
end;

function FindSectionByName(const aRoot: IXMLNode; const aName: string): IXMLNode;
var
  i: Integer;
  lNode: IXMLNode;
  lAttr: string;
begin
  Result := nil;
  if aRoot = nil then
    Exit;

  for i := 0 to aRoot.ChildNodes.Count - 1 do
  begin
    lNode := aRoot.ChildNodes[i];
    if not SameText(lNode.NodeName, 'section') then
      Continue;
    if lNode.HasAttribute('name') then
    begin
      lAttr := VarToStr(lNode.Attributes['name']);
      if SameText(lAttr, aName) then
        Exit(lNode);
    end;
  end;
end;

function FindChildText(const aNode: IXMLNode; const aChildName: string): string;
var
  i: Integer;
  lNode: IXMLNode;
begin
  Result := '';
  if aNode = nil then
    Exit;

  for i := 0 to aNode.ChildNodes.Count - 1 do
  begin
    lNode := aNode.ChildNodes[i];
    if SameText(lNode.NodeName, aChildName) then
    begin
      Result := Trim(VarToStr(lNode.Text));
      Exit;
    end;
  end;
end;

procedure SumSectionCounts(const aNode: IXMLNode; var aTotal: Integer);
var
  i: Integer;
  lNode: IXMLNode;
  lCountText: string;
  lCount: Integer;
begin
  if aNode = nil then
    Exit;

  if SameText(aNode.NodeName, 'section') and aNode.HasAttribute('count') then
  begin
    lCountText := VarToStr(aNode.Attributes['count']);
    lCount := StrToIntDef(lCountText, 0);
    Inc(aTotal, lCount);
  end;

  for i := 0 to aNode.ChildNodes.Count - 1 do
  begin
    lNode := aNode.ChildNodes[i];
    SumSectionCounts(lNode, aTotal);
  end;
end;

function LoadXmlDocument(const aPath: string): IXMLDocument;
var
  lDoc: IXMLDocument;
begin
  if not FileExists(aPath) then
    Exit(nil);
  lDoc := LoadXMLDocument(aPath);
  Result := lDoc;
end;

function GetSectionCountTotal(const aPath: string): Integer;
var
  lDoc: IXMLDocument;
begin
  Result := 0;
  lDoc := LoadXmlDocument(aPath);
  if lDoc = nil then
    Exit(0);
  SumSectionCounts(lDoc.DocumentElement, Result);
end;

procedure ReadStatusSummary(const aPath: string; out aVersion: string; out aCompiler: string);
var
  lDoc: IXMLDocument;
  lRoot: IXMLNode;
  lOverview: IXMLNode;
begin
  aVersion := '';
  aCompiler := '';
  lDoc := LoadXmlDocument(aPath);
  if lDoc = nil then
    Exit;
  lRoot := lDoc.DocumentElement;
  if lRoot = nil then
    Exit;
  lOverview := FindSectionByName(lRoot, 'Overview');
  if lOverview = nil then
    Exit;
  aVersion := FindChildText(lOverview, 'version');
  aCompiler := FindChildText(lOverview, 'compiler');
end;

function TryPrepareProjectParams(const aOptions: TAppOptions; aDiagnostics: TDiagnostics;
  out aParams: TFixInsightParams; out aFixOptions: TFixInsightExtraOptions; out aFixIgnoreDefaults: TFixInsightIgnoreDefaults;
  out aReportFilter: TReportFilterDefaults; out aPascalAnalyzer: TPascalAnalyzerDefaults; out aProjectName: string;
  out aError: string; out aErrorCode: Integer): Boolean;
var
  lEnvVars: TDictionary<string, string>;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lError: string;
  lInputPath: string;
  lFixExe: string;
  lOptions: TAppOptions;
  lDprojPath: string;
begin
  Result := False;
  aError := '';
  aErrorCode := 6;
  aProjectName := '';
  aParams := Default(TFixInsightParams);

  lEnvVars := nil;
  try
    if not LoadSettings(aDiagnostics, aFixOptions, aFixIgnoreDefaults, aReportFilter, aPascalAnalyzer) then
    begin
      aError := 'Failed to read settings.ini.';
      aErrorCode := 6;
      Exit(False);
    end;
    ApplySettingsOverrides(aOptions, aFixOptions, aFixIgnoreDefaults, aReportFilter, aPascalAnalyzer);

    lOptions := aOptions;
    lInputPath := aOptions.fDprojPath;
    if not TryResolveDprojPath(lInputPath, lDprojPath, lError) then
    begin
      aError := lError;
      aErrorCode := 3;
      Exit(False);
    end;

    lOptions.fDprojPath := lDprojPath;
    aProjectName := TPath.GetFileNameWithoutExtension(lDprojPath);

    if not TryLoadRsVars(lOptions.fDelphiVersion, lOptions.fRsVarsPath, aDiagnostics, lError) then
    begin
      aError := lError;
      aErrorCode := 4;
      Exit(False);
    end;

    if not TryReadIdeConfig(lOptions.fDelphiVersion, lOptions.fPlatform, lOptions.fEnvOptionsPath, lEnvVars,
      lLibraryPath, lLibrarySource, aDiagnostics, lError) then
    begin
      aError := lError;
      aErrorCode := 4;
      Exit(False);
    end;

    if not TryBuildParams(lOptions, lEnvVars, lLibraryPath, lLibrarySource, aDiagnostics, aParams, lError, aErrorCode) then
    begin
      aError := lError;
      Exit(False);
    end;

    if aFixOptions.fExePath <> '' then
    begin
      lFixExe := ResolveFixInsightPath(aFixOptions.fExePath);
      if (lFixExe <> '') and FileExists(lFixExe) then
        aParams.fFixInsightExe := lFixExe
      else
        aDiagnostics.AddWarning(Format(SFixInsightPathInvalid, [aFixOptions.fExePath]));
    end;

    if (aParams.fFixInsightExe = '') and (not TryResolveFixInsightExe(aDiagnostics, aParams.fFixInsightExe)) then
      aDiagnostics.AddWarning(SFixInsightNotFound);

    Result := True;
  finally
    lEnvVars.Free;
  end;
end;

function BuildOutputRoot(const aBaseOut: string; const aProjectName: string): string;
var
  lOut: string;
begin
  if aBaseOut <> '' then
  begin
    lOut := aBaseOut;
    if not TPath.IsPathRooted(lOut) then
      lOut := TPath.GetFullPath(lOut);
    Exit(lOut);
  end;

  Result := CombinePath([GetCurrentDir, '_analysis', aProjectName]);
end;

function BuildUnitOutputRoot(const aBaseOut: string; const aUnitName: string): string;
var
  lOut: string;
begin
  if aBaseOut <> '' then
  begin
    lOut := aBaseOut;
    if not TPath.IsPathRooted(lOut) then
      lOut := TPath.GetFullPath(lOut);
    Exit(lOut);
  end;

  Result := CombinePath([GetCurrentDir, '_analysis', '_unit', aUnitName]);
end;

function TryRunFixInsightLogged(const aParams: TFixInsightParams; const aRunLogPath: string;
  out aExitCode: Cardinal; out aError: string): Boolean;
var
  lExe: string;
  lCmdLine: string;
  lHandle: THandle;
  lLogError: string;
  lWorkDir: string;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not BuildFixInsightCommandLine(aParams, lExe, lCmdLine, aError) then
    Exit(False);

  lWorkDir := GetCurrentDir;
  AppendRunHeader(aRunLogPath, lWorkDir, lCmdLine);

  if not TryOpenLogHandle(aRunLogPath, lHandle, lLogError) then
  begin
    aError := lLogError;
    Exit(False);
  end;
  try
    Result := TryRunFixInsightWithHandles(aParams, lHandle, lHandle, aExitCode, aError);
  finally
    CloseHandle(lHandle);
  end;
end;

function TryRunPalLogged(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  const aRunLogPath: string; out aExitCode: Cardinal; out aError: string): Boolean;
var
  lExe: string;
  lCmdLine: string;
  lHandle: THandle;
  lLogError: string;
  lWorkDir: string;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not BuildPalCmdCommandLine(aParams, aPa, lExe, lCmdLine, aError) then
    Exit(False);

  lWorkDir := GetCurrentDir;
  AppendRunHeader(aRunLogPath, lWorkDir, lCmdLine);

  if not TryOpenLogHandle(aRunLogPath, lHandle, lLogError) then
  begin
    aError := lLogError;
    Exit(False);
  end;
  try
    Result := TryRunPascalAnalyzerWithHandles(aParams, aPa, lHandle, lHandle, aExitCode, aError);
  finally
    CloseHandle(lHandle);
  end;
end;

function TryRunPalUnitLogged(const aUnitPath: string; const aPa: TPascalAnalyzerDefaults;
  const aRunLogPath: string; out aExitCode: Cardinal; out aError: string): Boolean;
var
  lExe: string;
  lCmdLine: string;
  lHandle: THandle;
  lLogError: string;
  lWorkDir: string;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not BuildPalCmdUnitCommandLine(aUnitPath, aPa, lExe, lCmdLine, aError) then
    Exit(False);

  lWorkDir := GetCurrentDir;
  AppendRunHeader(aRunLogPath, lWorkDir, lCmdLine);

  if not TryOpenLogHandle(aRunLogPath, lHandle, lLogError) then
  begin
    aError := lLogError;
    Exit(False);
  end;
  try
    Result := TryRunPascalAnalyzerUnit(aUnitPath, aPa, lHandle, lHandle, aExitCode, aError);
  finally
    CloseHandle(lHandle);
  end;
end;

procedure CaptureFixInsightSummary(const aTxtPath: string; out aCounts: TFixInsightCounts);
var
  lCounts: TDictionary<string, Integer>;
begin
  aCounts.Total := 0;
  aCounts.Top := nil;
  CountFixInsightCodes(aTxtPath, lCounts, aCounts.Total);
  try
    aCounts.Top := BuildTopFixInsightCodes(lCounts, 10);
  finally
    lCounts.Free;
  end;
end;

function BuildProjectSummary(const aProjectName: string; const aDprojPath: string; const aOutRoot: string;
  const aFixTxtPath: string; const aFixXmlPath: string; const aFixCsvPath: string; aFixTxtRan: Boolean;
  aFixXmlRan: Boolean; aFixCsvRan: Boolean; aFixTxtExit: Integer; aFixXmlExit: Integer; aFixCsvExit: Integer;
  const aFixCounts: TFixInsightCounts; const aPal: TPalSummary; const aErrors: TArray<string>): string;
var
  lLines: TStringBuilder;
  lOutputs: TList<string>;
  lCodes: TList<string>;
  lMissing: TList<string>;
  lItem: string;
  lPair: TPair<string, Integer>;
begin
  lLines := TStringBuilder.Create;
  lOutputs := TList<string>.Create;
  lCodes := TList<string>.Create;
  lMissing := TList<string>.Create;
  try
    lLines.AppendLine('# Static analysis summary: ' + aProjectName);
    lLines.AppendLine('');
    lLines.AppendLine('- Timestamp: ' + FormatTimestamp);
    lLines.AppendLine('- Project: `' + aDprojPath + '`');
    lLines.AppendLine('- Outputs: `' + aOutRoot + '`');
    lLines.AppendLine('');

    lLines.AppendLine('## FixInsight');
    lLines.AppendLine('');

    if aFixTxtRan then
      lOutputs.Add('txt=`' + aFixTxtPath + '`');
    if aFixXmlRan then
      lOutputs.Add('xml=`' + aFixXmlPath + '`');
    if aFixCsvRan then
      lOutputs.Add('csv=`' + aFixCsvPath + '`');

    if lOutputs.Count > 0 then
      lLines.AppendLine('- Report files: ' + String.Join(', ', lOutputs.ToArray))
    else
      lLines.AppendLine('- Report files: (none)');

    if aFixTxtRan then
      lCodes.Add('txt=' + aFixTxtExit.ToString);
    if aFixXmlRan then
      lCodes.Add('xml=' + aFixXmlExit.ToString);
    if aFixCsvRan then
      lCodes.Add('csv=' + aFixCsvExit.ToString);

    if lCodes.Count > 0 then
      lLines.AppendLine('- Exit codes: ' + String.Join(', ', lCodes.ToArray))
    else
      lLines.AppendLine('- Exit codes: (none)');

    if aFixTxtRan and (not FileExists(aFixTxtPath)) then
      lMissing.Add('txt');
    if aFixXmlRan and (not FileExists(aFixXmlPath)) then
      lMissing.Add('xml');
    if aFixCsvRan and (not FileExists(aFixCsvPath)) then
      lMissing.Add('csv');
    if lMissing.Count > 0 then
      lLines.AppendLine('- Note: some outputs are missing (' + String.Join(', ', lMissing.ToArray) + ').');

    if FileExists(aFixTxtPath) then
      lLines.AppendLine('- Findings (by code): ' + aFixCounts.Total.ToString)
    else
      lLines.AppendLine('- Findings (by code): (TXT not generated)');

    if Length(aFixCounts.Top) > 0 then
    begin
      lLines.AppendLine('- Top codes:');
      for lPair in aFixCounts.Top do
        lLines.AppendLine('  - ' + lPair.Key + ': ' + lPair.Value.ToString);
    end;
    lLines.AppendLine('');

    lLines.AppendLine('## Pascal Analyzer');
    lLines.AppendLine('');
    if aPal.Ran then
    begin
      lLines.AppendLine('- Output root: `' + aPal.OutputRoot + '`');
      lLines.AppendLine('- Exit code: ' + aPal.ExitCode.ToString);
      if aPal.ReportRoot <> '' then
        lLines.AppendLine('- Report folder: `' + aPal.ReportRoot + '`');
      if aPal.Version <> '' then
        lLines.AppendLine('- Version: ' + aPal.Version);
      if aPal.Compiler <> '' then
        lLines.AppendLine('- Compiler target: ' + aPal.Compiler);
      lLines.AppendLine(Format('- Totals: warnings=%d, strong_warnings=%d, exceptions=%d', [
        aPal.Warnings, aPal.StrongWarnings, aPal.Exceptions]));
    end else
      lLines.AppendLine('- Skipped.');
    lLines.AppendLine('');

    if Length(aErrors) > 0 then
    begin
      lLines.AppendLine('## Errors');
      lLines.AppendLine('');
      for lItem in aErrors do
        lLines.AppendLine('- ' + lItem);
      lLines.AppendLine('');
    end;

    Result := lLines.ToString;
  finally
    lMissing.Free;
    lCodes.Free;
    lOutputs.Free;
    lLines.Free;
  end;
end;

function BuildUnitSummary(const aUnitName: string; const aUnitPath: string; const aOutRoot: string;
  const aPal: TPalSummary; const aErrors: TArray<string>): string;
var
  lLines: TStringBuilder;
  lItem: string;
begin
  lLines := TStringBuilder.Create;
  try
    lLines.AppendLine('# Pascal Analyzer unit summary: ' + aUnitName);
    lLines.AppendLine('');
    lLines.AppendLine('- Timestamp: ' + FormatTimestamp);
    lLines.AppendLine('- Unit: `' + aUnitPath + '`');
    lLines.AppendLine('- Output: `' + aOutRoot + '`');
    if aPal.ReportRoot <> '' then
      lLines.AppendLine('- Report folder: `' + aPal.ReportRoot + '`');
    if aPal.Version <> '' then
      lLines.AppendLine('- PAL version: ' + aPal.Version);
    if aPal.Compiler <> '' then
      lLines.AppendLine('- Compiler target: ' + aPal.Compiler);
    lLines.AppendLine('');

    if Length(aErrors) > 0 then
    begin
      lLines.AppendLine('## Errors');
      lLines.AppendLine('');
      for lItem in aErrors do
        lLines.AppendLine('- ' + lItem);
      lLines.AppendLine('');
    end;

    Result := lLines.ToString;
  finally
    lLines.Free;
  end;
end;

function RunAnalyzeProject(const aOptions: TAppOptions): Integer;
var
  lDiagnostics: TDiagnostics;
  lFixOptions: TFixInsightExtraOptions;
  lFixIgnoreDefaults: TFixInsightIgnoreDefaults;
  lReportFilter: TReportFilterDefaults;
  lPascalAnalyzer: TPascalAnalyzerDefaults;
  lParams: TFixInsightParams;
  lError: string;
  lErrorCode: Integer;
  lProjectName: string;
  lOutRoot: string;
  lFixDir: string;
  lPaDir: string;
  lRunLog: string;
  lSummaryPath: string;
  lFixTxtPath: string;
  lFixXmlPath: string;
  lFixCsvPath: string;
  lFixTxtRan: Boolean;
  lFixXmlRan: Boolean;
  lFixCsvRan: Boolean;
  lFixTxtExit: Integer;
  lFixXmlExit: Integer;
  lFixCsvExit: Integer;
  lFixCounts: TFixInsightCounts;
  lErrors: TList<string>;
  lRunExit: Cardinal;
  lRunError: string;
  lExitCode: Integer;
  lFilterError: string;
  lFixLogPath: string;
  lPal: TPalSummary;
  lPaReportRoot: string;
  lSummaryText: string;
begin
  lExitCode := 0;
  lDiagnostics := TDiagnostics.Create;
  lErrors := TList<string>.Create;
  try
    lDiagnostics.Verbose := aOptions.fVerbose;
    if aOptions.fHasLogFile then
    begin
      if not lDiagnostics.TryOpenLogFile(TPath.GetFullPath(aOptions.fLogFile), lError) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(6);
      end;
      if aOptions.fHasLogTee then
        lDiagnostics.LogToStderr := aOptions.fLogTee
      else
        lDiagnostics.LogToStderr := False;
    end;

    if not TryPrepareProjectParams(aOptions, lDiagnostics, lParams, lFixOptions, lFixIgnoreDefaults, lReportFilter,
      lPascalAnalyzer, lProjectName, lError, lErrorCode) then
    begin
      WriteLn(ErrOutput, lError);
      Exit(lErrorCode);
    end;

    lOutRoot := BuildOutputRoot(aOptions.fAnalyzeOutPath, lProjectName);
    if aOptions.fAnalyzeClean and DirectoryExists(lOutRoot) then
      TDirectory.Delete(lOutRoot, True);
    TDirectory.CreateDirectory(lOutRoot);

    lFixDir := TPath.Combine(lOutRoot, 'fixinsight');
    lPaDir := TPath.Combine(lOutRoot, 'pascal-analyzer');
    TDirectory.CreateDirectory(lFixDir);
    TDirectory.CreateDirectory(lPaDir);

    lRunLog := TPath.Combine(lOutRoot, 'run.log');
    if aOptions.fAnalyzeClean or (not FileExists(lRunLog)) then
      WriteLogText(lRunLog, '');

    lParams.fFixIgnore := lFixOptions.fIgnore;
    lParams.fFixSettings := lFixOptions.fSettings;
    lParams.fFixSilent := lFixOptions.fSilent;
    if lParams.fFixSettings <> '' then
      lParams.fFixSettings := TPath.GetFullPath(lParams.fFixSettings);

    lFixTxtPath := TPath.Combine(lFixDir, 'fixinsight.txt');
    lFixXmlPath := TPath.Combine(lFixDir, 'fixinsight.xml');
    lFixCsvPath := TPath.Combine(lFixDir, 'fixinsight.csv');

    lFixTxtRan := False;
    lFixXmlRan := False;
    lFixCsvRan := False;
  lFixTxtExit := -1;
  lFixXmlExit := -1;
  lFixCsvExit := -1;

    if TReportFormat.rfText in aOptions.fAnalyzeFiFormats then
    begin
      lFixTxtRan := True;
      lParams.fFixOutput := TPath.GetFullPath(lFixTxtPath);
      lParams.fFixXml := False;
      lParams.fFixCsv := False;
      lFixLogPath := TPath.Combine(lFixDir, 'fixinsight.txt.log');
      if TryRunFixInsightLogged(lParams, lRunLog, lRunExit, lRunError) then
      begin
        lFixTxtExit := Integer(lRunExit);
        if lFixTxtExit <> 0 then
        begin
          lErrors.Add(Format('FixInsight TXT failed (exit=%d).', [lFixTxtExit]));
          if lExitCode = 0 then
            lExitCode := lFixTxtExit;
        end
        else if HasAnyReportFilters(lReportFilter.fExcludePathMasks, lFixIgnoreDefaults.fWarnings) then
        begin
          if not TryPostProcessFixInsightReport(lParams.fFixOutput, TReportFormat.rfText,
            lReportFilter.fExcludePathMasks, lFixIgnoreDefaults.fWarnings, lFilterError) then
          begin
            lErrors.Add('FixInsight TXT post-processing failed: ' + lFilterError);
            if lExitCode = 0 then
              lExitCode := 6;
          end;
        end;
      end else
      begin
        lErrors.Add('FixInsight TXT failed: ' + lRunError);
        if lExitCode = 0 then
          lExitCode := 6;
      end;
      WriteToolLog(lFixLogPath, 'FixInsight TXT', lFixTxtExit, lRunError);
    end;

    if TReportFormat.rfXml in aOptions.fAnalyzeFiFormats then
    begin
      lFixXmlRan := True;
      lParams.fFixOutput := TPath.GetFullPath(lFixXmlPath);
      lParams.fFixXml := True;
      lParams.fFixCsv := False;
      lFixLogPath := TPath.Combine(lFixDir, 'fixinsight.xml.log');
      if TryRunFixInsightLogged(lParams, lRunLog, lRunExit, lRunError) then
      begin
        lFixXmlExit := Integer(lRunExit);
        if lFixXmlExit <> 0 then
        begin
          lErrors.Add(Format('FixInsight XML failed (exit=%d).', [lFixXmlExit]));
          if lExitCode = 0 then
            lExitCode := lFixXmlExit;
        end
        else if HasAnyReportFilters(lReportFilter.fExcludePathMasks, lFixIgnoreDefaults.fWarnings) then
        begin
          if not TryPostProcessFixInsightReport(lParams.fFixOutput, TReportFormat.rfXml,
            lReportFilter.fExcludePathMasks, lFixIgnoreDefaults.fWarnings, lFilterError) then
          begin
            lErrors.Add('FixInsight XML post-processing failed: ' + lFilterError);
            if lExitCode = 0 then
              lExitCode := 6;
          end;
        end;
      end else
      begin
        lErrors.Add('FixInsight XML failed: ' + lRunError);
        if lExitCode = 0 then
          lExitCode := 6;
      end;
      WriteToolLog(lFixLogPath, 'FixInsight XML', lFixXmlExit, lRunError);
    end;

    if TReportFormat.rfCsv in aOptions.fAnalyzeFiFormats then
    begin
      lFixCsvRan := True;
      lParams.fFixOutput := TPath.GetFullPath(lFixCsvPath);
      lParams.fFixXml := False;
      lParams.fFixCsv := True;
      lFixLogPath := TPath.Combine(lFixDir, 'fixinsight.csv.log');
      if TryRunFixInsightLogged(lParams, lRunLog, lRunExit, lRunError) then
      begin
        lFixCsvExit := Integer(lRunExit);
        if lFixCsvExit <> 0 then
        begin
          lErrors.Add(Format('FixInsight CSV failed (exit=%d).', [lFixCsvExit]));
          if lExitCode = 0 then
            lExitCode := lFixCsvExit;
        end
        else if HasAnyReportFilters(lReportFilter.fExcludePathMasks, lFixIgnoreDefaults.fWarnings) then
        begin
          if not TryPostProcessFixInsightReport(lParams.fFixOutput, TReportFormat.rfCsv,
            lReportFilter.fExcludePathMasks, lFixIgnoreDefaults.fWarnings, lFilterError) then
          begin
            lErrors.Add('FixInsight CSV post-processing failed: ' + lFilterError);
            if lExitCode = 0 then
              lExitCode := 6;
          end;
        end;
      end else
      begin
        lErrors.Add('FixInsight CSV failed: ' + lRunError);
        if lExitCode = 0 then
          lExitCode := 6;
      end;
      WriteToolLog(lFixLogPath, 'FixInsight CSV', lFixCsvExit, lRunError);
    end;

    lPal := Default(TPalSummary);
    if aOptions.fAnalyzePal then
    begin
      lPal.Ran := True;
      if aOptions.fHasPaOutput then
        lPascalAnalyzer.fOutput := TPath.GetFullPath(aOptions.fPaOutput)
      else
        lPascalAnalyzer.fOutput := lPaDir;
      lPal.OutputRoot := lPascalAnalyzer.fOutput;
      if TryRunPalLogged(lParams, lPascalAnalyzer, lRunLog, lRunExit, lRunError) then
      begin
        lPal.ExitCode := Integer(lRunExit);
        if lPal.ExitCode <> 0 then
        begin
          lErrors.Add(Format('Pascal Analyzer failed (exit=%d).', [lPal.ExitCode]));
          if lExitCode = 0 then
            lExitCode := lPal.ExitCode;
        end
        else
        begin
          if TryFindPalReportRoot(lPal.OutputRoot, lPaReportRoot, lRunError) then
          begin
            lPal.ReportRoot := lPaReportRoot;
            ReadStatusSummary(TPath.Combine(lPaReportRoot, 'Status.xml'), lPal.Version, lPal.Compiler);
            lPal.Warnings := GetSectionCountTotal(TPath.Combine(lPaReportRoot, 'Warnings.xml'));
            lPal.StrongWarnings := GetSectionCountTotal(TPath.Combine(lPaReportRoot, 'Strong Warnings.xml'));
            lPal.Exceptions := GetSectionCountTotal(TPath.Combine(lPaReportRoot, 'Exception.xml'));
            if not TryGeneratePalArtifacts(lPaReportRoot, lPal.OutputRoot, lRunError) then
              lDiagnostics.AddWarning('PAL findings generation failed: ' + lRunError);
          end else
          begin
            lDiagnostics.AddWarning('PAL report root not found: ' + lRunError);
          end;
        end;
      end else
      begin
        lPal.ExitCode := -1;
        lErrors.Add('Pascal Analyzer failed: ' + lRunError);
        if lExitCode = 0 then
          lExitCode := 6;
      end;
      WriteToolLog(TPath.Combine(lPaDir, 'pascal-analyzer.log'), 'PALCMD', lPal.ExitCode, lRunError);
    end;

    CaptureFixInsightSummary(lFixTxtPath, lFixCounts);

    if aOptions.fAnalyzeWriteSummary then
    begin
      lSummaryPath := TPath.Combine(lOutRoot, 'summary.md');
      lSummaryText := BuildProjectSummary(lProjectName, lParams.fProjectDpr, lOutRoot, lFixTxtPath, lFixXmlPath,
        lFixCsvPath, lFixTxtRan, lFixXmlRan, lFixCsvRan, lFixTxtExit, lFixXmlExit, lFixCsvExit, lFixCounts, lPal,
        lErrors.ToArray);
      WriteLogText(lSummaryPath, lSummaryText);
    end;
  finally
    lDiagnostics.WriteToStderr;
    lErrors.Free;
    lDiagnostics.Free;
  end;

  Result := lExitCode;
end;

function RunAnalyzeUnit(const aOptions: TAppOptions): Integer;
var
  lDiagnostics: TDiagnostics;
  lFixOptions: TFixInsightExtraOptions;
  lFixIgnoreDefaults: TFixInsightIgnoreDefaults;
  lReportFilter: TReportFilterDefaults;
  lPascalAnalyzer: TPascalAnalyzerDefaults;
  lOutRoot: string;
  lPaDir: string;
  lRunLog: string;
  lSummaryPath: string;
  lErrors: TList<string>;
  lUnitPath: string;
  lUnitName: string;
  lRunExit: Cardinal;
  lRunError: string;
  lExitCode: Integer;
  lPal: TPalSummary;
  lPaReportRoot: string;
  lSummaryText: string;
  lError: string;
begin
  lExitCode := 0;
  lDiagnostics := TDiagnostics.Create;
  lErrors := TList<string>.Create;
  try
    lDiagnostics.Verbose := aOptions.fVerbose;
    if aOptions.fHasLogFile then
    begin
      if not lDiagnostics.TryOpenLogFile(TPath.GetFullPath(aOptions.fLogFile), lError) then
      begin
        WriteLn(ErrOutput, lError);
        Exit(6);
      end;
      if aOptions.fHasLogTee then
        lDiagnostics.LogToStderr := aOptions.fLogTee
      else
        lDiagnostics.LogToStderr := False;
    end;

    if not LoadSettings(lDiagnostics, lFixOptions, lFixIgnoreDefaults, lReportFilter, lPascalAnalyzer) then
    begin
      WriteLn(ErrOutput, 'Failed to read settings.ini.');
      Exit(6);
    end;
    ApplySettingsOverrides(aOptions, lFixOptions, lFixIgnoreDefaults, lReportFilter, lPascalAnalyzer);

    lUnitPath := TPath.GetFullPath(aOptions.fUnitPath);
    if not FileExists(lUnitPath) then
    begin
      WriteLn(ErrOutput, Format(SFileNotFound, [lUnitPath]));
      Exit(3);
    end;

    lUnitName := TPath.GetFileNameWithoutExtension(lUnitPath);
    lOutRoot := BuildUnitOutputRoot(aOptions.fAnalyzeOutPath, lUnitName);
    if aOptions.fAnalyzeClean and DirectoryExists(lOutRoot) then
      TDirectory.Delete(lOutRoot, True);
    TDirectory.CreateDirectory(lOutRoot);

    lPaDir := TPath.Combine(lOutRoot, 'pascal-analyzer');
    TDirectory.CreateDirectory(lPaDir);

    lRunLog := TPath.Combine(lOutRoot, 'run.log');
    if aOptions.fAnalyzeClean or (not FileExists(lRunLog)) then
      WriteLogText(lRunLog, '');

    lPal := Default(TPalSummary);
    if aOptions.fAnalyzePal then
    begin
      lPal.Ran := True;
      if aOptions.fHasPaOutput then
        lPascalAnalyzer.fOutput := TPath.GetFullPath(aOptions.fPaOutput)
      else
        lPascalAnalyzer.fOutput := lPaDir;
      lPal.OutputRoot := lPascalAnalyzer.fOutput;
      if TryRunPalUnitLogged(lUnitPath, lPascalAnalyzer, lRunLog, lRunExit, lRunError) then
      begin
        lPal.ExitCode := Integer(lRunExit);
        if lPal.ExitCode <> 0 then
        begin
          lErrors.Add(Format('Pascal Analyzer failed (exit=%d).', [lPal.ExitCode]));
          if lExitCode = 0 then
            lExitCode := lPal.ExitCode;
        end
        else if TryFindPalReportRoot(lPal.OutputRoot, lPaReportRoot, lRunError) then
        begin
          lPal.ReportRoot := lPaReportRoot;
          ReadStatusSummary(TPath.Combine(lPaReportRoot, 'Status.xml'), lPal.Version, lPal.Compiler);
        end else
        begin
          lDiagnostics.AddWarning('PAL report root not found: ' + lRunError);
        end;
      end else
      begin
        lPal.ExitCode := -1;
        lErrors.Add('Pascal Analyzer failed: ' + lRunError);
        if lExitCode = 0 then
          lExitCode := 6;
      end;
      WriteToolLog(TPath.Combine(lPaDir, 'pascal-analyzer.log'), 'PALCMD', lPal.ExitCode, lRunError);
    end;

    if aOptions.fAnalyzeWriteSummary then
    begin
      lSummaryPath := TPath.Combine(lOutRoot, 'summary.md');
      lSummaryText := BuildUnitSummary(lUnitName, lUnitPath, lOutRoot, lPal, lErrors.ToArray);
      WriteLogText(lSummaryPath, lSummaryText);
    end;
  finally
    lDiagnostics.WriteToStderr;
    lErrors.Free;
    lDiagnostics.Free;
  end;

  Result := lExitCode;
end;

function RunAnalyzeCommand(const aOptions: TAppOptions): Integer;
begin
  if aOptions.fCommand = TCommandKind.ckAnalyzeProject then
    Result := RunAnalyzeProject(aOptions)
  else if aOptions.fCommand = TCommandKind.ckAnalyzeUnit then
    Result := RunAnalyzeUnit(aOptions)
  else
    Result := 2;
end;

end.
