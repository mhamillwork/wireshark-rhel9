#!/usr/bin/env bash
# Install the Docker client and dockerd into the job image.
# JOB_IMAGE_ROOT is empty during the image build. Tests set it to a temp tree.
set -euo pipefail

prefix="${JOB_IMAGE_ROOT:-}"
rhsm="${prefix}/etc/rhsm-host"
ubi="${prefix}/etc/yum.repos.d/ubi.repo"

echo "job-image: preparing package configuration"
if [ -e "$rhsm" ] || [ -L "$rhsm" ]; then
  rm -f "$rhsm" || echo "job-image: left ${rhsm} in place" >&2
fi
if [ -f "$ubi" ] && [ -w "$ubi" ] && grep -q '^enabled=' "$ubi" && ! grep -q '^priority=' "$ubi"; then
  sed -i '/^enabled=/a priority=1' "$ubi" || echo "job-image: left ubi.repo unchanged" >&2
fi

echo "job-image: reading repos"
dnf repolist --all > /tmp/repolist.txt
cut -d' ' -f1 /tmp/repolist.txt > /tmp/repo-ids.txt
repos=()
for repo in ubi-9-codeready-builder-rpms "codeready-builder-for-rhel-9-$(uname -m)-rpms"; do
  if grep -qx "$repo" /tmp/repo-ids.txt; then
    repos+=("--enablerepo=${repo}")
  fi
done
while read -r id; do
  [ -n "$id" ] || continue
  case "$id" in
    *docker*) repos+=("--enablerepo=${id}") ;;
  esac
done < /tmp/repo-ids.txt

if rpm -q --whatprovides /usr/bin/docker >/dev/null 2>&1; then
  rpm -q --qf '%{NAME}\n' --whatprovides /usr/bin/docker > /tmp/docker-providers
  while read -r provider; do
    case "$provider" in
      ""|docker-ce|docker-ce-cli|containerd.io) ;;
      *)
        echo "job-image: removing ${provider}, which provides /usr/bin/docker"
        dnf -y remove "$provider"
        ;;
    esac
  done < /tmp/docker-providers
fi

echo "job-image: enabling repos: ${repos[*]:-none}"
if ! dnf -y \
  --setopt=install_weak_deps=False \
  --setopt=tsflags=nodocs \
  --setopt=max_parallel_downloads=10 \
  install "${repos[@]}" \
  ca-certificates \
  git \
  gzip \
  tar \
  docker-ce \
  docker-ce-cli \
  containerd.io
then
  echo "job-image: Satellite did not install docker-ce, docker-ce-cli, and containerd.io" >&2
  dnf list --available docker-ce docker-ce-cli containerd.io >&2 || true
  exit 1
fi

command -v docker
command -v dockerd
command -v containerd
docker --version > /tmp/docker-client-version
grep -q '^Docker version ' /tmp/docker-client-version
dockerd --version
dnf clean all
rm -rf /var/cache/dnf /tmp/repolist.txt /tmp/repo-ids.txt /tmp/docker-providers /tmp/docker-client-version
ln -sfn /run/secrets/rhsm "$rhsm"
echo "job-image: docker client and dockerd are installed"
