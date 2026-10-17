import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/reaction_provider.dart';
import '../theme/app_theme.dart';
import 'friend_request_card.dart'; // for FriendAvatar

class ActivityFeedItem extends StatelessWidget {
  final String avatarUrl;
  final String friendName;
  final String habitName;
  final bool isStreak; // true = streak message, false = started message
  final int? streakDays;
  final String timeAgo;
  /// When set, the row grows a reaction strip. Null keeps the item read-only
  /// (used by previews and any feed without a backing completion).
  final String? completionId;

  const ActivityFeedItem({
    super.key,
    required this.avatarUrl,
    required this.friendName,
    required this.habitName,
    this.isStreak = false,
    this.streakDays,
    required this.timeAgo,
    this.completionId,
  });

  @override
  Widget build(BuildContext context) {
    final message = isStreak
        ? 'completed a ${streakDays ?? 0}-day streak on $habitName'
        : 'started $habitName';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FriendAvatar(url: avatarUrl, radius: 20, name: friendName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: context.colors.textPrimary,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: friendName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: ' $message'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeAgo,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
                if (completionId != null) ...[
                  const SizedBox(height: 8),
                  _ReactionStrip(completionId: completionId!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The reaction palette for one completion. Emoji the user has already left
/// are filled in; the rest stay ghosted until tapped.
class _ReactionStrip extends ConsumerWidget {
  final String completionId;

  const _ReactionStrip({required this.completionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(reactionsProvider).valueOrNull?[completionId] ??
        const ReactionSummary();

    return Wrap(
      spacing: 6,
      children: [
        for (final emoji in reactionEmojis)
          _ReactionChip(
            emoji: emoji,
            count: summary.countOf(emoji),
            selected: summary.didReact(emoji),
            onTap: () async {
              HapticFeedback.selectionClick();
              try {
                await ref
                    .read(reactionsProvider.notifier)
                    .toggle(completionId, emoji);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Couldn't save that reaction.")),
                  );
                }
              }
            },
          ),
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final String emoji;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.primaryAccent.withValues(alpha: 0.14)
              : context.colors.secondarySurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? context.colors.primaryAccent
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? context.colors.primaryAccent
                      : context.colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feed entries now come from activityFeedProvider
// (see lib/providers/activity_feed_provider.dart).
// ---------------------------------------------------------------------------
