import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/tag_dialogs.dart';
import 'diary_import.dart';
import 'diary_models.dart';
import 'diary_pdf_images.dart';
import 'diary_pdf_text.dart';
import 'diary_repository.dart';

/// 导入外部日记（其他软件的 txt / PDF）。
///
/// **不覆盖现有日记**：解析后先预览、可勾选，导入时每篇都分配全新 ID 新增写入，
/// 已有日记不会被修改或删除。
class DiaryImportPage extends ConsumerStatefulWidget {
  const DiaryImportPage({super.key});

  @override
  ConsumerState<DiaryImportPage> createState() => _DiaryImportPageState();
}

/// 已读取的源文件（保留原文，便于切换切分方式后重新解析）
class _SourceText {
  final String name;
  final String text;
  final DateTime? fileDate;
  const _SourceText({
    required this.name,
    required this.text,
    required this.fileDate,
  });
}

/// 已解析的 PDF 源文件。
///
/// PDF 的解析（提取文本行 + 抽出内嵌照片 + 按日期分篇）开销大，
/// 所以只在选文件时做一次，结果缓存在这里；
/// 之后切换切分选项时不必重新解析。
class _PdfSource {
  final String name;

  /// 解析出的日记草稿（已带归属好的图片）
  final List<DiaryImportDraft> drafts;
  const _PdfSource({required this.name, required this.drafts});
}

class _DiaryImportPageState extends ConsumerState<DiaryImportPage> {
  final List<_SourceText> _sources = [];
  final List<_PdfSource> _pdfSources = [];
  final List<String> _errors = [];
  List<DiaryImportDraft> _drafts = [];

  DiaryImportSplit _split = DiaryImportSplit.auto;
  bool _useFileNameDate = true;
  bool _skipDuplicates = true;
  List<String> _tags = ['导入'];

  bool _busy = false;
  String _status = '';
  Set<String> _existingKeys = {};

  int get _selectedCount => _drafts
      .where((d) => d.selected && !(_skipDuplicates && d.duplicate))
      .length;

  /// 已读取的源文件总数（txt + pdf）
  int get _fileCount => _sources.length + _pdfSources.length;

  /// 已读取的源文件名（txt + pdf）
  List<String> get _sourceNames => [
    for (final s in _sources) s.name,
    for (final p in _pdfSources) p.name,
  ];

  /// 源文件名的展示文本
  String get _sourceNamesText => _sourceNames.join('、');

  /// 已选草稿带的总图片数（用于底部按钮提示）
  int get _selectedImageCount => _drafts
      .where((d) => d.selected && !(_skipDuplicates && d.duplicate))
      .fold<int>(0, (s, d) => s + d.imageCount);

  @override
  void initState() {
    super.initState();
    // 现有日记指纹（用于标记疑似重复），不修改任何数据
    _existingKeys = diaryFingerprints(
      ref.read(diaryListProvider).valueOrNull ?? const <DiaryEntry>[],
    );
  }

  // ---------------------------------------------------------------- 文件读取

  Future<void> _pickFiles() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在选择文件…';
      _errors.clear();
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'pdf'],
        allowMultiple: true,
        withData: true,
      );
      final files = result?.files ?? const <PlatformFile>[];
      if (files.isEmpty) return;

      // 每次选择前刷新一次现有日记指纹
      _existingKeys = diaryFingerprints(
        ref.read(diaryListProvider).valueOrNull ?? const <DiaryEntry>[],
      );

      for (final f in files) {
        setState(() => _status = '正在解析：${f.name}');
        final bytes = await _readBytes(f);
        if (bytes == null || bytes.isEmpty) {
          _errors.add('${f.name}：无法读取文件内容');
          continue;
        }
        final ext = _extensionOf(f);
        if (ext == 'pdf') {
          // PDF 走专门流程：提文本 + 抽出内嵌照片 + 按日期分篇并归图
          try {
            final parsed = _parsePdf(f.name, bytes);
            if (parsed.isEmpty) {
              _errors.add('${f.name}：未提取到文字，可能是扫描件（图片型 PDF），需先做 OCR');
              continue;
            }
            _pdfSources.add(_PdfSource(name: f.name, drafts: parsed));
          } catch (e) {
            _errors.add('${f.name}：PDF 解析失败（$e）');
          }
          continue;
        }
        final text = decodeDiaryText(bytes);
        if (text.trim().isEmpty) {
          _errors.add('${f.name}：文件内容为空');
          continue;
        }
        _sources.add(
          _SourceText(
            name: f.name,
            text: text,
            fileDate: parseDateFromFileName(f.name),
          ),
        );
      }
    } catch (e) {
      _errors.add('选择文件失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
          _drafts = _buildDrafts();
        });
      }
    }
    if (mounted && _errors.isNotEmpty) await _showErrors();
  }

  Future<List<int>?> _readBytes(PlatformFile f) async {
    if (f.bytes != null) return f.bytes;
    final path = f.path;
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  String _extensionOf(PlatformFile f) {
    final e = f.extension?.toLowerCase();
    if (e != null && e.isNotEmpty) return e;
    final name = f.name.toLowerCase();
    final i = name.lastIndexOf('.');
    return i >= 0 ? name.substring(i + 1) : '';
  }

  /// 把 PDF 源解析成草稿（含内嵌照片的归属）。
  ///
  /// 只在选文件时调用一次；结果缓存在 [_PdfSource]，之后切分选项变化不再重解析。
  List<DiaryImportDraft> _parsePdf(String fileName, List<int> bytes) {
    final lines = DiaryPdfText.extractLines(bytes);
    final images = PdfJpegExtractor.extractWithPages(bytes);
    final pdfDrafts = buildDraftsFromPdf(
      lines: lines,
      images: images,
      dateRe: _pdfDateRe,
    );
    final source = sourceNameWithoutExtension(fileName);
    return [
      for (final d in pdfDrafts)
        DiaryImportDraft(
          sourceName: source,
          title: _titleFromPdfText(d),
          plainText: _bodyWithoutTitle(d),
          date: d.date == null ? null : DateTime.tryParse(d.date!),
          attachedImages: d.images,
        ),
    ];
  }

  /// PDF 的日期行识别用正则（「一本日记」导出为 `2026年03月08日`）
  static final RegExp _pdfDateRe = RegExp(
    r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日',
  );

  /// 取正文首行做标题（去掉日期行；末尾单个「。」是排版残渣，一并去掉）
  String _titleFromPdfText(PdfImportDraft d) {
    final lines = d.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return d.date ?? '';
    var first = lines.first;
    first = first.replaceAll(RegExp(r'。$'), '').trim();
    if (first.isEmpty) return d.date ?? '';
    return first.length > 40 ? '${first.substring(0, 40)}…' : first;
  }

  /// 正文 = 去掉被当作标题的首行
  String _bodyWithoutTitle(PdfImportDraft d) {
    final lines = d.text.split('\n').toList();
    // 找第一个非空行并去掉（它就是标题）
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) {
        lines.removeAt(i);
        break;
      }
    }
    return lines.join('\n').trim();
  }

  /// 重新切分所有源文件（切换选项后调用）
  List<DiaryImportDraft> _buildDrafts() {
    final drafts = <DiaryImportDraft>[];
    for (final s in _sources) {
      drafts.addAll(
        splitDiaryText(
          s.text,
          sourceName: sourceNameWithoutExtension(s.name),
          split: _split,
          fileDate: _useFileNameDate ? s.fileDate : null,
        ),
      );
    }
    // PDF 已解析好的草稿直接并入（图片归属在解析时已完成）
    for (final p in _pdfSources) {
      drafts.addAll(p.drafts);
    }
    for (final d in drafts) {
      d.duplicate = _existingKeys.contains(d.fingerprint);
    }
    return drafts;
  }

  void _resplit() => setState(() => _drafts = _buildDrafts());

  // ------------------------------------------------------------------ 导入

  Future<void> _import() async {
    final selected = _drafts
        .where((d) => d.selected && !(_skipDuplicates && d.duplicate))
        .toList();
    if (selected.isEmpty) {
      _snack('请先勾选要导入的日记');
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在导入 ${selected.length} 篇…';
    });
    try {
      final selected = _drafts
          .where((d) => d.selected && !(_skipDuplicates && d.duplicate))
          .toList();
      // 草稿 → 条目；同时记住每篇带的图片，导入时一起落盘
      final entryImages = <String, List<Uint8List>>{};
      final entries = <DiaryEntry>[];
      for (final d in selected) {
        final e = d.toEntry(tags: _tags);
        entries.add(e);
        if (d.attachedImages.isNotEmpty) {
          entryImages[e.id] = d.attachedImages;
        }
      }
      final totalImages = entryImages.values.fold<int>(
        0,
        (s, v) => s + v.length,
      );
      final n = await ref
          .read(diaryListProvider.notifier)
          .importEntries(
            entries,
            imagesOf: (e) => entryImages[e.id] ?? const [],
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入完成'),
          content: Text(
            '已新增 $n 篇日记'
            '${totalImages > 0 ? '，含 $totalImages 张照片' : ''}。\n'
            '${_drafts.length - selected.length} 篇未导入（未勾选或已跳过重复）。\n\n'
            '原有日记未做任何修改或删除。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('好'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
      _snack('导入失败：$e');
    }
  }

  Future<void> _showErrors() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('部分文件未导入'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('以下文件无法解析，可先在原软件中导出为 txt 再试：'),
              const SizedBox(height: 8),
              for (final e in _errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('· $e', style: const TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickTags() async {
    final all = <String>{
      for (final e
          in ref.read(diaryListProvider).valueOrNull ?? const <DiaryEntry>[])
        ...e.tags,
      ..._tags,
    }.toList();
    final picked = await showTagPicker(
      context,
      allTags: all,
      initial: _tags,
      title: '导入后统一添加的标签',
    );
    if (picked != null) setState(() => _tags = picked);
  }

  Future<void> _previewDraft(DiaryImportDraft d) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(d.title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '日期：${d.date == null ? '未识别（用导入时间）' : _fmtDateTime(d.date!)}'
                  '　字数：${d.charCount}'
                  '${d.imageCount > 0 ? '　照片：${d.imageCount} 张' : ''}\n'
                  '来源：${d.sourceName}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (d.attachedImages.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('随本篇导入的照片', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: d.attachedImages.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          d.attachedImages[i],
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 84,
                            height: 84,
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: const Text(
                              '无法显示',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                SelectableText(
                  d.plainText.isEmpty ? '（正文为空）' : d.plainText,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}'
        '${d.hour == 0 && d.minute == 0 ? '' : ' ${two(d.hour)}:${two(d.minute)}'}';
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入外部日记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '使用说明',
            onPressed: _showHelp,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [_noticeCard(), _fileCard(), _optionCard(), _previewCard()],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _noticeCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 18, color: Colors.green),
              const SizedBox(width: 6),
              const Text(
                '导入不会覆盖现有日记',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '· 支持其他软件导出的 .txt（自动识别 UTF-8 / GBK 编码，不乱码）与文本型 .pdf；\n'
            '· 解析结果先预览、逐篇勾选，确认后才写入；每篇都作为新日记新增，'
            '原有日记不会被修改或删除；\n'
            '· 识别到的日期会作为日记日期，这样日历 / 时间轴顺序与原来一致；\n'
            '· 扫描件（图片型 PDF）没有文字层，请先在原软件导出 txt 或 PDF 文字版。',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _fileCard() => Card(
    child: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.upload_file, color: AppTheme.primary),
          title: const Text('选择文件'),
          subtitle: Text(
            (_sources.isEmpty && _pdfSources.isEmpty)
                ? '可多选：.txt / .pdf（其他软件的日记导出文件）'
                : '已读取 $_fileCount 个文件：$_sourceNamesText',
          ),
          isThreeLine: _fileCount > 0,
          trailing: const Icon(Icons.add, size: 20),
          onTap: _busy ? null : _pickFiles,
        ),
        if (_busy || _status.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _status.isEmpty ? '处理中…' : _status,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_sources.isNotEmpty || _pdfSources.isNotEmpty) ...[
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.delete_sweep_outlined, size: 20),
            title: const Text('清空已读取的文件', style: TextStyle(fontSize: 14)),
            onTap: _busy
                ? null
                : () => setState(() {
                    _sources.clear();
                    _pdfSources.clear();
                    _drafts = [];
                  }),
          ),
        ],
      ],
    ),
  );

  Widget _optionCard() => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '导入选项',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<DiaryImportSplit>(
            initialValue: _split,
            decoration: const InputDecoration(labelText: '分篇方式', isDense: true),
            items: [
              for (final s in DiaryImportSplit.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _split = v);
                    _resplit();
                  },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              _split.hint,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('用文件名中的日期'),
            subtitle: const Text(
              '如「2024-05-01 日记.txt」→ 日记日期取 2024-05-01',
              style: TextStyle(fontSize: 12),
            ),
            value: _useFileNameDate,
            onChanged: _busy
                ? null
                : (v) {
                    setState(() => _useFileNameDate = v);
                    _resplit();
                  },
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('跳过与现有日记重复的篇目'),
            subtitle: const Text(
              '按「标题 + 日期 + 正文」比对，重复项默认不导入',
              style: TextStyle(fontSize: 12),
            ),
            value: _skipDuplicates,
            onChanged: _busy
                ? null
                : (v) => setState(() => _skipDuplicates = v),
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('导入后统一加的标签：'),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.local_offer_outlined, size: 18),
                label: const Text('选择'),
                onPressed: _busy ? null : _pickTags,
              ),
            ],
          ),
          if (_tags.isEmpty)
            const Text(
              '未设置（不添加标签）',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in _tags)
                  InputChip(
                    label: Text(t),
                    onDeleted: _busy
                        ? null
                        : () => setState(() => _tags.remove(t)),
                  ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _previewCard() {
    if (_drafts.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '尚未解析出内容：请先选择 txt / PDF 文件。',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
      );
    }
    final dup = _drafts.where((d) => d.duplicate).length;
    return Card(
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text(
              '解析预览：共 ${_drafts.length} 篇'
              '${dup > 0 ? '，其中 $dup 篇疑似重复' : ''}',
            ),
            subtitle: Text('已勾选 $_selectedCount 篇将导入'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          for (final d in _drafts) {
                            d.selected = true;
                          }
                        }),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          for (final d in _drafts) {
                            d.selected = false;
                          }
                        }),
                  child: const Text('全不选'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final d in _drafts) ...[
            CheckboxListTile(
              dense: true,
              value: d.selected,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => d.selected = v ?? false),
              title: Text(
                d.title.isEmpty ? '（无标题）' : d.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${d.date == null ? '日期未识别（用导入时间）' : _fmtDateTime(d.date!)}'
                '　${d.charCount} 字　来自 ${d.sourceName}'
                '${d.imageCount > 0 ? '　· 含 ${d.imageCount} 张照片' : ''}'
                '${_skipDuplicates && d.duplicate ? '　· 疑似重复（已跳过）' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              secondary: IconButton(
                icon: Icon(
                  d.imageCount > 0
                      ? Icons.photo_library_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                tooltip: d.imageCount > 0 ? '预览正文与照片' : '预览正文',
                onPressed: () => _previewDraft(d),
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: const Icon(Icons.download_done),
          label: Text(
            _drafts.isEmpty
                ? '导入（请先选择文件）'
                : '导入选中的 $_selectedCount 篇'
                      '${_selectedImageCount > 0 ? '（含 $_selectedImageCount 张照片）' : ''}',
          ),
          onPressed: (_busy || _selectedCount == 0) ? null : _import,
        ),
      ),
    ),
  );

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入外部日记'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '用途：把之前在其他软件（记事本、印象笔记、OneNote、'
                '日记 App 等）写的日记搬到 AllOne。',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
              SizedBox(height: 10),
              Text('步骤', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 4),
              Text(
                '1. 在原软件里把日记导出为 txt（首选）或 PDF；\n'
                '2. 回到本页选择文件，程序自动识别编码与日期；\n'
                '3. 检查预览，取消不想导入的篇目；\n'
                '4. 点击「导入选中的 N 篇」。',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              SizedBox(height: 10),
              Text('导入规则', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 4),
              Text(
                '· 只新增，不覆盖、不删除任何已有日记；\n'
                '· 日期行（如「2024年5月1日 晴」）会被识别为分篇依据与日记日期；\n'
                '· 疑似重复（标题/日期/正文都相同）默认跳过，可关闭该开关强制导入。',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
