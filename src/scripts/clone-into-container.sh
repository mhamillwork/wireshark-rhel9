#!/usr/bin/env bash
# Start the compile container. Compose mounts the workstation checkout at /src:
#   ${HOME}/sandbox/wireshark-packet-penguin/src
#
#   ./src/scripts/clone-into-container.sh
#   ./src/scripts/clone-into-container.sh --compile
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"
ROOT="$(build_checkout_root)"
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
  echo "Build it on this network. Satellite is not in the image hosts file:" >&2
  echo "  docker build --add-host satellite9b.hsv.local:10.10.106.59 -f dockerfile/Dockerfile.wireshark-ubi9-build -t $IMAGE ." >&2
  exit 1
fi

docker_cmd compose up -d

docker_cmd compose exec -T wireshark-compile /src/scripts/compile-wireshark.sh --rhel 9 --check

if [ "$COMPILE" -eq 1 ]; then
  docker_cmd compose exec -T wireshark-compile /src/scripts/compile-wireshark.sh --rhel 9 --build --test
fi
