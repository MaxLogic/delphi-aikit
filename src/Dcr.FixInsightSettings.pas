unit Dcr.FixInsightSettings;

interface

uses
  System.IniFiles, System.IOUtils, System.SysUtils,
  Dcr.Diagnostics, Dcr.Messages, Dcr.Types;

function LoadFixInsightDefaults(aDiagnostics: TDiagnostics; out aOptions: TFixInsightExtraOptions): Boolean;
procedure ApplyFixInsightOverrides(const aOverrides: TAppOptions; var aOptions: TFixInsightExtraOptions);

implementation

const
  SSettingsFileName = 'settings.ini';
  SFixInsightSection = 'FixInsightCL';

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

function LoadFixInsightDefaults(aDiagnostics: TDiagnostics; out aOptions: TFixInsightExtraOptions): Boolean;
var
  lIni: TIniFile;
  lPath: string;
begin
  aOptions := Default(TFixInsightExtraOptions);
  lPath := GetSettingsPath;
  if aDiagnostics <> nil then
    aDiagnostics.AddInfo(Format(SInfoSettingsPath, [lPath]));
  if not FileExists(lPath) then
    Exit(True);

  Result := False;
  lIni := TIniFile.Create(lPath);
  try
    aOptions.fOutput := Trim(lIni.ReadString(SFixInsightSection, 'Output', ''));
    aOptions.fIgnore := Trim(lIni.ReadString(SFixInsightSection, 'Ignore', ''));
    aOptions.fSettings := Trim(lIni.ReadString(SFixInsightSection, 'Settings', ''));
    ReadBoolOption(lIni, 'Silent', aOptions.fSilent, aDiagnostics);
    ReadBoolOption(lIni, 'Xml', aOptions.fXml, aDiagnostics);
    ReadBoolOption(lIni, 'Csv', aOptions.fCsv, aDiagnostics);
    Result := True;
  finally
    lIni.Free;
  end;
end;

procedure ApplyFixInsightOverrides(const aOverrides: TAppOptions; var aOptions: TFixInsightExtraOptions);
begin
  if aOverrides.fHasFixOutput then
    aOptions.fOutput := aOverrides.fFixOutput;
  if aOverrides.fHasFixIgnore then
    aOptions.fIgnore := aOverrides.fFixIgnore;
  if aOverrides.fHasFixSettings then
    aOptions.fSettings := aOverrides.fFixSettings;
  if aOverrides.fHasFixSilent then
    aOptions.fSilent := aOverrides.fFixSilent;
  if aOverrides.fHasFixXml then
    aOptions.fXml := aOverrides.fFixXml;
  if aOverrides.fHasFixCsv then
    aOptions.fCsv := aOverrides.fFixCsv;
end;

end.
