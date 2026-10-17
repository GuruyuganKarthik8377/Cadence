import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/friend.dart';
import '../../providers/activity_feed_provider.dart';
import '../../providers/friend_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/async_value_view.dart';
import '../../widgets/friend_request_card.dart';
import '../../widgets/friend_card.dart';
import '../../widgets/activity_feed_item.dart';
import 'add_friend_page.dart';
import 'friend_detail_page.dart';

class FriendsPage extends ConsumerStatefulWidget {
  /// When true the screen is embedded inside the bottom nav stack,
  /// so the back button and Scaffold are suppressed.
  final bool isTabMode;

  const FriendsPage({super.key, this.isTabMode = false});

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Friend> _filteredFriends(List<Friend> friends) {
    if (_searchQuery.isEmpty) return friends;
    return friends
        .where((f) =>
            f.name.toLowerCase().contains(_searchQuery) ||
            f.username.toLowerCase().contains(_searchQuery))
        .toList();
  }

  Future<void> _acceptRequest(Friend friend) async {
    await ref.read(friendsProvider.notifier).acceptRequest(friend.friendshipId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'You and ${friend.name} are now connected.',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        backgroundColor: context.colors.primaryAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  Future<void> _declineRequest(Friend friend) async {
    await ref.read(friendsProvider.notifier).declineRequest(friend.friendshipId);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final friendsAsync = ref.watch(friendsProvider);
    final friendsState = friendsAsync.valueOrNull ?? const FriendsState();
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.isTabMode
            ? null
            : IconButton(
                icon: Icon(LucideIcons.chevronLeft,
                    color: context.colors.primaryAccent),
                onPressed: () => Navigator.pop(context),
              ),
        title: Text(
          'Friends',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(LucideIcons.userPlus,
                color: context.colors.primaryAccent, size: 22),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddFriendPage()),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: TabBar(
            controller: _tabController,
            indicatorColor: context.colors.primaryAccent,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: context.colors.textPrimary,
            unselectedLabelColor: context.colors.textSecondary,
            labelStyle: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            tabs: const [
              Tab(text: 'Friends'),
              Tab(text: 'Activity'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          friendsAsync.hasError
              ? Center(
                  child: AsyncErrorCard(
                      onRetry: () => ref.invalidate(friendsProvider)))
              : friendsAsync.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildFriendsTab(bottomPadding, friendsState),
          _buildActivityTab(bottomPadding),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding + 90),
        child: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddFriendPage()),
            );
          },
          backgroundColor: context.colors.primaryAccent,
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Icon(LucideIcons.userPlus,
              color: context.colors.onAccent, size: 22),
        ),
      ),
    );
  }

  Widget _buildFriendsTab(double bottomPadding, FriendsState friendsState) {
    final filtered = _filteredFriends(friendsState.friends);
    final pendingRequests = friendsState.pendingRequests;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
          left: 24, right: 24, top: 20, bottom: 120 + bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          _buildSearchBar(),
          const SizedBox(height: 28),

          // Pending requests section
          if (pendingRequests.isNotEmpty) ...[
            _SectionLabel(
              label: 'Pending Requests',
              count: pendingRequests.length,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: pendingRequests.length,
                itemBuilder: (context, index) {
                  final req = pendingRequests[index];
                  return FriendRequestCard(
                    friend: req,
                    onAccept: () => _acceptRequest(req),
                    onDecline: () => _declineRequest(req),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
          ],

          // Friends list
          _SectionLabel(label: 'Your Friends', count: filtered.length),
          const SizedBox(height: 14),

          if (filtered.isEmpty) _buildEmptyState() else ...[
            ...filtered.map((friend) => FriendCard(
                  friend: friend,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FriendDetailPage(friend: friend),
                      ),
                    );
                  },
                )),
          ],
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  Widget _buildActivityTab(double bottomPadding) {
    final entriesAsync = ref.watch(activityFeedProvider);
    if (entriesAsync.hasError) {
      return Center(
        child: AsyncErrorCard(
            onRetry: () => ref.invalidate(activityFeedProvider)),
      );
    }
    if (entriesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final entries = entriesAsync.valueOrNull ?? const [];
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
          left: 24, right: 24, top: 20, bottom: 120 + bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Activity',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Updates from people you\'re accountable with.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No recent activity yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            ...entries.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final isLast = i == entries.length - 1;
              return Column(
                children: [
                  ActivityFeedItem(
                    avatarUrl: item.friendAvatarUrl,
                    friendName: item.friendName,
                    habitName: item.habitName,
                    timeAgo: _timeAgo(item.completedAt),
                    completionId: item.completionId,
                  ),
                  if (!isLast)
                    Divider(
                      color: context.colors.border,
                      height: 1,
                      thickness: 1,
                    ),
                ],
              );
            }),
        ],
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
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: context.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search friends',
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
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.colors.secondarySurface,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.users,
                  size: 32, color: context.colors.textSecondary),
            ),
            const SizedBox(height: 20),
            Text(
              'Connect with friends\nto stay accountable together.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: context.colors.textSecondary,
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddFriendPage()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: context.colors.primaryAccent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Add Friend',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.onAccent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final int count;

  const _SectionLabel({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: context.colors.secondarySurface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
