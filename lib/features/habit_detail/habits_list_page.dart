import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/habit.dart';
import '../../providers/habit_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_value_view.dart';
import 'habit_detail_page.dart';

// ---------------------------------------------------------------------------
// HabitsListPage — full-screen, accessible from Profile → "My Habits"
// ---------------------------------------------------------------------------

class HabitsListPage extends ConsumerWidget {
  const HabitsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);
    final habits = habitsAsync.valueOrNull ?? const <Habit>[];

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
          'My Habits',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: habitsAsync.hasError
          ? Center(
              child: AsyncErrorCard(
                  onRetry: () => ref.invalidate(habitsProvider)))
          : habitsAsync.isLoading
              ? const Center(child: CircularProgressIndicator())
              : habits.isEmpty
              ? const _EmptyState()
              : _ReorderableHabitList(
                  habits: habits,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared list body — long-press a row to drag it into a new position.
// ---------------------------------------------------------------------------

class _ReorderableHabitList extends ConsumerWidget {
  final List<Habit> habits;
  final EdgeInsets padding;

  const _ReorderableHabitList({required this.habits, required this.padding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: padding,
      itemCount: habits.length,
      onReorderItem: (oldIndex, newIndex) async {
        HapticFeedback.mediumImpact();
        try {
          await ref
              .read(habitsProvider.notifier)
              .reorderHabits(oldIndex, newIndex);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Couldn't save the new order.")),
            );
          }
        }
      },
      // The default handle sits on the trailing edge and fights the row's
      // own tap target, so the whole row becomes the drag handle instead.
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final habit = habits[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(habit.id),
          index: index,
          child: _HabitListRow(
            habit: habit,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HabitDetailPage(habitId: habit.id),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// HabitsTabView — renders Habits as a bottom-nav tab (no back button).
// ---------------------------------------------------------------------------

class HabitsTabView extends ConsumerWidget {
  const HabitsTabView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);
    final habits = habitsAsync.valueOrNull ?? const <Habit>[];
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tab header ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text(
              'My Habits',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),

          // ── Scrollable list ───────────────────────────────────────────
          Expanded(
            child: habitsAsync.hasError
                ? Center(
                    child: AsyncErrorCard(
                        onRetry: () => ref.invalidate(habitsProvider)))
                : habitsAsync.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : habits.isEmpty
                    ? const _EmptyState()
                    : _ReorderableHabitList(
                        habits: habits,
                        padding: EdgeInsets.fromLTRB(
                            24, 0, 24, 120 + bottomPadding),
                      ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Habit list row
// ---------------------------------------------------------------------------

class _HabitListRow extends StatelessWidget {
  final Habit habit;
  final VoidCallback onTap;

  const _HabitListRow({required this.habit, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.colors.secondarySurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  habitIconData(habit.iconOrEmoji),
                  size: 20,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.name,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  if (habit.category.isNotEmpty)
                    Text(
                      habit.category,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: context.colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight,
                size: 16, color: context.colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.colors.secondarySurface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                LucideIcons.list,
                size: 32,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No habits yet',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tap + to add your first habit.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: context.colors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
