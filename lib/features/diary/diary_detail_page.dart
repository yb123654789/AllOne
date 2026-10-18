import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;

import '../../core/storage/json_store.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets/attachment_view.dart';
import '../../core/widgets/location_map_view.dart';
import '../notes/notes_diary_import.dart';
import 'diary_edit_page.dart';
import 'diary_models.dart';
import 'diary_repository.dart';

/// 日记只读详情页。
class DiaryDetailPage extends ConsumerWidget {
  final DiaryEntry entry;

  const DiaryDetailPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          entry.title.isEmpty ? '日记详情' : entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            tooltip: '转存为笔记',
            onPressed: () => showDiaryTransferFlow(context, ref, [entry]),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => DiaryEditPage(entry: entry)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: FutureBuilder<JsonStore>(
        future: ref.watch(jsonStoreProvider.future),
        builder: (context, snap) {
          final store = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _meta(context),
              const SizedBox(height: 12),
              _content(context, store),
              if (entry.media.isNotEmpty) ...[
                const SizedBox(height: 16),
                // 附件区必须等 store 就绪再渲染。
                //
                // 附件路径 = store.root.path + 条目目录，store 为 null 时算不出路径，
                // 于是 `file.existsSync()` 恒为 false —— 表现为「只显示文件名、
                // 打不开」（打开/播放按钮根本不出现）。
                // 之前这里在加载期间直接用 null 渲染，正是这个症状的来源。
                store == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '正在加载附件…',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _attachments(context, store),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _meta(BuildContext context) {
    final stamps = <Widget>[];
    if (entry.timeStamp.enabled) {
      stamps.add(
        _stampChip(
          Icons.schedule,
          '时间戳${entry.timeStamp.nodeDate == null ? '' : ' ${entry.timeStamp.nodeDate}'}',
          AppTheme.primary,
        ),
      );
    }
    if (entry.locationStamp.enabled) {
      stamps.add(
        _stampChip(
          Icons.location_on,
          '地址戳 ${entry.locationStamp.name}',
          Colors.green,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}-${entry.createdAt.day.toString().padLeft(2, '0')} '
          '${entry.createdAt.hour.toString().padLeft(2, '0')}:${entry.createdAt.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        if (stamps.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: stamps),
        ],
        if (entry.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: entry.tags
                .map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        // 地址戳：在地图上可视化展示位置
        if (entry.locationStamp.enabled) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.green),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  entry.locationStamp.name.isEmpty
                      ? '位置：${entry.locationStamp.lat}, ${entry.locationStamp.lng}'
                      : '位置：${entry.locationStamp.name}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LocationMapView(
            center: LatLng(
              entry.locationStamp.lat == 0 ? 39.9042 : entry.locationStamp.lat,
              entry.locationStamp.lng == 0 ? 116.4074 : entry.locationStamp.lng,
            ),
            height: 180,
          ),
        ],
        const Divider(height: 24),
      ],
    );
  }

  Widget _stampChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, JsonStore? store) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: SelectableText(
        entry.plainText.isEmpty ? '（空）' : entry.plainText,
        style: const TextStyle(fontSize: 15, height: 1.6),
      ),
    );
  }

  Widget _attachments(BuildContext context, JsonStore store) {
    // 附件路径 = store.root.path + 条目目录（store 一定非空，调用方已保证）。
    //
    // 早期这里在 store 为 null 时把 mediaDir 退化成空串，会让所有附件
    // 「存在性判断」失败（表现为只显示文件名、打不开）。
    final mediaDir = p.join(store.root.path, diaryMediaDir(entry.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '附件',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        // 整行可点即打开（照片看大图 / 录音直接播放 / 视频播放 / 文件交给系统程序）
        for (final m in entry.media)
          AttachmentTile(media: m, mediaDir: mediaDir),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除日记'),
        content: const Text('确定删除这篇日记吗？该操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(diaryListProvider.notifier).deleteEntry(entry.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
