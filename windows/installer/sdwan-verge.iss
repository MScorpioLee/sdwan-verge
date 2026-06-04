#define SourceDir GetEnv("SDWAN_SOURCE_DIR")
#define OutputDir GetEnv("SDWAN_OUTPUT_DIR")
#define AppVersion GetEnv("SDWAN_APP_VERSION")

[Setup]
AppId={{7C8F76CF-93BE-49D9-BF7B-98157C3CC481}
AppName=SD-WAN Verge
AppVersion={#AppVersion}
AppPublisher=SD-WAN Verge
DefaultDirName={autopf}\SD-WAN Verge
DefaultGroupName=SD-WAN Verge
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=sdwan-verge-windows-x64-setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\SD-WAN Verge"; Filename: "{app}\sdwan_client.exe"
Name: "{autodesktop}\SD-WAN Verge"; Filename: "{app}\sdwan_client.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sdwan_windows_helper.exe"; Parameters: "install"; Flags: runhidden waituntilterminated
Filename: "{app}\sdwan_client.exe"; Description: "{cm:LaunchProgram,SD-WAN Verge}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\sdwan_windows_helper.exe"; Parameters: "uninstall"; Flags: runhidden waituntilterminated
