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
procedure BeginRemoveWithSelectorTypeCache(const aInventory: TRemoveWithFactSet);
procedure EndRemoveWithSelectorTypeCache;
function ResolveRemoveWithSelectorType(const aInventory: TRemoveWithFactSet; const aRoutineName,
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
    class function CanonicalSourceTypeName(const aInventory: TRemoveWithFactSet;
      const aTypeName: string): string; static;
    class function ArrayElementTypeName(const aInventory: TRemoveWithFactSet;
      const aTypeName: string): string; static;
    class function ElementTypeName(const aTypeName: string): string; static;
    class function FindDirectMember(const aInventory: TRemoveWithFactSet; const aOwnerType,
      aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindDefaultProperty(const aInventory: TRemoveWithFactSet; const aOwnerType: string;
      out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindLexicalParentRoutineName(const aInventory: TRemoveWithFactSet;
      const aRoutineName: string; out aParentRoutineName: string): Boolean; static;
    class function FindLexicalParentSymbol(const aInventory: TRemoveWithFactSet; const aRoutineName,
      aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function FindRoutineSymbol(const aInventory: TRemoveWithFactSet; const aRoutineName,
      aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean; static;
    class function HasSourceType(const aInventory: TRemoveWithFactSet; const aTypeName: string): Boolean;
      static;
    class function IsExternalType(const aInventory: TRemoveWithFactSet; const aTypeName: string): Boolean;
      static;
    class function UnsupportedSourceTypeReason(const aInventory: TRemoveWithFactSet;
      const aTypeName: string; out aReason: string): Boolean; static;
    class function ParseSegment(const aText: string; out aSegment: TSelectorSegment): Boolean; static;
    class function PointerTargetType(const aInventory: TRemoveWithFactSet; const aTypeName: string): string;
      static;
    class function SplitSelector(const aSelectorText: string): TArray<string>; static;
    class function TopLevelOpenParenPos(const aText: string): Integer; static;
    class procedure SetInfo(out aInfo: TRemoveWithSelectorTypeInfo; const aSelectorText, aTypeName,
      aReason: string; const aStatus: TRemoveWithSelectorTypeStatus; const aAddressable: Boolean); static;
    class function UnsupportedCallOrCast(const aInventory: TRemoveWithFactSet; const aSelectorText: string;
      out aReason: string): Boolean; static;
    class function UnsupportedSymbolKind(const aKind: TRemoveWithSymbolKind; out aReason: string): Boolean; static;
    class function PlaceholderRecordTypeName(const aTypeName: string): Boolean; static;
    class function TryResolveCastDerefSelector(const aInventory: TRemoveWithFactSet;
      const aSelectorText: string; out aInfo: TRemoveWithSelectorTypeInfo): Boolean; static;
  public
    class function Resolve(const aInventory: TRemoveWithFactSet; const aRoutineName, aSelectorText: string;
      out aInfo: TRemoveWithSelectorTypeInfo): Boolean; static;
  end;

var
  GExpressionCacheDepth: Integer;

procedure BeginRemoveWithSelectorTypeCache(const aInventory: TRemoveWithFactSet);
begin
  Inc(GExpressionCacheDepth);
end;

procedure EndRemoveWithSelectorTypeCache;
begin
  if GExpressionCacheDepth <= 0 then
    Exit;
  Dec(GExpressionCacheDepth);
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

class function TRemoveWithExpressionResolver.PlaceholderRecordTypeName(const aTypeName: string): Boolean;
begin
  Result := MatchText(Trim(aTypeName), ['PACKED', 'RECORD']);
end;

class function TRemoveWithExpressionResolver.CanonicalSourceTypeName(const aInventory: TRemoveWithFactSet;
  const aTypeName: string): string;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeName: string;
begin
  lTypeName := Trim(aTypeName);
  if StartsText('^', lTypeName) then
    Delete(lTypeName, 1, 1);
  if lTypeName = '' then
    Exit('');

  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lTypeName, lSymbols) then
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

class function TRemoveWithExpressionResolver.ArrayElementTypeName(const aInventory: TRemoveWithFactSet;
  const aTypeName: string): string;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeName: string;
begin
  Result := ElementTypeName(aTypeName);
  if Result <> '' then
    Exit;

  lTypeName := DirectTypeName(aTypeName);
  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
        Exit(ElementTypeName(lSymbol.fTypeName));
    end;
  end;
end;

class function TRemoveWithExpressionResolver.FindDirectMember(const aInventory: TRemoveWithFactSet;
  const aOwnerType, aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
var
  lFallbackSymbol: TRemoveWithSymbolInfo;
  lHasFallbackSymbol: Boolean;
  lRelatedTypeName: string;
  lSemanticMembers: TArray<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
begin
  aSymbol := Default(TRemoveWithSymbolInfo);
  lFallbackSymbol := Default(TRemoveWithSymbolInfo);
  lHasFallbackSymbol := False;
  if FindRemoveWithFactSetMembers(aInventory, aOwnerType, aName, lSemanticMembers) then
  begin
    for lSymbol in lSemanticMembers do
    begin
      if lSymbol.fKind in [TRemoveWithSymbolKind.rwskField, TRemoveWithSymbolKind.rwskProperty,
        TRemoveWithSymbolKind.rwskMethod, TRemoveWithSymbolKind.rwskConstant,
        TRemoveWithSymbolKind.rwskClassVar] then
      begin
        if not PlaceholderRecordTypeName(lSymbol.fTypeName) then
        begin
          aSymbol := lSymbol;
          Exit(True);
        end;
        if not lHasFallbackSymbol then
        begin
          lFallbackSymbol := lSymbol;
          lHasFallbackSymbol := True;
        end;
      end;
    end;
  end;
  if lHasFallbackSymbol then
  begin
    aSymbol := lFallbackSymbol;
    Exit(True);
  end;
  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, aOwnerType, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if (lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember) and
        (lSymbol.fRelatedTypeName <> '') then
      begin
        lRelatedTypeName := DirectTypeName(lSymbol.fRelatedTypeName);
        if (lRelatedTypeName <> '') and (not SameText(lRelatedTypeName, aOwnerType)) then
          Exit(FindDirectMember(aInventory, lRelatedTypeName, aName, aSymbol));
      end;
    end;
  end;
  Result := False;
end;

class function TRemoveWithExpressionResolver.FindDefaultProperty(const aInventory: TRemoveWithFactSet;
  const aOwnerType: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
begin
  aSymbol := Default(TRemoveWithSymbolInfo);
  Result := FindRemoveWithFactSetDefaultProperty(aInventory, aOwnerType, aSymbol);
end;

class function TRemoveWithExpressionResolver.FindLexicalParentRoutineName(
  const aInventory: TRemoveWithFactSet; const aRoutineName: string; out aParentRoutineName: string):
  Boolean;
var
  lCurrentRoutine: TRemoveWithSymbolInfo;
  lCurrentSymbols: TArray<TRemoveWithSymbolInfo>;
  lMatchedParentLine: Integer;
  lParentLine: Integer;
  lSymbol: TRemoveWithSymbolInfo;
begin
  Result := False;
  aParentRoutineName := '';
  if aRoutineName = '' then
    Exit;

  if not FindRemoveWithFactSetSymbolsByName(aInventory, aRoutineName, lCurrentSymbols) then
    Exit;

  lParentLine := 0;
  for lCurrentRoutine in lCurrentSymbols do
  begin
    if (lCurrentRoutine.fKind <> TRemoveWithSymbolKind.rwskRoutine) or (lCurrentRoutine.fEndLine <= lCurrentRoutine.fLine) then
      Continue;
    lMatchedParentLine := 0;
    for lSymbol in aInventory.fSymbols do
    begin
      if (lSymbol.fKind <> TRemoveWithSymbolKind.rwskRoutine) or SameText(lSymbol.fName, lCurrentRoutine.fName) then
        Continue;
      if (lSymbol.fEndLine <= lSymbol.fLine) or (lSymbol.fLine >= lCurrentRoutine.fLine) or
        (lSymbol.fEndLine < lCurrentRoutine.fEndLine) then
        Continue;
      if lSymbol.fLine > lMatchedParentLine then
      begin
        lMatchedParentLine := lSymbol.fLine;
        if (lMatchedParentLine > lParentLine) or (aParentRoutineName = '') then
        begin
          lParentLine := lMatchedParentLine;
          aParentRoutineName := lSymbol.fName;
        end;
      end;
    end;
  end;

  Result := aParentRoutineName <> '';
end;

class function TRemoveWithExpressionResolver.FindLexicalParentSymbol(
  const aInventory: TRemoveWithFactSet; const aRoutineName, aName: string;
  out aSymbol: TRemoveWithSymbolInfo): Boolean;
const
  cParentKinds: set of TRemoveWithSymbolKind = [TRemoveWithSymbolKind.rwskLocalVariable,
    TRemoveWithSymbolKind.rwskParameter];
var
  lBestCandidateLine: Integer;
  lBestParentLine: Integer;
  lCandidate: TRemoveWithSymbolInfo;
  lCurrentRoutine: TRemoveWithSymbolInfo;
  lCurrentSymbols: TArray<TRemoveWithSymbolInfo>;
  lNamedSymbols: TArray<TRemoveWithSymbolInfo>;
  lParentRoutine: TRemoveWithSymbolInfo;
  lParentSymbols: TArray<TRemoveWithSymbolInfo>;
begin
  Result := False;
  aSymbol := Default(TRemoveWithSymbolInfo);
  if (aRoutineName = '') or (aName = '') then
    Exit;

  if (not FindRemoveWithFactSetSymbolsByName(aInventory, aRoutineName, lCurrentSymbols)) or
    (not FindRemoveWithFactSetSymbolsByName(aInventory, aName, lNamedSymbols)) then
    Exit;

  lBestParentLine := 0;
  lBestCandidateLine := 0;
  for lCurrentRoutine in lCurrentSymbols do
  begin
    if (lCurrentRoutine.fKind <> TRemoveWithSymbolKind.rwskRoutine) or
      (lCurrentRoutine.fEndLine <= lCurrentRoutine.fLine) then
      Continue;
    for lCandidate in lNamedSymbols do
    begin
      if not (lCandidate.fKind in cParentKinds) or (lCandidate.fRoutineName = '') or
        (lCandidate.fLine >= lCurrentRoutine.fLine) then
        Continue;
      if (lCandidate.fFilePath <> '') and (lCurrentRoutine.fFilePath <> '') and
        (not SameText(lCandidate.fFilePath, lCurrentRoutine.fFilePath)) then
        Continue;
      if not FindRemoveWithFactSetSymbolsByName(aInventory, lCandidate.fRoutineName,
        lParentSymbols) then
        Continue;
      for lParentRoutine in lParentSymbols do
      begin
        if (lParentRoutine.fKind <> TRemoveWithSymbolKind.rwskRoutine) or
          (lParentRoutine.fEndLine <= lParentRoutine.fLine) then
          Continue;
        if (lParentRoutine.fFilePath <> '') and (lCurrentRoutine.fFilePath <> '') and
          (not SameText(lParentRoutine.fFilePath, lCurrentRoutine.fFilePath)) then
          Continue;
        if (lParentRoutine.fLine >= lCurrentRoutine.fLine) or
          (lParentRoutine.fEndLine < lCurrentRoutine.fEndLine) then
          Continue;
        if (lParentRoutine.fLine > lBestParentLine) or
          ((lParentRoutine.fLine = lBestParentLine) and (lCandidate.fLine > lBestCandidateLine)) then
        begin
          lBestParentLine := lParentRoutine.fLine;
          lBestCandidateLine := lCandidate.fLine;
          aSymbol := lCandidate;
          Result := True;
        end;
      end;
    end;
  end;
end;

class function TRemoveWithExpressionResolver.FindRoutineSymbol(const aInventory: TRemoveWithFactSet;
  const aRoutineName, aName: string; out aSymbol: TRemoveWithSymbolInfo): Boolean;
const
  cKinds: array [0..4] of TRemoveWithSymbolKind = (TRemoveWithSymbolKind.rwskLocalVariable,
    TRemoveWithSymbolKind.rwskParameter, TRemoveWithSymbolKind.rwskCurrentClassMember,
    TRemoveWithSymbolKind.rwskUnitGlobal, TRemoveWithSymbolKind.rwskConstant);
var
  lFallbackSymbol: TRemoveWithSymbolInfo;
  lHasFallbackSymbol: Boolean;
  lKind: TRemoveWithSymbolKind;
  lParentChecked: Boolean;
  lParentRoutineName: string;
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
begin
  aSymbol := Default(TRemoveWithSymbolInfo);
  lFallbackSymbol := Default(TRemoveWithSymbolInfo);
  lHasFallbackSymbol := False;
  if FindRemoveWithFactSetSymbolsByName(aInventory, aName, lSymbols) then
  begin
    lParentChecked := False;
    for lKind in cKinds do
    begin
      if (not lParentChecked) and (lKind = TRemoveWithSymbolKind.rwskUnitGlobal) then
      begin
        lParentChecked := True;
        if FindLexicalParentSymbol(aInventory, aRoutineName, aName, aSymbol) then
          Exit(True);
        if FindLexicalParentRoutineName(aInventory, aRoutineName, lParentRoutineName) and
          FindRoutineSymbol(aInventory, lParentRoutineName, aName, aSymbol) then
          Exit(True);
      end;

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
          if (lSymbol.fTypeName <> '') and PlaceholderRecordTypeName(lSymbol.fTypeName) then
          begin
            if not lHasFallbackSymbol then
            begin
              lFallbackSymbol := lSymbol;
              lHasFallbackSymbol := True;
            end;
            Continue;
          end;
          aSymbol := lSymbol;
          Exit(True);
        end;
      end;
    end;
  end;
  if lHasFallbackSymbol then
  begin
    aSymbol := lFallbackSymbol;
    Exit(True);
  end;
  if FindRemoveWithFactSetRoutineSymbol(aInventory, aRoutineName, aName, aSymbol) and
    (Trim(aSymbol.fTypeName) <> '') then
    Exit(True);
  Result := False;
end;

class function TRemoveWithExpressionResolver.HasSourceType(const aInventory: TRemoveWithFactSet;
  const aTypeName: string): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeName: string;
begin
  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, DirectTypeName(aTypeName),
    lSymbols) then
  begin
    for lSymbol in lSymbols do
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
        Exit(True);
  end;

  lTypeName := CanonicalSourceTypeName(aInventory, aTypeName);
  if (lTypeName = '') or BuiltInTypeName(lTypeName) then
    Exit(True);
  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lTypeName, lSymbols) then
  begin
    for lSymbol in lSymbols do
    begin
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
        Exit(True);
    end;
  end;
  Result := False;
end;

class function TRemoveWithExpressionResolver.IsExternalType(const aInventory: TRemoveWithFactSet;
  const aTypeName: string): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeName: string;
begin
  if FindRemoveWithFactSetSymbolsByName(aInventory, DirectTypeName(aTypeName), lSymbols) then
  begin
    for lSymbol in lSymbols do
      if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
        Exit(False);
  end;

  lTypeName := CanonicalSourceTypeName(aInventory, aTypeName);
  if FindRemoveWithFactSetSymbolsByName(aInventory, lTypeName, lSymbols) then
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
  const aInventory: TRemoveWithFactSet; const aTypeName: string; out aReason: string): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
  lSymbols: TArray<TRemoveWithSymbolInfo>;
  lTypeName: string;
begin
  aReason := '';
  lTypeName := CanonicalSourceTypeName(aInventory, aTypeName);
  if lTypeName = '' then
    Exit(False);

  if FindRemoveWithFactSetDeclarationOrTypeAlias(aInventory, lTypeName, lSymbols) then
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

class function TRemoveWithExpressionResolver.PointerTargetType(const aInventory: TRemoveWithFactSet;
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
  Result := RemoveWithFactSetPointerTargetType(aInventory, lTypeName);
  if Result <> '' then
    Exit;
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

class function TRemoveWithExpressionResolver.TopLevelOpenParenPos(const aText: string): Integer;
var
  lBracketDepth: Integer;
  i: Integer;
begin
  lBracketDepth := 0;
  for i := 1 to Length(aText) do
  begin
    if aText[i] = '[' then
      Inc(lBracketDepth)
    else if (aText[i] = ']') and (lBracketDepth > 0) then
      Dec(lBracketDepth)
    else if (aText[i] = '(') and (lBracketDepth = 0) then
      Exit(i);
  end;
  Result := 0;
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

class function TRemoveWithExpressionResolver.UnsupportedCallOrCast(const aInventory: TRemoveWithFactSet;
  const aSelectorText: string; out aReason: string): Boolean;
var
  lOpenPos: Integer;
  lPrefix: string;
begin
  aReason := '';
  lOpenPos := TopLevelOpenParenPos(aSelectorText);
  Result := lOpenPos > 0;
  if not Result then
    Exit;

  lPrefix := Trim(Copy(aSelectorText, 1, lOpenPos - 1));
  if HasSourceType(aInventory, lPrefix) then
    aReason := 'cast-selector'
  else
    aReason := 'call-selector';
end;

class function TRemoveWithExpressionResolver.TryResolveCastDerefSelector(
  const aInventory: TRemoveWithFactSet; const aSelectorText: string;
  out aInfo: TRemoveWithSelectorTypeInfo): Boolean;
var
  lOpenPos: Integer;
  lPointerTargetType: string;
  lPrefix: string;
  lText: string;
begin
  aInfo := Default(TRemoveWithSelectorTypeInfo);
  lText := Trim(aSelectorText);
  lOpenPos := TopLevelOpenParenPos(lText);
  Result := (lOpenPos > 1) and EndsText(')^', lText);
  if not Result then
    Exit;

  lPrefix := Trim(Copy(lText, 1, lOpenPos - 1));
  if not HasSourceType(aInventory, lPrefix) then
    Exit(False);

  lPointerTargetType := PointerTargetType(aInventory, lPrefix);
  if (lPointerTargetType = '') or (not HasSourceType(aInventory, lPointerTargetType)) then
    Exit(False);

  SetInfo(aInfo, aSelectorText, CanonicalSourceTypeName(aInventory, lPointerTargetType), '',
    TRemoveWithSelectorTypeStatus.rwstsResolved, True);
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

class function TRemoveWithExpressionResolver.Resolve(const aInventory: TRemoveWithFactSet; const aRoutineName,
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
  if TryResolveCastDerefSelector(aInventory, aSelectorText, aInfo) then
    Exit(True);

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
      if lSegment.fDeref and (not lSegment.fDerefBeforeIndex) then
        lTypeName := lSymbol.fTypeName
      else
      begin
        SetInfo(aInfo, aSelectorText, '', 'property-selector', TRemoveWithSelectorTypeStatus.rwstsUnsupported,
          False);
        Exit(True);
      end;
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
      SetInfo(aInfo, aSelectorText, CanonicalSourceTypeName(aInventory, lTypeName), 'type-source-not-indexed',
        TRemoveWithSelectorTypeStatus.rwstsExternal, False);
      Exit(True);
    end;
    if not FindDirectMember(aInventory, CanonicalSourceTypeName(aInventory, lTypeName), lSegment.fName, lSymbol) then
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
        if lSegment.fDeref and (not lSegment.fDerefBeforeIndex) then
          lTypeName := lSymbol.fTypeName
        else
        begin
          SetInfo(aInfo, aSelectorText, '', 'property-selector', TRemoveWithSelectorTypeStatus.rwstsUnsupported,
            False);
          Exit(True);
        end;
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
    SetInfo(aInfo, aSelectorText, CanonicalSourceTypeName(aInventory, lTypeName), 'type-source-not-indexed',
      TRemoveWithSelectorTypeStatus.rwstsExternal, False)
  else if not HasSourceType(aInventory, lTypeName) then
    SetInfo(aInfo, aSelectorText, CanonicalSourceTypeName(aInventory, lTypeName), 'type-not-found',
      TRemoveWithSelectorTypeStatus.rwstsUnresolved, False)
  else
    SetInfo(aInfo, aSelectorText, Trim(lTypeName), '',
      TRemoveWithSelectorTypeStatus.rwstsResolved, True);

  Result := True;
end;

function ResolveRemoveWithSelectorType(const aInventory: TRemoveWithFactSet; const aRoutineName,
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
