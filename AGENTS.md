# AGENTS.md

本文件帮助 AI 编码智能体在 AllOne 项目中快速上手。项目详情见 [README.md](README.md)，架构 / 数据格式 / 构建细节请**链接到文档而非复制内容**：
- [架构设计](docs/ARCHITECTURE.md) · [数据格式](docs/DATA_FORMAT.md) · [构建指南](docs/BUILD.md) · [需求规格](docs/REQUIREMENTS.md)

## 项目概览

AllOne —— 个人全功能生活管理 App（Flutter，本地存储优先）。功能：📔 日记 · ✅ 待办 · 🔁 习惯 · 🏫 课程表 · 💰 记账 · 📅 日历，另有底部「工具」标签集中收纳备份/导入/导出/模板管理等辅助功能。
**中文 UI、中文注释**，与代码交互时请用中文。

## 技术栈

- Flutter 3.47（Dart 3.13）+ Riverpod 2.x（状态管理）
- `flutter_map` + `latlong2`（地图）、`geolocator`（系统定位；**GPS 离线可用**）
- 底图源可选，见 `lib/core/widgets/tile_sources.dart`：默认 **Esri**
  （OSM 官方在国内常被 DNS 污染 / 直连超时，会导致地图**整块空白**，
  看着像 bug 其实是网络）；本地 `AllOneData/map_tiles/` 有瓦片时优先读取
- `archive/share_plus`（备份）、`file_picker/record/audioplayers/video_player`（附件）、`syncfusion_flutter_pdf/fast_gbk`（外部日记导入：PDF 文本提取 / GBK txt 解码）

## 常用命令（智能体应直接运行）

```bash
flutter pub get                 # 拉取依赖
flutter test                    # 单元测试（test/ 下：models_test.dart、diary_import_test.dart 等）
flutter analyze                 # 静态分析
flutter run -d chrome           # 开发期快速预览（无需 Android SDK / VS）
flutter build windows --release # Windows 桌面版
flutter build apk --release     # Android APK
```

> Windows 桌面构建需要 Visual Studio（"C++ 桌面开发"工作负载）；iOS 构建需 macOS + Xcode。云编译走 GitHub Actions（`.github/workflows/flutter-build.yml`），产物在 Actions 的 Artifacts 下载。
>
> **Windows 构建必须在纯英文路径下进行**：路径含中文时 Flutter 的 Windows 工具链会报
> `Unable to read file ... app.dill`（路径按 GBK 解释而实际是 UTF-8）。
> 8.3 短路径、目录联接（junction）都绕不过去，因为 Flutter 内部仍会解析出真实路径。

## 架构约定（务必遵守）

- **分层**：`lib/core/`（核心层：存储引擎、通用模型、组件、备份、工具）与 `lib/features/<name>/`（日记 diary / 待办 todo / 习惯 habit / 课程表 schedule / 记账 ledger / 设置 settings / 日历 calendar / 工具 tools）。
- **依赖方向**：feature 只能依赖 core，**core 不依赖任何 feature**；feature 之间**互不引用内部实现**（风险隔离）。日历是只读聚合视图，通过 core 读取各模块数据。
- **每个 feature 的标准文件**：`<name>_models.dart`（模型）+ `<name>_repository.dart`（Riverpod 仓库）+ `<name>_page.dart`（页面）。新功能按此结构组织。

## 数据与存储

- 所有数据保存在应用文档目录的 `AllOneData/` 下（JSON + 附件），详见 [docs/DATA_FORMAT.md](docs/DATA_FORMAT.md)（含各模块 JSON 结构）。
- 通过 `JsonStore`（`lib/core/storage/json_store.dart`）读写：`read` / `write` / `delete` / `listFiles`，**原子写入**（临时文件 + 替换），单文件损坏返回 null 不影响整体。
- 模块数据在独立子目录（如 `diary/entries`、`diary/templates`、`todo/items`、`habit/habits`），一个条目一个文件。
- ID 用 `AppPaths.newId()`（`yyyyMMddHHmmss-XXXX`）；日期统一 `yyyy-MM-dd`，时间统一 ISO 8601。

## Riverpod 模式（新增仓库时照此实现）

- 仓库类：`class XxxListNotifier extends AsyncNotifier<List<XxxModel>>`，内部用 `static const _dir = '<module>/<subdir>'` 声明数据目录。
- `build()` 中用 `ref.watch(jsonStoreProvider.future)` 取存储并加载列表；写操作后用 `ref.read(jsonStoreProvider.future)` + `ref.invalidateSelf()` 刷新。
- Provider 定义：`final xxxListProvider = AsyncNotifierProvider<XxxListNotifier, List<XxxModel>>(XxxListNotifier.new);`

## 模型约定

- 每个模型实现 `Map<String, dynamic> toJson()` 与 `factory Xxx.fromJson(Map<String, dynamic>)`。
- 反序列化**必须容错**：可空字段用 `?? 默认值`，枚举用 `values.firstWhere(..., orElse:)`（参考 `lib/core/models/common.dart`）。
- 日期格式化用 `AppTime.dateOnly()`。

## 测试约定

- 单元测试集中在 `test/` 下（按模块分文件：`models_test.dart` 等），用 `group('模块名', ...)` 组织；核心是 **JSON 往返**（`toJson` → `fromJson`）与关键逻辑（进度、连续打卡）。
- 新增模型时，在对应 `group` 里补 JSON 往返测试；纯逻辑（如 `features/diary/diary_import.dart` 的解析 / 切分 / 去重）可直接单元测试。

## 常见坑（源自历史会话）

- Windows 桌面预览需先装 Visual Studio；若只是想快速看界面用 `flutter run -d chrome`。
- 本地远程仓库与 GitHub 远程库是两个概念：云编译把代码推送到 `https://github.com/yb123654789/AllOne.git` 的 `main` 分支后自动触发。
- 构建输出/状态文件（`build_out*.txt`、`build_status.json`）是构建辅助产物，非源码，勿修改。
