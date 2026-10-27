#!/usr/bin/env bash
# Inspect the RPM produced by build-rpm.sh. Installation in a container is
# attempted only when docker or podman and a local base image are available.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

build_load_versions "${RHEL_VERSION:-9}"
build_layout
shopt -s nullglob
rpms=("$ARTIFACT_DIR"/wireshark-ppv-*.rpm)
shopt -u nullglob
[ "${#rpms[@]}" -ge 1 ] || build_fail "no RPM in $ARTIFACT_DIR"
rpm_file="${rpms[0]}"

command -v rpm >/dev/null 2>&1 || build_fail "rpm is not installed"
mkdir -p "$LOG_DIR"
{
  echo "RPM info:"
  rpm -qpi "$rpm_file"
  echo "RPM requires:"
  rpm -qp --requires "$rpm_file"
  echo "RPM files:"
  rpm -qpl "$rpm_file"
} | tee "$LOG_DIR/package-test.txt"

rel="${RPM_PACKAGE_RELEASE}.ppv${PACKET_PENGUIN_VERSION}.el${RHEL_VERSION}"
rpm -qp --queryformat '%{NAME} %{VERSION} %{RELEASE} %{ARCH}\n' "$rpm_file" \
  | grep -q "wireshark-ppv ${WIRESHARK_VERSION} ${rel}" \
  || build_fail "RPM metadata does not match the version file"
rpm -qpl "$rpm_file" | grep -q '/usr/local/bin/tshark' || build_fail "tshark is not in the RPM"
echo "RPM metadata checks passed"

if command -v podman >/dev/null 2>&1; then
  engine=podman
elif command -v docker >/dev/null 2>&1; then
  engine=docker
else
  echo "Container installation test was not run: docker and podman are absent"
  exit 0
fi

base="${RPM_TEST_IMAGE:-artifactory.tahaa.local/tahaa-image-local/ubi9-tahaa-bootstrap:9.8}"
if ! "$engine" image inspect "$base" >/dev/null 2>&1; then
  echo "Container installation test was not run: base image $base is not loaded"
  exit 0
fi

"$engine" run --rm -v "$rpm_file:/tmp/wireshark-ppv.rpm:ro" "$base" \
  bash -lc 'dnf -y install /tmp/wireshark-ppv.rpm && /usr/local/bin/tshark -v && rpm -e wireshark-ppv'
echo "Container installation test passed"
