#!/usr/bin/env bash
# Configure and compile Wireshark, then the Packet Penguin plugins when present.
# Versions come from versions/RHEL<n>.env.
#
#   ./src/scripts/compile-wireshark.sh --rhel 9
#   ./src/scripts/compile-wireshark.sh --rhel 9 --clean --build --test
#   ./src/scripts/compile-wireshark.sh --rhel 9 --package
#   ./src/scripts/compile-wireshark.sh --help
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

trap 'echo "error: ${BASH_SOURCE[0]}:${LINENO}: command failed" >&2' ERR

usage() {
  cat <<'EOF'
Usage: compile-wireshark.sh [--rhel 9] [--clean] [--build] [--test] [--package] [--check]

  --rhel N    Load versions/RHELN.env. Default: 9.
  --clean     Remove the CMake build directory under src/build (rhelN/wireshark).
  --build     Configure, compile, and install Wireshark and any CMake plugins.
  --test      Run tshark and the Wireshark GUI version check.
  --package   Build the RHEL RPM from the staged install.
  --check     Load versions, resolve paths, and exit.
  --help      Show this help.

With no mode flags, the script builds and runs the version checks.
EOF
}

RHEL=9
DO_CLEAN=0
DO_BUILD=0
DO_TEST=0
DO_PACKAGE=0
DO_CHECK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --rhel)
      [ $# -ge 2 ] || build_fail "--rhel requires a version"
      RHEL="$2"
      shift 2
      ;;
    --clean) DO_CLEAN=1; shift ;;
    --build) DO_BUILD=1; shift ;;
    --test) DO_TEST=1; shift ;;
    --package) DO_PACKAGE=1; DO_BUILD=1; shift ;;
    --check) DO_CHECK=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) build_fail "unknown argument: $1" ;;
  esac
done

if [ "$DO_CLEAN" -eq 0 ] && [ "$DO_BUILD" -eq 0 ] && [ "$DO_TEST" -eq 0 ] && [ "$DO_PACKAGE" -eq 0 ] && [ "$DO_CHECK" -eq 0 ]; then
  DO_BUILD=1
  DO_TEST=1
fi

build_load_versions "$RHEL"
build_resolve_source_dir
build_resolve_plugin_dir
build_layout
build_print_versions
echo "Build directory: $BUILD_DIR"
echo "Staging directory: $STAGING_DIR"

if [ "$DO_CHECK" -eq 1 ]; then
  exit 0
fi

mkdir -p "$LOG_DIR"

if [ "$DO_CLEAN" -eq 1 ]; then
  rm -rf "$BUILD_DIR"
fi

if [ "$DO_BUILD" -eq 1 ]; then
  for tool in cmake ninja gcc; do
    command -v "$tool" >/dev/null 2>&1 || build_fail "required tool not found: $tool"
  done

  INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
  BUILD_TYPE="${CMAKE_BUILD_TYPE:-RelWithDebInfo}"
  JOBS="${JOBS:-$(nproc)}"

  if [ ! -d "$INSTALL_PREFIX" ] || [ ! -w "$INSTALL_PREFIX" ]; then
    mkdir -p "$INSTALL_PREFIX" 2>/dev/null || true
  fi
  if [ ! -w "$INSTALL_PREFIX" ]; then
    INSTALL_PREFIX="$BUILD_ROOT/install"
    echo "Using writable install prefix $INSTALL_PREFIX"
    mkdir -p "$INSTALL_PREFIX"
  fi
  export INSTALL_PREFIX

  mkdir -p "$BUILD_DIR"
  # RHEL 9 ships Qt 5.15, not Qt 6. Wireshark defaults to Qt 6.
  # Ninja cannot rewrite a build-tree RPATH at install time unless CMake
  # can patch ELF. Link with the install RPATH from the start.
  build_prepare_intree_plugins
  cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    -DUSE_qt6=OFF

  cmake --build "$BUILD_DIR" --parallel "$JOBS"

  libdir=lib64
  if [ -f "$BUILD_DIR/CMakeCache.txt" ]; then
    cached="$(sed -n 's/^CMAKE_INSTALL_LIBDIR:[^=]*=//p' "$BUILD_DIR/CMakeCache.txt" | head -1)"
    if [ -n "$cached" ]; then
      libdir="$cached"
    fi
  fi
  mkdir -p "$BUILD_DIR/$libdir"
  shopt -s nullglob
  for so in "$BUILD_DIR/run"/lib*.so*; do
    ln -sfn "../run/$(basename "$so")" "$BUILD_DIR/$libdir/$(basename "$so")"
  done
  shopt -u nullglob

  cmake --install "$BUILD_DIR"
  cmake --install "$BUILD_DIR" --component Development

  if [ -n "${PLUGIN_DIR:-}" ]; then
    REQUIRE_PLUGINS="${REQUIRE_PLUGINS:-0}"
    if [ "$DO_PACKAGE" -eq 1 ]; then
      REQUIRE_PLUGINS=1
    fi
    export REQUIRE_PLUGINS PLUGIN_DIR PACKET_PENGUIN_VERSION
    export PLUGIN_BUILD_DIR="$BUILD_ROOT/plugins"
    "$SCRIPT_DIR/build-sandbox-plugins.sh"
  elif [ "$DO_PACKAGE" -eq 1 ]; then
    build_fail "Packet Penguin plugin directory is missing"
  else
    echo "No plugin directory found; Wireshark was built without Packet Penguin plugins"
  fi
fi

if [ "$DO_PACKAGE" -eq 1 ]; then
  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR"
  DESTDIR="$STAGING_DIR" cmake --install "$BUILD_DIR"
  DESTDIR="$STAGING_DIR" cmake --install "$BUILD_DIR" --component Development
  if [ -n "${PLUGIN_DIR:-}" ]; then
    DESTDIR="$STAGING_DIR" "$SCRIPT_DIR/build-sandbox-plugins.sh"
  fi
  "$SCRIPT_DIR/build-rpm.sh"
fi

if [ "$DO_TEST" -eq 1 ]; then
  [ -x "$BUILD_DIR/run/tshark" ] || build_fail "tshark was not built at $BUILD_DIR/run/tshark"
  [ -x "$BUILD_DIR/run/wireshark" ] || build_fail "wireshark was not built at $BUILD_DIR/run/wireshark"
  export LD_LIBRARY_PATH="$BUILD_DIR/run${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  echo "tshark: $BUILD_DIR/run/tshark"
  echo "wireshark: $BUILD_DIR/run/wireshark"
  "$BUILD_DIR/run/tshark" -v
  QT_QPA_PLATFORM=offscreen "$BUILD_DIR/run/wireshark" --version
  pcap="$SRC_DIR/test/captures/dhcp.pcap"
  if [ -f "$pcap" ]; then
    "$BUILD_DIR/run/tshark" -n -r "$pcap" >/dev/null
    echo "Capture check: $pcap"
  fi
fi
