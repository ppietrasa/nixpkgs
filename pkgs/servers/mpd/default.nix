{ stdenv, fetchurl, pkgconfig, glib, alsaSupport ? true, alsaLib
, flacSupport ? true, flac, vorbisSupport ? true, libvorbis
, madSupport ? true, libmad, id3tagSupport ? true, libid3tag
, mikmodSupport ? true, libmikmod, cueSupport ? true, libcue
, shoutSupport ? true, libshout
}:
let
  opt = stdenv.lib.optional;
in
stdenv.mkDerivation rec {
  name = "mpd-0.16.8";
  src = fetchurl {
    url = "mirror://sourceforge/musicpd/${name}.tar.bz2";
    sha256 = "35183ae4a706391f5d739e4378b74f516952adda09a260fecfd531a58b0fff17";
  };

  buildInputs = [ pkgconfig glib ]
    ++ opt alsaSupport alsaLib
    ++ opt flacSupport flac
    ++ opt vorbisSupport libvorbis
    ++ opt madSupport libmad
    ++ opt id3tagSupport libid3tag
    ++ opt mikmodSupport libmikmod
    ++ opt cueSupport libcue
    ++ opt shoutSupport libshout;

  configureFlags = ''
    ${if alsaSupport then "--enable-alsa" else "--disable-alsa"}
    ${if flacSupport then "--enable-flac" else "--disable-flac"}
    ${if vorbisSupport then "--enable-vorbis" else "--disable-vorbis"}
    ${if madSupport then "--enable-mad" else "--disable-mad"}
    ${if mikmodSupport then "--enable-mikmod" else "--disable-mikmod"}
    ${if id3tagSupport then "--enable-id3" else "--disable-id3"}
    ${if cueSupport then "--enable-cue" else "--disable-cue"}
    ${if shoutSupport then "--enable-shout" else "--disable-shout"}
  '';

  NIX_LDFLAGS = ''
    ${if shoutSupport then "-lshout" else ""}
  '';

  meta = {
    description = "A flexible, powerful daemon for playing music";
    longDescription = ''
      Music Player Daemon (MPD) is a flexible, powerful daemon for playing
      music. Through plugins and libraries it can play a variety of sound
      files while being controlled by its network protocol.
    '';
    homepage = http://mpd.wikia.com/wiki/Music_Player_Daemon_Wiki;
    license = "GPLv2";
    maintainers = with stdenv.lib.maintainers; [ astsmtl ];
    platforms = with stdenv.lib.platforms; linux;
  };
}
