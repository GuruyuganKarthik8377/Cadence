import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../theme/app_theme.dart';

/// One row in the "By Habit" breakdown list.
/// Shows emoji + name, an animated completion-rate progress bar, and % value.
class HabitProgressRow extends StatefulWidget {
  final Habit habit;
  /// Completion rate 0–1.
  final double rate;
  final VoidCallback? onTap;

  const HabitProgressRow({
    super.key,
    required this.habit,
    required this.rate,
    this.onTap,
  });

  @override
  State<HabitProgressRow> createState() => _HabitProgressRowState();
}

class _HabitProgressRowState extends State<HabitProgressRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    // Slight stagger so it feels alive without being distracting
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(HabitProgressRow old) {
    super.didUpdateWidget(old);
    if (old.rate != widget.rate) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pct = (widget.rate * 100).round();
    return GestureDetector(
      onTap: widget.onTap,
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
            // Emoji
            Icon(
              habitIconData(widget.habit.iconOrEmoji),
              size: 20,
              color: context.colors.textPrimary,
            ),
            const SizedBox(width: 12),
            // Name + progress bar
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.habit.name,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Animated thin bar
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (_, _) => LayoutBuilder(
                      builder: (ctx, constraints) {
                        final maxW = constraints.maxWidth;
                        return Stack(
                          children: [
                            // Track
                            Container(
                              height: 4,
                              width: maxW,
                              decoration: BoxDecoration(
                                color: context.colors.secondarySurface,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            // Fill
                            Container(
                              height: 4,
                              width: maxW * widget.rate * _animation.value,
                              decoration: BoxDecoration(
                                color: context.colors.primaryAccent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Percentage
            Text(
              '$pct%',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
