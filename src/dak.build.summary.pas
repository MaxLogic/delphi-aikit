unit Dak.Build.Summary;

interface

uses
  System.Generics.Collections, System.JSON, System.SysUtils,
  Dak.Build.Types, Dak.Types;

function ParseBuildLogs(const aOutLogPath, aErrLogPath: string;
  const aOptions: TBuildSummaryOptions): TBuildSummary;
function BuildSummaryAsJson(const aProjectPath: string; const aOptions: TAppOptions;
  const aSummary: TBuildSummary; const aTarget: string; aTimeMs: Int64): string;

implementation

uses
  System.Classes, System.IOUtils, System.RegularExpressions, System.StrUtils,
  Dak.SourceContext;

function SplitList(const aValue: string): TArray<string>;
var
  lItem: string;
  lItems: TList<string>;
  lPart: string;
begin
  lItems := TList<string>.Create;
  try
    for lPart in aValue.Split([';']) do
    begin
      lItem := Trim(lPart);
      if lItem <> '' then
        lItems.Add(lItem);
    end;
    Result := lItems.ToArray;
  finally
    lItems.Free;
  end;
end;

function MatchesMaskCI(const aText, aMask: string): Boolean;
var
  i: Integer;
  j: Integer;
  lMark: Integer;
  lMask: string;
  lStar: Integer;
  lText: string;
begin
  lText := UpperCase(aText);
  lMask := UpperCase(aMask);
  i := 1;
  j := 1;
  lStar := 0;
  lMark := 0;
  while i <= Length(lText) do
  begin
    if (j <= Length(lMask)) and ((lMask[j] = '?') or (lMask[j] = lText[i])) then
    begin
      Inc(i);
      Inc(j);
    end else if (j <= Length(lMask)) and (lMask[j] = '*') then
    begin
      lStar := j;
      lMark := i;
      Inc(j);
    end else if lStar <> 0 then
    begin
      j := lStar + 1;
      Inc(lMark);
      i := lMark;
    end else
      Exit(False);
  end;

  while (j <= Length(lMask)) and (lMask[j] = '*') do
    Inc(j);

  Result := j > Length(lMask);
end;

function NormalizeDir(const aDir: string): string;
var
  lRoot: string;
begin
  if aDir = '' then
    Exit('');

  Result := TPath.GetFullPath(aDir);
  lRoot := TPath.GetPathRoot(Result);
  if (lRoot <> '') and SameText(Result, lRoot) then
    Exit(lRoot);

  Result := ExcludeTrailingPathDelimiter(Result);
end;

function FindRepoRoot(const aStartDir: string): string;
var
  lDir: string;
  lParent: string;
begin
  lDir := NormalizeDir(aStartDir);
  while lDir <> '' do
  begin
    if DirectoryExists(TPath.Combine(lDir, '.git')) or DirectoryExists(TPath.Combine(lDir, '.svn')) then
      Exit(lDir);
    lParent := NormalizeDir(ExtractFileDir(lDir));
    if (lParent = '') or SameText(lParent, lDir) then
      Break;
    lDir := lParent;
  end;
  Result := '';
end;

function DetermineProjectRoot(const aProjectPath: string): string;
var
  lProjectDir: string;
begin
  lProjectDir := NormalizeDir(ExtractFileDir(TPath.GetFullPath(aProjectPath)));
  Result := FindRepoRoot(lProjectDir);
  if Result = '' then
    Result := lProjectDir;
end;

function NormalizeBuildLine(const aLine, aProjectRoot: string): string;
var
  lRoot: string;
begin
  Result := aLine;
  lRoot := NormalizeDir(aProjectRoot);
  if lRoot = '' then
    Exit;

  if not lRoot.EndsWith('\') then
    lRoot := lRoot + '\';

  Result := TRegEx.Replace(Result, '(?i)' + TRegEx.Escape(lRoot), '');
  Result := TRegEx.Replace(Result, '(?i)\[' + TRegEx.Escape(lRoot), '[');
end;

function LineIsExcluded(const aLine, aExcludeMasks: string): Boolean;
var
  lFileName: string;
  lMatch: TMatch;
  lNormalizedMask: string;
  lRawMask: string;
begin
  Result := False;
  if Trim(aExcludeMasks) = '' then
    Exit(False);

  lMatch := TRegEx.Match(aLine, '^(?<f>.+?)\(\d+');
  if not lMatch.Success then
    Exit(False);

  lFileName := Trim(lMatch.Groups['f'].Value.Replace('/', '\', [rfReplaceAll]));
  lFileName := lFileName.TrimLeft(['.', '\']);
  for lRawMask in SplitList(aExcludeMasks) do
  begin
    lNormalizedMask := lRawMask.Replace('/', '\', [rfReplaceAll]).TrimLeft(['.', '\']);
    if MatchesMaskCI(lFileName, lNormalizedMask) then
      Exit(True);
  end;
end;

function BuildIgnoreSet(const aValue: string): THashSet<string>;
var
  lItem: string;
begin
  Result := THashSet<string>.Create;
  for lItem in SplitList(aValue) do
    Result.Add(UpperCase(lItem));
end;

procedure AddFinding(var aItems: TArray<string>; const aLine: string; const aLimit: Integer);
var
  lLength: Integer;
begin
  if (aLimit > 0) and (Length(aItems) >= aLimit) then
    Exit;

  lLength := Length(aItems);
  SetLength(aItems, lLength + 1);
  aItems[lLength] := aLine;
end;

procedure AddFindingPair(var aDisplayItems, aRawItems: TArray<string>; const aDisplayLine, aRawLine: string;
  const aLimit: Integer);
begin
  if (aLimit > 0) and (Length(aDisplayItems) >= aLimit) then
    Exit;
  AddFinding(aDisplayItems, aDisplayLine, 0);
  AddFinding(aRawItems, aRawLine, 0);
end;

procedure ParseLogFile(const aLogPath: string; const aOptions: TBuildSummaryOptions;
  const aIgnoreWarnings, aIgnoreHints: THashSet<string>; var aSummary: TBuildSummary);
var
  lCode: string;
  lLine: string;
  lLines: TStringList;
  lMatch: TMatch;
  lNormalizedLine: string;
begin
  if (aLogPath = '') or (not FileExists(aLogPath)) then
    Exit;

  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aLogPath);
    for lLine in lLines do
    begin
      lNormalizedLine := NormalizeBuildLine(lLine, aOptions.fProjectRoot);
      if LineIsExcluded(lNormalizedLine, aOptions.fExcludePathMasks) then
        Continue;

      if TRegEx.IsMatch(lNormalizedLine, ':\s+error\s+') or TRegEx.IsMatch(lNormalizedLine, ':\s+fatal\s+') then
      begin
        Inc(aSummary.fErrorCount);
        AddFindingPair(aSummary.fErrors, aSummary.fErrorsRaw, lNormalizedLine.Trim, lLine.Trim, aOptions.fMaxFindings);
        Continue;
      end;

      if TRegEx.IsMatch(lNormalizedLine, '(^|\s)(\[Fatal Error\]|\[Error\]|Fatal Error:|Error:)') then
      begin
        Inc(aSummary.fErrorCount);
        AddFindingPair(aSummary.fErrors, aSummary.fErrorsRaw, lNormalizedLine.Trim, lLine.Trim, aOptions.fMaxFindings);
        Continue;
      end;

      lMatch := TRegEx.Match(lNormalizedLine, ':\s+warning\s+(W\d+):');
      if lMatch.Success then
      begin
        lCode := UpperCase(lMatch.Groups[1].Value);
        if not aIgnoreWarnings.Contains(lCode) then
        begin
          Inc(aSummary.fWarningCount);
          if aOptions.fIncludeWarnings then
            AddFindingPair(aSummary.fWarnings, aSummary.fWarningsRaw, lNormalizedLine.Trim, lLine.Trim,
              aOptions.fMaxFindings);
        end;
        Continue;
      end;

      if TRegEx.IsMatch(lNormalizedLine, '(^|\s)(\[Warning\]|Warning:)') then
      begin
        Inc(aSummary.fWarningCount);
        if aOptions.fIncludeWarnings then
          AddFindingPair(aSummary.fWarnings, aSummary.fWarningsRaw, lNormalizedLine.Trim, lLine.Trim,
            aOptions.fMaxFindings);
        Continue;
      end;

      lMatch := TRegEx.Match(lNormalizedLine, ' hint warning\s+(H\d+):');
      if not lMatch.Success then
        lMatch := TRegEx.Match(lNormalizedLine, ':\s+hint\s+(H\d+):');
      if lMatch.Success then
      begin
        lCode := UpperCase(lMatch.Groups[1].Value);
        if not aIgnoreHints.Contains(lCode) then
        begin
          Inc(aSummary.fHintCount);
          if aOptions.fIncludeHints then
            AddFindingPair(aSummary.fHints, aSummary.fHintsRaw, lNormalizedLine.Trim, lLine.Trim,
              aOptions.fMaxFindings);
        end;
        Continue;
      end;

      if TRegEx.IsMatch(lNormalizedLine, '(^|\s)(\[Hint\]|Hint:)') then
      begin
        Inc(aSummary.fHintCount);
        if aOptions.fIncludeHints then
          AddFindingPair(aSummary.fHints, aSummary.fHintsRaw, lNormalizedLine.Trim, lLine.Trim,
            aOptions.fMaxFindings);
      end;
    end;
  finally
    lLines.Free;
  end;
end;

function ParseBuildLogs(const aOutLogPath, aErrLogPath: string;
  const aOptions: TBuildSummaryOptions): TBuildSummary;
var
  lIgnoreHints: THashSet<string>;
  lIgnoreWarnings: THashSet<string>;
begin
  Result := Default(TBuildSummary);
  lIgnoreWarnings := BuildIgnoreSet(aOptions.fIgnoreWarnings);
  lIgnoreHints := BuildIgnoreSet(aOptions.fIgnoreHints);
  try
    ParseLogFile(aErrLogPath, aOptions, lIgnoreWarnings, lIgnoreHints, Result);
    ParseLogFile(aOutLogPath, aOptions, lIgnoreWarnings, lIgnoreHints, Result);
  finally
    lIgnoreHints.Free;
    lIgnoreWarnings.Free;
  end;
end;

function PrefixSourceContext(const aLines: TArray<string>): string;
var
  lIndex: Integer;
  lParts: TArray<string>;
begin
  SetLength(lParts, Length(aLines));
  for lIndex := 0 to High(aLines) do
    lParts[lIndex] := '  ' + aLines[lIndex];
  Result := String.Join(sLineBreak, lParts);
end;

function AppendSourceContextToFinding(const aDisplayFinding, aLookupFinding: string;
  const aLookup: TProjectSourceLookup; aContextLines: Integer): string;
var
  lContext: TSourceContextSnippet;
  lError: string;
  lFileToken: string;
  lLineNumber: Integer;
begin
  Result := aDisplayFinding;
  if not TryParseFindingLocation(aLookupFinding, lFileToken, lLineNumber) then
    Exit(Result);
  if not TryResolveSourceContext(aLookup, lFileToken, lLineNumber, aContextLines, lContext, lError) then
    Exit(Result);
  Result := Result + sLineBreak + PrefixSourceContext(FormatSourceContextLines(lContext));
end;

procedure EnrichBuildFindingsWithSourceContext(var aItems: TArray<string>; const aLookupItems: TArray<string>;
  const aLookup: TProjectSourceLookup; aContextLines: Integer);
var
  i: Integer;
begin
  for i := 0 to High(aItems) do
    if i <= High(aLookupItems) then
      aItems[i] := AppendSourceContextToFinding(aItems[i], aLookupItems[i], aLookup, aContextLines);
end;

function BuildSummaryAsJson(const aProjectPath: string; const aOptions: TAppOptions;
  const aSummary: TBuildSummary; const aTarget: string; aTimeMs: Int64): string;
var
  lErrors: TJSONArray;
  lHints: TJSONArray;
  lIssues: TJSONObject;
  lLine: string;
  lRoot: TJSONObject;
  lWarnings: TJSONArray;
begin
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('status', aSummary.fStatus);
    lRoot.AddPair('project', TPath.GetFileName(aProjectPath));
    lRoot.AddPair('project_path', aProjectPath);
    lRoot.AddPair('config', aOptions.fConfig);
    lRoot.AddPair('platform', aOptions.fPlatform);
    lRoot.AddPair('target', aTarget);
    lRoot.AddPair('time_ms', TJSONNumber.Create(aTimeMs));
    lRoot.AddPair('exit_code', TJSONNumber.Create(aSummary.fExitCode));
    lRoot.AddPair('errors', TJSONNumber.Create(aSummary.fErrorCount));
    lRoot.AddPair('warnings', TJSONNumber.Create(aSummary.fWarningCount));
    lRoot.AddPair('hints', TJSONNumber.Create(aSummary.fHintCount));
    lRoot.AddPair('max_findings', TJSONNumber.Create(aOptions.fBuildMaxFindings));
    lRoot.AddPair('output', aSummary.fOutputPath);
    lRoot.AddPair('output_stale', TJSONBool.Create(aSummary.fOutputStale));
    lRoot.AddPair('output_message', aSummary.fOutputMessage);

    lIssues := TJSONObject.Create;
    lErrors := TJSONArray.Create;
    lWarnings := TJSONArray.Create;
    lHints := TJSONArray.Create;
    for lLine in aSummary.fErrors do
      lErrors.Add(lLine);
    for lLine in aSummary.fWarnings do
      lWarnings.Add(lLine);
    for lLine in aSummary.fHints do
      lHints.Add(lLine);
    lIssues.AddPair('errors', lErrors);
    lIssues.AddPair('warnings', lWarnings);
    lIssues.AddPair('hints', lHints);
    lRoot.AddPair('issues', lIssues);
    Result := lRoot.ToJSON;
  finally
    lRoot.Free;
  end;
end;

end.
