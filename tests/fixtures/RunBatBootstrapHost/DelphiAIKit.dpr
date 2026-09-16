program DelphiAIKit;

{$APPTYPE CONSOLE}

// T-310 stand-in for the DelphiAIKit host that tests/run.bat bootstraps in an isolated tree. It records
// each command line next to itself, prints help text containing every switch run.bat checks, and writes
// the file named by --out-file, so run.bat's bootstrap and first fixture commands can be inspected.

uses
  System.Classes, System.IOUtils, System.SysUtils;

var
  i: Integer;
  lArguments: TStringList;
  lOutFile: string;

begin
  lArguments := TStringList.Create;
  try
    lOutFile := '';
    for i := 1 to ParamCount do
    begin
      lArguments.Add(ParamStr(i));
      if SameText(ParamStr(i), '--out-file') and (i < ParamCount) then
        lOutFile := ParamStr(i + 1);
    end;
    TFile.AppendAllText(TPath.Combine(ExtractFilePath(ParamStr(0)), 'invocations.log'),
      String.Join(' ', lArguments.ToStringArray) + sLineBreak, TEncoding.UTF8);
    Writeln('resolve analyze build --format --out-file --fi-output --fixinsight --pascal-analyzer ' +
      '--exclude-path-masks --ignore-warning-ids --pa-path --pa-output --pa-args');
    if lOutFile <> '' then
      TFile.WriteAllText(lOutFile, 'stand-in output' + sLineBreak, TEncoding.UTF8);
  finally
    lArguments.Free;
  end;
end.
