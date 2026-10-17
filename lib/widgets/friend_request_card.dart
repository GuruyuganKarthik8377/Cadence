import 'package:flutter/material.dart';
import '../models/friend.dart';
import '../theme/app_theme.dart';
import 'app_avatar.dart';

/// A compact pending-request card used in the horizontal scroll row.
class FriendRequestCard extends StatelessWidget {
  final Friend friend;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const FriendRequestCard({
    super.key,
    required this.friend,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar
          _Avatar(url: friend.avatarUrl, radius: 28, name: friend.name),
          const SizedBox(height: 10),
          // Name
          Text(
            friend.name,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            friend.username,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.textSecondary,
                  fontSize: 11,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          // Accept
          _ActionButton(
            label: 'Accept',
            filled: true,
            onTap: onAccept,
          ),
          const SizedBox(height: 6),
          // Decline
          _ActionButton(
            label: 'Decline',
            filled: false,
            onTap: onDecline,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.filled ? context.colors.primaryAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: widget.filled
                ? null
                : Border.all(color: context.colors.border, width: 1),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.filled ? Colors.white : context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared circular avatar widget used across friend screens.
/// Delegates to AppAvatar for graceful loading/error fallbacks.
class _Avatar extends StatelessWidget {
  final String url;
  final double radius;
  final String name;

  const _Avatar({required this.url, this.radius = 24, this.name = ''});

  @override
  Widget build(BuildContext context) {
    return AppAvatar(name: name, imageUrl: url, radius: radius);
  }
}

// Export the _Avatar so friend_card.dart can use it too.
class FriendAvatar extends StatelessWidget {
  final String url;
  final double radius;
  final String name;

  const FriendAvatar(
      {super.key, required this.url, this.radius = 24, this.name = ''});

  @override
  Widget build(BuildContext context) =>
      _Avatar(url: url, radius: radius, name: name);
}
