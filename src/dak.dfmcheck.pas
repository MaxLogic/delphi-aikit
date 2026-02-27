unit Dak.DfmCheck;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.RegularExpressions, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  Dak.Messages, Dak.RsVars, Dak.Types;

type
  TDfmCheckErrorCategory = (
    ecNone,
    ecInvalidInput,
    ecToolNotFound,
    ecDfmCheckFailed,
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
  lChangedExitCode: Boolean;
  lUsesBody: string;
  lUsesText: string;
  lEndPos: Integer;
  lPrefix: string;
begin
  Result := False;
  aError := '';
  aChanged := False;
  lWorkText := aInputText;
  lChangedUses := False;
  lChangedExitCode := False;
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
    lEndPos := LastPosText('end.', lWorkText);
    if lEndPos = 0 then
    begin
      aError := 'Could not patch DPR: final "end." not found.';
      Exit(False);
    end;

    lPrefix := Copy(lWorkText, 1, lEndPos - 1);
    if (lPrefix <> '') and (not CharInSet(lPrefix[Length(lPrefix)], [#10, #13])) then
      lPrefix := lPrefix + cLineBreak;
    lWorkText := lPrefix + '  ExitCode := TDfmStreamAll.Run;' + cLineBreak + Copy(lWorkText, lEndPos, MaxInt);
    lChangedExitCode := True;
  end;

  aChanged := lChangedUses or lChangedExitCode;
  aOutputText := lWorkText;
  Result := True;
end;

function TryFindValidatorExe(const aPaths: TDfmCheckPaths; const aPlatform: string; const aConfig: string;
  out aValidatorExePath: string; out aError: string): Boolean;
var
  lExpectedExePath: string;
  lExeArray: TArray<string>;
  lExeList: TStringList;
  lExePath: string;
  lNeedlePath: string;
  lExeBaseName: string;
begin
  aError := '';
  aValidatorExePath := '';
  lExeBaseName := TPath.GetFileNameWithoutExtension(aPaths.fGeneratedDproj) + '.exe';
  lExpectedExePath := TPath.Combine(TPath.Combine(TPath.Combine(aPaths.fGeneratedDir, aPlatform), aConfig),
    lExeBaseName);
  if FileExists(lExpectedExePath) then
  begin
    aValidatorExePath := lExpectedExePath;
    Exit(True);
  end;

  lExeArray := TDirectory.GetFiles(aPaths.fGeneratedDir, '*.exe', TSearchOption.soAllDirectories);
  lExeList := TStringList.Create;
  try
    lExeList.CaseSensitive := False;
    lExeList.Sorted := True;
    lExeList.Duplicates := TDuplicates.dupIgnore;
    for lExePath in lExeArray do
      lExeList.Add(lExePath);

    lNeedlePath := '\' + aPlatform + '\' + aConfig + '\';
    for lExePath in lExeList do
    begin
      if SameText(TPath.GetFileName(lExePath), lExeBaseName) and
        (Pos(UpperCase(lNeedlePath), UpperCase(lExePath)) > 0) then
      begin
        aValidatorExePath := lExePath;
        Exit(True);
      end;
    end;

    for lExePath in lExeList do
    begin
      if SameText(TPath.GetFileName(lExePath), lExeBaseName) then
      begin
        aValidatorExePath := lExePath;
        Exit(True);
      end;
    end;

    for lExePath in lExeList do
    begin
      if Pos('_DFMCHECK', UpperCase(TPath.GetFileNameWithoutExtension(lExePath))) > 0 then
      begin
        aValidatorExePath := lExePath;
        Exit(True);
      end;
    end;
  finally
    lExeList.Free;
  end;

  aError := 'Could not find built _DfmCheck.exe under: ' + aPaths.fGeneratedDir;
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
  lDprojPath: string;
  lDfmCheckExePath: string;
  lPaths: TDfmCheckPaths;
  lText: string;
  lPatchedText: string;
  lChanged: Boolean;
  lExitCode: Cardinal;
  lRunnerError: string;
  lBuildExePath: string;
  lConfig: string;
  lPlatform: string;
  lValidatorExePath: string;
  lWriterEncoding: TEncoding;
begin
  Result := 1;
  aError := '';
  aCategory := TDfmCheckErrorCategory.ecNone;

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

  if not TryResolveAbsolutePath(aOptions.fDfmCheckExePath, lDfmCheckExePath, aError) then
  begin
    aCategory := TDfmCheckErrorCategory.ecInvalidInput;
    Exit(MapDfmCheckExitCode(aCategory, 0));
  end;
  if not FileExists(lDfmCheckExePath) then
  begin
    aCategory := TDfmCheckErrorCategory.ecToolNotFound;
    aError := Format(SFileNotFound, [lDfmCheckExePath]);
    Exit(MapDfmCheckExitCode(aCategory, 0));
  end;

  if aOptions.fHasRsVarsPath then
  begin
    EmitLine(aOutput, '[dfm-check] Loading RAD Studio environment from rsvars.bat...');
    if not TryLoadRsVars('', aOptions.fRsVarsPath, nil, aError) then
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

  EmitLine(aOutput, '[dfm-check] Running DFMCheck...');
  if not aRunner.Run(lDfmCheckExePath, QuoteCmdArg(lDprojPath), lPaths.fProjectDir, aOutput, lExitCode, lRunnerError)
  then
  begin
    aCategory := TDfmCheckErrorCategory.ecDfmCheckFailed;
    aError := 'DFMCheck failed to start: ' + lRunnerError;
    Exit(MapDfmCheckExitCode(aCategory, 0));
  end;
  if lExitCode <> 0 then
  begin
    aCategory := TDfmCheckErrorCategory.ecDfmCheckFailed;
    aError := Format('DFMCheck exited with code %d.', [lExitCode]);
    Exit(MapDfmCheckExitCode(aCategory, Integer(lExitCode)));
  end;

  if not TryLocateGeneratedDfmCheckProject(lPaths, aError) then
  begin
    aCategory := TDfmCheckErrorCategory.ecGeneratedProjectMissing;
    Exit(MapDfmCheckExitCode(aCategory, 0));
  end;
  EmitLine(aOutput, '[dfm-check] Generated project: ' + lPaths.fGeneratedDproj);

  TFile.Copy(lPaths.fInjectAutoFree, TPath.Combine(lPaths.fGeneratedDir, 'autoFree.pas'), True);
  TFile.Copy(lPaths.fInjectDfmStreamAll, TPath.Combine(lPaths.fGeneratedDir, 'DfmStreamAll.pas'), True);

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

  lBuildExePath := Trim(GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD'));
  if lBuildExePath = '' then
    lBuildExePath := 'msbuild.exe';
  EmitLine(aOutput, '[dfm-check] Building generated DfmCheck project via MSBuild...');
  if not aRunner.Run(lBuildExePath,
    QuoteCmdArg(lPaths.fGeneratedDproj) + ' /t:Build /p:Config=' + lConfig + ' /p:Platform=' + lPlatform + ' /v:m',
    lPaths.fGeneratedDir, aOutput, lExitCode, lRunnerError) then
  begin
    aCategory := TDfmCheckErrorCategory.ecBuildFailed;
    aError := 'MSBuild failed to start: ' + lRunnerError;
    Exit(MapDfmCheckExitCode(aCategory, 0));
  end;
  if lExitCode <> 0 then
  begin
    aCategory := TDfmCheckErrorCategory.ecBuildFailed;
    aError := Format('MSBuild exited with code %d.', [lExitCode]);
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
