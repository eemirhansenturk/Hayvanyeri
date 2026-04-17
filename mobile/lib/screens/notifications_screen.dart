import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../services/api_service.dart';
import '../config/api_config.dart';
import 'listing_detail_screen.dart';
import 'chat_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    final pos = _scrollController.position;
    if (pos.extentAfter <= 200) {
      _loadMoreNotifications();
    }
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _notifications = [];
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      final result = await _apiService.getNotifications(page: 1, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _notifications = result['notifications'] as List<dynamic>;
        _hasMore = result['hasMore'] as bool? ?? false;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreNotifications() async {
    if (_isLoadingMore || !_hasMore) return;

    if (mounted) setState(() => _isLoadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final result = await _apiService.getNotifications(page: nextPage, limit: _pageSize);

      if (!mounted) return;
      final incoming = result['notifications'] as List<dynamic>;
      setState(() {
        _notifications.addAll(incoming);
        _currentPage = nextPage;
        _hasMore = result['hasMore'] as bool? ?? false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _markAsRead(String notificationId, int index) async {
    try {
      await _apiService.markNotificationAsRead(notificationId);
      if (mounted) {
        setState(() {
          _notifications[index]['read'] = true;
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await _apiService.markAllNotificationsAsRead();
      if (mounted) {
        setState(() {
          for (var notif in _notifications) {
            notif['read'] = true;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tüm bildirimler okundu olarak işaretlendi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    }
  }

  Future<void> _deleteNotification(String notificationId, int index) async {
    try {
      await _apiService.deleteNotification(notificationId);
      if (mounted) {
        setState(() {
          _notifications.removeAt(index);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bildirim silindi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silme başarısız: $e')),
        );
      }
    }
  }

  void _onNotificationTap(Map<String, dynamic> notification, int index) async {
    final type = notification['type'] ?? '';
    final listingId = notification['listing']?['_id'] ?? notification['listing'];
    final relatedUserId = notification['relatedUser']?['_id'] ?? notification['relatedUser'];
    
    if (!notification['read']) {
      _markAsRead(notification['_id'], index);
    }

    // Mesaj bildirimi ise doğrudan sohbete yönlendir
    if (type == 'message' && listingId != null && relatedUserId != null) {
      try {
        // İlan bilgisini al
        final listingData = await _apiService.getListing(listingId.toString());
        
        // Kullanıcı bilgisini notification'dan al
        final relatedUser = notification['relatedUser'];
        
        if (mounted && listingData != null && relatedUser != null) {
          final userName = relatedUser is Map ? (relatedUser['name'] ?? 'Kullanıcı') : 'Kullanıcı';
          final userAvatar = relatedUser is Map ? relatedUser['avatar'] : null;
          final userId = relatedUser is Map ? relatedUser['_id'] : relatedUserId;
          
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                listingId: listingId.toString(),
                listingTitle: listingData['title'],
                receiverId: userId.toString(),
                receiverName: userName,
                receiverAvatar: userAvatar,
              ),
            ),
          );
        }
      } catch (e) {
        // Hata durumunda ilan detayına yönlendir
        if (mounted && listingId != null) {
          Navigator.push(
            context,
            PageRouteBuilder(
              opaque: false,
              pageBuilder: (context, animation, secondaryAnimation) =>
                  ListingDetailScreen(listingId: listingId.toString()),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          );
        }
      }
    } else if (listingId != null) {
      // Diğer bildirimler için ilan detayına git
      Navigator.push(
        context,
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (context, animation, secondaryAnimation) =>
              ListingDetailScreen(listingId: listingId.toString()),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'favorite':
        return Icons.favorite;
      case 'message':
        return Icons.message;
      case 'view_milestone':
        return Icons.visibility;
      case 'listing_published':
        return Icons.check_circle;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'favorite':
        return Colors.red;
      case 'message':
        return Colors.blue;
      case 'view_milestone':
        return Colors.orange;
      case 'listing_published':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays > 7) {
        return DateFormat('dd.MM.yyyy').format(date);
      } else if (diff.inDays > 0) {
        return '${diff.inDays} gün önce';
      } else if (diff.inHours > 0) {
        return '${diff.inHours} saat önce';
      } else if (diff.inMinutes > 0) {
        return '${diff.inMinutes} dakika önce';
      } else {
        return 'Şimdi';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Bildirimler', style: TextStyle(color: Colors.white)),
        elevation: 0,
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_notifications.any((n) => !n['read']))
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: _markAllAsRead,
              tooltip: 'Tümünü okundu işaretle',
            ),
        ],
      ),
      body: _isLoading
          ? _buildSkeletonList()
          : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _notifications.length + (_isLoadingMore ? 3 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _notifications.length) {
                        return _buildSkeletonItem();
                      }

                      final notification = _notifications[index];
                      return _buildNotificationItem(notification, index);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Henüz bildiriminiz yok',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      itemCount: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemBuilder: (context, index) => _buildSkeletonItem(),
    );
  }

  Widget _buildSkeletonItem() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.white,
            radius: 24,
          ),
          title: Container(
            height: 14,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                height: 12,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 10,
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          trailing: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification, int index) {
    final isRead = notification['read'] ?? false;
    final type = notification['type'] ?? '';
    final title = notification['title'] ?? '';
    final message = notification['message'] ?? '';
    final createdAt = notification['createdAt'] ?? '';
    final listing = notification['listing'];

    String? imageUrl;
    if (listing != null && listing is Map) {
      final images = listing['images'];
      if (images != null && images is List && images.isNotEmpty) {
        imageUrl = '${ApiConfig.uploadsUrl}/${images[0]}';
      }
    }

    return Dismissible(
      key: Key(notification['_id']),
      direction: isRead ? DismissDirection.endToStart : DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Sağa kaydırma - Okundu işaretle (sadece okunmamışlar için)
          if (!isRead) {
            await _markAsRead(notification['_id'], index);
          }
          return false; // Dismiss etme, sadece okundu işaretle
        } else {
          // Sola kaydırma - Sil
          return true; // Dismiss et
        }
      },
      background: Container(
        color: isRead ? Colors.transparent : Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: isRead ? null : const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.done_all, color: Colors.white, size: 32),
            SizedBox(height: 4),
            Text(
              'Okundu',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white, size: 32),
            SizedBox(height: 4),
            Text(
              'Sil',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          _deleteNotification(notification['_id'], index);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          onTap: () => _onNotificationTap(notification, index),
          leading: CircleAvatar(
            backgroundColor: _getNotificationColor(type).withValues(alpha: 0.1),
            child: Icon(
              _getNotificationIcon(type),
              color: _getNotificationColor(type),
              size: 24,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
              fontSize: 15,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
          trailing: imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: Colors.grey[200],
                      width: 50,
                      height: 50,
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey[200],
                      width: 50,
                      height: 50,
                      child: const Icon(Icons.image_not_supported),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
