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
set +e
bad_out="$(VERSIONS_FILE="$tmp/bad.env" bash -c 'source "'"$root"'/src/scripts/lib/build-config.sh"; build_load_versions 9' 2>&1)"
bad_status=$?
set -e
[ "$bad_status" -ne 0 ] || fail "malformed version was accepted"
printf '%s\n' "$bad_out" | grep -q 'malformed WIRESHARK_VERSION' || fail "malformed version error was: $bad_out"

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
  [ "$(build_build_image_tag)" = "1.2.3-ppv9.9.9-rhel9-build" ] || fail "build image tag $(build_build_image_tag)"
  [ "$(build_dev_tag)" = "1.2.3-ppv9.9.9-rhel9-dev-mhamill" ] || fail "dev tag $(build_dev_tag)"
  [ "$(build_dev_sha_tag)" = "1.2.3-ppv9.9.9-rhel9-dev-mhamill-a1b2c3d4" ] || fail "sha tag $(build_dev_sha_tag)"
)

rm -rf "$repo/wireshark-1.2.3"
set +e
missing_src="$(
  cd "$repo" || exit 1
  # shellcheck source=/dev/null
  source scripts/lib/build-config.sh
  build_load_versions 9
  build_resolve_source_dir 2>&1
)"
missing_src_status=$?
set -e
[ "$missing_src_status" -ne 0 ] || fail "missing source directory was accepted"
printf '%s\n' "$missing_src" | grep -q 'Wireshark source directory not found' || fail "missing source error was: $missing_src"

# shellcheck disable=SC1091
source "$root/versions/RHEL9.env"
"$root/src/scripts/compile-wireshark.sh" --help >/dev/null
"$root/src/scripts/compile-wireshark.sh" --rhel 9 --check >"$tmp/check.out"
grep -q "Wireshark version: ${WIRESHARK_VERSION}" "$tmp/check.out" || fail "check did not print the Wireshark version"
grep -q "Packet Penguin version: ${PACKET_PENGUIN_VERSION}" "$tmp/check.out" || fail "check did not print the Packet Penguin version"
grep -q "RHEL version: ${RHEL_VERSION}" "$tmp/check.out" || fail "check did not print the RHEL version"
grep -q "wireshark-${WIRESHARK_VERSION}" "$tmp/check.out" || fail "check did not resolve wireshark-\$WIRESHARK_VERSION"
grep -q "src/build/rhel${RHEL_VERSION}/wireshark" "$tmp/check.out" || fail "check did not use src/build"

(
  # shellcheck disable=SC1091
  source "$root/src/scripts/lib/build-config.sh"
  build_load_versions 9
  expected="${WIRESHARK_VERSION}-ppv${PACKET_PENGUIN_VERSION}-rhel${RHEL_VERSION}"
  [ "$(build_release_tag)" = "$expected" ] || fail "release tag does not follow the versions file: $(build_release_tag)"
  [ "$(build_build_image_tag)" = "${expected}-build" ] || fail "build image tag does not follow the versions file: $(build_build_image_tag)"
  [ "$ARTIFACTORY_RPM_REPOSITORY" = "tahaa-rpm-local" ] || fail "rpm repository is $ARTIFACTORY_RPM_REPOSITORY"
)

if "$root/src/scripts/compile-wireshark.sh" --rhel 8 --check >"$tmp/rhel8.out" 2>&1; then
  fail "RHEL 8 was accepted"
fi
grep -q 'not supported' "$tmp/rhel8.out" || fail "RHEL 8 failure did not explain itself"

(
  export BUILD_ROOT="$tmp/publish-build"
  # GitLab sets CI_COMMIT_REF_PROTECTED=true for the validate job on main.
  # Pin both variables so that value cannot skip a guard.
  set +e
  release_out="$(CI_COMMIT_REF_PROTECTED=false CI_COMMIT_TAG='' ARTIFACTORY_USERNAME=user ARTIFACTORY_PASSWORD=secret BUILD_TYPE=release "$root/src/scripts/publish-image.sh" 2>&1)"
  release_status=$?
  set -e
  [ "$release_status" -ne 0 ] || fail "unprotected release publish was accepted"
  printf '%s\n' "$release_out" | grep -q 'protected Git ref' || fail "release guard said: $release_out"
  if printf '%s\n' "$release_out" | grep -q 'login'; then
    fail "release guard reached registry login: $release_out"
  fi

  set +e
  tag_out="$(CI_COMMIT_REF_PROTECTED=true CI_COMMIT_TAG='not-the-release' ARTIFACTORY_USERNAME=user ARTIFACTORY_PASSWORD=secret BUILD_TYPE=release "$root/src/scripts/publish-image.sh" 2>&1)"
  tag_status=$?
  set -e
  [ "$tag_status" -ne 0 ] || fail "release publish with the wrong git tag was accepted"
  printf '%s\n' "$tag_out" | grep -q 'requires git tag' || fail "tag guard said: $tag_out"
  if printf '%s\n' "$tag_out" | grep -q 'login'; then
    fail "tag guard reached registry login: $tag_out"
  fi
)

(
  export BUILD_ROOT="$tmp/publish-build"
  set +e
  dev_rpm="$(CI_COMMIT_TAG='' BUILD_TYPE=dev "$root/src/scripts/publish-rpm.sh" 2>&1)"
  dev_rpm_status=$?
  set -e
  [ "$dev_rpm_status" -ne 0 ] || fail "dev RPM publish was accepted"
  printf '%s\n' "$dev_rpm" | grep -q 'only for BUILD_TYPE=release' || fail "dev RPM publish said: $dev_rpm"
  if printf '%s\n' "$dev_rpm" | grep -q 'https://'; then
    fail "dev RPM publish reached Artifactory: $dev_rpm"
  fi

  set +e
  release_rpm="$(CI_COMMIT_REF_PROTECTED=false CI_COMMIT_TAG='' ARTIFACTORY_USERNAME=user ARTIFACTORY_PASSWORD=secret BUILD_TYPE=release "$root/src/scripts/publish-rpm.sh" 2>&1)"
  release_rpm_status=$?
  set -e
  [ "$release_rpm_status" -ne 0 ] || fail "unprotected RPM publish was accepted"
  printf '%s\n' "$release_rpm" | grep -q 'protected Git ref' || fail "RPM release guard said: $release_rpm"
  if printf '%s\n' "$release_rpm" | grep -q 'https://'; then
    fail "unprotected RPM publish reached Artifactory: $release_rpm"
  fi

  set +e
  tag_rpm="$(CI_COMMIT_REF_PROTECTED=true CI_COMMIT_TAG='not-the-release' ARTIFACTORY_USERNAME=user ARTIFACTORY_PASSWORD=secret BUILD_TYPE=release "$root/src/scripts/publish-rpm.sh" 2>&1)"
  tag_rpm_status=$?
  set -e
  [ "$tag_rpm_status" -ne 0 ] || fail "RPM publish with the wrong git tag was accepted"
  printf '%s\n' "$tag_rpm" | grep -q 'requires git tag' || fail "RPM tag guard said: $tag_rpm"
  if printf '%s\n' "$tag_rpm" | grep -q 'https://'; then
    fail "RPM tag guard reached Artifactory: $tag_rpm"
  fi
)

set +e
bad_type="$(BUILD_ROOT="$tmp/publish-build" BUILD_TYPE=nightly "$root/src/scripts/publish-image.sh" 2>&1)"
bad_status=$?
set -e
[ "$bad_status" -ne 0 ] || fail "BUILD_TYPE=nightly was accepted"
printf '%s\n' "$bad_type" | grep -q 'dev or release' || fail "build type error was: $bad_type"

(
  # shellcheck disable=SC1091
  source "$root/src/scripts/lib/build-config.sh"
  pinned="$(CHECKOUT_ROOT="$root" build_checkout_root)"
  [ "$pinned" = "$root" ] || fail "CHECKOUT_ROOT resolved to $pinned"
  set +e
  bad_root="$(CHECKOUT_ROOT="$tmp/missing" build_checkout_root 2>&1)"
  bad_root_status=$?
  set -e
  [ "$bad_root_status" -ne 0 ] || fail "missing CHECKOUT_ROOT was accepted"
  printf '%s\n' "$bad_root" | grep -q 'CHECKOUT_ROOT is not a checkout' || fail "CHECKOUT_ROOT error was: $bad_root"
)

(
  # shellcheck disable=SC1091
  source "$root/src/scripts/lib/build-config.sh"
  build_load_versions 9
  release_tag="$(build_release_tag)"
  [ "$(BUILD_TYPE=dev CI_COMMIT_TAG='' build_effective_build_type)" = dev ] || fail "dev pipeline was treated as a release"
  [ "$(BUILD_TYPE=release CI_COMMIT_TAG='' build_effective_build_type)" = release ] || fail "BUILD_TYPE=release was ignored"
  [ "$(BUILD_TYPE=dev CI_COMMIT_TAG="$release_tag" build_effective_build_type)" = release ] || fail "release tag was left on the dev publish path"
  [ "$(BUILD_TYPE=dev CI_COMMIT_TAG='other-tag' build_effective_build_type)" = dev ] || fail "an ordinary tag was treated as a release"
  build_registry_error_means_absent 'manifest unknown: The named manifest is not known to the registry.' || fail "a missing manifest was not recognized"
  if build_registry_error_means_absent 'denied: requested access to the resource is denied'; then
    fail "a permission error was treated as a missing tag"
  fi
  curl_cfg="$tmp/curl.cfg"
  ARTIFACTORY_USERNAME=publisher ARTIFACTORY_PASSWORD='secret#with-hash' build_write_curl_config "$curl_cfg"
  expected_auth="$(printf '%s:%s' publisher 'secret#with-hash' | base64 -w 0)"
  grep -q "$expected_auth" "$curl_cfg" || fail "curl config dropped the part of the password after #"
  if grep -q 'secret#with-hash' "$curl_cfg"; then
    fail "curl config contains the password"
  fi
)

release_tag="$(
  # shellcheck disable=SC1091
  source "$root/src/scripts/lib/build-config.sh"
  build_load_versions 9
  build_release_tag
)"

set +e
preflight_out="$(CI_COMMIT_REF_PROTECTED=false CI_COMMIT_TAG="$release_tag" BUILD_TYPE=dev "$root/src/scripts/release-preflight.sh" 2>&1)"
preflight_status=$?
set -e
[ "$preflight_status" -ne 0 ] || fail "unprotected release tag passed preflight"
printf '%s\n' "$preflight_out" | grep -q 'protected Git ref' || fail "preflight said: $preflight_out"

CI_COMMIT_REF_PROTECTED=true CI_COMMIT_TAG="$release_tag" BUILD_TYPE=dev "$root/src/scripts/release-preflight.sh" >/dev/null
CI_COMMIT_REF_PROTECTED=false CI_COMMIT_TAG='' BUILD_TYPE=dev "$root/src/scripts/release-preflight.sh" >/dev/null

(
  export BUILD_ROOT="$tmp/publish-build"
  set +e
  tag_dev="$(CI_COMMIT_REF_PROTECTED=false CI_COMMIT_TAG="$release_tag" ARTIFACTORY_USERNAME=user ARTIFACTORY_PASSWORD=secret BUILD_TYPE=dev "$root/src/scripts/publish-image.sh" 2>&1)"
  tag_dev_status=$?
  set -e
  [ "$tag_dev_status" -ne 0 ] || fail "unprotected release tag published with BUILD_TYPE=dev"
  printf '%s\n' "$tag_dev" | grep -q 'protected Git ref' || fail "release tag with BUILD_TYPE=dev said: $tag_dev"
  if printf '%s\n' "$tag_dev" | grep -q 'login'; then
    fail "release tag with BUILD_TYPE=dev reached registry login: $tag_dev"
  fi

  set +e
  tag_rpm_dev="$(CI_COMMIT_REF_PROTECTED=false CI_COMMIT_TAG="$release_tag" ARTIFACTORY_USERNAME=user ARTIFACTORY_PASSWORD=secret BUILD_TYPE=dev "$root/src/scripts/publish-rpm.sh" 2>&1)"
  tag_rpm_dev_status=$?
  set -e
  [ "$tag_rpm_dev_status" -ne 0 ] || fail "unprotected release tag uploaded an RPM with BUILD_TYPE=dev"
  printf '%s\n' "$tag_rpm_dev" | grep -q 'protected Git ref' || fail "RPM release tag with BUILD_TYPE=dev said: $tag_rpm_dev"
  if printf '%s\n' "$tag_rpm_dev" | grep -q 'https://'; then
    fail "RPM release tag with BUILD_TYPE=dev reached Artifactory: $tag_rpm_dev"
  fi
)

echo "build-config tests passed"
