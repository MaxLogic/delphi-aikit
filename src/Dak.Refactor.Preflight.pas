unit Dak.Refactor.Preflight;

interface

uses
  System.SysUtils,
  DelphiSemantics.Refactor.Plan;

type
  TDakMaterializedFile = record
    FileName: string;
    OriginalHash: string;
    ProposedHash: string;
    OriginalBytes: TBytes;
    ProposedBytes: TBytes;
  end;

// Read-only byte preparation. This does not certify semantic completeness,
// compiler context, build success or authorization to mutate source.
// Source hashes are SHA-256 over disk bytes. Version 1 accepts strict UTF-8
// (with or without BOM), including ASCII; other encodings are refused.
function MaterializeRefactoringPlan(const aPlan: TSemanticRefactoringPlan;
  const aWorkspaceRoot: string; out aFiles: TArray<TDakMaterializedFile>;
  out aError: string): Boolean;

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.Hash,
  System.IOUtils, System.Math, System.StrUtils,
  Winapi.Windows,
  AutoFree, maxLogic.StrUtils,
  Dak.Analysis.Workspace;

type
  TByteEdit = record
    StartOffset: NativeInt;
    EndOffset: NativeInt;
    Replacement: TBytes;
  end;

function HashBytes(const aBytes: TBytes): string;
var
  lHash: THashSHA2;
begin
  lHash := THashSHA2.Create;
  lHash.Update(aBytes);
  Result := lHash.HashAsString;
end;

function SameBytes(const aLeft, aRight: TBytes): Boolean;
begin
  Result := Length(aLeft) = Length(aRight);
  if Result and (Length(aLeft) > 0) then
    Result := CompareMem(@aLeft[0], @aRight[0], Length(aLeft));
end;

// DAK targets Windows Win64; canonical identity deliberately uses its handle API.
{$WARN SYMBOL_PLATFORM OFF}
function HandlePath(const aHandle: THandle): string;
var
  lLength: Cardinal;
begin
  lLength := GetFinalPathNameByHandle(aHandle, nil, 0, 0);
  if lLength = 0 then
    RaiseLastOSError;
  SetLength(Result, lLength);
  lLength := GetFinalPathNameByHandle(aHandle, PChar(Result), Length(Result), 0);
  if lLength = 0 then
    RaiseLastOSError;
  if lLength >= Cardinal(Length(Result)) then
    raise EInOutError.Create('Filesystem identity changed during preflight');
  SetLength(Result, lLength);
  if StartsText('\\?\UNC\', Result) then
    Result := '\\' + Copy(Result, 9, MaxInt)
  else if StartsText('\\?\', Result) then
    Delete(Result, 1, 4);
end;
{$WARN SYMBOL_PLATFORM ON}

function ReadSourceBytes(const aSource: TSemanticPlanSource; const aRoot: string;
  out aFile: TDakMaterializedFile; out aError: string): Boolean;
var
  g: TGarbos;
  lStream: TFileStream;
  lInfo: TByHandleFileInformation;
begin
  Result := False;
  aFile := Default(TDakMaterializedFile);
  aError := 'preflight.out-of-scope';
  if not TPath.IsPathRooted(aSource.FileName) or (Pos(':', Copy(aSource.FileName, 3, MaxInt)) > 0) then
    Exit;
  // Deny concurrent writes/deletion while observing identity and bytes. Apply must
  // reacquire and revalidate these observations before its first mutation.
  GC(lStream, TFileStream.Create(aSource.FileName, fmOpenRead or fmShareDenyWrite), g);
  aFile.FileName := HandlePath(lStream.Handle);
  if not StartsText(IncludeTrailingPathDelimiter(aRoot), aFile.FileName) then
    Exit;
  if not GetFileInformationByHandle(lStream.Handle, lInfo) then
    RaiseLastOSError;
  aError := 'preflight.read-only';
  if (lInfo.dwFileAttributes and FILE_ATTRIBUTE_READONLY) <> 0 then
    Exit;
  aError := 'preflight.path-alias';
  // A hard link can expose this write outside the selected workspace.
  if lInfo.nNumberOfLinks <> 1 then
    Exit;
  aError := 'preflight.source-too-large';
  if lStream.Size > MaxInt then
    Exit;
  SetLength(aFile.OriginalBytes, lStream.Size);
  if Length(aFile.OriginalBytes) > 0 then
    lStream.ReadBuffer(aFile.OriginalBytes[0], Length(aFile.OriginalBytes));
  aFile.OriginalHash := HashBytes(aFile.OriginalBytes);
  aError := 'preflight.stale-source';
  if not SameText(aFile.OriginalHash, aSource.ContentHash) then
    Exit;
  Result := True;
end;

function DecodeSource(const aBytes: TBytes; out aText: string; out aBomLength: Integer): Boolean;
var
  lBody: TBytes;
begin
  aText := '';
  aBomLength := 0;
  if (Length(aBytes) >= 3) and (aBytes[0] = $EF) and (aBytes[1] = $BB) and (aBytes[2] = $BF) then
    aBomLength := 3;
  lBody := Copy(aBytes, aBomLength, Length(aBytes) - aBomLength);
  Result := TEncoding.UTF8.IsBufferValid(lBody);
  if not Result then
    Exit;
  aText := TEncoding.UTF8.GetString(lBody);
  // UTF-16/32 and binary inputs can look like ASCII with embedded zeroes.
  Result := (Pos(#0, aText) = 0) and SameBytes(TEncoding.UTF8.GetBytes(aText), lBody);
end;

function TextOffset(const aText: string; const aLine, aColumn: Integer): Integer;
var
  i, lLine, lStart: Integer;
begin
  Result := -1;
  if (aLine < 1) or (aColumn < 1) then
    Exit;
  i := 1;
  lLine := 1;
  while (i <= Length(aText)) and (lLine < aLine) do
  begin
    if aText[i] = #13 then
    begin
      Inc(i);
      if (i <= Length(aText)) and (aText[i] = #10) then
        Inc(i);
      Inc(lLine);
    end else if aText[i] = #10 then
    begin
      Inc(i);
      Inc(lLine);
    end else
      Inc(i);
  end;
  if lLine <> aLine then
    Exit;
  lStart := i;
  while (i <= Length(aText)) and not CharInSet(aText[i], [#13, #10]) do
    Inc(i);
  if aColumn > i - lStart + 1 then
    Exit;
  i := lStart + aColumn - 1;
  if (i > 1) and (i <= Length(aText)) and (Ord(aText[i - 1]) >= $D800) and
    (Ord(aText[i - 1]) <= $DBFF) and (Ord(aText[i]) >= $DC00) and (Ord(aText[i]) <= $DFFF) then
    Exit;
  Result := i - 1;
end;

function Utf8ByteOffset(const aText: string; const aOffset, aBomLength: Integer): NativeInt;
begin
  Result := NativeInt(aBomLength) + NativeInt(TEncoding.UTF8.GetByteCount(Copy(aText, 1, aOffset)));
end;

function RenderSource(const aPlan: TSemanticRefactoringPlan; const aSource: TSemanticPlanSource;
  var aFile: TDakMaterializedFile; out aError: string): Boolean;
var
  g: TGarbos;
  lEdits: TList<TByteEdit>;
  lOutput: TMemoryStream;
  lEdit: TSemanticPlanEdit;
  lByteEdit, lPrevious: TByteEdit;
  lText: string;
  i, lStart, lFinish, lBomLength: Integer;
  lCursor: NativeInt;
begin
  Result := False;
  aError := 'preflight.unsupported-encoding';
  if not DecodeSource(aFile.OriginalBytes, lText, lBomLength) then
    Exit;
  aError := 'preflight.stale-source';
  if lText <> aSource.OriginalText then
    Exit;
  GC(lEdits, TList<TByteEdit>.Create, g);
  for i := 0 to aPlan.EditCount - 1 do
  begin
    lEdit := aPlan.Edits[i];
    if lEdit.FileName <> aSource.FileName then
      Continue;
    aError := 'preflight.invalid-range';
    lStart := TextOffset(lText, lEdit.StartLine, lEdit.StartColumn);
    lFinish := TextOffset(lText, lEdit.EndLine, lEdit.EndColumn);
    if (lStart < 0) or (lFinish < lStart) then
      Exit;
    aError := 'preflight.expected-text-mismatch';
    if Copy(lText, lStart + 1, lFinish - lStart) <> lEdit.ExpectedText then
      Exit;
    aError := 'preflight.lossy-replacement';
    lByteEdit.Replacement := TEncoding.UTF8.GetBytes(lEdit.ReplacementText);
    if (Pos(#0, lEdit.ReplacementText) > 0) or
      (TEncoding.UTF8.GetString(lByteEdit.Replacement) <> lEdit.ReplacementText) then
      Exit;
    lByteEdit.StartOffset := Utf8ByteOffset(lText, lStart, lBomLength);
    lByteEdit.EndOffset := Utf8ByteOffset(lText, lFinish, lBomLength);
    lEdits.Add(lByteEdit);
  end;
  lEdits.Sort(TComparer<TByteEdit>.Construct(
    function(const aLeft, aRight: TByteEdit): Integer
    begin
      Result := CompareValue(aLeft.StartOffset, aRight.StartOffset);
      if Result = 0 then
        Result := CompareValue(aLeft.EndOffset, aRight.EndOffset);
    end));
  GC(lOutput, TMemoryStream.Create, g);
  lCursor := 0;
  lPrevious := Default(TByteEdit);
  for i := 0 to lEdits.Count - 1 do
  begin
    lByteEdit := lEdits[i];
    aError := 'preflight.overlapping-edits';
    if (i > 0) and ((lByteEdit.StartOffset < lPrevious.EndOffset) or
      (lByteEdit.StartOffset = lPrevious.StartOffset) or
      ((lByteEdit.StartOffset = lPrevious.EndOffset) and
       (lByteEdit.StartOffset = lByteEdit.EndOffset))) then
      Exit;
    if lByteEdit.StartOffset > lCursor then
      lOutput.WriteBuffer(aFile.OriginalBytes[lCursor], lByteEdit.StartOffset - lCursor);
    if Length(lByteEdit.Replacement) > 0 then
      lOutput.WriteBuffer(lByteEdit.Replacement[0], Length(lByteEdit.Replacement));
    lCursor := lByteEdit.EndOffset;
    lPrevious := lByteEdit;
  end;
  if lCursor < Length(aFile.OriginalBytes) then
    lOutput.WriteBuffer(aFile.OriginalBytes[lCursor], Length(aFile.OriginalBytes) - lCursor);
  SetLength(aFile.ProposedBytes, lOutput.Size);
  if lOutput.Size > 0 then
    Move(lOutput.Memory^, aFile.ProposedBytes[0], lOutput.Size);
  aFile.ProposedHash := HashBytes(aFile.ProposedBytes);
  Result := True;
end;

function MaterializeRefactoringPlan(const aPlan: TSemanticRefactoringPlan;
  const aWorkspaceRoot: string; out aFiles: TArray<TDakMaterializedFile>;
  out aError: string): Boolean;
var
  g: TGarbos;
  lNames: THashSet<string>;
  lEdited: THashSet<string>;
  lFiles: TList<TDakMaterializedFile>;
  lSource: TSemanticPlanSource;
  lFile: TDakMaterializedFile;
  lRoot: string;
  i: Integer;
begin
  aFiles := nil;
  Result := False;
  aError := 'preflight.incomplete-plan';
  if (aPlan = nil) or not (aPlan.Status in [TSemanticPlanStatus.Complete, TSemanticPlanStatus.NoChange]) then
    Exit;
  try
    aError := 'preflight.invalid-workspace';
    if not TPath.IsPathRooted(aWorkspaceRoot) or not TDirectory.Exists(aWorkspaceRoot) then
      Exit;
    lRoot := ResolveFilesystemPath(aWorkspaceRoot);
    GC(lNames, THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase), g);
    GC(lEdited, THashSet<string>.Create(TFastCaseAwareComparer.Ordinal), g);
    GC(lFiles, TList<TDakMaterializedFile>.Create, g);
    for i := 0 to aPlan.EditCount - 1 do
      lEdited.Add(aPlan.Edits[i].FileName);
    for i := 0 to aPlan.SourceCount - 1 do
    begin
      lSource := aPlan.Sources[i];
      if not lEdited.Contains(lSource.FileName) then
        Continue;
      if not ReadSourceBytes(lSource, lRoot, lFile, aError) then
        Exit;
      aError := 'preflight.path-alias';
      if not lNames.Add(lFile.FileName) then
        Exit;
      if not RenderSource(aPlan, lSource, lFile, aError) then
        Exit;
      if not SameBytes(lFile.OriginalBytes, lFile.ProposedBytes) then
        lFiles.Add(lFile);
    end;
    aFiles := lFiles.ToArray;
    aError := '';
    Result := True;
  except
    on E: Exception do
    begin
      aFiles := nil;
      aError := 'preflight.io-error: ' + E.Message;
    end;
  end;
end;

end.
