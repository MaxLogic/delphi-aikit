unit Dak.PascalAnalyzerRunner;

interface

uses
  System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.JSON, System.StrUtils,
  System.SysUtils, System.Types, System.Variants,
  Xml.omnixmldom, Xml.XMLDoc, Xml.XMLIntf, Xml.xmldom,
  Winapi.Windows,
  maxLogic.StrUtils,
  Dak.Types;

function TryResolvePalCmdExe(const aOverridePath: string; out aExePath: string; out aError: string): Boolean;
function BuildPalCmdCommandLine(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  out aExePath: string; out aCmdLine: string; out aError: string): Boolean;
function TryRunPascalAnalyzer(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  out aExitCode: Cardinal; out aError: string): Boolean;
function TryRunPascalAnalyzerWithHandles(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  aStdOut: THandle; aStdErr: THandle; out aExitCode: Cardinal; out aError: string): Boolean;
function BuildPalCmdUnitCommandLine(const aUnitPath: string; const aPa: TPascalAnalyzerDefaults;
  out aExePath: string; out aCmdLine: string; out aError: string): Boolean;
function TryRunPascalAnalyzerUnit(const aUnitPath: string; const aPa: TPascalAnalyzerDefaults;
  aStdOut: THandle; aStdErr: THandle; out aExitCode: Cardinal; out aError: string): Boolean;
function TryFindPalReportRoot(const aOutputRoot: string; out aReportRoot: string; out aError: string): Boolean;
function TryGeneratePalArtifacts(const aReportRoot: string; const aOutRoot: string; out aError: string): Boolean;

implementation

const
  SPalCmdExeName = 'palcmd.exe';
  SPalCmd32ExeName = 'palcmd32.exe';
  SPalCmdMapFileName = 'palcmd-map.json';
  SPalFindingsFileName = 'pal-findings.md';
  SPalFindingsJsonlFileName = 'pal-findings.jsonl';
  SPalHotspotsFileName = 'pal-hotspots.md';
  SPalWarningsFileName = 'Warnings.xml';
  SPalStrongWarningsFileName = 'Strong Warnings.xml';
  SPalOptimizationFileName = 'Optimization.xml';
  SPalExceptionFileName = 'Exception.xml';
  SPalComplexityFileName = 'Complexity.xml';
  SPalModuleTotalsFileName = 'Module Totals.xml';
  SPalStatusFileName = 'Status.xml';

function QuoteArg(const aValue: string): string;
var
  lNeedsQuotes: Boolean;
  lCh: Char;
  lBsCount: Integer;
  lBuilder: TStringBuilder;
begin
  lNeedsQuotes := (aValue = '') or (Pos(' ', aValue) > 0) or (Pos(#9, aValue) > 0) or (Pos('"', aValue) > 0);
  if not lNeedsQuotes then
    Exit(aValue);

  lBuilder := TStringBuilder.Create;
  try
    lBuilder.Append('"');
    lBsCount := 0;
    for lCh in aValue do
    begin
      if lCh = '\' then
      begin
        Inc(lBsCount);
        Continue;
      end;

      if lCh = '"' then
      begin
        lBuilder.Append(StringOfChar('\', (lBsCount * 2) + 1));
        lBuilder.Append('"');
        lBsCount := 0;
        Continue;
      end;

      if lBsCount > 0 then
      begin
        lBuilder.Append(StringOfChar('\', lBsCount));
        lBsCount := 0;
      end;
      lBuilder.Append(lCh);
    end;

    if lBsCount > 0 then
      lBuilder.Append(StringOfChar('\', lBsCount * 2));
    lBuilder.Append('"');
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
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

type
  TPalCmdMap = record
    DelphiOrder: TArray<string>;
    BdsToDelphi: TDictionary<Integer, string>;
    PalCmdMax: TDictionary<Integer, string>;
    DelphiWin32: TDictionary<string, string>;
    DelphiWin64: TDictionary<string, string>;
  end;

procedure InitPalCmdMap(out aMap: TPalCmdMap);
begin
  aMap.DelphiOrder := nil;
  aMap.BdsToDelphi := TDictionary<Integer, string>.Create;
  aMap.PalCmdMax := TDictionary<Integer, string>.Create;
  aMap.DelphiWin32 := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  aMap.DelphiWin64 := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
end;

procedure FreePalCmdMap(var aMap: TPalCmdMap);
begin
  aMap.BdsToDelphi.Free;
  aMap.PalCmdMax.Free;
  aMap.DelphiWin32.Free;
  aMap.DelphiWin64.Free;
  aMap.DelphiOrder := nil;
end;

function PalCmdMapPath: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), SPalCmdMapFileName);
end;

function JsonGetString(const aObj: TJSONObject; const aName: string; const aDefault: string): string;
var
  lValue: TJSONValue;
begin
  lValue := aObj.GetValue(aName);
  if lValue = nil then
    Exit(aDefault);
  Result := lValue.Value;
end;

function JsonGetInteger(const aObj: TJSONObject; const aName: string; const aDefault: Integer): Integer;
var
  lValue: TJSONValue;
begin
  lValue := aObj.GetValue(aName);
  if lValue = nil then
    Exit(aDefault);
  Result := StrToIntDef(lValue.Value, aDefault);
end;

function TryGetJsonArray(const aObj: TJSONObject; const aName: string; out aArr: TJSONArray): Boolean;
var
  lValue: TJSONValue;
begin
  aArr := nil;
  lValue := aObj.GetValue(aName);
  Result := (lValue <> nil) and (lValue is TJSONArray);
  if Result then
    aArr := lValue as TJSONArray;
end;

function TryLoadPalCmdMap(out aMap: TPalCmdMap; out aError: string): Boolean;
var
  lPath: string;
  lText: string;
  lJson: TJSONObject;
  lArr: TJSONArray;
  lItem: TJSONValue;
  lObj: TJSONObject;
  lKey: Integer;
  lValue: string;
  i: Integer;
begin
  Result := False;
  aError := '';
  InitPalCmdMap(aMap);
  try
    lPath := PalCmdMapPath;
    if not FileExists(lPath) then
    begin
      aError := 'PALCMD mapping file not found: ' + lPath;
      Exit(False);
    end;

    lText := TFile.ReadAllText(lPath, TEncoding.UTF8);
    lJson := TJSONObject.ParseJSONValue(lText) as TJSONObject;
    if lJson = nil then
    begin
      aError := 'PALCMD mapping file is not valid JSON: ' + lPath;
      Exit(False);
    end;
    try
      if not TryGetJsonArray(lJson, 'delphiOrder', lArr) then
      begin
        aError := 'PALCMD mapping file is missing delphiOrder: ' + lPath;
        Exit(False);
      end;
      SetLength(aMap.DelphiOrder, lArr.Count);
      for i := 0 to lArr.Count - 1 do
        aMap.DelphiOrder[i] := lArr.Items[i].Value;

      if not TryGetJsonArray(lJson, 'bdsToDelphi', lArr) then
      begin
        aError := 'PALCMD mapping file is missing bdsToDelphi: ' + lPath;
        Exit(False);
      end;
      for lItem in lArr do
        if lItem is TJSONObject then
        begin
          lObj := TJSONObject(lItem);
          lKey := JsonGetInteger(lObj, 'bdsMajor', -1);
          lValue := JsonGetString(lObj, 'delphi', '');
          if (lKey >= 0) and (lValue <> '') then
            aMap.BdsToDelphi.AddOrSetValue(lKey, lValue);
        end;

      if not TryGetJsonArray(lJson, 'palcmdSupport', lArr) then
      begin
        aError := 'PALCMD mapping file is missing palcmdSupport: ' + lPath;
        Exit(False);
      end;
      for lItem in lArr do
        if lItem is TJSONObject then
        begin
          lObj := TJSONObject(lItem);
          lKey := JsonGetInteger(lObj, 'palcmdMajor', -1);
          lValue := JsonGetString(lObj, 'maxDelphi', '');
          if (lKey >= 0) and (lValue <> '') then
            aMap.PalCmdMax.AddOrSetValue(lKey, lValue);
        end;

      if not TryGetJsonArray(lJson, 'delphiFlags', lArr) then
      begin
        aError := 'PALCMD mapping file is missing delphiFlags: ' + lPath;
        Exit(False);
      end;
      for lItem in lArr do
        if lItem is TJSONObject then
        begin
          lObj := TJSONObject(lItem);
          lValue := JsonGetString(lObj, 'delphi', '');
          if lValue = '' then
            Continue;
          if lObj.GetValue('win32') <> nil then
            aMap.DelphiWin32.AddOrSetValue(lValue, JsonGetString(lObj, 'win32', ''));
          if lObj.GetValue('win64') <> nil then
            aMap.DelphiWin64.AddOrSetValue(lValue, JsonGetString(lObj, 'win64', ''));
        end;

      if (Length(aMap.DelphiOrder) = 0) or (aMap.BdsToDelphi.Count = 0) or (aMap.PalCmdMax.Count = 0) then
      begin
        aError := 'PALCMD mapping file is incomplete: ' + lPath;
        Exit(False);
      end;

      Result := True;
    finally
      lJson.Free;
    end;
  finally
    if not Result then
      FreePalCmdMap(aMap);
  end;
end;

function FindOrderIndex(const aOrder: TArray<string>; const aKey: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(aOrder) do
    if SameText(aOrder[i], aKey) then
      Exit(i);
  Result := -1;
end;

function TryGetPalCmdMaxDelphi(const aMap: TPalCmdMap; const aPalCmdMajor: Integer; out aMaxDelphi: string): Boolean;
var
  lBest: Integer;
  lKey: Integer;
begin
  aMaxDelphi := '';
  if aMap.PalCmdMax.TryGetValue(aPalCmdMajor, aMaxDelphi) then
    Exit(True);

  lBest := -1;
  for lKey in aMap.PalCmdMax.Keys do
    if (lKey <= aPalCmdMajor) and (lKey > lBest) then
    begin
      lBest := lKey;
      aMaxDelphi := aMap.PalCmdMax[lKey];
    end;
  Result := lBest >= 0;
end;

function TryCaptureProcessOutput(const aExe, aArgs: string; out aOutput: string; out aExitCode: Cardinal;
  out aError: string): Boolean;
var
  lSa: TSecurityAttributes;
  lRead: THandle;
  lWrite: THandle;
  lSi: TStartupInfo;
  lPi: TProcessInformation;
  lCmdLine: string;
  lBuffer: array[0..4095] of Byte;
  lBytesRead: Cardinal;
  lBuilder: TStringBuilder;
  lLastError: Cardinal;
  lAnsi: AnsiString;
begin
  Result := False;
  aOutput := '';
  aExitCode := 0;
  aError := '';
  lRead := 0;
  lWrite := 0;

  FillChar(lSa, SizeOf(lSa), 0);
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;

  if not CreatePipe(lRead, lWrite, @lSa, 0) then
  begin
    aError := 'Failed to create PALCMD output pipe.';
    Exit(False);
  end;
  try
    SetHandleInformation(lRead, HANDLE_FLAG_INHERIT, 0);

    FillChar(lSi, SizeOf(lSi), 0);
    lSi.cb := SizeOf(lSi);
    lSi.dwFlags := STARTF_USESTDHANDLES;
    lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    lSi.hStdOutput := lWrite;
    lSi.hStdError := lWrite;

    FillChar(lPi, SizeOf(lPi), 0);
    lCmdLine := QuoteArg(aExe);
    if aArgs <> '' then
      lCmdLine := lCmdLine + ' ' + aArgs;
    UniqueString(lCmdLine);

    if not CreateProcess(PChar(aExe), PChar(lCmdLine), nil, nil, True, 0, nil, nil, lSi, lPi) then
    begin
      lLastError := GetLastError;
      aError := 'PALCMD help failed to start: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;
    CloseHandle(lWrite);
    lWrite := 0;

    lBuilder := TStringBuilder.Create;
    try
      while ReadFile(lRead, lBuffer, SizeOf(lBuffer), lBytesRead, nil) do
      begin
        if lBytesRead = 0 then
          Break;
        SetString(lAnsi, PAnsiChar(@lBuffer[0]), lBytesRead);
        lBuilder.Append(string(lAnsi));
      end;
      aOutput := lBuilder.ToString;
    finally
      lBuilder.Free;
    end;

    WaitForSingleObject(lPi.hProcess, INFINITE);
    if not GetExitCodeProcess(lPi.hProcess, aExitCode) then
    begin
      lLastError := GetLastError;
      aError := 'PALCMD help failed: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;
    Result := True;
  finally
    if lRead <> 0 then
      CloseHandle(lRead);
    if lWrite <> 0 then
      CloseHandle(lWrite);
    if lPi.hThread <> 0 then
      CloseHandle(lPi.hThread);
    if lPi.hProcess <> 0 then
      CloseHandle(lPi.hProcess);
  end;
end;

function TryGetPalCmdHelpText(const aPalCmdExe: string; out aText: string; out aError: string): Boolean;
var
  lExit: Cardinal;
begin
  Result := TryCaptureProcessOutput(aPalCmdExe, '', aText, lExit, aError);
  if Result and (lExit <> 0) then
  begin
    if aText = '' then
    begin
      aError := 'PALCMD help exited with code ' + lExit.ToString + '.';
      Result := False;
    end;
  end;
end;

function ContainsFlag(const aText: string; const aFlag: string): Boolean;
var
  lText: string;
  lFlag: string;
  lPos: Integer;
  lBefore: Char;
  lAfter: Char;
begin
  if (aText = '') or (aFlag = '') then
    Exit(False);
  lText := UpperCase(aText);
  lFlag := UpperCase(aFlag);
  lPos := Pos(lFlag, lText);
  while lPos > 0 do
  begin
    if lPos = 1 then
      lBefore := #0
    else
      lBefore := lText[lPos - 1];
    if (lPos + Length(lFlag)) > Length(lText) then
      lAfter := #0
    else
      lAfter := lText[lPos + Length(lFlag)];
    if not (lBefore in ['A'..'Z', '0'..'9']) and not (lAfter in ['A'..'Z', '0'..'9']) then
      Exit(True);
    lPos := PosEx(lFlag, lText, lPos + 1);
  end;
  Result := False;
end;

function TryResolveFlagFromHelp(const aMap: TPalCmdMap; const aHelpText: string; const aPlatform: string;
  const aStartDelphi: string; out aFlag: string): Boolean;
var
  lIndex: Integer;
  i: Integer;
  lKey: string;
  lFlag: string;
  lIsWin32: Boolean;
begin
  aFlag := '';
  lIndex := FindOrderIndex(aMap.DelphiOrder, aStartDelphi);
  if lIndex < 0 then
    Exit(False);
  lIsWin32 := SameText(aPlatform, 'Win32');
  for i := lIndex downto 0 do
  begin
    lKey := aMap.DelphiOrder[i];
    if lIsWin32 then
    begin
      if not aMap.DelphiWin32.TryGetValue(lKey, lFlag) then
        Continue;
    end else
    begin
      if not aMap.DelphiWin64.TryGetValue(lKey, lFlag) then
        Continue;
    end;
    if ContainsFlag(aHelpText, lFlag) then
    begin
      aFlag := lFlag;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TryGetFileVersionMajor(const aPath: string; out aMajor: Integer): Boolean;
var
  lSize: Cardinal;
  lHandle: Cardinal;
  lData: TBytes;
  lFixed: PVSFixedFileInfo;
  lLen: Cardinal;
begin
  Result := False;
  aMajor := 0;
  lHandle := 0;
  lSize := GetFileVersionInfoSize(PChar(aPath), lHandle);
  if lSize = 0 then
    Exit(False);
  SetLength(lData, lSize);
  if not GetFileVersionInfo(PChar(aPath), lHandle, lSize, lData) then
    Exit(False);
  if not VerQueryValue(@lData[0], '\', Pointer(lFixed), lLen) then
    Exit(False);
  aMajor := HiWord(lFixed.dwFileVersionMS);
  Result := aMajor > 0;
end;

function NormalizeExePath(const aValue: string): string;
var
  lValue: string;
begin
  lValue := Trim(ExpandEnvVars(aValue));
  if lValue = '' then
    Exit('');
  if not TPath.IsPathRooted(lValue) then
    lValue := TPath.Combine(ExtractFilePath(ParamStr(0)), lValue);
  Result := lValue;
end;

function ChoosePalCmdExeInDir(const aDir: string): string;
var
  lExe: string;
begin
  Result := '';
  if aDir = '' then
    Exit('');

  lExe := TPath.Combine(aDir, SPalCmdExeName);
  if FileExists(lExe) then
    Exit(lExe);

  lExe := TPath.Combine(aDir, SPalCmd32ExeName);
  if FileExists(lExe) then
    Exit(lExe);
end;

function TryResolvePalCmdExeFromKnownRoots(out aExePath: string): Boolean;
const
  CMinVer = 5;
  CMaxVer = 15;
var
  lRoots: TList<string>;
  lRoot: string;
  lPeganza: string;
  n: Integer;
  lDir: string;
  lCandidate: string;
  lDirs: TStringDynArray;
  lBestVer: Integer;
  lBestPath: string;

  function Env(const aName: string): string;
  begin
    Result := GetEnvironmentVariable(aName);
  end;

  procedure AddRoot(const aValue: string);
  var
    lValue: string;
    lItem: string;
  begin
    lValue := Trim(aValue);
    if lValue = '' then
      Exit;
    for lItem in lRoots do
      if SameText(lItem, lValue) then
        Exit;
    lRoots.Add(lValue);
  end;

  function TryParseVer(const aFolderName: string; out aVer: Integer): Boolean;
  var
    lText: string;
    lPos: Integer;
  begin
    aVer := 0;
    lText := Trim(aFolderName);
    if not lText.StartsWith('Pascal Analyzer', True) then
      Exit(False);
    lPos := LastDelimiter('0123456789', lText);
    if lPos = 0 then
      Exit(False);
    while (lPos > 0) and CharInSet(lText[lPos], ['0'..'9']) do
      Dec(lPos);
    lText := Trim(Copy(lText, lPos + 1, MaxInt));
    Result := TryStrToInt(lText, aVer);
  end;

begin
  Result := False;
  aExePath := '';

  lRoots := TList<string>.Create;
  try
    AddRoot(Env('ProgramFiles'));
    AddRoot(Env('ProgramFiles(x86)'));
    AddRoot(Env('ProgramW6432'));
    if lRoots.Count = 0 then
    begin
      // WSL-launched Windows processes sometimes miss ProgramFiles env vars.
      lRoots.Add('C:\Program Files');
      lRoots.Add('C:\Program Files (x86)');
    end;

    // Known default (v9)
    for lRoot in lRoots do
    begin
      lCandidate := TPath.Combine(lRoot, 'Peganza\Pascal Analyzer 9\' + SPalCmdExeName);
      if FileExists(lCandidate) then
      begin
        aExePath := lCandidate;
        Exit(True);
      end;
      lCandidate := TPath.Combine(lRoot, 'Peganza\Pascal Analyzer 9\' + SPalCmd32ExeName);
      if FileExists(lCandidate) then
      begin
        aExePath := lCandidate;
        Exit(True);
      end;
    end;

    // Version sweep: prefer newest.
    for n := CMaxVer downto CMinVer do
    begin
      for lRoot in lRoots do
      begin
        lDir := TPath.Combine(lRoot, 'Peganza\Pascal Analyzer ' + n.ToString);
        lCandidate := ChoosePalCmdExeInDir(lDir);
        if lCandidate <> '' then
        begin
          aExePath := lCandidate;
          Exit(True);
        end;
      end;
    end;

    // Directory scan (depth-limited): ...\Peganza\Pascal Analyzer*\
    lBestVer := -1;
    lBestPath := '';
    for lRoot in lRoots do
    begin
      lPeganza := TPath.Combine(lRoot, 'Peganza');
      if not DirectoryExists(lPeganza) then
        Continue;
      lDirs := TDirectory.GetDirectories(lPeganza, 'Pascal Analyzer*', TSearchOption.soTopDirectoryOnly);
      for lDir in lDirs do
      begin
        lCandidate := ChoosePalCmdExeInDir(lDir);
        if lCandidate = '' then
          Continue;
        if TryParseVer(ExtractFileName(lDir), n) then
        begin
          if n > lBestVer then
          begin
            lBestVer := n;
            lBestPath := lCandidate;
          end;
        end else if (lBestPath = '') then
          lBestPath := lCandidate;
      end;
    end;

    if lBestPath <> '' then
    begin
      aExePath := lBestPath;
      Exit(True);
    end;
  finally
    lRoots.Free;
  end;
end;

function TryResolvePalCmdExe(const aOverridePath: string; out aExePath: string; out aError: string): Boolean;
var
  lValue: string;
begin
  Result := False;
  aError := '';
  aExePath := '';

  lValue := NormalizeExePath(aOverridePath);
  if lValue <> '' then
  begin
    if DirectoryExists(lValue) then
    begin
      aExePath := ChoosePalCmdExeInDir(lValue);
      if aExePath = '' then
      begin
        aError := 'PALCMD executable not found in folder: ' + lValue;
        Exit(False);
      end;
      Exit(True);
    end;

    if FileExists(lValue) then
    begin
      aExePath := lValue;
      Exit(True);
    end;

    aError := 'PALCMD executable not found at: ' + lValue;
    Exit(False);
  end;

  if TryResolvePalCmdExeFromKnownRoots(aExePath) then
    Exit(True);

  aError := 'PALCMD not found. Provide --pa-path or set [PascalAnalyzer].Path in dak.ini.';
end;

function TryBuildDelphiTargetFlag(const aBdsVersion: string; const aPlatform: string; const aPalCmdExe: string;
  out aFlag: string; out aError: string): Boolean;
var
  lMajor: Integer;
  lIsWin32: Boolean;
  lIsWin64: Boolean;
  lMap: TPalCmdMap;
  lDelphiKey: string;
  lMaxDelphi: string;
  lExpectedFlag: string;
  lResolvedFlag: string;
  lIndex: Integer;
  lMaxIndex: Integer;
  lPalCmdMajor: Integer;
  lHelpText: string;
  lHelpError: string;
begin
  aFlag := '';
  aError := '';

  lMajor := StrToIntDef(Copy(aBdsVersion, 1, Pos('.', aBdsVersion + '.') - 1), 0);
  lIsWin32 := SameText(aPlatform, 'Win32');
  lIsWin64 := SameText(aPlatform, 'Win64');
  if not (lIsWin32 or lIsWin64) then
    Exit(False);
  if lMajor = 0 then
  begin
    aError := 'Invalid Delphi version: ' + aBdsVersion;
    Exit(False);
  end;

  if not TryLoadPalCmdMap(lMap, aError) then
    Exit(False);
  try
    if not lMap.BdsToDelphi.TryGetValue(lMajor, lDelphiKey) then
    begin
      aError := 'PALCMD mapping missing for Delphi version: ' + aBdsVersion;
      Exit(False);
    end;

    if lIsWin32 then
    begin
      if not lMap.DelphiWin32.TryGetValue(lDelphiKey, lExpectedFlag) then
      begin
        aError := 'PALCMD mapping missing Win32 flag for Delphi version: ' + lDelphiKey;
        Exit(False);
      end;
    end else
    begin
      if not lMap.DelphiWin64.TryGetValue(lDelphiKey, lExpectedFlag) then
      begin
        aError := 'PALCMD mapping missing Win64 flag for Delphi version: ' + lDelphiKey;
        Exit(False);
      end;
    end;

    if not TryGetPalCmdHelpText(aPalCmdExe, lHelpText, lHelpError) then
    begin
      // Fall back to version mapping when PALCMD help is unavailable.
      if not TryGetFileVersionMajor(aPalCmdExe, lPalCmdMajor) then
      begin
        aError := 'Unable to read PALCMD version from: ' + aPalCmdExe;
        Exit(False);
      end;

      if not TryGetPalCmdMaxDelphi(lMap, lPalCmdMajor, lMaxDelphi) then
      begin
        aError := 'PALCMD version ' + lPalCmdMajor.ToString + ' not supported in mapping file.';
        Exit(False);
      end;

      lIndex := FindOrderIndex(lMap.DelphiOrder, lDelphiKey);
      lMaxIndex := FindOrderIndex(lMap.DelphiOrder, lMaxDelphi);
      if (lIndex < 0) or (lMaxIndex < 0) then
      begin
        aError := 'PALCMD mapping order is missing Delphi version keys.';
        Exit(False);
      end;

      if lIndex > lMaxIndex then
      begin
        aError := Format('PALCMD %d supports Delphi up to %s, but %s was requested. Install a newer Pascal Analyzer or ' +
          'pass /CD... via --pa-args to override.', [lPalCmdMajor, lMaxDelphi, lDelphiKey]);
        Exit(False);
      end;

      aFlag := lExpectedFlag;
      Exit(True);
    end;

    // PALCMD help is authoritative: use it to choose a supported /CD flag.
    if ContainsFlag(lHelpText, lExpectedFlag) then
    begin
      aFlag := lExpectedFlag;
      Exit(True);
    end;

    if TryResolveFlagFromHelp(lMap, lHelpText, aPlatform, lDelphiKey, lResolvedFlag) then
    begin
      aFlag := lResolvedFlag;
      Exit(True);
    end;

    aError := Format('PALCMD help did not list a supported compiler flag for Delphi %s %s. Install a newer Pascal Analyzer or ' +
      'pass /CD... via --pa-args to override.', [lDelphiKey, aPlatform]);
    Result := False;
  finally
    FreePalCmdMap(lMap);
  end;
end;

function CpuCount: Integer;
var
  lSys: TSystemInfo;
begin
  GetSystemInfo(lSys);
  Result := lSys.dwNumberOfProcessors;
  if Result < 1 then
    Result := 1;
end;

function FilterExistingPaths(const aPaths: TArray<string>): TArray<string>;
var
  lList: TList<string>;
  lSet: THashSet<string>;
  lItem: string;
begin
  lList := TList<string>.Create;
  try
    lSet := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
    try
      for lItem in aPaths do
      begin
        if (lItem = '') or (not DirectoryExists(lItem)) then
          Continue;
        if lSet.Add(lItem) then
          lList.Add(lItem);
      end;
      Result := lList.ToArray;
    finally
      lSet.Free;
    end;
  finally
    lList.Free;
  end;
end;

function JoinSemi(const aItems: TArray<string>): string;
begin
  Result := String.Join(';', aItems);
end;

function ConcatArrays(const aLeft: TArray<string>; const aRight: TArray<string>): TArray<string>;
var
  lList: TList<string>;
  lItem: string;
begin
  lList := TList<string>.Create;
  try
    for lItem in aLeft do
      lList.Add(lItem);
    for lItem in aRight do
      lList.Add(lItem);
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function BuildArgs(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults; const aExePath: string;
  out aCmdLine: string; out aError: string): Boolean;
var
  lArgs: TStringBuilder;
  lFlag: string;
  lThreads: Integer;
  lSearch: string;
  lFolders: TArray<string>;
begin
  Result := False;
  aCmdLine := '';
  aError := '';

  lArgs := TStringBuilder.Create;
  try
    // exe + input path
    lArgs.Append(QuoteArg(aExePath));
    lArgs.Append(' ');
    lArgs.Append(QuoteArg(aParams.fProjectDpr));

    if (aPa.fArgs = '') or (Pos('/CD', UpperCase(aPa.fArgs)) = 0) then
    begin
      if not TryBuildDelphiTargetFlag(aParams.fDelphiVersion, aParams.fPlatform, aExePath, lFlag, aError) then
      begin
        Exit(False);
      end;
      lArgs.Append(' ');
      lArgs.Append(lFlag);
    end;

    lArgs.Append(' ');
    lArgs.Append('/BUILD=');
    lArgs.Append(aParams.fConfig);

    if Length(aParams.fDefines) > 0 then
    begin
      lArgs.Append(' ');
      lArgs.Append('/D=');
      lArgs.Append(JoinSemi(aParams.fDefines));
    end;

    lFolders := FilterExistingPaths(ConcatArrays(aParams.fUnitSearchPath, aParams.fLibraryPath));
    lSearch := JoinSemi(lFolders);
    if lSearch <> '' then
    begin
      lArgs.Append(' ');
      lArgs.Append('/S=');
      lArgs.Append(QuoteArg(lSearch));
    end;

    if aPa.fOutput <> '' then
    begin
      lArgs.Append(' ');
      lArgs.Append('/R=');
      lArgs.Append(QuoteArg(TPath.GetFullPath(aPa.fOutput)));
    end;

    if aPa.fArgs = '' then
    begin
      // Sensible defaults.
      lArgs.Append(' /F=X');
      lArgs.Append(' /Q');
      lArgs.Append(' /A+');
      lArgs.Append(' /FA');
      lThreads := CpuCount;
      if lThreads > 64 then
        lThreads := 64;
      lArgs.Append(' /T=');
      lArgs.Append(lThreads.ToString);
    end else
    begin
      lArgs.Append(' ');
      lArgs.Append(aPa.fArgs);
    end;

    aCmdLine := lArgs.ToString;
    Result := True;
  finally
    lArgs.Free;
  end;
end;

function BuildPalCmdCommandLine(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  out aExePath: string; out aCmdLine: string; out aError: string): Boolean;
var
  lExe: string;
begin
  Result := False;
  aExePath := '';
  aCmdLine := '';
  aError := '';

  if not TryResolvePalCmdExe(aPa.fPath, lExe, aError) then
    Exit(False);
  if not BuildArgs(aParams, aPa, lExe, aCmdLine, aError) then
    Exit(False);

  aExePath := lExe;
  Result := True;
end;

function TryRunPascalAnalyzer(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  out aExitCode: Cardinal; out aError: string): Boolean;
begin
  Result := TryRunPascalAnalyzerWithHandles(aParams, aPa, GetStdHandle(STD_OUTPUT_HANDLE),
    GetStdHandle(STD_ERROR_HANDLE), aExitCode, aError);
end;

function TryRunPascalAnalyzerWithHandles(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  aStdOut: THandle; aStdErr: THandle; out aExitCode: Cardinal; out aError: string): Boolean;
var
  lExe: string;
  lCmdLine: string;
  lSi: TStartupInfo;
  lPi: TProcessInformation;
  lWait: Cardinal;
  lLastError: Cardinal;
  lStdOut: THandle;
  lStdErr: THandle;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not BuildPalCmdCommandLine(aParams, aPa, lExe, lCmdLine, aError) then
    Exit(False);
  UniqueString(lCmdLine);

  FillChar(lSi, SizeOf(lSi), 0);
  lSi.cb := SizeOf(lSi);
  lSi.dwFlags := STARTF_USESTDHANDLES;
  lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lStdOut := aStdOut;
  if lStdOut = 0 then
    lStdOut := GetStdHandle(STD_OUTPUT_HANDLE);
  lStdErr := aStdErr;
  if lStdErr = 0 then
    lStdErr := GetStdHandle(STD_ERROR_HANDLE);
  lSi.hStdOutput := lStdOut;
  lSi.hStdError := lStdErr;
  FillChar(lPi, SizeOf(lPi), 0);

  if not CreateProcess(PChar(lExe), PChar(lCmdLine), nil, nil, True, 0, nil, nil, lSi, lPi) then
  begin
    lLastError := GetLastError;
    aError := 'PALCMD failed to start: ' + SysErrorMessage(lLastError);
    Exit(False);
  end;
  try
    lWait := WaitForSingleObject(lPi.hProcess, INFINITE);
    if lWait <> WAIT_OBJECT_0 then
    begin
      lLastError := GetLastError;
      aError := 'PALCMD failed: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;
    if not GetExitCodeProcess(lPi.hProcess, aExitCode) then
    begin
      lLastError := GetLastError;
      aError := 'PALCMD failed: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;
  finally
    CloseHandle(lPi.hThread);
    CloseHandle(lPi.hProcess);
  end;

  Result := True;
end;

function BuildPalCmdUnitCommandLine(const aUnitPath: string; const aPa: TPascalAnalyzerDefaults;
  out aExePath: string; out aCmdLine: string; out aError: string): Boolean;
var
  lExe: string;
  lArgs: TStringBuilder;
  lThreads: Integer;
begin
  Result := False;
  aExePath := '';
  aCmdLine := '';
  aError := '';

  if aUnitPath = '' then
  begin
    aError := 'PALCMD unit path is empty.';
    Exit(False);
  end;
  if not TryResolvePalCmdExe(aPa.fPath, lExe, aError) then
    Exit(False);

  lArgs := TStringBuilder.Create;
  try
    lArgs.Append(QuoteArg(lExe));
    lArgs.Append(' ');
    lArgs.Append(QuoteArg(TPath.GetFullPath(aUnitPath)));
    if aPa.fOutput <> '' then
    begin
      lArgs.Append(' /R=');
      lArgs.Append(QuoteArg(TPath.GetFullPath(aPa.fOutput)));
    end;

    if aPa.fArgs = '' then
    begin
      lArgs.Append(' /F=X');
      lArgs.Append(' /Q');
      lArgs.Append(' /A+');
      lArgs.Append(' /FA');
      lThreads := CpuCount;
      if lThreads > 64 then
        lThreads := 64;
      lArgs.Append(' /T=');
      lArgs.Append(lThreads.ToString);
    end else
    begin
      lArgs.Append(' ');
      lArgs.Append(aPa.fArgs);
    end;

    aExePath := lExe;
    aCmdLine := lArgs.ToString;
    Result := True;
  finally
    lArgs.Free;
  end;
end;

function TryRunPascalAnalyzerUnit(const aUnitPath: string; const aPa: TPascalAnalyzerDefaults;
  aStdOut: THandle; aStdErr: THandle; out aExitCode: Cardinal; out aError: string): Boolean;
var
  lExe: string;
  lCmdLine: string;
  lSi: TStartupInfo;
  lPi: TProcessInformation;
  lWait: Cardinal;
  lLastError: Cardinal;
  lStdOut: THandle;
  lStdErr: THandle;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not BuildPalCmdUnitCommandLine(aUnitPath, aPa, lExe, lCmdLine, aError) then
    Exit(False);
  UniqueString(lCmdLine);

  FillChar(lSi, SizeOf(lSi), 0);
  lSi.cb := SizeOf(lSi);
  lSi.dwFlags := STARTF_USESTDHANDLES;
  lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lStdOut := aStdOut;
  if lStdOut = 0 then
    lStdOut := GetStdHandle(STD_OUTPUT_HANDLE);
  lStdErr := aStdErr;
  if lStdErr = 0 then
    lStdErr := GetStdHandle(STD_ERROR_HANDLE);
  lSi.hStdOutput := lStdOut;
  lSi.hStdError := lStdErr;
  FillChar(lPi, SizeOf(lPi), 0);

  if not CreateProcess(PChar(lExe), PChar(lCmdLine), nil, nil, True, 0, nil, nil, lSi, lPi) then
  begin
    lLastError := GetLastError;
    aError := 'PALCMD failed to start: ' + SysErrorMessage(lLastError);
    Exit(False);
  end;
  try
    lWait := WaitForSingleObject(lPi.hProcess, INFINITE);
    if lWait <> WAIT_OBJECT_0 then
    begin
      lLastError := GetLastError;
      aError := 'PALCMD failed: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;
    if not GetExitCodeProcess(lPi.hProcess, aExitCode) then
    begin
      lLastError := GetLastError;
      aError := 'PALCMD failed: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;
  finally
    CloseHandle(lPi.hThread);
    CloseHandle(lPi.hProcess);
  end;

  Result := True;
end;

type
  TPalFinding = record
    Severity: string;
    Report: string;
    Section: string;
    ModuleName: string;
    Line: Integer;
    Message: string;
    ItemId: string;
    ItemKind: string;
  end;

  TComplexityEntry = record
    Name: string;
    Dp: Integer;
    LinesOfCode: Integer;
    IsRoutine: Boolean;
  end;

  THotspotEntry = record
    Name: string;
    Score: Integer;
    LinesOfCode: Integer;
  end;

const
  SPalSeverityWarning = 'warning';
  SPalSeverityStrongWarning = 'strong-warning';
  SPalSeverityOptimization = 'optimization';
  SPalSeverityException = 'exception';
  CHotspotTopN = 20;

function NormalizeLineText(const aValue: string): string;
begin
  Result := aValue.Replace(#13, ' ', [rfReplaceAll]).Replace(#10, ' ', [rfReplaceAll]).Replace('|', '/', [rfReplaceAll]);
  Result := Trim(Result);
end;

function ChildText(const aNode: IXMLNode; const aName: string): string;
var
  lChild: IXMLNode;
begin
  Result := '';
  if aNode = nil then
    Exit;
  lChild := aNode.ChildNodes.FindNode(aName);
  if lChild = nil then
    Exit;
  Result := Trim(lChild.Text);
end;

function AttrText(const aNode: IXMLNode; const aName: string): string;
var
  lValue: Variant;
begin
  Result := '';
  if (aNode = nil) or (not aNode.HasAttribute(aName)) then
    Exit;
  lValue := aNode.Attributes[aName];
  Result := VarToStr(lValue);
end;

function TryParseLocMod(const aText: string; out aModule: string; out aLine: Integer): Boolean;
var
  lText: string;
  lPos: Integer;
  lLineText: string;
begin
  aModule := '';
  aLine := 0;
  lText := Trim(aText);
  if lText = '' then
    Exit(False);

  lPos := LastDelimiter('(', lText);
  if (lPos > 0) and lText.EndsWith(')') then
  begin
    lLineText := Trim(Copy(lText, lPos + 1, Length(lText) - lPos - 1));
    if TryStrToInt(lLineText, aLine) then
    begin
      aModule := Trim(Copy(lText, 1, lPos - 1));
      Exit(aModule <> '');
    end;
  end;

  aModule := lText;
  Result := aModule <> '';
end;

function ChooseMessage(const aItemId, aName, aKind: string): string;
begin
  if aItemId <> '' then
    Exit(aItemId);
  if aName <> '' then
    Exit(aName);
  Result := aKind;
end;

function BuildFindingKey(const aFinding: TPalFinding): string;
begin
  Result := UpperCase(aFinding.Severity + '|' + aFinding.Report + '|' + aFinding.Section + '|' +
    aFinding.ModuleName + '|' + aFinding.Line.ToString + '|' + aFinding.Message + '|' + aFinding.ItemId + '|' +
    aFinding.ItemKind);
end;

procedure AddFindingRecord(const aSeverity, aReport, aSection, aModule: string; const aLine: Integer;
  const aMessage, aItemId, aItemKind: string; aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lFinding: TPalFinding;
  lKey: string;
begin
  if aModule = '' then
    Exit;

  lFinding.Severity := NormalizeLineText(aSeverity);
  lFinding.Report := NormalizeLineText(aReport);
  lFinding.Section := NormalizeLineText(aSection);
  lFinding.ModuleName := NormalizeLineText(aModule);
  lFinding.Line := aLine;
  lFinding.Message := NormalizeLineText(aMessage);
  lFinding.ItemId := NormalizeLineText(aItemId);
  lFinding.ItemKind := NormalizeLineText(aItemKind);

  if lFinding.Message = '' then
    lFinding.Message := '-';

  lKey := BuildFindingKey(lFinding);
  if (lKey <> '') and aSeen.Add(lKey) then
    aFindings.Add(lFinding);
end;

procedure AddFindingFromLoc(const aSeverity, aReport, aSection, aName, aItemId, aItemKind: string; const aLoc: IXMLNode;
  aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lLocMod: string;
  lLocLine: string;
  lLocKind: string;
  lModule: string;
  lLine: Integer;
  lLineFromMod: Integer;
  lMessage: string;
  lKind: string;
begin
  lLocMod := NormalizeLineText(ChildText(aLoc, 'locmod'));
  lLocLine := NormalizeLineText(ChildText(aLoc, 'locline'));
  lLocKind := NormalizeLineText(ChildText(aLoc, 'kind'));
  lLine := StrToIntDef(lLocLine, 0);
  lModule := '';

  if lLocMod <> '' then
  begin
    lLineFromMod := 0;
    if TryParseLocMod(lLocMod, lModule, lLineFromMod) and (lLine = 0) then
      lLine := lLineFromMod;
  end;

  lMessage := ChooseMessage(aItemId, aName, aItemKind);
  if (lMessage = '') and (lLocKind <> '') then
    lMessage := lLocKind;

  lKind := aItemKind;
  if (lKind = '') and (lLocKind <> '') then
    lKind := lLocKind;

  AddFindingRecord(aSeverity, aReport, aSection, lModule, lLine, lMessage, aItemId, lKind, aFindings, aSeen);
end;

procedure AddFindingFromLocMod(const aSeverity, aReport, aSection, aName, aItemId, aItemKind, aLocMod: string;
  aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lModule: string;
  lLine: Integer;
  lMessage: string;
begin
  lModule := '';
  lLine := 0;
  if not TryParseLocMod(aLocMod, lModule, lLine) then
    Exit;
  lMessage := ChooseMessage(aItemId, aName, aItemKind);
  AddFindingRecord(aSeverity, aReport, aSection, lModule, lLine, lMessage, aItemId, aItemKind, aFindings, aSeen);
end;

procedure ParseItemNode(const aItem: IXMLNode; const aSeverity, aReport, aSection, aName: string;
  aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lItemId: string;
  lItemKind: string;
  lLocMod: string;
  lNode: IXMLNode;
  lHasLoc: Boolean;
  i: Integer;
begin
  lItemId := NormalizeLineText(ChildText(aItem, 'id'));
  lItemKind := NormalizeLineText(ChildText(aItem, 'kind'));
  lLocMod := NormalizeLineText(ChildText(aItem, 'locmod'));

  lHasLoc := False;
  for i := 0 to aItem.ChildNodes.Count - 1 do
  begin
    lNode := aItem.ChildNodes[i];
    if SameText(lNode.NodeName, 'loc') then
    begin
      lHasLoc := True;
      AddFindingFromLoc(aSeverity, aReport, aSection, aName, lItemId, lItemKind, lNode, aFindings, aSeen);
    end;
  end;

  if (not lHasLoc) and (lLocMod <> '') then
    AddFindingFromLocMod(aSeverity, aReport, aSection, aName, lItemId, lItemKind, lLocMod, aFindings, aSeen);
end;

procedure ParseSectionNode(const aSection: IXMLNode; const aSeverity, aReport: string;
  aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lSectionName: string;
  lCurrentName: string;
  lNode: IXMLNode;
  i: Integer;
begin
  lSectionName := NormalizeLineText(AttrText(aSection, 'name'));
  lCurrentName := '';

  for i := 0 to aSection.ChildNodes.Count - 1 do
  begin
    lNode := aSection.ChildNodes[i];
    if SameText(lNode.NodeName, 'name') then
      lCurrentName := NormalizeLineText(lNode.Text)
    else if SameText(lNode.NodeName, 'loc') then
      AddFindingFromLoc(aSeverity, aReport, lSectionName, lCurrentName, '', '', lNode, aFindings, aSeen)
    else if SameText(lNode.NodeName, 'item') then
      ParseItemNode(lNode, aSeverity, aReport, lSectionName, lCurrentName, aFindings, aSeen);
  end;
end;

function TryLoadXml(const aPath: string; out aDoc: IXMLDocument; out aError: string): Boolean;
begin
  Result := False;
  aError := '';
  aDoc := nil;
  if not FileExists(aPath) then
  begin
    aError := 'PAL XML not found: ' + aPath;
    Exit(False);
  end;
  try
    DefaultDOMVendor := sOmniXmlVendor;
    aDoc := TXMLDocument.Create(nil);
    aDoc.Options := [doNodeAutoIndent];
    aDoc.LoadFromFile(aPath);
    aDoc.Active := True;
    if (aDoc.DocumentElement = nil) then
    begin
      aError := 'PAL XML has no document element: ' + aPath;
      Exit(False);
    end;
    Result := True;
  except
    on E: Exception do
    begin
      aError := 'PAL XML load failed: ' + aPath + ' (' + E.Message + ')';
      aDoc := nil;
    end;
  end;
end;

procedure ParseFindingReport(const aPath, aReportName, aSeverity: string; aFindings: TList<TPalFinding>;
  aSeen: THashSet<string>; out aParsed: Boolean; out aError: string);
var
  lDoc: IXMLDocument;
  lRoot: IXMLNode;
  lNode: IXMLNode;
  i: Integer;
begin
  aParsed := False;
  aError := '';
  if not FileExists(aPath) then
    Exit;
  if not TryLoadXml(aPath, lDoc, aError) then
    Exit;
  lRoot := lDoc.DocumentElement;
  for i := 0 to lRoot.ChildNodes.Count - 1 do
  begin
    lNode := lRoot.ChildNodes[i];
    if SameText(lNode.NodeName, 'section') then
      ParseSectionNode(lNode, aSeverity, aReportName, aFindings, aSeen);
  end;
  aParsed := True;
end;

procedure CollectExceptionCalls(const aNode: IXMLNode; const aSeverity, aReport, aSection: string;
  aFindings: TList<TPalFinding>; aSeen: THashSet<string>);
var
  lName: string;
  lLocMod: string;
  lLocLine: string;
  lModule: string;
  lLine: Integer;
  lLineFromMod: Integer;
  lChild: IXMLNode;
  i: Integer;
begin
  if SameText(aNode.NodeName, 'called_by') then
  begin
    lName := NormalizeLineText(ChildText(aNode, 'name'));
    lLocMod := NormalizeLineText(ChildText(aNode, 'locmod'));
    lLocLine := NormalizeLineText(ChildText(aNode, 'locline'));
    lLine := StrToIntDef(lLocLine, 0);
    lModule := '';
    if lLocMod <> '' then
    begin
      lLineFromMod := 0;
      if TryParseLocMod(lLocMod, lModule, lLineFromMod) and (lLine = 0) then
        lLine := lLineFromMod;
    end;
    AddFindingRecord(aSeverity, aReport, aSection, lModule, lLine, lName, '', '', aFindings, aSeen);
  end;

  for i := 0 to aNode.ChildNodes.Count - 1 do
  begin
    lChild := aNode.ChildNodes[i];
    if SameText(lChild.NodeName, 'called_by') then
      CollectExceptionCalls(lChild, aSeverity, aReport, aSection, aFindings, aSeen)
    else if SameText(lChild.NodeName, 'branch') then
      CollectExceptionCalls(lChild, aSeverity, aReport, aSection, aFindings, aSeen)
    else if SameText(lChild.NodeName, 'section') then
      CollectExceptionCalls(lChild, aSeverity, aReport, aSection, aFindings, aSeen);
  end;
end;

procedure ParseExceptionReport(const aPath, aReportName, aSeverity: string; aFindings: TList<TPalFinding>;
  aSeen: THashSet<string>; out aParsed: Boolean; out aError: string);
var
  lDoc: IXMLDocument;
  lRoot: IXMLNode;
  lNode: IXMLNode;
  lSectionName: string;
  i: Integer;
begin
  aParsed := False;
  aError := '';
  if not FileExists(aPath) then
    Exit;
  if not TryLoadXml(aPath, lDoc, aError) then
    Exit;
  lRoot := lDoc.DocumentElement;
  for i := 0 to lRoot.ChildNodes.Count - 1 do
  begin
    lNode := lRoot.ChildNodes[i];
    if SameText(lNode.NodeName, 'section') then
    begin
      lSectionName := NormalizeLineText(AttrText(lNode, 'name'));
      CollectExceptionCalls(lNode, aSeverity, aReportName, lSectionName, aFindings, aSeen);
    end;
  end;
  aParsed := True;
end;

function SplitComplexityName(const aRaw: string; out aName: string; out aTag: string): Boolean;
var
  lPos: Integer;
  lTag: string;
  lChar: Char;
begin
  aName := Trim(aRaw);
  aTag := '';
  Result := False;
  if aName = '' then
    Exit(False);
  lPos := LastDelimiter('(', aName);
  if (lPos > 0) and aName.EndsWith(')') then
  begin
    lTag := Trim(Copy(aName, lPos + 1, Length(aName) - lPos - 1));
    if lTag <> '' then
    begin
      for lChar in lTag do
        if not CharInSet(lChar, ['A'..'Z', 'a'..'z']) then
          Exit(False);
      aTag := lTag;
      aName := Trim(Copy(aName, 1, lPos - 1));
      Result := True;
    end;
  end;
end;

function IsAggregateName(const aName: string): Boolean;
var
  lName: string;
begin
  lName := Trim(aName);
  if lName = '' then
    Exit(True);
  if SameText(lName, 'Overall') then
    Exit(True);
  if lName.StartsWith('\') then
    Exit(True);
  if Pos('\...\', lName) > 0 then
    Exit(True);
  Result := False;
end;

function TryLoadComplexityEntries(const aPath: string; out aEntries: TArray<TComplexityEntry>; out aError: string): Boolean;
var
  lDoc: IXMLDocument;
  lRoot: IXMLNode;
  lSection: IXMLNode;
  lNode: IXMLNode;
  lList: TList<TComplexityEntry>;
  lEntry: TComplexityEntry;
  lName: string;
  lTag: string;
  i: Integer;
begin
  Result := False;
  aError := '';
  aEntries := nil;
  if not FileExists(aPath) then
    Exit(False);
  if not TryLoadXml(aPath, lDoc, aError) then
    Exit(False);

  lRoot := lDoc.DocumentElement;
  lSection := nil;
  for i := 0 to lRoot.ChildNodes.Count - 1 do
  begin
    lNode := lRoot.ChildNodes[i];
    if SameText(lNode.NodeName, 'section') then
    begin
      if SameText(AttrText(lNode, 'name'), 'Complexity per module/subprogram') then
      begin
        lSection := lNode;
        Break;
      end;
    end;
  end;
  if lSection = nil then
  begin
    aError := 'Complexity report section not found: ' + aPath;
    Exit(False);
  end;

  lList := TList<TComplexityEntry>.Create;
  try
    for i := 0 to lSection.ChildNodes.Count - 1 do
    begin
      lNode := lSection.ChildNodes[i];
      if not SameText(lNode.NodeName, 'module_or_subprogram') then
        Continue;
      lName := NormalizeLineText(ChildText(lNode, 'name'));
      if lName = '' then
        Continue;
      lEntry := Default(TComplexityEntry);
      lEntry.Dp := StrToIntDef(ChildText(lNode, 'dp'), 0);
      lEntry.LinesOfCode := StrToIntDef(ChildText(lNode, 'lines_of_code'), 0);
      if SplitComplexityName(lName, lEntry.Name, lTag) then
        lEntry.IsRoutine := True
      else
      begin
        lEntry.Name := lName;
        lEntry.IsRoutine := False;
      end;
      lList.Add(lEntry);
    end;
    aEntries := lList.ToArray;
    Result := True;
  finally
    lList.Free;
  end;
end;

function TryLoadModuleLines(const aPath: string; out aLines: TDictionary<string, Integer>; out aError: string): Boolean;
var
  lDoc: IXMLDocument;
  lRoot: IXMLNode;
  lSection: IXMLNode;
  lModule: IXMLNode;
  lItem: IXMLNode;
  lName: string;
  lKind: string;
  lTotal: Integer;
  i: Integer;
  j: Integer;
begin
  Result := False;
  aError := '';
  aLines := nil;
  if not FileExists(aPath) then
    Exit(False);
  if not TryLoadXml(aPath, lDoc, aError) then
    Exit(False);

  lRoot := lDoc.DocumentElement;
  lSection := nil;
  for i := 0 to lRoot.ChildNodes.Count - 1 do
  begin
    lModule := lRoot.ChildNodes[i];
    if SameText(lModule.NodeName, 'section') then
    begin
      lSection := lModule;
      Break;
    end;
  end;
  if lSection = nil then
  begin
    aError := 'Module Totals report section not found: ' + aPath;
    Exit(False);
  end;

  aLines := TDictionary<string, Integer>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for i := 0 to lSection.ChildNodes.Count - 1 do
    begin
      lModule := lSection.ChildNodes[i];
      if not SameText(lModule.NodeName, 'module') then
        Continue;
      lName := NormalizeLineText(ChildText(lModule, 'name'));
      if lName = '' then
        Continue;
      if IsAggregateName(lName) then
        Continue;
      lTotal := 0;
      for j := 0 to lModule.ChildNodes.Count - 1 do
      begin
        lItem := lModule.ChildNodes[j];
        if not SameText(lItem.NodeName, 'item') then
          Continue;
        lKind := NormalizeLineText(ChildText(lItem, 'kind'));
        if SameText(lKind, 'lines') then
        begin
          lTotal := StrToIntDef(ChildText(lItem, 'total'), 0);
          Break;
        end;
      end;
      if lTotal > 0 then
        aLines.AddOrSetValue(lName, lTotal);
    end;
    Result := True;
  except
    on E: Exception do
    begin
      aError := 'Module Totals parse failed: ' + aPath + ' (' + E.Message + ')';
      aLines.Free;
      aLines := nil;
      Result := False;
    end;
  end;
end;

function CompareHotspot(const aLeft, aRight: THotspotEntry): Integer;
begin
  if aLeft.Score > aRight.Score then
    Exit(-1);
  if aLeft.Score < aRight.Score then
    Exit(1);
  Result := CompareText(aLeft.Name, aRight.Name);
end;

function TakeTopHotspots(const aItems: TArray<THotspotEntry>): TArray<THotspotEntry>;
var
  lCount: Integer;
begin
  lCount := Length(aItems);
  if lCount > CHotspotTopN then
    lCount := CHotspotTopN;
  Result := Copy(aItems, 0, lCount);
end;

procedure SortHotspots(var aItems: TArray<THotspotEntry>);
begin
  TArray.Sort<THotspotEntry>(aItems, TComparer<THotspotEntry>.Construct(CompareHotspot));
end;

function WritePalFindingsMd(const aFindings: TList<TPalFinding>; const aPath: string; out aError: string): Boolean;
var
  lBuilder: TStringBuilder;
  lFinding: TPalFinding;
  lUtf8: TUTF8Encoding;
begin
  Result := False;
  aError := '';
  lBuilder := TStringBuilder.Create;
  try
    for lFinding in aFindings do
    begin
      lBuilder.Append(lFinding.Severity);
      lBuilder.Append(' | ');
      lBuilder.Append(lFinding.Report);
      lBuilder.Append(' | ');
      lBuilder.Append(lFinding.Section);
      lBuilder.Append(' | ');
      lBuilder.Append(lFinding.ModuleName);
      lBuilder.Append(':');
      lBuilder.Append(lFinding.Line.ToString);
      lBuilder.Append(' | ');
      lBuilder.Append(lFinding.Message);
      lBuilder.AppendLine;
    end;
    lUtf8 := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(aPath, lBuilder.ToString, lUtf8);
    finally
      lUtf8.Free;
    end;
    Result := True;
  finally
    lBuilder.Free;
  end;
end;

function WritePalFindingsJsonl(const aFindings: TList<TPalFinding>; const aPath: string; out aError: string): Boolean;
var
  lBuilder: TStringBuilder;
  lFinding: TPalFinding;
  lJson: TJSONObject;
  lUtf8: TUTF8Encoding;
begin
  Result := False;
  aError := '';
  lBuilder := TStringBuilder.Create;
  try
    for lFinding in aFindings do
    begin
      lJson := TJSONObject.Create;
      try
        lJson.AddPair('severity', lFinding.Severity);
        lJson.AddPair('report', lFinding.Report);
        lJson.AddPair('section', lFinding.Section);
        lJson.AddPair('module', lFinding.ModuleName);
        lJson.AddPair('line', TJSONNumber.Create(lFinding.Line));
        lJson.AddPair('message', lFinding.Message);
        if lFinding.ItemId <> '' then
          lJson.AddPair('id', lFinding.ItemId);
        if lFinding.ItemKind <> '' then
          lJson.AddPair('kind', lFinding.ItemKind);
        lBuilder.Append(lJson.ToJSON);
      finally
        lJson.Free;
      end;
      lBuilder.AppendLine;
    end;
    lUtf8 := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(aPath, lBuilder.ToString, lUtf8);
    finally
      lUtf8.Free;
    end;
    Result := True;
  finally
    lBuilder.Free;
  end;
end;

function WritePalHotspotsMd(const aRoutineHotspots, aModuleHotspots, aModuleLineHotspots: TArray<THotspotEntry>;
  const aPath: string; out aError: string): Boolean;
var
  lBuilder: TStringBuilder;
  lItem: THotspotEntry;
  lUtf8: TUTF8Encoding;
begin
  Result := False;
  aError := '';
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine('# PAL Hotspots (top 20)');
    lBuilder.AppendLine;
    lBuilder.AppendLine('## Routines by decision points');
    if Length(aRoutineHotspots) = 0 then
      lBuilder.AppendLine('- none')
    else
      for lItem in aRoutineHotspots do
        lBuilder.AppendLine(Format('dp=%d | loc=%d | %s', [lItem.Score, lItem.LinesOfCode, lItem.Name]));

    lBuilder.AppendLine;
    lBuilder.AppendLine('## Modules by decision points');
    if Length(aModuleHotspots) = 0 then
      lBuilder.AppendLine('- none')
    else
      for lItem in aModuleHotspots do
        lBuilder.AppendLine(Format('dp=%d | loc=%d | %s', [lItem.Score, lItem.LinesOfCode, lItem.Name]));

    lBuilder.AppendLine;
    lBuilder.AppendLine('## Modules by lines');
    if Length(aModuleLineHotspots) = 0 then
      lBuilder.AppendLine('- none')
    else
      for lItem in aModuleLineHotspots do
        lBuilder.AppendLine(Format('lines=%d | %s', [lItem.Score, lItem.Name]));

    lUtf8 := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(aPath, lBuilder.ToString, lUtf8);
    finally
      lUtf8.Free;
    end;
    Result := True;
  finally
    lBuilder.Free;
  end;
end;

function TryFindPalReportRoot(const aOutputRoot: string; out aReportRoot: string; out aError: string): Boolean;
var
  lRoot: string;
  lFiles: TStringDynArray;
  lPath: string;
begin
  Result := False;
  aError := '';
  aReportRoot := '';

  lRoot := Trim(aOutputRoot);
  if lRoot = '' then
  begin
    aError := 'PAL output root is empty.';
    Exit(False);
  end;
  lRoot := TPath.GetFullPath(lRoot);
  if not DirectoryExists(lRoot) then
  begin
    aError := 'PAL output root not found: ' + lRoot;
    Exit(False);
  end;

  lPath := TPath.Combine(lRoot, SPalStatusFileName);
  if FileExists(lPath) then
  begin
    aReportRoot := ExcludeTrailingPathDelimiter(lRoot);
    Exit(True);
  end;

  lFiles := TDirectory.GetFiles(lRoot, SPalStatusFileName, TSearchOption.soAllDirectories);
  if Length(lFiles) = 0 then
  begin
    aError := 'PAL report root not found under: ' + lRoot;
    Exit(False);
  end;

  aReportRoot := ExcludeTrailingPathDelimiter(ExtractFilePath(lFiles[0]));
  Result := True;
end;

function TryGeneratePalArtifacts(const aReportRoot: string; const aOutRoot: string; out aError: string): Boolean;
var
  lReportRoot: string;
  lOutRoot: string;
  lFindings: TList<TPalFinding>;
  lSeen: THashSet<string>;
  lHasFindingsSource: Boolean;
  lHasHotspotSource: Boolean;
  lError: string;
  lWarningsPath: string;
  lStrongPath: string;
  lOptimizationPath: string;
  lExceptionPath: string;
  lComplexityPath: string;
  lModuleTotalsPath: string;
  lParsed: Boolean;
  lEntries: TArray<TComplexityEntry>;
  lModuleLines: TDictionary<string, Integer>;
  lRoutineList: TList<THotspotEntry>;
  lModuleList: TList<THotspotEntry>;
  lModuleLineList: TList<THotspotEntry>;
  lRoutineArr: TArray<THotspotEntry>;
  lModuleArr: TArray<THotspotEntry>;
  lModuleLineArr: TArray<THotspotEntry>;
  lEntry: TComplexityEntry;
  lHotspot: THotspotEntry;
  lName: string;
begin
  Result := False;
  aError := '';
  lReportRoot := Trim(aReportRoot);
  if lReportRoot = '' then
  begin
    aError := 'PAL report root is empty.';
    Exit(False);
  end;
  lReportRoot := TPath.GetFullPath(lReportRoot);
  if not DirectoryExists(lReportRoot) then
  begin
    aError := 'PAL report root not found: ' + lReportRoot;
    Exit(False);
  end;

  lOutRoot := Trim(aOutRoot);
  if lOutRoot = '' then
    lOutRoot := lReportRoot;
  lOutRoot := TPath.GetFullPath(lOutRoot);
  if not DirectoryExists(lOutRoot) then
    TDirectory.CreateDirectory(lOutRoot);

  lWarningsPath := TPath.Combine(lReportRoot, SPalWarningsFileName);
  lStrongPath := TPath.Combine(lReportRoot, SPalStrongWarningsFileName);
  lOptimizationPath := TPath.Combine(lReportRoot, SPalOptimizationFileName);
  lExceptionPath := TPath.Combine(lReportRoot, SPalExceptionFileName);
  lComplexityPath := TPath.Combine(lReportRoot, SPalComplexityFileName);
  lModuleTotalsPath := TPath.Combine(lReportRoot, SPalModuleTotalsFileName);

  lFindings := TList<TPalFinding>.Create;
  lSeen := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    lHasFindingsSource := False;
    lParsed := False;
    if FileExists(lWarningsPath) then
    begin
      ParseFindingReport(lWarningsPath, SPalWarningsFileName, SPalSeverityWarning, lFindings, lSeen, lParsed, lError);
      lHasFindingsSource := lParsed;
      if lError <> '' then
      begin
        aError := lError;
        Exit(False);
      end;
    end;

    lParsed := False;
    if FileExists(lStrongPath) then
    begin
      ParseFindingReport(lStrongPath, SPalStrongWarningsFileName, SPalSeverityStrongWarning, lFindings, lSeen, lParsed,
        lError);
      lHasFindingsSource := lHasFindingsSource or lParsed;
      if lError <> '' then
      begin
        aError := lError;
        Exit(False);
      end;
    end;

    lParsed := False;
    if FileExists(lOptimizationPath) then
    begin
      ParseFindingReport(lOptimizationPath, SPalOptimizationFileName, SPalSeverityOptimization, lFindings, lSeen, lParsed,
        lError);
      lHasFindingsSource := lHasFindingsSource or lParsed;
      if lError <> '' then
      begin
        aError := lError;
        Exit(False);
      end;
    end;

    lParsed := False;
    if FileExists(lExceptionPath) then
    begin
      ParseExceptionReport(lExceptionPath, SPalExceptionFileName, SPalSeverityException, lFindings, lSeen, lParsed,
        lError);
      lHasFindingsSource := lHasFindingsSource or lParsed;
      if lError <> '' then
      begin
        aError := lError;
        Exit(False);
      end;
    end;

    lHasHotspotSource := FileExists(lComplexityPath) or FileExists(lModuleTotalsPath);

    if not (lHasFindingsSource or lHasHotspotSource) then
    begin
      aError := 'No PAL XML report files found under: ' + lReportRoot;
      Exit(False);
    end;

    if lHasFindingsSource then
    begin
      if not WritePalFindingsMd(lFindings, TPath.Combine(lOutRoot, SPalFindingsFileName), lError) then
      begin
        aError := lError;
        Exit(False);
      end;
      if not WritePalFindingsJsonl(lFindings, TPath.Combine(lOutRoot, SPalFindingsJsonlFileName), lError) then
      begin
        aError := lError;
        Exit(False);
      end;
    end;

    if lHasHotspotSource then
    begin
      lEntries := nil;
      lModuleLines := nil;
      lRoutineList := TList<THotspotEntry>.Create;
      lModuleList := TList<THotspotEntry>.Create;
      lModuleLineList := TList<THotspotEntry>.Create;
      try
        if FileExists(lComplexityPath) then
        begin
          if not TryLoadComplexityEntries(lComplexityPath, lEntries, lError) then
          begin
            aError := lError;
            Exit(False);
          end;
        end;
        if FileExists(lModuleTotalsPath) then
        begin
          if not TryLoadModuleLines(lModuleTotalsPath, lModuleLines, lError) then
          begin
            aError := lError;
            Exit(False);
          end;
        end;

        for lEntry in lEntries do
        begin
          if lEntry.IsRoutine then
          begin
            if lEntry.Dp <= 0 then
              Continue;
            lHotspot := Default(THotspotEntry);
            lHotspot.Name := lEntry.Name;
            lHotspot.Score := lEntry.Dp;
            lHotspot.LinesOfCode := lEntry.LinesOfCode;
            lRoutineList.Add(lHotspot);
          end else
          begin
            lName := lEntry.Name;
            if IsAggregateName(lName) then
              Continue;
            if lEntry.Dp <= 0 then
              Continue;
            lHotspot := Default(THotspotEntry);
            lHotspot.Name := lName;
            lHotspot.Score := lEntry.Dp;
            lHotspot.LinesOfCode := lEntry.LinesOfCode;
            lModuleList.Add(lHotspot);
          end;
        end;

        if lModuleLines <> nil then
          for lName in lModuleLines.Keys do
          begin
            lHotspot := Default(THotspotEntry);
            lHotspot.Name := lName;
            lHotspot.Score := lModuleLines[lName];
            lHotspot.LinesOfCode := lHotspot.Score;
            lModuleLineList.Add(lHotspot);
          end;

        lRoutineArr := lRoutineList.ToArray;
        lModuleArr := lModuleList.ToArray;
        lModuleLineArr := lModuleLineList.ToArray;

        SortHotspots(lRoutineArr);
        SortHotspots(lModuleArr);
        SortHotspots(lModuleLineArr);

        lRoutineArr := TakeTopHotspots(lRoutineArr);
        lModuleArr := TakeTopHotspots(lModuleArr);
        lModuleLineArr := TakeTopHotspots(lModuleLineArr);

        if not WritePalHotspotsMd(lRoutineArr, lModuleArr, lModuleLineArr,
          TPath.Combine(lOutRoot, SPalHotspotsFileName), lError) then
        begin
          aError := lError;
          Exit(False);
        end;
      finally
        lRoutineList.Free;
        lModuleList.Free;
        lModuleLineList.Free;
        lModuleLines.Free;
      end;
    end;
  finally
    lFindings.Free;
    lSeen.Free;
  end;

  Result := True;
end;

end.
