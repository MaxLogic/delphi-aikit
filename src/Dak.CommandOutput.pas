unit Dak.CommandOutput;

interface

type
  TCommandOutputPolicy = (
    copStdoutWhenNoPathOrDash,
    copStdoutOnlyWhenDash,
    copAlwaysStdoutAndOptionalFile);

function WriteCommandOutput(const aOutputText, aOutputPath: string; aPolicy: TCommandOutputPolicy;
  aStdoutLineBreak, aPublishFileMessage, aUtf8Bom: Boolean; out aError: string): Boolean;

implementation

uses
  System.IOUtils, System.SysUtils,
  Winapi.Windows;

function IsClosedPipeError(aErrorCode: Integer): Boolean;
begin
  Result := (aErrorCode = ERROR_BROKEN_PIPE) or (aErrorCode = ERROR_NO_DATA) or
    (aErrorCode = ERROR_PIPE_NOT_CONNECTED);
end;

function ShouldWriteStdout(const aOutputPath: string; aPolicy: TCommandOutputPolicy): Boolean;
begin
  case aPolicy of
    TCommandOutputPolicy.copStdoutWhenNoPathOrDash:
      Result := (Trim(aOutputPath) = '') or (aOutputPath = '-');
    TCommandOutputPolicy.copStdoutOnlyWhenDash:
      Result := aOutputPath = '-';
    TCommandOutputPolicy.copAlwaysStdoutAndOptionalFile:
      Result := True;
  else
    Result := False;
  end;
end;

function ShouldWriteFile(const aOutputPath: string; aPolicy: TCommandOutputPolicy): Boolean;
begin
  Result := (Trim(aOutputPath) <> '') and (aOutputPath <> '-');
end;

function TryWriteStdout(const aOutputText: string; aLineBreak: Boolean; out aError: string): Boolean;
begin
  aError := '';
  try
    if aLineBreak then
      WriteLn(aOutputText)
    else
      Write(aOutputText);
  except
    on E: EInOutError do
    begin
      if IsClosedPipeError(E.ErrorCode) then
        Exit(True);
      aError := E.Message;
      Exit(False);
    end;
    on E: Exception do
    begin
      aError := E.Message;
      Exit(False);
    end;
  end;
  Result := True;
end;

procedure WriteFileOutput(const aOutputText, aOutputPath: string; aUtf8Bom: Boolean);
var
  lEncoding: TEncoding;
  lOutputDir: string;
begin
  lOutputDir := TPath.GetDirectoryName(aOutputPath);
  if lOutputDir <> '' then
    TDirectory.CreateDirectory(lOutputDir);

  if aUtf8Bom then
    TFile.WriteAllText(aOutputPath, aOutputText, TEncoding.UTF8)
  else
  begin
    lEncoding := TUTF8Encoding.Create(False);
    try
      TFile.WriteAllText(aOutputPath, aOutputText, lEncoding);
    finally
      lEncoding.Free;
    end;
  end;
end;

function WriteCommandOutput(const aOutputText, aOutputPath: string; aPolicy: TCommandOutputPolicy;
  aStdoutLineBreak, aPublishFileMessage, aUtf8Bom: Boolean; out aError: string): Boolean;
begin
  aError := '';
  if ShouldWriteStdout(aOutputPath, aPolicy) and
    (not TryWriteStdout(aOutputText, aStdoutLineBreak, aError)) then
    Exit(False);

  try
    if ShouldWriteFile(aOutputPath, aPolicy) then
    begin
      WriteFileOutput(aOutputText, aOutputPath, aUtf8Bom);
      if aPublishFileMessage and (not TryWriteStdout('Wrote: ' + aOutputPath, True, aError)) then
        Exit(False);
    end;
  except
    on E: Exception do
    begin
      aError := E.Message;
      Exit(False);
    end;
  end;
  Result := True;
end;

end.
