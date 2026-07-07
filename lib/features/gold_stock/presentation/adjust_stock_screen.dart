import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../data/gold_stock_repository.dart';

/// Screen for recording a manual stock adjustment (add or remove) on an
/// unlocked day. Calls [GoldStockRepository.adjustStock] which owns the
/// lock gate, audit log, and DB transaction.
class AdjustStockScreen extends StatefulWidget {
  const AdjustStockScreen({
    super.key,
    required this.dateStr,
    required this.displayDate,
  });

  final String dateStr;
  final String displayDate;

  @override
  State<AdjustStockScreen> createState() => _AdjustStockScreenState();
}

class _AdjustStockScreenState extends State<AdjustStockScreen> {
  bool _isAdd = true;
  bool _saving = false;
  String? _error;

  final _netWeightCtrl = TextEditingController();
  final _grossWeightCtrl = TextEditingController();
  final _countCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  double get _netWeight =>
      double.tryParse(_netWeightCtrl.text) ?? 0.0;
  double get _grossWeight =>
      double.tryParse(_grossWeightCtrl.text) ?? 0.0;
  int get _count => int.tryParse(_countCtrl.text) ?? 0;

  @override
  void dispose() {
    _netWeightCtrl.dispose();
    _grossWeightCtrl.dispose();
    _countCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ─── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Reason is required.');
      return;
    }
    if (_netWeight == 0 && _grossWeight == 0 && _count == 0) {
      setState(() => _error = 'Enter at least one value (net weight, gross weight, or count).');
      return;
    }

    setState(() => _saving = true);

    try {
      await GoldStockRepository.instance.adjustStock(
        date: widget.dateStr,
        weight: _netWeight,
        grossWeight: _grossWeight,
        count: _count,
        reason: reason,
        isAdd: _isAdd,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('locked')
          ? 'This day has been locked — adjustments are not allowed.'
          : 'Failed to save. Please try again.';
      setState(() {
        _error = msg;
        _saving = false;
      });
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Adjust Stock',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.displayDate,
                style: const TextStyle(
                    fontSize: 13, color: FlowColors.textOnNavyMuted)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Add / Remove toggle ──────────────────────────────────────────
          FlowCard(
            header: 'Adjustment Type',
            child: Row(
              children: [
                Expanded(
                  child: _ModeChip(
                    label: 'Add Stock',
                    icon: Icons.add_circle_outline,
                    selected: _isAdd,
                    color: FlowColors.green,
                    onTap: () => setState(() {
                      _isAdd = true;
                      if (_error != null) _error = null;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeChip(
                    label: 'Remove Stock',
                    icon: Icons.remove_circle_outline,
                    selected: !_isAdd,
                    color: FlowColors.red,
                    onTap: () => setState(() {
                      _isAdd = false;
                      if (_error != null) _error = null;
                    }),
                  ),
                ),
              ],
            ),
          ),

          // ── Weight fields ────────────────────────────────────────────────
          FlowCard(
            header: 'Amounts (leave 0 for no change)',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _netWeightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,3}')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Net Weight (g)',
                          suffixText: 'g',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _grossWeightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,3}')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Gross Weight (g)',
                          suffixText: 'g',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _countCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Count (items)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
              ],
            ),
          ),

          // ── Reason (mandatory) ───────────────────────────────────────────
          FlowCard(
            header: 'Reason',
            child: TextField(
              controller: _reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason for adjustment *',
                hintText: 'e.g. "Found extra item during audit"',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ),

          if (_error != null) ...[
            Text(_error!,
                style:
                    const TextStyle(color: FlowColors.red, fontSize: 14)),
            const SizedBox(height: 10),
          ],

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(
                _saving ? 'Saving…' : 'SAVE ADJUSTMENT',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.primary,
                foregroundColor: FlowColors.goldRich,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.black26,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? color : Colors.black45, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? color : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
