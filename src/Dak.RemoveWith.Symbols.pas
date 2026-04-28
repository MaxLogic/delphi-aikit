unit Dak.RemoveWith.Symbols;

interface

uses
  Dak.Types;

type
  TRemoveWithSymbolKind = (rwskLocalVariable, rwskParameter, rwskCurrentClassMember, rwskUnitGlobal,
    rwskTypeMember, rwskField, rwskProperty, rwskMethod, rwskConstant, rwskClassVar, rwskRoutine, rwskUnitName,
    rwskExternal);

  TRemoveWithSymbolInfo = record
    fName: string;
    fTypeName: string;
    fOwnerType: string;
    fSourceOwnerType: string;
    fRelatedTypeName: string;
    fRoutineName: string;
    fUnitName: string;
    fFilePath: string;
    fLine: Integer;
    fColumn: Integer;
    fIsHelper: Boolean;
    fIsOverride: Boolean;
    fKind: TRemoveWithSymbolKind;
  end;

  TRemoveWithSymbolInventory = record
    fSymbols: TArray<TRemoveWithSymbolInfo>;
  end;

function RemoveWithSymbolKindToText(const aKind: TRemoveWithSymbolKind): string;
function BuildRemoveWithSymbolInventory(const aOptions: TAppOptions; out aInventory: TRemoveWithSymbolInventory;
  out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  DelphiAST.ProjectIndexer,
  Dak.Project;

type
  TRemoveWithSymbolBuilder = record
  private
    class function CleanLine(const aLine: string): string; static;
    class function IsIdentifierChar(const aValue: Char): Boolean; static;
    class function IsTopLevelLine(const aLine: string): Boolean; static;
    class function IsVisibilityLine(const aLine: string): Boolean; static;
    class function IsRoutineStart(const aLine: string): Boolean; static;
    class function TryDeclaration(const aLine: string; out aNames: TArray<string>; out aTypeName: string): Boolean;
      static;
    class function TryConstDeclaration(const aLine: string; out aName: string; out aTypeName: string): Boolean; static;
    class function TryTypeAlias(const aLine: string; out aName: string; out aTypeName: string): Boolean; static;
    class function TryTypeStart(const aLine: string; out aName: string): Boolean; static;
    class function TryTypeRelation(const aLine: string; out aRelatedTypeName: string; out aIsHelper: Boolean): Boolean;
      static;
    class function TryRoutineName(const aLine: string; out aName: string): Boolean; static;
    class function TryRoutineOwner(const aRoutineName: string; out aOwnerType: string): Boolean; static;
    class function CollectDeclarationText(const aLines: TArray<string>; const aStartLine: Integer): string; static;
    class function CollectTypeStartText(const aLines: TArray<string>; const aStartLine: Integer): string; static;
    class function FindColumn(const aLine, aName: string): Integer; static;
    class function IsDirectMemberKind(const aKind: TRemoveWithSymbolKind): Boolean; static;
    class function IsBuiltInTypeName(const aTypeName: string): Boolean; static;
    class function OwnerHasOwnMember(const aInventory: TRemoveWithSymbolInventory; const aOwnerType,
      aName: string): Boolean; static;
    class function SimpleTypeName(const aTypeName: string): string; static;
    class function FindNameSource(const aLines: TArray<string>; const aStartIndex, aEndIndex: Integer;
      const aName: string; out aLineNumber: Integer; out aLineText: string): Boolean; static;
    class procedure AddSymbol(var aInventory: TRemoveWithSymbolInventory; const aSymbol: TRemoveWithSymbolInfo);
      static;
    class procedure AddNamedSymbols(var aInventory: TRemoveWithSymbolInventory; const aNames: TArray<string>;
      const aTypeName, aOwnerType, aRoutineName, aUnitName, aFilePath: string; const aLineNumber: Integer;
      const aLineText: string; const aKind: TRemoveWithSymbolKind); static;
    class procedure AddNamedSymbolsFromSource(var aInventory: TRemoveWithSymbolInventory;
      const aNames: TArray<string>; const aTypeName, aOwnerType, aRoutineName, aUnitName, aFilePath: string;
      const aLines: TArray<string>; const aStartIndex, aEndIndex: Integer; const aKind: TRemoveWithSymbolKind);
      static;
    class procedure AddRelatedTypeMemberSymbols(var aInventory: TRemoveWithSymbolInventory); static;
    class procedure AddRelatedCurrentClassSymbols(var aInventory: TRemoveWithSymbolInventory); static;
    class procedure ParseParams(var aInventory: TRemoveWithSymbolInventory; const aLines: TArray<string>;
      const aStartIndex: Integer; const aSignature, aRoutineName, aUnitName, aFilePath: string); static;
    class procedure ParseLocals(var aInventory: TRemoveWithSymbolInventory; const aLines: TArray<string>;
      const aStartLine: Integer; const aRoutineName, aUnitName, aFilePath: string); static;
    class procedure ParseTypeMembers(var aInventory: TRemoveWithSymbolInventory; const aLines: TArray<string>;
      const aUnitName, aFilePath: string); static;
    class procedure ParseUnitGlobals(var aInventory: TRemoveWithSymbolInventory; const aLines: TArray<string>;
      const aUnitName, aFilePath: string); static;
    class procedure ParseRoutines(var aInventory: TRemoveWithSymbolInventory; const aLines: TArray<string>;
      const aUnitName, aFilePath: string); static;
    class procedure ParseUnit(var aInventory: TRemoveWithSymbolInventory; const aUnitName, aFilePath: string);
      static;
    class procedure AddExternalUnitSymbols(var aInventory: TRemoveWithSymbolInventory); static;
    class procedure AddExternalTypeSymbols(var aInventory: TRemoveWithSymbolInventory); static;
  end;

function RemoveWithSymbolKindToText(const aKind: TRemoveWithSymbolKind): string;
begin
  case aKind of
    TRemoveWithSymbolKind.rwskLocalVariable:
      Result := 'local-variable';
    TRemoveWithSymbolKind.rwskParameter:
      Result := 'parameter';
    TRemoveWithSymbolKind.rwskCurrentClassMember:
      Result := 'current-class-member';
    TRemoveWithSymbolKind.rwskUnitGlobal:
      Result := 'unit-global';
    TRemoveWithSymbolKind.rwskTypeMember:
      Result := 'type-member';
    TRemoveWithSymbolKind.rwskField:
      Result := 'field';
    TRemoveWithSymbolKind.rwskProperty:
      Result := 'property';
    TRemoveWithSymbolKind.rwskMethod:
      Result := 'method';
    TRemoveWithSymbolKind.rwskConstant:
      Result := 'constant';
    TRemoveWithSymbolKind.rwskClassVar:
      Result := 'class-var';
    TRemoveWithSymbolKind.rwskRoutine:
      Result := 'routine';
    TRemoveWithSymbolKind.rwskUnitName:
      Result := 'unit';
  else
    Result := 'external';
  end;
end;

class function TRemoveWithSymbolBuilder.CleanLine(const aLine: string): string;
var
  lCommentPos: Integer;
begin
  Result := Trim(aLine);
  lCommentPos := Pos('//', Result);
  if lCommentPos > 0 then
    Result := Trim(Copy(Result, 1, lCommentPos - 1));
end;

class function TRemoveWithSymbolBuilder.IsIdentifierChar(const aValue: Char): Boolean;
begin
  Result := CharInSet(aValue, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

class function TRemoveWithSymbolBuilder.IsTopLevelLine(const aLine: string): Boolean;
begin
  Result := (Trim(aLine) <> '') and (TrimLeft(aLine) = aLine);
end;

class function TRemoveWithSymbolBuilder.IsVisibilityLine(const aLine: string): Boolean;
begin
  Result := MatchText(LowerCase(Trim(aLine)), ['private', 'protected', 'public', 'published',
    'strict private', 'strict protected']);
end;

class function TRemoveWithSymbolBuilder.IsRoutineStart(const aLine: string): Boolean;
var
  lText: string;
begin
  lText := LowerCase(Trim(aLine));
  Result := StartsText('procedure ', lText) or StartsText('function ', lText) or
    StartsText('class procedure ', lText) or StartsText('class function ', lText) or
    StartsText('constructor ', lText) or StartsText('destructor ', lText);
end;

class function TRemoveWithSymbolBuilder.TryDeclaration(const aLine: string; out aNames: TArray<string>;
  out aTypeName: string): Boolean;
var
  lColonPos: Integer;
  lEqualsPos: Integer;
  lLeft: string;
  lPart: string;
  lParts: TArray<string>;
  lRawPart: string;
  lRight: string;
  lSemiPos: Integer;
  lNames: TList<string>;
begin
  Result := False;
  SetLength(aNames, 0);
  aTypeName := '';
  lColonPos := Pos(':', aLine);
  if lColonPos = 0 then
    Exit;

  lLeft := Trim(Copy(aLine, 1, lColonPos - 1));
  if (lLeft = '') or IsRoutineStart(lLeft) or StartsText('property ', LowerCase(lLeft)) then
    Exit;

  lRight := Trim(Copy(aLine, lColonPos + 1, MaxInt));
  lEqualsPos := Pos('=', lRight);
  if lEqualsPos > 0 then
    lRight := Trim(Copy(lRight, 1, lEqualsPos - 1));
  lSemiPos := Pos(';', lRight);
  if lSemiPos > 0 then
    lRight := Trim(Copy(lRight, 1, lSemiPos - 1));
  if lRight = '' then
    Exit;

  lNames := TList<string>.Create;
  try
    lParts := lLeft.Split([',']);
    for lRawPart in lParts do
    begin
      lPart := Trim(lRawPart);
      if lPart <> '' then
        lNames.Add(lPart);
    end;
    aNames := lNames.ToArray;
  finally
    lNames.Free;
  end;
  aTypeName := lRight;
  Result := Length(aNames) > 0;
end;

class function TRemoveWithSymbolBuilder.TryConstDeclaration(const aLine: string; out aName: string;
  out aTypeName: string): Boolean;
var
  lColonPos: Integer;
  lEqualsPos: Integer;
begin
  Result := False;
  aName := '';
  aTypeName := '';
  lEqualsPos := Pos('=', aLine);
  if lEqualsPos = 0 then
    Exit;

  lColonPos := Pos(':', aLine);
  if (lColonPos > 0) and (lColonPos < lEqualsPos) then
  begin
    aName := Trim(Copy(aLine, 1, lColonPos - 1));
    aTypeName := Trim(Copy(aLine, lColonPos + 1, lEqualsPos - lColonPos - 1));
  end else
  begin
    aName := Trim(Copy(aLine, 1, lEqualsPos - 1));
    aTypeName := '';
  end;
  Result := aName <> '';
end;

class function TRemoveWithSymbolBuilder.TryTypeAlias(const aLine: string; out aName: string;
  out aTypeName: string): Boolean;
var
  lEqualsPos: Integer;
  lRight: string;
  lSemiPos: Integer;
begin
  Result := False;
  aName := '';
  aTypeName := '';
  lEqualsPos := Pos('=', aLine);
  if lEqualsPos = 0 then
    Exit;

  aName := Trim(Copy(aLine, 1, lEqualsPos - 1));
  lRight := Trim(Copy(aLine, lEqualsPos + 1, MaxInt));
  lSemiPos := Pos(';', lRight);
  if lSemiPos > 0 then
    lRight := Trim(Copy(lRight, 1, lSemiPos - 1));

  aTypeName := lRight;
  Result := (aName <> '') and (aTypeName <> '');
end;

class function TRemoveWithSymbolBuilder.TryTypeStart(const aLine: string; out aName: string): Boolean;
var
  lEqualsPos: Integer;
  lLower: string;
begin
  Result := False;
  aName := '';
  lEqualsPos := Pos('=', aLine);
  if lEqualsPos = 0 then
    Exit;

  lLower := LowerCase(aLine);
  if (Pos(' record', lLower) = 0) and (Pos(' class', lLower) = 0) and (Pos(' interface', lLower) = 0) then
    Exit;

  aName := Trim(Copy(aLine, 1, lEqualsPos - 1));
  Result := aName <> '';
end;

class function TRemoveWithSymbolBuilder.TryTypeRelation(const aLine: string; out aRelatedTypeName: string;
  out aIsHelper: Boolean): Boolean;
var
  lClosePos: Integer;
  lLower: string;
  lRelationPos: Integer;
  lStartPos: Integer;
  lText: string;
begin
  aRelatedTypeName := '';
  aIsHelper := False;
  lText := Trim(aLine);
  lLower := LowerCase(lText);

  lRelationPos := Pos(' helper for ', lLower);
  if lRelationPos > 0 then
  begin
    aIsHelper := True;
    aRelatedTypeName := Trim(Copy(lText, lRelationPos + Length(' helper for '), MaxInt));
    lClosePos := Pos(';', aRelatedTypeName);
    if lClosePos > 0 then
      aRelatedTypeName := Trim(Copy(aRelatedTypeName, 1, lClosePos - 1));
    Exit(aRelatedTypeName <> '');
  end;
  if Pos(' helper(', lLower) > 0 then
  begin
    aIsHelper := True;
    Exit(False);
  end;

  lStartPos := Pos('class(', lLower);
  if lStartPos > 0 then
  begin
    Inc(lStartPos, Length('class('));
    lClosePos := PosEx(')', lText, lStartPos);
    if lClosePos > lStartPos then
      aRelatedTypeName := Trim(Copy(lText, lStartPos, lClosePos - lStartPos));
    lClosePos := Pos(',', aRelatedTypeName);
    if lClosePos > 0 then
      aRelatedTypeName := Trim(Copy(aRelatedTypeName, 1, lClosePos - 1));
  end;
  if aRelatedTypeName = '' then
  begin
    lStartPos := Pos('interface(', lLower);
    if lStartPos > 0 then
    begin
      Inc(lStartPos, Length('interface('));
      lClosePos := PosEx(')', lText, lStartPos);
      if lClosePos > lStartPos then
        aRelatedTypeName := Trim(Copy(lText, lStartPos, lClosePos - lStartPos));
    end;
  end;
  Result := aRelatedTypeName <> '';
end;

class function TRemoveWithSymbolBuilder.TryRoutineName(const aLine: string; out aName: string): Boolean;
var
  lNameEnd: Integer;
  lNameStart: Integer;
  lText: string;
begin
  Result := False;
  aName := '';
  lText := Trim(aLine);
  if StartsText('class procedure ', lText) then
    lNameStart := Length('class procedure ') + 1
  else if StartsText('class function ', lText) then
    lNameStart := Length('class function ') + 1
  else if StartsText('procedure ', lText) then
    lNameStart := Length('procedure ') + 1
  else if StartsText('function ', lText) then
    lNameStart := Length('function ') + 1
  else if StartsText('constructor ', lText) then
    lNameStart := Length('constructor ') + 1
  else if StartsText('destructor ', lText) then
    lNameStart := Length('destructor ') + 1
  else
    Exit;

  lNameEnd := lNameStart;
  while lNameEnd <= Length(lText) do
  begin
    if IsIdentifierChar(lText[lNameEnd]) or (lText[lNameEnd] = '.') then
      Inc(lNameEnd)
    else
      Break;
  end;
  aName := Copy(lText, lNameStart, lNameEnd - lNameStart);
  Result := aName <> '';
end;

class function TRemoveWithSymbolBuilder.TryRoutineOwner(const aRoutineName: string; out aOwnerType: string): Boolean;
var
  lDotPos: Integer;
begin
  lDotPos := LastDelimiter('.', aRoutineName);
  Result := lDotPos > 0;
  if Result then
    aOwnerType := Copy(aRoutineName, 1, lDotPos - 1)
  else
    aOwnerType := '';
end;

class function TRemoveWithSymbolBuilder.CollectDeclarationText(const aLines: TArray<string>;
  const aStartLine: Integer): string;
var
  lLine: string;
  lParenDepth: Integer;
  i: Integer;
  j: Integer;
begin
  Result := '';
  lParenDepth := 0;
  for i := aStartLine to High(aLines) do
  begin
    lLine := CleanLine(aLines[i]);
    if lLine <> '' then
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + lLine;
      for j := 1 to Length(lLine) do
      begin
        if lLine[j] = '(' then
          Inc(lParenDepth)
        else if (lLine[j] = ')') and (lParenDepth > 0) then
          Dec(lParenDepth);
      end;
    end;
    if (Pos(';', lLine) > 0) and (lParenDepth = 0) then
      Exit;
  end;
end;

class function TRemoveWithSymbolBuilder.CollectTypeStartText(const aLines: TArray<string>;
  const aStartLine: Integer): string;
var
  lLine: string;
  lText: string;
  i: Integer;
begin
  Result := '';
  for i := aStartLine to High(aLines) do
  begin
    lLine := CleanLine(aLines[i]);
    if lLine <> '' then
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + lLine;
      lText := LowerCase(Result);
      if (Pos(' class', lText) > 0) or (Pos(' record', lText) > 0) or (Pos(' interface', lText) > 0) or
        (Pos(';', lLine) > 0) then
        Exit;
    end;
  end;
end;

class function TRemoveWithSymbolBuilder.FindColumn(const aLine, aName: string): Integer;
begin
  Result := Pos(aName, aLine);
  if Result = 0 then
    Result := 1;
end;

class function TRemoveWithSymbolBuilder.IsDirectMemberKind(const aKind: TRemoveWithSymbolKind): Boolean;
begin
  Result := aKind in [TRemoveWithSymbolKind.rwskField, TRemoveWithSymbolKind.rwskProperty,
    TRemoveWithSymbolKind.rwskMethod, TRemoveWithSymbolKind.rwskConstant, TRemoveWithSymbolKind.rwskClassVar];
end;

class function TRemoveWithSymbolBuilder.IsBuiltInTypeName(const aTypeName: string): Boolean;
begin
  Result := MatchText(aTypeName, ['AnsiString', 'Array', 'Boolean', 'Byte', 'Cardinal', 'Char', 'Currency',
    'Date', 'DateTime', 'Double', 'Extended', 'Integer', 'Int64', 'NativeInt', 'NativeUInt', 'Pointer', 'Real',
    'ShortInt', 'Single', 'SmallInt', 'String', 'UInt64', 'Variant', 'WideChar', 'WideString', 'Word']);
end;

class function TRemoveWithSymbolBuilder.OwnerHasOwnMember(const aInventory: TRemoveWithSymbolInventory;
  const aOwnerType, aName: string): Boolean;
var
  lSymbol: TRemoveWithSymbolInfo;
begin
  for lSymbol in aInventory.fSymbols do
  begin
    if SameText(lSymbol.fOwnerType, aOwnerType) and (lSymbol.fSourceOwnerType = '') and
      SameText(lSymbol.fName, aName) and IsDirectMemberKind(lSymbol.fKind) then
      Exit(True);
  end;
  Result := False;
end;

class function TRemoveWithSymbolBuilder.SimpleTypeName(const aTypeName: string): string;
var
  lDelimiterPos: Integer;
  lTypeName: string;
begin
  lTypeName := Trim(aTypeName);
  if StartsText('^', lTypeName) then
    Delete(lTypeName, 1, 1);
  lDelimiterPos := Pos('<', lTypeName);
  if lDelimiterPos = 0 then
    lDelimiterPos := Pos('[', lTypeName);
  if lDelimiterPos = 0 then
    lDelimiterPos := Pos(' ', lTypeName);
  if lDelimiterPos > 0 then
    lTypeName := Trim(Copy(lTypeName, 1, lDelimiterPos - 1));
  lDelimiterPos := LastDelimiter('.', lTypeName);
  if lDelimiterPos > 0 then
    lTypeName := Copy(lTypeName, lDelimiterPos + 1, MaxInt);
  Result := lTypeName;
end;

class function TRemoveWithSymbolBuilder.FindNameSource(const aLines: TArray<string>; const aStartIndex,
  aEndIndex: Integer; const aName: string; out aLineNumber: Integer; out aLineText: string): Boolean;
var
  lEndIndex: Integer;
  i: Integer;
begin
  Result := False;
  aLineNumber := 0;
  aLineText := '';
  lEndIndex := aEndIndex;
  if lEndIndex > High(aLines) then
    lEndIndex := High(aLines);
  for i := aStartIndex to lEndIndex do
  begin
    if Pos(aName, aLines[i]) > 0 then
    begin
      aLineNumber := i + 1;
      aLineText := aLines[i];
      Exit(True);
    end;
  end;
end;

class procedure TRemoveWithSymbolBuilder.AddSymbol(var aInventory: TRemoveWithSymbolInventory;
  const aSymbol: TRemoveWithSymbolInfo);
var
  lIndex: Integer;
  lSymbol: TRemoveWithSymbolInfo;
begin
  for lSymbol in aInventory.fSymbols do
  begin
    if (lSymbol.fKind = aSymbol.fKind) and SameText(lSymbol.fName, aSymbol.fName) and
      SameText(lSymbol.fTypeName, aSymbol.fTypeName) and SameText(lSymbol.fOwnerType, aSymbol.fOwnerType) and
      SameText(lSymbol.fSourceOwnerType, aSymbol.fSourceOwnerType) and
      SameText(lSymbol.fRelatedTypeName, aSymbol.fRelatedTypeName) and
      SameText(lSymbol.fRoutineName, aSymbol.fRoutineName) and SameText(lSymbol.fUnitName, aSymbol.fUnitName) and
      SameText(lSymbol.fFilePath, aSymbol.fFilePath) and (lSymbol.fLine = aSymbol.fLine) and
      (lSymbol.fColumn = aSymbol.fColumn) and (lSymbol.fIsHelper = aSymbol.fIsHelper) and
      (lSymbol.fIsOverride = aSymbol.fIsOverride) then
      Exit;
  end;

  lIndex := Length(aInventory.fSymbols);
  SetLength(aInventory.fSymbols, lIndex + 1);
  aInventory.fSymbols[lIndex] := aSymbol;
end;

class procedure TRemoveWithSymbolBuilder.AddNamedSymbols(var aInventory: TRemoveWithSymbolInventory;
  const aNames: TArray<string>; const aTypeName, aOwnerType, aRoutineName, aUnitName, aFilePath: string;
  const aLineNumber: Integer; const aLineText: string; const aKind: TRemoveWithSymbolKind);
var
  lName: string;
  lSymbol: TRemoveWithSymbolInfo;
begin
  for lName in aNames do
  begin
    lSymbol := Default(TRemoveWithSymbolInfo);
    lSymbol.fName := lName;
    lSymbol.fTypeName := aTypeName;
    lSymbol.fOwnerType := aOwnerType;
    lSymbol.fRoutineName := aRoutineName;
    lSymbol.fUnitName := aUnitName;
    lSymbol.fFilePath := aFilePath;
    lSymbol.fLine := aLineNumber;
    lSymbol.fColumn := FindColumn(aLineText, lName);
    lSymbol.fKind := aKind;
    AddSymbol(aInventory, lSymbol);
  end;
end;

class procedure TRemoveWithSymbolBuilder.AddNamedSymbolsFromSource(var aInventory: TRemoveWithSymbolInventory;
  const aNames: TArray<string>; const aTypeName, aOwnerType, aRoutineName, aUnitName, aFilePath: string;
  const aLines: TArray<string>; const aStartIndex, aEndIndex: Integer; const aKind: TRemoveWithSymbolKind);
var
  lLineNumber: Integer;
  lLineText: string;
  lName: string;
begin
  for lName in aNames do
  begin
    if not FindNameSource(aLines, aStartIndex, aEndIndex, lName, lLineNumber, lLineText) then
    begin
      lLineNumber := aStartIndex + 1;
      if (aStartIndex >= 0) and (aStartIndex <= High(aLines)) then
        lLineText := aLines[aStartIndex]
      else
        lLineText := lName;
    end;
    AddNamedSymbols(aInventory, [lName], aTypeName, aOwnerType, aRoutineName, aUnitName, aFilePath,
      lLineNumber, lLineText, aKind);
  end;
end;

class procedure TRemoveWithSymbolBuilder.ParseParams(var aInventory: TRemoveWithSymbolInventory;
  const aLines: TArray<string>; const aStartIndex: Integer; const aSignature, aRoutineName, aUnitName,
  aFilePath: string);
var
  lClosePos: Integer;
  lEndIndex: Integer;
  lNames: TArray<string>;
  lOpenPos: Integer;
  lPart: string;
  lParts: TArray<string>;
  lText: string;
  lTypeName: string;
begin
  lOpenPos := Pos('(', aSignature);
  lClosePos := LastDelimiter(')', aSignature);
  if (lOpenPos = 0) or (lClosePos <= lOpenPos) then
    Exit;

  lParts := Copy(aSignature, lOpenPos + 1, lClosePos - lOpenPos - 1).Split([';']);
  for lPart in lParts do
  begin
    lText := Trim(lPart);
    if StartsText('const ', lText) then
      Delete(lText, 1, Length('const '))
    else if StartsText('var ', lText) then
      Delete(lText, 1, Length('var '))
    else if StartsText('out ', lText) then
      Delete(lText, 1, Length('out '));

    if TryDeclaration(lText, lNames, lTypeName) then
    begin
      lEndIndex := aStartIndex + 20;
      AddNamedSymbolsFromSource(aInventory, lNames, lTypeName, '', aRoutineName, aUnitName, aFilePath, aLines,
        aStartIndex, lEndIndex, TRemoveWithSymbolKind.rwskParameter);
    end;
  end;
end;

class procedure TRemoveWithSymbolBuilder.ParseLocals(var aInventory: TRemoveWithSymbolInventory;
  const aLines: TArray<string>; const aStartLine: Integer; const aRoutineName, aUnitName, aFilePath: string);
var
  lDeclaration: string;
  lDeclarationLine: Integer;
  lInVar: Boolean;
  lLine: string;
  lNames: TArray<string>;
  lTypeName: string;
  i: Integer;
begin
  lDeclaration := '';
  lDeclarationLine := 0;
  lInVar := False;
  for i := aStartLine to High(aLines) do
  begin
    lLine := CleanLine(aLines[i]);
    if SameText(lLine, 'var') then
    begin
      lInVar := True;
      Continue;
    end;
    if SameText(lLine, 'begin') then
      Exit;
    if lInVar and (lLine <> '') then
    begin
      if lDeclaration = '' then
      begin
        lDeclarationLine := i + 1;
      end;
      if lDeclaration <> '' then
        lDeclaration := lDeclaration + ' ';
      lDeclaration := lDeclaration + lLine;
      if Pos(';', lLine) > 0 then
      begin
        if TryDeclaration(lDeclaration, lNames, lTypeName) then
          AddNamedSymbolsFromSource(aInventory, lNames, lTypeName, '', aRoutineName, aUnitName, aFilePath,
            aLines, lDeclarationLine - 1, i, TRemoveWithSymbolKind.rwskLocalVariable);
        lDeclaration := '';
        lDeclarationLine := 0;
      end;
    end;
  end;
end;

class procedure TRemoveWithSymbolBuilder.ParseTypeMembers(var aInventory: TRemoveWithSymbolInventory;
  const aLines: TArray<string>; const aUnitName, aFilePath: string);
var
  lConstName: string;
  lCurrentType: string;
  lInClassVar: Boolean;
  lInConst: Boolean;
  lInTypeSection: Boolean;
  lLine: string;
  lLower: string;
  lMemberName: string;
  lNames: TArray<string>;
  lPropertyType: string;
  lPropertyTypeEnd: Integer;
  lRawLine: string;
  lRelatedTypeName: string;
  lTypeText: string;
  lTypeSymbol: TRemoveWithSymbolInfo;
  lTopLevelLine: Boolean;
  lTypeIsHelper: Boolean;
  lTypeName: string;
  i: Integer;
begin
  lCurrentType := '';
  lInClassVar := False;
  lInConst := False;
  lInTypeSection := False;
  for i := 0 to High(aLines) do
  begin
    lRawLine := aLines[i];
    lLine := CleanLine(lRawLine);
    lLower := LowerCase(lLine);
    if lLine = '' then
      Continue;
    lTopLevelLine := IsTopLevelLine(lRawLine);

    if lTopLevelLine and SameText(lLine, 'type') then
    begin
      lInTypeSection := True;
      Continue;
    end;
    if lTopLevelLine and (SameText(lLine, 'implementation') or SameText(lLine, 'const') or
      SameText(lLine, 'var') or SameText(lLine, 'threadvar') or IsRoutineStart(lLine)) then
    begin
      lCurrentType := '';
      lInTypeSection := False;
      lInClassVar := False;
      lInConst := False;
      Continue;
    end;

    if lCurrentType = '' then
    begin
      if not lInTypeSection then
        Continue;
      lTypeText := CollectTypeStartText(aLines, i);
      if TryTypeStart(lTypeText, lCurrentType) then
      begin
        lInClassVar := False;
        lInConst := False;
        TryTypeRelation(lTypeText, lRelatedTypeName, lTypeIsHelper);
        lTypeSymbol := Default(TRemoveWithSymbolInfo);
        lTypeSymbol.fName := lCurrentType;
        lTypeSymbol.fRelatedTypeName := lRelatedTypeName;
        lTypeSymbol.fIsHelper := lTypeIsHelper;
        lTypeSymbol.fUnitName := aUnitName;
        lTypeSymbol.fFilePath := aFilePath;
        lTypeSymbol.fLine := i + 1;
        lTypeSymbol.fColumn := FindColumn(aLines[i], lCurrentType);
        lTypeSymbol.fKind := TRemoveWithSymbolKind.rwskTypeMember;
        AddSymbol(aInventory, lTypeSymbol);
      end else if TryTypeAlias(lLine, lMemberName, lTypeName) then
      begin
        AddNamedSymbols(aInventory, [lMemberName], lTypeName, '', '', aUnitName, aFilePath, i + 1, aLines[i],
          TRemoveWithSymbolKind.rwskTypeMember);
      end;
      Continue;
    end;

    if SameText(lLine, 'end;') or SameText(lLine, 'end') then
    begin
      lCurrentType := '';
      Continue;
    end;
    if IsVisibilityLine(lLine) then
      Continue;
    if StartsText('class var', lLower) then
    begin
      lInClassVar := True;
      lLine := Trim(Copy(lLine, Length('class var') + 1, MaxInt));
      if lLine = '' then
        Continue;
    end;
    if SameText(lLine, 'const') then
    begin
      lInConst := True;
      lInClassVar := False;
      Continue;
    end;
    if StartsText('const ', lLower) then
    begin
      lInConst := True;
      lLine := Trim(Copy(lLine, Length('const ') + 1, MaxInt));
    end;

    if lInConst and TryConstDeclaration(lLine, lConstName, lTypeName) then
    begin
      AddNamedSymbols(aInventory, [lConstName], lTypeName, lCurrentType, '', aUnitName, aFilePath, i + 1,
        aLines[i], TRemoveWithSymbolKind.rwskConstant);
      Continue;
    end;

    if StartsText('property ', lLower) then
    begin
      lMemberName := Trim(Copy(lLine, Length('property ') + 1, MaxInt));
      if Pos(':', lMemberName) > 0 then
      begin
        lPropertyType := Trim(Copy(lMemberName, Pos(':', lMemberName) + 1, MaxInt));
        lPropertyTypeEnd := Pos(' read ', LowerCase(lPropertyType));
        if lPropertyTypeEnd = 0 then
          lPropertyTypeEnd := Pos(' write ', LowerCase(lPropertyType));
        if lPropertyTypeEnd = 0 then
          lPropertyTypeEnd := Pos(';', lPropertyType);
        if lPropertyTypeEnd > 0 then
          lPropertyType := Trim(Copy(lPropertyType, 1, lPropertyTypeEnd - 1));
        lMemberName := Trim(Copy(lMemberName, 1, Pos(':', lMemberName) - 1));
      end else
        lPropertyType := '';
      AddNamedSymbols(aInventory, [lMemberName], lPropertyType, lCurrentType, '', aUnitName, aFilePath, i + 1,
        aLines[i], TRemoveWithSymbolKind.rwskProperty);
      Continue;
    end;

    if IsRoutineStart(lLine) and TryRoutineName(lLine, lMemberName) then
    begin
      if Pos('.', lMemberName) > 0 then
        lMemberName := Copy(lMemberName, LastDelimiter('.', lMemberName) + 1, MaxInt);
      lTypeSymbol := Default(TRemoveWithSymbolInfo);
      lTypeSymbol.fName := lMemberName;
      lTypeSymbol.fOwnerType := lCurrentType;
      lTypeSymbol.fUnitName := aUnitName;
      lTypeSymbol.fFilePath := aFilePath;
      lTypeSymbol.fLine := i + 1;
      lTypeSymbol.fColumn := FindColumn(aLines[i], lMemberName);
      lTypeSymbol.fIsOverride := Pos(' override', lLower) > 0;
      lTypeSymbol.fKind := TRemoveWithSymbolKind.rwskMethod;
      AddSymbol(aInventory, lTypeSymbol);
      Continue;
    end;

    if TryDeclaration(lLine, lNames, lTypeName) then
    begin
      if lInClassVar then
        AddNamedSymbols(aInventory, lNames, lTypeName, lCurrentType, '', aUnitName, aFilePath, i + 1, aLines[i],
          TRemoveWithSymbolKind.rwskClassVar)
      else
        AddNamedSymbols(aInventory, lNames, lTypeName, lCurrentType, '', aUnitName, aFilePath, i + 1, aLines[i],
          TRemoveWithSymbolKind.rwskField);
    end;
  end;
end;

class procedure TRemoveWithSymbolBuilder.ParseUnitGlobals(var aInventory: TRemoveWithSymbolInventory;
  const aLines: TArray<string>; const aUnitName, aFilePath: string);
var
  lConstName: string;
  lInConst: Boolean;
  lInRoutine: Boolean;
  lInType: Boolean;
  lInVar: Boolean;
  lLine: string;
  lNames: TArray<string>;
  lRawLine: string;
  lTopLevelLine: Boolean;
  lTypeName: string;
  i: Integer;
begin
  lInConst := False;
  lInRoutine := False;
  lInType := False;
  lInVar := False;
  for i := 0 to High(aLines) do
  begin
    lRawLine := aLines[i];
    lLine := CleanLine(lRawLine);
    if lLine = '' then
      Continue;
    lTopLevelLine := IsTopLevelLine(lRawLine);

    if lTopLevelLine and SameText(lLine, 'implementation') then
    begin
      lInRoutine := False;
      lInType := False;
      lInVar := False;
      lInConst := False;
      Continue;
    end;

    if lTopLevelLine and SameText(lLine, 'type') then
    begin
      lInType := True;
      lInVar := False;
      lInConst := False;
      Continue;
    end;
    if lTopLevelLine and (SameText(lLine, 'var') or SameText(lLine, 'threadvar')) then
    begin
      lInType := False;
      lInVar := True;
      lInConst := False;
      Continue;
    end;
    if lTopLevelLine and SameText(lLine, 'const') then
    begin
      lInType := False;
      lInConst := True;
      lInVar := False;
      Continue;
    end;

    if lInType then
      Continue;

    if IsRoutineStart(lLine) then
    begin
      lInRoutine := True;
      lInVar := False;
      lInConst := False;
      Continue;
    end;
    if lInRoutine then
      Continue;

    if lInVar and TryDeclaration(lLine, lNames, lTypeName) then
      AddNamedSymbols(aInventory, lNames, lTypeName, '', '', aUnitName, aFilePath, i + 1, aLines[i],
        TRemoveWithSymbolKind.rwskUnitGlobal)
    else if lInConst and TryConstDeclaration(lLine, lConstName, lTypeName) then
      AddNamedSymbols(aInventory, [lConstName], lTypeName, '', '', aUnitName, aFilePath, i + 1, aLines[i],
        TRemoveWithSymbolKind.rwskConstant);
  end;
end;

class procedure TRemoveWithSymbolBuilder.ParseRoutines(var aInventory: TRemoveWithSymbolInventory;
  const aLines: TArray<string>; const aUnitName, aFilePath: string);
var
  lInType: Boolean;
  lMember: TRemoveWithSymbolInfo;
  lMemberCount: Integer;
  lLine: string;
  lOwnerType: string;
  lRawLine: string;
  lRoutineName: string;
  lSignature: string;
  lTopLevelLine: Boolean;
  i: Integer;
  j: Integer;
begin
  lInType := False;
  for i := 0 to High(aLines) do
  begin
    lRawLine := aLines[i];
    lLine := CleanLine(lRawLine);
    if lLine = '' then
      Continue;
    lTopLevelLine := IsTopLevelLine(lRawLine);
    if lTopLevelLine and SameText(lLine, 'type') then
    begin
      lInType := True;
      Continue;
    end;
    if lTopLevelLine and (SameText(lLine, 'const') or SameText(lLine, 'var') or SameText(lLine, 'threadvar') or
      SameText(lLine, 'implementation')) then
    begin
      lInType := False;
      if SameText(lLine, 'implementation') then
        Continue;
    end;
    if lInType then
      Continue;

    lSignature := CollectDeclarationText(aLines, i);
    if not TryRoutineName(lSignature, lRoutineName) then
      Continue;

    AddNamedSymbols(aInventory, [lRoutineName], '', '', '', aUnitName, aFilePath, i + 1, aLines[i],
      TRemoveWithSymbolKind.rwskRoutine);
    ParseParams(aInventory, aLines, i, lSignature, lRoutineName, aUnitName, aFilePath);
    ParseLocals(aInventory, aLines, i + 1, lRoutineName, aUnitName, aFilePath);
    if TryRoutineOwner(lRoutineName, lOwnerType) then
    begin
      lMemberCount := Length(aInventory.fSymbols);
      for j := 0 to lMemberCount - 1 do
      begin
        lMember := aInventory.fSymbols[j];
        if SameText(lMember.fOwnerType, lOwnerType) and (lMember.fRoutineName = '') and
          IsDirectMemberKind(lMember.fKind) then
        begin
          lMember.fKind := TRemoveWithSymbolKind.rwskCurrentClassMember;
          lMember.fRoutineName := lRoutineName;
          AddSymbol(aInventory, lMember);
        end;
      end;
    end;
  end;
end;

class procedure TRemoveWithSymbolBuilder.AddRelatedTypeMemberSymbols(var aInventory: TRemoveWithSymbolInventory);
var
  lAdded: Boolean;
  lBeforeCount: Integer;
  lMember: TRemoveWithSymbolInfo;
  lSourceOwnerType: string;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeSymbol: TRemoveWithSymbolInfo;
  i: Integer;
  j: Integer;
begin
  repeat
    lAdded := False;
    lBeforeCount := Length(aInventory.fSymbols);
    for i := 0 to lBeforeCount - 1 do
    begin
      lTypeSymbol := aInventory.fSymbols[i];
      if (lTypeSymbol.fKind <> TRemoveWithSymbolKind.rwskTypeMember) or
        (lTypeSymbol.fRelatedTypeName = '') then
        Continue;

      for j := 0 to lBeforeCount - 1 do
      begin
        lMember := aInventory.fSymbols[j];
        if (lMember.fRoutineName <> '') or (not IsDirectMemberKind(lMember.fKind)) then
          Continue;

        if lTypeSymbol.fIsHelper then
        begin
          if not SameText(lMember.fOwnerType, lTypeSymbol.fName) then
            Continue;
          lSymbol := lMember;
          lSymbol.fOwnerType := lTypeSymbol.fRelatedTypeName;
          lSymbol.fSourceOwnerType := lTypeSymbol.fName;
        end else
        begin
          if not SameText(lMember.fOwnerType, lTypeSymbol.fRelatedTypeName) then
            Continue;
          lSymbol := lMember;
          lSymbol.fOwnerType := lTypeSymbol.fName;
          lSourceOwnerType := lMember.fSourceOwnerType;
          if lSourceOwnerType = '' then
            lSourceOwnerType := lMember.fOwnerType;
          lSymbol.fSourceOwnerType := lSourceOwnerType;
        end;

        if OwnerHasOwnMember(aInventory, lSymbol.fOwnerType, lSymbol.fName) then
          Continue;
        AddSymbol(aInventory, lSymbol);
        lAdded := lAdded or (Length(aInventory.fSymbols) > lBeforeCount);
      end;
    end;
  until not lAdded;
end;

class procedure TRemoveWithSymbolBuilder.AddRelatedCurrentClassSymbols(var aInventory: TRemoveWithSymbolInventory);
var
  lCurrentMember: TRemoveWithSymbolInfo;
  lMember: TRemoveWithSymbolInfo;
  lSymbol: TRemoveWithSymbolInfo;
  lSymbolCount: Integer;
  i: Integer;
  j: Integer;
begin
  lSymbolCount := Length(aInventory.fSymbols);
  for i := 0 to lSymbolCount - 1 do
  begin
    lCurrentMember := aInventory.fSymbols[i];
    if (lCurrentMember.fKind <> TRemoveWithSymbolKind.rwskCurrentClassMember) or
      (lCurrentMember.fOwnerType = '') or (lCurrentMember.fRoutineName = '') then
      Continue;

    for j := 0 to lSymbolCount - 1 do
    begin
      lMember := aInventory.fSymbols[j];
      if SameText(lMember.fOwnerType, lCurrentMember.fOwnerType) and (lMember.fRoutineName = '') and
        IsDirectMemberKind(lMember.fKind) then
      begin
        lSymbol := lMember;
        lSymbol.fKind := TRemoveWithSymbolKind.rwskCurrentClassMember;
        lSymbol.fRoutineName := lCurrentMember.fRoutineName;
        AddSymbol(aInventory, lSymbol);
      end;
    end;
  end;
end;

class procedure TRemoveWithSymbolBuilder.ParseUnit(var aInventory: TRemoveWithSymbolInventory; const aUnitName,
  aFilePath: string);
var
  lLines: TArray<string>;
  lSymbol: TRemoveWithSymbolInfo;
begin
  lSymbol := Default(TRemoveWithSymbolInfo);
  lSymbol.fName := aUnitName;
  lSymbol.fUnitName := aUnitName;
  lSymbol.fFilePath := aFilePath;
  lSymbol.fLine := 1;
  lSymbol.fColumn := 1;
  lSymbol.fKind := TRemoveWithSymbolKind.rwskUnitName;
  AddSymbol(aInventory, lSymbol);

  lLines := TFile.ReadAllLines(aFilePath, TEncoding.UTF8);
  ParseTypeMembers(aInventory, lLines, aUnitName, aFilePath);
  ParseUnitGlobals(aInventory, lLines, aUnitName, aFilePath);
  ParseRoutines(aInventory, lLines, aUnitName, aFilePath);
end;

class procedure TRemoveWithSymbolBuilder.AddExternalUnitSymbols(var aInventory: TRemoveWithSymbolInventory);
var
  lBlockText: string;
  lCleanLine: string;
  lExistingUnits: TDictionary<string, Byte>;
  lExternalSymbol: TRemoveWithSymbolInfo;
  lExternalUnits: TDictionary<string, Byte>;
  lInUses: Boolean;
  lLine: string;
  lLines: TArray<string>;
  lPart: string;
  lParts: TArray<string>;
  lSourceSymbol: TRemoveWithSymbolInfo;
  lSourceSymbols: TList<TRemoveWithSymbolInfo>;
  lSymbol: TRemoveWithSymbolInfo;
  lUnitKey: string;
  lUnitName: string;
begin
  lExistingUnits := TDictionary<string, Byte>.Create;
  try
    lExternalUnits := TDictionary<string, Byte>.Create;
    try
      lSourceSymbols := TList<TRemoveWithSymbolInfo>.Create;
      try
        for lSymbol in aInventory.fSymbols do
        begin
          if lSymbol.fKind = TRemoveWithSymbolKind.rwskUnitName then
          begin
            lExistingUnits.AddOrSetValue(UpperCase(lSymbol.fName), 1);
            lSourceSymbols.Add(lSymbol);
          end else if lSymbol.fKind = TRemoveWithSymbolKind.rwskExternal then
            lExternalUnits.AddOrSetValue(UpperCase(lSymbol.fName), 1);
        end;

        for lSourceSymbol in lSourceSymbols do
        begin
          if (lSourceSymbol.fKind <> TRemoveWithSymbolKind.rwskUnitName) or
            (not TFile.Exists(lSourceSymbol.fFilePath)) then
            Continue;

        lLines := TFile.ReadAllLines(lSourceSymbol.fFilePath, TEncoding.UTF8);
        lInUses := False;
        lBlockText := '';
        for lLine in lLines do
        begin
          lCleanLine := CleanLine(lLine);
          if lCleanLine = '' then
            Continue;

          if not lInUses then
          begin
            if not StartsText('uses', LowerCase(lCleanLine)) then
              Continue;
            if (Length(lCleanLine) > 4) and IsIdentifierChar(lCleanLine[5]) then
              Continue;
            lInUses := True;
            lBlockText := Trim(Copy(lCleanLine, 5, MaxInt));
          end else
            lBlockText := Trim(lBlockText + ' ' + lCleanLine);

          if Pos(';', lCleanLine) = 0 then
            Continue;

          lParts := lBlockText.Replace(';', ',').Split([',']);
          for lPart in lParts do
          begin
            lUnitName := Trim(lPart);
            if ContainsText(lUnitName, ' in ') then
              lUnitName := Trim(Copy(lUnitName, 1, Pos(' in ', LowerCase(lUnitName)) - 1));
            if ContainsText(lUnitName, '=') then
              lUnitName := Trim(Copy(lUnitName, Pos('=', lUnitName) + 1, MaxInt));
            if lUnitName = '' then
              Continue;

            lUnitKey := UpperCase(lUnitName);
            if lExistingUnits.ContainsKey(lUnitKey) or lExternalUnits.ContainsKey(lUnitKey) then
              Continue;
            lExternalUnits.Add(lUnitKey, 1);
            lExternalSymbol := Default(TRemoveWithSymbolInfo);
            lExternalSymbol.fName := lUnitName;
            lExternalSymbol.fUnitName := lSourceSymbol.fName;
            lExternalSymbol.fFilePath := lSourceSymbol.fFilePath;
            lExternalSymbol.fKind := TRemoveWithSymbolKind.rwskExternal;
            AddSymbol(aInventory, lExternalSymbol);
          end;

          lInUses := False;
          lBlockText := '';
        end;
        end;
      finally
        lSourceSymbols.Free;
      end;
    finally
      lExternalUnits.Free;
    end;
  finally
    lExistingUnits.Free;
  end;
end;

class procedure TRemoveWithSymbolBuilder.AddExternalTypeSymbols(var aInventory: TRemoveWithSymbolInventory);
var
  lExternalSymbol: TRemoveWithSymbolInfo;
  lExternalTypes: TDictionary<string, Byte>;
  lSourceTypes: TDictionary<string, Byte>;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeKey: string;
  lTypeName: string;
begin
  lSourceTypes := TDictionary<string, Byte>.Create;
  try
    lExternalTypes := TDictionary<string, Byte>.Create;
    try
      for lSymbol in aInventory.fSymbols do
      begin
        if lSymbol.fKind = TRemoveWithSymbolKind.rwskTypeMember then
          lSourceTypes.AddOrSetValue(UpperCase(lSymbol.fName), 1);
      end;

      for lSymbol in aInventory.fSymbols do
      begin
        lTypeName := SimpleTypeName(lSymbol.fTypeName);
        if (lTypeName <> '') and (not IsBuiltInTypeName(lTypeName)) then
        begin
          lTypeKey := UpperCase(lTypeName);
          if (not lSourceTypes.ContainsKey(lTypeKey)) and (not lExternalTypes.ContainsKey(lTypeKey)) then
          begin
            lExternalTypes.Add(lTypeKey, 1);
            lExternalSymbol := Default(TRemoveWithSymbolInfo);
            lExternalSymbol.fName := lTypeName;
            lExternalSymbol.fTypeName := lTypeName;
            lExternalSymbol.fKind := TRemoveWithSymbolKind.rwskExternal;
            AddSymbol(aInventory, lExternalSymbol);
          end;
        end;

        lTypeName := SimpleTypeName(lSymbol.fRelatedTypeName);
        if (lTypeName = '') or IsBuiltInTypeName(lTypeName) then
          Continue;
        lTypeKey := UpperCase(lTypeName);
        if lSourceTypes.ContainsKey(lTypeKey) or lExternalTypes.ContainsKey(lTypeKey) then
          Continue;
        lExternalTypes.Add(lTypeKey, 1);
        lExternalSymbol := Default(TRemoveWithSymbolInfo);
        lExternalSymbol.fName := lTypeName;
        lExternalSymbol.fTypeName := lTypeName;
        lExternalSymbol.fKind := TRemoveWithSymbolKind.rwskExternal;
        AddSymbol(aInventory, lExternalSymbol);
      end;
    finally
      lExternalTypes.Free;
    end;
  finally
    lSourceTypes.Free;
  end;
end;

function BuildRemoveWithSymbolInventory(const aOptions: TAppOptions; out aInventory: TRemoveWithSymbolInventory;
  out aError: string): Boolean;
var
  lContext: TProjectAnalysisContext;
  lIndexer: TProjectIndexer;
  lParsedPaths: TDictionary<string, Byte>;
  lProblem: TProjectIndexer.TProblemInfo;
  lSymbol: TRemoveWithSymbolInfo;
  lUnit: TProjectIndexer.TUnitInfo;
  lUnitPath: string;
begin
  aInventory := Default(TRemoveWithSymbolInventory);
  aError := '';
  if not TryBuildProjectAnalysisContext(aOptions, lContext, aError) then
    Exit(False);

  lIndexer := TProjectIndexer.Create;
  try
    lIndexer.Defines := lContext.fParserDefines;
    lIndexer.SearchPath := lContext.fParserSearchPath;
    lIndexer.Index(lContext.fMainSourcePath);

    lParsedPaths := TDictionary<string, Byte>.Create;
    try
      for lUnit in lIndexer.ParsedUnits do
      begin
        lUnitPath := Trim(lUnit.Path);
        if (lUnitPath = '') or (not SameText(TPath.GetExtension(lUnitPath), '.pas')) or
          (not TFile.Exists(lUnitPath)) then
          Continue;
        lUnitPath := TPath.GetFullPath(lUnitPath);
        if lParsedPaths.ContainsKey(UpperCase(lUnitPath)) then
          Continue;
        lParsedPaths.Add(UpperCase(lUnitPath), 1);
    TRemoveWithSymbolBuilder.ParseUnit(aInventory, lUnit.Name, lUnitPath);
      end;
    finally
      lParsedPaths.Free;
    end;

    TRemoveWithSymbolBuilder.AddRelatedTypeMemberSymbols(aInventory);
    TRemoveWithSymbolBuilder.AddRelatedCurrentClassSymbols(aInventory);
    TRemoveWithSymbolBuilder.AddExternalUnitSymbols(aInventory);
    TRemoveWithSymbolBuilder.AddExternalTypeSymbols(aInventory);

    for lProblem in lIndexer.Problems do
    begin
      lSymbol := Default(TRemoveWithSymbolInfo);
      lSymbol.fName := TPath.GetFileNameWithoutExtension(lProblem.FileName);
      lSymbol.fFilePath := lProblem.FileName;
      lSymbol.fKind := TRemoveWithSymbolKind.rwskExternal;
      TRemoveWithSymbolBuilder.AddSymbol(aInventory, lSymbol);
    end;
  finally
    lIndexer.Free;
  end;
  Result := True;
end;

end.
