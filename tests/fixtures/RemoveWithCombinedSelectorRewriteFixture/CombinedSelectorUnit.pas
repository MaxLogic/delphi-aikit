unit CombinedSelectorUnit;

interface

type
  TCombinedOuterLeft = class
  private
    fLeftOuterOnly: string;
    fSharedOuter: string;
  public
    property LeftOuterOnly: string read fLeftOuterOnly write fLeftOuterOnly;
    property SharedOuter: string read fSharedOuter write fSharedOuter;
  end;

  TCombinedOuterRight = class
  private
    fRightOuterOnly: string;
    fSharedOuter: string;
  public
    property RightOuterOnly: string read fRightOuterOnly write fRightOuterOnly;
    property SharedOuter: string read fSharedOuter write fSharedOuter;
  end;

  TCombinedInnerLeft = class
  private
    fInnerShared: string;
    fLeftInnerOnly: string;
  public
    property InnerShared: string read fInnerShared write fInnerShared;
    property LeftInnerOnly: string read fLeftInnerOnly write fLeftInnerOnly;
  end;

  TCombinedInnerRight = class
  private
    fInnerShared: string;
    fRightInnerOnly: string;
  public
    property InnerShared: string read fInnerShared write fInnerShared;
    property RightInnerOnly: string read fRightInnerOnly write fRightInnerOnly;
  end;

  TCombinedDuplicate = record
    Raw: string;
  end;

  TCombinedDuplicateHelperA = record helper for TCombinedDuplicate
    procedure Clash;
  end;

  TCombinedDuplicateHelperB = record helper for TCombinedDuplicate
    procedure Clash;
  end;

  TCombinedSelectorScope = class
  public
    class procedure RunSafe;
    class procedure RunMixed;
  end;

implementation

procedure TCombinedDuplicateHelperA.Clash;
begin
end;

procedure TCombinedDuplicateHelperB.Clash;
begin
end;

class procedure TCombinedSelectorScope.RunSafe;
var
  lInnerLeft: TCombinedInnerLeft;
  lInnerRight: TCombinedInnerRight;
  lOuterLeft: TCombinedOuterLeft;
  lOuterRight: TCombinedOuterRight;
begin
  lOuterLeft := TCombinedOuterLeft.Create;
  lOuterRight := TCombinedOuterRight.Create;
  lInnerLeft := TCombinedInnerLeft.Create;
  lInnerRight := TCombinedInnerRight.Create;
  try
    lOuterRight.RightOuterOnly := 'before-safe';
    with lOuterLeft, lOuterRight do
    begin
      SharedOuter := 'outer-right';
      LeftOuterOnly := 'outer-left';
      with lInnerLeft, lInnerRight do
      begin
        InnerShared := 'inner-right';
        LeftInnerOnly := 'inner-left';
        RightInnerOnly := 'inner-right';
        RightOuterOnly := 'outer-fallback';
      end;
      RightOuterOnly := 'outer-after';
    end;
  finally
    lInnerRight.Free;
    lInnerLeft.Free;
    lOuterRight.Free;
    lOuterLeft.Free;
  end;
end;

class procedure TCombinedSelectorScope.RunMixed;
var
  lAmbiguous: TCombinedDuplicate;
  lOuterLeft: TCombinedOuterLeft;
  lOuterRight: TCombinedOuterRight;
  lSafeLeft: TCombinedOuterLeft;
  lSafeRight: TCombinedOuterRight;
begin
  lOuterLeft := TCombinedOuterLeft.Create;
  lOuterRight := TCombinedOuterRight.Create;
  lSafeLeft := TCombinedOuterLeft.Create;
  lSafeRight := TCombinedOuterRight.Create;
  try
    lOuterRight.RightOuterOnly := 'before-mixed';
    with lOuterLeft, lOuterRight do
    begin
      with lSafeRight do
      begin
        RightOuterOnly := 'safe-under-blocked-parent';
      end;
      with lAmbiguous do
      begin
        Clash();
      end;
    end;

    with lSafeLeft, lSafeRight do
    begin
      RightOuterOnly := 'safe-unrelated';
    end;
  finally
    lSafeRight.Free;
    lSafeLeft.Free;
    lOuterRight.Free;
    lOuterLeft.Free;
  end;
end;

end.
