unit Dak.Analysis.ProjectSources;

interface

// Inputs are absolute subject/project paths from the saved analysis context.
// A malformed project retains the subject identities and returns its diagnostic.
function CollectAnalysisProjectSources(const aSubjectPath, aProjectPath: string;
  out aDiagnostic: string): TArray<string>;

implementation

uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.IOUtils,
  System.SysUtils, System.Variants,
  Xml.omnixmldom, Xml.XMLDoc, Xml.xmldom, Xml.XMLIntf,
  Dak.Analysis.Workspace;

function TryLoadProject(const aPath: string; out aDocument: IXMLDocument;
  out aDiagnostic: string): Boolean;
var
  lXml: TXMLDocument;
begin
  aDiagnostic := '';
  Result := False;
  lXml := TXMLDocument.Create(nil);
  aDocument := lXml;
  lXml.DOMVendor := GetDOMVendor(sOmniXmlVendor);
  try
    aDocument.LoadFromFile(aPath);
    Result := aDocument.DocumentElement <> nil;
    if not Result then
      aDiagnostic := 'Project XML has no document element: ' + aPath;
  except
    on e: EDOMParseError do
      aDiagnostic := e.Message;
    on e: EXMLDocError do
      aDiagnostic := e.Message;
    on e: DOMException do
      aDiagnostic := e.Message;
    on e: EStreamError do
      aDiagnostic := e.Message;
    on e: EInOutError do
      aDiagnostic := e.Message;
  end;
end;

function CollectAnalysisProjectSources(const aSubjectPath, aProjectPath: string;
  out aDiagnostic: string): TArray<string>;
var
  i: Integer;
  lDocument: IXMLDocument;
  lInclude: string;
  lNode: IXMLNode;
  lPath: string;
  lPaths: TDictionary<string, Byte>;
  lPending: TStack<IXMLNode>;
begin
  aDiagnostic := '';
  lPaths := TDictionary<string, Byte>.Create(TIStringComparer.Ordinal);
  try
    for lPath in [aSubjectPath, aProjectPath] do
      if (lPath <> '') and (TFile.Exists(lPath) or TDirectory.Exists(lPath)) then
        lPaths.AddOrSetValue(ResolveFilesystemPath(lPath), 0);
    if TFile.Exists(aProjectPath) and TryLoadProject(aProjectPath, lDocument, aDiagnostic) then
    begin
      lPending := TStack<IXMLNode>.Create;
      try
        lPending.Push(lDocument.DocumentElement);
        while lPending.Count > 0 do
        begin
          lNode := lPending.Pop;
          if (lNode.LocalName = 'DCCReference') and lNode.HasAttribute('Include') then
          begin
            lInclude := VarToStr(lNode.Attributes['Include']).Trim;
            if lInclude <> '' then
            begin
              // Replay describes the recorded project, not an active MSBuild configuration.
              // Conditions and property expressions are deliberately not evaluated here.
              lPath := TPath.Combine(TPath.GetDirectoryName(aProjectPath), lInclude);
              if TFile.Exists(lPath) then
                lPaths.AddOrSetValue(ResolveFilesystemPath(lPath), 0);
            end;
          end;
          for i := lNode.ChildNodes.Count - 1 downto 0 do
            lPending.Push(lNode.ChildNodes[i]);
        end;
      finally
        lPending.Free;
      end;
    end;
    Result := lPaths.Keys.ToArray;
    TArray.Sort<string>(Result, TStringComparer.Ordinal);
  finally
    lPaths.Free;
  end;
end;

end.
