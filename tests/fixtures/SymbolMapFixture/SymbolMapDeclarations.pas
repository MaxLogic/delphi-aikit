unit SymbolMapDeclarations;

interface

type
  TDeclarationEnum = (deOne, deTwo);
  TDeclarationAlias = string;
  TDeclarationRecord = record
    Value: Integer;
  end;
  TDeclarationClass = class
  public
    procedure Run;
  end;

const
  cDeclarationConst = 42;
  cDeclarationTyped: Integer = 7;

var
  GDeclarationGlobal: Integer;

procedure DeclarationProcedure(const aName: string);
function DeclarationFunction: Integer;
function DeclarationMultiParam(const aName: string; const aValue: Integer): Boolean;

implementation

const
  cImplementationConst = 'impl';

var
  GImplementationGlobal: string;

procedure DeclarationProcedure(const aName: string);
begin
end;

function DeclarationFunction: Integer;
begin
  Result := 1;
end;

function DeclarationMultiParam(const aName: string; const aValue: Integer): Boolean;
begin
  Result := aName <> '';
end;

procedure ImplementationOnlyProcedure;
const
  cLocalConst = 1;
type
  TLocalType = Integer;
var
  lLocalValue: TLocalType;
begin
  lLocalValue := cLocalConst;
end;

end.
