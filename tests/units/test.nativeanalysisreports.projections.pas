unit Test.NativeAnalysisReports.Projections;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TNativeAnalysisProjectionTests = class
  public
    [TestCase('mask-slash-case-first', 'mask-slash-case-first')]
    [TestCase('mask-bracket-range', 'mask-bracket-range')]
    [TestCase('mask-bracket-negated', 'mask-bracket-negated')]
    [TestCase('mask-literal-bracket', 'mask-literal-bracket')]
    [TestCase('mask-range-reversed', 'mask-range-reversed')]
    [TestCase('mask-question-unicode', 'mask-question-unicode')]
    [TestCase('mask-unicode-lower', 'mask-unicode-lower')]
    [TestCase('mask-stars-cross-separators', 'mask-stars-cross-separators')]
    [TestCase('mask-first-closing-bracket', 'mask-first-closing-bracket')]
    [TestCase('mask-literal-caret', 'mask-literal-caret')]
    [TestCase('fallback-file', 'fallback-file')]
    [TestCase('stale-path-policy-cleared', 'stale-path-policy-cleared')]
    [TestCase('path-mask-overwrites-custom', 'path-mask-overwrites-custom')]
    [TestCase('custom-policy-blocks-rule-ignore', 'custom-policy-blocks-rule-ignore')]
    [TestCase('path-mask-precedes-rule-ignore', 'path-mask-precedes-rule-ignore')]
    [TestCase('ownership-precedence', 'ownership-precedence')]
    [TestCase('stale-rule-ignore-cleared', 'stale-rule-ignore-cleared')]
    [TestCase('aliases-9.21.3', 'aliases-9.21.3')]
    [TestCase('aliases-9.21.3.0', 'aliases-9.21.3.0')]
    [TestCase('aliases-9.21.4.0', 'aliases-9.21.4.0')]
    [TestCase('aliases-unknown', 'aliases-unknown')]
    [TestCase('verified-code-ignore', 'verified-code-ignore')]
    [TestCase('new-version-code-rejected', 'new-version-code-rejected')]
    [TestCase('empty-existing-code-known', 'empty-existing-code-known')]
    [TestCase('empty-existing-unknown-rejected', 'empty-existing-unknown-rejected')]
    [TestCase('missing-pal-ignore-not-validated', 'missing-pal-ignore-not-validated')]
    [TestCase('unrequested-pal-cleared', 'unrequested-pal-cleared')]
    [TestCase('canonical-collision-pairs', 'canonical-collision-pairs')]
    [TestCase('severity-fallback', 'severity-fallback')]
    [TestCase('metric-advisory-default', 'metric-advisory-default')]
    [TestCase('metric-explicit-opt-in', 'metric-explicit-opt-in')]
    [TestCase('xml-empty-section-catalog', 'xml-empty-section-catalog')]
    [TestCase('duplicates-and-stale-fields', 'duplicates-and-stale-fields')]
    [TestCase('unicode-astral-question', 'unicode-astral-question')]
    [TestCase('unicode-astral-class', 'unicode-astral-class')]
    [TestCase('unicode-dotted-capital-i', 'unicode-dotted-capital-i')]
    [TestCase('unicode-final-sigma', 'unicode-final-sigma')]
    [TestCase('unicode-long-s', 'unicode-long-s')]
    [TestCase('code-coercion-boolean', 'code-coercion-boolean')]
    [TestCase('code-coercion-float-integral', 'code-coercion-float-integral')]
    [TestCase('code-coercion-float-small', 'code-coercion-float-small')]
    [TestCase('code-coercion-float-large', 'code-coercion-float-large')]
    [TestCase('code-coercion-parsed-underflow-zero', 'code-coercion-parsed-underflow-zero')]
    [TestCase('code-coercion-negative-zero', 'code-coercion-negative-zero')]
    [TestCase('code-coercion-large-integer', 'code-coercion-large-integer')]
    [TestCase('code-coercion-list', 'code-coercion-list')]
    [TestCase('code-coercion-object', 'code-coercion-object')]
    [TestCase('code-coercion-empty-list', 'code-coercion-empty-list')]
    [TestCase('code-coercion-empty-object', 'code-coercion-empty-object')]
    [TestCase('code-coercion-sharp-s', 'code-coercion-sharp-s')]
    [TestCase('section-coercion-boolean', 'section-coercion-boolean')]
    [TestCase('section-coercion-float-integral', 'section-coercion-float-integral')]
    [TestCase('section-coercion-float-small', 'section-coercion-float-small')]
    [TestCase('section-coercion-float-large', 'section-coercion-float-large')]
    [TestCase('section-coercion-parsed-underflow-zero', 'section-coercion-parsed-underflow-zero')]
    [TestCase('section-coercion-negative-zero', 'section-coercion-negative-zero')]
    [TestCase('section-coercion-large-integer', 'section-coercion-large-integer')]
    [TestCase('section-coercion-list', 'section-coercion-list')]
    [TestCase('section-coercion-object', 'section-coercion-object')]
    [TestCase('section-coercion-empty-list', 'section-coercion-empty-list')]
    [TestCase('section-coercion-empty-object', 'section-coercion-empty-object')]
    [TestCase('section-coercion-sharp-s', 'section-coercion-sharp-s')]
    [TestCase('code-repr-quotes', 'code-repr-quotes')]
    [TestCase('code-repr-controls', 'code-repr-controls')]
    [TestCase('code-repr-astral', 'code-repr-astral')]
    [TestCase('code-repr-nested', 'code-repr-nested')]
    [TestCase('section-repr-quotes', 'section-repr-quotes')]
    [TestCase('section-repr-controls', 'section-repr-controls')]
    [TestCase('section-repr-astral', 'section-repr-astral')]
    [TestCase('section-repr-nested', 'section-repr-nested')]
    [TestCase('catalog-leading-space', 'catalog-leading-space')]
    procedure CompleteRowsMatchPinnedReference(const aCase: string);
    [TestCase('underflow-positive', '0')]
    [TestCase('underflow-negative', '1')]
    [TestCase('decimal-trailing-zero', '2')]
    [TestCase('uppercase-exponent', '3')]
    [TestCase('integral-exponent', '4')]
    [TestCase('integer-negative-zero', '5')]
    [TestCase('smallest-subnormal', '6')]
    [TestCase('smallest-normal', '7')]
    [TestCase('rounded-decimal', '8')]
    [TestCase('fixed-notation-boundary', '9')]
    [TestCase('exponent-notation-boundary', '10')]
    [TestCase('overflow-positive', '11')]
    [TestCase('overflow-negative', '12')]
    procedure RawNumbersPreserveSourceAndDeriveReferenceRules(aIndex: Integer);
  end;

implementation

uses
  System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Dak.Analysis.Findings, Dak.Analysis.Projections,
  Test.Support;

function CopyRows(aValue: TJSONValue): TJSONArray;
begin
  Result := nil;
  if aValue is TJSONArray then
    Result := TJSONObject.ParseJSONValue(aValue.ToJSON) as TJSONArray;
end;

procedure AssertRows(aExpected: TJSONValue; aActual: TJSONArray; const aMessage: string);
begin
  if aExpected is TJSONNull then
    Assert.IsNull(aActual, aMessage + ': absent input remains absent')
  else
  begin
    Assert.IsNotNull(aActual, aMessage + ': present input remains present');
    Assert.AreEqual(aExpected.ToJSON, aActual.ToJSON, aMessage);
  end;
end;

procedure TNativeAnalysisProjectionTests.CompleteRowsMatchPinnedReference(const aCase: string);
var
  i: Integer;
  lCase: TJSONObject;
  lDocument: TJSONObject;
  lError: string;
  lExpected: TJSONObject;
  lExpectedError: TJSONValue;
  lFixInsight: TJSONArray;
  lFound: Boolean;
  lItem: TJSONValue;
  lMasks: TArray<string>;
  lPair: TJSONPair;
  lPal: TJSONArray;
  lPalRoot: string;
  lPath: string;
  lPass: TJSONValue;
  lRoot: string;
begin
  lRoot := UniqueTempPath('analysis-projection-reference');
  lPalRoot := TPath.Combine(lRoot, 'pascal-analyzer');
  TDirectory.CreateDirectory(lPalRoot);
  try
    lDocument := ParseJsonObject(TFile.ReadAllText(TPath.Combine(RepoRoot,
      'tests\fixtures\native-analysis-projections\cases.json'), TEncoding.UTF8));
    try
      lFound := False;
      for lItem in lDocument.GetValue<TJSONArray>('cases') do
      begin
        lCase := lItem as TJSONObject;
        if lCase.GetValue<string>('name') <> aCase then
          Continue;
        lFound := True;
        for lPair in lCase.GetValue<TJSONObject>('xml') do
        begin
          lPath := TPath.Combine(lPalRoot, lPair.JsonString.Value.Replace('/', '\'));
          TDirectory.CreateDirectory(TPath.GetDirectoryName(lPath));
          TFile.WriteAllText(lPath, lPair.JsonValue.Value, TEncoding.UTF8);
        end;
        SetLength(lMasks, lCase.GetValue<TJSONArray>('masks').Count);
        for i := 0 to High(lMasks) do
          lMasks[i] := lCase.GetValue<TJSONArray>('masks').Items[i].Value;
        lFixInsight := CopyRows(lCase.GetValue('fi'));
        try
          lPal := CopyRows(lCase.GetValue('pal'));
          try
            i := 0;
            for lPass in lCase.GetValue<TJSONArray>('expected_passes') do
            begin
              Inc(i);
              lExpected := lPass as TJSONObject;
              lError := '';
              try
                ApplyAnalysisReportProjections(lFixInsight, lPal, lCase.GetValue<TJSONObject>('policy'),
                  lMasks, lCase.GetValue<string>('pal_version'), lPalRoot,
                  lCase.GetValue<Boolean>('pal_requested'));
              except
                on e: EConvertError do
                  lError := e.Message;
              end;
              lExpectedError := lExpected.GetValue('error');
              if lExpectedError is TJSONNull then
                Assert.AreEqual('', lError, aCase + ': unexpected error')
              else
                Assert.AreEqual(TJSONObject(lExpectedError).GetValue<string>('message'),
                  lError, aCase + ': expected validation failure');
              AssertRows(lExpected.GetValue('fi'), lFixInsight, Format('%s FI pass %d', [aCase, i]));
              AssertRows(lExpected.GetValue('pal'), lPal, Format('%s PAL pass %d', [aCase, i]));
            end;
          finally
            lPal.Free;
          end;
        finally
          lFixInsight.Free;
        end;
        Break;
      end;
      Assert.IsTrue(lFound, 'Unknown reference case: ' + aCase);
    finally
      lDocument.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TNativeAnalysisProjectionTests.RawNumbersPreserveSourceAndDeriveReferenceRules(aIndex: Integer);
var
  g: TGarbos;
  lCase, lDocument, lPolicy: TJSONObject;
  lExpected, lRows, lPal: TJSONArray;
  lPass: TJSONValue;
  lRoot, lInput, lExpectedPath: string;
begin
  lRoot := UniqueTempPath('analysis-projection-numbers');
  TDirectory.CreateDirectory(lRoot);
  try
    GC(lDocument, ParseJsonObject(TFile.ReadAllText(TPath.Combine(RepoRoot,
      'tests\fixtures\native-analysis-projections\raw-numbers.json'), TEncoding.UTF8)), g);
    lCase := lDocument.GetValue<TJSONArray>('cases').Items[aIndex] as TJSONObject;
    lInput := TPath.Combine(lRoot, 'input.jsonl');
    lExpectedPath := TPath.Combine(lRoot, 'expected.jsonl');
    TFile.WriteAllBytes(lInput, TEncoding.UTF8.GetBytes(lCase.GetValue<string>('raw_fi_jsonl')));
    GC(lRows, LoadAnalysisJsonLines(lInput), g);
    GC(lPal, TJSONArray.Create, g);
    GC(lPolicy, ParseJsonObject('{"gate_ownership":["project","repository"]}'), g);
    for lPass in lCase.GetValue<TJSONArray>('proposed_native_passes') do
    begin
      ApplyAnalysisReportProjections(lRows, lPal, lPolicy, [], '', lRoot, True);
      Assert.AreEqual(lCase.GetValue<string>('token'),
        TJSONObject(lRows.Items[0]).GetValue('code').Value, 'Source number must remain lossless');
      // T-335 preserves input tokens; expected annotations remain independently Python-derived.
      TFile.WriteAllBytes(lExpectedPath, TEncoding.UTF8.GetBytes(TJSONObject(lPass).GetValue<string>('fi_jsonl')));
      GC(lExpected, LoadAnalysisJsonLines(lExpectedPath), g);
      Assert.AreEqual(lExpected.ToJSON, lRows.ToJSON, 'Complete native rows and derived rule identity');
      Assert.AreEqual(0, lPal.Count, 'Empty PAL remains empty');
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisProjectionTests);

end.
