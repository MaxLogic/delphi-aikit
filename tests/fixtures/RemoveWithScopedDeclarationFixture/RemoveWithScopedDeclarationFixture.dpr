program RemoveWithScopedDeclarationFixture;

uses
  ScopedDeclarationUnit in 'ScopedDeclarationUnit.pas';

var
  lItem: TScopedDeclarationItem;

begin
  TScopedDeclarationScope.Run(@lItem);
end.
