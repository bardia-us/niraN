#ifndef AppVersion
  #define AppVersion "0.3.5"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef AppIdValue
  #define AppIdValue "{{E6E8B457-32B6-4B93-BB91-AB9242BF54E4}"
#endif
#ifndef AppNameValue
  #define AppNameValue "niraN"
#endif
#ifndef OutputBaseFilenameValue
  #define OutputBaseFilenameValue "niraN-v" + AppVersion + "-windows-x64-setup"
#endif

[Setup]
AppId={#AppIdValue}
AppName={#AppNameValue}
AppVersion={#AppVersion}
AppPublisher=bardia-us
AppPublisherURL=https://github.com/bardia-us/niraN
AppSupportURL=https://github.com/bardia-us/niraN/issues
DefaultDirName={localappdata}\Programs\niraN
DefaultGroupName=niraN
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/max
SolidCompression=yes
OutputDir=..\dist
OutputBaseFilename={#OutputBaseFilenameValue}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\niraN.exe
AppMutex=Local\niraN-bardia-us-v0
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
WizardStyle=modern

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "setup.marker"; DestDir: "{app}"; DestName: ".niran-setup-install"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\niraN"; Filename: "{app}\niraN.exe"
Name: "{autodesktop}\niraN"; Filename: "{app}\niraN.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\niraN.exe"; Description: "Launch niraN"; Flags: nowait postinstall skipifsilent

#ifndef SkipUninstallCleanup
[UninstallRun]
Filename: "{app}\niraN.exe"; Parameters: "--uninstall-cleanup"; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "niraNUninstallCleanup"
#endif
