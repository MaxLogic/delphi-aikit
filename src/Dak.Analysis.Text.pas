unit Dak.Analysis.Text;

interface

// UTF-8 BOM and replacement decoding shared by legacy report/context adapters.
function ReadAnalysisText(const aPath: string): string;

implementation

uses
  System.Character, System.IOUtils, System.SysUtils;

function DecodeMalformedUtf8(const aBytes: TBytes; aOffset: Integer): string;
var
  lBuilder: TStringBuilder;
  lCount: Integer;
  lLead: Byte;
  lNext: Byte;
  lPosition: Integer;
  lValue: UCS4Char;
  lWidth: Integer;
begin
  lBuilder := TStringBuilder.Create(Length(aBytes) - aOffset);
  try
    lPosition := aOffset;
    while lPosition < Length(aBytes) do
    begin
      lLead := aBytes[lPosition];
      if lLead < $80 then
      begin
        lBuilder.Append(Char(lLead));
        Inc(lPosition);
        Continue;
      end;
      case lLead of
        $C2..$DF:
          begin
            lWidth := 2;
            lValue := lLead and $1F;
          end;
        $E0..$EF:
          begin
            lWidth := 3;
            lValue := lLead and $0F;
          end;
        $F0..$F4:
          begin
            lWidth := 4;
            lValue := lLead and $07;
          end;
      else
        lBuilder.Append(Char($FFFD));
        Inc(lPosition);
        Continue;
      end;
      lCount := 1;
      while (lCount < lWidth) and (lPosition + lCount < Length(aBytes)) do
      begin
        lNext := aBytes[lPosition + lCount];
        if (lNext and $C0) <> $80 then
          Break;
        if (lCount = 1) and (((lLead = $E0) and (lNext < $A0)) or
          ((lLead = $ED) and (lNext > $9F)) or ((lLead = $F0) and (lNext < $90)) or
          ((lLead = $F4) and (lNext > $8F))) then
          Break;
        lValue := (lValue shl 6) or (lNext and $3F);
        Inc(lCount);
      end;
      if lCount = lWidth then
        lBuilder.Append(Char.ConvertFromUtf32(lValue))
      else
        // Replace only the valid prefix; the offending byte starts the next decoding attempt.
        lBuilder.Append(Char($FFFD));
      Inc(lPosition, lCount);
    end;
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

function ReadAnalysisText(const aPath: string): string;
var
  lBytes: TBytes;
  lLength: Integer;
  lOffset: Integer;
begin
  lBytes := TFile.ReadAllBytes(aPath);
  lOffset := 0;
  if (Length(lBytes) >= 3) and (lBytes[0] = $EF) and (lBytes[1] = $BB) and (lBytes[2] = $BF) then
    lOffset := 3;
  lLength := Length(lBytes) - lOffset;
  if lLength = 0 then
    Exit('');
  if TEncoding.UTF8.IsBufferValid(@lBytes[lOffset], lLength) then
    Result := TEncoding.UTF8.GetString(lBytes, lOffset, lLength)
  else
    // Windows flags=0 groups invalid sequences differently from the retained Python reader.
    Result := DecodeMalformedUtf8(lBytes, lOffset);
end;

end.
