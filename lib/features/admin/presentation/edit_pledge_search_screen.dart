import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../pledges/data/pledge_model.dart';
import '../../pledges/data/pledge_repository.dart';
import '../../pledges/presentation/open_pledge_screen.dart';

// ─── Search result states ─────────────────────────────────────────────────────

enum _SearchResult { none, notFound, closed, renewalChild, cashLocked, stockLocked, eligible }

// ─── Edit Pledge Search Screen ────────────────────────────────────────────────

class EditPledgeSearchScreen extends StatefulWidget {
  const EditPledgeSearchScreen({super.key});

  @override
  State<EditPledgeSearchScreen> createState() =>
      _EditPledgeSearchScreenState();
}

class _EditPledgeSearchScreenState extends State<EditPledgeSearchScreen> {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  _SearchResult _result = _SearchResult.none;
  PledgeModel? _foundPledge;
  String? _lockedDateDisplay;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _result = _SearchResult.none;
      _foundPledge = null;
      _lockedDateDisplay = null;
    });

    try {
      final pledge = await PledgeRepository.instance.getPledgeByNumber(query);

      if (pledge == null) {
        setState(() {
          _result = _SearchResult.notFound;
          _searching = false;
        });
        return;
      }

      if (pledge.status != 'open') {
        setState(() {
          _result = _SearchResult.closed;
          _searching = false;
        });
        return;
      }

      // Check: this pledge was not itself created by a renewal/part-payment/top-up.
      // Exception: if the parent pledge was created AND closed on the same calendar
      // day (same-day migration+closure), the data error carried over from the
      // parent so editing is allowed — the parent is already closed.
      if (pledge.renewalParentId != null) {
        final parent = await PledgeRepository.instance
            .getPledgeById(pledge.renewalParentId!);
        final sameDayClosure = parent != null &&
            parent.closureDate != null &&
            parent.closureDate == parent.createdAt.substring(0, 10);
        if (!sameDayClosure) {
          setState(() {
            _result = _SearchResult.renewalChild;
            _searching = false;
          });
          return;
        }
        // Same-day migration closure — fall through to remaining checks.
      }

      final db = await AppDatabase.instance.database;

      // Check: no successor pledge (renewal_parent_id pointing to this pledge)
      final successorRows = await db.rawQuery(
        'SELECT id FROM pledges WHERE renewal_parent_id = ? LIMIT 1',
        [pledge.id],
      );
      if (successorRows.isNotEmpty) {
        setState(() {
          _result = _SearchResult.closed;
          _searching = false;
        });
        return;
      }

      // Check: daily_balance lock for pledge start date
      final balanceRows = await db.rawQuery(
        'SELECT is_locked FROM daily_balance WHERE business_date = ? LIMIT 1',
        [pledge.pledgeDate],
      );
      if (balanceRows.isNotEmpty &&
          (balanceRows.first['is_locked'] as int? ?? 0) == 1) {
        setState(() {
          _result = _SearchResult.cashLocked;
          _foundPledge = pledge;
          _lockedDateDisplay = isoToDisplay(pledge.pledgeDate);
          _searching = false;
        });
        return;
      }

      // Check: daily_stock lock for pledge start date
      final stockRows = await db.rawQuery(
        'SELECT is_locked FROM daily_stock WHERE stock_date = ? LIMIT 1',
        [pledge.pledgeDate],
      );
      if (stockRows.isNotEmpty &&
          (stockRows.first['is_locked'] as int? ?? 0) == 1) {
        setState(() {
          _result = _SearchResult.stockLocked;
          _foundPledge = pledge;
          _lockedDateDisplay = isoToDisplay(pledge.pledgeDate);
          _searching = false;
        });
        return;
      }

      setState(() {
        _result = _SearchResult.eligible;
        _foundPledge = pledge;
        _searching = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _promptReason() {
    final pledge = _foundPledge;
    if (pledge == null) return;
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReasonBottomSheet(pledgeNo: pledge.pledgeNumber),
    ).then((reason) {
      if (reason == null || reason.trim().isEmpty || !mounted) return;
      _openEditDetail(pledge, reason.trim());
    });
  }

  void _openEditDetail(PledgeModel pledge, String reason) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PledgeDetailScreen(
          pledgeId: pledge.id!,
          editEntryContext: true,
          editReason: reason,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {
          _result = _SearchResult.none;
          _foundPledge = null;
          _lockedDateDisplay = null;
          _searchCtrl.clear();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Edit Pledge'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          const FlowSectionTitle('Search Pledge'),
          TextField(
            controller: _searchCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Pledge Number',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _searching ? null : _search,
              icon: _searching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: FlowColors.textOnNavyLarge),
                    )
                  : const Icon(Icons.search),
              label: Text(_searching ? 'SEARCHING…' : 'SEARCH',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary,
                foregroundColor: FlowColors.textOnNavyLarge,
                side: const BorderSide(
                    color: FlowColors.borderOnNavy, width: 0.8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildResultCard(),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    switch (_result) {
      case _SearchResult.none:
        return const SizedBox.shrink();

      case _SearchResult.notFound:
        return _infoCard(
          icon: Icons.search_off,
          color: FlowColors.red,
          bgColor: FlowColors.redLight,
          message: 'Pledge not found.',
        );

      case _SearchResult.closed:
        return _infoCard(
          icon: Icons.lock_outline,
          color: FlowColors.medText,
          bgColor: const Color(0xFFEEEEEE),
          message: 'This pledge is closed and cannot be edited.',
        );

      case _SearchResult.renewalChild:
        return _infoCard(
          icon: Icons.block,
          color: FlowColors.medText,
          bgColor: const Color(0xFFEEEEEE),
          message:
              'This pledge was created by a renewal, part payment, or loan top-up and cannot be edited through this feature.',
        );

      case _SearchResult.cashLocked:
        return _infoCard(
          icon: Icons.lock,
          color: CMBColors.warningOrange,
          bgColor: const Color(0xFFFFF3E0),
          message:
              'Cash Book for $_lockedDateDisplay is locked. Please unlock it first via Cash Book before editing this pledge.',
        );

      case _SearchResult.stockLocked:
        return _infoCard(
          icon: Icons.lock,
          color: CMBColors.warningOrange,
          bgColor: const Color(0xFFFFF3E0),
          message:
              'Stock Register for $_lockedDateDisplay is locked. Please unlock it first via Stock Register before editing this pledge.',
        );

      case _SearchResult.eligible:
        final p = _foundPledge!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FlowColors.greenLight,
                border: Border.all(color: FlowColors.green, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: FlowColors.green, size: 20),
                      const SizedBox(width: 8),
                      Text('Pledge #${p.pledgeNumber}',
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: FlowColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _detailRow('Date', isoToDisplay(p.pledgeDate)),
                  _detailRow('Loan Amount', money(p.loanAmount)),
                  if (p.customerName.isNotEmpty)
                    _detailRow('Customer', p.customerName),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _promptReason,
                icon: const Icon(Icons.edit_note, size: 22),
                label: const Text('EDIT THIS PLEDGE',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CMBColors.warningOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _infoCard({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 15,
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: FlowColors.medText)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FlowColors.darkText)),
          ),
        ],
      ),
    );
  }
}

// ─── Reason Bottom Sheet ──────────────────────────────────────────────────────

class _ReasonBottomSheet extends StatefulWidget {
  const _ReasonBottomSheet({required this.pledgeNo});
  final String pledgeNo;

  @override
  State<_ReasonBottomSheet> createState() => _ReasonBottomSheetState();
}

class _ReasonBottomSheetState extends State<_ReasonBottomSheet> {
  final _reasonCtrl = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _reasonCtrl.addListener(() {
      final hasText = _reasonCtrl.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              decoration: const BoxDecoration(
                color: FlowColors.primary,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.edit_note,
                      color: FlowColors.goldRich, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Edit Pledge #${widget.pledgeNo}',
                    style: const TextStyle(
                      color: FlowColors.goldRich,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Reason for edit',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: FlowColors.darkText),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonCtrl,
              maxLines: 3,
              autofocus: true,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'Describe why this pledge needs to be edited…',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _hasText
                    ? () => Navigator.pop(context, _reasonCtrl.text.trim())
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.primary,
                  foregroundColor: FlowColors.textOnNavyLarge,
                  disabledBackgroundColor: Colors.black12,
                  side: const BorderSide(
                      color: FlowColors.borderOnNavy, width: 0.8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('CONTINUE',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
