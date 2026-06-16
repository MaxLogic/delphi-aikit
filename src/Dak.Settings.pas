unit Dak.Settings;

interface

uses
  System.Generics.Collections, System.IniFiles, System.IOUtils, System.SysUtils,
  maxLogic.RichIniFile, maxLogic.StrUtils,
  Dak.Diagnostics, Dak.MacroExpander, Dak.Messages, Dak.Types;

type
  TDakBuildSettings = record
    fIgnoreWarnings: string;
    fIgnoreHints: string;
    fExcludePathMasks: string;
    fMadExceptPath: string;
    fWebCoreCompilerPath: string;
  end;

  TDakSettings = record
    fFixInsight: TFixInsightExtraOptions;
    fFixInsightIgnore: TFixInsightIgnoreDefaults;
    fReportFilter: TReportFilterDefaults;
    fPascalAnalyzer: TPascalAnalyzerDefaults;
    fBuild: TDakBuildSettings;
    fDiagnosticsDefaults: TDiagnosticsDefaults;
    fDelphiVersion: string;
  end;

function BuildSettingsPaths(const aDprojPath: string): TArray<string>;
function LoadDakSettings(aDiagnostics: TDiagnostics; const aDprojPath: string;
  const aEnvVars: TDictionary<string, string>; out aSettings: TDakSettings): Boolean;
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
procedure ApplyBuildSettingsOverrides(const aOverrides: TAppOptions; var aSettings: TDakBuildSettings);
procedure ApplyDiagnosticsOverrides(const aOverrides: TAppOptions; var aDiagnosticsDefaults: TDiagnosticsDefaults);

implementation

const
  SSettingsFileName = 'dak.ini';
  SFixInsightSection = 'FixInsightCL';
  SFixInsightIgnoreSection = 'FixInsightIgnore';
  SReportFilterSection = 'ReportFilter';
  SPascalAnalyzerSection = 'PascalAnalyzer';
  SBuildSection = 'Build';
  SBuildIgnoreSection = 'BuildIgnore';
  SMadExceptSection = 'MadExcept';
  SDiagnosticsSection = 'Diagnostics';
  SWebCoreSection = 'WebCore';

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
    DirectoryExists(TPath.Combine(aDir, '.svn'));
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

function BuildSettingsPaths(const aDprojPath: string): TArray<string>;
var
  lPaths: TList<string>;
  lSeen: THashSet<string>;
  lDprojDir: string;
  lRepoRoot: string;
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
  lPaths := TList<string>.Create;
  lSeen := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    AddPath(GetExeSettingsPath);
    if aDprojPath <> '' then
    begin
      lDprojDir := NormalizeDir(ExtractFileDir(TPath.GetFullPath(aDprojPath)));
      if lDprojDir <> '' then
      begin
        lRepoRoot := FindRepoRoot(lDprojDir);
        if lRepoRoot <> '' then
          lDirs := GetProjectDirChain(lRepoRoot, lDprojDir)
        else
          lDirs := [lDprojDir];
        for lDir in lDirs do
          AddPath(TPath.Combine(lDir, SSettingsFileName));
      end;
    end;
    Result := lPaths.ToArray;
  finally
    lSeen.Free;
    lPaths.Free;
  end;
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

function OpenSettingsIni(const aPath: string): TCustomIniFile;
var
  lOptions: TRichIniOptions;
  lIni: TRichIniFile;
begin
  lOptions := DefaultRichIniOptions;
  lIni := TRichIniFile.Create(aPath, lOptions);
  lIni.LoadFromFile(aPath);
  Result := lIni;
end;

procedure ReadBoolOption(const aIni: TCustomIniFile; const aKey: string; var aTarget: Boolean;
  aDiagnostics: TDiagnostics);
var
  lValue: string;
  lParsed: Boolean;
begin
  lValue := Trim(aIni.ReadString(SFixInsightSection, aKey, ''));
  if lValue = '' then
    Exit;
  if TryParseBoolText(lValue, lParsed) then
    aTarget := lParsed
  else if aDiagnostics <> nil then
    aDiagnostics.AddWarning(Format(SSettingsInvalidBool, [aKey, lValue]));
end;

procedure ReadPositiveIntegerOption(const aIni: TCustomIniFile; const aSection: string; const aKey: string;
  var aTarget: Integer; aDiagnostics: TDiagnostics);
var
  lParsed: Integer;
  lValue: string;
begin
  lValue := Trim(aIni.ReadString(aSection, aKey, ''));
  if lValue = '' then
    Exit;

  lParsed := StrToIntDef(lValue, -1);
  if lParsed >= 1 then
    aTarget := lParsed
  else if aDiagnostics <> nil then
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
    aSettings.fFixInsight.fExePath := lValue;
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Output', ''));
  if lValue <> '' then
    aSettings.fFixInsight.fOutput := lValue;
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Ignore', ''));
  if lValue <> '' then
    aSettings.fFixInsight.fIgnore := MergeList(aSettings.fFixInsight.fIgnore, lValue);
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Settings', ''));
  if lValue <> '' then
    aSettings.fFixInsight.fSettings := lValue;
  ReadBoolOption(aIni, 'Silent', aSettings.fFixInsight.fSilent, aDiagnostics);
  ReadBoolOption(aIni, 'Xml', aSettings.fFixInsight.fXml, aDiagnostics);
  ReadBoolOption(aIni, 'Csv', aSettings.fFixInsight.fCsv, aDiagnostics);
  ReadPositiveIntegerOption(aIni, SFixInsightSection, 'TimeoutSec', aSettings.fFixInsight.fTimeoutSec,
    aDiagnostics);

  lValue := Trim(aIni.ReadString(SFixInsightIgnoreSection, 'Warnings', ''));
  if lValue <> '' then
    aSettings.fFixInsightIgnore.fWarnings := MergeList(aSettings.fFixInsightIgnore.fWarnings, lValue);

  lValue := Trim(aIni.ReadString(SReportFilterSection, 'ExcludePathMasks', ''));
  if lValue <> '' then
  begin
    aSettings.fReportFilter.fExcludePathMasks := MergeList(aSettings.fReportFilter.fExcludePathMasks, lValue);
    aSettings.fBuild.fExcludePathMasks := MergeList(aSettings.fBuild.fExcludePathMasks, lValue);
  end;

  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'Path', ''));
  if lValue <> '' then
    aSettings.fPascalAnalyzer.fPath := lValue;
  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'Output', ''));
  if lValue <> '' then
    aSettings.fPascalAnalyzer.fOutput := lValue;
  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'Args', ''));
  if lValue <> '' then
    aSettings.fPascalAnalyzer.fArgs := lValue;
  ReadPositiveIntegerOption(aIni, SPascalAnalyzerSection, 'TimeoutSec', aSettings.fPascalAnalyzer.fTimeoutSec,
    aDiagnostics);

  lValue := Trim(aIni.ReadString(SBuildSection, 'DelphiVersion', ''));
  if lValue <> '' then
    aSettings.fDelphiVersion := lValue;

  lValue := Trim(aIni.ReadString(SBuildIgnoreSection, 'Warnings', ''));
  if lValue <> '' then
    aSettings.fBuild.fIgnoreWarnings := MergeList(aSettings.fBuild.fIgnoreWarnings, lValue);

  lValue := Trim(aIni.ReadString(SBuildIgnoreSection, 'Hints', ''));
  if lValue <> '' then
    aSettings.fBuild.fIgnoreHints := MergeList(aSettings.fBuild.fIgnoreHints, lValue);

  lValue := Trim(aIni.ReadString(SMadExceptSection, 'Path', ''));
  if lValue <> '' then
    aSettings.fBuild.fMadExceptPath := ExpandSettingPath(lValue, aIniPath, aEnvVars);

  lValue := Trim(aIni.ReadString(SWebCoreSection, 'CompilerPath', ''));
  if lValue <> '' then
    aSettings.fBuild.fWebCoreCompilerPath := ExpandSettingPath(lValue, aIniPath, aEnvVars);

  lValue := Trim(aIni.ReadString(SDiagnosticsSection, 'SourceContext', ''));
  if lValue <> '' then
  begin
    if TryParseSourceContextModeText(lValue, lMode) then
      aSettings.fDiagnosticsDefaults.fSourceContextMode := lMode
    else if aDiagnostics <> nil then
      aDiagnostics.AddWarning('Invalid dak.ini SourceContext value: ' + lValue);
  end;

  lValue := Trim(aIni.ReadString(SDiagnosticsSection, 'SourceContextLines', ''));
  if lValue <> '' then
  begin
    lLines := StrToIntDef(lValue, -1);
    if lLines >= 0 then
      aSettings.fDiagnosticsDefaults.fSourceContextLines := lLines
    else if aDiagnostics <> nil then
      aDiagnostics.AddWarning('Invalid dak.ini SourceContextLines value: ' + lValue);
  end;

  if aDiagnostics <> nil then
  begin
    lValue := Trim(aIni.ReadString(SDiagnosticsSection, 'IgnoreUnknownMacros', ''));
    if lValue <> '' then
      aDiagnostics.AddIgnoreUnknownMacros(lValue);
    lValue := Trim(aIni.ReadString(SDiagnosticsSection, 'IgnoreMissingPaths', ''));
    if lValue <> '' then
      aDiagnostics.AddIgnoreMissingPathMasks(lValue);
  end;
end;

function LoadDakSettings(aDiagnostics: TDiagnostics; const aDprojPath: string;
  const aEnvVars: TDictionary<string, string>; out aSettings: TDakSettings): Boolean;
var
  lIni: TCustomIniFile;
  lPath: string;
begin
  aSettings := Default(TDakSettings);
  aSettings.fDiagnosticsDefaults.fSourceContextMode := TSourceContextMode.scmAuto;
  aSettings.fDiagnosticsDefaults.fSourceContextLines := 2;
  Result := True;

  for lPath in BuildSettingsPaths(aDprojPath) do
  begin
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoSettingsPath, [lPath]));
    if not FileExists(lPath) then
      Continue;
    lIni := OpenSettingsIni(lPath);
    try
      ApplyIniSettings(lIni, lPath, aEnvVars, aSettings, aDiagnostics);
    finally
      lIni.Free;
    end;
  end;
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
  Result := LoadDakSettings(aDiagnostics, aDprojPath, nil, lSettings);
  aFixInsight := lSettings.fFixInsight;
  aFixInsightIgnore := lSettings.fFixInsightIgnore;
  aReportFilter := lSettings.fReportFilter;
  aPascalAnalyzer := lSettings.fPascalAnalyzer;
end;

function LoadDefaultDelphiVersion(const aDprojPath: string; out aDelphiVersion: string): Boolean;
var
  lSettings: TDakSettings;
begin
  Result := LoadDakSettings(nil, aDprojPath, nil, lSettings);
  aDelphiVersion := lSettings.fDelphiVersion;
end;

function LoadDiagnosticsDefaults(aDiagnostics: TDiagnostics; const aDprojPath: string;
  out aDiagnosticsDefaults: TDiagnosticsDefaults): Boolean;
var
  lSettings: TDakSettings;
begin
  Result := LoadDakSettings(aDiagnostics, aDprojPath, nil, lSettings);
  aDiagnosticsDefaults := lSettings.fDiagnosticsDefaults;
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

procedure ApplySettingsOverrides(const aOverrides: TAppOptions; var aFixInsight: TFixInsightExtraOptions;
  var aFixInsightIgnore: TFixInsightIgnoreDefaults; var aReportFilter: TReportFilterDefaults;
  var aPascalAnalyzer: TPascalAnalyzerDefaults);
begin
  if aOverrides.fHasFixOutput then
    aFixInsight.fOutput := aOverrides.fFixOutput;
  if aOverrides.fHasFixIgnore then
    aFixInsight.fIgnore := MergeList(aFixInsight.fIgnore, aOverrides.fFixIgnore);
  if aOverrides.fHasFixSettings then
    aFixInsight.fSettings := aOverrides.fFixSettings;
  if aOverrides.fHasFixSilent then
    aFixInsight.fSilent := aOverrides.fFixSilent;
  if aOverrides.fHasFixXml then
    aFixInsight.fXml := aOverrides.fFixXml;
  if aOverrides.fHasFixCsv then
    aFixInsight.fCsv := aOverrides.fFixCsv;
  if aOverrides.fHasFixTimeoutSec then
    aFixInsight.fTimeoutSec := aOverrides.fFixTimeoutSec;

  if aOverrides.fHasIgnoreWarningIds then
    aFixInsightIgnore.fWarnings := MergeList(aFixInsightIgnore.fWarnings, aOverrides.fIgnoreWarningIds);

  if aOverrides.fHasExcludePathMasks then
    aReportFilter.fExcludePathMasks := MergeList(aReportFilter.fExcludePathMasks, aOverrides.fExcludePathMasks);

  if aOverrides.fHasPaPath then
    aPascalAnalyzer.fPath := aOverrides.fPaPath;
  if aOverrides.fHasPaOutput then
    aPascalAnalyzer.fOutput := aOverrides.fPaOutput;
  if aOverrides.fHasPaArgs then
    aPascalAnalyzer.fArgs := aOverrides.fPaArgs;
  if aOverrides.fHasPaTimeoutSec then
    aPascalAnalyzer.fTimeoutSec := aOverrides.fPaTimeoutSec;
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

procedure ApplyDiagnosticsOverrides(const aOverrides: TAppOptions; var aDiagnosticsDefaults: TDiagnosticsDefaults);
begin
  if aOverrides.fHasSourceContextMode then
    aDiagnosticsDefaults.fSourceContextMode := aOverrides.fSourceContextMode;
  if aOverrides.fHasSourceContextLines then
    aDiagnosticsDefaults.fSourceContextLines := aOverrides.fSourceContextLines;
end;

end.
