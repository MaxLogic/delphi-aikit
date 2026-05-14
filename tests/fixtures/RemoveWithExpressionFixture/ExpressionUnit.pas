unit ExpressionUnit;

interface

uses
  System.Classes, System.SysUtils;

type
  TExpressionChild = record
    Name: string;
  end;

  TExpressionRecord = record
    Child: TExpressionChild;
  end;

  TExpressionNestedRecord = record
    Struktur: packed record
      RecSize: Integer;
    end;
  end;

  TExpressionRecordAlias = TExpressionRecord;
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

type
  TExpressionImplementationAlias = TExpressionRecord;
  TExpressionSearchRecAlias = TSearchRec;

class procedure TExpressionScope.Run(const aParamRecord: TExpressionRecord; aExternalList: TStringList);
var
  lAnonymous: packed record
    Value: TExpressionChild;
  end;
  lAliasPtr: PExpressionAlias;
  lImplementationAlias: TExpressionImplementationAlias;
  lAliasRecord: TExpressionRecordAlias;
  lLocalRecord: TExpressionRecord;
  lNested: TExpressionNestedRecord;
  lParentPtr: PExpressionRecord;
  lRecordPtr: PExpressionRecord;
  lRecords: TArray<TExpressionRecord>;
  lSearchAlias: TExpressionSearchRecAlias;
  lSearchRec: TSearchRec;
  lExternalList: TStringList;

  procedure ResolveParentSelector;
  begin
    lParentPtr := @lLocalRecord;
  end;

begin
  lLocalRecord := aParamRecord;
  lAnonymous.Value.Name := lLocalRecord.Child.Name;
  lNested.Struktur.RecSize := 0;
  lAliasPtr := @lLocalRecord;
  lImplementationAlias := lLocalRecord;
  lAliasRecord := lLocalRecord;
  lParentPtr := nil;
  lRecordPtr := @lLocalRecord;
  GlobalRecordPtrs[0] := lRecordPtr;
  lSearchAlias := Default(TExpressionSearchRecAlias);
  lSearchRec := Default(TSearchRec);
  SetLength(lRecords, 1);
  lRecords[0] := lRecordPtr^;
  ResolveParentSelector;
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
