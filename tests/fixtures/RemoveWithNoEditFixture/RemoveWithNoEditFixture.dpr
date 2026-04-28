program RemoveWithNoEditFixture;

uses
  NoEditBlockedUnit in 'NoEditBlockedUnit.pas',
  NoEditSkippedUnit in 'NoEditSkippedUnit.pas';

var
  lRecord: TNoEditBlockedRecord;

begin
  TNoEditBlockedScope.KeepBlocked(@lRecord);
  TNoEditHolder.KeepSkipped;
end.
