import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

/// Standard rendering for provider-backed data: data builder, compact
/// inline error card with retry, and a loading placeholder. Use this on
/// every screen-level provider read instead of `valueOrNull ?? []` so
/// failures surface instead of masquerading as empty states.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  /// Typically `() => ref.invalidate(theProvider)`.
  final VoidCallback onRetry;

  /// Optional custom loading widget (e.g. a skeleton).
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () =>
          loading ??
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      error: (_, _) => AsyncErrorCard(onRetry: onRetry),
    );
  }
}

/// Compact inline error state with a retry action.
class AsyncErrorCard extends StatelessWidget {
  const AsyncErrorCard({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.primarySurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.wifiOff,
              size: 20, color: context.colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message ?? "Couldn't load. Check your connection.",
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: context.colors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
            ),
            child: const Text(
              'Retry',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
