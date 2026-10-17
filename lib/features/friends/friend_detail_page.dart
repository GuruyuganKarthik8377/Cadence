import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/friend.dart';
import '../../models/habit_link.dart';
import '../../providers/friend_provider.dart';
import '../../providers/habit_link_provider.dart';
import '../../providers/nudge_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_value_view.dart';
import '../../widgets/friend_request_card.dart';
import '../../widgets/linked_habit_row.dart';
import 'link_habit_sheet.dart';

class FriendDetailPage extends ConsumerStatefulWidget {
  final Friend friend;

  const FriendDetailPage({super.key, required this.friend});

  @override
  ConsumerState<FriendDetailPage> createState() => _FriendDetailPageState();
}

class _FriendDetailPageState extends ConsumerState<FriendDetailPage> {
  List<HabitLink> get _links {
    final links = ref.watch(habitLinksProvider).valueOrNull ?? const [];
    return links.where((l) => l.friendId == widget.friend.id).toList();
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider).valueOrNull?.friends ?? const [];
    final friend = friends.where((f) => f.id == widget.friend.id).firstOrNull ?? widget.friend;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.chevronLeft,
              color: context.colors.primaryAccent),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(LucideIcons.moreHorizontal,
                color: context.colors.primaryAccent, size: 22),
            onPressed: () => _showFriendMenu(friend),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: 40 + bottomPadding),
        child: Column(
          children: [
            // Hero header
            _buildHeader(friend),
            const SizedBox(height: 24),

            // Stats row
            _buildStats(friend),
            const SizedBox(height: 36),

            // Linked Habits
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section title + count
                  Row(
                    children: [
                      Text(
                        'Linked Habits',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.colors.secondarySurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_links.length}',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'When ${friend.name.split(' ').first} acts, you\'re gently nudged.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),

                  if (ref.watch(habitLinksProvider).hasError)
                    AsyncErrorCard(
                        onRetry: () => ref.invalidate(habitLinksProvider))
                  else if (_links.isEmpty)
                    _buildNoLinksState(friend.name.split(' ').first)
                  else
                    ...List.generate(_links.length, (i) {
                      final link = _links[i];
                      return LinkedHabitRow(
                        link: link,
                        friendName: friend.name.split(' ').first,
                        onToggle: (val) => ref.read(habitLinksProvider.notifier).toggleActive(link.id, val),
                        onNudge: () => ref
                            .read(incomingNudgesProvider.notifier)
                            .send(
                              toUserId: friend.id,
                              habitId: link.friendHabitId,
                            ),
                      );
                    }),

                  const SizedBox(height: 20),

                  // Link a new habit button
                  _buildLinkButton(friend),

                  const SizedBox(height: 48),

                  // Remove friend
                  Center(
                    child: GestureDetector(
                      onTap: () => _showRemoveDialog(context, friend),
                      child: Text(
                        'Remove Friend',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: context.colors.textSecondary,
                                  decoration: TextDecoration.underline,
                                  decorationColor: context.colors.textSecondary,
                                ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFriendMenu(Friend friend) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.userMinus,
                    size: 20, color: Colors.red),
                title: const Text(
                  'Remove Friend',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmRemoveFriend(friend);
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.ban,
                    size: 20, color: context.colors.textSecondary),
                title: Text(
                  'Block User',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmBlockUser(friend);
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.flag,
                    size: 20, color: context.colors.textSecondary),
                title: Text(
                  'Report',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showReportDialog(friend);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmBlockUser(Friend friend) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Block ${friend.name.split(' ').first}?',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          'They won\'t be able to find you, send friend requests, or nudge you. '
          'This also removes the friendship.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            height: 1.5,
            color: context.colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: context.colors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(friendsProvider.notifier)
                    .blockUser(friend.id);
                if (mounted) Navigator.pop(context);
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Couldn't block user. Try again.")),
                  );
                }
              }
            },
            child: const Text('Block',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(Friend friend) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Report ${friend.name.split(' ').first}',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tell us what\'s happening (optional). Reports are reviewed privately.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                height: 1.5,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Describe the issue…',
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  color: context.colors.textSecondary,
                ),
                filled: true,
                fillColor: context.colors.secondarySurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.dispose();
              Navigator.pop(ctx);
            },
            child: Text('Cancel',
                style: TextStyle(color: context.colors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final reason = controller.text;
              controller.dispose();
              Navigator.pop(ctx);
              try {
                await ref
                    .read(friendsProvider.notifier)
                    .reportUser(friend.id, reason: reason);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Report submitted. Thank you.')),
                  );
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text("Couldn't submit report. Try again.")),
                  );
                }
              }
            },
            child: Text('Submit',
                style: TextStyle(
                    color: context.colors.primaryAccent,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveFriend(Friend friend) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.background,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Remove friend?',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          'You and ${friend.name} will no longer see each other\'s '
          'activity, and your linked habits will be unlinked.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            height: 1.5,
            color: context.colors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: context.colors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(friendsProvider.notifier)
                    .removeFriend(friend.friendshipId);
                if (mounted) Navigator.pop(context);
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Couldn't remove friend. Try again.")),
                  );
                }
              }
            },
            child: const Text('Remove',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Friend friend) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          FriendAvatar(url: friend.avatarUrl, radius: 44, name: friend.name),
          const SizedBox(height: 14),
          Text(
            friend.name,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            friend.username,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildStats(Friend friend) {
    final statsItems = [
      _StatItem(
        value: '${friend.currentStreak}',
        label: 'Day Streak',
        icon: LucideIcons.flame,
      ),
      _StatItem(
        value: '${friend.habitsLinked}',
        label: 'Habits Linked',
        icon: LucideIcons.link2,
      ),
      _StatItem(
        value: '${friend.daysConnected}',
        label: 'Days Together',
        icon: LucideIcons.calendarDays,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
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
          children: statsItems
              .map((s) => Expanded(
                    child: _buildStatCell(s),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildStatCell(_StatItem item) {
    return Column(
      children: [
        Icon(item.icon, size: 18, color: context.colors.textSecondary),
        const SizedBox(height: 6),
        Text(
          item.value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            color: context.colors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildNoLinksState(String firstName) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: context.colors.secondarySurface,
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.link2,
                size: 26, color: context.colors.textSecondary),
          ),
          const SizedBox(height: 14),
          Text(
            'No habits linked with $firstName yet.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLinkButton(Friend friend) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => LinkHabitSheet(friend: friend),
        ).then((_) => setState(() {}));
      },
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: context.colors.secondarySurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.plus,
                size: 18, color: context.colors.textPrimary),
            const SizedBox(width: 8),
            Text(
              'Link a New Habit',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveDialog(BuildContext context, Friend friend) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.primarySurface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Remove ${friend.name.split(' ').first}?',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          'All linked habits will be deactivated. This cannot be undone.',
          style: TextStyle(
            fontFamily: 'Inter',
            color: context.colors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Inter',
                color: context.colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(friendsProvider.notifier).removeFriend(friend.friendshipId);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              'Remove',
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem {
  final String value;
  final String label;
  final IconData icon;

  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
  });
}
