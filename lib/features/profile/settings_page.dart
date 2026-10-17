import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/habit_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/export_service.dart';
import '../../services/reminder_service.dart';
import '../../theme/app_theme.dart';
import '../habit_detail/archived_habits_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;

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
        title: Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        physics: const BouncingScrollPhysics(),
        children: [
          _buildSettingsRow(
            context,
            icon: LucideIcons.palette,
            label: 'Theme',
            value: _themeLabel(themeMode),
            onTap: () => _showThemeSheet(context, ref),
          ),
          _buildSettingsRow(
            context,
            icon: LucideIcons.moon,
            label: 'Quiet Hours',
            value: _quietLabel(context, profile),
            onTap: () => _showQuietHoursSheet(context, ref, profile),
          ),
          _buildSettingsRow(
            context,
            icon: LucideIcons.clock,
            label: 'Default Reminder Time',
            value: profile?.defaultReminderTime == null
                ? 'Off'
                : profile!.defaultReminderTime!.format(context),
            onTap: () => _pickDefaultReminder(context, ref, profile),
          ),
          _buildSettingsRow(
            context,
            icon: LucideIcons.bell,
            label: 'Sound & Vibration',
            value: 'System',
            onTap: () => _openSystemNotificationSettings(context),
          ),
          const SizedBox(height: 24),
          _buildSettingsRow(
            context,
            icon: LucideIcons.archive,
            label: 'Archived Habits',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ArchivedHabitsPage()),
            ),
          ),
          _buildSettingsRow(
            context,
            icon: LucideIcons.download,
            label: 'Export Data',
            value: 'CSV',
            onTap: () => _exportData(context, ref),
          ),
          const SizedBox(height: 24),
          _buildSettingsRow(
            context,
            icon: LucideIcons.info,
            label: 'About Cadence',
            onTap: () => _showAbout(context),
          ),
          _buildSettingsRow(
            context,
            icon: LucideIcons.star,
            label: 'Rate App',
            onTap: () => _requestReview(context),
          ),
          const SizedBox(height: 48),
          Center(
            child: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) => Text(
                snapshot.hasData
                    ? 'Cadence v${snapshot.data!.version}'
                    : 'Cadence',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  void _showThemeSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final current = ref.read(themeModeProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                for (final mode in ThemeMode.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _themeLabel(mode),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    trailing: mode == current
                        ? Icon(LucideIcons.check,
                            size: 18, color: context.colors.primaryAccent)
                        : null,
                    onTap: () {
                      ref.read(themeModeProvider.notifier).set(mode);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAbout(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'Cadence',
      applicationVersion: 'v${info.version} (${info.buildNumber})',
      applicationLegalese: 'Build habits, keep streaks, and stay '
          'accountable with friends.',
    );
  }

  Future<void> _requestReview(BuildContext context) async {
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('In-app review is available once the app is '
              'installed from the Play Store.'),
        ),
      );
    }
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    // Archived habits carry history too — exporting without them would hand
    // the user an incomplete record.
    final active = ref.read(habitsProvider).valueOrNull ?? const [];
    final archived = await ref.read(archivedHabitsProvider.future);

    try {
      final shared = await ExportService.share([...active, ...archived]);
      if (!shared) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nothing to export yet.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't create the export.")),
      );
    }
  }

  static String _quietLabel(BuildContext context, Profile? profile) {
    if (profile == null || !profile.hasQuietHours) return 'Off';
    return '${profile.quietHoursStart!.format(context)}'
        ' – ${profile.quietHoursEnd!.format(context)}';
  }

  /// Quiet hours silence follow-up nags only — never a habit's own reminder
  /// time, which the user chose on purpose.
  Future<void> _showQuietHoursSheet(
      BuildContext context, WidgetRef ref, Profile? profile) async {
    if (profile == null) return;
    final editor = ref.read(profileEditorProvider);

    if (profile.hasQuietHours) {
      final turnOff = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: context.colors.primarySurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(LucideIcons.clock,
                    color: sheetContext.colors.textPrimary),
                title: Text('Change window',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        color: sheetContext.colors.textPrimary)),
                onTap: () => Navigator.pop(sheetContext, false),
              ),
              ListTile(
                leading: Icon(LucideIcons.bellOff,
                    color: sheetContext.colors.textPrimary),
                title: Text('Turn off quiet hours',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        color: sheetContext.colors.textPrimary)),
                onTap: () => Navigator.pop(sheetContext, true),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
      if (turnOff == null) return;
      if (turnOff) {
        await editor.setQuietHours(null, null);
        return;
      }
    }

    if (!context.mounted) return;
    final start = await showTimePicker(
      context: context,
      initialTime:
          profile.quietHoursStart ?? const TimeOfDay(hour: 22, minute: 0),
      helpText: 'Quiet hours start',
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime:
          profile.quietHoursEnd ?? const TimeOfDay(hour: 7, minute: 0),
      helpText: 'Quiet hours end',
    );
    if (end == null) return;
    await editor.setQuietHours(start, end);
  }

  Future<void> _pickDefaultReminder(
      BuildContext context, WidgetRef ref, Profile? profile) async {
    if (profile == null) return;
    final editor = ref.read(profileEditorProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime:
          profile.defaultReminderTime ?? const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Default reminder for new habits',
    );
    if (picked == null) return;
    await editor.setDefaultReminderTime(picked);
  }

  Future<void> _openSystemNotificationSettings(BuildContext context) async {
    final opened = await SystemNotificationSettings.open();
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Couldn't open system notification settings."),
      ),
    );
  }

  Widget _buildSettingsRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? value,
    required VoidCallback onTap,
  }) {
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
            Icon(icon, size: 20, color: context.colors.textPrimary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            if (value != null)
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: context.colors.textSecondary,
                ),
              ),
            if (value != null) const SizedBox(width: 8),
            Icon(LucideIcons.chevronRight,
                size: 16, color: context.colors.textSecondary),
          ],
        ),
      ),
    );
  }
}
