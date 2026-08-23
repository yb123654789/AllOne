import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage_providers.dart';
import 'ledger_models.dart';

/// 账户列表 Notifier
class AccountListNotifier extends AsyncNotifier<List<LedgerAccount>> {
  static const _dir = 'ledger/accounts';

  @override
  Future<List<LedgerAccount>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final files = await store.listFiles(_dir);
    final list = <LedgerAccount>[];
    for (final f in files) {
      final json = await store.read('$_dir/$f');
      if (json != null) list.add(LedgerAccount.fromJson(json));
    }
    return list;
  }

  Future<void> saveAccount(LedgerAccount a) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write('$_dir/${a.id}.json', a.toJson());
    ref.invalidateSelf();
  }

  Future<void> deleteAccount(String id) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.delete('$_dir/$id.json');
    ref.invalidateSelf();
  }
}

/// 流水 Notifier：加载全部账户流水为平铺列表
class TransactionListNotifier extends AsyncNotifier<List<Transaction>> {
  static const _dir = 'ledger/transactions';

  @override
  Future<List<Transaction>> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final accounts = await ref.watch(accountListProvider.future);
    final all = <Transaction>[];
    // 流水文件为扁平格式：ledger/transactions/<accountId>_<yyyy-MM>.json
    final files = await store.listFiles(_dir);
    for (final acc in accounts) {
      final prefix = '${acc.id}_';
      for (final f in files) {
        if (!f.startsWith(prefix)) continue;
        final json = await store.read('$_dir/$f');
        if (json != null) {
          final m = MonthlyRecords.fromJson(json);
          all.addAll(m.records);
        }
      }
    }
    all.sort((a, b) => b.date.compareTo(a.date));
    return all;
  }

  Future<void> addTransaction(Transaction t) async {
    final store = await ref.read(jsonStoreProvider.future);
    final month = t.date.length >= 7 ? t.date.substring(0, 7) : t.date;
    final path = '$_dir/${t.accountId}_$month.json';
    final existing = await store.read(path);
    final records = existing == null
        ? <Transaction>[t]
        : [
            ...MonthlyRecords.fromJson(existing).records
                .where((r) => r.id != t.id),
            t,
          ];
    await store.write(
      path,
      MonthlyRecords(
        accountId: t.accountId,
        month: month,
        records: records,
      ).toJson(),
    );
    ref.invalidateSelf();
  }

  Future<void> deleteTransaction(
    String id,
    String accountId,
    String date,
  ) async {
    final store = await ref.read(jsonStoreProvider.future);
    final month = date.length >= 7 ? date.substring(0, 7) : date;
    final path = '$_dir/${accountId}_$month.json';
    final existing = await store.read(path);
    if (existing == null) return;
    final m = MonthlyRecords.fromJson(existing);
    final remaining = m.records.where((r) => r.id != id).toList();
    if (remaining.isEmpty) {
      await store.delete(path);
    } else {
      await store.write(
        path,
        MonthlyRecords(
          accountId: accountId,
          month: month,
          records: remaining,
        ).toJson(),
      );
    }
    ref.invalidateSelf();
  }
}

final accountListProvider =
    AsyncNotifierProvider<AccountListNotifier, List<LedgerAccount>>(
      AccountListNotifier.new,
    );
final transactionListProvider =
    AsyncNotifierProvider<TransactionListNotifier, List<Transaction>>(
      TransactionListNotifier.new,
    );

/// 记账设置 Notifier（计划支出 / 预算）
class LedgerSettingsNotifier extends AsyncNotifier<LedgerSettings> {
  static const _path = 'ledger/settings.json';

  @override
  Future<LedgerSettings> build() async {
    final store = await ref.watch(jsonStoreProvider.future);
    final json = await store.read(_path);
    return LedgerSettings.fromJson(json);
  }

  Future<void> setMonthlyBudget(double v) async {
    final store = await ref.read(jsonStoreProvider.future);
    await store.write(_path, LedgerSettings(monthlyBudget: v).toJson());
    ref.invalidateSelf();
  }
}

final ledgerSettingsProvider =
    AsyncNotifierProvider<LedgerSettingsNotifier, LedgerSettings>(
      LedgerSettingsNotifier.new,
    );
