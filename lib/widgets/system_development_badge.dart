import 'package:flutter/material.dart';

/// A compact status row that can wrap on narrow system cards.
class SystemDevelopmentBadge extends StatelessWidget {
  final String label;

  const SystemDevelopmentBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.lock_clock_rounded, size: 14, color: Colors.orange.shade800),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.orange.shade800,
            ),
          ),
        ),
      ],
    );
  }
}
