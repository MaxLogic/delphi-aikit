unit Dak.DfmCheck;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.RegularExpressions, System.StrUtils, System.SysUtils,
  System.Win.Registry,
  Winapi.Windows,
  DfmCheck_DfmCheck, DfmCheck_Options, DfmCheck_Utils, ToolsAPIRepl,
  Dak.FixInsightSettings, Dak.Messages, Dak.RsVars, Dak.Types;

type
  TDfmCheckErrorCategory = (
    ecNone,
    ecInvalidInput,
    ecToolNotFound,
    ecDfmCheckFailed,
    ecGeneratorIncompatible,
    ecGeneratedProjectMissing,
    ecInjectFilesMissing,
    ecDprPatchFailed,
    ecBuildFailed,
    ecValidatorNotFound,
    ecValidatorFailed
  );

  TDfmCheckPaths = record
    fProjectDproj: string;
    fProjectDir: string;
    fProjectName: string;
    fGeneratedDir: string;
    fGeneratedDproj: string;
    fGeneratedDpr: string;
    fInjectDir: string;
    fInjectAutoFree: string;
    fInjectDfmStreamAll: string;
  end;

  TDfmCheckOutputProc = reference to procedure(const aLine: string);

  IDfmCheckProcessRunner = interface
    ['{ACB2FBB2-D818-4F75-B0D1-A6E6CAEA3A54}']
    function Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
      const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
  end;

function TryResolveDfmCheckProjectPath(const aInputPath: string; out aDprojPath: string; out aError: string): Boolean;
function BuildExpectedDfmCheckPaths(const aDprojPath: string): TDfmCheckPaths;
function TryLocateGeneratedDfmCheckProject(var aPaths: TDfmCheckPaths; out aError: string): Boolean;
function TryPatchDfmCheckDpr(const aInputText: string; out aOutputText: string; out aChanged: Boolean;
  out aError: string): Boolean;
function MapDfmCheckExitCode(const aCategory: TDfmCheckErrorCategory; const aToolExitCode: Integer): Integer;
function RunDfmCheckPipeline(const aOptions: TAppOptions; const aRunner: IDfmCheckProcessRunner;
  const aOutput: TDfmCheckOutputProc; out aCategory: TDfmCheckErrorCategory; out aError: string): Integer;
function RunDfmCheckCommand(const aOptions: TAppOptions): Integer;

implementation

type
  TWinProcessRunner = class(TInterfacedObject, IDfmCheckProcessRunner)
  public
    function Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
      const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
  end;

function QuoteCmdArg(const aValue: string): string;
var
  lNeedsQuotes: Boolean;
begin
  lNeedsQuotes := (aValue = '') or (Pos(' ', aValue) > 0) or (Pos(#9, aValue) > 0) or (Pos('"', aValue) > 0);
  if not lNeedsQuotes then
    Exit(aValue);
  Result := '"' + StringReplace(aValue, '"', '""', [rfReplaceAll]) + '"';
end;

function SameTextAt(const aText: string; const aNeedle: string; const aIndex: Integer): Boolean;
begin
  if aIndex < 1 then
    Exit(False);
  if (aIndex + Length(aNeedle) - 1) > Length(aText) then
    Exit(False);
  Result := SameText(Copy(aText, aIndex, Length(aNeedle)), aNeedle);
end;

function LastPosText(const aNeedle: string; const aText: string): Integer;
var
  lIndex: Integer;
begin
  Result := 0;
  if (aNeedle = '') or (aText = '') then
    Exit(0);
  lIndex := Length(aText) - Length(aNeedle) + 1;
  while lIndex >= 1 do
  begin
    if SameTextAt(aText, aNeedle, lIndex) then
      Exit(lIndex);
    Dec(lIndex);
  end;
end;

function ContainsWord(const aText: string; const aWord: string): Boolean;
begin
  Result := TRegEx.IsMatch(aText, '\b' + TRegEx.Escape(aWord) + '\b', [roIgnoreCase]);
end;

procedure EmitLine(const aOutput: TDfmCheckOutputProc; const aLine: string);
begin
  if Assigned(aOutput) then
    aOutput(aLine)
  else
    WriteLn(aLine);
end;

function IsCmdScript(const aPath: string): Boolean;
var
  lExt: string;
begin
  lExt := LowerCase(TPath.GetExtension(aPath));
  Result := (lExt = '.bat') or (lExt = '.cmd');
end;

function TryResolveAbsolutePath(const aInputPath: string; out aOutputPath: string; out aError: string): Boolean; forward;

function IsTrueValue(const aValue: string): Boolean;
var
  lValue: string;
begin
  lValue := Trim(LowerCase(aValue));
  Result := (lValue = '1') or (lValue = 'true') or (lValue = 'yes') or (lValue = 'on');
end;

function ShouldKeepArtifacts: Boolean;
begin
  Result := IsTrueValue(GetEnvironmentVariable('DAK_DFMCHECK_KEEP_ARTIFACTS'));
end;

function TryFindExecutableInPath(const aExeName: string; out aExePath: string): Boolean;
var
  lFilePart: PChar;
  lLength: Cardinal;
  lBuffer: TArray<Char>;
begin
  aExePath := '';
  lFilePart := nil;
  lLength := SearchPath(nil, PChar(aExeName), nil, 0, nil, lFilePart);
  if lLength = 0 then
    Exit(False);
  SetLength(lBuffer, lLength);
  if SearchPath(nil, PChar(aExeName), nil, lLength, PChar(lBuffer), lFilePart) = 0 then
    Exit(False);
  aExePath := string(PChar(lBuffer));
  Result := aExePath <> '';
end;

function TryFindMsBuildFromRegistry(out aMsBuildPath: string): Boolean;
const
  CRegistryKeys: array [0 .. 4] of string = (
    'SOFTWARE\Microsoft\MSBuild\ToolsVersions\Current',
    'SOFTWARE\Microsoft\MSBuild\ToolsVersions\17.0',
    'SOFTWARE\Microsoft\MSBuild\ToolsVersions\16.0',
    'SOFTWARE\Microsoft\MSBuild\ToolsVersions\15.0',
    'SOFTWARE\Microsoft\MSBuild\ToolsVersions\14.0'
  );
  CRegistryViews: array [0 .. 1] of Cardinal = (
    KEY_WOW64_64KEY,
    KEY_WOW64_32KEY
  );
var
  lCandidatePath: string;
  lKey: string;
  lKeyIndex: Integer;
  lRegistry: TRegistry;
  lToolsPath: string;
  lViewIndex: Integer;
begin
  aMsBuildPath := '';
  for lViewIndex := Low(CRegistryViews) to High(CRegistryViews) do
  begin
    lRegistry := TRegistry.Create(KEY_READ or CRegistryViews[lViewIndex]);
    try
      lRegistry.RootKey := HKEY_LOCAL_MACHINE;
      for lKeyIndex := Low(CRegistryKeys) to High(CRegistryKeys) do
      begin
        lKey := CRegistryKeys[lKeyIndex];
        if not lRegistry.OpenKeyReadOnly(lKey) then
          Continue;
        try
          if lRegistry.ValueExists('MSBuildToolsPath') then
            lToolsPath := Trim(lRegistry.ReadString('MSBuildToolsPath'))
          else
            lToolsPath := '';
        finally
          lRegistry.CloseKey;
        end;
        if lToolsPath = '' then
          Continue;
        lCandidatePath := TPath.Combine(lToolsPath, 'MSBuild.exe');
        if FileExists(lCandidatePath) then
        begin
          aMsBuildPath := TPath.GetFullPath(lCandidatePath);
          Exit(True);
        end;
      end;
    finally
      lRegistry.Free;
    end;
  end;
  Result := False;
end;

function TryResolveMsBuildPath(const aMsBuildOverride: string; out aMsBuildPath: string; out aError: string): Boolean;
var
  lHasPathMarkers: Boolean;
  lOverride: string;
  lPath: string;
begin
  aError := '';
  aMsBuildPath := '';
  lOverride := Trim(aMsBuildOverride);

  if lOverride <> '' then
  begin
    lHasPathMarkers := (Pos('\', lOverride) > 0) or (Pos('/', lOverride) > 0) or (Pos(':', lOverride) > 0);
    if not lHasPathMarkers then
    begin
      aMsBuildPath := lOverride;
      Exit(True);
    end;

    if TryFindExecutableInPath(lOverride, lPath) then
    begin
      aMsBuildPath := lPath;
      Exit(True);
    end;

    if not TryResolveAbsolutePath(lOverride, lPath, aError) then
      Exit(False);
    if FileExists(lPath) then
    begin
      aMsBuildPath := lPath;
      Exit(True);
    end;
    aError := 'MSBuild override not found: ' + lOverride;
    Exit(False);
  end;

  if TryFindExecutableInPath('msbuild.exe', lPath) then
  begin
    aMsBuildPath := lPath;
    Exit(True);
  end;

  if TryFindMsBuildFromRegistry(lPath) then
  begin
    aMsBuildPath := lPath;
    Exit(True);
  end;

  aError := 'MSBuild.exe not found. Provide --rsvars or set DAK_DFMCHECK_MSBUILD.';
  Result := False;
end;

procedure CleanupFile(const aFilePath: string; var aErrors: string);
begin
  if (aFilePath = '') or (not FileExists(aFilePath)) then
    Exit;
  try
    TFile.Delete(aFilePath);
  except
    on E: Exception do
    begin
      if aErrors <> '' then
        aErrors := aErrors + '; ';
      aErrors := aErrors + 'Delete file failed (' + aFilePath + '): ' + E.Message;
    end;
  end;
end;

procedure CleanupDirectory(const aDirPath: string; var aErrors: string);
begin
  if (aDirPath = '') or (not DirectoryExists(aDirPath)) then
    Exit;
  try
    TDirectory.Delete(aDirPath, True);
  except
    on E: Exception do
    begin
      if aErrors <> '' then
        aErrors := aErrors + '; ';
      aErrors := aErrors + 'Delete directory failed (' + aDirPath + '): ' + E.Message;
    end;
  end;
end;

procedure CleanupGeneratedArtifacts(const aPaths: TDfmCheckPaths; const aCopiedAutoFree: Boolean;
  const aCopiedDfmStreamAll: Boolean; const aValidatorExePath: string; const aOutput: TDfmCheckOutputProc);
var
  lBasePath: string;
  lCmdsPath: string;
  lDirectBasePath: string;
  lErrors: string;
  lGeneratedDirName: string;
  lProjectDirNormalized: string;
  lGeneratedDirNormalized: string;
begin
  lErrors := '';
  lBasePath := TPath.ChangeExtension(aPaths.fGeneratedDpr, '');
  lDirectBasePath := TPath.Combine(aPaths.fProjectDir, aPaths.fProjectName + '_DfmCheck');

  CleanupFile(aPaths.fGeneratedDpr, lErrors);
  CleanupFile(aPaths.fGeneratedDproj, lErrors);
  CleanupFile(TPath.ChangeExtension(aPaths.fGeneratedDpr, '.cfg'), lErrors);
  CleanupFile(TPath.ChangeExtension(aPaths.fGeneratedDpr, '.res'), lErrors);
  CleanupFile(lBasePath + '_Unit.pas', lErrors);
  CleanupFile(lDirectBasePath + '.dpr', lErrors);
  CleanupFile(lDirectBasePath + '.dproj', lErrors);
  CleanupFile(lDirectBasePath + '.cfg', lErrors);
  CleanupFile(lDirectBasePath + '.res', lErrors);
  CleanupFile(lDirectBasePath + '_Unit.pas', lErrors);
  CleanupFile(aValidatorExePath, lErrors);

  if aCopiedAutoFree then
    CleanupFile(TPath.Combine(aPaths.fGeneratedDir, 'autoFree.pas'), lErrors);
  if aCopiedDfmStreamAll then
    CleanupFile(TPath.Combine(aPaths.fGeneratedDir, 'DfmStreamAll.pas'), lErrors);

  lCmdsPath := TPath.Combine(aPaths.fProjectDir, 'Bin\' + TPath.GetFileName(lBasePath) + '.cmds');
  CleanupFile(lCmdsPath, lErrors);
  if aPaths.fGeneratedDir <> '' then
  begin
    lCmdsPath := TPath.Combine(aPaths.fGeneratedDir, 'Bin\' + TPath.GetFileName(lBasePath) + '.cmds');
    CleanupFile(lCmdsPath, lErrors);
  end;

  lGeneratedDirNormalized := ExcludeTrailingPathDelimiter(aPaths.fGeneratedDir);
  lProjectDirNormalized := ExcludeTrailingPathDelimiter(aPaths.fProjectDir);
  if (lGeneratedDirNormalized <> '') and (not SameText(lGeneratedDirNormalized, lProjectDirNormalized)) then
  begin
    lGeneratedDirName := ExtractFileName(lGeneratedDirNormalized);
    if EndsText('_DfmCheck', lGeneratedDirName) then
      CleanupDirectory(lGeneratedDirNormalized, lErrors);
  end;

  if lErrors <> '' then
    EmitLine(aOutput, '[dfm-check] Cleanup warning: ' + lErrors)
  else
    EmitLine(aOutput, '[dfm-check] Cleanup complete.');
end;

function BuildExpectedDfmCheckPaths(const aDprojPath: string): TDfmCheckPaths;
begin
  Result := Default(TDfmCheckPaths);
  Result.fProjectDproj := TPath.GetFullPath(aDprojPath);
  Result.fProjectDir := ExcludeTrailingPathDelimiter(ExtractFilePath(Result.fProjectDproj));
  Result.fProjectName := TPath.GetFileNameWithoutExtension(Result.fProjectDproj);
  Result.fGeneratedDir := TPath.Combine(Result.fProjectDir, Result.fProjectName + '_DfmCheck');
  Result.fGeneratedDproj := TPath.Combine(Result.fGeneratedDir, Result.fProjectName + '_DfmCheck.dproj');
  Result.fGeneratedDpr := TPath.Combine(Result.fGeneratedDir, Result.fProjectName + '_DfmCheck.dpr');
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

function TryResolveAbsolutePath(const aInputPath: string; out aOutputPath: string; out aError: string): Boolean;
var
  lNormalizedPath: string;
begin
  aOutputPath := '';
  aError := '';
  if not TryNormalizeInputPath(aInputPath, lNormalizedPath, aError) then
    Exit(False);
  aOutputPath := TPath.GetFullPath(lNormalizedPath);
  Result := True;
end;

function TryResolveDfmCheckProjectPath(const aInputPath: string; out aDprojPath: string; out aError: string): Boolean;
var
  lExt: string;
  lCandidatePath: string;
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

function TryResolveInjectDir(out aInjectDir: string; out aError: string): Boolean;
var
  lExeDir: string;
  lInjectOverride: string;
  lInjectCandidates: TArray<string>;
  lCandidate: string;
begin
  aInjectDir := '';
  aError := '';

  lInjectOverride := Trim(GetEnvironmentVariable('DAK_DFMCHECK_INJECT_DIR'));
  if lInjectOverride <> '' then
  begin
    if not TryResolveAbsolutePath(lInjectOverride, aInjectDir, aError) then
      Exit(False);
    if not DirectoryExists(aInjectDir) then
    begin
      aError := 'Inject directory not found: ' + aInjectDir;
      Exit(False);
    end;
    Exit(True);
  end;

  lExeDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  lInjectCandidates := [
    TPath.Combine(lExeDir, 'tools\inject'),
    TPath.Combine(TPath.GetFullPath(TPath.Combine(lExeDir, '..')), 'tools\inject'),
    TPath.Combine(TPath.GetFullPath(TPath.Combine(lExeDir, '..')), 'docs\delphi-dfm-checker\tools\inject')
  ];

  for lCandidate in lInjectCandidates do
  begin
    if DirectoryExists(lCandidate) then
    begin
      aInjectDir := lCandidate;
      Exit(True);
    end;
  end;

  aError := 'Inject directory not found. Expected tools\inject next to DelphiAIKit.';
  Result := False;
end;

function TryResolveGeneratorProjectPath(const aDprojPath: string; out aSourceProjectPath: string;
  out aMainSourceRaw: string; out aError: string): Boolean;
var
  lCandidatePath: string;
  lDprojDir: string;
  lDprojText: string;
  lMatch: TMatch;
begin
  aSourceProjectPath := '';
  aMainSourceRaw := '';
  aError := '';

  lCandidatePath := TPath.ChangeExtension(aDprojPath, '.dpr');
  if FileExists(lCandidatePath) then
  begin
    aSourceProjectPath := lCandidatePath;
    aMainSourceRaw := ExtractFileName(lCandidatePath);
    Exit(True);
  end;

  lDprojText := TFile.ReadAllText(aDprojPath);
  lMatch := TRegEx.Match(lDprojText, '<MainSource>\s*([^<]+?)\s*</MainSource>', [roIgnoreCase, roSingleLine]);
  if lMatch.Success and (lMatch.Groups.Count > 1) then
  begin
    aMainSourceRaw := Trim(lMatch.Groups[1].Value);
    if aMainSourceRaw <> '' then
    begin
      lDprojDir := ExcludeTrailingPathDelimiter(ExtractFilePath(aDprojPath));
      lCandidatePath := TPath.Combine(lDprojDir, aMainSourceRaw);
      lCandidatePath := TPath.GetFullPath(lCandidatePath);
      if FileExists(lCandidatePath) then
      begin
        aSourceProjectPath := lCandidatePath;
        Exit(True);
      end;
    end;
  end;

  aError := 'Could not resolve MainSource (.dpr/.dpk) from .dproj: ' + aDprojPath;
  Result := False;
end;

function TryCopyDprojWithNewMainSource(const aSourceDprojPath: string; const aDestDprojPath: string;
  const aSourceMainSource: string; const aGeneratedMainSource: string; out aError: string): Boolean;
var
  lSourceText: string;
  lOutputText: string;
  lRegex: string;
begin
  aError := '';
  lSourceText := TFile.ReadAllText(aSourceDprojPath);
  lOutputText := lSourceText;
  lRegex := '<MainSource>\s*' + TRegEx.Escape(aSourceMainSource) + '\s*</MainSource>';

  lOutputText := TRegEx.Replace(lOutputText, lRegex, '<MainSource>' + aGeneratedMainSource + '</MainSource>',
    [roIgnoreCase, roSingleLine]);
  if lOutputText = lSourceText then
    lOutputText := TRegEx.Replace(lOutputText, '<MainSource>\s*([^<]+?)\s*</MainSource>',
      '<MainSource>' + aGeneratedMainSource + '</MainSource>', [roIgnoreCase, roSingleLine]);

  if lOutputText = lSourceText then
  begin
    aError := 'Could not patch generated .dproj MainSource.';
    Exit(False);
  end;

  TFile.WriteAllText(aDestDprojPath, lOutputText, TEncoding.UTF8);
  Result := True;
end;

function TryWriteRuntimeOnlyCheckerUnit(const aGeneratedUnitPath: string; out aError: string): Boolean;
const
  cLineBreak = #13#10;
var
  lContent: string;
  lEncoding: TEncoding;
  lInputText: string;
  lLine: string;
  lMatch: TMatch;
  lMatchCollection: TMatchCollection;
  lUsesBlock: string;
  lUsesUnits: TStringList;
  lUnitName: string;
  i: Integer;
begin
  aError := '';
  lUnitName := Trim(TPath.GetFileNameWithoutExtension(aGeneratedUnitPath));
  if lUnitName = '' then
  begin
    aError := 'Generated checker unit name is empty: ' + aGeneratedUnitPath;
    Exit(False);
  end;

  if not FileExists(aGeneratedUnitPath) then
  begin
    aError := 'Generated checker unit not found: ' + aGeneratedUnitPath;
    Exit(False);
  end;

  lInputText := TFile.ReadAllText(aGeneratedUnitPath);
  lMatch := TRegEx.Match(lInputText, '\buses\b(.*?);', [roIgnoreCase, roSingleLine]);
  if not lMatch.Success or (lMatch.Groups.Count < 2) then
  begin
    aError := 'Could not extract uses clause from generated checker unit: ' + aGeneratedUnitPath;
    Exit(False);
  end;

  lUsesUnits := TStringList.Create;
  try
    lUsesUnits.CaseSensitive := False;
    lUsesUnits.Sorted := False;
    lUsesUnits.Duplicates := TDuplicates.dupIgnore;

    lUsesBlock := lMatch.Groups[1].Value;
    lMatchCollection := TRegEx.Matches(lUsesBlock, '[A-Za-z_][A-Za-z0-9_\.]*');
    for lMatch in lMatchCollection do
      lUsesUnits.Add(lMatch.Value);
    if lUsesUnits.Count = 0 then
    begin
      aError := 'Generated checker unit uses clause is empty: ' + aGeneratedUnitPath;
      Exit(False);
    end;
    if lUsesUnits.IndexOf('System.Classes') < 0 then
      lUsesUnits.Add('System.Classes');

    lContent :=
      'unit ' + lUnitName + ';' + cLineBreak + cLineBreak +
      'interface' + cLineBreak + cLineBreak +
      'implementation' + cLineBreak + cLineBreak +
      'uses' + cLineBreak;
    for i := 0 to lUsesUnits.Count - 1 do
    begin
      lLine := '  ' + lUsesUnits[i];
      if i < lUsesUnits.Count - 1 then
        lLine := lLine + ','
      else
        lLine := lLine + ';';
      lContent := lContent + lLine + cLineBreak;
    end;
    lContent := lContent + cLineBreak +
      'procedure TouchDfmCheckUnits;' + cLineBreak +
      'begin' + cLineBreak;
    lContent := lContent +
      'end;' + cLineBreak + cLineBreak +
      'initialization' + cLineBreak +
      '  TouchDfmCheckUnits;' + cLineBreak + cLineBreak +
      'end.' + cLineBreak;
  finally
    lUsesUnits.Free;
  end;

  lEncoding := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(aGeneratedUnitPath, lContent, lEncoding);
  finally
    lEncoding.Free;
  end;
  Result := True;
end;

function TryGenerateDfmCheckProject(const aDprojPath: string; var aPaths: TDfmCheckPaths; out aError: string): Boolean;
var
  lCheck: TDfmCheck;
  lContent: string;
  lGeneratedCfgPath: string;
  lGeneratedDprPath: string;
  lGeneratedDprName: string;
  lGeneratedDprojPath: string;
  lGeneratedDprojName: string;
  lGeneratedUnitPath: string;
  lMainSourceRaw: string;
  lOptionsObj: TOptions;
  lSourceCfgPath: string;
  lSourceProjectExt: string;
  lSourceProjectPath: string;
  lProject: IOTAProject;
begin
  aError := '';
  if not TryResolveGeneratorProjectPath(aDprojPath, lSourceProjectPath, lMainSourceRaw, aError) then
    Exit(False);

  lSourceProjectExt := LowerCase(TPath.GetExtension(lSourceProjectPath));
  if not SameText(lSourceProjectExt, '.dpr') then
  begin
    aError := 'Only Delphi .dpr MainSource projects are supported for dfm-check.';
    Exit(False);
  end;

  lOptionsObj := TOptions.Create;
  Options := lOptionsObj;
  try
    lProject := LoadProject(lSourceProjectPath);
    if (lProject = nil) or (lProject.ModuleCount = 0) then
    begin
      aError := 'DFMCheck generator found no form modules in: ' + lSourceProjectPath;
      Exit(False);
    end;

    lCheck := TDfmCheck.Create(lProject);
    try
      lCheck.CheckForms(True, False);
      lGeneratedUnitPath := lCheck.ProjectFileNameDfmCheckUnit;
    finally
      lCheck.Free;
    end;
  finally
    Options := nil;
    lOptionsObj.Free;
  end;

  if not FileExists(lGeneratedUnitPath) then
  begin
    aError := 'Generated DFMCheck unit not found: ' + lGeneratedUnitPath;
    Exit(False);
  end;

  if not TryWriteRuntimeOnlyCheckerUnit(lGeneratedUnitPath, aError) then
    Exit(False);

  lGeneratedDprName := TPath.GetFileNameWithoutExtension(aDprojPath) + '_DfmCheck.dpr';
  lGeneratedDprojName := TPath.GetFileNameWithoutExtension(aDprojPath) + '_DfmCheck.dproj';
  lGeneratedDprPath := TPath.Combine(aPaths.fProjectDir, lGeneratedDprName);
  lGeneratedDprojPath := TPath.Combine(aPaths.fProjectDir, lGeneratedDprojName);
  lGeneratedCfgPath := TPath.ChangeExtension(lGeneratedDprPath, '.cfg');

  lContent := TFile.ReadAllText(lSourceProjectPath);
  if not AppendProjectUnit(lContent, ExtractFileName(lGeneratedUnitPath)) then
  begin
    aError := 'Could not append generated DFMCheck unit to project source.';
    Exit(False);
  end;
  TFile.WriteAllText(lGeneratedDprPath, lContent, TEncoding.UTF8);

  lSourceCfgPath := TPath.ChangeExtension(lSourceProjectPath, '.cfg');
  if FileExists(lSourceCfgPath) then
    TFile.Copy(lSourceCfgPath, lGeneratedCfgPath, True);

  if not TryCopyDprojWithNewMainSource(aDprojPath, lGeneratedDprojPath, lMainSourceRaw, lGeneratedDprName, aError) then
    Exit(False);

  aPaths.fGeneratedDir := aPaths.fProjectDir;
  aPaths.fGeneratedDpr := lGeneratedDprPath;
  aPaths.fGeneratedDproj := lGeneratedDprojPath;
  Result := True;
end;

function GetFirstSortedFile(const aDirectoryPath: string; const aPattern: string): string;
var
  lFileArray: TArray<string>;
  lFileList: TStringList;
  lFilePath: string;
begin
  Result := '';
  if not DirectoryExists(aDirectoryPath) then
    Exit('');

  lFileArray := TDirectory.GetFiles(aDirectoryPath, aPattern, TSearchOption.soTopDirectoryOnly);
  if Length(lFileArray) = 0 then
    Exit('');

  lFileList := TStringList.Create;
  try
    lFileList.CaseSensitive := False;
    lFileList.Sorted := True;
    lFileList.Duplicates := TDuplicates.dupIgnore;
    for lFilePath in lFileArray do
      lFileList.Add(lFilePath);
    if lFileList.Count > 0 then
      Result := lFileList[0];
  finally
    lFileList.Free;
  end;
end;

function TryLocateGeneratedDfmCheckProject(var aPaths: TDfmCheckPaths; out aError: string): Boolean;
var
  lDirectDproj: string;
  lDirectDpr: string;
  lDirectoryArray: TArray<string>;
  lDirectoryList: TStringList;
  lDirectoryPath: string;
  lExpectedDir: string;
  lFoundDproj: string;
  lFoundDpr: string;
begin
  aError := '';
  lExpectedDir := aPaths.fGeneratedDir;
  lDirectoryList := TStringList.Create;
  try
    lDirectoryList.CaseSensitive := False;
    lDirectoryList.Sorted := True;
    lDirectoryList.Duplicates := TDuplicates.dupIgnore;

    if DirectoryExists(lExpectedDir) then
      lDirectoryList.Add(lExpectedDir);

    lDirectoryArray := TDirectory.GetDirectories(aPaths.fProjectDir, '*_DfmCheck', TSearchOption.soTopDirectoryOnly);
    for lDirectoryPath in lDirectoryArray do
      lDirectoryList.Add(lDirectoryPath);

    lDirectoryArray := TDirectory.GetDirectories(aPaths.fProjectDir, aPaths.fProjectName + '_DfmCheck*',
      TSearchOption.soTopDirectoryOnly);
    for lDirectoryPath in lDirectoryArray do
      lDirectoryList.Add(lDirectoryPath);

    for lDirectoryPath in lDirectoryList do
    begin
      lFoundDproj := TPath.Combine(lDirectoryPath, aPaths.fProjectName + '_DfmCheck.dproj');
      if not FileExists(lFoundDproj) then
        lFoundDproj := GetFirstSortedFile(lDirectoryPath, '*.dproj');
      lFoundDpr := TPath.Combine(lDirectoryPath, aPaths.fProjectName + '_DfmCheck.dpr');
      if not FileExists(lFoundDpr) then
        lFoundDpr := GetFirstSortedFile(lDirectoryPath, '*.dpr');
      if (lFoundDproj <> '') and (lFoundDpr <> '') then
      begin
        aPaths.fGeneratedDir := lDirectoryPath;
        aPaths.fGeneratedDproj := lFoundDproj;
        aPaths.fGeneratedDpr := lFoundDpr;
        Exit(True);
      end;
    end;

    lDirectDproj := TPath.Combine(aPaths.fProjectDir, aPaths.fProjectName + '_DfmCheck.dproj');
    if not FileExists(lDirectDproj) then
      lDirectDproj := GetFirstSortedFile(aPaths.fProjectDir, '*_DfmCheck.dproj');
    lDirectDpr := TPath.Combine(aPaths.fProjectDir, aPaths.fProjectName + '_DfmCheck.dpr');
    if not FileExists(lDirectDpr) then
      lDirectDpr := GetFirstSortedFile(aPaths.fProjectDir, '*_DfmCheck.dpr');
    if (lDirectDproj <> '') and (lDirectDpr <> '') then
    begin
      aPaths.fGeneratedDir := aPaths.fProjectDir;
      aPaths.fGeneratedDproj := lDirectDproj;
      aPaths.fGeneratedDpr := lDirectDpr;
      Exit(True);
    end;
  finally
    lDirectoryList.Free;
  end;

  aError := 'Could not locate generated _DfmCheck project under: ' + aPaths.fProjectDir;
  Result := False;
end;

function TryPatchDfmCheckDpr(const aInputText: string; out aOutputText: string; out aChanged: Boolean;
  out aError: string): Boolean;
const
  cLineBreak = #13#10;
var
  lClauseEnd: Integer;
  lClauseStart: Integer;
  lCharAfter: Char;
  lCharBefore: Char;
  lFoundUses: Boolean;
  lLowerText: string;
  lPos: Integer;
  lWorkText: string;
  lChangedUses: Boolean;
  lChangedValidatorStart: Boolean;
  lUsesBody: string;
  lUsesText: string;
  lBeginPos: Integer;
  lMainBlockPrefix: string;
  lMainEndPos: Integer;
  lSuffix: string;
begin
  Result := False;
  aError := '';
  aChanged := False;
  lWorkText := aInputText;
  lChangedUses := False;
  lChangedValidatorStart := False;
  lClauseStart := 0;
  lClauseEnd := 0;

  if not ContainsWord(lWorkText, 'DfmStreamAll') then
  begin
    lFoundUses := False;
    lLowerText := LowerCase(lWorkText);
    lPos := Pos('uses', lLowerText);
    while lPos > 0 do
    begin
      if lPos > 1 then
        lCharBefore := lLowerText[lPos - 1]
      else
        lCharBefore := #0;
      if (lPos + 4) <= Length(lLowerText) then
        lCharAfter := lLowerText[lPos + 4]
      else
        lCharAfter := #0;

      if (not CharInSet(lCharBefore, ['a'..'z', '0'..'9', '_'])) and
        (not CharInSet(lCharAfter, ['a'..'z', '0'..'9', '_'])) then
      begin
        lClauseStart := lPos;
        lClauseEnd := PosEx(';', lWorkText, lClauseStart + 4);
        if lClauseEnd > 0 then
        begin
          lFoundUses := True;
          Break;
        end;
      end;
      lPos := PosEx('uses', lLowerText, lPos + 4);
    end;

    if not lFoundUses then
    begin
      aError := 'Could not patch DPR: uses clause not found.';
      Exit(False);
    end;

    lUsesBody := Copy(lWorkText, lClauseStart + 4, lClauseEnd - (lClauseStart + 4));
    lUsesBody := TrimLeft(lUsesBody);
    if lUsesBody = '' then
    begin
      aError := 'Could not patch DPR: empty uses clause.';
      Exit(False);
    end;

    lUsesText := 'uses' + cLineBreak + '  DfmStreamAll,' + cLineBreak + '  ' + lUsesBody + ';';
    lWorkText := Copy(lWorkText, 1, lClauseStart - 1) + lUsesText + Copy(lWorkText, lClauseEnd + 1, MaxInt);
    lChangedUses := True;
  end;

  if not ContainsWord(lWorkText, 'TDfmStreamAll.Run') then
  begin
    lMainEndPos := LastPosText('end.', lWorkText);
    if lMainEndPos = 0 then
    begin
      aError := 'Could not patch DPR: final "end." not found.';
      Exit(False);
    end;

    lMainBlockPrefix := Copy(lWorkText, 1, lMainEndPos - 1);
    lBeginPos := LastPosText('begin', LowerCase(lMainBlockPrefix));
    if lBeginPos = 0 then
    begin
      aError := 'Could not patch DPR: main "begin" not found.';
      Exit(False);
    end;

    lSuffix := Copy(lWorkText, lBeginPos + Length('begin'), MaxInt);
    if (lSuffix <> '') and (not CharInSet(lSuffix[1], [#10, #13, ' '])) then
      lSuffix := cLineBreak + lSuffix;
    lWorkText := Copy(lWorkText, 1, lBeginPos + Length('begin') - 1) +
      cLineBreak +
      '  ExitCode := TDfmStreamAll.Run;' + cLineBreak +
      '  Halt(ExitCode);' + lSuffix;
    lChangedValidatorStart := True;
  end;

  aChanged := lChangedUses or lChangedValidatorStart;
  aOutputText := lWorkText;
  Result := True;
end;

function IsGeneratedUnitBuildFailure(const aBuildLines: TStrings; const aPaths: TDfmCheckPaths): Boolean;
var
  lLine: string;
  lLineUpper: string;
  lUnitPathUpper: string;
  lUnitNameUpper: string;
begin
  Result := False;
  if aBuildLines = nil then
    Exit(False);

  lUnitPathUpper := UpperCase(TPath.Combine(aPaths.fProjectDir, aPaths.fProjectName + '_DfmCheck_Unit.pas'));
  lUnitNameUpper := UpperCase(aPaths.fProjectName + '_DfmCheck_Unit.pas');

  for lLine in aBuildLines do
  begin
    lLineUpper := UpperCase(lLine);
    if (Pos(lUnitNameUpper, lLineUpper) = 0) and (Pos(lUnitPathUpper, lLineUpper) = 0) then
      Continue;

    if (Pos('ERROR E', lLineUpper) > 0) or
      (Pos('ERROR F', lLineUpper) > 0) or
      (Pos('COULD NOT COMPILE USED UNIT', lLineUpper) > 0) then
      Exit(True);
  end;
end;

function TryFindValidatorExe(const aPaths: TDfmCheckPaths; const aPlatform: string; const aConfig: string;
  out aValidatorExePath: string; out aError: string): Boolean;
var
  lExeBaseName: string;
  lExpectedPathList: TStringList;
  lProjectParentDir: string;
  lCandidatePath: string;
begin
  aError := '';
  aValidatorExePath := '';
  lExeBaseName := TPath.GetFileNameWithoutExtension(aPaths.fGeneratedDproj) + '.exe';
  lProjectParentDir := ExcludeTrailingPathDelimiter(ExtractFileDir(aPaths.fProjectDir));

  lExpectedPathList := TStringList.Create;
  try
    lExpectedPathList.CaseSensitive := False;
    lExpectedPathList.Sorted := True;
    lExpectedPathList.Duplicates := TDuplicates.dupIgnore;

    lExpectedPathList.Add(TPath.Combine(TPath.Combine(TPath.Combine(aPaths.fGeneratedDir, aPlatform), aConfig),
      lExeBaseName));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(TPath.Combine(aPaths.fGeneratedDir, 'Bin'), aPlatform),
      TPath.Combine(aConfig, lExeBaseName)));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(aPaths.fGeneratedDir, 'Bin'), lExeBaseName));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(TPath.Combine(aPaths.fProjectDir, aPlatform), aConfig),
      lExeBaseName));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(TPath.Combine(aPaths.fProjectDir, 'Bin'), aPlatform),
      TPath.Combine(aConfig, lExeBaseName)));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(aPaths.fProjectDir, 'Bin'), lExeBaseName));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(TPath.Combine(lProjectParentDir, 'Bin'), aPlatform),
      TPath.Combine(aConfig, lExeBaseName)));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(lProjectParentDir, 'Bin'), lExeBaseName));
    lExpectedPathList.Add(TPath.Combine(aPaths.fGeneratedDir, lExeBaseName));
    lExpectedPathList.Add(TPath.Combine(aPaths.fProjectDir, lExeBaseName));

    for lCandidatePath in lExpectedPathList do
    begin
      if FileExists(lCandidatePath) then
      begin
        aValidatorExePath := lCandidatePath;
        Exit(True);
      end;
    end;
  finally
    lExpectedPathList.Free;
  end;

  aError := 'Could not find built _DfmCheck.exe in expected output directories.';
  Result := False;
end;

function MapDfmCheckExitCode(const aCategory: TDfmCheckErrorCategory; const aToolExitCode: Integer): Integer;
begin
  case aCategory of
    TDfmCheckErrorCategory.ecNone:
      Result := aToolExitCode;
    TDfmCheckErrorCategory.ecInvalidInput,
    TDfmCheckErrorCategory.ecToolNotFound:
      Result := 3;
    TDfmCheckErrorCategory.ecDfmCheckFailed:
      if aToolExitCode <> 0 then
        Result := aToolExitCode
      else
        Result := 30;
    TDfmCheckErrorCategory.ecGeneratorIncompatible:
      if aToolExitCode <> 0 then
        Result := aToolExitCode
      else
        Result := 37;
    TDfmCheckErrorCategory.ecGeneratedProjectMissing:
      Result := 31;
    TDfmCheckErrorCategory.ecInjectFilesMissing:
      Result := 32;
    TDfmCheckErrorCategory.ecDprPatchFailed:
      Result := 33;
    TDfmCheckErrorCategory.ecBuildFailed:
      if aToolExitCode <> 0 then
        Result := aToolExitCode
      else
        Result := 34;
    TDfmCheckErrorCategory.ecValidatorNotFound:
      Result := 35;
    TDfmCheckErrorCategory.ecValidatorFailed:
      if aToolExitCode <> 0 then
        Result := aToolExitCode
      else
        Result := 36;
  else
    Result := 1;
  end;
end;

function RunDfmCheckPipeline(const aOptions: TAppOptions; const aRunner: IDfmCheckProcessRunner;
  const aOutput: TDfmCheckOutputProc; out aCategory: TDfmCheckErrorCategory; out aError: string): Integer;
var
  lCopiedAutoFree: Boolean;
  lCopiedDfmStreamAll: Boolean;
  lDelphiVersion: string;
  lDprojPath: string;
  lPaths: TDfmCheckPaths;
  lText: string;
  lPatchedText: string;
  lChanged: Boolean;
  lExitCode: Cardinal;
  lRunnerError: string;
  lBuildLines: TStringList;
  lBuildExePath: string;
  lBuildExeOverride: string;
  lConfig: string;
  lPlatform: string;
  lValidatorExePath: string;
  lWriterEncoding: TEncoding;
  lHadAutoFree: Boolean;
  lHadDfmStreamAll: Boolean;
begin
  Result := 1;
  aError := '';
  aCategory := TDfmCheckErrorCategory.ecNone;
  lCopiedAutoFree := False;
  lCopiedDfmStreamAll := False;
  lValidatorExePath := '';
  lBuildLines := TStringList.Create;

  try
    if aRunner = nil then
    begin
      aCategory := TDfmCheckErrorCategory.ecInvalidInput;
      aError := 'Process runner is not assigned.';
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;

    if not TryResolveDfmCheckProjectPath(aOptions.fDprojPath, lDprojPath, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecInvalidInput;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;

    lDelphiVersion := Trim(aOptions.fDelphiVersion);
    if lDelphiVersion = '' then
    begin
      if not LoadDefaultDelphiVersion(lDprojPath, lDelphiVersion) then
      begin
        aCategory := TDfmCheckErrorCategory.ecInvalidInput;
        aError := 'Failed to read default Delphi version from dak.ini.';
        Exit(MapDfmCheckExitCode(aCategory, 0));
      end;
      if lDelphiVersion <> '' then
        EmitLine(aOutput, '[dfm-check] Using Delphi version from dak.ini: ' + lDelphiVersion);
    end;
    if (lDelphiVersion <> '') and (Pos('.', lDelphiVersion) = 0) then
      lDelphiVersion := lDelphiVersion + '.0';

    if aOptions.fHasRsVarsPath or (lDelphiVersion <> '') then
    begin
      EmitLine(aOutput, '[dfm-check] Loading RAD Studio environment from rsvars.bat...');
      if not TryLoadRsVars(lDelphiVersion, aOptions.fRsVarsPath, nil, aError) then
      begin
        aCategory := TDfmCheckErrorCategory.ecInvalidInput;
        Exit(MapDfmCheckExitCode(aCategory, 0));
      end;
    end;

    lConfig := aOptions.fConfig;
    if Trim(lConfig) = '' then
      lConfig := 'Release';
    lPlatform := aOptions.fPlatform;
    if Trim(lPlatform) = '' then
      lPlatform := 'Win32';

    lPaths := BuildExpectedDfmCheckPaths(lDprojPath);

    if not TryResolveInjectDir(lPaths.fInjectDir, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecInjectFilesMissing;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    lPaths.fInjectAutoFree := TPath.Combine(lPaths.fInjectDir, 'autoFree.pas');
    lPaths.fInjectDfmStreamAll := TPath.Combine(lPaths.fInjectDir, 'DfmStreamAll.pas');
    if (not FileExists(lPaths.fInjectAutoFree)) or (not FileExists(lPaths.fInjectDfmStreamAll)) then
    begin
      aCategory := TDfmCheckErrorCategory.ecInjectFilesMissing;
      aError := 'Missing inject files in: ' + lPaths.fInjectDir;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;

    EmitLine(aOutput, '[dfm-check] Generating DFMCheck project...');
    if not TryGenerateDfmCheckProject(lDprojPath, lPaths, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecDfmCheckFailed;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;

    if not TryLocateGeneratedDfmCheckProject(lPaths, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecGeneratedProjectMissing;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    EmitLine(aOutput, '[dfm-check] Generated project: ' + lPaths.fGeneratedDproj);

    lHadAutoFree := FileExists(TPath.Combine(lPaths.fGeneratedDir, 'autoFree.pas'));
    lHadDfmStreamAll := FileExists(TPath.Combine(lPaths.fGeneratedDir, 'DfmStreamAll.pas'));
    TFile.Copy(lPaths.fInjectAutoFree, TPath.Combine(lPaths.fGeneratedDir, 'autoFree.pas'), True);
    TFile.Copy(lPaths.fInjectDfmStreamAll, TPath.Combine(lPaths.fGeneratedDir, 'DfmStreamAll.pas'), True);
    lCopiedAutoFree := not lHadAutoFree;
    lCopiedDfmStreamAll := not lHadDfmStreamAll;

    lText := TFile.ReadAllText(lPaths.fGeneratedDpr);
    if not TryPatchDfmCheckDpr(lText, lPatchedText, lChanged, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecDprPatchFailed;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    if lChanged then
    begin
      lWriterEncoding := TUTF8Encoding.Create(False);
      try
        TFile.WriteAllText(lPaths.fGeneratedDpr, lPatchedText, lWriterEncoding);
      finally
        lWriterEncoding.Free;
      end;
    end;

    lBuildExeOverride := Trim(GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD'));
    if not TryResolveMsBuildPath(lBuildExeOverride, lBuildExePath, lRunnerError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecToolNotFound;
      aError := lRunnerError;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    EmitLine(aOutput, '[dfm-check] Using MSBuild: ' + lBuildExePath);

    EmitLine(aOutput, '[dfm-check] Building generated DfmCheck project via MSBuild...');
    if not aRunner.Run(lBuildExePath,
      QuoteCmdArg(lPaths.fGeneratedDproj) + ' /t:Build /p:Config=' + lConfig + ' /p:Platform=' + lPlatform +
      ' /p:DCC_ForceExecute=true /v:m',
      lPaths.fGeneratedDir,
      procedure(const aLine: string)
      begin
        lBuildLines.Add(aLine);
        EmitLine(aOutput, aLine);
      end, lExitCode, lRunnerError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecBuildFailed;
      aError := 'MSBuild failed to start: ' + lRunnerError;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    if lExitCode <> 0 then
    begin
      if IsGeneratedUnitBuildFailure(lBuildLines, lPaths) then
      begin
        aCategory := TDfmCheckErrorCategory.ecGeneratorIncompatible;
        aError := Format('Generated *_DfmCheck_Unit.pas failed to compile (generator incompatibility). MSBuild exited with code %d.',
          [lExitCode]);
      end else
      begin
        aCategory := TDfmCheckErrorCategory.ecBuildFailed;
        aError := Format('MSBuild exited with code %d.', [lExitCode]);
      end;
      Exit(MapDfmCheckExitCode(aCategory, Integer(lExitCode)));
    end;

    if not TryFindValidatorExe(lPaths, lPlatform, lConfig, lValidatorExePath, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecValidatorNotFound;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;

    EmitLine(aOutput, '[dfm-check] Running validator exe...');
    if not aRunner.Run(lValidatorExePath, '', lPaths.fGeneratedDir, aOutput, lExitCode, lRunnerError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecValidatorFailed;
      aError := 'Validator executable failed to start: ' + lRunnerError;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;

    // Propagate streaming validator result directly: 0 = success, >0 = number of failed resources.
    Result := Integer(lExitCode);
  finally
    lBuildLines.Free;
    if ShouldKeepArtifacts then
      EmitLine(aOutput, '[dfm-check] Keeping generated _DfmCheck artifacts (DAK_DFMCHECK_KEEP_ARTIFACTS).')
    else
      CleanupGeneratedArtifacts(lPaths, lCopiedAutoFree, lCopiedDfmStreamAll, lValidatorExePath, aOutput);
  end;
end;

function RunDfmCheckCommand(const aOptions: TAppOptions): Integer;
var
  lCategory: TDfmCheckErrorCategory;
  lError: string;
  lRunner: IDfmCheckProcessRunner;
begin
  lRunner := TWinProcessRunner.Create;
  Result := RunDfmCheckPipeline(aOptions, lRunner, nil, lCategory, lError);
  if lError <> '' then
    WriteLn(ErrOutput, lError);
end;

function TWinProcessRunner.Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
  const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
var
  lStartupInfo: TStartupInfo;
  lProcessInfo: TProcessInformation;
  lCmdLine: string;
  lAppName: string;
  lWorkDir: string;
  lWaitResult: Cardinal;
  lLastError: Cardinal;
  lCommandExe: string;
  lCommandScript: string;
  lUnusedOutput: TDfmCheckOutputProc;
begin
  Result := False;
  aExitCode := 0;
  aError := '';
  lUnusedOutput := aOutput;
  if Assigned(lUnusedOutput) then
  begin
    // The default runner writes directly to inherited stdout/stderr handles.
  end;

  FillChar(lStartupInfo, SizeOf(lStartupInfo), 0);
  lStartupInfo.cb := SizeOf(lStartupInfo);
  lStartupInfo.dwFlags := STARTF_USESTDHANDLES;
  lStartupInfo.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lStartupInfo.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  lStartupInfo.hStdError := GetStdHandle(STD_ERROR_HANDLE);
  FillChar(lProcessInfo, SizeOf(lProcessInfo), 0);

  if IsCmdScript(aExePath) then
  begin
    lCommandExe := GetEnvironmentVariable('ComSpec');
    if lCommandExe = '' then
      lCommandExe := 'C:\Windows\System32\cmd.exe';
    lCommandScript := 'call ' + QuoteCmdArg(aExePath);
    if Trim(aArguments) <> '' then
      lCommandScript := lCommandScript + ' ' + aArguments;
    lCmdLine := QuoteCmdArg(lCommandExe) + ' /S /C "' + lCommandScript + '"';
    lAppName := lCommandExe;
  end else
  begin
    lCmdLine := QuoteCmdArg(aExePath);
    if Trim(aArguments) <> '' then
      lCmdLine := lCmdLine + ' ' + aArguments;
    if FileExists(aExePath) then
      lAppName := aExePath
    else
      lAppName := '';
  end;
  UniqueString(lCmdLine);

  lWorkDir := aWorkingDir;
  if Trim(lWorkDir) = '' then
    lWorkDir := ExtractFilePath(aExePath);
  if Trim(lWorkDir) = '' then
    lWorkDir := GetCurrentDir;

  if lAppName = '' then
  begin
    if not CreateProcess(nil, PChar(lCmdLine), nil, nil, True, 0, nil, PChar(lWorkDir), lStartupInfo, lProcessInfo)
    then
    begin
      lLastError := GetLastError;
      aError := SysErrorMessage(lLastError);
      Exit(False);
    end;
  end else if not CreateProcess(PChar(lAppName), PChar(lCmdLine), nil, nil, True, 0, nil, PChar(lWorkDir),
      lStartupInfo, lProcessInfo) then
  begin
    lLastError := GetLastError;
    aError := SysErrorMessage(lLastError);
    Exit(False);
  end;

  try
    lWaitResult := WaitForSingleObject(lProcessInfo.hProcess, INFINITE);
    if lWaitResult <> WAIT_OBJECT_0 then
    begin
      lLastError := GetLastError;
      aError := SysErrorMessage(lLastError);
      Exit(False);
    end;
    if not GetExitCodeProcess(lProcessInfo.hProcess, aExitCode) then
    begin
      lLastError := GetLastError;
      aError := SysErrorMessage(lLastError);
      Exit(False);
    end;
  finally
    CloseHandle(lProcessInfo.hThread);
    CloseHandle(lProcessInfo.hProcess);
  end;

  Result := True;
end;

end.
