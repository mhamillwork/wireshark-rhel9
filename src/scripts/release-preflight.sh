#!/usr/bin/env bash
# Stop a release-tag pipeline before the image build when the tag is not
# protected. The publish job would otherwise run the whole pipeline and
# then refuse to push.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

build_load_versions "${RHEL_VERSION:-9}"
release="$(build_release_tag)"
build_type="$(build_effective_build_type)" || exit 1
echo "BUILD_TYPE=${BUILD_TYPE:-dev} effective=${build_type} CI_COMMIT_TAG=${CI_COMMIT_TAG:-} CI_COMMIT_BRANCH=${CI_COMMIT_BRANCH:-} CI_COMMIT_REF_PROTECTED=${CI_COMMIT_REF_PROTECTED:-}"
if [ "$build_type" != release ]; then
  exit 0
fi
echo "This pipeline publishes the release image and the RPM for tag ${release}."
build_require_release_ref "$release"
