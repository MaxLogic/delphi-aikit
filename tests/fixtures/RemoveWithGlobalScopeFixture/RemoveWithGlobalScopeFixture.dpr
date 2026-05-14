program RemoveWithGlobalScopeFixture;

uses
  GlobalScopeMain in 'GlobalScopeMain.pas',
  GlobalScopeSupport in 'GlobalScopeSupport.pas',
  ScopedSupport.Nested in 'ScopedSupport.Nested.pas';

begin
  TGlobalScope.Run('');
end.
