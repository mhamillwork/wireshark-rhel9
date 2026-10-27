# wireshark-rhel9

Wireshark and a Red Hat UBI 9 image that can compile it. Versions are in `versions/RHEL9.env` (Wireshark 4.6.9, Packet Penguin 1.0.5, RHEL 9). The compile script accepts `src/wireshark-$WIRESHARK_VERSION` or a `wireshark/` tree of that version, and plugins under `src/plugins`. See `docs/RHEL9-BUILD.md` for the RPM, the runtime image, and the GitLab pipeline. The image build copies `src/` to `/src`.

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

Push this repository to the isolated GitLab. Jobs use the image already loaded on the runner. The development pipeline validates, compiles, tests, builds the RPM, and publishes the development image. Override the image name with CI variable `WIRESHARK_IMAGE` if the loaded tag is different. Details are in `docs/RHEL9-BUILD.md`.

The compile job saves `build/rhel9/wireshark/run/`. The build is also installed to `/usr/local`, which gives plugins `WiresharkConfig.cmake` and the libraries they link.

## Compile inside the container

The image already contains the Wireshark tree, `/src/scripts`, and `/src/plugins`. Run the compile script in the container:

```bash
docker run --rm wireshark-ubi9:dev /src/scripts/compile-wireshark.sh
```

Use `podman` in place of `docker` when the image is in Podman's store. If the container is already running, use its name:

```bash
docker exec <container> /src/scripts/compile-wireshark.sh
```

The script reads `versions/RHEL9.env`, configures the matching Wireshark tree, builds with Ninja, and installs to `/usr/local`. Binaries are at `build/rhel9/wireshark/run/tshark` and `build/rhel9/wireshark/run/wireshark`. Inside the image whose scripts live in `/src/scripts`, that path is `/src/build/rhel9/wireshark/run/`.

After that install, build each plugin under `/src/plugins`:

```bash
docker exec <container> /src/scripts/build-sandbox-plugins.sh
```

Each directory with a `CMakeLists.txt` under the plugin root is built on its own. Upstream's example is `doc/plugins.example` in the Wireshark tree.

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
