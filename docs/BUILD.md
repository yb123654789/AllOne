# AllOne 构建指南

本文件说明如何在不同平台上构建 / 运行 AllOne。

## 0. 环境准备

| 工具 | 用途 | 版本要求 |
|------|------|----------|
| Flutter SDK | 编译与运行 | 3.47+（含 Dart 3.13） |
| Android SDK | 构建 Android 包 | API 21+ |
| Visual Studio | 构建 Windows 桌面 | 2022，含"C++ 桌面开发"工作负载 |
| macOS + Xcode | 构建 iOS / iPadOS | 仅需在 Mac 上编译 iOS |

## 1. 获取依赖

```bash
flutter pub get
```

## 2. 运行调试

```bash
# 在已连接的设备 / 模拟器运行（优先使用真机以获得完整功能）
flutter run

# Chrome 快速预览（开发期，无需 Android SDK / VS）
flutter run -d chrome

# 指定 Windows 桌面
flutter run -d windows

# 指定 Android 设备
flutter run -d <device-id>
```

## 3. 打包发布

```bash
# Android APK
flutter build apk --release
# Android App Bundle（上架应用商店）
flutter build appbundle --release

# Windows 桌面（免安装版）
flutter build windows --release
# 产物位于 build/windows/x64/runner/Release/

# iOS（需在 macOS 上执行）
flutter build ios --release
```

## 4. 测试

```bash
flutter test          # 运行单元测试（模型序列化 / 逻辑）
flutter analyze       # 静态分析
```

## 5. 常见问题

### 5.1 首次运行 Windows 报错缺少工具链
需要安装 Visual Studio 2022，并勾选 **"使用 C++ 的桌面开发"** 工作负载
（含 Windows 11 SDK 与 MSVC 工具链）。

### 5.2 Android 构建报错 "Unable to locate Android SDK"
- 安装 Android Studio 或命令行 `cmdline-tools`；
- 或在 `flutter config --android-sdk <路径>` 指定 SDK 位置。

### 5.3 iOS 构建
- 必须在 macOS + Xcode 上执行；
- `flutter config --enable-ios` 并确保 `flutter doctor` 中 iOS 项通过。

### 5.4 地图底图与离线瓦片

- **在线底图**：默认 **Esri 世界街道图**，可在「设置 → 地图底图」切换
  （Esri 街道 / Esri 影像 / 高德 / 腾讯 / OSM）。
  为什么不用 OSM 官方做默认：`tile.openstreetmap.org` 在国内常被 DNS 污染 /
  直连超时，地图会**整块空白**。实测未开代理时 OSM / Carto / OpenTopoMap 全部超时。
  高德 / 腾讯使用 **GCJ-02** 坐标，与 GPS 的 WGS-84 有几十米偏移（仅影响显示位置）。
- **离线瓦片**：把标准 XYZ 瓦片放入 `AllOneData/map_tiles/{z}/{x}/{y}.png`，
  应用会**优先使用本地瓦片**，缺失才回退在线源。项目不内置地图数据。
- **定位**：使用系统定位（手机 GPS），**不需要网络**；权限被拒时会明确提示。

### 5.5 Windows 构建必须在纯英文路径下

路径含中文时 Flutter 的 Windows 工具链会报
`Unable to read file ... app.dill`（路径按 GBK 解释而实际是 UTF-8）。
实测 8.3 短路径与目录联接（junction）都绕不过去 —— Flutter 内部仍会解析出真实路径。
建议工程放在纯英文路径（如 `C:\VScode\SoftwareDevelopment\AllOne`）。

## 6. 数据目录

- 应用数据保存在系统文档目录的 `AllOneData/`。
- 备份：设置页 → 导出备份 zip → 复制到 U 盘。
- 恢复：设置页 → 从备份恢复。
