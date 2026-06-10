import 'package:flutter/material.dart';

import '../../../shared/widgets/flow_widgets.dart';
import '../data/sample_pledge.dart';

class OpenPledgeScreen extends StatefulWidget {
  const OpenPledgeScreen({super.key});

  @override
  State<OpenPledgeScreen> createState() => _OpenPledgeScreenState();
}

class _OpenPledgeScreenState extends State<OpenPledgeScreen> {
  final _searchController = TextEditingController();
  bool _notFound = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    final query = _searchController.text.trim();
    final pledge = samplePledges.where((p) => p.id == query && p.status == 'open').firstOrNull;
    if (pledge == null) {
      setState(() => _notFound = true);
      return;
    }
    _openDetail(pledge);
  }

  void _openDetail(SamplePledge pledge) {
    setState(() => _notFound = false);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PledgeDetailScreen(pledge: pledge)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = samplePledges.where((p) => p.status == 'open').toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Open Pledge'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const FlowSectionTitle('Search Pledge'),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(labelText: 'Pledge Number', hintText: 'e.g. 3201'),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _search,
            icon: const Icon(Icons.search),
            label: const Text('SEARCH'),
          ),
          if (_notFound)
            const FlowCard(
              backgroundColor: FlowColors.redLight,
              borderColor: FlowColors.red,
              child: Text(
                'No open pledge found for that number.',
                style: TextStyle(color: FlowColors.red, fontWeight: FontWeight.bold),
              ),
            ),
          const SizedBox(height: 10),
          FlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Try These Sample Pledges', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 12),
                ...open.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: FlowColors.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      title: Text('Pledge ${p.id}', style: const TextStyle(color: FlowColors.primary, fontWeight: FontWeight.bold)),
                      subtitle: Text('${p.date} - ${money(p.amount)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openDetail(p),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PledgeDetailScreen extends StatelessWidget {
  const PledgeDetailScreen({super.key, required this.pledge});

  final SamplePledge pledge;

  @override
  Widget build(BuildContext context) {
    final previewDays = [0, 1, 7, 30];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: FlowColors.primary,
        foregroundColor: Colors.white,
        title: Text('Pledge ${pledge.id}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const StatusBadge(text: 'OPEN', color: FlowColors.green, backgroundColor: FlowColors.greenLight),
              Text('${pledge.days} days old', style: const TextStyle(color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 14),
          FlowCard(
            child: Column(
              children: [
                DetailRow(label: 'Pledge No.', value: pledge.id),
                DetailRow(label: 'Pledge Date', value: pledge.date),
                DetailRow(label: 'Loan Amount', value: money(pledge.amount)),
                DetailRow(label: 'Interest Rate', value: '${pledge.rate.toStringAsFixed(0)}% p.a.', isLast: true),
              ],
            ),
          ),
          FlowCard(
            child: Column(
              children: [
                DetailRow(label: 'Item', value: pledge.gold),
                const DetailRow(label: 'Photo', value: 'View Photo', isLast: true, valueColor: Colors.black54),
              ],
            ),
          ),
          if (pledge.renewalChain.isNotEmpty)
            FlowCard(
              backgroundColor: FlowColors.accent,
              child: Text(
                'Renewal chain: ${pledge.renewalChain.join(' -> ')} -> ${pledge.id}',
                style: const TextStyle(color: FlowColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
          FlowCard(
            backgroundColor: FlowColors.accent,
            child: Column(
              children: [
                DetailRow(label: 'Days Elapsed', value: '${pledge.days} days'),
                DetailRow(label: 'Interest Due', value: money(pledge.interest)),
                DetailRow(label: 'Total Due', value: money(pledge.total), isLast: true),
              ],
            ),
          ),
          FlowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quick Interest Preview', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 10),
                ...previewDays.map((extra) {
                  final days = pledge.days + extra;
                  final interest = pledge.interest + (pledge.amount * extra / 360) * (pledge.rate / 100);
                  final total = pledge.amount + interest;
                  final label = extra == 0 ? 'Today' : extra == 1 ? 'Tomorrow' : '$extra Days';
                  return DetailRow(
                    label: '$label ($days days)',
                    value: '${money(interest)} | Total ${money(total)}',
                    isLast: extra == previewDays.last,
                  );
                }),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClosePledgeScreen(pledge: pledge))),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('CLOSE PLEDGE'),
            style: ElevatedButton.styleFrom(backgroundColor: FlowColors.green),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RenewalScreen(pledge: pledge))),
            icon: const Icon(Icons.refresh),
            label: const Text('RENEW PLEDGE'),
          ),
        ],
      ),
    );
  }
}

class ClosePledgeScreen extends StatefulWidget {
  const ClosePledgeScreen({super.key, required this.pledge});

  final SamplePledge pledge;

  @override
  State<ClosePledgeScreen> createState() => _ClosePledgeScreenState();
}

class _ClosePledgeScreenState extends State<ClosePledgeScreen> {
  String? _method;
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    if (_confirmed) {
      return _DoneScreen(
        title: 'Pledge Closed',
        message: 'Pledge ${widget.pledge.id} successfully closed',
        detail: 'Total collected: ${money(widget.pledge.total)}',
      );
    }

    return Scaffold(
      appBar: AppBar(backgroundColor: FlowColors.primary, foregroundColor: Colors.white, title: const Text('Close Pledge')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FlowCard(
            backgroundColor: FlowColors.accent,
            child: Column(
              children: [
                DetailRow(label: 'Principal', value: money(widget.pledge.amount)),
                DetailRow(label: 'Interest', value: money(widget.pledge.interest)),
                DetailRow(label: 'Total Due', value: money(widget.pledge.total), isLast: true),
              ],
            ),
          ),
          const FlowSectionTitle('How was payment received?'),
          Row(
            children: [
              Expanded(child: _methodButton('cash', 'Cash')),
              const SizedBox(width: 10),
              Expanded(child: _methodButton('upi', 'UPI')),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => setState(() => _method = 'split'),
            icon: const Icon(Icons.call_split),
            label: const Text('SPLIT PAYMENT'),
          ),
          if (_method == 'split')
            FlowCard(
              child: Column(
                children: [
                  TextField(decoration: InputDecoration(labelText: 'Cash Amount', hintText: widget.pledge.total.toStringAsFixed(2))),
                  const SizedBox(height: 12),
                  const TextField(decoration: InputDecoration(labelText: 'UPI Amount', hintText: '0.00')),
                  const SizedBox(height: 8),
                  Text('Total: ${money(widget.pledge.total)}', style: const TextStyle(color: FlowColors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          if (_method != null)
            ElevatedButton.icon(
              onPressed: () => setState(() => _confirmed = true),
              icon: const Icon(Icons.check),
              label: const Text('CONFIRM CLOSURE'),
              style: ElevatedButton.styleFrom(backgroundColor: FlowColors.green),
            ),
        ],
      ),
    );
  }

  Widget _methodButton(String value, String label) {
    final selected = _method == value;
    return OutlinedButton(
      onPressed: () => setState(() => _method = value),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? FlowColors.accent : Colors.white,
        side: BorderSide(color: selected ? FlowColors.primary : Colors.black26, width: 2),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(label),
    );
  }
}

class RenewalScreen extends StatefulWidget {
  const RenewalScreen({super.key, required this.pledge});

  final SamplePledge pledge;

  @override
  State<RenewalScreen> createState() => _RenewalScreenState();
}

class _RenewalScreenState extends State<RenewalScreen> {
  String? _type;
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final capitalised = widget.pledge.amount + widget.pledge.interest;
    if (_confirmed) {
      return _DoneScreen(
        title: 'Pledge Renewed',
        message: 'Old pledge ${widget.pledge.id} closed',
        detail: 'New pledge 3212 is open',
      );
    }

    return Scaffold(
      appBar: AppBar(backgroundColor: FlowColors.primary, foregroundColor: Colors.white, title: const Text('Renew Pledge')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FlowCard(
            backgroundColor: FlowColors.accent,
            child: Column(
              children: [
                DetailRow(label: 'Principal', value: money(widget.pledge.amount)),
                DetailRow(label: 'Interest Due', value: money(widget.pledge.interest)),
                DetailRow(label: 'Total Due', value: money(widget.pledge.total), isLast: true),
              ],
            ),
          ),
          const FlowSectionTitle('Renewal Type'),
          _renewalButton('pay', 'Pay Interest & Renew', 'New principal stays ${money(widget.pledge.amount)}'),
          _renewalButton('capitalise', 'Capitalise Interest', 'New principal becomes ${money(capitalised)}'),
          if (_type != null)
            FlowCard(
              child: Column(
                children: [
                  const DetailRow(label: 'New Pledge No.', value: '3212 (auto)'),
                  DetailRow(label: 'New Amount', value: _type == 'pay' ? money(widget.pledge.amount) : money(capitalised)),
                  const DetailRow(label: 'Interest Rate', value: '18% p.a.'),
                  const DetailRow(label: 'Gold Items', value: 'Carried forward', isLast: true),
                ],
              ),
            ),
          if (_type != null)
            FlowCard(
              backgroundColor: FlowColors.accent,
              child: Text('Renewal chain: ${[...widget.pledge.renewalChain, widget.pledge.id, '3212'].join(' -> ')}'),
            ),
          if (_type != null)
            ElevatedButton.icon(
              onPressed: () => setState(() => _confirmed = true),
              icon: const Icon(Icons.refresh),
              label: const Text('CONFIRM RENEWAL'),
            ),
        ],
      ),
    );
  }

  Widget _renewalButton(String value, String title, String subtitle) {
    final selected = _type == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton(
        onPressed: () => setState(() => _type = value),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: selected ? FlowColors.accent : Colors.white,
          side: BorderSide(color: selected ? FlowColors.primary : Colors.black26, width: 2),
          padding: const EdgeInsets.all(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class _DoneScreen extends StatelessWidget {
  const _DoneScreen({required this.title, required this.message, required this.detail});

  final String title;
  final String message;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: FlowColors.primary, foregroundColor: Colors.white, title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: FlowColors.green, size: 72),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 24, color: FlowColors.green, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
              Text(detail, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 28),
              ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('BACK')),
            ],
          ),
        ),
      ),
    );
  }
}
