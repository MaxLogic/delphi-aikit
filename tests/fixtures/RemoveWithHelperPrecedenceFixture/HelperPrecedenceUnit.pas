unit HelperPrecedenceUnit;

interface

uses
  System.Classes;

type
  TDirectHelperRecord = record
    SharedName: string;
    procedure DirectMethod;
  end;

  TDirectHelperRecordHelper = record helper for TDirectHelperRecord
    function GetSharedName: string;
    procedure DirectMethod;
    property SharedName: string read GetSharedName;
  end;

  THelperOnlyRecord = record
    Raw: string;
  end;

  THelperOnlyRecordHelper = record helper for THelperOnlyRecord
    function GetHelperValue: string;
    procedure Normalize;
    property HelperValue: string read GetHelperValue;
  end;

  TMultiHelperTarget = record
    Raw: string;
  end;

  TMultiHelperA = record helper for TMultiHelperTarget
    procedure Clash;
  end;

  TMultiHelperB = record helper for TMultiHelperTarget
    procedure Clash;
  end;

  TChainWrapper = record
    Target: THelperOnlyRecord;
  end;

  TClassHelperTarget = class
  public
    Data: string;
  end;

  TClassHelperTargetHelper = class helper for TClassHelperTarget
    function GetHelperData: string;
    procedure ClearData;
    property HelperData: string read GetHelperData;
  end;

  TStringListHelperForPrecedence = class helper for TStringList
    procedure ExternalHelper;
  end;

  THelperPrecedenceScope = class
  public
    class procedure Run;
  end;

implementation

procedure TDirectHelperRecord.DirectMethod;
begin
end;

function TDirectHelperRecordHelper.GetSharedName: string;
begin
  Result := '';
end;

procedure TDirectHelperRecordHelper.DirectMethod;
begin
end;

function THelperOnlyRecordHelper.GetHelperValue: string;
begin
  Result := Raw;
end;

procedure THelperOnlyRecordHelper.Normalize;
begin
  Raw := Trim(Raw);
end;

procedure TMultiHelperA.Clash;
begin
end;

procedure TMultiHelperB.Clash;
begin
end;

function TClassHelperTargetHelper.GetHelperData: string;
begin
  Result := Data;
end;

procedure TClassHelperTargetHelper.ClearData;
begin
  Data := '';
end;

procedure TStringListHelperForPrecedence.ExternalHelper;
begin
  Add('');
end;

class procedure THelperPrecedenceScope.Run;
var
  lClassHelper: TClassHelperTarget;
  lDirect: TDirectHelperRecord;
  lExternal: TStringList;
  lHelperOnly: THelperOnlyRecord;
  lMulti: TMultiHelperTarget;
  lWrapper: TChainWrapper;
begin
  with lDirect do
  begin
    SharedName := '';
    DirectMethod;
  end;

  with lHelperOnly do
  begin
    Normalize;
    HelperValue;
  end;

  with lMulti do
  begin
    Clash();
  end;

  with lWrapper.Target do
  begin
    HelperValue;
  end;

  with lClassHelper do
  begin
    ClearData;
    HelperData;
  end;

  with lExternal do
  begin
    ExternalHelper;
  end;
end;

end.
