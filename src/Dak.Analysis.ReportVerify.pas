unit Dak.Analysis.ReportVerify;

{$SCOPEDENUMS ON}

interface

uses
  System.JSON;

// verify_outputs for the report-processing artifacts: raises EConvertError with the reference's
// message when an artifact is missing, malformed, stale or contradictory. Returns the caller-owned
// actionable ownership counts. Policy artifacts (baseline, delta, history, trend) are verified by
// the policy stage (T-325). Nothing under the output directory is written.
function VerifyAnalysisReport(const aOutRoot: string): TJSONObject;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.RegularExpressions, System.StrUtils,
  System.SysUtils,
  AutoFree,
  Dak.Analysis.Findings, Dak.Analysis.JsonText, Dak.Analysis.Ownership, Dak.Analysis.OwnershipContext,
  Dak.Analysis.Projections, Dak.Analysis.ReportBundle, Dak.Analysis.ReportWriters, Dak.Analysis.Text;

type
  // The published views that must all repeat the same actionable ownership counts.
  TOwnershipLine = record
    fArtifact: string;
    fPrefix: string;
    fMessage: string;
  end;

const
  cAnalyzers: array[0..1] of string = ('fixinsight', 'pascal_analyzer');
  cLabels: array[0..1] of string = ('FixInsight', 'Pascal Analyzer');
  cOwnershipLines: array[0..3] of TOwnershipLine = (
    (fArtifact: 'summary.md'; fPrefix: '- '; fMessage: 'summary.md ownership mismatch'),
    (fArtifact: 'delta.md'; fPrefix: '- After: '; fMessage: 'delta.md After ownership mismatch'),
    (fArtifact: 'trend.md'; fPrefix: '- Latest ownership: '; fMessage: 'trend.md ownership mismatch'),
    (fArtifact: 'triage.md'; fPrefix: '- Ownership: '; fMessage: 'triage.md ownership mismatch'));

function LoadJsonObject(const aPath, aLabel: string): TJSONObject;
var
  lValue: TJSONValue;
begin
  if not TFile.Exists(aPath) then
    raise EConvertError.CreateFmt('%s is missing: %s', [aLabel, aPath]);
  lValue := TJSONObject.ParseJSONValue(ReadAnalysisText(aPath), False, False);
  if not (lValue is TJSONObject) then
  begin
    lValue.Free;
    raise EConvertError.CreateFmt('%s is malformed: %s', [aLabel, aPath]);
  end;
  Result := TJSONObject(lValue);
end;

function TriageWithoutTimestamp(const aText: string): string;
var
  lLine: string;
  lLines: TList<string>;
begin
  lLines := TList<string>.Create;
  try
    for lLine in aText.Replace(#13#10, #10).Split([#10]) do
      if not lLine.StartsWith('- Timestamp: ') then
        lLines.Add(lLine);
    Result := String.Join(#10, lLines.ToArray).TrimRight;
  finally
    lLines.Free;
  end;
end;

// The baseline's counts for one rule projection, or nil when there is no baseline to compare.
function BaselineCounts(aBaseline, aBaselinePal: TJSONObject; const aName: string): TJSONObject;
begin
  Result := nil;
  if aBaseline <> nil then
    Result := JsonObjectMember(aBaselinePal, aName);
end;

// The four PAL totals a history row repeats, taken from the actionable counts.
function PalTotalsOf(aPalCounts: TJSONObject): TJSONObject;
var
  lName: string;
begin
  Result := TJSONObject.Create;
  for lName in ['warnings', 'strong_warnings', 'optimizations', 'total'] do
    Result.AddPair(lName, JsonCloneValue(aPalCounts.GetValue(lName)));
end;

// The last trend row must repeat this run's published totals.
procedure VerifyTrendTotals(const aTrendText: string; aFi, aPal: TJSONObject);
var
  lCells: TArray<string>;
  lExpected: TArray<string>;
  lLastRow, lLine: string;
  i: Integer;
const
  cColumns: array[0..4] of Integer = (1, 3, 5, 7, 9);
begin
  lLastRow := '';
  for lLine in aTrendText.Replace(#13#10, #10).Split([#10]) do
    if lLine.StartsWith('| ') and not lLine.StartsWith('| ---') then
      lLastRow := lLine;
  if lLastRow = '' then
    raise EConvertError.Create('trend.md latest totals are missing');
  lCells := lLastRow.Trim.Trim(['|']).Split(['|']);
  for i := 0 to High(lCells) do
    lCells[i] := lCells[i].Trim;
  lExpected := [JsonText(aFi, 'total'), JsonText(aPal, 'strong_warnings'), JsonText(aPal, 'warnings'),
    JsonText(aPal, 'optimizations'), JsonText(aPal, 'total')];
  for i := 0 to High(cColumns) do
    if (cColumns[i] > High(lCells)) or (lCells[cColumns[i]] <> lExpected[i]) then
      raise EConvertError.CreateFmt('trend.md total mismatch: expected=%s', [String.Join(', ', lExpected)]);
end;

// The nonzero counts only: Python compares the dictionaries the delta rows reconstruct.
function NonZeroCounts(aCounts: TJSONObject): TJSONObject;
var
  lPair: TJSONPair;
  lValue: Integer;
begin
  Result := TJSONObject.Create;
  if aCounts = nil then
    Exit;
  for lPair in aCounts do
    if TryStrToInt(lPair.JsonValue.Value, lValue) and (lValue <> 0) then
      Result.AddPair(lPair.JsonString.Value, TJSONNumber.Create(lValue));
end;

// A rule-count delta row set must be internally consistent and reconstruct the counts it claims.
procedure VerifyRuleDelta(aDeltaPal: TJSONObject; const aField: string; aExpectedBefore, aExpectedAfter: TJSONObject);
var
  g: TGarbos;
  lAfter, lBefore, lExpectedAfter, lExpectedBefore, lRow: TJSONObject;
  lAfterCount, lBeforeCount: Integer;
  lItem: TJSONValue;
  lRows: TJSONArray;
  lRule: string;
  lSeen: TDictionary<string, Boolean>;
begin
  lRows := JsonArrayMember(aDeltaPal, aField);
  if lRows = nil then
    raise EConvertError.CreateFmt('delta.json %s is missing', [aField]);
  GC(lBefore, TJSONObject.Create, g);
  GC(lAfter, TJSONObject.Create, g);
  GC(lSeen, TDictionary<string, Boolean>.Create, g);
  for lItem in lRows do
  begin
    if not (lItem is TJSONObject) then
      raise EConvertError.CreateFmt('delta.json %s is invalid', [aField]);
    lRow := TJSONObject(lItem);
    lRule := JsonText(lRow, 'rule');
    if (lRule = '') or lSeen.ContainsKey(lRule) then
      raise EConvertError.CreateFmt('delta.json %s is invalid', [aField]);
    lSeen.Add(lRule, True);
    lBeforeCount := StrToIntDef(JsonText(lRow, 'before'), 0);
    lAfterCount := StrToIntDef(JsonText(lRow, 'after'), 0);
    if StrToIntDef(JsonText(lRow, 'delta'), 0) <> lAfterCount - lBeforeCount then
      raise EConvertError.CreateFmt('delta.json %s is invalid', [aField]);
    if lBeforeCount <> 0 then
      lBefore.AddPair(lRule, TJSONNumber.Create(lBeforeCount));
    if lAfterCount <> 0 then
      lAfter.AddPair(lRule, TJSONNumber.Create(lAfterCount));
  end;
  GC(lExpectedAfter, NonZeroCounts(aExpectedAfter), g);
  if not AnalysisJsonEquivalent(lAfter, lExpectedAfter) then
    raise EConvertError.CreateFmt('delta.json %s evidence mismatch', [aField]);
  if aExpectedBefore = nil then
    Exit;
  GC(lExpectedBefore, NonZeroCounts(aExpectedBefore), g);
  if not AnalysisJsonEquivalent(lBefore, lExpectedBefore) then
    raise EConvertError.CreateFmt('delta.json %s baseline evidence mismatch', [aField]);
end;

// triage.md must be what the recorded active policy regenerates from the normalized rows.
procedure VerifyTriageEvidence(const aOutRoot: string; aSummaryJson: TJSONObject; aFi, aPal: TJSONArray);
var
  lActive, lTriage: TJSONObject;
  lActual, lFirstLine: string;
  lMatch: TMatch;
  lPolicy: TAnalysisTriagePolicy;
  lTop: Integer;
begin
  lActual := ReadAnalysisText(TPath.Combine(aOutRoot, 'triage.md'));
  lFirstLine := lActual.Replace(#13#10, #10).Split([#10])[0];
  lMatch := TRegEx.Match(lFirstLine, '^# (.+) triage$');
  if not lMatch.Success then
    raise EConvertError.Create('triage.md evidence mismatch');
  lActive := JsonObjectMember(JsonObjectMember(aSummaryJson, 'policy'), 'active');
  lTriage := JsonObjectMember(lActive, 'triage');
  if lTriage = nil then
    raise EConvertError.Create('summary.json active triage policy is missing');
  if not ((lTriage.GetValue('top') is TJSONNumber) and TryStrToInt(lTriage.GetValue('top').Value, lTop) and (lTop > 0)) then
    raise EConvertError.Create('summary.json active triage policy is invalid');
  lPolicy.fTop := lTop;
  lPolicy.fIncludePaths := JsonText(lTriage, 'include_paths');
  lPolicy.fExcludePaths := JsonText(lTriage, 'exclude_paths');
  lPolicy.fPalIncludeCallTree := (lTriage.GetValue('pal_include_call_tree') is TJSONBool) and
    TJSONBool(lTriage.GetValue('pal_include_call_tree')).AsBoolean;
  lPolicy.fSnippets := False;
  if TriageWithoutTimestamp(lActual) <>
    TriageWithoutTimestamp(RenderAnalysisTriage(lMatch.Groups[1].Value, aFi, aPal, lPolicy)) then
    raise EConvertError.Create('triage.md evidence mismatch');
end;

type
  // Compares what a renderer writes against a file as it is produced, so neither the rendering
  // nor the published artifact is ever held whole in memory.
  TFileCompareStream = class(TStream)
  private
    fBuffer: TBytes;
    fFile: TFileStream;
    fMatched: Boolean;
    fPosition: Int64;
  public
    constructor Create(const aPath: string);
    destructor Destroy; override;
    function Write(const aBuffer; aCount: Longint): Longint; override;
    // True when the rendering matched the file exactly, with nothing left over on either side.
    function Complete: Boolean;
  end;

constructor TFileCompareStream.Create(const aPath: string);
begin
  inherited Create;
  fFile := TFileStream.Create(aPath, fmOpenRead or fmShareDenyWrite);
  fMatched := True;
end;

destructor TFileCompareStream.Destroy;
begin
  fFile.Free;
  inherited;
end;

function TFileCompareStream.Write(const aBuffer; aCount: Longint): Longint;
begin
  Result := aCount;
  Inc(fPosition, aCount);
  if not fMatched then
    Exit;
  if Length(fBuffer) < aCount then
    SetLength(fBuffer, aCount);
  if fFile.Read(fBuffer[0], aCount) <> aCount then
  begin
    fMatched := False;
    Exit;
  end;
  fMatched := CompareMem(@aBuffer, @fBuffer[0], aCount);
end;

function TFileCompareStream.Complete: Boolean;
begin
  Result := fMatched and (fPosition = fFile.Size);
end;

// The published SARIF must be what the normalized rows regenerate, and its results must carry the
// rows' ownership in row order (FixInsight rows first, then Pascal Analyzer rows).
procedure VerifySarifEvidence(const aOutRoot, aName: string; aFi, aPal: TJSONArray; aFull: Boolean;
  aOwnership: TJSONObject);
var
  g: TGarbos;
  lActual, lExpected, lProperties, lPublished, lPublishedCounts: TJSONObject;
  lActualHash, lExpectedHash, lPublishedOwnership: string;
  lCompare: TFileCompareStream;
  lExpectedRows, lPublishedRows: TList<TJSONObject>;
  lIndex: Integer;
  lItem, lResult, lRun: TJSONValue;
  lMismatch, lOwnershipMissing: Boolean;
  lPath: string;
  lRows: TJSONArray;
begin
  lPath := TPath.Combine(aOutRoot, aName);
  if not TFile.Exists(lPath) then
    raise EConvertError.CreateFmt('%s is missing: %s', [aName, lPath]);
  GC(lExpectedRows, TList<TJSONObject>.Create, g);
  for lRows in [aFi, aPal] do
    for lItem in lRows do
      if aFull or AnalysisRecordIsActionable(TJSONObject(lItem)) then
        lExpectedRows.Add(TJSONObject(lItem));
  // Our own publication is byte-identical to a fresh rendering; then the ownership records are the
  // rows' by construction and no document needs to be parsed.
  lExpected := BuildAnalysisSarif(aFi, aPal, aFull);
  try
    lCompare := TFileCompareStream.Create(lPath);
    try
      TPythonJson.WriteDocument(lExpected, lCompare);
      if lCompare.Complete then
        Exit;
    finally
      lCompare.Free;
    end;
  finally
    lExpected.Free;
  end;
  // Otherwise the reference's semantic comparison: only one large document is resident at a time,
  // the published one being reduced to its canonical fingerprint and ownership sequence first.
  lActual := LoadJsonObject(lPath, aName);
  GC(lPublishedRows, TObjectList<TJSONObject>.Create(True), g);
  try
    lIndex := 0;
    lMismatch := False;
    lOwnershipMissing := False;
    if JsonArrayMember(lActual, 'runs') <> nil then
      for lRun in JsonArrayMember(lActual, 'runs') do
        if (lRun is TJSONObject) and (JsonArrayMember(TJSONObject(lRun), 'results') <> nil) then
          for lResult in JsonArrayMember(TJSONObject(lRun), 'results') do
          begin
            lProperties := JsonObjectMember(TJSONObject(lResult), 'properties');
            if (JsonText(lProperties, 'ownership') = '') or (lProperties = nil) or
              (lProperties.GetValue('ownership_root') = nil) then
              lOwnershipMissing := True
            else if (lIndex < lExpectedRows.Count) and
              ((JsonText(lProperties, 'ownership') <> JsonText(lExpectedRows[lIndex], 'ownership')) or
              not AnalysisJsonEquivalent(lProperties.GetValue('ownership_root'),
                lExpectedRows[lIndex].GetValue('ownership_root'))) then
              lMismatch := True;
            // The reported "actual" is the published document's own ownership breakdown.
            lPublished := TJSONObject.Create;
            lPublished.AddPair('ownership', JsonCloneValue(lProperties.GetValue('ownership')));
            lPublishedRows.Add(lPublished);
            Inc(lIndex);
          end;
    lActualHash := TPythonJson.CompactSha256(lActual);
  finally
    lActual.Free;
  end;
  lExpected := BuildAnalysisSarif(aFi, aPal, aFull);
  try
    lExpectedHash := TPythonJson.CompactSha256(lExpected);
  finally
    lExpected.Free;
  end;
  if lActualHash <> lExpectedHash then
    raise EConvertError.CreateFmt('%s evidence mismatch', [aName]);
  if lOwnershipMissing and not aFull then
    raise EConvertError.CreateFmt('%s ownership is missing', [aName]);
  if lMismatch or (lIndex <> lExpectedRows.Count) then
  begin
    if aFull then
      raise EConvertError.CreateFmt('%s raw evidence mismatch: expected=%d, actual=%d',
        [aName, lExpectedRows.Count, lIndex]);
    lPublishedCounts := AnalysisOwnershipCounts([lPublishedRows]);
    try
      lPublishedOwnership := TPythonJson.Compact(lPublishedCounts);
    finally
      lPublishedCounts.Free;
    end;
    raise EConvertError.CreateFmt('%s ownership mismatch: expected=%s, actual=%s',
      [aName, TPythonJson.Compact(aOwnership), lPublishedOwnership]);
  end;
end;

function VerifyAnalysisReport(const aOutRoot: string): TJSONObject;
var
  g: TGarbos;
  lActive, lAliases, lAnalyzer, lAnalyzers, lCompatibility, lCounts, lExpectedCompatibility, lExpectedCounts,
    lExpectedProjections, lPolicy, lResolved, lRow, lSummaryJson, lSummaryMarkdown: TJSONObject;
  lBaselineJson, lBaselinePal, lDelta, lDeltaAliases, lDeltaFi, lDeltaPal, lGate, lHistoryRow,
    lProjectionPal: TJSONObject;
  lBaselinePath, lDeltaText, lTrendText: string;
  lHistory: TJSONArray;
  lFi, lOrigins, lPal, lRows: TJSONArray;
  lBoundaries: TAnalysisOwnershipContext;
  lFiPath, lLine, lOutRoot, lPalPath, lPalVersion, lText: string;
  lItem: TJSONValue;
  lActionable, lTotal: Integer;
  i: Integer;
  lFound: Boolean;
begin
  lOutRoot := ExcludeTrailingPathDelimiter(TPath.GetFullPath(aOutRoot));
  lFiPath := TPath.Combine(lOutRoot, 'fixinsight\fi-findings.jsonl');
  lPalPath := TPath.Combine(lOutRoot, 'pascal-analyzer\pal-findings.jsonl');
  GC(lSummaryJson, LoadJsonObject(TPath.Combine(lOutRoot, 'summary.json'), 'summary.json'), g);
  lAnalyzers := JsonObjectMember(lSummaryJson, 'analyzers');
  for i := 0 to High(cAnalyzers) do
  begin
    lAnalyzer := JsonObjectMember(lAnalyzers, cAnalyzers[i]);
    if (lAnalyzer <> nil) and (lAnalyzer.GetValue('requested') is TJSONBool) and
      TJSONBool(lAnalyzer.GetValue('requested')).AsBoolean and (JsonText(lAnalyzer, 'status') = 'complete') then
    begin
      if (i = 0) and not TFile.Exists(lFiPath) then
        raise EConvertError.CreateFmt('requested %s JSONL is missing: %s', [cLabels[i], lFiPath]);
      if (i = 1) and not TFile.Exists(lPalPath) then
        raise EConvertError.CreateFmt('requested %s JSONL is missing: %s', [cLabels[i], lPalPath]);
    end;
  end;
  // iter_records: a missing stream contributes no rows.
  if TFile.Exists(lFiPath) then
    GC(lFi, LoadAnalysisJsonLines(lFiPath), g)
  else
    GC(lFi, TJSONArray.Create, g);
  if TFile.Exists(lPalPath) then
    GC(lPal, LoadAnalysisJsonLines(lPalPath), g)
  else
    GC(lPal, TJSONArray.Create, g);
  lActionable := 0;
  for lRows in [lFi, lPal] do
    for lItem in lRows do
    begin
      if TJSONObject(lItem).GetValue('ownership') = nil then
        raise EConvertError.Create('normalized JSONL ownership is missing');
      if AnalysisRecordIsActionable(TJSONObject(lItem)) then
        Inc(lActionable);
    end;
  GC(lSummaryMarkdown, ParseAnalysisSummaryMarkdown(TPath.Combine(lOutRoot, 'summary.md')), g);
  GC(lExpectedProjections, AnalysisReportProjections(lSummaryMarkdown, lFi, lPal), g);
  GC(lExpectedCounts, AnalysisActionableCounts(lSummaryMarkdown, lFi, lPal), g);
  Result := JsonCloneValue(JsonObjectMember(lExpectedCounts, 'ownership')) as TJSONObject;
  try
    lCounts := JsonObjectMember(lSummaryJson, 'counts');
    if not AnalysisJsonEquivalent(lCounts, lExpectedProjections) then
      raise EConvertError.CreateFmt('summary.json projection mismatch: expected=%s, actual=%s',
        [TPythonJson.Compact(lExpectedProjections), IfThen(lCounts = nil, 'None', TPythonJson.Compact(lCounts))]);
    lTotal := StrToIntDef(JsonText(JsonObjectMember(lCounts, 'actionable'), 'total'), -1);
    if lTotal <> lActionable then
      raise EConvertError.CreateFmt('summary.json total mismatch: expected=%d, actual=%d', [lActionable, lTotal]);
    GC(lDelta, LoadJsonObject(TPath.Combine(lOutRoot, 'delta.json'), 'delta.json'), g);
    lDeltaPal := JsonObjectMember(lDelta, 'pascal_analyzer');
    lDeltaFi := JsonObjectMember(lDelta, 'fixinsight');
    lPolicy := JsonObjectMember(lSummaryJson, 'policy');
    GC(lResolved, ResolveAnalysisPolicy(lSummaryJson), g);
    lActive := JsonObjectMember(lPolicy, 'active');
    if not AnalysisJsonEquivalent(JsonArrayMember(lActive, 'pal_ignore_rules'),
      JsonArrayMember(lResolved, 'pal_ignore_rules')) then
      raise EConvertError.Create('summary.json active PAL ignore policy mismatch');
    if JsonArrayMember(lResolved, 'pal_ignore_rules').Count > 0 then
    begin
      lOrigins := JsonArrayMember(JsonObjectMember(lPolicy, 'origins'), 'pal_ignore_rules');
      lFound := (lOrigins <> nil) and (lOrigins.Count > 0);
      if lFound then
        for lItem in lOrigins do
          if not ((lItem is TJSONString) and not (lItem is TJSONNumber) and (Trim(lItem.Value) <> '')) then
            lFound := False;
      if not lFound then
        raise EConvertError.Create('summary.json PAL ignore provenance is missing');
    end;
    lAnalyzer := JsonObjectMember(lAnalyzers, 'pascal_analyzer');
    lPalVersion := JsonText(lAnalyzer, 'version');
    for lItem in lPal do
    begin
      lRow := TJSONObject(lItem);
      if (JsonText(lRow, 'normalized_rule') <> AnalysisNormalizedRuleId(lRow)) or
        (Trim(JsonText(lRow, 'pal_code')) <> AnalysisPalNativeCode(lRow, lPalVersion)) then
        raise EConvertError.Create('normalized PAL identity mismatch');
    end;
    GC(lAliases, AnalysisPalRegisteredAliases(lPalVersion), g);
    if not AnalysisJsonEquivalent(JsonObjectMember(lAnalyzer, 'verified_rule_aliases'), lAliases) then
      raise EConvertError.Create('summary.json verified PAL alias mismatch');
    lDeltaAliases := JsonObjectMember(lDeltaPal, 'verified_rule_aliases');
    if not AnalysisJsonEquivalent(JsonObjectMember(lDeltaAliases, 'after'), lAliases) then
      raise EConvertError.Create('delta.json verified PAL alias mismatch');
    // The delta names the baseline it compared against; that file must still be there.
    lBaselineJson := nil;
    lBaselinePath := JsonText(JsonObjectMember(lDelta, 'baseline'), 'path');
    if lBaselinePath <> '' then
    begin
      if not TPath.IsPathRooted(lBaselinePath) then
        lBaselinePath := TPath.Combine(lOutRoot, lBaselinePath);
      if not TFile.Exists(lBaselinePath) then
        raise EConvertError.CreateFmt('referenced baseline is missing: %s', [lBaselinePath]);
      GC(lBaselineJson, LoadJsonObject(lBaselinePath, 'baseline.json'), g);
    end;
    lBaselinePal := JsonObjectMember(lBaselineJson, 'pascal_analyzer');
    if (lBaselineJson <> nil) and not AnalysisJsonEquivalent(JsonObjectMember(lDeltaAliases, 'before'),
      JsonObjectMember(lBaselinePal, 'verified_rule_aliases')) then
      raise EConvertError.Create('delta.json verified PAL alias baseline mismatch');
    lProjectionPal := JsonObjectMember(JsonObjectMember(lExpectedProjections, 'actionable'), 'pascal_analyzer');
    VerifyRuleDelta(lDeltaPal, 'rule_count_deltas',
      BaselineCounts(lBaselineJson, lBaselinePal, 'rule_counts'),
      JsonObjectMember(lProjectionPal, 'by_rule'));
    lProjectionPal := JsonObjectMember(JsonObjectMember(lExpectedProjections, 'raw'), 'pascal_analyzer');
    VerifyRuleDelta(lDeltaPal, 'raw_rule_count_deltas',
      BaselineCounts(lBaselineJson, lBaselinePal, 'raw_rule_counts'),
      JsonObjectMember(lProjectionPal, 'by_rule'));
    lProjectionPal := JsonObjectMember(JsonObjectMember(lExpectedProjections, 'ignored'), 'pascal_analyzer');
    VerifyRuleDelta(lDeltaPal, 'ignored_rule_count_deltas',
      BaselineCounts(lBaselineJson, lBaselinePal, 'ignored_rule_counts'),
      JsonObjectMember(lProjectionPal, 'by_rule'));
    // Like the reference, the fingerprint is recomputed from the recorded seed alone; no inventory runs.
    lBoundaries := BuildAnalysisPolicyBoundaries(lSummaryJson);
    GC(lExpectedCompatibility, AnalysisCompatibilitySnapshot(lSummaryJson, lBoundaries), g);
    lCompatibility := JsonObjectMember(lSummaryJson, 'compatibility');
    if (lCompatibility = nil) or (JsonText(lCompatibility, 'sha256') <> JsonText(lExpectedCompatibility, 'sha256')) then
      raise EConvertError.Create('summary.json compatibility fingerprint mismatch');
    if JsonText(JsonObjectMember(JsonObjectMember(lDelta, 'current'), 'compatibility'), 'sha256') <>
      JsonText(lCompatibility, 'sha256') then
      raise EConvertError.Create('delta.json current compatibility mismatch');
    lGate := JsonObjectMember(lDelta, 'gate');
    // A gate may only pass against a baseline recorded under the same analysis context.
    if (lGate <> nil) and (lGate.GetValue('enabled') is TJSONBool) and TJSONBool(lGate.GetValue('enabled')).AsBoolean and
      (lGate.GetValue('pass') is TJSONBool) and TJSONBool(lGate.GetValue('pass')).AsBoolean then
    begin
      if JsonText(JsonObjectMember(JsonObjectMember(lDelta, 'baseline'), 'compatibility'), 'sha256') <>
        JsonText(lCompatibility, 'sha256') then
        raise EConvertError.Create('passing gate baseline compatibility mismatch');
      if lBaselineJson = nil then
        raise EConvertError.Create('passing gate baseline.json is missing');
      if JsonText(JsonObjectMember(lBaselineJson, 'compatibility'), 'sha256') <> JsonText(lCompatibility, 'sha256') then
        raise EConvertError.Create('baseline.json compatibility mismatch');
    end;
    if not AnalysisJsonEquivalent(JsonObjectMember(JsonObjectMember(lDelta, 'ownership'), 'after'), Result) then
      raise EConvertError.CreateFmt('delta.json ownership mismatch: expected=%s, actual=%s',
        [TPythonJson.Compact(Result),
         TPythonJson.Compact(JsonObjectMember(JsonObjectMember(lDelta, 'ownership'), 'after'))]);
    if JsonText(lDeltaFi, 'total_after') <> JsonText(JsonObjectMember(lExpectedCounts, 'fixinsight'), 'total') then
      raise EConvertError.Create('delta.json FixInsight total mismatch');
    if JsonText(lDeltaPal, 'total_after') <> JsonText(JsonObjectMember(lExpectedCounts, 'pascal_analyzer'), 'total') then
      raise EConvertError.Create('delta.json Pascal Analyzer total mismatch');
    // The last history row must describe this run.
    if TFile.Exists(TPath.Combine(lOutRoot, 'history.jsonl')) then
      GC(lHistory, LoadAnalysisJsonLines(TPath.Combine(lOutRoot, 'history.jsonl')), g)
    else
      GC(lHistory, TJSONArray.Create, g);
    lHistoryRow := nil;
    if lHistory.Count > 0 then
      lHistoryRow := TJSONObject(lHistory.Items[lHistory.Count - 1]);
    if not AnalysisJsonEquivalent(JsonObjectMember(lHistoryRow, 'ownership'), Result) then
      raise EConvertError.CreateFmt('history.jsonl ownership mismatch: expected=%s, actual=%s',
        [TPythonJson.Compact(Result), IfThen(lHistoryRow = nil, 'None',
         TPythonJson.Compact(JsonObjectMember(lHistoryRow, 'ownership')))]);
    if JsonText(JsonObjectMember(lHistoryRow, 'fixinsight'), 'total') <>
      JsonText(JsonObjectMember(lExpectedCounts, 'fixinsight'), 'total') then
      raise EConvertError.Create('history.jsonl FixInsight total mismatch');
    if not AnalysisJsonEquivalent(JsonObjectMember(JsonObjectMember(lHistoryRow, 'pascal_analyzer'), 'totals'),
      PalTotalsOf(JsonObjectMember(lExpectedCounts, 'pascal_analyzer'))) then
      raise EConvertError.Create('history.jsonl Pascal Analyzer totals mismatch');
    if not AnalysisJsonEquivalent(JsonObjectMember(lHistoryRow, 'raw'),
      JsonObjectMember(lExpectedProjections, 'raw')) then
      raise EConvertError.Create('history.jsonl raw projection mismatch');
    lText := AnalysisOwnershipText(Result);
    for i := 0 to High(cOwnershipLines) do
    begin
      lFound := False;
      for lLine in ReadAnalysisText(TPath.Combine(lOutRoot, cOwnershipLines[i].fArtifact))
        .Replace(#13#10, #10).Split([#10]) do
        if lLine = cOwnershipLines[i].fPrefix + lText then
          lFound := True;
      if not lFound then
        raise EConvertError.CreateFmt('%s ownership mismatch: expected ''%s''',
          [cOwnershipLines[i].fMessage, lText]);
    end;
    lTrendText := ReadAnalysisText(TPath.Combine(lOutRoot, 'trend.md'));
    lText := AnalysisOwnershipText(JsonObjectMember(JsonObjectMember(lExpectedProjections, 'raw'), 'ownership'));
    lFound := False;
    for lLine in lTrendText.Replace(#13#10, #10).Split([#10]) do
      if lLine = '- Latest raw ownership: ' + lText then
        lFound := True;
    if not lFound then
      raise EConvertError.CreateFmt('trend.md raw ownership mismatch: expected ''%s''', [lText]);
    VerifyTriageEvidence(lOutRoot, lSummaryJson, lFi, lPal);
    lText := ReadAnalysisText(TPath.Combine(lOutRoot, 'triage.md'));
    for i := 0 to 1 do
      if not lText.Contains(Format('- %s findings: %s ', [cLabels[i],
        JsonText(JsonObjectMember(lExpectedCounts, cAnalyzers[i]), 'total')])) then
        raise EConvertError.CreateFmt('triage.md %s total mismatch', [cLabels[i]]);
    lDeltaText := ReadAnalysisText(TPath.Combine(lOutRoot, 'delta.md'));
    if not TRegEx.IsMatch(lDeltaText, '^- Findings: .* -> ' +
      TRegEx.Escape(JsonText(JsonObjectMember(lExpectedCounts, 'fixinsight'), 'total')) + ' \(', [roMultiLine]) then
      raise EConvertError.Create('delta.md FixInsight total mismatch');
    if not TRegEx.IsMatch(lDeltaText, '^- Total: .* -> ' +
      TRegEx.Escape(JsonText(JsonObjectMember(lExpectedCounts, 'pascal_analyzer'), 'total')) + ' \(', [roMultiLine]) then
      raise EConvertError.Create('delta.md Pascal Analyzer total mismatch');
    VerifyTrendTotals(lTrendText, JsonObjectMember(lExpectedCounts, 'fixinsight'),
      JsonObjectMember(lExpectedCounts, 'pascal_analyzer'));
    VerifySarifEvidence(lOutRoot, 'static-analysis.sarif', lFi, lPal, False, Result);
    VerifySarifEvidence(lOutRoot, 'static-analysis.full.sarif', lFi, lPal, True, Result);
  except
    Result.Free;
    raise;
  end;
end;

end.
