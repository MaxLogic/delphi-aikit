unit Dak.NativeInputLocks;

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils,
  Winapi.Windows;

type
  TDakNativeInputLocks = class
  private type
    TInputIdentity = record
      fFileName: string;
      fInformation: TByHandleFileInformation;
      fContentHash: string;
      fReadLocked: Boolean;
    end;
  private
    fStreams: TObjectList<TFileStream>;
    fIdentities: TArray<TInputIdentity>;
    function Capture(const aFileName: string; const aFingerprint: TStringBuilder;
      const aReadLock, aReadBytes: Boolean): TBytes;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Retain(const aFileName: string; const aFingerprint: TStringBuilder);
    procedure Snapshot(const aFileName: string; const aFingerprint: TStringBuilder);
    function SnapshotMatching(const aFileName, aExpectedHash: string;
      const aFingerprint: TStringBuilder): Boolean;
    function SnapshotBytes(const aFileName: string; const aFingerprint: TStringBuilder): TBytes;
    function InputsAreCurrent: Boolean;
  end;

implementation

uses
  System.Hash, System.IOUtils,
  AutoFree;

constructor TDakNativeInputLocks.Create;
begin
  inherited;
  fStreams := TObjectList<TFileStream>.Create(True);
end;

destructor TDakNativeInputLocks.Destroy;
begin
  fStreams.Free;
  inherited;
end;

procedure TDakNativeInputLocks.Retain(const aFileName: string; const aFingerprint: TStringBuilder);
begin
  Capture(aFileName, aFingerprint, True, False);
end;

procedure TDakNativeInputLocks.Snapshot(const aFileName: string; const aFingerprint: TStringBuilder);
begin
  Capture(aFileName, aFingerprint, False, False);
end;

function TDakNativeInputLocks.SnapshotMatching(const aFileName, aExpectedHash: string;
  const aFingerprint: TStringBuilder): Boolean;
begin
  Snapshot(aFileName, aFingerprint);
  Result := (aExpectedHash <> '') and
    (fIdentities[High(fIdentities)].fContentHash = aExpectedHash);
end;

function TDakNativeInputLocks.SnapshotBytes(const aFileName: string;
  const aFingerprint: TStringBuilder): TBytes;
begin
  Result := Capture(aFileName, aFingerprint, False, True);
end;

function TDakNativeInputLocks.Capture(const aFileName: string; const aFingerprint: TStringBuilder;
  const aReadLock, aReadBytes: Boolean): TBytes;
var
  lHash: THashSHA2;
  lIdentity: TInputIdentity;
  lNewIdentities: TArray<TInputIdentity>;
  lStream: TFileStream;
begin
  Result := nil;
  lIdentity := Default(TInputIdentity);
  lIdentity.fFileName := TPath.GetFullPath(aFileName);
  lStream := TFileStream.Create(lIdentity.fFileName, fmOpenRead or fmShareDenyWrite);
  try
    if not GetFileInformationByHandle(lStream.Handle, lIdentity.fInformation) then
      RaiseLastOSError;
    if (lIdentity.fInformation.nFileIndexHigh = 0) and (lIdentity.fInformation.nFileIndexLow = 0) then
      raise EInvalidOpException.Create('Native input has no verifiable file identity');
    if aReadBytes then
    begin
      SetLength(Result, lStream.Size);
      if Length(Result) > 0 then
        lStream.ReadBuffer(Result[0], Length(Result));
      lHash := THashSHA2.Create;
      lHash.Update(Result);
      lIdentity.fContentHash := lHash.HashAsString;
    end else
      lIdentity.fContentHash := THashSHA2.GetHashString(lStream);
    lIdentity.fReadLocked := aReadLock;
    aFingerprint.AppendLine(lIdentity.fFileName).AppendLine(lIdentity.fContentHash);
    aFingerprint.AppendLine(Format('%u:%u:%u', [lIdentity.fInformation.dwVolumeSerialNumber,
      lIdentity.fInformation.nFileIndexHigh, lIdentity.fInformation.nFileIndexLow]));
    lNewIdentities := fIdentities + [lIdentity];
    if aReadLock then
    begin
      fStreams.Add(lStream);
      lStream := nil;
    end;
    fIdentities := lNewIdentities;
  finally
    lStream.Free;
  end;
end;

function TDakNativeInputLocks.InputsAreCurrent: Boolean;
var
  g: TGarbos;
  lCurrent: TByHandleFileInformation;
  lIdentity: TInputIdentity;
  lStream: TFileStream;
begin
  Result := False;
  try
    for lIdentity in fIdentities do
    begin
      GC(lStream, TFileStream.Create(lIdentity.fFileName, fmOpenRead or fmShareDenyWrite), g);
      if not GetFileInformationByHandle(lStream.Handle, lCurrent) then
        Exit;
      if (lCurrent.dwVolumeSerialNumber <> lIdentity.fInformation.dwVolumeSerialNumber) or
        (lCurrent.nFileIndexHigh <> lIdentity.fInformation.nFileIndexHigh) or
        (lCurrent.nFileIndexLow <> lIdentity.fInformation.nFileIndexLow) then
        Exit;
      // Mutable application source remains writable; its evidence is checked again before proof or apply.
      if (not lIdentity.fReadLocked) and (THashSHA2.GetHashString(lStream) <> lIdentity.fContentHash) then
        Exit;
    end;
    Result := True;
  except
    // Optional evidence cannot use an input whose current pathname cannot be verified.
    Result := False;
  end;
end;

end.
