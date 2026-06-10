import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../features/calculator/data/interest_calculator.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/payment_model.dart';
import '../data/pledge_model.dart';
import '../data/pledge_repository.dart';

// ─── Open Pledge Screen ───────────────────────────────────────────────────────

class OpenPledgeScreen extends StatefulWidget {
  const OpenPledgeScreen({super.key});

  @override
  State<OpenPledgeScreen> createState() => _OpenPledgeScreenState();
}

class _OpenPledgeScreenState extends State<OpenPledgeScreen> {
  final _searchController = TextEditingController();
  List<PledgeModel> _recentPledges = [];
  bool _notFound = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final pledges = await PledgeRepository.instance.getOpenPledges(limit: 10);
    if (mounted) setState(() { _recentPledges = pledges; _loading = false; });
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final pledge = await PledgeRepository.instance.getPledgeByNumber(query);
    if (!mounted) return;
    if (pledge == null || pledge.status != 'open') {
      setState(() => _notFound = true);
      return;
    }
    setState(() => _notFound = false);
    _openDetail(pledge);
  }

  void _openDetail(PledgeModel pledge) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PledgeDetailScreen(pledgeId: pledge.id!)),
    ).then((_) => _loadRecent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Open Pledge'),
      ),
      backgroundColor: FlowColors.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRecent,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const FlowSectionTitle('Search by Pledge Number'),
                  TextField(
                    controller: _searchController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Pledge Number',
                      hintText: 'e.g. 3201',
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _search,
                      icon: const Icon(Icons.search),
                      label: const Text('SEARCH'),
                    ),
                  ),
                  if (_notFound) ...[
                    const SizedBox(height: 10),
                    const FlowCard(
                      backgroundColor: FlowColors.redLight,
                      borderColor: FlowColors.red,
                      child: Text(
                        'No open pledge found for that number.',
                        style: TextStyle(
                            color: FlowColors.red, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const FlowSectionTitle('Recent Open Pledges'),
                  if (_recentPledges.isEmpty)
                    const FlowCard(
                      child: Text('No open pledges.',
                          style: TextStyle(color: Colors.black54)),
                    )
                  else
                    ..._recentPledges.map(
                      (p) => GestureDetector(
                        onTap: () => _openDetail(p),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                                color: FlowColors.primaryLight, width: 1.5),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x0A000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Pledge ${p.pledgeNumber}',
                                        style: const TextStyle(
                                            color: FlowColors.primary,
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 3),
                                    Text(
                                        '${p.pledgeDate}  ·  ${money(p.loanAmount)}',
                                        style: const TextStyle(
                                            fontSize: 14,
                                            color: FlowColors.medText)),
                                    if (p.customerName.isNotEmpty)
                                      Text(p.customerName,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black45)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: Colors.black38),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ─── Pledge Detail Screen ─────────────────────────────────────────────────────

class PledgeDetailScreen extends StatefulWidget {
  const PledgeDetailScreen({super.key, required this.pledgeId});
  final int pledgeId;

  @override
  State<PledgeDetailScreen> createState() => _PledgeDetailScreenState();
}

class _PledgeDetailScreenState extends State<PledgeDetailScreen> {
  PledgeModel? _pledge;
  bool _loading = true;
  String? _itemPhotoPath;
  String? _idProofPath;

  Future<void> _goClose(PledgeModel p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ClosePledgeScreen(pledge: p)),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _goRenew(PledgeModel p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RenewalScreen(pledge: p)),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pledge = await PledgeRepository.instance.getPledgeById(widget.pledgeId);
    final items = await PledgeRepository.instance.getItemsForPledge(widget.pledgeId);

    String? itemPhoto = items.isNotEmpty ? items.first.photoPath : null;
    String? idProof;

    if (pledge != null) {
      // Derive ID proof path from pledge number (saved as {pledgeNo}_idproof.jpg)
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final path = '${docsDir.path}/pledge_photos/${pledge.pledgeNumber}_idproof.jpg';
        if (File(path).existsSync()) idProof = path;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _pledge = pledge;
        _itemPhotoPath = itemPhoto;
        _idProofPath = idProof;
        _loading = false;
      });
    }
  }

  void _showInterestPreview(PledgeModel p, DateTime fromDate, DateTime today) {
    const offsets = [0, 1, 7, 30];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Interest Preview',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                color: FlowColors.primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '* Minimum 7 days & ₹50 applied where applicable.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            ...offsets.map((extra) {
              final targetDate = today.add(Duration(days: extra));
              final calc = InterestCalculator.calculate(
                principal: p.loanAmount,
                fromDate: fromDate,
                toDate: targetDate,
                ratePercent: p.interestRate,
              );
              final days = InterestCalculator.effectiveDays(fromDate, targetDate);
              final label = extra == 0
                  ? 'Today'
                  : extra == 1
                      ? 'Tomorrow'
                      : '+$extra Days';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$label ($days d)',
                        style: const TextStyle(fontSize: 15, color: Colors.black54)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Int: ${money(calc.interest)}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        Text('Total: ${money(calc.total)}',
                            style: const TextStyle(
                                fontSize: 14, color: FlowColors.primary)),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE',
                style: TextStyle(fontSize: 17, color: FlowColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final p = _pledge;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(
            backgroundColor: FlowColors.primary,
            foregroundColor: Colors.white,
            title: const Text('Pledge')),
        body: const Center(child: Text('Pledge not found.')),
      );
    }

    final fromDate = DateTime.tryParse(p.pledgeDate) ?? DateTime.now();
    final today = DateTime.now();
    final actualDays = today.difference(fromDate).inDays;
    final effectiveDays = InterestCalculator.effectiveDays(fromDate, today);
    final calc = InterestCalculator.calculate(
      principal: p.loanAmount,
      fromDate: fromDate,
      toDate: today,
      ratePercent: p.interestRate,
    );
    final minApplied = actualDays < 7 || calc.note.isNotEmpty;

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: Text('Pledge ${p.pledgeNumber}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status + age
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const StatusBadge(
                  text: 'OPEN',
                  color: FlowColors.green,
                  backgroundColor: FlowColors.greenLight),
              Text('$actualDays days elapsed',
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
          if (minApplied)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '* Interest calculated using minimum 7 days / ₹50 where applicable.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 14),

          // Pledge details
          FlowCard(
            child: Column(
              children: [
                const FlowCardTitle('Pledge Details'),
                DetailRow(label: 'Pledge No.', value: p.pledgeNumber),
                if (p.customerName.isNotEmpty)
                  DetailRow(label: 'Customer', value: p.customerName),
                if (p.customerPhone != null)
                  DetailRow(label: 'Phone', value: p.customerPhone!),
                DetailRow(label: 'Pledge Date', value: p.pledgeDate),
                DetailRow(label: 'Loan Amount', value: money(p.loanAmount)),
                DetailRow(
                    label: 'Interest Rate',
                    value: '${p.interestRate.toStringAsFixed(0)}% p.a.',
                    isLast: true),
              ],
            ),
          ),

          // Gold details + photos
          FlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FlowCardTitle('Gold Details'),
                if (p.netWeight > 0)
                  DetailRow(label: 'Weight', value: '${p.netWeight.toStringAsFixed(2)} g'),
                if (p.purity.isNotEmpty)
                  DetailRow(label: 'Purity', value: p.purity, isLast: true),
                if (_itemPhotoPath != null || _idProofPath != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (_itemPhotoPath != null && File(_itemPhotoPath!).existsSync())
                        _photoThumb(_itemPhotoPath!, 'Gold Item'),
                      if (_itemPhotoPath != null && _idProofPath != null)
                        const SizedBox(width: 12),
                      if (_idProofPath != null && File(_idProofPath!).existsSync())
                        _photoThumb(_idProofPath!, 'ID Proof'),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Renewal chain
          if (p.renewalParentId != null)
            FlowCard(
              backgroundColor: FlowColors.accent,
              child: Text(
                'Renewal: parent pledge #${p.renewalParentId}',
                style: const TextStyle(
                    color: FlowColors.primary, fontWeight: FontWeight.bold),
              ),
            ),

          // Current interest due
          FlowCard(
            backgroundColor: FlowColors.accent,
            child: Column(
              children: [
                const FlowCardTitle('Interest as of Today'),
                DetailRow(
                    label: 'Days (effective)',
                    value: '$effectiveDays days'),
                DetailRow(label: 'Interest Due', value: money(calc.interest)),
                DetailRow(
                    label: 'Total Due', value: money(calc.total), isLast: true),
              ],
            ),
          ),

          // Interest preview button
          OutlinedButton.icon(
            onPressed: () => _showInterestPreview(p, fromDate, today),
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('VIEW INTEREST PREVIEW',
                style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton.icon(
              onPressed: () => _goClose(p),
              icon: const Icon(Icons.check_circle_outline, size: 26),
              label: const Text('CLOSE PLEDGE',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton.icon(
              onPressed: () => _goRenew(p),
              icon: const Icon(Icons.refresh, size: 26),
              label: const Text('RENEW PLEDGE',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _photoThumb(String path, String label) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => _PhotoViewScreen(file: File(path))),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(path),
              height: 80,
              width: 100,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

// ─── Photo Fullscreen Viewer ──────────────────────────────────────────────────

class _PhotoViewScreen extends StatelessWidget {
  const _PhotoViewScreen({required this.file});
  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Photo'),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.file(file),
        ),
      ),
    );
  }
}

// ─── Close Pledge Screen ──────────────────────────────────────────────────────

class ClosePledgeScreen extends StatefulWidget {
  const ClosePledgeScreen({super.key, required this.pledge});
  final PledgeModel pledge;

  @override
  State<ClosePledgeScreen> createState() => _ClosePledgeScreenState();
}

class _ClosePledgeScreenState extends State<ClosePledgeScreen> {
  String _paymentMode = 'cash';
  final _cashController = TextEditingController();
  final _upiController = TextEditingController();
  bool _isSaving = false;
  String? _donePledgeNo;
  double? _doneTotal;

  late final double _interest;
  late final double _total;

  @override
  void initState() {
    super.initState();
    final from = DateTime.tryParse(widget.pledge.pledgeDate) ?? DateTime.now();
    final calc = InterestCalculator.calculate(
      principal: widget.pledge.loanAmount,
      fromDate: from,
      toDate: DateTime.now(),
      ratePercent: widget.pledge.interestRate,
    );
    _interest = calc.interest;
    _total = calc.total;
    _cashController.text = _total.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _cashController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  Future<void> _confirmClose() async {
    if (_paymentMode == 'split') {
      final cash = double.tryParse(_cashController.text.trim()) ?? 0;
      final upi = double.tryParse(_upiController.text.trim()) ?? 0;
      if ((cash + upi - _total).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cash + UPI must equal ${money(_total)}.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Closure',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: Text(
          'Close pledge ${widget.pledge.pledgeNumber}?\n\nTotal collected: ${money(_total)}',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 18, color: Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: FlowColors.green),
            child: const Text('CLOSE',
                style: TextStyle(fontSize: 18, color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      double cashAmt = _total;
      double upiAmt = 0;
      if (_paymentMode == 'upi') {
        cashAmt = 0;
        upiAmt = _total;
      } else if (_paymentMode == 'split') {
        cashAmt = double.tryParse(_cashController.text.trim()) ?? 0;
        upiAmt = double.tryParse(_upiController.text.trim()) ?? 0;
      }

      final now = DateTime.now();
      final payment = PaymentModel(
        pledgeId: widget.pledge.id!,
        paymentDate: now.toIso8601String(),
        amount: _total,
        cashAmount: cashAmt,
        upiAmount: upiAmt,
        paymentType: 'closure',
        paymentMode: _paymentMode,
        createdAt: now.toIso8601String(),
      );

      await PledgeRepository.instance.closePledge(widget.pledge.id!, payment);

      if (mounted) {
        setState(() {
          _donePledgeNo = widget.pledge.pledgeNumber;
          _doneTotal = _total;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error closing pledge: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_donePledgeNo != null) {
      return _DoneScreen(
        title: 'Pledge Closed',
        message: 'Pledge $_donePledgeNo successfully closed.',
        detail: 'Total collected: ${money(_doneTotal ?? 0)}',
      );
    }

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Close Pledge'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FlowCard(
            backgroundColor: FlowColors.accent,
            child: Column(
              children: [
                const FlowCardTitle('Closure Summary'),
                DetailRow(label: 'Principal', value: money(widget.pledge.loanAmount)),
                DetailRow(label: 'Interest', value: money(_interest)),
                DetailRow(label: 'Total Due', value: money(_total), isLast: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const FlowSectionTitle('Payment Mode'),
          Row(
            children: [
              Expanded(child: _modeButton('cash', 'Cash')),
              const SizedBox(width: 10),
              Expanded(child: _modeButton('upi', 'UPI')),
            ],
          ),
          const SizedBox(height: 10),
          _modeButton('split', 'Split Payment'),
          if (_paymentMode == 'split') ...[
            const SizedBox(height: 14),
            _amountField('Cash Amount (₹)', _cashController),
            _amountField('UPI Amount (₹)', _upiController),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _confirmClose,
              icon: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_isSaving ? 'CLOSING…' : 'CONFIRM CLOSURE',
                  style: const TextStyle(fontSize: 20)),
              style: ElevatedButton.styleFrom(backgroundColor: FlowColors.green),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _modeButton(String value, String label) {
    final selected = _paymentMode == value;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => setState(() => _paymentMode = value),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? FlowColors.accent : Colors.white,
          side: BorderSide(
              color: selected ? FlowColors.primary : Colors.black26, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 17,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _amountField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
        ],
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

// ─── Renewal Screen ───────────────────────────────────────────────────────────

class RenewalScreen extends StatefulWidget {
  const RenewalScreen({super.key, required this.pledge});
  final PledgeModel pledge;

  @override
  State<RenewalScreen> createState() => _RenewalScreenState();
}

class _RenewalScreenState extends State<RenewalScreen> {
  String? _renewalType;
  bool _isSaving = false;
  String? _newPledgeNo;
  String _nextPledgeNo = '…';

  late final double _interest;
  late final double _total;
  late final double _capitalised;

  @override
  void initState() {
    super.initState();
    final from = DateTime.tryParse(widget.pledge.pledgeDate) ?? DateTime.now();
    final calc = InterestCalculator.calculate(
      principal: widget.pledge.loanAmount,
      fromDate: from,
      toDate: DateTime.now(),
      ratePercent: widget.pledge.interestRate,
    );
    _interest = calc.interest;
    _total = calc.total;
    _capitalised = widget.pledge.loanAmount + _interest;
    _loadNextNo();
  }

  Future<void> _loadNextNo() async {
    final no = await PledgeRepository.instance.nextPledgeNumber();
    if (mounted) setState(() => _nextPledgeNo = no);
  }

  Future<void> _confirmRenewal() async {
    if (_renewalType == null) return;
    final newPrincipal =
        _renewalType == 'pay' ? widget.pledge.loanAmount : _capitalised;
    final payInterest = _renewalType == 'pay';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Renewal',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: Text(
          payInterest
              ? 'Customer pays interest (${money(_interest)}).\nNew pledge amount: ${money(newPrincipal)}'
              : 'Interest capitalised.\nNew pledge amount: ${money(newPrincipal)}',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 18, color: Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RENEW',
                style: TextStyle(fontSize: 18, color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      PaymentModel? interestPayment;
      if (payInterest) {
        interestPayment = PaymentModel(
          pledgeId: widget.pledge.id!,
          paymentDate: now.toIso8601String(),
          amount: _interest,
          cashAmount: _interest,
          upiAmount: 0,
          paymentType: 'interest',
          paymentMode: 'cash',
          createdAt: now.toIso8601String(),
        );
      }

      final newNo = await PledgeRepository.instance.renewPledge(
        widget.pledge.id!,
        newPrincipal,
        interestPayment,
      );

      if (mounted) setState(() { _newPledgeNo = newNo; _isSaving = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error renewing pledge: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_newPledgeNo != null) {
      return _DoneScreen(
        title: 'Pledge Renewed',
        message: 'Old pledge ${widget.pledge.pledgeNumber} closed.',
        detail: 'New pledge $_newPledgeNo is open.',
      );
    }

    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Renew Pledge'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FlowCard(
            backgroundColor: FlowColors.accent,
            child: Column(
              children: [
                const FlowCardTitle('Current Pledge'),
                DetailRow(label: 'Principal', value: money(widget.pledge.loanAmount)),
                DetailRow(label: 'Interest Due', value: money(_interest)),
                DetailRow(label: 'Total Due', value: money(_total), isLast: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const FlowSectionTitle('Renewal Type'),
          _renewalButton(
            'pay',
            'Pay Interest & Renew',
            'Customer pays ${money(_interest)}. New principal: ${money(widget.pledge.loanAmount)}',
          ),
          _renewalButton(
            'capitalise',
            'Capitalise Interest',
            'No cash needed. New principal: ${money(_capitalised)}',
          ),
          if (_renewalType != null) ...[
            const SizedBox(height: 12),
            FlowCard(
              child: Column(
                children: [
                  const FlowCardTitle('New Pledge Details'),
                  DetailRow(label: 'New Pledge No.', value: _nextPledgeNo),
                  DetailRow(
                      label: 'New Amount',
                      value: _renewalType == 'pay'
                          ? money(widget.pledge.loanAmount)
                          : money(_capitalised)),
                  DetailRow(
                      label: 'Interest Rate',
                      value:
                          '${widget.pledge.interestRate.toStringAsFixed(0)}% p.a.'),
                  const DetailRow(
                      label: 'Gold Items',
                      value: 'Carried forward',
                      isLast: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _confirmRenewal,
                icon: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isSaving ? 'RENEWING…' : 'CONFIRM RENEWAL',
                    style: const TextStyle(fontSize: 20)),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _renewalButton(String value, String title, String subtitle) {
    final selected = _renewalType == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        onPressed: () => setState(() => _renewalType = value),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: selected ? FlowColors.accent : Colors.white,
          side: BorderSide(
              color: selected ? FlowColors.primary : Colors.black26, width: 2),
          padding: const EdgeInsets.all(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

// ─── Done Screen ──────────────────────────────────────────────────────────────

class _DoneScreen extends StatelessWidget {
  const _DoneScreen(
      {required this.title, required this.message, required this.detail});
  final String title;
  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: Text(title),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: FlowColors.green, size: 72),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 24,
                      color: FlowColors.green,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18)),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('BACK TO HOME'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
