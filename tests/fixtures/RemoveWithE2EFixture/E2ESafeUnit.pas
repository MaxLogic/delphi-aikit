unit E2ESafeUnit;

interface

type
  TE2ECustomer = record
    Count: Integer;
    Name: string;
  end;

  PE2ECustomer = ^TE2ECustomer;

  TE2ESafeScope = class
  public
    class procedure Apply(aCustomerPtr: PE2ECustomer);
  end;

implementation

class procedure TE2ESafeScope.Apply(aCustomerPtr: PE2ECustomer);
begin
  with aCustomerPtr^ do
  begin
    Name := 'e2e';
    Count := Count + 1;
  end;
end;

end.
