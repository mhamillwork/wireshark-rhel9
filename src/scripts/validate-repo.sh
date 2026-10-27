#!/usr/bin/env bash
# Static checks for the RHEL 9 build. This does not compile Wireshark.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

root="$(build_checkout_root)"
cd "$root"

build_type="${BUILD_TYPE:-dev}"
case "$build_type" in
  dev|release) ;;
  *) build_fail "BUILD_TYPE must be dev or release" ;;
esac

fail=0
while IFS= read -r script; do
  bash -n "$script" || fail=1
done < <(find src/scripts -name '*.sh' -type f | sort)
[ "$fail" -eq 0 ] || build_fail "shell syntax check failed"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -P SCRIPTDIR src/scripts/*.sh src/scripts/lib/*.sh tests/*.sh || build_fail "shellcheck failed"
else
  echo "shellcheck is not installed; syntax checks ran"
fi

"$SCRIPT_DIR/compile-wireshark.sh" --rhel 9 --check
# The version comes from versions/RHEL9.env. This file does not spell the path.
# shellcheck disable=SC1091
source "$root/versions/RHEL9.env"
hardcoded_path="wireshark-${WIRESHARK_VERSION}"
if grep -RIn --exclude-dir=.git -e "$hardcoded_path" src/scripts .gitlab-ci.yml dockerfile versions >/dev/null 2>&1; then
  echo "error: a build script still hardcodes ${hardcoded_path}" >&2
  grep -RIn --exclude-dir=.git -e "$hardcoded_path" src/scripts .gitlab-ci.yml dockerfile versions >&2 || true
  exit 1
fi

grep -q 'BUILD_TYPE' .gitlab-ci.yml || build_fail ".gitlab-ci.yml has no BUILD_TYPE"
grep -q 'wireshark-ppv' src/rpmbuild/RHEL-9/SPECS/wireshark-ppv.spec.in || build_fail "RPM spec template is missing the package name"
grep -q 'FROM registry.access.redhat.com/ubi9/ubi:9.8' dockerfile/RHEL-9/Dockerfile || build_fail "runtime Dockerfile base image changed"

"$root/tests/test-build-config.sh"
if command -v rpmbuild >/dev/null 2>&1; then
  "$root/tests/test-rpm-metadata.sh"
else
  echo "rpmbuild is not installed; RPM metadata test skipped"
fi
echo "Repository validation passed"
