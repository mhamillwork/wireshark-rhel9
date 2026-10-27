#!/usr/bin/env bash
# Build an RPM from a stand-in /usr/local tree and check its filename and
# metadata. This does not compile Wireshark or Packet Penguin.
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
command -v rpmbuild >/dev/null 2>&1 || {
  echo "rpmbuild is not installed" >&2
  exit 1
}
command -v gcc >/dev/null 2>&1 || {
  echo "gcc is not installed" >&2
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

stage="$tmp/staging"
plugin_dir="$stage/usr/local/lib64/wireshark/plugins/4.6/epan"
mkdir -p "$stage/usr/local/bin" "$plugin_dir"
echo 'int main(void){return 0;}' | gcc -x c -o "$stage/usr/local/bin/tshark" -
echo 'void plugin_register(void){}' | gcc -shared -fPIC -x c -o "$plugin_dir/packet-penguin.so" -

export BUILD_ROOT="$tmp/build"
export STAGING_DIR="$stage"
export ARTIFACT_DIR="$tmp/rpms"
export LOG_DIR="$tmp/logs"
export REQUIRE_PLUGINS=1

"$root/scripts/build-rpm.sh"

mapfile -t rpms < <(find "$ARTIFACT_DIR" -type f -name 'wireshark-ppv-4.6.9-1.ppv1.0.5.el9.*.rpm' | sort)
[ "${#rpms[@]}" -eq 1 ] || {
  echo "expected one wireshark-ppv RPM, found ${#rpms[@]}" >&2
  find "$ARTIFACT_DIR" -type f -print >&2 || true
  exit 1
}

"$root/scripts/test-rpm.sh"
echo "RPM metadata test passed: $(basename "${rpms[0]}")"
