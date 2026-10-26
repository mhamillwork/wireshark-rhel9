# wireshark-rhel9

Wireshark 4.6.9, the current stable release, and a Red Hat UBI 9 image that can compile it. Put the Wireshark sources at `src/wireshark-4.6.9` and dissector plugins at `src/plugins`. The image build copies `src/` to `/src`.

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

Leave `DISPLAY` unset, and leave every other environment variable unset. Compiling does not open a window. `scripts/compile-wireshark.sh` checks the GUI binary with `QT_QPA_PLATFORM=offscreen`, so that check does not need an X server. flex, c-ares, and speexdsp are found on the default pkg-config path.

To show the GUI on a host display, pass `DISPLAY` when you start the container and mount the X11 socket. The value depends on the host session, so it does not belong in the image. Capturing packets needs `NET_RAW` and `NET_ADMIN` on the container, not an environment variable.

## GitLab CI

Push this repository to the isolated GitLab. The job uses the image already loaded on the runner, checks out this project, and compiles `src/wireshark-4.6.9`. Override the image name with CI variable `WIRESHARK_IMAGE` if the loaded tag is different.

`./build/run/tshark` is saved as a job artifact. The build is also installed to `/usr/local`, which gives `/src/plugins` `WiresharkConfig.cmake` and the libraries they link.

The host needs Docker Compose v2 (`docker compose`).

## Compose session and plugins

`~/sandbox` is mounted at `/sandbox` in the compile container. Put each dissector plugin in its own subdirectory with a `CMakeLists.txt` (see `wireshark/doc/plugins.example`).

```bash
mkdir -p ~/sandbox
./scripts/clone-into-container.sh
```

That starts the container and clones this repository into `/src/project` inside it. The default clone is local (`file` clone of the mounted checkout) and does not use the network. To clone from the isolated GitLab instead:

```bash
WIRESHARK_GIT_URL=https://gitlab.example/group/wireshark-rhel9.git \
  ./scripts/clone-into-container.sh
```

Compile inside the running container:

```bash
docker compose exec -w /src/project wireshark-compile ./scripts/compile-wireshark.sh
```

`./scripts/clone-into-container.sh --compile` clones and compiles in one step.

After the headers are installed, build plugins from `/src/plugins`:

```bash
docker compose exec wireshark-compile ./scripts/build-sandbox-plugins.sh
```

`SANDBOX_DIR` changes the host directory that is mounted. `WIRESHARK_IMAGE` changes the image tag.
