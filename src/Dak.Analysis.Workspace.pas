unit Dak.Analysis.Workspace;

interface

uses
  System.JSON,
  Dak.Settings;

// The caller owns the returned snapshot. Capture it once and share it with report writers.
function CaptureWorkspaceIdentity(const aWorkspace: TWorkspaceSettings; const aScratchRoot: string = ''): TJSONObject;

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.Hash, System.IOUtils,
  System.StrUtils, System.SysUtils,
  Winapi.Windows,
  AutoFree,
  Dak.ExternalToolProcess;

type
  TSourceInput = record
    fPath: string;
    fRelativeUtf8: UTF8String;
  end;

// DAK is a Windows Win64 tool; handle-based identity deliberately uses the Windows API.
{$WARN SYMBOL_PLATFORM OFF}
function ResolveFilesystemPath(const aPath: string): string;
var
  lHandle: THandle;
  lLength: Cardinal;
begin
  Result := TPath.GetFullPath(aPath);
  lHandle := CreateFile(PChar(Result), 0, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
  if lHandle = INVALID_HANDLE_VALUE then
  begin
    // Like the reference's non-strict resolution, a missing path retains its absolute spelling.
    if (GetLastError = ERROR_FILE_NOT_FOUND) or (GetLastError = ERROR_PATH_NOT_FOUND) then
      Exit;
    RaiseLastOSError;
  end;
  try
    lLength := GetFinalPathNameByHandle(lHandle, nil, 0, 0);
    if lLength = 0 then
      RaiseLastOSError;
    SetLength(Result, lLength);
    lLength := GetFinalPathNameByHandle(lHandle, PChar(Result), Length(Result), 0);
    if lLength = 0 then
      RaiseLastOSError;
    if lLength >= Cardinal(Length(Result)) then
      raise EInOutError.Create('Filesystem path changed while resolving workspace identity.');
    SetLength(Result, lLength);
  finally
    CloseHandle(lHandle);
  end;
  if StartsText('\\?\UNC\', Result) then
    Result := '\\' + Copy(Result, 9, MaxInt)
  else if StartsText('\\?\', Result) then
    Delete(Result, 1, 4);
end;
{$WARN SYMBOL_PLATFORM ON}

function CompareSourceInputs(const aLeft, aRight: TSourceInput): Integer;
var
  i: Integer;
  lLimit: Integer;
begin
  // UTF-8 byte order matches Python's Unicode scalar ordering, including supplementary characters.
  lLimit := Length(aLeft.fRelativeUtf8);
  if Length(aRight.fRelativeUtf8) < lLimit then
    lLimit := Length(aRight.fRelativeUtf8);
  for i := 1 to lLimit do
  begin
    Result := Ord(aLeft.fRelativeUtf8[i]) - Ord(aRight.fRelativeUtf8[i]);
    if Result <> 0 then
      Exit;
  end;
  Result := Length(aLeft.fRelativeUtf8) - Length(aRight.fRelativeUtf8);
end;

procedure RequireInventoryDirectory(const aDirectory: string);
var
  lAttributes: DWORD;
  lError: DWORD;
begin
  lAttributes := GetFileAttributes(PChar(aDirectory));
  if lAttributes = INVALID_FILE_ATTRIBUTES then
  begin
    lError := GetLastError;
    raise EInOutError.CreateFmt('Cannot inspect workspace directory "%s": %s (Windows error %d).',
      [aDirectory, SysErrorMessage(lError), lError]);
  end;
  if (lAttributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then
    raise EInOutError.CreateFmt('Workspace inventory requires a directory: "%s".', [aDirectory]);
end;

procedure RaiseInventoryError(const aDirectory: string; aError: Integer);
begin
  raise EInOutError.CreateFmt('Cannot enumerate workspace directory "%s": %s (Windows error %d).',
    [aDirectory, SysErrorMessage(aError), aError]);
end;

function CollectFilesystemInputs(const aRoot: string): TArray<TSourceInput>;
var
  g: TGarbos;
  lDirectory: string;
  lEntry: TSourceInput;
  lFiles: TList<TSourceInput>;
  lPending: TStack<string>;
  lSearch: TSearchRec;
  lStatus: Integer;
begin
  GC(lFiles, TList<TSourceInput>.Create, g);
  GC(lPending, TStack<string>.Create, g);
  lPending.Push(aRoot);
  while lPending.Count > 0 do
  begin
    lDirectory := lPending.Pop;
    RequireInventoryDirectory(lDirectory);
    lStatus := FindFirst(TPath.Combine(lDirectory, '*'), faAnyFile, lSearch);
    if lStatus = ERROR_FILE_NOT_FOUND then
    begin
      // Recheck before accepting an empty directory: it may have disappeared during enumeration.
      RequireInventoryDirectory(lDirectory);
      Continue;
    end;
    if lStatus <> 0 then
      RaiseInventoryError(lDirectory, lStatus);
    try
      repeat
        if not MatchText(lSearch.Name, ['.', '..', '.dak', '.git', '.svn']) and
          ((lSearch.Attr and FILE_ATTRIBUTE_REPARSE_POINT) = 0) then
        begin
          lEntry.fPath := TPath.Combine(lDirectory, lSearch.Name);
          if (lSearch.Attr and faDirectory) <> 0 then
            lPending.Push(lEntry.fPath)
          else if MatchText(ExtractFileExt(lSearch.Name), ['.pas', '.dpr', '.dpk', '.inc']) then
          begin
            lEntry.fRelativeUtf8 := UTF8String(StringReplace(
              ExtractRelativePath(IncludeTrailingPathDelimiter(aRoot), lEntry.fPath), '\', '/', [rfReplaceAll]));
            lFiles.Add(lEntry);
          end;
        end;
        lStatus := FindNext(lSearch);
      until lStatus <> 0;
      if lStatus <> ERROR_NO_MORE_FILES then
        RaiseInventoryError(lDirectory, lStatus);
    finally
      System.SysUtils.FindClose(lSearch);
    end;
  end;
  Result := lFiles.ToArray;
  TArray.Sort<TSourceInput>(Result, TComparer<TSourceInput>.Construct(CompareSourceInputs));
end;

procedure HashSourceInput(var aHash: THashSHA2; const aInput: TSourceInput; var aBuffer: TBytes);
const
  cZero: Byte = 0;
var
  g: TGarbos;
  lCount: Integer;
  lHeader: UTF8String;
  lStream: TFileStream;
begin
  aHash.Update(aInput.fRelativeUtf8[1], Length(aInput.fRelativeUtf8));
  aHash.Update(cZero, 1);
  if TFile.Exists(aInput.fPath) then
  begin
    GC(lStream, TFileStream.Create(aInput.fPath, fmOpenRead or fmShareDenyNone), g);
    lHeader := UTF8String(IntToStr(lStream.Size));
    aHash.Update(lHeader[1], Length(lHeader));
    aHash.Update(cZero, 1);
    repeat
      lCount := lStream.Read(aBuffer[0], Length(aBuffer));
      if lCount > 0 then
        aHash.Update(aBuffer[0], lCount);
    until lCount = 0;
  end else
    aHash.Update('missing');
  aHash.Update(cZero, 1);
end;

function SourceIdentity(const aInputs: TArray<TSourceInput>; const aScope: string): TJSONObject;
var
  lBuffer: TBytes;
  lHash: THashSHA2;
  lInput: TSourceInput;
begin
  lHash := THashSHA2.Create;
  SetLength(lBuffer, 1024 * 1024);
  for lInput in aInputs do
    HashSourceInput(lHash, lInput, lBuffer);
  Result := TJSONObject.Create;
  try
    Result.AddPair('file_count', TJSONNumber.Create(Length(aInputs)));
    Result.AddPair('scope', aScope);
    Result.AddPair('sha256', LowerCase(lHash.HashAsString));
  except
    Result.Free;
    raise;
  end;
end;

function FindMetadataExecutable(const aName: string): string;
var
  lFilePart: PChar;
  lLength: Cardinal;
begin
  lFilePart := nil;
  lLength := SearchPath(nil, PChar(aName), nil, 0, nil, lFilePart);
  if lLength = 0 then
    raise EFileNotFoundException.Create(aName + ' not found on PATH');
  SetLength(Result, lLength);
  lLength := SearchPath(nil, PChar(aName), nil, Length(Result), PChar(Result), lFilePart);
  if (lLength = 0) or (lLength >= Cardinal(Length(Result))) then
    raise EFileNotFoundException.Create(aName + ' changed while resolving PATH');
  SetLength(Result, lLength);
end;

function CreateCaptureHandle(const aPath: string; const aSecurity: TSecurityAttributes): THandle;
begin
  // Unique files are removed by Windows after the last inherited handle closes.
  Result := CreateFile(PChar(aPath), GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_DELETE,
    @aSecurity, CREATE_NEW, FILE_ATTRIBUTE_TEMPORARY or FILE_FLAG_DELETE_ON_CLOSE, 0);
  if Result = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
end;

function ReadCapture(const aHandle: THandle; aLimit: Integer): string;
var
  g: TGarbos;
  lBytes: TBytes;
  lStream: THandleStream;
begin
  GC(lStream, THandleStream.Create(aHandle), g);
  if lStream.Size > aLimit then
    raise EInOutError.Create('Workspace metadata output exceeds the capture limit.');
  SetLength(lBytes, lStream.Size);
  lStream.Position := 0;
  if Length(lBytes) > 0 then
    lStream.ReadBuffer(lBytes[0], Length(lBytes));
  // Decode only after capture so multibyte characters and NUL separators survive chunk boundaries.
  Result := TEncoding.UTF8.GetString(lBytes);
end;

function RunMetadataCommand(const aExePath, aArguments, aRoot, aScratchRoot: string): string;
var
  lError: string;
  lErrHandle: THandle;
  lExitCode: Cardinal;
  lGuid: TGUID;
  lInput: THandle;
  lOptions: TExternalToolProcessRunOptions;
  lOutHandle: THandle;
  lPrefix: string;
  lSecurity: TSecurityAttributes;
  lTimedOut: Boolean;
begin
  if not TDirectory.Exists(aScratchRoot) then
    raise EDirectoryNotFoundException.Create('Workspace metadata requires an existing caller-owned scratch directory.');
  CreateGUID(lGuid);
  lPrefix := TPath.Combine(aScratchRoot, GUIDToString(lGuid));
  lSecurity := Default(TSecurityAttributes);
  lSecurity.nLength := SizeOf(lSecurity);
  lSecurity.bInheritHandle := True;
  lOutHandle := CreateCaptureHandle(lPrefix + '.stdout', lSecurity);
  try
    lErrHandle := CreateCaptureHandle(lPrefix + '.stderr', lSecurity);
    try
      lInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
        @lSecurity, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
      if lInput = INVALID_HANDLE_VALUE then
        RaiseLastOSError;
      try
        lOptions := Default(TExternalToolProcessRunOptions);
        lOptions.fExePath := aExePath;
        lOptions.fArguments := aArguments;
        lOptions.fWorkDir := aRoot;
        lOptions.fStdInHandle := lInput;
        lOptions.fStdOutHandle := lOutHandle;
        lOptions.fStdErrHandle := lErrHandle;
        lOptions.fCreationFlags := CREATE_NO_WINDOW;
        lOptions.fTimeoutSec := 30;
        if not TryRunExternalToolProcess(lOptions, lExitCode, lTimedOut, lError) then
          raise EInOutError.Create(lError);
        if lExitCode <> 0 then
          raise EInOutError.CreateFmt('%s %s failed in %s: %s (exit code %d)',
            [ExtractFileName(aExePath), aArguments, aRoot, Trim(ReadCapture(lErrHandle, 8 * 1024 * 1024)), lExitCode]);
        Result := ReadCapture(lOutHandle, 64 * 1024 * 1024);
      finally
        CloseHandle(lInput);
      end;
    finally
      CloseHandle(lErrHandle);
    end;
  finally
    CloseHandle(lOutHandle);
  end;
end;

function GitSourceInputs(const aExePath, aRoot, aScratchRoot: string): TArray<TSourceInput>;
var
  g: TGarbos;
  lEntry: TSourceInput;
  lFiles: TDictionary<string, TSourceInput>;
  lName: string;
  lOutput: string;
begin
  GC(lFiles, TDictionary<string, TSourceInput>.Create, g);
  lOutput := RunMetadataCommand(aExePath,
    '--no-optional-locks ls-files -z --cached --others --exclude-standard', aRoot, aScratchRoot);
  for lName in lOutput.Split([#0]) do
    if (lName <> '') and MatchText(ExtractFileExt(lName), ['.pas', '.dpr', '.dpk', '.inc']) then
    begin
      lEntry.fRelativeUtf8 := UTF8String(StringReplace(lName, '\', '/', [rfReplaceAll]));
      lEntry.fPath := TPath.Combine(aRoot, lName);
      lFiles.AddOrSetValue(string(lEntry.fRelativeUtf8), lEntry);
    end;
  Result := lFiles.Values.ToArray;
  TArray.Sort<TSourceInput>(Result, TComparer<TSourceInput>.Construct(CompareSourceInputs));
end;

function GitChangedFiles(const aExePath, aRoot, aScratchRoot: string): TJSONArray;
var
  g: TGarbos;
  i: Integer;
  lEntry: TSourceInput;
  lFiles: TDictionary<string, TSourceInput>;
  lInputs: TArray<TSourceInput>;
  lOutput: string;
  lParts: TArray<string>;
begin
  GC(lFiles, TDictionary<string, TSourceInput>.Create, g);
  lOutput := RunMetadataCommand(aExePath,
    '--no-optional-locks status --porcelain=v1 -z --untracked-files=all', aRoot, aScratchRoot);
  lParts := lOutput.Split([#0]);
  i := 0;
  while i < Length(lParts) do
  begin
    if Length(lParts[i]) >= 4 then
    begin
      lEntry.fRelativeUtf8 := UTF8String(StringReplace(Copy(lParts[i], 4, MaxInt), '\', '/', [rfReplaceAll]));
      lFiles.AddOrSetValue(string(lEntry.fRelativeUtf8), lEntry);
      if CharInSet(lParts[i][1], ['R', 'C']) or CharInSet(lParts[i][2], ['R', 'C']) then
        Inc(i); // Porcelain -z places the old name after the retained destination name.
    end;
    Inc(i);
  end;
  lInputs := lFiles.Values.ToArray;
  TArray.Sort<TSourceInput>(lInputs, TComparer<TSourceInput>.Construct(CompareSourceInputs));
  Result := TJSONArray.Create;
  try
    for lEntry in lInputs do
      Result.Add(string(lEntry.fRelativeUtf8));
  except
    Result.Free;
    raise;
  end;
end;

function GitRevision(const aExePath, aRoot, aScratchRoot: string): string;
var
  lActualRoot: string;
  lFields: TArray<string>;
  lOutput: string;
begin
  lOutput := RunMetadataCommand(aExePath, '--no-optional-locks rev-parse --show-toplevel HEAD', aRoot, aScratchRoot);
  lFields := lOutput.Replace(#13, '').Split([#10]);
  if Length(lFields) < 2 then
    raise EInOutError.Create('Git did not return a workspace root and revision.');
  lActualRoot := ResolveFilesystemPath(lFields[0]);
  if not SameFileName(lActualRoot, aRoot) then
    raise EInOutError.CreateFmt('Git resolved workspace %s instead of selected workspace %s.', [lActualRoot, aRoot]);
  Result := Trim(lFields[1]);
end;

function GitIdentity(const aRoot, aScratchRoot: string): TJSONObject;
const
  cGitLocationVariables: array[0..6] of string = (
    'GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE',
    'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE');
var
  g: TGarbos;
  lChanged: TJSONArray;
  lExePath: string;
  lHead: string;
  lOutput: string;
  lLine: string;
  lFields: TArray<string>;
  lState: string;
  lModules: TJSONArray;
  lModulePath: string;
  lModuleRoot: string;
  lInput: TSourceInput;
  lMapped: TSourceInput;
  lInputs: TList<TSourceInput>;
  lOrdered: TArray<TSourceInput>;
  lVariable: string;
begin
  for lVariable in cGitLocationVariables do
    if GetEnvironmentVariable(lVariable) <> '' then
      raise EInOutError.Create(lVariable + ' overrides selected workspace metadata; provenance is unavailable.');
  lExePath := FindMetadataExecutable('git.exe');
  lHead := GitRevision(lExePath, aRoot, aScratchRoot);
  Result := TJSONObject.Create;
  try
    lModules := TJSONArray.Create;
    Result.AddPair('submodules', lModules);
    GC(lInputs, TList<TSourceInput>.Create, g);
    lInputs.AddRange(GitSourceInputs(lExePath, aRoot, aScratchRoot));
    lOutput := RunMetadataCommand(lExePath, '--no-optional-locks submodule status --recursive', aRoot, aScratchRoot);
    for lLine in lOutput.Replace(#13, '').Split([#10]) do
    begin
      if lLine = '' then
        Continue;
      lFields := Copy(lLine, 2, MaxInt).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      if Length(lFields) < 2 then
        Continue;
      case lLine[1] of
        ' ': lState := 'clean';
        '+': lState := 'modified';
        '-': lState := 'uninitialized';
        'U': lState := 'conflict';
      else
        lState := 'unknown';
      end;
      lModulePath := lFields[1].Replace('\', '/');
      lModules.AddElement(TJSONObject.Create
        .AddPair('path', lModulePath)
        .AddPair('revision', lFields[0])
        .AddPair('state', lState));
      lModuleRoot := ResolveFilesystemPath(TPath.Combine(aRoot, lModulePath));
      if TDirectory.Exists(lModuleRoot) and (TFile.Exists(TPath.Combine(lModuleRoot, '.git')) or
        TDirectory.Exists(TPath.Combine(lModuleRoot, '.git'))) then
      begin
        GitRevision(lExePath, lModuleRoot, aScratchRoot);
        for lInput in GitSourceInputs(lExePath, lModuleRoot, aScratchRoot) do
        begin
          lMapped := lInput;
          lMapped.fRelativeUtf8 := UTF8String(lModulePath + '/') + lInput.fRelativeUtf8;
          lInputs.Add(lMapped);
        end;
      end;
    end;
    lOrdered := lInputs.ToArray;
    TArray.Sort<TSourceInput>(lOrdered, TComparer<TSourceInput>.Construct(CompareSourceInputs));
    lChanged := GitChangedFiles(lExePath, aRoot, aScratchRoot);
    Result.AddPair('changed_files', lChanged);
    Result.AddPair('dirty', TJSONBool.Create(lChanged.Count > 0));
    Result.AddPair('head', lHead);
    Result.AddPair('revision', lHead);
    Result.AddPair('root', aRoot);
    Result.AddPair('source_inputs', SourceIdentity(lOrdered, 'git-delphi-inputs-with-recursive-submodules'));
    Result.AddPair('status', 'complete');
    Result.AddPair('vcs', 'git');
    Result.AddPair('capabilities', TJSONObject.Create
      .AddPair('changed_files', 'available')
      .AddPair('inventory', 'available')
      .AddPair('nested_roots', 'available')
      .AddPair('revision', 'available')
      .AddPair('status', 'available'));
  except
    Result.Free;
    raise;
  end;
end;

function UnavailableIdentity(const aRoot, aVcs, aError: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('capabilities', TJSONObject.Create
      .AddPair('changed_files', 'unavailable')
      .AddPair('inventory', 'fallback')
      .AddPair('nested_roots', 'unavailable')
      .AddPair('revision', 'unavailable')
      .AddPair('status', 'unavailable'));
    Result.AddPair('changed_files', TJSONNull.Create);
    Result.AddPair('diagnostic', aVcs + ' metadata unavailable: ' + aError);
    Result.AddPair('dirty', TJSONNull.Create);
    Result.AddPair('revision', TJSONNull.Create);
    Result.AddPair('root', aRoot);
    Result.AddPair('source_inputs', SourceIdentity(CollectFilesystemInputs(aRoot), 'filesystem-delphi-inputs'));
    Result.AddPair('status', 'unavailable');
    Result.AddPair('vcs', aVcs);
    if aVcs = 'git' then
    begin
      Result.AddPair('head', TJSONNull.Create);
      Result.AddPair('submodules', TJSONArray.Create);
    end else if aVcs = 'svn' then
      Result.AddPair('externals', TJSONArray.Create);
  except
    Result.Free;
    raise;
  end;
end;

function CaptureWorkspaceIdentity(const aWorkspace: TWorkspaceSettings; const aScratchRoot: string): TJSONObject;
var
  lRoot: string;
begin
  lRoot := ResolveFilesystemPath(aWorkspace.fRoot);
  if SameText(aWorkspace.fVcs, 'git') then
  begin
    try
      Exit(GitIdentity(lRoot, aScratchRoot));
    except
      on e: EInOutError do
        Exit(UnavailableIdentity(lRoot, 'git', e.Message));
      on e: EOSError do
        Exit(UnavailableIdentity(lRoot, 'git', e.Message));
    end;
  end;
  if not SameText(aWorkspace.fVcs, 'none') then
    raise ENotSupportedException.Create('T-322: native VCS provenance is not implemented yet.');
  Result := TJSONObject.Create;
  try
    Result.AddPair('capabilities', TJSONObject.Create
      .AddPair('changed_files', 'not_applicable')
      .AddPair('inventory', 'available')
      .AddPair('nested_roots', 'not_applicable')
      .AddPair('revision', 'not_applicable')
      .AddPair('status', 'not_applicable'));
    Result.AddPair('changed_files', TJSONNull.Create);
    Result.AddPair('dirty', TJSONNull.Create);
    Result.AddPair('revision', TJSONNull.Create);
    Result.AddPair('root', lRoot);
    Result.AddPair('source_inputs', SourceIdentity(CollectFilesystemInputs(lRoot), 'filesystem-delphi-inputs'));
    Result.AddPair('status', 'not_applicable');
    Result.AddPair('vcs', 'none');
  except
    Result.Free;
    raise;
  end;
end;

end.
