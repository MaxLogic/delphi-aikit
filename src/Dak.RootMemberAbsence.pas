unit Dak.RootMemberAbsence;

interface

uses
  System.SysUtils,
  DelphiSemantics.RootMemberAbsence,
  Dak.RemoveWith.Model, Dak.Types;

type
  TDakNativeRootLookup = record
    fUnitScopeNames: TArray<string>;
    fUnitAliases: TArray<string>;
    fUnitPaths: TArray<string>;
    fSdkLibRoot: string;
  end;

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

function TryCreateNativeRootMemberAbsence(const aCompilerFileName, aSdkLibraryDirectory,
  aWorkRoot: string; const aLookup: TDakNativeRootLookup; const aIO: IDakNativeWitnessIO;
  out aReason: string): IDelphiSemanticImplicitRootMemberAbsence;
function TryCreateNativeRootRequestOwner(const aOptions: TAppOptions;
  out aGuard: IDakRemoveWithPlanInputGuard; out aReason: string):
  IDelphiSemanticImplicitRootMemberAbsence;

implementation

uses
  System.Classes, System.Diagnostics, System.Generics.Collections, System.Hash, System.IOUtils, System.JSON,
  System.RegularExpressions, System.StrUtils,
  Winapi.Windows,
  AutoFree,
  maxLogic.ioutils, maxLogic.StrUtils,
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
  cNativeWitness = 'unit %s;' + #13#10 +
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


type
  TNativeWitnessIO = class(TInterfacedObject, IDakNativeWitnessIO)
  public
    procedure WriteText(const aFileName, aText: string; const aEncoding: TEncoding);
    function ReadTextBounded(const aFileName: string; const aLimit: Integer;
      const aEncoding: TEncoding): string;
    function FlushOutput(const aHandle: NativeUInt): Boolean;
  end;

  IDakNativeNamedRootEvidence = interface
    ['{CB1B0D98-B285-4EE7-9768-E8BD026D7418}']
    function IsNamedRootMemberAbsentInto(const aRoot: TDelphiSemanticQualifiedRootType;
      const aSiteUnits: TArray<string>; const aName: string;
      const aIdentity: TStringBuilder): Boolean;
    procedure AddNamedProvenance(const aJson: TJSONObject);
  end;

  TNativeImplicitRootMemberAbsence = class(TInterfacedObject,
    IDelphiSemanticImplicitRootMemberAbsence, IDelphiSemanticNamedRootMemberAbsence,
    IDakNativeNamedRootEvidence)
  private
    type
      TNamedAbsence = record
        fRoot: string;
        fUnits: TArray<string>;
        fDeclarationUnits: TArray<string>;
        fName: string;
      end;
      TRunArtifacts = record
        fRoot: string;
        fIdentity: TByHandleFileInformation;
        fFiles: TArray<string>;
      end;
  private
    fLookup: TDakNativeRootLookup;
    fResolved: TDictionary<string, string>;
    fProbeUnits: TDictionary<string, string>;
    fNamedMemo: TDictionary<string, Boolean>;
    fUnitSelectionMemo: TDictionary<string, Boolean>;
    fUnitSelectionFingerprint: string;
    fSelectionSnapshot: string;
    fUnitSelectionChecks, fUnitSelectionMemoHits: Int64;
    fClosures: TDictionary<string, TArray<string>>;
    fSdkDependencies: TDictionary<string, string>;
    fNamedAbsences: TList<TNamedAbsence>;
    fNamedQueryCount, fNamedMilliseconds: Int64;
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
    function SelectionSnapshot: string;
    function UnitSelectionIsCurrent(const aName: string): Boolean;
    function CheckUnitSelection(const aName: string): Boolean;
    function NamedSelectionIsCurrent(const aUnits: TArray<string>): Boolean;
    function NamedDependenciesMatch(const aRunRoot, aProgramName: string;
      const aGenerated: TArray<string>; const aIdentity: TStringBuilder;
      out aDependencies: TArray<string>): Boolean;
    procedure RegisterNamedArtifacts(const aRoot, aProgramName: string;
      const aUnits: TArray<string>);
    function CleanupRunArtifacts(const aIndex: Integer): Boolean;
    function RunNamedProgram(const aRunRoot, aProgramName: string;
      const aGenerated: TArray<string>; const aIdentity: TStringBuilder;
      out aOutput: string; out aDependencies: TArray<string>): Boolean;
    function ResolveNamedRoot(const aRoot: TDelphiSemanticQualifiedRootType;
      const aIdentity: TStringBuilder; out aQualifiedRoot: string): Boolean;
    function ProbeUnitName(const aName: string): string;
    function CanonicalProbeUnits(const aUnits: TArray<string>;
      out aCanonical: TArray<string>): Boolean;
    function ProveNamedAbsent(const aKind, aQualifiedRoot: string;
      const aDeclarationUnits, aSiteUnits: TArray<string>; const aName: string;
      const aIdentity: TStringBuilder): Boolean;
    function RunCaptured(const aExePath, aArguments, aRunRoot,
      aLogName: string): Boolean;
    function DependenciesMatch(const aRunRoot, aProgramName,
      aWitnessName, aProbeName: string): Boolean;
    function ProveNameAbsent(const aName: string): Boolean;
    procedure RetainInput(const aFileName: string; const aIdentity: TStringBuilder);
  public
    constructor Create(const aCompilerFileName, aSdkLibraryDirectory, aWorkRoot: string;
      const aIO: IDakNativeWitnessIO; const aLookup: TDakNativeRootLookup);
    destructor Destroy; override;
    function EvidenceFingerprint: string;
    function IsNameAbsent(const aName: string): Boolean;
    function IsNamedRootMemberAbsent(const aRoot: TDelphiSemanticQualifiedRootType;
      const aSiteUnits: TArray<string>; const aName: string): Boolean;
    function IsNamedRootMemberAbsentInto(const aRoot: TDelphiSemanticQualifiedRootType;
      const aSiteUnits: TArray<string>; const aName: string;
      const aIdentity: TStringBuilder): Boolean;
    procedure AddNamedProvenance(const aJson: TJSONObject);
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
  // A 96-bit tag bounds both directory and generated unit names.
  Result := Copy(THashSHA2.GetHashString(GUIDToString(lGuid)), 1, 24);
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
  aSdkLibraryDirectory, aWorkRoot: string; const aIO: IDakNativeWitnessIO;
  const aLookup: TDakNativeRootLookup);
var
  lIdentity: TStringBuilder;
begin
  inherited Create;
  fLookup := aLookup;
  fLookup.fUnitPaths := Copy(aLookup.fUnitPaths);
  fLookup.fUnitAliases := Copy(aLookup.fUnitAliases);
  fLookup.fUnitScopeNames := Copy(aLookup.fUnitScopeNames);
  fResolved := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fProbeUnits := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fNamedMemo := TDictionary<string, Boolean>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fUnitSelectionMemo := TDictionary<string, Boolean>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fClosures := TDictionary<string, TArray<string>>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fSdkDependencies := TDictionary<string, string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fNamedAbsences := TList<TNamedAbsence>.Create;
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
  fNamedAbsences.Free;
  fSdkDependencies.Free;
  fClosures.Free;
  fUnitSelectionMemo.Free;
  fNamedMemo.Free;
  fProbeUnits.Free;
  fResolved.Free;
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
  if fInputLocks.InputsAreCurrent and
    ((fSelectionSnapshot = '') or (SelectionSnapshot = fSelectionSnapshot)) then
    Result := fFingerprint
  else begin
    fUnitSelectionMemo.Clear;
    fUnitSelectionFingerprint := '';
    Result := '';
  end;
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
      Format(cNativeWitness, [lWitnessName]), TEncoding.ASCII);
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

function IsDottedIdentifier(const aName: string): Boolean;
var
  lPart: string;
begin
  Result := False;
  if (aName = '') or (Length(aName) > 1024) then
    Exit;
  for lPart in aName.Split(['.']) do
    if not IsPlainIdentifier(lPart) then
      Exit;
  Result := True;
end;

function UnitListIsValid(const aUnits: TArray<string>): Boolean;
var
  lUnitName: string;
begin
  Result := False;
  if Length(aUnits) > 256 then
    Exit;
  for lUnitName in aUnits do
    if not IsDottedIdentifier(lUnitName) then
      Exit;
  Result := True;
end;

function TNativeImplicitRootMemberAbsence.SelectionSnapshot: string;
var
  g: TGarbos;
  lNames: TStringList;
  lPath, lFileName: string;
begin
  // Negative lookup depends on directory entries as well as locked input bytes.
  // Enumerate once per currency check, rather than repeating each name/path stat.
  GC(lNames, TStringList.Create, g);
  for lPath in fLookup.fUnitPaths do
  begin
    lNames.Add('directory:' + LowerCase(TPath.GetFullPath(lPath)));
    if not TDirectory.Exists(lPath) then
    begin
      lNames.Add('missing:' + LowerCase(lPath));
      Continue;
    end;
    for lFileName in TDirectory.GetFiles(lPath, '*', TSearchOption.soTopDirectoryOnly) do
      if MatchText(TPath.GetExtension(lFileName), ['.pas', '.dcu']) then
        lNames.Add(LowerCase(TPath.GetFullPath(lFileName)));
  end;
  lNames.Sort;
  Result := THashSHA2.GetHashString(lNames.Text);
end;

function TNativeImplicitRootMemberAbsence.UnitSelectionIsCurrent(const aName: string): Boolean;
var
  lKey: string;
begin
  if fSelectionSnapshot = '' then
    fSelectionSnapshot := SelectionSnapshot;
  // The lookup arrays are copied at construction and immutable for this provider.
  // Keep their order in the key: compiler unit and namespace selection is ordered.
  if fUnitSelectionFingerprint <> fFingerprint then
  begin
    fUnitSelectionMemo.Clear;
    fUnitSelectionFingerprint := fFingerprint;
  end;
  lKey := aName + #30 + string.Join(#31, fLookup.fUnitPaths) + #30 +
    string.Join(#31, fLookup.fUnitScopeNames);
  if fUnitSelectionMemo.TryGetValue(lKey, Result) then
  begin
    Inc(fUnitSelectionMemoHits);
    Exit;
  end;
  Inc(fUnitSelectionChecks);
  Result := CheckUnitSelection(aName);
  fUnitSelectionMemo.AddOrSetValue(lKey, Result);
end;

function TNativeImplicitRootMemberAbsence.CheckUnitSelection(const aName: string): Boolean;
var
  lCandidate, lPath, lSelected, lScope: string;
  lCandidates: TArray<string>;
begin
  if Length(fLookup.fUnitPaths) = 0 then
    Exit(True);
  Result := False;
  lCandidates := [aName];
  for lScope in fLookup.fUnitScopeNames do
    lCandidates := lCandidates + [lScope + '.' + aName];
  for lCandidate in lCandidates do
  begin
    lSelected := '';
    for lPath in fLookup.fUnitPaths do
    begin
      if TFile.Exists(TPath.Combine(lPath, lCandidate + '.pas')) then
        Exit(False);
      if TFile.Exists(TPath.Combine(lPath, lCandidate + '.dcu')) then
      begin
        if (fLookup.fSdkLibRoot = '') or
          (not StartsText(IncludeTrailingPathDelimiter(TPath.GetFullPath(fLookup.fSdkLibRoot)),
          IncludeTrailingPathDelimiter(TPath.GetFullPath(lPath)))) then
          Exit(False);
        if lSelected = '' then
          lSelected := TPath.GetFullPath(lPath);
      end;
    end;
    if lSelected <> '' then
    begin
      if not SameText(lSelected, fSdkLibraryDirectory) then
        Exit(False);
      Result := True;
    end;
  end;
end;

function TNativeImplicitRootMemberAbsence.NamedSelectionIsCurrent(
  const aUnits: TArray<string>): Boolean;
var
  lUnitName: string;
begin
  for lUnitName in aUnits do
    if not UnitSelectionIsCurrent(lUnitName) then
      Exit(False);
  Result := True;
end;

function TNativeImplicitRootMemberAbsence.NamedDependenciesMatch(
  const aRunRoot, aProgramName: string; const aGenerated: TArray<string>;
  const aIdentity: TStringBuilder; out aDependencies: TArray<string>): Boolean;
var
  g: TGarbos;
  i: Integer;
  lExpected, lSeen: TDictionary<string, Byte>;
  lFileName, lLine, lName, lHash: string;
  lLines: TArray<string>;
  lSystem, lSysInit: Boolean;
begin
  Result := False;
  aDependencies := nil;
  lFileName := TPath.Combine(aRunRoot, aProgramName + '.d');
  lLines := fIO.ReadTextBounded(lFileName, 1024 * 1024, TEncoding.Default).Split(
    [#13, #10], TStringSplitOptions.ExcludeEmpty);
  if (Length(lLines) < 3) or
    (not SameText(Trim(lLines[0]), TPath.Combine(aRunRoot, aProgramName + '.exe') + ': ' +
    TPath.Combine(aRunRoot, aProgramName + '.dpr') + ' \')) then
    Exit;
  GC(lExpected, TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
  GC(lSeen, TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
  for lName in aGenerated do
    lExpected.Add(TPath.Combine(aRunRoot, lName + '.dcu'), 0);
  lSystem := False;
  lSysInit := False;
  for i := 1 to High(lLines) do
  begin
    lLine := Trim(lLines[i]);
    if EndsText(' \', lLine) then
      lLine := Trim(Copy(lLine, 1, Length(lLine) - 2));
    if not lSeen.TryAdd(lLine, 0) then
      Exit;
    if lExpected.ContainsKey(lLine) then
    begin
      lExpected.Remove(lLine);
      Continue;
    end;
    if (not SameText(TPath.GetExtension(lLine), '.dcu')) or
      (not SameText(TPath.GetDirectoryName(lLine), fSdkLibraryDirectory)) then
      Exit;
    lName := TPath.GetFileNameWithoutExtension(lLine);
    if (not IsDottedIdentifier(lName)) or (not UnitSelectionIsCurrent(lName)) then
      Exit;
    lSystem := lSystem or SameText(lName, 'System');
    lSysInit := lSysInit or SameText(lName, 'SysInit');
    aDependencies := aDependencies + [lName];
    if not fSdkDependencies.ContainsKey(lLine) then
    begin
      RetainInput(lLine, aIdentity);
      lHash := THashSHA2.GetHashStringFromFile(lLine);
      fSdkDependencies.Add(lLine, lHash);
    end;
  end;
  Result := (lExpected.Count = 0) and lSystem and lSysInit;
end;

procedure TNativeImplicitRootMemberAbsence.RegisterNamedArtifacts(
  const aRoot, aProgramName: string; const aUnits: TArray<string>);
var
  lArtifacts: TRunArtifacts;
  lUnitName: string;
begin
  lArtifacts := Default(TRunArtifacts);
  lArtifacts.fRoot := aRoot;
  if not TryReadDirectoryIdentity(aRoot, lArtifacts.fIdentity) then
    raise EInvalidOpException.Create('Named witness directory identity cannot be retained');
  lArtifacts.fFiles := [aProgramName + '.dpr', aProgramName + '.exe', aProgramName + '.d',
    'compiler.log', 'compiler.log.status', 'runtime.log', 'runtime.log.status'];
  for lUnitName in aUnits do
    lArtifacts.fFiles := lArtifacts.fFiles + [lUnitName + '.pas', lUnitName + '.dcu'];
  fArtifacts.Add(lArtifacts);
end;

function TNativeImplicitRootMemberAbsence.CleanupRunArtifacts(const aIndex: Integer): Boolean;
var
  lArtifacts: TRunArtifacts;
  lCurrent: TByHandleFileInformation;
  lFileName: string;
begin
  Result := False;
  lArtifacts := fArtifacts[aIndex];
  try
    if (not TryReadDirectoryIdentity(lArtifacts.fRoot, lCurrent)) or
      (lCurrent.dwVolumeSerialNumber <> lArtifacts.fIdentity.dwVolumeSerialNumber) or
      (lCurrent.nFileIndexHigh <> lArtifacts.fIdentity.nFileIndexHigh) or
      (lCurrent.nFileIndexLow <> lArtifacts.fIdentity.nFileIndexLow) then
    begin
      OutputDebugString(PChar('DAK-418 witness cleanup refused after directory identity change: ' +
        lArtifacts.fRoot));
      Exit;
    end;
    for lFileName in lArtifacts.fFiles do
      if TFile.Exists(TPath.Combine(lArtifacts.fRoot, lFileName)) then
        TFile.Delete(TPath.Combine(lArtifacts.fRoot, lFileName));
    TDirectory.Delete(lArtifacts.fRoot, False);
    fArtifacts.Delete(aIndex);
    Result := True;
  except
    on E: Exception do
      OutputDebugString(PChar('DAK-418 witness cleanup incomplete: ' + E.Message));
  end;
end;

function TNativeImplicitRootMemberAbsence.RunNamedProgram(const aRunRoot, aProgramName: string;
  const aGenerated: TArray<string>; const aIdentity: TStringBuilder;
  out aOutput: string; out aDependencies: TArray<string>): Boolean;
var
  g: TGarbos;
  lInputs: TDakNativeInputLocks;
  lIdentity: TStringBuilder;
  lArguments, lUnitName: string;
begin
  Result := False;
  aOutput := '';
  aDependencies := nil;
  GC(lInputs, TDakNativeInputLocks.Create, g);
  GC(lIdentity, TStringBuilder.Create, g);
  for lUnitName in aGenerated do
    lInputs.Retain(TPath.Combine(aRunRoot, lUnitName + '.pas'), lIdentity);
  lInputs.Retain(TPath.Combine(aRunRoot, aProgramName + '.dpr'), lIdentity);
  lArguments := '--no-config --depends -B -Q -W+ -U' + Quoted(fSdkLibraryDirectory) +
    ' -E' + Quoted(aRunRoot) + ' -N0' + Quoted(aRunRoot);
  if Length(fLookup.fUnitScopeNames) > 0 then
    lArguments := lArguments + ' -NS' + Quoted(string.Join(';', fLookup.fUnitScopeNames));
  if Length(fLookup.fUnitAliases) > 0 then
    lArguments := lArguments + ' -A' + Quoted(string.Join(';', fLookup.fUnitAliases));
  lArguments := lArguments + ' ' + Quoted(TPath.Combine(aRunRoot, aProgramName + '.dpr'));
  if not RunCaptured(fCompilerFileName, lArguments, aRunRoot, 'compiler.log') then
    Exit;
  if not NamedDependenciesMatch(aRunRoot, aProgramName, aGenerated, aIdentity, aDependencies) then
    Exit;
  lInputs.Retain(TPath.Combine(aRunRoot, aProgramName + '.exe'), lIdentity);
  if not RunCaptured(TPath.Combine(aRunRoot, aProgramName + '.exe'), '', aRunRoot, 'runtime.log') then
    Exit;
  aOutput := fIO.ReadTextBounded(TPath.Combine(aRunRoot, 'runtime.log'), 4096, TEncoding.ASCII);
  Result := lInputs.InputsAreCurrent and fInputLocks.InputsAreCurrent;
end;

function TNativeImplicitRootMemberAbsence.ResolveNamedRoot(
  const aRoot: TDelphiSemanticQualifiedRootType; const aIdentity: TStringBuilder;
  out aQualifiedRoot: string): Boolean;
var
  lArtifactIndex: Integer;
  lTag, lRunRoot, lUnitName, lProgramName, lMarker, lUses, lSource, lProgram, lOutput: string;
  lLines, lDependencies: TArray<string>;
begin
  Result := False;
  aQualifiedRoot := '';
  lTag := NewTag;
  lRunRoot := TPath.Combine(fWorkRoot, 'run-' + lTag);
  TDirectory.CreateDirectory(lRunRoot);
  lUnitName := 'Resolve_' + lTag;
  lProgramName := 'Native_' + lTag;
  lMarker := 'completed-' + lTag;
  RegisterNamedArtifacts(lRunRoot, lProgramName, [lUnitName]);
  lArtifactIndex := fArtifacts.Count - 1;
  try
    lUses := '';
    if Length(aRoot.LookupUnits) > 0 then
      lUses := 'uses ' + string.Join(', ', aRoot.LookupUnits) + ';'#13#10;
    lSource := 'unit ' + lUnitName + ';'#13#10'interface'#13#10 + lUses;
    lProgram := 'program ' + lProgramName + ';'#13#10'{$APPTYPE CONSOLE}'#13#10;
    if SameText(aRoot.Kind, 'class') then
    begin
      lSource := lSource + 'type TProbe = class(' + aRoot.TypeName + ') end;'#13#10;
      lProgram := lProgram + 'uses ' + lUnitName + ';'#13#10 +
        'begin WriteLn(TProbe.ClassParent.UnitName); WriteLn(TProbe.ClassParent.ClassName); ' +
        'WriteLn(TProbe.ClassParent.QualifiedClassName);';
    end else begin
      lSource := lSource + 'type IProbe = interface(' + aRoot.TypeName + ') end;'#13#10;
      lProgram := lProgram + 'uses System.TypInfo, ' + lUnitName + ';'#13#10 +
        'begin if GetTypeData(TypeInfo(IProbe))^.IntfParent^ <> TypeInfo(System.IInterface) then Halt(8);' +
        ' WriteLn(''System.IInterface'');';
    end;
    lSource := lSource + 'implementation'#13#10'end.'#13#10;
    lProgram := lProgram + ' WriteLn(''' + lMarker + '''); Flush(Output); end.'#13#10;
    fIO.WriteText(TPath.Combine(lRunRoot, lUnitName + '.pas'), lSource, TEncoding.ASCII);
    fIO.WriteText(TPath.Combine(lRunRoot, lProgramName + '.dpr'), lProgram, TEncoding.ASCII);
    if not RunNamedProgram(lRunRoot, lProgramName, [lUnitName], aIdentity, lOutput, lDependencies) then
      Exit;
    lLines := lOutput.Split([#13#10], TStringSplitOptions.None);
    if (Length(lLines) = 0) or (lLines[High(lLines)] <> '') then
      Exit;
    SetLength(lLines, Length(lLines) - 1);
    if SameText(aRoot.Kind, 'class') then
    begin
      if (Length(lLines) <> 4) or (not IsDottedIdentifier(lLines[0])) or
        (not IsPlainIdentifier(lLines[1])) or (lLines[2] <> lLines[0] + '.' + lLines[1]) or
        (lLines[3] <> lMarker) then
        Exit;
      aQualifiedRoot := lLines[2];
    end else begin
      if (Length(lLines) <> 2) or (lLines[0] <> 'System.IInterface') or (lLines[1] <> lMarker) then
        Exit;
      aQualifiedRoot := lLines[0];
    end;
    fClosures.AddOrSetValue('resolution' + #31 + aQualifiedRoot, lDependencies);
    Result := True;
  finally
    CleanupRunArtifacts(lArtifactIndex);
  end;
end;

function TNativeImplicitRootMemberAbsence.ProbeUnitName(const aName: string): string;
var
  lName, lAlias, lScope: string;
  lParts: TArray<string>;
begin
  if fProbeUnits.TryGetValue(aName, Result) then
    Exit;
  Result := '';
  lName := aName;
  for lAlias in fLookup.fUnitAliases do
  begin
    lParts := lAlias.Split(['=']);
    if (Length(lParts) = 2) and SameText(lParts[0], lName) then
    begin
      lName := lParts[1];
      Break;
    end;
  end;
  if not IsDottedIdentifier(lName) then
    Exit;
  if TFile.Exists(TPath.Combine(fSdkLibraryDirectory, lName + '.dcu')) then
    Result := lName;
  for lScope in fLookup.fUnitScopeNames do
    if TFile.Exists(TPath.Combine(fSdkLibraryDirectory, lScope + '.' + lName + '.dcu')) then
    begin
      // Multiple viable SDK spellings require compiler unit-selection evidence.
      if Result <> '' then
        Exit('');
      Result := lScope + '.' + lName;
    end;
  fProbeUnits.AddOrSetValue(aName, Result);
end;

function TNativeImplicitRootMemberAbsence.CanonicalProbeUnits(
  const aUnits: TArray<string>; out aCanonical: TArray<string>): Boolean;
var
  i: Integer;
  lSelected: string;
begin
  aCanonical := nil;
  // Resolve identity before deduplication; namespace and alias spellings can
  // select the same SDK unit. Retain its last position, never its first.
  for i := High(aUnits) downto 0 do
  begin
    lSelected := ProbeUnitName(aUnits[i]);
    if lSelected = '' then
      Exit(False);
    if not MatchText(lSelected, aCanonical) then
      aCanonical := [lSelected] + aCanonical;
  end;
  Result := True;
end;

function TNativeImplicitRootMemberAbsence.ProveNamedAbsent(
  const aKind, aQualifiedRoot: string; const aDeclarationUnits, aSiteUnits: TArray<string>;
  const aName: string;
  const aIdentity: TStringBuilder): Boolean;
var
  lArtifactIndex: Integer;
  lTag, lRunRoot, lWitness, lBase, lProbe, lProgram, lMarker: string;
  lUses, lSource, lTypeName, lRunName, lReceiver, lOutput: string;
  lDependencies: TArray<string>;
begin
  Result := False;
  lTag := NewTag;
  lRunRoot := TPath.Combine(fWorkRoot, 'run-' + lTag);
  TDirectory.CreateDirectory(lRunRoot);
  lWitness := 'Witness_' + lTag;
  lBase := 'Base_' + lTag;
  lProbe := 'Probe_' + lTag;
  lProgram := 'Native_' + lTag;
  lMarker := 'completed-' + lTag;
  lTypeName := 'TProbe_' + lTag;
  lRunName := 'Run_' + lTag;
  lReceiver := 'aReceiver_' + lTag;
  RegisterNamedArtifacts(lRunRoot, lProgram, [lWitness, lBase, lProbe]);
  lArtifactIndex := fArtifacts.Count - 1;
  try
    fIO.WriteText(TPath.Combine(lRunRoot, lWitness + '.pas'), Format(cNativeWitness, [lWitness]),
      TEncoding.ASCII);
    lUses := '';
    if Length(aDeclarationUnits) > 0 then
      lUses := 'uses ' + string.Join(', ', aDeclarationUnits) + ';'#13#10;
    lSource := 'unit ' + lBase + ';'#13#10'interface'#13#10 + lUses;
    if SameText(aKind, 'class') then
      // A real subclass captures the active helper's methods at this point.
      // An alias loses that compiler state, even if every uses entry is kept.
      lSource := lSource + 'type TProbeRoot = class(' + aQualifiedRoot + ') end;'#13#10
    else
      lSource := lSource + 'type TProbeRoot = ' + aQualifiedRoot + ';'#13#10;
    fIO.WriteText(TPath.Combine(lRunRoot, lBase + '.pas'),
      lSource + 'implementation'#13#10'end.'#13#10, TEncoding.ASCII);
    lUses := lWitness;
    if Length(aSiteUnits) > 0 then
      lUses := lUses + ', ' + string.Join(', ', aSiteUnits);
    lUses := lUses + ', ' + lBase;
    lSource := 'unit ' + lProbe + ';'#13#10'interface'#13#10'uses ' + lUses + ';'#13#10;
    if SameText(aKind, 'class') then
      lSource := lSource + 'type ' + lTypeName + ' = class(' + lBase + '.TProbeRoot)'#13#10 +
        'class procedure ' + lRunName + '(const ' + lReceiver + ': ' + lTypeName + '); end;'#13#10
    else
      lSource := lSource + 'type ' + lTypeName + ' = interface(' + lBase + '.TProbeRoot) end;'#13#10 +
        'procedure ' + lRunName + '(const ' + lReceiver + ': ' + lTypeName + ');'#13#10;
    lSource := lSource + 'var &' + aName + ': ' + lWitness + '.TUnique;'#13#10'implementation'#13#10;
    if SameText(aKind, 'class') then
      lSource := lSource + 'class procedure ' + lTypeName + '.'
    else
      lSource := lSource + 'procedure ';
    lSource := lSource + lRunName + '(const ' + lReceiver + ': ' + lTypeName + ');'#13#10 +
      'begin with ' + lReceiver + ' do ' + lWitness + '.Check(' + aName + '); end;'#13#10'end.'#13#10;
    fIO.WriteText(TPath.Combine(lRunRoot, lProbe + '.pas'), lSource, TEncoding.ASCII);
    lSource := 'program ' + lProgram + ';'#13#10'{$APPTYPE CONSOLE}'#13#10 +
      'uses ' + lProbe + ', ' + lWitness + ';'#13#10 +
      'begin if ' + lWitness + '.Completed then Halt(6); ';
    if SameText(aKind, 'class') then
      lSource := lSource + lTypeName + '.';
    lSource := lSource + lRunName + '(nil); if not ' + lWitness + '.Completed then Halt(7); ' +
      'WriteLn(''' + lMarker + '''); Flush(Output); end.'#13#10;
    fIO.WriteText(TPath.Combine(lRunRoot, lProgram + '.dpr'), lSource, TEncoding.ASCII);
    if not RunNamedProgram(lRunRoot, lProgram, [lWitness, lBase, lProbe], aIdentity,
      lOutput, lDependencies) then
      Exit;
    Result := lOutput = lMarker + #13#10;
    if Result then
      fClosures.AddOrSetValue(aQualifiedRoot + #30 + string.Join(#31, aDeclarationUnits) + #30 +
        string.Join(#31, aSiteUnits), lDependencies);
  finally
    CleanupRunArtifacts(lArtifactIndex);
  end;
end;

function TNativeImplicitRootMemberAbsence.IsNamedRootMemberAbsentInto(
  const aRoot: TDelphiSemanticQualifiedRootType; const aSiteUnits: TArray<string>;
  const aName: string; const aIdentity: TStringBuilder): Boolean;
var
  lRootKey, lQualifiedRoot, lKey, lClosureKey: string;
  lUnits, lDeclarationUnits, lDependencies, lRootUnits: TArray<string>;
  lRoot: TDelphiSemanticQualifiedRootType;
  lRootUnit, lRootPrefix: string;
  lAbsent: TNamedAbsence;
  lClock: TStopwatch;
begin
  Result := False;
  // Guard failures neither launch a compiler nor become cache entries.
  if (not MatchText(aRoot.Kind, ['class', 'interface'])) or
    (not IsDottedIdentifier(aRoot.TypeName)) or (not IsPlainIdentifier(aName)) or
    (not UnitListIsValid(aRoot.LookupUnits)) or (not UnitListIsValid(aSiteUnits)) or
    ((SameText(aRoot.Kind, 'interface')) and (Length(aRoot.LookupUnits) = 0) and
    (not SameText(aRoot.TypeName, 'System.IInterface'))) or
    (EvidenceFingerprint = '') or (not NamedSelectionIsCurrent(aRoot.LookupUnits)) or
    (not NamedSelectionIsCurrent(aSiteUnits)) then
    Exit;
  if not CanonicalProbeUnits(aRoot.LookupUnits, lDeclarationUnits) then
    Exit;
  lRoot := aRoot;
  lRoot.LookupUnits := lDeclarationUnits;
  lRootPrefix := Copy(aRoot.TypeName, 1, LastDelimiter('.', aRoot.TypeName) - 1);
  if lRootPrefix <> '' then
  begin
    lRootUnit := ProbeUnitName(lRootPrefix);
    if lRootUnit <> '' then
      lRoot.TypeName := lRootUnit + Copy(aRoot.TypeName, LastDelimiter('.', aRoot.TypeName), MaxInt);
  end;
  lRootKey := aRoot.Kind + #31 + aRoot.TypeName + #31 + string.Join(#31, lDeclarationUnits);
  lClock := TStopwatch.StartNew;
  try
    try
      if not fResolved.TryGetValue(lRootKey, lQualifiedRoot) then
      begin
        if (Length(aRoot.LookupUnits) = 0) and
          ((SameText(aRoot.Kind, 'class') and SameText(aRoot.TypeName, 'System.TObject')) or
          (SameText(aRoot.Kind, 'interface') and SameText(aRoot.TypeName, 'System.IInterface'))) then
          lQualifiedRoot := aRoot.TypeName
        else if not ResolveNamedRoot(lRoot, aIdentity, lQualifiedRoot) then
          lQualifiedRoot := '';
        fResolved.Add(lRootKey, lQualifiedRoot);
        aIdentity.AppendLine('root:' + lRootKey + ' => ' + lQualifiedRoot);
      end;
      if lQualifiedRoot = '' then
        Exit;
      if fClosures.TryGetValue('resolution' + #31 + lQualifiedRoot, lDependencies) and
        (not NamedSelectionIsCurrent(lDependencies)) then
        Exit;
      lRootUnit := Copy(lQualifiedRoot, 1, LastDelimiter('.', lQualifiedRoot) - 1);
      lRootUnits := nil;
      // System is already implicit; explicitly importing it is E2004.
      if not SameText(lRootUnit, 'System') then
        lRootUnits := [lRootUnit];
      // The root's defining unit is a conservative prefix. Site imports keep
      // their exact order and outrank it; canonicalization retains a repeated
      // root unit at its actual final position.
      if not CanonicalProbeUnits(lRootUnits + lDeclarationUnits, lDeclarationUnits) then
        Exit;
      if not CanonicalProbeUnits(lRootUnits + aSiteUnits, lUnits) then
        Exit;
      if SameText(aRoot.Kind, 'interface') then
        lUnits := nil;
      lClosureKey := lQualifiedRoot + #30 + string.Join(#31, lDeclarationUnits) + #30 +
        string.Join(#31, lUnits);
      if fClosures.TryGetValue(lClosureKey, lDependencies) and
        (not NamedSelectionIsCurrent(lDependencies)) then
        Exit;
      lKey := aRoot.Kind + #31 + lClosureKey + #31 + aName;
      if fNamedMemo.TryGetValue(lKey, Result) then
        Exit;
      Inc(fNamedQueryCount);
      Result := ProveNamedAbsent(aRoot.Kind, lQualifiedRoot, lDeclarationUnits, lUnits, aName, aIdentity) and
        (EvidenceFingerprint <> '');
      fNamedMemo.Add(lKey, Result);
      if Result then
      begin
        lAbsent.fRoot := lQualifiedRoot;
        lAbsent.fUnits := Copy(lUnits);
        lAbsent.fDeclarationUnits := Copy(lDeclarationUnits);
        lAbsent.fName := aName;
        fNamedAbsences.Add(lAbsent);
      end;
    except
      on E: Exception do
      begin
        OutputDebugString(PChar('DAK-418 named root proof unavailable: ' + E.Message));
        Result := False;
      end;
    end;
    finally
      fNamedMilliseconds := fNamedMilliseconds + lClock.ElapsedMilliseconds;
    end;
end;

function TNativeImplicitRootMemberAbsence.IsNamedRootMemberAbsent(
  const aRoot: TDelphiSemanticQualifiedRootType; const aSiteUnits: TArray<string>;
  const aName: string): Boolean;
var
  g: TGarbos;
  lIdentity: TStringBuilder;
begin
  GC(lIdentity, TStringBuilder.Create, g);
  Result := IsNamedRootMemberAbsentInto(aRoot, aSiteUnits, aName, lIdentity);
end;

procedure TNativeImplicitRootMemberAbsence.AddNamedProvenance(const aJson: TJSONObject);
var
  lRoots, lAbsent, lDependencies, lUnits: TJSONArray;
  lItem: TJSONObject;
  lPair: TPair<string, string>;
  lAbsence: TNamedAbsence;
  lUnitName: string;
begin
  aJson.AddPair('namedRootSchema', 'native-named-root-absence-v1');
  aJson.AddPair('unitSelectionChecks', TJSONNumber.Create(fUnitSelectionChecks));
  aJson.AddPair('unitSelectionMemoHits', TJSONNumber.Create(fUnitSelectionMemoHits));
  aJson.AddPair('namedRootQueryCount', TJSONNumber.Create(fNamedQueryCount));
  aJson.AddPair('namedRootQueryMilliseconds', TJSONNumber.Create(fNamedMilliseconds));
  lRoots := TJSONArray.Create;
  aJson.AddPair('namedRoots', lRoots);
  for lPair in fResolved do
  begin
    lItem := TJSONObject.Create;
    lItem.AddPair('lookup', lPair.Key);
    lItem.AddPair('qualifiedRoot', lPair.Value);
    lRoots.AddElement(lItem);
  end;
  lAbsent := TJSONArray.Create;
  aJson.AddPair('absentNamedRootMembers', lAbsent);
  for lAbsence in fNamedAbsences do
  begin
    lItem := TJSONObject.Create;
    lItem.AddPair('qualifiedRoot', lAbsence.fRoot);
    lUnits := TJSONArray.Create;
    lItem.AddPair('siteUnits', lUnits);
    for lUnitName in lAbsence.fUnits do
      lUnits.Add(lUnitName);
    lUnits := TJSONArray.Create;
    lItem.AddPair('declarationUnits', lUnits);
    for lUnitName in lAbsence.fDeclarationUnits do
      lUnits.Add(lUnitName);
    lItem.AddPair('name', lAbsence.fName);
    lAbsent.AddElement(lItem);
  end;
  lDependencies := TJSONArray.Create;
  aJson.AddPair('sdkDependencies', lDependencies);
  for lPair in fSdkDependencies do
  begin
    lItem := TJSONObject.Create;
    lItem.AddPair('file', lPair.Key);
    lItem.AddPair('sha256', lPair.Value);
    lDependencies.AddElement(lItem);
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
  Result := TryCreateNativeRootMemberAbsence(aCompilerFileName, aSdkLibraryDirectory,
    aWorkRoot, Default(TDakNativeRootLookup), aIO, aReason);
end;

function TryCreateNativeRootMemberAbsence(const aCompilerFileName, aSdkLibraryDirectory,
  aWorkRoot: string; const aLookup: TDakNativeRootLookup; const aIO: IDakNativeWitnessIO;
  out aReason: string): IDelphiSemanticImplicitRootMemberAbsence;
var
  lAlias: string;
  lLongestPath: string;
begin
  // Bound the generated witness before any directory, compiler or executable is opened.
  lLongestPath := maxLogic.ioutils.CombinePath([TPath.GetFullPath(aWorkRoot), 'root-member-absence',
    'run-' + StringOfChar('0', 24), 'Witness_' + StringOfChar('0', 24) + '.pas']);
  if Length(lLongestPath) >= MAX_PATH then
  begin
    aReason := Format('native-root-proof-unavailable: witness path length %d exceeds %d: %s',
      [Length(lLongestPath), MAX_PATH - 1, lLongestPath]);
    Exit(nil);
  end;
  if not UnitListIsValid(aLookup.fUnitScopeNames) then
  begin
    aReason := 'invalid-native-unit-scope-names';
    Exit(nil);
  end;
  for lAlias in aLookup.fUnitAliases do
    if (not TRegEx.IsMatch(lAlias, '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*=' +
      '[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$')) or
      TRegEx.IsMatch(lAlias, '^(System|SysInit)=', [roIgnoreCase]) then
    begin
      aReason := 'unsupported-native-unit-alias';
      Exit(nil);
    end;
  Result := nil;
  aReason := '';
  if not MatchText(ExtractFileName(aCompilerFileName), ['dcc32.exe', 'dcc64.exe']) then
  begin
    aReason := 'unsupported-native-compiler';
    Exit;
  end;
  try
    Result := TNativeImplicitRootMemberAbsence.Create(aCompilerFileName,
      aSdkLibraryDirectory, aWorkRoot, aIO, aLookup);
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
    IDakNativeRootProofMetrics, IDelphiSemanticNamedRootMemberAbsence)
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
    function IsNamedRootMemberAbsent(const aRoot: TDelphiSemanticQualifiedRootType;
      const aSiteUnits: TArray<string>; const aName: string): Boolean;
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

function TNativeRootRequestOwner.IsNamedRootMemberAbsent(
  const aRoot: TDelphiSemanticQualifiedRootType; const aSiteUnits: TArray<string>;
  const aName: string): Boolean;
var
  lNamed: IDakNativeNamedRootEvidence;
  lReason: string;
begin
  Result := ValidateInputs(EvidenceFingerprint, lReason) and
    Supports(fProvider, IDakNativeNamedRootEvidence, lNamed);
  if Result then
    Result := lNamed.IsNamedRootMemberAbsentInto(aRoot, aSiteUnits, aName, fIdentity);
  if Result then
    fUsed := True;
end;

function TNativeRootRequestOwner.ProvenanceJson: string;
var
  g: TGarbos;
  lJson, lSourceJson: TJSONObject;
  lNamed: IDakNativeNamedRootEvidence;
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
  if Supports(fProvider, IDakNativeNamedRootEvidence, lNamed) then
    lNamed.AddNamedProvenance(lJson);
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
  lSelectionPaths: IDakNativeRootSelectionPaths;
  lLookup: TDakNativeRootLookup;
  lProfile: TDakNativeCompilerSourceProfile;
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
    lLookup := Default(TDakNativeRootLookup);
    lProfile := lContext.SourceProfile;
    lLookup.fUnitScopeNames := lProfile.fUnitScopeNames.Split([#13, #10], TStringSplitOptions.ExcludeEmpty);
    lLookup.fUnitAliases := lProfile.fUnitAliases.Split([#13, #10], TStringSplitOptions.ExcludeEmpty);
    lLookup.fUnitPaths := lContext.UnitSearchPaths;
    if Supports(lContext, IDakNativeRootSelectionPaths, lSelectionPaths) then
      lLookup.fUnitPaths := lSelectionPaths.RootSelectionPaths;
    lLookup.fSdkLibRoot := TPath.Combine(TPath.GetDirectoryName(
      TPath.GetDirectoryName(lContext.CompilerFileName)), 'lib');
    lProvider := TryCreateNativeRootMemberAbsence(lContext.CompilerFileName,
      lContext.RootLibraryDirectory, lWorkRoot, lLookup, CreateNativeWitnessIO, aReason);
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
