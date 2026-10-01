unit Dak.Lsp.Protocol;

interface

uses
  System.JSON,
  Dak.Lsp.Context, Dak.Types;

const
  cLspCleanupWarning = 'DAK used controlled process-tree termination to avoid a vendor shutdown defect.';
  cLspSettingsWarning = 'Project settings were supplied; server acceptance is not verified.';

type
  // One client-to-server notification in the order the runner sends it.
  TLspWireMessage = record
    fMethod: string;
    fParams: string;
  end;

function BuildContextFileInitializeOptions(const aContext: TLspContext): TJSONObject;
function BuildSettingsFileInitializeOptions(const aContext: TLspContext; const aSettingsFilePath: string): TJSONObject;
function BuildInitializeParamsWithOptions(const aContext: TLspContext; aInitializeOptions: TJSONObject): string;
function BuildSettingsConfigurationParams(const aSettingsFilePath: string): string;
function BuildRequestInitializeParams(const aContext: TLspContext; const aSettingsFilePath: string): string;
function BuildRequestNotifications(const aSettingsFilePath, aRequestFilePath: string): TArray<TLspWireMessage>;
function BuildLspStageError(const aStage, aDetail: string): string;
function TryBuildOperationResultText(const aOptions: TAppOptions; const aRequestFilePath: string;
  aResponse: TJSONObject; out aResultText: string; out aError: string): Boolean;
function BuildOperationEnvelope(const aOptions: TAppOptions; const aContext: TLspContext; const aLspPath,
  aOperationName: string; const aRequestFilePath: string; const aRawResultJson: string;
  const aExtraWarnings: TArray<string>): string;
function BuildOperationText(const aOptions: TAppOptions; const aContext: TLspContext; const aLspPath,
  aOperationName: string; const aRequestFilePath: string; const aRawResultJson: string;
  const aExtraWarnings: TArray<string>): string;
function BuildRequestParams(const aOptions: TAppOptions; const aFileUri: string): string;

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.IOUtils, System.NetEncoding,
  System.StrUtils, System.SysUtils,
  Winapi.Windows,
  maxLogic.ioUtils,
  Dak.Utils;

function AddJsonStringPair(aObject: TJSONObject; const aName, aValue: string): TJSONObject;
begin
  aObject.AddPair(aName, aValue);
  Result := aObject;
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
  // Takes ownership of aInitializeOptions.
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

function BuildSettingsConfigurationParams(const aSettingsFilePath: string): string;
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

function BuildRequestInitializeParams(const aContext: TLspContext; const aSettingsFilePath: string): string;
begin
  Result := BuildInitializeParamsWithOptions(aContext, BuildSettingsFileInitializeOptions(aContext, aSettingsFilePath));
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

function BuildRequestNotifications(const aSettingsFilePath, aRequestFilePath: string): TArray<TLspWireMessage>;
begin
  SetLength(Result, 3);
  Result[0].fMethod := 'initialized';
  Result[0].fParams := '{}';
  Result[1].fMethod := 'workspace/didChangeConfiguration';
  Result[1].fParams := BuildSettingsConfigurationParams(aSettingsFilePath);
  Result[2].fMethod := 'textDocument/didOpen';
  Result[2].fParams := BuildDidOpenParams(aRequestFilePath);
end;

function BuildLspStageError(const aStage, aDetail: string): string;
begin
  // Transport details (timeouts, framing, server error code and message) keep
  // their own text; the runner adds which protocol step failed.
  Result := Format('DelphiLSP %s failed: %s', [aStage, aDetail]);
end;

function BuildOperationEnvelope(const aOptions: TAppOptions; const aContext: TLspContext; const aLspPath,
  aOperationName: string; const aRequestFilePath: string; const aRawResultJson: string;
  const aExtraWarnings: TArray<string>): string;
var
  lJsonValue: TJSONValue;
  lExtraWarning: string;
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
    end else begin
      AddJsonStringPair(lQueryObject, 'file', aRequestFilePath);
      lQueryObject.AddPair('line', TJSONNumber.Create(aOptions.fLspLine));
      lQueryObject.AddPair('col', TJSONNumber.Create(aOptions.fLspCol));
    end;
    lRoot.AddPair('query', lQueryObject);

    lLspObject := TJSONObject.Create;
    AddJsonStringPair(lLspObject, 'path', aLspPath);
    AddJsonStringPair(lLspObject, 'cleanup', 'controlled-termination');
    AddJsonStringPair(lLspObject, 'settingsAcceptance', 'unverified');
    lRoot.AddPair('lsp', lLspObject);

    lJsonValue := TJSONObject.ParseJSONValue(aRawResultJson);
    if lJsonValue = nil then
      lRoot.AddPair('result', aRawResultJson)
    else
      lRoot.AddPair('result', lJsonValue);

    lWarnings := TJSONArray.Create;
    lWarnings.Add(cLspCleanupWarning);
    lWarnings.Add(cLspSettingsWarning);
    for lExtraWarning in aExtraWarnings do
      lWarnings.Add(lExtraWarning);
    lRoot.AddPair('warnings', lWarnings);

    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;

function BuildHoverText(const aResultJson: string): string; forward;

function BuildOperationText(const aOptions: TAppOptions; const aContext: TLspContext; const aLspPath,
  aOperationName: string; const aRequestFilePath: string; const aRawResultJson: string;
  const aExtraWarnings: TArray<string>): string;
var
  lExtraWarning: string;
  lLines: TStringBuilder;
begin
  if aOptions.fLspOperation = TLspOperation.loHover then
  begin
    Result := BuildHoverText(aRawResultJson) + sLineBreak + cLspCleanupWarning + sLineBreak + cLspSettingsWarning;
    for lExtraWarning in aExtraWarnings do
      Result := Result + sLineBreak + lExtraWarning;
    Exit;
  end;

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
    lLines.AppendLine(cLspCleanupWarning);
    lLines.AppendLine(cLspSettingsWarning);
    for lExtraWarning in aExtraWarnings do
      lLines.AppendLine(lExtraWarning);
    lLines.Append('result: ' + aRawResultJson);
    Result := lLines.ToString;
  finally
    lLines.Free;
  end;
end;

function BuildPositionParams(const aOptions: TAppOptions; const aFileUri: string): string;
var
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

function ExtractRawResultText(aResponse: TJSONObject): string;
var
  lResultValue: TJSONValue;
begin
  lResultValue := aResponse.Values['result'];
  if lResultValue = nil then
    Exit('null');
  Result := lResultValue.ToJSON;
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

function IsJsonText(aValue: TJSONValue): Boolean;
begin
  // TJSONNumber derives from TJSONString in the RTL; a number is not text.
  Result := (aValue is TJSONString) and not (aValue is TJSONNumber);
end;

function TryReadPosition(aValue: TJSONValue; out aLine, aCharacter: Integer): Boolean;
var
  lObject: TJSONObject;
begin
  aLine := 0;
  aCharacter := 0;
  if not (aValue is TJSONObject) then
    Exit(False);
  lObject := aValue as TJSONObject;
  // A missing coordinate is malformed, never position 0.
  Result := (lObject.Values['line'] is TJSONNumber) and (lObject.Values['character'] is TJSONNumber) and
    TryStrToInt(lObject.Values['line'].Value, aLine) and TryStrToInt(lObject.Values['character'].Value, aCharacter) and
    (aLine >= 0) and (aCharacter >= 0);
end;

function TryAddNormalizedRange(aRangeValue: TJSONValue; aTarget: TJSONObject): Boolean;
var
  lEndCharacter, lEndLine, lStartCharacter, lStartLine: Integer;
begin
  Result := (aRangeValue is TJSONObject) and
    TryReadPosition((aRangeValue as TJSONObject).Values['start'], lStartLine, lStartCharacter) and
    TryReadPosition((aRangeValue as TJSONObject).Values['end'], lEndLine, lEndCharacter);
  if not Result then
    Exit;
  aTarget.AddPair('line', TJSONNumber.Create(lStartLine + 1));
  aTarget.AddPair('col', TJSONNumber.Create(lStartCharacter + 1));
  aTarget.AddPair('endLine', TJSONNumber.Create(lEndLine + 1));
  aTarget.AddPair('endCol', TJSONNumber.Create(lEndCharacter + 1));
end;

// Returns nil unless the value is a complete Location or LocationLink.
function BuildNormalizedLocationObject(aLocationValue: TJSONValue): TJSONObject;
var
  lFilePath: string;
  lLocationObject: TJSONObject;
  lRangeValue: TJSONValue;
  lUri: string;
begin
  Result := nil;
  if not (aLocationValue is TJSONObject) then
    Exit(nil);

  lLocationObject := aLocationValue as TJSONObject;
  if IsJsonText(lLocationObject.Values['uri']) then
  begin
    lUri := lLocationObject.Values['uri'].Value;
    lRangeValue := lLocationObject.Values['range'];
  end else if IsJsonText(lLocationObject.Values['targetUri']) then
  begin
    lUri := lLocationObject.Values['targetUri'].Value;
    lRangeValue := lLocationObject.Values['targetRange'];
    if lRangeValue = nil then
      lRangeValue := lLocationObject.Values['targetSelectionRange'];
  end else
    Exit(nil);
  if lUri = '' then
    Exit(nil);
  if not TryDecodeFileUri(lUri, lFilePath) then
    lFilePath := lUri;

  Result := TJSONObject.Create;
  try
    AddJsonStringPair(Result, 'file', lFilePath);
    AddJsonStringPair(Result, 'uri', lUri);
    if not TryAddNormalizedRange(lRangeValue, Result) then
      FreeAndNil(Result);
  except
    Result.Free;
    raise;
  end;
end;

// Definition results: Location | Location[] | LocationLink[] | null. Any other
// shape, or an incomplete entry, is malformed rather than an empty answer.
function TryBuildNormalizedLocationsResult(aResultValue: TJSONValue; out aResultText: string;
  out aError: string): Boolean;
var
  lItemValue: TJSONValue;
  lLocation: TJSONObject;
  lLocations: TJSONArray;
  lResultObject: TJSONObject;
begin
  aResultText := '';
  aError := '';
  lResultObject := TJSONObject.Create;
  try
    lLocations := TJSONArray.Create;
    lResultObject.AddPair('locations', lLocations);
    if aResultValue is TJSONArray then
    begin
      for lItemValue in aResultValue as TJSONArray do
      begin
        lLocation := BuildNormalizedLocationObject(lItemValue);
        if lLocation = nil then
        begin
          aError := 'an entry is not a complete Location or LocationLink';
          Exit(False);
        end;
        lLocations.AddElement(lLocation);
      end;
    end else if (aResultValue <> nil) and not (aResultValue is TJSONNull) then
    begin
      lLocation := BuildNormalizedLocationObject(aResultValue);
      if lLocation = nil then
      begin
        aError := 'expected Location, Location[], LocationLink[] or null';
        Exit(False);
      end;
      lLocations.AddElement(lLocation);
    end;
    aResultText := lResultObject.ToJSON;
    Result := True;
  finally
    lResultObject.Free;
  end;
end;

function BuildNormalizedRangeObject(aRangeValue: TJSONValue): TJSONObject;
begin
  Result := TJSONObject.Create;
  if not TryAddNormalizedRange(aRangeValue, Result) then
    FreeAndNil(Result);
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

  if IsJsonText(aContentsValue) then
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

function IsMarkedContent(aValue: TJSONValue): Boolean;
begin
  // MarkedString (string or {language, value}) or MarkupContent ({kind, value}).
  Result := IsJsonText(aValue) or
    ((aValue is TJSONObject) and IsJsonText((aValue as TJSONObject).Values['value']));
end;

function IsHoverContents(aValue: TJSONValue): Boolean;
var
  lItemValue: TJSONValue;
begin
  if aValue is TJSONArray then
  begin
    for lItemValue in aValue as TJSONArray do
      if not IsMarkedContent(lItemValue) then
        Exit(False);
    Exit(True);
  end;
  Result := IsMarkedContent(aValue);
end;

// Hover results: Hover | null. A Hover without valid contents or with an
// unreadable range is malformed.
function TryBuildNormalizedHoverResult(aResultValue: TJSONValue; out aResultText: string;
  out aError: string): Boolean;
var
  lContentsValue: TJSONValue;
  lHoverObject: TJSONObject;
  lMarkdownBuilder: TStringBuilder;
  lRangeObject: TJSONObject;
  lRangeValue: TJSONValue;
  lResultObject: TJSONObject;
  lTextBuilder: TStringBuilder;
begin
  aResultText := '';
  aError := '';
  lContentsValue := nil;
  lRangeValue := nil;
  if (aResultValue <> nil) and not (aResultValue is TJSONNull) then
  begin
    if not (aResultValue is TJSONObject) then
    begin
      aError := 'expected Hover or null';
      Exit(False);
    end;
    lHoverObject := aResultValue as TJSONObject;
    lContentsValue := lHoverObject.Values['contents'];
    if not IsHoverContents(lContentsValue) then
    begin
      aError := 'Hover contents must be MarkedString, MarkedString[] or MarkupContent';
      Exit(False);
    end;
    lRangeValue := lHoverObject.Values['range'];
    if lRangeValue is TJSONNull then
      lRangeValue := nil;
  end;

  lTextBuilder := TStringBuilder.Create;
  lMarkdownBuilder := TStringBuilder.Create;
  lResultObject := TJSONObject.Create;
  try
    ExtractHoverContent(lContentsValue, lTextBuilder, lMarkdownBuilder);
    lResultObject.AddPair('contentsText', lTextBuilder.ToString);
    if lMarkdownBuilder.Length > 0 then
      lResultObject.AddPair('contentsMarkdown', lMarkdownBuilder.ToString);

    if lRangeValue <> nil then
    begin
      lRangeObject := BuildNormalizedRangeObject(lRangeValue);
      if lRangeObject = nil then
      begin
        aError := 'Hover range is not a complete Range';
        Exit(False);
      end;
      lResultObject.AddPair('range', lRangeObject);
    end;

    if lTextBuilder.Length = 0 then
      lResultObject.AddPair('isEmpty', TJSONBool.Create(True));

    aResultText := lResultObject.ToJSON;
    Result := True;
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

function HasSymbolIdentity(aSymbolObject: TJSONObject): Boolean;
var
  lKind: Integer;
begin
  Result := IsJsonText(aSymbolObject.Values['name']) and (aSymbolObject.Values['kind'] is TJSONNumber) and
    TryStrToInt(aSymbolObject.Values['kind'].Value, lKind);
end;

// Returns nil unless the entry is a complete SymbolInformation.
function BuildNormalizedSymbolInformationObject(aSymbolObject: TJSONObject): TJSONObject;
var
  lContainerName: string;
  lLocationObject: TJSONObject;
begin
  if not HasSymbolIdentity(aSymbolObject) then
    Exit(nil);
  lLocationObject := BuildNormalizedLocationObject(aSymbolObject.Values['location']);
  if lLocationObject = nil then
    Exit(nil);
  try
    lContainerName := '';
    if IsJsonText(aSymbolObject.Values['containerName']) then
      lContainerName := aSymbolObject.Values['containerName'].Value;
    Result := TJSONObject.Create;
    AddJsonStringPair(Result, 'name', aSymbolObject.Values['name'].Value);
    Result.AddPair('kind', TJSONNumber.Create(StrToInt(aSymbolObject.Values['kind'].Value)));
    AddJsonStringPair(Result, 'containerName', lContainerName);
    AddJsonStringPair(Result, 'file', lLocationObject.GetValue<string>('file'));
    Result.AddPair('line', TJSONNumber.Create(lLocationObject.GetValue<Integer>('line')));
    Result.AddPair('col', TJSONNumber.Create(lLocationObject.GetValue<Integer>('col')));
  finally
    lLocationObject.Free;
  end;
end;

// Returns nil unless the entry is a complete DocumentSymbol.
function BuildNormalizedDocumentSymbolObject(const aFilePath, aContainerName: string;
  aSymbolObject: TJSONObject): TJSONObject;
var
  lRangeObject: TJSONObject;
  lRangeValue: TJSONValue;
begin
  if not HasSymbolIdentity(aSymbolObject) then
    Exit(nil);

  lRangeValue := aSymbolObject.Values['selectionRange'];
  if lRangeValue = nil then
    lRangeValue := aSymbolObject.Values['range'];

  lRangeObject := BuildNormalizedRangeObject(lRangeValue);
  if lRangeObject = nil then
    Exit(nil);
  try
    Result := TJSONObject.Create;
    AddJsonStringPair(Result, 'name', aSymbolObject.Values['name'].Value);
    Result.AddPair('kind', TJSONNumber.Create(StrToInt(aSymbolObject.Values['kind'].Value)));
    AddJsonStringPair(Result, 'containerName', aContainerName);
    AddJsonStringPair(Result, 'file', aFilePath);
    Result.AddPair('line', TJSONNumber.Create(lRangeObject.GetValue<Integer>('line')));
    Result.AddPair('col', TJSONNumber.Create(lRangeObject.GetValue<Integer>('col')));
  finally
    lRangeObject.Free;
  end;
end;

function TryCollectNormalizedSymbols(aTarget: TObjectList<TJSONObject>; aItems: TJSONArray;
  const aFilePath, aContainerName: string; out aError: string): Boolean;
var
  lChildrenValue: TJSONValue;
  lItemValue: TJSONValue;
  lSymbolObject: TJSONObject;
  lValueObject: TJSONObject;
begin
  aError := '';
  for lItemValue in aItems do
  begin
    if not (lItemValue is TJSONObject) then
    begin
      aError := 'a symbol entry is not an object';
      Exit(False);
    end;
    lValueObject := lItemValue as TJSONObject;

    if lValueObject.Values['location'] <> nil then
      lSymbolObject := BuildNormalizedSymbolInformationObject(lValueObject)
    else
      lSymbolObject := BuildNormalizedDocumentSymbolObject(aFilePath, aContainerName, lValueObject);
    if lSymbolObject = nil then
    begin
      aError := 'a symbol entry lacks a name, kind, location or range';
      Exit(False);
    end;
    aTarget.Add(lSymbolObject);

    lChildrenValue := lValueObject.Values['children'];
    if (lChildrenValue = nil) or (lChildrenValue is TJSONNull) then
      Continue;
    if not (lChildrenValue is TJSONArray) then
    begin
      aError := 'symbol children are not an array';
      Exit(False);
    end;
    if not TryCollectNormalizedSymbols(aTarget, lChildrenValue as TJSONArray, aFilePath,
      lValueObject.Values['name'].Value, aError) then
      Exit(False);
  end;
  Result := True;
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

// Document-symbol results: DocumentSymbol[] | SymbolInformation[] | null.
function TryBuildNormalizedSymbolsResult(const aFilePath, aQuery: string; aLimit: Integer;
  aResultValue: TJSONValue; out aResultText: string; out aError: string): Boolean;
var
  lResultObject: TJSONObject;
  lSymbolList: TObjectList<TJSONObject>;
  lSymbolObject: TJSONObject;
  lSymbolsArray: TJSONArray;
begin
  aResultText := '';
  aError := '';
  if (aResultValue <> nil) and not (aResultValue is TJSONNull) and not (aResultValue is TJSONArray) then
  begin
    aError := 'expected DocumentSymbol[], SymbolInformation[] or null';
    Exit(False);
  end;
  lResultObject := TJSONObject.Create;
  lSymbolList := TObjectList<TJSONObject>.Create(True);
  try
    lSymbolsArray := TJSONArray.Create;
    lResultObject.AddPair('symbols', lSymbolsArray);
    if (aResultValue is TJSONArray) and
      not TryCollectNormalizedSymbols(lSymbolList, aResultValue as TJSONArray, aFilePath, '', aError) then
      Exit(False);
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
    aResultText := lResultObject.ToJSON;
    Result := True;
  finally
    lSymbolList.Free;
    lResultObject.Free;
  end;
end;

function TryBuildOperationResultText(const aOptions: TAppOptions; const aRequestFilePath: string;
  aResponse: TJSONObject; out aResultText: string; out aError: string): Boolean;
var
  lDetail: string;
  lOperationName: string;
  lResultValue: TJSONValue;
begin
  aResultText := '';
  aError := '';
  lDetail := '';
  lResultValue := aResponse.Values['result'];
  case aOptions.fLspOperation of
    TLspOperation.loDefinition:
      begin
        lOperationName := 'definition';
        Result := TryBuildNormalizedLocationsResult(lResultValue, aResultText, lDetail);
      end;
    TLspOperation.loHover:
      begin
        lOperationName := 'hover';
        Result := TryBuildNormalizedHoverResult(lResultValue, aResultText, lDetail);
      end;
    TLspOperation.loSymbols:
      begin
        lOperationName := 'symbols';
        Result := TryBuildNormalizedSymbolsResult(aRequestFilePath, aOptions.fLspQuery, aOptions.fLspLimit,
          lResultValue, aResultText, lDetail);
      end;
  else
    aResultText := ExtractRawResultText(aResponse);
    Exit(True);
  end;
  if not Result then
    aError := Format('DelphiLSP %s returned a malformed result: %s.', [lOperationName, lDetail]);
end;

end.
