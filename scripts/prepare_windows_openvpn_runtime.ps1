param(
  [string]$Version = $(if ($env:SDWAN_OPENVPN_VERSION) { $env:SDWAN_OPENVPN_VERSION } else { "2.7.4-I001" }),
  [string]$Url = $(if ($env:SDWAN_OPENVPN_URL) { $env:SDWAN_OPENVPN_URL } else { "" }),
  [string]$SourceMsiPath = $(if ($env:SDWAN_OPENVPN_MSI_PATH) { $env:SDWAN_OPENVPN_MSI_PATH } else { "" })
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$target = Join-Path $repoRoot "windows\third_party\openvpn\windows-x64"
$expectedExe = Join-Path $target "bin\openvpn.exe"
$expectedMsi = Join-Path $target "installer\OpenVPN-$Version-amd64.msi"

if ((Test-Path $expectedExe) -and (Test-Path $expectedMsi)) {
  Write-Host "Bundled OpenVPN runtime already exists: $expectedExe"
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Url)) {
  $Url = "https://swupdate.openvpn.org/community/releases/OpenVPN-$Version-amd64.msi"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sdwan-openvpn-" + [System.Guid]::NewGuid().ToString("N"))
$msiPath = Join-Path $tempRoot "OpenVPN-$Version-amd64.msi"
$extractDir = Join-Path $tempRoot "extract"

New-Item -ItemType Directory -Force $tempRoot | Out-Null
New-Item -ItemType Directory -Force $extractDir | Out-Null

try {
  if ([string]::IsNullOrWhiteSpace($SourceMsiPath)) {
    Write-Host "Downloading OpenVPN runtime: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $msiPath
  } else {
    Write-Host "Using local OpenVPN MSI: $SourceMsiPath"
    Copy-Item -Path $SourceMsiPath -Destination $msiPath -Force
  }

  $signature = Get-AuthenticodeSignature $msiPath
  if ($signature.Status -ne "Valid") {
    throw "OpenVPN MSI signature is not valid: $($signature.Status)"
  }

  Write-Host "Extracting OpenVPN MSI"
  $process = Start-Process msiexec.exe `
    -ArgumentList @("/a", "`"$msiPath`"", "/qn", "TARGETDIR=`"$extractDir`"") `
    -Wait `
    -PassThru
  if ($process.ExitCode -ne 0) {
    throw "msiexec extraction failed with exit code $($process.ExitCode)"
  }

  $openVpnExe = Get-ChildItem -Path $extractDir -Filter openvpn.exe -Recurse |
    Where-Object { $_.FullName -match "\\bin\\openvpn\.exe$" } |
    Select-Object -First 1
  if (-not $openVpnExe) {
    throw "bin\openvpn.exe was not found in extracted OpenVPN MSI"
  }

  $binDir = Split-Path -Parent $openVpnExe.FullName
  $runtimeRoot = Split-Path -Parent $binDir
  if (Test-Path $target) {
    Remove-Item -Path $target -Recurse -Force
  }
  New-Item -ItemType Directory -Force $target | Out-Null
  New-Item -ItemType Directory -Force (Split-Path -Parent $expectedMsi) | Out-Null
  Copy-Item -Path (Join-Path $runtimeRoot "*") -Destination $target -Recurse -Force
  Copy-Item -Path $msiPath -Destination $expectedMsi -Force

  if (-not (Test-Path $expectedExe)) {
    throw "OpenVPN runtime copy failed: $expectedExe missing"
  }
  if (-not (Test-Path $expectedMsi)) {
    throw "OpenVPN installer copy failed: $expectedMsi missing"
  }
  Write-Host "Prepared bundled OpenVPN runtime at $target"
} finally {
  if (Test-Path $tempRoot) {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
