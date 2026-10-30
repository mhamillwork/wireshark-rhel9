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
build_type="$(build_effective_build_type)" || exit 1
release="$(build_release_tag)"
if [ "$build_type" = release ]; then
  build_require_release_ref "$release"
fi

[ -n "${ARTIFACTORY_USERNAME:-}" ] || build_fail "ARTIFACTORY_USERNAME is unset"
[ -n "${ARTIFACTORY_PASSWORD:-}" ] || build_fail "ARTIFACTORY_PASSWORD is unset"

command -v docker >/dev/null 2>&1 || build_fail "docker is required to publish"
engine=docker

repo="$(build_image_repo)"

# Registry HTTP status for a Docker manifest. 404 means the tag is absent.
# docker manifest inspect sometimes prints an error that does not say so.
release_manifest_http_code() {
  local dest="$1" host path name tag url cfg code
  host="${dest%%/*}"
  path="${dest#*/}"
  tag="${path##*:}"
  name="${path%:*}"
  url="https://${host}/v2/${name}/manifests/${tag}"
  command -v curl >/dev/null 2>&1 || { printf '%s\n' 000; return 0; }
  cfg="$(mktemp)"
  chmod 600 "$cfg"
  build_write_curl_config "$cfg"
  code="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --config "$cfg" \
    --header 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
    --head "$url" || true)"
  rm -f "$cfg"
  printf '%s\n' "${code:-000}"
}

publish_ref() {
  local source_image="$1"
  local dest="$2"
  local protect="$3"
  local inspect_text http_code
  if [ "$protect" = 1 ]; then
    if "$engine" manifest inspect "$dest" >"$BUILD_ROOT/manifest-inspect.txt" 2>&1; then
      build_fail "release tag already exists and will not be overwritten: $dest"
    fi
    inspect_text="$(cat "$BUILD_ROOT/manifest-inspect.txt")"
    if ! build_registry_error_means_absent "$inspect_text"; then
      http_code="$(release_manifest_http_code "$dest")"
      case "$http_code" in
        404) ;;
        200) build_fail "release tag already exists and will not be overwritten: $dest" ;;
        *)
          echo "error: could not confirm that the release tag is absent: $dest" >&2
          echo "docker manifest inspect said:" >&2
          printf '%s\n' "$inspect_text" >&2
          echo "registry HTTP status: ${http_code}" >&2
          exit 1
          ;;
      esac
    fi
  fi
  if ! "$engine" image inspect "$source_image" >/dev/null 2>&1; then
    build_fail "local image is not loaded: $source_image"
  fi
  "$engine" tag "$source_image" "$dest"
  "$engine" push "$dest"
  echo "Pushed $dest"
}

printf '%s' "$ARTIFACTORY_PASSWORD" | "$engine" login --password-stdin -u "$ARTIFACTORY_USERNAME" "$ARTIFACTORY_REGISTRY"

local_image="${LOCAL_IMAGE:-wireshark-ppv:candidate}"
if [ "$build_type" = release ]; then
  # Runtime image, then the compile image. Neither tag carries -dev.
  publish_ref "$local_image" "$repo:$release" 1
  publish_ref "${WIRESHARK_IMAGE:-wireshark-ubi9:dev}" "$repo:$(build_build_image_tag)" 1
else
  # Development tags cannot collide with the release runtime or -build tags.
  publish_ref "$local_image" "$repo:$(build_dev_tag)" 0
  publish_ref "$local_image" "$repo:$(build_dev_sha_tag)" 0
fi
