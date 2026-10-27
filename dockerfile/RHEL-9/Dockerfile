# Runtime image. The compile image remains the repository-root Dockerfile.
# Build this only after src/scripts/build-rpm.sh has written the RPM.
#
#   docker build -f dockerfile/RHEL-9/Dockerfile -t wireshark-ppv:candidate .
#
# UBI 9 has no Qt 6. The compile uses Qt 5 from AppStream. Installing the RPM
# needs the same UBI and Satellite repositories the compile image uses.

FROM registry.access.redhat.com/ubi9/ubi:9.8

# Versions come from versions/RHEL9.env via --build-arg. There is no second copy here.
ARG WIRESHARK_VERSION
ARG PACKET_PENGUIN_VERSION
ARG RHEL_VERSION
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown
ARG PIPELINE_ID=local
ARG BUILD_TYPE=dev
ARG RPM_DIR

RUN test -n "$WIRESHARK_VERSION" \
    && test -n "$PACKET_PENGUIN_VERSION" \
    && test -n "$RHEL_VERSION"

LABEL org.opencontainers.image.title="wireshark" \
      org.opencontainers.image.version="${WIRESHARK_VERSION}" \
      wireshark.version="${WIRESHARK_VERSION}" \
      packet.penguin.version="${PACKET_PENGUIN_VERSION}" \
      rhel.version="${RHEL_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      gitlab.pipeline.id="${PIPELINE_ID}" \
      build.type="${BUILD_TYPE}"

COPY ${RPM_DIR}/ /tmp/rpms/

RUN printf 'assumeyes=1\nmax_parallel_downloads=10\ntsflags=nodocs\ninstall_weak_deps=0\n' >> /etc/dnf/dnf.conf \
    && rm -rf /etc/rhsm-host \
    && sed -i '/^enabled=/a priority=1' /etc/yum.repos.d/ubi.repo \
    && dnf -y install /tmp/rpms/*.rpm \
    && dnf clean all \
    && rm -rf /var/cache/dnf /tmp/rpms \
    && ln -s /run/secrets/rhsm /etc/rhsm-host

CMD ["/usr/local/bin/tshark", "-v"]
