import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class ApiService {
  static String get baseUrl => ApiConfig.apiUrl;
  static const Duration timeout = Duration(seconds: 10);
  
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<Map<String, String>> _getHeaders({bool needsAuth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (needsAuth) {
      final token = await _getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // Auth
  Future<Map<String, dynamic>> sendVerificationCode(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/send-verification'),
        headers: await _getHeaders(),
        body: jsonEncode(data),
      ).timeout(timeout);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Kod gönderilemedi');
      }
    } on SocketException {
      throw Exception('İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.');
    } on TimeoutException {
      throw Exception('Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.');
    } on FormatException {
      throw Exception('Sunucudan geçersiz yanıt alındı.');
    } catch (e) {
      throw Exception('Bağlantı hatası: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  Future<Map<String, dynamic>> verifyCode(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/verify-code'),
        headers: await _getHeaders(),
        body: jsonEncode(data),
      ).timeout(timeout);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Doğrulama başarısız');
      }
    } on SocketException {
      throw Exception('İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.');
    } on TimeoutException {
      throw Exception('Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.');
    } on FormatException {
      throw Exception('Sunucudan geçersiz yanıt alındı.');
    } catch (e) {
      throw Exception('Bağlantı hatası: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: await _getHeaders(),
        body: jsonEncode(data),
      ).timeout(timeout);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Kayıt başarısız');
      }
    } on SocketException {
      throw Exception('İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.');
    } on TimeoutException {
      throw Exception('Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.');
    } on FormatException {
      throw Exception('Sunucudan geçersiz yanıt alındı.');
    } catch (e) {
      throw Exception('Bağlantı hatası: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: await _getHeaders(),
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(timeout);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['message'] ?? 'Giriş başarısız');
      }
    } on SocketException {
      throw Exception('İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.');
    } on TimeoutException {
      throw Exception('Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.');
    } on FormatException {
      throw Exception('Sunucudan geçersiz yanıt alındı.');
    } catch (e) {
      throw Exception('Bağlantı hatası: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // Listings
  Future<Map<String, dynamic>> getListings({
    Map<String, dynamic>? filters,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      var url = '$baseUrl/listings?page=$page&limit=$limit&';
      if (filters != null) {
        filters.forEach((key, value) {
          if (value != null && value.toString().isNotEmpty) {
            url += '$key=${Uri.encodeComponent(value.toString())}&';
          }
        });
      }
      
      final response = await http.get(Uri.parse(url)).timeout(timeout);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('İlanlar yüklenemedi');
      }
    } on SocketException {
      throw Exception('İnternet bağlantısı yok');
    } on TimeoutException {
      throw Exception('Bağlantı zaman aşımına uğradı');
    } catch (e) {
      throw Exception('Hata: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  Future<Map<String, dynamic>> getListing(String id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/listings/$id')).timeout(timeout);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('İlan bulunamadı');
      }
    } catch (e) {
      throw Exception('Hata: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  Future<Map<String, dynamic>> createListing(Map<String, dynamic> data, List<File> images) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Token bulunamadı');
      
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/listings'));
      request.headers['Authorization'] = 'Bearer $token';
      
      // Tüm alanları string olarak ekle
      data.forEach((key, value) {
        if (value != null && value.toString().isNotEmpty) {
          request.fields[key] = value.toString();
        }
      });
      
      // Resimleri ekle
      for (var image in images) {
        request.files.add(await http.MultipartFile.fromPath('images', image.path));
      }
      
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(responseData);
      } else {
        throw Exception('İlan oluşturulamadı: $responseData');
      }
    } catch (e) {
      throw Exception('Bağlantı hatası: $e');
    }
  }

  Future<Map<String, dynamic>> updateListingTextAndImages(String id, Map<String, dynamic> data, List<File> newImages, List<String> deletedImages) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Token bulunamadı');
      
      var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/listings/$id'));
      request.headers['Authorization'] = 'Bearer $token';
      
      data.forEach((key, value) {
        if (value != null && value.toString().isNotEmpty) {
          request.fields[key] = value.toString();
        }
      });

      if (deletedImages.isNotEmpty) {
        request.fields['deletedImages'] = deletedImages.join(',');
      }

      for (var image in newImages) {
        request.files.add(await http.MultipartFile.fromPath('newImages', image.path));
      }
      
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(responseData);
      } else {
        throw Exception('İlan güncellenemedi: $responseData');
      }
    } catch (e) {
      throw Exception('Bağlantı hatası: $e');
    }
  }

  Future<void> updateListingStatus(String id, String status) async {
    final response = await http.put(
      Uri.parse('$baseUrl/listings/$id'),
      headers: await _getHeaders(needsAuth: true),
      body: jsonEncode({'status': status}),
    );
    if (response.statusCode != 200) {
      throw Exception('İlan durumu güncellenemedi: ${response.body}');
    }
  }

  Future<void> deleteListing(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/listings/$id'),
      headers: await _getHeaders(needsAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception('İlan silinemedi: ${response.body}');
    }
  }

  // Messages
  Future<Map<String, dynamic>> getConversations({int page = 1, int limit = 20}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/messages/conversations?page=$page&limit=$limit'),
      headers: await _getHeaders(needsAuth: true),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'conversations': data['conversations'] as List<dynamic>,
        'hasMore': data['hasMore'] as bool? ?? false,
        'total': data['total'] as int? ?? 0,
      };
    } else {
      throw Exception('Konuşmalar getirilemedi: ${response.body}');
    }
  }

  Future<int> getUnreadMessageCount() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/messages/unread-count'),
        headers: await _getHeaders(needsAuth: true),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<Map<String, dynamic>> getMessages(String listingId, String otherUserId, {int page = 1, int limit = 10}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/messages/$listingId/$otherUserId?page=$page&limit=$limit'),
      headers: await _getHeaders(needsAuth: true),
    );
    final data = jsonDecode(response.body);
    return {
      'messages': data['messages'] as List<dynamic>,
      'hasMore': data['hasMore'] as bool? ?? false,
      'total': data['total'] as int? ?? 0,
      'listingRemoved': data['listingRemoved'] as bool? ?? false,
      'listingPassive': data['listingPassive'] as bool? ?? false,
      'listingTitle': data['listingTitle'] as String?,
      'listingOwner': data['listingOwner'] as String?,
    };
  }

  Future<Map<String, dynamic>> sendMessage(Map<String, dynamic> data) async {
    
    final response = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: await _getHeaders(needsAuth: true),
      body: jsonEncode(data),
    );
    
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Mesaj gönderilemedi: ${response.body}');
    }
  }

  Future<void> markMessagesAsRead(String listingId, String otherUserId) async {
    try {
      await http.put(
        Uri.parse('$baseUrl/messages/read/$listingId/$otherUserId'),
        headers: await _getHeaders(needsAuth: true),
      );
    } catch (e) {
    }
  }

  Future<void> markMessagesAsDelivered() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/messages/mark-delivered'),
        headers: await _getHeaders(needsAuth: true),
      );
    } catch (e) {
    }
  }

  Future<void> deleteConversationsWithUser(String otherUserId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/messages/user/$otherUserId'),
      headers: await _getHeaders(needsAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception('Konuşmalar silinemedi');
    }
  }

  Future<void> deleteListingConversationWithUser(String listingId, String otherUserId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/messages/listing/$listingId/user/$otherUserId'),
      headers: await _getHeaders(needsAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception('İlan konuşması silinemedi');
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/users/change-password'),
      headers: await _getHeaders(needsAuth: true),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );

    if (response.statusCode == 200) return;

    String errorMessage = 'Şifre güncellenemedi';
    try {
      final error = jsonDecode(response.body);
      if (error['message'] != null) {
        errorMessage = error['message'];
      }
    } catch (_) {}
    
    throw Exception(errorMessage);
  }

  // User
  Future<Map<String, dynamic>> getProfile() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/profile'),
      headers: await _getHeaders(needsAuth: true),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/$userId/profile'),
      headers: await _getHeaders(needsAuth: true),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Kullanıcı profili getirilemedi: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? phone,
    String? city,
    String? district,
    File? avatarFile,
    bool removeAvatar = false,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Token bulunamadı');

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('$baseUrl/users/profile'),
      );
      request.headers['Authorization'] = 'Bearer $token';

      if (name != null) request.fields['name'] = name;
      if (phone != null) request.fields['phone'] = phone;
      if (city != null) request.fields['city'] = city;
      if (district != null) request.fields['district'] = district;

      if (removeAvatar) {
        request.fields['removeAvatar'] = 'true';
      } else if (avatarFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('avatar', avatarFile.path),
        );
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        return jsonDecode(responseBody) as Map<String, dynamic>;
      }
      throw Exception('Profil güncellenemedi: $responseBody');
    } catch (e) {
      throw Exception('Bağlantı hatası: $e');
    }
  }

  Future<Map<String, dynamic>> getMyListings({int page = 1, int limit = 10}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/my-listings?page=$page&limit=$limit'),
      headers: await _getHeaders(needsAuth: true),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('İlanlar getirilemedi: ${response.body}');
  }

  // Location
  Future<List<dynamic>> getCities() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/locations/cities'), headers: await _getHeaders()).timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<dynamic>> getDistricts(String tkgmId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/locations/districts/$tkgmId'), headers: await _getHeaders()).timeout(timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Favorites
  Future<List<dynamic>> getFavorites() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/favorites'),
      headers: await _getHeaders(needsAuth: true),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> toggleFavorite(String listingId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/favorites/$listingId'),
      headers: await _getHeaders(needsAuth: true),
    );
    return jsonDecode(response.body);
  }

  Future<void> submitSupportRequest({
    required String category,
    required String subject,
    required String message,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/support'),
      headers: await _getHeaders(needsAuth: true),
      body: jsonEncode({
        'category': category,
        'subject': subject,
        'message': message,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Destek talebi gonderilemedi: ${response.body}');
    }
  }

  // Notifications
  Future<Map<String, dynamic>> getNotifications({int page = 1, int limit = 20}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications?page=$page&limit=$limit'),
      headers: await _getHeaders(needsAuth: true),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Bildirimler getirilemedi: ${response.body}');
    }
  }

  Future<int> getUnreadNotificationCount() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/notifications/unread-count'),
        headers: await _getHeaders(needsAuth: true),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    await http.put(
      Uri.parse('$baseUrl/notifications/$notificationId/read'),
      headers: await _getHeaders(needsAuth: true),
    );
  }

  Future<void> markAllNotificationsAsRead() async {
    await http.put(
      Uri.parse('$baseUrl/notifications/mark-all-read'),
      headers: await _getHeaders(needsAuth: true),
    );
  }

  Future<void> deleteNotification(String notificationId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/notifications/$notificationId'),
      headers: await _getHeaders(needsAuth: true),
    );
    if (response.statusCode != 200) {
      throw Exception('Bildirim silinemedi: ${response.body}');
    }
  }

  // Account deletion
  Future<void> deleteAccount({required String password}) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/auth/delete-account'),
        headers: await _getHeaders(needsAuth: true),
        body: jsonEncode({'password': password}),
      ).timeout(timeout);

      if (response.statusCode == 200) return;

      String errorMessage = 'Hesap silinemedi';
      try {
        final error = jsonDecode(response.body);
        if (error['message'] != null) {
          errorMessage = error['message'];
        }
      } catch (_) {}

      throw Exception(errorMessage);
    } on SocketException {
      throw Exception('İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.');
    } on TimeoutException {
      throw Exception('Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.');
    } on FormatException {
      throw Exception('Sunucudan geçersiz yanıt alındı.');
    } catch (e) {
      throw Exception('Bağlantı hatası: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }
}


