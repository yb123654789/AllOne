import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 内嵌视频播放器（基于 video_player）。
///
/// 用于播放本地视频附件（Android / iOS / Web 支持；桌面端若无对应实现会提示不支持）。
class VideoViewer extends StatefulWidget {
  final File file;

  const VideoViewer({super.key, required this.file});

  @override
  State<VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<VideoViewer> {
  VideoPlayerController? _controller;
  String? _error;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.file(widget.file);
      _controller = controller;
      await controller.initialize();
      controller.setLooping(false);
      if (!mounted) return;
      setState(() => _initialized = true);
      controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '当前平台暂不支持内嵌视频播放：$e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            )
          : !_initialized || controller == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: controller.value.aspectRatio <= 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          controller.value.isPlaying
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                          color: Colors.white,
                          size: 40,
                        ),
                        onPressed: () {
                          setState(() {
                            controller.value.isPlaying
                                ? controller.pause()
                                : controller.play();
                          });
                        },
                      ),
                      _positionText(controller),
                    ],
                  ),
                  _progressBar(controller),
                ],
              ),
            ),
    );
  }

  Widget _positionText(VideoPlayerController controller) {
    final pos = controller.value.position;
    final dur = controller.value.duration;
    String fmt(Duration d) =>
        '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Text(
      '${fmt(pos)} / ${fmt(dur)}',
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    );
  }

  Widget _progressBar(VideoPlayerController controller) {
    final dur = controller.value.duration;
    if (dur.inMilliseconds <= 0) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: VideoProgressIndicator(
        controller,
        allowScrubbing: true,
        colors: const VideoProgressColors(
          playedColor: Colors.white,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white12,
        ),
      ),
    );
  }
}
