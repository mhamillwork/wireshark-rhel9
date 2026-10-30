#!/usr/bin/env bash
# Upload the RPM to the Artifactory RPM repository. Release pipelines only.
# The password is sent as an Authorization header and is not printed.
# Curl netrc treats "#" as a comment, which would truncate the password.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

build_load_versions "${RHEL_VERSION:-9}"
build_layout
mkdir -p "$BUILD_ROOT"

build_type="$(build_effective_build_type)" || exit 1
[ "$build_type" = release ] || build_fail "RPM publish runs only for BUILD_TYPE=release"

release="$(build_release_tag)"
build_require_release_ref "$release"

[ -n "${ARTIFACTORY_USERNAME:-}" ] || build_fail "ARTIFACTORY_USERNAME is unset"
[ -n "${ARTIFACTORY_PASSWORD:-}" ] || build_fail "ARTIFACTORY_PASSWORD is unset"
command -v curl >/dev/null 2>&1 || build_fail "curl is required to publish the RPM"

mapfile -t rpms < <(find "$ARTIFACT_DIR" -maxdepth 1 -type f \
  -name "wireshark-${WIRESHARK_VERSION}-${RPM_PACKAGE_RELEASE}.ppv${PACKET_PENGUIN_VERSION}.el${RHEL_VERSION}.*.rpm" | sort)
[ "${#rpms[@]}" -eq 1 ] || build_fail "expected one RPM in $ARTIFACT_DIR, found ${#rpms[@]}"
rpm_file="${rpms[0]}"
rpm_name="$(basename "$rpm_file")"

url="https://${ARTIFACTORY_REGISTRY}/artifactory/${ARTIFACTORY_RPM_REPOSITORY}/${rpm_name}"
curl_config="$(mktemp)"
chmod 600 "$curl_config"
cleanup() { rm -f "$curl_config"; }
trap cleanup EXIT
build_write_curl_config "$curl_config"

http_code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --config "$curl_config" --head "$url")" \
  || build_fail "could not check whether the RPM is already published"
case "$http_code" in
  200) build_fail "RPM already exists and will not be overwritten: $url" ;;
  404) ;;
  *) build_fail "could not confirm that the RPM is absent (HTTP $http_code)" ;;
esac

curl --fail --silent --show-error --config "$curl_config" --upload-file "$rpm_file" "$url"
echo "Pushed RPM $url"
