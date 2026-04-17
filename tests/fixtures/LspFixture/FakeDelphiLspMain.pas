unit FakeDelphiLspMain;

interface

function RunFakeDelphiLsp: Integer;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.JSON, System.SysUtils,
  Winapi.Windows;

function CloneJsonValue(aValue: TJSONValue): TJSONValue;
begin
  if aValue = nil then
    Exit(nil);
  Result := TJSONObject.ParseJSONValue(aValue.ToJSON);
end;

function ReadCommandLineValue(const aName: string): string;
var
  i: Integer;
  lArg: string;
begin
  Result := '';
  for i := 1 to ParamCount do
  begin
    lArg := ParamStr(i);
    if SameText(lArg, aName) and (i < ParamCount) then
      Exit(ParamStr(i + 1));
  end;
end;

function ResolveScriptPath: string;
begin
  Result := ReadCommandLineValue('--script');
  if Trim(Result) = '' then
    Result := Trim(GetEnvironmentVariable('DAK_FAKE_LSP_SCRIPT'));
end;

function ReadLine(aStream: THandleStream; out aLine: string): Boolean;
var
  lBuilder: TStringBuilder;
  lByte: Byte;
  lCount: Integer;
begin
  aLine := '';
  lBuilder := TStringBuilder.Create;
  try
    while True do
    begin
      lCount := aStream.Read(lByte, 1);
      if lCount <> 1 then
        Exit(False);
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

function ReadMessage(aStream: THandleStream; out aBody: string): Boolean;
var
  lBodyBytes: TBytes;
  lContentLength: Integer;
  lLine: string;
  lOffset: Integer;
  lRead: Integer;
begin
  aBody := '';
  lContentLength := -1;
  while True do
  begin
    if not ReadLine(aStream, lLine) then
      Exit(False);
    if lLine = '' then
      Break;
    if SameText(Copy(lLine, 1, Length('Content-Length:')), 'Content-Length:') then
      lContentLength := StrToInt(Trim(Copy(lLine, Length('Content-Length:') + 1, MaxInt)));
  end;
  if lContentLength < 0 then
    raise Exception.Create('Missing Content-Length header.');
  SetLength(lBodyBytes, lContentLength);
  lOffset := 0;
  while lOffset < lContentLength do
  begin
    lRead := aStream.Read(lBodyBytes[lOffset], lContentLength - lOffset);
    if lRead <= 0 then
      raise Exception.Create('Unexpected end of stream while reading body.');
    Inc(lOffset, lRead);
  end;
  aBody := TEncoding.UTF8.GetString(lBodyBytes);
  Result := True;
end;

procedure WriteMessage(aStream: THandleStream; const aBody: string);
var
  lBodyBytes: TBytes;
  lHeaderBytes: TBytes;
  lHeaderText: string;
begin
  lBodyBytes := TEncoding.UTF8.GetBytes(aBody);
  lHeaderText := 'Content-Length: ' + IntToStr(Length(lBodyBytes)) + #13#10#13#10;
  lHeaderBytes := TEncoding.ASCII.GetBytes(lHeaderText);
  if Length(lHeaderBytes) > 0 then
    aStream.WriteBuffer(lHeaderBytes[0], Length(lHeaderBytes));
  if Length(lBodyBytes) > 0 then
    aStream.WriteBuffer(lBodyBytes[0], Length(lBodyBytes));
end;

function LoadScript(const aScriptPath: string): TJSONObject;
var
  lJsonValue: TJSONValue;
begin
  Result := TJSONObject.Create;
  if Trim(aScriptPath) = '' then
    Exit(Result);
  lJsonValue := TJSONObject.ParseJSONValue(TFile.ReadAllText(aScriptPath, TEncoding.UTF8));
  if not (lJsonValue is TJSONObject) then
  begin
    lJsonValue.Free;
    raise Exception.Create('FakeDelphiLsp script must be a JSON object.');
  end;
  Result.Free;
  Result := lJsonValue as TJSONObject;
end;

function FindScriptSection(aScript: TJSONObject; const aSectionName: string): TJSONObject;
begin
  Result := nil;
  if aScript = nil then
    Exit(nil);
  if not (aScript.Values[aSectionName] is TJSONObject) then
    Exit(nil);
  Result := aScript.Values[aSectionName] as TJSONObject;
end;

function FindScriptResponse(aScript: TJSONObject; const aMethod: string): TJSONValue;
var
  lResponses: TJSONObject;
begin
  Result := nil;
  lResponses := FindScriptSection(aScript, 'responses');
  if (lResponses = nil) or (lResponses.Values[aMethod] = nil) then
    Exit(nil);
  Result := CloneJsonValue(lResponses.Values[aMethod]);
end;

function TryFindScriptError(aScript: TJSONObject; const aMethod: string; out aCode: Integer; out aMessage: string): Boolean;
var
  lErrors: TJSONObject;
  lErrorObject: TJSONObject;
begin
  Result := False;
  aCode := 0;
  aMessage := '';
  lErrors := FindScriptSection(aScript, 'errors');
  if (lErrors = nil) or not (lErrors.Values[aMethod] is TJSONObject) then
    Exit(False);
  lErrorObject := lErrors.Values[aMethod] as TJSONObject;
  aCode := StrToIntDef(lErrorObject.GetValue<string>('code', '0'), 0);
  aMessage := lErrorObject.GetValue<string>('message', '');
  Result := True;
end;

function BuildInitializeResult(aScript: TJSONObject): TJSONValue;
var
  lValue: TJSONValue;
  lResult: TJSONObject;
begin
  lValue := nil;
  if aScript <> nil then
    lValue := aScript.Values['initializeResult'];
  if lValue <> nil then
    Exit(CloneJsonValue(lValue));
  lResult := TJSONObject.Create;
  lResult.AddPair('capabilities',
    TJSONObject.Create
      .AddPair('definitionProvider', TJSONBool.Create(True))
      .AddPair('referencesProvider', TJSONBool.Create(True))
      .AddPair('hoverProvider', TJSONBool.Create(True))
      .AddPair('documentSymbolProvider', TJSONBool.Create(True))
      .AddPair('workspaceSymbolProvider', TJSONBool.Create(True)));
  Result := lResult;
end;

function ScriptRequiresOpenedDocuments(aScript: TJSONObject): Boolean;
var
  lValue: TJSONValue;
begin
  Result := False;
  if aScript = nil then
    Exit(False);
  lValue := aScript.Values['requireOpenedDocuments'];
  if lValue = nil then
    Exit(False);
  if lValue is TJSONTrue then
    Exit(True);
  if lValue is TJSONFalse then
    Exit(False);
  Result := SameText(lValue.Value, 'true') or (lValue.Value = '1');
end;

function TryGetTextDocumentUri(aMessage: TJSONObject; out aUri: string): Boolean;
var
  lParams: TJSONObject;
  lTextDocument: TJSONObject;
begin
  Result := False;
  aUri := '';
  if (aMessage = nil) or not (aMessage.Values['params'] is TJSONObject) then
    Exit(False);
  lParams := aMessage.Values['params'] as TJSONObject;
  if not (lParams.Values['textDocument'] is TJSONObject) then
    Exit(False);
  lTextDocument := lParams.Values['textDocument'] as TJSONObject;
  aUri := Trim(lTextDocument.GetValue<string>('uri', ''));
  Result := aUri <> '';
end;

function JsonValuesMatch(aExpected, aActual: TJSONValue): Boolean;
var
  i: Integer;
  lActualArray: TJSONArray;
  lActualObject: TJSONObject;
  lExpectedArray: TJSONArray;
  lExpectedObject: TJSONObject;
  lExpectedPair: TJSONPair;
begin
  if aExpected = nil then
    Exit(aActual = nil);
  if aActual = nil then
    Exit(False);

  if aExpected is TJSONObject then
  begin
    if not (aActual is TJSONObject) then
      Exit(False);
    lExpectedObject := aExpected as TJSONObject;
    lActualObject := aActual as TJSONObject;
    for lExpectedPair in lExpectedObject do
    begin
      if not JsonValuesMatch(lExpectedPair.JsonValue, lActualObject.Values[lExpectedPair.JsonString.Value]) then
        Exit(False);
    end;
    Exit(True);
  end;

  if aExpected is TJSONArray then
  begin
    if not (aActual is TJSONArray) then
      Exit(False);
    lExpectedArray := aExpected as TJSONArray;
    lActualArray := aActual as TJSONArray;
    if lExpectedArray.Count <> lActualArray.Count then
      Exit(False);
    for i := 0 to lExpectedArray.Count - 1 do
    begin
      if not JsonValuesMatch(lExpectedArray.Items[i], lActualArray.Items[i]) then
        Exit(False);
    end;
    Exit(True);
  end;

  Result := aExpected.ToJSON = aActual.ToJSON;
end;

function TryCheckScriptExpectation(aScript: TJSONObject; const aMethod: string; aMessage: TJSONObject;
  out aErrorMessage: string): Boolean;
var
  lExpectations: TJSONObject;
  lExpectedValue: TJSONValue;
  lParamsValue: TJSONValue;
begin
  Result := True;
  aErrorMessage := '';
  lExpectations := FindScriptSection(aScript, 'expect');
  if (lExpectations = nil) or (lExpectations.Values[aMethod] = nil) then
    Exit(True);
  lExpectedValue := lExpectations.Values[aMethod];
  lParamsValue := aMessage.Values['params'];
  if JsonValuesMatch(lExpectedValue, lParamsValue) then
    Exit(True);
  aErrorMessage := 'Request expectation failed for ' + aMethod + '.';
  Result := False;
end;

procedure SendResult(aOutput: THandleStream; aId: TJSONValue; aResult: TJSONValue);
var
  lResponse: TJSONObject;
begin
  lResponse := TJSONObject.Create;
  try
    lResponse.AddPair('jsonrpc', '2.0');
    lResponse.AddPair('id', CloneJsonValue(aId));
    lResponse.AddPair('result', aResult);
    WriteMessage(aOutput, lResponse.ToJSON);
  finally
    lResponse.Free;
  end;
end;

procedure SendError(aOutput: THandleStream; aId: TJSONValue; aCode: Integer; const aMessage: string);
var
  lErrorObject: TJSONObject;
  lResponse: TJSONObject;
begin
  lResponse := TJSONObject.Create;
  try
    lErrorObject := TJSONObject.Create;
    lErrorObject.AddPair('code', TJSONNumber.Create(aCode));
    lErrorObject.AddPair('message', aMessage);
    lResponse.AddPair('jsonrpc', '2.0');
    lResponse.AddPair('id', CloneJsonValue(aId));
    lResponse.AddPair('error', lErrorObject);
    WriteMessage(aOutput, lResponse.ToJSON);
  finally
    lResponse.Free;
  end;
end;

function RunFakeDelphiLsp: Integer;
var
  lBody: string;
  lErrorCode: Integer;
  lErrorMessage: string;
  lIdValue: TJSONValue;
  lInput: THandleStream;
  lMessage: TJSONObject;
  lMethod: string;
  lOpenedDocuments: TDictionary<string, Boolean>;
  lOutput: THandleStream;
  lRequireOpenedDocuments: Boolean;
  lResultValue: TJSONValue;
  lScript: TJSONObject;
  lScriptPath: string;
  lShouldExit: Boolean;
  lUri: string;
  lExpectationError: string;
begin
  Result := 0;
  lScriptPath := ResolveScriptPath;
  lScript := nil;
  lInput := nil;
  lOpenedDocuments := nil;
  lOutput := nil;
  try
    lScript := LoadScript(lScriptPath);
    lRequireOpenedDocuments := ScriptRequiresOpenedDocuments(lScript);
    lInput := THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
    lOpenedDocuments := TDictionary<string, Boolean>.Create;
    lOutput := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
    lShouldExit := False;
    while not lShouldExit do
    begin
      if not ReadMessage(lInput, lBody) then
        Break;
      lMessage := TJSONObject.ParseJSONValue(lBody) as TJSONObject;
      if lMessage = nil then
        raise Exception.Create('Invalid JSON-RPC payload.');
      try
        lMethod := lMessage.GetValue<string>('method', '');
        if SameText(lMethod, 'exit') then
        begin
          lShouldExit := True;
          Continue;
        end;

        if SameText(lMethod, 'textDocument/didOpen') then
        begin
          if TryGetTextDocumentUri(lMessage, lUri) then
            lOpenedDocuments.AddOrSetValue(lUri, True);
          Continue;
        end;

        lIdValue := lMessage.Values['id'];
        if lIdValue = nil then
          Continue;

        if SameText(lMethod, 'initialize') then
        begin
          if TryFindScriptError(lScript, lMethod, lErrorCode, lErrorMessage) then
          begin
            SendError(lOutput, lIdValue, lErrorCode, lErrorMessage);
            Continue;
          end;
          SendResult(lOutput, lIdValue, BuildInitializeResult(lScript));
          Continue;
        end;

        if SameText(lMethod, 'shutdown') then
        begin
          SendResult(lOutput, lIdValue, TJSONNull.Create);
          Continue;
        end;

        if lRequireOpenedDocuments and SameText(Copy(lMethod, 1, Length('textDocument/')), 'textDocument/') and
          TryGetTextDocumentUri(lMessage, lUri) and (not lOpenedDocuments.ContainsKey(lUri)) then
        begin
          SendError(lOutput, lIdValue, -32002, 'Document not opened: ' + lUri);
          Continue;
        end;

        if not TryCheckScriptExpectation(lScript, lMethod, lMessage, lExpectationError) then
        begin
          SendError(lOutput, lIdValue, -32003, lExpectationError);
          Continue;
        end;

        if TryFindScriptError(lScript, lMethod, lErrorCode, lErrorMessage) then
        begin
          SendError(lOutput, lIdValue, lErrorCode, lErrorMessage);
          Continue;
        end;

        lResultValue := FindScriptResponse(lScript, lMethod);
        if lResultValue = nil then
          lResultValue := TJSONNull.Create;
        SendResult(lOutput, lIdValue, lResultValue);
      finally
        lMessage.Free;
      end;
    end;
  finally
    lOutput.Free;
    lOpenedDocuments.Free;
    lInput.Free;
    lScript.Free;
  end;
end;

end.
