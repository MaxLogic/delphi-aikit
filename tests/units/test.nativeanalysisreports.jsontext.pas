unit Test.NativeAnalysisReports.JsonText;

interface

uses
  DUnitX.TestFramework;

type
  // Pinned Python 3.13.15 json.dumps oracle for Dak.Analysis.JsonText: indented sorted
  // documents, single-line JSONL rows and compact fingerprint text must match byte for byte.
  [TestFixture]
  [Category('Fast')]
  TNativeAnalysisJsonTextTests = class
  public
    [Test]
    procedure PinnedPythonCasesMatchDocumentLineAndCompact;
    [Test]
    procedure NonAsciiAndControlCharactersEscapeLikePython;
  end;

implementation

uses
  System.Hash, System.IOUtils, System.JSON, System.SysUtils,
  AutoFree,
  Dak.Analysis.JsonText,
  Test.Support;

const
  cFixtureFolder = 'tests\fixtures\native-analysis-reports';

function FixturePath(const aName: string): string;
begin
  Result := TPath.Combine(TPath.Combine(RepoRoot, cFixtureFolder), aName);
end;

function Visible(const aText: string): string;
begin
  Result := aText.Replace(#13, '<CR>').Replace(#10, '<LF>' + sLineBreak);
end;

// Escape expectations are assembled from pieces so no editor decodes them.
function Esc(const aHex: string): string;
begin
  Result := '\' + 'u' + aHex;
end;

procedure TNativeAnalysisJsonTextTests.PinnedPythonCasesMatchDocumentLineAndCompact;
var
  g: TGarbos;
  lBytes: TBytes;
  lHash: THashSHA2;
  lReceipt, lDocument, lCase: TJSONObject;
  lItem, lValue: TJSONValue;
  lSource, lLabel: string;
  lCount: Integer;
begin
  GC(lReceipt, ParseJsonObject(TFile.ReadAllText(FixturePath('json-receipt.json'), TEncoding.ASCII), 'json-receipt.json'), g);
  lBytes := TFile.ReadAllBytes(FixturePath('python-json-cases.json'));
  lHash := THashSHA2.Create;
  lHash.Update(lBytes[0], Length(lBytes));
  Assert.AreEqual((lReceipt.GetValue('python-json-cases.json') as TJSONObject).GetValue<string>('sha256'),
    lHash.HashAsString.ToLowerInvariant, 'python-json-cases.json SHA256');
  GC(lDocument, ParseJsonObject(TEncoding.ASCII.GetString(lBytes), 'python-json-cases.json'), g);
  lCount := 0;
  for lItem in lDocument.GetValue<TJSONArray>('cases') do
  begin
    lCase := lItem as TJSONObject;
    lSource := lCase.GetValue<string>('source');
    lLabel := 'case ' + IntToStr(lCount) + ' ' + lSource;
    lValue := TJSONObject.ParseJSONValue(lSource, False, True);
    try
      Assert.AreEqual(Visible(lCase.GetValue<string>('document')), Visible(TPythonJson.Document(lValue)), lLabel + ' document');
      Assert.AreEqual(Visible(lCase.GetValue<string>('line')), Visible(TPythonJson.Line(lValue)), lLabel + ' line');
      Assert.AreEqual(Visible(lCase.GetValue<string>('compact')), Visible(TPythonJson.Compact(lValue)), lLabel + ' compact');
    finally
      lValue.Free;
    end;
    Inc(lCount);
  end;
  Assert.AreEqual(16, lCount, 'pinned case count');
end;

procedure TNativeAnalysisJsonTextTests.NonAsciiAndControlCharactersEscapeLikePython;
begin
  Assert.AreEqual('"' + Esc('00df') + Esc('0130') + '"', TPythonJson.QuoteString(#$00DF#$0130), 'Latin and Turkish letters');
  Assert.AreEqual('"' + Esc('d83d') + Esc('de00') + '"', TPythonJson.QuoteString(#$D83D#$DE00), 'astral pair escapes as surrogates');
  Assert.AreEqual('"' + Esc('d800') + '"', TPythonJson.QuoteString(#$D800), 'lone surrogate escapes as-is');
  Assert.AreEqual('"' + Esc('0000') + Esc('001f') + Esc('007f') + '"', TPythonJson.QuoteString(#0#$1F#$7F), 'controls and DEL');
  Assert.AreEqual('"a\"b\\c/d"', TPythonJson.QuoteString('a"b\c/d'), 'quote, backslash and unescaped slash');
end;

initialization
  TDUnitX.RegisterTestFixture(TNativeAnalysisJsonTextTests);

end.
