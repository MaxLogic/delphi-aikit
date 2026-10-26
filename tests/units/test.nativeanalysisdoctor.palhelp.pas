unit Test.NativeAnalysisDoctor.PalHelp;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Slow')]
  TPalHelpTests = class
  public
    [Test]
    procedure LegacyHelpReportsVersionArchitectureAndTargets;
    [Test]
    procedure TargetsRetainCanonicalOrderAndExactMembership;
    [Test]
    procedure UnknownBannerAndUnavailableSyntaxRemainIndependent;
    [Test]
    procedure VersionParsingRetainsLegacyBannerGrammar;
    [Test]
    procedure DoctorFlagsRequireLineStartAndWordBoundary;
    [TestCase('EmptyText', ',/CD12W64,false')]
    [TestCase('EmptyFlag', '/CD12W64,,false')]
    [TestCase('Exact', '/CD12W64,/CD12W64,true')]
    [TestCase('CaseInsensitive', '/cd12w64,/CD12W64,true')]
    [TestCase('Inline', 'Use /CD12W64 now,/CD12W64,true')]
    [TestCase('LeftLetter', 'X/CD12W64,/CD12W64,false')]
    [TestCase('RightDigit', '/CD12W640,/CD12W64,false')]
    [TestCase('Underscores', '_/CD12W64_,/CD12W64,true')]
    [TestCase('LaterValidMatch', '/CD12W640 /CD12W64,/CD12W64,true')]
    procedure NativeFlagBoundariesRemainCompatible(const aText, aFlag: string; aExpected: Boolean);
  end;

implementation

uses
  Dak.PascalAnalyzer.Help;

procedure TPalHelpTests.LegacyHelpReportsVersionArchitectureAndTargets;
var
  lInfo: TPalHelpInfo;
begin
  // Port of test_doctor.py:test_pal_help_reports_version_architecture_and_supported_targets.
  lInfo := ParsePalHelp('Pascal Analyzer (64-bits) version 9.21.3.0' + #10 +
    'Syntax: PALCMD [options] project-file' + #10 +
    '  /CD12W64  Emulate Delphi 12 Win64' + #10 +
    '  /CD13W64  Emulate Delphi 13 Win64' + #10);
  Assert.AreEqual('9.21.3.0', lInfo.fVersion);
  Assert.AreEqual('64-bit', lInfo.fArchitecture);
  Assert.IsTrue(lInfo.fHelpAvailable);
  Assert.AreEqual<NativeInt>(2, Length(lInfo.fSupportedFlags));
  Assert.AreEqual('/CD12W64', lInfo.fSupportedFlags[0]);
  Assert.AreEqual('/CD13W64', lInfo.fSupportedFlags[1]);
end;

procedure TPalHelpTests.TargetsRetainCanonicalOrderAndExactMembership;
var
  lInfo: TPalHelpInfo;
begin
  lInfo := ParsePalHelp('/CD13W64' + #10 + '/cd12w64' + #10 + '/CD13W32' + #10 +
    '/CD12W32' + #10 + '/CD12W32');
  Assert.AreEqual<NativeInt>(4, Length(lInfo.fSupportedFlags));
  Assert.AreEqual('/CD12W32', lInfo.fSupportedFlags[0]);
  Assert.AreEqual('/CD12W64', lInfo.fSupportedFlags[1]);
  Assert.AreEqual('/CD13W32', lInfo.fSupportedFlags[2]);
  Assert.AreEqual('/CD13W64', lInfo.fSupportedFlags[3]);
  Assert.IsTrue(PalHelpSupportsTarget(lInfo, '/CD13W32'));
  Assert.IsFalse(PalHelpSupportsTarget(lInfo, '/cd13w32'));
  Assert.IsFalse(PalHelpSupportsTarget(lInfo, '/CD14W64'));
  Assert.IsFalse(PalHelpSupportsTarget(lInfo, ''));
end;

procedure TPalHelpTests.UnknownBannerAndUnavailableSyntaxRemainIndependent;
var
  lInfo: TPalHelpInfo;
begin
  lInfo := ParsePalHelp('');
  Assert.AreEqual('unknown', lInfo.fVersion);
  Assert.AreEqual('unknown', lInfo.fArchitecture);
  Assert.IsFalse(lInfo.fHelpAvailable);
  Assert.AreEqual<NativeInt>(0, Length(lInfo.fSupportedFlags));
  lInfo := ParsePalHelp('Syntax: available without banner');
  Assert.IsTrue(lInfo.fHelpAvailable);
  Assert.AreEqual('unknown', lInfo.fVersion);
  lInfo := ParsePalHelp('Pascal Analyzer (32-bits) version 9.21.3.0' + #10 + 'syntax: lowercase');
  Assert.AreEqual('32-bit', lInfo.fArchitecture);
  Assert.AreEqual('9.21.3.0', lInfo.fVersion);
  Assert.IsFalse(lInfo.fHelpAvailable);
end;

procedure TPalHelpTests.VersionParsingRetainsLegacyBannerGrammar;
var
  lInfo: TPalHelpInfo;
begin
  lInfo := ParsePalHelp('PASCAL ANALYZER' + #9 + '(64-bits)' + #10 + 'VERSION 9.21..3.beta');
  Assert.AreEqual('64-bit', lInfo.fArchitecture);
  Assert.AreEqual('9.21..3.', lInfo.fVersion);
  lInfo := ParsePalHelp('Pascal Analyzer (64-bit) version 9.21.3.0');
  Assert.AreEqual('unknown', lInfo.fVersion);
  Assert.AreEqual('unknown', lInfo.fArchitecture);
end;

procedure TPalHelpTests.DoctorFlagsRequireLineStartAndWordBoundary;
var
  lInfo: TPalHelpInfo;
begin
  lInfo := ParsePalHelp('Inline /CD12W32' + #10 + '/CD12W64_extra' + #10 +
    '/CD12W64' + #$017C + #10 +
    '/CD13W320' + #10 + #9 + '/cd13w64: accepted');
  Assert.AreEqual<NativeInt>(1, Length(lInfo.fSupportedFlags));
  Assert.AreEqual('/CD13W64', lInfo.fSupportedFlags[0]);
  // The runner deliberately has different boundaries from the legacy doctor parser.
  Assert.IsTrue(PalHelpContainsFlag('/CD12W64_extra', '/CD12W64'));
end;

procedure TPalHelpTests.NativeFlagBoundariesRemainCompatible(const aText, aFlag: string; aExpected: Boolean);
begin
  Assert.AreEqual(aExpected, PalHelpContainsFlag(aText, aFlag));
end;

initialization
  TDUnitX.RegisterTestFixture(TPalHelpTests);

end.
