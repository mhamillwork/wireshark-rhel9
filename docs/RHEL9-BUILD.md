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

The compile script looks for a directory named `wireshark-$WIRESHARK_VERSION` under `src/` or the repository root, then for an unversioned `wireshark/` directory whose `CMakeLists.txt` version matches. Packet Penguin plugins are CMake projects under `src/plugins/` or `plugins/`. A plugin may put the same version in a `PACKET_PENGUIN_VERSION` file; if that file exists and differs, the build stops.

This checkout stores upstream Wireshark in `wireshark/`. A GitLab checkout that uses `src/wireshark-$WIRESHARK_VERSION` and `src/plugins` is also accepted. There is no Packet Penguin source in this GitHub tree, so packaging fails here until those plugins are added.

A directory under the plugin root that has its own `CMakeLists.txt` is built out of tree after Wireshark is installed. C sources with no `CMakeLists.txt` are the in-tree dissectors: link them into the Wireshark tree and they are compiled with Wireshark, then shipped inside `libwireshark`. `--package` still requires one of those two layouts.

## Local compile

The script can be started from any directory.

```bash
./scripts/compile-wireshark.sh --help
./scripts/compile-wireshark.sh --rhel 9 --check
./scripts/compile-wireshark.sh --rhel 9 --clean --build --test
```

With no mode flags it builds and runs the version checks. The out-of-source build is `build/rhel9/wireshark/`. `tshark` is `build/rhel9/wireshark/run/tshark`.

RHEL 9 has Qt 5.15, so the script passes `-DUSE_qt6=OFF`. Ninja links with the install RPATH (`$ORIGIN/../lib64`). The script symlinks the libraries from `run/` into that directory. The version check also sets `LD_LIBRARY_PATH` to `run/`.

Build tools are gcc, cmake, and ninja, plus the libraries installed by the root `Dockerfile` from UBI 9 and Satellite (BaseOS, AppStream, and CodeReady Builder). Qt 6, libsmi, nghttp3, spandsp, iLBC, bcg729, and opencore-amr are not in RHEL 9 and stay off.

## RPM

The package name is `wireshark-ppv`. It installs under `/usr/local` and does not replace the RHEL `wireshark` package. `/usr/local/bin` is normally ahead of `/usr/bin`.

```bash
./scripts/compile-wireshark.sh --rhel 9 --package
```

Output:

```text
artifacts/rpms/rhel9/wireshark-ppv-4.6.9-1.ppv1.0.5.el9.x86_64.rpm
```

The architecture follows the build machine. Inspect it with:

```bash
rpm -qpi artifacts/rpms/rhel9/*.rpm
rpm -qp --requires artifacts/rpms/rhel9/*.rpm
rpm -qpl artifacts/rpms/rhel9/*.rpm
```

`rpmlint` runs when it is installed. Packaging errors fail the script. Two results are filtered in `src/rpmbuild/rpmlintrc`: `dir-or-file-in-usr-local`, because the package lives under `/usr/local` beside the distribution Wireshark, and `no-signature`, because signing uses a key that is not in this repository. `invalid-license` can appear as a warning: the spec uses the SPDX id `GPL-2.0-or-later`, which older rpmlint license lists do not know. Other rpmlint errors still fail the build. On a host without `rpmlint`, the script records that the metadata checks still ran.

`./scripts/test-rpm.sh` repeats the metadata checks. If podman or docker can see a local UBI 9 image, it also installs and removes the RPM in a container. Otherwise it says that installation test was not run.

## Runtime image

The root `Dockerfile` is the compile image. The image that is published is `dockerfile/RHEL-9/Dockerfile`. It installs only the RPM onto UBI 9.8. The compile image's `dnf` transaction is what reaches Satellite; the runtime install needs those same repositories so library dependencies resolve. Do not turn TLS verification off.

```bash
set -a
. ./versions/RHEL9.env
set +a
docker build -f dockerfile/RHEL-9/Dockerfile \
  --build-arg WIRESHARK_VERSION="$WIRESHARK_VERSION" \
  --build-arg PACKET_PENGUIN_VERSION="$PACKET_PENGUIN_VERSION" \
  --build-arg RHEL_VERSION="$RHEL_VERSION" \
  --build-arg BUILD_TYPE=dev \
  -t wireshark-ppv:candidate .
docker run --rm wireshark-ppv:candidate
```

`docker run` executes `/usr/local/bin/tshark -v`. The local tag is `wireshark-ppv:candidate` so this build does not replace the compile image `wireshark-ubi9:dev`.

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

Edit `versions/RHEL9.env`, commit, and let the development pipeline run. The source directory, RPM filename, and image tags follow that file. Put the new Wireshark tree at `src/wireshark-<version>` or replace `wireshark/` with a tree of that version.

## Troubleshooting

- `version configuration not found`: `versions/RHEL9.env` is not beside the scripts, at `/workspace/versions` (the Compose checkout mount), or at `/opt/wireshark-build/versions` in the compile image.
- `Wireshark source directory not found`: the tree name or the `CMakeLists.txt` version does not match `WIRESHARK_VERSION`.
- `Packet Penguin plugin directory is missing`: `--package` requires a CMake plugin under `src/plugins` or `plugins`.
- `libwireshark.so.19: cannot open shared object file`: the build-tree binary's RPATH is `$ORIGIN/../lib64` while the libraries are in `run/`. From a checkout whose scripts live in `/src/scripts`, the binary is `/src/build/rhel9/wireshark/run/tshark`. Re-run the compile script so it recreates `build/rhel9/wireshark/lib64`, or link the libraries yourself: `mkdir -p /src/build/rhel9/wireshark/lib64` and `ln -sfn "../run/<library>"` for each `lib*.so*` in `run/`. The version check also accepts `LD_LIBRARY_PATH` pointed at `run/`.
- `rpmbuild is not installed`: rebuild the compile image; `rpm-build` is in the root `Dockerfile`.
- `podman or docker is required`: the docker and publish jobs need a container engine on the runner.
- Registry login failed: check the masked variables, DNS for `artifactory.tahaa.local`, and the CA trust. Do not pass `--tls-verify=false`.
