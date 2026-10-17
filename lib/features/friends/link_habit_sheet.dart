import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/friend.dart';
import '../../models/habit.dart';
import '../../providers/habit_link_provider.dart';
import '../../providers/habit_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_value_view.dart';

class LinkHabitSheet extends ConsumerStatefulWidget {
  final Friend friend;
  final Habit? initialUserHabit;

  const LinkHabitSheet({super.key, required this.friend, this.initialUserHabit});

  @override
  ConsumerState<LinkHabitSheet> createState() => _LinkHabitSheetState();
}

class _LinkHabitSheetState extends ConsumerState<LinkHabitSheet> {
  Habit? _selectedUserHabit;
  Habit? _selectedFriendHabit;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _selectedUserHabit = widget.initialUserHabit;
  }

  bool get _canCreate =>
      _selectedUserHabit != null && _selectedFriendHabit != null;

  String get _previewText {
    if (!_canCreate) return '';
    final firstName = widget.friend.name.split(' ').first;
    return 'When $firstName starts ${_selectedFriendHabit!.name}, you\'ll be reminded to begin ${_selectedUserHabit!.name}.';
  }

  Future<void> _createLink() async {
    if (!_canCreate) return;
    setState(() => _isCreating = true);

    await ref.read(habitLinksProvider.notifier).createLink(
          userHabitId: _selectedUserHabit!.id,
          friendHabitId: _selectedFriendHabit!.id,
          friendshipId: widget.friend.friendshipId,
        );

    if (mounted) {
      setState(() => _isCreating = false);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final myHabitsAsync = ref.watch(habitsProvider);
    final friendHabitsAsync = ref.watch(friendHabitsProvider(widget.friend.id));
    final myHabits = myHabitsAsync.valueOrNull ?? const <Habit>[];
    final friendHabits = friendHabitsAsync.valueOrNull ?? const <Habit>[];
    if (myHabitsAsync.hasError || friendHabitsAsync.hasError) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: AsyncErrorCard(onRetry: () {
          ref.invalidate(habitsProvider);
          ref.invalidate(friendHabitsProvider(widget.friend.id));
        }),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Link a Habit',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create an accountability anchor with ${widget.friend.name.split(' ').first}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),

          // Step 1
          _StepLabel(number: '1', label: 'Choose your habit'),
          const SizedBox(height: 10),
          _HabitSelector(
            habits: myHabits,
            selected: _selectedUserHabit,
            hint: 'Select your habit',
            onSelected: (h) => setState(() => _selectedUserHabit = h),
          ),

          const SizedBox(height: 20),

          // Step 2
          _StepLabel(
            number: '2',
            label: 'Choose ${widget.friend.name.split(' ').first}\'s habit to anchor to',
          ),
          const SizedBox(height: 10),
          _HabitSelector(
            habits: friendHabits,
            selected: _selectedFriendHabit,
            hint: 'Select their habit',
            onSelected: (h) => setState(() => _selectedFriendHabit = h),
          ),

          // Preview text
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _canCreate
                ? Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.colors.primarySurface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(LucideIcons.bellRing,
                              size: 16, color: context.colors.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _previewText,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: context.colors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          const SizedBox(height: 28),

          // Create button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _canCreate && !_isCreating ? _createLink : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primaryAccent,
                disabledBackgroundColor: context.colors.secondarySurface,
                foregroundColor: context.colors.onAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text(
                      'Create Link',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _StepLabel extends StatelessWidget {
  final String number;
  final String label;

  const _StepLabel({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colors.primaryAccent,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.colors.onAccent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _HabitSelector extends StatelessWidget {
  final List<Habit> habits;
  final Habit? selected;
  final String hint;
  final ValueChanged<Habit> onSelected;

  const _HabitSelector({
    required this.habits,
    required this.selected,
    required this.hint,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (selected != null) ...[
              Icon(habitIconData(selected!.iconOrEmoji), size: 20, color: context.colors.textPrimary),
              const SizedBox(width: 10),
            ] else ...[
              Icon(LucideIcons.listChecks,
                  size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                selected?.name ?? hint,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight:
                      selected != null ? FontWeight.w500 : FontWeight.normal,
                  color: selected != null
                      ? context.colors.textPrimary
                      : context.colors.textSecondary,
                ),
              ),
            ),
            Icon(LucideIcons.chevronsUpDown,
                size: 16, color: context.colors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Select a habit',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ...habits.map((h) => GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onSelected(h);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected?.id == h.id
                          ? context.colors.primaryAccent
                          : context.colors.primarySurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected?.id == h.id
                            ? context.colors.primaryAccent
                            : context.colors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          habitIconData(h.iconOrEmoji),
                          size: 20,
                          color: selected?.id == h.id ? Colors.white : context.colors.textPrimary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          h.name,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: selected?.id == h.id
                                ? Colors.white
                                : context.colors.textPrimary,
                          ),
                        ),
                        if (selected?.id == h.id) ...[
                          const Spacer(),
                          const Icon(LucideIcons.check,
                              size: 16, color: Colors.white),
                        ],
                      ],
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
