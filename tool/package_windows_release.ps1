param(
  [string]$Version = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ReleaseDirectory = [IO.Path]::GetFullPath(
  (Join-Path $ProjectRoot 'build\windows\x64\runner\Release')
)
$DistDirectory = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'dist'))

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Pubspec = Get-Content -LiteralPath (Join-Path $ProjectRoot 'pubspec.yaml')
  $VersionLine = $Pubspec | Where-Object { $_ -match '^version:\s*([^+\s]+)' } | Select-Object -First 1
  if ($null -eq $VersionLine) { throw 'Could not read version from pubspec.yaml' }
  $Version = [regex]::Match($VersionLine, '^version:\s*([^+\s]+)').Groups[1].Value
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid release version' }
if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDirectory 'niraN.exe'))) {
  throw 'Windows Release build is missing. Run flutter build windows --release first.'
}

$RootFolderName = "niraN-$Version-windows-x64"
$StageDirectory = [IO.Path]::GetFullPath((Join-Path $DistDirectory $RootFolderName))
$ArchivePath = [IO.Path]::GetFullPath((Join-Path $DistDirectory "$RootFolderName.zip"))
if ([IO.Path]::GetDirectoryName($StageDirectory) -ne $DistDirectory -or
    [IO.Path]::GetDirectoryName($ArchivePath) -ne $DistDirectory) {
  throw 'Unsafe package output path'
}

New-Item -ItemType Directory -Path $DistDirectory -Force | Out-Null
if (Test-Path -LiteralPath $StageDirectory) {
  Remove-Item -LiteralPath $StageDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $ArchivePath) {
  Remove-Item -LiteralPath $ArchivePath -Force
}
New-Item -ItemType Directory -Path $StageDirectory -Force | Out-Null
Copy-Item -Path (Join-Path $ReleaseDirectory '*') -Destination $StageDirectory -Recurse -Force

[Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') | Out-Null
[IO.Compression.ZipFile]::CreateFromDirectory(
  $StageDirectory,
  $ArchivePath,
  [IO.Compression.CompressionLevel]::Optimal,
  $true
)
Remove-Item -LiteralPath $StageDirectory -Recurse -Force

$Hash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash
Write-Output "Archive: $ArchivePath"
Write-Output "SHA256: $Hash"
