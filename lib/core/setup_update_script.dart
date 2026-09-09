class SetupUpdatePlan {
  const SetupUpdatePlan({
    required this.processId,
    required this.installerPath,
    required this.installDirectory,
    required this.workDirectory,
    required this.version,
    this.uninstallRegistryKey =
        r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{E6E8B457-32B6-4B93-BB91-AB9242BF54E4}_is1',
  });

  final int processId;
  final String installerPath;
  final String installDirectory;
  final String workDirectory;
  final String version;
  final String uninstallRegistryKey;

  String get scriptPath => '$workDirectory\\install-setup-update-$version.ps1';
  String get resultPath => '$workDirectory\\update-result.json';
  String get logPath => '$workDirectory\\update-helper.log';

  String buildScript() {
    const template = r'''
param(
  [switch]$SkipRestart,
  [string]$TestInstallerScript = ''
)
$ErrorActionPreference = 'Stop'
$TargetPid = @@PID@@
$Installer = '@@INSTALLER@@'
$InstallDirectory = '@@INSTALL@@'
$WorkDirectory = '@@WORK@@'
$Version = '@@VERSION@@'
$ResultFile = '@@RESULT@@'
$LogFile = '@@LOG@@'
$UninstallKey = '@@UNINSTALL_KEY@@'
$Mutex = $null
$MutexOwned = $false

function Write-State([string]$State, [string]$Message = '') {
  $record = [ordered]@{
    state = $State
    version = $Version
    message = $Message
    updatedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    installDirectory = $InstallDirectory
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

function Normalize-Path([string]$Path) {
  return [IO.Path]::GetFullPath($Path).TrimEnd('\').ToLowerInvariant()
}

try {
  New-Item -ItemType Directory -Path $WorkDirectory -Force | Out-Null
  if (-not (Test-Path -LiteralPath $Installer -PathType Leaf)) {
    throw 'The verified setup file is missing'
  }
  $Mutex = [Threading.Mutex]::new($false, 'Local\niraN-Setup-Updater-v1')
  $MutexOwned = $Mutex.WaitOne(0)
  if (-not $MutexOwned) { throw 'Another niraN setup update is already running' }

  Write-State 'closingApp'
  Wait-ForProcessExit $TargetPid 60
  Start-Sleep -Milliseconds 250

  Write-State 'replacingFiles'
  if ($TestInstallerScript -ne '') {
    $Setup = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
      '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
      '-File', ('"{0}"' -f $TestInstallerScript),
      '-InstallDirectory', ('"{0}"' -f $InstallDirectory),
      '-Version', $Version
    ) -Wait -PassThru
  } else {
    $Arguments = '/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /DIR="' + $InstallDirectory + '"'
    $Setup = Start-Process -FilePath $Installer -ArgumentList $Arguments -Wait -PassThru
  }
  if ($Setup.ExitCode -ne 0) {
    throw "Setup exited with code $($Setup.ExitCode)"
  }

  $NewExecutable = Join-Path $InstallDirectory 'niraN.exe'
  if (-not (Test-Path -LiteralPath $NewExecutable -PathType Leaf)) {
    throw 'Updated niraN.exe is missing after setup'
  }
  if ($TestInstallerScript -eq '') {
    $ProductVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($NewExecutable).ProductVersion
    if ([string]::IsNullOrWhiteSpace($ProductVersion) -or -not $ProductVersion.StartsWith($Version)) {
      throw "Installed executable version is $ProductVersion instead of $Version"
    }
    $Metadata = Get-ItemProperty -LiteralPath $UninstallKey -ErrorAction Stop
    if ([string]$Metadata.DisplayVersion -ne $Version) {
      throw "Installed Apps version is $($Metadata.DisplayVersion) instead of $Version"
    }
    if ((Normalize-Path ([string]$Metadata.InstallLocation)) -ne (Normalize-Path $InstallDirectory)) {
      throw 'Setup changed the installation directory'
    }
  }

  Write-State 'restarting'
  if (-not $SkipRestart) {
    $Started = Start-Process -FilePath $NewExecutable -WorkingDirectory $InstallDirectory -PassThru
    Start-Sleep -Milliseconds 1200
    if ($Started.HasExited) { throw 'Updated niraN exited immediately' }
  }

  Write-State 'completed'
  Remove-Item -LiteralPath $Installer -Force -ErrorAction SilentlyContinue
} catch {
  $Failure = $_.Exception.Message
  Write-State 'failed' $Failure
  $OldExecutable = Join-Path $InstallDirectory 'niraN.exe'
  if (-not $SkipRestart -and (Test-Path -LiteralPath $OldExecutable)) {
    Start-Process -FilePath $OldExecutable -WorkingDirectory $InstallDirectory -ErrorAction SilentlyContinue | Out-Null
  }
  exit 1
} finally {
  if ($MutexOwned) { $Mutex.ReleaseMutex() }
  if ($null -ne $Mutex) { $Mutex.Dispose() }
}
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
''';
    return template
        .replaceAll('@@PID@@', '$processId')
        .replaceAll('@@INSTALLER@@', _ps(installerPath))
        .replaceAll('@@INSTALL@@', _ps(installDirectory))
        .replaceAll('@@WORK@@', _ps(workDirectory))
        .replaceAll('@@VERSION@@', _ps(version))
        .replaceAll('@@UNINSTALL_KEY@@', _ps(uninstallRegistryKey))
        .replaceAll('@@RESULT@@', _ps(resultPath))
        .replaceAll('@@LOG@@', _ps(logPath));
  }

  String _ps(String value) => value.replaceAll("'", "''");
}
