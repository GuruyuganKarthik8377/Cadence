import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/habit.dart';
import '../models/habit_link.dart';
import '../theme/app_theme.dart';

/// A row showing a friend's anchor habit → user's linked habit with a toggle.
class LinkedHabitRow extends StatefulWidget {
  final HabitLink link;
  final String friendName;
  final ValueChanged<bool> onToggle;
  /// Sends a poke about the friend's side of this pair. Null hides the button.
  final Future<void> Function()? onNudge;

  const LinkedHabitRow({
    super.key,
    required this.link,
    required this.friendName,
    required this.onToggle,
    this.onNudge,
  });

  @override
  State<LinkedHabitRow> createState() => _LinkedHabitRowState();
}

class _LinkedHabitRowState extends State<LinkedHabitRow> {
  late bool _isActive;
  bool _nudging = false;

  @override
  void initState() {
    super.initState();
    _isActive = widget.link.isActive;
  }

  Future<void> _nudge() async {
    setState(() => _nudging = true);
    try {
      await widget.onNudge!();
      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nudged ${widget.friendName}.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _nudging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          // Habit pair row
          Row(
            children: [
              // Friend's habit
              Expanded(
                child: _HabitChip(
                  icon: widget.link.friendHabitIcon,
                  name: widget.link.friendHabitName,
                  label: widget.friendName,
                  dimmed: !_isActive,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  LucideIcons.arrowRight,
                  size: 16,
                  color: _isActive
                      ? context.colors.textPrimary
                      : context.colors.textSecondary,
                ),
              ),
              // User's habit
              Expanded(
                child: _HabitChip(
                  icon: widget.link.userHabitIcon,
                  name: widget.link.userHabitName,
                  label: 'You',
                  dimmed: !_isActive,
                ),
              ),
            ],
          ),
          if (widget.link.coStreak >= 2) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.colors.primaryAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.flame, size: 13, color: context.colors.primaryAccent),
                  const SizedBox(width: 5),
                  Text(
                    '${widget.link.coStreak}-day streak together',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.colors.primaryAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Toggle row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _isActive ? 'Anchor active' : 'Anchor paused',
                  key: ValueKey(_isActive),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                      ),
                ),
              ),
              const Spacer(),
              if (widget.onNudge != null && _isActive)
                TextButton.icon(
                  onPressed: _nudging ? null : _nudge,
                  icon: _nudging
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(LucideIcons.handHelping,
                          size: 14, color: context.colors.primaryAccent),
                  label: Text(
                    'Nudge',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.colors.primaryAccent,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              Switch(
                value: _isActive,
                onChanged: (val) {
                  setState(() => _isActive = val);
                  widget.onToggle(val);
                },
                activeThumbColor: context.colors.primaryAccent,
                activeTrackColor: context.colors.primaryAccent.withValues(alpha: 0.3),
                inactiveThumbColor: context.colors.textSecondary,
                inactiveTrackColor: context.colors.secondarySurface,
                trackOutlineColor:
                    WidgetStateProperty.all(Colors.transparent),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HabitChip extends StatelessWidget {
  final String icon;
  final String name;
  final String label;
  final bool dimmed;

  const _HabitChip({
    required this.icon,
    required this.name,
    required this.label,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: dimmed ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.secondarySurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(habitIconData(icon), size: 18, color: context.colors.textPrimary),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
