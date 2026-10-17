import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/focus_card.dart';
import '../../widgets/habit_card.dart';
import '../../widgets/progress_chart.dart';
import '../../models/habit.dart';
import '../../providers/auth_provider.dart';
import '../../providers/habit_provider.dart';
import '../../providers/nudge_provider.dart';
import '../../services/insights_service.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/async_value_view.dart';
import '../friends/friends_page.dart';
import '../profile/profile_page.dart';
import '../add_habit/add_habit_page.dart';
import '../habit_detail/habit_detail_page.dart';
import '../insights/insights_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

enum _StatusFilter { all, completed, pending }

class _HomePageState extends ConsumerState<HomePage> {
  // 0=Home, 1=Insights, 2=+(unused as tab), 3=Friends, 4=Habits
  int _bottomNavIndex = 0;
  int _selectedCategoryIndex = 0;
  _StatusFilter _statusFilter = _StatusFilter.all;

  /// 'All' plus the distinct categories of the user's actual habits, so
  /// custom categories always get a chip and unused defaults don't.
  List<String> get categories {
    final habits = ref.watch(habitsProvider).valueOrNull ?? const <Habit>[];
    final cats = habits.map((h) => h.category).where((c) => c.isNotEmpty).toSet().toList()..sort();
    return ['All', ...cats];
  }

  List<Habit> _applyFilters(List<Habit> habits) {
    final cats = categories;
    final idx = _selectedCategoryIndex < cats.length ? _selectedCategoryIndex : 0;
    final selectedCat = cats[idx];
    var result = selectedCat == 'All'
        ? habits
        : habits.where((h) => h.category == selectedCat).toList();
    switch (_statusFilter) {
      case _StatusFilter.completed:
        result = result.where((h) => h.isCompletedToday).toList();
      case _StatusFilter.pending:
        result = result.where((h) => !h.isCompletedToday).toList();
      case _StatusFilter.all:
        break;
    }
    return result;
  }

  void _openAddHabit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddHabitPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Insights tab (index 1)
    if (_bottomNavIndex == 1) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Stack(
          children: [
            const InsightsTabView(),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingBottomNav(
                currentIndex: _bottomNavIndex,
                onTap: _handleNavTap,
                onAddTap: _openAddHabit,
              ),
            ),
          ],
        ),
      );
    }

    // Friends tab (index 3)
    if (_bottomNavIndex == 3) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Stack(
          children: [
            const FriendsPage(isTabMode: true),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingBottomNav(
                currentIndex: _bottomNavIndex,
                onTap: _handleNavTap,
                onAddTap: _openAddHabit,
              ),
            ),
          ],
        ),
      );
    }

    // Habits tab (index 4)
    if (_bottomNavIndex == 4) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Stack(
          children: [
            _buildHabitsContent(bottomPadding),

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingBottomNav(
                currentIndex: _bottomNavIndex,
                onTap: _handleNavTap,
                onAddTap: _openAddHabit,
              ),
            ),
          ],
        ),
      );
    }

    // Home tab (index 0) — default
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(bottom: 120 + bottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  _buildNudgeBanner(),
                  const SizedBox(height: 32),
                  _buildSearchBar(),
                  const SizedBox(height: 24),
                  _buildCategories(),
                  const SizedBox(height: 32),
                  _buildTodayFocus(),
                  const SizedBox(height: 40),
                  _buildTodayHabits(),
                  const SizedBox(height: 40),
                  _buildWeeklyProgress(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingBottomNav(
              currentIndex: _bottomNavIndex,
              onTap: _handleNavTap,
              onAddTap: _openAddHabit,
            ),
          ),
        ],
      ),
    );
  }

  void _handleNavTap(int index) {
    if (index == 2) {
      _openAddHabit();
      return;
    }
    setState(() => _bottomNavIndex = index);
  }

  // ── Habits tab content (inlined to avoid DDC module diamond deps) ───────

  Widget _buildHabitsContent(double bottomPadding) {
    final habitsAsync = ref.watch(habitsProvider);
    if (habitsAsync.hasError) {
      return SafeArea(
        child: Center(
          child: AsyncErrorCard(
              onRetry: () => ref.invalidate(habitsProvider)),
        ),
      );
    }
    final habits = habitsAsync.valueOrNull ?? const <Habit>[];
    final filteredHabits = _applyFilters(habits);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text(
              'My Habits',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Expanded(
            child: filteredHabits.isEmpty
                ? Center(
                    child: Text(
                      'No habits found for this category.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding:
                        EdgeInsets.fromLTRB(24, 0, 24, 120 + bottomPadding),
                    itemCount: filteredHabits.length,
                    itemBuilder: (ctx, index) {
                      final habit = filteredHabits[index];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HabitDetailPage(habitId: habit.id),
                          ),
                        ),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: context.colors.primarySurface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: context.colors.border),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  habitCoverImageFor(
                                      habit.coverImageUrl, habit.id),
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stack) =>
                                      Container(
                                    width: 40,
                                    height: 40,
                                    color: context.colors.secondarySurface,
                                    child: Center(
                                      child: Icon(
                                        habitIconData(habit.iconOrEmoji),
                                        size: 20,
                                        color: context.colors.textPrimary,
                                      ),
                                    ),
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
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  /// Unread pokes from friends. Absent entirely when there are none, so the
  /// home screen doesn't carry a permanent empty slot.
  Widget _buildNudgeBanner() {
    final nudges = ref.watch(incomingNudgesProvider).valueOrNull ?? const [];
    if (nudges.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        children: [
          for (final nudge in nudges.take(3))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.colors.primaryAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: context.colors.primaryAccent.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.handHelping,
                      size: 16, color: context.colors.primaryAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${nudge.fromName} nudged you about ${nudge.habitName}',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        height: 1.35,
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => ref
                        .read(incomingNudgesProvider.notifier)
                        .dismiss(nudge.id),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(LucideIcons.x,
                          size: 15, color: context.colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final firstName =
        profile != null ? profile.displayName.split(' ').first : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstName.isEmpty ? _greeting : '$_greeting, $firstName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Stay consistent today.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Friends shortcut icon
          GestureDetector(
            onTap: () => setState(() => _bottomNavIndex = 3),
            child: Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.border),
              ),
              child: Icon(
                LucideIcons.users,
                size: 20,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfilePage(
                  onSwitchToHabits: () => setState(() => _bottomNavIndex = 4),
                  onSwitchToFriends: () => setState(() => _bottomNavIndex = 3),
                ),
              ),
            ),
            child: AppAvatar(
              radius: 24,
              name: profile?.displayName ?? '',
              imageUrl: profile?.avatarUrl,
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 20),
            Icon(LucideIcons.search, color: context.colors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: _showSearchSheet,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'What habit are you building today?',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.colors.textSecondary,
                      ),
                ),
              ),
            ),
            GestureDetector(
              onTap: _showFilterSheet,
              child: Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: context.colors.primaryAccent,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Icon(LucideIcons.slidersHorizontal,
                    color: context.colors.onAccent, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Categories ─────────────────────────────────────────────────────────

  Widget _buildCategories() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedCategoryIndex == index;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategoryIndex = index;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? context.colors.primaryAccent : context.colors.primarySurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? context.colors.primaryAccent : context.colors.border,
                ),
              ),
              child: Center(
                child: Text(
                  categories[index],
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: isSelected ? context.colors.onAccent : context.colors.textSecondary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Today's Focus ──────────────────────────────────────────────────────

  Widget _buildTodayFocus() {
    final habits = ref.watch(habitsProvider).valueOrNull ?? const <Habit>[];
    if (habits.isEmpty) return const SizedBox.shrink();
    // Focus on the first habit still pending today; hide once all are done.
    final focusHabit =
        habits.where((h) => !h.isCompletedToday).firstOrNull;
    if (focusHabit == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s Focus',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 20),
          FocusCard(
            title: focusHabit.name,
            duration: '${focusHabit.durationValue} ${focusHabit.durationUnit}',
            category: focusHabit.category,
            imageUrl: habitCoverImageFor(focusHabit.coverImageUrl, focusHabit.id),
            onStartTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HabitDetailPage(habitId: focusHabit.id)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Today's Habits ─────────────────────────────────────────────────────

  Widget _buildTodayHabits() {
    final habitsAsync = ref.watch(habitsProvider);
    if (habitsAsync.hasError) {
      return AsyncErrorCard(onRetry: () => ref.invalidate(habitsProvider));
    }
    final habits = habitsAsync.valueOrNull ?? const <Habit>[];
    final filteredHabits = _applyFilters(habits);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Today\'s Habits',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              GestureDetector(
                onTap: () => setState(() => _bottomNavIndex = 4),
                child: Text(
                  'See all',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: context.colors.textSecondary,
                        decoration: TextDecoration.underline,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 180,
          child: filteredHabits.isEmpty
              ? Center(
                  child: Text(
                    'No habits found for this category.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(left: 24, right: 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: filteredHabits.length,
                  itemBuilder: (context, index) {
                    final habit = filteredHabits[index];
                    return HabitCard(
                      name: habit.name,
                      duration: '${habit.durationValue} ${habit.durationUnit}',
                      icon: habitIconData(habit.iconOrEmoji),
                      isCompleted: habit.isCompletedToday,
                      imageUrl: habitCoverImageFor(habit.coverImageUrl, habit.id),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HabitDetailPage(habitId: habit.id),
                        ),
                      ),
                      onToggleComplete: () {
                        // Run/walk habits require a verified accelerometer
                        // session (also enforced server-side) — route to the
                        // habit page's Start Run flow instead of toggling.
                        if (isRunOrWalkHabit(habit) && !habit.isCompletedToday) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'This habit needs a tracked run to complete.',
                              ),
                            ),
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HabitDetailPage(habitId: habit.id),
                            ),
                          );
                          return;
                        }
                        ref
                            .read(habitsProvider.notifier)
                            .toggleCompletion(habit.id, DateTime.now());
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Weekly Progress ────────────────────────────────────────────────────

  Widget _buildWeeklyProgress() {
    final habits = ref.watch(habitsProvider).valueOrNull ?? const <Habit>[];
    if (habits.isEmpty) return const SizedBox.shrink();
    final svc = InsightsService(habits);
    final range = dateRangeFor(InsightRange.week);
    final bars = svc.chartData(InsightRange.week, range);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: ProgressChart(
        weeklyData: bars.map((b) => b.value).toList(),
      ),
    );
  }

  // ── Modals ─────────────────────────────────────────────────────────────

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _HabitSearchSheet(
        habits: ref.read(habitsProvider).valueOrNull ?? const <Habit>[],
        onSelect: (habit) {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => HabitDetailPage(habitId: habit.id),
            ),
          );
        },
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        var selected = _statusFilter;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                Text(
                  'Status',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: context.colors.textPrimary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, value) in [
                      ('All', _StatusFilter.all),
                      ('Completed', _StatusFilter.completed),
                      ('Pending', _StatusFilter.pending),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: selected == value,
                        onSelected: (_) =>
                            setSheetState(() => selected = value),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _statusFilter = selected);
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.primaryAccent,
                      foregroundColor: context.colors.primarySurface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    child: const Text('Apply Filters',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Habit search sheet — live filtering over the user's habits
// ---------------------------------------------------------------------------

class _HabitSearchSheet extends StatefulWidget {
  const _HabitSearchSheet({required this.habits, required this.onSelect});

  final List<Habit> habits;
  final ValueChanged<Habit> onSelect;

  @override
  State<_HabitSearchSheet> createState() => _HabitSearchSheetState();
}

class _HabitSearchSheetState extends State<_HabitSearchSheet> {
  String _query = '';

  List<Habit> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.habits;
    return widget.habits
        .where((h) =>
            h.name.toLowerCase().contains(q) ||
            h.category.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search Habits',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            autofocus: true,
            onChanged: (val) => setState(() => _query = val),
            decoration: InputDecoration(
              hintText: 'Type to search...',
              hintStyle: TextStyle(color: context.colors.textSecondary),
              prefixIcon: Icon(LucideIcons.search,
                  color: context.colors.textSecondary),
              filled: true,
              fillColor: context.colors.primarySurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: context.colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: context.colors.border),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  widget.habits.isEmpty
                      ? 'No habits yet — tap + to create one.'
                      : 'No habits match "$_query".',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (ctx, i) {
                  final habit = results[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.colors.secondarySurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(habitIconData(habit.iconOrEmoji),
                          size: 20, color: context.colors.textPrimary),
                    ),
                    title: Text(
                      habit.name,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    subtitle: habit.category.isEmpty
                        ? null
                        : Text(
                            habit.category,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: context.colors.textSecondary,
                            ),
                          ),
                    trailing: Icon(LucideIcons.chevronRight,
                        size: 16, color: context.colors.textSecondary),
                    onTap: () => widget.onSelect(habit),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
