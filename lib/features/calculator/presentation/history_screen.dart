import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../data/calc_history_repository.dart';
import 'history_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _allHistory = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final entries = await CalcHistoryRepository.instance.getAll();
    setState(() {
      _allHistory = entries;
    });
  }

  Future<void> _deleteEntry(int id) async {
    await CalcHistoryRepository.instance.delete(id);
    _loadHistory();
  }

  Future<void> _clearAll() async {
    await CalcHistoryRepository.instance.deleteAll();
    _loadHistory();
  }

  void _confirmDeleteEntry(int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to delete this entry?',
            style: TextStyle(fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteEntry(id);
            },
            child: const Text('Delete',
                style: TextStyle(fontSize: 18, color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All History',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: const Text(
            'Are you sure you want to delete all history? This cannot be undone.',
            style: TextStyle(fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _clearAll();
            },
            child: const Text('Clear All',
                style: TextStyle(fontSize: 18, color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final entry in _allHistory) {
      final date = entry['calculatedOn'].toString().split('T')[0];
      final dt = DateTime.parse(date);
      final label = _formatGroupDate(dt);
      grouped.putIfAbsent(label, () => []).add(entry);
    }
    return grouped;
  }

  String _formatGroupDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate();
    final groupKeys = grouped.keys.toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        title: const Text('History',
            style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white, size: 30),
        actions: [
          if (_allHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white, size: 30),
              tooltip: 'Clear All',
              onPressed: _confirmClearAll,
            ),
        ],
      ),
      body: _allHistory.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No history yet.',
                      style: TextStyle(fontSize: 22, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('Your calculations will appear here.',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: groupKeys.length,
              itemBuilder: (context, groupIndex) {
                final groupLabel = groupKeys[groupIndex];
                final entries = grouped[groupLabel]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Group Header
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        groupLabel,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A237E)),
                      ),
                    ),
                    ...entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Slidable(
                          endActionPane: ActionPane(
                            motion: const DrawerMotion(),
                            children: [
                              SlidableAction(
                                onPressed: (_) =>
                                    _confirmDeleteEntry(entry['id'] as int),
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                icon: Icons.delete,
                                label: 'Delete',
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ],
                          ),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      HistoryDetailScreen(entry: entry),
                                ),
                              );
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFF3949AB), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withValues(alpha: 0.15),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '₹ ${double.parse(entry['principal'].toString()).toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1A237E)),
                                      ),
                                      Text(
                                        'SI: ₹ ${double.parse(entry['simpleInterest'].toString()).toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.date_range,
                                          size: 18, color: Colors.grey),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${entry['fromDate']}  →  ${entry['toDate']}',
                                        style: const TextStyle(
                                            fontSize: 17, color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${entry['numberOfDays']} days • ${entry['interestRate']}% p.a.',
                                        style: const TextStyle(
                                            fontSize: 16, color: Colors.grey),
                                      ),
                                      const Icon(Icons.chevron_right,
                                          color: Colors.grey, size: 24),
                                    ],
                                  ),
                                  if (entry['notes'] != null &&
                                      entry['notes'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.note_outlined,
                                            color: Color(0xFF1A237E), size: 18),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            entry['notes'].toString(),
                                            style: const TextStyle(
                                                fontSize: 15,
                                                color: Colors.black54,
                                                fontStyle: FontStyle.italic),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (entry['minimumChargeNote'] != null &&
                                      entry['minimumChargeNote']
                                          .toString()
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.info_outline,
                                            color: Colors.orange, size: 18),
                                        const SizedBox(width: 6),
                                        Text(
                                          entry['minimumChargeNote'],
                                          style: const TextStyle(
                                              fontSize: 15,
                                              color: Colors.orange,
                                              fontStyle: FontStyle.italic),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
    );
  }
}
