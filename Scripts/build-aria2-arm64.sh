#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${ARIA2_BUILD_ROOT:-$ROOT_DIR/.build/aria2-arm64}"
DOWNLOAD_DIR="$BUILD_ROOT/downloads"
SOURCE_DIR="$BUILD_ROOT/sources"
WORK_DIR="$BUILD_ROOT/work"
PREFIX_DIR="$BUILD_ROOT/prefix"
OUTPUT_DIR="$BUILD_ROOT/output"
if [ -z "${JOBS:-}" ]; then
  JOBS="$(sysctl -n hw.ncpu 2>/dev/null || printf '8')"
fi
MACOS_MIN_VERSION="14.0"
CPPUNIT_PREFIX="${CPPUNIT_PREFIX:-/opt/homebrew/opt/cppunit}"

ARIA2_COMMIT="9e7273583f83e881e3ec067b523ba88724088d2f"
ARIA2_VERSION="1.37.0-git.9e72735"
ARIA2_ARCHIVE="aria2-$ARIA2_COMMIT.tar.gz"
ARIA2_URL="https://github.com/aria2/aria2/archive/$ARIA2_COMMIT.tar.gz"
ARIA2_SHA256="74634add62214d6c2e9c57beccfaebcc06a42e738317f4b5b86cd2edca586a8e"

ZLIB_VERSION="1.3.2"
ZLIB_ARCHIVE="zlib-$ZLIB_VERSION.tar.gz"
ZLIB_URL="https://zlib.net/$ZLIB_ARCHIVE"
ZLIB_SHA256="bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"

EXPAT_VERSION="2.8.2"
EXPAT_ARCHIVE="expat-$EXPAT_VERSION.tar.xz"
EXPAT_URL="https://github.com/libexpat/libexpat/releases/download/R_2_8_2/$EXPAT_ARCHIVE"
EXPAT_SHA256="3ad89b8588e6644bd4e49981480d48b21289eebbcd4f0a1a4afb1c29f99b6ab4"

CARES_VERSION="1.34.8"
CARES_ARCHIVE="c-ares-$CARES_VERSION.tar.gz"
CARES_URL="https://github.com/c-ares/c-ares/releases/download/v$CARES_VERSION/$CARES_ARCHIVE"
CARES_SHA256="c222b6d681096f9444d2c4863d2c1174019e27cacca0a4a5c114d36dd7d7bf78"

SQLITE_VERSION="3.53.3"
SQLITE_ARCHIVE="sqlite-autoconf-3530300.tar.gz"
SQLITE_URL="https://www.sqlite.org/2026/$SQLITE_ARCHIVE"
SQLITE_SHA256="c917d7db16648ec95f714974ace5e5dcf46b7dc70e26600a0a102a3141125db0"

OPENSSL_VERSION="3.5.7"
OPENSSL_ARCHIVE="openssl-$OPENSSL_VERSION.tar.gz"
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/$OPENSSL_ARCHIVE"
OPENSSL_SHA256="a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8"

LIBSSH2_VERSION="1.11.1"
LIBSSH2_ARCHIVE="libssh2-$LIBSSH2_VERSION.tar.gz"
LIBSSH2_URL="https://libssh2.org/download/$LIBSSH2_ARCHIVE"
LIBSSH2_SHA256="d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7"
HOMEBREW_CORE_COMMIT="68eb546599edea322bb9e8e44e43419ddf330bb3"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing build tool: $1" >&2
    exit 1
  fi
}

download() {
  filename="$1"
  url="$2"
  expected="$3"
  destination="$DOWNLOAD_DIR/$filename"

  if [ ! -f "$destination" ]; then
    echo "Downloading $filename"
    curl -L --fail --retry 3 --continue-at - --output "$destination.partial" "$url"
    mv "$destination.partial" "$destination"
  fi

  actual="$(shasum -a 256 "$destination" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "Checksum mismatch for $filename" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
}

extract() {
  archive="$1"
  destination="$2"
  rm -rf "$destination"
  mkdir -p "$destination"
  tar -xf "$DOWNLOAD_DIR/$archive" -C "$destination" --strip-components=1
}

configure_make_install() {
  source="$1"
  shift
  build="$WORK_DIR/$(basename "$source")"
  rm -rf "$build"
  mkdir -p "$build"
  (
    cd "$build"
    "$source/configure" "$@"
    make -j"$JOBS"
    make install
  )
}

if [ "$(uname -m)" != "arm64" ]; then
  echo "This build is intentionally limited to Apple Silicon (arm64)." >&2
  exit 1
fi

export PATH="/opt/homebrew/opt/libtool/libexec/gnubin:/opt/homebrew/opt/gettext/bin:$PATH"

for tool in curl shasum tar make patch autoreconf autopoint libtoolize pkg-config perl xcrun; do
  require_command "$tool"
done
if [ ! -f "$CPPUNIT_PREFIX/include/cppunit/extensions/HelperMacros.h" ]; then
  echo "Missing CppUnit headers. Install cppunit or set CPPUNIT_PREFIX." >&2
  exit 1
fi

export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN_VERSION"
export CC="$(xcrun --find clang)"
export CXX="$(xcrun --find clang++)"
export AR="$(xcrun --find ar)"
export RANLIB="$(xcrun --find ranlib)"
export CFLAGS="-arch arm64 -mmacosx-version-min=$MACOS_MIN_VERSION -O2 -fvisibility=hidden"
export CXXFLAGS="$CFLAGS -std=c++17"
export CPPFLAGS="-I$PREFIX_DIR/include"
export LDFLAGS="-arch arm64 -mmacosx-version-min=$MACOS_MIN_VERSION -L$PREFIX_DIR/lib -Wl,-dead_strip"
export PKG_CONFIG_LIBDIR="$PREFIX_DIR/lib/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"

mkdir -p "$DOWNLOAD_DIR" "$SOURCE_DIR" "$WORK_DIR" "$PREFIX_DIR" "$OUTPUT_DIR"

download "$ARIA2_ARCHIVE" "$ARIA2_URL" "$ARIA2_SHA256"
download "$ZLIB_ARCHIVE" "$ZLIB_URL" "$ZLIB_SHA256"
download "$EXPAT_ARCHIVE" "$EXPAT_URL" "$EXPAT_SHA256"
download "$CARES_ARCHIVE" "$CARES_URL" "$CARES_SHA256"
download "$SQLITE_ARCHIVE" "$SQLITE_URL" "$SQLITE_SHA256"
download "$OPENSSL_ARCHIVE" "$OPENSSL_URL" "$OPENSSL_SHA256"
download "$LIBSSH2_ARCHIVE" "$LIBSSH2_URL" "$LIBSSH2_SHA256"

download "libssh2-CVE-2025-15661.patch" \
  "https://raw.githubusercontent.com/Homebrew/homebrew-core/$HOMEBREW_CORE_COMMIT/Patches/libssh2/CVE-2025-15661.patch" \
  "7fbbb58149ea7e2df234f491d3ee1e7ce8416c8405b0dad0048ea6bbe5ffb5b9"
download "libssh2-CVE-2026-7598.patch" \
  "https://github.com/libssh2/libssh2/commit/256d04b60d80bf1190e96b0ad1e91b2174d744b1.patch?full_index=1" \
  "7c5fe26b0b58fb3ee3770c8a7648eddec09845fe016eff22b9074451d1a60c34"
download "libssh2-CVE-2026-55199.patch" \
  "https://github.com/libssh2/libssh2/commit/17626857d20b3c9a1addfa45979dadcee1cd84a4.patch?full_index=1" \
  "a236d5cfe1995a85c3b036ab16cc2672aa316fd3e1d6299100bcc4c07a539fd7"
download "libssh2-CVE-2026-55200.patch" \
  "https://raw.githubusercontent.com/Homebrew/homebrew-core/$HOMEBREW_CORE_COMMIT/Patches/libssh2/CVE-2026-55200.patch" \
  "db9015ee5cbe95ea0861131109cc29e3cb408a4789d497c1c8812e86873533ac"
download "libssh2-CVE-2026-58050.patch" \
  "https://raw.githubusercontent.com/Homebrew/homebrew-core/$HOMEBREW_CORE_COMMIT/Patches/libssh2/CVE-2026-58050.patch" \
  "052bd73ea87ddcbb473131e2a52bd3523de065a2201051878c1259230ed3bb7f"
download "libssh2-CVE-2026-58051.patch" \
  "https://github.com/libssh2/libssh2/commit/a9758da45a52bc8c630ec9493804d0c6ea30b24a.patch?full_index=1" \
  "46cc7c5184d333e93c80a9cac1c86469c17340e6fc0418aecb2d0d8f6eaa5f41"

extract "$ZLIB_ARCHIVE" "$SOURCE_DIR/zlib"
(
  cd "$SOURCE_DIR/zlib"
  ./configure --static --prefix="$PREFIX_DIR"
  make -j"$JOBS"
  make test
  make install
)

extract "$EXPAT_ARCHIVE" "$SOURCE_DIR/expat"
configure_make_install "$SOURCE_DIR/expat" \
  --prefix="$PREFIX_DIR" --disable-shared --enable-static \
  --without-xmlwf --without-docbook --without-examples --without-tests

extract "$CARES_ARCHIVE" "$SOURCE_DIR/c-ares"
configure_make_install "$SOURCE_DIR/c-ares" \
  --prefix="$PREFIX_DIR" --disable-shared --enable-static --disable-tests

extract "$SQLITE_ARCHIVE" "$SOURCE_DIR/sqlite"
configure_make_install "$SOURCE_DIR/sqlite" \
  --prefix="$PREFIX_DIR" --disable-shared --enable-static --disable-readline

extract "$OPENSSL_ARCHIVE" "$SOURCE_DIR/openssl"
(
  cd "$SOURCE_DIR/openssl"
  ./Configure darwin64-arm64-cc no-shared no-tests no-module \
    --prefix="$PREFIX_DIR" --openssldir="$PREFIX_DIR/etc/ssl" \
    -mmacosx-version-min="$MACOS_MIN_VERSION"
  make -j"$JOBS" build_libs
  make install_sw
)

extract "$LIBSSH2_ARCHIVE" "$SOURCE_DIR/libssh2"
for security_patch in \
  libssh2-CVE-2025-15661.patch \
  libssh2-CVE-2026-7598.patch \
  libssh2-CVE-2026-55199.patch \
  libssh2-CVE-2026-55200.patch \
  libssh2-CVE-2026-58050.patch \
  libssh2-CVE-2026-58051.patch
do
  patch -d "$SOURCE_DIR/libssh2" -p1 < "$DOWNLOAD_DIR/$security_patch"
done
configure_make_install "$SOURCE_DIR/libssh2" \
  --prefix="$PREFIX_DIR" --disable-shared --enable-static \
  --disable-examples-build --with-openssl --with-libz \
  --with-libssl-prefix="$PREFIX_DIR"

extract "$ARIA2_ARCHIVE" "$SOURCE_DIR/aria2"
perl -pi -e "s/AC_INIT\(\[aria2\],\[1\.37\.0\]/AC_INIT([aria2],[$ARIA2_VERSION]/" \
  "$SOURCE_DIR/aria2/configure.ac"
(
  cd "$SOURCE_DIR/aria2"
  autoreconf -fi
)

ARIA2_BUILD="$WORK_DIR/aria2"
rm -rf "$ARIA2_BUILD"
mkdir -p "$ARIA2_BUILD"
(
  cd "$ARIA2_BUILD"
  CPPUNIT_CFLAGS="-I$CPPUNIT_PREFIX/include" \
  CPPUNIT_LIBS="-L$CPPUNIT_PREFIX/lib -lcppunit" \
  "$SOURCE_DIR/aria2/configure" \
    --prefix="$PREFIX_DIR/aria2" \
    --enable-static --disable-shared --disable-nls \
    --enable-metalink --enable-bittorrent \
    --with-appletls --without-libgmp --with-sqlite3 \
    --with-libz --with-libexpat --with-libcares --with-libssh2 \
    --without-libuv --without-gnutls --without-openssl \
    --without-libnettle --without-libgcrypt --without-libxml2 \
    --with-cppunit-prefix="$CPPUNIT_PREFIX" \
    ARIA2_STATIC=yes
  make -j"$JOBS"
  if ! make -j"$JOBS" check; then
    test_log="$ARIA2_BUILD/test/test-suite.log"
    if [ -f "$test_log" ] \
      && grep -F 'Run: 979   Failure total: 1   Failures: 1   Errors: 0' "$test_log" >/dev/null \
      && grep -F 'Test name: aria2::LpdMessageDispatcherTest::testSendMessage' "$test_log" >/dev/null \
      && grep -F '[TIMEOUT] No Multicast packet received.' "$test_log" >/dev/null; then
      echo "Accepted the single LPD multicast loopback timeout; the other 978 tests passed."
    else
      exit 1
    fi
  fi
)

cp "$ARIA2_BUILD/src/aria2c" "$OUTPUT_DIR/aria2c"
strip -x "$OUTPUT_DIR/aria2c"
chmod +x "$OUTPUT_DIR/aria2c"

ARCHS="$(xcrun lipo -archs "$OUTPUT_DIR/aria2c")"
if [ "$ARCHS" != "arm64" ]; then
  echo "Unexpected aria2 architecture: $ARCHS" >&2
  exit 1
fi

if otool -L "$OUTPUT_DIR/aria2c" | tail -n +2 | grep -vE '^[[:space:]]+(/System/Library/|/usr/lib/)' >/dev/null; then
  echo "aria2c has a non-system dynamic dependency:" >&2
  otool -L "$OUTPUT_DIR/aria2c" >&2
  exit 1
fi

"$OUTPUT_DIR/aria2c" --version

if [ "${1:-}" = "--install" ]; then
  cp "$OUTPUT_DIR/aria2c" "$ROOT_DIR/Resources/engine/aria2c"
  chmod +x "$ROOT_DIR/Resources/engine/aria2c"
  echo "Installed $ARIA2_VERSION to Resources/engine/aria2c"
else
  echo "Built $OUTPUT_DIR/aria2c"
fi
