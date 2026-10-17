import 'dart:math' as math;

/// Peak-detection pedometer: turns a stream of raw accelerometer magnitudes
/// into step counts. Pure and synchronous — no sensor/platform dependency —
/// so the algorithm itself is unit-testable with synthetic data.
///
/// Approach: smooth the magnitude with a small moving average to reject
/// sensor noise, then count a step each time the smoothed signal rises above
/// a threshold (mean-ish level, calibrated from the walking/running band of
/// human accel magnitude) after having been below it, with a minimum
/// interval enforced so a single foot-strike can't be double-counted from
/// vibration ringing.
class StepDetector {
  StepDetector({
    this.threshold = 11.5, // m/s^2 — above resting gravity (~9.8)
    this.minStepIntervalMs = 250, // ~240 spm ceiling; faster is noise
    int smoothingWindow = 4,
  }) : _windowSize = smoothingWindow;

  final double threshold;
  final int minStepIntervalMs;
  final int _windowSize;

  final List<double> _window = [];
  bool _abovePeak = false;
  int? _lastStepAtMs;
  int _steps = 0;

  int get steps => _steps;

  /// Feed one accelerometer sample (x, y, z in m/s²) and its timestamp.
  /// Returns true if this sample completed a new step.
  bool addSample(double x, double y, double z, int timestampMs) {
    final magnitude = _magnitude(x, y, z);

    _window.add(magnitude);
    if (_window.length > _windowSize) _window.removeAt(0);
    final smoothed = _window.reduce((a, b) => a + b) / _window.length;

    if (smoothed >= threshold) {
      if (!_abovePeak) {
        _abovePeak = true;
        final last = _lastStepAtMs;
        if (last == null || timestampMs - last >= minStepIntervalMs) {
          _lastStepAtMs = timestampMs;
          _steps++;
          return true;
        }
      }
    } else {
      _abovePeak = false;
    }
    return false;
  }

  double _magnitude(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);

  void reset() {
    _window.clear();
    _abovePeak = false;
    _lastStepAtMs = null;
    _steps = 0;
  }
}
