unit Dak.Paths;

interface

const
  // DAK-385: hex characters of the random token that names a transient per-run directory below
  // .dak\<ProjectName>\ (remove-with\<token>, dfm-check\runs\<token>, refactor-transactions\<token>,
  // signature\<token>). The 32- to 38-character GUID forms these replaced spent the path budget that deep
  // project locations need. TryCreateDakRunDirectory creates the directory exclusively, so 32 random bits
  // cannot hand one directory to two runs.
  cDakRunTokenLength = 8;
  // The classic Windows path limit: MAX_PATH (260) less the terminating null. DAK and most tools it starts
  // (MSBuild, the Delphi compiler) are not long-path aware.
  cClassicPathLimit = 259;

// Shared ownership marker validation for builds and DFM checks.
function IsRepositoryRootDirectory(const aDirectory: string): Boolean;

function DakProjectRoot(const aProjectDir, aProjectName: string): string;
function DakProjectRootForProjectPath(const aProjectPath: string): string;
function DakProjectPath(const aDakProjectRoot: string; const aSegments: array of string): string;
function ExplicitPathOrDefault(const aExplicitPath, aDefaultPath: string): string;
// DAK-385: a fresh lowercase token of cDakRunTokenLength hex characters.
function NewDakRunToken: string;
// DAK-385: creates <aParentDir>\<token> exclusively (and aParentDir when missing), drawing a new token when the
// name is taken. A failure reports the parent and the reason in aError.
function TryCreateDakRunDirectory(const aParentDir: string; out aRunDir: string; out aError: string): Boolean;
// DAK-385: False, with a message naming the command, the path, its length and the limit, when aPath does not fit
// cClassicPathLimit. aTools names what needs the classic limit, for example 'MSBuild and the Delphi compiler'.
function TryCheckClassicPathLimit(const aCommand, aTools, aPath: string; out aError: string): Boolean;

implementation

uses
  System.Classes, System.IOUtils, System.SysUtils,
  Winapi.Windows,
  maxLogic.IOUtils,
  Dak.Utils;

const
  // A taken name is redrawn; after this many draws the parent is treated as unusable.
  cDakRunTokenAttempts = 100;
  cDakRunDirCreateFailed = 'DAK working directory could not be created under %s (%s)';
  cDakRunDirTokensExhausted = 'every drawn name was already taken';
  cDakPathTooLong = '%s path too long: %s is %d characters, and %s accept at most %d (the Windows MAX_PATH ' +
    'limit). Move the project to a shorter directory.';

function IsRepositoryRootDirectory(const aDirectory: string): Boolean;
var
  lGitPath: string;
  lLines: TArray<string>;
  lTarget: string;
begin
  lGitPath := TPath.Combine(aDirectory, '.git');
  Result := TDirectory.Exists(lGitPath) or TDirectory.Exists(TPath.Combine(aDirectory, '.svn'));
  if Result or not TFile.Exists(lGitPath) then
    Exit;
  // An unreadable or malformed marker cannot establish ownership; callers keep walking upwards.
  try
    lLines := TFile.ReadAllLines(lGitPath, TEncoding.UTF8);
    if (Length(lLines) <> 1) or not lLines[0].StartsWith('gitdir: ') then
      Exit(False);
    lTarget := Trim(Copy(lLines[0], Length('gitdir: ') + 1, MaxInt));
    if lTarget = '' then
      Exit(False);
    if not TPath.IsPathRooted(lTarget) then
      lTarget := TPath.Combine(aDirectory, lTarget);
    Result := TDirectory.Exists(TPath.GetFullPath(lTarget));
  except
    on E: EInOutError do
      Result := False;
    on E: EStreamError do
      Result := False;
    on E: EArgumentException do
      Result := False;
    on E: EEncodingError do
      Result := False;
  end;
end;

function NewDakRunToken: string;
begin
  Result := LowerCase(IntToHex(TGUID.NewGuid.D1, cDakRunTokenLength));
end;

function TryCreateDakRunDirectory(const aParentDir: string; out aRunDir: string; out aError: string): Boolean;
var
  lAttempt: Integer;
  lCandidate: string;
  lLastError: DWORD;
begin
  aRunDir := '';
  aError := '';
  try
    // The parent is shared by every run of the project; a concurrent run may create it first.
    TDirectory.CreateDirectory(LongPathSafe(aParentDir));
    lAttempt := 0;
    while lAttempt < cDakRunTokenAttempts do
    begin
      Inc(lAttempt);
      lCandidate := TPath.Combine(aParentDir, NewDakRunToken);
      // CreateDir fails on an existing name, so the directory we get is ours alone. The long-path form only
      // matters for creation; callers keep the readable path.
      if CreateDir(LongPathSafe(lCandidate)) then
      begin
        aRunDir := lCandidate;
        Exit(True);
      end;
      lLastError := GetLastError;
      if lLastError <> ERROR_ALREADY_EXISTS then
      begin
        aError := Format(cDakRunDirCreateFailed, [aParentDir, SysErrorMessage(lLastError)]);
        Exit(False);
      end;
    end;
    aError := Format(cDakRunDirCreateFailed, [aParentDir, cDakRunDirTokensExhausted]);
    Result := False;
  except
    on E: Exception do
    begin
      aError := Format(cDakRunDirCreateFailed, [aParentDir, E.Message]);
      Result := False;
    end;
  end;
end;

function TryCheckClassicPathLimit(const aCommand, aTools, aPath: string; out aError: string): Boolean;
begin
  aError := '';
  Result := Length(aPath) <= cClassicPathLimit;
  if not Result then
    aError := Format(cDakPathTooLong, [aCommand, aPath, Length(aPath), aTools, cClassicPathLimit]);
end;

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
