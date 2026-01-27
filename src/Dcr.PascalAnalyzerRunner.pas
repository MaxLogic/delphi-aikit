unit Dcr.PascalAnalyzerRunner;

interface

uses
  System.Generics.Collections,
  System.JSON,
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  System.Types,
  Winapi.Windows,
  maxLogic.StrUtils,
  Dcr.Types;

function TryResolvePalCmdExe(const aOverridePath: string; out aExePath: string; out aError: string): Boolean;
function TryRunPascalAnalyzer(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  out aExitCode: Cardinal; out aError: string): Boolean;

implementation

const
  SPalCmdExeName = 'palcmd.exe';
  SPalCmd32ExeName = 'palcmd32.exe';
  SPalCmdMapFileName = 'palcmd-map.json';

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
    aArr := TJSONArray(lValue);
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
    aError := 'PALCMD help exited with code ' + lExit.ToString + '.';
    Result := False;
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

  aError := 'PALCMD not found. Provide --pa-path or set [PascalAnalyzer].Path in settings.ini.';
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
  lSelected: string;
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

    lSelected := lDelphiKey;
    if lIndex > lMaxIndex then
      lSelected := lMaxDelphi;

    if TryGetPalCmdHelpText(aPalCmdExe, lHelpText, lHelpError) then
    begin
      if not TryResolveFlagFromHelp(lMap, lHelpText, aPlatform, lSelected, aFlag) then
      begin
        aError := 'PALCMD help does not list a compatible /CD flag.';
        Exit(False);
      end;
    end else
    begin
      if lIsWin32 then
      begin
        if not lMap.DelphiWin32.TryGetValue(lSelected, aFlag) then
        begin
          aError := 'PALCMD mapping missing Win32 flag for Delphi version: ' + lSelected;
          Exit(False);
        end;
      end else
      begin
        if not lMap.DelphiWin64.TryGetValue(lSelected, aFlag) then
        begin
          aError := 'PALCMD mapping missing Win64 flag for Delphi version: ' + lSelected;
          Exit(False);
        end;
      end;
    end;

    Result := True;
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
      lArgs.Append(' /FR');
      lThreads := CpuCount;
      if lThreads > 8 then
        lThreads := 8;
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

function TryRunPascalAnalyzer(const aParams: TFixInsightParams; const aPa: TPascalAnalyzerDefaults;
  out aExitCode: Cardinal; out aError: string): Boolean;
var
  lExe: string;
  lCmdLine: string;
  lSi: TStartupInfo;
  lPi: TProcessInformation;
  lWait: Cardinal;
  lLastError: Cardinal;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not TryResolvePalCmdExe(aPa.fPath, lExe, aError) then
    Exit(False);

  if not BuildArgs(aParams, aPa, lExe, lCmdLine, aError) then
    Exit(False);
  UniqueString(lCmdLine);

  FillChar(lSi, SizeOf(lSi), 0);
  lSi.cb := SizeOf(lSi);
  lSi.dwFlags := STARTF_USESTDHANDLES;
  lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lSi.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  lSi.hStdError := GetStdHandle(STD_ERROR_HANDLE);
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

end.
