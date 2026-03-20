object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Main Form'
  ClientHeight = 240
  ClientWidth = 320
  OnCreate = FormCreate
  object pnlMain: TPanel
    Align = alClient
    TabOrder = 0
    object BtnSave: TButton
      Left = 16
      Top = 24
      Width = 75
      Height = 25
      Caption = 'Save'
      TabOrder = 0
      OnClick = BtnSaveClick
    end
    object EditName: TEdit
      Left = 16
      Top = 64
      Width = 121
      Height = 21
      TabOrder = 1
      Text = 'Alice'
    end
  end
end
