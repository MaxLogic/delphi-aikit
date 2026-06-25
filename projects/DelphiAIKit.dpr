program DelphiAIKit;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  FireDAC.Phys.SQLiteWrapper.Stat,
  madExcept,
  madLinkDisAsm,
  madListHardware,
  madListProcesses,
  madListModules,
  Dak.App in '..\src\dak.app.pas';

begin
  Halt(TDelphiAIKitApp.Run);
end.
