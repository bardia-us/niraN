[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$version = '1.14.0'
$expectedSha256 = '3ffb56267da14e287be48bd10cf7e6505260125bad940b75101fbb4d5d58e5d6'
$downloadUrl = "https://github.com/SagerNet/sing-box/releases/download/v$version/sing-box-$version-windows-amd64.zip"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $repositoryRoot 'windows\sing-box\bin'
$singBoxPath = Join-Path $destination "sing-box-v$version.exe"
$cronetPath = Join-Path $destination 'libcronet.dll'

if ((Test-Path -LiteralPath $singBoxPath) -and (Test-Path -LiteralPath $cronetPath)) {
  exit 0
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("niraN-sing-box-" + [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $temporaryRoot 'sing-box.zip'
$extractPath = Join-Path $temporaryRoot 'extract'

try {
  New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
  New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
  Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing
  $actualSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualSha256 -ne $expectedSha256) {
    throw "sing-box checksum mismatch. Expected $expectedSha256 but received $actualSha256."
  }
  Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
  $releaseRoot = Join-Path $extractPath "sing-box-$version-windows-amd64"
  foreach ($file in @('sing-box.exe', 'libcronet.dll', 'LICENSE')) {
    if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot $file))) {
      throw "The official sing-box archive did not contain $file."
    }
  }
  New-Item -ItemType Directory -Path $destination -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $releaseRoot 'sing-box.exe') -Destination $singBoxPath -Force
  Copy-Item -LiteralPath (Join-Path $releaseRoot 'libcronet.dll') -Destination $cronetPath -Force
  Copy-Item -LiteralPath (Join-Path $releaseRoot 'LICENSE') -Destination (Join-Path $destination 'LICENSE') -Force
  Write-Host "Provisioned sing-box v$version."
}
finally {
  $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
  $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
      (Split-Path -Leaf $resolvedTemporaryRoot).StartsWith('niraN-sing-box-', [System.StringComparison]::Ordinal)) {
    Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
