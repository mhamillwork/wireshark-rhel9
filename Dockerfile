# Compile Wireshark 4.6.9, including the Qt 6 GUI, on UBI 9.8.
#
# UBI 9.8 has the compiler and most protocol libraries. It does not ship Qt 6
# or several libraries the GUI and the default features need (flex, c-ares,
# speexdsp, Lua, GnuTLS, and the X11, Wayland, and GL stack). Those RPMs come
# from Rocky Linux 9.8, which matches this UBI release, and from EPEL 9.
# UBI repositories keep priority, so packages UBI does ship stay on the UBI build.
# libsmi and nghttp3 are not packaged for EL9 in these repositories.
#
# On an isolated network, load the vendored base image first so this FROM
# line does not pull from the registry. The build itself still needs network
# access to UBI, Rocky Linux 9.8, and EPEL.
#
#   ./scripts/load-ubi-image.sh
#   docker build -t wireshark-ubi9:dev .
#
# Wireshark 4.6.9 sources live in wireshark/ and are compiled with
# scripts/compile-wireshark.sh (see README.md).

FROM registry.access.redhat.com/ubi9/ubi:9.8

RUN printf 'assumeyes=1\nmax_parallel_downloads=10\ntsflags=nodocs\ninstall_weak_deps=0\n' >> /etc/dnf/dnf.conf \
    && dnf -y install dnf-plugins-core \
    && sed -i '/^enabled=1/a priority=1' /etc/yum.repos.d/ubi*.repo \
    && dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
    && rpm --import https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9 \
    && printf '%s\n' \
        '[rocky9-baseos]' \
        'name=Rocky Linux 9.8 BaseOS' \
        'baseurl=https://dl.rockylinux.org/pub/rocky/9.8/BaseOS/x86_64/os/' \
        'gpgcheck=1' \
        'gpgkey=https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9' \
        'enabled=1' \
        'priority=100' \
        '[rocky9-appstream]' \
        'name=Rocky Linux 9.8 AppStream' \
        'baseurl=https://dl.rockylinux.org/pub/rocky/9.8/AppStream/x86_64/os/' \
        'gpgcheck=1' \
        'gpgkey=https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9' \
        'enabled=1' \
        'priority=100' \
        '[rocky9-crb]' \
        'name=Rocky Linux 9.8 CRB' \
        'baseurl=https://dl.rockylinux.org/pub/rocky/9.8/CRB/x86_64/os/' \
        'gpgcheck=1' \
        'gpgkey=https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9' \
        'enabled=1' \
        'priority=100' \
        > /etc/yum.repos.d/rocky9.repo \
    && dnf -y install \
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
        qt6-qtbase-devel \
        qt6-qttools-devel \
        qt6-qtmultimedia-devel \
        qt6-qt5compat-devel \
        qt6-linguist \
        qt6-qtsvg-devel \
        qt6-qtimageformats \
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
        spandsp-devel \
        ilbc-devel \
        bcg729-devel \
        minizip-devel \
        opencore-amr-devel \
        libxslt \
        docbook-style-xsl \
        rubygem-asciidoctor \
        xdg-utils \
        hicolor-icon-theme \
    && dnf clean all

WORKDIR /src
CMD ["bash"]
