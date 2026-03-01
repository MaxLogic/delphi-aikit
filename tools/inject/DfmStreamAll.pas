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
  System.Classes, System.SysUtils;

type
  TValidationStats = record
    Errors: Integer;
    Streamed: Integer;
    Skipped: Integer;
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

function TryReadRootComponent(const aStream: TStream; out aErr: string): Boolean;
var
  lComp: TComponent;
  lReader: TReader;
begin
  aErr := '';
  aStream.Position := 0;
  lReader := TReader.Create(aStream, 4096);
  lComp := nil;
  try
    try
      // Missing published properties / missing event handlers typically raise here (EReadError).
      lComp := lReader.ReadRootComponent(nil);
      lComp.Free;
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

procedure ValidateResource(const aModule: HMODULE; const aResourceName: string; var aStats: TValidationStats);
var
  lOpenErr: string;
  lReadErr: string;
  lSigErr: string;
  lStream: TResourceStream;
begin
  if not TryOpenResourceStream(aModule, aResourceName, lStream, lOpenErr) then
  begin
    Inc(aStats.Errors);
    Writeln('FAIL ', aResourceName, ' -> ', lOpenErr);
    Exit;
  end;

  try
    try
      if not IsComponentStream(lStream, lSigErr) then
      begin
        Inc(aStats.Skipped);
        Exit;
      end;

      Inc(aStats.Streamed);
      if not TryReadRootComponent(lStream, lReadErr) then
      begin
        Inc(aStats.Errors);
        Writeln('FAIL ', aResourceName, ' -> ', lReadErr);
      end else
        Writeln('OK   ', aResourceName);
    except
      on E: Exception do
      begin
        Inc(aStats.Errors);
        Writeln('FAIL ', aResourceName, ' -> ', E.ClassName, ': ', E.Message);
      end;
    end;
  finally
    lStream.Free;
  end;
end;

class function TDfmStreamAll.Run: Integer;
var
  i: Integer;
  lResourceName: string;
  lResourceNames: TStringList;
  lStats: TValidationStats;
begin
  lStats := Default(TValidationStats);
  lResourceNames := TStringList.Create;
  try
    lResourceNames.CaseSensitive := False;
    lResourceNames.Sorted := True;
    lResourceNames.Duplicates := TDuplicates.dupIgnore;
    EnumResourceNames(HInstance, RT_RCDATA, @EnumRcDataNameProc, NativeInt(Pointer(lResourceNames)));
    for i := 0 to lResourceNames.Count - 1 do
    begin
      lResourceName := lResourceNames[i];
      ValidateResource(HInstance, lResourceName, lStats);
    end;
  finally
    lResourceNames.Free;
  end;

  Writeln(Format('DFM stream validation summary: streamed=%d skipped=%d failed=%d',
    [lStats.Streamed, lStats.Skipped, lStats.Errors]));
  if lStats.Errors <> 0 then
    Writeln(Format('DFM stream validation failed: %d error(s)', [lStats.Errors]));

  Result := lStats.Errors;
end;

end.
