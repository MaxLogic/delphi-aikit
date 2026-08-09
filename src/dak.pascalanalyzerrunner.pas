unit Dak.PascalAnalyzerRunner;

interface

uses
  System.Classes, System.Diagnostics, System.Generics.Collections, System.IOUtils, System.JSON, System.StrUtils,
  System.SysUtils, System.Types,
  Winapi.ShellAPI, Winapi.Windows,
  maxLogic.StrUtils,
  Dak.ExternalToolProcess, Dak.PascalAnalyzer.Artifacts, Dak.Types, Dak.Utils;

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
  cMaxPalArguments = 256;
  SPalCmdMapPathEnvVar = 'DAK_PALCMD_MAP_PATH';
  SPalCmdExeName = 'palcmd.exe';
  SPalCmd32ExeName = 'palcmd32.exe';
  SPalCmdMapFileName = 'palcmd-map.json';

type
  TPalArgValues = array[0..cMaxPalArguments - 1] of PWideChar;
  PPalArgValues = ^TPalArgValues;

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
var
  lOverridePath: string;
begin
  lOverridePath := Trim(GetEnvironmentVariable(SPalCmdMapPathEnvVar));
  if lOverridePath <> '' then
    Exit(TPath.GetFullPath(lOverridePath));
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), SPalCmdMapFileName);
end;

function ReadSharedUtf8TextFile(const aPath: string): string;
var
  lReader: TStreamReader;
  lStream: TFileStream;
begin
  lStream := TFileStream.Create(aPath, fmOpenRead or fmShareDenyNone);
  try
    lReader := TStreamReader.Create(lStream, TEncoding.UTF8, True);
    try
      Result := lReader.ReadToEnd;
    finally
      lReader.Free;
    end;
  finally
    lStream.Free;
  end;
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
  lJsonValue: TJSONValue;
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

    lText := ReadSharedUtf8TextFile(lPath);
    lJsonValue := TJSONObject.ParseJSONValue(lText);
    if lJsonValue = nil then
    begin
      aError := 'PALCMD mapping file is not valid JSON: ' + lPath;
      Exit(False);
    end;
    if not (lJsonValue is TJSONObject) then
    begin
      lJsonValue.Free;
      aError := 'PALCMD mapping file root must be a JSON object: ' + lPath;
      Exit(False);
    end;
    lJson := TJSONObject(lJsonValue);
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

function TryCaptureProcessOutput(const aExe, aArgs: string; aTimeoutSec: Integer; out aOutput: string;
  out aExitCode: Cardinal; out aError: string): Boolean;
var
  lAvailable: Cardinal;
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
  lStopwatch: TStopwatch;
  lTimeoutMs: Cardinal;
  lTimeoutSec: Integer;
  lWait: Cardinal;

  function CheckTimeout: Boolean;
  begin
    Result := True;
    if UInt64(lStopwatch.ElapsedMilliseconds) < lTimeoutMs then
      Exit(True);
    TryTerminateTimedOutExternalToolProcess('PALCMD help', lPi.hProcess, lTimeoutSec, aExitCode, aError);
    Result := False;
  end;

  function DrainPipe: Boolean;
  var
    lToRead: Cardinal;
  begin
    Result := True;
    while True do
    begin
      if not CheckTimeout then
        Exit(False);
      lAvailable := 0;
      if not PeekNamedPipe(lRead, nil, 0, nil, @lAvailable, nil) then
      begin
        lLastError := GetLastError;
        if (lLastError = ERROR_BROKEN_PIPE) or (lLastError = ERROR_HANDLE_EOF) then
          Exit(True);
        aError := 'PALCMD help output read failed: ' + SysErrorMessage(lLastError);
        Exit(False);
      end;
      if lAvailable = 0 then
        Exit(True);

      lToRead := lAvailable;
      if lToRead > SizeOf(lBuffer) then
        lToRead := SizeOf(lBuffer);
      if not ReadFile(lRead, lBuffer, lToRead, lBytesRead, nil) then
      begin
        lLastError := GetLastError;
        if (lLastError = ERROR_BROKEN_PIPE) or (lLastError = ERROR_HANDLE_EOF) then
          Exit(True);
        aError := 'PALCMD help output read failed: ' + SysErrorMessage(lLastError);
        Exit(False);
      end;
      if lBytesRead = 0 then
        Exit(True);

      SetString(lAnsi, PAnsiChar(@lBuffer[0]), lBytesRead);
      lBuilder.Append(string(lAnsi));
      if not CheckTimeout then
        Exit(False);
    end;
  end;
begin
  // Protocol-specific output capture: PAL help must drain pipes while polling so the child cannot block on output.
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
      lTimeoutSec := ResolveExternalToolTimeoutSec(aTimeoutSec);
      lTimeoutMs := ResolveExternalToolTimeoutMs(lTimeoutSec);
      lStopwatch := TStopwatch.StartNew;
      while True do
      begin
        if not DrainPipe then
          Exit(False);
        lWait := WaitForSingleObject(lPi.hProcess, 25);
        if lWait = WAIT_OBJECT_0 then
        begin
          if not DrainPipe then
            Exit(False);
          Break;
        end;
        if lWait <> WAIT_TIMEOUT then
        begin
          lLastError := GetLastError;
          aError := 'PALCMD help wait failed: ' + SysErrorMessage(lLastError);
          Exit(False);
        end;
        if not CheckTimeout then
          Exit(False);
      end;
      aOutput := lBuilder.ToString;
    finally
      lBuilder.Free;
    end;

    if not TryWaitForExternalToolProcess('PALCMD help', lPi.hProcess, lTimeoutSec, aExitCode, aError) then
      Exit(False);
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

function TryGetPalCmdHelpText(const aPalCmdExe: string; aTimeoutSec: Integer; out aText: string;
  out aTimedOut: Boolean; out aError: string): Boolean;
var
  lExit: Cardinal;
begin
  aTimedOut := False;
  Result := TryCaptureProcessOutput(aPalCmdExe, '', aTimeoutSec, aText, lExit, aError);
  aTimedOut := lExit = cExternalToolTimeoutExitCode;
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
    if not CharInSet(lBefore, ['A'..'Z', '0'..'9']) and not CharInSet(lAfter, ['A'..'Z', '0'..'9']) then
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
begin
  Result := NormalizeConfiguredPath(aValue);
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
    Result := System.SysUtils.GetEnvironmentVariable(aName);
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
  aTimeoutSec: Integer; out aFlag: string; out aError: string): Boolean;
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
  lHelpTimedOut: Boolean;
begin
  aFlag := '';
  aError := '';

  lMajor := StrToIntDef(Copy(aBdsVersion, 1, Pos('.', aBdsVersion + '.') - 1), 0);
  lIsWin32 := SameText(aPlatform, 'Win32');
  lIsWin64 := SameText(aPlatform, 'Win64');
  if not (lIsWin32 or lIsWin64) then
  begin
    aError := 'Unsupported platform for Pascal Analyzer: ' + aPlatform + '. Use Win32 or Win64.';
    Exit(False);
  end;
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

    if not TryGetPalCmdHelpText(aPalCmdExe, aTimeoutSec, lHelpText, lHelpTimedOut, lHelpError) then
    begin
      if lHelpTimedOut then
      begin
        aError := lHelpError;
        Exit(False);
      end;

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

function GetCpuCount: Integer;
var
  lSys: TSystemInfo;
begin
  GetSystemInfo(lSys);
  Result := lSys.dwNumberOfProcessors;
  if Result < 1 then
    Result := 1;
end;

procedure AppendAutomationDefaults(const aArgs: TStringBuilder);
var
  lThreads: Integer;
begin
  aArgs.Append(' /F=X /Q /A+ /FA /T=');
  lThreads := GetCpuCount;
  if lThreads > 64 then
    lThreads := 64;
  aArgs.Append(lThreads.ToString);
end;

function IsOwnedPalArgument(const aArg: string): Boolean;
var
  lArg: string;
begin
  lArg := UpperCase(aArg);
  Result := StartsText('/F=', lArg) or StartsText('/R=', lArg) or StartsText('/NAME=', lArg) or
    StartsText('/T=', lArg) or StartsText('/X=', lArg) or StartsText('/XF=', lArg) or
    MatchText(lArg, ['/A+', '/A-', '/FA', '/F+', '/FR', '/FM', '/F-', '/Q']);
end;

function TryValidatePalExclusionList(const aValue, aSwitch: string; const aRequireAbsolute: Boolean;
  out aError: string): Boolean;
var
  lItem: string;
  lItems: TStringList;
  lPath: string;
begin
  Result := False;
  aError := '';
  if aValue = '' then
    Exit(True);
  if (Pos('"', aValue) > 0) or (Pos(#13, aValue) > 0) or (Pos(#10, aValue) > 0) then
  begin
    aError := aSwitch + ' contains an unsupported quote or line break.';
    Exit(False);
  end;

  lItems := TStringList.Create;
  try
    lItems.StrictDelimiter := True;
    lItems.Delimiter := ';';
    lItems.DelimitedText := aValue;
    for lItem in lItems do
    begin
      lPath := Trim(lItem);
      if lPath = '' then
      begin
        aError := aSwitch + ' contains an empty item.';
        Exit(False);
      end;
      if aRequireAbsolute then
      begin
        if EndsText('<+>', lPath) then
          Delete(lPath, Length(lPath) - 2, 3);
        if not TPath.IsPathRooted(lPath) then
        begin
          aError := aSwitch + ' folders must be absolute: ' + lItem;
          Exit(False);
        end;
      end;
    end;
    Result := True;
  finally
    lItems.Free;
  end;
end;

function TryValidatePalExclusions(const aPa: TPascalAnalyzerDefaults; out aError: string): Boolean;
begin
  Result := TryValidatePalExclusionList(aPa.fExcludeSearchFolders, 'PAL /X', True, aError) and
    TryValidatePalExclusionList(aPa.fExcludeFiles, 'PAL /XF', False, aError);
end;

procedure AppendPalExclusions(const aArgs: TStringBuilder; const aPa: TPascalAnalyzerDefaults);
begin
  if aPa.fExcludeSearchFolders <> '' then
  begin
    aArgs.Append(' /X=');
    aArgs.Append(QuoteArg(aPa.fExcludeSearchFolders));
  end;
  if aPa.fExcludeFiles <> '' then
  begin
    aArgs.Append(' /XF=');
    aArgs.Append(QuoteArg(aPa.fExcludeFiles));
  end;
end;

function TryValidatePalExtraArgs(const aArgs: string; out aError: string): Boolean;
var
  i: Integer;
  lArg: string;
  lArgCount: Integer;
  lArgValues: PPWideChar;
  lCommandLine: string;
begin
  Result := False;
  aError := '';
  if Trim(aArgs) = '' then
    Exit(True);

  lCommandLine := 'palcmd ' + aArgs;
  lArgValues := CommandLineToArgvW(PWideChar(lCommandLine), lArgCount);
  if lArgValues = nil then
  begin
    aError := 'Unable to parse extra PALCMD arguments. Windows error: ' + GetLastError.ToString;
    Exit(False);
  end;
  try
    if lArgCount > cMaxPalArguments then
    begin
      aError := 'Too many extra PALCMD arguments.';
      Exit(False);
    end;
    for i := 1 to lArgCount - 1 do
    begin
      lArg := PPalArgValues(lArgValues)^[i];
      if IsOwnedPalArgument(lArg) then
      begin
        aError := 'PALCMD argument conflicts with DAK-owned automation: ' + lArg;
        Exit(False);
      end;
    end;
    Result := True;
  finally
    LocalFree(HLOCAL(lArgValues));
  end;
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
  lReportName: string;
  lSearch: string;
  lFolders: TArray<string>;
begin
  Result := False;
  aCmdLine := '';
  aError := '';
  if not TryValidatePalExclusions(aPa, aError) then
    Exit(False);
  if not TryValidatePalExtraArgs(aPa.fArgs, aError) then
    Exit(False);

  lArgs := TStringBuilder.Create;
  try
    // exe + input path
    lArgs.Append(QuoteArg(aExePath));
    lArgs.Append(' ');
    lArgs.Append(QuoteArg(aParams.fProjectDpr));

    if (aPa.fArgs = '') or (Pos('/CD', UpperCase(aPa.fArgs)) = 0) then
    begin
      if not TryBuildDelphiTargetFlag(aParams.fDelphiVersion, aParams.fPlatform, aExePath, aPa.fTimeoutSec, lFlag,
        aError) then
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

    lReportName := TPath.GetFileNameWithoutExtension(aParams.fProjectDpr);
    lArgs.Append(' /NAME=');
    lArgs.Append(QuoteArg(lReportName));

    AppendAutomationDefaults(lArgs);
    AppendPalExclusions(lArgs, aPa);
    if aPa.fArgs <> '' then
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
  lCmdLine: string;
  lExe: string;
  lRunOptions: TExternalToolProcessRunOptions;
  lStdOut: THandle;
  lStdErr: THandle;
  lTimedOut: Boolean;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not BuildPalCmdCommandLine(aParams, aPa, lExe, lCmdLine, aError) then
    Exit(False);
  UniqueString(lCmdLine);

  lStdOut := aStdOut;
  if lStdOut = 0 then
    lStdOut := GetStdHandle(STD_OUTPUT_HANDLE);
  lStdErr := aStdErr;
  if lStdErr = 0 then
    lStdErr := GetStdHandle(STD_ERROR_HANDLE);

  lRunOptions := Default(TExternalToolProcessRunOptions);
  lRunOptions.fApplicationName := lExe;
  lRunOptions.fExePath := lExe;
  lRunOptions.fCommandLine := lCmdLine;
  lRunOptions.fEnvironmentBlock := aParams.fEnvironmentBlock;
  lRunOptions.fToolName := 'PALCMD';
  lRunOptions.fStartFailureFormat := 'PALCMD failed to start: %s';
  lRunOptions.fStdInHandle := GetStdHandle(STD_INPUT_HANDLE);
  lRunOptions.fStdOutHandle := lStdOut;
  lRunOptions.fStdErrHandle := lStdErr;
  lRunOptions.fTimeoutSec := aPa.fTimeoutSec;
  lRunOptions.fUseDefaultTimeout := True;
  lRunOptions.fTimeoutExitCode := cExternalToolTimeoutExitCode;
  Result := TryRunExternalToolProcess(lRunOptions, aExitCode, lTimedOut, aError);
end;

function BuildPalCmdUnitCommandLine(const aUnitPath: string; const aPa: TPascalAnalyzerDefaults;
  out aExePath: string; out aCmdLine: string; out aError: string): Boolean;
var
  lExe: string;
  lArgs: TStringBuilder;
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
  if not TryValidatePalExclusions(aPa, aError) then
    Exit(False);
  if not TryValidatePalExtraArgs(aPa.fArgs, aError) then
    Exit(False);
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

    AppendAutomationDefaults(lArgs);
    AppendPalExclusions(lArgs, aPa);
    if aPa.fArgs <> '' then
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
  lRunOptions: TExternalToolProcessRunOptions;
  lStdOut: THandle;
  lStdErr: THandle;
  lTimedOut: Boolean;
begin
  Result := False;
  aError := '';
  aExitCode := 0;

  if not BuildPalCmdUnitCommandLine(aUnitPath, aPa, lExe, lCmdLine, aError) then
    Exit(False);
  UniqueString(lCmdLine);

  lStdOut := aStdOut;
  if lStdOut = 0 then
    lStdOut := GetStdHandle(STD_OUTPUT_HANDLE);
  lStdErr := aStdErr;
  if lStdErr = 0 then
    lStdErr := GetStdHandle(STD_ERROR_HANDLE);

  lRunOptions := Default(TExternalToolProcessRunOptions);
  lRunOptions.fApplicationName := lExe;
  lRunOptions.fExePath := lExe;
  lRunOptions.fCommandLine := lCmdLine;
  lRunOptions.fToolName := 'PALCMD';
  lRunOptions.fStartFailureFormat := 'PALCMD failed to start: %s';
  lRunOptions.fStdInHandle := GetStdHandle(STD_INPUT_HANDLE);
  lRunOptions.fStdOutHandle := lStdOut;
  lRunOptions.fStdErrHandle := lStdErr;
  lRunOptions.fTimeoutSec := aPa.fTimeoutSec;
  lRunOptions.fUseDefaultTimeout := True;
  lRunOptions.fTimeoutExitCode := cExternalToolTimeoutExitCode;
  Result := TryRunExternalToolProcess(lRunOptions, aExitCode, lTimedOut, aError);
end;

function TryFindPalReportRoot(const aOutputRoot: string; out aReportRoot: string; out aError: string): Boolean;
begin
  Result := Dak.PascalAnalyzer.Artifacts.TryFindPalReportRoot(aOutputRoot, aReportRoot, aError);
end;

function TryGeneratePalArtifacts(const aReportRoot: string; const aOutRoot: string; out aError: string): Boolean;
begin
  Result := Dak.PascalAnalyzer.Artifacts.TryGeneratePalArtifacts(aReportRoot, aOutRoot, aError);
end;

end.
