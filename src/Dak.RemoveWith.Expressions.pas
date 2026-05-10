unit Dak.RemoveWith.Expressions;

interface

uses
  Dak.RemoveWith.Symbols;

type
  TRemoveWithSelectorTypeStatus = (rwstsResolved, rwstsExternal, rwstsUnsupported, rwstsUnresolved);

  TRemoveWithSelectorTypeInfo = record
    fSelectorText: string;
    fTypeName: string;
    fReason: string;
    fAddressable: Boolean;
    fStatus: TRemoveWithSelectorTypeStatus;
  end;

function RemoveWithSelectorTypeStatusToText(const aStatus: TRemoveWithSelectorTypeStatus): string;
procedure BeginRemoveWithSelectorTypeCache(const aInventory: TRemoveWithSymbolInventory);
procedure EndRemoveWithSelectorTypeCache;
function ResolveRemoveWithSelectorType(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
  aSelectorText: string; out aInfo: TRemoveWithSelectorTypeInfo): Boolean;

implementation

uses
  System.Generics.Collections, System.StrUtils, System.SysUtils,
  MaxLogic.StrUtils,
  Dak.RemoveWith.Model;

type
  TSelectorSegment = record
    fName: string;
    fDeref: Boolean;
    fDerefBeforeIndex: Boolean;
    fIndexed: Boolean;
  end;

  TRemoveWithExpressionResolver = record
  private
    class function BuiltInTypeName(const aTypeName: string): Boolean; static;
    class function CurrentOwnerType(const aRoutineName: string): string; static;
    class function DirectTypeName(const aTypeName: string): string; static;
    class function ArrayElementTypeName(const aInventory: TRemoveWithSymbolInventory;
      const aTypeName: string): string; static;
    class function ElementTypeName(const aTypeName: string): string; static;
    class function FindDirectMember(const aInventory: TRemoveWithSymbolInventory; const aOwnerType,
      aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindDefaultProperty(const aInventory: TRemoveWithSymbolInventory; const aOwnerType: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindRoutineSymbol(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
      aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function HasSourceType(const aInventory: TRemoveWithSymbolInventory; const aTypeName: string): Boolean;
      static;
    class function IsExternalType(const aInventory: TRemoveWithSymbolInventory; const aTypeName: string): Boolean;
      static;
    class function UnsupportedSourceTypeReason(const aInventory: TRemoveWithSymbolInventory;
      const aTypeName: string; out aReason: string): Boolean; static;
    class function ParseSegment(const aText: string; out aSegment: TSelectorSegment): Boolean; static;
    class function PointerTargetType(const aInventory: TRemoveWithSymbolInventory; const aTypeName: string): string;
      static;
    class function SplitSelector(const aSelectorText: string): TArray<string>; static;
    class procedure SetInfo(out aInfo: TRemoveWithSelectorTypeInfo; const aSelectorText, aTypeName,
      aReason: string; const aStatus: TRemoveWithSelectorTypeStatus; const aAddressable: Boolean); static;
    class function UnsupportedCallOrCast(const aInventory: TRemoveWithSymbolInventory; const aSelectorText: string;
      out aReason: string): Boolean; static;
    class function UnsupportedSymbolKind(const aKind: TRemoveWithSymbolKind; out aReason: string): Boolean; static;
  public
    class function Resolve(const aInventory: TRemoveWithSymbolInventory; const aRoutineName, aSelectorText: string;
      out aInfo: TRemoveWithSelectorTypeInfo): Boolean; static;
  end;

var
  GExpressionCacheDepth: Integer;
  GExpressionDefaultPropertyByOwner: TDictionary<string, TRemoveWithSymbolInfo>;
  GExpressionSymbolNameIndex: TDictionary<string, TArray<TRemoveWithSymbolInfo>>;

procedure EnsureExpressionSymbolNameIndex(const aInventory: TRemoveWithSymbolInventory);
var
  lBuckets: TDictionary<string, TList<TRemoveWithSymbolInfo>>;
  lIndex: TDictionary<string, TArray<TRemoveWithSymbolInfo>>;
  lList: TList<TRemoveWithSymbolInfo>;
  lPair: TPair<string, TList<TRemoveWithSymbolInfo>>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if GExpressionSymbolNameIndex <> nil then
    Exit;

  GExpressionDefaultPropertyByOwner := TDictionary<string, TRemoveWithSymbolInfo>.Create(
    TFastCaseAwareComparer.OrdinalIgnoreCase);
  lBuckets := TDictionary<string, TList<TRemoveWithSymbolInfo>>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for lSymbol in aInventory.fSymbols do
    begin
      if lSymbol.fName = '' then
        Continue;
      if (lSymbol.fOwnerType <> '') and (lSymbol.fKind = TRemoveWithSymbolKind.rwskProperty) and
        lSymbol.fIsDefault then
        GExpressionDefaultPropertyByOwner.AddOrSetValue(lSymbol.fOwnerType, lSymbol);
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
      GExpressionSymbolNameIndex := lIndex;
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

procedure BeginRemoveWithSelectorTypeCache(const aInventory: TRemoveWithSymbolInventory);
begin
  if GExpressionCacheDepth = 0 then
  begin
    GExpressionDefaultPropertyByOwner.Free;
    GExpressionDefaultPropertyByOwner := nil;
    GExpressionSymbolNameIndex.Free;
    GExpressionSymbolNameIndex := nil;
    EnsureExpressionSymbolNameIndex(aInventory);
  end;
  Inc(GExpressionCacheDepth);
end;

procedure EndRemoveWithSelectorTypeCache;
begin
  if GExpressionCacheDepth <= 0 then
    Exit;
  Dec(GExpressionCacheDepth);
  if GExpressionCacheDepth = 0 then
  begin
    GExpressionSymbolNameIndex.Free;
    GExpressionSymbolNameIndex := nil;
    GExpressionDefaultPropertyByOwner.Free;
    GExpressionDefaultPropertyByOwner := nil;
  end;
end;

function ModelMemberKindToSymbolKind(const aKind: TRemoveWithModelMemberKind): TRemoveWithSymbolKind;
begin
  case aKind of
    TRemoveWithModelMemberKind.rwmmProperty:
      Result := TRemoveWithSymbolKind.rwskProperty;
    TRemoveWithModelMemberKind.rwmmMethod:
      Result := TRemoveWithSymbolKind.rwskMethod;
    TRemoveWithModelMemberKind.rwmmConstant:
      Result := TRemoveWithSymbolKind.rwskConstant;
    TRemoveWithModelMemberKind.rwmmClassVar:
      Result := TRemoveWithSymbolKind.rwskClassVar;
  else
    Result := TRemoveWithSymbolKind.rwskField;
  end;
end;

function ModelRoutineSymbolKindToSymbolKind(
  const aKind: TRemoveWithModelRoutineSymbolKind): TRemoveWithSymbolKind;
begin
  case aKind of
    TRemoveWithModelRoutineSymbolKind.rwmrsParameter:
      Result := TRemoveWithSymbolKind.rwskParameter;
  else
    Result := TRemoveWithSymbolKind.rwskLocalVariable;
  end;
end;

function SymbolFromModelMember(const aMember: TRemoveWithModelMemberInfo): TRemoveWithSymbolInfo;
begin
  Result := Default(TRemoveWithSymbolInfo);
  Result.fName := aMember.fName;
  Result.fTypeName := aMember.fTypeName;
  Result.fOwnerType := aMember.fOwnerType;
  Result.fIsDefault := aMember.fIsDefault;
  Result.fKind := ModelMemberKindToSymbolKind(aMember.fKind);
end;

function SymbolFromModelRoutineSymbol(
  const aSymbol: TRemoveWithModelRoutineSymbolInfo): TRemoveWithSymbolInfo;
begin
  Result := Default(TRemoveWithSymbolInfo);
  Result.fName := aSymbol.fName;
  Result.fTypeName := aSymbol.fTypeName;
  Result.fRoutineName := aSymbol.fRoutineName;
  Result.fKind := ModelRoutineSymbolKindToSymbolKind(aSymbol.fKind);
end;

function RemoveWithSelectorTypeStatusToText(const aStatus: TRemoveWithSelectorTypeStatus): string;
begin
  case aStatus of
    TRemoveWithSelectorTypeStatus.rwstsResolved:
      Result := 'resolved';
    TRemoveWithSelectorTypeStatus.rwstsExternal:
      Result := 'external';
    TRemoveWithSelectorTypeStatus.rwstsUnsupported:
      Result := 'unsupported';
  else
    Result := 'unresolved';
  end;
end;

class function TRemoveWithExpressionResolver.BuiltInTypeName(const aTypeName: string): Boolean;
begin
  Result := MatchText(aTypeName, ['AnsiString', 'Boolean', 'Byte', 'Cardinal', 'Char', 'Currency', 'Date',
    'DateTime', 'Double', 'Extended', 'Integer', 'Int64', 'NativeInt', 'NativeUInt', 'Pointer', 'Real', 'ShortInt',
    'Single', 'SmallInt', 'String', 'PByte', 'UInt64', 'Variant', 'WideChar', 'WideString', 'Word']);
end;

class function TRemoveWithExpressionResolver.CurrentOwnerType(const aRoutineName: string): string;
var
  lDotPos: Integer;
begin
  lDotPos := LastDelimiter('.', aRoutineName);
  if lDotPos > 0 then
    Result := Copy(aRoutineName, 1, lDotPos - 1)
  else
    Result := '';
end;

class function TRemoveWithExpressionResolver.DirectTypeName(const aTypeName: string): string;
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

class function TRemoveWithExpressionResolver.ElementTypeName(const aTypeName: string): string;
var
  lEndPos: Integer;
  lOfPos: Integer;
  lStartPos: Integer;
  lText: string;
begin
  Result := '';
  lText := Trim(aTypeName);
  if StartsText('array of ', LowerCase(lText)) then
    Exit(Trim(Copy(lText, Length('array of ') + 1, MaxInt)));
  if StartsText('array[', LowerCase(lText)) or StartsText('array [', LowerCase(lText)) then
  begin
    lEndPos := Pos(']', lText);
    if lEndPos > 0 then
    begin
      lOfPos := Pos(' of ', LowerCase(Copy(lText, lEndPos + 1, MaxInt)));
      if lOfPos > 0 then
        Exit(Trim(Copy(lText, lEndPos + lOfPos + Length(' of '), MaxInt)));
    end;
  end;

  if not StartsText('TArray<', lText) then
    Exit;
  lStartPos := Pos('<', lText);
  lEndPos := LastDelimiter('>', lText);
  if (lStartPos > 0) and (lEndPos > lStartPos) then
    Result := Trim(Copy(lText, lStartPos + 1, lEndPos - lStartPos - 1));
end;

class function TRemoveWithExpressionResolver.ArrayElementTypeName(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): string;
var
  lTypeInfo: TRemoveWithModelTypeInfo;
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeName: string;
begin
  Result := ElementTypeName(aTypeName);
  if Result <> '' then
    Exit;

  lTypeName := DirectTypeName(aTypeName);
  if Assigned(aInventory.fSemanticIndex) and aInventory.fSemanticIndex.TryResolveArrayElement(lTypeName,
    lTypeInfo) then
    Exit(lTypeInfo.fRelatedTypeName);

  EnsureExpressionSymbolNameIndex(aInventory);
  if GExpressionSymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
        Exit(ElementTypeName(lSymbol.fTypeName));
    end;
  end;
end;

class function TRemoveWithExpressionResolver.FindDirectMember(const aInventory: TRemoveWithSymbolInventory;
  const aOwnerType, aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lMember: TRemoveWithModelMemberInfo;
  lMembers: TArray<TRemoveWithModelMemberInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
begin
  aSymbol := Default(TRemoveWithSymbolInfo);
  EnsureExpressionSymbolNameIndex(aInventory);
  if GExpressionSymbolNameIndex.TryGetValue(aName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if SameText(lSymbol.fOwnerType, aOwnerType) and (lSymbol.fRoutineName = '') and
        (lSymbol.fKind in [TRemoveWithSymbolKind.rwskField, TRemoveWithSymbolKind.rwskProperty,
        TRemoveWithSymbolKind.rwskMethod, TRemoveWithSymbolKind.rwskConstant, TRemoveWithSymbolKind.rwskClassVar]) then
      begin
        aSymbol := lSymbol;
        Exit(True);
      end;
    end;
  end;
  if Assigned(aInventory.fSemanticIndex) and aInventory.fSemanticIndex.TryFindMembers(aOwnerType, aName,
    lMembers) then
  begin
    for lMember in lMembers do
    begin
      if ModelMemberKindToSymbolKind(lMember.fKind) in [TRemoveWithSymbolKind.rwskField,
        TRemoveWithSymbolKind.rwskProperty, TRemoveWithSymbolKind.rwskMethod,
        TRemoveWithSymbolKind.rwskConstant, TRemoveWithSymbolKind.rwskClassVar] then
      begin
        aSymbol := SymbolFromModelMember(lMember);
        if aSymbol.fTypeName <> '' then
          Exit(True);
      end;
    end;
  end;
  Result := False;
end;

class function TRemoveWithExpressionResolver.FindDefaultProperty(const aInventory: TRemoveWithSymbolInventory;
  const aOwnerType: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lMember: TRemoveWithModelMemberInfo;
begin
  aSymbol := Default(TRemoveWithSymbolInfo);
  EnsureExpressionSymbolNameIndex(aInventory);
  Result := GExpressionDefaultPropertyByOwner.TryGetValue(aOwnerType, aSymbol);
  if Result then
    Exit;
  if Assigned(aInventory.fSemanticIndex) and aInventory.fSemanticIndex.TryFindDefaultProperty(aOwnerType,
    lMember) then
  begin
    aSymbol := SymbolFromModelMember(lMember);
    Exit(True);
  end;
end;

class function TRemoveWithExpressionResolver.FindRoutineSymbol(const aInventory: TRemoveWithSymbolInventory;
  const aRoutineName, aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
const
  cKinds: array [0..4] of TRemoveWithSymbolKind = (TRemoveWithSymbolKind.rwskLocalVariable,
    TRemoveWithSymbolKind.rwskParameter, TRemoveWithSymbolKind.rwskCurrentClassMember,
    TRemoveWithSymbolKind.rwskUnitGlobal, TRemoveWithSymbolKind.rwskConstant);
var
  lKind: TRemoveWithSymbolKind;
  lModelSymbol: TRemoveWithModelRoutineSymbolInfo;
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
begin
  aSymbol := Default(TRemoveWithSymbolInfo);
  EnsureExpressionSymbolNameIndex(aInventory);
  if GExpressionSymbolNameIndex.TryGetValue(aName, lSymbols) then
  begin
    for lKind in cKinds do
    begin
      for lSymbol in lSymbols do
      begin
        if lSymbol.fKind <> lKind then
          Continue;
        if lKind in [TRemoveWithSymbolKind.rwskLocalVariable, TRemoveWithSymbolKind.rwskParameter,
          TRemoveWithSymbolKind.rwskCurrentClassMember] then
        begin
          if not SameText(lSymbol.fRoutineName, aRoutineName) then
            Continue;
          if Trim(lSymbol.fTypeName) = '' then
            Continue;
        end else if (lSymbol.fRoutineName <> '') and (not SameText(lSymbol.fRoutineName, aRoutineName)) then
          Continue;

        if lSymbol.fKind = lKind then
        begin
          aSymbol := lSymbol;
          Exit(True);
        end;
      end;
    end;
  end;
  if Assigned(aInventory.fSemanticIndex) and aInventory.fSemanticIndex.TryFindRoutineSymbol(aRoutineName,
    aName, lModelSymbol) then
  begin
    aSymbol := SymbolFromModelRoutineSymbol(lModelSymbol);
    if aSymbol.fTypeName <> '' then
      Exit(True);
  end;
  Result := False;
end;

class function TRemoveWithExpressionResolver.HasSourceType(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeInfo: TRemoveWithModelTypeInfo;
  lTypeName: string;
begin
  lTypeName := DirectTypeName(aTypeName);
  if (lTypeName = '') or BuiltInTypeName(lTypeName) then
    Exit(True);
  if Assigned(aInventory.fSemanticIndex) and aInventory.fSemanticIndex.TryFindType(lTypeName, lTypeInfo) then
    Exit(True);

  EnsureExpressionSymbolNameIndex(aInventory);
  if GExpressionSymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
        Exit(True);
    end;
  end;
  Result := False;
end;

class function TRemoveWithExpressionResolver.IsExternalType(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeInfo: TRemoveWithModelTypeInfo;
  lTypeName: string;
begin
  lTypeName := DirectTypeName(aTypeName);
  EnsureExpressionSymbolNameIndex(aInventory);
  if GExpressionSymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskExternal then
        Exit(True);
    end;
  end;
  Result := False;
end;

class function TRemoveWithExpressionResolver.UnsupportedSourceTypeReason(
  const aInventory: TRemoveWithSymbolInventory; const aTypeName: string; out aReason: string): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeInfo: TRemoveWithModelTypeInfo;
  lTypeName: string;
begin
  aReason := '';
  lTypeName := DirectTypeName(aTypeName);
  if lTypeName = '' then
    Exit(False);

  EnsureExpressionSymbolNameIndex(aInventory);
  if GExpressionSymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and (lSymbol.fUnsupportedReason <> '') then
      begin
        aReason := lSymbol.fUnsupportedReason;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

class function TRemoveWithExpressionResolver.ParseSegment(const aText: string; out aSegment: TSelectorSegment): Boolean;
var
  lBracketPos: Integer;
  lCaretPos: Integer;
  lNameEnd: Integer;
  lText: string;
begin
  aSegment := Default(TSelectorSegment);
  lText := Trim(aText);
  if lText = '' then
    Exit(False);

  lCaretPos := Pos('^', lText);
  lBracketPos := Pos('[', lText);
  lNameEnd := 1;
  while (lNameEnd <= Length(lText)) and
    (CharInSet(lText[lNameEnd], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) do
    Inc(lNameEnd);

  aSegment.fName := Copy(lText, 1, lNameEnd - 1);
  aSegment.fDeref := lCaretPos > 0;
  aSegment.fDerefBeforeIndex := aSegment.fDeref and ((lBracketPos = 0) or (lCaretPos < lBracketPos));
  aSegment.fIndexed := lBracketPos > 0;
  Result := aSegment.fName <> '';
end;

class function TRemoveWithExpressionResolver.PointerTargetType(const aInventory: TRemoveWithSymbolInventory;
  const aTypeName: string): string;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeInfo: TRemoveWithModelTypeInfo;
  lTypeName: string;
begin
  lTypeName := Trim(aTypeName);
  if StartsText('^', lTypeName) then
    Exit(Trim(Copy(lTypeName, 2, MaxInt)));

  lTypeName := DirectTypeName(lTypeName);
  if Assigned(aInventory.fSemanticIndex) and aInventory.fSemanticIndex.TryResolvePointerTarget(lTypeName,
    lTypeInfo) then
    Exit(lTypeInfo.fRelatedTypeName);

  EnsureExpressionSymbolNameIndex(aInventory);
  if GExpressionSymbolNameIndex.TryGetValue(lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and StartsText('^', Trim(lSymbol.fTypeName)) then
        Exit(Trim(Copy(Trim(lSymbol.fTypeName), 2, MaxInt)));
    end;
  end;
  Result := '';
end;

class function TRemoveWithExpressionResolver.SplitSelector(const aSelectorText: string): TArray<string>;
var
  lBracketDepth: Integer;
  lList: TList<string>;
  lStart: Integer;
  i: Integer;
begin
  lList := TList<string>.Create;
  try
    lBracketDepth := 0;
    lStart := 1;
    for i := 1 to Length(aSelectorText) do
    begin
      if aSelectorText[i] = '[' then
        Inc(lBracketDepth)
      else if (aSelectorText[i] = ']') and (lBracketDepth > 0) then
        Dec(lBracketDepth)
      else if (aSelectorText[i] = '.') and (lBracketDepth = 0) then
      begin
        lList.Add(Copy(aSelectorText, lStart, i - lStart));
        lStart := i + 1;
      end;
    end;
    lList.Add(Copy(aSelectorText, lStart, MaxInt));
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

class procedure TRemoveWithExpressionResolver.SetInfo(out aInfo: TRemoveWithSelectorTypeInfo;
  const aSelectorText, aTypeName, aReason: string; const aStatus: TRemoveWithSelectorTypeStatus;
  const aAddressable: Boolean);
begin
  aInfo := Default(TRemoveWithSelectorTypeInfo);
  aInfo.fSelectorText := aSelectorText;
  aInfo.fTypeName := aTypeName;
  aInfo.fReason := aReason;
  aInfo.fStatus := aStatus;
  aInfo.fAddressable := aAddressable;
end;

class function TRemoveWithExpressionResolver.UnsupportedCallOrCast(const aInventory: TRemoveWithSymbolInventory;
  const aSelectorText: string; out aReason: string): Boolean;
var
  lOpenPos: Integer;
  lPrefix: string;
begin
  aReason := '';
  lOpenPos := Pos('(', aSelectorText);
  Result := lOpenPos > 0;
  if not Result then
    Exit;

  lPrefix := Trim(Copy(aSelectorText, 1, lOpenPos - 1));
  if HasSourceType(aInventory, lPrefix) then
    aReason := 'cast-selector'
  else
    aReason := 'call-selector';
end;

class function TRemoveWithExpressionResolver.UnsupportedSymbolKind(const aKind: TRemoveWithSymbolKind;
  out aReason: string): Boolean;
begin
  Result := True;
  case aKind of
    TRemoveWithSymbolKind.rwskProperty:
      aReason := 'property-selector';
    TRemoveWithSymbolKind.rwskMethod:
      aReason := 'call-selector';
  else
    Result := False;
    aReason := '';
  end;
end;

class function TRemoveWithExpressionResolver.Resolve(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
  aSelectorText: string; out aInfo: TRemoveWithSelectorTypeInfo): Boolean;
var
  lReason: string;
  lSegment: TSelectorSegment;
  lSegments: TArray<string>;
  lDirectSymbol: TRemoveWithSymbolInfo;
  lIndexedTypeName: string;
  lSymbol: TRemoveWithSymbolInfo;
  lOwnerType: string;
  lTypeName: string;
  i: Integer;
begin
  if UnsupportedCallOrCast(aInventory, aSelectorText, lReason) then
  begin
    SetInfo(aInfo, aSelectorText, '', lReason, TRemoveWithSelectorTypeStatus.rwstsUnsupported, False);
    Exit(True);
  end;

  lSegments := SplitSelector(aSelectorText);
  if Length(lSegments) = 0 then
  begin
    SetInfo(aInfo, aSelectorText, '', 'empty-selector', TRemoveWithSelectorTypeStatus.rwstsUnresolved, False);
    Exit(True);
  end;

  if not ParseSegment(lSegments[0], lSegment) then
  begin
    SetInfo(aInfo, aSelectorText, '', 'invalid-selector', TRemoveWithSelectorTypeStatus.rwstsUnresolved, False);
    Exit(True);
  end;

  if SameText(lSegment.fName, 'Self') then
    lTypeName := CurrentOwnerType(aRoutineName)
  else
  begin
    if not FindRoutineSymbol(aInventory, aRoutineName, lSegment.fName, lSymbol) then
    begin
      lOwnerType := CurrentOwnerType(aRoutineName);
      if not FindDirectMember(aInventory, lOwnerType, lSegment.fName, lSymbol) then
      begin
        SetInfo(aInfo, aSelectorText, '', 'symbol-not-found', TRemoveWithSelectorTypeStatus.rwstsUnresolved, False);
        Exit(True);
      end;
    end;
    if lSymbol.fKind = TRemoveWithSymbolKind.rwskCurrentClassMember then
    begin
      if FindDirectMember(aInventory, lSymbol.fOwnerType, lSymbol.fName, lDirectSymbol) then
        lSymbol := lDirectSymbol;
    end;
    if UnsupportedSymbolKind(lSymbol.fKind, lReason) then
    begin
      SetInfo(aInfo, aSelectorText, '', lReason, TRemoveWithSelectorTypeStatus.rwstsUnsupported, False);
      Exit(True);
    end;
    lTypeName := lSymbol.fTypeName;
  end;

  if lSegment.fDeref and lSegment.fDerefBeforeIndex then
    lTypeName := PointerTargetType(aInventory, lTypeName);
  if lSegment.fIndexed then
  begin
    lIndexedTypeName := ArrayElementTypeName(aInventory, lTypeName);
    if lIndexedTypeName <> '' then
      lTypeName := lIndexedTypeName
    else if FindDefaultProperty(aInventory, DirectTypeName(lTypeName), lSymbol) then
    begin
      SetInfo(aInfo, aSelectorText, '', 'property-selector', TRemoveWithSelectorTypeStatus.rwstsUnsupported, False);
      Exit(True);
    end else
      lTypeName := '';
  end;
  if lSegment.fDeref and (not lSegment.fDerefBeforeIndex) then
    lTypeName := PointerTargetType(aInventory, lTypeName);
  if UnsupportedSourceTypeReason(aInventory, lTypeName, lReason) then
  begin
    SetInfo(aInfo, aSelectorText, DirectTypeName(lTypeName), lReason,
      TRemoveWithSelectorTypeStatus.rwstsUnsupported, False);
    Exit(True);
  end;

  for i := 1 to High(lSegments) do
  begin
    if not ParseSegment(lSegments[i], lSegment) then
    begin
      SetInfo(aInfo, aSelectorText, '', 'invalid-selector', TRemoveWithSelectorTypeStatus.rwstsUnresolved, False);
      Exit(True);
    end;
    if UnsupportedSourceTypeReason(aInventory, lTypeName, lReason) then
    begin
      SetInfo(aInfo, aSelectorText, DirectTypeName(lTypeName), lReason,
        TRemoveWithSelectorTypeStatus.rwstsUnsupported, False);
      Exit(True);
    end;
    if (not HasSourceType(aInventory, lTypeName)) and IsExternalType(aInventory, lTypeName) then
    begin
      SetInfo(aInfo, aSelectorText, DirectTypeName(lTypeName), 'type-source-not-indexed',
        TRemoveWithSelectorTypeStatus.rwstsExternal, False);
      Exit(True);
    end;
    if not FindDirectMember(aInventory, DirectTypeName(lTypeName), lSegment.fName, lSymbol) then
    begin
      SetInfo(aInfo, aSelectorText, '', 'member-not-found', TRemoveWithSelectorTypeStatus.rwstsUnresolved, False);
      Exit(True);
    end;
    if UnsupportedSymbolKind(lSymbol.fKind, lReason) then
    begin
      SetInfo(aInfo, aSelectorText, '', lReason, TRemoveWithSelectorTypeStatus.rwstsUnsupported, False);
      Exit(True);
    end;
    lTypeName := lSymbol.fTypeName;
    if lSegment.fDeref and lSegment.fDerefBeforeIndex then
      lTypeName := PointerTargetType(aInventory, lTypeName);
    if lSegment.fIndexed then
    begin
      lIndexedTypeName := ArrayElementTypeName(aInventory, lTypeName);
      if lIndexedTypeName <> '' then
        lTypeName := lIndexedTypeName
      else if FindDefaultProperty(aInventory, DirectTypeName(lTypeName), lSymbol) then
      begin
        SetInfo(aInfo, aSelectorText, '', 'property-selector', TRemoveWithSelectorTypeStatus.rwstsUnsupported,
          False);
        Exit(True);
      end else
        lTypeName := '';
    end;
    if lSegment.fDeref and (not lSegment.fDerefBeforeIndex) then
      lTypeName := PointerTargetType(aInventory, lTypeName);
    if UnsupportedSourceTypeReason(aInventory, lTypeName, lReason) then
    begin
      SetInfo(aInfo, aSelectorText, DirectTypeName(lTypeName), lReason,
        TRemoveWithSelectorTypeStatus.rwstsUnsupported, False);
      Exit(True);
    end;
  end;

  if (lTypeName = '') then
    SetInfo(aInfo, aSelectorText, '', 'type-not-resolved', TRemoveWithSelectorTypeStatus.rwstsUnresolved, False)
  else if (not HasSourceType(aInventory, lTypeName)) and IsExternalType(aInventory, lTypeName) then
    SetInfo(aInfo, aSelectorText, DirectTypeName(lTypeName), 'type-source-not-indexed',
      TRemoveWithSelectorTypeStatus.rwstsExternal, False)
  else if not HasSourceType(aInventory, lTypeName) then
    SetInfo(aInfo, aSelectorText, DirectTypeName(lTypeName), 'type-not-found',
      TRemoveWithSelectorTypeStatus.rwstsUnresolved, False)
  else
    SetInfo(aInfo, aSelectorText, DirectTypeName(lTypeName), '', TRemoveWithSelectorTypeStatus.rwstsResolved, True);

  Result := True;
end;

function ResolveRemoveWithSelectorType(const aInventory: TRemoveWithSymbolInventory; const aRoutineName,
  aSelectorText: string; out aInfo: TRemoveWithSelectorTypeInfo): Boolean;
begin
  BeginRemoveWithSelectorTypeCache(aInventory);
  try
    Result := TRemoveWithExpressionResolver.Resolve(aInventory, aRoutineName, aSelectorText, aInfo);
  finally
    EndRemoveWithSelectorTypeCache;
  end;
end;

end.
