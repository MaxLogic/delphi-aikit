unit Dak.Analysis.JsonText;

{$SCOPEDENUMS ON}

interface

uses
  System.Classes, System.JSON, System.SysUtils;

type
  // Serializes JSON values exactly like Python's json.dumps with ensure_ascii=True:
  // escapes for control and non-ASCII characters, ', ' and ': ' separators on one line,
  // or two-space indentation with ',' item separators, optional code-point key sorting.
  // Numbers keep integer digits and print floats as Python repr (see TNumericText).
  TPythonJson = class sealed
  public
    // json.dumps(value, indent=2, sort_keys=True) plus the trailing newline of _write_json.
    class function Document(aValue: TJSONValue): string; static;
    // The same document written as Python's text mode does on Windows (UTF-8, CRLF) in bounded
    // chunks, so a large report never exists as one string.
    class procedure WriteDocument(aValue: TJSONValue; aStream: TStream); static;
    // json.dumps(value) for one JSONL row; the caller appends the line break.
    class function Line(aValue: TJSONValue): string; static;
    // json.dumps(value, sort_keys=True) on one line, as the CLI prints its verification result.
    class function SortedLine(aValue: TJSONValue): string; static;
    // json.dumps(value, sort_keys=True, separators=(',', ':')) as used for fingerprints.
    class function Compact(aValue: TJSONValue): string; static;
    // Lowercase SHA-256 of the compact form without materializing it.
    class function CompactSha256(aValue: TJSONValue): string; static;
    class function QuoteString(const aText: string): string; static;
  end;

  // An array whose elements are produced while it is rendered and freed right after, so a large
  // document never exists in memory at once. Only rendering reads it; it renders once and its
  // element count stays 0. The producer returns nil when exhausted.
  TJsonStreamedArray = class(TJSONValue)
  private
    fNext: TFunc<TJSONValue>;
    fProducer: TObject;
    fRendered: Integer;
  protected
    // The RTL's own serializers see an empty array; only TPythonJson renders the elements.
    function EstimatedByteSize: Integer; override;
    function ToBytes(const aData: TArray<Byte>; aOffset: Integer): Integer; override;
    procedure ToChars(aBuilder: TStringBuilder; aOptions: TJSONAncestor.TJSONOutputOptions); override;
  public
    // aProducer is owned and freed with the array; it typically backs aNext.
    constructor Create(aProducer: TObject; const aNext: TFunc<TJSONValue>); reintroduce;
    destructor Destroy; override;
    function Clone: TJSONAncestor; override;
    // Elements rendered so far.
    property Rendered: Integer read fRendered;
  end;

implementation

uses
  System.Generics.Collections, System.Generics.Defaults, System.Hash,
  Dak.Analysis.NumericText;

type
  TJsonLayout = record
    Indent: Integer;        // 0 = single line
    SortKeys: Boolean;
    ItemSeparator: string;
    KeySeparator: string;
  end;

  // Rendering target: an in-memory string, a text-mode stream, or a running hash. The rendered
  // text is pure ASCII (ensure_ascii), so chunks may be cut between any two appends.
  TJsonSink = class
  private
    fBuilder: TStringBuilder;
    fHash: THashSHA2;
    fHashing: Boolean;
    fPrevious: Char;
    fStream: TStream;
    procedure FlushIfLarge;
    procedure Flush;
  public
    constructor Create(aStream: TStream; aHashing: Boolean);
    destructor Destroy; override;
    procedure Append(const aText: string); overload;
    procedure Append(aChar: Char); overload;
    procedure Append(aChar: Char; aCount: Integer); overload;
    function Text: string;
    function HashHex: string;
  end;

const
  cSinkChunkChars = 65536;

constructor TJsonStreamedArray.Create(aProducer: TObject; const aNext: TFunc<TJSONValue>);
begin
  inherited Create;
  fProducer := aProducer;
  fNext := aNext;
end;

destructor TJsonStreamedArray.Destroy;
begin
  fNext := nil;
  fProducer.Free;
  inherited;
end;

function TJsonStreamedArray.EstimatedByteSize: Integer;
begin
  Result := 2;
end;

function TJsonStreamedArray.ToBytes(const aData: TArray<Byte>; aOffset: Integer): Integer;
begin
  aData[aOffset] := Ord('[');
  aData[aOffset + 1] := Ord(']');
  Result := aOffset + 2;
end;

procedure TJsonStreamedArray.ToChars(aBuilder: TStringBuilder; aOptions: TJSONAncestor.TJSONOutputOptions);
begin
  aBuilder.Append('[]');
end;

function TJsonStreamedArray.Clone: TJSONAncestor;
begin
  Result := TJSONArray.Create;
end;

var
  // One comparer for every rendered object instead of a closure per object.
  GPairKeyComparer: IComparer<TJSONPair>;

function ComparePairKeys(const aLeft, aRight: TJSONPair): Integer;
begin
  Result := CompareStr(aLeft.JsonString.Value, aRight.JsonString.Value);
end;

constructor TJsonSink.Create(aStream: TStream; aHashing: Boolean);
begin
  inherited Create;
  fStream := aStream;
  fHashing := aHashing;
  fBuilder := TStringBuilder.Create;
  if fHashing then
    fHash := THashSHA2.Create;
end;

destructor TJsonSink.Destroy;
begin
  fBuilder.Free;
  inherited;
end;

procedure TJsonSink.Append(const aText: string);
begin
  fBuilder.Append(aText);
  FlushIfLarge;
end;

procedure TJsonSink.Append(aChar: Char);
begin
  fBuilder.Append(aChar);
  FlushIfLarge;
end;

procedure TJsonSink.Append(aChar: Char; aCount: Integer);
begin
  fBuilder.Append(aChar, aCount);
  FlushIfLarge;
end;

procedure TJsonSink.FlushIfLarge;
begin
  if ((fStream <> nil) or fHashing) and (fBuilder.Length >= cSinkChunkChars) then
    Flush;
end;

procedure TJsonSink.Flush;
var
  lBytes: TBytes;
  lChunk: TStringBuilder;
  i: Integer;
  c: Char;
begin
  if fBuilder.Length = 0 then
    Exit;
  if fHashing then
    fHash.Update(TEncoding.UTF8.GetBytes(fBuilder.ToString))
  else begin
    // Python text mode: each LF becomes CRLF; an LF already preceded by CR keeps that CR.
    lChunk := TStringBuilder.Create(fBuilder.Length + fBuilder.Length div 16);
    try
      for i := 0 to fBuilder.Length - 1 do
      begin
        c := fBuilder.Chars[i];
        if (c = #10) and (fPrevious <> #13) then
          lChunk.Append(#13);
        lChunk.Append(c);
        fPrevious := c;
      end;
      lBytes := TEncoding.UTF8.GetBytes(lChunk.ToString);
    finally
      lChunk.Free;
    end;
    if Length(lBytes) > 0 then
      fStream.WriteBuffer(lBytes[0], Length(lBytes));
  end;
  fBuilder.Length := 0;
end;

function TJsonSink.Text: string;
begin
  Result := fBuilder.ToString;
end;

function TJsonSink.HashHex: string;
begin
  Flush;
  Result := LowerCase(fHash.HashAsString);
end;

class function TPythonJson.QuoteString(const aText: string): string;
var
  c: Char;
  lBuilder: TStringBuilder;
  lPlain: Boolean;
begin
  // Most values need no escape at all; quote them without a builder.
  lPlain := True;
  for c in aText do
    if (Ord(c) < $20) or (Ord(c) > $7E) or (c = '"') or (c = '\') then
    begin
      lPlain := False;
      Break;
    end;
  if lPlain then
    Exit('"' + aText + '"');
  lBuilder := TStringBuilder.Create(Length(aText) + 2);
  try
    lBuilder.Append('"');
    for c in aText do
    begin
      case c of
        '"': lBuilder.Append('\"');
        '\': lBuilder.Append('\\');
        #10: lBuilder.Append('\n');
        #13: lBuilder.Append('\r');
        #9: lBuilder.Append('\t');
        #8: lBuilder.Append('\b');
        #12: lBuilder.Append('\f');
      else
        // ensure_ascii escapes everything outside 0x20..0x7E; lone surrogates escape as-is.
        if (Ord(c) < $20) or (Ord(c) > $7E) then
          lBuilder.Append('\u').Append(IntToHex(Ord(c), 4).ToLowerInvariant)
        else
          lBuilder.Append(c);
      end;
    end;
    lBuilder.Append('"');
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

// json.dumps prints float infinities as Infinity/-Infinity (allow_nan), unlike repr.
function JsonNumberText(const aToken: string): string;
begin
  Result := TNumericText.PythonText(aToken);
  if Result = 'inf' then
    Result := 'Infinity'
  else if Result = '-inf' then
    Result := '-Infinity';
end;

procedure AppendValue(aBuilder: TJsonSink; aValue: TJSONValue; const aLayout: TJsonLayout; aLevel: Integer);

  procedure NewLine(aDepth: Integer);
  begin
    if aLayout.Indent > 0 then
    begin
      aBuilder.Append(#10);
      aBuilder.Append(' ', aLayout.Indent * aDepth);
    end;
  end;

var
  i: Integer;
  lArray: TJSONArray;
  lItem: TJSONValue;
  lObject: TJSONObject;
  lPairs: TList<TJSONPair>;
begin
  if (aValue = nil) or (aValue is TJSONNull) then
    aBuilder.Append('null')
  else if aValue is TJSONBool then
  begin
    if TJSONBool(aValue).AsBoolean then
      aBuilder.Append('true')
    else
      aBuilder.Append('false');
  end else if aValue is TJSONNumber then
    aBuilder.Append(JsonNumberText(aValue.Value))
  else if aValue is TJSONString then
    aBuilder.Append(TPythonJson.QuoteString(aValue.Value))
  else if aValue is TJsonStreamedArray then
  begin
    lItem := TJsonStreamedArray(aValue).fNext();
    if lItem = nil then
    begin
      aBuilder.Append('[]');
      Exit;
    end;
    aBuilder.Append('[');
    i := 0;
    while lItem <> nil do
    begin
      if i > 0 then
        aBuilder.Append(aLayout.ItemSeparator);
      NewLine(aLevel + 1);
      try
        AppendValue(aBuilder, lItem, aLayout, aLevel + 1);
      finally
        lItem.Free;
      end;
      Inc(i);
      Inc(TJsonStreamedArray(aValue).fRendered);
      lItem := TJsonStreamedArray(aValue).fNext();
    end;
    NewLine(aLevel);
    aBuilder.Append(']');
  end else if aValue is TJSONArray then
  begin
    lArray := TJSONArray(aValue);
    if lArray.Count = 0 then
    begin
      aBuilder.Append('[]');
      Exit;
    end;
    aBuilder.Append('[');
    for i := 0 to lArray.Count - 1 do
    begin
      if i > 0 then
        aBuilder.Append(aLayout.ItemSeparator);
      NewLine(aLevel + 1);
      AppendValue(aBuilder, lArray.Items[i], aLayout, aLevel + 1);
    end;
    NewLine(aLevel);
    aBuilder.Append(']');
  end else if aValue is TJSONObject then
  begin
    lObject := TJSONObject(aValue);
    if lObject.Count = 0 then
    begin
      aBuilder.Append('{}');
      Exit;
    end;
    lPairs := TList<TJSONPair>.Create;
    try
      for i := 0 to lObject.Count - 1 do
        lPairs.Add(lObject.Pairs[i]);
      if aLayout.SortKeys then
        // Python compares str keys by code point; ordinal comparison matches that.
        lPairs.Sort(GPairKeyComparer);
      aBuilder.Append('{');
      for i := 0 to lPairs.Count - 1 do
      begin
        if i > 0 then
          aBuilder.Append(aLayout.ItemSeparator);
        NewLine(aLevel + 1);
        aBuilder.Append(TPythonJson.QuoteString(lPairs[i].JsonString.Value));
        aBuilder.Append(aLayout.KeySeparator);
        AppendValue(aBuilder, lPairs[i].JsonValue, aLayout, aLevel + 1);
      end;
      NewLine(aLevel);
      aBuilder.Append('}');
    finally
      lPairs.Free;
    end;
  end else
    raise EArgumentException.Create('Unsupported JSON value class: ' + aValue.ClassName);
end;

function Render(aValue: TJSONValue; const aLayout: TJsonLayout): string;
var
  lSink: TJsonSink;
begin
  lSink := TJsonSink.Create(nil, False);
  try
    AppendValue(lSink, aValue, aLayout, 0);
    Result := lSink.Text;
  finally
    lSink.Free;
  end;
end;

function DocumentLayout: TJsonLayout;
begin
  Result.Indent := 2;
  Result.SortKeys := True;
  Result.ItemSeparator := ',';
  Result.KeySeparator := ': ';
end;

function CompactLayout: TJsonLayout;
begin
  Result.Indent := 0;
  Result.SortKeys := True;
  Result.ItemSeparator := ',';
  Result.KeySeparator := ':';
end;

class procedure TPythonJson.WriteDocument(aValue: TJSONValue; aStream: TStream);
var
  lSink: TJsonSink;
begin
  lSink := TJsonSink.Create(aStream, False);
  try
    AppendValue(lSink, aValue, DocumentLayout, 0);
    lSink.Append(#10);
    lSink.Flush;
  finally
    lSink.Free;
  end;
end;

class function TPythonJson.CompactSha256(aValue: TJSONValue): string;
var
  lSink: TJsonSink;
begin
  lSink := TJsonSink.Create(nil, True);
  try
    AppendValue(lSink, aValue, CompactLayout, 0);
    Result := lSink.HashHex;
  finally
    lSink.Free;
  end;
end;

class function TPythonJson.Document(aValue: TJSONValue): string;
begin
  Result := Render(aValue, DocumentLayout) + #10;
end;

class function TPythonJson.Line(aValue: TJSONValue): string;
var
  lLayout: TJsonLayout;
begin
  lLayout.Indent := 0;
  lLayout.SortKeys := False;
  lLayout.ItemSeparator := ', ';
  lLayout.KeySeparator := ': ';
  Result := Render(aValue, lLayout);
end;

class function TPythonJson.SortedLine(aValue: TJSONValue): string;
var
  lLayout: TJsonLayout;
begin
  lLayout.Indent := 0;
  lLayout.SortKeys := True;
  lLayout.ItemSeparator := ', ';
  lLayout.KeySeparator := ': ';
  Result := Render(aValue, lLayout);
end;

class function TPythonJson.Compact(aValue: TJSONValue): string;
begin
  Result := Render(aValue, CompactLayout);
end;

initialization
  GPairKeyComparer := TComparer<TJSONPair>.Construct(ComparePairKeys);

end.
