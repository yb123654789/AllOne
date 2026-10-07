import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import '../../core/widgets/color_picker.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';

/// 「特殊日子 · 倒数日」总览页。
///
/// 需求来源：日历里加的特殊日子分散在各个月份格子里，
/// 时间一长就想不起来、也找不到。这里把**所有自定义特殊日子按时间排好**，
/// 上面是「即将到来」（含每年重复的生日 / 纪念日，带倒数天数），
/// 下面是「已经过去」，点一下即可编辑，右下角可新增。

/// 添加 / 编辑特殊日子（日历页与本页共用同一个对话框）
Future<void> showSpecialDayEditor(
  BuildContext context,
  WidgetRef ref, {
  required String date,
  SpecialDay? editing,
}) async {
  final nameCtrl = TextEditingController(text: editing?.name ?? '');
  String color = editing?.color ?? '#F5A623';
  bool repeatYearly = editing?.repeatYearly ?? false;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(editing == null ? '添加特殊日子' : '编辑特殊日子'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '日期：$date',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '名称（如：生日 / 纪念日 / 考试）',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: repeatYearly,
                onChanged: (v) => setState(() => repeatYearly = v),
                title: const Text('每年重复', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  '生日、纪念日等：每年这一天都会出现在日历里，并自动倒数',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: hexColor(color),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.divider),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '当前颜色 $color',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.colorize, size: 18),
                    label: const Text('自定义颜色'),
                    onPressed: () async {
                      final picked = await showColorPickerDialog(
                        ctx,
                        initial: color,
                        title: '自定义颜色',
                      );
                      if (picked == null || !ctx.mounted) return;
                      setState(() => color = picked);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in const [
                    '#E5484D',
                    '#F5A623',
                    '#30A46C',
                    '#1E88E5',
                    '#7C3AED',
                    '#D6409F',
                  ])
                    _ColorDot(
                      hex: c,
                      selected: color.toUpperCase() == c.toUpperCase(),
                      onTap: () => setState(() => color = c),
                    ),
                ],
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

  if (saved != true) return;
  await ref
      .read(specialDayListProvider.notifier)
      .save(
        SpecialDay(
          // 编辑时沿用原 id 与原日期；新增时生成新 id
          id: editing?.id ?? AppPaths.newId(),
          date: editing?.date ?? date,
          name: nameCtrl.text.trim(),
          type: 'custom',
          color: color,
          repeatYearly: repeatYearly,
        ),
      );
}

/// 特殊日子总览（按时间排列的倒数日）
class SpecialDaysPage extends ConsumerWidget {
  const SpecialDaysPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(specialDayListProvider);
    final today = AppTime.dateOnly(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('特殊日子 · 倒数日')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('添加'),
        onPressed: () => _add(context, ref),
      ),
      body: async.when(
        data: (all) {
          // 内置节假日不入库，这里只可能是用户自己建的日子
          final list = all.where((s) => s.isCustom).toList();
          if (list.isEmpty) return _empty();

          final upcoming = list.where((s) => s.daysFrom(today) >= 0).toList()
            ..sort((a, b) => _cmpUpcoming(a, b, today));
          final past = list.where((s) => s.daysFrom(today) < 0).toList()
            ..sort((a, b) => _cmpPast(a, b, today));

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _section('即将到来（${upcoming.length}）'),
              if (upcoming.isEmpty)
                _hint('没有还没到的日子')
              else
                for (final s in upcoming) _tile(context, ref, s, today),
              _section('已经过去（${past.length}）'),
              if (past.isEmpty)
                _hint('没有已过去的日子')
              else
                for (final s in past) _tile(context, ref, s, today),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
    );
  }

  /// 即将到来：今天 0 天最前，然后天数从小到大；同一天按名称
  int _cmpUpcoming(SpecialDay a, SpecialDay b, String today) {
    final d = a.daysFrom(today).compareTo(b.daysFrom(today));
    if (d != 0) return d;
    final n = a.name.compareTo(b.name);
    return n != 0 ? n : a.date.compareTo(b.date);
  }

  /// 已经过去：最近过去的排前面（按天数从 -1 往下）
  int _cmpPast(SpecialDay a, SpecialDay b, String today) {
    final d = b.daysFrom(today).compareTo(a.daysFrom(today));
    if (d != 0) return d;
    final n = a.name.compareTo(b.name);
    return n != 0 ? n : a.date.compareTo(b.date);
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    SpecialDay s,
    String today,
  ) {
    final days = s.daysFrom(today);
    final isToday = days == 0;
    final color = hexColor(s.color);
    final years = s.anniversaryYears(today);
    final sub = <String>[
      s.date,
      if (s.repeatYearly) '每年重复',
      if (years != null) '第 $years 周年',
    ].join(' · ');

    return ListTile(
      // 点整行即可编辑（改名 / 改颜色 / 开关每年重复）
      onTap: () => showSpecialDayEditor(context, ref, date: s.date, editing: s),
      leading: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(
        s.name.isEmpty ? '（未命名）' : s.name,
        style: TextStyle(
          fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isToday ? color : color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              s.countdownLabel(today),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isToday ? Colors.white : color,
              ),
            ),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('删除特殊日子'),
                  content: Text('确定删除「${s.name.isEmpty ? '未命名' : s.name}」吗？'),
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
                await ref
                    .read(specialDayListProvider.notifier)
                    .delete(s.id);
              }
            },
          ),
        ],
      ),
    );
  }

  /// 新增：先选日期，再填名称 / 颜色
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year + 50),
      helpText: '选择日期',
    );
    if (picked == null) return;
    if (!context.mounted) return;
    await showSpecialDayEditor(
      context,
      ref,
      date: AppTime.dateOnly(picked),
    );
  }

  Widget _section(String s) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      s,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
    ),
  );

  Widget _hint(String s) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      s,
      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
    ),
  );

  Widget _empty() => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Text(
        '还没有特殊日子。\n\n点右下角「添加」，可以记生日、纪念日、考试倒计时等；\n'
        '打开「每年重复」后，每年这一天都会自动出现在日历里并倒数。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, height: 1.7, color: AppTheme.textSecondary),
      ),
    ),
  );
}

/// 对话框里的色块（选中打勾）
class _ColorDot extends StatelessWidget {
  final String hex;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: hexColor(hex),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppTheme.textPrimary : AppTheme.divider,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}
