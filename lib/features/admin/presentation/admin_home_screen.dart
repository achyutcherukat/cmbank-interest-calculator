import 'package:flutter/material.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../../ledger/presentation/ledger_home_screen.dart';
import '../data/admin_repository.dart';
import 'admin_dashboard_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_settings_screen.dart';
import 'audit_log_viewer_screen.dart';
import 'edit_pledge_search_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkTimeout();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkTimeout();
  }

  void _checkTimeout() {
    if (!AdminSession.isValid && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin session expired. Please re-authenticate.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  bool _guard() {
    if (!AdminSession.isValid) {
      _checkTimeout();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Admin',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(16, 20, 16, 40).withNavBarInset(context),
        children: [
          // Role banner
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: FlowColors.accent,
              border:
                  Border.all(color: FlowColors.primaryLight, width: 1.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user,
                    color: FlowColors.primary, size: 28),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Logged in as Admin',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: FlowColors.primary)),
                    SizedBox(height: 2),
                    Text('Full access — session expires in 30 min',
                        style: TextStyle(
                            fontSize: 13, color: FlowColors.medText)),
                  ],
                ),
              ],
            ),
          ),

          _navCard(
            icon: Icons.bar_chart,
            label: 'Dashboard',
            subtitle: 'Portfolio, ageing & business overview',
            color: FlowColors.primary,
            onTap: () {
              if (!_guard()) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminDashboardScreen()),
              ).then((_) => _checkTimeout());
            },
          ),
          const SizedBox(height: 14),
          _navCard(
            icon: Icons.analytics,
            label: 'Reports',
            subtitle: 'Period-wise pledge, gold & financial reports',
            color: FlowColors.primary,
            onTap: () {
              if (!_guard()) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminReportsScreen()),
              ).then((_) => _checkTimeout());
            },
          ),
          const SizedBox(height: 14),
          _navCard(
            icon: Icons.menu_book,
            label: 'Ledger',
            subtitle: 'General ledger, trial balance, P&L & balance sheet',
            color: FlowColors.primary,
            onTap: () {
              if (!_guard()) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LedgerHomeScreen()),
              ).then((_) => _checkTimeout());
            },
          ),
          const SizedBox(height: 14),
          _navCard(
            icon: Icons.edit_note,
            label: 'Edit Pledge',
            subtitle: 'Admin correction of an existing open pledge',
            color: FlowColors.primary,
            onTap: () {
              if (!_guard()) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const EditPledgeSearchScreen()),
              ).then((_) => _checkTimeout());
            },
          ),
          const SizedBox(height: 14),
          _navCard(
            icon: Icons.settings,
            label: 'Settings',
            subtitle: 'Rates, PINs, masters, backup & day management',
            color: FlowColors.primary,
            onTap: () {
              if (!_guard()) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminSettingsScreen()),
              ).then((_) => _checkTimeout());
            },
          ),
          const SizedBox(height: 14),
          _navCard(
            icon: Icons.history,
            label: 'Audit Log',
            subtitle: 'View all logged actions & changes',
            color: FlowColors.primary,
            onTap: () {
              if (!_guard()) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AuditLogViewerScreen()),
              ).then((_) => _checkTimeout());
            },
          ),
        ],
      ),
    );
  }

  Widget _navCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Row(
            children: [
              Icon(icon, color: FlowColors.goldRich, size: 34),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: FlowColors.textOnNavyLarge)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 14, color: FlowColors.textOnNavySmall)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: FlowColors.goldRich, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
