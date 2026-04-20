unit Dak.SourceContext;

interface

uses
  System.Generics.Collections, System.Math, System.SysUtils,
  Dak.Types;

function ShouldEmitSourceContext(const aMode: TSourceContextMode; const aIsError: Boolean): Boolean;
function TryParseFindingLocation(const aFinding: string; out aFileToken: string; out aLineNumber: Integer): Boolean;
function TryParseFindingLocationWithColumn(const aFinding: string; out aFileToken: string; out aLineNumber,
  aColNumber: Integer): Boolean;
function TryResolveSourceContext(const aLookup: TProjectSourceLookup; const aFileToken: string;
  aLineNumber, aContextLines: Integer; out aContext: TSourceContextSnippet; out aError: string): Boolean;
function TryResolveSourceContextCandidate(const aLookup: TProjectSourceLookup; const aFinding: string;
  aContextLines: Integer; out aContext: TSourceContextSnippet; out aToken: string; out aEnclosingSymbol: string;
  out aError: string): Boolean;
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
  lColNumber: Integer;
begin
  Result := TryParseFindingLocationWithColumn(aFinding, aFileToken, aLineNumber, lColNumber);
end;

function TryParseFindingLocationWithColumn(const aFinding: string; out aFileToken: string; out aLineNumber,
  aColNumber: Integer): Boolean;
var
  lMatch: TMatch;
begin
  aFileToken := '';
  aLineNumber := 0;
  aColNumber := 0;
  lMatch := TRegEx.Match(aFinding, '^(.+)\((\d+)(?:,(\d+))?\):');
  if (not lMatch.Success) or (lMatch.Groups.Count < 3) then
    Exit(False);

  aFileToken := Trim(lMatch.Groups[1].Value);
  aLineNumber := StrToIntDef(lMatch.Groups[2].Value, 0);
  if lMatch.Groups.Count >= 4 then
    aColNumber := StrToIntDef(lMatch.Groups[3].Value, 0);
  Result := (aFileToken <> '') and (aLineNumber > 0) and ((aColNumber = 0) or (aColNumber > 0));
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

function IsIdentifierChar(const aChar: Char): Boolean;
begin
  Result := (aChar = '_') or (aChar in ['A'..'Z', 'a'..'z', '0'..'9']);
end;

function IsPascalKeyword(const aToken: string): Boolean;
const
  cKeywords: array[0..18] of string = (
    'begin', 'class', 'const', 'constructor', 'destructor', 'do', 'else', 'end', 'except', 'finally',
    'for', 'function', 'implementation', 'interface', 'operator', 'procedure', 'record', 'then', 'try');
var
  lKeyword: string;
begin
  for lKeyword in cKeywords do
  begin
    if SameText(aToken, lKeyword) then
      Exit(True);
  end;
  Result := False;
end;

function TryExtractIdentifierAtColumn(const aLineText: string; aColNumber: Integer; out aToken: string): Boolean;
var
  lLeft: Integer;
  lRight: Integer;
  lIndex: Integer;
begin
  Result := False;
  aToken := '';
  if (aLineText = '') or (aColNumber <= 0) then
    Exit(False);
  if aColNumber > Length(aLineText) then
    Exit(False);

  lIndex := aColNumber;
  if not IsIdentifierChar(aLineText[lIndex]) then
  begin
    if (lIndex > 1) and IsIdentifierChar(aLineText[lIndex - 1]) then
      Dec(lIndex)
    else
      Exit(False);
  end;

  lLeft := lIndex;
  while (lLeft > 1) and IsIdentifierChar(aLineText[lLeft - 1]) do
    Dec(lLeft);

  lRight := lIndex;
  while (lRight < Length(aLineText)) and IsIdentifierChar(aLineText[lRight + 1]) do
    Inc(lRight);

  aToken := Copy(aLineText, lLeft, lRight - lLeft + 1);
  Result := (aToken <> '') and (not IsPascalKeyword(aToken));
end;

function TryExtractFirstIdentifierFromLine(const aLineText: string; out aToken: string): Boolean;
var
  lEnd: Integer;
  lIndex: Integer;
  lStart: Integer;
begin
  Result := False;
  aToken := '';
  if aLineText = '' then
    Exit(False);

  lIndex := 1;
  while lIndex <= Length(aLineText) do
  begin
    if IsIdentifierChar(aLineText[lIndex]) and (not (aLineText[lIndex] in ['0'..'9'])) then
    begin
      lStart := lIndex;
      Inc(lIndex);
      while (lIndex <= Length(aLineText)) and IsIdentifierChar(aLineText[lIndex]) do
        Inc(lIndex);
      lEnd := lIndex - 1;
      aToken := Copy(aLineText, lStart, lEnd - lStart + 1);
      if (aToken <> '') and (not IsPascalKeyword(aToken)) then
        Exit(True);
    end;
    Inc(lIndex);
  end;
end;

function TryExtractEnclosingSymbolFromLine(const aLineText: string; out aSymbol: string): Boolean;
var
  lMatch: TMatch;
begin
  aSymbol := '';
  if aLineText = '' then
    Exit(False);

  lMatch := TRegEx.Match(aLineText,
    '^\s*(?:class\s+)?(?:procedure|function|constructor|destructor)\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)',
    [roIgnoreCase]);
  if not lMatch.Success then
  begin
    lMatch := TRegEx.Match(aLineText, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*class\b', [roIgnoreCase]);
    if not lMatch.Success then
      Exit(False);
  end;

  aSymbol := lMatch.Groups[1].Value;
  Result := aSymbol <> '';
end;

function TryExtractQuotedIdentifier(const aFinding: string; out aIdentifier: string): Boolean;
var
  lMatch: TMatch;
begin
  aIdentifier := '';
  lMatch := TRegEx.Match(aFinding, '''([A-Za-z_][A-Za-z0-9_]*)''');
  if not lMatch.Success then
    Exit(False);
  aIdentifier := lMatch.Groups[1].Value;
  Result := aIdentifier <> '';
end;

function TryFindIdentifierInContext(const aContext: TSourceContextSnippet; const aIdentifier: string;
  out aCandidate: string): Boolean;
var
  lLineText: string;
  lPattern: string;
begin
  Result := False;
  aCandidate := '';
  if (aIdentifier = '') or (Length(aContext.fLines) = 0) then
    Exit(False);

  lPattern := '\b' + TRegEx.Escape(aIdentifier) + '\b';
  for lLineText in aContext.fLines do
  begin
    if TRegEx.IsMatch(lLineText, lPattern) then
    begin
      aCandidate := aIdentifier;
      Exit(True);
    end;
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

function TryResolveSourceContextCandidate(const aLookup: TProjectSourceLookup; const aFinding: string;
  aContextLines: Integer; out aContext: TSourceContextSnippet; out aToken: string; out aEnclosingSymbol: string;
  out aError: string): Boolean;
var
  lColNumber: Integer;
  lFileToken: string;
  lLineNumber: Integer;
  lLineText: string;
  lIndex: Integer;
begin
  Result := False;
  aContext := Default(TSourceContextSnippet);
  aToken := '';
  aEnclosingSymbol := '';
  aError := '';
  if not TryParseFindingLocationWithColumn(aFinding, lFileToken, lLineNumber, lColNumber) then
  begin
    aError := 'Could not parse compiler failure location: ' + aFinding;
    Exit(False);
  end;
  if not TryResolveSourceContext(aLookup, lFileToken, lLineNumber, aContextLines, aContext, aError) then
    Exit(False);

  lIndex := aContext.fTargetLine - aContext.fStartLine;
  if (lIndex < 0) or (lIndex > High(aContext.fLines)) then
  begin
    aError := Format('Could not derive enrichment candidate from %s(%d,%d).',
      [lFileToken, lLineNumber, lColNumber]);
    Exit(False);
  end;

  lLineText := aContext.fLines[lIndex];
  if (lColNumber > 0) and TryExtractIdentifierAtColumn(lLineText, lColNumber, aToken) then
    Exit(True);

  if TryExtractQuotedIdentifier(aFinding, aToken) and TryFindIdentifierInContext(aContext, aToken, aToken) then
    Exit(True);

  if TryExtractFirstIdentifierFromLine(lLineText, aToken) then
    Exit(True);

  if TryExtractIdentifierAtColumn(lLineText, 1, aToken) then
    Exit(True);

  while lIndex >= 0 do
  begin
    if TryExtractEnclosingSymbolFromLine(aContext.fLines[lIndex], aEnclosingSymbol) then
      Exit(True);
    Dec(lIndex);
  end;

  aError := Format('Could not derive enrichment candidate from %s(%d,%d).',
    [lFileToken, lLineNumber, lColNumber]);
  Exit(False);
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
