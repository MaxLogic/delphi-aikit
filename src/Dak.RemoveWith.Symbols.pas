unit Dak.RemoveWith.Symbols;

interface

uses
  DelphiSemantics.Model, DelphiSemantics.WithBinding,
  Dak.RemoveWith.Model, Dak.Types;

type
  TRemoveWithTypeCategory = (rwtcUnknown, rwtcRecord, rwtcClass, rwtcInterface);

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
    fEndLine: Integer;
    fColumn: Integer;
    fUnsupportedReason: string;
    fIsHelper: Boolean;
    fIsOverride: Boolean;
    fIsDefault: Boolean;
    fTypeCategory: TRemoveWithTypeCategory;
    fKind: TRemoveWithSymbolKind;
  end;

  TRemoveWithSymbolInventory = record
    fSymbols: TArray<TRemoveWithSymbolInfo>;
    fSemanticIndex: TRemoveWithSemanticIndex;
    fDelphiSemanticUnitModels: TArray<TDelphiSemanticUnitModel>;
    fDelphiSemanticWithBindings: TArray<TDelphiSemanticWithBinding>;
    fParserDefines: string;
  end;

function RemoveWithSymbolKindToText(const aKind: TRemoveWithSymbolKind): string;
function RemoveWithTypeCategoryToText(const aCategory: TRemoveWithTypeCategory): string;
function BuildRemoveWithSymbolInventory(const aOptions: TAppOptions; out aInventory: TRemoveWithSymbolInventory;
  out aError: string): Boolean; overload;
function BuildRemoveWithSymbolInventory(const aOptions: TAppOptions; const aProjectModel: TRemoveWithProjectModel;
  out aInventory: TRemoveWithSymbolInventory; out aError: string): Boolean; overload;

implementation

uses
  System.Classes, System.Diagnostics, System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  DelphiAST.ProjectIndexer,
  MaxLogic.StrUtils;

procedure LogRemoveWithSymbolProgress(const aOptions: TAppOptions; const aMessage: string);
begin
  if not aOptions.fVerbose then
    Exit;
  WriteLn(ErrOutput, FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now) + ' [remove-with:symbols] ' +
    aMessage);
  Flush(ErrOutput);
end;

function SplitSemanticListText(const aText: string): TArray<string>;
var
  lItems: TArray<string>;
  lPart: string;
  lResult: TList<string>;
begin
  lResult := TList<string>.Create;
  try
    lItems := SplitString(aText, ';');
    for lPart in lItems do
    begin
      if Trim(lPart) <> '' then
      begin
        lResult.Add(Trim(lPart));
      end;
    end;
    Result := lResult.ToArray;
  finally
    lResult.Free;
  end;
end;

type
  TRemoveWithSymbolBuilder = record
  private
    class function SameSymbol(const aLeft, aRight: TRemoveWithSymbolInfo): Boolean; static;
    class function SymbolIdentityKey(const aSymbol: TRemoveWithSymbolInfo): string; static;
    class function CleanLine(const aLine: string): string; static;
    class function IsIdentifierChar(const aValue: Char): Boolean; static;
    class function IsTopLevelLine(const aLine: string): Boolean; static;
    class function IsVisibilityLine(const aLine: string): Boolean; static;
    class function IsRoutineStart(const aLine: string): Boolean; static;
    class function IsAttributeLine(const aLine: string): Boolean; static;
    class function IsConditionalDirectiveLine(const aLine: string): Boolean; static;
    class function IsConditionalStartDirective(const aLine: string): Boolean; static;
    class function IsConditionalEndDirective(const aLine: string): Boolean; static;
    class function IsMultilineDeclarationStart(const aLine: string): Boolean; static;
    class function TryDeclaration(const aLine: string; out aNames: TArray<string>; out aTypeName: string): Boolean;
      static;
    class function TryConstDeclaration(const aLine: string; out aName: string; out aTypeName: string): Boolean; static;
    class function TryPropertyDeclaration(const aLine: string; out aName, aTypeName: string;
      out aIsDefault: Boolean): Boolean; static;
    class function TryEnumValues(const aTypeText: string; out aNames: TArray<string>): Boolean; static;
    class function TryTypeAlias(const aLine: string; out aName: string; out aTypeName: string): Boolean; static;
    class function TryTypeStart(const aLine: string; out aName: string;
      out aCategory: TRemoveWithTypeCategory): Boolean; static;
    class function TryVariantTagDeclaration(const aLine: string; out aName, aTypeName: string): Boolean; static;
    class function VariantFieldDeclarationLine(const aLine: string): string; static;
    class function TryTypeRelation(const aLine: string; out aRelatedTypeName: string; out aIsHelper: Boolean): Boolean;
      static;
    class function TryRoutineName(const aLine: string; out aName: string): Boolean; static;
    class function TryRoutineOwner(const aRoutineName: string; out aOwnerType: string): Boolean; static;
    class function EndTerminatedBlockOpenCount(const aText: string): Integer; static;
    class function TokenCount(const aText, aToken: string): Integer; static;
    class function FindRoutineEndLine(const aLines: TArray<string>; const aStartIndex: Integer): Integer; static;
    class function CollectDeclarationText(const aLines: TArray<string>; const aStartLine: Integer): string; overload;
      static;
    class function CollectDeclarationText(const aLines: TArray<string>; const aStartLine: Integer;
      out aEndLine: Integer): string; overload; static;
    class function CollectTypeStartText(const aLines: TArray<string>; const aStartLine: Integer): string; static;
    class function FindColumn(const aLine, aName: string): Integer; static;
    class function IsDirectMemberKind(const aKind: TRemoveWithSymbolKind): Boolean; static;
    class function IsBuiltInTypeName(const aTypeName: string): Boolean; static;
    class function OwnerHasOwnMember(const aInventory: TRemoveWithSymbolInventory; const aOwnerType,
      aName: string): Boolean; static;
    class function SimpleTypeName(const aTypeName: string): string; static;
    class function UnsupportedReasonForTypeStart(const aTypeName, aPendingReason: string;
      const aConditionalDepth: Integer): string; static;
    class function FindNameSource(const aLines: TArray<string>; const aStartIndex, aEndIndex: Integer;
      const aName: string; out aLineNumber: Integer; out aLineText: string): Boolean; static;
    class function DecodeSourceText(const aBytes: TBytes): string; static;
    class function ReadSourceLines(const aFilePath: string): TArray<string>; static;
    class procedure AddSymbol(var aInventory: TRemoveWithSymbolInventory; const aSymbol: TRemoveWithSymbolInfo);
      static;
    class procedure MarkTypeUnsupported(var aInventory: TRemoveWithSymbolInventory; const aTypeName,
      aReason: string); static;
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

var
  GRemoveWithSymbolKeys: TDictionary<string, Byte>;

procedure AppendDelphiSemanticModel(var aInventory: TRemoveWithSymbolInventory;
  const aModel: TDelphiSemanticUnitModel);
var
  lIndex: Integer;
begin
  lIndex := Length(aInventory.fDelphiSemanticUnitModels);
  SetLength(aInventory.fDelphiSemanticUnitModels, lIndex + 1);
  aInventory.fDelphiSemanticUnitModels[lIndex] := aModel;
end;

procedure AppendDelphiSemanticBindings(var aInventory: TRemoveWithSymbolInventory;
  const aBindings: TArray<TDelphiSemanticWithBinding>);
var
  lBinding: TDelphiSemanticWithBinding;
  lIndex: Integer;
begin
  for lBinding in aBindings do
  begin
    lIndex := Length(aInventory.fDelphiSemanticWithBindings);
    SetLength(aInventory.fDelphiSemanticWithBindings, lIndex + 1);
    aInventory.fDelphiSemanticWithBindings[lIndex] := lBinding;
  end;
end;

procedure BuildDelphiSemanticBindings(const aProjectModel: TRemoveWithProjectModel;
  var aInventory: TRemoveWithSymbolInventory);
var
  lBindings: TArray<TDelphiSemanticWithBinding>;
  lOptions: TDelphiSemanticModelOptions;
  lSemanticModel: TDelphiSemanticUnitModel;
  lUnitModel: TRemoveWithUnitModel;
begin
  for lUnitModel in aProjectModel.UnitModels do
  begin
    if (Length(lUnitModel.fWithStatements) = 0) or (Trim(lUnitModel.fFilePath) = '') or
      (not SameText(TPath.GetExtension(lUnitModel.fFilePath), '.pas')) or
      (not TFile.Exists(lUnitModel.fFilePath)) then
    begin
      Continue;
    end;

    lOptions := Default(TDelphiSemanticModelOptions);
    lOptions.SourceFileName := lUnitModel.fFilePath;
    lOptions.ProjectContextApplied := True;
    lOptions.Defines := SplitSemanticListText(aProjectModel.Context.fParserDefines);
    lOptions.SearchPaths := SplitSemanticListText(aProjectModel.Context.fParserSearchPath);
    lSemanticModel := TDelphiSemanticUnitModelExtractor.ExtractFromFile(lOptions);
    if not lSemanticModel.Success then
    begin
      Continue;
    end;

    AppendDelphiSemanticModel(aInventory, lSemanticModel);
    lBindings := TDelphiSemanticWithBinder.BindModel(lSemanticModel);
    AppendDelphiSemanticBindings(aInventory, lBindings);
  end;
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

function RemoveWithTypeCategoryToText(const aCategory: TRemoveWithTypeCategory): string;
begin
  case aCategory of
    TRemoveWithTypeCategory.rwtcRecord:
      Result := 'record';
    TRemoveWithTypeCategory.rwtcClass:
      Result := 'class';
    TRemoveWithTypeCategory.rwtcInterface:
      Result := 'interface';
  else
    Result := 'unknown';
  end;
end;

class function TRemoveWithSymbolBuilder.CleanLine(const aLine: string): string;
var
  lCommentPos: Integer;
  lEndPos: Integer;
  lStartPos: Integer;
begin
  Result := Trim(aLine);
  if Result = '' then
    Exit;
  if StartsText('{$', Result) or StartsText('(*$', Result) then
    Exit;

  repeat
    lStartPos := Pos('{', Result);
    if lStartPos = 0 then
      Break;
    if Copy(Result, lStartPos, 2) = '{$' then
      Break;
    lEndPos := PosEx('}', Result, lStartPos + 1);
    if lEndPos = 0 then
    begin
      Delete(Result, lStartPos, MaxInt);
      Break;
    end;
    Delete(Result, lStartPos, lEndPos - lStartPos + 1);
    Result := Trim(Result);
  until False;

  repeat
    lStartPos := Pos('(*', Result);
    if lStartPos = 0 then
      Break;
    if Copy(Result, lStartPos, 3) = '(*$' then
      Break;
    lEndPos := PosEx('*)', Result, lStartPos + 2);
    if lEndPos = 0 then
    begin
      Delete(Result, lStartPos, MaxInt);
      Break;
    end;
    Delete(Result, lStartPos, lEndPos - lStartPos + 2);
    Result := Trim(Result);
  until False;

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

class function TRemoveWithSymbolBuilder.IsAttributeLine(const aLine: string): Boolean;
begin
  Result := StartsText('[', Trim(aLine));
end;

class function TRemoveWithSymbolBuilder.IsConditionalDirectiveLine(const aLine: string): Boolean;
var
  lText: string;
begin
  lText := UpperCase(Trim(aLine));
  Result := StartsText('{$IF', lText) or StartsText('{$ELSE', lText) or StartsText('{$ELSEIF', lText) or
    StartsText('{$ENDIF', lText) or StartsText('{$IFEND', lText);
end;

class function TRemoveWithSymbolBuilder.IsConditionalStartDirective(const aLine: string): Boolean;
var
  lText: string;
begin
  lText := UpperCase(Trim(aLine));
  Result := StartsText('{$IF', lText) and (not StartsText('{$IFEND', lText));
end;

class function TRemoveWithSymbolBuilder.IsConditionalEndDirective(const aLine: string): Boolean;
var
  lText: string;
begin
  lText := UpperCase(Trim(aLine));
  Result := StartsText('{$ENDIF', lText) or StartsText('{$IFEND', lText);
end;

class function TRemoveWithSymbolBuilder.IsMultilineDeclarationStart(const aLine: string): Boolean;
var
  lText: string;
begin
  lText := Trim(aLine);
  Result := (Pos(',', lText) > 0) and (Pos(':', lText) = 0) and (Pos(';', lText) = 0) and
    (not IsRoutineStart(lText));
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

class function TRemoveWithSymbolBuilder.TryEnumValues(const aTypeText: string;
  out aNames: TArray<string>): Boolean;
var
  lClosePos: Integer;
  lEqualsPos: Integer;
  lList: TList<string>;
  lName: string;
  lOpenPos: Integer;
  lPart: string;
  lParts: TArray<string>;
  lPrefix: string;
  lRawPart: string;
  lText: string;
  i: Integer;
begin
  Result := False;
  SetLength(aNames, 0);
  lText := Trim(aTypeText);
  lEqualsPos := Pos('=', lText);
  lOpenPos := Pos('(', lText);
  lClosePos := PosEx(')', lText, lOpenPos + 1);
  if (lEqualsPos = 0) or (lOpenPos <= lEqualsPos) or (lClosePos <= lOpenPos) then
    Exit;

  lPrefix := Copy(lText, 1, lOpenPos - 1);
  if ContainsText(lPrefix, 'procedure') or ContainsText(lPrefix, 'function') then
    Exit;

  lList := TList<string>.Create;
  try
    lParts := Copy(lText, lOpenPos + 1, lClosePos - lOpenPos - 1).Split([',']);
    for lRawPart in lParts do
    begin
      lPart := Trim(lRawPart);
      lName := '';
      i := 1;
      while (i <= Length(lPart)) and IsIdentifierChar(lPart[i]) do
      begin
        lName := lName + lPart[i];
        Inc(i);
      end;
      if lName <> '' then
        lList.Add(lName);
    end;
    aNames := lList.ToArray;
    Result := Length(aNames) > 0;
  finally
    lList.Free;
  end;
end;

class function TRemoveWithSymbolBuilder.TryPropertyDeclaration(const aLine: string; out aName, aTypeName: string;
  out aIsDefault: Boolean): Boolean;
var
  lBracketDepth: Integer;
  lMemberText: string;
  lNameEnd: Integer;
  lPropertyTypeEnd: Integer;
  lTypePos: Integer;
  i: Integer;
begin
  Result := False;
  aName := '';
  aTypeName := '';
  aIsDefault := False;
  if not StartsText('property ', LowerCase(aLine)) then
    Exit;

  lMemberText := Trim(Copy(aLine, Length('property ') + 1, MaxInt));
  aIsDefault := ContainsText(LowerCase(lMemberText), ' default');
  lBracketDepth := 0;
  lTypePos := 0;
  for i := 1 to Length(lMemberText) do
  begin
    if lMemberText[i] = '[' then
      Inc(lBracketDepth)
    else if (lMemberText[i] = ']') and (lBracketDepth > 0) then
      Dec(lBracketDepth)
    else if (lMemberText[i] = ':') and (lBracketDepth = 0) then
    begin
      lTypePos := i;
      Break;
    end;
  end;

  if lTypePos > 0 then
  begin
    aTypeName := Trim(Copy(lMemberText, lTypePos + 1, MaxInt));
    lPropertyTypeEnd := Pos(' read ', LowerCase(aTypeName));
    if lPropertyTypeEnd = 0 then
      lPropertyTypeEnd := Pos(' write ', LowerCase(aTypeName));
    if lPropertyTypeEnd = 0 then
      lPropertyTypeEnd := Pos(' index ', LowerCase(aTypeName));
    if lPropertyTypeEnd = 0 then
      lPropertyTypeEnd := Pos(' default', LowerCase(aTypeName));
    if lPropertyTypeEnd = 0 then
      lPropertyTypeEnd := Pos(';', aTypeName);
    if lPropertyTypeEnd > 0 then
      aTypeName := Trim(Copy(aTypeName, 1, lPropertyTypeEnd - 1));
    lMemberText := Trim(Copy(lMemberText, 1, lTypePos - 1));
  end;

  lNameEnd := Pos('[', lMemberText);
  if lNameEnd = 0 then
    lNameEnd := Pos(';', lMemberText);
  if lNameEnd > 0 then
    aName := Trim(Copy(lMemberText, 1, lNameEnd - 1))
  else
    aName := Trim(lMemberText);
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

class function TRemoveWithSymbolBuilder.TryTypeStart(const aLine: string; out aName: string;
  out aCategory: TRemoveWithTypeCategory): Boolean;
var
  lEqualsPos: Integer;
  lLower: string;
begin
  Result := False;
  aName := '';
  aCategory := TRemoveWithTypeCategory.rwtcUnknown;
  lEqualsPos := Pos('=', aLine);
  if lEqualsPos = 0 then
    Exit;

  lLower := LowerCase(aLine);
  if (Pos(' record', lLower) = 0) and (Pos(' class', lLower) = 0) and (Pos(' interface', lLower) = 0) then
    Exit;

  if Pos(' record', lLower) > 0 then
    aCategory := TRemoveWithTypeCategory.rwtcRecord
  else if Pos(' interface', lLower) > 0 then
    aCategory := TRemoveWithTypeCategory.rwtcInterface
  else if Pos(' class', lLower) > 0 then
    aCategory := TRemoveWithTypeCategory.rwtcClass;

  aName := Trim(Copy(aLine, 1, lEqualsPos - 1));
  Result := aName <> '';
end;

class function TRemoveWithSymbolBuilder.TryVariantTagDeclaration(const aLine: string; out aName,
  aTypeName: string): Boolean;
var
  lColonPos: Integer;
  lOfPos: Integer;
  lRest: string;
  lRestLower: string;
  lText: string;
begin
  Result := False;
  aName := '';
  aTypeName := '';
  lText := Trim(aLine);
  if not StartsText('case ', LowerCase(lText)) then
    Exit;

  lRest := Trim(Copy(lText, Length('case ') + 1, MaxInt));
  lRestLower := LowerCase(lRest);
  lColonPos := Pos(':', lRest);
  lOfPos := Pos(' of', lRestLower);
  if (lColonPos = 0) or (lOfPos = 0) or (lOfPos < lColonPos) then
    Exit;

  aName := Trim(Copy(lRest, 1, lColonPos - 1));
  aTypeName := Trim(Copy(lRest, lColonPos + 1, lOfPos - lColonPos - 1));
  Result := (aName <> '') and (aTypeName <> '');
end;

class function TRemoveWithSymbolBuilder.VariantFieldDeclarationLine(const aLine: string): string;
var
  lInnerText: string;
  lOpenPos: Integer;
  lText: string;
begin
  Result := aLine;
  lText := Trim(aLine);
  lOpenPos := Pos('(', lText);
  if (lOpenPos > 1) and (Pos(':', Copy(lText, 1, lOpenPos - 1)) > 0) then
  begin
    lInnerText := Copy(lText, lOpenPos + 1, MaxInt);
    if Pos(':', lInnerText) > 0 then
      lText := Trim(Copy(lText, lOpenPos, MaxInt));
  end;
  if StartsText('(', lText) then
  begin
    lText := Trim(Copy(lText, 2, MaxInt));
    if EndsText(');', lText) then
      Result := Trim(Copy(lText, 1, Length(lText) - 2)) + ';'
    else if EndsText(')', lText) then
      Result := Trim(Copy(lText, 1, Length(lText) - 1)) + ';'
    else
      Result := lText;
  end else if EndsText(');', lText) then
    Result := Trim(Copy(lText, 1, Length(lText) - 2)) + ';';
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

class function TRemoveWithSymbolBuilder.TokenCount(const aText, aToken: string): Integer;
var
  lEndPos: Integer;
  lStartPos: Integer;
  i: Integer;
begin
  Result := 0;
  i := 1;
  while i <= Length(aText) do
  begin
    if not IsIdentifierChar(aText[i]) then
    begin
      Inc(i);
      Continue;
    end;
    lStartPos := i;
    while (i <= Length(aText)) and IsIdentifierChar(aText[i]) do
      Inc(i);
    lEndPos := i - 1;
    if SameText(Copy(aText, lStartPos, lEndPos - lStartPos + 1), aToken) then
      Inc(Result);
  end;
end;

class function TRemoveWithSymbolBuilder.EndTerminatedBlockOpenCount(const aText: string): Integer;
begin
  Result := TokenCount(aText, 'begin') + TokenCount(aText, 'case') + TokenCount(aText, 'try') +
    TokenCount(aText, 'asm');
end;

class function TRemoveWithSymbolBuilder.FindRoutineEndLine(const aLines: TArray<string>;
  const aStartIndex: Integer): Integer;
var
  lDepth: Integer;
  lLine: string;
  lNestedEndLine: Integer;
  lStarted: Boolean;
  i: Integer;
begin
  Result := 0;
  lDepth := 0;
  lStarted := False;
  i := aStartIndex + 1;
  while i <= High(aLines) do
  begin
    lLine := LowerCase(CleanLine(aLines[i]));
    if lLine = '' then
    begin
      Inc(i);
      Continue;
    end;
    if not lStarted then
    begin
      if IsTopLevelLine(aLines[i]) and (IsRoutineStart(lLine) or SameText(lLine, 'implementation') or
        SameText(lLine, 'interface')) then
        Exit(0);
      if IsRoutineStart(lLine) then
      begin
        lNestedEndLine := FindRoutineEndLine(aLines, i);
        if lNestedEndLine > 0 then
        begin
          i := lNestedEndLine;
          Continue;
        end;
      end;
      if EndTerminatedBlockOpenCount(lLine) = 0 then
      begin
        Inc(i);
        Continue;
      end;
      lStarted := True;
    end;
    Inc(lDepth, EndTerminatedBlockOpenCount(lLine));
    Dec(lDepth, TokenCount(lLine, 'end'));
    if lStarted and (lDepth <= 0) then
      Exit(i + 1);
    Inc(i);
  end;
end;

class function TRemoveWithSymbolBuilder.CollectDeclarationText(const aLines: TArray<string>;
  const aStartLine: Integer): string;
var
  lEndLine: Integer;
begin
  Result := CollectDeclarationText(aLines, aStartLine, lEndLine);
end;

class function TRemoveWithSymbolBuilder.CollectDeclarationText(const aLines: TArray<string>;
  const aStartLine: Integer; out aEndLine: Integer): string;
var
  lLine: string;
  lParenDepth: Integer;
  i: Integer;
  j: Integer;
begin
  Result := '';
  aEndLine := aStartLine;
  lParenDepth := 0;
  for i := aStartLine to High(aLines) do
  begin
    aEndLine := i;
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

class function TRemoveWithSymbolBuilder.UnsupportedReasonForTypeStart(const aTypeName, aPendingReason: string;
  const aConditionalDepth: Integer): string;
begin
  if aPendingReason <> '' then
    Exit(aPendingReason);
  if aConditionalDepth > 0 then
    Exit('unsupported-source-model-conditional-region');
  if Pos('<', aTypeName) > 0 then
    Exit('unsupported-source-model-generic-declaration');
  Result := '';
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

class function TRemoveWithSymbolBuilder.DecodeSourceText(const aBytes: TBytes): string;
var
  lOffset: Integer;
begin
  lOffset := 0;
  if (Length(aBytes) >= 3) and (aBytes[0] = $EF) and (aBytes[1] = $BB) and (aBytes[2] = $BF) then
    lOffset := 3;

  try
    Result := TEncoding.UTF8.GetString(aBytes, lOffset, Length(aBytes) - lOffset);
  except
    on E: EEncodingError do
      Result := TEncoding.Default.GetString(aBytes, lOffset, Length(aBytes) - lOffset);
  end;
end;

class function TRemoveWithSymbolBuilder.ReadSourceLines(const aFilePath: string): TArray<string>;
var
  i: Integer;
  lLines: TStringList;
  lText: string;
begin
  lText := DecodeSourceText(TFile.ReadAllBytes(aFilePath));
  lLines := TStringList.Create;
  try
    lLines.Text := lText;
    SetLength(Result, lLines.Count);
    for i := 0 to lLines.Count - 1 do
      Result[i] := lLines[i];
  finally
    lLines.Free;
  end;
end;

class function TRemoveWithSymbolBuilder.SameSymbol(const aLeft, aRight: TRemoveWithSymbolInfo): Boolean;
begin
  Result := (aLeft.fKind = aRight.fKind) and SameText(aLeft.fName, aRight.fName) and
    SameText(aLeft.fTypeName, aRight.fTypeName) and SameText(aLeft.fOwnerType, aRight.fOwnerType) and
    SameText(aLeft.fSourceOwnerType, aRight.fSourceOwnerType) and
    SameText(aLeft.fRelatedTypeName, aRight.fRelatedTypeName) and
    SameText(aLeft.fRoutineName, aRight.fRoutineName) and SameText(aLeft.fUnitName, aRight.fUnitName) and
    SameText(aLeft.fFilePath, aRight.fFilePath) and (aLeft.fLine = aRight.fLine) and
    (aLeft.fColumn = aRight.fColumn) and (aLeft.fIsHelper = aRight.fIsHelper) and
    (aLeft.fIsOverride = aRight.fIsOverride) and (aLeft.fIsDefault = aRight.fIsDefault) and
    (aLeft.fTypeCategory = aRight.fTypeCategory) and
    SameText(aLeft.fUnsupportedReason, aRight.fUnsupportedReason);
end;

class function TRemoveWithSymbolBuilder.SymbolIdentityKey(const aSymbol: TRemoveWithSymbolInfo): string;
const
  cSeparator = #31;
begin
  Result := IntToStr(Ord(aSymbol.fKind)) + cSeparator + aSymbol.fName + cSeparator + aSymbol.fTypeName +
    cSeparator + aSymbol.fOwnerType + cSeparator + aSymbol.fSourceOwnerType + cSeparator +
    aSymbol.fRelatedTypeName + cSeparator + aSymbol.fRoutineName + cSeparator + aSymbol.fUnitName +
    cSeparator + aSymbol.fFilePath + cSeparator + IntToStr(aSymbol.fLine) + cSeparator +
    IntToStr(aSymbol.fColumn) + cSeparator + IntToStr(Ord(aSymbol.fIsHelper)) + cSeparator +
    IntToStr(Ord(aSymbol.fIsOverride)) + cSeparator + IntToStr(Ord(aSymbol.fIsDefault)) + cSeparator +
    IntToStr(Ord(aSymbol.fTypeCategory)) + cSeparator + aSymbol.fUnsupportedReason;
end;

class procedure TRemoveWithSymbolBuilder.AddSymbol(var aInventory: TRemoveWithSymbolInventory;
  const aSymbol: TRemoveWithSymbolInfo);
var
  lIndex: Integer;
  lKey: string;
  lSymbol: TRemoveWithSymbolInfo;
begin
  if GRemoveWithSymbolKeys <> nil then
  begin
    lKey := SymbolIdentityKey(aSymbol);
    if GRemoveWithSymbolKeys.ContainsKey(lKey) then
      Exit;
    GRemoveWithSymbolKeys.Add(lKey, 1);
  end else
  begin
    for lSymbol in aInventory.fSymbols do
    begin
      if SameSymbol(lSymbol, aSymbol) then
        Exit;
    end;
  end;

  lIndex := Length(aInventory.fSymbols);
  SetLength(aInventory.fSymbols, lIndex + 1);
  aInventory.fSymbols[lIndex] := aSymbol;
end;

class procedure TRemoveWithSymbolBuilder.MarkTypeUnsupported(var aInventory: TRemoveWithSymbolInventory;
  const aTypeName, aReason: string);
var
  i: Integer;
  lKey: string;
  lSymbol: TRemoveWithSymbolInfo;
  lTypeName: string;
begin
  if aReason = '' then
    Exit;
  lTypeName := SimpleTypeName(aTypeName);
  for i := 0 to High(aInventory.fSymbols) do
  begin
    if (aInventory.fSymbols[i].fKind = TRemoveWithSymbolKind.rwskTypeMember) and
      SameText(aInventory.fSymbols[i].fName, lTypeName) then
    begin
      if aInventory.fSymbols[i].fUnsupportedReason = '' then
      begin
        lSymbol := aInventory.fSymbols[i];
        if GRemoveWithSymbolKeys <> nil then
          GRemoveWithSymbolKeys.Remove(SymbolIdentityKey(lSymbol));
        aInventory.fSymbols[i].fUnsupportedReason := aReason;
        if GRemoveWithSymbolKeys <> nil then
        begin
          lKey := SymbolIdentityKey(aInventory.fSymbols[i]);
          if not GRemoveWithSymbolKeys.ContainsKey(lKey) then
            GRemoveWithSymbolKeys.Add(lKey, 1);
        end;
      end;
      Exit;
    end;
  end;
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
  lConstName: string;
  lDeclaration: string;
  lDeclarationLine: Integer;
  lInConst: Boolean;
  lInVar: Boolean;
  lLine: string;
  lNames: TArray<string>;
  lTypeName: string;
  i: Integer;
begin
  lDeclaration := '';
  lDeclarationLine := 0;
  lInConst := False;
  lInVar := False;
  for i := aStartLine to High(aLines) do
  begin
    lLine := CleanLine(aLines[i]);
    if SameText(lLine, 'const') then
    begin
      lInConst := True;
      lInVar := False;
      Continue;
    end;
    if SameText(lLine, 'var') then
    begin
      lInConst := False;
      lInVar := True;
      Continue;
    end;
    if SameText(lLine, 'begin') then
      Exit;
    if StartsText('const ', LowerCase(lLine)) then
    begin
      lInConst := True;
      lInVar := False;
      lLine := Trim(Copy(lLine, Length('const ') + 1, MaxInt));
    end;
    if lInConst and (lLine <> '') and TryConstDeclaration(lLine, lConstName, lTypeName) then
    begin
      AddNamedSymbols(aInventory, [lConstName], lTypeName, '', aRoutineName, aUnitName, aFilePath, i + 1,
        aLines[i], TRemoveWithSymbolKind.rwskConstant);
      Continue;
    end;
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
  lConditionalDepth: Integer;
  lConstName: string;
  lCurrentType: string;
  lCurrentTypeUnsupportedReason: string;
  lDeclaration: string;
  lDeclarationAdded: Boolean;
  lDeclarationParts: TArray<string>;
  lEnumNames: TArray<string>;
  lInClassVar: Boolean;
  lInConst: Boolean;
  lInTypeSection: Boolean;
  lLine: string;
  lLower: string;
  lMemberName: string;
  lNames: TArray<string>;
  lPendingUnsupportedReason: string;
  lPropertyType: string;
  lRawLine: string;
  lRawDeclaration: string;
  lRelatedTypeName: string;
  lRawTypeName: string;
  lTypeText: string;
  lTypeSymbol: TRemoveWithSymbolInfo;
  lTypeCategory: TRemoveWithTypeCategory;
  lTopLevelLine: Boolean;
  lTypeIsHelper: Boolean;
  lPropertyIsDefault: Boolean;
  lTypeName: string;
  lCollectedEndLine: Integer;
  lSkipUntilLine: Integer;
  i: Integer;
begin
  lConditionalDepth := 0;
  lCurrentType := '';
  lCurrentTypeUnsupportedReason := '';
  lInClassVar := False;
  lInConst := False;
  lInTypeSection := False;
  lPendingUnsupportedReason := '';
  lSkipUntilLine := 0;
  for i := 0 to High(aLines) do
  begin
    if i < lSkipUntilLine then
      Continue;
    lRawLine := aLines[i];
    lLine := CleanLine(lRawLine);
    lLower := LowerCase(lLine);
    if lLine = '' then
      Continue;
    lTopLevelLine := IsTopLevelLine(lRawLine);

    if IsConditionalDirectiveLine(lLine) then
    begin
      if lCurrentType <> '' then
      begin
        lCurrentTypeUnsupportedReason := 'unsupported-source-model-conditional-region';
        MarkTypeUnsupported(aInventory, lCurrentType, lCurrentTypeUnsupportedReason);
      end else if lInTypeSection and (not IsConditionalEndDirective(lLine)) then
        lPendingUnsupportedReason := 'unsupported-source-model-conditional-region';

      if IsConditionalStartDirective(lLine) then
        Inc(lConditionalDepth)
      else if IsConditionalEndDirective(lLine) and (lConditionalDepth > 0) then
        Dec(lConditionalDepth);
      Continue;
    end;

    if IsAttributeLine(lLine) then
    begin
      if lCurrentType <> '' then
      begin
        lCurrentTypeUnsupportedReason := 'unsupported-source-model-attribute';
        MarkTypeUnsupported(aInventory, lCurrentType, lCurrentTypeUnsupportedReason);
      end else if lInTypeSection then
        lPendingUnsupportedReason := 'unsupported-source-model-attribute';
      Continue;
    end;

    if lTopLevelLine and SameText(lLine, 'type') then
    begin
      lConditionalDepth := 0;
      lInTypeSection := True;
      Continue;
    end;
    if lTopLevelLine and (SameText(lLine, 'implementation') or SameText(lLine, 'const') or
      SameText(lLine, 'var') or SameText(lLine, 'threadvar') or IsRoutineStart(lLine)) then
    begin
      lCurrentType := '';
      lCurrentTypeUnsupportedReason := '';
      lInTypeSection := False;
      lInClassVar := False;
      lInConst := False;
      lPendingUnsupportedReason := '';
      Continue;
    end;

    if lCurrentType = '' then
    begin
      if not lInTypeSection then
        Continue;
      lTypeText := CollectTypeStartText(aLines, i);
      if TryTypeStart(lTypeText, lRawTypeName, lTypeCategory) then
      begin
        lCurrentType := SimpleTypeName(lRawTypeName);
        lCurrentTypeUnsupportedReason := UnsupportedReasonForTypeStart(lRawTypeName, lPendingUnsupportedReason,
          lConditionalDepth);
        lInClassVar := False;
        lInConst := False;
        TryTypeRelation(lTypeText, lRelatedTypeName, lTypeIsHelper);
        lTypeSymbol := Default(TRemoveWithSymbolInfo);
        lTypeSymbol.fName := lCurrentType;
        lTypeSymbol.fRelatedTypeName := lRelatedTypeName;
        lTypeSymbol.fIsHelper := lTypeIsHelper;
        lTypeSymbol.fTypeCategory := lTypeCategory;
        lTypeSymbol.fUnitName := aUnitName;
        lTypeSymbol.fFilePath := aFilePath;
        lTypeSymbol.fLine := i + 1;
        lTypeSymbol.fColumn := FindColumn(aLines[i], lCurrentType);
        lTypeSymbol.fUnsupportedReason := lCurrentTypeUnsupportedReason;
        lTypeSymbol.fKind := TRemoveWithSymbolKind.rwskTypeMember;
        AddSymbol(aInventory, lTypeSymbol);
        if TryEnumValues(lTypeText, lEnumNames) then
          AddNamedSymbols(aInventory, lEnumNames, lCurrentType, '', '', aUnitName, aFilePath, i + 1, aLines[i],
            TRemoveWithSymbolKind.rwskConstant);
        lPendingUnsupportedReason := '';
      end else if TryTypeAlias(lTypeText, lMemberName, lTypeName) then
      begin
        AddNamedSymbols(aInventory, [lMemberName], lTypeName, '', '', aUnitName, aFilePath, i + 1, aLines[i],
          TRemoveWithSymbolKind.rwskTypeMember);
        if TryEnumValues(lTypeText, lEnumNames) then
          AddNamedSymbols(aInventory, lEnumNames, lMemberName, '', '', aUnitName, aFilePath, i + 1, aLines[i],
            TRemoveWithSymbolKind.rwskConstant);
        lPendingUnsupportedReason := '';
      end;
      Continue;
    end;

    if SameText(lLine, 'end;') or SameText(lLine, 'end') then
    begin
      lCurrentType := '';
      lCurrentTypeUnsupportedReason := '';
      Continue;
    end;
    if IsVisibilityLine(lLine) then
      Continue;
    if SameText(lLine, 'type') then
    begin
      lCurrentTypeUnsupportedReason := 'unsupported-source-model-nested-type';
      MarkTypeUnsupported(aInventory, lCurrentType, lCurrentTypeUnsupportedReason);
      Continue;
    end;
    if IsMultilineDeclarationStart(lLine) then
    begin
      lLine := CollectDeclarationText(aLines, i, lCollectedEndLine);
      lSkipUntilLine := lCollectedEndLine + 1;
    end;
    if lCurrentTypeUnsupportedReason <> '' then
      Continue;
    lLine := VariantFieldDeclarationLine(lLine);
    lLower := LowerCase(lLine);
    if TryVariantTagDeclaration(lLine, lMemberName, lTypeName) then
    begin
      AddNamedSymbols(aInventory, [lMemberName], lTypeName, lCurrentType, '', aUnitName, aFilePath, i + 1,
        aLines[i], TRemoveWithSymbolKind.rwskField);
      Continue;
    end;
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

    if TryPropertyDeclaration(lLine, lMemberName, lPropertyType, lPropertyIsDefault) then
    begin
      lTypeSymbol := Default(TRemoveWithSymbolInfo);
      lTypeSymbol.fName := lMemberName;
      lTypeSymbol.fTypeName := lPropertyType;
      lTypeSymbol.fOwnerType := lCurrentType;
      lTypeSymbol.fUnitName := aUnitName;
      lTypeSymbol.fFilePath := aFilePath;
      lTypeSymbol.fLine := i + 1;
      lTypeSymbol.fColumn := FindColumn(aLines[i], lMemberName);
      lTypeSymbol.fIsDefault := lPropertyIsDefault;
      lTypeSymbol.fKind := TRemoveWithSymbolKind.rwskProperty;
      AddSymbol(aInventory, lTypeSymbol);
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

    lDeclarationAdded := False;
    lDeclarationParts := lLine.Split([';']);
    for lRawDeclaration in lDeclarationParts do
    begin
      lDeclaration := Trim(lRawDeclaration);
      if lDeclaration = '' then
        Continue;
      if not TryDeclaration(lDeclaration + ';', lNames, lTypeName) then
        Continue;

      if lInClassVar then
        AddNamedSymbols(aInventory, lNames, lTypeName, lCurrentType, '', aUnitName, aFilePath, i + 1, aLines[i],
          TRemoveWithSymbolKind.rwskClassVar)
      else
        AddNamedSymbols(aInventory, lNames, lTypeName, lCurrentType, '', aUnitName, aFilePath, i + 1, aLines[i],
          TRemoveWithSymbolKind.rwskField);
      lDeclarationAdded := True;
    end;
    if lDeclarationAdded then
      Continue;

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
  lInType: Boolean;
  lInVar: Boolean;
  lLine: string;
  lNames: TArray<string>;
  lRawLine: string;
  lRoutineEndLine: Integer;
  lTopLevelLine: Boolean;
  lTypeName: string;
  i: Integer;
begin
  lInConst := False;
  lInType := False;
  lInVar := False;
  i := 0;
  while i <= High(aLines) do
  begin
    try
      lRawLine := aLines[i];
      lLine := CleanLine(lRawLine);
      if lLine = '' then
        Continue;
      lTopLevelLine := IsTopLevelLine(lRawLine);

      if lTopLevelLine and SameText(lLine, 'implementation') then
      begin
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
        lInVar := False;
        lInConst := False;
        lRoutineEndLine := FindRoutineEndLine(aLines, i);
        if lRoutineEndLine > 0 then
          i := lRoutineEndLine - 1;
        Continue;
      end;

      if lInVar and TryDeclaration(lLine, lNames, lTypeName) then
        AddNamedSymbols(aInventory, lNames, lTypeName, '', '', aUnitName, aFilePath, i + 1, aLines[i],
          TRemoveWithSymbolKind.rwskUnitGlobal)
      else if lInConst and TryConstDeclaration(lLine, lConstName, lTypeName) then
        AddNamedSymbols(aInventory, [lConstName], lTypeName, '', '', aUnitName, aFilePath, i + 1, aLines[i],
          TRemoveWithSymbolKind.rwskConstant);
    finally
      Inc(i);
    end;
  end;
end;

class procedure TRemoveWithSymbolBuilder.ParseRoutines(var aInventory: TRemoveWithSymbolInventory;
  const aLines: TArray<string>; const aUnitName, aFilePath: string);
var
  lInImplementation: Boolean;
  lInType: Boolean;
  lMember: TRemoveWithSymbolInfo;
  lMemberCount: Integer;
  lLine: string;
  lOwnerType: string;
  lRawLine: string;
  lRoutine: TRemoveWithSymbolInfo;
  lRoutineName: string;
  lSignature: string;
  lTopLevelLine: Boolean;
  i: Integer;
  j: Integer;
begin
  lInImplementation := False;
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
      begin
        lInImplementation := True;
        Continue;
      end;
    end;
    if lInImplementation and lTopLevelLine and IsRoutineStart(lLine) then
      lInType := False;
    if lInType then
      Continue;

    if (not lTopLevelLine) and (not IsRoutineStart(lLine)) then
      Continue;
    lSignature := CollectDeclarationText(aLines, i);
    if not TryRoutineName(lSignature, lRoutineName) then
      Continue;

    lRoutine := Default(TRemoveWithSymbolInfo);
    lRoutine.fName := lRoutineName;
    lRoutine.fUnitName := aUnitName;
    lRoutine.fFilePath := aFilePath;
    lRoutine.fLine := i + 1;
    lRoutine.fEndLine := FindRoutineEndLine(aLines, i);
    if lRoutine.fEndLine = 0 then
      Continue;
    lRoutine.fColumn := FindColumn(aLines[i], lRoutineName);
    lRoutine.fKind := TRemoveWithSymbolKind.rwskRoutine;
    AddSymbol(aInventory, lRoutine);
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
        (lTypeSymbol.fRelatedTypeName = '') or (lTypeSymbol.fUnsupportedReason <> '') then
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
  lMembers: TList<TRemoveWithSymbolInfo>;
  lMembersByOwner: TDictionary<string, TList<TRemoveWithSymbolInfo>>;
  lPair: TPair<string, TList<TRemoveWithSymbolInfo>>;
  lSymbol: TRemoveWithSymbolInfo;
  lSymbolCount: Integer;
  i: Integer;
begin
  lSymbolCount := Length(aInventory.fSymbols);
  lMembersByOwner := TDictionary<string, TList<TRemoveWithSymbolInfo>>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    for i := 0 to lSymbolCount - 1 do
    begin
      lMember := aInventory.fSymbols[i];
      if (lMember.fOwnerType = '') or (lMember.fRoutineName <> '') or (not IsDirectMemberKind(lMember.fKind)) then
        Continue;
      if not lMembersByOwner.TryGetValue(lMember.fOwnerType, lMembers) then
      begin
        lMembers := TList<TRemoveWithSymbolInfo>.Create;
        lMembersByOwner.Add(lMember.fOwnerType, lMembers);
      end;
      lMembers.Add(lMember);
    end;

    for i := 0 to lSymbolCount - 1 do
    begin
      lCurrentMember := aInventory.fSymbols[i];
      if (lCurrentMember.fKind <> TRemoveWithSymbolKind.rwskCurrentClassMember) or
        (lCurrentMember.fOwnerType = '') or (lCurrentMember.fRoutineName = '') then
        Continue;
      if not lMembersByOwner.TryGetValue(lCurrentMember.fOwnerType, lMembers) then
        Continue;

      for lMember in lMembers do
      begin
        lSymbol := lMember;
        lSymbol.fKind := TRemoveWithSymbolKind.rwskCurrentClassMember;
        lSymbol.fRoutineName := lCurrentMember.fRoutineName;
        AddSymbol(aInventory, lSymbol);
      end;
    end;
  finally
    for lPair in lMembersByOwner do
      lPair.Value.Free;
    lMembersByOwner.Free;
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

  lLines := ReadSourceLines(aFilePath);
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

        lLines := ReadSourceLines(lSourceSymbol.fFilePath);
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
  lModel: TRemoveWithProjectModel;
begin
  lModel := nil;
  if not BuildRemoveWithProjectModel(aOptions, aOptions.fDprojPath, lModel, aError) then
    Exit(False);
  try
    Result := BuildRemoveWithSymbolInventory(aOptions, lModel, aInventory, aError);
    aInventory.fSemanticIndex := nil;
  finally
    lModel.Free;
  end;
end;

function BuildRemoveWithSymbolInventory(const aOptions: TAppOptions; const aProjectModel: TRemoveWithProjectModel;
  out aInventory: TRemoveWithSymbolInventory; out aError: string): Boolean;
var
  lProblem: TProjectIndexer.TProblemInfo;
  lSymbolKeys: TDictionary<string, Byte>;
  lStopwatch: TStopwatch;
  lSymbol: TRemoveWithSymbolInfo;
  lUnitIndex: Integer;
  lUnitModel: TRemoveWithUnitModel;
begin
  aInventory := Default(TRemoveWithSymbolInventory);
  aError := '';

  if not Assigned(aProjectModel) then
  begin
    aError := 'Remove-with project model is not assigned.';
    Exit(False);
  end;
  aInventory.fSemanticIndex := aProjectModel.SemanticIndex;
  aInventory.fParserDefines := aProjectModel.Context.fParserDefines;
  BuildDelphiSemanticBindings(aProjectModel, aInventory);

  lSymbolKeys := TDictionary<string, Byte>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    GRemoveWithSymbolKeys := lSymbolKeys;
    lUnitIndex := 0;
    for lUnitModel in aProjectModel.UnitModels do
    begin
      if (Trim(lUnitModel.fFilePath) = '') or (not SameText(TPath.GetExtension(lUnitModel.fFilePath), '.pas')) then
        Continue;
      Inc(lUnitIndex);
      LogRemoveWithSymbolProgress(aOptions, Format('model-unit start index=%d unit=%s path=%s',
        [lUnitIndex, lUnitModel.fUnitName, lUnitModel.fFilePath]));
      lStopwatch := TStopwatch.StartNew;
      if TFile.Exists(lUnitModel.fFilePath) then
        TRemoveWithSymbolBuilder.ParseUnit(aInventory, lUnitModel.fUnitName, lUnitModel.fFilePath);
      lStopwatch.Stop;
      LogRemoveWithSymbolProgress(aOptions, Format('model-unit done index=%d elapsedMs=%d symbols=%d',
        [lUnitIndex, lStopwatch.ElapsedMilliseconds, Length(aInventory.fSymbols)]));
    end;

    LogRemoveWithSymbolProgress(aOptions, 'related-type-members start');
    lStopwatch := TStopwatch.StartNew;
    TRemoveWithSymbolBuilder.AddRelatedTypeMemberSymbols(aInventory);
    lStopwatch.Stop;
    LogRemoveWithSymbolProgress(aOptions, Format('related-type-members done elapsedMs=%d symbols=%d',
      [lStopwatch.ElapsedMilliseconds, Length(aInventory.fSymbols)]));

    LogRemoveWithSymbolProgress(aOptions, 'current-class-members start');
    lStopwatch := TStopwatch.StartNew;
    TRemoveWithSymbolBuilder.AddRelatedCurrentClassSymbols(aInventory);
    lStopwatch.Stop;
    LogRemoveWithSymbolProgress(aOptions, Format('current-class-members done elapsedMs=%d symbols=%d',
      [lStopwatch.ElapsedMilliseconds, Length(aInventory.fSymbols)]));

    LogRemoveWithSymbolProgress(aOptions, 'external-units start');
    lStopwatch := TStopwatch.StartNew;
    TRemoveWithSymbolBuilder.AddExternalUnitSymbols(aInventory);
    lStopwatch.Stop;
    LogRemoveWithSymbolProgress(aOptions, Format('external-units done elapsedMs=%d symbols=%d',
      [lStopwatch.ElapsedMilliseconds, Length(aInventory.fSymbols)]));

    LogRemoveWithSymbolProgress(aOptions, 'external-types start');
    lStopwatch := TStopwatch.StartNew;
    TRemoveWithSymbolBuilder.AddExternalTypeSymbols(aInventory);
    lStopwatch.Stop;
    LogRemoveWithSymbolProgress(aOptions, Format('external-types done elapsedMs=%d symbols=%d',
      [lStopwatch.ElapsedMilliseconds, Length(aInventory.fSymbols)]));

    for lProblem in aProjectModel.Indexer.Problems do
    begin
      lSymbol := Default(TRemoveWithSymbolInfo);
      lSymbol.fName := TPath.GetFileNameWithoutExtension(lProblem.FileName);
      lSymbol.fFilePath := lProblem.FileName;
      lSymbol.fKind := TRemoveWithSymbolKind.rwskExternal;
      TRemoveWithSymbolBuilder.AddSymbol(aInventory, lSymbol);
    end;
  finally
    GRemoveWithSymbolKeys := nil;
    lSymbolKeys.Free;
  end;
  Result := True;
end;

end.
