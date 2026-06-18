unit Dak.Paths;

interface

function DakProjectRoot(const aProjectDir, aProjectName: string): string;
function DakProjectRootForProjectPath(const aProjectPath: string): string;
function DakProjectPath(const aDakProjectRoot: string; const aSegments: array of string): string;
function ExplicitPathOrDefault(const aExplicitPath, aDefaultPath: string): string;

implementation

uses
  System.IOUtils, System.SysUtils,
  maxLogic.IOUtils;

function DakProjectRoot(const aProjectDir, aProjectName: string): string;
begin
  Result := CombinePath([aProjectDir, '.dak', aProjectName]);
end;

function DakProjectRootForProjectPath(const aProjectPath: string): string;
var
  lProjectPath: string;
begin
  lProjectPath := TPath.GetFullPath(aProjectPath);
  Result := DakProjectRoot(TPath.GetDirectoryName(lProjectPath),
    TPath.GetFileNameWithoutExtension(lProjectPath));
end;

function DakProjectPath(const aDakProjectRoot: string; const aSegments: array of string): string;
var
  i: Integer;
  lParts: TArray<string>;
begin
  SetLength(lParts, Length(aSegments) + 1);
  lParts[0] := aDakProjectRoot;
  for i := 0 to High(aSegments) do
    lParts[i + 1] := aSegments[i];
  Result := CombinePath(lParts);
end;

function ExplicitPathOrDefault(const aExplicitPath, aDefaultPath: string): string;
begin
  if aExplicitPath <> '' then
    Exit(aExplicitPath);
  Result := aDefaultPath;
end;

end.
