; ============================================================
; AllOne 安装脚本 (Inno Setup 6)
; 功能：
;   1. 生成安装程序 + 卸载程序（自动注册到控制面板）
;   2. 安装时自动创建数据目录 Documents\AllOneData 及全部子目录
;   3. 卸载时**默认保留**数据目录，只有用户明确选择才删除
; 生成产物：installer\output\AllOne_Setup_v1.2.3.exe
;
; ⚠ 数据安全说明（重要，勿改回旧写法）：
;   旧版本用 [UninstallDelete] 无条件删除 {userdocs}\AllOneData。
;   而 Setup 安装新版本时会**自动静默调用旧版本的卸载程序**，
;   静默模式下 MsgBox 取默认按钮（旧写法的默认是「是」），
;   于是「升级安装」会把用户全部数据静默删掉。
;   现在改为：卸载时询问（默认按钮 = 否 / 保留），且删除动作由
;   CurUninstallStepChanged(usPostUninstall) 执行，升级路径不再有任何删除。
; ============================================================

#define MyAppName "AllOne"
; 版本号：CI 会用 /DMyAppVersion=x.y.z 覆盖（从 pubspec.yaml 读，见 .github/workflows/flutter-build.yml）；
; 本地直接编译时才用下面这个默认值。发布前记得确认两处一致。
#ifndef MyAppVersion
  #define MyAppVersion "1.3.0"
#endif
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

; 注意：这里**故意没有** [UninstallDelete] 删除数据目录的条目。
; 卸载时是否删除数据，由下面的脚本在询问之后决定。

[Code]
var
  DeleteData: Boolean;

{ 卸载询问：默认按钮为「否」（保留数据）。
  静默卸载（升级时 Setup 会自动调用旧卸载器）取默认值 = 否，
  因此升级永远不会删除数据。 }
function InitializeUninstall(): Boolean;
begin
  DeleteData := MsgBox(
    '是否同时删除全部个人数据？' + #13#10 + #13#10 +
    '数据目录：Documents\AllOneData' + #13#10 +
    '（含日记、待办、习惯、课程表、记账、日历、附件等全部内容）' + #13#10 + #13#10 +
    '建议选择「否」保留数据 —— 以后重新安装 AllOne 还能继续使用。',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES;
  Result := True;
end;

{ 只有用户明确选择「是」才删除数据目录 }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and DeleteData then
  begin
    DelTree(ExpandConstant('{userdocs}\AllOneData'), True, True, True);
  end;
end;
