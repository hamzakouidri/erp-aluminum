; Inno Setup Script for ERP Aluminum Desktop App
#define MyAppName "ورشتي - ERP Aluminum"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "ورشتي للألمنيوم"
#define MyAppExeName "database_data.exe"

[Setup]
AppId={{A3D89E71-4B98-4F12-86D4-00129B7F72C1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\ERP_Aluminum
DisableProgramGroupPage=yes
OutputDir=C:\Users\hp\Desktop\ERP_Aluminum_Releases
OutputBaseFilename=ERP_Aluminum_Setup
SetupIconFile=c:\Users\hp\Desktop\erp-alum\erp-aluminum-main\windows\runner\resources\setup_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "c:\Users\hp\Desktop\erp-alum\erp-aluminum-main\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}"

