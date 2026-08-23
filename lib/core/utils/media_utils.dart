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
  static Future<bool> requestMicPermission() async {
    final s = await Permission.microphone.request();
    return s.isGranted;
  }

  /// 开始录音到指定路径
  static Future<void> startRecording(String path) async {
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) return;
    await recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
  }

  /// 停止录音，返回文件路径
  static Future<String?> stopRecording() async {
    final recorder = AudioRecorder();
    return recorder.stop();
  }

  static Future<bool> isRecording() async {
    final recorder = AudioRecorder();
    return recorder.isRecording();
  }

  // —— 播放 ——
  static Future<void> playAudio(String path) async {
    final player = AudioPlayer();
    await player.play(DeviceFileSource(path));
  }
}
