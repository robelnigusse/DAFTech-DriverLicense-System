import 'package:flutter/material.dart';

/// Small colour-coded pill used for licence and verification statuses.
class StatusChip extends StatelessWidget {
  final String label;

  const StatusChip(this.label, {super.key});

  Color _color() {
    switch (label.toLowerCase()) {
      case 'active':
      case 'real':
        return const Color(0xFF1B7F4B);
      case 'expired':
        return const Color(0xFFB26A00);
      case 'fake':
        return const Color(0xFFB3261E);
      case 'needsreview':
        return const Color(0xFF3A5FCD);
      default:
        return const Color(0xFF5F6368);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
