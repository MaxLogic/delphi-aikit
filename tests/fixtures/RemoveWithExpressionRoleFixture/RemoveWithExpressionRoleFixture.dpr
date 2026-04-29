program RemoveWithExpressionRoleFixture;

uses
  ExpressionRoleUnit in 'ExpressionRoleUnit.pas',
  ExpressionRoleSupportUnit in 'ExpressionRoleSupportUnit.pas';

var
  lItem: TExpressionRoleItem;

begin
  TExpressionRoleScope.Run(@lItem);
end.
