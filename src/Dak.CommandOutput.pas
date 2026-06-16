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
  System.IOUtils, System.SysUtils;

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

procedure WriteStdout(const aOutputText: string; aLineBreak: Boolean);
begin
  if aLineBreak then
    WriteLn(aOutputText)
  else
    Write(aOutputText);
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
  try
    if ShouldWriteStdout(aOutputPath, aPolicy) then
      WriteStdout(aOutputText, aStdoutLineBreak);

    if ShouldWriteFile(aOutputPath, aPolicy) then
    begin
      WriteFileOutput(aOutputText, aOutputPath, aUtf8Bom);
      if aPublishFileMessage then
        WriteLn('Wrote: ' + aOutputPath);
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
