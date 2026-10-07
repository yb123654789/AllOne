# AllOne 数据格式设计文档

> 版本：0.1
> 设计目标：**格式通用、可长期保存、可直接用 U 盘复制备份、跨设备可读**

## 1. 总览：数据目录结构

AllOne 的所有数据保存在一个**根数据目录**中（用户可自行选择位置，默认在应用文档目录）：

```
AllOneData/
├── diary/                   # 日记模块
│   ├── templates/           # 日记模板
│   │   └── <templateId>.json
│   └── entries/
│       ├── <entryId>.json   # 日记元数据 + 正文
│       └── <entryId>/       # 同一 id 的附件目录（与 .json 并列）
│           └── media/       # 附件（照片/录音/视频/文件）
├── todo/                    # 待办模块
│   ├── templates/           # 待办模板
│   └── items/
│       ├── <itemId>.json    # 顶层待办（子任务内嵌在 children）
│       └── <itemId>/
│           └── media/       # 附件
├── habit/
│   ├── habits/
│   │   ├── <habitId>.json
│   │   └── <habitId>/media/
│   └── checkins/
│       └── <habitId>.json   # 打卡记录 { "yyyy-MM-dd": 数值 }
├── schedule/
│   ├── terms/               # 学期（半年一换）
│   │   └── <termId>.json
│   └── courses/             # 课程
│       └── <courseId>.json
├── ledger/
│   ├── ledger.json          # 总账本配置
│   ├── settings.json        # 记账设置（本月计划支出预算）
│   ├── accounts/            # 账户
│   │   └── <accountId>.json
│   └── transactions/        # 流水（扁平文件：<accountId>_<yyyy-MM>.json）
│       └── <accountId>_<yyyy-MM>.json
├── calendar/
│   ├── special_days.json    # 日历界面创建的特殊日子/节假日
│   └── settings.json
└── map_tiles/               # 离线地图瓦片（可选，{z}/{x}/{y}.png）

settings/
    └── nav.json             # 导航设置（底部导航栏显示哪些功能）
```

> 说明：日记 / 待办 / 习惯的每一条数据是「一个 JSON 文件 + 一个同名附件目录」，
> 附件目录与 JSON **并列**（不是把 JSON 放进目录里），且附件字段只存**文件名**，
> 目录由条目 id 推导（如 `todo/items/<id>/media/<文件名>`）。
> 好处：备份时整个目录原样复制；条目独立，单条目损坏不影响全局；附件与元数据天然在一起。
>
> 注意：**没有 `manifest.json`**。数据版本迁移所需的字段目前尚未落盘，
> 若将来需要 schema 迁移，应先实现它再更新本文档。


## 2. 通用约定

- 所有文本统一 UTF-8 编码，正文存纯文本（`plainText` / `contentPlain` / `description` 等），保证 txt 可读、格式通用。

## 3. 各模块数据模型（JSON Schema 摘要）

### 3.1 日记条目 `diary/entries/<entryId>.json`

```json
{
  "id": "20260820103000-a1b2c",
  "title": "标题",
  "plainText": "正文（纯文本，类似 txt）",
  "createdAt": "2026-08-20T10:30:00.000",
  "updatedAt": "2026-08-20T10:35:00.000",
  "timeStamp": { "enabled": true, "nodeDate": "2027-02-20", "pinTop": true },
  "locationStamp": { "enabled": true, "lat": 30.67, "lng": 104.06, "name": "家" },
  "tags": ["生活", "旅行"],
  "media": [
    { "type": "photo", "file": "1787658907441_a.jpg", "size": 123456 },
    { "type": "audio", "file": "1787658907442_rec.m4a", "size": 4567 },
    { "type": "video", "file": "1787658907443_v.mp4", "size": 8000000 },
    { "type": "file", "file": "1787658907444_d.pdf", "size": 9999 },
    { "type": "videoLink", "external": "D:\\Videos\\big.mp4", "note": "大视频外链" }
  ],
  "pinned": false
}
```

> - 正文为**纯文本**（类似 txt），手机 / 电脑键盘双适配编辑。
> - `templateId` 为**可选**字段，仅在使用模板创建时写入。
> - `tags` / `timeStamp` / `locationStamp` 是**顶层字段**（不是嵌套的 `stamps`）。
> - `media[].type` 取值为 `photo | audio | video | file | videoLink`。
> - `media[].file` 只存**文件名**，实际路径为
>   `diary/entries/<entryId>/media/<file>`。

**大视频处理规则**：
- 附件 ≥ 阈值（默认 50MB，可配置）→ 不复制进 `media/`，改为 `external` 外链引用（保存原路径 / 外部存储位置），正文中以链接形式展示。


### 3.2 待办条目 `todo/items/<itemId>.json`

```json
{
  "id": "202608201100-c3d4",
  "type": "todo",
  "title": "待办标题",
  "contentPlain": "内容（纯文本，txt 风格）",
  "deadline": { "date": "2026-08-25", "time": "18:00", "color": "#E53935", "highlight": true },
  "location": { "text": "图书馆 3F", "color": "#1E88E5", "highlight": true, "lat": 0, "lng": 0 },
  "status": "pending | done | archived",
  "media": [ "同日记 media 结构" ],
  "tags": [],
  "children": [ "子任务（递归嵌套，任意层级，结构同本条）" ],
  "createdAt": "...", "updatedAt": "..."
}
```

> **待办为树形结构**：每个待办可嵌套任意层级的子任务 `children`。
> 普通待办 = 没有子任务；任务链 = 嵌套了子任务的普通待办，每个子任务都拥有完整功能
> （标题 / 正文 / 截止 / 地点 / 标签 / 附件 / 状态）。

### 3.3 任务链（树形待办）`items/`

任务链已合并进普通待办，不再单独存储。一个含子任务的待办即构成一棵任务链树：

```json
{
  "id": "chain-001",
  "title": "学习 Python",
  "contentPlain": "达到能独立开发脚本的水平",
  "status": "pending",
  "children": [
    {
      "id": "st-1",
      "title": "完成基础语法",
      "contentPlain": "先看官方文档",
      "status": "done",
      "children": [
        { "id": "st-1-1", "title": "循环练习", "status": "done" }
      ]
    },
    { "id": "st-2", "title": "完成数据处理练习", "status": "pending" }
  ],
  "createdAt": "...", "updatedAt": "..."
}
```

- 普通待办与任务链统一为**树形 TodoItem**：顶层条目一个文件（`todo/items/<id>.json`），子任务内嵌于父 JSON 的 `children`。
- 每个节点（含子任务）都具备完整待办功能，可继续嵌套任意层。
- 待办列表按树形展开/折叠展示，节点可添加子任务、勾选完成、编辑、删除。

### 3.4 待办模板 `templates/<templateId>.json`

模板可整体保存「标题预设 + 内容（纯文本）+ 截止时间 + 地点 + 标签」，
新建待办时一键套用：

```json
{
  "id": "tp-001",
  "name": "周报",
  "title": "周报",
  "contentPlain": "模板纯文本内容",
  "deadline": { "date": "2026-08-28", "time": "18:00", "color": "#E5484D", "highlight": true },
  "location": { "text": "办公室", "color": "#1E88E5", "highlight": false, "lat": 0, "lng": 0 },
  "tags": ["工作"],
  "createdAt": "...", "updatedAt": "..."
}
```

### 3.5 习惯 `habits/<habitId>.json`

```json
{
  "id": "20260824224613-18806",
  "title": "每日阅读",
  "category": "学习",
  "frequency": "daily",
  "weekdays": [],
  "intervalDays": 1,
  "weeklyTimes": 1,
  "dailyTarget": "once",
  "dailyTargetValue": 1,
  "persistence": "unlimited",
  "persistenceValue": 0,
  "archived": false,
  "description": "描述（纯文本）",
  "media": [],
  "tags": [],
  "createdAt": "2026-08-24T22:46:13.000",
  "updatedAt": "2026-08-24T22:46:13.000"
}
```

> 三维度打卡：**频率** `frequency` = `daily | weekly | interval | weeklyTimes`
> （配合 `weekdays` / `intervalDays` / `weeklyTimes`）；
> **当天目标** `dailyTarget` = `once | quantity | minutes`（配合 `dailyTargetValue`）；
> **坚持周期** `persistence` = `unlimited | days | times | cycles`（配合 `persistenceValue`）。
> 习惯描述为**纯文本**，可附附件与标签。`archived=true` 表示已移入回收站。

打卡记录 `checkins/<habitId>.json`（**一个习惯一个文件**，不是按月分文件）：
```json
{ "2026-08-01": 1, "2026-08-02": 3, "2026-08-05": -1 }
```

> 值为当天累计数值；`-1` 表示当天标记为**失败**（不计入完成与连续打卡）。

### 3.6 课程表

学期 `terms/<termId>.json`：
```json
{
  "id": "term-2026s",
  "name": "2026 秋季学期",
  "start": "2026-09-01",
  "end": "2027-01-15"
}
```

课程 `courses/<courseId>.json`：
```json
{
  "id": "course-001",
  "termId": "term-2026s",
  "name": "数据结构",
  "teacher": "张老师",
  "classroom": "教学楼 301",
  "weekday": 1,
  "startTime": "08:00",
  "endTime": "09:40",
  "weeks": [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],
  "notes": "课程说明：考核方式、参考资料等（Markdown）"
}
```

### 3.7 记账

总账本 `ledger.json`：
```json
{
  "id": "ledger-main",
  "name": "我的总账本",
  "currency": "CNY",
  "accountIds": ["acc-1", "acc-2"]
}
```

账户 `accounts/<accountId>.json`：
```json
{ "id": "acc-1", "name": "现金", "icon": "💵", "color": "#4CAF50", "initialBalance": 0 }
```

流水 `transactions/<accountId>_<yyyy-MM>.json`：
```json
{
  "accountId": "acc-1",
  "month": "2026-08",
  "records": [
    { "id": "tx-1", "date": "2026-08-20", "type": "expense | income", "amount": 35.5, "category": "餐饮", "note": "午饭" }
  ]
}
```

> 流水文件为**扁平结构** `<accountId>_<yyyy-MM>.json`（注意：不是子目录）。

记账设置 `settings.json`：
```json
{ "monthlyBudget": 2000 }
```

### 3.8 日历特殊日子 `calendar/special_days.json`

```json
{
  "specialDays": [
    {
      "id": "sd-1",
      "date": "2026-10-01",
      "name": "纪念日",
      "type": "custom",
      "color": "#F44336",
      "repeatYearly": false
    }
  ]
}
```

> - `special_days.json` 只保存**用户自定义**的特殊日子（`type = custom`）。
> - `repeatYearly`：是否**每年重复**（生日 / 纪念日）。`true` 时只比较「月-日」，
>   每年这一天都会出现在日历里，并在「特殊日子 · 倒数日」页给出倒数天数；
>   旧数据没有该字段时按 `false`（不重复）处理。
> - `color` 为 `#RRGGBB`，可由用户任意自定义（常用色板 / RGB 微调 / 十六进制输入）。
> - **内置法定节假日 / 传统节日**（元旦、春节、清明、端午、中秋、国庆等，`type = holiday`）
>   由代码在运行时动态生成（含农历算法，见 `calendar/lunar_calendar.dart`），**不落盘**，
>   因此备份中无需包含，也不可被删除。

### 3.10 导航设置 `settings/nav.json`

```json
{
  "bottomBarVisible": {
    "diary": true,
    "todo": true,
    "habit": false
  }
}
```

> - 控制各功能（diary / todo / habit / schedule / ledger / calendar / tools）
>   是否显示在**底部导航栏**中。
> - 未配置的功能默认显示（缺省为 `true`）；关闭后仍可从「工具 → 功能导航」进入。

### 3.11 界面偏好 `settings/ui.json`

```json
{
  "scheduleLayout": "list",
  "lastUpdateCheck": "2026-10-07T14:20:00.000",
  "skippedUpdateVersion": "1.2.4"
}
```

> - 记录「记住显示方式」这类小偏好，键值对形式，**新增偏好不需要改数据结构**。
> - `scheduleLayout`：课程表周视图的排布 —— `auto`（按窗口宽度自动，缺省）/
>   `grid`（7 列网格）/ `list`（按天纵向列表）。
> - `lastUpdateCheck`：上次检查更新的时间（ISO 8601），用于「一天最多查一次」。
> - `skippedUpdateVersion`：用户点过「跳过此版本」的版本号，不再重复提示。
> - 读取**全程容错**：文件损坏、字段缺失或类型不对都回退到默认值，不影响启动。

## 4. 备份格式

- 手动备份：将整个 `AllOneData/` 目录**原样复制**到 U 盘 / 外部目录，即完成备份。
- 可选打包：一键导出为 `AllOneData_backup_<date>.zip`。
- **通用文本导出**：设置页可把日记 / 待办 / 习惯 / 课程 / 记账整理为
  `01_diary.md`、`02_todo.md` 等标准 Markdown / txt 文件打包成 zip，
  任何设备可用记事本打开（此格式**只读导出**，不用于导入）。
- 恢复：从 zip 导入，**覆盖同名文件**（逐文件先写 `.tmp` 再改名，保证单个文件不会写一半）。
  导出与恢复都采用流式读写，附件再大也不会把整个文件读进内存。

## 5. 兼容与迁移

- 目前**没有** `manifest.json`，也没有落盘的 `schemaVersion`。
  早期文档曾声称存在，实际未实现；若将来需要做数据版本迁移，
  应先在 `AppPaths` / 启动流程中实现它，再更新本文档。
- 附件与正文分离，正文始终是通用文本（Markdown/txt），保证 10 年后仍可读。
