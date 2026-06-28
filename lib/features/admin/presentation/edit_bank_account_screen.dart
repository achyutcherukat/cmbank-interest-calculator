import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../accounts/data/bank_account_model.dart';
import '../../accounts/data/bank_account_repository.dart';

class EditBankAccountScreen extends StatefulWidget {
  const EditBankAccountScreen({super.key, required this.account});
  final BankAccount account;

  @override
  State<EditBankAccountScreen> createState() => _EditBankAccountScreenState();
}

class _EditBankAccountScreenState extends State<EditBankAccountScreen> {
  late BankAccount _account;
  late TextEditingController _nameCtrl;
  bool _saving = false;
  bool _nameDirty = false;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _nameCtrl = TextEditingController(text: _account.name);
    _nameCtrl.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    final dirty = _nameCtrl.text.trim() != _account.name;
    if (dirty != _nameDirty) setState(() => _nameDirty = dirty);
  }

  Future<void> _reload() async {
    final updated = await BankAccountRepository.instance.getById(_account.id!);
    if (mounted && updated != null) {
      setState(() {
        _account = updated;
        _nameDirty = _nameCtrl.text.trim() != updated.name;
      });
    }
  }

  Future<void> _rename() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || name == _account.name) return;
    setState(() => _saving = true);
    await BankAccountRepository.instance.rename(_account.id!, name);
    await _reload();
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account renamed successfully')));
    }
  }

  Future<void> _setDefault() async {
    setState(() => _saving = true);
    await BankAccountRepository.instance.setDefault(_account.id!);
    await _reload();
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Set as default account')));
    }
  }

  Future<void> _toggleActive() async {
    final willActivate = !_account.isActive;
    setState(() => _saving = true);
    await BankAccountRepository.instance
        .setActive(_account.id!, active: willActivate);
    await _reload();
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              willActivate ? 'Account reactivated' : 'Account deactivated')));
    }
  }

  String _fmtDate(String iso) {
    final parts = iso.split('T').first.split('-');
    if (parts.length < 3) return iso;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: CMBColors.pageBackground,
      appBar: AppBar(
        backgroundColor: CMBColors.navy,
        foregroundColor: CMBColors.goldRich,
        title: const Text('Edit Account',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerCard(),
            const SizedBox(height: 4),
            _detailsCard(),
            _renameCard(),
            _actionsCard(),
          ],
        ),
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: CMBColors.navy,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CMBColors.borderOnNavy, width: 0.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: CMBColors.goldRich.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance,
                color: CMBColors.goldRich, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_account.name,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: CMBColors.textOnNavyLarge)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (_account.isDefault) _badge('DEFAULT', CMBColors.goldRich),
                    if (_account.isDefault && !_account.isActive)
                      const SizedBox(width: 6),
                    if (!_account.isActive)
                      _badge('INACTIVE', const Color(0xFFEF9A9A)),
                    if (_account.isActive && !_account.isDefault)
                      _badge('ACTIVE', const Color(0xFF81C784)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5)),
    );
  }

  Widget _detailsCard() {
    return FlowCard(
      header: 'Account Details',
      child: Column(
        children: [
          _detailRow(Icons.account_balance_wallet_outlined, 'Opening Balance',
              money(_account.openingBalance)),
          const Divider(height: 20, thickness: 0.5),
          _detailRow(Icons.calendar_today_outlined, 'Active Since',
              _fmtDate(_account.startDate)),
          const Divider(height: 20, thickness: 0.5),
          _detailRow(Icons.access_time_outlined, 'Created',
              _fmtDate(_account.createdAt)),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: CMBColors.textOnLight.withValues(alpha: 0.45)),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                fontSize: 14, color: CMBColors.textOnLight)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: CMBColors.textOnLight)),
      ],
    );
  }

  Widget _renameCard() {
    return FlowCard(
      header: 'Rename Account',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'Account Name',
              prefixIcon: Icon(Icons.drive_file_rename_outline),
            ),
            onSubmitted: (_) => _nameDirty && !_saving ? _rename() : null,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _nameDirty && !_saving ? _rename : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: CMBColors.goldRich))
                  : const Icon(Icons.save_outlined, size: 20),
              label: const Text('SAVE NAME',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: CMBColors.navy,
                foregroundColor: CMBColors.goldRich,
                disabledBackgroundColor:
                    CMBColors.navy.withValues(alpha: 0.25),
                disabledForegroundColor:
                    CMBColors.goldRich.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionsCard() {
    return FlowCard(
      header: 'Account Settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_account.isDefault) ...[
            _infoRow(
              Icons.star,
              CMBColors.goldRich,
              'This is the default account.',
              'Set another account as default first to change this.',
            ),
            const SizedBox(height: 14),
          ],
          if (!_account.isDefault && _account.isActive) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _setDefault,
                icon: const Icon(Icons.star_outline, size: 18),
                label: const Text('Set as Default Account'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CMBColors.navy,
                  side: const BorderSide(color: CMBColors.navy),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _account.isDefault || _saving ? null : _toggleActive,
              icon: Icon(
                  _account.isActive
                      ? Icons.block_outlined
                      : Icons.check_circle_outline,
                  size: 18),
              label: Text(_account.isActive
                  ? 'Deactivate Account'
                  : 'Reactivate Account'),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    _account.isActive ? FlowColors.red : FlowColors.green,
                side: BorderSide(
                    color: _account.isActive
                        ? FlowColors.red.withValues(alpha: 0.6)
                        : FlowColors.green.withValues(alpha: 0.6)),
                disabledForegroundColor: Colors.black26,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (_account.isDefault) ...[
            const SizedBox(height: 8),
            const Text(
              'Cannot deactivate the default account.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, Color color, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: CMBColors.textOnLight)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
