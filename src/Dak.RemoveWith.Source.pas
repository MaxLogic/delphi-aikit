unit Dak.RemoveWith.Source;

interface

uses
  System.SysUtils;

type
  TRemoveWithSourceEncoding = (rwseUtf8, rwseAnsi);

  TRemoveWithSourceBuffer = record
    fPath: string;
    fText: string;
    fEncoding: TRemoveWithSourceEncoding;
    fHasUtf8Bom: Boolean;
    fLineStarts: TArray<Integer>;
  end;

  TRemoveWithInactiveRange = record
    fStartOffset: Integer;
    fEndOffset: Integer;
  end;

function LoadRemoveWithSource(const aPath: string; out aSource: TRemoveWithSourceBuffer; out aError: string): Boolean;
function RemoveWithSourceEncodingToText(const aEncoding: TRemoveWithSourceEncoding;
  const aHasUtf8Bom: Boolean): string;
function RemoveWithTextToBytes(const aText: string; const aEncoding: TRemoveWithSourceEncoding;
  const aHasUtf8Bom: Boolean): TBytes;
function RemoveWithOffsetForLineColumn(const aSource: TRemoveWithSourceBuffer; const aLine,
  aColumn: Integer; out aOffset: Integer): Boolean;
function RemoveWithLineColumnForOffset(const aSource: TRemoveWithSourceBuffer; const aOffset: Integer;
  out aLine, aColumn: Integer): Boolean;
function RemoveWithInclusiveEndOffset(const aSource: TRemoveWithSourceBuffer; const aEndOffset: Integer): Integer;
function RemoveWithTextSlice(const aSource: TRemoveWithSourceBuffer; const aStartOffset,
  aEndOffset: Integer): string;
function RemoveWithInactiveDirectiveRanges(const aSource: TRemoveWithSourceBuffer;
  const aDefines: string): TArray<TRemoveWithInactiveRange>;
function RemoveWithOffsetInInactiveRanges(const aOffset: Integer;
  const aRanges: TArray<TRemoveWithInactiveRange>): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils;

procedure AddLineStart(var aLineStarts: TArray<Integer>; const aOffset: Integer);
var
  lIndex: Integer;
begin
  lIndex := Length(aLineStarts);
  SetLength(aLineStarts, lIndex + 1);
  aLineStarts[lIndex] := aOffset;
end;

procedure BuildLineStarts(var aSource: TRemoveWithSourceBuffer);
var
  lIndex: Integer;
begin
  SetLength(aSource.fLineStarts, 1);
  aSource.fLineStarts[0] := 1;

  lIndex := 1;
  while lIndex <= Length(aSource.fText) do
  begin
    if aSource.fText[lIndex] = #13 then
    begin
      if (lIndex < Length(aSource.fText)) and (aSource.fText[lIndex + 1] = #10) then
        Inc(lIndex);
      AddLineStart(aSource.fLineStarts, lIndex + 1);
    end else if aSource.fText[lIndex] = #10 then
      AddLineStart(aSource.fLineStarts, lIndex + 1);
    Inc(lIndex);
  end;
end;

function LoadRemoveWithSource(const aPath: string; out aSource: TRemoveWithSourceBuffer; out aError: string): Boolean;
var
  lBodyLength: Integer;
  lBytes: TBytes;
  lOffset: Integer;
begin
  aSource := Default(TRemoveWithSourceBuffer);
  aError := '';
  Result := False;
  try
    lBytes := TFile.ReadAllBytes(aPath);
    lOffset := 0;
    aSource.fHasUtf8Bom := (Length(lBytes) >= 3) and (lBytes[0] = $EF) and (lBytes[1] = $BB) and
      (lBytes[2] = $BF);
    if aSource.fHasUtf8Bom then
      lOffset := 3;

    aSource.fPath := aPath;
    lBodyLength := Length(lBytes) - lOffset;
    try
      aSource.fText := TEncoding.UTF8.GetString(lBytes, lOffset, lBodyLength);
      aSource.fEncoding := TRemoveWithSourceEncoding.rwseUtf8;
    except
      on E: EEncodingError do
      begin
        aSource.fText := TEncoding.Default.GetString(lBytes, lOffset, lBodyLength);
        aSource.fEncoding := TRemoveWithSourceEncoding.rwseAnsi;
      end;
    end;
    BuildLineStarts(aSource);
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
end;

function RemoveWithSourceEncodingToText(const aEncoding: TRemoveWithSourceEncoding;
  const aHasUtf8Bom: Boolean): string;
begin
  if aEncoding = TRemoveWithSourceEncoding.rwseAnsi then
    Exit('ansi');
  if aHasUtf8Bom then
    Exit('utf-8-bom');
  Result := 'utf-8';
end;

function RemoveWithTextToBytes(const aText: string; const aEncoding: TRemoveWithSourceEncoding;
  const aHasUtf8Bom: Boolean): TBytes;
var
  lBody: TBytes;
begin
  if aEncoding = TRemoveWithSourceEncoding.rwseAnsi then
    Exit(TEncoding.Default.GetBytes(aText));

  lBody := TEncoding.UTF8.GetBytes(aText);
  if not aHasUtf8Bom then
    Exit(lBody);
  SetLength(Result, Length(lBody) + 3);
  Result[0] := $EF;
  Result[1] := $BB;
  Result[2] := $BF;
  if Length(lBody) > 0 then
    Move(lBody[0], Result[3], Length(lBody));
end;

function RemoveWithOffsetForLineColumn(const aSource: TRemoveWithSourceBuffer; const aLine,
  aColumn: Integer; out aOffset: Integer): Boolean;
var
  lLineStart: Integer;
begin
  aOffset := 0;
  Result := False;
  if (aLine < 1) or (aLine > Length(aSource.fLineStarts)) or (aColumn < 1) then
    Exit;

  lLineStart := aSource.fLineStarts[aLine - 1];
  aOffset := lLineStart + aColumn - 1;
  Result := (aOffset >= 1) and (aOffset <= Length(aSource.fText) + 1);
end;

function RemoveWithLineColumnForOffset(const aSource: TRemoveWithSourceBuffer; const aOffset: Integer;
  out aLine, aColumn: Integer): Boolean;
var
  lHigh: Integer;
  lLow: Integer;
  lMid: Integer;
begin
  aLine := 0;
  aColumn := 0;
  Result := False;
  if (aOffset < 1) or (aOffset > Length(aSource.fText) + 1) or (Length(aSource.fLineStarts) = 0) then
    Exit;

  lLow := 0;
  lHigh := High(aSource.fLineStarts);
  while lLow <= lHigh do
  begin
    lMid := (lLow + lHigh) div 2;
    if aSource.fLineStarts[lMid] <= aOffset then
      lLow := lMid + 1
    else
      lHigh := lMid - 1;
  end;

  aLine := lHigh + 1;
  aColumn := aOffset - aSource.fLineStarts[lHigh] + 1;
  Result := True;
end;

function RemoveWithInclusiveEndOffset(const aSource: TRemoveWithSourceBuffer; const aEndOffset: Integer): Integer;
begin
  Result := aEndOffset;
  if (Result < 2) or (Result > Length(aSource.fText)) then
    Exit;
  if CharInSet(aSource.fText[Result], ['A'..'Z', 'a'..'z', '_']) and
    CharInSet(aSource.fText[Result - 1], [#9, #10, #13, ' ']) then
    Dec(Result);
end;

function RemoveWithTextSlice(const aSource: TRemoveWithSourceBuffer; const aStartOffset,
  aEndOffset: Integer): string;
begin
  if (aStartOffset < 1) or (aEndOffset < aStartOffset) or (aEndOffset > Length(aSource.fText)) then
    Exit('');

  Result := Copy(aSource.fText, aStartOffset, aEndOffset - aStartOffset + 1);
end;

function RemoveWithDirectiveLineRange(const aSource: TRemoveWithSourceBuffer; const aOffset: Integer;
  out aStartOffset, aEndOffset: Integer): Boolean;
begin
  Result := False;
  aStartOffset := aOffset;
  aEndOffset := aOffset;
  if (aOffset < 1) or (aOffset > Length(aSource.fText)) then
    Exit;

  while (aStartOffset > 1) and not CharInSet(aSource.fText[aStartOffset - 1], [#10, #13]) do
    Dec(aStartOffset);
  while (aEndOffset <= Length(aSource.fText)) and not CharInSet(aSource.fText[aEndOffset], [#10, #13]) do
    Inc(aEndOffset);
  Result := True;
end;

function RemoveWithDirectiveSymbol(const aText, aDirective: string): string;
var
  lClosePos: Integer;
  lText: string;
begin
  Result := '';
  lText := Trim(aText);
  if StartsText('{$', lText) then
    Delete(lText, 1, 2)
  else if StartsText('(*$', lText) then
    Delete(lText, 1, 3);
  lClosePos := Pos('}', lText);
  if lClosePos = 0 then
    lClosePos := Pos('*)', lText);
  if lClosePos > 0 then
    lText := Trim(Copy(lText, 1, lClosePos - 1));
  if StartsText(aDirective, UpperCase(lText)) then
    Result := Trim(Copy(lText, Length(aDirective) + 1, MaxInt));
end;

function RemoveWithDirectiveIsElse(const aText: string): Boolean;
begin
  Result := StartsText('{$ELSE}', UpperCase(Trim(aText))) or StartsText('(*$ELSE*)', UpperCase(Trim(aText)));
end;

function RemoveWithDirectiveIsEnd(const aText: string): Boolean;
var
  lText: string;
begin
  lText := UpperCase(Trim(aText));
  Result := StartsText('{$ENDIF', lText) or StartsText('{$IFEND', lText) or StartsText('(*$ENDIF', lText) or
    StartsText('(*$IFEND', lText);
end;

function RemoveWithNormalizeDirectiveSymbol(const aValue: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while (i <= Length(aValue)) and CharInSet(aValue[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Result := Result + aValue[i];
    Inc(i);
  end;
end;

function RemoveWithDirectiveConditionValue(const aDirectiveText: string;
  const aDefines: TDictionary<string, Byte>): Boolean;
var
  lSymbol: string;
begin
  lSymbol := RemoveWithDirectiveSymbol(aDirectiveText, 'IFDEF');
  if lSymbol <> '' then
    Exit(aDefines.ContainsKey(lSymbol));

  lSymbol := RemoveWithDirectiveSymbol(aDirectiveText, 'IFNDEF');
  if lSymbol <> '' then
    Exit(not aDefines.ContainsKey(lSymbol));

  lSymbol := RemoveWithDirectiveSymbol(aDirectiveText, 'ELSEIF Defined(');
  if lSymbol <> '' then
    Exit(aDefines.ContainsKey(RemoveWithNormalizeDirectiveSymbol(lSymbol)));

  Result := True;
end;

procedure RemoveWithAddInactiveRange(var aRanges: TArray<TRemoveWithInactiveRange>; const aStartOffset,
  aEndOffset: Integer);
var
  lIndex: Integer;
begin
  if (aStartOffset <= 0) or (aEndOffset < aStartOffset) then
    Exit;
  lIndex := Length(aRanges);
  SetLength(aRanges, lIndex + 1);
  aRanges[lIndex].fStartOffset := aStartOffset;
  aRanges[lIndex].fEndOffset := aEndOffset;
end;

function RemoveWithInactiveDirectiveRanges(const aSource: TRemoveWithSourceBuffer;
  const aDefines: string): TArray<TRemoveWithInactiveRange>;
type
  TDirectiveFrame = record
    fParentActive: Boolean;
    fCurrentActive: Boolean;
    fBranchTaken: Boolean;
    fInactiveStartOffset: Integer;
  end;
var
  lCloseOffset: Integer;
  lConditionActive: Boolean;
  lDefine: string;
  lDefines: TDictionary<string, Byte>;
  lDirectiveEndOffset: Integer;
  lDirectiveLineEndOffset: Integer;
  lDirectiveStartOffset: Integer;
  lDirectiveText: string;
  lFrame: TDirectiveFrame;
  lFrameIndex: Integer;
  lFrames: TList<TDirectiveFrame>;
  lLineStartOffset: Integer;
  lParts: TArray<string>;
  lParentActive: Boolean;
  lRawDefine: string;
  i: Integer;
begin
  SetLength(Result, 0);
  lDefines := TDictionary<string, Byte>.Create;
  try
    lParts := aDefines.Split([';']);
    for lRawDefine in lParts do
    begin
      lDefine := Trim(lRawDefine);
      if lDefine <> '' then
        lDefines.AddOrSetValue(lDefine, 1);
    end;

    lFrames := TList<TDirectiveFrame>.Create;
    try
      i := 1;
      while i <= Length(aSource.fText) do
      begin
        if ((aSource.fText[i] = '{') and (i < Length(aSource.fText)) and (aSource.fText[i + 1] = '$')) or
          ((i + 2 <= Length(aSource.fText)) and (aSource.fText[i] = '(') and (aSource.fText[i + 1] = '*') and
          (aSource.fText[i + 2] = '$')) then
        begin
          lDirectiveStartOffset := i;
          if aSource.fText[i] = '{' then
            lCloseOffset := PosEx('}', aSource.fText, i + 2)
          else
            lCloseOffset := PosEx('*)', aSource.fText, i + 3);
          if lCloseOffset = 0 then
            Break;
          if aSource.fText[i] = '{' then
            lDirectiveEndOffset := lCloseOffset
          else
            lDirectiveEndOffset := lCloseOffset + 1;
          lDirectiveText := Copy(aSource.fText, lDirectiveStartOffset,
            lDirectiveEndOffset - lDirectiveStartOffset + 1);
          RemoveWithDirectiveLineRange(aSource, lDirectiveStartOffset, lLineStartOffset, lDirectiveLineEndOffset);

          if (RemoveWithDirectiveSymbol(lDirectiveText, 'IFDEF') <> '') or
            (RemoveWithDirectiveSymbol(lDirectiveText, 'IFNDEF') <> '') then
          begin
            lParentActive := True;
            if lFrames.Count > 0 then
              lParentActive := lFrames.Last.fCurrentActive;
            lConditionActive := lParentActive and RemoveWithDirectiveConditionValue(lDirectiveText, lDefines);
            lFrame.fParentActive := lParentActive;
            lFrame.fCurrentActive := lConditionActive;
            lFrame.fBranchTaken := lConditionActive;
            lFrame.fInactiveStartOffset := 0;
            if not lFrame.fCurrentActive then
              lFrame.fInactiveStartOffset := lDirectiveEndOffset + 1;
            lFrames.Add(lFrame);
          end else if (RemoveWithDirectiveSymbol(lDirectiveText, 'ELSEIF Defined(') <> '') and
            (lFrames.Count > 0) then
          begin
            lFrameIndex := lFrames.Count - 1;
            lFrame := lFrames[lFrameIndex];
            if not lFrame.fCurrentActive then
              RemoveWithAddInactiveRange(Result, lFrame.fInactiveStartOffset, lDirectiveStartOffset - 1)
            else
              lFrame.fInactiveStartOffset := lDirectiveEndOffset + 1;
            lConditionActive := lFrame.fParentActive and (not lFrame.fBranchTaken) and
              RemoveWithDirectiveConditionValue(lDirectiveText, lDefines);
            lFrame.fCurrentActive := lConditionActive;
            lFrame.fBranchTaken := lFrame.fBranchTaken or lConditionActive;
            if lFrame.fCurrentActive then
              lFrame.fInactiveStartOffset := 0
            else
              lFrame.fInactiveStartOffset := lDirectiveEndOffset + 1;
            lFrames[lFrameIndex] := lFrame;
          end else if RemoveWithDirectiveIsElse(lDirectiveText) and (lFrames.Count > 0) then
          begin
            lFrameIndex := lFrames.Count - 1;
            lFrame := lFrames[lFrameIndex];
            if not lFrame.fCurrentActive then
              RemoveWithAddInactiveRange(Result, lFrame.fInactiveStartOffset, lDirectiveStartOffset - 1)
            else
              lFrame.fInactiveStartOffset := lDirectiveEndOffset + 1;
            lFrame.fCurrentActive := lFrame.fParentActive and (not lFrame.fBranchTaken);
            lFrame.fBranchTaken := True;
            if lFrame.fCurrentActive then
              lFrame.fInactiveStartOffset := 0
            else
              lFrame.fInactiveStartOffset := lDirectiveEndOffset + 1;
            lFrames[lFrameIndex] := lFrame;
          end else if RemoveWithDirectiveIsEnd(lDirectiveText) and (lFrames.Count > 0) then
          begin
            lFrameIndex := lFrames.Count - 1;
            lFrame := lFrames[lFrameIndex];
            if not lFrame.fCurrentActive then
              RemoveWithAddInactiveRange(Result, lFrame.fInactiveStartOffset, lDirectiveStartOffset - 1);
            lFrames.Delete(lFrameIndex);
          end;

          i := lDirectiveEndOffset + 1;
          Continue;
        end;
        Inc(i);
      end;

      for lFrame in lFrames do
      begin
        if not lFrame.fCurrentActive then
          RemoveWithAddInactiveRange(Result, lFrame.fInactiveStartOffset, Length(aSource.fText));
      end;
    finally
      lFrames.Free;
    end;
  finally
    lDefines.Free;
  end;
end;

function RemoveWithOffsetInInactiveRanges(const aOffset: Integer;
  const aRanges: TArray<TRemoveWithInactiveRange>): Boolean;
var
  lRange: TRemoveWithInactiveRange;
begin
  Result := False;
  for lRange in aRanges do
  begin
    if (aOffset >= lRange.fStartOffset) and (aOffset <= lRange.fEndOffset) then
      Exit(True);
  end;
end;

end.
