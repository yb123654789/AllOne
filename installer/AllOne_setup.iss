; ============================================================
; AllOne 安装脚本 (Inno Setup 6)
; 功能：
;   1. 生成安装程序 + 卸载程序（自动注册到控制面板）
;   2. 安装时自动创建数据目录 Documents\AllOneData 及全部子目录
;   3. 卸载时自动删除程序文件与数据目录
; 生成产物：installer\output\AllOne_Setup_v1.2.1.exe
; ============================================================

#define MyAppName "AllOne"
#define MyAppVersion "1.2.1"
#define MyAppPublisher "AllOne"
#define MyAppExeName "allone.exe"
#define MyAppId "{{8E9D1F2A-3B4C-5D6E-7F80-9A1B2C3D4E5F}}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=output
OutputBaseFilename=AllOne_Setup_v{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
CloseApplicationsFilter={#MyAppExeName},*.exe
RestartApplications=no
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription={#MyAppName} Setup
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCopyright={#MyAppPublisher}

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

; 安装时自动创建数据目录结构（Documents\AllOneData）
[Dirs]
Name: "{userdocs}\AllOneData"
Name: "{userdocs}\AllOneData\diary"
Name: "{userdocs}\AllOneData\diary\templates"
Name: "{userdocs}\AllOneData\diary\entries"
Name: "{userdocs}\AllOneData\todo"
Name: "{userdocs}\AllOneData\todo\templates"
Name: "{userdocs}\AllOneData\todo\items"
Name: "{userdocs}\AllOneData\habit"
Name: "{userdocs}\AllOneData\habit\habits"
Name: "{userdocs}\AllOneData\habit\checkins"
Name: "{userdocs}\AllOneData\schedule"
Name: "{userdocs}\AllOneData\schedule\terms"
Name: "{userdocs}\AllOneData\schedule\courses"
Name: "{userdocs}\AllOneData\ledger"
Name: "{userdocs}\AllOneData\ledger\accounts"
Name: "{userdocs}\AllOneData\ledger\transactions"
Name: "{userdocs}\AllOneData\calendar"
Name: "{userdocs}\AllOneData\settings"
Name: "{userdocs}\AllOneData\map_tiles"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

; 卸载时自动删除数据目录（全部个人数据）
[UninstallDelete]
Type: filesandordirs; Name: "{userdocs}\AllOneData"

[Code]
{ 卸载确认：提醒数据目录会被删除 }
function InitializeUninstall(): Boolean;
begin
  Result := MsgBox(
    '即将卸载 AllOne，并删除全部个人数据（Documents\AllOneData 目录，' +
    '包含日记、待办、习惯、课程表、记账、日历等所有数据）。' + #13#10 + #13#10 +
    '确定要继续卸载吗？',
    mbConfirmation, MB_YESNO) = IDYES;
end;
