#!/usr/bin/env bash
# Start the compile container. Compose mounts the workstation checkout at /src:
#   ${HOME}/sandbox/wireshark-packet-penguin/src
#
#   ./scripts/clone-into-container.sh
#   ./scripts/clone-into-container.sh --compile
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COMPILE=0
if [ "${1:-}" = "--compile" ]; then
  COMPILE=1
fi

IMAGE="${WIRESHARK_IMAGE:-wireshark-ubi9:dev}"
SANDBOX="${SANDBOX_DIR:-$HOME/sandbox}"
mkdir -p "$SANDBOX"
export SANDBOX_DIR="$SANDBOX"
export WIRESHARK_IMAGE="$IMAGE"

if docker info >/dev/null 2>&1; then
  docker_cmd() { docker "$@"; }
else
  docker_cmd() { sudo docker "$@"; }
fi

if ! docker_cmd image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Docker image $IMAGE is not loaded." >&2
  echo "On a machine that can reach the network, build and export it:" >&2
  echo "  docker build -t $IMAGE ." >&2
  echo "  docker save $IMAGE | gzip > wireshark-ubi9.tar.gz" >&2
  echo "On the isolated machine:" >&2
  echo "  docker load -i wireshark-ubi9.tar.gz" >&2
  exit 1
fi

docker_cmd compose up -d

docker_cmd compose exec -T wireshark-compile bash -lc '
  set -euo pipefail
  if [ ! -f /src/wireshark-4.6.9/CMakeLists.txt ]; then
    echo "Wireshark sources not found at /src/wireshark-4.6.9" >&2
    echo "Compose mounts ~/sandbox/wireshark-packet-penguin/src on /src." >&2
    exit 1
  fi
  echo "Wireshark sources: /src/wireshark-4.6.9"
  echo "Dissector plugins: /src/plugins"
'

if [ "$COMPILE" -eq 1 ]; then
  docker_cmd compose exec -T wireshark-compile /src/scripts/compile-wireshark.sh
fi
