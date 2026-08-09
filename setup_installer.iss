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
OutputDir=C:\Users\hp\Desktop
OutputBaseFilename=ERP_Aluminum_Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut (إضافة اختصار على سطح المكتب)"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "c:\Users\hp\Desktop\erp-alum\erp-aluminum-main\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Run {#MyAppName} (تشغيل البرنامج الآن)"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}"
