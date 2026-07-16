#define MyAppName "Blacked Aeronautics"
#define MyAppExeName "elyprismlauncher.exe"
#define MyAppVersion GetEnv("BLACKED_VERSION")
#define PortableSource GetEnv("BLACKED_PORTABLE_SOURCE")
#define SetupOutputDir GetEnv("BLACKED_SETUP_OUTPUT")

#if MyAppVersion == ""
  #error "BLACKED_VERSION is not set"
#endif
#if PortableSource == ""
  #error "BLACKED_PORTABLE_SOURCE is not set"
#endif
#if SetupOutputDir == ""
  #error "BLACKED_SETUP_OUTPUT is not set"
#endif

[Setup]
AppId={{D2501AE9-BB5A-46F3-BDB8-A386C0F095ED}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=BlackSoul1337
AppPublisherURL=https://github.com/BlackSoul1337/Blacked-Aeronautics
AppSupportURL=https://github.com/BlackSoul1337/Blacked-Aeronautics/issues
AppUpdatesURL=https://github.com/BlackSoul1337/Blacked-Aeronautics/releases/latest
DefaultDirName={localappdata}\Programs\Blacked Aeronautics
DefaultGroupName=Blacked Aeronautics
DisableProgramGroupPage=yes
DisableDirPage=yes
OutputDir={#SetupOutputDir}
OutputBaseFilename=Blacked-Aeronautics-{#MyAppVersion}-win-x64-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=force
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительные ярлыки:"; Flags: unchecked

[Files]
Source: "{#PortableSource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Blacked Aeronautics"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\Blacked Aeronautics"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Запустить Blacked Aeronautics"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
