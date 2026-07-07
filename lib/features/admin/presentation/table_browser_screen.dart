import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/widgets/flow_widgets.dart';
import '../data/admin_repository.dart';

class _Condition {
  String column;
  final TextEditingController controller;

  _Condition({required this.column, required this.controller});

  void dispose() => controller.dispose();
}

class TableBrowserScreen extends StatefulWidget {
  const TableBrowserScreen({super.key});

  @override
  State<TableBrowserScreen> createState() => _TableBrowserScreenState();
}

class _TableBrowserScreenState extends State<TableBrowserScreen>
    with WidgetsBindingObserver {
  static const _rowLimit = 500;

  List<String> _tables = [];

  String? _selectedTable;
  List<String> _columns = [];
  final List<_Condition> _conditions = [];

  List<Map<String, Object?>> _rows = [];
  bool _loading = false;
  bool _limited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!AdminSession.isValid && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context));
    }
    _loadTables();
  }

  Future<void> _loadTables() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    if (mounted) {
      setState(() {
        _tables = rows.map((r) => r['name'] as String).toList();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _conditions) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !AdminSession.isValid && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _onTableSelected(String? table) async {
    if (table == null || table == _selectedTable) return;
    for (final c in _conditions) {
      c.dispose();
    }
    setState(() {
      _selectedTable = table;
      _columns = [];
      _conditions.clear();
      _rows = [];
      _error = null;
      _loading = true;
    });
    await _loadColumns(table);
    await _runQuery();
  }

  Future<void> _loadColumns(String table) async {
    final db = await AppDatabase.instance.database;
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (mounted) {
      setState(() => _columns = info.map((r) => r['name'] as String).toList());
    }
  }

  Future<void> _runQuery() async {
    final table = _selectedTable;
    if (table == null) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final db = await AppDatabase.instance.database;
      final active = _conditions
          .where((c) => c.column.isNotEmpty && c.controller.text.trim().isNotEmpty)
          .toList();

      var sql = 'SELECT * FROM $table';
      final args = <Object?>[];
      if (active.isNotEmpty) {
        sql += ' WHERE ${active.map((c) => '${c.column} = ?').join(' AND ')}';
        args.addAll(active.map((c) => c.controller.text.trim()));
      }
      sql += ' ORDER BY 1 DESC LIMIT ${_rowLimit + 1}';

      final results = await db.rawQuery(sql, args.isEmpty ? null : args);
      if (mounted) {
        setState(() {
          _limited = results.length > _rowLimit;
          _rows = _limited ? results.sublist(0, _rowLimit) : results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _rows = [];
          _loading = false;
        });
      }
    }
  }

  void _addCondition() {
    if (_columns.isEmpty) return;
    setState(() {
      _conditions.add(_Condition(
        column: _columns.first,
        controller: TextEditingController(),
      ));
    });
  }

  void _removeCondition(int index) {
    _conditions[index].dispose();
    setState(() => _conditions.removeAt(index));
    _runQuery();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowColors.bg,
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: FlowColors.goldRich,
        title: const Text('Table Browser',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        actions: [
          if (_selectedTable != null)
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Run Query',
              onPressed: _loading ? null : _runQuery,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tableSelector(),
          if (_selectedTable != null) _conditionsPanel(),
          if (_selectedTable != null) _statusBar(),
          Expanded(child: _resultsArea()),
        ],
      ),
    );
  }

  // ─── Table selector ────────────────────────────────────────────────────────

  Widget _tableSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedTable,
        decoration: InputDecoration(
          labelText: 'Table',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
        hint: Text(_tables.isEmpty ? 'Loading tables…' : 'Select a table…'),
        items: _tables
            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
            .toList(),
        onChanged: _tables.isEmpty ? null : _onTableSelected,
      ),
    );
  }

  // ─── Conditions panel ──────────────────────────────────────────────────────

  Widget _conditionsPanel() {
    return Container(
      color: const Color(0xFFF3F4F6),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('WHERE',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: FlowColors.medText,
                      letterSpacing: 0.8)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Add Condition'),
                style: TextButton.styleFrom(
                  foregroundColor: FlowColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _addCondition,
              ),
            ],
          ),
          if (_conditions.isNotEmpty)
            ..._conditions.asMap().entries.map((e) =>
                _conditionRow(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _conditionRow(int index, _Condition cond) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (index > 0)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('AND',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: FlowColors.medText)),
            )
          else
            const SizedBox(width: 2),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: cond.column,
              isDense: true,
              isExpanded: true,
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: Colors.white,
              ),
              items: _columns
                  .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c,
                          style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace'))))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => cond.column = val);
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('=',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: FlowColors.medText)),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              controller: cond.controller,
              decoration: InputDecoration(
                hintText: 'value',
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: Colors.white,
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _runQuery(),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _removeCondition(index),
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 16, color: FlowColors.red),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Status bar ────────────────────────────────────────────────────────────

  Widget _statusBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          if (_loading)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
          else if (_error != null)
            const SizedBox.shrink()
          else
            Text(
              _limited
                  ? '$_rowLimit rows shown (>$_rowLimit total — add conditions to narrow)'
                  : '${_rows.length} row${_rows.length == 1 ? '' : 's'}',
              style: TextStyle(
                  fontSize: 12,
                  color: _limited ? FlowColors.orange : FlowColors.medText,
                  fontWeight:
                      _limited ? FontWeight.bold : FontWeight.normal),
            ),
          const Spacer(),
          if (!_loading && _rows.isNotEmpty)
            GestureDetector(
              onTap: () => _copyAsCsv(),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy, size: 14, color: FlowColors.medText),
                  SizedBox(width: 4),
                  Text('CSV',
                      style: TextStyle(fontSize: 12, color: FlowColors.medText)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _copyAsCsv() {
    if (_rows.isEmpty) return;
    final cols = _rows.first.keys.toList();
    final buf = StringBuffer();
    buf.writeln(cols.join(','));
    for (final row in _rows) {
      buf.writeln(cols.map((c) {
        final v = row[c]?.toString() ?? '';
        return v.contains(',') || v.contains('"') || v.contains('\n')
            ? '"${v.replaceAll('"', '""')}"'
            : v;
      }).join(','));
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied as CSV'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ─── Results area ──────────────────────────────────────────────────────────

  Widget _resultsArea() {
    if (_selectedTable == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart_outlined, size: 48, color: Colors.black26),
            SizedBox(height: 12),
            Text('Select a table to view its data',
                style: TextStyle(fontSize: 15, color: Colors.black38)),
          ],
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 36, color: FlowColors.red),
              const SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13,
                      color: FlowColors.red,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
      );
    }

    if (_rows.isEmpty) {
      return const Center(
        child: Text('No rows found',
            style: TextStyle(fontSize: 15, color: Colors.black38)),
      );
    }

    final cols = _rows.first.keys.toList();

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: DataTable(
          columnSpacing: 20,
          horizontalMargin: 12,
          headingRowHeight: 38,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 48,
          headingRowColor:
              WidgetStateProperty.all(FlowColors.primary.withAlpha(18)),
          headingTextStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: FlowColors.primary,
              fontFamily: 'monospace'),
          dataTextStyle: const TextStyle(
              fontSize: 12,
              color: FlowColors.darkText,
              fontFamily: 'monospace'),
          border: TableBorder.all(
              color: FlowColors.primaryLight.withAlpha(120), width: 0.5),
          columns: cols
              .map((c) => DataColumn(label: Text(c)))
              .toList(),
          rows: _rows
              .map((row) => DataRow(
                    cells: cols
                        .map((c) => DataCell(
                              row[c] == null
                                  ? const Text('null',
                                      style: TextStyle(
                                          color: Colors.black26,
                                          fontStyle: FontStyle.italic,
                                          fontFamily: 'monospace'))
                                  : Text(row[c]!.toString()),
                            ))
                        .toList(),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
