# Install the NSIS executable into the Windows 11 runtime image.
# The Dockerfile copies one installer to C:\installer before it runs this.
# /S is the silent NSIS switch. /D= sets the directory and has to be last.
# Npcap is a host kernel driver. The silent install does not start it.
# Run the same executable on the Windows 11 desktop when the GUI must capture.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($env:OS -ne 'Windows_NT') {
    throw 'The Windows 11 runtime install runs on Windows. This host is not Windows.'
}

$exe = @(Get-ChildItem -Path 'C:\installer' -Filter '*.exe' -File)
if ($exe.Count -ne 1) {
    throw "expected one installer in C:\installer, found $($exe.Count)"
}

$proc = Start-Process -FilePath $exe[0].FullName -ArgumentList '/S /D=C:\Wireshark' -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "installer exit $($proc.ExitCode)"
}
if (-not (Test-Path 'C:\Wireshark\Wireshark.exe')) {
    throw 'Wireshark.exe was not installed at C:\Wireshark\Wireshark.exe'
}
if (-not (Test-Path 'C:\Wireshark\tshark.exe')) {
    throw 'tshark.exe was not installed at C:\Wireshark\tshark.exe'
}
Write-Output 'Installed C:\Wireshark\Wireshark.exe'
