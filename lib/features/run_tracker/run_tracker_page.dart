import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../providers/run_session_provider.dart';
import '../../providers/run_tracker_provider.dart';
import '../../theme/app_theme.dart';

/// Live accelerometer-based run tracker for a single habit. Counts steps via
/// peak-detection on the device accelerometer (see StepDetector) — no GPS,
/// so distance/pace are stride-length estimates, not exact.
class RunTrackerPage extends ConsumerStatefulWidget {
  final String habitId;
  final String habitName;

  const RunTrackerPage({
    super.key,
    required this.habitId,
    required this.habitName,
  });

  @override
  ConsumerState<RunTrackerPage> createState() => _RunTrackerPageState();
}

class _RunTrackerPageState extends ConsumerState<RunTrackerPage> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(runTrackerProvider.notifier).start();
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  String _formatPace(double? minPerKm) {
    if (minPerKm == null || !minPerKm.isFinite) return '—';
    final mins = minPerKm.floor();
    final secs = ((minPerKm - mins) * 60).round();
    return "$mins'${secs.toString().padLeft(2, '0')}\"/km";
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final session =
          await ref.read(runTrackerProvider.notifier).finish(widget.habitId);
      ref.invalidate(runSessionsProvider(widget.habitId));
      if (mounted) {
        Navigator.pop(context, session);
      }
    } on NoAccelerometerDataException {
      // Tracking is still running (finish() didn't tear it down) — let the
      // user keep moving and try again instead of losing their progress.
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No motion detected yet. Keep moving with your phone, '
              'then tap Finish again.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save your run. Try again.")),
        );
      }
    }
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Discard this run?',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary)),
        content: Text(
          'Your steps and time so far will be lost.',
          style: TextStyle(
              fontFamily: 'Inter', color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep Going',
                style: TextStyle(color: context.colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(runTrackerProvider.notifier).discard();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(runTrackerProvider);
    final isTracking = run.status == RunStatus.tracking;
    final isPaused = run.status == RunStatus.paused;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _discard();
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          backgroundColor: context.colors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(LucideIcons.x, color: context.colors.primaryAccent),
            onPressed: _discard,
          ),
          title: Text(
            widget.habitName,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                Text(
                  _formatDuration(run.elapsed),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isPaused ? 'Paused' : 'Tracking via accelerometer',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  children: [
                    _MetricTile(
                      icon: LucideIcons.footprints,
                      value: '${run.steps}',
                      label: 'Steps',
                    ),
                    const SizedBox(width: 12),
                    _MetricTile(
                      icon: LucideIcons.route,
                      value: _formatDistance(run.distanceMeters),
                      label: 'Distance',
                    ),
                    const SizedBox(width: 12),
                    _MetricTile(
                      icon: LucideIcons.gauge,
                      value: _formatPace(_currentPace(run)),
                      label: 'Pace',
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'Distance is estimated from step count, not GPS.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => isTracking
                                  ? ref
                                      .read(runTrackerProvider.notifier)
                                      .pause()
                                  : ref
                                      .read(runTrackerProvider.notifier)
                                      .resume(),
                          icon: Icon(
                            isTracking ? LucideIcons.pause : LucideIcons.play,
                            size: 18,
                            color: context.colors.textPrimary,
                          ),
                          label: Text(
                            isTracking ? 'Pause' : 'Resume',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              color: context.colors.textPrimary,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: context.colors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _finish,
                          icon: _saving
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.colors.onAccent,
                                  ),
                                )
                              : Icon(LucideIcons.check,
                                  size: 18, color: context.colors.onAccent),
                          label: Text(
                            'Finish',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              color: context.colors.onAccent,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.primaryAccent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double? _currentPace(RunTrackerState run) {
    if (run.distanceMeters <= 0 || run.elapsed.inSeconds == 0) return null;
    final km = run.distanceMeters / 1000;
    final minutes = run.elapsed.inSeconds / 60;
    return minutes / km;
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MetricTile(
      {required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.colors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: context.colors.textSecondary),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
