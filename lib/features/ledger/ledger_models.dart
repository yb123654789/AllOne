/// 账户
class LedgerAccount {
  final String id;
  final String name;
  final String icon; // emoji
  final String color; // hex
  final double initialBalance;

  const LedgerAccount({
    required this.id,
    this.name = '',
    this.icon = '💵',
    this.color = '#30A46C',
    this.initialBalance = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'color': color,
        'initialBalance': initialBalance,
      };

  factory LedgerAccount.fromJson(Map<String, dynamic> j) => LedgerAccount(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        icon: j['icon'] as String? ?? '💵',
        color: j['color'] as String? ?? '#30A46C',
        initialBalance: (j['initialBalance'] as num?)?.toDouble() ?? 0,
      );
}

/// 收支类型
enum TxType { income, expense }

/// 一笔流水
class Transaction {
  final String id;
  final String accountId;
  final String date; // yyyy-MM-dd
  final TxType type;
  final double amount;
  final String category;
  final String note;

  const Transaction({
    required this.id,
    required this.accountId,
    required this.date,
    required this.type,
    required this.amount,
    this.category = '其他',
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountId': accountId,
        'date': date,
        'type': type.name,
        'amount': amount,
        'category': category,
        'note': note,
      };

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'] as String? ?? '',
        accountId: j['accountId'] as String? ?? '',
        date: j['date'] as String? ?? '',
        type: TxType.values.firstWhere(
            (e) => e.name == j['type'],
            orElse: () => TxType.expense),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        category: j['category'] as String? ?? '其他',
        note: j['note'] as String? ?? '',
      );
}

/// 某账户某月的流水文件
class MonthlyRecords {
  final String accountId;
  final String month; // yyyy-MM
  final List<Transaction> records;

  const MonthlyRecords({required this.accountId, required this.month, this.records = const []});

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'month': month,
        'records': records.map((r) => r.toJson()).toList(),
      };

  factory MonthlyRecords.fromJson(Map<String, dynamic> j) => MonthlyRecords(
        accountId: j['accountId'] as String? ?? '',
        month: j['month'] as String? ?? '',
        records: (j['records'] as List?)
                ?.map((e) => Transaction.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
