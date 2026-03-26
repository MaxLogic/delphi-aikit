unit Dak.Registry;

interface

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.SysUtils,
  System.Win.Registry,
  Winapi.Windows,
  maxLogic.StrUtils,
  Dak.Diagnostics, Dak.Messages, Dak.MsBuild, Dak.Types;

function TryReadIdeConfig(const aDelphiVersion, aPlatform, aEnvOptionsOverride: string;
  out aEnvVars: TDictionary<string, string>; out aLibraryPath: string; out aLibrarySource: TPropertySource;
  aDiagnostics: TDiagnostics; out aError: string): Boolean;

implementation

function BuildEnvOptionsPlatformCandidates(const aPlatform: string): TArray<string>;
var
  lPlatform: string;
begin
  lPlatform := Trim(aPlatform);
  if SameText(lPlatform, 'Win64') then
    Exit(TArray<string>.Create('Win64', 'Win64x'));
  if SameText(lPlatform, 'Win64x') then
    Exit(TArray<string>.Create('Win64x', 'Win64'));
  Result := TArray<string>.Create(lPlatform);
end;

function TryReadEnvOptionsLibraryPath(const aEnvOptionsFile, aPlatform, aDelphiVersion: string;
  aEnvVars: TDictionary<string, string>; aDiagnostics: TDiagnostics; out aLibraryPath: string;
  out aError: string): Boolean;
var
  lCandidatePlatform: string;
  lCandidatePlatforms: TArray<string>;
  lProps: TDictionary<string, string>;
  lEvaluator: TMsBuildEvaluator;
  lValue: string;
  lOptionValue: string;

  procedure CaptureOption(const aName: string; aAllowEmpty: Boolean = False);
  begin
    if aEnvVars.ContainsKey(aName) then
      Exit;
    if lProps.TryGetValue(aName, lOptionValue) then
    begin
      lOptionValue := Trim(lOptionValue);
      if (lOptionValue <> '') or aAllowEmpty then
        aEnvVars.AddOrSetValue(aName, lOptionValue);
    end;
  end;
begin
  Result := False;
  aLibraryPath := '';
  aError := '';

  if not FileExists(aEnvOptionsFile) then
  begin
    aError := Format(SEnvOptionsNotFound, [aEnvOptionsFile]);
    Exit(False);
  end;

  lProps := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    lCandidatePlatforms := BuildEnvOptionsPlatformCandidates(aPlatform);
    for lCandidatePlatform in lCandidatePlatforms do
    begin
      lProps.Clear;
      lProps.AddOrSetValue('Platform', lCandidatePlatform);
      lProps.AddOrSetValue('Config', '');
      lProps.AddOrSetValue('DelphiVersion', aDelphiVersion);
      lEvaluator := TMsBuildEvaluator.Create(lProps, aEnvVars, aDiagnostics);
      try
        if not lEvaluator.EvaluateFile(aEnvOptionsFile, aError) then
          Exit(False);
      finally
        lEvaluator.Free;
      end;

      if not lProps.TryGetValue('DelphiLibraryPath', lValue) or (Trim(lValue) = '') then
        Continue;

      if (aDiagnostics <> nil) and (not SameText(lCandidatePlatform, aPlatform)) then
        aDiagnostics.AddInfo(Format(SInfoEnvOptionsPlatformAlias, [aPlatform, lCandidatePlatform]));
      aLibraryPath := lValue;
      CaptureOption('DCC_Define', True);
      CaptureOption('DCC_UnitSearchPath', True);
      CaptureOption('DCC_Namespace', True);
      CaptureOption('DCC_UnitAliases', True);
      CaptureOption('DCC_UnitAlias', True);
      CaptureOption('BDSCatalogRepository');
      CaptureOption('BDSUSERDIR');
      CaptureOption('BDSLIB');
      Exit(True);
    end;

    aError := Format(SEnvOptionsMissingLibPath, [aPlatform]);
  finally
    lProps.Free;
  end;
end;

function TryReadIdeConfig(const aDelphiVersion, aPlatform, aEnvOptionsOverride: string;
  out aEnvVars: TDictionary<string, string>; out aLibraryPath: string; out aLibrarySource: TPropertySource;
  aDiagnostics: TDiagnostics; out aError: string): Boolean;
var
  lReg: TRegistry;
  lBaseKey: string;
  lEnvKey: string;
  lLibKey: string;
  lHasLibPath: Boolean;
  lBaseFound: Boolean;
  lRegistryLibFound: Boolean;
  lNames: TStringList;
  lName: string;
  lBdsUserDir: string;
  lAppData: string;
  lEnvOptionsFile: string;
  lValue: string;
  lCatalogRepo: string;
  lBdsRoot: string;
  lBdsLib: string;

  procedure EnsureEnvVar(const aName, aValue: string; aAllowEmpty: Boolean);
  var
    lExisting: string;
  begin
    if aEnvVars.TryGetValue(aName, lExisting) then
    begin
      if (lExisting = '') and (aValue <> '') then
        aEnvVars.AddOrSetValue(aName, aValue);
      Exit;
    end;
    if (aValue <> '') or aAllowEmpty then
      aEnvVars.AddOrSetValue(aName, aValue);
  end;

  function JoinNames(const aList: TStrings): string;
  begin
    if (aList = nil) or (aList.Count = 0) then
      Exit('');
    Result := String.Join(';', aList.ToStringArray);
  end;

  procedure LogBdsVersions(const aViewLabel: string; aWowFlag: Cardinal);
  var
    lList: TStringList;
  begin
    lReg := TRegistry.Create;
    try
      lReg.Access := KEY_READ or aWowFlag;
      lReg.RootKey := HKEY_CURRENT_USER;
      if lReg.OpenKeyReadOnly('Software\Embarcadero\BDS') then
      begin
        lList := TStringList.Create;
        try
          lReg.GetKeyNames(lList);
          if aDiagnostics <> nil then
            aDiagnostics.AddInfo(Format(SInfoRegistryVersions, [aViewLabel, JoinNames(lList)]));
        finally
          lList.Free;
        end;
      end;
    finally
      lReg.Free;
      lReg := nil;
    end;
  end;

  function TryReadRegistryView(const aViewLabel: string; aWowFlag: Cardinal): Boolean;
  var
    i: Integer;
  begin
    Result := False;
    lReg := TRegistry.Create;
    try
      lReg.Access := KEY_READ or aWowFlag;
      lReg.RootKey := HKEY_CURRENT_USER;
      if aDiagnostics <> nil then
        aDiagnostics.AddInfo(Format(SInfoRegistryView, [aViewLabel]));
      if lReg.OpenKeyReadOnly(lBaseKey) then
      begin
        lBaseFound := True;
        lReg.CloseKey; // ensure we close the base key before opening sibling keys
        lReg.Access := KEY_READ or aWowFlag;
        if lReg.OpenKeyReadOnly(lEnvKey) then
        begin
          lNames := TStringList.Create;
          try
            lReg.GetValueNames(lNames);
            for i := 0 to lNames.Count - 1 do
            begin
              lName := lNames[i];
              lValue := lReg.ReadString(lName);
              if not aEnvVars.ContainsKey(lName) then
                aEnvVars.AddOrSetValue(lName, lValue);
            end;
            if aDiagnostics <> nil then
              aDiagnostics.AddInfo(Format(SInfoEnvVarCountView, [aViewLabel, lNames.Count]));
          finally
            lNames.Free;
          end;
        end;
        lReg.CloseKey; // ensure we close any open key before opening the library key

        lHasLibPath := False;
        lReg.Access := KEY_READ or aWowFlag;
        if lReg.OpenKeyReadOnly(lLibKey) then
          lHasLibPath := lReg.ValueExists('Search Path');


        if lHasLibPath then
        begin
          aLibraryPath := lReg.ReadString('Search Path');
          aLibrarySource := TPropertySource.psRegistry;
          if aDiagnostics <> nil then
            aDiagnostics.AddInfo(Format(SInfoLibraryPathRaw, [aLibraryPath]));
          Exit(True);
        end;
      end else if aDiagnostics <> nil then
        aDiagnostics.AddInfo(Format(SInfoRegistryBaseMissing, [aViewLabel]));
    finally
      lReg.Free;
      lReg := nil;
    end;
  end;
begin
  Result := False;
  aError := '';
  aLibraryPath := '';
  aLibrarySource := TPropertySource.psUnknown;
  aEnvVars := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);

  lBaseKey := 'Software\Embarcadero\BDS\' + aDelphiVersion;
  lEnvKey := lBaseKey + '\Environment Variables';
  lLibKey := lBaseKey + '\Library\' + aPlatform;

  lHasLibPath := False;
  lBaseFound := False;
  lRegistryLibFound := False;
  if aDiagnostics <> nil then
    aDiagnostics.AddInfo(Format(SInfoRegistryBase, [lBaseKey]));

  if TryReadRegistryView('64-bit', KEY_WOW64_64KEY) then
    lRegistryLibFound := True;
  if (not lRegistryLibFound) and TryReadRegistryView('32-bit', KEY_WOW64_32KEY) then
    lRegistryLibFound := True;

  if not aEnvVars.TryGetValue('BDSUSERDIR', lBdsUserDir) then
    lBdsUserDir := System.SysUtils.GetEnvironmentVariable('BDSUSERDIR');
  if lBdsUserDir = '' then
  begin
    lAppData := System.SysUtils.GetEnvironmentVariable('APPDATA');
    if lAppData <> '' then
      lBdsUserDir := TPath.Combine(lAppData, 'Embarcadero\BDS\' + aDelphiVersion)
    else
      lBdsUserDir := TPath.Combine(TPath.GetDocumentsPath, 'Embarcadero\Studio\' + aDelphiVersion);
  end;
  EnsureEnvVar('BDSUSERDIR', lBdsUserDir, False);

  if not aEnvVars.TryGetValue('BDSCatalogRepository', lCatalogRepo) then
    lCatalogRepo := System.SysUtils.GetEnvironmentVariable('BDSCatalogRepository');
  if (lCatalogRepo = '') and (lBdsUserDir <> '') then
    lCatalogRepo := TPath.Combine(lBdsUserDir, 'CatalogRepository');
  EnsureEnvVar('BDSCatalogRepository', lCatalogRepo, False);

  if not lRegistryLibFound then
  begin
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(SInfoRegistryLibraryFallback);

    if aEnvOptionsOverride <> '' then
      lEnvOptionsFile := TPath.GetFullPath(aEnvOptionsOverride)
    else
      lEnvOptionsFile := TPath.Combine(lBdsUserDir, 'EnvOptions.proj');
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoEnvOptionsPath, [lEnvOptionsFile]));
    if (aEnvOptionsOverride <> '') and (aDiagnostics <> nil) then
      aDiagnostics.AddInfo(Format(SInfoEnvOptionsOverride, [lEnvOptionsFile]));
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoStep, ['Read EnvOptions.proj']));
    if not TryReadEnvOptionsLibraryPath(lEnvOptionsFile, aPlatform, aDelphiVersion, aEnvVars, aDiagnostics,
      aLibraryPath, aError) then
    begin
      if not lBaseFound then
      begin
        if aDiagnostics <> nil then
        begin
          LogBdsVersions('64-bit', KEY_WOW64_64KEY);
          LogBdsVersions('32-bit', KEY_WOW64_32KEY);
        end;
        aError := Format(SRegistryBaseMissingFallbackFailed, [aDelphiVersion, aError]);
      end;
      Exit(False);
    end;

    aLibrarySource := TPropertySource.psEnvOptions;
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoLibraryPathRaw, [aLibraryPath]));
  end;

  if not aEnvVars.TryGetValue('BDS', lBdsRoot) then
    lBdsRoot := System.SysUtils.GetEnvironmentVariable('BDS');
  EnsureEnvVar('BDS', lBdsRoot, False);

  if not aEnvVars.TryGetValue('BDSLIB', lBdsLib) then
    lBdsLib := System.SysUtils.GetEnvironmentVariable('BDSLIB');
  if (lBdsLib = '') and (lBdsRoot <> '') then
    lBdsLib := TPath.Combine(lBdsRoot, 'lib');
  EnsureEnvVar('BDSLIB', lBdsLib, False);

  lValue := System.SysUtils.GetEnvironmentVariable('DCC_Define');
  EnsureEnvVar('DCC_Define', lValue, True);
  lValue := System.SysUtils.GetEnvironmentVariable('DCC_UnitSearchPath');
  EnsureEnvVar('DCC_UnitSearchPath', lValue, True);
  lValue := System.SysUtils.GetEnvironmentVariable('DCC_Namespace');
  EnsureEnvVar('DCC_Namespace', lValue, True);
  Result := True;
end;

end.
