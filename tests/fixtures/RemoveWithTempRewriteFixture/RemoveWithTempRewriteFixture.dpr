program RemoveWithTempRewriteFixture;

uses
  TempRewriteUnit in 'TempRewriteUnit.pas';

var
  lRecord: TTempRewriteRecord;

begin
  TTempRewriteScope.Run(@lRecord);
end.
