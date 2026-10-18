# Compile Wireshark on Red Hat Universal Base Image 9.
#
# UBI 9 does not ship flex, c-ares, or speexdsp. Qt 6 is in EPEL, but its GUI
# packages need X11, libinput, and GL libraries that UBI does not provide, so
# this image builds the Wireshark CLI tools rather than the Qt application.
#
#   docker build -t wireshark-ubi9:dev .
# Wireshark 4.6.9 sources live in wireshark/ and are compiled with
# scripts/compile-wireshark.sh (see README.md). The Qt GUI is not built.

FROM registry.access.redhat.com/ubi9/ubi:9.8

ARG FLEX_VERSION=2.6.4
ARG CARES_VERSION=1.34.8
ARG SPEEXDSP_VERSION=1.2.1

RUN printf 'assumeyes=1\nmax_parallel_downloads=10\ntsflags=nodocs\n' >> /etc/dnf/dnf.conf \
    && dnf -y install \
        ca-certificates \
        cmake \
        curl-minimal \
        diffutils \
        gcc \
        gcc-c++ \
        git \
        glib2-devel \
        gzip \
        krb5-devel \
        libcap \
        libcap-devel \
        libgcrypt-devel \
        libpcap-devel \
        libssh-devel \
        libxml2-devel \
        lz4-devel \
        m4 \
        make \
        ninja-build \
        pcre2-devel \
        pkgconf-pkg-config \
        python3 \
        systemd-devel \
        tar \
        which \
        xz \
        zlib-devel \
    && dnf clean all \
    && printf '/usr/local/lib64\n/usr/local/lib\n' > /etc/ld.so.conf.d/usr-local.conf

# flex is the lexer Wireshark requires (find_package(LEX)).
RUN curl -fsSL -o /tmp/flex.tar.gz \
        "https://github.com/westes/flex/releases/download/v${FLEX_VERSION}/flex-${FLEX_VERSION}.tar.gz" \
    && tar -xzf /tmp/flex.tar.gz -C /tmp \
    && cd "/tmp/flex-${FLEX_VERSION}" \
    && ./configure --prefix=/usr/local \
    && make -j"$(nproc)" \
    && touch doc/flex.1 \
    && make install \
    && ln -sf /usr/local/bin/flex /usr/local/bin/lex \
    && rm -rf /tmp/flex.tar.gz "/tmp/flex-${FLEX_VERSION}"

# c-ares is a required Wireshark dependency and is not in the UBI repositories.
ENV PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig

RUN curl -fsSL -o /tmp/c-ares.tar.gz \
        "https://github.com/c-ares/c-ares/releases/download/v${CARES_VERSION}/c-ares-${CARES_VERSION}.tar.gz" \
    && tar -xzf /tmp/c-ares.tar.gz -C /tmp \
    && cmake -S "/tmp/c-ares-${CARES_VERSION}" -B /tmp/c-ares-build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCARES_SHARED=ON \
        -DCARES_STATIC=OFF \
        -DCARES_BUILD_TOOLS=OFF \
    && cmake --build /tmp/c-ares-build \
    && cmake --install /tmp/c-ares-build \
    && ldconfig \
    && rm -rf /tmp/c-ares.tar.gz /tmp/c-ares-build "/tmp/c-ares-${CARES_VERSION}"

# speexdsp is required for sharkd, which Wireshark builds by default.
RUN curl -fsSL -o /tmp/speexdsp.tar.gz \
        "https://downloads.xiph.org/releases/speex/speexdsp-${SPEEXDSP_VERSION}.tar.gz" \
    && tar -xzf /tmp/speexdsp.tar.gz -C /tmp \
    && cd "/tmp/speexdsp-${SPEEXDSP_VERSION}" \
    && ./configure --prefix=/usr/local --libdir=/usr/local/lib64 --disable-static \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig \
    && rm -rf /tmp/speexdsp.tar.gz "/tmp/speexdsp-${SPEEXDSP_VERSION}"

WORKDIR /src
CMD ["bash"]
