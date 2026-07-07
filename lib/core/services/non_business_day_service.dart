import '../../features/accounts/data/daily_balance_repository.dart';
import '../../features/accounts/data/day_reconciliation_repository.dart';
import '../../features/admin/data/audit_log_repository.dart';
import '../../features/gold_stock/data/gold_stock_repository.dart';

/// Handles automatic closing of non-business days.
/// Currently: Sundays (shop operates Monday–Saturday).
class NonBusinessDayService {
  NonBusinessDayService._();

  static bool isSunday(String isoDate) {
    final p = isoDate.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]))
            .weekday ==
        DateTime.sunday;
  }

  /// Auto-closes [isoDate] for both the cashbook and the gold stock register
  /// if it falls on a Sunday. Idempotent — skips whichever side is already
  /// locked.
  ///
  /// Returns `true` when [isoDate] is a Sunday (regardless of whether any work
  /// was done), `false` when it is a regular business day.
  static Future<bool> autoCloseIfNonBusinessDay(String isoDate) async {
    if (!isSunday(isoDate)) return false;

    // ── Cashbook ──────────────────────────────────────────────────────────────
    final cashRecord =
        await DailyBalanceRepository.instance.getForDate(isoDate);
    if (cashRecord == null || !cashRecord.isLocked) {
      final totals =
          await DailyBalanceRepository.instance.lockDay(isoDate, null);
      await DayReconciliationRepository.instance.lockReconciliation(
        date: isoDate,
        expectedCash: totals.closingCash,
        expectedUpi: totals.closingUpi,
        actualCash: totals.closingCash,
        actualUpi: totals.closingUpi,
        remarks: 'Auto-closed: non-business day (Sunday)',
      );
      await AuditLogRepository.instance.log(
        actionCategory: AuditCategory.dayManagement,
        action: 'DAY_LOCKED',
        entityType: 'daily_balance',
        entityId: isoDate,
        oldValueJson: '{"is_locked":0}',
        newValueJson: '{"is_locked":1,"cash_diff":0,"upi_diff":0}',
        reason: 'Auto-closed: non-business day (Sunday)',
      );
    }

    // ── Gold stock ────────────────────────────────────────────────────────────
    final stockRecord =
        await GoldStockRepository.instance.getForDate(isoDate);
    if (stockRecord == null || !stockRecord.isLocked) {
      final computed =
          await GoldStockRepository.instance.getOrCreateDayRecord(isoDate);
      await GoldStockRepository.instance.verifyAndLock(
        date: isoDate,
        actualGrossWeight: computed.closingGrossWeight,
        actualWeight: computed.closingWeight,
        discrepancyNote: 'Auto-verified: non-business day (Sunday)',
      );
    }

    return true;
  }
}
