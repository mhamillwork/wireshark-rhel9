#!/usr/bin/env bash
# In-tree plugins call include(WiresharkPlugin). They configure only as part
# of the Wireshark CMake project. This does not compile Wireshark.
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../src/scripts/lib/build-config.sh
source "$root/src/scripts/lib/build-config.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

src="$tmp/wireshark"
plugins="$tmp/plugins/c/foo"
mkdir -p "$src/cmake/modules" "$plugins" "$tmp/plugins/external"

cat > "$plugins/CMakeLists.txt" <<'EOF'
# CMakeLists.txt
include(WiresharkPlugin)

# Plugin name and version info (major minor micro extra)
set_module_info(foo 0 0 1 0)
EOF

cat > "$tmp/plugins/external/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(External C)
find_package(Wireshark CONFIG REQUIRED)
EOF

cat > "$src/cmake/modules/WiresharkPlugin.cmake" <<'EOF'
macro(set_module_info name)
  message(STATUS "module ${name}")
endmacro()
EOF

cat > "$src/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(fake C)
set(CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake/modules)
if(EXISTS ${CMAKE_SOURCE_DIR}/CMakeListsCustom.txt)
  include(${CMAKE_SOURCE_DIR}/CMakeListsCustom.txt)
endif()
foreach(_plugin_src_dir ${CUSTOM_PLUGIN_SRC_DIR})
  add_subdirectory(${_plugin_src_dir})
endforeach()
EOF

SRC_DIR="$src"
PLUGIN_DIR="$tmp/plugins"
build_prepare_intree_plugins

[ -L "$src/packet-penguin-plugins/c_foo" ] || fail "in-tree plugin was not linked"
[ "$(readlink "$src/packet-penguin-plugins/c_foo")" = "$plugins" ] || fail "plugin link target is wrong"
grep -q 'packet-penguin-plugins/c_foo' "$src/CMakeListsCustom.txt" || fail "custom cmake list omitted the plugin"
if grep -q 'external' "$src/CMakeListsCustom.txt"; then
  fail "find_package plugin was linked into the Wireshark tree"
fi

cmake -S "$src" -B "$tmp/with-parent" >"$tmp/with-parent.log" 2>&1 || fail "parent configure failed: $(cat "$tmp/with-parent.log")"
grep -q 'module foo' "$tmp/with-parent.log" || fail "parent configure did not load the plugin: $(cat "$tmp/with-parent.log")"

# A hand-written custom file is left in place. build_fail exits the shell.
printf 'set(CUSTOM_PLUGIN_SRC_DIR "kept")\n' > "$src/CMakeListsCustom.txt"
set +e
( build_prepare_intree_plugins >"$tmp/keep.log" 2>&1 )
keep_status=$?
set -e
[ "$keep_status" -ne 0 ] || fail "an existing CMakeListsCustom.txt was overwritten"
grep -q 'already exists' "$tmp/keep.log" || fail "overwrite error was: $(cat "$tmp/keep.log")"
grep -q 'kept' "$src/CMakeListsCustom.txt" || fail "existing custom file changed"

rm -rf "$tmp/plugins/external"
export PLUGIN_DIR="$tmp/plugins"
export PLUGIN_BUILD_DIR="$tmp/plugin-build"
export PACKET_PENGUIN_VERSION=1.0.5
"$root/src/scripts/build-sandbox-plugins.sh" >"$tmp/sandbox.log"
grep -q 'compiled inside the Wireshark build' "$tmp/sandbox.log" || fail "sandbox script tried to configure the in-tree plugin: $(cat "$tmp/sandbox.log")"
[ ! -d "$tmp/plugin-build/foo" ] || fail "sandbox script created a standalone build directory"

echo "in-tree plugin tests passed"
