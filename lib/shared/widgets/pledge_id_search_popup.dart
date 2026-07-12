import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/pledges/data/pledge_model.dart';
import '../../features/pledges/data/pledge_repository.dart';
import 'flow_widgets.dart';

/// Reusable "Find Pledge" bottom sheet.
///
/// Searches the `pledges` table for the entered pledge number and routes the
/// caller via [onPledgeFound] (an existing *open* pledge) or [onPledgeNotFound]
/// (a not-in-system pledge that must be migrated, or one already closed).
///
/// [contextDate] / [prefilledAmount] / [prefilledOpenDate] are passthrough
/// context the caller uses when it navigates after a callback fires (e.g. the
/// calculator's principal and from-date); they are not edited here.
Future<void> showPledgeIdSearchPopup(
  BuildContext context, {
  DateTime? contextDate,
  String? prefilledPledgeId,
  double? prefilledAmount,
  DateTime? prefilledOpenDate,
  required void Function(PledgeModel pledge) onPledgeFound,
  required void Function(String pledgeId) onPledgeNotFound,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PledgeIdSearchSheet(
      contextDate: contextDate,
      prefilledPledgeId: prefilledPledgeId,
      prefilledAmount: prefilledAmount,
      prefilledOpenDate: prefilledOpenDate,
      onPledgeFound: onPledgeFound,
      onPledgeNotFound: onPledgeNotFound,
    ),
  );
}

class _PledgeIdSearchSheet extends StatefulWidget {
  const _PledgeIdSearchSheet({
    this.contextDate,
    this.prefilledPledgeId,
    this.prefilledAmount,
    this.prefilledOpenDate,
    required this.onPledgeFound,
    required this.onPledgeNotFound,
  });

  final DateTime? contextDate;
  final String? prefilledPledgeId;
  final double? prefilledAmount;
  final DateTime? prefilledOpenDate;
  final void Function(PledgeModel pledge) onPledgeFound;
  final void Function(String pledgeId) onPledgeNotFound;

  @override
  State<_PledgeIdSearchSheet> createState() => _PledgeIdSearchSheetState();
}

enum _SearchState { idle, searching, foundOpen, foundClosed, notFound }

class _PledgeIdSearchSheetState extends State<_PledgeIdSearchSheet> {
  late final TextEditingController _ctrl;
  _SearchState _state = _SearchState.idle;
  PledgeModel? _result;
  String _searchedNo = '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.prefilledPledgeId ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final no = _ctrl.text.trim();
    if (no.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _state = _SearchState.searching;
      _searchedNo = no;
    });

    final pledge = await PledgeRepository.instance.getPledgeByNumber(no);
    if (!mounted) return;

    setState(() {
      _result = pledge;
      if (pledge == null) {
        _state = _SearchState.notFound;
      } else if (pledge.status == 'open') {
        _state = _SearchState.foundOpen;
      } else {
        _state = _SearchState.foundClosed;
      }
    });
  }

  void _open() {
    final pledge = _result;
    if (pledge == null) return;
    Navigator.pop(context);
    widget.onPledgeFound(pledge);
  }

  void _migrate() {
    Navigator.pop(context);
    widget.onPledgeNotFound(_searchedNo);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28)
            .withNavBarInset(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Find Pledge',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.primary)),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 20),
              autofocus: widget.prefilledPledgeId == null,
              decoration: const InputDecoration(
                labelText: 'Pledge Number',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                if (_state != _SearchState.idle) {
                  setState(() => _state = _SearchState.idle);
                }
              },
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed:
                    _state == _SearchState.searching ? null : _search,
                icon: _state == _SearchState.searching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: FlowColors.textOnNavyLarge))
                    : const Icon(Icons.manage_search),
                label: const Text('SEARCH',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.primary,
                  foregroundColor: FlowColors.textOnNavyLarge,
                  side: const BorderSide(
                      color: FlowColors.borderOnNavy, width: 0.8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            _buildResult(),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    switch (_state) {
      case _SearchState.idle:
      case _SearchState.searching:
        return const SizedBox.shrink();

      case _SearchState.foundOpen:
        final p = _result!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            FlowNoticeBox(
              text:
                  'Pledge found: ${p.pledgeNumber} — ${money(p.loanAmount)}',
              color: FlowColors.green,
              backgroundColor: FlowColors.greenLight,
              icon: Icons.check_circle,
            ),
            const SizedBox(height: 12),
            _navyButton('OPEN', Icons.folder_open, _open),
          ],
        );

      case _SearchState.foundClosed:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 16),
            FlowNoticeBox(
              text: '⚠ This pledge is already closed',
              color: FlowColors.orange,
              backgroundColor: FlowColors.orangeLight,
              icon: Icons.warning_amber,
            ),
          ],
        );

      case _SearchState.notFound:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const FlowNoticeBox(
              text: 'Pledge not found in system',
              color: FlowColors.red,
              backgroundColor: FlowColors.redLight,
              icon: Icons.error_outline,
            ),
            const SizedBox(height: 12),
            _navyButton('Add Existing Loan & Close', Icons.lock, _migrate),
          ],
        );
    }
  }

  Widget _navyButton(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: FlowColors.primary,
          foregroundColor: FlowColors.textOnNavyLarge,
          side: const BorderSide(color: FlowColors.borderOnNavy, width: 0.8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
