import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'notes_models.dart';
import 'notes_repository.dart';
import 'notes_style.dart';

/// 新建 / 编辑笔记主题。
///
/// 主题只描述「记什么」：名称、简介、分组、颜色、是否置顶 / 归档。
/// 内容全部写在主题下的记录里（记录编辑页）。
class NoteTopicEditPage extends ConsumerStatefulWidget {
  final NoteTopic? topic;

  /// 新建时预选的分组（从某个分组筛选状态下点「新的主题」时带上）
  final String? initialGroupId;

  const NoteTopicEditPage({super.key, this.topic, this.initialGroupId});

  @override
  ConsumerState<NoteTopicEditPage> createState() => _NoteTopicEditPageState();
}

class _NoteTopicEditPageState extends ConsumerState<NoteTopicEditPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _introCtrl;
  late String _color;
  final Set<String> _groupIds = {};
  late bool _pinned;
  late bool _archived;

  @override
  void initState() {
    super.initState();
    final t = widget.topic;
    _titleCtrl = TextEditingController(text: t?.title ?? '');
    _introCtrl = TextEditingController(text: t?.intro ?? '');
    _color = t?.color ?? kNotePalette.first;
    _groupIds.addAll(t?.groupIds ?? const <String>[]);
    if (t == null && widget.initialGroupId != null) {
      _groupIds.add(widget.initialGroupId!);
    }
    _pinned = t?.pinned ?? false;
    _archived = t?.archived ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _introCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('给主题起个名字吧（如书名、技能名、项目名）')));
      return;
    }
    final now = DateTime.now();
    final existing = widget.topic;
    final groupIds = List<String>.of(_groupIds);
    final topic = existing == null
        ? NoteTopic(
            id: AppPaths.newId(),
            groupIds: groupIds,
            title: title,
            intro: _introCtrl.text.trim(),
            color: _color,
            pinned: _pinned,
            archived: _archived,
            createdAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            groupIds: groupIds,
            title: title,
            intro: _introCtrl.text.trim(),
            color: _color,
            pinned: _pinned,
            archived: _archived,
            updatedAt: now,
          );
    await ref.read(noteTopicListProvider.notifier).save(topic);
    if (mounted) Navigator.pop(context, topic);
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(noteGroupListProvider).valueOrNull ?? const <NoteGroup>[];
    final isNew = widget.topic == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '新建主题' : '编辑主题'),
        actions: [
          IconButton(
            onPressed: _save,
            tooltip: '保存',
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            autofocus: isNew,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '主题名称',
              hintText: '如：《人类简史》 / 吉他 / 某项目复盘',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _introCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '简介（可选）',
              hintText: '一句话说明记什么、为什么记；也可以是「当前结论」',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '分组（可多选；不选即未分组）',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final g in groups)
                FilterChip(
                  avatar: CircleAvatar(radius: 5, backgroundColor: noteColor(g.color)),
                  label: Text(g.name.isEmpty ? '未命名分组' : g.name),
                  selected: _groupIds.contains(g.id),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _groupIds.add(g.id);
                    } else {
                      _groupIds.remove(g.id);
                    }
                  }),
                ),
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '还没有分组；可在笔记列表的「分组」里新建',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('颜色', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          NoteColorPicker(value: _color, onChanged: (c) => setState(() => _color = c)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('置顶'),
            subtitle: const Text('列表里排在最前面', style: TextStyle(fontSize: 12)),
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('归档'),
            subtitle: const Text('不再活跃的主题，列表里默认收起', style: TextStyle(fontSize: 12)),
            value: _archived,
            onChanged: (v) => setState(() => _archived = v),
          ),
          const SizedBox(height: 8),
          const Text(
            '主题建好后，进去点右下角「记一条」就能一条条往里记；\n'
            '每条记录可以带照片、录音、视频、文件、位置和标签。',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }
}
