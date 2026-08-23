import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';

/// 快捷记账页（手机端）。
///
/// 用法：在手机上复制一条账单消息（支付宝 / 微信 / 银行短信），
/// 打开本页自动读取剪贴板 -> 解析出金额 / 日期 / 分类 / 备注，
/// 并自动判断该笔是否已记录过（按账户 + 日期 + 金额 + 分类匹配）。
/// 确认后一键保存。
class QuickRecordPage extends ConsumerStatefulWidget {
  const QuickRecordPage({super.key});

  @override
  ConsumerState<QuickRecordPage> createState() => _QuickRecordPageState();
}

class _QuickRecordPageState extends ConsumerState<QuickRecordPage> {
  static const _categories = ['餐饮', '交通', '购物', '居住', '娱乐', '学习', '医疗', '其他'];

  late final TextEditingController _rawCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _noteCtrl;

  TxType _type = TxType.expense;
  String _accountId = '';
  DateTime _date = DateTime.now();

  bool _readingClipboard = false;

  @override
  void initState() {
    super.initState();
    _rawCtrl = TextEditingController();
    _amountCtrl = TextEditingController();
    _categoryCtrl = TextEditingController(text: '其他');
    _noteCtrl = TextEditingController();
    _readClipboard();
  }

  @override
  void dispose() {
    _rawCtrl.dispose();
    _amountCtrl.dispose();
    _categoryCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 读取剪贴板文本并自动解析填充
  Future<void> _readClipboard() async {
    setState(() => _readingClipboard = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isNotEmpty) {
        _rawCtrl.text = text;
        _parse(text);
      }
    } catch (_) {
      // 剪贴板不可用则忽略
    } finally {
      if (mounted) setState(() => _readingClipboard = false);
    }
  }

  /// 从账单文本解析：金额 / 日期 / 类型 / 分类 / 备注
  void _parse(String text) {
    if (text.trim().isEmpty) return;

    // —— 类型：收入关键词 ——
    final isIncome = RegExp(r'收入|入账|到账|退款|返现|收款|进账').hasMatch(text);
    final parsedType = isIncome ? TxType.income : TxType.expense;

    // —— 金额：优先匹配「金额 123.45 / ¥123.45 / 元」附近的数字 ——
    double? amount;
    final moneyRe = RegExp(
      r'(?:金额|人民币|¥|￥|共计|消费|支付|收入|到账)\s*[:：]?\s*(\d+(?:\.\d{1,2})?)',
    );
    final moneyMatch = moneyRe.firstMatch(text);
    if (moneyMatch != null) {
      amount = double.tryParse(moneyMatch.group(1)!);
    }
    if (amount == null) {
      // 兜底：找第一个数字
      final anyNum = RegExp(r'(\d+(?:\.\d{1,2})?)').firstMatch(text);
      if (anyNum != null) amount = double.tryParse(anyNum.group(1)!);
    }

    // —— 日期 ——
    DateTime? date;
    final dateRe = RegExp(
      r'(\d{4})[-年/.](\d{1,2})[-月/.](\d{1,2})日?|(\d{1,2})月(\d{1,2})日',
    );
    final dateMatch = dateRe.firstMatch(text);
    if (dateMatch != null) {
      if (dateMatch.group(1) != null) {
        date = DateTime.tryParse(
          '${dateMatch.group(1)}-${dateMatch.group(2)!.padLeft(2, '0')}-${dateMatch.group(3)!.padLeft(2, '0')}',
        );
      } else {
        final now = DateTime.now();
        date = DateTime(
          now.year,
          int.parse(dateMatch.group(4)!),
          int.parse(dateMatch.group(5)!),
        );
      }
    }

    // —— 分类关键词 ——
    String category = '其他';
    for (final c in _categories) {
      if (text.contains(c)) {
        category = c;
        break;
      }
    }

    // —— 备注：剔除金额/日期/分类等噪声 ——
    var note = text
        .replaceAll(RegExp(r'[【\[][^】\]]*[】\]]'), ' ')
        .replaceAll(RegExp(r'\d+(\.\d{1,2})?'), ' ')
        .replaceAll(RegExp(r'[¥￥元]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    setState(() {
      _type = parsedType;
      if (amount != null) _amountCtrl.text = _fmtAmount(amount);
      if (date != null) _date = date;
      _categoryCtrl.text = category;
      if (note.isNotEmpty) _noteCtrl.text = note;
    });
  }

  String _fmtAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// 自动判断该笔是否可能已记录（同账户 + 同日期 + 同金额 + 同分类）
  bool _maybeDuplicate(Transaction t) {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null) return false;
    final date =
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    return t.accountId == _accountId &&
        t.date == date &&
        (t.amount - amount).abs() < 0.005 &&
        t.category == _categoryCtrl.text.trim() &&
        t.type == _type;
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请输入有效金额')));
      }
      return;
    }
    if (_accountId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请选择账户')));
      }
      return;
    }
    final t = Transaction(
      id: AppPaths.newId(),
      accountId: _accountId,
      date:
          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
      type: _type,
      amount: amount,
      category: _categoryCtrl.text.trim().isEmpty
          ? '其他'
          : _categoryCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
    );
    await ref.read(transactionListProvider.notifier).addTransaction(t);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountListProvider).valueOrNull ?? [];
    final txs = ref.watch(transactionListProvider).valueOrNull ?? [];
    if (_accountId.isEmpty && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }

    // 去重提示
    final dup = txs.where(_maybeDuplicate).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('快捷记账'),
        actions: [
          IconButton(
            onPressed: _readClipboard,
            tooltip: '从剪贴板读取',
            icon: _readingClipboard
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.content_paste_go_outlined),
          ),
          IconButton(
            onPressed: _save,
            tooltip: '保存',
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '粘贴账单消息（支付宝 / 微信 / 银行短信），自动识别金额、日期、分类：',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _rawCtrl,
            maxLines: 4,
            minLines: 3,
            decoration: InputDecoration(
              hintText: '例如：您尾号8888的银行卡支付￥36.50 餐饮消费，余额...',
              suffixIcon: IconButton(
                icon: const Icon(Icons.auto_awesome, size: 20),
                tooltip: '解析',
                onPressed: () => _parse(_rawCtrl.text),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _parse(_rawCtrl.text),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('自动解析并填充'),
            ),
          ),
          if (dup.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.danger.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    color: AppTheme.danger,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '检测到 ${dup.length} 笔可能已记录的流水（同账户·同日期·同金额·同分类）。请核对后再保存。',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 24),
          SegmentedButton<TxType>(
            segments: const [
              ButtonSegment(
                value: TxType.expense,
                label: Text('支出'),
                icon: Icon(Icons.remove_circle_outline),
              ),
              ButtonSegment(
                value: TxType.income,
                label: Text('收入'),
                icon: Icon(Icons.add_circle_outline),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _accountId.isEmpty && accounts.isNotEmpty
                ? accounts.first.id
                : _accountId,
            decoration: const InputDecoration(labelText: '账户'),
            items: [
              for (final a in accounts)
                DropdownMenuItem(
                  value: a.id,
                  child: Text('${a.icon} ${a.name}'),
                ),
            ],
            onChanged: (v) => setState(() => _accountId = v ?? ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '金额',
              prefixText: _type == TxType.expense ? '- ' : '+ ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _categoryCtrl,
            decoration: const InputDecoration(labelText: '分类'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _categories
                .map(
                  (c) => ActionChip(
                    label: Text(c, style: const TextStyle(fontSize: 12)),
                    onPressed: () => setState(() => _categoryCtrl.text = c),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            decoration: const InputDecoration(labelText: '备注'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('日期'),
            subtitle: Text(
              '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
            ),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _date = d);
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存这笔记录'),
          ),
        ],
      ),
    );
  }
}
