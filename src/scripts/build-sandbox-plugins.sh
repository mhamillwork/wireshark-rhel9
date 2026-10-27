#!/usr/bin/env bash
# Build dissector plugins that call find_package(Wireshark).
# A CMakeLists.txt that calls include(WiresharkPlugin) is compiled inside
# the Wireshark build. compile-wireshark.sh links those in before CMake runs.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

if [ -z "${PACKET_PENGUIN_VERSION:-}" ]; then
  build_load_versions "${RHEL_VERSION:-9}"
fi
if [ -z "${PLUGIN_DIR:-}" ]; then
  build_resolve_plugin_dir
fi

SANDBOX="${SANDBOX:-${PLUGIN_DIR:-}}"
if [ -z "$SANDBOX" ]; then
  if [ -d /src/plugins ]; then
    SANDBOX=/src/plugins
  elif [ -d /sandbox ]; then
    SANDBOX=/sandbox
  fi
fi

PREFIX="${CMAKE_PREFIX_PATH:-${INSTALL_PREFIX:-/usr/local}}"
JOBS="${JOBS:-$(nproc)}"
REQUIRE_PLUGINS="${REQUIRE_PLUGINS:-0}"
if [ -z "${PLUGIN_BUILD_DIR:-}" ]; then
  if [ -n "${RHEL_VERSION:-}" ]; then
    build_layout
    PLUGIN_BUILD_DIR="$BUILD_ROOT/plugins"
  else
    PLUGIN_BUILD_DIR=/tmp/sandbox-plugins
  fi
fi

if [ ! -d "$SANDBOX" ]; then
  echo "No plugin directory at ${SANDBOX:-<unset>}" >&2
  [ "$REQUIRE_PLUGINS" -eq 0 ] || exit 1
  exit 0
fi

echo "Packet Penguin version: ${PACKET_PENGUIN_VERSION:-unset}"
echo "Dissector plugins: $SANDBOX"

while IFS= read -r marker; do
  marked="$(tr -d '[:space:]' < "$marker")"
  [ "$marked" = "${PACKET_PENGUIN_VERSION:-}" ] || build_fail "$(basename "$(dirname "$marker")") version $marked does not match PACKET_PENGUIN_VERSION ${PACKET_PENGUIN_VERSION:-}"
done < <(find "$SANDBOX" -name PACKET_PENGUIN_VERSION -type f | sort)

found=0
plugins=()
while IFS= read -r plugin; do
  [ -n "$plugin" ] || continue
  plugins+=("$plugin")
done < <(build_list_plugin_dirs "$SANDBOX")

if [ "${#plugins[@]}" -gt 0 ]; then
  for plugin in "${plugins[@]}"; do
    found=1
    name="$(basename "$plugin")"
    if build_plugin_is_intree "$plugin"; then
      echo "Plugin $name uses include(WiresharkPlugin) and is compiled inside the Wireshark build"
      continue
    fi
    build_dir="$PLUGIN_BUILD_DIR/$name"
    echo "Building plugin $name"
    cmake -S "$plugin" -B "$build_dir" \
      -DCMAKE_PREFIX_PATH="$PREFIX" \
      -DPACKET_PENGUIN_VERSION="${PACKET_PENGUIN_VERSION:-}"
    cmake --build "$build_dir" --parallel "$JOBS"
    if [ -n "${DESTDIR:-}" ]; then
      DESTDIR="$DESTDIR" cmake --install "$build_dir"
    else
      cmake --install "$build_dir"
    fi
    echo "Plugin build: $build_dir"
  done
fi

if [ "$found" -eq 0 ]; then
  source_count="$(find "$SANDBOX" -type f \( -name '*.c' -o -name '*.cpp' -o -name '*.h' \) -print -quit)"
  if [ -n "$source_count" ]; then
    echo "No out-of-tree CMake plugins under $SANDBOX"
    echo "C sources there are compiled with Wireshark when they are linked into the Wireshark tree"
  else
    echo "No CMakeLists.txt plugins under $SANDBOX" >&2
    [ "$REQUIRE_PLUGINS" -eq 0 ] || exit 1
  fi
fi
