import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/theme.dart';
import 'account_edit_page.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';
import 'quick_record_page.dart';
import 'transaction_edit_page.dart';

/// 记账模块入口页：总账本总览 + 账户列表 + 月/年统计。
class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  /// 统计时间段：day / month / year
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountListProvider);
    final txAsync = ref.watch(transactionListProvider);
    final settingsAsync = ref.watch(ledgerSettingsProvider);
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
          data: (txs) => settingsAsync.when(
            data: (settings) => _body(context, accounts, txs, settings),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败：$e')),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onFabPressed,
        tooltip: '记一笔 / 快捷记账',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 悬浮按钮：弹出「记一笔」与「快捷记账」两个入口
  Future<void> _onFabPressed() async {
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: AppTheme.primary),
              title: const Text('记一笔'),
              subtitle: const Text('手动填写收支流水'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
            ListTile(
              leading: const Icon(
                Icons.content_paste_go,
                color: AppTheme.primary,
              ),
              title: const Text('快捷记账'),
              subtitle: const Text('粘贴账单文本自动识别，判断是否已记录（推荐手机端）'),
              onTap: () => Navigator.pop(ctx, 'quick'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (act == 'quick') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QuickRecordPage()),
      );
    } else if (act == 'manual') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TransactionEditPage()),
      );
    }
  }

  Widget _body(
    BuildContext context,
    List<LedgerAccount> accounts,
    List<Transaction> txs,
    LedgerSettings settings,
  ) {
    final now = DateTime.now();
    final today = AppTime.dateOnly(now);
    final ym = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final year = now.year.toString();

    bool inPeriod(Transaction t) => switch (_period) {
      'day' => t.date == today,
      'month' => t.date.startsWith(ym),
      _ => t.date.startsWith(year),
    };

    final periodTxs = txs.where(inPeriod).toList();
    final income = periodTxs
        .where((t) => t.type == TxType.income)
        .fold(0.0, (a, t) => a + t.amount);
    final expense = periodTxs
        .where((t) => t.type == TxType.expense)
        .fold(0.0, (a, t) => a + t.amount);

    // 月度预算分析（仅本月视图）
    final dailyAvg = now.day > 0 ? expense / now.day : 0.0;
    final budget = settings.monthlyBudget;
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day;
    final leftPerDay = (budget > 0 && daysLeft > 0)
        ? (budget - expense) / daysLeft
        : 0.0;

    final periodLabel = _period == 'day'
        ? '今日'
        : (_period == 'month' ? '本月' : '本年');

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        // 时间段切换：今日 / 本月 / 本年
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'day', label: Text('今日')),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '总账本（$periodLabel）',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    if (_period == 'month')
                      TextButton.icon(
                        onPressed: () => _editBudget(settings),
                        icon: const Icon(Icons.track_changes, size: 16),
                        label: Text(
                          budget > 0
                              ? '预算 ¥${budget.toStringAsFixed(0)}'
                              : '设预算',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('收入', income, Colors.green),
                    _stat('支出', expense, AppTheme.danger),
                    _stat('结余', income - expense, AppTheme.primary),
                  ],
                ),
                if (_period == 'month') ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _stat('日均支出', dailyAvg, AppTheme.textSecondary),
                      if (budget > 0) ...[
                        _stat('本月预算', budget, AppTheme.primary),
                        _stat(
                          '剩余每天可花',
                          leftPerDay,
                          leftPerDay >= 0 ? Colors.green : AppTheme.danger,
                        ),
                      ],
                    ],
                  ),
                  if (budget <= 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        '设置「本月预算」后，可查看剩余每天可花额度',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        // 账户列表
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '账户',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
        for (final a in accounts) _accountCard(context, a, txs),
        // 流水列表
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            _period == 'day' ? '今日流水' : '近期流水',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
        if (periodTxs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                '暂无流水，点击右下角 + 记一笔',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          for (final t in periodTxs.take(_period == 'day' ? 200 : 30))
            _txTile(t, accounts),
      ],
    );
  }

  /// 设置本月计划支出预算
  Future<void> _editBudget(LedgerSettings settings) async {
    final ctrl = TextEditingController(
      text: settings.monthlyBudget > 0
          ? settings.monthlyBudget.toStringAsFixed(0)
          : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('本月计划支出预算'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '设置本月计划支出金额，用于计算「剩余每天可花额度」',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '本月预算（元，0 表示不设）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final v = double.tryParse(ctrl.text.trim()) ?? 0;
      await ref.read(ledgerSettingsProvider.notifier).setMonthlyBudget(v);
    }
  }

  Widget _stat(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value.toStringAsFixed(2),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _accountCard(
    BuildContext context,
    LedgerAccount a,
    List<Transaction> txs,
  ) {
    final accTxs = txs.where((t) => t.accountId == a.id).toList();
    final balance =
        a.initialBalance +
        accTxs
            .where((t) => t.type == TxType.income)
            .fold(0.0, (s, t) => s + t.amount) -
        accTxs
            .where((t) => t.type == TxType.expense)
            .fold(0.0, (s, t) => s + t.amount);

    // 该账户在当前周期（日/月/年）内的统计
    final now = DateTime.now();
    final today = AppTime.dateOnly(now);
    final ym = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final year = now.year.toString();
    bool inPeriod(Transaction t) => switch (_period) {
      'day' => t.date == today,
      'month' => t.date.startsWith(ym),
      _ => t.date.startsWith(year),
    };
    final periodLabel = _period == 'day'
        ? '今日'
        : (_period == 'month' ? '本月' : '本年');
    final periodTxs = accTxs.where(inPeriod).toList();
    final periodIncome = periodTxs
        .where((t) => t.type == TxType.income)
        .fold(0.0, (s, t) => s + t.amount);
    final periodExpense = periodTxs
        .where((t) => t.type == TxType.expense)
        .fold(0.0, (s, t) => s + t.amount);

    return Card(
      child: ExpansionTile(
        leading: Text(a.icon, style: const TextStyle(fontSize: 24)),
        title: Text(a.name.isEmpty ? '未命名账户' : a.name),
        subtitle: Text(
          '共 ${accTxs.length} 笔 · $periodLabel 收 ${periodIncome.toStringAsFixed(2)} / 支 ${periodExpense.toStringAsFixed(2)}',
        ),
        shape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('$periodLabel收入', periodIncome, Colors.green),
              _stat('$periodLabel支出', periodExpense, AppTheme.danger),
              _stat(
                '$periodLabel结余',
                periodIncome - periodExpense,
                AppTheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(
                '当前余额',
                balance,
                balance >= 0 ? AppTheme.primary : AppTheme.danger,
              ),
            ],
          ),
        ],
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
