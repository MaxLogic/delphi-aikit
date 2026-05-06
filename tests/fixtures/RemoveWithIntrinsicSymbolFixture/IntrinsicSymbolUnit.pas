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
  end;

implementation

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
    GetMem(Ptr, SizeOf(Integer));
    FreeMem(Ptr);
    New(Ptr);
    Dispose(Ptr);
    Seek(lUntypedFile, Count);
    BlockRead(lUntypedFile, Data, SizeOf(Data));
    BlockWrite(lUntypedFile, Data, SizeOf(Data));
    Assign(lTextFile, Text);
    Rewrite(lTextFile);
    Write(lTextFile, Text);
    Writeln(lTextFile, Text);
    Read(lTextFile, Text);
    Readln(lTextFile, Text);
    Flush(lTextFile);
    Close(lTextFile);
    Target := FilePos(lUntypedFile) + Copy(Text, 1, 1).Length + Pred(Count);
    Target := Abs(Count) + Sqr(Count) + Succ(Count);
    Assert(Target >= 0);
    if EOF(lTextFile) then
      Target := Target + 1;
  end;

  with lUnknown do
  begin
    Count := UnknownProjectRoutine(Count);
  end;
end;

end.
