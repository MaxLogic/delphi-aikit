unit Dak.PascalAnalyzer.Help;

interface

type
  TPalHelpInfo = record
    fVersion: string;
    fArchitecture: string;
    fHelpAvailable: Boolean;
    fSupportedFlags: TArray<string>;
  end;

function ParsePalHelp(const aText: string): TPalHelpInfo;
function PalHelpSupportsTarget(const aInfo: TPalHelpInfo; const aFlag: string): Boolean;
function PalHelpContainsFlag(const aText, aFlag: string): Boolean;

implementation

uses
  System.RegularExpressions, System.StrUtils, System.SysUtils;

function ParsePalHelp(const aText: string): TPalHelpInfo;
const
  cFlags: array[0..3] of string = ('/CD12W32', '/CD12W64', '/CD13W32', '/CD13W64');
var
  lCount: Integer;
  lFlag: string;
  lMatch: TMatch;
begin
  Result := Default(TPalHelpInfo);
  Result.fVersion := 'unknown';
  Result.fArchitecture := 'unknown';
  // UCP retains the Python reference's Unicode whitespace/digit/word semantics.
  lMatch := TRegEx.Match(aText, '(*UCP)Pascal Analyzer\s+\((\d+)-bits\)\s+version\s+([0-9.]+)',
    [roIgnoreCase]);
  if lMatch.Success then
  begin
    Result.fArchitecture := lMatch.Groups[1].Value + '-bit';
    Result.fVersion := lMatch.Groups[2].Value;
  end;
  Result.fHelpAvailable := Pos('Syntax:', aText) > 0;
  SetLength(Result.fSupportedFlags, Length(cFlags));
  lCount := 0;
  // Doctor's fixed display list and line-start matching differ from runner flag containment.
  for lFlag in cFlags do
    if TRegEx.IsMatch(aText, '(*UCP)^\s*' + TRegEx.Escape(lFlag) + '\b', [roIgnoreCase, roMultiLine]) then
    begin
      Result.fSupportedFlags[lCount] := lFlag;
      Inc(lCount);
    end;
  SetLength(Result.fSupportedFlags, lCount);
end;

function PalHelpSupportsTarget(const aInfo: TPalHelpInfo; const aFlag: string): Boolean;
var
  lFlag: string;
begin
  if aFlag = '' then
    Exit(False);
  for lFlag in aInfo.fSupportedFlags do
    if lFlag = aFlag then
      Exit(True);
  Result := False;
end;

function PalHelpContainsFlag(const aText, aFlag: string): Boolean;
var
  lAfter: Char;
  lBefore: Char;
  lFlag: string;
  lPos: Integer;
  lText: string;
begin
  // Preserve the existing runner's ASCII alphanumeric boundaries, including underscore behavior.
  if (aText = '') or (aFlag = '') then
    Exit(False);
  lText := UpperCase(aText);
  lFlag := UpperCase(aFlag);
  lPos := Pos(lFlag, lText);
  while lPos > 0 do
  begin
    if lPos = 1 then
      lBefore := #0
    else
      lBefore := lText[lPos - 1];
    if (lPos + Length(lFlag)) > Length(lText) then
      lAfter := #0
    else
      lAfter := lText[lPos + Length(lFlag)];
    if not CharInSet(lBefore, ['A'..'Z', '0'..'9']) and not CharInSet(lAfter, ['A'..'Z', '0'..'9']) then
      Exit(True);
    lPos := PosEx(lFlag, lText, lPos + 1);
  end;
  Result := False;
end;

end.
