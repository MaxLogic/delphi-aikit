unit Dak.MsBuild.Args;

// DAK-373: the single rule for putting a value on an MSBuild command line, shared by `build` and `dfm-check`.

interface

// MSBuild parses its own command line. An unquoted ';' or ',' ends a /p: value and the text after it is
// rejected as a property without a name (MSB1006). Inside quotes a backslash run before a quote is halved and
// \" is a literal quote, so a trailing backslash is doubled; otherwise it would escape the closing quote and
// swallow the following arguments. Values without those shapes are returned unchanged.
function QuoteMsBuildPropertyValue(const aValue: string): string;

// Renders one global property argument: /p:Name=Value, with the value quoted by QuoteMsBuildPropertyValue.
function FormatMsBuildProperty(const aName, aValue: string): string;

implementation

uses
  System.SysUtils;

function QuoteMsBuildPropertyValue(const aValue: string): string;
var
  c: Char;
  lBackslashes: Integer;
begin
  if (aValue <> '') and (aValue.IndexOfAny([' ', #9, '"', ';', ',']) < 0) then
    Exit(aValue);

  Result := '"';
  lBackslashes := 0;
  for c in aValue do
  begin
    if c = '\' then
      Inc(lBackslashes)
    else begin
      if c = '"' then
        Result := Result + StringOfChar('\', lBackslashes + 1);
      lBackslashes := 0;
    end;
    Result := Result + c;
  end;
  Result := Result + StringOfChar('\', lBackslashes) + '"';
end;

function FormatMsBuildProperty(const aName, aValue: string): string;
begin
  Result := '/p:' + aName + '=' + QuoteMsBuildPropertyValue(aValue);
end;

end.
