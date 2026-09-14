unit Dak.Analysis.WorkspaceCommand;

interface

uses
  System.JSON,
  Dak.Types;

// The caller owns aDocument when inspection returns complete or partial evidence.
function InspectAnalysisWorkspace(const aOptions: TAppOptions;
  out aDocument: TJSONObject; out aError: string): Integer;
function RunAnalyzeWorkspaceCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.Classes, System.IOUtils, System.SysUtils,
  AutoFree,
  Dak.Analysis.Workspace, Dak.CommandOutput, Dak.ExitCodes, Dak.Settings, Dak.Utils;

const
  cExitWorkspacePartial = 3;

function ResolveWorkspaceSubject(const aOptions: TAppOptions;
  out aSubject: string; out aError: string): Boolean;
var
  lUnit: string;
begin
  aError := '';
  if (aOptions.fDprojPath = '') = (aOptions.fUnitPath = '') then
  begin
    aError := 'Workspace inspection requires exactly one of --project or --unit.';
    Exit(False);
  end;
  if aOptions.fDprojPath <> '' then
  begin
    if aOptions.fHasProjectContextPath then
    begin
      aError := '--project-context requires --unit.';
      Exit(False);
    end;
    Exit(TryResolveDprojPath(aOptions.fDprojPath, aSubject, aError));
  end;
  if not TryResolveAbsolutePath(aOptions.fUnitPath, lUnit, aError) then
    Exit(False);
  if not SameText(ExtractFileExt(lUnit), '.pas') or not TFile.Exists(lUnit) then
  begin
    aError := 'Workspace inspection requires an existing Pascal unit: ' + lUnit;
    Exit(False);
  end;
  if aOptions.fHasProjectContextPath then
    Exit(TryResolveDprojPath(aOptions.fProjectContextPath, aSubject, aError));
  aSubject := lUnit;
  Result := True;
end;

function InspectAnalysisWorkspace(const aOptions: TAppOptions;
  out aDocument: TJSONObject; out aError: string): Integer;
var
  lDocument: TJSONObject;
  lProvenance: TJSONObject;
  lSettings: TDakSettings;
  lSubject: string;
  lWorkspace: TJSONObject;
begin
  aDocument := nil;
  aError := '';
  Result := cExitInvalidArgs;
  try
    if not ResolveWorkspaceSubject(aOptions, lSubject, aError) then
      Exit;
    if not LoadDakSettings(nil, lSubject, nil, aOptions.fWorkspaceRoot, lSettings) then
    begin
      aError := lSettings.fError;
      Exit;
    end;
    Result := cExitEnvironmentError;
    // Capture uses pipes; reusing an existing subject directory creates no .dak entry in SVN status.
    // --out remains a compatible scratch hint, with no output mutation during inspection.
    // Transfer the document to our caller without cloning the potentially large changed-file list.
    lDocument := TJSONObject.Create;
    try
      lProvenance := CaptureRunProvenance(lSettings.fWorkspace, ParamStr(0), ExtractFileDir(lSubject));
      lDocument.AddPair('provenance', lProvenance);
      lWorkspace := TJSONObject.Create;
      lDocument.AddPair('workspace', lWorkspace);
      lWorkspace.AddPair('root', lProvenance.GetValue<TJSONObject>('target').GetValue<string>('root'));
      lWorkspace.AddPair('selector', lSettings.fWorkspace.fSelector);
      lWorkspace.AddPair('vcs', lSettings.fWorkspace.fVcs);
      lWorkspace.AddPair('source', lSettings.fWorkspace.fSource);
      Result := cExitSuccess;
      if (lProvenance.GetValue<TJSONObject>('target').GetValue<string>('status', '') = 'unavailable') or
        (lProvenance.GetValue<TJSONObject>('dak').GetValue<string>('status', '') = 'unavailable') then
        Result := cExitWorkspacePartial;
      aDocument := lDocument;
      lDocument := nil;
    finally
      lDocument.Free;
    end;
  except
    on e: EArgumentException do
    begin
      aError := e.Message;
      Result := cExitInvalidArgs;
    end;
    on e: EInOutError do
      aError := e.Message;
    on e: EStreamError do
      aError := e.Message;
    on e: EOSError do
      aError := e.Message;
  end;
end;

function RunAnalyzeWorkspaceCommand(const aOptions: TAppOptions): Integer;
var
  g: TGarbos;
  lDocument: TJSONObject;
  lError: string;
  lProvenance: TJSONObject;
  lText: string;
  lWorkspace: TJSONObject;
begin
  Result := InspectAnalysisWorkspace(aOptions, lDocument, lError);
  GC(lDocument, g);
  if lDocument = nil then
  begin
    WriteLn(ErrOutput, lError);
    Exit;
  end;
  if aOptions.fWorkspaceJson then
    lText := lDocument.ToJSON
  else
  begin
    lWorkspace := lDocument.GetValue<TJSONObject>('workspace');
    lProvenance := lDocument.GetValue<TJSONObject>('provenance');
    lText := 'Workspace: ' + lWorkspace.GetValue<string>('root') + sLineBreak +
      'Selection: ' + lWorkspace.GetValue<string>('selector') + ' from ' +
      lWorkspace.GetValue<string>('source') + sLineBreak +
      'Target provenance: ' + lProvenance.GetValue<TJSONObject>('target').GetValue<string>('status') + sLineBreak +
      'DAK provenance: ' + lProvenance.GetValue<TJSONObject>('dak').GetValue<string>('status', 'not_applicable');
  end;
  if not WriteCommandOutput(lText, '', TCommandOutputPolicy.copStdoutWhenNoPathOrDash,
    True, False, False, lError) then
  begin
    WriteLn(ErrOutput, lError);
    Result := cExitEnvironmentError;
  end;
end;

end.
