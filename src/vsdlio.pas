{$INCLUDE valkyrie.inc}
unit vsdlio;
interface
uses Classes, SysUtils, vutil, viotypes, vioevent,
{$IFDEF USE_SDL2}
     sdl2,
     vsdl2library;
{$ELSE}
     vsdllibrary;
{$ENDIF}

type TSDLIOFlag  = ( SDLIO_OpenGL, SDLIO_FullScreen, SDLIO_Resizable );
     TSDLIOFlags = set of TSDLIOFlag;

type TSDLIODriver = class( TIODriver )
  class function GetCurrentResolution( out aResult : TIOPoint ) : Boolean;

  constructor Create( aWidth, aHeight, aBPP : Word; aFlags : TSDLIOFlags );
  function ResetVideoMode( aWidth, aHeight, aBPP : Word; aFlags : TSDLIOFlags ) : Boolean;
  procedure SetupOpenGL;
  {$IFDEF USE_SDL2}
  function ToggleFullScreen( aWidth, aHeight: Word ) : Boolean;
  {$ENDIF}
  function PollEvent( out aEvent : TIOEvent ) : Boolean; override;
  function PeekEvent( out aEvent : TIOEvent ) : Boolean; override;
  function EventPending : Boolean; override;
  procedure SetEventMask( aMask : TIOEventType ); override;
  procedure Sleep( Milliseconds : DWord ); override;
  function GetMs : DWord; override;
  procedure PreUpdate; override;
  procedure PostUpdate; override;
  destructor Destroy; override;
  function GetSizeX : DWord; override;
  function GetSizeY : DWord; override;
  function GetMousePos( out aResult : TIOPoint) : Boolean; override;
  function GetMouseButtonState( out aResult : TIOMouseButtonSet) : Boolean; override;
  function GetModKeyState : TIOModKeySet; override;
  procedure SetTitle( const aLongTitle : AnsiString; const aShortTitle : AnsiString ); override;
  procedure ShowMouse( aShow : Boolean );
  procedure ScreenShot( const aFileName : AnsiString );
private
  FFlags    : TSDLIOFlags;
  FSizeX    : DWord;
  FSizeY    : DWord;
  FBPP      : DWord;
  FOpenGL   : Boolean;
  FFScreen  : Boolean;
  FOnResize : TIOInterrupt;
  {$IFDEF USE_SDL2}
  FWindow   : PSDL_Window;
  FGLContext: TSDL_GLContext;
  {$ENDIF}
public
  property Width : DWord        read FSizeX;
  property Height : DWord       read FSizeY;
  property BPP : DWord          read FBPP;
  property OpenGLMode : Boolean read FOpenGL;
  property FullScreen : Boolean read FFScreen;
  property Flags : TSDLIOFlags  read FFlags;

  property OnResizeEvent : TIOInterrupt write FOnResize;
end;

var SDLIO : TSDLIODriver = nil;

{$IFDEF USE_SDL2}
function SDLIOEventFilter(userdata: Pointer; event: PSDL_Event) : Integer; cdecl;
{$ELSE}
function SDLIOEventFilter(event: PSDL_Event) : Integer; cdecl;
{$ENDIF}

implementation

uses vgllibrary,
     {Screenshot support}
     FPImage, FPCanvas,
     FPWritePNG;

function SDLSymToCode( Key : TSDLKey ) : Byte;
begin
  Result := VKEY_NONE;
  case Key of
    SDLK_ESCAPE         : Result := VKEY_ESCAPE;
    SDLK_TAB            : Result := VKEY_TAB;
    SDLK_BACKSPACE      : Result := VKEY_BACK;
    SDLK_RETURN         : Result := VKEY_ENTER;
    SDLK_INSERT         : Result := VKEY_INSERT;
    SDLK_DELETE         : Result := VKEY_DELETE;
    SDLK_HOME           : Result := VKEY_HOME;
    SDLK_END            : Result := VKEY_END;
    SDLK_PAGEUP         : Result := VKEY_PGUP;
    SDLK_PAGEDOWN       : Result := VKEY_PGDOWN;
    SDLK_UP             : Result := VKEY_UP;
    SDLK_DOWN           : Result := VKEY_DOWN;
    SDLK_LEFT           : Result := VKEY_LEFT;
    SDLK_RIGHT          : Result := VKEY_RIGHT;
    SDLK_F1             : Result := VKEY_F1;
    SDLK_F2             : Result := VKEY_F2;
    SDLK_F3             : Result := VKEY_F3;
    SDLK_F4             : Result := VKEY_F4;
    SDLK_F5             : Result := VKEY_F5;
    SDLK_F6             : Result := VKEY_F6;
    SDLK_F7             : Result := VKEY_F7;
    SDLK_F8             : Result := VKEY_F8;
    SDLK_F9             : Result := VKEY_F9;
    SDLK_F10            : Result := VKEY_F10;
    SDLK_F11            : Result := VKEY_F11;
    SDLK_F12            : Result := VKEY_F12;

    // TEMPORARY
    SDLK_KP1            : Result := VKEY_END;
    SDLK_KP2            : Result := VKEY_DOWN;
    SDLK_KP3            : Result := VKEY_PGDOWN;
    SDLK_KP4            : Result := VKEY_LEFT;
    SDLK_KP5            : Result := VKEY_CENTER;
    SDLK_KP6            : Result := VKEY_RIGHT;
    SDLK_KP7            : Result := VKEY_HOME;
    SDLK_KP8            : Result := VKEY_UP;
    SDLK_KP9            : Result := VKEY_PGUP;
    SDLK_KP_ENTER       : Result := VKEY_ENTER;
  else
    if Key in VKEY_SCANSET then
      Result := Key;
  end;
end;

function SDLKeyEventToKeyCode( event : PSDL_Event ) : TIOKeyCode;
var smod : TSDLMod;
begin
  Result := SDLSymToCode( event^.key.keysym.sym );
  smod := event^.key.keysym.modifier;
  if smod and KMOD_CTRL  <> 0 then Result += IOKeyCodeCtrlMask;
  if smod and KMOD_SHIFT <> 0 then Result += IOKeyCodeShiftMask;
  if smod and KMOD_ALT   <> 0 then Result += IOKeyCodeAltMask;
end;

function SDLModToModKeySet( smod : TSDLMod ) : TIOModKeySet;
begin
  Result := [];
  if smod = KMOD_NONE then Exit;
  if smod and KMOD_CTRL  <> 0 then Include( Result, VKMOD_CTRL );
  if smod and KMOD_SHIFT <> 0 then Include( Result, VKMOD_SHIFT );
  if smod and KMOD_ALT   <> 0 then Include( Result, VKMOD_ALT );
end;

function SDLKeyEventToIOEvent( event : PSDL_Event ) : TIOEvent;
var ASCII : Char;
    KeyCode : Byte;
begin
  {$IFDEF USE_SDL2}
  if event^.type_ = SDL_TEXTINPUT then
    ASCII := event^.text.text[0]
  else  // SDL_KEYDOWN or SDL_KEYUP
    begin
      ASCII := #0;
      KeyCode := SDLSymToCode( event^.key.keysym.sym );
      if not (KeyCode in VKEY_ARROWSET + VKEY_CONTROLSET) then
        Exit( DummyKeyEvent() );  // we handle "printable" keys through SDL_TEXTINPUT
    end;
  {$ELSE}
  ASCII := Char(event^.key.keysym.unicode);
  {$ENDIF}
  if Ord(ASCII) in VKEY_PRINTABLESET then
  begin
    Result := PrintableToIOEvent( ASCII );
    if event^.type_ = SDL_KEYUP then Result.EType := VEVENT_KEYUP;
    Exit;
  end;
  if event^.type_ = SDL_KEYDOWN
    then Result.EType := VEVENT_KEYDOWN
    else Result.EType := VEVENT_KEYUP;
  Result.Key.ASCII    := #0;
  Result.Key.ModState := SDLModToModKeySet( event^.key.keysym.modifier );
  Result.Key.Code     := SDLSymToCode( event^.key.keysym.sym );
end;

function SDLSystemEventToIOEvent( event : PSDL_Event ) : TIOEvent;
begin
  Result.EType := VEVENT_SYSTEM;
  Result.System.Param1 := 0;
  Result.System.Param2 := 0;

  case event^.type_ of
    SDL_QUITEV      : Result.System.Code := VIO_SYSEVENT_QUIT;
    {$IFDEF USE_SDL2}
    SDL_WINDOWEVENT :
      case event^.window.event of
        SDL_WINDOWEVENT_RESIZED:
          begin
            Result.System.Code := VIO_SYSEVENT_RESIZE;
            Result.System.Param1 := event^.window.data1;
            Result.System.Param2 := event^.window.data2;
          end;
        SDL_WINDOWEVENT_EXPOSED:
          Result.System.Code := VIO_SYSEVENT_EXPOSE;
        SDL_WINDOWEVENT_ENTER:    // simulation of SDL1.2 behavior
          begin
            Result.System.Code := VIO_SYSEVENT_ACTIVE;
            Result.System.Param1 := 1;
            Result.System.Param2 := 1;
          end;
        SDL_WINDOWEVENT_LEAVE:
          begin
            Result.System.Code := VIO_SYSEVENT_ACTIVE;
            Result.System.Param1 := 0;
            Result.System.Param2 := 1;
          end;
        SDL_WINDOWEVENT_FOCUS_GAINED:
          begin
            Result.System.Code := VIO_SYSEVENT_ACTIVE;
            Result.System.Param1 := 1;
            Result.System.Param2 := 2;
          end;
        SDL_WINDOWEVENT_FOCUS_LOST:
          begin
            Result.System.Code := VIO_SYSEVENT_ACTIVE;
            Result.System.Param1 := 0;
            Result.System.Param2 := 2;
          end;
        else
          begin
            Result.System.Code := VIO_SYSEVENT_UNKNOWN;
            Result.System.Param1 := event^.type_;
          end;
      end;
    {$ELSE}
    SDL_VIDEOEXPOSE :
      Result.System.Code := VIO_SYSEVENT_EXPOSE;
    SDL_ACTIVEEVENT :
      begin
        Result.System.Code := VIO_SYSEVENT_ACTIVE;
        Result.System.Param1 := event^.active.gain;
        Result.System.Param2 := event^.active.state;
      end;
    SDL_VIDEORESIZE :
      begin
        Result.System.Code := VIO_SYSEVENT_RESIZE;
        Result.System.Param1 := event^.resize.w;
        Result.System.Param2 := event^.resize.h;
      end;
    {$ENDIF}

    SDL_SYSWMEVENT :
      begin
        Result.System.Code := VIO_SYSEVENT_WM;
        // TODO : Windows messages?
      end
    else
      begin
        Result.System.Code := VIO_SYSEVENT_UNKNOWN;
        Result.System.Param1 := event^.type_;
      end;
  end;
end;

function SDLMouseButtonToVMB( Button : Byte ) : TIOMouseButton;
begin
  case button of
    SDL_BUTTON_LEFT     : Exit( VMB_BUTTON_LEFT );
    SDL_BUTTON_MIDDLE   : Exit( VMB_BUTTON_MIDDLE );
    SDL_BUTTON_RIGHT    : Exit( VMB_BUTTON_RIGHT );
    {$IFNDEF USE_SDL2} // handled in SDLMouseWheelEventToIOEvent
    SDL_BUTTON_WHEELUP  : Exit( VMB_WHEEL_UP );
    SDL_BUTTON_WHEELDOWN: Exit( VMB_WHEEL_DOWN );
    {$ENDIF}
  end;
  Exit( VMB_UNKNOWN );
end;

function SDLMouseButtonSetToVMB( ButtonMask : Byte ) : TIOMouseButtonSet;
begin
  Result := [];
  if (ButtonMask and SDL_BUTTON( 1 )) <> 0 then Include( Result, VMB_BUTTON_LEFT );
  if (ButtonMask and SDL_BUTTON( 2 )) <> 0 then Include( Result, VMB_BUTTON_MIDDLE );
  if (ButtonMask and SDL_BUTTON( 3 )) <> 0 then Include( Result, VMB_BUTTON_RIGHT );
  if (ButtonMask and SDL_BUTTON( 4 )) <> 0 then Include( Result, VMB_WHEEL_UP );
  if (ButtonMask and SDL_BUTTON( 5 )) <> 0 then Include( Result, VMB_WHEEL_DOWN );
  if (ButtonMask and SDL_BUTTON( 6 )) <> 0 then Include( Result, VMB_UNKNOWN );
  if (ButtonMask and SDL_BUTTON( 7 )) <> 0 then Include( Result, VMB_UNKNOWN );
end;

function SDLMouseEventToIOEvent( event : PSDL_Event ) : TIOEvent;
begin
  case event^.type_ of
    SDL_MOUSEBUTTONDOWN : Result.EType := VEVENT_MOUSEDOWN;
    SDL_MOUSEBUTTONUP   : Result.EType := VEVENT_MOUSEUP;
  end;
  Result.Mouse.Button  := SDLMouseButtonToVMB( event^.button.button );
  Result.Mouse.Pos.X   := event^.button.x;
  Result.Mouse.Pos.Y   := event^.button.y;
  Result.Mouse.Pressed := event^.button.state = SDL_PRESSED;
end;

{$IFDEF USE_SDL2}
function SDLMouseWheelEventToIOEvent( event : PSDL_Event ) : TIOEvent;
begin
  // simulating SDL1.2 behavior
  Result.EType := VEVENT_MOUSEDOWN;
  if event^.wheel.y > 0 then Result.Mouse.Button := VMB_WHEEL_UP;
  if event^.wheel.y < 0 then Result.Mouse.Button := VMB_WHEEL_DOWN;
  SDL_GetMouseState( @Result.Mouse.Pos.X, @Result.Mouse.Pos.Y );
  Result.Mouse.Pressed := event^.button.state = SDL_PRESSED;
end;
{$ENDIF}

function SDLMouseMoveEventToIOEvent( event : PSDL_Event ) : TIOEvent;
begin
  Result.EType := VEVENT_MOUSEMOVE;
  Result.MouseMove.ButtonState := SDLMouseButtonSetToVMB( event^.motion.state );
  Result.MouseMove.Pos.X       := event^.motion.x;
  Result.MouseMove.Pos.Y       := event^.motion.y;
  Result.MouseMove.RelPos.X    := event^.motion.xrel;
  Result.MouseMove.RelPos.Y    := event^.motion.yrel;
end;

function SDLEventToIOEvent( event : PSDL_Event ) : TIOEvent;
begin
  case event^.type_ of
    SDL_KEYDOWN : Exit( SDLKeyEventToIOEvent( event ) );
    SDL_KEYUP   : Exit( SDLKeyEventToIOEvent( event ) );
    {$IFDEF USE_SDL2}
    SDL_TEXTINPUT : Exit( SDLKeyEventToIOEvent( event ) );
    {$ENDIF}

    SDL_MOUSEMOTION     : Exit( SDLMouseMoveEventToIOEvent( event ) );
    SDL_MOUSEBUTTONDOWN : Exit( SDLMouseEventToIOEvent( event ) );
    SDL_MOUSEBUTTONUP   : Exit( SDLMouseEventToIOEvent( event ) );
    {$IFDEF USE_SDL2}
    SDL_MOUSEWHEEL      : Exit( SDLMouseWheelEventToIOEvent( event ) );
    {$ENDIF}

    SDL_JOYAXISMOTION : ;
    SDL_JOYBALLMOTION : ;
    SDL_JOYHATMOTION  : ;
    SDL_JOYBUTTONDOWN,
    SDL_JOYBUTTONUP   : ;

    //{$IFDEF USE_SDL2}
    //SDL_APP_WILLENTERBACKGROUND: ; // TODO: implement this
    //{$ENDIF}
    else
      Exit( SDLSystemEventToIOEvent( event ) );
  end;
  Result.EType := VEVENT_SYSTEM;
  Result.System.Code := VIO_SYSEVENT_NONE;
end;

{$IFDEF USE_SDL2}
function SDLIOEventFilter(userdata: Pointer; event: PSDL_Event) : Integer; cdecl;
{$ELSE}
function SDLIOEventFilter(event: PSDL_Event) : Integer; cdecl;
{$ENDIF}
var iCode : TIOKeyCode;
begin
  if event^.type_ = SDL_QUITEV then
    if Assigned( SDLIO.FOnQuit ) then
      if SDLIO.FOnQuit( SDLEventToIOEvent( event ) ) then
        Exit(0);
  {$IFDEF USE_SDL2}
  if (event^.type_ = SDL_WINDOWEVENT) and (event^.window.event = SDL_WINDOWEVENT_RESIZED) then
  {$ELSE}
  if event^.type_ = SDL_VIDEORESIZE then
  {$ENDIF}
    if Assigned( SDLIO.FOnResize ) then
    if SDLIO.FOnResize( SDLEventToIOEvent( event ) ) then
      Exit(0);
  if event^.type_ = SDL_KEYDOWN then
  begin
    iCode := SDLKeyEventToKeyCode( event );
    if SDLIO.FInterrupts[iCode] <> nil then
      if SDLIO.FInterrupts[iCode]( SDLKeyEventToIOEvent( event ) ) then
        Exit(0);
  end;
  Exit(1);
end;

{ TSDLIODriver }

class function TSDLIODriver.GetCurrentResolution ( out aResult : TIOPoint ) : Boolean;
var
  {$IFDEF USE_SDL2}
  info : TSDL_DisplayMode;
  {$ELSE}
  info : PSDL_VideoInfo;
  {$ENDIF}
begin
  LoadSDL;
  if ( SDL_Init(SDL_INIT_VIDEO) < 0 ) then
  begin
    SDL_Quit();
    SDLIO := nil;
    raise EIOException.Create('Couldn''t initialize SDL : '+SDL_GetError());
  end;

  {$IFDEF USE_SDL2}
  if ( SDL_GetCurrentDisplayMode(0, @info) <> 0 ) then Exit( False );
  aResult.Init( info.w, info.h );
  {$ELSE}
  info := SDL_GetVideoInfo();
  if info = nil then Exit( False );
  aResult.Init( info^.current_w, info^.current_h );
  {$ENDIF}
  Exit( True );
end;

constructor TSDLIODriver.Create( aWidth, aHeight, aBPP : Word; aFlags : TSDLIOFlags );
begin
  ClearInterrupts;
  SDLIO := Self;
  inherited Create;
  LoadSDL;
  if SDLIO_OpenGL in aFlags then
    LoadGL;

  Log('Initializing SDL...');

  if ( SDL_Init(SDL_INIT_VIDEO) < 0 ) then
  begin
    SDL_Quit();
    SDLIO := nil;
    raise EIOException.Create('Couldn''t initialize SDL : '+SDL_GetError());
  end;

  if not ResetVideoMode( aWidth, aHeight, aBPP, aFlags ) then
  begin
    SDL_Quit();
    SDLIO := nil;
    raise EIOException.Create('Could not set '+IntToStr(aWidth)+'x'+IntToStr(aHeight)+'@'+IntToStr(aBPP)+'bpp!' );
  end;

  Log('Mode %dx%d/%d set.', [aWidth,aHeight,aBPP]);

  if SDLIO_OpenGL in aFlags then
  begin
    Log( LOGINFO, 'OpenGL Vendor       : %s', [ glGetString(GL_VENDOR) ] );
    Log( LOGINFO, 'OpenGL Renderer     : %s', [ glGetString(GL_RENDERER) ] );
    Log( LOGINFO, 'OpenGL Version      : %s', [ glGetString(GL_VERSION) ] );
    Log( LOGINFO, 'OpenGL GLSL Version : %s', [ glGetString(35724) ] );
  end;

  {$IFNDEF USE_SDL2}
  SDL_WM_SetCaption('Valkyrie SDL Application','VSDL Application');

  SDL_EventState(SDL_ACTIVEEVENT, SDL_IGNORE);
  {$ENDIF}

  SDL_EventState(SDL_KEYUP, SDL_IGNORE);
//  SDL_EventState(SDL_MOUSEMOTION, SDL_IGNORE);
//  SDL_EventState(SDL_MOUSEBUTTONDOWN, SDL_IGNORE);
//  SDL_EventState(SDL_MOUSEBUTTONUP, SDL_IGNORE);
//  SDL_EventState(SDL_VIDEORESIZE, SDL_IGNORE);
//  SDL_EventState(SDL_VIDEOEXPOSE, SDL_IGNORE);
//  SDL_EventState(SDL_USEREVENT, SDL_IGNORE);

  {$IFDEF USE_SDL2}
  SDL_SetEventFilter(@SDLIOEventFilter, nil);
  {$ELSE}
  SDL_EnableUNICODE(1);
  SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_DELAY, SDL_DEFAULT_REPEAT_INTERVAL);
  SDL_SetEventFilter(@SDLIOEventFilter);
  {$ENDIF}

  Log('SDL IO system ready.');
end;

function TSDLIODriver.ResetVideoMode ( aWidth, aHeight, aBPP : Word; aFlags : TSDLIOFlags ) : Boolean;
var iSDLFlags : DWord;
begin
  iSDLFlags := 0;
  FFScreen  := SDLIO_FullScreen in aFlags;
  FOpenGL   := SDLIO_OpenGL in aFlags;
  FSizeX    := aWidth;
  FSizeY    := aHeight;
  FBPP      := aBPP;
  FFlags    := aFlags;

  {$IFDEF USE_SDL2}
  if FOpenGL  then iSDLFlags := iSDLFlags or SDL_WINDOW_OPENGL;
  if FFScreen then iSDLFlags := iSDLFlags or SDL_WINDOW_FULLSCREEN;
  if SDLIO_Resizable in aFlags then iSDLFlags := iSDLFlags or SDL_WINDOW_RESIZABLE;
  {$ELSE}
  if not FOpenGL then
    begin
      iSDLFlags := iSDLFlags or SDL_HWSURFACE;
      iSDLFlags := iSDLFlags or SDL_DOUBLEBUF;
    end;

  if FOpenGL  then iSDLFlags := iSDLFlags or SDL_OPENGL;
  if FFScreen then iSDLFlags := iSDLFlags or SDL_FULLSCREEN;
  if SDLIO_Resizable in aFlags then iSDLFlags := iSDLFlags or SDL_RESIZABLE;
  {$ENDIF}

  if FOpenGL then
  begin
    {$IFDEF ANDROID}
    SDL_GL_SetAttribute( SDL_GL_RED_SIZE, 5 );
    SDL_GL_SetAttribute( SDL_GL_GREEN_SIZE, 6 );
    SDL_GL_SetAttribute( SDL_GL_BLUE_SIZE, 5 );
    {$ELSE}
    SDL_GL_SetAttribute( SDL_GL_RED_SIZE, 8 );
    SDL_GL_SetAttribute( SDL_GL_GREEN_SIZE, 8 );
    SDL_GL_SetAttribute( SDL_GL_BLUE_SIZE, 8 );
    {$ENDIF}
    SDL_GL_SetAttribute( SDL_GL_DEPTH_SIZE, 16 );
    SDL_GL_SetAttribute( SDL_GL_DOUBLEBUFFER, 1 );
  end;

  {$IFDEF USE_SDL2}
    {$IFDEF ANDROID} // on Android we need fullscreen anyway
    iSDLFlags := SDL_WINDOW_FULLSCREEN_DESKTOP or SDL_WINDOW_OPENGL;
    {$ENDIF}
  FWindow := SDL_CreateWindow('Valkyrie SDL Application',
                              SDL_WINDOWPOS_UNDEFINED,
                              SDL_WINDOWPOS_UNDEFINED,
                              aWidth, aHeight, iSDLFlags);
  if FWindow = nil then
    begin
      Log(LOGERROR, 'Error setting mode %dx%d: %s',
          [aWidth,aHeight,SDL_GetError()]);
      Exit( False );
    end;
  if FOpenGL then
    begin
      FGLContext := SDL_GL_CreateContext(FWindow);
      if FGLContext = nil then
        begin
          Log(LOGERROR, 'Error creating OpenGL context: %s', [SDL_GetError()]);
          Exit( False );
        end
    end;
  {$ELSE}
  Log('Checking mode %dx%d/%dbit. flags:%04x', [aWidth,aHeight,aBPP,iSDLFlags]);
  if aBPP <> SDL_VideoModeOK( aWidth, aHeight, aBPP, iSDLFlags ) then Exit( False );
  if SDL_SetVideoMode( aWidth, aHeight, aBPP, iSDLFlags ) = nil then Exit( False );
  {$ENDIF}

  if FOpenGL then SetupOpenGL;
  Exit( True );
end;

procedure TSDLIODriver.SetupOpenGL;
begin
  glShadeModel( GL_SMOOTH );
  glClearColor( 0.0, 0.0, 0.0, 0.0 );
  glClearDepthf( 1.0 );
  glHint( GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST );
  glHint( GL_LINE_SMOOTH_HINT,            GL_NICEST );
  glHint( GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST );
  glHint( GL_POINT_SMOOTH_HINT,           GL_NICEST );
  glHint( GL_POLYGON_SMOOTH_HINT,         GL_NICEST );
  glEnable( GL_CULL_FACE );
  glEnable( GL_DEPTH_TEST );
  glEnable( GL_BLEND );
  glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
  glDepthFunc( GL_LEQUAL );
  glCullFace( GL_BACK );
  glFrontFace( GL_CCW );
  glClearColor( 0, 0, 0, 0 );
  glViewport( 0, 0, FSizeX, FSizeY );
  glMatrixMode( GL_PROJECTION );
  glLoadIdentity( );
  glMatrixMode( GL_MODELVIEW );
  glLoadIdentity( );
end;

{$IFDEF USE_SDL2}
function TSDLIODriver.ToggleFullScreen( aWidth, aHeight: Word ) : Boolean;
begin
  if FWindow = nil then Exit( False );
  FSizeX := aWidth;
  FSizeY := aHeight;
  FFScreen := not FFScreen;
  if FFScreen then
    begin
      Include( FFlags, SDLIO_FullScreen );
      SDL_SetWindowSize( FWindow, aWidth, aHeight );
      SDL_SetWindowFullscreen( FWindow, SDL_WINDOW_FULLSCREEN );
    end
  else
    begin
      Exclude( FFlags, SDLIO_FullScreen );
      SDL_SetWindowFullscreen( FWindow, 0 );
      SDL_SetWindowSize( FWindow, aWidth, aHeight );
    end;
  glMatrixMode( GL_PROJECTION );
  glLoadIdentity( );
  {$IFDEF ANDROID}
  glOrthof(0, FSizeX, FSizeY, 0, -1, 1);
  {$ELSE}
  glOrtho(0, FSizeX, FSizeY, 0, -1, 1);
  {$ENDIF}
  glMatrixMode( GL_MODELVIEW );
  glLoadIdentity( );
  Exit( True );
end;
{$ENDIF}

procedure TSDLIODriver.Sleep ( Milliseconds : DWord ) ;
begin
  SDL_Delay( Milliseconds );
end;

function TSDLIODriver.PollEvent ( out aEvent : TIOEvent ) : Boolean;
var event : TSDL_Event;
begin
  Result := SDL_PollEvent( @event ) > 0;
  if Result then
    aEvent := SDLEventToIOEvent( @event );
end;

function TSDLIODriver.PeekEvent ( out aEvent : TIOEvent ) : Boolean;
var event : TSDL_Event;
begin
  SDL_PumpEvents();
  {$IFDEF USE_SDL2}
  Result := (SDL_PeepEvents( @event, 1, SDL_PEEKEVENT, SDL_FIRSTEVENT, SDL_LASTEVENT ) > 0 );
  {$ELSE}
  Result := (SDL_PeepEvents( @event, 1, SDL_PEEKEVENT, SDL_ALLEVENTS ) > 0 );
  {$ENDIF}
  if Result then
    aEvent := SDLEventToIOEvent( @event );
end;

function TSDLIODriver.EventPending : Boolean;
var event : TSDL_Event;
begin
  SDL_PumpEvents();
  {$IFDEF USE_SDL2}
  Result := (SDL_PeepEvents( @event, 1, SDL_PEEKEVENT, SDL_FIRSTEVENT, SDL_LASTEVENT ) > 0 );
  {$ELSE}
  Result := (SDL_PeepEvents( @event, 1, SDL_PEEKEVENT, SDL_ALLEVENTS ) > 0 );
  {$ENDIF}
end;

procedure TSDLIODriver.SetEventMask ( aMask : TIOEventType ) ;
begin

end;

function TSDLIODriver.GetMs : DWord;
begin
  Exit( SDL_GetTicks() );
end;

procedure TSDLIODriver.PreUpdate;
begin
  if FOpenGL then
  begin
    glClearColor(0.0,0.0,0.0,1.0);
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  end;
end;

procedure TSDLIODriver.PostUpdate;
begin
  {$IFDEF USE_SDL2}
  if FOpenGL then
    SDL_GL_SwapWindow(FWindow);
  // else ... for now we ignore non-gl rendering with SDL2
  {$ELSE}
  if FOpenGL then
    SDL_GL_SwapBuffers()
  else
    SDL_Flip( SDL_GetVideoSurface() );
  {$ENDIF}
end;

destructor TSDLIODriver.Destroy;
begin
  {$IFDEF USE_SDL2}
  if FOpenGL and (FGLContext <> nil) then
    SDL_GL_DeleteContext(FGLContext);
  {$ENDIF}
  inherited Destroy;
end;

function TSDLIODriver.GetSizeX : DWord;
begin
  Result := FSizeX;
end;

function TSDLIODriver.GetSizeY : DWord;
begin
  Result := FSizeY;
end;

function TSDLIODriver.GetMousePos ( out aResult : TIOPoint ) : Boolean;
var x,y : Integer;
begin
  x := 0; y := 0;
  {$IFDEF USE_SDL2}
  if SDL_GetWindowFlags( FWindow ) and SDL_WINDOW_MOUSE_FOCUS = 0 then Exit( False );
  SDL_GetMouseState(@x,@y);
  {$ELSE}
  if SDL_GetAppState() and SDL_APPMOUSEFOCUS = 0 then Exit( False );
  SDL_GetMouseState(x,y);
  {$ENDIF}
  aResult := Point( x, y );
  Exit( True );
end;

function TSDLIODriver.GetMouseButtonState ( out aResult : TIOMouseButtonSet
  ) : Boolean;
var x,y : Integer;
begin
  x := 0; y := 0;
  {$IFDEF USE_SDL2}
  if SDL_GetWindowFlags( FWindow ) and SDL_WINDOW_MOUSE_FOCUS = 0 then Exit( False );
  aResult := SDLMouseButtonSetToVMB( SDL_GetMouseState(@x,@y) );
  {$ELSE}
  if SDL_GetAppState() and SDL_APPMOUSEFOCUS = 0 then Exit( False );
  aResult := SDLMouseButtonSetToVMB( SDL_GetMouseState(x,y) );
  {$ENDIF}
  Exit( True );
end;

function TSDLIODriver.GetModKeyState : TIOModKeySet;
begin
  Exit( SDLModToModKeySet( SDL_GetModState() ) );
end;

procedure TSDLIODriver.SetTitle ( const aLongTitle : AnsiString;
  const aShortTitle : AnsiString ) ;
begin
  {$IFDEF USE_SDL2}
  SDL_SetWindowTitle(FWindow, PChar(aLongTitle));
  {$ELSE}
  if aShortTitle = ''
    then SDL_WM_SetCaption(PChar(aLongTitle),PChar(aLongTitle))
    else SDL_WM_SetCaption(PChar(aLongTitle),PChar(aShortTitle));
  {$ENDIF}
end;

procedure TSDLIODriver.ShowMouse ( aShow : Boolean ) ;
begin
  if aShow
    then SDL_ShowCursor(1)
    else SDL_ShowCursor(0);
end;

procedure TSDLIODriver.ScreenShot ( const aFileName : AnsiString ) ;
var image  : TFPCustomImage;
    writer : TFPWriterPNG;
    data   : PByte;
    sx,sy  : Word;
    x,y    : Word;
begin
try
  try
    sx := GetSizeX;
    sy := GetSizeY;
    Image  := TFPMemoryImage.Create(sx,sy);
    Data   := GetMem( sx*sy*4 );
    glReadPixels(0, 0, sx, sy, GL_RGBA, GL_UNSIGNED_BYTE, Data);
    for x := 0 to sx-1 do
      for y := 0 to sy-1 do
        Image.Colors[x,sy-y-1] := FPColor( Data[ 4*(sx*y+x) ] shl 8, Data[ 4*(sx*y+x)+1 ] shl 8, Data[ 4*(sx*y+x)+2 ] shl 8);
    Writer := TFPWriterPNG.Create;
    Writer.Indexed := False;
    Image.SaveToFile( aFileName, writer );
  finally
    FreeMem( Data );
    FreeAndNil( image );
    FreeAndNil( writer );
  end;
except on e : Exception do
end;
end;


end.

