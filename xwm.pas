unit XWM;

{$mode objfpc}{$H+}

interface

uses
  Classes, Sysutils, fpGui, X, Xlib, XAtom, ctypes, BaseWM, XRootWindow,
  XFrames, NETAtoms, XAtoms;
  
type

  { TXWindowManager }
  
  // This class will do the 'dirty' work of managing the window and will have
  // abstract methods for descendants to implement. i.e. TfpGUIWindowManager or so
  // all painting will be done in a descendant
  TXWindowManager = class(TBaseWindowManager)
  private
    fQuit: Boolean;
    fDisplay: PXDisplay;
    fRootWindowList: TWMRootWindowList;
    fLastErrorHandler: TXErrorHandler;
    fNetAtoms: TNetAtoms;
    function GrabRootWindows: Boolean;
  public
    constructor Create(const ADisplayName: String); virtual;
    destructor Destroy; override;
    function WindowToFrame(const AWindow: TWindow): TXFrame;
    procedure CreateDisplay(ADisplayName: String); virtual;
    procedure InitWM(QueryWindows: Boolean = True); override;
    procedure MainLoop; override;
    function XEventCB(const AEvent: TXEvent): Boolean; virtual;
    // create and destroy frame windows
    function CreateNewWindowFrame(Sender: TWMRootWindow; const AScreen: PScreen; const AChild: TWindow): TXFrame; virtual; abstract;
    procedure DestroyWindowFrame(var AWindow: TXFrame); virtual; abstract;
    // procedures to handle windows
    procedure ConfigureWindow(const AWindow: TXFrame; const AConfigureEv: TXConfigureRequestEvent); virtual;
    procedure MapWindow(const AWindow: TXFrame); virtual;
    procedure MoveWindow(const AWindow: TXFrame; APosition: TPoint); virtual;
    procedure ResizeWindow(const AWindow: TXFrame; AWidth, AHeight: Integer); virtual;
    procedure PaintWindowFrame(AFrame: TXFrame); virtual; abstract;
    function  CloseWindowNice(const AWindow: TWindow): Boolean; virtual;
    procedure CloseWindowDirty(const AWindow: TWindow); virtual;
    // methods to send clients messages
    procedure SendXMessage(const ADestWindow; AMessage: PXEvent; AMask: LongWord);
    procedure SendXClientMessage(const ADestWindow: TWindow; AType: TAtom);
    // methods responding to ClientMessages
    function HandleClientMessage(const AWindow: TXFrame; const AClientEv: TXClientMessageEvent): Boolean; virtual;
    procedure NetWMMoveResize(const AWindow: TXFrame; XOffset, YOffset: Integer; Direction: Integer; Button: Integer; FromApp: Boolean); virtual; abstract;
    procedure NetCloseWindow(const AWindow: TXFrame; ATimeStamp: Integer; FromApp: Boolean); virtual; abstract;
    // manage window properties
    procedure ChangeWindowProperty(AWindow: TWindow; AProperty: TAtom;
                AType: TAtom; AFormat: cint; AMode: cint; const AData: Pointer; Elements: cint);
    procedure DeleteWindowProperty(AWindow: TWindow; AProperty: TAtom);
    function WindowSupportsProto(AWindow: TWindow; AProto: TAtom): Boolean;
    // procedures to initialize the ICCCM and Extended WM hints
    procedure InitICCCMHints; virtual;
    procedure InitNETHints; virtual;
    procedure InitAtoms; virtual;
    property Display: PXDisplay read fDisplay write fDisplay;
    property _NET: TNetAtoms read fNetAtoms;
    property RootWindows: TWMRootWindowList read fRootWindowList;
  end;
  
const WindowManagerEventMask = SubstructureRedirectMask or SubstructureNotifyMask or
                                          ColormapChangeMask or EnterWindowMask;

implementation


// Creates an exception
function X11_Error(Display :PXDisplay; ErrEvent :PXErrorEvent):cint; cdecl;
var
 ErrorStr: String;
 e: Exception;
begin
  Result := 0;
  SetLength(ErrorStr, 1024);
  XGetErrorText(Display, ErrEvent^.error_code, @ErrorStr[1], 1024);
  e := Exception.Create(ErrorStr);
  raise E;
  e.Free;
end;

{ TXWindowManager }

{
  Returns True for success
}
function TXWindowManager.GrabRootWindows: Boolean;
var
  Attributes: TXSetWindowAttributes;
  I: Integer;
  AWindow: TWindow;
  ARootWindow: TWMRootWindow;
begin
  Result := False;
  for I := 0 to XScreenCount(fDisplay)-1 do begin
    AWindow := RootWindow(fDisplay, I);
    FillChar(Attributes, SizeOf(TXSetWindowAttributes), 0);
    // Set the event mask for the root window
    Attributes.event_mask := WindowManagerEventMask;
    try
      XChangeWindowAttributes(fDisplay, AWindow, CWEventMask, @Attributes);
      Result := True;
      ARootWindow := TWMRootWindow.Create(Self, XScreenOfDisplay(fDisplay, I), AWindow);
      fRootWindowList.Add(ARootWindow);
    except
      Result := False;
    end;
  end;
end;

procedure TXWindowManager.CreateDisplay(ADisplayName: String);
begin
  fDisplay := XOpenDisplay(PChar(ADisplayName));
end;

constructor TXWindowManager.Create(const ADisplayName: String);
begin
  fLastErrorHandler := XSetErrorHandler(@X11_Error);
  fRootWindowList := TWMRootWindowList.Create;
  CreateDisplay(ADisplayName);
  InitAtoms;
end;

destructor TXWindowManager.Destroy;
begin
  fRootWindowList.Free;
  if Assigned(fDisplay) then XCloseDisplay(fDisplay);
  inherited Destroy;
end;


// finds our TXFrame from a TWindow
function TXWindowManager.WindowToFrame(const AWindow: TWindow): TXFrame;
var
  I: Integer;
  J: Integer;
  Frames: TXFrameList;
begin
  Result := nil;
  for I := 0 to RootWindows.Count-1 do begin
    Frames := RootWindows.Windows[I].Frames;
    for J := 0 to Frames.Count-1 do begin
      if (Frames.Frame[J].ClientWindow = AWindow)
      or (Frames.Frame[J].FrameWindow = AWindow)
      then Exit(Frames.Frame[J]);
    end;
  end;
end;

procedure TXWindowManager.InitWM(QueryWindows: Boolean = True);
var
  I: Integer;
begin
  if not GrabRootWindows then exit;

  // Look for windows which need to be managed and add them to the list;
  if QueryWindows then begin
    for I := 0 to fRootWindowList.Count-1 do
      fRootWindowList.Windows[I].GrabExistingWindows;
  end;
end;

procedure TXWindowManager.MainLoop;
begin
  Application.Run;
end;

function TXWindowManager.XEventCB(const AEvent: TXEvent): Boolean;
var
  Frame: TXFrame;
  RootWindow: TWMRootWindow;
begin
  Result := False;
  //Return True to stop the event from being handled by the toolkit
  case AEvent._type of
    ConfigureRequest:
      begin
        Frame := WindowToFrame(AEvent.xconfigurerequest.window);
        RootWindow := RootWindows.RootWindowFromXWindow(AEvent.xmaprequest.parent);
        if  (Frame = nil) and (RootWindow <> nil)
        then
          Frame := RootWindow.AddNewClient(AEvent.xmaprequest.window);
        if Frame <> nil then
          ConfigureWindow(Frame, AEvent.xconfigurerequest);
        Result := True;
      end;
    MapRequest:
      begin
        Frame := WindowToFrame(AEvent.xconfigurerequest.window);
        if Frame <> nil then begin
          MapWindow(Frame);
          Result := True;
        end;
      end;
    ClientMessage:
      begin
        Frame := WindowToFrame(AEvent.xclient.window);
        if Frame <> nil then begin
          Result := HandleClientMessage(Frame, AEvent.xclient);
        end;
      end;
    //MapNotify:;
    //UnmapNotify:;
    //CreateNotify:;// do we need to do anything here?
    DestroyNotify:
      begin
        Frame := WindowToFrame(AEvent.xdestroywindow.window);
        // only react to the destruction of client windows not of our frame windows
        if (Frame <> nil) and (Frame.ClientWindow = AEvent.xdestroywindow.window) then begin
          DestroyWindowFrame(Frame);
          Result := True;
        end;
      end;
    Expose:
      begin
        Frame := WindowToFrame(AEvent.xexpose.window);
        if (Frame <> nil) and (Frame.FrameWindow = AEvent.xany.window) then begin
          PaintWindowFrame(Frame);
          Result := True;
        end;
      end
    else
      begin
        WriteLn('Got Unhandled Event: ', AEvent.xany._type);
        Result := False;
      end;
  end;
  WriteLn('DoneEvent');
end;

procedure TXWindowManager.MapWindow(const AWindow: TXFrame);
var
 Width,
 Height: Integer;
begin
  // this makes it so if we crash the child windows will be remapped to the screen
  XAddToSaveSet(Display, AWindow.ClientWindow);

  Width := AWindow.FrameWidth - AWindow.FrameLeftWidth - AWindow.FrameRightWidth;
  Height := AWindow.FrameHeight - AWindow.FrameTopHeight - AWindow.FrameBottomHeight;
  XMapWindow(Display, AWindow.ClientWindow);

  XRaiseWindow(Display, AWindow.FrameWindow);
  XMapRaised(Display, AWindow.FrameWindow);
  
  XSetInputFocus(Display, AWindow.ClientWindow, RevertToPointerRoot, CurrentTime);
end;

procedure TXWindowManager.MoveWindow(const AWindow: TXFrame; APosition: TPoint
  );
begin
  XMoveWindow(Display, AWindow.FrameWindow, APosition.X, APosition.Y);
  // TODO Send an event to the client so it knows it moved per the ICCCM
end;

procedure TXWindowManager.ResizeWindow(const AWindow: TXFrame; AWidth,
  AHeight: Integer);
begin
  AWindow.FrameWidth := AWidth+AWindow.FrameLeftWidth+AWindow.FrameRightWidth;
  AWindow.FrameHeight := AHeight+AWindow.FrameTopHeight+AWindow.FrameBottomHeight;
  // resize the Frame to fit the client window
  XResizeWindow(Display, AWindow.FrameWindow, AWindow.FrameWidth, AWindow.FrameHeight);
  // resize the client to fit in the frame window
  XResizeWindow(Display, AWindow.ClientWindow, AWidth, AHeight);
end;

function TXWindowManager.CloseWindowNice(const AWindow: TWindow): Boolean;
begin
  Result := False;
  if WindowSupportsProto(AWindow, WM_DELETE_WINDOW) then begin
    Result := True;
    
  end;

end;

procedure TXWindowManager.CloseWindowDirty(const AWindow: TWindow);
begin
  // not very nice is it? >:D
  XKillClient(Display, AWindow);
end;

procedure TXWindowManager.SendXMessage(const ADestWindow; AMessage: PXEvent; AMask: LongWord);
begin
  //XSendEvent(Display, ADestWindow, True; AMask; AMessage);
end;

procedure TXWindowManager.SendXClientMessage(const ADestWindow: TWindow; AType: TAtom);
var
Ev : TXClientMessageEvent;
begin
  Ev._type := ClientMessage;
  Ev.window := ADestWindow;
  Ev.message_type := AType;
  //Ev.data :=;
  //SendXmessage, AWindow, True);
  //XSendEvent(para1:PDisplay; para2:TWindow; para3:TBool; para4:clong; para5:PXEvent):TStatus;cdecl;external libX11;
end;

// AFormat is the size of the type of elements in bits. so a cardinal is 32 char is 8 etc
// Elements is how many items there are
// AMode is PropModeAppend, PropModePrepend, or PropModeReplace
procedure TXWindowManager.ChangeWindowProperty(AWindow: TWindow; AProperty: TAtom;
  AType: TAtom; AFormat: cint; AMode: cint; const AData: Pointer; Elements: cint);
begin
  XChangeProperty(Display, AWindow, AProperty, AType, AFormat, AMode, AData, Elements);
end;

procedure TXWindowManager.DeleteWindowProperty(AWindow: TWindow; AProperty: TAtom
  );
begin
  XDeleteProperty(Display, AWindow, AProperty);
end;

function TXWindowManager.WindowSupportsProto(AWindow: TWindow; AProto: TAtom
  ): Boolean;
var
Protocols: PAtom;
I, ProtoCount: Integer;
begin
  Result := False;
  if (XGetWMProtocols(display, AWindow, @Protocols, @ProtoCount) <> 0) then begin
    for I := 0 to ProtoCount-1 do begin
      if (Protocols[i] = AProto) then begin
        Result := True;
        Break;
      end;
    end;
    if (Protocols <> nil) then XFree(Protocols);
  end;
end;

procedure TXWindowManager.InitICCCMHints;
begin
  // currently all ICCCM atoms are defined in XAtom;
end;

procedure TXWindowManager.InitNETHints;
begin
  Init_NETAtoms(fDisplay, fNetAtoms);
end;

procedure TXWindowManager.InitAtoms;
begin
  InitICCCMHints;
  InitNETHints;
  WM_DELETE_WINDOW := XInternAtom(Display, 'WM_DELETE_WINDOW', False);

end;

procedure TXWindowManager.ConfigureWindow(const AWindow: TXFrame;
  const AConfigureEv: TXConfigureRequestEvent);
begin
  // Move to the desired position and set the frame size, also the client will be resized
  MoveWindow(AWindow, Point(AConfigureEv.x, AConfigureEv.y));
  ResizeWindow(AWindow, AConfigureEv.width, AConfigureEv.height);
end;

function TXWindowManager.HandleClientMessage(const AWindow: TXFrame;
  const AClientEv: TXClientMessageEvent): Boolean;
var
Atom: TAtom;
begin
  //Return False to not eat the event
  Result := False;
  Atom := AClientEv.message_type;
  if Atom = _NET[_MOVERESIZE_WINDOW] then
  begin
    WriteLn('_NET[_MOVERESIZE_WINDOW]');
  end
  else if Atom =_NET[_WM_MOVERESIZE] then
  begin
    NetWMMoveResize(AWindow,
              AClientEv.data.l[0], // x_root
              AClientEv.data.l[1], // y_root
              AClientEv.data.l[2], // direction
              AClientEv.data.l[3], // button
              AClientEv.data.l[4]=1);// source (1 for regular apps 2 for pagers or other special apps)
    Result := True;
  end
  else if Atom = _NET[_CLOSE_WINDOW] then
  begin
    WriteLn('_NET[_CLOSE_WINDOW]');
  end
  else if Atom = _NET[_RESTACK_WINDOW] then
  begin
  end
  else if Atom = _NET[_REQUEST_FRAME_EXTENTS] then
  begin
  end
  else WriteLn('Unhandled Client Message');
end;

end.

