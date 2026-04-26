unit Dak.RemoveWith.Source;

interface

uses
  System.SysUtils;

type
  TRemoveWithSourceBuffer = record
    fPath: string;
    fText: string;
    fHasUtf8Bom: Boolean;
    fLineStarts: TArray<Integer>;
  end;

function LoadRemoveWithSource(const aPath: string; out aSource: TRemoveWithSourceBuffer; out aError: string): Boolean;
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
    aSource.fText := TEncoding.UTF8.GetString(lBytes, lOffset, Length(lBytes) - lOffset);
    BuildLineStarts(aSource);
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
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
