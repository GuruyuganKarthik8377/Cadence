import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/habit.dart';
import '../theme/app_theme.dart';

/// Compact horizontal streak card shown in the Insights streak scroller.
/// Tapping it navigates to the habit's detail screen.
class StreakCard extends StatelessWidget {
  final Habit habit;
  final int streak;
  final VoidCallback? onTap;

  const StreakCard({
    super.key,
    required this.habit,
    required this.streak,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Lucide icon (replaces emoji for consistent cross-device rendering)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.secondarySurface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  habitIconData(habit.iconOrEmoji),
                  size: 20,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Habit name
            Text(
              habit.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            // Streak badge
            Row(
              children: [
                Icon(LucideIcons.flame,
                    size: 11, color: context.colors.textSecondary),
                const SizedBox(width: 3),
                Text(
                  '$streak ${streak == 1 ? 'day' : 'days'}',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
