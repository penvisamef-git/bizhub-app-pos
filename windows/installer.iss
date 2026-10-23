; BizHub POS for Windows: the installer (Inno Setup 6, https://jrsoftware.org/isinfo.php).
; Made by tool\build_windows.ps1 after "flutter build windows"; it passes /DAppVersion=<x.y.z>.
; Output: build\installer\BizHub-POS-Setup-<version>.exe

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppName "BizHub POS"
#define AppExe "BizHubPOS.exe"
#define Src "..\build\windows\x64\runner\Release"

[Setup]
; never change AppId: Windows uses it to find and update the installed app
AppId={{6F2B7C1E-4D3A-4B8E-9C5F-1A2B3C4D5E6F}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Blackcorp Enterprise
AppPublisherURL=https://bizhubcambodia.com
AppSupportURL=https://bizhubcambodia.com
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; installs for everyone by default; a cashier without admin rights can choose "only for me"
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=BizHub-POS-Setup-{#AppVersion}
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Src}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
