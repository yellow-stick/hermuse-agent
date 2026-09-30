; Hermuse Agent per-user installer (Inno Setup 6). Compiled by
; build-release.ps1, which passes every define below:
;   AppVersion           0.1.0 / 0.1.0-rc.1 (pubspec without build number)
;   FileVersion          0.1.0.1 (numeric, Setup.exe resources)
;   BundleDir            the verified Flutter bundle (+ cliproxy.exe, CRT, notices)
;   IconFile             apps/hermuse_app/windows/runner/resources/app_icon.ico
;   OutputDir, OutputBaseFilename
;   Sign                 (optional) sign Setup.exe and the uninstaller through
;                        the `hermuse` sign tool given to ISCC with /Shermuse=...
;
; Installs for the current user only, without elevation, to
; %LOCALAPPDATA%\Programs\Hermuse Agent. Uninstalling removes the installed
; files and shortcuts only: the app data (%APPDATA%\Yellow Stick\Hermuse
; Agent, secrets included), HERMES_HOME and anything Hermes installed stay.

#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef FileVersion
  #error FileVersion is required
#endif
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef IconFile
  #error IconFile is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef OutputBaseFilename
  #error OutputBaseFilename is required
#endif

[Setup]
; Never change the AppId: it keys upgrades and the uninstall entry.
AppId={{623CBA2D-B2D8-40B4-B0A3-334510D03899}
AppName=Hermuse Agent
AppVersion={#AppVersion}
AppVerName=Hermuse Agent {#AppVersion}
AppPublisher=Yellow Stick
AppPublisherURL=https://yellow-stick.com
AppSupportURL=https://github.com/yellow-stick/hermuse-agent
AppUpdatesURL=https://github.com/yellow-stick/hermuse-agent/releases
AppContact=contact@yellow-stick.com
AppCopyright=Copyright (C) 2026 Yellow Stick
VersionInfoVersion={#FileVersion}
VersionInfoCompany=Yellow Stick
VersionInfoDescription=Hermuse Agent Setup
VersionInfoProductName=Hermuse Agent
VersionInfoProductTextVersion={#AppVersion}
VersionInfoCopyright=Copyright (C) 2026 Yellow Stick
; Per-user only: no elevation, no /ALLUSERS override.
PrivilegesRequired=lowest
DefaultDirName={autopf}\Hermuse Agent
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
WizardStyle=modern
SetupIconFile={#IconFile}
UninstallDisplayName=Hermuse Agent
UninstallDisplayIcon={app}\hermuse_app.exe
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
Compression=lzma2/max
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
#ifdef Sign
SignTool=hermuse
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; The previous version's Flutter assets: the bundle replaces them whole.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Hermuse Agent"; Filename: "{app}\hermuse_app.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Hermuse Agent"; Filename: "{app}\hermuse_app.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\hermuse_app.exe"; Description: "{cm:LaunchProgram,Hermuse Agent}"; Flags: nowait postinstall skipifsilent
