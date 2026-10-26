#!/usr/bin/env bash
# Configure and compile the Wireshark 4.6.9 tree in this repository.
# Runs inside the UBI 9 compile image (GitLab CI or the compose container).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Prefer the tree copied from src/ in the GitLab repo. Fall back to a
# checkout that still keeps the sources at wireshark/.
if [ -z "${SRC_DIR:-}" ]; then
  SRC_DIR=""
  for candidate in \
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
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DUSE_qt6=OFF

cmake --build "$BUILD_DIR" --parallel "$JOBS"
cmake --install "$BUILD_DIR"
cmake --install "$BUILD_DIR" --component Development

echo "tshark: $BUILD_DIR/run/tshark"
echo "wireshark: $BUILD_DIR/run/wireshark"
echo "installed: $INSTALL_PREFIX (libraries and WiresharkConfig.cmake for /src/plugins)"
"$BUILD_DIR/run/tshark" -v
QT_QPA_PLATFORM=offscreen "$BUILD_DIR/run/wireshark" --version
