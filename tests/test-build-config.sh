#!/usr/bin/env bash
# Argument, version, and path tests. These do not compile Wireshark.
# Fixture values are set inside subshells on purpose. They must not leak.
# shellcheck disable=SC2030,SC2031
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../src/scripts/lib/build-config.sh
source "$root/src/scripts/lib/build-config.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/bad.env" <<'EOF'
WIRESHARK_VERSION=not-a-version
PACKET_PENGUIN_VERSION=1.0.5
RHEL_VERSION=9
RPM_PACKAGE_RELEASE=1
SUPPORTED=1
EOF
if VERSIONS_FILE="$tmp/bad.env" bash -c 'source "'"$root"'/src/scripts/lib/build-config.sh"; build_load_versions 9'; then
  fail "malformed version was accepted"
fi

set +e
missing_out="$(VERSIONS_FILE="$tmp/missing.env" bash -c 'source "'"$root"'/src/scripts/lib/build-config.sh"; build_load_versions 9' 2>&1)"
missing_status=$?
set -e
[ "$missing_status" -ne 0 ] || fail "missing version file was accepted"
printf '%s\n' "$missing_out" | grep -q 'version configuration not found' || fail "missing file error was: $missing_out"
if printf '%s\n' "$missing_out" | grep -q 'WIRESHARK_VERSION is unset'; then
  fail "missing file continued into an empty source: $missing_out"
fi

repo="$tmp/repo"
mkdir -p "$repo/versions" "$repo/scripts/lib" "$repo/wireshark-1.2.3"
cp "$root/src/scripts/lib/build-config.sh" "$repo/scripts/lib/"
cat > "$repo/versions/RHEL9.env" <<'EOF'
WIRESHARK_VERSION=1.2.3
PACKET_PENGUIN_VERSION=9.9.9
RHEL_VERSION=9
RPM_PACKAGE_RELEASE=1
SUPPORTED=1
EOF
printf 'cmake_minimum_required(VERSION 3.16)\n' > "$repo/wireshark-1.2.3/CMakeLists.txt"
(
  cd "$repo"
  # shellcheck source=/dev/null
  source scripts/lib/build-config.sh
  build_load_versions 9
  build_resolve_source_dir
  [ "$SRC_DIR" = "$repo/wireshark-1.2.3" ] || fail "source path resolved to $SRC_DIR"
  [ "$PACKET_PENGUIN_VERSION" = "9.9.9" ] || fail "plugin version was not loaded"
  build_layout
  [ "$BUILD_DIR" = "$repo/build/rhel9/wireshark" ] || fail "build dir is $BUILD_DIR"
  export GITLAB_USER_LOGIN=mhamill CI_COMMIT_SHORT_SHA=a1b2c3d4
  [ "$(build_release_tag)" = "1.2.3-ppv9.9.9-rhel9" ] || fail "release tag $(build_release_tag)"
  [ "$(build_dev_tag)" = "1.2.3-ppv9.9.9-rhel9-dev-mhamill" ] || fail "dev tag $(build_dev_tag)"
  [ "$(build_dev_sha_tag)" = "1.2.3-ppv9.9.9-rhel9-dev-mhamill-a1b2c3d4" ] || fail "sha tag $(build_dev_sha_tag)"
)

rm -rf "$repo/wireshark-1.2.3"
if (
  cd "$repo"
  # shellcheck source=/dev/null
  source scripts/lib/build-config.sh
  build_load_versions 9
  build_resolve_source_dir
); then
  fail "missing source directory was accepted"
fi

# shellcheck disable=SC1091
source "$root/versions/RHEL9.env"
"$root/src/scripts/compile-wireshark.sh" --help >/dev/null
"$root/src/scripts/compile-wireshark.sh" --rhel 9 --check >"$tmp/check.out"
grep -q "Wireshark version: ${WIRESHARK_VERSION}" "$tmp/check.out" || fail "check did not print the Wireshark version"
grep -q "Packet Penguin version: ${PACKET_PENGUIN_VERSION}" "$tmp/check.out" || fail "check did not print the Packet Penguin version"
grep -q "RHEL version: ${RHEL_VERSION}" "$tmp/check.out" || fail "check did not print the RHEL version"
grep -q "wireshark-${WIRESHARK_VERSION}" "$tmp/check.out" || fail "check did not resolve wireshark-\$WIRESHARK_VERSION"
grep -q "src/build/rhel${RHEL_VERSION}/wireshark" "$tmp/check.out" || fail "check did not use src/build"

if "$root/src/scripts/compile-wireshark.sh" --rhel 8 --check >"$tmp/rhel8.out" 2>&1; then
  fail "RHEL 8 was accepted"
fi
grep -q 'not supported' "$tmp/rhel8.out" || fail "RHEL 8 failure did not explain itself"

(
  export BUILD_ROOT="$tmp/publish-build"
  set +e
  release_out="$(ARTIFACTORY_USERNAME=user ARTIFACTORY_PASSWORD=secret BUILD_TYPE=release "$root/src/scripts/publish-image.sh" 2>&1)"
  release_status=$?
  set -e
  [ "$release_status" -ne 0 ] || fail "unprotected release publish was accepted"
  printf '%s\n' "$release_out" | grep -q 'protected Git ref' || fail "release guard said: $release_out"
  if printf '%s\n' "$release_out" | grep -q 'login'; then
    fail "release guard reached registry login: $release_out"
  fi
)

set +e
bad_type="$(BUILD_ROOT="$tmp/publish-build" BUILD_TYPE=nightly "$root/src/scripts/publish-image.sh" 2>&1)"
bad_status=$?
set -e
[ "$bad_status" -ne 0 ] || fail "BUILD_TYPE=nightly was accepted"
printf '%s\n' "$bad_type" | grep -q 'dev or release' || fail "build type error was: $bad_type"

echo "build-config tests passed"
