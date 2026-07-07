/// One-off production database correction script.
///
/// This is the ONLY file that changes between fixes. To ship a new fix:
///   1. Bump [dataFixVersion] by one.
///   2. Replace [dataFixDescription] with the new fix's summary.
///   3. Update [dataFixFlavors] and [dataFixStatements] for the new fix.
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
/// LEDGER RULE (Prompt 8): any future fix that UPDATEs a `payments` or
/// `pledges` row in a way that changes its ledger-visible figures MUST also
/// set that row's `updated_at`, e.g.
///   `..., updated_at = strftime('%Y-%m-%dT%H:%M:%f', 'now', 'localtime')`
/// so relocking the affected day auto-reverses and reposts its journal
/// entry. DELETEs need nothing — the lock-time staleness pass detects the
/// orphaned entry and reverses it automatically. The v3 bank_account_id
/// clean-up below deliberately does NOT stamp updated_at: it only nulls an
/// unused reference on cash-only rows, which no posting rule reads, so
/// stamping it would cause pointless reverse-and-repost churn.
library;

const int dataFixVersion = 4;

const String dataFixDescription =
    'Correct gross_weight (2.67) and net_weight (2.60) for pledge 34544 (CMB only)';

/// Flavours this fix applies to (values match `AppBranding.flavor`).
const List<String> dataFixFlavors = ['cmb'];

/// Per-flavour SQL statements, executed in order within one atomic transaction.
/// [admin_settings_screen.dart] reads `dataFixStatements[AppBranding.flavor]`.
final Map<String, List<String>> dataFixStatements = {
  'cmb': [
    // Correct the pledge-level weight summary for pledge 34544.
    "UPDATE pledges SET gross_weight = 2.67, net_weight = 2.60, "
        "updated_at = strftime('%Y-%m-%dT%H:%M:%f', 'now', 'localtime') "
        "WHERE pledge_no = '34544';",

    // Correct the matching pledge_items row (feeds gold stock SUMs).
    "UPDATE pledge_items SET gross_weight = 2.67, net_weight = 2.60 "
        "WHERE pledge_id = (SELECT id FROM pledges WHERE pledge_no = '34544');",
  ],
};
