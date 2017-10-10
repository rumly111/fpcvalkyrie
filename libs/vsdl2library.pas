unit vsdl2library;

{$MODE OBJFPC}

interface

uses Classes, SysUtils, sdl2;

const
  SDL_RLEACCEL = $00004000;
  SDL_SRCALPHA = $00010000;

  SDLK_KP1     = SDLK_KP_1;
  SDLK_KP2     = SDLK_KP_2;
  SDLK_KP3     = SDLK_KP_3;
  SDLK_KP4     = SDLK_KP_4;
  SDLK_KP5     = SDLK_KP_5;
  SDLK_KP6     = SDLK_KP_6;
  SDLK_KP7     = SDLK_KP_7;
  SDLK_KP8     = SDLK_KP_8;
  SDLK_KP9     = SDLK_KP_9;


type
  SDL_Rect = TSDL_Rect;  // needed for some functions
  TSDLKey = TSDL_KeyCode;
  TSDLMod = TSDL_KeyMod;

function SDL_RWopsFromStream ( Stream : TStream; Size : DWord ) : PSDL_RWops;

// SDL-1.2 compatibility function
function SDL_SetAlpha(surface: PSDL_Surface; flag: UInt32; alpha: UInt8): Integer;

{$NOTE This function is provided for compatibility with vsdllibrary}
function LoadSDL( const aPath : AnsiString = '' ) : Boolean;

implementation

function LoadSDL( const aPath : AnsiString = '' ) : Boolean;
begin
  Exit( True );
end;

function RW_Stream_Size( context: PSDL_RWops ) : Int64; cdecl;
var Stream  : TStream;
begin
  Stream := TStream(context^.mem.here);
  Exit( Stream.Size );
end;

function RW_Stream_Seek( context: PSDL_RWops; offset: Int64; whence: Integer ) : Int64; cdecl;
var Stream  : TStream;
    SOffset : PtrUInt;
    SSize   : PtrUInt;
begin
  SOffset := PtrUInt(context^.mem.base);
  Stream  := TStream(context^.mem.here);
  SSize   := PtrUInt(context^.mem.stop);

  case whence of
    0 : Stream.Seek( SOffset+offset, soBeginning );
    1 : Stream.Seek( offset, soCurrent );
    2 : Stream.Seek( SOffset+SSize+offset, soCurrent );
  end;
  Exit( Stream.Position-SOffset );
end;

function RW_Stream_Read( context: PSDL_RWops; Ptr: Pointer; size: LongWord; maxnum : LongWord ): DWord; cdecl;
var Stream : TStream;
begin
  Stream := TStream(context^.mem.here);
  Exit( Stream.Read( Ptr^, Size * maxnum ) div Size );
end;

function RW_Stream_Write( context: PSDL_RWops; const Ptr: Pointer; size: LongWord; num: LongWord ): DWord; cdecl;
var Stream : TStream;
begin
  Stream := TStream(context^.mem.here);
  Exit( Stream.Write( Ptr^, Size * num ) div Size );
end;

function RW_Stream_Close( context: PSDL_RWops ): Integer; cdecl;
var Stream : TStream;
begin
  if Context <> nil then
  begin
    Stream := TStream(context^.mem.here);
    FreeAndNil( Stream );
    SDL_FreeRW( context );
  end;
  Exit( 0 );
end;

function SDL_RWopsFromStream( Stream : TStream; Size : DWord ) : PSDL_RWops;
begin
  SDL_RWopsFromStream := SDL_AllocRW();
  if SDL_RWopsFromStream <> nil then
  begin
    SDL_RWopsFromStream^.size := @RW_Stream_Size;
    SDL_RWopsFromStream^.seek := @RW_Stream_Seek;
    SDL_RWopsFromStream^.read := @RW_Stream_Read;
    SDL_RWopsFromStream^.write := @RW_Stream_Write;
    SDL_RWopsFromStream^.close := @RW_Stream_Close;
    SDL_RWopsFromStream^.mem.base := PUInt8( Stream.Position );
    SDL_RWopsFromStream^.mem.here := PUInt8( Stream );
    SDL_RWopsFromStream^.mem.stop := PUInt8( Size );
  end;
end;

function SDL_SetAlpha(surface: PSDL_Surface; flag: UInt32; alpha: UInt8): Integer;
begin
  {$WARNING this could be wrong}
  if flag and SDL_SRCALPHA = 1 then
    Exit( SDL_SetSurfaceAlphaMod(surface,alpha) );
  Exit( 1 );
end;

end.

