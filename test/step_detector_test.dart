import 'package:flutter_test/flutter_test.dart';
import 'package:cadence/services/step_detector.dart';

/// Synthetic accelerometer feed: alternates between resting gravity (~9.8)
/// and a footstrike peak, at [stepIntervalMs] apart, spanning [steps] steps.
List<(double, double, double, int)> _syntheticGait({
  required int steps,
  int stepIntervalMs = 500,
  double peakMagnitude = 15.0,
}) {
  final samples = <(double, double, double, int)>[];
  const sampleIntervalMs = 20; // ~50Hz, matches gameInterval
  var t = 0;
  for (var s = 0; s < steps; s++) {
    final stepStart = t;
    while (t < stepStart + stepIntervalMs) {
      final phase = (t - stepStart) / stepIntervalMs;
      // Rises to a peak mid-step, falls back to resting gravity.
      final magnitude = 9.8 + (peakMagnitude - 9.8) * _bump(phase);
      // Distribute magnitude across axes arbitrarily; only magnitude matters.
      samples.add((magnitude, 0.0, 0.0, t));
      t += sampleIntervalMs;
    }
  }
  return samples;
}

double _bump(double phase) {
  // Peaks at phase=0.3, near-zero elsewhere — one clean pulse per step.
  const center = 0.3;
  const width = 0.08;
  final d = (phase - center).abs();
  return d < width ? 1 - (d / width) : 0;
}

void main() {
  group('StepDetector', () {
    test('counts a clean walking gait accurately', () {
      final detector = StepDetector();
      final gait = _syntheticGait(steps: 20);
      for (final (x, y, z, t) in gait) {
        detector.addSample(x, y, z, t);
      }
      // Peak detection on synthetic data should be exact.
      expect(detector.steps, 20);
    });

    test('does not count steps while resting (no motion)', () {
      final detector = StepDetector();
      for (var t = 0; t < 5000; t += 20) {
        detector.addSample(0, 0, 9.81, t); // stationary, holding the phone
      }
      expect(detector.steps, 0);
    });

    test('rejects rapid double-triggers within the minimum step interval',
        () {
      final detector = StepDetector(minStepIntervalMs: 250);
      // Two peaks 50ms apart — physically impossible footstrikes, should
      // collapse to one step, not two.
      detector.addSample(9.8, 0, 0, 0);
      detector.addSample(15.0, 0, 0, 20);
      detector.addSample(15.0, 0, 0, 40);
      detector.addSample(9.8, 0, 0, 60);
      detector.addSample(15.0, 0, 0, 80); // re-trigger too soon
      expect(detector.steps, 1);
    });

    test('counts a second step once enough time has passed', () {
      final detector = StepDetector(minStepIntervalMs: 250);
      // First peak.
      detector.addSample(9.8, 0, 0, 0);
      detector.addSample(15.0, 0, 0, 20);
      // Several resting samples — enough for the moving-average window
      // (default size 4) to fall back below threshold, matching a real
      // ~20ms-interval sensor feed between footstrikes.
      for (var t = 40; t <= 360; t += 20) {
        detector.addSample(9.8, 0, 0, t);
      }
      // Second peak (spans 2 samples, like the first — a footstrike's
      // accelerometer spike lasts longer than one 20ms sample), >250ms
      // after the first.
      detector.addSample(15.0, 0, 0, 400);
      detector.addSample(15.0, 0, 0, 420);
      expect(detector.steps, 2);
    });

    test('reset clears step count and internal state', () {
      final detector = StepDetector();
      for (final (x, y, z, t) in _syntheticGait(steps: 5)) {
        detector.addSample(x, y, z, t);
      }
      expect(detector.steps, greaterThan(0));
      detector.reset();
      expect(detector.steps, 0);
    });

    test('addSample returns true only on the sample that completes a step',
        () {
      final detector = StepDetector(minStepIntervalMs: 250);
      expect(detector.addSample(9.8, 0, 0, 0), isFalse);
      expect(detector.addSample(15.0, 0, 0, 20), isTrue);
      expect(detector.addSample(15.0, 0, 0, 40), isFalse); // still above
      expect(detector.addSample(9.8, 0, 0, 60), isFalse); // falling edge
    });
  });
}
