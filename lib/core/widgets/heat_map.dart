import 'package:flutter/material.dart';

import '../models/common.dart';
import '../theme.dart';

/// 热力图的一格
class HeatCell {
  /// yyyy-MM-dd
  final String date;

  /// 该格颜色（语义由调用方决定）
  final Color color;

  /// 长按 / 悬停提示
  final String? tooltip;

  const HeatCell({required this.date, required this.color, this.tooltip});
}

/// 通用「日历热力图」：**列 = 周**（周一在最上，周日在下），最后一列是本周。
///
/// 有意不含任何业务语义：颜色、提示、周行头都由调用方给出，
/// 所以 core 层不依赖任何 feature（习惯模块把打卡状态映射成颜色即可）。
class HeatMap extends StatefulWidget {
  final List<HeatCell> cells;

  /// 显示多少周（含本周）
  final int weeks;

  /// 以哪一天为「本周」的锚点（yyyy-MM-dd），默认今天
  final String? anchorDate;

  final double cellSize;
  final double gap;

  /// 选中的日期（可点击模式下用于多选高亮）
  final Set<String> selected;

  /// 点击某一格；为 null 表示只读
  final void Function(String date)? onTapDay;

  /// 是否显示左侧「一/三/五」这类星期标记
  final bool showWeekdayLabels;

  /// 需要显示在列顶部的周行头：weekStart(yyyy-MM-dd) -> 文本（如「2/3」「✓」）
  final Map<String, String> weekHeaders;

  /// 是否用细框标出今天
  final bool highlightToday;

  /// 是否横向可滚动（大图用）
  final bool scrollable;

  const HeatMap({
    super.key,
    required this.cells,
    required this.weeks,
    this.anchorDate,
    this.cellSize = 12,
    this.gap = 3,
    this.selected = const {},
    this.onTapDay,
    this.showWeekdayLabels = false,
    this.weekHeaders = const {},
    this.highlightToday = true,
    this.scrollable = false,
  });

  /// 横向滚动区（测试与「滚到今天」定位用）
  static const scrollKey = ValueKey('heatmap-scroll');

  @override
  State<HeatMap> createState() => _HeatMapState();
}

class _HeatMapState extends State<HeatMap> {
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  final ScrollController _scroll = ScrollController();

  /// 已经做过「滚到最右（今天）」这一步了吗
  bool _jumped = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(HeatMap old) {
    super.didUpdateWidget(old);
    // 周数变了（比如换了习惯 / 改了一年的范围）→ 重新定位到今天
    if (old.weeks != widget.weeks || old.cells.length != widget.cells.length) {
      _jumped = false;
    }
  }

  /// 大图默认要看到**今天**，而不是停在一年前的那一端。
  ///
  /// 之前不看这个：53 周的图宽约 1200px，手机一屏只露出最左边十几周 ——
  /// 对新建不久的习惯，那一整屏全是「习惯还没创建」的灰格子，
  /// 看起来就像「热力图没有颜色、完全用不了」。
  void _jumpToEndSoon() {
    if (!widget.scrollable || _jumped) return;
    _jumped = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) _scroll.jumpTo(max);
    });
  }

  @override
  Widget build(BuildContext context) {
    _jumpToEndSoon();
    final map = {for (final c in widget.cells) c.date: c};
    final today = AppTime.dateOnly(DateTime.now());
    final anchor = DateTime.tryParse(widget.anchorDate ?? today) ?? DateTime.now();
    // 本周的周一
    final lastMonday = DateTime(
      anchor.year,
      anchor.month,
      anchor.day,
    ).subtract(Duration(days: anchor.weekday - 1));
    final hasHeaders = widget.weekHeaders.values.any((v) => v.isNotEmpty);

    final columns = <Widget>[];
    for (var i = widget.weeks - 1; i >= 0; i--) {
      final monday = lastMonday.subtract(Duration(days: 7 * i));
      final children = <Widget>[];
      if (hasHeaders) {
        final text = widget.weekHeaders[AppTime.dateOnly(monday)] ?? '';
        children.add(
          SizedBox(
            height: widget.cellSize * 1.1,
            child: Center(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 9,
                  height: 1,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        );
      }
      for (var r = 0; r < 7; r++) {
        final day = monday.add(Duration(days: r));
        final key = AppTime.dateOnly(day);
        children.add(_square(key, map[key], key == today));
      }
      columns.add(
        Column(mainAxisSize: MainAxisSize.min, children: children),
      );
    }

    final grid = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showWeekdayLabels) ...[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasHeaders) SizedBox(height: widget.cellSize * 1.1),
              for (var r = 0; r < 7; r++)
                SizedBox(
                  height: widget.cellSize,
                  width: 14,
                  child: Center(
                    child: Text(
                      // 只标 一/三/五/日，避免太密
                      (r % 2 == 0 || r == 6) ? _weekdayLabels[r] : '',
                      style: const TextStyle(
                        fontSize: 9,
                        height: 1,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
        ],
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0) SizedBox(width: widget.gap),
          columns[i],
        ],
      ],
    );

    return widget.scrollable
        ? SingleChildScrollView(
            key: HeatMap.scrollKey,
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: grid,
          )
        : grid;
  }

  Widget _square(String date, HeatCell? cell, bool isToday) {
    final isSelected = widget.selected.contains(date);
    return GestureDetector(
      key: ValueKey('heat-$date'),
      onTap: widget.onTapDay == null ? null : () => widget.onTapDay!(date),
      child: Tooltip(
        message: cell?.tooltip ?? date,
        waitDuration: const Duration(milliseconds: 500),
        child: Container(
          width: widget.cellSize,
          height: widget.cellSize,
          margin: EdgeInsets.only(bottom: widget.gap),
          decoration: BoxDecoration(
            color: cell?.color ?? const Color(0xFFF0F1F3),
            borderRadius: BorderRadius.circular(widget.cellSize * 0.24),
            border: isSelected
                ? Border.all(color: AppTheme.textPrimary, width: 2)
                : widget.highlightToday && isToday
                ? Border.all(color: AppTheme.textSecondary, width: 1)
                : null,
          ),
        ),
      ),
    );
  }
}
