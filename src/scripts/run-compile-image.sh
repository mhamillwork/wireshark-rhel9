#!/usr/bin/env bash
# Run a command in the compile image.
# A local daemon bind-mounts the checkout. A remote daemon (DOCKER_HOST=tcp://...)
# cannot see that path, so the checkout is copied to /workspace and
# src/build plus src/artifacts are copied back.
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

remote_daemon() {
  case "${DOCKER_HOST:-}" in
    tcp:*|ssh:*|fd:*) return 0 ;;
    *) return 1 ;;
  esac
}

run_local() {
  local status=0
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
  return "$status"
}

wait_for_workspace() {
  local name="$1" _
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if docker exec "$name" test -d /workspace; then
      return 0
    fi
    sleep 0.2
  done
  build_fail "compile container ${name} did not create /workspace"
}

own_remote_outputs() {
  local name="$1"
  [ "$(id -u)" -eq 0 ] && return 0
  docker exec "$name" bash -c \
    'uid="$1"; gid="$2"; for d in /workspace/src/build /workspace/src/artifacts; do if [ -d "$d" ]; then chown -R "${uid}:${gid}" "$d"; fi; done' \
    bash "$(id -u)" "$(id -g)"
}

copy_back() {
  local name="$1" rel stage
  for rel in src/build src/artifacts; do
    stage="$(mktemp -d)"
    if docker cp "${name}:/workspace/${rel}" "${stage}/tree"; then
      rm -rf "${root:?}/${rel}"
      mkdir -p "${root}/src"
      mv "${stage}/tree" "${root}/${rel}"
    fi
    rm -rf "$stage"
  done
}

run_remote() {
  local name status=0
  name="wireshark-${CI_JOB_ID:-$$}"
  # shellcheck disable=SC2064
  trap "docker rm -f '$name' >/dev/null 2>&1 || true" RETURN
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker create --name "$name" --network=host --entrypoint bash "$image" \
    -c 'mkdir -p /workspace && exec sleep infinity' >/dev/null
  docker start "$name" >/dev/null
  wait_for_workspace "$name"
  docker cp "${root}/." "${name}:/workspace/"
  docker exec -w /workspace "$name" "$@" || status=$?
  own_remote_outputs "$name"
  copy_back "$name"
  return "$status"
}

if remote_daemon; then
  run_remote "$@"
else
  run_local "$@"
fi
