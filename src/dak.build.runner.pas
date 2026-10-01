unit Dak.Build.Runner;

interface

uses
  System.Generics.Collections, System.IOUtils, System.SysUtils,
  Dak.Build.Types, Dak.Types;

function TryRunBuildInternal(const aOptions: TAppOptions; out aExitCode: Integer; out aError: string): Boolean; overload;
function TryRunBuildInternal(const aOptions: TAppOptions; const aRunner: IBuildProcessRunner;
  out aExitCode: Integer; out aError: string): Boolean; overload;
function TryRunBuildInternal(const aOptions: TAppOptions; const aRunner: IBuildProcessRunner;
  const aDfmCheckRunner: TBuildDfmCheckRunner; out aExitCode: Integer; out aError: string): Boolean; overload;
// DAK-379: creates the per-run `run-<guid>` log directory that --keep-logs/--log-dir describe. Public so that
// concurrent creation can be proved without running builds.
function TryCreateBuildLogRunDir(const aOptions: TAppOptions; out aRunDir: string; out aError: string): Boolean;

implementation

uses
  System.Character, System.Classes, System.JSON, System.RegularExpressions, System.StrUtils,
  System.Win.Registry,
  Winapi.Windows,
  maxLogic.StrUtils,
  SimpleParser.Lexer, SimpleParser.Lexer.Types,
  Dak.Build.Enrichment, Dak.Build.Summary, Dak.DfmCheck,
  Dak.Diagnostics, Dak.ExternalToolProcess, Dak.Lsp.Context, Dak.Lsp.Runner, Dak.MacroExpander, Dak.Messages,
  Dak.MsBuild, Dak.MsBuild.Args, Dak.Paths, Dak.Project.BuildParams, Dak.Project.SourceLookup,
  Dak.RadStudio.Locator, Dak.Registry, Dak.RsVars,
  Dak.Settings, Dak.SourceContext, Dak.Utils;

const
  cStatusOk = 'ok';
  cStatusWarnings = 'warnings';
  cStatusHints = 'hints';
  cStatusError = 'error';
  cStatusTimeout = 'timeout';
  cStatusOutputLocked = 'output_locked';
  cStatusOutputMissing = 'output_missing';
  cStatusInternalError = 'internal_error';
  cMadExceptSymbol = 'madExcept';
  cMadExceptPatchExeName = 'madExceptPatch.exe';
  cTmsWebCompilerExeName = 'TMSWebCompiler.exe';
  cWebCoreCompilerEnvVar = 'DAK_TMSWEB_COMPILER';
  cMsBuildNotFound = 'MSBuild.exe not found.';
  cMadExceptPatchRequiredMessage = 'madExcept patch is required but madExceptPatch.exe was not found.';
  cMadExceptPatchFailedMessage = 'madExcept patch step failed.';
  cMadExceptOutputMissingMessage = 'Resolved build output path does not exist: %s';
  cWebCoreCompilerMissingMessage =
    'TMSWebCompiler.exe not found. Checked --webcore-compiler, [WebCore].CompilerPath in dak.ini, ' +
    'DAK_TMSWEB_COMPILER, and PATH.';
  cOutputMissingMessage = 'Compilation succeeded but the resolved output file does not exist: %s';
  cOutputUnresolvedMessage = 'Compilation succeeded but the output file name could not be resolved: %s';
  cTestOutputDirUnusable = 'Test output directory is not usable: %s (%s)';
  cTestOutputDirDriveRelative = 'a path that depends on the working directory''s drive is not accepted; give a ' +
    'relative path or a full path';
  cOutputLockedMessage =
    'Compilation succeeded but output file timestamp was not updated. The executable may be locked by another process.';
  cBuildDiagnosticsDirEnvVar = 'DAK_BUILD_DIAGNOSTICS_DIR';
  cBuildLogsDirCreateFailed = 'Build log directory could not be created: %s (%s)';
  cBuildLogsRootUnusable = 'Build log directory is not usable: %s (%s)';
  cBuildLogsCopyFailed = 'Build logs could not be kept: %s could not be saved in %s (%s)';
  cBuildLogMissing = '%s was not produced by the build process';
  cBuildLogsKept = 'Build logs kept: %s';
  cBuildLogsRunDirPrefix = 'run-';
  cBuildLogsCreateAttempts = 5;
  cBuildLogsDriveRelative = 'a root that depends on the working directory is not accepted; give a path relative ' +
    'to the project directory or a full path';
  cMsBuildInvalidPropertyError = 'error MSB1006';
  cMsBuildRedactedValue = '<redacted>';
  cMsBuildRejectedSwitchScanLines = 50;
  cMsBuildTraceMaxLength = 32768;
  cMsBuildTraceTruncated = ' ... [truncated]';
  cMsBuildRejectedPropertyMessage = 'DAK: MSBuild rejected the generated property %s. Values are not shown.';
  cMsBuildRejectedUnknownMessage =
    'DAK: MSBuild rejected a generated /p: property that DAK could not identify. Rerun with --verbose to list ' +
    'the generated MSBuild arguments; environment.proj values are redacted there.';
  cMsBuildOriginEnvironmentProj = 'from environment.proj';
  cMsBuildOriginOption = 'from the build options';

type
  TMsBuildPropertyOrigin = (poOption, poEnvironmentProj);

  TMsBuildProperty = record
    fName: string;
    fValue: string;
    fOrigin: TMsBuildPropertyOrigin;
  end;

  // DAK-379: the per-run directory of --keep-logs and the failure to fill it. fError is set after the build ran,
  // so the build result and the retention failure are both reported.
  TBuildLogRetention = record
    fRunDir: string;
    fError: string;
  end;

  // avTrace is the form we may print: environment.proj can hold secrets, so its values are replaced.
  TMsBuildArgumentsView = (avProcess, avTrace);

  TBuildProjectInfo = record
    fProjectPath: string;
    fProjectDir: string;
    fProjectName: string;
    fMainSourcePath: string;
    fMesPath: string;
    fDefines: string;
    fUnitSearchPath: string;
    fOutputPath: string;
    // DAK-374: fOutputPath is empty when the artifact name is unknown; this says why.
    fOutputUnresolvedReason: string;
    fOutputNameSource: string;
    // DAK-374: set when the name assumes something DAK could not check, such as an include it could not read.
    fOutputNote: string;
    fMadExceptRequired: Boolean;
    fMadExceptReason: string;
  end;

  // DAK-374: how a platform names programs, libraries and packages (CodeGear.Common.Targets).
  TArtifactNaming = record
    fExeExt: string;
    fDllExt: string;
    fBplExt: string;
    fDllPrefix: string;
    fBplPrefix: string;
    fSource: string;
  end;

  TWebCoreProjectInfo = record
    fIsWebCore: Boolean;
    fProjectPath: string;
    fProjectDir: string;
    fProjectName: string;
    fHtmlFile: string;
    fOutputPath: string;
    fPatchIndexDebugPath: string;
    fPwaEnabled: Boolean;
  end;

  TBuildProcessRunner = class(TInterfacedObject, IBuildProcessRunner)
  public
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
      out aTimedOut: Boolean; out aError: string): Boolean;
  end;

function QuoteCmdArg(const aValue: string): string;
begin
  if (aValue = '') or (Pos(' ', aValue) > 0) or (Pos('"', aValue) > 0) or (Pos(';', aValue) > 0) then
    Result := '"' + StringReplace(aValue, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := aValue;
end;

function MergeSemicolonValues(const aOverlayValue, aProjectValue: string): string;
var
  lOverlayValue: string;
  lProjectValue: string;
begin
  lOverlayValue := Trim(aOverlayValue);
  lProjectValue := Trim(aProjectValue);
  if lOverlayValue = '' then
    Exit(lProjectValue);
  if lProjectValue = '' then
    Exit(lOverlayValue);
  Result := lOverlayValue + ';' + lProjectValue;
end;

procedure AddMsBuildProperty(var aProperties: TArray<TMsBuildProperty>; const aName, aValue: string;
  aOrigin: TMsBuildPropertyOrigin);
var
  lProperty: TMsBuildProperty;
begin
  lProperty.fName := aName;
  lProperty.fValue := aValue;
  lProperty.fOrigin := aOrigin;
  aProperties := aProperties + [lProperty];
end;

function RenderMsBuildProperties(const aProperties: TArray<TMsBuildProperty>; aView: TMsBuildArgumentsView): string;
var
  lProperty: TMsBuildProperty;
begin
  Result := '';
  for lProperty in aProperties do
  begin
    Result := Result + ' /p:' + lProperty.fName + '=';
    if (aView = TMsBuildArgumentsView.avTrace) and
      (lProperty.fOrigin = TMsBuildPropertyOrigin.poEnvironmentProj) then
      Result := Result + cMsBuildRedactedValue
    else
      Result := Result + QuoteMsBuildPropertyValue(lProperty.fValue);
  end;
end;

function NormalizeDelphiVerForBuild(const aValue: string): string;
begin
  Result := Trim(aValue);
  if (Result <> '') and (Pos('.', Result) = 0) then
    Result := Result + '.0';
end;

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

function DiagnosticSourceToken(const aDiagnostic: TBuildDiagnostic): string;
var
  lColNumber: Integer;
  lLineNumber: Integer;
begin
  // Display normalization can remove a repository prefix unrelated to the caller's directory.
  // Retain the compiler's source identity for lookup, without changing the reported token.
  if not TryParseFindingLocationWithColumn(aDiagnostic.fRawLine, Result, lLineNumber, lColNumber) or
    (lLineNumber <> aDiagnostic.fLine) or (lColNumber <> aDiagnostic.fColumn) then
    Result := aDiagnostic.fFileToken;
end;

function AppendSourceContextToFinding(const aDisplayFinding: string; const aDiagnostic: TBuildDiagnostic;
  const aCache: TSourceContextRunCache; aContextLines: Integer): string;
var
  lContext: TSourceContextSnippet;
  lError: string;
  lFileToken: string;
begin
  Result := aDisplayFinding;
  lFileToken := DiagnosticSourceToken(aDiagnostic);
  if (lFileToken = '') or (aDiagnostic.fLine <= 0) then
    Exit(Result);
  if not aCache.TryResolve(lFileToken, aDiagnostic.fLine, aContextLines, lContext, lError) then
    Exit(Result);
  Result := Result + sLineBreak + PrefixSourceContext(FormatSourceContextLines(lContext));
end;

procedure EnrichBuildFindingsWithSourceContext(var aItems: TArray<string>; const aDiagnostics: TArray<TBuildDiagnostic>;
  const aCache: TSourceContextRunCache; aContextLines: Integer);
var
  i: Integer;
begin
  for i := 0 to High(aItems) do
    if i <= High(aDiagnostics) then
      aItems[i] := AppendSourceContextToFinding(aItems[i], aDiagnostics[i], aCache, aContextLines);
end;

function LspHintCacheKey(const aOperation, aFilePath: string; aLineNumber, aColNumber: Integer;
  const aCandidate: string): string;
begin
  Result := Format('%s|%s|%d|%d|%s', [aOperation, aFilePath, aLineNumber, aColNumber, aCandidate]);
end;

function FindCandidateColumn(const aContext: TSourceContextSnippet; const aCandidate: string): Integer;
var
  lIndex: Integer;
  lLineText: string;
  lPos: Integer;
begin
  Result := 1;
  if (aCandidate = '') or (Length(aContext.fLines) = 0) then
    Exit(1);

  lIndex := aContext.fTargetLine - aContext.fStartLine;
  if (lIndex < 0) or (lIndex > High(aContext.fLines)) then
    Exit(1);

  lLineText := aContext.fLines[lIndex];
  lPos := Pos(LowerCase(aCandidate), LowerCase(lLineText));
  if lPos > 0 then
    Exit(lPos);
  Exit(1);
end;

function TryBuildLspEnrichmentText(const aOptions: TAppOptions; const aDiagnostic: TBuildDiagnostic; const aContext: TLspContext;
  aContextLines: Integer;
  const aSourceCache: TSourceContextRunCache; const aCache: TDictionary<string, string>;
  out aHintText: string; out aError: string): Boolean;
var
  lCandidate: string;
  lColNumber: Integer;
  lEnclosingSymbol: string;
  lFileToken: string;
  lHintResult: TLspRunnerResult;
  lLspOptions: TAppOptions;
  lOperation: TLspOperation;
  lResolvedContext: TSourceContextSnippet;
  lCacheKey: string;
begin
  Result := False;
  aHintText := '';
  aError := '';
  lResolvedContext := Default(TSourceContextSnippet);
  lFileToken := DiagnosticSourceToken(aDiagnostic);
  if (lFileToken = '') or (aDiagnostic.fLine <= 0) then
  begin
    aError := 'Could not parse compiler failure location: ' + aDiagnostic.fNormalizedLine;
    Exit(False);
  end;
  if not aSourceCache.TryResolveCandidate(lFileToken, aDiagnostic.fLine, aDiagnostic.fColumn,
    aContextLines, aDiagnostic.fMessage, lResolvedContext, lCandidate,
    lEnclosingSymbol, aError) then
    Exit(False);

  if not SelectEnrichmentOperation(aDiagnostic.fMessage, lCandidate, lEnclosingSymbol, lOperation) then
  begin
    aError := '';
    Exit(False);
  end;

  lColNumber := aDiagnostic.fColumn;
  lCacheKey := LspHintCacheKey(EnrichmentOperationName(lOperation), lResolvedContext.fFilePath,
    aDiagnostic.fLine, lColNumber, lCandidate);
  if aCache.ContainsKey(lCacheKey) then
  begin
    aHintText := aCache[lCacheKey];
    Exit(aHintText <> '');
  end;

  lLspOptions := aOptions;
  lLspOptions.fLspOperation := lOperation;
  lLspOptions.fLspFilePath := lResolvedContext.fFilePath;
  lLspOptions.fLspLine := aDiagnostic.fLine;
  if lColNumber > 0 then
    lLspOptions.fLspCol := lColNumber
  else
    lLspOptions.fLspCol := FindCandidateColumn(lResolvedContext, lCandidate);
  lLspOptions.fLspQuery := lCandidate;
  lLspOptions.fLspLimit := 3;
  lLspOptions.fHasLspLimit := True;

  if not TryRunLspRequest(lLspOptions, aContext, lHintResult, aError) then
  begin
    aCache.AddOrSetValue(lCacheKey, '');
    Exit(False);
  end;

  if not BuildSemanticHintText(lOperation, lHintResult.fResponseText, aHintText) then
  begin
    aCache.AddOrSetValue(lCacheKey, '');
    Exit(False);
  end;

  aCache.AddOrSetValue(lCacheKey, aHintText);
  Result := True;
end;

function CaptureEnvironment: TDictionary<string, string>;
var
  lBlock: PChar;
  lCursor: PChar;
  lLine: string;
  lName: string;
  lPos: Integer;
  lValue: string;
begin
  Result := TDictionary<string, string>.Create;
  lBlock := GetEnvironmentStrings;
  if lBlock = nil then
    Exit;

  try
    lCursor := lBlock;
    while lCursor^ <> #0 do
    begin
      lLine := lCursor;
      Inc(lCursor, Length(lLine) + 1);
      lPos := Pos('=', lLine);
      if lPos <= 1 then
        Continue;
      lName := Copy(lLine, 1, lPos - 1);
      if (lName = '') or (lName[1] = '=') then
        Continue;
      lValue := Copy(lLine, lPos + 1, MaxInt);
      Result.AddOrSetValue(lName, lValue);
    end;
  finally
    FreeEnvironmentStrings(lBlock);
  end;
end;

function BuildEnvironmentProjPath(const aDelphiVersion, aBdsRoot: string): string;
var
  lVersion: string;
begin
  lVersion := Trim(aDelphiVersion);
  if lVersion = '' then
    lVersion := ExtractFileName(ExcludeTrailingPathDelimiter(aBdsRoot));
  Result := TPath.Combine(GetEnvironmentVariable('APPDATA'),
    TPath.Combine('Embarcadero\BDS', TPath.Combine(lVersion, 'environment.proj')));
end;

// DAK-376: environment.proj is read as text, not through an XML parser, so its entities arrive undecoded. One
// left-to-right pass decodes the five predefined entities and numeric references; an unknown or malformed
// entity stays as written, and decoded text is never decoded again (&amp;lt; becomes &lt;).
function DecodeXmlEntities(const aText: string): string;
var
  lBuilder: TStringBuilder;
  lCode: Integer;
  lDigits: string;
  lEnd: Integer;
  lEntity: string;
  lIndex: Integer;
  lIsHex: Boolean;
begin
  if Pos('&', aText) = 0 then
    Exit(aText);

  lBuilder := TStringBuilder.Create(Length(aText));
  try
    lIndex := 1;
    while lIndex <= Length(aText) do
    begin
      if aText[lIndex] <> '&' then
      begin
        lBuilder.Append(aText[lIndex]);
        Inc(lIndex);
        Continue;
      end;

      lEnd := PosEx(';', aText, lIndex + 1);
      // The longest entity we accept is &#x10FFFF; (10 characters).
      if (lEnd = 0) or (lEnd - lIndex > 9) then
      begin
        lBuilder.Append('&');
        Inc(lIndex);
        Continue;
      end;

      lEntity := Copy(aText, lIndex + 1, lEnd - lIndex - 1);
      lCode := -1;
      if lEntity = 'amp' then
        lCode := Ord('&')
      else if lEntity = 'lt' then
        lCode := Ord('<')
      else if lEntity = 'gt' then
        lCode := Ord('>')
      else if lEntity = 'quot' then
        lCode := Ord('"')
      else if lEntity = 'apos' then
        lCode := Ord('''')
      else if (Length(lEntity) > 1) and (lEntity[1] = '#') then
      begin
        lIsHex := (lEntity[2] = 'x');
        if lIsHex then
          lDigits := '$' + Copy(lEntity, 3, MaxInt)
        else
          lDigits := Copy(lEntity, 2, MaxInt);
        // A sign or blank would be accepted by StrToIntDef; a numeric reference has digits only.
        if (lDigits <> '') and (lDigits <> '$') and
          TRegEx.IsMatch(lDigits, '^(?:\$[0-9A-Fa-f]+|[0-9]+)$') then
          lCode := StrToIntDef(lDigits, -1);
        // Surrogate halves and values past U+10FFFF are not characters.
        if (lCode <= 0) or (lCode > $10FFFF) or ((lCode >= $D800) and (lCode <= $DFFF)) then
          lCode := -1;
      end;

      if lCode < 0 then
      begin
        lBuilder.Append('&');
        Inc(lIndex);
        Continue;
      end;
      lBuilder.Append(Char.ConvertFromUtf32(lCode));
      lIndex := lEnd + 1;
    end;
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

function HasLineBreak(const aText: string): Boolean;
begin
  Result := (Pos(#13, aText) > 0) or (Pos(#10, aText) > 0);
end;

// Policy (DAK-068, DAK-376): every environment.proj property that the process environment lacks is forwarded, as
// the IDE does. DAK cannot know which custom variables a project references, so it does not filter by name.
// A value with a line break cannot be put on a command line safely; such a property is skipped and only its
// name is reported in aSkippedNames.
procedure ApplyEnvironmentProjProps(const aEnvProjPath: string; const aEnvVars: TDictionary<string, string>;
  out aMsBuildEnvProps: TArray<TMsBuildProperty>; out aSkippedNames: TArray<string>);
var
  lBody: string;
  lGroupMatch: TMatch;
  lGroupMatches: TMatchCollection;
  lKey: string;
  lMatches: TMatchCollection;
  lText: string;
  lValue: string;
  lMatch: TMatch;
begin
  aMsBuildEnvProps := nil;
  aSkippedNames := nil;
  if not FileExists(aEnvProjPath) then
    Exit;

  lText := TFile.ReadAllText(aEnvProjPath);
  lGroupMatches := TRegEx.Matches(lText, '<PropertyGroup(?:\s+[^>]*)?>(?<body>.*?)</PropertyGroup>',
    [roIgnoreCase, roSingleLine]);
  for lGroupMatch in lGroupMatches do
  begin
    lBody := lGroupMatch.Groups['body'].Value;
    lMatches := TRegEx.Matches(lBody, '<(?<key>[A-Za-z_][A-Za-z0-9_]*)(?:\s+[^>]*)?>(?<value>.*?)</\k<key>>',
      [roIgnoreCase, roSingleLine]);
    for lMatch in lMatches do
    begin
      lKey := Trim(lMatch.Groups['key'].Value);
      if lKey = '' then
        Continue;
      if Trim(GetEnvironmentVariable(lKey)) <> '' then
        Continue;
      if aEnvVars.ContainsKey(lKey) and (Trim(aEnvVars[lKey]) <> '') then
        Continue;

      // Tags go first: a decoded &lt; must not be mistaken for markup.
      lValue := Trim(DecodeXmlEntities(Trim(TRegEx.Replace(lMatch.Groups['value'].Value, '<[^>]+>', ''))));
      if lValue = '' then
        Continue;
      if HasLineBreak(lValue) then
      begin
        aSkippedNames := aSkippedNames + [lKey];
        Continue;
      end;
      AddMsBuildProperty(aMsBuildEnvProps, lKey, lValue, TMsBuildPropertyOrigin.poEnvironmentProj);
    end;
  end;
end;

function HasMadExceptDefine(const aDefines: string): Boolean;
var
  lDefine: string;
begin
  Result := False;
  for lDefine in SplitList(aDefines) do
    if SameText(lDefine, cMadExceptSymbol) then
      Exit(True);
end;

function TryParseIniBool(const aValue: string; out aEnabled: Boolean): Boolean;
begin
  aEnabled := False;
  if aValue = '' then
    Exit(False);

  if SameText(aValue, '1') or SameText(aValue, 'true') or SameText(aValue, 'yes') then
    aEnabled := True
  else if SameText(aValue, '0') or SameText(aValue, 'false') or SameText(aValue, 'no') then
    aEnabled := False
  else
    Exit(False);

  Result := True;
end;

function TryReadIniSectionValue(const aPath, aSection, aKey: string; out aValue: string): Boolean;
var
  lCurrentSection: string;
  lEqualsPos: Integer;
  lLine: string;
  lLines: TStringList;
  lName: string;
  lTrimmedLine: string;
begin
  Result := False;
  aValue := '';
  if not FileExists(aPath) then
    Exit(False);

  lLines := TStringList.Create;
  try
    lLines.LoadFromFile(aPath);
    lCurrentSection := '';
    for lLine in lLines do
    begin
      lTrimmedLine := Trim(lLine);
      if lTrimmedLine = '' then
        Continue;
      if (lTrimmedLine[1] = ';') or (lTrimmedLine[1] = '#') then
        Continue;
      if (lTrimmedLine[1] = '[') and (lTrimmedLine[Length(lTrimmedLine)] = ']') then
      begin
        lCurrentSection := Trim(Copy(lTrimmedLine, 2, Length(lTrimmedLine) - 2));
        Continue;
      end;
      if not SameText(lCurrentSection, aSection) then
        Continue;

      lEqualsPos := Pos('=', lTrimmedLine);
      if lEqualsPos <= 0 then
        Continue;
      lName := Trim(Copy(lTrimmedLine, 1, lEqualsPos - 1));
      if not SameText(lName, aKey) then
        Continue;

      aValue := Trim(Copy(lTrimmedLine, lEqualsPos + 1, MaxInt));
      Exit(True);
    end;
  finally
    lLines.Free;
  end;
end;

function MesFileDisablesMadExcept(const aMesPath: string): Boolean;
var
  lEnabled: Boolean;
  lValue: string;
begin
  Result := False;
  if not FileExists(aMesPath) then
    Exit(False);

  if TryReadIniSectionValue(aMesPath, 'GeneralSettings', 'LinkInCode', lValue) then
    if TryParseIniBool(lValue, lEnabled) and (not lEnabled) then
      Exit(True);

  if TryReadIniSectionValue(aMesPath, 'GeneralSettings', 'HandleExceptions', lValue) then
    if TryParseIniBool(lValue, lEnabled) and (not lEnabled) then
      Exit(True);
end;

function ResolveOutputName(const aProps: TDictionary<string, string>; const aProjectName: string): string;
begin
  if aProps.TryGetValue('SanitizedProjectName', Result) and (Trim(Result) <> '') then
    Exit(Result);
  if aProps.TryGetValue('ProjectName', Result) and (Trim(Result) <> '') then
    Exit(Result);
  Result := aProjectName;
end;

function PropertyIsEnabled(const aValue: string): Boolean; forward;

// DAK-374: the extensions and prefixes CodeGear.Common.Targets defines for a platform.
function TryGetArtifactNaming(const aProps: TDictionary<string, string>; const aPlatform: string;
  out aNaming: TArtifactNaming): Boolean;
begin
  aNaming := Default(TArtifactNaming);
  // The project imports the compiler targets, so their evaluated values are the compiler's own naming rules.
  if aProps.ContainsKey('ExeExt') then
  begin
    aProps.TryGetValue('ExeExt', aNaming.fExeExt);
    aProps.TryGetValue('DllExt', aNaming.fDllExt);
    aProps.TryGetValue('BplExt', aNaming.fBplExt);
    aProps.TryGetValue('DllPlatformPrefix', aNaming.fDllPrefix);
    aProps.TryGetValue('BplPlatformPrefix', aNaming.fBplPrefix);
    aNaming.fSource := 'compiler targets';
    Exit(True);
  end;

  // Without the targets we use the same table as CodeGear.Common.Targets of Delphi 12.
  aNaming.fSource := 'platform table';
  if MatchText(aPlatform, ['Win32', 'WinNX32', 'Win64', 'Win64x']) then
  begin
    aNaming.fExeExt := 'exe';
    aNaming.fDllExt := 'dll';
    aNaming.fBplExt := 'bpl';
  end else if SameText(aPlatform, 'Linux64') then
  begin
    aNaming.fDllExt := 'so';
    aNaming.fBplExt := 'so';
    aNaming.fDllPrefix := 'lib';
    aNaming.fBplPrefix := 'bpl';
  end else if MatchText(aPlatform, ['OSX32', 'OSX64', 'OSXARM64']) then
  begin
    aNaming.fDllExt := 'dylib';
    aNaming.fBplExt := 'dylib';
    aNaming.fDllPrefix := 'lib';
    aNaming.fBplPrefix := 'bpl';
  end else if MatchText(aPlatform, ['iOSDevice32', 'iOSDevice64', 'iOSSimulator', 'iOSSimulator64',
    'iOSSimARM64']) then
  begin
    aNaming.fDllExt := 'dylib';
    aNaming.fBplExt := 'a';
    aNaming.fDllPrefix := 'lib';
    aNaming.fBplPrefix := 'lib';
  end else if MatchText(aPlatform, ['Android', 'Android64']) then
  begin
    aNaming.fExeExt := 'so';
    aNaming.fDllExt := 'so';
    aNaming.fBplExt := 'a';
    aNaming.fDllPrefix := 'lib';
    aNaming.fBplPrefix := 'lib';
  end else
    Exit(False);
  Result := True;
end;

function AppendArtifactExtension(const aFileName, aExtension: string): string;
begin
  if aExtension = '' then
    Exit(aFileName);
  Result := aFileName + '.' + aExtension;
end;

// DAK-381: AUTO of {$LIBSUFFIX AUTO} is the version of the installed RTL package. The compiler has no property
// for it (dcc32 and dcclinux64 write 290 on Delphi 23.0 although the targets define no such value), and the
// Delphi bin folder holds exactly one rtl<N>.bpl (rtl290.bpl), which is the evidence we read instead of a table.
function TryReadAutoLibrarySuffix(const aBdsRoot: string; out aSuffix, aReason: string): Boolean;
var
  lFile: string;
  lFiles: TArray<string>;
  lMatch: TMatch;
begin
  aSuffix := '';
  aReason := '';
  if Trim(aBdsRoot) = '' then
  begin
    aReason := 'the Delphi installation folder is unknown, so the RTL package suffix cannot be read';
    Exit(False);
  end;
  try
    lFiles := TDirectory.GetFiles(TPath.Combine(aBdsRoot, 'bin'), 'rtl*.bpl');
  except
    on E: Exception do
    begin
      aReason := Format('the RTL package suffix cannot be read from "%s" (%s)', [aBdsRoot, E.Message]);
      Exit(False);
    end;
  end;
  for lFile in lFiles do
  begin
    lMatch := TRegEx.Match(TPath.GetFileName(lFile), '^rtl(\d+)\.bpl$', [roIgnoreCase]);
    if not lMatch.Success then
      Continue;
    if aSuffix <> '' then
    begin
      aSuffix := '';
      aReason := Format('"%s\bin" holds more than one rtl<N>.bpl, so the suffix of AUTO is ambiguous', [aBdsRoot]);
      Exit(False);
    end;
    aSuffix := lMatch.Groups[1].Value;
  end;
  Result := aSuffix <> '';
  if not Result then
    aReason := Format('"%s\bin" holds no rtl<N>.bpl to take the suffix of AUTO from', [aBdsRoot]);
end;

type
  // The naming directives of a main source. The compiler takes the library prefix, suffix, version and extension
  // from them. It ignores the project's DllPrefix, DllSuffix, DllVersion and DCC_DependencyCheckOutputName, which
  // the IDE only mirrors, but it does honour the project's OutputExt for programs and libraries (a {$E} wins
  // over it). Verified with dcc32, dcclinux64 and dccaarm64 on Delphi 23.0 (DAK-374 and DAK-381).
  TSourceNaming = record
    fHasPrefix: Boolean;
    fPrefix: string;
    fHasSuffix: Boolean;
    fSuffixIsAuto: Boolean;
    fSuffix: string;
    fHasVersion: Boolean;
    fVersion: string;
    fHasExtension: Boolean;
    fExtension: string;
  end;

const
  cMaxIncludes = 256;
  cNamingIncludeNote = 'naming include %s not read; name assumes no directives in it';

// 'text' as the string it stands for ('' is a quote); False for anything else.
function TryUnquoteDirectiveValue(const aArg: string; out aValue: string): Boolean;
var
  lInner: string;
begin
  aValue := '';
  Result := False;
  if (Length(aArg) < 2) or (aArg[1] <> '''') or (aArg[Length(aArg)] <> '''') then
    Exit;
  lInner := Copy(aArg, 2, Length(aArg) - 2);
  aValue := StringReplace(lInner, '''''', '''', [rfReplaceAll]);
  Result := Pos('''', StringReplace(lInner, '''''', '', [rfReplaceAll])) = 0;
end;

procedure AddOutputNote(var aNotes: string; const aNote: string);
begin
  if aNotes <> '' then
    aNotes := aNotes + '; ';
  aNotes := aNotes + aNote;
end;

type
  // Resolves {$I file} for the lexer. A file next to the including one is read; one that cannot be found (Jedi.inc
  // is often on a search path) or read is skipped with a note, so the name assumes no directive in it and the
  // post-build existence check decides. An include DAK cannot even name (wildcard or %), or too many includes (a
  // cycle), leave the naming unknown (fFatalReason).
  TNamingIncludeHandler = class(TInterfacedObject, IIncludeHandler)
  strict private
    fCount: Integer;
  public
    fNotes: string;
    fFatalReason: string;
    function GetIncludeFileContent(const aParentFileName, aIncludeName: string; out aContent,
      aFileName: string): Boolean;
  end;

function TNamingIncludeHandler.GetIncludeFileContent(const aParentFileName, aIncludeName: string; out aContent,
  aFileName: string): Boolean;
var
  lPath: string;
  lUsable: Boolean;
begin
  aContent := '';
  aFileName := '';
  Result := False;
  Inc(fCount);
  if fCount > cMaxIncludes then
  begin
    fFatalReason := Format('more than %d includes were followed, so the naming directives are not read',
      [cMaxIncludes]);
    Exit;
  end;
  if (aIncludeName = '') or (Pos('%', aIncludeName) > 0) or (Pos('*', aIncludeName) > 0) then
  begin
    fFatalReason := Format('"%s" includes "%s", which DAK cannot locate, so a naming directive there is not ' +
      'ruled out', [TPath.GetFileName(aParentFileName), aIncludeName]);
    Exit;
  end;
  lPath := aIncludeName;
  lUsable := True;
  try
    if TPath.GetExtension(lPath) = '' then
      lPath := lPath + '.inc';
    if not TPath.IsPathRooted(lPath) then
      lPath := TPath.Combine(TPath.GetDirectoryName(aParentFileName), lPath);
    lPath := TPath.GetFullPath(lPath);
  except
    // An include path that is not a usable path is one DAK could not read: it gets the same note below.
    on E: Exception do
      lUsable := False;
  end;
  if lUsable and FileExists(lPath) then
  begin
    try
      aContent := TFile.ReadAllText(lPath);
      aFileName := lPath;
      Exit(True);
    except
      // An unreadable include is noted below like a missing one.
      on E: Exception do
        aContent := '';
    end;
  end;
  AddOutputNote(fNotes, Format(cNamingIncludeNote, [ExtractFileName(aIncludeName)]));
end;

// Applies one compiler directive token to aNaming. A token that is not a naming directive is left alone. A naming
// directive in a form DAK does not evaluate makes the naming unknown.
function TryApplyNamingDirective(const aToken: string; var aNaming: TSourceNaming; out aReason: string): Boolean;
const
  cNamingDirective = '^(?:\{\$|\(\*\$)\s*(LIBPREFIX|SOPREFIX|LIBSUFFIX|SOSUFFIX|LIBVERSION|SOVERSION|EXTENSION|E)' +
    '(?![A-Za-z0-9_+-])\s*(.*?)\s*(?:\}|\*\))$';
var
  lArg: string;
  lMatch: TMatch;
  lName: string;
  lQuoted: string;
begin
  aReason := '';
  Result := True;
  // Groups: 1 = the directive name, 2 = its argument.
  lMatch := TRegEx.Match(aToken, cNamingDirective, [roIgnoreCase, roSingleLine]);
  if not lMatch.Success then
    Exit;
  lName := UpperCase(lMatch.Groups[1].Value);
  lArg := Trim(lMatch.Groups[2].Value);
  if EndsStr('PREFIX', lName) and TryUnquoteDirectiveValue(lArg, lQuoted) then
  begin
    aNaming.fHasPrefix := True;
    aNaming.fPrefix := lQuoted;
  end else if EndsStr('SUFFIX', lName) and SameText(lArg, 'AUTO') then
  begin
    aNaming.fHasSuffix := True;
    aNaming.fSuffixIsAuto := True;
    aNaming.fSuffix := '';
  end else if EndsStr('SUFFIX', lName) and TryUnquoteDirectiveValue(lArg, lQuoted) then
  begin
    aNaming.fHasSuffix := True;
    aNaming.fSuffixIsAuto := False;
    aNaming.fSuffix := lQuoted;
  end else if EndsStr('VERSION', lName) and TryUnquoteDirectiveValue(lArg, lQuoted) then
  begin
    aNaming.fHasVersion := True;
    aNaming.fVersion := lQuoted;
  end else if (EndsStr('EXTENSION', lName) or (lName = 'E')) and
    (TryUnquoteDirectiveValue(lArg, lQuoted) or TRegEx.IsMatch(lArg, '^\.?[A-Za-z0-9_]+$')) then
  begin
    // {$E ocx} is the usual form; a quoted value is taken as written.
    if not TryUnquoteDirectiveValue(lArg, lQuoted) then
      lQuoted := lArg;
    aNaming.fHasExtension := True;
    aNaming.fExtension := lQuoted;
    if StartsStr('.', aNaming.fExtension) then
      aNaming.fExtension := Copy(aNaming.fExtension, 2, MaxInt);
  end else begin
    aReason := Format('the naming directive {$%s %s} has a form DAK does not evaluate', [lName, lArg]);
    Result := False;
  end;
end;

// Reads {$LIBPREFIX}, {$LIBSUFFIX}, {$LIBVERSION} and {$E}/{$EXTENSION} (and the SO* aliases) from the main source
// in source order, as the compiler does: DelphiAST's lexer (SimpleParser.Lexer, already part of DAK) skips //, { }
// and (* *) comments and string literals, reads a directive wherever it sits on a line or spans lines, and expands
// each {$I file} where it appears through TNamingIncludeHandler. The last directive of a kind wins. Conditional
// compilation is not evaluated.
function TryReadSourceNaming(const aMainSourcePath: string; out aNaming: TSourceNaming;
  out aNotes, aReason: string): Boolean;
var
  lHandler: TNamingIncludeHandler;
  lHandlerRef: IIncludeHandler;
  lLexer: TmwBasePasLex;
  lText: string;
begin
  aNaming := Default(TSourceNaming);
  aNotes := '';
  aReason := '';
  Result := False;
  try
    lText := TFile.ReadAllText(aMainSourcePath);
  except
    on E: Exception do
    begin
      aReason := Format('the source "%s" cannot be read to find its naming directives (%s)',
        [aMainSourcePath, E.Message]);
      Exit;
    end;
  end;

  lHandler := TNamingIncludeHandler.Create;
  lHandlerRef := lHandler;
  lLexer := TmwBasePasLex.Create;
  try
    try
      lLexer.IncludeHandler := lHandlerRef;
      lLexer.Buffer.FileName := aMainSourcePath;
      lLexer.Origin := lText;
      while lLexer.TokenID <> ptNull do
      begin
        if lHandler.fFatalReason <> '' then
        begin
          aReason := lHandler.fFatalReason;
          Exit;
        end;
        if (lLexer.TokenID = ptCompDirect) and not TryApplyNamingDirective(lLexer.Token, aNaming, aReason) then
          Exit;
        lLexer.Next;
      end;
    except
      on E: Exception do
      begin
        aReason := Format('the source "%s" could not be scanned for naming directives (%s)',
          [aMainSourcePath, E.Message]);
        Exit;
      end;
    end;
    if lHandler.fFatalReason <> '' then
    begin
      aReason := lHandler.fFatalReason;
      Exit;
    end;
    aNotes := lHandler.fNotes;
  finally
    lLexer.Free;
  end;
  Result := True;
end;

// Returns False with aReason when the name is unknown; no name is guessed then. The compiler names an artifact
// <prefix><name><suffix>[.<version>].<ext> (DAK-374, DAK-381, compiler-verified on Win32, Linux64 and Android64):
// - The prefix defaults to the platform's (empty on Windows, lib or bpl on Linux, lib on Android) and is replaced
//   by {$LIBPREFIX}, also when that is empty. The extension defaults to the platform's and is replaced by {$E}.
// - Libraries and packages add {$LIBSUFFIX} and {$LIBVERSION}; the version follows the extension on Linux and
//   Android (CodeGear.Delphi.Targets l.104-105, but Linux64 as dcclinux64 does it) and precedes it elsewhere.
// - Programs keep their name and take only {$E}, except an Android program, a shared library, which also takes the
//   prefix and the suffix (not the version).
// The project properties DllPrefix, DllSuffix, DllVersion and DCC_DependencyCheckOutputName are not used.
function TryResolveOutputFileName(const aProps: TDictionary<string, string>; const aProjectName,
  aPlatform, aMainSourcePath, aBdsRoot: string; out aFileName, aSource, aReason, aNote: string;
  out aIsPackage: Boolean): Boolean;
var
  lAppType: string;
  lBaseName: string;
  lExtension: string;
  lGenDll: string;
  lIsAndroid: Boolean;
  lIsLibrary: Boolean;
  lMainSource: string;
  lNaming: TArtifactNaming;
  lOutputExt: string;
  lPrefix: string;
  lSourceNaming: TSourceNaming;
  lSuffix: string;
  lVersion: string;
begin
  aFileName := '';
  aSource := '';
  aReason := '';
  aNote := '';
  lMainSource := '';
  aProps.TryGetValue('MainSource', lMainSource);
  aIsPackage := SameText(TPath.GetExtension(Trim(lMainSource)), '.dpk');

  if not TryGetArtifactNaming(aProps, aPlatform, lNaming) then
  begin
    aReason := Format('platform "%s" has no known artifact naming rules and the project did not import ' +
      'compiler targets that define them', [aPlatform]);
    Exit(False);
  end;
  aSource := lNaming.fSource;

  // The compiler names the output after the main source file. SanitizedProjectName is the program
  // identifier form, which differs for dotted names such as Build.Output.Name.dpr (T-264).
  if Trim(lMainSource) <> '' then
    lBaseName := TPath.GetFileNameWithoutExtension(Trim(lMainSource))
  else
    lBaseName := ResolveOutputName(aProps, aProjectName);

  lAppType := '';
  lGenDll := '';
  aProps.TryGetValue('AppType', lAppType);
  aProps.TryGetValue('GenDll', lGenDll);
  lIsLibrary := aIsPackage or SameText(Trim(lAppType), 'Library') or PropertyIsEnabled(lGenDll);
  lIsAndroid := MatchText(aPlatform, ['Android', 'Android64']);

  if aIsPackage then
  begin
    lPrefix := lNaming.fBplPrefix;
    lExtension := lNaming.fBplExt;
  end else if lIsLibrary then
  begin
    lPrefix := lNaming.fDllPrefix;
    lExtension := lNaming.fDllExt;
  end else begin
    // An Android program is a shared library: dccaarm/dccaarm64 write lib<name>.so.
    if lIsAndroid then
      lPrefix := lNaming.fDllPrefix
    else
      lPrefix := '';
    lExtension := lNaming.fExeExt;
  end;

  // An Android package is a static library: dccaarm64 writes lib<name>.a into DCC_DcpOutput and ignores the naming
  // directives (verified with {$LIBPREFIX}, {$LIBSUFFIX}, {$LIBVERSION} and {$E}).
  if aIsPackage and lIsAndroid then
  begin
    aFileName := AppendArtifactExtension(lPrefix + lBaseName, lExtension);
    Exit(True);
  end;

  // The IDE's "Target file extension" (OutputExt) reaches dcc for programs and libraries, with a dot put in front
  // of it by the targets, so ".ocx" gives "..ocx". A package ignores it, and {$E} below wins over it (DAK-374).
  if not aIsPackage then
  begin
    lOutputExt := '';
    aProps.TryGetValue('OutputExt', lOutputExt);
    lOutputExt := Trim(lOutputExt);
    if Pos('$(', lOutputExt) > 0 then
    begin
      aReason := Format('OutputExt "%s" contains an unexpanded property', [lOutputExt]);
      Exit(False);
    end;
    // With the targets imported, the evaluated value already carries the dot they put in front of it (l.94: the
    // platform default, or the project's value behind a dot), and the name adds its own. Without them the value
    // is the project's own.
    if (lNaming.fSource = 'compiler targets') and StartsStr('.', lOutputExt) then
      lOutputExt := Copy(lOutputExt, 2, MaxInt);
    if lOutputExt <> '' then
      lExtension := lOutputExt;
  end;

  if not TryReadSourceNaming(aMainSourcePath, lSourceNaming, aNote, aReason) then
    Exit(False);
  if lSourceNaming.fHasExtension then
    lExtension := lSourceNaming.fExtension;

  lSuffix := '';
  lVersion := '';
  if lIsLibrary or lIsAndroid then
  begin
    if lSourceNaming.fHasPrefix then
      lPrefix := lSourceNaming.fPrefix;
    if lSourceNaming.fHasSuffix then
    begin
      if lSourceNaming.fSuffixIsAuto then
      begin
        if not TryReadAutoLibrarySuffix(aBdsRoot, lSuffix, aReason) then
          Exit(False);
      end else
        lSuffix := lSourceNaming.fSuffix;
    end;
  end;
  if lIsLibrary and lSourceNaming.fHasVersion then
    lVersion := '.' + lSourceNaming.fVersion;

  if MatchText(aPlatform, ['Linux32', 'Linux64', 'Android', 'Android64']) then
    aFileName := AppendArtifactExtension(lPrefix + lBaseName + lSuffix, lExtension) + lVersion
  else
    aFileName := AppendArtifactExtension(lPrefix + lBaseName + lSuffix + lVersion, lExtension);
  Result := True;
end;

// DAK-382: a directory property as a full path, or a reason. GetFullPath and Combine raise on a value with invalid
// path characters, which an evaluated property can hold, so they run here and never outside a guard.
function TryResolveProjectDirectory(const aValue, aProjectDir, aLabel: string; out aFullDir,
  aReason: string): Boolean;
var
  lValue: string;
begin
  aFullDir := '';
  aReason := '';
  lValue := Trim(aValue);
  if Pos('$(', lValue) > 0 then
  begin
    aReason := Format('%s "%s" contains an unexpanded property', [aLabel, lValue]);
    Exit(False);
  end;
  try
    if TPath.IsPathRooted(lValue) then
      aFullDir := TPath.GetFullPath(lValue)
    else
      aFullDir := TPath.GetFullPath(TPath.Combine(aProjectDir, lValue));
  except
    on E: Exception do
    begin
      aFullDir := '';
      aReason := Format('%s "%s" is not a usable path (%s)', [aLabel, lValue, E.Message]);
      Exit(False);
    end;
  end;
  Result := True;
end;

// DAK-382: a file property as a full path next to the project, or a reason; same guard as the directory form.
function TryResolveProjectFile(const aValue, aProjectDir, aLabel: string; out aFullPath,
  aReason: string): Boolean;
begin
  Result := TryResolveProjectDirectory(aValue, aProjectDir, aLabel, aFullPath, aReason);
end;

// DAK-374: the directory the compiler writes a package to. CodeGear.Delphi.Targets l.55 defaults an empty
// DCC_BplOutput to DelphiDLLOutputPath (EnvOptions.proj); with the targets imported the evaluated
// DCC_BplOutput already holds that default. Without either, the directory is unknown.
function TryResolvePackageOutputDir(const aProps: TDictionary<string, string>; const aProjectDir: string;
  out aOutputDir, aReason: string): Boolean;
var
  lValue: string;
begin
  aOutputDir := '';
  aReason := '';
  if not aProps.TryGetValue('DCC_BplOutput', lValue) or (Trim(lValue) = '') then
    if not aProps.TryGetValue('DelphiDLLOutputPath', lValue) or (Trim(lValue) = '') then
    begin
      aReason := 'the package output directory is unknown: DCC_BplOutput and DelphiDLLOutputPath are empty';
      Exit(False);
    end;
  Result := TryResolveProjectDirectory(lValue, aProjectDir, 'the package output directory', aOutputDir, aReason);
end;

function PropertyIsEnabled(const aValue: string): Boolean;
var
  lValue: string;
begin
  lValue := Trim(aValue);
  if lValue = '' then
    Exit(False);
  Result :=
    not SameText(lValue, '0') and
    not SameText(lValue, 'false') and
    not SameText(lValue, 'no');
end;

procedure CopyProps(const aSource, aTarget: TDictionary<string, string>);
var
  lPair: TPair<string, string>;
begin
  for lPair in aSource do
    aTarget.AddOrSetValue(lPair.Key, lPair.Value);
end;

procedure AddPropAliases(const aProps: TDictionary<string, string>; const aName, aValue: string);
var
  lLowerName: string;
begin
  aProps.AddOrSetValue(aName, aValue);
  lLowerName := LowerCase(aName);
  if lLowerName <> aName then
    aProps.AddOrSetValue(lLowerName, aValue);
end;

function ResolveProjectFilePath(const aValue, aProjectDir: string; const aProps,
  aEnvVars: TDictionary<string, string>): string;
begin
  Result := TMacroExpander.Expand(aValue, aProps, aEnvVars, nil, False);
  if not TPath.IsPathRooted(Result) then
    Result := TPath.GetFullPath(TPath.Combine(aProjectDir, Result))
  else
    Result := TPath.GetFullPath(Result);
end;

function TryEvaluateProjectProperties(const aProjectPath, aConfig, aPlatform: string;
  const aEnvVars: TDictionary<string, string>; out aProps: TDictionary<string, string>; out aError: string): Boolean;
var
  lEnvVars: TDictionary<string, string>;
  lEvaluator: TMsBuildEvaluator;
  lEnvVarPair: TPair<string, string>;
  lOptset: string;
  lOptsetPath: string;
  lProjectDir: string;
  lProjectFile: string;
  lProjectFullPath: string;
  lProjectName: string;
  lTempProps: TDictionary<string, string>;
begin
  aError := '';
  aProps := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  lEnvVars := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    try
      lProjectFullPath := TPath.GetFullPath(aProjectPath);
      lProjectDir := TPath.GetDirectoryName(lProjectFullPath);
      lProjectFile := TPath.GetFileName(lProjectFullPath);
      lProjectName := TPath.GetFileNameWithoutExtension(lProjectFullPath);
      AddPropAliases(aProps, 'Config', aConfig);
      AddPropAliases(aProps, 'Platform', aPlatform);
      AddPropAliases(aProps, 'ProjectDir', IncludeTrailingPathDelimiter(lProjectDir));
      AddPropAliases(aProps, 'PROJECTDIR', IncludeTrailingPathDelimiter(lProjectDir));
      AddPropAliases(aProps, 'ProjectName', lProjectName);
      AddPropAliases(aProps, 'MSBuildProjectName', lProjectName);
      AddPropAliases(aProps, 'MSBuildProjectFullPath', lProjectFullPath);
      AddPropAliases(aProps, 'MSBuildProjectDirectory', IncludeTrailingPathDelimiter(lProjectDir));
      AddPropAliases(aProps, 'MSBuildProjectFile', lProjectFile);

      if aEnvVars <> nil then
      begin
        for lEnvVarPair in aEnvVars do
        begin
          AddPropAliases(lEnvVars, lEnvVarPair.Key, lEnvVarPair.Value);
          if not aProps.ContainsKey(lEnvVarPair.Key) then
            AddPropAliases(aProps, lEnvVarPair.Key, lEnvVarPair.Value);
        end;
      end;

      lTempProps := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
      try
        CopyProps(aProps, lTempProps);
        lEvaluator := TMsBuildEvaluator.Create(lTempProps, lEnvVars, nil);
        try
          if not lEvaluator.EvaluateFile(lProjectFullPath, aError) then
          begin
            aProps.Free;
            aProps := nil;
            Exit(False);
          end;
        finally
          lEvaluator.Free;
        end;
        lTempProps.TryGetValue('CfgDependentOn', lOptset);
      finally
        lTempProps.Free;
      end;

      lOptsetPath := '';
      lOptset := Trim(lOptset);
      if lOptset <> '' then
      begin
        lOptsetPath := ResolveProjectFilePath(lOptset, lProjectDir, aProps, lEnvVars);
        if not FileExists(lOptsetPath) then
          lOptsetPath := '';
      end;

      if lOptsetPath <> '' then
      begin
        lEvaluator := TMsBuildEvaluator.Create(aProps, lEnvVars, nil);
        try
          if not lEvaluator.EvaluateFile(lOptsetPath, aError) then
          begin
            aProps.Free;
            aProps := nil;
            Exit(False);
          end;
        finally
          lEvaluator.Free;
        end;
      end;

      lEvaluator := TMsBuildEvaluator.Create(aProps, lEnvVars, nil);
      try
        if not lEvaluator.EvaluateFile(lProjectFullPath, aError) then
        begin
          aProps.Free;
          aProps := nil;
          Exit(False);
        end;
      finally
        lEvaluator.Free;
      end;

      Result := True;
    except
      aProps.Free;
      aProps := nil;
      raise;
    end;
  finally
    lEnvVars.Free;
  end;
end;

function LooksLikeWebCoreProject(const aProps: TDictionary<string, string>): Boolean;
var
  lHasHtmlFile: Boolean;
  lHasProjectFlag: Boolean;
  lHasTmsPackage: Boolean;
  lPackages: string;
  lProjectFlag: string;
  lHtmlFile: string;
begin
  lProjectFlag := '';
  lHtmlFile := '';
  lPackages := '';
  aProps.TryGetValue('TMSWebProject', lProjectFlag);
  aProps.TryGetValue('TMSWebHTMLFile', lHtmlFile);
  aProps.TryGetValue('DCC_UsePackage', lPackages);

  lHasProjectFlag := PropertyIsEnabled(lProjectFlag);
  lHasHtmlFile := Trim(lHtmlFile) <> '';
  lHasTmsPackage := ContainsText(lPackages, 'TMSWEBCorePkg');

  Result :=
    (lHasProjectFlag and lHasHtmlFile) or
    (lHasProjectFlag and lHasTmsPackage) or
    (lHasHtmlFile and lHasTmsPackage);
end;

function TryReadWebCoreProjectInfo(const aProjectPath, aConfig, aPlatform: string;
  const aEnvVars: TDictionary<string, string>; out aInfo: TWebCoreProjectInfo; out aError: string): Boolean;
var
  lHtmlFile: string;
  lProps: TDictionary<string, string>;
  lProjectName: string;
  lPwaValue: string;
begin
  aInfo := Default(TWebCoreProjectInfo);
  aError := '';
  lProps := nil;
  if not TryEvaluateProjectProperties(aProjectPath, aConfig, aPlatform, aEnvVars, lProps, aError) then
    Exit(False);
  try
    aInfo.fProjectPath := TPath.GetFullPath(aProjectPath);
    aInfo.fProjectDir := TPath.GetDirectoryName(aInfo.fProjectPath);
    lProjectName := TPath.GetFileNameWithoutExtension(aInfo.fProjectPath);
    if lProps.TryGetValue('ProjectName', aInfo.fProjectName) and (Trim(aInfo.fProjectName) <> '') then
      lProjectName := aInfo.fProjectName
    else
      aInfo.fProjectName := lProjectName;

    if not lProps.TryGetValue('TMSWebHTMLFile', lHtmlFile) or (Trim(lHtmlFile) = '') then
      lHtmlFile := 'index.html';
    aInfo.fHtmlFile := lHtmlFile;
    aInfo.fOutputPath := TPath.Combine(TPath.Combine(aInfo.fProjectDir, 'TMSWeb\' + aConfig), aInfo.fHtmlFile);
    aInfo.fPatchIndexDebugPath := TPath.Combine(aInfo.fProjectDir, 'tools\patch-index-debug.ps1');
    aInfo.fIsWebCore := LooksLikeWebCoreProject(lProps);
    if lProps.TryGetValue('TMSWebPWA', lPwaValue) then
      aInfo.fPwaEnabled := PropertyIsEnabled(lPwaValue)
    else
      aInfo.fPwaEnabled := False;

    Result := True;
  finally
    lProps.Free;
  end;
end;

function BuildProjectInfo(const aProjectPath, aConfig, aPlatform: string;
  const aEnvVars: TDictionary<string, string>; const aTestOutputDir, aBuildDefines,
  aBuildUnitSearchPath, aBdsRoot: string; out aError: string): TBuildProjectInfo;
var
  lError: string;
  lIsPackage: Boolean;
  lProps: TDictionary<string, string>;
  lOutputDir: string;
  lMainSourcePath: string;
  lMainSourceUsable: Boolean;
  lOutputFileName: string;
  lOutputValue: string;
  lPackageDir: string;
begin
  Result := Default(TBuildProjectInfo);
  aError := '';
  Result.fProjectPath := TPath.GetFullPath(aProjectPath);
  Result.fProjectDir := TPath.GetDirectoryName(Result.fProjectPath);
  Result.fProjectName := TPath.GetFileNameWithoutExtension(Result.fProjectPath);
  Result.fMesPath := TPath.ChangeExtension(Result.fProjectPath, '.mes');

  lProps := nil;
  try
    if not TryEvaluateProjectProperties(Result.fProjectPath, aConfig, aPlatform,
      aEnvVars, lProps, lError) then
    begin
      aError := lError;
      Exit;
    end;

    if not lProps.TryGetValue('MainSource', Result.fMainSourcePath) or (Trim(Result.fMainSourcePath) = '') then
      Result.fMainSourcePath := Result.fProjectName + '.dpr';
    // DAK-382: MainSource is an evaluated property too, so an unusable value is a named reason, not an exception.
    lMainSourceUsable := TryResolveProjectFile(Result.fMainSourcePath, Result.fProjectDir, 'MainSource',
      lMainSourcePath, Result.fOutputUnresolvedReason);
    if lMainSourceUsable then
      Result.fMainSourcePath := lMainSourcePath;

    if lMainSourceUsable and TryResolveOutputFileName(lProps, Result.fProjectName, aPlatform,
      Result.fMainSourcePath, aBdsRoot, lOutputFileName, Result.fOutputNameSource,
      Result.fOutputUnresolvedReason, Result.fOutputNote, lIsPackage) then
    begin
      // aTestOutputDir is already a validated full path (NormalizeBuildOptions).
      if aTestOutputDir <> '' then
        Result.fOutputPath := TPath.Combine(aTestOutputDir, lOutputFileName)
      else if not lIsPackage then
      begin
        // DAK-382: an unusable DCC_ExeOutput leaves the path unresolved with a reason instead of raising.
        if not lProps.TryGetValue('DCC_ExeOutput', lOutputValue) or (Trim(lOutputValue) = '') then
          lOutputDir := Result.fProjectDir
        else
          TryResolveProjectDirectory(lOutputValue, Result.fProjectDir, 'DCC_ExeOutput', lOutputDir,
            Result.fOutputUnresolvedReason);
        if lOutputDir <> '' then
          Result.fOutputPath := TPath.Combine(lOutputDir, lOutputFileName);
      end else if MatchText(aPlatform, ['Android', 'Android64']) then
      begin
        // The static package lands next to the .dcp files, not in DCC_BplOutput.
        if not lProps.TryGetValue('DCC_DcpOutput', lOutputValue) or (Trim(lOutputValue) = '') then
          Result.fOutputUnresolvedReason := 'the Android package output directory is unknown: DCC_DcpOutput is empty'
        else if TryResolveProjectDirectory(lOutputValue, Result.fProjectDir, 'DCC_DcpOutput', lPackageDir,
          Result.fOutputUnresolvedReason) then
          Result.fOutputPath := TPath.Combine(lPackageDir, lOutputFileName);
      end else if TryResolvePackageOutputDir(lProps, Result.fProjectDir, lPackageDir,
        Result.fOutputUnresolvedReason) then
        Result.fOutputPath := TPath.Combine(lPackageDir, lOutputFileName);
    end;

    lProps.TryGetValue('DCC_Define', Result.fDefines);
    Result.fDefines := MergeSemicolonValues(aBuildDefines, Result.fDefines);
    lProps.TryGetValue('DCC_UnitSearchPath', Result.fUnitSearchPath);
    Result.fUnitSearchPath := MergeSemicolonValues(aBuildUnitSearchPath, Result.fUnitSearchPath);

    if not FileExists(Result.fMainSourcePath) then
      Result.fMadExceptReason := 'main-source-missing'
    else if not FileExists(Result.fMesPath) then
      Result.fMadExceptReason := 'mes-missing'
    else if not SameText(TPath.GetFileNameWithoutExtension(Result.fMainSourcePath), Result.fProjectName) then
      Result.fMadExceptReason := 'name-mismatch'
    else if not HasMadExceptDefine(Result.fDefines) then
      Result.fMadExceptReason := 'define-missing'
    else if MesFileDisablesMadExcept(Result.fMesPath) then
      Result.fMadExceptReason := 'mes-disabled'
    else if not MatchText(aPlatform, ['Win32', 'Win64']) then
      // madExceptPatch patches Windows binaries; the resolved output of another platform is an ELF, .so or .a.
      Result.fMadExceptReason := 'platform-not-windows'
    else
    begin
      Result.fMadExceptRequired := True;
      Result.fMadExceptReason := 'enabled';
    end;
  finally
    if Assigned(lProps) then
      lProps.Free;
  end;
end;

function ResolveMadExceptPatchExe(const aSettingPath: string): string;
var
  lCandidate: string;
  lPathCandidate: string;
  lPathItem: string;
begin
  Result := '';

  if Trim(aSettingPath) <> '' then
  begin
    if SameText(TPath.GetExtension(aSettingPath), '.exe') then
      lCandidate := aSettingPath
    else
      lCandidate := TPath.Combine(aSettingPath, cMadExceptPatchExeName);
    if FileExists(lCandidate) then
      Exit(TPath.GetFullPath(lCandidate));
  end;

  for lPathItem in GetEnvironmentVariable('PATH').Split([';']) do
  begin
    lPathCandidate := Trim(lPathItem);
    if lPathCandidate = '' then
      Continue;
    lCandidate := TPath.Combine(lPathCandidate, cMadExceptPatchExeName);
    if FileExists(lCandidate) then
      Exit(TPath.GetFullPath(lCandidate));
  end;

  for lCandidate in [
    TPath.Combine(GetEnvironmentVariable('ProgramFiles'), 'madCollection\madExcept\Tools\' + cMadExceptPatchExeName),
    TPath.Combine(GetEnvironmentVariable('ProgramFiles'), 'madCollection\madExcept\tools\' + cMadExceptPatchExeName),
    TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'),
      'madCollection\madExcept\Tools\' + cMadExceptPatchExeName),
    TPath.Combine(GetEnvironmentVariable('ProgramFiles(x86)'),
      'madCollection\madExcept\tools\' + cMadExceptPatchExeName),
    TPath.Combine(GetEnvironmentVariable('ProgramData'), 'madCollection\madExcept\Tools\' + cMadExceptPatchExeName),
    TPath.Combine(GetEnvironmentVariable('ProgramData'), 'madCollection\madExcept\tools\' + cMadExceptPatchExeName)
  ] do
    if (lCandidate <> '') and FileExists(lCandidate) then
      Exit(TPath.GetFullPath(lCandidate));
end;

function TryFindExecutableInPath(const aExeName: string; out aExePath: string): Boolean;
var
  lFilePart: PChar;
  lLength: Cardinal;
  lBuffer: TArray<Char>;
begin
  aExePath := '';
  lFilePart := nil;
  lLength := SearchPath(nil, PChar(aExeName), nil, 0, nil, lFilePart);
  if lLength = 0 then
    Exit(False);
  SetLength(lBuffer, lLength);
  if SearchPath(nil, PChar(aExeName), nil, lLength, PChar(lBuffer), lFilePart) = 0 then
    Exit(False);
  aExePath := string(PChar(lBuffer));
  Result := aExePath <> '';
end;

function NormalizeOptionalPath(const aInputPath: string; out aNormalizedPath: string): Boolean;
var
  lError: string;
begin
  aNormalizedPath := '';
  if Trim(aInputPath) = '' then
    Exit(False);
  if not TryNormalizeInputPath(aInputPath, aNormalizedPath, lError) then
    Exit(False);
  aNormalizedPath := TPath.GetFullPath(aNormalizedPath);
  Result := True;
end;

function ResolveWebCoreCompilerPath(const aOptions: TAppOptions; const aSettings: TDakBuildSettings;
  out aCompilerPath: string): Boolean;
var
  lCandidatePath: string;
begin
  aCompilerPath := '';

  if aOptions.fHasWebCoreCompilerPath and NormalizeOptionalPath(aOptions.fWebCoreCompilerPath, lCandidatePath) and
    FileExists(lCandidatePath) then
  begin
    aCompilerPath := lCandidatePath;
    Exit(True);
  end;

  if NormalizeOptionalPath(aSettings.fWebCoreCompilerPath, lCandidatePath) and FileExists(lCandidatePath) then
  begin
    aCompilerPath := lCandidatePath;
    Exit(True);
  end;

  if NormalizeOptionalPath(GetEnvironmentVariable(cWebCoreCompilerEnvVar), lCandidatePath) and FileExists(lCandidatePath) then
  begin
    aCompilerPath := lCandidatePath;
    Exit(True);
  end;

  if TryFindExecutableInPath(cTmsWebCompilerExeName, lCandidatePath) then
  begin
    aCompilerPath := TPath.GetFullPath(lCandidatePath);
    Exit(True);
  end;

  Result := False;
end;

function TryFindMsBuildFromRegistry(out aMsBuildPath: string): Boolean;
const
  CRegistryKeys: array [0 .. 4] of string = (
    'SOFTWARE\Microsoft\MSBuild\ToolsVersions\Current',
    'SOFTWARE\Microsoft\MSBuild\ToolsVersions\17.0',
    'SOFTWARE\Microsoft\MSBuild\ToolsVersions\16.0',
    'SOFTWARE\Microsoft\MSBuild\ToolsVersions\15.0',
    'SOFTWARE\Microsoft\MSBuild\ToolsVersions\14.0'
  );
  CRegistryViews: array [0 .. 1] of Cardinal = (
    KEY_WOW64_64KEY,
    KEY_WOW64_32KEY
  );
var
  lCandidatePath: string;
  lKey: string;
  lKeyIndex: Integer;
  lRegistry: TRegistry;
  lToolsPath: string;
  lViewIndex: Integer;
begin
  aMsBuildPath := '';
  for lViewIndex := Low(CRegistryViews) to High(CRegistryViews) do
  begin
    lRegistry := TRegistry.Create(KEY_READ or CRegistryViews[lViewIndex]);
    try
      lRegistry.RootKey := HKEY_LOCAL_MACHINE;
      for lKeyIndex := Low(CRegistryKeys) to High(CRegistryKeys) do
      begin
        lKey := CRegistryKeys[lKeyIndex];
        if not lRegistry.OpenKeyReadOnly(lKey) then
          Continue;
        try
          if lRegistry.ValueExists('MSBuildToolsPath') then
            lToolsPath := Trim(lRegistry.ReadString('MSBuildToolsPath'))
          else
            lToolsPath := '';
        finally
          lRegistry.CloseKey;
        end;
        if lToolsPath = '' then
          Continue;
        lCandidatePath := TPath.Combine(lToolsPath, 'MSBuild.exe');
        if FileExists(lCandidatePath) then
        begin
          aMsBuildPath := TPath.GetFullPath(lCandidatePath);
          Exit(True);
        end;
      end;
    finally
      lRegistry.Free;
    end;
  end;
  Result := False;
end;

function TryFindMsBuild(const aBdsRoot: string; out aMsBuildPath: string): Boolean;
var
  lCandidate: string;
begin
  aMsBuildPath := '';

  lCandidate := TPath.Combine(aBdsRoot, 'bin\msbuild.exe');
  if FileExists(lCandidate) then
  begin
    aMsBuildPath := lCandidate;
    Exit(True);
  end;

  if TryFindExecutableInPath('MSBuild.exe', lCandidate) then
  begin
    aMsBuildPath := TPath.GetFullPath(lCandidate);
    Exit(True);
  end;

  if TryFindMsBuildFromRegistry(lCandidate) then
  begin
    aMsBuildPath := lCandidate;
    Exit(True);
  end;

  lCandidate := TPath.Combine(GetEnvironmentVariable('WINDIR'), 'Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe');
  if FileExists(lCandidate) then
  begin
    aMsBuildPath := lCandidate;
    Exit(True);
  end;

  lCandidate := TPath.Combine(GetEnvironmentVariable('WINDIR'), 'Microsoft.NET\Framework\v4.0.30319\MSBuild.exe');
  if FileExists(lCandidate) then
  begin
    aMsBuildPath := lCandidate;
    Exit(True);
  end;

  Result := False;
end;

function BuildMsBuildSelectionProperties(const aOptions: TAppOptions): TArray<TMsBuildProperty>;
begin
  Result := nil;
  AddMsBuildProperty(Result, 'Config', aOptions.fConfig, TMsBuildPropertyOrigin.poOption);
  AddMsBuildProperty(Result, 'Platform', aOptions.fPlatform, TMsBuildPropertyOrigin.poOption);
end;

// The properties whose values come from the caller or the machine, in the order they follow the fixed switches.
function BuildMsBuildOverrideProperties(const aOptions: TAppOptions; const aProjectInfo: TBuildProjectInfo;
  const aEnvProps: TArray<TMsBuildProperty>): TArray<TMsBuildProperty>;
var
  lOutputDir: string;
begin
  Result := nil;
  if aOptions.fHasBuildTestOutputDir then
  begin
    // Already a validated full path (NormalizeBuildOptions), so nothing here can raise.
    lOutputDir := aOptions.fBuildTestOutputDir;
    AddMsBuildProperty(Result, 'DCC_ExeOutput', lOutputDir, TMsBuildPropertyOrigin.poOption);
    // DAK-375: unit output is a build artifact too. DCC_DcuOutput is the compiler's property (the retired
    // wrapper's DCC_UnitOutputDirectory was ignored); DCC_ObjOutput follows it so .o/.obj files move as well.
    AddMsBuildProperty(Result, 'DCC_DcuOutput', TPath.Combine(lOutputDir, 'dcu'), TMsBuildPropertyOrigin.poOption);
    AddMsBuildProperty(Result, 'DCC_ObjOutput', TPath.Combine(lOutputDir, 'dcu'), TMsBuildPropertyOrigin.poOption);
    AddMsBuildProperty(Result, 'DCC_BplOutput', lOutputDir, TMsBuildPropertyOrigin.poOption);
    AddMsBuildProperty(Result, 'DCC_DcpOutput', lOutputDir, TMsBuildPropertyOrigin.poOption);
    // DAK-382: C++ headers are unit-derived output and follow the DCUs; the package interface (.bpi) follows the
    // .dcp files. Both default to a project or machine folder (CodeGear.Delphi.Targets l.59-60), and DCC_BpiOutput
    // only follows DCC_DcpOutput when the project leaves it empty.
    AddMsBuildProperty(Result, 'DCC_HppOutput', TPath.Combine(lOutputDir, 'dcu'), TMsBuildPropertyOrigin.poOption);
    AddMsBuildProperty(Result, 'DCC_BpiOutput', lOutputDir, TMsBuildPropertyOrigin.poOption);
  end;

  Result := Result + aEnvProps;

  if aOptions.fHasBuildDefines and (Trim(aProjectInfo.fDefines) <> '') then
    AddMsBuildProperty(Result, 'DCC_Define', Trim(aProjectInfo.fDefines), TMsBuildPropertyOrigin.poOption);
  if aOptions.fHasBuildUnitSearchPath and (Trim(aProjectInfo.fUnitSearchPath) <> '') then
    AddMsBuildProperty(Result, 'DCC_UnitSearchPath', Trim(aProjectInfo.fUnitSearchPath),
      TMsBuildPropertyOrigin.poOption);
end;

function BuildMsBuildArguments(const aOptions: TAppOptions; const aProjectInfo: TBuildProjectInfo;
  const aOverrideProps: TArray<TMsBuildProperty>; aView: TMsBuildArgumentsView): string;
begin
  Result := QuoteCmdArg(aProjectInfo.fProjectPath) +
    ' /t:' + aOptions.fBuildTarget +
    RenderMsBuildProperties(BuildMsBuildSelectionProperties(aOptions), aView) +
    ' /p:DCC_Quiet=true /p:DCC_UseMSBuildExternally=true /p:DCC_UseResponseFile=1 /p:DCC_UseCommandFile=1 /nologo /v:m /fl /m' +
    RenderMsBuildProperties(aOverrideProps, aView);

  if (aView = TMsBuildArgumentsView.avTrace) and (Length(Result) > cMsBuildTraceMaxLength) then
    Result := Copy(Result, 1, cMsBuildTraceMaxLength) + cMsBuildTraceTruncated;
end;

// MSBuild words MSB1006 in the user's language, so only the error code and the layout are used: the first
// non-empty line after the error repeats the rejected text after a label and a colon.
function TryReadMsBuildRejectedSwitch(const aLogPath: string; out aRejectedText: string): Boolean;
var
  lErrorSeen: Boolean;
  lLine: string;
  lLineCount: Integer;
  lPos: Integer;
  lReader: TStreamReader;
begin
  aRejectedText := '';
  if (aLogPath = '') or (not FileExists(aLogPath)) then
    Exit(False);

  lReader := TStreamReader.Create(aLogPath, TEncoding.Default, True);
  try
    lErrorSeen := False;
    lLineCount := 0;
    // MSBuild rejects the command line before it builds anything, so the error leads the log.
    while (not lReader.EndOfStream) and (lLineCount < cMsBuildRejectedSwitchScanLines) do
    begin
      lLine := Trim(lReader.ReadLine);
      Inc(lLineCount);
      if lLine = '' then
        Continue;
      if lErrorSeen then
      begin
        lPos := Pos(':', lLine);
        if lPos > 0 then
          aRejectedText := Trim(Copy(lLine, lPos + 1, MaxInt));
        Break;
      end;
      lErrorSeen := ContainsText(lLine, cMsBuildInvalidPropertyError);
    end;
  finally
    lReader.Free;
  end;
  Result := aRejectedText <> '';
end;

// MSBuild reports the piece it could not read as a property, which is one ';' or ',' separated part of a
// generated value. That text can be part of a secret, so we report only the names of the properties it fits.
function DescribeMsBuildPropertyRejection(const aProperties: TArray<TMsBuildProperty>;
  const aRejectedText: string): string;
var
  lNames: string;
  lPart: string;
  lProperty: TMsBuildProperty;
begin
  lNames := '';
  if aRejectedText <> '' then
    for lProperty in aProperties do
      for lPart in lProperty.fValue.Split([';', ',']) do
        if SameStr(Trim(lPart), aRejectedText) then
        begin
          if lNames <> '' then
            lNames := lNames + ', ';
          lNames := lNames + '/p:' + lProperty.fName;
          if lProperty.fOrigin = TMsBuildPropertyOrigin.poEnvironmentProj then
            lNames := lNames + ' (' + cMsBuildOriginEnvironmentProj + ')'
          else
            lNames := lNames + ' (' + cMsBuildOriginOption + ')';
          Break;
        end;

  if lNames = '' then
    Exit(cMsBuildRejectedUnknownMessage);
  Result := Format(cMsBuildRejectedPropertyMessage, [lNames]);
end;

procedure AnnotateMsBuildPropertyRejection(const aOutLogPath, aErrLogPath: string;
  const aProperties: TArray<TMsBuildProperty>; var aSummary: TBuildSummary);
var
  i: Integer;
  lRejectedText: string;
begin
  for i := 0 to High(aSummary.fErrors) do
    if ContainsText(aSummary.fErrors[i], cMsBuildInvalidPropertyError) then
    begin
      // Without the rejected text the description says that the property could not be identified.
      if (not TryReadMsBuildRejectedSwitch(aOutLogPath, lRejectedText)) and
        (not TryReadMsBuildRejectedSwitch(aErrLogPath, lRejectedText)) then
        lRejectedText := '';
      aSummary.fErrors[i] := aSummary.fErrors[i] + sLineBreak +
        DescribeMsBuildPropertyRejection(aProperties, lRejectedText);
      Exit;
    end;
end;

function FileUtcTicks(const aPath: string): Int64;
var
  lFileTime: Int64;
  lHandle: THandle;
  lInfo: TByHandleFileInformation;
begin
  Result := 0;
  if not FileExists(aPath) then
    Exit;

  lHandle := CreateFile(PChar(aPath), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if lHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    if GetFileInformationByHandle(lHandle, lInfo) then
    begin
      lFileTime := lInfo.ftLastWriteTime.dwHighDateTime;
      lFileTime := (lFileTime shl 32) or lInfo.ftLastWriteTime.dwLowDateTime;
      Result := lFileTime;
    end;
  finally
    CloseHandle(lHandle);
  end;
end;

function BuildMadExceptMissingDcuGuidance(const aErrors: TArray<string>): string; forward;
procedure PrintPostBuildDfmCheckNotes(const aOptions: TAppOptions; const aSummary: TBuildSummary;
  const aSourceBuildFailed: Boolean); forward;

procedure PrintLogRetention(const aLogRetention: TBuildLogRetention; const aErrorPrefix: string);
begin
  // The failure message names the directory; a "kept" line next to it would claim a success.
  if aLogRetention.fError <> '' then
    Writeln(aErrorPrefix + aLogRetention.fError)
  else if aLogRetention.fRunDir <> '' then
    Writeln(Format(cBuildLogsKept, [aLogRetention.fRunDir]));
end;

procedure PrintSummary(const aOptions: TAppOptions; const aProjectInfo: TBuildProjectInfo;
  const aSummary: TBuildSummary; const aSourceBuildFailed: Boolean; const aLogRetention: TBuildLogRetention);
var
  lLine: string;
begin
  if aOptions.fBuildQuiet then
    Exit;

  if aOptions.fBuildJson then
    Exit;

  if aOptions.fBuildAi then
  begin
    if aSummary.fTimedOut then
      Writeln('FAILED. Build timed out after ' + IntToStr(aOptions.fBuildTimeoutSec) + 's.')
    else if aSummary.fExitCode <> 0 then
      Writeln('FAILED. Errors: ' + IntToStr(aSummary.fErrorCount))
    else if aSummary.fWarningCount > 0 then
      Writeln('SUCCESS. Warnings: ' + IntToStr(aSummary.fWarningCount))
    else if aSummary.fHintCount > 0 then
      Writeln('SUCCESS. Hints: ' + IntToStr(aSummary.fHintCount))
    else
      Writeln('SUCCESS.');

    for lLine in aSummary.fErrors do
      Writeln(lLine);
    if aOptions.fBuildShowWarnings then
      for lLine in aSummary.fWarnings do
        Writeln(lLine);
    if aOptions.fBuildShowHints then
      for lLine in aSummary.fHints do
        Writeln(lLine);
    if aSummary.fOutputStale and (aSummary.fOutputMessage <> '') then
      Writeln('WARNING. ' + aSummary.fOutputMessage);
    if (not aSummary.fOutputStale) and (aSummary.fOutputMessage <> '') then
    begin
      if aSummary.fExitCode = 0 then
        Writeln('NOTE. ' + aSummary.fOutputMessage)
      else
        Writeln('ERROR. ' + aSummary.fOutputMessage);
    end;
    PrintLogRetention(aLogRetention, 'ERROR. ');
    PrintPostBuildDfmCheckNotes(aOptions, aSummary, aSourceBuildFailed);
    Exit;
  end;

  if aSummary.fExitCode <> 0 then
    Writeln('Build FAILED.')
  else if aProjectInfo.fOutputPath = '' then
    // DAK-374: the name is unresolved; the output message below says why.
    Writeln('Build succeeded.')
  else
    Writeln('Build succeeded: ' + aProjectInfo.fOutputPath);

  for lLine in aSummary.fErrors do
    Writeln(lLine);
  if aOptions.fBuildShowWarnings then
    for lLine in aSummary.fWarnings do
      Writeln(lLine);
  if aOptions.fBuildShowHints then
    for lLine in aSummary.fHints do
      Writeln(lLine);
  if aSummary.fOutputStale and (aSummary.fOutputMessage <> '') then
    Writeln(aSummary.fOutputMessage);
  if (not aSummary.fOutputStale) and (aSummary.fOutputMessage <> '') then
    Writeln(aSummary.fOutputMessage);
  PrintLogRetention(aLogRetention, '');
  PrintPostBuildDfmCheckNotes(aOptions, aSummary, aSourceBuildFailed);
end;

function CurrentTicks: Int64;
begin
  Result := GetTickCount64;
end;

procedure PrintVerboseStep(const aOptions: TAppOptions; const aStep: string);
var
  lTracePath: string;
begin
  if aOptions.fVerbose and (not aOptions.fBuildQuiet) then
  begin
    Writeln(ErrOutput, '[build] ' + aStep);
    // A line longer than the text buffer is written in pieces; flush so a verbose line is never left
    // half-buffered while later stdout/stderr output reaches a shared pipe first (DAK-372).
    Flush(ErrOutput);
  end;
  lTracePath := Trim(GetEnvironmentVariable('DAK_TRACE_BUILD'));
  if lTracePath <> '' then
    TFile.AppendAllText(lTracePath, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' ' + aStep + sLineBreak,
      TEncoding.UTF8);
end;

function ContainsTextCI(const aItems: TArray<string>; const aValue: string): Boolean;
var
  lItem: string;
begin
  Result := False;
  for lItem in aItems do
    if SameText(Trim(lItem), aValue) then
      Exit(True);
end;

function BuildMadExceptMissingDcuGuidance(const aErrors: TArray<string>): string;
var
  lError: string;
begin
  for lError in aErrors do
    if ContainsText(lError, 'madExcept.dcu') and ContainsText(lError, 'File not found') then
      Exit('HINT. madExcept is enabled by DCC_Define; restore the madExcept install/library path for this ' +
        'Delphi platform/config, or disable that define only for builds that do not compile madExcept-aware code.');
  Result := '';
end;

procedure PrintPostBuildDfmCheckNotes(const aOptions: TAppOptions; const aSummary: TBuildSummary;
  const aSourceBuildFailed: Boolean);
var
  lGuidance: string;
begin
  if aOptions.fBuildRunDfmCheck and aSourceBuildFailed then
    Writeln('NOTE. dfm-check was not run because the source build failed.');

  lGuidance := BuildMadExceptMissingDcuGuidance(aSummary.fErrors);
  if lGuidance <> '' then
    Writeln(lGuidance);
end;

procedure EmitBuildPreflightWarnings(const aOptions: TAppOptions; const aEnvVars: TDictionary<string, string>);
var
  lError: string;
  lErrorCode: Integer;
  lLibraryPath: string;
  lLibrarySource: TPropertySource;
  lParams: TFixInsightParams;
  lPair: TPair<string, string>;
  lPreflightEnvVars: TDictionary<string, string>;
begin
  if aOptions.fBuildQuiet then
    Exit;

  if not SameText(Trim(aOptions.fPlatform), 'Win64') then
    Exit;

  lPreflightEnvVars := nil;
  try
    if not TryReadIdeConfig(aOptions.fDelphiVersion, aOptions.fPlatform, aOptions.fEnvOptionsPath, aEnvVars,
      lPreflightEnvVars, lLibraryPath, lLibrarySource, nil, lError) then
    begin
      if aOptions.fVerbose and (Trim(lError) <> '') then
        Writeln('NOTE. ' + Format(SBuildPreflightSkipped, [lError]));
      Exit;
    end;

    if aEnvVars <> nil then
      for lPair in aEnvVars do
        lPreflightEnvVars.AddOrSetValue(lPair.Key, lPair.Value);

    if not TryBuildParams(aOptions, lPreflightEnvVars, lLibraryPath, lLibrarySource, nil, lParams, lError, lErrorCode)
    then
    begin
      if aOptions.fVerbose and (Trim(lError) <> '') then
        Writeln('NOTE. ' + Format(SBuildPreflightSkipped, [lError]));
      Exit;
    end;

    if not ContainsTextCI(lParams.fUnitScopes, 'Winapi') then
      Writeln('WARNING. ' + Format(SBuildWarningMissingWinapiNamespace, [aOptions.fDprojPath, aOptions.fPlatform]));
  finally
    lPreflightEnvVars.Free;
  end;
end;

function TBuildProcessRunner.RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
  const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
  out aTimedOut: Boolean; out aError: string): Boolean;
var
  lErrHandle: THandle;
  lOutHandle: THandle;
  lProcExitCode: Cardinal;
  lRunOptions: TExternalToolProcessRunOptions;
  lRunTimedOut: Boolean;
  lSa: TSecurityAttributes;
begin
  Result := False;
  aExitCode := 1;
  aTimedOut := False;
  aError := '';
  lOutHandle := INVALID_HANDLE_VALUE;
  lErrHandle := INVALID_HANDLE_VALUE;

  FillChar(lSa, SizeOf(lSa), 0);
  lSa.nLength := SizeOf(lSa);
  lSa.bInheritHandle := True;

  lOutHandle := CreateFile(PChar(aStdOutPath), GENERIC_WRITE, FILE_SHARE_READ, @lSa, CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0);
  if lOutHandle = INVALID_HANDLE_VALUE then
  begin
    aError := 'Failed to create stdout log.';
    Exit(False);
  end;

  lErrHandle := CreateFile(PChar(aStdErrPath), GENERIC_WRITE, FILE_SHARE_READ, @lSa, CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0);
  if lErrHandle = INVALID_HANDLE_VALUE then
  begin
    aError := 'Failed to create stderr log.';
    Exit(False);
  end;

  try
    lRunOptions := Default(TExternalToolProcessRunOptions);
    lRunOptions.fApplicationName := aExePath;
    lRunOptions.fExePath := aExePath;
    lRunOptions.fArguments := aArguments;
    lRunOptions.fWorkDir := aWorkDir;
    lRunOptions.fEnvironmentBlock := aEnvironmentBlock;
    lRunOptions.fToolName := ExtractFileName(aExePath);
    lRunOptions.fStdInHandle := GetStdHandle(STD_INPUT_HANDLE);
    lRunOptions.fStdOutHandle := lOutHandle;
    lRunOptions.fStdErrHandle := lErrHandle;
    lRunOptions.fCreationFlags := CREATE_NO_WINDOW;
    lRunOptions.fTimeoutSec := aTimeoutSec;
    lRunOptions.fTimeoutExitCode := 124;

    if not TryRunExternalToolProcess(lRunOptions, lProcExitCode, lRunTimedOut, aError) then
    begin
      aTimedOut := lRunTimedOut;
      if aTimedOut then
      begin
        aExitCode := Integer(lProcExitCode);
        aError := '';
        Exit(True);
      end;
      Exit(False);
    end;
    aExitCode := Integer(lProcExitCode);
  finally
    if lErrHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(lErrHandle);
    if lOutHandle <> INVALID_HANDLE_VALUE then
      CloseHandle(lOutHandle);
  end;

  Result := True;
end;

function ResolveDetectedBuildBackend(const aOptions: TAppOptions; out aBuildBackend: TBuildBackend;
  out aError: string): Boolean;
var
  lDetectionError: string;
  lWebCoreInfo: TWebCoreProjectInfo;
begin
  aError := '';
  if aOptions.fBuildBackend <> TBuildBackend.bbAuto then
  begin
    aBuildBackend := aOptions.fBuildBackend;
    Exit(True);
  end;

  lDetectionError := '';
  if not TryReadWebCoreProjectInfo(aOptions.fDprojPath, aOptions.fConfig, aOptions.fPlatform, nil, lWebCoreInfo,
    lDetectionError) then
  begin
    aBuildBackend := TBuildBackend.bbDelphi;
    Exit(True);
  end;

  if lWebCoreInfo.fIsWebCore then
    aBuildBackend := TBuildBackend.bbWebCore
  else
    aBuildBackend := TBuildBackend.bbDelphi;
  Result := True;
end;

function ResolveWebCorePwaEnabled(const aOptions: TAppOptions; const aProjectInfo: TWebCoreProjectInfo): Boolean;
begin
  if aOptions.fHasWebCorePwaEnabled then
    Exit(aOptions.fWebCorePwaEnabled);
  Result := aProjectInfo.fPwaEnabled;
end;

function BuildWebCoreArguments(const aOptions: TAppOptions; const aProjectInfo: TWebCoreProjectInfo): string;
begin
  Result := '/ParseDprojFile ' +
    '/ProjectFile:' + QuoteCmdArg(aProjectInfo.fProjectPath) + ' ' +
    '/Config:' + QuoteCmdArg(aOptions.fConfig);
  if ResolveWebCorePwaEnabled(aOptions, aProjectInfo) then
    Result := Result + ' /PWA';
end;

function ResolvePowerShellExe: string;
var
  lCandidate: string;
begin
  lCandidate := TPath.Combine(GetEnvironmentVariable('WINDIR'), 'System32\WindowsPowerShell\v1.0\powershell.exe');
  if (lCandidate <> '') and FileExists(lCandidate) then
    Exit(lCandidate);
  Result := 'powershell.exe';
end;

procedure EmitWebCoreHookWarning(const aMessage: string);
begin
  Writeln(ErrOutput, 'WARNING. ' + aMessage);
end;

procedure PreserveBuildDiagnosticLog(const aDiagnosticsDir, aSourcePath, aTargetName: string);
var
  lDiagnosticsDir: string;
  lTargetPath: string;
begin
  lDiagnosticsDir := Trim(aDiagnosticsDir);
  if lDiagnosticsDir = '' then
    lDiagnosticsDir := Trim(GetEnvironmentVariable(cBuildDiagnosticsDirEnvVar));
  if (lDiagnosticsDir = '') or (aSourcePath = '') or (not FileExists(aSourcePath)) then
    Exit;

  // Callers such as remove-with verification place diagnostics deep inside the project's .dak
  // workspace, where the log path can pass MAX_PATH (T-263).
  lDiagnosticsDir := LongPathSafe(lDiagnosticsDir);
  TDirectory.CreateDirectory(lDiagnosticsDir);
  lTargetPath := TPath.Combine(lDiagnosticsDir, aTargetName);
  TFile.Copy(aSourcePath, lTargetPath, True);
end;

// DAK-379: <log root>\run-<guid>. The root is the project's .dak build folder, or --log-dir: relative to the
// project directory (never the working directory), or absolute. The GUID keeps concurrent builds apart.
// A root such as `\logs` or `D:logs` depends on the working directory's drive or directory, not on the project.
function IsDriveRelativePath(const aPath: string): Boolean;
begin
  Result := ((Length(aPath) >= 1) and (aPath[1] = '\') and ((Length(aPath) = 1) or (aPath[2] <> '\'))) or
    ((Length(aPath) >= 2) and (aPath[2] = ':') and ((Length(aPath) = 2) or (not CharInSet(aPath[3], ['\', '/']))));
end;

// The RTL ForceDirectories fails when a concurrent build creates a shared parent first. A directory that
// exists afterwards is what we need, whoever made it.
function EnsureDirectoryExists(const aPath: string): Boolean;
var
  lParent: string;
begin
  if DirectoryExists(aPath) then
    Exit(True);
  lParent := ExtractFileDir(ExcludeTrailingPathDelimiter(aPath));
  if (lParent <> '') and (Length(lParent) < Length(aPath)) and (not DirectoryExists(lParent)) then
    EnsureDirectoryExists(lParent);
  Result := CreateDir(aPath) or DirectoryExists(aPath);
end;

function EnsureDirectoryExistsWithRetry(const aPath: string): Boolean;
var
  lAttempt: Integer;
begin
  Result := False;
  for lAttempt := 1 to cBuildLogsCreateAttempts do
  begin
    if EnsureDirectoryExists(aPath) then
      Exit(True);
    Sleep(10 * lAttempt);
  end;
end;

function TryCreateBuildLogRunDir(const aOptions: TAppOptions; out aRunDir: string; out aError: string): Boolean;
var
  lError: string;
  lGuid: TGUID;
  lLogDir: string;
  lNormalizedDir: string;
  lRoot: string;
  lRunDir: string;
begin
  aRunDir := '';
  aError := '';
  lRunDir := '';
  try
    lLogDir := Trim(aOptions.fBuildLogDir);
    if lLogDir = '' then
      lRoot := DakProjectPath(DakProjectRootForProjectPath(aOptions.fDprojPath), ['build'])
    else
    begin
      if not TryNormalizeInputPath(lLogDir, lNormalizedDir, lError) then
      begin
        aError := Format(cBuildLogsRootUnusable, [aOptions.fBuildLogDir, lError]);
        Exit(False);
      end;
      if IsDriveRelativePath(lNormalizedDir) then
      begin
        aError := Format(cBuildLogsRootUnusable, [aOptions.fBuildLogDir, cBuildLogsDriveRelative]);
        Exit(False);
      end;
      lRoot := TPath.GetFullPath(TPath.Combine(ExtractFilePath(aOptions.fDprojPath), lNormalizedDir));
    end;

    CreateGUID(lGuid);
    lRunDir := TPath.Combine(lRoot, cBuildLogsRunDirPrefix + Copy(GUIDToString(lGuid), 2, 36));
    // The long-path form only matters for creation; the plain path is what we report.
    if not EnsureDirectoryExistsWithRetry(LongPathSafe(lRoot)) then
      raise EInOutError.Create(SysErrorMessage(GetLastError));
    // The GUID makes the run directory ours alone, so failing to create it is a real failure.
    if not CreateDir(LongPathSafe(lRunDir)) then
      raise EInOutError.Create(SysErrorMessage(GetLastError));
  except
    on E: Exception do
    begin
      if lRunDir = '' then
        lRunDir := aOptions.fBuildLogDir;
      aError := Format(cBuildLogsDirCreateFailed, [lRunDir, E.Message]);
      Exit(False);
    end;
  end;
  aRunDir := lRunDir;
  Result := True;
end;

// Only an empty directory goes: RemoveDir fails on a directory that holds anything, so kept files are safe.
procedure RemoveEmptyRunDir(const aRunDir: string);
begin
  if aRunDir = '' then
    Exit;
  // A failed removal leaves an empty directory behind; the failure being reported matters more.
  RemoveDir(LongPathSafe(aRunDir));
end;

procedure RetainBuildLog(const aRunDir, aSourcePath, aTargetName: string);
begin
  // The shared copier skips a missing source; a requested log that is missing must not vanish quietly.
  if not FileExists(aSourcePath) then
    raise EFileNotFoundException.CreateFmt(cBuildLogMissing, [aTargetName]);
  PreserveBuildDiagnosticLog(aRunDir, aSourcePath, aTargetName);
end;

// Runs once the build process has ended, so the files are complete. A failure is recorded, never raised: the
// caller still owes the build result.
procedure RetainBuildLogs(var aLogRetention: TBuildLogRetention; const aOutLog, aErrLog: string);
var
  lCurrentLog: string;
begin
  if aLogRetention.fRunDir = '' then
    Exit;
  lCurrentLog := 'stdout.log';
  try
    RetainBuildLog(aLogRetention.fRunDir, aOutLog, lCurrentLog);
    lCurrentLog := 'stderr.log';
    RetainBuildLog(aLogRetention.fRunDir, aErrLog, lCurrentLog);
  except
    on E: Exception do
      aLogRetention.fError := Format(cBuildLogsCopyFailed, [lCurrentLog, aLogRetention.fRunDir, E.Message]);
  end;
end;

procedure RunWebCorePatchHook(const aRunner: IBuildProcessRunner; const aProjectInfo: TWebCoreProjectInfo;
  const aOptions: TAppOptions);
var
  lArguments: string;
  lError: string;
  lErrLog: string;
  lExitCode: Integer;
  lOutLog: string;
  lTempBase: string;
  lTimedOut: Boolean;
begin
  if not SameText(Trim(aOptions.fConfig), 'Debug') then
    Exit;

  if not FileExists(aProjectInfo.fPatchIndexDebugPath) then
    Exit;

  lTempBase := TPath.Combine(TPath.GetTempPath,
    'dak-webcore-hook-' + IntToStr(GetCurrentProcessId) + '-' + IntToStr(GetTickCount));
  lOutLog := lTempBase + '.out.log';
  lErrLog := lTempBase + '.err.log';
  lArguments :=
    '-NoProfile -ExecutionPolicy Bypass -File ' + QuoteCmdArg(aProjectInfo.fPatchIndexDebugPath) +
    ' -ProjectDir ' + QuoteCmdArg(aProjectInfo.fProjectDir) +
    ' -Config ' + QuoteCmdArg(aOptions.fConfig) +
    ' -ProjectName ' + QuoteCmdArg(aProjectInfo.fProjectName);

  lError := '';
  if not aRunner.RunProcess(ResolvePowerShellExe(), lArguments, aProjectInfo.fProjectDir, lOutLog, lErrLog, '',
    aOptions.fBuildTimeoutSec, lExitCode, lTimedOut, lError) then
  begin
    EmitWebCoreHookWarning('patch-index-debug.ps1 failed to start: ' + lError);
    Exit;
  end;

  if lTimedOut then
  begin
    EmitWebCoreHookWarning('patch-index-debug.ps1 timed out.');
    Exit;
  end;

  if lExitCode <> 0 then
    EmitWebCoreHookWarning('patch-index-debug.ps1 exited with code ' + IntToStr(lExitCode) + '.');
end;

function TryRunWebCoreBuild(const aOptions: TAppOptions; const aRunner: IBuildProcessRunner;
  const aSettings: TDakBuildSettings; out aExitCode: Integer; out aError: string): Boolean;
var
  lCompilerPath: string;
  lErrLog: string;
  lOutLog: string;
  lProjectInfo: TBuildProjectInfo;
  lSummaryOptions: TBuildSummaryOptions;
  lStartTick: UInt64;
  lSummary: TBuildSummary;
  lTempBase: string;
  lTimeMs: Int64;
  lTimedOut: Boolean;
  lWebCoreInfo: TWebCoreProjectInfo;
begin
  Result := False;
  aExitCode := 1;
  aError := '';

  if not ResolveWebCoreCompilerPath(aOptions, aSettings, lCompilerPath) then
  begin
    aError := cWebCoreCompilerMissingMessage;
    Exit(False);
  end;

  if not TryReadWebCoreProjectInfo(aOptions.fDprojPath, aOptions.fConfig, aOptions.fPlatform, nil, lWebCoreInfo, aError) then
    Exit(False);

  lTempBase := TPath.Combine(TPath.GetTempPath,
    'dak-webcore-' + IntToStr(GetCurrentProcessId) + '-' + IntToStr(GetTickCount));
  lOutLog := lTempBase + '.out.log';
  lErrLog := lTempBase + '.err.log';
  lStartTick := GetTickCount64;

  if not aRunner.RunProcess(lCompilerPath, BuildWebCoreArguments(aOptions, lWebCoreInfo),
    lWebCoreInfo.fProjectDir, lOutLog, lErrLog, '', aOptions.fBuildTimeoutSec,
    aExitCode, lTimedOut, aError) then
    Exit(False);

  lTimeMs := Int64(GetTickCount64 - lStartTick);
  lSummaryOptions := Default(TBuildSummaryOptions);
  lSummaryOptions.fProjectRoot := lWebCoreInfo.fProjectDir;
  lSummaryOptions.fIgnoreWarnings := aSettings.fIgnoreWarnings;
  lSummaryOptions.fIgnoreHints := aSettings.fIgnoreHints;
  lSummaryOptions.fExcludePathMasks := aSettings.fExcludePathMasks;
  lSummaryOptions.fMaxFindings := aOptions.fBuildMaxFindings;
  lSummaryOptions.fIncludeWarnings := aOptions.fBuildShowWarnings;
  lSummaryOptions.fIncludeHints := aOptions.fBuildShowHints;
  lSummary := ParseBuildLogs(lOutLog, lErrLog, lSummaryOptions);
  lSummary.fExitCode := aExitCode;
  lSummary.fTimedOut := lTimedOut;
  lSummary.fOutputPath := lWebCoreInfo.fOutputPath;

  if lTimedOut then
    lSummary.fStatus := cStatusTimeout
  else if aExitCode <> 0 then
    lSummary.fStatus := cStatusError
  else if lSummary.fWarningCount > 0 then
      lSummary.fStatus := cStatusWarnings
  else if lSummary.fHintCount > 0 then
    lSummary.fStatus := cStatusHints
  else
    lSummary.fStatus := cStatusOk;

  if (aExitCode = 0) and (not lTimedOut) then
    RunWebCorePatchHook(aRunner, lWebCoreInfo, aOptions);

  lProjectInfo := Default(TBuildProjectInfo);
  lProjectInfo.fProjectPath := lWebCoreInfo.fProjectPath;
  lProjectInfo.fProjectDir := lWebCoreInfo.fProjectDir;
  lProjectInfo.fProjectName := lWebCoreInfo.fProjectName;
  lProjectInfo.fOutputPath := lWebCoreInfo.fOutputPath;

  if not aOptions.fBuildQuiet then
  begin
    if aOptions.fBuildJson then
      Writeln(BuildSummaryAsJson(lProjectInfo.fProjectPath, aOptions, lSummary, aOptions.fBuildTarget, lTimeMs))
    else
      PrintSummary(aOptions, lProjectInfo, lSummary, lSummary.fExitCode <> 0, Default(TBuildLogRetention));
  end;

  Result := True;
end;

function ValidateWebCoreBuildOptions(const aOptions: TAppOptions; out aError: string): Boolean;
begin
  aError := '';
  if aOptions.fBuildRunDfmCheck then
  begin
    aError := Format(SBuildOptionDelphiOnly, ['--dfmcheck']);
    Exit(False);
  end;

  if aOptions.fHasRsVarsPath then
  begin
    aError := Format(SBuildOptionDelphiOnly, ['--rsvars']);
    Exit(False);
  end;

  if aOptions.fHasEnvOptionsPath then
  begin
    aError := Format(SBuildOptionDelphiOnly, ['--envoptions']);
    Exit(False);
  end;

  if aOptions.fHasBuildDefines then
  begin
    aError := Format(SBuildOptionDelphiOnly, ['--define']);
    Exit(False);
  end;

  if aOptions.fHasBuildUnitSearchPath then
  begin
    aError := Format(SBuildOptionDelphiOnly, ['--unit-search-path']);
    Exit(False);
  end;

  if aOptions.fBuildKeepLogs then
  begin
    if Trim(aOptions.fBuildLogDir) <> '' then
      aError := Format(SBuildOptionDelphiOnly, ['--log-dir'])
    else
      aError := Format(SBuildOptionDelphiOnly, ['--keep-logs']);
    Exit(False);
  end;

  Result := True;
end;

// DAK-374: --test-output-dir is normalized once here, where a failure is a named error, and the full path is
// reused by BuildProjectInfo and BuildMsBuildOverrideProperties. A relative value keeps its meaning (relative to
// the working directory); a value such as `\out` or `D:out` depends on the working directory's drive and is
// rejected with the rule --log-dir uses (IsDriveRelativePath).
function TryNormalizeTestOutputDir(const aValue: string; out aFullPath, aError: string): Boolean;
var
  lError: string;
  lNormalized: string;
begin
  aFullPath := '';
  aError := '';
  if Trim(aValue) = '' then
  begin
    aError := Format(cTestOutputDirUnusable, [aValue, 'a directory is required']);
    Exit(False);
  end;
  if not TryNormalizeInputPath(aValue, lNormalized, lError) then
  begin
    aError := Format(cTestOutputDirUnusable, [aValue, lError]);
    Exit(False);
  end;
  if IsDriveRelativePath(lNormalized) then
  begin
    aError := Format(cTestOutputDirUnusable, [aValue, cTestOutputDirDriveRelative]);
    Exit(False);
  end;
  try
    aFullPath := TPath.GetFullPath(lNormalized);
  except
    on E: Exception do
    begin
      aError := Format(cTestOutputDirUnusable, [aValue, E.Message]);
      Exit(False);
    end;
  end;
  Result := True;
end;

function NormalizeBuildOptions(const aOptions: TAppOptions; out aNormalizedOptions: TAppOptions;
  out aError: string): Boolean;
var
  lBuildBackend: TBuildBackend;
  lTestOutputDir: string;
begin
  Result := False;
  aError := '';
  aNormalizedOptions := aOptions;

  if not TryResolveDprojPath(aOptions.fDprojPath, aNormalizedOptions.fDprojPath, aError) then
    Exit(False);

  if Trim(aNormalizedOptions.fBuildTarget) = '' then
    aNormalizedOptions.fBuildTarget := 'Build';

  if not ResolveDetectedBuildBackend(aNormalizedOptions, lBuildBackend, aError) then
    Exit(False);
  aNormalizedOptions.fBuildBackend := lBuildBackend;

  if aNormalizedOptions.fBuildBackend = TBuildBackend.bbWebCore then
  begin
    if not ValidateWebCoreBuildOptions(aNormalizedOptions, aError) then
      Exit(False);
    Exit(True);
  end;

  if aNormalizedOptions.fHasBuildTestOutputDir then
  begin
    if not TryNormalizeTestOutputDir(aNormalizedOptions.fBuildTestOutputDir, lTestOutputDir, aError) then
      Exit(False);
    aNormalizedOptions.fBuildTestOutputDir := lTestOutputDir;
  end;

  if Trim(aNormalizedOptions.fDelphiVersion) = '' then
  begin
    if not LoadDefaultDelphiVersion(aNormalizedOptions.fDprojPath, aNormalizedOptions.fDelphiVersion) and
      (Trim(aNormalizedOptions.fRsVarsPath) = '') then
    begin
      aError := 'Delphi version is required. Pass --delphi <major.minor> or set [Build] DelphiVersion in dak.ini.';
      Exit(False);
    end;
  end;

  aNormalizedOptions.fDelphiVersion := NormalizeDelphiVerForBuild(aNormalizedOptions.fDelphiVersion);
  Result := True;
end;

// DAK-382: the semantic project loader raises EArgumentException for a MainSource with invalid path characters.
// Source context is optional, so that becomes the lookup error the caller already reports with --verbose.
function TryBuildProjectSourceLookupGuarded(const aDprojPath, aConfig, aPlatform, aDelphiVersion: string;
  const aEnvVars: TDictionary<string, string>; out aLookup: TProjectSourceLookup; out aError: string): Boolean;
begin
  try
    Result := TryBuildProjectSourceLookup(aDprojPath, aConfig, aPlatform, aDelphiVersion, aEnvVars, nil, aLookup,
      aError);
  except
    on E: EArgumentException do
    begin
      aError := E.Message;
      Result := False;
    end;
  end;
end;

function TryRunBuildInternal(const aOptions: TAppOptions; out aExitCode: Integer; out aError: string): Boolean;
var
  lRunner: IBuildProcessRunner;
begin
  lRunner := TBuildProcessRunner.Create;
  Result := TryRunBuildInternal(aOptions, lRunner, nil, aExitCode, aError);
end;

function TryRunBuildInternal(const aOptions: TAppOptions; const aRunner: IBuildProcessRunner;
  out aExitCode: Integer; out aError: string): Boolean;
begin
  Result := TryRunBuildInternal(aOptions, aRunner, nil, aExitCode, aError);
end;

function TryRunBuildInternal(const aOptions: TAppOptions; const aRunner: IBuildProcessRunner;
  const aDfmCheckRunner: TBuildDfmCheckRunner; out aExitCode: Integer; out aError: string): Boolean;
var
  lBdsRoot: string;
  lBuildSourceContextCache: TSourceContextRunCache;
  lDiagnosticsWarnings: TDiagnostics;
  lDiagnosticsDefaults: TDiagnosticsDefaults;
  lEnvVars: TDictionary<string, string>;
  lErrLog: string;
  lExtraProps: TArray<TMsBuildProperty>;
  lJson: string;
  lLookupError: string;
  lMadErrLog: string;
  lMadExceptExe: string;
  lMadExitCode: Integer;
  lLspContext: TLspContext;
  lLspHintCache: TDictionary<string, string>;
  lLspHintError: string;
  lLspHintText: string;
  lLspLookup: TProjectSourceLookup;
  lLspLookupError: string;
  lLogRetention: TBuildLogRetention;
  lLspNotePrinted: Boolean;
  lNormalizedOptions: TAppOptions;
  lOutLog: string;
  lOutputPostTicks: Int64;
  lOutputPreTicks: Int64;
  lProjectInfo: TBuildProjectInfo;
  lProjectLookup: TProjectSourceLookup;
  lRsVarsEnvironment: TRsVarsEnvironment;
  lRsVarsEnvironmentBlock: string;
  lRunProcessOk: Boolean;
  lSettings: TDakBuildSettings;
  lSkippedEnvProjNames: TArray<string>;
  lSkippedName: string;
  lSourceBuildExitCode: Integer;
  lSourceBuildTimedOut: Boolean;
  lStartTick: Int64;
  lSummary: TBuildSummary;
  lSummaryOptions: TBuildSummaryOptions;
  lTempBase: string;
  lTimeMs: Int64;
  lTimedOut: Boolean;
  lMsBuildPath: string;
  lMsBuildProps: TArray<TMsBuildProperty>;
begin
  Result := False;
  aExitCode := 1;
  aError := '';
  lEnvVars := nil;
  lDiagnosticsWarnings := nil;
  lExtraProps := nil;
  lOutLog := '';
  lErrLog := '';
  lMadErrLog := '';
  lTempBase := '';
  lLogRetention := Default(TBuildLogRetention);

  if not NormalizeBuildOptions(aOptions, lNormalizedOptions, aError) then
    Exit(False);

  lEnvVars := CaptureEnvironment;
  try
    LoadBuildSettings(lNormalizedOptions.fDprojPath, lNormalizedOptions, lEnvVars, lSettings);

    if lNormalizedOptions.fBuildBackend = TBuildBackend.bbWebCore then
      Exit(TryRunWebCoreBuild(lNormalizedOptions, aRunner, lSettings, aExitCode, aError));

    PrintVerboseStep(lNormalizedOptions, 'load-rsvars');
    if not TryLoadRsVars(lNormalizedOptions.fDelphiVersion, lNormalizedOptions.fRsVarsPath, nil,
      lRsVarsEnvironment, aError) then
      Exit(False);
    lRsVarsEnvironmentBlock := lRsVarsEnvironment.ToEnvironmentBlock;

    PrintVerboseStep(lNormalizedOptions, 'capture-environment');
    lEnvVars.Free;
    lEnvVars := lRsVarsEnvironment.ToDictionary;
    lDiagnosticsWarnings := TDiagnostics.Create;
    PrintVerboseStep(lNormalizedOptions, 'load-settings');
    LoadBuildSettings(lNormalizedOptions.fDprojPath, lNormalizedOptions, lEnvVars, lSettings);
    LoadDiagnosticsDefaults(lDiagnosticsWarnings, lNormalizedOptions.fDprojPath, lDiagnosticsDefaults);
    ApplyDiagnosticsOverrides(lNormalizedOptions, lDiagnosticsDefaults);
    if not lNormalizedOptions.fBuildQuiet then
    begin
      lDiagnosticsWarnings.EmitWarnings(
        procedure(const aMessage: string)
        begin
          WriteLn(aMessage);
        end);
    end;

    PrintVerboseStep(lNormalizedOptions, 'resolve-msbuild');
    lBdsRoot := ResolveBdsRoot(lNormalizedOptions.fDelphiVersion, lNormalizedOptions.fRsVarsPath,
      lRsVarsEnvironment.ValueOrDefault('BDS'));
    if not TryFindMsBuild(lBdsRoot, lMsBuildPath) then
    begin
      aError := cMsBuildNotFound;
      Exit(False);
    end;

    PrintVerboseStep(lNormalizedOptions, 'environment-props');
    ApplyEnvironmentProjProps(BuildEnvironmentProjPath(lNormalizedOptions.fDelphiVersion, lBdsRoot), lEnvVars,
      lExtraProps, lSkippedEnvProjNames);
    // Only the name: an environment.proj value can be a secret.
    for lSkippedName in lSkippedEnvProjNames do
      PrintVerboseStep(lNormalizedOptions, 'environment-props: skipped ' + lSkippedName +
        ' (its value contains a line break)');
    PrintVerboseStep(lNormalizedOptions, 'preflight');
    EmitBuildPreflightWarnings(lNormalizedOptions, lEnvVars);
    PrintVerboseStep(lNormalizedOptions, 'project-info');
    lProjectInfo := BuildProjectInfo(lNormalizedOptions.fDprojPath, lNormalizedOptions.fConfig,
      lNormalizedOptions.fPlatform, lEnvVars, IfThen(lNormalizedOptions.fHasBuildTestOutputDir,
      lNormalizedOptions.fBuildTestOutputDir, ''), lNormalizedOptions.fBuildDefines,
      lNormalizedOptions.fBuildUnitSearchPath, lBdsRoot, aError);
    if aError <> '' then
      Exit(False);
    if lProjectInfo.fOutputPath <> '' then
      PrintVerboseStep(lNormalizedOptions, 'output-name: ' + TPath.GetFileName(lProjectInfo.fOutputPath) +
        ' (from ' + lProjectInfo.fOutputNameSource + ')')
    else
      PrintVerboseStep(lNormalizedOptions, 'output-name: unresolved (' + lProjectInfo.fOutputUnresolvedReason + ')');
    if lProjectInfo.fMadExceptReason = 'platform-not-windows' then
      PrintVerboseStep(lNormalizedOptions, 'madexcept-patch: skipped (platform ' + lNormalizedOptions.fPlatform +
        ' is not Win32 or Win64; madExceptPatch patches Windows binaries only)');

    lTempBase := TPath.Combine(TPath.GetTempPath,
      'dak-build-' + IntToStr(GetCurrentProcessId) + '-' + IntToStr(GetTickCount));
    lOutLog := lTempBase + '.out.log';
    lErrLog := lTempBase + '.err.log';
    lMadErrLog := lTempBase + '.mad.err.log';

    lOutputPreTicks := FileUtcTicks(lProjectInfo.fOutputPath);
    lStartTick := CurrentTicks;
    lMsBuildProps := BuildMsBuildOverrideProperties(lNormalizedOptions, lProjectInfo, lExtraProps);
    PrintVerboseStep(lNormalizedOptions, 'run-msbuild');
    PrintVerboseStep(lNormalizedOptions, 'msbuild-exe: ' + lMsBuildPath);
    PrintVerboseStep(lNormalizedOptions, 'msbuild-args: ' +
      BuildMsBuildArguments(lNormalizedOptions, lProjectInfo, lMsBuildProps, TMsBuildArgumentsView.avTrace));
    // The run directory is made before the build starts, so a location we cannot write fails fast instead of
    // after a long build. The files follow once the process has ended.
    if lNormalizedOptions.fBuildKeepLogs then
      if not TryCreateBuildLogRunDir(lNormalizedOptions, lLogRetention.fRunDir, aError) then
        Exit(False);
    try
      lRunProcessOk := aRunner.RunProcess(lMsBuildPath,
        BuildMsBuildArguments(lNormalizedOptions, lProjectInfo, lMsBuildProps, TMsBuildArgumentsView.avProcess),
        lProjectInfo.fProjectDir, lOutLog, lErrLog, lRsVarsEnvironmentBlock, lNormalizedOptions.fBuildTimeoutSec,
        aExitCode, lTimedOut, aError);
    except
      // The launcher failed before any log existed: do not leave an empty run directory behind.
      RemoveEmptyRunDir(lLogRetention.fRunDir);
      raise;
    end;
    // A process that never started has no logs to keep; only its failure is reported.
    if lRunProcessOk or FileExists(lOutLog) then
      RetainBuildLogs(lLogRetention, lOutLog, lErrLog);
    if not lRunProcessOk then
    begin
      RemoveEmptyRunDir(lLogRetention.fRunDir);
      if lLogRetention.fError <> '' then
        aError := Trim(aError + sLineBreak + lLogRetention.fError);
      Exit(False);
    end;
    lSourceBuildExitCode := aExitCode;
    lSourceBuildTimedOut := lTimedOut;
    lTimeMs := CurrentTicks - lStartTick;

    PrintVerboseStep(lNormalizedOptions, 'parse-logs');
    lSummaryOptions := Default(TBuildSummaryOptions);
    lSummaryOptions.fProjectRoot := DetermineProjectRoot(lProjectInfo.fProjectPath);
    lSummaryOptions.fIgnoreWarnings := lSettings.fIgnoreWarnings;
    lSummaryOptions.fIgnoreHints := lSettings.fIgnoreHints;
    lSummaryOptions.fExcludePathMasks := lSettings.fExcludePathMasks;
    lSummaryOptions.fMaxFindings := lNormalizedOptions.fBuildMaxFindings;
    lSummaryOptions.fIncludeWarnings := lNormalizedOptions.fBuildShowWarnings;
    lSummaryOptions.fIncludeHints := lNormalizedOptions.fBuildShowHints;

    lSummary := ParseBuildLogs(lOutLog, lErrLog, lSummaryOptions);
    if lSourceBuildExitCode <> 0 then
      AnnotateMsBuildPropertyRejection(lOutLog, lErrLog,
        BuildMsBuildSelectionProperties(lNormalizedOptions) + lMsBuildProps, lSummary);
    if ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, True) or
      ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, False) then
    begin
      lLookupError := '';
      lProjectLookup := Default(TProjectSourceLookup);
      lProjectLookup.fProjectDproj := lNormalizedOptions.fDprojPath;
      lProjectLookup.fProjectDir := lProjectInfo.fProjectDir;
        lProjectLookup.fMainSourcePath := lProjectInfo.fMainSourcePath;
      if TryBuildProjectSourceLookupGuarded(lNormalizedOptions.fDprojPath, lNormalizedOptions.fConfig,
        lNormalizedOptions.fPlatform, lNormalizedOptions.fDelphiVersion, lEnvVars, lProjectLookup, lLookupError)
      then
      begin
        lBuildSourceContextCache := TSourceContextRunCache.Create(lProjectLookup);
        try
          if ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, True) then
            EnrichBuildFindingsWithSourceContext(lSummary.fErrors, lSummary.fErrorDiagnostics,
              lBuildSourceContextCache, lDiagnosticsDefaults.fSourceContextLines);
          if ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, False) then
          begin
            EnrichBuildFindingsWithSourceContext(lSummary.fWarnings, lSummary.fWarningDiagnostics,
              lBuildSourceContextCache, lDiagnosticsDefaults.fSourceContextLines);
            EnrichBuildFindingsWithSourceContext(lSummary.fHints, lSummary.fHintDiagnostics,
              lBuildSourceContextCache, lDiagnosticsDefaults.fSourceContextLines);
          end;
        finally
          lBuildSourceContextCache.Free;
        end;
      end else
      begin
        lBuildSourceContextCache := TSourceContextRunCache.Create(lProjectLookup);
        try
          if ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, True) then
            EnrichBuildFindingsWithSourceContext(lSummary.fErrors, lSummary.fErrorDiagnostics,
              lBuildSourceContextCache, lDiagnosticsDefaults.fSourceContextLines);
          if ShouldEmitSourceContext(lDiagnosticsDefaults.fSourceContextMode, False) then
          begin
            EnrichBuildFindingsWithSourceContext(lSummary.fWarnings, lSummary.fWarningDiagnostics,
              lBuildSourceContextCache, lDiagnosticsDefaults.fSourceContextLines);
            EnrichBuildFindingsWithSourceContext(lSummary.fHints, lSummary.fHintDiagnostics,
              lBuildSourceContextCache, lDiagnosticsDefaults.fSourceContextLines);
          end;
        finally
          lBuildSourceContextCache.Free;
        end;
        if lNormalizedOptions.fVerbose and (not lNormalizedOptions.fBuildQuiet) and (lLookupError <> '') then
          Writeln('NOTE. Source context search paths unavailable: ' + lLookupError);
    end;
  end;
    if lNormalizedOptions.fBuildAi and (lSummary.fErrorCount > 0) then
    begin
      lLspLookup := lProjectLookup;
      if (lLspLookup.fProjectDir = '') or (Length(lLspLookup.fSearchPaths) = 0) then
      begin
        lLspLookupError := '';
        lLspLookup.fProjectDproj := lNormalizedOptions.fDprojPath;
        lLspLookup.fProjectDir := lProjectInfo.fProjectDir;
        lLspLookup.fMainSourcePath := lProjectInfo.fMainSourcePath;
        if not TryBuildProjectSourceLookup(lNormalizedOptions.fDprojPath, lNormalizedOptions.fConfig,
          lNormalizedOptions.fPlatform, lNormalizedOptions.fDelphiVersion, lEnvVars, nil, lLspLookup, lLspLookupError)
        then
        begin
          if lNormalizedOptions.fVerbose and (lLspLookupError <> '') then
            Writeln('NOTE. LSP enrichment skipped: ' + lLspLookupError);
        end;
      end;

      if (lLspLookup.fProjectDir <> '') and (Length(lLspLookup.fSearchPaths) > 0) then
      begin
        lLspHintCache := TDictionary<string, string>.Create;
        try
          var lLspSourceCache := TSourceContextRunCache.Create(lLspLookup);
          try
            lLspHintError := '';
            lLspNotePrinted := False;
            if TryBuildStrictLspContext(lNormalizedOptions, lLspContext, lLspHintError) then
            begin
              for var i := 0 to High(lSummary.fErrors) do
              begin
                if i > High(lSummary.fErrorDiagnostics) then
                  Break;
                lLspHintText := '';
                if TryBuildLspEnrichmentText(lNormalizedOptions, lSummary.fErrorDiagnostics[i], lLspContext,
                  lDiagnosticsDefaults.fSourceContextLines,
                  lLspSourceCache, lLspHintCache, lLspHintText, lLspHintError) then
                  lSummary.fErrors[i] := lSummary.fErrors[i] + sLineBreak + lLspHintText
                else if lNormalizedOptions.fVerbose and (lLspHintError <> '') and (not lLspNotePrinted) then
                begin
                  Writeln('NOTE. LSP enrichment skipped: ' + lLspHintError);
                  lLspNotePrinted := True;
                end;
              end;
            end else if lNormalizedOptions.fVerbose and (lLspHintError <> '') then
              Writeln('NOTE. LSP enrichment skipped: ' + lLspHintError);
          finally
            lLspSourceCache.Free;
          end;
        finally
          lLspHintCache.Free;
        end;
      end;
    end;
    lSummary.fExitCode := aExitCode;
    lSummary.fTimedOut := lTimedOut;
    lSummary.fOutputPath := lProjectInfo.fOutputPath;

    if lTimedOut then
      lSummary.fStatus := cStatusTimeout
    else if aExitCode <> 0 then
      lSummary.fStatus := cStatusError
    else
    begin
      lOutputPostTicks := FileUtcTicks(lProjectInfo.fOutputPath);
      if (lOutputPostTicks > 0) and (lOutputPreTicks > 0) and (lOutputPostTicks <= lOutputPreTicks) then
      begin
        lSummary.fOutputStale := True;
        lSummary.fOutputMessage := cOutputLockedMessage;
        lSummary.fStatus := cStatusOutputLocked;
      end else if lProjectInfo.fOutputPath = '' then
      begin
        // DAK-374: an unknown artifact name is reported with its reason instead of a guessed path.
        lSummary.fOutputStale := True;
        lSummary.fOutputMessage := Format(cOutputUnresolvedMessage, [lProjectInfo.fOutputUnresolvedReason]);
        lSummary.fStatus := cStatusOutputMissing;
      end else if not FileExists(lProjectInfo.fOutputPath) then
      begin
        // A predicted output the compiler did not write is never reported as a fresh result.
        lSummary.fOutputStale := True;
        lSummary.fOutputMessage := Format(cOutputMissingMessage, [lProjectInfo.fOutputPath]);
        if lProjectInfo.fOutputNote <> '' then
          lSummary.fOutputMessage := lSummary.fOutputMessage + ' (' + lProjectInfo.fOutputNote + ')';
        lSummary.fStatus := cStatusOutputMissing;
      end else
      begin
        if lSummary.fWarningCount > 0 then
          lSummary.fStatus := cStatusWarnings
        else if lSummary.fHintCount > 0 then
          lSummary.fStatus := cStatusHints
        else
          lSummary.fStatus := cStatusOk;
        // DAK-374: the file exists and is fresh; the note says what its name assumed.
        lSummary.fOutputMessage := lProjectInfo.fOutputNote;
      end;
    end;

    if (aExitCode = 0) and lProjectInfo.fMadExceptRequired then
    begin
      PrintVerboseStep(lNormalizedOptions, 'madexcept-patch');
      if not FileExists(lProjectInfo.fOutputPath) then
      begin
        lSummary.fStatus := cStatusInternalError;
        lSummary.fExitCode := 1;
        aExitCode := 1;
        if lProjectInfo.fOutputPath = '' then
          lSummary.fOutputMessage := Format(cOutputUnresolvedMessage, [lProjectInfo.fOutputUnresolvedReason])
        else
          lSummary.fOutputMessage := Format(cMadExceptOutputMissingMessage, [lProjectInfo.fOutputPath]);
      end else
      begin
        lMadExceptExe := ResolveMadExceptPatchExe(lSettings.fMadExceptPath);
        if lMadExceptExe = '' then
        begin
          lSummary.fStatus := cStatusInternalError;
          lSummary.fExitCode := 1;
          aExitCode := 1;
          lSummary.fOutputMessage := cMadExceptPatchRequiredMessage;
        end else if not aRunner.RunProcess(lMadExceptExe,
          QuoteCmdArg(lProjectInfo.fOutputPath) + ' ' + QuoteCmdArg(lProjectInfo.fMesPath), lProjectInfo.fProjectDir,
          lTempBase + '.mad.out.log', lMadErrLog, lRsVarsEnvironmentBlock, 0, lMadExitCode, lTimedOut, aError) then
          Exit(False)
        else if lMadExitCode <> 0 then
        begin
          lSummary.fStatus := cStatusInternalError;
          lSummary.fExitCode := 1;
          aExitCode := 1;
          lSummary.fOutputMessage := cMadExceptPatchFailedMessage;
        end;
      end;
    end;

    // A build whose requested logs were lost is not a clean success; a failed build keeps its own result.
    if (lLogRetention.fError <> '') and (aExitCode = 0) then
    begin
      lSummary.fStatus := cStatusInternalError;
      lSummary.fExitCode := 1;
      aExitCode := 1;
    end;
    lSummary.fLogsDir := lLogRetention.fRunDir;
    lSummary.fLogsError := lLogRetention.fError;

    if not lNormalizedOptions.fBuildQuiet then
    begin
      if lNormalizedOptions.fBuildJson then
      begin
        PrintVerboseStep(lNormalizedOptions, 'emit-json');
        lJson := BuildSummaryAsJson(lProjectInfo.fProjectPath, lNormalizedOptions, lSummary,
          lNormalizedOptions.fBuildTarget, lTimeMs);
        Writeln(lJson);
      end else
      begin
        PrintVerboseStep(lNormalizedOptions, 'print-summary');
        PrintSummary(lNormalizedOptions, lProjectInfo, lSummary, (lSourceBuildExitCode <> 0) or lSourceBuildTimedOut,
          lLogRetention);
      end;
    end;

    if lNormalizedOptions.fBuildRunDfmCheck and (lSourceBuildExitCode = 0) and (not lSourceBuildTimedOut) then
    begin
      WriteLn('[build] Running dfm-check validation...');
      if Assigned(aDfmCheckRunner) then
        lMadExitCode := aDfmCheckRunner(lNormalizedOptions)
      else
        lMadExitCode := RunDfmCheckCommand(lNormalizedOptions);
      if (aExitCode = 0) and (lMadExitCode <> 0) then
        aExitCode := lMadExitCode;
    end;

    Result := True;
  finally
    lDiagnosticsWarnings.Free;
    lEnvVars.Free;
    PreserveBuildDiagnosticLog(lNormalizedOptions.fBuildDiagnosticsDir, lOutLog, 'stdout.log');
    PreserveBuildDiagnosticLog(lNormalizedOptions.fBuildDiagnosticsDir, lErrLog, 'stderr.log');
    if (lOutLog <> '') and FileExists(lOutLog) then
      System.SysUtils.DeleteFile(lOutLog);
    if (lErrLog <> '') and FileExists(lErrLog) then
      System.SysUtils.DeleteFile(lErrLog);
    if (lTempBase <> '') and FileExists(lTempBase + '.mad.out.log') then
      System.SysUtils.DeleteFile(lTempBase + '.mad.out.log');
    if (lMadErrLog <> '') and FileExists(lMadErrLog) then
      System.SysUtils.DeleteFile(lMadErrLog);
  end;
end;
end.
