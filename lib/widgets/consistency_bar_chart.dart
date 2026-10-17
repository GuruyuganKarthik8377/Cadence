import 'package:flutter/material.dart';
import '../services/insights_service.dart';
import '../theme/app_theme.dart';

/// Animated vertical bar chart for consistency data.
///
/// Bars grow from the bottom using a scale animation on load and whenever
/// [bars] changes (e.g. range switched).
///
/// Layout: bars are evenly distributed across the full available width using
/// [Expanded] flex children inside a Row. Each bar column has a fixed-width
/// bar track centered within its Expanded slot, with consistent inter-bar
/// spacing achieved via symmetric padding on the outer Row.
class ConsistencyBarChart extends StatefulWidget {
  final List<BarPoint> bars;

  const ConsistencyBarChart({
    super.key,
    required this.bars,
  });

  @override
  State<ConsistencyBarChart> createState() => _ConsistencyBarChartState();
}

class _ConsistencyBarChartState extends State<ConsistencyBarChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 550),
      vsync: this,
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(ConsistencyBarChart old) {
    super.didUpdateWidget(old);
    // Replay animation when data changes (range switched)
    if (old.bars != widget.bars) {
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bars.isEmpty) return const SizedBox.shrink();

    const double barMaxHeight = 100.0;
    // Bar track width — narrower for many bars, wider for few.
    // Clamped so it never gets too wide (Year=12 bars) or too thin (Week=7).
    final int count = widget.bars.length;
    final double barWidth = count >= 10
        ? 10.0
        : count >= 7
            ? 12.0
            : 16.0;

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) {
        return Row(
          // Use spaceEvenly so every bar gets an identical slot regardless
          // of count — works correctly for 2, 4, 5, 7, or 12 bars.
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: widget.bars.map((bar) {
            final double animatedHeight =
                (bar.value.clamp(0.0, 1.0) * barMaxHeight * _anim.value)
                    .clamp(0.0, barMaxHeight);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Bar track + fill ──────────────────────────────────────
                SizedBox(
                  width: barWidth,
                  height: barMaxHeight,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      // Track (full height, light gray)
                      Container(
                        width: barWidth,
                        height: barMaxHeight,
                        decoration: BoxDecoration(
                          color: context.colors.secondarySurface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      // Animated fill
                      if (animatedHeight > 0)
                        Container(
                          width: barWidth,
                          height: animatedHeight,
                          decoration: BoxDecoration(
                            color: bar.isHighlighted
                                ? context.colors.primaryAccent
                                : context.colors.textSecondary
                                    .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // ── X-axis label ─────────────────────────────────────────
                Text(
                  bar.label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10,
                    fontWeight: bar.isHighlighted
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: bar.isHighlighted
                        ? context.colors.primaryAccent
                        : context.colors.textSecondary,
                  ),
                ),
              ],
            );
          }).toList(),
        );
      },
    );
  }
}
