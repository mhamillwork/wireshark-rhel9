# wireshark-rhel9

Wireshark and two Red Hat UBI 9 images. `dockerfile/Dockerfile.wireshark-ubi9-build` compiles it. `dockerfile/Dockerfile.wireshark-ubi9-runtime` installs the built RPM and the Qt packages that open the GUI. Versions are in `versions/RHEL9.env` (Wireshark 4.6.9, Packet Penguin 1.0.5, RHEL 9). Wireshark is `src/wireshark-$WIRESHARK_VERSION`, with `$WIRESHARK_VERSION` taken from that file. Plugins live under `src/plugins`. Scripts live under `src/scripts`. See `docs/RHEL9-BUILD.md` for the RPM, the runtime image, and the GitLab pipeline. The compile image copies `src/` to `/src` and leaves out `src/build`. The runtime image copies the RPM from `src/artifacts/rpms`.

The image installs its RPMs from UBI 9.8 and from the RHEL 9 repositories on Satellite. UBI supplies the compiler and many protocol libraries. BaseOS, AppStream, and CodeReady Builder supply the rest, including flex, c-ares, speexdsp, and the Qt 5.15 GUI. RHEL 9 does not ship Qt 6. It also does not ship `libsmi-devel`, `nghttp3`, spandsp, iLBC, bcg729, or opencore-amr, so those features stay off.

## Base image

`images/ubi9-ubi-9.8.tar.gz` is an archive of the public `registry.access.redhat.com/ubi9/ubi:9.8` image (`sha256:16e9e43d99e181463513cc84a514859b1abb9460f1c4d9e208da4b4e51cd5cc3`). The Wireshark Dockerfile does not use that image. Its base is `artifactory.tahaa.local/tahaa-image-local/ubi9-tahaa-bootstrap:9.8`. Load the public archive only when you need that UBI image locally:

```bash
./src/scripts/load-ubi-image.sh
```

The load script checks the archive checksum and the image id, then loads the archive with Docker.

## Compile image

Build on the isolated network, where `artifactory.tahaa.local/tahaa-image-local/ubi9-tahaa-bootstrap:9.8` is already loaded or reachable. The image stays in the local Docker store. The bootstrap image carries the RHEL 9 repositories. speexdsp, libpcap, Lua, and Ninja come from CodeReady Builder when that repository is present in the bootstrap. Use Docker for this build.

`satellite9b.hsv.local` is the Satellite server those repositories use. The build only pulls packages from it. The build container does not resolve that name, so pass it on the command line. `--add-host` is local to that build.

```bash
docker build \
  --add-host satellite9b.hsv.local:10.10.106.59 \
  -f dockerfile/Dockerfile.wireshark-ubi9-build \
  -t wireshark-ubi9:dev .
```

## Environment

Leave `DISPLAY` unset on the compile image. Compiling does not open a window. `/src/scripts/compile-wireshark.sh` checks the GUI binary with `QT_QPA_PLATFORM=offscreen`, so that check does not need an X server. flex, c-ares, and speexdsp are found on the default pkg-config path.

The runtime image sets `QT_X11_NO_MITSHM=1`. It still leaves `DISPLAY` unset: pass that from the host session and mount the X11 socket when you start the container. Capturing packets needs `NET_RAW` and `NET_ADMIN` on the container. The run command is in the runtime section below. `docker compose up` stays on the compile image and does not need the runtime image.

## GitLab CI

Push this repository to the isolated GitLab. The first job builds `dockerfile/Dockerfile.wireshark-ubi9-build` on the runner, which can reach Satellite, and tags it `wireshark-ubi9:dev`. The compile jobs then run inside that image. `BUILD_TYPE` defaults to `dev`. A development pipeline validates, compiles, tests, builds the RPM, and publishes development image tags. It does not publish the release images or the RPM. `BUILD_TYPE=release` publishes those, and only from the matching protected Git tag. Override the compile image name with CI variable `WIRESHARK_IMAGE` if the loaded tag is different. Details are in `docs/RHEL9-BUILD.md`.

The compile job saves `src/build/rhel9/wireshark/run/`. The build is also installed to `/usr/local`, which gives plugins `WiresharkConfig.cmake` and the libraries they link.

## Compile inside the container

The image already contains the Wireshark tree, `/src/scripts`, and `/src/plugins`. Run the compile script in the container:

```bash
docker run --rm wireshark-ubi9:dev /src/scripts/compile-wireshark.sh
```

If the container is already running, use its name:

```bash
docker exec <container> /src/scripts/compile-wireshark.sh
```

The script reads `versions/RHEL9.env` and configures `src/wireshark-$WIRESHARK_VERSION`. It builds with Ninja and installs to `/usr/local`. From the checkout, `tshark` is `src/build/rhel9/wireshark/run/tshark`. Inside the image that path is `/src/build/rhel9/wireshark/run/tshark`.

`--clean` deletes that CMake build directory, including `CMakeCache.txt`. It leaves `src/build/rhel9/staging`, `src/build/rhel9/logs`, and anything already installed under `/usr/local`.

```bash
./src/scripts/compile-wireshark.sh --rhel 9 --clean --build
docker exec <container> /src/scripts/compile-wireshark.sh --rhel 9 --clean --build
```

`./src/scripts/compile-wireshark.sh` compiles a plugin with Wireshark when its `CMakeLists.txt` calls `include(WiresharkPlugin)`. That is the form in `plugins/epan/gryphon`. Wireshark's CMake provides `WiresharkPlugin` and `set_module_info`, so that file is not a project on its own.

A plugin that calls `find_package(Wireshark)` is built after the install. Upstream's example is `doc/plugins.example`.

```bash
docker exec <container> /src/scripts/build-sandbox-plugins.sh
```

## Package the RPM and run the runtime image

A finished compile does not write the RPM and does not build the runtime image. The runtime file is `dockerfile/Dockerfile.wireshark-ubi9-runtime`.

`--package` builds, installs into `src/build/rhel9/staging`, and writes the RPM:

```bash
./src/scripts/compile-wireshark.sh --rhel 9 --package
```

Inside the compile container:

```bash
docker exec <container> /src/scripts/compile-wireshark.sh --rhel 9 --package
```

The RPM is `src/artifacts/rpms/rhel9/wireshark-4.6.9-1.ppv1.0.5.el9.x86_64.rpm`. The architecture follows the build machine.

From the checkout, build the runtime image. It installs the RPM from that directory. The local tag is `wireshark-ppv:candidate`, separate from the compile image `wireshark-ubi9:dev`. `dnf` still needs the Satellite host mapping.

```bash
set -a
. ./versions/RHEL9.env
set +a
docker build \
  --add-host satellite9b.hsv.local:10.10.106.59 \
  -f dockerfile/Dockerfile.wireshark-ubi9-runtime \
  --build-arg WIRESHARK_VERSION="$WIRESHARK_VERSION" \
  --build-arg PACKET_PENGUIN_VERSION="$PACKET_PENGUIN_VERSION" \
  --build-arg RHEL_VERSION="$RHEL_VERSION" \
  --build-arg BUILD_TYPE=dev \
  --build-arg RPM_DIR="src/artifacts/rpms/rhel${RHEL_VERSION}" \
  -t wireshark-ppv:candidate .
```

A check with no display overrides the GUI command:

```bash
docker run --rm -e QT_QPA_PLATFORM=offscreen wireshark-ppv:candidate /usr/local/bin/tshark -v
docker run --rm -e QT_QPA_PLATFORM=offscreen wireshark-ppv:candidate /usr/local/bin/wireshark --version
```

Open the window from a graphical session. `DISPLAY` comes from that session. Packet capture uses `NET_RAW` and `NET_ADMIN`.

```bash
docker run --rm \
  -e DISPLAY \
  -e XAUTHORITY=/tmp/.Xauthority \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "${XAUTHORITY:-$HOME/.Xauthority}:/tmp/.Xauthority:ro" \
  --network host \
  --cap-add NET_RAW --cap-add NET_ADMIN \
  wireshark-ppv:candidate
```

GitLab runs the same steps after compile and test. The rpm job passes `--package`, the docker job builds this Dockerfile, and publish pushes the image to Artifactory.

## Compose

`docker-compose.yml` mounts the workstation checkout `${HOME}/sandbox/wireshark-packet-penguin/src` at `/src`. The parent checkout is read-only at `/workspace`. The build writes `/src/build` back into that `src` directory. The service uses host networking and the workstation X11 display.

Run Compose from the graphical session so `DISPLAY` is set. The X11 cookie is `${XAUTHORITY}`, or `~/.Xauthority` when that variable is unset.

```bash
docker compose up -d
docker compose exec wireshark-compile /src/scripts/compile-wireshark.sh
docker compose exec wireshark-compile /src/build/rhel9/wireshark/run/wireshark
```

If the window is refused, allow the container's root user on the local display:

```bash
xhost +SI:localuser:root
```
