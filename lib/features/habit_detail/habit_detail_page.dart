import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/habit.dart';
import '../../models/friend.dart';
import '../../models/habit_link.dart';
import '../../models/run_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_provider.dart';
import '../../providers/habit_link_provider.dart';
import '../../providers/habit_provider.dart';
import '../../providers/run_session_provider.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/async_value_view.dart';
import '../add_habit/add_habit_page.dart';
import '../friends/link_habit_sheet.dart';
import '../run_tracker/run_tracker_page.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const double _kCoverHeight = 280.0;


// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class HabitDetailPage extends ConsumerStatefulWidget {
  final String habitId;

  const HabitDetailPage({super.key, required this.habitId});

  @override
  ConsumerState<HabitDetailPage> createState() => _HabitDetailPageState();
}

class _HabitDetailPageState extends ConsumerState<HabitDetailPage> {
  // Re-derived from habitsProvider at the top of every build() so every
  // helper method below can keep referencing it as a plain field.
  late Habit _habit;
  bool _isCheckingIn = false;
  bool _isFreezing = false;

  // ── Derived helpers ─────────────────────────────────────────────────────

  Friend? get _linkedFriend {
    if (_habit.linkedFriendId == null) return null;
    final friends = ref.watch(friendsProvider).valueOrNull?.friends ?? const [];
    return friends.where((f) => f.id == _habit.linkedFriendId).firstOrNull;
  }

  HabitLink? get _habitLink {
    final links = ref.watch(habitLinksProvider).valueOrNull ?? const [];
    return links.where((l) => l.userHabitId == _habit.id).firstOrNull;
  }

  String _formatFrequency() {
    switch (_habit.frequency) {
      case FrequencyType.daily:
        return 'Every day';
      case FrequencyType.timesPerWeek:
        return '${_habit.timesPerWeek}× per week';
      case FrequencyType.specificDays:
        const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return _habit.specificDays.map((i) => labels[i]).join(', ');
    }
  }

  String _formatGoal() {
    if (_habit.durationValue == 0) return '';
    return '${_habit.durationValue} ${_habit.durationUnit}';
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  String _habitTypeLabel() {
    switch (_habit.habitType) {
      case HabitType.build:
        return 'Build';
      case HabitType.breakHabit:
        return 'Break';
      case HabitType.custom:
        return _habit.customTypeLabel ?? 'Custom';
    }
  }

  Future<void> _toggleTodayCompletion() async {
    // Run/walk habits redirect to the accelerometer tracker (server-enforced).
    // Un-completing is always allowed without restriction.
    if (isRunOrWalkHabit(_habit) && !_habit.isCompletedToday) {
      _startRunTracking();
      return;
    }
    if (_habit.hasLocation && !_habit.isCompletedToday) {
      await _checkInAtLocation();
      return;
    }
    HapticFeedback.mediumImpact();
    await ref.read(habitsProvider.notifier).toggleCompletion(_habit.id, DateTime.now());
  }

  Future<void> _checkInAtLocation() async {
    setState(() => _isCheckingIn = true);
    try {
      final result = await LocationService.checkAtLocation(
        _habit.locationLat!,
        _habit.locationLng!,
        radiusMeters: _habit.locationRadiusM.toDouble(),
      );
      if (!mounted) return;
      if (result.withinRange) {
        HapticFeedback.mediumImpact();
        await ref
            .read(habitsProvider.notifier)
            .toggleCompletion(_habit.id, DateTime.now());
      } else {
        final dist = result.distance < 1000
            ? '${result.distance.round()} m'
            : '${(result.distance / 1000).toStringAsFixed(1)} km';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "You're $dist away from ${_habit.locationName}. "
                'Get closer to check in.',
                style: const TextStyle(fontFamily: 'Inter'),
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              margin: const EdgeInsets.all(20),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceFirst('Exception: ', ''),
              style: const TextStyle(fontFamily: 'Inter'),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            margin: const EdgeInsets.all(20),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingIn = false);
    }
  }

  // ── Delete ──────────────────────────────────────────────────────────────

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.primarySurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Delete this habit?',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
            fontSize: 17,
          ),
        ),
        content: Text(
          'This will permanently remove "${_habit.name}" and its history.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: context.colors.textSecondary,
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
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(habitsProvider.notifier).deleteHabit(_habit.id);
              if (mounted) Navigator.pop(context);
            },
            child: const Text(
              'Delete',
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

  void _showMoreMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(LucideIcons.pencil, color: context.colors.textPrimary),
                title: Text(
                  'Edit Habit',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AddHabitPage(habit: _habit)),
                  );
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.archive, color: context.colors.textPrimary),
                title: Text(
                  'Archive',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ref.read(habitsProvider.notifier).archiveHabit(_habit.id);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.trash2, color: Colors.red),
                title: const Text(
                  'Delete Habit',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDeleteDialog();
                },
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        );
      },
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final habitsAsync = ref.watch(habitsProvider);
    final habit = habitsAsync.valueOrNull?.where((h) => h.id == widget.habitId).firstOrNull;

    if (habit == null) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Center(
          child: habitsAsync.isLoading
              ? const CircularProgressIndicator()
              : Text('Habit not found', style: TextStyle(color: context.colors.textSecondary)),
        ),
      );
    }
    _habit = habit;

    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── 1. Collapsing cover image ──────────────────────────────────
          _buildSliverHeader(),

          // ── Body content ───────────────────────────────────────────────
          SliverPadding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 40 + bottomPadding),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 24),
                _buildTitleBlock(),
                const SizedBox(height: 24),
                _buildStatsRow(),
                const SizedBox(height: 28),
                _buildTodayCard(),
                const SizedBox(height: 28),
                _buildHeatmap(),
                const SizedBox(height: 28),
                _buildAccountabilitySection(),
                const SizedBox(height: 28),
                _buildScheduleSection(),
                if (isRunOrWalkHabit(_habit)) ...[
                  const SizedBox(height: 28),
                  _buildRunHistory(),
                ],
                const SizedBox(height: 40),
                _buildActions(),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sliver Header (Cover Image + AppBar) ────────────────────────────────

  Widget _buildSliverHeader() {
    return SliverAppBar(
      expandedHeight: _kCoverHeight,
      pinned: true,
      stretch: true,
      backgroundColor: context.colors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      // Collapsed bar (shows when scrolled past the image)
      title: Text(
        _habit.name,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: context.colors.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // Collapsed-bar controls — shown only when scrolled past the image
      leading: IconButton(
        icon: const Icon(LucideIcons.chevronLeft, size: 20),
        onPressed: () => Navigator.pop(context),
        color: context.colors.textPrimary,
      ),
      actions: [
        IconButton(
          icon: Icon(
            LucideIcons.star,
            size: 20,
            color: _habit.isFavorite
                ? context.colors.primaryAccent
                : context.colors.textSecondary,
          ),
          onPressed: _toggleFavorite,
        ),
        IconButton(
          icon: const Icon(LucideIcons.moreHorizontal, size: 20),
          onPressed: () => _showMoreMenu(context),
          color: context.colors.textSecondary,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: _buildCoverImageArea(),
      ),
    );
  }

  Widget _buildCoverImageArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Cover image (own cover, or a stable preset) with icon fallback.
        Image.network(
          habitCoverImageFor(_habit.coverImageUrl, _habit.id),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildFallbackCover(),
        ),

        // Gradient overlay — dark at top for controls, dark at bottom for tag
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.40),
                ],
                stops: const [0.0, 0.25, 0.65, 1.0],
              ),
            ),
          ),
        ),

        // ── Header icons: back ◄ (left)  |  ★ ⋯ (right) ───────────────────
        // Positioned.fill ensures the Row spans the full image area.
        // SafeArea keeps icons below the status bar.
        // Each icon is a 40×40 black-translucent circle with a white icon
        // inside — readable on ANY image brightness.
        Positioned.fill(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button — left
                  _buildCoverIconBtn(
                    icon: LucideIcons.chevronLeft,
                    onTap: () => Navigator.pop(context),
                  ),
                  // Star + overflow — right
                  Row(
                    children: [
                      _buildCoverIconBtn(
                        icon: LucideIcons.star,
                        highlighted: _habit.isFavorite,
                        onTap: _toggleFavorite,
                      ),
                      const SizedBox(width: 12),
                      _buildCoverIconBtn(
                        icon: LucideIcons.moreHorizontal,
                        onTap: () => _showMoreMenu(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Category tag (bottom-left of image)
        Positioned(
          bottom: 20,
          left: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _habit.category.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackCover() {
    return Container(
      color: context.colors.secondarySurface,
      child: Center(
        child: Icon(
          habitIconData(_habit.iconOrEmoji),
          size: 56,
          color: context.colors.textPrimary,
        ),
      ),
    );
  }

  /// 40×40 black-translucent circle button placed directly over the cover image.
  /// Readable on any image brightness (bright OR dark cover photo).
  Widget _buildCoverIconBtn({
    required IconData icon,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    return Container(
      width: 40,
      height: 40,
      // Fixed colors: these buttons sit on the cover image's dark scrim,
      // which doesn't change with the theme.
      decoration: BoxDecoration(
        color: highlighted ? Colors.white : Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: highlighted ? Colors.black : Colors.white,
          size: 20,
        ),
        onPressed: onTap,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    final newValue = !_habit.isFavorite;
    setState(() => _habit = _habit.copyWith(isFavorite: newValue));
    try {
      await ref
          .read(habitsProvider.notifier)
          .setFavorite(_habit.id, newValue);
    } catch (_) {
      if (mounted) {
        setState(() => _habit = _habit.copyWith(isFavorite: !newValue));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save favorite. Try again.")),
        );
      }
    }
  }

  // ── 2. Title Block ──────────────────────────────────────────────────────

  Widget _buildTitleBlock() {
    final goal = _formatGoal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _habit.name,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.colors.primaryAccent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _habitTypeLabel(),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.colors.onAccent,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            if (goal.isNotEmpty) ...[
              const SizedBox(width: 10),
              Icon(LucideIcons.clock3,
                  size: 13, color: context.colors.textSecondary),
              const SizedBox(width: 4),
              Text(
                goal,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(LucideIcons.repeat2,
                size: 13, color: context.colors.textSecondary),
            const SizedBox(width: 5),
            Text(
              _formatFrequency(),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── 3. Stats Row ────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Column(
      children: [
        Row(
          children: [
            _StatCard(
              icon: LucideIcons.flame,
              value: '${_habit.currentStreak}',
              label: 'Current\nStreak',
            ),
            const SizedBox(width: 10),
            _StatCard(
              icon: LucideIcons.trophy,
              value: '${_habit.bestStreak}',
              label: 'Best\nStreak',
            ),
            const SizedBox(width: 10),
            _StatCard(
              icon: LucideIcons.target,
              value: '${_habit.completionRateLast30}%',
              label: 'Last 30\nDays',
            ),
          ],
        ),
        _buildEarnFreezeBanner(),
        _buildFreezeBanner(),
      ],
    );
  }

  /// Milestone banner — appears once per 7-day streak tier until claimed.
  Widget _buildEarnFreezeBanner() {
    final streak = _habit.currentStreak;
    final lastAwarded = _habit.freezeAwardedAtStreak;
    // A new milestone = a new floor(streak/7) level above the last awarded one.
    if (streak < 7 || (streak ~/ 7) <= (lastAwarded ~/ 7)) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.primarySurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.primaryAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Text('🧊', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$streak-day milestone! Claim a bonus freeze.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                height: 1.4,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          _isFreezing
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : GestureDetector(
                  onTap: () => _claimFreeze(),
                  child: Text(
                    'Claim',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.colors.primaryAccent,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _claimFreeze() async {
    setState(() => _isFreezing = true);
    try {
      final awarded = await ref.read(habitsProvider.notifier).earnFreeze(_habit.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(awarded
              ? '🧊 Freeze added to your balance!'
              : 'Already claimed for this milestone.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isFreezing = false);
    }
  }

  /// Offered only when there's a specific missed day a freeze would rescue,
  /// so it stays out of the way while the streak is healthy.
  Widget _buildFreezeBanner() {
    final missed = _habit.lastMissedDay;
    if (missed == null) return const SizedBox.shrink();

    final remaining =
        ref.watch(currentProfileProvider).valueOrNull?.availableFreezes ?? 0;
    final label = '${_weekdayName(missed.weekday)} ${missed.day} '
        '${_monthName(missed.month)}';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.primarySurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.snowflake, size: 16, color: context.colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              remaining > 0
                  ? 'Missed $label. Use a freeze to protect your streak '
                      '($remaining left).'
                  : 'Missed $label. No freezes left this month.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                height: 1.4,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          if (remaining > 0) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _isFreezing ? null : () => _useFreeze(missed),
              child: _isFreezing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Freeze',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.primaryAccent,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _useFreeze(DateTime day) async {
    setState(() => _isFreezing = true);
    try {
      await ref.read(habitsProvider.notifier).useFreeze(_habit.id, day);
      if (mounted) HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFreezing = false);
    }
  }

  // ── 4. Today's Status Card ──────────────────────────────────────────────

  /// Second line of the completed state — shows what was actually logged when
  /// there is anything, rather than a generic cheer.
  String _completedSubtitle() {
    final today = DateTime.now();
    final note = _habit.noteOn(today);
    final qty = _habit.quantityOn(today);
    final progress = qty == null
        ? null
        : _habit.hasGoal
            ? '$qty of ${_habit.durationValue} ${_habit.durationUnit}'
            : '$qty ${_habit.durationUnit}';

    // Show both when both exist — logging a quantity shouldn't hide the note,
    // or the other way round.
    if (progress != null && note != null) return '$progress · $note';
    return progress ?? note ?? 'Keep the streak going!';
  }

  Widget _buildDetailAffordance() {
    final detail = _habit.detailOn(DateTime.now());
    final hasDetail = detail != null && !detail.isEmpty;
    return GestureDetector(
      onTap: _showDetailSheet,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(hasDetail ? LucideIcons.pencil : LucideIcons.plus,
              size: 13, color: context.colors.primaryAccent),
          const SizedBox(width: 6),
          Text(
            hasDetail ? 'Edit details' : 'Add how it went',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.primaryAccent,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetailSheet() async {
    final today = DateTime.now();
    final detail = _habit.detailOn(today);
    final quantityController = TextEditingController(
        text: detail?.quantity != null ? '${detail!.quantity}' : '');
    final noteController = TextEditingController(text: detail?.note ?? '');

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
            Text(
              'How did it go?',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            if (_habit.hasGoal) ...[
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                // Digits only. The DB rejects negatives, and a check-constraint
                // violation surfaces as an unhelpful "couldn't save"; block the
                // minus sign (and any pasted text) at the field instead.
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                    fontFamily: 'Inter', color: context.colors.textPrimary),
                decoration: InputDecoration(
                  labelText:
                      '${_habit.durationUnit} done (goal ${_habit.durationValue})',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: noteController,
              maxLength: 140,
              maxLines: 2,
              style: TextStyle(
                  fontFamily: 'Inter', color: context.colors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );

    final quantityText = quantityController.text.trim();
    final noteText = noteController.text.trim();
    quantityController.dispose();
    noteController.dispose();
    if (saved != true || !mounted) return;

    try {
      await ref.read(habitsProvider.notifier).logCompletionDetail(
            _habit.id,
            today,
            quantity: quantityText.isEmpty ? null : int.tryParse(quantityText),
            note: noteText.isEmpty ? null : noteText,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save those details.")),
        );
      }
    }
  }

  Widget _buildTodayCard() {
    final completed = _habit.isCompletedToday;
    final today = DateTime.now();
    final dateLabel =
        '${_weekdayName(today.weekday)}, ${_monthName(today.month)} ${today.day}';

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
            children: [
              Icon(LucideIcons.calendarCheck,
                  size: 16, color: context.colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                dateLabel,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (completed) ...[
            // Completed state
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.colors.primaryAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.check,
                      color: context.colors.onAccent, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Completed today',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      Text(
                        _completedSubtitle(),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _toggleTodayCompletion,
                  child: Text(
                    'Undo',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: context.colors.textSecondary,
                      decoration: TextDecoration.underline,
                      decorationColor: context.colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDetailAffordance(),
          ] else ...[
            // Mark complete / Check In button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed:
                    _isCheckingIn ? null : _toggleTodayCompletion,
                icon: _isCheckingIn
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.onAccent,
                        ),
                      )
                    : Icon(
                        _habit.hasLocation
                            ? LucideIcons.mapPin
                            : LucideIcons.check,
                        size: 18,
                      ),
                label: Text(
                  _habit.hasLocation
                      ? 'Check In at ${_habit.locationName}'
                      : 'Mark as Complete',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primaryAccent,
                  foregroundColor: context.colors.onAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            if (_habit.hasLocation) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.circleAlert,
                      size: 12, color: context.colors.textSecondary),
                  const SizedBox(width: 5),
                  Text(
                    'Must be within ${_habit.locationRadiusM} m of ${_habit.locationName}',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── 5. Calendar Heatmap ─────────────────────────────────────────────────

  Widget _buildHeatmap() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'History'),
        const SizedBox(height: 14),
        _HeatmapGrid(habit: _habit),
        const SizedBox(height: 10),
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Less',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            ...[0.08, 0.25, 0.5, 0.75, 1.0].map((v) => Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: v),
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
            const SizedBox(width: 4),
            Text(
              'More',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── 6. Accountability Section ────────────────────────────────────────────

  Widget _buildAccountabilitySection() {
    final friend = _linkedFriend;
    final habitLink = _habitLink;

    if (friend == null) {
      // No link — show prompt card
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.users,
                size: 20, color: context.colors.textSecondary),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add accountability',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Link this habit to a friend to stay on track.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final friends = ref.read(friendsProvider).valueOrNull?.friends ?? const [];
                if (friends.isNotEmpty) {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => LinkHabitSheet(friend: friends.first, initialUserHabit: _habit),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: context.colors.primaryAccent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.plus, size: 14, color: context.colors.onAccent),
                    SizedBox(width: 4),
                    Text(
                      'Link',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Has a linked friend
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'Accountability'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
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
              // Friend header
              Row(
                children: [
                  AppAvatar(
                    radius: 20,
                    imageUrl: friend.avatarUrl,
                    name: friend.name,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friend.name,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        Text(
                          friend.username,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Toggle
                  Switch(
                    value: habitLink?.isActive ?? true,
                    onChanged: (v) {
                      final link = habitLink;
                      if (link != null) {
                        ref.read(habitLinksProvider.notifier).toggleActive(link.id, v);
                      }
                    },
                    activeThumbColor: Colors.white,
                    activeTrackColor: context.colors.primaryAccent,
                    inactiveThumbColor: context.colors.textSecondary,
                    inactiveTrackColor: context.colors.secondarySurface,
                    trackOutlineColor:
                        WidgetStateProperty.all(Colors.transparent),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              if (habitLink != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.secondarySurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.bellRing,
                          size: 14, color: context.colors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You\'re notified when ${friend.name.split(' ').first} starts ${habitLink.friendHabitName}.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: context.colors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── 7. Schedule & Reminder Section ──────────────────────────────────────

  Widget _buildScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'Schedule'),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: context.colors.primarySurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            children: [
              // Frequency row
              _ScheduleRow(
                icon: LucideIcons.repeat2,
                label: 'Frequency',
                value: _formatFrequency(),
                onTap: _openEdit,
                child: _habit.frequency == FrequencyType.specificDays
                    ? _DayChips(activeDays: _habit.specificDays)
                    : null,
              ),
              Divider(
                  height: 1, thickness: 1, color: context.colors.border),
              // Reminder row
              _ScheduleRow(
                icon: LucideIcons.bell,
                label: 'Reminder',
                value: _habit.reminderEnabled
                    ? _formatTime(_habit.reminderTime!)
                    : 'Off',
                onTap: _openEdit,
              ),
              if (_habit.hasLocation) ...[
                Divider(height: 1, thickness: 1, color: context.colors.border),
                _ScheduleRow(
                  icon: LucideIcons.mapPin,
                  label: 'Check-in location',
                  value: _habit.locationName ?? '',
                  onTap: _openEdit,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── 7b. Run history (accelerometer-tracked runs) ──────────────────────

  Widget _buildRunHistory() {
    final runsAsync = ref.watch(runSessionsProvider(_habit.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(label: 'Tracked Runs'),
        const SizedBox(height: 14),
        AsyncValueView<List<RunSession>>(
          value: runsAsync,
          onRetry: () => ref.invalidate(runSessionsProvider(_habit.id)),
          builder: (runs) {
            if (runs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.colors.primarySurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.colors.border),
                ),
                child: Text(
                  'No runs tracked yet. Tap Start Run below to begin.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: context.colors.textSecondary,
                  ),
                ),
              );
            }
            return Container(
              decoration: BoxDecoration(
                color: context.colors.primarySurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.colors.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < runs.length; i++) ...[
                    if (i > 0)
                      Divider(
                          height: 1,
                          thickness: 1,
                          color: context.colors.border),
                    _RunHistoryRow(run: runs[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ── 8. Actions ──────────────────────────────────────────────────────────

  void _openEdit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddHabitPage(habit: _habit)),
    );
  }

  Future<void> _startRunTracking() async {
    final session = await Navigator.push<RunSession?>(
      context,
      MaterialPageRoute(
        builder: (_) => RunTrackerPage(
          habitId: _habit.id,
          habitName: _habit.name,
        ),
      ),
    );
    if (session != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Run saved — ${session.steps} steps, '
            '${(session.distanceMeters / 1000).toStringAsFixed(2)} km',
          ),
        ),
      );
    }
  }

  Widget _buildActions() {
    return Column(
      children: [
        // Start Run — accelerometer-tracked activity, Fitness habits only
        if (isRunOrWalkHabit(_habit)) ...[
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _startRunTracking,
              icon: Icon(LucideIcons.footprints,
                  size: 18, color: context.colors.onAccent),
              label: Text(
                'Start Run',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.colors.onAccent,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primaryAccent,
                elevation: 0,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Edit
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _openEdit,
            icon: Icon(LucideIcons.pencil,
                size: 16, color: context.colors.textPrimary),
            label: Text(
              'Edit Habit',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: context.colors.border, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              backgroundColor: context.colors.primarySurface,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Delete link
        GestureDetector(
          onTap: _showDeleteDialog,
          child: const Text(
            'Delete Habit',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ── Date helpers ────────────────────────────────────────────────────────

  String _weekdayName(int w) {
    const n = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return n[w - 1];
  }

  String _monthName(int m) {
    const n = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return n[m - 1];
  }
}

// ---------------------------------------------------------------------------
// Stat card
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: context.colors.textSecondary),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: context.colors.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Heatmap grid — 12 weeks × 7 days, grayscale intensity
// ---------------------------------------------------------------------------

class _HeatmapGrid extends StatefulWidget {
  final Habit habit;

  const _HeatmapGrid({required this.habit});

  @override
  State<_HeatmapGrid> createState() => _HeatmapGridState();
}

class _HeatmapGridState extends State<_HeatmapGrid> {
  DateTime? _selectedDay;

  static const _weeks = 13; // columns
  static const _cellSize = 14.0;
  static const _cellGap = 3.0;
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  String _dKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    // Start from _weeks*7 days ago, aligned to Monday of that week
    final daysTotal = _weeks * 7;
    final startRaw = today.subtract(Duration(days: daysTotal - 1));
    // Align to Monday
    final startOffset = (startRaw.weekday - 1) % 7;
    final start = startRaw.subtract(Duration(days: startOffset));

    final completed = widget.habit.completionHistory.toSet();

    return Container(
      decoration: BoxDecoration(
        color: context.colors.primarySurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.colors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day label column + week columns
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day labels (M T W T F S S)
              Column(
                children: List.generate(7, (row) {
                  final showLabel = row.isEven;
                  return SizedBox(
                    width: 12,
                    height: _cellSize + _cellGap,
                    child: Center(
                      child: Text(
                        showLabel ? _dayLabels[row] : '',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 8,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(width: 6),
              // Weeks
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(_weeks + 2, (col) {
                      return Column(
                        children: List.generate(7, (row) {
                          final d =
                              start.add(Duration(days: col * 7 + row));
                          final isCompleted =
                              completed.contains(_dKey(d));
                          final isFuture = d.isAfter(today);
                          final isSelected = _selectedDay != null &&
                              _dKey(_selectedDay!) == _dKey(d);

                          return GestureDetector(
                            onTap: isFuture
                                ? null
                                : () {
                                    setState(() {
                                      _selectedDay =
                                          isSelected ? null : d;
                                    });
                                    if (!isSelected) {
                                      _showDayTooltip(
                                          context, d, isCompleted);
                                    }
                                  },
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 150),
                              width: _cellSize,
                              height: _cellSize,
                              margin: const EdgeInsets.only(
                                right: _cellGap,
                                bottom: _cellGap,
                              ),
                              decoration: BoxDecoration(
                                color: isFuture
                                    ? Colors.transparent
                                    : isCompleted
                                        ? Colors.black
                                            .withValues(alpha: 0.88)
                                        : Colors.black
                                            .withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(3),
                                border: isSelected
                                    ? Border.all(
                                        color: context.colors.textPrimary,
                                        width: 1.5)
                                    : null,
                              ),
                            ),
                          );
                        }),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDayTooltip(
      BuildContext context, DateTime day, bool isCompleted) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final label = '${months[day.month - 1]} ${day.day}, ${day.year}';
    final status = isCompleted ? '✓ Completed' : '✗ Not completed';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, 24 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? context.colors.primaryAccent
                        : context.colors.secondarySurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isCompleted ? LucideIcons.check : LucideIcons.x,
                    color:
                        isCompleted ? context.colors.onAccent : context.colors.textSecondary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    Text(
                      status,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Schedule section sub-widgets
// ---------------------------------------------------------------------------

class _ScheduleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Widget? child;

  const _ScheduleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: context.colors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: context.colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(LucideIcons.chevronRight,
                    size: 14, color: context.colors.textSecondary),
              ],
            ),
            if (child != null) ...[
              const SizedBox(height: 10),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Day of week chips for specific-days frequency display.
class _DayChips extends StatelessWidget {
  final List<int> activeDays;

  const _DayChips({required this.activeDays});

  @override
  Widget build(BuildContext context) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: List.generate(7, (i) {
        final active = activeDays.contains(i);
        return Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: active ? context.colors.primaryAccent : context.colors.secondarySurface,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            letters[i],
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: active ? context.colors.onAccent : context.colors.textSecondary,
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared section title
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  final String label;

  const _SectionTitle({required this.label});

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
// Run history row
// ---------------------------------------------------------------------------

class _RunHistoryRow extends StatelessWidget {
  final RunSession run;

  const _RunHistoryRow({required this.run});

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final km = run.distanceMeters / 1000;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.colors.secondarySurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.footprints,
                size: 16, color: context.colors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${km.toStringAsFixed(2)} km · ${run.steps} steps',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.colors.textPrimary,
                  ),
                ),
                Text(
                  _formatDate(run.startedAt.toLocal()),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatDuration(run.durationSeconds),
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
