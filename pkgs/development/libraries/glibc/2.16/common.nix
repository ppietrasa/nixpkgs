/* Build configuration used to build glibc, Info files, and locale
   information.  */

cross:

{ name, fetchurl, stdenv, installLocales ? false
, gccCross ? null, kernelHeaders ? null
, machHeaders ? null, hurdHeaders ? null, libpthreadHeaders ? null
, mig ? null
, profilingLibraries ? false, meta
, preConfigure ? "", ... }@args:

let
  version = "2.16.0";

  needsPortsNative = stdenv.isMips || stdenv.isArm;
  needsPortsCross = cross.arch == "mips" || cross.arch == "arm";
  needsPorts =
    if stdenv.cross or null != null && hurdHeaders == null then true
    else if cross == null then needsPortsNative
    else needsPortsCross;

  srcPorts = fetchurl {
    url = "mirror://gnu/glibc/glibc-ports-${version}.tar.bz2";
    sha256 = "0qw4n71rqykl83ybq0c92w1n8afsx079sw3hn5nyib5nw6iphrfm";
  };

in

assert cross != null -> gccCross != null;

assert mig != null -> machHeaders != null;
assert machHeaders != null -> hurdHeaders != null;
assert hurdHeaders != null -> libpthreadHeaders != null;

stdenv.mkDerivation ({
  inherit kernelHeaders installLocales;

  # The host/target system.
  crossConfig = if cross != null then cross.config else null;

  inherit (stdenv) is64bit;

  enableParallelBuilding = true;

  patches =
    [ /* Fix for NIXPKGS-79: when doing host name lookups, when
         nsswitch.conf contains a line like

           hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4

         don't return an error when mdns4_minimal can't be found.  This
         is a bug in Glibc: when a service can't be found, NSS should
         continue to the next service unless "UNAVAIL=return" is set.
         ("NOTFOUND=return" refers to the service returning a NOTFOUND
         error, not the service itself not being found.)  The reason is
         that the "status" variable (while initialised to UNAVAIL) is
         outside of the loop that iterates over the services, the
         "files" service sets status to NOTFOUND.  So when the call to
         find "mdns4_minimal" fails, "status" will still be NOTFOUND,
         and it will return instead of continuing to "dns".  Thus, the
         line

           hosts: mdns4_minimal [NOTFOUND=return] dns mdns4

         does work because "status" will contain UNAVAIL after the
         failure to find mdns4_minimal. */
      ./nss-skip-unavail.patch

      /* Have rpcgen(1) look for cpp(1) in $PATH.  */
      ./rpcgen-path.patch

      /* Allow NixOS and Nix to handle the locale-archive. */
      ./nix-locale-archive.patch

      /* Don't use /etc/ld.so.cache, for non-NixOS systems.  Currently
         disabled on GNU/Hurd, which uses a more recent libc snapshot. */
      ./dont-use-system-ld-so-cache.patch

      /* Without this patch many KDE binaries crash. */
      ./glibc-elf-localscope.patch
    ];

  postPatch = ''
    # Needed for glibc to build with the gnumake 3.82
    # http://comments.gmane.org/gmane.linux.lfs.support/31227
    sed -i 's/ot \$/ot:\n\ttouch $@\n$/' manual/Makefile

    # nscd needs libgcc, and we don't want it dynamically linked
    # because we don't want it to depend on bootstrap-tools libs.
    echo "LDFLAGS-nscd += -static-libgcc" >> nscd/Makefile
  '';

  configureFlags =
    [ "-C"
      "--enable-add-ons"
      "--enable-obsolete-rpc"
      "--sysconfdir=/etc"
      "--localedir=/var/run/current-system/sw/lib/locale"
      "libc_cv_ssp=no"
      (if kernelHeaders != null
       then "--with-headers=${kernelHeaders}/include"
       else "--without-headers")
      (if profilingLibraries
       then "--enable-profile"
       else "--disable-profile")
    ] ++ stdenv.lib.optionals (cross == null && kernelHeaders != null) [
      "--enable-kernel=${kernelHeaders.versionForGlibc}"
    ] ++ stdenv.lib.optionals (cross != null) [
      (if cross.withTLS then "--with-tls" else "--without-tls")
      (if cross.float == "soft" then "--without-fp" else "--with-fp")
    ] ++ stdenv.lib.optionals (cross != null
          && cross.platform ? kernelMajor
          && cross.platform.kernelMajor == "2.6") [
      "--enable-kernel=2.6.0"
      "--with-__thread"
    ] ++ stdenv.lib.optionals stdenv.isArm [
      "--host=arm-linux-gnueabi"
      "--build=arm-linux-gnueabi"
      "--without-fp"
      # To avoid linking with -lgcc_s (dynamic link)
      # so the glibc does not depend on its compiler store path
      "libc_cv_as_needed=no"
    ];

  installFlags = [ "sysconfdir=$(out)/etc" ];

  buildInputs = stdenv.lib.optionals (cross != null) [ gccCross ]
    ++ stdenv.lib.optional (mig != null) mig;

  # Needed to install share/zoneinfo/zone.tab.  Set to impure /bin/sh to
  # prevent a retained dependency on the bootstrap tools in the stdenv-linux
  # bootstrap.
  BASH_SHELL = "/bin/sh";

  # Workaround for this bug:
  #   http://sourceware.org/bugzilla/show_bug.cgi?id=411
  # I.e. when gcc is compiled with --with-arch=i686, then the
  # preprocessor symbol `__i686' will be defined to `1'.  This causes
  # the symbol __i686.get_pc_thunk.dx to be mangled.
  NIX_CFLAGS_COMPILE = stdenv.lib.optionalString (stdenv.system == "i686-linux") "-U__i686";
}

# Remove the `gccCross' attribute so that the *native* glibc store path
# doesn't depend on whether `gccCross' is null or not.
// (removeAttrs args [ "gccCross" "fetchurl" ]) //

{
  name = name + "-${version}" +
    stdenv.lib.optionalString (cross != null) "-${cross.config}";

  src = fetchurl {
    url = "mirror://gnu/glibc/glibc-${version}.tar.gz";
    sha256 = "0vlz4x6cgz7h54qq4528q526qlhnsjzbsvgc4iizn76cb0bfanx7";
  };

  # Remove absolute paths from `configure' & co.; build out-of-tree.
  preConfigure = ''
    export PWD_P=$(type -tP pwd)
    for i in configure io/ftwtest-sh; do
        # Can't use substituteInPlace here because replace hasn't been
        # built yet in the bootstrap.
        sed -i "$i" -e "s^/bin/pwd^$PWD_P^g"
    done

    ${if needsPorts then "tar xvf ${srcPorts}" else ""}

    mkdir ../build
    cd ../build

    configureScript="`pwd`/../$sourceRoot/configure"

    # Needed to build rpcgen.
    export LD_LIBRARY_PATH=${stdenv.gcc.libc}/lib

    ${preConfigure}
  '';

  meta = {
    homepage = http://www.gnu.org/software/libc/;
    description = "The GNU C Library"
      + stdenv.lib.optionalString (hurdHeaders != null) ", for GNU/Hurd";

    longDescription =
      '' Any Unix-like operating system needs a C library: the library which
         defines the "system calls" and other basic facilities such as
         open, malloc, printf, exit...

         The GNU C library is used as the C library in the GNU system and
         most systems with the Linux kernel.
      '';

    license = "LGPLv2+";

    maintainers = [ stdenv.lib.maintainers.ludo ];
    #platforms = stdenv.lib.platforms.linux;
  } // meta;
}

// stdenv.lib.optionalAttrs (hurdHeaders != null) {
  # Work around the fact that the configure snippet that looks for
  # <hurd/version.h> does not honor `--with-headers=$sysheaders' and that
  # glibc expects Mach, Hurd, and pthread headers to be in the same place.
  CPATH = "${hurdHeaders}/include:${machHeaders}/include:${libpthreadHeaders}/include";

  # Install NSS stuff in the right place.
  # XXX: This will be needed for all new glibcs and isn't Hurd-specific.
  makeFlags = ''vardbdir="$out/var/db"'';
})