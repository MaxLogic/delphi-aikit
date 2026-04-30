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

function LoadRemoveWithSource(const aPath: string; out aSource: TRemoveWithSourceBuffer; out aError: string): Boolean;
function RemoveWithSourceEncodingToText(const aEncoding: TRemoveWithSourceEncoding;
  const aHasUtf8Bom: Boolean): string;
function RemoveWithTextToBytes(const aText: string; const aEncoding: TRemoveWithSourceEncoding;
  const aHasUtf8Bom: Boolean): TBytes;
function RemoveWithOffsetForLineColumn(const aSource: TRemoveWithSourceBuffer; const aLine,
  aColumn: Integer; out aOffset: Integer): Boolean;
function RemoveWithLineColumnForOffset(const aSource: TRemoveWithSourceBuffer; const aOffset: Integer;
  out aLine, aColumn: Integer): Boolean;
function RemoveWithTextSlice(const aSource: TRemoveWithSourceBuffer; const aStartOffset,
  aEndOffset: Integer): string;

implementation

uses
  System.IOUtils;

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

function RemoveWithTextSlice(const aSource: TRemoveWithSourceBuffer; const aStartOffset,
  aEndOffset: Integer): string;
begin
  if (aStartOffset < 1) or (aEndOffset < aStartOffset) or (aEndOffset > Length(aSource.fText)) then
    Exit('');

  Result := Copy(aSource.fText, aStartOffset, aEndOffset - aStartOffset + 1);
end;

end.
