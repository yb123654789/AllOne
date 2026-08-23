import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// 富文本编辑器封装（基于 flutter_quill）。
/// 供日记、待办等模块共用，支持手机/电脑两种键盘习惯（触屏 + 键盘快捷键）。
class RichTextEditor extends StatefulWidget {
  final QuillController controller;
  final String? placeholder;
  final bool showToolbar;
  final EdgeInsets padding;

  const RichTextEditor({
    super.key,
    required this.controller,
    this.placeholder,
    this.showToolbar = true,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  State<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showToolbar) ...[
          QuillSimpleToolbar(
            controller: widget.controller,
            config: const QuillSimpleToolbarConfig(
              showFontFamily: false,
              showFontSize: false,
              showHeaderStyle: true,
              showListNumbers: true,
              showListBullets: true,
              showListCheck: true,
              showColorButton: true,
              showBackgroundColorButton: false,
              showAlignmentButtons: true,
              showIndent: false,
              showLink: true,
              showSubscript: false,
              showSuperscript: false,
              showStrikeThrough: true,
              showInlineCode: false,
              showBoldButton: true,
              showItalicButton: true,
              showUnderLineButton: true,
              showUndo: true,
              showRedo: true,
            ),
          ),
          Container(
            width: double.infinity,
            color: const Color(0x0A2F6FED),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: const Text(
              '💡 先点击正文获得光标，或选中文字，再用上方工具栏设置 加粗 · 斜体 · 变色 · 列表 等格式',
              style: TextStyle(fontSize: 11, color: Color(0xFF2F6FED)),
            ),
          ),
        ],
        Expanded(
          child: QuillEditor.basic(
            controller: widget.controller,
            focusNode: _focusNode,
            scrollController: _scrollController,
            config: QuillEditorConfig(
              placeholder: widget.placeholder,
              expands: false,
              padding: widget.padding,
              scrollable: true,
              autoFocus: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// Delta JSON <-> Document / 纯文本 转换工具
class QuillCodec {
  QuillCodec._();

  /// 把 Document 序列化为 Delta JSON 字符串
  static String encode(Document doc) => jsonEncode(doc.toDelta().toJson());

  /// 从 Delta JSON 字符串还原 Document；非法输入返回空文档
  static Document decode(String? json) {
    if (json == null || json.isEmpty) return Document();
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) return Document.fromJson(decoded);
      return Document();
    } catch (_) {
      return Document();
    }
  }

  /// 从 Delta JSON 提取纯文本（用于 txt 通用格式）
  static String toPlainText(String? json) => decode(json).toPlainText();
}
