#!/usr/bin/env bash
# Push the RHEL 9 image to Artifactory. Passwords are read from the environment
# and sent on stdin. They are not printed.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

build_load_versions "${RHEL_VERSION:-9}"
build_layout
mkdir -p "$BUILD_ROOT"
build_type="${BUILD_TYPE:-dev}"
case "$build_type" in
  dev|release) ;;
  *) build_fail "BUILD_TYPE must be dev or release" ;;
esac

[ -n "${ARTIFACTORY_USERNAME:-}" ] || build_fail "ARTIFACTORY_USERNAME is unset"
[ -n "${ARTIFACTORY_PASSWORD:-}" ] || build_fail "ARTIFACTORY_PASSWORD is unset"

command -v docker >/dev/null 2>&1 || build_fail "docker is required to publish"
engine=docker

repo="$(build_image_repo)"
release="$(build_release_tag)"
if [ "$build_type" = release ]; then
  [ "${CI_COMMIT_REF_PROTECTED:-}" = "true" ] || build_fail "release publish requires a protected Git ref"
  [ "${CI_COMMIT_TAG:-}" = "$release" ] || build_fail "release publish requires git tag $release"
  tags=("$release")
else
  tags=("$(build_dev_tag)" "$(build_dev_sha_tag)")
fi

printf '%s' "$ARTIFACTORY_PASSWORD" | "$engine" login --password-stdin -u "$ARTIFACTORY_USERNAME" "$ARTIFACTORY_REGISTRY"

local_image="${LOCAL_IMAGE:-wireshark-ppv:candidate}"
for tag in "${tags[@]}"; do
  dest="$repo:$tag"
  if [ "$build_type" = release ]; then
    if "$engine" manifest inspect "$dest" >"$BUILD_ROOT/manifest-inspect.txt" 2>&1; then
      build_fail "release tag already exists and will not be overwritten: $dest"
    fi
    if ! grep -Eiq 'manifest unknown|not found|404|no such manifest' "$BUILD_ROOT/manifest-inspect.txt"; then
      echo "error: could not confirm that the release tag is absent" >&2
      exit 1
    fi
  fi
  "$engine" tag "$local_image" "$dest"
  "$engine" push "$dest"
  echo "Pushed $dest"
done
