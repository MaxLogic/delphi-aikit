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
  SFixInsightRegValue = 'Path';
  CFixInsightRegKeys: array[0..1] of string = (
    'Software\FixInsight',
    'Software\TMSSoftware\TMS FixInsight Pro'
  );

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
const
  CRoots: array[0..1] of HKEY = (HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE);
  CViews: array[0..1] of Cardinal = (KEY_WOW64_64KEY, KEY_WOW64_32KEY);
var
  lReg: TRegistry;
  lValue: string;
  lCandidate: string;
  lRootIndex: Integer;
  lViewIndex: Integer;
  lKeyIndex: Integer;

  function TryReadRegistryValue(const aRegKey: string; aRootKey: HKEY; aViewFlag: Cardinal;
    out aOutValue: string): Boolean;
  begin
    Result := False;
    aOutValue := '';
    lReg := TRegistry.Create;
    try
      lReg.Access := KEY_READ or aViewFlag;
      lReg.RootKey := aRootKey;
      if lReg.OpenKeyReadOnly(aRegKey) then
      begin
        if lReg.ValueExists(SFixInsightRegValue) then
          aOutValue := lReg.ReadString(SFixInsightRegValue);
      end;
    finally
      lReg.Free;
      lReg := nil;
    end;
    Result := aOutValue <> '';
  end;
begin
  aExePath := '';
  if FindInPath(SFixInsightExeName, aExePath) then
  begin
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoFixInsightPath, [aExePath]));
    Exit(True);
  end;

  for lRootIndex := 0 to High(CRoots) do
    for lViewIndex := 0 to High(CViews) do
      for lKeyIndex := 0 to High(CFixInsightRegKeys) do
      begin
        if not TryReadRegistryValue(CFixInsightRegKeys[lKeyIndex], CRoots[lRootIndex], CViews[lViewIndex], lValue) then
          Continue;
        lCandidate := BuildFromRegistry(lValue);
        if (lCandidate <> '') and FileExists(lCandidate) then
        begin
          aExePath := lCandidate;
          if aDiagnostics <> nil then
            aDiagnostics.AddInfo(Format(SInfoFixInsightPath, [aExePath]));
          Exit(True);
        end;
      end;

  Result := False;
end;

end.
