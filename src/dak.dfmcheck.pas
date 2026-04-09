unit Dak.DfmCheck;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.IniFiles, System.RegularExpressions, System.StrUtils,
  System.SysUtils,
  System.Win.Registry,
  Winapi.Messages,
  Winapi.Windows,
  DfmCheck_Utils,
  Dak.Diagnostics, Dak.FixInsightSettings, Dak.Messages, Dak.RsVars, Dak.SourceContext, Dak.Types, Dak.Utils;

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
    fDakRootDir: string;
    fRunsDir: string;
    fRunDir: string;
    fGeneratedDir: string;
    fGeneratedDproj: string;
    fGeneratedDpr: string;
    fGeneratedRegisterUnit: string;
    fForcedExeOutputDir: string;
    fForcedDcuOutputDir: string;
    fInjectDir: string;
    fInjectDfmStreamAll: string;
    fInjectRuntimeGuard: string;
  end;

  TDfmValidationSummary = record
    fHasSummary: Boolean;
    fMatched: Integer;
    fRequested: Integer;
    fSkipped: Integer;
    fStreamed: Integer;
    fFailed: Integer;
  end;

  TDfmCacheModule = record
    fDfmHash: string;
    fDfmPath: string;
    fNeedsValidation: Boolean;
    fPasHash: string;
    fPasPath: string;
    fResourceName: string;
    fUnitName: string;
  end;

  TDfmCacheStats = record
    fEnabled: Boolean;
    fFilePath: string;
    fSkippedUnchanged: Integer;
    fToValidate: Integer;
    fTotal: Integer;
  end;

  TDfmCheckOutputProc = reference to procedure(const aLine: string);

  IDfmCheckProcessRunner = interface
    ['{ACB2FBB2-D818-4F75-B0D1-A6E6CAEA3A54}']
    function Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
      const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
  end;

function TryResolveDfmCheckProjectPath(const aInputPath: string; out aDprojPath: string; out aError: string): Boolean;
function TryResolveBundledInjectDir(const aExePath: string; out aInjectDir: string; out aError: string): Boolean;
function BuildExpectedDfmCheckPaths(const aDprojPath: string): TDfmCheckPaths;
function TryLocateGeneratedDfmCheckProject(var aPaths: TDfmCheckPaths; out aError: string): Boolean;
function TryPatchDfmCheckDpr(const aInputText: string; out aOutputText: string; out aChanged: Boolean;
  out aError: string; const aRegisterUnitName: string = ''; const aProgramName: string = ''): Boolean;
function MapDfmCheckExitCode(const aCategory: TDfmCheckErrorCategory; const aToolExitCode: Integer): Integer;
function RunDfmCheckPipeline(const aOptions: TAppOptions; const aRunner: IDfmCheckProcessRunner;
  const aOutput: TDfmCheckOutputProc; out aCategory: TDfmCheckErrorCategory; out aError: string): Integer;
function RunDfmCheckCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  Dak.Project;

type
  TWinProcessRunner = class(TInterfacedObject, IDfmCheckProcessRunner)
  public
    function Run(const aExePath: string; const aArguments: string; const aWorkingDir: string;
      const aOutput: TDfmCheckOutputProc; out aExitCode: Cardinal; out aError: string): Boolean;
  end;

type
  TWindowCloseContext = record
    ProcessId: Cardinal;
  end;
  PWindowCloseContext = ^TWindowCloseContext;

type
  TDfmWarningPromotion = record
    fActionName: string;
    fActionObjectLine: Integer;
    fActionParentClassName: string;
    fActionPropertyLine: Integer;
    fButtonClassName: string;
    fButtonName: string;
    fButtonObjectLine: Integer;
    fImageName: string;
    fImageNamePropertyLine: Integer;
    fImagesName: string;
    fImagesPropertyLine: Integer;
  end;

  TDfmTextObjectInfo = class
  public
    fClassName: string;
    fEndLine: Integer;
    fName: string;
    fParentClassName: string;
    fParentName: string;
    fProperties: TStringList;
    fPropertyLines: TStringList;
    fStartLine: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

function EnumCloseProcessWindowsProc(aWnd: HWND; aParam: LPARAM): BOOL; stdcall;
var
  lProcessId: Cardinal;
  lWindowProcessId: Cardinal;
  lWindowStyle: Longint;
begin
  Result := True;
  if aParam = 0 then
    Exit(True);

  lProcessId := PWindowCloseContext(aParam)^.ProcessId;
  if lProcessId = 0 then
    Exit(True);

  lWindowProcessId := 0;
  GetWindowThreadProcessId(aWnd, lWindowProcessId);
  if lWindowProcessId <> lProcessId then
    Exit(True);

  lWindowStyle := GetWindowLong(aWnd, GWL_STYLE);
  if (lWindowStyle and WS_VISIBLE) <> 0 then
    ShowWindow(aWnd, SW_HIDE);
  PostMessage(aWnd, WM_CLOSE, 0, 0);
end;

constructor TDfmTextObjectInfo.Create;
begin
  inherited Create;
  fProperties := TStringList.Create;
  fProperties.CaseSensitive := False;
  fProperties.NameValueSeparator := '=';
  fPropertyLines := TStringList.Create;
  fPropertyLines.CaseSensitive := False;
  fPropertyLines.NameValueSeparator := '=';
end;

destructor TDfmTextObjectInfo.Destroy;
begin
  fPropertyLines.Free;
  fProperties.Free;
  inherited;
end;

procedure CloseTopLevelWindowsForProcess(const aProcessId: Cardinal; const aDesktop: HDESK = 0);
var
  lContext: TWindowCloseContext;
begin
  if aProcessId = 0 then
    Exit;
  lContext.ProcessId := aProcessId;
  if aDesktop <> 0 then
    EnumDesktopWindows(aDesktop, @EnumCloseProcessWindowsProc, LPARAM(@lContext))
  else
    EnumWindows(@EnumCloseProcessWindowsProc, LPARAM(@lContext));
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

function TryFindMainProgramBegin(const aText: string; const aMainEndPos: Integer; out aBeginPos: Integer): Boolean;
var
  lBestPos: Integer;
  lLinePrefix: string;
  lMatch: TMatch;
  lMatchCollection: TMatchCollection;
  lPrefixText: string;
begin
  aBeginPos := 0;
  if aMainEndPos <= 1 then
    Exit(False);

  lPrefixText := Copy(aText, 1, aMainEndPos - 1);
  lMatchCollection := TRegEx.Matches(lPrefixText, '(^[ \t]*)begin[ \t]*$', [roIgnoreCase, roMultiLine]);
  lBestPos := 0;
  for lMatch in lMatchCollection do
  begin
    if not lMatch.Success or (lMatch.Groups.Count < 2) then
      Continue;
    lLinePrefix := lMatch.Groups[1].Value;
    if Length(lLinePrefix) = 0 then
      lBestPos := lMatch.Index + 1;
  end;
  if lBestPos <> 0 then
  begin
    aBeginPos := lBestPos;
    Exit(True);
  end;

  for lMatch in lMatchCollection do
  begin
    if lMatch.Success then
      lBestPos := lMatch.Index + 1;
  end;
  if lBestPos <> 0 then
  begin
    aBeginPos := lBestPos;
    Exit(True);
  end;

  lBestPos := LastPosText('begin', LowerCase(lPrefixText));
  if lBestPos = 0 then
    Exit(False);
  aBeginPos := lBestPos;
  Result := True;
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

function ShouldIsolateUiProcess(const aExePath: string; const aArguments: string): Boolean;
var
  lExeName: string;
begin
  if aArguments <> '' then
  begin
    // Validator filters are passed via command line; they must not disable desktop isolation.
  end;
  lExeName := TPath.GetFileName(aExePath);
  Result := EndsText('_DfmCheck.exe', lExeName);
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

function TrimMatchingQuotes(const aValue: string): string;
var
  lValue: string;
begin
  lValue := Trim(aValue);
  if Length(lValue) >= 2 then
  begin
    if ((lValue[1] = '"') and (lValue[Length(lValue)] = '"')) or
      ((lValue[1] = '''') and (lValue[Length(lValue)] = '''')) then
      lValue := Copy(lValue, 2, Length(lValue) - 2);
  end;
  Result := Trim(lValue);
end;

function NormalizeRequestedDfmName(const aToken: string): string;
var
  lExt: string;
  lName: string;
begin
  lName := TrimMatchingQuotes(aToken);
  if lName = '' then
    Exit('');

  lName := lName.Replace('/', '\', [rfReplaceAll]);
  lExt := LowerCase(TPath.GetExtension(lName));
  if (lExt <> '') or (Pos('\', lName) > 0) then
    lName := TPath.GetFileNameWithoutExtension(lName);

  Result := UpperCase(Trim(lName));
end;

function RemoveKnownDfmSuffix(const aValue: string): string;
begin
  Result := aValue;
  if EndsText('.DFM', Result) then
    Exit(Copy(Result, 1, Length(Result) - 4));
  if EndsText('_DFM', Result) then
    Exit(Copy(Result, 1, Length(Result) - 4));
end;

function NormalizeResourceToken(const aToken: string): string;
begin
  Result := RemoveKnownDfmSuffix(UpperCase(TrimMatchingQuotes(Trim(aToken))));
end;

function ResourceNamesMatch(const aLeft: string; const aRight: string): Boolean;
var
  lLeft: string;
  lRight: string;
begin
  lLeft := NormalizeResourceToken(aLeft);
  lRight := NormalizeResourceToken(aRight);
  if (lLeft = '') or (lRight = '') then
    Exit(False);
  if SameText(lLeft, lRight) then
    Exit(True);
  if (Length(lLeft) > 1) and (lLeft[1] = 'T') and SameText(Copy(lLeft, 2, MaxInt), lRight) then
    Exit(True);
  if (Length(lRight) > 1) and (lRight[1] = 'T') and SameText(lLeft, Copy(lRight, 2, MaxInt)) then
    Exit(True);
  Result := False;
end;

function TryComputeFileHash(const aFilePath: string; out aHash: string; out aError: string): Boolean;
const
  cFNVOffsetBasis: UInt64 = UInt64($CBF29CE484222325);
  cFNVPrime: UInt64 = UInt64($00000100000001B3);
var
  lBuffer: TBytes;
  lHash: UInt64;
  lIndex: Integer;
  lRead: Integer;
  lStream: TFileStream;
begin
  aError := '';
  aHash := '';
  if not FileExists(aFilePath) then
  begin
    aError := 'File not found: ' + aFilePath;
    Exit(False);
  end;

{$IFOPT Q+}
  {$DEFINE DFMCHECK_HASH_QPLUS}
  {$Q-}
{$ENDIF}
  lHash := cFNVOffsetBasis;
  lStream := TFileStream.Create(aFilePath, fmOpenRead or fmShareDenyNone);
  try
    SetLength(lBuffer, 64 * 1024);
    repeat
      lRead := lStream.Read(lBuffer[0], Length(lBuffer));
      for lIndex := 0 to lRead - 1 do
        lHash := (lHash xor lBuffer[lIndex]) * cFNVPrime;
    until lRead = 0;
  finally
    lStream.Free;
  end;
{$IFDEF DFMCHECK_HASH_QPLUS}
  {$UNDEF DFMCHECK_HASH_QPLUS}
  {$Q+}
{$ENDIF}

  aHash := IntToHex(lHash, 16);
  Result := True;
end;

function BuildDfmCachePath(const aDprojPath: string): string;
begin
  Result := TPath.Combine(ExtractFilePath(aDprojPath), TPath.GetFileNameWithoutExtension(aDprojPath) +
    '.dfmcheck.cache');
end;

function TryCollectDfmModulePathsFromDproj(const aDprojPath: string; const aUnitNames: TStrings; const aPasPaths: TStrings;
  const aDfmPaths: TStrings; out aError: string): Boolean;
var
  lDprDir: string;
  lDprPath: string;
  lDprText: string;
  lDfmPath: string;
  lDprojDir: string;
  lDprojText: string;
  lIncludePath: string;
  lMatch: TMatch;
  lMatches: TMatchCollection;
  lPasPath: string;
  lUnitName: string;
begin
  aError := '';
  if not FileExists(aDprojPath) then
  begin
    aError := 'Dproj file not found: ' + aDprojPath;
    Exit(False);
  end;
  if (aUnitNames = nil) or (aPasPaths = nil) or (aDfmPaths = nil) then
  begin
    aError := 'Cache module collectors are not assigned.';
    Exit(False);
  end;

  lDprojDir := ExcludeTrailingPathDelimiter(ExtractFileDir(aDprojPath));
  lDprojText := TFile.ReadAllText(aDprojPath);
  lDprPath := TPath.ChangeExtension(aDprojPath, '.dpr');
  if not FileExists(lDprPath) then
  begin
    lMatch := TRegEx.Match(lDprojText, '<MainSource>\s*([^<]+?)\s*</MainSource>', [roIgnoreCase, roSingleLine]);
    if lMatch.Success and (lMatch.Groups.Count > 1) then
    begin
      lIncludePath := Trim(lMatch.Groups[1].Value);
      if lIncludePath <> '' then
        lDprPath := TPath.GetFullPath(TPath.Combine(lDprojDir, lIncludePath));
    end;
  end;

  if FileExists(lDprPath) then
  begin
    lDprDir := ExcludeTrailingPathDelimiter(ExtractFileDir(lDprPath));
    lDprText := TFile.ReadAllText(lDprPath);
    lMatches := TRegEx.Matches(lDprText,
      '([A-Za-z_&][A-Za-z0-9_&]*(?:\.[A-Za-z_&][A-Za-z0-9_&]*)*)\s+in\s+''([^'']+\.pas)''', [roIgnoreCase]);
    for lMatch in lMatches do
    begin
      if (not lMatch.Success) or (lMatch.Groups.Count < 3) then
        Continue;
      lUnitName := UpperCase(Trim(lMatch.Groups[1].Value));
      lIncludePath := Trim(lMatch.Groups[2].Value);
      if (lUnitName = '') or (lIncludePath = '') then
        Continue;
      if aUnitNames.IndexOf(lUnitName) >= 0 then
        Continue;
      lPasPath := TPath.GetFullPath(TPath.Combine(lDprDir, lIncludePath));
      if not FileExists(lPasPath) then
        Continue;
      lDfmPath := TPath.ChangeExtension(lPasPath, '.dfm');
      if not FileExists(lDfmPath) then
        Continue;
      aUnitNames.Add(lUnitName);
      aPasPaths.Add(lPasPath);
      aDfmPaths.Add(lDfmPath);
    end;
  end;

  if aUnitNames.Count = 0 then
  begin
    lMatches := TRegEx.Matches(lDprojText, '<DCCReference\b[^>]*\bInclude\s*=\s*"([^"]+)"', [roIgnoreCase]);
    for lMatch in lMatches do
    begin
      if (not lMatch.Success) or (lMatch.Groups.Count < 2) then
        Continue;

      lIncludePath := Trim(lMatch.Groups[1].Value);
      if lIncludePath = '' then
        Continue;
      lIncludePath := lIncludePath.Replace('/', '\', [rfReplaceAll]);
      if not SameText(TPath.GetExtension(lIncludePath), '.pas') then
        Continue;

      lPasPath := TPath.GetFullPath(TPath.Combine(lDprojDir, lIncludePath));
      if not FileExists(lPasPath) then
        Continue;
      lDfmPath := TPath.ChangeExtension(lPasPath, '.dfm');
      if not FileExists(lDfmPath) then
        Continue;

      lUnitName := UpperCase(TPath.GetFileNameWithoutExtension(lPasPath));
      if lUnitName = '' then
        Continue;
      if aUnitNames.IndexOf(lUnitName) >= 0 then
        Continue;

      aUnitNames.Add(lUnitName);
      aPasPaths.Add(lPasPath);
      aDfmPaths.Add(lDfmPath);
    end;
  end;

  Result := True;
end;

function ContainsMatchingResourceName(const aResourceNames: TStrings; const aResourceName: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if aResourceNames = nil then
    Exit(False);
  for i := 0 to aResourceNames.Count - 1 do
  begin
    if ResourceNamesMatch(aResourceNames[i], aResourceName) then
      Exit(True);
  end;
end;

function TryPrepareDfmCacheSelection(const aDprojPath: string; out aModules: TArray<TDfmCacheModule>;
  out aFilterCsv: string; out aDisplay: string; out aStats: TDfmCacheStats; out aError: string): Boolean;
var
  lCachedDfmHash: string;
  lCachedPasHash: string;
  lCachedResourceName: string;
  lCachedStatus: string;
  lCacheIni: TMemIniFile;
  lCacheSection: string;
  lClassName: string;
  lDfmPaths: TStringList;
  lFilterList: TStringList;
  lIndex: Integer;
  lModule: TDfmCacheModule;
  lPasPaths: TStringList;
  lUnitNames: TStringList;
begin
  aError := '';
  aFilterCsv := '';
  aDisplay := '';
  aModules := nil;
  aStats := Default(TDfmCacheStats);
  aStats.fEnabled := True;
  aStats.fFilePath := BuildDfmCachePath(aDprojPath);

  lUnitNames := TStringList.Create;
  lPasPaths := TStringList.Create;
  lDfmPaths := TStringList.Create;
  lFilterList := TStringList.Create;
  lCacheIni := TMemIniFile.Create(aStats.fFilePath);
  try
    lUnitNames.CaseSensitive := False;
    lUnitNames.Sorted := False;
    lUnitNames.Duplicates := TDuplicates.dupIgnore;
    lPasPaths.CaseSensitive := False;
    lPasPaths.Sorted := False;
    lPasPaths.Duplicates := TDuplicates.dupIgnore;
    lDfmPaths.CaseSensitive := False;
    lDfmPaths.Sorted := False;
    lDfmPaths.Duplicates := TDuplicates.dupIgnore;
    lFilterList.CaseSensitive := False;
    lFilterList.Sorted := True;
    lFilterList.Duplicates := TDuplicates.dupIgnore;

    if not TryCollectDfmModulePathsFromDproj(aDprojPath, lUnitNames, lPasPaths, lDfmPaths, aError) then
      Exit(False);

    SetLength(aModules, lUnitNames.Count);
    aStats.fTotal := lUnitNames.Count;

    for lIndex := 0 to lUnitNames.Count - 1 do
    begin
      if not TryComputeFileHash(lPasPaths[lIndex], lCachedPasHash, aError) then
        Exit(False);
      if not TryComputeFileHash(lDfmPaths[lIndex], lCachedDfmHash, aError) then
        Exit(False);

      lModule := Default(TDfmCacheModule);
      lModule.fUnitName := lUnitNames[lIndex];
      lModule.fPasPath := lPasPaths[lIndex];
      lModule.fDfmPath := lDfmPaths[lIndex];
      lModule.fPasHash := lCachedPasHash;
      lModule.fDfmHash := lCachedDfmHash;
      lModule.fNeedsValidation := True;

      lCacheSection := 'Unit:' + lModule.fUnitName;
      lCachedResourceName := NormalizeResourceToken(lCacheIni.ReadString(lCacheSection, 'ResourceName', ''));
      lCachedStatus := UpperCase(Trim(lCacheIni.ReadString(lCacheSection, 'Status', '')));
      lCachedPasHash := UpperCase(Trim(lCacheIni.ReadString(lCacheSection, 'PasHash', '')));
      lCachedDfmHash := UpperCase(Trim(lCacheIni.ReadString(lCacheSection, 'DfmHash', '')));

      if SameText(lCachedPasHash, lModule.fPasHash) and SameText(lCachedDfmHash, lModule.fDfmHash) and
        (lCachedResourceName <> '') then
      begin
        lModule.fResourceName := lCachedResourceName;
        if SameText(lCachedStatus, 'OK') then
          lModule.fNeedsValidation := False;
      end;

      if lModule.fResourceName = '' then
      begin
        try
          lClassName := Trim(ReadFormClassNameFromFile(lModule.fDfmPath));
        except
          on E: Exception do
          begin
            aError := 'Failed to read root form class from DFM (' + lModule.fDfmPath + '): ' + E.Message;
            Exit(False);
          end;
        end;
        lModule.fResourceName := NormalizeResourceToken(lClassName);
      end;

      if lModule.fResourceName = '' then
      begin
        aError := 'Could not determine form class/resource name from DFM: ' + lModule.fDfmPath;
        Exit(False);
      end;

      if lModule.fNeedsValidation then
        lFilterList.Add(lModule.fResourceName)
      else
        Inc(aStats.fSkippedUnchanged);

      aModules[lIndex] := lModule;
    end;

    aStats.fToValidate := lFilterList.Count;
    if lFilterList.Count > 0 then
    begin
      aFilterCsv := String.Join(',', lFilterList.ToStringArray);
      aDisplay := aFilterCsv.Replace(',', ', ', [rfReplaceAll]);
    end;

    Result := True;
  finally
    lCacheIni.Free;
    lFilterList.Free;
    lDfmPaths.Free;
    lPasPaths.Free;
    lUnitNames.Free;
  end;
end;

function TryWriteDfmCache(const aCachePath: string; const aModules: TArray<TDfmCacheModule>;
  const aFailedResources: TStrings; out aError: string): Boolean;
var
  lCacheIni: TMemIniFile;
  lCacheSection: string;
  lIndex: Integer;
  lKeepSections: TStringList;
  lSections: TStringList;
  lStatus: string;
begin
  aError := '';
  lCacheIni := TMemIniFile.Create(aCachePath);
  lSections := TStringList.Create;
  lKeepSections := TStringList.Create;
  try
    try
      lKeepSections.CaseSensitive := False;
      lKeepSections.Sorted := True;
      lKeepSections.Duplicates := TDuplicates.dupIgnore;

      lCacheIni.WriteString('Meta', 'Version', '1');
      for lIndex := Low(aModules) to High(aModules) do
      begin
        lCacheSection := 'Unit:' + aModules[lIndex].fUnitName;
        lKeepSections.Add(lCacheSection);
        lCacheIni.WriteString(lCacheSection, 'ResourceName', aModules[lIndex].fResourceName);
        lCacheIni.WriteString(lCacheSection, 'PasHash', aModules[lIndex].fPasHash);
        lCacheIni.WriteString(lCacheSection, 'DfmHash', aModules[lIndex].fDfmHash);
        if aModules[lIndex].fNeedsValidation and ContainsMatchingResourceName(aFailedResources,
          aModules[lIndex].fResourceName) then
          lStatus := 'FAIL'
        else
          lStatus := 'OK';
        lCacheIni.WriteString(lCacheSection, 'Status', lStatus);
      end;

      lCacheIni.ReadSections(lSections);
      for lIndex := 0 to lSections.Count - 1 do
      begin
        lCacheSection := lSections[lIndex];
        if not StartsText('Unit:', lCacheSection) then
          Continue;
        if lKeepSections.IndexOf(lCacheSection) >= 0 then
          Continue;
        lCacheIni.EraseSection(lCacheSection);
      end;

      lCacheIni.UpdateFile;
      Result := True;
    except
      on E: Exception do
      begin
        aError := 'Failed to write DFM cache file (' + aCachePath + '): ' + E.Message;
        Result := False;
      end;
    end;
  finally
    lKeepSections.Free;
    lSections.Free;
    lCacheIni.Free;
  end;
end;

function TryAppendDprojClassAliases(const aDprojPath: string; const aFilterList: TStringList; out aError: string): Boolean;
var
  lClassName: string;
  lDfmPath: string;
  lDprojDir: string;
  lDprojText: string;
  lFilterIndex: Integer;
  lIncludePath: string;
  lMatch: TMatch;
  lMatches: TMatchCollection;
  lPasPath: string;
  lRequestedName: string;
begin
  aError := '';
  if (aFilterList = nil) or (aFilterList.Count = 0) then
    Exit(True);
  if (Trim(aDprojPath) = '') or (not FileExists(aDprojPath)) then
    Exit(True);

  lDprojDir := ExcludeTrailingPathDelimiter(ExtractFileDir(aDprojPath));
  lDprojText := TFile.ReadAllText(aDprojPath);
  lMatches := TRegEx.Matches(lDprojText, '<DCCReference\b[^>]*\bInclude\s*=\s*"([^"]+)"', [roIgnoreCase]);
  for lMatch in lMatches do
  begin
    if (not lMatch.Success) or (lMatch.Groups.Count < 2) then
      Continue;

    lIncludePath := Trim(lMatch.Groups[1].Value);
    if lIncludePath = '' then
      Continue;
    lIncludePath := lIncludePath.Replace('/', '\', [rfReplaceAll]);
    if not SameText(TPath.GetExtension(lIncludePath), '.pas') then
      Continue;

    lRequestedName := UpperCase(TPath.GetFileNameWithoutExtension(lIncludePath));
    if lRequestedName = '' then
      Continue;
    if aFilterList.IndexOf(lRequestedName) < 0 then
      Continue;

    lPasPath := TPath.GetFullPath(TPath.Combine(lDprojDir, lIncludePath));
    lDfmPath := TPath.ChangeExtension(lPasPath, '.dfm');
    if not FileExists(lDfmPath) then
      Continue;

    try
      lClassName := UpperCase(Trim(ReadFormClassNameFromFile(lDfmPath)));
    except
      on E: Exception do
      begin
        aError := 'Failed to read root form class from DFM (' + lDfmPath + '): ' + E.Message;
        Exit(False);
      end;
    end;

    if lClassName <> '' then
    begin
      lFilterIndex := aFilterList.IndexOf(lRequestedName);
      if lFilterIndex >= 0 then
        aFilterList.Delete(lFilterIndex);
      aFilterList.Add(lClassName);
    end;
  end;

  Result := True;
end;

function TryBuildValidatorFilterCsv(const aFilterText: string; const aDprojPath: string; out aFilterCsv: string;
  out aDisplay: string; out aError: string): Boolean;
var
  lFilterList: TStringList;
  lPart: string;
  lParts: TArray<string>;
  lResourceName: string;
begin
  aError := '';
  aFilterCsv := '';
  aDisplay := '';
  lFilterList := TStringList.Create;
  try
    lFilterList.CaseSensitive := False;
    lFilterList.Sorted := True;
    lFilterList.Duplicates := TDuplicates.dupIgnore;

    lParts := aFilterText.Split([',', ';']);
    for lPart in lParts do
    begin
      lResourceName := NormalizeRequestedDfmName(lPart);
      if lResourceName <> '' then
        lFilterList.Add(lResourceName);
    end;

    if lFilterList.Count = 0 then
    begin
      aError := 'No valid DFM names were provided for --dfm.';
      Exit(False);
    end;

    if not TryAppendDprojClassAliases(aDprojPath, lFilterList, aError) then
      Exit(False);

    aFilterCsv := String.Join(',', lFilterList.ToStringArray);
    aDisplay := aFilterCsv.Replace(',', ', ', [rfReplaceAll]);
    Result := True;
  finally
    lFilterList.Free;
  end;
end;

function TryBuildValidatorArguments(const aOptions: TAppOptions; const aDprojPath: string; out aValidatorArgs: string;
  out aScopeText: string; out aError: string): Boolean;
var
  lDisplayParts: TArray<string>;
  lFilterCsv: string;
  lPreview: string;
  lResourceCount: Integer;
begin
  aError := '';
  aValidatorArgs := '--all';
  aScopeText := 'all DFM resources';

  if aOptions.fDfmCheckAll then
    Exit(True);

  if Trim(aOptions.fDfmCheckFilter) = '' then
    Exit(True);

  if not TryBuildValidatorFilterCsv(aOptions.fDfmCheckFilter, aDprojPath, lFilterCsv, aScopeText, aError) then
    Exit(False);

  aValidatorArgs := '--dfm=' + QuoteCmdArg(lFilterCsv);
  lDisplayParts := lFilterCsv.Split([',']);
  lResourceCount := Length(lDisplayParts);
  if lResourceCount <= 0 then
    lResourceCount := 1;
  if lResourceCount <= 5 then
    aScopeText := Format('selected DFM resources (%d): %s', [lResourceCount, lFilterCsv.Replace(',', ', ', [rfReplaceAll])])
  else
  begin
    lPreview := String.Join(', ', Copy(lDisplayParts, 0, 5));
    aScopeText := Format('selected DFM resources (%d): %s, ...', [lResourceCount, lPreview]);
  end;
  Result := True;
end;

function TryFindModuleByResourceName(const aModules: TArray<TDfmCacheModule>; const aResourceName: string;
  out aModule: TDfmCacheModule): Boolean;
var
  i: Integer;
  lResourceName: string;
begin
  Result := False;
  aModule := Default(TDfmCacheModule);
  lResourceName := NormalizeResourceToken(aResourceName);
  if lResourceName = '' then
    Exit(False);
  for i := Low(aModules) to High(aModules) do
  begin
    if ResourceNamesMatch(aModules[i].fResourceName, lResourceName) then
    begin
      aModule := aModules[i];
      Exit(True);
    end;
  end;
end;

function TryCollectDfmModuleMetadata(const aDprojPath: string; out aModules: TArray<TDfmCacheModule>;
  out aError: string): Boolean;
var
  lClassName: string;
  lDfmPaths: TStringList;
  lIndex: Integer;
  lModule: TDfmCacheModule;
  lPasPaths: TStringList;
  lUnitNames: TStringList;
begin
  aError := '';
  aModules := nil;
  lUnitNames := TStringList.Create;
  lPasPaths := TStringList.Create;
  lDfmPaths := TStringList.Create;
  try
    lUnitNames.CaseSensitive := False;
    lUnitNames.Sorted := False;
    lUnitNames.Duplicates := TDuplicates.dupIgnore;
    lPasPaths.CaseSensitive := False;
    lPasPaths.Sorted := False;
    lPasPaths.Duplicates := TDuplicates.dupIgnore;
    lDfmPaths.CaseSensitive := False;
    lDfmPaths.Sorted := False;
    lDfmPaths.Duplicates := TDuplicates.dupIgnore;

    if not TryCollectDfmModulePathsFromDproj(aDprojPath, lUnitNames, lPasPaths, lDfmPaths, aError) then
      Exit(False);

    SetLength(aModules, lUnitNames.Count);
    for lIndex := 0 to lUnitNames.Count - 1 do
    begin
      lClassName := '';
      try
        lClassName := Trim(ReadFormClassNameFromFile(lDfmPaths[lIndex]));
      except
        on E: Exception do
        begin
          aError := 'Failed to read root form class from DFM (' + lDfmPaths[lIndex] + '): ' + E.Message;
          Exit(False);
        end;
      end;

      lModule := Default(TDfmCacheModule);
      lModule.fUnitName := lUnitNames[lIndex];
      lModule.fPasPath := lPasPaths[lIndex];
      lModule.fDfmPath := lDfmPaths[lIndex];
      lModule.fResourceName := NormalizeResourceToken(lClassName);
      if lModule.fResourceName = '' then
        lModule.fResourceName := NormalizeResourceToken(TPath.GetFileNameWithoutExtension(lDfmPaths[lIndex]));
      aModules[lIndex] := lModule;
    end;

    Result := True;
  finally
    lDfmPaths.Free;
    lPasPaths.Free;
    lUnitNames.Free;
  end;
end;

procedure EmitVerboseLine(const aVerbose: Boolean; const aOutput: TDfmCheckOutputProc; const aLine: string);
begin
  if not aVerbose then
    Exit;
  EmitLine(aOutput, aLine);
end;

function TryParseValidatorSummaryLine(const aLine: string; out aSummary: TDfmValidationSummary): Boolean;
var
  lMatch: TMatch;
begin
  Result := False;
  if Pos('DFM stream validation summary:', aLine) <> 1 then
    Exit(False);

  lMatch := TRegEx.Match(aLine,
    'streamed=(\d+)\s+skipped=(\d+)\s+failed=(\d+)\s+requested=(\d+)\s+matched=(\d+)', [roIgnoreCase]);
  if not lMatch.Success then
    Exit(False);

  aSummary.fHasSummary := True;
  aSummary.fStreamed := StrToIntDef(lMatch.Groups[1].Value, 0);
  aSummary.fSkipped := StrToIntDef(lMatch.Groups[2].Value, 0);
  aSummary.fFailed := StrToIntDef(lMatch.Groups[3].Value, 0);
  aSummary.fRequested := StrToIntDef(lMatch.Groups[4].Value, 0);
  aSummary.fMatched := StrToIntDef(lMatch.Groups[5].Value, 0);
  Result := True;
end;

function ExtractResourceNameFromDiagnosticLine(const aPrefix: string; const aLine: string): string; forward;

function ExtractFailedResourceName(const aLine: string): string;
begin
  Result := ExtractResourceNameFromDiagnosticLine('FAIL', aLine);
end;

function ExtractWarnedResourceName(const aLine: string): string;
begin
  Result := ExtractResourceNameFromDiagnosticLine('WARN', aLine);
end;

function ExtractResourceNameFromDiagnosticLine(const aPrefix: string; const aLine: string): string;
var
  lArrowPos: Integer;
  lTail: string;
begin
  Result := '';
  if not StartsText(aPrefix + ' ', aLine) then
    Exit('');
  lTail := Trim(Copy(aLine, Length(aPrefix) + 2, MaxInt));
  if lTail = '' then
    Exit('');
  lArrowPos := Pos('->', lTail);
  if lArrowPos > 0 then
    lTail := Trim(Copy(lTail, 1, lArrowPos - 1));
  Result := NormalizeResourceToken(lTail);
end;

function ExtractFailReasonText(const aLine: string): string;
var
  lArrowPos: Integer;
begin
  Result := '';
  lArrowPos := Pos('->', aLine);
  if lArrowPos <= 0 then
    Exit('');
  Result := Trim(Copy(aLine, lArrowPos + 2, MaxInt));
end;

function BuildDiagnosticLineWithModuleContext(const aLine: string; const aPrefix: string;
  const aModules: TArray<TDfmCacheModule>): string;
var
  lModule: TDfmCacheModule;
  lResourceName: string;
begin
  Result := aLine;
  lResourceName := ExtractResourceNameFromDiagnosticLine(aPrefix, aLine);
  if lResourceName = '' then
    Exit(Result);
  if not TryFindModuleByResourceName(aModules, lResourceName, lModule) then
    Exit(Result);
  Result := Result + Format(' [unit=%s pas=%s dfm=%s]', [lModule.fUnitName, lModule.fPasPath, lModule.fDfmPath]);
end;

function BuildFailLineWithModuleContext(const aFailLine: string; const aModules: TArray<TDfmCacheModule>): string;
begin
  Result := BuildDiagnosticLineWithModuleContext(aFailLine, 'FAIL', aModules);
end;

function BuildWarnLineWithModuleContext(const aWarnLine: string; const aModules: TArray<TDfmCacheModule>): string;
begin
  Result := BuildDiagnosticLineWithModuleContext(aWarnLine, 'WARN', aModules);
end;

function TryExtractFailMember(const aReason: string; out aMemberPath: string): Boolean;
var
  lMatch: TMatch;
begin
  aMemberPath := '';
  lMatch := TRegEx.Match(aReason, 'Error\s+reading\s+([^:]+):', [roIgnoreCase]);
  if not lMatch.Success then
    Exit(False);
  aMemberPath := Trim(lMatch.Groups[1].Value);
  Result := aMemberPath <> '';
end;

function TryExtractFailMethodName(const aReason: string; out aMethodName: string): Boolean;
var
  lMatch: TMatch;
begin
  aMethodName := '';
  lMatch := TRegEx.Match(aReason, 'method\s+''([^'']+)''', [roIgnoreCase]);
  if not lMatch.Success then
    Exit(False);
  aMethodName := Trim(lMatch.Groups[1].Value);
  Result := aMethodName <> '';
end;

function BuildMethodDeclarationSnippet(const aLines: TStrings; const aLineIndex: Integer): string;
const
  cMaxLines = 4;
var
  lLineText: string;
  lResultText: string;
  lScanIndex: Integer;
  lTaken: Integer;
begin
  Result := '';
  if (aLines = nil) or (aLineIndex < 0) or (aLineIndex >= aLines.Count) then
    Exit('');

  lResultText := '';
  lTaken := 0;
  for lScanIndex := aLineIndex to aLines.Count - 1 do
  begin
    lLineText := Trim(aLines[lScanIndex]);
    if lLineText = '' then
      Continue;
    if lResultText = '' then
      lResultText := lLineText
    else
      lResultText := lResultText + ' ' + lLineText;
    Inc(lTaken);
    if (Pos(';', lLineText) > 0) or (lTaken >= cMaxLines) then
      Break;
  end;

  Result := Trim(lResultText);
end;

function TryFindHandlerDeclarationInPas(const aPasPath: string; const aMethodName: string;
  out aLineNumber: Integer; out aDeclaration: string): Boolean;
var
  i: Integer;
  lLines: TStringList;
  lMatch: TMatch;
  lMethodToken: string;
  lQualifiedRegex: string;
  lUnqualifiedRegex: string;

  function TryMatch(const aRegex: string): Boolean;
  var
    lIndex: Integer;
  begin
    Result := False;
    for lIndex := 0 to lLines.Count - 1 do
    begin
      lMatch := TRegEx.Match(lLines[lIndex], aRegex, [roIgnoreCase]);
      if not lMatch.Success then
        Continue;

      aLineNumber := lIndex + 1;
      aDeclaration := BuildMethodDeclarationSnippet(lLines, lIndex);
      if aDeclaration = '' then
        aDeclaration := Trim(lLines[lIndex]);
      Exit(True);
    end;
  end;
begin
  Result := False;
  aLineNumber := 0;
  aDeclaration := '';
  if (Trim(aPasPath) = '') or (Trim(aMethodName) = '') or (not FileExists(aPasPath)) then
    Exit(False);

  lMethodToken := Trim(aMethodName);
  lQualifiedRegex := '^\s*(class\s+)?(procedure|function)\s+[A-Za-z_][A-Za-z0-9_]*\.(' +
    TRegEx.Escape(lMethodToken) + ')\b';
  lUnqualifiedRegex := '^\s*(class\s+)?(procedure|function)\s+(' +
    TRegEx.Escape(lMethodToken) + ')\b';
  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aPasPath);
    if TryMatch(lQualifiedRegex) then
      Exit(True);
    Result := TryMatch(lUnqualifiedRegex);
  finally
    lLines.Free;
  end;
end;

function TryExtractEventPropertyName(const aMemberPath: string; out aEventName: string): Boolean;
var
  lDotPos: Integer;
  lTail: string;
begin
  aEventName := '';
  lTail := Trim(aMemberPath);
  if lTail = '' then
    Exit(False);

  lDotPos := LastDelimiter('.', lTail);
  if lDotPos > 0 then
    lTail := Trim(Copy(lTail, lDotPos + 1, MaxInt));
  if lTail = '' then
    Exit(False);
  if not StartsText('On', lTail) then
    Exit(False);

  aEventName := lTail;
  Result := True;
end;

function TryGetDfmPropertyValue(const aObject: TDfmTextObjectInfo; const aPropertyName: string; out aValue: string): Boolean;
var
  lIndex: Integer;
begin
  aValue := '';
  if aObject = nil then
    Exit(False);
  lIndex := aObject.fProperties.IndexOfName(aPropertyName);
  if lIndex < 0 then
    Exit(False);
  aValue := TrimMatchingQuotes(Trim(aObject.fProperties.ValueFromIndex[lIndex]));
  Result := aValue <> '';
end;

function TryParseDfmTextObjects(const aDfmPath: string; const aObjects: TObjectList<TDfmTextObjectInfo>;
  out aError: string): Boolean;
var
  lCurrentObject: TDfmTextObjectInfo;
  lLine: string;
  lLines: TStringList;
  lMatch: TMatch;
  lObjectStack: TList<TDfmTextObjectInfo>;
  lPropertyName: string;
  lPropertyValue: string;
  lIndex: Integer;
begin
  Result := False;
  aError := '';
  if (Trim(aDfmPath) = '') or (not FileExists(aDfmPath)) then
  begin
    aError := 'DFM file not found: ' + aDfmPath;
    Exit(False);
  end;
  if aObjects = nil then
  begin
    aError := 'Object list is not assigned.';
    Exit(False);
  end;

  lLines := TStringList.Create;
  lObjectStack := TList<TDfmTextObjectInfo>.Create;
  try
    try
      lLines.LoadFromFile(aDfmPath);
      for lIndex := 0 to lLines.Count - 1 do
      begin
        lLine := lLines[lIndex];
        lMatch := TRegEx.Match(lLine,
          '^\s*(object|inherited|inline)\s+([A-Za-z0-9_]+)\s*:\s*([A-Za-z0-9_.]+)', [roIgnoreCase]);
        if lMatch.Success then
        begin
          lCurrentObject := TDfmTextObjectInfo.Create;
          lCurrentObject.fName := lMatch.Groups[2].Value;
          lCurrentObject.fClassName := lMatch.Groups[3].Value;
          lCurrentObject.fStartLine := lIndex + 1;
          if lObjectStack.Count > 0 then
          begin
            lCurrentObject.fParentName := lObjectStack.Last.fName;
            lCurrentObject.fParentClassName := lObjectStack.Last.fClassName;
          end;
          aObjects.Add(lCurrentObject);
          lObjectStack.Add(lCurrentObject);
          Continue;
        end;

        if SameText(Trim(lLine), 'end') then
        begin
          if lObjectStack.Count > 0 then
          begin
            lObjectStack.Last.fEndLine := lIndex + 1;
            lObjectStack.Delete(lObjectStack.Count - 1);
          end;
          Continue;
        end;

        if lObjectStack.Count = 0 then
          Continue;
        lMatch := TRegEx.Match(lLine, '^\s*([A-Za-z0-9_.]+)\s*=\s*(.+?)\s*$', [roIgnoreCase]);
        if not lMatch.Success then
          Continue;
        lPropertyName := lMatch.Groups[1].Value;
        lPropertyValue := lMatch.Groups[2].Value;
        lObjectStack.Last.fProperties.Values[lPropertyName] := lPropertyValue;
        lObjectStack.Last.fPropertyLines.Values[lPropertyName] := IntToStr(lIndex + 1);
      end;
      Result := True;
    except
      on E: Exception do
      begin
        aError := E.ClassName + ': ' + E.Message;
        Result := False;
      end;
    end;
  finally
    lObjectStack.Free;
    lLines.Free;
  end;
end;

function TryFindDfmObjectByName(const aObjects: TObjectList<TDfmTextObjectInfo>; const aObjectName: string;
  out aObject: TDfmTextObjectInfo): Boolean;
var
  lCandidate: TDfmTextObjectInfo;
begin
  aObject := nil;
  if aObjects = nil then
    Exit(False);
  for lCandidate in aObjects do
  begin
    if not SameText(lCandidate.fName, aObjectName) then
      Continue;
    aObject := lCandidate;
    Exit(True);
  end;
  Result := False;
end;

function TryFindDfmObjectLine(const aDfmPath: string; const aObjectName: string; out aLineNumber: Integer): Boolean;
var
  lLine: string;
  lLines: TStringList;
  lMatch: TMatch;
  lIndex: Integer;
begin
  Result := False;
  aLineNumber := 0;
  if (Trim(aDfmPath) = '') or (Trim(aObjectName) = '') or (not FileExists(aDfmPath)) then
    Exit(False);
  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aDfmPath);
    for lIndex := 0 to lLines.Count - 1 do
    begin
      lLine := lLines[lIndex];
      lMatch := TRegEx.Match(lLine, '^\s*(object|inherited|inline)\s+([A-Za-z0-9_]+)\s*:', [roIgnoreCase]);
      if not lMatch.Success then
        Continue;
      if not SameText(lMatch.Groups[2].Value, aObjectName) then
        Continue;
      aLineNumber := lIndex + 1;
      Exit(True);
    end;
  finally
    lLines.Free;
  end;
end;

function TryFindDfmPropertyLine(const aDfmPath: string; const aObjectName: string; const aPropertyName: string;
  out aLineNumber: Integer): Boolean;
var
  lCurrentDepth: Integer;
  lLine: string;
  lLines: TStringList;
  lMatch: TMatch;
  lIndex: Integer;
  lTargetDepth: Integer;
begin
  Result := False;
  aLineNumber := 0;
  if (Trim(aDfmPath) = '') or (Trim(aObjectName) = '') or (Trim(aPropertyName) = '') or (not FileExists(aDfmPath)) then
    Exit(False);

  lCurrentDepth := 0;
  lTargetDepth := 0;
  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aDfmPath);
    for lIndex := 0 to lLines.Count - 1 do
    begin
      lLine := lLines[lIndex];
      lMatch := TRegEx.Match(lLine, '^\s*(object|inherited|inline)\s+([A-Za-z0-9_]+)\s*:', [roIgnoreCase]);
      if lMatch.Success then
      begin
        Inc(lCurrentDepth);
        if (lTargetDepth = 0) and SameText(lMatch.Groups[2].Value, aObjectName) then
          lTargetDepth := lCurrentDepth;
        Continue;
      end;

      if SameText(Trim(lLine), 'end') then
      begin
        if lTargetDepth = lCurrentDepth then
          lTargetDepth := 0;
        Dec(lCurrentDepth);
        Continue;
      end;

      if lTargetDepth = 0 then
        Continue;
      if lCurrentDepth <> lTargetDepth then
        Continue;
      if not TRegEx.IsMatch(lLine, '^\s*' + TRegEx.Escape(aPropertyName) + '\s*=', [roIgnoreCase]) then
        Continue;
      aLineNumber := lIndex + 1;
      Exit(True);
    end;
  finally
    lLines.Free;
  end;
end;

procedure EmitSourceContextClue(const aOutput: TDfmCheckOutputProc; const aPrefix: string; const aFilePath: string;
  const aLineNumber: Integer; const aDiagnosticsDefaults: TDiagnosticsDefaults);
var
  lContext: TSourceContextSnippet;
  lContextError: string;
  lContextLine: string;
  lContextLines: TArray<string>;
begin
  if (aLineNumber <= 0) or (not ShouldEmitSourceContext(aDiagnosticsDefaults.fSourceContextMode, True)) then
    Exit;
  if not TryReadSourceContext(aFilePath, aLineNumber, aDiagnosticsDefaults.fSourceContextLines, lContext, lContextError) then
    Exit;
  lContextLines := FormatSourceContextLines(lContext);
  for lContextLine in lContextLines do
    EmitLine(aOutput, aPrefix + lContextLine);
end;

function TryDiagnoseStandaloneBitBtnActionWarning(const aModule: TDfmCacheModule; const aWarnReason: string;
  out aPromotion: TDfmWarningPromotion; out aError: string): Boolean;
var
  lActionName: string;
  lActionObject: TDfmTextObjectInfo;
  lCandidateCount: Integer;
  lDfmObject: TDfmTextObjectInfo;
  lDfmObjects: TObjectList<TDfmTextObjectInfo>;
  lImageName: string;
  lImagesName: string;
begin
  Result := False;
  aError := '';
  aPromotion := Default(TDfmWarningPromotion);
  if Pos('EAccessViolation', aWarnReason) <= 0 then
    Exit(False);
  if (Trim(aModule.fDfmPath) = '') or (not FileExists(aModule.fDfmPath)) then
  begin
    aError := 'DFM file not found for warning diagnosis: ' + aModule.fDfmPath;
    Exit(False);
  end;

  lDfmObjects := TObjectList<TDfmTextObjectInfo>.Create(True);
  try
    if not TryParseDfmTextObjects(aModule.fDfmPath, lDfmObjects, aError) then
      Exit(False);
    lCandidateCount := 0;
    for lDfmObject in lDfmObjects do
    begin
      if not SameText(lDfmObject.fClassName, 'TBitBtn') then
        Continue;
      if not TryGetDfmPropertyValue(lDfmObject, 'Action', lActionName) then
        Continue;
      if not TryGetDfmPropertyValue(lDfmObject, 'Images', lImagesName) then
        Continue;
      if not TryFindDfmObjectByName(lDfmObjects, lActionName, lActionObject) then
        Continue;
      if not SameText(lActionObject.fClassName, 'TAction') then
        Continue;
      if Pos('ACTIONLIST', UpperCase(lActionObject.fParentClassName)) > 0 then
        Continue;

      Inc(lCandidateCount);
      if lCandidateCount <> 1 then
        Continue;

      aPromotion := Default(TDfmWarningPromotion);
      aPromotion.fButtonName := lDfmObject.fName;
      aPromotion.fButtonClassName := lDfmObject.fClassName;
      aPromotion.fButtonObjectLine := lDfmObject.fStartLine;
      aPromotion.fActionName := lActionName;
      aPromotion.fActionParentClassName := lActionObject.fParentClassName;
      aPromotion.fActionObjectLine := lActionObject.fStartLine;
      aPromotion.fImagesName := lImagesName;
      aPromotion.fActionPropertyLine := StrToIntDef(lDfmObject.fPropertyLines.Values['Action'], 0);
      aPromotion.fImagesPropertyLine := StrToIntDef(lDfmObject.fPropertyLines.Values['Images'], 0);
      TryGetDfmPropertyValue(lDfmObject, 'ImageName', lImageName);
      aPromotion.fImageName := lImageName;
      aPromotion.fImageNamePropertyLine := StrToIntDef(lDfmObject.fPropertyLines.Values['ImageName'], 0);
    end;
    Result := lCandidateCount = 1;
  finally
    lDfmObjects.Free;
  end;
end;

function EmitPromotedWarningGuidance(const aOutput: TDfmCheckOutputProc; const aWarnedResources: TStrings;
  const aWarnReasons: TStrings; const aModules: TArray<TDfmCacheModule>; const aDiagnosticsDefaults: TDiagnosticsDefaults;
  const aFailedResources: TStrings): Integer;
var
  lDiagnosticError: string;
  lHasModule: Boolean;
  lModule: TDfmCacheModule;
  lPromotion: TDfmWarningPromotion;
  lResourceName: string;
  lWarnReason: string;
  lIndex: Integer;
begin
  Result := 0;
  if aWarnedResources = nil then
    Exit;

  for lIndex := 0 to aWarnedResources.Count - 1 do
  begin
    lResourceName := NormalizeResourceToken(aWarnedResources[lIndex]);
    if lResourceName = '' then
      Continue;

    lHasModule := TryFindModuleByResourceName(aModules, lResourceName, lModule);
    if not lHasModule then
      Continue;

    lWarnReason := '';
    if aWarnReasons <> nil then
      lWarnReason := Trim(aWarnReasons.Values[lResourceName]);
    if not TryDiagnoseStandaloneBitBtnActionWarning(lModule, lWarnReason, lPromotion, lDiagnosticError) then
      Continue;

    EmitLine(aOutput, Format('[dfm-check] FAIL diagnosis: resource=%s dfm=%s:%d component=%s action=%s cause=standalone TAction + TBitBtn Images/ImageName can AV during streaming',
      [lResourceName, lModule.fDfmPath, lPromotion.fButtonObjectLine, lPromotion.fButtonName, lPromotion.fActionName]));
    EmitLine(aOutput, Format('[dfm-check] WARN target: resource=%s unit=%s pas=%s dfm=%s',
      [lResourceName, lModule.fUnitName, lModule.fPasPath, lModule.fDfmPath]));
    EmitLine(aOutput, Format('[dfm-check] WARN clue: component=%s class=%s',
      [lPromotion.fButtonName, lPromotion.fButtonClassName]));
    if lPromotion.fButtonObjectLine > 0 then
      EmitLine(aOutput, Format('[dfm-check] WARN clue: component declaration line=%d', [lPromotion.fButtonObjectLine]));
    if lPromotion.fActionPropertyLine > 0 then
      EmitLine(aOutput, Format('[dfm-check] WARN clue: component property line=%d: Action=%s',
        [lPromotion.fActionPropertyLine, lPromotion.fActionName]));
    if lPromotion.fImagesPropertyLine > 0 then
      EmitLine(aOutput, Format('[dfm-check] WARN clue: component property line=%d: Images=%s',
        [lPromotion.fImagesPropertyLine, lPromotion.fImagesName]));
    if (lPromotion.fImageName <> '') and (lPromotion.fImageNamePropertyLine > 0) then
      EmitLine(aOutput, Format('[dfm-check] WARN clue: component property line=%d: ImageName=%s',
        [lPromotion.fImageNamePropertyLine, lPromotion.fImageName]));
    if lPromotion.fActionParentClassName <> '' then
      EmitLine(aOutput, Format('[dfm-check] WARN clue: action=%s is a standalone TAction (parent=%s).',
        [lPromotion.fActionName, lPromotion.fActionParentClassName]))
    else
      EmitLine(aOutput, Format('[dfm-check] WARN clue: action=%s is a standalone TAction.', [lPromotion.fActionName]));
    if lPromotion.fActionObjectLine > 0 then
      EmitLine(aOutput, Format('[dfm-check] WARN clue: action declaration line=%d', [lPromotion.fActionObjectLine]));
    EmitLine(aOutput,
      '[dfm-check] WARN clue: TBitBtn with button-local Images/ImageName plus a standalone TAction can AV during VCL DFM fixups in TBitBtnActionLink.IsGlyphLinked when ActionList=nil.');
    EmitLine(aOutput,
      '[dfm-check] WARN clue: move the action into a TActionList or stop mixing Action with button-local Images/ImageName.');
    EmitSourceContextClue(aOutput, '[dfm-check] WARN clue: ', lModule.fDfmPath, lPromotion.fButtonObjectLine, aDiagnosticsDefaults);
    if (lPromotion.fActionObjectLine > 0) and (lPromotion.fActionObjectLine <> lPromotion.fButtonObjectLine) then
      EmitSourceContextClue(aOutput, '[dfm-check] WARN clue: ', lModule.fDfmPath, lPromotion.fActionObjectLine, aDiagnosticsDefaults);
    if aFailedResources <> nil then
      aFailedResources.Add(lResourceName);
    Inc(Result);
  end;
end;

procedure EmitFailedResourceGuidance(const aOutput: TDfmCheckOutputProc; const aFailedResources: TStrings;
  const aFailReasons: TStrings; const aModules: TArray<TDfmCacheModule>;
  const aDiagnosticsDefaults: TDiagnosticsDefaults);
var
  lContext: TSourceContextSnippet;
  lContextError: string;
  lContextLine: string;
  lContextLines: TArray<string>;
  lDeclaration: string;
  lDeclarationLine: Integer;
  lEventName: string;
  lFailReason: string;
  lHasModule: Boolean;
  lMemberPath: string;
  lMethodName: string;
  lModule: TDfmCacheModule;
  lResourceName: string;
  i: Integer;
begin
  if aFailedResources = nil then
    Exit;

  for i := 0 to aFailedResources.Count - 1 do
  begin
    lResourceName := NormalizeResourceToken(aFailedResources[i]);
    if lResourceName = '' then
      Continue;

    lHasModule := TryFindModuleByResourceName(aModules, lResourceName, lModule);
    if lHasModule then
      EmitLine(aOutput, Format('[dfm-check] FAIL target: resource=%s unit=%s pas=%s dfm=%s',
        [lResourceName, lModule.fUnitName, lModule.fPasPath, lModule.fDfmPath]))
    else
      EmitLine(aOutput, '[dfm-check] FAIL target: resource=' + lResourceName);

    lFailReason := '';
    if aFailReasons <> nil then
      lFailReason := Trim(aFailReasons.Values[lResourceName]);
    if lFailReason = '' then
      Continue;

    if TryExtractFailMember(lFailReason, lMemberPath) then
      EmitLine(aOutput, '[dfm-check] FAIL clue: member=' + lMemberPath);
    if TryExtractFailMethodName(lFailReason, lMethodName) then
    begin
      EmitLine(aOutput, '[dfm-check] FAIL clue: handler=' + lMethodName + ' (check signature/visibility)');
      if lHasModule then
      begin
        lDeclarationLine := 0;
        lDeclaration := '';
        if TryFindHandlerDeclarationInPas(lModule.fPasPath, lMethodName, lDeclarationLine, lDeclaration) then
        begin
          EmitLine(aOutput, Format('[dfm-check] FAIL clue: handler declaration line=%d: %s',
            [lDeclarationLine, lDeclaration]));
          if ShouldEmitSourceContext(aDiagnosticsDefaults.fSourceContextMode, True) and
            TryReadSourceContext(lModule.fPasPath, lDeclarationLine, aDiagnosticsDefaults.fSourceContextLines, lContext,
            lContextError) then
          begin
            lContextLines := FormatSourceContextLines(lContext);
            for lContextLine in lContextLines do
              EmitLine(aOutput, '[dfm-check] FAIL clue: ' + lContextLine);
          end;
        end
        else
          EmitLine(aOutput, '[dfm-check] FAIL clue: handler declaration not found in ' + lModule.fPasPath);
      end;
    end;
    if TryExtractEventPropertyName(lMemberPath, lEventName) then
      EmitLine(aOutput, '[dfm-check] FAIL clue: verify handler signature matches event type for ' + lEventName + '.');
  end;
end;

procedure EmitValidatorLog(const aLogPath: string; const aVerbose: Boolean; const aOutput: TDfmCheckOutputProc;
  const aSuppressLineOutput: Boolean; const aEmitProgressLines: Boolean; const aFailedResources: TStrings;
  const aFailReasons: TStrings; const aWarnedResources: TStrings; const aWarnReasons: TStrings;
  const aResourceModules: TArray<TDfmCacheModule>; out aSummary: TDfmValidationSummary; out aFailLines: Integer;
  out aWarnLines: Integer);
var
  lDisplayLine: string;
  lFailReason: string;
  lFailedResourceName: string;
  lLine: string;
  lLines: TStringList;
  lParsedSummary: TDfmValidationSummary;
  lTrimmedLine: string;
begin
  aSummary := Default(TDfmValidationSummary);
  aFailLines := 0;
  aWarnLines := 0;
  if (aLogPath = '') or (not FileExists(aLogPath)) then
    Exit;

  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aLogPath, TEncoding.UTF8);
    for lLine in lLines do
    begin
      lTrimmedLine := Trim(lLine);
      if lTrimmedLine = '' then
        Continue;

      if not aSuppressLineOutput then
      begin
        if aVerbose then
        begin
          lDisplayLine := lTrimmedLine;
          if StartsText('FAIL ', lTrimmedLine) then
            lDisplayLine := BuildFailLineWithModuleContext(lTrimmedLine, aResourceModules);
          if StartsText('WARN ', lTrimmedLine) then
            lDisplayLine := BuildWarnLineWithModuleContext(lTrimmedLine, aResourceModules);
          EmitLine(aOutput, lDisplayLine);
        end
        else if StartsText('FAIL ', lTrimmedLine) then
        begin
          EmitLine(aOutput, BuildFailLineWithModuleContext(lTrimmedLine, aResourceModules));
        end else if StartsText('WARN ', lTrimmedLine) then
        begin
          EmitLine(aOutput, lTrimmedLine);
        end else if aEmitProgressLines and StartsText('CHECK ', lTrimmedLine) then
        begin
          EmitLine(aOutput, lTrimmedLine);
        end;
      end;

      if StartsText('FAIL ', lTrimmedLine) then
      begin
        Inc(aFailLines);
        if aFailedResources <> nil then
        begin
          lFailedResourceName := ExtractFailedResourceName(lTrimmedLine);
          if lFailedResourceName <> '' then
            aFailedResources.Add(lFailedResourceName);
          if (aFailReasons <> nil) and (lFailedResourceName <> '') then
          begin
            lFailReason := ExtractFailReasonText(lTrimmedLine);
            if lFailReason <> '' then
              aFailReasons.Values[lFailedResourceName] := lFailReason;
          end;
        end;
      end;

      if StartsText('WARN ', lTrimmedLine) then
      begin
        Inc(aWarnLines);
        if aWarnedResources <> nil then
        begin
          lFailedResourceName := ExtractWarnedResourceName(lTrimmedLine);
          if lFailedResourceName <> '' then
            aWarnedResources.Add(lFailedResourceName);
          if (aWarnReasons <> nil) and (lFailedResourceName <> '') then
          begin
            lFailReason := ExtractFailReasonText(lTrimmedLine);
            if lFailReason <> '' then
              aWarnReasons.Values[lFailedResourceName] := lFailReason;
          end;
        end;
      end;

      if TryParseValidatorSummaryLine(lTrimmedLine, lParsedSummary) then
        aSummary := lParsedSummary;
    end;
  finally
    lLines.Free;
  end;
end;

function IsBuildErrorLine(const aLine: string): Boolean;
var
  lLower: string;
begin
  lLower := LowerCase(aLine);
  Result := (Pos(': error ', lLower) > 0) or
    (Pos(' error e', lLower) > 0) or
    (Pos(' error f', lLower) > 0) or
    (Pos('fatal error', lLower) > 0);
end;

procedure EmitBuildFailureDiagnostics(const aBuildLines: TStrings; const aOutput: TDfmCheckOutputProc);
const
  cMaxErrorLines = 20;
var
  lErrorLines: TStringList;
  lLine: string;
  lShownCount: Integer;
begin
  if aBuildLines = nil then
    Exit;

  lErrorLines := TStringList.Create;
  try
    lErrorLines.CaseSensitive := False;
    lErrorLines.Sorted := False;
    lErrorLines.Duplicates := TDuplicates.dupIgnore;
    for lLine in aBuildLines do
    begin
      if not IsBuildErrorLine(lLine) then
        Continue;
      lErrorLines.Add(Trim(lLine));
    end;

    if lErrorLines.Count = 0 then
      Exit;

    EmitLine(aOutput, '[dfm-check] Build diagnostics (errors):');
    lShownCount := 0;
    for lLine in lErrorLines do
    begin
      EmitLine(aOutput, lLine);
      Inc(lShownCount);
      if lShownCount >= cMaxErrorLines then
      begin
        if lErrorLines.Count > cMaxErrorLines then
          EmitLine(aOutput, Format('[dfm-check] ... %d more error line(s) omitted.', [lErrorLines.Count - cMaxErrorLines]));
        Break;
      end;
    end;
  finally
    lErrorLines.Free;
  end;
end;

function FormatExitCodeForDisplay(const aExitCode: Cardinal): string;
begin
  Result := IntToStr(Int64(aExitCode));
  if aExitCode > Cardinal(High(Integer)) then
    Result := Result + ' (0x' + IntToHex(Int64(aExitCode), 8) + ')';
end;

function NormalizeNativeExitCode(const aExitCode: Cardinal): Integer;
begin
  if aExitCode <= Cardinal(High(Integer)) then
    Exit(Integer(aExitCode));
  Result := 0;
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

procedure CleanupProjectRootArtifacts(const aPaths: TDfmCheckPaths; var aErrors: string);
var
  lDirectBasePath: string;
begin
  lDirectBasePath := TPath.Combine(aPaths.fProjectDir, aPaths.fProjectName + '_DfmCheck');
  CleanupFile(lDirectBasePath + '.dpr', aErrors);
  CleanupFile(lDirectBasePath + '.dproj', aErrors);
  CleanupFile(lDirectBasePath + '.dproj.local', aErrors);
  CleanupFile(lDirectBasePath + '.identcache', aErrors);
  CleanupFile(lDirectBasePath + '.cfg', aErrors);
  CleanupFile(lDirectBasePath + '.res', aErrors);
  CleanupFile(lDirectBasePath + '_Register.pas', aErrors);
end;

procedure CleanupGeneratedArtifacts(const aPaths: TDfmCheckPaths; const aCopiedDfmStreamAll: Boolean;
  const aCopiedRuntimeGuard: Boolean; const aValidatorExePath: string; const aOutput: TDfmCheckOutputProc;
  const aVerbose: Boolean);
var
  lBasePath: string;
  lBuildCmdPath: string;
  lBuildLogPath: string;
  lCmdsPath: string;
  lDirectBasePath: string;
  lErrors: string;
  lGeneratedDirName: string;
  lProjectDirNormalized: string;
  lGeneratedDirNormalized: string;
begin
  if aPaths.fRunDir <> '' then
  begin
    lErrors := '';
    CleanupProjectRootArtifacts(aPaths, lErrors);
    CleanupDirectory(aPaths.fRunDir, lErrors);
    if lErrors <> '' then
      EmitLine(aOutput, '[dfm-check] Cleanup warning: ' + lErrors)
    else if aVerbose then
      EmitLine(aOutput, '[dfm-check] Cleanup complete.');
    Exit;
  end;

  lErrors := '';
  lBasePath := TPath.ChangeExtension(aPaths.fGeneratedDpr, '');
  lDirectBasePath := TPath.Combine(aPaths.fProjectDir, aPaths.fProjectName + '_DfmCheck');

  CleanupFile(aPaths.fGeneratedDpr, lErrors);
  CleanupFile(aPaths.fGeneratedDproj, lErrors);
  CleanupFile(aPaths.fGeneratedDproj + '.local', lErrors);
  CleanupFile(TPath.ChangeExtension(aPaths.fGeneratedDproj, '.identcache'), lErrors);
  CleanupFile(TPath.ChangeExtension(aPaths.fGeneratedDpr, '.cfg'), lErrors);
  CleanupFile(TPath.ChangeExtension(aPaths.fGeneratedDpr, '.res'), lErrors);
  if aPaths.fGeneratedRegisterUnit <> '' then
    CleanupFile(aPaths.fGeneratedRegisterUnit, lErrors);
  CleanupProjectRootArtifacts(aPaths, lErrors);
  CleanupFile(aValidatorExePath, lErrors);
  lBuildCmdPath := TPath.Combine(aPaths.fGeneratedDir, '_DfmCheckBuild.cmd');
  lBuildLogPath := TPath.Combine(aPaths.fGeneratedDir, '_DfmCheckBuild.log');
  CleanupFile(lBuildCmdPath, lErrors);
  CleanupFile(lBuildLogPath, lErrors);
  CleanupFile(TPath.Combine(aPaths.fGeneratedDir, '_DfmCheckValidator.log'), lErrors);

  if aCopiedDfmStreamAll then
    CleanupFile(TPath.Combine(aPaths.fGeneratedDir, 'DfmStreamAll.pas'), lErrors);
  if aCopiedRuntimeGuard then
    CleanupFile(TPath.Combine(aPaths.fGeneratedDir, 'DfmCheckRuntimeGuard.pas'), lErrors);

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
  if aPaths.fForcedExeOutputDir <> '' then
    CleanupDirectory(aPaths.fForcedExeOutputDir, lErrors);
  if aPaths.fForcedDcuOutputDir <> '' then
    CleanupDirectory(aPaths.fForcedDcuOutputDir, lErrors);

  if lErrors <> '' then
    EmitLine(aOutput, '[dfm-check] Cleanup warning: ' + lErrors)
  else if aVerbose then
    EmitLine(aOutput, '[dfm-check] Cleanup complete.');
end;

function BuildExpectedDfmCheckPaths(const aDprojPath: string): TDfmCheckPaths;
begin
  Result := Default(TDfmCheckPaths);
  Result.fProjectDproj := TPath.GetFullPath(aDprojPath);
  Result.fProjectDir := ExcludeTrailingPathDelimiter(ExtractFilePath(Result.fProjectDproj));
  Result.fProjectName := TPath.GetFileNameWithoutExtension(Result.fProjectDproj);
  Result.fDakRootDir := TPath.Combine(Result.fProjectDir, '.dak\' + Result.fProjectName + '\dfm-check');
  Result.fRunsDir := TPath.Combine(Result.fDakRootDir, 'runs');
  Result.fGeneratedDir := TPath.Combine(Result.fDakRootDir, 'generated');
  Result.fGeneratedDproj := TPath.Combine(Result.fGeneratedDir, Result.fProjectName + '_DfmCheck.dproj');
  Result.fGeneratedDpr := TPath.Combine(Result.fGeneratedDir, Result.fProjectName + '_DfmCheck.dpr');
  Result.fGeneratedRegisterUnit := TPath.Combine(Result.fGeneratedDir, Result.fProjectName + '_DfmCheck_Register.pas');
end;

procedure AssignOwnedRunPaths(var aPaths: TDfmCheckPaths; const aRunSuffix: string);
begin
  aPaths.fRunDir := TPath.Combine(aPaths.fRunsDir, aRunSuffix);
  aPaths.fGeneratedDir := TPath.Combine(aPaths.fRunDir, 'generated');
  aPaths.fGeneratedDproj := TPath.Combine(aPaths.fGeneratedDir, aPaths.fProjectName + '_DfmCheck.dproj');
  aPaths.fGeneratedDpr := TPath.Combine(aPaths.fGeneratedDir, aPaths.fProjectName + '_DfmCheck.dpr');
  aPaths.fGeneratedRegisterUnit := TPath.Combine(aPaths.fGeneratedDir, aPaths.fProjectName + '_DfmCheck_Register.pas');
end;

procedure CleanupOwnedRunDirectories(const aRunsDir: string; const aRunDirToKeep: string; const aOutput: TDfmCheckOutputProc;
  const aVerbose: Boolean);
var
  lDirPath: string;
  lError: string;
  lRunDirToKeepNormalized: string;
begin
  if not DirectoryExists(aRunsDir) then
    Exit;

  lRunDirToKeepNormalized := ExcludeTrailingPathDelimiter(aRunDirToKeep);
  for lDirPath in TDirectory.GetDirectories(aRunsDir, '*', TSearchOption.soTopDirectoryOnly) do
  begin
    if SameText(ExcludeTrailingPathDelimiter(lDirPath), lRunDirToKeepNormalized) then
      Continue;

    lError := '';
    CleanupDirectory(lDirPath, lError);
    if (lError <> '') and aVerbose then
      EmitLine(aOutput, '[dfm-check] Stale-run cleanup warning: ' + lError);
  end;
end;

function TryResolveAbsolutePath(const aInputPath: string; out aOutputPath: string; out aError: string): Boolean;
begin
  Result := Dak.Utils.TryResolveAbsolutePath(aInputPath, aOutputPath, aError);
end;

function TryResolveDfmCheckProjectPath(const aInputPath: string; out aDprojPath: string; out aError: string): Boolean;
begin
  Result := Dak.Utils.TryResolveDprojPath(aInputPath, aDprojPath, aError);
end;

function TryResolveInjectDir(out aInjectDir: string; out aError: string): Boolean;
var
  lInjectOverride: string;
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

  Result := TryResolveBundledInjectDir(ParamStr(0), aInjectDir, aError);
end;

function TryResolveBundledInjectDir(const aExePath: string; out aInjectDir: string; out aError: string): Boolean;
var
  lCandidate: string;
  lCandidates: TList<string>;
  lCurrentDir: string;
  lExeDir: string;
  lNextDir: string;
  lVisitedDirs: TList<string>;
  procedure AddCandidate(const aBaseDir: string; const aRelativePath: string);
  var
    lPath: string;
  begin
    if Trim(aBaseDir) = '' then
      Exit;
    lPath := TPath.Combine(aBaseDir, aRelativePath);
    if lCandidates.IndexOf(lPath) < 0 then
      lCandidates.Add(lPath);
  end;
  function NormalizeWalkDir(const aDir: string): string;
  var
    lDriveRoot: string;
    lFullPath: string;
  begin
    lFullPath := TPath.GetFullPath(aDir);
    lDriveRoot := IncludeTrailingPathDelimiter(ExtractFileDrive(lFullPath));
    if SameText(IncludeTrailingPathDelimiter(lFullPath), lDriveRoot) then
      Result := lDriveRoot
    else
      Result := ExcludeTrailingPathDelimiter(lFullPath);
  end;
begin
  aInjectDir := '';
  aError := '';
  lExeDir := ExcludeTrailingPathDelimiter(ExtractFilePath(aExePath));
  lCandidates := TList<string>.Create;
  lVisitedDirs := TList<string>.Create;
  try
    lCurrentDir := NormalizeWalkDir(lExeDir);
    while Trim(lCurrentDir) <> '' do
    begin
      if lVisitedDirs.IndexOf(lCurrentDir) >= 0 then
        Break;
      lVisitedDirs.Add(lCurrentDir);
      AddCandidate(lCurrentDir, 'tools\inject');
      AddCandidate(lCurrentDir, 'docs\delphi-dfm-checker\tools\inject');
      lNextDir := NormalizeWalkDir(TPath.Combine(lCurrentDir, '..'));
      if SameText(lNextDir, lCurrentDir) then
        Break;
      lCurrentDir := lNextDir;
    end;

    for lCandidate in lCandidates do
    begin
      if DirectoryExists(lCandidate) then
      begin
        aInjectDir := lCandidate;
        Exit(True);
      end;
    end;
  finally
    lVisitedDirs.Free;
    lCandidates.Free;
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
  const aSourceMainSource: string; const aGeneratedMainSource: string; const aAdditionalUnitSearchPath: string;
  out aError: string): Boolean;
const
  cLineBreak = #13#10;
  cDfmCheckSymbol = 'DFMCheck';
  cMadExceptSymbol = 'madExcept';
  cNoLocalizationSymbol = 'NO_LOCALIZATION';
  function EnsureDefineSymbol(const aDefines: string; const aSymbol: string): string;
  begin
    if TRegEx.IsMatch(aDefines, '(^|;)\s*' + TRegEx.Escape(aSymbol) + '\s*(;|$)', [roIgnoreCase]) then
      Exit(aDefines);
    if Trim(aDefines) = '' then
      Exit(aSymbol);
    if EndsText(';', TrimRight(aDefines)) then
      Exit(aDefines + aSymbol);
    Result := aDefines + ';' + aSymbol;
  end;
  function RemoveDefineSymbol(const aDefines: string; const aSymbol: string): string;
  var
    i: Integer;
    lDefineList: TStringList;
    lToken: string;
  begin
    lDefineList := TStringList.Create;
    try
      lDefineList.StrictDelimiter := True;
      lDefineList.Delimiter := ';';
      lDefineList.DelimitedText := aDefines;
      Result := '';
      for i := 0 to lDefineList.Count - 1 do
      begin
        lToken := Trim(lDefineList[i]);
        if lToken = '' then
          Continue;
        if SameText(lToken, aSymbol) then
          Continue;
        if Result <> '' then
          Result := Result + ';';
        Result := Result + lToken;
      end;
    finally
      lDefineList.Free;
    end;
  end;
  function XmlEscape(const aValue: string): string;
  begin
    Result := aValue;
    Result := StringReplace(Result, '&', '&amp;', [rfReplaceAll]);
    Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
    Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
    Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
    Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
  end;
  function EscapeRegexReplacement(const aValue: string): string;
  begin
    Result := StringReplace(aValue, '$', '$$', [rfReplaceAll]);
  end;
  function NormalizeRelativePropertyPath(const aProjectText: string; const aPropertyName: string;
    const aBaseDir: string): string;
  var
    lMatch: TMatch;
    lMatches: TMatchCollection;
    lMatchStart: Integer;
    lPropertyPattern: string;
    lPropertyValue: string;
    lReplacement: string;
    lResolvedPath: string;
    lIndex: Integer;
  begin
    Result := aProjectText;
    lPropertyPattern := '<' + aPropertyName + '>\s*([^<]+?)\s*</' + aPropertyName + '>';
    lMatches := TRegEx.Matches(Result, lPropertyPattern, [roIgnoreCase, roSingleLine]);
    for lIndex := lMatches.Count - 1 downto 0 do
    begin
      lMatch := lMatches.Item[lIndex];
      if lMatch.Groups.Count < 2 then
        Continue;
      lPropertyValue := Trim(lMatch.Groups[1].Value);
      if (lPropertyValue = '') or StartsText('$(', lPropertyValue) or TPath.IsPathRooted(lPropertyValue) then
        Continue;

      lResolvedPath := TPath.GetFullPath(TPath.Combine(aBaseDir, lPropertyValue));
      if not FileExists(lResolvedPath) then
        Continue;

      lMatchStart := lMatch.Index;
      lReplacement := '<' + aPropertyName + '>' + XmlEscape(lResolvedPath) + '</' + aPropertyName + '>';
      Result := Copy(Result, 1, lMatchStart - 1) + lReplacement +
        Copy(Result, lMatchStart + lMatch.Length, MaxInt);
    end;
  end;
  function ClearBuildEventBlock(const aProjectText: string; const aTagName: string): string;
  begin
    Result := TRegEx.Replace(aProjectText, '<' + aTagName + '>\s*.*?\s*</' + aTagName + '>',
      '<' + aTagName + '></' + aTagName + '>', [roIgnoreCase, roSingleLine]);
  end;
var
  lEscapedSearchPath: string;
  lEscapedSearchPathReplacement: string;
  lDefineMatch: TMatch;
  lExistingDefines: string;
  lInsertedSearchPath: string;
  lInsertText: string;
  lPropertyGroupMatch: TMatch;
  lInsertPos: Integer;
  lUpdatedDefines: string;
  lUpdatedDefinesReplacement: string;
  lSourceText: string;
  lSourceDprojDir: string;
  lOutputText: string;
  lRegex: string;
begin
  aError := '';
  lSourceText := TFile.ReadAllText(aSourceDprojPath);
  lOutputText := lSourceText;
  lSourceDprojDir := ExcludeTrailingPathDelimiter(ExtractFileDir(aSourceDprojPath));
  lRegex := '<MainSource>\s*' + TRegEx.Escape(aSourceMainSource) + '\s*</MainSource>';

  lOutputText := TRegEx.Replace(lOutputText, lRegex, '<MainSource>' + aGeneratedMainSource + '</MainSource>',
    [roIgnoreCase, roSingleLine]);
  if lOutputText = lSourceText then
    lOutputText := TRegEx.Replace(lOutputText, '<MainSource>\s*([^<]+?)\s*</MainSource>',
      '<MainSource>' + aGeneratedMainSource + '</MainSource>', [roIgnoreCase, roSingleLine]);
  lOutputText := TRegEx.Replace(lOutputText, '<Source\s+Name\s*=\s*"MainSource"\s*>\s*([^<]+?)\s*</Source>',
    '<Source Name="MainSource">' + aGeneratedMainSource + '</Source>', [roIgnoreCase, roSingleLine]);

  if lOutputText = lSourceText then
  begin
    aError := 'Could not patch generated .dproj MainSource.';
    Exit(False);
  end;

  if Trim(aAdditionalUnitSearchPath) <> '' then
  begin
    lEscapedSearchPath := XmlEscape(aAdditionalUnitSearchPath);
    lEscapedSearchPathReplacement := EscapeRegexReplacement(lEscapedSearchPath);
    if TRegEx.IsMatch(lOutputText, '<DCC_UnitSearchPath>\s*([^<]*)\s*</DCC_UnitSearchPath>', [roIgnoreCase]) then
      lOutputText := TRegEx.Replace(lOutputText, '<DCC_UnitSearchPath>\s*([^<]*)\s*</DCC_UnitSearchPath>',
        '<DCC_UnitSearchPath>' + lEscapedSearchPathReplacement + ';$1</DCC_UnitSearchPath>', [roIgnoreCase])
    else
    begin
      lInsertedSearchPath := lEscapedSearchPath + ';$(DCC_UnitSearchPath)';
      lPropertyGroupMatch := TRegEx.Match(lOutputText, '<PropertyGroup\b[^>]*>', [roIgnoreCase]);
      if lPropertyGroupMatch.Success then
      begin
        lInsertPos := lPropertyGroupMatch.Index + lPropertyGroupMatch.Length;
        lInsertText := cLineBreak + '    <DCC_UnitSearchPath>' + lInsertedSearchPath + '</DCC_UnitSearchPath>';
        lOutputText := Copy(lOutputText, 1, lInsertPos) + lInsertText + Copy(lOutputText, lInsertPos + 1, MaxInt);
      end;
    end;
  end;

  lDefineMatch := TRegEx.Match(lOutputText, '<DCC_Define>\s*([^<]*)\s*</DCC_Define>', [roIgnoreCase]);
  if lDefineMatch.Success and (lDefineMatch.Groups.Count > 1) then
  begin
    lExistingDefines := lDefineMatch.Groups[1].Value;
    lUpdatedDefines := RemoveDefineSymbol(lExistingDefines, cMadExceptSymbol);
    lUpdatedDefines := EnsureDefineSymbol(lUpdatedDefines, cDfmCheckSymbol);
    lUpdatedDefines := EnsureDefineSymbol(lUpdatedDefines, cNoLocalizationSymbol);
    if lUpdatedDefines <> lExistingDefines then
    begin
      lUpdatedDefinesReplacement := EscapeRegexReplacement(lUpdatedDefines);
      lOutputText := TRegEx.Replace(lOutputText, '<DCC_Define>\s*([^<]*)\s*</DCC_Define>',
        '<DCC_Define>' + lUpdatedDefinesReplacement + '</DCC_Define>', [roIgnoreCase]);
    end;
  end else
  begin
    lPropertyGroupMatch := TRegEx.Match(lOutputText, '<PropertyGroup\b[^>]*>', [roIgnoreCase]);
    if lPropertyGroupMatch.Success then
    begin
      lInsertPos := lPropertyGroupMatch.Index + lPropertyGroupMatch.Length;
      lInsertText := cLineBreak + '    <DCC_Define>' + cDfmCheckSymbol + ';' + cNoLocalizationSymbol +
        '</DCC_Define>';
      lOutputText := Copy(lOutputText, 1, lInsertPos) + lInsertText + Copy(lOutputText, lInsertPos + 1, MaxInt);
    end;
  end;

  lOutputText := NormalizeRelativePropertyPath(lOutputText, 'Icon_MainIcon', lSourceDprojDir);
  lOutputText := ClearBuildEventBlock(lOutputText, 'PreBuildEvent');
  lOutputText := ClearBuildEventBlock(lOutputText, 'PreLinkEvent');
  lOutputText := ClearBuildEventBlock(lOutputText, 'PostBuildEvent');

  TFile.WriteAllText(aDestDprojPath, lOutputText, TEncoding.UTF8);
  Result := True;
end;

function BuildDelimitedPath(const aPaths: TStrings): string;
var
  i: Integer;
begin
  Result := '';
  if aPaths = nil then
    Exit;
  for i := 0 to aPaths.Count - 1 do
  begin
    if Result <> '' then
      Result := Result + ';';
    Result := Result + aPaths[i];
  end;
end;

procedure AppendDelimitedPaths(const aPathList: string; const aPaths: TStrings);
var
  lItem: string;
  lPath: string;
  lPaths: TArray<string>;
begin
  if (aPaths = nil) or (Trim(aPathList) = '') then
    Exit;

  lPaths := aPathList.Split([';']);
  for lPath in lPaths do
  begin
    lItem := Trim(lPath);
    if lItem = '' then
      Continue;
    if aPaths.IndexOf(lItem) < 0 then
      aPaths.Add(lItem);
  end;
end;

function TryBuildEffectiveProjectSearchPath(const aOptions: TAppOptions; out aSearchPath: string): Boolean;
var
  lContext: TProjectAnalysisContext;
  lPaths: TStringList;
  lUnusedError: string;
begin
  aSearchPath := '';
  if not TryBuildProjectAnalysisContext(aOptions, lContext, lUnusedError) then
    Exit(False);
  if Trim(lContext.fParserSearchPath) = '' then
    Exit(True);

  lPaths := TStringList.Create;
  try
    lPaths.CaseSensitive := False;
    lPaths.Sorted := False;
    lPaths.Duplicates := TDuplicates.dupIgnore;
    AppendDelimitedPaths(lContext.fParserSearchPath, lPaths);
    aSearchPath := BuildDelimitedPath(lPaths);
  finally
    lPaths.Free;
  end;
  Result := True;
end;

function BuildDfmCheckSearchPath(const aOptions: TAppOptions; const aReferenceDirs: TStrings;
  const aDiscoveredUnitDirs: TStrings): string;
var
  lEffectiveSearchPath: string;
  lPaths: TStringList;
begin
  lPaths := TStringList.Create;
  try
    lPaths.CaseSensitive := False;
    lPaths.Sorted := False;
    lPaths.Duplicates := TDuplicates.dupIgnore;
    AppendDelimitedPaths(BuildDelimitedPath(aReferenceDirs), lPaths);
    AppendDelimitedPaths(BuildDelimitedPath(aDiscoveredUnitDirs), lPaths);
    if TryBuildEffectiveProjectSearchPath(aOptions, lEffectiveSearchPath) then
      AppendDelimitedPaths(lEffectiveSearchPath, lPaths);
    Result := BuildDelimitedPath(lPaths);
  finally
    lPaths.Free;
  end;
end;

function TryCollectFormModulesFromDproj(const aDprojPath: string; const aUnitNames: TStrings;
  const aFormClassNames: TStrings; const aUnitSearchDirs: TStrings; out aError: string): Boolean;
var
  lDprDir: string;
  lDprPath: string;
  lDprText: string;
  lDfmPath: string;
  lDprojDir: string;
  lDprojText: string;
  lFormClassName: string;
  lIncludePath: string;
  lMatch: TMatch;
  lMatches: TMatchCollection;
  lModuleDir: string;
  lModuleFilePath: string;
  lUnitName: string;
begin
  Result := False;
  aError := '';
  if not FileExists(aDprojPath) then
  begin
    aError := 'Dproj file not found for module discovery: ' + aDprojPath;
    Exit(False);
  end;
  lDprojDir := ExcludeTrailingPathDelimiter(ExtractFileDir(aDprojPath));

  lDprPath := TPath.ChangeExtension(aDprojPath, '.dpr');
  if not FileExists(lDprPath) then
  begin
    lDprojText := TFile.ReadAllText(aDprojPath);
    lMatch := TRegEx.Match(lDprojText, '<MainSource>\s*([^<]+?)\s*</MainSource>', [roIgnoreCase, roSingleLine]);
    if lMatch.Success and (lMatch.Groups.Count > 1) then
    begin
      lIncludePath := Trim(lMatch.Groups[1].Value);
      if lIncludePath <> '' then
        lDprPath := TPath.GetFullPath(TPath.Combine(lDprojDir, lIncludePath));
    end;
  end;

  if FileExists(lDprPath) then
  begin
    lDprDir := ExcludeTrailingPathDelimiter(ExtractFileDir(lDprPath));
    lDprText := TFile.ReadAllText(lDprPath);
    lMatches := TRegEx.Matches(lDprText,
      '([A-Za-z_&][A-Za-z0-9_&]*(?:\.[A-Za-z_&][A-Za-z0-9_&]*)*)\s+in\s+''([^'']+\.pas)''', [roIgnoreCase]);
    for lMatch in lMatches do
    begin
      if (not lMatch.Success) or (lMatch.Groups.Count < 3) then
        Continue;
      lUnitName := Trim(lMatch.Groups[1].Value);
      lIncludePath := Trim(lMatch.Groups[2].Value);
      if (lUnitName = '') or (lIncludePath = '') then
        Continue;

      lModuleFilePath := TPath.GetFullPath(TPath.Combine(lDprDir, lIncludePath));
      if not FileExists(lModuleFilePath) then
        Continue;
      lModuleDir := ExcludeTrailingPathDelimiter(ExtractFileDir(lModuleFilePath));
      if lModuleDir <> '' then
        aUnitSearchDirs.Add(lModuleDir);
      lDfmPath := TPath.ChangeExtension(lModuleFilePath, '.dfm');
      if not FileExists(lDfmPath) then
        Continue;
      if aUnitNames.IndexOf(lUnitName) >= 0 then
        Continue;

      try
        lFormClassName := Trim(ReadFormClassNameFromFile(lDfmPath));
      except
        on E: Exception do
        begin
          aError := 'Failed to read root form class from DFM (' + lDfmPath + '): ' + E.Message;
          Exit(False);
        end;
      end;

      aUnitNames.Add(lUnitName);
      aFormClassNames.Add(lFormClassName);
    end;
  end;

  if aUnitNames.Count > 0 then
    Exit(True);

  lDprojText := TFile.ReadAllText(aDprojPath);
  lMatches := TRegEx.Matches(lDprojText, '<DCCReference\b[^>]*\bInclude\s*=\s*"([^"]+)"', [roIgnoreCase]);
  for lMatch in lMatches do
  begin
    if (not lMatch.Success) or (lMatch.Groups.Count < 2) then
      Continue;
    lIncludePath := Trim(lMatch.Groups[1].Value);
    if lIncludePath = '' then
      Continue;
    lIncludePath := lIncludePath.Replace('/', '\', [rfReplaceAll]);
    if not SameText(TPath.GetExtension(lIncludePath), '.pas') then
      Continue;

    lModuleFilePath := TPath.GetFullPath(TPath.Combine(lDprojDir, lIncludePath));
    if not FileExists(lModuleFilePath) then
      Continue;
    lDfmPath := TPath.ChangeExtension(lModuleFilePath, '.dfm');
    if not FileExists(lDfmPath) then
      Continue;

    lUnitName := TPath.GetFileNameWithoutExtension(lModuleFilePath);
    lModuleDir := ExcludeTrailingPathDelimiter(ExtractFileDir(lModuleFilePath));
    if lModuleDir <> '' then
      aUnitSearchDirs.Add(lModuleDir);
    if aUnitNames.IndexOf(lUnitName) >= 0 then
      Continue;

    try
      lFormClassName := Trim(ReadFormClassNameFromFile(lDfmPath));
    except
      on E: Exception do
      begin
        aError := 'Failed to read root form class from DFM (' + lDfmPath + '): ' + E.Message;
        Exit(False);
      end;
    end;

    aUnitNames.Add(lUnitName);
    aFormClassNames.Add(lFormClassName);
  end;

  Result := True;
end;

function TryCollectFormModules(const aSourceProjectPath: string; const aUnitNames: TStrings;
  const aFormClassNames: TStrings; const aUnitSearchDirs: TStrings; const aSourceDprojPath: string;
  out aError: string): Boolean;
begin
  if Trim(aSourceProjectPath) <> '' then
  begin
    // Project path is resolved by caller; module discovery for dfm-check uses dpr/dproj references directly.
  end;
  Result := TryCollectFormModulesFromDproj(aSourceDprojPath, aUnitNames, aFormClassNames, aUnitSearchDirs, aError);
end;

function TryCollectDprojReferenceUnitDirs(const aDprojPath: string; const aUnitDirs: TStrings;
  out aError: string): Boolean;
var
  lDprojDir: string;
  lDprojText: string;
  lIncludePath: string;
  lMatch: TMatch;
  lMatches: TMatchCollection;
  lModuleDir: string;
  lModuleFilePath: string;
  lOrderedDirs: TStringList;
  lIndex: Integer;
begin
  Result := False;
  aError := '';
  if aUnitDirs = nil then
  begin
    aError := 'Reference unit directory output list is not assigned.';
    Exit(False);
  end;
  if not FileExists(aDprojPath) then
  begin
    aError := 'Dproj file not found for unit reference discovery: ' + aDprojPath;
    Exit(False);
  end;

  lDprojDir := ExcludeTrailingPathDelimiter(ExtractFileDir(aDprojPath));
  lDprojText := TFile.ReadAllText(aDprojPath);
  lMatches := TRegEx.Matches(lDprojText, '<DCCReference\b[^>]*\bInclude\s*=\s*"([^"]+)"', [roIgnoreCase]);
  lOrderedDirs := TStringList.Create;
  try
    lOrderedDirs.CaseSensitive := False;
    lOrderedDirs.Sorted := False;
    for lMatch in lMatches do
    begin
      if (not lMatch.Success) or (lMatch.Groups.Count < 2) then
        Continue;
      lIncludePath := Trim(lMatch.Groups[1].Value);
      if lIncludePath = '' then
        Continue;
      lIncludePath := lIncludePath.Replace('/', '\', [rfReplaceAll]);
      if not SameText(TPath.GetExtension(lIncludePath), '.pas') then
        Continue;
      lModuleFilePath := TPath.GetFullPath(TPath.Combine(lDprojDir, lIncludePath));
      if not FileExists(lModuleFilePath) then
        Continue;
      lModuleDir := ExcludeTrailingPathDelimiter(ExtractFileDir(lModuleFilePath));
      if lModuleDir = '' then
        Continue;
      if lOrderedDirs.IndexOf(lModuleDir) < 0 then
        lOrderedDirs.Add(lModuleDir);
    end;

    // Reverse insertion so later project references have higher lookup priority.
    for lIndex := lOrderedDirs.Count - 1 downto 0 do
      if aUnitDirs.IndexOf(lOrderedDirs[lIndex]) < 0 then
        aUnitDirs.Add(lOrderedDirs[lIndex]);
  finally
    lOrderedDirs.Free;
  end;
  Result := True;
end;

function TryWriteRegisterUnit(const aRegisterUnitPath: string; const aUnitNames: TStrings;
  const aFormClassNames: TStrings; out aError: string): Boolean;
const
  cLineBreak = #13#10;
var
  lContent: string;
  lEncoding: TEncoding;
  i: Integer;
  lRegisterUnitName: string;
begin
  aError := '';
  lRegisterUnitName := TPath.GetFileNameWithoutExtension(aRegisterUnitPath);
  if lRegisterUnitName = '' then
  begin
    aError := 'Generated register unit name is empty: ' + aRegisterUnitPath;
    Exit(False);
  end;
  if (aUnitNames = nil) or (aFormClassNames = nil) or (aUnitNames.Count <> aFormClassNames.Count) then
  begin
    aError := 'Generated register unit inputs are invalid.';
    Exit(False);
  end;

  lContent := 'unit ' + lRegisterUnitName + ';' + cLineBreak + cLineBreak +
    'interface' + cLineBreak + cLineBreak +
    'implementation' + cLineBreak + cLineBreak +
    'uses' + cLineBreak +
    '  System.Classes';
  if aUnitNames.Count > 0 then
    lContent := lContent + ',' + cLineBreak
  else
    lContent := lContent + ';' + cLineBreak;
  for i := 0 to aUnitNames.Count - 1 do
  begin
    lContent := lContent + '  ' + aUnitNames[i];
    if i < aUnitNames.Count - 1 then
      lContent := lContent + ','
    else
      lContent := lContent + ';';
    lContent := lContent + cLineBreak;
  end;

  lContent := lContent + cLineBreak +
    'procedure RegisterDfmCheckClasses;' + cLineBreak +
    'begin' + cLineBreak;
  for i := 0 to aFormClassNames.Count - 1 do
  begin
    if Trim(aFormClassNames[i]) <> '' then
      lContent := lContent + '  {$IF Declared(' + aFormClassNames[i] + ')} RegisterClass(' + aFormClassNames[i] +
        '); {$IFEND}' + cLineBreak;
  end;
  lContent := lContent + 'end;' + cLineBreak + cLineBreak +
    'initialization' + cLineBreak +
    '  RegisterDfmCheckClasses;' + cLineBreak + cLineBreak +
    'end.' + cLineBreak;

  lEncoding := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(aRegisterUnitPath, lContent, lEncoding);
  finally
    lEncoding.Free;
  end;
  Result := True;
end;

function TryWriteGeneratedDpr(const aGeneratedDprPath: string; const aProgramName: string;
  const aRegisterUnitName: string; const aSourceDprText: string; out aError: string): Boolean;
const
  cLineBreak = #13#10;
var
  lContent: string;
  lEncoding: TEncoding;
  lMadExceptAvailable: Boolean;
  lMadExceptUses: string;
  function IsMadExceptInstalled: Boolean;
  var
    lBaseDir: string;
    lProgramFilesDir: string;
    lProgramFilesX86Dir: string;
  begin
    lProgramFilesX86Dir := Trim(GetEnvironmentVariable('ProgramFiles(x86)'));
    lProgramFilesDir := Trim(GetEnvironmentVariable('ProgramFiles'));

    for lBaseDir in [lProgramFilesX86Dir, lProgramFilesDir] do
    begin
      if lBaseDir = '' then
        Continue;
      if TDirectory.Exists(TPath.Combine(lBaseDir, 'madCollection\madExcept')) then
        Exit(True);
    end;
    Result := False;
  end;
begin
  aError := '';
  if Trim(aProgramName) = '' then
  begin
    aError := 'Generated DFM checker program name is empty.';
    Exit(False);
  end;
  if Trim(aRegisterUnitName) = '' then
  begin
    aError := 'Generated register unit name is empty.';
    Exit(False);
  end;

  lMadExceptUses := '';
  lMadExceptAvailable := IsMadExceptInstalled;
  if lMadExceptAvailable and ContainsWord(aSourceDprText, 'madExcept') then
    lMadExceptUses := lMadExceptUses + '  madExcept,' + cLineBreak;
  if lMadExceptAvailable and ContainsWord(aSourceDprText, 'madLinkDisAsm') then
    lMadExceptUses := lMadExceptUses + '  madLinkDisAsm,' + cLineBreak;
  if lMadExceptAvailable and ContainsWord(aSourceDprText, 'madListHardware') then
    lMadExceptUses := lMadExceptUses + '  madListHardware,' + cLineBreak;
  if lMadExceptAvailable and ContainsWord(aSourceDprText, 'madListProcesses') then
    lMadExceptUses := lMadExceptUses + '  madListProcesses,' + cLineBreak;
  if lMadExceptAvailable and ContainsWord(aSourceDprText, 'madListModules') then
    lMadExceptUses := lMadExceptUses + '  madListModules,' + cLineBreak;

  lContent :=
    'program ' + aProgramName + ';' + cLineBreak + cLineBreak +
    '{$R *.res}' + cLineBreak + cLineBreak +
    'uses' + cLineBreak +
    lMadExceptUses +
    '  Winapi.Windows,' + cLineBreak +
    '  System.SysUtils,' + cLineBreak +
    '  DfmStreamAll in ''DfmStreamAll.pas'',' + cLineBreak +
    '  ' + aRegisterUnitName + ' in ''' + aRegisterUnitName + '.pas'',' + cLineBreak +
    '  DfmCheckRuntimeGuard in ''DfmCheckRuntimeGuard.pas'';' + cLineBreak + cLineBreak +
    'procedure EmitFatalInit(const aText: string);' + cLineBreak +
    'var' + cLineBreak +
    '  lBytesWritten: Cardinal;' + cLineBreak +
    '  lLine: UTF8String;' + cLineBreak +
    '  lStdErr: THandle;' + cLineBreak +
    'begin' + cLineBreak +
    '  lLine := UTF8String(aText + sLineBreak);' + cLineBreak +
    '  lStdErr := GetStdHandle(STD_ERROR_HANDLE);' + cLineBreak +
    '  if (lStdErr <> 0) and (lStdErr <> INVALID_HANDLE_VALUE) then' + cLineBreak +
    '    WriteFile(lStdErr, Pointer(lLine)^, Length(lLine), lBytesWritten, nil)' + cLineBreak +
    '  else' + cLineBreak +
    '    OutputDebugString(PChar(aText));' + cLineBreak +
    'end;' + cLineBreak + cLineBreak +
    'begin' + cLineBreak +
    '  try' + cLineBreak +
    '    ExitCode := TDfmStreamAll.Run;' + cLineBreak +
    '  except' + cLineBreak +
    '    on E: Exception do' + cLineBreak +
    '    begin' + cLineBreak +
    '      EmitFatalInit(''FATAL INIT -> '' + E.ClassName + '': '' + E.Message);' + cLineBreak +
    '      if DebugHook <> 0 then' + cLineBreak +
    '        raise;' + cLineBreak +
    '      ExitCode := 255;' + cLineBreak +
    '    end;' + cLineBreak +
    '  end;' + cLineBreak +
    '  Halt(ExitCode);' + cLineBreak +
    'end.' + cLineBreak;

  lEncoding := TUTF8Encoding.Create(False);
  try
    TFile.WriteAllText(aGeneratedDprPath, lContent, lEncoding);
  finally
    lEncoding.Free;
  end;
  Result := True;
end;

function TryGenerateDfmCheckProject(const aOptions: TAppOptions; const aDprojPath: string; const aFilterCsv: string;
  var aPaths: TDfmCheckPaths; out aError: string): Boolean;
var
  lContextOptions: TAppOptions;
  lDprojReferenceDirs: TStringList;
  lFilterList: TStringList;
  lFormClassNames: TStringList;
  lGeneratedCfgPath: string;
  lGeneratedDprName: string;
  lGeneratedDprojName: string;
  lIndex: Integer;
  lMainSourceRaw: string;
  lSourceDprText: string;
  lResourceToken: string;
  lResourceName: string;
  lSourceCfgPath: string;
  lSourceProjectExt: string;
  lSourceProjectPath: string;
  lUnitNames: TStringList;
  lUnitSearchDirs: TStringList;
  lUnitSearchPath: string;
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

  lSourceDprText := TFile.ReadAllText(lSourceProjectPath, TEncoding.UTF8);

  lUnitNames := TStringList.Create;
  lFormClassNames := TStringList.Create;
  lFilterList := TStringList.Create;
  lDprojReferenceDirs := TStringList.Create;
  lUnitSearchDirs := TStringList.Create;
  try
    lUnitNames.CaseSensitive := False;
    lUnitNames.Sorted := False;
    lUnitNames.Duplicates := TDuplicates.dupIgnore;
    lFormClassNames.CaseSensitive := False;
    lFormClassNames.Sorted := False;
    lFormClassNames.Duplicates := TDuplicates.dupIgnore;
    lFilterList.CaseSensitive := False;
    lFilterList.Sorted := True;
    lFilterList.Duplicates := TDuplicates.dupIgnore;
    lDprojReferenceDirs.CaseSensitive := False;
    lDprojReferenceDirs.Sorted := False;
    lDprojReferenceDirs.Duplicates := TDuplicates.dupIgnore;
    lUnitSearchDirs.CaseSensitive := False;
    lUnitSearchDirs.Sorted := True;
    lUnitSearchDirs.Duplicates := TDuplicates.dupIgnore;

    if not TryCollectDprojReferenceUnitDirs(aDprojPath, lDprojReferenceDirs, aError) then
      Exit(False);

    if not TryCollectFormModules(lSourceProjectPath, lUnitNames, lFormClassNames, lUnitSearchDirs, aDprojPath, aError) then
      Exit(False);

    if Trim(aFilterCsv) <> '' then
    begin
      for lResourceName in aFilterCsv.Split([',', ';']) do
      begin
        lResourceToken := NormalizeResourceToken(lResourceName);
        if lResourceToken <> '' then
          lFilterList.Add(lResourceToken);
      end;

      for lIndex := lUnitNames.Count - 1 downto 0 do
      begin
        if (lFilterList.IndexOf(NormalizeResourceToken(lFormClassNames[lIndex])) >= 0) or
          (lFilterList.IndexOf(NormalizeResourceToken(lUnitNames[lIndex])) >= 0) then
          Continue;
        lUnitNames.Delete(lIndex);
        lFormClassNames.Delete(lIndex);
      end;
      if lUnitNames.Count = 0 then
      begin
        aError := 'No form units matched the selected --dfm filter after project module resolution.';
        Exit(False);
      end;
    end;

    lContextOptions := aOptions;
    lContextOptions.fDprojPath := aDprojPath;
    if Trim(lContextOptions.fConfig) = '' then
      lContextOptions.fConfig := 'Release';
    if Trim(lContextOptions.fPlatform) = '' then
      lContextOptions.fPlatform := 'Win32';
    lUnitSearchPath := BuildDfmCheckSearchPath(lContextOptions, lDprojReferenceDirs, lUnitSearchDirs);
    lGeneratedDprName := TPath.GetFileNameWithoutExtension(aDprojPath) + '_DfmCheck.dpr';
    lGeneratedDprojName := TPath.GetFileNameWithoutExtension(aDprojPath) + '_DfmCheck.dproj';
    TDirectory.CreateDirectory(aPaths.fGeneratedDir);
    aPaths.fGeneratedDpr := TPath.Combine(aPaths.fGeneratedDir, lGeneratedDprName);
    aPaths.fGeneratedDproj := TPath.Combine(aPaths.fGeneratedDir, lGeneratedDprojName);
    aPaths.fGeneratedRegisterUnit := TPath.Combine(aPaths.fGeneratedDir,
      TPath.GetFileNameWithoutExtension(aDprojPath) + '_DfmCheck_Register.pas');
    lGeneratedCfgPath := TPath.ChangeExtension(aPaths.fGeneratedDpr, '.cfg');

    if not TryWriteRegisterUnit(aPaths.fGeneratedRegisterUnit, lUnitNames, lFormClassNames, aError) then
      Exit(False);

    if not TryWriteGeneratedDpr(aPaths.fGeneratedDpr, TPath.GetFileNameWithoutExtension(aPaths.fGeneratedDpr),
      TPath.GetFileNameWithoutExtension(aPaths.fGeneratedRegisterUnit), lSourceDprText, aError) then
      Exit(False);

    lSourceCfgPath := TPath.ChangeExtension(lSourceProjectPath, '.cfg');
    if FileExists(lSourceCfgPath) then
      TFile.Copy(lSourceCfgPath, lGeneratedCfgPath, True);

    if not TryCopyDprojWithNewMainSource(aDprojPath, aPaths.fGeneratedDproj, lMainSourceRaw, lGeneratedDprName,
      lUnitSearchPath, aError) then
      Exit(False);
  finally
    lUnitSearchDirs.Free;
    lDprojReferenceDirs.Free;
    lFilterList.Free;
    lFormClassNames.Free;
    lUnitNames.Free;
  end;
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

    if DirectoryExists(aPaths.fRunsDir) then
    begin
      lDirectoryArray := TDirectory.GetDirectories(aPaths.fRunsDir, '*', TSearchOption.soTopDirectoryOnly);
      for lDirectoryPath in lDirectoryArray do
        lDirectoryList.Add(TPath.Combine(lDirectoryPath, 'generated'));
    end;

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
        aPaths.fGeneratedRegisterUnit := TPath.Combine(lDirectoryPath,
          TPath.GetFileNameWithoutExtension(lFoundDpr) + '_Register.pas');
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
      aPaths.fGeneratedRegisterUnit := TPath.Combine(aPaths.fProjectDir,
        TPath.GetFileNameWithoutExtension(lDirectDpr) + '_Register.pas');
      Exit(True);
    end;
  finally
    lDirectoryList.Free;
  end;

  aError := 'Could not locate generated _DfmCheck project under: ' + aPaths.fProjectDir;
  Result := False;
end;

function TryPatchDfmCheckDpr(const aInputText: string; out aOutputText: string; out aChanged: Boolean;
  out aError: string; const aRegisterUnitName: string; const aProgramName: string): Boolean;
const
  cLineBreak = #13#10;
var
  lClauseEnd: Integer;
  lClauseStart: Integer;
  lCharAfter: Char;
  lCharBefore: Char;
  lFoundUses: Boolean;
  lMadExceptPattern: string;
  lInjectedUnits: string;
  lLowerText: string;
  lNeedsDfmStreamAll: Boolean;
  lNeedsRegisterUnit: Boolean;
  lBomPrefix: string;
  lPos: Integer;
  lRegisterUnitName: string;
  lReplacedText: string;
  lWorkText: string;
  lChangedUses: Boolean;
  lChangedValidatorStart: Boolean;
  lChangedProgramName: Boolean;
  lChangedMadExcept: Boolean;
  lUsesBody: string;
  lUsesText: string;
  lBeginPos: Integer;
  lMainEndPos: Integer;
  lSuffix: string;
begin
  Result := False;
  aError := '';
  aChanged := False;
  lWorkText := aInputText;
  lBomPrefix := '';
  lChangedUses := False;
  lChangedValidatorStart := False;
  lChangedProgramName := False;
  lChangedMadExcept := False;
  lClauseStart := 0;
  lClauseEnd := 0;
  lRegisterUnitName := Trim(aRegisterUnitName);
  lNeedsDfmStreamAll := not ContainsWord(lWorkText, 'DfmStreamAll');
  lNeedsRegisterUnit := (lRegisterUnitName <> '') and (not ContainsWord(lWorkText, lRegisterUnitName));

  if (lWorkText <> '') and ((lWorkText[1] = #$FEFF) or (Ord(lWorkText[1]) > 127)) then
  begin
    lBomPrefix := lWorkText[1];
    Delete(lWorkText, 1, 1);
  end;

  if Trim(aProgramName) <> '' then
  begin
    if not TRegEx.IsMatch(lWorkText, '(^[ \t]*program[ \t]+)([A-Za-z_][A-Za-z0-9_]*)([ \t]*;)',
      [roIgnoreCase, roMultiLine]) then
    begin
      aError := 'Could not patch DPR: program declaration not found.';
      Exit(False);
    end;

    lReplacedText := TRegEx.Replace(lWorkText, '(^[ \t]*program[ \t]+)([A-Za-z_][A-Za-z0-9_]*)([ \t]*;)',
      '$1' + aProgramName + '$3', [roIgnoreCase, roMultiLine]);
    if lReplacedText <> lWorkText then
    begin
      lWorkText := lReplacedText;
      lChangedProgramName := True;
    end;
  end;

  lMadExceptPattern := '\{\$IFDEF\s+madExcept\}.*?\{\$ENDIF(?:\s+madExcept)?\}';
  lReplacedText := TRegEx.Replace(lWorkText, lMadExceptPattern, '', [roIgnoreCase, roSingleLine]);
  if lReplacedText <> lWorkText then
  begin
    lWorkText := lReplacedText;
    lChangedMadExcept := True;
  end;

  if lNeedsDfmStreamAll or lNeedsRegisterUnit then
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

    lInjectedUnits := '';
    if lNeedsDfmStreamAll then
      lInjectedUnits := lInjectedUnits + '  DfmStreamAll,' + cLineBreak;
    if lNeedsRegisterUnit then
      lInjectedUnits := lInjectedUnits + '  ' + lRegisterUnitName + ',' + cLineBreak;

    lUsesText := 'uses' + cLineBreak + lInjectedUnits + '  ' + lUsesBody + ';';
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

    if not TryFindMainProgramBegin(lWorkText, lMainEndPos, lBeginPos) then
    begin
      aError := 'Could not patch DPR: main "begin" not found.';
      Exit(False);
    end;

    lSuffix := Copy(lWorkText, lBeginPos + Length('begin'), MaxInt);
    if (lSuffix <> '') and (not CharInSet(lSuffix[1], [#10, #13, ' '])) then
      lSuffix := cLineBreak + lSuffix;
    lWorkText := Copy(lWorkText, 1, lBeginPos + Length('begin') - 1) +
      cLineBreak +
      '  try' + cLineBreak +
      '    ExitCode := TDfmStreamAll.Run;' + cLineBreak +
      '  except' + cLineBreak +
      '    ExitCode := 255;' + cLineBreak +
      '  end;' + cLineBreak +
      '  Halt(ExitCode);' + lSuffix;
    lChangedValidatorStart := True;
  end;

  if lBomPrefix <> '' then
    lWorkText := lBomPrefix + lWorkText;

  aChanged := lChangedProgramName or lChangedMadExcept or lChangedUses or lChangedValidatorStart;
  aOutputText := lWorkText;
  Result := True;
end;

function IsGeneratedUnitBuildFailure(const aBuildLines: TStrings; const aPaths: TDfmCheckPaths): Boolean;
var
  lHelperUnitNameUpper: string;
  lHelperUnitPathUpper: string;
  lLine: string;
  lLineUpper: string;
  lLegacyUnitNameUpper: string;
  lLegacyUnitPathUpper: string;
  lUnitPathUpper: string;
  lUnitNameUpper: string;
begin
  Result := False;
  if aBuildLines = nil then
    Exit(False);

  lLegacyUnitPathUpper := UpperCase(TPath.Combine(aPaths.fProjectDir, aPaths.fProjectName + '_DfmCheck_Unit.pas'));
  lLegacyUnitNameUpper := UpperCase(aPaths.fProjectName + '_DfmCheck_Unit.pas');
  lHelperUnitPathUpper := UpperCase(aPaths.fGeneratedRegisterUnit);
  if lHelperUnitPathUpper = '' then
    lHelperUnitPathUpper := UpperCase(TPath.Combine(aPaths.fProjectDir, aPaths.fProjectName + '_DfmCheck_Register.pas'));
  lHelperUnitNameUpper := UpperCase(TPath.GetFileName(lHelperUnitPathUpper));
  lUnitPathUpper := lLegacyUnitPathUpper;
  lUnitNameUpper := lLegacyUnitNameUpper;

  for lLine in aBuildLines do
  begin
    lLineUpper := UpperCase(lLine);
    if (Pos(lUnitNameUpper, lLineUpper) = 0) and
      (Pos(lUnitPathUpper, lLineUpper) = 0) and
      (Pos(lHelperUnitNameUpper, lLineUpper) = 0) and
      (Pos(lHelperUnitPathUpper, lLineUpper) = 0) then
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
  lGeneratedParentDir: string;
  lProjectParentDir: string;
  lCandidatePath: string;
begin
  aError := '';
  aValidatorExePath := '';
  lExeBaseName := TPath.GetFileNameWithoutExtension(aPaths.fGeneratedDproj) + '.exe';
  lGeneratedParentDir := ExcludeTrailingPathDelimiter(ExtractFileDir(aPaths.fGeneratedDir));
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
    if lGeneratedParentDir <> '' then
    begin
      lExpectedPathList.Add(TPath.Combine(TPath.Combine(TPath.Combine(lGeneratedParentDir, 'Bin'), aPlatform),
        TPath.Combine(aConfig, lExeBaseName)));
      lExpectedPathList.Add(TPath.Combine(TPath.Combine(lGeneratedParentDir, 'Bin'), lExeBaseName));
    end;
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(TPath.Combine(aPaths.fProjectDir, aPlatform), aConfig),
      lExeBaseName));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(TPath.Combine(aPaths.fProjectDir, 'Bin'), aPlatform),
      TPath.Combine(aConfig, lExeBaseName)));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(aPaths.fProjectDir, 'Bin'), lExeBaseName));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(TPath.Combine(lProjectParentDir, 'Bin'), aPlatform),
      TPath.Combine(aConfig, lExeBaseName)));
    lExpectedPathList.Add(TPath.Combine(TPath.Combine(lProjectParentDir, 'Bin'), lExeBaseName));
    if aPaths.fForcedExeOutputDir <> '' then
    begin
      lExpectedPathList.Add(TPath.Combine(aPaths.fForcedExeOutputDir, lExeBaseName));
      lExpectedPathList.Add(TPath.Combine(TPath.Combine(aPaths.fForcedExeOutputDir, aPlatform),
        TPath.Combine(aConfig, lExeBaseName)));
    end;
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
  lCacheDisplay: string;
  lCacheError: string;
  lCacheFilterCsv: string;
  lCacheModules: TArray<TDfmCacheModule>;
  lCacheStats: TDfmCacheStats;
  lCopiedDfmStreamAll: Boolean;
  lCopiedRuntimeGuard: Boolean;
  lDelphiVersion: string;
  lDiagnostics: TDiagnostics;
  lDiagnosticsDefaults: TDiagnosticsDefaults;
  lDprojPath: string;
  lEffectiveOptions: TAppOptions;
  lFailedResources: TStringList;
  lPaths: TDfmCheckPaths;
  lText: string;
  lExitCode: Cardinal;
  lRunnerError: string;
  lBuildLines: TStringList;
  lBuildExePath: string;
  lBuildExeOverride: string;
  lBuildArgs: string;
  lBuildCmdPath: string;
  lBuildLogPath: string;
  lBuildVerbosity: string;
  lConfig: string;
  lFailLines: Integer;
  lForcedDcuOutputDir: string;
  lForcedExeOutputDir: string;
  lGeneratorFilterCsv: string;
  lRunGuid: TGUID;
  lRunSuffix: string;
  lSummary: TDfmValidationSummary;
  lPlatform: string;
  lValidatorArgs: string;
  lValidatorExePath: string;
  lValidatorLogPath: string;
  lValidatorScope: string;
  lUseQuietValidator: Boolean;
  lValidatorStreamingOutput: Boolean;
  lVerbose: Boolean;
  lDiagnosticModules: TArray<TDfmCacheModule>;
  lDiagnosticError: string;
  lFailReasons: TStringList;
  lPromotedWarnings: Integer;
  lHadDfmStreamAll: Boolean;
  lHadRuntimeGuard: Boolean;
  lMappedExitCode: Integer;
  lNativeExitCodeText: string;
  lOriginalAllRequested: Boolean;
  lWarnLines: Integer;
  lWarnReasons: TStringList;
  lWarnedResources: TStringList;
  lCleanupErrors: string;
begin
  Result := 1;
  aError := '';
  aCategory := TDfmCheckErrorCategory.ecNone;
  lCopiedDfmStreamAll := False;
  lCopiedRuntimeGuard := False;
  lCacheStats := Default(TDfmCacheStats);
  lCacheModules := nil;
  lCacheFilterCsv := '';
  lCacheDisplay := '';
  lCacheError := '';
  lEffectiveOptions := aOptions;
  lGeneratorFilterCsv := '';
  lValidatorExePath := '';
  lValidatorLogPath := '';
  lSummary := Default(TDfmValidationSummary);
  lFailLines := 0;
  lWarnLines := 0;
  lVerbose := aOptions.fVerbose;
  lDiagnosticModules := nil;
  lDiagnosticError := '';
  lPromotedWarnings := 0;
  lOriginalAllRequested := aOptions.fDfmCheckAll or (Trim(aOptions.fDfmCheckFilter) = '');
  lCleanupErrors := '';
  lBuildLines := TStringList.Create;
  lDiagnostics := nil;
  lFailedResources := TStringList.Create;
  lFailReasons := TStringList.Create;
  lWarnedResources := TStringList.Create;
  lWarnReasons := TStringList.Create;

  try
    lFailedResources.CaseSensitive := False;
    lFailedResources.Sorted := True;
    lFailedResources.Duplicates := TDuplicates.dupIgnore;
    lFailReasons.CaseSensitive := False;
    lFailReasons.Sorted := False;
    lFailReasons.Duplicates := TDuplicates.dupIgnore;
    lFailReasons.NameValueSeparator := '=';
    lWarnedResources.CaseSensitive := False;
    lWarnedResources.Sorted := True;
    lWarnedResources.Duplicates := TDuplicates.dupIgnore;
    lWarnReasons.CaseSensitive := False;
    lWarnReasons.Sorted := False;
    lWarnReasons.Duplicates := TDuplicates.dupIgnore;
    lWarnReasons.NameValueSeparator := '=';

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
    lDiagnostics := TDiagnostics.Create;
    LoadDiagnosticsDefaults(lDiagnostics, lDprojPath, lDiagnosticsDefaults);
    ApplyDiagnosticsOverrides(aOptions, lDiagnosticsDefaults);
    lDiagnostics.EmitWarnings(
      procedure(const aMessage: string)
      begin
        EmitLine(aOutput, '[dfm-check] Warning: ' + aMessage);
      end);

    if lOriginalAllRequested then
    begin
      if not TryPrepareDfmCacheSelection(lDprojPath, lCacheModules, lCacheFilterCsv, lCacheDisplay, lCacheStats, aError)
      then
      begin
        aCategory := TDfmCheckErrorCategory.ecInvalidInput;
        Exit(MapDfmCheckExitCode(aCategory, 0));
      end;
      EmitLine(aOutput, Format('[dfm-check] Cache: total=%d unchanged=%d validating=%d', [lCacheStats.fTotal,
        lCacheStats.fSkippedUnchanged, lCacheStats.fToValidate]));
      if lVerbose then
        EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Cache file: ' + lCacheStats.fFilePath);
      if lVerbose and (lCacheDisplay <> '') then
        EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Cache selection: ' + lCacheDisplay);
      if lCacheStats.fToValidate = 0 then
      begin
        EmitLine(aOutput, '[dfm-check] Summary: streamed=0 skipped=0 failed=0 requested=0 matched=0');
        EmitLine(aOutput, '[dfm-check] Result: OK');
        Result := 0;
        Exit(0);
      end;

      lEffectiveOptions.fDfmCheckAll := False;
      lEffectiveOptions.fDfmCheckFilter := lCacheFilterCsv;
      lDiagnosticModules := Copy(lCacheModules, 0, Length(lCacheModules));
    end else
    begin
      if not TryCollectDfmModuleMetadata(lDprojPath, lDiagnosticModules, lDiagnosticError) then
        EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Module metadata warning: ' + lDiagnosticError);
    end;

    if not TryBuildValidatorArguments(lEffectiveOptions, lDprojPath, lValidatorArgs, lValidatorScope, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecInvalidInput;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    if StartsText('--dfm=', lValidatorArgs) then
      lGeneratorFilterCsv := TrimMatchingQuotes(Copy(lValidatorArgs, Length('--dfm=') + 1, MaxInt));

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
        EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Using Delphi version from dak.ini: ' + lDelphiVersion);
    end;
    if lDelphiVersion = '' then
    begin
      aCategory := TDfmCheckErrorCategory.ecInvalidInput;
      aError := 'Delphi version is required for dfm-check. Pass --delphi <major.minor> or set [Build] DelphiVersion in dak.ini.';
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    if (lDelphiVersion <> '') and (Pos('.', lDelphiVersion) = 0) then
      lDelphiVersion := lDelphiVersion + '.0';

    if aOptions.fHasRsVarsPath or (lDelphiVersion <> '') then
    begin
      EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Loading RAD Studio environment from rsvars.bat...');
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
    if CreateGUID(lRunGuid) = S_OK then
      lRunSuffix := GUIDToString(lRunGuid)
    else
      lRunSuffix := FormatDateTime('yyyymmddhhnnsszzz', Now);
    lRunSuffix := StringReplace(lRunSuffix, '{', '', [rfReplaceAll]);
    lRunSuffix := StringReplace(lRunSuffix, '}', '', [rfReplaceAll]);
    lRunSuffix := StringReplace(lRunSuffix, '-', '', [rfReplaceAll]);
    AssignOwnedRunPaths(lPaths, lRunSuffix);
    TDirectory.CreateDirectory(lPaths.fRunsDir);
    CleanupOwnedRunDirectories(lPaths.fRunsDir, lPaths.fRunDir, aOutput, lVerbose);

    if not TryResolveInjectDir(lPaths.fInjectDir, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecInjectFilesMissing;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    lPaths.fInjectDfmStreamAll := TPath.Combine(lPaths.fInjectDir, 'DfmStreamAll.pas');
    lPaths.fInjectRuntimeGuard := TPath.Combine(lPaths.fInjectDir, 'DfmCheckRuntimeGuard.pas');
    if not FileExists(lPaths.fInjectDfmStreamAll) then
    begin
      aCategory := TDfmCheckErrorCategory.ecInjectFilesMissing;
      aError := 'Missing inject file: ' + lPaths.fInjectDfmStreamAll;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    if not FileExists(lPaths.fInjectRuntimeGuard) then
    begin
      aCategory := TDfmCheckErrorCategory.ecInjectFilesMissing;
      aError := 'Missing inject file: ' + lPaths.fInjectRuntimeGuard;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;

    EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Generating DFMCheck project...');
    if not TryGenerateDfmCheckProject(lEffectiveOptions, lDprojPath, lGeneratorFilterCsv, lPaths, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecDfmCheckFailed;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;

    if not TryLocateGeneratedDfmCheckProject(lPaths, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecGeneratedProjectMissing;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Generated project: ' + lPaths.fGeneratedDproj);

    lHadDfmStreamAll := FileExists(TPath.Combine(lPaths.fGeneratedDir, 'DfmStreamAll.pas'));
    lHadRuntimeGuard := FileExists(TPath.Combine(lPaths.fGeneratedDir, 'DfmCheckRuntimeGuard.pas'));
    TFile.Copy(lPaths.fInjectDfmStreamAll, TPath.Combine(lPaths.fGeneratedDir, 'DfmStreamAll.pas'), True);
    TFile.Copy(lPaths.fInjectRuntimeGuard, TPath.Combine(lPaths.fGeneratedDir, 'DfmCheckRuntimeGuard.pas'), True);
    lCopiedDfmStreamAll := not lHadDfmStreamAll;
    lCopiedRuntimeGuard := not lHadRuntimeGuard;

    lBuildExeOverride := Trim(GetEnvironmentVariable('DAK_DFMCHECK_MSBUILD'));
    if not TryResolveMsBuildPath(lBuildExeOverride, lBuildExePath, lRunnerError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecToolNotFound;
      aError := lRunnerError;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Using MSBuild: ' + lBuildExePath);

    lForcedExeOutputDir := TPath.Combine(lPaths.fRunDir, 'bin');
    lForcedDcuOutputDir := TPath.Combine(lPaths.fRunDir, 'dcu');
    TDirectory.CreateDirectory(lForcedExeOutputDir);
    TDirectory.CreateDirectory(lForcedDcuOutputDir);
    lPaths.fForcedExeOutputDir := lForcedExeOutputDir;
    lPaths.fForcedDcuOutputDir := lForcedDcuOutputDir;

    EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Building generated DfmCheck project via MSBuild...');
    lBuildVerbosity := '/v:q';
    lBuildArgs :=
      QuoteCmdArg(lPaths.fGeneratedDproj) + ' /t:Build /p:Config=' + lConfig + ' /p:Platform=' + lPlatform +
      ' /p:DCC_ForceExecute=true /p:DCC_ExeOutput=' + QuoteCmdArg(IncludeTrailingPathDelimiter(lForcedExeOutputDir)) +
      ' /p:DCC_DcuOutput=' + QuoteCmdArg(IncludeTrailingPathDelimiter(lForcedDcuOutputDir)) +
      ' ' + lBuildVerbosity;
    lBuildLogPath := TPath.Combine(lPaths.fGeneratedDir, '_DfmCheckBuild.log');
    lBuildCmdPath := TPath.Combine(lPaths.fGeneratedDir, '_DfmCheckBuild.cmd');
    TFile.WriteAllText(lBuildCmdPath,
      '@echo off' + #13#10 +
      QuoteCmdArg(lBuildExePath) + ' ' + lBuildArgs + ' > ' + QuoteCmdArg(lBuildLogPath) + ' 2>&1' + #13#10 +
      'exit /b %errorlevel%' + #13#10, TEncoding.Default);
    if not aRunner.Run(lBuildCmdPath, '', lPaths.fGeneratedDir, nil, lExitCode, lRunnerError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecBuildFailed;
      aError := 'MSBuild failed to start: ' + lRunnerError;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;
    if FileExists(lBuildLogPath) then
    begin
      try
        lBuildLines.LoadFromFile(lBuildLogPath, TEncoding.UTF8);
      except
        lBuildLines.LoadFromFile(lBuildLogPath, TEncoding.Default);
      end;
    end;
    if lExitCode <> 0 then
    begin
      EmitBuildFailureDiagnostics(lBuildLines, aOutput);
      lNativeExitCodeText := FormatExitCodeForDisplay(lExitCode);
      if IsGeneratedUnitBuildFailure(lBuildLines, lPaths) then
      begin
        aCategory := TDfmCheckErrorCategory.ecGeneratorIncompatible;
        aError := 'Generated helper unit failed to compile (generator incompatibility). MSBuild exited with code ' +
          lNativeExitCodeText + '.';
      end else
      begin
        aCategory := TDfmCheckErrorCategory.ecBuildFailed;
        aError := 'MSBuild exited with code ' + lNativeExitCodeText + '.';
      end;
      lMappedExitCode := NormalizeNativeExitCode(lExitCode);
      Exit(MapDfmCheckExitCode(aCategory, lMappedExitCode));
    end;

    if not TryFindValidatorExe(lPaths, lPlatform, lConfig, lValidatorExePath, aError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecValidatorNotFound;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;

    lValidatorLogPath := TPath.Combine(lPaths.fGeneratedDir, '_DfmCheckValidator.log');
    if FileExists(lValidatorLogPath) then
    begin
      try
        TFile.Delete(lValidatorLogPath);
      except
        // Best-effort cleanup before new run.
      end;
    end;
    // All-mode should emit live CHECK progress; filtered runs stay quiet by default.
    lUseQuietValidator := not lOriginalAllRequested;
    lValidatorStreamingOutput := not lUseQuietValidator;
    if lUseQuietValidator then
      lValidatorArgs := Trim(lValidatorArgs + ' --quiet');
    if lOriginalAllRequested then
      lValidatorArgs := Trim(lValidatorArgs + ' --progress');
    lValidatorArgs := Trim(lValidatorArgs + ' --log-file=' + QuoteCmdArg(lValidatorLogPath));

    EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Validator scope: ' + lValidatorScope);
    EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Running validator exe...');
    if not aRunner.Run(lValidatorExePath, lValidatorArgs, lPaths.fGeneratedDir, nil, lExitCode, lRunnerError) then
    begin
      aCategory := TDfmCheckErrorCategory.ecValidatorFailed;
      aError := 'Validator executable failed to start: ' + lRunnerError;
      Exit(MapDfmCheckExitCode(aCategory, 0));
    end;

    EmitValidatorLog(lValidatorLogPath, lVerbose, aOutput, lValidatorStreamingOutput, lOriginalAllRequested,
      lFailedResources, lFailReasons, lWarnedResources, lWarnReasons, lDiagnosticModules, lSummary, lFailLines,
      lWarnLines);
    lPromotedWarnings := EmitPromotedWarningGuidance(aOutput, lWarnedResources, lWarnReasons, lDiagnosticModules,
      lDiagnosticsDefaults, lFailedResources);
    if lCacheStats.fEnabled then
    begin
      if (lExitCode <> 0) and (lFailLines = 0) then
      begin
        EmitVerboseLine(lVerbose, aOutput,
          '[dfm-check] Cache skipped: validator failed without resource-level FAIL lines.');
      end else if not TryWriteDfmCache(lCacheStats.fFilePath, lCacheModules, lFailedResources, lCacheError) then
      begin
        EmitVerboseLine(lVerbose, aOutput, '[dfm-check] Cache warning: ' + lCacheError);
      end;
    end;
    if lSummary.fHasSummary then
      EmitLine(aOutput, Format('[dfm-check] Summary: streamed=%d skipped=%d failed=%d requested=%d matched=%d',
        [lSummary.fStreamed, lSummary.fSkipped, lSummary.fFailed, lSummary.fRequested, lSummary.fMatched]))
    else if lExitCode = 0 then
      EmitLine(aOutput, '[dfm-check] Summary: failed=0')
    else
      EmitLine(aOutput, '[dfm-check] Summary: validator exit code=' + FormatExitCodeForDisplay(lExitCode));
    if lPromotedWarnings > 0 then
      EmitLine(aOutput, Format('[dfm-check] Warning diagnostics: promoted=%d', [lPromotedWarnings]));

    if (lExitCode <> 0) and (not lVerbose) and (lFailLines = 0) then
      EmitLine(aOutput, '[dfm-check] FAIL details hidden or unavailable. Re-run with --verbose.');
    if lFailLines > 0 then
      EmitFailedResourceGuidance(aOutput, lFailedResources, lFailReasons, lDiagnosticModules, lDiagnosticsDefaults);

    if (lExitCode = 0) and (lPromotedWarnings = 0) then
      EmitLine(aOutput, '[dfm-check] Result: OK')
    else if lPromotedWarnings > 0 then
      EmitLine(aOutput, Format('[dfm-check] Result: FAIL (%d diagnosed warning(s))', [lPromotedWarnings]))
    else if (lFailLines = 0) and (lExitCode > Cardinal(High(Integer))) then
      EmitLine(aOutput, '[dfm-check] Result: FAIL (validator crashed, exit code ' + FormatExitCodeForDisplay(lExitCode) + ')')
    else
      EmitLine(aOutput, Format('[dfm-check] Result: FAIL (%s error(s))', [FormatExitCodeForDisplay(lExitCode)]));

    // Propagate streaming validator result directly: 0 = success, >0 = number of failed resources.
    if lPromotedWarnings > 0 then
      Result := lPromotedWarnings
    else if lExitCode <= Cardinal(High(Integer)) then
      Result := Integer(lExitCode)
    else
      Result := MapDfmCheckExitCode(TDfmCheckErrorCategory.ecValidatorFailed, 0);
  finally
    lDiagnostics.Free;
    lWarnReasons.Free;
    lWarnedResources.Free;
    lFailReasons.Free;
    lFailedResources.Free;
    lBuildLines.Free;
    if ShouldKeepArtifacts then
    begin
      CleanupProjectRootArtifacts(lPaths, lCleanupErrors);
      if lCleanupErrors <> '' then
        EmitLine(aOutput, '[dfm-check] Cleanup warning: ' + lCleanupErrors);
      EmitLine(aOutput, '[dfm-check] Keeping generated _DfmCheck artifacts (DAK_DFMCHECK_KEEP_ARTIFACTS).');
    end
    else
      CleanupGeneratedArtifacts(lPaths, lCopiedDfmStreamAll, lCopiedRuntimeGuard, lValidatorExePath, aOutput, lVerbose);
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
  lCreateFlags: Cardinal;
  lIsolatedDesktop: HDESK;
  lIsolatedDesktopName: string;
  lIsolatedProcess: Boolean;
  lStartTick: Cardinal;
  lTimeoutMs: Cardinal;
  lPreviousErrorMode: Cardinal;
  lCommandExe: string;
  lCommandScript: string;
  lElapsedSec: Cardinal;
  lHeartbeatTick: Cardinal;
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
  lStartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  lStartupInfo.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  lStartupInfo.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
  lStartupInfo.hStdError := GetStdHandle(STD_ERROR_HANDLE);
  lStartupInfo.wShowWindow := SW_HIDE;
  FillChar(lProcessInfo, SizeOf(lProcessInfo), 0);
  lCreateFlags := CREATE_NO_WINDOW;
  lIsolatedDesktop := 0;
  lIsolatedDesktopName := '';
  lIsolatedProcess := False;
  lStartTick := 0;
  lTimeoutMs := 0;
  lHeartbeatTick := 0;

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

  lIsolatedProcess := ShouldIsolateUiProcess(aExePath, aArguments);
  if lIsolatedProcess then
  begin
    lIsolatedDesktopName := Format('DAK_DFMCHECK_%d_%d', [GetCurrentProcessId, GetTickCount]);
    lIsolatedDesktop := CreateDesktop(PChar(lIsolatedDesktopName), nil, nil, 0, GENERIC_ALL, nil);
    if lIsolatedDesktop <> 0 then
      lStartupInfo.lpDesktop := PChar(lIsolatedDesktopName);
    lTimeoutMs := 0;
  end;

  lPreviousErrorMode := SetErrorMode(SEM_FAILCRITICALERRORS or SEM_NOGPFAULTERRORBOX or SEM_NOOPENFILEERRORBOX);
  if lAppName = '' then
  begin
    if not CreateProcess(nil, PChar(lCmdLine), nil, nil, True, lCreateFlags, nil, PChar(lWorkDir), lStartupInfo,
      lProcessInfo)
    then
    begin
      lLastError := GetLastError;
      aError := SysErrorMessage(lLastError);
      SetErrorMode(lPreviousErrorMode);
      Exit(False);
    end;
  end else if not CreateProcess(PChar(lAppName), PChar(lCmdLine), nil, nil, True, lCreateFlags, nil, PChar(lWorkDir),
      lStartupInfo, lProcessInfo) then
  begin
    lLastError := GetLastError;
    aError := SysErrorMessage(lLastError);
    SetErrorMode(lPreviousErrorMode);
    Exit(False);
  end;
  SetErrorMode(lPreviousErrorMode);
  lStartTick := GetTickCount;
  lHeartbeatTick := lStartTick;

  try
    repeat
      lWaitResult := WaitForSingleObject(lProcessInfo.hProcess, 200);
      if lWaitResult = WAIT_TIMEOUT then
      begin
        if lIsolatedDesktop <> 0 then
          CloseTopLevelWindowsForProcess(lProcessInfo.dwProcessId, lIsolatedDesktop)
        else
          CloseTopLevelWindowsForProcess(lProcessInfo.dwProcessId);
        if lIsolatedProcess and Assigned(aOutput) and ((GetTickCount - lHeartbeatTick) >= 15000) then
        begin
          lElapsedSec := (GetTickCount - lStartTick) div 1000;
          aOutput(Format('[dfm-check] Validator still running (%ds)...', [lElapsedSec]));
          lHeartbeatTick := GetTickCount;
        end;
        if (lTimeoutMs <> 0) and ((GetTickCount - lStartTick) >= lTimeoutMs) then
        begin
          TerminateProcess(lProcessInfo.hProcess, 146);
          aError := 'Process timed out waiting for background validation.';
          Exit(False);
        end;
      end;
    until lWaitResult <> WAIT_TIMEOUT;
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
    if lIsolatedDesktop <> 0 then
      CloseDesktop(lIsolatedDesktop);
    CloseHandle(lProcessInfo.hThread);
    CloseHandle(lProcessInfo.hProcess);
  end;

  Result := True;
end;

end.
