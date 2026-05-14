unit IntrinsicSymbolUnit;

interface

type
  TIntrinsicRecord = record
    Count: Integer;
    Data: array[0..7] of Byte;
    Ptr: Pointer;
    Target: Integer;
    Text: string;
  end;

  TIntrinsicScope = class
  public
    class procedure Run;
    class procedure RunUntyped(const aValue);
  end;

implementation

uses
  System.SysUtils;

class procedure TIntrinsicScope.Run;
var
  lCode: Integer;
  lTextFile: Text;
  lUntypedFile: file;
  lKnown: TIntrinsicRecord;
  lUnknown: TIntrinsicRecord;
begin
  with lKnown do
  begin
    IOResult;
    System.Val(Text, Target, lCode);
    Target := SizeOf(Int32);
    Inc(Count);
    Dec(Count);
    if Low(Text) <= High(Text) then
      Target := Count;
    Addr(Count);
    Ptr := PByte(Ptr);
    GetMem(Ptr, SizeOf(Integer));
    FreeMem(Ptr);
    New(Ptr);
    Dispose(Ptr);
    Seek(lUntypedFile, Count);
    BlockRead(lUntypedFile, Data, SizeOf(Data));
    BlockWrite(lUntypedFile, Data, SizeOf(Data));
    Assign(lTextFile, Text);
    Reset(lTextFile);
    Rewrite(lTextFile);
    Write(lTextFile, Text);
    Writeln(lTextFile, Text);
    Read(lTextFile, Text);
    Readln(lTextFile, Text);
    Flush(lTextFile);
    Close(lTextFile);
    Target := FilePos(lUntypedFile) + Copy(Text, 1, 1).Length + Pred(Count);
    Target := Abs(Count) + Sqr(Count) + Succ(Count);
    Target := Max(Target, Min(Count, Target));
    Target := Round(FileDateToDateTime(0)) + abs(Count) + succ(Count);
    Text := ExpandFileName(Text);
    ReallocMem(Ptr, SizeOf(Integer));
    Assert(Target >= 0);
    if EOF(lTextFile) then
      Target := Target + 1;
  end;

  with lUnknown do
  begin
    Count := UnknownProjectRoutine(Count);
  end;
end;

class procedure TIntrinsicScope.RunUntyped(const aValue);
var
  lKnown: TIntrinsicRecord;
begin
  with lKnown do
  begin
    Move(aValue, Target, SizeOf(Target));
  end;
end;

end.
