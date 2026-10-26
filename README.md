# wireshark-rhel9

Wireshark 4.6.9, the current stable release, and a Red Hat UBI 9 image that can compile it. Put Wireshark at `src/wireshark-4.6.9`, the compile scripts at `src/scripts`, and dissector plugins at `src/plugins`. The image build copies `src/` to `/src`.

The image installs its RPMs from UBI 9.8 and from the RHEL 9 repositories on Satellite. UBI supplies the compiler and many protocol libraries. BaseOS, AppStream, and CodeReady Builder supply the rest, including flex, c-ares, speexdsp, and the Qt 5.15 GUI. RHEL 9 does not ship Qt 6. It also does not ship `libsmi-devel`, `nghttp3`, spandsp, iLBC, bcg729, or opencore-amr, so those features stay off.

## Base image

`images/ubi9-ubi-9.8.tar.gz` is an archive of `registry.access.redhat.com/ubi9/ubi:9.8` (`sha256:16e9e43d99e181463513cc84a514859b1abb9460f1c4d9e208da4b4e51cd5cc3`), the image named by the Dockerfile `FROM` line. Load it before the build so that line does not contact the registry:

```bash
./scripts/load-ubi-image.sh
```

The load script checks the archive checksum and the image id. It loads into Podman when Podman is available, and into Docker otherwise.

## Compile image

Build on a RHEL host registered to Satellite, after the base image is loaded. Podman mounts that host's entitlement into the build, which is how `dnf` reaches BaseOS, AppStream, and CodeReady Builder. Enable CodeReady Builder on the host (`codeready-builder-for-rhel-9-<arch>-rpms`); speexdsp, libpcap, Lua, and Ninja come from that repository. Use Podman for this build.

```bash
podman build -t wireshark-ubi9:dev .
podman save wireshark-ubi9:dev | gzip > wireshark-ubi9.tar.gz
```

Copy `wireshark-ubi9.tar.gz` and this repository to the isolated network, then:

```bash
docker load -i wireshark-ubi9.tar.gz
```

## Environment

Leave `DISPLAY` unset, and leave every other environment variable unset. Compiling does not open a window. `/src/scripts/compile-wireshark.sh` checks the GUI binary with `QT_QPA_PLATFORM=offscreen`, so that check does not need an X server. flex, c-ares, and speexdsp are found on the default pkg-config path.

To show the GUI on a host display, pass `DISPLAY` when you start the container and mount the X11 socket. The value depends on the host session, so it does not belong in the image. Capturing packets needs `NET_RAW` and `NET_ADMIN` on the container, not an environment variable.

## GitLab CI

Push this repository to the isolated GitLab. The job uses the image already loaded on the runner and runs `/src/scripts/compile-wireshark.sh`. Override the image name with CI variable `WIRESHARK_IMAGE` if the loaded tag is different.

`/src/build/run/tshark` is copied to `build/run/` and saved as a job artifact. The build is also installed to `/usr/local`, which gives `/src/plugins` `WiresharkConfig.cmake` and the libraries they link.

## Compile inside the container

The image already contains `/src/wireshark-4.6.9`, `/src/scripts`, and `/src/plugins`. Run the compile script in the container:

```bash
docker run --rm wireshark-ubi9:dev /src/scripts/compile-wireshark.sh
```

Use `podman` in place of `docker` when the image is in Podman's store. If the container is already running, use its name:

```bash
docker exec <container> /src/scripts/compile-wireshark.sh
```

The script configures `/src/wireshark-4.6.9`, builds with Ninja, and installs to `/usr/local`. Binaries are at `/src/build/run/tshark` and `/src/build/run/wireshark`.

After that install, build each plugin under `/src/plugins`:

```bash
docker exec <container> /src/scripts/build-sandbox-plugins.sh
```

Each immediate subdirectory with a `CMakeLists.txt` is built on its own. The example is `/src/wireshark-4.6.9/doc/plugins.example`.
