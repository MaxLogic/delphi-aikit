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
  System.Classes, System.SysUtils,
  autoFree;

type
  TEnumCtx = record
    Errors: Integer;
  end;
  PEnumCtx = ^TEnumCtx;

function IsComponentStream(const aStream: TStream; out aErr: string): Boolean;
var
  lGarbo: iGarbo;
  lReader: TReader;
begin
  aErr := '';
  aStream.Position := 0;

  lReader := nil;
  lGarbo := gc(lReader, TReader.Create(aStream, 4096));

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
end;

function TryReadRootComponent(const aStream: TStream; out aErr: string): Boolean;
var
  lGarboComp: iGarbo;
  lGarboReader: iGarbo;
  lComp: TComponent;
  lReader: TReader;
begin
  aErr := '';
  aStream.Position := 0;

  lReader := nil;
  lGarboReader := gc(lReader, TReader.Create(aStream, 4096));

  lComp := nil;
  try
    // Missing published properties / missing event handlers typically raise here (EReadError).
    lComp := lReader.ReadRootComponent(nil);
    lGarboComp := gc(lComp, lComp);
    Result := True;
  except
    on E: Exception do
    begin
      aErr := E.ClassName + ': ' + E.Message;
      Result := False;
    end;
  end;
end;

function EnumRcDataProc(aModule: HMODULE; aType, aName: PChar; aParam: NativeInt): BOOL; stdcall;
var
  lCtx: PEnumCtx;
  lGarbo: iGarbo;
  lName: string;
  lReadErr: string;
  lSigErr: string;
  lStream: TResourceStream;
begin
  Result := True;
  lCtx := PEnumCtx(aParam);

  if NativeUInt(aName) shr 16 = 0 then
    lName := Format('#%d', [NativeUInt(aName)])
  else
    lName := string(aName);

  lStream := nil;
  try
    lGarbo := gc(lStream, TResourceStream.Create(aModule, aName, RT_RCDATA));

    // Filter: not every RCDATA resource is a DFM. ReadSignature is a cheap discriminator.
    if not IsComponentStream(lStream, lSigErr) then
      Exit(True);

    if not TryReadRootComponent(lStream, lReadErr) then
    begin
      Inc(lCtx^.Errors);
      Writeln('FAIL ', lName, ' -> ', lReadErr);
    end else
      Writeln('OK   ', lName);

  except
    on E: Exception do
    begin
      Inc(lCtx^.Errors);
      Writeln('FAIL ', lName, ' -> ', E.ClassName, ': ', E.Message);
    end;
  end;
end;

class function TDfmStreamAll.Run: Integer;
var
  lCtx: TEnumCtx;
begin
  lCtx.Errors := 0;

  EnumResourceNames(HInstance, RT_RCDATA, @EnumRcDataProc, NativeInt(@lCtx));

  if lCtx.Errors <> 0 then
    Writeln(Format('DFM stream validation failed: %d error(s)', [lCtx.Errors]));

  Result := lCtx.Errors;
end;

end.
