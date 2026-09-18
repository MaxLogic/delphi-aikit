unit Dak.Analysis.ReportBundle;

{$SCOPEDENUMS ON}

interface

uses
  System.Generics.Collections, System.JSON,
  Dak.Analysis.Ownership;

// Inputs and derived facts of one analysis output directory, matching postprocess.py.
// Every function returns caller-owned JSON; rows are the arrays loaded by Dak.Analysis.Findings.

// parse_dak_summary_md: keys path, timestamp, project|unit, fixinsight_total, fixinsight_top_codes,
// pal_totals, pal_version, pal_compiler_target, errors, analyzers.
function ParseAnalysisSummaryMarkdown(const aSummaryPath: string): TJSONObject;
// _validate_success_summary: raises EConvertError('Invalid analysis summary: ...').
procedure ValidateAnalysisSummary(aSummary: TJSONObject);
// _build_run_context with environment overrides and run.log parsing.
function BuildAnalysisRunContext(const aOutRoot: string; aSummary: TJSONObject): TJSONObject;
// _load_status_seed: existing schema 2/3 seed validated against the summary subject, or a default seed.
function LoadAnalysisStatusSeed(const aOutRoot: string; aSummary, aRunContext: TJSONObject;
  aRequired: Boolean): TJSONObject;
// _enrich_analyzer_versions
procedure EnrichAnalyzerVersions(aSeed, aRunContext: TJSONObject);
// _resolved_analysis_policy: gate_ownership, project_roots, third_party_roots, exclude_path_masks,
// gate_metrics, fixinsight_ignore, pal_ignore_rules, sha256, errors.
function ResolveAnalysisPolicy(aSeed: TJSONObject): TJSONObject;
// _record_is_actionable
function AnalysisRecordIsActionable(aRow: TJSONObject): Boolean;
// _ownership_counts (raises EConvertError on an invalid category) and its text form.
function AnalysisOwnershipCounts(const aRowSets: array of TJSONArray): TJSONObject; overload;
// The same over non-owning row selections, so callers count subsets without cloning rows.
function AnalysisOwnershipCounts(const aRowSets: array of TList<TJSONObject>): TJSONObject; overload;
function AnalysisOwnershipText(aCounts: TJSONObject): string;
// _actionable_counts with the summary consistency checks.
function AnalysisActionableCounts(aSummary: TJSONObject; aFixInsight, aPal: TJSONArray): TJSONObject;
// _report_projections: raw plus one entry per projection.
function AnalysisReportProjections(aSummary: TJSONObject; aFixInsight, aPal: TJSONArray): TJSONObject;
// _compatibility_snapshot: {sha256, context}.
function AnalysisCompatibilitySnapshot(aSeed: TJSONObject; const aContext: TAnalysisOwnershipContext): TJSONObject;
// platform.win32_ver: the Windows release name the reference records in the run context. The
// tables are ordered high to low and the first entry not above the running version wins, so a
// Windows 10 kernel with build 22000 or later is reported as 11, not as 10.
function AnalysisHostRelease(aMajor, aMinor, aBuild: Integer; aIsClient: Boolean): string;
// _active_triage_policy
function AnalysisActiveTriagePolicy: TJSONObject;
// datetime.now(timezone.utc).replace(microsecond=0).isoformat()
function AnalysisUtcNowIso: string;
function AnalysisTruthyEnvironment(const aName: string; aDefault: Boolean): Boolean;
// _int_env: an unset or blank name yields the default; a value that is not an integer is an
// error, never a silent fallback that would weaken a configured limit.
function AnalysisIntegerEnvironment(const aName: string; aDefault: Integer): Integer;
// The same without a default: aHasValue is False when the variable is unset or blank.
function AnalysisOptionalIntegerEnvironment(const aName: string; out aHasValue: Boolean): Integer;
function SplitSemicolonPatterns(const aRaw: string): TArray<string>;
// Nullable text member: '' for absent, null, or empty.
function JsonText(aObject: TJSONObject; const aName: string): string;
function JsonObjectMember(aObject: TJSONObject; const aName: string): TJSONObject;
function JsonArrayMember(aObject: TJSONObject; const aName: string): TJSONArray;
// Replaces or appends a member while keeping an existing member's position.
procedure JsonPut(aObject: TJSONObject; const aName: string; aValue: TJSONValue);
procedure JsonPutText(aObject: TJSONObject; const aName, aValue: string);
function JsonStringArray(const aValues: TArray<string>): TJSONArray;
function JsonCloneValue(aValue: TJSONValue): TJSONValue;
// Python == on decoded JSON: member order is irrelevant, numbers compare by value.
function AnalysisJsonEquivalent(aLeft, aRight: TJSONValue): Boolean;

implementation

uses
  System.Classes, System.Generics.Defaults, System.Hash, System.IOUtils, System.Math, System.RegularExpressions,
  System.StrUtils, System.SysUtils,
  Winapi.Windows,
  AutoFree,
  Dak.Analysis.JsonText, Dak.Analysis.NumericText, Dak.Analysis.Text, Dak.Analysis.Workspace;

const
  cOwnershipNames: array[0..3] of string = ('project', 'repository', 'third_party', 'unknown');

function JsonObjectMember(aObject: TJSONObject; const aName: string): TJSONObject;
var
  lValue: TJSONValue;
begin
  Result := nil;
  if aObject = nil then
    Exit;
  lValue := aObject.GetValue(aName);
  if lValue is TJSONObject then
    Result := TJSONObject(lValue);
end;

function JsonArrayMember(aObject: TJSONObject; const aName: string): TJSONArray;
var
  lValue: TJSONValue;
begin
  Result := nil;
  if aObject = nil then
    Exit;
  lValue := aObject.GetValue(aName);
  if lValue is TJSONArray then
    Result := TJSONArray(lValue);
end;

// JsonText of a value already found; nil and null are the empty text, as for a missing member.
function JsonValueText(aValue: TJSONValue): string;
begin
  Result := '';
  if (aValue = nil) or (aValue is TJSONNull) then
    Exit;
  if aValue is TJSONNumber then
    Exit(TNumericText.PythonText(aValue.Value));
  if aValue is TJSONBool then
  begin
    if TJSONBool(aValue).AsBoolean then
      Exit('True');
    Exit('False');
  end;
  Result := aValue.Value;
end;

function JsonText(aObject: TJSONObject; const aName: string): string;
begin
  Result := '';
  if aObject <> nil then
    Result := JsonValueText(aObject.GetValue(aName));
end;

procedure JsonPut(aObject: TJSONObject; const aName: string; aValue: TJSONValue);
var
  lPair: TJSONPair;
begin
  lPair := aObject.Get(aName);
  if lPair <> nil then
    lPair.JsonValue := aValue
  else
    aObject.AddPair(aName, aValue);
end;

procedure JsonPutText(aObject: TJSONObject; const aName, aValue: string);
begin
  JsonPut(aObject, aName, TJSONString.Create(aValue));
end;

function JsonStringArray(const aValues: TArray<string>): TJSONArray;
var
  lValue: string;
begin
  Result := TJSONArray.Create;
  for lValue in aValues do
    Result.Add(lValue);
end;

function JsonCloneValue(aValue: TJSONValue): TJSONValue;
var
  c: Char;
  lArray: TJSONArray;
  lItem: TJSONValue;
  lNumber: TJSONNumber;
  lObject: TJSONObject;
  lPair: TJSONPair;
begin
  if aValue is TJSONObject then
  begin
    lObject := TJSONObject.Create;
    try
      for lPair in TJSONObject(aValue) do
        lObject.AddPair(TJSONPair.Create(lPair.JsonString.Value, JsonCloneValue(lPair.JsonValue)));
      Result := lObject;
    except
      lObject.Free;
      raise;
    end;
  end else if aValue is TJSONArray then
  begin
    lArray := TJSONArray.Create;
    try
      for lItem in TJSONArray(aValue) do
        lArray.AddElement(JsonCloneValue(lItem));
      Result := lArray;
    except
      lArray.Free;
      raise;
    end;
  end else if aValue is TJSONNumber then
  begin
    // Clone converts through Double; keep the decimal token.
    lNumber := TJSONNumber.Create('');
    for c in aValue.Value do
      lNumber.AddChar(c);
    Result := lNumber;
  end else
    Result := aValue.Clone as TJSONValue;
end;

function AnalysisJsonEquivalent(aLeft, aRight: TJSONValue): Boolean;
var
  i: Integer;
  lLeft, lRight: Double;
  lOther: TJSONValue;
  lPair: TJSONPair;
begin
  if (aLeft = nil) or (aRight = nil) then
    Exit((aLeft = nil) and (aRight = nil));
  if aLeft is TJSONObject then
  begin
    if not (aRight is TJSONObject) or (TJSONObject(aLeft).Count <> TJSONObject(aRight).Count) then
      Exit(False);
    for lPair in TJSONObject(aLeft) do
    begin
      lOther := TJSONObject(aRight).GetValue(lPair.JsonString.Value);
      if (lOther = nil) or not AnalysisJsonEquivalent(lPair.JsonValue, lOther) then
        Exit(False);
    end;
    Exit(True);
  end;
  if aLeft is TJSONArray then
  begin
    if not (aRight is TJSONArray) or (TJSONArray(aLeft).Count <> TJSONArray(aRight).Count) then
      Exit(False);
    for i := 0 to TJSONArray(aLeft).Count - 1 do
      if not AnalysisJsonEquivalent(TJSONArray(aLeft).Items[i], TJSONArray(aRight).Items[i]) then
        Exit(False);
    Exit(True);
  end;
  if aLeft is TJSONNumber then
  begin
    if not (aRight is TJSONNumber) then
      Exit(False);
    if aLeft.Value = aRight.Value then
      Exit(True);
    try
      lLeft := TNumericText.ParseDouble(aLeft.Value);
      lRight := TNumericText.ParseDouble(aRight.Value);
    except
      on EConvertError do
        Exit(False);
    end;
    Exit(lLeft = lRight);
  end;
  if aLeft is TJSONString then
    Exit((aRight is TJSONString) and not (aRight is TJSONNumber) and (aLeft.Value = aRight.Value));
  if aLeft is TJSONBool then
    Exit((aRight is TJSONBool) and (TJSONBool(aLeft).AsBoolean = TJSONBool(aRight).AsBoolean));
  Result := (aLeft is TJSONNull) and (aRight is TJSONNull);
end;

function AnalysisTruthyEnvironment(const aName: string; aDefault: Boolean): Boolean;
var
  lValue: string;
begin
  lValue := Trim(GetEnvironmentVariable(aName)).ToLowerInvariant;
  if lValue = '' then
    Exit(aDefault);
  Result := MatchText(lValue, ['1', 'true', 'yes', 'on']);
end;

function AnalysisOptionalIntegerEnvironment(const aName: string; out aHasValue: Boolean): Integer;
var
  lValue: string;
begin
  Result := 0;
  lValue := Trim(GetEnvironmentVariable(aName));
  aHasValue := lValue <> '';
  if not aHasValue then
    Exit;
  if not TryStrToInt(lValue, Result) then
    raise EConvertError.CreateFmt('%s must be an integer, got: %s', [aName, QuotedStr(lValue)]);
end;

function AnalysisIntegerEnvironment(const aName: string; aDefault: Integer): Integer;
var
  lHasValue: Boolean;
begin
  Result := AnalysisOptionalIntegerEnvironment(aName, lHasValue);
  if not lHasValue then
    Result := aDefault;
end;

function SplitSemicolonPatterns(const aRaw: string): TArray<string>;
var
  lList: TList<string>;
  lPart: string;
begin
  lList := TList<string>.Create;
  try
    for lPart in aRaw.Split([';']) do
      if Trim(lPart) <> '' then
        lList.Add(Trim(lPart));
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function AnalysisUtcNowIso: string;
var
  lNow: TSystemTime;
begin
  GetSystemTime(lNow);
  Result := Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d+00:00',
    [lNow.wYear, lNow.wMonth, lNow.wDay, lNow.wHour, lNow.wMinute, lNow.wSecond]);
end;

function FirstGroup(const aText, aPattern: string; aOptions: TRegExOptions = [roMultiLine]): string;
var
  lMatch: TMatch;
begin
  lMatch := TRegEx.Match(aText, aPattern, aOptions);
  if lMatch.Success then
    Result := lMatch.Groups[1].Value
  else
    Result := '';
end;

function SectionBody(const aText, aHeading: string): string;
var
  lMatch: TMatch;
begin
  // ^## Heading\s*$\s*(.*?)(?=^##\s|\Z)
  lMatch := TRegEx.Match(aText, '^## ' + TRegEx.Escape(aHeading) + '\s*$\s*(.*?)(?=^##\s|\z)',
    [roMultiLine, roSingleLine]);
  if lMatch.Success then
    Result := lMatch.Groups[1].Value
  else
    Result := #0; // absent marker
end;

function ParseAnalysisSummaryMarkdown(const aSummaryPath: string): TJSONObject;
var
  lAnalyzers: TJSONArray;
  lBody: string;
  lErrors: TJSONArray;
  lMatch: TMatch;
  lText: string;
  lTop: TJSONObject;
  lUnitSummary, lPalSkipped: Boolean;
  lValue: string;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('path', aSummaryPath);
    if not TFile.Exists(aSummaryPath) then
      Exit;
    lText := ReadAnalysisText(aSummaryPath);
    lValue := FirstGroup(lText, '^- Timestamp:\s*([0-9TZ:.-]+)\s*$');
    if lValue <> '' then
      Result.AddPair('timestamp', lValue);
    lValue := FirstGroup(lText, '^- Project:\s*`([^`]+)`\s*$');
    if lValue <> '' then
      Result.AddPair('project', lValue);
    lValue := FirstGroup(lText, '^- Unit:\s*`([^`]+)`\s*$');
    if lValue <> '' then
      Result.AddPair('unit', lValue);
    lValue := FirstGroup(lText, '^- Findings \(by code\):\s*(\d+)\s*$');
    if lValue <> '' then
      Result.AddPair('fixinsight_total', TJSONNumber.Create(StrToInt(lValue)));
    lTop := TJSONObject.Create;
    for lMatch in TRegEx.Matches(lText, '^\s*-\s*([A-Z]\d{3}):\s*(\d+)\s*$', [roMultiLine]) do
      JsonPut(lTop, lMatch.Groups[1].Value, TJSONNumber.Create(StrToInt(lMatch.Groups[2].Value)));
    if lTop.Count > 0 then
      Result.AddPair('fixinsight_top_codes', lTop)
    else
      lTop.Free;
    lMatch := TRegEx.Match(lText,
      '^- Totals:\s*warnings=(\d+),\s*strong_warnings=(\d+),\s*optimizations=(\d+),\s*total=(\d+)\s*$', [roMultiLine]);
    if lMatch.Success then
      Result.AddPair('pal_totals', TJSONObject.Create
        .AddPair('warnings', TJSONNumber.Create(StrToInt(lMatch.Groups[1].Value)))
        .AddPair('strong_warnings', TJSONNumber.Create(StrToInt(lMatch.Groups[2].Value)))
        .AddPair('optimizations', TJSONNumber.Create(StrToInt(lMatch.Groups[3].Value)))
        .AddPair('total', TJSONNumber.Create(StrToInt(lMatch.Groups[4].Value))));
    lValue := FirstGroup(lText, '^- (?:PAL )?Version:\s*([0-9.]+)\s*$', [roMultiLine, roIgnoreCase]);
    if lValue <> '' then
      Result.AddPair('pal_version', lValue);
    lValue := FirstGroup(lText, '^- Compiler target:\s*(.+)\s*$');
    if lValue <> '' then
      Result.AddPair('pal_compiler_target', Trim(lValue));
    lBody := SectionBody(lText, 'Errors');
    if lBody <> #0 then
    begin
      lErrors := TJSONArray.Create;
      for lMatch in TRegEx.Matches(lBody, '^\s*-\s+(.+?)\s*$', [roMultiLine]) do
        lErrors.Add(Trim(lMatch.Groups[1].Value));
      if lErrors.Count > 0 then
        Result.AddPair('errors', lErrors)
      else
        lErrors.Free;
    end;
    lAnalyzers := TJSONArray.Create;
    lBody := SectionBody(lText, 'FixInsight');
    if (Result.GetValue('fixinsight_total') <> nil) or ((lBody <> #0) and
      TRegEx.IsMatch(lBody, '^- (?:Findings \(by code\):\s*\(TXT not generated\)|Skipped\.)\s*$', [roMultiLine])) then
      lAnalyzers.Add('fixinsight');
    lBody := SectionBody(lText, 'Pascal Analyzer');
    lUnitSummary := TRegEx.IsMatch(lText, '^# Pascal Analyzer unit summary:', [roMultiLine]);
    if lUnitSummary then
      lPalSkipped := TRegEx.IsMatch(lText, '^- Skipped\.\s*$', [roMultiLine])
    else
      lPalSkipped := (lBody <> #0) and TRegEx.IsMatch(lBody, '^- Skipped\.\s*$', [roMultiLine]);
    if (Result.GetValue('pal_totals') <> nil) or lPalSkipped then
      lAnalyzers.Add('pascal_analyzer');
    if lAnalyzers.Count > 0 then
      Result.AddPair('analyzers', lAnalyzers)
    else
      lAnalyzers.Free;
  except
    Result.Free;
    raise;
  end;
end;

procedure ValidateAnalysisSummary(aSummary: TJSONObject);
var
  lAnalyzers: TJSONArray;
  lItem: TJSONValue;
  lMissing, lProblems: TList<string>;
  lName: string;
  lSubjects: Integer;
  lFound: Boolean;
begin
  lProblems := TList<string>.Create;
  lMissing := TList<string>.Create;
  try
    if JsonText(aSummary, 'timestamp') = '' then
      lProblems.Add('timestamp is missing');
    lSubjects := 0;
    if JsonText(aSummary, 'project') <> '' then
      Inc(lSubjects);
    if JsonText(aSummary, 'unit') <> '' then
      Inc(lSubjects);
    if lSubjects <> 1 then
      lProblems.Add('exactly one project or unit subject is required');
    lAnalyzers := JsonArrayMember(aSummary, 'analyzers');
    for lName in ['fixinsight', 'pascal_analyzer'] do
    begin
      if (lName = 'fixinsight') and (JsonText(aSummary, 'project') = '') then
        Continue;
      lFound := False;
      if lAnalyzers <> nil then
        for lItem in lAnalyzers do
          if lItem.Value = lName then
            lFound := True;
      if not lFound then
        lMissing.Add(lName);
    end;
    if lMissing.Count > 0 then
      lProblems.Add('analyzer status is missing for ' + String.Join(', ', lMissing.ToArray));
    if lProblems.Count > 0 then
      raise EConvertError.Create('Invalid analysis summary: ' + String.Join('; ', lProblems.ToArray));
  finally
    lMissing.Free;
    lProblems.Free;
  end;
end;

function LastMatchingLine(const aText, aPrefix, aContains: string): string;
var
  lLine: string;
begin
  Result := '';
  for lLine in aText.Split([#10]) do
    if lLine.StartsWith(aPrefix) and lLine.ToLowerInvariant.Contains(aContains.ToLowerInvariant) then
      Result := lLine.TrimRight([#13]);
end;

function ParseRunLogContext(const aRunLogPath: string): TJSONObject;
var
  lCd, lLine, lText: string;
  lMatch: TMatch;
  lMatches: TMatchCollection;
begin
  Result := TJSONObject.Create;
  if not TFile.Exists(aRunLogPath) then
    Exit;
  lText := ReadAnalysisText(aRunLogPath);
  lLine := '';
  for lMatch in TRegEx.Matches(lText, '^CWD:\s*(.+?)\s*$', [roMultiLine]) do
    lLine := Trim(lMatch.Groups[1].Value);
  if lLine <> '' then
    Result.AddPair('analysis_cwd', lLine);
  lLine := LastMatchingLine(lText, 'CMD:', 'fixinsightcl.');
  if lLine <> '' then
  begin
    lMatch := TRegEx.Match(lLine, '^CMD:\s*"([^"]*FixInsightCL\.(?:exe|cmd))"', [roIgnoreCase]);
    if lMatch.Success then
      Result.AddPair('fixinsight_exe', lMatch.Groups[1].Value);
  end;
  lLine := LastMatchingLine(lText, 'CMD:', 'palcmd.exe');
  if lLine <> '' then
  begin
    lMatch := TRegEx.Match(lLine, '^CMD:\s*"([^"]*palcmd\.exe)"', [roIgnoreCase]);
    if lMatch.Success then
      Result.AddPair('pal_exe', lMatch.Groups[1].Value);
    lMatch := TRegEx.Match(lLine, '/BUILD=(\S+)', [roIgnoreCase]);
    if lMatch.Success then
      Result.AddPair('config', lMatch.Groups[1].Value);
    lMatch := TRegEx.Match(lLine, '/CD(\S+)', [roIgnoreCase]);
    if lMatch.Success then
    begin
      lCd := Trim(lMatch.Groups[1].Value);
      Result.AddPair('pal_compiler_switch', 'CD' + lCd);
      if lCd.ToUpperInvariant.Contains('W32') then
        Result.AddPair('platform', 'Win32')
      else if lCd.ToUpperInvariant.Contains('W64') then
        Result.AddPair('platform', 'Win64');
    end;
  end;
  lMatches := TRegEx.Matches(lText, 'Embarcadero[\\/]+Studio[\\/]+(\d+\.\d+)', [roIgnoreCase]);
  if lMatches.Count > 0 then
    Result.AddPair('delphi', lMatches[lMatches.Count - 1].Groups[1].Value);
end;

procedure ParsePalCompilerTarget(const aTarget: string; out aLabel, aPlatform: string);
var
  lMatch: TMatch;
  lText: string;
begin
  aLabel := '';
  aPlatform := '';
  lText := Trim(aTarget);
  if lText = '' then
    Exit;
  lMatch := TRegEx.Match(lText, '^(.+?)\s*\(([^)]+)\)\s*$');
  if not lMatch.Success then
  begin
    aLabel := lText;
    Exit;
  end;
  aLabel := Trim(lMatch.Groups[1].Value);
  aPlatform := Trim(lMatch.Groups[2].Value);
  if SameText(aPlatform, 'win32') then
    aPlatform := 'Win32'
  else if SameText(aPlatform, 'win64') then
    aPlatform := 'Win64';
end;

// _query_fixinsight_version: "FixInsightCL [Pro] version X" from the tool's own --version output.
function QueryFixInsightVersion(const aExecutable, aWorkDir: string): string;
var
  lMatch: TMatch;
  lOutput: string;
begin
  Result := '';
  if not TryCaptureToolOutput(aExecutable, '--version', aWorkDir, 10, lOutput) then
    Exit;
  lMatch := TRegEx.Match(lOutput, 'FixInsightCL(?:\s+Pro)?\s+version\s+([^\s]+)', [roIgnoreCase]);
  if lMatch.Success then
    Result := lMatch.Groups[1].Value;
end;

type
  // One row of platform.win32_ver's release tables: the lowest version that still carries the name.
  TAnalysisReleaseEntry = record
    fMajor: Integer;
    fMinor: Integer;
    fBuild: Integer;
    fName: string;
  end;

const
  cClientReleases: array[0..10] of TAnalysisReleaseEntry = (
    (fMajor: 10; fMinor: 1; fBuild: 0; fName: 'post11'),
    (fMajor: 10; fMinor: 0; fBuild: 22000; fName: '11'),
    (fMajor: 6; fMinor: 4; fBuild: 0; fName: '10'),
    (fMajor: 6; fMinor: 3; fBuild: 0; fName: '8.1'),
    (fMajor: 6; fMinor: 2; fBuild: 0; fName: '8'),
    (fMajor: 6; fMinor: 1; fBuild: 0; fName: '7'),
    (fMajor: 6; fMinor: 0; fBuild: 0; fName: 'Vista'),
    (fMajor: 5; fMinor: 2; fBuild: 3790; fName: 'XP64'),
    (fMajor: 5; fMinor: 2; fBuild: 0; fName: 'XPMedia'),
    (fMajor: 5; fMinor: 1; fBuild: 0; fName: 'XP'),
    (fMajor: 5; fMinor: 0; fBuild: 0; fName: '2000'));
  cServerReleases: array[0..10] of TAnalysisReleaseEntry = (
    (fMajor: 10; fMinor: 1; fBuild: 0; fName: 'post2025Server'),
    (fMajor: 10; fMinor: 0; fBuild: 26100; fName: '2025Server'),
    (fMajor: 10; fMinor: 0; fBuild: 20348; fName: '2022Server'),
    (fMajor: 10; fMinor: 0; fBuild: 17763; fName: '2019Server'),
    (fMajor: 6; fMinor: 4; fBuild: 0; fName: '2016Server'),
    (fMajor: 6; fMinor: 3; fBuild: 0; fName: '2012ServerR2'),
    (fMajor: 6; fMinor: 2; fBuild: 0; fName: '2012Server'),
    (fMajor: 6; fMinor: 1; fBuild: 0; fName: '2008ServerR2'),
    (fMajor: 6; fMinor: 0; fBuild: 0; fName: '2008Server'),
    (fMajor: 5; fMinor: 2; fBuild: 0; fName: '2003Server'),
    (fMajor: 5; fMinor: 0; fBuild: 0; fName: '2000Server'));

function AnalysisHostRelease(aMajor, aMinor, aBuild: Integer; aIsClient: Boolean): string;

  function EntryAtMost(const aEntry: TAnalysisReleaseEntry): Boolean;
  begin
    if aEntry.fMajor <> aMajor then
      Exit(aEntry.fMajor < aMajor);
    if aEntry.fMinor <> aMinor then
      Exit(aEntry.fMinor < aMinor);
    Result := aEntry.fBuild <= aBuild;
  end;

var
  lEntry: TAnalysisReleaseEntry;
begin
  // The tables run from newest to oldest, so the first row the running version reaches wins.
  // Nothing matching leaves the release empty, exactly as the reference's default does.
  Result := '';
  if aIsClient then
  begin
    for lEntry in cClientReleases do
      if EntryAtMost(lEntry) then
        Exit(lEntry.fName);
  end else
  begin
    for lEntry in cServerReleases do
      if EntryAtMost(lEntry) then
        Exit(lEntry.fName);
  end;
end;

// RtlGetVersion reports the real build even when a process manifest would make GetVersionEx answer
// for an older Windows, and it carries the product type the reference reads from WMI.
function CurrentHostRelease: string;
type
  TOsVersionInfoExW = record
    dwOSVersionInfoSize: ULONG;
    dwMajorVersion: ULONG;
    dwMinorVersion: ULONG;
    dwBuildNumber: ULONG;
    dwPlatformId: ULONG;
    szCSDVersion: array[0..127] of WideChar;
    wServicePackMajor: USHORT;
    wServicePackMinor: USHORT;
    wSuiteMask: USHORT;
    wProductType: Byte;
    wReserved: Byte;
  end;
  TRtlGetVersion = function(var aInfo: TOsVersionInfoExW): LongInt; stdcall;
var
  lInfo: TOsVersionInfoExW;
  lRtlGetVersion: TRtlGetVersion;
begin
  lRtlGetVersion := TRtlGetVersion(GetProcAddress(GetModuleHandle('ntdll.dll'), 'RtlGetVersion'));
  if Assigned(lRtlGetVersion) then
  begin
    FillChar(lInfo, SizeOf(lInfo), 0);
    lInfo.dwOSVersionInfoSize := SizeOf(lInfo);
    if lRtlGetVersion(lInfo) = 0 then
      Exit(AnalysisHostRelease(lInfo.dwMajorVersion, lInfo.dwMinorVersion, lInfo.dwBuildNumber,
        lInfo.wProductType = VER_NT_WORKSTATION));
  end;
  Result := AnalysisHostRelease(TOSVersion.Major, TOSVersion.Minor, TOSVersion.Build, True);
end;

function BuildAnalysisRunContext(const aOutRoot: string; aSummary: TJSONObject): TJSONObject;
const
  cKeys: array[0..2] of string = ('platform', 'config', 'delphi');
  cEnvironment: array[0..2] of string = ('DAK_PLATFORM', 'DAK_CONFIG', 'DAK_DELPHI');
var
  g: TGarbos;
  i: Integer;
  lHost, lRunLog, lTools: TJSONObject;
  lLabel, lPlatform, lTarget, lValue: string;
begin
  Result := TJSONObject.Create;
  try
    for i := 0 to High(cKeys) do
    begin
      lValue := Trim(GetEnvironmentVariable(cEnvironment[i]));
      if lValue <> '' then
        Result.AddPair(cKeys[i], lValue);
    end;
    GC(lRunLog, ParseRunLogContext(TPath.Combine(aOutRoot, 'run.log')), g);
    for i := 0 to High(cKeys) do
      if (JsonText(Result, cKeys[i]) = '') and (JsonText(lRunLog, cKeys[i]) <> '') then
        JsonPutText(Result, cKeys[i], JsonText(lRunLog, cKeys[i]));
    lTarget := Trim(JsonText(aSummary, 'pal_compiler_target'));
    if lTarget <> '' then
    begin
      ParsePalCompilerTarget(lTarget, lLabel, lPlatform);
      if (JsonText(Result, 'platform') = '') and (lPlatform <> '') then
        JsonPutText(Result, 'platform', lPlatform);
      if (JsonText(Result, 'delphi') = '') and (lLabel <> '') then
        JsonPutText(Result, 'delphi', lLabel);
    end;
    for i := 0 to High(cKeys) do
      if JsonText(Result, cKeys[i]) = '' then
        JsonPutText(Result, cKeys[i], 'unknown');
    lTools := TJSONObject.Create;
    if JsonText(lRunLog, 'fixinsight_exe') <> '' then
    begin
      lTools.AddPair('fixinsight_exe', JsonText(lRunLog, 'fixinsight_exe'));
      lValue := QueryFixInsightVersion(JsonText(lRunLog, 'fixinsight_exe'), aOutRoot);
      if lValue <> '' then
        lTools.AddPair('fixinsight_version', lValue);
    end;
    if JsonText(lRunLog, 'pal_exe') <> '' then
      lTools.AddPair('pal_exe', JsonText(lRunLog, 'pal_exe'));
    if JsonText(lRunLog, 'pal_compiler_switch') <> '' then
      lTools.AddPair('pal_compiler_switch', JsonText(lRunLog, 'pal_compiler_switch'));
    if JsonText(aSummary, 'pal_version') <> '' then
      lTools.AddPair('pal_version', JsonText(aSummary, 'pal_version'));
    if lTarget <> '' then
      lTools.AddPair('pal_compiler_target', lTarget);
    if lTools.Count > 0 then
      Result.AddPair('tools', lTools)
    else
      lTools.Free;
    lHost := TJSONObject.Create
      .AddPair('os', 'Windows')
      .AddPair('release', CurrentHostRelease)
      .AddPair('python', TJSONNull.Create)
      .AddPair('wsl', TJSONBool.Create(False));
    if JsonText(lRunLog, 'analysis_cwd') <> '' then
      lHost.AddPair('analysis_cwd', JsonText(lRunLog, 'analysis_cwd'));
    Result.AddPair('host', lHost);
  except
    Result.Free;
    raise;
  end;
end;

function NormalizeSubject(const aValue: string): string;
begin
  Result := aValue.Replace('\', '/').TrimRight(['/']).ToLowerInvariant;
end;

function LoadAnalysisStatusSeed(const aOutRoot: string; aSummary, aRunContext: TJSONObject;
  aRequired: Boolean): TJSONObject;
var
  lActual, lExpected, lSeedPath, lSubjectKind: string;
  lFixInsightRequested, lPalRequested: Boolean;
  lSchema: Integer;
  lSeed: TJSONValue;
  lSubject: TJSONObject;
begin
  lSeedPath := TPath.Combine(aOutRoot, 'summary.json');
  lExpected := JsonText(aSummary, 'project');
  if lExpected = '' then
    lExpected := JsonText(aSummary, 'unit');
  if TFile.Exists(lSeedPath) then
  begin
    lSeed := TJSONObject.ParseJSONValue(ReadAnalysisText(lSeedPath), False, False);
    try
      lSchema := 0;
      if (lSeed is TJSONObject) and (TJSONObject(lSeed).GetValue('schema_version') is TJSONNumber) then
        lSchema := StrToIntDef(TJSONObject(lSeed).GetValue('schema_version').Value, 0);
      if not ((lSeed is TJSONObject) and ((lSchema = 2) or (lSchema = 3))) then
        raise EConvertError.CreateFmt('Invalid analysis status seed: %s', [lSeedPath]);
      lSubject := JsonObjectMember(TJSONObject(lSeed), 'subject');
      lActual := JsonText(lSubject, 'path');
      if NormalizeSubject(lActual) <> NormalizeSubject(lExpected) then
        raise EConvertError.CreateFmt('Analysis seed subject does not match summary: seed=''%s'', summary=''%s''',
          [lActual, lExpected]);
      Result := JsonCloneValue(lSeed) as TJSONObject;
    finally
      lSeed.Free;
    end;
    Exit;
  end;
  if aRequired then
    raise EConvertError.CreateFmt('Required schema-2 analysis seed is missing: %s', [lSeedPath]);
  lFixInsightRequested := aSummary.GetValue('fixinsight_total') <> nil;
  lPalRequested := aSummary.GetValue('pal_totals') <> nil;
  if JsonText(aSummary, 'project') <> '' then
    lSubjectKind := 'project'
  else
    lSubjectKind := 'unit';
  Result := TJSONObject.Create
    .AddPair('schema_version', TJSONNumber.Create(2))
    .AddPair('status', TJSONObject.Create
      .AddPair('infrastructure', 'complete')
      .AddPair('policy', 'not_evaluated'))
    .AddPair('subject', TJSONObject.Create
      .AddPair('kind', lSubjectKind)
      .AddPair('path', lExpected))
    .AddPair('compiler', TJSONObject.Create
      .AddPair('platform', JsonText(aRunContext, 'platform'))
      .AddPair('config', JsonText(aRunContext, 'config'))
      .AddPair('delphi', JsonText(aRunContext, 'delphi')))
    .AddPair('analyzers', TJSONObject.Create
      .AddPair('fixinsight', TJSONObject.Create
        .AddPair('requested', TJSONBool.Create(lFixInsightRequested))
        .AddPair('status', IfThen(lFixInsightRequested, 'complete', 'not_requested'))
        .AddPair('count_quality', 'complete'))
      .AddPair('pascal_analyzer', TJSONObject.Create
        .AddPair('requested', TJSONBool.Create(lPalRequested))
        .AddPair('status', IfThen(lPalRequested, 'complete', 'not_requested'))
        .AddPair('count_quality', 'complete')));
  if aSummary.GetValue('errors') is TJSONArray then
    Result.AddPair('errors', JsonCloneValue(aSummary.GetValue('errors')))
  else
    Result.AddPair('errors', TJSONArray.Create);
end;

procedure EnrichAnalyzerVersions(aSeed, aRunContext: TJSONObject);
var
  lAnalyzer, lAnalyzers, lTools: TJSONObject;
  lName, lVersion: string;
  i: Integer;
const
  cNames: array[0..1] of string = ('fixinsight', 'pascal_analyzer');
  cToolKeys: array[0..1] of string = ('fixinsight_version', 'pal_version');
begin
  lAnalyzers := JsonObjectMember(aSeed, 'analyzers');
  if lAnalyzers = nil then
  begin
    lAnalyzers := TJSONObject.Create;
    aSeed.AddPair('analyzers', lAnalyzers);
  end;
  lTools := JsonObjectMember(aRunContext, 'tools');
  for i := 0 to High(cNames) do
  begin
    lName := cNames[i];
    lAnalyzer := JsonObjectMember(lAnalyzers, lName);
    if lAnalyzer = nil then
    begin
      lAnalyzer := TJSONObject.Create;
      lAnalyzers.AddPair(lName, lAnalyzer);
    end;
    if not ((lAnalyzer.GetValue('requested') is TJSONBool) and TJSONBool(lAnalyzer.GetValue('requested')).AsBoolean) then
      Continue;
    lVersion := JsonText(lTools, cToolKeys[i]);
    if lVersion = '' then
      lVersion := JsonText(lAnalyzer, 'version');
    if lVersion = '' then
      lVersion := 'unavailable';
    JsonPutText(lAnalyzer, 'version', lVersion);
  end;
end;

function ResolveAnalysisPolicy(aSeed: TJSONObject): TJSONObject;
var
  lErrors: TJSONArray;
  lPolicy, lValues: TJSONObject;
  lSha: string;

  function Names(const aKey: string; const aDefault: array of string; aOptional: Boolean): TJSONArray;
  var
    lItem: TJSONValue;
    lRaw: TJSONValue;
    lValid: Boolean;
    lValue: string;
  begin
    Result := TJSONArray.Create;
    lRaw := nil;
    if lValues <> nil then
      lRaw := lValues.GetValue(aKey);
    if (lRaw = nil) or (lRaw is TJSONNull) then
    begin
      if not aOptional then
        lErrors.Add('Resolved AnalysisPolicy value is missing: ' + aKey);
      for lValue in aDefault do
        Result.Add(lValue);
      Exit;
    end;
    lValid := lRaw is TJSONArray;
    if lValid then
      for lItem in TJSONArray(lRaw) do
        if not ((lItem is TJSONString) and not (lItem is TJSONNumber) and (Trim(lItem.Value) <> '')) then
          lValid := False;
    if not lValid then
    begin
      lErrors.Add('Resolved AnalysisPolicy value is invalid: ' + aKey);
      for lValue in aDefault do
        Result.Add(lValue);
      Exit;
    end;
    for lItem in TJSONArray(lRaw) do
      Result.Add(Trim(lItem.Value));
  end;

  function ValidGate(aGate: TJSONArray): Boolean;
  var
    i, j: Integer;
  begin
    for i := 0 to aGate.Count - 1 do
    begin
      if not MatchStr(aGate.Items[i].Value, ['project', 'repository', 'third_party']) then
        Exit(False);
      for j := 0 to i - 1 do
        if aGate.Items[j].Value = aGate.Items[i].Value then
          Exit(False);
    end;
    Result := True;
  end;

var
  lGate: TJSONArray;
begin
  lErrors := TJSONArray.Create;
  Result := TJSONObject.Create;
  try
    lPolicy := JsonObjectMember(aSeed, 'policy');
    lValues := JsonObjectMember(lPolicy, 'values');
    lGate := Names('gate_ownership', ['project', 'repository'], False);
    if not ValidGate(lGate) then
    begin
      lErrors.Add('Resolved AnalysisPolicy gate_ownership is invalid');
      lGate.Free;
      lGate := JsonStringArray(['project', 'repository']);
    end;
    Result.AddPair('gate_ownership', lGate);
    Result.AddPair('project_roots', Names('project_roots', [], False));
    Result.AddPair('third_party_roots', Names('third_party_roots', [], False));
    Result.AddPair('exclude_path_masks', Names('exclude_path_masks', [], True));
    Result.AddPair('gate_metrics', Names('gate_metrics', [], True));
    Result.AddPair('fixinsight_ignore', Names('fixinsight_ignore', [], True));
    Result.AddPair('pal_ignore_rules', Names('pal_ignore_rules', [], True));
    lSha := Trim(JsonText(lPolicy, 'sha256')).ToLowerInvariant;
    if not TRegEx.IsMatch(lSha, '^[0-9a-f]{64}$') then
      lErrors.Add('Resolved AnalysisPolicy sha256 is missing or invalid');
    Result.AddPair('sha256', lSha);
    Result.AddPair('errors', lErrors);
    lErrors := nil;
  except
    lErrors.Free;
    Result.Free;
    raise;
  end;
end;

function AnalysisRecordIsActionable(aRow: TJSONObject): Boolean;
var
  lPolicy: TJSONValue;
  lProjection: TJSONValue;
begin
  lProjection := aRow.GetValue('report_projection');
  if (lProjection is TJSONString) and not (lProjection is TJSONNumber) then
    Exit(lProjection.Value = 'actionable');
  lPolicy := aRow.GetValue('report_policy');
  Result := not ((lPolicy is TJSONObject) and (JsonText(TJSONObject(lPolicy), 'disposition') = 'ignored'));
end;

function AnalysisOwnershipCounts(const aRowSets: array of TList<TJSONObject>): TJSONObject;
var
  lCounts: array[0..3] of Integer;
  lOwnership: TJSONValue;
  lRow: TJSONObject;
  lRows: TList<TJSONObject>;
  i: Integer;
  lIndex: Integer;
begin
  for i := 0 to High(lCounts) do
    lCounts[i] := 0;
  for lRows in aRowSets do
  begin
    if lRows = nil then
      Continue;
    for lRow in lRows do
    begin
      lOwnership := lRow.GetValue('ownership');
      lIndex := -1;
      if (lOwnership is TJSONString) and not (lOwnership is TJSONNumber) then
        lIndex := IndexStr(lOwnership.Value, cOwnershipNames);
      if lIndex < 0 then
        raise EConvertError.CreateFmt('invalid ownership category: %s', [QuotedStr(JsonText(lRow, 'ownership'))]);
      Inc(lCounts[lIndex]);
    end;
  end;
  Result := TJSONObject.Create;
  for i := 0 to High(cOwnershipNames) do
    Result.AddPair(cOwnershipNames[i], TJSONNumber.Create(lCounts[i]));
end;

function AllRows(aRows: TJSONArray): TList<TJSONObject>;
var
  lItem: TJSONValue;
begin
  Result := TList<TJSONObject>.Create;
  if aRows <> nil then
    for lItem in aRows do
      Result.Add(TJSONObject(lItem));
end;

function AnalysisOwnershipCounts(const aRowSets: array of TJSONArray): TJSONObject;
var
  g: TGarbos;
  i: Integer;
  lLists: TArray<TList<TJSONObject>>;
begin
  SetLength(lLists, Length(aRowSets));
  for i := 0 to High(aRowSets) do
    GC(lLists[i], AllRows(aRowSets[i]), g);
  Result := AnalysisOwnershipCounts(lLists);
end;

function AnalysisOwnershipText(aCounts: TJSONObject): string;
var
  i: Integer;
  lParts: TArray<string>;
begin
  SetLength(lParts, Length(cOwnershipNames));
  for i := 0 to High(cOwnershipNames) do
    lParts[i] := cOwnershipNames[i] + '=' + IntToStr(StrToIntDef(JsonText(aCounts, cOwnershipNames[i]), 0));
  Result := String.Join(', ', lParts);
end;

function CountOf(aCounts: TDictionary<string, Integer>; const aKey: string): Integer;
begin
  if not aCounts.TryGetValue(aKey, Result) then
    Result := 0;
end;

function SortedKeys(aCounts: TDictionary<string, Integer>): TArray<string>;
begin
  Result := aCounts.Keys.ToArray;
  TArray.Sort<string>(Result, TStringComparer.Ordinal);
end;

type
  // The fields the count projections read from one normalized row, taken in a single pass over the
  // row's pairs. The projections below walk every row several times; reading each field by name on
  // every walk dominated report verification and replay on large reports (T-344).
  TAnalysisRowFacts = record
    fKind: string;
    fSeverity: string;
    fOwnership: Integer;
    fOwnershipText: string;
    fRule: string;
    fProjection: string;
    fActionable: Boolean;
  end;
  TAnalysisRowFactsArray = TArray<TAnalysisRowFacts>;
  TAnalysisRowSelector = reference to function(const aFacts: TAnalysisRowFacts): Boolean;

// Exact, ordinal member-name match. IndexStr compares through the locale, which dominated this loop.
function FactField(const aName: string): Integer;
begin
  if aName = 'kind' then
    Result := 0
  else if aName = 'severity' then
    Result := 1
  else if aName = 'ownership' then
    Result := 2
  else if aName = 'normalized_rule' then
    Result := 3
  else if aName = 'report_projection' then
    Result := 4
  else
    Result := -1;
end;

function OwnershipIndex(const aValue: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(cOwnershipNames) do
    if aValue = cOwnershipNames[i] then
      Exit(i);
  Result := -1;
end;

function AnalysisRowFacts(aRows: TJSONArray): TAnalysisRowFactsArray;
var
  lFacts: TAnalysisRowFacts;
  lField: Integer;
  lItem: TJSONValue;
  lPair: TJSONPair;
  lProjection: TJSONValue;
  lRow: TJSONObject;
  lSeen: array[0..4] of Boolean;
  i: Integer;
  lCount: Integer;
begin
  Result := nil;
  if aRows = nil then
    Exit;
  SetLength(Result, aRows.Count);
  lCount := 0;
  for lItem in aRows do
  begin
    lRow := TJSONObject(lItem);
    lFacts := Default(TAnalysisRowFacts);
    lFacts.fOwnership := -1;
    lProjection := nil;
    for i := 0 to High(lSeen) do
      lSeen[i] := False;
    for lPair in lRow do
    begin
      lField := FactField(lPair.JsonString.Value);
      // TJSONObject.GetValue answers the first member of a name; so does this pass.
      if (lField < 0) or lSeen[lField] then
        Continue;
      lSeen[lField] := True;
      case lField of
        0: lFacts.fKind := Trim(JsonValueText(lPair.JsonValue)).ToUpperInvariant;
        1: lFacts.fSeverity := Trim(JsonValueText(lPair.JsonValue)).ToLowerInvariant;
        2:
          begin
            lFacts.fOwnershipText := JsonValueText(lPair.JsonValue);
            if (lPair.JsonValue is TJSONString) and not (lPair.JsonValue is TJSONNumber) then
              lFacts.fOwnership := OwnershipIndex(lPair.JsonValue.Value);
          end;
        3: lFacts.fRule := JsonValueText(lPair.JsonValue);
        4:
          begin
            lProjection := lPair.JsonValue;
            lFacts.fProjection := JsonValueText(lProjection);
          end;
      end;
    end;
    // AnalysisRecordIsActionable, answered from the projection already found when it is a string.
    if (lProjection is TJSONString) and not (lProjection is TJSONNumber) then
      lFacts.fActionable := lProjection.Value = 'actionable'
    else
      lFacts.fActionable := AnalysisRecordIsActionable(lRow);
    Result[lCount] := lFacts;
    Inc(lCount);
  end;
  SetLength(Result, lCount);
end;

function SelectAll: TAnalysisRowSelector;
begin
  Result :=
    function(const aFacts: TAnalysisRowFacts): Boolean
    begin
      Result := True;
    end;
end;

function SelectActionable: TAnalysisRowSelector;
begin
  Result :=
    function(const aFacts: TAnalysisRowFacts): Boolean
    begin
      Result := aFacts.fActionable;
    end;
end;

function SelectProjection(const aProjection: string): TAnalysisRowSelector;
begin
  Result :=
    function(const aFacts: TAnalysisRowFacts): Boolean
    begin
      Result := aFacts.fProjection = aProjection;
    end;
end;

function SelectedCount(const aFacts: TAnalysisRowFactsArray; const aSelect: TAnalysisRowSelector): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(aFacts) do
    if aSelect(aFacts[i]) then
      Inc(Result);
end;

// Counts of the FixInsight kind (aKind) or the Pascal Analyzer severity of the selected rows.
function FactCounts(const aFacts: TAnalysisRowFactsArray; const aSelect: TAnalysisRowSelector;
  aKind: Boolean): TDictionary<string, Integer>;
var
  lValue: string;
  i: Integer;
begin
  Result := TDictionary<string, Integer>.Create;
  for i := 0 to High(aFacts) do
    if aSelect(aFacts[i]) then
    begin
      if aKind then
        lValue := aFacts[i].fKind
      else
        lValue := aFacts[i].fSeverity;
      Result.AddOrSetValue(lValue, CountOf(Result, lValue) + 1);
    end;
end;

// AnalysisOwnershipCounts over the selected rows, raising on the first invalid category in order.
function FactOwnershipCounts(const aSets: array of TAnalysisRowFactsArray;
  const aSelect: TAnalysisRowSelector): TJSONObject;
var
  lCounts: array[0..3] of Integer;
  i, lSet: Integer;
begin
  for i := 0 to High(lCounts) do
    lCounts[i] := 0;
  for lSet := 0 to High(aSets) do
    for i := 0 to High(aSets[lSet]) do
      if aSelect(aSets[lSet][i]) then
      begin
        if aSets[lSet][i].fOwnership < 0 then
          raise EConvertError.CreateFmt('invalid ownership category: %s', [QuotedStr(aSets[lSet][i].fOwnershipText)]);
        Inc(lCounts[aSets[lSet][i].fOwnership]);
      end;
  Result := TJSONObject.Create;
  for i := 0 to High(cOwnershipNames) do
    Result.AddPair(cOwnershipNames[i], TJSONNumber.Create(lCounts[i]));
end;

function FactRuleCounts(const aSets: array of TAnalysisRowFactsArray; const aSelect: TAnalysisRowSelector): TJSONObject;
var
  g: TGarbos;
  lCounts: TDictionary<string, Integer>;
  lKey: string;
  i, lSet: Integer;
begin
  GC(lCounts, TDictionary<string, Integer>.Create, g);
  for lSet := 0 to High(aSets) do
    for i := 0 to High(aSets[lSet]) do
      if aSelect(aSets[lSet][i]) then
        lCounts.AddOrSetValue(aSets[lSet][i].fRule, CountOf(lCounts, aSets[lSet][i].fRule) + 1);
  Result := TJSONObject.Create;
  for lKey in SortedKeys(lCounts) do
    Result.AddPair(lKey, TJSONNumber.Create(lCounts[lKey]));
end;

function ActionableCountsOfFacts(aSummary: TJSONObject; const aFi, aPal: TAnalysisRowFactsArray): TJSONObject;
var
  g: TGarbos;
  lActionable: TAnalysisRowSelector;
  lFiKinds, lPalSeverities, lRawSeverities: TDictionary<string, Integer>;
  lFiCounts, lPalCounts, lOwnership, lSummaryPal: TJSONObject;
  lKey: string;
  lUnknown: TList<string>;
  lExpected, lActual: TArray<Integer>;
  lFiActionable, lPalActionable, lRawFiCount, lRawPalCount: Integer;
  i: Integer;
const
  cPalKeys: array[0..3] of string = ('warnings', 'strong_warnings', 'optimizations', 'total');
begin
  lActionable := SelectActionable();
  lFiActionable := SelectedCount(aFi, lActionable);
  lPalActionable := SelectedCount(aPal, lActionable);
  GC(lFiKinds, FactCounts(aFi, lActionable, True), g);
  GC(lUnknown, TList<string>.Create, g);
  for lKey in SortedKeys(lFiKinds) do
    if not MatchStr(lKey, ['W', 'C', 'O']) then
      lUnknown.Add(lKey);
  if lUnknown.Count > 0 then
    raise EConvertError.Create('Unsupported FixInsight finding kinds: ' + String.Join(', ', lUnknown.ToArray));
  Result := TJSONObject.Create;
  try
    lFiCounts := TJSONObject.Create;
    Result.AddPair('fixinsight', lFiCounts);
    lFiCounts.AddPair('total', TJSONNumber.Create(lFiActionable))
      .AddPair('warnings', TJSONNumber.Create(CountOf(lFiKinds, 'W')))
      .AddPair('maintainability', TJSONNumber.Create(CountOf(lFiKinds, 'C')))
      .AddPair('hygiene', TJSONNumber.Create(CountOf(lFiKinds, 'O')))
      .AddPair('ownership', FactOwnershipCounts([aFi], lActionable));
    lRawFiCount := Length(aFi);
    if (aSummary.GetValue('fixinsight_total') <> nil) and
      (StrToInt(aSummary.GetValue('fixinsight_total').Value) <> lRawFiCount) then
      raise EConvertError.CreateFmt('FixInsight count mismatch: summary=%s, JSONL=%d',
        [aSummary.GetValue('fixinsight_total').Value, lRawFiCount]);
    if (lRawFiCount > 0) and (aSummary.GetValue('fixinsight_total') = nil) then
      raise EConvertError.Create('FixInsight count mismatch: summary total is missing');
    GC(lPalSeverities, FactCounts(aPal, lActionable, False), g);
    lUnknown.Clear;
    for lKey in SortedKeys(lPalSeverities) do
      if not MatchStr(lKey, ['warning', 'strong-warning', 'optimization']) then
        lUnknown.Add(lKey);
    if lUnknown.Count > 0 then
      raise EConvertError.Create('Unsupported Pascal Analyzer finding severities: ' + String.Join(', ', lUnknown.ToArray));
    lPalCounts := TJSONObject.Create;
    Result.AddPair('pascal_analyzer', lPalCounts);
    lPalCounts.AddPair('warnings', TJSONNumber.Create(CountOf(lPalSeverities, 'warning')))
      .AddPair('strong_warnings', TJSONNumber.Create(CountOf(lPalSeverities, 'strong-warning')))
      .AddPair('optimizations', TJSONNumber.Create(CountOf(lPalSeverities, 'optimization')))
      .AddPair('total', TJSONNumber.Create(lPalActionable))
      .AddPair('ownership', FactOwnershipCounts([aPal], lActionable));
    lRawPalCount := Length(aPal);
    lSummaryPal := JsonObjectMember(aSummary, 'pal_totals');
    if lSummaryPal <> nil then
    begin
      GC(lRawSeverities, FactCounts(aPal, SelectAll(), False), g);
      SetLength(lExpected, 4);
      SetLength(lActual, 4);
      for i := 0 to 3 do
        lExpected[i] := StrToIntDef(JsonText(lSummaryPal, cPalKeys[i]), 0);
      lActual[0] := CountOf(lRawSeverities, 'warning');
      lActual[1] := CountOf(lRawSeverities, 'strong-warning');
      lActual[2] := CountOf(lRawSeverities, 'optimization');
      lActual[3] := lRawPalCount;
      for i := 0 to 3 do
        if lExpected[i] <> lActual[i] then
          raise EConvertError.CreateFmt(
            'Pascal Analyzer count mismatch: summary={''warnings'': %d, ''strong_warnings'': %d, ''optimizations'': %d, ''total'': %d}, ' +
            'JSONL={''warnings'': %d, ''strong_warnings'': %d, ''optimizations'': %d, ''total'': %d}',
            [lExpected[0], lExpected[1], lExpected[2], lExpected[3], lActual[0], lActual[1], lActual[2], lActual[3]]);
    end else if lRawPalCount > 0 then
      raise EConvertError.Create('Pascal Analyzer count mismatch: summary totals are missing');
    lOwnership := TJSONObject.Create;
    for lKey in cOwnershipNames do
      lOwnership.AddPair(lKey, TJSONNumber.Create(
        StrToInt(JsonText(JsonObjectMember(lFiCounts, 'ownership'), lKey)) +
        StrToInt(JsonText(JsonObjectMember(lPalCounts, 'ownership'), lKey))));
    Result.AddPair('ownership', lOwnership);
    Result.AddPair('total', TJSONNumber.Create(lFiActionable + lPalActionable));
  except
    Result.Free;
    raise;
  end;
end;

function AnalysisActionableCounts(aSummary: TJSONObject; aFixInsight, aPal: TJSONArray): TJSONObject;
begin
  Result := ActionableCountsOfFacts(aSummary, AnalysisRowFacts(aFixInsight), AnalysisRowFacts(aPal));
end;

function ProjectionCounts(const aFi, aPal: TAnalysisRowFactsArray; const aSelect: TAnalysisRowSelector): TJSONObject;
const
  cSeverityOrder: array[0..5] of string = ('warning', 'strong_warning', 'optimization',
    'maintainability', 'hygiene', 'other');
var
  g: TGarbos;
  lBySeverity, lFiBySeverity, lPalBySeverity: TJSONObject;
  lFiKinds, lFiSeverity, lPalSeverity, lPalRaw, lSeverity: TDictionary<string, Integer>;
  lKey, lName: string;
  lFiCount, lPalCount: Integer;
begin
  lFiCount := SelectedCount(aFi, aSelect);
  lPalCount := SelectedCount(aPal, aSelect);
  GC(lFiKinds, FactCounts(aFi, aSelect, True), g);
  GC(lPalRaw, FactCounts(aPal, aSelect, False), g);
  GC(lFiSeverity, TDictionary<string, Integer>.Create, g);
  GC(lPalSeverity, TDictionary<string, Integer>.Create, g);
  GC(lSeverity, TDictionary<string, Integer>.Create, g);
  for lKey in lFiKinds.Keys do
  begin
    if lKey = 'W' then
      lName := 'warning'
    else if lKey = 'C' then
      lName := 'maintainability'
    else if lKey = 'O' then
      lName := 'hygiene'
    else
      lName := 'other';
    lFiSeverity.AddOrSetValue(lName, CountOf(lFiSeverity, lName) + lFiKinds[lKey]);
  end;
  for lKey in lPalRaw.Keys do
  begin
    lName := lKey.Replace('-', '_');
    if lName = '' then
      lName := 'other';
    lPalSeverity.AddOrSetValue(lName, CountOf(lPalSeverity, lName) + lPalRaw[lKey]);
  end;
  for lKey in lFiSeverity.Keys do
    lSeverity.AddOrSetValue(lKey, CountOf(lSeverity, lKey) + lFiSeverity[lKey]);
  for lKey in lPalSeverity.Keys do
    lSeverity.AddOrSetValue(lKey, CountOf(lSeverity, lKey) + lPalSeverity[lKey]);
  lBySeverity := TJSONObject.Create;
  for lName in cSeverityOrder do
    lBySeverity.AddPair(lName, TJSONNumber.Create(CountOf(lSeverity, lName)));
  for lKey in SortedKeys(lSeverity) do
    if lBySeverity.GetValue(lKey) = nil then
      lBySeverity.AddPair(lKey, TJSONNumber.Create(lSeverity[lKey]));
  lFiBySeverity := TJSONObject.Create;
  for lKey in SortedKeys(lFiSeverity) do
    lFiBySeverity.AddPair(lKey, TJSONNumber.Create(lFiSeverity[lKey]));
  lPalBySeverity := TJSONObject.Create;
  for lKey in SortedKeys(lPalSeverity) do
    lPalBySeverity.AddPair(lKey, TJSONNumber.Create(lPalSeverity[lKey]));
  Result := TJSONObject.Create
    .AddPair('fixinsight', TJSONObject.Create
      .AddPair('total', TJSONNumber.Create(lFiCount))
      .AddPair('warnings', TJSONNumber.Create(CountOf(lFiKinds, 'W')))
      .AddPair('maintainability', TJSONNumber.Create(CountOf(lFiKinds, 'C')))
      .AddPair('hygiene', TJSONNumber.Create(CountOf(lFiKinds, 'O')))
      .AddPair('by_severity', lFiBySeverity)
      .AddPair('ownership', FactOwnershipCounts([aFi], aSelect))
      .AddPair('by_rule', FactRuleCounts([aFi], aSelect)))
    .AddPair('pascal_analyzer', TJSONObject.Create
      .AddPair('total', TJSONNumber.Create(lPalCount))
      .AddPair('warnings', TJSONNumber.Create(CountOf(lPalRaw, 'warning')))
      .AddPair('strong_warnings', TJSONNumber.Create(CountOf(lPalRaw, 'strong-warning')))
      .AddPair('optimizations', TJSONNumber.Create(CountOf(lPalRaw, 'optimization')))
      .AddPair('by_severity', lPalBySeverity)
      .AddPair('ownership', FactOwnershipCounts([aPal], aSelect))
      .AddPair('by_rule', FactRuleCounts([aPal], aSelect)))
    .AddPair('ownership', FactOwnershipCounts([aFi, aPal], aSelect))
    .AddPair('by_analyzer', TJSONObject.Create
      .AddPair('fixinsight', TJSONNumber.Create(lFiCount))
      .AddPair('pascal_analyzer', TJSONNumber.Create(lPalCount)))
    .AddPair('by_severity', lBySeverity)
    .AddPair('by_rule', FactRuleCounts([aFi, aPal], aSelect))
    .AddPair('total', TJSONNumber.Create(lFiCount + lPalCount));
end;

function AnalysisReportProjections(aSummary: TJSONObject; aFixInsight, aPal: TJSONArray): TJSONObject;
const
  cProjections: array[0..4] of string = ('actionable', 'ignored', 'external', 'advisory_metrics', 'unknown');
var
  lFi, lPal: TAnalysisRowFactsArray;
  lName: string;
begin
  lFi := AnalysisRowFacts(aFixInsight);
  lPal := AnalysisRowFacts(aPal);
  // The actionable counts are validated first, as report_projections does before projecting.
  ActionableCountsOfFacts(aSummary, lFi, lPal).Free;
  Result := TJSONObject.Create;
  try
    Result.AddPair('raw', ProjectionCounts(lFi, lPal, SelectAll()));
    for lName in cProjections do
      Result.AddPair(lName, ProjectionCounts(lFi, lPal, SelectProjection(lName)));
  except
    Result.Free;
    raise;
  end;
end;

function CanonicalLower(const aPath: string): string;
begin
  // os.path.normcase(str(path.resolve())): backslashes and lower case.
  Result := aPath.Replace('/', '\').ToLowerInvariant;
end;

function SortedPathRevisions(aItems: TJSONArray): TJSONArray;
var
  lItem: TJSONValue;
  lList: TList<TJSONObject>;
  lEntry: TJSONObject;
begin
  Result := TJSONArray.Create;
  if aItems = nil then
    Exit;
  lList := TList<TJSONObject>.Create;
  try
    for lItem in aItems do
      if lItem is TJSONObject then
        lList.Add(TJSONObject.Create
          .AddPair('path', JsonText(TJSONObject(lItem), 'path').Replace('\', '/'))
          .AddPair('revision', JsonText(TJSONObject(lItem), 'revision')));
    lList.Sort(TComparer<TJSONObject>.Construct(
      function(const aLeft, aRight: TJSONObject): Integer
      begin
        Result := CompareStr(JsonText(aLeft, 'path').ToLowerInvariant, JsonText(aRight, 'path').ToLowerInvariant);
      end));
    for lEntry in lList do
      Result.AddElement(lEntry);
  finally
    lList.Free;
  end;
end;

function AnalysisCompatibilitySnapshot(aSeed: TJSONObject; const aContext: TAnalysisOwnershipContext): TJSONObject;
var
  i: Integer;
  lAnalyzer, lAnalyzers, lCapabilities, lCapabilityStates, lCompiler, lDak, lInputs, lMaterial,
    lPolicy, lPolicyRoots, lProvenance, lSourceInputs, lSubject, lTarget, lWorkspace: TJSONObject;
  lManifests: TJSONArray;
  lItem: TJSONValue;
  lKey, lName: string;
  lKeys: TArray<string>;
  lRootEntry: TJSONArray;
  lRootList: TList<TJSONArray>;
  lNested: TJSONArray;
  lOptions: TJSONObject;
  lEncoded: string;
const
  cCompilerKeys: array[0..3] of string = ('delphi', 'platform', 'config', 'search_path_sha256');
begin
  lAnalyzers := JsonObjectMember(aSeed, 'analyzers');
  lInputs := JsonObjectMember(aSeed, 'inputs');
  lPolicy := JsonObjectMember(aSeed, 'policy');
  lSubject := JsonObjectMember(aSeed, 'subject');
  lProvenance := JsonObjectMember(aSeed, 'provenance');
  lTarget := JsonObjectMember(lProvenance, 'target');
  lDak := JsonObjectMember(lProvenance, 'dak');
  lMaterial := TJSONObject.Create;
  try
    lCapabilityStates := TJSONObject.Create;
    lManifests := TJSONArray.Create;
    if JsonArrayMember(lInputs, 'config_manifests') <> nil then
      for lItem in JsonArrayMember(lInputs, 'config_manifests') do
        if lItem is TJSONObject then
          lManifests.Add(JsonText(TJSONObject(lItem), 'sha256'));
    lCapabilities := JsonObjectMember(lTarget, 'capabilities');
    if lCapabilities <> nil then
    begin
      lKeys := nil;
      SetLength(lKeys, lCapabilities.Count);
      for i := 0 to lCapabilities.Count - 1 do
        lKeys[i] := lCapabilities.Pairs[i].JsonString.Value;
      TArray.Sort<string>(lKeys, TStringComparer.Ordinal);
      for lKey in lKeys do
      begin
        lItem := lCapabilities.GetValue(lKey);
        if (lItem is TJSONObject) or (lItem is TJSONArray) then
          Continue;
        if lItem is TJSONNull then
          lCapabilityStates.AddPair(lKey, 'None')
        else
          lCapabilityStates.AddPair(lKey, JsonText(lCapabilities, lKey));
      end;
    end;
    lSourceInputs := JsonObjectMember(lTarget, 'source_inputs');
    lRootList := TList<TJSONArray>.Create;
    try
      for i := 0 to High(aContext.fPolicyRoots) do
        lRootList.Add(TJSONArray.Create.Add(aContext.fPolicyRoots[i].fOwnership)
          .Add(CanonicalLower(aContext.fPolicyRoots[i].fPath)));
      lRootList.Sort(TComparer<TJSONArray>.Construct(
        function(const aLeft, aRight: TJSONArray): Integer
        begin
          Result := CompareStr(aLeft.Items[0].Value, aRight.Items[0].Value);
          if Result = 0 then
            Result := CompareStr(aLeft.Items[1].Value, aRight.Items[1].Value);
        end));
      lPolicyRoots := TJSONObject.Create;
      lRootEntry := TJSONArray.Create;
      for i := 0 to lRootList.Count - 1 do
        lRootEntry.AddElement(lRootList[i]);
      lRootList.Clear;
      lPolicyRoots.AddPair('policy_roots', lRootEntry);
      lNested := TJSONArray.Create;
      for lName in aContext.fMaintainedNestedRoots do
        lNested.Add(CanonicalLower(lName));
      lPolicyRoots.AddPair('maintained_nested_roots', lNested);
    finally
      for lRootEntry in lRootList do
        lRootEntry.Free;
      lRootList.Free;
    end;
    lMaterial.AddPair('ownership_contract', 'maintained-roots-v2');
    lMaterial.AddPair('ownership_boundaries', lPolicyRoots);
    lMaterial.AddPair('subject_kind', JsonText(lSubject, 'kind'));
    lWorkspace := JsonObjectMember(aSeed, 'workspace');
    lCompiler := JsonObjectMember(aSeed, 'compiler');
    lMaterial.AddPair('compiler', TJSONObject.Create
      .AddPair(cCompilerKeys[0], JsonText(lCompiler, cCompilerKeys[0]))
      .AddPair(cCompilerKeys[1], JsonText(lCompiler, cCompilerKeys[1]))
      .AddPair(cCompilerKeys[2], JsonText(lCompiler, cCompilerKeys[2]))
      .AddPair(cCompilerKeys[3], JsonText(lCompiler, cCompilerKeys[3])));
    lAnalyzer := TJSONObject.Create;
    for lName in ['fixinsight', 'pascal_analyzer'] do
    begin
      lOptions := JsonObjectMember(JsonObjectMember(lAnalyzers, lName), 'options');
      lAnalyzer.AddPair(lName, TJSONObject.Create
        .AddPair('requested', TJSONBool.Create((JsonObjectMember(lAnalyzers, lName) <> nil) and
          (JsonObjectMember(lAnalyzers, lName).GetValue('requested') is TJSONBool) and
          TJSONBool(JsonObjectMember(lAnalyzers, lName).GetValue('requested')).AsBoolean))
        .AddPair('version', JsonText(JsonObjectMember(lAnalyzers, lName), 'version'))
        .AddPair('options_sha256', JsonText(lOptions, 'sha256')));
    end;
    lMaterial.AddPair('analyzers', lAnalyzer);
    lMaterial.AddPair('policy_sha256', JsonText(lPolicy, 'sha256'));
    lMaterial.AddPair('reporting_policy_sha256', JsonText(lPolicy, 'reporting_sha256'));
    if JsonObjectMember(lPolicy, 'origins') <> nil then
      lMaterial.AddPair('reporting_policy_origins', JsonCloneValue(JsonObjectMember(lPolicy, 'origins')))
    else
      lMaterial.AddPair('reporting_policy_origins', TJSONObject.Create);
    lKey := JsonText(lInputs, 'project_sha256');
    if lKey = '' then
      lKey := JsonText(lInputs, 'project_context_sha256');
    lMaterial.AddPair('project_manifest_sha256', lKey);
    lMaterial.AddPair('config_manifest_sha256', lManifests);
    lKey := JsonText(lWorkspace, 'root');
    if lKey = '' then
      lKey := JsonText(lTarget, 'root');
    lName := JsonText(lWorkspace, 'vcs');
    if lName = '' then
      lName := JsonText(lTarget, 'vcs');
    lMaterial.AddPair('workspace', TJSONObject.Create
      .AddPair('root', lKey.Replace('\', '/'))
      .AddPair('vcs', lName)
      .AddPair('status', JsonText(lTarget, 'status'))
      .AddPair('inventory_scope', JsonText(lSourceInputs, 'scope'))
      .AddPair('capabilities', lCapabilityStates)
      .AddPair('externals', SortedPathRevisions(JsonArrayMember(lTarget, 'externals'))));
    lMaterial.AddPair('submodules', SortedPathRevisions(JsonArrayMember(lTarget, 'submodules')));
    lMaterial.AddPair('dak', TJSONObject.Create
      .AddPair('head', JsonText(lDak, 'head'))
      .AddPair('executable_sha256', JsonText(lDak, 'executable_sha256')));
    lEncoded := TPythonJson.Compact(lMaterial);
    Result := TJSONObject.Create
      .AddPair('sha256', LowerCase(THashSHA2.GetHashString(lEncoded)))
      .AddPair('context', lMaterial);
  except
    lMaterial.Free;
    raise;
  end;
end;

function AnalysisActiveTriagePolicy: TJSONObject;
var
  lTop: Integer;
begin
  lTop := AnalysisIntegerEnvironment('DAK_TRIAGE_TOP', 20);
  if lTop = 0 then
    lTop := 20;
  Result := TJSONObject.Create
    .AddPair('top', TJSONNumber.Create(lTop))
    .AddPair('include_paths', Trim(GetEnvironmentVariable('DAK_TRIAGE_INCLUDE_PATHS')))
    .AddPair('exclude_paths', Trim(GetEnvironmentVariable('DAK_TRIAGE_EXCLUDE_PATHS')))
    .AddPair('pal_include_call_tree', TJSONBool.Create(AnalysisTruthyEnvironment('DAK_TRIAGE_PAL_INCLUDE_CALL_TREE', False)));
end;

end.
