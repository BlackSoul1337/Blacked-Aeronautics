#define MyAppName "Blacked Aeronautics"
#define MyAppExeName "Blacked Aeronautics.exe"
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
DefaultDirName={%USERPROFILE}\Games\BA
DefaultGroupName=Blacked Aeronautics
DisableProgramGroupPage=yes
DisableDirPage=no
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
Uninstallable=yes
CreateUninstallRegKey=yes
UninstallFilesDir={app}\uninstall

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
russian.CreateStartMenuIcon=Создать ярлык в меню «Пуск»
english.CreateStartMenuIcon=Create a Start Menu shortcut
russian.InstallPathTooLong=Выбранный путь слишком длинный для Distant Horizons.%n%nВыберите папку ближе к корню диска, например C:\Games\BA.
english.InstallPathTooLong=The selected path is too long for Distant Horizons.%n%nChoose a folder closer to the drive root, for example C:\Games\BA.

[Tasks]
Name: "startmenuicon"; Description: "{cm:CreateStartMenuIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#PortableSource}\*"; DestDir: "{app}"; Excludes: "\elyprismlauncher.cfg,\instances\Blacked-Aeronautics\instance.cfg"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#PortableSource}\elyprismlauncher.cfg"; DestDir: "{app}"; Flags: onlyifdoesntexist
Source: "{#PortableSource}\instances\Blacked-Aeronautics\instance.cfg"; DestDir: "{app}\instances\Blacked-Aeronautics"; Flags: onlyifdoesntexist

[Icons]
Name: "{group}\Blacked Aeronautics"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: startmenuicon
Name: "{autodesktop}\Blacked Aeronautics"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
function NextButtonClick(CurPageID: Integer): Boolean;
var
  GameDirectory: String;
begin
  Result := True;
  if CurPageID <> wpSelectDir then
    Exit;

  GameDirectory := AddBackslash(WizardDirValue) +
    'instances\Blacked-Aeronautics\minecraft';
  if Length(GameDirectory) > 70 then
  begin
    MsgBox(ExpandConstant('{cm:InstallPathTooLong}'), mbError, MB_OK);
    Result := False;
  end;
end;
