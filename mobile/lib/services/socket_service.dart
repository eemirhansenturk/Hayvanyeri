import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../config/api_config.dart';
import 'api_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? socket;
  String? _currentUserId;
  bool _isInitializing = false;
  Timer? _unreadSyncDebounceTimer;

  final List<Function(Map<String, dynamic>)> _messageReceivedListeners = [];
  final List<Function(Map<String, dynamic>)> _messagesReadListeners = [];
  final List<Function(Map<String, dynamic>)> _messagesDeliveredListeners = [];
  final List<Function(Map<String, dynamic>)> _notificationListeners = [];
  final List<Function(Map<String, dynamic>)> _listingRemovedListeners = [];

  int unreadCount = 0;
  final List<Function(int)> _unreadCountListeners = [];

  void addUnreadCountListener(Function(int) callback) {
    _unreadCountListeners.add(callback);
  }

  void removeUnreadCountListener(Function(int) callback) {
    _unreadCountListeners.remove(callback);
  }

  void _notifyUnreadCountListeners() {
    for (var listener in _unreadCountListeners) {
      listener(unreadCount);
    }
  }

  void notifyUnreadCountListeners() {
    _notifyUnreadCountListeners();
  }

  Map<String, dynamic> _normalizeEventData(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  void _scheduleUnreadSync({bool optimisticIncrement = false}) {
    _unreadSyncDebounceTimer?.cancel();
    _unreadSyncDebounceTimer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final apiService = ApiService();
        unreadCount = await apiService.getUnreadMessageCount();
      } catch (_) {
        if (optimisticIncrement) {
          unreadCount++;
        }
      }
      _notifyUnreadCountListeners();
    });
  }

  void addMessageReceivedListener(Function(Map<String, dynamic>) callback) {
    _messageReceivedListeners.add(callback);
  }

  void addMessagesReadListener(Function(Map<String, dynamic>) callback) {
    _messagesReadListeners.add(callback);
  }

  void addMessagesDeliveredListener(Function(Map<String, dynamic>) callback) {
    _messagesDeliveredListeners.add(callback);
  }

  void addNotificationListener(Function(Map<String, dynamic>) callback) {
    _notificationListeners.add(callback);
  }

  void removeMessageReceivedListener(Function(Map<String, dynamic>) callback) {
    _messageReceivedListeners.remove(callback);
  }

  void removeMessagesReadListener(Function(Map<String, dynamic>) callback) {
    _messagesReadListeners.remove(callback);
  }

  void removeMessagesDeliveredListener(
    Function(Map<String, dynamic>) callback,
  ) {
    _messagesDeliveredListeners.remove(callback);
  }

  void removeNotificationListener(Function(Map<String, dynamic>) callback) {
    _notificationListeners.remove(callback);
  }

  void addListingRemovedListener(Function(Map<String, dynamic>) callback) {
    _listingRemovedListeners.add(callback);
  }

  void removeListingRemovedListener(Function(Map<String, dynamic>) callback) {
    _listingRemovedListeners.remove(callback);
  }

  int notificationCount = 0;
  final List<Function(int)> _notificationCountListeners = [];

  void addNotificationCountListener(Function(int) callback) {
    _notificationCountListeners.add(callback);
  }

  void removeNotificationCountListener(Function(int) callback) {
    _notificationCountListeners.remove(callback);
  }

  void _notifyNotificationCountListeners() {
    for (var listener in _notificationCountListeners) {
      listener(notificationCount);
    }
  }

  void notifyNotificationCountListeners() {
    _notifyNotificationCountListeners();
  }

  Future<void> init(String userId) async {
    if (_isInitializing) return;

    final normalizedUserId = userId.toString();
    _currentUserId = normalizedUserId;

    if (socket != null && socket!.connected) {
      socket!.emit('register', normalizedUserId);
      _scheduleUnreadSync();
      return;
    }

    _isInitializing = true;
    try {
      final String serverUrl = ApiConfig.baseUrl.replaceAll('/api', '');

      disconnect();

      socket = IO.io(serverUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': 99999,
        'reconnectionDelay': 1000,
        'reconnectionDelayMax': 5000,
      });

      socket!.connect();

      socket!.onConnect((_) async {
        socket!.emit('register', normalizedUserId);
        try {
          final apiService = ApiService();
          await apiService.markMessagesAsDelivered();
          
          // Bildirim sayısını yükle
          notificationCount = await apiService.getUnreadNotificationCount();
          _notifyNotificationCountListeners();
        } catch (_) {
          // Ignore
        }
        _scheduleUnreadSync();
      });

      socket!.onConnectError((_) {
        // Ignore
      });

      socket!.onError((_) {
        // Ignore
      });

      socket!.off('receive_message');
      socket!.off('messages_read');
      socket!.off('messages_delivered');
      socket!.off('new_message_notification');
      socket!.off('listing_removed');

      socket!.on('receive_message', (data) {
        final eventData = _normalizeEventData(data);
        for (var listener in _messageReceivedListeners) {
          listener(eventData);
        }

        final senderId = eventData['senderId']?.toString();
        if (senderId != null &&
            _currentUserId != null &&
            senderId != _currentUserId) {
          _scheduleUnreadSync(optimisticIncrement: true);
        }
      });

      socket!.on('messages_read', (data) {
        final eventData = _normalizeEventData(data);
        for (var listener in _messagesReadListeners) {
          listener(eventData);
        }
      });

      socket!.on('messages_delivered', (data) {
        final eventData = _normalizeEventData(data);
        for (var listener in _messagesDeliveredListeners) {
          listener(eventData);
        }
      });

      socket!.on('new_message_notification', (data) {
        final eventData = _normalizeEventData(data);
        final senderId = eventData['senderId']?.toString();
        if (senderId != null &&
            _currentUserId != null &&
            senderId == _currentUserId) {
          return;
        }

        _scheduleUnreadSync(optimisticIncrement: true);

        for (var listener in _notificationListeners) {
          listener(eventData);
        }
      });

      socket!.on('new_notification', (data) {
        final eventData = _normalizeEventData(data);
        
        // Bildirim sayısını artır
        notificationCount++;
        _notifyNotificationCountListeners();

        for (var listener in _notificationListeners) {
          listener(eventData);
        }
      });

      socket!.on('listing_removed', (data) {
        final eventData = _normalizeEventData(data);
        for (var listener in _listingRemovedListeners) {
          listener(eventData);
        }
      });

      socket!.onDisconnect((_) {
        // Ignore
      });
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> reconnectIfNeeded() async {
    final userId = _currentUserId;
    if (userId == null) return;

    if (socket == null || !(socket!.connected)) {
      await init(userId);
      return;
    }

    socket!.emit('register', userId);
    try {
      final apiService = ApiService();
      await apiService.markMessagesAsDelivered();
    } catch (_) {
      // Ignore
    }
    _scheduleUnreadSync();
  }

  void disconnectForBackground() {
    disconnect();
  }

  void resetUnreadCount() {
    unreadCount = 0;
    _notifyUnreadCountListeners();
  }

  void disconnect() {
    _unreadSyncDebounceTimer?.cancel();
    if (socket != null && socket!.connected) {
      socket!.disconnect();
    }
  }
}
