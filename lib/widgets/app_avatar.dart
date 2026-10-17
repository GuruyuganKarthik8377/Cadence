import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

/// Circular avatar that renders the user's initials while the image loads
/// and whenever the URL is missing or fails — never a blank circle or a
/// broken-image exception.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 24,
  });

  final String name;
  final String? imageUrl;
  final double radius;

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: context.colors.secondarySurface,
      child: name.trim().isEmpty
          ? Icon(LucideIcons.user,
              size: radius, color: context.colors.textSecondary)
          : Text(
              _initials,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: radius * 0.7,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
    );

    final url = imageUrl;
    if (url == null || url.isEmpty) return fallback;

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback,
        ),
      ),
    );
  }
}
