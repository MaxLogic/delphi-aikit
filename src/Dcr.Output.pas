unit Dcr.Output;

interface

uses
  System.Classes, System.IOUtils, System.SysUtils,
  Dcr.Messages, Dcr.Types;

function WriteOutput(const aParams: TFixInsightParams; aKind: TOutputKind; const aOutPath: string;
  out aError: string): Boolean;

implementation

function JoinList(const aValues: TArray<string>): string;
begin
  if Length(aValues) = 0 then
    Exit('');
  Result := String.Join(';', aValues);
end;

function XmlEscape(const aValue: string): string;
begin
  Result := aValue;
  Result := Result.Replace('&', '&amp;');
  Result := Result.Replace('<', '&lt;');
  Result := Result.Replace('>', '&gt;');
  Result := Result.Replace('"', '&quot;');
  Result := Result.Replace('''', '&apos;');
end;

function CmdQuote(const aValue: string): string;
begin
  Result := '"' + StringReplace(aValue, '"', '""', [rfReplaceAll]) + '"';
end;

function BuildIni(const aParams: TFixInsightParams): string;
var
  lLines: TStringBuilder;
begin
  lLines := TStringBuilder.Create;
  try
    lLines.AppendLine('[FixInsight]');
    lLines.AppendLine('ProjectDpr=' + aParams.fProjectDpr);
    lLines.AppendLine('Defines=' + JoinList(aParams.fDefines));
    lLines.AppendLine('SearchPath=' + JoinList(aParams.fUnitSearchPath));
    lLines.AppendLine('LibPath=' + JoinList(aParams.fLibraryPath));
    lLines.AppendLine('UnitScopes=' + JoinList(aParams.fUnitScopes));
    lLines.AppendLine('UnitAliases=' + JoinList(aParams.fUnitAliases));
    lLines.AppendLine('DelphiVersion=' + aParams.fDelphiVersion);
    lLines.AppendLine('Platform=' + aParams.fPlatform);
    lLines.AppendLine('Config=' + aParams.fConfig);
    Result := lLines.ToString;
  finally
    lLines.Free;
  end;
end;

function BuildXml(const aParams: TFixInsightParams): string;
var
  lLines: TStringBuilder;
  lItem: string;
begin
  lLines := TStringBuilder.Create;
  try
    lLines.AppendLine(Format('<FixInsightParams delphi="%s" platform="%s" config="%s">', [
      XmlEscape(aParams.fDelphiVersion), XmlEscape(aParams.fPlatform), XmlEscape(aParams.fConfig)]));
    lLines.AppendLine('  <ProjectDpr>' + XmlEscape(aParams.fProjectDpr) + '</ProjectDpr>');
    lLines.AppendLine('  <Defines>');
    for lItem in aParams.fDefines do
      lLines.AppendLine('    <D>' + XmlEscape(lItem) + '</D>');
    lLines.AppendLine('  </Defines>');
    lLines.AppendLine('  <SearchPath>');
    for lItem in aParams.fUnitSearchPath do
      lLines.AppendLine('    <P>' + XmlEscape(lItem) + '</P>');
    lLines.AppendLine('  </SearchPath>');
    lLines.AppendLine('  <LibPath>');
    for lItem in aParams.fLibraryPath do
      lLines.AppendLine('    <P>' + XmlEscape(lItem) + '</P>');
    lLines.AppendLine('  </LibPath>');
    lLines.AppendLine('  <UnitScopes>');
    for lItem in aParams.fUnitScopes do
      lLines.AppendLine('    <U>' + XmlEscape(lItem) + '</U>');
    lLines.AppendLine('  </UnitScopes>');
    if Length(aParams.fUnitAliases) > 0 then
    begin
      lLines.AppendLine('  <UnitAliases>');
      for lItem in aParams.fUnitAliases do
        lLines.AppendLine('    <A>' + XmlEscape(lItem) + '</A>');
      lLines.AppendLine('  </UnitAliases>');
    end;
    lLines.AppendLine('</FixInsightParams>');
    Result := lLines.ToString;
  finally
    lLines.Free;
  end;
end;

function BuildBat(const aParams: TFixInsightParams): string;
var
  lLines: TStringBuilder;
  lDefines: string;
  lSearchPath: string;
  lLibPath: string;
  lScopes: string;
  lAliases: string;
  lArgs: TArray<string>;
  lArgCount: Integer;
  lIndex: Integer;
  lExe: string;
  lFixOutput: string;
  lFixIgnore: string;
  lFixSettings: string;
  lFixSilent: Boolean;
  lFixXml: Boolean;
  lFixCsv: Boolean;

  procedure AddArg(const aValue: string);
  begin
    SetLength(lArgs, lArgCount + 1);
    lArgs[lArgCount] := aValue;
    Inc(lArgCount);
  end;
begin
  lLines := TStringBuilder.Create;
  try
    lDefines := JoinList(aParams.fDefines);
    lSearchPath := JoinList(aParams.fUnitSearchPath);
    lLibPath := JoinList(aParams.fLibraryPath);
    lScopes := JoinList(aParams.fUnitScopes);
    lAliases := JoinList(aParams.fUnitAliases);
    lExe := aParams.fFixInsightExe;
    if lExe = '' then
      lExe := 'FixInsightCL.exe';
    lFixOutput := aParams.fFixOutput;
    lFixIgnore := aParams.fFixIgnore;
    lFixSettings := aParams.fFixSettings;
    lFixSilent := aParams.fFixSilent;
    lFixXml := aParams.fFixXml;
    lFixCsv := aParams.fFixCsv;

    lArgCount := 0;
    AddArg('--project=' + CmdQuote(aParams.fProjectDpr));
    AddArg('--defines=' + CmdQuote(lDefines));
    AddArg('--searchpath=' + CmdQuote(lSearchPath));
    AddArg('--libpath=' + CmdQuote(lLibPath));
    AddArg('--unitscopes=' + CmdQuote(lScopes));
    if lAliases <> '' then
      AddArg('--unitaliases=' + CmdQuote(lAliases));
    if lFixOutput <> '' then
      AddArg('--output=' + CmdQuote(lFixOutput));
    if lFixIgnore <> '' then
      AddArg('--ignore=' + CmdQuote(lFixIgnore));
    if lFixSettings <> '' then
      AddArg('--settings=' + CmdQuote(lFixSettings));
    if lFixSilent then
      AddArg('--silent');
    if lFixXml then
      AddArg('--xml');
    if lFixCsv then
      AddArg('--csv');

    lLines.AppendLine('@echo off');
    lLines.AppendLine('setlocal');
    lLines.AppendLine(CmdQuote(lExe) + ' ^');
    for lIndex := 0 to High(lArgs) do
    begin
      if lIndex < High(lArgs) then
        lLines.AppendLine('  ' + lArgs[lIndex] + ' ^')
      else
        lLines.AppendLine('  ' + lArgs[lIndex]);
    end;
    Result := lLines.ToString;
  finally
    lLines.Free;
  end;
end;

function WriteOutput(const aParams: TFixInsightParams; aKind: TOutputKind; const aOutPath: string;
  out aError: string): Boolean;
var
  lContent: string;
begin
  aError := '';
  case aKind of
    TOutputKind.okIni: lContent := BuildIni(aParams);
    TOutputKind.okXml: lContent := BuildXml(aParams);
    TOutputKind.okBat: lContent := BuildBat(aParams);
  else
    lContent := '';
  end;

  if aOutPath = '' then
  begin
    Write(lContent);
    Exit(True);
  end;

  try
    TFile.WriteAllText(aOutPath, lContent, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      aError := Format(SOutputWriteFailed, [E.Message]);
      Exit(False);
    end;
  end;

  Result := True;
end;

end.
