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
    fCommon: string;
    fRightOnly: string;
  public
    property Common: string read fCommon write fCommon;
    property RightOnly: string read fRightOnly write fRightOnly;
  end;

  TMultiPair = class
  private
    fLeft: TMultiLeft;
    fRight: TMultiRight;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure Run;
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
      Common := 'right';
      LeftOnly := 'left';
      RightOnly := 'right-only';
    end;
  finally
    lPair.Free;
  end;
end;

end.
