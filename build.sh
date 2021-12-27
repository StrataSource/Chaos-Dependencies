#!/usr/bin/env bash
set -e

# Add all of our required libraries 
if [ ! -z $RUNNING_ALPINE ]; then
	apk add build-base clang libpng-static libpng-dev expat-static expat-dev zlib-dev zlib-static freetype-dev freetype-static fontconfig-static pixman-static || error
	apk add libxcb-static libxrender-dev harfbuzz-static gtk-doc fontconfig-dev pixman-dev
	apk add git autoconf make cmake automake libtool bzip2-static bzip2-dev brotli-dev brotli-static
fi

# Applies patch if it does not already exist
function apply-patch
{
	git apply $1 || true # Honestly fuck off, patch really likes doing interactive bullshit and it can kiss my ass. If this breaks, nobody fucking cares
#	patch -N --dry-run --silent < $1 2> /dev/null
#	if [ $? -eq 0 ]; then
#		patch $1
#	fi
}

INCDIR="$PWD/install/include"
LIBDIR="$PWD/install/lib"
INSTALLDIR="$PWD/install"

#------------------------#
# Build gobject, gio, etc
#------------------------#
pushd glib > /dev/null

export CFLAGS="-fPIC"

meson build --buildtype release --default-library static --prefix "$INSTALLDIR" --libdir lib
cd build
ninja install

popd > /dev/null
#------------------------#

#------------------------#
# Build libffi
#------------------------#
pushd libffi > /dev/null

export CFLAGS="-fPIC"

./autogen.sh
./configure --enable-static --enable-shared=no --prefix="$INSTALLDIR"
make install -j$(nproc)

popd > /dev/null
#------------------------#

#------------------------#
# Build pixman
#------------------------#
pushd pixman > /dev/null

export CFLAGS="-fPIC"
./autogen.sh --enable-gtk=no --enable-png=no --enable-shared=no --enable-static --prefix="$INSTALLDIR"
make install -j$(nproc)

popd > /dev/null
#------------------------#


#------------------------#
# Build libmd
#------------------------#
pushd libmd > /dev/null

export CFLAGS="-fPIC"
./autogen
./configure --prefix="$INSTALLDIR" --enable-static --enable-shared=no
make install -j$(nproc)

popd > /dev/null
#------------------------#


#------------------------#
# Build libz
#------------------------#
pushd zlib > /dev/null

export CFLAGS="-fPIC"
./configure --static --64 --prefix="$INSTALLDIR"
make install -j$(nproc)

popd > /dev/null
#------------------------#

#------------------------#
# Build bzip2
#------------------------#
pushd bzip2 > /dev/null

make install -j$(nproc) CFLAGS=-fPIC LDFLAGS=-fPIC PREFIX="$INSTALLDIR"

popd > /dev/null
#------------------------#

#------------------------#
# Build brotli
#------------------------#
pushd brotli > /dev/null

./bootstrap
export CFLAGS="-fPIC"
./configure --enable-static --disable-shared --prefix="$INSTALLDIR"
make install -j$(nproc)

popd > /dev/null
#------------------------#

#------------------------#
# Build libpng
#------------------------#
pushd libpng > /dev/null

export CFLAGS="-fPIC"
./configure --enable-static --disable-shared --prefix="$INSTALLDIR"
make install -j$(nproc)

# --disable-shared does nothing, cool! 
rm -f ../install/lib/libpng*.so*

popd > /dev/null
#------------------------#

#------------------------#
# Build jsonc
#------------------------#
pushd json-c > /dev/null

mkdir -p build && cd build
../cmake-configure --enable-static --prefix="$INSTALLDIR" -- -DDISABLE_EXTRA_LIBS=ON -DCMAKE_BUILD_TYPE="Release"
make install -j$(nproc)

# Once again, no way to cull shared objects!
rm -f "$PWD"/../../install/lib/libjson-c*.so*

popd > /dev/null
#------------------------#


# Uncomment me when libxml2 is required, if ever!
#------------------------#
# Build libxml2
#------------------------#
#pushd libxml2 > /dev/null
#
#export CFLAGS="-fPIC"
#
# Make sure we do not pull anything in, fontconfig needs to do that!
#export Z_LIBS=""
#export LZMA_LIBS=""
#export ICU_LIBS=""
#
# Why does libxml2 have python bindings??
#./autogen.sh --prefix="$PWD/../install" --enable-static --without-icu --enable-shared=no --without-python
#make install -j$(nproc)
#
#popd > /dev/null
#------------------------#

#------------------------#
# Build expat
#------------------------#
pushd libexpat/expat > /dev/null

./buildconf.sh
export CFLAGS="-fPIC"

./configure --without-docbook --without-examples --without-tests --enable-static --enable-shared=no --prefix="$INSTALLDIR"
make install -j$(nproc)

popd > /dev/null
#------------------------#


#------------------------#
# Build freetype
#------------------------#
pushd freetype > /dev/null

# Setup pkgconfig overrides
export LDFLAGS="-L$LIBDIR -Wl,--no-undefined"
export ZLIB_LIBS=""
export BZIP2_LIBS=""
# Manually specify link order for png, bz2, zlib and libm to avoid unresolved symbols due to single pass linking
export LIBPNG_LIBS="$(realpath ../install/lib/libpng.a) -lbz2 -lz -lm"
export BROTLI_LIBS="$(realpath ../install/lib/libbrotlidec.a) $(realpath ../install/lib/libbrotlienc.a) $(realpath ../install/lib/libbrotlicommon.a)"
export CFLAGS="-fPIC"

./autogen.sh
./configure --with-harfbuzz=no --enable-shared --disable-static --prefix="$INSTALLDIR"
make install -j$(nproc)

popd > /dev/null
#------------------------#


#------------------------#
# Build fontconfig
#------------------------#
pushd fontconfig > /dev/null

export LDFLAGS="-L$LIBDIR -Wl,--no-undefined"

# Override pkgconfig stuff
export CFLAGS="-fPIC -I$INCDIR"
export FREETYPE_CFLAGS="-I$INCDIR/freetype2 -I$INCDIR/freetype2/freetype"
export FREETYPE_LIBS="-L$LIBDIR -lfreetype"
export EXPAT_CFLAGS=""
export EXPAT_LIBS="$LIBDIR/libexpat.a"
export JSONC_CFLAGS="-I$INCDIR/json-c"
export JSONC_LIBS="$LIBDIR/libjson-c.a"

./autogen.sh --enable-static=no --prefix="$INSTALLDIR" --with-expat="$INSTALLDIR" 
make install -j$(nproc)

popd > /dev/null
#------------------------#

#------------------------#
# Build cairo
#------------------------#
pushd cairo > /dev/null

export PKG_CONFIG="pkg-config --static" 
export LDFLAGS="-fPIC -L$LIBDIR -Wl,--no-undefined"
export CFLAGS="-fPIC"
export pixman_LIBS="$LIBDIR/libpixman-1.a"
export png_LIBS="$LIBDIR/libpng.a"
export FREETYPE_LIBS="-L$LIBDIR -lfreetype"
export FONTCONFIG_LIBS="-L$LIBDIR -lfontconfig"

./autogen.sh --enable-xlib=no --enable-xlib-xrender=no --enable-xlib-xcb=no --enable-xcb-shm=no --enable-ft --enable-egl=no --without-x --enable-glx=no --enable-wgl=no --enable-quartz=no --enable-svg=yes --enable-pdf=yes --enable-ps=yes --enable-gobject=no --enable-png --disable-static --prefix="$INSTALLDIR"

make install -j$(nproc)

popd > /dev/null
#------------------------#

#------------------------#
# Build pango
#------------------------#
pushd pango > /dev/null

export CFLAGS="-fPIC"
export LDFLAGS="-L$LIBDIR -Wl,--no-undefined -Wl,-Bstatic"
export PKG_CONFIG_PATH="$LIBDIR/pkgconfig"

# When running locally, meson decides to grab cairo-xlib from the system instead of where it SHOULD come from (install/), so we end up with build errors
# there's no way to fix this as far as I can tell, so patch that stupid behavior out.
apply-patch ../patches/pango/meson-cairo.patch

MESON_COMMAND=
[ -f build ] && MESON_COMMAND="--reconfigure"
meson $MESON_COMMAND build --prefix "$INSTALLDIR" --buildtype release --libdir lib --pkg-config-path "$LIBDIR/pkgconfig" --build.pkg-config-path "$LIBDIR/pkgconfig"
cd build
ninja install

popd > /dev/null
#------------------------#
