#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BuildRoot
  #error BuildRoot is required
#endif
#ifndef OutputRoot
  #error OutputRoot is required
#endif

[Setup]
AppId={{A2D61CD6-C577-4A60-BF57-B43CC1EC71C9}
AppName=Lumen
AppVersion={#AppVersion}
AppPublisher=Lumen
DefaultDirName={localappdata}\Programs\Lumen
DefaultGroupName=Lumen
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputRoot}
OutputBaseFilename=lumen-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=lumen_iptv.exe
UninstallDisplayIcon={app}\lumen_iptv.exe

[Files]
Source: "{#BuildRoot}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Lumen"; Filename: "{app}\lumen_iptv.exe"
Name: "{autodesktop}\Lumen"; Filename: "{app}\lumen_iptv.exe"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\lumen_iptv.exe"; Description: "Launch Lumen"; Flags: nowait postinstall skipifsilent

; App settings/SQLite live outside {app}; upgrades and uninstall retain them.
