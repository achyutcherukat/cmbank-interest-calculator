import 'package:flutter/material.dart';

class FlowColors {
  const FlowColors._();

  static const primary = Color(0xFF1A237E);
  static const primaryLight = Color(0xFF3949AB);
  static const accent = Color(0xFFE8EAF6);
  static const bg = Color(0xFFF5F5F5);
  static const gold = Color(0xFFF9A825);
  static const goldLight = Color(0xFFFFF8E1);
  static const green = Color(0xFF2E7D32);
  static const greenLight = Color(0xFFE8F5E9);
  static const orange = Color(0xFFE65100);
  static const orangeLight = Color(0xFFFFF3E0);
  static const red = Color(0xFFC62828);
  static const redLight = Color(0xFFFFEBEE);
  static const darkText = Color(0xFF212121);
  static const medText = Color(0xFF555555);
}

class FlowCard extends StatelessWidget {
  const FlowCard({
    super.key,
    required this.child,
    this.backgroundColor = Colors.white,
    this.borderColor = FlowColors.primaryLight,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class FlowCardTitle extends StatelessWidget {
  const FlowCardTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black45,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class FlowSectionTitle extends StatelessWidget {
  const FlowSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: FlowColors.primary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class FlowNoticeBox extends StatelessWidget {
  const FlowNoticeBox({
    super.key,
    required this.text,
    this.color = FlowColors.primaryLight,
    this.backgroundColor = FlowColors.accent,
    this.icon = Icons.info_outline,
  });

  final String text;
  final Color color;
  final Color backgroundColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.isLast = false,
    this.valueColor = FlowColors.primary,
  });

  final String label;
  final String value;
  final bool isLast;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 17, color: FlowColors.medText),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
    required this.backgroundColor,
  });

  final String text;
  final Color color;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

String money(num value) {
  final isNegative = value < 0;
  final abs = value.abs();
  final parts = abs.toStringAsFixed(2).split('.');
  final whole = parts[0];
  final decimal = parts[1];

  String intStr;
  if (whole.length <= 3) {
    intStr = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    final rest = whole.substring(0, whole.length - 3);
    final buf = StringBuffer();
    final start = rest.length % 2;
    if (start > 0) buf.write(rest.substring(0, start));
    for (var i = start; i < rest.length; i += 2) {
      if (buf.isNotEmpty) buf.write(',');
      buf.write(rest.substring(i, i + 2));
    }
    intStr = '${buf.toString()},$last3';
  }

  return '${isNegative ? '-' : ''}₹$intStr.$decimal';
}
