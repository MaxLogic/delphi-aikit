unit Dak.FixInsightSettings;

interface

uses
  System.Generics.Collections,
  System.IniFiles, System.IOUtils, System.SysUtils,
  maxLogic.StrUtils,
  Dak.Diagnostics, Dak.Messages, Dak.Types;

function LoadSettings(aDiagnostics: TDiagnostics; out aFixInsight: TFixInsightExtraOptions;
  out aFixInsightIgnore: TFixInsightIgnoreDefaults; out aReportFilter: TReportFilterDefaults;
  out aPascalAnalyzer: TPascalAnalyzerDefaults): Boolean;
procedure ApplySettingsOverrides(const aOverrides: TAppOptions; var aFixInsight: TFixInsightExtraOptions;
  var aFixInsightIgnore: TFixInsightIgnoreDefaults; var aReportFilter: TReportFilterDefaults;
  var aPascalAnalyzer: TPascalAnalyzerDefaults);

implementation

const
  SSettingsFileName = 'settings.ini';
  SFixInsightSection = 'FixInsightCL';
  SFixInsightIgnoreSection = 'FixInsightIgnore';
  SReportFilterSection = 'ReportFilter';
  SPascalAnalyzerSection = 'PascalAnalyzer';

function GetSettingsPath: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), SSettingsFileName);
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
var
  lIni: TIniFile;
  lPath: string;
begin
  aFixInsight := Default(TFixInsightExtraOptions);
  aFixInsightIgnore := Default(TFixInsightIgnoreDefaults);
  aReportFilter := Default(TReportFilterDefaults);
  aPascalAnalyzer := Default(TPascalAnalyzerDefaults);
  lPath := GetSettingsPath;
  if aDiagnostics <> nil then
    aDiagnostics.AddInfo(Format(SInfoSettingsPath, [lPath]));
  if not FileExists(lPath) then
    Exit(True);

  Result := False;
  lIni := TIniFile.Create(lPath);
  try
    aFixInsight.fExePath := Trim(lIni.ReadString(SFixInsightSection, 'Path', ''));
    aFixInsight.fOutput := Trim(lIni.ReadString(SFixInsightSection, 'Output', ''));
    aFixInsight.fIgnore := Trim(lIni.ReadString(SFixInsightSection, 'Ignore', ''));
    aFixInsight.fSettings := Trim(lIni.ReadString(SFixInsightSection, 'Settings', ''));
    ReadBoolOption(lIni, 'Silent', aFixInsight.fSilent, aDiagnostics);
    ReadBoolOption(lIni, 'Xml', aFixInsight.fXml, aDiagnostics);
    ReadBoolOption(lIni, 'Csv', aFixInsight.fCsv, aDiagnostics);

    aFixInsightIgnore.fWarnings := Trim(lIni.ReadString(SFixInsightIgnoreSection, 'Warnings', ''));

    aReportFilter.fExcludePathMasks := Trim(lIni.ReadString(SReportFilterSection, 'ExcludePathMasks', ''));

    aPascalAnalyzer.fPath := Trim(lIni.ReadString(SPascalAnalyzerSection, 'Path', ''));
    aPascalAnalyzer.fOutput := Trim(lIni.ReadString(SPascalAnalyzerSection, 'Output', ''));
    aPascalAnalyzer.fArgs := Trim(lIni.ReadString(SPascalAnalyzerSection, 'Args', ''));
    Result := True;
  finally
    lIni.Free;
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
    aReportFilter.fExcludePathMasks := aOverrides.fExcludePathMasks;

  if aOverrides.fHasPaPath then
    aPascalAnalyzer.fPath := aOverrides.fPaPath;
  if aOverrides.fHasPaOutput then
    aPascalAnalyzer.fOutput := aOverrides.fPaOutput;
  if aOverrides.fHasPaArgs then
    aPascalAnalyzer.fArgs := aOverrides.fPaArgs;
end;

end.
