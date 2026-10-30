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

The tests stay in `tests/` at the checkout root. The compile image copies `src/` and does not include that directory. It also leaves out `src/build`, which the workstation `src` mount supplies. `src/artifacts` stays in the Docker context so the runtime image can copy the RPM. GitLab runs `./src/scripts/validate-repo.sh`, which calls the tests from the checkout.

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

The package name is `wireshark`. The release is `1.ppv1.0.5.el9`. It installs under `/usr/local`. `/usr/local/bin` is normally ahead of `/usr/bin`. Every file is owned by root. Programs are mode `0755` and other files are mode `0644`, so any user can run Wireshark. `dumpcap` also carries `cap_net_raw` and `cap_net_admin`, so a live capture does not require a root shell.

`--package` fills `src/build/rhel9/staging` by installing the build with `DESTDIR`. `rpmbuild` copies that directory into the RPM. Satellite is the source of the RHEL packages `dnf` pulls while the images are built. This repository publishes the runtime image to Artifactory.

```bash
./src/scripts/compile-wireshark.sh --rhel 9 --package
```

Output:

```text
src/artifacts/rpms/rhel9/wireshark-4.6.9-1.ppv1.0.5.el9.x86_64.rpm
```

The architecture follows the build machine. Inspect it with:

```bash
rpm -qpi src/artifacts/rpms/rhel9/*.rpm
rpm -qp --requires src/artifacts/rpms/rhel9/*.rpm
rpm -qpl src/artifacts/rpms/rhel9/*.rpm
```

`rpmlint` runs when it is installed. Packaging errors fail the script. Two results are filtered in `src/rpmbuild/rpmlintrc`: `dir-or-file-in-usr-local`, because the package lives under `/usr/local` beside the distribution Wireshark, and `no-signature`, because signing uses a key that is not in this repository. `invalid-license` can appear as a warning: the spec uses the SPDX id `GPL-2.0-or-later`, which older rpmlint license lists do not know. Other rpmlint errors still fail the build. On a host without `rpmlint`, the script records that the metadata checks still ran.

`./src/scripts/test-rpm.sh` repeats the metadata checks. If docker can see the local bootstrap image, it also installs and removes the RPM in a container. Otherwise it says that installation test was not run.

## Images

The compile image and the runtime image are separate Dockerfiles. They share the bootstrap `artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap:9.8`, which already has the isolated-network certificates and repositories. They do not inherit each other: the published image does not contain the compiler. Do not turn TLS verification off.

`dockerfile/Dockerfile.ubi9-tahaa-bootstrap-docker` is the GitLab job image and the in-cluster engine image. It starts FROM `artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap-docker:9.8`. That image is the bootstrap plus the yum repo file for the Docker RPMs in Artifactory. Satellite does not publish those packages yet. The Dockerfile installs `docker-ce`, `docker-ce-cli`, `containerd.io`, git, and the archive tools the runner uses, then pushes that same tag. Build it on a machine whose `docker version` shows a Server section. A failure from `fuse-overlayfs` while mounting `/var/lib/containers/storage` means the `docker` command on that machine is not Docker Engine. If `dnf` reports `No match for argument` for `docker-ce` or `containerd.io`, the base image is missing that Artifactory repo file. The distro package named `docker` is not a substitute. The pipeline does not build this image. Rebuild and push it before applying the engine manifest. The pod exits at startup when that tag does not contain `dockerd`.

```bash
docker build \
  --add-host satellite9b.hsv.local:10.10.106.59 \
  -f dockerfile/Dockerfile.ubi9-tahaa-bootstrap-docker \
  -t artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap-docker:9.8 .
docker push artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap-docker:9.8
```

Apply `k8s/wireshark-docker.yaml` after that push. The claim, Deployment, and Service set `namespace: gitlab`, which is where the runner starts job pods. Pass `-n gitlab` as well. The kube context is `default`, and an apply without that flag has been creating the pod in `default`. The first command deletes a pod left there. The pipeline does not apply the file.

```bash
kubectl -n default delete deployment,service,pvc wireshark-docker --ignore-not-found
kubectl apply -f k8s/wireshark-docker.yaml -n gitlab
kubectl -n gitlab rollout status deployment/wireshark-docker
```

The Deployment is privileged. Its command enables the cgroup v2 controllers, checks that the volume can mount overlay, and starts `dockerd --host=tcp://0.0.0.0:2375 --iptables=false --ip6tables=false`. It does not create the DOCKER nat chain. When the image contains `/etc/docker/tls`, it also passes `--tlsverify`. IPv6 iptables stay off. Image builds and the remote compile container use the pod network, so `dnf` still reaches Satellite. The volume has to be ext4 or xfs. `/var/lib/docker` is a 100Gi volume, so `wireshark-ubi9:dev` is still there for the next job. The claim is read-write once, so the Deployment strategy is Recreate. The Service name is `wireshark-docker`, ClusterIP port 2375. Do not publish that Service outside the cluster. GitLab sets `DOCKER_HOST=tcp://wireshark-docker:2375`. It does not set a TLS verify flag or a certificate path, because this engine answers HTTP. A certificate path makes the client post to `https://wireshark-docker:2375` and fail with `server gave HTTP response to HTTPS client`. BuildKit stays on. Setting `DOCKER_BUILDKIT=0` selects the legacy builder, which the client warns will be removed. That short name resolves for job pods in `gitlab`. The pod maps `satellite9b.hsv.local` to `10.10.106.59`. Image builds still pass `--add-host`, because a container started by `dockerd` does not inherit the pod hosts file. A shell runner that already has a local engine overrides `DOCKER_HOST` to `unix:///var/run/docker.sock`.

`src/scripts/run-compile-image.sh` bind-mounts the checkout when `DOCKER_HOST` is a local socket. A `tcp://` daemon resolves that path on the engine pod, so the script copies the checkout to `/workspace` on a Docker volume named `wireshark-<pipeline id>`. The Wireshark build stays on that volume for the test and RPM jobs. The script can copy `src/artifacts` and `src/build/rhel9/logs` back to the runner. It does not copy `src/build/rhel9/wireshark/run/`. The pipeline does not upload GitLab artifacts. The runner posts those archives to the webservice on port 8080, and that service returns 400 for every upload. Workhorse on port 8181 is the service that accepts them. Validate does not create those directories. The docker job copies the RPM off the volume before `docker build`. The runtime image stays on the same daemon, so the docker job does not `docker save` it for the publish job. A later pipeline removes volumes left by finished pipelines, and the cleanup job removes this pipeline's volume. `docker build` sends its context from the job, so the compile and runtime image builds do not need that copy. BuildKit stays enabled.

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

`BUILD_TYPE` defaults to `dev`. A manual pipeline can select `dev` or `release`. Selecting `release` on an ordinary branch does not publish.

Stages, in order: image, validate, compile, test, rpm, package-test, docker, publish. Publish does not run unless the earlier jobs passed. The rpm job still builds the RPM for the runtime image on a dev pipeline. The RPM is uploaded only when the pipeline is a release.

Image names and the RPM filename come from `versions/RHEL9.env`:

```text
<WIRESHARK_VERSION>-ppv<PACKET_PENGUIN_VERSION>-rhel<RHEL_VERSION>
wireshark-<WIRESHARK_VERSION>-<RPM_PACKAGE_RELEASE>.ppv<PACKET_PENGUIN_VERSION>.el<RHEL_VERSION>.<arch>.rpm
```

With the versions in that file today, a release publishes:

```text
oci://artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9
oci://artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9-build
https://artifactory.tahaa.local/artifactory/tahaa-rpm-local/wireshark-4.6.9-1.ppv1.0.5.el9.<arch>.rpm
```

Docker pushes the same image names without the `oci://` scheme. The first image is the runtime image. The second is the compile image built by the `compile-image` job. The RPM goes to the `tahaa-rpm-local` repository.

Development tags, for the runtime image only:

```text
artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9-dev-mhamill
artifactory.tahaa.local/tahaa-image-local/wireshark:4.6.9-ppv1.0.5-rhel9-dev-mhamill-a1b2c3d4
```

The username comes from `GITLAB_USER_LOGIN` and is sanitized. The tag with the short commit SHA is the immutable one. The username tag moves. Those tags do not replace the release runtime tag or the `-build` tag.

A release is published only when all of these are true:

- `BUILD_TYPE=release`
- the Git ref is protected (`CI_COMMIT_REF_PROTECTED=true`)
- the pipeline is the Git tag `<WIRESHARK_VERSION>-ppv<PACKET_PENGUIN_VERSION>-rhel<RHEL_VERSION>`

Setting `BUILD_TYPE=release` on an ordinary branch does not publish. If a release image tag or the RPM is already in Artifactory, the push stops. Prefer an immutable tag policy in Artifactory as well.

The `compile-image` job runs `docker build` on `dockerfile/Dockerfile.wireshark-ubi9-build` and tags it `wireshark-ubi9:dev`. `--add-host satellite9b.hsv.local:10.10.106.59` lets that build reach Satellite. GitLab job containers use `artifactory.tahaa.local/tahaa-image-local/ubi9/ubi9-tahaa-bootstrap-docker:9.8`, so the runner pulls that image from Artifactory instead of pulling the local `wireshark-ubi9:dev` tag. The compile and runtime images still build FROM `ubi9-tahaa-bootstrap:9.8`. Validate runs `./src/scripts/validate-repo.sh` in the job container, on this checkout. The compile image copies only `src/` and `versions/`, so it does not contain `dockerfile/` or `tests/`. Compile, test, rpm, and package-test run inside the tag through `src/scripts/run-compile-image.sh`. The pipeline does not set `pull_policy`: this runner's `allowed_pull_policies` list is empty, and a job-level policy is rejected. Those jobs, and a release publish of the compile image, have to use the same `DOCKER_HOST`. On Kubernetes that is the `wireshark-docker` Service from `k8s/wireshark-docker.yaml`, applied with `-n gitlab`. The client is in the job image. It uses plain HTTP. `DOCKER_TLS_VERIFY` or `DOCKER_CERT_PATH` makes that client use HTTPS against this engine. BuildKit stays on. The engine pod has to reach Satellite while an image builds, and it has to reach Artifactory when a job pushes. The runner must trust the Artifactory certificate. Do not disable TLS verification for the registry. The rpm job compiles again: the compile job keeps `run/` and the logs, and the package step needs a fresh CMake build in that job.

Merge request pipelines run the checks and do not publish. A branch pipeline publishes the development tags. Release publishing is a separate manual pipeline on the protected Git tag, and a resource group keeps two publishes from pushing at the same time. The steps are in `docs/RELEASE.md`.

## GitLab CI/CD variables

| Name | Masked | Protected | Purpose |
| --- | --- | --- | --- |
| `ARTIFACTORY_USERNAME` | yes | when dev runs on a protected branch | Registry user |
| `ARTIFACTORY_PASSWORD` | yes | when dev runs on a protected branch | Registry password or token |
| `ARTIFACTORY_REGISTRY` | no | no | Defaults to `artifactory.tahaa.local` |
| `ARTIFACTORY_REPOSITORY` | no | no | Defaults to `tahaa-image-local` |
| `ARTIFACTORY_RPM_REPOSITORY` | no | no | Defaults to `tahaa-rpm-local`. Used when `BUILD_TYPE=release` |
| `BUILD_TYPE` | no | no | Defaults to `dev`. `release` publishes the release images and the RPM |
| `DOCKER_HOST` | no | no | Set in `.gitlab-ci.yml` to `tcp://wireshark-docker:2375`. A shell runner with a local engine overrides this to `unix:///var/run/docker.sock` |

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
- `docker is required`: the job image is missing the client, or `PATH` does not include it. The engine is the `wireshark-docker` Service, not a socket on the node.
- `400 Bad Request` while uploading artifacts, then `invalid argument`: the job script succeeded. The POST URL is the webservice, usually `http://gitlab-webservice-default:8080/api/v4/jobs/<id>/artifacts`. That port does not accept artifact uploads. Workhorse does, on port 8181. Point the runner `gitlabUrl` at port 8181. This pipeline no longer uploads artifacts, so the job can finish before that runner change.
- `compile image wireshark-ubi9:dev is not on this Docker daemon`: `compile-image` did not run against this `DOCKER_HOST`, or the engine pod was replaced without its volume.
- connection refused for `wireshark-docker:2375`: apply `k8s/wireshark-docker.yaml -n gitlab` and wait until the pod is Ready in `gitlab`. That namespace has to allow a privileged pod. `kubectl -n gitlab logs deployment/wireshark-docker` shows why it is not Ready.
- `dockerd is not in this image`: the pushed tag is still the client-only image. Rebuild and push `dockerfile/Dockerfile.ubi9-tahaa-bootstrap-docker`, then delete the pod so `imagePullPolicy: Always` pulls the new tag.
- `This volume cannot mount overlay`: the claim is on NFS or another filesystem that cannot host overlay2. Use a storage class that provides ext4 or xfs.
- `failed to create NAT chain DOCKER` or `Perhaps iptables or your kernel needs to be upgraded`: the running command still lets dockerd create that chain. Apply `k8s/wireshark-docker.yaml` with `-n gitlab`. The first log line from the new command is `Starting dockerd with --iptables=false`. A log that says `using iptables-nft` or `using iptables-legacy` is the previous command. Delete the deployment in `default` so that copy is not the one restarting.
- `server gave HTTP response to HTTPS client`: the job is posting to `https://wireshark-docker:2375` while dockerd is speaking HTTP. Remove `DOCKER_TLS_VERIFY` and `DOCKER_CERT_PATH` from the job. Leave BuildKit enabled. `DOCKER_BUILDKIT=0` is the legacy-builder warning.
- the engine pod is in `default`: delete `deployment`, `service`, and `pvc` `wireshark-docker` from `default`, then apply with `-n gitlab`. A volume in `default` does not move to `gitlab`.
- `job-image: Satellite did not install docker-ce, docker-ce-cli, and containerd.io`: the base image is missing the Artifactory yum repo for those packages, or that repo is disabled. The script also enables CodeReady Builder and any repo id containing `docker`. The distro package named `docker` is not a substitute. A log that still quotes `printf 'assumeyes=1` is the previous Dockerfile; pull and rebuild.
- `failed to solve` and the command is `bash /tmp/install-job-image-packages.sh`: read the last `job-image:` line. That line is the failure. Lines above it are the `dnf` output.
- Registry login failed: check the masked variables, DNS for `artifactory.tahaa.local`, and the CA trust. Do not pass `--tls-verify=false`.
