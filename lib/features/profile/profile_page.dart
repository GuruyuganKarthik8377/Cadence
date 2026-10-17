import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../models/habit.dart';
import '../../models/profile.dart';
import '../../providers/achievement_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/habit_provider.dart';
import '../../services/achievement_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/async_value_view.dart';
import 'notifications_page.dart';
import 'privacy_page.dart';
import 'settings_page.dart';

class ProfilePage extends ConsumerWidget {
  final VoidCallback onSwitchToHabits;
  final VoidCallback onSwitchToFriends;

  const ProfilePage({
    super.key,
    required this.onSwitchToHabits,
    required this.onSwitchToFriends,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final profileAsync = ref.watch(currentProfileProvider);
    final habitsAsync = ref.watch(habitsProvider);
    final habits = habitsAsync.valueOrNull ?? const <Habit>[];
    final friendsState = ref.watch(friendsProvider).valueOrNull;
    final friendCount = friendsState?.friends.length ?? 0;
    final hasLoadError = profileAsync.hasError || habitsAsync.hasError;
    final dayStreak = habits.fold<int>(0, (max, h) => h.currentStreak > max ? h.currentStreak : max);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.chevronLeft, color: context.colors.primaryAccent),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(bottom: 120 + bottomPadding),
        child: Column(
          children: [
            if (hasLoadError)
              AsyncErrorCard(onRetry: () {
                ref.invalidate(currentProfileProvider);
                ref.invalidate(habitsProvider);
                ref.invalidate(friendsProvider);
              }),
            const SizedBox(height: 10),
            // Avatar + name (tap the avatar to change it)
            _EditableAvatar(
              name: profileAsync.valueOrNull?.displayName ?? '',
              imageUrl: profileAsync.valueOrNull?.avatarUrl,
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: profileAsync.valueOrNull == null
                  ? null
                  : () => _editIdentity(context, ref, profileAsync.value!),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      profileAsync.valueOrNull?.displayName ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (profileAsync.valueOrNull != null) ...[
                    const SizedBox(width: 6),
                    Icon(LucideIcons.pencil,
                        size: 15, color: context.colors.textSecondary),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              profileAsync.valueOrNull != null ? '@${profileAsync.valueOrNull!.username}' : '',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (profileAsync.valueOrNull != null) ...[
              const SizedBox(height: 10),
              _BioLine(profile: profileAsync.valueOrNull!),
            ],
            const SizedBox(height: 32),

            // Stats row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
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
                    _StatCell(value: '$dayStreak', label: 'Day Streak'),
                    _Divider(),
                    _StatCell(value: '${habits.length}', label: 'Habits'),
                    _Divider(),
                    _StatCell(value: '$friendCount', label: 'Friends'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _LifetimeStatsCard(habits: habits),
            const SizedBox(height: 20),
            const _AchievementsCard(),
            const SizedBox(height: 28),

            // Settings list
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  // My Habits (full list)
                  _SettingsRow(
                    icon: LucideIcons.list,
                    label: 'My Habits',
                    subtitle: 'All your active habits',
                    onTap: () {
                      Navigator.pop(context);
                      onSwitchToHabits();
                    },
                  ),
                  const SizedBox(height: 4),
                  // Friends entry point
                  _SettingsRow(
                    icon: LucideIcons.users,
                    label: 'Friends',
                    subtitle: '$friendCount connection${friendCount == 1 ? '' : 's'}',
                    onTap: () {
                      Navigator.pop(context);
                      onSwitchToFriends();
                    },
                  ),
                  _SettingsRow(
                    icon: LucideIcons.bell,
                    label: 'Notifications',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsPage()),
                    ),
                  ),
                  _SettingsRow(
                    icon: LucideIcons.shieldCheck,
                    label: 'Privacy',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PrivacyPage()),
                    ),
                  ),
                  _SettingsRow(
                    icon: LucideIcons.settings,
                    label: 'Settings',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsRow(
                    icon: LucideIcons.logOut,
                    label: 'Log Out',
                    isDestructive: true,
                    onTap: () => _showLogOutDialog(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.primarySurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Log Out',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to log out of your account?',
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
              Navigator.pop(context);
              // AuthGate watches the session stream and swaps to SignInPage
              // automatically once this completes — no manual nav needed.
              await supabase.auth.signOut();
            },
            child: const Text(
              'Log Out',
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

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: context.colors.border,
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool isDestructive;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.red : context.colors.textPrimary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: context.colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (!isDestructive)
              Icon(LucideIcons.chevronRight,
                  size: 16, color: context.colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Profile avatar that doubles as an upload button. Tapping it picks an
/// image, uploads it to the `user-content` bucket, and points the profile at
/// the new URL.
class _EditableAvatar extends ConsumerStatefulWidget {
  final String name;
  final String? imageUrl;

  const _EditableAvatar({required this.name, this.imageUrl});

  @override
  ConsumerState<_EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends ConsumerState<_EditableAvatar> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _uploading = true);
      final bytes = await picked.readAsBytes();
      final userId = supabase.auth.currentUser!.id;
      // Fixed path per user (matches the storage policy, which requires the
      // file name to start with the uploader's id).
      final path = 'avatars/$userId.jpg';
      await supabase.storage.from('user-content').uploadBinary(
            path,
            bytes,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
      // The path never changes, so bust the image cache with a version param.
      final url = '${supabase.storage.from('user-content').getPublicUrl(path)}'
          '?v=${DateTime.now().millisecondsSinceEpoch}';
      await supabase
          .from('profiles')
          .update({'avatar_url': url}).eq('id', userId);
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't update photo. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _uploading ? null : _pickAndUpload,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AppAvatar(
            radius: 46,
            name: widget.name,
            imageUrl: widget.imageUrl,
          ),
          if (_uploading)
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.colors.primaryAccent,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.colors.background, width: 2),
                ),
                child: Icon(LucideIcons.camera,
                    size: 13, color: context.colors.onAccent),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Identity editing ──────────────────────────────────────────────────────

/// Edits display name, username and bio in one sheet.
///
/// Username goes through the set_username RPC, which is the only thing that
/// can tell "taken" apart from any other failure, so its error is surfaced
/// verbatim rather than flattened into a generic message.
Future<void> _editIdentity(
    BuildContext context, WidgetRef ref, Profile profile) async {
  final messenger = ScaffoldMessenger.of(context);
  final nameController = TextEditingController(text: profile.displayName);
  final usernameController = TextEditingController(text: profile.username);
  final bioController = TextEditingController(text: profile.bio ?? '');

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.primarySurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit profile',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: sheetContext.colors.textPrimary,
              )),
          const SizedBox(height: 18),
          _SheetField(controller: nameController, label: 'Display name', maxLength: 40),
          const SizedBox(height: 14),
          _SheetField(
            controller: usernameController,
            label: 'Username',
            prefix: '@',
            maxLength: 20,
            helper: 'Letters, numbers, dot or underscore',
          ),
          const SizedBox(height: 14),
          _SheetField(
            controller: bioController,
            label: 'Bio',
            maxLength: Profile.maxBioLength,
            maxLines: 3,
            helper: 'Visible to your friends',
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(sheetContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: sheetContext.colors.primaryAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    ),
  );

  if (saved != true) return;
  final editor = ref.read(profileEditorProvider);

  try {
    if (nameController.text.trim() != profile.displayName) {
      await editor.setDisplayName(nameController.text);
    }
    if ((bioController.text.trim()) != (profile.bio ?? '')) {
      await editor.setBio(bioController.text);
    }
    // Last, so a rejected username doesn't discard the other two edits.
    final wantedUsername =
        usernameController.text.trim().replaceFirst(RegExp(r'^@'), '');
    if (wantedUsername != profile.username) {
      await editor.setUsername(wantedUsername);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.toString().replaceFirst('Exception: ', '')),
    ));
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? prefix;
  final String? helper;
  final int maxLength;
  final int maxLines;

  const _SheetField({
    required this.controller,
    required this.label,
    this.prefix,
    this.helper,
    required this.maxLength,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      style: TextStyle(
          fontFamily: 'Inter', fontSize: 15, color: context.colors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        helperText: helper,
        filled: true,
        fillColor: context.colors.secondarySurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _BioLine extends StatelessWidget {
  final Profile profile;
  const _BioLine({required this.profile});

  @override
  Widget build(BuildContext context) {
    final bio = profile.bio;
    if (bio == null || bio.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Text(
        bio,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          height: 1.5,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

// ─── Lifetime stats ────────────────────────────────────────────────────────

class _LifetimeStatsCard extends StatelessWidget {
  final List<Habit> habits;
  const _LifetimeStatsCard({required this.habits});

  @override
  Widget build(BuildContext context) {
    final stats = LifetimeStats.from(habits);
    if (stats.totalCompletions == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('All time',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textSecondary,
                )),
            const SizedBox(height: 16),
            Row(
              children: [
                _StatCell(
                    value: '${stats.totalCompletions}', label: 'Completions'),
                _Divider(),
                _StatCell(
                    value: '${stats.bestStreakEver}', label: 'Best Streak'),
                _Divider(),
                _StatCell(value: '${stats.perfectDays}', label: 'Perfect Days'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Achievements ──────────────────────────────────────────────────────────

class _AchievementsCard extends ConsumerWidget {
  const _AchievementsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(achievementsProvider);
    final earned = async.valueOrNull;
    if (earned == null || earned.isEmpty) return const SizedBox.shrink();

    final unlockedCount = earned.where((e) => e.isUnlocked).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Achievements',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textSecondary,
                    )),
                Text('$unlockedCount of ${earned.length}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    )),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 12,
              children: [
                for (final e in earned) _AchievementChip(earned: e),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementChip extends StatelessWidget {
  final EarnedAchievement earned;
  const _AchievementChip({required this.earned});

  @override
  Widget build(BuildContext context) {
    final unlocked = earned.isUnlocked;
    return Tooltip(
      message: unlocked
          ? '${earned.achievement.title} — ${earned.achievement.description}'
          : 'Locked: ${earned.achievement.description}',
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: unlocked
              ? context.colors.primaryAccent.withValues(alpha: 0.12)
              : context.colors.secondarySurface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              habitIconData(earned.achievement.iconKey),
              size: 20,
              color: unlocked
                  ? context.colors.primaryAccent
                  : context.colors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            Text(
              earned.achievement.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 9,
                height: 1.2,
                fontWeight: FontWeight.w500,
                color: unlocked
                    ? context.colors.textPrimary
                    : context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
