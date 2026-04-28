unit AncestorHelperUnit;

interface

uses
  System.Classes;

type
  TBaseWithClass = class
  private
    FBaseName: string;
  public
    const
      BaseLimit: Integer = 9;
    class var
      BaseCount: Integer;
    procedure BaseTouch;
    property BaseName: string read FBaseName write FBaseName;
  end;

  TDerivedWithClass = class(TBaseWithClass)
  private
    FDerivedName: string;
  public
    procedure DerivedTouch;
    procedure Run;
    property DerivedName: string read FDerivedName write FDerivedName;
  end;

  TGrandDerivedWithClass = class(TDerivedWithClass)
  end;

  TExternalDerivedList = class(TStringList)
  end;

  THelperRecordTarget = record
    Value: string;
  end;

  THelperRecordTargetHelper = record helper for THelperRecordTarget
    function GetHelperValue: string;
    procedure Normalize;
    property HelperValue: string read GetHelperValue;
  end;

  THelperClassTarget = class
  public
    Data: string;
  end;

  THelperClassTargetHelper = class helper for THelperClassTarget
    procedure ClearData;
    function GetHelperData: string;
    property HelperData: string read GetHelperData;
  end;

  TInheritedClassTargetHelper = class helper(THelperClassTargetHelper) for THelperClassTarget
    procedure UnsupportedInheritedHelper;
  end;

  TStringListVisibleHelper = class helper for TStringList
    procedure ExternalTargetHelper;
  end;

implementation

procedure TBaseWithClass.BaseTouch;
begin
  Inc(BaseCount);
end;

procedure TDerivedWithClass.DerivedTouch;
begin
  DerivedName := BaseName;
end;

procedure TDerivedWithClass.Run;
begin
  BaseName := '';
end;

function THelperRecordTargetHelper.GetHelperValue: string;
begin
  Result := Value;
end;

procedure THelperRecordTargetHelper.Normalize;
begin
  Value := Trim(Value);
end;

procedure THelperClassTargetHelper.ClearData;
begin
  Data := '';
end;

function THelperClassTargetHelper.GetHelperData: string;
begin
  Result := Data;
end;

procedure TInheritedClassTargetHelper.UnsupportedInheritedHelper;
begin
end;

procedure TStringListVisibleHelper.ExternalTargetHelper;
begin
  Add('');
end;

end.
