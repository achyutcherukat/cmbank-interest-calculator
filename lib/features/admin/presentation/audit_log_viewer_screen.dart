import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../data/admin_repository.dart';
import '../data/audit_log_repository.dart';
import 'table_browser_screen.dart';

class AuditLogViewerScreen extends StatefulWidget {
  const AuditLogViewerScreen({super.key});

  @override
  State<AuditLogViewerScreen> createState() => _AuditLogViewerScreenState();
}

class _AuditLogViewerScreenState extends State<AuditLogViewerScreen>
    with WidgetsBindingObserver {
  String _category = 'ALL';
  List<AuditLogEntry> _entries = [];
  bool _loading = true;

  static const _filters = <(String, String)>[
    ('ALL', 'All'),
    (AuditCategory.pledge, 'Pledge'),
    (AuditCategory.dayManagement, 'Day'),
    (AuditCategory.settings, 'Settings'),
    (AuditCategory.admin, 'Admin'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!AdminSession.isValid && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context));
      return;
    }
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !AdminSession.isValid && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries =
          await AuditLogRepository.instance.getEntries(category: _category);
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectCategory(String value) {
    if (value == _category) return;
    setState(() => _category = value);
    _load();
  }

  // ── Category colours ──────────────────────────────────────────────────────────

  (Color, Color) _categoryColors(String category) {
    switch (category) {
      case AuditCategory.pledge:
        return (FlowColors.primary, FlowColors.accent);
      case AuditCategory.dayManagement:
        return (FlowColors.orange, FlowColors.orangeLight);
      case AuditCategory.settings:
        return (FlowColors.green, FlowColors.greenLight);
      case AuditCategory.admin:
        return (FlowColors.red, FlowColors.redLight);
      default:
        return (FlowColors.medText, const Color(0xFFEEEEEE));
    }
  }

  String _formatDateTime(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    final now = DateTime.now();

    final h = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$h:$m $ampm';

    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final today = DateTime(now.year, now.month, now.day);
    final day   = DateTime(local.year, local.month, local.day);
    final diff  = today.difference(day).inDays;

    if (diff == 0) return 'Today, $timeStr';
    if (diff == 1) return 'Yesterday, $timeStr';

    final dateStr = local.year == now.year
        ? '${local.day} ${months[local.month - 1]}'
        : '${local.day} ${months[local.month - 1]} ${local.year}';
    return '$dateStr, $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Audit Log',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _filterBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? const Center(
                        child: Text('No log entries.',
                            style:
                                TextStyle(fontSize: 17, color: Colors.black45)),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40)
                              .withNavBarInset(context),
                          itemCount: _entries.length,
                          itemBuilder: (_, i) => _entryCard(_entries[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Filter bar ────────────────────────────────────────────────────────────────

  Widget _filterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ..._filters.map((f) {
              final active = _category == f.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _selectCategory(f.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? FlowColors.primary : FlowColors.bg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: active
                              ? FlowColors.primary
                              : FlowColors.primaryLight),
                    ),
                    child: Text(
                      f.$2,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: active ? Colors.white : FlowColors.primary,
                      ),
                    ),
                  ),
                ),
              );
            }),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const TableBrowserScreen()),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: FlowColors.bg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: FlowColors.primaryLight),
                ),
                child: const Text(
                  'Tables',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Entry card ────────────────────────────────────────────────────────────────

  Widget _entryCard(AuditLogEntry e) {
    final (color, bgColor) = _categoryColors(e.actionCategory);
    final hasDiff = e.oldValueJson != null || e.newValueJson != null;
    final entity = e.pledgeNo != null && e.pledgeNo!.isNotEmpty
        ? 'Pledge ${e.pledgeNo}'
        : (e.entityId != null && e.entityId!.isNotEmpty
            ? '${e.entityType} #${e.entityId}'
            : e.entityType);
    final by = (e.createdByName?.isNotEmpty ?? false)
        ? e.createdByName!
        : 'System';

    return GestureDetector(
      onTap: hasDiff
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => _AuditDetailScreen(entry: e)),
              )
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FlowColors.primaryLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _badge(e.actionCategory, color, bgColor),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          _formatDateTime(e.createdAt),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black45),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (hasDiff)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.chevron_right,
                              size: 18, color: Colors.black38),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(e.action,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: FlowColors.darkText)),
            const SizedBox(height: 2),
            Text('$entity  ·  by $by',
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
            if (e.reason != null && e.reason!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Reason: ${e.reason}',
                  style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withAlpha(80)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 0.5)),
    );
  }
}

// ─── Audit Detail (before / after diff) ───────────────────────────────────────

class _AuditDetailScreen extends StatelessWidget {
  const _AuditDetailScreen({required this.entry});

  final AuditLogEntry entry;

  String _pretty(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Log Entry'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16).withNavBarInset(context),
        children: [
          FlowCard(
            header: 'Details',
            child: Column(
              children: [
                DetailRow(label: 'Category', value: entry.actionCategory),
                DetailRow(label: 'Action', value: entry.action),
                DetailRow(
                    label: 'Entity',
                    value: entry.pledgeNo != null && entry.pledgeNo!.isNotEmpty
                        ? 'Pledge ${entry.pledgeNo}'
                        : (entry.entityId != null && entry.entityId!.isNotEmpty
                            ? '${entry.entityType} #${entry.entityId}'
                            : entry.entityType)),
                DetailRow(
                    label: 'By',
                    value: (entry.createdByName?.isNotEmpty ?? false)
                        ? entry.createdByName!
                        : 'System'),
                DetailRow(
                    label: 'When',
                    value: isoToDisplay(entry.createdAt),
                    isLast: entry.reason == null || entry.reason!.isEmpty),
                if (entry.reason != null && entry.reason!.isNotEmpty)
                  DetailRow(
                      label: 'Reason', value: entry.reason!, isLast: true),
              ],
            ),
          ),
          _jsonCard('Before', _pretty(entry.oldValueJson)),
          _jsonCard('After', _pretty(entry.newValueJson)),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _jsonCard(String title, String body) {
    return FlowCard(
      header: title.toUpperCase(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          body,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            fontFamily: 'monospace',
            color: FlowColors.darkText,
          ),
        ),
      ),
    );
  }
}
