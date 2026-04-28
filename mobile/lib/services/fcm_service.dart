import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../main.dart';
import '../screens/chat_screen.dart';
import '../screens/listing_detail_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Arka planda gelen mesajlar
  print("Arka planda bildirim geldi: ${message.messageId}");
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    // Arka plan handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Izin iste (Özellikle iOS ve Android 13+ icin)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('Kullanici bildirim izni verdi.');
    } else {
      print('Kullanici bildirim izni vermedi.');
      return;
    }

    // Local notifications kurulumu (Ön planda bildirim gostermek icin)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        print('Bildirime tiklandi: ${details.payload}');
        if (details.payload != null) {
          try {
            final data = jsonDecode(details.payload!);
            _handleNotificationClick(data);
          } catch (e) {
            print("Payload decode hatasi: $e");
          }
        }
      },
    );

    // Android icin öncelikli kanal olusturma (Bildirimin ustte pop-up cikmasi icin)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      'Yüksek Öncelikli Bildirimler', // name
      description: 'Bu kanal anlık mesaj bildirimleri içindir.',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // FCM'den on planda mesaj geldiginde dinle
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      if (notification != null) {
        _localNotifications.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              icon: '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.high,
              styleInformation: BigTextStyleInformation(notification.body ?? ''),
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: jsonEncode(message.data),
        );
      }
    });

    // Uygulama arka plandayken bildirime tıklandığında (Native FCM)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Arka planda mesaja tıklandı: ${message.data}');
      _handleNotificationClick(message.data);
    });

    // Uygulama tamamen kapalıyken (Terminated) bildirime tıklandığında
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('Kapalıyken mesaja tıklandı: ${initialMessage.data}');
      // Uygulama yeni acildigi icin Navigator henüz hazır olmayabilir, kucuk bir gecikme ekliyoruz
      Future.delayed(const Duration(milliseconds: 1000), () {
        _handleNotificationClick(initialMessage.data);
      });
    }

    // FCM token al ve backend'e yolla
    await registerDevice();

    // Token yenilendiginde de yolla
    _fcm.onTokenRefresh.listen((newToken) {
      sendTokenToBackend(newToken);
    });

    _isInitialized = true;
  }

  void _handleNotificationClick(Map<String, dynamic> data) async {
    int attempts = 0;
    while (navigatorKey.currentState == null && attempts < 20) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }

    if (navigatorKey.currentState == null) {
      print("Navigator hala null, yonlendirme yapilamadi.");
      return;
    }

    final type = data['type'];
    final listingId = data['listingId']?.toString();

    if (type == 'message' && listingId != null) {
      final receiverId = data['otherUserId']?.toString() ?? '';
      final receiverName = data['otherUserName']?.toString() ?? 'Kullanıcı';
      final listingTitle = data['listingTitle']?.toString() ?? 'İlan';

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            listingId: listingId,
            listingTitle: listingTitle,
            receiverId: receiverId,
            receiverName: receiverName,
          ),
        ),
      );
    } else if ((type == 'favorite' || type == 'listing_published' || type == 'view_milestone') && listingId != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ListingDetailScreen(listingId: listingId),
        ),
      );
    }
  }

  Future<void> registerDevice() async {
    String? token = await _fcm.getToken();
    if (token != null) {
      print("FCM Token: $token");
      await sendTokenToBackend(token);
    }
  }

  Future<void> sendTokenToBackend(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userToken = prefs.getString('token');
      if (userToken == null) return;

      final response = await http.post(
        Uri.parse('${ApiConfig.apiUrl}/users/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $userToken',
        },
        body: jsonEncode({'token': token}),
      );

      if (response.statusCode == 200) {
        print('FCM token backend e basariyla kaydedildi.');
      }
    } catch (e) {
      print('FCM token kaydedilemedi: $e');
    }
  }
}
