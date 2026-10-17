import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProgressChart extends StatelessWidget {
  final List<double> weeklyData; // Values between 0.0 and 1.0

  const ProgressChart({
    super.key,
    required this.weeklyData,
  });

  @override
  Widget build(BuildContext context) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.primarySurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly Progress',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (index) {
              final value = index < weeklyData.length ? weeklyData[index] : 0.0;
              final isToday = index == 3; // Mocking today as Thursday

              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 12,
                    height: 100,
                    decoration: BoxDecoration(
                      color: context.colors.secondarySurface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: value,
                      child: Container(
                        width: 12,
                        decoration: BoxDecoration(
                          color: isToday ? context.colors.primaryAccent : context.colors.textSecondary.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    days[index],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isToday ? context.colors.primaryAccent : context.colors.textSecondary,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
