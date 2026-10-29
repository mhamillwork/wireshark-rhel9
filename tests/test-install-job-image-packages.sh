#!/usr/bin/env bash
# The job-image install script selects repos and requests docker-ce.
# Stubs stand in for dnf and rpm. This does not contact Satellite.
# shellcheck disable=SC2030,SC2031
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stubdir="$tmp/bin"
mkdir -p "$stubdir"

cat > "$stubdir/dnf" <<'EOF'
#!/bin/bash
log="${DNF_LOG:?}"
printf '%s\n' "$*" >> "$log"
case "$1" in
  repolist)
    cat <<'LIST'
repo id
ubi-9-codeready-builder-rpms    CodeReady
codeready-builder-for-rhel-9-x86_64-rpms    CRB
docker-ce-stable    Docker
rhel-9-appstream-rpms    AppStream
LIST
    exit 0
    ;;
  clean)
    exit 0
    ;;
esac
if [[ "$*" == *\ remove\ * ]]; then
  exit 0
fi
if [[ "$*" == *\ list\ * ]]; then
  echo "Available packages"
  exit 0
fi
if [[ "$*" == *\ install\ * ]]; then
  exit "${DNF_INSTALL_STATUS:-0}"
fi
echo "unexpected dnf $*" >&2
exit 1
EOF

cat > "$stubdir/rpm" <<'EOF'
#!/bin/bash
if [ "${1:-}" != "-q" ]; then
  exit 1
fi
if [ -z "${RPM_PROVIDER:-}" ]; then
  exit 1
fi
case "$*" in
  *--qf*) printf '%s\n' "$RPM_PROVIDER" ;;
esac
exit 0
EOF

cat > "$stubdir/docker" <<'EOF'
#!/bin/bash
[ "${1:-}" = "--version" ] || exit 1
echo "Docker version 0.0.0"
EOF

cat > "$stubdir/dockerd" <<'EOF'
#!/bin/bash
[ "${1:-}" = "--version" ] || exit 1
echo "Docker version 0.0.0"
EOF

cat > "$stubdir/containerd" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$stubdir"/*

image_root="$tmp/image"
mkdir -p "$image_root/etc/yum.repos.d"
printf 'enabled=1\n' > "$image_root/etc/yum.repos.d/ubi.repo"
printf 'mounted\n' > "$image_root/etc/rhsm-host"

log="$tmp/dnf.log"
: > "$log"
(
  export PATH="$stubdir:$PATH"
  export DNF_LOG="$log"
  export RPM_PROVIDER="other-engine"
  export JOB_IMAGE_ROOT="$image_root"
  bash "$root/src/scripts/install-job-image-packages.sh"
)
grep -F 'remove other-engine' "$log" >/dev/null || fail "conflicting docker provider was kept: $(cat "$log")"
grep -F -- '--enablerepo=ubi-9-codeready-builder-rpms' "$log" >/dev/null || fail "CodeReady Builder was not enabled: $(cat "$log")"
grep -F -- '--enablerepo=docker-ce-stable' "$log" >/dev/null || fail "docker repo was not enabled: $(cat "$log")"
grep -F 'docker-ce' "$log" >/dev/null || fail "docker-ce was not requested: $(cat "$log")"
grep -F 'containerd.io' "$log" >/dev/null || fail "containerd.io was not requested: $(cat "$log")"
grep -F 'iptables' "$log" >/dev/null || fail "iptables was not requested: $(cat "$log")"
grep -F 'openssl' "$log" >/dev/null || fail "openssl was not requested: $(cat "$log")"
[ ! -e "$image_root/etc/rhsm-host" ] || fail "rhsm-host file was left in place"
grep -q '^priority=1$' "$image_root/etc/yum.repos.d/ubi.repo" || fail "ubi.repo did not gain priority"
[ -L "$image_root/etc/rhsm-host" ] || fail "rhsm-host symlink was not restored"

fail_log="$tmp/dnf-fail.log"
: > "$fail_log"
set +e
(
  export PATH="$stubdir:$PATH"
  export DNF_LOG="$fail_log"
  export DNF_INSTALL_STATUS=1
  export RPM_PROVIDER=""
  export JOB_IMAGE_ROOT="$tmp/fail-image"
  bash "$root/src/scripts/install-job-image-packages.sh"
) >"$tmp/fail.out" 2>"$tmp/fail.err"
status=$?
set -e
[ "$status" -eq 1 ] || fail "missing packages exited $status"
grep -F 'job-image: Satellite did not install docker-ce, docker-ce-cli, and containerd.io' "$tmp/fail.err" >/dev/null || fail "missing package error was: $(cat "$tmp/fail.err")"

echo "job-image package install script passed"
