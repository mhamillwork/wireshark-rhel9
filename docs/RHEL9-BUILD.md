# RHEL 9 Wireshark and Packet Penguin builds

Versions live in `versions/RHEL9.env`:

```bash
WIRESHARK_VERSION=4.6.9
PACKET_PENGUIN_VERSION=1.0.5
RHEL_VERSION=9
RPM_PACKAGE_RELEASE=1
```

`RPM_PACKAGE_RELEASE` is the packaging counter. Increment it when the RPM changes and the Wireshark and Packet Penguin versions stay the same. Image tags and the RPM release field use the three version values plus this counter.

`versions/RHEL8.env` is present so the interface can grow. This repository has no RHEL 8 tree, and `--rhel 8` fails on purpose.

## Where sources are found

Wireshark is `src/wireshark-$WIRESHARK_VERSION`. The directory suffix is the `WIRESHARK_VERSION` value from `versions/RHEL9.env`. Packet Penguin plugins are CMake projects under `src/plugins/`. A plugin may put the same version in a `PACKET_PENGUIN_VERSION` file; if that file exists and differs, the build stops.

There is no Packet Penguin source in this checkout, so packaging fails here until those plugins are added.

The tests stay in `tests/` at the checkout root. The compile image copies `src/` and does not include that directory. GitLab runs `./src/scripts/validate-repo.sh`, which calls the tests from the checkout.

A plugin `CMakeLists.txt` that calls `include(WiresharkPlugin)` is the form in `plugins/epan/gryphon`. The compile script links that directory into the Wireshark source tree at `packet-penguin-plugins/` and writes `CMakeListsCustom.txt`, and Wireshark's CMake compiles it. A `CMakeLists.txt` that calls `find_package(Wireshark)` is built after Wireshark is installed. C sources with no `CMakeLists.txt` are compiled with Wireshark when they are linked into the tree, and they ship inside `libwireshark`. `--package` still requires one of those layouts.

## Local compile

The script can be started from any directory.

```bash
./src/scripts/compile-wireshark.sh --help
./src/scripts/compile-wireshark.sh --rhel 9 --check
./src/scripts/compile-wireshark.sh --rhel 9 --clean --build --test
```

With no mode flags it builds and runs the version checks. The out-of-source build is `src/build/rhel9/wireshark/`. `tshark` is `src/build/rhel9/wireshark/run/tshark`. Inside the image, that same directory is `/src/build/rhel9/wireshark/run/tshark`.

`--clean` deletes that CMake build directory, including `CMakeCache.txt`. It leaves `src/build/rhel9/staging`, `src/build/rhel9/logs`, and anything already installed under `/usr/local`. Clean and compile again with:

```bash
./src/scripts/compile-wireshark.sh --rhel 9 --clean --build
```

Inside the compile container the same command is `/src/scripts/compile-wireshark.sh --rhel 9 --clean --build`.

RHEL 9 has Qt 5.15, so the script passes `-DUSE_qt6=OFF`. Ninja links with the install RPATH (`$ORIGIN/../lib64`). The script symlinks the libraries from `run/` into that directory. The version check also sets `LD_LIBRARY_PATH` to `run/`.

Build tools are gcc, cmake, and ninja, plus the libraries installed by `dockerfile/Dockerfile.wireshark-ubi9-build` from the bootstrap image's RHEL 9 repositories (BaseOS, AppStream, and CodeReady Builder). Qt 6, libsmi, nghttp3, spandsp, iLBC, bcg729, and opencore-amr are not in RHEL 9 and stay off.

## RPM

The package name is `wireshark-ppv`. It installs under `/usr/local` and does not replace the RHEL `wireshark` package. `/usr/local/bin` is normally ahead of `/usr/bin`.

`--package` fills `src/build/rhel9/staging` by installing the build with `DESTDIR`. `rpmbuild` copies that directory into the RPM. Satellite is the source of the RHEL packages `dnf` pulls while the images are built. This repository publishes the runtime image to Artifactory.

```bash
./src/scripts/compile-wireshark.sh --rhel 9 --package
```

Output:

```text
src/artifacts/rpms/rhel9/wireshark-ppv-4.6.9-1.ppv1.0.5.el9.x86_64.rpm
```

The architecture follows the build machine. Inspect it with:

```bash
rpm -qpi src/artifacts/rpms/rhel9/*.rpm
rpm -qp --requires src/artifacts/rpms/rhel9/*.rpm
rpm -qpl src/artifacts/rpms/rhel9/*.rpm
```

`rpmlint` runs when it is installed. Packaging errors fail the script. Two results are filtered in `src/rpmbuild/rpmlintrc`: `dir-or-file-in-usr-local`, because the package lives under `/usr/local` beside the distribution Wireshark, and `no-signature`, because signing uses a key that is not in this repository. `invalid-license` can appear as a warning: the spec uses the SPDX id `GPL-2.0-or-later`, which older rpmlint license lists do not know. Other rpmlint errors still fail the build. On a host without `rpmlint`, the script records that the metadata checks still ran.

`./src/scripts/test-rpm.sh` repeats the metadata checks. If podman or docker can see the local bootstrap image, it also installs and removes the RPM in a container. Otherwise it says that installation test was not run.

## Images

The compile image and the runtime image are separate Dockerfiles. They share the bootstrap `artifactory.tahaa.local/tahaa-image-local/ubi9-tahaa-bootstrap:9.8`, which already has the isolated-network certificates and repositories. They do not inherit each other: the published image does not contain the compiler. Do not turn TLS verification off.

`dockerfile/Dockerfile.wireshark-ubi9-build` is the compile image, tagged `wireshark-ubi9:dev`. `docker compose up` uses that image. It does not require the runtime image to exist.

`dockerfile/Dockerfile.wireshark-ubi9-runtime` is the image that gets published. It installs the RPM from `src/artifacts/rpms/rhel9/` and the packages the GUI needs on top of what the RPM requires. `install_weak_deps=0` drops recommended plugins, so the file names `qt5-qtbase-gui` (the xcb platform plugin `libqxcb.so`), `qt5-qtsvg`, `qt5-qtmultimedia`, `qt5-qtimageformats`, DejaVu fonts, fontconfig, the X11 and xcb libraries, `libxkbcommon-x11`, `mesa-libGL`, the icon theme, `dbus-libs`, and `glib2`. The image sets `QT_X11_NO_MITSHM=1` and `XDG_RUNTIME_DIR`. It does not set `DISPLAY` or `QT_QPA_PLATFORM`. Its command is `/usr/local/bin/wireshark`. Build it on the isolated network. `dnf` uses `satellite9b.hsv.local`, and the build container does not resolve that name, so the command passes the host mapping.

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

The local tag is `wireshark-ppv:candidate` so this build does not replace the compile image `wireshark-ubi9:dev`.

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

## GitLab

Commits run with `BUILD_TYPE=dev`. A manual pipeline can select `dev` or `release`.

Stages, in order: validate, compile, test, rpm, package-test, docker, publish. Publish does not run unless the earlier jobs passed.

Development tags:

```text
artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9-dev-mhamill
artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9-dev-mhamill-a1b2c3d4
```

The username comes from `GITLAB_USER_LOGIN` and is sanitized. The tag with the short commit SHA is the immutable one. The username tag moves.

Release tag, with no `-dev` suffix:

```text
artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9
```

A release is published only when all of these are true:

- `BUILD_TYPE=release`
- the Git ref is protected (`CI_COMMIT_REF_PROTECTED=true`)
- the pipeline is the Git tag `4.6.9-ppv1.0.5-rhel9`

Setting `BUILD_TYPE=release` on an ordinary branch does not publish. If the release tag already exists in the registry, the push stops. Prefer an immutable tag policy in Artifactory as well.

The runner uses the compile image already loaded as `wireshark-ubi9:dev` (`pull_policy: if-not-present`). Rebuild that image after this change so it contains `rpm-build` and `versions/`. The rpm job compiles again: the compile job keeps `run/` and the logs, and the package step needs a fresh CMake build in that job. Publish uses `docker` or `podman` from the job, so the runner has to provide one of those commands (a shell runner, or a client plus the engine socket). The registry must be reachable from the runner, and the runner must trust the Artifactory certificate. Do not disable TLS verification.

Merge request pipelines run the checks and do not publish. A branch pipeline publishes the development tags. Release publishing is a separate manual pipeline on the protected Git tag, and a resource group keeps two publishes from pushing at the same time.

## GitLab CI/CD variables

| Name | Masked | Protected | Purpose |
| --- | --- | --- | --- |
| `ARTIFACTORY_USERNAME` | yes | when dev runs on a protected branch | Registry user |
| `ARTIFACTORY_PASSWORD` | yes | when dev runs on a protected branch | Registry password or token |
| `ARTIFACTORY_REGISTRY` | no | no | Defaults to `artifactory.tahaa.local` |
| `ARTIFACTORY_REPOSITORY` | no | no | Defaults to `tahaa-image-local` |
| `BUILD_TYPE` | no | no | `dev` or `release` |

Mask both registry variables. Protect them when development pipelines run on a protected branch such as `main`: a protected variable is not visible to an unprotected branch, so those pipelines cannot log in. A release still cannot be published from a variable alone. It also needs the protected Git tag. The scripts never print the password. `artifacts/build-metadata.json` records versions, commit, pipeline id, and image tag, and does not contain credentials.

## Changing versions

Edit `versions/RHEL9.env` and rename `src/wireshark-$WIRESHARK_VERSION` so the directory suffix matches the new `WIRESHARK_VERSION`. Commit and let the development pipeline run. The RPM filename and image tags follow that file.

## Troubleshooting

- `version configuration not found`: `versions/RHEL9.env` is not beside the scripts, at `/workspace/versions` (the Compose checkout mount), or at `/opt/wireshark-build/versions` in the compile image.
- `Wireshark source directory not found`: the tree name or the `CMakeLists.txt` version does not match `WIRESHARK_VERSION`.
- `Packet Penguin plugin directory is missing`: `--package` requires a CMake plugin under `src/plugins` or `plugins`.
- `include could not find requested file: WiresharkPlugin` or `Unknown CMake command "set_module_info"`: that `CMakeLists.txt` is an in-tree plugin and was configured on its own. Re-run `./src/scripts/compile-wireshark.sh` so it links the plugin into the Wireshark build before CMake runs.
- `Could NOT find Asciidoctor (missing: ASCIIDOCTOR_EXECUTABLE)`: Asciidoctor builds the user guide and man pages. The configure continues without it. The RPM does not need those docs.
- `Unknown CMake command "add_wireshark_epan_plugin_library"`: Wireshark 4.6.9 does not define that command. In the dissector `CMakeLists.txt`, replace `add_wireshark_epan_plugin_library(ospl)` with `add_wireshark_plugin_library(ospl epan)`. `src/plugins` is not part of this repository, so that edit is made in the plugin checkout.
- `ninja: error: dependency cycle: .../plugin.c -> .../plugin.c`: `register_plugin_files` was given `plugin.c`, which is the file Wireshark 4.6.9 generates. Pass `${DISSECTOR_SRC}` to that command, and keep `plugin.c` only in `PLUGIN_FILES`. Clean the CMake build directory and compile again.
- `libwireshark.so.19: cannot open shared object file`: the build-tree binary's RPATH is `$ORIGIN/../lib64` while the libraries are in `run/`. From a checkout whose scripts live in `/src/scripts`, the binary is `/src/build/rhel9/wireshark/run/tshark`. Re-run the compile script so it recreates `src/build/rhel9/wireshark/lib64`, or link the libraries yourself: `mkdir -p /src/build/rhel9/wireshark/lib64` and `ln -sfn "../run/<library>"` for each `lib*.so*` in `run/`. The version check also accepts `LD_LIBRARY_PATH` pointed at `run/`.
- `rpmbuild is not installed`: rebuild the compile image; `rpm-build` is installed by `dockerfile/Dockerfile.wireshark-ubi9-build`.
- `podman or docker is required`: the docker and publish jobs need a container engine on the runner.
- Registry login failed: check the masked variables, DNS for `artifactory.tahaa.local`, and the CA trust. Do not pass `--tls-verify=false`.
