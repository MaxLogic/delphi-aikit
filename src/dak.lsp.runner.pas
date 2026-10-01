unit Dak.Lsp.Runner;

interface

uses
  Dak.Lsp.Context, Dak.Types;

type
  TLspRunnerResult = record
    fLspPath: string;
    fResponseText: string;
    fTextResponse: string;
  end;

function TryResolveDelphiLspExe(const aOptions: TAppOptions; const aContext: TLspContext;
  out aExePath: string; out aError: string): Boolean;
function TryRunLspRequest(const aOptions: TAppOptions; const aContext: TLspContext;
  out aResult: TLspRunnerResult; out aError: string): Boolean;
// Removes a stale compatibility context file and writes the canonical settings file.
function TryPrepareLspRequestFiles(const aContext: TLspContext; const aCompilerDllName: string;
  out aSettingsFilePath: string; out aError: string): Boolean;

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.JSON, System.NetEncoding,
  System.StrUtils, System.SysUtils,
  Winapi.Windows,
  maxLogic.ioUtils,
  Dak.Lsp.Protocol, Dak.Lsp.Transport,
  Dak.RadStudio.Locator,
  Dak.Utils;


function AddJsonStringPair(aObject: TJSONObject; const aName, aValue: string): TJSONObject;
begin
  aObject.AddPair(aName, aValue);
  Result := aObject;
end;


function FileExistsAt(const aPath: string): Boolean;
begin
  Result := (Trim(aPath) <> '') and FileExists(aPath);
end;

function TryFindLspExeInRoot(const aRootPath: string; out aExePath: string): Boolean;
var
  lCandidate: string;
  lRootPath: string;
begin
  Result := False;
  aExePath := '';
  lRootPath := Trim(aRootPath);
  if lRootPath = '' then
    Exit(False);
  lCandidate := TPath.Combine(lRootPath, 'DelphiLSP.exe');
  if FileExists(lCandidate) then
  begin
    aExePath := TPath.GetFullPath(lCandidate);
    Exit(True);
  end;
  lCandidate := TPath.Combine(lRootPath, 'bin64\DelphiLSP.exe');
  if FileExists(lCandidate) then
  begin
    aExePath := TPath.GetFullPath(lCandidate);
    Exit(True);
  end;
  lCandidate := TPath.Combine(lRootPath, 'bin\DelphiLSP.exe');
  if FileExists(lCandidate) then
  begin
    aExePath := TPath.GetFullPath(lCandidate);
    Exit(True);
  end;
end;

function LspOperationName(aOperation: TLspOperation): string;
begin
  case aOperation of
    TLspOperation.loDefinition:
      Result := 'definition';
    TLspOperation.loHover:
      Result := 'hover';
    TLspOperation.loSymbols:
      Result := 'symbols';
    TLspOperation.loProbe:
      Result := 'probe';
  else
    Result := 'unknown';
  end;
end;

function LspRequestMethod(aOperation: TLspOperation): string;
begin
  case aOperation of
    TLspOperation.loDefinition:
      Result := 'textDocument/definition';
    TLspOperation.loHover:
      Result := 'textDocument/hover';
    TLspOperation.loSymbols:
      Result := 'textDocument/documentSymbol';
  else
    Result := '';
  end;
end;

function LspCapabilityName(aOperation: TLspOperation): string;
begin
  case aOperation of
    TLspOperation.loSymbols:
      Result := 'documentSymbolProvider';
  else
    Result := '';
  end;
end;

function BuildAdvertisedCapabilitiesText(const aInitResponse: TJSONObject): string;
var
  lCapabilitiesObject: TJSONObject;
  lPair: TJSONPair;
  lResultObject: TJSONObject;
  lValues: TList<string>;
begin
  Result := '';
  if not (aInitResponse.Values['result'] is TJSONObject) then
    Exit('');
  lResultObject := aInitResponse.Values['result'] as TJSONObject;
  if not (lResultObject.Values['capabilities'] is TJSONObject) then
    Exit('');
  lCapabilitiesObject := lResultObject.Values['capabilities'] as TJSONObject;
  lValues := TList<string>.Create;
  try
    for lPair in lCapabilitiesObject do
    begin
      if (lPair.JsonValue <> nil) and not (lPair.JsonValue is TJSONFalse) then
        lValues.Add(lPair.JsonString.Value);
    end;
    Result := String.Join(', ', lValues.ToArray);
  finally
    lValues.Free;
  end;
end;

function ProbeModeName(aMode: TLspProbeMode): string;
begin
  case aMode of
    TLspProbeMode.lpmContextFile:
      Result := 'contextFile';
    TLspProbeMode.lpmSettingsFile:
      Result := 'settingsFile';
  else
    Result := 'unknown';
  end;
end;

function BuildAdvertisedCapabilitiesArray(const aInitResponse: TJSONObject): TJSONArray;
var
  lAdvertised: string;
  lArray: TJSONArray;
  lItem: string;
begin
  lArray := TJSONArray.Create;
  lAdvertised := BuildAdvertisedCapabilitiesText(aInitResponse);
  if lAdvertised <> '' then
    for lItem in lAdvertised.Split([',']) do
      lArray.Add(Trim(lItem));
  Result := lArray;
end;

function CloneJsonObject(aValue: TJSONValue): TJSONObject;
begin
  Result := nil;
  if aValue = nil then
    Exit(nil);
  Result := TJSONObject.ParseJSONValue(aValue.ToJSON) as TJSONObject;
end;

function BuildProbeModeObject(const aInitResponse: TJSONObject; aMode: TLspProbeMode; const aSettingsFilePath: string;
  aShowInitOptions: Boolean; aInitializationOptions, aConfigurationParams: TJSONObject): TJSONObject;
var
  lCapabilities: TJSONObject;
begin
  Result := TJSONObject.Create;
  AddJsonStringPair(Result, 'mode', ProbeModeName(aMode));
  Result.AddPair('advertisedCapabilities', BuildAdvertisedCapabilitiesArray(aInitResponse));
  if (aInitResponse.Values['result'] is TJSONObject) and
    ((aInitResponse.Values['result'] as TJSONObject).Values['capabilities'] is TJSONObject) then
    lCapabilities := CloneJsonObject((aInitResponse.Values['result'] as TJSONObject).Values['capabilities'])
  else
    lCapabilities := TJSONObject.Create;
  Result.AddPair('capabilities', lCapabilities);
  if aSettingsFilePath <> '' then
    AddJsonStringPair(Result, 'settingsFile', aSettingsFilePath);
  if aShowInitOptions and (aInitializationOptions <> nil) then
    Result.AddPair('initializationOptions', CloneJsonObject(aInitializationOptions));
  if aShowInitOptions and (aConfigurationParams <> nil) then
    Result.AddPair('configurationNotification', CloneJsonObject(aConfigurationParams));
end;

function BuildProbeEnvelope(const aContext: TLspContext; const aLspPath: string; aModes: TJSONArray;
  const aExtraWarnings: TArray<string>): string;
var
  lExtraWarning: string;
  lLspObject: TJSONObject;
  lWarnings: TJSONArray;
  lProjectObject: TJSONObject;
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  try
    AddJsonStringPair(lRoot, 'operation', 'probe');
    lProjectObject := TJSONObject.Create;
    AddJsonStringPair(lProjectObject, 'path', aContext.fProjectPath);
    AddJsonStringPair(lProjectObject, 'platform', aContext.fParams.fPlatform);
    AddJsonStringPair(lProjectObject, 'config', aContext.fParams.fConfig);
    AddJsonStringPair(lProjectObject, 'contextMode', 'full');
    lRoot.AddPair('project', lProjectObject);

    lLspObject := TJSONObject.Create;
    AddJsonStringPair(lLspObject, 'path', aLspPath);
    AddJsonStringPair(lLspObject, 'cleanup', 'controlled-termination');
    AddJsonStringPair(lLspObject, 'settingsAcceptance', 'unverified');
    lRoot.AddPair('lsp', lLspObject);
    lRoot.AddPair('result', TJSONObject.Create.AddPair('modes', TJSONObject.ParseJSONValue(aModes.ToJSON) as TJSONArray));
    lWarnings := TJSONArray.Create(cLspCleanupWarning, cLspSettingsWarning);
    for lExtraWarning in aExtraWarnings do
      lWarnings.Add(lExtraWarning);
    lRoot.AddPair('warnings', lWarnings);
    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;

function JsonArrayToDelimitedText(aArray: TJSONArray): string;
var
  lValues: TList<string>;
  lValue: TJSONValue;
begin
  lValues := TList<string>.Create;
  try
    if aArray <> nil then
      for lValue in aArray do
        lValues.Add(lValue.Value);
    Result := String.Join(', ', lValues.ToArray);
  finally
    lValues.Free;
  end;
end;

function BuildProbeText(const aModes: TJSONArray; aShowInitOptions: Boolean;
  const aExtraWarnings: TArray<string>): string;
var
  lBuilder: TStringBuilder;
  lExtraWarning: string;
  lModeObject: TJSONObject;
  i: Integer;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine(cLspCleanupWarning);
    lBuilder.AppendLine(cLspSettingsWarning);
    for lExtraWarning in aExtraWarnings do
      lBuilder.AppendLine(lExtraWarning);
    for i := 0 to aModes.Count - 1 do
    begin
      lModeObject := aModes.Items[i] as TJSONObject;
      if i > 0 then
        lBuilder.AppendLine;
      lBuilder.AppendLine('mode: ' + lModeObject.GetValue<string>('mode', ''));
      if lModeObject.Values['settingsFile'] <> nil then
        lBuilder.AppendLine('settingsFile: ' + lModeObject.GetValue<string>('settingsFile', ''));
      lBuilder.AppendLine('advertisedCapabilities: ' +
        JsonArrayToDelimitedText(lModeObject.GetValue<TJSONArray>('advertisedCapabilities')));
      if aShowInitOptions and (lModeObject.Values['initializationOptions'] <> nil) then
        lBuilder.AppendLine('initializationOptions: ' + lModeObject.Values['initializationOptions'].ToJSON);
      if aShowInitOptions and (lModeObject.Values['configurationNotification'] <> nil) then
        lBuilder.AppendLine('configurationNotification: ' + lModeObject.Values['configurationNotification'].ToJSON);
    end;
    Result := lBuilder.ToString.TrimRight;
  finally
    lBuilder.Free;
  end;
end;

function ProbeModesFromOptions(const aOptions: TAppOptions): TArray<TLspProbeMode>;
begin
  Result := nil;
  if TLspProbeMode.lpmContextFile in aOptions.fLspProbeModes then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := TLspProbeMode.lpmContextFile;
  end;
  if TLspProbeMode.lpmSettingsFile in aOptions.fLspProbeModes then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := TLspProbeMode.lpmSettingsFile;
  end;
  if Length(Result) = 0 then
  begin
    SetLength(Result, 2);
    Result[0] := TLspProbeMode.lpmContextFile;
    Result[1] := TLspProbeMode.lpmSettingsFile;
  end;
end;

function TryRunLspProbe(const aOptions: TAppOptions; const aContext: TLspContext; const aLspPath,
  aCompilerDllName, aCompilerDllWarning: string; out aResult: TLspRunnerResult; out aError: string): Boolean;
var
  lClient: TLspJsonRpcClient;
  lConfigObject: TJSONObject;
  lExtraWarnings: TArray<string>;
  lConfigParams: string;
  lError: string;
  lInitOptions: TJSONObject;
  lInitResponse: TJSONObject;
  lMode: TLspProbeMode;
  lModeObject: TJSONObject;
  lModes: TJSONArray;
  lSettingsFilePath: string;
begin
  Result := False;
  aResult := Default(TLspRunnerResult);
  aError := '';
  lExtraWarnings := [];
  lModes := TJSONArray.Create;
  try
    for lMode in ProbeModesFromOptions(aOptions) do
    begin
      lSettingsFilePath := '';
      lInitResponse := nil;
      lInitOptions := nil;
      lConfigObject := nil;
      lClient := TLspJsonRpcClient.Create;
      try
        if lMode = TLspProbeMode.lpmSettingsFile then
        begin
          if not TryWriteOfficialLspSettingsFile(aContext, aCompilerDllName, lSettingsFilePath, lError) then
          begin
            aError := lError;
            Exit(False);
          end;
          // Only the settings handshake carries "dllname"; contextFile mode never uses it.
          if aCompilerDllWarning <> '' then
            lExtraWarnings := [aCompilerDllWarning];
          lInitOptions := BuildSettingsFileInitializeOptions(aContext, lSettingsFilePath);
        end else begin
          if not TryWriteLspContextFile(aContext, lError) then
          begin
            aError := lError;
            Exit(False);
          end;
          lInitOptions := BuildContextFileInitializeOptions(aContext);
        end;

        if not lClient.Start(aLspPath, '', aContext.fDakLspRoot,
          TPath.Combine(aContext.fLogsDir, 'DelphiLSP.' + ProbeModeName(lMode) + '.stderr.log'),
          aContext.fEnvironmentBlock, lError) then
        begin
          aError := lClient.StopAfterFailure(lError);
          Exit(False);
        end;

        if not lClient.SendRequest(1, 'initialize', BuildInitializeParamsWithOptions(aContext,
          CloneJsonObject(lInitOptions)), lInitResponse, lError) then
        begin
          aError := lClient.StopAfterFailure(BuildLspStageError('probe initialize ' + ProbeModeName(lMode), lError));
          Exit(False);
        end;

        if not lClient.SendNotification('initialized', '{}', lError) then
        begin
          aError := lClient.StopAfterFailure(BuildLspStageError('initialized notification', lError));
          Exit(False);
        end;

        if lMode = TLspProbeMode.lpmSettingsFile then
        begin
          lConfigParams := BuildSettingsConfigurationParams(lSettingsFilePath);
          lConfigObject := TJSONObject.ParseJSONValue(lConfigParams) as TJSONObject;
          if not lClient.SendNotification('workspace/didChangeConfiguration', lConfigParams, lError) then
          begin
            aError := lClient.StopAfterFailure(BuildLspStageError('workspace/didChangeConfiguration notification',
              lError));
            Exit(False);
          end;
        end;

        if not lClient.StopProcessTree(lError) then
        begin
          aError := lError;
          Exit(False);
        end;

        lModeObject := BuildProbeModeObject(lInitResponse, lMode, lSettingsFilePath, aOptions.fLspShowInitOptions,
          lInitOptions, lConfigObject);
        lModes.AddElement(lModeObject);
      finally
        lConfigObject.Free;
        lInitOptions.Free;
        lInitResponse.Free;
        lClient.Free;
      end;
    end;

    aResult.fLspPath := aLspPath;
    aResult.fResponseText := BuildProbeEnvelope(aContext, aLspPath, lModes, lExtraWarnings);
    aResult.fTextResponse := BuildProbeText(lModes, aOptions.fLspShowInitOptions, lExtraWarnings);
    Result := True;
  finally
    lModes.Free;
  end;
end;

function BuildUnsupportedCapabilityError(const aInitResponse: TJSONObject; const aContext: TLspContext;
  const aLspPath: string; aOperation: TLspOperation; const aReason: string): string;
var
  lAdvertised: string;
  lFallback: string;
  lRequestMethod: string;
begin
  lRequestMethod := LspRequestMethod(aOperation);
  lAdvertised := BuildAdvertisedCapabilitiesText(aInitResponse);
  lFallback := '';
  Result := Format('Installed DelphiLSP at %s for Delphi %s does not advertise support for %s (%s).',
    [aLspPath, aContext.fDelphiVersion, lRequestMethod, aReason]);
  if lAdvertised <> '' then
    Result := Result + ' Advertised capabilities: ' + lAdvertised + '.';
  Result := Result + lFallback;
end;

function TryEnsureOperationSupported(const aInitResponse: TJSONObject; const aContext: TLspContext;
  const aLspPath: string; aOperation: TLspOperation; out aError: string): Boolean;
var
  lCapabilitiesObject: TJSONObject;
  lCapabilityName: string;
  lCapabilityValue: TJSONValue;
  lResultObject: TJSONObject;
begin
  aError := '';
  lCapabilityName := LspCapabilityName(aOperation);
  if lCapabilityName = '' then
    Exit(True);

  if not (aInitResponse.Values['result'] is TJSONObject) then
  begin
    aError := BuildUnsupportedCapabilityError(aInitResponse, aContext, aLspPath, aOperation,
      'initialize result omitted capabilities');
    Exit(False);
  end;
  lResultObject := aInitResponse.Values['result'] as TJSONObject;
  if not (lResultObject.Values['capabilities'] is TJSONObject) then
  begin
    aError := BuildUnsupportedCapabilityError(aInitResponse, aContext, aLspPath, aOperation,
      'initialize result omitted capabilities');
    Exit(False);
  end;
  lCapabilitiesObject := lResultObject.Values['capabilities'] as TJSONObject;
  lCapabilityValue := lCapabilitiesObject.Values[lCapabilityName];
  if (lCapabilityValue <> nil) and not (lCapabilityValue is TJSONFalse) then
    Exit(True);

  aError := BuildUnsupportedCapabilityError(aInitResponse, aContext, aLspPath, aOperation,
    Format('missing %s in initialize capabilities', [lCapabilityName]));
  Result := False;
end;

function TryResolveRequestFilePath(const aOptions: TAppOptions; out aFilePath: string; out aError: string): Boolean;
begin
  aFilePath := '';
  aError := '';
  if not TryResolveAbsolutePath(aOptions.fLspFilePath, aFilePath, aError) then
    Exit(False);
  if not FileExists(aFilePath) then
  begin
    aError := 'File not found: ' + aFilePath;
    Exit(False);
  end;
  Result := True;
end;

function TryResolveConfiguredLspPath(const aValue: string; out aResolvedPath: string; out aError: string): Boolean;
var
  lRootPath: string;
begin
  aResolvedPath := '';
  aError := '';
  if not TryResolveAbsolutePath(aValue, lRootPath, aError) then
    Exit(False);
  if DirectoryExists(lRootPath) then
  begin
    if TryFindLspExeInRoot(lRootPath, aResolvedPath) then
      Exit(True);
    aResolvedPath := TPath.GetFullPath(TPath.Combine(lRootPath, 'DelphiLSP.exe'));
    Exit(True);
  end;
  aResolvedPath := TPath.GetFullPath(lRootPath);
  Result := True;
end;

function TryResolveDelphiLspExe(const aOptions: TAppOptions; const aContext: TLspContext;
  out aExePath: string; out aError: string): Boolean;
var
  lCandidate: string;
  lCandidates: TArray<string>;
  lTried: TList<string>;

  function TryCandidate(const aCandidate: string): Boolean;
  begin
    Result := False;
    lCandidate := Trim(aCandidate);
    if lCandidate = '' then
      Exit;
    lCandidate := TPath.GetFullPath(lCandidate);
    if not lTried.Contains(lCandidate) then
      lTried.Add(lCandidate);
    if FileExists(lCandidate) then
    begin
      aExePath := lCandidate;
      Exit(True);
    end;
  end;
begin
  Result := False;
  aExePath := '';
  aError := '';

  if aOptions.fHasLspPath or (Trim(aOptions.fLspPath) <> '') then
  begin
    if not TryResolveConfiguredLspPath(aOptions.fLspPath, lCandidate, aError) then
      Exit(False);
    if FileExistsAt(lCandidate) then
    begin
      aExePath := lCandidate;
      Exit(True);
    end;
    aError := 'DelphiLSP.exe not found at: ' + lCandidate + '. Use --lsp-path to specify the correct path.';
    Exit(False);
  end;

  lTried := TList<string>.Create;
  try
    lCandidates := BuildDelphiLspCandidatePaths(aContext.fDelphiVersion, aContext.fEnvironmentBlock);
    for lCandidate in lCandidates do
      if TryCandidate(lCandidate) then
        Exit(True);

    aError := 'DelphiLSP.exe not found for Delphi ' + aContext.fDelphiVersion + '. Tried: ' +
      String.Join('; ', lTried.ToArray) + '. Use --lsp-path to specify the correct path.';
  finally
    lTried.Free;
  end;
end;

function TryPrepareLspRequestFiles(const aContext: TLspContext; const aCompilerDllName: string;
  out aSettingsFilePath: string; out aError: string): Boolean;
begin
  aSettingsFilePath := '';
  // Normal requests use only the canonical settings file; a stale context file
  // left by probe mode must not be mistaken for current input.
  Result := TryDeleteLspContextFile(aContext, aError) and
    TryWriteCanonicalLspSettingsFile(aContext, aCompilerDllName, aSettingsFilePath, aError);
end;

function TryRunLspRequest(const aOptions: TAppOptions; const aContext: TLspContext;
  out aResult: TLspRunnerResult; out aError: string): Boolean;
var
  lClient: TLspJsonRpcClient;
  lCompilerDllName: string;
  lCompilerDllWarning: string;
  lError: string;
  lExtraWarnings: TArray<string>;
  lInitResponse: TJSONObject;
  lLspPath: string;
  lNotification: TLspWireMessage;
  lOperationName: string;
  lSettingsFilePath: string;
  lRequestFilePath: string;
  lRequestMethod: string;
  lRequestParams: string;
  lRequestResponse: TJSONObject;
  lResponseText: string;
begin
  Result := False;
  aResult := Default(TLspRunnerResult);
  aError := '';
  lInitResponse := nil;
  lRequestResponse := nil;

  if not TryResolveDelphiLspExe(aOptions, aContext, lLspPath, aError) then
    Exit(False);
  // An unresolved compiler DLL never refuses the query: the settings omit
  // "dllname" as before, and the result names the reason as a warning.
  lCompilerDllWarning := ResolveLspCompilerDllForRequest(lLspPath, aContext.fParams.fPlatform, lCompilerDllName);
  if aOptions.fLspOperation = TLspOperation.loProbe then
  begin
    if not TryRunLspProbe(aOptions, aContext, lLspPath, lCompilerDllName, lCompilerDllWarning, aResult, aError) then
      Exit(False);
    Exit(True);
  end;

  if not TryResolveRequestFilePath(aOptions, lRequestFilePath, aError) then
    Exit(False);

  lOperationName := LspOperationName(aOptions.fLspOperation);
  lRequestMethod := LspRequestMethod(aOptions.fLspOperation);
  if lRequestMethod = '' then
  begin
    aError := 'Unsupported lsp operation.';
    Exit(False);
  end;

  if not TryPrepareLspRequestFiles(aContext, lCompilerDllName, lSettingsFilePath, aError) then
    Exit(False);

  lClient := TLspJsonRpcClient.Create;
  try
    lError := '';
    if not lClient.Start(lLspPath, '', aContext.fDakLspRoot,
      TPath.Combine(aContext.fLogsDir, 'DelphiLSP.stderr.log'), aContext.fEnvironmentBlock, lError) then
    begin
      aError := lClient.StopAfterFailure(lError);
      Exit(False);
    end;

    if not lClient.SendRequest(1, 'initialize', BuildRequestInitializeParams(aContext, lSettingsFilePath),
      lInitResponse, lError) then
    begin
      aError := lClient.StopAfterFailure(BuildLspStageError('initialize', lError));
      Exit(False);
    end;

    if not TryEnsureOperationSupported(lInitResponse, aContext, lLspPath, aOptions.fLspOperation, lError) then
    begin
      aError := lClient.StopAfterFailure(lError);
      Exit(False);
    end;

    for lNotification in BuildRequestNotifications(lSettingsFilePath, lRequestFilePath) do
      if not lClient.SendNotification(lNotification.fMethod, lNotification.fParams, lError) then
      begin
        aError := lClient.StopAfterFailure(BuildLspStageError(lNotification.fMethod + ' notification', lError));
        Exit(False);
      end;
    lRequestParams := BuildRequestParams(aOptions, FilePathToURL(lRequestFilePath));

    if not lClient.SendRequest(2, lRequestMethod, lRequestParams, lRequestResponse, lError) then
    begin
      aError := lClient.StopAfterFailure(BuildLspStageError(lOperationName + ' request', lError));
      Exit(False);
    end;

    if not lClient.StopProcessTree(lError) then
    begin
      aError := lError;
      Exit(False);
    end;

    if not TryBuildOperationResultText(aOptions, lRequestFilePath, lRequestResponse, lResponseText, aError) then
      Exit(False);
    aResult.fLspPath := lLspPath;
    if lCompilerDllWarning <> '' then
      lExtraWarnings := [lCompilerDllWarning]
    else
      lExtraWarnings := [];
    aResult.fResponseText := BuildOperationEnvelope(aOptions, aContext, lLspPath, lOperationName, lRequestFilePath,
      lResponseText, lExtraWarnings);
    aResult.fTextResponse := BuildOperationText(aOptions, aContext, lLspPath, lOperationName, lRequestFilePath,
      lResponseText, lExtraWarnings);
    Result := True;
  finally
    lRequestResponse.Free;
    lInitResponse.Free;
    lClient.Free;
  end;
end;

end.
