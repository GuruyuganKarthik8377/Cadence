import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_value_view.dart';

/// One honest toggle: habit reminders. It persists to
/// profiles.reminders_enabled, which `reminderSyncProvider` watches — flipping
/// it schedules or clears every on-device reminder immediately. No decorative
/// toggles that control nothing.
class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool _saving = false;

  Future<void> _setReminders(bool value) async {
    setState(() => _saving = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase
          .from('profiles')
          .update({'reminders_enabled': value}).eq('id', userId);
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);

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
        title: Text(
          'Notifications',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: AsyncValueView(
        value: profileAsync,
        onRetry: () => ref.invalidate(currentProfileProvider),
        builder: (profile) {
          final enabled = profile?.remindersEnabled ?? true;
          return ListView(
            padding: const EdgeInsets.all(24),
            physics: const BouncingScrollPhysics(),
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.colors.border),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Habit Reminders',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'A notification at each habit\'s reminder time',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  value: enabled,
                  onChanged: _saving ? null : _setReminders,
                  activeThumbColor: context.colors.primaryAccent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Set a reminder time on each habit to get notified. '
                'Reminders also require notifications to be allowed in '
                'your device settings.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  height: 1.5,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
