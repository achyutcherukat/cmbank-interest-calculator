import 'package:flutter/material.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../../accounts/data/bank_account_model.dart';
import '../../accounts/data/bank_account_repository.dart';
import 'edit_bank_account_screen.dart';

class ManageBankAccountsScreen extends StatefulWidget {
  const ManageBankAccountsScreen({super.key});

  @override
  State<ManageBankAccountsScreen> createState() =>
      _ManageBankAccountsScreenState();
}

class _ManageBankAccountsScreenState extends State<ManageBankAccountsScreen> {
  List<BankAccount> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await BankAccountRepository.instance.getAll();
    if (mounted) setState(() { _accounts = accounts; _loading = false; });
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final balCtrl = TextEditingController(text: '0');
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlg) => AlertDialog(
          title: const Text('Add Bank Account',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: FlowColors.primary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(labelText: 'Account Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [IndianNumberFormatter()],
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(labelText: 'Opening Balance (₹)', prefixText: '₹ '),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: FlowColors.primary),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) { setDlg(() => error = 'Enter an account name'); return; }
                final openingBal = double.tryParse(balCtrl.text.trim().replaceAll(',', '')) ?? 0.0;
                final today = DateTime.now();
                final startDate =
                    '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
                Navigator.pop(ctx2);
                await BankAccountRepository.instance.insert(
                  name: name,
                  openingBalance: openingBal,
                  startDate: startDate,
                );
                _load();
              },
              child: const Text('Add', style: TextStyle(color: FlowColors.textOnNavyLarge)),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditScreen(BankAccount acct) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => EditBankAccountScreen(account: acct)),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Manage Bank Accounts'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        icon: const Icon(Icons.add),
        label: const Text('Add Account'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accounts.isEmpty
              ? const Center(
                  child: Text('No bank accounts yet.',
                      style: TextStyle(fontSize: 16, color: Colors.black45)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: _accounts.length,
                  itemBuilder: (ctx, i) {
                    final acct = _accounts[i];
                    return FlowCard(
                      padding: const EdgeInsets.all(0),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 6),
                        leading: Icon(
                          Icons.account_balance,
                          color: acct.isActive
                              ? FlowColors.primary
                              : Colors.black26,
                          size: 26,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                acct.name,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: acct.isActive
                                        ? FlowColors.darkText
                                        : Colors.black38,
                                    decoration: acct.isActive
                                        ? null
                                        : TextDecoration.lineThrough),
                              ),
                            ),
                            if (acct.isDefault)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: FlowColors.goldLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('DEFAULT',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: FlowColors.primary,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5)),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          'Opening: ${money(acct.openingBalance)}  ·  From ${acct.startDate}',
                          style: const TextStyle(
                              fontSize: 13, color: FlowColors.medText),
                        ),
                        trailing: const Icon(Icons.edit_outlined,
                            size: 20, color: FlowColors.primary),
                        onTap: () => _openEditScreen(acct),
                      ),
                    );
                  },
                ),
    );
  }
}
