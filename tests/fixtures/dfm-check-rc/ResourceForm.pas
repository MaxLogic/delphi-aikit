unit ResourceForm;

interface

uses
  System.Classes,
  Vcl.Forms;

type
  TResourceForm = class(TForm);

implementation

{$IFDEF NEED_PAYLOAD}
uses
  ResourcePayload;
{$ENDIF}

{$R *.dfm}

end.
