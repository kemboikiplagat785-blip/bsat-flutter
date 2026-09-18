import 'package:bsat/utils/constants.dart';
import 'package:flutter/material.dart';

class QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Function() onTap;
  final BuildContext context;

  const QuickAction(
      {super.key,
      required this.icon,
      required this.label,
      required this.color,
      required this.onTap,
      required this.context});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: kPagePaddingInsets,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(kBorderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.9),
              blurRadius: 0,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                // color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
