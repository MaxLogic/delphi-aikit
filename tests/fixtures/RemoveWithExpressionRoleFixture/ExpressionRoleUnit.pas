unit ExpressionRoleUnit;

interface

type
  TExpressionRoleItem = record
    Count: Integer;
    Name: string;
  end;

  PExpressionRoleItem = ^TExpressionRoleItem;

  TExpressionRoleScope = class
  public
    class function DefaultName: string; static;
    class procedure Run(aItemPtr: PExpressionRoleItem);
  end;

implementation

uses
  System.SysUtils,
  ExpressionRoleSupportUnit;

class function TExpressionRoleScope.DefaultName: string;
begin
  Result := 'default';
end;

class procedure TExpressionRoleScope.Run(aItemPtr: PExpressionRoleItem);
label
  LocalLabel;
begin
  with aItemPtr^ do
  begin
    goto LocalLabel;
LocalLabel:
    Name := 'label';
  end;

  with aItemPtr^ do
  begin
    case Count of
      0:
        Name := 'case';
    end;
  end;

  with aItemPtr^ do
  begin
    Name := TExpressionRoleScope.DefaultName;
  end;

  with aItemPtr^ do
  begin
    var Name := 'local';
    Count := Length(Name);
  end;

  with aItemPtr^ do
  begin
    ExpressionRoleSupportUnit.TouchName(Name);
  end;
end;

end.
