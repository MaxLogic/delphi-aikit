program GlobalVarsFixture;

uses
  {$IFDEF NeverDefined}
  MissingFixture.Unit in 'MissingFixture.Unit.pas',
  {$ENDIF}
  GlobalVarsFixture.Consumer in 'GlobalVarsFixture.Consumer.pas',
  GlobalVarsFixture.Globals in 'GlobalVarsFixture.Globals.pas' { LegacyFixture.Unit in 'LegacyFixture.Unit.pas' };

begin
end.
