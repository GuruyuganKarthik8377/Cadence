import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/profile.dart';
import '../../providers/friend_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/friend_request_card.dart';

class AddFriendPage extends ConsumerStatefulWidget {
  const AddFriendPage({super.key});

  @override
  ConsumerState<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends ConsumerState<AddFriendPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Profile> _results = [];
  bool _isSearching = false;
  // Tracks which IDs have had a request sent in this session
  final Set<String> _sentIds = {};
  final Map<String, Profile> _sentProfiles = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged() async {
    final query = _searchController.text.trim();
    setState(() => _searchQuery = query);
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isSearching = true);
    final results = await ref.read(friendsProvider.notifier).searchUsers(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _isSearching = false;
    });
  }

  List<Profile> get _recentlySent => _sentProfiles.values.toList();

  Future<void> _sendRequest(Profile profile) async {
    setState(() {
      _sentIds.add(profile.id);
      _sentProfiles[profile.id] = profile;
    });
    await ref.read(friendsProvider.notifier).sendRequest(profile.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Request sent to ${profile.displayName}.',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        backgroundColor: context.colors.primaryAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final recentlySent = _recentlySent;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.chevronLeft,
              color: context.colors.primaryAccent),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Add Friend',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search bar
            _buildSearchBar(),
            const SizedBox(height: 28),

            // Search results
            if (_searchQuery.isNotEmpty) ...[
              Text(
                _isSearching
                    ? 'Searching...'
                    : results.isEmpty
                        ? 'No users found.'
                        : 'Search Results',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 14),
              if (results.isNotEmpty)
                ...results.map((p) => _UserResultRow(
                      profile: p,
                      isSent: _sentIds.contains(p.id),
                      onSend: () => _sendRequest(p),
                    )),
            ] else ...[
              // Hint text
              Text(
                'Search by username or email to find friends.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],

            // Recently sent
            if (recentlySent.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text(
                'Recently Sent',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 14),
              ...recentlySent.map((p) => _UserResultRow(
                    profile: p,
                    isSent: true,
                    onSend: () {},
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: context.colors.primarySurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Icon(LucideIcons.search,
              color: context.colors.textSecondary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: context.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search by username or email',
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  color: context.colors.textSecondary,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () => _searchController.clear(),
              child: Padding(
                padding: EdgeInsets.only(right: 14),
                child: Icon(LucideIcons.x,
                    size: 16, color: context.colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserResultRow extends StatelessWidget {
  final Profile profile;
  final bool isSent;
  final VoidCallback onSend;

  const _UserResultRow({
    required this.profile,
    required this.isSent,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      child: Row(
        children: [
          FriendAvatar(url: profile.avatarUrl ?? '', radius: 22, name: profile.displayName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '@${profile.username}',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SendButton(isSent: isSent, onTap: onSend),
        ],
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final bool isSent;
  final VoidCallback onTap;
  const _SendButton({required this.isSent, required this.onTap});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.isSent ? null : (_) => setState(() => _pressed = true),
      onTapUp: widget.isSent
          ? null
          : (_) {
              setState(() => _pressed = false);
              widget.onTap();
            },
      onTapCancel: widget.isSent
          ? null
          : () => setState(() => _pressed = false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSent
                ? context.colors.secondarySurface
                : context.colors.primaryAccent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            widget.isSent ? 'Pending' : 'Send Request',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.isSent ? context.colors.textSecondary : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
