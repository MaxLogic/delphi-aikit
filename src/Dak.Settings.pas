unit Dak.Settings;

interface

uses
  System.Classes, System.Generics.Collections, System.IniFiles, System.IOUtils, System.StrUtils, System.SysUtils,
  maxLogic.RichIniFile, maxLogic.StrUtils,
  Dak.Diagnostics, Dak.MacroExpander, Dak.Messages, Dak.Types;

type
  TAnalysisPolicySettings = record
    fGateOwnership: string;
    fGateMetrics: string;
    fProjectRoots: string;
    fThirdPartyRoots: string;
    fSources: TArray<string>;
    fSha256: string;
  end;

  TDakBuildSettings = record
    fIgnoreWarnings: string;
    fIgnoreHints: string;
    fExcludePathMasks: string;
    fMadExceptPath: string;
    fWebCoreCompilerPath: string;
  end;

  TWorkspaceSettings = record
    fRoot: string;
    fSelector: string;
    fSource: string;
    fVcs: string;
  end;

  TSettingsValueOrigin = record
    fName: string;
    fSources: TArray<string>;
  end;

  TDakSettings = record
    fFixInsight: TFixInsightExtraOptions;
    fFixInsightIgnore: TFixInsightIgnoreDefaults;
    fPascalAnalyzerIgnore: TPascalAnalyzerIgnoreDefaults;
    fReportFilter: TReportFilterDefaults;
    fPascalAnalyzer: TPascalAnalyzerDefaults;
    fBuild: TDakBuildSettings;
    fDiagnosticsDefaults: TDiagnosticsDefaults;
    fDelphiVersion: string;
    fAnalysisPolicy: TAnalysisPolicySettings;
    fWorkspace: TWorkspaceSettings;
    fLoadedPaths: TArray<string>;
    fOrigins: TArray<TSettingsValueOrigin>;
    fIgnoreUnknownMacros: string;
    fIgnoreMissingPaths: string;
    fError: string;
  end;

function BuildSettingsPaths(const aDprojPath: string): TArray<string>;
function FindNamedRepoRoot(const aStartDir, aMarker: string): string;
function LoadDakSettings(aDiagnostics: TDiagnostics; const aDprojPath: string;
  const aEnvVars: TDictionary<string, string>; out aSettings: TDakSettings): Boolean; overload;
function LoadDakSettings(aDiagnostics: TDiagnostics; const aDprojPath: string;
  const aEnvVars: TDictionary<string, string>; const aWorkspaceSelector: string;
  out aSettings: TDakSettings): Boolean; overload;
function LoadSettings(aDiagnostics: TDiagnostics; const aDprojPath: string;
  out aFixInsight: TFixInsightExtraOptions; out aFixInsightIgnore: TFixInsightIgnoreDefaults;
  out aReportFilter: TReportFilterDefaults; out aPascalAnalyzer: TPascalAnalyzerDefaults): Boolean; overload;
function LoadSettings(aDiagnostics: TDiagnostics; out aFixInsight: TFixInsightExtraOptions;
  out aFixInsightIgnore: TFixInsightIgnoreDefaults; out aReportFilter: TReportFilterDefaults;
  out aPascalAnalyzer: TPascalAnalyzerDefaults): Boolean; overload;
function LoadDefaultDelphiVersion(const aDprojPath: string; out aDelphiVersion: string): Boolean;
function LoadDiagnosticsDefaults(aDiagnostics: TDiagnostics; const aDprojPath: string;
  out aDiagnosticsDefaults: TDiagnosticsDefaults): Boolean;
procedure LoadBuildSettings(const aDprojPath: string; const aOverrides: TAppOptions;
  const aEnvVars: TDictionary<string, string>; out aSettings: TDakBuildSettings);
procedure ApplySettingsOverrides(const aOverrides: TAppOptions; var aFixInsight: TFixInsightExtraOptions;
  var aFixInsightIgnore: TFixInsightIgnoreDefaults; var aReportFilter: TReportFilterDefaults;
  var aPascalAnalyzer: TPascalAnalyzerDefaults);
procedure ApplyAnalysisSettingsOverrides(const aOptions: TAppOptions; var aSettings: TDakSettings);
procedure ApplyPascalAnalyzerEnvironment(var aPascalAnalyzer: TPascalAnalyzerDefaults);
procedure ApplyPascalAnalyzerIgnoreOverride(const aOverrides: TAppOptions;
  var aPascalAnalyzerIgnore: TPascalAnalyzerIgnoreDefaults);
procedure ApplyBuildSettingsOverrides(const aOverrides: TAppOptions; var aSettings: TDakBuildSettings);
procedure ApplyDiagnosticsOverrides(const aOverrides: TAppOptions; var aDiagnosticsDefaults: TDiagnosticsDefaults);

implementation

uses
  System.Hash;

const
  SSettingsFileName = 'dak.ini';
  SFixInsightSection = 'FixInsightCL';
  SFixInsightIgnoreSection = 'FixInsightIgnore';
  SPascalAnalyzerIgnoreSection = 'PascalAnalyzerIgnore';
  SPalIgnoreRulesEnvironment = 'DAK_PAL_IGNORE_RULES';
  SPalIgnoreRulesOriginEnvironment = 'DAK_PAL_IGNORE_RULES_ORIGIN';
  SReportFilterSection = 'ReportFilter';
  SPascalAnalyzerSection = 'PascalAnalyzer';
  SBuildSection = 'Build';
  SBuildIgnoreSection = 'BuildIgnore';
  SMadExceptSection = 'MadExcept';
  SDiagnosticsSection = 'Diagnostics';
  SWebCoreSection = 'WebCore';
  SAnalysisPolicySection = 'AnalysisPolicy';
  SWorkspaceSection = 'Workspace';

function GetExeSettingsPath: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), SSettingsFileName);
end;

function NormalizeDir(const aDir: string): string;
var
  lFull: string;
  lRoot: string;
begin
  if aDir = '' then
    Exit('');
  lFull := TPath.GetFullPath(aDir);
  lRoot := TPath.GetPathRoot(lFull);
  if (lRoot <> '') and SameText(lFull, lRoot) then
    Result := lRoot
  else
    Result := ExcludeTrailingPathDelimiter(lFull);
end;

function HasRepoMarker(const aDir: string): Boolean;
begin
  Result := DirectoryExists(TPath.Combine(aDir, '.git')) or
    FileExists(TPath.Combine(aDir, '.git')) or
    DirectoryExists(TPath.Combine(aDir, '.svn'));
end;

function HasNamedRepoMarker(const aDir, aMarker: string): Boolean;
var
  lPath: string;
begin
  lPath := TPath.Combine(aDir, aMarker);
  if SameText(aMarker, '.git') then
    Result := DirectoryExists(lPath) or FileExists(lPath)
  else
    Result := DirectoryExists(lPath);
end;

function FindRepoRoot(const aStartDir: string): string;
var
  lDir: string;
  lParent: string;
begin
  lDir := NormalizeDir(aStartDir);
  if lDir = '' then
    Exit('');
  while True do
  begin
    if HasRepoMarker(lDir) then
      Exit(lDir);
    lParent := NormalizeDir(ExtractFileDir(lDir));
    if (lParent = '') or SameText(lParent, lDir) then
      Break;
    lDir := lParent;
  end;
  Result := '';
end;

function FindNamedRepoRoot(const aStartDir, aMarker: string): string;
var
  lDir: string;
  lParent: string;
begin
  lDir := NormalizeDir(aStartDir);
  while lDir <> '' do
  begin
    if HasNamedRepoMarker(lDir, aMarker) then
      Exit(lDir);
    lParent := NormalizeDir(ExtractFileDir(lDir));
    if (lParent = '') or SameText(lParent, lDir) then
      Break;
    lDir := lParent;
  end;
  Result := '';
end;

function IsSameOrChildDir(const aDir, aRoot: string): Boolean;
var
  lDir: string;
  lRoot: string;
begin
  lDir := IncludeTrailingPathDelimiter(NormalizeDir(aDir));
  lRoot := IncludeTrailingPathDelimiter(NormalizeDir(aRoot));
  Result := (lDir <> '') and (lRoot <> '') and StartsText(lRoot, lDir);
end;

function OpenSettingsIni(const aPath: string;
  aCaseSensitivity: TCaseSensitivity = TCaseSensitivity.csCaseSensitive): TCustomIniFile;
var
  lOptions: TRichIniOptions;
  lIni: TRichIniFile;
begin
  lOptions := DefaultRichIniOptions;
  lOptions.CaseSensitivity := aCaseSensitivity;
  lIni := TRichIniFile.Create(aPath, lOptions);
  lIni.LoadFromFile(aPath);
  Result := lIni;
end;

function TryReadWorkspaceSelector(const aIniPath: string; out aSelector: string): Boolean;
var
  lIni: TCustomIniFile;
begin
  aSelector := '';
  if not FileExists(aIniPath) then
    Exit(False);
  // Share decoding with typed settings while preserving case-insensitive selector keys.
  lIni := OpenSettingsIni(aIniPath, TCaseSensitivity.csCaseInsensitive);
  try
    Result := lIni.ValueExists(SWorkspaceSection, 'Root');
    if Result then
      aSelector := Trim(lIni.ReadString(SWorkspaceSection, 'Root', ''));
  finally
    lIni.Free;
  end;
end;

function TryFindWorkspaceSelector(const aStartDir: string; out aSelector, aSourcePath: string): Boolean;
var
  lDir: string;
  lIniPath: string;
  lParent: string;
begin
  aSelector := '';
  aSourcePath := '';
  lDir := NormalizeDir(aStartDir);
  while lDir <> '' do
  begin
    lIniPath := TPath.Combine(lDir, SSettingsFileName);
    if TryReadWorkspaceSelector(lIniPath, aSelector) then
    begin
      aSourcePath := lIniPath;
      Exit(True);
    end;
    lParent := NormalizeDir(ExtractFileDir(lDir));
    if (lParent = '') or SameText(lParent, lDir) then
      Break;
    lDir := lParent;
  end;
  aSourcePath := GetExeSettingsPath;
  Result := TryReadWorkspaceSelector(aSourcePath, aSelector);
  if not Result then
    aSourcePath := '';
end;

function GetWorkspaceVcs(const aRoot: string): string;
begin
  if HasNamedRepoMarker(aRoot, '.git') then
    Result := 'git'
  else if HasNamedRepoMarker(aRoot, '.svn') then
    Result := 'svn'
  else
    Result := 'none';
end;

function TryResolveWorkspaceRoot(const aStartDir, aWorkspaceSelector: string;
  out aWorkspace: TWorkspaceSettings; out aError: string): Boolean;
var
  lSelector: string;
  lSelectorBaseDir: string;
  lSelectorPath: string;
begin
  aError := '';
  aWorkspace := Default(TWorkspaceSettings);
  if aWorkspaceSelector <> '' then
  begin
    lSelector := Trim(aWorkspaceSelector);
    lSelectorBaseDir := GetCurrentDir;
    lSelectorPath := 'command_line';
  end else if not TryFindWorkspaceSelector(aStartDir, lSelector, lSelectorPath) then
  begin
    lSelector := 'auto';
    lSelectorBaseDir := '';
    lSelectorPath := 'default';
  end else begin
    lSelectorPath := TPath.GetFullPath(lSelectorPath);
    lSelectorBaseDir := ExtractFileDir(lSelectorPath);
  end;
  if lSelector = '' then
  begin
    aError := Format('Workspace Root in "%s" is empty.', [lSelectorPath]);
    Exit(False);
  end;
  if SameText(lSelector, 'git') then
  begin
    aWorkspace.fRoot := FindNamedRepoRoot(aStartDir, '.git');
    if aWorkspace.fRoot = '' then
    begin
      aError := Format('Workspace Root=git requires a .git marker above "%s".', [aStartDir]);
      Exit(False);
    end;
  end else if SameText(lSelector, 'svn') then
  begin
    aWorkspace.fRoot := FindNamedRepoRoot(aStartDir, '.svn');
    if aWorkspace.fRoot = '' then
    begin
      aError := Format('Workspace Root=svn requires a .svn marker above "%s".', [aStartDir]);
      Exit(False);
    end;
  end else if SameText(lSelector, 'project') then
    aWorkspace.fRoot := NormalizeDir(aStartDir)
  else if SameText(lSelector, 'auto') then
  begin
    aWorkspace.fRoot := FindRepoRoot(aStartDir);
    if aWorkspace.fRoot = '' then
      aWorkspace.fRoot := NormalizeDir(aStartDir);
  end else begin
    if TPath.IsPathRooted(lSelector) then
      aWorkspace.fRoot := NormalizeDir(lSelector)
    else
      aWorkspace.fRoot := NormalizeDir(TPath.Combine(lSelectorBaseDir, lSelector));
    if not DirectoryExists(aWorkspace.fRoot) then
    begin
      aError := Format('Workspace root "%s" from "%s" does not exist.',
        [aWorkspace.fRoot, lSelectorPath]);
      Exit(False);
    end;
    if not IsSameOrChildDir(aStartDir, aWorkspace.fRoot) then
    begin
      aError := Format('Workspace root "%s" does not contain project directory "%s".',
        [aWorkspace.fRoot, aStartDir]);
      Exit(False);
    end;
  end;
  if MatchText(lSelector, ['auto', 'git', 'svn', 'project']) then
    aWorkspace.fSelector := LowerCase(lSelector)
  else
    aWorkspace.fSelector := lSelector;
  aWorkspace.fSource := lSelectorPath;
  if SameText(lSelector, 'git') then
    aWorkspace.fVcs := 'git'
  else if SameText(lSelector, 'svn') then
    aWorkspace.fVcs := 'svn'
  else
    aWorkspace.fVcs := GetWorkspaceVcs(aWorkspace.fRoot);
  Result := True;
end;

function GetProjectDirChain(const aRepoRoot, aDprojDir: string): TArray<string>;
var
  lDirs: TList<string>;
  lDir: string;
  lParent: string;
  i: Integer;
begin
  Result := nil;
  if (aRepoRoot = '') or (aDprojDir = '') then
    Exit;
  lDirs := TList<string>.Create;
  try
    lDir := NormalizeDir(aDprojDir);
    while lDir <> '' do
    begin
      lDirs.Add(lDir);
      if SameText(lDir, aRepoRoot) then
        Break;
      lParent := NormalizeDir(ExtractFileDir(lDir));
      if (lParent = '') or SameText(lParent, lDir) then
        Break;
      lDir := lParent;
    end;

    SetLength(Result, lDirs.Count);
    for i := 0 to lDirs.Count - 1 do
      Result[i] := lDirs[lDirs.Count - 1 - i];
  finally
    lDirs.Free;
  end;
end;

function TryBuildSettingsPaths(const aDprojPath, aWorkspaceSelector: string; out aPaths: TArray<string>;
  out aWorkspace: TWorkspaceSettings; out aError: string): Boolean;
var
  lPaths: TList<string>;
  lSeen: THashSet<string>;
  lDprojDir: string;
  lDirs: TArray<string>;
  lDir: string;

  procedure AddPath(const aPath: string);
  var
    lFull: string;
  begin
    if aPath = '' then
      Exit;
    lFull := TPath.GetFullPath(aPath);
    if lSeen.Add(lFull) then
      lPaths.Add(lFull);
  end;
begin
  aError := '';
  aPaths := nil;
  aWorkspace := Default(TWorkspaceSettings);
  lPaths := TList<string>.Create;
  lSeen := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    if aDprojPath = '' then
      AddPath(GetExeSettingsPath)
    else
    begin
      lDprojDir := NormalizeDir(ExtractFileDir(TPath.GetFullPath(aDprojPath)));
      if lDprojDir <> '' then
      begin
        if not TryResolveWorkspaceRoot(lDprojDir, aWorkspaceSelector, aWorkspace, aError) then
          Exit(False);
        if SameText(aWorkspace.fSource, 'default') then
          AddPath(GetExeSettingsPath);
        lDirs := GetProjectDirChain(aWorkspace.fRoot, lDprojDir);
        for lDir in lDirs do
          AddPath(TPath.Combine(lDir, SSettingsFileName));
      end;
    end;
    aPaths := lPaths.ToArray;
    Result := True;
  finally
    lSeen.Free;
    lPaths.Free;
  end;
end;

function BuildSettingsPaths(const aDprojPath: string): TArray<string>;
var
  lError: string;
  lWorkspace: TWorkspaceSettings;
begin
  if not TryBuildSettingsPaths(aDprojPath, '', Result, lWorkspace, lError) then
    Result := nil;
end;

function TryParseBoolText(const aValue: string; out aResult: Boolean): Boolean;
begin
  if aValue = '' then
    Exit(False);
  if SameText(aValue, 'true') or SameText(aValue, '1') or SameText(aValue, 'yes') then
    aResult := True
  else if SameText(aValue, 'false') or SameText(aValue, '0') or SameText(aValue, 'no') then
    aResult := False
  else
    Exit(False);
  Result := True;
end;

function TryParseSourceContextModeText(const aValue: string; out aMode: TSourceContextMode): Boolean;
begin
  if SameText(aValue, 'auto') then
    aMode := TSourceContextMode.scmAuto
  else if SameText(aValue, 'off') then
    aMode := TSourceContextMode.scmOff
  else if SameText(aValue, 'on') then
    aMode := TSourceContextMode.scmOn
  else
    Exit(False);
  Result := True;
end;

procedure RecordSettingOrigin(var aOrigins: TArray<TSettingsValueOrigin>;
  const aName, aSource: string; aMerge: Boolean = False);
var
  i: Integer;
  lIndex: Integer;
  lSource: string;
begin
  lIndex := -1;
  for i := 0 to High(aOrigins) do
    if SameText(aOrigins[i].fName, aName) then
    begin
      lIndex := i;
      Break;
    end;
  // Detach managed arrays before mutating a copied settings record.
  aOrigins := Copy(aOrigins);
  if lIndex < 0 then
  begin
    lIndex := Length(aOrigins);
    SetLength(aOrigins, lIndex + 1);
    aOrigins[lIndex].fName := aName;
  end;
  if not aMerge then
    aOrigins[lIndex].fSources := nil;
  if aSource = '' then
    Exit;
  for lSource in aOrigins[lIndex].fSources do
    if SameText(lSource, aSource) then
      Exit;
  aOrigins[lIndex].fSources := Copy(aOrigins[lIndex].fSources);
  SetLength(aOrigins[lIndex].fSources, Length(aOrigins[lIndex].fSources) + 1);
  aOrigins[lIndex].fSources[High(aOrigins[lIndex].fSources)] := aSource;
end;

procedure ReadBoolOption(const aIni: TCustomIniFile; const aKey: string; var aTarget: Boolean;
  aDiagnostics: TDiagnostics; const aIniPath: string; var aOrigins: TArray<TSettingsValueOrigin>);
var
  lValue: string;
  lParsed: Boolean;
begin
  lValue := Trim(aIni.ReadString(SFixInsightSection, aKey, ''));
  if lValue = '' then
    Exit;
  if TryParseBoolText(lValue, lParsed) then
  begin
    aTarget := lParsed;
    RecordSettingOrigin(aOrigins, SFixInsightSection + '.' + aKey, aIniPath);
  end else if aDiagnostics <> nil then
    aDiagnostics.AddWarning(Format(SSettingsInvalidBool, [aKey, lValue]));
end;

procedure ReadPositiveIntegerOption(const aIni: TCustomIniFile; const aSection: string; const aKey: string;
  var aTarget: Integer; aDiagnostics: TDiagnostics; const aIniPath: string;
  var aOrigins: TArray<TSettingsValueOrigin>);
var
  lParsed: Integer;
  lValue: string;
begin
  lValue := Trim(aIni.ReadString(aSection, aKey, ''));
  if lValue = '' then
    Exit;

  lParsed := StrToIntDef(lValue, -1);
  if lParsed >= 1 then
  begin
    aTarget := lParsed;
    RecordSettingOrigin(aOrigins, aSection + '.' + aKey, aIniPath);
  end else if aDiagnostics <> nil then
    aDiagnostics.AddWarning(Format(SSettingsInvalidInteger, [aSection, aKey, lValue]));
end;

function SplitList(const aValue: string): TArray<string>;
var
  lPart: string;
  lItem: string;
  lRaw: TArray<string>;
  lList: TList<string>;
begin
  Result := nil;
  if aValue = '' then
    Exit;
  lRaw := aValue.Split([';']);
  lList := TList<string>.Create;
  try
    for lPart in lRaw do
    begin
      lItem := Trim(lPart);
      if lItem <> '' then
        lList.Add(lItem);
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function MergeList(const aFirst: string; const aSecond: string): string;
var
  lSet: THashSet<string>;
  lItems: TList<string>;

  procedure AddFrom(const aValue: string);
  var
    lItem: string;
  begin
    for lItem in SplitList(aValue) do
      if lSet.Add(lItem) then
        lItems.Add(lItem);
  end;
begin
  Result := '';
  lSet := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    lItems := TList<string>.Create;
    try
      AddFrom(aFirst);
      AddFrom(aSecond);
      Result := String.Join(';', lItems.ToArray);
    finally
      lItems.Free;
    end;
  finally
    lSet.Free;
  end;
end;

function IsAnalysisPolicyKey(const aKey: string): Boolean;
begin
  Result := SameText(aKey, 'GateOwnership') or SameText(aKey, 'GateMetrics') or
    SameText(aKey, 'ProjectRoots') or SameText(aKey, 'ThirdPartyRoots');
end;

function TryNormalizeGateOwnership(const aValue: string; out aNormalized: string): Boolean;
var
  lItem: string;
  lName: string;
  lSeen: THashSet<string>;
begin
  aNormalized := '';
  lSeen := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for lItem in SplitList(aValue) do
    begin
      lName := LowerCase(lItem);
      if (lName <> 'project') and (lName <> 'repository') and (lName <> 'third_party') then
        Exit(False);
      lSeen.Add(lName);
    end;
    if lSeen.Count = 0 then
      Exit(False);
    if lSeen.Contains('project') then
      aNormalized := 'project';
    if lSeen.Contains('repository') then
      aNormalized := MergeList(aNormalized, 'repository');
    if lSeen.Contains('third_party') then
      aNormalized := MergeList(aNormalized, 'third_party');
    Result := True;
  finally
    lSeen.Free;
  end;
end;

function TryNormalizeGateMetrics(const aValue: string; out aNormalized: string): Boolean;
var
  ch: Char;
  i: Integer;
  lItem: string;
begin
  aNormalized := '';
  if Trim(aValue) = '' then
    Exit(True);
  for lItem in SplitList(aValue) do
  begin
    if (Length(lItem) <= 4) or not SameText(Copy(lItem, 1, 4), 'PAL.') or
      (lItem[Length(lItem)] = '.') or (Pos('..', lItem) > 0) then
      Exit(False);
    for i := 5 to Length(lItem) do
    begin
      ch := lItem[i];
      if not CharInSet(ch, ['A'..'Z', 'a'..'z', '0'..'9', '-', '.']) then
        Exit(False);
    end;
    aNormalized := MergeList(aNormalized, lItem);
  end;
  Result := aNormalized <> '';
end;

function ExpandSettingPath(const aValue, aIniPath: string;
  const aEnvVars: TDictionary<string, string>): string; forward;

function TryNormalizePolicyRoots(const aValue, aIniPath: string;
  const aEnvVars: TDictionary<string, string>; out aNormalized: string; out aError: string): Boolean;
var
  lItem: string;
  lItems: TList<string>;
  lPath: string;
  lSeen: THashSet<string>;
begin
  aNormalized := '';
  aError := '';
  lItems := TList<string>.Create;
  lSeen := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    try
      for lItem in SplitList(aValue) do
      begin
        lPath := NormalizeDir(ExpandSettingPath(lItem, aIniPath, aEnvVars));
        if (lPath = '') or (Pos('$(', lPath) > 0) then
        begin
          aError := 'path is empty or contains an unresolved macro';
          Exit(False);
        end;
        if lSeen.Add(lPath) then
          lItems.Add(lPath);
      end;
    except
      on E: Exception do
      begin
        aError := E.Message;
        Exit(False);
      end;
    end;
    aNormalized := String.Join(';', lItems.ToArray);
    Result := True;
  finally
    lSeen.Free;
    lItems.Free;
  end;
end;

procedure AppendPath(var aPaths: TArray<string>; const aPath: string);
var
  lLength: Integer;
begin
  lLength := Length(aPaths);
  SetLength(aPaths, lLength + 1);
  aPaths[lLength] := aPath;
end;

procedure AppendUniquePath(var aPaths: TArray<string>; const aPath: string);
var
  lExisting: string;
begin
  for lExisting in aPaths do
    if SameText(lExisting, aPath) then
      Exit;
  AppendPath(aPaths, aPath);
end;

function ApplyAnalysisPolicy(const aIni: TCustomIniFile; const aIniPath: string;
  const aEnvVars: TDictionary<string, string>; var aSettings: TDakSettings): Boolean;
var
  lError: string;
  lKey: string;
  lKeys: TStringList;
  lNormalized: string;
  lValue: string;
begin
  Result := False;
  lKeys := TStringList.Create;
  try
    aIni.ReadSection(SAnalysisPolicySection, lKeys);
    for lKey in lKeys do
      if not IsAnalysisPolicyKey(lKey) then
      begin
        aSettings.fError := Format('Unknown dak.ini [%s] key in "%s": %s',
          [SAnalysisPolicySection, aIniPath, lKey]);
        Exit(False);
      end;

    if lKeys.IndexOf('GateOwnership') >= 0 then
    begin
      lValue := Trim(aIni.ReadString(SAnalysisPolicySection, 'GateOwnership', ''));
      if not TryNormalizeGateOwnership(lValue, lNormalized) then
      begin
        aSettings.fError := Format('Invalid dak.ini [%s] GateOwnership in "%s": %s',
          [SAnalysisPolicySection, aIniPath, lValue]);
        Exit(False);
      end;
      aSettings.fAnalysisPolicy.fGateOwnership := lNormalized;
      if lNormalized <> '' then
        RecordSettingOrigin(aSettings.fOrigins, 'AnalysisPolicy.GateOwnership', aIniPath)
      else
        RecordSettingOrigin(aSettings.fOrigins, 'AnalysisPolicy.GateOwnership', '');
    end;

    if lKeys.IndexOf('GateMetrics') >= 0 then
    begin
      lValue := Trim(aIni.ReadString(SAnalysisPolicySection, 'GateMetrics', ''));
      if not TryNormalizeGateMetrics(lValue, lNormalized) then
      begin
        aSettings.fError := Format('Invalid dak.ini [%s] GateMetrics in "%s": %s',
          [SAnalysisPolicySection, aIniPath, lValue]);
        Exit(False);
      end;
      aSettings.fAnalysisPolicy.fGateMetrics := lNormalized;
      RecordSettingOrigin(aSettings.fOrigins, 'AnalysisPolicy.GateMetrics', aIniPath);
    end;

    if lKeys.IndexOf('ProjectRoots') >= 0 then
    begin
      lValue := Trim(aIni.ReadString(SAnalysisPolicySection, 'ProjectRoots', ''));
      if not TryNormalizePolicyRoots(lValue, aIniPath, aEnvVars, lNormalized, lError) then
      begin
        aSettings.fError := Format('Invalid dak.ini [%s] ProjectRoots in "%s": %s',
          [SAnalysisPolicySection, aIniPath, lValue]);
        if lError <> '' then
          aSettings.fError := aSettings.fError + ': ' + lError;
        Exit(False);
      end;
      aSettings.fAnalysisPolicy.fProjectRoots := lNormalized;
      RecordSettingOrigin(aSettings.fOrigins, 'AnalysisPolicy.ProjectRoots', aIniPath);
    end;

    if lKeys.IndexOf('ThirdPartyRoots') >= 0 then
    begin
      lValue := Trim(aIni.ReadString(SAnalysisPolicySection, 'ThirdPartyRoots', ''));
      if not TryNormalizePolicyRoots(lValue, aIniPath, aEnvVars, lNormalized, lError) then
      begin
        aSettings.fError := Format('Invalid dak.ini [%s] ThirdPartyRoots in "%s": %s',
          [SAnalysisPolicySection, aIniPath, lValue]);
        if lError <> '' then
          aSettings.fError := aSettings.fError + ': ' + lError;
        Exit(False);
      end;
      aSettings.fAnalysisPolicy.fThirdPartyRoots := lNormalized;
      RecordSettingOrigin(aSettings.fOrigins, 'AnalysisPolicy.ThirdPartyRoots', aIniPath);
    end;

    if lKeys.Count > 0 then
      AppendUniquePath(aSettings.fAnalysisPolicy.fSources, aIniPath);
    Result := True;
  finally
    lKeys.Free;
  end;
end;

function ExpandSettingPath(const aValue, aIniPath: string; const aEnvVars: TDictionary<string, string>): string;
var
  lPair: TPair<string, string>;
  lEnv: TDictionary<string, string>;
  lProps: TDictionary<string, string>;
begin
  Result := Trim(aValue);
  if Result = '' then
    Exit('');

  lProps := TDictionary<string, string>.Create;
  try
    lEnv := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
    try
      if aEnvVars <> nil then
        for lPair in aEnvVars do
          lEnv.AddOrSetValue(lPair.Key, lPair.Value);
      Result := TMacroExpander.Expand(Result, lProps, lEnv, nil, False);
    finally
      lEnv.Free;
    end;
  finally
    lProps.Free;
  end;

  if (Result <> '') and (not TPath.IsPathRooted(Result)) then
    Result := TPath.GetFullPath(TPath.Combine(ExtractFileDir(aIniPath), Result));
end;

procedure ApplyIniSettings(const aIni: TCustomIniFile; const aIniPath: string;
  const aEnvVars: TDictionary<string, string>; var aSettings: TDakSettings; aDiagnostics: TDiagnostics);
var
  lLines: Integer;
  lMode: TSourceContextMode;
  lValue: string;
begin
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Path', ''));
  if lValue <> '' then
  begin
    aSettings.fFixInsight.fExePath := lValue;
    RecordSettingOrigin(aSettings.fOrigins, SFixInsightSection + '.Path', aIniPath);
  end;
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Output', ''));
  if lValue <> '' then
  begin
    aSettings.fFixInsight.fOutput := lValue;
    RecordSettingOrigin(aSettings.fOrigins, SFixInsightSection + '.Output', aIniPath);
  end;
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Ignore', ''));
  if lValue <> '' then
  begin
    aSettings.fFixInsight.fIgnore := MergeList(aSettings.fFixInsight.fIgnore, lValue);
    RecordSettingOrigin(aSettings.fOrigins, SFixInsightSection + '.Ignore', aIniPath, True);
  end;
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Settings', ''));
  if lValue <> '' then
  begin
    aSettings.fFixInsight.fSettings := lValue;
    RecordSettingOrigin(aSettings.fOrigins, SFixInsightSection + '.Settings', aIniPath);
  end;
  ReadBoolOption(aIni, 'ExcludeFlexCel', aSettings.fFixInsight.fExcludeFlexCel, aDiagnostics,
    aIniPath, aSettings.fOrigins);
  ReadBoolOption(aIni, 'Silent', aSettings.fFixInsight.fSilent, aDiagnostics, aIniPath, aSettings.fOrigins);
  ReadBoolOption(aIni, 'Xml', aSettings.fFixInsight.fXml, aDiagnostics, aIniPath, aSettings.fOrigins);
  ReadBoolOption(aIni, 'Csv', aSettings.fFixInsight.fCsv, aDiagnostics, aIniPath, aSettings.fOrigins);
  ReadPositiveIntegerOption(aIni, SFixInsightSection, 'TimeoutSec', aSettings.fFixInsight.fTimeoutSec,
    aDiagnostics, aIniPath, aSettings.fOrigins);

  lValue := Trim(aIni.ReadString(SFixInsightIgnoreSection, 'Warnings', ''));
  if lValue <> '' then
  begin
    aSettings.fFixInsightIgnore.fWarnings := MergeList(aSettings.fFixInsightIgnore.fWarnings, lValue);
    RecordSettingOrigin(aSettings.fOrigins, SFixInsightIgnoreSection + '.Warnings', aIniPath, True);
  end;

  lValue := Trim(aIni.ReadString(SPascalAnalyzerIgnoreSection, 'Rules', ''));
  if lValue <> '' then
  begin
    RecordSettingOrigin(aSettings.fOrigins, 'PascalAnalyzerIgnore.Rules', aIniPath, True);
    aSettings.fPascalAnalyzerIgnore.fRules := MergeList(
      aSettings.fPascalAnalyzerIgnore.fRules, lValue);
    aSettings.fPascalAnalyzerIgnore.fSources := MergeList(
      aSettings.fPascalAnalyzerIgnore.fSources, aIniPath);
    AppendUniquePath(aSettings.fAnalysisPolicy.fSources, aIniPath);
  end;

  lValue := Trim(aIni.ReadString(SReportFilterSection, 'ExcludePathMasks', ''));
  if lValue <> '' then
  begin
    RecordSettingOrigin(aSettings.fOrigins, 'ReportFilter.ExcludePathMasks', aIniPath, True);
    aSettings.fReportFilter.fExcludePathMasks := MergeList(aSettings.fReportFilter.fExcludePathMasks, lValue);
    aSettings.fBuild.fExcludePathMasks := MergeList(aSettings.fBuild.fExcludePathMasks, lValue);
  end;

  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'Path', ''));
  if lValue <> '' then
  begin
    aSettings.fPascalAnalyzer.fPath := lValue;
    RecordSettingOrigin(aSettings.fOrigins, SPascalAnalyzerSection + '.Path', aIniPath);
  end;
  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'Output', ''));
  if lValue <> '' then
  begin
    aSettings.fPascalAnalyzer.fOutput := lValue;
    RecordSettingOrigin(aSettings.fOrigins, SPascalAnalyzerSection + '.Output', aIniPath);
  end;
  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'Args', ''));
  if lValue <> '' then
  begin
    aSettings.fPascalAnalyzer.fArgs := lValue;
    RecordSettingOrigin(aSettings.fOrigins, 'PascalAnalyzer.Args', aIniPath);
    aSettings.fPascalAnalyzer.fArgsSource := '[PascalAnalyzer] Args in ' + aIniPath;
  end;
  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'ExcludeSearchFolders', ''));
  if lValue <> '' then
  begin
    aSettings.fPascalAnalyzer.fExcludeSearchFolders := lValue;
    RecordSettingOrigin(aSettings.fOrigins, SPascalAnalyzerSection + '.ExcludeSearchFolders', aIniPath);
  end;
  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'ExcludeFiles', ''));
  if lValue <> '' then
  begin
    aSettings.fPascalAnalyzer.fExcludeFiles := lValue;
    RecordSettingOrigin(aSettings.fOrigins, SPascalAnalyzerSection + '.ExcludeFiles', aIniPath);
  end;
  ReadPositiveIntegerOption(aIni, SPascalAnalyzerSection, 'TimeoutSec', aSettings.fPascalAnalyzer.fTimeoutSec,
    aDiagnostics, aIniPath, aSettings.fOrigins);

  lValue := Trim(aIni.ReadString(SBuildSection, 'DelphiVersion', ''));
  if lValue <> '' then
  begin
    aSettings.fDelphiVersion := lValue;
    RecordSettingOrigin(aSettings.fOrigins, SBuildSection + '.DelphiVersion', aIniPath);
  end;

  lValue := Trim(aIni.ReadString(SBuildIgnoreSection, 'Warnings', ''));
  if lValue <> '' then
  begin
    aSettings.fBuild.fIgnoreWarnings := MergeList(aSettings.fBuild.fIgnoreWarnings, lValue);
    RecordSettingOrigin(aSettings.fOrigins, SBuildIgnoreSection + '.Warnings', aIniPath, True);
  end;

  lValue := Trim(aIni.ReadString(SBuildIgnoreSection, 'Hints', ''));
  if lValue <> '' then
  begin
    aSettings.fBuild.fIgnoreHints := MergeList(aSettings.fBuild.fIgnoreHints, lValue);
    RecordSettingOrigin(aSettings.fOrigins, SBuildIgnoreSection + '.Hints', aIniPath, True);
  end;

  lValue := Trim(aIni.ReadString(SMadExceptSection, 'Path', ''));
  if lValue <> '' then
  begin
    aSettings.fBuild.fMadExceptPath := ExpandSettingPath(lValue, aIniPath, aEnvVars);
    RecordSettingOrigin(aSettings.fOrigins, SMadExceptSection + '.Path', aIniPath);
  end;

  lValue := Trim(aIni.ReadString(SWebCoreSection, 'CompilerPath', ''));
  if lValue <> '' then
  begin
    aSettings.fBuild.fWebCoreCompilerPath := ExpandSettingPath(lValue, aIniPath, aEnvVars);
    RecordSettingOrigin(aSettings.fOrigins, SWebCoreSection + '.CompilerPath', aIniPath);
  end;

  lValue := Trim(aIni.ReadString(SDiagnosticsSection, 'SourceContext', ''));
  if lValue <> '' then
  begin
    if TryParseSourceContextModeText(lValue, lMode) then
    begin
      aSettings.fDiagnosticsDefaults.fSourceContextMode := lMode;
      RecordSettingOrigin(aSettings.fOrigins, 'Diagnostics.SourceContext', aIniPath);
    end else if aDiagnostics <> nil then
      aDiagnostics.AddWarning('Invalid dak.ini SourceContext value: ' + lValue);
  end;

  lValue := Trim(aIni.ReadString(SDiagnosticsSection, 'SourceContextLines', ''));
  if lValue <> '' then
  begin
    lLines := StrToIntDef(lValue, -1);
    if lLines >= 0 then
    begin
      aSettings.fDiagnosticsDefaults.fSourceContextLines := lLines;
      RecordSettingOrigin(aSettings.fOrigins, 'Diagnostics.SourceContextLines', aIniPath);
    end else if aDiagnostics <> nil then
      aDiagnostics.AddWarning('Invalid dak.ini SourceContextLines value: ' + lValue);
  end;

  lValue := Trim(aIni.ReadString(SDiagnosticsSection, 'IgnoreUnknownMacros', ''));
  if lValue <> '' then
  begin
    aSettings.fIgnoreUnknownMacros := MergeList(aSettings.fIgnoreUnknownMacros, lValue);
    RecordSettingOrigin(aSettings.fOrigins, 'Diagnostics.IgnoreUnknownMacros', aIniPath, True);
    if aDiagnostics <> nil then
      aDiagnostics.AddIgnoreUnknownMacros(lValue);
  end;
  lValue := Trim(aIni.ReadString(SDiagnosticsSection, 'IgnoreMissingPaths', ''));
  if lValue <> '' then
  begin
    aSettings.fIgnoreMissingPaths := MergeList(aSettings.fIgnoreMissingPaths, lValue);
    RecordSettingOrigin(aSettings.fOrigins, 'Diagnostics.IgnoreMissingPaths', aIniPath, True);
    if aDiagnostics <> nil then
      aDiagnostics.AddIgnoreMissingPathMasks(lValue);
  end;
end;

function LoadDakSettingsCore(aDiagnostics: TDiagnostics; const aDprojPath: string;
  const aEnvVars: TDictionary<string, string>; const aWorkspaceSelector: string;
  out aSettings: TDakSettings): Boolean;
var
  lError: string;
  lIni: TCustomIniFile;
  lPath: string;
  lPaths: TArray<string>;
begin
  aSettings := Default(TDakSettings);
  aSettings.fFixInsight.fExcludeFlexCel := True;
  aSettings.fDiagnosticsDefaults.fSourceContextMode := TSourceContextMode.scmAuto;
  aSettings.fDiagnosticsDefaults.fSourceContextLines := 2;
  aSettings.fAnalysisPolicy.fGateOwnership := 'project;repository';
  Result := True;

  if not TryBuildSettingsPaths(aDprojPath, aWorkspaceSelector, lPaths, aSettings.fWorkspace, lError) then
  begin
    aSettings.fError := lError;
    Exit(False);
  end;
  for lPath in lPaths do
  begin
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoSettingsPath, [lPath]));
    if not FileExists(lPath) then
      Continue;
    AppendPath(aSettings.fLoadedPaths, lPath);
    lIni := OpenSettingsIni(lPath);
    try
      ApplyIniSettings(lIni, lPath, aEnvVars, aSettings, aDiagnostics);
      if not ApplyAnalysisPolicy(lIni, lPath, aEnvVars, aSettings) then
        Result := False;
    finally
      lIni.Free;
    end;
  end;
  aSettings.fAnalysisPolicy.fSha256 := LowerCase(THashSHA2.GetHashString(
    'GateOwnership=' + aSettings.fAnalysisPolicy.fGateOwnership + #10 +
    'GateMetrics=' + aSettings.fAnalysisPolicy.fGateMetrics + #10 +
    'ProjectRoots=' + LowerCase(aSettings.fAnalysisPolicy.fProjectRoots) + #10 +
    'ThirdPartyRoots=' + LowerCase(aSettings.fAnalysisPolicy.fThirdPartyRoots)));
end;

function LoadDakSettings(aDiagnostics: TDiagnostics; const aDprojPath: string;
  const aEnvVars: TDictionary<string, string>; out aSettings: TDakSettings): Boolean; overload;
begin
  Result := LoadDakSettingsCore(aDiagnostics, aDprojPath, aEnvVars, '', aSettings);
end;

function LoadDakSettings(aDiagnostics: TDiagnostics; const aDprojPath: string;
  const aEnvVars: TDictionary<string, string>; const aWorkspaceSelector: string;
  out aSettings: TDakSettings): Boolean; overload;
begin
  Result := LoadDakSettingsCore(aDiagnostics, aDprojPath, aEnvVars, aWorkspaceSelector, aSettings);
end;

function LoadSettings(aDiagnostics: TDiagnostics; out aFixInsight: TFixInsightExtraOptions;
  out aFixInsightIgnore: TFixInsightIgnoreDefaults; out aReportFilter: TReportFilterDefaults;
  out aPascalAnalyzer: TPascalAnalyzerDefaults): Boolean;
begin
  Result := LoadSettings(aDiagnostics, '', aFixInsight, aFixInsightIgnore, aReportFilter, aPascalAnalyzer);
end;

function LoadSettings(aDiagnostics: TDiagnostics; const aDprojPath: string;
  out aFixInsight: TFixInsightExtraOptions; out aFixInsightIgnore: TFixInsightIgnoreDefaults;
  out aReportFilter: TReportFilterDefaults; out aPascalAnalyzer: TPascalAnalyzerDefaults): Boolean;
var
  lSettings: TDakSettings;
begin
  LoadDakSettings(aDiagnostics, aDprojPath, nil, lSettings);
  aFixInsight := lSettings.fFixInsight;
  aFixInsightIgnore := lSettings.fFixInsightIgnore;
  aReportFilter := lSettings.fReportFilter;
  aPascalAnalyzer := lSettings.fPascalAnalyzer;
  Result := True;
end;

function LoadDefaultDelphiVersion(const aDprojPath: string; out aDelphiVersion: string): Boolean;
var
  lSettings: TDakSettings;
begin
  LoadDakSettings(nil, aDprojPath, nil, lSettings);
  aDelphiVersion := lSettings.fDelphiVersion;
  Result := True;
end;

function LoadDiagnosticsDefaults(aDiagnostics: TDiagnostics; const aDprojPath: string;
  out aDiagnosticsDefaults: TDiagnosticsDefaults): Boolean;
var
  lSettings: TDakSettings;
begin
  LoadDakSettings(aDiagnostics, aDprojPath, nil, lSettings);
  aDiagnosticsDefaults := lSettings.fDiagnosticsDefaults;
  Result := True;
end;

procedure LoadBuildSettings(const aDprojPath: string; const aOverrides: TAppOptions;
  const aEnvVars: TDictionary<string, string>; out aSettings: TDakBuildSettings);
var
  lSettings: TDakSettings;
begin
  LoadDakSettings(nil, aDprojPath, aEnvVars, lSettings);
  aSettings := lSettings.fBuild;
  ApplyBuildSettingsOverrides(aOverrides, aSettings);
end;

procedure ApplyPascalAnalyzerEnvironmentCore(var aPascalAnalyzer: TPascalAnalyzerDefaults;
  var aOrigins: TArray<TSettingsValueOrigin>);
var
  lValue: string;
begin
  lValue := Trim(GetEnvironmentVariable('PA_PATH'));
  if lValue <> '' then
  begin
    aPascalAnalyzer.fPath := lValue;
    RecordSettingOrigin(aOrigins, 'PascalAnalyzer.Path', 'PA_PATH environment variable');
  end;
  lValue := Trim(GetEnvironmentVariable('PA_ARGS'));
  if lValue <> '' then
  begin
    aPascalAnalyzer.fArgs := lValue;
    RecordSettingOrigin(aOrigins, 'PascalAnalyzer.Args', 'PA_ARGS environment variable');
    aPascalAnalyzer.fArgsSource := 'PA_ARGS environment variable';
  end;
end;

procedure ApplyPascalAnalyzerEnvironment(var aPascalAnalyzer: TPascalAnalyzerDefaults);
var
  lOrigins: TArray<TSettingsValueOrigin>;
begin
  ApplyPascalAnalyzerEnvironmentCore(aPascalAnalyzer, lOrigins);
end;

procedure ApplySettingsOverridesCore(const aOverrides: TAppOptions; var aFixInsight: TFixInsightExtraOptions;
  var aFixInsightIgnore: TFixInsightIgnoreDefaults; var aReportFilter: TReportFilterDefaults;
  var aPascalAnalyzer: TPascalAnalyzerDefaults; var aOrigins: TArray<TSettingsValueOrigin>);
begin
  if aOverrides.fHasFixOutput then
  begin
    aFixInsight.fOutput := aOverrides.fFixOutput;
    RecordSettingOrigin(aOrigins, 'FixInsightCL.Output', '--fi-output');
  end;
  if aOverrides.fHasFixIgnore then
  begin
    aFixInsight.fIgnore := MergeList(aFixInsight.fIgnore, aOverrides.fFixIgnore);
    RecordSettingOrigin(aOrigins, 'FixInsightCL.Ignore', '--fi-ignore', True);
  end;
  if aOverrides.fHasFixSettings then
  begin
    aFixInsight.fSettings := aOverrides.fFixSettings;
    RecordSettingOrigin(aOrigins, 'FixInsightCL.Settings', '--fi-settings');
  end;
  if aOverrides.fHasFixSilent then
  begin
    aFixInsight.fSilent := aOverrides.fFixSilent;
    RecordSettingOrigin(aOrigins, 'FixInsightCL.Silent', '--fi-silent');
  end;
  if aOverrides.fHasFixXml then
  begin
    aFixInsight.fXml := aOverrides.fFixXml;
    RecordSettingOrigin(aOrigins, 'FixInsightCL.Xml', '--fi-xml');
  end;
  if aOverrides.fHasFixCsv then
  begin
    aFixInsight.fCsv := aOverrides.fFixCsv;
    RecordSettingOrigin(aOrigins, 'FixInsightCL.Csv', '--fi-csv');
  end;
  if aOverrides.fHasFixTimeoutSec then
  begin
    aFixInsight.fTimeoutSec := aOverrides.fFixTimeoutSec;
    RecordSettingOrigin(aOrigins, 'FixInsightCL.TimeoutSec', '--fi-timeout-sec');
  end;

  if aOverrides.fHasIgnoreWarningIds then
  begin
    aFixInsightIgnore.fWarnings := MergeList(aFixInsightIgnore.fWarnings, aOverrides.fIgnoreWarningIds);
    RecordSettingOrigin(aOrigins, 'FixInsightIgnore.Warnings', '--ignore-warning-ids', True);
  end;

  if aOverrides.fHasExcludePathMasks then
  begin
    aReportFilter.fExcludePathMasks := MergeList(aReportFilter.fExcludePathMasks, aOverrides.fExcludePathMasks);
    RecordSettingOrigin(aOrigins, 'ReportFilter.ExcludePathMasks', '--exclude-path-masks', True);
  end;

  if aOverrides.fHasPaPath then
  begin
    aPascalAnalyzer.fPath := aOverrides.fPaPath;
    RecordSettingOrigin(aOrigins, 'PascalAnalyzer.Path', '--pa-path');
  end;
  if aOverrides.fHasPaOutput then
  begin
    aPascalAnalyzer.fOutput := aOverrides.fPaOutput;
    RecordSettingOrigin(aOrigins, 'PascalAnalyzer.Output', '--pa-output');
  end;
  if aOverrides.fHasPaArgs then
  begin
    RecordSettingOrigin(aOrigins, 'PascalAnalyzer.Args', '--pa-args');
    aPascalAnalyzer.fArgs := aOverrides.fPaArgs;
    aPascalAnalyzer.fArgsSource := '--pa-args';
    if (Trim(GetEnvironmentVariable('PA_ARGS')) <> '') and
      (Trim(GetEnvironmentVariable('PA_ARGS')) = Trim(aOverrides.fPaArgs)) then
      aPascalAnalyzer.fArgsSource := '--pa-args (matching PA_ARGS environment value)';
  end;
  if aOverrides.fHasPaExcludeSearchFolders then
  begin
    aPascalAnalyzer.fExcludeSearchFolders := aOverrides.fPaExcludeSearchFolders;
    RecordSettingOrigin(aOrigins, 'PascalAnalyzer.ExcludeSearchFolders', '--pa-exclude-search-folders');
  end;
  if aOverrides.fHasPaExcludeFiles then
  begin
    aPascalAnalyzer.fExcludeFiles := aOverrides.fPaExcludeFiles;
    RecordSettingOrigin(aOrigins, 'PascalAnalyzer.ExcludeFiles', '--pa-exclude-files');
  end;
  if aOverrides.fHasPaTimeoutSec then
  begin
    aPascalAnalyzer.fTimeoutSec := aOverrides.fPaTimeoutSec;
    RecordSettingOrigin(aOrigins, 'PascalAnalyzer.TimeoutSec', '--pa-timeout-sec');
  end;
end;

procedure ApplySettingsOverrides(const aOverrides: TAppOptions; var aFixInsight: TFixInsightExtraOptions;
  var aFixInsightIgnore: TFixInsightIgnoreDefaults; var aReportFilter: TReportFilterDefaults;
  var aPascalAnalyzer: TPascalAnalyzerDefaults);
var
  lOrigins: TArray<TSettingsValueOrigin>;
begin
  ApplySettingsOverridesCore(aOverrides, aFixInsight, aFixInsightIgnore, aReportFilter, aPascalAnalyzer, lOrigins);
end;

procedure ApplyAnalysisSettingsOverrides(const aOptions: TAppOptions; var aSettings: TDakSettings);
begin
  ApplyPascalAnalyzerEnvironmentCore(aSettings.fPascalAnalyzer, aSettings.fOrigins);
  ApplySettingsOverridesCore(aOptions, aSettings.fFixInsight, aSettings.fFixInsightIgnore,
    aSettings.fReportFilter, aSettings.fPascalAnalyzer, aSettings.fOrigins);
end;

procedure ApplyBuildSettingsOverrides(const aOverrides: TAppOptions; var aSettings: TDakBuildSettings);
begin
  if aOverrides.fHasBuildIgnoreWarnings then
    aSettings.fIgnoreWarnings := MergeList(aSettings.fIgnoreWarnings, aOverrides.fBuildIgnoreWarnings);
  if aOverrides.fHasBuildIgnoreHints then
    aSettings.fIgnoreHints := MergeList(aSettings.fIgnoreHints, aOverrides.fBuildIgnoreHints);
  if aOverrides.fHasExcludePathMasks then
    aSettings.fExcludePathMasks := MergeList(aSettings.fExcludePathMasks, aOverrides.fExcludePathMasks);
end;

procedure ApplyPascalAnalyzerIgnoreOverride(const aOverrides: TAppOptions;
  var aPascalAnalyzerIgnore: TPascalAnalyzerIgnoreDefaults);
var
  lOrigin: string;
begin
  if aOverrides.fHasPalIgnoreRules then
  begin
    aPascalAnalyzerIgnore.fRules := MergeList(
      aPascalAnalyzerIgnore.fRules, aOverrides.fPalIgnoreRules);
    aPascalAnalyzerIgnore.fSources := MergeList(
      aPascalAnalyzerIgnore.fSources, 'command_line');
    // D3: the parser records an environment origin directly. The process variable is still
    // honored for callers that set it themselves.
    if aOverrides.fPalIgnoreRulesOrigin <> '' then
      aPascalAnalyzerIgnore.fSources := MergeList(
        aPascalAnalyzerIgnore.fSources, aOverrides.fPalIgnoreRulesOrigin);
    lOrigin := Trim(GetEnvironmentVariable(
      SPalIgnoreRulesOriginEnvironment));
    if SameText(lOrigin, 'environment:' + SPalIgnoreRulesEnvironment) then
      aPascalAnalyzerIgnore.fSources := MergeList(
        aPascalAnalyzerIgnore.fSources, lOrigin);
  end;
end;

procedure ApplyDiagnosticsOverrides(const aOverrides: TAppOptions; var aDiagnosticsDefaults: TDiagnosticsDefaults);
begin
  if aOverrides.fHasSourceContextMode then
    aDiagnosticsDefaults.fSourceContextMode := aOverrides.fSourceContextMode;
  if aOverrides.fHasSourceContextLines then
    aDiagnosticsDefaults.fSourceContextLines := aOverrides.fSourceContextLines;
end;

end.
