import 'package:flutter/material.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../data/customer_repository.dart';
import 'add_edit_customer_screen.dart';
import 'customer_detail_screen.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final _searchCtrl = TextEditingController();
  List<CustomerWithStats> _customers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_load);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_load);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final query = _searchCtrl.text.trim();
    final customers = query.isEmpty
        ? await CustomerRepository.instance.getAllCustomers()
        : await CustomerRepository.instance.searchCustomers(query);
    if (mounted) {
      setState(() {
        _customers = customers;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Customers',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                hintText: 'Search by name or phone',
                prefixIcon: const Icon(Icons.search, color: Colors.black45),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.black45),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: FlowColors.primaryLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: FlowColors.primaryLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: FlowColors.primary, width: 1.8),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 90),
                          itemCount: _customers.length,
                          itemBuilder: (ctx, i) => _CustomerCard(
                            customer: _customers[i],
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CustomerDetailScreen(
                                      customerId: _customers[i].id),
                                ),
                              );
                              _load();
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const AddEditCustomerScreen()),
          );
          _load();
        },
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.textOnNavyLarge,
        icon: const Icon(Icons.person_add),
        label: const Text('ADD NEW CUSTOMER',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_outline, size: 72, color: Colors.black26),
          const SizedBox(height: 14),
          Text(
            _searchCtrl.text.isNotEmpty
                ? 'No customers found'
                : 'No customers yet',
            style: const TextStyle(fontSize: 18, color: Colors.black45),
          ),
          if (_searchCtrl.text.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Tap + ADD NEW CUSTOMER to get started',
              style: TextStyle(fontSize: 14, color: Colors.black38),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Customer Card ────────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onTap});

  final CustomerWithStats customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: FlowColors.primaryLight, width: 1.2),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 6,
                offset: Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: FlowColors.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person,
                  color: FlowColors.primary, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name.isNotEmpty ? customer.name : '—',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: FlowColors.darkText),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.phone,
                          size: 13, color: Colors.black45),
                      const SizedBox(width: 4),
                      Text(
                        customer.phone.isNotEmpty ? customer.phone : '—',
                        style: const TextStyle(
                            fontSize: 15, color: FlowColors.medText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 13, color: Colors.black45),
                    const SizedBox(width: 4),
                    Text(
                      '${customer.totalPledges} total',
                      style: const TextStyle(
                          fontSize: 13, color: FlowColors.medText),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                customer.activePledges > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: FlowColors.greenLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${customer.activePledges} active',
                          style: const TextStyle(
                              fontSize: 12,
                              color: FlowColors.green,
                              fontWeight: FontWeight.bold),
                        ),
                      )
                    : const Text('No active',
                        style: TextStyle(
                            fontSize: 12, color: Colors.black38)),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}
