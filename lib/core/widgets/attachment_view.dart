import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/common.dart';
import '../theme.dart';
import '../utils/media_utils.dart';
import 'video_viewer.dart';

/// 附件查看 / 播放的统一入口。
///
/// 设计要点（源自实际使用反馈）：
/// - **整行点一下就能打开**：以前必须精确点到右侧那个小图标，
///   照片要「按一个按钮」才打得开，体验很差；
/// - **录音可直接播放**：以前录音点了没有任何反应（路径不存在 / 解码失败
///   都是静默失败），这里改为内置播放器，并**把失败原因明确显示出来**；
/// - **文件找不到时说清楚**：显示完整路径，可复制，不再「点了没反应」。

/// 附件类型中文名
String mediaTypeLabel(MediaType t) => switch (t) {
  MediaType.photo => '照片',
  MediaType.audio => '录音',
  MediaType.video => '视频',
  MediaType.file => '文件',
  MediaType.videoLink => '外链',
};

/// 附件类型图标
IconData mediaTypeIcon(MediaType t) => switch (t) {
  MediaType.photo => Icons.photo_outlined,
  MediaType.audio => Icons.mic_none_outlined,
  MediaType.video => Icons.videocam_outlined,
  MediaType.file => Icons.insert_drive_file_outlined,
  MediaType.videoLink => Icons.link,
};

/// 附件体积显示（统一格式，避免各页面各写一份）
String formatMediaSize(int bytes) {
  if (bytes <= 0) return '大小未知';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 去掉落盘时加的 `<毫秒>_` 前缀，显示成用户能认出来的文件名
String mediaDisplayName(MediaAttachment m) {
  final raw = m.file ?? m.external ?? '';
  if (raw.isEmpty) return '（未知附件）';
  final base = raw.split(RegExp(r'[\\/]')).last;
  final stripped = base.replaceFirst(RegExp(r'^\d{10,}_'), '');
  return stripped.isEmpty ? base : stripped;
}

/// 算出附件的真实文件（内嵌附件 = mediaDir + 文件名；外链 = 原始路径）。
/// 目录未知（例如新条目尚未保存）或本身是网址时返回 null。
File? resolveMediaFile(MediaAttachment m, String? mediaDir) {
  final name = m.file;
  if (name != null && name.isNotEmpty && mediaDir != null) {
    return File(p.join(mediaDir, name));
  }
  final ext = m.external;
  if (ext != null &&
      ext.isNotEmpty &&
      !ext.startsWith('http://') &&
      !ext.startsWith('https://')) {
    return File(ext);
  }
  return null;
}

/// 附件行：**整行可点即打开**，右侧另有播放 / 查看图标（同一动作）与可选的删除按钮。
class AttachmentTile extends StatelessWidget {
  final MediaAttachment media;

  /// 内嵌附件所在目录（绝对路径）。为 null 表示路径未知（尚未保存的新条目）。
  final String? mediaDir;

  /// 编辑态可传入删除回调（列表里显示删除按钮）
  final VoidCallback? onDelete;

  final EdgeInsetsGeometry contentPadding;

  const AttachmentTile({
    super.key,
    required this.media,
    this.mediaDir,
    this.onDelete,
    this.contentPadding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final file = resolveMediaFile(media, mediaDir);
    final exists = file != null && file.existsSync();
    // 路径本来算不出来（新条目）还是算出来了但文件不在，提示语不同
    final unknown = media.file != null && media.file!.isNotEmpty && file == null;
    final missing = file != null && !exists;

    final subtitleParts = <String>[
      mediaTypeLabel(media.type),
      formatMediaSize(media.size),
    ];
    final note = media.note;
    if (note != null && note.isNotEmpty) subtitleParts.add(note);
    if (unknown) subtitleParts.add('尚未保存');
    if (missing) subtitleParts.add('文件不存在');

    return ListTile(
      contentPadding: contentPadding,
      onTap: () => openAttachment(context, media, mediaDir: mediaDir),
      leading: _leading(file, exists),
      title: Text(
        mediaDisplayName(media),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: missing ? AppTheme.danger : AppTheme.textSecondary,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _actionLabel(media.type),
            icon: Icon(_actionIcon(media.type), color: AppTheme.primary),
            onPressed: () => openAttachment(context, media, mediaDir: mediaDir),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: '移除',
              icon: const Icon(Icons.delete_outline, color: AppTheme.textSecondary),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  /// 照片直接显示缩略图（一眼能看出是哪张，不用先点开）
  Widget _leading(File? file, bool exists) {
    if (media.type == MediaType.photo && file != null && exists) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            file,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            cacheWidth: 144,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, color: AppTheme.danger),
          ),
        ),
      );
    }
    final color = (file != null && !exists) ? AppTheme.danger : AppTheme.primary;
    return Icon(mediaTypeIcon(media.type), color: color);
  }

  String _actionLabel(MediaType t) => switch (t) {
    MediaType.photo => '查看照片',
    MediaType.audio => '播放录音',
    MediaType.video => '播放视频',
    MediaType.file => '打开文件',
    MediaType.videoLink => '打开外链',
  };

  IconData _actionIcon(MediaType t) => switch (t) {
    MediaType.photo => Icons.visibility_outlined,
    MediaType.audio => Icons.play_circle_outline,
    MediaType.video => Icons.play_circle_outline,
    MediaType.file => Icons.open_in_new,
    MediaType.videoLink => Icons.open_in_new,
  };
}

/// 按类型打开附件：照片 → 全屏查看；录音 → 内置播放器；
/// 视频 → 播放器；文件 / 外链 → 交给系统默认程序。
Future<void> openAttachment(
  BuildContext context,
  MediaAttachment media, {
  String? mediaDir,
}) async {
  final file = resolveMediaFile(media, mediaDir);
  final exists = file != null && file.existsSync();

  switch (media.type) {
    case MediaType.photo:
      if (!exists) return _showProblem(context, '照片打不开', media, file);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ImageViewerPage(file: file, title: mediaDisplayName(media)),
        ),
      );
    case MediaType.audio:
      if (!exists) return _showProblem(context, '录音打不开', media, file);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              AudioPlayerPage(file: file, title: mediaDisplayName(media)),
        ),
      );
    case MediaType.video:
      if (!exists) return _showProblem(context, '视频打不开', media, file);
      // 桌面端没有 video_player 实现（Windows / Linux 未提供插件），
      // 内嵌播放只会显示「暂不支持」；这里直接交给系统播放器。
      if (Platform.isWindows || Platform.isLinux) {
        final opened = await MediaUtils.openWithSystem(file.path);
        if (!context.mounted || opened) return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoViewer(file: file)),
      );
    case MediaType.videoLink:
    case MediaType.file:
      final target = file?.path ?? media.external;
      if (target == null || target.isEmpty) {
        return _showProblem(context, '附件打不开', media, file);
      }
      if (file != null && !exists) {
        return _showProblem(context, '找不到文件', media, file);
      }
      final opened = await MediaUtils.openWithSystem(target);
      if (!context.mounted) return;
      if (!opened) return _showProblem(context, '无法用系统程序打开', media, file);
  }
}

/// 统一的「打不开」提示：说清楚是路径没了还是平台不支持，并提供可复制的路径。
Future<void> _showProblem(
  BuildContext context,
  String title,
  MediaAttachment media,
  File? file,
) async {
  final path = file?.path ?? media.external ?? '';
  final missing = file != null && !file.existsSync();
  final lines = <String>[
    missing
        ? '数据里记录了该附件，但磁盘上找不到这个文件（可能被移动、重命名或删除）。'
        : '当前平台无法直接打开这个附件。',
    if (media.note != null && media.note!.isNotEmpty) '备注：${media.note}',
    if (path.isNotEmpty) '路径：$path',
  ];
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SelectableText(
        lines.join('\n\n'),
        style: const TextStyle(fontSize: 13, height: 1.5),
      ),
      actions: [
        if (path.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制路径'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: path));
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// 全屏图片查看（可双指 / 滚轮缩放，点空白返回）
class ImageViewerPage extends StatelessWidget {
  final File file;
  final String? title;

  const ImageViewerPage({super.key, required this.file, this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          title ?? file.uri.pathSegments.last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: '用系统程序打开',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => MediaUtils.openWithSystem(file.path),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6,
          child: Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '图片无法显示（文件可能已损坏或格式不支持）',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 录音播放器：打开即播放，带播放 / 暂停、进度条与时长；
/// 失败时把原因显示在界面上（不再「点了没反应」）。
class AudioPlayerPage extends StatefulWidget {
  final File file;
  final String? title;

  const AudioPlayerPage({super.key, required this.file, this.title});

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _ready = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
    );
    _subs.add(
      _player.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _position = pos);
      }),
    );
    _subs.add(
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }),
    );
    _subs.add(
      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
        }
      }),
    );
    _init();
  }

  Future<void> _init() async {
    final f = widget.file;
    if (!await f.exists()) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '录音文件不存在：\n${f.path}\n\n可能已被移动、重命名或删除。';
      });
      return;
    }
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(DeviceFileSource(f.path));
      if (!mounted) return;
      setState(() {
        _loading = false;
        _ready = true;
      });
      await _player.resume();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法播放这段录音：$e';
      });
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.resume();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '播放失败：$e');
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final max = _duration.inMilliseconds;
    final value = _position.inMilliseconds.clamp(0, max <= 0 ? 0 : max).toDouble();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ?? '录音',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.graphic_eq, size: 72, color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(
              widget.title ?? widget.file.uri.pathSegments.last,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              formatMediaSize(widget.file.existsSync() ? widget.file.lengthSync() : 0),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  _error!,
                  style: const TextStyle(fontSize: 13, color: AppTheme.danger),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '可尝试用系统默认程序打开这个音频文件。',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('用系统程序打开'),
                onPressed: () => MediaUtils.openWithSystem(widget.file.path),
              ),
            ],
            if (_ready && _error == null) ...[
              Slider(
                value: value,
                max: max <= 0 ? 1 : max.toDouble(),
                onChanged: max <= 0
                    ? null
                    : (v) => _player.seek(Duration(milliseconds: v.round())),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_fmt(_position), style: const TextStyle(fontSize: 12)),
                  Text(
                    max <= 0 ? '--:--' : _fmt(_duration),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: Icon(
                  _playing ? Icons.pause : Icons.play_arrow,
                  size: 22,
                ),
                label: Text(_playing ? '暂停' : '播放'),
                onPressed: _toggle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 已添加附件的**缩略图条**（日记 / 待办 / 任务 / 笔记共用）。
///
/// 为什么要有它：以前加完附件，界面上只有底部一个「附件(n)」计数按钮，
/// 正文区空空的 —— 得再点开弹层、再一条条点开才看得到内容，
/// 用起来像「慢一拍」。这里让附件**加完就铺开**：
/// - 照片直接显示真实缩略图，视频 / 录音 / 文件给块状图标；
/// - 新附件排在最右，数量增加时**自动滚到它**；
/// - 点缩略图打开（大图 / 播放 / 交给系统程序），右上角 × 移除。
class MediaThumbStrip extends StatefulWidget {
  final List<MediaAttachment> media;

  /// 内嵌附件所在目录（绝对路径）；null = 路径未知（尚未保存的新条目）
  final String? mediaDir;

  /// 传 null 表示不显示删除按钮（只读展示）
  final void Function(MediaAttachment media)? onRemove;

  final double thumbSize;
  final EdgeInsetsGeometry padding;

  const MediaThumbStrip({
    super.key,
    required this.media,
    this.mediaDir,
    this.onRemove,
    this.thumbSize = 76,
    this.padding = const EdgeInsets.fromLTRB(10, 4, 10, 6),
  });

  @override
  State<MediaThumbStrip> createState() => _MediaThumbStripState();
}

class _MediaThumbStripState extends State<MediaThumbStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(MediaThumbStrip old) {
    super.didUpdateWidget(old);
    // 又多了一个附件 → 滚到最右边，让新加的那个出现在视野里
    if (widget.media.length > old.media.length) _scrollToEndSoon();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEndSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) return;
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: widget.padding,
      child: SizedBox(
        height: widget.thumbSize + 6,
        child: ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          itemCount: widget.media.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final m = widget.media[i];
            return _thumb(m, () {
              final cb = widget.onRemove;
              if (cb != null) cb(m);
            });
          },
        ),
      ),
    );
  }

  Widget _thumb(MediaAttachment m, VoidCallback onRemove) {
    final file = resolveMediaFile(m, widget.mediaDir);
    final name = mediaDisplayName(m);
    final size = widget.thumbSize;
    Widget content;
    if (m.type == MediaType.photo && file != null && file.existsSync()) {
      content = Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _iconBlock(m.type, size),
      );
    } else {
      content = _iconBlock(m.type, size);
    }
    return Tooltip(
      message: '$name（点一下打开）',
      waitDuration: const Duration(milliseconds: 300),
      child: Stack(
        children: [
          InkWell(
            onTap: () => openAttachment(context, m, mediaDir: widget.mediaDir),
            borderRadius: BorderRadius.circular(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: size, height: size, child: content),
            ),
          ),
          if (widget.onRemove != null)
            Positioned(
              right: 0,
              top: 0,
              child: InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xCC000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconBlock(MediaType type, double size) {
    return Container(
      width: size,
      height: size,
      color: AppTheme.primary.withValues(alpha: 0.08),
      child: Center(
        child: Icon(mediaTypeIcon(type), size: 26, color: AppTheme.primary),
      ),
    );
  }
}

/// 添加附件后的即时提示（各编辑页共用）：加了什么、一共几个。
void showAttachmentAddedToast(
  BuildContext context,
  MediaType type,
  int total,
) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('已添加${mediaTypeLabel(type)} · 共 $total 个附件'),
        duration: const Duration(seconds: 2),
      ),
    );
}
