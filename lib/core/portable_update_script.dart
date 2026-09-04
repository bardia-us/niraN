import 'package:flutter/foundation.dart';

@immutable
class PortableUpdatePlan {
  const PortableUpdatePlan({
    required this.processId,
    required this.archivePath,
    required this.installDirectory,
    required this.workDirectory,
    required this.version,
  });

  final int processId;
  final String archivePath;
  final String installDirectory;
  final String workDirectory;
  final String version;

  String get targetFolderName => 'niraN-$version-windows-x64';
  String get scriptPath => '$workDirectory\\install-update-$version.ps1';
  String get resultPath => '$workDirectory\\update-result.json';
  String get logPath => '$workDirectory\\update-helper.log';
  String get stagingPath => '$workDirectory\\staging-$version';
  String get backupPath => '$workDirectory\\backup-$version';

  String buildScript() {
    const template = r'''
param(
  [switch]$SkipRestart,
  [switch]$SimulateRenameFailure,
  [int]$HoldMutexMilliseconds = 0
)
$ErrorActionPreference = 'Stop'
$TargetPid = @@PID@@
$Archive = '@@ARCHIVE@@'
$InstallDirectory = '@@INSTALL@@'
$WorkDirectory = '@@WORK@@'
$Version = '@@VERSION@@'
$TargetFolderName = '@@TARGET_FOLDER@@'
$ResultFile = '@@RESULT@@'
$LogFile = '@@LOG@@'
$Staging = '@@STAGING@@'
$Backup = '@@BACKUP@@'
$ActiveFolder = $InstallDirectory
$PayloadItems = @()
$Mutex = $null
$MutexOwned = $false
[Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') | Out-Null

function Write-State([string]$State, [string]$Message = '') {
  $record = [ordered]@{
    state = $State
    version = $Version
    message = $Message
    updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    installDirectory = $ActiveFolder
  }
  $temporary = "$ResultFile.tmp"
  [IO.File]::WriteAllText($temporary, ($record | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $ResultFile -Force
  Add-Content -LiteralPath $LogFile -Value ("{0:o} {1} {2}" -f [DateTime]::UtcNow, $State, $Message)
}

function Wait-ForProcessExit([int]$ProcessId, [int]$TimeoutSeconds) {
  if ($ProcessId -le 0) { return }
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
    if ([DateTime]::UtcNow -ge $deadline) {
      throw "niraN did not exit within $TimeoutSeconds seconds"
    }
    Start-Sleep -Milliseconds 150
  }
}

function Restore-Backup {
  if (-not (Test-Path -LiteralPath $Backup)) { return }
  foreach ($item in $PayloadItems) {
    $destination = Join-Path $ActiveFolder $item.Name
    if (Test-Path -LiteralPath $destination) {
      Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  Get-ChildItem -LiteralPath $Backup -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $ActiveFolder -Recurse -Force
  }
}

try {
  New-Item -ItemType Directory -Path $WorkDirectory -Force | Out-Null
  $Mutex = [Threading.Mutex]::new($false, 'Local\niraN-Portable-Updater-v1')
  $MutexOwned = $Mutex.WaitOne(0)
  if (-not $MutexOwned) { throw 'Another niraN updater is already running' }
  if ($HoldMutexMilliseconds -gt 0) { Start-Sleep -Milliseconds $HoldMutexMilliseconds }

  Write-State 'closingApp'
  Wait-ForProcessExit $TargetPid 60
  Start-Sleep -Milliseconds 250

  Write-State 'extracting'
  if (Test-Path -LiteralPath $Staging) {
    Remove-Item -LiteralPath $Staging -Recurse -Force
  }
  New-Item -ItemType Directory -Path $Staging -Force | Out-Null
  [IO.Compression.ZipFile]::ExtractToDirectory($Archive, $Staging)
  $candidates = @(Get-ChildItem -LiteralPath $Staging -Filter 'niraN.exe' -File -Recurse)
  if ($candidates.Count -ne 1) {
    throw 'The update archive must contain exactly one niraN.exe'
  }
  $PayloadRoot = $candidates[0].Directory.FullName
  $PayloadItems = @(Get-ChildItem -LiteralPath $PayloadRoot -Force)
  if ($PayloadItems.Count -eq 0) { throw 'The update payload is empty' }

  Write-State 'replacingFiles'
  if (Test-Path -LiteralPath $Backup) {
    Remove-Item -LiteralPath $Backup -Recurse -Force
  }
  New-Item -ItemType Directory -Path $Backup -Force | Out-Null
  foreach ($item in $PayloadItems) {
    $existing = Join-Path $InstallDirectory $item.Name
    if (Test-Path -LiteralPath $existing) {
      Copy-Item -LiteralPath $existing -Destination $Backup -Recurse -Force
    }
  }
  foreach ($item in $PayloadItems) {
    Copy-Item -LiteralPath $item.FullName -Destination $InstallDirectory -Recurse -Force
  }

  Write-State 'renamingFolder'
  $CurrentFolder = Get-Item -LiteralPath $InstallDirectory
  if ($CurrentFolder.Name -match '^niraN-(?:v)?\d+\.\d+\.\d+-windows-x64$' -and
      $CurrentFolder.Name -ne $TargetFolderName) {
    $TargetFolder = Join-Path $CurrentFolder.Parent.FullName $TargetFolderName
    if (-not (Test-Path -LiteralPath $TargetFolder)) {
      try {
        if ($SimulateRenameFailure) { throw 'Simulated folder rename failure' }
        Rename-Item -LiteralPath $InstallDirectory -NewName $TargetFolderName -ErrorAction Stop
        $ActiveFolder = $TargetFolder
      } catch {
        Add-Content -LiteralPath $LogFile -Value ("{0:o} renameFallback {1}" -f [DateTime]::UtcNow, $_.Exception.Message)
        $ActiveFolder = $InstallDirectory
      }
    }
  }

  $NewExecutable = Join-Path $ActiveFolder 'niraN.exe'
  if (-not (Test-Path -LiteralPath $NewExecutable)) {
    throw 'Updated niraN.exe is missing after replacement'
  }

  $RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  $AutoStart = Get-ItemProperty -Path $RunKey -Name 'niraN' -ErrorAction SilentlyContinue
  if ($null -ne $AutoStart) {
    Set-ItemProperty -Path $RunKey -Name 'niraN' -Value ('"{0}"' -f $NewExecutable)
  }

  Write-State 'restarting'
  if (-not $SkipRestart) {
    $Started = Start-Process -FilePath $NewExecutable -WorkingDirectory $ActiveFolder -PassThru
    Start-Sleep -Milliseconds 1200
    if ($Started.HasExited) { throw 'Updated niraN exited immediately' }
  }

  Write-State 'completed'
  Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Backup -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
} catch {
  $Failure = $_.Exception.Message
  try { Restore-Backup } catch {
    $Failure = "$Failure; rollback failed: $($_.Exception.Message)"
  }
  Write-State 'failed' $Failure
  $OldExecutable = Join-Path $ActiveFolder 'niraN.exe'
  if (-not $SkipRestart -and (Test-Path -LiteralPath $OldExecutable)) {
    Start-Process -FilePath $OldExecutable -WorkingDirectory $ActiveFolder -ErrorAction SilentlyContinue | Out-Null
  }
  Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
} finally {
  if ($MutexOwned) { $Mutex.ReleaseMutex() }
  if ($null -ne $Mutex) { $Mutex.Dispose() }
}
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
''';
    return template
        .replaceAll('@@PID@@', '$processId')
        .replaceAll('@@ARCHIVE@@', _ps(archivePath))
        .replaceAll('@@INSTALL@@', _ps(installDirectory))
        .replaceAll('@@WORK@@', _ps(workDirectory))
        .replaceAll('@@VERSION@@', _ps(version))
        .replaceAll('@@TARGET_FOLDER@@', _ps(targetFolderName))
        .replaceAll('@@RESULT@@', _ps(resultPath))
        .replaceAll('@@LOG@@', _ps(logPath))
        .replaceAll('@@STAGING@@', _ps(stagingPath))
        .replaceAll('@@BACKUP@@', _ps(backupPath));
  }

  String _ps(String value) => value.replaceAll("'", "''");
}
