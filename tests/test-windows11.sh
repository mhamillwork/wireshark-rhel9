#!/usr/bin/env bash
# Windows 11 file checks. These do not compile Wireshark or start Docker.
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

# shellcheck disable=SC1091
source "$root/versions/WINDOWS11.env"
expected="wireshark-${WIRESHARK_VERSION}-${INSTALLER_RELEASE}.ppv${PACKET_PENGUIN_VERSION}.win11.x64.exe"

out="$("$root/src/scripts/check-windows11.sh")"
printf '%s\n' "$out" | grep -q 'Windows version: 11' || fail "check did not print Windows 11: $out"
printf '%s\n' "$out" | grep -q "Qt version: ${QT_VERSION}" || fail "check did not print the Qt version: $out"
printf '%s\n' "$out" | grep -q "Installer: src/artifacts/installers/windows11/${expected}" || fail "installer name was: $out"
grep -q "$expected" "$root/docs/WINDOWS11-BUILD.md" || fail "Windows build document does not name ${expected}"

build_df="$root/dockerfile/Dockerfile.wireshark-win11-build"
runtime_df="$root/dockerfile/Dockerfile.wireshark-win11-runtime"
grep -q 'mcr.microsoft.com/windows/servercore:ltsc2025' "$build_df" || fail "compile image base changed"
grep -q 'mcr.microsoft.com/windows:ltsc2025' "$runtime_df" || fail "runtime image base changed"
grep -q 'src/build' "$build_df" || fail "compile Dockerfile does not document the src/build exclusion"
grep -q 'install-windows-build-tools.ps1' "$build_df" || fail "compile Dockerfile does not install the build tools"
grep -q 'install-windows-runtime.ps1' "$runtime_df" || fail "runtime Dockerfile does not install the NSIS executable"
grep -qF 'C:\\Wireshark\\Wireshark.exe' "$runtime_df" || fail "runtime command is not Wireshark.exe"

compose="$root/docker-compose.windows11.yml"
grep -q 'Documents/Sandbox/wireshark-packet-penguin:C:/workspace:ro' "$compose" || fail "Compose does not mount the checkout read-only"
grep -q 'Documents/Sandbox/wireshark-packet-penguin/src:C:/src' "$compose" || fail "Compose does not mount src"
grep -q 'Documents/Sandbox}:C:/sandbox' "$compose" || fail "Compose does not mount the Documents Sandbox"
grep -qF 'profiles: ["runtime"]' "$compose" || fail "runtime service is not behind the runtime profile"

grep -q 'wireshark_nsis' "$root/src/scripts/build-windows-installer.ps1" || fail "installer script does not build the NSIS target"
grep -q 'Windows11SDK.26100' "$root/src/scripts/install-windows-build-tools.ps1" || fail "build tools do not install the Windows 11 SDK"
grep -qF '/S /D=C:\Wireshark' "$root/src/scripts/install-windows-runtime.ps1" || fail "runtime install is not silent"

if grep -q 'Dockerfile.wireshark-win11' "$root/.gitlab-ci.yml"; then
  fail "GitLab CI references a Windows 11 Dockerfile"
fi
grep -q 'docs/WINDOWS11-BUILD.md' "$root/README.md" || fail "README does not point at the Windows 11 build document"
grep -qF 'Documents\Sandbox' "$root/docs/WINDOWS11-BUILD.md" || fail "Windows build document does not name the Documents Sandbox"

echo "windows 11 build files passed"
