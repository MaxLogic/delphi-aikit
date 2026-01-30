unit Dak.RsVars;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.SysUtils,
  Winapi.Windows,
  Dak.Diagnostics, Dak.Messages;

function TryLoadRsVars(const aDelphiVersion, aOverridePath: string; aDiagnostics: TDiagnostics;
  out aError: string): Boolean;

implementation

function QuoteCmd(const aValue: string): string;
begin
  Result := '"' + StringReplace(aValue, '"', '""', [rfReplaceAll]) + '"';
end;

function DefaultRsVarsPath(const aDelphiVersion: string): string;
var
  lBase: string;
  lPath: string;
begin
  lBase := GetEnvironmentVariable('ProgramFiles(x86)');
  if lBase <> '' then
  begin
    lPath := TPath.Combine(lBase, 'Embarcadero\Studio\' + aDelphiVersion + '\bin\rsvars.bat');
    if FileExists(lPath) then
      Exit(lPath);
  end;

  lBase := GetEnvironmentVariable('ProgramFiles');
  if lBase <> '' then
  begin
    lPath := TPath.Combine(lBase, 'Embarcadero\Studio\' + aDelphiVersion + '\bin\rsvars.bat');
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
  out aError: string): Boolean;
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
begin
  Result := False;
  aError := '';
  lCount := 0;

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
    lComSpec := GetEnvironmentVariable('ComSpec');
    if lComSpec = '' then
      lComSpec := 'cmd.exe';

    lCmd := QuoteCmd(lComSpec) + ' /s /c "call ' + QuoteCmd(lPath) + ' >nul & set > ' +
      QuoteCmd(lTempFile) + '"';
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
        Winapi.Windows.SetEnvironmentVariable(PChar(lName), PChar(lValue));
        Inc(lCount);
      end;
    finally
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
