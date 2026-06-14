import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../features/pledges/data/pledge_model.dart';
import '../../../shared/widgets/shared_customer_details_step.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class CustomerWithStats {
  const CustomerWithStats({
    required this.id,
    required this.name,
    required this.phone,
    this.address,
    this.district,
    this.state,
    this.pinCode,
    this.idProofType,
    this.idProofNumber,
    this.idProofPhotoPaths,
    required this.createdAt,
    required this.updatedAt,
    this.totalPledges = 0,
    this.activePledges = 0,
  });

  final int id;
  final String name;
  final String phone;
  final String? address;
  final String? district;
  final String? state;
  final String? pinCode;
  final String? idProofType;
  final String? idProofNumber;
  final String? idProofPhotoPaths;
  final String createdAt;
  final String updatedAt;
  final int totalPledges;
  final int activePledges;

  List<File> get photoFiles {
    if (idProofPhotoPaths == null || idProofPhotoPaths!.isEmpty) return [];
    try {
      final paths = (jsonDecode(idProofPhotoPaths!) as List).cast<String>();
      return paths.map((p) => File(p)).where((f) => f.existsSync()).toList();
    } catch (_) {
      return [];
    }
  }

  factory CustomerWithStats.fromMap(
    Map<String, dynamic> map, {
    int totalPledges = 0,
    int activePledges = 0,
  }) {
    return CustomerWithStats(
      id: map['id'] as int,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      address: map['address'] as String?,
      district: map['district'] as String?,
      state: map['state'] as String?,
      pinCode: map['pin_code'] as String?,
      idProofType: map['id_proof_type'] as String?,
      idProofNumber: map['id_proof_number'] as String?,
      idProofPhotoPaths: map['id_proof_photo_paths'] as String?,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
      totalPledges: totalPledges,
      activePledges: activePledges,
    );
  }
}

// ─── Repository ───────────────────────────────────────────────────────────────

class CustomerRepository {
  CustomerRepository._();
  static final instance = CustomerRepository._();

  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<CustomerWithStats>> getAllCustomers() async {
    final db = await _db;
    final customers = await db.query('customers', orderBy: 'name ASC');
    return _attachStats(db, customers);
  }

  Future<List<CustomerWithStats>> searchCustomers(String query) async {
    final db = await _db;
    final q = '%${query.trim()}%';
    final customers = await db.rawQuery(
      "SELECT * FROM customers WHERE name LIKE ? OR phone LIKE ? ORDER BY name ASC",
      [q, q],
    );
    return _attachStats(db, customers);
  }

  Future<Map<String, dynamic>?> getCustomerById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> createCustomer(CustomerDetailsData data) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final photoPathsJson = data.idProofPhotos.isNotEmpty
        ? jsonEncode(data.idProofPhotos.map((f) => f.path).toList())
        : null;

    return db.insert('customers', {
      'name': data.name,
      'phone': data.phone,
      'address': data.address,
      'district': data.district,
      'state': data.state,
      'pin_code': data.pinCode,
      'id_proof_type': data.idProofType,
      'id_proof_number': data.idNumber,
      'id_proof_photo_paths': photoPathsJson,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateCustomer(int id, CustomerDetailsData data) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final photoPathsJson = data.idProofPhotos.isNotEmpty
        ? jsonEncode(data.idProofPhotos.map((f) => f.path).toList())
        : null;

    await db.update(
      'customers',
      {
        'name': data.name,
        'phone': data.phone,
        'address': data.address,
        'district': data.district,
        'state': data.state,
        'pin_code': data.pinCode,
        'id_proof_type': data.idProofType,
        'id_proof_number': data.idNumber,
        'id_proof_photo_paths': photoPathsJson,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> phoneExistsForOther(String phone, {int? excludeId}) async {
    if (phone.isEmpty) return false;
    final db = await _db;
    final rows = excludeId != null
        ? await db.query(
            'customers',
            columns: ['id'],
            where: 'phone = ? AND id != ?',
            whereArgs: [phone, excludeId],
            limit: 1,
          )
        : await db.query(
            'customers',
            columns: ['id'],
            where: 'phone = ?',
            whereArgs: [phone],
            limit: 1,
          );
    return rows.isNotEmpty;
  }

  Future<List<PledgeModel>> getPledgesForCustomer(
      int customerId, String? phone) async {
    final db = await _db;
    final List<Map<String, dynamic>> rows;
    if (phone != null && phone.isNotEmpty) {
      rows = await db.rawQuery(
        '''SELECT * FROM pledges
           WHERE customer_id = ? OR (customer_id IS NULL AND customer_phone = ?)
           ORDER BY id DESC''',
        [customerId, phone],
      );
    } else {
      rows = await db.query(
        'pledges',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: 'id DESC',
      );
    }
    return rows.map(PledgeModel.fromMap).toList();
  }

  Future<double> getTotalOutstanding(int customerId, String? phone) async {
    final db = await _db;
    final List<Map<String, dynamic>> rows;
    if (phone != null && phone.isNotEmpty) {
      rows = await db.rawQuery(
        '''SELECT SUM(principal_amount) as total FROM pledges
           WHERE status = 'open'
             AND (customer_id = ? OR (customer_id IS NULL AND customer_phone = ?))''',
        [customerId, phone],
      );
    } else {
      rows = await db.rawQuery(
        '''SELECT SUM(principal_amount) as total FROM pledges
           WHERE status = 'open' AND customer_id = ?''',
        [customerId],
      );
    }
    return (rows.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<CustomerWithStats>> _attachStats(
    Database db,
    List<Map<String, dynamic>> customers,
  ) async {
    final result = <CustomerWithStats>[];
    for (final c in customers) {
      final id = c['id'] as int;
      final phone = c['phone'] as String? ?? '';

      final List<Map<String, dynamic>> totalRows;
      final List<Map<String, dynamic>> activeRows;

      if (phone.isNotEmpty) {
        totalRows = await db.rawQuery(
          '''SELECT COUNT(*) as cnt FROM pledges
             WHERE customer_id = ? OR (customer_id IS NULL AND customer_phone = ?)''',
          [id, phone],
        );
        activeRows = await db.rawQuery(
          '''SELECT COUNT(*) as cnt FROM pledges
             WHERE status = 'open'
               AND (customer_id = ? OR (customer_id IS NULL AND customer_phone = ?))''',
          [id, phone],
        );
      } else {
        totalRows = await db.rawQuery(
          'SELECT COUNT(*) as cnt FROM pledges WHERE customer_id = ?',
          [id],
        );
        activeRows = await db.rawQuery(
          "SELECT COUNT(*) as cnt FROM pledges WHERE status = 'open' AND customer_id = ?",
          [id],
        );
      }

      result.add(CustomerWithStats.fromMap(
        c,
        totalPledges: (totalRows.first['cnt'] as int?) ?? 0,
        activePledges: (activeRows.first['cnt'] as int?) ?? 0,
      ));
    }
    return result;
  }
}
