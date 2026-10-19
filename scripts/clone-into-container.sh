#!/usr/bin/env bash
# Start the compile container and clone this project into it.
#
# Offline (default): clone the checkout mounted at /workspace.
# Connected GitLab: set WIRESHARK_GIT_URL (and optional WIRESHARK_GIT_REF).
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

export WIRESHARK_GIT_URL="${WIRESHARK_GIT_URL:-}"
export WIRESHARK_GIT_REF="${WIRESHARK_GIT_REF:-}"

docker_cmd compose exec -T \
  -e WIRESHARK_GIT_URL \
  -e WIRESHARK_GIT_REF \
  wireshark-compile \
  bash -lc '
    set -euo pipefail
    git config --global --add safe.directory /workspace
    rm -rf /src/project
    if [ -n "${WIRESHARK_GIT_URL:-}" ]; then
      if [ -n "${WIRESHARK_GIT_REF:-}" ]; then
        git clone --depth 1 --branch "$WIRESHARK_GIT_REF" "$WIRESHARK_GIT_URL" /src/project
      else
        git clone --depth 1 "$WIRESHARK_GIT_URL" /src/project
      fi
    else
      git clone --no-local /workspace /src/project
    fi
    test -f /src/project/wireshark/CMakeLists.txt
    echo "Wireshark sources: /src/project/wireshark"
    echo "Dissector plugins: /sandbox"
  '

if [ "$COMPILE" -eq 1 ]; then
  docker_cmd compose exec -T -w /src/project wireshark-compile ./scripts/compile-wireshark.sh
fi
