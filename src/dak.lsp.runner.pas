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

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.JSON, System.NetEncoding, System.SysUtils,
  Winapi.Windows,
  maxLogic.ioUtils,
  Dak.Utils;

type
  TLspJsonRpcClient = class
  private
    fInput: THandleStream;
    fOutput: THandleStream;
    fProcessHandle: THandle;
    fStdErrHandle: THandle;
    fThreadHandle: THandle;
    function ReadLine(out aLine: string; out aError: string): Boolean;
    function ReadMessage(out aBody: string; out aError: string): Boolean;
    function WriteMessage(const aBody: string; out aError: string): Boolean;
  public
    destructor Destroy; override;
    function SendNotification(const aMethod, aParamsJson: string; out aError: string): Boolean;
    function SendRequest(aId: Integer; const aMethod, aParamsJson: string; out aResponse: TJSONObject;
      out aError: string): Boolean;
    function ShutdownAndExit(out aError: string): Boolean;
    function Start(const aExePath, aArguments, aWorkDir, aStdErrPath: string; out aError: string): Boolean;
  end;

function AddJsonStringPair(aObject: TJSONObject; const aName, aValue: string): TJSONObject;
begin
  aObject.AddPair(aName, aValue);
  Result := aObject;
end;

function BuildDerivedLspRoots(const aContext: TLspContext): TArray<string>;
var
  lProgramFiles: string;
  lProgramFilesX86: string;
  lRoots: TList<string>;

  procedure AddRoot(const aRoot: string);
  var
    lRoot: string;
  begin
    lRoot := Trim(aRoot);
    if lRoot = '' then
      Exit;
    lRoot := TPath.GetFullPath(lRoot);
    if lRoots.Contains(lRoot) then
      Exit;
    lRoots.Add(lRoot);
  end;
begin
  lRoots := TList<string>.Create;
  try
    AddRoot(GetEnvironmentVariable('BDS'));

    lProgramFilesX86 := Trim(GetEnvironmentVariable('ProgramFiles(x86)'));
    if lProgramFilesX86 <> '' then
    begin
      AddRoot(TPath.Combine(lProgramFilesX86, 'Embarcadero\Studio\' + aContext.fDelphiVersion));
      AddRoot(TPath.Combine(lProgramFilesX86, 'Embarcadero\RAD Studio\' + aContext.fDelphiVersion));
    end;

    lProgramFiles := Trim(GetEnvironmentVariable('ProgramFiles'));
    if lProgramFiles <> '' then
    begin
      AddRoot(TPath.Combine(lProgramFiles, 'Embarcadero\Studio\' + aContext.fDelphiVersion));
      AddRoot(TPath.Combine(lProgramFiles, 'Embarcadero\RAD Studio\' + aContext.fDelphiVersion));
    end;

    Result := lRoots.ToArray;
  finally
    lRoots.Free;
  end;
end;

function BuildContextFileInitializeOptions(const aContext: TLspContext): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddJsonStringPair(Result, 'contextFile', aContext.fContextFilePath);
  AddJsonStringPair(Result, 'contextFileUri', FilePathToURL(aContext.fContextFilePath));
  AddJsonStringPair(Result, 'logsDir', aContext.fLogsDir);
end;

function BuildSettingsFileInitializeOptions(const aContext: TLspContext; const aSettingsFilePath: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  AddJsonStringPair(Result, 'settingsFile', aSettingsFilePath);
  AddJsonStringPair(Result, 'settingsFileUri', FilePathToURL(aSettingsFilePath));
  AddJsonStringPair(Result, 'logsDir', aContext.fLogsDir);
end;

function BuildInitializeParamsWithOptions(const aContext: TLspContext; aInitializeOptions: TJSONObject): string;
var
  lClientInfo: TJSONObject;
  lFolders: TJSONArray;
  lParams: TJSONObject;
  lWorkspaceFolder: TJSONObject;
begin
  lParams := TJSONObject.Create;
  try
    lParams.AddPair('processId', TJSONNumber.Create(GetCurrentProcessId));
    lParams.AddPair('rootUri', FilePathToURL(aContext.fProjectDir));
    lParams.AddPair('capabilities', TJSONObject.Create);

    lClientInfo := TJSONObject.Create;
    lClientInfo.AddPair('name', 'DelphiAIKit');
    lParams.AddPair('clientInfo', lClientInfo);

    lFolders := TJSONArray.Create;
    lWorkspaceFolder := TJSONObject.Create;
    AddJsonStringPair(lWorkspaceFolder, 'uri', FilePathToURL(aContext.fProjectDir));
    AddJsonStringPair(lWorkspaceFolder, 'name', aContext.fProjectName);
    lFolders.AddElement(lWorkspaceFolder);
    lParams.AddPair('workspaceFolders', lFolders);

    lParams.AddPair('initializationOptions', aInitializeOptions);

    Result := lParams.ToJSON;
  finally
    lParams.Free;
  end;
end;

function BuildInitializeParams(const aContext: TLspContext): string;
begin
  Result := BuildInitializeParamsWithOptions(aContext, BuildContextFileInitializeOptions(aContext));
end;

function BuildProbeConfigurationParams(const aSettingsFilePath: string): string;
var
  lRoot: TJSONObject;
  lSettings: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  try
    lSettings := TJSONObject.Create;
    AddJsonStringPair(lSettings, 'settingsFile', aSettingsFilePath);
    AddJsonStringPair(lSettings, 'settingsFileUri', FilePathToURL(aSettingsFilePath));
    lRoot.AddPair('settings', lSettings);
    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;


function BuildOperationEnvelope(const aOptions: TAppOptions; const aContext: TLspContext; const aLspPath,
  aOperationName: string; const aRequestFilePath: string; const aRawResultJson: string): string;
var
  lJsonValue: TJSONValue;
  lLspObject: TJSONObject;
  lProjectObject: TJSONObject;
  lQueryObject: TJSONObject;
  lRoot: TJSONObject;
  lWarnings: TJSONArray;
begin
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('operation', aOperationName);

    lProjectObject := TJSONObject.Create;
    AddJsonStringPair(lProjectObject, 'path', aContext.fProjectPath);
    AddJsonStringPair(lProjectObject, 'platform', aContext.fParams.fPlatform);
    AddJsonStringPair(lProjectObject, 'config', aContext.fParams.fConfig);
    AddJsonStringPair(lProjectObject, 'contextMode', 'full');
    lRoot.AddPair('project', lProjectObject);

    lQueryObject := TJSONObject.Create;
    if aOptions.fLspOperation = TLspOperation.loSymbols then
    begin
      AddJsonStringPair(lQueryObject, 'file', aRequestFilePath);
      AddJsonStringPair(lQueryObject, 'query', aOptions.fLspQuery);
      lQueryObject.AddPair('limit', TJSONNumber.Create(aOptions.fLspLimit));
    end else
    begin
      AddJsonStringPair(lQueryObject, 'file', aRequestFilePath);
      lQueryObject.AddPair('line', TJSONNumber.Create(aOptions.fLspLine));
      lQueryObject.AddPair('col', TJSONNumber.Create(aOptions.fLspCol));
    end;
    lRoot.AddPair('query', lQueryObject);

    lLspObject := TJSONObject.Create;
    AddJsonStringPair(lLspObject, 'path', aLspPath);
    lRoot.AddPair('lsp', lLspObject);

    lJsonValue := TJSONObject.ParseJSONValue(aRawResultJson);
    if lJsonValue = nil then
      lRoot.AddPair('result', aRawResultJson)
    else
      lRoot.AddPair('result', lJsonValue);

    lWarnings := TJSONArray.Create;
    lRoot.AddPair('warnings', lWarnings);

    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;

function BuildHoverText(const aResultJson: string): string; forward;

function BuildOperationText(const aOptions: TAppOptions; const aContext: TLspContext; const aLspPath,
  aOperationName: string; const aRequestFilePath: string; const aRawResultJson: string): string;
var
  lLines: TStringBuilder;
begin
  if aOptions.fLspOperation = TLspOperation.loHover then
    Exit(BuildHoverText(aRawResultJson));

  lLines := TStringBuilder.Create;
  try
    lLines.AppendLine('operation: ' + aOperationName);
    lLines.AppendLine('project: ' + aContext.fProjectPath);
    if aOptions.fLspOperation = TLspOperation.loSymbols then
    begin
      lLines.AppendLine('file: ' + aRequestFilePath);
      lLines.AppendLine('query: ' + aOptions.fLspQuery);
      lLines.AppendLine('limit: ' + IntToStr(aOptions.fLspLimit));
    end else
      lLines.AppendLine(Format('query: %s:%d:%d', [aRequestFilePath, aOptions.fLspLine, aOptions.fLspCol]));
    lLines.AppendLine('lsp: ' + aLspPath);
    lLines.Append('result: ' + aRawResultJson);
    Result := lLines.ToString;
  finally
    lLines.Free;
  end;
end;

function BuildPositionParams(const aOptions: TAppOptions; const aFileUri: string): string;
var
  lContextObject: TJSONObject;
  lParams: TJSONObject;
  lPositionObject: TJSONObject;
  lTextDocumentObject: TJSONObject;
begin
  lParams := TJSONObject.Create;
  try
    lTextDocumentObject := TJSONObject.Create;
    AddJsonStringPair(lTextDocumentObject, 'uri', aFileUri);
    lParams.AddPair('textDocument', lTextDocumentObject);

    lPositionObject := TJSONObject.Create;
    lPositionObject.AddPair('line', TJSONNumber.Create(aOptions.fLspLine - 1));
    lPositionObject.AddPair('character', TJSONNumber.Create(aOptions.fLspCol - 1));
    lParams.AddPair('position', lPositionObject);

    Result := lParams.ToJSON;
  finally
    lParams.Free;
  end;
end;

function BuildDocumentSymbolParams(const aFileUri: string): string;
var
  lParams: TJSONObject;
  lTextDocumentObject: TJSONObject;
begin
  lParams := TJSONObject.Create;
  try
    lTextDocumentObject := TJSONObject.Create;
    AddJsonStringPair(lTextDocumentObject, 'uri', aFileUri);
    lParams.AddPair('textDocument', lTextDocumentObject);
    Result := lParams.ToJSON;
  finally
    lParams.Free;
  end;
end;

function BuildRequestParams(const aOptions: TAppOptions; const aFileUri: string): string;
begin
  if aOptions.fLspOperation in [TLspOperation.loDefinition, TLspOperation.loHover] then
    Exit(BuildPositionParams(aOptions, aFileUri));
  if aOptions.fLspOperation = TLspOperation.loSymbols then
    Exit(BuildDocumentSymbolParams(aFileUri));
  Result := '{}';
end;

function BuildDidOpenParams(const aFilePath: string): string;
var
  lParams: TJSONObject;
  lTextDocumentObject: TJSONObject;
begin
  lParams := TJSONObject.Create;
  try
    lTextDocumentObject := TJSONObject.Create;
    AddJsonStringPair(lTextDocumentObject, 'uri', FilePathToURL(aFilePath));
    AddJsonStringPair(lTextDocumentObject, 'languageId', 'delphi');
    lTextDocumentObject.AddPair('version', TJSONNumber.Create(1));
    AddJsonStringPair(lTextDocumentObject, 'text', TFile.ReadAllText(aFilePath));
    lParams.AddPair('textDocument', lTextDocumentObject);
    Result := lParams.ToJSON;
  finally
    lParams.Free;
  end;
end;

function BuildResponseError(const aStage: string; const aResponse: TJSONObject): string;
var
  lCode: string;
  lErrorObject: TJSONObject;
  lMessage: string;
begin
  if not (aResponse.Values['error'] is TJSONObject) then
    Exit('DelphiLSP ' + aStage + ' failed.');
  lErrorObject := aResponse.Values['error'] as TJSONObject;
  lCode := lErrorObject.GetValue<string>('code', '');
  lMessage := lErrorObject.GetValue<string>('message', '');
  if lCode <> '' then
    Result := Format('DelphiLSP %s failed (%s): %s', [aStage, lCode, lMessage])
  else
    Result := Format('DelphiLSP %s failed: %s', [aStage, lMessage]);
end;

function ExtractRawResultText(aResponse: TJSONObject): string;
var
  lResultValue: TJSONValue;
begin
  lResultValue := aResponse.Values['result'];
  if lResultValue = nil then
    Exit('null');
  Result := lResultValue.ToJSON;
end;

function FileExistsAt(const aPath: string): Boolean;
begin
  Result := (Trim(aPath) <> '') and FileExists(aPath);
end;

function TryDecodeFileUri(const aUri: string; out aFilePath: string): Boolean;
var
  lAuthority: string;
  lDecodedPath: string;
  lEncodedPath: string;
  lPathStart: Integer;
  lUri: string;
begin
  aFilePath := '';
  lUri := Trim(aUri);
  if not SameText(Copy(lUri, 1, 7), 'file://') then
    Exit(False);

  lUri := Copy(lUri, 8, MaxInt);
  lPathStart := Pos('/', lUri);
  if lPathStart = 0 then
    Exit(False);

  lAuthority := Copy(lUri, 1, lPathStart - 1);
  lEncodedPath := Copy(lUri, lPathStart, MaxInt);
  lDecodedPath := TNetEncoding.URL.Decode(StringReplace(lEncodedPath, '+', '%2B', [rfReplaceAll]));
  lDecodedPath := StringReplace(lDecodedPath, '/', '\', [rfReplaceAll]);

  if (Length(lAuthority) = 2) and CharInSet(lAuthority[1], ['A'..'Z', 'a'..'z']) and (lAuthority[2] = ':') then
  begin
    aFilePath := lAuthority + lDecodedPath;
    Exit(True);
  end;

  if (lAuthority = '') or SameText(lAuthority, 'localhost') then
  begin
    if (Length(lDecodedPath) >= 3) and (lDecodedPath[1] = '\') and
      CharInSet(lDecodedPath[2], ['A'..'Z', 'a'..'z']) and (lDecodedPath[3] = ':') then
      Delete(lDecodedPath, 1, 1);
    aFilePath := lDecodedPath;
    Exit(True);
  end;

  if (lDecodedPath <> '') and (lDecodedPath[1] = '\') then
    Delete(lDecodedPath, 1, 1);
  aFilePath := '\\' + lAuthority + '\' + lDecodedPath;
  Result := True;
end;

function BuildNormalizedLocationObject(aLocationValue: TJSONValue): TJSONObject;
var
  lEndObject: TJSONObject;
  lFilePath: string;
  lLocationObject: TJSONObject;
  lRangeObject: TJSONObject;
  lResult: TJSONObject;
  lStartObject: TJSONObject;
  lUri: string;
begin
  Result := nil;
  if not (aLocationValue is TJSONObject) then
    Exit(nil);

  lLocationObject := aLocationValue as TJSONObject;
  lUri := lLocationObject.GetValue<string>('uri', '');
  lRangeObject := nil;
  if lUri <> '' then
  begin
    if lLocationObject.Values['range'] is TJSONObject then
      lRangeObject := lLocationObject.Values['range'] as TJSONObject;
  end else
  begin
    lUri := lLocationObject.GetValue<string>('targetUri', '');
    if lLocationObject.Values['targetRange'] is TJSONObject then
      lRangeObject := lLocationObject.Values['targetRange'] as TJSONObject
    else if lLocationObject.Values['targetSelectionRange'] is TJSONObject then
      lRangeObject := lLocationObject.Values['targetSelectionRange'] as TJSONObject;
  end;

  if (lUri = '') or (lRangeObject = nil) then
    Exit(nil);
  if not (lRangeObject.Values['start'] is TJSONObject) or not (lRangeObject.Values['end'] is TJSONObject) then
    Exit(nil);

  lStartObject := lRangeObject.Values['start'] as TJSONObject;
  lEndObject := lRangeObject.Values['end'] as TJSONObject;
  lFilePath := lUri;
  TryDecodeFileUri(lUri, lFilePath);

  lResult := TJSONObject.Create;
  AddJsonStringPair(lResult, 'file', lFilePath);
  AddJsonStringPair(lResult, 'uri', lUri);
  lResult.AddPair('line', TJSONNumber.Create(lStartObject.GetValue<Integer>('line', 0) + 1));
  lResult.AddPair('col', TJSONNumber.Create(lStartObject.GetValue<Integer>('character', 0) + 1));
  lResult.AddPair('endLine', TJSONNumber.Create(lEndObject.GetValue<Integer>('line', 0) + 1));
  lResult.AddPair('endCol', TJSONNumber.Create(lEndObject.GetValue<Integer>('character', 0) + 1));
  Result := lResult;
end;

function BuildNormalizedLocationsArray(aResultValue: TJSONValue): TJSONArray;

  procedure AppendLocation(aTarget: TJSONArray; aLocationValue: TJSONValue);
  var
    lLocationObject: TJSONObject;
  begin
    lLocationObject := BuildNormalizedLocationObject(aLocationValue);
    if lLocationObject <> nil then
      aTarget.AddElement(lLocationObject);
  end;

var
  lItemValue: TJSONValue;
  lResult: TJSONArray;
begin
  lResult := TJSONArray.Create;
  if (aResultValue = nil) or (aResultValue is TJSONNull) then
    Exit(lResult);

  if aResultValue is TJSONArray then
  begin
    for lItemValue in aResultValue as TJSONArray do
      AppendLocation(lResult, lItemValue);
    Exit(lResult);
  end;

  AppendLocation(lResult, aResultValue);
  Result := lResult;
end;

function BuildNormalizedLocationsResult(const aCollectionName: string; aResultValue: TJSONValue): string;
var
  lLocations: TJSONArray;
  lResultObject: TJSONObject;
begin
  lResultObject := TJSONObject.Create;
  try
    lLocations := BuildNormalizedLocationsArray(aResultValue);
    lResultObject.AddPair(aCollectionName, lLocations);
    Result := lResultObject.ToJSON;
  finally
    lResultObject.Free;
  end;
end;

function BuildNormalizedRangeObject(aRangeValue: TJSONValue): TJSONObject;
var
  lEndObject: TJSONObject;
  lRangeObject: TJSONObject;
  lResult: TJSONObject;
  lStartObject: TJSONObject;
begin
  Result := nil;
  if not (aRangeValue is TJSONObject) then
    Exit(nil);

  lRangeObject := aRangeValue as TJSONObject;
  if not (lRangeObject.Values['start'] is TJSONObject) or not (lRangeObject.Values['end'] is TJSONObject) then
    Exit(nil);

  lStartObject := lRangeObject.Values['start'] as TJSONObject;
  lEndObject := lRangeObject.Values['end'] as TJSONObject;
  lResult := TJSONObject.Create;
  lResult.AddPair('line', TJSONNumber.Create(lStartObject.GetValue<Integer>('line', 0) + 1));
  lResult.AddPair('col', TJSONNumber.Create(lStartObject.GetValue<Integer>('character', 0) + 1));
  lResult.AddPair('endLine', TJSONNumber.Create(lEndObject.GetValue<Integer>('line', 0) + 1));
  lResult.AddPair('endCol', TJSONNumber.Create(lEndObject.GetValue<Integer>('character', 0) + 1));
  Result := lResult;
end;

procedure AppendHoverSegment(aBuilder: TStringBuilder; const aValue: string);
begin
  if aValue = '' then
    Exit;
  if aBuilder.Length > 0 then
    aBuilder.AppendLine.AppendLine;
  aBuilder.Append(aValue);
end;

procedure ExtractHoverContent(aContentsValue: TJSONValue; aTextBuilder: TStringBuilder; aMarkdownBuilder: TStringBuilder);
var
  lContentsArray: TJSONArray;
  lContentsObject: TJSONObject;
  lItemValue: TJSONValue;
  lKind: string;
  lValue: string;
begin
  if (aContentsValue = nil) or (aContentsValue is TJSONNull) then
    Exit;

  if aContentsValue is TJSONString then
  begin
    AppendHoverSegment(aTextBuilder, aContentsValue.Value);
    Exit;
  end;

  if aContentsValue is TJSONArray then
  begin
    lContentsArray := aContentsValue as TJSONArray;
    for lItemValue in lContentsArray do
      ExtractHoverContent(lItemValue, aTextBuilder, aMarkdownBuilder);
    Exit;
  end;

  if not (aContentsValue is TJSONObject) then
    Exit;

  lContentsObject := aContentsValue as TJSONObject;
  lValue := lContentsObject.GetValue<string>('value', '');
  if lValue = '' then
    Exit;

  AppendHoverSegment(aTextBuilder, lValue);
  lKind := lContentsObject.GetValue<string>('kind', '');
  if SameText(lKind, 'markdown') then
    AppendHoverSegment(aMarkdownBuilder, lValue);
end;

function BuildNormalizedHoverResult(aResultValue: TJSONValue): string;
var
  lContentsValue: TJSONValue;
  lHoverObject: TJSONObject;
  lMarkdownBuilder: TStringBuilder;
  lRangeObject: TJSONObject;
  lRangeValue: TJSONValue;
  lResultObject: TJSONObject;
  lTextBuilder: TStringBuilder;
begin
  lTextBuilder := TStringBuilder.Create;
  lMarkdownBuilder := TStringBuilder.Create;
  lResultObject := TJSONObject.Create;
  try
    lContentsValue := aResultValue;
    lRangeValue := nil;
    if aResultValue is TJSONObject then
    begin
      lHoverObject := aResultValue as TJSONObject;
      if Assigned(lHoverObject.Values['contents']) then
        lContentsValue := lHoverObject.Values['contents'];
      lRangeValue := lHoverObject.Values['range'];
    end;

    ExtractHoverContent(lContentsValue, lTextBuilder, lMarkdownBuilder);
    lResultObject.AddPair('contentsText', lTextBuilder.ToString);
    if lMarkdownBuilder.Length > 0 then
      lResultObject.AddPair('contentsMarkdown', lMarkdownBuilder.ToString);

    lRangeObject := BuildNormalizedRangeObject(lRangeValue);
    if lRangeObject <> nil then
      lResultObject.AddPair('range', lRangeObject);

    if lTextBuilder.Length = 0 then
      lResultObject.AddPair('isEmpty', TJSONBool.Create(True));

    Result := lResultObject.ToJSON;
  finally
    lResultObject.Free;
    lMarkdownBuilder.Free;
    lTextBuilder.Free;
  end;
end;

function BuildHoverText(const aResultJson: string): string;
var
  lBuilder: TStringBuilder;
  lJsonValue: TJSONValue;
  lRangeObject: TJSONObject;
  lResultObject: TJSONObject;
begin
  lJsonValue := TJSONObject.ParseJSONValue(aResultJson);
  if not (lJsonValue is TJSONObject) then
  begin
    lJsonValue.Free;
    Exit('Hover: ' + aResultJson);
  end;

  lBuilder := TStringBuilder.Create;
  try
    lResultObject := lJsonValue as TJSONObject;
    if lResultObject.GetValue<Boolean>('isEmpty', False) then
      lBuilder.Append('Hover: empty')
    else
    begin
      lBuilder.AppendLine('Hover:');
      lBuilder.Append(lResultObject.GetValue<string>('contentsText', ''));
      if lResultObject.Values['range'] is TJSONObject then
      begin
        lRangeObject := lResultObject.Values['range'] as TJSONObject;
        lBuilder.AppendLine;
        lBuilder.Append(Format('Range: %d:%d-%d:%d',
          [lRangeObject.GetValue<Integer>('line', 0), lRangeObject.GetValue<Integer>('col', 0),
           lRangeObject.GetValue<Integer>('endLine', 0), lRangeObject.GetValue<Integer>('endCol', 0)]));
      end;
    end;
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
    lJsonValue.Free;
  end;
end;

function BuildNormalizedSymbolInformationObject(aSymbolValue: TJSONValue): TJSONObject;
var
  lLocationObject: TJSONObject;
  lLocationValue: TJSONValue;
  lResult: TJSONObject;
  lSymbolObject: TJSONObject;
begin
  Result := nil;
  if not (aSymbolValue is TJSONObject) then
    Exit(nil);

  lSymbolObject := aSymbolValue as TJSONObject;
  lLocationValue := lSymbolObject.Values['location'];
  if lLocationValue = nil then
    lLocationValue := aSymbolValue;

  lLocationObject := BuildNormalizedLocationObject(lLocationValue);
  if lLocationObject = nil then
    Exit(nil);
  try
    lResult := TJSONObject.Create;
    AddJsonStringPair(lResult, 'name', lSymbolObject.GetValue<string>('name', ''));
    lResult.AddPair('kind', TJSONNumber.Create(lSymbolObject.GetValue<Integer>('kind', 0)));
    AddJsonStringPair(lResult, 'containerName', lSymbolObject.GetValue<string>('containerName', ''));
    AddJsonStringPair(lResult, 'file', lLocationObject.GetValue<string>('file', ''));
    lResult.AddPair('line', TJSONNumber.Create(lLocationObject.GetValue<Integer>('line', 0)));
    lResult.AddPair('col', TJSONNumber.Create(lLocationObject.GetValue<Integer>('col', 0)));
    Result := lResult;
  finally
    lLocationObject.Free;
  end;
end;

function BuildNormalizedDocumentSymbolObject(const aFilePath, aContainerName: string;
  aSymbolObject: TJSONObject): TJSONObject;
var
  lRangeObject: TJSONObject;
  lRangeValue: TJSONValue;
  lResult: TJSONObject;
begin
  Result := nil;
  if aSymbolObject = nil then
    Exit(nil);

  lRangeValue := aSymbolObject.Values['selectionRange'];
  if lRangeValue = nil then
    lRangeValue := aSymbolObject.Values['range'];

  lRangeObject := BuildNormalizedRangeObject(lRangeValue);
  if lRangeObject = nil then
    Exit(nil);
  try
    lResult := TJSONObject.Create;
    AddJsonStringPair(lResult, 'name', aSymbolObject.GetValue<string>('name', ''));
    lResult.AddPair('kind', TJSONNumber.Create(aSymbolObject.GetValue<Integer>('kind', 0)));
    AddJsonStringPair(lResult, 'containerName', aContainerName);
    AddJsonStringPair(lResult, 'file', aFilePath);
    lResult.AddPair('line', TJSONNumber.Create(lRangeObject.GetValue<Integer>('line', 0)));
    lResult.AddPair('col', TJSONNumber.Create(lRangeObject.GetValue<Integer>('col', 0)));
    Result := lResult;
  finally
    lRangeObject.Free;
  end;
end;

procedure CollectNormalizedSymbols(aTarget: TObjectList<TJSONObject>; aResultValue: TJSONValue;
  const aFilePath, aContainerName: string);
var
  lChildrenValue: TJSONValue;
  lItemValue: TJSONValue;
  lNextContainerName: string;
  lSymbolObject: TJSONObject;
  lValueObject: TJSONObject;
begin
  if (aResultValue = nil) or (aResultValue is TJSONNull) then
    Exit;

  if aResultValue is TJSONArray then
  begin
    for lItemValue in aResultValue as TJSONArray do
      CollectNormalizedSymbols(aTarget, lItemValue, aFilePath, aContainerName);
    Exit;
  end;

  if not (aResultValue is TJSONObject) then
    Exit;
  lValueObject := aResultValue as TJSONObject;

  if lValueObject.Values['location'] <> nil then
    lSymbolObject := BuildNormalizedSymbolInformationObject(aResultValue)
  else
    lSymbolObject := BuildNormalizedDocumentSymbolObject(aFilePath, aContainerName, lValueObject);
  if lSymbolObject <> nil then
    aTarget.Add(lSymbolObject);

  lChildrenValue := lValueObject.Values['children'];
  if lChildrenValue <> nil then
  begin
    lNextContainerName := lValueObject.GetValue<string>('name', aContainerName);
    CollectNormalizedSymbols(aTarget, lChildrenValue, aFilePath, lNextContainerName);
  end;
end;

function SymbolMatchesQuery(aSymbolObject: TJSONObject; const aQuery: string): Boolean;
var
  lQuery: string;
begin
  lQuery := Trim(aQuery);
  if lQuery = '' then
    Exit(True);
  Result := Pos(LowerCase(lQuery), LowerCase(aSymbolObject.GetValue<string>('name', ''))) > 0;
end;

function CompareIntegerValues(aLeft, aRight: Integer): Integer;
begin
  if aLeft < aRight then
    Exit(-1);
  if aLeft > aRight then
    Exit(1);
  Result := 0;
end;

function CompareOrdinalStrings(const aLeft, aRight: string): Integer;
var
  lIndex: Integer;
  lLimit: Integer;
  lLeftLength: Integer;
  lRightLength: Integer;
begin
  lLeftLength := Length(aLeft);
  lRightLength := Length(aRight);
  if lLeftLength < lRightLength then
    lLimit := lLeftLength
  else
    lLimit := lRightLength;

  for lIndex := 1 to lLimit do
  begin
    if aLeft[lIndex] < aRight[lIndex] then
      Exit(-1);
    if aLeft[lIndex] > aRight[lIndex] then
      Exit(1);
  end;

  Result := CompareIntegerValues(lLeftLength, lRightLength);
end;

function CompareNormalizedSymbols(const aLeft, aRight: TJSONObject): Integer;
begin
  Result := CompareOrdinalStrings(aLeft.GetValue<string>('file', ''), aRight.GetValue<string>('file', ''));
  if Result <> 0 then
    Exit(Result);

  Result := CompareIntegerValues(aLeft.GetValue<Integer>('line', 0), aRight.GetValue<Integer>('line', 0));
  if Result <> 0 then
    Exit(Result);

  Result := CompareIntegerValues(aLeft.GetValue<Integer>('col', 0), aRight.GetValue<Integer>('col', 0));
  if Result <> 0 then
    Exit(Result);

  Result := CompareOrdinalStrings(aLeft.GetValue<string>('name', ''), aRight.GetValue<string>('name', ''));
  if Result <> 0 then
    Exit(Result);

  Result := CompareIntegerValues(aLeft.GetValue<Integer>('kind', 0), aRight.GetValue<Integer>('kind', 0));
  if Result <> 0 then
    Exit(Result);

  Result := CompareOrdinalStrings(aLeft.GetValue<string>('containerName', ''), aRight.GetValue<string>('containerName', ''));
end;

function BuildNormalizedSymbolsResult(const aFilePath, aQuery: string; aLimit: Integer;
  aResultValue: TJSONValue): string;
var
  lResultObject: TJSONObject;
  lSymbolList: TObjectList<TJSONObject>;
  lSymbolObject: TJSONObject;
  lSymbolsArray: TJSONArray;
begin
  lResultObject := TJSONObject.Create;
  lSymbolList := TObjectList<TJSONObject>.Create(True);
  try
    lSymbolsArray := TJSONArray.Create;
    lResultObject.AddPair('symbols', lSymbolsArray);
    CollectNormalizedSymbols(lSymbolList, aResultValue, aFilePath, '');
    lSymbolList.Sort(TComparer<TJSONObject>.Construct(CompareNormalizedSymbols));
    while lSymbolList.Count > 0 do
    begin
      lSymbolObject := lSymbolList.Extract(lSymbolList[0]);
      if not SymbolMatchesQuery(lSymbolObject, aQuery) then
      begin
        lSymbolObject.Free;
        Continue;
      end;
      lSymbolsArray.AddElement(lSymbolObject);
      if (aLimit > 0) and (lSymbolsArray.Count >= aLimit) then
        Break;
    end;
    Result := lResultObject.ToJSON;
  finally
    lSymbolList.Free;
    lResultObject.Free;
  end;
end;

function BuildOperationResultText(const aOptions: TAppOptions; const aRequestFilePath: string;
  aResponse: TJSONObject): string;
var
  lResultValue: TJSONValue;
begin
  lResultValue := aResponse.Values['result'];
  case aOptions.fLspOperation of
    TLspOperation.loDefinition:
      Result := BuildNormalizedLocationsResult('locations', lResultValue);
    TLspOperation.loHover:
      Result := BuildNormalizedHoverResult(lResultValue);
    TLspOperation.loSymbols:
      Result := BuildNormalizedSymbolsResult(aRequestFilePath, aOptions.fLspQuery, aOptions.fLspLimit, lResultValue);
  else
    Result := ExtractRawResultText(aResponse);
  end;
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

function BuildProbeEnvelope(const aContext: TLspContext; const aLspPath: string; aModes: TJSONArray): string;
var
  lLspObject: TJSONObject;
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
    lRoot.AddPair('lsp', lLspObject);
    lRoot.AddPair('result', TJSONObject.Create.AddPair('modes', TJSONObject.ParseJSONValue(aModes.ToJSON) as TJSONArray));
    lRoot.AddPair('warnings', TJSONArray.Create);
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

function BuildProbeText(const aModes: TJSONArray; aShowInitOptions: Boolean): string;
var
  lBuilder: TStringBuilder;
  lModeObject: TJSONObject;
  i: Integer;
begin
  lBuilder := TStringBuilder.Create;
  try
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

function TryRunLspProbe(const aOptions: TAppOptions; const aContext: TLspContext; const aLspPath: string;
  out aResult: TLspRunnerResult; out aError: string): Boolean;
var
  lClient: TLspJsonRpcClient;
  lConfigObject: TJSONObject;
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
          if not TryWriteOfficialLspSettingsFile(aContext, lSettingsFilePath, lError) then
          begin
            aError := lError;
            Exit(False);
          end;
          lInitOptions := BuildSettingsFileInitializeOptions(aContext, lSettingsFilePath);
        end else
          lInitOptions := BuildContextFileInitializeOptions(aContext);

        if not lClient.Start(aLspPath, '', aContext.fDakLspRoot,
          TPath.Combine(aContext.fLogsDir, 'DelphiLSP.' + ProbeModeName(lMode) + '.stderr.log'), lError) then
        begin
          aError := lError;
          Exit(False);
        end;

        if not lClient.SendRequest(1, 'initialize', BuildInitializeParamsWithOptions(aContext, CloneJsonObject(lInitOptions)), lInitResponse, lError) then
        begin
          aError := lError;
          Exit(False);
        end;
        if Assigned(lInitResponse.Values['error']) then
        begin
          aError := BuildResponseError('probe initialize ' + ProbeModeName(lMode), lInitResponse);
          Exit(False);
        end;

        if not lClient.SendNotification('initialized', '{}', lError) then
        begin
          aError := 'DelphiLSP initialized notification failed: ' + lError;
          Exit(False);
        end;

        if lMode = TLspProbeMode.lpmSettingsFile then
        begin
          lConfigParams := BuildProbeConfigurationParams(lSettingsFilePath);
          lConfigObject := TJSONObject.ParseJSONValue(lConfigParams) as TJSONObject;
          if not lClient.SendNotification('workspace/didChangeConfiguration', lConfigParams, lError) then
          begin
            aError := 'DelphiLSP didChangeConfiguration failed: ' + lError;
            Exit(False);
          end;
        end;

        if not lClient.ShutdownAndExit(lError) then
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
    aResult.fResponseText := BuildProbeEnvelope(aContext, aLspPath, lModes);
    aResult.fTextResponse := BuildProbeText(lModes, aOptions.fLspShowInitOptions);
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
  lRoot: string;
  lRoots: TArray<string>;
  lTried: TList<string>;

  procedure TryCandidate(const aCandidate: string);
  begin
    lCandidate := Trim(aCandidate);
    if lCandidate = '' then
      Exit;
    lCandidate := TPath.GetFullPath(lCandidate);
    if not lTried.Contains(lCandidate) then
      lTried.Add(lCandidate);
    if FileExists(lCandidate) then
    begin
      aExePath := lCandidate;
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
    lRoots := BuildDerivedLspRoots(aContext);
    for lRoot in lRoots do
    begin
      if TryFindLspExeInRoot(lRoot, lCandidate) then
      begin
        aExePath := lCandidate;
        Exit(True);
      end;
      TryCandidate(TPath.Combine(lRoot, 'bin64\\DelphiLSP.exe'));
      TryCandidate(TPath.Combine(lRoot, 'bin\\DelphiLSP.exe'));
    end;

    aError := 'DelphiLSP.exe not found for Delphi ' + aContext.fDelphiVersion + '. Tried: ' +
      String.Join('; ', lTried.ToArray) + '. Use --lsp-path to specify the correct path.';
  finally
    lTried.Free;
  end;
end;

function TLspJsonRpcClient.ReadLine(out aLine: string; out aError: string): Boolean;
var
  lBuilder: TStringBuilder;
  lByte: Byte;
  lCount: Integer;
begin
  Result := False;
  aLine := '';
  aError := '';
  lBuilder := TStringBuilder.Create;
  try
    while True do
    begin
      lCount := fOutput.Read(lByte, 1);
      if lCount <> 1 then
      begin
        aError := 'Unexpected end of stream while reading DelphiLSP response header.';
        Exit(False);
      end;
      if lByte = Ord(#10) then
        Break;
      if lByte <> Ord(#13) then
        lBuilder.Append(Char(lByte));
    end;
    aLine := lBuilder.ToString;
    Result := True;
  finally
    lBuilder.Free;
  end;
end;

function TLspJsonRpcClient.ReadMessage(out aBody: string; out aError: string): Boolean;
var
  lBodyBytes: TBytes;
  lContentLength: Integer;
  lLine: string;
  lOffset: Integer;
  lRead: Integer;
begin
  Result := False;
  aBody := '';
  aError := '';
  lContentLength := -1;
  while True do
  begin
    if not ReadLine(lLine, aError) then
      Exit(False);
    if lLine = '' then
      Break;
    if SameText(Copy(lLine, 1, Length('Content-Length:')), 'Content-Length:') then
      lContentLength := StrToIntDef(Trim(Copy(lLine, Length('Content-Length:') + 1, MaxInt)), -1);
  end;
  if lContentLength < 0 then
  begin
    aError := 'Missing Content-Length header in DelphiLSP response.';
    Exit(False);
  end;
  SetLength(lBodyBytes, lContentLength);
  lOffset := 0;
  while lOffset < lContentLength do
  begin
    lRead := fOutput.Read(lBodyBytes[lOffset], lContentLength - lOffset);
    if lRead <= 0 then
    begin
      aError := 'Unexpected end of stream while reading DelphiLSP response body.';
      Exit(False);
    end;
    Inc(lOffset, lRead);
  end;
  aBody := TEncoding.UTF8.GetString(lBodyBytes);
  Result := True;
end;

function TLspJsonRpcClient.WriteMessage(const aBody: string; out aError: string): Boolean;
var
  lBodyBytes: TBytes;
  lHeaderBytes: TBytes;
  lHeaderText: string;
begin
  Result := False;
  aError := '';
  lBodyBytes := TEncoding.UTF8.GetBytes(aBody);
  lHeaderText := 'Content-Length: ' + IntToStr(Length(lBodyBytes)) + #13#10#13#10;
  lHeaderBytes := TEncoding.ASCII.GetBytes(lHeaderText);
  try
    if Length(lHeaderBytes) > 0 then
      fInput.WriteBuffer(lHeaderBytes[0], Length(lHeaderBytes));
    if Length(lBodyBytes) > 0 then
      fInput.WriteBuffer(lBodyBytes[0], Length(lBodyBytes));
    Result := True;
  except
    on E: Exception do
    begin
      aError := 'Failed to write DelphiLSP message: ' + E.Message;
    end;
  end;
end;

destructor TLspJsonRpcClient.Destroy;
begin
  fInput.Free;
  fOutput.Free;
  if fStdErrHandle <> 0 then
    CloseHandle(fStdErrHandle);
  if fProcessHandle <> 0 then
  begin
    if WaitForSingleObject(fProcessHandle, 0) = WAIT_TIMEOUT then
      TerminateProcess(fProcessHandle, 1);
    CloseHandle(fProcessHandle);
  end;
  if fThreadHandle <> 0 then
    CloseHandle(fThreadHandle);
  inherited Destroy;
end;

function TLspJsonRpcClient.SendNotification(const aMethod, aParamsJson: string; out aError: string): Boolean;
var
  lBody: string;
  lParamsJson: string;
begin
  lParamsJson := aParamsJson;
  if Trim(lParamsJson) = '' then
    lParamsJson := '{}';
  lBody := '{"jsonrpc":"2.0","method":"' + aMethod + '","params":' + lParamsJson + '}';
  Result := WriteMessage(lBody, aError);
end;

function TLspJsonRpcClient.SendRequest(aId: Integer; const aMethod, aParamsJson: string; out aResponse: TJSONObject;
  out aError: string): Boolean;
var
  lBody: string;
  lJsonValue: TJSONValue;
  lParamsJson: string;
  lResponseText: string;
begin
  Result := False;
  aError := '';
  aResponse := nil;
  lParamsJson := aParamsJson;
  if Trim(lParamsJson) = '' then
    lParamsJson := '{}';
  lBody := '{"jsonrpc":"2.0","id":' + IntToStr(aId) + ',"method":"' + aMethod + '","params":' + lParamsJson + '}';
  if not WriteMessage(lBody, aError) then
    Exit(False);
  if not ReadMessage(lResponseText, aError) then
    Exit(False);
  lJsonValue := TJSONObject.ParseJSONValue(lResponseText);
  if not (lJsonValue is TJSONObject) then
  begin
    lJsonValue.Free;
    aError := 'Invalid DelphiLSP JSON-RPC response: ' + lResponseText;
    Exit(False);
  end;
  aResponse := lJsonValue as TJSONObject;
  Result := True;
end;

function TLspJsonRpcClient.ShutdownAndExit(out aError: string): Boolean;
var
  lResponse: TJSONObject;
  lWait: Cardinal;
begin
  lResponse := nil;
  try
    if not SendRequest(9001, 'shutdown', '{}', lResponse, aError) then
      Exit(False);
  finally
    lResponse.Free;
  end;
  if not SendNotification('exit', '{}', aError) then
    Exit(False);
  lWait := WaitForSingleObject(fProcessHandle, 5000);
  if lWait <> WAIT_OBJECT_0 then
  begin
    aError := 'DelphiLSP did not exit cleanly.';
    Exit(False);
  end;
  Result := True;
end;

function TLspJsonRpcClient.Start(const aExePath, aArguments, aWorkDir, aStdErrPath: string; out aError: string): Boolean;
var
  lChildStdInRead: THandle;
  lChildStdInWrite: THandle;
  lChildStdOutRead: THandle;
  lChildStdOutWrite: THandle;
  lCmdLine: string;
  lLastError: Cardinal;
  lPi: TProcessInformation;
  lSa: TSecurityAttributes;
  lSi: TStartupInfo;
  lStdErrHandle: THandle;
  lStdErrDir: string;
begin
  Result := False;
  aError := '';
  lChildStdInRead := 0;
  lChildStdInWrite := 0;
  lChildStdOutRead := 0;
  lChildStdOutWrite := 0;
  lStdErrHandle := 0;

  FillChar(lSa, SizeOf(lSa), 0);
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;

  if not CreatePipe(lChildStdOutRead, lChildStdOutWrite, @lSa, 0) then
  begin
    aError := 'Failed to create DelphiLSP stdout pipe.';
    Exit(False);
  end;
  if not CreatePipe(lChildStdInRead, lChildStdInWrite, @lSa, 0) then
  begin
    aError := 'Failed to create DelphiLSP stdin pipe.';
    CloseHandle(lChildStdOutRead);
    CloseHandle(lChildStdOutWrite);
    Exit(False);
  end;

  try
    SetHandleInformation(lChildStdOutRead, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(lChildStdInWrite, HANDLE_FLAG_INHERIT, 0);

    if Trim(aStdErrPath) <> '' then
    begin
      lStdErrDir := ExtractFileDir(aStdErrPath);
      if lStdErrDir <> '' then
        ForceDirectories(lStdErrDir);
      lStdErrHandle := CreateFile(PChar(aStdErrPath), GENERIC_WRITE, FILE_SHARE_READ, @lSa, CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL, 0);
      if lStdErrHandle = INVALID_HANDLE_VALUE then
      begin
        lStdErrHandle := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @lSa, OPEN_EXISTING,
          FILE_ATTRIBUTE_NORMAL, 0);
        if lStdErrHandle = INVALID_HANDLE_VALUE then
          lStdErrHandle := GetStdHandle(STD_ERROR_HANDLE);
      end;
    end else
      lStdErrHandle := GetStdHandle(STD_ERROR_HANDLE);

    FillChar(lSi, SizeOf(lSi), 0);
    lSi.cb := SizeOf(lSi);
    lSi.dwFlags := STARTF_USESTDHANDLES;
    lSi.hStdInput := lChildStdInRead;
    lSi.hStdOutput := lChildStdOutWrite;
    lSi.hStdError := lStdErrHandle;

    FillChar(lPi, SizeOf(lPi), 0);
    lCmdLine := '"' + aExePath + '"';
    if aArguments <> '' then
      lCmdLine := lCmdLine + ' ' + aArguments;
    UniqueString(lCmdLine);

    if not CreateProcess(PChar(aExePath), PChar(lCmdLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      PChar(aWorkDir), lSi, lPi) then
    begin
      lLastError := GetLastError;
      aError := 'Failed to start DelphiLSP.exe: ' + SysErrorMessage(lLastError);
      Exit(False);
    end;

    CloseHandle(lChildStdInRead);
    lChildStdInRead := 0;
    CloseHandle(lChildStdOutWrite);
    lChildStdOutWrite := 0;

    fInput := THandleStream.Create(lChildStdInWrite);
    fOutput := THandleStream.Create(lChildStdOutRead);
    fProcessHandle := lPi.hProcess;
    fThreadHandle := lPi.hThread;
    if (Trim(aStdErrPath) <> '') and (lStdErrHandle <> INVALID_HANDLE_VALUE) then
    begin
      fStdErrHandle := lStdErrHandle;
      lStdErrHandle := 0;
    end;
    Result := True;
  finally
    if lChildStdInRead <> 0 then
      CloseHandle(lChildStdInRead);
    if lChildStdOutWrite <> 0 then
      CloseHandle(lChildStdOutWrite);
    if not Result then
    begin
      if lChildStdInWrite <> 0 then
        CloseHandle(lChildStdInWrite);
      if lChildStdOutRead <> 0 then
        CloseHandle(lChildStdOutRead);
    end;
    if (lStdErrHandle <> 0) and (lStdErrHandle <> GetStdHandle(STD_ERROR_HANDLE)) and
      (lStdErrHandle <> INVALID_HANDLE_VALUE) then
      CloseHandle(lStdErrHandle);
  end;
end;

function TryRunLspRequest(const aOptions: TAppOptions; const aContext: TLspContext;
  out aResult: TLspRunnerResult; out aError: string): Boolean;
var
  lClient: TLspJsonRpcClient;
  lError: string;
  lInitResponse: TJSONObject;
  lLspPath: string;
  lOperationName: string;
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
  if aOptions.fLspOperation = TLspOperation.loProbe then
  begin
    if not TryRunLspProbe(aOptions, aContext, lLspPath, aResult, aError) then
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

  lClient := TLspJsonRpcClient.Create;
  try
    lError := '';
    if not lClient.Start(lLspPath, '', aContext.fDakLspRoot,
      TPath.Combine(aContext.fLogsDir, 'DelphiLSP.stderr.log'), lError) then
    begin
      aError := lError;
      Exit(False);
    end;

    if not lClient.SendRequest(1, 'initialize', BuildInitializeParams(aContext), lInitResponse, lError) then
    begin
      aError := lError;
      Exit(False);
    end;
    if Assigned(lInitResponse.Values['error']) then
    begin
      aError := BuildResponseError('initialize', lInitResponse);
      Exit(False);
    end;

    if not TryEnsureOperationSupported(lInitResponse, aContext, lLspPath, aOptions.fLspOperation, lError) then
    begin
      aError := lError;
      Exit(False);
    end;

    if not lClient.SendNotification('initialized', '{}', lError) then
    begin
      aError := 'DelphiLSP initialized notification failed: ' + lError;
      Exit(False);
    end;

    if not lClient.SendNotification('textDocument/didOpen', BuildDidOpenParams(lRequestFilePath), lError) then
    begin
      aError := 'DelphiLSP didOpen failed: ' + lError;
      Exit(False);
    end;
    lRequestParams := BuildRequestParams(aOptions, FilePathToURL(lRequestFilePath));

    if not lClient.SendRequest(2, lRequestMethod, lRequestParams, lRequestResponse, lError) then
    begin
      aError := lError;
      Exit(False);
    end;
    if Assigned(lRequestResponse.Values['error']) then
    begin
      aError := BuildResponseError(lOperationName + ' request', lRequestResponse);
      Exit(False);
    end;

    if not lClient.ShutdownAndExit(lError) then
    begin
      aError := lError;
      Exit(False);
    end;

    lResponseText := BuildOperationResultText(aOptions, lRequestFilePath, lRequestResponse);
    aResult.fLspPath := lLspPath;
    aResult.fResponseText := BuildOperationEnvelope(aOptions, aContext, lLspPath, lOperationName, lRequestFilePath,
      lResponseText);
    aResult.fTextResponse := BuildOperationText(aOptions, aContext, lLspPath, lOperationName, lRequestFilePath,
      lResponseText);
    Result := True;
  finally
    lRequestResponse.Free;
    lInitResponse.Free;
    lClient.Free;
  end;
end;

end.
