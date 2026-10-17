import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/run_session.dart';
import '../services/step_detector.dart';
import 'auth_provider.dart';
import 'habit_provider.dart';

/// Average adult stride length in metres — used to turn a step count into a
/// distance estimate. No user height/stride profile exists yet, so this is a
/// fixed constant; documented as an approximation, not GPS-grade precision.
const double kAssumedStrideMeters = 0.78;

/// Thrown by [RunTrackerNotifier.finish] when the accelerometer recorded no
/// steps — there is no motion data to verify the activity with.
class NoAccelerometerDataException implements Exception {
  const NoAccelerometerDataException();
}

enum RunStatus { idle, tracking, paused, finished }

class RunTrackerState {
  final RunStatus status;
  final int steps;
  final Duration elapsed;
  final double distanceMeters;

  const RunTrackerState({
    this.status = RunStatus.idle,
    this.steps = 0,
    this.elapsed = Duration.zero,
    this.distanceMeters = 0,
  });

  RunTrackerState copyWith({
    RunStatus? status,
    int? steps,
    Duration? elapsed,
    double? distanceMeters,
  }) {
    return RunTrackerState(
      status: status ?? this.status,
      steps: steps ?? this.steps,
      elapsed: elapsed ?? this.elapsed,
      distanceMeters: distanceMeters ?? this.distanceMeters,
    );
  }
}

final runTrackerProvider =
    NotifierProvider.autoDispose<RunTrackerNotifier, RunTrackerState>(
  RunTrackerNotifier.new,
);

class RunTrackerNotifier extends AutoDisposeNotifier<RunTrackerState> {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _clock;
  StepDetector? _detector;
  DateTime? _startedAt;
  Duration _accumulatedBeforePause = Duration.zero;
  DateTime? _resumedAt;

  @override
  RunTrackerState build() {
    ref.onDispose(() {
      _accelSub?.cancel();
      _clock?.cancel();
      WakelockPlus.disable();
    });
    return const RunTrackerState();
  }

  void start() {
    _detector = StepDetector();
    _startedAt = DateTime.now();
    _resumedAt = DateTime.now();
    _accumulatedBeforePause = Duration.zero;
    state = const RunTrackerState(status: RunStatus.tracking);
    WakelockPlus.enable();

    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen((event) {
      final stepped = _detector!.addSample(
        event.x,
        event.y,
        event.z,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (stepped) {
        final steps = _detector!.steps;
        state = state.copyWith(
          steps: steps,
          distanceMeters: steps * kAssumedStrideMeters,
        );
      }
    });

    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.status != RunStatus.tracking) return;
      final resumed = _resumedAt;
      if (resumed == null) return;
      state = state.copyWith(
        elapsed: _accumulatedBeforePause + DateTime.now().difference(resumed),
      );
    });
  }

  void pause() {
    if (state.status != RunStatus.tracking) return;
    final resumed = _resumedAt;
    if (resumed != null) {
      _accumulatedBeforePause += DateTime.now().difference(resumed);
    }
    _resumedAt = null;
    _accelSub?.pause();
    state = state.copyWith(status: RunStatus.paused);
  }

  void resume() {
    if (state.status != RunStatus.paused) return;
    _resumedAt = DateTime.now();
    _accelSub?.resume();
    state = state.copyWith(status: RunStatus.tracking);
  }

  /// Stops tracking, saves the session, and marks the habit complete for
  /// today. Returns the saved session, or null if nothing was recorded.
  ///
  /// Throws [NoAccelerometerDataException] if zero steps were recorded — the
  /// device's accelerometer never registered motion, so there is nothing to
  /// verify the activity with. Tracking is left running so the user can
  /// simply keep moving and try again rather than losing progress; the
  /// database also independently rejects any completion insert that isn't
  /// backed by a steps>0 run_sessions row, so this can't be bypassed even if
  /// this client-side check were skipped.
  Future<RunSession?> finish(String habitId) async {
    if (_startedAt == null) {
      _teardownSensors();
      state = const RunTrackerState();
      return null;
    }
    if (state.steps == 0) {
      throw const NoAccelerometerDataException();
    }
    _teardownSensors();
    state = state.copyWith(status: RunStatus.finished);

    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('run_sessions')
        .insert({
          'habit_id': habitId,
          'user_id': userId,
          'started_at': _startedAt!.toIso8601String(),
          'duration_seconds': state.elapsed.inSeconds,
          'steps': state.steps,
          'distance_meters': state.distanceMeters,
        })
        .select()
        .single();

    // Log today's completion, but don't fight an already-completed day.
    await ref.read(habitsProvider.notifier).ensureCompletedToday(habitId);

    return RunSession.fromJson(row);
  }

  void discard() {
    _teardownSensors();
    state = const RunTrackerState();
  }

  void _teardownSensors() {
    _accelSub?.cancel();
    _accelSub = null;
    _clock?.cancel();
    _clock = null;
    WakelockPlus.disable();
  }
}
