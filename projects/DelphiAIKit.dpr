program DelphiAIKit;

{$APPTYPE CONSOLE}

uses
  madExcept,
  madLinkDisAsm,
  madListHardware,
  madListProcesses,
  madListModules,
  Dak.App in '..\src\dak.app.pas';

begin
  Halt(TDelphiAIKitApp.Run);
end.
