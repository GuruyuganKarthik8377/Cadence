import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/friend.dart';
import '../theme/app_theme.dart';
import 'friend_request_card.dart'; // for FriendAvatar

/// A full-width list tile representing a connected friend.
class FriendCard extends StatelessWidget {
  final Friend friend;
  final VoidCallback onTap;

  const FriendCard({
    super.key,
    required this.friend,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final habitsLabel = friend.habitsLinked == 0
        ? 'No habits linked yet'
        : '${friend.habitsLinked} habit${friend.habitsLinked == 1 ? '' : 's'} linked';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            FriendAvatar(url: friend.avatarUrl, radius: 26, name: friend.name),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.name,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    habitsLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: friend.habitsLinked == 0
                              ? context.colors.textSecondary
                              : context.colors.textSecondary,
                          fontSize: 13,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: context.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
