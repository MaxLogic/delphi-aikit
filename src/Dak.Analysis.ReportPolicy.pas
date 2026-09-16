unit Dak.Analysis.ReportPolicy;

{$SCOPEDENUMS ON}

interface

uses
  System.JSON;

type
  // Everything the policy stage reads from the finalized report, so it derives nothing twice.
  TAnalysisPolicyInput = record
    fOutRoot: string;
    fTitle: string;
    fSummaryPath: string;
    // The workspace Git root, or '' when the target is not a Git checkout; only history uses it.
    fRepoRoot: string;
    fSummary: TJSONObject;
    fSeed: TJSONObject;
    fRunContext: TJSONObject;
    fResolvedPolicy: TJSONObject;
    fActionable: TJSONObject;
    fCounts: TJSONObject;
    fCompatibility: TJSONObject;
    fFi: TJSONArray;
    fPal: TJSONArray;
  end;

  TAnalysisPolicyOutcome = record
    fBaselinePath: string;
    fDeltaPath: string;
    fDeltaMdPath: string;
    fHistoryPath: string;
    fTrendPath: string;
    fGatePass: Boolean;
    fPolicyEvaluated: Boolean;
    fBaselineCreated: Boolean;
    fBaselineUpdated: Boolean;
    // The version 4 snapshot of this run; caller-owned.
    fSnapshot: TJSONObject;
  end;

// The baseline/delta half of run_postprocess: reads any existing baseline, computes the delta,
// evaluates the gate and publishes baseline.json/.md and delta.json/.md. Never replaces a baseline
// the gate rejected, and never approves one implicitly.
function ApplyAnalysisReportPolicy(const aInput: TAnalysisPolicyInput): TAnalysisPolicyOutcome;
// _update_history_and_trend: appends one history row per distinct summary timestamp and rewrites
// the human-readable trend view.
procedure UpdateAnalysisHistoryAndTrend(const aInput: TAnalysisPolicyInput; aSnapshot: TJSONObject;
  out aHistoryPath, aTrendPath: string);

implementation

uses
  System.Generics.Collections, System.Generics.Defaults, System.Hash, System.IOUtils, System.Math,
  System.RegularExpressions, System.StrUtils, System.SysUtils,
  AutoFree,
  Dak.Analysis.Findings, Dak.Analysis.JsonText, Dak.Analysis.Projections, Dak.Analysis.ReportBundle,
  Dak.Analysis.ReportWriters, Dak.Analysis.Text, Dak.Analysis.Workspace;

const
  cOwnershipNames: array[0..3] of string = ('project', 'repository', 'third_party', 'unknown');

type
  TStringCounts = TDictionary<string, Integer>;

function JoinArray(aValues: TJSONArray; const aSeparator: string): string;
var
  lItem: TJSONValue;
  lParts: TList<string>;
begin
  lParts := TList<string>.Create;
  try
    if aValues <> nil then
      for lItem in aValues do
        lParts.Add(lItem.Value);
    Result := String.Join(aSeparator, lParts.ToArray);
  finally
    lParts.Free;
  end;
end;

function Sha1Hex(const aText: string): string;
begin
  Result := THashSHA1.GetHashString(aText).ToLowerInvariant;
end;

function EmptyOwnershipCounts: TJSONObject;
var
  lName: string;
begin
  Result := TJSONObject.Create;
  for lName in cOwnershipNames do
    Result.AddPair(lName, TJSONNumber.Create(0));
end;

function OwnershipValue(aCounts: TJSONObject; const aName: string): Integer;
begin
  Result := StrToIntDef(JsonText(aCounts, aName), 0);
end;

// json.dumps writes Python ints without a decimal point; the deltas are always whole numbers.
function IntegerPair(const aName: string; aValue: Integer): TJSONPair;
begin
  Result := TJSONPair.Create(aName, TJSONNumber.Create(aValue));
end;

// A member that is an int in the reference, or JSON null when the baseline never recorded it.
function NullableInteger(aObject: TJSONObject; const aName: string; out aValue: Integer): Boolean;
var
  lValue: TJSONValue;
begin
  aValue := 0;
  lValue := nil;
  if aObject <> nil then
    lValue := aObject.GetValue(aName);
  Result := (lValue is TJSONNumber) and TryStrToInt(lValue.Value, aValue);
end;

function NullableIntegerValue(aObject: TJSONObject; const aName: string): TJSONValue;
var
  lValue: Integer;
begin
  if NullableInteger(aObject, aName, lValue) then
    Result := TJSONNumber.Create(lValue)
  else
    Result := TJSONNull.Create;
end;

function ObjectOrEmpty(aObject: TJSONObject; const aName: string): TJSONObject;
begin
  Result := JsonObjectMember(aObject, aName);
end;

function ActionableRows(aRows: TJSONArray): TList<TJSONObject>;
var
  lItem: TJSONValue;
begin
  Result := TList<TJSONObject>.Create;
  if aRows = nil then
    Exit;
  for lItem in aRows do
    if AnalysisRecordIsActionable(TJSONObject(lItem)) then
      Result.Add(TJSONObject(lItem));
end;

function PalFingerprint(aRow: TJSONObject): string;
begin
  // Canonical identity and location keep PAL deltas stable and actionable.
  Result := Sha1Hex(String.Join('|', [JsonText(aRow, 'severity'), JsonText(aRow, 'normalized_rule'),
    JsonText(aRow, 'pal_code'), JsonText(aRow, 'module'), JsonText(aRow, 'line'), JsonText(aRow, 'message'),
    JsonText(aRow, 'id'), JsonText(aRow, 'kind')]));
end;

function FixInsightFingerprint(aRow: TJSONObject; aUseNormalizedPath: Boolean): string;
var
  lFile: string;
begin
  if aUseNormalizedPath then
    lFile := JsonText(aRow, 'path')
  else
    lFile := JsonText(aRow, 'file');
  if lFile = '' then
    lFile := JsonText(aRow, 'file');
  if lFile = '' then
    lFile := JsonText(aRow, 'path');
  Result := Sha1Hex(String.Join('|', [JsonText(aRow, 'code'), lFile, JsonText(aRow, 'line'),
    JsonText(aRow, 'col'), JsonText(aRow, 'message')]));
end;

function SortedStringArray(aValues: TDictionary<string, Boolean>): TJSONArray;
var
  lKeys: TArray<string>;
  lKey: string;
begin
  lKeys := aValues.Keys.ToArray;
  TArray.Sort<string>(lKeys, TStringComparer.Ordinal);
  Result := TJSONArray.Create;
  for lKey in lKeys do
    Result.Add(lKey);
end;

function SortedCountKeys(aCounts: TStringCounts): TArray<string>;
begin
  Result := aCounts.Keys.ToArray;
  TArray.Sort<string>(Result, TStringComparer.Ordinal);
end;

// A Python dict filled in row order: the members follow aOrder, the first-seen order of the keys.
function OrderedCountsObject(aCounts: TStringCounts; aOrder: TList<string>): TJSONObject;
var
  lKey: string;
begin
  Result := TJSONObject.Create;
  for lKey in aOrder do
    Result.AddPair(lKey, TJSONNumber.Create(aCounts[lKey]));
end;

// The member names of a counts object in document order, which is the dict order Python iterates:
// row order for a fresh snapshot, file order for a loaded baseline.
function MemberNames(aObject: TJSONObject): TArray<string>;
var
  lPair: TJSONPair;
begin
  Result := nil;
  if aObject = nil then
    Exit;
  for lPair in aObject do
    Result := Result + [lPair.JsonString.Value];
end;

procedure Bump(aCounts: TStringCounts; const aKey: string);
var
  lCount: Integer;
begin
  if not aCounts.TryGetValue(aKey, lCount) then
    lCount := 0;
  aCounts.AddOrSetValue(aKey, lCount + 1);
end;

function CountsFromObject(aObject: TJSONObject): TStringCounts;
var
  lPair: TJSONPair;
  lValue: Integer;
begin
  Result := TStringCounts.Create;
  if aObject = nil then
    Exit;
  for lPair in aObject do
    if TryStrToInt(lPair.JsonValue.Value, lValue) then
      Result.AddOrSetValue(lPair.JsonString.Value, lValue);
end;

// _top_section_counts: the ten most frequent sections of one severity, most frequent first and
// ties in first-seen order, as collections.Counter.most_common reports them.
function TopSectionCounts(aRows: TList<TJSONObject>; const aSeverity: string): TJSONArray;
var
  lCounts: TStringCounts;
  lOrder: TList<string>;
  lRow: TJSONObject;
  lSection: string;
  lPairs: TArray<string>;
  i, j: Integer;
  lBest: Integer;
begin
  Result := TJSONArray.Create;
  lCounts := TStringCounts.Create;
  lOrder := TList<string>.Create;
  try
    for lRow in aRows do
    begin
      if JsonText(lRow, 'severity') <> aSeverity then
        Continue;
      lSection := Trim(JsonText(lRow, 'section'));
      if lSection = '' then
        Continue;
      if not lCounts.ContainsKey(lSection) then
        lOrder.Add(lSection);
      Bump(lCounts, lSection);
    end;
    lPairs := lOrder.ToArray;
    // Stable selection sort by descending count, preserving insertion order within a count.
    for i := 0 to High(lPairs) do
    begin
      lBest := i;
      for j := i + 1 to High(lPairs) do
        if lCounts[lPairs[j]] > lCounts[lPairs[lBest]] then
          lBest := j;
      if lBest <> i then
      begin
        lSection := lPairs[lBest];
        for j := lBest downto i + 1 do
          lPairs[j] := lPairs[j - 1];
        lPairs[i] := lSection;
      end;
    end;
    for i := 0 to Min(High(lPairs), 9) do
      Result.AddElement(TJSONObject.Create
        .AddPair('section', lPairs[i])
        .AddPair('count', TJSONNumber.Create(lCounts[lPairs[i]])));
  finally
    lOrder.Free;
    lCounts.Free;
  end;
end;

// _section_delta and _code_delta: the ten largest absolute changes, ties in set-iteration order.
// Python's set order is unspecified, so we compare by magnitude and then by key to stay stable.
function NamedDelta(aBefore, aAfter: TStringCounts; const aKeyName: string): TJSONArray;
var
  lKeys: TList<string>;
  lKey: string;
  lRows: TList<TJSONObject>;
  lBefore, lAfter: Integer;
  i: Integer;
begin
  lKeys := TList<string>.Create;
  lRows := TList<TJSONObject>.Create;
  try
    for lKey in SortedCountKeys(aBefore) do
      lKeys.Add(lKey);
    for lKey in SortedCountKeys(aAfter) do
      if not lKeys.Contains(lKey) then
        lKeys.Add(lKey);
    lKeys.Sort(TStringComparer.Ordinal);
    for lKey in lKeys do
    begin
      if not aBefore.TryGetValue(lKey, lBefore) then
        lBefore := 0;
      if not aAfter.TryGetValue(lKey, lAfter) then
        lAfter := 0;
      if lAfter = lBefore then
        Continue;
      lRows.Add(TJSONObject.Create
        .AddPair(aKeyName, lKey)
        .AddPair('before', TJSONNumber.Create(lBefore))
        .AddPair('after', TJSONNumber.Create(lAfter))
        .AddPair('delta', TJSONNumber.Create(lAfter - lBefore)));
    end;
    lRows.Sort(TComparer<TJSONObject>.Construct(
      function(const aLeft, aRight: TJSONObject): Integer
      begin
        Result := Abs(StrToIntDef(JsonText(aRight, 'delta'), 0)) - Abs(StrToIntDef(JsonText(aLeft, 'delta'), 0));
      end));
    Result := TJSONArray.Create;
    for i := 0 to Min(lRows.Count - 1, 9) do
      Result.AddElement(lRows[i]);
    for i := 10 to lRows.Count - 1 do
      lRows[i].Free;
  finally
    lRows.Free;
    lKeys.Free;
  end;
end;

// _rule_count_delta: one row per rule present on either side, in code-point order.
function RuleCountDelta(aBefore, aAfter: TJSONObject): TJSONArray;
var
  g: TGarbos;
  lAfter, lBefore: TStringCounts;
  lKey: string;
  lKeys: TList<string>;
  lBeforeCount, lAfterCount: Integer;
begin
  GC(lBefore, CountsFromObject(aBefore), g);
  GC(lAfter, CountsFromObject(aAfter), g);
  GC(lKeys, TList<string>.Create, g);
  for lKey in lBefore.Keys do
    lKeys.Add(lKey);
  for lKey in lAfter.Keys do
    if not lKeys.Contains(lKey) then
      lKeys.Add(lKey);
  lKeys.Sort(TStringComparer.Ordinal);
  Result := TJSONArray.Create;
  for lKey in lKeys do
  begin
    if not lBefore.TryGetValue(lKey, lBeforeCount) then
      lBeforeCount := 0;
    if not lAfter.TryGetValue(lKey, lAfterCount) then
      lAfterCount := 0;
    Result.AddElement(TJSONObject.Create
      .AddPair('rule', lKey)
      .AddPair('before', TJSONNumber.Create(lBeforeCount))
      .AddPair('after', TJSONNumber.Create(lAfterCount))
      .AddPair('delta', TJSONNumber.Create(lAfterCount - lBeforeCount)));
  end;
end;

// _diff_run_context: only differences between two known, concrete values are worth reporting.
function DiffRunContext(aBaseline, aCurrent: TJSONObject): TArray<string>;
var
  lLines: TList<string>;
  lBaselineTools, lCurrentTools: TJSONObject;

  procedure Add(const aLabel: string; aBefore, aAfter: TJSONObject; const aName: string);
  var
    lAfterValue, lBeforeValue: string;
  begin
    lBeforeValue := Trim(JsonText(aBefore, aName));
    lAfterValue := Trim(JsonText(aAfter, aName));
    if (lBeforeValue = '') or (lAfterValue = '') then
      Exit;
    if MatchText(lBeforeValue, ['unknown', '?']) or MatchText(lAfterValue, ['unknown', '?']) then
      Exit;
    if lBeforeValue = lAfterValue then
      Exit;
    lLines.Add(aLabel + ': ' + lBeforeValue + ' -> ' + lAfterValue);
  end;

begin
  lLines := TList<string>.Create;
  try
    Add('platform', aBaseline, aCurrent, 'platform');
    Add('config', aBaseline, aCurrent, 'config');
    Add('delphi', aBaseline, aCurrent, 'delphi');
    lBaselineTools := JsonObjectMember(aBaseline, 'tools');
    lCurrentTools := JsonObjectMember(aCurrent, 'tools');
    Add('pal_version', lBaselineTools, lCurrentTools, 'pal_version');
    Add('pal_compiler_target', lBaselineTools, lCurrentTools, 'pal_compiler_target');
    Add('pal_compiler_switch', lBaselineTools, lCurrentTools, 'pal_compiler_switch');
    Result := lLines.ToArray;
  finally
    lLines.Free;
  end;
end;

function SignedText(aValue: Integer): string;
begin
  // Python's {:+d}
  if aValue >= 0 then
    Result := '+' + IntToStr(aValue)
  else
    Result := IntToStr(aValue);
end;

function TextOrQuestion(aObject: TJSONObject; const aName: string): string;
begin
  if (aObject = nil) or (aObject.GetValue(aName) = nil) or (aObject.GetValue(aName) is TJSONNull) then
    Exit('?');
  Result := JsonText(aObject, aName);
end;

function DeltaOrZero(aObject: TJSONObject; const aName: string): Integer;
begin
  if not NullableInteger(aObject, aName, Result) then
    Result := 0;
end;

function ContextLine(const aLabel: string; aContext: TJSONObject): string;
begin
  Result := Format('- %s: platform=%s, config=%s, delphi=%s',
    [aLabel, TextOrQuestion(aContext, 'platform'), TextOrQuestion(aContext, 'config'),
     TextOrQuestion(aContext, 'delphi')]);
end;

function RenderDeltaMarkdown(aDelta: TJSONObject): string;
var
  g: TGarbos;
  lBaseline, lCurrent, lFi, lGate, lOwnership, lPal, lPathFilter: TJSONObject;
  lExclude, lInclude, lRows: TJSONArray;
  lItem: TJSONValue;
  lLines: TList<string>;
  lMismatch: string;
  lMismatches: TArray<string>;
  lTitle: string;

  procedure AddRows(const aHeading, aKeyName: string; aList: TJSONArray);
  var
    lEntry: TJSONValue;
    lRowObject: TJSONObject;
  begin
    if (aList = nil) or (aList.Count = 0) then
      Exit;
    lLines.Add(aHeading);
    for lEntry in aList do
    begin
      lRowObject := TJSONObject(lEntry);
      lLines.Add(Format('  - %s: %s -> %s (%s)', [JsonText(lRowObject, aKeyName), JsonText(lRowObject, 'before'),
        JsonText(lRowObject, 'after'), SignedText(StrToIntDef(JsonText(lRowObject, 'delta'), 0))]));
    end;
  end;

  procedure AddPreview(const aHeading: string; aList: TJSONArray);
  var
    lIndex: Integer;
  begin
    if (aList = nil) or (aList.Count = 0) then
      Exit;
    lLines.Add(aHeading);
    for lIndex := 0 to Min(aList.Count - 1, 19) do
      lLines.Add('- ' + aList.Items[lIndex].Value);
    lLines.Add('');
  end;

begin
  GC(lLines, TList<string>.Create, g);
  lTitle := JsonText(aDelta, 'title');
  if lTitle = '' then
    lTitle := 'Static analysis delta';
  lLines.Add('# ' + lTitle);
  lLines.Add('');
  lBaseline := ObjectOrEmpty(aDelta, 'baseline');
  lCurrent := ObjectOrEmpty(aDelta, 'current');
  lLines.Add(Format('- Baseline: `%s` (%s)', [JsonText(lBaseline, 'path'),
    IfThen(TextOrQuestion(lBaseline, 'timestamp') = '?', 'unknown', JsonText(lBaseline, 'timestamp'))]));
  lLines.Add(Format('- Current: `%s` (%s)', [JsonText(lCurrent, 'summary_path'),
    IfThen(TextOrQuestion(lCurrent, 'timestamp') = '?', 'unknown', JsonText(lCurrent, 'timestamp'))]));
  if (JsonObjectMember(lBaseline, 'run_context') <> nil) and (JsonObjectMember(lBaseline, 'run_context').Count > 0) then
    lLines.Add(ContextLine('Baseline context', JsonObjectMember(lBaseline, 'run_context')));
  if (JsonObjectMember(lCurrent, 'run_context') <> nil) and (JsonObjectMember(lCurrent, 'run_context').Count > 0) then
    lLines.Add(ContextLine('Current context', JsonObjectMember(lCurrent, 'run_context')));
  lLines.Add('');
  lMismatches := DiffRunContext(JsonObjectMember(lBaseline, 'run_context'), JsonObjectMember(lCurrent, 'run_context'));
  if Length(lMismatches) > 0 then
  begin
    lLines.Add('## Context mismatch');
    lLines.Add('Baseline and current analysis contexts differ; deltas and gates may be misleading.');
    for lMismatch in lMismatches do
      lLines.Add('- ' + lMismatch);
    lLines.Add('');
  end;
  lFi := ObjectOrEmpty(aDelta, 'fixinsight');
  lLines.Add('## FixInsight');
  lLines.Add(Format('- Findings: %s -> %s (%s)', [TextOrQuestion(lFi, 'total_before'),
    TextOrQuestion(lFi, 'total_after'), SignedText(DeltaOrZero(lFi, 'total_delta'))]));
  lLines.Add(Format('- New W-findings: %d', [DeltaOrZero(lFi, 'new_w_count')]));
  AddRows('- Top code deltas:', 'code', JsonArrayMember(lFi, 'top_code_deltas'));
  lLines.Add('');
  lPal := ObjectOrEmpty(aDelta, 'pascal_analyzer');
  lLines.Add('## Pascal Analyzer');
  lLines.Add(Format('- Strong warnings: %s -> %s (%s)', [TextOrQuestion(lPal, 'strong_before'),
    TextOrQuestion(lPal, 'strong_after'), SignedText(DeltaOrZero(lPal, 'strong_delta'))]));
  lLines.Add(Format('- Warnings: %s -> %s (%s)', [TextOrQuestion(lPal, 'warnings_before'),
    TextOrQuestion(lPal, 'warnings_after'), SignedText(DeltaOrZero(lPal, 'warnings_delta'))]));
  lLines.Add(Format('- Optimizations: %s -> %s (%s)', [TextOrQuestion(lPal, 'optimizations_before'),
    TextOrQuestion(lPal, 'optimizations_after'), SignedText(DeltaOrZero(lPal, 'optimizations_delta'))]));
  lLines.Add(Format('- Total: %s -> %s (%s)', [TextOrQuestion(lPal, 'total_before'),
    TextOrQuestion(lPal, 'total_after'), SignedText(DeltaOrZero(lPal, 'total_delta'))]));
  AddRows('- Top section deltas (warnings):', 'section', JsonArrayMember(lPal, 'top_section_deltas'));
  lLines.Add('');
  lRows := JsonArrayMember(lPal, 'new_strong');
  if (lRows <> nil) and (lRows.Count > 0) then
    AddPreview(Format('### New strong warnings (%d)', [lRows.Count]), lRows);
  if DeltaOrZero(lPal, 'new_warnings_count') <> 0 then
    AddPreview(Format('### New warnings (%d)', [DeltaOrZero(lPal, 'new_warnings_count')]),
      JsonArrayMember(lPal, 'new_warnings_preview'));
  lRows := JsonArrayMember(lFi, 'new_w');
  if (lRows <> nil) and (lRows.Count > 0) then
    AddPreview(Format('### New FixInsight W-findings (%d)', [lRows.Count]), lRows);
  lOwnership := ObjectOrEmpty(aDelta, 'ownership');
  lLines.Add('## Ownership');
  lLines.Add('- Before: ' + AnalysisOwnershipText(JsonObjectMember(lOwnership, 'before')));
  lLines.Add('- After: ' + AnalysisOwnershipText(JsonObjectMember(lOwnership, 'after')));
  lLines.Add('- Delta: ' + AnalysisOwnershipText(JsonObjectMember(lOwnership, 'delta')));
  lLines.Add('');
  lGate := ObjectOrEmpty(aDelta, 'gate');
  if (lGate <> nil) and (lGate.GetValue('enabled') is TJSONBool) and TJSONBool(lGate.GetValue('enabled')).AsBoolean then
  begin
    lLines.Add('## Gate');
    lLines.Add('- Result: **' + IfThen((lGate.GetValue('pass') is TJSONBool) and
      TJSONBool(lGate.GetValue('pass')).AsBoolean, 'PASS', 'FAIL') + '**');
    lPathFilter := JsonObjectMember(lGate, 'path_filter');
    lInclude := JsonArrayMember(lPathFilter, 'include');
    lExclude := JsonArrayMember(lPathFilter, 'exclude');
    if ((lInclude <> nil) and (lInclude.Count > 0)) or ((lExclude <> nil) and (lExclude.Count > 0)) then
      lLines.Add(Format('- Path filter: include=%s, exclude=%s',
        [IfThen((lInclude = nil) or (lInclude.Count = 0), '(none)', JoinArray(lInclude, ';')),
         IfThen((lExclude = nil) or (lExclude.Count = 0), '(none)', JoinArray(lExclude, ';'))]));
    if JsonArrayMember(lGate, 'reasons') <> nil then
      for lItem in JsonArrayMember(lGate, 'reasons') do
        lLines.Add('- ' + lItem.Value);
    lLines.Add('');
  end;
  Result := String.Join(#10, lLines.ToArray).TrimRight + #10;
end;

function RenderBaselineMarkdown(const aTitle, aBaselinePath, aSummaryPath: string; aSnapshot: TJSONObject): string;
var
  g: TGarbos;
  lContext, lFi, lPal, lRow, lTotals: TJSONObject;
  lCounts: TStringCounts;
  lItem: TJSONValue;
  lKeys: TArray<string>;
  lLines: TList<string>;
  lSections: TJSONArray;
  i, j, lBest: Integer;
  lSwap: string;
begin
  GC(lLines, TList<string>.Create, g);
  lLines.Add('# Static analysis baseline: ' + aTitle);
  lLines.Add('');
  lLines.Add('- Timestamp: ' + IfThen(JsonText(aSnapshot, 'created_at') = '', 'unknown', JsonText(aSnapshot, 'created_at')));
  lLines.Add('- Baseline file: `' + aBaselinePath + '`');
  lLines.Add('- Summary: `' + aSummaryPath + '`');
  lContext := JsonObjectMember(aSnapshot, 'run_context');
  if (lContext <> nil) and (lContext.Count > 0) then
    lLines.Add(ContextLine('Context', lContext));
  lLines.Add('');
  lFi := JsonObjectMember(aSnapshot, 'fixinsight');
  lLines.Add('## FixInsight');
  lLines.Add('- Findings: ' + TextOrQuestion(lFi, 'total'));
  GC(lCounts, CountsFromObject(JsonObjectMember(lFi, 'counts_by_code')), g);
  if lCounts.Count > 0 then
  begin
    lLines.Add('- Top codes:');
    lKeys := MemberNames(JsonObjectMember(lFi, 'counts_by_code'));
    // sorted(..., key=count, reverse=True) is stable: equal counts keep the dict's own order.
    for i := 0 to High(lKeys) do
    begin
      lBest := i;
      for j := i + 1 to High(lKeys) do
        if lCounts[lKeys[j]] > lCounts[lKeys[lBest]] then
          lBest := j;
      if lBest <> i then
      begin
        lSwap := lKeys[lBest];
        for j := lBest downto i + 1 do
          lKeys[j] := lKeys[j - 1];
        lKeys[i] := lSwap;
      end;
    end;
    for i := 0 to Min(High(lKeys), 9) do
      lLines.Add(Format('  - %s: %d', [lKeys[i], lCounts[lKeys[i]]]));
  end;
  lLines.Add('');
  lPal := JsonObjectMember(aSnapshot, 'pascal_analyzer');
  lLines.Add('## Pascal Analyzer');
  lTotals := JsonObjectMember(lPal, 'totals');
  if (lTotals <> nil) and (lTotals.Count > 0) then
    lLines.Add(Format('- Totals: warnings=%s, strong_warnings=%s, optimizations=%s, total=%s',
      [TextOrQuestion(lTotals, 'warnings'), TextOrQuestion(lTotals, 'strong_warnings'),
       TextOrQuestion(lTotals, 'optimizations'), TextOrQuestion(lTotals, 'total')]));
  lSections := JsonArrayMember(lPal, 'top_warning_sections');
  if (lSections <> nil) and (lSections.Count > 0) then
  begin
    lLines.Add('- Top warning sections:');
    for lItem in lSections do
    begin
      lRow := TJSONObject(lItem);
      lLines.Add(Format('  - %s: %s', [TextOrQuestion(lRow, 'section'), TextOrQuestion(lRow, 'count')]));
    end;
  end;
  lLines.Add('');
  Result := String.Join(#10, lLines.ToArray).TrimRight + #10;
end;

function GatedOwnershipMatches(aGated: TJSONArray; const aOwnership: string): Boolean;
var
  lItem: TJSONValue;
begin
  Result := False;
  if aGated = nil then
    Exit;
  for lItem in aGated do
    if lItem.Value = aOwnership then
      Exit(True);
end;

// The first aCount elements; the caller owns the result and the remainder is released.
function LimitedArray(aValues: TJSONArray; aCount: Integer): TJSONArray;
begin
  Result := aValues;
  while Result.Count > aCount do
    Result.Remove(Result.Count - 1).Free;
end;

function BaselineTimestamp(aBaseline: TJSONObject): string;
begin
  Result := JsonText(aBaseline, 'created_at');
  if Result = '' then
    Result := JsonText(JsonObjectMember(aBaseline, 'summary'), 'timestamp');
end;

function SectionCounts(aSections: TJSONArray): TStringCounts;
var
  lItem: TJSONValue;
  lRow: TJSONObject;
  lValue: Integer;
begin
  Result := TStringCounts.Create;
  if aSections = nil then
    Exit;
  for lItem in aSections do
  begin
    lRow := TJSONObject(lItem);
    if (lRow.GetValue('section') = nil) or (lRow.GetValue('count') = nil) then
      Continue;
    if TryStrToInt(JsonText(lRow, 'count'), lValue) then
      Result.AddOrSetValue(JsonText(lRow, 'section'), lValue);
  end;
end;

function SectionDelta(aBefore, aAfter: TJSONArray): TJSONArray;
var
  g: TGarbos;
  lAfter, lBefore: TStringCounts;
begin
  GC(lBefore, SectionCounts(aBefore), g);
  GC(lAfter, SectionCounts(aAfter), g);
  if (lBefore.Count = 0) and (lAfter.Count = 0) then
    Exit(TJSONArray.Create);
  Result := NamedDelta(lBefore, lAfter, 'section');
end;

// _select_new_pal_items / _select_new_fi_items: the human-readable lines for the new findings.
function SelectNewPalItems(aRows: TList<TJSONObject>; aNew: TDictionary<string, Boolean>;
  const aSeverity: string): TJSONArray;
var
  lRow: TJSONObject;
begin
  Result := TJSONArray.Create;
  if aNew.Count = 0 then
    Exit;
  for lRow in aRows do
  begin
    if JsonText(lRow, 'severity') <> aSeverity then
      Continue;
    if not aNew.ContainsKey(PalFingerprint(lRow)) then
      Continue;
    Result.Add(Format('[%s] %s:%s - %s', [JsonText(lRow, 'section'),
      TextOrQuestion(lRow, 'module'), TextOrQuestion(lRow, 'line'), JsonText(lRow, 'message')]));
  end;
end;

function SelectNewFixInsightItems(aRows: TList<TJSONObject>; aNew: TDictionary<string, Boolean>;
  aUseNormalizedPath: Boolean): TJSONArray;
var
  lFile: string;
  lRow: TJSONObject;
begin
  Result := TJSONArray.Create;
  if aNew.Count = 0 then
    Exit;
  for lRow in aRows do
  begin
    if JsonText(lRow, 'kind') <> 'W' then
      Continue;
    if not aNew.ContainsKey(FixInsightFingerprint(lRow, aUseNormalizedPath)) then
      Continue;
    lFile := JsonText(lRow, 'path');
    if lFile = '' then
      lFile := JsonText(lRow, 'file');
    if lFile = '' then
      lFile := '?';
    Result.Add(Format('[%s] %s:%s:%s - %s', [TextOrQuestion(lRow, 'code'), lFile,
      TextOrQuestion(lRow, 'line'), TextOrQuestion(lRow, 'col'), JsonText(lRow, 'message')]));
  end;
end;

// The version 4 run snapshot: the identity a future run compares itself against.
function BuildRunSnapshot(const aInput: TAnalysisPolicyInput): TJSONObject;
var
  g: TGarbos;
  lActionableFi, lActionablePal, lPalWarnings: TList<TJSONObject>;
  lCountsByCode: TStringCounts;
  lCodeOrder: TList<string>;
  lCreated: string;
  lFi, lPal, lRawCounts, lActionableCounts: TJSONObject;
  lRow: TJSONObject;
  lStrong, lWarning, lWHashes: TDictionary<string, Boolean>;
  lTotals: TJSONObject;
  lName: string;
begin
  GC(lActionableFi, ActionableRows(aInput.fFi), g);
  GC(lActionablePal, ActionableRows(aInput.fPal), g);
  GC(lPalWarnings, TList<TJSONObject>.Create, g);
  GC(lCountsByCode, TStringCounts.Create, g);
  GC(lCodeOrder, TList<string>.Create, g);
  GC(lWarning, TDictionary<string, Boolean>.Create, g);
  GC(lStrong, TDictionary<string, Boolean>.Create, g);
  GC(lWHashes, TDictionary<string, Boolean>.Create, g);
  for lRow in lActionablePal do
  begin
    if JsonText(lRow, 'severity') = 'warning' then
    begin
      lWarning.AddOrSetValue(PalFingerprint(lRow), True);
      lPalWarnings.Add(lRow);
    end else if JsonText(lRow, 'severity') = 'strong-warning' then
      lStrong.AddOrSetValue(PalFingerprint(lRow), True);
  end;
  for lRow in lActionableFi do
  begin
    if JsonText(lRow, 'code') <> '' then
    begin
      if not lCountsByCode.ContainsKey(JsonText(lRow, 'code')) then
        lCodeOrder.Add(JsonText(lRow, 'code'));
      Bump(lCountsByCode, JsonText(lRow, 'code'));
    end;
    if JsonText(lRow, 'kind') <> 'W' then
      Continue;
    lWHashes.AddOrSetValue(FixInsightFingerprint(lRow, True), True);
  end;
  lActionableCounts := aInput.fActionable;
  lRawCounts := JsonObjectMember(aInput.fCounts, 'raw');
  lCreated := JsonText(aInput.fSummary, 'timestamp');
  if lCreated = '' then
    lCreated := AnalysisUtcNowIso;
  lTotals := TJSONObject.Create;
  for lName in ['warnings', 'strong_warnings', 'optimizations', 'total'] do
    lTotals.AddPair(lName, JsonCloneValue(
      JsonObjectMember(lActionableCounts, 'pascal_analyzer').GetValue(lName)));
  lFi := TJSONObject.Create
    .AddPair('total', JsonCloneValue(JsonObjectMember(lActionableCounts, 'fixinsight').GetValue('total')))
    .AddPair('counts_by_code', OrderedCountsObject(lCountsByCode, lCodeOrder))
    .AddPair('w_hashes', SortedStringArray(lWHashes))
    .AddPair('ownership', JsonCloneValue(JsonObjectMember(JsonObjectMember(lActionableCounts, 'fixinsight'), 'ownership')));
  lPal := TJSONObject.Create
    .AddPair('totals', lTotals)
    .AddPair('top_warning_sections', TopSectionCounts(lActionablePal, 'warning'))
    .AddPair('warning_hashes', SortedStringArray(lWarning))
    .AddPair('strong_hashes', SortedStringArray(lStrong))
    .AddPair('rule_counts', JsonCloneValue(JsonObjectMember(JsonObjectMember(
      JsonObjectMember(aInput.fCounts, 'actionable'), 'pascal_analyzer'), 'by_rule')))
    .AddPair('raw_rule_counts', JsonCloneValue(JsonObjectMember(JsonObjectMember(
      JsonObjectMember(aInput.fCounts, 'raw'), 'pascal_analyzer'), 'by_rule')))
    .AddPair('ignored_rule_counts', JsonCloneValue(JsonObjectMember(JsonObjectMember(
      JsonObjectMember(aInput.fCounts, 'ignored'), 'pascal_analyzer'), 'by_rule')))
    .AddPair('verified_rule_aliases', AnalysisPalRegisteredAliases(
      JsonText(JsonObjectMember(JsonObjectMember(aInput.fSeed, 'analyzers'), 'pascal_analyzer'), 'version')))
    .AddPair('ownership', JsonCloneValue(JsonObjectMember(JsonObjectMember(lActionableCounts, 'pascal_analyzer'), 'ownership')))
    .AddPair('warning_ownership', AnalysisOwnershipCounts([lPalWarnings]));
  Result := TJSONObject.Create
    .AddPair('version', TJSONNumber.Create(4))
    .AddPair('created_at', lCreated)
    .AddPair('run_context', JsonCloneValue(aInput.fRunContext))
    .AddPair('summary', JsonCloneValue(aInput.fSummary))
    .AddPair('fixinsight', lFi)
    .AddPair('pascal_analyzer', lPal)
    .AddPair('ownership', JsonCloneValue(JsonObjectMember(lActionableCounts, 'ownership')))
    .AddPair('raw', JsonCloneValue(lRawCounts))
    .AddPair('compatibility', JsonCloneValue(aInput.fCompatibility));
end;

function ResolveBaselinePath(const aOutRoot: string): string;
begin
  Result := Trim(GetEnvironmentVariable('DAK_BASELINE'));
  if Result <> '' then
    Result := TPath.GetFullPath(Result)
  else
    Result := TPath.Combine(aOutRoot, 'baseline.json');
end;

function GateEnabled: Boolean;
begin
  Result := AnalysisTruthyEnvironment('DAK_GATE', False) or AnalysisTruthyEnvironment('DAK_CI', False);
end;

// The preflight reasons that reject a run before any baseline comparison.
function PreflightReasons(const aInput: TAnalysisPolicyInput): TJSONArray;
var
  lItem: TJSONValue;
  lUnknown: Integer;
begin
  Result := TJSONArray.Create;
  if JsonArrayMember(aInput.fResolvedPolicy, 'errors') <> nil then
    for lItem in JsonArrayMember(aInput.fResolvedPolicy, 'errors') do
      Result.Add(lItem.Value);
  lUnknown := StrToIntDef(JsonText(JsonObjectMember(aInput.fCounts, 'unknown'), 'total'), 0);
  if lUnknown > 0 then
    Result.Add(Format('Unknown ownership findings: %d', [lUnknown]));
end;

// _gate_eval: the configured limits, evaluated against the computed delta.
function EvaluateGate(aDelta: TJSONObject; out aReasons: TJSONArray): Boolean;
var
  lBaselineSha, lCurrentSha: string;
  lFi, lPal: TJSONObject;
  lItem: TJSONValue;
  lLimit, lValue: Integer;
  lHasLimit: Boolean;
begin
  aReasons := TJSONArray.Create;
  if JsonArrayMember(JsonObjectMember(aDelta, 'gate'), 'preflight_reasons') <> nil then
    for lItem in JsonArrayMember(JsonObjectMember(aDelta, 'gate'), 'preflight_reasons') do
      aReasons.Add(lItem.Value);
  Result := aReasons.Count = 0;
  lBaselineSha := JsonText(JsonObjectMember(JsonObjectMember(aDelta, 'baseline'), 'compatibility'), 'sha256');
  lCurrentSha := JsonText(JsonObjectMember(JsonObjectMember(aDelta, 'current'), 'compatibility'), 'sha256');
  if lBaselineSha = '' then
  begin
    Result := False;
    aReasons.Add('Baseline compatibility fingerprint is missing');
  end else if (lCurrentSha = '') or (lBaselineSha <> lCurrentSha) then
  begin
    Result := False;
    aReasons.Add(Format('Baseline compatibility mismatch: %s -> %s',
      [IfThen(lBaselineSha = '', '<missing>', lBaselineSha), IfThen(lCurrentSha = '', '<missing>', lCurrentSha)]));
  end;
  lPal := JsonObjectMember(aDelta, 'pascal_analyzer');
  lFi := JsonObjectMember(aDelta, 'fixinsight');
  // These two limits default to zero, so they always apply.
  lValue := DeltaOrZero(lPal, 'new_strong_count');
  lLimit := AnalysisIntegerEnvironment('DAK_MAX_NEW_PAL_STRONG', 0);
  if lValue > lLimit then
  begin
    Result := False;
    aReasons.Add(Format('New PAL strong warnings: %d > %d', [lValue, lLimit]));
  end;
  lValue := DeltaOrZero(lFi, 'new_w_count');
  lLimit := AnalysisIntegerEnvironment('DAK_MAX_NEW_FI_W', 0);
  if lValue > lLimit then
  begin
    Result := False;
    aReasons.Add(Format('New FixInsight W-findings: %d > %d', [lValue, lLimit]));
  end;
  lLimit := AnalysisOptionalIntegerEnvironment('DAK_MAX_PAL_WARNING_INCREASE', lHasLimit);
  if lHasLimit then
  begin
    if not NullableInteger(lPal, 'gated_warnings_delta', lValue) then
      lValue := DeltaOrZero(lPal, 'warnings_delta');
    if lValue > lLimit then
    begin
      Result := False;
      aReasons.Add(Format('PAL warnings increase: %d > %d', [lValue, lLimit]));
    end;
  end;
  lLimit := AnalysisOptionalIntegerEnvironment('DAK_MAX_FI_TOTAL_INCREASE', lHasLimit);
  if lHasLimit then
  begin
    if not NullableInteger(lFi, 'gated_total_delta', lValue) then
      lValue := DeltaOrZero(lFi, 'total_delta');
    if lValue > lLimit then
    begin
      Result := False;
      aReasons.Add(Format('FixInsight findings increase: %d > %d', [lValue, lLimit]));
    end;
  end;
end;

function CloneOrNull(aValue: TJSONValue): TJSONValue;
begin
  if (aValue = nil) or (aValue is TJSONNull) then
    Result := TJSONNull.Create
  else
    Result := JsonCloneValue(aValue);
end;

function OwnershipDelta(aBefore, aAfter: TJSONObject): TJSONObject;
var
  lName: string;
begin
  Result := TJSONObject.Create;
  for lName in cOwnershipNames do
    Result.AddPair(lName, TJSONNumber.Create(OwnershipValue(aAfter, lName) - OwnershipValue(aBefore, lName)));
end;

// Reads a baseline and applies the metadata-only migrations. Finding identities are never rewritten
// unless the outputs still match the baseline run, so an older baseline keeps its verdict.
function LoadAndMigrateBaseline(const aPath: string; const aInput: TAnalysisPolicyInput;
  out aDirty: Boolean): TJSONObject;
var
  g: TGarbos;
  lActionableFi: TList<TJSONObject>;
  lCanTrust: Boolean;
  lContext, lFi, lInferred, lInferredTools, lSummary, lTools: TJSONObject;
  lCurrent, lExpected, lName: string;
  lHashes: TDictionary<string, Boolean>;
  lPair: TJSONPair;
  lRow: TJSONObject;
  lValue: TJSONValue;
  lVersion: Integer;
begin
  aDirty := False;
  lValue := TJSONObject.ParseJSONValue(ReadAnalysisText(aPath), False, False);
  if not (lValue is TJSONObject) then
  begin
    lValue.Free;
    raise EConvertError.CreateFmt('Invalid analysis baseline: %s', [aPath]);
  end;
  Result := TJSONObject(lValue);
  try
    if not NullableInteger(Result, 'version', lVersion) then
      lVersion := 0;
    if lVersion < 2 then
    begin
      JsonPut(Result, 'version', TJSONNumber.Create(2));
      lVersion := 2;
      aDirty := True;
    end;
    lSummary := JsonObjectMember(Result, 'summary');
    lExpected := Trim(JsonText(lSummary, 'timestamp'));
    if lExpected = '' then
      lExpected := Trim(JsonText(Result, 'created_at'));
    lCanTrust := (lExpected <> '') and (JsonText(aInput.fSummary, 'timestamp') = lExpected);
    // Only a run proven to match may upgrade the FixInsight identities to normalized paths.
    if lCanTrust and (lVersion < 3) then
    begin
      lFi := JsonObjectMember(Result, 'fixinsight');
      if lFi <> nil then
      begin
        GC(lActionableFi, ActionableRows(aInput.fFi), g);
        GC(lHashes, TDictionary<string, Boolean>.Create, g);
        for lRow in lActionableFi do
          if JsonText(lRow, 'kind') = 'W' then
            lHashes.AddOrSetValue(FixInsightFingerprint(lRow, True), True);
        JsonPut(lFi, 'w_hashes', SortedStringArray(lHashes));
      end;
      JsonPut(Result, 'version', TJSONNumber.Create(3));
      aDirty := True;
    end;
    lContext := JsonObjectMember(Result, 'run_context');
    if (lContext = nil) or (lContext.Count = 0) then
    begin
      JsonPut(Result, 'run_context', JsonCloneValue(aInput.fRunContext));
      aDirty := True;
      Exit;
    end;
    for lName in ['platform', 'config', 'delphi'] do
      if lContext.GetValue(lName) = nil then
      begin
        JsonPutText(lContext, lName, 'unknown');
        aDirty := True;
      end;
    // Backfill unknown context only when the outputs prove they belong to the baseline run.
    if not lCanTrust then
      Exit;
    lInferred := aInput.fRunContext;
    for lName in ['platform', 'config', 'delphi'] do
    begin
      lCurrent := Trim(JsonText(lContext, lName));
      if lName = 'delphi' then
      begin
        // A concrete BDS version replaces a generic product label; nothing else replaces a value.
        if (lCurrent <> '') and not SameText(lCurrent, 'unknown') and
          not (TRegEx.IsMatch(lCurrent, '^Delphi\s+\d+\b', [roIgnoreCase]) and
          TRegEx.IsMatch(Trim(JsonText(lInferred, lName)), '^\d+\.\d+$')) then
          Continue;
      end else if not MatchText(lCurrent.ToLowerInvariant, ['', 'unknown']) then
        Continue;
      if (Trim(JsonText(lInferred, lName)) <> '') and not SameText(Trim(JsonText(lInferred, lName)), 'unknown') then
      begin
        JsonPutText(lContext, lName, JsonText(lInferred, lName));
        aDirty := True;
      end;
    end;
    lInferredTools := JsonObjectMember(lInferred, 'tools');
    if lInferredTools = nil then
      Exit;
    lTools := JsonObjectMember(lContext, 'tools');
    if lTools = nil then
    begin
      if lInferredTools.Count > 0 then
      begin
        JsonPut(lContext, 'tools', JsonCloneValue(lInferredTools));
        aDirty := True;
      end;
      Exit;
    end;
    for lPair in lInferredTools do
      if lTools.GetValue(lPair.JsonString.Value) = nil then
      begin
        lTools.AddPair(lPair.JsonString.Value, JsonCloneValue(lPair.JsonValue));
        aDirty := True;
      end;
  except
    Result.Free;
    raise;
  end;
end;

// The delta published when no baseline existed: this run becomes the baseline, or is refused.
function BuildCreatedDelta(const aInput: TAnalysisPolicyInput; aSnapshot: TJSONObject;
  const aBaselinePath: string; aCreated, aGateEnabled: Boolean; aPreflight: TJSONArray): TJSONObject;
var
  lAliases, lBefore, lFi, lGate, lPal, lSnapshotFi, lSnapshotPal, lTotals: TJSONObject;
  lCompatibility: TJSONValue;
  lNote: string;
  lRuleCounts: TJSONObject;
begin
  lSnapshotFi := JsonObjectMember(aSnapshot, 'fixinsight');
  lSnapshotPal := JsonObjectMember(aSnapshot, 'pascal_analyzer');
  lTotals := JsonObjectMember(lSnapshotPal, 'totals');
  lAliases := JsonObjectMember(lSnapshotPal, 'verified_rule_aliases');
  lRuleCounts := lSnapshotPal;
  if aCreated then
  begin
    lBefore := JsonCloneValue(JsonObjectMember(aSnapshot, 'ownership')) as TJSONObject;
    lCompatibility := JsonCloneValue(JsonObjectMember(aSnapshot, 'compatibility'));
    lNote := 'Baseline created (no delta).';
  end else begin
    lBefore := EmptyOwnershipCounts;
    lCompatibility := TJSONObject.Create;
    lNote := 'Baseline not created because policy evaluation failed.';
  end;

  lFi := TJSONObject.Create
    .AddPair('total_before', CloneOrNull(lSnapshotFi.GetValue('total')))
    .AddPair('total_after', CloneOrNull(lSnapshotFi.GetValue('total')))
    .AddPair('total_delta', TJSONNumber.Create(0))
    .AddPair('gated_total_delta', TJSONNumber.Create(0))
    .AddPair('top_code_deltas', TJSONArray.Create)
    .AddPair('new_w_count', TJSONNumber.Create(0))
    .AddPair('new_w', TJSONArray.Create);

  lPal := TJSONObject.Create
    .AddPair('warnings_before', CloneOrNull(lTotals.GetValue('warnings')))
    .AddPair('warnings_after', CloneOrNull(lTotals.GetValue('warnings')))
    .AddPair('warnings_delta', TJSONNumber.Create(0))
    .AddPair('gated_warnings_delta', TJSONNumber.Create(0))
    .AddPair('strong_before', CloneOrNull(lTotals.GetValue('strong_warnings')))
    .AddPair('strong_after', CloneOrNull(lTotals.GetValue('strong_warnings')))
    .AddPair('strong_delta', TJSONNumber.Create(0))
    .AddPair('optimizations_before', CloneOrNull(lTotals.GetValue('optimizations')))
    .AddPair('optimizations_after', CloneOrNull(lTotals.GetValue('optimizations')))
    .AddPair('optimizations_delta', TJSONNumber.Create(0))
    .AddPair('total_before', CloneOrNull(lTotals.GetValue('total')))
    .AddPair('total_after', CloneOrNull(lTotals.GetValue('total')))
    .AddPair('total_delta', TJSONNumber.Create(0))
    .AddPair('new_strong_count', TJSONNumber.Create(0))
    .AddPair('new_strong', TJSONArray.Create)
    .AddPair('new_warnings_count', TJSONNumber.Create(0))
    .AddPair('new_warnings_preview', TJSONArray.Create)
    .AddPair('top_section_deltas', TJSONArray.Create)
    .AddPair('rule_count_deltas', RuleCountDelta(JsonObjectMember(lRuleCounts, 'rule_counts'),
      JsonObjectMember(lRuleCounts, 'rule_counts')))
    .AddPair('raw_rule_count_deltas', RuleCountDelta(JsonObjectMember(lRuleCounts, 'raw_rule_counts'),
      JsonObjectMember(lRuleCounts, 'raw_rule_counts')))
    .AddPair('ignored_rule_count_deltas', RuleCountDelta(JsonObjectMember(lRuleCounts, 'ignored_rule_counts'),
      JsonObjectMember(lRuleCounts, 'ignored_rule_counts')))
    .AddPair('verified_rule_aliases', TJSONObject.Create
      .AddPair('before', JsonCloneValue(lAliases))
      .AddPair('after', JsonCloneValue(lAliases)));

  lGate := TJSONObject.Create
    .AddPair('enabled', TJSONBool.Create(aGateEnabled))
    .AddPair('pass', TJSONBool.Create(not (aGateEnabled and (aPreflight.Count > 0))));
  if aGateEnabled then
    lGate.AddPair('reasons', JsonCloneValue(aPreflight))
  else
    lGate.AddPair('reasons', TJSONArray.Create);

  Result := TJSONObject.Create
    .AddPair('title', aInput.fTitle)
    .AddPair('baseline', TJSONObject.Create
      .AddPair('path', aBaselinePath)
      .AddPair('timestamp', JsonText(aSnapshot, 'created_at'))
      .AddPair('created', TJSONBool.Create(aCreated))
      .AddPair('run_context', JsonCloneValue(JsonObjectMember(aSnapshot, 'run_context')))
      .AddPair('compatibility', lCompatibility))
    .AddPair('current', TJSONObject.Create
      .AddPair('summary_path', aInput.fSummaryPath)
      .AddPair('timestamp', JsonText(aSnapshot, 'created_at'))
      .AddPair('run_context', JsonCloneValue(JsonObjectMember(aSnapshot, 'run_context')))
      .AddPair('compatibility', JsonCloneValue(JsonObjectMember(aSnapshot, 'compatibility'))))
    .AddPair('fixinsight', lFi)
    .AddPair('pascal_analyzer', lPal)
    .AddPair('ownership', TJSONObject.Create
      .AddPair('before', lBefore)
      .AddPair('after', JsonCloneValue(JsonObjectMember(aSnapshot, 'ownership')))
      .AddPair('delta', OwnershipDelta(lBefore, JsonObjectMember(aSnapshot, 'ownership'))))
    .AddPair('note', lNote)
    .AddPair('gate', lGate);
end;

function HashSet(aValues: TJSONArray): TDictionary<string, Boolean>;
var
  lItem: TJSONValue;
begin
  Result := TDictionary<string, Boolean>.Create;
  if aValues = nil then
    Exit;
  for lItem in aValues do
    Result.AddOrSetValue(lItem.Value, True);
end;

function Difference(aAfter, aBefore: TDictionary<string, Boolean>): TDictionary<string, Boolean>;
var
  lKey: string;
begin
  Result := TDictionary<string, Boolean>.Create;
  for lKey in aAfter.Keys do
    if not aBefore.ContainsKey(lKey) then
      Result.AddOrSetValue(lKey, True);
end;

function GatedOwnershipSum(aBefore, aAfter: TJSONObject; aGated: TJSONArray): Integer;
var
  lItem: TJSONValue;
begin
  Result := 0;
  if aGated = nil then
    Exit;
  for lItem in aGated do
    Inc(Result, OwnershipValue(aAfter, lItem.Value) - OwnershipValue(aBefore, lItem.Value));
end;

function DifferenceValue(aBefore, aAfter: TJSONObject; const aBeforeName, aAfterName: string): Integer;
var
  lAfter, lBefore: Integer;
begin
  if NullableInteger(aBefore, aBeforeName, lBefore) and NullableInteger(aAfter, aAfterName, lAfter) then
    Result := lAfter - lBefore
  else
    Result := 0;
end;

// The delta published against an existing baseline. Gate path filters and gated ownership apply to
// this run's findings only, so a vendor-heavy baseline still gates our own code.
function BuildComparisonDelta(const aInput: TAnalysisPolicyInput; aSnapshot, aBaseline: TJSONObject;
  const aBaselinePath: string; aGateEnabled: Boolean; aPreflight: TJSONArray): TJSONObject;
var
  g: TGarbos;
  lActionableFi, lActionablePal: TList<TJSONObject>;
  lAfterFi, lAfterStrong, lAfterWarning: TDictionary<string, Boolean>;
  lBaselineFi, lBaselinePal, lBaselineTotals: TJSONObject;
  lBeforeCounts, lAfterCounts: TStringCounts;
  lBeforeFi, lBeforeStrong, lBeforeWarning: TDictionary<string, Boolean>;
  lExclude, lInclude: TArray<string>;
  lFi, lGate, lPal, lPathFilter, lSnapshotFi, lSnapshotPal, lTotals: TJSONObject;
  lGated: TJSONArray;
  lNewFi, lNewStrong, lNewWarning: TDictionary<string, Boolean>;
  lOwnershipBefore: TJSONObject;
  lPathFiltered, lUseNormalized: Boolean;
  lPath, lSeverity: string;
  lReasons: TJSONArray;
  lRow: TJSONObject;
  lVersion: Integer;
begin
  lSnapshotFi := JsonObjectMember(aSnapshot, 'fixinsight');
  lSnapshotPal := JsonObjectMember(aSnapshot, 'pascal_analyzer');
  lTotals := JsonObjectMember(lSnapshotPal, 'totals');
  lBaselineFi := JsonObjectMember(aBaseline, 'fixinsight');
  lBaselinePal := JsonObjectMember(aBaseline, 'pascal_analyzer');
  lBaselineTotals := JsonObjectMember(lBaselinePal, 'totals');
  lOwnershipBefore := JsonObjectMember(aBaseline, 'ownership');
  if lOwnershipBefore = nil then
  begin
    GC(lOwnershipBefore, EmptyOwnershipCounts, g);
  end;
  lGated := JsonArrayMember(aInput.fResolvedPolicy, 'gate_ownership');
  lInclude := SplitSemicolonPatterns(GetEnvironmentVariable('DAK_GATE_INCLUDE_PATHS'));
  lExclude := SplitSemicolonPatterns(GetEnvironmentVariable('DAK_GATE_EXCLUDE_PATHS'));
  lPathFiltered := (Length(lInclude) > 0) or (Length(lExclude) > 0);
  if not NullableInteger(aBaseline, 'version', lVersion) then
    lVersion := 0;
  lUseNormalized := lVersion >= 3;

  GC(lActionableFi, ActionableRows(aInput.fFi), g);
  GC(lActionablePal, ActionableRows(aInput.fPal), g);
  GC(lAfterWarning, TDictionary<string, Boolean>.Create, g);
  GC(lAfterStrong, TDictionary<string, Boolean>.Create, g);
  GC(lAfterFi, TDictionary<string, Boolean>.Create, g);
  for lRow in lActionablePal do
  begin
    if aGateEnabled and not GatedOwnershipMatches(lGated, JsonText(lRow, 'ownership')) then
      Continue;
    if lPathFiltered and not AnalysisTriagePathAllowed(JsonText(lRow, 'path'), lInclude, lExclude) then
      Continue;
    lSeverity := JsonText(lRow, 'severity');
    if lSeverity = 'warning' then
      lAfterWarning.AddOrSetValue(PalFingerprint(lRow), True)
    else if lSeverity = 'strong-warning' then
      lAfterStrong.AddOrSetValue(PalFingerprint(lRow), True);
  end;
  for lRow in lActionableFi do
  begin
    if JsonText(lRow, 'kind') <> 'W' then
      Continue;
    if aGateEnabled and not GatedOwnershipMatches(lGated, JsonText(lRow, 'ownership')) then
      Continue;
    lPath := JsonText(lRow, 'path');
    if lPath = '' then
      lPath := JsonText(lRow, 'file');
    if lPathFiltered and not AnalysisTriagePathAllowed(lPath, lInclude, lExclude) then
      Continue;
    lAfterFi.AddOrSetValue(FixInsightFingerprint(lRow, lUseNormalized), True);
  end;
  GC(lBeforeWarning, HashSet(JsonArrayMember(lBaselinePal, 'warning_hashes')), g);
  GC(lBeforeStrong, HashSet(JsonArrayMember(lBaselinePal, 'strong_hashes')), g);
  GC(lBeforeFi, HashSet(JsonArrayMember(lBaselineFi, 'w_hashes')), g);
  GC(lNewWarning, Difference(lAfterWarning, lBeforeWarning), g);
  GC(lNewStrong, Difference(lAfterStrong, lBeforeStrong), g);
  GC(lNewFi, Difference(lAfterFi, lBeforeFi), g);

  GC(lBeforeCounts, CountsFromObject(JsonObjectMember(lBaselineFi, 'counts_by_code')), g);
  GC(lAfterCounts, CountsFromObject(JsonObjectMember(lSnapshotFi, 'counts_by_code')), g);

  lFi := TJSONObject.Create
    .AddPair('total_before', CloneOrNull(lBaselineFi.GetValue('total')))
    .AddPair('total_after', CloneOrNull(lSnapshotFi.GetValue('total')))
    .AddPair('total_delta', TJSONNumber.Create(DifferenceValue(lBaselineFi, lSnapshotFi, 'total', 'total')))
    .AddPair('gated_total_delta', TJSONNumber.Create(GatedOwnershipSum(
      JsonObjectMember(lBaselineFi, 'ownership'), JsonObjectMember(lSnapshotFi, 'ownership'), lGated)))
    .AddPair('top_code_deltas', NamedDelta(lBeforeCounts, lAfterCounts, 'code'))
    .AddPair('new_w_count', TJSONNumber.Create(lNewFi.Count))
    .AddPair('new_w', SelectNewFixInsightItems(lActionableFi, lNewFi, lUseNormalized))
    ;

  lPal := TJSONObject.Create
    .AddPair('warnings_before', CloneOrNull(lBaselineTotals.GetValue('warnings')))
    .AddPair('warnings_after', CloneOrNull(lTotals.GetValue('warnings')))
    .AddPair('warnings_delta', TJSONNumber.Create(DifferenceValue(lBaselineTotals, lTotals, 'warnings', 'warnings')))
    .AddPair('gated_warnings_delta', TJSONNumber.Create(GatedOwnershipSum(
      JsonObjectMember(lBaselinePal, 'warning_ownership'), JsonObjectMember(lSnapshotPal, 'warning_ownership'), lGated)))
    .AddPair('strong_before', CloneOrNull(lBaselineTotals.GetValue('strong_warnings')))
    .AddPair('strong_after', CloneOrNull(lTotals.GetValue('strong_warnings')))
    .AddPair('strong_delta', TJSONNumber.Create(DifferenceValue(lBaselineTotals, lTotals, 'strong_warnings', 'strong_warnings')))
    .AddPair('optimizations_before', CloneOrNull(lBaselineTotals.GetValue('optimizations')))
    .AddPair('optimizations_after', CloneOrNull(lTotals.GetValue('optimizations')))
    .AddPair('optimizations_delta', TJSONNumber.Create(DifferenceValue(lBaselineTotals, lTotals, 'optimizations', 'optimizations')))
    .AddPair('total_before', CloneOrNull(lBaselineTotals.GetValue('total')))
    .AddPair('total_after', CloneOrNull(lTotals.GetValue('total')))
    .AddPair('total_delta', TJSONNumber.Create(DifferenceValue(lBaselineTotals, lTotals, 'total', 'total')))
    .AddPair('new_strong_count', TJSONNumber.Create(lNewStrong.Count))
    .AddPair('new_strong', SelectNewPalItems(lActionablePal, lNewStrong, 'strong-warning'))
    .AddPair('new_warnings_count', TJSONNumber.Create(lNewWarning.Count))
    .AddPair('new_warnings_preview', LimitedArray(SelectNewPalItems(lActionablePal, lNewWarning, 'warning'), 20))
    .AddPair('top_section_deltas', SectionDelta(JsonArrayMember(lBaselinePal, 'top_warning_sections'),
      JsonArrayMember(lSnapshotPal, 'top_warning_sections')))
    .AddPair('rule_count_deltas', RuleCountDelta(JsonObjectMember(lBaselinePal, 'rule_counts'),
      JsonObjectMember(lSnapshotPal, 'rule_counts')))
    .AddPair('raw_rule_count_deltas', RuleCountDelta(JsonObjectMember(lBaselinePal, 'raw_rule_counts'),
      JsonObjectMember(lSnapshotPal, 'raw_rule_counts')))
    .AddPair('ignored_rule_count_deltas', RuleCountDelta(JsonObjectMember(lBaselinePal, 'ignored_rule_counts'),
      JsonObjectMember(lSnapshotPal, 'ignored_rule_counts')))
    .AddPair('verified_rule_aliases', TJSONObject.Create
      .AddPair('before', JsonCloneValue(JsonObjectMember(lBaselinePal, 'verified_rule_aliases')))
      .AddPair('after', JsonCloneValue(JsonObjectMember(lSnapshotPal, 'verified_rule_aliases'))));

  lGate := TJSONObject.Create
    .AddPair('enabled', TJSONBool.Create(aGateEnabled))
    .AddPair('ownership', JsonCloneValue(lGated))
    .AddPair('preflight_reasons', JsonCloneValue(aPreflight));

  Result := TJSONObject.Create
    .AddPair('title', aInput.fTitle)
    .AddPair('baseline', TJSONObject.Create
      .AddPair('path', aBaselinePath)
      .AddPair('timestamp', BaselineTimestamp(aBaseline))
      .AddPair('run_context', JsonCloneValue(JsonObjectMember(aBaseline, 'run_context')))
      .AddPair('compatibility', JsonCloneValue(JsonObjectMember(aBaseline, 'compatibility'))))
    .AddPair('current', TJSONObject.Create
      .AddPair('summary_path', aInput.fSummaryPath)
      .AddPair('timestamp', JsonText(aSnapshot, 'created_at'))
      .AddPair('run_context', JsonCloneValue(JsonObjectMember(aSnapshot, 'run_context')))
      .AddPair('compatibility', JsonCloneValue(JsonObjectMember(aSnapshot, 'compatibility'))))
    .AddPair('fixinsight', lFi)
    .AddPair('pascal_analyzer', lPal)
    .AddPair('ownership', TJSONObject.Create
      .AddPair('before', JsonCloneValue(lOwnershipBefore))
      .AddPair('after', JsonCloneValue(JsonObjectMember(aSnapshot, 'ownership')))
      .AddPair('delta', OwnershipDelta(lOwnershipBefore, JsonObjectMember(aSnapshot, 'ownership'))))
    .AddPair('gate', lGate);
  if lPathFiltered then
  begin
    lPathFilter := TJSONObject.Create
      .AddPair('include', JsonStringArray(lInclude))
      .AddPair('exclude', JsonStringArray(lExclude));
    lGate.AddPair('path_filter', lPathFilter);
  end;
  if aGateEnabled then
  begin
    lGate.AddPair('pass', TJSONBool.Create(EvaluateGate(Result, lReasons)));
    lGate.AddPair('reasons', lReasons);
  end else begin
    lGate.AddPair('pass', TJSONBool.Create(True));
    lGate.AddPair('reasons', TJSONArray.Create);
  end;
end;

function ApplyAnalysisReportPolicy(const aInput: TAnalysisPolicyInput): TAnalysisPolicyOutcome;
var
  g: TGarbos;
  lBaseline, lDelta: TJSONObject;
  lBaselineDirty, lGateEnabled, lUpdate, lWriteAllowed: Boolean;
  lBaselineMdPath: string;
  lPreflight: TJSONArray;
begin
  Result := Default(TAnalysisPolicyOutcome);
  Result.fBaselinePath := ResolveBaselinePath(aInput.fOutRoot);
  lBaselineMdPath := TPath.ChangeExtension(Result.fBaselinePath, '.md');
  Result.fDeltaPath := TPath.Combine(aInput.fOutRoot, 'delta.json');
  Result.fDeltaMdPath := TPath.Combine(aInput.fOutRoot, 'delta.md');
  lGateEnabled := GateEnabled;
  Result.fPolicyEvaluated := lGateEnabled;
  lUpdate := AnalysisTruthyEnvironment('DAK_UPDATE_BASELINE', False);
  Result.fSnapshot := BuildRunSnapshot(aInput);
  try
    GC(lPreflight, PreflightReasons(aInput), g);
    if not TFile.Exists(Result.fBaselinePath) then
    begin
      // A first run becomes the baseline unless the gate already rejected it.
      Result.fBaselineCreated := not (lGateEnabled and (lPreflight.Count > 0));
      if Result.fBaselineCreated then
      begin
        WriteAnalysisJsonDocument(Result.fBaselinePath, Result.fSnapshot);
        WriteAnalysisText(lBaselineMdPath, RenderBaselineMarkdown(aInput.fTitle, Result.fBaselinePath,
          aInput.fSummaryPath, Result.fSnapshot));
      end;
      GC(lDelta, BuildCreatedDelta(aInput, Result.fSnapshot, Result.fBaselinePath, Result.fBaselineCreated,
        lGateEnabled, lPreflight), g);
      WriteAnalysisJsonDocument(Result.fDeltaPath, lDelta);
      WriteAnalysisText(Result.fDeltaMdPath, RenderDeltaMarkdown(lDelta));
      Result.fGatePass := TJSONBool(JsonObjectMember(lDelta, 'gate').GetValue('pass')).AsBoolean;
      Exit;
    end;
    GC(lBaseline, LoadAndMigrateBaseline(Result.fBaselinePath, aInput, lBaselineDirty), g);
    GC(lDelta, BuildComparisonDelta(aInput, Result.fSnapshot, lBaseline, Result.fBaselinePath,
      lGateEnabled, lPreflight), g);
    WriteAnalysisJsonDocument(Result.fDeltaPath, lDelta);
    WriteAnalysisText(Result.fDeltaMdPath, RenderDeltaMarkdown(lDelta));
    Result.fGatePass := TJSONBool(JsonObjectMember(lDelta, 'gate').GetValue('pass')).AsBoolean;
    // A rejected run never replaces or re-publishes the accepted baseline.
    lWriteAllowed := (not lGateEnabled) or Result.fGatePass;
    Result.fBaselineUpdated := lUpdate and lWriteAllowed;
    if not lWriteAllowed then
      Exit;
    if lUpdate then
      WriteAnalysisJsonDocument(Result.fBaselinePath, Result.fSnapshot)
    else if lBaselineDirty then
      WriteAnalysisJsonDocument(Result.fBaselinePath, lBaseline);
    if lUpdate then
      WriteAnalysisText(lBaselineMdPath, RenderBaselineMarkdown(aInput.fTitle, Result.fBaselinePath,
        aInput.fSummaryPath, Result.fSnapshot))
    else
      WriteAnalysisText(lBaselineMdPath, RenderBaselineMarkdown(aInput.fTitle, Result.fBaselinePath,
        aInput.fSummaryPath, lBaseline));
  except
    Result.fSnapshot.Free;
    Result.fSnapshot := nil;
    raise;
  end;
end;

// _build_history_context: only the identifying context values a trend row needs.
function BuildHistoryContext(aRunContext: TJSONObject): TJSONObject;
var
  lName: string;
  lTools, lToolsOut: TJSONObject;
begin
  Result := TJSONObject.Create;
  for lName in ['platform', 'config', 'delphi'] do
    if JsonText(aRunContext, lName) <> '' then
      Result.AddPair(lName, JsonCloneValue(aRunContext.GetValue(lName)));
  lTools := JsonObjectMember(aRunContext, 'tools');
  lToolsOut := TJSONObject.Create;
  for lName in ['pal_version', 'pal_compiler_target'] do
    if JsonText(lTools, lName) <> '' then
      lToolsOut.AddPair(lName, JsonCloneValue(lTools.GetValue(lName)));
  if lToolsOut.Count > 0 then
    Result.AddPair('tools', lToolsOut)
  else
    lToolsOut.Free;
end;

procedure UpdateAnalysisHistoryAndTrend(const aInput: TAnalysisPolicyInput; aSnapshot: TJSONObject;
  out aHistoryPath, aTrendPath: string);
var
  g: TGarbos;
  lEntries: TJSONArray;
  lEntry, lFi, lGit, lPal, lRow, lTotals: TJSONObject;
  lLast, lSummaryTimestamp: string;
  lLines: TList<string>;
  lRecent: TList<TJSONObject>;
  lShow, i: Integer;
  lPrevFi, lPrevOptimizations, lPrevStrong, lPrevTotal, lPrevWarnings: Integer;
  lHasPrevFi, lHasPrevOptimizations, lHasPrevStrong, lHasPrevTotal, lHasPrevWarnings: Boolean;

  function Cell(aObject: TJSONObject; const aName: string; out aValue: Integer; out aHasValue: Boolean): string;
  begin
    aHasValue := NullableInteger(aObject, aName, aValue);
    if aHasValue then
      Result := IntToStr(aValue)
    else
      Result := '?';
  end;

  function DeltaCell(aValue: Integer; aHasValue: Boolean; aPrevious: Integer; aHasPrevious: Boolean): string;
  begin
    if not (aHasValue and aHasPrevious) then
      Exit('');
    if aValue = aPrevious then
      Exit('0');
    Result := SignedText(aValue - aPrevious);
  end;

var
  lFiText, lOptimizationsText, lStrongText, lTotalText, lWarningsText: string;
  lFiValue, lOptimizationsValue, lStrongValue, lTotalValue, lWarningsValue: Integer;
  lHasFi, lHasOptimizations, lHasStrong, lHasTotal, lHasWarnings: Boolean;
begin
  aHistoryPath := TPath.Combine(aInput.fOutRoot, 'history.jsonl');
  aTrendPath := TPath.Combine(aInput.fOutRoot, 'trend.md');
  lSummaryTimestamp := Trim(JsonText(aInput.fSummary, 'timestamp'));
  if lSummaryTimestamp = '' then
    lSummaryTimestamp := Trim(JsonText(aSnapshot, 'created_at'));
  // A malformed history row is skipped rather than failing the run, as the reference does.
  if TFile.Exists(aHistoryPath) then
    GC(lEntries, LoadAnalysisHistoryRows(aHistoryPath), g)
  else
    GC(lEntries, TJSONArray.Create, g);
  lLast := '';
  if lEntries.Count > 0 then
    lLast := Trim(JsonText(TJSONObject(lEntries.Items[lEntries.Count - 1]), 'summary_timestamp'));
  // Re-running the postprocessor on the same outputs must not duplicate a history row.
  if (lSummaryTimestamp = '') or (lSummaryTimestamp <> lLast) then
  begin
    lFi := JsonObjectMember(aSnapshot, 'fixinsight');
    lPal := JsonObjectMember(aSnapshot, 'pascal_analyzer');
    lEntry := TJSONObject.Create
      .AddPair('timestamp', AnalysisUtcNowIso)
      .AddPair('summary_timestamp', lSummaryTimestamp)
      .AddPair('project', aInput.fTitle)
      .AddPair('context', BuildHistoryContext(JsonObjectMember(aSnapshot, 'run_context')))
      .AddPair('fixinsight', TJSONObject.Create
        .AddPair('total', CloneOrNull(lFi.GetValue('total')))
        .AddPair('counts_by_code', JsonCloneValue(JsonObjectMember(lFi, 'counts_by_code'))))
      .AddPair('pascal_analyzer', TJSONObject.Create
        .AddPair('totals', JsonCloneValue(JsonObjectMember(lPal, 'totals'))))
      .AddPair('ownership', JsonCloneValue(JsonObjectMember(aSnapshot, 'ownership')))
      .AddPair('raw', JsonCloneValue(JsonObjectMember(aSnapshot, 'raw')));
    lGit := CaptureAnalysisHistoryGit(aInput.fRepoRoot, aInput.fOutRoot);
    if lGit.Count > 0 then
      lEntry.AddPair('git', lGit)
    else
      lGit.Free;
    lEntries.AddElement(lEntry);
    // Keep the history bounded so it cannot grow without limit.
    while lEntries.Count > 200 do
      lEntries.Remove(0).Free;
    WriteAnalysisJsonLines(aHistoryPath, lEntries);
  end;
  lShow := AnalysisIntegerEnvironment('DAK_TREND_N', 20);
  if lShow = 0 then
    lShow := 20;
  GC(lRecent, TList<TJSONObject>.Create, g);
  for i := Max(0, lEntries.Count - lShow) to lEntries.Count - 1 do
    lRecent.Add(TJSONObject(lEntries.Items[i]));
  GC(lLines, TList<string>.Create, g);
  lLines.Add('# ' + aInput.fTitle + ' trend');
  lLines.Add('');
  lLines.Add('- Updated: ' + AnalysisUtcNowIso);
  lLines.Add(Format('- Entries: %d (showing last %d)', [lEntries.Count, lRecent.Count]));
  if lRecent.Count > 0 then
  begin
    lLines.Add('- Latest ownership: ' + AnalysisOwnershipText(JsonObjectMember(lRecent.Last, 'ownership')));
    lLines.Add('- Latest raw ownership: ' + AnalysisOwnershipText(
      JsonObjectMember(JsonObjectMember(lRecent.Last, 'raw'), 'ownership')));
  end;
  lLines.Add('');
  lLines.Add('| Summary timestamp | FI total | FI ' + #$0394 + ' | PAL strong | ' + #$0394 +
    ' | PAL warnings | ' + #$0394 + ' | PAL optimizations | ' + #$0394 + ' | PAL total | ' + #$0394 + ' |');
  lLines.Add('| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  lHasPrevFi := False;
  lHasPrevStrong := False;
  lHasPrevWarnings := False;
  lHasPrevOptimizations := False;
  lHasPrevTotal := False;
  lPrevFi := 0;
  lPrevStrong := 0;
  lPrevWarnings := 0;
  lPrevOptimizations := 0;
  lPrevTotal := 0;
  for lRow in lRecent do
  begin
    lLast := Trim(JsonText(lRow, 'summary_timestamp'));
    if lLast = '' then
      lLast := Trim(JsonText(lRow, 'timestamp'));
    if lLast = '' then
      lLast := '?';
    lFi := JsonObjectMember(lRow, 'fixinsight');
    lPal := JsonObjectMember(lRow, 'pascal_analyzer');
    lTotals := JsonObjectMember(lPal, 'totals');
    lFiText := Cell(lFi, 'total', lFiValue, lHasFi);
    lStrongText := Cell(lTotals, 'strong_warnings', lStrongValue, lHasStrong);
    lWarningsText := Cell(lTotals, 'warnings', lWarningsValue, lHasWarnings);
    lOptimizationsText := Cell(lTotals, 'optimizations', lOptimizationsValue, lHasOptimizations);
    lTotalText := Cell(lTotals, 'total', lTotalValue, lHasTotal);
    lLines.Add('| ' + String.Join(' | ', [lLast, lFiText, DeltaCell(lFiValue, lHasFi, lPrevFi, lHasPrevFi),
      lStrongText, DeltaCell(lStrongValue, lHasStrong, lPrevStrong, lHasPrevStrong),
      lWarningsText, DeltaCell(lWarningsValue, lHasWarnings, lPrevWarnings, lHasPrevWarnings),
      lOptimizationsText, DeltaCell(lOptimizationsValue, lHasOptimizations, lPrevOptimizations, lHasPrevOptimizations),
      lTotalText, DeltaCell(lTotalValue, lHasTotal, lPrevTotal, lHasPrevTotal)]) + ' |');
    if lHasFi then
    begin
      lPrevFi := lFiValue;
      lHasPrevFi := True;
    end;
    if lHasStrong then
    begin
      lPrevStrong := lStrongValue;
      lHasPrevStrong := True;
    end;
    if lHasWarnings then
    begin
      lPrevWarnings := lWarningsValue;
      lHasPrevWarnings := True;
    end;
    if lHasOptimizations then
    begin
      lPrevOptimizations := lOptimizationsValue;
      lHasPrevOptimizations := True;
    end;
    if lHasTotal then
    begin
      lPrevTotal := lTotalValue;
      lHasPrevTotal := True;
    end;
  end;
  WriteAnalysisText(aTrendPath, String.Join(#10, lLines.ToArray).TrimRight + #10);
end;

end.
