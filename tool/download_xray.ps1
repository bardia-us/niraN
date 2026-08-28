[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$version = 'v26.7.28'
$expectedSha256 = 'c7172078fca4711bcd92a4774dcd1822544579c58816197575c47533317fd8d1'
$downloadUrl = "https://github.com/XTLS/Xray-core/releases/download/$version/Xray-windows-64.zip"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $repositoryRoot 'windows\xray\bin'
$xrayPath = Join-Path $destination 'xray-v26.7.28.exe'

if (Test-Path -LiteralPath $xrayPath) {
  exit 0
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("niraN-xray-" + [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $temporaryRoot 'xray.zip'
$extractPath = Join-Path $temporaryRoot 'extract'

try {
  New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
  New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
  Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing
  $actualSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualSha256 -ne $expectedSha256) {
    throw "Xray checksum mismatch. Expected $expectedSha256 but received $actualSha256."
  }
  Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
  $downloadedXray = Join-Path $extractPath 'xray.exe'
  if (-not (Test-Path -LiteralPath $downloadedXray)) {
    throw 'The official Xray archive did not contain xray.exe.'
  }
  New-Item -ItemType Directory -Path $destination -Force | Out-Null
  Copy-Item -LiteralPath $downloadedXray -Destination $xrayPath -Force
  $license = Join-Path $extractPath 'LICENSE'
  if (Test-Path -LiteralPath $license) {
    Copy-Item -LiteralPath $license -Destination (Join-Path $destination 'LICENSE') -Force
  }
  Write-Host "Provisioned Xray Core $version."
}
finally {
  $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
  $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
      (Split-Path -Leaf $resolvedTemporaryRoot).StartsWith('niraN-xray-', [System.StringComparison]::Ordinal)) {
    Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
