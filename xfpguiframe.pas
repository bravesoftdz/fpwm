unit XfpGUIFrame;

{$mode objfpc}{$H+}

interface

uses
  { FCL RTL }
  Classes,
  { X Stuff }
  X, XLib,
  { fpGUI units}
  fpGUI, GfxBase, Gfx_X11,
  { program units }
  BaseWM,
  XfpGUIWM, XFrames;

type
  { TfpGUIFrame }

  TfpGUIFrame = class(TXFrame)
  private
    fForm: TForm;
    fBox: TGridLayout;
    fTitleLabel: TLabel;
    fCloseBttn,
    fMinimizeBttn,
    fRestoreBttn: TButton;
    procedure CloseClick(Sender: TObject);
    procedure SetCaption(const AValue: String); override;
  public
   constructor Create(AOwner: TBaseWindowManager; AClientWindow: TWindow; AFrameWindow: TWindow); override;
   property Form: TForm read fForm;
  end;

implementation

{ TfpGUIFrame }

procedure TfpGUIFrame.CloseClick(Sender: TObject);
begin
  TfpGUIWindowManager(Owner).CloseWindowNice(ClientWindow);
end;

procedure TfpGUIFrame.SetCaption(const AValue: String);
begin
  inherited SetCaption(AValue);
  fTitleLabel.Text := AValue;
end;

constructor TfpGUIFrame.Create(AOwner: TBaseWindowManager; AClientWindow: TWindow; AFrameWindow: TWindow);
begin
  fForm := TForm.Create(nil);
  fForm.WindowOptions := [woBorderless, woX11SkipWMHints];
  fBox := TGridLayout.Create(fForm);
  fBox.Parent := fForm;
  fBox.ColCount := 4;
  fBox.RowCount := 2;

  fTitleLabel := TLabel.Create(Caption,fForm);

  fBox.AddWidget(fTitleLabel,1,0,1,1);
  fCloseBttn := TButton.Create('X', fForm);
  fCloseBttn.SetBounds(1,0,20,20);
  fCloseBttn.Embedded := True;

  fBox.AddWidget(fCloseBttn, 3,0,1,1);
  //fCloseBttn.SetBounds(60, 3, 20,20);
  fCloseBttn.OnClick := @CloseClick;
  // create the TWindow that is the frame
  inherited Create(AOwner, AClientWindow, TXWindow(Form.Wnd).Handle);
end;

end.

