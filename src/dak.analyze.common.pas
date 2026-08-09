unit Dak.Analyze.Common;

interface

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.SysUtils,
  System.Variants,
  Xml.omnixmldom, Xml.XMLDoc, Xml.XMLIntf,
  Winapi.Windows,
  maxLogic.IOUtils, maxLogic.StrUtils,
  Dak.Diagnostics, Dak.FixInsight, Dak.FixInsightRunner, Dak.Messages,
  Dak.PascalAnalyzerRunner, Dak.Paths, Dak.Project.BuildParams, Dak.Registry, Dak.ReportPostProcess, Dak.RsVars,
  Dak.Settings, Dak.Types, Dak.Utils;

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
    Context: string;
    Warnings: Integer;
    StrongWarnings: Integer;
    Optimizations: Integer;
  end;

function FormatTimestamp: string;
procedure AppendLogText(const aPath: string; const aText: string);
procedure WriteLogText(const aPath: string; const aText: string);
procedure AppendRunHeader(const aLogPath: string; const aWorkDir: string; const aCommandLine: string);
procedure AppendAnalyzeRunLogIndex(const aRunLogPath: string; const aWorkDir: string; const aCommandLine: string;
  const aStdOutLogPath: string; const aStdErrLogPath: string; const aArtifactPath: string);
function TryOpenLogHandle(const aLogPath: string; out aHandle: THandle; out aError: string): Boolean;
procedure WriteToolLog(const aLogPath: string; const aCommandLine: string; aExitCode: Integer; const aError: string);
function GetSectionCountTotal(const aPath: string): Integer;
procedure ReadStatusSummary(const aPath: string; out aVersion: string; out aCompiler: string);
function TryPrepareProjectParams(const aOptions: TAppOptions; aDiagnostics: TDiagnostics;
  out aParams: TFixInsightParams; out aFixOptions: TFixInsightExtraOptions; out aFixIgnoreDefaults: TFixInsightIgnoreDefaults;
  out aReportFilter: TReportFilterDefaults; out aPascalAnalyzer: TPascalAnalyzerDefaults; out aProjectName: string;
  out aProjectDproj: string; out aError: string; out aErrorCode: Integer): Boolean; overload;
function TryPrepareProjectParams(const aOptions: TAppOptions; aDiagnostics: TDiagnostics;
  out aParams: TFixInsightParams; out aFixOptions: TFixInsightExtraOptions; out aFixIgnoreDefaults: TFixInsightIgnoreDefaults;
  out aReportFilter: TReportFilterDefaults; out aPascalAnalyzer: TPascalAnalyzerDefaults;
  out aSettings: TDakSettings; out aProjectName: string; out aProjectDproj: string; out aError: string;
  out aErrorCode: Integer): Boolean; overload;
function BuildOutputRoot(const aBaseOut: string; const aProjectPath: string; const aProjectName: string): string;
function BuildUnitOutputRoot(const aBaseOut: string; const aUnitPath: string; const aUnitName: string): string;
function TryRunFixInsightLogged(const aParams: TFixInsightParams; const aStdOutLogPath: string;
  const aStdErrLogPath: string; const aRunLogPath: string; out aExitCode: Cardinal; out aError: string): Boolean;
function TryRunPalLogged(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  const aStdOutLogPath: string; const aStdErrLogPath: string; const aRunLogPath: string; out aExitCode: Cardinal;
  out aError: string): Boolean;
function TryRunPalUnitLogged(const aUnitPath: string; const aPa: TPascalAnalyzerDefaults;
  const aStdOutLogPath: string; const aStdErrLogPath: string; const aRunLogPath: string; out aExitCode: Cardinal;
  out aError: string): Boolean;
procedure CaptureFixInsightSummary(const aTxtPath: string; out aCounts: TFixInsightCounts);
function BuildProjectSummary(const aProjectName: string; const aDprojPath: string; const aOutRoot: string;
  const aFixTxtPath: string; const aFixXmlPath: string; const aFixCsvPath: string; aFixTxtRan: Boolean;
  aFixXmlRan: Boolean; aFixCsvRan: Boolean; aFixTxtExit: Integer; aFixXmlExit: Integer; aFixCsvExit: Integer;
  const aFixCounts: TFixInsightCounts; const aPal: TPalSummary; const aErrors: TArray<string>): string;
function BuildUnitSummary(const aUnitName: string; const aUnitPath: string; const aOutRoot: string;
  const aPal: TPalSummary; const aErrors: TArray<string>): string;
procedure WriteUnitStatusSeed(const aOutRoot: string; const aUnitPath: string; const aProjectContext: string;
  const aParams: TFixInsightParams; const aSettings: TDakSettings;
  const aPascalAnalyzer: TPascalAnalyzerDefaults; const aPal: TPalSummary; const aDurationMs: Int64;
  const aExitCode: Integer; const aRequested: Boolean; const aErrors: TArray<string>);

implementation

uses
  System.Hash, System.JSON, System.StrUtils;

function FormatTimestamp: string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now);
end;

procedure AppendLogText(const aPath: string; const aText: string);
var
  lEncoding: TEncoding;
  lDir: string;
  lRetry: Integer;
begin
  lDir := ExtractFileDir(aPath);
  if lDir <> '' then
    ForceDirectories(lDir);
  lEncoding := TUTF8Encoding.Create(False);
  try
    for lRetry := 1 to 20 do
      try
        TFile.AppendAllText(aPath, aText, lEncoding);
        Exit;
      except
        on E: EInOutError do
        begin
          if lRetry = 20 then
            raise;
          Sleep(50);
        end;
      end;
  finally
    lEncoding.Free;
  end;
end;

procedure WriteLogText(const aPath: string; const aText: string);
var
  lEncoding: TEncoding;
  lDir: string;
  lRetry: Integer;
begin
  lDir := ExtractFileDir(aPath);
  if lDir <> '' then
    ForceDirectories(lDir);
  lEncoding := TUTF8Encoding.Create(False);
  try
    for lRetry := 1 to 20 do
      try
        TFile.WriteAllText(aPath, aText, lEncoding);
        Exit;
      except
        on E: EInOutError do
        begin
          if lRetry = 20 then
            raise;
          Sleep(50);
        end;
      end;
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

procedure AppendAnalyzeRunLogIndex(const aRunLogPath: string; const aWorkDir: string; const aCommandLine: string;
  const aStdOutLogPath: string; const aStdErrLogPath: string; const aArtifactPath: string);
var
  lLines: TStringBuilder;
begin
  lLines := TStringBuilder.Create;
  try
    lLines.AppendLine('');
    lLines.AppendLine(StringOfChar('=', 78));
    lLines.AppendLine('[' + FormatTimestamp + '] CHILD');
    lLines.AppendLine('CWD: ' + aWorkDir);
    lLines.AppendLine('CMD: ' + aCommandLine);
    lLines.AppendLine('STDOUT: ' + aStdOutLogPath);
    lLines.AppendLine('STDERR: ' + aStdErrLogPath);
    if aArtifactPath <> '' then
      lLines.AppendLine('ARTIFACT: ' + aArtifactPath);
    AppendLogText(aRunLogPath, lLines.ToString);
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

  lHandle := CreateFile(PChar(aLogPath), FILE_APPEND_DATA,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, @lSec,
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
  if not CharInSet(lCh, ['A'..'Z']) then
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
    if lCount > 0 then
      Inc(aTotal, lCount);
  end;

  for i := 0 to aNode.ChildNodes.Count - 1 do
  begin
    lNode := aNode.ChildNodes[i];
    SumSectionCounts(lNode, aTotal);
  end;
end;

function TryLoadXmlDocument(const aPath: string): IXMLDocument;
var
  lDoc: IXMLDocument;
begin
  if not FileExists(aPath) then
    Exit(nil);
  lDoc := Xml.XMLDoc.LoadXMLDocument(aPath);
  Result := lDoc;
end;

function GetSectionCountTotal(const aPath: string): Integer;
var
  lDoc: IXMLDocument;
begin
  Result := 0;
  lDoc := TryLoadXmlDocument(aPath);
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
  lDoc := TryLoadXmlDocument(aPath);
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
  out aProjectDproj: string; out aError: string; out aErrorCode: Integer): Boolean; overload;
var
  lSettings: TDakSettings;
begin
  Result := TryPrepareProjectParams(aOptions, aDiagnostics, aParams, aFixOptions, aFixIgnoreDefaults,
    aReportFilter, aPascalAnalyzer, lSettings, aProjectName, aProjectDproj, aError, aErrorCode);
end;

function TryPrepareProjectParams(const aOptions: TAppOptions; aDiagnostics: TDiagnostics;
  out aParams: TFixInsightParams; out aFixOptions: TFixInsightExtraOptions; out aFixIgnoreDefaults: TFixInsightIgnoreDefaults;
  out aReportFilter: TReportFilterDefaults; out aPascalAnalyzer: TPascalAnalyzerDefaults;
  out aSettings: TDakSettings; out aProjectName: string; out aProjectDproj: string; out aError: string;
  out aErrorCode: Integer): Boolean; overload;
var
  lEnvVars: TDictionary<string, string>;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lError: string;
  lInputPath: string;
  lFixExe: string;
  lOptions: TAppOptions;
  lDprojPath: string;
  lRsVarsEnvironment: TRsVarsEnvironment;
  lRsVarsEnvVars: TDictionary<string, string>;
begin
  Result := False;
  aError := '';
  aErrorCode := 6;
  aProjectName := '';
  aProjectDproj := '';

  lOptions := aOptions;
  lInputPath := aOptions.fDprojPath;
  if not TryResolveDprojPath(lInputPath, lDprojPath, lError) then
  begin
    aError := lError;
    aErrorCode := 3;
    Exit(False);
  end;

  if aOptions.fHasWorkspaceRoot then
    Result := LoadDakSettings(aDiagnostics, lDprojPath, nil, aOptions.fWorkspaceRoot, aSettings)
  else
    Result := LoadDakSettings(aDiagnostics, lDprojPath, nil, aSettings);
  if not Result then
  begin
    aError := aSettings.fError;
    if aError = '' then
      aError := 'Failed to read dak.ini.';
    aErrorCode := 6;
    Exit(False);
  end;
  aFixOptions := aSettings.fFixInsight;
  aFixIgnoreDefaults := aSettings.fFixInsightIgnore;
  aReportFilter := aSettings.fReportFilter;
  aPascalAnalyzer := aSettings.fPascalAnalyzer;
  ApplySettingsOverrides(aOptions, aFixOptions, aFixIgnoreDefaults, aReportFilter, aPascalAnalyzer);
  ApplyPascalAnalyzerIgnoreOverride(aOptions, aSettings.fPascalAnalyzerIgnore);
  aSettings.fFixInsight := aFixOptions;
  aSettings.fFixInsightIgnore := aFixIgnoreDefaults;
  aSettings.fReportFilter := aReportFilter;
  aSettings.fPascalAnalyzer := aPascalAnalyzer;

  lOptions.fDprojPath := lDprojPath;
  aProjectName := TPath.GetFileNameWithoutExtension(lDprojPath);
  aProjectDproj := lDprojPath;

  if not TryLoadRsVars(lOptions.fDelphiVersion, lOptions.fRsVarsPath, aDiagnostics, lRsVarsEnvironment, lError) then
  begin
    aError := lError;
    aErrorCode := 4;
    Exit(False);
  end;

  lRsVarsEnvVars := lRsVarsEnvironment.ToDictionary;
  try
    if not TryReadIdeConfig(lOptions.fDelphiVersion, lOptions.fPlatform, lOptions.fEnvOptionsPath, lRsVarsEnvVars,
      lEnvVars, lLibraryPath, lLibrarySource, aDiagnostics, lError) then
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
    aParams.fEnvironmentBlock := lRsVarsEnvironment.ToEnvironmentBlock;

    if aFixOptions.fExePath <> '' then
    begin
      lFixExe := ResolveExePathFromConfiguredValue(aFixOptions.fExePath, 'FixInsightCL.exe');
      if (lFixExe <> '') and FileExists(lFixExe) then
        aParams.fFixInsightExe := lFixExe
      else
        aDiagnostics.AddWarning(Format(SFixInsightPathInvalid, [aFixOptions.fExePath]));
    end;

    if (aParams.fFixInsightExe = '') and (not TryResolveFixInsightExe(aDiagnostics, aParams.fFixInsightExe)) then
      aDiagnostics.AddWarning(SFixInsightNotFound);

    Result := True;
  finally
    lRsVarsEnvVars.Free;
    lEnvVars.Free;
  end;
end;

function BuildOutputRoot(const aBaseOut: string; const aProjectPath: string; const aProjectName: string): string;
var
  lProjectDir: string;
  lOut: string;
begin
  if aBaseOut <> '' then
  begin
    lOut := aBaseOut;
    if not TPath.IsPathRooted(lOut) then
      lOut := TPath.GetFullPath(lOut);
    Exit(lOut);
  end;

  lProjectDir := TPath.GetDirectoryName(TPath.GetFullPath(aProjectPath));
  Result := DakProjectRoot(lProjectDir, aProjectName);
end;

function BuildUnitOutputRoot(const aBaseOut: string; const aUnitPath: string; const aUnitName: string): string;
var
  lUnitDir: string;
  lOut: string;
begin
  if aBaseOut <> '' then
  begin
    lOut := aBaseOut;
    if not TPath.IsPathRooted(lOut) then
      lOut := TPath.GetFullPath(lOut);
    Exit(lOut);
  end;

  lUnitDir := TPath.GetDirectoryName(TPath.GetFullPath(aUnitPath));
  Result := DakProjectPath(DakProjectRoot(lUnitDir, '_unit'), [aUnitName]);
end;

function TryRunFixInsightLogged(const aParams: TFixInsightParams; const aStdOutLogPath: string;
  const aStdErrLogPath: string; const aRunLogPath: string; out aExitCode: Cardinal; out aError: string): Boolean;
var
  lExe: string;
  lCmdLine: string;
  lStdErrHandle: THandle;
  lStdOutHandle: THandle;
  lLogError: string;
  lWorkDir: string;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not BuildFixInsightCommandLine(aParams, lExe, lCmdLine, aError) then
    Exit(False);

  lWorkDir := GetCurrentDir;
  AppendAnalyzeRunLogIndex(aRunLogPath, lWorkDir, lCmdLine, aStdOutLogPath, aStdErrLogPath, aParams.fFixOutput);

  if not TryOpenLogHandle(aStdOutLogPath, lStdOutHandle, lLogError) then
  begin
    aError := lLogError;
    Exit(False);
  end;
  try
    if not TryOpenLogHandle(aStdErrLogPath, lStdErrHandle, lLogError) then
    begin
      aError := lLogError;
      Exit(False);
    end;
    try
      Result := TryRunFixInsightWithHandles(aParams, lStdOutHandle, lStdErrHandle, aExitCode, aError);
    finally
      CloseHandle(lStdErrHandle);
    end;
  finally
    CloseHandle(lStdOutHandle);
  end;
end;

function TryRunPalLogged(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  const aStdOutLogPath: string; const aStdErrLogPath: string; const aRunLogPath: string; out aExitCode: Cardinal;
  out aError: string): Boolean;
var
  lExe: string;
  lCmdLine: string;
  lStdErrHandle: THandle;
  lStdOutHandle: THandle;
  lLogError: string;
  lWorkDir: string;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not BuildPalCmdCommandLine(aParams, aPa, lExe, lCmdLine, aError) then
    Exit(False);

  lWorkDir := GetCurrentDir;
  AppendAnalyzeRunLogIndex(aRunLogPath, lWorkDir, lCmdLine, aStdOutLogPath, aStdErrLogPath, aPa.fOutput);

  if not TryOpenLogHandle(aStdOutLogPath, lStdOutHandle, lLogError) then
  begin
    aError := lLogError;
    Exit(False);
  end;
  try
    if not TryOpenLogHandle(aStdErrLogPath, lStdErrHandle, lLogError) then
    begin
      aError := lLogError;
      Exit(False);
    end;
    try
      Result := TryRunPascalAnalyzerWithHandles(aParams, aPa, lStdOutHandle, lStdErrHandle, aExitCode, aError);
    finally
      CloseHandle(lStdErrHandle);
    end;
  finally
    CloseHandle(lStdOutHandle);
  end;
end;

function TryRunPalUnitLogged(const aUnitPath: string; const aPa: TPascalAnalyzerDefaults;
  const aStdOutLogPath: string; const aStdErrLogPath: string; const aRunLogPath: string; out aExitCode: Cardinal;
  out aError: string): Boolean;
var
  lExe: string;
  lCmdLine: string;
  lStdErrHandle: THandle;
  lStdOutHandle: THandle;
  lLogError: string;
  lWorkDir: string;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not BuildPalCmdUnitCommandLine(aUnitPath, aPa, lExe, lCmdLine, aError) then
    Exit(False);

  lWorkDir := GetCurrentDir;
  AppendAnalyzeRunLogIndex(aRunLogPath, lWorkDir, lCmdLine, aStdOutLogPath, aStdErrLogPath, aPa.fOutput);

  if not TryOpenLogHandle(aStdOutLogPath, lStdOutHandle, lLogError) then
  begin
    aError := lLogError;
    Exit(False);
  end;
  try
    if not TryOpenLogHandle(aStdErrLogPath, lStdErrHandle, lLogError) then
    begin
      aError := lLogError;
      Exit(False);
    end;
    try
      Result := TryRunPascalAnalyzerUnit(aUnitPath, aPa, lStdOutHandle, lStdErrHandle, aExitCode, aError);
    finally
      CloseHandle(lStdErrHandle);
    end;
  finally
    CloseHandle(lStdOutHandle);
  end;
end;

procedure CaptureFixInsightSummary(const aTxtPath: string; out aCounts: TFixInsightCounts);
var
  lCounts: TDictionary<string, Integer>;
begin
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

    if aFixTxtRan and FileExists(aFixTxtPath) then
      lLines.AppendLine('- Findings (by code): ' + aFixCounts.Total.ToString)
    else
      lLines.AppendLine('- Findings (by code): (TXT not generated)');

    if aFixTxtRan and (Length(aFixCounts.Top) > 0) then
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
      lLines.AppendLine(Format('- Totals: warnings=%d, strong_warnings=%d, optimizations=%d, total=%d', [
        aPal.Warnings, aPal.StrongWarnings, aPal.Optimizations,
        aPal.Warnings + aPal.StrongWarnings + aPal.Optimizations]));
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
    if aPal.Context <> '' then
      lLines.AppendLine('- Context: ' + aPal.Context);
    if aPal.Ran and (aPal.ExitCode = 0) then
      lLines.AppendLine(Format('- Totals: warnings=%d, strong_warnings=%d, optimizations=%d, total=%d', [
        aPal.Warnings, aPal.StrongWarnings, aPal.Optimizations,
        aPal.Warnings + aPal.StrongWarnings + aPal.Optimizations]))
    else if not aPal.Ran then
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
    lLines.Free;
  end;
end;

procedure WriteUnitStatusSeed(const aOutRoot: string; const aUnitPath: string; const aProjectContext: string;
  const aParams: TFixInsightParams; const aSettings: TDakSettings;
  const aPascalAnalyzer: TPascalAnalyzerDefaults; const aPal: TPalSummary; const aDurationMs: Int64;
  const aExitCode: Integer; const aRequested: Boolean; const aErrors: TArray<string>);
var
  lAnalyzer: TJSONObject;
  lComplete: Boolean;
  lConfigFiles: TJSONArray;
  lCounts: TJSONObject;
  lError: string;
  lErrors: TJSONArray;
  lInputs: TJSONObject;
  lOptionsInput: string;
  lQuality: string;
  lPolicy: TJSONObject;
  lPolicyOrigins: TJSONObject;
  lPolicySources: TJSONArray;
  lPolicyValues: TJSONObject;
  lRoot: TJSONObject;
  lRuns: TJSONArray;
  lSettingsPath: string;

  function HashArray(const aValues: TArray<string>): string;
  begin
    Result := LowerCase(THashSHA2.GetHashString(String.Join(#10, aValues)));
  end;

  function HashFile(const aPath: string): string;
  begin
    if (aPath = '') or (not FileExists(aPath)) then
      Exit('');
    Result := LowerCase(THashSHA2.GetHashStringFromFile(aPath));
  end;

  function StringListJson(const aValues: string): TJSONArray;
  var
    lValue: string;
  begin
    Result := TJSONArray.Create;
    for lValue in aValues.Split([';']) do
      if Trim(lValue) <> '' then
        Result.AddElement(TJSONString.Create(Trim(lValue)));
  end;

begin
  lComplete := (not aRequested) or
    (aPal.Ran and (aPal.ExitCode = 0) and (aPal.ReportRoot <> '') and (Length(aErrors) = 0));
  if not aRequested then
    lQuality := 'complete'
  else if lComplete then
    lQuality := 'complete'
  else
    lQuality := 'unavailable';

  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('schema_version', TJSONNumber.Create(2));
    lRoot.AddPair('status', TJSONObject.Create
      .AddPair('infrastructure', IfThen(aExitCode = 0, 'complete', 'failed'))
      .AddPair('policy', 'not_evaluated'));
    lRoot.AddPair('subject', TJSONObject.Create
      .AddPair('kind', 'unit')
      .AddPair('path', aUnitPath)
      .AddPair('project_context', aProjectContext));
    lRoot.AddPair('workspace', TJSONObject.Create
      .AddPair('selector', aSettings.fWorkspace.fSelector)
      .AddPair('root', aSettings.fWorkspace.fRoot)
      .AddPair('vcs', aSettings.fWorkspace.fVcs)
      .AddPair('source', aSettings.fWorkspace.fSource));
    lRoot.AddPair('compiler', TJSONObject.Create
      .AddPair('delphi', aParams.fDelphiVersion)
      .AddPair('platform', aParams.fPlatform)
      .AddPair('config', aParams.fConfig)
      .AddPair('search_path_sha256',
        LowerCase(THashSHA2.GetHashString(String.Join(#10, aParams.fUnitSearchPath)))));

    lAnalyzer := TJSONObject.Create
      .AddPair('requested', TJSONBool.Create(aRequested))
      .AddPair('status', IfThen(not aRequested, 'not_requested', IfThen(lComplete, 'complete', 'failed')))
      .AddPair('executable', aPascalAnalyzer.fPath)
      .AddPair('version', aPal.Version)
      .AddPair('count_quality', lQuality);
    lOptionsInput := String.Join('|', [aPascalAnalyzer.fArgs, aPascalAnalyzer.fExcludeSearchFolders,
      aPascalAnalyzer.fExcludeFiles, aPascalAnalyzer.fTimeoutSec.ToString,
      HashArray(aParams.fDefines), HashArray(aParams.fUnitSearchPath)]);
    lAnalyzer.AddPair('options', TJSONObject.Create
      .AddPair('exclude_search_folders', aPascalAnalyzer.fExcludeSearchFolders)
      .AddPair('exclude_files', aPascalAnalyzer.fExcludeFiles)
      .AddPair('sha256', LowerCase(THashSHA2.GetHashString(lOptionsInput))));
    lRuns := TJSONArray.Create;
    if aPal.Ran then
      lRuns.AddElement(TJSONObject.Create
        .AddPair('exit_code', TJSONNumber.Create(aPal.ExitCode))
        .AddPair('duration_ms', TJSONNumber.Create(aDurationMs))
        .AddPair('parse_status', IfThen(lComplete, 'complete', 'unavailable'))
        .AddPair('artifacts', TJSONObject.Create
          .AddPair('stdout', 'pascal-analyzer/pascal-analyzer.stdout.log')
          .AddPair('stderr', 'pascal-analyzer/pascal-analyzer.stderr.log')
          .AddPair('log', 'pascal-analyzer/pascal-analyzer.log')));
    lAnalyzer.AddPair('runs', lRuns);
    lRoot.AddPair('analyzers', TJSONObject.Create.AddPair('pascal_analyzer', lAnalyzer));

    lCounts := TJSONObject.Create.AddPair('quality', lQuality);
    if lQuality <> 'unavailable' then
    begin
      lCounts.AddPair('warnings', TJSONNumber.Create(aPal.Warnings));
      lCounts.AddPair('strong_warnings', TJSONNumber.Create(aPal.StrongWarnings));
      lCounts.AddPair('optimizations', TJSONNumber.Create(aPal.Optimizations));
      lCounts.AddPair('total', TJSONNumber.Create(aPal.Warnings + aPal.StrongWarnings + aPal.Optimizations));
    end;
    lRoot.AddPair('counts', TJSONObject.Create.AddPair('pascal_analyzer', lCounts));

    lConfigFiles := TJSONArray.Create;
    for lSettingsPath in aSettings.fLoadedPaths do
      lConfigFiles.AddElement(TJSONObject.Create
        .AddPair('path', lSettingsPath)
        .AddPair('sha256', HashFile(lSettingsPath)));
    lInputs := TJSONObject.Create
      .AddPair('unit_sha256', HashFile(aUnitPath))
      .AddPair('project_sha256', HashFile(aProjectContext))
      .AddPair('config_manifests', lConfigFiles);
    lRoot.AddPair('inputs', lInputs);
    lPolicyValues := TJSONObject.Create
      .AddPair('gate_ownership', StringListJson(aSettings.fAnalysisPolicy.fGateOwnership))
      .AddPair('gate_metrics', StringListJson(aSettings.fAnalysisPolicy.fGateMetrics))
      .AddPair('fixinsight_ignore', StringListJson(aSettings.fFixInsightIgnore.fWarnings))
      .AddPair('pal_ignore_rules', StringListJson(aSettings.fPascalAnalyzerIgnore.fRules))
      .AddPair('project_roots', StringListJson(aSettings.fAnalysisPolicy.fProjectRoots))
      .AddPair('third_party_roots', StringListJson(aSettings.fAnalysisPolicy.fThirdPartyRoots))
      .AddPair('exclude_path_masks', StringListJson(aSettings.fReportFilter.fExcludePathMasks));
    lPolicySources := TJSONArray.Create;
    for lSettingsPath in aSettings.fAnalysisPolicy.fSources do
      lPolicySources.AddElement(TJSONString.Create(lSettingsPath));
    lPolicyOrigins := TJSONObject.Create
      .AddPair('pal_ignore_rules',
        StringListJson(aSettings.fPascalAnalyzerIgnore.fSources));
    lPolicy := TJSONObject.Create
      .AddPair('resolver', 'Dak.Settings')
      .AddPair('values', lPolicyValues)
      .AddPair('sources', lPolicySources)
      .AddPair('origins', lPolicyOrigins)
      .AddPair('sha256', aSettings.fAnalysisPolicy.fSha256)
      .AddPair('reporting_sha256', LowerCase(THashSHA2.GetHashString(
        'GateMetrics=' + aSettings.fAnalysisPolicy.fGateMetrics + #10 +
        'FixInsightIgnore=' + aSettings.fFixInsightIgnore.fWarnings + #10 +
        'PascalAnalyzerIgnore=' + aSettings.fPascalAnalyzerIgnore.fRules + #10 +
        'ExcludePathMasks=' + aSettings.fReportFilter.fExcludePathMasks)));
    lRoot.AddPair('policy', lPolicy);
    lErrors := TJSONArray.Create;
    for lError in aErrors do
      lErrors.AddElement(TJSONString.Create(lError));
    lRoot.AddPair('errors', lErrors);
    lRoot.AddPair('artifacts', TJSONObject.Create
      .AddPair('summary_markdown', 'summary.md')
      .AddPair('run_log', 'run.log'));
    WriteLogText(TPath.Combine(aOutRoot, 'summary.json'), lRoot.Format(2));
  finally
    lRoot.Free;
  end;
end;
end.
