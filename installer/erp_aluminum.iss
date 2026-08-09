; Windows installer for ERP Aluminum.

#define AppName "ERP Aluminum"
#define AppVersion "1.0.0"
#define AppExeName "database_data.exe"
#define BuildDir "..\build\windows\x64\runner\Release"
#define IconFile "..\windows\runner\resources\app_icon.ico"

[Setup]
AppId={{9F063C4B-6DAB-4D9E-97D5-4389CFF5F5A6}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=ERP Aluminum
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=ERP-Aluminum-Setup-ColorFix
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\{#AppExeName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.pdb,*.lib,*.exp"

[Icons]
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "تشغيل {#AppName}"; Flags: nowait postinstall skipifsilent
