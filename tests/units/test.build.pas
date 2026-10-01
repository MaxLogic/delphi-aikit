unit Test.Build;

interface

uses
  System.DateUtils,
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  System.StrUtils,
  System.SysUtils,
  System.Threading,
  Winapi.Windows,
  DUnitX.TestFramework,
  maxLogic.CmdLineParams,
  maxLogic.ioutils,
  Dak.Build,
  Dak.Cli,
  Dak.ExternalToolProcess,
  Dak.Registry,
  Dak.RsVars,
  Dak.Types,
  Test.Support;

type
  TCapturingBuildRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    fArguments: string;
    fArgumentsList: TArray<string>;
    fCallCount: Integer;
    fEnvironmentBlocks: TArray<string>;
    fExitCodesByCall: TDictionary<Integer, Integer>;
    fExePaths: TArray<string>;
    fFilesToCreateOnCall: TDictionary<Integer, string>;
    destructor Destroy; override;
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
      out aTimedOut: Boolean; out aError: string): Boolean;
  end;

  TFailingBuildRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    fStdOutText: string;
    fStdErrText: string;
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
      out aTimedOut: Boolean; out aError: string): Boolean;
  end;

  // DAK-379: writes fixed logs, records whether the run directory already existed when the build started and can
  // make the later copy of stdout.log fail by putting a directory where that file belongs.
  TLogRetentionBuildRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    fBreakStdOutCopy: Boolean;
    fCallCount: Integer;
    fExitCode: Integer;
    fLogRoot: string;
    fRaise: Boolean;
    fReturnFalse: Boolean;
    fRunDirsAtStart: Integer;
    fStdErrText: string;
    fStdOutText: string;
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
      out aTimedOut: Boolean; out aError: string): Boolean;
  end;

  // DAK-372: hands the argument vector DAK generated to the machine's real MSBuild command-line parser.
  TRealMsBuildRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    fArguments: string;
    fOutput: string;
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
      out aTimedOut: Boolean; out aError: string): Boolean;
  end;

  [TestFixture]
  TBuildTests = class
  public
    [Test]
    [TestCase('Lazy streams', '1,0')]
    [TestCase('Open streams', '0,0')]
    [TestCase('Lazy streams after exception', '1,1')]
    [TestCase('Open streams after exception', '0,1')]
    procedure ConsoleCaptureRestoresTextState(aLazy, aRaise: Integer);
    [Test]
    procedure ProjectDprListsMadExceptFirstAndAllSourceUnits;
    [Test]
    procedure ExternalToolProcessCentralizesBasicCommandRunners;
    [Test]
    procedure ExternalToolTimeoutMillisecondsPreserveCardinalRange;
    [Test]
    procedure ProtocolSpecificProcessRunnersRemainDocumentedExceptions;
    [Test]
    procedure BuildResolverExe;
    [Test]
    procedure BuildCommandUsesNativeRunnerForExternalRepoProjects;
    [Test]
    procedure BuildCommandAddsEnvironmentProjPropsToMsBuildArgs;
    [Test]
    procedure BuildCommandAddsCompilerOverlaysToMsBuildArgs;
    // DAK-372: MSBuild splits an unquoted /p: value on ',' and ';' and rejects the rest with MSB1006.
    [TestCase('comma', 'comma')]
    [TestCase('semicolon', 'semicolon')]
    [TestCase('space and trailing backslash', 'space-trailing-backslash')]
    [TestCase('embedded quote', 'embedded-quote')]
    [TestCase('backslash before quote', 'backslash-before-quote')]
    [TestCase('plain trailing backslash', 'plain-trailing-backslash')]
    [TestCase('output directory with space and trailing backslash', 'output-dir')]
    procedure BuildPropertyValueSurvivesRealMsBuildParsing(const aShape: string);
    // DAK-376: environment.proj is read as text, so XML entities must be decoded before the value is forwarded.
    [TestCase('ampersand', 'ampersand')]
    [TestCase('angle brackets', 'angle-brackets')]
    [TestCase('quotes', 'quotes')]
    [TestCase('apostrophe', 'apostrophe')]
    [TestCase('numeric decimal and hex', 'numeric')]
    [TestCase('no double decoding', 'no-double-decode')]
    [TestCase('unknown entity stays literal', 'unknown-entity')]
    procedure BuildDecodesXmlEntitiesInEnvironmentProjValues(const aShape: string);
    [Test]
    procedure BuildSkipsEnvironmentProjValuesWithLineBreaksAndNamesThem;
    [Test]
    procedure BuildForwardsEveryMissingEnvironmentProjPropertyAndProcessEnvironmentWins;
    [Test]
    procedure BuildVerboseTraceRedactsEnvironmentProjValues;
    [Test]
    procedure BuildRetainsNoLogsByDefault;
    [TestCase('json', 'json')]
    [TestCase('ai', 'ai')]
    [TestCase('text', 'text')]
    procedure BuildKeepLogsRetainsRunLogsUnderProjectDak(const aMode: string);
    [Test]
    procedure BuildLogDirResolvesRelativeToProjectDirectory;
    [Test]
    procedure BuildLogDirAcceptsAbsolutePath;
    [Test]
    procedure BuildKeepLogsGivesEveryRunItsOwnDirectory;
    [Test]
    procedure BuildKeepLogsFailsBeforeBuildWhenDirectoryCannotBeCreated;
    [TestCase('failed build, json', 'json,1')]
    [TestCase('successful build, text', 'text,0')]
    procedure BuildKeepLogsReportsLogCopyFailureWithBuildResult(const aMode: string; aBuildExitCode: Integer);
    [TestCase('pipe', 'a|b')]
    [TestCase('less-than', 'a<b')]
    [TestCase('drive-relative', '\drive relative logs')]
    procedure BuildLogDirThatCannotBeUsedIsANamedFailure(const aLogDir: string);
    [Test]
    procedure BuildKeepLogsSurvivesConcurrentCreationOfAFreshRoot;
    [Test]
    procedure BuildKeepLogsReportsOnlyTheFailureWhenLogsCannotBeCopied;
    [TestCase('runner raises', 'raise')]
    [TestCase('runner fails to start', 'false')]
    procedure BuildKeepLogsRemovesTheEmptyRunDirectoryWhenTheProcessProducesNothing(const aMode: string);
    [Test]
    procedure BuildDiagnosticsDirEnvVarKeepsWorkingWithoutKeepLogs;
    [Test]
    procedure BuildAutoDetectedWebCoreRejectsKeepLogs;
    [TestCase('Polish MSBuild', 'pl,True')]
    [TestCase('English MSBuild', 'en,True')]
    [TestCase('unidentified property', 'en,False')]
    procedure BuildNamesPropertyRejectedByMsBuild(const aLocale: string; aIdentifiable: Boolean);
    [Test]
    procedure RsVarsLoaderIgnoresStaleRadEnvironmentAndOverlongPath;
    [Test]
    procedure BuildSkipsMadExceptPatchWhenMesDisablesMadExcept;
    [Test]
    procedure BuildSkipsMadExceptPatchWhenMesDisablesLinkInCode;
    [Test]
    procedure BuildSkipsMadExceptPatchWhenUtf8BomMesDisablesMadExcept;
    [Test]
    procedure BuildStillRunsMadExceptPatchWhenMesEnablesMadExcept;
    [Test]
    procedure BuildResolvesMadExceptOutputPathFromCfgDependentOnOptset;
    [Test]
    procedure BuildProjectPropertiesOverrideCfgDependentOnOptsetOutputPath;
    [Test]
    procedure BuildUsesDependencyOutputExtensionForLibraries;
    [Test]
    procedure BuildReportsProjectPropertyEvaluationFailure;
    // DAK-374: the artifact is named by the target platform's rules; a Linux64 program has no extension.
    [TestCase('Linux64 program', 'Linux64,program,MesGateCheck')]
    [TestCase('Linux64 library', 'Linux64,library,libMesGateCheck.so')]
    [TestCase('Linux64 package', 'Linux64,package,bplMesGateCheck.so')]
    [TestCase('Win64 program', 'Win64,program,MesGateCheck.exe')]
    [TestCase('Win32 library', 'Win32,library,MesGateCheck.dll')]
    [TestCase('Win32 package', 'Win32,package,MesGateCheck.bpl')]
    // dccaarm64 writes an Android program as lib<name>.so (verified on Delphi 12).
    [TestCase('Android64 program', 'Android64,program,libMesGateCheck.so')]
    procedure BuildNamesTheArtifactByPlatformRules(const aPlatform, aKind, aFileName: string);
    [Test]
    procedure BuildPrefersEvaluatedCompilerTargetsArtifactNaming;
    [Test]
    procedure BuildReportsWhyTheArtifactNameIsUnresolved;
    // DAK-375: --test-output-dir also moves unit output (DCU and object files) into <dir>\dcu.
    [TestCase('Win32', 'Win32,MesGateCheck.exe')]
    [TestCase('Linux64', 'Linux64,MesGateCheck')]
    procedure BuildTestOutputDirRedirectsUnitOutput(const aPlatform, aFileName: string);
    // DAK-374: a package goes to DCC_BplOutput, or DelphiDLLOutputPath as CodeGear.Delphi.Targets l.55 defaults it.
    [TestCase('DelphiDLLOutputPath when DCC_BplOutput is empty', 'dll-output-path')]
    [TestCase('no package directory', 'none')]
    procedure BuildResolvesPackageOutputDirectory(const aMode: string);
    // DAK-374: {$LIBSUFFIX} and {$LIBVERSION} of the main source (the compiler ignores the project's DllSuffix and
    // DllVersion) in the order of CodeGear.Delphi.Targets l.104-105.
    [TestCase('Win32 package suffix', 'Win32,package,290,,MesGateCheck290.bpl')]
    [TestCase('Win64 library suffix', 'Win64,library,_x,,MesGateCheck_x.dll')]
    // Linux64 puts the version after the extension, as dcclinux64 does ({$LIBVERSION}), unlike the targets.
    [TestCase('Linux64 library suffix and version', 'Linux64,library,_x,1.2,libMesGateCheck_x.so.1.2')]
    [TestCase('Linux64 package version', 'Linux64,package,,7,bplMesGateCheck.so.7')]
    [TestCase('Win32 library version', 'Win32,library,,1.2,MesGateCheck.1.2.dll')]
    [TestCase('Android64 library version after the extension', 'Android64,library,,3,libMesGateCheck.so.3')]
    [TestCase('program ignores the library suffix', 'Win64,program,_x,,MesGateCheck.exe')]
    procedure BuildAppliesLibrarySuffixAndVersion(const aPlatform, aKind, aSuffix, aVersion, aFileName: string);
    // DAK-381: a DllSuffix of $(Auto) is decided by the {$LIBSUFFIX} directive of the main source, as dcc does
    // (verified with dcc32 and dcclinux64 on Delphi 23.0): AUTO becomes the installed RTL package suffix, here the
    // 777 of the stand-in rtl777.bpl, a value no real Delphi uses, so the name must come from that file.
    [TestCase('Win32 package AUTO', 'Win32,package,{$LIBSUFFIX AUTO},MesGateCheck777.bpl')]
    [TestCase('Linux64 package AUTO', 'Linux64,package,{$LIBSUFFIX AUTO},bplMesGateCheck777.so')]
    [TestCase('Win64 library AUTO', 'Win64,library,{$LIBSUFFIX AUTO},MesGateCheck777.dll')]
    [TestCase('Linux64 library AUTO', 'Linux64,library,{$LIBSUFFIX AUTO},libMesGateCheck777.so')]
    [TestCase('SOSUFFIX is the same directive', 'Linux64,package,{$SOSUFFIX AUTO},bplMesGateCheck777.so')]
    [TestCase('spaced directive', 'Win32,package,{$ libsuffix  auto },MesGateCheck777.bpl')]
    // DUnitX drops single quotes from case values, so ~ stands for the quote of a literal suffix.
    [TestCase('an explicit suffix wins', 'Win32,package,{$LIBSUFFIX ~_y~},MesGateCheck_y.bpl')]
    [TestCase('no directive means no suffix', 'Win32,package,,MesGateCheck.bpl')]
    [TestCase('a commented directive is ignored', 'Win32,package,// {$LIBSUFFIX AUTO},MesGateCheck.bpl')]
    [TestCase('a program ignores the suffix', 'Win32,program,{$LIBSUFFIX AUTO},MesGateCheck.exe')]
    // DAK-374: the fixture's suffix.inc holds {$LIBSUFFIX AUTO}; a found include is read.
    [TestCase('a found include file is read', 'Win32,package,{$I suffix.inc},MesGateCheck777.bpl')]
    [TestCase('AUTO inside a brace comment is ignored', 'Win32,package,{ disabled {$LIBSUFFIX AUTO},MesGateCheck.bpl')]
    procedure BuildResolvesAutoLibrarySuffixFromTheSourceDirective(const aPlatform, aKind, aDirective,
      aFileName: string);
    // DAK-381: AUTO without exactly one installed rtl<N>.bpl is unresolved, never a guessed number.
    [TestCase('no rtl package', 'none')]
    [TestCase('two rtl packages', 'two')]
    procedure BuildReportsWhyTheAutoLibrarySuffixIsUnresolved(const aMode: string);
    // DAK-382: an evaluated DCC_ExeOutput that is not a usable path is a named reason, not an exception.
    [Test]
    procedure BuildReportsAnInvalidExeOutputAsUnresolved;
    // DAK-382: dcc names a program by the platform rules whatever DCC_DependencyCheckOutputName says (verified
    // with dcc32, dcclinux64 and dccaarm64). Old Win64 expectation: Legacy.exe, the property value.
    [TestCase('Linux64 program', 'Linux64,Legacy.exe,MesGateCheck')]
    [TestCase('Android64 program', 'Android64,Legacy.exe,libMesGateCheck.so')]
    [TestCase('Win64 program', 'Win64,Legacy.exe,MesGateCheck.exe')]
    procedure BuildIgnoresLegacyDependencyOutputName(const aPlatform, aValue, aFileName: string);
    // DAK-382: --test-output-dir also moves C++ header output and the package interface output.
    [Test]
    procedure BuildTestOutputDirAlsoRedirectsHppAndBpiOutput;
    // DAK-382: dccaarm64 writes lib<name>.so for an Android program whatever the project DllPrefix says
    // (verified: DllPrefix px gave libPrefApp.so), so the project value is not applied.
    [Test]
    procedure BuildAndroidProgramIgnoresTheProjectDllPrefix;
    // DAK-374: the compiler names an artifact after the directives of the main source (verified with dcc32,
    // dcclinux64 and dccaarm64 on Delphi 23.0). In case values ~ stands for a single quote (DUnitX drops them) and
    // | for a line break.
    [TestCase('Win32 library prefix', 'Win32,library,{$LIBPREFIX ~zz~},zzMesGateCheck.dll')]
    [TestCase('Linux64 library prefix replaces lib', 'Linux64,library,{$LIBPREFIX ~zz~},zzMesGateCheck.so')]
    [TestCase('Linux64 empty prefix', 'Linux64,library,{$LIBPREFIX ~~},MesGateCheck.so')]
    [TestCase('Linux64 package prefix replaces bpl', 'Linux64,package,{$LIBPREFIX ~zz~},zzMesGateCheck.so')]
    [TestCase('Win32 library extension', 'Win32,library,{$E ocx},MesGateCheck.ocx')]
    [TestCase('dotted extension', 'Win32,library,{$E .ocx},MesGateCheck.ocx')]
    [TestCase('EXTENSION spelling', 'Win32,library,{$EXTENSION ocx},MesGateCheck.ocx')]
    [TestCase('Linux64 library extension keeps the prefix', 'Linux64,library,{$E ocx},libMesGateCheck.ocx')]
    [TestCase('Win32 package extension', 'Win32,package,{$E xpl},MesGateCheck.xpl')]
    [TestCase('Linux64 package extension', 'Linux64,package,{$E xpl},bplMesGateCheck.xpl')]
    [TestCase('Win32 program extension', 'Win32,program,{$E scr},MesGateCheck.scr')]
    [TestCase('Linux64 program extension', 'Linux64,program,{$E scr},MesGateCheck.scr')]
    [TestCase('Android64 program extension', 'Android64,program,{$E scr},libMesGateCheck.scr')]
    [TestCase('Win32 all directives',
      'Win32,library,{$LIBPREFIX ~zz~}|{$LIBSUFFIX ~_s~}|{$LIBVERSION ~3.4~}|{$E ocx},zzMesGateCheck_s.3.4.ocx')]
    [TestCase('Linux64 all directives',
      'Linux64,library,{$LIBPREFIX ~zz~}|{$LIBSUFFIX ~_s~}|{$LIBVERSION ~3.4~}|{$E ocx},zzMesGateCheck_s.ocx.3.4')]
    [TestCase('Win32 package directives',
      'Win32,package,{$LIBPREFIX ~zz~}|{$LIBSUFFIX ~_s~}|{$LIBVERSION ~3.4~},zzMesGateCheck_s.3.4.bpl')]
    [TestCase('SO aliases',
      'Linux64,library,{$SOPREFIX ~zz~}|{$SOSUFFIX ~_s~}|{$SOVERSION ~3.4~},zzMesGateCheck_s.so.3.4')]
    [TestCase('Android64 program takes prefix and suffix',
      'Android64,program,{$LIBPREFIX ~zz~}|{$LIBSUFFIX ~_s~},zzMesGateCheck_s.so')]
    [TestCase('Android64 program ignores the version', 'Android64,program,{$LIBVERSION ~3.4~},libMesGateCheck.so')]
    [TestCase('Win32 program ignores prefix and suffix',
      'Win32,program,{$LIBPREFIX ~zz~}|{$LIBSUFFIX ~_s~}|{$LIBVERSION ~3.4~},MesGateCheck.exe')]
    [TestCase('Linux64 program ignores prefix', 'Linux64,program,{$LIBPREFIX ~zz~},MesGateCheck')]
    // DAK-374 repair 1: the scanner reads in source order like the compiler. Each shape was compiled with dcc32:
    // ppSameLine_s.dll, BlockCmt.dll, IncOrder_main.dll, IncAfter_inc.dll, StrLit.dll (naming.inc, written by the
    // test, holds {$LIBSUFFIX ~_inc~}). Old results: ppSameLine.dll, BlockCmt_old.9.dll, IncOrder_inc.dll, none for
    // StrLit (unresolved).
    [TestCase('two directives on one line', 'Win32,library,{$LIBPREFIX ~pp~} {$LIBSUFFIX ~_s~},ppMesGateCheck_s.dll')]
    [TestCase('Linux64 two directives on one line',
      'Linux64,library,{$LIBPREFIX ~pp~} {$LIBSUFFIX ~_s~},ppMesGateCheck_s.so')]
    [TestCase('directives in block comments',
      'Win32,library,(* {$LIBSUFFIX ~_old~} *)|{ disabled {$LIBVERSION ~9~},MesGateCheck.dll')]
    [TestCase('AUTO inside a brace comment', 'Win32,library,{ disabled {$LIBSUFFIX AUTO},MesGateCheck.dll')]
    [TestCase('a directive inside a string literal',
      'Win32,library,const S = ~{$LIBSUFFIX ~~_str~~}~;,MesGateCheck.dll')]
    [TestCase('include then directive', 'Win32,library,{$I naming.inc}|{$LIBSUFFIX ~_main~},MesGateCheck_main.dll')]
    [TestCase('directive then include', 'Win32,library,{$LIBSUFFIX ~_main~}|{$I naming.inc},MesGateCheck_inc.dll')]
    [TestCase('Linux64 include then directive',
      'Linux64,library,{$I naming.inc}|{$LIBSUFFIX ~_main~},libMesGateCheck_main.so')]
    procedure BuildTakesNamingFromTheSourceDirectives(const aPlatform, aKind, aDirectives, aFileName: string);
    // DAK-374: the project's DllPrefix, DllSuffix, DllVersion and DCC_DependencyCheckOutputName are mirrors the
    // compiler ignores. Old expectations: pxMesGateCheck.dll, MesGateCheck_x.bpl, MesGateCheck.9.dll,
    // libMesGateCheck.so.9 and MesGateCheck.ocx; the compiler wrote the names below.
    [TestCase('DllPrefix Win32', 'Win32,library,<DllPrefix>px</DllPrefix>,MesGateCheck.dll')]
    [TestCase('DllPrefix Linux64', 'Linux64,library,<DllPrefix>px</DllPrefix>,libMesGateCheck.so')]
    [TestCase('DllSuffix package', 'Win32,package,<DllSuffix>_x</DllSuffix>,MesGateCheck.bpl')]
    [TestCase('DllVersion Win32', 'Win32,library,<DllVersion>9</DllVersion>,MesGateCheck.dll')]
    [TestCase('DllVersion Linux64', 'Linux64,library,<DllVersion>9</DllVersion>,libMesGateCheck.so')]
    [TestCase('DependencyCheckOutputName ocx',
      'Win32,library,<DCC_DependencyCheckOutputName>MesGateCheck.ocx</DCC_DependencyCheckOutputName>,MesGateCheck.dll')]
    procedure BuildIgnoresProjectNamingMirrors(const aPlatform, aKind, aProperty, aFileName: string);
    // DAK-374: a directive in a form DAK does not evaluate, or a main source it cannot read, is a named reason.
    [TestCase('unquoted prefix', '{$LIBPREFIX zz},LIBPREFIX')]
    [TestCase('unquoted version', '{$LIBVERSION AUTO},LIBVERSION')]
    [TestCase('extension without a value', '{$E},naming directive')]
    procedure BuildReportsAnUnsupportedNamingDirective(const aDirective, aReasonPart: string);
    [Test]
    procedure BuildReportsAnUnreadableMainSourceAsUnresolved;
    // DAK-382: an evaluated MainSource that is not a usable path is a named reason, not an exception.
    [Test]
    procedure BuildReportsAnInvalidMainSourceAsUnresolved;
    // DAK-374: dccaarm64 writes an Android package as a static lib<name>.a into DCC_DcpOutput and ignores the naming
    // directives (verified: dcp\Android64\libPrefPkg.a for {$LIBPREFIX 'zz'}). Old expectation: bpl\Android64\...
    [Test]
    procedure BuildPlacesAnAndroidPackageInTheDcpOutput;
    // DAK-374: an include DAK cannot find (Jedi.inc on a search path) does not make the name unknown: the name
    // assumes no directive in it and carries a note. The default-named file exists: status ok, note kept.
    [TestCase('program', 'program,MesGateCheck.exe')]
    [TestCase('library', 'library,MesGateCheck.dll')]
    procedure BuildKeepsTheNameWithANoteWhenAnIncludeCannotBeRead(const aKind, aFileName: string);
    // The compiler would have taken a suffix from that include: the default-named file does not exist, so the
    // status is output_missing and the message names the include.
    [Test]
    procedure BuildReportsOutputMissingNamingTheUnreadIncludeWhenTheAssumedFileIsAbsent;
    // DAK-374 repair 1: the IDE's "Target file extension" (OutputExt) reaches dcc for programs and libraries; {$E}
    // wins over it; a package ignores it; the targets put a dot in front of the value, so ".ocx" gives "..ocx"
    // (verified with dcc32, dcclinux64 and dccaarm64 on Delphi 23.0: OextApp.scr, libOextLib.ocx, OextBoth.cpl,
    // OextPkg.bpl, OextDot..ocx). Old expectation for each: the platform default extension.
    [TestCase('Win32 program', 'Win32,program,scr,,MesGateCheck.scr')]
    [TestCase('Linux64 program', 'Linux64,program,scr,,MesGateCheck.scr')]
    [TestCase('Android64 program', 'Android64,program,scr,,libMesGateCheck.scr')]
    [TestCase('Win32 library', 'Win32,library,ocx,,MesGateCheck.ocx')]
    [TestCase('Linux64 library', 'Linux64,library,ocx,,libMesGateCheck.ocx')]
    [TestCase('E directive wins', 'Win32,program,scr,{$E cpl},MesGateCheck.cpl')]
    [TestCase('package ignores it', 'Win32,package,xpl,,MesGateCheck.bpl')]
    [TestCase('dotted value keeps the dot', 'Win32,library,.ocx,,MesGateCheck..ocx')]
    procedure BuildHonoursTheProjectOutputExt(const aPlatform, aKind, aOutputExt, aDirectives, aFileName: string);
    // DAK-374 repair 1: madExceptPatch patches Windows binaries. A project whose madExcept define and .mes also
    // apply to Linux64 or Android64 must not have an ELF or .so handed to it; the skip is named with --verbose.
    [TestCase('Linux64', 'Linux64,MesGateCheck')]
    [TestCase('Android64', 'Android64,libMesGateCheck.so')]
    procedure BuildDoesNotPatchNonWindowsOutputWithMadExcept(const aPlatform, aFileName: string);
    // DAK-374 repair 1: with the compiler targets imported, the evaluated OutputExt already carries the dot the
    // targets put in front of it (CodeGear.Delphi.Targets l.91-94: the platform default, or the project's value
    // behind a dot). The name must not get a second dot: real dcc32 wrote MesGate.dll, not MesGate..dll.
    [TestCase('platform default', ',dlMesGateCheck.sox.4')]
    [TestCase('project value', 'ocx,dlMesGateCheck.ocx.4')]
    [TestCase('dotted project value', '.ocx,dlMesGateCheck..ocx.4')]
    procedure BuildReadsOutputExtThatTheTargetsAlreadyDotted(const aOutputExt, aFileName: string);
    // DAK-374: a --test-output-dir that cannot be used is a named failure before the build starts.
    [TestCase('pipe', 'a|b')]
    [TestCase('less-than', 'a<b')]
    [TestCase('root-relative', '\drive relative out')]
    [TestCase('drive-relative', 'D:relative out')]
    // --project rejects a '/' path other than /mnt/<drive>/, so a forward-slash UNC form is rejected here too.
    [TestCase('forward-slash UNC', '//server/share/out')]
    procedure BuildTestOutputDirThatCannotBeUsedIsANamedFailure(const aOutputDir: string);
    // A UNC path does not depend on the working directory; --project accepts it, and so must --test-output-dir.
    [Test]
    procedure BuildTestOutputDirAcceptsUncPath;
    // DAK-374: text mode must not print an empty output path when the name is unresolved.
    [Test]
    procedure BuildTextReportsUnresolvedNameWithoutBlankPath;
    [Test]
    procedure BuildTestOutputDirFailureExitsNonzeroFromCli;
    [Test]
    procedure BuildReportsSpecificErrorWhenResolvedMadExceptOutputIsMissing;
    [Test]
    procedure BuildDfmCheckFailureReportsSkippedValidationAndMadExceptGuidance;
    [Test]
    procedure BuildDfmCheckRunsAfterSuccessfulSourceBuildWhenPostBuildPatchFails;
    [Test]
    procedure BuildIgnoresMissingCfgDependentOnOptsetWhenProjectOutputExists;
    [Test]
    procedure BuildWarnsOnInvalidDiagnosticsIniValues;
    [Test]
    procedure BuildWarnsWhenWin64NamespacesOmitWinapi;
    [Test]
    procedure BuildSummaryIncludesResolvedSourceContextForErrors;
    [Test]
    procedure ParseBuildLogsExposesStructuredDiagnostics;
    [Test]
    procedure BuildEnrichmentPolicyPrefersHoverForTypeErrors;
    [Test]
    procedure BuildEnrichmentPolicyPrefersDefinitionForSymbolMismatch;
    [Test]
    procedure BuildEnrichmentHelperFallsBackSilently;
    [Test]
    procedure BuildWebCoreCompilerResolutionPrefersCliOverDakIni;
    [Test]
    procedure BuildWebCoreCompilerResolutionUsesDakIniWhenCliMissing;
    [Test]
    procedure BuildWebCoreCompilerResolutionUsesEnvVarWhenDakIniMissing;
    [Test]
    procedure BuildWebCoreCompilerResolutionUsesPathWhenConfigMissing;
    [Test]
    procedure BuildWebCoreCompilerResolutionDoesNotProbeFixedPaths;
    [Test]
    procedure BuildWebCoreMissingCompilerReportsSupportedSources;
    [Test]
    procedure BuildWebCoreUsesCompilerFromCli;
    [Test]
    procedure BuildWebCoreRunsDebugPatchHook;
    [Test]
    procedure BuildWebCoreSkipsPatchHookOutsideDebug;
    [Test]
    procedure BuildWebCoreNoPwaOmitsPwaArgument;
    [Test]
    procedure BuildAutoDetectedWebCoreRejectsCompilerOverlays;
    [Test]
    procedure BuildWebCoreAiBuildEmitsSuccessSummary;
    [Test]
    procedure BuildWebCorePlainBuildEmitsOutputPath;
    [Test]
    procedure BuildWebCoreJsonBuildEmitsSummary;
    [Test]
    procedure BuildAutoFallsBackToDelphiWhenWebCoreProbeNeedsEnvironment;
    [Test]
    procedure IdeConfigFallsBackToEnvOptionsWin64Alias;
    [Test]
    procedure ParseBuildLogsAppliesIgnoreAndExcludeFilters;
    // T-264: a real Win64 build whose DPR file name differs from its program identifier.
    [TestCase('file-name', 'False')]
    [TestCase('wrong-prediction', 'True')]
    procedure BuildReportsTheExecutableTheCompilerEmitted(aForceWrongPrediction: Boolean);
    [TestCase('empty target', 'False')]
    [TestCase('reserved directory', 'True')]
    procedure NativeBuildOutputContracts(aReservedDirectory: Boolean);
    [Test]
    procedure NativeBuildPreservesMsBuildFailure;
    [TestCase('Win64', 'Win64,none,1')]
    [TestCase('Win32', 'Win32,none,1')]
    [TestCase('warning and hint codes', 'Win64,codes,0')]
    [TestCase('source exclusion', 'Win64,source,0')]
    [TestCase('unmatched filters', 'Win64,unmatched,1')]
    procedure NativeBuildWarningSummary(const aPlatform, aFilter: string; aExpected: Integer);
    [Test]
    procedure NativeConcurrentBuildsKeepOutputsAndDiagnosticsSeparate;
    [TestCase('fixture ini', 'ini,False')]
    [TestCase('fixture xml', 'xml,False')]
    [TestCase('fixture bat', 'bat,False')]
    [TestCase('self ini', 'ini,True')]
    [TestCase('self xml', 'xml,True')]
    [TestCase('self bat', 'bat,True')]
    procedure NativeResolverWritesFormats(const aFormat: string; aSelf: Boolean);
  end;

implementation

uses
  Dak.Build.Enrichment, Dak.Build.Runner;

procedure TBuildTests.NativeResolverWritesFormats(const aFormat: string; aSelf: Boolean);
var
  lBytes: TBytes;
  lDpr, lRoot, lProject, lOutput, lLog, lText: string;
  lExit: Cardinal;
  lHasBom: Boolean;
  lLines: TArray<string>;
begin
  lRoot := UniqueTempPath('resolve-formats');
  TDirectory.CreateDirectory(lRoot);
  if aSelf then
    lProject := TPath.Combine(RepoRoot, 'projects\DelphiAIKit.dproj')
  else
    lProject := TPath.Combine(RepoRoot, 'tests\fixtures\Sample.dproj');
  lDpr := TPath.ChangeExtension(lProject, '.dpr');
  lOutput := TPath.Combine(lRoot, 'resolved.' + aFormat);
  lLog := TPath.Combine(lRoot, 'resolve.log');
  Assert.IsTrue(RunResolverProcess('resolve --project ' + QuoteArg(lProject) +
    ' --platform Win64 --config Debug --delphi 23.0 --format ' + aFormat + ' --out-file ' + QuoteArg(lOutput),
    RepoRoot, lLog, lExit));
  Assert.AreEqual(Cardinal(0), lExit, TFile.ReadAllText(lLog));
  Assert.IsTrue(TFile.Exists(lOutput), 'Resolver must write the selected format: ' + lOutput);
  lBytes := TFile.ReadAllBytes(lOutput);
  lHasBom := (Length(lBytes) >= 3) and (lBytes[0] = $EF) and (lBytes[1] = $BB) and (lBytes[2] = $BF);
  lText := TFile.ReadAllText(lOutput, TEncoding.UTF8);
  lLines := lText.Split([#13#10, #10]);
  Assert.IsTrue(Length(lLines) > 0, 'Resolver output must not be empty');
  // Each format has its own shape; the resolved project, platform and
  // configuration must reach it. A different format in the file fails here.
  if aFormat = 'ini' then
  begin
    Assert.IsTrue(lHasBom, 'INI output is UTF-8 with BOM');
    Assert.AreEqual('[FixInsight]', lLines[0]);
    Assert.IsTrue(MatchText('ProjectDpr=' + lDpr, lLines), 'INI must name the project: ' + lOutput);
    Assert.IsTrue(MatchStr('DelphiVersion=23.0', lLines), lOutput);
    Assert.IsTrue(MatchStr('Platform=Win64', lLines), lOutput);
    Assert.IsTrue(MatchStr('Config=Debug', lLines), lOutput);
    Assert.IsTrue(ContainsText(lText, sLineBreak + 'Defines=') and ContainsText(lText, ';WIN64;'),
      'INI must carry the Win64 defines: ' + lOutput);
  end else if aFormat = 'xml' then
  begin
    Assert.IsTrue(lHasBom, 'XML output is UTF-8 with BOM');
    Assert.AreEqual('<FixInsightParams delphi="23.0" platform="Win64" config="Debug">', lLines[0]);
    Assert.IsTrue(MatchText('  <ProjectDpr>' + lDpr + '</ProjectDpr>', lLines), 'XML must name the project: ' + lOutput);
    Assert.IsTrue(MatchStr('    <D>WIN64</D>', lLines), 'XML must carry the Win64 defines: ' + lOutput);
    Assert.IsTrue(lText.TrimRight.EndsWith(sLineBreak + '</FixInsightParams>'),
      'XML must close its root element last: ' + lOutput);
  end else
  begin
    Assert.IsFalse(lHasBom, 'The batch file has no BOM, so cmd.exe can run its first line');
    Assert.AreEqual('@echo off', lLines[0]);
    Assert.IsTrue(MatchText('  --project="' + lDpr + '" ^', lLines), 'The batch file must run the project: ' + lOutput);
    Assert.IsTrue(ContainsText(lText, 'set "FI_DEFINES=') and ContainsText(lText, ';WIN64;'),
      'The batch file must carry the Win64 defines: ' + lOutput);
    Assert.IsTrue(ContainsText(lText, '--defines="%FI_DEFINES%"'), lOutput);
  end;
end;

procedure TBuildTests.NativeConcurrentBuildsKeepOutputsAndDiagnosticsSeparate;
var
  lRoot, lFile, lExe, lCmdExe: string;
  lProjects, lOutputs, lDiagnostics, lLogs, lErrors: TArray<string>;
  lExitCodes: TArray<Cardinal>;
  lCompleted: TArray<Boolean>;
  lLoop: TParallel.TLoopResult;
begin
  EnsureResolverBuilt;
  lExe := ResolverExePath;
  lCmdExe := GetEnvironmentVariable('ComSpec');
  Assert.IsTrue(TFile.Exists(lCmdExe), 'Windows command processor must be available');
  lRoot := UniqueNoRepoTempPath('native parallel builds');
  SetLength(lProjects, 2);
  SetLength(lOutputs, 2);
  SetLength(lDiagnostics, 2);
  SetLength(lLogs, 2);
  SetLength(lErrors, 2);
  SetLength(lExitCodes, 2);
  SetLength(lCompleted, 2);
  for var i := 0 to 1 do
  begin
    lProjects[i] := TPath.Combine(lRoot, 'project ' + IntToStr(i));
    TDirectory.CreateDirectory(lProjects[i]);
    for lFile in TDirectory.GetFiles(TPath.Combine(RepoRoot, 'tests\fixtures\BuildOutputNameFixture')) do
      TFile.Copy(lFile, TPath.Combine(lProjects[i], TPath.GetFileName(lFile)));
    lOutputs[i] := TPath.Combine(lProjects[i], 'output');
    lDiagnostics[i] := TPath.Combine(lProjects[i], 'diagnostics');
    lLogs[i] := TPath.Combine(lProjects[i], 'build.log');
    lProjects[i] := TPath.Combine(lProjects[i], 'Build.Output.Name.dproj');
  end;
  // Each shell only supplies that child's environment. The Pascal helper owns
  // launch, deadline, output capture and the complete descendant job.
  lLoop := TParallel.For(0, 1,
    procedure(aIndex: Integer)
    var
      lArguments: string;
    begin
      try
        lArguments := '/d /s /c "set "DAK_BUILD_DIAGNOSTICS_DIR=' + lDiagnostics[aIndex] + '"&&"' + lExe +
          '" build --project "' + lProjects[aIndex] + '" --delphi 23.0 --platform Win64 --config Debug' +
          ' --test-output-dir "' + lOutputs[aIndex] + '" --json"';
        lCompleted[aIndex] := RunProcessWithTimeout(lCmdExe, lArguments, RepoRoot,
          lLogs[aIndex], 90000, lExitCodes[aIndex]);
      except
        on E: Exception do
          lErrors[aIndex] := E.Message;
      end;
    end);
  Assert.IsTrue(lLoop.Completed, 'Both native builds must finish');
  for var i := 0 to 1 do
  begin
    Assert.AreEqual('', lErrors[i], lLogs[i]);
    Assert.IsTrue(lCompleted[i], lLogs[i]);
    Assert.AreEqual(Cardinal(0), lExitCodes[i], TFile.ReadAllText(lLogs[i]));
    Assert.IsTrue(TFile.Exists(TPath.Combine(lOutputs[i], 'Build.Output.Name.exe')), lOutputs[i]);
    Assert.IsTrue(TFile.Exists(TPath.Combine(lDiagnostics[i], 'stdout.log')), lDiagnostics[i]);
    Assert.IsTrue(TFile.Exists(TPath.Combine(lDiagnostics[i], 'stderr.log')), lDiagnostics[i]);
  end;
  DeleteTempPath(lRoot);
end;

procedure TBuildTests.NativeBuildWarningSummary(const aPlatform, aFilter: string; aExpected: Integer);
const
  cProgram = 'program RemoveWithApplyFixture;' + sLineBreak + '{$APPTYPE CONSOLE}' + sLineBreak +
    'uses Test.Support in ''units\Test.Support.pas'';' + sLineBreak +
    'begin Writeln(ParseJsonObject(True)); ProduceHint; end.';
  cUnit = 'unit Test.Support;' + sLineBreak + 'interface' + sLineBreak +
    'function ParseJsonObject(aValid: Boolean): Integer;' + sLineBreak + 'procedure ProduceHint;' + sLineBreak +
    'implementation' + sLineBreak + '{$WARNINGS ON}' + sLineBreak + '{$HINTS ON}' + sLineBreak +
    'function ParseJsonObject(aValid: Boolean): Integer;' + sLineBreak +
    'begin' + sLineBreak + '  if aValid then Result := 1;' + sLineBreak + 'end;' + sLineBreak +
    'procedure ProduceHint;' + sLineBreak + 'var lUnused: Integer;' + sLineBreak +
    'begin' + sLineBreak + '  lUnused := 1;' + sLineBreak + 'end;' + sLineBreak + 'end.';
var
  lRoot, lProject, lText, lArguments, lLog: string;
  lGuard: IInterface;
  lExit: Cardinal;
  lJson: TJSONObject;
begin
  lRoot := UniqueNoRepoTempPath('native-warning-summary');
  TDirectory.CreateDirectory(TPath.Combine(lRoot, 'units'));
  lProject := TPath.Combine(lRoot, 'RemoveWithApplyFixture.dproj');
  lText := TFile.ReadAllText(TPath.Combine(RepoRoot,
    'tests\fixtures\RemoveWithApplyFixture\RemoveWithApplyFixture.dproj'));
  lText := lText.Replace('System;System.Win;', 'System;System.Win;Winapi;');
  TFile.WriteAllText(lProject, lText.Replace('ApplyUnit.pas', 'units\Test.Support.pas'), TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(lRoot, 'RemoveWithApplyFixture.dpr'), cProgram, TEncoding.ASCII);
  // These diagnostics are deliberate fixture inputs, not warnings in DAK itself.
  TFile.WriteAllText(TPath.Combine(lRoot, 'units\Test.Support.pas'), cUnit, TEncoding.ASCII);
  lGuard := SetScopedEnvironmentVariable('DAK_BUILD_DIAGNOSTICS_DIR', TPath.Combine(lRoot, 'diagnostics'));
  Assert.IsNotNull(lGuard);
  lArguments := 'build --project ' + QuoteArg(lProject) + ' --delphi 23.0 --config Debug --platform ' +
    aPlatform + ' --target Rebuild --json --show-warnings --show-hints';
  if aFilter = 'codes' then
    lArguments := lArguments + ' --ignore-warnings W1035 --ignore-hints H2077'
  else if aFilter = 'source' then
    lArguments := lArguments + ' --exclude-path-masks ' + QuoteArg('units\*')
  else if aFilter = 'unmatched' then
    lArguments := lArguments + ' --ignore-warnings W9999 --ignore-hints H9999 --exclude-path-masks ' +
      QuoteArg('vendor\*');
  lLog := TPath.Combine(lRoot, 'build.log');
  Assert.IsTrue(RunResolverProcess(lArguments, RepoRoot, lLog, lExit));
  lText := TFile.ReadAllText(lLog);
  Assert.AreEqual(Cardinal(0), lExit, lText);
  lJson := ParseJsonObject(lText, 'native diagnostic counts');
  try
    Assert.AreEqual(aExpected, lJson.GetValue<Integer>('warnings'), lText);
    Assert.AreEqual(aExpected, lJson.GetValue<Integer>('hints'), lText);
  finally
    lJson.Free;
  end;
  lText := TFile.ReadAllText(TPath.Combine(lRoot, 'diagnostics\stdout.log'));
  Assert.IsTrue(lText.Contains('W1035'), 'The compiler must actually emit the warning');
  Assert.IsTrue(lText.Contains('H2077'), 'The compiler must actually emit the hint');
  DeleteTempPath(lRoot);
end;

procedure TBuildTests.NativeBuildOutputContracts(aReservedDirectory: Boolean);
var
  lRoot, lProject, lFile, lText, lLog, lEmitted: string;
  lCut: Integer;
  lExit: Cardinal;
  lJson: TJSONObject;
begin
  lRoot := UniqueNoRepoTempPath('native-output');
  TDirectory.CreateDirectory(lRoot);
  for lFile in TDirectory.GetFiles(TPath.Combine(RepoRoot, 'tests\fixtures\BuildOutputNameFixture')) do
    TFile.Copy(lFile, TPath.Combine(lRoot, TPath.GetFileName(lFile)));
  lProject := TPath.Combine(lRoot, 'Build.Output.Name.dproj');
  lText := TFile.ReadAllText(lProject);
  if aReservedDirectory then
    lText := lText.Replace('<DCC_ExeOutput>.\bin</DCC_ExeOutput>',
      '<DCC_ExeOutput>$(MSBuildProjectDirectory)\.dak\Build.Output.Name\bin\$(Platform)\$(Config)</DCC_ExeOutput>')
  else begin
    lCut := lText.IndexOf('<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets"');
    Assert.IsTrue(lCut >= 0, 'Fixture must contain the compiler import');
    lText := lText.Substring(0, lCut) + '<Target Name="Build" />' + sLineBreak + '</Project>';
  end;
  TFile.WriteAllText(lProject, lText, TEncoding.UTF8);
  lLog := TPath.Combine(lRoot, 'build.log');
  Assert.IsTrue(RunResolverProcess('build --project ' + QuoteArg(lProject) +
    ' --config Debug --platform Win64 --delphi 23.0 --json', RepoRoot, lLog, lExit));
  lText := TFile.ReadAllText(lLog);
  Assert.AreEqual(Cardinal(0), lExit, lText);
  lJson := TJSONObject.ParseJSONValue(lText) as TJSONObject;
  try
    Assert.IsNotNull(lJson, lText);
    lEmitted := lJson.GetValue<string>('output');
    if aReservedDirectory then
    begin
      Assert.AreEqual(TPath.Combine(lRoot, '.dak\Build.Output.Name\bin\Win64\Debug\Build.Output.Name.exe'),
        lEmitted, lText);
      Assert.IsTrue(TFile.Exists(lEmitted), lText);
      Assert.IsFalse(lJson.GetValue<Boolean>('output_stale'), lText);
    end else begin
      Assert.IsFalse(TFile.Exists(lEmitted), lText);
      Assert.IsTrue(lJson.GetValue<Boolean>('output_stale'), lText);
      Assert.AreEqual('output_missing', lJson.GetValue<string>('status'), lText);
      Assert.IsTrue(lJson.GetValue<string>('output_message').Contains(lEmitted), lText);
    end;
  finally
    lJson.Free;
  end;
  DeleteTempPath(lRoot);
end;

procedure TBuildTests.NativeBuildPreservesMsBuildFailure;
var
  lRoot, lProject, lFile, lLog, lText: string;
  lCut: Integer;
  lExit: Cardinal;
  lGuard: IInterface;
  lJson: TJSONObject;
begin
  lRoot := UniqueNoRepoTempPath('native-msbuild-failure');
  TDirectory.CreateDirectory(lRoot);
  for lFile in TDirectory.GetFiles(TPath.Combine(RepoRoot, 'tests\fixtures\BuildOutputNameFixture')) do
    TFile.Copy(lFile, TPath.Combine(lRoot, TPath.GetFileName(lFile)));
  lProject := TPath.Combine(lRoot, 'Build.Output.Name.dproj');
  lText := TFile.ReadAllText(lProject);
  lCut := lText.IndexOf('<Import Project="$(BDS)\Bin\CodeGear.Delphi.Targets"');
  Assert.IsTrue(lCut >= 0, 'Fixture must contain the compiler import');
  TFile.WriteAllText(lProject, lText.Substring(0, lCut) + '</Project>', TEncoding.UTF8);
  lLog := TPath.Combine(lRoot, 'build.log');
  lGuard := SetScopedEnvironmentVariable('DAK_BUILD_DIAGNOSTICS_DIR', TPath.Combine(lRoot, 'diagnostics'));
  Assert.IsNotNull(lGuard);
  // A real MSBuild target error exercises failure before a compiler diagnostic exists.
  Assert.IsTrue(RunResolverProcess('build --project ' + QuoteArg(lProject) +
    ' --config Debug --platform Win64 --delphi 23.0 --target Build --json', RepoRoot, lLog, lExit));
  lText := TFile.ReadAllText(lLog);
  Assert.AreNotEqual(Cardinal(0), lExit, lText);
  lJson := TJSONObject.ParseJSONValue(lText) as TJSONObject;
  try
    Assert.IsNotNull(lJson, lText);
    Assert.AreEqual('error', lJson.GetValue<string>('status'), lText);
    Assert.IsTrue(lJson.GetValue<Integer>('errors') > 0, lText);
  finally
    lJson.Free;
  end;
  Assert.IsTrue(TFile.ReadAllText(TPath.Combine(lRoot, 'diagnostics\stdout.log')).Contains('MSB4057'),
    'The real MSBuild target must reject the request');
  DeleteTempPath(lRoot);
end;

function ReadRepoTextFile(const aRelativePath: string): string;
begin
  Result := TFile.ReadAllText(TPath.Combine(RepoRoot, aRelativePath), TEncoding.UTF8);
end;

// The compiler names the executable after the DPR file, not after the program identifier or
// SanitizedProjectName. The reported output must be that fresh file, and a predicted output that does
// not exist after a successful build must never be reported as fresh.
procedure TBuildTests.BuildReportsTheExecutableTheCompilerEmitted(aForceWrongPrediction: Boolean);
var
  lDproj, lEmitted, lJsonText, lLog, lOutput, lRoot: string;
  lExit: Cardinal;
  lFile: string;
  lJson: TJSONObject;
  lStarted: TDateTime;
begin
  lRoot := UniqueNoRepoTempPath('build-output-name');
  try
    TDirectory.CreateDirectory(lRoot);
    for lFile in TDirectory.GetFiles(TPath.Combine(RepoRoot, 'tests\fixtures\BuildOutputNameFixture')) do
      TFile.Copy(lFile, TPath.Combine(lRoot, TPath.GetFileName(lFile)));
    lDproj := TPath.Combine(lRoot, 'Build.Output.Name.dproj');
    if aForceWrongPrediction then
      // Old forcing: DCC_DependencyCheckOutputName Never.Written.exe, which the compiler ignores. A {$E} inside
      // conditional compilation that DAK does not evaluate predicts .scr while the compiler writes .exe.
      TFile.WriteAllText(TPath.Combine(lRoot, 'Build.Output.Name.dpr'),
        TFile.ReadAllText(TPath.Combine(lRoot, 'Build.Output.Name.dpr'), TEncoding.UTF8).Replace(
        '{$APPTYPE CONSOLE}', '{$APPTYPE CONSOLE}' + sLineBreak + '{$IFDEF NEVER_DEFINED}{$E scr}{$ENDIF}'),
        TEncoding.UTF8);
    lEmitted := TPath.Combine(lRoot, 'bin\Build.Output.Name.exe');
    lLog := TPath.Combine(lRoot, 'build.json.log');
    lStarted := Now;
    Assert.IsTrue(RunResolverProcess('build --project ' + QuoteArg(lDproj) +
      ' --config Debug --platform Win64 --delphi 23.0 --json', RepoRoot, lLog, lExit), 'build must start');
    lJsonText := TFile.ReadAllText(lLog);
    Assert.AreEqual(Cardinal(0), lExit, lJsonText);
    Assert.IsTrue(TFile.Exists(lEmitted), 'the compiler emits the file-named executable: ' + lJsonText);
    Assert.IsTrue(TFile.GetLastWriteTime(lEmitted) >= IncSecond(lStarted, -2), 'the emitted executable is fresh');
    lJson := ParseJsonObject(lJsonText.Substring(lJsonText.IndexOf('{'), lJsonText.LastIndexOf('}') - lJsonText.IndexOf('{') + 1), 'build json');
    try
      lOutput := lJson.GetValue<string>('output');
      if aForceWrongPrediction then
      begin
        Assert.IsFalse(TFile.Exists(lOutput), 'the forced prediction names a missing file: ' + lOutput);
        Assert.IsTrue(lJson.GetValue<Boolean>('output_stale'), 'a missing output is not reported as fresh: ' + lJsonText);
        Assert.IsTrue(lJson.GetValue<string>('output_message').Contains(lOutput), lJsonText);
      end else begin
        Assert.IsTrue(SameText(lEmitted, lOutput), 'reported ' + lOutput + ', compiler emitted ' + lEmitted);
        Assert.IsFalse(lJson.GetValue<Boolean>('output_stale'), lJsonText);
      end;
    finally
      lJson.Free;
    end;
  finally
    DeleteTempPath(lRoot);
  end;
end;

procedure TBuildTests.ProjectDprListsMadExceptFirstAndAllSourceUnits;
var
  lDprText: string;
  lExpectedPrefix: string;
  lPasFile: string;
  lPasFiles: TArray<string>;
  lRelativePath: string;
  lSourceDir: string;
begin
  lDprText := ReadRepoTextFile('projects\DelphiAIKit.dpr');
  lExpectedPrefix :=
    'uses' + sLineBreak +
    '  madExcept,' + sLineBreak +
    '  madLinkDisAsm,' + sLineBreak +
    '  madListHardware,' + sLineBreak +
    '  madListProcesses,' + sLineBreak +
    '  madListModules,';
  Assert.IsTrue(Pos(lExpectedPrefix, lDprText) > 0,
    'The DPR uses list must start with the standard madExcept units in canonical order.');

  lSourceDir := TPath.Combine(RepoRoot, 'src');
  lPasFiles := TDirectory.GetFiles(lSourceDir, '*.pas', TSearchOption.soTopDirectoryOnly);
  Assert.IsTrue(Length(lPasFiles) > 0, 'Expected project source units under src.');
  for lPasFile in lPasFiles do
  begin
    lRelativePath := '..\src\' + TPath.GetFileName(lPasFile);
    Assert.IsTrue(ContainsText(lDprText, ' in ''' + lRelativePath + ''''),
      'The DPR must explicitly list project source unit: ' + lRelativePath);
  end;
end;

procedure SetBuildParams(const aCmdLine: string);
var
  lParams: iCmdLineParams;
begin
  lParams := maxCmdLineParams;
  lParams.BuildFromString(aCmdLine);
end;

procedure TBuildTests.ExternalToolProcessCentralizesBasicCommandRunners;
var
  lBuildSource: string;
  lExternalToolSource: string;
  lFixInsightSource: string;
  lPascalAnalyzerSource: string;
begin
  lExternalToolSource := ReadRepoTextFile('src\Dak.ExternalToolProcess.pas');
  lBuildSource := ReadRepoTextFile('src\Dak.Build.Runner.pas');
  lFixInsightSource := ReadRepoTextFile('src\dak.fixinsightrunner.pas');
  lPascalAnalyzerSource := ReadRepoTextFile('src\dak.pascalanalyzerrunner.pas');

  Assert.IsTrue(ContainsText(lExternalToolSource, 'TExternalToolProcessRunOptions'),
    'Expected shared external-tool run options.');
  Assert.IsTrue(ContainsText(lExternalToolSource, 'TryRunExternalToolProcess'),
    'Expected shared external-tool run primitive.');
  Assert.IsTrue(ContainsText(lBuildSource, 'TryRunExternalToolProcess'),
    'Build process runner should use the shared external-tool runner.');
  Assert.IsTrue(ContainsText(lFixInsightSource, 'TryRunExternalToolProcess'),
    'FixInsight process runner should use the shared external-tool runner.');
  Assert.IsTrue(ContainsText(lPascalAnalyzerSource, 'TryRunExternalToolProcess'),
    'Pascal Analyzer process runners should use the shared external-tool runner.');
end;

procedure TBuildTests.ExternalToolTimeoutMillisecondsPreserveCardinalRange;
begin
  Assert.AreEqual(Cardinal(3000000000), ResolveExternalToolTimeoutMs(3000000));
end;

procedure TBuildTests.ProtocolSpecificProcessRunnersRemainDocumentedExceptions;
var
  lDfmCheckSource: string;
  lLspTransportSource: string;
  lPascalAnalyzerSource: string;
begin
  lDfmCheckSource := ReadRepoTextFile('src\dak.dfmcheck.pas');
  lLspTransportSource := ReadRepoTextFile('src\Dak.Lsp.Transport.pas');
  lPascalAnalyzerSource := ReadRepoTextFile('src\dak.pascalanalyzerrunner.pas');

  Assert.IsTrue(ContainsText(lDfmCheckSource, 'Protocol-specific process supervision'),
    'DFMCheck local process control must be documented as a protocol-specific exception.');
  Assert.IsTrue(ContainsText(lLspTransportSource, 'Protocol-specific process supervision'),
    'LSP local process control must be documented as a protocol-specific exception.');
  Assert.IsTrue(ContainsText(lPascalAnalyzerSource, 'Protocol-specific output capture'),
    'PAL help pipe capture must be documented as a protocol-specific exception.');
end;

destructor TCapturingBuildRunner.Destroy;
begin
  if Assigned(fExitCodesByCall) then
    fExitCodesByCall.Free;
  if Assigned(fFilesToCreateOnCall) then
    fFilesToCreateOnCall.Free;
  inherited;
end;

function TCapturingBuildRunner.RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
  const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
  out aTimedOut: Boolean; out aError: string): Boolean;
var
  lFileToCreate: string;
  lLength: Integer;
begin
  Inc(fCallCount);
  fArguments := aArguments;
  lLength := Length(fExePaths);
  SetLength(fExePaths, lLength + 1);
  fExePaths[lLength] := aExePath;
  SetLength(fArgumentsList, lLength + 1);
  fArgumentsList[lLength] := aArguments;
  SetLength(fEnvironmentBlocks, lLength + 1);
  fEnvironmentBlocks[lLength] := aEnvironmentBlock;
  ForceDirectories(ExtractFileDir(aStdOutPath));
  TFile.WriteAllText(aStdOutPath, '', TEncoding.UTF8);
  TFile.WriteAllText(aStdErrPath, '', TEncoding.UTF8);
  if Assigned(fFilesToCreateOnCall) and fFilesToCreateOnCall.TryGetValue(lLength, lFileToCreate) then
  begin
    ForceDirectories(ExtractFileDir(lFileToCreate));
    TFile.WriteAllText(lFileToCreate, '', TEncoding.UTF8);
  end;
  aExitCode := 0;
  if Assigned(fExitCodesByCall) then
    fExitCodesByCall.TryGetValue(lLength, aExitCode);
  aTimedOut := False;
  aError := '';
  Result := True;
end;

function TFailingBuildRunner.RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
  const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
  out aTimedOut: Boolean; out aError: string): Boolean;
begin
  ForceDirectories(ExtractFileDir(aStdOutPath));
  TFile.WriteAllText(aStdOutPath, fStdOutText, TEncoding.UTF8);
  TFile.WriteAllText(aStdErrPath, fStdErrText, TEncoding.UTF8);
  aExitCode := 1;
  aTimedOut := False;
  aError := '';
  Result := True;
end;

function TRealMsBuildRunner.RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
  const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
  out aTimedOut: Boolean; out aError: string): Boolean;
var
  lExit: Cardinal;
  lMsBuild: string;
begin
  // aExePath is the fixture's stub toolchain; only the generated arguments are under test.
  lMsBuild := TPath.Combine(GetEnvironmentVariable('WINDIR'), 'Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe');
  if not TFile.Exists(lMsBuild) then
    lMsBuild := TPath.Combine(GetEnvironmentVariable('WINDIR'), 'Microsoft.NET\Framework\v4.0.30319\MSBuild.exe');
  Assert.IsTrue(TFile.Exists(lMsBuild), 'This test needs the .NET Framework MSBuild: ' + lMsBuild);
  fArguments := aArguments;
  aTimedOut := False;
  aError := '';
  Result := Test.Support.RunProcess(lMsBuild, aArguments, aWorkDir, aStdOutPath, lExit);
  aExitCode := Integer(lExit);
  TFile.WriteAllText(aStdErrPath, '');
  fOutput := TFile.ReadAllText(aStdOutPath);
end;

procedure WriteUtf8File(const aPath, aText: string);
begin
  ForceDirectories(ExtractFileDir(aPath));
  TFile.WriteAllText(aPath, aText, TEncoding.UTF8);
end;

// DAK-372: a stub toolchain whose environment.proj holds aEnvProjProperties. aProjectTargets becomes the
// project's MSBuild targets, so a real MSBuild can report the property values it received.
function PrepareEnvironmentProjBuild(const aName, aProjectTargets, aEnvProjProperties: string;
  out aProjectRoot, aAppData: string): TAppOptions;
var
  lDprojPath: string;
  lFakeBdsRoot: string;
begin
  EnsureTempClean;
  aProjectRoot := TPath.Combine(TempRoot, aName);
  if TDirectory.Exists(aProjectRoot) then
    TDirectory.Delete(aProjectRoot, True);
  ForceDirectories(aProjectRoot);

  lDprojPath := TPath.Combine(aProjectRoot, 'EnvProps372.dproj');
  WriteUtf8File(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" DefaultTargets="Build">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>EnvProps372.dpr</MainSource>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    aProjectTargets +
    '</Project>' + sLineBreak);
  WriteUtf8File(TPath.ChangeExtension(lDprojPath, '.dpr'),
    'program EnvProps372;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(aProjectRoot, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  TFile.WriteAllText(TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat'), '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');

  aAppData := TPath.Combine(aProjectRoot, 'fake-appdata');
  WriteUtf8File(TPath.Combine(aAppData, 'Embarcadero\BDS\23.0\environment.proj'),
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    aEnvProjProperties +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);

  Result := Default(TAppOptions);
  Result.fDprojPath := lDprojPath;
  Result.fConfig := 'Debug';
  Result.fPlatform := 'Win32';
  Result.fDelphiVersion := '23.0';
  Result.fHasRsVarsPath := True;
  Result.fRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
end;

procedure WriteIniTextFile(const aPath, aText: string);
begin
  ForceDirectories(ExtractFileDir(aPath));
  TFile.WriteAllText(aPath, aText, TEncoding.ASCII);
end;

function DescribeCapturedProcesses(const aRunner: TCapturingBuildRunner): string;
var
  i: Integer;
  lParts: TArray<string>;
begin
  SetLength(lParts, Length(aRunner.fExePaths));
  for i := 0 to High(aRunner.fExePaths) do
    lParts[i] := Format('%d:%s | %s', [i, aRunner.fExePaths[i], aRunner.fArgumentsList[i]]);
  Result := String.Join(' || ', lParts);
end;

function CaptureConsoleOutput(const aProc: TProc): string;
var
  lBytesRead: Cardinal;
  lChunk: AnsiString;
  lOldErr: TTextRec;
  lOldOut: TTextRec;
  lReadHandle: THandle;
  lSa: TSecurityAttributes;
  lWriteHandle: THandle;
  lBuffer: array[0..4095] of AnsiChar;
begin
  Result := '';
  FillChar(lSa, SizeOf(lSa), 0);
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;
  lReadHandle := 0;
  lWriteHandle := 0;
  if not CreatePipe(lReadHandle, lWriteHandle, @lSa, 0) then
    raise Exception.Create('Failed to create capture pipe.');
  try
    Flush(Output);
    Flush(ErrOutput);
    lOldOut := TTextRec(Output);
    lOldErr := TTextRec(ErrOutput);
    try
      // Open lazy RTL streams before redirecting; first-write initialization replaces their handles.
      if TTextRec(Output).Mode = fmClosed then
        Rewrite(Output);
      if TTextRec(ErrOutput).Mode = fmClosed then
        Rewrite(ErrOutput);
      TTextRec(Output).Handle := lWriteHandle;
      TTextRec(ErrOutput).Handle := lWriteHandle;
      try
        aProc();
      finally
        Flush(Output);
        Flush(ErrOutput);
      end;
    finally
      TTextRec(Output) := lOldOut;
      TTextRec(ErrOutput) := lOldErr;
    end;

    CloseHandle(lWriteHandle);
    lWriteHandle := 0;
    while ReadFile(lReadHandle, lBuffer, SizeOf(lBuffer), lBytesRead, nil) and (lBytesRead > 0) do
    begin
      SetString(lChunk, PAnsiChar(@lBuffer[0]), lBytesRead);
      Result := Result + string(lChunk);
    end;
  finally
    if lWriteHandle <> 0 then
      CloseHandle(lWriteHandle);
    if lReadHandle <> 0 then
      CloseHandle(lReadHandle);
  end;
end;

procedure TBuildTests.ConsoleCaptureRestoresTextState(aLazy, aRaise: Integer);
var
  lOriginalOut: TTextRec;
  lOriginalErr: TTextRec;
  lExpectedOut: TTextRec;
  lExpectedErr: TTextRec;
  lCaptured: string;
  lRestored: Boolean;
  lRaised: Boolean;
  lIoResult: Integer;
begin
  Flush(Output);
  Flush(ErrOutput);
  lOriginalOut := TTextRec(Output);
  lOriginalErr := TTextRec(ErrOutput);
  try
    if aLazy <> 0 then
    begin
      TTextRec(Output) := Default(TTextRec);
      TTextRec(Output).Mode := fmClosed;
      TTextRec(ErrOutput) := Default(TTextRec);
      TTextRec(ErrOutput).Mode := fmClosed;
    end else begin
      Write(Output, '');
      Write(ErrOutput, '');
    end;
    lExpectedOut := TTextRec(Output);
    lExpectedErr := TTextRec(ErrOutput);
    lRaised := False;
    try
      lCaptured := CaptureConsoleOutput(
        procedure
        begin
          System.WriteLn(Output, 'captured stdout');
          System.WriteLn(ErrOutput, 'captured stderr');
          if aRaise <> 0 then
            raise EAbort.Create('capture exception');
        end);
    except
      on E: EAbort do
        lRaised := True;
    end;
    lRestored := CompareMem(@lExpectedOut, @Output, SizeOf(TTextRec)) and
      CompareMem(@lExpectedErr, @ErrOutput, SizeOf(TTextRec));
    {$IOCHECKS OFF}
    System.WriteLn(ErrOutput, 'stderr after capture');
    Flush(ErrOutput);
    lIoResult := IOResult;
    {$IOCHECKS ON}
  finally
    TTextRec(Output) := lOriginalOut;
    TTextRec(ErrOutput) := lOriginalErr;
  end;
  Assert.IsTrue(lRestored, 'Capture must restore the complete RTL text state.');
  Assert.AreEqual(0, lIoResult, 'A subsequent stderr write and flush must succeed.');
  Assert.AreEqual(aRaise <> 0, lRaised, 'Capture must propagate callback exceptions.');
  if aRaise = 0 then
  begin
    Assert.IsTrue(lCaptured.Contains('captured stdout'), lCaptured);
    Assert.IsTrue(lCaptured.Contains('captured stderr'), lCaptured);
  end;
end;

procedure PrepareMadExceptBuildFixture(const aRootDir, aMesText: string; out aDprojPath, aRsVarsPath,
  aPatchExePath: string); forward;

procedure PrepareMadExceptBuildFixture(const aRootDir, aMesText: string; out aDprojPath, aRsVarsPath,
  aPatchExePath: string);
var
  lDprPath: string;
  lFakeBdsRoot: string;
begin
  ForceDirectories(aRootDir);

  aDprojPath := TPath.Combine(aRootDir, 'MesGateCheck.dproj');
  lDprPath := TPath.ChangeExtension(aDprojPath, '.dpr');
  aPatchExePath := TPath.Combine(aRootDir, 'madExceptPatch.exe');

  WriteUtf8File(aDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>MesGateCheck.dpr</MainSource>' + sLineBreak +
    '    <DCC_Define>madExcept</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program MesGateCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);
  WriteIniTextFile(TPath.ChangeExtension(aDprojPath, '.mes'), aMesText);
  WriteIniTextFile(TPath.Combine(aRootDir, 'dak.ini'),
    '[MadExcept]' + sLineBreak +
    'Path=' + aPatchExePath + sLineBreak);
  WriteUtf8File(aPatchExePath, 'stub' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(aRootDir, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  aRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(aRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');
end;

procedure PrepareMadExceptBuildFixtureWithOptset(const aRootDir, aMesText, aOptsetText,
  aProjectPropertyXml: string; out aDprojPath, aRsVarsPath, aPatchExePath: string);
var
  lDprPath: string;
  lFakeBdsRoot: string;
  lOptsetPath: string;
begin
  ForceDirectories(aRootDir);

  aDprojPath := TPath.Combine(aRootDir, 'MesGateCheck.dproj');
  lDprPath := TPath.ChangeExtension(aDprojPath, '.dpr');
  lOptsetPath := TPath.Combine(aRootDir, 'MesGateCheck.optset');
  aPatchExePath := TPath.Combine(aRootDir, 'madExceptPatch.exe');

  WriteUtf8File(aDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>MesGateCheck.dpr</MainSource>' + sLineBreak +
    '    <CfgDependentOn>MesGateCheck.optset</CfgDependentOn>' + sLineBreak +
    '    <DCC_Define>madExcept</DCC_Define>' + sLineBreak +
         aProjectPropertyXml +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lOptsetPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
         aOptsetText +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program MesGateCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);
  WriteIniTextFile(TPath.ChangeExtension(aDprojPath, '.mes'), aMesText);
  WriteIniTextFile(TPath.Combine(aRootDir, 'dak.ini'),
    '[MadExcept]' + sLineBreak +
    'Path=' + aPatchExePath + sLineBreak);
  WriteUtf8File(aPatchExePath, 'stub' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(aRootDir, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  aRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(aRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');
end;

// DAK-374: a project without madExcept whose kind (program, library or package) decides the artifact name.
// aProjectXml goes inside <Project>, for example an Import of stand-in compiler targets.
function PrepareArtifactNamingFixture(const aRootDir, aKind, aProjectXml: string; out aDprojPath,
  aRsVarsPath: string): TAppOptions;
var
  lFakeBdsRoot: string;
  lKindXml: string;
  lMainSource: string;
  lSourceText: string;
begin
  ForceDirectories(aRootDir);
  aDprojPath := TPath.Combine(aRootDir, 'MesGateCheck.dproj');
  if SameText(aKind, 'package') then
  begin
    lMainSource := 'MesGateCheck.dpk';
    lKindXml := '    <AppType>Package</AppType>' + sLineBreak;
    lSourceText := 'package MesGateCheck;' + sLineBreak + 'end.' + sLineBreak;
  end else if SameText(aKind, 'library') then
  begin
    lMainSource := 'MesGateCheck.dpr';
    lKindXml := '    <AppType>Library</AppType>' + sLineBreak + '    <GenDll>true</GenDll>' + sLineBreak;
    lSourceText := 'library MesGateCheck;' + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak;
  end else begin
    lMainSource := 'MesGateCheck.dpr';
    lKindXml := '    <AppType>Console</AppType>' + sLineBreak;
    lSourceText := 'program MesGateCheck;' + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak;
  end;

  WriteUtf8File(aDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>' + lMainSource + '</MainSource>' + sLineBreak +
         lKindXml +
    '    <DCC_ExeOutput>out\$(Platform)</DCC_ExeOutput>' + sLineBreak +
    '    <DCC_DcuOutput>_dcus\$(Platform)</DCC_DcuOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
         aProjectXml +
    '</Project>' + sLineBreak);
  WriteUtf8File(TPath.Combine(aRootDir, lMainSource), lSourceText);

  lFakeBdsRoot := TPath.Combine(aRootDir, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  aRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(aRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');

  Result := Default(TAppOptions);
  Result.fDprojPath := aDprojPath;
  Result.fConfig := 'Debug';
  Result.fDelphiVersion := '23.0';
  Result.fRsVarsPath := aRsVarsPath;
  Result.fBuildJson := True;
end;

// Runs the build with a runner that writes aEmittedPath as the compiler output and returns the JSON summary.
// aCapture and aRunner are the same object: the caller's interface reference keeps it alive.
function RunArtifactNamingBuild(const aOptions: TAppOptions; const aEmittedPath: string;
  const aCapture: TCapturingBuildRunner; const aRunner: IBuildProcessRunner): string;
var
  lError: string;
  lExitCode: Integer;
  lOk: Boolean;
begin
  aCapture.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  if aEmittedPath <> '' then
    aCapture.fFilesToCreateOnCall.AddOrSetValue(0, aEmittedPath);
  lOk := False;
  lExitCode := -1;
  lError := '';
  Result := CaptureConsoleOutput(
    procedure
    begin
      lOk := TryRunBuild(aOptions, aRunner, lExitCode, lError);
    end);
  Assert.IsTrue(lOk, 'The build must complete. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'The compiler reported success. Output: ' + Result);
  Assert.AreEqual(1, aCapture.fCallCount, 'Only MSBuild must run. Output: ' + Result);
end;

// DAK-374: rewrites the main source of a fixture made by PrepareArtifactNamingFixture so that it carries
// aDirectives (naming directives such as {$LIBSUFFIX 'x'}, one per line). The compiler names an artifact after
// these, not after the project's DllPrefix, DllSuffix, DllVersion or DCC_DependencyCheckOutputName.
procedure WriteNamingSource(const aRootDir, aKind, aDirectives: string);
begin
  if SameText(aKind, 'package') then
    WriteUtf8File(TPath.Combine(aRootDir, 'MesGateCheck.dpk'),
      'package MesGateCheck;' + sLineBreak + aDirectives + sLineBreak + 'end.' + sLineBreak)
  else if SameText(aKind, 'library') then
    WriteUtf8File(TPath.Combine(aRootDir, 'MesGateCheck.dpr'),
      'library MesGateCheck;' + sLineBreak + aDirectives + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak)
  else
    WriteUtf8File(TPath.Combine(aRootDir, 'MesGateCheck.dpr'),
      'program MesGateCheck;' + sLineBreak + aDirectives + sLineBreak + 'begin' + sLineBreak + 'end.' + sLineBreak);
end;

const
  cBplOutputGroup =
    '  <PropertyGroup>' + sLineBreak +
    '    <DCC_BplOutput>bpl\$(Platform)</DCC_BplOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak;

function JsonPathValue(const aPath: string): string;
begin
  Result := StringReplace(aPath, '\', '\\', [rfReplaceAll]);
end;

procedure PrepareMadExceptBuildFixtureWithMissingOptset(const aRootDir, aMesText, aProjectPropertyXml: string;
  out aDprojPath, aRsVarsPath, aPatchExePath: string);
var
  lDprPath: string;
  lFakeBdsRoot: string;
begin
  ForceDirectories(aRootDir);

  aDprojPath := TPath.Combine(aRootDir, 'MesGateCheck.dproj');
  lDprPath := TPath.ChangeExtension(aDprojPath, '.dpr');
  aPatchExePath := TPath.Combine(aRootDir, 'madExceptPatch.exe');

  WriteUtf8File(aDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>MesGateCheck.dpr</MainSource>' + sLineBreak +
    '    <CfgDependentOn>Missing.optset</CfgDependentOn>' + sLineBreak +
    '    <DCC_Define>madExcept</DCC_Define>' + sLineBreak +
         aProjectPropertyXml +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program MesGateCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);
  WriteIniTextFile(TPath.ChangeExtension(aDprojPath, '.mes'), aMesText);
  WriteIniTextFile(TPath.Combine(aRootDir, 'dak.ini'),
    '[MadExcept]' + sLineBreak +
    'Path=' + aPatchExePath + sLineBreak);
  WriteUtf8File(aPatchExePath, 'stub' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(aRootDir, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  aRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(aRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');
end;

procedure TBuildTests.BuildResolverExe;
begin
  EnsureResolverBuilt;
  Assert.IsTrue(FileExists(ResolverExePath), 'Resolver exe not found: ' + ResolverExePath);
end;

procedure TBuildTests.BuildCommandUsesNativeRunnerForExternalRepoProjects;
var
  lCmd: string;
  lDprPath: string;
  lDprojPath: string;
  lExit: Cardinal;
  lExternalRoot: string;
  lLog: string;
  lLogText: string;
begin
  EnsureTempClean;
  lExternalRoot := TPath.Combine(TempRoot, 'external-build-root');
  if TDirectory.Exists(lExternalRoot) then
    TDirectory.Delete(lExternalRoot, True);
  ForceDirectories(TPath.Combine(lExternalRoot, '.git'));

  lDprojPath := TPath.Combine(lExternalRoot, 'ExternalBuildCheck.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  lLog := TPath.Combine(lExternalRoot, 'build.log');

  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>ExternalBuildCheck.dpr</MainSource>' + sLineBreak +
    '    <DCC_Define>madExcept</DCC_Define>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program ExternalBuildCheck;' + sLineBreak +
    'begin' + sLineBreak +
    '  this does not compile' + sLineBreak +
    'end.' + sLineBreak);
  WriteUtf8File(TPath.ChangeExtension(lDprojPath, '.mes'), 'stub' + sLineBreak);

  Assert.IsTrue(
    RunProcess(
      ResolverExePath,
      'build --project ' + QuoteArg(lDprojPath) + ' --config Debug --platform Win32 --delphi 23.0 --ai',
      RepoRoot,
      lLog,
      lExit
    ),
    'Failed to start DelphiAIKit.exe build.'
  );

  lLogText := '';
  if FileExists(lLog) then
    lLogText := TFile.ReadAllText(lLog);

  Assert.AreNotEqual(Cardinal(0), lExit, 'The synthetic project must fail to compile so we can inspect build output.');

  Assert.IsFalse(
    ContainsText(lLogText, 'madExcept probe script not found'),
    'DelphiAIKit.exe still depends on the old helper-script probe path. Log: ' + lLog
  );
  Assert.IsFalse(
    ContainsText(lLogText, 'madExcept tool resolver script not found'),
    'DelphiAIKit.exe still depends on the old helper-script resolver path. Log: ' + lLog
  );
  Assert.IsTrue(
    ContainsText(lLogText, 'FAILED.'),
    'The native runner did not report a build failure summary. Log: ' + lLog
  );
end;

procedure TBuildTests.BuildCommandAddsEnvironmentProjPropsToMsBuildArgs;
var
  lAppData: string;
  lCapturingRunner: TCapturingBuildRunner;
  lDprPath: string;
  lDprojPath: string;
  lEnvGuard: IInterface;
  lEnvProjPath: string;
  lError: string;
  lExitCode: Integer;
  lFakeBdsRoot: string;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lRsVarsPath: string;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'env-props-build');
  ForceDirectories(lProjectRoot);

  lDprojPath := TPath.Combine(lProjectRoot, 'EnvPropsCheck.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>EnvPropsCheck.dpr</MainSource>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program EnvPropsCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(TempRoot, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  lRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(lRsVarsPath, '@echo off' + sLineBreak +
    'set DAK_RSVARS_SENTINEL=build-child-env' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');

  lAppData := TPath.Combine(TempRoot, 'fake-appdata');
  lEnvProjPath := TPath.Combine(lAppData, 'Embarcadero\BDS\23.0\environment.proj');
  WriteUtf8File(lEnvProjPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <FrameworkDirOverride>C:\Program Files\Reference Assemblies</FrameworkDirOverride>' + sLineBreak +
    '    <FrameworkVersionOverride>v4.8</FrameworkVersionOverride>' + sLineBreak +
    '    <ExistingProp>must-not-override</ExistingProp>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);

  lEnvGuard := SetScopedEnvironmentVariables([
    'APPDATA', lAppData,
    'ExistingProp', 'already-set'
  ]);
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '23.0';
    lOptions.fRsVarsPath := lRsVarsPath;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected native build runner to succeed with fake toolchain. Error: ' + lError);
    Assert.AreEqual(0, lExitCode, 'The fake build runner should return success.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one MSBuild launch.');
    Assert.IsTrue(ContainsText(lCapturingRunner.fArguments,
      '/p:FrameworkDirOverride="C:\Program Files\Reference Assemblies"'),
      'Expected environment.proj property to be forwarded to MSBuild arguments.');
    Assert.IsTrue(ContainsText(lCapturingRunner.fArguments, '/p:FrameworkVersionOverride=v4.8'),
      'Expected environment.proj scalar property to be forwarded to MSBuild arguments.');
    Assert.IsFalse(ContainsText(lCapturingRunner.fArguments, '/p:ExistingProp=must-not-override'),
      'Existing process environment values must win over environment.proj overrides.');
    Assert.IsTrue(Pos('DAK_RSVARS_SENTINEL=build-child-env' + #0, lCapturingRunner.fEnvironmentBlocks[0]) > 0,
      'Expected MSBuild child environment to receive rsvars snapshot values.');
  finally
    lRunner := nil;
    lCapturingRunner := nil;
    lEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildCommandAddsCompilerOverlaysToMsBuildArgs;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lFakeBdsRoot: string;
  lOptions: TAppOptions;
  lOverlayPath: string;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lRsVarsPath: string;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'compiler-overlays-build');
  ForceDirectories(lProjectRoot);

  lDprojPath := TPath.Combine(lProjectRoot, 'CompilerOverlaysCheck.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>CompilerOverlaysCheck.dpr</MainSource>' + sLineBreak +
    '    <DCC_Define>BASE;$(DCC_Define)</DCC_Define>' + sLineBreak +
    '    <DCC_UnitSearchPath>src;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program CompilerOverlaysCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(TempRoot, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  lRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(lRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');

  lOverlayPath := TPath.Combine(TempRoot, 'Profiler Runtime');
  SetBuildParams('build --project ' + QuoteArg(lDprojPath) +
    ' --config Debug --platform Win32 --delphi 23.0 --rsvars ' + QuoteArg(lRsVarsPath) +
    ' --define maxProfiling --define PROFILE_EXTRA --unit-search-path ' + QuoteArg(lOverlayPath));

  lError := '';
  Assert.IsTrue(TryParseOptions(lOptions, lError),
    'Expected compiler overlay build command to parse. Error: ' + lError);

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  try
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected native build runner to succeed with fake toolchain. Error: ' + lError);
    Assert.AreEqual(0, lExitCode, 'The fake build runner should return success.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one MSBuild launch.');
    Assert.IsTrue(ContainsText(lCapturingRunner.fArguments,
      '/p:DCC_Define="maxProfiling;PROFILE_EXTRA;BASE;"'),
      'Expected define overlays to be prepended while preserving project defines. Args: ' +
      lCapturingRunner.fArguments);
    Assert.IsTrue(ContainsText(lCapturingRunner.fArguments,
      '/p:DCC_UnitSearchPath="' + lOverlayPath + ';src;"'),
      'Expected unit search path overlays to be prepended while preserving project paths. Args: ' +
      lCapturingRunner.fArguments);
  finally
    lRunner := nil;
    lCapturingRunner := nil;
  end;
end;

procedure TBuildTests.BuildPropertyValueSurvivesRealMsBuildParsing(const aShape: string);
const
  // 'comma' is the shape that failed: MSBuild treats the text after an unquoted comma as a second property.
  cShapes: array[0..6] of string = ('comma', 'semicolon', 'space-trailing-backslash', 'embedded-quote',
    'backslash-before-quote', 'plain-trailing-backslash', 'output-dir');
  cValues: array[0..6] of string = ('alpha,beta', 'alpha;beta', 'C:\Dir With Space\', 'say "hi" now',
    'tail\"q,z', 'C:\NoSpace\', '');
  cTargets =
    '  <Target Name="Build">' + sLineBreak +
    '    <Message Importance="high" Text="DAK372 Value=[$(Dak372Value)]" />' + sLineBreak +
    '    <Message Importance="high" Text="DAK372 ExeOutput=[$(DCC_ExeOutput)]" />' + sLineBreak +
    '    <Message Importance="high" Text="DAK372 Last=[$(Dak372Last)]" />' + sLineBreak +
    '  </Target>' + sLineBreak;
var
  lAppData: string;
  lEnvGuard: IInterface;
  lEnvProps: string;
  lError: string;
  lExitCode: Integer;
  lEvidence: string;
  lOptions: TAppOptions;
  lOutputDir: string;
  lProjectRoot: string;
  lRealRunner: TRealMsBuildRunner;
  lRunner: IBuildProcessRunner;
  lShape: Integer;
begin
  lShape := IndexText(aShape, cShapes);
  Assert.IsTrue(lShape >= 0, 'Unknown property shape: ' + aShape);
  lEnvProps := '';
  if cValues[lShape] <> '' then
    lEnvProps := '    <Dak372Value>' + cValues[lShape] + '</Dak372Value>' + sLineBreak;
  // The last property proves that the value before it did not swallow or split the following arguments.
  lEnvProps := lEnvProps + '    <Dak372Last>sentinel</Dak372Last>' + sLineBreak;

  lOptions := PrepareEnvironmentProjBuild('msbuild-round-trip-' + aShape, cTargets, lEnvProps, lProjectRoot, lAppData);
  lOptions.fBuildQuiet := True;
  lOutputDir := '';
  if SameText(aShape, 'output-dir') then
  begin
    lOutputDir := IncludeTrailingPathDelimiter(TPath.Combine(lProjectRoot, 'out dir'));
    lOptions.fHasBuildTestOutputDir := True;
    lOptions.fBuildTestOutputDir := lOutputDir;
  end;

  lEnvGuard := SetScopedEnvironmentVariables(['APPDATA', lAppData]);
  lRealRunner := TRealMsBuildRunner.Create;
  lRunner := lRealRunner;
  try
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError), 'The build must reach MSBuild. Error: ' + lError);
    lEvidence := ' Arguments: ' + lRealRunner.fArguments + sLineBreak + 'Output: ' + lRealRunner.fOutput;
    Assert.AreEqual(0, lExitCode, 'MSBuild must accept the generated arguments.' + lEvidence);
    Assert.IsTrue(Pos('DAK372 Value=[' + cValues[lShape] + ']', lRealRunner.fOutput) > 0,
      'The environment.proj value must reach MSBuild unchanged.' + lEvidence);
    Assert.IsTrue(Pos('DAK372 ExeOutput=[' + lOutputDir + ']', lRealRunner.fOutput) > 0,
      'The test output directory must reach MSBuild unchanged.' + lEvidence);
    Assert.IsTrue(Pos('DAK372 Last=[sentinel]', lRealRunner.fOutput) > 0,
      'The property after the tested value must still arrive.' + lEvidence);
  finally
    lRunner := nil;
    lEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildDecodesXmlEntitiesInEnvironmentProjValues(const aShape: string);
const
  cShapes: array[0..6] of string = ('ampersand', 'angle-brackets', 'quotes', 'apostrophe', 'numeric',
    'no-double-decode', 'unknown-entity');
  // What environment.proj holds, as XML text.
  cXmlValues: array[0..6] of string = ('a&amp;b', '&lt;x&gt;', '&quot;q&quot;', 'it&apos;s', '&#65;&#x42;&#x63;',
    '&amp;lt;', 'a&bogus;b');
  // What MSBuild must receive.
  cExpected: array[0..6] of string = ('a&b', '<x>', '"q"', 'it''s', 'ABc', '&lt;', 'a&bogus;b');
  cTargets =
    '  <Target Name="Build">' + sLineBreak +
    '    <Message Importance="high" Text="DAK376 Value=[$(Dak376Value)]" />' + sLineBreak +
    '    <Message Importance="high" Text="DAK376 Last=[$(Dak376Last)]" />' + sLineBreak +
    '  </Target>' + sLineBreak;
var
  lAppData: string;
  lEnvGuard: IInterface;
  lError: string;
  lEvidence: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRealRunner: TRealMsBuildRunner;
  lRunner: IBuildProcessRunner;
  lShape: Integer;
begin
  lShape := IndexText(aShape, cShapes);
  Assert.IsTrue(lShape >= 0, 'Unknown entity shape: ' + aShape);
  lOptions := PrepareEnvironmentProjBuild('msbuild-entities-' + aShape, cTargets,
    '    <Dak376Value>' + cXmlValues[lShape] + '</Dak376Value>' + sLineBreak +
    '    <Dak376Last>sentinel</Dak376Last>' + sLineBreak, lProjectRoot, lAppData);
  lOptions.fBuildQuiet := True;

  lEnvGuard := SetScopedEnvironmentVariables(['APPDATA', lAppData]);
  lRealRunner := TRealMsBuildRunner.Create;
  lRunner := lRealRunner;
  try
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError), 'The build must reach MSBuild. Error: ' + lError);
    lEvidence := ' Arguments: ' + lRealRunner.fArguments + sLineBreak + 'Output: ' + lRealRunner.fOutput;
    Assert.AreEqual(0, lExitCode, 'MSBuild must accept the generated arguments.' + lEvidence);
    Assert.IsTrue(Pos('DAK376 Value=[' + cExpected[lShape] + ']', lRealRunner.fOutput) > 0,
      'The decoded environment.proj value must reach MSBuild.' + lEvidence);
    Assert.IsTrue(Pos('DAK376 Last=[sentinel]', lRealRunner.fOutput) > 0,
      'The property after the tested value must still arrive.' + lEvidence);
  finally
    lRunner := nil;
    lEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildSkipsEnvironmentProjValuesWithLineBreaksAndNamesThem;
const
  cSecretLf = 'lf-secret-DAK376';
  cSecretEntity = 'entity-secret-DAK376';
var
  lAppData: string;
  lCapturedOutput: string;
  lCapturingRunner: TCapturingBuildRunner;
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lTracePath: string;
  lTraceText: string;
begin
  lOptions := PrepareEnvironmentProjBuild('msbuild-linebreak-values', '',
    '    <Dak376RawLf>first' + cSecretLf + #10 + 'second</Dak376RawLf>' + sLineBreak +
    '    <Dak376EntityCr>first' + cSecretEntity + '&#13;second</Dak376EntityCr>' + sLineBreak +
    '    <Dak376Fine>plain</Dak376Fine>' + sLineBreak, lProjectRoot, lAppData);
  lOptions.fVerbose := True;
  lTracePath := TPath.Combine(lProjectRoot, 'build-trace.log');

  lEnvGuard := SetScopedEnvironmentVariables(['APPDATA', lAppData, 'DAK_TRACE_BUILD', lTracePath]);
  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  try
    lCapturedOutput := CaptureConsoleOutput(
      procedure
      begin
        Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError), 'Expected the stub build to run. Error: ' + lError);
      end);
    lTraceText := TFile.ReadAllText(lTracePath, TEncoding.UTF8);

    Assert.IsTrue(Pos('/p:Dak376Fine=plain', lCapturingRunner.fArguments) > 0,
      'A well-formed value is still forwarded. Arguments: ' + lCapturingRunner.fArguments);
    Assert.IsFalse(ContainsText(lCapturingRunner.fArguments, 'Dak376RawLf'),
      'A value with a line break must not be forwarded. Arguments: ' + lCapturingRunner.fArguments);
    Assert.IsFalse(ContainsText(lCapturingRunner.fArguments, 'Dak376EntityCr'),
      'A value that decodes to a line break must not be forwarded. Arguments: ' + lCapturingRunner.fArguments);
    Assert.IsTrue(ContainsText(lCapturedOutput, 'Dak376RawLf'), 'The skipped property must be named on --verbose.');
    Assert.IsTrue(ContainsText(lCapturedOutput, 'Dak376EntityCr'), 'The skipped property must be named on --verbose.');
    Assert.IsTrue(ContainsText(lTraceText, 'Dak376RawLf'), 'The skipped property must be named in the trace.');
    Assert.IsTrue(ContainsText(lCapturedOutput, 'skipped Dak376RawLf'), 'The skip line must name the property.');
    Assert.IsFalse(ContainsText(lCapturedOutput, 'skipped Dak376Fine'), 'A forwarded property is not reported as skipped.');
    Assert.IsFalse(ContainsText(lCapturedOutput, cSecretLf) or ContainsText(lCapturedOutput, cSecretEntity),
      'A skipped environment.proj value reached the verbose output.');
    Assert.IsFalse(ContainsText(lTraceText, cSecretLf) or ContainsText(lTraceText, cSecretEntity),
      'A skipped environment.proj value reached the trace file.');
  finally
    lRunner := nil;
    lEnvGuard := nil;
  end;
end;

// DAK-376 policy (architect, 2026-09-30): DAK cannot know which variables a project references, so every
// environment.proj property that the process environment lacks is forwarded, as the IDE does (DAK-068).
procedure TBuildTests.BuildForwardsEveryMissingEnvironmentProjPropertyAndProcessEnvironmentWins;
var
  lAppData: string;
  lCapturingRunner: TCapturingBuildRunner;
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
begin
  lOptions := PrepareEnvironmentProjBuild('msbuild-forwarding-policy', '',
    '    <Dak376CustomOnlyHere>custom-value</Dak376CustomOnlyHere>' + sLineBreak +
    '    <Dak376InProcess>from-environment-proj</Dak376InProcess>' + sLineBreak, lProjectRoot, lAppData);
  lOptions.fBuildQuiet := True;

  lEnvGuard := SetScopedEnvironmentVariables(['APPDATA', lAppData, 'Dak376InProcess', 'from-process']);
  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  try
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError), 'Expected the stub build to run. Error: ' + lError);
    Assert.IsTrue(Pos('/p:Dak376CustomOnlyHere=custom-value', lCapturingRunner.fArguments) > 0,
      'A property that only environment.proj holds must be forwarded. Arguments: ' + lCapturingRunner.fArguments);
    Assert.IsFalse(ContainsText(lCapturingRunner.fArguments, 'Dak376InProcess'),
      'The process environment wins over environment.proj. Arguments: ' + lCapturingRunner.fArguments);
  finally
    lRunner := nil;
    lEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildVerboseTraceRedactsEnvironmentProjValues;
const
  cSecret = 'hunter2-DAK372';
var
  lAppData: string;
  lCapturedOutput: string;
  lCapturingRunner: TCapturingBuildRunner;
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lTraceText: string;
  lTracePath: string;
begin
  lOptions := PrepareEnvironmentProjBuild('msbuild-args-trace', '',
    '    <Dak372Secret>' + cSecret + ',second part</Dak372Secret>' + sLineBreak, lProjectRoot, lAppData);
  lOptions.fVerbose := True;
  lTracePath := TPath.Combine(lProjectRoot, 'build-trace.log');

  lEnvGuard := SetScopedEnvironmentVariables(['APPDATA', lAppData, 'DAK_TRACE_BUILD', lTracePath]);
  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  try
    lCapturedOutput := CaptureConsoleOutput(
      procedure
      begin
        Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError), 'Expected the stub build to run. Error: ' + lError);
      end);
    lTraceText := TFile.ReadAllText(lTracePath, TEncoding.UTF8);

    Assert.IsTrue(Pos('/p:Dak372Secret="' + cSecret + ',second part"', lCapturingRunner.fArguments) > 0,
      'MSBuild itself must still receive the value. Arguments: ' + lCapturingRunner.fArguments);
    Assert.IsTrue(Pos('[build] msbuild-args: ', lCapturedOutput) > 0,
      '--verbose must retain the generated MSBuild arguments. Output: ' + lCapturedOutput);
    Assert.IsTrue(Pos('/p:Config=Debug', lCapturedOutput) > 0,
      'Arguments that are not from environment.proj stay readable. Output: ' + lCapturedOutput);
    Assert.IsTrue(Pos('/p:Dak372Secret=<redacted>', lCapturedOutput) > 0,
      'The property name is kept and its value redacted. Output: ' + lCapturedOutput);
    Assert.IsTrue(Pos('/p:Dak372Secret=<redacted>', lTraceText) > 0,
      'The DAK_TRACE_BUILD file records the same redacted arguments. Trace: ' + lTraceText);
    Assert.IsFalse(ContainsText(lCapturedOutput, cSecret), 'An environment.proj value reached the verbose output.');
    Assert.IsFalse(ContainsText(lCapturedOutput, 'second part'), 'An environment.proj value reached the verbose output.');
    Assert.IsFalse(ContainsText(lTraceText, cSecret), 'An environment.proj value reached the trace file.');
  finally
    lRunner := nil;
    lEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildNamesPropertyRejectedByMsBuild(const aLocale: string; aIdentifiable: Boolean);
const
  cSecret = 'hunter2-DAK372';
  cRejectedPart = 'tail-DAK372';
  cUnknownPart = 'unrelated-DAK372';
var
  lAppData: string;
  lCapturedOutput: string;
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lFailingRunner: TFailingBuildRunner;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lSwitchLine: string;
begin
  lOptions := PrepareEnvironmentProjBuild('msbuild-rejected-property-' + aLocale + IfThen(aIdentifiable, '', '-unknown'),
    '', '    <Dak372Comma>' + cSecret + ',' + cRejectedPart + '</Dak372Comma>' + sLineBreak, lProjectRoot, lAppData);

  lFailingRunner := TFailingBuildRunner.Create;
  lRunner := lFailingRunner;
  // MSBuild reports MSB1006 in the user's language and repeats the rejected text on the next line.
  if SameText(aLocale, 'pl') then
  begin
    lFailingRunner.fStdOutText := 'MSBUILD : error MSB1006: w'#$0142'a'#$015B'ciwo'#$015B#$0107' jest nieprawid'#$0142'owa.';
    lSwitchLine := 'Prze'#$0142#$0105'cznik: ';
  end else begin
    lFailingRunner.fStdOutText := 'MSBUILD : error MSB1006: Property is not valid.';
    lSwitchLine := 'Switch: ';
  end;
  if aIdentifiable then
    lSwitchLine := lSwitchLine + cRejectedPart
  else
    lSwitchLine := lSwitchLine + cUnknownPart;
  lFailingRunner.fStdOutText := lFailingRunner.fStdOutText + sLineBreak + lSwitchLine + sLineBreak;

  lEnvGuard := SetScopedEnvironmentVariables(['APPDATA', lAppData]);
  try
    lCapturedOutput := CaptureConsoleOutput(
      procedure
      begin
        Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
          'Expected the rejected build to be summarized. Error: ' + lError);
      end);

    Assert.AreEqual(1, lExitCode, 'The MSBuild failure stays a failure.');
    Assert.IsTrue(Pos('MSB1006', lCapturedOutput) > 0, 'The MSBuild error stays visible. Output: ' + lCapturedOutput);
    if aIdentifiable then
    begin
      Assert.IsTrue(Pos('/p:Dak372Comma', lCapturedOutput) > 0,
        'The rejected property must be named. Output: ' + lCapturedOutput);
      Assert.IsTrue(Pos('environment.proj', lCapturedOutput) > 0,
        'The origin of the rejected property must be named. Output: ' + lCapturedOutput);
    end else begin
      Assert.IsFalse(Pos('/p:Dak372Comma', lCapturedOutput) > 0,
        'A property MSBuild did not reject must not be blamed. Output: ' + lCapturedOutput);
      Assert.IsTrue(Pos('--verbose', lCapturedOutput) > 0,
        'An unidentified rejection must say how to list the generated arguments. Output: ' + lCapturedOutput);
    end;
    Assert.IsFalse(ContainsText(lCapturedOutput, cSecret), 'An environment.proj value reached the build output.');
    Assert.IsFalse(ContainsText(lCapturedOutput, cRejectedPart), 'An environment.proj value reached the build output.');
    Assert.IsFalse(ContainsText(lCapturedOutput, cUnknownPart), 'MSBuild''s rejected text reached the build output.');
  finally
    lRunner := nil;
    lEnvGuard := nil;
  end;
end;

function TLogRetentionBuildRunner.RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
  const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
  out aTimedOut: Boolean; out aError: string): Boolean;
var
  lRunDir: string;
begin
  Inc(fCallCount);
  fRunDirsAtStart := 0;
  if (fLogRoot <> '') and TDirectory.Exists(fLogRoot) then
    fRunDirsAtStart := Length(TDirectory.GetDirectories(fLogRoot, 'run-*'));
  if fRaise then
    raise EInvalidOpException.Create('simulated process launcher failure');
  if fReturnFalse then
  begin
    aExitCode := 1;
    aTimedOut := False;
    aError := 'simulated launch failure';
    Exit(False);
  end;
  ForceDirectories(ExtractFileDir(aStdOutPath));
  TFile.WriteAllText(aStdOutPath, fStdOutText, TEncoding.UTF8);
  TFile.WriteAllText(aStdErrPath, fStdErrText, TEncoding.UTF8);
  if fBreakStdOutCopy then
    for lRunDir in TDirectory.GetDirectories(fLogRoot, 'run-*') do
      TDirectory.CreateDirectory(TPath.Combine(lRunDir, 'stdout.log'));
  aExitCode := fExitCode;
  aTimedOut := False;
  aError := '';
  Result := True;
end;

const
  cKeepLogsDiagnosticsEnvVar = 'DAK_BUILD_DIAGNOSTICS_DIR';
  cKeptLogsPrefix = 'Build logs kept: ';

// DAK-379: a project fixture whose environment (APPDATA, diagnostics variable) cannot reach the machine's own.
function PrepareKeepLogsBuild(const aName: string; out aProjectRoot: string; out aEnvGuard: IInterface): TAppOptions;
var
  lAppData: string;
begin
  Result := PrepareEnvironmentProjBuild(aName, '', '', aProjectRoot, lAppData);
  aEnvGuard := SetScopedEnvironmentVariables(['APPDATA', lAppData, cKeepLogsDiagnosticsEnvVar, '']);
end;

procedure ApplyOutputMode(var aOptions: TAppOptions; const aMode: string);
begin
  aOptions.fBuildJson := SameText(aMode, 'json');
  aOptions.fBuildAi := SameText(aMode, 'ai');
end;

function ParseLastJsonLine(const aOutput: string): TJSONObject;
var
  lLine: string;
  lValue: TJSONValue;
begin
  Result := nil;
  for lLine in aOutput.Split([#13#10, #10]) do
    if lLine.StartsWith('{') then
    begin
      lValue := TJSONObject.ParseJSONValue(lLine);
      if lValue is TJSONObject then
        Result := TJSONObject(lValue)
      else
        lValue.Free;
    end;
end;

function JsonStringField(const aOutput, aName: string): string;
var
  lJson: TJSONObject;
begin
  Result := '';
  lJson := ParseLastJsonLine(aOutput);
  try
    if Assigned(lJson) then
      lJson.TryGetValue<string>(aName, Result);
  finally
    lJson.Free;
  end;
end;

// The kept directory as the user would read it: the JSON field, or the line of the text and --ai summaries.
function KeptLogsDirFromOutput(const aMode, aOutput: string): string;
var
  lLine: string;
begin
  if SameText(aMode, 'json') then
    Exit(JsonStringField(aOutput, 'kept_logs_dir'));
  Result := '';
  for lLine in aOutput.Split([#13#10, #10]) do
    if lLine.StartsWith(cKeptLogsPrefix) then
      Result := Copy(lLine, Length(cKeptLogsPrefix) + 1, MaxInt);
end;

function RunKeepLogsBuild(const aOptions: TAppOptions; const aRunner: IBuildProcessRunner;
  out aExitCode: Integer; out aError: string): string;
var
  lExitCode: Integer;
  lError: string;
  lOptions: TAppOptions;
begin
  lOptions := aOptions;
  lExitCode := -1;
  lError := '';
  Result := CaptureConsoleOutput(
    procedure
    begin
      Assert.IsTrue(TryRunBuild(lOptions, aRunner, lExitCode, lError),
        'Expected the build to be summarized. Error: ' + lError);
    end);
  aExitCode := lExitCode;
  aError := lError;
end;

procedure AssertKeptLogs(const aKeptDir, aExpectedRoot, aStdOutText, aStdErrText: string);
begin
  Assert.AreEqual(ExcludeTrailingPathDelimiter(aExpectedRoot), ExtractFileDir(aKeptDir),
    'The run directory belongs under the log root.');
  Assert.IsTrue(StartsText('run-', ExtractFileName(aKeptDir)), aKeptDir);
  Assert.AreEqual(Length('run-') + 36, Length(ExtractFileName(aKeptDir)), 'run-<guid>: ' + aKeptDir);
  Assert.AreEqual(aStdOutText, TFile.ReadAllText(TPath.Combine(aKeptDir, 'stdout.log'), TEncoding.UTF8));
  Assert.AreEqual(aStdErrText, TFile.ReadAllText(TPath.Combine(aKeptDir, 'stderr.log'), TEncoding.UTF8));
  Assert.AreEqual(2, Integer(Length(TDirectory.GetFiles(aKeptDir))), 'Only stdout.log and stderr.log are kept.');
end;

procedure TBuildTests.BuildRetainsNoLogsByDefault;
var
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
begin
  lOptions := PrepareKeepLogsBuild('keep-logs-default-off', lProjectRoot, lEnvGuard);
  lOptions.fBuildJson := True;
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lRunner.fStdOutText := 'stdout that must not be kept';

  lOutput := RunKeepLogsBuild(lOptions, lRunnerIntf, lExitCode, lError);

  Assert.AreEqual(1, lRunner.fCallCount, 'The build itself must still run.');
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(lProjectRoot, '.dak')),
    'Without --keep-logs nothing is written under .dak.');
  Assert.IsFalse(ContainsText(lOutput, 'kept_logs'), 'The JSON summary only names kept logs when asked: ' + lOutput);
end;

procedure TBuildTests.BuildKeepLogsRetainsRunLogsUnderProjectDak(const aMode: string);
var
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lKeptDir: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
begin
  lOptions := PrepareKeepLogsBuild('keep-logs-default-root-' + aMode, lProjectRoot, lEnvGuard);
  lOptions.fBuildKeepLogs := True;
  ApplyOutputMode(lOptions, aMode);
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lRunner.fExitCode := 1;
  lRunner.fStdOutText := 'stdout marker ' + aMode;
  lRunner.fStdErrText := 'stderr marker ' + aMode;
  lRunner.fLogRoot := TPath.Combine(lProjectRoot, '.dak\EnvProps372\build');

  lOutput := RunKeepLogsBuild(lOptions, lRunnerIntf, lExitCode, lError);

  Assert.AreEqual(1, lExitCode, 'Keeping logs must not change the MSBuild exit code.');
  Assert.AreEqual(1, lRunner.fRunDirsAtStart, 'The run directory exists before the build starts.');
  lKeptDir := KeptLogsDirFromOutput(aMode, lOutput);
  Assert.AreNotEqual('', lKeptDir, 'The kept directory must be reported. Output: ' + lOutput);
  AssertKeptLogs(lKeptDir, lRunner.fLogRoot, lRunner.fStdOutText, lRunner.fStdErrText);
  if SameText(aMode, 'json') then
  begin
    Assert.AreEqual('', JsonStringField(lOutput, 'kept_logs_error'), lOutput);
    Assert.AreEqual('error', JsonStringField(lOutput, 'status'), 'Existing fields stay as they were: ' + lOutput);
  end else
    Assert.IsFalse(ContainsText(lOutput, 'could not be kept'), lOutput);
end;

procedure TBuildTests.BuildLogDirResolvesRelativeToProjectDirectory;
const
  cRelativeRoot = 'rel logs DAK379\sub dir\';
var
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lKeptDir: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
begin
  lOptions := PrepareKeepLogsBuild('keep-logs-relative', lProjectRoot, lEnvGuard);
  lOptions.fBuildKeepLogs := True;
  lOptions.fBuildLogDir := cRelativeRoot;
  lOptions.fBuildJson := True;
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lRunner.fStdOutText := 'relative stdout';
  lRunner.fStdErrText := 'relative stderr';

  lOutput := RunKeepLogsBuild(lOptions, lRunnerIntf, lExitCode, lError);

  lKeptDir := KeptLogsDirFromOutput('json', lOutput);
  AssertKeptLogs(lKeptDir, TPath.Combine(lProjectRoot, 'rel logs DAK379\sub dir'), lRunner.fStdOutText,
    lRunner.fStdErrText);
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(GetCurrentDir, 'rel logs DAK379')),
    'A relative --log-dir is resolved against the project directory, not the working directory.');
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(lProjectRoot, '.dak')), 'A custom root replaces the default one.');
end;

procedure TBuildTests.BuildLogDirAcceptsAbsolutePath;
var
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lKeptDir: string;
  lLogRoot: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
begin
  lOptions := PrepareKeepLogsBuild('keep-logs-absolute', lProjectRoot, lEnvGuard);
  lLogRoot := TPath.Combine(UniqueNoRepoTempPath('keep-logs-absolute'), 'caller logs');
  lOptions.fBuildKeepLogs := True;
  lOptions.fBuildLogDir := lLogRoot;
  lOptions.fBuildAi := True;
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lRunner.fStdOutText := 'absolute stdout';
  lRunner.fStdErrText := 'absolute stderr';
  try
    lOutput := RunKeepLogsBuild(lOptions, lRunnerIntf, lExitCode, lError);

    lKeptDir := KeptLogsDirFromOutput('ai', lOutput);
    AssertKeptLogs(lKeptDir, lLogRoot, lRunner.fStdOutText, lRunner.fStdErrText);
    Assert.IsFalse(TDirectory.Exists(TPath.Combine(lProjectRoot, '.dak')), 'An absolute root is used as given.');
  finally
    DeleteTempPath(ExtractFileDir(lLogRoot));
  end;
end;

procedure TBuildTests.BuildKeepLogsGivesEveryRunItsOwnDirectory;
var
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lFirst: string;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
  lSecond: string;
begin
  lOptions := PrepareKeepLogsBuild('keep-logs-unique', lProjectRoot, lEnvGuard);
  lOptions.fBuildKeepLogs := True;
  lOptions.fBuildJson := True;
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lRunner.fStdOutText := 'unique stdout';

  lFirst := KeptLogsDirFromOutput('json', RunKeepLogsBuild(lOptions, lRunnerIntf, lExitCode, lError));
  lSecond := KeptLogsDirFromOutput('json', RunKeepLogsBuild(lOptions, lRunnerIntf, lExitCode, lError));

  Assert.AreNotEqual('', lFirst);
  Assert.AreNotEqual(lFirst, lSecond, 'Two builds against the same log root must not share a directory.');
  Assert.AreEqual(2, Integer(Length(TDirectory.GetDirectories(ExtractFileDir(lFirst), 'run-*'))));
  Assert.IsTrue(TFile.Exists(TPath.Combine(lFirst, 'stdout.log')), lFirst);
  Assert.IsTrue(TFile.Exists(TPath.Combine(lSecond, 'stdout.log')), lSecond);
end;

procedure TBuildTests.BuildKeepLogsFailsBeforeBuildWhenDirectoryCannotBeCreated;
var
  lBlocker: string;
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
begin
  lOptions := PrepareKeepLogsBuild('keep-logs-uncreatable', lProjectRoot, lEnvGuard);
  // A regular file where a directory must go: no run directory can exist beneath it.
  lBlocker := TPath.Combine(lProjectRoot, 'not a directory.txt');
  WriteUtf8File(lBlocker, 'file');
  lOptions.fBuildKeepLogs := True;
  lOptions.fBuildLogDir := 'not a directory.txt\logs';
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lError := '';

  Assert.IsFalse(TryRunBuild(lOptions, lRunnerIntf, lExitCode, lError),
    'A log directory that cannot be created is a failure, never a silent skip.');
  Assert.IsTrue(ContainsText(lError, 'Build log directory could not be created'), lError);
  Assert.IsTrue(ContainsText(lError, 'not a directory.txt'), 'The message names the path. ' + lError);
  Assert.AreEqual(0, lRunner.fCallCount, 'The build must not start when its logs cannot be kept.');
end;

procedure TBuildTests.BuildKeepLogsReportsLogCopyFailureWithBuildResult(const aMode: string; aBuildExitCode: Integer);
var
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lLogRoot: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
begin
  lOptions := PrepareKeepLogsBuild('keep-logs-copy-failure-' + aMode, lProjectRoot, lEnvGuard);
  lLogRoot := TPath.Combine(UniqueNoRepoTempPath('keep-logs-copy-failure'), 'logs');
  lOptions.fBuildKeepLogs := True;
  lOptions.fBuildLogDir := lLogRoot;
  ApplyOutputMode(lOptions, aMode);
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lRunner.fBreakStdOutCopy := True;
  lRunner.fLogRoot := lLogRoot;
  lRunner.fExitCode := aBuildExitCode;
  lRunner.fStdOutText := 'copy failure stdout';
  try
    lOutput := RunKeepLogsBuild(lOptions, lRunnerIntf, lExitCode, lError);

    Assert.AreNotEqual(0, lExitCode, 'A build whose logs were lost cannot report success. Output: ' + lOutput);
    if aBuildExitCode <> 0 then
      Assert.AreEqual(aBuildExitCode, lExitCode, 'The MSBuild exit code stays the reported one.');
    if SameText(aMode, 'json') then
    begin
      Assert.IsTrue(ContainsText(JsonStringField(lOutput, 'kept_logs_error'), 'stdout.log'), lOutput);
      Assert.AreNotEqual('', JsonStringField(lOutput, 'kept_logs_dir'), 'The directory that holds what was kept. ' + lOutput);
      if aBuildExitCode <> 0 then
        Assert.AreEqual('error', JsonStringField(lOutput, 'status'), 'The build failure stays visible. ' + lOutput)
      else
        Assert.AreEqual('internal_error', JsonStringField(lOutput, 'status'), lOutput);
    end else
    begin
      Assert.IsTrue(ContainsText(lOutput, 'Build logs could not be kept'), lOutput);
      Assert.IsTrue(ContainsText(lOutput, 'stdout.log'), lOutput);
    end;
  finally
    DeleteTempPath(ExtractFileDir(lLogRoot));
  end;
end;

procedure TBuildTests.BuildLogDirThatCannotBeUsedIsANamedFailure(const aLogDir: string);
var
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
begin
  lOptions := PrepareKeepLogsBuild('keep-logs-unusable', lProjectRoot, lEnvGuard);
  lOptions.fBuildKeepLogs := True;
  lOptions.fBuildLogDir := aLogDir;
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lError := '';

  // Invalid path characters and a drive-relative root must be reported, not raised or resolved against
  // the working directory's drive.
  Assert.IsFalse(TryRunBuild(lOptions, lRunnerIntf, lExitCode, lError), aLogDir);
  Assert.IsTrue(ContainsText(lError, 'Build log directory'), lError);
  Assert.AreEqual(0, lRunner.fCallCount, 'The build must not start when its logs cannot be kept.');
end;

procedure TBuildTests.BuildKeepLogsSurvivesConcurrentCreationOfAFreshRoot;
const
  cRoots = 40;
  cThreads = 8;
var
  lBase: string;
  lDirs: TArray<TArray<string>>;
  lErrors: TArray<string>;
  lFailures: Integer;
  lLoop: TParallel.TLoopResult;
  lSeen: TDictionary<string, Boolean>;
  lText: string;
begin
  lBase := UniqueNoRepoTempPath('keep-logs-race');
  SetLength(lDirs, cThreads);
  SetLength(lErrors, cThreads);
  try
    lLoop := TParallel.For(0, cThreads - 1,
      procedure(aThread: Integer)
      var
        lError: string;
        lOptions: TAppOptions;
        lRoot: Integer;
        lRunDir: string;
      begin
        lOptions := Default(TAppOptions);
        lOptions.fDprojPath := TPath.Combine(lBase, 'Race.dproj');
        lOptions.fBuildKeepLogs := True;
        for lRoot := 0 to cRoots - 1 do
        begin
          // Every thread races for the same fresh, nested root: each shares its parents with the others.
          lOptions.fBuildLogDir := TPath.Combine(lBase, 'root ' + IntToStr(lRoot) + '\a\b');
          if TryCreateBuildLogRunDir(lOptions, lRunDir, lError) then
          begin
            SetLength(lDirs[aThread], Length(lDirs[aThread]) + 1);
            lDirs[aThread][High(lDirs[aThread])] := lRunDir;
          end else if lErrors[aThread] = '' then
            lErrors[aThread] := lError;
        end;
      end);
    Assert.IsTrue(lLoop.Completed, 'All threads must finish');
    lFailures := 0;
    lText := '';
    lSeen := TDictionary<string, Boolean>.Create;
    try
      for var i := 0 to cThreads - 1 do
      begin
        if lErrors[i] <> '' then
          lText := lErrors[i];
        lFailures := lFailures + cRoots - Length(lDirs[i]);
        for var lDir in lDirs[i] do
          lSeen.AddOrSetValue(lDir, True);
      end;
      Assert.AreEqual(0, lFailures, 'Concurrent builds on a fresh root must all succeed. ' + lText);
      Assert.AreEqual(Integer(cThreads * cRoots), Integer(lSeen.Count), 'Every build needs its own run directory.');
    finally
      lSeen.Free;
    end;
  finally
    DeleteTempPath(lBase);
  end;
end;

procedure TBuildTests.BuildKeepLogsReportsOnlyTheFailureWhenLogsCannotBeCopied;
var
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lLogRoot: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
begin
  lOptions := PrepareKeepLogsBuild('keep-logs-only-failure', lProjectRoot, lEnvGuard);
  lLogRoot := TPath.Combine(UniqueNoRepoTempPath('keep-logs-only-failure'), 'logs');
  lOptions.fBuildKeepLogs := True;
  lOptions.fBuildLogDir := lLogRoot;
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lRunner.fBreakStdOutCopy := True;
  lRunner.fLogRoot := lLogRoot;
  try
    lOutput := RunKeepLogsBuild(lOptions, lRunnerIntf, lExitCode, lError);

    Assert.IsTrue(ContainsText(lOutput, 'Build logs could not be kept'), lOutput);
    Assert.IsTrue(ContainsText(lOutput, lLogRoot), 'The failure names the directory. ' + lOutput);
    Assert.IsFalse(ContainsText(lOutput, 'Build logs kept:'), 'A success line on a failed path. ' + lOutput);
  finally
    DeleteTempPath(ExtractFileDir(lLogRoot));
  end;
end;

procedure TBuildTests.BuildKeepLogsRemovesTheEmptyRunDirectoryWhenTheProcessProducesNothing(const aMode: string);
var
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lLogRoot: string;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRaised: Boolean;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
begin
  lOptions := PrepareKeepLogsBuild('keep-logs-empty-' + aMode, lProjectRoot, lEnvGuard);
  lLogRoot := TPath.Combine(UniqueNoRepoTempPath('keep-logs-empty'), 'logs');
  lOptions.fBuildKeepLogs := True;
  lOptions.fBuildLogDir := lLogRoot;
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lRunner.fRaise := SameText(aMode, 'raise');
  lRunner.fReturnFalse := SameText(aMode, 'false');
  lError := '';
  try
    if lRunner.fRaise then
    begin
      lRaised := False;
      try
        TryRunBuild(lOptions, lRunnerIntf, lExitCode, lError);
      except
        on EInvalidOpException do
          lRaised := True;
      end;
      Assert.IsTrue(lRaised, 'The launcher exception must reach the caller.');
    end else
    begin
      Assert.IsFalse(TryRunBuild(lOptions, lRunnerIntf, lExitCode, lError), 'The launch failure is reported.');
      Assert.IsTrue(ContainsText(lError, 'simulated launch failure'), lError);
    end;
    Assert.AreEqual(1, lRunner.fCallCount);
    Assert.AreEqual(0, Integer(Length(TDirectory.GetDirectories(lLogRoot, 'run-*'))),
      'An empty run directory must not be left behind.');
  finally
    DeleteTempPath(ExtractFileDir(lLogRoot));
  end;
end;

procedure TBuildTests.BuildDiagnosticsDirEnvVarKeepsWorkingWithoutKeepLogs;
var
  lAppData: string;
  lDiagnosticsDir: string;
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: TLogRetentionBuildRunner;
  lRunnerIntf: IBuildProcessRunner;
begin
  lOptions := PrepareEnvironmentProjBuild('keep-logs-env-var', '', '', lProjectRoot, lAppData);
  lDiagnosticsDir := TPath.Combine(lProjectRoot, 'env diagnostics');
  lEnvGuard := SetScopedEnvironmentVariables(['APPDATA', lAppData, cKeepLogsDiagnosticsEnvVar, lDiagnosticsDir]);
  lRunner := TLogRetentionBuildRunner.Create;
  lRunnerIntf := lRunner;
  lRunner.fStdOutText := 'env var stdout';

  RunKeepLogsBuild(lOptions, lRunnerIntf, lExitCode, lError);

  Assert.AreEqual('env var stdout', TFile.ReadAllText(TPath.Combine(lDiagnosticsDir, 'stdout.log'), TEncoding.UTF8));
  Assert.IsTrue(TFile.Exists(TPath.Combine(lDiagnosticsDir, 'stderr.log')), lDiagnosticsDir);
  Assert.IsFalse(TDirectory.Exists(TPath.Combine(lProjectRoot, '.dak')),
    'The environment variable does not start keeping logs under .dak.');
end;

procedure TBuildTests.RsVarsLoaderIgnoresStaleRadEnvironmentAndOverlongPath;
var
  lError: string;
  lEnvGuard: IInterface;
  lEnvironment: TRsVarsEnvironment;
  lPathCapture: string;
  lRoot: string;
  lRsVarsPath: string;
  lScriptText: string;
begin
  EnsureTempClean;
  lRoot := TPath.Combine(TempRoot, 'rsvars-clean-env');
  ForceDirectories(lRoot);
  lRsVarsPath := TPath.Combine(lRoot, 'rsvars.bat');
  lPathCapture := TPath.Combine(lRoot, 'path.txt');
  lScriptText := '@echo off' + sLineBreak +
    'if defined BDS exit /b 17' + sLineBreak +
    'if defined BDSLIB exit /b 18' + sLineBreak +
    'if defined DCC_Define exit /b 19' + sLineBreak +
    'if defined DCC_Namespace exit /b 20' + sLineBreak +
    'if defined DCC_UnitSearchPath exit /b 21' + sLineBreak +
    'echo %PATH%>' + QuoteArg(lPathCapture) + sLineBreak +
    'if not "%PATH:stale-path-marker=%"=="%PATH%" exit /b 22' + sLineBreak +
    'set BDS=clean-bds' + sLineBreak +
    'set BDSLIB=clean-lib' + sLineBreak +
    'set DCC_Define=clean-define' + sLineBreak +
    'set DCC_Namespace=clean-namespace' + sLineBreak +
    'set DCC_UnitSearchPath=clean-search-path' + sLineBreak;
  TFile.WriteAllText(lRsVarsPath, lScriptText, TEncoding.ASCII);

  lEnvGuard := SetScopedEnvironmentVariables([
    'BDS', 'stale-bds',
    'BDSLIB', 'stale-bdslib',
    'DCC_Define', 'stale-define',
    'DCC_Namespace', 'stale-namespace',
    'DCC_UnitSearchPath', 'stale-search-path',
    'PATH', 'C:\stale-path-marker;' + StringOfChar('x', 7000)
  ]);
  try
    Assert.IsTrue(TryLoadRsVars('', lRsVarsPath, nil, lEnvironment, lError),
      'Expected rsvars loader to sanitize stale child environment. Error: ' + lError);
    Assert.AreEqual('clean-bds', lEnvironment.ValueOrDefault('BDS'));
    Assert.AreEqual('clean-lib', lEnvironment.ValueOrDefault('BDSLIB'));
    Assert.AreEqual('clean-define', lEnvironment.ValueOrDefault('DCC_Define'));
    Assert.AreEqual('clean-namespace', lEnvironment.ValueOrDefault('DCC_Namespace'));
    Assert.AreEqual('clean-search-path', lEnvironment.ValueOrDefault('DCC_UnitSearchPath'));
    Assert.AreEqual('stale-bds', GetEnvironmentVariable('BDS'));
    Assert.AreEqual('stale-bdslib', GetEnvironmentVariable('BDSLIB'));
    Assert.AreEqual('stale-define', GetEnvironmentVariable('DCC_Define'));
    Assert.AreEqual('stale-namespace', GetEnvironmentVariable('DCC_Namespace'));
    Assert.AreEqual('stale-search-path', GetEnvironmentVariable('DCC_UnitSearchPath'));
    Assert.IsTrue(ContainsText(GetEnvironmentVariable('PATH'), 'stale-path-marker'),
      'Expected parent PATH to remain unchanged after rsvars capture.');
    Assert.IsTrue(TFile.Exists(lPathCapture), 'Expected fake rsvars to capture PATH.');
    Assert.IsFalse(ContainsText(TFile.ReadAllText(lPathCapture, TEncoding.ASCII), 'stale-path-marker'),
      'Expected long inherited PATH to be trimmed before rsvars.bat.');
  finally
    lEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildSkipsMadExceptPatchWhenMesDisablesMadExcept;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-disabled-build');
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=0' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed with fake toolchain. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Disabled madExcept in .mes should not fail the build.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'madExcept patch should be skipped when .mes disables exception handling. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(SameText(lCapturingRunner.fExePaths[0], TPath.Combine(TPath.GetDirectoryName(lRsVarsPath), 'MSBuild.exe')),
    'Expected the first process invocation to be MSBuild. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildSkipsMadExceptPatchWhenMesDisablesLinkInCode;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-link-disabled-build');
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=0' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed with fake toolchain. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Disabled LinkInCode in .mes should not fail the build.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'madExcept patch should be skipped when .mes disables LinkInCode. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(SameText(lCapturingRunner.fExePaths[0], TPath.Combine(TPath.GetDirectoryName(lRsVarsPath), 'MSBuild.exe')),
    'Expected the first process invocation to be MSBuild. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildSkipsMadExceptPatchWhenUtf8BomMesDisablesMadExcept;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-bom-disabled-build');
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=0' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);
  WriteUtf8File(TPath.ChangeExtension(lDprojPath, '.mes'),
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=0' + sLineBreak +
    'LinkInCode=1' + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed with fake toolchain. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'BOM-encoded disabled .mes should not fail the build.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'madExcept patch should be skipped when a UTF-8 BOM .mes disables exception handling. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(SameText(lCapturingRunner.fExePaths[0], TPath.Combine(TPath.GetDirectoryName(lRsVarsPath), 'MSBuild.exe')),
    'Expected the first process invocation to be MSBuild. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildStillRunsMadExceptPatchWhenMesEnablesMadExcept;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lExpectedOutputPath: string;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-enabled-build');
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);
  lExpectedOutputPath := TPath.Combine(lProjectRoot, 'MesGateCheck.exe');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lExpectedOutputPath);
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed with fake toolchain. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Enabled madExcept in .mes should keep the patch step green.');
  Assert.AreEqual(2, lCapturingRunner.fCallCount,
    'madExcept patch should run when .mes still enables exception handling. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(SameText(lCapturingRunner.fExePaths[1], lPatchExePath),
    'Expected the second process invocation to be madExceptPatch.exe. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildResolvesMadExceptOutputPathFromCfgDependentOnOptset;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lExpectedOutputPath: string;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-optset-output-build');
  PrepareMadExceptBuildFixtureWithOptset(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    '    <DCC_ExeOutput>bin\$(CONFIG)\$(PLATFORM)</DCC_ExeOutput>' + sLineBreak,
    '', lDprojPath, lRsVarsPath, lPatchExePath);

  lExpectedOutputPath := TPath.Combine(lProjectRoot, 'bin\Debug\Win32\MesGateCheck.exe');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lExpectedOutputPath);
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed with imported optset output path. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected build to stay green when the imported optset output exists.');
  Assert.AreEqual(2, lCapturingRunner.fCallCount,
    'Expected MSBuild followed by madExcept patch. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], 'bin\Debug\Win32\MesGateCheck.exe'),
    'Expected madExcept patch to target the imported optset output path. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildProjectPropertiesOverrideCfgDependentOnOptsetOutputPath;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lExpectedOutputPath: string;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-optset-override-output-build');
  PrepareMadExceptBuildFixtureWithOptset(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    '    <DCC_ExeOutput>optset-bin\$(Config)\$(Platform)</DCC_ExeOutput>' + sLineBreak,
    '    <DCC_ExeOutput>project-bin\$(Config)\$(Platform)</DCC_ExeOutput>' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);

  lExpectedOutputPath := TPath.Combine(lProjectRoot, 'project-bin\Debug\Win32\MesGateCheck.exe');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lExpectedOutputPath);
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to succeed when project output overrides imported optset output. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected project-local DCC_ExeOutput override to stay green.');
  Assert.AreEqual(2, lCapturingRunner.fCallCount,
    'Expected MSBuild followed by madExcept patch. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], 'project-bin\Debug\Win32\MesGateCheck.exe'),
    'Expected madExcept patch to use the project-local output override. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsFalse(ContainsText(lCapturingRunner.fArgumentsList[1], 'optset-bin\Debug\Win32\MesGateCheck.exe'),
    'Expected imported optset output path to be overridden by the project file. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildUsesDependencyOutputExtensionForLibraries;
var
  lCapturedOutput: string;
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lEscapedOutputPath: string;
  lExitCode: Integer;
  lExpectedOutputPath: string;
  lExtension: string;
  lExtensions: TArray<string>;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  lExtensions := ['.dll', '.ocx'];
  for lExtension in lExtensions do
  begin
    EnsureTempClean;
    lProjectRoot := TPath.Combine(TempRoot,
      'mes-library-output-' + Copy(lExtension, 2, MaxInt));
    PrepareMadExceptBuildFixtureWithOptset(lProjectRoot,
      '[GeneralSettings]' + sLineBreak +
      'HandleExceptions=1' + sLineBreak +
      'LinkInCode=1' + sLineBreak,
      '',
      '    <DCC_ExeOutput>artifact-bin\$(Config)\$(Platform)</DCC_ExeOutput>' + sLineBreak +
      '    <AppType>Library</AppType>' + sLineBreak +
      '    <GenDll>true</GenDll>' + sLineBreak,
      lDprojPath, lRsVarsPath, lPatchExePath);
    // Old test: DCC_DependencyCheckOutputName ..\bin\MesGateCheck.ocx. The compiler writes .ocx only for {$E ocx}
    // (real dcc32: the property alone gave .dll, {$E ocx} gave .ocx).
    if SameText(lExtension, '.ocx') then
      WriteNamingSource(lProjectRoot, 'library', '{$E ocx}')
    else
      WriteNamingSource(lProjectRoot, 'library', '');
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win64';
    lOptions.fDelphiVersion := '23.0';
    lOptions.fRsVarsPath := lRsVarsPath;
    lOptions.fBuildJson := True;
    if SameText(lExtension, '.ocx') then
    begin
      lOptions.fHasBuildTestOutputDir := True;
      lOptions.fBuildTestOutputDir := TPath.Combine(lProjectRoot, 'isolated-output');
      lExpectedOutputPath := TPath.Combine(lOptions.fBuildTestOutputDir,
        'MesGateCheck' + lExtension);
    end else
      lExpectedOutputPath := TPath.Combine(lProjectRoot,
        'artifact-bin\Debug\Win64\MesGateCheck' + lExtension);

    lCapturingRunner := TCapturingBuildRunner.Create;
    lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
    lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lExpectedOutputPath);
    lRunner := lCapturingRunner;
    lCapturedOutput := CaptureConsoleOutput(
      procedure
      begin
        lError := '';
        Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
          'Expected library build to complete. Error: ' + lError);
      end);

    Assert.AreEqual(0, lExitCode,
      'Expected library artifact to keep its evaluated extension: ' + lExtension);
    Assert.AreEqual(2, lCapturingRunner.fCallCount,
      'Expected MSBuild followed by madExcept patch for ' + lExtension + '. Calls: ' +
      DescribeCapturedProcesses(lCapturingRunner));
    Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], lExpectedOutputPath),
      'Expected madExcept patch to receive ' + lExpectedOutputPath + '. Calls: ' +
      DescribeCapturedProcesses(lCapturingRunner));
    lEscapedOutputPath := StringReplace(lExpectedOutputPath, '\', '\\', [rfReplaceAll]);
    Assert.IsTrue(Pos('"output":"' + lEscapedOutputPath + '"', lCapturedOutput) > 0,
      'Expected JSON output to name ' + lExpectedOutputPath + '. Output: ' +
      lCapturedOutput);
  end;
end;

procedure TBuildTests.BuildReportsProjectPropertyEvaluationFailure;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'invalid-project-properties');
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);
  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup Condition="''Debug'' === ''Debug''">' + sLineBreak +
    '    <MainSource>MesGateCheck.dpr</MainSource>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win64';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsFalse(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected invalid evaluated project properties to fail preflight.');
  Assert.AreEqual(0, lCapturingRunner.fCallCount,
    'MSBuild must not run after project-property evaluation fails.');
  Assert.IsTrue(ContainsText(lError, 'Unsupported or invalid Condition'),
    'Expected the original evaluator diagnostic. Actual: ' + lError);
end;

procedure TBuildTests.BuildNamesTheArtifactByPlatformRules(const aPlatform, aKind, aFileName: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-naming-' + aPlatform + '-' + aKind);
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, aKind, cBplOutputGroup, lDprojPath, lRsVarsPath);
  lOptions.fPlatform := aPlatform;
  // A package goes to DCC_BplOutput; programs and libraries go to DCC_ExeOutput.
  if SameText(aKind, 'package') then
    lEmitted := CombinePath([lProjectRoot, 'bpl', aPlatform, aFileName])
  else
    lEmitted := CombinePath([lProjectRoot, 'out', aPlatform, aFileName]);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name the file the compiler emitted: ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsTrue(Pos('"output_stale":false', lOutput) > 0, 'The emitted file exists. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
  // Without --test-output-dir the project's own unit output stays in charge.
  Assert.IsFalse(ContainsText(lCapture.fArgumentsList[0], 'DcuOutput'),
    'Unit output must not be overridden. Arguments: ' + lCapture.fArgumentsList[0]);
end;

procedure TBuildTests.BuildPrefersEvaluatedCompilerTargetsArtifactNaming;
const
  // Stand-in compiler targets with values no real platform uses, so the result shows where the name came from.
  cTargets =
    '<Project>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Platform)''==''Linux64''">' + sLineBreak +
    '    <ExeExt>elf</ExeExt>' + sLineBreak +
    '    <DllExt>sox</DllExt>' + sLineBreak +
    '    <BplExt>bplx</BplExt>' + sLineBreak +
    '    <DllPlatformPrefix>dl</DllPlatformPrefix>' + sLineBreak +
    '    <BplPlatformPrefix>pk</BplPlatformPrefix>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak;
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-naming-evaluated-targets');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'library',
    '  <Import Project="naming.targets"/>' + sLineBreak, lDprojPath, lRsVarsPath);
  // Old test: the project's DllVersion 4; the compiler takes the version from the source.
  WriteNamingSource(lProjectRoot, 'library', '{$LIBVERSION ''4''}');
  WriteUtf8File(TPath.Combine(lProjectRoot, 'naming.targets'), cTargets);
  lOptions.fPlatform := 'Linux64';
  // Linux64 puts the version after the extension, as dcclinux64 does.
  lEmitted := CombinePath([lProjectRoot, 'out', 'Linux64', 'dlMesGateCheck.sox.4']);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The evaluated compiler targets must decide the name: ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildReportsWhyTheArtifactNameIsUnresolved;
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-naming-unknown-platform');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'program', '', lDprojPath, lRsVarsPath);
  lOptions.fPlatform := 'Mars64';

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, '', lCapture, lRunner);

  Assert.IsTrue(Pos('"output":""', lOutput) > 0, 'No path may be reported for an unresolved name. Output: ' +
    lOutput);
  Assert.IsTrue(Pos('"status":"output_missing"', lOutput) > 0, 'Expected output_missing. Output: ' + lOutput);
  Assert.IsTrue(ContainsText(lOutput, 'could not be resolved') and ContainsText(lOutput, 'Mars64'),
    'The report must say why the name is unknown. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'MesGateCheck.exe'), 'No guessed name may appear. Output: ' + lOutput);
end;

procedure TBuildTests.BuildTestOutputDirRedirectsUnitOutput(const aPlatform, aFileName: string);
var
  lArguments: string;
  lCapture: TCapturingBuildRunner;
  lDcuDir: string;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
  lScratchDir: string;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'test-output-dir-units-' + aPlatform);
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'program', '', lDprojPath, lRsVarsPath);
  lOptions.fPlatform := aPlatform;
  lScratchDir := TPath.Combine(lProjectRoot, 'scratch');
  lOptions.fHasBuildTestOutputDir := True;
  lOptions.fBuildTestOutputDir := lScratchDir;
  lEmitted := TPath.Combine(lScratchDir, aFileName);
  lDcuDir := TPath.Combine(lScratchDir, 'dcu');

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);
  lArguments := lCapture.fArgumentsList[0];

  Assert.IsTrue(Pos(' /p:DCC_DcuOutput=' + lDcuDir + ' ', lArguments + ' ') > 0,
    'DCU output must move to ' + lDcuDir + '. Arguments: ' + lArguments);
  Assert.IsTrue(Pos(' /p:DCC_ObjOutput=' + lDcuDir + ' ', lArguments + ' ') > 0,
    'Object output must move to ' + lDcuDir + '. Arguments: ' + lArguments);
  Assert.IsTrue(Pos(' /p:DCC_ExeOutput=' + lScratchDir + ' ', lArguments + ' ') > 0,
    'Executables stay directly in the test output directory. Arguments: ' + lArguments);
  Assert.IsFalse(ContainsText(lArguments, 'DCC_UnitOutputDirectory'),
    'DCC_UnitOutputDirectory is not a compiler property. Arguments: ' + lArguments);
  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name the redirected artifact. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildResolvesPackageOutputDirectory(const aMode: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lProjectXml: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'package-output-dir-' + aMode);
  lProjectXml := '';
  lEmitted := '';
  if SameText(aMode, 'dll-output-path') then
  begin
    // EnvOptions.proj defines DelphiDLLOutputPath; the Delphi targets use it when DCC_BplOutput is empty.
    lProjectXml :=
      '  <PropertyGroup>' + sLineBreak +
      '    <DelphiDLLOutputPath>common-bpl\$(Platform)</DelphiDLLOutputPath>' + sLineBreak +
      '  </PropertyGroup>' + sLineBreak;
    lEmitted := CombinePath([lProjectRoot, 'common-bpl', 'Win32', 'MesGateCheck.bpl']);
  end;
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'package', lProjectXml, lDprojPath, lRsVarsPath);
  lOptions.fPlatform := 'Win32';

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  if lEmitted <> '' then
  begin
    Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
      'The package must be reported in its package directory: ' + lEmitted + '. Output: ' + lOutput);
    Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
  end else begin
    Assert.IsTrue(Pos('"output":""', lOutput) > 0, 'No guessed package path may be reported. Output: ' + lOutput);
    Assert.IsTrue(ContainsText(lOutput, 'could not be resolved') and ContainsText(lOutput, 'DCC_BplOutput'),
      'The report must say why the package directory is unknown. Output: ' + lOutput);
  end;
  // The executable directory is not where a package goes.
  Assert.IsFalse(ContainsText(lOutput, JsonPathValue(TPath.Combine(lProjectRoot, 'out'))),
    'The DCC_ExeOutput directory must not be reported for a package. Output: ' + lOutput);
end;

procedure TBuildTests.BuildAppliesLibrarySuffixAndVersion(const aPlatform, aKind, aSuffix, aVersion,
  aFileName: string);
var
  lCapture: TCapturingBuildRunner;
  lDirectives: string;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lProjectXml: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-suffix-' + aPlatform + '-' + aKind);
  // The compiler reads suffix and version from the source (old test: the project's DllSuffix and DllVersion).
  lProjectXml := cBplOutputGroup;
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, aKind, lProjectXml, lDprojPath, lRsVarsPath);
  lDirectives := '';
  if aSuffix <> '' then
    lDirectives := '{$LIBSUFFIX ''' + aSuffix + '''}' + sLineBreak;
  if aVersion <> '' then
    lDirectives := lDirectives + '{$LIBVERSION ''' + aVersion + '''}' + sLineBreak;
  WriteNamingSource(lProjectRoot, aKind, lDirectives);
  lOptions.fPlatform := aPlatform;
  if SameText(aKind, 'package') then
    lEmitted := CombinePath([lProjectRoot, 'bpl', aPlatform, aFileName])
  else
    lEmitted := CombinePath([lProjectRoot, 'out', aPlatform, aFileName]);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

// DAK-381: a project whose DllSuffix is $(Auto) and whose main source holds aDirective. Writes a stand-in
// rtl<aRtlSuffix>.bpl for each entry of aRtlSuffixes into the fake Delphi bin folder, which is where DAK looks.
function PrepareAutoSuffixFixture(const aRootDir, aKind, aDirective: string; const aRtlSuffixes: TArray<string>;
  out aDprojPath, aRsVarsPath: string): TAppOptions;
var
  lSuffix: string;
begin
  Result := PrepareArtifactNamingFixture(aRootDir, aKind,
    cBplOutputGroup +
    '  <PropertyGroup>' + sLineBreak +
    '    <DllSuffix>$(Auto)</DllSuffix>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak, aDprojPath, aRsVarsPath);
  WriteNamingSource(aRootDir, aKind, aDirective);
  WriteUtf8File(TPath.Combine(aRootDir, 'suffix.inc'), '{$LIBSUFFIX AUTO}' + sLineBreak);
  for lSuffix in aRtlSuffixes do
    WriteUtf8File(TPath.Combine(aRootDir, 'fake-bds-root\bin\rtl' + lSuffix + '.bpl'), 'stub');
end;

procedure TBuildTests.BuildResolvesAutoLibrarySuffixFromTheSourceDirective(const aPlatform, aKind, aDirective,
  aFileName: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-auto-suffix-' + aPlatform + '-' + aKind);
  lOptions := PrepareAutoSuffixFixture(lProjectRoot, aKind, StringReplace(aDirective, '~', '''', [rfReplaceAll]),
    ['777'], lDprojPath, lRsVarsPath);
  lOptions.fPlatform := aPlatform;
  if SameText(aKind, 'package') then
    lEmitted := CombinePath([lProjectRoot, 'bpl', aPlatform, aFileName])
  else
    lEmitted := CombinePath([lProjectRoot, 'out', aPlatform, aFileName]);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name ' + lEmitted + ' for directive [' + aDirective + ']. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildReportsWhyTheAutoLibrarySuffixIsUnresolved(const aMode: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
  lSuffixes: TArray<string>;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-auto-suffix-' + aMode);
  if SameText(aMode, 'two') then
    lSuffixes := ['777', '888']
  else
    lSuffixes := nil;
  lOptions := PrepareAutoSuffixFixture(lProjectRoot, 'package', '{$LIBSUFFIX AUTO}', lSuffixes, lDprojPath,
    lRsVarsPath);
  lOptions.fPlatform := 'Win32';

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, '', lCapture, lRunner);

  Assert.IsTrue(Pos('"output":""', lOutput) > 0, 'No guessed name may be reported. Output: ' + lOutput);
  Assert.IsTrue(ContainsText(lOutput, 'could not be resolved') and ContainsText(lOutput, 'rtl<N>.bpl'),
    'The report must name the RTL package evidence it needs. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, '777.bpl') or ContainsText(lOutput, '888.bpl'),
    'No suffix may be picked among several candidates. Output: ' + lOutput);
end;

procedure TBuildTests.BuildReportsAnInvalidExeOutputAsUnresolved;
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-invalid-exe-output');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'program',
    '  <PropertyGroup>' + sLineBreak +
    '    <DCC_ExeOutput>out|bad</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak, lDprojPath, lRsVarsPath);
  lOptions.fPlatform := 'Win32';

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, '', lCapture, lRunner);

  Assert.IsTrue(Pos('"output":""', lOutput) > 0, 'No path may be reported for an unusable directory. Output: ' +
    lOutput);
  Assert.IsTrue(ContainsText(lOutput, 'could not be resolved') and ContainsText(lOutput, 'DCC_ExeOutput'),
    'The report must name DCC_ExeOutput as the reason. Output: ' + lOutput);
end;

procedure TBuildTests.BuildIgnoresLegacyDependencyOutputName(const aPlatform, aValue,
  aFileName: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-legacy-dependency-name-' + aPlatform);
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'program',
    '  <PropertyGroup>' + sLineBreak +
    '    <DCC_DependencyCheckOutputName>' + aValue + '</DCC_DependencyCheckOutputName>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak, lDprojPath, lRsVarsPath);
  lOptions.fPlatform := aPlatform;
  lEmitted := CombinePath([lProjectRoot, 'out', aPlatform, aFileName]);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildTestOutputDirAlsoRedirectsHppAndBpiOutput;
var
  lArguments: string;
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
  lScratchDir: string;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'test-output-dir-hpp-bpi');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'program',
    '  <PropertyGroup>' + sLineBreak +
    '    <DCC_HppOutput>project-hpp</DCC_HppOutput>' + sLineBreak +
    '    <DCC_BpiOutput>project-bpi</DCC_BpiOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak, lDprojPath, lRsVarsPath);
  lOptions.fPlatform := 'Win32';
  lScratchDir := TPath.Combine(lProjectRoot, 'scratch');
  lOptions.fHasBuildTestOutputDir := True;
  lOptions.fBuildTestOutputDir := lScratchDir;
  lEmitted := TPath.Combine(lScratchDir, 'MesGateCheck.exe');

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);
  lArguments := lCapture.fArgumentsList[0];

  // Headers are unit-derived output and follow the DCUs; the package interface follows the .dcp files.
  Assert.IsTrue(Pos(' /p:DCC_HppOutput=' + TPath.Combine(lScratchDir, 'dcu') + ' ', lArguments + ' ') > 0,
    'C++ header output must move into the test output directory. Arguments: ' + lArguments);
  Assert.IsTrue(Pos(' /p:DCC_BpiOutput=' + lScratchDir + ' ', lArguments + ' ') > 0,
    'The package interface output must move into the test output directory. Arguments: ' + lArguments);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildAndroidProgramIgnoresTheProjectDllPrefix;
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-android-dllprefix');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'program',
    '  <PropertyGroup>' + sLineBreak +
    '    <DllPrefix>px</DllPrefix>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak, lDprojPath, lRsVarsPath);
  lOptions.fPlatform := 'Android64';
  lEmitted := CombinePath([lProjectRoot, 'out', 'Android64', 'libMesGateCheck.so']);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildTakesNamingFromTheSourceDirectives(const aPlatform, aKind, aDirectives,
  aFileName: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-directives-' + aPlatform + '-' + aKind);
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, aKind, cBplOutputGroup, lDprojPath, lRsVarsPath);
  WriteUtf8File(TPath.Combine(lProjectRoot, 'naming.inc'), '{$LIBSUFFIX ''_inc''}' + sLineBreak);
  WriteNamingSource(lProjectRoot, aKind,
    StringReplace(StringReplace(aDirectives, '~', '''', [rfReplaceAll]), '|', sLineBreak, [rfReplaceAll]));
  lOptions.fPlatform := aPlatform;
  if SameText(aKind, 'package') then
    lEmitted := CombinePath([lProjectRoot, 'bpl', aPlatform, aFileName])
  else
    lEmitted := CombinePath([lProjectRoot, 'out', aPlatform, aFileName]);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildIgnoresProjectNamingMirrors(const aPlatform, aKind, aProperty, aFileName: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-mirrors-' + aPlatform + '-' + aKind);
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, aKind,
    cBplOutputGroup +
    '  <PropertyGroup>' + sLineBreak +
    '    ' + aProperty + sLineBreak +
    '  </PropertyGroup>' + sLineBreak, lDprojPath, lRsVarsPath);
  lOptions.fPlatform := aPlatform;
  if SameText(aKind, 'package') then
    lEmitted := CombinePath([lProjectRoot, 'bpl', aPlatform, aFileName])
  else
    lEmitted := CombinePath([lProjectRoot, 'out', aPlatform, aFileName]);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildReportsAnUnsupportedNamingDirective(const aDirective, aReasonPart: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-unsupported-directive');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'library', '', lDprojPath, lRsVarsPath);
  WriteNamingSource(lProjectRoot, 'library', aDirective);
  lOptions.fPlatform := 'Win32';

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, '', lCapture, lRunner);

  Assert.IsTrue(Pos('"output":""', lOutput) > 0, 'No guessed name may be reported. Output: ' + lOutput);
  Assert.IsTrue(ContainsText(lOutput, 'could not be resolved') and ContainsText(lOutput, aReasonPart),
    'The report must name the directive. Output: ' + lOutput);
end;

procedure TBuildTests.BuildReportsAnUnreadableMainSourceAsUnresolved;
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-unreadable-source');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'library', '', lDprojPath, lRsVarsPath);
  TFile.Delete(TPath.Combine(lProjectRoot, 'MesGateCheck.dpr'));
  lOptions.fPlatform := 'Win32';

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, '', lCapture, lRunner);

  Assert.IsTrue(Pos('"output":""', lOutput) > 0, 'No guessed name may be reported. Output: ' + lOutput);
  Assert.IsTrue(ContainsText(lOutput, 'could not be resolved') and ContainsText(lOutput, 'cannot be read'),
    'The report must say the source cannot be read. Output: ' + lOutput);
end;

procedure TBuildTests.BuildReportsAnInvalidMainSourceAsUnresolved;
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-invalid-main-source');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'program',
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>a|b.dpr</MainSource>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak, lDprojPath, lRsVarsPath);
  lOptions.fPlatform := 'Win32';

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, '', lCapture, lRunner);

  Assert.IsTrue(Pos('"output":""', lOutput) > 0, 'No path may be reported for an unusable source. Output: ' +
    lOutput);
  Assert.IsTrue(ContainsText(lOutput, 'could not be resolved') and ContainsText(lOutput, 'MainSource'),
    'The report must name MainSource as the reason. Output: ' + lOutput);
end;

procedure TBuildTests.BuildPlacesAnAndroidPackageInTheDcpOutput;
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-android-package');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'package',
    cBplOutputGroup +
    '  <PropertyGroup>' + sLineBreak +
    '    <DCC_DcpOutput>dcp\$(Platform)</DCC_DcpOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak, lDprojPath, lRsVarsPath);
  WriteNamingSource(lProjectRoot, 'package',
    '{$LIBPREFIX ''zz''}' + sLineBreak + '{$LIBSUFFIX ''_s''}' + sLineBreak + '{$E xpl}');
  lOptions.fPlatform := 'Android64';
  lEmitted := CombinePath([lProjectRoot, 'dcp', 'Android64', 'libMesGateCheck.a']);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildKeepsTheNameWithANoteWhenAnIncludeCannotBeRead(const aKind, aFileName: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-unread-include-' + aKind);
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, aKind, '', lDprojPath, lRsVarsPath);
  WriteNamingSource(lProjectRoot, aKind, '{$I Jedi.inc}');
  lOptions.fPlatform := 'Win32';
  lEmitted := CombinePath([lProjectRoot, 'out', 'Win32', aFileName]);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsTrue(Pos('"status":"ok"', lOutput) > 0, 'The existing fresh file means ok. Output: ' + lOutput);
  Assert.IsTrue(ContainsText(lOutput, 'naming include Jedi.inc not read; name assumes no directives in it'),
    'The note must name the include. Output: ' + lOutput);
end;

procedure TBuildTests.BuildReportsOutputMissingNamingTheUnreadIncludeWhenTheAssumedFileIsAbsent;
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-unread-include-absent');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'library', '', lDprojPath, lRsVarsPath);
  WriteNamingSource(lProjectRoot, 'library', '{$I Jedi.inc}');
  lOptions.fPlatform := 'Win32';

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  // The runner writes nothing: the compiler "used a suffix from the include", so the assumed name is absent.
  lOutput := RunArtifactNamingBuild(lOptions, '', lCapture, lRunner);

  Assert.IsTrue(Pos('"status":"output_missing"', lOutput) > 0, 'Expected output_missing. Output: ' + lOutput);
  Assert.IsTrue(ContainsText(lOutput, JsonPathValue(CombinePath([lProjectRoot, 'out', 'Win32', 'MesGateCheck.dll']))),
    'The assumed name must be shown. Output: ' + lOutput);
  Assert.IsTrue(ContainsText(lOutput, 'naming include Jedi.inc not read'),
    'The reason must name the unread include. Output: ' + lOutput);
end;

procedure TBuildTests.BuildHonoursTheProjectOutputExt(const aPlatform, aKind, aOutputExt, aDirectives,
  aFileName: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-outputext-' + aPlatform + '-' + aKind + '-' +
    IntToStr(Length(aOutputExt)) + IntToStr(Length(aDirectives)));
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, aKind,
    cBplOutputGroup +
    '  <PropertyGroup>' + sLineBreak +
    '    <OutputExt>' + aOutputExt + '</OutputExt>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak, lDprojPath, lRsVarsPath);
  WriteNamingSource(lProjectRoot, aKind, aDirectives);
  lOptions.fPlatform := aPlatform;
  if SameText(aKind, 'package') then
    lEmitted := CombinePath([lProjectRoot, 'bpl', aPlatform, aFileName])
  else
    lEmitted := CombinePath([lProjectRoot, 'out', aPlatform, aFileName]);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildDoesNotPatchNonWindowsOutputWithMadExcept(const aPlatform, aFileName: string);
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
  lTracePath: string;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-non-windows-' + aPlatform);
  PrepareMadExceptBuildFixtureWithOptset(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    '',
    '    <DCC_ExeOutput>artifact-bin\$(Config)\$(Platform)</DCC_ExeOutput>' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);
  lEmitted := TPath.Combine(lProjectRoot, 'artifact-bin\Debug\' + aPlatform + '\' + aFileName);
  lTracePath := TPath.Combine(lProjectRoot, 'build-trace.log');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := aPlatform;
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fVerbose := True;

  lEnvGuard := SetScopedEnvironmentVariables(['DAK_TRACE_BUILD', lTracePath]);
  lCapturingRunner := TCapturingBuildRunner.Create;
  lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lEmitted);
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError), 'Expected the build to run. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'The build must stay green.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'Only MSBuild may run; madExceptPatch must not touch a non-Windows output. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(TFile.ReadAllText(lTracePath, TEncoding.UTF8), 'madexcept-patch: skipped'),
    'The skip must be named in the verbose trace.');
end;

procedure TBuildTests.BuildReadsOutputExtThatTheTargetsAlreadyDotted(const aOutputExt, aFileName: string);
const
  // Stand-in compiler targets: the Linux64 names of the earlier stand-in plus the OutputExt rules of l.91-94.
  cTargets =
    '<Project>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Platform)''==''Linux64''">' + sLineBreak +
    '    <ExeExt>elf</ExeExt>' + sLineBreak +
    '    <DllExt>sox</DllExt>' + sLineBreak +
    '    <BplExt>bplx</BplExt>' + sLineBreak +
    '    <DllPlatformPrefix>dl</DllPlatformPrefix>' + sLineBreak +
    '    <BplPlatformPrefix>pk</BplPlatformPrefix>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(GenDll)''==''true''">' + sLineBreak +
    '    <OutputExt Condition="''$(OutputExt)''==''''">$(DllExt)</OutputExt>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <OutputExt Condition="''$(OutputExt)''==''''">$(ExeExt)</OutputExt>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <OutputExt Condition="''$(OutputExt)''!=''''">.$(OutputExt)</OutputExt>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak;
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lEmitted: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-outputext-targets-' + IntToStr(Length(aOutputExt)));
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'library',
    '  <PropertyGroup>' + sLineBreak +
    '    <OutputExt>' + aOutputExt + '</OutputExt>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <Import Project="naming.targets"/>' + sLineBreak, lDprojPath, lRsVarsPath);
  WriteUtf8File(TPath.Combine(lProjectRoot, 'naming.targets'), cTargets);
  WriteNamingSource(lProjectRoot, 'library', '{$LIBVERSION ''4''}');
  lOptions.fPlatform := 'Linux64';
  lEmitted := CombinePath([lProjectRoot, 'out', 'Linux64', aFileName]);

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, lEmitted, lCapture, lRunner);

  Assert.IsTrue(Pos('"output":"' + JsonPathValue(lEmitted) + '"', lOutput) > 0,
    'The report must name ' + lEmitted + '. Output: ' + lOutput);
  Assert.IsFalse(ContainsText(lOutput, 'output_missing'), 'The emitted file exists. Output: ' + lOutput);
end;

procedure TBuildTests.BuildTestOutputDirThatCannotBeUsedIsANamedFailure(const aOutputDir: string);
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'test-output-dir-unusable');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'program', '', lDprojPath, lRsVarsPath);
  lOptions.fPlatform := 'Win32';
  lOptions.fHasBuildTestOutputDir := True;
  lOptions.fBuildTestOutputDir := aOutputDir;
  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lError := '';
  lExitCode := 0;

  // Invalid characters and a root that depends on the working directory's drive are reported, not raised.
  Assert.IsFalse(TryRunBuild(lOptions, lRunner, lExitCode, lError), aOutputDir);
  Assert.IsTrue(ContainsText(lError, 'Test output directory is not usable') and ContainsText(lError, aOutputDir),
    lError);
  Assert.AreEqual(0, lCapture.fCallCount, 'The build must not start with an unusable test output directory.');
end;

procedure TBuildTests.BuildTestOutputDirFailureExitsNonzeroFromCli;
var
  lDprojPath: string;
  lExit: Cardinal;
  lLog: string;
  lRsVarsPath: string;
  lText: string;
begin
  EnsureTempClean;
  PrepareArtifactNamingFixture(TPath.Combine(TempRoot, 'test-output-dir-cli'), 'program', '', lDprojPath,
    lRsVarsPath);
  lLog := TPath.Combine(TempRoot, 'test-output-dir-cli.log');
  Assert.IsTrue(RunResolverProcess('build --project ' + QuoteArg(lDprojPath) + ' --rsvars ' + QuoteArg(lRsVarsPath) +
    ' --delphi 23.0 --platform Win32 --config Debug --test-output-dir ' + QuoteArg('a|b'), RepoRoot, lLog, lExit));
  lText := TFile.ReadAllText(lLog);
  Assert.AreNotEqual(Cardinal(0), lExit, lText);
  Assert.IsTrue(ContainsText(lText, 'Test output directory is not usable'), lText);
end;

procedure TBuildTests.BuildTestOutputDirAcceptsUncPath;
const
  cUncDir = '\\dak-test-server\share\out';
var
  lArguments: string;
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'test-output-dir-unc');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'program', '', lDprojPath, lRsVarsPath);
  lOptions.fPlatform := 'Win32';
  lOptions.fHasBuildTestOutputDir := True;
  lOptions.fBuildTestOutputDir := cUncDir;

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  // Nothing is written to the share: the capturing runner only records the MSBuild arguments.
  lOutput := RunArtifactNamingBuild(lOptions, '', lCapture, lRunner);
  lArguments := lCapture.fArgumentsList[0];

  Assert.IsTrue(Pos(' /p:DCC_ExeOutput=' + cUncDir + ' ', lArguments + ' ') > 0,
    'The UNC directory must reach MSBuild unchanged. Arguments: ' + lArguments);
  Assert.IsTrue(Pos('"output":"' + JsonPathValue(cUncDir + '\MesGateCheck.exe') + '"', lOutput) > 0,
    'The artifact is reported under the UNC directory. Output: ' + lOutput);
end;

procedure TBuildTests.BuildTextReportsUnresolvedNameWithoutBlankPath;
var
  lCapture: TCapturingBuildRunner;
  lDprojPath: string;
  lLine: string;
  lOptions: TAppOptions;
  lOutput: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
  lSawSuccess: Boolean;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'artifact-naming-unresolved-text');
  lOptions := PrepareArtifactNamingFixture(lProjectRoot, 'program', '', lDprojPath, lRsVarsPath);
  lOptions.fPlatform := 'Mars64';
  lOptions.fBuildJson := False;

  lCapture := TCapturingBuildRunner.Create;
  lRunner := lCapture;
  lOutput := RunArtifactNamingBuild(lOptions, '', lCapture, lRunner);

  lSawSuccess := False;
  for lLine in lOutput.Split([#13#10, #10]) do
    if StartsText('Build succeeded', Trim(lLine)) then
    begin
      lSawSuccess := True;
      Assert.AreNotEqual('Build succeeded:', Trim(lLine), 'No empty output path may be printed. Output: ' + lOutput);
    end;
  Assert.IsTrue(lSawSuccess, 'The compiler succeeded, so the success line stays. Output: ' + lOutput);
  Assert.IsTrue(ContainsText(lOutput, 'could not be resolved') and ContainsText(lOutput, 'Mars64'),
    'The reason must still be printed. Output: ' + lOutput);
end;

procedure TBuildTests.BuildReportsSpecificErrorWhenResolvedMadExceptOutputIsMissing;
var
  lCapturedOutput: string;
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExpectedMessage: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-optset-output-missing');
  PrepareMadExceptBuildFixtureWithOptset(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    '    <DCC_ExeOutput>bin\$(Config)\$(Platform)</DCC_ExeOutput>' + sLineBreak,
    '', lDprojPath, lRsVarsPath, lPatchExePath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fBuildJson := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      lError := '';
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected build command to complete and emit JSON output. Error: ' + lError);
    end);

  Assert.AreEqual(1, lExitCode, 'Expected missing resolved output path to fail the build.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'Expected madExcept patching to stop before invoking madExceptPatch.exe. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(Pos('"status":"internal_error"', lCapturedOutput) > 0,
    'Expected JSON summary to report internal_error. Output: ' + lCapturedOutput);
  lExpectedMessage := 'Resolved build output path does not exist: ' +
    StringReplace(TPath.Combine(lProjectRoot, 'bin\Debug\Win32\MesGateCheck.exe'), '\', '\\', [rfReplaceAll]);
  Assert.IsTrue(Pos(lExpectedMessage, lCapturedOutput) > 0,
    'Expected JSON summary to include the missing resolved output path. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.BuildDfmCheckFailureReportsSkippedValidationAndMadExceptGuidance;
var
  lCapturedOutput: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lFailingRunner: TFailingBuildRunner;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  lProjectRoot := TPath.Combine(TempRoot, 'build-dfmcheck-madexcept-missing-dcu');
  if TDirectory.Exists(lProjectRoot) then
    TDirectory.Delete(lProjectRoot, True);
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fHasRsVarsPath := True;
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fBuildRunDfmCheck := True;

  lFailingRunner := TFailingBuildRunner.Create;
  lFailingRunner.fStdOutText :=
    lDprojPath + '(1): message: fake build started' + sLineBreak +
    'MesGateCheck.dpr(6): error F1026: File not found: ' +
    '''C:\Program Files (x86)\madCollection\madExcept\BDS23\win32\madExcept.dcu''' + sLineBreak;
  lRunner := lFailingRunner;

  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected failing build process to be summarized. Error: ' + lError);
    end);

  Assert.AreEqual(1, lExitCode, 'Expected build exit code to remain the source build failure.');
  Assert.IsTrue(Pos('dfm-check was not run because the source build failed', lCapturedOutput) > 0,
    'Expected build output to explain that post-build DFM validation was skipped. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('madExcept.dcu', lCapturedOutput) > 0,
    'Expected original missing madExcept.dcu compiler error to remain visible. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('madExcept is enabled by DCC_Define', lCapturedOutput) > 0,
    'Expected targeted madExcept guidance for missing madExcept.dcu. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.BuildDfmCheckRunsAfterSuccessfulSourceBuildWhenPostBuildPatchFails;
var
  lCapturedOutput: string;
  lCapturingRunner: TCapturingBuildRunner;
  lDfmCheckRan: Boolean;
  lDfmCheckRunner: TBuildDfmCheckRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lExpectedOutputPath: string;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'build-dfmcheck-after-postbuild-failure');
  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);
  lExpectedOutputPath := TPath.Combine(lProjectRoot, 'MesGateCheck.exe');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fHasRsVarsPath := True;
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fBuildRunDfmCheck := True;
  lOptions.fBuildAi := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lExpectedOutputPath);
  lCapturingRunner.fExitCodesByCall := TDictionary<Integer, Integer>.Create;
  lCapturingRunner.fExitCodesByCall.AddOrSetValue(1, 2);
  lRunner := lCapturingRunner;
  lDfmCheckRan := False;
  lDfmCheckRunner :=
    function(const aDfmOptions: TAppOptions): Integer
    begin
      Assert.AreEqual(lDprojPath, aDfmOptions.fDprojPath, 'Expected DFM validation to use the source project.');
      lDfmCheckRan := True;
      Result := 0;
    end;

  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lDfmCheckRunner, lExitCode, lError),
        'Expected build command to complete through post-build failure. Error: ' + lError);
    end);

  Assert.AreEqual(1, lExitCode, 'Expected failing madExcept post-build patch to keep the aggregate build red.');
  Assert.IsTrue(lDfmCheckRan, 'Expected DFM validation to run because the source build succeeded.');
  Assert.IsTrue(Pos('[build] Running dfm-check validation...', lCapturedOutput) > 0,
    'Expected build output to announce DFM validation. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('madExcept patch step failed.', lCapturedOutput) > 0,
    'Expected post-build failure output to name the failed phase. Output: ' + lCapturedOutput);
  Assert.IsFalse(Pos('dfm-check was not run because the source build failed', lCapturedOutput) > 0,
    'Post-build failures must not be reported as source-build failures. Output: ' + lCapturedOutput);
  lDfmCheckRunner := nil;
  lRunner := nil;
end;

procedure TBuildTests.BuildIgnoresMissingCfgDependentOnOptsetWhenProjectOutputExists;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lExpectedOutputPath: string;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'mes-missing-optset-output-build');
  PrepareMadExceptBuildFixtureWithMissingOptset(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=1' + sLineBreak +
    'LinkInCode=1' + sLineBreak,
    '    <DCC_ExeOutput>project-bin\$(Config)\$(Platform)</DCC_ExeOutput>' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);

  lExpectedOutputPath := TPath.Combine(lProjectRoot, 'project-bin\Debug\Win32\MesGateCheck.exe');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lCapturingRunner.fFilesToCreateOnCall := TDictionary<Integer, string>.Create;
  lCapturingRunner.fFilesToCreateOnCall.AddOrSetValue(0, lExpectedOutputPath);
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected build to stay non-fatal when CfgDependentOn points to a missing optset. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected missing CfgDependentOn optset to keep the build green.');
  Assert.AreEqual(2, lCapturingRunner.fCallCount,
    'Expected MSBuild followed by madExcept patch even when the optset file is missing. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], 'project-bin\Debug\Win32\MesGateCheck.exe'),
    'Expected the fallback project output path to reach madExcept patching when the optset file is missing. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildWarnsOnInvalidDiagnosticsIniValues;
var
  lCapturedOutput: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPatchExePath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunnerImpl: TCapturingBuildRunner;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'build-invalid-diagnostics');
  if TDirectory.Exists(lProjectRoot) then
    TDirectory.Delete(lProjectRoot, True);
  TDirectory.CreateDirectory(lProjectRoot);

  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=0' + sLineBreak +
    'LinkInCode=0' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[MadExcept]' + sLineBreak +
    'Path=' + lPatchExePath + sLineBreak +
    '[Diagnostics]' + sLineBreak +
    'SourceContext=autoo' + sLineBreak +
    'SourceContextLines=abc' + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;

  lRunnerImpl := TCapturingBuildRunner.Create;
  lRunner := lRunnerImpl;
  lError := '';
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected build run to complete. Error: ' + lError);
    end);

  Assert.AreEqual(0, lExitCode, 'Expected scripted build success for warning-only configuration issue.');
  Assert.IsTrue(Pos('Invalid dak.ini SourceContext value: autoo', lCapturedOutput) > 0,
    'Expected invalid SourceContext warning in build output. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('Invalid dak.ini SourceContextLines value: abc', lCapturedOutput) > 0,
    'Expected invalid SourceContextLines warning in build output. Output: ' + lCapturedOutput);
end;

procedure PrepareWebCoreBuildFixture(const aRootDir: string; out aDprojPath: string);
var
  lDprPath: string;
begin
  ForceDirectories(aRootDir);
  aDprojPath := TPath.Combine(aRootDir, 'WebCoreCheck.dproj');
  lDprPath := TPath.ChangeExtension(aDprojPath, '.dpr');
  WriteUtf8File(aDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>WebCoreCheck.dpr</MainSource>' + sLineBreak +
    '    <Config Condition="' + '''$(Config)''==''''">Debug</Config>' + sLineBreak +
    '    <Platform Condition="' + '''$(Platform)''==''''">Win32</Platform>' + sLineBreak +
    '    <TMSWebProject>2</TMSWebProject>' + sLineBreak +
    '    <TMSWebHTMLFile>index.html</TMSWebHTMLFile>' + sLineBreak +
    '    <TMSWebPWA>2</TMSWebPWA>' + sLineBreak +
    '    <DCC_UsePackage>TMSWEBCorePkgDXE15;$(DCC_UsePackage)</DCC_UsePackage>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program WebCoreCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);
end;

procedure PrepareWebCoreDebugHookFixture(const aRootDir: string; out aDprojPath: string);
var
  lIndexPath: string;
  lJsPath: string;
begin
  PrepareWebCoreBuildFixture(aRootDir, aDprojPath);
  WriteUtf8File(TPath.Combine(aRootDir, 'tools\patch-index-debug.ps1'),
    'param([string]$ProjectDir,[string]$Config,[string]$ProjectName)' + sLineBreak);

  lIndexPath := TPath.Combine(aRootDir, 'TMSWeb\Debug\index.html');
  lJsPath := TPath.Combine(aRootDir, 'TMSWeb\Debug\WebCoreCheck.js');
  WriteUtf8File(lIndexPath,
    '<html><body><script src="WebCoreCheck.js"></script></body></html>' + sLineBreak);
  WriteUtf8File(lJsPath, 'console.log("ok");' + sLineBreak);
end;

procedure TBuildTests.BuildWarnsWhenWin64NamespacesOmitWinapi;
var
  lAppData: string;
  lCapturedOutput: string;
  lCapturingRunner: TCapturingBuildRunner;
  lDprPath: string;
  lDprojPath: string;
  lEnvGuard: IInterface;
  lEnvOptionsPath: string;
  lError: string;
  lExitCode: Integer;
  lFakeBdsRoot: string;
  lFakeLibPath: string;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'build-preflight-win64-no-winapi');
  if TDirectory.Exists(lProjectRoot) then
    TDirectory.Delete(lProjectRoot, True);
  TDirectory.CreateDirectory(lProjectRoot);

  lDprojPath := TPath.Combine(lProjectRoot, 'Win64NamespaceCheck.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>Win64NamespaceCheck.dpr</MainSource>' + sLineBreak +
    '    <DCC_ExeOutput>bin</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Base_Win64)''!=''''">' + sLineBreak +
    '    <DCC_ConsoleTarget>true</DCC_ConsoleTarget>' + sLineBreak +
    '    <DCC_Namespace>System.Win;Data.Win;$(DCC_Namespace)</DCC_Namespace>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program Win64NamespaceCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(TempRoot, 'fake-bds-root-win64-warning');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  lRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(lRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');

  lFakeLibPath := TPath.Combine(lProjectRoot, 'fake-lib\win64');
  ForceDirectories(lFakeLibPath);
  lAppData := TPath.Combine(TempRoot, 'fake-appdata-win64-warning');
  lEnvOptionsPath := TPath.Combine(lAppData, 'Embarcadero\BDS\99.9\EnvOptions.proj');
  WriteUtf8File(lEnvOptionsPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Platform)''==''Win64x''">' + sLineBreak +
    '    <DelphiLibraryPath>' + lFakeLibPath + '</DelphiLibraryPath>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);

  lEnvGuard := SetScopedEnvironmentVariable('APPDATA', lAppData);
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Release';
    lOptions.fPlatform := 'Win64';
    lOptions.fDelphiVersion := '99.9';
    lOptions.fRsVarsPath := lRsVarsPath;
    lOptions.fHasRsVarsPath := True;
    lOptions.fEnvOptionsPath := lEnvOptionsPath;
    lOptions.fHasEnvOptionsPath := True;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lCapturedOutput := CaptureConsoleOutput(
      procedure
      begin
        lError := '';
        Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
          'Expected build to succeed with fake toolchain. Error: ' + lError);
      end);

    Assert.AreEqual(0, lExitCode, 'Expected successful fake build.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one MSBuild launch.');
    Assert.IsTrue(Pos('does not include Winapi in the effective DCC_Namespace', lCapturedOutput) > 0,
      'Expected missing Winapi preflight warning. Output: ' + lCapturedOutput);
  finally
    lRunner := nil;
    lCapturingRunner := nil;
    lEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildSummaryIncludesResolvedSourceContextForErrors;
var
  lCapturedOutput: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lFailingRunner: TFailingBuildRunner;
  lOptions: TAppOptions;
  lPreviousDirectory: string;
  lWorkingDirectory: string;
  lPatchExePath: string;
  lDprPath: string;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'build-source-context');
  if TDirectory.Exists(lProjectRoot) then
    TDirectory.Delete(lProjectRoot, True);
  TDirectory.CreateDirectory(lProjectRoot);

  PrepareMadExceptBuildFixture(lProjectRoot,
    '[GeneralSettings]' + sLineBreak +
    'HandleExceptions=0' + sLineBreak +
    'LinkInCode=0' + sLineBreak,
    lDprojPath, lRsVarsPath, lPatchExePath);
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  WriteUtf8File(lDprojPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>' + TPath.GetFileName(lDprPath) + '</MainSource>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[MadExcept]' + sLineBreak +
    'Path=' + lPatchExePath + sLineBreak +
    '[Diagnostics]' + sLineBreak +
    'SourceContext=on' + sLineBreak +
    'SourceContextLines=1' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program MesGateCheck;' + sLineBreak +
    sLineBreak +
    'uses' + sLineBreak +
    '  BrokenUnit;' + sLineBreak +
    sLineBreak +
    'begin' + sLineBreak +
    '  Trigger;' + sLineBreak +
    'end.' + sLineBreak);
  WriteUtf8File(TPath.Combine(lProjectRoot, 'BrokenUnit.pas'),
    'unit BrokenUnit;' + sLineBreak +
    sLineBreak +
    'interface' + sLineBreak +
    sLineBreak +
    'procedure Trigger;' + sLineBreak +
    sLineBreak +
    'implementation' + sLineBreak +
    sLineBreak +
    'procedure Trigger;' + sLineBreak +
    'begin' + sLineBreak +
    '  MissingIdentifier := 1;' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'end.' + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fDelphiVersion := '23.0';
  lOptions.fRsVarsPath := lRsVarsPath;
  lOptions.fHasRsVarsPath := True;
  lOptions.fBuildAi := True;

  lFailingRunner := TFailingBuildRunner.Create;
  lFailingRunner.fStdErrText :=
    TPath.Combine(lProjectRoot, 'BrokenUnit.pas') + '(11): error E2003: Undeclared identifier: ''MissingIdentifier''' +
    sLineBreak;
  lRunner := lFailingRunner;
  lError := '';
  lWorkingDirectory := TPath.Combine(lProjectRoot, 'unrelated-working-directory');
  TDirectory.CreateDirectory(lWorkingDirectory);
  lPreviousDirectory := GetCurrentDir;
  try
    Assert.IsTrue(SetCurrentDir(lWorkingDirectory));
    lCapturedOutput := CaptureConsoleOutput(
      procedure
      begin
        Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
          'Expected scripted build run to complete. Error: ' + lError);
      end);
  finally
    Assert.IsTrue(SetCurrentDir(lPreviousDirectory));
  end;

  Assert.AreEqual(1, lExitCode, 'Expected scripted build failure exit code.');
  Assert.IsTrue(Pos('BrokenUnit.pas(11): error E2003', lCapturedOutput) > 0,
    'Expected compiler error to be reported in summary output. Output: ' + lCapturedOutput);
  Assert.IsTrue(lCapturedOutput.Contains(ExtractRelativePath(IncludeTrailingPathDelimiter(RepoRoot),
    TPath.Combine(lProjectRoot, 'BrokenUnit.pas')) + '(11): error E2003'),
    'The displayed diagnostic must remain repository-relative.');
  Assert.IsTrue(Pos('source context:', LowerCase(lCapturedOutput)) > 0,
    'Expected build output to include resolved source context. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('MissingIdentifier := 1;', lCapturedOutput) > 0,
    'Expected build output to include the failing source line. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.ParseBuildLogsExposesStructuredDiagnostics;
var
  lErrLog: string;
  lOptions: TBuildSummaryOptions;
  lOutLog: string;
  lSummary: TBuildSummary;
begin
  EnsureTempClean;
  lOutLog := TPath.Combine(TempRoot, 'build-parse-structured.out.log');
  lErrLog := TPath.Combine(TempRoot, 'build-parse-structured.err.log');

  WriteUtf8File(lOutLog, '');

  lOptions := Default(TBuildSummaryOptions);
  lOptions.fProjectRoot := 'F:\repo';
  lOptions.fIncludeWarnings := True;
  lOptions.fIncludeHints := True;

  WriteUtf8File(lErrLog,
    'F:\repo\src\BrokenUnit.pas(11,3): error E2003: Undeclared identifier: ''MissingIdentifier''' + sLineBreak +
    'F:\repo\src\BrokenUnit.pas(44,2): Fatal error F2063: Could not compile used unit ''MissingUnit''' + sLineBreak +
    'F:\repo\src\BrokenUnit.pas(45): fatal F1026: File not found: ''MissingInclude.inc''' + sLineBreak +
    'F:\repo\src\BrokenUnit.pas(46): Fatal: F1027 Unit not found: ''MissingUnit''' + sLineBreak +
    'F:\repo\src\BrokenUnit.pas(55,7): Hint warning H2077: Value assigned to ''UnusedValue'' never used' + sLineBreak +
    '[Error] Link step failed' + sLineBreak);
  lSummary := ParseBuildLogs(lOutLog, lErrLog, lOptions);

  Assert.AreEqual(5, Integer(Length(lSummary.fErrorDiagnostics)), 'Expected five structured error diagnostics.');
  Assert.AreEqual(1, Integer(Length(lSummary.fHintDiagnostics)), 'Expected one structured hint diagnostic.');
  Assert.AreEqual('error', lSummary.fErrorDiagnostics[0].fSeverity, 'Expected error severity.');
  Assert.AreEqual('F:\repo\src\BrokenUnit.pas(11,3): error E2003: Undeclared identifier: ''MissingIdentifier''',
    lSummary.fErrorDiagnostics[0].fRawLine, 'Expected raw line to be preserved.');
  Assert.AreEqual('src\BrokenUnit.pas(11,3): error E2003: Undeclared identifier: ''MissingIdentifier''',
    lSummary.fErrorDiagnostics[0].fNormalizedLine, 'Expected normalized line to use the project-relative path.');
  Assert.AreEqual('src\BrokenUnit.pas', lSummary.fErrorDiagnostics[0].fFileToken, 'Expected file token.');
  Assert.AreEqual(11, lSummary.fErrorDiagnostics[0].fLine, 'Expected line number.');
  Assert.AreEqual(3, lSummary.fErrorDiagnostics[0].fColumn, 'Expected column number.');
  Assert.AreEqual('E2003', lSummary.fErrorDiagnostics[0].fCode, 'Expected diagnostic code.');
  Assert.AreEqual('Undeclared identifier: ''MissingIdentifier''', lSummary.fErrorDiagnostics[0].fMessage,
    'Expected diagnostic message.');
  Assert.AreEqual('error', lSummary.fErrorDiagnostics[1].fSeverity, 'Expected fallback error severity.');
  Assert.AreEqual('F:\repo\src\BrokenUnit.pas(44,2): Fatal error F2063: Could not compile used unit ''MissingUnit''',
    lSummary.fErrorDiagnostics[1].fRawLine, 'Expected fatal raw line to be preserved.');
  Assert.AreEqual('src\BrokenUnit.pas(44,2): Fatal error F2063: Could not compile used unit ''MissingUnit''',
    lSummary.fErrorDiagnostics[1].fNormalizedLine, 'Expected fatal normalized line to be preserved.');
  Assert.AreEqual('src\BrokenUnit.pas', lSummary.fErrorDiagnostics[1].fFileToken, 'Expected fatal file token.');
  Assert.AreEqual(44, lSummary.fErrorDiagnostics[1].fLine, 'Expected fatal line number.');
  Assert.AreEqual(2, lSummary.fErrorDiagnostics[1].fColumn, 'Expected fatal column number.');
  Assert.AreEqual('F2063', lSummary.fErrorDiagnostics[1].fCode, 'Expected fatal diagnostic code.');
  Assert.AreEqual('Could not compile used unit ''MissingUnit''', lSummary.fErrorDiagnostics[1].fMessage,
    'Expected fatal diagnostic message.');
  Assert.AreEqual('F1026', lSummary.fErrorDiagnostics[2].fCode, 'Expected short fatal diagnostic code.');
  Assert.AreEqual('File not found: ''MissingInclude.inc''', lSummary.fErrorDiagnostics[2].fMessage,
    'Expected short fatal diagnostic message.');
  Assert.AreEqual('F1027', lSummary.fErrorDiagnostics[3].fCode, 'Expected colon fatal diagnostic code.');
  Assert.AreEqual('Unit not found: ''MissingUnit''', lSummary.fErrorDiagnostics[3].fMessage,
    'Expected colon fatal diagnostic message.');
  Assert.AreEqual('hint', lSummary.fHintDiagnostics[0].fSeverity, 'Expected hint severity.');
  Assert.AreEqual('F:\repo\src\BrokenUnit.pas(55,7): Hint warning H2077: Value assigned to ''UnusedValue'' never used',
    lSummary.fHintDiagnostics[0].fRawLine, 'Expected hint raw line to be preserved.');
  Assert.AreEqual('src\BrokenUnit.pas(55,7): Hint warning H2077: Value assigned to ''UnusedValue'' never used',
    lSummary.fHintDiagnostics[0].fNormalizedLine, 'Expected hint normalized line to be preserved.');
  Assert.AreEqual('src\BrokenUnit.pas', lSummary.fHintDiagnostics[0].fFileToken, 'Expected hint file token.');
  Assert.AreEqual(55, lSummary.fHintDiagnostics[0].fLine, 'Expected hint line number.');
  Assert.AreEqual(7, lSummary.fHintDiagnostics[0].fColumn, 'Expected hint column number.');
  Assert.AreEqual('H2077', lSummary.fHintDiagnostics[0].fCode, 'Expected hint diagnostic code.');
  Assert.AreEqual('Value assigned to ''UnusedValue'' never used', lSummary.fHintDiagnostics[0].fMessage,
    'Expected hint diagnostic message.');
  Assert.AreEqual('error', lSummary.fErrorDiagnostics[4].fSeverity, 'Expected fallback error severity.');
  Assert.AreEqual('[Error] Link step failed', lSummary.fErrorDiagnostics[4].fNormalizedLine,
    'Expected fallback normalized line to be preserved.');
  Assert.AreEqual('Link step failed', lSummary.fErrorDiagnostics[4].fMessage,
    'Expected fallback error message to be preserved.');

  lOptions.fIgnoreHints := 'H2077';
  lSummary := ParseBuildLogs(lOutLog, lErrLog, lOptions);
  Assert.AreEqual(0, Integer(Length(lSummary.fHintDiagnostics)),
    'Expected ignored hint-warning diagnostics to stay filtered.');
end;

procedure TBuildTests.BuildEnrichmentPolicyPrefersHoverForTypeErrors;
var
  lOperation: TLspOperation;
  lHint: string;
begin
  Assert.IsTrue(SelectEnrichmentOperation('Type mismatch: Integer and string', 'Value', '', lOperation));
  Assert.AreEqual(TLspOperation.loHover, lOperation);
  Assert.IsTrue(BuildSemanticHintText(lOperation, '{"result":{"contentsText":"Integer"}}', lHint));
  Assert.AreEqual('semantic hint: hover -> Integer', lHint);
end;
procedure TBuildTests.BuildEnrichmentPolicyPrefersDefinitionForSymbolMismatch;
var
  lOperation: TLspOperation;
  lHint: string;
begin
  Assert.IsTrue(SelectEnrichmentOperation('Undeclared identifier', 'MissingIdentifier', '', lOperation));
  Assert.AreEqual(TLspOperation.loDefinition, lOperation);
  Assert.IsTrue(BuildSemanticHintText(lOperation,
    '{"result":{"locations":[{"file":"C:\\repo\\BrokenUnit.pas","line":13,"col":1}]}}', lHint));
  Assert.AreEqual('semantic hint: definition -> C:\repo\BrokenUnit.pas(13,1)', lHint);
end;
procedure TBuildTests.BuildEnrichmentHelperFallsBackSilently;
var
  lHint: string;
begin
  Assert.IsFalse(BuildSemanticHintText(TLspOperation.loDefinition, '{"result":{"locations":[]}}', lHint));
  Assert.AreEqual('', lHint);
end;
procedure TBuildTests.BuildWebCoreCompilerResolutionPrefersCliOverDakIni;
var
  lCliCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lIniCompilerPath: string;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-cli-over-ini');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCliCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  lIniCompilerPath := TPath.Combine(lProjectRoot, 'ini\TMSWebCompiler.exe');
  WriteUtf8File(lCliCompilerPath, 'stub');
  WriteUtf8File(lIniCompilerPath, 'stub');
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + lIniCompilerPath + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;
  lOptions.fWebCoreCompilerPath := lCliCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected WebCore build to use the CLI compiler path. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one WebCore compiler launch.');
  Assert.IsTrue(SameText(lCliCompilerPath, lCapturingRunner.fExePaths[0]),
    'Expected CLI compiler path to win over dak.ini. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildWebCoreCompilerResolutionUsesDakIniWhenCliMissing;
var
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lIniCompilerPath: string;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-ini');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lIniCompilerPath := TPath.Combine(lProjectRoot, 'ini\TMSWebCompiler.exe');
  WriteUtf8File(lIniCompilerPath, 'stub');
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + lIniCompilerPath + sLineBreak);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected WebCore build to use dak.ini compiler path. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one WebCore compiler launch.');
  Assert.IsTrue(SameText(lIniCompilerPath, lCapturingRunner.fExePaths[0]),
    'Expected dak.ini compiler path to be used when CLI is absent. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildWebCoreCompilerResolutionUsesEnvVarWhenDakIniMissing;
var
  lDprojPath: string;
  lEnvCompilerPath: string;
  lEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-env');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lEnvCompilerPath := TPath.Combine(lProjectRoot, 'env\TMSWebCompiler.exe');
  WriteUtf8File(lEnvCompilerPath, 'stub');
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + TPath.Combine(lProjectRoot, 'missing\TMSWebCompiler.exe') + sLineBreak);

  lEnvGuard := SetScopedEnvironmentVariable('DAK_TMSWEB_COMPILER', lEnvCompilerPath);
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fBuildBackend := TBuildBackend.bbWebCore;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected WebCore build to use DAK_TMSWEB_COMPILER. Error: ' + lError);
    Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one WebCore compiler launch.');
    Assert.IsTrue(SameText(lEnvCompilerPath, lCapturingRunner.fExePaths[0]),
      'Expected env var compiler path to be used when dak.ini is absent. Calls: ' +
      DescribeCapturedProcesses(lCapturingRunner));
  finally
    lEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildWebCoreCompilerResolutionUsesPathWhenConfigMissing;
var
  lDprojPath: string;
  lCompilerEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPathCompilerDir: string;
  lPathCompilerPath: string;
  lPathEnvGuard: IInterface;
  lPreviousPath: string;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-path');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lPathCompilerDir := TPath.Combine(lProjectRoot, 'path-bin');
  lPathCompilerPath := TPath.Combine(lPathCompilerDir, 'TMSWebCompiler.exe');
  WriteUtf8File(lPathCompilerPath, 'stub');
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + TPath.Combine(lProjectRoot, 'missing\TMSWebCompiler.exe') + sLineBreak);

  lPreviousPath := GetEnvironmentVariable('PATH');
  lCompilerEnvGuard := ClearScopedEnvironmentVariable('DAK_TMSWEB_COMPILER');
  lPathEnvGuard := SetScopedEnvironmentVariable('PATH', lPathCompilerDir + ';' + lPreviousPath);
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fBuildBackend := TBuildBackend.bbWebCore;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected WebCore build to use TMSWebCompiler.exe from PATH. Error: ' + lError);
    Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one WebCore compiler launch.');
    Assert.IsTrue(SameText(lPathCompilerPath, lCapturingRunner.fExePaths[0]),
      'Expected PATH compiler path to be used when CLI, dak.ini, and env var are unavailable. Calls: ' +
      DescribeCapturedProcesses(lCapturingRunner));
  finally
    lPathEnvGuard := nil;
    lCompilerEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildWebCoreCompilerResolutionDoesNotProbeFixedPaths;
var
  lDprojPath: string;
  lCompilerEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPathEnvGuard: IInterface;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-no-fixed-probe');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + TPath.Combine(lProjectRoot, 'missing\TMSWebCompiler.exe') + sLineBreak);

  lCompilerEnvGuard := ClearScopedEnvironmentVariable('DAK_TMSWEB_COMPILER');
  lPathEnvGuard := SetScopedEnvironmentVariable('PATH', lProjectRoot);
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fBuildBackend := TBuildBackend.bbWebCore;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsFalse(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected WebCore build to fail when only fixed machine paths could satisfy compiler discovery.');
    Assert.AreEqual(0, lCapturingRunner.fCallCount, 'No compiler should be launched when discovery fails.');
    Assert.IsFalse(ContainsText(lError, 'TMS-SmartSetUp'),
      'Compiler resolution must not mention hardcoded machine-specific probe paths. Error: ' + lError);
    Assert.IsFalse(ContainsText(lError, 'Program Files'),
      'Compiler resolution must not mention hardcoded install roots. Error: ' + lError);
  finally
    lPathEnvGuard := nil;
    lCompilerEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildWebCoreMissingCompilerReportsSupportedSources;
var
  lDprojPath: string;
  lCompilerEnvGuard: IInterface;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lPathEnvGuard: IInterface;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-compiler-missing-message');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  WriteIniTextFile(TPath.Combine(lProjectRoot, 'dak.ini'),
    '[WebCore]' + sLineBreak +
    'CompilerPath=' + TPath.Combine(lProjectRoot, 'missing\TMSWebCompiler.exe') + sLineBreak);

  lCompilerEnvGuard := ClearScopedEnvironmentVariable('DAK_TMSWEB_COMPILER');
  lPathEnvGuard := SetScopedEnvironmentVariable('PATH', lProjectRoot);
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fBuildBackend := TBuildBackend.bbWebCore;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsFalse(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected missing WebCore compiler resolution to fail.');
    Assert.AreEqual(0, lCapturingRunner.fCallCount, 'No compiler should be launched when discovery fails.');
    Assert.IsTrue(ContainsText(lError, '--webcore-compiler'),
      'Expected missing compiler message to mention the CLI override. Error: ' + lError);
    Assert.IsTrue(ContainsText(lError, '[WebCore]') and ContainsText(lError, 'CompilerPath'),
      'Expected missing compiler message to mention dak.ini settings. Error: ' + lError);
    Assert.IsTrue(ContainsText(lError, 'DAK_TMSWEB_COMPILER'),
      'Expected missing compiler message to mention the environment variable. Error: ' + lError);
    Assert.IsTrue(ContainsText(lError, 'PATH'),
      'Expected missing compiler message to mention PATH lookup. Error: ' + lError);
  finally
    lPathEnvGuard := nil;
    lCompilerEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildWebCoreUsesCompilerFromCli;
var
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-auto-cli-compiler');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbAuto;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected WebCore auto build to use the CLI compiler path. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.IsTrue(lCapturingRunner.fCallCount >= 1, 'Expected at least one WebCore process launch.');
  Assert.IsTrue(SameText(lCompilerPath, lCapturingRunner.fExePaths[0]),
    'Expected auto-detected WebCore build to launch the CLI compiler path. Calls: ' +
    DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[0], '/ParseDprojFile'),
    'Expected WebCore compiler args to include /ParseDprojFile. Args: ' + lCapturingRunner.fArgumentsList[0]);
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[0], '/Config:Debug'),
    'Expected WebCore compiler args to include the selected config. Args: ' + lCapturingRunner.fArgumentsList[0]);
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[0], '/PWA'),
    'Expected WebCore builds to enable /PWA by default. Args: ' + lCapturingRunner.fArgumentsList[0]);
end;

procedure TBuildTests.BuildWebCoreRunsDebugPatchHook;
var
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-debug-hook');
  PrepareWebCoreDebugHookFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbAuto;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected WebCore build to run the debug patch hook. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.AreEqual(2, lCapturingRunner.fCallCount,
    'Expected compiler plus debug patch hook launches. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(ExtractFileName(lCapturingRunner.fExePaths[1]), 'powershell.exe'),
    'Expected the second launch to invoke PowerShell. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], 'patch-index-debug.ps1'),
    'Expected PowerShell args to target patch-index-debug.ps1. Args: ' + lCapturingRunner.fArgumentsList[1]);
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], '-ProjectDir'),
    'Expected PowerShell args to pass -ProjectDir. Args: ' + lCapturingRunner.fArgumentsList[1]);
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], '-Config') and
    ContainsText(lCapturingRunner.fArgumentsList[1], 'Debug'),
    'Expected PowerShell args to pass the build config. Args: ' + lCapturingRunner.fArgumentsList[1]);
  Assert.IsTrue(ContainsText(lCapturingRunner.fArgumentsList[1], '-ProjectName') and
    ContainsText(lCapturingRunner.fArgumentsList[1], 'WebCoreCheck'),
    'Expected PowerShell args to pass the project name. Args: ' + lCapturingRunner.fArgumentsList[1]);
end;

procedure TBuildTests.BuildWebCoreSkipsPatchHookOutsideDebug;
var
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-release-hook-skip');
  PrepareWebCoreDebugHookFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Release';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbAuto;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected non-Debug WebCore build to skip the patch hook cleanly. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.AreEqual(1, lCapturingRunner.fCallCount,
    'Expected only the WebCore compiler launch outside Debug. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
end;

procedure TBuildTests.BuildWebCoreNoPwaOmitsPwaArgument;
var
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-no-pwa');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;
  lOptions.fWebCorePwaEnabled := False;
  lOptions.fHasWebCorePwaEnabled := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected WebCore build with --no-pwa to complete successfully. Error: ' + lError);
  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.IsFalse(ContainsText(lCapturingRunner.fArgumentsList[0], '/PWA'),
    'Expected explicit --no-pwa to omit /PWA from compiler args. Args: ' + lCapturingRunner.fArgumentsList[0]);
end;

procedure TBuildTests.BuildAutoDetectedWebCoreRejectsCompilerOverlays;
var
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-auto-compiler-overlays');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbAuto;
  lOptions.fBuildDefines := 'maxProfiling';
  lOptions.fHasBuildDefines := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';
  Assert.IsFalse(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected auto-detected WebCore build to reject --define overlays.');
  Assert.IsTrue(Pos('--define', lError) > 0,
    'Expected rejection to mention --define. Actual: ' + lError);
  Assert.AreEqual(0, lCapturingRunner.fCallCount,
    'Expected rejection before any WebCore compiler launch.');

  lOptions.fBuildDefines := '';
  lOptions.fHasBuildDefines := False;
  lOptions.fBuildUnitSearchPath := TPath.Combine(lProjectRoot, 'ProfilerRuntime');
  lOptions.fHasBuildUnitSearchPath := True;
  lError := '';
  Assert.IsFalse(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'Expected auto-detected WebCore build to reject --unit-search-path overlays.');
  Assert.IsTrue(Pos('--unit-search-path', lError) > 0,
    'Expected rejection to mention --unit-search-path. Actual: ' + lError);
  Assert.AreEqual(0, lCapturingRunner.fCallCount,
    'Expected rejection before any WebCore compiler launch.');
end;

procedure TBuildTests.BuildAutoDetectedWebCoreRejectsKeepLogs;
var
  lCapturingRunner: TCapturingBuildRunner;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-auto-keep-logs');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbAuto;
  lOptions.fBuildKeepLogs := True;
  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lError := '';

  Assert.IsFalse(TryRunBuild(lOptions, lRunner, lExitCode, lError),
    'The WebCore backend keeps no MSBuild logs, so it must say so instead of ignoring --keep-logs.');
  Assert.IsTrue(Pos('--keep-logs', lError) > 0, lError);
  Assert.AreEqual(0, lCapturingRunner.fCallCount, 'Expected rejection before any WebCore compiler launch.');
end;

procedure TBuildTests.BuildAutoFallsBackToDelphiWhenWebCoreProbeNeedsEnvironment;
var
  lDprPath: string;
  lDprojPath: string;
  lEnvGuard: IInterface;
  lEnvImportPath: string;
  lError: string;
  lExitCode: Integer;
  lFakeBdsRoot: string;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRsVarsPath: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'auto-delphi-fallback');
  ForceDirectories(lProjectRoot);
  lDprojPath := TPath.Combine(lProjectRoot, 'AutoDelphiCheck.dproj');
  lDprPath := TPath.ChangeExtension(lDprojPath, '.dpr');
  lEnvImportPath := TPath.Combine(lProjectRoot, 'env-import.props');
  WriteUtf8File(lEnvImportPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <ImportedFromEnv>1</ImportedFromEnv>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprojPath,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' + sLineBreak +
    '  <Import Project="$(DAK_TEST_IMPORT)" />' + sLineBreak +
    '  <PropertyGroup>' + sLineBreak +
    '    <MainSource>AutoDelphiCheck.dpr</MainSource>' + sLineBreak +
    '    <DCC_ExeOutput>bin</DCC_ExeOutput>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);
  WriteUtf8File(lDprPath,
    'program AutoDelphiCheck;' + sLineBreak +
    'begin' + sLineBreak +
    'end.' + sLineBreak);

  lFakeBdsRoot := TPath.Combine(lProjectRoot, 'fake-bds-root');
  ForceDirectories(TPath.Combine(lFakeBdsRoot, 'bin'));
  lRsVarsPath := TPath.Combine(lFakeBdsRoot, 'bin\rsvars.bat');
  TFile.WriteAllText(lRsVarsPath, '@echo off' + sLineBreak, TEncoding.ASCII);
  WriteUtf8File(TPath.Combine(lFakeBdsRoot, 'bin\MSBuild.exe'), 'stub');

  lEnvGuard := SetScopedEnvironmentVariable('DAK_TEST_IMPORT', lEnvImportPath);
  try
    lOptions := Default(TAppOptions);
    lOptions.fDprojPath := lDprojPath;
    lOptions.fConfig := 'Debug';
    lOptions.fPlatform := 'Win32';
    lOptions.fDelphiVersion := '23.0';
    lOptions.fRsVarsPath := lRsVarsPath;
    lOptions.fBuildBackend := TBuildBackend.bbAuto;

    lCapturingRunner := TCapturingBuildRunner.Create;
    lRunner := lCapturingRunner;
    lError := '';
    Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
      'Expected auto backend to fall back to Delphi when WebCore probing needs environment imports. Error: ' + lError);
    Assert.AreEqual(0, lExitCode, 'Expected fake Delphi build to succeed.');
    Assert.AreEqual(1, lCapturingRunner.fCallCount, 'Expected exactly one MSBuild launch.');
    Assert.IsTrue(ContainsText(ExtractFileName(lCapturingRunner.fExePaths[0]), 'MSBuild.exe'),
      'Expected auto backend fallback to launch MSBuild. Calls: ' + DescribeCapturedProcesses(lCapturingRunner));
  finally
    lEnvGuard := nil;
  end;
end;

procedure TBuildTests.BuildWebCoreAiBuildEmitsSuccessSummary;
var
  lCapturedOutput: string;
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-ai-summary');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;
  lOptions.fBuildAi := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      lError := '';
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected WebCore build to complete successfully. Error: ' + lError);
    end);

  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.IsTrue(Pos('SUCCESS.', lCapturedOutput) > 0,
    'Expected AI summary output for successful WebCore builds. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.BuildWebCorePlainBuildEmitsOutputPath;
var
  lCapturedOutput: string;
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-plain-summary');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      lError := '';
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected plain WebCore build summary to complete successfully. Error: ' + lError);
    end);

  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.IsTrue(Pos('Build succeeded:', lCapturedOutput) > 0,
    'Expected plain summary output to include the success banner. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('TMSWeb\Debug\index.html', lCapturedOutput) > 0,
    'Expected plain summary output to include the WebCore output path. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.BuildWebCoreJsonBuildEmitsSummary;
var
  lCapturedOutput: string;
  lCompilerPath: string;
  lDprojPath: string;
  lError: string;
  lExitCode: Integer;
  lOptions: TAppOptions;
  lProjectRoot: string;
  lRunner: IBuildProcessRunner;
  lCapturingRunner: TCapturingBuildRunner;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'webcore-json-summary');
  PrepareWebCoreBuildFixture(lProjectRoot, lDprojPath);
  lCompilerPath := TPath.Combine(lProjectRoot, 'cli\TMSWebCompiler.exe');
  WriteUtf8File(lCompilerPath, 'stub');

  lOptions := Default(TAppOptions);
  lOptions.fDprojPath := lDprojPath;
  lOptions.fConfig := 'Debug';
  lOptions.fPlatform := 'Win32';
  lOptions.fBuildBackend := TBuildBackend.bbWebCore;
  lOptions.fWebCoreCompilerPath := lCompilerPath;
  lOptions.fHasWebCoreCompilerPath := True;
  lOptions.fBuildJson := True;

  lCapturingRunner := TCapturingBuildRunner.Create;
  lRunner := lCapturingRunner;
  lCapturedOutput := CaptureConsoleOutput(
    procedure
    begin
      lError := '';
      Assert.IsTrue(TryRunBuild(lOptions, lRunner, lExitCode, lError),
        'Expected JSON WebCore build summary to complete successfully. Error: ' + lError);
    end);

  Assert.AreEqual(0, lExitCode, 'Expected fake WebCore build to succeed.');
  Assert.IsTrue(Pos('"status":"ok"', lCapturedOutput) > 0,
    'Expected JSON summary output to include the ok status. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('"output":"', lCapturedOutput) > 0,
    'Expected JSON summary output to include the output path. Output: ' + lCapturedOutput);
  Assert.IsTrue(Pos('index.html', lCapturedOutput) > 0,
    'Expected JSON summary output to include the WebCore output file. Output: ' + lCapturedOutput);
end;

procedure TBuildTests.IdeConfigFallsBackToEnvOptionsWin64Alias;
var
  lEnvOptionsPath: string;
  lEnvVars: TDictionary<string, string>;
  lError: string;
  lFakeLibPath: string;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lProjectRoot: string;
begin
  EnsureTempClean;
  lProjectRoot := TPath.Combine(TempRoot, 'ide-config-envoptions-alias');
  if TDirectory.Exists(lProjectRoot) then
    TDirectory.Delete(lProjectRoot, True);
  TDirectory.CreateDirectory(lProjectRoot);

  lFakeLibPath := TPath.Combine(lProjectRoot, 'fake-lib\win64');
  ForceDirectories(lFakeLibPath);
  lEnvOptionsPath := TPath.Combine(lProjectRoot, 'EnvOptions.proj');
  WriteUtf8File(lEnvOptionsPath,
    '<Project>' + sLineBreak +
    '  <PropertyGroup Condition="''$(Platform)''==''Win64x''">' + sLineBreak +
    '    <DelphiLibraryPath>' + lFakeLibPath + '</DelphiLibraryPath>' + sLineBreak +
    '    <DCC_Namespace>Winapi;System.Win</DCC_Namespace>' + sLineBreak +
    '  </PropertyGroup>' + sLineBreak +
    '</Project>' + sLineBreak);

  lEnvVars := nil;
  try
    lError := '';
    Assert.IsTrue(TryReadIdeConfig('99.9', 'Win64', lEnvOptionsPath, lEnvVars, lLibraryPath, lLibrarySource, nil,
      lError), 'Expected EnvOptions fallback to succeed. Error: ' + lError);
    Assert.IsTrue(SameText(lLibraryPath, lFakeLibPath),
      'Expected DelphiLibraryPath from the Win64x EnvOptions block. Actual: ' + lLibraryPath);
    Assert.AreEqual(Integer(TPropertySource.psEnvOptions), Integer(lLibrarySource),
      'Expected EnvOptions to be reported as the library source.');
    Assert.IsTrue(Assigned(lEnvVars), 'Expected EnvOptions environment values to be captured.');
    Assert.IsTrue(lEnvVars.ContainsKey('DCC_Namespace'), 'Expected DCC_Namespace from EnvOptions to be captured.');
    Assert.AreEqual('Winapi;System.Win', lEnvVars['DCC_Namespace'],
      'Expected DCC_Namespace from the aliased Win64x block.');
  finally
    lEnvVars.Free;
  end;
end;

procedure TBuildTests.ParseBuildLogsAppliesIgnoreAndExcludeFilters;
var
  lErrLog: string;
  lOutLog: string;
  lOptions: TBuildSummaryOptions;
  lSummary: TBuildSummary;
begin
  EnsureResolverBuilt;
  EnsureTempClean;
  lOutLog := TPath.Combine(TempRoot, 'build-parse.out.log');
  lErrLog := TPath.Combine(TempRoot, 'build-parse.err.log');

  WriteUtf8File(lErrLog,
    'F:\repo\src\main.pas(10): error E2003: Undeclared identifier: ''Foo''' + sLineBreak +
    'F:\repo\3rdParty\skip.pas(20): error E2003: Undeclared identifier: ''Bar''' + sLineBreak);
  WriteUtf8File(lOutLog,
    'F:\repo\src\warn1.pas(30): warning W1000: Visible warning' + sLineBreak +
    'F:\repo\src\warn2.pas(31): warning W2000: Ignored warning' + sLineBreak +
    'F:\repo\src\hint1.pas(40): hint H1000: Visible hint' + sLineBreak +
    'F:\repo\src\hint2.pas(41): hint H2000: Ignored hint' + sLineBreak);

  lOptions := Default(TBuildSummaryOptions);
  lOptions.fProjectRoot := 'F:\repo';
  lOptions.fIgnoreWarnings := 'W2000';
  lOptions.fIgnoreHints := 'H2000';
  lOptions.fExcludePathMasks := '3rdParty\*';
  lOptions.fMaxFindings := 5;
  lOptions.fIncludeWarnings := True;
  lOptions.fIncludeHints := True;

  lSummary := ParseBuildLogs(lOutLog, lErrLog, lOptions);

  Assert.AreEqual(1, lSummary.fErrorCount, 'Excluded paths must not contribute to error counts.');
  Assert.AreEqual(1, lSummary.fWarningCount, 'Ignored warnings must not contribute to warning counts.');
  Assert.AreEqual(1, lSummary.fHintCount, 'Ignored hints must not contribute to hint counts.');
  Assert.AreEqual(1, Integer(Length(lSummary.fErrors)), 'Only one error finding should remain after path exclusion.');
  Assert.AreEqual(1, Integer(Length(lSummary.fWarnings)), 'Ignored warnings must not be returned as findings.');
  Assert.AreEqual(1, Integer(Length(lSummary.fHints)), 'Ignored hints must not be returned as findings.');
  Assert.AreEqual('src\main.pas(10): error E2003: Undeclared identifier: ''Foo''', lSummary.fErrors[0]);
  Assert.AreEqual('src\warn1.pas(30): warning W1000: Visible warning', lSummary.fWarnings[0]);
  Assert.AreEqual('src\hint1.pas(40): hint H1000: Visible hint', lSummary.fHints[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TBuildTests);

end.
