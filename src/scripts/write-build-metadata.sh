#!/usr/bin/env bash
# Write artifacts/build-metadata.json from the version file and the CI environment.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

build_load_versions "${1:-${RHEL_VERSION:-9}}"
build_type="${BUILD_TYPE:-dev}"
case "$build_type" in
  dev|release) ;;
  *) build_fail "BUILD_TYPE must be dev or release" ;;
esac

commit="${CI_COMMIT_SHA:-}"
if [ -z "$commit" ]; then
  commit="$(git -C "$(build_repo_root)" rev-parse HEAD 2>/dev/null || echo unknown)"
fi
short="${CI_COMMIT_SHORT_SHA:-}"
if [ -z "$short" ] || [ "$short" = unknown ]; then
  short="$(git -C "$(build_repo_root)" rev-parse --short=8 HEAD 2>/dev/null || echo unknown)"
fi
export CI_COMMIT_SHORT_SHA="$short"
repo="$(build_image_repo)"
build_image=""
rpm_repository=""
if [ "$build_type" = release ]; then
  tag="$(build_release_tag)"
  build_image="${repo}:$(build_build_image_tag)"
  rpm_repository="https://${ARTIFACTORY_REGISTRY}/artifactory/${ARTIFACTORY_RPM_REPOSITORY}"
else
  tag="$(build_dev_sha_tag)"
fi
runtime_image="${repo}:${tag}"

out="${METADATA_FILE:-$(build_repo_root)/artifacts/build-metadata.json}"
mkdir -p "$(dirname "$out")"
cat > "$out" <<EOF
{
  "wireshark_version": "${WIRESHARK_VERSION}",
  "packet_penguin_version": "${PACKET_PENGUIN_VERSION}",
  "rhel_version": "${RHEL_VERSION}",
  "rpm_package_release": "${RPM_PACKAGE_RELEASE}",
  "build_type": "${build_type}",
  "git_commit": "${commit}",
  "gitlab_pipeline_id": "${CI_PIPELINE_ID:-local}",
  "gitlab_user": "${GITLAB_USER_LOGIN:-}",
  "image_repository": "${repo}",
  "image_tag": "${tag}",
  "runtime_image": "${runtime_image}",
  "build_image": "${build_image}",
  "rpm_repository": "${rpm_repository}"
}
EOF
echo "Metadata: $out"
