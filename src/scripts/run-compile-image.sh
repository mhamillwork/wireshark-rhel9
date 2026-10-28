#!/usr/bin/env bash
# Run a command in the compile image with the Git checkout mounted.
# The image is the local tag from build-compile-image. This does not pull it.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

[ "$#" -ge 1 ] || build_fail "usage: run-compile-image.sh <command> [args...]"
command -v docker >/dev/null 2>&1 || build_fail "docker is required"

image="${WIRESHARK_IMAGE:-wireshark-ubi9:dev}"
root="${CI_PROJECT_DIR:-$(build_checkout_root)}"
if ! docker image inspect "$image" >/dev/null 2>&1; then
  build_fail "compile image ${image} is not on this Docker daemon. The compile-image job has to run on this runner first"
fi

status=0
docker run --rm \
  -v "${root}:${root}" \
  -w "$root" \
  "$image" \
  "$@" || status=$?

if [ "$(id -u)" -ne 0 ]; then
  docker run --rm \
    -v "${root}:${root}" \
    "$image" \
    chown -R "$(id -u):$(id -g)" "$root" || true
fi
exit "$status"
