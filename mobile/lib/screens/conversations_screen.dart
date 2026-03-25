import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../providers/auth_provider.dart';
import '../config/api_config.dart';
import 'chat_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _conversations = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 20;

  // Debounce iÃ§in
  static const double _loadMoreThreshold = 280;
  static final DateFormat _timeFormatter = DateFormat('HH:mm');
  static final DateFormat _dateFormatter = DateFormat('dd.MM.yy');

  Timer? _refreshTimer;
  bool _isRefreshingFirstPage = false;
  bool _queuedRefresh = false;
  final Set<String> _expandedUserIds = <String>{};

  late final Function(Map<String, dynamic>) _messageReceivedListener;
  late final Function(Map<String, dynamic>) _notificationListener;

  @override
  void initState() {
    super.initState();

    _messageReceivedListener = _onMessageReceived;
    _notificationListener = _onNotification;

    _loadConversations();
    _setupSocketListener();
    _updateUnreadCount();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    final socketService = SocketService();
    socketService.removeMessageReceivedListener(_messageReceivedListener);
    socketService.removeNotificationListener(_notificationListener);
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    final pos = _scrollController.position;
    if (pos.extentAfter <= _loadMoreThreshold) {
      _loadMoreConversations();
    }
  }

  Future<void> _updateUnreadCount() async {
    try {
      final socketService = SocketService();
      final newCount = await _apiService.getUnreadMessageCount();
      socketService.unreadCount = newCount;
      socketService.notifyUnreadCountListeners();
    } catch (_) {}
  }

  void _setupSocketListener() {
    final socketService = SocketService();
    socketService.addMessageReceivedListener(_messageReceivedListener);
    socketService.addNotificationListener(_notificationListener);
  }

  void _onMessageReceived(Map<String, dynamic> data) {
    _scheduleRefreshFirstPage();
  }

  void _onNotification(Map<String, dynamic> data) {
    _scheduleRefreshFirstPage();
  }

  void _scheduleRefreshFirstPage() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 250), _refreshFirstPage);
  }

  /// Scroll'u bozmadan sadece listeyi gÃ¼nceller
  Future<void> _refreshFirstPage() async {
    if (!mounted) return;
    if (_isRefreshingFirstPage) {
      _queuedRefresh = true;
      return;
    }
    _isRefreshingFirstPage = true;

    try {
      await _apiService.markMessagesAsDelivered();
      final result = await _apiService.getConversations(page: 1, limit: _pageSize);
      if (!mounted) return;
      final conversations = result['conversations'] as List<dynamic>;
      setState(() {
        _conversations = conversations;
        _hasMore = result['hasMore'] as bool? ?? false;
        _currentPage = 1;
      });
      _warmUpConversationAvatars(conversations);
    } catch (_) {
      // no-op
    } finally {
      _isRefreshingFirstPage = false;
      if (_queuedRefresh) {
        _queuedRefresh = false;
        _scheduleRefreshFirstPage();
      }
    }
  }

  Future<void> _loadConversations() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _conversations = [];
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      await _apiService.markMessagesAsDelivered();
      final result = await _apiService.getConversations(page: 1, limit: _pageSize);

      if (!mounted) return;
      final conversations = result['conversations'] as List<dynamic>;
      setState(() {
        _conversations = conversations;
        _hasMore = result['hasMore'] as bool? ?? false;
        _isLoading = false;
      });
      _warmUpConversationAvatars(conversations);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreConversations() async {
    if (_isLoadingMore || !_hasMore) return;

    if (mounted) setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final result = await _apiService.getConversations(page: nextPage, limit: _pageSize);

      if (!mounted) return;
      final incoming = result['conversations'] as List<dynamic>;
      setState(() {
        _conversations.addAll(incoming);
        _currentPage = nextPage;
        _hasMore = result['hasMore'] as bool? ?? false;
        _isLoadingMore = false;
      });
      _warmUpConversationAvatars(incoming);
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _warmUpConversationAvatars(List<dynamic> items) {
    if (!mounted || items.isEmpty) return;

    final urls = <String>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final sender = raw['sender'];
      final receiver = raw['receiver'];
      if (sender is! Map || receiver is! Map) continue;

      final avatarPaths = [
        (sender['avatar'] ?? '').toString().trim(),
        (receiver['avatar'] ?? '').toString().trim(),
      ];
      for (final avatarPath in avatarPaths) {
        if (avatarPath.isEmpty) continue;
        final url = '${ApiConfig.uploadsUrl}/$avatarPath';
        if (!urls.contains(url)) {
          urls.add(url);
        }
        if (urls.length >= 8) break;
      }
      if (urls.length >= 8) break;
    }

    for (final url in urls) {
      precacheImage(
        ResizeImage(
          CachedNetworkImageProvider(url, cacheKey: url),
          width: 96,
          height: 96,
        ),
        context,
      );
    }
  }

  String _formatDate(String dateStr) {
    final date = DateTime.parse(dateStr).toLocal();
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return _timeFormatter.format(date);
    } else if (difference.inDays < 7) {
      return '${difference.inDays}g önce';
    } else {
      return _dateFormatter.format(date);
    }
  }

  DateTime _safeParseDate(String? dateStr) {
    if (dateStr == null) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      return DateTime.parse(dateStr).toLocal();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  int _threadUnreadCount(Map<String, dynamic> thread, String? currentUserId) {
    final senderId = (thread['sender']?['_id'] ?? thread['sender']?['id'])?.toString();
    final isIncoming = senderId != null && senderId != currentUserId;
    if (!isIncoming) return 0;

    final unreadCountRaw = thread['unreadCount'];
    if (unreadCountRaw is int) return unreadCountRaw;
    if (unreadCountRaw is num) return unreadCountRaw.toInt();
    return 0;
  }

  int _groupUnreadCount(_ConversationGroup group, String? currentUserId) {
    var total = 0;
    for (final thread in group.threads) {
      total += _threadUnreadCount(thread, currentUserId);
    }
    return total;
  }

  List<_ConversationGroup> _buildConversationGroups(String? currentUserId) {
    final grouped = <String, _ConversationGroup>{};

    for (final raw in _conversations) {
      if (raw is! Map<String, dynamic>) continue;
      final sender = raw['sender'];
      final receiver = raw['receiver'];
      if (sender is! Map || receiver is! Map) continue;

      final senderId = (sender['_id'] ?? sender['id'])?.toString() ?? '';
      if (senderId.isEmpty) continue;
      final isMeSender = senderId == currentUserId;
      final otherUser = (isMeSender ? receiver : sender).cast<String, dynamic>();
      final otherUserId = (otherUser['_id'] ?? otherUser['id'])?.toString() ?? '';
      if (otherUserId.isEmpty) continue;

      final existing = grouped[otherUserId];
      if (existing == null) {
        grouped[otherUserId] = _ConversationGroup(
          otherUser: otherUser,
          threads: [raw],
        );
      } else {
        existing.threads.add(raw);
      }
    }

    final groups = grouped.values.toList();
    for (final group in groups) {
      group.threads.sort((a, b) {
        final aDate = _safeParseDate(a['createdAt']?.toString());
        final bDate = _safeParseDate(b['createdAt']?.toString());
        return bDate.compareTo(aDate);
      });
    }
    groups.sort((a, b) {
      final aDate = a.threads.isNotEmpty
          ? _safeParseDate(a.threads.first['createdAt']?.toString())
          : DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.threads.isNotEmpty
          ? _safeParseDate(b.threads.first['createdAt']?.toString())
          : DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return groups;
  }

  void _openChatFromMessage(Map<String, dynamic> message, String? currentUserId) {
    final listing = message['listing'];
    if (listing is! Map) return;

    final sender = message['sender'];
    final receiver = message['receiver'];
    if (sender is! Map || receiver is! Map) return;

    final senderId = (sender['_id'] ?? sender['id'])?.toString() ?? '';
    final isMeSender = senderId == currentUserId;
    final otherUser = (isMeSender ? receiver : sender).cast<String, dynamic>();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          listingId: (listing['_id'] ?? '').toString(),
          listingTitle: (listing['title'] ?? '').toString(),
          receiverId: (otherUser['_id'] ?? otherUser['id']).toString(),
          receiverName: (otherUser['name'] ?? 'Kullanıcı').toString(),
          receiverAvatar: (otherUser['avatar'] ?? '').toString(),
        ),
      ),
    ).then((_) => _refreshFirstPage());
  }

  Widget _buildConversationGroupItem(
    _ConversationGroup group,
    String? currentUserId,
  ) {
    final otherUser = group.otherUser;
    final otherUserId = (otherUser['_id'] ?? otherUser['id'])?.toString() ?? '';
    final otherUserName = (otherUser['name'] ?? 'Kullanıcı').toString();
    final otherUserAvatar = (otherUser['avatar'] ?? '').toString().trim();
    final unreadCount = _groupUnreadCount(group, currentUserId);
    final isExpanded = otherUserId.isNotEmpty && _expandedUserIds.contains(otherUserId);

    final avatarUrl = otherUserAvatar.isNotEmpty
        ? '${ApiConfig.uploadsUrl}/$otherUserAvatar'
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (otherUserId.isEmpty) return;
                setState(() {
                  if (isExpanded) {
                    _expandedUserIds.remove(otherUserId);
                  } else {
                    _expandedUserIds.add(otherUserId);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: avatarUrl.isNotEmpty
                          ? ResizeImage(
                              CachedNetworkImageProvider(avatarUrl, cacheKey: avatarUrl),
                              width: 96,
                              height: 96,
                            )
                          : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        otherUserName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (unreadCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green[600],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: Colors.grey[700],
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded) const SizedBox(height: 10),
            if (isExpanded)
              ...group.threads.map((thread) {
                final listing = thread['listing'] as Map<String, dynamic>?;
                final listingTitle = (listing?['title'] ?? 'İlan').toString();
                final senderId = (thread['sender']?['_id'] ?? thread['sender']?['id'])?.toString();
                final isMeSender = senderId == currentUserId;
                final threadUnreadCount = _threadUnreadCount(thread, currentUserId);
                final isUnread = threadUnreadCount > 0;
                final createdAt = (thread['createdAt'] ?? '').toString();
                final previewText = '${isMeSender ? "Siz: " : ""}${thread['content'] ?? ''}';

                return InkWell(
                  onTap: () => _openChatFromMessage(thread, currentUserId),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: isUnread
                          ? Colors.green.withValues(alpha: 0.08)
                          : Colors.grey.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                listingTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                previewText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[800],
                                  fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatDate(createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: isUnread ? Colors.green[700] : Colors.grey[500],
                                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (isUnread) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green[600],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.notifications_active_rounded,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '$threadUnreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // â”€â”€â”€ Skeleton â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Tek bir Shimmer wrapper iÃ§inde tÃ¼m skeleton itemlarÄ± â€” performans iÃ§in
  Widget _buildSkeletonList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      period: const Duration(milliseconds: 1100),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, __) => _buildSkeletonRow(),
      ),
    );
  }

  Widget _buildSkeletonRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 13, width: double.infinity, color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 7)),
                Container(height: 11, width: 160, color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 6)),
                Container(height: 11, width: 220, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadMoreSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: const LinearProgressIndicator(minHeight: 4),
      ),
    );
  }

  // â”€â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?['_id'] ?? authProvider.user?['id'];
    final groupedConversations = _buildConversationGroups(currentUserId?.toString());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesajlar', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green[700],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? _buildSkeletonList()
          : groupedConversations.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadConversations,
                  child: ListView.separated(
                    controller: _scrollController,
                    // cacheExtent yÃ¼ksek tutarak off-screen widget'larÄ±n
                    // dispose edilip yeniden build edilmesini engelliyoruz
                    cacheExtent: 320,
                    itemCount: groupedConversations.length + (_isLoadingMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 0),
                    itemBuilder: (context, index) {
                      if (index >= groupedConversations.length) {
                        return _buildLoadMoreSkeleton();
                      }

                      final group = groupedConversations[index];
                      return _buildConversationGroupItem(group, currentUserId?.toString());
                    },
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Henüz mesajınız yok',
              style: TextStyle(color: Colors.grey[600], fontSize: 16)),
        ],
      ),
    );
  }
}

class _ConversationGroup {
  final Map<String, dynamic> otherUser;
  final List<Map<String, dynamic>> threads;

  _ConversationGroup({
    required this.otherUser,
    required this.threads,
  });
}
