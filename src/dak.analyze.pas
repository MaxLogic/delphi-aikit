unit Dak.Analyze;

interface

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.SysUtils,
  System.Variants,
  Xml.omnixmldom, Xml.XMLDoc, Xml.XMLIntf,
  Winapi.Windows,
  maxLogic.IOUtils, maxLogic.StrUtils,
  Dak.Diagnostics, Dak.FixInsight, Dak.FixInsightRunner, Dak.FixInsightSettings, Dak.Messages,
  Dak.PascalAnalyzerRunner, Dak.Project, Dak.Registry, Dak.ReportPostProcess, Dak.RsVars, Dak.Types;

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

  lOptions := aOptions;
  lInputPath := aOptions.fDprojPath;
  if not TryResolveDprojPath(lInputPath, lDprojPath, lError) then
  begin
    aError := lError;
    aErrorCode := 3;
    Exit(False);
  end;

  if not LoadSettings(aDiagnostics, lDprojPath, aFixOptions, aFixIgnoreDefaults, aReportFilter, aPascalAnalyzer) then
  begin
    aError := 'Failed to read dak.ini.';
    aErrorCode := 6;
    Exit(False);
  end;
  ApplySettingsOverrides(aOptions, aFixOptions, aFixIgnoreDefaults, aReportFilter, aPascalAnalyzer);

  lOptions.fDprojPath := lDprojPath;
  aProjectName := TPath.GetFileNameWithoutExtension(lDprojPath);

  if not TryLoadRsVars(lOptions.fDelphiVersion, lOptions.fRsVarsPath, aDiagnostics, lError) then
  begin
    aError := lError;
    aErrorCode := 4;
    Exit(False);
  end;

  if not TryReadIdeConfig(lOptions.fDelphiVersion, lOptions.fPlatform, lOptions.fEnvOptionsPath, lEnvVars, lLibraryPath,
    lLibrarySource, aDiagnostics, lError) then
  begin
    lEnvVars.Free;
    aError := lError;
    aErrorCode := 4;
    Exit(False);
  end;
  try
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
    fPascalAnalyzer, fProjectName, lError, lErrorCode) then
  begin
    WriteLn(ErrOutput, lError);
    fExitCode := lErrorCode;
    Exit(False);
  end;
  Result := True;
end;

procedure TAnalyzeProjectRunner.PrepareOutputTree;
begin
  fOutRoot := BuildOutputRoot(fOptions.fAnalyzeOutPath, fProjectName);
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
  fOutRoot := BuildUnitOutputRoot(fOptions.fAnalyzeOutPath, fUnitName);
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
