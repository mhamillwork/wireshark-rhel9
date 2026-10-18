#!/usr/bin/env bash
# Build out-of-tree dissector plugins mounted at /sandbox.
# Each immediate subdirectory with a CMakeLists.txt is configured against
# the Wireshark headers installed by scripts/compile-wireshark.sh.
set -euo pipefail

SANDBOX="${SANDBOX:-/sandbox}"
PREFIX="${CMAKE_PREFIX_PATH:-${INSTALL_PREFIX:-/usr/local}}"
JOBS="${JOBS:-$(nproc)}"

if [ ! -d "$SANDBOX" ]; then
  echo "No plugin directory at $SANDBOX" >&2
  exit 1
fi

found=0
for plugin in "$SANDBOX"/*; do
  [ -d "$plugin" ] || continue
  [ -f "$plugin/CMakeLists.txt" ] || continue
  found=1
  name="$(basename "$plugin")"
  build_dir="/tmp/sandbox-plugins/$name"
  echo "Building plugin $name"
  cmake -S "$plugin" -B "$build_dir" -DCMAKE_PREFIX_PATH="$PREFIX"
  cmake --build "$build_dir" --parallel "$JOBS"
  echo "Plugin build: $build_dir"
done

if [ "$found" -eq 0 ]; then
  echo "No CMakeLists.txt plugins under $SANDBOX"
fi
