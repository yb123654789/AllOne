import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'course_ocr.dart';

/// 从照片识别课程：选图 → 本地 OCR → 解析候选字段 → 用户确认后返回。
/// 通过 `Navigator.pop(context, CourseOcrResult)` 把结果带回编辑页。
class CourseOcrPage extends StatefulWidget {
  const CourseOcrPage({super.key});

  @override
  State<CourseOcrPage> createState() => _CourseOcrPageState();
}

class _CourseOcrPageState extends State<CourseOcrPage> {
  bool _busy = false;
  String? _error;
  CourseOcrResult? _result;

  Future<void> _recognize() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await recognizeCourseFromImage();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = res;
      if (res == null) _error = '未选择图片或未能识别';
    });
  }

  /// 确认使用识别结果，返回编辑页
  void _confirm() {
    final r = _result;
    if (r == null || !r.usable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择图片并完成识别')),
      );
      return;
    }
    Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('从照片识别课程')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _intro(),
                const SizedBox(height: 16),
                Center(
                  child: FilledButton.icon(
                    onPressed: _recognize,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('选择照片并识别'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.danger),
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    '识别结果（可修改后使用）',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _resultCard(_result!),
                  const SizedBox(height: 16),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _confirm,
                      icon: const Icon(Icons.check),
                      label: const Text('使用此结果'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _intro() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '拍照/选图识别课程信息（本地识别，不上传图片）',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '课程表照片一般是表格，识别后会自动提取课程名、教室、时间、星期、周次等候选字段。\n'
              '由于识别可能有误差，请务必核对后再保存。建议一次识别一节课，或识别后手动修正。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(CourseOcrResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('课程名', r.name),
            _row('教师', r.teacher),
            _row('教室', r.classroom),
            _row('星期', r.weekday == null ? '' : '周${_weekCn(r.weekday!)}'),
            _row('时间', '${r.startTime} - ${r.endTime}'),
            _row('周次', r.weeks),
            const Divider(),
            Text(
              '原文：\n${r.rawText}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '（未识别）' : value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _weekCn(int w) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return (w >= 1 && w <= 7) ? names[w - 1] : '$w';
  }
}
