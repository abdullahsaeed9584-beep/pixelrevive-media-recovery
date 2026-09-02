import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

class ConfidenceBadge extends StatelessWidget {
  final int confidence;

  const ConfidenceBadge({super.key, required this.confidence});

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    Color textColor;

    if (confidence >= 80) {
      badgeColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.15);
      textColor = Theme.of(context).colorScheme.primary;
    } else if (confidence >= 40) {
      badgeColor = AppColors.accentOrange.withValues(alpha: 0.15);
      textColor = AppColors.accentOrange;
    } else {
      badgeColor = Theme.of(context).colorScheme.error.withValues(alpha: 0.15);
      textColor = Theme.of(context).colorScheme.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 10, color: textColor),
          SizedBox(width: 4),
          Text(
            '$confidence%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
