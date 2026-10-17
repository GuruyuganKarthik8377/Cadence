import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/habit.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/habit_provider.dart';
import '../../theme/app_theme.dart';
import '../add_habit/add_habit_page.dart' show habitTemplates, HabitTemplate;

/// First-run flow shown once, right after sign-up, while the account has no
/// habits yet — pick starter habits, set a reminder time, optionally add a
/// friend. Each step can be skipped; nothing here is required to reach
/// HomePage. Gated purely on habits being empty (see AuthGate) rather than a
/// persisted "seen onboarding" flag — adding a habit is itself proof the
/// flow doesn't need to show again, so there's no separate state to track
/// or fall out of sync.
class OnboardingPage extends ConsumerStatefulWidget {
  final VoidCallback onDone;
  const OnboardingPage({super.key, required this.onDone});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pageController = PageController();
  int _page = 0;
  final Set<HabitTemplate> _selectedTemplates = {};
  TimeOfDay _reminderTime = const TimeOfDay(hour: 8, minute: 0);
  bool _reminderOn = true;
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 2) {
      _finish();
      return;
    }
    _pageController.nextPage(
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final notifier = ref.read(habitsProvider.notifier);
      for (final t in _selectedTemplates) {
        await notifier.addHabit(Habit(
          id: '',
          name: t.name,
          iconOrEmoji: t.icon,
          category: t.category,
          habitType: HabitType.build,
          frequency: FrequencyType.daily,
          durationValue: t.value,
          durationUnit: t.unit,
          reminderEnabled: _reminderOn,
          reminderTime: _reminderOn ? _reminderTime : null,
        ));
      }
      if (_reminderOn) {
        await ref
            .read(profileEditorProvider)
            .setDefaultReminderTime(_reminderTime);
      }
    } catch (_) {
      // Best-effort — a partial save still lands the user on a working
      // HomePage rather than stuck on a spinner.
    } finally {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressDots(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _TemplateStep(
                    selected: _selectedTemplates,
                    onToggle: (t) => setState(() {
                      _selectedTemplates.contains(t)
                          ? _selectedTemplates.remove(t)
                          : _selectedTemplates.add(t);
                    }),
                  ),
                  _ReminderStep(
                    enabled: _reminderOn,
                    time: _reminderTime,
                    onToggle: (v) => setState(() => _reminderOn = v),
                    onTimeChanged: (t) => setState(() => _reminderTime = t),
                  ),
                  const _InviteStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _saving ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primaryAccent,
                    foregroundColor: context.colors.onAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: context.colors.onAccent),
                        )
                      : Text(
                          _page == 2 ? 'Get Started' : 'Continue',
                          style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
            if (_page < 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                  onTap: _saving ? null : _finish,
                  child: Text(
                    'Skip for now',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: context.colors.textSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressDots() {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final active = i == _page;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: active ? 22 : 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? context.colors.primaryAccent
                  : context.colors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — pick starter habits
// ---------------------------------------------------------------------------

class _TemplateStep extends StatelessWidget {
  final Set<HabitTemplate> selected;
  final ValueChanged<HabitTemplate> onToggle;

  const _TemplateStep({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome to Cadence',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Pick a few habits to start with. You can always add more later.',
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: context.colors.textSecondary,
                height: 1.4),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: habitTemplates.map((t) {
              final isSelected = selected.contains(t);
              return GestureDetector(
                onTap: () => onToggle(t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? context.colors.primaryAccent
                        : context.colors.primarySurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? context.colors.primaryAccent
                          : context.colors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(habitIconData(t.icon),
                          size: 16,
                          color: isSelected
                              ? context.colors.onAccent
                              : context.colors.textPrimary),
                      const SizedBox(width: 8),
                      Text(
                        t.name,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? context.colors.onAccent
                              : context.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — reminder time
// ---------------------------------------------------------------------------

class _ReminderStep extends StatelessWidget {
  final bool enabled;
  final TimeOfDay time;
  final ValueChanged<bool> onToggle;
  final ValueChanged<TimeOfDay> onTimeChanged;

  const _ReminderStep({
    required this.enabled,
    required this.time,
    required this.onToggle,
    required this.onTimeChanged,
  });

  String _format(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stay on track',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'A daily nudge at the same time works better than relying on memory.',
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: context.colors.textSecondary,
                height: 1.4),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.colors.primarySurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.colors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.bell,
                        size: 18, color: context.colors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Daily reminder',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textPrimary)),
                    ),
                    Switch(
                      value: enabled,
                      onChanged: onToggle,
                      activeThumbColor: Colors.white,
                      activeTrackColor: context.colors.primaryAccent,
                    ),
                  ],
                ),
                if (enabled) ...[
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showTimePicker(
                          context: context, initialTime: time);
                      if (picked != null) onTimeChanged(picked);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: context.colors.secondarySurface,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _format(time),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — invite a friend (optional)
// ---------------------------------------------------------------------------

class _InviteStep extends ConsumerStatefulWidget {
  const _InviteStep();

  @override
  ConsumerState<_InviteStep> createState() => _InviteStepState();
}

class _InviteStepState extends ConsumerState<_InviteStep> {
  final _controller = TextEditingController();
  List<Profile> _results = [];
  bool _searching = false;
  final Set<String> _sentTo = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results =
          await ref.read(friendsProvider.notifier).searchUsers(query);
      if (mounted) setState(() => _results = results);
    } catch (_) {
      // Leave the last results in place on failure.
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _send(Profile p) async {
    try {
      await ref.read(friendsProvider.notifier).sendRequest(p.id);
      if (mounted) setState(() => _sentTo.add(p.id));
    } catch (_) {
      // Silent — an optional onboarding step shouldn't block on this.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Better with friends',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Link a habit with a friend and you\'ll both stay honest. Totally optional.',
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: context.colors.textSecondary,
                height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            onChanged: _search,
            style:
                TextStyle(fontFamily: 'Inter', color: context.colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by username',
              prefixIcon: Icon(LucideIcons.search,
                  size: 18, color: context.colors.textSecondary),
              filled: true,
              fillColor: context.colors.primarySurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.colors.border),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ..._results.map((p) {
              final sent = _sentTo.contains(p.id);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.colors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.displayName,
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textPrimary)),
                          Text('@${p.username}',
                              style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: context.colors.textSecondary)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: sent ? null : () => _send(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sent
                              ? context.colors.secondarySurface
                              : context.colors.primaryAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          sent ? 'Sent' : 'Add',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: sent
                                ? context.colors.textSecondary
                                : context.colors.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
