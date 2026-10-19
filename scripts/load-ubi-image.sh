#!/usr/bin/env bash
# Load the vendored UBI 9.8 base image used by the Dockerfile.
#
# The archive is docker save of registry.access.redhat.com/ubi9/ubi:9.8.
# After this script, docker build resolves that FROM line locally.
#
#   ./scripts/load-ubi-image.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
  docker_cmd() { docker "$@"; }
else
  docker_cmd() { sudo docker "$@"; }
fi

docker_cmd load -i "$ARCHIVE"

image_id="$(docker_cmd image inspect "$TAG" --format '{{.Id}}')"
if [ "$image_id" != "$EXPECTED_IMAGE_ID" ]; then
  echo "Loaded $TAG is $image_id, expected $EXPECTED_IMAGE_ID" >&2
  exit 1
fi

echo "Loaded $TAG ($image_id)"
