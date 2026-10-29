#!/usr/bin/env bash
# The job Dockerfile FROMs the plain bootstrap image. GitLab sets
# BOOTSTRAP_IMAGE to the docker tag, and that must not change the check.
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

job_df="$root/dockerfile/Dockerfile.ubi9-tahaa-bootstrap-docker"
job_base='artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap:9.8'
# shellcheck disable=SC2016
job_from='FROM ${BOOTSTRAP_IMAGE}'
docker_tag='artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap-docker:9.8'

[ -f "$job_df" ] || fail "job Dockerfile is missing"
BOOTSTRAP_IMAGE="$docker_tag" grep -q "$job_base" "$job_df" || fail "job Dockerfile lost the bootstrap base while BOOTSTRAP_IMAGE is the docker tag"
BOOTSTRAP_IMAGE="$docker_tag" grep -qF "$job_from" "$job_df" || fail "FROM line was expanded to the docker tag"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sed "s|${job_base}|${docker_tag}|" "$job_df" > "$tmp"
if grep -q "$job_base" "$tmp"; then
  fail "a Dockerfile that only names the docker tag still matched the bootstrap base"
fi

echo "job image Dockerfile base check passed"
