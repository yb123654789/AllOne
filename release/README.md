# 发布产物

本目录为**发布产物说明**。安装包 / APK 等大文件**不直接存于 git 仓库**（避免仓库膨胀），统一通过 **GitHub Releases** 发布：

👉 **下载地址**：`https://github.com/yb123654789/AllOne/releases`

## 发布内容

| 平台 | 文件 | 说明 |
|------|------|------|
| **Windows** | `AllOne_Setup_vX.Y.Z.exe` | Inno Setup 安装包（含卸载程序，安装/卸载自动管理 `文档\AllOneData` 数据目录） |
| **Android** | `AllOne_vX.Y.Z.apk` | Release APK（可直接安装到手机） |

## 如何发布新版本

自动发布（推荐）：推送一个 `v*` 标签即可触发 CI 自动构建并发布到 Releases：

```bash
git tag v1.1.0
git push origin v1.1.0
```

或到 GitHub 仓库 **Actions** 页手动运行 **Build AllOne** 工作流，产物会作为 Artifacts 提供。

## 打包脚本

- Windows 安装包：`installer/AllOne_setup.iss`（Inno Setup 脚本）
- 构建说明见根目录 [README](../README.md)
