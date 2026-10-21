unit Dak.Build.NativeContext;

interface

uses
  Dak.Build.Types;

type
  TDakNativeCompilerInvocation = record
    fProjectFileName: string;
    fMsBuildFileName: string;
    fCompilerFileName: string;
    fSdkRoot: string;
    fEnvironmentBlock: string;
    fPropertyArguments: string;
    fWorkRoot: string;
  end;

  TDakNativeCompilerSourceProfile = record
    fDefines: string;
    fIncludePaths: string;
    fPlatform: string;
    fConfiguration: string;
    fUnitAliases: string;
    fUnitScopeNames: string;
  end;

  IDakNativeCompilerContext = interface
    ['{8EF7CB07-CDA3-4F4D-AAC0-713CC709CF75}']
    function CompilerFileName: string;
    function RootLibraryDirectory: string;
    function UnitSearchPaths: TArray<string>;
    function SourceProfile: TDakNativeCompilerSourceProfile;
    function EvidenceFingerprint: string;
    function InputsAreCurrent: Boolean;
  end;

type
  IDakNativeRootSelectionPaths = interface
    ['{E8E4D89E-3207-4DBC-8870-043E50CB7622}']
    function RootSelectionPaths: TArray<string>;
  end;

  IDakNativeCompilerContextObservation = interface
    ['{467EFC4C-8826-4C63-B88B-545C736ED414}']
    function CapturedFingerprint: string;
    function CapturedInputsAreCurrent: Boolean;
    function RevalidationCount: Integer;
  end;

function TryCaptureNativeCompilerContext(const aInvocation: TDakNativeCompilerInvocation;
  const aRunner: IBuildProcessRunner; out aReason: string): IDakNativeCompilerContext;

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.Hash, System.IOUtils,
  System.RegularExpressions, System.StrUtils, System.SysUtils,
  Winapi.Windows,
  Xml.omnixmldom, Xml.xmldom,
  AutoFree,
  maxLogic.ioutils,
  SimpleParser.Lexer, SimpleParser.Lexer.Types,
  Dak.NativeInputLocks;

const
  cNativeContextProperties: array[0..18] of string = ('UnitAliases', 'DCC_AdditionalSwitches', 'DCC_UsePackage',
    'DCC_Namespace', 'DCC_DefaultNamespace', 'DCC_DebugDCUs', 'DCC_DcuOutput', 'MainSource',
    'GlobalOptionFile', 'DCC_ToolExe', 'DCC_PreferredToolArchitecture', 'DCC_IgnoreCommandLine', 'BDS',
    'PreBuildEvent', 'PostBuildEvent', 'DCC_Define', 'DCC_IncludePath', 'Platform', 'Config');

type
  TNativeContextIncludeRefusal = class(TInterfacedObject, IIncludeHandler)
  public
    function GetIncludeFileContent(const aParentFileName, aIncludeName: string;
      out aContent, aFileName: string): Boolean;
  end;

  TNativeCompilerContext = class(TInterfacedObject, IDakNativeCompilerContext,
    IDakNativeCompilerContextObservation, IDakNativeRootSelectionPaths)
  private
    fInvocation: TDakNativeCompilerInvocation;
    fRunRoot: string;
    fLibraryDirectory: string;
    fPaths: TArray<string>;
    fUnitPaths: TArray<string>;
    fFingerprint: string;
    fPreprocessed: string;
    fSnapshotArguments: string;
    fSnapshotIdentity: string;
    fSourceProfile: TDakNativeCompilerSourceProfile;
    fValidationIndex: Integer;
    fInputLocks: TDakNativeInputLocks;
    fRunner: IBuildProcessRunner;
    fTransportFiles: TList<string>;
    fDirectoryIdentity: TByHandleFileInformation;
    fFailed: Boolean;
    function TransportFile(const aName: string): string;
    procedure CleanupTransport;
    procedure RetainFailureTransport;
    function RunMetadata(const aArguments, aTag: string): Boolean;
    function Preprocess(const aTag: string): string;
    function ReadProperty(const aName: string): string;
    function ReadSnapshotIdentity(const aPathsFileName: string): string;
    procedure RetainInput(const aFileName: string; const aIdentity: TStringBuilder);
    procedure CaptureSourceReferences(const aFileName: string; const aIdentity: TStringBuilder);
    procedure Capture;
    function RootSelectionIsCurrent: Boolean;
    function RootSelectionPaths: TArray<string>;
  public
    constructor Create(const aInvocation: TDakNativeCompilerInvocation; const aRunner: IBuildProcessRunner);
    destructor Destroy; override;
    function CompilerFileName: string;
    function RootLibraryDirectory: string;
    function UnitSearchPaths: TArray<string>;
    function SourceProfile: TDakNativeCompilerSourceProfile;
    function EvidenceFingerprint: string;
    function InputsAreCurrent: Boolean;
    function CapturedFingerprint: string;
    function CapturedInputsAreCurrent: Boolean;
    function RevalidationCount: Integer;
  end;

function ReadNativeTransport(const aFileName: string; const aLimit: Integer): string; forward;

function XmlAttribute(const aValue: string): string;
begin
  Result := StringReplace(aValue, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

function NewRunName: string;
var
  lGuid: TGUID;
begin
  CreateGUID(lGuid);
  Result := 'run-' + GUIDToString(lGuid);
end;

function ReadContextDirectoryIdentity(const aPath: string;
  out aInformation: TByHandleFileInformation): Boolean;
var
  lHandle: THandle;
begin
  aInformation := Default(TByHandleFileInformation);
  lHandle := CreateFile(PChar(aPath), FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or $00200000, 0);
  if lHandle = INVALID_HANDLE_VALUE then
    Exit(False);
  try
    Result := GetFileInformationByHandle(lHandle, aInformation) and
      ((aInformation.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) = 0);
  finally
    CloseHandle(lHandle);
  end;
end;

function TNativeCompilerContext.TransportFile(const aName: string): string;
begin
  Result := TPath.Combine(fRunRoot, aName);
  if not fTransportFiles.Contains(Result) then
    fTransportFiles.Add(Result);
end;

function ContextDirectoryIdentityText(const aInformation: TByHandleFileInformation): string;
begin
  Result := Format('%d:%d:%d', [aInformation.dwVolumeSerialNumber,
    aInformation.nFileIndexHigh, aInformation.nFileIndexLow]);
end;

procedure TNativeCompilerContext.RetainFailureTransport;
var
  g: TGarbos;
  lFailedRoots: TList<string>;
  lRoot, lFileName, lMarker: string;
  lCurrent: TByHandleFileInformation;
  lLines: TArray<string>;
  lBytes: TBytes;
  lStream: TFileStream;
  lIdentity: TStringBuilder;
  i, j: Integer;
begin
  GC(lIdentity, TStringBuilder.Create, g);
  lIdentity.AppendLine(ContextDirectoryIdentityText(fDirectoryIdentity));
  for lFileName in fTransportFiles do
    if TFile.Exists(lFileName) then
    begin
      lStream := TFileStream.Create(lFileName, fmOpenReadWrite or fmShareExclusive);
      try
        // Failure diagnostics are the first MiB only; never truncate an input.
        if lStream.Size > 1024 * 1024 then
          lStream.Size := 1024 * 1024;
      finally
        lStream.Free;
      end;
      lIdentity.AppendLine(TPath.GetFileName(lFileName));
    end;
  lMarker := TPath.Combine(fRunRoot, 'failure.manifest');
  lBytes := TEncoding.UTF8.GetBytes(lIdentity.ToString);
  lStream := TFileStream.Create(lMarker, fmCreate);
  try
    lStream.WriteBuffer(lBytes[0], Length(lBytes));
    if not FlushFileBuffers(lStream.Handle) then
      RaiseLastOSError;
  finally
    lStream.Free;
  end;
  GC(lFailedRoots, TList<string>.Create, g);
  for lRoot in TDirectory.GetDirectories(fInvocation.fWorkRoot, 'run-*') do
    if TFile.Exists(TPath.Combine(lRoot, 'failure.manifest')) then
      lFailedRoots.Add(lRoot);
  lFailedRoots.Sort(TComparer<string>.Construct(
    function(const aLeft, aRight: string): Integer
    begin
      if TDirectory.GetCreationTimeUtc(aLeft) < TDirectory.GetCreationTimeUtc(aRight) then
        Exit(-1);
      if TDirectory.GetCreationTimeUtc(aLeft) > TDirectory.GetCreationTimeUtc(aRight) then
        Exit(1);
      Result := CompareStr(aLeft, aRight);
    end));
  for i := 0 to lFailedRoots.Count - 4 do
  begin
    lRoot := lFailedRoots[i];
    lMarker := TPath.Combine(lRoot, 'failure.manifest');
    if not ReadContextDirectoryIdentity(lRoot, lCurrent) then
      Continue;
    // Only completed failure sets have a marker. Exclusive open excludes another
    // pruner; live successful contexts never enter this retention queue.
    lStream := TFileStream.Create(lMarker, fmOpenReadWrite or fmShareExclusive);
    try
      if lStream.Size > 64 * 1024 then
        Continue;
      SetLength(lBytes, Integer(lStream.Size));
      if Length(lBytes) > 0 then
        lStream.ReadBuffer(lBytes[0], Length(lBytes));
      lLines := TEncoding.UTF8.GetString(lBytes).Replace(#13, '').Split([#10],
        TStringSplitOptions.ExcludeEmpty);
      if (Length(lLines) = 0) or
        (lLines[0] <> ContextDirectoryIdentityText(lCurrent)) then
        Continue;
      for j := 1 to High(lLines) do
      begin
        lFileName := lLines[j];
        if (TPath.GetFileName(lFileName) <> lFileName) or
          (not MatchText(TPath.GetExtension(lFileName), ['.xml', '.txt', '.cmds', '.log', '.targets'])) then
          raise EInvalidOpException.Create('Unknown native failure manifest artifact');
      end;
      for j := 1 to High(lLines) do
        if not DeleteFile(PChar(TPath.Combine(lRoot, lLines[j]))) then
          if GetLastError <> ERROR_FILE_NOT_FOUND then
            RaiseLastOSError;
    finally
      lStream.Free;
    end;
    if not DeleteFile(PChar(lMarker)) then
      RaiseLastOSError;
    // Unknown files are retained; there is no recursive deletion.
    if not RemoveDirectory(PChar(lRoot)) then
      OutputDebugString(PChar('DAK-414 native failure directory retained: ' + lRoot));
  end;
end;

procedure TNativeCompilerContext.CleanupTransport;
var
  lCurrent: TByHandleFileInformation;
  lFileName: string;
begin
  // Exact known flat files only; unknown content and replaced directories stay.
  if (fTransportFiles = nil) or
    (not ReadContextDirectoryIdentity(fRunRoot, lCurrent)) or
    (lCurrent.dwVolumeSerialNumber <> fDirectoryIdentity.dwVolumeSerialNumber) or
    (lCurrent.nFileIndexHigh <> fDirectoryIdentity.nFileIndexHigh) or
    (lCurrent.nFileIndexLow <> fDirectoryIdentity.nFileIndexLow) then
    Exit;
  if fFailed then
  begin
    RetainFailureTransport;
    Exit;
  end;
  for lFileName in fTransportFiles do
    if TFile.Exists(lFileName) and (not DeleteFile(PChar(lFileName))) then
      OutputDebugString(PChar('DAK-414 native transport cleanup failed: ' + lFileName));
  if not RemoveDirectory(PChar(fRunRoot)) then
    OutputDebugString(PChar('DAK-414 native context directory retained: ' + fRunRoot));
end;

constructor TNativeCompilerContext.Create(const aInvocation: TDakNativeCompilerInvocation;
  const aRunner: IBuildProcessRunner);
begin
  inherited Create;
  fInvocation := aInvocation;
  fRunner := aRunner;
  fInputLocks := TDakNativeInputLocks.Create;
  fTransportFiles := TList<string>.Create;
  fFailed := True;
  fRunRoot := TPath.Combine(aInvocation.fWorkRoot, NewRunName);
  TDirectory.CreateDirectory(fRunRoot);
  if not ReadContextDirectoryIdentity(fRunRoot, fDirectoryIdentity) then
    raise EInvalidOpException.Create('Native transport directory identity unavailable');
  Capture;
  fFailed := False;
end;

destructor TNativeCompilerContext.Destroy;
begin
  fInputLocks.Free;
  try
    CleanupTransport;
  except
    on E: Exception do
      OutputDebugString(PChar('DAK-414 native transport cleanup failed: ' + E.Message));
  end;
  fTransportFiles.Free;
  inherited;
end;

procedure TNativeCompilerContext.RetainInput(const aFileName: string; const aIdentity: TStringBuilder);
begin
  fInputLocks.Retain(aFileName, aIdentity);
end;

function TNativeCompilerContext.RunMetadata(const aArguments, aTag: string): Boolean;
var
  lError: string;
  lExitCode: Integer;
  lTimedOut: Boolean;
begin
  Result := fRunner.RunProcess(fInvocation.fMsBuildFileName,
    '"' + fInvocation.fProjectFileName + '" ' + fInvocation.fPropertyArguments + ' ' + aArguments,
    TPath.GetDirectoryName(fInvocation.fProjectFileName),
    TransportFile(aTag + '.stdout.log'), TransportFile(aTag + '.stderr.log'),
    fInvocation.fEnvironmentBlock, 30, lExitCode, lTimedOut, lError);
  Result := Result and (not lTimedOut) and (lExitCode = 0);
end;

function TNativeCompilerContext.Preprocess(const aTag: string): string;
var
  lFileName: string;
begin
  lFileName := TransportFile(aTag + '.xml');
  if not RunMetadata('/pp:"' + lFileName + '" /nologo', aTag) then
    raise EInvalidOpException.Create('Native MSBuild context preprocessing failed');
  Result := ReadNativeTransport(lFileName, 4 * 1024 * 1024);
end;

function TNativeCompilerContext.ReadProperty(const aName: string): string;
var
  i: Integer;
  lLines: TArray<string>;
begin
  lLines := ReadNativeTransport(TransportFile(aName + '.txt'), 64 * 1024).Replace(#13, '').Split([#10]);
  if (Length(lLines) > 0) and (lLines[High(lLines)] = '') then
    SetLength(lLines, Length(lLines) - 1);
  if (Length(lLines) < 2) or (lLines[0] <> 'DAK_CONTEXT_BEGIN') or
    (lLines[High(lLines)] <> 'DAK_CONTEXT_END') then
    raise EInvalidOpException.Create('Native property export is missing or malformed');
  Result := '';
  for i := 1 to High(lLines) - 1 do
  begin
    if i > 1 then
      Result := Result + sLineBreak;
    Result := Result + lLines[i];
  end;
end;

function TNativeCompilerContext.ReadSnapshotIdentity(const aPathsFileName: string): string;
var
  g: TGarbos;
  lIdentity: TStringBuilder;
  lProperty: string;
begin
  GC(lIdentity, TStringBuilder.Create, g);
  for lProperty in cNativeContextProperties do
    lIdentity.AppendLine(lProperty).AppendLine(ReadProperty(lProperty));
  lIdentity.AppendLine('References').AppendLine(ReadProperty('References'));
  lIdentity.AppendLine(ReadNativeTransport(aPathsFileName, 1024 * 1024));
  Result := THashSHA2.GetHashString(lIdentity.ToString);
end;

function TNativeContextIncludeRefusal.GetIncludeFileContent(const aParentFileName, aIncludeName: string;
  out aContent, aFileName: string): Boolean;
begin
  aContent := '';
  aFileName := '';
  Result := False;
  raise EInvalidOpException.Create('Native main-source includes cannot certify root selection');
end;

function DecodeCapturedSource(const aBytes: TBytes): string;
var
  lBomLength: Integer;
  lEncoding: TEncoding;
begin
  lEncoding := nil;
  lBomLength := TEncoding.GetBufferEncoding(aBytes, lEncoding, TEncoding.UTF8);
  // Match Delphi 12 TFile.ReadAllText's BOM detection and invalid-UTF8 fallback.
  if (lBomLength = 0) and (lEncoding = TEncoding.UTF8) and
    not lEncoding.IsBufferValid(aBytes) then
    lEncoding := TEncoding.ANSI;
  Result := lEncoding.GetString(aBytes, lBomLength, Length(aBytes) - lBomLength);
end;

function ReadNativeTransport(const aFileName: string; const aLimit: Integer): string;
var
  lBytes: TBytes;
  lStream: TFileStream;
begin
  lStream := TFileStream.Create(aFileName, fmOpenRead or fmShareDenyWrite);
  try
    if lStream.Size > aLimit then
      raise EInvalidOpException.Create('native-context-output-too-large: ' + aFileName);
    SetLength(lBytes, Integer(lStream.Size));
    if Length(lBytes) > 0 then
      lStream.ReadBuffer(lBytes[0], Length(lBytes));
    Result := DecodeCapturedSource(lBytes);
  finally
    lStream.Free;
  end;
end;

procedure TNativeCompilerContext.CaptureSourceReferences(const aFileName: string;
  const aIdentity: TStringBuilder);
var
  g: TGarbos;
  lIncludeHandler: IIncludeHandler;
  lInUses: Boolean;
  lLexer: TmwBasePasLex;
  lSourceBytes: TBytes;
  lSourceFileName: string;
  lToken: string;
  lUnitName: string;
begin
  lSourceBytes := fInputLocks.SnapshotBytes(aFileName, aIdentity);
  lIncludeHandler := TNativeContextIncludeRefusal.Create;
  GC(lLexer, TmwBasePasLex.Create, g);
  lLexer.IncludeHandler := lIncludeHandler;
  // Inspect every branch conservatively; the native profile does not supply a source preprocessor here.
  lLexer.UseDefines := False;
  lLexer.Buffer.FileName := aFileName;
  lLexer.Origin := DecodeCapturedSource(lSourceBytes);
  lInUses := False;
  lUnitName := '';
  while lLexer.TokenID <> ptNull do
  begin
    if lInUses and (lLexer.TokenID in [ptIfDirect, ptElseDirect, ptIfEndDirect, ptElseIfDirect,
      ptIfDefDirect, ptIfNDefDirect, ptEndIfDirect, ptIfOptDirect, ptDefineDirect, ptUndefDirect]) then
      raise EInvalidOpException.Create('Conditional native source entries cannot certify root selection');
    if not lLexer.IsJunk then
      case lLexer.TokenID of
        ptUses:
          begin
            lInUses := True;
            lUnitName := '';
          end;
        ptSemiColon:
          lInUses := False;
        ptComma:
          lUnitName := '';
        ptIdentifier, ptPoint:
          if lInUses then
          begin
            lToken := lLexer.Token;
            if (lToken <> '') and (lToken[1] = '&') then
              lToken := Copy(lToken, 2, MaxInt);
            lUnitName := lUnitName + lToken;
          end;
        ptIn:
          if lInUses then
          begin
            if MatchText(lUnitName, ['System', 'SysInit', 'System.System', 'System.SysInit']) then
              raise EInvalidOpException.Create('Explicit native root source selection is unsupported');
            lLexer.NextNoJunk;
            if (lUnitName = '') or (lLexer.TokenID <> ptStringConst) then
              raise EInvalidOpException.Create('Native source reference cannot be verified');
            lToken := lLexer.Token;
            if (Length(lToken) < 2) or (lToken[1] <> '''') or (lToken[Length(lToken)] <> '''') then
              raise EInvalidOpException.Create('Native source reference path cannot be verified');
            lSourceFileName := StringReplace(Copy(lToken, 2, Length(lToken) - 2), '''''', '''', [rfReplaceAll]);
            if not TPath.IsPathRooted(lSourceFileName) then
              lSourceFileName := TPath.Combine(TPath.GetDirectoryName(aFileName), lSourceFileName);
            lSourceFileName := TPath.GetFullPath(lSourceFileName);
            fInputLocks.Snapshot(lSourceFileName, aIdentity);
            fPaths := [TPath.GetDirectoryName(lSourceFileName)] + fPaths;
            aIdentity.AppendLine('main-source-reference').AppendLine(lSourceFileName);
            lLexer.NextNoJunk;
            if not (lLexer.TokenID in [ptComma, ptSemiColon]) then
              raise EInvalidOpException.Create('Native source reference suffix cannot be verified');
            Continue;
          end;
      end;
    lLexer.Next;
  end;
end;

procedure ValidateNativeContextXml(const aFileName: string; const aProjectImports,
  aRejectTargets: Boolean);
var
  i: Integer;
  g: TGarbos;
  lAttribute: IDOMNode;
  lDocument: IDOMDocument;
  lName: string;
  lNode: IDOMNode;
  lPersist: IDOMPersist;
  lPending: TQueue<IDOMNode>;
  lStream: TFileStream;
begin
  lDocument := OmniXML4Factory.DOMImplementation.createDocument('', '', nil);
  // Parse original bytes so the XML declaration and BOM retain their actual encoding.
  GC(lStream, TFileStream.Create(aFileName, fmOpenRead or fmShareDenyWrite), g);
  if lStream.Size > 4 * 1024 * 1024 then
    raise EInvalidOpException.Create('native-context-output-too-large: ' + aFileName);
  if (not Supports(lDocument, IDOMPersist, lPersist)) or (not lPersist.loadFromStream(lStream)) then
    raise EInvalidOpException.Create('Native MSBuild context XML cannot be verified');
  GC(lPending, TQueue<IDOMNode>.Create, g);
  lPending.Enqueue(lDocument.documentElement);
  while lPending.Count > 0 do
  begin
    lNode := lPending.Dequeue;
    if lNode.nodeType = ELEMENT_NODE then
    begin
      if (lNode.namespaceURI <> '') and
        (lNode.namespaceURI <> 'http://schemas.microsoft.com/developer/msbuild/2003') then
        raise EInvalidOpException.Create('Unknown native MSBuild context namespace');
      lName := lNode.localName;
      if lName = '' then
        lName := lNode.nodeName;
      if SameText(lName, 'GlobalOptionFile') or
        (aRejectTargets and MatchText(lName, ['Target', 'UsingTask'])) then
        raise EInvalidOpException.Create('Custom native MSBuild context is unsupported');
      if SameText(lName, 'Import') then
      begin
        lAttribute := lNode.attributes.getNamedItem('Project');
        if (not aProjectImports) or (lAttribute = nil) or
          (not SameText(lAttribute.nodeValue, '$(BDS)\Bin\CodeGear.Delphi.Targets')) then
          raise EInvalidOpException.Create('Custom native MSBuild imports are unsupported');
      end;
    end;
    for i := 0 to lNode.childNodes.length - 1 do
      lPending.Enqueue(lNode.childNodes[i]);
  end;
end;

procedure TNativeCompilerContext.Capture;
var
  g: TGarbos;
  lAlias: string;
  lComment: TMatch;
  lCompilerName: string;
  lIdentity: TStringBuilder;
  lImportedFile: string;
  lLine: string;
  lMatch: TMatch;
  lMetadata: string;
  lPath: string;
  lPreprocessed: string;
  lProperty: string;
  lSourceFileName: string;
  lTargetFileName: string;
  lTargets: TStringBuilder;
  lUnitPathsFileName: string;
begin
  lCompilerName := TPath.GetFileName(fInvocation.fCompilerFileName);
  if (not SameText(lCompilerName, 'dcc32.exe')) and (not SameText(lCompilerName, 'dcc64.exe')) then
    raise EInvalidOpException.Create('Unsupported native compiler');
  GC(lIdentity, TStringBuilder.Create, g);
  GC(lTargets, TStringBuilder.Create, g);
  begin
    lIdentity.AppendLine('native-target-root-context-v1').AppendLine(fInvocation.fPropertyArguments);
    RetainInput(fInvocation.fProjectFileName, lIdentity);
    RetainInput(fInvocation.fMsBuildFileName, lIdentity);
    RetainInput(fInvocation.fCompilerFileName, lIdentity);
    RetainInput(CombinePath([fInvocation.fSdkRoot, 'bin', 'Borland.Build.Tasks.Delphi.dll']), lIdentity);
    RetainInput(CombinePath([fInvocation.fSdkRoot, 'bin', 'Borland.Build.Tasks.Shared.dll']), lIdentity);
    lPreprocessed := Preprocess('original');
    fPreprocessed := lPreprocessed;
    // MSBuild 4 supplies evaluated import paths in /pp comments. Unknown formats fail closed.
    for lComment in TRegEx.Matches(lPreprocessed, '<!--(.*?)-->', [roSingleLine]) do
    begin
      if not TRegEx.IsMatch(lComment.Groups[1].Value, '<\s*(?:[\w.-]+:)?Import\b', [roIgnoreCase]) then
        Continue;
      lMatch := TRegEx.Match(lComment.Groups[1].Value, '(?m)^\s*([A-Za-z]:[^\r\n<>]+)\s*$');
      if not lMatch.Success then
      begin
        // MSBuild retains an absent conditional import as one self-closing XML element.
        // An expanded import must disclose its evaluated file path; unknown formats cannot certify it.
        if not TRegEx.IsMatch(Trim(lComment.Groups[1].Value), '^<\s*Import\b[^<>]*/\s*>$', [roIgnoreCase]) then
          raise EInvalidOpException.Create('Native evaluated import path cannot be verified');
        Continue;
      end;
      lImportedFile := Trim(lMatch.Groups[1].Value);
      if not StartsText(IncludeTrailingPathDelimiter(TPath.GetFullPath(fInvocation.fSdkRoot)),
        TPath.GetFullPath(lImportedFile)) then
      begin
        ValidateNativeContextXml(lImportedFile, False, True);
      end;
      RetainInput(lImportedFile, lIdentity);
    end;
    ValidateNativeContextXml(fInvocation.fProjectFileName, True, True);
    ValidateNativeContextXml(TPath.Combine(fRunRoot, 'original.xml'), False, False);
    if ContainsText(fInvocation.fEnvironmentBlock, 'GlobalOptionFile=') then
      raise EInvalidOpException.Create('Custom native MSBuild context is unsupported');
    lTargetFileName := TransportFile('context.targets');
    lTargets.Append('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">')
      .Append('<Target Name="DakRootContextSnapshot">');
    for lProperty in cNativeContextProperties do
      lTargets.Append('<WriteLinesToFile File="').Append(XmlAttribute(TransportFile(lProperty + '.txt'))).Append('" Lines="DAK_CONTEXT_BEGIN;$(').Append(lProperty)
        .Append(');DAK_CONTEXT_END" Overwrite="true" />');
    lTargets.Append('<WriteLinesToFile File="').Append(XmlAttribute(TransportFile('References.txt'))).Append('" Lines="DAK_CONTEXT_BEGIN;@(DCCReference);DAK_CONTEXT_END" Overwrite="true" />');
    lTargets.Append('</Target></Project>');
    TFile.WriteAllText(lTargetFileName, lTargets.ToString, TEncoding.UTF8);
    lUnitPathsFileName := TransportFile('paths.cmds');
    fSnapshotArguments := '/t:__RemoveLatestBackSlashFromPaths,__GenerateUnitSearchPathFile,DakRootContextSnapshot ' +
      '/p:DCC_ForceExecute=true /p:DCC_Quiet=true /p:DCC_UseMSBuildExternally=true ' +
      '/p:DCC_UseResponseFile=1 /p:DCC_UseCommandFile=1 /p:CmdsFileOutput="' + lUnitPathsFileName +
      '" /p:GlobalOptionFile="' + lTargetFileName + '" /nologo /v:q';
    if not RunMetadata(fSnapshotArguments, 'snapshot') then
      raise EInvalidOpException.Create('Native MSBuild context snapshot failed');
    fSnapshotIdentity := ReadSnapshotIdentity(lUnitPathsFileName);
    // Retain our metadata target too; its generated transport path is excluded from the public identity.
    lTargets.Clear;
    RetainInput(lTargetFileName, lTargets);
    for lProperty in cNativeContextProperties do
    begin
      lMetadata := ReadProperty(lProperty);
      if lProperty = 'GlobalOptionFile' then
      begin
        if not SameText(Trim(lMetadata), lTargetFileName) then
          raise EInvalidOpException.Create('Native snapshot import was overridden');
        // Our fresh metadata target path is transport, not a target compiler input.
        lIdentity.AppendLine(lProperty).AppendLine('<owned metadata snapshot>');
      end else
        lIdentity.AppendLine(lProperty).AppendLine(lMetadata);
      if ((lProperty = 'DCC_AdditionalSwitches') or (lProperty = 'DCC_UsePackage') or
        (lProperty = 'PreBuildEvent') or (lProperty = 'PostBuildEvent') or
        (lProperty = 'DCC_DefaultNamespace') or (lProperty = 'DCC_ToolExe') or
        (lProperty = 'DCC_PreferredToolArchitecture') or (lProperty = 'DCC_IgnoreCommandLine')) and
        (Trim(lMetadata) <> '') then
        raise EInvalidOpException.Create('Additional compiler switches, packages or unit namespaces are unsupported');
      if (lProperty = 'BDS') and (not SameText(TPath.GetFullPath(Trim(lMetadata)),
        TPath.GetFullPath(fInvocation.fSdkRoot))) then
        raise EInvalidOpException.Create('Native SDK root was overridden');
    end;
    // Retain evaluated values from this snapshot, rather than rereading mutable exports later.
    fSourceProfile.fDefines := ReadProperty('DCC_Define');
    fSourceProfile.fIncludePaths := ReadProperty('DCC_IncludePath');
    fSourceProfile.fPlatform := ReadProperty('Platform');
    fSourceProfile.fConfiguration := ReadProperty('Config');
    fSourceProfile.fUnitAliases := ReadProperty('UnitAliases');
    fSourceProfile.fUnitScopeNames := ReadProperty('DCC_Namespace');
    for lLine in fSourceProfile.fUnitScopeNames.Split([#13, #10], TStringSplitOptions.ExcludeEmpty) do
      if not TRegEx.IsMatch(Trim(lLine),
        '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$') then
        raise EInvalidOpException.Create('Invalid root lookup namespace');
    for lAlias in ReadProperty('UnitAliases').Split([#13, #10], TStringSplitOptions.ExcludeEmpty) do
      if TRegEx.IsMatch(lAlias, '^\s*(System|SysInit)\s*=', [roIgnoreCase]) then
        raise EInvalidOpException.Create('Native root unit aliases are unsupported');
    // The original import graph must still be identical after the snapshot.
    if Preprocess('after-snapshot') <> lPreprocessed then
      raise EInvalidOpException.Create('Native MSBuild context changed during capture');
    for lLine in ReadNativeTransport(lUnitPathsFileName, 1024 * 1024).Split(
      [#13, #10], TStringSplitOptions.ExcludeEmpty) do
    begin
      if not StartsText('-U"', lLine) or (not EndsText('"', lLine)) then
        raise EInvalidOpException.Create('Unknown native unit search path format');
      lPath := Copy(lLine, 4, Length(lLine) - 4);
      if ContainsText(lPath, '$(') then
        raise EInvalidOpException.Create('Unresolved native unit search path');
      if not TPath.IsPathRooted(lPath) then
        lPath := TPath.Combine(TPath.GetDirectoryName(fInvocation.fProjectFileName), lPath);
      lPath := TPath.GetFullPath(lPath);
      fPaths := fPaths + [lPath];
      lIdentity.AppendLine(lPath);
    end;
    fUnitPaths := Copy(fPaths);
    lMetadata := Trim(ReadProperty('DCC_DcuOutput'));
    if lMetadata <> '' then
    begin
      if not TPath.IsPathRooted(lMetadata) then
        lMetadata := TPath.Combine(TPath.GetDirectoryName(fInvocation.fProjectFileName), lMetadata);
      fPaths := [TPath.GetFullPath(lMetadata)] + fPaths;
    end;
    fPaths := [TPath.GetDirectoryName(fInvocation.fProjectFileName)] + fPaths;
    lSourceFileName := Trim(ReadProperty('MainSource'));
    if not TPath.IsPathRooted(lSourceFileName) then
      lSourceFileName := TPath.Combine(TPath.GetDirectoryName(fInvocation.fProjectFileName), lSourceFileName);
    fPaths := [TPath.GetDirectoryName(TPath.GetFullPath(lSourceFileName))] + fPaths;
    for lLine in ReadProperty('References').Split([#13, #10], TStringSplitOptions.ExcludeEmpty) do
    begin
      lPath := Trim(lLine);
      if ContainsText(lPath, '$(') then
        raise EInvalidOpException.Create('Unresolved native source reference');
      if not TPath.IsPathRooted(lPath) then
        lPath := TPath.Combine(TPath.GetDirectoryName(fInvocation.fProjectFileName), lPath);
      lPath := TPath.GetDirectoryName(TPath.GetFullPath(lPath));
      fPaths := [lPath] + fPaths;
      lIdentity.AppendLine('reference-directory').AppendLine(lPath);
    end;
    CaptureSourceReferences(lSourceFileName, lIdentity);
    for lPath in fPaths do
      if FileExists(TPath.Combine(lPath, 'System.dcu')) then
      begin
        fLibraryDirectory := lPath;
        Break;
      end;
    if (fLibraryDirectory = '') or
      (not StartsText(IncludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(fInvocation.fSdkRoot, 'lib'))),
        IncludeTrailingPathDelimiter(fLibraryDirectory))) or (not RootSelectionIsCurrent) then
      raise EInvalidOpException.Create('Native target does not select an isolated shipped RTL root');
    RetainInput(TPath.Combine(fLibraryDirectory, 'System.dcu'), lIdentity);
    RetainInput(TPath.Combine(fLibraryDirectory, 'SysInit.dcu'), lIdentity);
    fFingerprint := THashSHA2.GetHashString(lIdentity.ToString);
  end;
end;

function TNativeCompilerContext.RootSelectionIsCurrent: Boolean;
var
  lExtension: string;
  lName: string;
  lPath: string;
  lSelectedPath: string;
begin
  Result := FileExists(TPath.Combine(fLibraryDirectory, 'System.dcu')) and
    FileExists(TPath.Combine(fLibraryDirectory, 'SysInit.dcu'));
  if not Result then
    Exit;
  for lName in ['System', 'SysInit'] do
  begin
    lSelectedPath := '';
    for lPath in fPaths do
      for lExtension in ['.pas', '.dcu'] do
        if FileExists(TPath.Combine(lPath, lName + lExtension)) then
        begin
          if (lExtension <> '.dcu') or
            (not StartsText(IncludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(fInvocation.fSdkRoot, 'lib'))),
              IncludeTrailingPathDelimiter(lPath))) then
            Exit(False);
          if lSelectedPath = '' then
            lSelectedPath := lPath;
        end;
    if not SameText(lSelectedPath, fLibraryDirectory) then
      Exit(False);
  end;
end;

function TNativeCompilerContext.CompilerFileName: string;
begin
  Result := fInvocation.fCompilerFileName;
end;

function TNativeCompilerContext.RootLibraryDirectory: string;
begin
  Result := fLibraryDirectory;
end;

function TNativeCompilerContext.RootSelectionPaths: TArray<string>;
begin
  Result := Copy(fPaths);
end;

function TNativeCompilerContext.UnitSearchPaths: TArray<string>;
begin
  Result := Copy(fUnitPaths);
end;

function TNativeCompilerContext.SourceProfile: TDakNativeCompilerSourceProfile;
begin
  Result := fSourceProfile;
end;

function TNativeCompilerContext.CapturedFingerprint: string;
begin
  Result := fFingerprint;
end;

function TNativeCompilerContext.CapturedInputsAreCurrent: Boolean;
begin
  Result := fInputLocks.InputsAreCurrent and RootSelectionIsCurrent;
end;

function TNativeCompilerContext.RevalidationCount: Integer;
begin
  Result := fValidationIndex;
end;

function TNativeCompilerContext.EvidenceFingerprint: string;
begin
  if InputsAreCurrent then
    Result := fFingerprint
  else
    Result := '';
end;

function TNativeCompilerContext.InputsAreCurrent: Boolean;
var
  lArguments: string;
  lPathsFileName: string;
begin
  // Immutable inputs stay read-locked; mutable source uses identity and content snapshots.
  // Directory absence is observed again at each proof use;
  // it does not isolate directories against a concurrent creator.
  try
    Inc(fValidationIndex);
    // The SDK may append unit paths to an existing response file. Each evaluation needs a fresh file.
    lPathsFileName := TransportFile('paths-current.cmds');
    if TFile.Exists(lPathsFileName) and (not DeleteFile(PChar(lPathsFileName))) then
    begin
      fFailed := True;
      Exit(False);
    end;
    lArguments := StringReplace(fSnapshotArguments, TransportFile('paths.cmds'),
      lPathsFileName, []);
    Result := fInputLocks.InputsAreCurrent and RootSelectionIsCurrent and
      (Preprocess('revalidate') = fPreprocessed) and
      RunMetadata(lArguments, 'snapshot-current') and
      (ReadSnapshotIdentity(lPathsFileName) = fSnapshotIdentity) and
      fInputLocks.InputsAreCurrent and RootSelectionIsCurrent;
  except
    // Optional evidence remains unavailable when revalidation cannot read or launch.
    Result := False;
  end;
  fFailed := fFailed or (not Result);
end;

function TryCaptureNativeCompilerContext(const aInvocation: TDakNativeCompilerInvocation;
  const aRunner: IBuildProcessRunner; out aReason: string): IDakNativeCompilerContext;
begin
  Result := nil;
  aReason := '';
  try
    Result := TNativeCompilerContext.Create(aInvocation, aRunner);
  except
    on E: Exception do
      aReason := E.Message;
  end;
end;

end.
