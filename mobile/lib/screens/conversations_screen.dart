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
import 'user_profile_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => ConversationsScreenState();
}

class ConversationsScreenState extends State<ConversationsScreen> {
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
  final Set<String> _selectedItems = <String>{};

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

  void refreshList() {
    _scheduleRefreshFirstPage();
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

  void _clearSelection() {
    setState(() {
      _selectedItems.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedItems.contains(id)) {
        _selectedItems.remove(id);
      } else {
        _selectedItems.add(id);
      }
    });
  }

  Future<void> _deleteSelectedItems() async {
    if (_selectedItems.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_sweep, color: Colors.red[700], size: 36),
              ),
              const SizedBox(height: 16),
              const Text('Mesajları Sil', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '${_selectedItems.length} adet sohbeti silmek istiyor musunuz? İşlem geri alınamaz.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[700], height: 1.4),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('İptal', style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Sil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Siliniyor...')),
      );

      final futures = <Future>[];
      for (final id in _selectedItems) {
        if (id.startsWith('user_')) {
          final otherUserId = id.substring(5);
          futures.add(_apiService.deleteConversationsWithUser(otherUserId));
        } else if (id.startsWith('listing_')) {
          final parts = id.substring(8).split('_user_');
          if (parts.length == 2) {
            futures.add(_apiService.deleteListingConversationWithUser(parts[0], parts[1]));
          }
        }
      }

      await Future.wait(futures);

      _clearSelection();
      _loadConversations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    }
  }

  Future<void> _showDeleteConversationDialog(String otherUserId, String otherUserName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_sweep, color: Colors.red[700], size: 36),
              ),
              const SizedBox(height: 16),
              const Text('Konuşmaları Sil', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '$otherUserName ile olan tüm konuşmalarınızı silmek istediğinizden emin misiniz? İşlem geri alınamaz.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey[700], height: 1.4),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.grey[300]!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('İptal', style: TextStyle(fontSize: 16, color: Colors.grey[700], fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Sil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Siliniyor...')),
      );

      await _apiService.deleteConversationsWithUser(otherUserId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konuşmalar silindi')),
      );

      _loadConversations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: ${e.toString().replaceAll('Exception: ', '')}')),
        );
      }
    }
  }

  void _openChatFromMessage(Map<String, dynamic> message, String? currentUserId, {bool isListingRemoved = false, bool isListingPassive = false}) {
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
          isListingRemoved: isListingRemoved,
          isListingPassive: isListingPassive,
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
    final userIdStr = 'user_$otherUserId';
    final isUserSelected = _selectedItems.contains(userIdStr);

    final avatarUrl = otherUserAvatar.isNotEmpty
        ? '${ApiConfig.uploadsUrl}/$otherUserAvatar'
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isUserSelected ? Colors.green.withValues(alpha: 0.15) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isUserSelected
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
        border: isUserSelected ? Border.all(color: Colors.green, width: 2) : Border.all(color: Colors.transparent, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (otherUserId.isEmpty) return;
                if (_selectedItems.isNotEmpty) {
                  _toggleSelection(userIdStr);
                  return;
                }
                setState(() {
                  if (isExpanded) {
                    _expandedUserIds.remove(otherUserId);
                  } else {
                    _expandedUserIds.add(otherUserId);
                  }
                });
              },
              onLongPress: () {
                if (otherUserId.isEmpty) return;
                _toggleSelection(userIdStr);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Stack(
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
                        if (isUserSelected)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, size: 14, color: Colors.white),
                            ),
                          ),
                      ],
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
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        decoration: BoxDecoration(
                          color: Colors.green[600],
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.more_horiz, color: Colors.grey[700], size: 20),
                      ),
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        if (value == 'profile' && otherUserId.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfileScreen(
                                userId: otherUserId,
                                userName: otherUserName,
                              ),
                            ),
                          );
                        } else if (value == 'delete' && otherUserId.isNotEmpty) {
                          _showDeleteConversationDialog(otherUserId, otherUserName);
                        }
                      },
                      itemBuilder: (BuildContext context) => [
                        const PopupMenuItem<String>(
                          value: 'profile',
                          child: Row(
                            children: [
                              Icon(Icons.person, size: 20, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Profil detaylarını gör'),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 20, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Bu kişiyle konuşmaları sil'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.grey[700],
                        size: 20,
                      ),
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
                final listingStatus = (listing?['status'] ?? 'aktif').toString();
                final isListingRemoved = listingStatus == 'silindi';
                final isListingPassive = listingStatus == 'pasif';
                final senderId = (thread['sender']?['_id'] ?? thread['sender']?['id'])?.toString();
                final isMeSender = senderId == currentUserId;
                final threadUnreadCount = _threadUnreadCount(thread, currentUserId);
                final isUnread = threadUnreadCount > 0;
                final createdAt = (thread['createdAt'] ?? '').toString();
                final previewText = '${isMeSender ? "Siz: " : "O: "}${thread['content'] ?? ''}';
                final threadIdStr = 'listing_${(listing?['_id'] ?? '')}_user_$otherUserId';
                final isThreadSelected = _selectedItems.contains(threadIdStr);

                return InkWell(
                  onTap: () {
                    if (_selectedItems.isNotEmpty) {
                      _toggleSelection(threadIdStr);
                      return;
                    }
                    _openChatFromMessage(thread, currentUserId, isListingRemoved: isListingRemoved, isListingPassive: isListingPassive);
                  },
                  onLongPress: () {
                     final lId = (listing?['_id'] ?? '').toString();
                     if (lId.isEmpty || otherUserId.isEmpty) return;
                     _toggleSelection(threadIdStr);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: isThreadSelected
                          ? Colors.green.withValues(alpha: 0.15)
                          : isUnread
                              ? Colors.green.withValues(alpha: 0.08)
                              : Colors.grey.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: isThreadSelected
                          ? Border.all(color: Colors.green, width: 1.5)
                          : Border.all(color: Colors.transparent, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        if (isThreadSelected) ...[
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      listingTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (isListingRemoved) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red[50],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Kaldırıldı',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.red[600],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (isListingPassive) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber[50],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Pasif İlan',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.amber[800],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
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

    return WillPopScope(
      onWillPop: () async {
        if (_selectedItems.isNotEmpty) {
          _clearSelection();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: _selectedItems.isNotEmpty
            ? AppBar(
                backgroundColor: Colors.green[700],
                iconTheme: const IconThemeData(color: Colors.white),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                ),
                title: Text(
                  '${_selectedItems.length} seçildi',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _deleteSelectedItems,
                  ),
                ],
              )
            : AppBar(
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
