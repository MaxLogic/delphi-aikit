unit Dak.FixInsightSettings;

interface

uses
  System.Generics.Collections,
  System.IniFiles, System.IOUtils, System.SysUtils,
  maxLogic.StrUtils,
  Dak.Diagnostics, Dak.Messages, Dak.Types;

function LoadSettings(aDiagnostics: TDiagnostics; const aDprojPath: string;
  out aFixInsight: TFixInsightExtraOptions; out aFixInsightIgnore: TFixInsightIgnoreDefaults;
  out aReportFilter: TReportFilterDefaults; out aPascalAnalyzer: TPascalAnalyzerDefaults): Boolean; overload;
function LoadSettings(aDiagnostics: TDiagnostics; out aFixInsight: TFixInsightExtraOptions;
  out aFixInsightIgnore: TFixInsightIgnoreDefaults; out aReportFilter: TReportFilterDefaults;
  out aPascalAnalyzer: TPascalAnalyzerDefaults): Boolean; overload;
procedure ApplySettingsOverrides(const aOverrides: TAppOptions; var aFixInsight: TFixInsightExtraOptions;
  var aFixInsightIgnore: TFixInsightIgnoreDefaults; var aReportFilter: TReportFilterDefaults;
  var aPascalAnalyzer: TPascalAnalyzerDefaults);

implementation

const
  SSettingsFileName = 'dak.ini';
  SFixInsightSection = 'FixInsightCL';
  SFixInsightIgnoreSection = 'FixInsightIgnore';
  SReportFilterSection = 'ReportFilter';
  SPascalAnalyzerSection = 'PascalAnalyzer';
  SDiagnosticsSection = 'Diagnostics';

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

procedure ReadBoolOption(const aIni: TIniFile; const aKey: string; var aTarget: Boolean;
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

function LoadSettings(aDiagnostics: TDiagnostics; out aFixInsight: TFixInsightExtraOptions;
  out aFixInsightIgnore: TFixInsightIgnoreDefaults; out aReportFilter: TReportFilterDefaults;
  out aPascalAnalyzer: TPascalAnalyzerDefaults): Boolean;
begin
  Result := LoadSettings(aDiagnostics, '', aFixInsight, aFixInsightIgnore, aReportFilter, aPascalAnalyzer);
end;

procedure ApplyIniSettings(const aIni: TIniFile; var aFixInsight: TFixInsightExtraOptions;
  var aFixInsightIgnore: TFixInsightIgnoreDefaults; var aReportFilter: TReportFilterDefaults;
  var aPascalAnalyzer: TPascalAnalyzerDefaults; aDiagnostics: TDiagnostics);
var
  lValue: string;
begin
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Path', ''));
  if lValue <> '' then
    aFixInsight.fExePath := lValue;
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Output', ''));
  if lValue <> '' then
    aFixInsight.fOutput := lValue;
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Ignore', ''));
  if lValue <> '' then
    aFixInsight.fIgnore := MergeList(aFixInsight.fIgnore, lValue);
  lValue := Trim(aIni.ReadString(SFixInsightSection, 'Settings', ''));
  if lValue <> '' then
    aFixInsight.fSettings := lValue;
  ReadBoolOption(aIni, 'Silent', aFixInsight.fSilent, aDiagnostics);
  ReadBoolOption(aIni, 'Xml', aFixInsight.fXml, aDiagnostics);
  ReadBoolOption(aIni, 'Csv', aFixInsight.fCsv, aDiagnostics);

  lValue := Trim(aIni.ReadString(SFixInsightIgnoreSection, 'Warnings', ''));
  if lValue <> '' then
    aFixInsightIgnore.fWarnings := MergeList(aFixInsightIgnore.fWarnings, lValue);

  lValue := Trim(aIni.ReadString(SReportFilterSection, 'ExcludePathMasks', ''));
  if lValue <> '' then
    aReportFilter.fExcludePathMasks := MergeList(aReportFilter.fExcludePathMasks, lValue);

  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'Path', ''));
  if lValue <> '' then
    aPascalAnalyzer.fPath := lValue;
  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'Output', ''));
  if lValue <> '' then
    aPascalAnalyzer.fOutput := lValue;
  lValue := Trim(aIni.ReadString(SPascalAnalyzerSection, 'Args', ''));
  if lValue <> '' then
    aPascalAnalyzer.fArgs := lValue;

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

function LoadSettings(aDiagnostics: TDiagnostics; const aDprojPath: string;
  out aFixInsight: TFixInsightExtraOptions; out aFixInsightIgnore: TFixInsightIgnoreDefaults;
  out aReportFilter: TReportFilterDefaults; out aPascalAnalyzer: TPascalAnalyzerDefaults): Boolean;
var
  lIni: TIniFile;
  lPath: string;
  lPaths: TArray<string>;
begin
  aFixInsight := Default(TFixInsightExtraOptions);
  aFixInsightIgnore := Default(TFixInsightIgnoreDefaults);
  aReportFilter := Default(TReportFilterDefaults);
  aPascalAnalyzer := Default(TPascalAnalyzerDefaults);
  Result := True;
  lPaths := BuildSettingsPaths(aDprojPath);
  for lPath in lPaths do
  begin
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoSettingsPath, [lPath]));
    if not FileExists(lPath) then
      Continue;
    lIni := TIniFile.Create(lPath);
    try
      ApplyIniSettings(lIni, aFixInsight, aFixInsightIgnore, aReportFilter, aPascalAnalyzer, aDiagnostics);
    finally
      lIni.Free;
    end;
  end;
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
end;

end.
