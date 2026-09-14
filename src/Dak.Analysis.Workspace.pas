unit Dak.Analysis.Workspace;

interface

uses
  System.JSON,
  Dak.Settings;

// The caller owns the returned snapshot. Capture it once and share it with report writers.
function CaptureWorkspaceIdentity(const aWorkspace: TWorkspaceSettings; const aScratchRoot: string = ''): TJSONObject;
function CaptureRunProvenance(const aWorkspace: TWorkspaceSettings;
  const aDakExecutable, aScratchRoot: string): TJSONObject;
// Shared handle-based identity for source resolution; missing paths retain absolute spelling.
function ResolveFilesystemPath(const aPath: string): string;
// Source inventory for report ownership; callers retain metadata failures as diagnostics.
function CollectAnalysisSourcePaths(const aRoot, aVcs, aScratchRoot: string): TArray<string>;

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.Hash, System.IOUtils,
  System.RegularExpressions, System.StrUtils, System.SysUtils,
  Xml.omnixmldom, Xml.XMLDoc, Xml.xmldom, Xml.XMLIntf,
  Winapi.Windows,
  AutoFree,
  Dak.ExternalToolProcess;

type
  TSourceInventoryMode = (simInclude, simMetadataOnly);

  TMetadataCapture = class(TThread)
  private
    fRead: array[0..1] of THandle;
    fWrite: array[0..1] of THandle;
    fData: array[0..1] of TMemoryStream;
    fOverflow: array[0..1] of Boolean;
    fStop: THandle;
    fError: string;
    procedure Drain(aIndex: Integer; aFinal: Boolean);
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Finish;
    function Text(aIndex: Integer): string;
  end;

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

procedure RaiseInventoryError(const aDirectory: string; aError: DWORD);
begin
  raise EInOutError.CreateFmt('Cannot enumerate workspace directory "%s": %s (Windows error %d).',
    [aDirectory, SysErrorMessage(aError), aError]);
end;

procedure RequireAcyclicJunction(const aRoot, aDirectory, aJunction: string);
var
  lAncestor: string;
  lParent: string;
  lRoot: string;
  lTarget: string;
begin
  lTarget := ResolveFilesystemPath(aJunction);
  lRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(aRoot));
  lAncestor := ExcludeTrailingPathDelimiter(TPath.GetFullPath(aDirectory));
  // Compare only ancestors, so independent aliases retain their reference inventory entries.
  while lAncestor <> '' do
  begin
    if SameText(ResolveFilesystemPath(lAncestor), lTarget) then
      raise EInOutError.CreateFmt('Cannot enumerate directory junction cycle at "%s".', [aJunction]);
    if SameText(lAncestor, lRoot) then
      Break;
    lParent := ExtractFileDir(lAncestor);
    if lParent = lAncestor then
      Break;
    lAncestor := lParent;
  end;
end;

function CollectFilesystemInputs(const aRoot: string; const aIncludeJunctions: Boolean = False): TArray<TSourceInput>;
const
  // Windows SDK winnt.h: directory junctions are mount-point reparse entries.
  cMountPointTag = $A0000003;
var
  g: TGarbos;
  lDirectory: string;
  lEntry: TSourceInput;
  lFiles: TList<TSourceInput>;
  lPending: TStack<string>;
  lSearch: TWin32FindData;
  lHandle: THandle;
  lName: string;
  lStatus: DWORD;
begin
  GC(lFiles, TList<TSourceInput>.Create, g);
  GC(lPending, TStack<string>.Create, g);
  lPending.Push(aRoot);
  while lPending.Count > 0 do
  begin
    lDirectory := lPending.Pop;
    RequireInventoryDirectory(lDirectory);
    lHandle := Winapi.Windows.FindFirstFile(PChar(TPath.Combine(lDirectory, '*')), lSearch);
    lStatus := 0;
    if lHandle = INVALID_HANDLE_VALUE then
      lStatus := GetLastError;
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
        lName := lSearch.cFileName;
        if not MatchText(lName, ['.', '..', '.dak', '.git', '.svn']) and
          (((lSearch.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) = 0) or
          (aIncludeJunctions and ((lSearch.dwFileAttributes and faDirectory) <> 0) and
          (lSearch.dwReserved0 = cMountPointTag))) then
        begin
          lEntry.fPath := TPath.Combine(lDirectory, lName);
          if (lSearch.dwFileAttributes and faDirectory) <> 0 then
          begin
            if aIncludeJunctions and ((lSearch.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
              RequireAcyclicJunction(aRoot, lDirectory, lEntry.fPath);
            lPending.Push(lEntry.fPath);
          end else if MatchText(ExtractFileExt(lName), ['.pas', '.dpr', '.dpk', '.inc']) then
          begin
            lEntry.fRelativeUtf8 := UTF8String(StringReplace(
              ExtractRelativePath(IncludeTrailingPathDelimiter(aRoot), lEntry.fPath), '\', '/', [rfReplaceAll]));
            lFiles.Add(lEntry);
          end;
        end;
        lStatus := 0;
        if not Winapi.Windows.FindNextFile(lHandle, lSearch) then
          lStatus := GetLastError;
      until lStatus <> 0;
      if lStatus <> ERROR_NO_MORE_FILES then
        RaiseInventoryError(lDirectory, lStatus);
    finally
      Winapi.Windows.FindClose(lHandle);
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

constructor TMetadataCapture.Create;
var
  i: Integer;
  lSecurity: TSecurityAttributes;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fStop := CreateEvent(nil, True, False, nil);
  if fStop = 0 then
    RaiseLastOSError;
  lSecurity := Default(TSecurityAttributes);
  lSecurity.nLength := SizeOf(lSecurity);
  lSecurity.bInheritHandle := True;
  for i := 0 to 1 do
  begin
    fData[i] := TMemoryStream.Create;
    if not CreatePipe(fRead[i], fWrite[i], @lSecurity, 65536) then
      RaiseLastOSError;
    if not SetHandleInformation(fRead[i], HANDLE_FLAG_INHERIT, 0) then
      RaiseLastOSError;
  end;
end;

destructor TMetadataCapture.Destroy;
var
  i: Integer;
begin
  if fStop <> 0 then
    SetEvent(fStop);
  // TThread also resumes/joins an instance whose constructor failed while suspended.
  inherited;
  for i := 0 to 1 do
  begin
    if fRead[i] <> 0 then
      CloseHandle(fRead[i]);
    if fWrite[i] <> 0 then
      CloseHandle(fWrite[i]);
    fData[i].Free;
  end;
  if fStop <> 0 then
    CloseHandle(fStop);
end;

procedure TMetadataCapture.Drain(aIndex: Integer; aFinal: Boolean);
const
  cLimits: array[0..1] of Integer = (64 * 1024 * 1024, 8 * 1024 * 1024);
var
  lAvailable: Cardinal;
  lBuffer: array[0..65535] of Byte;
  lCount: Cardinal;
  lRead: Cardinal;
begin
  if not PeekNamedPipe(fRead[aIndex], nil, 0, nil, @lAvailable, nil) then
  begin
    if GetLastError = ERROR_BROKEN_PIPE then
      Exit;
    RaiseLastOSError;
  end;
  // Alternate streams during execution. On completion drain only the buffered snapshot,
  // never wait for EOF from a descendant that inherited a writer.
  if not aFinal and (lAvailable > SizeOf(lBuffer)) then
    lAvailable := SizeOf(lBuffer);
  while lAvailable > 0 do
  begin
    lCount := lAvailable;
    if lCount > SizeOf(lBuffer) then
      lCount := SizeOf(lBuffer);
    if not ReadFile(fRead[aIndex], lBuffer, lCount, lRead, nil) then
      RaiseLastOSError;
    if lRead = 0 then
      raise EInOutError.Create('Workspace metadata pipe ended during capture.');
    if fData[aIndex].Size + lRead > cLimits[aIndex] then
      fOverflow[aIndex] := True;
    // Keep draining after overflow so the direct child can exit without blocking on a full pipe.
    if not fOverflow[aIndex] then
      fData[aIndex].WriteBuffer(lBuffer, lRead);
    Dec(lAvailable, lRead);
  end;
end;

procedure TMetadataCapture.Execute;
begin
  try
    repeat
      Drain(0, False);
      Drain(1, False);
    until WaitForSingleObject(fStop, 1) = WAIT_OBJECT_0;
    Drain(0, True);
    Drain(1, True);
  except
    on e: Exception do
      fError := e.ClassName + ': ' + e.Message; // Propagated after the caller joins this thread.
  end;
end;

procedure TMetadataCapture.Finish;
var
  i: Integer;
begin
  for i := 0 to 1 do
    if fWrite[i] <> 0 then
    begin
      CloseHandle(fWrite[i]);
      fWrite[i] := 0;
    end;
  SetEvent(fStop);
  WaitFor;
end;

function TMetadataCapture.Text(aIndex: Integer): string;
var
  lBytes: TBytes;
begin
  if fError <> '' then
    raise EInOutError.Create(fError);
  if fOverflow[aIndex] then
    raise EInOutError.Create('Workspace metadata output exceeds the capture limit.');
  // Decode complete raw buffers once, preserving NUL separators and split UTF-8 sequences.
  SetLength(lBytes, fData[aIndex].Size);
  fData[aIndex].Position := 0;
  if Length(lBytes) > 0 then
    fData[aIndex].ReadBuffer(lBytes[0], Length(lBytes));
  Result := TEncoding.UTF8.GetString(lBytes);
end;

function RunMetadataCommand(const aExePath, aArguments, aRoot, aScratchRoot: string): string;
var
  g: TGarbos;
  lCapture: TMetadataCapture;
  lError: string;
  lExitCode: Cardinal;
  lInput: THandle;
  lOptions: TExternalToolProcessRunOptions;
  lSecurity: TSecurityAttributes;
  lTimedOut: Boolean;
begin
  if not TDirectory.Exists(aScratchRoot) then
    raise EDirectoryNotFoundException.Create('Workspace metadata requires an existing caller-owned scratch directory.');
  // Pipes keep the inspected workspace unchanged, including when scratch is not ignored by its VCS.
  GC(lCapture, TMetadataCapture.Create, g);
  lCapture.Start;
  lSecurity := Default(TSecurityAttributes);
  lSecurity.nLength := SizeOf(lSecurity);
  lSecurity.bInheritHandle := True;
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
    lOptions.fStdOutHandle := lCapture.fWrite[0];
    lOptions.fStdErrHandle := lCapture.fWrite[1];
    lOptions.fCreationFlags := CREATE_NO_WINDOW;
    lOptions.fTimeoutSec := 30;
    try
      if not TryRunExternalToolProcess(lOptions, lExitCode, lTimedOut, lError) then
        raise EInOutError.Create(lError);
    finally
      lCapture.Finish;
    end;
    if lExitCode <> 0 then
      raise EInOutError.CreateFmt('%s %s failed in %s: %s (exit code %d)',
        [ExtractFileName(aExePath), aArguments, aRoot, Trim(lCapture.Text(1)), lExitCode]);
    Result := lCapture.Text(0);
  finally
    CloseHandle(lInput);
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

function ResolveGitExecutable: string;
const
  cGitLocationVariables: array[0..6] of string = (
    'GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE',
    'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE');
var
  lVariable: string;
begin
  for lVariable in cGitLocationVariables do
    if GetEnvironmentVariable(lVariable) <> '' then
      raise EInOutError.Create(lVariable + ' overrides selected workspace metadata; provenance is unavailable.');
  Result := FindMetadataExecutable('git.exe');
end;

function CollectAnalysisSourcePaths(const aRoot, aVcs, aScratchRoot: string): TArray<string>;
var
  lInput: TSourceInput;
  lInputs: TArray<TSourceInput>;
  lPaths: TList<string>;
begin
  if aRoot = '' then
    Exit(nil);
  if SameText(aVcs, 'git') then
    // Ownership indexes the selected repository, not its recursively expanded submodule inputs.
    lInputs := GitSourceInputs(ResolveGitExecutable, aRoot, aScratchRoot)
  else
    lInputs := CollectFilesystemInputs(aRoot, True);
  lPaths := TList<string>.Create;
  try
    for lInput in lInputs do
      if TFile.Exists(lInput.fPath) then
        lPaths.Add(ResolveFilesystemPath(lInput.fPath));
    Result := lPaths.ToArray;
  finally
    lPaths.Free;
  end;
end;

procedure AddGitMetadata(const aIdentity: TJSONObject; const aHead: string; const aChanged: TJSONArray);
begin
  aIdentity.AddPair('changed_files', aChanged);
  aIdentity.AddPair('dirty', TJSONBool.Create(aChanged.Count > 0));
  aIdentity.AddPair('head', aHead);
  aIdentity.AddPair('revision', aHead);
  aIdentity.AddPair('status', 'complete');
  aIdentity.AddPair('vcs', 'git');
  aIdentity.AddPair('capabilities', TJSONObject.Create
    .AddPair('changed_files', 'available')
    .AddPair('inventory', 'available')
    .AddPair('nested_roots', 'available')
    .AddPair('revision', 'available')
    .AddPair('status', 'available'));
end;

function GitSubmoduleStatus(const aExePath, aRoot, aScratchRoot: string): string;
var
  lEntry: string;
  lManifest: string;
  lOutput: string;
  lRequiresStatus: Boolean;
begin
  lManifest := TPath.Combine(aRoot, '.gitmodules');
  lRequiresStatus := TFile.Exists(lManifest) or TDirectory.Exists(lManifest);
  if not lRequiresStatus then
  begin
    // Git's recursive command starts shell helpers even for an ordinary repository.
    // Inspect the index, including conflict stages; a missing manifest does not rule out gitlinks.
    lOutput := '';
    try
      lOutput := RunMetadataCommand(aExePath, '--no-optional-locks ls-files --cached --stage -z',
        aRoot, aScratchRoot);
    except
      // This optional fast path must not replace the original command's result or diagnostic.
      on EInOutError do
        lRequiresStatus := True;
      on EOSError do
        lRequiresStatus := True;
    end;
    for lEntry in lOutput.Split([#0]) do
      if lEntry.StartsWith('160000 ') or lEntry.EndsWith(#9 + '.gitmodules') then
      begin
        lRequiresStatus := True;
        Break;
      end;
  end;
  Result := '';
  if lRequiresStatus then
    // Preserve errors from malformed, missing or conflicted manifests, including index-only manifests.
    Result := RunMetadataCommand(aExePath, '--no-optional-locks submodule status --recursive', aRoot, aScratchRoot);
end;

function GitSubmoduleRevision(const aLine, aPath: string): string;
var
  ch: Char;
  lSeparator: Integer;
  lSuffix: string;
begin
  if (aLine = '') or not CharInSet(aLine[1], [' ', '+', '-', 'U']) then
    raise EInOutError.Create('Git returned an invalid submodule state.');
  lSeparator := PosEx(' ', aLine, 2);
  Result := Copy(aLine, 2, lSeparator - 2);
  if (Length(Result) <> 40) and (Length(Result) <> 64) then
    raise EInOutError.Create('Git returned an invalid submodule revision.');
  for ch in Result do
    if not CharInSet(ch, ['0'..'9', 'a'..'f']) then
      raise EInOutError.Create('Git returned an invalid submodule revision.');
  // Consume the entire known index path before considering Git's optional description.
  // Spaces and parentheses belong to the path too (T-333).
  if Copy(aLine, lSeparator + 1, Length(aPath)) <> aPath then
    raise EInOutError.CreateFmt('Git submodule status does not match index path %s.', [aPath]);
  lSuffix := Copy(aLine, lSeparator + 1 + Length(aPath), MaxInt);
  if (lSuffix <> '') and not (CharInSet(aLine[1], [' ', '+']) and
    lSuffix.StartsWith(' (') and lSuffix.EndsWith(')')) then
    raise EInOutError.CreateFmt('Git returned an invalid submodule status suffix for %s.', [aPath]);
end;

procedure AddGitSubmoduleInputs(const aExePath, aRoot, aPrefix, aScratchRoot: string;
  const aLines: TArray<string>; var aNextLine: Integer;
  const aModules: TJSONArray; const aInputs: TList<TSourceInput>);
var
  lEntry: string;
  lInput: TSourceInput;
  lLastPath: string;
  lMapped: TSourceInput;
  lModulePath: string;
  lModuleRoot: string;
  lOutput: string;
  lPath: string;
  lRevision: string;
  lSeparator: Integer;
  lState: string;
  lStateCode: Char;
begin
  lOutput := RunMetadataCommand(aExePath, '--no-optional-locks ls-files --cached --stage -z',
    aRoot, aScratchRoot);
  lLastPath := '';
  // Git emits recursive status in index order, with one entry per conflict path.
  // Retain that order and its original command errors; never infer paths from display text.
  for lEntry in lOutput.Split([#0]) do
  begin
    if not lEntry.StartsWith('160000 ') then
      Continue;
    lSeparator := Pos(#9, lEntry);
    lPath := Copy(lEntry, lSeparator + 1, MaxInt);
    if (lSeparator = 0) or (lPath = '') or (Pos(#9, lPath) > 0) or
      (Pos(#10, lPath) > 0) or (Pos(#13, lPath) > 0) then
      raise EInOutError.Create('Git returned an unsupported Windows submodule index path.');
    if lPath = lLastPath then
      Continue;
    lLastPath := lPath;
    lModulePath := aPrefix + lPath;
    if aNextLine >= Length(aLines) then
      raise EInOutError.CreateFmt('Git submodule status is missing index path %s.', [lModulePath]);
    lRevision := GitSubmoduleRevision(aLines[aNextLine], lModulePath);
    lStateCode := aLines[aNextLine][1];
    Inc(aNextLine);
    case lStateCode of
      ' ': lState := 'clean';
      '+': lState := 'modified';
      '-': lState := 'uninitialized';
      'U': lState := 'conflict';
    end;
    aModules.AddElement(TJSONObject.Create
      .AddPair('path', lModulePath)
      .AddPair('revision', lRevision)
      .AddPair('state', lState));
    lModuleRoot := ResolveFilesystemPath(TPath.Combine(aRoot, lPath));
    if TDirectory.Exists(lModuleRoot) and (TFile.Exists(TPath.Combine(lModuleRoot, '.git')) or
      TDirectory.Exists(TPath.Combine(lModuleRoot, '.git'))) then
    begin
      GitRevision(aExePath, lModuleRoot, aScratchRoot);
      for lInput in GitSourceInputs(aExePath, lModuleRoot, aScratchRoot) do
      begin
        lMapped := lInput;
        lMapped.fRelativeUtf8 := UTF8String(lModulePath + '/') + lInput.fRelativeUtf8;
        aInputs.Add(lMapped);
      end;
      // Populated but inactive/conflicted modules retain their own inputs; Git does not recurse into them.
      if CharInSet(lStateCode, [' ', '+']) then
        AddGitSubmoduleInputs(aExePath, lModuleRoot, lModulePath + '/', aScratchRoot,
          aLines, aNextLine, aModules, aInputs);
    end;
  end;
end;

function GitIdentity(const aRoot, aScratchRoot: string): TJSONObject;
var
  g: TGarbos;
  lChanged: TJSONArray;
  lExePath: string;
  lHead: string;
  lLines: TArray<string>;
  lModules: TJSONArray;
  lNextLine: Integer;
  lOutput: string;
  lInputs: TList<TSourceInput>;
  lOrdered: TArray<TSourceInput>;
begin
  lExePath := ResolveGitExecutable;
  lHead := GitRevision(lExePath, aRoot, aScratchRoot);
  Result := TJSONObject.Create;
  try
    lModules := TJSONArray.Create;
    Result.AddPair('submodules', lModules);
    GC(lInputs, TList<TSourceInput>.Create, g);
    lInputs.AddRange(GitSourceInputs(lExePath, aRoot, aScratchRoot));
    lOutput := GitSubmoduleStatus(lExePath, aRoot, aScratchRoot);
    if lOutput <> '' then
    begin
      lLines := lOutput.Replace(#13, '').Split([#10], TStringSplitOptions.ExcludeEmpty);
      lNextLine := 0;
      AddGitSubmoduleInputs(lExePath, aRoot, '', aScratchRoot, lLines, lNextLine, lModules, lInputs);
      if lNextLine <> Length(lLines) then
        raise EInOutError.Create('Git returned submodule status entries outside the selected index tree.');
    end;
    lOrdered := lInputs.ToArray;
    TArray.Sort<TSourceInput>(lOrdered, TComparer<TSourceInput>.Construct(CompareSourceInputs));
    lChanged := GitChangedFiles(lExePath, aRoot, aScratchRoot);
    AddGitMetadata(Result, lHead, lChanged);
    Result.AddPair('root', aRoot);
    Result.AddPair('source_inputs', SourceIdentity(lOrdered, 'git-delphi-inputs-with-recursive-submodules'));
  except
    Result.Free;
    raise;
  end;
end;

function UnavailableIdentity(const aRoot, aVcs, aError: string;
  aInventoryMode: TSourceInventoryMode = TSourceInventoryMode.simInclude): TJSONObject;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('capabilities', TJSONObject.Create
      .AddPair('changed_files', 'unavailable')
      .AddPair('inventory', IfThen(aInventoryMode = TSourceInventoryMode.simInclude, 'fallback', 'unavailable'))
      .AddPair('nested_roots', 'unavailable')
      .AddPair('revision', 'unavailable')
      .AddPair('status', 'unavailable'));
    Result.AddPair('changed_files', TJSONNull.Create);
    Result.AddPair('diagnostic', aVcs + ' metadata unavailable: ' + aError);
    Result.AddPair('dirty', TJSONNull.Create);
    Result.AddPair('revision', TJSONNull.Create);
    Result.AddPair('root', aRoot);
    if aInventoryMode = TSourceInventoryMode.simInclude then
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

function FindSvnExecutable: string;
var
  lFilePart: PChar;
  lLength: Cardinal;
  lPath: string;
begin
  Result := GetEnvironmentVariable('DAK_SVN_EXE');
  if Result <> '' then
  begin
    if not TFile.Exists(Result) then
      Result := '';
    Exit;
  end;
  lPath := GetEnvironmentVariable('PATH');
  if lPath <> '' then
  begin
    lFilePart := nil;
    lLength := SearchPath(PChar(lPath), 'svn.exe', nil, 0, nil, lFilePart);
    if lLength > 0 then
    begin
      SetLength(Result, lLength);
      lLength := SearchPath(PChar(lPath), 'svn.exe', nil, Length(Result), PChar(Result), lFilePart);
      if (lLength > 0) and (lLength < Cardinal(Length(Result))) then
      begin
        SetLength(Result, lLength);
        Exit;
      end;
    end;
  end;
  Result := 'C:\Program Files\TortoiseSVN\bin\svn.exe';
  if not TFile.Exists(Result) then
    Result := '';
end;

function TrySvnCommand(const aExe, aArguments, aRoot, aScratch: string;
  out aOutput: string; const aErrors: TList<string>): Boolean;
begin
  Result := False;
  try
    // Forward slashes avoid a trailing Windows path separator escaping the closing quote.
    aOutput := RunMetadataCommand(aExe, aArguments + ' "' + aRoot.Replace('\', '/') + '"', aRoot, aScratch);
    Result := True;
  except
    on e: EInOutError do
      aErrors.Add(e.Message);
    on e: EOSError do
      aErrors.Add(e.Message);
  end;
end;

function TrySvnXml(const aExe, aArguments, aRoot, aScratch: string;
  out aDocument: IXMLDocument; const aErrors: TList<string>): Boolean;
var
  lOutput: string;
  lXml: TXMLDocument;
begin
  aDocument := nil;
  if not TrySvnCommand(aExe, aArguments, aRoot, aScratch, lOutput, aErrors) then
    Exit(False);
  Result := False;
  lXml := TXMLDocument.Create(nil);
  aDocument := lXml;
  lXml.DOMVendor := GetDOMVendor(sOmniXmlVendor);
  try
    aDocument.LoadFromXML(lOutput);
    Result := aDocument.DocumentElement <> nil;
    if not Result then
      aErrors.Add('SVN XML has no document element.');
  except
    on e: EDOMParseError do
      aErrors.Add(e.Message);
    on e: EXMLDocError do
      aErrors.Add(e.Message);
    on e: DOMException do
      aErrors.Add(e.Message);
  end;
end;

function XmlChild(const aNode: IXMLNode; const aName: string): IXMLNode;
begin
  Result := nil;
  if aNode <> nil then
    Result := aNode.ChildNodes.FindNode(aName);
end;

function XmlValue(const aNode: IXMLNode): string;
begin
  Result := '';
  if aNode <> nil then
    Result := aNode.Text;
end;

function XmlAttribute(const aNode: IXMLNode; const aName: string): string;
begin
  Result := '';
  if aNode <> nil then
    Result := XmlValue(aNode.AttributeNodes.FindNode(aName));
end;

procedure AddNullableText(const aObject: TJSONObject; const aName, aValue: string);
begin
  if aValue = '' then
    aObject.AddPair(aName, TJSONNull.Create)
  else
    aObject.AddPair(aName, aValue);
end;

function ReadSvnInfo(const aDocument: IXMLDocument; const aErrors: TList<string>): TJSONObject;
var
  lEntry: IXMLNode;
  lRepository: IXMLNode;
  lRoot: string;
  lUrl: string;
begin
  lEntry := XmlChild(aDocument.DocumentElement, 'entry');
  lRepository := XmlChild(lEntry, 'repository');
  lRoot := XmlValue(XmlChild(lRepository, 'root'));
  lUrl := XmlValue(XmlChild(lEntry, 'url'));
  if (lRoot = '') or (lUrl = '') then
  begin
    aErrors.Add('svn info did not identify a working copy');
    Exit(nil);
  end;
  Result := TJSONObject.Create;
  try
    Result.AddPair('url', lUrl);
    Result.AddPair('repository_root', lRoot);
    AddNullableText(Result, 'repository_uuid', XmlValue(XmlChild(lRepository, 'uuid')));
    AddNullableText(Result, 'root_revision', XmlAttribute(lEntry, 'revision'));
  except
    Result.Free;
    raise;
  end;
end;

function ReadSvnVersion(const aExe, aRoot, aScratch: string; const aErrors: TList<string>): TJSONObject;
var
  lFirst: Int64;
  lFlags: string;
  lLast: Int64;
  lMatch: TMatch;
  lOutput: string;
  lRevision: string;
begin
  Result := nil;
  if not TFile.Exists(aExe) then
  begin
    aErrors.Add('svnversion executable not found');
    Exit;
  end;
  if not TrySvnCommand(aExe, '', aRoot, aScratch, lOutput, aErrors) then
    Exit;
  lOutput := Trim(lOutput);
  lMatch := TRegEx.Match(lOutput, '\A(\d+)(?::(\d+))?([MSP]*)\z');
  if not lMatch.Success then
  begin
    aErrors.Add('unexpected svnversion output: ' + IfThen(lOutput = '', '<empty>', lOutput));
    Exit;
  end;
  lRevision := lMatch.Groups[1].Value;
  if not TryStrToInt64(lRevision, lFirst) then
  begin
    aErrors.Add('svnversion revision exceeds the supported integer range');
    Exit;
  end;
  lLast := lFirst;
  if lMatch.Groups[2].Value <> '' then
  begin
    if not TryStrToInt64(lMatch.Groups[2].Value, lLast) then
    begin
      aErrors.Add('svnversion revision exceeds the supported integer range');
      Exit;
    end;
    lRevision := lRevision + ':' + lMatch.Groups[2].Value;
  end;
  lFlags := lMatch.Groups[3].Value;
  Result := TJSONObject.Create
    .AddPair('raw', lOutput).AddPair('revision', lRevision)
    .AddPair('minimum', TJSONNumber.Create(lFirst)).AddPair('maximum', TJSONNumber.Create(lLast))
    .AddPair('modified', TJSONBool.Create(Pos('M', lFlags) > 0))
    .AddPair('switched', TJSONBool.Create(Pos('S', lFlags) > 0))
    .AddPair('sparse', TJSONBool.Create(Pos('P', lFlags) > 0));
end;

function SvnEntries(const aDocument: IXMLDocument): TArray<IXMLNode>;
var
  g: TGarbos;
  i: Integer;
  lEntries: TList<IXMLNode>;
  lNode: IXMLNode;
  lPending: TStack<IXMLNode>;
begin
  GC(lEntries, TList<IXMLNode>.Create, g);
  GC(lPending, TStack<IXMLNode>.Create, g);
  lPending.Push(aDocument.DocumentElement);
  while lPending.Count > 0 do
  begin
    lNode := lPending.Pop;
    if lNode.NodeName = 'entry' then
      lEntries.Add(lNode)
    else
      for i := lNode.ChildNodes.Count - 1 downto 0 do
        lPending.Push(lNode.ChildNodes[i]);
  end;
  Result := lEntries.ToArray;
end;

procedure AddSourcePath(const aPaths: TDictionary<string, TSourceInput>; const aRoot, aRelative: string);
var
  lInput: TSourceInput;
begin
  lInput.fRelativeUtf8 := UTF8String(aRelative.Replace('\', '/'));
  lInput.fPath := TPath.Combine(aRoot, aRelative);
  aPaths.AddOrSetValue(string(lInput.fRelativeUtf8), lInput);
end;

function OrderedSourcePaths(const aPaths: TDictionary<string, TSourceInput>): TArray<TSourceInput>;
begin
  Result := aPaths.Values.ToArray;
  TArray.Sort<TSourceInput>(Result, TComparer<TSourceInput>.Construct(CompareSourceInputs));
end;

function SourcePathsJson(const aPaths: TDictionary<string, TSourceInput>): TJSONArray;
var
  lInput: TSourceInput;
begin
  Result := TJSONArray.Create;
  try
    for lInput in OrderedSourcePaths(aPaths) do
      Result.Add(string(lInput.fRelativeUtf8));
  except
    Result.Free;
    raise;
  end;
end;

function SvnRelativePath(const aRoot, aValue: string): string;
var
  lPath: string;
begin
  lPath := aValue;
  if not TPath.IsPathRooted(lPath) then
    lPath := TPath.Combine(aRoot, lPath);
  lPath := ResolveFilesystemPath(lPath);
  if SameFileName(aRoot, lPath) then
    Result := '.'
  else if StartsText(IncludeTrailingPathDelimiter(aRoot), lPath) then
    Result := Copy(lPath, Length(IncludeTrailingPathDelimiter(aRoot)) + 1, MaxInt)
  else
    Result := lPath;
end;

procedure ReadSvnStatus(const aDocument: IXMLDocument; const aRoot: string;
  const aChanged, aSources, aExternals: TDictionary<string, TSourceInput>);
var
  lEntry: IXMLNode;
  lItem: string;
  lRelative: string;
  lStatus: IXMLNode;
begin
  for lEntry in SvnEntries(aDocument) do
  begin
    lStatus := XmlChild(lEntry, 'wc-status');
    if lStatus = nil then
      Continue;
    lRelative := SvnRelativePath(aRoot, XmlAttribute(lEntry, 'path'));
    lItem := XmlAttribute(lStatus, 'item');
    if lItem = 'external' then
    begin
      AddSourcePath(aExternals, aRoot, lRelative);
      Continue;
    end;
    if MatchStr(lItem, ['added', 'conflicted', 'deleted', 'incomplete', 'merged', 'missing', 'modified',
      'obstructed', 'replaced', 'unversioned']) or
      MatchStr(XmlAttribute(lStatus, 'props'), ['conflicted', 'modified']) then
      AddSourcePath(aChanged, aRoot, lRelative);
    if MatchStr(lItem, ['added', 'unversioned']) and
      MatchText(ExtractFileExt(lRelative), ['.pas', '.dpr', '.dpk', '.inc']) then
      AddSourcePath(aSources, aRoot, lRelative);
  end;
end;

function TryReadSvnStatus(const aDocument: IXMLDocument; const aRoot: string;
  const aChanged, aSources, aExternals: TDictionary<string, TSourceInput>; const aErrors: TList<string>): Boolean;
begin
  Result := False;
  try
    ReadSvnStatus(aDocument, aRoot, aChanged, aSources, aExternals);
    Result := True;
  except
    on e: EInOutError do
      aErrors.Add('svn status extraction failed: ' + e.Message);
    on e: EOSError do
      aErrors.Add('svn status extraction failed: ' + e.Message);
  end;
  if not Result then
  begin
    // Partial path lists cannot establish either clean status or complete external boundaries.
    aChanged.Clear;
    aSources.Clear;
    aExternals.Clear;
  end;
end;

function TryReadSvnInventory(const aDocument: IXMLDocument; const aRoot: string;
  const aSources: TDictionary<string, TSourceInput>; const aErrors: TList<string>): Boolean;
var
  lEntry: IXMLNode;
  lName: string;
begin
  Result := False;
  try
    for lEntry in SvnEntries(aDocument) do
    begin
      lName := SvnRelativePath(aRoot, XmlAttribute(lEntry, 'path'));
      if (XmlAttribute(lEntry, 'kind') = 'file') and
        MatchText(ExtractFileExt(lName), ['.pas', '.dpr', '.dpk', '.inc']) then
        AddSourcePath(aSources, aRoot, lName);
    end;
    Result := True;
  except
    on e: EInOutError do
      aErrors.Add('svn inventory extraction failed: ' + e.Message);
    on e: EOSError do
      aErrors.Add('svn inventory extraction failed: ' + e.Message);
  end;
end;

function SvnIdentity(const aRoot, aScratch: string): TJSONObject;
var
  g: TGarbos;
  lChanged: TDictionary<string, TSourceInput>;
  lDocument: IXMLDocument;
  lErrors: TList<string>;
  lExe: string;
  lExternals: TDictionary<string, TSourceInput>;
  lExternalJson: TJSONArray;
  lInfo: TJSONObject;
  lInput: TSourceInput;
  lInventory: Boolean;
  lInventoryDocument: IXMLDocument;
  lInventoryErrors: TList<string>;
  lName: string;
  lPair: TJSONPair;
  lRootFromInventory: Boolean;
  lSources: TDictionary<string, TSourceInput>;
  lStatus: Boolean;
  lVersion: TJSONObject;
begin
  lExe := FindSvnExecutable;
  if lExe = '' then
    Exit(UnavailableIdentity(aRoot, 'svn', 'svn executable not found'));
  GC(lErrors, TList<string>.Create, g);
  GC(lInventoryErrors, TList<string>.Create, g);
  GC(lChanged, TDictionary<string, TSourceInput>.Create, g);
  GC(lSources, TDictionary<string, TSourceInput>.Create, g);
  GC(lExternals, TDictionary<string, TSourceInput>.Create, g);
  lInfo := nil;
  // The recursive working-copy result also describes its root. Reuse that one observation.
  lInventory := TrySvnXml(lExe, 'info --xml --depth infinity', aRoot, aScratch, lInventoryDocument, lInventoryErrors);
  lRootFromInventory := False;
  if lInventory then
    lRootFromInventory := SameFileName(XmlAttribute(XmlChild(lInventoryDocument.DocumentElement, 'entry'),
      'path').Replace('/', '\'), aRoot);
  if lRootFromInventory then
    GC(lInfo, ReadSvnInfo(lInventoryDocument, lErrors), g)
  else if TrySvnXml(lExe, 'info --xml', aRoot, aScratch, lDocument, lErrors) then
    // A failed inventory must not discard independently available root metadata.
    GC(lInfo, ReadSvnInfo(lDocument, lErrors), g);
  GC(lVersion, ReadSvnVersion(TPath.Combine(ExtractFileDir(lExe), 'svnversion.exe'), aRoot, aScratch, lErrors), g);
  lStatus := TrySvnXml(lExe, 'status --xml', aRoot, aScratch, lDocument, lErrors);
  if lStatus then
    lStatus := TryReadSvnStatus(lDocument, aRoot, lChanged, lSources, lExternals, lErrors);
  lStatus := lStatus and (lInfo <> nil);
  // T-332: repository listing at a directory's BASE revision omits newer committed children.
  // Recursive info reads the working copy, including mixed revisions, without merging externals.
  // Publish diagnostics in their established info/version/status/inventory order.
  lErrors.AddRange(lInventoryErrors.ToArray);
  if lInventory then
    lInventory := TryReadSvnInventory(lInventoryDocument, aRoot, lSources, lErrors);
  lInventory := lInventory and lStatus;
  Result := TJSONObject.Create;
  try
    Result.AddPair('vcs', 'svn').AddPair('root', aRoot);
    if lInfo <> nil then
      for lPair in lInfo do
        Result.AddPair(lPair.JsonString.Value, lPair.JsonValue.Clone as TJSONValue)
    else
      for lName in ['url', 'repository_root', 'repository_uuid', 'root_revision'] do
        Result.AddPair(lName, TJSONNull.Create);
    if lVersion <> nil then
    begin
      Result.AddPair('revision', lVersion.GetValue<string>('revision'));
      Result.AddPair('svnversion', lVersion.Clone as TJSONObject);
    end else
      Result.AddPair('revision', TJSONNull.Create);
    if lStatus then
    begin
      Result.AddPair('dirty', TJSONBool.Create(lChanged.Count > 0));
      Result.AddPair('changed_files', SourcePathsJson(lChanged));
    end else begin
      Result.AddPair('dirty', TJSONNull.Create);
      Result.AddPair('changed_files', TJSONNull.Create);
    end;
    Result.AddPair('status', IfThen(lErrors.Count = 0, 'complete', 'unavailable'));
    Result.AddPair('capabilities', TJSONObject.Create
      .AddPair('revision', IfThen(lVersion <> nil, 'available', 'unavailable'))
      .AddPair('status', IfThen(lStatus, 'available', 'unavailable'))
      .AddPair('changed_files', IfThen(lStatus, 'available', 'unavailable'))
      .AddPair('inventory', IfThen(lInventory, 'available', 'fallback'))
      .AddPair('nested_roots', IfThen(lStatus, 'available', 'unavailable')));
    if lInventory then
      Result.AddPair('source_inputs', SourceIdentity(OrderedSourcePaths(lSources),
        'svn-versioned-plus-unversioned-delphi-inputs'))
    else
      Result.AddPair('source_inputs', SourceIdentity(CollectFilesystemInputs(aRoot), 'filesystem-delphi-inputs'));
    lExternalJson := TJSONArray.Create;
    Result.AddPair('externals', lExternalJson);
    for lInput in OrderedSourcePaths(lExternals) do
      lExternalJson.AddElement(TJSONObject.Create.AddPair('path', string(lInput.fRelativeUtf8)));
    if lErrors.Count > 0 then
      Result.AddPair('diagnostic', string.Join('; ', lErrors.ToArray));
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
  if SameText(aWorkspace.fVcs, 'svn') then
    Exit(SvnIdentity(lRoot, aScratchRoot));
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

function GitMetadataIdentity(const aRoot, aScratchRoot: string): TJSONObject;
var
  lExe: string;
  lHead: string;
begin
  lExe := ResolveGitExecutable;
  lHead := GitRevision(lExe, aRoot, aScratchRoot);
  Result := TJSONObject.Create;
  try
    AddGitMetadata(Result, lHead, GitChangedFiles(lExe, aRoot, aScratchRoot));
  except
    Result.Free;
    raise;
  end;
end;

function CaptureDakIdentity(const aRoot, aScratchRoot: string): TJSONObject;
begin
  if aRoot = '' then
    Exit(TJSONObject.Create.AddPair('vcs', 'none'));
  try
    Result := GitMetadataIdentity(aRoot, aScratchRoot);
  except
    on e: EInOutError do
      Result := UnavailableIdentity(aRoot, 'git', e.Message, TSourceInventoryMode.simMetadataOnly);
    on e: EOSError do
      Result := UnavailableIdentity(aRoot, 'git', e.Message, TSourceInventoryMode.simMetadataOnly);
  end;
end;

function ProjectDakIdentity(const aTarget: TJSONObject): TJSONObject;
begin
  Result := aTarget.Clone as TJSONObject;
  try
    Result.RemovePair('source_inputs').Free;
    Result.RemovePair('root').Free;
    Result.RemovePair('submodules').Free;
  except
    Result.Free;
    raise;
  end;
end;

// Delphi 12 has no CNG declarations. These signatures match the Windows SDK bcrypt.h.
function BCryptOpenAlgorithmProvider(out aAlgorithm: THandle; aAlgorithmId, aImplementation: PWideChar;
  aFlags: Cardinal): LongInt; stdcall; external 'bcrypt.dll';
function BCryptCloseAlgorithmProvider(aAlgorithm: THandle; aFlags: Cardinal): LongInt; stdcall; external 'bcrypt.dll';
function BCryptCreateHash(aAlgorithm: THandle; out aHash: THandle; aObject: PByte; aObjectSize: Cardinal;
  aSecret: PByte; aSecretSize, aFlags: Cardinal): LongInt; stdcall; external 'bcrypt.dll';
function BCryptHashData(aHash: THandle; aInput: PByte; aInputSize, aFlags: Cardinal): LongInt;
  stdcall; external 'bcrypt.dll';
function BCryptFinishHash(aHash: THandle; aOutput: PByte; aOutputSize, aFlags: Cardinal): LongInt;
  stdcall; external 'bcrypt.dll';
function BCryptDestroyHash(aHash: THandle): LongInt; stdcall; external 'bcrypt.dll';

procedure RequireHashSuccess(const aOperation: string; aStatus: LongInt);
begin
  if aStatus < 0 then
    raise EInOutError.CreateFmt('%s failed with NTSTATUS 0x%.8x.', [aOperation, Cardinal(aStatus)]);
end;

function ExecutableSha256(const aPath: string): string;
var
  g: TGarbos;
  lAlgorithm: THandle;
  lBuffer: TBytes;
  lCount: Integer;
  lDigest: TBytes;
  lHash: THandle;
  lStream: TFileStream;
begin
  // Hash fresh bytes with the same sharing mode as the RTL reference; never cache by timestamp.
  GC(lStream, TFileStream.Create(aPath, fmOpenRead or fmShareDenyNone), g);
  lAlgorithm := 0;
  RequireHashSuccess('BCryptOpenAlgorithmProvider', BCryptOpenAlgorithmProvider(lAlgorithm, 'SHA256', nil, 0));
  try
    lHash := 0;
    // CNG owns its hash-object buffer and releases it with the hash handle (Windows 7 and later).
    RequireHashSuccess('BCryptCreateHash', BCryptCreateHash(lAlgorithm, lHash, nil, 0, nil, 0, 0));
    try
      SetLength(lBuffer, 1024 * 1024);
      repeat
        lCount := lStream.Read(lBuffer[0], Length(lBuffer));
        if lCount > 0 then
          RequireHashSuccess('BCryptHashData', BCryptHashData(lHash, @lBuffer[0], lCount, 0));
      until lCount = 0;
      SetLength(lDigest, 32);
      RequireHashSuccess('BCryptFinishHash', BCryptFinishHash(lHash, @lDigest[0], Length(lDigest), 0));
      Result := LowerCase(THash.DigestAsString(lDigest));
    finally
      BCryptDestroyHash(lHash);
    end;
  finally
    BCryptCloseAlgorithmProvider(lAlgorithm, 0);
  end;
end;

function CaptureRunProvenance(const aWorkspace: TWorkspaceSettings;
  const aDakExecutable, aScratchRoot: string): TJSONObject;
var
  lDak: TJSONObject;
  lDakRoot: string;
  lExecutable: string;
  lTarget: TJSONObject;
begin
  lExecutable := ResolveFilesystemPath(aDakExecutable);
  lDakRoot := FindNamedRepoRoot(ExtractFileDir(lExecutable), '.git');
  if lDakRoot <> '' then
    lDakRoot := ResolveFilesystemPath(lDakRoot);
  Result := TJSONObject.Create;
  try
    lTarget := CaptureWorkspaceIdentity(aWorkspace, aScratchRoot);
    Result.AddPair('target', lTarget);
    if (lTarget.GetValue<string>('vcs') = 'git') and
      (lTarget.GetValue<string>('status') = 'complete') and
      SameFileName(lTarget.GetValue<string>('root'), lDakRoot) then
      // Both report views describe this one capture; retain separate JSON ownership for consumers.
      lDak := ProjectDakIdentity(lTarget)
    else
      lDak := CaptureDakIdentity(lDakRoot, aScratchRoot);
    Result.AddPair('dak', lDak);
    lDak.AddPair('executable', lExecutable);
    if TFile.Exists(lExecutable) then
      lDak.AddPair('executable_sha256', ExecutableSha256(lExecutable))
    else
      lDak.AddPair('executable_sha256', TJSONNull.Create);
  except
    Result.Free;
    raise;
  end;
end;

end.
