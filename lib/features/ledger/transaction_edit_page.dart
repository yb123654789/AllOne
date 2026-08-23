import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';

/// 记账表单页（记一笔）。
class TransactionEditPage extends ConsumerStatefulWidget {
  final Transaction? transaction;

  const TransactionEditPage({super.key, this.transaction});

  @override
  ConsumerState<TransactionEditPage> createState() =>
      _TransactionEditPageState();
}

class _TransactionEditPageState extends ConsumerState<TransactionEditPage> {
  static const _categories = ['餐饮', '交通', '购物', '居住', '娱乐', '学习', '医疗', '其他'];

  late final TextEditingController _amountCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _noteCtrl;
  TxType _type = TxType.expense;
  String _accountId = '';
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _amountCtrl = TextEditingController(
      text: t == null ? '' : t.amount.toString(),
    );
    _categoryCtrl = TextEditingController(text: t?.category ?? '其他');
    _noteCtrl = TextEditingController(text: t?.note ?? '');
    if (t != null) {
      _type = t.type;
      _accountId = t.accountId;
      _date = DateTime.tryParse(t.date) ?? DateTime.now();
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _categoryCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
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
      id: widget.transaction?.id ?? AppPaths.newId(),
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
    if (_accountId.isEmpty && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.transaction == null ? '记一笔' : '编辑流水'),
        actions: [
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
        ],
      ),
    );
  }
}
