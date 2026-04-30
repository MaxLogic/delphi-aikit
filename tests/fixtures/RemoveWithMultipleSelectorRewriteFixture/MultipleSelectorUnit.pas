unit MultipleSelectorUnit;

interface

type
  TMultiLeft = class
  private
    fCommon: string;
    fLeftOnly: string;
  public
    property Common: string read fCommon write fCommon;
    property LeftOnly: string read fLeftOnly write fLeftOnly;
  end;

  TMultiRight = class
  private
    fCode1: string;
    fCommon: string;
    fRightOnly: string;
  public
    property Code1: string read fCode1 write fCode1;
    property Common: string read fCommon write fCommon;
    property RightOnly: string read fRightOnly write fRightOnly;
  end;

  TMultiIndexRecord = record
    Index: Integer;
  end;

  TMultiPair = class
  private
    fLeft: TMultiLeft;
    fRight: TMultiRight;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure Run;
    class procedure RunDependentSelector;
  end;

implementation

constructor TMultiPair.Create;
begin
  inherited Create;
  fLeft := TMultiLeft.Create;
  fRight := TMultiRight.Create;
end;

destructor TMultiPair.Destroy;
begin
  fRight.Free;
  fLeft.Free;
  inherited Destroy;
end;

class procedure TMultiPair.Run;
var
  lPair: TMultiPair;
begin
  lPair := TMultiPair.Create;
  try
    lPair.fLeft.Common := 'left-original';
    lPair.fRight.Common := 'right-original';
    with lPair.fLeft, lPair.fRight do
    begin
      Code1 := 'right-code';
      Common := 'right';
      LeftOnly := 'left';
      RightOnly := 'right-only';
    end;
  finally
    lPair.Free;
  end;
end;

class procedure TMultiPair.RunDependentSelector;
var
  lIndex: TMultiIndexRecord;
  lItems: array[0..1] of TMultiRight;
begin
  lItems[0] := TMultiRight.Create;
  lItems[1] := TMultiRight.Create;
  try
    lIndex.Index := 1;
    with lIndex, lItems[Index] do
    begin
      RightOnly := 'dependent';
    end;
  finally
    lItems[1].Free;
    lItems[0].Free;
  end;
end;

end.
