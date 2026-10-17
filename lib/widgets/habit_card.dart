import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

class HabitCard extends StatelessWidget {
  final String name;
  final String duration;
  final IconData icon;
  final bool isCompleted;
  final String imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onToggleComplete;

  const HabitCard({
    super.key,
    required this.name,
    required this.duration,
    required this.icon,
    this.isCompleted = false,
    required this.imageUrl,
    this.onTap,
    this.onToggleComplete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 280,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: context.colors.primarySurface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: context.colors.border,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Section (Image and Completion Indicator)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      imageUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 64,
                          height: 64,
                          color: context.colors.secondarySurface,
                          child: Icon(icon, color: context.colors.textSecondary),
                        );
                      },
                    ),
                  ),
                  GestureDetector(
                    onTap: onToggleComplete,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? context.colors.primaryAccent
                            : context.colors.secondarySurface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCompleted
                            ? LucideIcons.check
                            : LucideIcons.chevronRight,
                        color: isCompleted
                            ? context.colors.primarySurface
                            : context.colors.textPrimary,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Title and details
              Text(
                name,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                duration,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
