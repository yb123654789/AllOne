import 'package:flutter_test/flutter_test.dart';

import 'package:allone/core/updater/update_models.dart';
import 'package:allone/core/updater/update_service.dart';

/// 应用内更新的纯逻辑测试：
/// 版本比较错了会导致「有新版本却提示已是最新」（或反之），
/// 产物挑错了会让手机下到 Windows 安装包。
void main() {
  group('更新 - 版本号', () {
    test('去掉 v 前缀与 +build 后缀', () {
      expect(normalizeVersion('v1.2.3'), '1.2.3');
      expect(normalizeVersion('1.2.3+4'), '1.2.3');
      expect(normalizeVersion('V1.2.3+4'), '1.2.3');
      expect(normalizeVersion(' 1.2.3 '), '1.2.3');
    });

    test('按数字比较，不是按字符串', () {
      expect(compareVersions('1.2.10', '1.2.9'), 1);
      expect(compareVersions('1.2.9', '1.2.10'), -1);
      expect(compareVersions('1.10.0', '1.9.9'), 1);
      expect(compareVersions('2.0.0', '1.99.99'), 1);
    });

    test('段数不同时缺的按 0 算', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.0', '1.2'), 0);
      expect(compareVersions('1.2.1', '1.2'), 1);
    });

    test('带 v 前缀与 build 号也能比较', () {
      expect(compareVersions('v1.2.3', '1.2.2'), 1);
      expect(compareVersions('1.2.2+4', '1.2.2+3'), 0);
    });

    test('isNewerVersion', () {
      expect(isNewerVersion('1.2.3', '1.2.2'), isTrue);
      expect(isNewerVersion('1.2.2', '1.2.2'), isFalse);
      expect(isNewerVersion('1.2.1', '1.2.2'), isFalse);
    });
  });

  group('更新 - 产物选择', () {
    test('按文件名判断平台', () {
      expect(targetOfAsset('AllOne_Setup_v1.2.3.exe'), UpdateTarget.windows);
      expect(targetOfAsset('allone_setup_v1.2.3.exe'), UpdateTarget.windows);
      expect(targetOfAsset('AllOne-v1.2.3.apk'), UpdateTarget.android);
      expect(targetOfAsset('AllOne-v1.2.3-Windows.zip'), UpdateTarget.other);
      expect(targetOfAsset('some.dmg'), UpdateTarget.other);
    });

    test('从文件名取版本号', () {
      expect(versionFromAssetName('AllOne_Setup_v1.2.3.exe'), '1.2.3');
      expect(versionFromAssetName('AllOne-v1.2.10.apk'), '1.2.10');
      expect(versionFromAssetName('AllOne-v1.3-Windows.zip'), '1.3');
      expect(versionFromAssetName('no-version-here.exe'), '');
    });

    test('体积显示', () {
      expect(const UpdateAsset(name: 'a', url: 'u', size: 0).sizeText, '大小未知');
      expect(
        const UpdateAsset(name: 'a', url: 'u', size: 500 * 1024).sizeText,
        '500 KB',
      );
      expect(
        const UpdateAsset(name: 'a', url: 'u', size: 12 * 1024 * 1024).sizeText,
        '12.0 MB',
      );
    });
  });

  group('更新 - 解析 GitHub Releases', () {
    final sample = {
      'tag_name': 'v1.2.3',
      'body': '## 更新内容\n- 附件点一下即打开\n- 课程表双视图',
      'published_at': '2026-10-08T10:00:00Z',
      'assets': [
        {
          'name': 'AllOne-v1.2.3-Windows.zip',
          'browser_download_url': 'https://example.com/zip',
          'size': 13000000,
        },
        {
          'name': 'AllOne_Setup_v1.2.3.exe',
          'browser_download_url': 'https://example.com/setup',
          'size': 12000000,
        },
        {
          'name': 'AllOne-v1.2.3.apk',
          'browser_download_url': 'https://example.com/apk',
          'size': 50000000,
        },
      ],
    };

    test('解析版本 / 说明 / 各平台产物', () {
      final info = parseLatestRelease(sample)!;
      expect(info.version, '1.2.3');
      expect(info.tag, 'v1.2.3');
      expect(info.notes, contains('附件点一下即打开'));
      expect(info.windows!.name, 'AllOne_Setup_v1.2.3.exe');
      expect(info.windows!.url, 'https://example.com/setup');
      expect(info.android!.name, 'AllOne-v1.2.3.apk');
      expect(info.assetFor(UpdateTarget.windows)!.size, 12000000);
      expect(info.assetFor(UpdateTarget.android)!.name, 'AllOne-v1.2.3.apk');
      expect(info.assetFor(UpdateTarget.other), isNull);
      expect(info.publishedAt, '2026-10-08T10:00:00Z');
    });

    test('没有对应产物时为 null（但仍算一次有效更新）', () {
      final info = parseLatestRelease({
        'tag_name': 'v9.9.9',
        'assets': <dynamic>[],
      })!;
      expect(info.version, '9.9.9');
      expect(info.windows, isNull);
      expect(info.android, isNull);
      expect(info.notes, isEmpty);
    });

    test('缺少 tag 时返回 null', () {
      expect(parseLatestRelease({'body': 'x'}), isNull);
      expect(parseLatestRelease({'tag_name': ''}), isNull);
      expect(parseLatestRelease({'tag_name': 'v'}), isNull);
    });

    test('assets 字段异常也不崩', () {
      final info = parseLatestRelease({
        'tag_name': 'v1.0.0',
        'assets': '不是列表',
      })!;
      expect(info.windows, isNull);
    });

    test('zip 不会被误判成安装包', () {
      final info = parseLatestRelease({
        'tag_name': 'v1.0.0',
        'assets': [
          {
            'name': 'AllOne-v1.0.0-Windows.zip',
            'browser_download_url': 'https://example.com/zip',
          },
        ],
      })!;
      expect(info.windows, isNull);
    });
  });

  group('更新 - 数据安全', () {
    test('从会删数据的旧版本升级时，需要先备份', () {
      expect(UpdateService.needsBackupBeforeUpdate('1.2.1'), isTrue);
      expect(UpdateService.needsBackupBeforeUpdate('1.1.0'), isTrue);
      expect(UpdateService.needsBackupBeforeUpdate('1.2.2'), isFalse);
      expect(UpdateService.needsBackupBeforeUpdate('1.3.0'), isFalse);
    });
  });
}
