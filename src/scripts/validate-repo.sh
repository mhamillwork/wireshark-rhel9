#!/usr/bin/env bash
# Static checks for the RHEL 9 build. This does not compile Wireshark.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/build-config.sh
source "$SCRIPT_DIR/lib/build-config.sh"

root="$(build_checkout_root)"
cd "$root"

build_type="${BUILD_TYPE:-dev}"
case "$build_type" in
  dev|release) ;;
  *) build_fail "BUILD_TYPE must be dev or release" ;;
esac

fail=0
while IFS= read -r script; do
  bash -n "$script" || fail=1
done < <(find src/scripts -name '*.sh' -type f | sort)
[ "$fail" -eq 0 ] || build_fail "shell syntax check failed"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -x -P SCRIPTDIR src/scripts/*.sh src/scripts/lib/*.sh tests/*.sh || build_fail "shellcheck failed"
else
  echo "shellcheck is not installed; syntax checks ran"
fi

"$SCRIPT_DIR/compile-wireshark.sh" --rhel 9 --check
# The version comes from versions/RHEL9.env. This file does not spell the path.
# shellcheck disable=SC1091
source "$root/versions/RHEL9.env"
hardcoded_path="wireshark-${WIRESHARK_VERSION}"
if grep -RIn --exclude-dir=.git -e "$hardcoded_path" src/scripts .gitlab-ci.yml dockerfile versions >/dev/null 2>&1; then
  echo "error: a build script still hardcodes ${hardcoded_path}" >&2
  grep -RIn --exclude-dir=.git -e "$hardcoded_path" src/scripts .gitlab-ci.yml dockerfile versions >&2 || true
  exit 1
fi

grep -q 'BUILD_TYPE' .gitlab-ci.yml || build_fail ".gitlab-ci.yml has no BUILD_TYPE"
if grep -q 'pull_policy:' .gitlab-ci.yml; then
  build_fail "GitLab CI sets pull_policy, which this runner's empty allowed_pull_policies list rejects"
fi
grep -q 'value: "dev"' .gitlab-ci.yml || build_fail "GitLab BUILD_TYPE default is not dev"
grep -q 'CI_COMMIT_REF_PROTECTED' .gitlab-ci.yml || build_fail "GitLab release publish is not limited to a protected ref"
grep -q 'CI_COMMIT_TAG' .gitlab-ci.yml || build_fail "GitLab release publish is not limited to the release Git tag"
grep -q 'tahaa-rpm-local' versions/RHEL9.env || build_fail "versions file is missing the RPM repository"
grep -q 'publish-rpm.sh' .gitlab-ci.yml || build_fail "GitLab publish job does not upload the RPM"
grep -q '^Name:[[:space:]]*wireshark$' src/rpmbuild/RHEL-9/SPECS/wireshark.spec.in || build_fail "RPM spec template is missing the package name"
grep -q 'cap_net_raw,cap_net_admin=ep' src/scripts/build-rpm.sh || build_fail "RPM file list does not grant dumpcap capture capabilities"
grep -qxF 'src/build' .dockerignore || build_fail "compile image dockerignore does not exclude src/build"
if grep -qxF 'src/artifacts' .dockerignore; then
  build_fail "dockerignore excludes src/artifacts, which the runtime image copies"
fi
grep -qxF 'src/wireshark-*/build' .dockerignore || build_fail "compile image dockerignore does not exclude the in-tree Wireshark build"
grep -q 'src/build' dockerfile/Dockerfile.wireshark-ubi9-build || build_fail "compile Dockerfile does not document the src/build exclusion"
grep -q 'artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap:9.8' dockerfile/Dockerfile.wireshark-ubi9-build || build_fail "compile Dockerfile bootstrap image changed"
grep -q 'artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap:9.8' dockerfile/Dockerfile.wireshark-ubi9-runtime || build_fail "runtime Dockerfile bootstrap image changed"
grep -q 'artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap-docker:9.8' .gitlab-ci.yml || build_fail "GitLab job image is not the bootstrap image with the docker client"
grep -q 'artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap:9.8' dockerfile/Dockerfile.ubi9-tahaa-bootstrap-docker || build_fail "job image Dockerfile does not start from the bootstrap image"
grep -q 'docker-ce-cli' dockerfile/Dockerfile.ubi9-tahaa-bootstrap-docker || build_fail "job image Dockerfile does not install the Docker client"
if grep -q 'install docker;' dockerfile/Dockerfile.ubi9-tahaa-bootstrap-docker || grep -q 'install docker ' dockerfile/Dockerfile.ubi9-tahaa-bootstrap-docker; then
  build_fail "job image Dockerfile installs the distro docker package"
fi
grep -q 'qt5-qtbase-gui' dockerfile/Dockerfile.wireshark-ubi9-runtime || build_fail "runtime image is missing the Qt xcb platform package"
grep -q 'QT_X11_NO_MITSHM=1' dockerfile/Dockerfile.wireshark-ubi9-runtime || build_fail "runtime image is missing QT_X11_NO_MITSHM"
grep -q '/usr/local/bin/wireshark' dockerfile/Dockerfile.wireshark-ubi9-runtime || build_fail "runtime image command is not the Wireshark GUI"
grep -q 'Dockerfile.wireshark-ubi9-build' .gitlab-ci.yml || build_fail "GitLab does not build the compile Dockerfile"
grep -q 'run-compile-image.sh' .gitlab-ci.yml || build_fail "GitLab compile jobs do not run inside the compile image"
grep -q 'Dockerfile.wireshark-ubi9-runtime' .gitlab-ci.yml || build_fail "GitLab docker job does not build the runtime Dockerfile"
grep -q -- '--add-host satellite9b.hsv.local:10.10.106.59' README.md || build_fail "README compile build is missing the Satellite host"
grep -q 'Dockerfile.wireshark-ubi9-runtime' README.md || build_fail "README is missing the runtime image build"
grep -q -- '--package' README.md || build_fail "README is missing the manual package command"
if grep -RIn --exclude-dir=.git --exclude=validate-repo.sh -i -e podman README.md docs .gitlab-ci.yml dockerfile src/scripts >/dev/null; then
  echo "error: container instructions still mention podman" >&2
  grep -RIn --exclude-dir=.git --exclude=validate-repo.sh -i -e podman README.md docs .gitlab-ci.yml dockerfile src/scripts >&2 || true
  exit 1
fi
grep -q -- '--add-host satellite9b.hsv.local:10.10.106.59' .gitlab-ci.yml || build_fail "GitLab runtime build is missing the Satellite host"
grep -q 'QT_QPA_PLATFORM=offscreen' .gitlab-ci.yml || build_fail "GitLab docker job would start the GUI with no display"
if grep -q 'AS runtime' dockerfile/Dockerfile.wireshark-ubi9-build; then
  build_fail "compile Dockerfile still contains the runtime stage"
fi

"$root/tests/test-build-config.sh"
"$root/tests/test-intree-plugins.sh"
if command -v rpmbuild >/dev/null 2>&1; then
  "$root/tests/test-rpm-metadata.sh"
else
  echo "rpmbuild is not installed; RPM metadata test skipped"
fi
echo "Repository validation passed"
