import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:allone/core/models/common.dart';
import 'package:allone/core/widgets/attachment_view.dart';

/// 附件「点一下就能打开」相关纯逻辑测试：
/// 显示名、体积格式、路径解析（决定附件能不能被打开）。
void main() {
  group('附件显示与路径', () {
    test('显示名去掉落盘时的毫秒前缀', () {
      const m = MediaAttachment(
        type: MediaType.audio,
        file: '1787658907441_rec.m4a',
        size: 1024,
      );
      expect(mediaDisplayName(m), 'rec.m4a');
    });

    test('显示名对外链取文件名', () {
      const m = MediaAttachment(
        type: MediaType.videoLink,
        external: r'D:\Videos\旅行.mp4',
        note: '大文件外链',
      );
      expect(mediaDisplayName(m), '旅行.mp4');
    });

    test('显示名对空附件不崩溃', () {
      const m = MediaAttachment(type: MediaType.file);
      expect(mediaDisplayName(m), '（未知附件）');
    });

    test('体积格式化', () {
      expect(formatMediaSize(0), '大小未知');
      expect(formatMediaSize(512), '512 B');
      expect(formatMediaSize(2048), '2.0 KB');
      expect(formatMediaSize(5 * 1024 * 1024), '5.0 MB');
      expect(formatMediaSize(2 * 1024 * 1024 * 1024), '2.00 GB');
    });

    test('内嵌附件 = 目录 + 文件名', () {
      const m = MediaAttachment(type: MediaType.audio, file: 'a.m4a');
      final f = resolveMediaFile(m, p.join('C:', 'data', 'diary', 'entries', 'x', 'media'));
      expect(f, isNotNull);
      expect(f!.path, endsWith(p.join('media', 'a.m4a')));
    });

    test('目录未知时不给出错误路径（新条目尚未保存）', () {
      const m = MediaAttachment(type: MediaType.audio, file: 'a.m4a');
      expect(resolveMediaFile(m, null), isNull);
    });

    test('外链形式（大文件）按原始路径解析', () {
      const m = MediaAttachment(type: MediaType.video, external: r'D:\Videos\a.mp4');
      final f = resolveMediaFile(m, null);
      expect(f, isNotNull);
      expect(f!.path, r'D:\Videos\a.mp4');
    });

    test('网址不会被当成文件路径', () {
      const m = MediaAttachment(
        type: MediaType.videoLink,
        external: 'https://example.com/a.mp4',
      );
      expect(resolveMediaFile(m, null), isNull);
    });

    test('附件类型中文名与图标齐全（5 种类型都有）', () {
      for (final t in MediaType.values) {
        expect(mediaTypeLabel(t), isNotEmpty);
        expect(mediaTypeIcon(t), isNotNull);
      }
    });
  });
}
