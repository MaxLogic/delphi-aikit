unit Dak.SourceContext;

interface

uses
  System.Generics.Collections, System.Math, System.SysUtils,
  Dak.Types;

function ShouldEmitSourceContext(const aMode: TSourceContextMode; const aIsError: Boolean): Boolean;
function TryParseFindingLocation(const aFinding: string; out aFileToken: string; out aLineNumber: Integer): Boolean;
function TryResolveSourceContext(const aLookup: TProjectSourceLookup; const aFileToken: string;
  aLineNumber, aContextLines: Integer; out aContext: TSourceContextSnippet; out aError: string): Boolean;
function TryReadSourceContext(const aFilePath: string; aLineNumber, aContextLines: Integer;
  out aContext: TSourceContextSnippet; out aError: string): Boolean;
function FormatSourceContextLines(const aContext: TSourceContextSnippet): TArray<string>;

implementation

uses
  System.Classes, System.IOUtils, System.RegularExpressions;

function ShouldEmitSourceContext(const aMode: TSourceContextMode; const aIsError: Boolean): Boolean;
begin
  case aMode of
    TSourceContextMode.scmOff:
      Result := False;
    TSourceContextMode.scmOn:
      Result := True;
  else
    Result := aIsError;
  end;
end;

function TryParseFindingLocation(const aFinding: string; out aFileToken: string; out aLineNumber: Integer): Boolean;
var
  lMatch: TMatch;
begin
  aFileToken := '';
  aLineNumber := 0;
  lMatch := TRegEx.Match(aFinding, '^(.+)\((\d+)(?:,\d+)?\):');
  if (not lMatch.Success) or (lMatch.Groups.Count < 3) then
    Exit(False);

  aFileToken := Trim(lMatch.Groups[1].Value);
  aLineNumber := StrToIntDef(lMatch.Groups[2].Value, 0);
  Result := (aFileToken <> '') and (aLineNumber > 0);
end;

procedure AddCandidate(const aCandidates: TList<string>; const aSeen: THashSet<string>; const aValue: string);
var
  lPath: string;
begin
  lPath := Trim(aValue);
  if lPath = '' then
    Exit;
  lPath := TPath.GetFullPath(lPath);
  if aSeen.Add(lPath) then
    aCandidates.Add(lPath);
end;

function TryResolveSourceFile(const aLookup: TProjectSourceLookup; const aFileToken: string; out aResolvedPath: string): Boolean;
var
  lBaseName: string;
  lCandidates: TList<string>;
  lFileToken: string;
  lHasDirs: Boolean;
  lPath: string;
  lSearchPath: string;
  lSeen: THashSet<string>;
begin
  aResolvedPath := '';
  lFileToken := Trim(aFileToken).Replace('/', '\', [rfReplaceAll]);
  if lFileToken = '' then
    Exit(False);

  if TPath.IsPathRooted(lFileToken) then
  begin
    if FileExists(lFileToken) then
    begin
      aResolvedPath := TPath.GetFullPath(lFileToken);
      Exit(True);
    end;
    Exit(False);
  end;

  lHasDirs := (Pos('\', lFileToken) > 0) or (Pos('/', lFileToken) > 0);
  lBaseName := TPath.GetFileName(lFileToken);
  lCandidates := TList<string>.Create;
  lSeen := THashSet<string>.Create;
  try
    AddCandidate(lCandidates, lSeen, TPath.Combine(aLookup.fProjectDir, lFileToken));
    if aLookup.fMainSourcePath <> '' then
      AddCandidate(lCandidates, lSeen, TPath.Combine(ExtractFileDir(aLookup.fMainSourcePath), lFileToken));

    for lSearchPath in aLookup.fSearchPaths do
    begin
      AddCandidate(lCandidates, lSeen, TPath.Combine(lSearchPath, lFileToken));
      if lHasDirs then
        AddCandidate(lCandidates, lSeen, TPath.Combine(lSearchPath, lBaseName));
    end;
    AddCandidate(lCandidates, lSeen, TPath.GetFullPath(lFileToken));

    for lPath in lCandidates do
    begin
      if FileExists(lPath) then
      begin
        aResolvedPath := lPath;
        Exit(True);
      end;
    end;
  finally
    lSeen.Free;
    lCandidates.Free;
  end;

  Result := False;
end;

function TryLoadLines(const aFilePath: string; const aLines: TStrings): Boolean;
begin
  Result := False;
  try
    aLines.LoadFromFile(aFilePath, TEncoding.UTF8);
    Exit(True);
  except
    on EEncodingError do
    begin
      // Fall back to the platform default for legacy ANSI Pascal files.
    end;
    on EStreamError do
    begin
      // Retry with the platform default when UTF-8 decoding fails.
    end;
  end;

  try
    aLines.LoadFromFile(aFilePath, TEncoding.Default);
    Result := True;
  except
    Result := False;
  end;
end;

function TryReadSourceContext(const aFilePath: string; aLineNumber, aContextLines: Integer;
  out aContext: TSourceContextSnippet; out aError: string): Boolean;
var
  lEndLine: Integer;
  lLines: TStringList;
  lStartLine: Integer;
  i: Integer;
begin
  Result := False;
  aError := '';
  aContext := Default(TSourceContextSnippet);
  if (aFilePath = '') or (not FileExists(aFilePath)) then
  begin
    aError := 'Source file not found: ' + aFilePath;
    Exit(False);
  end;
  if aLineNumber <= 0 then
  begin
    aError := 'Source line number must be greater than zero.';
    Exit(False);
  end;
  if aContextLines < 0 then
    aContextLines := 0;

  lLines := TStringList.Create;
  try
    if not TryLoadLines(aFilePath, lLines) then
    begin
      aError := 'Failed to read source file: ' + aFilePath;
      Exit(False);
    end;
    if aLineNumber > lLines.Count then
    begin
      aError := Format('Source line %d is outside %s.', [aLineNumber, aFilePath]);
      Exit(False);
    end;

    lStartLine := Max(1, aLineNumber - aContextLines);
    lEndLine := Min(lLines.Count, aLineNumber + aContextLines);
    aContext.fFilePath := TPath.GetFullPath(aFilePath);
    aContext.fTargetLine := aLineNumber;
    aContext.fStartLine := lStartLine;
    SetLength(aContext.fLines, lEndLine - lStartLine + 1);
    for i := lStartLine to lEndLine do
      aContext.fLines[i - lStartLine] := lLines[i - 1];
    Result := True;
  finally
    lLines.Free;
  end;
end;

function TryResolveSourceContext(const aLookup: TProjectSourceLookup; const aFileToken: string;
  aLineNumber, aContextLines: Integer; out aContext: TSourceContextSnippet; out aError: string): Boolean;
var
  lResolvedPath: string;
begin
  aContext := Default(TSourceContextSnippet);
  aError := '';
  if not TryResolveSourceFile(aLookup, aFileToken, lResolvedPath) then
  begin
    aError := 'Could not resolve source file: ' + aFileToken;
    Exit(False);
  end;
  Result := TryReadSourceContext(lResolvedPath, aLineNumber, aContextLines, aContext, aError);
end;

function FormatSourceContextLines(const aContext: TSourceContextSnippet): TArray<string>;
var
  lIndex: Integer;
  lLineNo: Integer;
  lMarker: string;
begin
  SetLength(Result, Length(aContext.fLines) + 1);
  Result[0] := 'source context: ' + aContext.fFilePath;
  for lIndex := 0 to High(aContext.fLines) do
  begin
    lLineNo := aContext.fStartLine + lIndex;
    if lLineNo = aContext.fTargetLine then
      lMarker := '>'
    else
      lMarker := ' ';
    Result[lIndex + 1] := Format('%s %4d | %s', [lMarker, lLineNo, aContext.fLines[lIndex]]);
  end;
end;

end.
