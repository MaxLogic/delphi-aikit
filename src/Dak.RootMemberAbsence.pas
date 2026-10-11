unit Dak.RootMemberAbsence;

interface

uses
  System.SysUtils,
  DelphiSemantics.RootMemberAbsence,
  Dak.RemoveWith.Model, Dak.Types;

type
  IDakNativeRootProofMetrics = interface
    ['{F9778409-3028-4286-9AAB-03C82C1CD414}']
    function NativeRevalidationCount: Integer;
  end;

  IDakNativeWitnessIO = interface
    ['{DC071F77-F047-47A0-BB5D-695DC1AF179F}']
    procedure WriteText(const aFileName, aText: string; const aEncoding: TEncoding);
    function ReadTextBounded(const aFileName: string; const aLimit: Integer;
      const aEncoding: TEncoding): string;
    function FlushOutput(const aHandle: NativeUInt): Boolean;
  end;

function FinalizeNativeRootProof(const aGuard: IDakRemoveWithPlanInputGuard;
  out aFingerprint, aProvenance, aReason: string): Boolean;

function CreateNativeWitnessIO: IDakNativeWitnessIO;

function TryCreateNativeImplicitRootMemberAbsence(const aCompilerFileName,
  aSdkLibraryDirectory, aWorkRoot: string; out aReason: string):
  IDelphiSemanticImplicitRootMemberAbsence; overload;

function TryCreateNativeImplicitRootMemberAbsence(const aCompilerFileName,
  aSdkLibraryDirectory, aWorkRoot: string; const aIO: IDakNativeWitnessIO;
  out aReason: string): IDelphiSemanticImplicitRootMemberAbsence; overload;

function TryCreateNativeRootRequestOwner(const aOptions: TAppOptions;
  out aGuard: IDakRemoveWithPlanInputGuard; out aReason: string):
  IDelphiSemanticImplicitRootMemberAbsence;

implementation

uses
  System.Classes, System.Generics.Collections, System.Hash, System.IOUtils, System.JSON,
  System.RegularExpressions, System.StrUtils,
  Winapi.Windows,
  AutoFree,
  maxLogic.StrUtils,
  DelphiSemantics.Cache, DelphiSemantics.CompilerProfile, DelphiSemantics.ProjectContext,
  DelphiSemantics.Source,
  Dak.Build.NativeContext, Dak.Build.Runner, Dak.ExternalToolProcess, Dak.NativeInputLocks;

function FinalizeNativeRootProof(const aGuard: IDakRemoveWithPlanInputGuard;
  out aFingerprint, aProvenance, aReason: string): Boolean;
var
  lProvenance: IDakRemoveWithNativeProofProvenance;
  lUsage: IDakRemoveWithNativeProofUsage;
begin
  aFingerprint := '';
  aProvenance := '';
  aReason := '';
  Result := False;
  try
    if aGuard = nil then
      Exit(True);
    aFingerprint := aGuard.ProofFingerprint;
    if aFingerprint = '' then
    begin
      if Supports(aGuard, IDakRemoveWithNativeProofUsage, lUsage) and lUsage.ProofWasUsed then
        aReason := 'native-request-inputs-changed'
      else
        Exit(True);
    end else if aGuard.ValidateInputs(aFingerprint, aReason) then
    begin
      if Supports(aGuard, IDakRemoveWithNativeProofProvenance, lProvenance) then
        aProvenance := lProvenance.ProvenanceJson;
      Exit(True);
    end;
  except
    on E: Exception do
      aReason := 'native-root-proof-finalization-failed: ' + E.ClassName + ': ' + E.Message;
  end;
  // Never leave a partially captured proof on a refused plan.
  aFingerprint := '';
  aProvenance := '';
end;

const
  cProofSchema = 'native-implicit-root-absence-v1';
  // Winapi.Windows marks this Windows-only flag PLATFORM. Our tool is native
  // Windows; retain its verified Win32 API value without a compiler warning.
  cOpenReparsePoint = $00200000;

type
  TNativeWitnessIO = class(TInterfacedObject, IDakNativeWitnessIO)
  public
    procedure WriteText(const aFileName, aText: string; const aEncoding: TEncoding);
    function ReadTextBounded(const aFileName: string; const aLimit: Integer;
      const aEncoding: TEncoding): string;
    function FlushOutput(const aHandle: NativeUInt): Boolean;
  end;

  TNativeImplicitRootMemberAbsence = class(TInterfacedObject,
    IDelphiSemanticImplicitRootMemberAbsence)
  private
    type
      TRunArtifacts = record
        fRoot: string;
        fIdentity: TByHandleFileInformation;
        fFiles: TArray<string>;
      end;
  private
    fCompilerFileName: string;
    fSdkLibraryDirectory: string;
    fWorkRoot: string;
    fFingerprint: string;
    fInputLocks: TDakNativeInputLocks;
    fMemo: TDictionary<string, Boolean>;
    fIO: IDakNativeWitnessIO;
    fArtifacts: TList<TRunArtifacts>;
    procedure RegisterArtifacts(const aRoot, aProgramName, aProbeName, aWitnessName: string);
    procedure CleanupArtifacts;
    function RunCaptured(const aExePath, aArguments, aRunRoot,
      aLogName: string): Boolean;
    function DependenciesMatch(const aRunRoot, aProgramName,
      aWitnessName, aProbeName: string): Boolean;
    function ProveNameAbsent(const aName: string): Boolean;
    procedure RetainInput(const aFileName: string; const aIdentity: TStringBuilder);
  public
    constructor Create(const aCompilerFileName, aSdkLibraryDirectory, aWorkRoot: string;
      const aIO: IDakNativeWitnessIO);
    destructor Destroy; override;
    function EvidenceFingerprint: string;
    function IsNameAbsent(const aName: string): Boolean;
  end;

procedure TNativeWitnessIO.WriteText(const aFileName, aText: string; const aEncoding: TEncoding);
var
  g: TGarbos;
  lStream: TFileStream;
  lBytes: TBytes;
begin
  lBytes := aEncoding.GetBytes(aText);
  GC(lStream, TFileStream.Create(aFileName, fmCreate), g);
  if Length(lBytes) > 0 then
    lStream.WriteBuffer(lBytes[0], Length(lBytes));
  if not FlushFileBuffers(lStream.Handle) then
    RaiseLastOSError;
end;

function TNativeWitnessIO.ReadTextBounded(const aFileName: string; const aLimit: Integer;
  const aEncoding: TEncoding): string;
var
  g: TGarbos;
  lStream: TFileStream;
  lBytes: TBytes;
begin
  GC(lStream, TFileStream.Create(aFileName, fmOpenRead or fmShareDenyWrite), g);
  if (aLimit < 0) or (lStream.Size > aLimit) then
    raise EReadError.Create('Native witness output exceeded its size limit');
  SetLength(lBytes, lStream.Size);
  if Length(lBytes) > 0 then
    lStream.ReadBuffer(lBytes[0], Length(lBytes));
  Result := aEncoding.GetString(lBytes);
end;

function TNativeWitnessIO.FlushOutput(const aHandle: NativeUInt): Boolean;
begin
  Result := FlushFileBuffers(aHandle);
end;

function CreateNativeWitnessIO: IDakNativeWitnessIO;
begin
  Result := TNativeWitnessIO.Create;
end;

function Quoted(const aValue: string): string;
begin
  Result := '"' + aValue + '"';
end;

function NewTag: string;
var
  lGuid: TGUID;
begin
  CreateGUID(lGuid);
  Result := StringReplace(StringReplace(StringReplace(GUIDToString(lGuid),
    '{', '', [rfReplaceAll]), '}', '', [rfReplaceAll]), '-', '', [rfReplaceAll]);
end;

function IsPlainIdentifier(const aName: string): Boolean;
var
  i: Integer;
begin
  Result := (aName <> '') and (Length(aName) <= 255) and
    CharInSet(aName[1], ['A'..'Z', 'a'..'z', '_']);
  if not Result then
    Exit;
  for i := 2 to Length(aName) do
    if not CharInSet(aName[i], ['A'..'Z', 'a'..'z', '_', '0'..'9']) then
      Exit(False);
end;

procedure TNativeImplicitRootMemberAbsence.RetainInput(const aFileName: string;
  const aIdentity: TStringBuilder);
begin
  fInputLocks.Retain(aFileName, aIdentity);
end;

constructor TNativeImplicitRootMemberAbsence.Create(const aCompilerFileName,
  aSdkLibraryDirectory, aWorkRoot: string; const aIO: IDakNativeWitnessIO);
var
  lIdentity: TStringBuilder;
begin
  inherited Create;
  fIO := aIO;
  if fIO = nil then
    raise EArgumentNilException.Create('Native witness IO is required');
  fCompilerFileName := TPath.GetFullPath(aCompilerFileName);
  fSdkLibraryDirectory := TPath.GetFullPath(aSdkLibraryDirectory);
  fWorkRoot := TPath.Combine(TPath.GetFullPath(aWorkRoot), 'root-member-absence');
  fInputLocks := TDakNativeInputLocks.Create;
  fMemo := TDictionary<string, Boolean>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fArtifacts := TList<TRunArtifacts>.Create;
  lIdentity := TStringBuilder.Create;
  try
    lIdentity.AppendLine(cProofSchema).AppendLine('--no-config -B --depends SDK-only');
    RetainInput(fCompilerFileName, lIdentity);
    RetainInput(TPath.Combine(fSdkLibraryDirectory, 'System.dcu'), lIdentity);
    RetainInput(TPath.Combine(fSdkLibraryDirectory, 'SysInit.dcu'), lIdentity);
    fFingerprint := THashSHA2.GetHashString(lIdentity.ToString);
  finally
    lIdentity.Free;
  end;
end;

destructor TNativeImplicitRootMemberAbsence.Destroy;
begin
  CleanupArtifacts;
  fArtifacts.Free;
  fMemo.Free;
  fInputLocks.Free;
  inherited;
end;

function TryReadDirectoryIdentity(const aPath: string;
  out aInformation: TByHandleFileInformation): Boolean;
var
  lHandle: THandle;
begin
  aInformation := Default(TByHandleFileInformation);
  lHandle := CreateFile(PChar(aPath), FILE_READ_ATTRIBUTES,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or cOpenReparsePoint, 0);
  if lHandle = INVALID_HANDLE_VALUE then
    Exit(False);
  try
    Result := GetFileInformationByHandle(lHandle, aInformation) and
      ((aInformation.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT) = 0);
  finally
    CloseHandle(lHandle);
  end;
end;

procedure TNativeImplicitRootMemberAbsence.RegisterArtifacts(const aRoot,
  aProgramName, aProbeName, aWitnessName: string);
var
  lArtifacts: TRunArtifacts;
begin
  lArtifacts := Default(TRunArtifacts);
  lArtifacts.fRoot := aRoot;
  if not TryReadDirectoryIdentity(aRoot, lArtifacts.fIdentity) then
    raise EInvalidOpException.Create('Witness directory identity cannot be retained');
  lArtifacts.fFiles := [aProgramName + '.dpr', aProgramName + '.exe', aProgramName + '.d',
    aWitnessName + '.pas', aWitnessName + '.dcu', aProbeName + '.pas', aProbeName + '.dcu',
    'compiler.log', 'compiler.log.status', 'runtime.log', 'runtime.log.status', 'result.txt', 'refusal.txt'];
  fArtifacts.Add(lArtifacts);
end;

procedure TNativeImplicitRootMemberAbsence.CleanupArtifacts;
var
  lArtifacts: TRunArtifacts;
  lCurrent: TByHandleFileInformation;
  lFileName: string;
begin
  if fArtifacts = nil then
    Exit;
  for lArtifacts in fArtifacts do
  begin
    try
      if (not TryReadDirectoryIdentity(lArtifacts.fRoot, lCurrent)) or
        (lCurrent.dwVolumeSerialNumber <> lArtifacts.fIdentity.dwVolumeSerialNumber) or
        (lCurrent.nFileIndexHigh <> lArtifacts.fIdentity.nFileIndexHigh) or
        (lCurrent.nFileIndexLow <> lArtifacts.fIdentity.nFileIndexLow) then
      begin
        OutputDebugString(PChar('DAK-412 witness cleanup refused after directory identity change: ' +
          lArtifacts.fRoot));
        Continue;
      end;
      // Delete only our exact generated flat filenames. Unknown files or a
      // changed directory identity remain untouched; no recursive cleanup.
      for lFileName in lArtifacts.fFiles do
        if TFile.Exists(TPath.Combine(lArtifacts.fRoot, lFileName)) then
          TFile.Delete(TPath.Combine(lArtifacts.fRoot, lFileName));
      TDirectory.Delete(lArtifacts.fRoot, False);
    except
      on E: Exception do
        OutputDebugString(PChar('DAK-412 witness cleanup incomplete: ' + E.Message));
    end;
  end;
end;

function TNativeImplicitRootMemberAbsence.EvidenceFingerprint: string;
begin
  if fInputLocks.InputsAreCurrent then
    Result := fFingerprint
  else
    Result := '';
end;

function TNativeImplicitRootMemberAbsence.RunCaptured(const aExePath, aArguments,
  aRunRoot, aLogName: string): Boolean;
var
  lError: string;
  lExitCode: Cardinal;
  lInput: THandle;
  lOptions: TExternalToolProcessRunOptions;
  lOutput: THandle;
  lSecurity: TSecurityAttributes;
  lTimedOut: Boolean;
begin
  Result := False;
  lSecurity := Default(TSecurityAttributes);
  lSecurity.nLength := SizeOf(lSecurity);
  lSecurity.bInheritHandle := True;
  lInput := CreateFile('NUL', GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
    @lSecurity, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if lInput = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
  try
    lOutput := CreateFile(PChar(TPath.Combine(aRunRoot, aLogName)), GENERIC_WRITE,
      FILE_SHARE_READ, @lSecurity, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
    if lOutput = INVALID_HANDLE_VALUE then
      RaiseLastOSError;
    try
      lOptions := Default(TExternalToolProcessRunOptions);
      lOptions.fExePath := aExePath;
      lOptions.fArguments := aArguments;
      lOptions.fWorkDir := aRunRoot;
      lOptions.fStdInHandle := lInput;
      lOptions.fStdOutHandle := lOutput;
      lOptions.fStdErrHandle := lOutput;
      lOptions.fCreationFlags := CREATE_NO_WINDOW;
      lOptions.fTimeoutSec := 30;
      Result := TryRunExternalToolProcess(lOptions, lExitCode, lTimedOut, lError) and
        (not lTimedOut) and (lExitCode = 0);
      if not fIO.FlushOutput(lOutput) then
      begin
        lError := 'native-witness-output-flush-failed';
        Result := False;
      end;
      if not Result then
        TFile.WriteAllText(TPath.Combine(aRunRoot, aLogName + '.status'),
          Format('exit=%d; timeout=%s; error=%s',
            [lExitCode, BoolToStr(lTimedOut, True), lError]), TEncoding.UTF8);
    finally
      CloseHandle(lOutput);
    end;
  finally
    CloseHandle(lInput);
  end;
end;

function TNativeImplicitRootMemberAbsence.DependenciesMatch(const aRunRoot,
  aProgramName, aWitnessName, aProbeName: string): Boolean;
var
  i: Integer;
  lExpected: TDictionary<string, Byte>;
  lFileName: string;
  lLines: TArray<string>;
  lLine: string;
begin
  Result := False;
  lFileName := TPath.Combine(aRunRoot, aProgramName + '.d');
  if not TFile.Exists(lFileName) then
    Exit;
  lLines := fIO.ReadTextBounded(lFileName, 1024 * 1024, TEncoding.Default).Split([#13, #10],
    TStringSplitOptions.ExcludeEmpty);
  if Length(lLines) <> 5 then
    Exit;
  if not SameText(Trim(lLines[0]), TPath.Combine(aRunRoot, aProgramName + '.exe') + ': ' +
    TPath.Combine(aRunRoot, aProgramName + '.dpr') + ' \') then
    Exit;
  lExpected := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    lExpected.Add(TPath.Combine(aRunRoot, aWitnessName + '.dcu'), 0);
    lExpected.Add(TPath.Combine(aRunRoot, aProbeName + '.dcu'), 0);
    lExpected.Add(TPath.Combine(fSdkLibraryDirectory, 'System.dcu'), 0);
    lExpected.Add(TPath.Combine(fSdkLibraryDirectory, 'SysInit.dcu'), 0);
    for i := 1 to High(lLines) do
    begin
      lLine := Trim(lLines[i]);
      if EndsText(' \', lLine) then
        lLine := Trim(Copy(lLine, 1, Length(lLine) - 2));
      if not lExpected.ContainsKey(lLine) then
        Exit;
      lExpected.Remove(lLine);
    end;
    Result := lExpected.Count = 0;
  finally
    lExpected.Free;
  end;
end;

function TNativeImplicitRootMemberAbsence.ProveNameAbsent(const aName: string): Boolean;
const
  cWitness = 'unit %s;' + #13#10 +
    'interface' + #13#10 +
    'type TUnique = record fToken: Integer; end;' + #13#10 +
    'procedure Check(var aValue: TUnique);' + #13#10 +
    'function Completed: Boolean;' + #13#10 +
    'implementation' + #13#10 +
    'var CheckCount: Integer;' + #13#10 +
    'procedure Check(var aValue: TUnique);' + #13#10 +
    'begin Inc(CheckCount); end;' + #13#10 +
    'function Completed: Boolean;' + #13#10 +
    'begin Result := CheckCount = 1; end;' + #13#10 +
    'end.';
  cProbe = 'unit %s;' + #13#10 +
    'interface' + #13#10 +
    'uses %s;' + #13#10 +
    'type TProbe = class(System.TObject)' + #13#10 +
    'procedure Run(const aReceiver: TProbe); end;' + #13#10 +
    'var &%s: %s.TUnique;' + #13#10 +
    'implementation' + #13#10 +
    'procedure TProbe.Run(const aReceiver: TProbe);' + #13#10 +
    'begin' + #13#10 +
    '  with aReceiver do' + #13#10 +
    '    %s.Check(&%s);' + #13#10 +
    'end;' + #13#10 +
    'end.';
  cProgram = 'program %s;' + #13#10 +
    '{$APPTYPE CONSOLE}' + #13#10 +
    'uses %s, %s;' + #13#10 +
    'var lProbe: TProbe;' + #13#10 +
    'begin' + #13#10 +
    '  if %s.Completed then' + #13#10 +
    '    Halt(6);' + #13#10 +
    '  lProbe := TProbe.Create;' + #13#10 +
    '  try lProbe.Run(lProbe); finally lProbe.Free; end;' + #13#10 +
    '  if not %s.Completed then' + #13#10 +
    '    Halt(7);' + #13#10 +
    '  WriteLn(''%s''); Flush(Output);' + #13#10 +
    'end.';
var
  g: TGarbos;
  lProofInputs: TDakNativeInputLocks;
  lProofIdentity: TStringBuilder;
  lArguments: string;
  lMarker: string;
  lProbeName: string;
  lProgramName: string;
  lRunRoot: string;
  lTag: string;
  lWitnessName: string;
begin
  Result := False;
  lTag := NewTag;
  lRunRoot := TPath.Combine(fWorkRoot, 'run-' + lTag);
  TDirectory.CreateDirectory(lRunRoot);
  try
    lWitnessName := 'Witness_' + lTag;
    lProbeName := 'Probe_' + lTag;
    lProgramName := 'Native_' + lTag;
    lMarker := 'completed-' + lTag;
    RegisterArtifacts(lRunRoot, lProgramName, lProbeName, lWitnessName);
    fIO.WriteText(TPath.Combine(lRunRoot, lWitnessName + '.pas'),
      Format(cWitness, [lWitnessName]), TEncoding.ASCII);
    fIO.WriteText(TPath.Combine(lRunRoot, lProbeName + '.pas'),
      Format(cProbe, [lProbeName, lWitnessName, aName, lWitnessName,
        lWitnessName, aName]), TEncoding.ASCII);
    fIO.WriteText(TPath.Combine(lRunRoot, lProgramName + '.dpr'),
      Format(cProgram, [lProgramName, lProbeName, lWitnessName,
        lWitnessName, lWitnessName, lMarker]), TEncoding.ASCII);
    GC(lProofInputs, TDakNativeInputLocks.Create, g);
    GC(lProofIdentity, TStringBuilder.Create, g);
    lProofInputs.Retain(TPath.Combine(lRunRoot, lWitnessName + '.pas'), lProofIdentity);
    lProofInputs.Retain(TPath.Combine(lRunRoot, lProbeName + '.pas'), lProofIdentity);
    lProofInputs.Retain(TPath.Combine(lRunRoot, lProgramName + '.dpr'), lProofIdentity);
    lArguments := '--no-config --depends -B -Q -W+ -U' + Quoted(fSdkLibraryDirectory) +
      ' -E' + Quoted(lRunRoot) + ' -N0' + Quoted(lRunRoot) + ' ' +
      Quoted(TPath.Combine(lRunRoot, lProgramName + '.dpr'));
    if not RunCaptured(fCompilerFileName, lArguments, lRunRoot, 'compiler.log') then
      Exit;
    if not DependenciesMatch(lRunRoot, lProgramName, lWitnessName, lProbeName) then
    begin
      TFile.WriteAllText(TPath.Combine(lRunRoot, 'refusal.txt'),
        'Compiler dependencies did not match the locked SDK and generated inputs.', TEncoding.UTF8);
      Exit;
    end;
    lProofInputs.Retain(TPath.Combine(lRunRoot, lProgramName + '.exe'), lProofIdentity);
    if not RunCaptured(TPath.Combine(lRunRoot, lProgramName + '.exe'), '',
      lRunRoot, 'runtime.log') then
      Exit;
    Result := Trim(fIO.ReadTextBounded(TPath.Combine(lRunRoot, 'runtime.log'), 4096,
      TEncoding.ASCII)) = lMarker;
    Result := Result and lProofInputs.InputsAreCurrent;
    TFile.WriteAllText(TPath.Combine(lRunRoot, 'result.txt'),
      Format('schema=%s; name=%s; fingerprint=%s; absent=%s',
        [cProofSchema, aName, fFingerprint, BoolToStr(Result, True)]), TEncoding.UTF8);
  except
    on E: Exception do
    begin
      // Proof is optional; preserve the concrete failure and retain refusal.
      TFile.WriteAllText(TPath.Combine(lRunRoot, 'refusal.txt'), E.Message, TEncoding.UTF8);
      Result := False;
    end;
  end;
end;

function TNativeImplicitRootMemberAbsence.IsNameAbsent(const aName: string): Boolean;
begin
  Result := False;
  if not fInputLocks.InputsAreCurrent then
    Exit;
  if not IsPlainIdentifier(aName) then
    Exit;
  if fMemo.TryGetValue(aName, Result) then
    Exit;
  try
    Result := ProveNameAbsent(aName) and fInputLocks.InputsAreCurrent;
  except
    on E: Exception do
    begin
      // Optional proof must retain refusal even when its scratch log cannot be
      // created. Preserve the failure through the native diagnostic channel.
      OutputDebugString(PChar(Format('DAK-412 optional root proof unavailable: %s', [E.Message])));
      Result := False;
    end;
  end;
  fMemo.Add(aName, Result);
end;

function TryCreateNativeImplicitRootMemberAbsence(const aCompilerFileName,
  aSdkLibraryDirectory, aWorkRoot: string; out aReason: string):
  IDelphiSemanticImplicitRootMemberAbsence;
begin
  Result := TryCreateNativeImplicitRootMemberAbsence(aCompilerFileName,
    aSdkLibraryDirectory, aWorkRoot, CreateNativeWitnessIO, aReason);
end;

function TryCreateNativeImplicitRootMemberAbsence(const aCompilerFileName,
  aSdkLibraryDirectory, aWorkRoot: string; const aIO: IDakNativeWitnessIO;
  out aReason: string): IDelphiSemanticImplicitRootMemberAbsence;
begin
  Result := nil;
  aReason := '';
  if not MatchText(ExtractFileName(aCompilerFileName), ['dcc32.exe', 'dcc64.exe']) then
  begin
    aReason := 'unsupported-native-compiler';
    Exit;
  end;
  try
    Result := TNativeImplicitRootMemberAbsence.Create(aCompilerFileName,
      aSdkLibraryDirectory, aWorkRoot, aIO);
  except
    on E: Exception do
      aReason := E.Message;
  end;
end;

type
  TNativeRootRequestOwner = class(TInterfacedObject,
    IDelphiSemanticImplicitRootMemberAbsence, IDelphiSemanticProjectProfileValidator,
    IDelphiSemanticModelObservationOwner, IDakRemoveWithPlanInputGuard,
    IDakRemoveWithNativeProofProvenance, IDakRemoveWithNativeProofUsage,
    IDakNativeRootProofMetrics)
  private
    fContext: IDakNativeCompilerContext;
    fContextObservation: IDakNativeCompilerContextObservation;
    fProvider: IDelphiSemanticImplicitRootMemberAbsence;
    fSources: TDakNativeInputLocks;
    fIdentity: TStringBuilder;
    fKnownSources: TDictionary<string, string>;
    fProjectFingerprint: string;
    fUsed: Boolean;
    fProvenNames: TDictionary<string, Byte>;
  public
    constructor Create(const aContext: IDakNativeCompilerContext;
      const aProvider: IDelphiSemanticImplicitRootMemberAbsence);
    destructor Destroy; override;
    function EvidenceFingerprint: string;
    function IsNameAbsent(const aName: string): Boolean;
    function ProofFingerprint: string;
    function ProofWasUsed: Boolean;
    function NativeRevalidationCount: Integer;
    function ProvenanceJson: string;
    function ValidateInputs(const aExpectedFingerprint: string; out aReason: string): Boolean;
    function ValidateProjectProfile(const aProject: TDelphiSemanticProjectInfo;
      out aReason: string): Boolean;
    function ValidateModelSources(const aObservation: TDelphiSemanticModelObservation;
      out aReason: string): Boolean;
  end;

constructor TNativeRootRequestOwner.Create(const aContext: IDakNativeCompilerContext;
  const aProvider: IDelphiSemanticImplicitRootMemberAbsence);
begin
  inherited Create;
  fContext := aContext;
  if not Supports(aContext, IDakNativeCompilerContextObservation, fContextObservation) then
    raise EInvalidOpException.Create('Native context observations unavailable');
  fProvider := aProvider;
  fSources := TDakNativeInputLocks.Create;
  fIdentity := TStringBuilder.Create;
  fKnownSources := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fProvenNames := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fIdentity.AppendLine(fContextObservation.CapturedFingerprint).AppendLine(aProvider.EvidenceFingerprint);
end;

destructor TNativeRootRequestOwner.Destroy;
begin
  fProvenNames.Free;
  fKnownSources.Free;
  fIdentity.Free;
  fSources.Free;
  inherited;
end;

function TNativeRootRequestOwner.EvidenceFingerprint: string;
begin
  Result := '';
  if (fProjectFingerprint <> '') and fContextObservation.CapturedInputsAreCurrent and
    (fProvider.EvidenceFingerprint <> '') and fSources.InputsAreCurrent then
    Result := THashSHA2.GetHashString(fIdentity.ToString);
end;

function TNativeRootRequestOwner.NativeRevalidationCount: Integer;
var
  lObservation: IDakNativeCompilerContextObservation;
begin
  if not Supports(fContext, IDakNativeCompilerContextObservation, lObservation) then
    raise EInvalidOpException.Create('Native context observations unavailable');
  Result := lObservation.RevalidationCount;
end;

function TNativeRootRequestOwner.ProofWasUsed: Boolean;
begin
  Result := fUsed;
end;

function TNativeRootRequestOwner.ProofFingerprint: string;
begin
  Result := '';
  if fUsed then
    Result := EvidenceFingerprint;
end;

function TNativeRootRequestOwner.ValidateInputs(const aExpectedFingerprint: string;
  out aReason: string): Boolean;
begin
  aReason := 'native-request-inputs-changed';
  Result := (aExpectedFingerprint <> '') and
    fContext.InputsAreCurrent and (aExpectedFingerprint = EvidenceFingerprint);
  if Result then
    aReason := '';
end;

function TNativeRootRequestOwner.IsNameAbsent(const aName: string): Boolean;
var
  lReason: string;
begin
  Result := ValidateInputs(EvidenceFingerprint, lReason) and fProvider.IsNameAbsent(aName);
  if Result then
  begin
    fUsed := True;
    fProvenNames.AddOrSetValue(aName, 0);
  end;
end;

function TNativeRootRequestOwner.ProvenanceJson: string;
var
  g: TGarbos;
  lJson, lSourceJson: TJSONObject;
  lNames, lSources: TJSONArray;
  lName, lReason: string;
  lSource: TPair<string, string>;
begin
  lReason := 'native-request-inputs-changed';
  if (not fUsed) or (EvidenceFingerprint = '') then
    raise EInvalidOpException.Create(lReason);
  GC(lJson, TJSONObject.Create, g);
  lJson.AddPair('schema', cProofSchema);
  lJson.AddPair('fingerprint', ProofFingerprint);
  lJson.AddPair('nativeContextFingerprint', fContextObservation.CapturedFingerprint);
  lJson.AddPair('semanticContextFingerprint', fProjectFingerprint);
  lJson.AddPair('compiler', fContext.CompilerFileName);
  lJson.AddPair('compilerSha256', THashSHA2.GetHashStringFromFile(fContext.CompilerFileName));
  lJson.AddPair('sdkLibraryDirectory', fContext.RootLibraryDirectory);
  lJson.AddPair('systemSha256', THashSHA2.GetHashStringFromFile(
    TPath.Combine(fContext.RootLibraryDirectory, 'System.dcu')));
  lJson.AddPair('sysInitSha256', THashSHA2.GetHashStringFromFile(
    TPath.Combine(fContext.RootLibraryDirectory, 'SysInit.dcu')));
  lJson.AddPair('protocol', 'nominal-record-private-counter-fresh-completion-marker');
  lNames := TJSONArray.Create;
  lJson.AddPair('absentNames', lNames);
  for lName in fProvenNames.Keys do
    lNames.Add(lName);
  lSources := TJSONArray.Create;
  lJson.AddPair('sources', lSources);
  for lSource in fKnownSources do
  begin
    lSourceJson := TJSONObject.Create;
    lSourceJson.AddPair('file', lSource.Key);
    lSourceJson.AddPair('sha256', lSource.Value);
    lSources.AddElement(lSourceJson);
  end;
  Result := lJson.ToJSON;
end;

function TNativeRootRequestOwner.ValidateProjectProfile(
  const aProject: TDelphiSemanticProjectInfo; out aReason: string): Boolean;
var
  g: TGarbos;
  lProfile: TDakNativeCompilerSourceProfile;
  lNativeDefines, lSemanticDefines: TStringList;
  lDefine: string;
begin
  Result := False;
  aReason := 'native-semantic-source-profile-mismatch';
  lProfile := fContext.SourceProfile;
  if not fContext.InputsAreCurrent then
  begin
    aReason := 'native-request-inputs-changed';
    Exit;
  end;
  if not SameText(aProject.Platform, lProfile.fPlatform) or
    not SameText(aProject.Configuration, lProfile.fConfiguration) then
    Exit;
  GC(lNativeDefines, TStringList.Create, g);
  GC(lSemanticDefines, TStringList.Create, g);
  lNativeDefines.Sorted := True;
  lNativeDefines.Duplicates := dupIgnore;
  lSemanticDefines.Sorted := True;
  lSemanticDefines.Duplicates := dupIgnore;
  for lDefine in lProfile.fDefines.Split([';', #13, #10], TStringSplitOptions.ExcludeEmpty) do
    lNativeDefines.Add(UpperCase(Trim(lDefine)));
  for lDefine in TDelphiSemanticCompilerProfileBuilder.DefinesForPlatform(aProject.Platform) do
    lNativeDefines.Add(UpperCase(lDefine));
  for lDefine in aProject.Defines do
    lSemanticDefines.Add(UpperCase(Trim(lDefine)));
  if lNativeDefines.Text <> lSemanticDefines.Text then
    Exit;
  fProjectFingerprint := aProject.ContextFingerprint;
  fIdentity.AppendLine(fProjectFingerprint);
  aReason := '';
  Result := True;
end;

function TNativeRootRequestOwner.ValidateModelSources(
  const aObservation: TDelphiSemanticModelObservation; out aReason: string): Boolean;
var
  i: Integer;
  lSource: TDelphiSemanticSourceText;
  lPreviousHash: string;
begin
  Result := False;
  aReason := 'native-request-inputs-changed';
  if not fContext.InputsAreCurrent then
    Exit;
  aReason := 'native-request-source-profile-unsupported';
  if (fProjectFingerprint = '') or
    (aObservation.ProjectContextFingerprint <> fProjectFingerprint) or
    (aObservation.SourceObservations = nil) or
    (Length(aObservation.IncludeFileNames) <> 0) then
    Exit;
  for i := 0 to aObservation.SourceObservations.Count - 1 do
  begin
    lSource := aObservation.SourceObservations.Items[i];
    aReason := 'native-request-source-profile-unsupported';
    // Include resolution and compiler predefined conditional symbols need
    // their own parity proof. Until then these source profiles retain refusal.
    if TRegEx.IsMatch(lSource.Text, '\{\$\s*(IF|IFDEF|IFNDEF|IFOPT|DEFINE|UNDEF|I|INCLUDE)\b',
      [roIgnoreCase]) or TRegEx.IsMatch(lSource.Text,
      '\(\*\$\s*(IF|IFDEF|IFNDEF|IFOPT|DEFINE|UNDEF|I|INCLUDE)\b', [roIgnoreCase]) then
      Exit;
    aReason := 'native-request-inputs-changed';
    if fKnownSources.TryGetValue(lSource.FileName, lPreviousHash) then
    begin
      if lPreviousHash <> lSource.ContentHash then
        Exit;
    end else begin
      if not fSources.SnapshotMatching(lSource.FileName, lSource.ContentHash, fIdentity) then
        Exit;
      fKnownSources.Add(lSource.FileName, lSource.ContentHash);
    end;
  end;
  aReason := 'native-request-inputs-changed';
  Result := fSources.InputsAreCurrent and fContextObservation.CapturedInputsAreCurrent;
  if Result then
    aReason := '';
end;

function TryCreateNativeRootRequestOwner(const aOptions: TAppOptions;
  out aGuard: IDakRemoveWithPlanInputGuard; out aReason: string):
  IDelphiSemanticImplicitRootMemberAbsence;
var
  lContext: IDakNativeCompilerContext;
  lProvider: IDelphiSemanticImplicitRootMemberAbsence;
  lWorkRoot: string;
begin
  Result := nil;
  aGuard := nil;
  aReason := 'native-toolchain-not-selected';
  if Trim(aOptions.fDelphiVersion) = '' then
    Exit;
  try
    if not TryReadNativeCompilerContext(aOptions, lContext, aReason) then
      Exit;
    lWorkRoot := TPath.Combine(TPath.GetDirectoryName(aOptions.fDprojPath), '.dak');
    lWorkRoot := TPath.Combine(lWorkRoot, TPath.GetFileNameWithoutExtension(aOptions.fDprojPath));
    lProvider := TryCreateNativeImplicitRootMemberAbsence(lContext.CompilerFileName,
      lContext.RootLibraryDirectory, lWorkRoot, aReason);
    if lProvider = nil then
      Exit;
    Result := TNativeRootRequestOwner.Create(lContext, lProvider);
    if not Supports(Result, IDakRemoveWithPlanInputGuard, aGuard) then
      raise EInvalidOpException.Create('Native request owner has no apply guard');
  except
    on E: Exception do
    begin
      Result := nil;
      aGuard := nil;
      aReason := 'native-request-owner-unavailable: ' + E.ClassName + ': ' + E.Message;
    end;
  end;
end;

end.
