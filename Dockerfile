# Compile Wireshark 4.6.9 on UBI 9.8.
#
# UBI 9.8 supplies the compiler and many protocol libraries. flex, c-ares,
# speexdsp, and the Qt 5 GUI are RHEL 9 packages. A host registered to
# Satellite exposes BaseOS, AppStream, and CodeReady Builder during this
# RUN; Podman on that host mounts the host entitlement at /run/secrets.
# RHEL 9 does not ship Qt 6, so the GUI is Qt 5.15. It also does not ship
# libsmi-devel, nghttp3, spandsp, iLBC, bcg729, or opencore-amr.
#
# No DISPLAY (or other ENV) is set. Compiling does not open a window, and
# scripts/compile-wireshark.sh runs "wireshark --version" with
# QT_QPA_PLATFORM=offscreen. Pass DISPLAY only when starting a container
# that should show the GUI on a host X server.
#
#   ./scripts/load-ubi-image.sh
#   podman build -t wireshark-ubi9:dev .
#
# The build context's src/ directory is copied to /src. A GitLab checkout
# puts wireshark-$WIRESHARK_VERSION, scripts, and plugins there.
# Compile inside the image with /src/scripts/compile-wireshark.sh.

FROM registry.access.redhat.com/ubi9/ubi:9.8

RUN printf 'assumeyes=1\nmax_parallel_downloads=10\ntsflags=nodocs\ninstall_weak_deps=0\n' >> /etc/dnf/dnf.conf \
    && rm -rf /etc/rhsm-host \
    && sed -i '/^enabled=/a priority=1' /etc/yum.repos.d/ubi.repo \
    && bash -c 'set -euo pipefail; \
        repos=(); \
        for repo in ubi-9-codeready-builder-rpms "codeready-builder-for-rhel-9-$(uname -m)-rpms"; do \
          if dnf repolist --all | awk "{print \$1}" | grep -qx "$repo"; then \
            repos+=("--enablerepo=${repo}"); \
          fi; \
        done; \
        echo "CodeReady Builder repos: ${repos[*]:-none}"; \
        dnf -y install "${repos[@]}" \
          ca-certificates \
          cmake \
          curl-minimal \
          diffutils \
          gcc \
          gcc-c++ \
          git \
          gzip \
          m4 \
          make \
          ninja-build \
          rpm-build \
          pkgconf-pkg-config \
          python3 \
          tar \
          which \
          xz \
          flex \
          perl \
          perl-Parse-Yapp \
          gettext-devel \
          desktop-file-utils \
          glib2-devel \
          libgcrypt-devel \
          c-ares-devel \
          pcre2-devel \
          libxml2-devel \
          speexdsp-devel \
          qt5-qtbase-devel \
          qt5-qttools-devel \
          qt5-qtmultimedia-devel \
          qt5-linguist \
          qt5-qtsvg-devel \
          qt5-qtimageformats \
          libxkbcommon-devel \
          libpcap-devel \
          zlib-devel \
          lz4-devel \
          libzstd-devel \
          brotli-devel \
          libnghttp2-devel \
          krb5-devel \
          libcap \
          libcap-devel \
          libssh-devel \
          systemd-devel \
          lua-devel \
          gnutls-devel \
          snappy-devel \
          xxhash-devel \
          libmaxminddb-devel \
          libnl3-devel \
          opus-devel \
          sbc-devel \
          libxslt \
          docbook-style-xsl \
          xdg-utils \
          hicolor-icon-theme; \
        dnf clean all; \
        rm -rf /var/cache/dnf' \
    && ln -s /run/secrets/rhsm /etc/rhsm-host

# Version configuration used by scripts/compile-wireshark.sh.
COPY versions/ /opt/wireshark-build/versions/

# src/wireshark-${WIRESHARK_VERSION} and src/plugins from the GitLab checkout.
COPY src/ /src/

WORKDIR /src
CMD ["bash"]
