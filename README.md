# wireshark-rhel9

Wireshark 4.6.9, the current stable release, and a Red Hat UBI 9 image that can compile it. The Wireshark sources are in `wireshark/` so this repository can be copied to a network that cannot reach the internet.

The image has the RPMs for a full Wireshark 4.6.9 compile, including the Qt 6 GUI. UBI 9.8 supplies the compiler and most protocol libraries. Rocky Linux 9.8 and EPEL 9 supply the packages UBI does not ship: Qt 6, flex, c-ares, speexdsp, and the X11, Wayland, and GL libraries Qt needs. `libsmi` and `nghttp3` are not packaged for EL9 in those repositories, so those two features stay off.

## Base image

`images/ubi9-ubi-9.8.tar.gz` is `docker save` of `registry.access.redhat.com/ubi9/ubi:9.8` (`sha256:16e9e43d99e181463513cc84a514859b1abb9460f1c4d9e208da4b4e51cd5cc3`), the image named by the Dockerfile `FROM` line. Load it before `docker build` so the build uses that copy and does not contact the registry:

```bash
./scripts/load-ubi-image.sh
docker build -t wireshark-ubi9:dev .
```

The load script checks the archive checksum and the image id after `docker load`.

## Compile image

On a machine with network access, after the base image is loaded:

```bash
docker build -t wireshark-ubi9:dev .
docker save wireshark-ubi9:dev | gzip > wireshark-ubi9.tar.gz
```

Copy `wireshark-ubi9.tar.gz` and this repository to the isolated network, then:

```bash
docker load -i wireshark-ubi9.tar.gz
```

## GitLab CI

Push this repository to the isolated GitLab. The job uses the image already loaded on the runner, checks out this project, and compiles `wireshark/`. Override the image name with CI variable `WIRESHARK_IMAGE` if the loaded tag is different.

`./build/run/tshark` is saved as a job artifact. The build is also installed to `/usr/local`, which gives `/sandbox` plugins `WiresharkConfig.cmake` and the libraries they link.

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

After the headers are installed, build plugins from `/sandbox`:

```bash
docker compose exec wireshark-compile ./scripts/build-sandbox-plugins.sh
```

`SANDBOX_DIR` changes the host directory that is mounted. `WIRESHARK_IMAGE` changes the image tag.
