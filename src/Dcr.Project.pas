unit Dcr.Project;

interface

uses
  System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.SysUtils,
  maxLogic.StrUtils,
  Dcr.Diagnostics, Dcr.MacroExpander, Dcr.Messages, Dcr.MsBuild, Dcr.Types;

function TryBuildParams(const aOptions: TAppOptions; const aEnvVars: TDictionary<string, string>;
  const aLibraryPath: string; aLibrarySource: TPropertySource; aDiagnostics: TDiagnostics;
  out aParams: TFixInsightParams; out aError: string; out aErrorCode: Integer): Boolean;

implementation

type
  TSourceTracker = class
  private
    fSource: TPropertySource;
    fMap: TDictionary<string, TPropertySource>;
  public
    constructor Create(const aMap: TDictionary<string, TPropertySource>; aSource: TPropertySource);
    procedure OnPropertySet(const aName, aValue: string);
  end;

constructor TSourceTracker.Create(const aMap: TDictionary<string, TPropertySource>; aSource: TPropertySource);
begin
  inherited Create;
  fMap := aMap;
  fSource := aSource;
end;

procedure TSourceTracker.OnPropertySet(const aName, aValue: string);
begin
  fMap.AddOrSetValue(aName, fSource);
end;

function ContainsMacro(const aValue: string): Boolean;
begin
  Result := Pos('$(', aValue) > 0;
end;

procedure CopyProps(const aSource, aTarget: TDictionary<string, string>);
var
  lPair: TPair<string, string>;
begin
  for lPair in aSource do
    aTarget.AddOrSetValue(lPair.Key, lPair.Value);
end;

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

function NormalizeTextList(const aValue, aLabel: string; const aProps, aEnvVars: TDictionary<string, string>;
  aDiagnostics: TDiagnostics): TArray<string>;
var
  lExpanded: string;
  lParts: TArray<string>;
  lItem: string;
  lSet: THashSet<string>;
  lList: TList<string>;
begin
  lExpanded := TMacroExpander.Expand(aValue, aProps, aEnvVars, aDiagnostics, False);
  lParts := SplitList(lExpanded);
  lSet := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  lList := TList<string>.Create;
  try
    for lItem in lParts do
    begin
      if ContainsMacro(lItem) then
      begin
        if aDiagnostics <> nil then
          aDiagnostics.AddWarning(Format(SUnresolvedMacroDropped, [aLabel, lItem]));
        Continue;
      end;
      if lSet.Add(lItem) then
        lList.Add(lItem);
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
    lSet.Free;
  end;
end;

function NormalizePathList(const aValue, aProjectDir, aLabel: string; const aProps, aEnvVars: TDictionary<string, string>;
  aDiagnostics: TDiagnostics): TArray<string>;
var
  lParts: TArray<string>;
  lItem: string;
  lExpandedList: string;
  lExpanded: string;
  lSet: THashSet<string>;
  lList: TList<string>;
  lPath: string;
begin
  lExpandedList := TMacroExpander.Expand(aValue, aProps, aEnvVars, aDiagnostics, False);
  lParts := SplitList(lExpandedList);
  lSet := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  lList := TList<string>.Create;
  try
    for lItem in lParts do
    begin
      lExpanded := Trim(lItem);
      if lExpanded = '' then
        Continue;
      lPath := lExpanded;
      if ContainsMacro(lPath) then
      begin
        if aDiagnostics <> nil then
          aDiagnostics.AddWarning(Format(SUnresolvedMacroDropped, [aLabel, lPath]));
        Continue;
      end;
      if not TPath.IsPathRooted(lPath) then
        lPath := TPath.Combine(aProjectDir, lPath);
      lPath := TPath.GetFullPath(lPath);
      if not DirectoryExists(lPath) and (aDiagnostics <> nil) then
        aDiagnostics.AddMissingPath(lPath);
      if lSet.Add(lPath) then
        lList.Add(lPath);
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
    lSet.Free;
  end;
end;

function ConcatDedup(const aFirst, aSecond: TArray<string>): TArray<string>;
var
  lSet: THashSet<string>;
  lList: TList<string>;
  lItem: string;
begin
  lSet := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  lList := TList<string>.Create;
  try
    for lItem in aFirst do
      if lSet.Add(lItem) then
        lList.Add(lItem);
    for lItem in aSecond do
      if lSet.Add(lItem) then
        lList.Add(lItem);
    Result := lList.ToArray;
  finally
    lList.Free;
    lSet.Free;
  end;
end;

function ResolveFilePath(const aValue, aProjectDir: string; const aProps, aEnvVars: TDictionary<string, string>;
  aDiagnostics: TDiagnostics): string;
var
  lExpanded: string;
  lPath: string;
begin
  lExpanded := Trim(TMacroExpander.Expand(aValue, aProps, aEnvVars, aDiagnostics, False));
  if ContainsMacro(lExpanded) then
    Exit(lExpanded);
  lPath := lExpanded;
  if not TPath.IsPathRooted(lPath) then
    lPath := TPath.Combine(aProjectDir, lPath);
  Result := TPath.GetFullPath(lPath);
end;

function JoinList(const aItems: TArray<string>): string;
begin
  if Length(aItems) = 0 then
    Exit('');
  Result := String.Join(';', aItems);
end;

function GetPropertySource(const aMap: TDictionary<string, TPropertySource>; const aName: string): TPropertySource;
begin
  if not aMap.TryGetValue(aName, Result) then
    Result := TPropertySource.psUnknown;
end;

function TryBuildParams(const aOptions: TAppOptions; const aEnvVars: TDictionary<string, string>;
  const aLibraryPath: string; aLibrarySource: TPropertySource; aDiagnostics: TDiagnostics;
  out aParams: TFixInsightParams; out aError: string; out aErrorCode: Integer): Boolean;
var
  lProjectDir: string;
  lProps: TDictionary<string, string>;
  lTempProps: TDictionary<string, string>;
  lSources: TDictionary<string, TPropertySource>;
  lEvaluator: TMsBuildEvaluator;
  lTracker: TSourceTracker;
  lOptset: string;
  lOptsetPath: string;
  lMainSource: string;
  lProjectDpr: string;
  lDefine: string;
  lSearchPath: string;
  lUnitScopes: string;
  lUnitAliases: string;
  lLibPaths: TArray<string>;
  lProjPaths: TArray<string>;
  lCombinedPaths: TArray<string>;
  lAliasesProp: string;
  lPair: TPair<string, string>;
  lProjectName: string;
  lProjectFile: string;
  lProjectFullPath: string;
begin
  Result := False;
  aError := '';
  aParams := Default(TFixInsightParams);
  aErrorCode := 6;

  lProjectFullPath := TPath.GetFullPath(aOptions.fDprojPath);
  lProjectDir := TPath.GetDirectoryName(lProjectFullPath);
  lProjectFile := TPath.GetFileName(lProjectFullPath);
  lProjectName := TPath.GetFileNameWithoutExtension(lProjectFullPath);
  if aDiagnostics <> nil then
    aDiagnostics.AddInfo(Format(SInfoProjectDir, [lProjectDir]));

  lProps := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  lSources := TDictionary<string, TPropertySource>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    lProps.AddOrSetValue('Config', aOptions.fConfig);
    lProps.AddOrSetValue('Platform', aOptions.fPlatform);
    lProps.AddOrSetValue('DelphiVersion', aOptions.fDelphiVersion);
    lProps.AddOrSetValue('ProjectDir', IncludeTrailingPathDelimiter(lProjectDir));
    lProps.AddOrSetValue('PROJECTDIR', IncludeTrailingPathDelimiter(lProjectDir));
    lProps.AddOrSetValue('ProjectName', lProjectName);
    lProps.AddOrSetValue('MSBuildProjectName', lProjectName);
    lProps.AddOrSetValue('MSBuildProjectFullPath', lProjectFullPath);
    lProps.AddOrSetValue('MSBuildProjectDirectory', IncludeTrailingPathDelimiter(lProjectDir));
    lProps.AddOrSetValue('MSBuildProjectFile', lProjectFile);

    for lPair in aEnvVars do
      if not lProps.ContainsKey(lPair.Key) then
        lProps.AddOrSetValue(lPair.Key, lPair.Value);

    lTempProps := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
    try
      CopyProps(lProps, lTempProps);
      lEvaluator := TMsBuildEvaluator.Create(lTempProps, aEnvVars, aDiagnostics);
      try
        if not lEvaluator.EvaluateFile(aOptions.fDprojPath, aError) then
        begin
          aError := Format(SDprojParseError, [aError]);
          aErrorCode := 5;
          Exit(False);
        end;
      finally
        lEvaluator.Free;
      end;

      lTempProps.TryGetValue('CfgDependentOn', lOptset);
      lOptset := Trim(lOptset);
    finally
      lTempProps.Free;
    end;

    if lOptset <> '' then
    begin
      lOptsetPath := ResolveFilePath(lOptset, lProjectDir, lProps, aEnvVars, aDiagnostics);
      if aDiagnostics <> nil then
        aDiagnostics.AddInfo(Format(SInfoOptsetResolved, [lOptsetPath]));
      if not FileExists(lOptsetPath) then
      begin
        if aDiagnostics <> nil then
          aDiagnostics.AddWarning(Format(SOptsetMissing, [lOptsetPath]));
        lOptsetPath := '';
      end;
    end else
      lOptsetPath := '';

    if lOptsetPath <> '' then
    begin
      if aDiagnostics <> nil then
        aDiagnostics.AddWarning(Format(SOptsetUsing, [lOptsetPath]));
      if aDiagnostics <> nil then
        aDiagnostics.AddInfo(Format(SInfoStep, ['Evaluate option set']));
      lTracker := TSourceTracker.Create(lSources, TPropertySource.psOptset);
      try
        lEvaluator := TMsBuildEvaluator.Create(lProps, aEnvVars, aDiagnostics);
        lEvaluator.OnPropertySet := lTracker.OnPropertySet;
        try
          if not lEvaluator.EvaluateFile(lOptsetPath, aError) then
          begin
            aError := Format(SOptsetParseError, [aError]);
            aErrorCode := 5;
            Exit(False);
          end;
        finally
          lEvaluator.Free;
        end;
      finally
        lTracker.Free;
      end;
    end;

    lTracker := TSourceTracker.Create(lSources, TPropertySource.psDproj);
    try
      if aDiagnostics <> nil then
        aDiagnostics.AddInfo(Format(SInfoStep, ['Evaluate project file']));
      lEvaluator := TMsBuildEvaluator.Create(lProps, aEnvVars, aDiagnostics);
      lEvaluator.OnPropertySet := lTracker.OnPropertySet;
      try
        if not lEvaluator.EvaluateFile(aOptions.fDprojPath, aError) then
        begin
          aError := Format(SDprojParseError, [aError]);
          aErrorCode := 5;
          Exit(False);
        end;
      finally
        lEvaluator.Free;
      end;
    finally
      lTracker.Free;
    end;

    if not lProps.TryGetValue('MainSource', lMainSource) or (Trim(lMainSource) = '') then
    begin
      aError := SMainSourceMissing;
      Exit(False);
    end;

    lProjectDpr := ResolveFilePath(lMainSource, lProjectDir, lProps, aEnvVars, aDiagnostics);
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoMainSource, [lProjectDpr]));
    if ContainsMacro(lProjectDpr) or (not FileExists(lProjectDpr)) then
    begin
      aError := Format(SMainSourceMissingFile, [lProjectDpr]);
      Exit(False);
    end;

    lProps.TryGetValue('DCC_Define', lDefine);
    lProps.TryGetValue('DCC_UnitSearchPath', lSearchPath);
    lProps.TryGetValue('DCC_Namespace', lUnitScopes);
    if lProps.TryGetValue('DCC_UnitAliases', lAliasesProp) then
      lUnitAliases := lAliasesProp
    else if lProps.TryGetValue('DCC_UnitAlias', lAliasesProp) then
      lUnitAliases := lAliasesProp
    else
      lUnitAliases := '';

    lLibPaths := NormalizePathList(aLibraryPath, lProjectDir, 'LibPath', lProps, aEnvVars, aDiagnostics);
    lProjPaths := NormalizePathList(lSearchPath, lProjectDir, 'SearchPath', lProps, aEnvVars, aDiagnostics);
    lCombinedPaths := ConcatDedup(lProjPaths, lLibPaths);
    if aDiagnostics <> nil then
    begin
      aDiagnostics.AddInfo(Format(SInfoResolvedProjectSearchPath, [JoinList(lProjPaths)]));
      aDiagnostics.AddInfo(Format(SInfoResolvedLibraryPath, [JoinList(lLibPaths)]));
      aDiagnostics.AddInfo(Format(SInfoResolvedCombinedSearchPath, [JoinList(lCombinedPaths)]));
    end;

    if Length(lLibPaths) = 0 then
    begin
      aError := SLibraryPathEmpty;
      Exit(False);
    end;
    if Length(lCombinedPaths) = 0 then
    begin
      aError := SSearchPathEmpty;
      Exit(False);
    end;

    aParams.fProjectDpr := lProjectDpr;
    aParams.fDefines := NormalizeTextList(lDefine, 'Defines', lProps, aEnvVars, aDiagnostics);
    aParams.fUnitScopes := NormalizeTextList(lUnitScopes, 'UnitScopes', lProps, aEnvVars, aDiagnostics);
    aParams.fUnitAliases := NormalizeTextList(lUnitAliases, 'UnitAliases', lProps, aEnvVars, aDiagnostics);
    aParams.fUnitSearchPath := lCombinedPaths;
    aParams.fLibraryPath := lLibPaths;
    aParams.fDelphiVersion := aOptions.fDelphiVersion;
    aParams.fPlatform := aOptions.fPlatform;
    aParams.fConfig := aOptions.fConfig;
    aParams.fLibrarySource := aLibrarySource;
    aParams.fDefineSource := GetPropertySource(lSources, 'DCC_Define');
    aParams.fSearchPathSource := GetPropertySource(lSources, 'DCC_UnitSearchPath');
    aParams.fUnitScopesSource := GetPropertySource(lSources, 'DCC_Namespace');
    if lUnitAliases <> '' then
    begin
      if lProps.ContainsKey('DCC_UnitAliases') then
        aParams.fUnitAliasesSource := GetPropertySource(lSources, 'DCC_UnitAliases')
      else
        aParams.fUnitAliasesSource := GetPropertySource(lSources, 'DCC_UnitAlias');
    end else
      aParams.fUnitAliasesSource := TPropertySource.psUnknown;

    if aDiagnostics <> nil then
    begin
      aDiagnostics.AddInfo(Format(SInfoResolvedDefines, [JoinList(aParams.fDefines)]));
      aDiagnostics.AddInfo(Format(SInfoResolvedUnitScopes, [JoinList(aParams.fUnitScopes)]));
    end;

    Result := True;
  finally
    lSources.Free;
    lProps.Free;
  end;
end;

end.
