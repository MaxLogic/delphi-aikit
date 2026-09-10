unit Dak.FixInsight;

interface

uses
  System.IOUtils, System.SysUtils, System.Win.Registry,
  Winapi.Windows,
  Dak.Diagnostics, Dak.Messages, Dak.Types, Dak.Utils;

function TryResolveFixInsightExe(aDiagnostics: TDiagnostics; out aExePath: string): Boolean;

procedure ApplyFixInsightVendorExclusions(const aParams: TFixInsightParams;
  var aOptions: TFixInsightExtraOptions);

implementation

uses
  System.Classes,
  AutoFree, maxLogic.IOUtils;

function IsFlexCelProductRoot(const aRoot: string): Boolean;
var
  lInfo: string;
  lLine: string;
begin
  Result := False;
  lInfo := CombinePath([aRoot, 'tmsfetch.info.txt']);
  if not FileExists(lInfo) or not FileExists(CombinePath([aRoot, 'Source', 'Core', 'FlexCel.Core.pas'])) then
    Exit;
  for lLine in TFile.ReadAllLines(lInfo) do
    if SameText(Trim(lLine), 'product_id: tms.flexcel.vcl') then
      Exit(True);
end;

procedure AppendIgnoreMask(var aIgnore: string; const aMask: string);
var
  lItem: string;
begin
  for lItem in aIgnore.Split([';']) do
    if SameText(Trim(lItem), aMask) then
      Exit;
  if (aIgnore <> '') and not aIgnore.EndsWith(';') then
    aIgnore := aIgnore + ';';
  aIgnore := aIgnore + aMask;
end;

procedure ApplyFixInsightVendorExclusions(const aParams: TFixInsightParams;
  var aOptions: TFixInsightExtraOptions);
var
  g: TGarbos;
  lSeen: TStringList;
  lRoots: TStringList;
  lPath: string;
  lDir: string;
  lParent: string;
  lSource: string;
  lMask: string;
begin
  aOptions.fFlexCelRoots := '';
  if not aOptions.fExcludeFlexCel then
    Exit;
  GC(lSeen, TStringList.Create, g);
  GC(lRoots, TStringList.Create, g);
  lSeen.Sorted := True;
  lSeen.CaseSensitive := False;
  lRoots.Sorted := True;
  lRoots.CaseSensitive := False;
  for lPath in aParams.fUnitSearchPath + aParams.fLibraryPath do
  begin
    if (lPath = '') or not DirectoryExists(lPath) then
      Continue;
    lDir := ExcludeTrailingPathDelimiter(TPath.GetFullPath(lPath));
    while (lDir <> '') and (lSeen.IndexOf(lDir) < 0) do
    begin
      lSeen.Add(lDir);
      if IsFlexCelProductRoot(lDir) then
      begin
        lSource := CombinePath([lDir, 'Source']);
        if lRoots.IndexOf(lSource) < 0 then
          lRoots.Add(lSource);
        Break;
      end;
      lParent := ExtractFileDir(lDir);
      if SameText(lParent, lDir) then
        Break;
      lDir := lParent;
    end;
  end;
  for lSource in lRoots do
  begin
    lMask := CombinePath([lSource, '*.pas']);
    AppendIgnoreMask(aOptions.fIgnore, lMask);
    // FixInsight matches both resolved dependencies and relative DPR entries.
    if aParams.fProjectDpr <> '' then
      AppendIgnoreMask(aOptions.fIgnore, ExtractRelativePath(aParams.fProjectDpr, lMask));
  end;
  aOptions.fFlexCelRoots := String.Join(';', lRoots.ToStringArray);
end;

const
  SFixInsightExeName = 'FixInsightCL.exe';
  SFixInsightRegValue = 'Path';
  CFixInsightRegKeys: array[0..1] of string = (
    'Software\FixInsight',
    'Software\TMSSoftware\TMS FixInsight Pro'
  );

function FindInPath(const aExeName: string; out aFullPath: string): Boolean;
var
  lRequired: Cardinal;
  lBuffer: TArray<Char>;
  lFilePart: PChar;
begin
  aFullPath := '';
  lFilePart := nil;
  lRequired := SearchPath(nil, PChar(aExeName), nil, 0, nil, lFilePart);
  if lRequired = 0 then
    Exit(False);
  SetLength(lBuffer, lRequired + 1);
  lRequired := SearchPath(nil, PChar(aExeName), nil, Length(lBuffer), PChar(lBuffer), lFilePart);
  if lRequired = 0 then
    Exit(False);
  aFullPath := PChar(lBuffer);
  Result := aFullPath <> '';
end;

function BuildFromRegistry(const aBaseValue: string): string;
begin
  Result := ResolveExePathFromConfiguredValue(aBaseValue, SFixInsightExeName, '');
end;

function TryResolveFixInsightExe(aDiagnostics: TDiagnostics; out aExePath: string): Boolean;
const
  CRoots: array[0..1] of HKEY = (HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE);
  CViews: array[0..1] of Cardinal = (KEY_WOW64_64KEY, KEY_WOW64_32KEY);
var
  lReg: TRegistry;
  lValue: string;
  lCandidate: string;
  lRootIndex: Integer;
  lViewIndex: Integer;
  lKeyIndex: Integer;

  function TryReadRegistryValue(const aRegKey: string; aRootKey: HKEY; aViewFlag: Cardinal;
    out aOutValue: string): Boolean;
  begin
    Result := False;
    aOutValue := '';
    lReg := TRegistry.Create;
    try
      lReg.Access := KEY_READ or aViewFlag;
      lReg.RootKey := aRootKey;
      if lReg.OpenKeyReadOnly(aRegKey) then
      begin
        if lReg.ValueExists(SFixInsightRegValue) then
          aOutValue := lReg.ReadString(SFixInsightRegValue);
      end;
    finally
      lReg.Free;
      lReg := nil;
    end;
    Result := aOutValue <> '';
  end;
begin
  aExePath := '';
  if FindInPath(SFixInsightExeName, aExePath) then
  begin
    if aDiagnostics <> nil then
      aDiagnostics.AddInfo(Format(SInfoFixInsightPath, [aExePath]));
    Exit(True);
  end;

  for lRootIndex := 0 to High(CRoots) do
    for lViewIndex := 0 to High(CViews) do
      for lKeyIndex := 0 to High(CFixInsightRegKeys) do
      begin
        if not TryReadRegistryValue(CFixInsightRegKeys[lKeyIndex], CRoots[lRootIndex], CViews[lViewIndex], lValue) then
          Continue;
        lCandidate := BuildFromRegistry(lValue);
        if (lCandidate <> '') and FileExists(lCandidate) then
        begin
          aExePath := lCandidate;
          if aDiagnostics <> nil then
            aDiagnostics.AddInfo(Format(SInfoFixInsightPath, [aExePath]));
          Exit(True);
        end;
      end;

  Result := False;
end;

end.
