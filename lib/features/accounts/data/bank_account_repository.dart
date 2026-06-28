import '../../../core/database/app_database.dart';
import '../../pledges/data/payment_model.dart';
import '../../pledges/data/payments_repository.dart';
import 'bank_account_model.dart';

class BankAccountRepository {
  BankAccountRepository._();
  static final BankAccountRepository instance = BankAccountRepository._();

  // ─── Read ────────────────────────────────────────────────────────────────────

  Future<List<BankAccount>> getAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('bank_accounts', orderBy: 'name ASC');
    return rows.map(BankAccount.fromMap).toList();
  }

  Future<List<BankAccount>> getActive() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('bank_accounts',
        where: 'is_active = 1', orderBy: 'name ASC');
    return rows.map(BankAccount.fromMap).toList();
  }

  /// Active accounts whose start_date is on or before [date].
  Future<List<BankAccount>> getActiveForDate(String date) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('bank_accounts',
        where: 'is_active = 1 AND start_date <= ?',
        whereArgs: [date],
        orderBy: 'name ASC');
    return rows.map(BankAccount.fromMap).toList();
  }

  Future<BankAccount?> getDefault() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('bank_accounts',
        where: 'is_default = 1 AND is_active = 1', limit: 1);
    return rows.isEmpty ? null : BankAccount.fromMap(rows.first);
  }

  Future<BankAccount?> getById(int id) async {
    final db = await AppDatabase.instance.database;
    final rows =
        await db.query('bank_accounts', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : BankAccount.fromMap(rows.first);
  }

  // ─── Write ───────────────────────────────────────────────────────────────────

  Future<BankAccount> insert({
    required String name,
    required double openingBalance,
    required String startDate,
    bool createOpeningPayment = true,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final id = await db.insert('bank_accounts', {
      'name': name,
      'opening_balance': openingBalance,
      'start_date': startDate,
      'is_default': 0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    if (openingBalance > 0 && createOpeningPayment) {
      await PaymentsRepository.instance.createAdjustment(
        openingBalance,
        0,
        openingBalance,
        PaymentSubCategory.addBank,
        PaymentDirection.inward,
        startDate,
        bankAccountId: id,
        notes: 'Opening balance',
      );
    }

    return BankAccount(
      id: id,
      name: name,
      openingBalance: openingBalance,
      startDate: startDate,
      isDefault: false,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> rename(int id, String newName) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'bank_accounts',
      {'name': newName, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Sets [id] as the sole default account in a single transaction.
  Future<void> setDefault(int id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.rawUpdate(
        'UPDATE bank_accounts SET is_default = 0, updated_at = ? WHERE is_default = 1',
        [now],
      );
      await txn.update(
        'bank_accounts',
        {'is_default': 1, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> setActive(int id, {required bool active}) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'bank_accounts',
      {'is_active': active ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
