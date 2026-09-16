unit Dak.Analysis.ReportWriters;

{$SCOPEDENUMS ON}

interface

uses
  System.JSON;

// Consumer artifacts written exactly as postprocess.py writes them on Windows:
// UTF-8 without BOM, CRLF line endings, Python json.dumps layouts.

procedure WriteAnalysisText(const aPath, aText: string);
// _write_json: indent 2, sorted keys, trailing newline, temporary file then replace.
procedure WriteAnalysisJsonDocument(const aPath: string; aValue: TJSONValue);
// _write_jsonl: one insertion-ordered row per line. Nil rows delete nothing and write nothing.
procedure WriteAnalysisJsonLines(const aPath: string; aRows: TJSONArray);
// _write_summary_ownership
procedure WriteAnalysisSummaryOwnership(const aSummaryPath: string; aCounts: TJSONObject);
// _write_sarif for actionable rows (aFull = False) or every row (aFull = True); returns the path.
function WriteAnalysisSarif(const aOutRoot: string; aFixInsight, aPal: TJSONArray; aFull: Boolean): string; overload;
function WriteAnalysisSarif(const aOutRoot: string; aFixInsight, aPal: TJSONArray; aFull: Boolean;
  out aResultCount: Integer): string; overload;
// The SARIF document itself (caller-owned), for verification without touching the output.
function BuildAnalysisSarif(aFixInsight, aPal: TJSONArray; aFull: Boolean): TJSONObject;
function AnalysisSarifResultCount(aSarif: TJSONObject): Integer;
function WriteAnalysisExternalSummary(const aOutRoot: string; aFixInsight, aPal: TJSONArray): string;
function WriteAnalysisMetricsSummary(const aOutRoot: string; aFixInsight, aPal: TJSONArray): string;
type
  // The triage selection controls, from the environment during finalization or from
  // summary.json's recorded active policy during verification.
  TAnalysisTriagePolicy = record
    fTop: Integer;
    fIncludePaths: string;
    fExcludePaths: string;
    fPalIncludeCallTree: Boolean;
    fSnippets: Boolean;
    class function FromEnvironment: TAnalysisTriagePolicy; static;
  end;

// _write_triage plus optional snippets; returns triage.md.
function WriteAnalysisTriage(const aOutRoot, aTitle: string; aFixInsight, aPal: TJSONArray;
  const aPolicy: TAnalysisTriagePolicy): string;
// The triage.md text alone, for verification without touching the output.
function RenderAnalysisTriage(const aTitle: string; aFixInsight, aPal: TJSONArray;
  const aPolicy: TAnalysisTriagePolicy): string;
// _write_triage_changed using the provenance target's changed files.
function WriteAnalysisTriageChanged(const aOutRoot, aTitle: string; aSummary: TJSONObject;
  aFixInsight, aPal: TJSONArray; const aWorkspaceFiles: TArray<string>): string;

implementation

uses
  System.Character, System.Classes, System.Generics.Collections, System.Generics.Defaults, System.IOUtils,
  System.Math, System.RegularExpressions, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  Dak.Analysis.JsonText, Dak.Analysis.Projections, Dak.Analysis.ReportBundle, Dak.Analysis.Text,
  Dak.Settings;

function OrDefaultText(const aValue, aDefault: string): string;
begin
  if aValue = '' then
    Result := aDefault
  else
    Result := aValue;
end;

function NullableText(const aValue: string): TJSONValue;
begin
  if aValue = '' then
    Result := TJSONNull.Create
  else
    Result := TJSONString.Create(aValue);
end;

type
  // Python text-mode output: UTF-8 without BOM, each LF written as CRLF (an LF already preceded by
  // CR keeps that CR), encoded in bounded chunks so a large report never has several copies alive.
  TAnalysisTextWriter = class
  private
    fChunk: TStringBuilder;
    fPrevious: Char;
    fStream: TFileStream;
    procedure Flush;
  public
    constructor Create(const aPath: string);
    destructor Destroy; override;
    procedure Append(const aText: string);
  end;

const
  cTextChunkChars = 32768;

constructor TAnalysisTextWriter.Create(const aPath: string);
begin
  inherited Create;
  TDirectory.CreateDirectory(TPath.GetDirectoryName(aPath));
  fStream := TFileStream.Create(aPath, fmCreate);
  fChunk := TStringBuilder.Create(cTextChunkChars + cTextChunkChars div 8);
end;

destructor TAnalysisTextWriter.Destroy;
begin
  if fChunk <> nil then
    Flush;
  fChunk.Free;
  fStream.Free;
  inherited;
end;

procedure TAnalysisTextWriter.Flush;
var
  lBytes: TBytes;
begin
  if fChunk.Length = 0 then
    Exit;
  lBytes := TEncoding.UTF8.GetBytes(fChunk.ToString);
  fStream.WriteBuffer(lBytes[0], Length(lBytes));
  fChunk.Length := 0;
end;

procedure TAnalysisTextWriter.Append(const aText: string);
var
  c: Char;
begin
  for c in aText do
  begin
    if (c = #10) and (fPrevious <> #13) then
      fChunk.Append(#13);
    fChunk.Append(c);
    fPrevious := c;
    // A chunk never ends between a high and a low surrogate.
    if (fChunk.Length >= cTextChunkChars) and not c.IsHighSurrogate then
      Flush;
  end;
end;

procedure WriteAnalysisText(const aPath, aText: string);
var
  lWriter: TAnalysisTextWriter;
begin
  lWriter := TAnalysisTextWriter.Create(aPath);
  try
    lWriter.Append(aText);
  finally
    lWriter.Free;
  end;
end;

procedure WriteAnalysisJsonDocument(const aPath: string; aValue: TJSONValue);
var
  lStream: TFileStream;
  lTemp: string;
begin
  TDirectory.CreateDirectory(TPath.GetDirectoryName(aPath));
  lTemp := TPath.Combine(TPath.GetDirectoryName(aPath), '.' + TPath.GetFileName(aPath) + '.' +
    IntToStr(GetCurrentProcessId) + '.tmp');
  try
    lStream := TFileStream.Create(lTemp, fmCreate);
    try
      TPythonJson.WriteDocument(aValue, lStream);
    finally
      lStream.Free;
    end;
    if TFile.Exists(aPath) then
      TFile.Delete(aPath);
    TFile.Move(lTemp, aPath);
  finally
    if TFile.Exists(lTemp) then
      TFile.Delete(lTemp);
  end;
end;

procedure WriteAnalysisJsonLines(const aPath: string; aRows: TJSONArray);
var
  lItem: TJSONValue;
  lWriter: TAnalysisTextWriter;
begin
  if aRows = nil then
    Exit;
  lWriter := TAnalysisTextWriter.Create(aPath);
  try
    for lItem in aRows do
    begin
      lWriter.Append(TPythonJson.Line(lItem));
      lWriter.Append(#10);
    end;
  finally
    lWriter.Free;
  end;
end;

procedure WriteAnalysisSummaryOwnership(const aSummaryPath: string; aCounts: TJSONObject);
const
  cMarker = '<!-- DAK ownership -->';
var
  lText: string;
  lIndex: Integer;
begin
  lText := ReadAnalysisText(aSummaryPath).TrimRight;
  lIndex := lText.IndexOf(cMarker);
  if lIndex >= 0 then
    lText := lText.Substring(0, lIndex).TrimRight;
  WriteAnalysisText(aSummaryPath, lText + #10#10 + cMarker + #10 + '## Ownership' + #10#10 + '- ' +
    AnalysisOwnershipText(aCounts) + #10);
end;

function RowText(aRow: TJSONObject; const aName: string): string;
begin
  Result := JsonText(aRow, aName);
end;

function RowNullableText(aRow: TJSONObject; const aName: string): TJSONValue;
var
  lValue: TJSONValue;
begin
  lValue := aRow.GetValue(aName);
  if (lValue = nil) or (lValue is TJSONNull) then
    Exit(TJSONNull.Create);
  Result := JsonCloneValue(lValue);
end;

function RowInteger(aRow: TJSONObject; const aName: string; aDefault: Integer): Integer;
var
  lValue: TJSONValue;
begin
  lValue := aRow.GetValue(aName);
  if (lValue = nil) or (lValue is TJSONNull) then
    Exit(aDefault);
  // int(obj.get(...) or 1): falsy values fall back to the default.
  if (lValue is TJSONNumber) and ((lValue.Value = '0') or (lValue.Value = '')) then
    Exit(aDefault);
  Result := StrToIntDef(lValue.Value, aDefault);
end;

function SarifUri(const aPath: string): string;
var
  lPart: string;
  lParts: TList<string>;
  lValue: string;
  lLeading: Integer;
  lAbsolute: Boolean;
begin
  lValue := Trim(aPath).Replace('\', '/');
  if (lValue = '') or (lValue = '.') then
    Exit('');
  // posixpath.normpath
  lAbsolute := lValue.StartsWith('/');
  lLeading := 0;
  if lValue.StartsWith('//') and not lValue.StartsWith('///') then
    lLeading := 2
  else if lAbsolute then
    lLeading := 1;
  lParts := TList<string>.Create;
  try
    for lPart in lValue.Split(['/']) do
    begin
      if (lPart = '') or (lPart = '.') then
        Continue;
      if (lPart <> '..') or ((lLeading = 0) and (lParts.Count = 0)) or
        ((lParts.Count > 0) and (lParts.Last = '..')) then
        lParts.Add(lPart)
      else if lParts.Count > 0 then
        lParts.Delete(lParts.Count - 1);
    end;
    Result := String.Join('/', lParts.ToArray);
    if lLeading > 0 then
      Result := StringOfChar('/', lLeading) + Result;
    if Result = '' then
      Result := '.';
  finally
    lParts.Free;
  end;
  if Result.StartsWith('../') then
    Result := '';
end;

function SarifLocation(const aUri: string; aLine, aColumn: Integer): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.AddElement(TJSONObject.Create.AddPair('physicalLocation', TJSONObject.Create
    .AddPair('artifactLocation', TJSONObject.Create.AddPair('uri', aUri))
    .AddPair('region', TJSONObject.Create
      .AddPair('startLine', TJSONNumber.Create(aLine))
      .AddPair('startColumn', TJSONNumber.Create(aColumn)))));
end;

type
  // Produces one SARIF result per selected row while the document renders, registering each
  // rule on first sight in the run's rule list (rendered after the results).
  TSarifRunProducer = class
  private
    fFull: Boolean;
    fIndex: Integer;
    fPal: Boolean;
    fRows: TJSONArray;
    fRuleIds: TDictionary<string, Boolean>;
    fRuleList: TJSONArray;
    function Selected(aRow: TJSONObject): Boolean;
    function FixInsightResult(aRow: TJSONObject): TJSONObject;
    function PalResult(aRow: TJSONObject): TJSONObject;
  public
    constructor Create(aRows: TJSONArray; aFull, aPal: Boolean; aRuleList: TJSONArray);
    destructor Destroy; override;
    function HasSelected: Boolean;
    function Next: TJSONValue;
  end;

constructor TSarifRunProducer.Create(aRows: TJSONArray; aFull, aPal: Boolean; aRuleList: TJSONArray);
begin
  inherited Create;
  fRows := aRows;
  fFull := aFull;
  fPal := aPal;
  fRuleList := aRuleList;
  fRuleIds := TDictionary<string, Boolean>.Create;
end;

destructor TSarifRunProducer.Destroy;
begin
  fRuleIds.Free;
  inherited;
end;

function TSarifRunProducer.Selected(aRow: TJSONObject): Boolean;
begin
  Result := fFull or AnalysisRecordIsActionable(aRow);
end;

function TSarifRunProducer.HasSelected: Boolean;
var
  lItem: TJSONValue;
begin
  for lItem in fRows do
    if Selected(TJSONObject(lItem)) then
      Exit(True);
  Result := False;
end;

function TSarifRunProducer.FixInsightResult(aRow: TJSONObject): TJSONObject;
var
  lCode, lKind, lMessage, lUri: string;
begin
  lCode := Trim(RowText(aRow, 'code'));
  if lCode = '' then
    Exit(nil);
  lKind := Trim(RowText(aRow, 'kind'));
  lUri := RowText(aRow, 'path');
  if lUri = '' then
    lUri := RowText(aRow, 'file');
  lUri := SarifUri(lUri);
  lMessage := Trim(RowText(aRow, 'message'));
  if lMessage = '' then
    lMessage := lCode;
  if not fRuleIds.ContainsKey(lCode) then
  begin
    fRuleIds.Add(lCode, True);
    fRuleList.AddElement(TJSONObject.Create
      .AddPair('id', lCode)
      .AddPair('shortDescription', TJSONObject.Create.AddPair('text', 'FixInsight ' + lCode)));
  end;
  Result := TJSONObject.Create
    .AddPair('ruleId', lCode)
    .AddPair('level', IfThen(SameText(lKind, 'W'), 'warning', 'note'))
    .AddPair('message', TJSONObject.Create.AddPair('text', lMessage))
    .AddPair('properties', TJSONObject.Create
      .AddPair('tool', 'FixInsight')
      .AddPair('kind', lKind)
      .AddPair('code', lCode)
      .AddPair('ownership', IfThen(RowText(aRow, 'ownership') = '', 'unknown', RowText(aRow, 'ownership')))
      .AddPair('ownership_root', RowNullableText(aRow, 'ownership_root')));
  if lUri <> '' then
    Result.AddPair('locations', SarifLocation(lUri, RowInteger(aRow, 'line', 1), RowInteger(aRow, 'col', 1)));
end;

function TSarifRunProducer.PalResult(aRow: TJSONObject): TJSONObject;
var
  lIdent, lMessage, lPalCode, lRuleId, lSection, lSeverity, lUri: string;
  lRule: TJSONObject;
begin
  lSeverity := Trim(RowText(aRow, 'severity'));
  lSection := Trim(RowText(aRow, 'section'));
  lUri := SarifUri(RowText(aRow, 'path'));
  lIdent := Trim(RowText(aRow, 'id'));
  if lIdent = '' then
    lIdent := Trim(RowText(aRow, 'message'));
  lRuleId := Trim(RowText(aRow, 'normalized_rule'));
  if lRuleId = '' then
    lRuleId := AnalysisNormalizedRuleId(aRow);
  lPalCode := Trim(RowText(aRow, 'pal_code'));
  if not fRuleIds.ContainsKey(lRuleId) then
  begin
    fRuleIds.Add(lRuleId, True);
    lRule := TJSONObject.Create
      .AddPair('id', lRuleId)
      .AddPair('name', IfThen(lSection = '', lRuleId, lSection))
      .AddPair('shortDescription', TJSONObject.Create.AddPair('text',
        IfThen(lSection = '', 'Pascal Analyzer finding', lSection)));
    if lPalCode <> '' then
      lRule.AddPair('properties', TJSONObject.Create.AddPair('nativeCode', lPalCode));
    fRuleList.AddElement(lRule);
  end;
  if (lSection <> '') and (lIdent <> '') then
    lMessage := lSection + ': ' + lIdent
  else if lSection <> '' then
    lMessage := lSection
  else if lIdent <> '' then
    lMessage := lIdent
  else
    lMessage := 'Pascal Analyzer finding';
  Result := TJSONObject.Create
    .AddPair('ruleId', lRuleId)
    .AddPair('level', IfThen(SameText(lSeverity, 'strong-warning'), 'warning', 'note'))
    .AddPair('message', TJSONObject.Create.AddPair('text', lMessage))
    .AddPair('properties', TJSONObject.Create
      .AddPair('tool', 'Pascal Analyzer')
      .AddPair('severity', lSeverity)
      .AddPair('report', RowText(aRow, 'report'))
      .AddPair('section', lSection)
      .AddPair('normalized_rule', lRuleId)
      .AddPair('pal_code', NullableText(lPalCode))
      .AddPair('ownership', IfThen(RowText(aRow, 'ownership') = '', 'unknown', RowText(aRow, 'ownership')))
      .AddPair('ownership_root', RowNullableText(aRow, 'ownership_root')));
  if lUri <> '' then
    Result.AddPair('locations', SarifLocation(lUri, RowInteger(aRow, 'line', 1), RowInteger(aRow, 'col', 1)));
end;

function TSarifRunProducer.Next: TJSONValue;
var
  lRow: TJSONObject;
begin
  Result := nil;
  while (Result = nil) and (fIndex < fRows.Count) do
  begin
    lRow := TJSONObject(fRows.Items[fIndex]);
    Inc(fIndex);
    if not Selected(lRow) then
      Continue;
    if fPal then
      Result := PalResult(lRow)
    else
      Result := FixInsightResult(lRow);
  end;
end;

function BuildAnalysisSarif(aFixInsight, aPal: TJSONArray; aFull: Boolean): TJSONObject;
var
  lDocument: TJSONObject;
  lRuns: TJSONArray;

  procedure AddRun(aRows: TJSONArray; aPal: Boolean; const aTool: string);
  var
    lProducer: TSarifRunProducer;
    lResults: TJsonStreamedArray;
    lRuleList: TJSONArray;
  begin
    if aRows = nil then
      Exit;
    // Rules keep first-seen order, like the reference's insertion-ordered dictionary; a run without
    // results is not published at all.
    lRuleList := TJSONArray.Create;
    lProducer := TSarifRunProducer.Create(aRows, aFull, aPal, lRuleList);
    if not lProducer.HasSelected then
    begin
      lProducer.Free;
      lRuleList.Free;
      Exit;
    end;
    lResults := TJsonStreamedArray.Create(lProducer,
      function: TJSONValue
      begin
        Result := lProducer.Next;
      end);
    // "results" precedes "tool" in both insertion and sorted order, so the rule list is complete
    // by the time the driver renders.
    lRuns.AddElement(TJSONObject.Create
      .AddPair('results', lResults)
      .AddPair('tool', TJSONObject.Create.AddPair('driver', TJSONObject.Create
        .AddPair('name', aTool)
        .AddPair('rules', lRuleList))));
  end;

begin
  lRuns := TJSONArray.Create;
  lDocument := TJSONObject.Create
    .AddPair('$schema', 'https://json.schemastore.org/sarif-2.1.0.json')
    .AddPair('version', '2.1.0')
    .AddPair('runs', lRuns);
  try
    AddRun(aFixInsight, False, 'FixInsight');
    AddRun(aPal, True, 'Pascal Analyzer');
    Result := lDocument;
  except
    lDocument.Free;
    raise;
  end;
end;

function AnalysisSarifResultCount(aSarif: TJSONObject): Integer;
var
  lResults: TJSONValue;
  lRun: TJSONValue;
  lRuns: TJSONArray;
begin
  Result := 0;
  lRuns := JsonArrayMember(aSarif, 'runs');
  if lRuns = nil then
    Exit;
  for lRun in lRuns do
    if lRun is TJSONObject then
    begin
      lResults := TJSONObject(lRun).GetValue('results');
      if lResults is TJsonStreamedArray then
        Inc(Result, TJsonStreamedArray(lResults).Rendered)
      else if lResults is TJSONArray then
        Inc(Result, TJSONArray(lResults).Count);
    end;
end;

function WriteAnalysisSarif(const aOutRoot: string; aFixInsight, aPal: TJSONArray; aFull: Boolean;
  out aResultCount: Integer): string;
var
  lDocument: TJSONObject;
begin
  if aFull then
    Result := TPath.Combine(aOutRoot, 'static-analysis.full.sarif')
  else
    Result := TPath.Combine(aOutRoot, 'static-analysis.sarif');
  lDocument := BuildAnalysisSarif(aFixInsight, aPal, aFull);
  try
    // The results stream while the document is written, so the count follows the write.
    WriteAnalysisJsonDocument(Result, lDocument);
    aResultCount := AnalysisSarifResultCount(lDocument);
  finally
    lDocument.Free;
  end;
end;

function WriteAnalysisSarif(const aOutRoot: string; aFixInsight, aPal: TJSONArray; aFull: Boolean): string;
var
  lCount: Integer;
begin
  Result := WriteAnalysisSarif(aOutRoot, aFixInsight, aPal, aFull, lCount);
end;

function ProjectionRows(aFixInsight, aPal: TJSONArray; const aProjection: string): TList<TJSONObject>;
var
  lItem: TJSONValue;
  lRows: TJSONArray;
begin
  Result := TList<TJSONObject>.Create;
  for lRows in [aFixInsight, aPal] do
    if lRows <> nil then
      for lItem in lRows do
        if RowText(TJSONObject(lItem), 'report_projection') = aProjection then
          Result.Add(TJSONObject(lItem));
end;

function WriteAnalysisExternalSummary(const aOutRoot: string; aFixInsight, aPal: TJSONArray): string;
var
  lExternal: TList<TJSONObject>;
  lGrouped: TDictionary<string, Integer>;
  lLines: TList<string>;
  lRoot, lRule, lKey: string;
  lRootOwnership: TDictionary<string, string>;
  lRoots: TDictionary<string, Integer>;
  lRow: TJSONObject;
  lSortedRoots, lSortedGroups: TArray<string>;
begin
  Result := TPath.Combine(aOutRoot, 'external-summary.md');
  lExternal := ProjectionRows(aFixInsight, aPal, 'external');
  lGrouped := TDictionary<string, Integer>.Create;
  lRoots := TDictionary<string, Integer>.Create;
  lRootOwnership := TDictionary<string, string>.Create;
  lLines := TList<string>.Create;
  try
    for lRow in lExternal do
    begin
      lRoot := RowText(lRow, 'ownership_root');
      if lRoot = '' then
        lRoot := '<unknown root>';
      lRule := RowText(lRow, 'normalized_rule');
      if lRule = '' then
        lRule := 'unknown';
      lRoots.AddOrSetValue(lRoot, IfThen(lRoots.ContainsKey(lRoot), lRoots[lRoot], 0) + 1);
      lRootOwnership.AddOrSetValue(lRoot, IfThen(RowText(lRow, 'ownership') = '', 'unknown', RowText(lRow, 'ownership')));
      lKey := lRoot + #0 + lRule;
      lGrouped.AddOrSetValue(lKey, IfThen(lGrouped.ContainsKey(lKey), lGrouped[lKey], 0) + 1);
    end;
    lLines.Add('# External static-analysis summary');
    lLines.Add('');
    lLines.Add('- Findings: ' + IntToStr(lExternal.Count));
    lLines.Add('- Projection: external ownership outside the active gate policy');
    lLines.Add('');
    lSortedRoots := lRoots.Keys.ToArray;
    TArray.Sort<string>(lSortedRoots, TComparer<string>.Construct(
      function(const aLeft, aRight: string): Integer
      begin
        Result := lRoots[aRight] - lRoots[aLeft];
        if Result = 0 then
          Result := CompareStr(aLeft.ToLowerInvariant, aRight.ToLowerInvariant);
      end));
    lSortedGroups := lGrouped.Keys.ToArray;
    TArray.Sort<string>(lSortedGroups, TComparer<string>.Construct(
      function(const aLeft, aRight: string): Integer
      var
        lLeftRoot, lRightRoot: string;
      begin
        lLeftRoot := aLeft.Substring(0, aLeft.IndexOf(#0)).ToLowerInvariant;
        lRightRoot := aRight.Substring(0, aRight.IndexOf(#0)).ToLowerInvariant;
        Result := CompareStr(lLeftRoot, lRightRoot);
        if Result = 0 then
          Result := CompareStr(aLeft.Substring(aLeft.IndexOf(#0) + 1), aRight.Substring(aRight.IndexOf(#0) + 1));
      end));
    for lRoot in lSortedRoots do
    begin
      lLines.Add('## `' + lRoot + '`');
      lLines.Add('');
      lLines.Add('- Ownership: ' + lRootOwnership[lRoot]);
      lLines.Add('- Findings: ' + IntToStr(lRoots[lRoot]));
      for lKey in lSortedGroups do
        if lKey.Substring(0, lKey.IndexOf(#0)) = lRoot then
          lLines.Add('- `' + lKey.Substring(lKey.IndexOf(#0) + 1) + '`: ' + IntToStr(lGrouped[lKey]));
      lLines.Add('');
    end;
    WriteAnalysisText(Result, String.Join(#10, lLines.ToArray).TrimRight + #10);
  finally
    lLines.Free;
    lRootOwnership.Free;
    lRoots.Free;
    lGrouped.Free;
    lExternal.Free;
  end;
end;

function WriteAnalysisMetricsSummary(const aOutRoot: string; aFixInsight, aPal: TJSONArray): string;
var
  lAdvisory: TList<TJSONObject>;
  lByRule: TDictionary<string, Integer>;
  lLines: TList<string>;
  lRow: TJSONObject;
  lRule: string;
  lRules: TArray<string>;
begin
  Result := TPath.Combine(aOutRoot, 'metrics.md');
  lAdvisory := ProjectionRows(aFixInsight, aPal, 'advisory_metrics');
  lByRule := TDictionary<string, Integer>.Create;
  lLines := TList<string>.Create;
  try
    for lRow in lAdvisory do
    begin
      lRule := RowText(lRow, 'normalized_rule');
      if lRule = '' then
        lRule := 'unknown';
      lByRule.AddOrSetValue(lRule, IfThen(lByRule.ContainsKey(lRule), lByRule[lRule], 0) + 1);
    end;
    lLines.Add('# Advisory static-analysis metrics');
    lLines.Add('');
    lLines.Add('- Findings: ' + IntToStr(lAdvisory.Count));
    lLines.Add('- Gate behavior: advisory by default; only explicitly selected metric rules are actionable');
    lLines.Add('');
    lRules := lByRule.Keys.ToArray;
    TArray.Sort<string>(lRules, TComparer<string>.Construct(
      function(const aLeft, aRight: string): Integer
      begin
        Result := lByRule[aRight] - lByRule[aLeft];
        if Result = 0 then
          Result := CompareStr(aLeft, aRight);
      end));
    for lRule in lRules do
      lLines.Add('- `' + lRule + '`: ' + IntToStr(lByRule[lRule]));
    WriteAnalysisText(Result, String.Join(#10, lLines.ToArray).TrimRight + #10);
  finally
    lLines.Free;
    lByRule.Free;
    lAdvisory.Free;
  end;
end;

type
  TTriageItem = record
    fPriority: Integer;
    fPath: string;
    fCode: string;
    fKind: string;
    fSeverity: string;
    fOwnership: string;
    fSection: string;
    fModule: string;
    fLine: string;
    fCol: string;
    fMessage: string;
    // int(line) if str(line).isdigit() else 0, computed once: the sort compares it for every pair.
    fLineNumber: Integer;
  end;

function TriageLineNumber(const aLine: string): Integer;
var
  c: Char;
begin
  if aLine = '' then
    Exit(0);
  for c in aLine do
    if not c.IsDigit then
      Exit(0);
  if not TryStrToInt(aLine, Result) then
    Result := 0;
end;

// Windows drive prefix as the reference's regular expressions '^[A-Za-z]:' and '^[A-Za-z]:/' see it.
function StartsWithDriveLetter(const aValue: string; aRequireSlash: Boolean): Boolean;
begin
  Result := (Length(aValue) >= 2) and CharInSet(aValue[1], ['A'..'Z', 'a'..'z']) and (aValue[2] = ':') and
    ((not aRequireSlash) or ((Length(aValue) >= 3) and (aValue[3] = '/')));
end;

function FixInsightPriority(const aKind: string): Integer;
var
  lKind: string;
begin
  lKind := Trim(aKind).ToUpperInvariant;
  if lKind = 'W' then
    Result := 300
  else if lKind = 'C' then
    Result := 200
  else if lKind = 'O' then
    Result := 100
  else
    Result := 50;
end;

function PalPriority(const aSeverity: string): Integer;
var
  lSeverity: string;
begin
  lSeverity := Trim(aSeverity).ToLowerInvariant;
  if MatchStr(lSeverity, ['strong-warning', 'strong_warning', 'strongwarning']) then
    Result := 300
  else if lSeverity = 'warning' then
    Result := 200
  else if lSeverity = 'exception' then
    Result := 150
  else if lSeverity = 'hint' then
    Result := 100
  else
    Result := 80;
end;

class function TAnalysisTriagePolicy.FromEnvironment: TAnalysisTriagePolicy;
begin
  Result.fTop := AnalysisIntegerEnvironment('DAK_TRIAGE_TOP', 20);
  if Result.fTop = 0 then
    Result.fTop := 20;
  Result.fIncludePaths := Trim(GetEnvironmentVariable('DAK_TRIAGE_INCLUDE_PATHS'));
  Result.fExcludePaths := Trim(GetEnvironmentVariable('DAK_TRIAGE_EXCLUDE_PATHS'));
  Result.fPalIncludeCallTree := AnalysisTruthyEnvironment('DAK_TRIAGE_PAL_INCLUDE_CALL_TREE', False);
  Result.fSnippets := AnalysisTruthyEnvironment('DAK_TRIAGE_SNIPPETS', False);
end;

function PalItemPriority(const aSeverity, aReport, aSection, aMessage: string; aIncludeCallTree: Boolean): Integer;
var
  lMessage, lReport, lSection: string;
begin
  Result := PalPriority(aSeverity);
  if Result <= 0 then
    Exit;
  if (Trim(aSeverity).ToLowerInvariant = 'exception') and not aIncludeCallTree then
  begin
    lSection := Trim(aSection).ToLowerInvariant;
    lMessage := Trim(aMessage).ToLowerInvariant;
    lReport := Trim(aReport).ToLowerInvariant;
    if lSection.Contains('call tree') or lMessage.Contains('call tree') or
      ((lReport = 'exception.xml') and (lSection = 'exception call tree')) then
      Result := 10;
  end;
end;

function TriagePathAllowed(const aPath: string; const aInclude, aExclude: TArray<string>): Boolean;
var
  lPattern: string;
  lPath: string;
  lMatched: Boolean;
begin
  // _triage_path_allowed: an empty path passes only without include patterns; exclude wins.
  lPath := Trim(aPath);
  if lPath = '' then
    Exit(Length(aInclude) = 0);
  if Length(aInclude) > 0 then
  begin
    lMatched := False;
    for lPattern in aInclude do
      if AnalysisPathMaskMatches(lPath, lPattern) then
        lMatched := True;
    if not lMatched then
      Exit(False);
  end;
  for lPattern in aExclude do
    if AnalysisPathMaskMatches(lPath, lPattern) then
      Exit(False);
  Result := True;
end;

function CompareTriage(const aLeft, aRight: TTriageItem; aPal: Boolean): Integer;
begin
  Result := aRight.fPriority - aLeft.fPriority;
  if Result = 0 then
  begin
    if aPal then
      Result := CompareStr(aLeft.fSeverity, aRight.fSeverity)
    else
      Result := CompareStr(aLeft.fCode, aRight.fCode);
  end;
  if Result = 0 then
    Result := CompareStr(aLeft.fPath, aRight.fPath);
  if Result = 0 then
    Result := aLeft.fLineNumber - aRight.fLineNumber;
end;

procedure WriteTriageSnippets(const aOutRoot, aTitle: string; const aFiTop, aPalTop: TArray<TTriageItem>);
var
  lRepoRoot: string;
  lContext, lMaxBytes, lUsed: Integer;
  lTruncated: Boolean;
  lBuffer: TList<string>;
  lCache: TDictionary<string, TArray<string>>;

  function BlockBytes(const aLines: TArray<string>): Integer;
  begin
    Result := Length(TEncoding.UTF8.GetBytes(String.Join(#10, aLines).TrimRight + #10));
  end;

  function TryAddBlock(const aLines: TArray<string>): Boolean;
  var
    lBytes: Integer;
  begin
    lBytes := BlockBytes(aLines);
    if lUsed + lBytes > lMaxBytes then
    begin
      lTruncated := True;
      Exit(False);
    end;
    lBuffer.AddRange(aLines);
    Inc(lUsed, lBytes);
    Result := True;
  end;

  // The trailing blocks of a section: a block that no longer fits only sets the truncation note.
  procedure AddBlock(const aLines: TArray<string>);
  begin
    TryAddBlock(aLines);
  end;

  function TryLoadLines(const aPath: string; out aLines: TArray<string>): Boolean;
  var
    lNormalized, lFull: string;
  begin
    // Callers read the lines only on True; an unreadable path leaves an explicitly empty array.
    aLines := nil;
    Result := False;
    if lRepoRoot = '' then
      Exit;
    lNormalized := Trim(aPath);
    if (lNormalized = '') or (lNormalized = '?') or (lNormalized = 'unknown') then
      Exit;
    lNormalized := lNormalized.Replace('\', '/');
    if lNormalized.StartsWith('/') or StartsWithDriveLetter(lNormalized, False) then
      Exit;
    lFull := TPath.GetFullPath(TPath.Combine(lRepoRoot, lNormalized.Replace('/', '\')));
    if not lFull.StartsWith(IncludeTrailingPathDelimiter(lRepoRoot), True) then
      Exit;
    if not TFile.Exists(lFull) then
      Exit;
    if not lCache.TryGetValue(lFull, aLines) then
    begin
      aLines := ReadAnalysisText(lFull).Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
      if (Length(aLines) > 0) and (aLines[High(aLines)] = '') then
        SetLength(aLines, Length(aLines) - 1);
      lCache.Add(lFull, aLines);
    end;
    Result := True;
  end;

  function SnippetFor(const aLines: TArray<string>; aLineNumber: Integer): string;
  var
    i, lStart, lEnd, lWidth: Integer;
    lOut: TList<string>;
    lMark: string;
  begin
    Result := '';
    if (aLineNumber <= 0) or (aLineNumber - 1 >= Length(aLines)) then
      Exit;
    lStart := Max(0, aLineNumber - 1 - lContext);
    lEnd := Min(Integer(Length(aLines)) - 1, aLineNumber - 1 + lContext);
    lWidth := Length(IntToStr(lEnd + 1));
    lOut := TList<string>.Create;
    try
      for i := lStart to lEnd do
      begin
        if i = aLineNumber - 1 then
          lMark := '=>'
        else
          lMark := '  ';
        lOut.Add(lMark + IntToStr(i + 1).PadLeft(lWidth) + ': ' + aLines[i]);
      end;
      Result := String.Join(#10, lOut.ToArray).TrimRight;
    finally
      lOut.Free;
    end;
  end;

  function EmitGroup(const aPath: string; const aItems: TArray<TTriageItem>; const aHeading: string;
    aFixInsight: Boolean): Boolean;
  var
    lItem: TTriageItem;
    lLineNumber: Integer;
    lLineText, lSummary, lSnippet: string;
    lLines: TArray<string>;
    lSnippetLines: TList<string>;
  begin
    Result := False;
    if lTruncated then
      Exit;
    if not TryAddBlock([aHeading + ' `' + aPath + '`', '']) then
      Exit;
    for lItem in aItems do
    begin
      if lTruncated then
        Exit;
      lLineNumber := lItem.fLineNumber;
      if lItem.fLine = '' then
        lLineText := '?'
      else
        lLineText := lItem.fLine;
      if lLineNumber > 0 then
        lLineText := IntToStr(lLineNumber);
      if aFixInsight then
        lSummary := '- [' + lItem.fCode + '] ' + lLineText + ':' + lItem.fCol + ' - ' + lItem.fMessage
      else
        lSummary := '- [' + lItem.fSeverity + '] ' + lLineText + ' - ' + lItem.fSection + ': ' + lItem.fMessage;
      lSnippetLines := TList<string>.Create;
      try
        lSnippetLines.Add(lSummary);
        if (lLineNumber > 0) and TryLoadLines(aPath, lLines) then
        begin
          lSnippet := SnippetFor(lLines, lLineNumber);
          if lSnippet <> '' then
            lSnippetLines.AddRange(['', '```delphi', lSnippet, '```']);
        end;
        if lSnippetLines.Count = 1 then
          lSnippetLines[0] := lSnippetLines[0] + ' (snippet unavailable)';
        lSnippetLines.Add('');
        if not TryAddBlock(lSnippetLines.ToArray) then
          Exit;
      finally
        lSnippetLines.Free;
      end;
    end;
    Result := True;
  end;

  procedure EmitGroupedByPath(const aItems: TArray<TTriageItem>; const aHeading: string; aFixInsight: Boolean);
  var
    lGroups: TDictionary<string, TList<TTriageItem>>;
    lOrder: TList<string>;
    lItem: TTriageItem;
    lPath: string;
  begin
    lGroups := TObjectDictionary<string, TList<TTriageItem>>.Create([doOwnsValues]);
    lOrder := TList<string>.Create;
    try
      for lItem in aItems do
      begin
        lPath := lItem.fPath;
        if lPath = '' then
          lPath := '?';
        if not lGroups.ContainsKey(lPath) then
        begin
          lGroups.Add(lPath, TList<TTriageItem>.Create);
          lOrder.Add(lPath);
        end;
        lGroups[lPath].Add(lItem);
      end;
      for lPath in lOrder do
        if not EmitGroup(lPath, lGroups[lPath].ToArray, aHeading, aFixInsight) then
          Exit;
    finally
      lOrder.Free;
      lGroups.Free;
    end;
  end;

  procedure EmitSection(const aName: string; const aItems: TArray<TTriageItem>; aFixInsight: Boolean);
  var
    lKinds: array[0..3] of TList<TTriageItem>;
    lItem: TTriageItem;
    i, lIndex: Integer;
  const
    cHeadings: array[0..2] of string = ('### W findings (defects)', '### C findings (maintainability)',
      '### O findings (hygiene)');
    cKinds: array[0..2] of string = ('W', 'C', 'O');
  begin
    if lTruncated then
      Exit;
    if not TryAddBlock(['## ' + aName, '']) then
      Exit;
    if Length(aItems) = 0 then
    begin
      AddBlock(['No ' + aName + ' findings.', '']);
      Exit;
    end;
    if not aFixInsight then
    begin
      EmitGroupedByPath(aItems, '###', False);
      Exit;
    end;
    for i := 0 to 3 do
      lKinds[i] := TList<TTriageItem>.Create;
    try
      for lItem in aItems do
      begin
        lIndex := IndexStr(Trim(lItem.fKind).ToUpperInvariant, cKinds);
        if lIndex < 0 then
          lIndex := 3;
        lKinds[lIndex].Add(lItem);
      end;
      for i := 0 to 2 do
      begin
        if lTruncated then
          Exit;
        if not TryAddBlock([cHeadings[i], '']) then
          Exit;
        if lKinds[i].Count = 0 then
        begin
          if not TryAddBlock(['No findings.', '']) then
            Exit;
          Continue;
        end;
        EmitGroupedByPath(lKinds[i].ToArray, '####', True);
      end;
      if (lKinds[3].Count > 0) and not lTruncated then
        if TryAddBlock(['### Other findings', '']) then
          EmitGroupedByPath(lKinds[3].ToArray, '####', True);
    finally
      for i := 0 to 3 do
        lKinds[i].Free;
    end;
  end;

var
  lRootLine: string;
begin
  lRepoRoot := FindNamedRepoRoot(aOutRoot, '.git');
  if lRepoRoot <> '' then
    lRepoRoot := TPath.GetFullPath(lRepoRoot);
  lContext := Max(0, AnalysisIntegerEnvironment('DAK_TRIAGE_SNIPPET_CONTEXT', 2));
  lMaxBytes := Max(0, AnalysisIntegerEnvironment('DAK_TRIAGE_SNIPPET_MAX_BYTES', 200000));
  lUsed := 0;
  lTruncated := False;
  lBuffer := TList<string>.Create;
  lCache := TDictionary<string, TArray<string>>.Create;
  try
    if lRepoRoot <> '' then
      lRootLine := '- Repo root: `' + lRepoRoot + '`'
    else
      lRootLine := '- Repo root: `<unknown>`';
    AddBlock(['# ' + aTitle + ' triage (snippets)', '', '- Timestamp: ' + AnalysisUtcNowIso, lRootLine,
      '- Context lines: ' + IntToStr(lContext), '- Max bytes: ' + IntToStr(lMaxBytes), '',
      'Snippets are best-effort and only emitted for repo-relative paths that exist on disk.', '']);
    EmitSection('FixInsight', aFiTop, True);
    EmitSection('Pascal Analyzer', aPalTop, False);
    if lTruncated then
      AddBlock(['', '_Output truncated due to `DAK_TRIAGE_SNIPPET_MAX_BYTES` budget._', '']);
    WriteAnalysisText(TPath.Combine(aOutRoot, 'triage-snippets.md'), String.Join(#10, lBuffer.ToArray).TrimRight + #10);
  finally
    lCache.Free;
    lBuffer.Free;
  end;
end;

function RenderTriage(const aTitle: string; aFixInsight, aPal: TJSONArray; const aPolicy: TAnalysisTriagePolicy;
  out aFiTop, aPalTop: TArray<TTriageItem>): string;
var
  lExclude, lInclude: TArray<string>;
  lFiItems, lPalItems: TList<TTriageItem>;
  lFiRecords, lPalRecords: TList<TJSONObject>;
  lFiTop, lPalTop: TArray<TTriageItem>;
  lItem: TJSONValue;
  lLines: TList<string>;
  lRow: TJSONObject;
  lTop: Integer;
  lTriage: TTriageItem;
  lOwnership: TJSONObject;

  procedure EmitKind(const aKind, aHeading: string; const aItems: TArray<TTriageItem>);
  var
    lGroups: TDictionary<string, TList<TTriageItem>>;
    lOrder: TList<string>;
    lEntry: TTriageItem;
    lPath: string;
  begin
    lLines.Add('### ' + aHeading);
    if Length(aItems) = 0 then
    begin
      lLines.Add('No findings.');
      lLines.Add('');
      Exit;
    end;
    lGroups := TObjectDictionary<string, TList<TTriageItem>>.Create([doOwnsValues]);
    lOrder := TList<string>.Create;
    try
      for lEntry in aItems do
      begin
        if not lGroups.ContainsKey(lEntry.fPath) then
        begin
          lGroups.Add(lEntry.fPath, TList<TTriageItem>.Create);
          lOrder.Add(lEntry.fPath);
        end;
        lGroups[lEntry.fPath].Add(lEntry);
      end;
      for lPath in lOrder do
      begin
        lLines.Add('#### `' + lPath + '`');
        for lEntry in lGroups[lPath] do
          lLines.Add('- [' + lEntry.fCode + '] [' + lEntry.fOwnership + '] ' + lEntry.fLine + ':' + lEntry.fCol +
            ' - ' + lEntry.fMessage);
        lLines.Add('');
      end;
    finally
      lOrder.Free;
      lGroups.Free;
    end;
  end;

  function KindItems(const aKind: string): TArray<TTriageItem>;
  var
    lEntry: TTriageItem;
    lList: TList<TTriageItem>;
    lKind: string;
  begin
    lList := TList<TTriageItem>.Create;
    try
      for lEntry in lFiTop do
      begin
        lKind := Trim(lEntry.fKind).ToUpperInvariant;
        if (lKind = aKind) or ((aKind = 'other') and not MatchStr(lKind, ['W', 'C', 'O'])) then
          lList.Add(lEntry);
      end;
      Result := lList.ToArray;
    finally
      lList.Free;
    end;
  end;

  function OrDefault(const aValue, aDefault: string): string;
  begin
    if aValue = '' then
      Result := aDefault
    else
      Result := aValue;
  end;

var
  lGroups: TDictionary<string, TList<TTriageItem>>;
  lOrder: TList<string>;
  lPath: string;
  lEntry: TTriageItem;
begin
  lTop := aPolicy.fTop;
  if lTop <= 0 then
    lTop := 20;
  lInclude := SplitSemicolonPatterns(aPolicy.fIncludePaths);
  lExclude := SplitSemicolonPatterns(aPolicy.fExcludePaths);
  lFiItems := TList<TTriageItem>.Create;
  lPalItems := TList<TTriageItem>.Create;
  lLines := TList<string>.Create;
  lFiRecords := TList<TJSONObject>.Create;
  lPalRecords := TList<TJSONObject>.Create;
  try
    if aFixInsight <> nil then
      for lItem in aFixInsight do
        if AnalysisRecordIsActionable(TJSONObject(lItem)) then
          lFiRecords.Add(TJSONObject(lItem));
    if aPal <> nil then
      for lItem in aPal do
        if AnalysisRecordIsActionable(TJSONObject(lItem)) then
          lPalRecords.Add(TJSONObject(lItem));
    for lRow in lFiRecords do
    begin
      lTriage := Default(TTriageItem);
      lTriage.fPath := OrDefault(OrDefault(RowText(lRow, 'path'), RowText(lRow, 'file')), '?');
      if not TriagePathAllowed(lTriage.fPath, lInclude, lExclude) then
        Continue;
      lTriage.fKind := Trim(RowText(lRow, 'kind'));
      lTriage.fPriority := FixInsightPriority(lTriage.fKind);
      lTriage.fCode := OrDefault(RowText(lRow, 'code'), '?');
      lTriage.fOwnership := OrDefault(RowText(lRow, 'ownership'), 'unknown');
      lTriage.fLine := OrDefault(RowText(lRow, 'line'), '?');
      lTriage.fLineNumber := TriageLineNumber(lTriage.fLine);
      lTriage.fCol := OrDefault(RowText(lRow, 'col'), '?');
      lTriage.fMessage := RowText(lRow, 'message');
      lFiItems.Add(lTriage);
    end;
    lFiItems.Sort(TComparer<TTriageItem>.Construct(
      function(const aLeft, aRight: TTriageItem): Integer
      begin
        Result := CompareTriage(aLeft, aRight, False);
      end));
    for lRow in lPalRecords do
    begin
      lTriage := Default(TTriageItem);
      lTriage.fSeverity := Trim(RowText(lRow, 'severity'));
      lTriage.fPath := OrDefault(OrDefault(RowText(lRow, 'path'), RowText(lRow, 'module')), '?');
      if not TriagePathAllowed(lTriage.fPath, lInclude, lExclude) then
        Continue;
      lTriage.fSection := RowText(lRow, 'section');
      lTriage.fMessage := RowText(lRow, 'message');
      lTriage.fPriority := PalItemPriority(lTriage.fSeverity, RowText(lRow, 'report'), lTriage.fSection,
        lTriage.fMessage, aPolicy.fPalIncludeCallTree);
      lTriage.fOwnership := OrDefault(RowText(lRow, 'ownership'), 'unknown');
      lTriage.fModule := OrDefault(RowText(lRow, 'module'), '?');
      lTriage.fLine := OrDefault(RowText(lRow, 'line'), '?');
      lTriage.fLineNumber := TriageLineNumber(lTriage.fLine);
      lPalItems.Add(lTriage);
    end;
    lPalItems.Sort(TComparer<TTriageItem>.Construct(
      function(const aLeft, aRight: TTriageItem): Integer
      begin
        Result := CompareTriage(aLeft, aRight, True);
      end));
    lFiTop := Copy(lFiItems.ToArray, 0, Min(lTop, lFiItems.Count));
    lPalTop := Copy(lPalItems.ToArray, 0, Min(lTop, lPalItems.Count));
    lLines.Add('# ' + aTitle + ' triage');
    lLines.Add('');
    lLines.Add('- Timestamp: ' + AnalysisUtcNowIso);
    lLines.Add(Format('- FixInsight findings: %d (eligible %d, showing top %d)',
      [lFiRecords.Count, lFiItems.Count, Min(lTop, lFiItems.Count)]));
    lLines.Add(Format('- Pascal Analyzer findings: %d (eligible %d, showing top %d)',
      [lPalRecords.Count, lPalItems.Count, Min(lTop, lPalItems.Count)]));
    lOwnership := AnalysisOwnershipCounts([lFiRecords, lPalRecords]);
    try
      lLines.Add('- Ownership: ' + AnalysisOwnershipText(lOwnership));
    finally
      lOwnership.Free;
    end;
    lLines.Add('');
    lLines.Add('## FixInsight');
    if Length(lFiTop) = 0 then
    begin
      lLines.Add('No FixInsight findings.');
      lLines.Add('');
    end else begin
      EmitKind('W', 'W findings (defects)', KindItems('W'));
      EmitKind('C', 'C findings (maintainability)', KindItems('C'));
      EmitKind('O', 'O findings (hygiene)', KindItems('O'));
      if Length(KindItems('other')) > 0 then
        EmitKind('other', 'Other findings', KindItems('other'));
    end;
    lLines.Add('## Pascal Analyzer');
    if Length(lPalTop) = 0 then
    begin
      lLines.Add('No Pascal Analyzer findings.');
      lLines.Add('');
    end else begin
      lGroups := TObjectDictionary<string, TList<TTriageItem>>.Create([doOwnsValues]);
      lOrder := TList<string>.Create;
      try
        for lEntry in lPalTop do
        begin
          if not lGroups.ContainsKey(lEntry.fPath) then
          begin
            lGroups.Add(lEntry.fPath, TList<TTriageItem>.Create);
            lOrder.Add(lEntry.fPath);
          end;
          lGroups[lEntry.fPath].Add(lEntry);
        end;
        for lPath in lOrder do
        begin
          lLines.Add('### `' + lPath + '`');
          for lEntry in lGroups[lPath] do
            lLines.Add('- [' + lEntry.fSeverity + '] [' + lEntry.fOwnership + '] ' + lEntry.fLine + ' - ' +
              lEntry.fSection + ': ' + lEntry.fMessage);
          lLines.Add('');
        end;
      finally
        lOrder.Free;
        lGroups.Free;
      end;
    end;
    Result := String.Join(#10, lLines.ToArray).TrimRight + #10;
    aFiTop := lFiTop;
    aPalTop := lPalTop;
  finally
    lPalRecords.Free;
    lFiRecords.Free;
    lLines.Free;
    lPalItems.Free;
    lFiItems.Free;
  end;
end;

function WriteAnalysisTriage(const aOutRoot, aTitle: string; aFixInsight, aPal: TJSONArray;
  const aPolicy: TAnalysisTriagePolicy): string;
var
  lFiTop, lPalTop: TArray<TTriageItem>;
begin
  Result := TPath.Combine(aOutRoot, 'triage.md');
  WriteAnalysisText(Result, RenderTriage(aTitle, aFixInsight, aPal, aPolicy, lFiTop, lPalTop));
  if aPolicy.fSnippets then
    WriteTriageSnippets(aOutRoot, aTitle, lFiTop, lPalTop);
end;

function RenderAnalysisTriage(const aTitle: string; aFixInsight, aPal: TJSONArray;
  const aPolicy: TAnalysisTriagePolicy): string;
var
  lFiTop, lPalTop: TArray<TTriageItem>;
begin
  Result := RenderTriage(aTitle, aFixInsight, aPal, aPolicy, lFiTop, lPalTop);
end;

function NormalizeRelativeToRoot(const aValue, aRoot: string): string;
var
  lFull, lRoot: string;
begin
  // Absolute paths inside the workspace root become slash-separated relative paths.
  Result := '';
  if (aValue = '') or (aRoot = '') then
    Exit;
  lFull := TPath.GetFullPath(aValue.Replace('/', '\'));
  lRoot := IncludeTrailingPathDelimiter(TPath.GetFullPath(aRoot));
  if lFull.StartsWith(lRoot, True) then
    Result := lFull.Substring(Length(lRoot)).Replace('\', '/');
end;

function WriteAnalysisTriageChanged(const aOutRoot, aTitle: string; aSummary: TJSONObject;
  aFixInsight, aPal: TJSONArray; const aWorkspaceFiles: TArray<string>): string;
var
  lChanged: TDictionary<string, string>;
  lChangedSorted: TArray<string>;
  lFiItems, lPalItems: TList<string>;
  lItem: TJSONValue;
  lLines: TList<string>;
  lMatched, lNorm, lRepoRoot, lUnitName, lVcs, lValue: string;
  lRow, lTarget: TJSONObject;
  lUnique: TDictionary<string, string>;
  lFile: string;
  lSeen: TDictionary<string, Boolean>;
  lChangedFiles: TJSONArray;
  lDisplay: string;
begin
  Result := TPath.Combine(aOutRoot, 'triage-changed.md');
  lTarget := JsonObjectMember(JsonObjectMember(aSummary, 'provenance'), 'target');
  if lTarget = nil then
  begin
    WriteAnalysisText(Result, '# ' + aTitle + ' (changed files)' + #10#10 +
      'Git repo not found; cannot compute changed-file scope.' + #10);
    Exit;
  end;
  lRepoRoot := JsonText(lTarget, 'root');
  if lRepoRoot <> '' then
    lRepoRoot := TPath.GetFullPath(lRepoRoot);
  lVcs := OrDefaultText(JsonText(lTarget, 'vcs'), 'none');
  lChangedFiles := JsonArrayMember(lTarget, 'changed_files');
  if (lVcs = 'none') and ((lTarget.GetValue('changed_files') = nil) or (lTarget.GetValue('changed_files') is TJSONNull)) then
  begin
    WriteAnalysisText(Result, '# ' + aTitle + ' (changed files)' + #10#10 + 'No-VCS changed-file scope is not applicable.' + #10);
    Exit;
  end;
  if (lRepoRoot = '') or (lChangedFiles = nil) then
  begin
    WriteAnalysisText(Result, '# ' + aTitle + ' (changed files)' + #10#10 + lVcs.ToUpperInvariant +
      ' changed-file scope unavailable: ' + OrDefaultText(JsonText(lTarget, 'diagnostic'), 'metadata unavailable') + '.' + #10);
    Exit;
  end;
  lChanged := TDictionary<string, string>.Create;
  lLines := TList<string>.Create;
  lFiItems := TList<string>.Create;
  lPalItems := TList<string>.Create;
  lUnique := TDictionary<string, string>.Create;
  lSeen := TDictionary<string, Boolean>.Create;
  try
    for lItem in lChangedFiles do
    begin
      lValue := lItem.Value.Replace('\', '/');
      lChanged.AddOrSetValue(lValue.ToLowerInvariant, lValue);
    end;
    lChangedSorted := lChanged.Values.ToArray;
    TArray.Sort<string>(lChangedSorted, TStringComparer.Ordinal);
    lLines.Add('# ' + aTitle + ' (changed files)');
    lLines.Add('');
    lLines.Add('- Timestamp: ' + AnalysisUtcNowIso);
    lLines.Add('- VCS: `' + lVcs + '`');
    lLines.Add('- Workspace root: `' + lRepoRoot + '`');
    lLines.Add('- Changed files: ' + IntToStr(Length(lChangedSorted)));
    lLines.Add('');
    if Length(lChangedSorted) = 0 then
    begin
      lLines.Add('No ' + lVcs.ToUpperInvariant + '-changed files detected.');
      lLines.Add('');
      WriteAnalysisText(Result, String.Join(#10, lLines.ToArray).TrimRight + #10);
      Exit;
    end;
    lLines.Add('## Changed files');
    for lValue in lChangedSorted do
      lLines.Add('- `' + lValue + '`');
    lLines.Add('');
    if aFixInsight <> nil then
      for lItem in aFixInsight do
      begin
        lRow := TJSONObject(lItem);
        if not AnalysisRecordIsActionable(lRow) then
          Continue;
        lNorm := Trim(RowText(lRow, 'path')).Replace('\', '/');
        if lNorm = '' then
          lNorm := NormalizeRelativeToRoot(Trim(RowText(lRow, 'file')), lRepoRoot);
        if (lNorm <> '') and (lNorm.StartsWith('/') or StartsWithDriveLetter(lNorm, True)) then
        begin
          lValue := NormalizeRelativeToRoot(lNorm, lRepoRoot);
          if lValue <> '' then
            lNorm := lValue;
        end;
        if (lNorm = '') or not lChanged.ContainsKey(lNorm.ToLowerInvariant) or (lChanged[lNorm.ToLowerInvariant] <> lNorm) then
          Continue;
        lFiItems.Add('[' + OrDefaultText(RowText(lRow, 'code'), '?') + '] ' + lNorm + ':' +
          OrDefaultText(RowText(lRow, 'line'), '?') + ':' + OrDefaultText(RowText(lRow, 'col'), '?') + ' - ' +
          RowText(lRow, 'message'));
      end;
    // Unique basename index of the workspace inventory for module-only PAL rows.
    for lFile in aWorkspaceFiles do
    begin
      lUnitName := TPath.GetFileName(lFile).ToLowerInvariant;
      lDisplay := NormalizeRelativeToRoot(lFile, lRepoRoot);
      if lDisplay = '' then
        lDisplay := lFile.Replace('\', '/');
      if lSeen.ContainsKey(lUnitName) then
      begin
        if lUnique.ContainsKey(lUnitName) and not SameText(lUnique[lUnitName], lDisplay) then
          lUnique.Remove(lUnitName);
      end else begin
        lSeen.Add(lUnitName, True);
        lUnique.Add(lUnitName, lDisplay);
      end;
    end;
    if aPal <> nil then
      for lItem in aPal do
      begin
        lRow := TJSONObject(lItem);
        if not AnalysisRecordIsActionable(lRow) then
          Continue;
        if Trim(RowText(lRow, 'module')) = '' then
          Continue;
        lNorm := Trim(RowText(lRow, 'path')).Replace('\', '/');
        lMatched := '';
        if lNorm <> '' then
        begin
          if lNorm.StartsWith('/') or StartsWithDriveLetter(lNorm, True) then
            lNorm := NormalizeRelativeToRoot(lNorm, lRepoRoot);
          if (lNorm <> '') and lChanged.ContainsKey(lNorm.ToLowerInvariant) then
            lMatched := lChanged[lNorm.ToLowerInvariant];
        end else begin
          lUnitName := TPath.GetFileName(Trim(RowText(lRow, 'module')).Replace('\', '/'));
          if not lUnitName.ToLowerInvariant.EndsWith('.pas') then
            lUnitName := lUnitName + '.pas';
          if lUnique.TryGetValue(lUnitName.ToLowerInvariant, lValue) and lChanged.ContainsKey(lValue.ToLowerInvariant) then
            lMatched := lChanged[lValue.ToLowerInvariant];
        end;
        if lMatched = '' then
          Continue;
        lPalItems.Add('[' + RowText(lRow, 'section') + '] ' + lMatched + ':' + OrDefaultText(RowText(lRow, 'line'), '?') +
          ' - ' + RowText(lRow, 'message'));
      end;
    lLines.Add('## FixInsight (changed files)');
    lLines.Add('- Findings: ' + IntToStr(lFiItems.Count));
    for lValue in Copy(lFiItems.ToArray, 0, Min(200, lFiItems.Count)) do
      lLines.Add('- ' + lValue);
    lLines.Add('');
    lLines.Add('## Pascal Analyzer (changed files)');
    lLines.Add('- Findings: ' + IntToStr(lPalItems.Count));
    for lValue in Copy(lPalItems.ToArray, 0, Min(200, lPalItems.Count)) do
      lLines.Add('- ' + lValue);
    lLines.Add('');
    WriteAnalysisText(Result, String.Join(#10, lLines.ToArray).TrimRight + #10);
  finally
    lSeen.Free;
    lUnique.Free;
    lPalItems.Free;
    lFiItems.Free;
    lLines.Free;
    lChanged.Free;
  end;
end;

end.
