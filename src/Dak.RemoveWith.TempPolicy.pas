unit Dak.RemoveWith.TempPolicy;

interface

uses
  Dak.RemoveWith.Symbols;

type
  TRemoveWithTempStrategy = (rwtsSkip, rwtsDirectQualification, rwtsReferenceTemp, rwtsRecordPointerTemp);

  TRemoveWithReservedTempNames = record
    fNames: TArray<string>;
  end;

  TRemoveWithTempDecision = record
    fSelectorText: string;
    fReceiverType: string;
    fTempName: string;
    fDeclarationText: string;
    fInitializationText: string;
    fQualifierText: string;
    fReason: string;
    fStrategy: TRemoveWithTempStrategy;
  end;

function RemoveWithTempStrategyToText(const aStrategy: TRemoveWithTempStrategy): string;
procedure BeginRemoveWithTempPolicyCache(const aInventory: TRemoveWithSymbolInventory);
procedure EndRemoveWithTempPolicyCache;
function PlanRemoveWithTempPolicy(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
  aSelectorText: string; out aDecision: TRemoveWithTempDecision): Boolean; overload;
function PlanRemoveWithTempPolicy(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
  aSelectorText: string; var aReservedNames: TRemoveWithReservedTempNames;
  out aDecision: TRemoveWithTempDecision): Boolean; overload;

implementation

uses
  System.Generics.Collections, System.StrUtils, System.SysUtils,
  MaxLogic.StrUtils,
  Dak.RemoveWith.Expressions, Dak.RemoveWith.Model;

type
  TRemoveWithTempPolicy = record
  private
    class function DirectTypeName(const aTypeName: string): string; static;
    class function CanonicalSourceTypeName(const aInventory: TRemoveWithSymbolInventory;
      const aTypeName: string): string; static;
    class function IsIdentifierChar(const aValue: Char): Boolean; static;
    class function IsSimpleIdentifier(const aText: string): Boolean; static;
    class function IsPureUnitLevelSelector(const aText: string): Boolean; static;
    class function TypeCategory(const aInventory: TRemoveWithSymbolInventory;
      const aTypeName: string): TRemoveWithTypeCategory; static;
    class function SelectorUsesPointerDeref(const aSelectorText: string): Boolean; static;
    class function TempBaseName(const aTypeName: string): string; static;
    class function ReservedNameExists(const aReservedNames: TRemoveWithReservedTempNames;
      const aName: string): Boolean; static;
    class function NameExists(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
      aName: string; const aReservedNames: TRemoveWithReservedTempNames): Boolean; static;
    class function UniqueTempName(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
      aBaseName: string; const aReservedNames: TRemoveWithReservedTempNames): string; static;
    class procedure ReserveName(var aReservedNames: TRemoveWithReservedTempNames; const aName: string); static;
    class function ReserveUniqueTempName(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
      aBaseName: string; var aReservedNames: TRemoveWithReservedTempNames): string; static;
    class procedure SetSkip(out aDecision: TRemoveWithTempDecision; const aSelectorText, aReason: string); static;
  public
    class function Plan(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
      aSelectorText: string; out aDecision: TRemoveWithTempDecision): Boolean; overload; static;
    class function Plan(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
      aSelectorText: string; var aReservedNames: TRemoveWithReservedTempNames;
      out aDecision: TRemoveWithTempDecision): Boolean; overload; static;
  end;

var
  GTempPolicyCacheDepth: Integer;
  GTempPolicySymbolNameIndex: TDictionary<string, TArray<TRemoveWithSymbolInfo>>;

procedure EnsureTempPolicySymbolNameIndex(const aInventory: TRemoveWithSymbolInventory);
var
  lBuckets: TDictionary<string, TList<TRemoveWithSymbolInfo>>;
  lIndex: TDictionary<string, TArray<TRemoveWithSymbolInfo>>;
  lList: TList<TRemoveWithSymbolInfo>;
  lPair: TPair<string, TList<TRemoveWithSymbolInfo>>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if GTempPolicySymbolNameIndex <> nil then
    Exit;

  lBuckets := TDictionary<string, TList<TRemoveWithSymbolInfo>>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for lSymbol in aInventory.fSymbols do
    begin
      if lSymbol.fName = '' then
        Continue;
      if not lBuckets.TryGetValue(lSymbol.fName, lList) then
      begin
        lList := TList<TRemoveWithSymbolInfo>.Create;
        lBuckets.Add(lSymbol.fName, lList);
      end;
      lList.Add(lSymbol);
    end;

    lIndex := TDictionary<string, TArray<TRemoveWithSymbolInfo>>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
    try
      for lPair in lBuckets do
        lIndex.Add(lPair.Key, lPair.Value.ToArray);
      GTempPolicySymbolNameIndex := lIndex;
      lIndex := nil;
    finally
      lIndex.Free;
    end;
  finally
    for lPair in lBuckets do
      lPair.Value.Free;
    lBuckets.Free;
  end;
end;

procedure BeginRemoveWithTempPolicyCache(const aInventory: TRemoveWithSymbolInventory);
begin
  if GTempPolicyCacheDepth = 0 then
  begin
    GTempPolicySymbolNameIndex.Free;
    GTempPolicySymbolNameIndex := nil;
    EnsureTempPolicySymbolNameIndex(aInventory);
  end;
  Inc(GTempPolicyCacheDepth);
end;

procedure EndRemoveWithTempPolicyCache;
begin
  if GTempPolicyCacheDepth <= 0 then
    Exit;
  Dec(GTempPolicyCacheDepth);
  if GTempPolicyCacheDepth = 0 then
  begin
    GTempPolicySymbolNameIndex.Free;
    GTempPolicySymbolNameIndex := nil;
  end;
end;

function TypeCategoryForModelKind(const aKind: TRemoveWithModelTypeKind): TRemoveWithTypeCategory;
begin
  case aKind of
    TRemoveWithModelTypeKind.rwmtRecord:
      Result := TRemoveWithTypeCategory.rwtcRecord;
    TRemoveWithModelTypeKind.rwmtClass:
      Result := TRemoveWithTypeCategory.rwtcClass;
    TRemoveWithModelTypeKind.rwmtInterface:
      Result := TRemoveWithTypeCategory.rwtcInterface;
  else
    Result := TRemoveWithTypeCategory.rwtcUnknown;
  end;
end;

function RemoveWithTempStrategyToText(const aStrategy: TRemoveWithTempStrategy): string;
begin
  case aStrategy of
    TRemoveWithTempStrategy.rwtsDirectQualification:
      Result := 'direct-qualification';
    TRemoveWithTempStrategy.rwtsReferenceTemp:
      Result := 'reference-temp';
    TRemoveWithTempStrategy.rwtsRecordPointerTemp:
      Result := 'record-pointer-temp';
  else
    Result := 'skip';
  end;
end;

class function TRemoveWithTempPolicy.DirectTypeName(const aTypeName: string): string;
var
  lDelimiterPos: Integer;
begin
  Result := Trim(aTypeName);
  if StartsText('^', Result) then
    Delete(Result, 1, 1);
  lDelimiterPos := Pos('<', Result);
  if lDelimiterPos = 0 then
    lDelimiterPos := Pos('[', Result);
  if lDelimiterPos = 0 then
    lDelimiterPos := Pos(' ', Result);
  if lDelimiterPos > 0 then
    Result := Trim(Copy(Result, 1, lDelimiterPos - 1));
  lDelimiterPos := LastDelimiter('.', Result);
  if lDelimiterPos > 0 then
    Result := Copy(Result, lDelimiterPos + 1, MaxInt);
end;

class function TRemoveWithTempPolicy.CanonicalSourceTypeName(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): string;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeInfo: TRemoveWithModelTypeInfo;
  lTypeName: string;
begin
  lTypeName := Trim(aTypeName);
  if StartsText('^', lTypeName) then
    Delete(lTypeName, 1, 1);
  if lTypeName = '' then
    Exit('');

  if Assigned(aInventory.fSemanticIndex) and aInventory.fSemanticIndex.TryFindType(lTypeName, lTypeInfo) then
    Exit(lTypeName);

  EnsureTempPolicySymbolNameIndex(aInventory);
  if GTempPolicySymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
      begin
        if (lSymbol.fTypeCategory = TRemoveWithTypeCategory.rwtcUnknown) and (lSymbol.fTypeName <> '') and
          not MatchText(lSymbol.fTypeName, ['class', 'interface', 'record', 'object', 'enum']) and
          not SameText(lSymbol.fTypeName, lTypeName) then
          Exit(CanonicalSourceTypeName(aInventory, lSymbol.fTypeName));
        Exit(lTypeName);
      end;
    end;
  end;

  Result := DirectTypeName(lTypeName);
end;

class function TRemoveWithTempPolicy.IsIdentifierChar(const aValue: Char): Boolean;
begin
  Result := CharInSet(aValue, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

class function TRemoveWithTempPolicy.IsSimpleIdentifier(const aText: string): Boolean;
var
  lText: string;
  i: Integer;
begin
  lText := Trim(aText);
  if lText = '' then
    Exit(False);
  if not CharInSet(lText[1], ['A'..'Z', 'a'..'z', '_']) then
    Exit(False);
  for i := 2 to Length(lText) do
  begin
    if not IsIdentifierChar(lText[i]) then
      Exit(False);
  end;
  Result := True;
end;

class function TRemoveWithTempPolicy.IsPureUnitLevelSelector(const aText: string): Boolean;
var
  lBracketDepth: Integer;
  lPreviousWasDot: Boolean;
  lSawCode: Boolean;
  lText: string;
  i: Integer;
begin
  lText := Trim(aText);
  if lText = '' then
    Exit(False);

  lBracketDepth := 0;
  lPreviousWasDot := False;
  lSawCode := False;
  for i := 1 to Length(lText) do
  begin
    if CharInSet(lText[i], [#9, ' ']) then
      Continue;

    if lBracketDepth > 0 then
    begin
      if lText[i] = ']' then
      begin
        Dec(lBracketDepth);
        lPreviousWasDot := False;
        Continue;
      end;
      if not CharInSet(lText[i], ['0'..'9', ',']) then
        Exit(False);
      Continue;
    end;

    if lText[i] = '[' then
    begin
      if not lSawCode then
        Exit(False);
      Inc(lBracketDepth);
      lPreviousWasDot := False;
      Continue;
    end;

    if lText[i] = '.' then
    begin
      if (not lSawCode) or lPreviousWasDot then
        Exit(False);
      lPreviousWasDot := True;
      Continue;
    end;

    if not IsIdentifierChar(lText[i]) then
      Exit(False);
    lSawCode := True;
    lPreviousWasDot := False;
  end;

  Result := lSawCode and (lBracketDepth = 0) and not lPreviousWasDot;
end;

class function TRemoveWithTempPolicy.TypeCategory(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): TRemoveWithTypeCategory;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeInfo: TRemoveWithModelTypeInfo;
  lTypeName: string;
begin
  lTypeName := CanonicalSourceTypeName(aInventory, aTypeName);
  if Assigned(aInventory.fSemanticIndex) and aInventory.fSemanticIndex.TryFindType(lTypeName, lTypeInfo) then
    Exit(TypeCategoryForModelKind(lTypeInfo.fKind));

  EnsureTempPolicySymbolNameIndex(aInventory);
  if GTempPolicySymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
        Exit(lSymbol.fTypeCategory);
    end;
  end;
  Result := TRemoveWithTypeCategory.rwtcUnknown;
end;

class function TRemoveWithTempPolicy.SelectorUsesPointerDeref(const aSelectorText: string): Boolean;
var
  lBracketDepth: Integer;
  i: Integer;
begin
  lBracketDepth := 0;
  for i := 1 to Length(aSelectorText) do
  begin
    if aSelectorText[i] = '[' then
      Inc(lBracketDepth)
    else if (aSelectorText[i] = ']') and (lBracketDepth > 0) then
      Dec(lBracketDepth)
    else if (aSelectorText[i] = '^') and (lBracketDepth = 0) then
      Exit(True);
  end;
  Result := False;
end;

class function TRemoveWithTempPolicy.TempBaseName(const aTypeName: string): string;
var
  lTypeName: string;
begin
  lTypeName := DirectTypeName(aTypeName);
  if StartsText('T', lTypeName) and (Length(lTypeName) > 1) and CharInSet(lTypeName[2], ['A'..'Z']) then
    Delete(lTypeName, 1, 1);
  if lTypeName = '' then
    lTypeName := 'Receiver';
  Result := 'lWith' + lTypeName;
end;

class function TRemoveWithTempPolicy.ReservedNameExists(const aReservedNames: TRemoveWithReservedTempNames;
  const aName: string): Boolean;
var
  lName: string;
begin
  for lName in aReservedNames.fNames do
  begin
    if SameText(lName, aName) then
      Exit(True);
  end;
  Result := False;
end;

class function TRemoveWithTempPolicy.NameExists(const aInventory: TRemoveWithSymbolInventory;
  const aRoutineName, aName: string; const aReservedNames: TRemoveWithReservedTempNames): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
begin
  if ReservedNameExists(aReservedNames, aName) then
    Exit(True);
  EnsureTempPolicySymbolNameIndex(aInventory);
  if GTempPolicySymbolNameIndex.TryGetValue(aName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if (lSymbol.fRoutineName = '') or SameText(lSymbol.fRoutineName, aRoutineName) then
        Exit(True);
    end;
  end;
  Result := False;
end;

class function TRemoveWithTempPolicy.UniqueTempName(const aInventory: TRemoveWithSymbolInventory;
  const aRoutineName, aBaseName: string; const aReservedNames: TRemoveWithReservedTempNames): string;
var
  lIndex: Integer;
begin
  Result := aBaseName;
  lIndex := 1;
  while NameExists(aInventory, aRoutineName, Result, aReservedNames) do
  begin
    Result := aBaseName + IntToStr(lIndex);
    Inc(lIndex);
  end;
end;

class procedure TRemoveWithTempPolicy.ReserveName(var aReservedNames: TRemoveWithReservedTempNames;
  const aName: string);
var
  lLength: Integer;
begin
  if aName = '' then
    Exit;
  if ReservedNameExists(aReservedNames, aName) then
    Exit;
  lLength := Length(aReservedNames.fNames);
  SetLength(aReservedNames.fNames, lLength + 1);
  aReservedNames.fNames[lLength] := aName;
end;

class function TRemoveWithTempPolicy.ReserveUniqueTempName(const aInventory: TRemoveWithSymbolInventory;
  const aRoutineName, aBaseName: string; var aReservedNames: TRemoveWithReservedTempNames): string;
begin
  Result := UniqueTempName(aInventory, aRoutineName, aBaseName, aReservedNames);
  ReserveName(aReservedNames, Result);
end;

class procedure TRemoveWithTempPolicy.SetSkip(out aDecision: TRemoveWithTempDecision; const aSelectorText,
  aReason: string);
begin
  aDecision := Default(TRemoveWithTempDecision);
  aDecision.fSelectorText := aSelectorText;
  aDecision.fReason := aReason;
  aDecision.fStrategy := TRemoveWithTempStrategy.rwtsSkip;
end;

class function TRemoveWithTempPolicy.Plan(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
  aSelectorText: string; out aDecision: TRemoveWithTempDecision): Boolean;
var
  lReservedNames: TRemoveWithReservedTempNames;
begin
  lReservedNames := Default(TRemoveWithReservedTempNames);
  Result := Plan(aInventory, aRoutineName, aSelectorText, lReservedNames, aDecision);
end;

class function TRemoveWithTempPolicy.Plan(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
  aSelectorText: string; var aReservedNames: TRemoveWithReservedTempNames;
  out aDecision: TRemoveWithTempDecision): Boolean;
var
  lCategory: TRemoveWithTypeCategory;
  lInfo: TRemoveWithSelectorTypeInfo;
  lPointerTargetType: string;
  lTempBaseName: string;
  lTypeName: string;
begin
  aDecision := Default(TRemoveWithTempDecision);
  aDecision.fSelectorText := aSelectorText;
  Result := ResolveRemoveWithSelectorType(aInventory, aRoutineName, aSelectorText, lInfo);
  if not Result then
    Exit;

  if lInfo.fStatus <> TRemoveWithSelectorTypeStatus.rwstsResolved then
  begin
    SetSkip(aDecision, aSelectorText, lInfo.fReason);
    Exit(True);
  end;

  if SelectorUsesPointerDeref(aSelectorText) then
    lPointerTargetType := lInfo.fTypeName
  else
    lPointerTargetType := '';
  if lPointerTargetType <> '' then
  begin
    aDecision.fReceiverType := lPointerTargetType;
    aDecision.fQualifierText := aSelectorText;
    aDecision.fReason := 'already-pointer-qualified';
    aDecision.fStrategy := TRemoveWithTempStrategy.rwtsDirectQualification;
    Exit(True);
  end;

  lTypeName := CanonicalSourceTypeName(aInventory, lInfo.fTypeName);
  lCategory := TypeCategory(aInventory, lTypeName);
  aDecision.fReceiverType := lTypeName;
  lTempBaseName := TempBaseName(lTypeName);
  if lCategory = TRemoveWithTypeCategory.rwtcRecord then
  begin
    if (aRoutineName = '') and IsPureUnitLevelSelector(aSelectorText) then
    begin
      aDecision.fQualifierText := aSelectorText;
      aDecision.fReason := 'unit-level-pure-selector';
      aDecision.fStrategy := TRemoveWithTempStrategy.rwtsDirectQualification;
    end else if Pos('.', lTypeName) > 0 then
    begin
      aDecision.fQualifierText := aSelectorText;
      aDecision.fReason := 'anonymous-record-direct-qualification';
      aDecision.fStrategy := TRemoveWithTempStrategy.rwtsDirectQualification;
    end else
    begin
      aDecision.fTempName := ReserveUniqueTempName(aInventory, aRoutineName, lTempBaseName + 'Ptr',
        aReservedNames);
      aDecision.fDeclarationText := aDecision.fTempName + ': ^' + lTypeName + ';';
      aDecision.fInitializationText := aDecision.fTempName + ' := @' + aSelectorText + ';';
      aDecision.fQualifierText := aDecision.fTempName + '^';
      aDecision.fReason := 'record-pointer-preserves-alias';
      aDecision.fStrategy := TRemoveWithTempStrategy.rwtsRecordPointerTemp;
    end;
  end else if lCategory in [TRemoveWithTypeCategory.rwtcClass, TRemoveWithTypeCategory.rwtcInterface] then
  begin
    aDecision.fTempName := ReserveUniqueTempName(aInventory, aRoutineName, lTempBaseName, aReservedNames);
    aDecision.fDeclarationText := aDecision.fTempName + ': ' + lTypeName + ';';
    aDecision.fInitializationText := aDecision.fTempName + ' := ' + aSelectorText + ';';
    aDecision.fQualifierText := aDecision.fTempName;
    aDecision.fReason := 'reference-temp-preserves-evaluation';
    aDecision.fStrategy := TRemoveWithTempStrategy.rwtsReferenceTemp;
  end else if IsSimpleIdentifier(aSelectorText) then
  begin
    aDecision.fQualifierText := aSelectorText;
    aDecision.fReason := 'simple-selector';
    aDecision.fStrategy := TRemoveWithTempStrategy.rwtsDirectQualification;
  end else
    SetSkip(aDecision, aSelectorText, 'type-category-not-resolved');
end;

function PlanRemoveWithTempPolicy(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
  aSelectorText: string; out aDecision: TRemoveWithTempDecision): Boolean; overload;
begin
  BeginRemoveWithTempPolicyCache(aInventory);
  try
    Result := TRemoveWithTempPolicy.Plan(aInventory, aRoutineName, aSelectorText, aDecision);
  finally
    EndRemoveWithTempPolicyCache;
  end;
end;

function PlanRemoveWithTempPolicy(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
  aSelectorText: string; var aReservedNames: TRemoveWithReservedTempNames;
  out aDecision: TRemoveWithTempDecision): Boolean; overload;
begin
  BeginRemoveWithTempPolicyCache(aInventory);
  try
    Result := TRemoveWithTempPolicy.Plan(aInventory, aRoutineName, aSelectorText, aReservedNames, aDecision);
  finally
    EndRemoveWithTempPolicyCache;
  end;
end;

end.
