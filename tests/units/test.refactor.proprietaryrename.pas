unit Test.Refactor.ProprietaryRename;

interface

uses
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  DUnitX.TestFramework,
  Test.Support;

type
  [TestFixture]
  TRefactorProprietaryRenameTests = class
  private
    procedure AssertAppliedRename(const aRoot: TJSONObject; const aSymbol, aNewName: string);
    procedure AssertBytesEqual(const aExpected, aActual: TBytes; const aMessage: string);
    procedure AssertSnapshotUnchanged(const aPaths: TArray<string>; const aBytes: TArray<TBytes>;
      const aMessage: string);
    procedure CopyDirectoryToTemp(const aSourceDir, aTempName: string; out aCloneDir: string);
    function CommandExePath: string;
    function FindMaxTdbProject(const aFixtureDir: string): string;
    function IsIgnoredProjectArtifact(const aRelativePath: string): Boolean;
    function IsSourceSnapshotFile(const aPath: string): Boolean;
    function RunBuild(const aDprojPath, aLogName: string; out aExitCode: Cardinal): string;
    function RunRenameApply(const aDprojPath, aSymbol, aNewName, aLogName: string;
      out aExitCode: Cardinal): TJSONObject;
    procedure SnapshotSourceFiles(const aRootDir: string; out aPaths: TArray<string>;
      out aBytes: TArray<TBytes>);
  public
    [Test]
    procedure RenameApplyOnMaxTdbCloneBuildsAndPreservesOriginal;
  end;

implementation

procedure TRefactorProprietaryRenameTests.AssertAppliedRename(const aRoot: TJSONObject;
  const aSymbol, aNewName: string);
var
  lBackup: string;
  lFiles: TJSONArray;
  lManifestPath: string;
begin
  Assert.AreEqual('applied', aRoot.GetValue<string>('status', ''),
    'Expected applied rename status for ' + aSymbol + '.');
  Assert.AreEqual(aSymbol, aRoot.GetValue<string>('symbol', ''),
    'Expected output symbol for ' + aSymbol + '.');
  Assert.IsTrue(aRoot.GetValue<Integer>('editCount', 0) > 0,
    'Expected at least one rename edit for ' + aSymbol + '.');
  Assert.IsTrue(Pos(aNewName, aRoot.ToJSON) > 0,
    'Expected JSON output to contain new name ' + aNewName + '.');
  lFiles := aRoot.Values['appliedFiles'] as TJSONArray;
  Assert.IsTrue(lFiles.Count > 0, 'Expected applied file backups for ' + aSymbol + '.');
  lBackup := (lFiles.Items[0] as TJSONObject).GetValue<string>('backup', '');
  Assert.IsTrue(Pos('\.dak\maxtdb\rename\', LowerCase(lBackup)) > 0,
    'Expected project-scoped .dak rename backup for ' + aSymbol + ': ' + lBackup);
  Assert.IsTrue(TFile.Exists(lBackup), 'Expected backup file to exist for ' + aSymbol + ': ' + lBackup);
  lManifestPath := TPath.Combine(TPath.GetDirectoryName(TPath.GetDirectoryName(lBackup)), 'manifest.json');
  Assert.IsTrue(TFile.Exists(lManifestPath), 'Expected rename manifest for ' + aSymbol + ': ' + lManifestPath);
  Assert.IsTrue(Pos('"status":"applied"', TFile.ReadAllText(lManifestPath, TEncoding.UTF8)) > 0,
    'Expected applied status in manifest for ' + aSymbol + '.');
end;

procedure TRefactorProprietaryRenameTests.AssertBytesEqual(const aExpected, aActual: TBytes;
  const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aExpected), Length(aActual), aMessage + ' Size differs.');
  for i := 0 to High(aExpected) do
    Assert.AreEqual(aExpected[i], aActual[i], aMessage + ' Byte differs at index ' + i.ToString + '.');
end;

procedure TRefactorProprietaryRenameTests.AssertSnapshotUnchanged(const aPaths: TArray<string>;
  const aBytes: TArray<TBytes>; const aMessage: string);
var
  i: Integer;
begin
  Assert.AreEqual(Length(aPaths), Length(aBytes), aMessage + ' Snapshot shape differs.');
  for i := 0 to High(aPaths) do
  begin
    Assert.IsTrue(TFile.Exists(aPaths[i]), aMessage + ' Snapshot file disappeared: ' + aPaths[i]);
    AssertBytesEqual(aBytes[i], TFile.ReadAllBytes(aPaths[i]), aMessage + ' File changed: ' + aPaths[i]);
  end;
end;

procedure TRefactorProprietaryRenameTests.CopyDirectoryToTemp(const aSourceDir, aTempName: string;
  out aCloneDir: string);
var
  lFile: string;
  lRelativePath: string;
  lTargetFile: string;
begin
  aCloneDir := TPath.Combine(TempRoot, aTempName);
  if TDirectory.Exists(aCloneDir) then
    TDirectory.Delete(aCloneDir, True);
  TDirectory.CreateDirectory(aCloneDir);

  for lFile in TDirectory.GetFiles(aSourceDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(aSourceDir) + 2, MaxInt);
    if IsIgnoredProjectArtifact(lRelativePath) then
      Continue;

    lTargetFile := TPath.Combine(aCloneDir, lRelativePath);
    TDirectory.CreateDirectory(TPath.GetDirectoryName(lTargetFile));
    TFile.Copy(lFile, lTargetFile, True);
  end;
end;

function TRefactorProprietaryRenameTests.CommandExePath: string;
begin
  Result := TPath.Combine(RepoRoot, 'bin\DelphiAIKit.exe');
end;

function TRefactorProprietaryRenameTests.FindMaxTdbProject(const aFixtureDir: string): string;
var
  lProjectFile: string;
  lProjectFiles: TArray<string>;
  lPreferredPath: string;
begin
  lPreferredPath := TPath.Combine(TPath.Combine(aFixtureDir, 'src'), 'maxtdb.dproj');
  if TFile.Exists(lPreferredPath) then
    Exit(lPreferredPath);

  lProjectFiles := TDirectory.GetFiles(aFixtureDir, '*.dproj', TSearchOption.soAllDirectories);
  Assert.IsTrue(Length(lProjectFiles) > 0, 'Expected at least one maxTdb project file in: ' + aFixtureDir);
  for lProjectFile in lProjectFiles do
  begin
    if SameText(TPath.GetFileName(lProjectFile), 'maxtdb.dproj') then
      Exit(lProjectFile);
  end;
  Result := lProjectFiles[0];
end;

function TRefactorProprietaryRenameTests.IsIgnoredProjectArtifact(const aRelativePath: string): Boolean;
var
  lPath: string;
begin
  lPath := LowerCase(StringReplace(aRelativePath, '/', '\', [rfReplaceAll]));
  Result := StartsText('.dak\', lPath) or ContainsText(lPath, '\.dak\') or StartsText('.git\', lPath) or
    ContainsText(lPath, '\.git\') or StartsText('__history\', lPath) or ContainsText(lPath, '\__history\');
end;

function TRefactorProprietaryRenameTests.IsSourceSnapshotFile(const aPath: string): Boolean;
var
  lExt: string;
begin
  lExt := LowerCase(TPath.GetExtension(aPath));
  Result := (lExt = '.pas') or (lExt = '.dpr') or (lExt = '.dpk') or (lExt = '.inc') or (lExt = '.dfm') or
    (lExt = '.fmx') or (lExt = '.dproj') or (lExt = '.deployproj');
end;

function TRefactorProprietaryRenameTests.RunBuild(const aDprojPath, aLogName: string;
  out aExitCode: Cardinal): string;
var
  lArgs: string;
  lCmdArgs: string;
  lCmdExe: string;
  lLogPath: string;
  lOutputDir: string;
  lRsVarsPath: string;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lOutputDir := TPath.Combine(TempRoot, 'refactor-maxtdb-build-out');
  ForceDirectories(lOutputDir);
  lRsVarsPath := 'C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat';
  if not TFile.Exists(lRsVarsPath) then
    lRsVarsPath := TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'),
      'Embarcadero\Studio\23.0\bin\rsvars.bat');
  lArgs := 'build --project ' + QuoteArg(aDprojPath) +
    ' --delphi 23.0 --platform Win32 --config Debug --builder delphi --ai --rsvars ' +
    QuoteArg(lRsVarsPath) + ' --test-output-dir ' + QuoteArg(lOutputDir);
  lCmdExe := GetEnvironmentVariable('ComSpec');
  if lCmdExe = '' then
    lCmdExe := 'C:\Windows\System32\cmd.exe';
  lCmdArgs := '/C set "BDS=" & set "BDSLIB=" & set "DCC_Namespace=" & set "DCC_UnitSearchPath=" & ' +
    'set "DelphiLibraryPath=" & set "EnvOptions=" & ' + QuoteArg(CommandExePath) + ' ' + lArgs;
  Assert.IsTrue(RunProcess(lCmdExe, lCmdArgs, RepoRoot, lLogPath, aExitCode),
    'Failed to start maxTdb build process.');
  Result := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
end;

function TRefactorProprietaryRenameTests.RunRenameApply(const aDprojPath, aSymbol, aNewName,
  aLogName: string; out aExitCode: Cardinal): TJSONObject;
var
  lArgs: string;
  lLogPath: string;
  lOutput: string;
  lValue: TJSONValue;
begin
  EnsureResolverBuilt;
  lLogPath := TPath.Combine(TempRoot, aLogName);
  lArgs := 'rename --project ' + QuoteArg(aDprojPath) + ' --symbol ' + aSymbol + ' --new-name ' +
    aNewName + ' --apply --format json';
  Assert.IsTrue(RunProcess(CommandExePath, lArgs, TPath.GetDirectoryName(CommandExePath), lLogPath, aExitCode),
    'Failed to start maxTdb rename process for ' + aSymbol + '.');
  lOutput := TFile.ReadAllText(lLogPath, TEncoding.UTF8);
  lValue := TJSONObject.ParseJSONValue(lOutput);
  Assert.IsTrue(lValue is TJSONObject, 'Expected parseable maxTdb rename JSON. Output: ' + lOutput);
  Result := lValue as TJSONObject;
end;

procedure TRefactorProprietaryRenameTests.SnapshotSourceFiles(const aRootDir: string;
  out aPaths: TArray<string>; out aBytes: TArray<TBytes>);
var
  lCount: Integer;
  lFile: string;
  lRelativePath: string;
begin
  SetLength(aPaths, 0);
  SetLength(aBytes, 0);
  lCount := 0;
  for lFile in TDirectory.GetFiles(aRootDir, '*', TSearchOption.soAllDirectories) do
  begin
    lRelativePath := Copy(lFile, Length(aRootDir) + 2, MaxInt);
    if IsIgnoredProjectArtifact(lRelativePath) or not IsSourceSnapshotFile(lFile) then
      Continue;

    SetLength(aPaths, lCount + 1);
    SetLength(aBytes, lCount + 1);
    aPaths[lCount] := lFile;
    aBytes[lCount] := TFile.ReadAllBytes(lFile);
    Inc(lCount);
  end;
end;

procedure TRefactorProprietaryRenameTests.RenameApplyOnMaxTdbCloneBuildsAndPreservesOriginal;
var
  lBuildExitCode: Cardinal;
  lBuildOutput: string;
  lCloneDir: string;
  lDprojPath: string;
  lExitCode: Cardinal;
  lOriginalBytes: TArray<TBytes>;
  lOriginalPaths: TArray<string>;
  lRoot: TJSONObject;
  lSourceDir: string;
begin
  lSourceDir := TPath.Combine(RepoRoot, 'tests\fixtures\test-projects\maxTdb');
  if not TDirectory.Exists(lSourceDir) then
  begin
    Assert.Pass('Optional proprietary maxTdb fixture is absent; no maxTdb rename dogfood check was run.');
    Exit;
  end;

  SnapshotSourceFiles(lSourceDir, lOriginalPaths, lOriginalBytes);
  Assert.IsTrue(Length(lOriginalPaths) > 0, 'Expected maxTdb source files to snapshot.');

  CopyDirectoryToTemp(lSourceDir, 'refactor-maxtdb-rename', lCloneDir);
  lDprojPath := FindMaxTdbProject(lCloneDir);

  lRoot := RunRenameApply(lDprojPath, 'ScanURL', 'ScanHttpUrl', 'refactor-maxtdb-rename-scanurl.json',
    lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected ScanURL rename to succeed.');
    AssertAppliedRename(lRoot, 'ScanURL', 'ScanHttpUrl');
  finally
    lRoot.Free;
  end;

  lRoot := RunRenameApply(lDprojPath, 'TCacheItem', 'TRenameDogfoodCacheItem',
    'refactor-maxtdb-rename-cacheitem.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected TCacheItem rename to succeed.');
    AssertAppliedRename(lRoot, 'TCacheItem', 'TRenameDogfoodCacheItem');
  finally
    lRoot.Free;
  end;

  lRoot := RunRenameApply(lDprojPath, 'Soundex', 'RenameDogfoodSoundex',
    'refactor-maxtdb-rename-soundex.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected Soundex rename to succeed.');
    AssertAppliedRename(lRoot, 'Soundex', 'RenameDogfoodSoundex');
  finally
    lRoot.Free;
  end;

  lRoot := RunRenameApply(lDprojPath, 'ArrayVarRecPtr', 'TRenameDogfoodArrayVarRecPtr',
    'refactor-maxtdb-rename-arrayvarrecptr.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected ArrayVarRecPtr rename to succeed.');
    AssertAppliedRename(lRoot, 'ArrayVarRecPtr', 'TRenameDogfoodArrayVarRecPtr');
  finally
    lRoot.Free;
  end;

  lRoot := RunRenameApply(lDprojPath, 'AllFiles', 'RenameDogfoodAllFiles',
    'refactor-maxtdb-rename-allfiles.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected AllFiles rename to succeed.');
    AssertAppliedRename(lRoot, 'AllFiles', 'RenameDogfoodAllFiles');
  finally
    lRoot.Free;
  end;

  lRoot := RunRenameApply(lDprojPath, 'SourceVarRecPtr', 'TRenameDogfoodSourceVarRecPtr',
    'refactor-maxtdb-rename-sourcevarrecptr.json', lExitCode);
  try
    Assert.AreEqual(Cardinal(0), lExitCode, 'Expected SourceVarRecPtr rename to succeed.');
    AssertAppliedRename(lRoot, 'SourceVarRecPtr', 'TRenameDogfoodSourceVarRecPtr');
  finally
    lRoot.Free;
  end;

  lBuildOutput := RunBuild(lDprojPath, 'refactor-maxtdb-rename-build.log', lBuildExitCode);
  Assert.AreEqual(Cardinal(0), lBuildExitCode, 'Expected renamed maxTdb clone to build. Output: ' + lBuildOutput);

  AssertSnapshotUnchanged(lOriginalPaths, lOriginalBytes,
    'Original proprietary maxTdb fixture must never be edited.');
end;

initialization
  TDUnitX.RegisterTestFixture(TRefactorProprietaryRenameTests);

end.
