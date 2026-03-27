unit DfmStreamAll;

interface

type
  TDfmStreamAll = class sealed
  public
    class function Run: Integer; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes, System.IOUtils, System.StrUtils, System.SysUtils, Vcl.Forms;

type
  TValidationStats = record
    Errors: Integer;
    Warnings: Integer;
    Matched: Integer;
    Requested: Integer;
    Streamed: Integer;
    Skipped: Integer;
  end;

var
  GQuietOutput: Boolean = False;
  GLogFilePath: string = '';

procedure AppendLogLine(const aText: string);
begin
  if GLogFilePath = '' then
    Exit;
  try
    TFile.AppendAllText(GLogFilePath, aText + sLineBreak, TEncoding.UTF8);
  except
    // Log file output is best-effort and must never break validation.
  end;
end;

procedure EmitLine(const aText: string);
var
  lBytesWritten: Cardinal;
  lLine: UTF8String;
  lStdOut: THandle;
begin
  AppendLogLine(aText);
  if GQuietOutput then
    Exit;

  lLine := UTF8String(aText + sLineBreak);
  lStdOut := GetStdHandle(STD_OUTPUT_HANDLE);
  if (lStdOut <> 0) and (lStdOut <> INVALID_HANDLE_VALUE) then
    WriteFile(lStdOut, Pointer(lLine)^, Length(lLine), lBytesWritten, nil)
  else
  begin
    Writeln(aText);
    Flush(Output);
  end;
end;

function IsComponentStream(const aStream: TStream; out aErr: string): Boolean;
var
  lReader: TReader;
begin
  aErr := '';
  aStream.Position := 0;
  lReader := TReader.Create(aStream, 4096);
  try
    try
      lReader.ReadSignature;
      Result := True;
    except
      on E: Exception do
      begin
        aErr := E.ClassName + ': ' + E.Message;
        Result := False;
      end;
    end;
  finally
    lReader.Free;
  end;
end;

function TryCreateStreamingRootComponent(const aResourceName: string; out aRoot: TComponent; out aErr: string): Boolean;
type
  TCustomFormClass = class of TCustomForm;
var
  lComponentClass: TComponentClass;
  lPersistentClass: TPersistentClass;
begin
  aErr := '';
  aRoot := nil;
  lPersistentClass := GetClass(aResourceName);
  if lPersistentClass = nil then
    Exit(True);
  if not lPersistentClass.InheritsFrom(TComponent) then
    Exit(True);
  lComponentClass := TComponentClass(lPersistentClass);
  try
    if lPersistentClass.InheritsFrom(TCustomForm) then
      aRoot := TCustomFormClass(lComponentClass).CreateNew(nil)
    else
      aRoot := lComponentClass.Create(nil);
    Result := True;
  except
    on E: Exception do
    begin
      aErr := E.ClassName + ': ' + E.Message;
      Result := False;
    end;
  end;
end;

function TryValidateByConstructor(const aResourceName: string; out aErr: string): Boolean;
type
  TCustomFormClass = class of TCustomForm;
var
  lComp: TComponent;
  lPersistentClass: TPersistentClass;
begin
  aErr := '';
  lComp := nil;
  lPersistentClass := GetClass(aResourceName);
  if (lPersistentClass = nil) or (not lPersistentClass.InheritsFrom(TComponent)) then
  begin
    aErr := 'Class not registered for constructor fallback: ' + aResourceName;
    Exit(False);
  end;

  try
    if lPersistentClass.InheritsFrom(TCustomForm) then
      lComp := TCustomFormClass(TComponentClass(lPersistentClass)).Create(nil)
    else
      lComp := TComponentClass(lPersistentClass).Create(nil);
    Result := True;
  except
    on E: Exception do
    begin
      aErr := E.ClassName + ': ' + E.Message;
      Result := False;
    end;
  end;
  lComp.Free;
end;

function ShouldUseConstructorFallbackForFrame(const aResourceName: string; const aErr: string): Boolean;
var
  lPersistentClass: TPersistentClass;
begin
  lPersistentClass := GetClass(aResourceName);
  if (lPersistentClass = nil) or (not lPersistentClass.InheritsFrom(TCustomFrame)) then
    Exit(False);
  Result := StartsText('EComponentError: A component named ', aErr) and EndsText(' already exists', aErr);
end;

function TryReadRootComponent(const aStream: TStream; const aResourceName: string; out aErr: string): Boolean;
var
  lComp: TComponent;
  lFallbackErr: string;
  lReader: TReader;
  lRootCreateErr: string;
begin
  aErr := '';
  aStream.Position := 0;
  if not TryCreateStreamingRootComponent(aResourceName, lComp, lRootCreateErr) then
  begin
    aErr := lRootCreateErr;
    Exit(False);
  end;
  lReader := TReader.Create(aStream, 4096);
  try
    try
      // Missing published properties / missing event handlers typically raise here (EReadError).
      lComp := lReader.ReadRootComponent(lComp);
      Result := True;
    except
      on E: Exception do
      begin
        aErr := E.ClassName + ': ' + E.Message;
        if StartsText('EReadError: Ancestor for ', aErr) then
        begin
          if TryValidateByConstructor(aResourceName, lFallbackErr) then
            Exit(True);
          aErr := aErr + ' (constructor fallback: ' + lFallbackErr + ')';
        end else if ShouldUseConstructorFallbackForFrame(aResourceName, aErr) then
        begin
          if TryValidateByConstructor(aResourceName, lFallbackErr) then
            Exit(True);
          aErr := aErr + ' (frame constructor fallback: ' + lFallbackErr + ')';
        end;
        Result := False;
      end;
    end;
  finally
    lComp.Free;
    lReader.Free;
  end;
end;

function NormalizeResourceName(const aValue: string): string;
begin
  Result := UpperCase(Trim(aValue));
end;

function RemoveKnownDfmSuffix(const aValue: string): string;
begin
  Result := aValue;
  if EndsText('.DFM', Result) then
    Exit(Copy(Result, 1, Length(Result) - 4));
  if EndsText('_DFM', Result) then
    Exit(Copy(Result, 1, Length(Result) - 4));
end;

function NamesMatch(const aResourceName: string; const aRequestedName: string): Boolean;
var
  lRequested: string;
  lResource: string;
begin
  lResource := RemoveKnownDfmSuffix(NormalizeResourceName(aResourceName));
  lRequested := RemoveKnownDfmSuffix(NormalizeResourceName(aRequestedName));
  if (lResource = '') or (lRequested = '') then
    Exit(False);
  if SameText(lResource, lRequested) then
    Exit(True);

  if (Length(lResource) > 1) and (lResource[1] = 'T') and SameText(Copy(lResource, 2, MaxInt), lRequested) then
    Exit(True);
  if (Length(lRequested) > 1) and (lRequested[1] = 'T') and SameText(lResource, Copy(lRequested, 2, MaxInt)) then
    Exit(True);
  Result := False;
end;

function TryMatchRequestedFilter(const aResourceName: string; const aRequestedFilters: TStrings;
  out aMatchedFilter: string): Boolean;
var
  i: Integer;
begin
  aMatchedFilter := '';
  if aRequestedFilters = nil then
    Exit(False);
  for i := 0 to aRequestedFilters.Count - 1 do
  begin
    if not NamesMatch(aResourceName, aRequestedFilters[i]) then
      Continue;
    aMatchedFilter := aRequestedFilters[i];
    Exit(True);
  end;
  Result := False;
end;

function TrimMatchingQuotes(const aValue: string): string;
var
  lValue: string;
begin
  lValue := Trim(aValue);
  if Length(lValue) >= 2 then
  begin
    if ((lValue[1] = '"') and (lValue[Length(lValue)] = '"')) or
      ((lValue[1] = '''') and (lValue[Length(lValue)] = '''')) then
      lValue := Copy(lValue, 2, Length(lValue) - 2);
  end;
  Result := Trim(lValue);
end;

function StartsWithNoCase(const aText: string; const aPrefix: string): Boolean;
begin
  if Length(aText) < Length(aPrefix) then
    Exit(False);
  Result := SameText(Copy(aText, 1, Length(aPrefix)), aPrefix);
end;

function BuildScopePreview(const aRequestedFilters: TStrings): string;
const
  cPreviewMax = 12;
var
  i: Integer;
  lLimit: Integer;
  lPreview: TStringList;
begin
  if (aRequestedFilters = nil) or (aRequestedFilters.Count = 0) then
    Exit('selected resources: <none>');

  if aRequestedFilters.Count <= cPreviewMax then
    Exit('selected resources: ' + String.Join(', ', aRequestedFilters.ToStringArray));

  lPreview := TStringList.Create;
  try
    lLimit := cPreviewMax;
    if aRequestedFilters.Count < lLimit then
      lLimit := aRequestedFilters.Count;
    for i := 0 to lLimit - 1 do
      lPreview.Add(aRequestedFilters[i]);
    Result := Format('selected resources (%d): %s ...', [aRequestedFilters.Count,
      String.Join(', ', lPreview.ToStringArray)]);
  finally
    lPreview.Free;
  end;
end;

procedure AddFilterTokens(const aListValue: string; const aRequestedFilters: TStrings);
var
  lPart: string;
  lParts: TArray<string>;
  lResourceName: string;
begin
  if aRequestedFilters = nil then
    Exit;

  lParts := aListValue.Split([',', ';']);
  for lPart in lParts do
  begin
    lResourceName := NormalizeResourceName(lPart);
    if lResourceName <> '' then
      aRequestedFilters.Add(lResourceName);
  end;
end;

procedure LoadValidatorFilters(const aRequestedFilters: TStrings; out aValidateAll: Boolean);
var
  lArg: string;
  lIndex: Integer;
begin
  aValidateAll := False;
  if aRequestedFilters = nil then
    Exit;

  lIndex := 1;
  while lIndex <= ParamCount do
  begin
    lArg := Trim(ParamStr(lIndex));
    if SameText(lArg, '--all') or SameText(lArg, '-all') then
    begin
      aValidateAll := True;
      aRequestedFilters.Clear;
      Exit;
    end;

    if SameText(lArg, '--dfm') or SameText(lArg, '-dfm') then
    begin
      if lIndex < ParamCount then
      begin
        Inc(lIndex);
        AddFilterTokens(ParamStr(lIndex), aRequestedFilters);
      end;
      Inc(lIndex);
      Continue;
    end;

    if StartsWithNoCase(lArg, '--dfm=') then
      AddFilterTokens(Copy(lArg, Length('--dfm=') + 1, MaxInt), aRequestedFilters)
    else if StartsWithNoCase(lArg, '-dfm=') then
      AddFilterTokens(Copy(lArg, Length('-dfm=') + 1, MaxInt), aRequestedFilters);

    Inc(lIndex);
  end;

  if aRequestedFilters.Count = 0 then
    aValidateAll := True;
end;

procedure LoadRuntimeOptions(out aQuiet: Boolean; out aLogFilePath: string);
var
  lArg: string;
  lIndex: Integer;
begin
  aQuiet := False;
  aLogFilePath := '';

  lIndex := 1;
  while lIndex <= ParamCount do
  begin
    lArg := Trim(ParamStr(lIndex));

    if SameText(lArg, '--quiet') or SameText(lArg, '-quiet') then
    begin
      aQuiet := True;
      Inc(lIndex);
      Continue;
    end;

    if SameText(lArg, '--log-file') or SameText(lArg, '-log-file') then
    begin
      if lIndex < ParamCount then
      begin
        Inc(lIndex);
        aLogFilePath := TrimMatchingQuotes(ParamStr(lIndex));
      end;
      Inc(lIndex);
      Continue;
    end;

    if StartsWithNoCase(lArg, '--log-file=') then
      aLogFilePath := TrimMatchingQuotes(Copy(lArg, Length('--log-file=') + 1, MaxInt))
    else if StartsWithNoCase(lArg, '-log-file=') then
      aLogFilePath := TrimMatchingQuotes(Copy(lArg, Length('-log-file=') + 1, MaxInt));

    Inc(lIndex);
  end;
end;

procedure LoadProgressOption(out aProgress: Boolean);
var
  lArg: string;
  lIndex: Integer;
begin
  aProgress := False;
  lIndex := 1;
  while lIndex <= ParamCount do
  begin
    lArg := Trim(ParamStr(lIndex));
    if SameText(lArg, '--progress') or SameText(lArg, '-progress') then
    begin
      aProgress := True;
      Exit;
    end;
    Inc(lIndex);
  end;
end;

function EnumRcDataNameProc(aModule: HMODULE; aType, aName: PChar; aParam: NativeInt): BOOL; stdcall;
var
  lResourceNames: TStrings;
  lResourceName: string;
begin
  lResourceNames := TStrings(Pointer(aParam));
  if lResourceNames = nil then
    Exit(True);

  if (NativeUInt(aName) shr 16) = 0 then
    lResourceName := Format('#%d', [NativeUInt(aName)])
  else
    lResourceName := string(aName);
  lResourceNames.Add(lResourceName);
  Result := True;
end;

function TryOpenResourceStream(const aModule: HMODULE; const aResourceName: string; out aStream: TResourceStream;
  out aErr: string): Boolean;
var
  lId: Integer;
begin
  aErr := '';
  aStream := nil;
  try
    if (Length(aResourceName) > 1) and (aResourceName[1] = '#') and
      TryStrToInt(Copy(aResourceName, 2, MaxInt), lId) and (lId >= 0) then
      aStream := TResourceStream.Create(aModule, PChar(NativeUInt(lId)), RT_RCDATA)
    else
      aStream := TResourceStream.Create(aModule, PChar(aResourceName), RT_RCDATA);
    Result := True;
  except
    on E: Exception do
    begin
      aErr := E.ClassName + ': ' + E.Message;
      Result := False;
    end;
  end;
end;

function ExtractExceptionClassName(const aErr: string): string;
var
  lPos: Integer;
begin
  Result := Trim(aErr);
  if Result = '' then
    Exit('');
  lPos := Pos(':', Result);
  if lPos > 0 then
    Result := Trim(Copy(Result, 1, lPos - 1));
end;

function IsStructuralStreamingError(const aErr: string): Boolean;
var
  lClassName: string;
begin
  lClassName := UpperCase(ExtractExceptionClassName(aErr));
  Result := (lClassName = 'EREADERROR') or
    (lClassName = 'ECLASSNOTFOUND') or
    (lClassName = 'EPARSERERROR') or
    (lClassName = 'EPROPERTYERROR');
end;

procedure ValidateResource(const aModule: HMODULE; const aResourceName: string; const aRequiredSelection: Boolean;
  var aStats: TValidationStats);
var
  lOpenErr: string;
  lReadErr: string;
  lSigErr: string;
  lStream: TResourceStream;
begin
  if not TryOpenResourceStream(aModule, aResourceName, lStream, lOpenErr) then
  begin
    Inc(aStats.Errors);
    EmitLine('FAIL ' + aResourceName + ' -> ' + lOpenErr);
    Exit;
  end;

  try
    try
      if not IsComponentStream(lStream, lSigErr) then
      begin
        if aRequiredSelection then
        begin
          Inc(aStats.Errors);
          if lSigErr <> '' then
            EmitLine('FAIL ' + aResourceName + ' -> Not a Delphi component stream: ' + lSigErr)
          else
            EmitLine('FAIL ' + aResourceName + ' -> Not a Delphi component stream');
        end else
          Inc(aStats.Skipped);
        Exit;
      end;

      Inc(aStats.Streamed);
      if not TryReadRootComponent(lStream, aResourceName, lReadErr) then
      begin
        if IsStructuralStreamingError(lReadErr) then
        begin
          Inc(aStats.Errors);
          EmitLine('FAIL ' + aResourceName + ' -> ' + lReadErr);
        end else
        begin
          Inc(aStats.Warnings);
          EmitLine('WARN ' + aResourceName + ' -> ' + lReadErr);
        end;
      end else
        EmitLine('OK   ' + aResourceName);
    except
      on E: Exception do
      begin
        lReadErr := E.ClassName + ': ' + E.Message;
        if IsStructuralStreamingError(lReadErr) then
        begin
          Inc(aStats.Errors);
          EmitLine('FAIL ' + aResourceName + ' -> ' + lReadErr);
        end else
        begin
          Inc(aStats.Warnings);
          EmitLine('WARN ' + aResourceName + ' -> ' + lReadErr);
        end;
      end;
    end;
  finally
    lStream.Free;
  end;
end;

class function TDfmStreamAll.Run: Integer;
var
  i: Integer;
  lIsComponent: Boolean;
  lIsComponentErr: string;
  lLogFilePath: string;
  lMatchedFilterName: string;
  lMatchedFilters: TStringList;
  lOpenErr: string;
  lProgress: Boolean;
  lQuietOutput: Boolean;
  lRequestedFilters: TStringList;
  lResourceName: string;
  lResourceNames: TStringList;
  lShowProgress: Boolean;
  lStream: TResourceStream;
  lStats: TValidationStats;
  lValidationNames: TStringList;
  lValidateAll: Boolean;
begin
  LoadRuntimeOptions(lQuietOutput, lLogFilePath);
  LoadProgressOption(lProgress);
  GQuietOutput := lQuietOutput;
  GLogFilePath := lLogFilePath;
  if (GLogFilePath <> '') and FileExists(GLogFilePath) then
  begin
    try
      TFile.Delete(GLogFilePath);
    except
      // Continue even when cleanup of previous log fails.
    end;
  end;

  lStats := Default(TValidationStats);
  EmitLine('DFM stream validation started...');
  lRequestedFilters := TStringList.Create;
  lMatchedFilters := TStringList.Create;
  lResourceNames := TStringList.Create;
  lValidationNames := TStringList.Create;
  try
    lRequestedFilters.CaseSensitive := False;
    lRequestedFilters.Sorted := True;
    lRequestedFilters.Duplicates := TDuplicates.dupIgnore;
    lMatchedFilters.CaseSensitive := False;
    lMatchedFilters.Sorted := True;
    lMatchedFilters.Duplicates := TDuplicates.dupIgnore;
    LoadValidatorFilters(lRequestedFilters, lValidateAll);

    lStats.Requested := lRequestedFilters.Count;
    if lValidateAll then
      EmitLine('DFM stream validation scope: all resources')
    else
      EmitLine('DFM stream validation scope: ' + BuildScopePreview(lRequestedFilters));

    lResourceNames.CaseSensitive := False;
    lResourceNames.Sorted := True;
    lResourceNames.Duplicates := TDuplicates.dupIgnore;
    lValidationNames.CaseSensitive := False;
    lValidationNames.Sorted := False;
    lValidationNames.Duplicates := TDuplicates.dupIgnore;
    EnumResourceNames(HInstance, RT_RCDATA, @EnumRcDataNameProc, NativeInt(Pointer(lResourceNames)));
    for i := 0 to lResourceNames.Count - 1 do
    begin
      lResourceName := lResourceNames[i];
      if not lValidateAll then
      begin
        if not TryMatchRequestedFilter(lResourceName, lRequestedFilters, lMatchedFilterName) then
          Continue;
        lMatchedFilters.Add(lMatchedFilterName);
      end;

      if not TryOpenResourceStream(HInstance, lResourceName, lStream, lOpenErr) then
      begin
        Inc(lStats.Errors);
        EmitLine('FAIL ' + lResourceName + ' -> ' + lOpenErr);
        Continue;
      end;

      try
        lIsComponent := IsComponentStream(lStream, lIsComponentErr);
      finally
        lStream.Free;
      end;

      if not lIsComponent then
      begin
        if lValidateAll then
          Inc(lStats.Skipped)
        else
        begin
          Inc(lStats.Errors);
          if lIsComponentErr <> '' then
            EmitLine('FAIL ' + lResourceName + ' -> Not a Delphi component stream: ' + lIsComponentErr)
          else
            EmitLine('FAIL ' + lResourceName + ' -> Not a Delphi component stream');
        end;
        Continue;
      end;

      lValidationNames.Add(lResourceName);
    end;

    lShowProgress := lProgress or lValidateAll;
    for i := 0 to lValidationNames.Count - 1 do
    begin
      lResourceName := lValidationNames[i];
      if lShowProgress then
        EmitLine(Format('CHECK %d/%d %s', [i + 1, lValidationNames.Count, lResourceName]));
      ValidateResource(HInstance, lResourceName, not lValidateAll, lStats);
    end;

    lStats.Matched := lMatchedFilters.Count;

    if not lValidateAll then
    begin
      for i := 0 to lRequestedFilters.Count - 1 do
      begin
        lResourceName := lRequestedFilters[i];
        if lMatchedFilters.IndexOf(lResourceName) >= 0 then
          Continue;
        Inc(lStats.Errors);
        EmitLine('FAIL ' + lResourceName + ' -> Requested DFM resource was not found in module');
      end;
    end;
  finally
    lValidationNames.Free;
    lMatchedFilters.Free;
    lRequestedFilters.Free;
    lResourceNames.Free;
  end;

  EmitLine(Format('DFM stream validation summary: streamed=%d skipped=%d failed=%d requested=%d matched=%d',
    [lStats.Streamed, lStats.Skipped, lStats.Errors, lStats.Requested, lStats.Matched]));
  if lStats.Warnings <> 0 then
    EmitLine(Format('DFM stream validation warnings: %d warning(s)', [lStats.Warnings]));
  if lStats.Errors <> 0 then
    EmitLine(Format('DFM stream validation failed: %d error(s)', [lStats.Errors]));

  Result := lStats.Errors;
end;

end.
