unit vsdl2ttflibrary;

{$MODE OBJFPC}

interface

uses SysUtils, sdl2, sdl2_ttf;

type TSDLTTFException = class( Exception );

function TTF_OpenFontOrThrow(const _file: PChar; ptsize : Integer): PTTF_Font;
function TTF_OpenFontRWOrThrow(src: PSDL_RWops; freesrc: Integer; ptsize : Integer): PTTF_Font;

implementation

function TTF_OpenFontOrThrow ( const _file : PChar; ptsize : Integer ) : PTTF_Font;
begin
  TTF_OpenFontOrThrow := TTF_OpenFont( _file, ptsize );
  if TTF_OpenFontOrThrow = nil then
    raise TSDLTTFException.Create('TTF_OpenFontOrThrow : '+TTF_GetError()+' (freetype library or font file missing?)' );
end;

function TTF_OpenFontRWOrThrow ( src : PSDL_RWops; freesrc : Integer; ptsize : Integer ) : PTTF_Font;
begin
  TTF_OpenFontRWOrThrow := TTF_OpenFontRW( src, freesrc, ptsize );
  if TTF_OpenFontRWOrThrow = nil then
    raise TSDLTTFException.Create('TTF_OpenFontRWOrThrow : '+TTF_GetError()+' (freetype library or font file missing?)' );
end;

end.

