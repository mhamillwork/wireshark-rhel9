#!/usr/bin/env bash
# Shared version, path, and image-tag helpers.
# Source this file. Do not execute it.
if [ -z "${BASH_VERSION:-}" ]; then
  echo "build-config.sh requires bash" >&2
  exit 1
fi

build_fail() {
  echo "error: $*" >&2
  exit 1
}

# Parent of scripts/lib. Printed from a subshell so the caller keeps its cwd.
build_scripts_dir() {
  local src
  src="${BASH_SOURCE[0]}"
  (cd "$(dirname "$src")/.." && pwd)
}

build_repo_root() {
  cd "$(build_scripts_dir)/.." && pwd
}

# Directory that contains .gitlab-ci.yml. Scripts live in src/scripts, so the
# checkout root is the parent of the src directory. Compose mounts that
# checkout at /workspace.
build_checkout_root() {
  local dir
  dir="$(build_scripts_dir)"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.gitlab-ci.yml" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  if [ -f /workspace/.gitlab-ci.yml ]; then
    printf '%s\n' /workspace
    return 0
  fi
  build_repo_root
}

# Walk upward from the script directory for versions/RHEL<n>.env.
build_find_versions_file() {
  local rhel="$1"
  local name="RHEL${rhel}.env"
  local dir start
  if [ -n "${VERSIONS_FILE:-}" ]; then
    [ -f "$VERSIONS_FILE" ] || build_fail "version configuration not found: $VERSIONS_FILE"
    printf '%s\n' "$VERSIONS_FILE"
    return 0
  fi
  start="$(build_scripts_dir)"
  dir="$start"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/versions/$name" ]; then
      printf '%s\n' "$dir/versions/$name"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # Compose mounts the checkout at /workspace and only its src/ tree at /src.
  if [ -f "/workspace/versions/$name" ]; then
    printf '%s\n' "/workspace/versions/$name"
    return 0
  fi
  if [ -f "/opt/wireshark-build/versions/$name" ]; then
    printf '%s\n' "/opt/wireshark-build/versions/$name"
    return 0
  fi
  build_fail "version configuration not found: versions/$name"
}

build_version_ok() {
  case "$1" in
    [0-9]*.[0-9]*.[0-9]*)
      case "$1" in
        *[!0-9.]*) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
  # Require exactly three numeric components.
  case "$1" in
    *.*.*.*) return 1 ;;
  esac
  return 0
}

build_load_versions() {
  local rhel="${1:-}"
  local file saved_registry saved_repository saved_image
  case "$rhel" in
    8|9) ;;
    *) build_fail "unsupported RHEL version: ${rhel:-<empty>}" ;;
  esac
  # exit inside $(...) only leaves that subshell, so a missing file must be
  # checked out here or the next line sources an empty path.
  file="$(build_find_versions_file "$rhel")" || exit 1
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    build_fail "version configuration not found: versions/RHEL${rhel}.env"
  fi
  saved_registry="${ARTIFACTORY_REGISTRY-}"
  saved_repository="${ARTIFACTORY_REPOSITORY-}"
  saved_image="${IMAGE_NAME-}"
  # shellcheck disable=SC1090
  set -a
  # shellcheck disable=SC1090
  source "$file"
  set +a
  VERSIONS_FILE="$file"
  [ -n "${WIRESHARK_VERSION:-}" ] || build_fail "WIRESHARK_VERSION is unset in $file"
  [ -n "${PACKET_PENGUIN_VERSION:-}" ] || build_fail "PACKET_PENGUIN_VERSION is unset in $file"
  [ -n "${RHEL_VERSION:-}" ] || build_fail "RHEL_VERSION is unset in $file"
  [ -n "${RPM_PACKAGE_RELEASE:-}" ] || build_fail "RPM_PACKAGE_RELEASE is unset in $file"
  build_version_ok "$WIRESHARK_VERSION" || build_fail "malformed WIRESHARK_VERSION: $WIRESHARK_VERSION"
  build_version_ok "$PACKET_PENGUIN_VERSION" || build_fail "malformed PACKET_PENGUIN_VERSION: $PACKET_PENGUIN_VERSION"
  [ "$RHEL_VERSION" = "$rhel" ] || build_fail "RHEL_VERSION in $file is $RHEL_VERSION, expected $rhel"
  case "$RPM_PACKAGE_RELEASE" in
    ''|*[!0-9]*) build_fail "RPM_PACKAGE_RELEASE must be an integer: $RPM_PACKAGE_RELEASE" ;;
  esac
  if [ "${SUPPORTED:-1}" != "1" ]; then
    build_fail "RHEL $RHEL_VERSION is not supported by this repository ($file)"
  fi
  if [ -n "$saved_registry" ]; then ARTIFACTORY_REGISTRY="$saved_registry"; fi
  if [ -n "$saved_repository" ]; then ARTIFACTORY_REPOSITORY="$saved_repository"; fi
  if [ -n "$saved_image" ]; then IMAGE_NAME="$saved_image"; fi
  ARTIFACTORY_REGISTRY="${ARTIFACTORY_REGISTRY:-artifactory.tahaa.local}"
  ARTIFACTORY_REPOSITORY="${ARTIFACTORY_REPOSITORY:-tahaa-image-local}"
  IMAGE_NAME="${IMAGE_NAME:-wireshark}"
  export WIRESHARK_VERSION PACKET_PENGUIN_VERSION RHEL_VERSION RPM_PACKAGE_RELEASE
  export ARTIFACTORY_REGISTRY ARTIFACTORY_REPOSITORY IMAGE_NAME VERSIONS_FILE
}

build_tree_version() {
  local file="$1/CMakeLists.txt"
  local major minor patch
  [ -f "$file" ] || return 1
  major="$(sed -n 's/^[[:space:]]*set(PROJECT_MAJOR_VERSION[[:space:]]\{1,\}\([0-9][0-9]*\).*/\1/p' "$file" | head -1)"
  minor="$(sed -n 's/^[[:space:]]*set(PROJECT_MINOR_VERSION[[:space:]]\{1,\}\([0-9][0-9]*\).*/\1/p' "$file" | head -1)"
  patch="$(sed -n 's/^[[:space:]]*set(PROJECT_PATCH_VERSION[[:space:]]\{1,\}\([0-9][0-9]*\).*/\1/p' "$file" | head -1)"
  [ -n "$major" ] && [ -n "$minor" ] && [ -n "$patch" ] || return 1
  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

build_resolve_source_dir() {
  local repo_root ver candidate version
  repo_root="$(build_repo_root)"
  ver="${WIRESHARK_VERSION:?}"
  SRC_DIR=""
  for candidate in \
    "$repo_root/src/wireshark-$ver" \
    "$repo_root/wireshark-$ver" \
    "/src/wireshark-$ver"
  do
    if [ -f "$candidate/CMakeLists.txt" ]; then
      SRC_DIR="$(cd "$candidate" && pwd)"
      break
    fi
  done
  if [ -z "$SRC_DIR" ]; then
    for candidate in "$repo_root/src/wireshark" "$repo_root/wireshark" "/src/wireshark"; do
      if [ -f "$candidate/CMakeLists.txt" ]; then
        version="$(build_tree_version "$candidate" || true)"
        if [ "$version" = "$ver" ]; then
          SRC_DIR="$(cd "$candidate" && pwd)"
          break
        fi
      fi
    done
  fi
  [ -n "$SRC_DIR" ] || build_fail "Wireshark source directory not found for version $ver"
  [ -f "$SRC_DIR/CMakeLists.txt" ] || build_fail "Wireshark sources not found at $SRC_DIR"
  export SRC_DIR
}

build_resolve_plugin_dir() {
  local repo_root candidate
  repo_root="$(build_repo_root)"
  PLUGIN_DIR=""
  for candidate in "$repo_root/src/plugins" "$repo_root/plugins" "/src/plugins"; do
    if [ -d "$candidate" ]; then
      PLUGIN_DIR="$(cd "$candidate" && pwd)"
      break
    fi
  done
  export PLUGIN_DIR
}

build_require_plugins() {
  local found=0 plugin
  build_resolve_plugin_dir
  [ -n "${PLUGIN_DIR:-}" ] || build_fail "Packet Penguin plugin directory is missing (expected src/plugins or plugins)"
  shopt -s nullglob
  for plugin in "$PLUGIN_DIR"/* "$PLUGIN_DIR"/*/*; do
    [ -f "$plugin/CMakeLists.txt" ] || continue
    found=1
    break
  done
  shopt -u nullglob
  [ "$found" -eq 1 ] || build_fail "no CMakeLists.txt plugins under $PLUGIN_DIR"
}

build_print_versions() {
  echo "Wireshark version: $WIRESHARK_VERSION"
  echo "Packet Penguin version: $PACKET_PENGUIN_VERSION"
  echo "RHEL version: $RHEL_VERSION"
  echo "RPM package release: $RPM_PACKAGE_RELEASE"
  echo "Version file: $VERSIONS_FILE"
  if [ -n "${SRC_DIR:-}" ]; then
    echo "Wireshark sources: $SRC_DIR"
  fi
  if [ -n "${PLUGIN_DIR:-}" ]; then
    echo "Dissector plugins: $PLUGIN_DIR"
  else
    echo "Dissector plugins: none"
  fi
}

build_layout() {
  local repo_root
  repo_root="$(build_repo_root)"
  BUILD_ROOT="${BUILD_ROOT:-$repo_root/build/rhel${RHEL_VERSION}}"
  BUILD_DIR="${BUILD_DIR:-$BUILD_ROOT/wireshark}"
  STAGING_DIR="${STAGING_DIR:-$BUILD_ROOT/staging}"
  LOG_DIR="${LOG_DIR:-$BUILD_ROOT/logs}"
  ARTIFACT_DIR="${ARTIFACT_DIR:-$repo_root/artifacts/rpms/rhel${RHEL_VERSION}}"
  export BUILD_ROOT BUILD_DIR STAGING_DIR LOG_DIR ARTIFACT_DIR
}

build_sanitize_tag() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_.-' '-')"
  value="${value#-}"
  value="${value%.}"
  [ -n "$value" ] || build_fail "Docker tag component is empty"
  printf '%s\n' "$value"
}

build_release_tag() {
  build_sanitize_tag "${WIRESHARK_VERSION}-ppv${PACKET_PENGUIN_VERSION}-rhel${RHEL_VERSION}"
}

build_dev_tag() {
  local user
  user="${GITLAB_USER_LOGIN:-${GITLAB_USER:-${USER:-local}}}"
  build_sanitize_tag "$(build_release_tag)-dev-${user}"
}

build_dev_sha_tag() {
  local sha
  sha="${CI_COMMIT_SHORT_SHA:-}"
  if [ -z "$sha" ]; then
    sha="$(git -C "$(build_repo_root)" rev-parse --short=8 HEAD 2>/dev/null || true)"
  fi
  [ -n "$sha" ] || build_fail "git commit SHA is unavailable for the development image tag"
  build_sanitize_tag "$(build_dev_tag)-${sha}"
}

build_image_repo() {
  printf '%s/%s/%s\n' "$ARTIFACTORY_REGISTRY" "$ARTIFACTORY_REPOSITORY" "$IMAGE_NAME"
}
