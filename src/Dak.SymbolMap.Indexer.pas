unit Dak.SymbolMap.Indexer;

interface

uses
  DelphiSemantics.Model;

type
  TSymbolMapUnitUse = record
    fUnitName: string;
    fSectionKind: string;
    fLine: Integer;
    fCol: Integer;
  end;

  TSymbolMapSymbolModel = record
    fName: string;
    fKind: string;
    fUnitName: string;
    fFilePath: string;
    fOwnerName: string;
    fTypeName: string;
    fSignature: string;
    fSectionKind: string;
    fLine: Integer;
    fCol: Integer;
    fEndLine: Integer;
    fEndCol: Integer;
  end;

  TSymbolMapMemberModel = record
    fOwnerName: string;
    fMemberName: string;
    fKind: string;
    fTypeName: string;
    fVisibility: string;
    fSignature: string;
    fIsDefault: Boolean;
    fIsIndexed: Boolean;
    fLine: Integer;
    fCol: Integer;
    fEndLine: Integer;
    fEndCol: Integer;
  end;

  TSymbolMapReferenceModel = record
    fName: string;
    fSectionKind: string;
    fRole: string;
    fLine: Integer;
    fCol: Integer;
    fEndLine: Integer;
    fEndCol: Integer;
  end;

  TSymbolMapUnitModel = record
    fUnitName: string;
    fFilePath: string;
    fEncodingName: string;
    fUses: TArray<TSymbolMapUnitUse>;
    fSymbols: TArray<TSymbolMapSymbolModel>;
    fMembers: TArray<TSymbolMapMemberModel>;
    fReferences: TArray<TSymbolMapReferenceModel>;
    fDiagnostics: TArray<string>;
  end;

function TryLoadSymbolMapSourceFile(const aFilePath: string; out aText, aEncodingName, aError: string): Boolean;
function SymbolMapUnitModelFromDelphiSemanticModel(const aSemanticModel: TDelphiSemanticUnitModel):
  TSymbolMapUnitModel;
function TryExtractSymbolMapUnitModel(const aFilePath: string; out aModel: TSymbolMapUnitModel;
  out aError: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.StrUtils, System.SysUtils,
  maxLogic.StrUtils;

type
  TSymbolMapTokenKind = (smtIdentifier, smtDot, smtComma, smtSemicolon, smtColon, smtEqual, smtLParen, smtRParen,
    smtLBracket, smtRBracket);

  TSymbolMapToken = record
    fKind: TSymbolMapTokenKind;
    fText: string;
    fLine: Integer;
    fCol: Integer;
    fOffset: Integer;
    fEndOffset: Integer;
  end;

function IsIdentifierStart(const aChar: Char): Boolean;
begin
  Result := ((aChar >= 'A') and (aChar <= 'Z')) or ((aChar >= 'a') and (aChar <= 'z')) or (aChar = '_');
end;

function IsIdentifierChar(const aChar: Char): Boolean;
begin
  Result := IsIdentifierStart(aChar) or ((aChar >= '0') and (aChar <= '9'));
end;

function IsValidUtf8(const aBytes: TBytes; const aOffset, aCount: Integer): Boolean;
var
  lByte: Byte;
  lEndIndex: Integer;
  lFirstFollow: Byte;
  lFollow: Byte;
  lFollowIndex: Integer;
  lIndex: Integer;
  lNeed: Integer;
begin
  Result := False;
  lIndex := aOffset;
  lEndIndex := aOffset + aCount;
  while lIndex < lEndIndex do
  begin
    lByte := aBytes[lIndex];
    if lByte < $80 then
    begin
      Inc(lIndex);
      Continue;
    end;

    if (lByte >= $C2) and (lByte <= $DF) then
      lNeed := 1
    else
    begin
      if (lByte >= $E0) and (lByte <= $EF) then
        lNeed := 2
      else if (lByte >= $F0) and (lByte <= $F4) then
        lNeed := 3
      else
        Exit(False);
    end;

    if lIndex + lNeed >= lEndIndex then
      Exit(False);

    lFirstFollow := aBytes[lIndex + 1];
    if (lFirstFollow < $80) or (lFirstFollow > $BF) then
      Exit(False);
    case lByte of
      $E0:
        if lFirstFollow < $A0 then
          Exit(False);
      $ED:
        if lFirstFollow > $9F then
          Exit(False);
      $F0:
        if lFirstFollow < $90 then
          Exit(False);
      $F4:
        if lFirstFollow > $8F then
          Exit(False);
    end;

    for lFollowIndex := 2 to lNeed do
    begin
      lFollow := aBytes[lIndex + lFollowIndex];
      if (lFollow < $80) or (lFollow > $BF) then
        Exit(False);
    end;
    Inc(lIndex, lNeed + 1);
  end;
  Result := True;
end;

function TryLoadSymbolMapSourceFile(const aFilePath: string; out aText, aEncodingName, aError: string): Boolean;
var
  lBodyLength: Integer;
  lBytes: TBytes;
  lOffset: Integer;
begin
  Result := False;
  aText := '';
  aEncodingName := '';
  aError := '';
  try
    if not TFile.Exists(aFilePath) then
    begin
      aError := 'File not found: ' + aFilePath;
      Exit(False);
    end;

    lBytes := TFile.ReadAllBytes(aFilePath);
    lOffset := 0;
    if (Length(lBytes) >= 3) and (lBytes[0] = $EF) and (lBytes[1] = $BB) and (lBytes[2] = $BF) then
      lOffset := 3;
    lBodyLength := Length(lBytes) - lOffset;

    if IsValidUtf8(lBytes, lOffset, lBodyLength) then
    begin
      aText := TEncoding.UTF8.GetString(lBytes, lOffset, lBodyLength);
      aEncodingName := 'utf-8';
    end else begin
      aText := TEncoding.Default.GetString(lBytes, lOffset, lBodyLength);
      aEncodingName := 'ansi';
    end;
    Result := True;
  except
    on E: Exception do
      aError := E.Message;
  end;
end;

procedure AdvanceChar(const aText: string; var aIndex, aLine, aCol: Integer);
begin
  if aText[aIndex] = #13 then
  begin
    Inc(aIndex);
    if (aIndex <= Length(aText)) and (aText[aIndex] = #10) then
      Inc(aIndex);
    Inc(aLine);
    aCol := 1;
  end else if aText[aIndex] = #10 then
  begin
    Inc(aIndex);
    Inc(aLine);
    aCol := 1;
  end else begin
    Inc(aIndex);
    Inc(aCol);
  end;
end;

procedure AddToken(var aTokens: TArray<TSymbolMapToken>; const aKind: TSymbolMapTokenKind; const aText: string;
  const aLine, aCol, aOffset, aEndOffset: Integer);
var
  lIndex: Integer;
begin
  lIndex := Length(aTokens);
  SetLength(aTokens, lIndex + 1);
  aTokens[lIndex].fKind := aKind;
  aTokens[lIndex].fText := aText;
  aTokens[lIndex].fLine := aLine;
  aTokens[lIndex].fCol := aCol;
  aTokens[lIndex].fOffset := aOffset;
  aTokens[lIndex].fEndOffset := aEndOffset;
end;

procedure TokenizeSource(const aText: string; out aTokens: TArray<TSymbolMapToken>);
var
  lChar: Char;
  lCol: Integer;
  lIndex: Integer;
  lLine: Integer;
  lStart: Integer;
  lStartCol: Integer;
begin
  SetLength(aTokens, 0);
  lIndex := 1;
  lLine := 1;
  lCol := 1;
  while lIndex <= Length(aText) do
  begin
    lChar := aText[lIndex];
    if lChar <= ' ' then
    begin
      AdvanceChar(aText, lIndex, lLine, lCol);
      Continue;
    end;

    if (lChar = '/') and (lIndex < Length(aText)) and (aText[lIndex + 1] = '/') then
    begin
      while (lIndex <= Length(aText)) and not (aText[lIndex] in [#10, #13]) do
        AdvanceChar(aText, lIndex, lLine, lCol);
      Continue;
    end;

    if lChar = '{' then
    begin
      while (lIndex <= Length(aText)) and (aText[lIndex] <> '}') do
        AdvanceChar(aText, lIndex, lLine, lCol);
      if lIndex <= Length(aText) then
        AdvanceChar(aText, lIndex, lLine, lCol);
      Continue;
    end;

    if (lChar = '(') and (lIndex < Length(aText)) and (aText[lIndex + 1] = '*') then
    begin
      AdvanceChar(aText, lIndex, lLine, lCol);
      AdvanceChar(aText, lIndex, lLine, lCol);
      while lIndex <= Length(aText) do
      begin
        if (aText[lIndex] = '*') and (lIndex < Length(aText)) and (aText[lIndex + 1] = ')') then
        begin
          AdvanceChar(aText, lIndex, lLine, lCol);
          AdvanceChar(aText, lIndex, lLine, lCol);
          Break;
        end;
        AdvanceChar(aText, lIndex, lLine, lCol);
      end;
      Continue;
    end;

    if lChar = '''' then
    begin
      AdvanceChar(aText, lIndex, lLine, lCol);
      while lIndex <= Length(aText) do
      begin
        if aText[lIndex] = '''' then
        begin
          AdvanceChar(aText, lIndex, lLine, lCol);
          if (lIndex <= Length(aText)) and (aText[lIndex] = '''') then
          begin
            AdvanceChar(aText, lIndex, lLine, lCol);
            Continue;
          end;
          Break;
        end;
        AdvanceChar(aText, lIndex, lLine, lCol);
      end;
      Continue;
    end;

    if IsIdentifierStart(lChar) then
    begin
      lStart := lIndex;
      lStartCol := lCol;
      while (lIndex <= Length(aText)) and IsIdentifierChar(aText[lIndex]) do
        AdvanceChar(aText, lIndex, lLine, lCol);
      AddToken(aTokens, smtIdentifier, Copy(aText, lStart, lIndex - lStart), lLine, lStartCol, lStart,
        lIndex - 1);
      Continue;
    end;

    case lChar of
      '.':
        AddToken(aTokens, smtDot, lChar, lLine, lCol, lIndex, lIndex);
      ',':
        AddToken(aTokens, smtComma, lChar, lLine, lCol, lIndex, lIndex);
      ';':
        AddToken(aTokens, smtSemicolon, lChar, lLine, lCol, lIndex, lIndex);
      ':':
        AddToken(aTokens, smtColon, lChar, lLine, lCol, lIndex, lIndex);
      '=':
        AddToken(aTokens, smtEqual, lChar, lLine, lCol, lIndex, lIndex);
      '(':
        AddToken(aTokens, smtLParen, lChar, lLine, lCol, lIndex, lIndex);
      ')':
        AddToken(aTokens, smtRParen, lChar, lLine, lCol, lIndex, lIndex);
      '[':
        AddToken(aTokens, smtLBracket, lChar, lLine, lCol, lIndex, lIndex);
      ']':
        AddToken(aTokens, smtRBracket, lChar, lLine, lCol, lIndex, lIndex);
    end;
    AdvanceChar(aText, lIndex, lLine, lCol);
  end;
end;

procedure AddUse(var aModel: TSymbolMapUnitModel; const aUnitName, aSectionKind: string; const aLine, aCol: Integer);
var
  lIndex: Integer;
begin
  if (aUnitName = '') or (aSectionKind = '') then
    Exit;
  lIndex := Length(aModel.fUses);
  SetLength(aModel.fUses, lIndex + 1);
  aModel.fUses[lIndex].fUnitName := aUnitName;
  aModel.fUses[lIndex].fSectionKind := aSectionKind;
  aModel.fUses[lIndex].fLine := aLine;
  aModel.fUses[lIndex].fCol := aCol;
end;

procedure AddDiagnostic(var aModel: TSymbolMapUnitModel; const aMessage: string);
var
  lIndex: Integer;
begin
  lIndex := Length(aModel.fDiagnostics);
  SetLength(aModel.fDiagnostics, lIndex + 1);
  aModel.fDiagnostics[lIndex] := aMessage;
end;

procedure AddSymbol(var aModel: TSymbolMapUnitModel; const aName, aKind, aOwnerName, aTypeName, aSignature,
  aSectionKind: string; const aLine, aCol, aEndLine, aEndCol: Integer);
var
  lIndex: Integer;
begin
  if (aName = '') or (aKind = '') then
    Exit;
  lIndex := Length(aModel.fSymbols);
  SetLength(aModel.fSymbols, lIndex + 1);
  aModel.fSymbols[lIndex].fName := aName;
  aModel.fSymbols[lIndex].fKind := aKind;
  aModel.fSymbols[lIndex].fUnitName := aModel.fUnitName;
  aModel.fSymbols[lIndex].fFilePath := aModel.fFilePath;
  aModel.fSymbols[lIndex].fOwnerName := aOwnerName;
  aModel.fSymbols[lIndex].fTypeName := aTypeName;
  aModel.fSymbols[lIndex].fSignature := aSignature;
  aModel.fSymbols[lIndex].fSectionKind := aSectionKind;
  aModel.fSymbols[lIndex].fLine := aLine;
  aModel.fSymbols[lIndex].fCol := aCol;
  aModel.fSymbols[lIndex].fEndLine := aEndLine;
  aModel.fSymbols[lIndex].fEndCol := aEndCol;
end;

procedure AddMember(var aModel: TSymbolMapUnitModel; const aOwnerName, aMemberName, aKind, aTypeName,
  aVisibility, aSignature: string; const aIsDefault, aIsIndexed: Boolean; const aLine, aCol, aEndLine,
  aEndCol: Integer);
var
  lIndex: Integer;
begin
  if (aOwnerName = '') or (aMemberName = '') or (aKind = '') then
    Exit;
  lIndex := Length(aModel.fMembers);
  SetLength(aModel.fMembers, lIndex + 1);
  aModel.fMembers[lIndex].fOwnerName := aOwnerName;
  aModel.fMembers[lIndex].fMemberName := aMemberName;
  aModel.fMembers[lIndex].fKind := aKind;
  aModel.fMembers[lIndex].fTypeName := aTypeName;
  aModel.fMembers[lIndex].fVisibility := aVisibility;
  aModel.fMembers[lIndex].fSignature := aSignature;
  aModel.fMembers[lIndex].fIsDefault := aIsDefault;
  aModel.fMembers[lIndex].fIsIndexed := aIsIndexed;
  aModel.fMembers[lIndex].fLine := aLine;
  aModel.fMembers[lIndex].fCol := aCol;
  aModel.fMembers[lIndex].fEndLine := aEndLine;
  aModel.fMembers[lIndex].fEndCol := aEndCol;
end;

procedure AddReference(var aModel: TSymbolMapUnitModel; const aName, aSectionKind, aRole: string; const aLine,
  aCol, aEndLine, aEndCol: Integer);
var
  lIndex: Integer;
begin
  if aName = '' then
    Exit;
  lIndex := Length(aModel.fReferences);
  SetLength(aModel.fReferences, lIndex + 1);
  aModel.fReferences[lIndex].fName := aName;
  aModel.fReferences[lIndex].fSectionKind := aSectionKind;
  aModel.fReferences[lIndex].fRole := aRole;
  aModel.fReferences[lIndex].fLine := aLine;
  aModel.fReferences[lIndex].fCol := aCol;
  aModel.fReferences[lIndex].fEndLine := aEndLine;
  aModel.fReferences[lIndex].fEndCol := aEndCol;
end;

function ContainsReference(const aModel: TSymbolMapUnitModel; const aReference: TSymbolMapReferenceModel): Boolean;
var
  lReference: TSymbolMapReferenceModel;
begin
  for lReference in aModel.fReferences do
    if SameText(lReference.fName, aReference.fName) and (lReference.fLine = aReference.fLine) and
      (lReference.fCol = aReference.fCol) then
      Exit(True);

  Result := False;
end;

function TryUpdateReference(var aModel: TSymbolMapUnitModel;
  const aReference: TSymbolMapReferenceModel): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(aModel.fReferences) do
    if SameText(aModel.fReferences[i].fName, aReference.fName) and
      (aModel.fReferences[i].fLine = aReference.fLine) and
      (aModel.fReferences[i].fCol = aReference.fCol) then
    begin
      aModel.fReferences[i].fSectionKind := aReference.fSectionKind;
      aModel.fReferences[i].fRole := aReference.fRole;
      aModel.fReferences[i].fEndLine := aReference.fEndLine;
      aModel.fReferences[i].fEndCol := aReference.fEndCol;
      Exit(True);
    end;

  Result := False;
end;

procedure MergeLegacyCompatibilityModel(var aModel: TSymbolMapUnitModel;
  const aLegacyModel: TSymbolMapUnitModel);
var
  i: Integer;
  lLegacyReference: TSymbolMapReferenceModel;
  lLegacySymbol: TSymbolMapSymbolModel;
begin
  for i := 0 to High(aModel.fSymbols) do
    if aModel.fSymbols[i].fSignature = '' then
      for lLegacySymbol in aLegacyModel.fSymbols do
        if SameText(aModel.fSymbols[i].fName, lLegacySymbol.fName) and
          SameText(aModel.fSymbols[i].fKind, lLegacySymbol.fKind) and
          SameText(aModel.fSymbols[i].fSectionKind, lLegacySymbol.fSectionKind) then
        begin
          aModel.fSymbols[i].fSignature := lLegacySymbol.fSignature;
          Break;
        end;

  for lLegacyReference in aLegacyModel.fReferences do
    if not TryUpdateReference(aModel, lLegacyReference) and
      not ContainsReference(aModel, lLegacyReference) then
      AddReference(aModel, lLegacyReference.fName, lLegacyReference.fSectionKind,
        lLegacyReference.fRole, lLegacyReference.fLine, lLegacyReference.fCol,
        lLegacyReference.fEndLine, lLegacyReference.fEndCol);
end;

function SemanticDeclarationOwnerName(const aDeclaration: TDelphiSemanticDeclaration): string;
begin
  if SameText(aDeclaration.Kind, 'enum-value') then
  begin
    Result := aDeclaration.TypeName;
  end else
  begin
    Result := '';
  end;
end;

function SemanticDeclarationTypeName(const aDeclaration: TDelphiSemanticDeclaration): string;
begin
  if SameText(aDeclaration.Kind, 'enum-value') then
  begin
    Result := '';
  end else
  begin
    Result := aDeclaration.TypeName;
  end;
end;

function SymbolMapUseKey(const aUnitName, aSectionKind: string): string;
begin
  Result := aUnitName + #9 + aSectionKind;
end;

function SymbolMapSymbolKey(const aName, aKind, aSectionKind: string): string;
begin
  Result := aName + #9 + aKind + #9 + aSectionKind;
end;

function SymbolMapMemberKey(const aOwnerName, aMemberName, aKind: string): string;
begin
  Result := aOwnerName + #9 + aMemberName + #9 + aKind;
end;

procedure SeedSemanticUseKeys(const aModel: TSymbolMapUnitModel; aKeys: THashSet<string>);
var
  lUse: TSymbolMapUnitUse;
begin
  for lUse in aModel.fUses do
    aKeys.Add(SymbolMapUseKey(lUse.fUnitName, lUse.fSectionKind));
end;

procedure SeedSemanticSymbolKeys(const aModel: TSymbolMapUnitModel; aKeys: THashSet<string>);
var
  lSymbol: TSymbolMapSymbolModel;
begin
  for lSymbol in aModel.fSymbols do
    aKeys.Add(SymbolMapSymbolKey(lSymbol.fName, lSymbol.fKind, lSymbol.fSectionKind));
end;

procedure SeedSemanticMemberKeys(const aModel: TSymbolMapUnitModel; aKeys: THashSet<string>);
var
  lMember: TSymbolMapMemberModel;
begin
  for lMember in aModel.fMembers do
    aKeys.Add(SymbolMapMemberKey(lMember.fOwnerName, lMember.fMemberName, lMember.fKind));
end;

procedure AppendSemanticUse(var aModel: TSymbolMapUnitModel; aKeys: THashSet<string>; const aUnitName,
  aSectionKind: string; var aUseCount: Integer);
begin
  if (aUnitName = '') or (aSectionKind = '') or
    not aKeys.Add(SymbolMapUseKey(aUnitName, aSectionKind)) then
    Exit;

  aModel.fUses[aUseCount].fUnitName := aUnitName;
  aModel.fUses[aUseCount].fSectionKind := aSectionKind;
  aModel.fUses[aUseCount].fLine := 0;
  aModel.fUses[aUseCount].fCol := 0;
  Inc(aUseCount);
end;

procedure MergeSemanticUses(var aModel: TSymbolMapUnitModel; const aSemanticModel: TDelphiSemanticUnitModel);
var
  lUseCount: Integer;
  lUseKeys: THashSet<string>;
  lUseName: string;
begin
  lUseKeys := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    SeedSemanticUseKeys(aModel, lUseKeys);
    lUseCount := Length(aModel.fUses);
    SetLength(aModel.fUses, lUseCount + Length(aSemanticModel.InterfaceUses) +
      Length(aSemanticModel.ImplementationUses));
    for lUseName in aSemanticModel.InterfaceUses do
      AppendSemanticUse(aModel, lUseKeys, lUseName, 'interface', lUseCount);
    for lUseName in aSemanticModel.ImplementationUses do
      AppendSemanticUse(aModel, lUseKeys, lUseName, 'implementation', lUseCount);
    SetLength(aModel.fUses, lUseCount);
  finally
    lUseKeys.Free;
  end;
end;

procedure AppendSemanticSymbol(var aModel: TSymbolMapUnitModel; aKeys: THashSet<string>; const aName,
  aKind, aOwnerName, aTypeName, aSignature, aSectionKind: string; const aLine, aCol, aEndLine,
  aEndCol: Integer; var aSymbolCount: Integer);
begin
  if (aName = '') or (aKind = '') or
    not aKeys.Add(SymbolMapSymbolKey(aName, aKind, aSectionKind)) then
    Exit;

  aModel.fSymbols[aSymbolCount].fName := aName;
  aModel.fSymbols[aSymbolCount].fKind := aKind;
  aModel.fSymbols[aSymbolCount].fUnitName := aModel.fUnitName;
  aModel.fSymbols[aSymbolCount].fFilePath := aModel.fFilePath;
  aModel.fSymbols[aSymbolCount].fOwnerName := aOwnerName;
  aModel.fSymbols[aSymbolCount].fTypeName := aTypeName;
  aModel.fSymbols[aSymbolCount].fSignature := aSignature;
  aModel.fSymbols[aSymbolCount].fSectionKind := aSectionKind;
  aModel.fSymbols[aSymbolCount].fLine := aLine;
  aModel.fSymbols[aSymbolCount].fCol := aCol;
  aModel.fSymbols[aSymbolCount].fEndLine := aEndLine;
  aModel.fSymbols[aSymbolCount].fEndCol := aEndCol;
  Inc(aSymbolCount);
end;

procedure MergeSemanticSymbols(var aModel: TSymbolMapUnitModel; const aSemanticModel: TDelphiSemanticUnitModel);
var
  lDeclaration: TDelphiSemanticDeclaration;
  lRoutine: TDelphiSemanticRoutine;
  lSymbolCount: Integer;
  lSymbolKeys: THashSet<string>;
begin
  lSymbolKeys := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    SeedSemanticSymbolKeys(aModel, lSymbolKeys);
    lSymbolCount := Length(aModel.fSymbols);
    SetLength(aModel.fSymbols, lSymbolCount + Length(aSemanticModel.Declarations) +
      Length(aSemanticModel.Routines));
    for lDeclaration in aSemanticModel.Declarations do
      AppendSemanticSymbol(aModel, lSymbolKeys, lDeclaration.Name, lDeclaration.Kind,
        SemanticDeclarationOwnerName(lDeclaration), SemanticDeclarationTypeName(lDeclaration), '',
        lDeclaration.SectionKind, lDeclaration.Line, lDeclaration.Column, lDeclaration.Line,
        lDeclaration.Column, lSymbolCount);
    for lRoutine in aSemanticModel.Routines do
      AppendSemanticSymbol(aModel, lSymbolKeys, lRoutine.Name, 'routine', lRoutine.OwnerName,
        lRoutine.ReturnType, lRoutine.Signature, lRoutine.SectionKind, lRoutine.Line, lRoutine.Column,
        lRoutine.Line, lRoutine.Column, lSymbolCount);
    SetLength(aModel.fSymbols, lSymbolCount);
  finally
    lSymbolKeys.Free;
  end;
end;

procedure AppendSemanticMember(var aModel: TSymbolMapUnitModel; aKeys: THashSet<string>; const aOwnerName,
  aMemberName, aKind, aTypeName, aVisibility, aSignature: string; const aIsDefault, aIsIndexed: Boolean;
  const aLine, aCol, aEndLine, aEndCol: Integer; var aMemberCount: Integer);
begin
  if (aOwnerName = '') or (aMemberName = '') or (aKind = '') or
    not aKeys.Add(SymbolMapMemberKey(aOwnerName, aMemberName, aKind)) then
    Exit;

  aModel.fMembers[aMemberCount].fOwnerName := aOwnerName;
  aModel.fMembers[aMemberCount].fMemberName := aMemberName;
  aModel.fMembers[aMemberCount].fKind := aKind;
  aModel.fMembers[aMemberCount].fTypeName := aTypeName;
  aModel.fMembers[aMemberCount].fVisibility := aVisibility;
  aModel.fMembers[aMemberCount].fSignature := aSignature;
  aModel.fMembers[aMemberCount].fIsDefault := aIsDefault;
  aModel.fMembers[aMemberCount].fIsIndexed := aIsIndexed;
  aModel.fMembers[aMemberCount].fLine := aLine;
  aModel.fMembers[aMemberCount].fCol := aCol;
  aModel.fMembers[aMemberCount].fEndLine := aEndLine;
  aModel.fMembers[aMemberCount].fEndCol := aEndCol;
  Inc(aMemberCount);
end;

procedure MergeSemanticMembers(var aModel: TSymbolMapUnitModel; const aSemanticModel: TDelphiSemanticUnitModel);
var
  lMemberCount: Integer;
  lMemberKeys: THashSet<string>;
  lMember: TDelphiSemanticMember;
begin
  lMemberKeys := THashSet<string>.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  try
    SeedSemanticMemberKeys(aModel, lMemberKeys);
    lMemberCount := Length(aModel.fMembers);
    SetLength(aModel.fMembers, lMemberCount + Length(aSemanticModel.Members));
    for lMember in aSemanticModel.Members do
      AppendSemanticMember(aModel, lMemberKeys, lMember.OwnerName, lMember.Name, lMember.Kind,
        lMember.TypeName, lMember.Visibility, lMember.Signature, lMember.IsDefault, lMember.IsIndexed,
        lMember.Line, lMember.Column, lMember.Line, lMember.Column, lMemberCount);
    SetLength(aModel.fMembers, lMemberCount);
  finally
    lMemberKeys.Free;
  end;
end;

procedure MergeSemanticReferences(var aModel: TSymbolMapUnitModel; const aSemanticModel: TDelphiSemanticUnitModel);
var
  lReference: TDelphiSemanticReference;
  lReferenceCount: Integer;
begin
  lReferenceCount := Length(aModel.fReferences);
  SetLength(aModel.fReferences, lReferenceCount + Length(aSemanticModel.References));
  for lReference in aSemanticModel.References do
  begin
    if lReference.Name = '' then
      Continue;

    aModel.fReferences[lReferenceCount].fName := lReference.Name;
    aModel.fReferences[lReferenceCount].fSectionKind := 'implementation';
    aModel.fReferences[lReferenceCount].fRole := 'token';
    aModel.fReferences[lReferenceCount].fLine := lReference.Line;
    aModel.fReferences[lReferenceCount].fCol := lReference.Column;
    aModel.fReferences[lReferenceCount].fEndLine := lReference.Line;
    aModel.fReferences[lReferenceCount].fEndCol := lReference.Column;
    Inc(lReferenceCount);
  end;
  SetLength(aModel.fReferences, lReferenceCount);
end;

procedure MergeDelphiSemanticModel(var aModel: TSymbolMapUnitModel; const aSemanticModel: TDelphiSemanticUnitModel);
var
  lDiagnostic: TDelphiSemanticModelDiagnostic;
begin
  if aModel.fUnitName = '' then
  begin
    aModel.fUnitName := aSemanticModel.UnitName;
  end;

  MergeSemanticUses(aModel, aSemanticModel);
  MergeSemanticSymbols(aModel, aSemanticModel);
  MergeSemanticMembers(aModel, aSemanticModel);
  MergeSemanticReferences(aModel, aSemanticModel);

  for lDiagnostic in aSemanticModel.Diagnostics do
  begin
    if not SameText(lDiagnostic.Code, 'NO_PROJECT_CONTEXT') then
      AddDiagnostic(aModel, lDiagnostic.Message);
  end;
end;

function SymbolMapUnitModelFromDelphiSemanticModel(const aSemanticModel: TDelphiSemanticUnitModel):
  TSymbolMapUnitModel;
begin
  Result := Default(TSymbolMapUnitModel);
  Result.fFilePath := aSemanticModel.FileName;
  Result.fEncodingName := aSemanticModel.EncodingName;
  MergeDelphiSemanticModel(Result, aSemanticModel);
end;

procedure MergeDelphiSemanticExtraction(const aFilePath: string; var aModel: TSymbolMapUnitModel);
var
  lOptions: TDelphiSemanticModelOptions;
  lSemanticModel: TDelphiSemanticUnitModel;
begin
  if (aModel.fUnitName <> '') and ((Length(aModel.fSymbols) > 0) or (Length(aModel.fMembers) > 0)) then
  begin
    Exit;
  end;

  lOptions := Default(TDelphiSemanticModelOptions);
  lOptions.SourceFileName := aFilePath;
  lOptions.ProjectContextApplied := False;
  lSemanticModel := TDelphiSemanticUnitModelExtractor.ExtractFromFile(lOptions);
  if lSemanticModel.Success then
  begin
    MergeDelphiSemanticModel(aModel, lSemanticModel);
  end;
end;

procedure ExtractIdentifierReferences(const aTokens: TArray<TSymbolMapToken>; var aModel: TSymbolMapUnitModel); forward;
procedure ExtractUnitModelFromTokens(const aSource: string; const aTokens: TArray<TSymbolMapToken>;
  var aModel: TSymbolMapUnitModel); forward;

function TryExtractLegacySymbolMapUnitModel(const aFilePath: string; out aModel: TSymbolMapUnitModel;
  out aError: string): Boolean;
var
  lSourceText: string;
  lTokens: TArray<TSymbolMapToken>;
begin
  Result := False;
  aModel := Default(TSymbolMapUnitModel);
  aError := '';
  aModel.fFilePath := TPath.GetFullPath(aFilePath);
  if not TryLoadSymbolMapSourceFile(aFilePath, lSourceText, aModel.fEncodingName, aError) then
    Exit(False);
  TokenizeSource(lSourceText, lTokens);
  ExtractUnitModelFromTokens(lSourceText, lTokens, aModel);
  ExtractIdentifierReferences(lTokens, aModel);
  Result := True;
end;

function TokenIsIdentifierText(const aToken: TSymbolMapToken; const aText: string): Boolean;
begin
  Result := (aToken.fKind = smtIdentifier) and SameText(aToken.fText, aText);
end;

function TokenIsReferenceKeyword(const aToken: TSymbolMapToken): Boolean;
begin
  Result := (aToken.fKind = smtIdentifier) and MatchText(aToken.fText,
    ['absolute', 'abstract', 'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except', 'exports', 'file',
    'finalization', 'finally', 'for', 'function', 'goto', 'helper', 'if', 'implementation', 'in', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'mod', 'nil', 'not', 'object', 'of', 'or', 'out',
    'packed', 'private', 'procedure', 'program', 'property', 'protected', 'public', 'published', 'raise', 'record',
    'repeat', 'resourcestring', 'set', 'shl', 'shr', 'strict', 'string', 'then', 'threadvar', 'to', 'try', 'type',
    'unit', 'until', 'uses', 'var', 'while', 'with', 'xor']);
end;

procedure ExtractIdentifierReferences(const aTokens: TArray<TSymbolMapToken>; var aModel: TSymbolMapUnitModel);
var
  lIndex: Integer;
  lSectionKind: string;
begin
  lSectionKind := '';
  lIndex := 0;
  while lIndex <= High(aTokens) do
  begin
    if aTokens[lIndex].fKind = smtIdentifier then
    begin
      if SameText(aTokens[lIndex].fText, 'interface') then
        lSectionKind := 'interface'
      else if SameText(aTokens[lIndex].fText, 'implementation') then
        lSectionKind := 'implementation';
      if not TokenIsReferenceKeyword(aTokens[lIndex]) then
        AddReference(aModel, aTokens[lIndex].fText, lSectionKind, 'token', aTokens[lIndex].fLine,
          aTokens[lIndex].fCol, aTokens[lIndex].fLine, aTokens[lIndex].fCol + Length(aTokens[lIndex].fText) - 1);
    end;
    Inc(lIndex);
  end;
end;

function TokenStartsDeclarationSection(const aToken: TSymbolMapToken): Boolean;
begin
  Result := (aToken.fKind = smtIdentifier) and MatchText(aToken.fText,
    ['const', 'exports', 'finalization', 'function', 'implementation', 'initialization', 'procedure', 'resourcestring',
    'threadvar', 'type', 'var']);
end;

function TrimSourceFragment(const aSource: string; const aStartOffset, aEndOffset: Integer): string;
begin
  if (aStartOffset <= 0) or (aEndOffset < aStartOffset) or (aEndOffset > Length(aSource)) then
    Exit('');
  Result := Trim(Copy(aSource, aStartOffset, aEndOffset - aStartOffset + 1));
end;

function TryReadDottedName(const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer; out aName: string;
  out aLine, aCol: Integer): Boolean;
begin
  Result := False;
  aName := '';
  aLine := 0;
  aCol := 0;
  if (aIndex > High(aTokens)) or (aTokens[aIndex].fKind <> smtIdentifier) then
    Exit(False);

  aName := aTokens[aIndex].fText;
  aLine := aTokens[aIndex].fLine;
  aCol := aTokens[aIndex].fCol;
  Inc(aIndex);
  while (aIndex + 1 <= High(aTokens)) and (aTokens[aIndex].fKind = smtDot) and
    (aTokens[aIndex + 1].fKind = smtIdentifier) do
  begin
    aName := aName + '.' + aTokens[aIndex + 1].fText;
    Inc(aIndex, 2);
  end;
  Result := True;
end;

function TryReadTypeName(const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer; out aName: string): Boolean;
var
  lCol: Integer;
  lLine: Integer;
begin
  Result := TryReadDottedName(aTokens, aIndex, aName, lLine, lCol);
end;

procedure MoveToSemicolon(const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer);
begin
  while (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind <> smtSemicolon) do
    Inc(aIndex);
end;

function TokenIsVisibility(const aToken: TSymbolMapToken): Boolean;
begin
  Result := (aToken.fKind = smtIdentifier) and MatchText(aToken.fText,
    ['private', 'protected', 'public', 'published']);
end;

function TokenIsMemberRoutineKeyword(const aToken: TSymbolMapToken): Boolean;
begin
  Result := (aToken.fKind = smtIdentifier) and MatchText(aToken.fText,
    ['constructor', 'destructor', 'function', 'procedure']);
end;

procedure MoveToBalancedSemicolon(const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer);
var
  lBracketDepth: Integer;
  lParenDepth: Integer;
begin
  lBracketDepth := 0;
  lParenDepth := 0;
  while aIndex <= High(aTokens) do
  begin
    if aTokens[aIndex].fKind = smtLParen then
      Inc(lParenDepth)
    else if (aTokens[aIndex].fKind = smtRParen) and (lParenDepth > 0) then
      Dec(lParenDepth)
    else if aTokens[aIndex].fKind = smtLBracket then
      Inc(lBracketDepth)
    else if (aTokens[aIndex].fKind = smtRBracket) and (lBracketDepth > 0) then
      Dec(lBracketDepth)
    else if (lParenDepth = 0) and (lBracketDepth = 0) and (aTokens[aIndex].fKind = smtSemicolon) then
      Exit;
    Inc(aIndex);
  end;
end;

procedure ParseMemberRoutine(const aSource: string; const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer;
  const aOwnerName, aVisibility: string; var aModel: TSymbolMapUnitModel);
var
  lEndCol: Integer;
  lEndLine: Integer;
  lEndOffset: Integer;
  lIsFunction: Boolean;
  lMemberName: string;
  lNameCol: Integer;
  lNameLine: Integer;
  lParenDepth: Integer;
  lRoutineStart: Integer;
  lSignature: string;
  lTypeIndex: Integer;
  lTypeName: string;
begin
  lRoutineStart := aIndex;
  lIsFunction := TokenIsIdentifierText(aTokens[aIndex], 'function');
  Inc(aIndex);
  if (aIndex > High(aTokens)) or (aTokens[aIndex].fKind <> smtIdentifier) then
    Exit;
  lMemberName := aTokens[aIndex].fText;
  lNameLine := aTokens[aIndex].fLine;
  lNameCol := aTokens[aIndex].fCol;
  Inc(aIndex);
  lTypeName := '';
  lParenDepth := 0;
  while aIndex <= High(aTokens) do
  begin
    if aTokens[aIndex].fKind = smtLParen then
      Inc(lParenDepth)
    else if (aTokens[aIndex].fKind = smtRParen) and (lParenDepth > 0) then
      Dec(lParenDepth)
    else if lIsFunction and (lParenDepth = 0) and (aTokens[aIndex].fKind = smtColon) then
    begin
      Inc(aIndex);
      lTypeIndex := aIndex;
      TryReadTypeName(aTokens, lTypeIndex, lTypeName);
      Continue;
    end else if (lParenDepth = 0) and (aTokens[aIndex].fKind = smtSemicolon) then
      Break;
    Inc(aIndex);
  end;
  MoveToBalancedSemicolon(aTokens, aIndex);
  if aIndex <= High(aTokens) then
  begin
    lEndLine := aTokens[aIndex].fLine;
    lEndCol := aTokens[aIndex].fCol;
    lEndOffset := aTokens[aIndex].fEndOffset;
  end else begin
    lEndLine := lNameLine;
    lEndCol := lNameCol;
    lEndOffset := aTokens[lRoutineStart].fEndOffset;
  end;
  lSignature := TrimSourceFragment(aSource, aTokens[lRoutineStart].fOffset, lEndOffset);
  AddMember(aModel, aOwnerName, lMemberName, 'method', lTypeName, aVisibility, lSignature, False, False,
    lNameLine, lNameCol, lEndLine, lEndCol);
  if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtSemicolon) then
    Inc(aIndex);
end;

procedure ParseMemberProperty(const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer; const aOwnerName,
  aVisibility: string; var aModel: TSymbolMapUnitModel);
var
  lBracketDepth: Integer;
  lEndCol: Integer;
  lEndLine: Integer;
  lIsDefault: Boolean;
  lIsIndexed: Boolean;
  lMemberName: string;
  lNameCol: Integer;
  lNameLine: Integer;
  lParenDepth: Integer;
  lTypeIndex: Integer;
  lTypeName: string;
begin
  Inc(aIndex);
  if (aIndex > High(aTokens)) or (aTokens[aIndex].fKind <> smtIdentifier) then
    Exit;
  lMemberName := aTokens[aIndex].fText;
  lNameLine := aTokens[aIndex].fLine;
  lNameCol := aTokens[aIndex].fCol;
  lTypeName := '';
  lIsDefault := False;
  lIsIndexed := False;
  lBracketDepth := 0;
  lParenDepth := 0;
  Inc(aIndex);
  while aIndex <= High(aTokens) do
  begin
    if aTokens[aIndex].fKind = smtLBracket then
    begin
      lIsIndexed := True;
      Inc(lBracketDepth);
    end else if (aTokens[aIndex].fKind = smtRBracket) and (lBracketDepth > 0) then
      Dec(lBracketDepth)
    else if aTokens[aIndex].fKind = smtLParen then
      Inc(lParenDepth)
    else if (aTokens[aIndex].fKind = smtRParen) and (lParenDepth > 0) then
      Dec(lParenDepth)
    else if (lBracketDepth = 0) and (lParenDepth = 0) and (aTokens[aIndex].fKind = smtColon) then
    begin
      Inc(aIndex);
      lTypeIndex := aIndex;
      TryReadTypeName(aTokens, lTypeIndex, lTypeName);
      Continue;
    end else if (lBracketDepth = 0) and (lParenDepth = 0) and (aTokens[aIndex].fKind = smtSemicolon) then
      Break;
    Inc(aIndex);
  end;
  MoveToBalancedSemicolon(aTokens, aIndex);
  if aIndex <= High(aTokens) then
  begin
    lEndLine := aTokens[aIndex].fLine;
    lEndCol := aTokens[aIndex].fCol;
    if (aIndex + 1 <= High(aTokens)) and TokenIsIdentifierText(aTokens[aIndex + 1], 'default') then
    begin
      lIsDefault := True;
      Inc(aIndex, 2);
      MoveToBalancedSemicolon(aTokens, aIndex);
      if aIndex <= High(aTokens) then
      begin
        lEndLine := aTokens[aIndex].fLine;
        lEndCol := aTokens[aIndex].fCol;
      end;
    end;
  end else begin
    lEndLine := lNameLine;
    lEndCol := lNameCol;
  end;
  AddMember(aModel, aOwnerName, lMemberName, 'property', lTypeName, aVisibility, '', lIsDefault, lIsIndexed,
    lNameLine, lNameCol, lEndLine, lEndCol);
  if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtSemicolon) then
    Inc(aIndex);
end;

procedure ParseMemberFields(const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer; const aOwnerName,
  aVisibility: string; var aModel: TSymbolMapUnitModel);
var
  lEndCol: Integer;
  lEndLine: Integer;
  lNameCols: TArray<Integer>;
  lNameLines: TArray<Integer>;
  lNames: TArray<string>;
  lTypeIndex: Integer;
  lTypeName: string;
  i: Integer;
begin
  SetLength(lNames, 0);
  SetLength(lNameLines, 0);
  SetLength(lNameCols, 0);
  while (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind <> smtColon) and
    (aTokens[aIndex].fKind <> smtSemicolon) do
  begin
    if aTokens[aIndex].fKind = smtIdentifier then
    begin
      i := Length(lNames);
      SetLength(lNames, i + 1);
      SetLength(lNameLines, i + 1);
      SetLength(lNameCols, i + 1);
      lNames[i] := aTokens[aIndex].fText;
      lNameLines[i] := aTokens[aIndex].fLine;
      lNameCols[i] := aTokens[aIndex].fCol;
    end;
    Inc(aIndex);
  end;
  if Length(lNames) = 0 then
  begin
    MoveToBalancedSemicolon(aTokens, aIndex);
    if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtSemicolon) then
      Inc(aIndex);
    Exit;
  end;
  lTypeName := '';
  if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtColon) then
  begin
    Inc(aIndex);
    lTypeIndex := aIndex;
    TryReadTypeName(aTokens, lTypeIndex, lTypeName);
  end;
  MoveToBalancedSemicolon(aTokens, aIndex);
  if aIndex <= High(aTokens) then
  begin
    lEndLine := aTokens[aIndex].fLine;
    lEndCol := aTokens[aIndex].fCol;
  end else begin
    lEndLine := 0;
    lEndCol := 0;
  end;
  for i := 0 to High(lNames) do
    AddMember(aModel, aOwnerName, lNames[i], 'field', lTypeName, aVisibility, '', False, False, lNameLines[i],
      lNameCols[i], lEndLine, lEndCol);
  if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtSemicolon) then
    Inc(aIndex);
end;

procedure ParseStructuredTypeMembers(const aSource: string; const aTokens: TArray<TSymbolMapToken>;
  const aStartIndex, aEndIndex: Integer; const aOwnerName, aDefaultVisibility: string;
  var aModel: TSymbolMapUnitModel);
var
  lIndex: Integer;
  lVisibility: string;
begin
  lIndex := aStartIndex;
  lVisibility := aDefaultVisibility;
  while (lIndex <= aEndIndex) and (lIndex <= High(aTokens)) do
  begin
    if (aTokens[lIndex].fKind <> smtIdentifier) or TokenIsIdentifierText(aTokens[lIndex], 'end') then
    begin
      Inc(lIndex);
      Continue;
    end;
    if TokenIsIdentifierText(aTokens[lIndex], 'strict') and (lIndex + 1 <= aEndIndex) and
      TokenIsVisibility(aTokens[lIndex + 1]) then
    begin
      lVisibility := 'strict ' + LowerCase(aTokens[lIndex + 1].fText);
      Inc(lIndex, 2);
      Continue;
    end;
    if TokenIsVisibility(aTokens[lIndex]) then
    begin
      lVisibility := LowerCase(aTokens[lIndex].fText);
      Inc(lIndex);
      Continue;
    end;
    if TokenIsMemberRoutineKeyword(aTokens[lIndex]) then
    begin
      ParseMemberRoutine(aSource, aTokens, lIndex, aOwnerName, lVisibility, aModel);
      Continue;
    end;
    if TokenIsIdentifierText(aTokens[lIndex], 'property') then
    begin
      ParseMemberProperty(aTokens, lIndex, aOwnerName, lVisibility, aModel);
      Continue;
    end;
    if (lIndex + 1 <= aEndIndex) and ((aTokens[lIndex + 1].fKind = smtColon) or
      (aTokens[lIndex + 1].fKind = smtComma)) then
    begin
      ParseMemberFields(aTokens, lIndex, aOwnerName, lVisibility, aModel);
      Continue;
    end;
    Inc(lIndex);
  end;
end;

procedure ParseTypeSection(const aSource: string; const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer;
  const aSectionKind: string; var aModel: TSymbolMapUnitModel);
var
  lAliasName: string;
  lBodyEndIndex: Integer;
  lBodyStartIndex: Integer;
  lCol: Integer;
  lDefaultVisibility: string;
  lEndCol: Integer;
  lEndLine: Integer;
  lEnumName: string;
  lLine: Integer;
  lName: string;
  lNameCol: Integer;
  lNameLine: Integer;
  lStartIndex: Integer;
  lTypeName: string;
begin
  Inc(aIndex);
  while aIndex <= High(aTokens) do
  begin
    if TokenStartsDeclarationSection(aTokens[aIndex]) then
      Exit;
    if aTokens[aIndex].fKind <> smtIdentifier then
    begin
      Inc(aIndex);
      Continue;
    end;
    lName := aTokens[aIndex].fText;
    lNameLine := aTokens[aIndex].fLine;
    lNameCol := aTokens[aIndex].fCol;
    if (aIndex + 1 > High(aTokens)) or (aTokens[aIndex + 1].fKind <> smtEqual) then
    begin
      Inc(aIndex);
      Continue;
    end;

    Inc(aIndex, 2);
    if (aIndex <= High(aTokens)) and TokenIsIdentifierText(aTokens[aIndex], 'record') then
    begin
      lTypeName := 'record';
      if (aIndex + 1 <= High(aTokens)) and TokenIsIdentifierText(aTokens[aIndex + 1], 'helper') then
      begin
        lTypeName := 'record-helper';
        Inc(aIndex, 4);
      end else
        Inc(aIndex);
      lBodyStartIndex := aIndex;
      lBodyEndIndex := aIndex - 1;
      lEndLine := aTokens[aIndex].fLine;
      lEndCol := aTokens[aIndex].fCol;
      while aIndex <= High(aTokens) do
      begin
        lEndLine := aTokens[aIndex].fLine;
        lEndCol := aTokens[aIndex].fCol;
        if TokenIsIdentifierText(aTokens[aIndex], 'end') then
        begin
          lBodyEndIndex := aIndex - 1;
          while (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind <> smtSemicolon) do
          begin
            lEndLine := aTokens[aIndex].fLine;
            lEndCol := aTokens[aIndex].fCol;
            Inc(aIndex);
          end;
          if aIndex <= High(aTokens) then
          begin
            lEndLine := aTokens[aIndex].fLine;
            lEndCol := aTokens[aIndex].fCol;
          end;
          Break;
        end;
        Inc(aIndex);
      end;
      ParseStructuredTypeMembers(aSource, aTokens, lBodyStartIndex, lBodyEndIndex, lName, 'public', aModel);
      AddSymbol(aModel, lName, 'type', '', lTypeName, '', aSectionKind, lNameLine, lNameCol, lEndLine, lEndCol);
    end else if (aIndex <= High(aTokens)) and
      (TokenIsIdentifierText(aTokens[aIndex], 'class') or TokenIsIdentifierText(aTokens[aIndex], 'interface')) then
    begin
      lTypeName := LowerCase(aTokens[aIndex].fText);
      lDefaultVisibility := 'public';
      if (aIndex + 1 <= High(aTokens)) and TokenIsIdentifierText(aTokens[aIndex + 1], 'helper') then
      begin
        lTypeName := lTypeName + '-helper';
        lDefaultVisibility := 'public';
        Inc(aIndex, 4);
      end else
        Inc(aIndex);
      if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtLParen) then
      begin
        while (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind <> smtRParen) do
          Inc(aIndex);
        if aIndex <= High(aTokens) then
          Inc(aIndex);
      end;
      if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtLBracket) then
      begin
        while (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind <> smtRBracket) do
          Inc(aIndex);
        if aIndex <= High(aTokens) then
          Inc(aIndex);
      end;
      lBodyStartIndex := aIndex;
      lBodyEndIndex := aIndex - 1;
      lEndLine := aTokens[aIndex].fLine;
      lEndCol := aTokens[aIndex].fCol;
      while aIndex <= High(aTokens) do
      begin
        lEndLine := aTokens[aIndex].fLine;
        lEndCol := aTokens[aIndex].fCol;
        if TokenIsIdentifierText(aTokens[aIndex], 'end') then
        begin
          lBodyEndIndex := aIndex - 1;
          while (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind <> smtSemicolon) do
          begin
            lEndLine := aTokens[aIndex].fLine;
            lEndCol := aTokens[aIndex].fCol;
            Inc(aIndex);
          end;
          if aIndex <= High(aTokens) then
          begin
            lEndLine := aTokens[aIndex].fLine;
            lEndCol := aTokens[aIndex].fCol;
          end;
          Break;
        end;
        Inc(aIndex);
      end;
      ParseStructuredTypeMembers(aSource, aTokens, lBodyStartIndex, lBodyEndIndex, lName, lDefaultVisibility, aModel);
      AddSymbol(aModel, lName, 'type', '', lTypeName, '', aSectionKind, lNameLine, lNameCol, lEndLine, lEndCol);
    end else if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtLParen) then
    begin
      AddSymbol(aModel, lName, 'type', '', 'enum', '', aSectionKind, lNameLine, lNameCol, lNameLine, lNameCol);
      Inc(aIndex);
      while (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind <> smtRParen) do
      begin
        if aTokens[aIndex].fKind = smtIdentifier then
        begin
          lEnumName := aTokens[aIndex].fText;
          AddSymbol(aModel, lEnumName, 'enum-value', lName, '', '', aSectionKind, aTokens[aIndex].fLine,
            aTokens[aIndex].fCol, aTokens[aIndex].fLine, aTokens[aIndex].fCol);
        end;
        Inc(aIndex);
      end;
      MoveToSemicolon(aTokens, aIndex);
    end else begin
      lStartIndex := aIndex;
      if not TryReadTypeName(aTokens, aIndex, lAliasName) then
        lAliasName := '';
      lEndLine := aTokens[lStartIndex].fLine;
      lEndCol := aTokens[lStartIndex].fCol;
      MoveToSemicolon(aTokens, aIndex);
      if aIndex <= High(aTokens) then
      begin
        lEndLine := aTokens[aIndex].fLine;
        lEndCol := aTokens[aIndex].fCol;
      end;
      AddSymbol(aModel, lName, 'type-alias', '', lAliasName, '', aSectionKind, lNameLine, lNameCol, lEndLine,
        lEndCol);
    end;
    if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtSemicolon) then
      Inc(aIndex);
  end;
end;

procedure ParseConstSection(const aSource: string; const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer;
  const aSectionKind: string; var aModel: TSymbolMapUnitModel);
var
  lEndCol: Integer;
  lEndLine: Integer;
  lKind: string;
  lName: string;
  lNameCol: Integer;
  lNameLine: Integer;
  lTypeIndex: Integer;
  lTypeName: string;
begin
  Inc(aIndex);
  while aIndex <= High(aTokens) do
  begin
    if TokenStartsDeclarationSection(aTokens[aIndex]) then
      Exit;
    if aTokens[aIndex].fKind <> smtIdentifier then
    begin
      Inc(aIndex);
      Continue;
    end;
    lName := aTokens[aIndex].fText;
    lNameLine := aTokens[aIndex].fLine;
    lNameCol := aTokens[aIndex].fCol;
    Inc(aIndex);
    lKind := 'const';
    lTypeName := '';
    if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtColon) then
    begin
      lKind := 'typed-const';
      Inc(aIndex);
      lTypeIndex := aIndex;
      TryReadTypeName(aTokens, lTypeIndex, lTypeName);
    end;
    MoveToSemicolon(aTokens, aIndex);
    if aIndex <= High(aTokens) then
    begin
      lEndLine := aTokens[aIndex].fLine;
      lEndCol := aTokens[aIndex].fCol;
    end else begin
      lEndLine := lNameLine;
      lEndCol := lNameCol;
    end;
    AddSymbol(aModel, lName, lKind, '', lTypeName, '', aSectionKind, lNameLine, lNameCol, lEndLine, lEndCol);
    if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtSemicolon) then
      Inc(aIndex);
  end;
end;

procedure ParseVarSection(const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer; const aSectionKind: string;
  var aModel: TSymbolMapUnitModel);
var
  lEndCol: Integer;
  lEndLine: Integer;
  lNameCols: TArray<Integer>;
  lNameLines: TArray<Integer>;
  lNames: TArray<string>;
  lTypeIndex: Integer;
  lTypeName: string;
  i: Integer;
begin
  Inc(aIndex);
  while aIndex <= High(aTokens) do
  begin
    if TokenStartsDeclarationSection(aTokens[aIndex]) then
      Exit;
    SetLength(lNames, 0);
    SetLength(lNameLines, 0);
    SetLength(lNameCols, 0);
    while (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind <> smtColon) and
      (aTokens[aIndex].fKind <> smtSemicolon) do
    begin
      if aTokens[aIndex].fKind = smtIdentifier then
      begin
        i := Length(lNames);
        SetLength(lNames, i + 1);
        SetLength(lNameLines, i + 1);
        SetLength(lNameCols, i + 1);
        lNames[i] := aTokens[aIndex].fText;
        lNameLines[i] := aTokens[aIndex].fLine;
        lNameCols[i] := aTokens[aIndex].fCol;
      end;
      Inc(aIndex);
    end;
    lTypeName := '';
    if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtColon) then
    begin
      Inc(aIndex);
      lTypeIndex := aIndex;
      TryReadTypeName(aTokens, lTypeIndex, lTypeName);
    end;
    MoveToSemicolon(aTokens, aIndex);
    if aIndex <= High(aTokens) then
    begin
      lEndLine := aTokens[aIndex].fLine;
      lEndCol := aTokens[aIndex].fCol;
    end else begin
      lEndLine := 0;
      lEndCol := 0;
    end;
    for i := 0 to High(lNames) do
      AddSymbol(aModel, lNames[i], 'var', '', lTypeName, '', aSectionKind, lNameLines[i], lNameCols[i], lEndLine,
        lEndCol);
    if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtSemicolon) then
      Inc(aIndex);
  end;
end;

procedure ParseRoutineDeclaration(const aSource: string; const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer;
  const aSectionKind: string; var aModel: TSymbolMapUnitModel);
var
  lEndOffset: Integer;
  lEndCol: Integer;
  lEndLine: Integer;
  lIsFunction: Boolean;
  lName: string;
  lNameCol: Integer;
  lNameLine: Integer;
  lParenDepth: Integer;
  lRoutineStart: Integer;
  lSignature: string;
  lTypeIndex: Integer;
  lTypeName: string;
begin
  lRoutineStart := aIndex;
  lIsFunction := TokenIsIdentifierText(aTokens[aIndex], 'function');
  Inc(aIndex);
  if (aIndex > High(aTokens)) or (aTokens[aIndex].fKind <> smtIdentifier) then
    Exit;
  lName := aTokens[aIndex].fText;
  lNameLine := aTokens[aIndex].fLine;
  lNameCol := aTokens[aIndex].fCol;
  Inc(aIndex);
  lTypeName := '';
  lParenDepth := 0;
  while aIndex <= High(aTokens) do
  begin
    if (lParenDepth = 0) and (aTokens[aIndex].fKind = smtSemicolon) then
      Break;
    if aTokens[aIndex].fKind = smtLParen then
      Inc(lParenDepth)
    else if (aTokens[aIndex].fKind = smtRParen) and (lParenDepth > 0) then
      Dec(lParenDepth)
    else if lIsFunction and (lParenDepth = 0) and (aTokens[aIndex].fKind = smtColon) then
    begin
      Inc(aIndex);
      lTypeIndex := aIndex;
      TryReadTypeName(aTokens, lTypeIndex, lTypeName);
      Continue;
    end;
    Inc(aIndex);
  end;
  if aIndex <= High(aTokens) then
  begin
    lEndLine := aTokens[aIndex].fLine;
    lEndCol := aTokens[aIndex].fCol;
    lEndOffset := aTokens[aIndex].fEndOffset;
  end else begin
    lEndLine := lNameLine;
    lEndCol := lNameCol;
    lEndOffset := aTokens[lRoutineStart].fEndOffset;
  end;
  lSignature := TrimSourceFragment(aSource, aTokens[lRoutineStart].fOffset, lEndOffset);
  AddSymbol(aModel, lName, 'routine', '', lTypeName, lSignature, aSectionKind, lNameLine, lNameCol, lEndLine,
    lEndCol);
  if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtSemicolon) then
    Inc(aIndex);
end;

procedure SkipImplementationRoutineBody(const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer);
var
  lBeginDepth: Integer;
begin
  while (aIndex <= High(aTokens)) and not TokenIsIdentifierText(aTokens[aIndex], 'begin') do
    Inc(aIndex);
  if aIndex > High(aTokens) then
    Exit;

  lBeginDepth := 0;
  while aIndex <= High(aTokens) do
  begin
    if TokenIsIdentifierText(aTokens[aIndex], 'begin') or TokenIsIdentifierText(aTokens[aIndex], 'try') or
      TokenIsIdentifierText(aTokens[aIndex], 'case') then
      Inc(lBeginDepth)
    else if TokenIsIdentifierText(aTokens[aIndex], 'end') then
    begin
      Dec(lBeginDepth);
      if lBeginDepth <= 0 then
      begin
        Inc(aIndex);
        if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtDot) then
          Exit;
        if (aIndex <= High(aTokens)) and (aTokens[aIndex].fKind = smtSemicolon) then
          Inc(aIndex);
        Exit;
      end;
    end;
    Inc(aIndex);
  end;
end;

procedure ParseUsesClause(const aTokens: TArray<TSymbolMapToken>; var aIndex: Integer; const aSectionKind: string;
  var aModel: TSymbolMapUnitModel);
var
  lCol: Integer;
  lLine: Integer;
  lName: string;
begin
  Inc(aIndex);
  while aIndex <= High(aTokens) do
  begin
    if aTokens[aIndex].fKind = smtSemicolon then
      Exit;
    if aTokens[aIndex].fKind <> smtIdentifier then
    begin
      Inc(aIndex);
      Continue;
    end;
    if SameText(aTokens[aIndex].fText, 'in') then
    begin
      Inc(aIndex);
      Continue;
    end;

    if TryReadDottedName(aTokens, aIndex, lName, lLine, lCol) then
      AddUse(aModel, lName, aSectionKind, lLine, lCol);
  end;
end;

procedure ExtractUnitModelFromTokens(const aSource: string; const aTokens: TArray<TSymbolMapToken>;
  var aModel: TSymbolMapUnitModel);
var
  lIndex: Integer;
  lNameCol: Integer;
  lNameLine: Integer;
  lSectionKind: string;
begin
  lSectionKind := '';
  lIndex := 0;
  while lIndex <= High(aTokens) do
  begin
    if aTokens[lIndex].fKind = smtIdentifier then
    begin
      if SameText(aTokens[lIndex].fText, 'unit') and (lIndex + 1 <= High(aTokens)) and
        (aTokens[lIndex + 1].fKind = smtIdentifier) then
      begin
        Inc(lIndex);
        TryReadDottedName(aTokens, lIndex, aModel.fUnitName, lNameLine, lNameCol);
        Continue;
      end;
      if SameText(aTokens[lIndex].fText, 'interface') then
        lSectionKind := 'interface'
      else if SameText(aTokens[lIndex].fText, 'implementation') then
        lSectionKind := 'implementation'
      else if SameText(aTokens[lIndex].fText, 'uses') then
        ParseUsesClause(aTokens, lIndex, lSectionKind, aModel)
      else if SameText(aTokens[lIndex].fText, 'type') then
      begin
        ParseTypeSection(aSource, aTokens, lIndex, lSectionKind, aModel);
        Continue;
      end else if SameText(aTokens[lIndex].fText, 'const') then
      begin
        ParseConstSection(aSource, aTokens, lIndex, lSectionKind, aModel);
        Continue;
      end else if SameText(aTokens[lIndex].fText, 'var') then
      begin
        ParseVarSection(aTokens, lIndex, lSectionKind, aModel);
        Continue;
      end else if SameText(aTokens[lIndex].fText, 'procedure') or SameText(aTokens[lIndex].fText, 'function') then
      begin
        ParseRoutineDeclaration(aSource, aTokens, lIndex, lSectionKind, aModel);
        if SameText(lSectionKind, 'implementation') then
          SkipImplementationRoutineBody(aTokens, lIndex);
        Continue;
      end;
    end;
    Inc(lIndex);
  end;
  if aModel.fUnitName = '' then
    AddDiagnostic(aModel, 'missing-unit-name');
end;

function TryExtractSymbolMapUnitModel(const aFilePath: string; out aModel: TSymbolMapUnitModel;
  out aError: string): Boolean;
var
  lOptions: TDelphiSemanticModelOptions;
  lLegacyModel: TSymbolMapUnitModel;
  lLegacyError: string;
  lSemanticDiagnostic: TDelphiSemanticModelDiagnostic;
  lSemanticModel: TDelphiSemanticUnitModel;
begin
  Result := False;
  aModel := Default(TSymbolMapUnitModel);
  aError := '';
  aModel.fFilePath := TPath.GetFullPath(aFilePath);

  lOptions := Default(TDelphiSemanticModelOptions);
  lOptions.SourceFileName := aModel.fFilePath;
  lOptions.ProjectContextApplied := False;
  lSemanticModel := TDelphiSemanticUnitModelExtractor.ExtractFromFile(lOptions);
  if not lSemanticModel.Success then
  begin
    if TryExtractLegacySymbolMapUnitModel(aFilePath, aModel, aError) then
      Exit(True);

    for lSemanticDiagnostic in lSemanticModel.Diagnostics do
      if lSemanticDiagnostic.Message <> '' then
      begin
        aError := lSemanticDiagnostic.Message;
        Break;
      end;
    if aError = '' then
      aError := 'Failed to extract Delphi semantic unit model.';
    Exit(False);
  end;

  aModel.fFilePath := lSemanticModel.FileName;
  aModel.fEncodingName := lSemanticModel.EncodingName;
  MergeDelphiSemanticModel(aModel, lSemanticModel);
  if TryExtractLegacySymbolMapUnitModel(aFilePath, lLegacyModel, lLegacyError) then
    MergeLegacyCompatibilityModel(aModel, lLegacyModel);
  Result := True;
end;

end.
