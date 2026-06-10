class SamplePledge {
  const SamplePledge({
    required this.id,
    required this.date,
    required this.amount,
    required this.rate,
    required this.status,
    required this.gold,
    required this.days,
    required this.interest,
    required this.total,
    this.renewalChain = const [],
    this.closedDate,
    this.interestPaid,
    this.totalCollected,
  });

  final String id;
  final String date;
  final double amount;
  final double rate;
  final String status;
  final String gold;
  final int days;
  final double interest;
  final double total;
  final List<String> renewalChain;
  final String? closedDate;
  final double? interestPaid;
  final double? totalCollected;
}

const samplePledges = <SamplePledge>[
  SamplePledge(
    id: '3201',
    date: '01/04/2026',
    amount: 25000,
    rate: 18,
    status: 'open',
    gold: 'Gold Necklace 20g 22K',
    days: 70,
    interest: 875,
    total: 25875,
  ),
  SamplePledge(
    id: '3195',
    date: '10/01/2026',
    amount: 15000,
    rate: 18,
    status: 'open',
    gold: 'Gold Bangles 12g 22K',
    days: 151,
    interest: 1131.25,
    total: 16131.25,
  ),
  SamplePledge(
    id: '3180',
    date: '05/06/2024',
    amount: 50000,
    rate: 18,
    status: 'open',
    gold: 'Gold Chain 35g 22K',
    days: 735,
    interest: 18375,
    total: 68375,
    renewalChain: ['3165', '3150'],
  ),
  SamplePledge(
    id: '3199',
    date: '15/03/2026',
    amount: 8000,
    rate: 18,
    status: 'closed',
    gold: 'Gold Ring 5g 22K',
    days: 86,
    interest: 731.67,
    total: 8731.67,
    closedDate: '09/06/2026',
    interestPaid: 731.67,
    totalCollected: 8731.67,
  ),
];
