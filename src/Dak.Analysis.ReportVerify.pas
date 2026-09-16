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

const
  cAnalyzers: array[0..1] of string = ('fixinsight', 'pascal_analyzer');
  cLabels: array[0..1] of string = ('FixInsight', 'Pascal Analyzer');

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
  lFi, lOrigins, lPal, lRows: TJSONArray;
  lBoundaries: TAnalysisOwnershipContext;
  lFiPath, lLine, lName, lOutRoot, lPalPath, lPalVersion, lText: string;
  lItem: TJSONValue;
  lActionable, lTotal: Integer;
  lPrefixes: array[0..1] of string;
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
    // Like the reference, the fingerprint is recomputed from the recorded seed alone; no inventory runs.
    lBoundaries := BuildAnalysisPolicyBoundaries(lSummaryJson);
    GC(lExpectedCompatibility, AnalysisCompatibilitySnapshot(lSummaryJson, lBoundaries), g);
    lCompatibility := JsonObjectMember(lSummaryJson, 'compatibility');
    if (lCompatibility = nil) or (JsonText(lCompatibility, 'sha256') <> JsonText(lExpectedCompatibility, 'sha256')) then
      raise EConvertError.Create('summary.json compatibility fingerprint mismatch');
    lText := AnalysisOwnershipText(Result);
    lPrefixes[0] := '- ';
    lPrefixes[1] := '- Ownership: ';
    for i := 0 to 1 do
    begin
      lName := IfThen(i = 0, 'summary.md', 'triage.md');
      lFound := False;
      for lLine in ReadAnalysisText(TPath.Combine(lOutRoot, lName)).Replace(#13#10, #10).Split([#10]) do
        if lLine = lPrefixes[i] + lText then
          lFound := True;
      if not lFound then
        raise EConvertError.CreateFmt('%s ownership mismatch: expected ''%s''', [lName, lText]);
    end;
    VerifyTriageEvidence(lOutRoot, lSummaryJson, lFi, lPal);
    lText := ReadAnalysisText(TPath.Combine(lOutRoot, 'triage.md'));
    for i := 0 to 1 do
      if not lText.Contains(Format('- %s findings: %s ', [cLabels[i],
        JsonText(JsonObjectMember(lExpectedCounts, cAnalyzers[i]), 'total')])) then
        raise EConvertError.CreateFmt('triage.md %s total mismatch', [cLabels[i]]);
    VerifySarifEvidence(lOutRoot, 'static-analysis.sarif', lFi, lPal, False, Result);
    VerifySarifEvidence(lOutRoot, 'static-analysis.full.sarif', lFi, lPal, True, Result);
  except
    Result.Free;
    raise;
  end;
end;

end.
