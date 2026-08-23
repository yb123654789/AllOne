import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../calendar/calendar_repository.dart';
import '../diary/diary_repository.dart';
import '../habit/habit_models.dart';
import '../habit/habit_repository.dart';
import '../ledger/ledger_models.dart';
import '../ledger/ledger_repository.dart';
import '../schedule/schedule_repository.dart';
import '../todo/todo_models.dart';
import '../todo/todo_repository.dart';

/// 通用文本导出（txt / Markdown）。
///
/// 把所有模块数据整理为标准的 Markdown（.md）文本，打包成 zip 后分享，
/// 方便用 U 盘 / 文件管理器在其他设备上直接阅读或存档。
/// 导出的 .md 是通用格式，任何文本编辑器 / 记事本都能打开。
class TextExporter {
  TextExporter._();

  /// 导出全部模块为通用文本，返回 zip 文件路径。
  static Future<String> exportText(WidgetRef ref) async {
    final tmp = await getTemporaryDirectory();
    final outDir = Directory(p.join(tmp.path, 'AllOne_export'));
    if (await outDir.exists()) {
      await outDir.delete(recursive: true);
    }
    await outDir.create(recursive: true);

    final files = <String, String>{
      'README.md': _readme(),
      '01_diary.md': _diary(ref),
      '02_todo.md': _todo(ref),
      '03_habit.md': _habit(ref),
      '04_schedule.md': _schedule(ref),
      '05_ledger.md': _ledger(ref),
      '06_calendar.md': _calendar(ref),
    };

    for (final entry in files.entries) {
      final f = File(p.join(outDir.path, entry.key));
      await f.writeAsString(entry.value, flush: true);
    }

    // 打包 zip
    final ts = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${ts.year}${two(ts.month)}${two(ts.day)}_${two(ts.hour)}${two(ts.minute)}';
    final zipPath = p.join(tmp.path, 'AllOne_export_$stamp.zip');
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    for (final entry in files.entries) {
      final f = File(p.join(outDir.path, entry.key));
      final bytes = await f.readAsBytes();
      encoder.addArchiveFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    encoder.close();
    return zipPath;
  }

  static String _readme() =>
      '# AllOne 数据导出（通用文本）\n\n'
      '本目录由 AllOne 一键导出，所有文件为通用 Markdown / 纯文本格式（UTF-8），\n'
      '可用任意文本编辑器（记事本、VS Code、Typora 等）直接打开阅读。\n\n'
      '文件说明：\n'
      '- 01_diary.md    日记\n'
      '- 02_todo.md     待办事项与任务链\n'
      '- 03_habit.md    习惯\n'
      '- 04_schedule.md 课程表\n'
      '- 05_ledger.md   记账\n'
      '- 06_calendar.md 日历特殊日子\n\n'
      '> 完整原始数据（JSON + 附件）请用「设置 → 导出备份 zip」。\n';

  static String _diary(WidgetRef ref) {
    final entries = ref.read(diaryListProvider).valueOrNull ?? [];
    final b = StringBuffer('# 日记\n\n');
    if (entries.isEmpty) {
      b.write('（暂无日记）\n');
      return b.toString();
    }
    for (final e in entries) {
      b.write('## ${e.title.isEmpty ? '（无标题）' : e.title}\n\n');
      b.write('- 时间：${e.createdAt.toIso8601String()}\n');
      if (e.timeStamp.enabled) {
        b.write(
          '- 时间戳：${e.timeStamp.nodeDate ?? ''}${e.timeStamp.pinTop ? '（置顶）' : ''}\n',
        );
      }
      if (e.locationStamp.enabled) {
        b.write(
          '- 地址戳：${e.locationStamp.name}（${e.locationStamp.lat}, ${e.locationStamp.lng}）\n',
        );
      }
      if (e.tags.isNotEmpty) b.write('- 标签：${e.tags.join('、')}\n');
      if (e.media.isNotEmpty) {
        b.write(
          '- 附件：${e.media.map((m) => m.file ?? m.external ?? m.type.name).join('、')}\n',
        );
      }
      b.write('\n${e.plainText.trim()}\n\n---\n\n');
    }
    return b.toString();
  }

  static String _todo(WidgetRef ref) {
    final items = ref.read(todoListProvider).valueOrNull ?? [];
    final b = StringBuffer('# 待办事项\n\n');
    if (items.isEmpty) b.write('（暂无待办）\n');
    for (final t in items) {
      _writeTodoNode(b, t, 0);
    }
    return b.toString();
  }

  /// 递归导出待办树（子任务缩进）
  static void _writeTodoNode(StringBuffer b, TodoItem t, int depth) {
    final done = t.status == TodoStatus.done;
    final indent = '  ' * depth;
    b.write(
      '$indent- [${done ? 'x' : ' '}] ${t.title.isEmpty ? '（无标题）' : t.title}',
    );
    if (t.deadline.date.isNotEmpty) {
      b.write(
        '（截止 ${t.deadline.date}${t.deadline.time.isEmpty ? '' : ' ${t.deadline.time}'}）',
      );
    }
    if (t.location.text.isNotEmpty) b.write('（地点：${t.location.text}）');
    if (t.tags.isNotEmpty) b.write('（标签：${t.tags.join('、')}）');
    if (t.hasChildren) {
      b.write(
        '（子任务 ${t.children.where((c) => c.status == TodoStatus.done).length}/${t.children.length}）',
      );
    }
    b.write('\n');
    if (t.contentPlain.trim().isNotEmpty) {
      b.write('$indent  ${t.contentPlain.trim().replaceAll('\n', '\n$indent  ')}\n');
    }
    if (t.media.isNotEmpty) {
      b.write(
        '$indent  附件：${t.media.map((m) => m.file ?? m.external ?? m.type.name).join('、')}\n',
      );
    }
    for (final c in t.children) {
      _writeTodoNode(b, c, depth + 1);
    }
  }

  static String _habit(WidgetRef ref) {
    final habits = ref.read(habitListProvider).valueOrNull ?? [];
    final checkins = ref.read(habitCheckinProvider).valueOrNull ?? const {};
    final b = StringBuffer('# 习惯\n\n');
    if (habits.isEmpty) {
      b.write('（暂无习惯）\n');
      return b.toString();
    }
    for (final h in habits) {
      b.write('## ${h.title.isEmpty ? '未命名习惯' : h.title}\n');
      b.write('- 分类：${h.category}\n');
      b.write(
        '- 目标：${h.target.type == HabitType.count ? '次数' : '天数'} ${h.target.value}\n',
      );
      final cm = checkins[h.id] ?? const CheckinMap();
      b.write('- 已打卡：次数 ${cm.totalCount}，天数 ${cm.totalDays}\n');
      b.write('- 连续：${cm.streakDays(DateTime.now())} 天\n');
      if (h.tags.isNotEmpty) b.write('- 标签：${h.tags.join('、')}\n');
      if (h.description.isNotEmpty) b.write('- 描述：${h.description.trim()}\n');
      if (h.media.isNotEmpty) {
        b.write(
          '- 附件：${h.media.map((m) => m.file ?? m.external ?? m.type.name).join('、')}\n',
        );
      }
      b.write('\n');
    }
    return b.toString();
  }

  static String _schedule(WidgetRef ref) {
    final courses = ref.read(courseListProvider).valueOrNull ?? [];
    final b = StringBuffer('# 课程表\n\n');
    if (courses.isEmpty) {
      b.write('（暂无课程）\n');
      return b.toString();
    }
    const weekdayNames = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    for (final c in courses) {
      b.write('## ${c.name}\n');
      b.write(
        '- ${weekdayNames[c.weekday]} ${c.startTime}-${c.endTime} ${c.classroom}\n',
      );
      if (c.teacher.isNotEmpty) b.write('- 教师：${c.teacher}\n');
      if (c.weeks.isNotEmpty) b.write('- 周次：${c.weeks.join(', ')}\n');
      if (c.notes.isNotEmpty) b.write('- 说明：${c.notes.trim()}\n');
      b.write('\n');
    }
    return b.toString();
  }

  static String _ledger(WidgetRef ref) {
    final accounts = ref.read(accountListProvider).valueOrNull ?? [];
    final txs = ref.read(transactionListProvider).valueOrNull ?? [];
    final b = StringBuffer('# 记账\n\n');
    if (accounts.isEmpty) b.write('（暂无账户）\n');

    for (final a in accounts) {
      final accTxs = txs.where((t) => t.accountId == a.id).toList();
      final income = accTxs
          .where((t) => t.type == TxType.income)
          .fold(0.0, (s, t) => s + t.amount);
      final expense = accTxs
          .where((t) => t.type == TxType.expense)
          .fold(0.0, (s, t) => s + t.amount);
      final balance = a.initialBalance + income - expense;
      b.write('## 账户：${a.icon} ${a.name.isEmpty ? '未命名账户' : a.name}\n');
      b.write('- 初始余额：${a.initialBalance.toStringAsFixed(2)}\n');
      b.write(
        '- 累计收入：${income.toStringAsFixed(2)}，累计支出：${expense.toStringAsFixed(2)}\n',
      );
      b.write('- 当前余额：${balance.toStringAsFixed(2)}\n');
      if (accTxs.isEmpty) {
        b.write('- （无流水）\n\n');
        continue;
      }
      b.write('\n| 日期 | 类型 | 金额 | 分类 | 备注 |\n');
      b.write('|------|------|------|------|------|\n');
      for (final t in accTxs) {
        b.write(
          '| ${t.date} | ${t.type == TxType.income ? '收入' : '支出'} | '
          '${t.amount.toStringAsFixed(2)} | ${t.category} | ${t.note} |\n',
        );
      }
      b.write('\n');
    }
    return b.toString();
  }

  static String _calendar(WidgetRef ref) {
    final specials = ref.read(specialDayListProvider).valueOrNull ?? [];
    final b = StringBuffer('# 日历特殊日子\n\n');
    if (specials.isEmpty) {
      b.write('（暂无用户自定义的特殊日子；内置节假日随日历界面自动显示）\n');
      return b.toString();
    }
    for (final s in specials) {
      b.write('- ${s.date} ${s.name}${s.type == 'holiday' ? '（内置节假日）' : ''}\n');
    }
    return b.toString();
  }
}
