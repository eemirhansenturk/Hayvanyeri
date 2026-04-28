import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/fcm_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  bool _isAuthenticated = false;
  String? _token;
  Map<String, dynamic>? _user;

  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get user => _user;
  
  // Favori kontrolü için helper method
  bool isFavorite(String listingId) {
    if (_user == null || _user!['favorites'] == null) return false;
    return (_user!['favorites'] as List).contains(listingId);
  }
  
  // Favori toggle için method
  Future<void> toggleFavorite(String listingId) async {
    try {
      await _apiService.toggleFavorite(listingId);
      
      // Local state'i güncelle
      if (_user != null) {
        if (_user!['favorites'] == null) {
          _user!['favorites'] = [];
        }
        final favorites = _user!['favorites'] as List;
        if (favorites.contains(listingId)) {
          favorites.remove(listingId);
        } else {
          favorites.add(listingId);
        }
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }
  
  // Profil bilgisini yenile
  Future<void> refreshProfile() async {
    try {
      _user = await _apiService.getProfile();
      notifyListeners();
    } catch (e) {
      // Hata durumunda sessizce devam et
    }
  }

  Future<void> checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _isAuthenticated = _token != null;
    if (_isAuthenticated) {
      try {
        _user = await _apiService.getProfile();
        // Socket başlat
        final usrId = _user?['_id'] ?? _user?['id'];
        if (usrId != null) {
          SocketService().init(usrId.toString());
          try {
            await _apiService.markMessagesAsDelivered();
            if (!kIsWeb) await FCMService().registerDevice();
          } catch (_) {}
        }
      } catch (e) {
        await logout();
      }
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await _apiService.login(email, password);
      if (response['token'] != null) {
        _token = response['token'];
        _user = response['user'];
        _isAuthenticated = true;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _token!);
        
        final usrId = _user?['_id'] ?? _user?['id'];
        if (usrId != null) {
          SocketService().init(usrId.toString());
          try {
            await _apiService.markMessagesAsDelivered();
            if (!kIsWeb) await FCMService().registerDevice();
          } catch (_) {}
        }

        notifyListeners();
        return {'success': true};
      }
      return {'success': false, 'message': 'Token alınamadı'};
    } catch (e) {
      print('Login error: $e'); // Debug için
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    try {
      final response = await _apiService.register(data);
      if (response['token'] != null) {
        _token = response['token'];
        _user = response['user'];
        _isAuthenticated = true;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _token!);
        
        final usrId = _user?['_id'] ?? _user?['id'];
        if (usrId != null) {
          SocketService().init(usrId.toString());
          try {
            await _apiService.markMessagesAsDelivered();
            if (!kIsWeb) await FCMService().registerDevice();
          } catch (_) {}
        }

        notifyListeners();
        return {'success': true};
      }
      return {'success': false, 'message': 'Token alınamadı'};
    } catch (e) {
      print('Register error: $e'); // Debug için
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> sendVerificationCode(Map<String, dynamic> data) async {
    try {
      final response = await _apiService.sendVerificationCode(data);
      return response;
    } catch (e) {
      print('Send verification error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> verifyCode(Map<String, dynamic> data) async {
    try {
      final response = await _apiService.verifyCode(data);
      if (response['token'] != null) {
        _token = response['token'];
        _user = response['user'];
        _isAuthenticated = true;
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _token!);
        
        final usrId = _user?['_id'] ?? _user?['id'];
        if (usrId != null) {
          SocketService().init(usrId.toString());
          try {
            await _apiService.markMessagesAsDelivered();
            if (!kIsWeb) await FCMService().registerDevice();
          } catch (_) {}
        }

        notifyListeners();
        return {'success': true};
      }
      return {'success': false, 'message': 'Token alınamadı'};
    } catch (e) {
      print('Verify code error: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<void> logout() async {
    SocketService().disconnect();
    
    _token = null;
    _user = null;
    _isAuthenticated = false;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    
    notifyListeners();
  }
}
