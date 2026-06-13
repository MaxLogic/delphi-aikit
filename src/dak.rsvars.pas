unit Dak.RsVars;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.SysUtils,
  Winapi.Windows,
  maxLogic.StrUtils,
  Dak.Diagnostics, Dak.Messages;

type
  TRsVarsEnvironmentVariable = record
    Name: string;
    Value: string;
  end;

  TRsVarsEnvironment = record
    Variables: TArray<TRsVarsEnvironmentVariable>;
    function TryGetValue(const aName: string; out aValue: string): Boolean;
    function ValueOrDefault(const aName: string; const aDefault: string = ''): string;
    function ToDictionary: TDictionary<string, string>;
    function ToEnvironmentBlock: string;
  end;

function TryLoadRsVars(const aDelphiVersion, aOverridePath: string; aDiagnostics: TDiagnostics;
  out aEnvironment: TRsVarsEnvironment; out aError: string): Boolean;

implementation

function QuoteCmd(const aValue: string): string;
begin
  Result := '"' + StringReplace(aValue, '"', '""', [rfReplaceAll]) + '"';
end;

function TRsVarsEnvironment.TryGetValue(const aName: string; out aValue: string): Boolean;
var
  lVariable: TRsVarsEnvironmentVariable;
begin
  for lVariable in Variables do
    if SameText(lVariable.Name, aName) then
    begin
      aValue := lVariable.Value;
      Exit(True);
    end;
  aValue := '';
  Result := False;
end;

function TRsVarsEnvironment.ValueOrDefault(const aName, aDefault: string): string;
begin
  if not TryGetValue(aName, Result) then
    Result := aDefault;
end;

function TRsVarsEnvironment.ToDictionary: TDictionary<string, string>;
var
  lVariable: TRsVarsEnvironmentVariable;
begin
  Result := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  for lVariable in Variables do
    Result.AddOrSetValue(lVariable.Name, lVariable.Value);
end;

function TRsVarsEnvironment.ToEnvironmentBlock: string;
var
  lVariable: TRsVarsEnvironmentVariable;
begin
  Result := '';
  for lVariable in Variables do
    Result := Result + lVariable.Name + '=' + lVariable.Value + #0;
  if Result <> '' then
    Result := Result + #0;
end;

function CoreWindowsPath: string;
var
  lSystemRoot: string;
begin
  lSystemRoot := System.SysUtils.GetEnvironmentVariable('SystemRoot');
  if lSystemRoot = '' then
    lSystemRoot := 'C:\Windows';
  Result := TPath.Combine(lSystemRoot, 'System32') + ';' + lSystemRoot + ';' +
    TPath.Combine(lSystemRoot, 'System32\Wbem') + ';' +
    TPath.Combine(lSystemRoot, 'System32\WindowsPowerShell\v1.0');
end;

function BuildRsVarsEnvironmentPrefix: string;
var
  lPath: string;
begin
  Result := 'set "BDS=" & set "BDSLIB=" & set "DCC_Namespace=" & set "DCC_UnitSearchPath=" & ' +
    'set "DCC_Define=" & set "DCC_UnitAlias=" & set "DCC_UnitAliases=" & ' +
    'set "DelphiLibraryPath=" & set "EnvOptions=" & ';

  lPath := System.SysUtils.GetEnvironmentVariable('PATH');
  if Length(lPath) > 6000 then
    Result := Result + 'set "PATH=' + CoreWindowsPath + '" & ';
end;

function DefaultRsVarsPath(const aDelphiVersion: string): string;
var
  lBase: string;
  lPath: string;
begin
  lBase := System.SysUtils.GetEnvironmentVariable('ProgramFiles(x86)');
  if lBase <> '' then
  begin
    lPath := TPath.Combine(lBase, 'Embarcadero\Studio\' + aDelphiVersion + '\bin\rsvars.bat');
    if FileExists(lPath) then
      Exit(lPath);
    lPath := TPath.Combine(lBase, 'Embarcadero\RAD Studio\' + aDelphiVersion + '\bin\rsvars.bat');
    if FileExists(lPath) then
      Exit(lPath);
  end;

  lBase := System.SysUtils.GetEnvironmentVariable('ProgramFiles');
  if lBase <> '' then
  begin
    lPath := TPath.Combine(lBase, 'Embarcadero\Studio\' + aDelphiVersion + '\bin\rsvars.bat');
    if FileExists(lPath) then
      Exit(lPath);
    lPath := TPath.Combine(lBase, 'Embarcadero\RAD Studio\' + aDelphiVersion + '\bin\rsvars.bat');
    if FileExists(lPath) then
      Exit(lPath);
  end;

  if lPath <> '' then
    Exit(lPath);
  Result := TPath.Combine('C:\Program Files (x86)', 'Embarcadero\Studio\' + aDelphiVersion + '\bin\rsvars.bat');
end;

function RunCmdToFile(const aCommandLine: string; out aExitCode: Cardinal): Boolean;
var
  lSI: TStartupInfo;
  lPI: TProcessInformation;
  lCmd: string;
begin
  FillChar(lSI, SizeOf(lSI), 0);
  lSI.cb := SizeOf(lSI);
  lSI.dwFlags := STARTF_USESHOWWINDOW;
  lSI.wShowWindow := SW_HIDE;
  FillChar(lPI, SizeOf(lPI), 0);

  lCmd := aCommandLine;
  UniqueString(lCmd);
  Result := CreateProcess(nil, PChar(lCmd), nil, nil, False, CREATE_NO_WINDOW, nil, nil, lSI, lPI);
  if not Result then
    Exit(False);
  try
    WaitForSingleObject(lPI.hProcess, INFINITE);
    if not GetExitCodeProcess(lPI.hProcess, aExitCode) then
      aExitCode := 1;
  finally
    CloseHandle(lPI.hThread);
    CloseHandle(lPI.hProcess);
  end;
end;

function TryLoadRsVars(const aDelphiVersion, aOverridePath: string; aDiagnostics: TDiagnostics;
  out aEnvironment: TRsVarsEnvironment; out aError: string): Boolean;
var
  lPath: string;
  lTempFile: string;
  lComSpec: string;
  lCmd: string;
  lExitCode: Cardinal;
  lLines: TStringList;
  lLine: string;
  lPos: Integer;
  lName: string;
  lValue: string;
  lCount: Integer;
  lVariables: TList<TRsVarsEnvironmentVariable>;
  lVariable: TRsVarsEnvironmentVariable;
begin
  Result := False;
  aError := '';
  aEnvironment := Default(TRsVarsEnvironment);
  lCount := 0;

  if (Trim(aOverridePath) = '') and (Trim(aDelphiVersion) = '') then
  begin
    aError := 'Delphi version is required. Pass --delphi <major.minor> or set [Build] DelphiVersion in dak.ini.';
    Exit(False);
  end;

  if aOverridePath <> '' then
    lPath := aOverridePath
  else
    lPath := DefaultRsVarsPath(aDelphiVersion);

  if aDiagnostics <> nil then
    aDiagnostics.AddInfo(Format(SInfoRsVarsPath, [lPath]));

  if not FileExists(lPath) then
  begin
    aError := Format(SRsVarsNotFound, [lPath]);
    Exit(False);
  end;

  lTempFile := TPath.GetTempFileName;
  try
    lComSpec := System.SysUtils.GetEnvironmentVariable('ComSpec');
    if lComSpec = '' then
      lComSpec := 'cmd.exe';

    lCmd := QuoteCmd(lComSpec) + ' /s /c "' + BuildRsVarsEnvironmentPrefix + 'call ' + QuoteCmd(lPath) +
      ' >nul & set > ' + QuoteCmd(lTempFile) + '"';
    if not RunCmdToFile(lCmd, lExitCode) then
    begin
      aError := Format(SRsVarsFailed, [Cardinal(1)]);
      Exit(False);
    end;
    if lExitCode <> 0 then
    begin
      aError := Format(SRsVarsFailed, [lExitCode]);
      Exit(False);
    end;

    lLines := TStringList.Create;
    lVariables := TList<TRsVarsEnvironmentVariable>.Create;
    try
      lLines.LoadFromFile(lTempFile);
      for lLine in lLines do
      begin
        lPos := Pos('=', lLine);
        if lPos <= 1 then
          Continue;
        lName := Copy(lLine, 1, lPos - 1);
        if (lName = '') or (lName[1] = '=') then
          Continue;
        lValue := Copy(lLine, lPos + 1, Length(lLine) - lPos);
        lVariable.Name := lName;
        lVariable.Value := lValue;
        lVariables.Add(lVariable);
        Inc(lCount);
      end;
      aEnvironment.Variables := lVariables.ToArray;
    finally
      lVariables.Free;
      lLines.Free;
    end;

    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoRsVarsCount, [lCount]));
  finally
    if FileExists(lTempFile) then
      System.SysUtils.DeleteFile(lTempFile);
  end;

  Result := True;
end;

end.
