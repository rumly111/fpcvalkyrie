unit vsdl2imagelibrary;

{$MODE OBJFPC}

interface

uses SysUtils, sdl2, sdl2_image;

type TSDLImageException = class( Exception );

function IMG_LoadOrThrow(const _file: PChar): PSDL_Surface;
function IMG_LoadRWOrThrow(src: PSDL_RWops; freesrc: Integer): PSDL_Surface;

implementation

function IMG_LoadOrThrow ( const _file : PChar ) : PSDL_Surface;
begin
  IMG_LoadOrThrow := IMG_Load( _file );
  if IMG_LoadOrThrow = nil then
    raise TSDLImageException.Create('IMG_LoadOrThrow : '+IMG_GetError()+' (png/jpg library or file missing?)' );
end;

function IMG_LoadRWOrThrow ( src : PSDL_RWops; freesrc : Integer ) : PSDL_Surface;
begin
  IMG_LoadRWOrThrow := IMG_Load_RW( src, freesrc );
  if IMG_LoadRWOrThrow = nil then
    raise TSDLImageException.Create('IMG_LoadRWOrThrow : '+IMG_GetError()+' (png/jpg library or file missing?)' );
end;

end.

