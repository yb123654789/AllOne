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
├── notes/                   # 笔记模块（主题 → 记录，跨月跨年累积）
│   ├── groups/              # 分组（大类别 / 研究领域，可多归属）
│   │   └── <groupId>.json
│   └── topics/
│       ├── <topicId>.json            # 主题元数据（一本书 / 一个技能 / 一个项目）
│       └── <topicId>/entries/        # 该主题下的记录
│           ├── <entryId>.json
│           └── <entryId>/media/      # 记录的附件
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
│   ├── checkins/
│   │   └── <habitId>.json   # 打卡记录 { "yyyy-MM-dd": 数值 }
│   └── logs/
│       └── <habitId>.json   # 修改记录（补打卡审计日志，数组，只追加）
├── quest/
│   ├── quests/
│   │   ├── <questId>.json   # 任务（长期项目 / 领域）
│   │   └── <questId>/media/
│   └── logs/
│       └── <questId>.json   # 投入记录（数组：{at, minutes, note}）
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
  "order": 0,
  "createdAt": "...", "updatedAt": "..."
}
```

> **待办为树形结构**：每个待办可嵌套任意层级的子任务 `children`。
> 普通待办 = 没有子任务；任务链 = 嵌套了子任务的普通待办，每个子任务都拥有完整功能
> （标题 / 正文 / 截止 / 地点 / 标签 / 附件 / 状态）。
> - `order`：**只有顶层条目用**（同级排序，越小越靠前；手动排序时由仓库重排为 `1..n`）。
>   旧数据没有该字段，默认 `0`。
> - **子任务的顺序由 `children` 数组顺序表示**，不需要额外字段 —— 数组顺序即显示顺序。
> - 排序方式（手动 / 截止时间 / 创建时间 / 标题）存在 `settings/ui.json` 的
>   `todoSortMode`，默认 `deadline`（与加排序功能之前的行为一致）；
>   该设置**只作用于顶层列表**，子任务始终是手动顺序。

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

> 值为当天累计数值；`-1` 表示当天被标记为**未完成**（不计入完成与连续打卡）。
> 一个文件里放整月的记录吗？不是 —— **整个习惯的历史都在这一个文件里，整表写回**，
> 因此写操作必须基于**磁盘上的最新内容**（详见代码注释），否则并发/连续写入会丢数据。

修改记录 `logs/<habitId>.json`（**审计日志，只追加**）：
```json
[
  {
    "id": "20261011203000-0001",
    "at": "2026-10-11T20:30:00.000",
    "action": "checkin",
    "dates": ["2026-10-01", "2026-10-02"],
    "amount": 1,
    "before": { "2026-10-01": -1, "2026-10-02": 0 },
    "reason": "那两天做了但忘了打卡"
  }
]
```

> - `action` = `checkin`（补打卡）/ `markUndone`（标记未完成）/ `clear`（清除记录）。
> - `before` 记录改动前的原始值（`0` = 原本没有记录），便于追溯与人工复原。
> - `reason` **必填**：在热力图上修改历史记录必须写清原因，改动才会被接受。
> - 该文件由「习惯详情页 → 热力图 → 选日期 → 修改选中」写入；
>   删除习惯时会连同打卡记录、修改记录与附件目录一起清掉。

**热力图的五种状态**（由 `checkins` 推导，`-1` 与「无记录」是两回事）：

| 状态 | 数据来源 | 颜色 |
|------|----------|------|
| 已完成 | 当天达标（`dayMet`，多次打卡要满目标） | 绿 |
| 未完全完成 | 有打卡但没到当天目标 | 黄 |
| 漏打卡 | **计划日**（见下）却完全没有记录 | 浅红 |
| 标记未完成 | 值为 `-1`（用户主动标记） | 深红 |
| 未安排 | 非计划日 / 习惯创建之前 / 未来 | 灰 |

> **计划日**由 `frequency` 决定：`daily` 每天；`weekly` 只在 `weekdays` 选中的星期；
> `interval` 从**创建日**起每 `intervalDays` 天；`weeklyTimes` **没有固定计划日**，
> 因此不判「漏打卡」，改为在热力图列顶显示该周达成情况（`2/3` 或 `✓`）。

### 3.6 课程表

> **2026-10-11 改版（重要）**：课程不再是「一条 = 一个时段 + 手填时间」，改为：
>
> ```json
> {
>   "id": "c1",
>   "termId": "term-2026s",
>   "name": "数据结构",
>   "teacher": "张老师",
>   "color": "#E8E3FA",
>   "sessions": [
>     { "weekday": 1, "startSection": 3, "endSection": 4,
>       "weeks": [1,2,3,4,5,6,7,8], "classroom": "A4201" },
>     { "weekday": 3, "startSection": 3, "endSection": 4,
>       "weeks": [1,2,3,4,5,6,7,8], "classroom": "A4607" }
>   ],
>   "notes": "课程说明"
> }
> ```
>
> - **`sessions`**：一门课可有多个上课时段（不同天 / 不同教室各一条），
>   每个时段含 `weekday`（1-7）、`startSection`~`endSection`（节次，连堂即区间）、
>   `weeks`（逐周点选的上课周，**空 = 每周**）、`classroom`（该时段的教室）。
> - **时间不再存在课程里**：由作息表 `schedule/sections.json` 决定（见 3.6.1）。
> - **旧数据自动迁移**：只有 `weekday/startTime/endTime/weeks/classroom` 的旧课程，
>   读取时会变成一个时段（保留原自定义时间，节次留 0）；网格里按时间**就近匹配**节次落位。
> - 兼容 getter：`classroom` / `weekday` / `weeks` 仍返回**第一个时段**的值（旧代码可用）。
>
> #### 3.6.1 作息表 `schedule/sections.json`
>
> ```json
> { "sections": [ { "index": 1, "start": "08:50", "end": "09:35" } ] }
> ```
>
> - 第几节 → 起止时间；没写过就用内置默认（11 节，上午 4 / 下午 4 / 晚上 3）。
> - **编辑入口**：工具 → 课程表 · 学期管理 → 作息表。改动节数会重排 `index` 为 `1..n`
>   （已有课程按新编号对应，改完建议核对一下课程表）。
>
> #### 3.6.2 教学周次
>
> - 学期 `Term` 有 `start`/`end`；**第 1 周 = 开学日期所在周的周一**，
>   周次由日期实时算出（不落盘），课程表标题显示「第 N 周」并可前后翻周。
> - 课程只在 `weeks` 包含该周的周次出现（`weeks` 为空 = 每周都上）。
>
> ---
>
> 下面这段是**改版前的旧结构说明**，保留供参考：

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
    },
    {
      "id": "sd-2",
      "date": "2027-03-12",
      "originDate": "1998-03-12",
      "name": "生日",
      "type": "custom",
      "color": "#D6409F",
      "repeatYearly": true,
      "archived": false
    },
    {
      "id": "sd-3",
      "date": "2026-09-30",
      "name": "四级笔试",
      "type": "custom",
      "color": "#E5484D",
      "repeatYearly": false,
      "archived": true,
      "archivedAt": "2026-10-01"
    }
  ]
}
```

> - `special_days.json` 只保存**用户自定义**的特殊日子（`type = custom`）。
> - `repeatYearly`：是否**每年重复**（生日 / 纪念日）。`true` 时只比较「月-日」，
>   每年这一天都会出现在日历里，并在「特殊日子 · 倒数日」页给出倒数天数；
>   旧数据没有该字段时按 `false`（不重复）处理。
> - `originDate`：**原始日期**。每年重复的日子过了当天之后，会自动把 `date`
>   推进到下一次（见下），原始日期保留在这里，用于计算「第 N 周年」。
>   旧数据 / 还没推进过时为 `null`，此时回退用 `date` 计算。
> - `archived` / `archivedAt`：是否已移入**回收站**、以及归档日期（`yyyy-MM-dd`）。
>   `archivedAt` 为 `null` 时该字段不写入文件。归档后不再出现在日历格子与倒数日列表中，
>   只在「特殊日子 · 倒数日」页右上角的回收站里显示，可恢复或彻底删除。
> - **生命周期**（自动维护）：
>   - **单次**日子（`repeatYearly = false`）：`date < 今天` 才算过期，**当天不算**；
>     过期项由用户在倒数日页确认后归档（`archived = true`）。
>   - **每年重复**的日子：过期后自动把 `date` 推进到下一次发生日
>     （启动 App 时、以及进入倒数日页时各检查一次，幂等，无变化则不写盘）。
>     这类日子**永不归档**。
>   - 平年里的 2 月 29 日顺延到 2 月 28 日（否则 `2027-02-29` 这样的日期不存在，
>     解析失败会让倒数错误地显示成「今天」）。
> - `color` 为 `#RRGGBB`，可由用户任意自定义（常用色板 / RGB 微调 / 十六进制输入）。
> - **内置法定节假日 / 传统节日**（元旦、春节、清明、端午、中秋、国庆等，`type = holiday`）
>   由代码在运行时动态生成（含农历算法，见 `calendar/lunar_calendar.dart`），**不落盘**，
>   因此备份中无需包含，也不可被删除。

### 3.9 任务 `quest/quests/<questId>.json`

```json
{
  "id": "20261011120000-00001",
  "title": "写完那本书",
  "vision": "把这几年的想法整理成一本能给别人看的书",
  "category": "学习",
  "status": "active",
  "startDate": "2026-10-11",
  "targetDate": "2027-06-30",
  "time": "",
  "manualProgress": 20,
  "pinned": true,
  "pinnedAt": "2026-10-11T20:00:00.000",
  "milestones": [
    { "id": "m1", "title": "写完全部初稿", "dueDate": "2027-03-31", "done": false, "doneAt": "" }
  ],
  "todoIds": ["20261010101010-00007"],
  "media": [
    { "type": "photo", "file": "1787658907441_参考图.jpg", "size": 204800 }
  ],
  "parentId": "",
  "order": 0,
  "archived": false,
  "archivedAt": "",
  "createdAt": "2026-10-11T12:00:00.000",
  "updatedAt": "2026-10-11T20:00:00.000"
}
```

> - `status` = `active | paused | done | dropped`（进行中 / 暂停 / 已完成 / 已放弃）。
> - `targetDate` 为空串 = **长期、无期限**；`manualProgress`（0~100）**仅在没有里程碑时生效**。
> - `milestones`：阶段目标；**有里程碑时进度 = 已完成数 / 总数**（`manualProgress` 被忽略）。
> - `todoIds`：关联的**待办 id**（行动项）。任务**只引用不复制**待办数据 ——
>   待办仍归 `todo/` 管理，被删除后这边只在界面上显示「已失效」。
> - `media`：附件（照片 / 录音 / 视频 / 文件），放在 `quest/quests/<questId>/media/`；
>   超过 50 MB 的文件只记 `external` 外部路径引用。**子项目同样支持附件**（2026-10-18 新增）。
> - `pinned` / `pinnedAt`：钉住（当前重心），总览里排最前。
> - `archived` / `archivedAt`：回收站。

投入记录 `quest/logs/<questId>.json`（数组，只追加）：

```json
[
  {
    "id": "20261011203000-00001",
    "at": "2026-10-11T20:30:00.000",
    "minutes": 90,
    "note": "写完第二章"
  }
]
```

> - 用于累计「这个任务一共投入了多少时间」，以及判断**是否停滞**：
>   最近活动 = max(任务 `updatedAt`, 最近一条投入时间)；超过 14 天视为停滞
>   （进行中 / 暂停的任务才会提醒）。
> - 彻底删除任务时，`quest/quests/<id>.json`、`quest/logs/<id>.json` 与附件目录一起清理，
>   但**不会动 `todo/` 里的待办**。
> - `parentId` / `order`：**子项目**用的字段。`parentId` 为空串表示顶层任务；
>   `order` 是同级排序，结构变化（升降级 / 移动 / 上下移）后会被重排为 `0..n-1`。
>   子项目就是"挂在别的任务下的任务"，因此拥有全部字段与能力。
> - **有子项目时禁止删除或归档**该任务（必须先处理子项目）；
>   **子项目全部「已完成或已放弃」才允许把父任务设为已完成**（不自动完成）。
> - **父任务进度 = 子项目加权（递归）**：三个因子（工作量 = 子树叶子数 / 已投入分钟 =
>   子树累计 / 里程碑数 = 子树总数）先在**兄弟之间归一化**，再按比例合成。
>   默认比例 **工作量 0.5 : 投入 0.3 : 里程碑 0.2**，可在任务总览页调整，
>   存 `settings/ui.json`：
>   ```json
>   { "questWeights": { "work": 0.5, "invest": 0.3, "milestone": 0.2 },
>     "hideResolvedSubtasks": true }
>   ```
>   三个因子整组都失效时等权回退；**没有子项目**时才回退到「里程碑 / 手动百分比」。

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
> - `todoSortMode`：待办排序方式 —— `manual`（手动）/ `deadline`（按截止时间，缺省）/
>   `created`（按创建时间）/ `title`（按标题）；只作用于顶层列表。
> - `questWeights`：任务父进度的加权比例 `{work, invest, milestone}`（默认 0.5 / 0.3 / 0.2）。
> - `hideResolvedSubtasks`：任务详情页是否隐藏已了结的子项目（缺省 `true`）。
> - `notesGroupedView`：笔记列表视图 —— `true`（按分组折叠展示，缺省）/ `false`（平铺 + 分组筛选）。
> - 读取**全程容错**：文件损坏、字段缺失或类型不对都回退到默认值，不影响启动。

### 3.12 笔记 `notes/`

笔记是「主题 → 记录」两层结构，主要用来做**长期积累**：
一个主题（一本书 / 一个技能 / 一个研究 / 一段工作经历）下，
可以跨月跨年地一条条追加记录，界面按年月排成时间线。

**分组 `notes/groups/<groupId>.json`**

```json
{
  "id": "20261018201500-00042",
  "name": "大航海时代",
  "color": "#2E9E6B",
  "order": 0,
  "createdAt": "2026-10-18T20:15:00.000",
  "updatedAt": "2026-10-18T20:15:00.000"
}
```

> 分组只是**收纳用的标签**，本身不存记录。删分组不会删主题，只会把该分组
> 从各主题的归属里移除。

**主题 `notes/topics/<topicId>.json`**

```json
{
  "id": "20261018201600-00043",
  "groupIds": ["20261018201500-00042", "20261018201800-00044"],
  "title": "《大航海时代》",
  "intro": "欧洲扩张史，重点看技术与制度",
  "color": "#2F6FED",
  "pinned": false,
  "archived": false,
  "createdAt": "2026-10-18T20:16:00.000",
  "updatedAt": "2026-10-18T21:02:00.000"
}
```

> - `groupIds`：**可多归属**（一本书既能归到「大航海时代」，也能归到「2026 读完的书」）；
>   空 / 缺省 = 未分组。**兼容早期只有一个 `groupId`（字符串）的数据**，读取时自动转成数组。
> - `updatedAt`：最近一次「写入记录」的时间，列表按它排序（置顶优先）。
> - `deletedAt`：非空 = 在**回收站**（软删除）。主题 JSON、记录、附件都还在，
>   恢复即清空该字段；彻底删除才会删掉 `topics/<topicId>/` 整个目录。

**记录 `notes/topics/<topicId>/entries/<entryId>.json`**

```json
{
  "id": "20261018203000-00045",
  "topicId": "20261018201600-00043",
  "title": "第 3 章：香料与航线",
  "plainText": "香料贸易的利润率…",
  "occurredAt": "2026-10-18T21:20:00.000",
  "createdAt": "2026-10-18T21:25:00.000",
  "updatedAt": "2026-10-18T21:25:00.000",
  "tags": ["摘抄"],
  "media": [
    { "type": "photo", "file": "1787658907441_地图.jpg", "size": 204800 }
  ],
  "locationStamp": { "enabled": false, "lat": 0.0, "lng": 0.0, "name": "" }
}
```

> - `occurredAt` 是**这件事发生的时间**（可补记过去），时间线按它排序与分月；
>   `createdAt` 只是落盘时间，仅用于回溯。缺少 `occurredAt` 时退回 `createdAt`。
> - `topicId` 与所在目录应一致；若不一致（手工搬动 / 老数据），加载时以**目录归属**为准。
> - 附件目录与 JSON 并列：`notes/topics/<topicId>/entries/<entryId>/media/<文件名>`，
>   与日记 / 待办同一套约定。
> - 删除单条记录会连同它的附件目录一起删除（不可恢复）；
>   删除主题则是软删除，进回收站。

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
