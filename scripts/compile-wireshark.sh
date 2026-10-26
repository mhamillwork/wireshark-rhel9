#!/usr/bin/env bash
# Configure and compile Wireshark 4.6.9.
# Inside the image, run: /src/scripts/compile-wireshark.sh
# Sources are /src/wireshark-4.6.9, next to this script's directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# /src/scripts/compile-wireshark.sh -> /src/wireshark-4.6.9.
# A checkout that still has src/ or wireshark/ at the repo root works too.
if [ -z "${SRC_DIR:-}" ]; then
  SRC_DIR=""
  for candidate in \
    "$ROOT/wireshark-4.6.9" \
    "$ROOT/src/wireshark-4.6.9" \
    "/src/wireshark-4.6.9" \
    "$ROOT/wireshark"
  do
    if [ -f "$candidate/CMakeLists.txt" ]; then
      SRC_DIR="$candidate"
      break
    fi
  done
  if [ -z "$SRC_DIR" ]; then
    SRC_DIR="/src/wireshark-4.6.9"
  fi
fi
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
BUILD_TYPE="${CMAKE_BUILD_TYPE:-RelWithDebInfo}"
JOBS="${JOBS:-$(nproc)}"

if [ ! -f "$SRC_DIR/CMakeLists.txt" ]; then
  echo "Wireshark sources not found at $SRC_DIR" >&2
  exit 1
fi
echo "Wireshark sources: $SRC_DIR"

if [ ! -d "$INSTALL_PREFIX" ] || [ ! -w "$INSTALL_PREFIX" ]; then
  mkdir -p "$INSTALL_PREFIX" 2>/dev/null || true
fi
if [ ! -w "$INSTALL_PREFIX" ]; then
  INSTALL_PREFIX="$ROOT/install"
  echo "Using writable install prefix $INSTALL_PREFIX"
  mkdir -p "$INSTALL_PREFIX"
fi

mkdir -p "$BUILD_DIR"

# RHEL 9 ships Qt 5.15, not Qt 6. Wireshark defaults to Qt 6.
# Ninja cannot rewrite a build-tree RPATH at install time unless CMake
# can patch ELF. Link with the install RPATH from the start.
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DUSE_qt6=OFF

cmake --build "$BUILD_DIR" --parallel "$JOBS"
cmake --install "$BUILD_DIR"
cmake --install "$BUILD_DIR" --component Development

echo "tshark: $BUILD_DIR/run/tshark"
echo "wireshark: $BUILD_DIR/run/wireshark"
echo "installed: $INSTALL_PREFIX (libraries and WiresharkConfig.cmake for /src/plugins)"
"$BUILD_DIR/run/tshark" -v
QT_QPA_PLATFORM=offscreen "$BUILD_DIR/run/wireshark" --version
