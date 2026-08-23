import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_paths.dart';
import '../../core/theme.dart';
import 'ledger_models.dart';
import 'ledger_repository.dart';

/// 账户管理页：自由创建账户，设置初始余额。
class AccountEditPage extends ConsumerWidget {
  const AccountEditPage({super.key});

  static const _icons = ['💵', '💳', '🏦', '📱', '💰', '🧧', '💎', '🏠'];
  static const _colors = [
    '#30A46C',
    '#1E88E5',
    '#F5A623',
    '#E5484D',
    '#7C3AED',
    '#5C5C5C',
  ];

  Future<void> _createAccount(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final balCtrl = TextEditingController(text: '0');
    String icon = _icons.first;
    String color = _colors.first;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('新建账户'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '账户名称（如：现金 / 支付宝）',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '初始余额'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: _icons
                    .map(
                      (ic) => InkWell(
                        onTap: () => setState(() => icon = ic),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: icon == ic
                                ? AppTheme.primary.withValues(alpha: 0.15)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(ic, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: _colors
                    .map(
                      (c) => InkWell(
                        onTap: () => setState(() => color = c),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _hex(c),
                            shape: BoxShape.circle,
                            border: color == c
                                ? Border.all(
                                    color: AppTheme.textPrimary,
                                    width: 2,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    )
                    .toList(),
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
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await ref
          .read(accountListProvider.notifier)
          .saveAccount(
            LedgerAccount(
              id: AppPaths.newId(),
              name: nameCtrl.text.trim(),
              icon: icon,
              color: color,
              initialBalance: double.tryParse(balCtrl.text.trim()) ?? 0,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('账户管理')),
      body: accounts.when(
        data: (list) => list.isEmpty
            ? const Center(
                child: Text(
                  '暂无账户，点击右下角 + 创建',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final a = list[i];
                  return Card(
                    child: ListTile(
                      leading: Text(
                        a.icon,
                        style: const TextStyle(fontSize: 26),
                      ),
                      title: Text(a.name),
                      subtitle: Text(
                        '初始余额 ${a.initialBalance.toStringAsFixed(2)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('删除账户'),
                              content: Text('确定删除账户「${a.name}」吗？相关流水也会一并删除。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.danger,
                                  ),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await ref
                                .read(accountListProvider.notifier)
                                .deleteAccount(a.id);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createAccount(context, ref),
        tooltip: '新建账户',
        child: const Icon(Icons.add),
      ),
    );
  }

  Color _hex(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF30A46C);
  }
}
