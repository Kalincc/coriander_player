#define AppVersion GetEnv("CORIANDER_RELEASE_VERSION")
#define StageDir GetEnv("CORIANDER_STAGE_DIR")
#define ArtifactDir GetEnv("CORIANDER_OUTPUT_DIR")

[Setup]
AppId={{B1A7B3E9-42C5-4AE5-8B3D-79078C73D4F2}
AppName=Coriander Player
AppVersion={#AppVersion}
AppPublisher=Kalincc
AppPublisherURL=https://github.com/Kalincc/coriander_player
AppSupportURL=https://github.com/Kalincc/coriander_player/issues
DefaultDirName={localappdata}\Programs\Coriander Player
DefaultGroupName=Coriander Player
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#ArtifactDir}
OutputBaseFilename=Coriander.Player.{#AppVersion}.Setup
SetupIconFile=..\app_icon.ico
UninstallDisplayIcon={app}\coriander_player.exe
Compression=lzma2/ultra64
SolidCompression=yes
CloseApplications=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加快捷方式:"; Flags: unchecked

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Coriander Player"; Filename: "{app}\coriander_player.exe"
Name: "{autodesktop}\Coriander Player"; Filename: "{app}\coriander_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\coriander_player.exe"; Description: "启动 Coriander Player"; Flags: nowait postinstall skipifsilent
