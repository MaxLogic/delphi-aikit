unit Dak.Utils;

interface

function ExeDir: string;
function NormalizeConfiguredPath(const aValue: string; const aBaseDir: string = ''): string;
function ResolveExePathFromConfiguredValue(const aValue, aExeName: string; const aBaseDir: string = ''): string;
function TryNormalizeInputPath(const aPath: string; out aNormalizedPath: string; out aError: string): Boolean;
function TryResolveAbsolutePath(const aInputPath: string; out aResolvedPath: string; out aError: string): Boolean;
function TryResolveDprojPath(const aInputPath: string; out aDprojPath: string; out aError: string): Boolean;

implementation

uses
  System.IOUtils, System.SysUtils,
  maxLogic.StrUtils,
  Dak.Messages;

function ExeDir: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

function EffectiveBaseDir(const aBaseDir: string): string;
begin
  Result := Trim(aBaseDir);
  if Result = '' then
    Result := ExeDir;
end;

function NormalizeConfiguredPath(const aValue: string; const aBaseDir: string = ''): string;
var
  lValue: string;
begin
  lValue := Trim(ExpandEnvVars(aValue));
  if lValue = '' then
    Exit('');
  if not TPath.IsPathRooted(lValue) then
    lValue := TPath.Combine(EffectiveBaseDir(aBaseDir), lValue);
  Result := lValue;
end;

function ResolveExePathFromConfiguredValue(const aValue, aExeName: string; const aBaseDir: string = ''): string;
var
  lValue: string;
begin
  lValue := NormalizeConfiguredPath(aValue, aBaseDir);
  if lValue = '' then
    Exit('');
  if SameText(TPath.GetExtension(lValue), '.exe') then
    Exit(lValue);
  Result := TPath.Combine(lValue, aExeName);
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

function TryResolveAbsolutePath(const aInputPath: string; out aResolvedPath: string; out aError: string): Boolean;
var
  lNormalizedPath: string;
begin
  aResolvedPath := '';
  aError := '';
  if not TryNormalizeInputPath(aInputPath, lNormalizedPath, aError) then
    Exit(False);
  aResolvedPath := TPath.GetFullPath(lNormalizedPath);
  Result := True;
end;

function TryResolveDprojPath(const aInputPath: string; out aDprojPath: string; out aError: string): Boolean;
var
  lCandidatePath: string;
  lExt: string;
begin
  aError := '';
  if not TryResolveAbsolutePath(aInputPath, aDprojPath, aError) then
    Exit(False);

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
    lCandidatePath := TPath.ChangeExtension(aDprojPath, '.dproj');
    if FileExists(lCandidatePath) then
    begin
      aDprojPath := lCandidatePath;
      Exit(True);
    end;
    aError := Format(SAssociatedDprojMissing, [aDprojPath]);
    Exit(False);
  end;

  aError := Format(SUnsupportedProjectInput, [aDprojPath]);
  Result := False;
end;

end.
