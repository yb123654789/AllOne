import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'account_edit_page.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';
import 'transaction_edit_page.dart';

/// 记账模块入口页：总账本总览 + 账户列表 + 月/年统计。
class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  /// 统计时间段：month / year
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountListProvider);
    final txAsync = ref.watch(transactionListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('记账'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: '账户管理',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountEditPage()),
            ),
          ),
        ],
      ),
      body: accountsAsync.when(
        data: (accounts) => txAsync.when(
          data: (txs) => _body(context, accounts, txs),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TransactionEditPage()),
        ),
        tooltip: '记一笔',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _body(
      BuildContext context, List<LedgerAccount> accounts, List<Transaction> txs) {
    final now = DateTime.now();
    final ym = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final year = now.year.toString();

    bool inPeriod(Transaction t) =>
        _period == 'month' ? t.date.startsWith(ym) : t.date.startsWith(year);

    final periodTxs = txs.where(inPeriod).toList();
    final income = periodTxs.where((t) => t.type == TxType.income).fold(0.0, (a, t) => a + t.amount);
    final expense = periodTxs.where((t) => t.type == TxType.expense).fold(0.0, (a, t) => a + t.amount);

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        // 时间段切换
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'month', label: Text('本月')),
              ButtonSegment(value: 'year', label: Text('本年')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => setState(() => _period = s.first),
            showSelectedIcon: false,
          ),
        ),
        // 总账本卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('总账本（${_period == 'month' ? '本月' : '本年'}）',
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('收入', income, Colors.green),
                    _stat('支出', expense, AppTheme.danger),
                    _stat('结余', income - expense, AppTheme.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
        // 账户列表
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('账户', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        ),
        for (final a in accounts) _accountCard(context, a, txs),
        // 近期流水
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('近期流水', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        ),
        if (txs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('暂无流水，点击右下角 + 记一笔',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
          )
        else
          for (final t in txs.take(30)) _txTile(t, accounts),
      ],
    );
  }

  Widget _stat(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(
          value.toStringAsFixed(2),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  Widget _accountCard(
      BuildContext context, LedgerAccount a, List<Transaction> txs) {
    final accTxs = txs.where((t) => t.accountId == a.id).toList();
    final balance = a.initialBalance +
        accTxs
            .where((t) => t.type == TxType.income)
            .fold(0.0, (s, t) => s + t.amount) -
        accTxs
            .where((t) => t.type == TxType.expense)
            .fold(0.0, (s, t) => s + t.amount);
    return Card(
      child: ListTile(
        leading: Text(a.icon, style: const TextStyle(fontSize: 24)),
        title: Text(a.name.isEmpty ? '未命名账户' : a.name),
        subtitle: Text('共 ${accTxs.length} 笔'),
        trailing: Text(
          balance.toStringAsFixed(2),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: balance >= 0 ? AppTheme.primary : AppTheme.danger,
          ),
        ),
      ),
    );
  }

  Widget _txTile(Transaction t, List<LedgerAccount> accounts) {
    final acc = accounts.where((a) => a.id == t.accountId).firstOrNull;
    return ListTile(
      dense: true,
      leading: Text(acc?.icon ?? '💵'),
      title: Text('${t.category}${t.note.isEmpty ? '' : ' · ${t.note}'}'),
      subtitle: Text('${t.date}  ${acc?.name ?? ''}'),
      trailing: Text(
        '${t.type == TxType.income ? '+' : '-'}${t.amount.toStringAsFixed(2)}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: t.type == TxType.income ? Colors.green : AppTheme.danger,
        ),
      ),
    );
  }
}
