import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/ui_prefs.dart';
import '../../core/storage/ui_prefs_providers.dart';
import '../../core/theme.dart';
import 'quest_models.dart';
import 'quest_repository.dart';

/// 「任务进度权重」设置弹窗。
///
/// 父任务的进度 = 子项目进度按权重合成，权重由三个因子决定：
/// **工作量**（子树叶子数）/ **已投入时间** / **里程碑数**。
/// 三个因子会先在同一父节点的兄弟之间归一化，再按这里的比例相加，
/// 所以这里的数字只要相对比例有意义（内部会归一化）。
Future<void> showQuestWeightsDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final current = ref.read(questWeightsProvider);
  var work = current.work;
  var invest = current.invest;
  var milestone = current.milestone;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final preview = QuestWeights(
          work: work,
          invest: invest,
          milestone: milestone,
        ).normalized();
        return AlertDialog(
          title: const Text('任务进度权重'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '父任务的进度由子项目加权算出来。权重因子会先在兄弟之间归一化，'
                  '再按下面的比例合成 —— 所以只有相对比例有意义。',
                  style: TextStyle(fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 12),
                _row(
                  '工作量',
                  '子树最底层的项目数（件数不会因为漏记而失真）',
                  work,
                  (v) => setLocal(() => work = v),
                ),
                _row(
                  '已投入时间',
                  '子树累计投入分钟（客观，但取决于你记不记投入）',
                  invest,
                  (v) => setLocal(() => invest = v),
                ),
                _row(
                  '里程碑数',
                  '子树里程碑总数（容易被「多拆几个小阶段」灌水）',
                  milestone,
                  (v) => setLocal(() => milestone = v),
                ),
                const Divider(height: 20),
                Text(
                  '归一化后：工作量 ${(preview.work * 100).round()}% · '
                  '投入 ${(preview.invest * 100).round()}% · '
                  '里程碑 ${(preview.milestone * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (work + invest + milestone <= 0)
                  const Text(
                    '三项都为 0，将使用默认比例',
                    style: TextStyle(fontSize: 11, color: AppTheme.danger),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setLocal(() {
                work = QuestWeights.defaults.work;
                invest = QuestWeights.defaults.invest;
                milestone = QuestWeights.defaults.milestone;
              }),
              child: const Text('恢复默认'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );

  if (ok != true) return;
  await ref
      .read(uiPrefsProvider.notifier)
      .set(
        UiPrefs.questWeightsKey,
        QuestWeights(
          work: work,
          invest: invest,
          milestone: milestone,
        ).toJson(),
      );
}

Widget _row(
  String title,
  String hint,
  double value,
  void Function(double) onChanged,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            value.toStringAsFixed(2),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
      Slider(
        value: value.clamp(0, 1),
        max: 1,
        divisions: 20,
        onChanged: onChanged,
      ),
      Text(
        hint,
        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 6),
    ],
  );
}
