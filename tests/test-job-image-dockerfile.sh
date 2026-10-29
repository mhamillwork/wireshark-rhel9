#!/usr/bin/env bash
# The job Dockerfile FROMs the bootstrap image that carries the Docker yum
# repo. GitLab sets BOOTSTRAP_IMAGE to that same tag for the job container.
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

job_df="$root/dockerfile/Dockerfile.ubi9-tahaa-bootstrap-docker"
job_base='artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap-docker:9.8'
plain_base='artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap:9.8'
# shellcheck disable=SC2016
job_from='FROM ${BOOTSTRAP_IMAGE}'

[ -f "$job_df" ] || fail "job Dockerfile is missing"
grep -qF "ARG BOOTSTRAP_IMAGE=${job_base}" "$job_df" || fail "job Dockerfile does not start from the docker yum repo image"
BOOTSTRAP_IMAGE="$job_base" grep -qF "$job_from" "$job_df" || fail "FROM line was expanded to the docker tag"
grep -q "$plain_base" "$root/dockerfile/Dockerfile.wireshark-ubi9-build" || fail "compile Dockerfile left the plain bootstrap"
grep -q "$plain_base" "$root/dockerfile/Dockerfile.wireshark-ubi9-runtime" || fail "runtime Dockerfile left the plain bootstrap"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
sed "s|${job_base}|${plain_base}|" "$job_df" > "$tmp"
if grep -qF "ARG BOOTSTRAP_IMAGE=${job_base}" "$tmp"; then
  fail "the plain bootstrap still matched the docker yum repo base"
fi

echo "job image Dockerfile base check passed"
