unit ExpressionUnit;

interface

uses
  System.Classes;

type
  TExpressionChild = record
    Name: string;
  end;

  TExpressionRecord = record
    Child: TExpressionChild;
  end;

  PExpressionRecord = ^TExpressionRecord;
  TExpressionRecordPtrArray = array[0..1] of PExpressionRecord;

  TOtherExpression = record
    OtherRecord: TExpressionRecord;
  end;

  TExpressionScope = class
  private
    FRecord: TExpressionRecord;
  public
    property ClassProp: TExpressionRecord read FRecord;
    class procedure Run(const aParamRecord: TExpressionRecord; aExternalList: TStringList);
    class procedure OtherRun;
  end;

  PExpressionAlias = ^TExpressionRecord;

var
  GlobalRecordPtrs: TExpressionRecordPtrArray;

implementation

class procedure TExpressionScope.Run(const aParamRecord: TExpressionRecord; aExternalList: TStringList);
var
  lAliasPtr: PExpressionAlias;
  lLocalRecord: TExpressionRecord;
  lRecordPtr: PExpressionRecord;
  lRecords: TArray<TExpressionRecord>;
  lExternalList: TStringList;
begin
  lLocalRecord := aParamRecord;
  lAliasPtr := @lLocalRecord;
  lRecordPtr := @lLocalRecord;
  GlobalRecordPtrs[0] := lRecordPtr;
  SetLength(lRecords, 1);
  lRecords[0] := lRecordPtr^;
  lExternalList := aExternalList;
  if Assigned(lExternalList) then
    lLocalRecord.Child.Name := lExternalList.ClassName;
end;

class procedure TExpressionScope.OtherRun;
var
  lOtherOnly: TExpressionRecord;
begin
  lOtherOnly := Default(TExpressionRecord);
end;

end.
