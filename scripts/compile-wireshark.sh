#!/usr/bin/env bash
# Configure and compile the Wireshark 4.6.9 tree in this repository.
# Runs inside the UBI 9 compile image (GitLab CI or the compose container).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${SRC_DIR:-$ROOT/wireshark}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
BUILD_TYPE="${CMAKE_BUILD_TYPE:-RelWithDebInfo}"
JOBS="${JOBS:-$(nproc)}"

if [ ! -f "$SRC_DIR/CMakeLists.txt" ]; then
  echo "Wireshark sources not found at $SRC_DIR" >&2
  exit 1
fi

if [ ! -d "$INSTALL_PREFIX" ] || [ ! -w "$INSTALL_PREFIX" ]; then
  mkdir -p "$INSTALL_PREFIX" 2>/dev/null || true
fi
if [ ! -w "$INSTALL_PREFIX" ]; then
  INSTALL_PREFIX="$ROOT/install"
  echo "Using writable install prefix $INSTALL_PREFIX"
  mkdir -p "$INSTALL_PREFIX"
fi

mkdir -p "$BUILD_DIR"

cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX"

cmake --build "$BUILD_DIR" --parallel "$JOBS"
cmake --install "$BUILD_DIR"
cmake --install "$BUILD_DIR" --component Development

echo "tshark: $BUILD_DIR/run/tshark"
echo "wireshark: $BUILD_DIR/run/wireshark"
echo "installed: $INSTALL_PREFIX (libraries and WiresharkConfig.cmake for /sandbox plugins)"
"$BUILD_DIR/run/tshark" -v
QT_QPA_PLATFORM=offscreen "$BUILD_DIR/run/wireshark" --version
