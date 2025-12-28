unit Dcr.Output;

interface

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.SysUtils,
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
  lHasDefines: Boolean;
  lHasSearchPath: Boolean;
  lHasLibPath: Boolean;
  lHasScopes: Boolean;
  lHasAliases: Boolean;

  function SplitList(const aValue: string): TArray<string>;
  var
    lParts: TArray<string>;
    lPart: string;
    lList: TList<string>;
    i: Integer;
  begin
    lList := TList<string>.Create;
    try
      lParts := aValue.Split([';']);
      for i := 0 to High(lParts) do
      begin
        lPart := Trim(lParts[i]);
        if lPart <> '' then
          lList.Add(lPart);
      end;
      Result := lList.ToArray;
    finally
      lList.Free;
    end;
  end;

  procedure AppendVarList(const aVarName, aValue: string);
  const
    CMaxChunk = 1800;
  var
    lParts: TArray<string>;
    lPart: string;
    lChunk: string;
    lFirst: Boolean;

    procedure FlushChunk;
    begin
      if lChunk = '' then
        Exit;
      if lFirst then
        lLines.AppendLine(Format('set "%s=%s"', [aVarName, lChunk]))
      else
        lLines.AppendLine(Format('set "%s=%%%s%%;%s"', [aVarName, aVarName, lChunk]));
      lChunk := '';
      lFirst := False;
    end;
  begin
    if aValue = '' then
      Exit;
    lParts := SplitList(aValue);
    if Length(lParts) = 0 then
      Exit;
    lLines.AppendLine(Format('set "%s="', [aVarName]));
    lChunk := '';
    lFirst := True;
    for lPart in lParts do
    begin
      if lChunk = '' then
        lChunk := lPart
      else if Length(lChunk) + 1 + Length(lPart) <= CMaxChunk then
        lChunk := lChunk + ';' + lPart
      else
      begin
        FlushChunk;
        lChunk := lPart;
      end;
    end;
    FlushChunk;
  end;

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
    lHasDefines := lDefines <> '';
    lHasSearchPath := lSearchPath <> '';
    lHasLibPath := lLibPath <> '';
    lHasScopes := lScopes <> '';
    lHasAliases := lAliases <> '';
    lExe := aParams.fFixInsightExe;
    if lExe = '' then
      lExe := 'FixInsightCL.exe';
    lFixOutput := aParams.fFixOutput;
    lFixIgnore := aParams.fFixIgnore;
    lFixSettings := aParams.fFixSettings;
    lFixSilent := aParams.fFixSilent;
    lFixXml := aParams.fFixXml;
    lFixCsv := aParams.fFixCsv;

    lLines.AppendLine('@echo off');
    lLines.AppendLine('chcp 65001 >nul');
    lLines.AppendLine('setlocal EnableExtensions');

    if lHasDefines then
      AppendVarList('FI_DEFINES', lDefines);
    if lHasSearchPath then
      AppendVarList('FI_SEARCHPATH', lSearchPath);
    if lHasLibPath then
      AppendVarList('FI_LIBPATH', lLibPath);
    if lHasScopes then
      AppendVarList('FI_UNITSCOPES', lScopes);
    if lHasAliases then
      AppendVarList('FI_UNITALIASES', lAliases);

    lArgCount := 0;
    AddArg('--project=' + CmdQuote(aParams.fProjectDpr));
    if lHasDefines then
      AddArg('--defines=' + CmdQuote('%FI_DEFINES%'));
    if lHasSearchPath then
      AddArg('--searchpath=' + CmdQuote('%FI_SEARCHPATH%'));
    if lHasLibPath then
      AddArg('--libpath=' + CmdQuote('%FI_LIBPATH%'));
    if lHasScopes then
      AddArg('--unitscopes=' + CmdQuote('%FI_UNITSCOPES%'));
    if lHasAliases then
      AddArg('--unitaliases=' + CmdQuote('%FI_UNITALIASES%'));
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
  lEncoding: TEncoding;
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
    if aKind = TOutputKind.okBat then
    begin
      lEncoding := TUTF8Encoding.Create(False);
      try
        TFile.WriteAllText(aOutPath, lContent, lEncoding);
      finally
        lEncoding.Free;
      end;
    end else
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
