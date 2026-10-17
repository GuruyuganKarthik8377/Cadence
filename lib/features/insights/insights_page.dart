import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/habit.dart';
import '../../providers/habit_provider.dart';
import '../../services/insights_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_value_view.dart';
import '../../widgets/insight_stat_card.dart';
import '../../widgets/streak_card.dart';
import '../../widgets/habit_progress_row.dart';
import '../../widgets/consistency_bar_chart.dart';
import '../../widgets/insight_highlight_card.dart';
import '../habit_detail/habit_detail_page.dart';

// ---------------------------------------------------------------------------
// Insights Page
// ---------------------------------------------------------------------------

class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  InsightRange _range = InsightRange.week;

  // Re-derived from habitsProvider at the top of every build() so every
  // helper method below can keep referencing it as a plain field.
  late InsightsService _svc;
  late DateRange _dateRange;

  void _setRange(InsightRange r) {
    setState(() => _range = r);
  }

  @override
  Widget build(BuildContext context) {
    final habitsAsync = ref.watch(habitsProvider);
    final habits = habitsAsync.valueOrNull ?? const <Habit>[];
    _svc = InsightsService(habits);
    _dateRange = dateRangeFor(_range);

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final hasHistory = _svc.hasAnyHistory;

    if (habitsAsync.hasError) {
      return Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: context.colors.background,
          elevation: 0,
          leading: IconButton(
            icon: Icon(LucideIcons.chevronLeft,
                color: context.colors.primaryAccent),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: AsyncErrorCard(onRetry: () => ref.invalidate(habitsProvider)),
        ),
      );
    }

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
          'Insights',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: hasHistory
          ? SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(24, 8, 24, 40 + bottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. Date range selector ─────────────────────────────
                  _buildRangeSelector(),
                  const SizedBox(height: 24),

                  // ── 2. Overview stats row ──────────────────────────────
                  _buildOverviewStats(),
                  const SizedBox(height: 28),

                  // ── 3. Consistency chart ───────────────────────────────
                  _buildChartSection(),
                  const SizedBox(height: 28),

                  // ── 4. Pattern insight card ───────────────────────────
                  InsightHighlightCard(insightText: _svc.bestDayInsight()),
                  const SizedBox(height: 28),

                  // ── 5. Streaks ─────────────────────────────────────────
                  _buildStreaksSection(),
                  const SizedBox(height: 28),

                  // ── 6. By Habit breakdown ─────────────────────────────
                  _buildByHabitSection(),
                  const SizedBox(height: 28),

                  // ── 7. By Category (only if >1 category) ─────────────
                  _buildCategorySection(),
                ],
              ),
            )
          : _buildEmptyState(),
    );
  }

  // ── Date range selector ─────────────────────────────────────────────────

  Widget _buildRangeSelector() {
    const options = [InsightRange.week, InsightRange.month, InsightRange.year];
    const labels = ['Week', 'Month', 'Year'];

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.colors.secondarySurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(3, (i) {
          final sel = _range == options[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => _setRange(options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: sel ? context.colors.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : context.colors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Overview stats row ──────────────────────────────────────────────────

  Widget _buildOverviewStats() {
    final consistency = _svc.overallConsistency(_dateRange);
    final completions = _svc.totalCompletions(_dateRange);
    final active = _svc.activeHabitsCount;

    return Row(
      children: [
        InsightStatCard(
          icon: LucideIcons.target,
          value: '${(consistency * 100).round()}%',
          label: 'Consistency',
          delta: _svc.consistencyDelta(_dateRange),
        ),
        const SizedBox(width: 10),
        InsightStatCard(
          icon: LucideIcons.checkCircle2,
          value: '$completions',
          label: 'Completions',
        ),
        const SizedBox(width: 10),
        InsightStatCard(
          icon: LucideIcons.list,
          value: '$active',
          label: 'Active\nHabits',
        ),
      ],
    );
  }

  // ── Consistency chart ───────────────────────────────────────────────────

  Widget _buildChartSection() {
    final bars = _svc.chartData(_range, _dateRange);

    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Consistency Overview',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              Text(
                _rangeSubtitle(),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Use a unique key so AnimationController resets on range change
          KeyedSubtree(
            key: ValueKey(_range),
            child: ConsistencyBarChart(bars: bars),
          ),
        ],
      ),
    );
  }

  String _rangeSubtitle() {
    switch (_range) {
      case InsightRange.week:
        return 'This week';
      case InsightRange.month:
        return 'This month';
      case InsightRange.year:
        return 'This year';
    }
  }

  // ── Streaks ─────────────────────────────────────────────────────────────

  Widget _buildStreaksSection() {
    final streaks = _svc.streaksSorted();
    if (streaks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Streaks'),
        const SizedBox(height: 14),
        SizedBox(
          height: 148,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: streaks.length,
            itemBuilder: (_, i) {
              final info = streaks[i];
              return StreakCard(
                habit: info.habit,
                streak: info.streak,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        HabitDetailPage(habitId: info.habit.id),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── By Habit breakdown ──────────────────────────────────────────────────

  Widget _buildByHabitSection() {
    final breakdown = _svc.breakdownSorted(_dateRange);
    if (breakdown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'By Habit'),
        const SizedBox(height: 14),
        ...breakdown.map((b) => HabitProgressRow(
              key: ValueKey('${b.habit.id}-$_range'),
              habit: b.habit,
              rate: b.rate,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HabitDetailPage(habitId: b.habit.id),
                ),
              ),
            )),
      ],
    );
  }

  // ── By Category ─────────────────────────────────────────────────────────

  Widget _buildCategorySection() {
    final cats = _svc.categoryBreakdown();
    // Only render when there are multiple categories
    if (cats.length < 2) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'By Category'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.colors.primarySurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            children: [
              // Stacked bar
              _StackedCategoryBar(categories: cats),
              const SizedBox(height: 16),
              // Legend
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: List.generate(cats.length, (i) {
                  final shade = _categoryShade(i, cats.length);
                  final pct = (cats[i].rate * 100).round();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: shade,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${cats[i].category}  $pct%',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Empty state ─────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
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
                LucideIcons.barChart2,
                size: 32,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No insights yet',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Complete a few habits to see your insights here.',
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

// ---------------------------------------------------------------------------
// Stacked category bar (grayscale)
// ---------------------------------------------------------------------------

class _StackedCategoryBar extends StatefulWidget {
  final List<CategoryBreakdown> categories;
  const _StackedCategoryBar({required this.categories});

  @override
  State<_StackedCategoryBar> createState() => _StackedCategoryBarState();
}

class _StackedCategoryBarState extends State<_StackedCategoryBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total =
        widget.categories.fold(0, (s, c) => s + c.total).toDouble();

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 20,
          child: Row(
            children: List.generate(widget.categories.length, (i) {
              final cat = widget.categories[i];
              final fraction = total == 0 ? 0.0 : cat.total / total;
              return Expanded(
                flex: (fraction * 1000).round(),
                child: Container(
                  color: _categoryShade(i, widget.categories.length)
                      .withValues(alpha: _anim.value),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _categoryShade(int index, int total) {
  // Grayscale spectrum from near-black to light gray
  final shades = [
    const Color(0xFF111111),
    const Color(0xFF444444),
    const Color(0xFF777777),
    const Color(0xFFAAAAAA),
    const Color(0xFFCCCCCC),
    const Color(0xFFE0E0E0),
  ];
  return shades[index.clamp(0, shades.length - 1)];
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}

// ---------------------------------------------------------------------------
// InsightsTabView — renders Insights as a bottom-nav tab (no back button).
// Shares all logic/widgets with InsightsPage; only the chrome differs.
// ---------------------------------------------------------------------------

class InsightsTabView extends ConsumerStatefulWidget {
  const InsightsTabView({super.key});

  @override
  ConsumerState<InsightsTabView> createState() => _InsightsTabViewState();
}

class _InsightsTabViewState extends ConsumerState<InsightsTabView> {
  InsightRange _range = InsightRange.week;
  late InsightsService _svc;
  late DateRange _dateRange;

  void _setRange(InsightRange r) {
    setState(() => _range = r);
  }

  @override
  Widget build(BuildContext context) {
    final habitsAsync = ref.watch(habitsProvider);
    final habits = habitsAsync.valueOrNull ?? const <Habit>[];
    _svc = InsightsService(habits);
    _dateRange = dateRangeFor(_range);

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final hasHistory = _svc.hasAnyHistory;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tab header (no back button) ────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text(
              'Insights',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),

          // ── Scrollable content ─────────────────────────────────────────
          if (habitsAsync.hasError)
            AsyncErrorCard(onRetry: () => ref.invalidate(habitsProvider))
          else
          Expanded(
            child: hasHistory
                ? SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 120 + bottomPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRangeSelector(),
                        const SizedBox(height: 24),
                        _buildOverviewStats(),
                        const SizedBox(height: 28),
                        _buildChartSection(),
                        const SizedBox(height: 28),
                        InsightHighlightCard(insightText: _svc.bestDayInsight()),
                        const SizedBox(height: 28),
                        _buildStreaksSection(),
                        const SizedBox(height: 28),
                        _buildByHabitSection(),
                        const SizedBox(height: 28),
                        _buildCategorySection(),
                      ],
                    ),
                  )
                : _buildEmptyState(),
          ),
        ],
      ),
    );
  }

  // Reuse the same builder methods from InsightsPage ─────────────────────

  Widget _buildRangeSelector() {
    const options = [InsightRange.week, InsightRange.month, InsightRange.year];
    const labels = ['Week', 'Month', 'Year'];
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: context.colors.secondarySurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(3, (i) {
          final sel = _range == options[i];
          return Expanded(
            child: GestureDetector(
              onTap: () => _setRange(options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: sel ? context.colors.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : context.colors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOverviewStats() {
    final consistency = _svc.overallConsistency(_dateRange);
    final completions = _svc.totalCompletions(_dateRange);
    final active = _svc.activeHabitsCount;
    return Row(
      children: [
        InsightStatCard(
          icon: LucideIcons.target,
          value: '${(consistency * 100).round()}%',
          label: 'Consistency',
          delta: _svc.consistencyDelta(_dateRange),
        ),
        const SizedBox(width: 10),
        InsightStatCard(
          icon: LucideIcons.checkCircle2,
          value: '$completions',
          label: 'Completions',
        ),
        const SizedBox(width: 10),
        InsightStatCard(
          icon: LucideIcons.list,
          value: '$active',
          label: 'Active\nHabits',
        ),
      ],
    );
  }

  Widget _buildChartSection() {
    final bars = _svc.chartData(_range, _dateRange);
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Consistency Overview',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              Text(
                _rangeSubtitle(),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          KeyedSubtree(
            key: ValueKey(_range),
            child: ConsistencyBarChart(bars: bars),
          ),
        ],
      ),
    );
  }

  String _rangeSubtitle() {
    switch (_range) {
      case InsightRange.week:
        return 'This week';
      case InsightRange.month:
        return 'This month';
      case InsightRange.year:
        return 'This year';
    }
  }

  Widget _buildStreaksSection() {
    final streaks = _svc.streaksSorted();
    if (streaks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Streaks'),
        const SizedBox(height: 14),
        SizedBox(
          height: 148,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: streaks.length,
            itemBuilder: (_, i) {
              final info = streaks[i];
              return StreakCard(
                habit: info.habit,
                streak: info.streak,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HabitDetailPage(habitId: info.habit.id),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildByHabitSection() {
    final breakdown = _svc.breakdownSorted(_dateRange);
    if (breakdown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'By Habit'),
        const SizedBox(height: 14),
        ...breakdown.map((b) => HabitProgressRow(
              key: ValueKey('${b.habit.id}-$_range'),
              habit: b.habit,
              rate: b.rate,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HabitDetailPage(habitId: b.habit.id),
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildCategorySection() {
    final cats = _svc.categoryBreakdown();
    if (cats.length < 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'By Category'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.colors.primarySurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            children: [
              _StackedCategoryBar(categories: cats),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: List.generate(cats.length, (i) {
                  final shade = _categoryShade(i, cats.length);
                  final pct = (cats[i].rate * 100).round();
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: shade,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${cats[i].category}  $pct%',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
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
                LucideIcons.barChart2,
                size: 32,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No insights yet',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Complete a few habits to see your insights here.',
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
