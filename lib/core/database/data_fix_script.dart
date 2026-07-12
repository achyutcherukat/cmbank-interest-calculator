/// One-off production database correction script.
///
/// This is the ONLY file that changes between fixes. To ship a new fix:
///   1. Bump [dataFixVersion] by one.
///   2. Replace [dataFixDescription] with the new fix's summary.
///   3. Update [dataFixFlavors], [dataFixStatements] and (optionally)
///      [dataFixVerifyQueries] for the new fix.
///
/// The "Data Fix" section in Admin Settings is shown only while
/// `dataFixVersion > settings.last_data_fix_applied` AND the running flavour
/// is listed in [dataFixFlavors]; running the fix bumps the stored value so
/// the section disappears and the same fix never runs twice.
///
/// All statements are executed inside a single atomic transaction — if any one
/// throws, the whole fix rolls back and `last_data_fix_applied` is left
/// unchanged.
///
/// [dataFixVerifyQueries] holds an optional read-only SELECT per flavour. The
/// runner executes it BEFORE the confirm dialog (so current values are shown
/// alongside the SQL for review) and AGAIN after the transaction commits (so
/// the result dialog shows the corrected values). It never modifies data.
///
/// LEDGER RULE (Prompt 8): any future fix that UPDATEs a `payments` or
/// `pledges` row in a way that changes its ledger-visible figures MUST also
/// set that row's `updated_at`, e.g.
///   `..., updated_at = strftime('%Y-%m-%dT%H:%M:%f', 'now', 'localtime')`
/// so relocking the affected day auto-reverses and reposts its journal
/// entry. DELETEs need nothing — the lock-time staleness pass detects the
/// orphaned entry and reverses it automatically. The v3 bank_account_id
/// clean-up deliberately did NOT stamp updated_at: it only nulled an
/// unused reference on cash-only rows, which no posting rule reads, so
/// stamping it would cause pointless reverse-and-repost churn.
library;

const int dataFixVersion = 6;

const String dataFixDescription =
    'Renames pledge_no for ids 132/133/136/140, and shifts business dates '
    '+1 day for pledge 16972 (entered a day late): payments.payment_date, '
    'pledges.closure_date and pledges.closed_at. updated_at is stamped to '
    'now on the affected payments/pledge row so the ledger staleness pass '
    'reverses and reposts their journal entries on next relock.';

/// Flavours this fix applies to (values match `AppBranding.flavor`).
const List<String> dataFixFlavors = ['gmc'];

/// Per-flavour SQL statements, executed in order within one atomic transaction.
/// [admin_settings_screen.dart] reads `dataFixStatements[AppBranding.flavor]`.
///
/// v6 notes:
///  - pledge 16972 was entered a day late, so its payment_date/closure_date/
///    closed_at all need to move forward one day. closed_at is DATETIME and
///    carries a real time-of-day component (see pledge_repository.dart
///    closePledge()), so it is shifted with datetime(), not date(), to avoid
///    truncating the time part.
///  - updated_at is stamped to strftime(...'now'...) per the LEDGER RULE
///    above (not shifted like the business dates) so the staleness pass
///    detects the edit and reverses/reposts the affected journal entries the
///    next time their day is relocked.
final Map<String, List<String>> dataFixStatements = {
  'gmc': [
    // Pledge_no renames.
    "UPDATE pledges SET pledge_no = '17360' "
        "WHERE id = 132;",
    "UPDATE pledges SET pledge_no = '17361' "
        "WHERE id = 133;",
    "UPDATE pledges SET pledge_no = '17362' "
        "WHERE id = 136;",
    "UPDATE pledges SET pledge_no = '17365' "
        "WHERE id = 140;",

    // Move every payment linked to pledge 16972 (disbursement etc.) forward
    // one day, resolved via pledge_no rather than a raw id.
    "UPDATE payments SET payment_date = date(payment_date, '+1 day'), "
        "updated_at = strftime('%Y-%m-%dT%H:%M:%f', 'now', 'localtime') "
        "WHERE pledge_id = (SELECT id FROM pledges WHERE pledge_no = '16972');",

    "UPDATE pledges SET closure_date = date(closure_date, '+1 day'), "
        "closed_at = datetime(closed_at, '+1 day'), "
        "updated_at = strftime('%Y-%m-%dT%H:%M:%f', 'now', 'localtime') "
        "WHERE pledge_no = '16972';",
  ],
};

/// Optional per-flavour read-only SELECT shown before (current values) and
/// after (corrected values) the fix runs. Empty map / missing flavour = none.
final Map<String, String> dataFixVerifyQueries = {
  'gmc': "SELECT 'pledge ' || p.pledge_no AS record, "
      "p.closure_date || ' / ' || p.closed_at AS business_date "
      "FROM pledges p WHERE p.pledge_no = '16972' "
      "UNION ALL "
      "SELECT 'payment #' || pay.id || ' (' || pay.payment_type || ')', "
      "pay.payment_date "
      "FROM payments pay "
      "WHERE pay.pledge_id = "
      "(SELECT id FROM pledges WHERE pledge_no = '16972')",
};
