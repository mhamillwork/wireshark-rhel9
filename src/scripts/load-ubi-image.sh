#!/usr/bin/env bash
# Load the vendored public UBI 9.8 archive. The Wireshark Dockerfile bases
# both stages on artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap:9.8
# and does not use this archive.
#
# The archive is a docker save of registry.access.redhat.com/ubi9/ubi:9.8.
# Docker loads it so a following "docker build" sees this image.
#
#   ./src/scripts/load-ubi-image.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"
ROOT="$(build_checkout_root)"
ARCHIVE="$ROOT/images/ubi9-ubi-9.8.tar.gz"
TAG="registry.access.redhat.com/ubi9/ubi:9.8"
EXPECTED_ARCHIVE_SHA256="40eff05d9d8824c8f01ca429859f77ebd1017e98ad8538fa9432a3fc2230e571"
EXPECTED_IMAGE_ID="sha256:16e9e43d99e181463513cc84a514859b1abb9460f1c4d9e208da4b4e51cd5cc3"

if [ ! -f "$ARCHIVE" ]; then
  echo "Missing $ARCHIVE" >&2
  exit 1
fi

actual="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
if [ "$actual" != "$EXPECTED_ARCHIVE_SHA256" ]; then
  echo "Archive checksum does not match UBI 9.8." >&2
  echo "  expected $EXPECTED_ARCHIVE_SHA256" >&2
  echo "  actual   $actual" >&2
  exit 1
fi

if docker info >/dev/null 2>&1; then
  container_cmd() { docker "$@"; }
else
  container_cmd() { sudo docker "$@"; }
fi

container_cmd load -i "$ARCHIVE"

image_id="$(container_cmd image inspect "$TAG" --format '{{.Id}}')"
if [ "$image_id" != "$EXPECTED_IMAGE_ID" ]; then
  echo "Loaded $TAG is $image_id, expected $EXPECTED_IMAGE_ID" >&2
  exit 1
fi

echo "Loaded $TAG ($image_id)"
