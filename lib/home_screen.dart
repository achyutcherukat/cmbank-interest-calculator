import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'dart:convert';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _principalController = TextEditingController();
  final TextEditingController _fromDateController = TextEditingController();
  final TextEditingController _toDateController = TextEditingController();

  DateTime? _fromDate;
  DateTime? _toDate;
  int? _numberOfDays;

  double _simpleInterest = 0.0;
  double _totalAmount = 0.0;
  bool _hasResult = false;
  bool _showSaveButton = false;
  String _minimumChargeNote = '';
  double _interestRate = 18.0;

  @override
  void initState() {
    super.initState();
    _loadInterestRate();
    // Set To Date to today by default
    _toDate = DateTime.now();
    _toDateController.text = _formatDate(_toDate!);
  }

  Future<void> _loadInterestRate() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _interestRate = prefs.getDouble('interest_rate') ?? 18.0;
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  DateTime? _parseDate(String text) {
    try {
      final parts = text.split('/');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return null;
  }

  void _calculateDays() {
    if (_fromDate != null && _toDate != null) {
      final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      final to = DateTime(_toDate!.year, _toDate!.month, _toDate!.day);
      setState(() {
        _numberOfDays = to.difference(from).inDays; // excludes from, includes to
      });
    } else {
      setState(() {
        _numberOfDays = null;
      });
    }
  }

  Future<void> _pickDate(bool isFromDate) async {
    final initial = isFromDate
        ? (_fromDate ?? DateTime.now())
        : (_toDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1A237E),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textTheme: const TextTheme(
              bodyLarge: TextStyle(fontSize: 20),
              bodyMedium: TextStyle(fontSize: 18),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
          _fromDateController.text = _formatDate(picked);
        } else {
          _toDate = picked;
          _toDateController.text = _formatDate(picked);
        }
        _hasResult = false;
        _minimumChargeNote = '';
      });
      _calculateDays();
    }
  }

  void _calculate() async {
    final principalText = _principalController.text.trim();
    if (principalText.isEmpty) {
      _showError('Please enter the principal amount.');
      return;
    }
    final principal = double.tryParse(principalText);
    if (principal == null || principal <= 0) {
      _showError('Please enter a valid principal amount.');
      return;
    }
    if (_fromDate == null) {
      _showError('Please select or enter the From Date.');
      return;
    }
    if (_toDate == null) {
      _showError('Please select or enter the To Date.');
      return;
    }
    if (_numberOfDays == null || _numberOfDays! <= 0) {
      _showError('To Date must be after From Date.');
      return;
    }

    await _loadInterestRate();

    int effectiveDays = _numberOfDays!;
    String note = '';

    if (_numberOfDays! < 7) {
      effectiveDays = 7;
      // Calculate interest for 7 days
      double interestFor7Days = (principal * 7 / 360) * (_interestRate / 100);
      if (interestFor7Days < 50.0) {
        setState(() {
          _simpleInterest = 50.0;
          _totalAmount = principal + 50.0;
          _hasResult = true;
          _minimumChargeNote = 'Minimum interest of ₹50 applied.';
          _showSaveButton = true;
        });
        return;
      } else {
        note = 'Minimum interest for 7 days taken.';
      }
    }

    double interest = (principal * effectiveDays / 360) * (_interestRate / 100);

    setState(() {
      _simpleInterest = interest;
      _totalAmount = principal + interest;
      _hasResult = true;
      _minimumChargeNote = note;
      _showSaveButton = true;
    });
  }
  
  Future<void> _saveToHistory({
    required double principal,
    required String fromDate,
    required String toDate,
    required int numberOfDays,
    required double interestRate,
    required double simpleInterest,
    required double totalAmount,
    required String minimumChargeNote,
    required String notes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('calculation_history') ?? [];
    final entry = {
      'calculatedOn': DateTime.now().toIso8601String(),
      'principal': principal,
      'fromDate': fromDate,
      'toDate': toDate,
      'numberOfDays': numberOfDays,
      'interestRate': interestRate,
      'simpleInterest': simpleInterest,
      'totalAmount': totalAmount,
      'minimumChargeNote': minimumChargeNote,
      'notes': notes,
    };
    raw.add(json.encode(entry));
    await prefs.setStringList('calculation_history', raw);
  }

  void _showSaveDialog() {
    final TextEditingController notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Calculation',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pledge No. (optional)',
                style: TextStyle(fontSize: 18, color: Colors.black87)),
            const SizedBox(height: 10),
            TextField(
              controller: notesController,
              maxLength: 10,
              maxLines: 1,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                counterStyle: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _saveToHistory(
                principal: double.parse(_principalController.text.trim()),
                fromDate: _fromDateController.text,
                toDate: _toDateController.text,
                numberOfDays: _numberOfDays!,
                interestRate: _interestRate,
                simpleInterest: _simpleInterest,
                totalAmount: _totalAmount,
                minimumChargeNote: _minimumChargeNote,
                notes: notesController.text.trim(),
              );
              setState(() => _showSaveButton = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Calculation saved to history!',
                        style: TextStyle(fontSize: 18)),
                    backgroundColor: Color(0xFF1A237E),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Save',
                style: TextStyle(fontSize: 18, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invalid Input', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(fontSize: 18, color: Color(0xFF1A237E))),
          ),
        ],
      ),
    );
  }

  void _onFromDateTyped(String value) {
    final parsed = _parseDate(value);
    if (parsed != null) {
      _fromDate = parsed;
      _calculateDays();
    }
    setState(() {
      _hasResult = false;
      _minimumChargeNote = '';
      _showSaveButton = false;
    });
  }

  void _onToDateTyped(String value) {
    final parsed = _parseDate(value);
    if (parsed != null) {
      _toDate = parsed;
      _calculateDays();
    }
    setState(() {
      _hasResult = false;
      _minimumChargeNote = '';
      _showSaveButton = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        title: const Text(
          'CM Bank',
          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white, size: 30),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white, size: 30),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
              _loadInterestRate();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),

            // Principal Amount
            const Text('Principal Amount (₹)',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF1A237E))),
            const SizedBox(height: 8),
            TextField(
              controller: _principalController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(
                prefixText: '₹  ',
                prefixStyle: TextStyle(fontSize: 22, color: Colors.black87),
                hintText: '0.00',
                hintStyle: TextStyle(fontSize: 22, color: Colors.grey),
              ),
              onChanged: (_) => setState(() {
                _hasResult = false;
                _minimumChargeNote = '';
                _showSaveButton = false;
              }),
            ),

            const SizedBox(height: 24),

            // From Date
            const Text('From Date',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF1A237E))),
            const SizedBox(height: 8),
            TextField(
              controller: _fromDateController,
              style: const TextStyle(fontSize: 22),
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                hintText: 'DD/MM/YYYY',
                hintStyle: const TextStyle(fontSize: 20, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today, color: Color(0xFF1A237E), size: 28),
                  onPressed: () => _pickDate(true),
                ),
              ),
              onChanged: _onFromDateTyped,
            ),

            const SizedBox(height: 24),

            // To Date
            const Text('To Date',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF1A237E))),
            const SizedBox(height: 8),
            TextField(
              controller: _toDateController,
              style: const TextStyle(fontSize: 22),
              keyboardType: TextInputType.datetime,
              decoration: InputDecoration(
                hintText: 'DD/MM/YYYY',
                hintStyle: const TextStyle(fontSize: 20, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today, color: Color(0xFF1A237E), size: 28),
                  onPressed: () => _pickDate(false),
                ),
              ),
              onChanged: _onToDateTyped,
            ),

            // Number of Days
            if (_numberOfDays != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Number of days: $_numberOfDays',
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Calculate Button
            ElevatedButton(
              onPressed: _calculate,
              child: const Text('CALCULATE'),
            ),

            // Result
            if (_hasResult) ...[
              const SizedBox(height: 28),
              if (_showSaveButton)
                OutlinedButton.icon(
                  onPressed: _showSaveDialog,
                  icon: const Icon(Icons.save, color: Color(0xFF1A237E), size: 26),
                  label: const Text('SAVE',
                      style: TextStyle(fontSize: 20, color: Color(0xFF1A237E), fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 58),
                    side: const BorderSide(color: Color(0xFF1A237E), width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EAF6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3949AB), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Simple Interest',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black87)),
                        Text('₹ ${_simpleInterest.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                      ],
                    ),
                    const Divider(height: 24, thickness: 1),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Amount',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black87)),
                        Text('₹ ${_totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                      ],
                    ),
                    if (_minimumChargeNote.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.orange, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _minimumChargeNote,
                              style: const TextStyle(fontSize: 17, color: Colors.orange, fontStyle: FontStyle.italic),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}