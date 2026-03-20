unit Dak.Build;

interface

uses
  System.Generics.Collections, System.JSON, System.SysUtils,
  Dak.Types;

type
  TBuildSummaryOptions = record
    fProjectRoot: string;
    fIgnoreWarnings: string;
    fIgnoreHints: string;
    fExcludePathMasks: string;
    fMaxFindings: Integer;
    fIncludeWarnings: Boolean;
    fIncludeHints: Boolean;
  end;

  TBuildSummary = record
    fStatus: string;
    fExitCode: Integer;
    fErrorCount: Integer;
    fWarningCount: Integer;
    fHintCount: Integer;
    fErrors: TArray<string>;
    fWarnings: TArray<string>;
    fHints: TArray<string>;
    fOutputPath: string;
    fOutputStale: Boolean;
    fOutputMessage: string;
    fTimedOut: Boolean;
  end;

  IBuildProcessRunner = interface
    ['{98F53F02-06E8-4684-9316-B5472C4FD666}']
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      aTimeoutSec: Integer; out aExitCode: Integer; out aTimedOut: Boolean; out aError: string): Boolean;
  end;

function ParseBuildLogs(const aOutLogPath, aErrLogPath: string;
  const aOptions: TBuildSummaryOptions): TBuildSummary;
function BuildSummaryAsJson(const aProjectPath: string; const aOptions: TAppOptions;
  const aSummary: TBuildSummary; const aTarget: string; aTimeMs: Int64): string;
function TryRunBuild(const aOptions: TAppOptions; out aExitCode: Integer; out aError: string): Boolean; overload;
function TryRunBuild(const aOptions: TAppOptions; const aRunner: IBuildProcessRunner;
  out aExitCode: Integer; out aError: string): Boolean; overload;

implementation

uses
  System.Classes, System.IniFiles, System.IOUtils, System.RegularExpressions, System.StrUtils,
  System.Win.Registry,
  Winapi.Windows,
  Dak.FixInsightSettings, Dak.MacroExpander, Dak.Messages, Dak.MsBuild, Dak.Project, Dak.RsVars,
  Dak.SourceContext;

const
  cStatusOk = 'ok';
  cStatusWarnings = 'warnings';
  cStatusHints = 'hints';
  cStatusError = 'error';
  cStatusTimeout = 'timeout';
  cStatusOutputLocked = 'output_locked';
  cStatusInternalError = 'internal_error';
  cMadExceptSymbol = 'madExcept';
  cMadExceptPatchExeName = 'madExceptPatch.exe';
  cMsBuildNotFound = 'MSBuild.exe not found.';
  cMadExceptPatchRequiredMessage = 'madExcept patch is required but madExceptPatch.exe was not found.';
  cMadExceptPatchFailedMessage = 'madExcept patch step failed.';
  cOutputLockedMessage =
    'Compilation succeeded but output file timestamp was not updated. The executable may be locked by another process.';

type
  TBuildSettings = record
    fIgnoreWarnings: string;
    fIgnoreHints: string;
    fExcludePathMasks: string;
    fMadExceptPath: string;
  end;

  TBuildProjectInfo = record
    fProjectPath: string;
    fProjectDir: string;
    fProjectName: string;
    fMainSourcePath: string;
    fMesPath: string;
    fDefines: string;
    fOutputPath: string;
    fMadExceptRequired: Boolean;
    fMadExceptReason: string;
  end;

  TBuildProcessRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      aTimeoutSec: Integer; out aExitCode: Integer; out aTimedOut: Boolean; out aError: string): Boolean;
  end;

function QuoteCmdArg(const aValue: string): string;
begin
  if (aValue = '') or (Pos(' ', aValue) > 0) or (Pos('"', aValue) > 0) or (Pos(';', aValue) > 0) then
    Result := '"' + StringReplace(aValue, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := aValue;
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

function TryResolveDprojPath(const aInputPath: string; out aDprojPath: string; out aError: string): Boolean;
var
  lCandidate: string;
  lExt: string;
  lInputPath: string;
begin
  aError := '';
  if not TryNormalizeInputPath(aInputPath, lInputPath, aError) then
    Exit(False);

  aDprojPath := TPath.GetFullPath(lInputPath);
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
    lCandidate := TPath.ChangeExtension(aDprojPath, '.dproj');
    if FileExists(lCandidate) then
    begin
      aDprojPath := lCandidate;
      Exit(True);
    end;
    aError := Format(SAssociatedDprojMissing, [aDprojPath]);
    Exit(False);
  end;

  aError := Format(SUnsupportedProjectInput, [aDprojPath]);
  Result := False;
end;

function NormalizeDelphiVerForBuild(const aValue: string): string;
begin
  Result := Trim(aValue);
  if (Result <> '') and (Pos('.', Result) = 0) then
    Result := Result + '.0';
end;

function MergeList(const aBaseValue, aExtraValue: string): string;
var
  lItems: TList<string>;
  lItem: string;
  lPart: string;
  lSeen: THashSet<string>;
  lValue: string;
begin
  lItems := TList<string>.Create;
  lSeen := THashSet<string>.Create;
  try
    for lValue in [aBaseValue, aExtraValue] do
    begin
      if Trim(lValue) = '' then
        Continue;
      for lPart in lValue.Split([';']) do
      begin
        lItem := Trim(lPart);
        if lItem = '' then
          Continue;
        if lSeen.Add(UpperCase(lItem)) then
          lItems.Add(lItem);
      end;
    end;
    Result := String.Join(';', lItems.ToArray);
  finally
    lSeen.Free;
    lItems.Free;
  end;
end;

function SplitList(const aValue: string): TArray<string>;
var
  lItem: string;
  lItems: TList<string>;
  lPart: string;
begin
  lItems := TList<string>.Create;
  try
    for lPart in aValue.Split([';']) do
    begin
      lItem := Trim(lPart);
      if lItem <> '' then
        lItems.Add(lItem);
    end;
    Result := lItems.ToArray;
  finally
    lItems.Free;
  end;
end;

function MatchesMaskCI(const aText, aMask: string): Boolean;
var
  i: Integer;
  j: Integer;
  lMark: Integer;
  lMask: string;
  lStar: Integer;
  lText: string;
begin
  lText := UpperCase(aText);
  lMask := UpperCase(aMask);
  i := 1;
  j := 1;
  lStar := 0;
  lMark := 0;
  while i <= Length(lText) do
  begin
    if (j <= Length(lMask)) and ((lMask[j] = '?') or (lMask[j] = lText[i])) then
    begin
      Inc(i);
      Inc(j);
    end else if (j <= Length(lMask)) and (lMask[j] = '*') then
    begin
      lStar := j;
      lMark := i;
      Inc(j);
    end else if lStar <> 0 then
    begin
      j := lStar + 1;
      Inc(lMark);
      i := lMark;
    end else
      Exit(False);
  end;

  while (j <= Length(lMask)) and (lMask[j] = '*') do
    Inc(j);

  Result := j > Length(lMask);
end;

function NormalizeDir(const aDir: string): string;
var
  lRoot: string;
begin
  if aDir = '' then
    Exit('');

  Result := TPath.GetFullPath(aDir);
  lRoot := TPath.GetPathRoot(Result);
  if (lRoot <> '') and SameText(Result, lRoot) then
    Exit(lRoot);

  Result := ExcludeTrailingPathDelimiter(Result);
end;

function FindRepoRoot(const aStartDir: string): string;
var
  lDir: string;
  lParent: string;
begin
  lDir := NormalizeDir(aStartDir);
  while lDir <> '' do
  begin
    if DirectoryExists(TPath.Combine(lDir, '.git')) or DirectoryExists(TPath.Combine(lDir, '.svn')) then
      Exit(lDir);
    lParent := NormalizeDir(ExtractFileDir(lDir));
    if (lParent = '') or SameText(lParent, lDir) then
      Break;
    lDir := lParent;
  end;
  Result := '';
end;

function DetermineProjectRoot(const aProjectPath: string): string;
var
  lProjectDir: string;
begin
  lProjectDir := NormalizeDir(ExtractFileDir(TPath.GetFullPath(aProjectPath)));
  Result := FindRepoRoot(lProjectDir);
  if Result = '' then
    Result := lProjectDir;
end;

function NormalizeBuildLine(const aLine, aProjectRoot: string): string;
var
  lRoot: string;
begin
  Result := aLine;
  lRoot := NormalizeDir(aProjectRoot);
  if lRoot = '' then
    Exit;

  if not lRoot.EndsWith('\') then
    lRoot := lRoot + '\';

  Result := TRegEx.Replace(Result, '(?i)' + TRegEx.Escape(lRoot), '');
  Result := TRegEx.Replace(Result, '(?i)\[' + TRegEx.Escape(lRoot), '[');
end;

function LineIsExcluded(const aLine, aExcludeMasks: string): Boolean;
var
  lFileName: string;
  lMatch: TMatch;
  lNormalizedMask: string;
  lRawMask: string;
begin
  Result := False;
  if Trim(aExcludeMasks) = '' then
    Exit(False);

  lMatch := TRegEx.Match(aLine, '^(?<f>.+?)\(\d+');
  if not lMatch.Success then
    Exit(False);

  lFileName := Trim(lMatch.Groups['f'].Value.Replace('/', '\', [rfReplaceAll]));
  lFileName := lFileName.TrimLeft(['.', '\']);
  for lRawMask in SplitList(aExcludeMasks) do
  begin
    lNormalizedMask := lRawMask.Replace('/', '\', [rfReplaceAll]).TrimLeft(['.', '\']);
    if MatchesMaskCI(lFileName, lNormalizedMask) then
      Exit(True);
  end;
end;

function BuildIgnoreSet(const aValue: string): THashSet<string>;
var
  lItem: string;
begin
  Result := THashSet<string>.Create;
  for lItem in SplitList(aValue) do
    Result.Add(UpperCase(lItem));
end;

procedure AddFinding(var aItems: TArray<string>; const aLine: string; const aLimit: Integer);
var
  lLength: Integer;
begin
  if (aLimit > 0) and (Length(aItems) >= aLimit) then
    Exit;

  lLength := Length(aItems);
  SetLength(aItems, lLength + 1);
  aItems[lLength] := aLine;
end;

procedure ParseLogFile(const aLogPath: string; const aOptions: TBuildSummaryOptions;
  const aIgnoreWarnings, aIgnoreHints: THashSet<string>; var aSummary: TBuildSummary);
var
  lCode: string;
  lLine: string;
  lLines: TStringList;
  lMatch: TMatch;
  lNormalizedLine: string;
begin
  if (aLogPath = '') or (not FileExists(aLogPath)) then
    Exit;

  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aLogPath);
    for lLine in lLines do
    begin
      lNormalizedLine := NormalizeBuildLine(lLine, aOptions.fProjectRoot);
      if LineIsExcluded(lNormalizedLine, aOptions.fExcludePathMasks) then
        Continue;

      if TRegEx.IsMatch(lNormalizedLine, ':\s+error\s+') or TRegEx.IsMatch(lNormalizedLine, ':\s+fatal\s+') then
      begin
        Inc(aSummary.fErrorCount);
        AddFinding(aSummary.fErrors, lNormalizedLine.Trim, aOptions.fMaxFindings);
        Continue;
      end;

      lMatch := TRegEx.Match(lNormalizedLine, ':\s+warning\s+(W\d+):');
      if lMatch.Success then
      begin
        lCode := UpperCase(lMatch.Groups[1].Value);
        if not aIgnoreWarnings.Contains(lCode) then
        begin
          Inc(aSummary.fWarningCount);
          if aOptions.fIncludeWarnings then
            AddFinding(aSummary.fWarnings, lNormalizedLine.Trim, aOptions.fMaxFindings);
        end;
        Continue;
      end;

      lMatch := TRegEx.Match(lNormalizedLine, ' hint warning\s+(H\d+):');
      if not lMatch.Success then
        lMatch := TRegEx.Match(lNormalizedLine, ':\s+hint\s+(H\d+):');
      if lMatch.Success then
      begin
        lCode := UpperCase(lMatch.Groups[1].Value);
        if not aIgnoreHints.Contains(lCode) then
        begin
          Inc(aSummary.fHintCount);
          if aOptions.fIncludeHints then
            AddFinding(aSummary.fHints, lNormalizedLine.Trim, aOptions.fMaxFindings);
        end;
      end;
    end;
  finally
    lLines.Free;
  end;
end;

function ParseBuildLogs(const aOutLogPath, aErrLogPath: string;
  const aOptions: TBuildSummaryOptions): TBuildSummary;
var
  lIgnoreHints: THashSet<string>;
  lIgnoreWarnings: THashSet<string>;
begin
  Result := Default(TBuildSummary);
  lIgnoreWarnings := BuildIgnoreSet(aOptions.fIgnoreWarnings);
  lIgnoreHints := BuildIgnoreSet(aOptions.fIgnoreHints);
  try
    ParseLogFile(aErrLogPath, aOptions, lIgnoreWarnings, lIgnoreHints, Result);
    ParseLogFile(aOutLogPath, aOptions, lIgnoreWarnings, lIgnoreHints, Result);
  finally
    lIgnoreHints.Free;
    lIgnoreWarnings.Free;
  end;
end;

function PrefixSourceContext(const aLines: TArray<string>): string;
var
  lIndex: Integer;
  lParts: TArray<string>;
begin
  SetLength(lParts, Length(aLines));
  for lIndex := 0 to High(aLines) do
    lParts[lIndex] := '  ' + aLines[lIndex];
  Result := String.Join(sLineBreak, lParts);
end;

function AppendSourceContextToFinding(const aFinding: string; const aLookup: TProjectSourceLookup;
  aContextLines: Integer): string;
var
  lContext: TSourceContextSnippet;
  lError: string;
  lFileToken: string;
  lLineNumber: Integer;
begin
  Result := aFinding;
  if not TryParseFindingLocation(aFinding, lFileToken, lLineNumber) then
    Exit(Result);
  if not TryResolveSourceContext(aLookup, lFileToken, lLineNumber, aContextLines, lContext, lError) then
    Exit(Result);
  Result := Result + sLineBreak + PrefixSourceContext(FormatSourceContextLines(lContext));
end;

procedure EnrichBuildFindingsWithSourceContext(var aItems: TArray<string>; const aLookup: TProjectSourceLookup;
  aContextLines: Integer);
var
  i: Integer;
begin
  for i := 0 to High(aItems) do
    aItems[i] := AppendSourceContextToFinding(aItems[i], aLookup, aContextLines);
end;

function BuildSummaryAsJson(const aProjectPath: string; const aOptions: TAppOptions;
  const aSummary: TBuildSummary; const aTarget: string; aTimeMs: Int64): string;
var
  lErrors: TJSONArray;
  lHints: TJSONArray;
  lIssues: TJSONObject;
  lLine: string;
  lRoot: TJSONObject;
  lWarnings: TJSONArray;
begin
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('status', aSummary.fStatus);
    lRoot.AddPair('project', TPath.GetFileName(aProjectPath));
    lRoot.AddPair('project_path', aProjectPath);
    lRoot.AddPair('config', aOptions.fConfig);
    lRoot.AddPair('platform', aOptions.fPlatform);
    lRoot.AddPair('target', aTarget);
    lRoot.AddPair('time_ms', TJSONNumber.Create(aTimeMs));
    lRoot.AddPair('exit_code', TJSONNumber.Create(aSummary.fExitCode));
    lRoot.AddPair('errors', TJSONNumber.Create(aSummary.fErrorCount));
    lRoot.AddPair('warnings', TJSONNumber.Create(aSummary.fWarningCount));
    lRoot.AddPair('hints', TJSONNumber.Create(aSummary.fHintCount));
    lRoot.AddPair('max_findings', TJSONNumber.Create(aOptions.fBuildMaxFindings));
    lRoot.AddPair('output', aSummary.fOutputPath);
    lRoot.AddPair('output_stale', TJSONBool.Create(aSummary.fOutputStale));
    lRoot.AddPair('output_message', aSummary.fOutputMessage);

    lIssues := TJSONObject.Create;
    lErrors := TJSONArray.Create;
    lWarnings := TJSONArray.Create;
    lHints := TJSONArray.Create;
    for lLine in aSummary.fErrors do
      lErrors.Add(lLine);
    for lLine in aSummary.fWarnings do
      lWarnings.Add(lLine);
    for lLine in aSummary.fHints do
      lHints.Add(lLine);
    lIssues.AddPair('errors', lErrors);
    lIssues.AddPair('warnings', lWarnings);
    lIssues.AddPair('hints', lHints);
    lRoot.AddPair('issues', lIssues);
    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;

function CaptureEnvironment: TDictionary<string, string>;
var
  lBlock: PChar;
  lCursor: PChar;
  lLine: string;
  lName: string;
  lPos: Integer;
  lValue: string;
begin
  Result := TDictionary<string, string>.Create;
  lBlock := GetEnvironmentStrings;
  if lBlock = nil then
    Exit;

  try
    lCursor := lBlock;
    while lCursor^ <> #0 do
    begin
      lLine := lCursor;
      Inc(lCursor, Length(lLine) + 1);
      lPos := Pos('=', lLine);
      if lPos <= 1 then
        Continue;
      lName := Copy(lLine, 1, lPos - 1);
      if (lName = '') or (lName[1] = '=') then
        Continue;
      lValue := Copy(lLine, lPos + 1, MaxInt);
      Result.AddOrSetValue(lName, lValue);
    end;
  finally
    FreeEnvironmentStrings(lBlock);
  end;
end;

function ResolveBdsRoot(const aDelphiVersion, aRsVarsPath: string): string;
var
  lBase: string;
begin
  Result := Trim(GetEnvironmentVariable('BDS'));
  if Result <> '' then
    Exit(TPath.GetFullPath(Result));

  if aRsVarsPath <> '' then
    Exit(TPath.GetFullPath(ExtractFileDir(ExtractFileDir(aRsVarsPath))));

  for lBase in [
    TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'), 'Embarcadero\Studio'),
    TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'), 'Embarcadero\RAD Studio'),
    TPath.Combine(GetEnvironmentVariable('ProgramFiles'), 'Embarcadero\Studio'),
    TPath.Combine(GetEnvironmentVariable('ProgramFiles'), 'Embarcadero\RAD Studio')
  ] do
  begin
    if (lBase <> '') and DirectoryExists(TPath.Combine(lBase, aDelphiVersion)) then
      Exit(TPath.GetFullPath(TPath.Combine(lBase, aDelphiVersion)));
  end;

  Result := TPath.Combine('C:\Program Files (x86)\Embarcadero\Studio', aDelphiVersion);
end;

function BuildEnvironmentProjPath(const aDelphiVersion, aBdsRoot: string): string;
var
  lVersion: string;
begin
  lVersion := Trim(aDelphiVersion);
  if lVersion = '' then
    lVersion := ExtractFileName(ExcludeTrailingPathDelimiter(aBdsRoot));
  Result := TPath.Combine(GetEnvironmentVariable('APPDATA'),
    TPath.Combine('Embarcadero\BDS', TPath.Combine(lVersion, 'environment.proj')));
end;

procedure ApplyEnvironmentProjProps(const aEnvProjPath: string; const aEnvVars: TDictionary<string, string>;
  var aMsBuildEnvProps: string);
var
  lBody: string;
  lGroupMatch: TMatch;
  lGroupMatches: TMatchCollection;
  lKey: string;
  lMatches: TMatchCollection;
  lText: string;
  lValue: string;
  lMatch: TMatch;
begin
  aMsBuildEnvProps := '';
  if not FileExists(aEnvProjPath) then
    Exit;

  lText := TFile.ReadAllText(aEnvProjPath);
  lGroupMatches := TRegEx.Matches(lText, '<PropertyGroup(?:\s+[^>]*)?>(?<body>.*?)</PropertyGroup>',
    [roIgnoreCase, roSingleLine]);
  for lGroupMatch in lGroupMatches do
  begin
    lBody := lGroupMatch.Groups['body'].Value;
    lMatches := TRegEx.Matches(lBody, '<(?<key>[A-Za-z_][A-Za-z0-9_]*)(?:\s+[^>]*)?>(?<value>.*?)</\k<key>>',
      [roIgnoreCase, roSingleLine]);
    for lMatch in lMatches do
    begin
      lKey := Trim(lMatch.Groups['key'].Value);
      if lKey = '' then
        Continue;
      if Trim(GetEnvironmentVariable(lKey)) <> '' then
        Continue;
      if aEnvVars.ContainsKey(lKey) and (Trim(aEnvVars[lKey]) <> '') then
        Continue;

      lValue := Trim(TRegEx.Replace(lMatch.Groups['value'].Value, '<[^>]+>', ''));
      if lValue = '' then
        Continue;
      if aMsBuildEnvProps <> '' then
        aMsBuildEnvProps := aMsBuildEnvProps + ' ';
      aMsBuildEnvProps := aMsBuildEnvProps + '/p:' + lKey + '=' + QuoteCmdArg(lValue);
    end;
  end;
end;

function HasMadExceptDefine(const aDefines: string): Boolean;
var
  lDefine: string;
begin
  Result := False;
  for lDefine in SplitList(aDefines) do
    if SameText(lDefine, cMadExceptSymbol) then
      Exit(True);
end;

function TryParseIniBool(const aValue: string; out aEnabled: Boolean): Boolean;
begin
  if aValue = '' then
    Exit(False);

  if SameText(aValue, '1') or SameText(aValue, 'true') or SameText(aValue, 'yes') then
    aEnabled := True
  else if SameText(aValue, '0') or SameText(aValue, 'false') or SameText(aValue, 'no') then
    aEnabled := False
  else
    Exit(False);

  Result := True;
end;

function TryReadIniSectionValue(const aPath, aSection, aKey: string; out aValue: string): Boolean;
var
  lCurrentSection: string;
  lEqualsPos: Integer;
  lLine: string;
  lLines: TStringList;
  lName: string;
  lTrimmedLine: string;
begin
  Result := False;
  aValue := '';
  if not FileExists(aPath) then
    Exit(False);

  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aPath);
    lCurrentSection := '';
    for lLine in lLines do
    begin
      lTrimmedLine := Trim(lLine);
      if lTrimmedLine = '' then
        Continue;
      if (lTrimmedLine[1] = ';') or (lTrimmedLine[1] = '#') then
        Continue;
      if (lTrimmedLine[1] = '[') and (lTrimmedLine[Length(lTrimmedLine)] = ']') then
      begin
        lCurrentSection := Trim(Copy(lTrimmedLine, 2, Length(lTrimmedLine) - 2));
        Continue;
      end;
      if not SameText(lCurrentSection, aSection) then
        Continue;

      lEqualsPos := Pos('=', lTrimmedLine);
      if lEqualsPos <= 0 then
        Continue;
      lName := Trim(Copy(lTrimmedLine, 1, lEqualsPos - 1));
      if not SameText(lName, aKey) then
        Continue;

      aValue := Trim(Copy(lTrimmedLine, lEqualsPos + 1, MaxInt));
      Exit(True);
    end;
  finally
    lLines.Free;
  end;
end;

function MesFileDisablesMadExcept(const aMesPath: string): Boolean;
var
  lEnabled: Boolean;
  lValue: string;
begin
  Result := False;
  if not FileExists(aMesPath) then
    Exit(False);

  if TryReadIniSectionValue(aMesPath, 'GeneralSettings', 'LinkInCode', lValue) then
    if TryParseIniBool(lValue, lEnabled) and (not lEnabled) then
      Exit(True);

  if TryReadIniSectionValue(aMesPath, 'GeneralSettings', 'HandleExceptions', lValue) then
    if TryParseIniBool(lValue, lEnabled) and (not lEnabled) then
      Exit(True);
end;

function ResolveOutputName(const aProps: TDictionary<string, string>; const aProjectName: string): string;
begin
  if aProps.TryGetValue('SanitizedProjectName', Result) and (Trim(Result) <> '') then
    Exit(Result);
  if aProps.TryGetValue('ProjectName', Result) and (Trim(Result) <> '') then
    Exit(Result);
  Result := aProjectName;
end;

function BuildProjectInfo(const aProjectPath, aConfig, aPlatform: string;
  const aEnvVars: TDictionary<string, string>; const aTestOutputDir: string): TBuildProjectInfo;
var
  lDefines: string;
  lEvaluator: TMsBuildEvaluator;
  lOutputDir: string;
  lOutputName: string;
  lProps: TDictionary<string, string>;
begin
  Result := Default(TBuildProjectInfo);
  Result.fProjectPath := TPath.GetFullPath(aProjectPath);
  Result.fProjectDir := TPath.GetDirectoryName(Result.fProjectPath);
  Result.fProjectName := TPath.GetFileNameWithoutExtension(Result.fProjectPath);
  Result.fMesPath := TPath.ChangeExtension(Result.fProjectPath, '.mes');

  lProps := TDictionary<string, string>.Create;
  try
    lProps.AddOrSetValue('Config', aConfig);
    lProps.AddOrSetValue('Platform', aPlatform);

    lEvaluator := TMsBuildEvaluator.Create(lProps, aEnvVars, nil);
    try
      lEvaluator.EvaluateFile(Result.fProjectPath, Result.fMadExceptReason);
    finally
      lEvaluator.Free;
    end;

    if not lProps.TryGetValue('MainSource', Result.fMainSourcePath) or (Trim(Result.fMainSourcePath) = '') then
      Result.fMainSourcePath := Result.fProjectName + '.dpr';
    if not TPath.IsPathRooted(Result.fMainSourcePath) then
      Result.fMainSourcePath := TPath.Combine(Result.fProjectDir, Result.fMainSourcePath);
    Result.fMainSourcePath := TPath.GetFullPath(Result.fMainSourcePath);

    if not lProps.TryGetValue('DCC_ExeOutput', lOutputDir) or (Trim(lOutputDir) = '') then
      lOutputDir := Result.fProjectDir
    else if not TPath.IsPathRooted(lOutputDir) then
      lOutputDir := TPath.GetFullPath(TPath.Combine(Result.fProjectDir, lOutputDir))
    else
      lOutputDir := TPath.GetFullPath(lOutputDir);

    lOutputName := ResolveOutputName(lProps, Result.fProjectName);
    Result.fOutputPath := TPath.Combine(lOutputDir, lOutputName + '.exe');
    if aTestOutputDir <> '' then
      Result.fOutputPath := TPath.Combine(TPath.GetFullPath(aTestOutputDir), TPath.GetFileName(Result.fOutputPath));

    if lProps.TryGetValue('DCC_Define', lDefines) then
      Result.fDefines := lDefines;

    if not FileExists(Result.fMainSourcePath) then
      Result.fMadExceptReason := 'main-source-missing'
    else if not FileExists(Result.fMesPath) then
      Result.fMadExceptReason := 'mes-missing'
    else if not SameText(TPath.GetFileNameWithoutExtension(Result.fMainSourcePath), Result.fProjectName) then
      Result.fMadExceptReason := 'name-mismatch'
    else if not HasMadExceptDefine(Result.fDefines) then
      Result.fMadExceptReason := 'define-missing'
    else if MesFileDisablesMadExcept(Result.fMesPath) then
      Result.fMadExceptReason := 'mes-disabled'
    else
    begin
      Result.fMadExceptRequired := True;
      Result.fMadExceptReason := 'enabled';
    end;
  finally
    lProps.Free;
  end;
end;

function ExpandMadExceptSettingPath(const aValue, aIniPath: string; const aEnvVars: TDictionary<string, string>): string;
var
  lPair: TPair<string, string>;
  lEnv: TDictionary<string, string>;
  lProps: TDictionary<string, string>;
begin
  lProps := TDictionary<string, string>.Create;
  try
    lEnv := TDictionary<string, string>.Create;
    try
      if aEnvVars <> nil then
        for lPair in aEnvVars do
          lEnv.AddOrSetValue(lPair.Key, lPair.Value);
      Result := TMacroExpander.Expand(aValue, lProps, lEnv, nil, False);
    finally
      lEnv.Free;
    end;
  finally
    lProps.Free;
  end;
  if not TPath.IsPathRooted(Result) then
    Result := TPath.GetFullPath(TPath.Combine(ExtractFileDir(aIniPath), Result));
end;

procedure LoadBuildSettings(const aDprojPath: string; const aOptions: TAppOptions;
  const aEnvVars: TDictionary<string, string>; out aSettings: TBuildSettings);
var
  lIni: TIniFile;
  lIniPath: string;
  lValue: string;
begin
  aSettings := Default(TBuildSettings);
  for lIniPath in BuildSettingsPaths(aDprojPath) do
  begin
    if not FileExists(lIniPath) then
      Continue;

    lIni := TIniFile.Create(lIniPath);
    try
      lValue := Trim(lIni.ReadString('BuildIgnore', 'Warnings', ''));
      if lValue <> '' then
        aSettings.fIgnoreWarnings := MergeList(aSettings.fIgnoreWarnings, lValue);

      lValue := Trim(lIni.ReadString('BuildIgnore', 'Hints', ''));
      if lValue <> '' then
        aSettings.fIgnoreHints := MergeList(aSettings.fIgnoreHints, lValue);

      lValue := Trim(lIni.ReadString('ReportFilter', 'ExcludePathMasks', ''));
      if lValue <> '' then
        aSettings.fExcludePathMasks := MergeList(aSettings.fExcludePathMasks, lValue);

      lValue := Trim(lIni.ReadString('MadExcept', 'Path', ''));
      if lValue <> '' then
        aSettings.fMadExceptPath := ExpandMadExceptSettingPath(lValue, lIniPath, aEnvVars);
    finally
      lIni.Free;
    end;
  end;

  if aOptions.fHasBuildIgnoreWarnings then
    aSettings.fIgnoreWarnings := MergeList(aSettings.fIgnoreWarnings, aOptions.fBuildIgnoreWarnings);
  if aOptions.fHasBuildIgnoreHints then
    aSettings.fIgnoreHints := MergeList(aSettings.fIgnoreHints, aOptions.fBuildIgnoreHints);
  if aOptions.fHasExcludePathMasks then
    aSettings.fExcludePathMasks := MergeList(aSettings.fExcludePathMasks, aOptions.fExcludePathMasks);
end;

function ResolveMadExceptPatchExe(const aSettingPath: string): string;
var
  lCandidate: string;
  lPathCandidate: string;
  lPathItem: string;
begin
  Result := '';

  if Trim(aSettingPath) <> '' then
  begin
    if SameText(TPath.GetExtension(aSettingPath), '.exe') then
      lCandidate := aSettingPath
    else
      lCandidate := TPath.Combine(aSettingPath, cMadExceptPatchExeName);
    if FileExists(lCandidate) then
      Exit(TPath.GetFullPath(lCandidate));
  end;

  for lPathItem in GetEnvironmentVariable('PATH').Split([';']) do
  begin
    lPathCandidate := Trim(lPathItem);
    if lPathCandidate = '' then
      Continue;
    lCandidate := TPath.Combine(lPathCandidate, cMadExceptPatchExeName);
    if FileExists(lCandidate) then
      Exit(TPath.GetFullPath(lCandidate));
  end;

  for lCandidate in [
    TPath.Combine(GetEnvironmentVariable('ProgramFiles'), 'madCollection\madExcept\Tools\' + cMadExceptPatchExeName),
    TPath.Combine(GetEnvironmentVariable('ProgramFiles'), 'madCollection\madExcept\tools\' + cMadExceptPatchExeName),
    TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'),
      'madCollection\madExcept\Tools\' + cMadExceptPatchExeName),
    TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'),
      'madCollection\madExcept\tools\' + cMadExceptPatchExeName),
    TPath.Combine(GetEnvironmentVariable('ProgramData'), 'madCollection\madExcept\Tools\' + cMadExceptPatchExeName),
    TPath.Combine(GetEnvironmentVariable('ProgramData'), 'madCollection\madExcept\tools\' + cMadExceptPatchExeName)
  ] do
    if (lCandidate <> '') and FileExists(lCandidate) then
      Exit(TPath.GetFullPath(lCandidate));
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

function TryFindMsBuild(const aBdsRoot: string; out aMsBuildPath: string): Boolean;
var
  lCandidate: string;
begin
  aMsBuildPath := '';

  lCandidate := TPath.Combine(aBdsRoot, 'bin\msbuild.exe');
  if FileExists(lCandidate) then
  begin
    aMsBuildPath := lCandidate;
    Exit(True);
  end;

  if TryFindExecutableInPath('MSBuild.exe', lCandidate) then
  begin
    aMsBuildPath := TPath.GetFullPath(lCandidate);
    Exit(True);
  end;

  if TryFindMsBuildFromRegistry(lCandidate) then
  begin
    aMsBuildPath := lCandidate;
    Exit(True);
  end;

  lCandidate := TPath.Combine(GetEnvironmentVariable('WINDIR'), 'Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe');
  if FileExists(lCandidate) then
  begin
    aMsBuildPath := lCandidate;
    Exit(True);
  end;

  lCandidate := TPath.Combine(GetEnvironmentVariable('WINDIR'), 'Microsoft.NET\Framework\v4.0.30319\MSBuild.exe');
  if FileExists(lCandidate) then
  begin
    aMsBuildPath := lCandidate;
    Exit(True);
  end;

  Result := False;
end;

function BuildMsBuildArguments(const aOptions: TAppOptions; const aProjectInfo: TBuildProjectInfo;
  const aExtraProps: string): string;
var
  lOutputDir: string;
begin
  Result := QuoteCmdArg(aProjectInfo.fProjectPath) +
    ' /t:' + aOptions.fBuildTarget +
    ' /p:Config=' + aOptions.fConfig +
    ' /p:Platform=' + aOptions.fPlatform +
    ' /p:DCC_Quiet=true /p:DCC_UseMSBuildExternally=true /p:DCC_UseResponseFile=1 /p:DCC_UseCommandFile=1 /nologo /v:m /fl /m';

  if aOptions.fHasBuildTestOutputDir then
  begin
    lOutputDir := TPath.GetFullPath(aOptions.fBuildTestOutputDir);
    Result := Result +
      ' /p:DCC_ExeOutput=' + QuoteCmdArg(lOutputDir) +
      ' /p:DCC_UnitOutputDirectory=' + QuoteCmdArg(lOutputDir) +
      ' /p:DCC_BplOutput=' + QuoteCmdArg(lOutputDir) +
      ' /p:DCC_DcpOutput=' + QuoteCmdArg(lOutputDir);
  end;

  if Trim(aExtraProps) <> '' then
    Result := Result + ' ' + aExtraProps;
end;

function FileUtcTicks(const aPath: string): Int64;
var
  lFileTime: Int64;
  lHandle: THandle;
  lInfo: TByHandleFileInformation;
begin
  Result := 0;
  if not FileExists(aPath) then
    Exit;

  lHandle := CreateFile(PChar(aPath), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if lHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    if GetFileInformationByHandle(lHandle, lInfo) then
    begin
      lFileTime := lInfo.ftLastWriteTime.dwHighDateTime;
      lFileTime := (lFileTime shl 32) or lInfo.ftLastWriteTime.dwLowDateTime;
      Result := lFileTime;
    end;
  finally
    CloseHandle(lHandle);
  end;
end;

procedure PrintSummary(const aOptions: TAppOptions; const aProjectInfo: TBuildProjectInfo;
  const aSummary: TBuildSummary);
var
  lLine: string;
begin
  if aOptions.fBuildJson then
    Exit;

  if aOptions.fBuildAi then
  begin
    if aSummary.fTimedOut then
      Writeln('FAILED. Build timed out after ' + IntToStr(aOptions.fBuildTimeoutSec) + 's.')
    else if aSummary.fExitCode <> 0 then
      Writeln('FAILED. Errors: ' + IntToStr(aSummary.fErrorCount))
    else if aSummary.fWarningCount > 0 then
      Writeln('SUCCESS. Warnings: ' + IntToStr(aSummary.fWarningCount))
    else if aSummary.fHintCount > 0 then
      Writeln('SUCCESS. Hints: ' + IntToStr(aSummary.fHintCount))
    else
      Writeln('SUCCESS.');

    for lLine in aSummary.fErrors do
      Writeln(lLine);
    if aOptions.fBuildShowWarnings then
      for lLine in aSummary.fWarnings do
        Writeln(lLine);
    if aOptions.fBuildShowHints then
      for lLine in aSummary.fHints do
        Writeln(lLine);
    if aSummary.fOutputStale and (aSummary.fOutputMessage <> '') then
      Writeln('WARNING. ' + aSummary.fOutputMessage);
    Exit;
  end;

  if aSummary.fExitCode <> 0 then
    Writeln('Build FAILED.')
  else
    Writeln('Build succeeded: ' + aProjectInfo.fOutputPath);

  for lLine in aSummary.fErrors do
    Writeln(lLine);
  if aOptions.fBuildShowWarnings then
    for lLine in aSummary.fWarnings do
      Writeln(lLine);
  if aOptions.fBuildShowHints then
    for lLine in aSummary.fHints do
      Writeln(lLine);
  if aSummary.fOutputStale and (aSummary.fOutputMessage <> '') then
    Writeln(aSummary.fOutputMessage);
end;

function CurrentTicks: Int64;
begin
  Result := GetTickCount64;
end;

procedure PrintVerboseStep(const aOptions: TAppOptions; const aStep: string);
var
  lTracePath: string;
begin
  if aOptions.fVerbose then
    Writeln(ErrOutput, '[build] ' + aStep);
  lTracePath := Trim(GetEnvironmentVariable('DAK_TRACE_BUILD'));
  if lTracePath <> '' then
    TFile.AppendAllText(lTracePath, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' ' + aStep + sLineBreak,
      TEncoding.UTF8);
end;

function TBuildProcessRunner.RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
  aTimeoutSec: Integer; out aExitCode: Integer; out aTimedOut: Boolean; out aError: string): Boolean;
var
  lCmdLine: string;
  lErrHandle: THandle;
  lOutHandle: THandle;
  lPi: TProcessInformation;
  lProcExitCode: Cardinal;
  lSa: TSecurityAttributes;
  lSi: TStartupInfo;
  lWaitMs: Cardinal;
  lWaitResult: Cardinal;
begin
  Result := False;
  aExitCode := 1;
  aTimedOut := False;
  aError := '';
  lOutHandle := INVALID_HANDLE_VALUE;
  lErrHandle := INVALID_HANDLE_VALUE;

  FillChar(lSa, SizeOf(lSa), 0);
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;

  lOutHandle := CreateFile(PChar(aStdOutPath), GENERIC_WRITE, FILE_SHARE_READ, @lSa, CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0);
  if lOutHandle = INVALID_HANDLE_VALUE then
  begin
    aError := 'Failed to create stdout log.';
    Exit(False);
  end;

  lErrHandle := CreateFile(PChar(aStdErrPath), GENERIC_WRITE, FILE_SHARE_READ, @lSa, CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0);
  if lErrHandle = INVALID_HANDLE_VALUE then
  begin
    aError := 'Failed to create stderr log.';
    Exit(False);
  end;

  try
    FillChar(lSi, SizeOf(lSi), 0);
    lSi.cb := SizeOf(lSi);
    lSi.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    lSi.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    lSi.hStdOutput := lOutHandle;
    lSi.hStdError := lErrHandle;
    lSi.wShowWindow := SW_HIDE;

    FillChar(lPi, SizeOf(lPi), 0);
    lCmdLine := QuoteCmdArg(aExePath);
    if Trim(aArguments) <> '' then
      lCmdLine := lCmdLine + ' ' + aArguments;
    UniqueString(lCmdLine);

    if not CreateProcess(PChar(aExePath), PChar(lCmdLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      PChar(aWorkDir), lSi, lPi) then
    begin
      aError := SysErrorMessage(GetLastError);
      Exit(False);
    end;
    try
      if aTimeoutSec > 0 then
        lWaitMs := Cardinal(aTimeoutSec * 1000)
      else
        lWaitMs := INFINITE;
      lWaitResult := WaitForSingleObject(lPi.hProcess, lWaitMs);
      if lWaitResult = WAIT_TIMEOUT then
      begin
        TerminateProcess(lPi.hProcess, 124);
        aExitCode := 124;
        aTimedOut := True;
        Exit(True);
      end;
      if lWaitResult <> WAIT_OBJECT_0 then
      begin
        aError := SysErrorMessage(GetLastError);
        Exit(False);
      end;
      if not GetExitCodeProcess(lPi.hProcess, lProcExitCode) then
      begin
        aError := SysErrorMessage(GetLastError);
        Exit(False);
      end;
      aExitCode := Integer(lProcExitCode);
    finally
      CloseHandle(lPi.hThread);
      CloseHandle(lPi.hProcess);
    end;
  finally
    if lErrHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(lErrHandle);
    if lOutHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(lOutHandle);
  end;

  Result := True;
end;

function NormalizeBuildOptions(const aOptions: TAppOptions; out aNormalizedOptions: TAppOptions;
  out aError: string): Boolean;
begin
  Result := False;
  aError := '';
  aNormalizedOptions := aOptions;

  if not TryResolveDprojPath(aOptions.fDprojPath, aNormalizedOptions.fDprojPath, aError) then
    Exit(False);

  if Trim(aNormalizedOptions.fBuildTarget) = '' then
    aNormalizedOptions.fBuildTarget := 'Build';

  if Trim(aNormalizedOptions.fDelphiVersion) = '' then
  begin
    if not LoadDefaultDelphiVersion(aNormalizedOptions.fDprojPath, aNormalizedOptions.fDelphiVersion) and
      (Trim(aNormalizedOptions.fRsVarsPath) = '') then
    begin
      aError := 'Delphi version is required. Pass --delphi <major.minor> or set [Build] DelphiVersion in dak.ini.';
      Exit(False);
    end;
  end;

  aNormalizedOptions.fDelphiVersion := NormalizeDelphiVerForBuild(aNormalizedOptions.fDelphiVersion);
  Result := True;
end;

function TryRunBuild(const aOptions: TAppOptions; out aExitCode: Integer; out aError: string): Boolean;
begin
  Result := TryRunBuild(aOptions, TBuildProcessRunner.Create, aExitCode, aError);
end;

function TryRunBuild(const aOptions: TAppOptions; const aRunner: IBuildProcessRunner;
  out aExitCode: Integer; out aError: string): Boolean;
var
  lBdsRoot: string;
  lDiagnosticsDefaults: TDiagnosticsDefaults;
  lEnvVars: TDictionary<string, string>;
  lErrLog: string;
  lExtraProps: string;
  lJson: string;
  lLookupError: string;
  lMadErrLog: string;
  lMadExceptExe: string;
  lMadExitCode: Integer;
  lNormalizedOptions: TAppOptions;
  lOutLog: string;
  lOutputPostTicks: Int64;
  lOutputPreTicks: Int64;
  lProjectInfo: TBuildProjectInfo;
  lProjectLookup: TProjectSourceLookup;
  lSettings: TBuildSettings;
  lStartTick: Int64;
  lSummary: TBuildSummary;
  lSummaryOptions: TBuildSummaryOptions;
  lTempBase: string;
  lTimeMs: Int64;
  lTimedOut: Boolean;
  lMsBuildPath: string;
begin
  Result := False;
  aExitCode := 1;
  aError := '';
  lEnvVars := nil;
  lExtraProps := '';
  lOutLog := '';
  lErrLog := '';
  lMadErrLog := '';
  lTempBase := '';

  if not NormalizeBuildOptions(aOptions, lNormalizedOptions, aError) then
    Exit(False);

  PrintVerboseStep(lNormalizedOptions, 'load-rsvars');
  if not TryLoadRsVars(lNormalizedOptions.fDelphiVersion, lNormalizedOptions.fRsVarsPath, nil, aError) then
    Exit(False);

  PrintVerboseStep(lNormalizedOptions, 'capture-environment');
  lEnvVars := CaptureEnvironment;
  try
    PrintVerboseStep(lNormalizedOptions, 'load-settings');
    LoadBuildSettings(lNormalizedOptions.fDprojPath, lNormalizedOptions, lEnvVars, lSettings);
    LoadDiagnosticsDefaults(nil, lNormalizedOptions.fDprojPath, lDiagnosticsDefaults);
    ApplyDiagnosticsOverrides(lNormalizedOptions, lDiagnosticsDefaults);

    PrintVerboseStep(lNormalizedOptions, 'resolve-msbuild');
    lBdsRoot := ResolveBdsRoot(lNormalizedOptions.fDelphiVersion, lNormalizedOptions.fRsVarsPath);
    if not TryFindMsBuild(lBdsRoot, lMsBuildPath) then
    begin
      aError := cMsBuildNotFound;
      Exit(False);
    end;

    PrintVerboseStep(lNormalizedOptions, 'environment-props');
    ApplyEnvironmentProjProps(BuildEnvironmentProjPath(lNormalizedOptions.fDelphiVersion, lBdsRoot), lEnvVars, lExtraProps);
    PrintVerboseStep(lNormalizedOptions, 'project-info');
    lProjectInfo := BuildProjectInfo(lNormalizedOptions.fDprojPath, lNormalizedOptions.fConfig,
      lNormalizedOptions.fPlatform, lEnvVars, IfThen(lNormalizedOptions.fHasBuildTestOutputDir,
      lNormalizedOptions.fBuildTestOutputDir, ''));

    lTempBase := TPath.Combine(TPath.GetTempPath,
      'dak-build-' + IntToStr(GetCurrentProcessId) + '-' + IntToStr(GetTickCount));
    lOutLog := lTempBase + '.out.log';
    lErrLog := lTempBase + '.err.log';
    lMadErrLog := lTempBase + '.mad.err.log';

    lOutputPreTicks := FileUtcTicks(lProjectInfo.fOutputPath);
    lStartTick := CurrentTicks;
    PrintVerboseStep(lNormalizedOptions, 'run-msbuild');
    if not aRunner.RunProcess(lMsBuildPath, BuildMsBuildArguments(lNormalizedOptions, lProjectInfo, lExtraProps),
      lProjectInfo.fProjectDir, lOutLog, lErrLog, lNormalizedOptions.fBuildTimeoutSec, aExitCode, lTimedOut, aError) then
      Exit(False);
    lTimeMs := CurrentTicks - lStartTick;

    PrintVerboseStep(lNormalizedOptions, 'parse-logs');
    lSummaryOptions := Default(TBuildSummaryOptions);
    lSummaryOptions.fProjectRoot := DetermineProjectRoot(lProjectInfo.fProjectPath);
    lSummaryOptions.fIgnoreWarnings := lSettings.fIgnoreWarnings;
    lSummaryOptions.fIgnoreHints := lSettings.fIgnoreHints;
    lSummaryOptions.fExcludePathMasks := lSettings.fExcludePathMasks;
    lSummaryOptions.fMaxFindings := lNormalizedOptions.fBuildMaxFindings;
    lSummaryOptions.fIncludeWarnings := lNormalizedOptions.fBuildShowWarnings;
    lSummaryOptions.fIncludeHints := lNormalizedOptions.fBuildShowHints;

    lSummary := ParseBuildLogs(lOutLog, lErrLog, lSummaryOptions);
    if ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, True) or
      ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, False) then
    begin
      lLookupError := '';
      lProjectLookup := Default(TProjectSourceLookup);
      lProjectLookup.fProjectDproj := lNormalizedOptions.fDprojPath;
      lProjectLookup.fProjectDir := lProjectInfo.fProjectDir;
      lProjectLookup.fMainSourcePath := lProjectInfo.fMainSourcePath;
      if TryBuildProjectSourceLookup(lNormalizedOptions.fDprojPath, lNormalizedOptions.fConfig,
        lNormalizedOptions.fPlatform, lNormalizedOptions.fDelphiVersion, lEnvVars, nil, lProjectLookup, lLookupError)
      then
      begin
        if ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, True) then
          EnrichBuildFindingsWithSourceContext(lSummary.fErrors, lProjectLookup, lDiagnosticsDefaults.fSourceContextLines);
        if ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, False) then
        begin
          EnrichBuildFindingsWithSourceContext(lSummary.fWarnings, lProjectLookup,
            lDiagnosticsDefaults.fSourceContextLines);
          EnrichBuildFindingsWithSourceContext(lSummary.fHints, lProjectLookup,
            lDiagnosticsDefaults.fSourceContextLines);
        end;
      end else
      begin
        if ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, True) then
          EnrichBuildFindingsWithSourceContext(lSummary.fErrors, lProjectLookup, lDiagnosticsDefaults.fSourceContextLines);
        if ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, False) then
        begin
          EnrichBuildFindingsWithSourceContext(lSummary.fWarnings, lProjectLookup,
            lDiagnosticsDefaults.fSourceContextLines);
          EnrichBuildFindingsWithSourceContext(lSummary.fHints, lProjectLookup,
            lDiagnosticsDefaults.fSourceContextLines);
        end;
        if lNormalizedOptions.fVerbose and (lLookupError <> '') then
          Writeln('NOTE. Source context search paths unavailable: ' + lLookupError);
      end;
    end;
    lSummary.fExitCode := aExitCode;
    lSummary.fTimedOut := lTimedOut;
    lSummary.fOutputPath := lProjectInfo.fOutputPath;

    if lTimedOut then
      lSummary.fStatus := cStatusTimeout
    else if aExitCode <> 0 then
      lSummary.fStatus := cStatusError
    else
    begin
      lOutputPostTicks := FileUtcTicks(lProjectInfo.fOutputPath);
      if (lOutputPostTicks > 0) and (lOutputPreTicks > 0) and (lOutputPostTicks <= lOutputPreTicks) then
      begin
        lSummary.fOutputStale := True;
        lSummary.fOutputMessage := cOutputLockedMessage;
        lSummary.fStatus := cStatusOutputLocked;
      end else if lSummary.fWarningCount > 0 then
        lSummary.fStatus := cStatusWarnings
      else if lSummary.fHintCount > 0 then
        lSummary.fStatus := cStatusHints
      else
        lSummary.fStatus := cStatusOk;
    end;

    if (aExitCode = 0) and lProjectInfo.fMadExceptRequired then
    begin
      PrintVerboseStep(lNormalizedOptions, 'madexcept-patch');
      lMadExceptExe := ResolveMadExceptPatchExe(lSettings.fMadExceptPath);
      if lMadExceptExe = '' then
      begin
        lSummary.fStatus := cStatusInternalError;
        lSummary.fExitCode := 1;
        aExitCode := 1;
        lSummary.fOutputMessage := cMadExceptPatchRequiredMessage;
      end else if not aRunner.RunProcess(lMadExceptExe,
        QuoteCmdArg(lProjectInfo.fOutputPath) + ' ' + QuoteCmdArg(lProjectInfo.fMesPath), lProjectInfo.fProjectDir,
        lTempBase + '.mad.out.log', lMadErrLog, 0, lMadExitCode, lTimedOut, aError) then
        Exit(False)
      else if lMadExitCode <> 0 then
      begin
        lSummary.fStatus := cStatusInternalError;
        lSummary.fExitCode := 1;
        aExitCode := 1;
        lSummary.fOutputMessage := cMadExceptPatchFailedMessage;
      end;
    end;

    if lNormalizedOptions.fBuildJson then
    begin
      PrintVerboseStep(lNormalizedOptions, 'emit-json');
      lJson := BuildSummaryAsJson(lProjectInfo.fProjectPath, lNormalizedOptions, lSummary,
        lNormalizedOptions.fBuildTarget, lTimeMs);
      Writeln(lJson);
    end else
    begin
      PrintVerboseStep(lNormalizedOptions, 'print-summary');
      PrintSummary(lNormalizedOptions, lProjectInfo, lSummary);
    end;

    Result := True;
  finally
    lEnvVars.Free;
    if (lOutLog <> '') and FileExists(lOutLog) then
      System.SysUtils.DeleteFile(lOutLog);
    if (lErrLog <> '') and FileExists(lErrLog) then
      System.SysUtils.DeleteFile(lErrLog);
    if (lTempBase <> '') and FileExists(lTempBase + '.mad.out.log') then
      System.SysUtils.DeleteFile(lTempBase + '.mad.out.log');
    if (lMadErrLog <> '') and FileExists(lMadErrLog) then
      System.SysUtils.DeleteFile(lMadErrLog);
  end;
end;

end.
