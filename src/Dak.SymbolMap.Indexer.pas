unit Dak.SymbolMap.Indexer;

interface

type
  TSymbolMapUnitUse = record
    fUnitName: string;
    fSectionKind: string;
    fLine: Integer;
    fCol: Integer;
  end;

  TSymbolMapUnitModel = record
    fUnitName: string;
    fFilePath: string;
    fEncodingName: string;
    fUses: TArray<TSymbolMapUnitUse>;
    fDiagnostics: TArray<string>;
  end;

function TryLoadSymbolMapSourceFile(const aFilePath: string; out aText, aEncodingName, aError: string): Boolean;
function TryExtractSymbolMapUnitModel(const aFilePath: string; out aModel: TSymbolMapUnitModel;
  out aError: string): Boolean;

implementation

uses
  System.IOUtils, System.SysUtils;

type
  TSymbolMapTokenKind = (smtIdentifier, smtDot, smtComma, smtSemicolon);

  TSymbolMapToken = record
    fKind: TSymbolMapTokenKind;
    fText: string;
    fLine: Integer;
    fCol: Integer;
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
  const aLine, aCol: Integer);
var
  lIndex: Integer;
begin
  lIndex := Length(aTokens);
  SetLength(aTokens, lIndex + 1);
  aTokens[lIndex].fKind := aKind;
  aTokens[lIndex].fText := aText;
  aTokens[lIndex].fLine := aLine;
  aTokens[lIndex].fCol := aCol;
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
      AddToken(aTokens, smtIdentifier, Copy(aText, lStart, lIndex - lStart), lLine, lStartCol);
      Continue;
    end;

    case lChar of
      '.':
        AddToken(aTokens, smtDot, lChar, lLine, lCol);
      ',':
        AddToken(aTokens, smtComma, lChar, lLine, lCol);
      ';':
        AddToken(aTokens, smtSemicolon, lChar, lLine, lCol);
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

procedure ExtractUnitModelFromTokens(const aTokens: TArray<TSymbolMapToken>; var aModel: TSymbolMapUnitModel);
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
        ParseUsesClause(aTokens, lIndex, lSectionKind, aModel);
    end;
    Inc(lIndex);
  end;
  if aModel.fUnitName = '' then
    AddDiagnostic(aModel, 'missing-unit-name');
end;

function TryExtractSymbolMapUnitModel(const aFilePath: string; out aModel: TSymbolMapUnitModel;
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
  ExtractUnitModelFromTokens(lTokens, aModel);
  Result := True;
end;

end.
