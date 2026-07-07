import '../../../core/database/app_database.dart';
import '../../../core/database/chart_of_accounts_sync.dart';
import 'ledger_account_model.dart';

/// Result of a delete attempt on a ledger account.
enum LedgerAccountDeleteResult { deleted, blockedSystem, blockedHasActivity }

/// Repository for the `chart_of_accounts` table (Add Ledger Account screen).
class ChartOfAccountsRepository {
  ChartOfAccountsRepository._();
  static final ChartOfAccountsRepository instance =
      ChartOfAccountsRepository._();

  Future<List<LedgerAccount>> getAll() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'chart_of_accounts',
      orderBy: 'CAST(code AS INTEGER) ASC',
    );
    return rows.map(LedgerAccount.fromMap).toList();
  }

  /// Inserts a standalone (unlinked, non-system) account with an
  /// auto-generated code — next available number in the type's block.
  Future<LedgerAccount?> insertStandalone({
    required String name,
    required String accountType,
  }) async {
    final db = await AppDatabase.instance.database;
    late int id;
    await db.transaction((txn) async {
      id = await ChartOfAccountsSync.insertAccount(
        txn,
        name: name,
        accountType: accountType,
      );
    });
    return getById(id);
  }

  Future<LedgerAccount?> getById(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('chart_of_accounts',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : LedgerAccount.fromMap(rows.first);
  }

  /// Renames an account. Allowed on system accounts too (e.g. correcting
  /// "Partner A" to a real partner name) — only `name` is ever touched here.
  Future<void> rename(int id, String newName) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'chart_of_accounts',
      {'name': newName, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Soft enable/disable. The screen only offers this on non-system accounts.
  Future<void> setActive(int id, {required bool active}) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'chart_of_accounts',
      {
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Number of journal lines referencing [accountId].
  Future<int> journalLineCount(int accountId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM journal_lines WHERE account_id = ?',
      [accountId],
    );
    return rows.first['c'] as int? ?? 0;
  }

  /// Deletes a non-system account with no journal activity. Both guards are
  /// re-checked inside the transaction so the delete can never race a
  /// posting.
  Future<LedgerAccountDeleteResult> delete(int id) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) async {
      final rows = await txn.query('chart_of_accounts',
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return LedgerAccountDeleteResult.deleted;
      if ((rows.first['is_system'] as int? ?? 0) == 1) {
        return LedgerAccountDeleteResult.blockedSystem;
      }
      final activity = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM journal_lines WHERE account_id = ?',
        [id],
      );
      if ((activity.first['c'] as int? ?? 0) > 0) {
        return LedgerAccountDeleteResult.blockedHasActivity;
      }
      await txn.delete('chart_of_accounts', where: 'id = ?', whereArgs: [id]);
      return LedgerAccountDeleteResult.deleted;
    });
  }
}
