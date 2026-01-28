unit Dcr.FixInsightRunner;

interface

uses
  System.Generics.Collections, System.SysUtils,
  Winapi.Windows,
  Dcr.Messages, Dcr.Types;

function BuildFixInsightCommandLine(const aParams: TFixInsightParams; out aExePath: string; out aCmdLine: string;
  out aError: string): Boolean;
function TryRunFixInsight(const aParams: TFixInsightParams; out aExitCode: Cardinal; out aError: string): Boolean;
function TryRunFixInsightWithHandles(const aParams: TFixInsightParams; aStdOut: THandle; aStdErr: THandle;
  out aExitCode: Cardinal; out aError: string): Boolean;

implementation

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

procedure AddArg(var aArgs: TArray<string>; var aCount: Integer; const aValue: string);
begin
  SetLength(aArgs, aCount + 1);
  aArgs[aCount] := aValue;
  Inc(aCount);
end;

function BuildArgs(const aParams: TFixInsightParams): TArray<string>;
var
  lArgs: TArray<string>;
  lCount: Integer;
  lDefines: string;
  lSearchPath: string;
  lLibPath: string;
  lScopes: string;
  lAliases: string;
  lSearchPaths: TArray<string>;
  lLibPaths: TArray<string>;

  function FilterExistingPaths(const aPaths: TArray<string>): TArray<string>;
  var
    lList: TList<string>;
    lItem: string;
  begin
    lList := TList<string>.Create;
    try
      for lItem in aPaths do
        if (lItem <> '') and DirectoryExists(lItem) then
          lList.Add(lItem);
      Result := lList.ToArray;
    finally
      lList.Free;
    end;
  end;
begin
  lCount := 0;
  lDefines := String.Join(';', aParams.fDefines);
  lSearchPaths := FilterExistingPaths(aParams.fUnitSearchPath);
  lLibPaths := FilterExistingPaths(aParams.fLibraryPath);
  lSearchPath := String.Join(';', lSearchPaths);
  lLibPath := String.Join(';', lLibPaths);
  lScopes := String.Join(';', aParams.fUnitScopes);
  lAliases := String.Join(';', aParams.fUnitAliases);

  AddArg(lArgs, lCount, '--project=' + aParams.fProjectDpr);
  if lDefines <> '' then
    AddArg(lArgs, lCount, '--defines=' + lDefines);
  if lSearchPath <> '' then
    AddArg(lArgs, lCount, '--searchpath=' + lSearchPath);
  if lLibPath <> '' then
    AddArg(lArgs, lCount, '--libpath=' + lLibPath);
  if lScopes <> '' then
    AddArg(lArgs, lCount, '--unitscopes=' + lScopes);
  if lAliases <> '' then
    AddArg(lArgs, lCount, '--unitaliases=' + lAliases);
  if aParams.fFixOutput <> '' then
    AddArg(lArgs, lCount, '--output=' + aParams.fFixOutput);
  if aParams.fFixIgnore <> '' then
    AddArg(lArgs, lCount, '--ignore=' + aParams.fFixIgnore);
  if aParams.fFixSettings <> '' then
    AddArg(lArgs, lCount, '--settings=' + aParams.fFixSettings);
  if aParams.fFixSilent then
    AddArg(lArgs, lCount, '--silent');
  if aParams.fFixXml then
    AddArg(lArgs, lCount, '--xml');
  if aParams.fFixCsv then
    AddArg(lArgs, lCount, '--csv');

  Result := lArgs;
end;

function BuildCommandLine(const aExePath: string; const aArgs: TArray<string>): string;
var
  lBuilder: TStringBuilder;
  lArg: string;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.Append(QuoteArg(aExePath));
    for lArg in aArgs do
    begin
      lBuilder.Append(' ');
      lBuilder.Append(QuoteArg(lArg));
    end;
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

function BuildFixInsightCommandLine(const aParams: TFixInsightParams; out aExePath: string; out aCmdLine: string;
  out aError: string): Boolean;
var
  lExe: string;
  lArgs: TArray<string>;
begin
  Result := False;
  aError := '';
  aExePath := '';
  aCmdLine := '';

  lExe := aParams.fFixInsightExe;
  if lExe = '' then
    lExe := 'FixInsightCL.exe';
  if lExe = '' then
  begin
    aError := SFixInsightExeMissing;
    Exit(False);
  end;

  lArgs := BuildArgs(aParams);
  aExePath := lExe;
  aCmdLine := BuildCommandLine(lExe, lArgs);
  Result := True;
end;

function TryRunFixInsightWithHandles(const aParams: TFixInsightParams; aStdOut: THandle; aStdErr: THandle;
  out aExitCode: Cardinal; out aError: string): Boolean;
var
  lExe: string;
  lCmdLine: string;
  lAppName: string;
  lAppPtr: PChar;
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

  if not BuildFixInsightCommandLine(aParams, lExe, lCmdLine, aError) then
    Exit(False);
  UniqueString(lCmdLine);

  lAppName := '';
  if FileExists(lExe) then
    lAppName := lExe;
  if lAppName = '' then
    lAppPtr := nil
  else
    lAppPtr := PChar(lAppName);

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

  if not CreateProcess(lAppPtr, PChar(lCmdLine), nil, nil, True, 0, nil, nil, lSi, lPi) then
  begin
    lLastError := GetLastError;
    aError := Format(SFixInsightRunFailed, [SysErrorMessage(lLastError)]);
    Exit(False);
  end;
  try
    lWait := WaitForSingleObject(lPi.hProcess, INFINITE);
    if lWait <> WAIT_OBJECT_0 then
    begin
      lLastError := GetLastError;
      aError := Format(SFixInsightRunFailed, [SysErrorMessage(lLastError)]);
      Exit(False);
    end;
    if not GetExitCodeProcess(lPi.hProcess, aExitCode) then
    begin
      lLastError := GetLastError;
      aError := Format(SFixInsightRunFailed, [SysErrorMessage(lLastError)]);
      Exit(False);
    end;
  finally
    CloseHandle(lPi.hThread);
    CloseHandle(lPi.hProcess);
  end;

  Result := True;
end;

function TryRunFixInsight(const aParams: TFixInsightParams; out aExitCode: Cardinal; out aError: string): Boolean;
begin
  Result := TryRunFixInsightWithHandles(aParams, GetStdHandle(STD_OUTPUT_HANDLE), GetStdHandle(STD_ERROR_HANDLE),
    aExitCode, aError);
end;

end.
