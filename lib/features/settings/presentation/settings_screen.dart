import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _rateController = TextEditingController();
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _loadRate();
  }

  Future<void> _loadRate() async {
    final prefs = await SharedPreferences.getInstance();
    final rate = prefs.getDouble('interest_rate') ?? 18.0;
    setState(() {
      _rateController.text = rate.toStringAsFixed(2);
    });
  }

  Future<void> _saveRate() async {
    final text = _rateController.text.trim();
    final rate = double.tryParse(text);

    if (rate == null || rate <= 0 || rate > 100) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invalid Rate',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          content: const Text('Please enter a valid interest rate between 0 and 100.',
              style: TextStyle(fontSize: 18)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK',
                  style: TextStyle(fontSize: 18, color: Color(0xFF1A237E))),
            ),
          ],
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('interest_rate', rate);

    setState(() {
      _saved = true;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        title: const Text(
          'Settings',
          style: TextStyle(
              color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white, size: 30),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            // Info box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE8EAF6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3949AB), width: 1.5),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF1A237E), size: 26),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Default interest rate is 18% per annum. Change only if needed.',
                      style: TextStyle(fontSize: 17, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Interest Rate Input
            const Text(
              'Interest Rate (% per annum)',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A237E)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
              ],
              style: const TextStyle(fontSize: 24),
              decoration: const InputDecoration(
                suffixText: '%',
                suffixStyle: TextStyle(fontSize: 22, color: Colors.black87),
                hintText: '18.00',
                hintStyle: TextStyle(fontSize: 22, color: Colors.grey),
              ),
              onChanged: (_) => setState(() => _saved = false),
            ),

            const SizedBox(height: 32),

            // Save Button
            ElevatedButton(
              onPressed: _saveRate,
              child: const Text('SAVE'),
            ),

            // Saved confirmation
            if (_saved) ...[
              const SizedBox(height: 20),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Interest rate saved successfully!',
                    style: TextStyle(
                        fontSize: 18,
                        color: Colors.green,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }
}