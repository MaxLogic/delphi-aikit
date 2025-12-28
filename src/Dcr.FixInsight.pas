unit Dcr.FixInsight;

interface

uses
  System.IOUtils, System.SysUtils, System.Win.Registry,
  Winapi.Windows,
  Dcr.Diagnostics, Dcr.Messages;

function TryResolveFixInsightExe(aDiagnostics: TDiagnostics; out aExePath: string): Boolean;

implementation

const
  SFixInsightExeName = 'FixInsightCL.exe';
  SFixInsightRegKey = 'Software\FixInsight';
  SFixInsightRegValue = 'Path';

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

function FindInPath(const aExeName: string; out aFullPath: string): Boolean;
var
  lRequired: Cardinal;
  lBuffer: string;
  lFilePart: PChar;
begin
  aFullPath := '';
  lFilePart := nil;
  lRequired := SearchPath(nil, PChar(aExeName), nil, 0, nil, lFilePart);
  if lRequired = 0 then
    Exit(False);
  SetLength(lBuffer, lRequired + 1);
  lRequired := SearchPath(nil, PChar(aExeName), nil, Length(lBuffer), PChar(lBuffer), lFilePart);
  if lRequired = 0 then
    Exit(False);
  SetLength(lBuffer, StrLen(PChar(lBuffer)));
  aFullPath := lBuffer;
  Result := aFullPath <> '';
end;

function BuildFromRegistry(const aBaseValue: string): string;
var
  lValue: string;
begin
  lValue := Trim(ExpandEnvVars(aBaseValue));
  if lValue = '' then
    Exit('');
  if SameText(TPath.GetExtension(lValue), '.exe') then
    Result := lValue
  else
    Result := TPath.Combine(lValue, SFixInsightExeName);
end;

function TryResolveFixInsightExe(aDiagnostics: TDiagnostics; out aExePath: string): Boolean;
var
  lReg: TRegistry;
  lValue: string;
  lCandidate: string;
begin
  aExePath := '';
  if FindInPath(SFixInsightExeName, aExePath) then
  begin
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoFixInsightPath, [aExePath]));
    Exit(True);
  end;

  lValue := '';
  lReg := TRegistry.Create;
  try
    lReg.Access := KEY_READ;
    lReg.RootKey := HKEY_CURRENT_USER;
    if lReg.OpenKeyReadOnly(SFixInsightRegKey) then
    begin
      if lReg.ValueExists(SFixInsightRegValue) then
        lValue := lReg.ReadString(SFixInsightRegValue);
    end;
  finally
    lReg.Free;
  end;

  lCandidate := BuildFromRegistry(lValue);
  if (lCandidate <> '') and FileExists(lCandidate) then
  begin
    aExePath := lCandidate;
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoFixInsightPath, [aExePath]));
    Exit(True);
  end;

  Result := False;
end;

end.
