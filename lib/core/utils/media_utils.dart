import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// 多媒体工具：选图、选文件、录音、播放。
/// 各模块（日记/待办）共用。
class MediaUtils {
  MediaUtils._();

  /// 从相册选一张图
  static Future<File?> pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    return x == null ? null : File(x.path);
  }

  /// 选择任意文件
  static Future<File?> pickAnyFile() async {
    final r = await FilePicker.platform.pickFiles();
    final p = r?.files.single.path;
    return p == null ? null : File(p);
  }

  /// 把源文件复制到指定目录，返回目标路径（返回相对目录的文件名）
  static Future<String?> copyToDir(File src, Directory destDir) async {
    if (!await destDir.exists()) await destDir.create(recursive: true);
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${src.uri.pathSegments.last}';
    final dest = File('${destDir.path}${Platform.pathSeparator}$name');
    await src.copy(dest.path);
    return name;
  }

  // —— 录音 ——

  /// 全局唯一的录音器实例。
  ///
  /// **必须复用同一个实例**：`record` 插件的录音状态保存在实例内部，
  /// 若 [startRecording] 与 [stopRecording] 各自 new 一个 [AudioRecorder]，
  /// 那么 stop 操作的是另一个"从未开始录音"的对象，会返回 null，
  /// 于是这段录音既不会被登记为附件、也拿不到文件路径，
  /// 却仍在后台持续写入 —— 最终留下体积巨大、界面里看不到的孤立录音文件
  /// （真实数据中曾出现两段各 500+ MB 的 `*_rec.m4a`）。
  static AudioRecorder? _recorder;

  static AudioRecorder get _rec {
    final r = _recorder;
    if (r != null) return r;
    final created = AudioRecorder();
    _recorder = created;
    return created;
  }

  static Future<bool> requestMicPermission() async {
    final s = await Permission.microphone.request();
    return s.isGranted;
  }

  /// 开始录音到指定路径。返回是否真正开始（无权限时返回 false）。
  static Future<bool> startRecording(String path) async {
    if (!await _rec.hasPermission()) return false;
    await _rec.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    return true;
  }

  /// 停止录音，返回文件路径（未在录音时返回 null）
  static Future<String?> stopRecording() => _rec.stop();

  static Future<bool> isRecording() => _rec.isRecording();

  // —— 播放 ——

  /// 全局唯一的播放器实例（避免每次播放都新建、导致无法暂停/停止）
  static AudioPlayer? _player;

  static AudioPlayer get _play {
    final p = _player;
    if (p != null) return p;
    final created = AudioPlayer();
    _player = created;
    return created;
  }

  static Future<void> playAudio(String path) async {
    await _play.stop();
    await _play.play(DeviceFileSource(path));
  }

  /// 用系统默认程序打开本地文件或网址（Windows / macOS / Linux）。
  ///
  /// 移动端没有系统级「打开方式」，会返回 false，由调用方给出提示。
  /// 返回值表示是否**成功发起**打开动作（不代表目标程序一定能解析该格式）。
  static Future<bool> openWithSystem(String target) async {
    if (target.trim().isEmpty) return false;
    try {
      if (Platform.isWindows) {
        // `start` 的第一个参数是窗口标题，必须用空串占位，
        // 否则含空格的路径会被当成窗口标题而打不开。
        await Process.start('cmd', ['/c', 'start', '', target]);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [target]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [target]);
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }
}
