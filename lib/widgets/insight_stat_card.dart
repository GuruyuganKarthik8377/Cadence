import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

/// Compact stat card — icon, large value, small label.
/// Used in the Insights overview row.
class InsightStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  /// Change versus the previous period, in percentage points. Rendered as a
  /// small ▲/▼ badge beside the icon. Null (or 0) hides the badge.
  final int? delta;

  const InsightStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.delta,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: context.colors.textSecondary),
                if (delta != null && delta != 0) ...[
                  const Spacer(),
                  _DeltaBadge(delta: delta!),
                ],
              ],
            ),
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

/// Small ▲/▼ pill showing percentage-point change against the last period.
class _DeltaBadge extends StatelessWidget {
  final int delta;

  const _DeltaBadge({required this.delta});

  @override
  Widget build(BuildContext context) {
    final up = delta > 0;
    // Green/red read as gain/loss in both themes; the surrounding card
    // supplies the light or dark backdrop.
    final color = up ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? LucideIcons.arrowUp : LucideIcons.arrowDown,
              size: 9, color: color),
          const SizedBox(width: 1),
          Text(
            '${delta.abs()}',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
