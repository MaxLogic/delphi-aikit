unit Dcr.PascalAnalyzerRunner;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
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
    if Env('ProgramFiles') <> '' then
      lRoots.Add(Env('ProgramFiles'));
    if Env('ProgramFiles(x86)') <> '' then
      lRoots.Add(Env('ProgramFiles(x86)'));

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

function TryBuildDelphiTargetFlag(const aBdsVersion: string; const aPlatform: string; out aFlag: string): Boolean;
var
  lMajor: Integer;
  lDelphi: string;
  lPlat: string;
begin
  aFlag := '';

  lMajor := StrToIntDef(Copy(aBdsVersion, 1, Pos('.', aBdsVersion + '.') - 1), 0);
  case lMajor of
    23: lDelphi := '12';
    22: lDelphi := '11';
    21: lDelphi := '104';
    20: lDelphi := '103';
    19: lDelphi := '102';
    18: lDelphi := '101';
    17: lDelphi := '10';
  else
    Exit(False);
  end;

  if SameText(aPlatform, 'Win32') then
    lPlat := 'W32'
  else if SameText(aPlatform, 'Win64') then
    lPlat := 'W64'
  else
    Exit(False);

  aFlag := '/CD' + lDelphi + lPlat;
  Result := True;
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
      if not TryBuildDelphiTargetFlag(aParams.fDelphiVersion, aParams.fPlatform, lFlag) then
      begin
        aError := 'Unsupported Delphi/platform for PALCMD target flag. Provide /CD... via --pa-args.';
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
