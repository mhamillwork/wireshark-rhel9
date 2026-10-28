#!/usr/bin/env bash
# The remote-daemon path copies the checkout. A local socket bind-mounts it.
# This uses a stub docker and does not start an engine.
# Fixture values are set inside subshells on purpose. They must not leak.
# shellcheck disable=SC2030,SC2031
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

stubdir="$tmp/bin"
mkdir -p "$stubdir"
cat > "$stubdir/docker" <<'EOF'
#!/bin/bash
log="${DOCKER_STUB_LOG:?}"
{
  printf '%s' "$0"
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
} >> "$log"
cmd="$1"
shift
case "$cmd" in
  image|rm|create|start)
    exit 0
    ;;
  exec)
    if [ "${1:-}" = "-w" ]; then
      exit "${DOCKER_STUB_EXEC_STATUS:-0}"
    fi
    exit 0
    ;;
  cp)
    src="$1"
    dest="$2"
    case "$src" in
      *:/workspace/src/build)
        mkdir -p "$dest"
        echo built > "$dest/marker"
        exit 0
        ;;
      *:*)
        exit 1
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  run)
    exit 0
    ;;
  *)
    echo "unexpected docker $cmd" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$stubdir/docker"

repo="$tmp/repo"
mkdir -p "$repo/src/scripts"
printf 'pipeline\n' > "$repo/.gitlab-ci.yml"
printf 'echo ok\n' > "$repo/src/scripts/validate-repo.sh"

run_case() {
  local log="$1"
  shift
  : > "$log"
  (
    export PATH="$stubdir:$PATH"
    export DOCKER_STUB_LOG="$log"
    export CI_PROJECT_DIR="$repo"
    export WIRESHARK_IMAGE="wireshark-ubi9:dev"
    unset DOCKER_STUB_EXEC_STATUS
    cd "$repo"
    "$@"
  )
}

tcp_log="$tmp/tcp.log"
run_case "$tcp_log" \
  env DOCKER_HOST=tcp://wireshark-docker:2375 \
  "$root/src/scripts/run-compile-image.sh" ./src/scripts/validate-repo.sh --rhel 9
grep -q 'exec -w /workspace' "$tcp_log" || fail "tcp path did not exec in /workspace: $(cat "$tcp_log")"
grep -F "cp ${repo}/." "$tcp_log" | grep -F ':/workspace/' >/dev/null || fail "tcp path did not copy the checkout: $(cat "$tcp_log")"
grep -F 'sleep\ infinity' "$tcp_log" >/dev/null || fail "tcp path did not keep a workspace container: $(cat "$tcp_log")"
if grep -q ' -v ' "$tcp_log"; then
  fail "tcp path bind-mounted the checkout: $(cat "$tcp_log")"
fi
[ -f "$repo/src/build/marker" ] || fail "tcp path did not copy src/build back"
grep -qx built "$repo/src/build/marker" || fail "copied build marker was $(cat "$repo/src/build/marker")"
[ ! -e "$repo/src/artifacts" ] || fail "missing src/artifacts was created"

rm -rf "$repo/src/build"
unix_log="$tmp/unix.log"
run_case "$unix_log" \
  env DOCKER_HOST=unix:///var/run/docker.sock \
  "$root/src/scripts/run-compile-image.sh" ./src/scripts/validate-repo.sh
grep -q -- "-v ${repo}:${repo}" "$unix_log" || fail "local socket did not bind-mount: $(cat "$unix_log")"
if grep -F 'sleep\ infinity' "$unix_log" >/dev/null; then
  fail "local socket copied through a workspace container: $(cat "$unix_log")"
fi

empty_log="$tmp/empty.log"
run_case "$empty_log" \
  env -u DOCKER_HOST \
  "$root/src/scripts/run-compile-image.sh" ./src/scripts/validate-repo.sh
grep -q -- "-v ${repo}:${repo}" "$empty_log" || fail "unset DOCKER_HOST did not bind-mount: $(cat "$empty_log")"

fail_log="$tmp/fail.log"
: > "$fail_log"
set +e
(
  export PATH="$stubdir:$PATH"
  export DOCKER_STUB_LOG="$fail_log"
  export DOCKER_STUB_EXEC_STATUS=9
  export CI_PROJECT_DIR="$repo"
  export DOCKER_HOST=tcp://wireshark-docker:2375
  cd "$repo"
  "$root/src/scripts/run-compile-image.sh" ./src/scripts/validate-repo.sh
)
status=$?
set -e
[ "$status" -eq 9 ] || fail "remote command status was $status"
[ -f "$repo/src/build/marker" ] || fail "failed remote command did not copy src/build back"

echo "run-compile-image remote and local paths passed"
