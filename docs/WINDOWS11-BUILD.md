# Windows 11 build

Windows 11 is built on a Windows 11 workstation. GitLab CI is unchanged: the cluster has no Windows node, and `.gitlab-ci.yml` does not build these images or the installer.

The compile image is `dockerfile/Dockerfile.wireshark-win11-build`. The runtime image is `dockerfile/Dockerfile.wireshark-win11-runtime`. Versions are in `versions/WINDOWS11.env`. The installer is an NSIS executable, the same installer Wireshark builds for Windows, with the Packet Penguin version appended.

Docker has to be switched to Windows containers. A Linux Docker engine cannot build either file. The container OS build has to match the host. `ltsc2025` matches Windows 11 24H2 (build 26100). Check the host with `winver`. If the build number is not 26100, pass a matching `--build-arg WINDOWS_IMAGE` on both Dockerfiles. A mismatch fails at `docker build` before any package installs.

The first compile-image build downloads Visual Studio 2022 Build Tools, the Windows 11 SDK 26100, Qt from `versions/WINDOWS11.env`, CMake, Git, Python, win_flex_bison, and NSIS. That needs network access to Microsoft, Chocolatey, and `download.qt.io`. The Wireshark configure step later downloads libraries from `https://dev-libs.wireshark.org/windows/packages` into `C:\wireshark-libs`.

## Documents Sandbox

The RHEL Compose file mounts `${HOME}/sandbox/wireshark-packet-penguin`. On Windows 11 the same checkout lives in the user Documents Sandbox:

```text
%USERPROFILE%\Documents\Sandbox\wireshark-packet-penguin
```

Clone or copy this repository there. `docker-compose.windows11.yml` mounts that directory:

- `%USERPROFILE%\Documents\Sandbox\wireshark-packet-penguin` at `C:\workspace`, read-only, so the container can read `versions\WINDOWS11.env`
- `...\wireshark-packet-penguin\src` at `C:\src`, read-write, so the build writes `src\build\windows11` back to Documents
- `%USERPROFILE%\Documents\Sandbox` at `C:\sandbox`, for capture files

`SANDBOX_DIR` overrides the Documents Sandbox directory when the checkout is somewhere else. The three mounts stay the same shape.

## Compile image

From the checkout:

```powershell
docker build -f dockerfile/Dockerfile.wireshark-win11-build -t wireshark-win11:dev .
```

`src/build` is left out of the image by `.dockerignore`. A source change does not by itself require a new image: Compose compiles the mounted tree with the compiler already in the image. Rebuild the image when the Dockerfile or the Qt version changes.

## Compose

Run Compose from the checkout in Documents Sandbox, with Windows containers selected.

```powershell
docker compose -f docker-compose.windows11.yml up -d
docker compose -f docker-compose.windows11.yml exec wireshark-compile powershell -File C:\src\scripts\build-windows-installer.ps1 -Build
docker compose -f docker-compose.windows11.yml exec wireshark-compile powershell -File C:\src\scripts\build-windows-installer.ps1 -Test
```

`-Build` configures with Visual Studio 17 2022 for x64, compiles `RelWithDebInfo`, and links Packet Penguin plugins that use `include(WiresharkPlugin)`. `-Test` runs `tshark.exe -v` from `src\build\windows11\wireshark\run\RelWithDebInfo`. With no switches, the script does both.

`-Clean` deletes that CMake build directory. It leaves `src\artifacts`.

## Installer

The installer target is Wireshark's NSIS target `wireshark_nsis`. CMake downloads Npcap and USBPcap metadata while it prepares that package. The produced executable is copied to:

```text
src\artifacts\installers\windows11\wireshark-<version>-<release>.ppv<packet-penguin>.win11.x64.exe
```

With the versions in `versions/WINDOWS11.env` today, that file is `src\artifacts\installers\windows11\wireshark-4.6.9-1.ppv1.0.5.win11.x64.exe`.

```powershell
docker compose -f docker-compose.windows11.yml exec wireshark-compile powershell -File C:\src\scripts\build-windows-installer.ps1 -Installer
```

Install it on the Windows 11 desktop by running that executable. The desktop install is the one that can offer Npcap and capture on the host interfaces. The container install is silent and does not load that driver.

## Runtime image

Build the runtime image after the installer exists. It installs that executable to `C:\Wireshark` and starts `Wireshark.exe`.

```powershell
docker build -f dockerfile/Dockerfile.wireshark-win11-runtime -t wireshark-win11:runtime .
```

Open the GUI with the sandbox mounted. Process isolation is required for the window to show on the host session, and the host build has to match the image.

```powershell
docker compose -f docker-compose.windows11.yml --profile runtime up wireshark
```

A check with no window overrides the command:

```powershell
docker run --rm wireshark-win11:runtime C:\Wireshark\tshark.exe -v
```

Capture files placed in `%USERPROFILE%\Documents\Sandbox` are visible in the container at `C:\sandbox`.
