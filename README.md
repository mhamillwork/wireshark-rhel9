# wireshark-rhel9

Wireshark and two Red Hat UBI 9 images. `dockerfile/Dockerfile.wireshark-ubi9-build` compiles it. `dockerfile/Dockerfile.wireshark-ubi9-runtime` installs the built RPM and the Qt packages that open the GUI. Versions are in `versions/RHEL9.env` (Wireshark 4.6.9, Packet Penguin 1.0.5, RHEL 9). Wireshark is `src/wireshark-$WIRESHARK_VERSION`, with `$WIRESHARK_VERSION` taken from that file. Plugins live under `src/plugins`. Scripts live under `src/scripts`. See `docs/RHEL9-BUILD.md` for the RPM, the runtime image, and the GitLab pipeline. The compile image copies `src/` to `/src`.

The image installs its RPMs from UBI 9.8 and from the RHEL 9 repositories on Satellite. UBI supplies the compiler and many protocol libraries. BaseOS, AppStream, and CodeReady Builder supply the rest, including flex, c-ares, speexdsp, and the Qt 5.15 GUI. RHEL 9 does not ship Qt 6. It also does not ship `libsmi-devel`, `nghttp3`, spandsp, iLBC, bcg729, or opencore-amr, so those features stay off.

## Base image

`images/ubi9-ubi-9.8.tar.gz` is an archive of the public `registry.access.redhat.com/ubi9/ubi:9.8` image (`sha256:16e9e43d99e181463513cc84a514859b1abb9460f1c4d9e208da4b4e51cd5cc3`). The Wireshark Dockerfile does not use that image. Its base is `artifactory.tahaa.local/tahaa-image-local/ubi9-tahaa-bootstrap:9.8`. Load the public archive only when you need that UBI image locally:

```bash
./src/scripts/load-ubi-image.sh
```

The load script checks the archive checksum and the image id. It loads into Podman when Podman is available, and into Docker otherwise.

## Compile image

Build on the isolated network, where `artifactory.tahaa.local/tahaa-image-local/ubi9-tahaa-bootstrap:9.8` is already loaded or reachable. The image stays in the local Podman store. Podman on a Satellite-registered host mounts the host entitlement, which is how `dnf` reaches BaseOS, AppStream, and CodeReady Builder when the bootstrap still uses those repositories. Enable CodeReady Builder on the host (`codeready-builder-for-rhel-9-<arch>-rpms`); speexdsp, libpcap, Lua, and Ninja come from that repository. Use Podman for this build.

`satellite9b.hsv.local` is the Satellite server those repositories use. The build only pulls packages from it. The build container does not resolve that name, so pass it on the command line. `--add-host` is local to that build.

```bash
podman build \
  --add-host satellite9b.hsv.local:10.10.106.59 \
  -f dockerfile/Dockerfile.wireshark-ubi9-build \
  -t wireshark-ubi9:dev .
```

## Environment

Leave `DISPLAY` unset on the compile image. Compiling does not open a window. `/src/scripts/compile-wireshark.sh` checks the GUI binary with `QT_QPA_PLATFORM=offscreen`, so that check does not need an X server. flex, c-ares, and speexdsp are found on the default pkg-config path.

The runtime image sets `QT_X11_NO_MITSHM=1`. It still leaves `DISPLAY` unset: pass that from the host session and mount the X11 socket when you start the container. Capturing packets needs `NET_RAW` and `NET_ADMIN` on the container. The run command is in `docs/RHEL9-BUILD.md`. `docker compose up` stays on the compile image and does not need the runtime image.

## GitLab CI

Push this repository to the isolated GitLab. Jobs use the image already loaded on the runner. The development pipeline validates, compiles, tests, builds the RPM, and publishes the development image. Override the image name with CI variable `WIRESHARK_IMAGE` if the loaded tag is different. Details are in `docs/RHEL9-BUILD.md`.

The compile job saves `src/build/rhel9/wireshark/run/`. The build is also installed to `/usr/local`, which gives plugins `WiresharkConfig.cmake` and the libraries they link.

## Compile inside the container

The image already contains the Wireshark tree, `/src/scripts`, and `/src/plugins`. Run the compile script in the container:

```bash
docker run --rm wireshark-ubi9:dev /src/scripts/compile-wireshark.sh
```

Use `podman` in place of `docker` when the image is in Podman's store. If the container is already running, use its name:

```bash
docker exec <container> /src/scripts/compile-wireshark.sh
```

The script reads `versions/RHEL9.env` and configures `src/wireshark-$WIRESHARK_VERSION`. It builds with Ninja and installs to `/usr/local`. From the checkout, `tshark` is `src/build/rhel9/wireshark/run/tshark`. Inside the image that path is `/src/build/rhel9/wireshark/run/tshark`.

`./src/scripts/compile-wireshark.sh` compiles a plugin with Wireshark when its `CMakeLists.txt` calls `include(WiresharkPlugin)`. That is the form in `plugins/epan/gryphon`. Wireshark's CMake provides `WiresharkPlugin` and `set_module_info`, so that file is not a project on its own.

A plugin that calls `find_package(Wireshark)` is built after the install. Upstream's example is `doc/plugins.example`.

```bash
docker exec <container> /src/scripts/build-sandbox-plugins.sh
```

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
