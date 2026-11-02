#!/usr/bin/env bash
# Check versions/WINDOWS11.env and the Windows 11 build files.
# This does not compile Wireshark and does not need a Windows host.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

root="$(build_checkout_root)"
# shellcheck disable=SC1091
source "$root/versions/WINDOWS11.env"

[ -n "${WIRESHARK_VERSION:-}" ] || build_fail "WIRESHARK_VERSION is unset in versions/WINDOWS11.env"
[ -n "${PACKET_PENGUIN_VERSION:-}" ] || build_fail "PACKET_PENGUIN_VERSION is unset in versions/WINDOWS11.env"
[ -n "${WINDOWS_VERSION:-}" ] || build_fail "WINDOWS_VERSION is unset in versions/WINDOWS11.env"
[ -n "${INSTALLER_RELEASE:-}" ] || build_fail "INSTALLER_RELEASE is unset in versions/WINDOWS11.env"
[ -n "${QT_VERSION:-}" ] || build_fail "QT_VERSION is unset in versions/WINDOWS11.env"
[ "${WINDOWS_VERSION}" = 11 ] || build_fail "WINDOWS_VERSION is ${WINDOWS_VERSION}, expected 11"
[ "${SUPPORTED:-1}" = 1 ] || build_fail "Windows ${WINDOWS_VERSION} is not supported by versions/WINDOWS11.env"
build_version_ok "$WIRESHARK_VERSION" || build_fail "malformed WIRESHARK_VERSION: $WIRESHARK_VERSION"
build_version_ok "$PACKET_PENGUIN_VERSION" || build_fail "malformed PACKET_PENGUIN_VERSION: $PACKET_PENGUIN_VERSION"
case "$INSTALLER_RELEASE" in
  ''|*[!0-9]*) build_fail "INSTALLER_RELEASE must be an integer: $INSTALLER_RELEASE" ;;
esac
case "$QT_VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) build_fail "malformed QT_VERSION: $QT_VERSION" ;;
esac
[ -f "$root/src/wireshark-${WIRESHARK_VERSION}/CMakeLists.txt" ] || build_fail "Wireshark source directory not found for version $WIRESHARK_VERSION"

installer="wireshark-${WIRESHARK_VERSION}-${INSTALLER_RELEASE}.ppv${PACKET_PENGUIN_VERSION}.win11.x64.exe"
echo "Wireshark version: $WIRESHARK_VERSION"
echo "Packet Penguin version: $PACKET_PENGUIN_VERSION"
echo "Windows version: $WINDOWS_VERSION"
echo "Installer release: $INSTALLER_RELEASE"
echo "Qt version: $QT_VERSION"
echo "Version file: $root/versions/WINDOWS11.env"
echo "Installer: src/artifacts/installers/windows11/$installer"
