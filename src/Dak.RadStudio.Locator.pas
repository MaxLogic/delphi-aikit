unit Dak.RadStudio.Locator;

interface

function ResolveRsVarsPath(const aDelphiVersion, aOverridePath: string): string;
function ResolveBdsRoot(const aDelphiVersion, aRsVarsPath, aEnvironmentBdsRoot: string): string;
function ResolveRtlSourceRoot(const aDelphiVersion, aRsVarsPath: string): string;
function BuildDelphiLspCandidatePaths(const aDelphiVersion, aEnvironmentBlock: string): TArray<string>;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  DelphiSemantics.CompilerProfile;

function NormalizeDelphiVersion(const aValue: string): string;
begin
  Result := Trim(aValue);
  if (Result <> '') and (Pos('.', Result) = 0) then
    Result := Result + '.0';
end;

procedure AddUniquePath(const aPath: string; const aPaths: TList<string>);
var
  lPath: string;
begin
  lPath := Trim(aPath);
  if lPath = '' then
    Exit;
  lPath := TPath.GetFullPath(lPath);
  if not aPaths.Contains(lPath) then
    aPaths.Add(lPath);
end;

function HardcodedStudioRoot(const aDelphiVersion: string): string;
begin
  Result := TPath.Combine('C:\Program Files (x86)\Embarcadero\Studio', NormalizeDelphiVersion(aDelphiVersion));
end;

procedure AddEnvironmentInstallRootCandidates(const aDelphiVersion: string; const aPaths: TList<string>);
var
  lBase: string;
  lVersion: string;
begin
  lVersion := NormalizeDelphiVersion(aDelphiVersion);

  lBase := Trim(GetEnvironmentVariable('ProgramFiles(x86)'));
  if lBase <> '' then
  begin
    AddUniquePath(TPath.Combine(lBase, 'Embarcadero\Studio\' + lVersion), aPaths);
    AddUniquePath(TPath.Combine(lBase, 'Embarcadero\RAD Studio\' + lVersion), aPaths);
  end;

  lBase := Trim(GetEnvironmentVariable('ProgramFiles'));
  if lBase <> '' then
  begin
    AddUniquePath(TPath.Combine(lBase, 'Embarcadero\Studio\' + lVersion), aPaths);
    AddUniquePath(TPath.Combine(lBase, 'Embarcadero\RAD Studio\' + lVersion), aPaths);
  end;

end;

procedure AddInstallRootCandidates(const aDelphiVersion: string; const aPaths: TList<string>);
begin
  AddEnvironmentInstallRootCandidates(aDelphiVersion, aPaths);
  AddUniquePath(HardcodedStudioRoot(aDelphiVersion), aPaths);
end;

function EnvironmentBlockValue(const aEnvironmentBlock, aName: string): string;
var
  lEnd: Integer;
  lEntry: string;
  lPos: Integer;
  lStart: Integer;
begin
  Result := '';
  lStart := 1;
  while lStart <= Length(aEnvironmentBlock) do
  begin
    lEnd := PosEx(#0, aEnvironmentBlock, lStart);
    if lEnd = 0 then
      Break;
    if lEnd = lStart then
      Break;
    lEntry := Copy(aEnvironmentBlock, lStart, lEnd - lStart);
    lPos := Pos('=', lEntry);
    if (lPos > 1) and SameText(Copy(lEntry, 1, lPos - 1), aName) then
      Exit(Copy(lEntry, lPos + 1, MaxInt));
    lStart := lEnd + 1;
  end;
end;

function ResolveRsVarsPath(const aDelphiVersion, aOverridePath: string): string;
var
  lCandidate: string;
  lCandidates: TList<string>;
  lRoot: string;
begin
  if Trim(aOverridePath) <> '' then
    Exit(aOverridePath);

  lCandidates := TList<string>.Create;
  try
    AddEnvironmentInstallRootCandidates(aDelphiVersion, lCandidates);
    Result := '';
    for lRoot in lCandidates do
    begin
      lCandidate := TPath.Combine(lRoot, 'bin\rsvars.bat');
      Result := lCandidate;
      if FileExists(lCandidate) then
        Exit(lCandidate);
    end;
    if Result = '' then
      Result := TPath.Combine(HardcodedStudioRoot(aDelphiVersion), 'bin\rsvars.bat');
  finally
    lCandidates.Free;
  end;
end;

function ResolveBdsRoot(const aDelphiVersion, aRsVarsPath, aEnvironmentBdsRoot: string): string;
var
  lCandidate: string;
  lCandidates: TList<string>;
begin
  Result := Trim(aEnvironmentBdsRoot);
  if Result <> '' then
    Exit(TPath.GetFullPath(Result));

  if Trim(aRsVarsPath) <> '' then
    Exit(TPath.GetFullPath(ExtractFileDir(ExtractFileDir(aRsVarsPath))));

  lCandidates := TList<string>.Create;
  try
    AddEnvironmentInstallRootCandidates(aDelphiVersion, lCandidates);
    Result := '';
    for lCandidate in lCandidates do
    begin
      if DirectoryExists(lCandidate) then
        Exit(lCandidate);
    end;
    Result := HardcodedStudioRoot(aDelphiVersion);
  finally
    lCandidates.Free;
  end;
end;

function ResolveRtlSourceRoot(const aDelphiVersion, aRsVarsPath: string): string;
begin
  Result := TDelphiSemanticCompilerProfileBuilder.ResolveRtlSourceRoot(
    NormalizeDelphiVersion(aDelphiVersion), aRsVarsPath);
end;

function BuildDelphiLspCandidatePaths(const aDelphiVersion, aEnvironmentBlock: string): TArray<string>;
var
  lCandidates: TList<string>;
  lRoot: string;
  lRoots: TList<string>;
begin
  lRoots := TList<string>.Create;
  lCandidates := TList<string>.Create;
  try
    AddUniquePath(EnvironmentBlockValue(aEnvironmentBlock, 'BDS'), lRoots);
    AddInstallRootCandidates(aDelphiVersion, lRoots);

    for lRoot in lRoots do
    begin
      AddUniquePath(TPath.Combine(lRoot, 'DelphiLSP.exe'), lCandidates);
      AddUniquePath(TPath.Combine(lRoot, 'bin64\DelphiLSP.exe'), lCandidates);
      AddUniquePath(TPath.Combine(lRoot, 'bin\DelphiLSP.exe'), lCandidates);
    end;
    Result := lCandidates.ToArray;
  finally
    lCandidates.Free;
    lRoots.Free;
  end;
end;

end.
