param(
  [string]$Destination = (Join-Path $PSScriptRoot '..\windows\xray\bin')
)

$ErrorActionPreference = 'Stop'
$version = '0.14.1'
$expectedSha256 = '07C256185D6EE3652E09FA55C0B673E2624B565E02C4B9091C79CA7D2F24EF51'
$archive = Join-Path $env:TEMP "wintun-$version.zip"
$extract = Join-Path $env:TEMP "niran-wintun-$version"

Invoke-WebRequest -Uri "https://www.wintun.net/builds/wintun-$version.zip" -OutFile $archive
$actualSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
if ($actualSha256 -ne $expectedSha256) {
  throw "Wintun checksum mismatch. Expected $expectedSha256, got $actualSha256."
}

if (Test-Path -LiteralPath $extract) {
  Remove-Item -LiteralPath $extract -Recurse -Force
}
Expand-Archive -LiteralPath $archive -DestinationPath $extract
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $extract 'wintun\bin\amd64\wintun.dll') `
  -Destination (Join-Path $Destination 'wintun.dll') -Force
Copy-Item -LiteralPath (Join-Path $extract 'wintun\LICENSE.txt') `
  -Destination (Join-Path $Destination 'WINTUN_LICENSE.txt') -Force

Write-Host "Provisioned Wintun $version (amd64)."
