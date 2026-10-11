import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'schedule_logic.dart';
import 'schedule_models.dart';
import 'schedule_repository.dart';

/// 学期管理页（入口在工具页）：增删改学期 + 编辑作息表。
///
/// 学期只要填「名称 + 起止日期」，课程表就能自动算出当前第几周；
/// 作息表（第几节几点到几点）也在这里进。
class TermManagePage extends ConsumerWidget {
  const TermManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(termListProvider).valueOrNull ?? const <Term>[];
    final sections =
        ref.watch(sectionListProvider).valueOrNull ?? kDefaultSections;
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: const Text('学期管理')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('添加学期'),
        onPressed: () => showTermEditor(context, ref),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 92),
        children: [
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('作息表'),
            subtitle: Text(
              '${sections.length} 节 · 第 1 节 ${sections.first.start}'
              '${sections.length > 1 ? '，第 ${sections.last.index} 节 ${sections.last.start}' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SectionEditPage()),
            ),
          ),
          const Divider(height: 1),
          if (terms.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                '还没有学期。\n\n建一个学期填上起止日期，课程表就会自动算出'
                '「第几周」。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.8,
                  color: AppTheme.textSecondary,
                ),
              ),
            )
          else
            for (final t in terms)
              _termTile(context, ref, t, today),
        ],
      ),
    );
  }

  Widget _termTile(
    BuildContext context,
    WidgetRef ref,
    Term t,
    DateTime today,
  ) {
    final weekNo = ScheduleLogic.weekNoOf(t, today);
    final total = ScheduleLogic.totalWeeks(t);
    final isCurrent =
        t.start.isNotEmpty &&
        t.end.isNotEmpty &&
        AppTime.dateOnly(today).compareTo(t.start) >= 0 &&
        AppTime.dateOnly(today).compareTo(t.end) <= 0;

    return ListTile(
      leading: Icon(
        isCurrent ? Icons.play_circle_fill : Icons.circle_outlined,
        color: isCurrent ? AppTheme.primary : AppTheme.textSecondary,
      ),
      title: Text(t.name.isEmpty ? '未命名学期' : t.name),
      subtitle: Text(
        '${t.start} ~ ${t.end}\n'
        '${total > 0 ? '共 $total 周' : '未设置完整日期'}'
        '${isCurrent && weekNo > 0 ? ' · 现在是第 $weekNo 周' : ''}',
        style: const TextStyle(fontSize: 12),
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (v) async {
          if (v == 'edit') {
            await showTermEditor(context, ref, editing: t);
          } else if (v == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('删除学期'),
                content: Text(
                  '确定删除「${t.name.isEmpty ? '未命名学期' : t.name}」吗？\n\n'
                  '（课程不会被删除，但会失去所属学期）',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('删除'),
                  ),
                ],
              ),
            );
            if (ok == true) {
              await ref.read(termListProvider.notifier).deleteTerm(t.id);
            }
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }
}

/// 学期编辑对话框（新增 / 编辑共用）
Future<void> showTermEditor(
  BuildContext context,
  WidgetRef ref, {
  Term? editing,
}) async {
  final nameCtrl = TextEditingController(text: editing?.name ?? '');
  var start = editing?.start ?? AppTime.dateOnly(DateTime.now());
  var end = editing?.end ?? '';

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(editing == null ? '添加学期' : '编辑学期'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '学期名称',
                  hintText: '如：2026 秋季学期',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _dateRow(
                ctx,
                '开学日期（第 1 周从这一天所在的周算起）',
                start,
                (d) => setLocal(() => start = d),
              ),
              const SizedBox(height: 8),
              _dateRow(
                ctx,
                '结束日期（用于算总周数）',
                end.isEmpty ? '未设置' : end,
                (d) => setLocal(() => end = d),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );

  if (ok != true) return;
  final term = Term(
    id: editing?.id ?? AppPaths.newId(),
    name: nameCtrl.text.trim(),
    start: start,
    end: end,
  );
  await ref.read(termListProvider.notifier).saveTerm(term);
}

Widget _dateRow(
  BuildContext ctx,
  String label,
  String value,
  void Function(String) onPicked,
) {
  return Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(value, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
      TextButton(
        onPressed: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: ctx,
            initialDate: DateTime.tryParse(value) ?? now,
            firstDate: DateTime(now.year - 5),
            lastDate: DateTime(now.year + 10),
          );
          if (picked != null) onPicked(AppTime.dateOnly(picked));
        },
        child: const Text('选日期'),
      ),
    ],
  );
}

/// 作息表编辑页：第几节 → 起止时间（可增删、可改时间）。
///
/// 改节数会**重新编号**（1..n）：已有课程按新编号对应到新的作息时间，
/// 所以改完最好扫一眼课程表确认没有错位。
class SectionEditPage extends ConsumerStatefulWidget {
  const SectionEditPage({super.key});

  @override
  ConsumerState<SectionEditPage> createState() => _SectionEditPageState();
}

class _SectionEditPageState extends ConsumerState<SectionEditPage> {
  List<SectionTime> _sections = const [];
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(sectionListProvider).valueOrNull;
    if (!_loaded && loaded != null) {
      _sections = [...loaded];
      _loaded = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('作息表'),
        actions: [
          IconButton(
            tooltip: '恢复默认',
            icon: const Icon(Icons.restart_alt),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('恢复默认作息'),
                  content: const Text('将把作息表恢复为内置默认（11 节），确定吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('恢复'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await ref.read(sectionListProvider.notifier).resetDefault();
                setState(() => _loaded = false);
              }
            },
          ),
          IconButton(
            tooltip: '保存',
            icon: const Icon(Icons.save_outlined),
            onPressed: () async {
              await ref
                  .read(sectionListProvider.notifier)
                  .saveAll(_sections);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('作息表已保存')),
              );
              Navigator.pop(context);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('加一节'),
        onPressed: () => setState(() {
          final last = _sections.isEmpty ? null : _sections.last;
          _sections = [
            ..._sections,
            SectionTime(
              index: _sections.length + 1,
              start: last?.end ?? '08:00',
              end: last?.end ?? '08:45',
            ),
          ];
        }),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 92),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '课程只选「第几节」，时间由这张表决定。改完节数会重新编号（1..n），'
              '已有课程按新编号对应，建议改完看一眼课程表。',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          for (var i = 0; i < _sections.length; i++)
            _row(i, _sections[i]),
        ],
      ),
    );
  }

  Widget _row(int i, SectionTime s) {
    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
        child: Text(
          '${i + 1}',
          style: const TextStyle(fontSize: 12, color: AppTheme.primary),
        ),
      ),
      title: Text('第 ${i + 1} 节'),
      subtitle: Text('${s.start} - ${s.end}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: _toTime(s.start),
              );
              if (t == null) return;
              setState(() {
                final list = [..._sections];
                list[i] = list[i].copyWith(start: _fmt(t));
                _sections = list;
              });
            },
            child: const Text('开始'),
          ),
          TextButton(
            onPressed: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: _toTime(s.end),
              );
              if (t == null) return;
              setState(() {
                final list = [..._sections];
                list[i] = list[i].copyWith(end: _fmt(t));
                _sections = list;
              });
            },
            child: const Text('结束'),
          ),
          IconButton(
            tooltip: '删除这一节',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              final list = [..._sections]..removeAt(i);
              _sections = list;
            }),
          ),
        ],
      ),
    );
  }

  static TimeOfDay _toTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 8 : 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
