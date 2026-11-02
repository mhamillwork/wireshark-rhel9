# Install the compiler, Qt, and NSIS used by the Windows 11 compile image.
# The Dockerfile runs this once. A later source change does not reinstall it.
# Requires PowerShell 5.1. The image build needs network access to Microsoft,
# Chocolatey, and download.qt.io.

[CmdletBinding()]
param(
    [string]$QtVersion = $env:QT_VERSION
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($env:OS -ne 'Windows_NT') {
    throw 'Windows build tools install on Windows. This host is not Windows.'
}
if ([string]::IsNullOrWhiteSpace($QtVersion)) {
    throw 'QT_VERSION is unset. The Dockerfile passes it from versions/WINDOWS11.env.'
}

function Update-ProcessPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

New-Item -ItemType Directory -Force -Path 'C:\Temp','C:\wireshark-libs','C:\Qt' | Out-Null
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force | Out-Null

Write-Output 'Installing Chocolatey'
Set-ExecutionPolicy Bypass -Scope Process -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-Expression ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
Update-ProcessPath

Write-Output 'Installing git, CMake, Python, win_flex_bison, and NSIS'
choco install -y git cmake python3 winflexbison3 nsis --no-progress
if ($LASTEXITCODE -ne 0) {
    throw "choco install failed with exit $LASTEXITCODE"
}
Update-ProcessPath
foreach ($tool in @('git', 'cmake')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool was not placed on PATH"
    }
}
$python = Get-Command python, python3 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $python) {
    throw 'python was not placed on PATH'
}
& git config --system core.longpaths true

$vs = 'C:\Temp\vs_buildtools.exe'
Write-Output 'Downloading Visual Studio 2022 Build Tools'
Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vs_buildtools.exe' -OutFile $vs
# VCTools is the compiler. Windows11SDK.26100 matches Windows 11 24H2.
# CMake is also installed by Chocolatey, so the image does not depend on the
# Visual Studio CMake component being the one on PATH.
$vsArgs = @(
    '--quiet', '--wait', '--norestart', '--nocache',
    '--installPath', 'C:\BuildTools',
    '--add', 'Microsoft.VisualStudio.Workload.VCTools',
    '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
    '--add', 'Microsoft.VisualStudio.Component.Windows11SDK.26100',
    '--add', 'Microsoft.VisualStudio.Component.VC.CMake.Project'
) -join ' '
Write-Output 'Installing Visual Studio 2022 Build Tools'
$vsProc = Start-Process -FilePath $vs -ArgumentList $vsArgs -Wait -PassThru
if ($vsProc.ExitCode -ne 0 -and $vsProc.ExitCode -ne 3010) {
    throw "vs_buildtools.exe failed with exit $($vsProc.ExitCode)"
}
Remove-Item -Force $vs

Update-ProcessPath
Write-Output "Installing Qt $QtVersion with aqt"
& $python.Source -m pip install --upgrade pip aqtinstall
if ($LASTEXITCODE -ne 0) {
    throw "pip install aqtinstall failed with exit $LASTEXITCODE"
}
Update-ProcessPath
& $python.Source -m aqt install-qt windows desktop $QtVersion win64_msvc2022_64 -m qt5compat qtmultimedia -O C:\Qt
if ($LASTEXITCODE -ne 0) {
    throw "aqt install-qt failed with exit $LASTEXITCODE"
}

$qtPrefix = Join-Path 'C:\Qt' (Join-Path $QtVersion 'msvc2022_64')
if (-not (Test-Path (Join-Path $qtPrefix 'bin'))) {
    throw "Qt was not installed at $qtPrefix"
}
[Environment]::SetEnvironmentVariable('WIRESHARK_QT6_PREFIX_PATH', $qtPrefix, 'Machine')
[Environment]::SetEnvironmentVariable('WIRESHARK_BASE_DIR', 'C:\wireshark-libs', 'Machine')
Set-Content -Path 'C:\wireshark-build-tools.txt' -Encoding ascii -Value @"
QT_VERSION=$QtVersion
WIRESHARK_QT6_PREFIX_PATH=$qtPrefix
WIRESHARK_BASE_DIR=C:\wireshark-libs
VCVARS64=C:\BuildTools\VC\Auxiliary\Build\vcvars64.bat
"@
Write-Output "Windows build tools installed. Qt prefix: $qtPrefix"
