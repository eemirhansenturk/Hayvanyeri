import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../providers/auth_provider.dart';
import '../config/api_config.dart';
import 'user_profile_screen.dart';
import 'listing_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String listingId;
  final String? listingTitle;
  final String receiverId;
  final String receiverName;
  final String? receiverAvatar;

  const ChatScreen({
    super.key,
    required this.listingId,
    this.listingTitle,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final TextEditingController _messageController = TextEditingController();

  // reverse: true kullandÄ±ÄŸÄ±mÄ±zda index 0 = en yeni mesaj (alt)
  // Bu sayede scroll position manipÃ¼lasyonu gerekmez
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _messages = []; // index 0 = en yeni
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 20;
  static const double _loadMoreThreshold = 280;
  static final DateFormat _timeFormatter = DateFormat('HH:mm');

  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _isStatusSyncInFlight = false;
  Timer? _statusSyncTimer;

  late final Function(Map<String, dynamic>) _messageReceivedListener;
  late final Function(Map<String, dynamic>) _messagesReadListener;
  late final Function(Map<String, dynamic>) _messagesDeliveredListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _messageReceivedListener = _onMessageReceived;
    _messagesReadListener = _onMessagesRead;
    _messagesDeliveredListener = _onMessagesDelivered;

    _loadMessages();
    _setupSocketListeners();
    _startStatusSyncTimer();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageController.dispose();
    _statusSyncTimer?.cancel();
    _cleanupSocketListeners();
    super.dispose();
  }

  // reverse ListView'da aÅŸaÄŸÄ± kaydÄ±rmak = eski mesajlara gitmek
  // maxScrollExtent'e yaklaÅŸÄ±nca eski mesajlarÄ± yÃ¼kle
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.extentAfter <= _loadMoreThreshold) {
      _loadMoreMessages();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _markAsRead();
    }
  }

  void _markAsRead() {
    if (mounted &&
        _appLifecycleState == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      _apiService
          .markMessagesAsRead(widget.listingId, widget.receiverId)
          .then((_) async {
            await _syncCurrentThreadStatuses();
            await _syncUnreadCount();
          })
          .catchError((_) {});
    }
  }

  void _startStatusSyncTimer() {
    _statusSyncTimer?.cancel();
    _statusSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_appLifecycleState != AppLifecycleState.resumed) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (_messages.isEmpty) return;
      _syncCurrentThreadStatuses();
    });
  }

  Future<void> _syncUnreadCount() async {
    try {
      final socketService = SocketService();
      final newCount = await _apiService.getUnreadMessageCount();
      socketService.unreadCount = newCount;
      socketService.notifyUnreadCountListeners();
    } catch (_) {
      // no-op
    }
  }

  String? _normalizeId(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final nestedId = map['_id'] ?? map['id'] ?? map[r'$oid'];
      if (nestedId == null) return null;
      return nestedId.toString();
    }
    return value.toString();
  }

  Future<void> _syncCurrentThreadStatuses() async {
    if (!mounted || _isStatusSyncInFlight) return;
    _isStatusSyncInFlight = true;

    try {
      final result = await _apiService.getMessages(
        widget.listingId,
        widget.receiverId,
        page: 1,
        limit: 50,
      );

      final rawMessages = result['messages'];
      if (rawMessages is! List) return;

      final statusById = <String, Map<String, dynamic>>{};
      for (final raw in rawMessages) {
        if (raw is! Map) continue;
        final serverMsg = Map<String, dynamic>.from(raw);
        final msgId = _normalizeId(serverMsg['_id']);
        if (msgId == null) continue;
        statusById[msgId] = serverMsg;
      }

      bool hasChanges = false;
      for (final msg in _messages) {
        if (msg is! Map) continue;
        final msgId = _normalizeId(msg['_id']);
        if (msgId == null) continue;

        final serverMsg = statusById[msgId];
        if (serverMsg == null) continue;

        final delivered = serverMsg['delivered'] == true;
        final read = serverMsg['read'] == true;

        if (msg['delivered'] != delivered) {
          msg['delivered'] = delivered;
          hasChanges = true;
        }
        if (msg['read'] != read) {
          msg['read'] = read;
          hasChanges = true;
        }
      }

      if (mounted && hasChanges) {
        setState(() {});
      }
    } catch (_) {
      // no-op
    } finally {
      _isStatusSyncInFlight = false;
    }
  }

  void _setupSocketListeners() {
    final s = SocketService();
    s.addMessageReceivedListener(_messageReceivedListener);
    s.addMessagesReadListener(_messagesReadListener);
    s.addMessagesDeliveredListener(_messagesDeliveredListener);
  }

  void _cleanupSocketListeners() {
    final s = SocketService();
    s.removeMessageReceivedListener(_messageReceivedListener);
    s.removeMessagesReadListener(_messagesReadListener);
    s.removeMessagesDeliveredListener(_messagesDeliveredListener);
  }

  void _onMessageReceived(Map<String, dynamic> data) {
    final message = data['message'];
    if (message == null) return;
    if (message is! Map) return;
    final messageMap = Map<String, dynamic>.from(message);

    final senderId = _normalizeId(messageMap['sender']);
    final listingId =
        _normalizeId(messageMap['listing']) ?? _normalizeId(data['listingId']);
    if (senderId == null || listingId == null) return;

    if (listingId == widget.listingId.toString() &&
        senderId == widget.receiverId.toString()) {
      if (mounted) {
        setState(() {
          // reverse: true oldugu icin index 0'a ekliyoruz = en alt
          _messages.insert(0, messageMap);
        });
        _markAsRead();
      }
    }
  }

  void _onMessagesRead(Map<String, dynamic> data) {
    final eventListingId = _normalizeId(data['listingId']);
    final readBy = _normalizeId(data['readBy']);
    if (eventListingId != widget.listingId.toString() ||
        readBy != widget.receiverId.toString()) {
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId =
        _normalizeId(authProvider.user?['_id'] ?? authProvider.user?['id']);
    if (currentUserId == null) return;

    bool hasChanges = false;
    for (var msg in _messages) {
      if (msg is! Map) continue;
      final msgSenderId = _normalizeId(msg['sender']);
      if (msgSenderId == currentUserId && msg['read'] != true) {
        msg['delivered'] = true;
        msg['read'] = true;
        hasChanges = true;
      }
    }

    if (mounted && hasChanges) {
      setState(() {});
    }
    _syncCurrentThreadStatuses();
  }

  void _onMessagesDelivered(Map<String, dynamic> data) {
    final eventReceiverId = _normalizeId(data['receiverId']);
    final eventListingId = _normalizeId(data['listingId']);
    if (eventReceiverId != widget.receiverId.toString() ||
        eventListingId != widget.listingId.toString()) {
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId =
        _normalizeId(authProvider.user?['_id'] ?? authProvider.user?['id']);
    if (currentUserId == null) return;

    bool hasChanges = false;
    for (var msg in _messages) {
      if (msg is! Map) continue;
      final msgSenderId = _normalizeId(msg['sender']);
      if (msgSenderId == currentUserId &&
          msg['delivered'] != true &&
          msg['read'] != true) {
        msg['delivered'] = true;
        hasChanges = true;
      }
    }

    if (mounted && hasChanges) {
      setState(() {});
    }
    _syncCurrentThreadStatuses();
  }
  Future<void> _loadMessages() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _messages = [];
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      final result = await _apiService.getMessages(
        widget.listingId,
        widget.receiverId,
        page: 1,
        limit: _pageSize,
      );

      if (!mounted) return;

      // API kronolojik sÄ±rada dÃ¶nÃ¼yor (eskiâ†’yeni).
      // reverse ListView iÃ§in ters Ã§eviriyoruz (yeniâ†’eski).
      final msgs = (result['messages'] as List<dynamic>).reversed.toList();

      setState(() {
        _messages = msgs;
        _hasMore = result['hasMore'] as bool? ?? false;
        _isLoading = false;
      });

      _markAsRead();

      // Unread count gÃ¼ncelle
      final socketService = SocketService();
      try {
        final newCount = await _apiService.getUnreadMessageCount();
        socketService.unreadCount = newCount;
        socketService.notifyUnreadCountListeners();
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore) return;
    if (mounted) setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final result = await _apiService.getMessages(
        widget.listingId,
        widget.receiverId,
        page: nextPage,
        limit: _pageSize,
      );

      if (!mounted) return;

      // Eski mesajlar (daha Ã¶nce gÃ¶nderilmiÅŸ) â€” tersine Ã§evirerek listenin
      // sonuna ekliyoruz (reverse ListView'da ekran dÄ±ÅŸÄ± = Ã¼st kÄ±sÄ±m)
      final older = (result['messages'] as List<dynamic>).reversed.toList();

      setState(() {
        _messages.addAll(older);
        _currentPage = nextPage;
        _hasMore = result['hasMore'] as bool? ?? false;
        _isLoadingMore = false;
      });
      // reverse ListView'da addAll(older) scroll'u bozmaz,
      // Flutter otomatik olarak pozisyonu korur.
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?['_id'] ?? authProvider.user?['id'];

    final tempMsg = {
      'content': text,
      'createdAt': DateTime.now().toIso8601String(),
      'sender': {'_id': userId},
      'temp': true,
    };

    // reverse: true â†’ index 0'a ekle = en alta gÃ¶rÃ¼nÃ¼r
    setState(() => _messages.insert(0, tempMsg));

    // Scroll zaten en altta, reverse ile otomatik kalÄ±r.
    // Ama gÃ¼vence iÃ§in kÃ¼Ã§Ã¼k bir jump
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          _scrollController.position.pixels > 0) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      final sentMessage = await _apiService.sendMessage({
        'listing': widget.listingId,
        'receiver': widget.receiverId,
        'content': text,
      });

      if (mounted) {
        setState(() {
          final idx = _messages.indexOf(tempMsg);
          if (idx != -1) _messages[idx] = sentMessage;
        });
        Future.delayed(
          const Duration(milliseconds: 900),
          _syncCurrentThreadStatuses,
        );
        try {
          final socketService = SocketService();
          final newCount = await _apiService.getUnreadMessageCount();
          socketService.unreadCount = newCount;
          socketService.notifyUnreadCountListeners();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.remove(tempMsg));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mesaj gönderilemedi: $e')),
        );
      }
    }
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      return _timeFormatter.format(DateTime.parse(dateStr).toLocal());
    } catch (_) {
      return '';
    }
  }

  // â”€â”€â”€ Skeleton â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildSkeletonList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      period: const Duration(milliseconds: 1100),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: const [
          _SkeletonBubble(isMe: false),
          _SkeletonBubble(isMe: true),
          _SkeletonBubble(isMe: false, wide: true),
          _SkeletonBubble(isMe: true, wide: true),
          _SkeletonBubble(isMe: false),
          _SkeletonBubble(isMe: true),
        ],
      ),
    );
  }

  // â”€â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId =
        _normalizeId(authProvider.user?['_id'] ?? authProvider.user?['id']);

    final avatarPath = (widget.receiverAvatar ?? '').trim();
    final hasAvatar = avatarPath.isNotEmpty;
    final avatarUrl = hasAvatar ? '${ApiConfig.uploadsUrl}/$avatarPath' : '';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.white,
        elevation: 1,
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                if (widget.receiverId.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                        userId: widget.receiverId,
                        userName: widget.receiverName,
                      ),
                    ),
                  );
                }
              },
              child: CircleAvatar(
                backgroundColor: Colors.green[100],
                radius: 18,
                backgroundImage: hasAvatar
                    ? CachedNetworkImageProvider(avatarUrl)
                    : null,
                child: hasAvatar
                    ? null
                    : Text(
                        widget.receiverName.isNotEmpty
                            ? widget.receiverName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: Colors.green[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.receiverName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  GestureDetector(
                    onTap: () {
                      if (widget.listingId.isNotEmpty) {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            opaque: false,
                            pageBuilder: (context, animation, secondaryAnimation) =>
                                ListingDetailScreen(listingId: widget.listingId),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return FadeTransition(opacity: animation, child: child);
                            },
                          ),
                        );
                      }
                    },
                    child: Text(
                      (widget.listingTitle ?? '').trim().isNotEmpty
                          ? widget.listingTitle!.trim()
                          : 'Satıcı',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Colors.grey[800]),
            onSelected: (value) {
              if (value == 'profile' && widget.receiverId.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(
                      userId: widget.receiverId,
                      userName: widget.receiverName,
                    ),
                  ),
                );
              } else if (value == 'listing' && widget.listingId.isNotEmpty) {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    opaque: false,
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        ListingDetailScreen(listingId: widget.listingId),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                  ),
                );
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
                value: 'listing',
                child: Row(
                  children: [
                    Icon(Icons.pets, size: 20, color: Colors.green),
                    SizedBox(width: 8),
                    Text('İlanı Görüntüle'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? _buildSkeletonList()
                : _messages.isEmpty
                    ? _buildEmpty()
                    : _buildMessageList(currentUserId),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageList(String? currentUserId) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    return ListView.builder(
      controller: _scrollController,
      // reverse: true â†’ index 0 altta, scroll aÅŸaÄŸÄ±da baÅŸlar
      // Yeni mesaj = insert(0) kayÄ±t â†’ otomatik altta gÃ¶rÃ¼nÃ¼r
      // Eski mesaj = addAll(older) eklenir â†’ scroll position korunur
      reverse: true,
      cacheExtent: 300,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // reverse ListView'da en son item = en Ã¼st = "load more" gÃ¶stergesi
        if (index == _messages.length) {
          return _buildLoadMoreIndicator();
        }

        final message = _messages[index];
        final isMe = _normalizeId(message['sender']) == currentUserId;
        final isTemp = message['temp'] == true;

        // reverse: index 0 = en yeni â†’ Ã¶nceki = index 1 (daha eski)
        final prevMsg = index > 0 ? _messages[index - 1] : null;
        final nextMsg = index < _messages.length - 1 ? _messages[index + 1] : null;

        final prevSender = prevMsg == null ? null : _normalizeId(prevMsg['sender']);
        final nextSender = nextMsg == null ? null : _normalizeId(nextMsg['sender']);
        final curSender = _normalizeId(message['sender']);

        // reverse'de bir sonraki index (index+1) daha eski mesaj
        // isFirstInGroup: bu mesajÄ±n Ã¼stÃ¼nde farklÄ± gÃ¶nderici var mÄ±?
        // â†’ nextMsg (daha eski), farklÄ± gÃ¶ndericiyse ilk
        final isFirstInGroup = nextSender != curSender;
        final isLastInGroup = prevSender != curSender;

        return _MessageBubble(
          key: ValueKey(message['_id'] ?? index),
          message: message,
          isMe: isMe,
          isTemp: isTemp,
          isFirstInGroup: isFirstInGroup,
          isLastInGroup: isLastInGroup,
          formatTime: _formatTime,
          screenWidth: screenWidth,
        );
      },
    );
  }

  Widget _buildLoadMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green[600]!),
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
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green[50],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.chat_bubble_outline,
                size: 48, color: Colors.green[300]),
          ),
          const SizedBox(height: 16),
          Text(
            'Sohbete Başlayın',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800]),
          ),
          const SizedBox(height: 8),
          Text(
            'Hayvan ile ilgili sorularınızı sorabilirsiniz',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: 10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Bir mesaj yazın...',
                hintStyle: TextStyle(color: Colors.grey[500]),
                filled: true,
                fillColor: const Color(0xFFF0F2F5),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.green[400]!, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: Colors.green[600],
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _sendMessage,
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€ Stateless message bubble â€” gereksiz rebuild olmaz â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final bool isTemp;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final String Function(String?) formatTime;
  final double screenWidth;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isTemp,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.formatTime,
    required this.screenWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: isFirstInGroup ? 6 : 2,
        bottom: isLastInGroup ? 6 : 2,
      ),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: screenWidth * 0.75),
          decoration: BoxDecoration(
            color: isMe ? Colors.green[600] : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(
                isMe ? 18 : (isLastInGroup ? 4 : 18),
              ),
              bottomRight: Radius.circular(
                isMe ? (isLastInGroup ? 4 : 18) : 18,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message['content'] ?? '',
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatTime(message['createdAt']),
                    style: TextStyle(
                      color: isMe ? Colors.white70 : Colors.grey[500],
                      fontSize: 11,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _statusIcon(message, isTemp),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusIcon(Map<String, dynamic> msg, bool temp) {
    if (temp) {
      return const Icon(Icons.access_time, size: 13, color: Colors.white60);
    }
    if (msg['read'] == true) {
      return Icon(Icons.done_all, size: 13, color: Colors.blue[300]);
    } else if (msg['delivered'] == true) {
      return const Icon(Icons.done_all, size: 13, color: Colors.white70);
    } else {
      return const Icon(Icons.done, size: 13, color: Colors.white70);
    }
  }
}

// â”€â”€â”€ Skeleton bubble â€” const ile yeniden oluÅŸturma sÄ±fÄ±r â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SkeletonBubble extends StatelessWidget {
  final bool isMe;
  final bool wide;

  const _SkeletonBubble({required this.isMe, this.wide = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: wide ? 240 : 160,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}








