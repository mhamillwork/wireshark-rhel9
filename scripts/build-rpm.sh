#!/usr/bin/env bash
# Package the staged /usr/local tree as wireshark-ppv.
# The package installs under /usr/local and does not replace the RHEL wireshark RPM.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

trap 'echo "error: ${BASH_SOURCE[0]}:${LINENO}: command failed" >&2' ERR

if [ -z "${WIRESHARK_VERSION:-}" ]; then
  build_load_versions "${1:-9}"
fi
build_layout

command -v rpmbuild >/dev/null 2>&1 || build_fail "rpmbuild is not installed"

[ -d "$STAGING_DIR/usr/local" ] || build_fail "staging tree is missing: $STAGING_DIR/usr/local"
[ -e "$STAGING_DIR/usr/local/bin/tshark" ] || build_fail "staged tshark is missing"

arch="$(uname -m)"
release="${RPM_PACKAGE_RELEASE}.ppv${PACKET_PENGUIN_VERSION}.el${RHEL_VERSION}"
topdir="$BUILD_ROOT/rpmbuild"
root="$(build_repo_root)"
spec_in=""
for candidate in \
  "$root/src/rpmbuild/RHEL-${RHEL_VERSION}/SPECS/wireshark-ppv.spec.in" \
  "$root/rpmbuild/RHEL-${RHEL_VERSION}/SPECS/wireshark-ppv.spec.in"
do
  if [ -f "$candidate" ]; then
    spec_in="$candidate"
    break
  fi
done
[ -n "$spec_in" ] || build_fail "RPM spec template not found for RHEL $RHEL_VERSION"

rm -rf "$topdir"
mkdir -p "$topdir/BUILD" "$topdir/BUILDROOT" "$topdir/RPMS" "$topdir/SOURCES" "$topdir/SPECS" "$topdir/SRPMS" "$LOG_DIR"

filelist="$topdir/BUILD/filelist"
: > "$filelist"
while IFS= read -r path; do
  printf '/%s\n' "$path" >> "$filelist"
done < <(cd "$STAGING_DIR" && find usr/local \( -type f -o -type l \) | sort)

spec="$topdir/SPECS/wireshark-ppv.spec"
sed \
  -e "s|@WIRESHARK_VERSION@|$WIRESHARK_VERSION|g" \
  -e "s|@PACKET_PENGUIN_VERSION@|$PACKET_PENGUIN_VERSION|g" \
  -e "s|@RHEL_VERSION@|$RHEL_VERSION|g" \
  -e "s|@RELEASE@|$release|g" \
  -e "s|@ARCH@|$arch|g" \
  -e "s|@STAGING@|$STAGING_DIR|g" \
  -e "s|@FILELIST@|$filelist|g" \
  "$spec_in" > "$spec"

rpmbuild -bb \
  --define "_topdir $topdir" \
  --define "_tmppath $topdir/tmp" \
  "$spec" | tee "$LOG_DIR/rpmbuild.log"

mkdir -p "$ARTIFACT_DIR"
find "$topdir/RPMS" -type f -name '*.rpm' -exec cp -f {} "$ARTIFACT_DIR/" \;
rpm_file="$(find "$ARTIFACT_DIR" -type f -name "wireshark-ppv-${WIRESHARK_VERSION}-${release}.${arch}.rpm" | head -1)"
[ -n "$rpm_file" ] || build_fail "expected RPM was not produced"
echo "RPM: $rpm_file"

meta="$BUILD_ROOT/rpm-query.txt"
{
  echo "file=$rpm_file"
  rpm -qp --queryformat 'name=%{NAME}\nversion=%{VERSION}\nrelease=%{RELEASE}\narch=%{ARCH}\n' "$rpm_file"
  echo "requires:"
  rpm -qp --requires "$rpm_file"
  echo "files:"
  rpm -qpl "$rpm_file"
} | tee "$meta" "$LOG_DIR/rpm-query.txt"

name="$(rpm -qp --queryformat '%{NAME}' "$rpm_file")"
ver="$(rpm -qp --queryformat '%{VERSION}' "$rpm_file")"
rel="$(rpm -qp --queryformat '%{RELEASE}' "$rpm_file")"
got_arch="$(rpm -qp --queryformat '%{ARCH}' "$rpm_file")"
[ "$name" = "wireshark-ppv" ] || build_fail "RPM name is $name"
[ "$ver" = "$WIRESHARK_VERSION" ] || build_fail "RPM version is $ver"
[ "$rel" = "$release" ] || build_fail "RPM release is $rel"
[ "$got_arch" = "$arch" ] || build_fail "RPM arch is $got_arch"
rpm -qpl "$rpm_file" | grep -q '/usr/local/bin/tshark' || build_fail "RPM file list has no tshark"
if [ "${REQUIRE_PLUGINS:-0}" -eq 1 ]; then
  # Out-of-tree plugins are separate .so files. Dissectors compiled into
  # libwireshark do not have their own file; the library is the check then.
  if ! rpm -qpl "$rpm_file" | grep -E -q 'plugins/.*\.so|libwireshark\.so'; then
    build_fail "RPM file list has neither a plugin nor libwireshark"
  fi
fi

if command -v rpmlint >/dev/null 2>&1; then
  lint_args=()
  if [ -f "$root/src/rpmbuild/rpmlintrc" ]; then
    lint_args=(-r "$root/src/rpmbuild/rpmlintrc")
  fi
  rpmlint "${lint_args[@]}" "$spec" "$rpm_file" | tee "$LOG_DIR/rpmlint.txt" || build_fail "rpmlint reported an error"
else
  echo "rpmlint is not installed; metadata and file-list checks ran" | tee "$LOG_DIR/rpmlint.txt"
fi

echo "RPM checks passed: $(basename "$rpm_file")"
