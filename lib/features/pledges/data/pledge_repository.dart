import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/settings/app_settings_repository.dart';
import 'payment_model.dart';
import 'pledge_item_model.dart';
import 'pledge_model.dart';

class PledgeRepository {
  PledgeRepository._();

  static final PledgeRepository instance = PledgeRepository._();

  final _settingsRepo = AppSettingsRepository();

  // ─── Pledge Number ───────────────────────────────────────────────────────────

  Future<String> nextPledgeNumber() async {
    final db = await AppDatabase.instance.database;
    final settingVal =
        await _settingsRepo.getString('starting_pledge_number');
    final base = int.tryParse(settingVal ?? '3200') ?? 3200;

    final rows = await db
        .rawQuery('SELECT MAX(CAST(pledge_no AS INTEGER)) as mx FROM pledges');
    final maxFromDb = (rows.first['mx'] as int?) ?? 0;

    return '${maxFromDb >= base ? maxFromDb + 1 : base}';
  }

  Future<bool> pledgeNumberExists(String number) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'pledges',
      columns: ['id'],
      where: 'pledge_no = ?',
      whereArgs: [number],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // ─── Create ──────────────────────────────────────────────────────────────────

  Future<int> createPledge(
    PledgeModel pledge,
    List<PledgeItemModel> items, {
    String paymentMode = 'cash',
    double cashAmount = 0,
    double upiAmount = 0,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final today = now.substring(0, 10);

    return db.transaction((txn) async {
      final pledgeMap = pledge.toMap();
      pledgeMap['created_at'] = now;
      pledgeMap['updated_at'] = now;
      final pledgeId = await txn.insert('pledges', pledgeMap);

      for (final item in items) {
        final itemMap = item.toMap();
        itemMap['pledge_id'] = pledgeId;
        itemMap['created_at'] = now;
        await txn.insert('pledge_items', itemMap);
      }

      // Record loan disbursement — split into two rows so daily accounts
      // can tally cash-out and UPI-out independently
      if (paymentMode == 'split') {
        if (cashAmount > 0) {
          await txn.insert('transactions', {
            'transaction_date': today,
            'type': 'loan_disbursed',
            'direction': 'out',
            'amount': cashAmount,
            'mode': 'cash',
            'pledge_id': pledgeId,
            'payment_id': null,
            'expense_category_id': null,
            'description': 'Loan (cash) for pledge #${pledge.pledgeNumber}',
            'created_by': null,
            'created_at': now,
          });
        }
        if (upiAmount > 0) {
          await txn.insert('transactions', {
            'transaction_date': today,
            'type': 'loan_disbursed',
            'direction': 'out',
            'amount': upiAmount,
            'mode': 'upi',
            'pledge_id': pledgeId,
            'payment_id': null,
            'expense_category_id': null,
            'description': 'Loan (UPI) for pledge #${pledge.pledgeNumber}',
            'created_by': null,
            'created_at': now,
          });
        }
      } else {
        await txn.insert('transactions', {
          'transaction_date': today,
          'type': 'loan_disbursed',
          'direction': 'out',
          'amount': pledge.loanAmount,
          'mode': paymentMode,
          'pledge_id': pledgeId,
          'payment_id': null,
          'expense_category_id': null,
          'description': 'Loan for pledge #${pledge.pledgeNumber}',
          'created_by': null,
          'created_at': now,
        });
      }

      // Advance the starting pledge number counter
      final nextNo = int.tryParse(pledge.pledgeNumber) ?? 0;
      await txn.insert(
        'settings',
        {
          'key': 'starting_pledge_number',
          'value': '${nextNo + 1}',
          'value_type': 'int',
          'updated_by': null,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return pledgeId;
    });
  }

  // ─── Read ─────────────────────────────────────────────────────────────────

  Future<PledgeModel?> getPledgeByNumber(String number) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'pledges',
      where: 'pledge_no = ?',
      whereArgs: [number],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PledgeModel.fromMap(rows.first);
  }

  Future<PledgeModel?> getPledgeById(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'pledges',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PledgeModel.fromMap(rows.first);
  }

  Future<List<PledgeModel>> getOpenPledges({int limit = 50}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'pledges',
      where: "status = 'open'",
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(PledgeModel.fromMap).toList();
  }

  Future<List<PledgeModel>> getClosedPledges({int limit = 50}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'pledges',
      where: "status IN ('closed', 'renewed', 'migrated')",
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(PledgeModel.fromMap).toList();
  }

  Future<List<PledgeItemModel>> getItemsForPledge(int pledgeId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'pledge_items',
      where: 'pledge_id = ?',
      whereArgs: [pledgeId],
    );
    return rows.map(PledgeItemModel.fromMap).toList();
  }

  Future<List<PaymentModel>> getPaymentsForPledge(int pledgeId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'payments',
      where: 'pledge_id = ?',
      whereArgs: [pledgeId],
      orderBy: 'paid_at DESC',
    );
    return rows.map(PaymentModel.fromMap).toList();
  }

  // ─── Close ───────────────────────────────────────────────────────────────────

  Future<void> closePledge(int pledgeId, PaymentModel payment) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.update(
        'pledges',
        {
          'status': 'closed',
          'closed_at': now,
          'closure_date': now.substring(0, 10),
          'total_interest_paid': payment.amount - (await _getPrincipal(txn, pledgeId)),
          'total_amount_collected': payment.amount,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [pledgeId],
      );

      final paymentMap = payment.toMap();
      paymentMap['pledge_id'] = pledgeId;
      paymentMap['paid_at'] = now;
      paymentMap['created_at'] = now;
      final paymentId = await txn.insert('payments', paymentMap);

      await txn.insert('transactions', {
        'transaction_date': now.substring(0, 10),
        'type': 'payment_received',
        'direction': 'in',
        'amount': payment.amount,
        'mode': payment.paymentMode == 'split' ? 'cash' : payment.paymentMode,
        'pledge_id': pledgeId,
        'payment_id': paymentId,
        'expense_category_id': null,
        'description': 'Closure of pledge',
        'created_by': null,
        'created_at': now,
      });
    });
  }

  // ─── Renew ───────────────────────────────────────────────────────────────────

  Future<String> renewPledge(
    int oldPledgeId,
    double newLoanAmount,
    PaymentModel? interestPayment,
  ) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    final oldPledge = await getPledgeById(oldPledgeId);
    if (oldPledge == null) throw Exception('Pledge not found');

    final newNumber = await nextPledgeNumber();

    await db.transaction((txn) async {
      // Close old pledge as renewed
      await txn.update(
        'pledges',
        {
          'status': 'renewed',
          'closed_at': now,
          'closure_date': now.substring(0, 10),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [oldPledgeId],
      );

      // Insert new pledge
      final newPledge = PledgeModel(
        pledgeNumber: newNumber,
        pledgeDate: now.substring(0, 10),
        loanAmount: newLoanAmount,
        interestRate: oldPledge.interestRate,
        status: 'open',
        source: 'renewal',
        renewalParentId: oldPledgeId,
        createdAt: now,
        customerName: oldPledge.customerName,
        customerPhone: oldPledge.customerPhone,
        customerAddress: oldPledge.customerAddress,
        grossWeight: oldPledge.grossWeight,
        netWeight: oldPledge.netWeight,
        purity: oldPledge.purity,
        goldRate: oldPledge.goldRate,
        pledgeRate: oldPledge.pledgeRate,
      );
      final newPledgeMap = newPledge.toMap();
      newPledgeMap['created_at'] = now;
      newPledgeMap['updated_at'] = now;
      final newPledgeId = await txn.insert('pledges', newPledgeMap);

      // Copy items to new pledge
      final items = await db.query(
        'pledge_items',
        where: 'pledge_id = ?',
        whereArgs: [oldPledgeId],
      );
      for (final item in items) {
        final itemCopy = Map<String, dynamic>.from(item);
        itemCopy.remove('id');
        itemCopy['pledge_id'] = newPledgeId;
        itemCopy['created_at'] = now;
        await txn.insert('pledge_items', itemCopy);
      }

      // Record interest payment if provided
      if (interestPayment != null) {
        final payMap = interestPayment.toMap();
        payMap['pledge_id'] = oldPledgeId;
        payMap['paid_at'] = now;
        payMap['created_at'] = now;
        final payId = await txn.insert('payments', payMap);

        await txn.insert('transactions', {
          'transaction_date': now.substring(0, 10),
          'type': 'payment_received',
          'direction': 'in',
          'amount': interestPayment.amount,
          'mode': interestPayment.paymentMode == 'split'
              ? 'cash'
              : interestPayment.paymentMode,
          'pledge_id': oldPledgeId,
          'payment_id': payId,
          'expense_category_id': null,
          'description': 'Interest on renewal of pledge #${oldPledge.pledgeNumber}',
          'created_by': null,
          'created_at': now,
        });
      }

      // Advance pledge number counter
      final nextNo = int.tryParse(newNumber) ?? 0;
      await txn.insert(
        'settings',
        {
          'key': 'starting_pledge_number',
          'value': '${nextNo + 1}',
          'value_type': 'int',
          'updated_by': null,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    return newNumber;
  }

  // ─── Manual Close (legacy/physical records) ──────────────────────────────────

  Future<void> createManualClosedPledge({
    required String pledgeNumber,
    required String pledgeDate,
    required String closureDate,
    required double principal,
    required double interest,
    required double total,
    required double interestRate,
    required String paymentMode,
  }) async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    final today = now.substring(0, 10);

    await db.transaction((txn) async {
      final pledgeId = await txn.insert('pledges', {
        'pledge_no': pledgeNumber,
        'customer_name': '',
        'customer_phone': null,
        'customer_address': null,
        'gross_weight': 0.0,
        'stone_weight': 0.0,
        'net_weight': 0.0,
        'purity': '',
        'gold_rate': 0.0,
        'pledge_rate': 0.0,
        'principal_amount': principal,
        'interest_rate': interestRate,
        'start_date': pledgeDate,
        'status': 'closed',
        'closed_at': now,
        'closure_date': closureDate,
        'source': 'manual',
        'renewal_parent_id': null,
        'total_interest_paid': interest,
        'total_amount_collected': total,
        'notes': 'Closed via interest calculator',
        'created_by': null,
        'created_at': now,
        'updated_at': now,
      });

      await txn.insert('payments', {
        'pledge_id': pledgeId,
        'payment_type': 'closure',
        'amount': total,
        'cash_amount': paymentMode == 'cash' ? total : 0.0,
        'upi_amount': paymentMode == 'upi' ? total : 0.0,
        'interest_amount': interest,
        'principal_amount': principal,
        'payment_mode': paymentMode,
        'paid_at': now,
        'notes': 'Manual closure via calculator',
        'created_by': null,
        'created_at': now,
      });

      await txn.insert('transactions', {
        'transaction_date': today,
        'type': 'payment_received',
        'direction': 'in',
        'amount': total,
        'mode': paymentMode,
        'pledge_id': pledgeId,
        'payment_id': null,
        'expense_category_id': null,
        'description': 'Manual closure of pledge #$pledgeNumber',
        'created_by': null,
        'created_at': now,
      });
    });
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  Future<double> _getPrincipal(dynamic txn, int pledgeId) async {
    final rows = await txn.query(
      'pledges',
      columns: ['principal_amount'],
      where: 'id = ?',
      whereArgs: [pledgeId],
      limit: 1,
    );
    if (rows.isEmpty) return 0.0;
    return (rows.first['principal_amount'] as num?)?.toDouble() ?? 0.0;
  }
}
