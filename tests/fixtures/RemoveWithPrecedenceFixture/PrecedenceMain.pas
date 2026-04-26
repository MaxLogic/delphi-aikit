unit PrecedenceMain;

interface

type
  TNamedRecord = record
    id: string;
    OuterOnly: string;
  end;

  TInnerRecord = record
    id: string;
  end;

  TEmptyRecord = record
    Marker: string;
  end;

  TReceiverRecord = record
    GlobalName: string;
    id: string;
    function Pick(aValue: Integer): string; overload;
    function Pick(const aValue: string): string; overload;
  end;

  TAncestorClass = class
  public
    id: string;
  end;

  TDescendantClass = class(TAncestorClass)
  end;

  THelperRecord = record
    Raw: string;
  end;

  THelperRecordHelper = record helper for THelperRecord
  private
    function GetHelperName: string;
  public
    property HelperName: string read GetHelperName;
  end;

  TCurrentScope = class
  private
    CurrentOnly: string;
    id: string;
  public
    procedure Run;
  end;

  TPrecedenceFixture = class
  public
    class procedure Run;
  end;

implementation

uses
  System.SysUtils;

var
  gGlobalOnly: string;
  GlobalName: string;

function Pick(aValue: Integer): string; overload;
begin
  Result := 'global-int';
end;

function Pick(const aValue: string): string; overload;
begin
  Result := 'global-string';
end;

function TReceiverRecord.Pick(aValue: Integer): string;
begin
  Result := 'receiver-int';
end;

function TReceiverRecord.Pick(const aValue: string): string;
begin
  Result := 'receiver-string';
end;

function THelperRecordHelper.GetHelperName: string;
begin
  Result := Raw;
end;

procedure Emit(const aLine: string);
begin
  Writeln(aLine);
end;

procedure RunSelectorOrder;
var
  lLeft: TNamedRecord;
  lRight: TNamedRecord;
begin
  lLeft.id := 'left';
  lRight.id := 'right';

  with lLeft, lRight do
    Emit('selector-order=' + id);
end;

procedure RunNestedWith;
var
  lInner: TInnerRecord;
  lOuter: TNamedRecord;
begin
  lOuter.id := 'outer';
  lOuter.OuterOnly := 'outer-only';
  lInner.id := 'inner';

  with lOuter do
  begin
    with lInner do
    begin
      Emit('nested-inner=' + id);
      Emit('nested-fallback=' + OuterOnly);
    end;
  end;
end;

procedure RunLocalAndParameterPrecedence(const id: string);
var
  lEmpty: TEmptyRecord;
  lReceiver: TReceiverRecord;
  s: string;
begin
  lReceiver.id := 'receiver';
  lEmpty.Marker := '';
  s := 'local-only';

  with lReceiver do
    Emit('selector-beats-local=' + id);
  with lEmpty do
    Emit('local-fallback=' + s + Marker);

  with lReceiver do
    Emit('selector-beats-param=' + id);
  with lEmpty do
    Emit('param-fallback=' + id + Marker);
end;

procedure TCurrentScope.Run;
var
  lEmpty: TEmptyRecord;
  lReceiver: TReceiverRecord;
begin
  id := 'current';
  CurrentOnly := 'current-only';
  lEmpty.Marker := '';
  lReceiver.id := 'receiver';

  with lReceiver do
    Emit('selector-beats-current=' + id);
  with lEmpty do
    Emit('current-fallback=' + CurrentOnly + Marker);
end;

procedure RunCurrentScopePrecedence;
var
  lScope: TCurrentScope;
begin
  lScope := TCurrentScope.Create;
  try
    lScope.Run;
  finally
    lScope.Free;
  end;
end;

procedure RunGlobalPrecedence;
var
  lEmpty: TEmptyRecord;
  lReceiver: TReceiverRecord;
begin
  GlobalName := 'global';
  gGlobalOnly := 'global-only';
  lEmpty.Marker := '';
  lReceiver.GlobalName := 'receiver';

  with lReceiver do
    Emit('selector-beats-global=' + GlobalName);
  with lEmpty do
    Emit('global-fallback=' + gGlobalOnly + Marker);
end;

procedure RunInheritedPrecedence;
var
  lDescendant: TDescendantClass;
begin
  lDescendant := TDescendantClass.Create;
  try
    lDescendant.id := 'ancestor';
    with lDescendant do
      Emit('inherited-member=' + id);
  finally
    lDescendant.Free;
  end;
end;

procedure RunHelperPrecedence;
var
  lHelper: THelperRecord;
begin
  lHelper.Raw := 'helper';
  with lHelper do
    Emit('helper-member=' + HelperName);
end;

procedure RunOverloadPrecedence;
var
  lReceiver: TReceiverRecord;
begin
  with lReceiver do
  begin
    Emit('overload-int=' + Pick(1));
    Emit('overload-string=' + Pick('x'));
  end;
end;

class procedure TPrecedenceFixture.Run;
begin
  RunSelectorOrder;
  RunNestedWith;
  RunLocalAndParameterPrecedence('param-only');
  RunCurrentScopePrecedence;
  RunGlobalPrecedence;
  RunInheritedPrecedence;
  RunHelperPrecedence;
  RunOverloadPrecedence;
end;

end.
