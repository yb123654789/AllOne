import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;

import '../../core/storage/json_store.dart';
import '../../core/storage/storage_providers.dart';
import '../../core/theme.dart';
import '../../core/widgets/attachment_view.dart';
import '../../core/widgets/location_map_view.dart';
import 'note_entry_edit_page.dart';
import 'notes_logic.dart';
import 'notes_models.dart';
import 'notes_repository.dart';

/// 一条笔记记录的只读详情页。
class NoteEntryDetailPage extends ConsumerWidget {
  final String topicId;
  final NoteEntry entry;

  const NoteEntryDetailPage({
    super.key,
    required this.topicId,
    required this.entry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => NoteEntryEditPage(topicId: topicId, entry: entry),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除这条记录',
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
              _meta(),
              const SizedBox(height: 12),
              _content(),
              if (entry.media.isNotEmpty) ...[
                const SizedBox(height: 16),
                // store 未就绪时算不出附件绝对路径，必须等它，否则会「只显示文件名打不开」
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
                              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : _attachments(store),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _meta() {
    final edited = entry.updatedAt.difference(entry.createdAt).inMinutes >= 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_outlined, size: 15, color: AppTheme.primary),
            const SizedBox(width: 5),
            Text(
              dateTimeText(entry.occurredAt),
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            ),
            const SizedBox(width: 10),
            Text(
              relativeDaysText(entry.occurredAt),
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        if (edited) ...[
          const SizedBox(height: 4),
          Text(
            '最后编辑 ${dateTimeText(entry.updatedAt)}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
        if (entry.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: entry.tags
                .map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(fontSize: 11, color: AppTheme.primary),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
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
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
            height: 170,
          ),
        ],
        const Divider(height: 24),
      ],
    );
  }

  Widget _content() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: SelectableText(
        entry.plainText.isEmpty ? '（无正文）' : entry.plainText,
        style: const TextStyle(fontSize: 15, height: 1.6),
      ),
    );
  }

  Widget _attachments(JsonStore store) {
    final mediaDir = p.join(store.root.path, noteMediaDir(topicId, entry.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '附件',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        for (final m in entry.media) AttachmentTile(media: m, mediaDir: mediaDir),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定删除这条记录吗？附件也会一并删除，不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(noteEntryListProvider(topicId).notifier).delete(entry.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
