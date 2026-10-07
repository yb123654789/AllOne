# 发布产物

本目录为**发布产物说明**。安装包 / APK 等大文件**不直接存于 git 仓库**（避免仓库膨胀），统一通过 **GitHub Releases** 发布：

👉 **下载地址**：`https://github.com/yb123654789/AllOne/releases`

## 发布内容

| 平台 | 文件 | 说明 |
|------|------|------|
| **Windows** | `AllOne_Setup_vX.Y.Z.exe` | Inno Setup 安装包（含卸载程序，安装/卸载自动管理 `文档\AllOneData` 数据目录） |
| **Windows** | `AllOne-vX.Y.Z-Windows.zip` | 免安装版，解压即用（含 exe 与全部 dll） |
| **Android** | `AllOne-vX.Y.Z.apk` | Release APK（可直接安装到手机） |

> 三个产物均由 CI 自动构建，**推送 `v*` 标签即可**，无需手工打包。
> 产物文件名带版本号，避免下载多个版本时互相覆盖。

> 🔑 **Android 产物用固定发布签名**（`android/allone-release.jks`，随仓库保存）。
> 这是「应用内一键更新」能覆盖安装的前提：签名必须始终一致。
> 该密钥与 `android/key.properties` **一旦丢失就再也无法覆盖升级**（只能卸载重装 + 先备份数据），
> 请连同仓库一起备份到 U 盘。详见 [构建指南](../docs/BUILD.md) 的「Android 发布签名」。

## 如何发布新版本

自动发布（推荐）：推送一个 `v*` 标签即可触发 CI 自动构建并发布到 Releases：

```bash
git tag v1.2.1
git push origin v1.2.1
```

CI 依次完成：构建 Windows → 打包 zip → 编译 Inno Setup 安装包 →
构建 Android APK → 按 `pubspec.yaml` 的版本号重命名产物 → 发布到 Releases。

> **版本号取自 `pubspec.yaml`**（`version: X.Y.Z+build`）。发布前先改它，
> 并同步 `installer/AllOne_setup.iss` 里的 `MyAppVersion`（否则文件名与版本号会不一致）。

或到 GitHub 仓库 **Actions** 页手动运行 **Build AllOne** 工作流；
手动触发时可在 *Use workflow from* 选已有标签，用于给旧发布补齐产物。

## 打包脚本

- Windows 安装包：`installer/AllOne_setup.iss`（Inno Setup 脚本）
- 构建说明见根目录 [README](../README.md)
