#!/usr/bin/env bash
# Start the compile container. Compose mounts the checkout read-only and
# leaves /src/scripts in the image. Only src/build is writable.
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
PROJECT="${HOME}/sandbox/wireshark-packet-penguin"
SANDBOX="${SANDBOX_DIR:-$HOME/sandbox}"
export SANDBOX_DIR="$SANDBOX"
export WIRESHARK_IMAGE="$IMAGE"

missing=0
for dir in "$PROJECT" "$PROJECT/src/wireshark-4.6.9" "$PROJECT/src/plugins" "$SANDBOX"; do
  if [ ! -d "$dir" ]; then
    echo "Missing directory: $dir" >&2
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  echo "Compose does not create the checkout or ~/sandbox." >&2
  exit 1
fi
if [ ! -f "$PROJECT/src/scripts/compile-wireshark.sh" ]; then
  echo "Checkout has no src/scripts/compile-wireshark.sh." >&2
  echo "The container uses the copy in the image at /src/scripts." >&2
  echo "Copy that version back with:" >&2
  echo "  mkdir -p \"$PROJECT/src/scripts\"" >&2
  echo "  docker run --rm --entrypoint tar $IMAGE -C /src/scripts -cf - . | tar -C \"$PROJECT/src/scripts\" -xf -" >&2
fi
mkdir -p "$PROJECT/src/build"

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
    exit 1
  fi
  if [ ! -f /src/scripts/compile-wireshark.sh ]; then
    echo "Compile script not found at /src/scripts/compile-wireshark.sh" >&2
    exit 1
  fi
  echo "Wireshark sources: /src/wireshark-4.6.9"
  echo "Compile script: /src/scripts/compile-wireshark.sh"
  echo "Dissector plugins: /src/plugins"
'

if [ "$COMPILE" -eq 1 ]; then
  docker_cmd compose exec -T wireshark-compile /src/scripts/compile-wireshark.sh
fi
